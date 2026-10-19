# Phase 8 — The architecture refactor (D-198)

> Rank 4 (refactor) of the order of the work (D-194). Decided in D-198, D-199 and D-200 (answers to Q-067 and Q-068); D-200 closed the questions of Q-068 (the DuckDB server stays an executable and gets DuckDB embedded; a driver table; every driver documented). Ten stages, small, **with a halt after each one** so the author can review the result before the next starts.

Goal: one runtime that contains SQLite and the database layer, the compiler as a program that the editors include, and the DuckDB server out of the components.

```
Before                                       After
eve ──► evevm ──► evecp ──► evecm            eve ──► evevm (runtime + database layer + SQLite) ──► evecp ──► evecm
 └────► evedb (database layer, SQLite) ──►   evecp.exe, evetx, eveux ──► evecp ──► evecm
evedb.exe (DuckDB server, same folder)       drivers/duckdb (the DuckDB server: a separate project)
```

## How a stage ends

1. I change only what the stage names. Anything outside it that I find goes to `backlog/tech-debt.md`, not into the stage.
2. I run the **gate** of the stage and write down the results: the commands, the numbers, and what failed if anything did.
3. I report: `git diff --stat`, the gate results, what surprised me, and what the next stage will do.
4. **I stop.** The next stage starts only when the author says so. I do not commit unless asked; the author can ask for one commit per stage.

The gate of every stage includes these two: `zig build test` in the root (and in the part builds the stage touches), and `python script/runtest.py all --eve temp/rel/bin/eve.exe` on the ReleaseSafe build (`zig build -Doptimize=ReleaseSafe -p temp/rel`, plus `evedb.exe` beside it for the two tests that need the database server): **399 of 399** pass, as today. A stage that cannot say so is not finished.

### S8.0 Baseline `[x]`
2026-10-19: the restructure was committed by the author (`2bebf90`) and the plan in `6bf6458`. Baseline in `temp/stage-baseline.txt`: 399 of 399 tests; unit tests 108 (root: evecm 33, evecp 25, evevm 24, database layer 26) and 22 (the evedb server); ReleaseSafe `eve.exe` 4,066,304 bytes, `evedb.exe` 1,294,848; benchmark totals per level 292.7, 119.8, 198.2, 830.7, 110.1, 1670.8 ms (level 6 includes the server).
- **Needs the author's word:** commit the pending work (the restructure, `comp/`, the rename to `eve`, the manual and the dist tooling: 386 entries today) so that each stage shows as its own diff.
- Record the baseline in `temp/stage-baseline.txt`: the test totals (399 of 399), the number of unit tests of each `zig build test`, the size of the ReleaseSafe `bin/eve.exe` (3.9 MB in `dist/`), and one run of `python script/bmark.py --build ReleaseSafe --eve temp/rel/bin/eve.exe` **without `--save`**. The last saved run is of 0.0.3 (2026-10-13), so `--check` against it would measure seven versions, not this refactor.
- No code changes. **Halt.**

### S8.1 The protocol becomes a shared module `[x]`
2026-10-19: `ewp.zig`, `batch.zig`, `client.zig` are in `comp/evedb/protocol/` and the module `ewp_protocol` is made by the root build and by the server's build. No test lost: the protocol has its own test root (6 tests: the 5 of the files and one block that reaches them).
- **Change:** `ewp.zig`, `batch.zig` and `client.zig` (about 800 lines: the wire protocol between the DuckDB server and the native driver `evedb://`) move to `comp/evedb/protocol/` with a root file `protocol.zig` that exports the three. The module `ewp_protocol` is made from that path by the root build (for the database layer) and by `comp/evedb/build.zig` (for the server). The files that used them (`server.zig`, `cells.zig`, `main.zig`, `ewpdriver.zig`, …) import the module instead of a sibling file. Nothing else moves. (D-199 5: shared, not copied.)
- **Gate:** the common gate; `zig build test` in `comp/evedb`; `python script/evedb_check.py` and `python script/pg_check.py` (the protocol checked from the Python side: they need `pip install psycopg2-binary pg8000`); `eve.exe` and `evedb.exe` within 1% of the baseline size.
- **Review:** the diff of the two build files and the changed import lines; the root build calls no `lazyDependency`, so it never fetches the DuckDB library.
- **Risk:** a Zig file belongs to one module in a compilation. The server and the root build are two compilations, and inside each the files belong to `ewp_protocol` only.

### S8.2 The database layer moves into `evevm` `[x]`
2026-10-19: 11 files moved with `git mv` to `comp/evevm/src/db/`, the former root is `comp/evevm/src/db.zig` (`evevm.db`); SQLite is linked into `evevm`; the module `evedb` is gone from the root build. Unit tests 109 (evecm 33, evecp 25, evevm 45, protocol 6) and 23 in the server; 399 of 399; both Python checks pass; `eve.exe` and `evedb.exe` have the same size as the baseline, to the byte.
- **Change:** `sqlite`, `conn`, `orm`, `state`, `memory`, `columnar`, `dbf`, `importer`, `pgclient`, `pgdriver`, `ewpdriver` (about 4,900 lines) move from `comp/evedb/src/` to `comp/evevm/src/db/`, exposed as `evevm.db`; `evevm` imports `ewp_protocol`. The module `evedb` and its `src/root.zig` disappear from the root `build.zig`; SQLite (C) is linked into `evevm`; `comp/eve` calls `evevm.db`. The interfaces `Host` and `Data` stay as they are.
- **After:** `comp/evedb/` holds the DuckDB server and the protocol module only.
- **Gate:** the common gate; `zig build test` in `comp/evedb`; the two Python checks of S8.1; the ReleaseSafe `eve.exe` within 3% of the baseline size.
- **Review:** `git diff --stat -M` (renames, not rewrites), the root `build.zig` diff, the first-build time of the `evevm` tests (they now compile SQLite once).

### S8.3 The interface `Data` goes `[ ]`
- **Change:** the interpreter calls the database layer directly (`interp/calls.zig`, `datatypes.zig`, `parallel.zig`, `stmt.zig`, `host.zig`) instead of through the function table `interp.data_api`; `comp/eve/eve.zig` no longer plugs it in; `Data` leaves `comp/evecm/src/iface.zig`.
- **Gate:** the common gate; `python script/bmark.py --build ReleaseSafe --eve temp/rel/bin/eve.exe` compared by hand with the baseline: no benchmark more than 10% slower (a direct call should be as fast or faster).
- **Review:** the list of call sites changed, the benchmark table next to the baseline.

### S8.4 The interface `Host` goes `[ ]`
- **Change:** the database layer calls the interpreter helpers directly (evaluate an argument, make a value, raise an error) instead of through `Host`; `comp/evecm/src/iface.zig` is deleted. Both sides are files of the one module `evevm`, so they may import each other.
- **Gate:** the common gate; the benchmark comparison as in S8.3; and the memory check of the project on the Debug build: `EVE_GC_VERIFY=1 python script/runtest.py all` (the database layer builds values, so a count forgotten by a holder would show here).
- **Review:** what each former `Host` function became, any value that crossed the old boundary with a different ownership rule.

### S8.4a The driver table `[ ]`
- **Change (D-200):** one struct of functions per driver (is it my URL, connect, call a method, is it my object, finish the transactions, close), chosen by the URL scheme; `sqlite`, `pgdriver` and `ewpdriver` each register one; the `if` chains of `comp/evevm/src/db/conn.zig` and `state.zig` become a lookup. A new driver is one file and one line in the table. The behavior does not change.
- **Gate:** the common gate; the benchmark comparison as in S8.3 (the lookup is on `connect` and on a method call: no more than 10% slower).
- **Review:** the table definition (the functions a driver must provide) and the three drivers as examples.

### S8.5 The DuckDB server leaves `comp/` `[ ]`
- Decided (D-199, D-200): the program stays `evedb.exe`, launched by `eve` (the command words stay); the zip ships it in `bin/`; `drivers/` has no `LICENSE` file and the root license applies to it. See `design/design-drivers.md`.
- **Change:** `comp/evedb/` moves to `drivers/duckdb/` with its build, demo, README and the `protocol/` module (the root build then reads `drivers/duckdb/protocol/protocol.zig`); `run.sh build` gets the part word `duckdb` (and `evedb` stays an alias); `script/dist.py` builds it from the new place; `script/relnotes.py` and `script/genmanual.py` list it apart from the components; `drivers/README.md` is written; the root README's license section names `drivers/` and the Licensed Work line of `comp/LICENSE` names it (D-200); the launchers `eve db serve` and `eve -s -db --serve` stay.
- **Gate:** the common gate (the two level 6 tests start the server); `zig build test` in `drivers/duckdb`; the two Python checks of S8.1; `./run.sh dist` produces a zip that holds the server in `bin/`.
- **Review:** the tree (`comp/` now has seven folders), the new `drivers/README.md`, the manual page of the driver.

### S8.6 `evecp` becomes a program `[ ]`
- **Change:** `comp/evecp/` gets `build.zig`, `build.zig.zon` and `src/main.zig`; `bin/evecp.exe` with `check`, `doc`, `project init|new` (the commands of `comp/eve/cp_cmds.zig`, whose logic moves into `evecp` as one file); `eve cp ...` calls that same code in the `eve` process. `run.sh build evecp`; `dist.py` ships `bin/evecp.exe`; the manual page of `evecp` shows the commands. The module stays also in the root build, for `evevm`.
- **Gate:** the common gate; a script in `temp/` runs ten commands both ways (`evecp X` and `eve cp X`: good and bad scripts, `doc`, `project new`) and compares the output and the exit code byte for byte; `zig build test` in `comp/evecp`.
- **Review:** the comparison table, the size of `evecp.exe`, the new `comp/evecp/` listing.

### S8.7 The tooling entry point of `evecp` (TD-34) `[ ]`
- **Change:** one call, text in, result out: the diagnostics (file, line, column, message), the outline (aspects, processes, functions, classes) and the symbols with their positions. Unit tests on sources of `test/`; `evecp outline <file>` and `evecp symbols <file>` as a way to look at it. The type names and the call shape are shown in the report **before** the editors depend on them.
- **Gate:** the common gate; the new unit tests; TD-34 is paid in `backlog/tech-debt.md`.
- **Review:** the API as written, a sample output of `evecp outline` on a test script.

### S8.8 `evetx` includes `evecp` `[ ]`
- **Change:** `comp/evetx/build.zig` imports `evecp` (and `evecm`); the editor shows the diagnostics of the open file while typing (a mark in the gutter, the message in the status bar, a list of the errors of the file) without asking a machine; Run and Debug stay on the child machine (`eve --stdio`, D-198 d).
- **Gate:** `zig build test` in `comp/evetx`; the headless smoke test of the TUI (`temp/`, see the memory note `evetx-tui-smoke-test`); the common gate for the rest.
- **Review:** **the author tries it by hand** (the project rule for the screen of evetx): open a script, make an error, see the mark; a screen capture from the smoke harness in the report.

### S8.9 `eveux` includes `evecp` `[ ]`
- **Change:** `comp/eveux/build.zig` imports `evecp`; its logic layer (`src/editor/lang.zig` and the check that the editor will show) calls the entry point of S8.7, with unit tests. The window is still a draft (TD-35), so no screen work.
- **Gate:** `zig test` of the logic files and `zig build -p ../..` in `comp/eveux` (needs Developer Mode, TD-31); the common gate.
- **Review:** the diff of the build file and the new tests.

### S8.10 Documents and tidy-up `[ ]`
- **Change:** **a manual page for every driver** (D-200): `sqlite://`, `postgres://`, `evedb://` (the client drivers, in `comp/evevm/doc/drivers/`) and the DuckDB server (`drivers/duckdb/doc/`), copied into `manual/drivers/` by `script/genmanual.py`; `comp/README.md` (table and graph), `drivers/README.md`, `design/design-packages.md` (the module table, the arrows, the note on D-163), `design/version_map.md` F-VM-11, `CLAUDE.md`, the READMEs and `doc/` of `evevm` and `evecp`, the manual front page and the program table, the dist README template (the programs in `bin/`), `backlog/tech-debt.md` (paid TD-34, new lines). `Q-068` closed into a decision.
- **Gate:** `python script/mdlinks.py check` shows no new broken link; `python script/genmanual.py --check` and `python script/relnotes.py --check` are clean; `./run.sh dist`; the common gate once more, now on the whole.
- **Review:** the final tree, the module graph, the numbers of the baseline next to the numbers now.

### S8.10a DuckDB embedded in `evedb.exe` `[ ]`
- **Change (D-200):** link DuckDB statically into the server program, so the zip needs no `duckdb.dll`. **Starts with a spike, reported before any change is kept:** can Zig link the prebuilt static libraries of the release (built with the Microsoft compiler), or must the amalgamation (`duckdb.cpp`) be compiled by Zig? The build time, the memory the build needs, the size of `evedb.exe`, and whether the binding `duckdb.zig` runs unchanged.
- **Gate:** the common gate; `python script/evedb_check.py` and `python script/pg_check.py`; `./run.sh dist` ships `evedb.exe` without `duckdb.dll`.
- **Review:** the spike numbers, then the size and build-time cost against the DLL. If it does not work, the DLL stays and the finding goes to `backlog/tech-debt.md`.

## After this phase (not stages of it)

### S8.11 Run and debug in the child machine, with a better protocol `[ ]`
- D-198 (d). Its own design first (a `design/` note, shown before code): breakpoints in every file (aspects and modules, not only the main script), step into / over / out, the variables and the call stack as structured messages, the output of the script on its own channel so it never draws over `evetx`. It needs no change of the process model.

### S8.12 Bytecode (B5, version 6) `[ ]`
- D-198 (e), `design/design-packages.md` §10 B5 and the author's note "move bytecode in version 6": the `.evb` format and the instructions, the emitter and `evecp compile` in `evecp`, the syntax tree moving from `evecm` to `evecp`, the bytecode machine in `evevm`. It gets its own stages when it starts; it is large, and the stages above make it smaller (one runtime, the compiler a program).
