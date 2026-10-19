# evecp: the compiler

Reads source text and gives a checked syntax tree (design/design-packages.md §3). It imports `evecm` only: it knows nothing of the interpreter or the databases.

| File | Holds |
|---|---|
| `lexer.zig`, `parser.zig` | tokens, the grammar of `spec/syntax/grammar.md` |
| `check.zig`, `overload.zig` | the static checks (names, scopes, parameter order, private methods) and the rules for overloaded subprograms |
| `project.zig` | the link of a driver with its aspects and modules |
| `doc.zig`, `scaffold.zig` | `eve --doc`, `project init` and `project new` |

Build and test from the repository root: `zig build test`.
