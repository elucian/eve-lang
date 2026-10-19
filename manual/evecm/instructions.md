# Instruction set of the bytecode machine

Status: stage B5.2 (D-201, F-VM-04); the set grows with B5.3 to B5.6. The source of truth is `comp/evecm/src/op.zig`; `python script/bctest.py` fails when an instruction of the source is missing from this page. `eve --disasm file.eve` prints the listing of a script.

## Encoding

An instruction is a 32-bit word: `op` (8 bits), then the operands `A`, `B`, `C` (8 bits each). `Bx` is B and C together, unsigned 16 bits (a constant index); `sBx` is the same with a sign (a jump, counted in instructions from the next one). A function has at most 256 registers. `binx` is followed by an `extra` word.

## Instructions

| Instruction | Meaning |
|---|---|
| `move` | `A := B` |
| `loadk` | `A := const[Bx]` |
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
| `evalx`, `execx` | the bridge (TD-46): evaluate an expression or run a statement on the tree walker, with the named variables copied in and out |
| `over` | end the process |
| `halt` | end of the main process |

## Rules

- The tree walker is the reference: for every program both engines give the same output, exit code and errors (`runtest.py all --both`).
- A routine that the emitter cannot translate stays on the tree walker; `EVE_BC_TRACE=1` says why.
