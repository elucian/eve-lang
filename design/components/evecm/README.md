# evecm: the common part

Code: [`code/evecm/`](../../../code/evecm/). This folder holds the design, the notes and the user documents of the component; the code folder holds only code.

The leaf of the module graph (design/design-packages.md §3). It imports `std` and the build options only, and it holds Zig code only, never data. Every other part uses it.

| File | Holds |
|---|---|
| `ast.zig` | the syntax tree (until the bytecode, step B5, moves it to `evecp`) |
| `value.zig`, `heap.zig` | `Value`, the objects it points to (`List`, `Map`, `Object`, `Class`, `Func`, `Scope`, `Var`), the error codes, the helpers on values; the heap with reference counting and the tracing collector |
| `config.zig`, `wire.zig` | the keys of `eve.cfg`, the socket folder, the exit codes; JSON-RPC answers, HTTP helpers, the client calls to a machine |
| `decimal.zig`, `instant.zig`, `nfc.zig`, `nfc_data.zig` | exact numbers, time, Unicode normalization (`script/gen_nfc.py` writes `nfc_data.zig`) |
| `data.zig` | CSV and JSON text, connection URLs |
| `line.zig`, `terminal.zig` | the line editor and the raw keyboard mode of the prompt |
| `version.zig` | the version, written once in the root `build.zig.zon` and given by a build option |

Build and test from the repository root: `zig build test`.
