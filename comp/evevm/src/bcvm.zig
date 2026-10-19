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
// @see comp/evevm/src/interp/datatypes.zig:runRoot
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
    try execute(it, &c);
    return true;
}

// @eve-impl the loop of the machine: fetch, decode, do; a call pushes a frame, `ret` pops it
// @perf hot
fn execute(it: *Interp, c: *const chunk.Chunk) Signal!void {
    const b = it.base();
    var frames: std.ArrayList(Frame) = .empty;
    try grow(it, 4096);
    const main = c.funcs[c.main];
    try grow(it, main.nregs);
    b.bc_top = main.nregs;
    try frames.append(it.a, .{ .func = c.main, .pc = 0, .base = 0 });
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
            .over, .halt => return,
        }
    }
}
