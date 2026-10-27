//! @eve-module emit
//! @spec design/design-bytecode.md#9-stages
//! @feature F-VM-04
//! @decision D-201
//! @tests test/bytecode (`python script/bctest.py`), code/evecp/src/emit.zig (unit tests)
//! The emitter: turns the checked syntax tree of an aspect into a `Chunk` of the register machine. What it translates is
//! listed in design/design-bytecode.md §15; a call of anything that is not a translated routine is a `call` instruction
//! (§16.3); any other construct goes to the tree walker as an `evalx`/`execx` piece, and a piece the bridge can not carry
//! stops the compilation of its routine with the line and the name of the construct (`python script/bccensus.py`).
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

const Mark = struct { node: *const Node, reg: u8 };

const Local = struct { name: []const u8, reg: u8 };

const Loop = struct {
    /// The label of the loop (`n.text`), empty when it has none.
    label: []const u8 = "",
    /// The mark register of each declaration made in the body (D-213).
    marks: std.ArrayList(Mark) = .empty,
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
    /// The names that are function values in the scope of the code (routines of a module, imported functions): a call of one is a
    /// `call` of kind `value` whose callee the machine looks up by name, not a built-in.
    known: []const []const u8 = &.{},
    /// For each routine: does it have a native translation (else the tree walker runs it)? And its index in `funcs`.
    native: []bool = &.{},
    fidx: []u8 = &.{},
    xnodes: std.ArrayList(chunk.XNode) = .empty,
    /// The statements of the body of `main`, its `recover` and its `finalize` (see `chunk.Chunk`).
    stmt_pcs: std.ArrayList(u32) = .empty,
    recover_x: u16 = chunk.no_x,
    finalize_x: u16 = chunk.no_x,

    // the function being compiled
    locals: std.ArrayList(Local) = .empty,
    free: u8 = 0,
    max_regs: u8 = 0,
    start: u32 = 0,
    in_process: bool = false,
    result_reg: u8 = chunk.no_result,
    /// The routine being compiled defines names in the scope of its call (see `chunk.Func.needs_scope`).
    scope_used: bool = false,
    /// The routine has `defer` statements: every `ret` is preceded by `rundefers`.
    has_defer: bool = false,
    /// The xnodes of its `defer` statements, which name all the variables of the routine once it is compiled.
    pending_defers: std.ArrayList(u16) = .empty,
    /// How many results the routine has (consecutive registers from `result_reg`).
    result_n: u8 = 0,
    loops: std.ArrayList(Loop) = .empty,
    /// The register that holds `$` while the only index of a bracket is compiled.
    dollar_reg: ?u8 = null,
    /// The `apply` statement whose call site is being built by `callSite`.
    apply_node: ?*const Node = null,
    /// For each open `job` or `parallel` block: the count of loops open when it began (a jump may not leave the block).
    blocks: std.ArrayList(usize) = .empty,
    /// The names of the locals that a lambda of the routine names: they live in the scope of the routine, not in registers.
    captured: std.StringHashMapUnmanaged(void) = .empty,
    /// Compiled alone (`compileRoutine`): the routine has a scope of its own for each call.
    alone: bool = false,
    /// The aspect being compiled; null when a routine is compiled alone (its module's names are not known).
    aspect_root: ?*const Node = null,
    /// A loop header is being compiled: its declarations run once and need no mark of the enclosing loop.
    in_header: bool = false,

    /// Could `name` be a name of the aspect (a variable, a class, a routine, an import)? True when the aspect is not known.
    fn aspectMayHave(e: *Emitter, name: []const u8) bool {
        const root = e.aspect_root orelse return true;
        for (root.kids) |k| switch (k.tag) {
            .var_decl, .set => for (k.kids[0].kids) |t| if (std.mem.eql(u8, t.text, name)) return true,
            .import_decl => if (mentionsName(k, name)) return true,
            else => if (std.mem.eql(u8, k.text, name)) return true,
        };
        return false;
    }

    fn mentionsName(n: *const Node, name: []const u8) bool {
        if (std.mem.eql(u8, n.text, name)) return true;
        for (n.kids) |k| if (mentionsName(k, name)) return true;
        return false;
    }

    fn unsupported(e: *Emitter, n: *const Node, what: []const u8) Error {
        e.diag.message = what;
        e.diag.line = n.line;
        return error.Unsupported;
    }

    fn emit(e: *Emitter, i: Inst, line: u32) Error!u32 {
        switch (i.op) {
            .defvar, .closure, .jobbegin, .parbegin, .updbegin => e.scope_used = true,
            else => {},
        }
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

    /// The registers of a call: the callee (or its result) and the `nargs` arguments after it, contiguous, reserved before any
    /// argument is computed (the temporaries of an argument go above them).
    /// The result goes straight to `dst` when it is the last temporary: then the window starts there and no `move` follows.
    fn window(e: *Emitter, n: *const Node, nargs: usize, dst: u8) Error!u8 {
        const base = if (dst + 1 == e.free and !e.isLocal(dst)) dst else try e.alloc(n);
        for (0..nargs) |_| _ = try e.alloc(n);
        return base;
    }

    fn isKnown(e: *Emitter, name: []const u8) bool {
        for (e.known) |k| if (std.mem.eql(u8, k, name)) return true;
        return false;
    }

    fn isLocal(e: *Emitter, r: u8) bool {
        for (e.locals.items) |l| if (l.reg == r) return true;
        return false;
    }

    fn konst(e: *Emitter, c: chunk.Const) Error!u16 {
        for (e.consts.items, 0..) |k, i| {
            switch (k) {
                .int => |v| if (c == .int and c.int == v) return @intCast(i),
                .real => |v| if (c == .real and @as(u64, @bitCast(c.real)) == @as(u64, @bitCast(v))) return @intCast(i),
                .str => |v| if (c == .str and std.mem.eql(u8, v, c.str)) return @intCast(i),
                .cpx => |v| if (c == .cpx and @as(u64, @bitCast(c.cpx[0])) == @as(u64, @bitCast(v[0])) and @as(u64, @bitCast(c.cpx[1])) == @as(u64, @bitCast(v[1]))) return @intCast(i),
                .dur => |v| if (c == .dur and c.dur == v) return @intCast(i),
                .rat => |v| if (c == .rat and c.rat[0] == v[0] and c.rat[1] == v[1]) return @intCast(i),
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
                .rat => _ = try e.emit(Inst.abx(.loadk, dst, try e.konst(.{ .rat = .{ @as(i64, @intCast(n.lit_bits & 0xffffffff)), @as(i64, @intCast(n.lit_bits >> 32)) } })), line),
                .imag => _ = try e.emit(Inst.abx(.loadk, dst, try e.konst(.{ .cpx = .{ 0, @as(f64, @bitCast(n.lit_bits)) } })), line),
                .dur => _ = try e.emit(Inst.abx(.loadk, dst, try e.konst(.{ .dur = @bitCast(n.lit_bits) })), line),
                .none => _ = try e.emit(Inst.abx(.loadnum, dst, try e.konst(.{ .str = n.text })), line),
            },
            .text_lit => _ = try e.emit(Inst.abx(.loadtext, dst, try e.konst(.{ .str = n.text })), line),
            .chr => _ = try e.emit(Inst.abx(.loadrune, dst, try e.konst(.{ .str = n.text })), line),
            .field => {
                const mark = e.free;
                defer e.free = mark;
                const obj = try e.operand(n.kids[0]);
                _ = try e.emit(Inst.abc(.field, dst, obj, 0), line);
                if (!cannotBridge(n)) return e.xref(n);
                // the receiver holds a lambda or a task: the tree walker sees its value under a hidden name, never evaluates it again
                const synth = try e.a.create(Node);
                synth.* = n.*;
                const kids = try e.a.dupe(*const Node, n.kids);
                kids[0] = try e.hiddenNode(0, line);
                synth.kids = kids;
                const names = try e.a.alloc(chunk.NameReg, 1);
                names[0] = .{ .name = kids[0].text, .reg = obj };
                try e.xnodes.append(e.a, .{ .node = synth, .names = names });
                _ = try e.emit(Inst.abx(.xref, 0, @intCast(e.xnodes.items.len - 1)), line);
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
                if (!is_map and !std.mem.eql(u8, n.text, "set")) return e.objectLiteral(n, dst);
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
            .dollar => if (e.dollar_reg) |d| {
                if (d != dst) _ = try e.emit(Inst.abc(.move, dst, d, 0), line);
            } else try e.bridgeExpr(n, dst),
            .index => {
                if (!plainIndex(n) or (cannotBridge(n) and bracketsEligible(n))) {
                    if (!bracketsEligible(n)) return e.bridgeExpr(n, dst);
                    const mark = e.free;
                    defer e.free = mark;
                    const b = try e.brackets(n);
                    _ = try e.emit(Inst.abc(.indexv, dst, b.base, b.nargs), line);
                    _ = try e.emit(Inst.abx(.extra, 0, b.spec), line);
                    return;
                }
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
            .cond => {
                // `a if c else b`: the condition first, then only the branch that holds
                const mark = e.free;
                defer e.free = mark;
                const c = try e.operand(n.kids[1]);
                const to_else = try e.emit(Inst.asbx(.jf, c, 0), line);
                e.free = mark;
                try e.exprTo(n.kids[0], dst);
                const to_end = try e.emit(Inst.asbx(.jmp, 0, 0), line);
                e.patch(to_else, e.here());
                try e.exprTo(n.kids[2], dst);
                e.patch(to_end, e.here());
            },
            .range => {
                const mark = e.free;
                defer e.free = mark;
                const lo = try e.alloc(n);
                const hi = try e.alloc(n);
                const open_lo = n.kids[0].tag == .open_end;
                const open_hi = n.kids[1].tag == .open_end;
                if (open_lo) _ = try e.emit(Inst.abc(.loadnil, lo, 0, 0), line) else try e.exprTo(n.kids[0], lo);
                if (open_hi) _ = try e.emit(Inst.abc(.loadnil, hi, 0, 0), line) else try e.exprTo(n.kids[1], hi);
                _ = try e.emit(Inst.abc(.range, dst, lo, hi), line);
                _ = try e.emit(Inst.abx(.extra, @as(u8, @intFromBool(open_lo)) | (@as(u8, @intFromBool(open_hi)) << 1), try e.konst(.{ .str = n.text })), line);
            },
            .builder => try e.builder(n, dst),
            .lambda => {
                try e.xnodes.append(e.a, .{ .node = n, .names = &.{} });
                _ = try e.emit(Inst.abx(.closure, dst, @intCast(e.xnodes.items.len - 1)), line);
            },
            .bin => try e.binary(n, dst),
            .un => {
                if (!std.mem.eql(u8, n.text, "-") and !std.mem.eql(u8, n.text, "not")) return e.bridgeExpr(n, dst);
                const mark = e.free;
                defer e.free = mark;
                const src = try e.operand(n.kids[0]);
                _ = try e.emit(Inst.abc(if (n.text[0] == '-') .neg else .not, dst, src, 0), line);
            },
            .call => try e.call(n, dst, null),
            .await_ => try e.exprTo(n.kids[0], dst),
            else => try e.bridgeExpr(n, dst),
        }
    }

    // @eve-impl `[f(x) | x in src and cond]`, `(...)`, `{...}`: a loop over the elements of `src` that collects the values; a pattern of
    // several names and the product `a >< b` stay with the tree walker
    // @spec spec/syntax/expressions.md#literals-and-builders
    // @test test/bytecode/bc29_builders
    fn builder(e: *Emitter, n: *const Node, dst: u8) Error!void {
        var conds: std.ArrayList(*const Node) = .empty;
        var g = n.kids[1];
        while (g.tag == .bin and std.mem.eql(u8, g.text, "and")) {
            try conds.append(e.a, g.kids[1]);
            g = g.kids[0];
        }
        if (g.tag != .bin or !std.mem.eql(u8, g.text, "in")) return e.bridgeExpr(n, dst);
        const src = g.kids[1];
        if (src.tag == .bin and std.mem.eql(u8, src.text, "><")) return e.productBuilder(n, g, conds.items, dst);
        if (g.kids[0].tag != .name or std.mem.eql(u8, g.kids[0].text, "_")) return e.bridgeExpr(n, dst);
        if (cannotBridge(n)) return e.unsupported(n, "builder");
        const line = n.line;
        const mark = e.free;
        defer e.free = mark;
        const saved_locals = e.locals.items.len;
        defer e.locals.shrinkRetainingCapacity(saved_locals);
        const open = n.text[0];
        const out = try e.alloc(n);
        _ = try e.emit(Inst.abc(if (open == '{') .new_set else .new_list, out, @intFromBool(open == '['), 0), line);
        const base = try e.alloc(n);
        const pos = try e.alloc(n);
        const user = try e.alloc(n);
        std.debug.assert(pos == base + 1 and user == base + 2);
        try e.exprTo(src, base);
        _ = try e.emit(Inst.abc(.iterlist, base, base, 0), line);
        try e.locals.append(e.a, .{ .name = g.kids[0].text, .reg = user });
        const prep = try e.emit(Inst.asbx(.iterprep, base, 0), line);
        try e.xrefNode(n);
        const body = e.here();
        var skips: std.ArrayList(u32) = .empty;
        for (conds.items) |c| {
            const m2 = e.free;
            const r = try e.operand(c);
            try skips.append(e.a, try e.emit(Inst.asbx(.jf, r, 0), line));
            e.free = m2;
        }
        const slot = try e.alloc(n);
        try e.exprTo(n.kids[0], slot);
        _ = try e.emit(Inst.abc(if (open == '{') .set_add else .list_push, out, slot, 0), line);
        e.free = slot;
        for (skips.items) |j| e.patch(j, e.here());
        const back = try e.emit(Inst.asbx(.iterloop, base, 0), line);
        e.patch(back, body);
        e.patch(prep, e.here());
        _ = try e.emit(Inst.abc(.move, dst, out, 0), line);
    }

    // @eve-impl `[f(x, y) | (x, y) in a >< b and cond]`: two loops over the lists of `a` and `b`; a `[` builder collects a row for each `x`
    // (the pattern is a pair of names; any other pattern stays with the tree walker)
    // @spec spec/syntax/expressions.md#literals-and-builders
    // @test test/bytecode/bc29_builders
    fn productBuilder(e: *Emitter, n: *const Node, g: *const Node, conds: []const *const Node, dst: u8) Error!void {
        const pat = g.kids[0];
        if (pat.tag != .list or pat.kids.len != 2) return e.bridgeExpr(n, dst);
        for (pat.kids) |k| if (k.tag != .name or std.mem.eql(u8, k.text, "_") or std.mem.eql(u8, pat.kids[0].text, pat.kids[1].text)) return e.bridgeExpr(n, dst);
        if (cannotBridge(n)) return e.unsupported(n, "builder");
        const line = n.line;
        const src = g.kids[1];
        const mark = e.free;
        defer e.free = mark;
        const saved_locals = e.locals.items.len;
        defer e.locals.shrinkRetainingCapacity(saved_locals);
        const open = n.text[0];
        const out = try e.alloc(n);
        _ = try e.emit(Inst.abc(if (open == '{') .new_set else .new_list, out, @intFromBool(open == '['), 0), line);
        const row = try e.alloc(n);
        const xb = try e.alloc(n);
        const xpos = try e.alloc(n);
        const xu = try e.alloc(n);
        const yb = try e.alloc(n);
        const ypos = try e.alloc(n);
        const yu = try e.alloc(n);
        std.debug.assert(xpos == xb + 1 and xu == xb + 2 and ypos == yb + 1 and yu == yb + 2);
        try e.exprTo(src.kids[0], xb);
        _ = try e.emit(Inst.abc(.iterlist, xb, xb, 0), line);
        try e.exprTo(src.kids[1], yb);
        _ = try e.emit(Inst.abc(.iterlist, yb, yb, 0), line);
        try e.locals.append(e.a, .{ .name = pat.kids[0].text, .reg = xu });
        try e.locals.append(e.a, .{ .name = pat.kids[1].text, .reg = yu });
        const xprep = try e.emit(Inst.asbx(.iterprep, xb, 0), line);
        try e.xrefNode(n);
        const xbody = e.here();
        if (open == '[') _ = try e.emit(Inst.abc(.new_list, row, 1, 0), line);
        const yprep = try e.emit(Inst.asbx(.iterprep, yb, 0), line);
        try e.xrefNode(n);
        const ybody = e.here();
        var skips: std.ArrayList(u32) = .empty;
        for (conds) |c| {
            const m2 = e.free;
            const r = try e.operand(c);
            try skips.append(e.a, try e.emit(Inst.asbx(.jf, r, 0), line));
            e.free = m2;
        }
        const slot = try e.alloc(n);
        try e.exprTo(n.kids[0], slot);
        _ = try e.emit(Inst.abc(if (open == '{') .set_add else .list_push, if (open == '[') row else out, slot, 0), line);
        e.free = slot;
        for (skips.items) |j| e.patch(j, e.here());
        const yback = try e.emit(Inst.asbx(.iterloop, yb, 0), line);
        e.patch(yback, ybody);
        e.patch(yprep, e.here());
        if (open == '[') _ = try e.emit(Inst.abc(.list_push, out, row, 0), line);
        const xback = try e.emit(Inst.asbx(.iterloop, xb, 0), line);
        e.patch(xback, xbody);
        e.patch(xprep, e.here());
        _ = try e.emit(Inst.abc(.move, dst, out, 0), line);
    }

    /// `{x: 1, y: 2}`: an object literal, built field by field in the destination.
    fn objectLiteral(e: *Emitter, n: *const Node, dst: u8) Error!void {
        for (n.kids) |k| if (k.tag != .pair or k.kids.len != 2 or k.kids[0].tag != .name) return e.bridgeExpr(n, dst);
        const mark = e.free;
        defer e.free = mark;
        // a temporary holds the object: a value may read the variable `dst`
        const o = try e.alloc(n);
        _ = try e.emit(Inst.abc(.new_obj, o, 0, 0), n.line);
        for (n.kids) |k| {
            const v = try e.operand(k.kids[1]);
            _ = try e.emit(Inst.abc(.obj_set, o, v, 0), k.line);
            _ = try e.emit(Inst.abx(.extra, 0, try e.konst(.{ .str = k.kids[0].text })), k.line);
            e.free = o + 1;
        }
        if (o != dst) _ = try e.emit(Inst.abc(.move, dst, o, 0), n.line);
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
        // `??` runs its right side only when the left is null: the tree walker keeps that rule (types.md#narrowing-and-the-default)
        if (std.mem.eql(u8, n.text, "??")) {
            const t = try e.alloc(n);
            try e.exprTo(n.kids[0], t);
            const j = try e.emit(Inst.asbx(.jnn, t, 0), line);
            try e.exprTo(n.kids[1], t);
            e.patch(j, e.here());
            _ = try e.emit(Inst.abc(.move, dst, t, 0), line);
            return;
        }
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
                if (std.mem.eql(u8, n.text, "=~") and n.kids[1].tag == .range) {
                    if (!std.mem.eql(u8, n.kids[1].text, "+-")) return e.bridgeExpr(n, dst);
                    const base = try e.alloc(n);
                    try e.exprTo(n.kids[0], base);
                    const mid = try e.alloc(n);
                    try e.exprTo(n.kids[1].kids[0], mid);
                    const tol = try e.alloc(n);
                    try e.exprTo(n.kids[1].kids[1], tol);
                    _ = try e.emit(Inst.abc(.near, dst, base, 0), line);
                    return;
                }
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

    fn call(e: *Emitter, n: *const Node, dst: u8, stmt: ?*const Node) Error!void {
        const callee = n.kids[0];
        if (callee.tag == .field and n.kids.len == 1 and (std.mem.eql(u8, callee.text, "count") or std.mem.eql(u8, callee.text, "length")) and callee.kids[0].tag != .call and !cannotBridge(n)) {
            const mark = e.free;
            defer e.free = mark;
            const obj = try e.operand(callee.kids[0]);
            _ = try e.emit(Inst.abc(.length, dst, obj, 0), n.line);
            return e.xref(n);
        }
        if (callee.tag == .name and e.find(callee.text) == null and n.sel == null) direct: {
            const fi = e.routineIndex(callee.text) orelse break :direct;
            const target = e.routineNode(callee.text).?;
            const args = n.kids[1..];
            const params = target.kids[0].kids;
            if (args.len != params.len) break :direct;
            for (params) |p| if (p.tag == .vararg_param) break :direct;
            for (args) |a| if (a.tag == .pair or a.tag == .ref or a.tag == .spread) break :direct;
            const mark = e.free;
            defer e.free = mark;
            const base = try e.window(n, args.len, dst);
            for (args, 1..) |a, k| try e.exprTo(a, base + @as(u8, @intCast(k)));
            _ = try e.emit(Inst.abc(.callf, base, @intCast(args.len), fi), n.line);
            if (base != dst) _ = try e.emit(Inst.abc(.move, dst, base, 0), n.line);
            return;
        }
        return e.callSite(n, dst, stmt);
    }

    /// A call left to the tree walker: as a statement when it is one, so the variables it changes (`@x`) are copied back.
    fn bridgeCall(e: *Emitter, n: *const Node, dst: u8, stmt: ?*const Node) Error!void {
        if (stmt) |st| return e.bridgeStmt(st);
        return e.bridgeExpr(n, dst);
    }

    /// A routine whose first parameter is `@self`: it runs with a receiver.
    fn hasSelf(params: []const *const Node) bool {
        return params.len > 0 and params[0].tag == .ref_param and std.mem.eql(u8, params[0].text, "self");
    }

    /// The parameters of a routine or a process in the first registers; the register of a captured one holds the argument and the scope the variable.
    fn declareParams(e: *Emitter, params: []const *const Node) Error!u8 {
        var nparams: u8 = 0;
        for (params, 0..) |p, k| {
            // the receiver of a method is register 0, named `self`
            if (k == 0 and hasSelf(params)) {
                _ = try e.declare(p, "self");
                nparams += 1;
                continue;
            }
            if (p.tag == .ref_param) {
                // `@x`: the routine finds the variable of the caller by name, in the scope of the call (`bindArgs` binds the cell); the
                // register of the position stays empty. A routine called directly (`callf`) has no scope of its own.
                if (!e.alone) return e.unsupported(p, "a reference parameter, called directly");
                e.scope_used = true;
                _ = try e.alloc(p);
                nparams += 1;
                continue;
            }
            if ((p.tag != .param and p.tag != .vararg_param) or (p.kids.len > 0 and p.kids[0].tag != .none and !e.defaultFree(p.kids[0], params))) return e.unsupported(p, "a parameter that is not plain");
            if (e.captured.contains(p.text)) {
                const reg = try e.declare(p, try std.fmt.allocPrint(e.a, "$param{d}", .{nparams}));
                _ = try e.emit(Inst.abx(.defvar, reg, try e.konst(.{ .str = p.text })), p.line);
            } else _ = try e.declare(p, p.text);
            nparams += 1;
        }
        return nparams;
    }

    /// A default that names no parameter of the routine: the machine evaluates it in the scope of the call before the parameters exist.
    fn defaultFree(e: *Emitter, d: *const Node, params: []const *const Node) bool {
        if (literalDefault(d)) return true;
        if (cannotBridge(d)) return false;
        var used: std.StringHashMapUnmanaged(void) = .empty;
        e.mentioned(d, &.{}, &used) catch return false;
        for (params) |p| if (used.contains(p.text)) return false;
        return true;
    }

    /// A default of a parameter that the machine evaluates when it binds the arguments: a literal, `True`, `False` or `null`
    /// (a default that names another parameter stays with the tree walker, which binds the parameters in order).
    fn literalDefault(d: *const Node) bool {
        return switch (d.tag) {
            .str => true,
            .num => d.lit_kind != .none,
            .name => std.mem.eql(u8, d.text, "True") or std.mem.eql(u8, d.text, "False") or std.mem.eql(u8, d.text, "null"),
            else => false,
        };
    }

    /// The name of the hidden variable that carries register value `k` of a call site to the tree walker (`$0` the callee or the receiver).
    fn hiddenName(e: *Emitter, k: usize) Error![]const u8 {
        return std.fmt.allocPrint(e.a, "${d}", .{k});
    }

    /// A node that the tree walker evaluates at no cost and with no effect: a literal, or a name that is not a register of the
    /// routine (a module, a type, a constant of the aspect). A call site keeps such an argument as its node, in no register.
    fn selfEvident(e: *Emitter, n: *const Node) bool {
        return switch (n.tag) {
            .str => true,
            .num => n.lit_kind != .none,
            .name => e.find(n.text) == null,
            else => false,
        };
    }

    fn hiddenNode(e: *Emitter, k: usize, line: u32) Error!*const Node {
        const h = try e.a.create(Node);
        h.* = .{ .tag = .name, .line = line, .text = try e.hiddenName(k) };
        return h;
    }

    // @eve-impl a call that is not a direct call of a translated routine: the callee or the receiver and the arguments are computed
    // into registers, then the machine calls a function value at once, or gives the tree walker the call node with each value
    // replaced by a hidden name (the adapter for the natives that read their arguments as nodes)
    // @spec design/design-bytecode.md#163-calls-the-call-instruction
    // @test test/bytecode/bc23_calls
    fn callSite(e: *Emitter, n: *const Node, dst: u8, stmt: ?*const Node) Error!void {
        const callee = n.kids[0];
        const is_apply = e.apply_node != null;
        // an overload chosen by the checker (`n.sel`) and a callee with written types (`f(:T)(x)`) are called by the tree walker's own rule
        if (n.kids.len > 200 or cannotBridgeCall(n)) return e.bridgeCall(n, dst, stmt);
        var has_ref = false;
        for (n.kids[1..]) |a| switch (a.tag) {
            .star => return e.bridgeCall(n, dst, stmt),
            // `*xs`: the number of arguments is known when the call runs; the adapter binds the value of `xs` to a hidden name
            .spread => if (a.kids.len != 1) return e.bridgeCall(n, dst, stmt) else {
                has_ref = true;
            },
            // `@x` on a variable in a register: the final value of the argument is written back to it when the call returns
            .ref => if (a.kids.len > 0) {
                // an element `@s[i]`: the names it uses are defined for the call, the element is changed in its list
                has_ref = true;
            } else if (e.find(a.text) == null) return e.bridgeCall(n, dst, stmt) else {
                has_ref = true;
            },
            .pair => {
                if (a.kids.len != 2 or a.kids[0].tag != .name) return e.bridgeCall(n, dst, stmt);
                if (a.kids[1].tag == .ref) {
                    if (a.kids[1].kids.len == 0 and e.find(a.kids[1].text) == null) return e.bridgeCall(n, dst, stmt);
                    has_ref = true;
                }
            },
            else => {},
        };
        // a routine of the aspect that runs on the tree walker is a function value (`loadg`), called at once with the values
        const kind: evecm.op.CallKind = if (is_apply) .apply else if (callee.tag == .generic or n.sel != null) .builtin else if (callee.tag == .name and e.find(callee.text) == null and e.routineNode(callee.text) == null and !e.isKnown(callee.text)) .builtin else if (callee.tag == .field) .method else .value;
        const mark = e.free;
        defer e.free = mark;
        const base = try e.window(n, n.kids.len - 1, dst);
        var names: std.ArrayList(chunk.NameReg) = .empty;
        const kids = try e.a.alloc(*const Node, n.kids.len);
        // the machine calls the value of the callee or the receiver from the register: the site keeps the callee node for its name
        // and its type arguments only
        kids[0] = callee;
        var named = false;
        switch (kind) {
            .builtin, .apply => {},
            .value => if (callee.tag == .name and e.selfEvident(callee)) {
                named = true;
            } else try e.exprTo(callee, base),
            .method => if (e.selfEvident(callee.kids[0]) and callee.kids[0].tag == .name) {
                named = true;
            } else try e.exprTo(callee.kids[0], base),
        }
        for (n.kids[1..], 1..) |a, k| {
            const slot = base + @as(u8, @intCast(k));
            const value_node = if (a.tag == .pair) a.kids[1] else a;
            if (value_node.tag == .ref) {
                // the site keeps the reference under the name of the variable; the machine defines that name with the value of
                // its register for the call and, when the call returns, writes the final value back (a task: at its `done`)
                kids[k] = a;
                if (value_node.kids.len > 0) {
                    try e.collectNames(value_node, &names);
                } else {
                    const back = e.find(value_node.text).?;
                    try names.append(e.a, .{ .name = value_node.text, .reg = back, .back = back });
                }
                continue;
            }
            // the register stays empty: the machine evaluates the node when it needs the value (a direct call), the adapter reads it
            if (e.selfEvident(value_node)) {
                kids[k] = a;
                continue;
            }
            const h = try e.hiddenNode(k, a.line);
            if (a.tag == .spread) {
                try e.exprTo(a.kids[0], slot);
                const sp = try e.a.create(Node);
                sp.* = a.*;
                const sk = try e.a.alloc(*const Node, 1);
                sk[0] = h;
                sp.kids = sk;
                kids[k] = sp;
            } else if (a.tag == .pair) {
                try e.exprTo(a.kids[1], slot);
                const pk = try e.a.alloc(*const Node, 2);
                pk[0] = a.kids[0];
                pk[1] = h;
                const p = try e.a.create(Node);
                p.* = a.*;
                p.kids = pk;
                kids[k] = p;
            } else {
                try e.exprTo(a, slot);
                kids[k] = h;
            }
            try names.append(e.a, .{ .name = h.text, .reg = slot });
        }
        const site = try e.a.create(Node);
        site.* = n.*;
        site.kids = kids;
        // an `apply`: the site is the apply node with its arguments replaced (the dummy callee goes away)
        if (e.apply_node) |ap| {
            site.* = ap.*;
            if (ap.tag == .spawn_stmt) {
                // the node the tree walker reads is the spawn statement over the call with its arguments replaced
                const call_copy = try e.a.create(Node);
                call_copy.* = n.*;
                call_copy.kids = kids;
                const one = try e.a.alloc(*const Node, 1);
                one[0] = call_copy;
                site.kids = one;
            } else site.kids = kids[1..];
        }
        try e.xnodes.append(e.a, .{ .node = site, .names = names.items });
        _ = try e.emit(Inst.abc(.call, base, @intCast(n.kids.len - 1), @as(u8, @intFromEnum(kind)) | (if (stmt != null) evecm.op.call_stmt else 0) | (if (named) evecm.op.call_named else 0) | (if (has_ref) evecm.op.call_ref else 0) | (if (e.apply_node) |ap| (if (ap.tag == .start_stmt) evecm.op.call_start else if (ap.tag == .spawn_stmt) evecm.op.call_spawn else 0) else 0)), n.line);
        _ = try e.emit(Inst.abx(.site, 0, @intCast(e.xnodes.items.len - 1)), n.line);
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
            // a nested routine closes over the variables of its routine, which live in registers (captured variables are B5.4b)
            .break_stmt, .skip_stmt, .over_stmt, .exit_stmt, .stop_stmt, .retry_stmt, .resume_stmt, .abort_stmt, .lambda, .await_, .start_stmt, .spawn_stmt, .job, .parallel, .yield_stmt, .defer_stmt, .commit_stmt, .rollback_stmt, .panic_stmt, .function, .procedure, .generator, .method => return true,
            else => {},
        }
        for (n.kids) |k| if (cannotBridge(k)) return true;
        for (n.extra) |k| if (cannotBridge(k)) return true;
        return false;
    }

    /// `cannotBridge` for a call site: a lambda in the call is not a problem, the machine makes its function value in a register.
    fn cannotBridgeCall(n: *const Node) bool {
        if (n.tag == .lambda) return false;
        switch (n.tag) {
            .break_stmt, .skip_stmt, .over_stmt, .exit_stmt, .stop_stmt, .retry_stmt, .resume_stmt, .abort_stmt, .await_, .start_stmt, .spawn_stmt, .job, .parallel, .yield_stmt, .defer_stmt, .commit_stmt, .rollback_stmt, .panic_stmt, .function, .procedure, .generator, .method => return true,
            else => {},
        }
        for (n.kids) |k| if (cannotBridgeCall(k)) return true;
        for (n.extra) |k| if (cannotBridgeCall(k)) return true;
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

    fn hasDollar(n: *const Node) bool {
        if (n.tag == .dollar) return true;
        // the `$` of an index inside names that index's own object
        if (n.tag == .index) return hasDollar(n.kids[0]);
        for (n.kids) |k| if (hasDollar(k)) return true;
        return false;
    }

    /// Can the brackets `a[i, j][k]` be compiled to `indexv`/`index_setv`: plain indexes, ranges and `*`, at most 16 in all, and `$`
    /// only when it is the only index?
    fn bracketsEligible(n: *const Node) bool {
        var total: usize = 0;
        var groups: usize = 0;
        var dollar = false;
        var root = n;
        while (root.tag == .index) : (root = root.kids[0]) {
            if (root.kids.len < 2) return false;
            groups += 1;
            for (root.kids[1..]) |a| {
                switch (a.tag) {
                    .pair, .star, .spread => return false,
                    else => {},
                }
                if (a.tag != .all and hasDollar(a)) dollar = true;
                total += 1;
            }
        }
        return total <= 16 and !(dollar and (groups != 1 or total != 1));
    }

    const Brackets = struct { base: u8, nargs: u8, spec: u16 };

    // @eve-impl the brackets of an index chain `a[i, j][k]`: the object in a register, the value indexes after it, and the
    // description of the groups in a constant (the count of groups, the size of each, then 0 for a value and 1 for `*`)
    // @spec spec/syntax/expressions.md#index-slice-member
    // @test test/bytecode/bc28_indexes
    fn brackets(e: *Emitter, n: *const Node) Error!Brackets {
        var groups: std.ArrayList([]const *const Node) = .empty;
        var root = n;
        while (root.tag == .index) : (root = root.kids[0]) try groups.append(e.a, root.kids[1..]);
        std.mem.reverse([]const *const Node, groups.items);
        var dollar = false;
        for (groups.items) |g| for (g) |a| if (a.tag != .all and hasDollar(a)) {
            dollar = true;
        };
        const d: u8 = if (dollar) try e.alloc(n) else 0;
        const base = try e.alloc(n);
        try e.exprTo(root, base);
        if (dollar) _ = try e.emit(Inst.abc(.dim, d, base, 0), n.line);
        const saved = e.dollar_reg;
        defer e.dollar_reg = saved;
        if (dollar) e.dollar_reg = d;
        var spec: std.ArrayList(u8) = .empty;
        try spec.append(e.a, @intCast(groups.items.len));
        for (groups.items) |g| try spec.append(e.a, @intCast(g.len));
        var nargs: u8 = 0;
        for (groups.items) |g| for (g) |a| {
            if (a.tag == .all) {
                try spec.append(e.a, 1);
                continue;
            }
            try spec.append(e.a, 0);
            const slot = try e.alloc(a);
            try e.exprTo(a, slot);
            e.free = slot + 1;
            nargs += 1;
        };
        return .{ .base = base, .nargs = nargs, .spec = try e.konst(.{ .str = spec.items }) };
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

    /// The zero value of the type `ty` into register `reg`: a constant for the plain types, the zero of the tree walker for the rest.
    /// The caller has checked that `ty` has no array sizes.
    fn zeroOf(e: *Emitter, ty: *const Node, reg: u8) Error!void {
        const line = ty.line;
        const optional = ty.text.len > 0 and ty.text[ty.text.len - 1] == '?';
        switch (if (optional or ty.kids.len > 0) ast.TypeKind.none else ty.tk) {
            .integer, .short, .byte => _ = try e.emit(Inst.asbx(.loadi, reg, 0), line),
            .real, .float => _ = try e.emit(Inst.abx(.loadk, reg, try e.konst(.{ .real = 0 })), line),
            .logic => _ = try e.emit(Inst.abc(.loadfalse, reg, 0, 0), line),
            .string => _ = try e.emit(Inst.abx(.loadk, reg, try e.konst(.{ .str = "" })), line),
            else => {
                try e.xnodes.append(e.a, .{ .node = ty, .names = &.{} });
                _ = try e.emit(Inst.abx(.zero, reg, @intCast(e.xnodes.items.len - 1)), line);
            },
        }
    }

    // @eve-impl `update rec do ... done;`: the fields of the record are variables of the block, found by name (`loadg`/`storeg`) in the scope
    // that `updbegin` makes; the body may not name a local of the routine or declare a name (the tree walker would make it a field)
    // @spec spec/library/database.md#the-update-block
    // @test test/level5/e50_update_block
    fn updateStmt(e: *Emitter, n: *const Node) Error!void {
        const body = n.kids[1];
        var used: std.StringHashMapUnmanaged(void) = .empty;
        try e.mentioned(body, &.{}, &used);
        var it = used.keyIterator();
        while (it.next()) |name| if (e.find(name.*) != null) return e.bridgeStmt(n);
        if (cannotBridge(body) or declaresAny(body)) return e.bridgeStmt(n);
        const r = try e.operand(n.kids[0]);
        _ = try e.emit(Inst.abc(.updbegin, r, 0, 0), n.line);
        try e.block(body);
        _ = try e.emit(Inst.abc(.updend, 0, 0, 0), n.line);
    }

    fn declaresAny(n: *const Node) bool {
        switch (n.tag) {
            .var_decl, .set, .capture, .for_, .builder => return true,
            else => {},
        }
        for (n.kids) |k| if (declaresAny(k)) return true;
        return false;
    }

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
                // @eve-impl a `new` or `set` in the body of a loop: the loop has one scope for all its cycles and the second cycle is an
                // error, which only the tree walker reports (the declaration marks live in its variables); the program stays with it
                // @spec spec/semantics/scopes.md#redeclaration
                // @test a104_scope_loop_redeclare
                var mark_reg: ?u8 = null;
                if (e.loops.items.len > 0 and !e.in_header and !(e.blocks.items.len > 0 and e.blocks.getLast() == e.loops.items.len)) {
                    for (e.loops.items[e.loops.items.len - 1].marks.items) |m| if (m.node == n) {
                        mark_reg = m.reg;
                    };
                    if (mark_reg == null) return e.unsupported(n, "a declaration in the body of a loop");
                    for (n.kids[0].kids) |t| if ((t.tag == .name or t.tag == .star) and t.text.len > 0 and !std.mem.eql(u8, t.text, "_")) {
                        _ = try e.emit(Inst.abx(.declmark, mark_reg.?, try e.konst(.{ .str = t.text })), line);
                        break;
                    };
                }
                const one = n.kids.len == 2 and n.kids[0].kids.len == 1 and n.kids[0].kids[0].tag == .name and !std.mem.eql(u8, n.kids[0].kids[0].text, "_");
                const copy = std.mem.eql(u8, n.text, "::");
                const has_value = n.kids[1].tag != .none;
                const simple_ty = n.ty == null or n.ty.?.tk == .integer or n.ty.?.tk == .real or n.ty.?.tk == .string or n.ty.?.tk == .logic;
                const plain = one and (!has_value or std.mem.eql(u8, n.text, ":=") or std.mem.eql(u8, n.text, "=") or copy) and
                    (has_value or (n.ty != null and n.ty.?.kids.len == 0));
                // `new a, b :Integer;` and `new s :[5]Integer;`: each name gets the zero value of the type
                var zeros = !has_value and n.ty != null;
                if (zeros) for (n.kids[0].kids) |t| if (t.tag != .name or t.text.len == 0 or std.mem.eql(u8, t.text, "_")) {
                    zeros = false;
                };
                if (zeros and !plain) {
                    for (n.kids[0].kids) |t| {
                        if (e.captured.contains(t.text)) {
                            const tmp = try e.alloc(n);
                            try e.zeroOf(n.ty.?, tmp);
                            _ = try e.emit(Inst.abx(.defvar, tmp, try e.konst(.{ .str = t.text }) | (if (n.tag == .set) @as(u16, 0x8000) else 0)), line);
                            e.free = tmp;
                        } else try e.zeroOf(n.ty.?, try e.declare(n, t.text));
                    }
                    return;
                }
                if (!plain) {
                    for (n.kids[0].kids) |t| if ((t.tag == .name or t.tag == .star) and e.captured.contains(t.text)) return e.unsupported(n, "a captured variable declared by a form that is not plain");
                    if (!has_value or cannotBridge(n.kids[0])) return e.bridgeStmt(n);
                    // deconstructing (`new q, r := divmod(a, b);`, `new (u, v) = 7;`, `new p, *, r := xs;`): `unpack` binds registers to the parts
                    if (n.ty != null) return e.bridgeStmt(n);
                    for (n.kids[0].kids) |t| if (t.tag != .name and t.tag != .star) return e.bridgeStmt(n);
                    const targets = n.kids[0].kids;
                    const hold = try e.alloc(n);
                    try e.exprTo(n.kids[1], hold);
                    if (copy) _ = try e.emit(Inst.abc(.clone, hold, hold, 0), line);
                    const first = e.free;
                    var star: u16 = 0;
                    for (targets, 0..) |t, k| {
                        _ = try e.alloc(n);
                        if (t.tag == .star) star = @intCast(k + 1);
                    }
                    _ = try e.emit(Inst.abc(.unpack, hold, first, @intCast(targets.len)), line);
                    _ = try e.emit(Inst.abx(.extra, 0, star * 2 + @intFromBool(std.mem.eql(u8, n.text, "="))), line);
                    for (targets, 0..) |t, k| {
                        if (t.text.len == 0 or std.mem.eql(u8, t.text, "_")) continue;
                        try e.locals.append(e.a, .{ .name = t.text, .reg = first + @as(u8, @intCast(k)) });
                    }
                    return;
                }
                const t = n.kids[0].kids[0];
                // the value is computed before the name exists, as in the tree walker
                const tmp = try e.alloc(n);
                if (has_value) {
                    try e.exprTo(n.kids[1], tmp);
                    if (copy) _ = try e.emit(Inst.abc(.clone, tmp, tmp, 0), line);
                } else try e.zeroOf(n.ty.?, tmp);
                e.free = mark;
                const is_captured = e.captured.contains(t.text);
                const r = if (is_captured) tmp else try e.declare(n, t.text);
                if (r != tmp) _ = try e.emit(Inst.abc(.move, r, tmp, 0), line);
                // a declared type may convert the value: an Integer to a Real, a Real to an Integer (`coerce` of the tree walker)
                if (has_value) {
                    if (n.ty) |ty| {
                        if (simple_ty) {
                            if (ty.kids.len == 0 and (ty.tk == .real or ty.tk == .integer)) _ = try e.emit(Inst.abc(.coerce, r, @intFromEnum(ty.tk), 0), line);
                        } else {
                            try e.xnodes.append(e.a, .{ .node = n, .names = &.{} });
                            _ = try e.emit(Inst.abx(.declty, r, @intCast(e.xnodes.items.len - 1)), line);
                        }
                    } else if (n.kids[1].tag == .call and (n.kids[1].kids[0].tag == .name or n.kids[1].kids[0].tag == .generic) and std.mem.eql(u8, n.kids[1].kids[0].text, "Channel")) {
                        try e.xnodes.append(e.a, .{ .node = n, .names = &.{} });
                        _ = try e.emit(Inst.abx(.declty, r, @intCast(e.xnodes.items.len - 1)), line);
                    }
                }
                if (is_captured) _ = try e.emit(Inst.abx(.defvar, r, try e.konst(.{ .str = t.text }) | (if (n.tag == .set) @as(u16, 0x8000) else 0)), line);
            },
            .capture => {
                // @eve-impl `let l -> x;` `let x <- l;` `new x <- l;`: into `_`, a variable in a register or a variable declared here
                // @spec spec/syntax/statements.md#statements-that-bind-a-value
                // @test test/bytecode/bc27_fields
                const target = n.kids[1];
                const explicit_new = n.kids[2].tag == .none;
                // a name that is no register and no name of the aspect does not exist: `let` creates it, as `new` does
                if (target.tag != .name or !(std.mem.eql(u8, target.text, "_") or explicit_new or e.find(target.text) != null or !e.aspectMayHave(target.text))) return e.bridgeStmt(n);
                const l = try e.operand(n.kids[0]);
                const r = if (std.mem.eql(u8, target.text, "_")) try e.alloc(n) else try e.declare(n, target.text);
                _ = try e.emit(Inst.abc(.capture, r, l, @intFromBool(n.text[0] != '-')), line);
            },
            .update_stmt => try e.updateStmt(n),
            // @eve-impl a function or procedure declared in the body of a routine: its function value (`closure`, the scope of the call is its
            // closure) is the name in the scope, or the register when the name is a result of the routine (`function make() => (@next)`)
            // @spec spec/syntax/declarations.md#functions-and-procedures
            // @test test/level2/b19_closure
            .function, .procedure => {
                if (n.kids.len > 5 or n.is_external or n.is_async or n.is_sql) return e.unsupported(n, "a routine declared in a routine of this kind");
                try e.xnodes.append(e.a, .{ .node = n, .names = &.{} });
                const xi: u16 = @intCast(e.xnodes.items.len - 1);
                if (e.find(n.text)) |r| {
                    _ = try e.emit(Inst.abx(.closure, r, xi), line);
                } else {
                    const t = try e.alloc(n);
                    _ = try e.emit(Inst.abx(.closure, t, xi), line);
                    _ = try e.emit(Inst.abx(.defvar, t, try e.konst(.{ .str = n.text })), line);
                }
            },
            // @eve-impl `defer stmt;` in a routine: the statement waits in the frame and runs on the tree walker, newest first, with the
            // variables of the routine copied in and out, when the routine ends or an error leaves it
            // @spec spec/syntax/statements.md#interruptions
            // @test test/level2/b42_defer_procedure
            .defer_stmt => {
                if (e.in_process or cannotBridge(n.kids[0])) return e.unsupported(n, "defer");
                try e.xnodes.append(e.a, .{ .node = n.kids[0], .names = &.{} });
                try e.pending_defers.append(e.a, @intCast(e.xnodes.items.len - 1));
                _ = try e.emit(Inst.abx(.deferpush, 0, @intCast(e.xnodes.items.len - 1)), line);
            },
            .block => try e.block(n), // the groups of declarations (`new x = 1, y = 2 :Integer;`) are not a scope
            .assign => try e.assign(n),
            .print_stmt, .write_stmt => try e.printStmt(n),
            .expect_stmt, .assert_stmt => {
                const is_assert = n.tag == .assert_stmt;
                const r = try e.operand(n.kids[0]);
                if (!is_assert and n.kids.len == 1) {
                    _ = try e.emit(Inst.abc(.expect, r, 0, 0), line);
                } else {
                    // the message is computed only when the condition fails, as in the tree walker
                    const j = try e.emit(Inst.asbx(.jt, r, 0), line);
                    if (n.kids.len > 1) {
                        const m = try e.operand(n.kids[1]);
                        _ = try e.emit(Inst.abc(.failmsg, m, @intFromBool(is_assert), 1), line);
                    } else _ = try e.emit(Inst.abc(.failmsg, 0, @intFromBool(is_assert), 0), line);
                    e.patch(j, e.here());
                }
            },
            .raise_stmt => {
                if (n.kids.len == 0) return e.bridgeStmt(n);
                const r = try e.operand(n.kids[0]);
                _ = try e.emit(Inst.abc(.raise, r, 0, 0), line);
            },
            .if_ => try e.ifStmt(n),
            .while_ => try e.whileStmt(n),
            .for_ => try e.forStmt(n),
            .repeat_ => try e.repeatStmt(n),
            .match_ => try e.matchStmt(n),
            .cond_stmt => {
                const c = try e.operand(n.kids[0]);
                const j = try e.emit(Inst.asbx(.jf, c, 0), line);
                e.free = mark;
                try e.statement(n.kids[1]);
                e.patch(j, e.here());
            },
            .stop_stmt => _ = try e.emit(Inst.abc(.signal, 0, 0, 0), line),
            .rollback_stmt => _ = try e.emit(Inst.abc(.signal, 1, 0, 0), line),
            .panic_stmt => _ = try e.emit(Inst.abc(.signal, 2, 0, 0), line),
            .commit_stmt => _ = try e.emit(Inst.abc(.commit, 0, 0, 0), line),
            .job => try e.jobStmt(n),
            .parallel => try e.parallelStmt(n),
            .spawn_stmt => {
                // @eve-impl `spawn f(args);` in a job: a call site of kind `apply` whose callee is a name outside the registers
                // @spec spec/semantics/multitasking.md#tasks-in-a-job
                // @test test/bytecode/bc32_jobs
                const call_node = n.kids[0];
                if (call_node.tag != .call or call_node.kids[0].tag != .name or e.find(call_node.kids[0].text) != null) return e.bridgeStmt(n);
                e.apply_node = n;
                defer e.apply_node = null;
                const t = try e.alloc(n);
                try e.callSite(call_node, t, n);
            },
            .apply_stmt, .start_stmt => {
                // @eve-impl `apply name(args);` is a call site of kind `apply`: the arguments in registers, the aspect runs by the tree walker's rule
                // @spec spec/semantics/aspects.md#declarations-of-an-aspect
                // @test test/bytecode/bc30_apply
                const dummy = try e.a.create(Node);
                dummy.* = .{ .tag = .name, .line = n.line, .text = n.text };
                const all = try e.a.alloc(*const Node, n.kids.len + 1);
                all[0] = dummy;
                @memcpy(all[1..], n.kids);
                const synth = try e.a.create(Node);
                synth.* = .{ .tag = .call, .line = n.line, .kids = all };
                e.apply_node = n;
                defer e.apply_node = null;
                const t = try e.alloc(n);
                try e.callSite(synth, t, n);
            },
            .expr_stmt => {
                const x = if (n.kids[0].tag == .await_) n.kids[0].kids[0] else n.kids[0];
                // @eve-impl a bare name that is a routine is a call without arguments: `hello;` (exprStmt of the tree walker)
                if (x.tag == .name and n.kids[0].tag != .await_ and e.find(x.text) == null and (e.routineNode(x.text) != null or e.isKnown(x.text))) {
                    const synth = try e.a.create(Node);
                    const callee = try e.a.alloc(*const Node, 1);
                    callee[0] = x;
                    synth.* = .{ .tag = .call, .line = x.line, .kids = callee };
                    const t = try e.alloc(n);
                    try e.call(synth, t, null);
                    _ = try e.emit(Inst.abc(.loadnil, t, 0, 0), line);
                    return;
                }
                if (x.tag != .call) return e.bridgeStmt(n);
                const t = try e.alloc(n);
                try e.call(x, t, n);
            },
            .break_stmt, .skip_stmt => {
                if (e.loops.items.len == 0) return e.unsupported(n, "break or skip outside a loop");
                var at = e.loops.items.len - 1;
                if (n.text.len > 0) {
                    while (!std.mem.eql(u8, e.loops.items[at].label, n.text)) {
                        if (at == 0) return e.unsupported(n, "break or skip with an unknown label");
                        at -= 1;
                    }
                }
                if (e.blocks.items.len > 0 and at < e.blocks.getLast()) return e.unsupported(n, "a jump out of a job or a parallel block");
                const j = try e.emit(Inst.asbx(.jmp, 0, 0), line);
                const lp = &e.loops.items[at];
                if (n.tag == .break_stmt) try lp.breaks.append(e.a, j) else try lp.skips.append(e.a, j);
            },
            .over_stmt => {
                if (n.kids.len > 0) {
                    const r = try e.operand(n.kids[0]);
                    _ = try e.emit(Inst.abc(.exitcode, r, 0, 0), line);
                }
                _ = try e.emit(Inst.abc(.over, 0, 0, 0), line);
            },
            .exit_stmt => {
                if (e.blocks.items.len > 0) return e.unsupported(n, "exit in a job or a parallel block");
                if (n.kids.len > 0) {
                    const r = try e.operand(n.kids[0]);
                    _ = try e.emit(Inst.abc(.exitcode, r, 0, 0), line);
                }
                if (e.in_process) {
                    _ = try e.emit(Inst.abc(.halt, 0, 0, 0), line);
                } else try e.emitRet(line);
            },
            .pass_stmt => {},
            .wait_stmt => {
                const r = try e.operand(n.kids[0]);
                _ = try e.emit(Inst.abc(.wait, r, 0, 0), line);
            },
            else => return e.bridgeStmt(n),
        }
        e.free = e.floor();
    }

    /// The operator of a compound assignment `+= -= *= /= %= ^=`, or null for the others.
    fn augOp(n: *const Node) ?Op {
        return switch (n.op) {
            .add => .add,
            .sub => .sub,
            .mul => .mul,
            .div => .div,
            .mod => .mod,
            .other => if (std.mem.eql(u8, n.text, "^=")) .pow else null,
            else => null,
        };
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
        // @eve-impl an assignment to brackets that `index_set` does not take (several indexes, a slice, `*`, a chain): the value is
        // computed first, then the object and the indexes; a compound operator reads the element, combines, and stores it back
        // @spec spec/syntax/expressions.md#index-slice-member
        // @test test/bytecode/bc28_indexes
        if (target.tag == .index and bracketsEligible(target)) {
            const op: ?Op = augOp(n);
            if (n.op == .set or n.op == .copy or op != null) {
                const v = try e.alloc(n);
                try e.exprTo(n.kids[1], v);
                if (n.op == .copy) _ = try e.emit(Inst.abc(.clone, v, v, 0), line);
                const b = try e.brackets(target);
                var stored = v;
                if (op) |o| {
                    stored = try e.alloc(n);
                    _ = try e.emit(Inst.abc(.indexv, stored, b.base, b.nargs), line);
                    _ = try e.emit(Inst.abx(.extra, 0, b.spec), line);
                    _ = try e.emit(Inst.abc(.augment, stored, v, @intFromEnum(o)), line);
                }
                _ = try e.emit(Inst.abc(.index_setv, stored, b.base, b.nargs), line);
                _ = try e.emit(Inst.abx(.extra, @intFromBool(op != null), b.spec), line);
                return;
            }
        }
        if (n.op == .push_front and n.kids[1].tag == .name) if (e.find(n.kids[1].text)) |reg| {
            const v = try e.operand(n.kids[0]);
            _ = try e.emit(Inst.abc(.push_front, reg, v, 0), line);
            return e.xref(n);
        };
        if (target.tag == .name and n.op == .push_back) if (e.find(target.text)) |reg| {
            const v = try e.operand(n.kids[1]);
            _ = try e.emit(Inst.abc(.push, reg, v, 0), line);
            return e.xref(n);
        };
        // @eve-impl `let o.f := v;` and `let o.f :: v;` on a variable in a register: the value first, then the field
        // @spec spec/syntax/statements.md#statements-that-bind-a-value
        // @test test/bytecode/bc27_fields
        // a compound operator (`let self.n += 1;`) reads the field, combines, and stores it back unless a list or a set changed in place
        if (target.tag == .field and (n.op == .set or n.op == .copy or augOp(n) != null) and target.kids[0].tag == .name and e.find(target.kids[0].text) != null) {
            const v = try e.alloc(n);
            try e.exprTo(n.kids[1], v);
            if (n.op == .copy) _ = try e.emit(Inst.abc(.clone, v, v, 0), line);
            const obj = e.find(target.kids[0].text).?;
            var stored = v;
            if (augOp(n)) |o| {
                stored = try e.alloc(n);
                _ = try e.emit(Inst.abc(.field, stored, obj, 0), line);
                try e.xref(target);
                _ = try e.emit(Inst.abc(.augment, stored, v, @intFromEnum(o)), line);
            }
            _ = try e.emit(Inst.abc(.setfield, obj, stored, @intFromBool(augOp(n) != null)), line);
            _ = try e.emit(Inst.abx(.extra, 0, try e.konst(.{ .str = target.text })), line);
            return;
        }
        // `let name <+ v;` on a name outside the registers (a table or a list of the aspect): a list or a set takes the element at once; the
        // other targets are left to the tree walker, which sees the value of the element under a hidden name (it is not evaluated twice)
        if (target.tag == .name and n.op == .push_back and e.find(target.text) == null and !cannotBridge(n)) {
            const mark = e.free;
            defer e.free = mark;
            const t = try e.alloc(n);
            _ = try e.emit(Inst.abx(.loadg, t, try e.konst(.{ .str = target.text })), line);
            const v = try e.operand(n.kids[1]);
            _ = try e.emit(Inst.abc(.push, t, v, 0), line);
            const synth = try e.a.create(Node);
            synth.* = n.*;
            const kids = try e.a.dupe(*const Node, n.kids);
            kids[1] = try e.hiddenNode(0, line);
            synth.kids = kids;
            const names = try e.a.alloc(chunk.NameReg, 1);
            names[0] = .{ .name = kids[1].text, .reg = v };
            try e.xnodes.append(e.a, .{ .node = synth, .names = names });
            _ = try e.emit(Inst.abx(.xref, 0, @intCast(e.xnodes.items.len - 1)), line);
            return;
        }
        if (target.tag != .name) return e.bridgeStmt(n);
        // @eve-impl an assignment to a name outside the registers (a variable of the closure, the aspect, a module): the value is
        // computed here, the machine stores it by the rule of the tree walker
        // @spec design/design-bytecode.md#162-the-pivot-the-unit-of-the-bridge-is-the-routine-not-the-expression
        // @test test/bytecode/bc24_routines
        const reg = e.find(target.text) orelse switch (n.op) {
            .set, .copy, .add, .sub, .mul, .div, .mod, .other => {
                if (n.op == .other and augOp(n) == null) return e.bridgeStmt(n);
                const t = try e.alloc(n);
                try e.exprTo(n.kids[1], t);
                try e.xnodes.append(e.a, .{ .node = n, .names = &.{} });
                _ = try e.emit(Inst.abx(.storeg, t, @intCast(e.xnodes.items.len - 1)), line);
                return;
            },
            else => return e.bridgeStmt(n),
        };
        const op: Op = switch (n.op) {
            .set => {
                // the new value is computed first (it may read the variable), then stored with the conversion of `:=`
                const t = try e.alloc(n);
                try e.exprTo(n.kids[1], t);
                _ = try e.emit(Inst.abc(.setlike, reg, t, 0), line);
                return;
            },
            else => augOp(n) orelse return e.bridgeStmt(n),
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
            // `sep: text` (the last one wins, and is evaluated before the values, as in the tree walker) goes to the register before them
            var sep: ?*const Node = null;
            var count: u8 = 0;
            for (arg.kids) |k| {
                if (k.tag != .pair) {
                    count += 1;
                } else if (k.kids[0].tag == .name and std.mem.eql(u8, k.kids[0].text, "sep")) sep = k.kids[1] else return e.bridgeStmt(n);
            }
            if (sep) |sn| {
                const slot = try e.alloc(sn);
                try e.exprTo(sn, slot);
            }
            for (arg.kids) |k| {
                if (k.tag == .pair) continue;
                const slot = try e.alloc(k);
                try e.exprTo(k, slot);
            }
            _ = try e.emit(Inst.abc(.print, base, count, newline | (if (sep != null) @as(u8, 2) else 0)), line);
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

    /// The declarations of a loop body that share its scope: nested `if` blocks and groups, not nested loops.
    fn collectDecls(e: *Emitter, n: *const Node, out: *std.ArrayList(Mark)) Error!void {
        switch (n.tag) {
            .var_decl, .set => {
                const r = try e.alloc(n);
                try e.locals.append(e.a, .{ .name = "$mark", .reg = r });
                _ = try e.emit(Inst.abc(.loadfalse, r, 0, 0), n.line);
                try out.append(e.a, .{ .node = n, .reg = r });
            },
            .block, .if_, .cond_stmt => for (n.kids) |k| try e.collectDecls(k, out),
            .match_ => {
                for (n.kids[2..]) |w| try e.collectDecls(w.kids[1], out);
                try e.collectDecls(n.kids[1], out);
            },
            else => {},
        }
    }

    /// Start a loop: the marks of its declarations are cleared before the first cycle. `body` is the block of the loop.
    fn enterLoop(e: *Emitter, label: []const u8, body: *const Node) Error!void {
        var marks: std.ArrayList(Mark) = .empty;
        try e.collectDecls(body, &marks);
        try e.loops.append(e.a, .{ .label = label, .marks = marks });
    }

    fn whileStmt(e: *Emitter, n: *const Node) Error!void {
        const saved_locals = e.locals.items.len;
        try e.header(n.kids[0]);
        // `else` runs when the body never ran
        const has_else = n.kids[3].kids.len > 0;
        var ran: u8 = 0;
        if (has_else) {
            ran = try e.alloc(n);
            try e.locals.append(e.a, .{ .name = "$ran", .reg = ran });
            _ = try e.emit(Inst.abc(.loadfalse, ran, 0, 0), n.line);
        }
        try e.enterLoop(n.text, n.kids[2]);
        const top = e.here();
        const c = try e.operand(n.kids[1]);
        const exit = try e.emit(Inst.asbx(.jf, c, 0), n.line);
        e.free = e.floor();
        if (has_else) _ = try e.emit(Inst.abc(.loadtrue, ran, 0, 0), n.line);
        try e.block(n.kids[2]);
        const back = try e.emit(Inst.asbx(.jmp, 0, 0), n.line);
        e.patch(back, top);
        var lp = e.loops.pop().?;
        for (lp.skips.items) |j| e.patch(j, top);
        e.patch(exit, e.here());
        if (has_else) {
            const skip_else = try e.emit(Inst.asbx(.jt, ran, 0), n.line);
            try e.block(n.kids[3]);
            e.patch(skip_else, e.here());
        }
        const end = e.here();
        for (lp.breaks.items) |j| e.patch(j, end);
        lp.breaks.deinit(e.a);
        lp.skips.deinit(e.a);
        e.locals.shrinkRetainingCapacity(saved_locals);
        e.free = e.floor();
        try e.block(n.kids[4]);
    }

    /// The declarations of a loop header (`loop new steps := 100; while ...`): run once, in the scope of the loop.
    fn header(e: *Emitter, b: *const Node) Error!void {
        const saved = e.in_header;
        e.in_header = true;
        defer e.in_header = saved;
        try e.block(b);
    }

    // @eve-impl `loop do ... repeat [while c];`: the body runs once, then again while the condition holds (always when there is none);
    // `skip` goes to the condition
    // @spec spec/semantics/control.md#loops
    // @test a39_repeat
    fn repeatStmt(e: *Emitter, n: *const Node) Error!void {
        const saved_locals = e.locals.items.len;
        try e.header(n.kids[0]);
        try e.enterLoop(n.text, n.kids[1]);
        const top = e.here();
        e.free = e.floor();
        try e.block(n.kids[1]);
        var lp = e.loops.pop().?;
        const cont = e.here();
        for (lp.skips.items) |j| e.patch(j, cont);
        if (n.kids.len > 2) {
            const c = try e.operand(n.kids[2]);
            const back = try e.emit(Inst.asbx(.jt, c, 0), n.line);
            e.patch(back, top);
        } else {
            const back = try e.emit(Inst.asbx(.jmp, 0, 0), n.line);
            e.patch(back, top);
        }
        const end = e.here();
        for (lp.breaks.items) |j| e.patch(j, end);
        lp.breaks.deinit(e.a);
        lp.skips.deinit(e.a);
        e.locals.shrinkRetainingCapacity(saved_locals);
        e.free = e.floor();
    }

    // @eve-impl `match`: the subject is computed once; each `when` tests its patterns in order (all of them, as the tree walker does),
    // runs its block when one holds, and `match all` goes on to the next arm
    // @spec spec/semantics/control.md#match
    // @test test/bytecode/bc26_match
    fn matchStmt(e: *Emitter, n: *const Node) Error!void {
        const saved_locals = e.locals.items.len;
        const line = n.line;
        const all = std.mem.startsWith(u8, n.text, "all");
        const subj = try e.alloc(n);
        try e.exprTo(n.kids[0], subj);
        try e.locals.append(e.a, .{ .name = "$subject", .reg = subj });
        const hit = try e.alloc(n);
        try e.locals.append(e.a, .{ .name = "$hit", .reg = hit });
        var ends: std.ArrayList(u32) = .empty;
        for (n.kids[2..]) |w| {
            _ = try e.emit(Inst.abc(.loadfalse, hit, 0, 0), w.line);
            for (w.kids[0].kids) |pat| {
                e.free = e.floor();
                if (pat.tag == .name and std.mem.eql(u8, pat.text, "other") and e.find("other") == null) {
                    _ = try e.emit(Inst.abc(.loadtrue, hit, 0, 0), pat.line);
                    continue;
                }
                const t = try e.alloc(pat);
                const pv = try e.alloc(pat);
                if (pat.tag == .list) {
                    for (pat.kids) |k| {
                        try e.exprTo(k, pv);
                        _ = try e.emit(Inst.abc(.matcheq, t, subj, pv), k.line);
                        const j = try e.emit(Inst.asbx(.jf, t, 0), k.line);
                        _ = try e.emit(Inst.abc(.loadtrue, hit, 0, 0), k.line);
                        e.patch(j, e.here());
                    }
                } else {
                    try e.exprTo(pat, pv);
                    _ = try e.emit(Inst.abc(.matchpat, t, subj, pv), pat.line);
                    const j = try e.emit(Inst.asbx(.jf, t, 0), pat.line);
                    _ = try e.emit(Inst.abc(.loadtrue, hit, 0, 0), pat.line);
                    e.patch(j, e.here());
                }
            }
            e.free = e.floor();
            const next = try e.emit(Inst.asbx(.jf, hit, 0), w.line);
            try e.block(w.kids[1]);
            if (!all) try ends.append(e.a, try e.emit(Inst.asbx(.jmp, 0, 0), line));
            e.patch(next, e.here());
        }
        for (ends.items) |j| e.patch(j, e.here());
        e.locals.shrinkRetainingCapacity(saved_locals);
        e.free = e.floor();
        try e.block(n.kids[1]);
    }

    // @eve-impl `job ... done;`: the block runs in a scope of its own; an error in it goes to `jobclose`, which waits for the tasks,
    // commits or rolls back and sets the state of the job as the tree walker does
    // @spec spec/semantics/control.md#job
    // @test test/bytecode/bc32_jobs
    fn jobStmt(e: *Emitter, n: *const Node) Error!void {
        const saved_locals = e.locals.items.len;
        const begin = try e.emit(Inst.asbx(.jobbegin, 0, 0), n.line);
        _ = try e.emit(Inst.abx(.extra, 0, try e.konst(.{ .str = n.text })), n.line);
        try e.blocks.append(e.a, e.loops.items.len);
        try e.block(n.kids[0]);
        _ = e.blocks.pop();
        e.patch(begin, e.here());
        _ = try e.emit(Inst.abc(.jobclose, 0, 0, 0), n.line);
        e.locals.shrinkRetainingCapacity(saved_locals);
        e.free = e.floor();
    }

    // @eve-impl `parallel ... do ... done;`: like a job, with the group in which `start` is allowed and the `within` time limit
    // @spec spec/semantics/multitasking.md#where-a-group-is-allowed
    // @test test/bytecode/bc32_jobs
    fn parallelStmt(e: *Emitter, n: *const Node) Error!void {
        const saved_locals = e.locals.items.len;
        const mark = e.free;
        var within: u8 = 255;
        if (n.kids[2].tag != .none) {
            within = try e.alloc(n);
            try e.exprTo(n.kids[2], within);
        }
        const begin = try e.emit(Inst.asbx(.parbegin, within, 0), n.line);
        e.free = mark;
        _ = try e.emit(Inst.abx(.extra, @intFromBool(n.public), try e.konst(.{ .str = n.text })), n.line);
        try e.blocks.append(e.a, e.loops.items.len);
        try e.block(n.kids[0]);
        try e.block(n.kids[1]);
        _ = e.blocks.pop();
        e.patch(begin, e.here());
        _ = try e.emit(Inst.abc(.parclose, 0, 0, 0), n.line);
        e.locals.shrinkRetainingCapacity(saved_locals);
        e.free = e.floor();
    }

    fn forStmt(e: *Emitter, n: *const Node) Error!void {
        const range = n.kids[1];
        if (n.kids[0].tag == .name and range.tag != .range) return e.forEach(n);
        if (range.tag != .range and pairPattern(n.kids[0]) != null) return e.forEach(n);
        const rt = range.text;
        if (n.kids[0].tag != .name or range.tag != .range or !(std.mem.eql(u8, rt, "..") or std.mem.eql(u8, rt, ">..") or std.mem.eql(u8, rt, "..<") or std.mem.eql(u8, rt, ">..<"))) return e.bridgeStmt(n);
        if (range.kids[0].tag == .open_end or range.kids[1].tag == .open_end) return e.bridgeStmt(n);
        const saved_locals = e.locals.items.len;
        const base = try e.alloc(n);
        const limit = try e.alloc(n);
        const user = try e.alloc(n);
        std.debug.assert(limit == base + 1 and user == base + 2);
        try e.exprTo(range.kids[0], base);
        try e.exprTo(range.kids[1], limit);
        // an excluded end moves the limit by one (`1>..5` starts at 2, `1..<5` ends at 4)
        if (rt[0] == '>') _ = try e.emit(Inst.asbx(.step, base, 1), n.line);
        if (rt[rt.len - 1] == '<') _ = try e.emit(Inst.asbx(.step, limit, -1), n.line);
        try e.locals.append(e.a, .{ .name = n.kids[0].text, .reg = user });
        try e.enterLoop(n.text, n.kids[2]);
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

    // @eve-impl `for x in collection`: a list is visited by `iterprep` and `iterloop`, a map, a set, a string or a table as the list of its
    // elements, a range value, a channel, a generator or a stream by pulling one element at a time; `iterend` closes a generator or a stream
    // @spec spec/semantics/control.md#loops
    // @test test/bytecode/bc03_loops
    fn forEach(e: *Emitter, n: *const Node) Error!void {
        return e.forEachIn(n, n.kids[0]);
    }

    /// The two names of a loop or builder pattern `(k: v)` (the tree walker's `bindPattern` of a pair), or null.
    fn pairPattern(pat: *const Node) ?[2]*const Node {
        const pr = if (pat.tag == .list and pat.kids.len == 1) pat.kids[0] else pat;
        if (pr.tag != .pair or pr.kids.len != 2) return null;
        for (pr.kids) |k| if (k.tag != .name or std.mem.eql(u8, k.text, "_")) return null;
        if (std.mem.eql(u8, pr.kids[0].text, pr.kids[1].text)) return null;
        return .{ pr.kids[0], pr.kids[1] };
    }

    fn forEachIn(e: *Emitter, n: *const Node, pat: *const Node) Error!void {
        const src = n.kids[1];
        const saved_locals = e.locals.items.len;
        const base = try e.alloc(n);
        const pos = try e.alloc(n);
        const user = try e.alloc(n);
        std.debug.assert(pos == base + 1 and user == base + 2);
        try e.exprTo(src, base);
        const pair = pairPattern(pat);
        if (pair) |pr| {
            const kreg = try e.alloc(n);
            const vreg = try e.alloc(n);
            std.debug.assert(vreg == kreg + 1);
            try e.locals.append(e.a, .{ .name = pr[0].text, .reg = kreg });
            try e.locals.append(e.a, .{ .name = pr[1].text, .reg = vreg });
        } else try e.locals.append(e.a, .{ .name = pat.text, .reg = user });
        try e.enterLoop(n.text, n.kids[2]);
        const prep = try e.emit(Inst.asbx(.iterprep, base, 0), n.line);
        try e.xrefNode(n);
        const body = e.here();
        if (pair != null) _ = try e.emit(Inst.abc(.unpair, user, user + 1, 0), n.line);
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
        _ = try e.emit(Inst.abc(.iterend, base, 0, 0), n.line);
        e.free = e.floor();
        try e.block(n.kids[4]);
    }

    // ---- functions -----------------------------------------------------------------------

    // ---- captured locals ---------------------------------------------------------------------

    /// Every name that `n` mentions, except the parameters of `skip` (a lambda's own).
    fn mentioned(e: *Emitter, n: *const Node, skip: []const *const Node, out: *std.StringHashMapUnmanaged(void)) Error!void {
        if ((n.tag == .name or n.tag == .ref or n.tag == .star) and n.text.len > 0) {
            var own = false;
            for (skip) |p| if (std.mem.eql(u8, p.text, n.text)) {
                own = true;
            };
            if (!own) try out.put(e.a, n.text, {});
        }
        for (n.kids) |k| try e.mentioned(k, skip, out);
        for (n.extra) |k| try e.mentioned(k, skip, out);
    }

    /// The names that lambdas in `n` use from their routine.
    fn lambdaNames(e: *Emitter, n: *const Node, out: *std.StringHashMapUnmanaged(void)) Error!void {
        if (n.tag == .lambda) return e.mentioned(n.kids[1], n.kids[0].kids, out);
        // a routine declared in the body names the variables of its routine like a lambda does
        if ((n.tag == .function or n.tag == .procedure) and n.kids.len > 3) return e.mentioned(n.kids[3], n.kids[0].kids, out);
        for (n.kids) |k| try e.lambdaNames(k, out);
        for (n.extra) |k| try e.lambdaNames(k, out);
    }

    /// How many times `name` is declared in `n` (outside lambdas), and whether every declaration is a plain `new`/`set` of one name.
    fn declarations(n: *const Node, name: []const u8, count: *usize, plain: *bool) void {
        switch (n.tag) {
            .lambda, .function, .procedure => return,
            .var_decl, .set => {
                for (n.kids[0].kids) |t| if ((t.tag == .name or t.tag == .star) and std.mem.eql(u8, t.text, name)) {
                    count.* += 1;
                    if (n.kids[0].kids.len != 1 or n.kids.len != 2 or t.tag != .name) plain.* = false;
                };
            },
            .for_ => if (n.kids[0].tag == .name and std.mem.eql(u8, n.kids[0].text, name)) {
                count.* += 1;
                plain.* = false;
            } else if (n.kids[0].tag != .name) {
                count.* += 1;
                plain.* = false;
            },
            .capture => if (n.kids[1].tag == .name and std.mem.eql(u8, n.kids[1].text, name)) {
                count.* += 1;
                plain.* = false;
            },
            .builder => {
                // the pattern of a builder is local to it
                count.* += 1;
                plain.* = false;
            },
            else => {},
        }
        for (n.kids) |k| declarations(k, name, count, plain);
    }

    // @eve-impl the locals of a routine that its lambdas name live in the scope of the routine (`defvar`), where the lambda finds
    // them by name through its closure; the machine reads and writes them as any name outside the registers (`loadg`, `storeg`)
    // @spec design/design-bytecode.md#36-variables-captures-and-the-three-kinds-of-scope
    // @test test/bytecode/bc31_lambdas
    fn analyzeCaptures(e: *Emitter, n: *const Node, body: *const Node) Error!void {
        e.captured.clearRetainingCapacity();
        var used: std.StringHashMapUnmanaged(void) = .empty;
        try e.lambdaNames(body, &used);
        if (used.count() == 0) return;
        // the locals: parameters, results and the names declared in the body
        var it = used.keyIterator();
        while (it.next()) |name| {
            var count: usize = 0;
            var plain = true;
            if (n.tag != .process) {
                for (n.kids[0].kids) |p| if (std.mem.eql(u8, p.text, name.*)) {
                    count += 1;
                    if (p.tag != .param) plain = false;
                };
                if (n.tag != .lambda) for (n.kids[2].kids) |p| if (std.mem.eql(u8, p.text, name.*)) {
                    count += 1;
                    plain = false;
                };
            }
            declarations(body, name.*, &count, &plain);
            if (count == 0) continue; // not a local of the routine: a name of the aspect, a module, a built-in
            if (count > 1 or !plain) return e.unsupported(body, "a captured variable declared twice or not plainly");
            try e.captured.put(e.a, name.*, {});
        }
        if (e.captured.count() > 0 and !e.alone and n.tag != .process) return e.unsupported(n, "a routine with captured variables, called directly");
    }

    fn containsTag(n: *const Node, tag: ast.Tag) bool {
        if (n.tag == tag) return true;
        for (n.kids) |k| if (containsTag(k, tag)) return true;
        return false;
    }

    /// Every local of the routine with its register (for the blocks that run on the tree walker after the body: `recover`, `defer`).
    fn allLocals(e: *Emitter) Error![]chunk.NameReg {
        var names: std.ArrayList(chunk.NameReg) = .empty;
        for (e.locals.items) |l| try names.append(e.a, .{ .name = l.name, .reg = l.reg });
        return names.items;
    }

    /// `ret`: no result, the one result, or (C = the count) the list of the several results.
    fn emitRet(e: *Emitter, line: u32) Error!void {
        if (e.has_defer) _ = try e.emit(Inst.abc(.rundefers, 0, 0, 0), line);
        if (e.result_n > 1) {
            _ = try e.emit(Inst.abc(.ret, e.result_reg, 2, e.result_n), line);
        } else _ = try e.emit(Inst.abc(.ret, e.result_reg, if (e.result_reg == chunk.no_result) 0 else 1, 0), line);
    }

    // @eve-impl a lambda compiled alone: the parameters in the first registers, the value of the expression is the result; the names of the
    // routine that holds it are found in the scope (`loadg`, `storeg`), where the holder put them (`defvar`)
    // @spec spec/syntax/expressions.md#literals-and-builders
    // @test test/bytecode/bc31_lambdas
    fn lambdaFunction(e: *Emitter, n: *const Node) Error!void {
        e.locals.clearRetainingCapacity();
        e.free = 0;
        e.max_regs = 0;
        e.start = @intCast(e.code.items.len);
        e.in_process = false;
        e.result_reg = chunk.no_result;
        e.result_n = 0;
        e.has_defer = false;
        e.pending_defers.clearRetainingCapacity();
        e.scope_used = false;
        e.loops.clearRetainingCapacity();
        try e.analyzeCaptures(n, n.kids[1]);
        const nparams = try e.declareParams(n.kids[0].kids);
        const r = try e.alloc(n);
        try e.exprTo(n.kids[1], r);
        _ = try e.emit(Inst.abc(.ret, r, 1, 0), n.line);
        try e.funcs.append(e.a, .{
            .needs_scope = e.scope_used,
            .name = "lambda",
            .kind = "lambda",
            .nparams = nparams,
            .nregs = e.max_regs,
            .result = r,
            .start = e.start,
            .len = @intCast(e.code.items.len - e.start),
            .line = n.line,
            .file = ast.fileOf(n),
        });
    }

    /// Compile a function, a procedure or the process `main`.
    fn function(e: *Emitter, n: *const Node) Error!void {
        e.locals.clearRetainingCapacity();
        e.free = 0;
        e.max_regs = 0;
        e.start = @intCast(e.code.items.len);
        e.in_process = n.tag == .process;
        e.result_reg = chunk.no_result;
        e.result_n = 0;
        e.pending_defers.clearRetainingCapacity();
        e.scope_used = false;
        e.has_defer = n.tag != .process and containsTag(n.kids[3], .defer_stmt);
        e.loops.clearRetainingCapacity();
        var nparams: u8 = 0;
        var body: *const Node = undefined;
        try e.analyzeCaptures(n, if (n.tag == .process) n.kids[0] else n.kids[3]);
        if (n.tag == .process) {
            body = n.kids[0];
            nparams = try e.declareParams(n.kids[3].kids);
        } else {
            // the type list `(:T)` only guides the choice among overloads and the checker: the tree walker ignores it when the body runs
            nparams = try e.declareParams(n.kids[0].kids);
            const results = n.kids[2].kids;
            e.result_n = @intCast(results.len);
            for (results, 0..) |r, ri| {
                const reg = try e.declare(r, r.text);
                // several results are consecutive registers: `ret` makes the list of them
                if (ri == 0) e.result_reg = reg else if (reg != e.result_reg + ri) return e.unsupported(r, "results that do not share the registers in order");
                const zero_line = r.line;
                switch (if (r.ty) |t| t.tk else ast.TypeKind.none) {
                    .integer, .short, .byte => _ = try e.emit(Inst.asbx(.loadi, reg, 0), zero_line),
                    .real, .float => _ = try e.emit(Inst.abx(.loadk, reg, try e.konst(.{ .real = 0 })), zero_line),
                    .logic => _ = try e.emit(Inst.abc(.loadfalse, reg, 0, 0), zero_line),
                    .string => _ = try e.emit(Inst.abx(.loadk, reg, try e.konst(.{ .str = "" })), zero_line),
                    .none => if (r.ty) |t| {
                        // a list, a map, a Decimal, a class...: the zero of the tree walker; an array type with sizes stays there (a size may name a parameter)
                        if (t.kids.len > 0) return e.unsupported(r, "a result of an array type with sizes");
                        try e.xnodes.append(e.a, .{ .node = t, .names = &.{} });
                        _ = try e.emit(Inst.abx(.zero, reg, @intCast(e.xnodes.items.len - 1)), zero_line);
                    } else {
                        _ = try e.emit(Inst.abc(.loadnil, reg, 0, 0), zero_line);
                    },
                    else => {
                        if (r.ty.?.kids.len > 0) return e.unsupported(r, "a result of an array type with sizes");
                        try e.xnodes.append(e.a, .{ .node = r.ty.?, .names = &.{} });
                        _ = try e.emit(Inst.abx(.zero, reg, @intCast(e.xnodes.items.len - 1)), zero_line);
                    },
                }
            }
            body = n.kids[3];
        }
        if (e.in_process) {
            // a safe point follows each statement of the process body, as in the tree walker: the objects that nobody holds
            // any more are freed there (and their destructors run) at the same place in both engines
            for (body.kids) |s| {
                try e.stmt_pcs.append(e.a, @intCast(e.code.items.len - e.start));
                try e.statement(s);
                _ = try e.emit(Inst.abc(.safe, 0, 0, 0), s.line);
            }
            try e.stmt_pcs.append(e.a, @intCast(e.code.items.len - e.start));
            // `recover` and `finalize` run on the tree walker, with the variables of the process copied in and out
            if (n.kids[1].tag != .none or n.kids[2].tag != .none) {
                var names: std.ArrayList(chunk.NameReg) = .empty;
                for (e.locals.items) |l| try names.append(e.a, .{ .name = l.name, .reg = l.reg });
                if (n.kids[1].tag != .none) {
                    try e.xnodes.append(e.a, .{ .node = n.kids[1], .names = names.items });
                    e.recover_x = @intCast(e.xnodes.items.len - 1);
                }
                if (n.kids[2].tag != .none) {
                    try e.xnodes.append(e.a, .{ .node = n.kids[2], .names = names.items });
                    e.finalize_x = @intCast(e.xnodes.items.len - 1);
                }
            }
        } else try e.block(body);
        var recover_idx: u16 = chunk.no_x;
        const ret_pc: u32 = @intCast(e.code.items.len - e.start);
        if (e.in_process) {
            _ = try e.emit(Inst.abc(.halt, 0, 0, 0), n.line);
        } else {
            try e.emitRet(n.line);
            const names = try e.allLocals();
            for (e.pending_defers.items) |xi| e.xnodes.items[xi].names = names;
            // the `recover` block of a routine runs on the tree walker when an error leaves the body
            if (n.kids.len > 4) {
                try e.xnodes.append(e.a, .{ .node = n.kids[4], .names = names });
                recover_idx = @intCast(e.xnodes.items.len - 1);
            }
        }
        try e.funcs.append(e.a, .{
            .name = n.text,
            .kind = @tagName(n.tag),
            .nparams = nparams,
            .nregs = e.max_regs,
            .result = e.result_reg,
            .start = e.start,
            .len = @intCast(e.code.items.len - e.start),
            .line = n.line,
            .file = ast.fileOf(n),
            .recover = recover_idx,
            .ret_pc = ret_pc,
            .needs_scope = e.scope_used,
        });
    }
};

// @eve-impl compile an aspect to a chunk; function 0 is `process main`, the others follow in the order of the source
// @spec design/design-bytecode.md#9-stages
// @feature F-VM-04
/// Compile the aspect `root`. On `error.Unsupported` the `diag` says which construct and where. `known` names the function values
/// of the scopes above the aspect (imported functions).
pub fn compile(a: Alloc, root: *const Node, known: []const []const u8, diag: *Diag) Error!chunk.Chunk {
    var e: Emitter = .{ .a = a, .diag = diag, .known = known, .aspect_root = root };
    if (root.tag != .aspect) {
        diag.message = "the program is not a single aspect";
        diag.line = root.line;
        return error.Unsupported;
    }
    var main: ?*const Node = null;
    for (root.kids) |k| switch (k.tag) {
        .function, .procedure => try e.routines.append(a, k),
        // a private process is applied by name (`apply show(...)`): the tree walker runs it
        .process => if (std.mem.eql(u8, k.text, "main")) {
            main = k;
        },
        .none, .params => {},
        // declared by the tree walker before the machine starts (runRoot): the code reaches them by name
        .class, .trait, .adopt, .var_decl, .set, .generator, .table_decl, .import_decl, .method, .aspect => {},
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
        var trial: Emitter = .{ .a = a, .diag = diag, .routines = e.routines, .known = known, .aspect_root = root };
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
        .main_stmts = e.stmt_pcs.items,
        .recover = e.recover_x,
        .finalize = e.finalize_x,
    };
}

// @eve-impl compile one function or procedure alone (a routine of a module, of `lib/`, or one the tree walker calls): the chunk has the
// routine as function 0; every call in it is a `call` instruction, the routines of its unit are among `known`
// @spec design/design-bytecode.md#162-the-pivot-the-unit-of-the-bridge-is-the-routine-not-the-expression
// @test test/bytecode/bc24_routines
pub fn compileRoutine(a: Alloc, n: *const Node, known: []const []const u8, diag: *Diag) Error!chunk.Chunk {
    if (n.tag != .function and n.tag != .procedure and n.tag != .method and n.tag != .constructor and n.tag != .lambda) {
        diag.message = "only a function, a procedure, a method or a constructor is compiled alone";
        diag.line = n.line;
        return error.Unsupported;
    }
    var e: Emitter = .{ .a = a, .diag = diag, .known = known, .native = &.{}, .fidx = &.{}, .alone = true };
    if (n.tag == .lambda) try e.lambdaFunction(n) else try e.function(n);
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
    const c = try compile(arena.allocator(), tree, &.{}, &d);
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
        \\    print (1, 2, other: " ");
        \\    print 1;
        \\  return;
        \\end t;
    , &pd);
    var d: Diag = .{};
    const c = try compile(arena.allocator(), tree, &.{}, &d);
    try std.testing.expect(c.xnodes.len >= 1);
}
