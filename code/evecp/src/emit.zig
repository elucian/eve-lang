//! @eve-module emit
//! @spec design/design-bytecode.md#9-stages
//! @feature F-VM-04
//! @decision D-201
//! @tests test/level1 with `--engine bc`, code/evecp/src/emit.zig (unit tests)
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
    /// For each routine: does it have a native translation (else the tree walker runs it)? And its index in `funcs`.
    native: []bool = &.{},
    fidx: []u8 = &.{},
    xnodes: std.ArrayList(chunk.XNode) = .empty,

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
        for (e.routines.items, 0..) |r, i| if (std.mem.eql(u8, r.text, name)) {
            if (e.native.len == 0) return @intCast(i + 1); // a trial compilation: every routine counts as native
            return if (e.native[i]) e.fidx[i] else null;
        };
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
                .none => try e.bridgeExpr(n, dst),
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
                } else _ = try e.emit(Inst.abx(.loadg, dst, try e.konst(.{ .str = n.text })), line);
            },
            .list, .array => {
                for (n.kids) |k| if (k.tag == .pair or k.tag == .star or k.tag == .spread) return e.bridgeExpr(n, dst);
                const mark = e.free;
                defer e.free = mark;
                _ = try e.emit(Inst.abc(.new_list, dst, if (n.tag == .array) 1 else 0, 0), line);
                for (n.kids) |k| {
                    const slot = try e.alloc(k);
                    try e.exprTo(k, slot);
                    _ = try e.emit(Inst.abc(.list_push, dst, slot, 0), line);
                    e.free = mark;
                }
            },
            .brace => {
                const is_map = std.mem.eql(u8, n.text, "map");
                if (!is_map and !std.mem.eql(u8, n.text, "set")) return e.bridgeExpr(n, dst);
                for (n.kids) |k| if ((k.tag == .pair) != is_map or k.tag == .star or k.tag == .spread) return e.bridgeExpr(n, dst);
                const mark = e.free;
                defer e.free = mark;
                _ = try e.emit(Inst.abc(if (is_map) .new_map else .new_set, dst, 0, 0), line);
                for (n.kids) |k| {
                    if (is_map) {
                        const key = try e.alloc(k);
                        try e.exprTo(k.kids[0], key);
                        const val = try e.alloc(k);
                        try e.exprTo(k.kids[1], val);
                        _ = try e.emit(Inst.abc(.map_set, dst, key, val), line);
                    } else {
                        const slot = try e.alloc(k);
                        try e.exprTo(k, slot);
                        _ = try e.emit(Inst.abc(.set_add, dst, slot, 0), line);
                    }
                    e.free = mark;
                }
            },
            .index => {
                if (!plainIndex(n)) return e.bridgeExpr(n, dst);
                const mark = e.free;
                defer e.free = mark;
                const obj = try e.operand(n.kids[0]);
                const key = try e.operand(n.kids[1]);
                _ = try e.emit(Inst.abc(.index, dst, obj, key), line);
                try e.xref(n);
            },
            .interp => {
                if (n.kids.len > 200) return e.bridgeExpr(n, dst);
                const mark = e.free;
                defer e.free = mark;
                const base = e.free;
                for (n.kids) |part| {
                    const slot = try e.alloc(part);
                    if (part.tag != .str) try e.exprTo(part.kids[0], slot);
                }
                _ = try e.emit(Inst.abc(.interp, dst, base, 0), line);
                try e.xrefNode(n);
            },
            .bin => try e.binary(n, dst),
            .un => {
                if (!std.mem.eql(u8, n.text, "-") and !std.mem.eql(u8, n.text, "not")) return e.bridgeExpr(n, dst);
                const src = try e.operand(n.kids[0]);
                _ = try e.emit(Inst.abc(if (n.text[0] == '-') .neg else .not, dst, src, 0), line);
            },
            .call => try e.call(n, dst),
            else => try e.bridgeExpr(n, dst),
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
            else => {
                // every other operator goes through `apply` with its text, except the forms that read their operands specially
                if (std.mem.eql(u8, n.text, "=~") and n.kids[1].tag == .range) return e.bridgeExpr(n, dst);
                const l = try e.operand(n.kids[0]);
                const r = try e.operand(n.kids[1]);
                _ = try e.emit(Inst.abc(.binx, dst, l, r), line);
                _ = try e.emit(Inst.abx(.extra, 0, try e.konst(.{ .str = n.text })), line);
                return;
            },
        };
        const l = try e.operand(n.kids[0]);
        const r = try e.operand(n.kids[1]);
        _ = try e.emit(Inst.abc(op, dst, l, r), line);
    }

    fn call(e: *Emitter, n: *const Node, dst: u8) Error!void {
        const callee = n.kids[0];
        if (callee.tag == .field and n.kids.len == 1 and (std.mem.eql(u8, callee.text, "count") or std.mem.eql(u8, callee.text, "length"))) {
            const mark = e.free;
            defer e.free = mark;
            const obj = try e.operand(callee.kids[0]);
            _ = try e.emit(Inst.abc(.length, dst, obj, 0), n.line);
            return e.xref(n);
        }
        if (callee.tag != .name or e.find(callee.text) != null) return e.bridgeExpr(n, dst);
        const fi = e.routineIndex(callee.text) orelse return e.bridgeExpr(n, dst);
        const target = e.routineNode(callee.text).?;
        const args = n.kids[1..];
        const params = target.kids[0].kids;
        if (args.len != params.len) return e.bridgeExpr(n, dst);
        for (args) |a| if (a.tag == .pair or a.tag == .ref or a.tag == .spread) return e.bridgeExpr(n, dst);
        const mark = e.free;
        defer e.free = mark;
        const base = try e.alloc(n);
        for (args) |a| {
            const slot = try e.alloc(a);
            try e.exprTo(a, slot);
        }
        _ = try e.emit(Inst.abc(.callf, base, @intCast(args.len), fi), n.line);
        if (base != dst) _ = try e.emit(Inst.abc(.move, dst, base, 0), n.line);
    }

    // ---- the bridge to the tree walker -----------------------------------------------------

    fn routineNode(e: *Emitter, name: []const u8) ?*const Node {
        for (e.routines.items) |r| if (std.mem.eql(u8, r.text, name)) return r;
        return null;
    }

    /// The local variables that `n` names, with their registers, added to `list`.
    fn collectNames(e: *Emitter, n: *const Node, list: *std.ArrayList(chunk.NameReg)) Error!void {
        if ((n.tag == .name or n.tag == .ref or (n.tag == .star and n.text.len > 0)) and !std.mem.eql(u8, n.text, "_")) {
            if (e.find(n.text)) |r| {
                for (list.items) |x| if (std.mem.eql(u8, x.name, n.text)) return;
                try list.append(e.a, .{ .name = n.text, .reg = r });
            }
        }
        for (n.kids) |k| try e.collectNames(k, list);
        for (n.extra) |k| try e.collectNames(k, list);
    }

    /// Does the subtree hold something the bridge can not carry: a jump out of the statement, a closure over the variables, a task?
    fn cannotBridge(n: *const Node) bool {
        switch (n.tag) {
            .break_stmt, .skip_stmt, .over_stmt, .exit_stmt, .stop_stmt, .retry_stmt, .resume_stmt, .abort_stmt, .lambda, .await_, .start_stmt, .spawn_stmt, .job, .parallel, .yield_stmt, .defer_stmt, .commit_stmt, .rollback_stmt, .panic_stmt => return true,
            else => {},
        }
        for (n.kids) |k| if (cannotBridge(k)) return true;
        for (n.extra) |k| if (cannotBridge(k)) return true;
        return false;
    }

    // @eve-impl the second word of an instruction with a fast case: the tree walker runs `n` when the fast case does not apply
    // @spec design/design-bytecode.md#9-stages
    // @test test/bytecode
    fn xref(e: *Emitter, n: *const Node) Error!void {
        if (cannotBridge(n)) return e.unsupported(n, @tagName(n.tag));
        var names: std.ArrayList(chunk.NameReg) = .empty;
        try e.collectNames(n, &names);
        try e.xnodes.append(e.a, .{ .node = n, .names = names.items });
        _ = try e.emit(Inst.abx(.xref, 0, @intCast(e.xnodes.items.len - 1)), n.line);
    }

    /// An `xref` word that carries a node the machine only reads (the parts of an interpolation) or never runs.
    fn xrefNode(e: *Emitter, n: *const Node) Error!void {
        try e.xnodes.append(e.a, .{ .node = n, .names = &.{} });
        _ = try e.emit(Inst.abx(.xref, 0, @intCast(e.xnodes.items.len - 1)), n.line);
    }

    /// Does `n` use `$`, `*` or a range as an index, which only the tree walker knows?
    fn specialIndex(n: *const Node) bool {
        switch (n.tag) {
            .dollar, .all, .range, .pair, .star, .spread => return true,
            else => {},
        }
        for (n.kids) |k| if (specialIndex(k)) return true;
        return false;
    }

    /// `obj[i]` with one plain index on an object that is not itself indexed.
    fn plainIndex(n: *const Node) bool {
        return n.tag == .index and n.kids.len == 2 and n.kids[0].tag != .index and !specialIndex(n.kids[1]);
    }

    fn bridgeExpr(e: *Emitter, n: *const Node, dst: u8) Error!void {
        if (cannotBridge(n)) return e.unsupported(n, @tagName(n.tag));
        var names: std.ArrayList(chunk.NameReg) = .empty;
        try e.collectNames(n, &names);
        try e.xnodes.append(e.a, .{ .node = n, .names = names.items });
        _ = try e.emit(Inst.abx(.evalx, dst, @intCast(e.xnodes.items.len - 1)), n.line);
    }

    /// A statement the tree walker runs: the variables it declares get registers, the ones it names are copied in and out.
    fn bridgeStmt(e: *Emitter, n: *const Node) Error!void {
        if (cannotBridge(n)) return e.unsupported(n, @tagName(n.tag));
        if (n.tag == .var_decl or n.tag == .set) {
            for (n.kids[0].kids) |t| if (t.tag == .name or t.tag == .star) {
                if (t.text.len > 0 and !std.mem.eql(u8, t.text, "_")) _ = try e.declare(n, t.text);
            };
        } else if (n.tag == .capture) {
            if (n.kids[1].tag == .name and !std.mem.eql(u8, n.kids[1].text, "_") and e.find(n.kids[1].text) == null) _ = try e.declare(n, n.kids[1].text);
        }
        var names: std.ArrayList(chunk.NameReg) = .empty;
        try e.collectNames(n, &names);
        try e.xnodes.append(e.a, .{ .node = n, .names = names.items });
        _ = try e.emit(Inst.abx(.execx, 0, @intCast(e.xnodes.items.len - 1)), n.line);
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
                const plain = n.kids.len == 2 and n.kids[0].kids.len == 1 and n.kids[0].kids[0].tag == .name and n.kids[1].tag != .none and
                    (std.mem.eql(u8, n.text, ":=") or std.mem.eql(u8, n.text, "=")) and (n.ty == null or n.ty.?.tk == .integer or n.ty.?.tk == .real or n.ty.?.tk == .string or n.ty.?.tk == .logic);
                if (!plain) return e.bridgeStmt(n);
                const t = n.kids[0].kids[0];
                // the value is computed before the name exists, as in the tree walker
                const tmp = try e.alloc(n);
                try e.exprTo(n.kids[1], tmp);
                e.free = mark;
                const r = try e.declare(n, t.text);
                if (r != tmp) _ = try e.emit(Inst.abc(.move, r, tmp, 0), line);
                // a declared type may convert the value: an Integer to a Real, a Real to an Integer (`coerce` of the tree walker)
                if (n.ty) |ty| if (ty.kids.len == 0 and (ty.tk == .real or ty.tk == .integer)) {
                    _ = try e.emit(Inst.abc(.coerce, r, @intFromEnum(ty.tk), 0), line);
                };
            },
            .block => try e.block(n), // the groups of declarations (`new x = 1, y = 2 :Integer;`) are not a scope
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
                if (x.tag != .call) return e.bridgeStmt(n);
                const callee = x.kids[0];
                if (callee.tag != .name or e.routineIndex(callee.text) == null) return e.bridgeStmt(n);
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
            else => return e.bridgeStmt(n),
        }
        e.free = e.floor();
    }

    fn assign(e: *Emitter, n: *const Node) Error!void {
        const line = n.line;
        const target = n.kids[0];
        if (target.tag == .index and n.op == .set and plainIndex(target)) {
            // the value first, as the tree walker does, then the object and the index
            const v = try e.operand(n.kids[1]);
            const obj = try e.operand(target.kids[0]);
            const key = try e.operand(target.kids[1]);
            _ = try e.emit(Inst.abc(.index_set, obj, key, v), line);
            return e.xref(n);
        }
        if (target.tag == .name and n.op == .push_back) if (e.find(target.text)) |reg| {
            const v = try e.operand(n.kids[1]);
            _ = try e.emit(Inst.abc(.push, reg, v, 0), line);
            return e.xref(n);
        };
        if (target.tag != .name) return e.bridgeStmt(n);
        const reg = e.find(target.text) orelse return e.bridgeStmt(n);
        const op: Op = switch (n.op) {
            .set => {
                // the new value is computed first (it may read the variable), then stored with the conversion of `:=`
                const t = try e.alloc(n);
                try e.exprTo(n.kids[1], t);
                _ = try e.emit(Inst.abc(.setlike, reg, t, 0), line);
                return;
            },
            .add => .add,
            .sub => .sub,
            .mul => .mul,
            .div => .div,
            .mod => .mod,
            else => return e.bridgeStmt(n),
        };
        const v = try e.operand(n.kids[1]);
        _ = try e.emit(Inst.abc(.augment, reg, v, @intFromEnum(op)), line);
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
                if (k.tag == .pair) return e.bridgeStmt(n);
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
        if (n.kids[0].kids.len > 0 or n.kids[3].kids.len > 0) return e.bridgeStmt(n);
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
        if (n.kids[0].tag == .name and range.tag != .range) return e.forEach(n);
        if (n.kids[0].tag != .name or range.tag != .range or !std.mem.eql(u8, range.text, "..")) return e.bridgeStmt(n);
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

    // @eve-impl `for x in collection`: a list, a map, a set or a string is visited by `iterprep` and `iterloop`; a range value, a channel,
    // a generator, a stream or a table runs the whole statement on the tree walker (only when it can be bridged)
    // @spec spec/semantics/control.md#loops
    // @test test/bytecode/bc03_loops
    fn forEach(e: *Emitter, n: *const Node) Error!void {
        const src = n.kids[1];
        const literal = src.tag == .list or src.tag == .array or src.tag == .str or (src.tag == .brace and !std.mem.eql(u8, src.text, "object"));
        if (cannotBridge(n) and !literal) return e.bridgeStmt(n);
        const saved_locals = e.locals.items.len;
        const base = try e.alloc(n);
        const pos = try e.alloc(n);
        const user = try e.alloc(n);
        std.debug.assert(pos == base + 1 and user == base + 2);
        try e.exprTo(src, base);
        try e.locals.append(e.a, .{ .name = n.kids[0].text, .reg = user });
        try e.enterLoop();
        const prep = try e.emit(Inst.asbx(.iterprep, base, 0), n.line);
        if (literal) try e.xrefNode(n) else try e.xref(n);
        const body = e.here();
        try e.block(n.kids[2]);
        var lp = e.loops.pop().?;
        const cont = e.here();
        for (lp.skips.items) |j| e.patch(j, cont);
        const back = try e.emit(Inst.asbx(.iterloop, base, 0), n.line);
        e.patch(back, body);
        // the tree walker that ran the whole loop lands on this jump; an empty collection goes to the else block
        const skip_else = try e.emit(Inst.asbx(.jmp, 0, 0), n.line);
        e.patch(prep, e.here());
        try e.block(n.kids[3]);
        const end = e.here();
        e.patch(skip_else, end);
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
        if (e.in_process) {
            // a safe point follows each statement of the process body, as in the tree walker: the objects that nobody holds
            // any more are freed there (and their destructors run) at the same place in both engines
            for (body.kids) |s| {
                try e.statement(s);
                _ = try e.emit(Inst.abc(.safe, 0, 0, 0), s.line);
            }
        } else try e.block(body);
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
        // declared by the tree walker before the machine starts (runRoot): the code reaches them by name
        .class, .trait, .adopt, .var_decl, .set, .generator, .table_decl, .import_decl, .method => {},
        else => return e.unsupported(k, @tagName(k.tag)),
    };
    const m = main orelse return e.unsupported(root, "an aspect without process main");
    // a routine that has a construct the bridge can not carry stays with the tree walker: a trial compilation tells which
    e.native = try a.alloc(bool, e.routines.items.len);
    e.fidx = try a.alloc(u8, e.routines.items.len);
    var next: u8 = 1;
    for (e.routines.items, 0..) |r, i| {
        // several routines with one name are chosen by the types of the arguments: the tree walker does that
        var shared = false;
        for (e.routines.items, 0..) |o, j| if (j != i and std.mem.eql(u8, o.text, r.text)) {
            shared = true;
        };
        if (shared) {
            e.native[i] = false;
            continue;
        }
        var trial: Emitter = .{ .a = a, .diag = diag, .routines = e.routines };
        trial.function(r) catch |err| switch (err) {
            error.Unsupported => {
                e.native[i] = false;
                continue;
            },
            error.OutOfMemory => return error.OutOfMemory,
        };
        e.native[i] = true;
        e.fidx[i] = next;
        next += 1;
    }
    try e.function(m);
    for (e.routines.items, 0..) |r, i| if (e.native[i]) try e.function(r);
    return .{
        .consts = e.consts.items,
        .funcs = e.funcs.items,
        .code = e.code.items,
        .lines = e.lines.items,
        .xnodes = e.xnodes.items,
        .main = 0,
    };
}

test "a counting loop and a call are translated" {
    const parser = @import("parser.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var pd: parser.Diag = .{};
    const tree = try parser.parse(arena.allocator(),
        \\primary aspect t is
        \\  function sq(n: Integer) => (@r: Integer) is
        \\    let r := n * n;
        \\  return;
        \\  process main is
        \\    new total := 0;
        \\    for i in (1..3) do
        \\      let total += sq(i);
        \\    done;
        \\    print total;
        \\  return;
        \\end t;
    , &pd);
    var d: Diag = .{};
    const c = try compile(arena.allocator(), tree, &d);
    try std.testing.expectEqual(@as(usize, 2), c.funcs.len);
    try std.testing.expectEqual(@as(usize, 0), c.xnodes.len);
    var found_call = false;
    var found_for = false;
    for (c.code) |w| {
        const i = Inst.fromWord(w);
        if (i.op == .callf and i.c == 1) found_call = true;
        if (i.op == .forloop) found_for = true;
    }
    try std.testing.expect(found_call and found_for);
}

test "a construct without a translation goes to the tree walker" {
    const parser = @import("parser.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var pd: parser.Diag = .{};
    const tree = try parser.parse(arena.allocator(),
        \\primary aspect t is
        \\  process main is
        \\    new o := {x: 3};
        \\    print o.x;
        \\  return;
        \\end t;
    , &pd);
    var d: Diag = .{};
    const c = try compile(arena.allocator(), tree, &d);
    try std.testing.expect(c.xnodes.len >= 2);
}
