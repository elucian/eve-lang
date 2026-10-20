# Plan: less AI context, a better budget (rounded up 2026-10-20)

Goal: an AI session reads less to find and change code, and the code carries its own links to the specification. Rank 4 (refactor) of D-194. The steps A1 to A8 are done; their full text (measures before, notes, checks) is in [archive/design-ai-context-2026-10.md](archive/design-ai-context-2026-10.md).

## Result (2026-10-20)

| What | Before | Now |
|---|---|---|
| `CLAUDE.md` (loaded in every session) | 28,342 bytes | 7,973 (limit 8,000) |
| `// Zig tip:` lines in `code/` and `drivers/` | 4,836 lines | 0 |
| Live decision files (`design/decision/level*.md`) | level6 111 KB, level5 44 KB, level4 28 KB | largest level2 20 KB; limit 25,000 |
| Largest Zig file | `evetx/src/app.zig`, 8,594 lines | `check.zig`, 1,226 lines |
| Feature map | 54 KB read whole | 68 KB, read by `plan.py feature` / `features` (6.6 KB for all 142 lines) |

Measure again with `python script/ctxsize.py` (`--check` fails above the limits).

## What was done

- **A1** `CLAUDE.md` short; the old text is `design/dev-guide.md`. **A2** settled decisions archived (`plan.py archive`); the open questions of levels 5 and 6 answered by the author and archived (A2b, 2026-10-20), and level 7 archived after the evedb move (D-203, D-204). Archiving moves an entry whole and `plan.py show D-nnn` finds it in either place.
- **A3** the `// Zig tip:` blocks deleted (`script/strip_zigtips.py`). **A4** `script/tagcheck.py` checks `@spec`, `@feature`, `@decision` (pre-commit hook); the 24 files of the language core and the split files have a head.
- **A5** `script/ctxsize.py`, `plan.py feature`, `plan.py features`. **A7** the feature map is generated from the feature sections (`script/featmap.py`), by level.
- **A6** the big files split by concern with `script/splitzig.py` and `script/splitfree.py` (plans in `script/splitplans/`): evetx `app.zig` 7,997 → 984 lines + 19 files, `view.zig` 2,657 → 259 + 11, evecp `parser.zig` 2,208 → 422 + 8. No behavior change.
- **A8** the skills `eve-primer`, `eve-test-loop`, `zig-split-file` in `.claude/skills/`.

## Still open (not steps of this plan)

- 52 Zig files have no head tags (the database layer, `tui`, `screen`, `service`, `machine`, the `eve` command, `eveux`, the helpers); they get one when touched. List them with `python script/ctxsize.py --files`.
- Per-function tags (`@eve-fn`, `@spec`) on touch; the evetx files have none (TD-50).
- `design/feature_map.md` is still large; it is read by section only.

## Rules that stay

- Nothing is deleted without an archive or a copy. One step, one commit, tests green before the commit. A decision of the author is not reworded: archive moves it whole.
