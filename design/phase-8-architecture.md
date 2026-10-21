# Phase 8 — The architecture refactor (D-198)

> Rank 4 (refactor) of the order of the work (D-194). Decided in D-198, D-199 and D-200. Reviewed 2026-10-20: stages S8.0 to S8.7 are done and verified in the tree; S8.8 to S8.10a are open. The detail of the finished stages is in the git history of this file.

Goal: one runtime that contains SQLite and the database layer, the compiler as a program that the editors include, and the DuckDB server out of the components.

```
Before                                       After
eve ──► evevm ──► evecp ──► evecm            eve ──► evevm (runtime + database layer + SQLite) ──► evecp ──► evecm
 └────► evedb (database layer, SQLite) ──►   evecp.exe, evetx, eveux ──► evecp ──► evecm
evedb.exe (DuckDB server, same folder)       drivers/duckdb (the DuckDB server: a separate project)
```

## Done (2026-10-19, verified 2026-10-20)

| Stage | Result | Where to see it |
|---|---|---|
| S8.0 Baseline | 399 tests, benchmark totals and sizes recorded before the work | the git history |
| S8.1 Shared protocol | `ewp`, `batch`, `client` are the module `ewp_protocol`, used by the runtime and by the server | `drivers/duckdb/protocol/` |
| S8.2 Database layer in `evevm` | 11 files moved; SQLite linked into `evevm`; the module `evedb` is gone | `code/evevm/src/db/`, `code/evevm/src/db.zig` |
| S8.3 `Data` interface gone | 21 functions called directly | no `interp.data_api` |
| S8.4 `Host` interface gone | `code/evecm/src/iface.zig` deleted | `code/evevm/src/host.zig` |
| S8.4a Driver table | one struct per driver (`sqlite`, `postgres`, `evedb`), chosen by URL scheme; a new driver is one file and one line | `code/evevm/src/db/driver.zig` |
| S8.5 DuckDB server leaves `comp/` | moved to `drivers/`; `run.sh build duckdb`; the zip ships `evedb.exe` | `drivers/duckdb/`, `drivers/README.md` |
| S8.6 `evecp` is a program | `check`, `doc`, `project`; `eve cp X` gives the same output as `evecp X` | `code/evecp/build.zig`, `bin/evecp.exe` |
| S8.7 Tooling entry point (TD-34) | `analyze(gpa, text)`: diagnostics and outline; `evecp outline`, `evecp symbols` | `code/evecp/src/analyze.zig` |

Check of 2026-10-20: `zig build test` passes in the root, in `code/evecp` and in `drivers/duckdb`; all 440 conformance and smoke tests, the 20 bytecode tests and the scaffold test pass; `bin/evecp.exe outline` works.

## How a stage ends

1. Change only what the stage names. Anything outside it goes to `backlog/tech-debt.md`.
2. Run the **gate** of the stage and write down the commands and the numbers.
3. Report: `git diff --stat`, the gate results, what surprised, what the next stage will do. Stop; the next stage starts when the author says so. Commit only when asked.

The common gate: `zig build test` in the root and in the parts the stage touches, and `python script/runtest.py all --eve temp/rel/bin/eve.exe` on the ReleaseSafe build (`zig build -Doptimize=ReleaseSafe -p temp/rel`): every test passes.

## Open stages

### S8.8 `evetx` includes `evecp` `[ ]`
- **Change:** `code/evetx/build.zig` imports `evecp` (today it imports only the shared `ide` module of `evecm`); the editor shows the diagnostics of the open file while typing (a mark in the gutter, the message in the status bar, a list of the errors of the file) without asking a machine; Run and Debug stay on the child machine (`eve --stdio`, D-198 d).
- **Gate:** `zig build test` in `code/evetx`; the headless smoke test of the TUI (`temp/`, memory note `evetx-tui-smoke-test`); the common gate.
- **Review:** the author tries it by hand: open a script, make an error, see the mark.

### S8.9 `eveux` includes `evecp` `[ ]`
- **Change:** `code/eveux/build.zig` imports `evecp`; its logic layer (`src/editor/lang.zig`) calls `analyze` with unit tests. The window is still a draft (TD-35), so no screen work.
- **Gate:** `zig test` of the logic files and `zig build -p ../..` in `code/eveux` (needs Developer Mode, TD-31); the common gate.

### S8.10 Documents and tidy-up `[ ]`
Done so far: `manual/drivers/duckdb/` (from `drivers/duckdb/doc/`), `drivers/README.md`, `design/components/README.md`.
- **Missing:** **a manual page for each client driver** (D-200): `sqlite://`, `postgres://`, `evedb://`, in `design/components/evevm/doc/drivers/` (the folder does not exist yet), copied to `manual/drivers/` by `generator/evegen.py`; `design/design-packages.md` (module table, arrows, the note on D-163); the dist README template (the programs in `bin/`); Q-068 closed into a decision.
- **Gate:** `python script/mdlinks.py check manual`, `python generator/evegen.py check` and `python script/relnotes.py --check` are clean; `./run.sh dist`; the common gate.

### S8.10a DuckDB embedded in `evedb.exe` `[ ]`
- **Change (D-200):** link DuckDB statically into the server program, so the zip needs no `duckdb.dll` (today `drivers/duckdb/build.zig` links the import library and `bin/` holds `duckdb.dll`). **Starts with a spike, reported before any change is kept:** can Zig link the prebuilt static libraries of the release (built with the Microsoft compiler), or must the amalgamation (`duckdb.cpp`) be compiled by Zig? Build time, build memory, size of `evedb.exe`, whether `duckdb.zig` runs unchanged.
- **Gate:** the common gate; `python script/evedb_check.py` and `python script/pg_check.py`; `./run.sh dist` ships `evedb.exe` without `duckdb.dll`. If the spike fails, the DLL stays and the finding goes to `backlog/tech-debt.md`.

## After this phase (not stages of it)

### S8.11 Run and debug in the child machine, with a better protocol `[ ]`
- D-198 (d). Its own design first (a `design/` note, shown before code): breakpoints in every file, step into / over / out, variables and call stack as structured messages, the output of the script on its own channel so it never draws over `evetx`. No change of the process model.

### S8.12 Bytecode (B5, version 6) `[ ]`
- D-198 (e), `design/design-bytecode.md` (answered, D-201). The bytecode machine, the emitter and the golden listings exist and have their own tests (`script/bctest.py`); the `.evb` file, `evecp compile` and moving the syntax tree from `evecm` to `evecp` are open. It gets its own stages when it continues.
