//! @eve-module chunk
//! @spec design/design-bytecode.md#7-the-evb-file-rvm-r05
//! @feature F-VM-04
//! @decision D-201
//! @tests comp/evecm/src/chunk.zig (unit tests)
//! The compiled form of a program: the constants, the functions and their instructions, with the line of each
//! instruction. Made by `evecp.emit`, run by `evevm.bcvm`, written as text by `disassemble`. The `.evb` file of
//! stage B5.7 is this structure in binary.
const std = @import("std");
const Io = std.Io;
const op = @import("op.zig");
const ast = @import("ast.zig");

pub const Inst = op.Inst;

/// A constant of the program.
pub const Const = union(enum) { int: i64, real: f64, str: []const u8 };

pub const no_result: u8 = 255;

/// A variable of the function and the register that holds it.
pub const NameReg = struct { name: []const u8, reg: u8 };

// @eve-impl a piece of the tree that the tree walker runs for the bytecode machine (the bridge of stage B5.2)
// @invariant a chunk with xnodes can not be written as an .evb file: the bridge goes away when the constructs it carries are translated
/// An expression or a statement left to the tree walker, with the variables it reads (and, for a statement, may change).
pub const XNode = struct { node: *const ast.Node, names: []const NameReg };

/// One function (or procedure, or the main process): where its code is and how many registers it needs.
pub const Func = struct {
    name: []const u8,
    /// `function`, `procedure` or `process`.
    kind: []const u8,
    nparams: u8,
    nregs: u8,
    /// The register that holds the result, or `no_result`.
    result: u8,
    start: u32,
    len: u32,
    line: u32,
};

/// A whole program. `lines` has one entry for each instruction of `code`.
pub const Chunk = struct {
    consts: []const Const,
    funcs: []const Func,
    code: []const u32,
    lines: []const u32,
    /// The pieces of the tree that the tree walker runs (`evalx`, `execx`).
    xnodes: []const XNode = &.{},
    /// The index of the main process in `funcs`.
    main: u16,
};

// @eve-impl the readable listing of a chunk (`eve cp --disasm`)
// @spec design/design-bytecode.md#8-debugging-and-tools
/// Write the listing: one block for each function, one line for each instruction with its pc, its line and its operands.
pub fn disassemble(c: *const Chunk, w: *Io.Writer) Io.Writer.Error!void {
    for (c.funcs, 0..) |f, fi| {
        try w.print("{s} {s}  (function {d}, {d} registers, {d} parameters)\n", .{ f.kind, f.name, fi, f.nregs, f.nparams });
        var pc: u32 = 0;
        while (pc < f.len) : (pc += 1) {
            const at = f.start + pc;
            const i = Inst.fromWord(c.code[at]);
            try w.print("  {d:4}  line {d:<4} {s:<8}", .{ pc, c.lines[at], @tagName(i.op) });
            switch (i.op) {
                .move, .neg, .not, .setlike => try w.print(" r{d} r{d}", .{ i.a, i.b }),
                .loadk => {
                    try w.print(" r{d} k{d}", .{ i.a, i.bx() });
                    switch (c.consts[i.bx()]) {
                        .int => |v| try w.print("    ; {d}", .{v}),
                        .real => |v| try w.print("    ; {d}", .{v}),
                        .str => |v| try w.print("    ; \"{s}\"", .{v}),
                    }
                },
                .loadi => try w.print(" r{d} {d}", .{ i.a, i.sbx() }),
                .loadnil, .loadtrue, .loadfalse, .expect => try w.print(" r{d}", .{i.a}),
                .add, .sub, .mul, .div, .mod, .eq, .ne, .lt, .le, .gt, .ge => try w.print(" r{d} r{d} r{d}", .{ i.a, i.b, i.c }),
                .jmp => try w.print(" -> {d}", .{@as(i64, pc) + 1 + i.sbx()}),
                .jf, .jt, .forprep, .forloop => try w.print(" r{d} -> {d}", .{ i.a, @as(i64, pc) + 1 + i.sbx() }),
                .callf => try w.print(" r{d} f{d} args {d}    ; {s}", .{ i.a, i.c, i.b, c.funcs[i.c].name }),
                .ret => try w.print(" r{d} {s}", .{ i.a, if (i.b == 1) "value" else "none" }),
                .print => try w.print(" r{d} x{d} {s}", .{ i.a, i.b, if (i.c == 1) "print" else "write" }),
                .augment => try w.print(" r{d} r{d} {s}", .{ i.a, i.b, @tagName(@as(op.Op, @enumFromInt(i.c))) }),
                .coerce => try w.print(" r{d} {s}", .{ i.a, @tagName(@as(ast.TypeKind, @enumFromInt(i.b))) }),
                .evalx => try w.print(" r{d} x{d}    ; tree walker: {s}", .{ i.a, i.bx(), @tagName(c.xnodes[i.bx()].node.tag) }),
                .execx => try w.print(" x{d}    ; tree walker: {s}", .{ i.bx(), @tagName(c.xnodes[i.bx()].node.tag) }),
                .binx => try w.print(" r{d} r{d} r{d}", .{ i.a, i.b, i.c }),
                .extra => try w.print(" k{d}", .{i.bx()}),
                .new_list, .new_map => try w.print(" r{d}", .{i.a}),
                .list_push, .set_add => try w.print(" r{d} r{d}", .{ i.a, i.b }),
                .list_index, .map_get => try w.print(" r{d} r{d} r{d}", .{ i.a, i.b, i.c }),
                .list_set, .map_set => try w.print(" r{d} r{d} r{d}", .{ i.a, i.b, i.c }),
                .set_has => try w.print(" r{d} r{d} r{d}", .{ i.a, i.b, i.c }),
                .length => try w.print(" r{d} r{d}", .{ i.a, i.b }),
                .call_method => try w.print(" r{d} r{d} x{d}", .{ i.a, i.b, i.bx() }),
                .over, .halt => {},
            }
            try w.writeByte('\n');
        }
    }
}

test "the listing names the instructions" {
    const code = [_]u32{ Inst.asbx(.loadi, 0, 7).word(), Inst.abc(.print, 0, 1, 1).word(), Inst.abc(.halt, 0, 0, 0).word() };
    const lines = [_]u32{ 1, 2, 2 };
    const funcs = [_]Func{.{ .name = "main", .kind = "process", .nparams = 0, .nregs = 1, .result = no_result, .start = 0, .len = 3, .line = 1 }};
    const c: Chunk = .{ .consts = &.{}, .funcs = &funcs, .code = &code, .lines = &lines, .main = 0 };
    var buf: [512]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try disassemble(&c, &w);
    try std.testing.expect(std.mem.indexOf(u8, w.buffered(), "loadi    r0 7") != null);
    try std.testing.expect(std.mem.indexOf(u8, w.buffered(), "print    r0 x1 print") != null);
}
