# Eve Improvement Plan

Permanent, step-by-step plan for two linked goals:

1. **Improve the tutorial** (`tutorial/`, published by the scl repo) so it is correct,
   consistent and teaches everything a compiler author needs.
2. **Write the specification** (`spec/`) in Markdown + JSON, so compilers and tools can load the language rules without scraping HTML.
3. **Write the compiler manual** (`manual/`): how to implement and use an Eve compiler, with feature-support tables generated from the spec.

Eve is an open standard meant to have **many compilers**. Students build their own compiler from the specification and prove it against the conformance tests. Every step below serves that goal.

## How to use this plan

- Work one step per session. Take the first open step (`[ ]`) of the lowest open phase unless a later step is explicitly unblocked.
- Before starting, mark the step `[~]`. When it is done, mark it `[x]` and add the date and a one-line result, for example `[x] 2026-10-02: 41 keywords, 3 conflicts → D-004`.
- A step needs a decision from the author → mark `[!]`, add a question to
  [`decision_level1.md`](decision_level1.md) or [`decision_level2.md`](decision_level2.md), and move on to the next unblocked step.
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

Do not read the logs whole. `python script/plan.py status` prints the focus, the open steps and the open questions (about 50 lines). `python script/plan.py show D-087 Q-035` prints single entries. Each `decision_level1.md` and `decision_level2.md` holds an index of every id, the open questions and the newest decisions; settled entries are in `plan/archive/` with the full text (`python script/plan.py archive --keep 4` moves them; it loses nothing). Append a new `D-`/`Q-` entry at the end of the active file. Mark steps in the phase files as before.

## Current focus (2026-10-07)

2026-10-07: tutorial first. Phase 2 ends with the page Subprograms (parameters, procedures; D-105); Q-036 is answered (D-106); Q-035 (async, level 4) is open. Level 1 spec and tests (D-094) wait for the author's review, then the VM.

The **tutorial** comes first: it is reviewed and improved until it is good enough and feature complete, because it gives the complete vision of Eve and will shape the architecture of the interpreter. **Parked until the author says go:** the specification (`spec/`, phases 2–4), the test suites (`test/`, phase 5), the virtual machine (`evevm/`) and `demo/`. Design notes in `plan/` continue when they serve the tutorial.

## Features and versions

- [version_map.md](version_map.md): **one file to track the project** (D-138): the levels 1 to 7, the versions 0.1 to 1.0, and every large feature with a code (`F-<area>-<nn>`), its status and its version, with the exit criterion of each version. Mark a feature `✓ done` when it is implemented and tested.
- Decision logs by level: [1](decision_level1.md) single script, [2](decision_level2.md) project, [3](decision_level3.md) data, [4](decision_level4.md) parallel, [5](decision_level5.md) database, [6](decision_level6.md) server, [7](decision_level7.md) web.
- Designs for review: [design-multitasking.md](design-multitasking.md), [design-service.md](design-service.md) (the Eve machine and the server), [design-database-core.md](design-database-core.md) (SQLite core, ORM, transactions) and [design-database-remote.md](design-database-remote.md) (drivers, Eve server, ETL), [evedb](../evedb/README.md) (the Eve test database around DuckDB); the first draft [design-database.md](archive/design-database.md) is archived with the author's answers.
- [backlog.md](backlog.md): reserved words and ideas without a design.

## Phases

| Phase | File | Goal |
|---|---|---|
| 1 | [phase-1-tutorial.md](phase-1-tutorial.md) | Fix and complete the tutorial; add the compiler page |
| 2 | [phase-2-spec-foundation.md](phase-2-spec-foundation.md) | Spec skeleton, schemas, lexical rules, keywords, operators |
| 3 | [phase-3-syntax.md](phase-3-syntax.md) | Grammar: regions, statements, expressions, declarations |
| 4 | [phase-4-semantics.md](phase-4-semantics.md) | Types, scopes, topology, control flow, multitasking |
| 5 | [phase-5-conformance.md](phase-5-conformance.md) | Built-ins, conformance tests, test levels 1–3 |
| 6 | [phase-6-compiler-track.md](phase-6-compiler-track.md) | Test-runner contract, compiler registry, approval |
| 7 | [phase-7-manual.md](phase-7-manual.md) | Compiler manual: implement, use, generated feature tables |

Phases 1 and 2 can run in parallel. Phase 3 needs lexical rules from phase 2. Phase 5 needs the parts of phases 3–4 that its tests cover. Phase 7's generator needs the schemas (S2.2) and grows with each spec JSON file.

## Ground rules

- **The spec is normative, the tutorial is didactic.** When they disagree, the spec wins and the tutorial is fixed, after the author approves the decision in `decision_level1.md` or `decision_level2.md`.
- **Source of truth for tables is JSON.** When a tutorial table (keywords, operators) duplicates spec data, the tutorial table is regenerated from the JSON, not edited by hand. The same holds for every table in `manual/features/`.
- **Evidence over memory.** Extract facts from `tutorial/`, `pattern/` and `test/` with scripts (`temp/`), and cite the source file in the step result.
- **Tutorial changes are committed in the scl repo** (`git -C tutorial …`). Everything else is committed in eve-lang.
- After editing tutorial pages, run `bee-ed balance` on them and `npm run build` in the scl repo (see the scl `GEMINI.md` rules: one `h1`, `h2` sections with `h3` children, hierarchical `data/*.json` sidebars, external links with `target="_blank" rel="noopener noreferrer nofollow"`).
