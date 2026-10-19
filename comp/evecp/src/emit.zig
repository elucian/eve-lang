//! @eve-module emit
//! @spec design/design-bytecode.md#9-stages
//! @feature F-VM-04
//! @decision D-201
//! @tests test/level1 with `--engine bc`, comp/evecp/src/emit.zig (unit tests)
//! The emitter: turns the checked syntax tree of an aspect into a `Chunk` of the register machine. Stage B5.2 handles
//! the core of level 1 (numbers, text, variables, operators, `print`, `write`, `expect`, `if`, `while`, `for` over
//! integer ranges, functions and procedures with positional arguments); any other construct stops the compilation with
//! the line and the name of the construct, so a program is never run half translated.
const std = @import("std");
const evecm = @import("evecm");
const ast = evecm.ast;
const chunk = evecm.chunk;
const Inst = evecm.op.Inst;
const Op = evecm.op.Op;
const Node = ast.Node;
const Alloc = std.mem.Allocator;

pub const Error = error{ Unsupported, OutOfMemory };

/// Why the compilation stopped.
pub const Diag = struct { message: []const u8 = "", line: u32 = 0 };

const Local = struct { name: []const u8, reg: u8 };

const Loop = struct {
    /// Jumps to patch to the end of the loop (`break`) and to the next pass (`skip`): positions in `code`.
    breaks: std.ArrayList(u32) = .empty,
    skips: std.ArrayList(u32) = .empty,
};

const Emitter = struct {
    a: Alloc,
    diag: *Diag,
    consts: std.ArrayList(chunk.Const) = .empty,
    funcs: std.ArrayList(chunk.Func) = .empty,
    code: std.ArrayList(u32) = .empty,
    lines: std.ArrayList(u32) = .empty,
    /// The function and procedure nodes of the aspect, by name; the index in `funcs` is the position + 1.
    routines: std.ArrayList(*const Node) = .empty,

    // the function being compiled
    locals: std.ArrayList(Local) = .empty,
    free: u8 = 0,
    max_regs: u8 = 0,
    start: u32 = 0,
    in_process: bool = false,
    result_reg: u8 = chunk.no_result,
    loops: std.ArrayList(Loop) = .empty,

    fn unsupported(e: *Emitter, n: *const Node, what: []const u8) Error {
        e.diag.message = what;
        e.diag.line = n.line;
        return error.Unsupported;
    }

    fn emit(e: *Emitter, i: Inst, line: u32) Error!u32 {
        try e.code.append(e.a, i.word());
        try e.lines.append(e.a, line);
        return @intCast(e.code.items.len - 1);
    }

    /// The position in the code of the function being compiled.
    fn here(e: *Emitter) u32 {
        return @intCast(e.code.items.len - e.start);
    }

    /// Make the jump at `at` (a position in `code`) land on `target` (a position relative to the function).
    fn patch(e: *Emitter, at: u32, target: u32) void {
        var i = Inst.fromWord(e.code.items[at]);
        const rel: i32 = @as(i32, @intCast(target)) - @as(i32, @intCast(at - e.start)) - 1;
        i = Inst.asbx(i.op, i.a, @intCast(rel));
        e.code.items[at] = i.word();
    }

    fn alloc(e: *Emitter, n: *const Node) Error!u8 {
        if (e.free == 250) return e.unsupported(n, "a function needs more than 250 registers");
        const r = e.free;
        e.free += 1;
        if (e.free > e.max_regs) e.max_regs = e.free;
        return r;
    }

    fn konst(e: *Emitter, c: chunk.Const) Error!u16 {
        for (e.consts.items, 0..) |k, i| {
            switch (k) {
                .int => |v| if (c == .int and c.int == v) return @intCast(i),
                .real => |v| if (c == .real and @as(u64, @bitCast(c.real)) == @as(u64, @bitCast(v))) return @intCast(i),
                .str => |v| if (c == .str and std.mem.eql(u8, v, c.str)) return @intCast(i),
            }
        }
        try e.consts.append(e.a, c);
        return @intCast(e.consts.items.len - 1);
    }

    fn find(e: *Emitter, name: []const u8) ?u8 {
        var i = e.locals.items.len;
        while (i > 0) : (i -= 1) {
            if (std.mem.eql(u8, e.locals.items[i - 1].name, name)) return e.locals.items[i - 1].reg;
        }
        return null;
    }

    /// The first register above every local variable: where the temporaries of the next statement start.
    fn floor(e: *Emitter) u8 {
        var m: u8 = 0;
        for (e.locals.items) |l| m = @max(m, l.reg + 1);
        return m;
    }

    fn routineIndex(e: *Emitter, name: []const u8) ?u8 {
        for (e.routines.items, 0..) |r, i| if (std.mem.eql(u8, r.text, name)) return @intCast(i + 1);
        return null;
    }

    // ---- expressions ---------------------------------------------------------------------

    /// Evaluate `n` into register `dst`.
    fn exprTo(e: *Emitter, n: *const Node, dst: u8) Error!void {
        const line = n.line;
        switch (n.tag) {
            .num => switch (n.lit_kind) {
                .int => {
                    const v: i64 = @bitCast(n.lit_bits);
                    if (v >= -32768 and v <= 32767) {
                        _ = try e.emit(Inst.asbx(.loadi, dst, @intCast(v)), line);
                    } else _ = try e.emit(Inst.abx(.loadk, dst, try e.konst(.{ .int = v })), line);
                },
                .real => _ = try e.emit(Inst.abx(.loadk, dst, try e.konst(.{ .real = @bitCast(n.lit_bits) })), line),
                .none => return e.unsupported(n, "a number with a suffix, a comma or a base"),
            },
            .str => _ = try e.emit(Inst.abx(.loadk, dst, try e.konst(.{ .str = n.text })), line),
            .name => {
                if (e.find(n.text)) |r| {
                    if (r != dst) _ = try e.emit(Inst.abc(.move, dst, r, 0), line);
                } else if (std.mem.eql(u8, n.text, "True")) {
                    _ = try e.emit(Inst.abc(.loadtrue, dst, 0, 0), line);
                } else if (std.mem.eql(u8, n.text, "False")) {
                    _ = try e.emit(Inst.abc(.loadfalse, dst, 0, 0), line);
                } else if (std.mem.eql(u8, n.text, "null")) {
                    _ = try e.emit(Inst.abc(.loadnil, dst, 0, 0), line);
                } else return e.unsupported(n, "a name that is not a local variable of the function");
            },
            .bin => try e.binary(n, dst),
            .un => {
                const src = try e.operand(n.kids[0]);
                if (std.mem.eql(u8, n.text, "-")) {
                    _ = try e.emit(Inst.abc(.neg, dst, src, 0), line);
                } else if (std.mem.eql(u8, n.text, "not")) {
                    _ = try e.emit(Inst.abc(.not, dst, src, 0), line);
                } else return e.unsupported(n, "this unary operator");
            },
            .call => try e.call(n, dst),
            else => return e.unsupported(n, @tagName(n.tag)),
        }
    }

    /// A register that holds the value of `n`: the register of a local variable, or a new temporary.
    fn operand(e: *Emitter, n: *const Node) Error!u8 {
        if (n.tag == .name) if (e.find(n.text)) |r| return r;
        const t = try e.alloc(n);
        try e.exprTo(n, t);
        return t;
    }

    fn binary(e: *Emitter, n: *const Node, dst: u8) Error!void {
        const line = n.line;
        const mark = e.free;
        defer e.free = mark;
        if (std.mem.eql(u8, n.text, "and") or std.mem.eql(u8, n.text, "or")) {
            // short circuit: the left value decides, as a Logic
            // a temporary holds the value: `dst` may be a variable that the right side reads
            const is_and = n.text[0] == 'a';
            const t = try e.alloc(n);
            try e.exprTo(n.kids[0], t);
            const j = try e.emit(Inst.asbx(if (is_and) .jf else .jt, t, 0), line);
            try e.exprTo(n.kids[1], t);
            e.patch(j, e.here());
            _ = try e.emit(Inst.abc(.move, dst, t, 0), line);
            return;
        }
        const op: Op = switch (n.op) {
            .add => .add,
            .sub => .sub,
            .mul => .mul,
            .div => .div,
            .mod => .mod,
            .eq => .eq,
            .ne => .ne,
            .lt => .lt,
            .le => .le,
            .gt => .gt,
            .ge => .ge,
            else => return e.unsupported(n, "this binary operator"),
        };
        const l = try e.operand(n.kids[0]);
        const r = try e.operand(n.kids[1]);
        _ = try e.emit(Inst.abc(op, dst, l, r), line);
    }

    fn call(e: *Emitter, n: *const Node, dst: u8) Error!void {
        const callee = n.kids[0];
        if (callee.tag != .name) return e.unsupported(n, "a call of something that is not a function name");
        const fi = e.routineIndex(callee.text) orelse return e.unsupported(n, "a call of a name that is not a function of the aspect");
        const target = e.routines.items[fi - 1];
        const args = n.kids[1..];
        const params = target.kids[0].kids;
        if (args.len != params.len) return e.unsupported(n, "a call with default or named arguments");
        const mark = e.free;
        defer e.free = mark;
        const base = try e.alloc(n);
        for (args) |a| {
            if (a.tag == .pair or a.tag == .ref or a.tag == .spread) return e.unsupported(a, "a named, reference or spread argument");
            const slot = try e.alloc(a);
            try e.exprTo(a, slot);
        }
        _ = try e.emit(Inst.abc(.callf, base, @intCast(args.len), fi), n.line);
        if (base != dst) _ = try e.emit(Inst.abc(.move, dst, base, 0), n.line);
    }

    // ---- statements ----------------------------------------------------------------------

    fn block(e: *Emitter, b: *const Node) Error!void {
        for (b.kids) |s| try e.statement(s);
    }

    fn declare(e: *Emitter, n: *const Node, name: []const u8) Error!u8 {
        if (e.find(name)) |r| return r;
        const r = try e.alloc(n);
        try e.locals.append(e.a, .{ .name = name, .reg = r });
        return r;
    }

    fn statement(e: *Emitter, n: *const Node) Error!void {
        const line = n.line;
        const mark = e.free;
        switch (n.tag) {
            .var_decl, .set => {
                if (n.ty != null or n.kids.len != 2 or n.kids[0].kids.len != 1 or !(std.mem.eql(u8, n.text, ":=") or std.mem.eql(u8, n.text, "="))) return e.unsupported(n, "a typed or multiple declaration");
                const t = n.kids[0].kids[0];
                if (t.tag != .name) return e.unsupported(n, "a declaration of something that is not a name");
                // the value is computed before the name exists, as in the tree walker
                const tmp = try e.alloc(n);
                try e.exprTo(n.kids[1], tmp);
                e.free = mark;
                const r = try e.declare(n, t.text);
                if (r != tmp) _ = try e.emit(Inst.abc(.move, r, tmp, 0), line);
            },
            .assign => try e.assign(n),
            .print_stmt, .write_stmt => try e.printStmt(n),
            .expect_stmt => {
                const r = try e.operand(n.kids[0]);
                _ = try e.emit(Inst.abc(.expect, r, 0, 0), line);
            },
            .if_ => try e.ifStmt(n),
            .while_ => try e.whileStmt(n),
            .for_ => try e.forStmt(n),
            .cond_stmt => {
                const c = try e.operand(n.kids[0]);
                const j = try e.emit(Inst.asbx(.jf, c, 0), line);
                e.free = mark;
                try e.statement(n.kids[1]);
                e.patch(j, e.here());
            },
            .expr_stmt => {
                const x = n.kids[0];
                if (x.tag != .call) return e.unsupported(n, "an expression that is not a call, as a statement");
                const t = try e.alloc(n);
                try e.call(x, t);
            },
            .break_stmt, .skip_stmt => {
                if (e.loops.items.len == 0 or n.text.len > 0) return e.unsupported(n, "break or skip with a label, or outside a loop");
                const j = try e.emit(Inst.asbx(.jmp, 0, 0), line);
                const lp = &e.loops.items[e.loops.items.len - 1];
                if (n.tag == .break_stmt) try lp.breaks.append(e.a, j) else try lp.skips.append(e.a, j);
            },
            .over_stmt => {
                if (n.kids.len > 0) return e.unsupported(n, "over with an exit code");
                _ = try e.emit(Inst.abc(.over, 0, 0, 0), line);
            },
            .exit_stmt => {
                if (n.kids.len > 0) return e.unsupported(n, "exit with an exit code");
                if (e.in_process) {
                    _ = try e.emit(Inst.abc(.halt, 0, 0, 0), line);
                } else _ = try e.emit(Inst.abc(.ret, e.result_reg, if (e.result_reg == chunk.no_result) 0 else 1, 0), line);
            },
            .pass_stmt => {},
            else => return e.unsupported(n, @tagName(n.tag)),
        }
        e.free = e.floor();
    }

    fn assign(e: *Emitter, n: *const Node) Error!void {
        const line = n.line;
        const target = n.kids[0];
        if (target.tag != .name) return e.unsupported(n, "an assignment to something that is not a variable");
        const reg = e.find(target.text) orelse return e.unsupported(n, "an assignment to a name that is not a local variable");
        const op: Op = switch (n.op) {
            .set => {
                // `let x := x + 1`: the new value may read x, so it is computed in place only when it does not
                try e.exprTo(n.kids[1], reg);
                return;
            },
            .add => .add,
            .sub => .sub,
            .mul => .mul,
            .div => .div,
            .mod => .mod,
            else => return e.unsupported(n, "this assignment operator"),
        };
        const v = try e.operand(n.kids[1]);
        _ = try e.emit(Inst.abc(op, reg, reg, v), line);
    }

    fn printStmt(e: *Emitter, n: *const Node) Error!void {
        const line = n.line;
        const newline: u8 = if (n.tag == .print_stmt) 1 else 0;
        if (n.kids.len == 0) {
            _ = try e.emit(Inst.abc(.print, e.free, 0, newline), line);
            return;
        }
        const arg = n.kids[0];
        const base = e.free;
        if (arg.tag == .list) {
            for (arg.kids) |k| {
                if (k.tag == .pair) return e.unsupported(k, "print with sep:");
                const slot = try e.alloc(k);
                try e.exprTo(k, slot);
            }
            _ = try e.emit(Inst.abc(.print, base, @intCast(arg.kids.len), newline), line);
        } else {
            const slot = try e.alloc(arg);
            try e.exprTo(arg, slot);
            _ = try e.emit(Inst.abc(.print, base, 1, newline), line);
        }
    }

    fn ifStmt(e: *Emitter, n: *const Node) Error!void {
        var ends: std.ArrayList(u32) = .empty;
        var i: usize = 0;
        while (i + 1 < n.kids.len) : (i += 2) {
            const mark = e.free;
            const c = try e.operand(n.kids[i]);
            const j = try e.emit(Inst.asbx(.jf, c, 0), n.kids[i].line);
            e.free = mark;
            try e.block(n.kids[i + 1]);
            const last = i + 2 >= n.kids.len;
            if (!last) try ends.append(e.a, try e.emit(Inst.asbx(.jmp, 0, 0), n.line));
            e.patch(j, e.here());
        }
        if (n.kids.len % 2 == 1) try e.block(n.kids[n.kids.len - 1]);
        for (ends.items) |j| e.patch(j, e.here());
    }

    fn enterLoop(e: *Emitter) Error!void {
        try e.loops.append(e.a, .{});
    }

    fn whileStmt(e: *Emitter, n: *const Node) Error!void {
        if (n.kids[0].kids.len > 0 or n.kids[3].kids.len > 0) return e.unsupported(n, "a while with a block before the test or an else block");
        const saved_locals = e.locals.items.len;
        const mark = e.free;
        try e.enterLoop();
        const top = e.here();
        const c = try e.operand(n.kids[1]);
        const exit = try e.emit(Inst.asbx(.jf, c, 0), n.line);
        e.free = mark;
        try e.block(n.kids[2]);
        const back = try e.emit(Inst.asbx(.jmp, 0, 0), n.line);
        e.patch(back, top);
        var lp = e.loops.pop().?;
        for (lp.skips.items) |j| e.patch(j, top);
        const end = e.here();
        e.patch(exit, end);
        for (lp.breaks.items) |j| e.patch(j, end);
        lp.breaks.deinit(e.a);
        lp.skips.deinit(e.a);
        e.locals.shrinkRetainingCapacity(saved_locals);
        e.free = e.floor();
        try e.block(n.kids[4]);
    }

    fn forStmt(e: *Emitter, n: *const Node) Error!void {
        const range = n.kids[1];
        if (n.kids[0].tag != .name or range.tag != .range or !std.mem.eql(u8, range.text, "..")) {
            return e.unsupported(n, "a for loop that is not over a range of integers a..b");
        }
        const saved_locals = e.locals.items.len;
        const base = try e.alloc(n);
        const limit = try e.alloc(n);
        const user = try e.alloc(n);
        std.debug.assert(limit == base + 1 and user == base + 2);
        try e.exprTo(range.kids[0], base);
        try e.exprTo(range.kids[1], limit);
        try e.locals.append(e.a, .{ .name = n.kids[0].text, .reg = user });
        try e.enterLoop();
        const prep = try e.emit(Inst.asbx(.forprep, base, 0), n.line);
        const body = e.here();
        try e.block(n.kids[2]);
        var lp = e.loops.pop().?;
        const cont = e.here();
        for (lp.skips.items) |j| e.patch(j, cont);
        const back = try e.emit(Inst.asbx(.forloop, base, 0), n.line);
        e.patch(back, body);
        // an empty range runs the else block; a break goes past it
        var skip_else: ?u32 = null;
        if (n.kids[3].kids.len > 0) skip_else = try e.emit(Inst.asbx(.jmp, 0, 0), n.line);
        e.patch(prep, e.here());
        try e.block(n.kids[3]);
        const end = e.here();
        if (skip_else) |j| e.patch(j, end);
        for (lp.breaks.items) |j| e.patch(j, end);
        lp.breaks.deinit(e.a);
        lp.skips.deinit(e.a);
        e.locals.shrinkRetainingCapacity(saved_locals);
        e.free = e.floor();
        try e.block(n.kids[4]);
    }

    // ---- functions -----------------------------------------------------------------------

    /// Compile a function, a procedure or the process `main`.
    fn function(e: *Emitter, n: *const Node) Error!void {
        e.locals.clearRetainingCapacity();
        e.free = 0;
        e.max_regs = 0;
        e.start = @intCast(e.code.items.len);
        e.in_process = n.tag == .process;
        e.result_reg = chunk.no_result;
        e.loops.clearRetainingCapacity();
        var nparams: u8 = 0;
        var body: *const Node = undefined;
        if (n.tag == .process) {
            if (n.kids[1].tag != .none or n.kids[2].tag != .none) return e.unsupported(n, "a process with recover or finalize");
            if (n.kids[3].kids.len > 0) return e.unsupported(n, "a process with parameters");
            body = n.kids[0];
        } else {
            if (n.kids.len > 4) return e.unsupported(n, "a routine with recover");
            if (n.kids[1].kids.len > 0) return e.unsupported(n, "a routine with a type list");
            for (n.kids[0].kids) |p| {
                if (p.tag != .param or p.kids[0].tag != .none) return e.unsupported(p, "a parameter that is not plain");
                _ = try e.declare(p, p.text);
                nparams += 1;
            }
            const results = n.kids[2].kids;
            if (results.len > 1) return e.unsupported(n, "a routine with several results");
            if (results.len == 1) {
                const r = results[0];
                const reg = try e.declare(r, r.text);
                e.result_reg = reg;
                const zero_line = r.line;
                switch (if (r.ty) |t| t.tk else ast.TypeKind.none) {
                    .integer, .short, .byte => _ = try e.emit(Inst.asbx(.loadi, reg, 0), zero_line),
                    .real, .float => _ = try e.emit(Inst.abx(.loadk, reg, try e.konst(.{ .real = 0 })), zero_line),
                    .logic => _ = try e.emit(Inst.abc(.loadfalse, reg, 0, 0), zero_line),
                    .string => _ = try e.emit(Inst.abx(.loadk, reg, try e.konst(.{ .str = "" })), zero_line),
                    else => return e.unsupported(r, "a result of this type"),
                }
            }
            body = n.kids[3];
        }
        try e.block(body);
        if (e.in_process) {
            _ = try e.emit(Inst.abc(.halt, 0, 0, 0), n.line);
        } else _ = try e.emit(Inst.abc(.ret, e.result_reg, if (e.result_reg == chunk.no_result) 0 else 1, 0), n.line);
        try e.funcs.append(e.a, .{
            .name = n.text,
            .kind = @tagName(n.tag),
            .nparams = nparams,
            .nregs = e.max_regs,
            .result = e.result_reg,
            .start = e.start,
            .len = @intCast(e.code.items.len - e.start),
            .line = n.line,
        });
    }
};

// @eve-impl compile an aspect to a chunk; function 0 is `process main`, the others follow in the order of the source
// @spec design/design-bytecode.md#9-stages
// @feature F-VM-04
/// Compile the aspect `root`. On `error.Unsupported` the `diag` says which construct and where.
pub fn compile(a: Alloc, root: *const Node, diag: *Diag) Error!chunk.Chunk {
    var e: Emitter = .{ .a = a, .diag = diag };
    if (root.tag != .aspect) {
        diag.message = "the program is not a single aspect";
        diag.line = root.line;
        return error.Unsupported;
    }
    var main: ?*const Node = null;
    for (root.kids) |k| switch (k.tag) {
        .function, .procedure => try e.routines.append(a, k),
        .process => if (std.mem.eql(u8, k.text, "main")) {
            main = k;
        } else return e.unsupported(k, "a process other than main"),
        .none, .params => {},
        else => return e.unsupported(k, @tagName(k.tag)),
    };
    const m = main orelse return e.unsupported(root, "an aspect without process main");
    try e.function(m);
    for (e.routines.items) |r| try e.function(r);
    return .{
        .consts = e.consts.items,
        .funcs = e.funcs.items,
        .code = e.code.items,
        .lines = e.lines.items,
        .main = 0,
    };
}
