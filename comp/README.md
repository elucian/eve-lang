# Eve components

The source code of the Eve implementation, one folder per component. Each folder has a `README.md` (the design and the state of the work) and a `doc/` folder (the user documentation, copied into the manual by `script/genmanual.py`).

| Component | What it is | Built into |
|---|---|---|
| [eve](eve/README.md) | the `eve` command: the entry point, the options, the commands of each part, the help pages; the only place that imports every module | `bin/eve.exe` |
| [evecm](evecm/README.md) | the common part: values and the heap, decimals, time and Unicode, the data codecs (CSV, JSON), the configuration and the wire of a machine, the interfaces between the runtime and the database layer, the editor parts that need no screen | every program |
| [evecp](evecp/README.md) | the compiler front end: lexer, parser, static checks, the link of a project, `eve --doc`, `project init` and `project new` | `bin/eve.exe` |
| [evevm](evevm/README.md) | the runtime: the interpreter, tasks and parallel work, the native modules of the library, the machine with its IPC, HTTP and stdio doors, the service, the REPL, and the database layer with SQLite (tables and records, connections, the transaction of a job, the drivers `postgres://` and `evedb://`) | `bin/eve.exe`, `bin/evevm.exe` |
| [evedb](evedb/README.md) | the `evedb` server around DuckDB (PostgreSQL protocol, column batches, test faults) and the wire protocol `ewp_protocol` that it shares with the driver in `evevm`; it leaves `comp/` for `drivers/duckdb` (D-198) | `bin/evedb.exe` |
| [evetx](evetx/README.md) | the terminal IDE on libvaxis: file tree, editor, run and debug, data tables | `bin/evetx.exe` |
| [eveux](eveux/README.md) | the native graphical workbench on dvui (early draft) | `bin/eveux.exe` |
| [evewp](evewp/README.md) | the Eve Web Portal, written in Eve: edge, host, monitor and the web framework (design only) | not built yet |

## How they depend on each other

The modules of `eve` are built by the root `build.zig`; an arrow is an import, and a module that is not listed cannot be imported:

```
eve ──► evevm ──► evecp ──► evecm
           └────► ewp_protocol   (also imported by the evedb server)
```

The database layer is a part of `evevm` (since 2026-10-19); the interpreter and the layer call each other directly (the interfaces `Host` and `Data` of `evecm` are gone, S8.3 and S8.4 of `design/phase-8-architecture.md`). `evetx` and `eveux` import only the editor part of `evecm` (`evecm/src/ide.zig`) and talk to a machine like any client.

## Building

From the root of the repository (Zig 0.17.0):

| Command | Builds |
|---|---|
| `./run.sh build` | `eve` and `evevm` (`bin/eve.exe`, `bin/evevm.exe`, `lib/`) |
| `./run.sh build <part>` | one part: `eve`, `evevm`, `evedb`, `evetx`, `eveux` |
| `./run.sh build all` | every part |
| `zig build test` | the unit tests of the modules of `eve`; `zig build test` in `comp/evedb`, `comp/evetx` and `comp/eveux` for theirs |

## License

All the components are under one license, the Business Source License 1.1: [LICENSE](LICENSE). The code becomes Apache License 2.0 on the Change Date written there.
