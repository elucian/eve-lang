# Eve Improvement Plan

Permanent, step-by-step plan for two linked goals:

1. **Improve the tutorial** (`tutorial/`, published by the scl repo) so it is correct,
   consistent and teaches everything a compiler author needs.
2. **Write the specification** (`spec/`) in Markdown + JSON, so compilers and tools can load the
   language rules without scraping HTML.
3. **Write the compiler manual** (`manual/`): how to implement and use an Eve compiler, with
   feature-support tables generated from the spec.

Eve is an open standard meant to have **many compilers**. Students build their own compiler
from the specification and prove it against the conformance tests. Every step below serves
that goal.

## How to use this plan

- Work one step per session. Take the first open step (`[ ]`) of the lowest open phase unless
  a later step is explicitly unblocked.
- Before starting, mark the step `[~]`. When it is done, mark it `[x]` and add the date and a
  one-line result, for example `[x] 2026-10-02: 41 keywords, 3 conflicts → D-004`.
- A step needs a decision from the author → mark `[!]`, add a question to
  [`decisions.md`](decisions.md), and move on to the next unblocked step.
- Never delete steps. Obsolete steps become `[-]` with a reason.
- Keep each step small enough for one focused session. Split a step if it grows.

| Mark | Meaning |
|---|---|
| `[ ]` | open |
| `[~]` | in progress |
| `[x]` | done (with date + result) |
| `[!]` | blocked on a decision |
| `[-]` | dropped (with reason) |

## Phases

| Phase | File | Goal |
|---|---|---|
| 1 | [phase-1-tutorial.md](phase-1-tutorial.md) | Fix and complete the tutorial; add the compiler page |
| 2 | [phase-2-spec-foundation.md](phase-2-spec-foundation.md) | Spec skeleton, schemas, lexical rules, keywords, operators |
| 3 | [phase-3-syntax.md](phase-3-syntax.md) | Grammar: regions, statements, expressions, declarations |
| 4 | [phase-4-semantics.md](phase-4-semantics.md) | Types, scopes, topology, control flow, concurrency |
| 5 | [phase-5-conformance.md](phase-5-conformance.md) | Built-ins, conformance tests, test levels 1–3 |
| 6 | [phase-6-compiler-track.md](phase-6-compiler-track.md) | Test-runner contract, compiler registry, approval |
| 7 | [phase-7-manual.md](phase-7-manual.md) | Compiler manual: implement, use, generated feature tables |

Phases 1 and 2 can run in parallel. Phase 3 needs lexical rules from phase 2. Phase 5 needs
the parts of phases 3–4 that its tests cover. Phase 7's generator needs the schemas (S2.2) and
grows with each spec JSON file.

## Ground rules

- **The spec is normative, the tutorial is didactic.** When they disagree, the spec wins and
  the tutorial is fixed, after the author approves the decision in `decisions.md`.
- **Source of truth for tables is JSON.** When a tutorial table (keywords, operators) duplicates
  spec data, the tutorial table is regenerated from the JSON, not edited by hand. The same holds
  for every table in `manual/features/`.
- **Evidence over memory.** Extract facts from `tutorial/`, `demo/`, `pattern/` and `test/` with
  scripts (`temp/`), and cite the source file in the step result.
- **Tutorial changes are committed in the scl repo** (`git -C tutorial …`). Everything else is
  committed in eve-lang.
- After editing tutorial pages, run `bee-ed balance` on them and `npm run build` in the scl repo
  (see the scl `GEMINI.md` rules: one `h1`, `h2` sections with `h3` children, hierarchical
  `data/*.json` sidebars, external links with `target="_blank" rel="noopener noreferrer nofollow"`).
