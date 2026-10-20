---
name: eve-test-loop
description: Build and verify changes in the Eve repo (Zig VM, compiler, evetx). Use after editing code/ or lib/, before a commit, or when a test fails and you need the right engine, build mode and command.
---

# Build and test loop

Run everything from the repository root. Scratch files and logs go in `temp/`, never the system temp.

| Goal | Command |
|---|---|
| Fast test build (use for tests, 4.6x faster than Debug) | `zig build -Doptimize=ReleaseSafe -p temp/rel` |
| Conformance tests (tree walker) | `python script/runtest.py all --eve temp/rel/bin/eve.exe` (`1`..`7`, `smoke`, or one test name) |
| Bytecode machine tests and golden listings | `python script/bctest.py --eve temp/rel/bin/eve.exe` (its default `--eve` is `bin/eve.exe`, which may be stale) |
| Both engines agree | `python script/runtest.py all --both --eve temp/rel/bin/eve.exe` (before a release or a big emitter change) |
| Zig unit tests | `zig build test` (exit code 0 is the pass; it prints nothing when cached) |
| evetx (terminal IDE) | `cd code/evetx && zig build -p ../../temp/evetx`, then `zig build test` there; also `drivers/duckdb`, `code/eveux` via `./run.sh build <part>` |
| Performance (VM changes) | `python script/bmark.py --build ReleaseSafe --eve temp/rel/bin/eve.exe --check`, before and after |
| Tags and links | `python script/tagcheck.py`; size budget `python script/ctxsize.py --check` |

## Rules

- Pipe long output to `temp/` and read the tail: `... > temp/output_x.txt 2>&1; tail -5 temp/output_x.txt`.
- `runtest.py` rewrites `test/*/status.json`. If you did not mean to change test results, `git checkout test/*/status.json` before committing.
- Which engine runs which test: conformance tests on the tree walker only; `test/bytecode/` and `test/bmark/` on the bytecode machine (`test/readme.md`, "Which engine runs which test"). Run `bctest.py` after any change of `emit.zig`, `op.zig` or `bcvm.zig`.
- A failing test with `expected output not found: '<text>'` after a pure refactor means a message text changed. Look first at what the refactor did to string literals.
- evetx has no automated screen tests; a pure move of code is verified by the build plus `zig build test`. A headless smoke harness can be rebuilt in `temp/` (pywinpty + pyte, memory `evetx-tui-smoke-test`).
- Commit and push only when the author asks; master only, no branches. Commit messages end with the attribution lines of the session.
- First build compiles SQLite (about 3 minutes).
