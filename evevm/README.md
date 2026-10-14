# evevm — the Eve virtual machine

The first Eve implementation (D-006, D-007 in `../plan/decision_level1.md`): a virtual machine written in Zig that runs Eve scripts. It builds `bin/eve.exe` at the repo root, the official `eve`
command. Manual: [`../manual/README.md`](../manual/README.md).

Version: **0.0.6**. Status: level 1 passes (82 of 82 tests of `test/level1/`) and level 2 passes (29 of 29 tests of `test/level2/`, 2026-10-07): lexer, parser, a static check (`check.zig`, D-110), the link of a driver with its aspects (`project.zig`: `apply`, D-112) and a tree-walking interpreter with the run log. Levels 3 to 7 are not implemented.

## Build

Requires Zig 0.16.0 (`winget install zig.zig`). The build is at the **root of the repository** (one `build.zig` for all the modules, D-163); run it from there:

| Command | Result |
|---|---|
| `zig build -p .` | builds and installs `bin/eve.exe` (and its copy `evevm.exe`) |
| `zig build` | builds `zig-out/bin/eve.exe` (local, git-ignored) |
| `zig build run -- --version` | builds and runs `eve` with arguments |
| `zig build test` | runs the unit tests of every module |
| `zig build -Doptimize=ReleaseSafe -p temp/rel` | the build the tests and benchmarks use |
| `zig build doc` | writes `lib/doc` from the Eve sources of `lib/` |

## The modules

The source is split into modules (plan/design-packages.md). The arrows are the `.imports` of the root `build.zig`: a module that is not listed cannot be imported, so a wrong import does not compile.

```
cmd ──► evevm ──► evecp ──► evecm
 ├────► evedb ─────────────►
 └─────────────────────────►
```

| Module | Holds | Imports |
|---|---|---|
| [`evecm/`](../evecm) | the common part: the syntax tree (`ast`), the values and the heap (`value`, `heap`), the interfaces `Host` and `Data` (`iface`), Decimal, Instant, NFC, the codecs of data (`data`), the configuration of a machine (`config`), the wire (`wire`: JSON-RPC, HTTP, client calls), the line editor and the terminal, the version | `std` |
| [`evecp/`](../evecp) | the compiler: `lexer`, `parser`, `check`, `overload`, the project link (`project`), `doc`, `scaffold` | `evecm` |
| `evevm/` (here) | the runtime: `interp` (the tree walker: the state, errors, scopes and values in `interp.zig`, its methods by concern in `interp/`: `show`, `expr`, `collections`, `calls`, `stmt`, `script`, `parallel`, `generators`, `datatypes`), `task`, `scratch`, `vm` (session and slot), `dlib` (the natives of the library: streams, files), `host` (the `Host` of an interpreter), `machine` (the machine and its two doors), `client` (`-loc`, `-rem`, the words `status` and `stop`), `daemon` (`stop`, the machine in its own process, `-u`), the REPL (`tui`, `screen`, `helptext`) | `evecp`, `evecm` |
| [`evedb/`](../evedb) | the database layer: `sqlite`, `conn` (connections, statements, `sql function`), `orm` (tables, records, the transaction of a job), `state` | `evecm` |
| [`cmd/`](../cmd) | the `eve` command: `eve.zig` (the entry point), `cli.zig` (options, commands, REPL commands); it connects the parts (`interp.data_api = &evedb.data`) | all |

`evevm` and `evedb` never import each other. They meet through two interfaces defined in `evecm/src/iface.zig`: `Host` (what the interpreter offers to the database layer: memory, the heap, evaluating an argument, errors, building values) and `Data` (what the database layer offers to the interpreter: `database.connect`, the methods of a connection and a table, the transaction of a job). `lib/` holds the Eve standard library, mostly written in Eve ([README](../lib/README.md)); `lib/doc/` is generated from it by `eve --doc` and never edited by hand.

## License

Business Source License 1.1, see [LICENSE](LICENSE). The code becomes Apache 2.0 on the Change Date.
