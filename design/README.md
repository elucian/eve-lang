# Eve Improvement Plan

Permanent plan of the Eve project. The order of the work is the table under "Current focus" (D-194). The steps of the phases below serve three linked goals (the tutorial is the last of the work, rank 10):

1. **Improve the tutorial** (`tutorial/`, published by the scl repo) so it is correct,
   consistent and teaches everything a compiler author needs.
2. **Write the specification** (`spec/`) in Markdown + JSON, so compilers and tools can load the language rules without scraping HTML.
3. **Write the compiler manual** (`manual/`): how to implement and use an Eve compiler, with feature-support tables generated from the spec.

Eve is an open standard meant to have **many compilers**. Students build their own compiler from the specification and prove it against the conformance tests. Every step below serves that goal.

## This folder

| Path | Holds |
|---|---|
| `README.md` | this plan: the focus, the phases, the rules |
| `phase-*.md` | the steps of each phase |
| `feature_map.md` | a paragraph for each level and a subtitle with a paragraph for every feature, with its status; the tables are generated (`script/featmap.py`) |
| `design-*.md`, `library-audit.md` | the designs of the parts of Eve |
| `design-ai-context.md`, `dev-guide.md` | the plan to cut the AI context (A1 to A8, done; the long text is in `archive/`) and the full development guide that `CLAUDE.md` points to |
| `release.md` | the release policy and the steps of a release (D-153) |
| `manual.md` | how the manual is made: what is written by hand, what is generated |
| `decision/` | `level1.md` to `level7.md`: the decisions and the open questions, by level; `archive/` keeps the settled entries in full |
| `issues/` | the open questions of the tutorial review (three files, 9 questions, each with a suggestion) and the ledger of the closed ones; wording items are in `../backlog/tutorial.md` |
| `review/` | the critical review of the project (second round, 2026-10-20: README, follow-up of the first round, findings); the first round (2026-10-04) is in `archive/review-2026-10-04/` |
| `template/` | the templates of the generators: release notes, the generated pages of the manual, the README of a distribution, an issue page |
| `archive/` | designs and focus notes that were replaced |

Work that is not scheduled yet is in [`../backlog/`](../backlog/README.md): the technical debt, the library gaps, ideas.

## How to use this plan

- Work one piece per session, from the highest rank of the priority table (Current focus). For the steps of the phases: take the first open step (`[ ]`) of the lowest open phase of that rank unless a later step is explicitly unblocked.
- Before starting, mark the step `[~]`. When it is done, mark it `[x]` and add the date and a one-line result, for example `[x] 2026-10-02: 41 keywords, 3 conflicts → D-004`.
- A step needs a decision from the author → mark `[!]`, add a question to
  [`decision/level1.md`](decision/level1.md) or [`decision/level2.md`](decision/level2.md), and move on to the next unblocked step.
- Never delete steps. Obsolete steps become `[-]` with a reason.
- Keep each step small enough for one focused session. Split a step if it grows.

| Mark | Meaning |
|---|---|
| `[ ]` | open |
| `[~]` | in progress |
| `[x]` | done (with date + result) |
| `[!]` | blocked on a decision |
| `[-]` | dropped (with reason) |

## Tracking with few tokens

Do not read the logs whole. `python script/plan.py status` prints the focus, the open steps and the open questions (about 50 lines). `python script/plan.py show D-087 Q-035` prints single entries. Each `decision_level1.md` and `decision_level2.md` holds an index of every id, the open questions and the newest decisions; settled entries are in `design/archive/` with the full text (`python script/plan.py archive --keep 4` moves them; it loses nothing). Append a new `D-`/`Q-` entry at the end of the active file. Mark steps in the phase files as before.

## Current focus (2026-10-18)

2026-10-18 (D-194): the order of the work is plan, design, user interfaces, refactor, optimize, test, spec, compiler, manual, tutorial last. Take the next piece from the highest rank that has open work; `python script/plan.py status` lists the open steps and questions, `backlog/tech-debt.md` the debt.

| Rank | Work | Where |
|---|---|---|
| 1 | Plan | `design/` (decision logs, `feature_map.md`, `tech-debt.md`, `library-gaps.md`) |
| 2 | Design | `design/design-*.md`, the README and `design/` of `code/evetx/`, `code/eveux/`, `code/evewp/`, `drivers/duckdb/` |
| 3 | User interfaces | `code/evetx/` (terminal), `code/eveux/` (native window), `code/evewp/` (web portal) |
| 4 | Refactor | shared code in `code/evecm/` (`code/evecm/src/ide/` is shared by evetx and eveux), module borders (`design/design-packages.md`) |
| 5 | Optimize | `test/bmark/`, `script/bmark.py` |
| 6 | Test | `test/level1` to `level7`, `test/smoke`, `script/runtest.py` (phase 5) |
| 7 | Specification | `spec/` (phases 2 to 4); it follows the tests |
| 8 | Compiler | `code/evecp/`, `code/evevm/`, `code/evecm/`, `drivers/duckdb/`, `code/eve/` (phase 6) |
| 9 | Manual | `manual/` (phase 7) |
| 10 | Tutorial | `tutorial/` (phase 1), last; the steps wait, none is dropped |

**By case (D-196).** The ranks decide what to take; the way through one piece of work depends on its kind.

| Kind of work | Way through |
|---|---|
| A screen or an interface feature | **visual design first** (a drawing, reviewed by the author) → plan entry → code → tests of the logic → spec of the new messages → manual → tutorial |
| A language or compiler feature | plan → design (decision with examples) → failing test → compiler → spec → manual → tutorial |
| A library module | plan (`design-libraries.md`) → failing test → code → spec page → manual |
| A bug | failing test → fix |
| A refactor | tests green → move → tests green; no change of behavior; its own commit |
| An optimization | `bmark.py` before → change → `bmark.py` after |

The old focus (2026-10-07, "tutorial first": the tutorial was reviewed until feature complete, and the spec, the tests and the VM were parked) is over. The tutorial still teaches Eve, but it follows the other work and may lag.

## Features and versions

- [feature_map.md](feature_map.md): **one file to track the project** (D-138): the levels 1 to 7 and every large feature with a code (`F-<area>-<nn>`), its status and its version, with the exit criterion of each version. Mark a feature `✓ done` when it is implemented and tested.
- Decision logs by level: [1](decision/level1.md) single script, [2](decision/level2.md) project, [3](decision/level3.md) data, [4](decision/level4.md) parallel, [5](decision/level5.md) database, [6](decision/level6.md) server, [7](decision/level7.md) web.
- Designs for review: [design-multitasking.md](design-multitasking.md), [design-service.md](design-service.md) (the Eve machine and the server), [design-database-core.md](design-database-core.md) (SQLite core, ORM, transactions) and [design-database-remote.md](design-database-remote.md) (drivers, Eve server, ETL), [evedb](../drivers/duckdb/README.md) (the Eve test database around DuckDB), [design-packages.md](design-packages.md) (the split of the VM into modules and the parts of `eve`, D-163 to D-167, approved 2026-10-12); the first draft [design-database.md](archive/design-database.md) is archived with the author's answers.
- [backlog.md](../backlog/ideas.md): reserved words and ideas without a design.

## Phases

| Phase | File | Goal | Rank (D-194) |
|---|---|---|---|
| 1 | [phase-1-tutorial.md](phase-1-tutorial.md) | Fix and complete the tutorial; add the compiler page | 10 |
| 2 | [phase-2-spec-foundation.md](phase-2-spec-foundation.md) | Spec skeleton, schemas, lexical rules, keywords, operators | 7 |
| 3 | [phase-3-syntax.md](phase-3-syntax.md) | Grammar: regions, statements, expressions, declarations | 7 |
| 4 | [phase-4-semantics.md](phase-4-semantics.md) | Types, scopes, topology, control flow, multitasking | 7 |
| 5 | [phase-5-conformance.md](phase-5-conformance.md) | Built-ins, conformance tests, test levels 1–3 | 6 |
| 6 | [phase-6-compiler-track.md](phase-6-compiler-track.md) | Test-runner contract, compiler registry, approval | 8 |
| 7 | [phase-7-manual.md](phase-7-manual.md) | Compiler manual: implement, use, generated feature tables | 9 |
| 8 | [phase-8-architecture.md](phase-8-architecture.md) | The architecture refactor: one runtime with SQLite, the compiler as a program, the DuckDB server out of the components (D-198) | 4 |

Phases 1 and 2 can run in parallel. Phase 3 needs lexical rules from phase 2. Phase 5 needs the parts of phases 3–4 that its tests cover. Phase 7's generator needs the schemas (S2.2) and grows with each spec JSON file.

## Ground rules

- **The spec is normative, the tutorial is didactic.** When they disagree, the spec wins and the tutorial is fixed, after the author approves the decision in `decision_level1.md` or `decision_level2.md`.
- **Source of truth for tables is JSON.** When a tutorial table (keywords, operators) duplicates spec data, the tutorial table is regenerated from the JSON, not edited by hand. The same holds for every table in `manual/features/`.
- **Evidence over memory.** Extract facts from `tutorial/`, `pattern/` and `test/` with scripts (`temp/`), and cite the source file in the step result.
- **Tutorial changes are committed in the scl repo** (`git -C tutorial …`). Everything else is committed in eve-lang.
- After editing tutorial pages, run `bee-ed balance` on them and `npm run build` in the scl repo (see the scl `GEMINI.md` rules: one `h1`, `h2` sections with `h3` children, hierarchical `data/*.json` sidebars, external links with `target="_blank" rel="noopener noreferrer nofollow"`).
