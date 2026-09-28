# Decisions and Open Questions

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. When a question is
answered, turn it into a decision with the date and keep the question text for history. Plan
steps reference these ids.

## Decisions

### D-001 Specification formats (2026-09-28)
The specification is written in Markdown for prose and JSON for machine-readable tables, with
the grammar as EBNF in fenced `ebnf` blocks. No HTML in `spec/`. See `spec/README.md`.

### D-004 `docs/` becomes `manual/`, the compiler manual (2026-09-28)
Answers Q-001. `docs/` is renamed `manual/`: the manual of an Eve implementation, covering how
to implement it, how to use it, what was implemented, and which features it supports. The
feature tables are generated from the spec (JSON items and `ebnf` rules) joined with a support
file per implementation, never edited by hand. The empty stubs and `doc.sh` are removed.
See `manual/README.md` and `plan/phase-7-manual.md`.

### D-005 The manual documents the first Eve compiler, not yet built (2026-09-28)
Answers Q-007. No Eve implementation exists; the first compiler is being built now, together
with the spec. `manual/` is written alongside it: `implement.md` and the feature tables come
first, `usage.md` and `implemented.md` fill in as the compiler runs and ships versions.
Until then every feature counts as `no`.

### D-006 First implementation: an Eve VM written in Zig (2026-09-28)
Answers Q-008 in part. The first Eve implementation is a virtual machine written in Zig that runs
Eve source as a scripting language. There is no ahead-of-time compiler yet. `manual/` documents
this VM; the feature tables have one column for it. A compiler can come later as a second
implementation with its own support file.

### D-007 `evevm/` source, `bin/eve.exe` official implementation (2026-09-28)
Answers Q-009. The Zig source of the Eve virtual machine lives in `evevm/` in this repo. The build
produces `bin/eve.exe` (`bin/eve` on Unix), the official Eve implementation. Its implementation
id in the manual is `eve` (support file `manual/support/eve.json`). `bin/` holds build output
only; `*.exe` is already git-ignored.

### D-008 Shebang line (2026-09-28)
Eve files run as scripts, so a file may start with a shebang line, for example
`#!/usr/bin/env eve`. It is a comment: `#` already starts a line comment, and the VM ignores the
line. The spec states it in `lexical/lexical.md` (S2.3): only the first line of a file is an
interpreter directive; `#!` on a later line is an ordinary `#` comment.

### D-002 Tutorial stays in the scl repo (2026-09-28)
The tutorial remains HTML, published from `scl/projects/eve`, and is edited here through the
`tutorial/` junction. It is git-ignored in eve-lang.

### D-003 Many compilers, one specification (2026-09-28)
Eve has no single reference implementation. Any compiler is valid if it implements a stated spec
version and passes the conformance level it claims. Students are expected to build their own.

## Open questions

### Q-001 Fate of `docs/` (answered 2026-09-28 → D-004)
`docs/` holds an older Markdown documentation skeleton: `index.md` plus 20 empty stub pages
(core, db, net, os, std) created by `doc.sh`. Options:
(a) delete `docs/` and `doc.sh`, since `spec/` replaces them;
(b) keep `docs/` for user-level guides (database, network, OS) and link to `spec/`.
Recommended: (a) for the empty stubs, and move any real content into `spec/`.
Blocks: T1.2 cleanup of eve-lang, S2.1.
Answer: neither; rename to `manual/` as the compiler manual (D-004).

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
Status 2026-09-28: `script/runtest.py` implements (c): `expect` failures surface as a non-zero
exit code, `<name>.out` holds the stdout, and a per-level `expect.json` holds exit codes and
arguments. Confirm, or say what to change.

### Q-006 Specification license
The eve-lang repo is Apache 2.0. Does the specification use the same license, or a documentation
license (for example CC BY 4.0) so other compilers can quote it freely?
Blocks: S2.1.

### Q-007 Which implementation does `manual/` document? (answered 2026-09-28 → D-005)
The old README says the MD docs are "specific to EVE virtual machine hosted in this repository",
but there is no compiler here. What is the implementation's name (the manual uses the
placeholder `evec`), in which repository does its code live, and in which language is it written?
Blocks: M7.7; the support file name in M7.3.
Answer: none yet; Eve is being built now, and its implementation language is undecided (D-005).

### Q-008 Implementation language and name of the first compiler (answered in part 2026-09-28 → D-006)
Which language is the first Eve compiler written in, what is it called (the manual uses the
placeholder `evec` for its support file), and does its code live in this repo or its own?
Doesn't block the generator (M7.3); blocks M7.5 architecture details and M7.6.
Answer: Zig; the first implementation is a VM, not a compiler (D-006). Name and repository → Q-009.

### Q-009 Name and repository of the Eve VM (answered 2026-09-28 → D-007)
What are the VM's name and executable name (the manual uses the placeholder `eve-vm`), and does
its Zig code live in this repo (for example `vm/`) or in its own repository?
Blocks: M7.6 (command-line examples), the support file name in M7.3.
Answer: source folder `evevm/`, executable `bin/eve.exe`, the official implementation (D-007).

### Q-010 Exit codes of an Eve process (answered 2026-09-28 → D-010)
The tutorial lists `exit`, `over` and `panic` as ways to interrupt a program, but gives no exit
codes. Does `over N;` end the process with exit code N? Which codes do `exit`, `panic`, a failed
`expect` and an unhandled error produce? `test/level1/expect.json` assumes `over 1;` → 1 (a02).
The VM stub uses 70 for "not implemented"; the spec could reserve a range for VM failures.
Blocks: S5.2, the exit codes in `expect.json`.
Answer: `over` = 0, `over 1` = 1 (abnormal), failed `expect` = 2 (error), failed `assert` = 3
(warning) (D-010).

### D-009 Test runner and test-driven workflow (2026-09-28)
Tests are written first, then run on the VM with `python script/runtest.py <level|all|test>`.
Reports go to `temp/output/*.md` (not versioned). A failing result leads to a fix in the VM, the
spec or the test, one feature at a time. Utility and test scripts live in `script/`
(moved from `.claude/scripts/`). Usage and conventions: `test/readme.md`.

### D-010 Process exit codes (2026-09-28)
Answers Q-010.

| Code | Cause | Meaning |
|---|---|---|
| 0 | end of `process`, `over` or `over 0;` | normal exit |
| 1 | `over 1;` | forced, abnormal exit: incorrect parameters or environment. Not an error, but the job fails |
| 2 | failed `expect` | error |
| 3 | failed `assert` | warning |

Still open: the codes of `exit`, `panic` and an unhandled error; whether a failed `assert` stops
the process or only sets the final code; which code wins when several apply. The VM stub uses 70
for "not implemented", outside this range.
