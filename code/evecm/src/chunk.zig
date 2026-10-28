//! @eve-module chunk
//! @spec design/design-bytecode.md#7-the-evb-file-rvm-r05
//! @feature F-VM-04
//! @decision D-201
//! @tests code/evecm/src/chunk.zig (unit tests)
//! The compiled form of a program: the constants, the functions and their instructions, with the line of each
//! instruction. Made by `evecp.emit`, run by `evevm.bcvm`, written as text by `disassemble`. The `.evb` file of
//! stage B5.7 is this structure in binary.
const std = @import("std");
const Io = std.Io;
const op = @import("op.zig");
const ast = @import("ast.zig");

pub const Inst = op.Inst;

/// A constant of the program.
pub const Const = union(enum) { int: i64, real: f64, str: []const u8, rat: [2]i64, cpx: [2]f64, dur: i64 };

pub const no_result: u8 = 255;

/// The index of an xnode that is not there.
pub const no_x: u16 = 65535;

/// A variable of the function and the register that holds it.
/// A variable of a bridged piece or a call site, with its register. `back` is the register of the variable that an `@` argument
/// of a call site writes back to when the call returns (`no_back` when the name is not such an argument).
pub const NameReg = struct { name: []const u8, reg: u8, back: u8 = no_back };

pub const no_back: u8 = 255;

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
    /// The file of a routine that does not belong to the main script (a module), for the traces; empty otherwise.
    file: []const u8 = "",
    /// The `recover` block of a routine as an xnode that names all its variables, or `no_x`.
    recover: u16 = no_x,
    /// Where a routine continues, relative to its start, after its `recover` block handled an error: its `ret` (before it, `rundefers`).
    ret_pc: u32 = 0,
    /// The routine defines names in its own scope (`defvar`, reference parameters, `closure`, job and parallel blocks, `update`): each call
    /// gets a scope. Without it the call runs in the scope of its closure and makes no object (RC-03).
    needs_scope: bool = true,
    /// The routine can reach a safe point (a loop, a block, a call that the machine does not know to be free of them): its frame is a
    /// region. Without one, nothing in it can free the temporaries of its caller, and the call needs no region (RC-05, OPT-28).
    needs_region: bool = true,
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
    /// The first instruction (relative to `main`) of each statement of the body of the process, and the one after the last: where
    /// `retry` and `resume` of its `recover` go on.
    main_stmts: []const u32 = &.{},
    /// The `recover` and `finalize` blocks of the process, as xnodes that name all its variables, or `no_x`.
    recover: u16 = no_x,
    finalize: u16 = no_x,
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
                .move, .neg, .not, .setlike, .unpair, .updbegin, .updend, .rundefers, .yield => try w.print(" r{d} r{d}", .{ i.a, i.b }),
                .loadk => {
                    try w.print(" r{d} k{d}", .{ i.a, i.bx() });
                    switch (c.consts[i.bx()]) {
                        .int => |v| try w.print("    ; {d}", .{v}),
                        .real => |v| try w.print("    ; {d}", .{v}),
                        .str => |v| try w.print("    ; \"{s}\"", .{v}),
                        .dur => |v| try w.print("    ; duration {d} us", .{v}),
                        .cpx => |v| try w.print("    ; (i{d} imaginary, real {d})", .{ v[1], v[0] }),
                        .rat => |v| try w.print("    ; {d}\\{d}", .{ v[0], v[1] }),
                    }
                },
                .loadg => try w.print(" r{d} k{d}    ; {s}", .{ i.a, i.bx(), c.consts[i.bx()].str }),
                .storeg => try w.print(" r{d} x{d}    ; {s} {s}", .{ i.a, i.bx(), c.xnodes[i.bx()].node.kids[0].text, c.xnodes[i.bx()].node.text }),
                .loadi => try w.print(" r{d} {d}", .{ i.a, i.sbx() }),
                .loadnil, .loadtrue, .loadfalse, .expect => try w.print(" r{d}", .{i.a}),
                .add, .sub, .mul, .div, .mod, .eq, .ne, .lt, .le, .gt, .ge, .pow => try w.print(" r{d} r{d} r{d}", .{ i.a, i.b, i.c }),
                .jmp => try w.print(" -> {d}", .{@as(i64, pc) + 1 + i.sbx()}),
                .jf, .jt, .jnn, .forprep, .forloop => try w.print(" r{d} -> {d}", .{ i.a, @as(i64, pc) + 1 + i.sbx() }),
                .callf => try w.print(" r{d} f{d} args {d}    ; {s}", .{ i.a, i.c, i.b, c.funcs[i.c].name }),
                .ret => try w.print(" r{d} {s}", .{ i.a, if (i.b == 1) "value" else if (i.b == 2) "list" else "none" }),
                .print => try w.print(" r{d} x{d} {s}", .{ i.a, i.b, if (i.c == 1) "print" else "write" }),
                .augment => try w.print(" r{d} r{d} {s}", .{ i.a, i.b, @tagName(@as(op.Op, @enumFromInt(i.c))) }),
                .coerce => try w.print(" r{d} {s}", .{ i.a, @tagName(@as(ast.TypeKind, @enumFromInt(i.b))) }),
                .evalx => try w.print(" r{d} x{d}    ; tree walker: {s}", .{ i.a, i.bx(), @tagName(c.xnodes[i.bx()].node.tag) }),
                .execx => try w.print(" x{d}    ; tree walker: {s}", .{ i.bx(), @tagName(c.xnodes[i.bx()].node.tag) }),
                .binx => try w.print(" r{d} r{d} r{d}", .{ i.a, i.b, i.c }),
                .extra => try w.print(" k{d}", .{i.bx()}),
                .new_list, .new_map, .new_set => try w.print(" r{d}", .{i.a}),
                .list_push, .set_add, .push => try w.print(" r{d} r{d}", .{ i.a, i.b }),
                .index, .index_set, .map_set => try w.print(" r{d} r{d} r{d}", .{ i.a, i.b, i.c }),
                .length => try w.print(" r{d} r{d}", .{ i.a, i.b }),
                .xref => try w.print(" x{d}    ; the tree walker does the rare case: {s}", .{ i.bx(), @tagName(c.xnodes[i.bx()].node.tag) }),
                .interp => try w.print(" r{d} r{d}", .{ i.a, i.b }),
                .unpack => try w.print(" r{d} -> r{d}..r{d}", .{ i.a, i.b, i.b + i.c - 1 }),
                .wait => try w.print(" r{d}", .{i.a}),
                .iterend => try w.print(" r{d}", .{i.a}),
                .iterprep, .iterloop => try w.print(" r{d} -> {d}", .{ i.a, @as(i64, pc) + 1 + i.sbx() }),
                .call => {
                    const kind: op.CallKind = @enumFromInt(i.c & 3);
                    const site = c.xnodes[Inst.fromWord(c.code[at + 1]).bx()].node;
                    const callee: *const @import("ast.zig").Node = if (kind == .apply) site else site.kids[0];
                    try w.print(" r{d} args {d} {s}{s}    ; {s}", .{ i.a, i.b, @tagName(kind), if (i.c & op.call_stmt != 0) " stmt" else "", if (callee.tag == .name or callee.tag == .field or callee.tag == .apply_stmt) callee.text else @tagName(callee.tag) });
                },
                .site, .deferpush => try w.print(" x{d}", .{i.bx()}),
                .addi, .subi, .muli, .modi => try w.print(" r{d} r{d} {d}", .{ i.a, i.b, @as(i8, @bitCast(i.c)) }),
                .augi => try w.print(" r{d} {d} {s}", .{ i.a, @as(i8, @bitCast(i.b)), @tagName(@as(op.Op, @enumFromInt(i.c))) }),
                .jflt, .jfle, .jfgt, .jfge, .jfeq, .jfne => if (i.c == 1) try w.print(" r{d} {d}", .{ i.a, @as(i8, @bitCast(i.b)) }) else try w.print(" r{d} r{d}", .{ i.a, i.b }),
                .zero => try w.print(" r{d} x{d}    ; the zero of {s}", .{ i.a, i.bx(), c.xnodes[i.bx()].node.text }),
                .loadrune, .loadnum, .loadtext => try w.print(" r{d} k{d}    ; {s}", .{ i.a, i.bx(), c.consts[i.bx()].str }),
                .exitcode, .raise => try w.print(" r{d}", .{i.a}),
                .failmsg => try w.print(" r{d} {s}{s}", .{ i.a, if (i.b == 1) "assert" else "expect", if (i.c == 1) " message" else "" }),
                .declmark => try w.print(" r{d} k{d}    ; {s}", .{ i.a, i.bx(), c.consts[i.bx()].str }),
                .matchpat, .matcheq => try w.print(" r{d} r{d} r{d}", .{ i.a, i.b, i.c }),
                .clone => try w.print(" r{d} r{d}", .{ i.a, i.b }),
                .declty => try w.print(" r{d} x{d}", .{ i.a, i.bx() }),
                .range => try w.print(" r{d} r{d} r{d}", .{ i.a, i.b, i.c }),
                .new_obj => try w.print(" r{d}", .{i.a}),
                .obj_set => try w.print(" r{d} r{d}", .{ i.a, i.b }),
                .setfield => try w.print(" r{d} r{d}", .{ i.a, i.b }),
                .capture => try w.print(" r{d} r{d} {s}", .{ i.a, i.b, if (i.c == 0) "last" else "first" }),
                .indexv => try w.print(" r{d} r{d} args {d}", .{ i.a, i.b, i.c }),
                .index_setv => try w.print(" r{d} r{d} args {d}", .{ i.a, i.b, i.c }),
                .dim => try w.print(" r{d} r{d}", .{ i.a, i.b }),
                .step => try w.print(" r{d} {d}", .{ i.a, i.sbx() }),
                .near => try w.print(" r{d} r{d}", .{ i.a, i.b }),
                .iterlist => try w.print(" r{d} r{d}", .{ i.a, i.b }),
                .push_front => try w.print(" r{d} r{d}", .{ i.a, i.b }),
                .defvar => try w.print(" r{d} k{d}    ; {s}", .{ i.a, i.bx(), c.consts[i.bx()].str }),
                .closure => try w.print(" r{d} x{d}", .{ i.a, i.bx() }),
                .jobbegin, .parbegin => try w.print(" -> {d}", .{@as(i64, pc) + 1 + i.sbx()}),
                .jobclose, .parclose, .commit => {},
                .signal => try w.print(" {s}", .{switch (i.a) {
                    0 => "stop",
                    1 => "rollback",
                    else => "panic",
                }}),
                .field => try w.print(" r{d} r{d}", .{ i.a, i.b }),
                .over, .halt, .safe => {},
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
