# Decisions and Open Questions

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. When a question is
answered, turn it into a decision with the date and keep the question text for history. Plan
steps reference these ids.

## Decisions

### D-001 Specification formats (2026-09-28)
The specification is written in Markdown for prose and JSON for machine-readable tables, with
the grammar as EBNF in fenced `ebnf` blocks. No HTML in `spec/`. See `spec/README.md`.

### D-002 Tutorial stays in the scl repo (2026-09-28)
The tutorial remains HTML, published from `scl/projects/eve`, and is edited here through the
`tutorial/` junction. It is git-ignored in eve-lang.

### D-003 Many compilers, one specification (2026-09-28)
Eve has no single reference implementation. Any compiler is valid if it implements a stated spec
version and passes the conformance level it claims. Students are expected to build their own.

## Open questions

### Q-001 Fate of `docs/`
`docs/` holds an older Markdown documentation skeleton: `index.md` plus 20 empty stub pages
(core, db, net, os, std) created by `doc.sh`. Options:
(a) delete `docs/` and `doc.sh`, since `spec/` replaces them;
(b) keep `docs/` for user-level guides (database, network, OS) and link to `spec/`.
Recommended: (a) for the empty stubs, and move any real content into `spec/`.
Blocks: T1.2 cleanup of eve-lang, S2.1.

### Q-002 Canonical keyword list
The tutorial table (`syntax.html#keywords`) has duplicates (`constant`, `method`, `reset`,
`add`, `del`, `pop`) and a typo (`labe`). It lacks words the examples use at region level
(`driver`, `module`, `type`, `globals`). Which words are reserved in 0.1, and which are
contextual (reserved only in some regions)?
Blocks: S2.4.

### Q-003 Stray files in the tutorial folder
`tutorial/quiz.txt` (AI chat transcript), `tutorial/output.log` (UTF-16 PowerShell error log)
and `tutorial/databases.md` (AI review prompts) are not tutorial pages. Delete them, or move
useful parts (quiz questions) into a proper page?
Blocks: T1.2.

### Q-004 `global` or `globals`
`pattern/declaration.eve` uses both `globals` and `global`. Are they two region keywords with
different meanings, or one keyword with a legacy spelling?
Blocks: S3.2.

### Q-005 Expected-output convention for tests
How does a test state its expected result? Options: (a) `expect` statements inside the script
(already used in `demo/shared_state.eve`); (b) a sibling `.out` file with the exact stdout;
(c) both: `expect` for logic, `.out` for print formatting.
Recommended: (c).
Blocks: S5.2.

### Q-006 Specification license
The eve-lang repo is Apache 2.0. Does the specification use the same license, or a documentation
license (for example CC BY 4.0) so other compilers can quote it freely?
Blocks: S2.1.
