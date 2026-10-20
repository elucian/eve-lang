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
| `xref` | the second word of `index`, `index_set`, `push`, `length`, `iterprep` and `interp`: `Bx` is the node (xnode) that the tree walker runs for the slow case, so the error messages and the rare kinds are those of the reference |
| `interp` | `A := ` the text of an interpolation; the value of its part k is in register B+k and the format is in the node of the next `xref` word |
| `iterprep`, `iterloop` | the loop over a collection: A holds the collection (a map, a set or a string becomes a list of its elements), A+1 the position, A+2 the user's variable; `iterprep` jumps by `sBx` when there is nothing to visit; a range value, a channel, a generator or a table runs the whole loop on the tree walker (slow case) |
| `evalx`, `execx` | the bridge (TD-46): evaluate an expression or run a statement on the tree walker, with the named variables copied in and out |
| `safe` | a safe point after a statement of the process body: the objects that nobody holds are freed and their destructors run, at the same place as in the tree walker |
| `over` | end the process |
| `halt` | end of the main process |

## Rules

- The tree walker is the reference: for every program both engines give the same output, exit code and errors (`runtest.py all --both`).
- A routine that the emitter cannot translate stays on the tree walker; `EVE_BC_TRACE=1` says why.
