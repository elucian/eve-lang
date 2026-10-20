# Plan: less AI context, a better budget (2026-10-20)

Goal: an AI session reads less to find and change code, and the code carries its own links to the specification. Rank 4 (refactor) of D-194. Each step is a separate commit; each has a measure before and after.

## Measures (2026-10-20, before step A1)

| What | Before | After A1 | After the plan |
|---|---|---|---|
| `CLAUDE.md` (loaded in every session) | 28,342 bytes | 7,411 | below 8,000 |
| `// Zig tip:` comment lines in `code/` and `drivers/` | 4,836 lines, 445 KB (about 110k tokens) | same | 0 |
| `design/decision/level*.md` (live, not archive) | level6 111 KB, level5 44 KB, level4 28 KB, level2 21 KB | same | each below 25 KB |
| `design/version_map.md` | 54 KB | same | read by section only (outline) |
| largest Zig file | `evetx/src/app.zig`, 8,594 lines | same | below 2,000 lines per file |

Count again with `python script/ctxsize.py` once step A5 writes it (until then the one-off scripts in `temp/`).

## Steps

- **A1 `CLAUDE.md`** `[x]` 2026-10-20. The old file is `design/dev-guide.md` word for word; the new one has build and test, layout in one line per folder, rules of the work, the **Code written for AI** rule (tags that link code to `spec/`, no teaching comments, shape for search), and the budget rules. Check: size above; every command it names exists.
- **A2 Archive settled decisions** `[ ]`. Move the settled entries of `design/decision/level2.md` to `level6.md` (and `level1`, `level7` if over 25 KB) to `design/decision/archive/`, in full, keeping a one-line stub per decision (id, title, date, status, pointer) in the live file. `python script/plan.py show D-nnn` must still print any entry; `plan.py status` and `plan.py list` must give the same output as before. Settled = all its `(n)` items have an author answer and no `[ ]` open mark. Write the mover as `script/archive_decisions.py` (dry run first), run it level by level, commit each.
- **A3 Delete the Zig tips** `[ ]`. Script `script/strip_zigtips.py`: removes every comment block that starts with `// Zig tip:` (a `//` block up to the first line that is a blank, a non-comment, or an `// @` tag line) and keeps all `@` tags, `///` and `//!` lines. Dry run with counts per file; then per module in this order: `evecm`, `evecp`, `evevm`, `eve`, `drivers/duckdb`, `evetx`, `eveux`. After each module: `zig build -p .`, `zig build test`, `runtest.py all --both` (evetx and eveux: unit tests only). A tip that explains a decision (not Zig) is moved to the `design/` page or `README.md` of its module before it is deleted; when in doubt, keep it and list it in `backlog/tech-debt.md`. Closes TD-8.
- **A4 Tags on the hot paths** `[ ]`. On touch only (no sweep): add `@spec` and `@feature` to the files that lack them, starting with the ones the tests of levels 1 to 3 cover (`code/evecp/src/parser.zig`, `check.zig`, `code/evevm/src/interp*.zig`, `bcvm.zig`). Count: `grep -rL "@spec" code/*/src --include=*.zig` shrinks each commit. A tool `script/tagcheck.py` reports files without a head, `@spec` values whose page or anchor does not exist, and `@feature` ids missing from `version_map.md`; the pre-commit hook runs it on the changed files.
- **A5 Measure and keep it** `[ ]`. `script/ctxsize.py` prints the table above (bytes of `CLAUDE.md`, tip lines, live decision files, largest Zig files, files without tags) so the numbers stay honest; `--check` fails above the targets. Also: `version_map.md` gets a short front table (levels and counts) so an AI reads 60 lines, not 54 KB.
- **A6 Split the big files** `[ ]` (after A3, which makes the split cheaper). `code/evetx/src/app.zig` first (8.6k lines), then `view.zig`, `parser.zig`, `dlib.zig`; one concern per file, tags on each new head. Only with a green `--both` and no change of behavior (rank 4: refactor, measure the build time before and after).

## Rules while doing it

- Nothing is deleted without an archive or a copy (A1 and A2 move, A3 deletes only teaching text).
- One step, one commit, tests green before the commit; the plan file gets the mark of the step in the same commit.
- A decision of the author is not reworded: archive moves it whole.
