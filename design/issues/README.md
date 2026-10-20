# Tutorial issues

One file per tutorial topic that still has an open question for the author (page `tutorial/<page>.html` → `design/issues/<page>.md`), from the page-by-page review (plan step T1.10). Since the tutorial is last in the order of the work (D-194) this folder is kept small: only questions that need an answer live here; wording and layout items are in [`backlog/tutorial.md`](../../backlog/tutorial.md); a closed item is a row of the ledger below. The order of the work: [CLAUDE.md](../../CLAUDE.md), `python script/plan.py status`.

## How to answer

Write your answer on the `**Answer:**` line of the issue, replacing `_(open)_`. Short answers are fine ("yes", "use `<>`", "drop it"). Each open issue has a **Suggestion** (dated); "yes" accepts it, "no" and a reason rejects it. A suggestion is not a decision.

When a file is answered, Claude: (1) turns the answer into a decision in `design/decision/levelN.md`; (2) adds the rule to `spec/` after any follow-up question; (3) lists the page fix in `backlog/tutorial.md`; (4) removes the issue and adds its id to the ledger. Ids are stable and retired when removed (the text stays in git history).

## Open (2026-10-20)

| File | Open questions |
|---|---|
| [classes.md](classes.md) | 6: CLS-09, 13, 14, 15, 16, 17b |
| [command.md](command.md) | 2: CMD-04, CMD-05 |
| [option.md](option.md) | 1: OPT-01 with OPT-02 |

## Ledger of the triage of 2026-10-20

Deleted files with nothing open: `control`, `functions`, `index`, `manifest`, `topology`, `types`, `processing`, `collections`, `multitasking`, `compiler`, `library`, `syntax`, `databases`. Reasons, by issue:

| Id | Closed by |
|---|---|
| CLS-12 | `spec/semantics/types.md` (code outside the class cannot add an attribute, Q-031k) and `spec/syntax/declarations.md` (`new self.extra` in a constructor or a method) |
| CLS-I1, CLS-I2 | `backlog/tutorial.md` TB-1, TB-2 |
| CMD-02 | `spec/library/os.md`: `ProcessResult.status` is the exit code (127 when the program can not start), not an error of the language |
| CMD-03 | each run is its own process; `os.run!` takes a `cwd` (see CMD-05) |
| CMD-06 | no `File` or `Folder` class: the `fs` module and `os` (`spec/library/registry.md`) |
| DB-01 | the database layer is level 5 and implemented (117 tests, D-156 to D-188) |
| DB-02 | `from … use (name as alias)`, `spec/semantics/modules.md`, `spec/library/registry.md` |
| DB-03 | `commit;` and `rollback;` only in a job, `spec/library/database.md`; the `update` block of a record |
| DB-04 | debug mode connects, production trusts `db/mappings.json` (D-158), `spec/library/database.md` |
| COL-05 | implemented and tested: `let _ <- m;`, `new head <- q;` in `test/level1/a17_list.eve` |
| COL-16 | `backlog/tutorial.md` TB-4 |
| CON-06 | D-051 removed `wait all` and `wait name`; `wait <duration>` is in `spec/syntax/statements.md` and the level 4 tests |
| CON-11 | `spec/semantics/multitasking.md#parallel-groups` (D-140), level 4 tests |
| CON-12 | `capacity` is required (`multitasking.md`, D-145); the rest (`select`, directed parameters) is in `backlog/ideas.md` |
| CMP-02, CMP-F3 | `backlog/tutorial.md` TB-5 |
| LIB-01, LIB-02 | D-053; `spec/library/strings.md`; what is missing is G-7 of `backlog/library-gaps.md` |
| SPEC-01 | `status` of each word in `spec/lexical/keywords.json`; D-116 made most words contextual |
| SPEC-02 | replaced by D-116 (contextual keywords; the answer "reserved everywhere" no longer holds) |
| SPEC-03 | replaced by D-179 (no free script, no `#!`) |
| SPEC-04 | `spec/lexical/lexical.md` (Interpolation, D-102, D-120): a name or a literal in braces, a format after `%` |
| SPEC-05 | `spec/lexical/lexical.md#layout`: 2 spaces, a tab in the indentation is an error |
| SPEC-06 | D-078: the specification is CC BY-NC-SA 4.0 (`spec/LICENSE`); the license named in the author's answer (CC BY-ND) was replaced |
| TYP-19 | `backlog/tutorial.md` TB-8 (`Date` is in `spec/library/data-language.md#time-types`; an era field is not specified) |
| PRC-10 | `backlog/tutorial.md` TB-6 (the VM side is F-STR-05) |
| OPT-03 | `backlog/tutorial.md` TB-3 |

The template for a new issue file is `design/template/issue.md`.
