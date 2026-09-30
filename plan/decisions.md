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

### D-011 Comments (2026-09-28)
From `issues/syntax.md` SYN-03. Eve comments are `#`, `##`, `**`, `(* ... *)` and `/* ... */`.
`#` and `##` start only at the beginning of a line, without indentation. `**` runs to the end of
the line and may follow code or be indented. `(* ... *)` is an expression comment; `/* ... */` is a
block comment. The `--` end-of-line comment and the `+- -+` box comment are removed; all `--`
comments in `.eve` files and tutorial examples were converted to `**`. Amended by D-014:
`(* ... *)` became `(** ... **)`.

### D-012 Identifiers and the driver header (2026-09-28)
From SYN-01, SYN-02. `-` is not allowed in identifiers, to avoid confusion with the `-` operator.
The driver header and the `process` keyword need no `:` (`driver a01_driver()`, `process`).
Amended by D-015: headers end with the keyword `is`.

### D-013 Not-equal is `<>`; `!` marks unsafe operations (2026-09-28)
From SYN-05. `<>` is the not-equal operator; `!=` is not Eve. `!` is the sigil for unsafe
operations (its placement: SYN-19). All `!=` in `.eve` files and tutorial examples became `<>`.

### D-014 Comments: nesting, expression comments, file header (2026-09-28)
From SYN-04, SYN-16, SYN-17, SYN-18.
- `/* ... */` does not nest: the first `*/` closes the comment.
- Expression comments are `(** ... **)` (not `(* ... *)`, which clashes with the vararg `*` in
  `f(*args)`). They may span lines.
- A file starts with `#!` (shebang: a free script of sequential statements, no `driver` or
  `process` needed), `#` (title) or `##` (subtitle).
- Box comments became block comments: `+-` → `/*-` and `-+` → `-*/` in 6 `.eve` files and in the
  tutorial examples; lines of dashes in examples became `**--…`.

### D-015 Declaration headers end with `is` (2026-09-28)
From SYN-15. A header ends with the keyword `is` instead of `:`: `driver name is`,
`driver name(params) is`, and the same for `aspect`, `module`, `function`, `routine`, `method`
and `constructor`. `()` is optional when there are no parameters. `process` has no colon.
Applied to every example: 94 + 61 headers in the tutorial, 53 in `.eve` files. Class headers with
a body still end in `:` (CLS-01 open).

### D-016 Control-flow blocks (2026-09-28)
From SYN-11: the author rewrote control.html and processing.html. General form:
`label: <control_type>` declarations, `<transition>` executable region, optional clauses,
`<terminator>`.

| Block | Syntax |
|---|---|
| job | `name: job` … `do` … `done job [name];` (simplified by D-020) |
| if | `if c do` … `else if c do` … `else` … `done;` |
| match | `label: match s [one \| all]` … `when v1, v2 do` … `when [any \| other] do` … `then` … `done match [label];` |
| loop | `[label:] loop` declarations `cycle` … `then` … `repeat [label];` |
| while | `[label:] loop` declarations `while c cycle` … `else` … `then` … `repeat [label];` |
| for | `[label:] loop` declarations `for x in r cycle` … `repeat [label];` |
| aspect, serial | `apply name to (args);` (waits for the aspect) |
| aspects, parallel | `name: parallel` declarations `fork` … `begin aspect(args);` … `join name;` |

Interruptions: `break` leaves a loop, `next` starts the next iteration, `stop` ends a job without
error. `then` now means "after the block completed"; branches use `do`. Removed: `try`, `catch`,
`resolve`, `skip`, `split`, `run`, `cycle label:` as a header. All tutorial pages and `.eve` files
were converted; syntax.html keyword, block and interruption tables were rebuilt.

### D-017 Assignment, visibility, unsafe calls, shift operators (2026-09-28)
From SYN-06, SYN-08, SYN-10, SYN-19.
- `=` is an expression: no type inference, returns its value, chains (`a = b = 5 : Integer`,
  `let a = b = c = y : Integer;`), copies/borrows a value; also binds typed parameters.
  `:=` infers the type, is a statement (not an expression), and evaluates the right side fully.
- In a declaration, a leading `_` marks a protected member and a leading `.` a public member;
  neither is part of the name. `$` is part of the name (system-wide variable).
- `name!()`: a function or method that may raise, has side effects, or bypasses safety checks.
- `<<` and `>>` are shift modifiers (change a value in place). `->` and `<-` are reserved, unused.

### D-018 Test file names use `_` (2026-09-28)
From SYN-14. Test files follow identifier rules: `a01_driver.eve`, `a02_comments.eve`,
`a03_print.eve` (+ `.out`); conventions `a01_feature.eve`, `b01_feature.eve`, `c01_feature.eve`.

### D-019 Lexical rules: escapes, identifiers, `**`, precedence (2026-09-28)
From SYN-20 to SYN-24.
- Escapes in `"…"` and `'…'`: `\` `\"` `\'` `\{` `\}` `\n` `\r` `\t` `\0` `\xHH` `\u{H…}`
  (1 to 6 hex digits). Any other `\` sequence is a lexical error. `"""…"""` text is raw (no
  escapes). The `&code;` and `\LF` / `\CRLF` forms are dropped.
- Identifiers are case-sensitive, at most 42 characters.
- `**` may appear anywhere, including column 0 and the first line (a row of `*****`).
- `option` is a keyword: a method may declare a second parameter set, passed by name after
  `option`: `method name(*args) option (params)`, called `print (a, b) option (separator = " ");`.
  `print` is such a method; its `separator` defaults to `","`.
- Operator precedence, highest first: `.` `()` `[]` · unary `-` `not` · `^` (right) · `*` `/` `%` ·
  `+` `-` · `..` · `<<` `>>` · `&&` · `||` · `==` `<>` `<` `>` `<=` `>=` `~` `is` `in` `eq` · `and` ·
  `xor` · `or` · `if … else`. May be revised.

### D-020 Jobs without handlers; `recover` decides (2026-09-28)
Replaces the job handlers of D-016. Answers PRC-01, PRC-04, CTL-14; partly PRC-02, CTL-03.
- A job is `label: job` [declarations] `do` … `done job [label];`. The `error`, `other error`,
  `check` and `clean` clauses are removed; `error`, `check` and `clean` are no longer keywords.
  Write jobs that do not fail. Jobs are used only in a process (driver or aspect), at the top
  level, not nested; routines, functions and methods have none. The label is required.
- A job passes at `done` or `stop` and fails when an error is raised in it (also from a called
  routine or method). The status is recorded automatically.
- Any error in a process jumps to its `recover` region. There, normal control statements
  (`if`, `match`) on `$error` (`$error.job` is the failed job's label) choose one of:
  - `retry`: run the failed job again, from its declarations;
  - `resume`: the error is handled, the job stays failed, the process continues after its `done`;
  - `abort`: end the process, run `finalize`, propagate the error to the calling process.
- `retry` and `resume` need a failed job; an error outside a job can only be aborted. Raising an
  error in `recover` aborts with that error. Reaching the end of `recover` handles the error: the
  process ends normally. A process without `recover` aborts on every error.
- `finalize` runs once when the process ends (`return`, `exit`, end of `recover`, `abort`), not
  after `over` or `panic`. Preconditions use `over 1 if condition;` (the old `abort if`).
- `resume` keeps its coroutine meaning (`resume name;`); the bare `resume;` in `recover` is the
  job form. Open: exit code of an aborted driver (D-010).
Applied to control.html, processing.html, syntax.html (keyword tables).
