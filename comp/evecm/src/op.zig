//! @eve-module op
//! @spec design/design-bytecode.md#33-instruction-encoding
//! @feature F-VM-04
//! @decision D-201
//! @tests comp/evecm/src/op.zig (unit tests), test/level1 with `--engine bc`
//! The instructions of the register machine: a 32-bit word, `op` in the low byte, then the operands A, B and C
//! (registers or small numbers); `Bx` is B and C together (a constant index, 16 bits), `sBx` the same with a sign
//! (a jump, counted in instructions from the next one).
const std = @import("std");

// @eve-impl the instruction set of the first stage of the bytecode (B5.2): expressions, variables, print, if, while, for over ranges, calls
// @spec design/design-bytecode.md#5-instruction-set-first-version
/// What an instruction does; the comment of each says its operands.
pub const Op = enum(u8) {
    /// `A := B`
    move,
    /// `A := const[Bx]`
    loadk,
    /// `A := sBx` (an integer)
    loadi,
    /// `A := null`
    loadnil,
    /// `A := True`
    loadtrue,
    /// `A := False`
    loadfalse,
    /// `A := B + C`, and the others of the arithmetic
    add,
    sub,
    mul,
    div,
    mod,
    /// `A := -B`
    neg,
    /// `A := B == C`, and the others of the comparisons
    eq,
    ne,
    lt,
    le,
    gt,
    ge,
    /// `A := not B`
    not,
    /// `pc += sBx`
    jmp,
    /// `if not A then pc += sBx`
    jf,
    /// `if A then pc += sBx`
    jt,
    /// the loop `for A in lo..hi`: A is the counter, A+1 the limit, A+2 the user's variable; `pc += sBx` when the range is empty
    forprep,
    /// the counter A grows by one; while it is not above the limit A+1, the variable A+2 gets it and `pc += sBx` (back to the body)
    forloop,
    /// call the function `C` with `B` arguments in A+1 ..; the result goes to A
    callf,
    /// leave the function; the result is in register A when B is 1
    ret,
    /// show the B values from register A; C is 1 for `print` (separator `,` and a new line) and 0 for `write`
    print,
    /// fail with an `expect` error when A is not True
    expect,
    /// convert register A to the type with the `TypeKind` number B: an Integer becomes a Real for `real`, a Real becomes an Integer for `integer`
    coerce,
    /// `A := the tree walker's value of xnode[Bx]`: an expression the emitter does not translate yet; the variables it names are copied into a scope first
    evalx,
    /// run the statement xnode[Bx] on the tree walker, then copy the variables it names back into their registers
    execx,
    /// `A := B`, converted to the kind of the value that A holds: a Decimal becomes a Real when A holds a Real and the other way (the `:=` of the tree walker)
    setlike,
    /// `A := A op B`, where C is the arithmetic instruction (`add`...`mod`) as a number: the compound assignment `let A += B`; collections change in place
    augment,
    /// `A := B op C`, where the text of the operator is the constant in Bx of the next word (an `extra` word)
    binx,
    /// the second word of `binx`: `Bx` is the constant that holds the operator
    extra,
    /// `A := ()` (empty list)
    new_list,
    /// `A := {}` (empty map or set; the type is known from context)
    new_map,
    /// `A <+ B` (append B to list A; A is modified in place)
    list_push,
    /// `A := B[C]` (get element C from list B, 1-based indexing with negative index support)
    list_index,
    /// `A[B] := C` (set element B of list A to C; A is modified)
    list_set,
    /// `A := B[C]` (get value for key C from map B)
    map_get,
    /// `A[B] := C` (set A[B] to C for map A; A is modified)
    map_set,
    /// `A <+ B` (add B to set A; A is modified in place)
    set_add,
    /// `A := B in C` (check if B is in set C, return boolean)
    set_has,
    /// `A := B.count()` (or `.length()`, works on any collection or string; C is 0 for all types)
    length,
    /// `A := B.method(...)` where method name and args are in the next word; not yet implemented
    call_method,
    /// end the process (`over;`)
    over,
    /// end of the main process
    halt,
};

// @eve-impl one instruction word and its field accessors
/// An instruction.
pub const Inst = packed struct(u32) {
    op: Op,
    a: u8 = 0,
    b: u8 = 0,
    c: u8 = 0,

    /// `Bx`: B and C as one unsigned 16-bit number.
    pub fn bx(i: Inst) u16 {
        return @as(u16, i.b) | (@as(u16, i.c) << 8);
    }

    /// `sBx`: B and C as one signed 16-bit number.
    pub fn sbx(i: Inst) i16 {
        return @bitCast(i.bx());
    }

    pub fn abc(o: Op, a: u8, b: u8, c: u8) Inst {
        return .{ .op = o, .a = a, .b = b, .c = c };
    }

    pub fn abx(o: Op, a: u8, x: u16) Inst {
        return .{ .op = o, .a = a, .b = @truncate(x), .c = @truncate(x >> 8) };
    }

    pub fn asbx(o: Op, a: u8, x: i16) Inst {
        return abx(o, a, @bitCast(x));
    }

    /// The word, for the code array of a chunk.
    pub fn word(i: Inst) u32 {
        return @bitCast(i);
    }

    pub fn fromWord(w: u32) Inst {
        return @bitCast(w);
    }
};

test "an instruction keeps its operands" {
    const i = Inst.abc(.add, 1, 2, 3);
    try std.testing.expectEqual(Op.add, Inst.fromWord(i.word()).op);
    try std.testing.expectEqual(@as(u8, 3), Inst.fromWord(i.word()).c);
    const j = Inst.asbx(.jmp, 0, -5);
    try std.testing.expectEqual(@as(i16, -5), Inst.fromWord(j.word()).sbx());
    const k = Inst.abx(.loadk, 7, 513);
    try std.testing.expectEqual(@as(u16, 513), k.bx());
    try std.testing.expectEqual(@as(usize, 4), @sizeOf(Inst));
}
