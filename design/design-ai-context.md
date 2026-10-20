# Plan: less AI context, a better budget (2026-10-20)

Goal: an AI session reads less to find and change code, and the code carries its own links to the specification. Rank 4 (refactor) of D-194. Each step is a separate commit; each has a measure before and after.

## Measures (2026-10-20, before step A1)

| What | Before | After A1 | After the plan |
|---|---|---|---|
| `CLAUDE.md` (loaded in every session) | 28,342 bytes | 7,411 | below 8,000 |
| `// Zig tip:` comment lines in `code/` and `drivers/` | 4,836 lines, 445 KB (about 110k tokens) | same | 0 (done in A3: 4,133 lines removed) |
| `design/decision/level*.md` (live, not archive) | level6 111 KB, level5 44 KB, level4 28 KB, level2 21 KB | same | level6 37 KB, level5 27 KB, level4 20 KB (after A2); below 25 KB after A2b |
| `design/version_map.md` | 54 KB | same | read by section only (outline) |
| largest Zig file | `evetx/src/app.zig`, 8,594 lines | same | below 2,000 lines per file |

Count again with `python script/ctxsize.py` once step A5 writes it (until then the one-off scripts in `temp/`).

## Steps

- **A1 `CLAUDE.md`** `[x]` 2026-10-20. The old file is `design/dev-guide.md` word for word; the new one has build and test, layout in one line per folder, rules of the work, the **Code written for AI** rule (tags that link code to `spec/`, no teaching comments, shape for search), and the budget rules. Check: size above; every command it names exists.
- **A2 Archive settled decisions** `[x]` 2026-10-20. Done with the existing `python script/plan.py archive N --keep K` (levels 4 and 5 keep the last 2 to 8, level 6 the last 4); no stub lines are left in the live files, because `plan.py list` prints every id and `plan.py show D-nnn` finds an entry in either place. Fixed on the way: with `WITH_INDEX = False` the command still appended an index list to the live file (the file grew with each run). Checked: `temp/verify_dec.py` compares every entry (id and text) before and after (no entry lost or changed), `plan.py list` and `plan.py status` give the same output. Result: level6 111 KB → 37 KB, level5 44 KB → 27 KB, level4 28 KB → 20 KB. What stays live is open questions (a `Q-nnn` with an empty `**Answer:**`) and the newest decisions. **A2b (author):** the open questions of level 5 and 6 that later decisions answered (for instance Q-052 to Q-054 by D-174 to D-176) move to the archive when the author fills in the answer line or says they are closed; then level5 and level6 fall below 25 KB.
- **A3 Delete the Zig tips** `[x]` 2026-10-20. `script/strip_zigtips.py` (dry run, `--show N`, `--apply`) removed 4,133 lines of `// Zig tip:` blocks from 88 files of `code/` and `drivers/duckdb/` (4,836 lines were counted at the start, which included plain comments; 0 `Zig tip` left). Every existing `@` tag stayed (compared before and after); a `D-nnn`, `spec/...` path or `F-XXX-nn` named by a deleted tip became a tag when the neighbouring lines did not carry it (`@decision` 51 → 155). Checked: `zig build -p .`, `zig build test` (the first run failed once in a test binary started with `--listen`, the second passed, cause not found: a flaky network test, to watch), ReleaseSafe `runtest.py all --both` 409/409, `zig build test` in `drivers/duckdb` and `code/evetx`; `code/eveux` had no tips. Closes TD-8.
- **A4 Tags on the hot paths** `[~]` 2026-10-20: tool and first sweep done. `script/tagcheck.py` checks every `@spec` (file and anchor, GitHub slugs), `@feature` (row of `version_map.md`) and `@decision` (live or archive) in `code/` and `drivers/`, with lists separated by commas; `--staged` is run by `.githooks/pre-commit`; `--untagged` lists files with no tag. It found 7 wrong tags (five anchors, `F-TLS-31`, a manual anchor): fixed, and `F-TLS-31 eveux: source control` is now a row of version 0.6 (it was announced in `code/eveux/design/notes/elaboration.md` and used by `git_status.zig`). The 24 files of the language core got a head (`@eve-module`, `@spec`, `@feature`, `@decision`, `@tests`): lexer, parser, check, overload, project, ast, value, heap, data, decimal, instant, vm, task, channel, interp and its eight parts. Left: 58 Zig files without a head (the database layer `code/evevm/src/db/`, `tui`, `screen`, `service`, `machine`, the `eve` command, `evetx`, `eveux` and the helpers); they get theirs when touched, or in a later sweep, with `python script/ctxsize.py --files` to list them. Per-function tags (`@eve-fn`) stay on touch.
- **A5 Measure and keep it** `[x]` 2026-10-20. `script/ctxsize.py` prints the table (CLAUDE.md, Zig tip lines, live decision files, version map, the three largest Zig files, Zig files with and without a tag; `--files` lists the untagged ones; `--check` fails above the hard limits: CLAUDE.md 8,000 bytes, 0 tips, a decision file 40,000 bytes, to become 25,000 after A2b). Instead of a front table in `version_map.md` (its tables are parsed by `relnotes.py`, `genpages.py`, `genmanual.py`, so the layout stays), `python script/plan.py feature F-XXX-nn` prints one row and `plan.py features [open|partial|done] [0.5]` prints one line per feature: all 142 features are 6.6 KB instead of 54 KB, and `CLAUDE.md` says to use them.
- **A6 Split the big files** `[ ]` (after A3, which makes the split cheaper). `code/evetx/src/app.zig` first (8.6k lines), then `view.zig`, `parser.zig`, `dlib.zig`; one concern per file, tags on each new head. Only with a green `--both` and no change of behavior (rank 4: refactor, measure the build time before and after).

## Rules while doing it

- Nothing is deleted without an archive or a copy (A1 and A2 move, A3 deletes only teaching text).
- One step, one commit, tests green before the commit; the plan file gets the mark of the step in the same commit.
- A decision of the author is not reworded: archive moves it whole.

## Step A7 (added 2026-10-20): the feature map is generated from feature sections

`design/version_map.md` was 54 KB of table rows with the whole description in a cell, and the status was a hand-kept word in each row; the statuses fell behind the code because nothing tied a feature to its tests or its code (7 features of level 5 were `open` with all their tests passing; two features shared the code F-DAT-13). Now each feature is a subtitle with a `**Status:**` line, an optional `**Tests:**` line and a paragraph; the tables, counts and the Overview column are generated by `script/featmap.py --write` (pre-commit), the code of a table row links to its subtitle, and `--verify` / `--evidence` compare the status with the tests and the `@feature` tags. Debt: TD-48.
