# Eve components

The design of the Eve implementation, one folder per component; the source code of each component is in `code/<component>/` and nothing else is there. The database drivers are not components: they are separate projects in [`drivers/`](../../drivers/README.md). Each folder has a `README.md` (the design and the state of the work), a `doc/` folder (the user documentation, copied into the manual by `generator/evegen.py`) and, for the interfaces, a `design/` folder (drawings and notes).

| Component | What it is | Built into |
|---|---|---|
| [eve](eve/README.md) | the `eve` command: the entry point, the options, the commands of each part, the help pages; the only place that imports every module | `bin/eve.exe` |
| [evecm](evecm/README.md) | the common part: values and the heap, decimals, time and Unicode, the data codecs (CSV, JSON), the configuration and the wire of a machine, the interfaces between the runtime and the database layer, the editor parts that need no screen | every program |
| [evecp](evecp/README.md) | the compiler front end: lexer, parser, static checks, the link of a project, `check`, `doc`, `project init` and `project new`; a program of its own (`evecp check a.eve`) and the same code inside `eve` (`eve cp check a.eve`) | `bin/eve.exe`, `bin/evecp.exe` |
| [evevm](evevm/README.md) | the runtime: the interpreter, tasks and parallel work, the native modules of the library, the machine with its IPC, HTTP and stdio doors, the service, the REPL, and the database layer with SQLite (tables and records, connections, the transaction of a job, the drivers `postgres://` and `evedb://`) | `bin/eve.exe`, `bin/evevm.exe` |
| [evetx](evetx/README.md) | the terminal IDE on libvaxis: file tree, editor, run and debug, data tables | `bin/evetx.exe` |
| [eveux](eveux/README.md) | the native graphical workbench on dvui (early draft) | `bin/eveux.exe` |
| [evewp](evewp/README.md) | the Eve Web Portal, written in Eve: edge, host, monitor and the web framework (design only) | not built yet |

## Structure

The code and the design are in two places with the same shape for every component:

```
code/<component>/                       design/components/<component>/
  src/        the Zig source              README.md   design and state of the work
  build.zig   only evecp, evetx, eveux    design/     drawings and notes of an interface (evetx, eveux)
  build.zig.zon                           doc/        user documents, copied into manual/<component>/
  assets/     optional (evetx: themes)
```

`code/README.md` lists the components and the license. A component built by the root `build.zig` (`eve`, `evecm`, `evevm`) has no build file of its own; `evecp`, `evetx` and `eveux` have one because they are programs with their own dependencies (`evecp` is also a module of the root build). `evewp` has no code yet, so it has only a design folder. Tools that write code (`script/genidekeywords.py` writes `evecm/src/ide/keywords.zig`) are in `script/`.

## How they depend on each other

The modules of `eve` are built by the root `build.zig`; an arrow is an import, and a module that is not listed cannot be imported:

```
eve ──► evevm ──► evecp ──► evecm
           └────► ewp_protocol   (also imported by the DuckDB server of `drivers/duckdb`)
```

The database layer is a part of `evevm` (since 2026-10-19); the interpreter and the layer call each other directly (the interfaces `Host` and `Data` of `evecm` are gone of `design/phase-8-architecture.md`). `evetx` and `eveux` import only the editor part of `evecm` (`evecm/src/ide.zig`) and talk to a machine like any client.

## Building

From the root of the repository (Zig 0.17.0):

| Command | Builds |
|---|---|
| `./run.sh build` | `eve` and `evevm` (`bin/eve.exe`, `bin/evevm.exe`, `lib/`) |
| `./run.sh build <part>` | one part: `eve`, `evevm`, `evecp`, `duckdb` (the server of `drivers/duckdb`), `evetx`, `eveux` |
| `./run.sh build all` | every part |
| `zig build test` | the unit tests of the modules of `eve`; `zig build test` in `drivers/duckdb`, `code/evetx` and `code/eveux` for theirs |

## License

All the components are under one license, the Business Source License 1.1: [LICENSE](../../code/LICENSE). The code becomes Apache License 2.0 on the Change Date written there.
