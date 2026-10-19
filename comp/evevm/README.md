# evevm — the Eve virtual machine

The first Eve implementation (D-006, D-007 in `../design/decision/level1.md`): a virtual machine written in Zig that runs Eve scripts. It builds `bin/eve.exe` at the repo root, the official `eve`
command. Manual: [`../manual/README.md`](../../manual/README.md).

Version: **0.0.7**. Status: level 1 passes (82 of 82 tests of `test/level1/`) and level 2 passes (29 of 29 tests of `test/level2/`, 2026-10-07): lexer, parser, a static check (`check.zig`, D-110), the link of a driver with its aspects (`project.zig`: `apply`, D-112) and a tree-walking interpreter with the run log. Levels 3 to 7 are not implemented.

## Build

Requires Zig 0.17.0 (`winget install zig.zig`; since 2026-10-18, TD-37). The build is at the **root of the repository** (one `build.zig` for all the modules, D-163); run it from there:

| Command | Result |
|---|---|
| `zig build -p .` | builds and installs `bin/eve.exe` (and its copy `evevm.exe`) |
| `zig build` | builds `zig-out/bin/eve.exe` (local, git-ignored) |
| `zig build run -- --version` | builds and runs `eve` with arguments |
| `zig build test` | runs the unit tests of every module |
| `zig build -Doptimize=ReleaseSafe -p temp/rel` | the build the tests and benchmarks use |
| `zig build doc` | writes `lib/doc` from the Eve sources of `lib/` |

## The modules

The source is split into modules (design/design-packages.md). The arrows are the `.imports` of the root `build.zig`: a module that is not listed cannot be imported, so a wrong import does not compile.

```
eve ──► evevm ──► evecp ──► evecm
 │         └────► ewp_protocol
 └──────────────────────────► evecm
```

| Module | Holds | Imports |
|---|---|---|
| [`comp/evecm/`](../evecm) | the common part: the syntax tree (`ast`), the values and the heap (`value`, `heap`), Decimal, Instant, NFC, the codecs of data (`data`), the configuration of a machine (`config`), the wire (`wire`: JSON-RPC, HTTP, client calls), the line editor and the terminal, the version | `std` |
| [`comp/evecp/`](../evecp) | the compiler: `lexer`, `parser`, `check`, `overload`, the project link (`project`), `doc`, `scaffold` | `evecm` |
| `comp/evevm/` (here) | the runtime: `interp` (the tree walker: the state, errors, scopes and values in `interp.zig`, its methods by concern in `interp/`: `show`, `expr`, `collections`, `calls`, `stmt`, `script`, `parallel`, `generators`, `datatypes`), `task`, `scratch`, `vm` (session and slot), `dlib` (the natives of the library: streams, files), `machine` (the machine and its two doors), `client` (`-loc`, `-rem`, the words `status` and `stop`), `daemon` (`stop`, the machine in its own process, `-u`), the REPL (`tui`, `screen`, `helptext`), and the **database layer** `db` | `evecp`, `evecm`, `ewp_protocol`, SQLite (C) |
| [`comp/eve/`](../eve) | the `eve` command: `eve.zig` (the entry point), `cli.zig` (options, commands, REPL commands) | all |

The **database layer** (`comp/evevm/src/db.zig` and `db/`) is a part of `evevm` since 2026-10-19 (D-198): `sqlite` (the core database and the databases of a script, SQLite compiled in), `conn` (connections, statements, `sql function`), `orm` (tables, records, the transaction of a job), `state`, `memory` and `columnar` (the `Memory` tables), `importer` and `dbf` (files into tables), and the drivers `pgdriver` (`postgres://`) and `ewpdriver` (`evedb://`). The interpreter calls it directly, and it reaches the interpreter through `Host` (`host.zig`), a one-pointer struct. `ewp_protocol` (`comp/evedb/protocol/`) is the wire protocol of the `evedb://` driver, shared with the DuckDB server program of `comp/evedb/`, which is a separate program that `evevm` never links. `lib/` holds the Eve standard library, mostly written in Eve ([README](../../lib/README.md)); `lib/doc/` is generated from it by `eve --doc` and never edited by hand.

## License

Business Source License 1.1, the license of every component of `comp/`: see [LICENSE](../LICENSE). The code becomes Apache 2.0 on the Change Date.
