//! @eve-module op
//! @spec design/design-bytecode.md#33-instruction-encoding
//! @feature F-VM-04
//! @decision D-201
//! @tests code/evecm/src/op.zig (unit tests), test/level1 with `--engine bc`
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
    /// `A := the variable named const[Bx]` of the enclosing scopes (a shared variable of the aspect, a constant, a class, a module): the name is looked up as the tree walker does
    loadg,
    /// assign register A to the name outside the registers that the assignment xnode[Bx] targets (a variable of the closure, of the
    /// aspect, of a module), by the rule of the tree walker's `assign`: `:=` converts like `coerceLike`, `::` copies, `+=` and the others
    /// combine with the current value, an `Atomic` variable changes under its lock
    storeg,
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
    /// only as the operator of `augment`: `A := A ^ B`
    pow,
    /// `A := not B`
    not,
    /// `pc += sBx`
    jmp,
    /// `if not A then pc += sBx`
    jf,
    /// `if A then pc += sBx`
    jt,
    /// `if A is not null then pc += sBx` (`a ?? b`)
    jnn,
    /// deconstruct the value in A into the C registers from B (`new q, r := f();`, `new (u, v) = 7;`); the next `extra` word holds 2 * (index of the `*` target + 1, or 0) + 1 for `=` (a name for the whole value when the sizes differ)
    unpack,
    /// pause for the duration in A (`wait 10ms;`)
    wait,
    /// the loop `for A in lo..hi`: A is the counter, A+1 the limit, A+2 the user's variable; `pc += sBx` when the range is empty
    forprep,
    /// the counter A grows by one; while it is not above the limit A+1, the variable A+2 gets it and `pc += sBx` (back to the body)
    forloop,
    /// call the function `C` with `B` arguments in A+1 ..; the result goes to A
    callf,
    /// leave the function; the result is in register A when B is 1
    ret,
    /// show the B values from register A; bit 0 of C is 1 for `print` (separator `,` and a new line) and 0 for `write`; bit 1 says that register A holds the `sep:` text and the values start at A+1
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
    /// `A := ()` (an empty list); with B = 1, `A := []` (an array)
    new_list,
    /// `A := {}` of keys and values (an empty map)
    new_map,
    /// `A := {}` of values (an empty set)
    new_set,
    /// `A <+ B`: append B to the list A, the fresh list of a literal (no fallback)
    list_push,
    /// `A[B] := C` on the fresh map A of a literal (no fallback)
    map_set,
    /// `A <+ B` on the fresh set A of a literal (no fallback)
    set_add,
    /// `A := B[C]`: the element of a list, or the value of an existing key of a map; any other case (a string, a view, a matrix,
    /// a missing key, an index out of range) runs the expression xnode[Bx of the next `xref` word] on the tree walker, which gives
    /// its value or its error
    index,
    /// `A[B] := C`: store in a list or a map; any other case runs the statement xnode[Bx of the next `xref` word] on the tree walker
    index_set,
    /// `A <+ B` (the statement `let A <+ B`): append to a list, add to a set; any other case runs xnode[Bx of the `xref` word]
    push,
    /// `A := B.count()` (or `.length()`) of a string, a list, a set or a map; any other case runs xnode[Bx of the `xref` word]
    length,
    /// the second word of `index`, `index_set`, `push` and `length`: `Bx` is the xnode that the tree walker runs when the fast case does not apply
    xref,
    /// `A := the text of an interpolation`: the node is the xnode of the next `xref` word, the value of its part k is in the register B+k
    interp,
    /// the loop `for A in collection`: A holds the collection (it becomes a list of the elements), A+1 the position, A+2 the user's
    /// variable; `pc += sBx` when there is nothing to visit; a collection that is not a list, a map, a set, a string or a range
    /// runs the whole loop statement (xnode[Bx of the next `xref` word]) on the tree walker and jumps past it
    iterprep,
    /// the position A+1 grows by one; while it is not past the end of the list A, the variable A+2 gets the element and `pc += sBx` (back to the body)
    iterloop,
    /// the end of a loop over a generator or a stream (`for` statement): the one that is not finished is closed, as the tree walker does when the loop ends
    iterend,
    /// call through the tree walker's rules: the callee (kind `value`) or the receiver (kind `method`) is in A, the B arguments in
    /// A+1 .., the result goes to A; C is the `CallKind` (bits 0-1) and 4 when the call is a statement. The next word is `site`
    call,
    /// the second word of `call`: `Bx` is the xnode of the call site, the call node with its arguments replaced by hidden names
    site,
    /// `A := the zero value of the type node xnode[Bx]` (the result of a routine of a type without a literal zero: a list, a map, a
    /// Decimal, a class...), made by the tree walker's `zero`
    zero,
    /// `A := the Rune of const[Bx]` (the text of a rune literal)
    loadrune,
    /// `A := the number written as const[Bx]` that has no plain literal form: a unit, a suffix, a Rational, an imaginary, a duration
    loadnum,
    /// `A := the text of const[Bx]` marked as a multi-line text literal (`"""`), which the tree walker shows with its own rule
    loadtext,
    /// the pair in register A (a list of two) goes to registers B and B+1: the loop variable `(k: v)`; any other length fails
    unpair,
    /// the exit code in register A for the `over` or `exit` that follows: 0 or 6 to 125
    exitcode,
    /// `raise A`: the error of the value in register A
    raise,
    /// a failed `expect` (B = 0) or `assert` (B = 1): the message is in register A when C = 1, else the default text
    failmsg,
    /// a `new` or `set` in the body of a loop (D-213): register A is the mark of the declaration, false at the start of the loop;
    /// at the second cycle it fails with the error "already declared" for the name const[Bx]
    declmark,
    /// `A := the subject B matches the pattern value C` of a `match` arm: a range or a domain contains it, a class tests the class of an
    /// object, any other value is equal to it
    matchpat,
    /// `A := B equals C` (a value of a `when (a, b)` list)
    matcheq,
    /// `A := a copy of B` (`::`, the declaration `new c :: a`)
    clone,
    /// finish the declaration xnode[Bx] (a `new` or `set` with one name) for the value in register A: the declared type converts it,
    /// an object literal gets the class of the type, a channel gets the name
    declty,
    /// `A := the range or domain of the operator text const[Bx of the next extra word]` between B and C; bits 0 and 1 of the A of the
    /// `extra` word say that the lower or the upper limit is open (the register holds null)
    range,
    /// `A := a new object`
    new_obj,
    /// `A.name := B`, the name is const[Bx of the next `extra` word]: a field of the object literal in register A
    obj_set,
    /// `A.name := B`, the name is const[Bx of the next `extra` word]: assign a field of the value in register A (an object)
    setfield,
    /// `let l -> x` (C = 0) and `let x <- l` (C = 1): the last or the first element of the list in register B is removed and goes to register A
    capture,
    /// `A := B[...]` for every index that `index` does not take (several indexes, a range, `*`, a chain `a[i][j]`): the object is in
    /// register B, the C value indexes follow in B+1 ..; the next word is `extra` with the constant `Bx` that describes the brackets
    /// (the string: the count of groups, the size of each group, then one byte for each index: 0 a value, 1 `*`)
    indexv,
    /// `B[...] := A` for the same brackets (B and C as in `indexv`, the value is in register A; the next `extra` word follows)
    index_setv,
    /// `A := ` the value of `$` for the only index of the object in register B
    dim,
    /// `A += sBx` on an integer or a rune (the limit of an excluded end of a counting loop: `1>..<5`); any other value is left as it is
    step,
    /// `A := |B - (B+1)| <= (B+2)`: `x =~ c +- t`, the three numbers in B, B+1 and B+2
    near,
    /// `A := ` a list of the elements of the collection, range, string or map in register B (what a `for` or a builder visits)
    iterlist,
    /// `A <+ B` at the front (the statement `let B +> A`); the same cases as `push`, the next `xref` word for the others
    push_front,
    /// define the variable named const[Bx] in the current scope with the value of register A (bit 15 of Bx: a constant, `set`; the constant index is the low 15 bits): a local that a
    /// lambda names lives in the scope of its routine, where the lambda finds it
    defvar,
    /// `A := ` a function value of the lambda xnode[Bx] with the current scope as its closure
    closure,
    /// the start of a `job` block: the label is const[Bx of the next `extra` word]; `sBx` is the distance to the `jobclose` that ends the
    /// block, where an error in the block is handled. The block runs in a scope of its own and collects the tasks spawned in it
    jobbegin,
    /// the end of a `job` block, reached at the end of the block or by an error in it: wait for the tasks, commit or roll back, set
    /// the state of the job (`pass`, `fail`, `rolled back`), and give the error on
    jobclose,
    /// the start of a `parallel` group: register A holds the `within` duration (255: none), `sBx` is the distance to the `parclose`;
    /// the next `extra` word has the label in Bx and in A the bit 1 of `cancel`
    parbegin,
    /// the end of a `parallel` group (see `jobclose`): wait for the tasks, write their outputs
    parclose,
    /// `stop` (A = 0) and `rollback` (A = 1) in a job: end the block by the signal of the tree walker
    signal,
    /// `commit;` in a job
    commit,
    /// `A := B.name`: an attribute of an object or a member of a module; any other case runs the expression xnode[Bx of the next `xref` word]
    field,
    /// a safe point: free what nobody holds any more (the end of a statement of the process body)
    safe,
    /// end the process (`over;`)
    over,
    /// end of the main process
    halt,
};

// @eve-impl the kinds of a `call` instruction (design-bytecode.md §16.3)
// @spec design/design-bytecode.md#163-calls-the-call-instruction
pub const CallKind = enum(u2) {
    /// `f(x)`: the callee is a value in register A
    value,
    /// `x.m(...)`: the receiver is in register A, the name is in the call site
    method,
    /// `round(x)`: a name that is neither a register nor a translated routine; the tree walker finds it by name
    builtin,
    /// `apply name(args)`: the aspect or private process `name` runs with the arguments (register A is not used)
    apply,
};

/// The bit of C that marks a `call` that is a statement (`it.stmt_call`).
pub const call_stmt: u8 = 4;

/// The bit of C that marks a `call` whose callee or receiver is a name outside the registers (a module, a type, a routine of the
/// aspect): register A is not loaded, the machine reads the name from the node of the site.
pub const call_named: u8 = 8;

/// The bit of C that marks a `call` with an `@x` argument: the call goes through the adapter, and the final value of the argument
/// is written back to the variable (`NameReg.back`).
pub const call_ref: u8 = 16;

/// Bits of C for a call of kind `apply` that starts a task: `start name(args)` in a `parallel` group and `spawn f(args)` in a `job`.
pub const call_start: u8 = 32;
pub const call_spawn: u8 = 64;

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
