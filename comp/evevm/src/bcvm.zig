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

// @eve-impl run the aspect `root` on the bytecode machine: compile, then execute from `process main`
// @spec design/design-bytecode.md#9-stages
// @see comp/evevm/src/interp/datatypes.zig:runRoot
/// The bytecode counterpart of `Interp.runRoot`. A construct the emitter does not know yet is an error with its line.
pub fn runRoot(it: *Interp, root: *const Node) Signal!void {
    var diag: evecp.emit.Diag = .{};
    const c = evecp.emit.compile(it.a, root, &diag) catch |e| switch (e) {
        error.Unsupported => {
            it.line = diag.line;
            return it.fail("bytecode: {s} is not supported yet", .{diag.message});
        },
        error.OutOfMemory => return error.OutOfMemory,
    };
    try it.frames.append(it.a, .{ .kind = "aspect", .name = root.text, .call_line = it.line });
    defer _ = it.frames.pop();
    try execute(it, &c);
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
                    else => return it.fail("cannot negate {s}", .{Interp.typeName(v)}),
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
                if (lo != .int or hi != .int) {
                    it.line = c.lines[at];
                    return it.fail("bytecode: a for loop over something other than integers is not supported yet", .{});
                }
                if (lo.int > hi.int) {
                    fr.pc = @intCast(@as(i64, fr.pc) + i.sbx());
                } else regs[i.a + 2] = lo;
            },
            .forloop => {
                const next = regs[i.a].int + 1;
                if (next <= regs[i.a + 1].int) {
                    regs[i.a] = .{ .int = next };
                    regs[i.a + 2] = .{ .int = next };
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
            .over, .halt => return,
        }
    }
}
