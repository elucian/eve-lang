//! @eve-module bcvm
//! @spec design/design-bytecode.md#3-the-target
//! @feature F-VM-04
//! @decision D-201
//! @tests test/level1 with `--engine bc` (`python script/runtest.py 1 --engine bc`)
//! The bytecode machine, stage B5.2: runs a `Chunk` made by `evecp.emit` on the services of the interpreter (heap,
//! output, `show`, `applyOp`, errors), so values, messages and exit codes are those of the tree walker. A call does
//! not recurse in Zig: it pushes a frame and the loop goes on.
const std = @import("std");
const evecm = @import("evecm");
const evecp = @import("evecp");
const interp = @import("interp.zig");
const chunk = evecm.chunk;
const Inst = evecm.op.Inst;
const ast = evecm.ast;
const Interp = interp.Interp;
const Value = interp.Value;
const Signal = interp.Signal;
const Node = interp.Node;

const Frame = struct {
    func: u16,
    /// The next instruction, relative to the start of the function.
    pc: u32,
    /// The first register of the frame in the stack.
    base: u32,
};

/// True for the values that live outside the heap: a register that holds one can be overwritten without a count.
inline fn heapless(v: Value) bool {
    return switch (v) {
        .nil, .bool, .int, .nat, .byte, .short, .huge, .real, .float, .dec, .instant, .sym => true,
        else => false,
    };
}

// @eve-impl write a register: the new value is counted, the old one let go (the rule of `setVar` for a register)
// @invariant every register above the top of the stack holds a value without a heap object
// @perf hot
inline fn put(it: *Interp, slot: *Value, v: Value) void {
    if (heapless(slot.*) and heapless(v)) {
        slot.* = v;
    } else it.setCell(slot, v);
}

/// Make room for `need` registers; the new ones are null. The pointers into the stack are taken again after a call.
fn grow(it: *Interp, need: usize) Signal!void {
    const b = it.base();
    if (need <= b.bc_stack.len) return;
    var n = @max(b.bc_stack.len * 2, 4096);
    while (n < need) n *= 2;
    if (n > (1 << 22)) return it.fail("StackOverflow: the calls are nested too deeply", .{});
    const old = b.bc_stack;
    const fresh = try it.a.alloc(Value, n);
    @memcpy(fresh[0..old.len], old);
    @memset(fresh[old.len..], .nil);
    b.bc_stack = fresh;
}

fn opText(o: evecm.op.Op) []const u8 {
    return switch (o) {
        .add => "+",
        .sub => "-",
        .mul => "*",
        .div => "/",
        .mod => "%",
        .eq => "==",
        .ne => "<>",
        .lt => "<",
        .le => "<=",
        .gt => ">",
        .ge => ">=",
        else => "?",
    };
}

fn astOp(o: evecm.op.Op) ast.Op {
    return switch (o) {
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
        else => .other,
    };
}

/// Print why a program runs on the tree walker (`EVE_BC_TRACE=1`).
pub var trace: bool = false;

// @eve-impl run `process main` on the bytecode machine; false when the emitter can not translate it (the tree walker then runs it)
// @spec design/design-bytecode.md#9-stages
// @see code/evevm/src/interp/datatypes.zig:runRoot
/// The bytecode counterpart of `runProcess` for `main`: true when it ran, false when the program stays with the tree walker.
pub fn runMain(it: *Interp, root: *const Node, main: *const Node) Signal!bool {
    _ = main;
    var diag: evecp.emit.Diag = .{};
    const c = evecp.emit.compile(it.a, root, &diag) catch |e| switch (e) {
        error.Unsupported => {
            if (trace) std.debug.print("bytecode: the tree walker runs this program: {s} (line {d})\n", .{ diag.message, diag.line });
            return false;
        },
        error.OutOfMemory => return error.OutOfMemory,
    };
    const saved = try it.pushScope();
    defer it.leaveScope(saved);
    it.setProc(it.scope);
    try it.frames.append(it.a, .{ .kind = "aspect", .name = root.text, .call_line = it.line });
    defer _ = it.frames.pop();
    const jobs = try it.newMap();
    try it.define("jobs", .{ .map = jobs }, false);
    it.regionIn();
    defer it.regionOut();
    // @eve-impl the process `main` with `recover` and `finalize` (the loop of `runProcess` on the bytecode): an error leaves `execute`,
    // `recover` runs on the tree walker with the variables copied in and out, `retry` and `resume` start again at a statement
    // @spec spec/semantics/errors.md#recover
    // @test test/bytecode/bc14_recover
    const frames_len = it.frames.items.len;
    const m = c.funcs[c.main];
    var entry: u32 = 0;
    var failed: ?Signal = null;
    while (true) {
        execute(it, &c, entry) catch |e| {
            // the frames of the calls that the error left, and their registers, are gone
            it.frames.shrinkRetainingCapacity(frames_len);
            const b = it.base();
            for (b.bc_stack[m.nregs..@max(b.bc_top, m.nregs)]) |*slot| put(it, slot, .nil);
            b.bc_top = m.nregs;
            switch (e) {
                error.Raise => {
                    if (c.recover == chunk.no_x) {
                        failed = e;
                        break;
                    }
                    var k: usize = 0;
                    const pc = b.bc_main_pc -| 1;
                    while (k + 2 < c.main_stmts.len and c.main_stmts[k + 1] <= pc) k += 1;
                    const idx = it.reports.items.len - 1;
                    runBlock(it, &c, b.bc_stack.ptr, c.recover, true) catch |re| switch (re) {
                        error.Retry => {
                            entry = c.main_stmts[k];
                            continue;
                        },
                        error.Resume => {
                            it.reports.items[idx].handled = true;
                            entry = c.main_stmts[k + 1];
                            continue;
                        },
                        error.Abort => {
                            failed = error.Raise;
                            break;
                        },
                        error.Over, error.Exit => break,
                        error.Raise => {
                            failed = re;
                            break;
                        },
                        else => return re,
                    };
                    it.reports.items[idx].handled = true;
                    break;
                },
                error.Over, error.Exit => break,
                else => return e,
            }
        };
        break;
    }
    it.collectAtDone(); // the end of a process is a `done` too
    if (c.finalize != chunk.no_x) try runBlock(it, &c, it.base().bc_stack.ptr, c.finalize, false);
    if (failed) |f| return f;
    return true;
}

// @eve-impl a `recover` or `finalize` block on the tree walker: the variables of the process are copied in, and copied back also when the block ends with `retry`, `resume` or an error
fn runBlock(it: *Interp, c: *const chunk.Chunk, regs: [*]Value, xi: u16, with_error: bool) Signal!void {
    const x = c.xnodes[xi];
    const mark = it.scratch.mark();
    defer it.scratch.release(mark);
    const outer = try it.pushScope();
    defer it.leaveScope(outer);
    const scope = it.scope;
    for (x.names) |nm| try it.define(nm.name, regs[nm.reg], false);
    if (with_error) try it.define("$error", try it.errorObject(), false);
    var result: Signal!void = {};
    it.execBlock(x.node) catch |e| {
        result = e;
    };
    for (x.names) |nm| if (scope.find(nm.name)) |cell| put(it, &regs[nm.reg], cell.value);
    return result;
}

// @eve-impl the rare case of a fast instruction: the expression `xnode` runs on the tree walker and its value goes to `dst`
fn evalSlow(it: *Interp, c: *const chunk.Chunk, regs: [*]Value, xi: u16, dst: *Value) Signal!void {
    const x = c.xnodes[xi];
    const mark = it.scratch.mark();
    defer it.scratch.release(mark);
    const outer = try it.pushScope();
    defer it.leaveScope(outer);
    for (x.names) |nm| try it.define(nm.name, regs[nm.reg], false);
    const v = try it.eval(x.node);
    put(it, dst, v);
}

// @eve-impl the rare case of a fast instruction: the statement `xnode` runs on the tree walker, the variables it names are copied back
fn execSlow(it: *Interp, c: *const chunk.Chunk, regs: [*]Value, xi: u16) Signal!void {
    const x = c.xnodes[xi];
    const mark = it.scratch.mark();
    defer it.scratch.release(mark);
    const outer = try it.pushScope();
    defer it.leaveScope(outer);
    const scope = it.scope;
    for (x.names) |nm| try it.define(nm.name, regs[nm.reg], false);
    try it.exec(x.node);
    for (x.names) |nm| if (scope.find(nm.name)) |cell| put(it, &regs[nm.reg], cell.value);
}

// @eve-impl the loop of the machine: fetch, decode, do; a call pushes a frame, `ret` pops it
// @perf hot
fn execute(it: *Interp, c: *const chunk.Chunk, entry: u32) Signal!void {
    const b = it.base();
    var frames: std.ArrayList(Frame) = .empty;
    try grow(it, 4096);
    const main = c.funcs[c.main];
    try grow(it, main.nregs);
    b.bc_top = main.nregs;
    try frames.append(it.a, .{ .func = c.main, .pc = entry, .base = 0 });
    // the pc of the main frame when an error leaves: the statement that failed (`recover`, `retry`, `resume`)
    errdefer b.bc_main_pc = frames.items[0].pc;
    var fr: *Frame = &frames.items[frames.items.len - 1];
    var func = c.funcs[fr.func];
    var regs: [*]Value = b.bc_stack.ptr + fr.base;
    while (true) {
        const at = func.start + fr.pc;
        const i = Inst.fromWord(c.code[at]);
        fr.pc += 1;
        switch (i.op) {
            .move => put(it, &regs[i.a], regs[i.b]),
            .loadk => put(it, &regs[i.a], switch (c.consts[i.bx()]) {
                .int => |v| Value{ .int = v },
                .real => |v| Value{ .real = v },
                .str => |s| blk: {
                    it.line = c.lines[at];
                    break :blk try it.staticStr(s);
                },
            }),
            .loadi => put(it, &regs[i.a], .{ .int = i.sbx() }),
            .loadg => {
                it.line = c.lines[at];
                put(it, &regs[i.a], try it.lookup(c.consts[i.bx()].str));
            },
            .loadnil => put(it, &regs[i.a], .nil),
            .loadtrue => put(it, &regs[i.a], .{ .bool = true }),
            .loadfalse => put(it, &regs[i.a], .{ .bool = false }),
            .add, .sub, .mul, .div, .mod, .eq, .ne, .lt, .le, .gt, .ge => {
                const l = regs[i.b];
                const r = regs[i.c];
                it.line = c.lines[at];
                put(it, &regs[i.a], try it.applyOp(astOp(i.op), opText(i.op), l, r));
            },
            .neg => {
                const v = regs[i.b];
                it.line = c.lines[at];
                put(it, &regs[i.a], switch (v) {
                    .int, .nat, .byte, .short => |x| Value{ .int = -x },
                    .real, .float => |x| Value{ .real = -x },
                    else => try it.negate(v),
                });
            },
            .not => {
                it.line = c.lines[at];
                put(it, &regs[i.a], .{ .bool = !(try it.truth(regs[i.b])) });
            },
            .jmp => {
                const off = i.sbx();
                fr.pc = @intCast(@as(i64, fr.pc) + off);
                if (off < 0) it.h.safePoint();
            },
            .jf, .jt => {
                const v = regs[i.a];
                const t = if (v == .bool) v.bool else blk: {
                    it.line = c.lines[at];
                    break :blk try it.truth(v);
                };
                if (t == (i.op == .jt)) fr.pc = @intCast(@as(i64, fr.pc) + i.sbx());
            },
            .forprep => {
                const lo = regs[i.a];
                const hi = regs[i.a + 1];
                const is_sym = lo == .sym and hi == .sym;
                if (!is_sym and (lo != .int or hi != .int)) {
                    it.line = c.lines[at];
                    return it.fail("bytecode: a for loop over something other than integers or runes is not supported yet", .{});
                }
                const l: i64 = if (is_sym) lo.sym else lo.int;
                const h: i64 = if (is_sym) hi.sym else hi.int;
                if (l > h) {
                    fr.pc = @intCast(@as(i64, fr.pc) + i.sbx());
                } else regs[i.a + 2] = lo;
            },
            .forloop => {
                const is_sym = regs[i.a] == .sym;
                const next = (if (is_sym) @as(i64, regs[i.a].sym) else regs[i.a].int) + 1;
                if (next <= (if (is_sym) @as(i64, regs[i.a + 1].sym) else regs[i.a + 1].int)) {
                    regs[i.a] = if (is_sym) .{ .sym = @intCast(next) } else .{ .int = next };
                    regs[i.a + 2] = regs[i.a];
                    fr.pc = @intCast(@as(i64, fr.pc) + i.sbx());
                    it.h.safePoint();
                }
            },
            .callf => {
                const callee = c.funcs[i.c];
                it.line = c.lines[at];
                const base: u32 = fr.base + i.a + 1;
                try grow(it, base + callee.nregs);
                try it.frames.append(it.a, .{ .kind = callee.kind, .name = callee.name, .call_line = it.line });
                try frames.append(it.a, .{ .func = i.c, .pc = 0, .base = base });
                b.bc_top = base + callee.nregs;
                fr = &frames.items[frames.items.len - 1];
                func = callee;
                regs = b.bc_stack.ptr + fr.base;
            },
            .ret => {
                const done = frames.pop().?;
                _ = it.frames.pop();
                const callee_regs = b.bc_stack.ptr + done.base;
                // the result goes to the register of the caller that held the function's place (A of the call)
                const dst = b.bc_stack.ptr + done.base - 1;
                if (i.b == 1) put(it, &dst[0], callee_regs[i.a]) else put(it, &dst[0], .nil);
                var k: usize = 0;
                while (k < func.nregs) : (k += 1) put(it, &callee_regs[k], .nil);
                fr = &frames.items[frames.items.len - 1];
                func = c.funcs[fr.func];
                regs = b.bc_stack.ptr + fr.base;
                b.bc_top = fr.base + func.nregs;
            },
            .print => {
                const mark = it.scratch.mark();
                defer it.scratch.release(mark);
                it.line = c.lines[at];
                var buf: std.ArrayList(u8) = .empty;
                var k: usize = 0;
                while (k < i.b) : (k += 1) {
                    if (k > 0 and i.c == 1) try buf.append(it.t, ',');
                    try it.show(&buf, regs[i.a + k], false);
                }
                if (i.c == 1) try buf.append(it.t, '\n');
                try it.out.writeAll(buf.items);
            },
            .expect => {
                it.line = c.lines[at];
                if (!try it.truth(regs[i.a])) return it.failWith(interp.err_expect, "expect failed", .{});
            },
            .setlike => {
                const v = regs[i.b];
                put(it, &regs[i.a], if (heapless(regs[i.a]) and heapless(v) and (regs[i.a] == .int or regs[i.a] == .bool or regs[i.a] == .nil)) v else Interp.coerceLike(regs[i.a], v));
            },
            .augment => {
                it.line = c.lines[at];
                const o: evecm.op.Op = @enumFromInt(i.c);
                const cur = regs[i.a];
                const v = regs[i.b];
                if (cur == .list or cur == .set or v == .list or v == .set) {
                    if (try it.augmentValue(astOp(o), opText(o), cur, v)) |nv| put(it, &regs[i.a], nv);
                } else put(it, &regs[i.a], try it.applyOp(astOp(o), opText(o), cur, v));
            },
            .coerce => {
                const tk: ast.TypeKind = @enumFromInt(i.b);
                const v = regs[i.a];
                switch (tk) {
                    .real => if (Interp.isInt(v)) put(it, &regs[i.a], .{ .real = @floatFromInt(Interp.intOf(v)) }) else put(it, &regs[i.a], Interp.coerceLike(.{ .real = 0 }, v)),
                    .integer => if (v == .real or v == .float) put(it, &regs[i.a], .{ .int = @intFromFloat(Interp.realOf(v).?) }),
                    else => {},
                }
            },
            .binx => {
                const next = Inst.fromWord(c.code[at + 1]);
                fr.pc += 1;
                it.line = c.lines[at];
                put(it, &regs[i.a], try it.apply(c.consts[next.bx()].str, regs[i.b], regs[i.c]));
            },
            .extra => unreachable,
            .evalx => {
                const x = c.xnodes[i.bx()];
                it.line = c.lines[at];
                const mark = it.scratch.mark();
                defer it.scratch.release(mark);
                const outer = try it.pushScope();
                defer it.leaveScope(outer);
                for (x.names) |nm| try it.define(nm.name, regs[nm.reg], false);
                const v = try it.eval(x.node);
                put(it, &regs[i.a], v);
            },
            .execx => {
                const x = c.xnodes[i.bx()];
                it.line = c.lines[at];
                const mark = it.scratch.mark();
                defer it.scratch.release(mark);
                const outer = try it.pushScope();
                defer it.leaveScope(outer);
                const scope = it.scope;
                for (x.names) |nm| try it.define(nm.name, regs[nm.reg], false);
                try it.exec(x.node);
                for (x.names) |nm| if (scope.find(nm.name)) |cell| put(it, &regs[nm.reg], cell.value);
            },
            .new_list => put(it, &regs[i.a], .{ .list = try it.h.make(interp.List, .{ .array = i.b == 1 }) }),
            .new_map => put(it, &regs[i.a], .{ .map = try it.newMap() }),
            .new_set => put(it, &regs[i.a], .{ .set = try it.h.make(interp.List, .{}) }),
            .list_push => try it.listAppend(regs[i.a].list, regs[i.b]),
            .set_add => {
                it.line = c.lines[at];
                try it.setAdd(regs[i.a].set, regs[i.b]);
            },
            .map_set => {
                it.line = c.lines[at];
                try it.mapPut(regs[i.a].map, regs[i.b], regs[i.c]);
            },
            .index => {
                const x = Inst.fromWord(c.code[at + 1]);
                fr.pc += 1;
                it.line = c.lines[at];
                const key = regs[i.c];
                switch (regs[i.b]) {
                    .list => |l| if (key == .int and !Interp.isMatrix(l)) {
                        const items = l.elems();
                        const k = if (key.int < 0) @as(i64, @intCast(items.len)) + 1 + key.int else key.int;
                        if (k >= 1 and k <= items.len) {
                            put(it, &regs[i.a], items[@intCast(k - 1)]);
                            continue;
                        }
                    },
                    .map => |m| if (Interp.mapFind(m, key)) |at_key| {
                        put(it, &regs[i.a], m.entries.items[at_key].val);
                        continue;
                    },
                    else => {},
                }
                try evalSlow(it, c, regs, x.bx(), &regs[i.a]);
            },
            .index_set => {
                const x = Inst.fromWord(c.code[at + 1]);
                fr.pc += 1;
                it.line = c.lines[at];
                const key = regs[i.b];
                switch (regs[i.a]) {
                    .list => |l| if (key == .int and !Interp.isMatrix(l)) {
                        const items = l.elems();
                        const k = if (key.int < 0) @as(i64, @intCast(items.len)) + 1 + key.int else key.int;
                        if (k >= 1 and k <= items.len) {
                            it.setCell(&items[@intCast(k - 1)], regs[i.c]);
                            continue;
                        }
                    },
                    .map => |m| {
                        try it.mapPut(m, key, regs[i.c]);
                        continue;
                    },
                    else => {},
                }
                try execSlow(it, c, regs, x.bx());
            },
            .push => {
                const x = Inst.fromWord(c.code[at + 1]);
                fr.pc += 1;
                it.line = c.lines[at];
                switch (regs[i.a]) {
                    .list => |l| if (regs[i.b] != .list and l.base == null) {
                        try it.listAppend(l, regs[i.b]);
                        continue;
                    },
                    .set => |l| {
                        try it.setAdd(l, regs[i.b]);
                        continue;
                    },
                    else => {},
                }
                try execSlow(it, c, regs, x.bx());
            },
            .length => {
                const x = Inst.fromWord(c.code[at + 1]);
                fr.pc += 1;
                it.line = c.lines[at];
                const v = regs[i.b];
                const len: ?i64 = switch (v) {
                    .str => @intCast(std.unicode.utf8CountCodepoints(v.str) catch v.str.len),
                    .list, .set => |l| @intCast(l.elems().len),
                    .map => |m| @intCast(m.entries.items.len),
                    else => null,
                };
                if (len) |n| {
                    put(it, &regs[i.a], .{ .int = n });
                } else try evalSlow(it, c, regs, x.bx(), &regs[i.a]);
            },
            .xref => unreachable,
            .interp => {
                const x = Inst.fromWord(c.code[at + 1]);
                fr.pc += 1;
                it.line = c.lines[at];
                const mark = it.scratch.mark();
                defer it.scratch.release(mark);
                var buf: std.ArrayList(u8) = .empty;
                for (c.xnodes[x.bx()].node.kids, 0..) |part, k| {
                    if (part.tag == .str) {
                        try buf.appendSlice(it.t, part.text);
                    } else try buf.appendSlice(it.t, try it.format(part.text[0], part.text[1..], regs[i.b + k]));
                }
                put(it, &regs[i.a], .{ .str = try it.persist(buf.items) });
            },
            .iterprep => {
                const x = Inst.fromWord(c.code[at + 1]);
                fr.pc += 1;
                it.line = c.lines[at];
                const src = regs[i.a];
                switch (src) {
                    .list => {},
                    .map, .set, .str => {
                        // the elements are listed once: the pairs of a map are made here and live through every pass
                        const items = try it.iterate(src);
                        const snap = try it.h.make(interp.List, .{});
                        for (items) |e| try it.listAppend(snap, e);
                        put(it, &regs[i.a], .{ .list = snap });
                    },
                    else => {
                        // a range, a channel, a generator, a stream, a table: the tree walker runs the whole loop
                        try execSlow(it, c, regs, x.bx());
                        fr.pc = @intCast(@as(i64, fr.pc) + i.sbx() - 2); // the jump counts from the word after iterprep; the landing is the jmp before the else block
                        continue;
                    },
                }
                const items = regs[i.a].list.elems();
                if (items.len == 0) {
                    fr.pc = @intCast(@as(i64, fr.pc) + i.sbx() - 1); // counted from the word after iterprep, before the xref word
                } else {
                    regs[i.a + 1] = .{ .int = 1 };
                    put(it, &regs[i.a + 2], items[0]);
                }
            },
            .iterloop => {
                const items = regs[i.a].list.elems();
                const next = regs[i.a + 1].int + 1;
                if (next <= items.len) {
                    regs[i.a + 1] = .{ .int = next };
                    put(it, &regs[i.a + 2], items[@intCast(next - 1)]);
                    fr.pc = @intCast(@as(i64, fr.pc) + i.sbx());
                    it.h.safePoint();
                }
            },
            .safe => it.safe(),
            .over, .halt => return,
        }
    }
}
