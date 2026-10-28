# Instruction set of the bytecode machine

Status: stage B5.2 to B5.3 (D-201, F-VM-04); the set grows with B5.4 to B5.6. The source of truth is `code/evecm/src/op.zig`; `python script/bctest.py` fails when an instruction of the source is missing from this page. `eve --disasm file.eve` prints the listing of a script.

## Encoding

An instruction is a 32-bit word: `op` (8 bits), then the operands `A`, `B`, `C` (8 bits each). `Bx` is B and C together, unsigned 16 bits (a constant index); `sBx` is the same with a sign (a jump, counted in instructions from the next one). A function has at most 256 registers. `binx` is followed by an `extra` word.

## Instructions

| Instruction | Meaning |
|---|---|
| `move` | `A := B` |
| `loadk` | `A := const[Bx]` |
| `loadg` | `A := ` the variable named `const[Bx]` of the enclosing scopes: a variable or constant of the aspect, a class, a module (looked up as the tree walker does) |
| `loadi` | `A := sBx`, an integer |
| `loadnil`, `loadtrue`, `loadfalse` | `A` gets null, True, False |
| `add`, `sub`, `mul`, `div`, `mod` | `A := B op C` |
| `neg` | `A := -B` |
| `eq`, `ne`, `lt`, `le`, `gt`, `ge` | `A := B op C`, a Boolean |
| `not` | `A := not B` |
| `jmp` | `pc += sBx` |
| `jf`, `jt` | jump when `A` is False, when `A` is True |
| `jnn` | jump when `A` is not null (`a ?? b` skips its right side) |
| `unpack` | deconstruct the value in `A` into the `C` registers from `B`; the next `extra` word says where the `*` target is and whether the form is `=` |
| `wait` | pause for the duration in `A` (`wait 10ms;`); an error when `A` is not a duration |
| `forprep`, `forloop` | the loop over a range or a rune range: `A` counter, `A+1` limit, `A+2` the user's variable |
| `callf` | call function `C` with `B` arguments from `A+1`; the result goes to `A` |
| `ret` | leave the function; the result is in `A` when `B` is 1 |
| `print` | show `B` values from `A`; `C` is 1 for `print`, 0 for `write` |
| `expect` | fail with an `expect` error when `A` is not True |
| `coerce` | convert `A` to the `TypeKind` number `B` |
| `setlike` | `A := B`, converted to the kind that `A` holds |
| `augment` | `A := A op B`, `C` is the arithmetic instruction; lists and sets change in place |
| `binx`, `extra` | `A := B op C` for an operator without its own instruction; the operator text is the constant of the `extra` word |
| `new_list`, `new_map`, `new_set` | `A := ()`, `A := {}` of pairs, `A := {}` of values; with `new_list`, B = 1 makes an array `[]` |
| `list_push`, `map_set`, `set_add` | build the fresh list, map or set of a literal: `A <+ B`, `A[B] := C`, `A <+ B` (no other case exists) |
| `index` | `A := B[C]`: the element of a list (an integer index, negative from the end), or the value of an existing key of a map; a string, a view, a matrix, a missing key or an index out of range take the slow case |
| `index_set` | `A[B] := C` on a list (an integer index in range) or a map; any other case takes the slow case |
| `push` | `let A <+ B`: append to a list, add to a set; any other case (a string, a list added to a list, a table) takes the slow case |
| `length` | `A := B.count()` or `.length()` of a string, a list, a set or a map; an object takes the slow case |
| `xref` | the second word of `index`, `index_set`, `push`, `length`, `field`, `iterprep` and `interp`: `Bx` is the node (xnode) that the tree walker runs for the slow case, so the error messages and the rare kinds are those of the reference |
| `interp` | `A := ` the text of an interpolation; the value of its part k is in register B+k and the format is in the node of the next `xref` word |
| `iterprep`, `iterloop` | the loop over a collection: A holds the collection (a map, a set, a string or a table becomes a list of its elements), A+1 the position, A+2 the user's variable; `iterprep` jumps by `sBx` when there is nothing to visit; a range value (A+1 is the next number), a channel, a generator and a stream are pulled one element at a time by `iterprep` and `iterloop` |
| `iterend` | the end of a `for` loop (after a `break` too): the generator or the stream in `A` that is not finished is closed, which writes the rejects of a stream |
| `call`, `site` | a call that is not a direct call of a translated routine: the callee (kind `value`) or the receiver (kind `method`) is in A, the B arguments in A+1 and after, the result goes to A; C is the kind (`value`, `method`, `builtin`: a name that is neither a register nor a routine of the aspect), plus 4 for a call that is a statement, plus 8 when the callee or the receiver is a name outside the registers (a module, a type, a routine of the aspect): then A is not loaded and the machine reads the name from the site. A literal argument, or a name outside the registers, stays a node of the site and has no register. A plain function value and a module function are called at once with the values; any other callee (a method, a string or list function, a class, a library native) goes to the tree walker as the call node of the `site` word, each value bound to a hidden name `$k`, so the native reads the same values as from its own evaluation. The argument registers are cleared after the call. Kind `apply` (`apply name(args)`) has no callee: the tree walker runs the aspect or the private process of the site. Kinds `apply` with bit 32 (`start name(args)` in a `parallel` group) or bit 64 (`spawn f(args)` in a job) start a task through the tree walker; the `@x` arguments of a task keep one cell for the variable in the block, and the value the task wrote is copied to the register at the `done` (`jobclose`, `parclose`). An `@x` argument on a variable in a register (bit 16 of C) goes through the adapter as a reference to its hidden name, and when the call returns, also by failure, the final value of the hidden name is written back to the register of the variable |
| `evalx`, `execx` | the bridge (TD-46): evaluate an expression or run a statement on the tree walker, with the named variables copied in and out |
| `zero` | `A := ` the zero value of the type node of the xnode `Bx`, made by the tree walker (the result of a routine whose type has no literal zero: a list, a map, a `Decimal`, a class) |
| `storeg` | store register `A` in the name outside the registers that the assignment of the xnode `Bx` targets (a variable of the closure, of the aspect, of a module), by the steps of the tree walker's `assign`: `:=` converts like the current value (`coerceLike`), `::` copies, `+=` and the other compound forms combine with the current value, an `Atomic` variable changes under its lock |
| `field` | `A := B.name`: an attribute of an object or a member of a module; any other case (a class, a type, a generator value, a missing attribute) takes the slow case |
| `loadrune` | `A := ` the Rune written as the text of the constant `Bx` |
| `loadnum` | `A := ` the number written as the text of the constant `Bx`, when it has no plain literal form (a unit, a type suffix, a Rational, an imaginary number, a duration, a number written as a string) |
| `loadtext` | `A := ` the text of the constant `Bx`, marked as a multi-line text literal (`"""`) |
| `unpair` | the pair (a list of two) in register `A` goes to registers `B` and `B+1`: the loop variable `(k: v)`; another length fails |
| `updbegin` | `update A do`: the record in register `A`; a scope with the fields of the record as variables is entered, and assignments to them write the record |
| `updend` | the end of an `update` block: `validate` of the record runs, the scope and the state of the block are left |
| `deferpush` | `defer`: the statement of the xnode `Bx` waits in the frame; it runs on the tree walker, newest first, when the routine ends (`rundefers`) or an error leaves it |
| `rundefers` | run the `defer` statements of this frame; the next instruction is its `ret` |
| `addi`, `subi`, `muli`, `modi` | `A := B op C` with `C` a signed 8-bit number written in the instruction |
| `augi` | `A := A op B` (`let a += 1`) with `B` a signed 8-bit number and `C` the operator (`add`, `sub`, `mul`) |
| `jflt`, `jfle`, `jfgt`, `jfge`, `jfeq`, `jfne` | jump if the comparison of `A` with `B` is false; `B` is a register, or a signed 8-bit number when `C` is 1. The next word is the `jmp` taken when the comparison is false; when it is true that word is skipped |
| `exitcode` | check the exit code in register `A` (0 or 6 to 125) and set it for the `over` or `exit` that follows |
| `raise` | `raise A`: the error of the value in register `A` (a text, a list of a code and a text, an object with `code` and `message`) |
| `failmsg` | a failed `expect` (`B` = 0) or `assert` (`B` = 1): the message is in register `A` when `C` = 1, else the default text; the compiler skips it with `jt` when the condition holds, so the message is computed only on failure |
| `declmark` | a `new` or `set` in the body of a loop (D-213): register `A` is the mark of the declaration, cleared before the loop; the second cycle fails with the error "already declared" for the name of the constant `Bx` |
| `matchpat` | `A := ` does the subject `B` match the pattern value `C` of a `match` arm: a range or a domain contains it, a class tests the class of an object, any other value is equal to it |
| `matcheq` | `A := ` is `B` equal to `C` (a value of a `when (a, b)` list) |
| `clone` | `A := ` a copy of `B` (`::`) |
| `declty` | finish a declaration with one name (the node of the xnode `Bx`) for the value in register `A`: the declared type converts it, an object literal gets the class of the type, a channel gets the name |
| `range` | `A := ` the range or domain between `B` and `C`; the next `extra` word has the operator text in `Bx` and, in its `A`, bit 0 when the lower limit is open and bit 1 when the upper one is (the register then holds null) |
| `new_obj`, `obj_set` | `new_obj` makes the object of an object literal in `A`; `obj_set` stores register `B` in the field of the object `A`, the name is the constant `Bx` of the next `extra` word |
| `setfield` | `A.name := B`: assign the field named by the constant `Bx` of the next `extra` word on the object in register `A`; a record watched by the database layer is told before and after, any other value than an object is the error "has no attributes" |
| `capture` | `let l -> x` (`C` = 0) or `let x <- l` (`C` = 1): the last or the first element of the list in register `B` is removed and goes to register `A`; an empty list or a value that is not a list is an error |
| `indexv`, `index_setv` | the brackets that `index` and `index_set` do not take: several indexes `a[i, j]`, a range (a slice, a view of a list, a substring), `*`, a chain `a[i][j]` (merged on a matrix). The object is in register `B`, the value indexes follow it; the next `extra` word gives the constant `Bx` that describes the brackets (the count of groups, the size of each group, then a byte for each index: 0 a value, 1 `*`). `indexv` puts the element, the slice or the list of cells in `A`; `index_setv` stores register `A` in every cell selected (a map entry, an element, a slice, a row or column). For a compound assignment the `extra` word has `A` = 1: nothing is stored when the collection was changed in place |
| `dim` | `A := ` the value of `$` for the only index of the object in register `B`: the number of elements of a list (all the elements of a matrix), the runes of a string, the bytes of a Bytes |
| `step` | `A += sBx` on an integer or a rune: the limit of an excluded end of a counting loop (`1>..<5` starts at 2 and ends at 4) |
| `near` | `A := ` is `|B - (B+1)| <= (B+2)`: `x =~ c +- t` with the three numbers in `B`, `B+1` and `B+2` |
| `iterlist` | `A := ` a list of the elements of the collection, range, string or map in register `B` (what a builder visits with `iterprep` and `iterloop`) |
| `push_front` | `A +> B` as the statement `let B +> A`: puts register `B` in front of the list `A` (a set adds it); the other cases take the slow case of the `xref` word |
| `pow` | not executed: the operator code of `augment` for `^=` (`A := A ^ B`) |
| `defvar` | define the variable named by the constant `Bx` (bit 15: a constant, `set`) in the current scope with the value of register `A`: a local that a lambda of its routine names lives in the scope of the routine, where the lambda finds it by name through its closure; the machine then reads and writes it with `loadg` and `storeg` |
| `closure` | `A := ` the function value of the lambda of the xnode `Bx`, with the current scope as its closure |
| `jobbegin`, `jobclose` | a `job` block: `jobbegin` opens a scope for the block and a list for the tasks spawned in it (the label is the constant `Bx` of the next `extra` word) and sets a handler at the `jobclose` that `sBx` points to. The block runs; at its end, or when an error leaves it (the frames above the block are let go), `jobclose` waits for the tasks, writes their outputs to the registers of the variables, commits or rolls back, sets `jobs["label"].status` (`pass`, `fail`, `rolled back`) and gives the error on |
| `parbegin`, `parclose` | a `parallel` group, the same way: register `A` holds the `within` duration (255: none), the `extra` word has the label and, in its `A`, the `cancel` bit; `start` in the block starts a task of the group |
| `signal` | `stop` (`A` = 0), `rollback` (`A` = 1) and `panic` (`A` = 2): the signals that end a job block (the handler of the block sees them) or the program |
| `commit` | `commit;` in a job |
| `safe` | a safe point after a statement of the process body: the objects that nobody holds are freed and their destructors run, at the same place as in the tree walker |
| `over` | end the process |
| `halt` | end of the main process |

## Rules

- The tree walker is the reference: for every program both engines give the same output, exit code and errors. The bytecode machine is tested by `test/bytecode` (`python script/bctest.py`); the sweep over every conformance test is `runtest.py all --both`.
- An instruction with a fast case (`index`, `index_set`, `push`, `length`, `iterprep`) is followed by an `xref` word: the case it does not handle (a string, a view, a matrix, a missing key, an index out of range, a channel, a generator) runs the same node on the tree walker, so the values and the error messages are those of the reference.
- A routine that the emitter cannot translate stays on the tree walker; `EVE_BC_TRACE=1` says why.
