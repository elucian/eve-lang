# Decisions, level 1: project and single script

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. When a question is
answered, turn it into a decision with the date and keep the question text for history. Plan
steps reference these ids.

The log is split in two files. Ids are shared and keep counting across both (an id not found
here is in the other file); a new entry goes to the file of its topic:

- [decision_level1.md](decision_level1.md): the project (formats, repositories, licenses, the VM, tests)
  and the language of a single script (lexical rules, control flow, types, collections, functions,
  classes, errors in a driver). Matches `test/level1`.
- [decision_level2.md](decision_level2.md): programs made of several files: processes, aspects,
  modules and imports, libraries, multitasking and parallel aspects. Matches `test/level2`.

## D-001 Specification formats (2026-09-28)
The specification is written in Markdown for prose and JSON for machine-readable tables, with
the grammar as EBNF in fenced `ebnf` blocks. No HTML in `spec/`. See `spec/README.md`.

## D-004 `docs/` becomes `manual/`, the compiler manual (2026-09-28)
Answers Q-001. `docs/` is renamed `manual/`: the manual of an Eve implementation, covering how
to implement it, how to use it, what was implemented, and which features it supports. The
feature tables are generated from the spec (JSON items and `ebnf` rules) joined with a support
file per implementation, never edited by hand. The empty stubs and `doc.sh` are removed.
See `manual/README.md` and `plan/phase-7-manual.md`.

## D-005 The manual documents the first Eve compiler, not yet built (2026-09-28)
Answers Q-007. No Eve implementation exists; the first compiler is being built now, together
with the spec. `manual/` is written alongside it: `implement.md` and the feature tables come
first, `usage.md` and `implemented.md` fill in as the compiler runs and ships versions.
Until then every feature counts as `no`.

## D-006 First implementation: an Eve VM written in Zig (2026-09-28)
Answers Q-008 in part. The first Eve implementation is a virtual machine written in Zig that runs
Eve source as a scripting language. There is no ahead-of-time compiler yet. `manual/` documents
this VM; the feature tables have one column for it. A compiler can come later as a second
implementation with its own support file.

## D-007 `evevm/` source, `bin/eve.exe` official implementation (2026-09-28)
Answers Q-009. The Zig source of the Eve virtual machine lives in `evevm/` in this repo. The build
produces `bin/eve.exe` (`bin/eve` on Unix), the official Eve implementation. Its implementation
id in the manual is `eve` (support file `manual/support/eve.json`). `bin/` holds build output
only; `*.exe` is already git-ignored.

## D-008 Shebang line (2026-09-28)
Eve files run as scripts, so a file may start with a shebang line, for example
`#!/usr/bin/env eve`. It is a comment: `#` already starts a line comment, and the VM ignores the
line. The spec states it in `lexical/lexical.md` (S2.3): only the first line of a file is an
interpreter directive; `#!` on a later line is an ordinary `#` comment.

## D-002 Tutorial stays in the scl repo (2026-09-28)
The tutorial remains HTML, published from `scl/projects/eve`, and is edited here through the
`tutorial/` junction. It is git-ignored in eve-lang.

## D-003 Many compilers, one specification (2026-09-28)
Eve has no single reference implementation. Any compiler is valid if it implements a stated spec
version and passes the conformance level it claims. Students are expected to build their own.

## Q-001 Fate of `docs/` (answered 2026-09-28 → D-004)
`docs/` holds an older Markdown documentation skeleton: `index.md` plus 20 empty stub pages
(core, db, net, os, std) created by `doc.sh`. Options:
(a) delete `docs/` and `doc.sh`, since `spec/` replaces them;
(b) keep `docs/` for user-level guides (database, network, OS) and link to `spec/`.
Recommended: (a) for the empty stubs, and move any real content into `spec/`.
Blocks: T1.2 cleanup of eve-lang, S2.1.
Answer: neither; rename to `manual/` as the compiler manual (D-004).

## Q-002 Canonical keyword list
The tutorial table (`syntax.html#keywords`) has duplicates (`constant`, `method`, `reset`,
`add`, `del`, `pop`) and a typo (`labe`). It lacks words the examples use at region level
(`driver`, `module`, `type`, `globals`). Which words are reserved in 0.1, and which are
contextual (reserved only in some regions)?
Blocks: S2.4.

## Q-003 Stray files in the tutorial folder
`tutorial/quiz.txt` (AI chat transcript), `tutorial/output.log` (UTF-16 PowerShell error log)
and `tutorial/databases.md` (AI review prompts) are not tutorial pages. Delete them, or move
useful parts (quiz questions) into a proper page?
Blocks: T1.2.

## Q-004 `global` or `globals`
`pattern/declaration.eve` uses both `globals` and `global`. Are they two region keywords with
different meanings, or one keyword with a legacy spelling?
Blocks: S3.2.

## Q-005 Expected-output convention for tests
How does a test state its expected result? Options: (a) `expect` statements inside the script
(already used in `demo/shared_state.eve`); (b) a sibling `.out` file with the exact stdout;
(c) both: `expect` for logic, `.out` for print formatting.
Recommended: (c).
Blocks: S5.2.
Status 2026-09-28: `script/runtest.py` implements (c): `expect` failures surface as a non-zero
exit code, `<name>.out` holds the stdout, and a per-level `expect.json` holds exit codes and
arguments. Confirm, or say what to change.

## Q-006 Specification license
The eve-lang repo is Apache 2.0. Does the specification use the same license, or a documentation
license (for example CC BY 4.0) so other compilers can quote it freely?
Blocks: S2.1.

## Q-007 Which implementation does `manual/` document? (answered 2026-09-28 → D-005)
The old README says the MD docs are "specific to EVE virtual machine hosted in this repository",
but there is no compiler here. What is the implementation's name (the manual uses the
placeholder `evec`), in which repository does its code live, and in which language is it written?
Blocks: M7.7; the support file name in M7.3.
Answer: none yet; Eve is being built now, and its implementation language is undecided (D-005).

## Q-008 Implementation language and name of the first compiler (answered in part 2026-09-28 → D-006)
Which language is the first Eve compiler written in, what is it called (the manual uses the
placeholder `evec` for its support file), and does its code live in this repo or its own?
Doesn't block the generator (M7.3); blocks M7.5 architecture details and M7.6.
Answer: Zig; the first implementation is a VM, not a compiler (D-006). Name and repository → Q-009.

## Q-009 Name and repository of the Eve VM (answered 2026-09-28 → D-007)
What are the VM's name and executable name (the manual uses the placeholder `eve-vm`), and does
its Zig code live in this repo (for example `vm/`) or in its own repository?
Blocks: M7.6 (command-line examples), the support file name in M7.3.
Answer: source folder `evevm/`, executable `bin/eve.exe`, the official implementation (D-007).

## Q-010 Exit codes of an Eve process (answered 2026-09-28 → D-010)
The tutorial lists `exit`, `over` and `panic` as ways to interrupt a program, but gives no exit
codes. Does `over N;` end the process with exit code N? Which codes do `exit`, `panic`, a failed
`expect` and an unhandled error produce? `test/level1/expect.json` assumes `over 1;` → 1 (a02).
The VM stub uses 70 for "not implemented"; the spec could reserve a range for VM failures.
Blocks: S5.2, the exit codes in `expect.json`.
Answer: `over` = 0, `over 1` = 1 (abnormal), failed `expect` = 2 (error), failed `assert` = 3
(warning) (D-010).

## D-009 Test runner and test-driven workflow (2026-09-28)
Tests are written first, then run on the VM with `python script/runtest.py <level|all|test>`.
Reports go to `temp/output/*.md` (not versioned). A failing result leads to a fix in the VM, the
spec or the test, one feature at a time. Utility and test scripts live in `script/`
(moved from `.claude/scripts/`). Usage and conventions: `test/readme.md`.

## D-010 Process exit codes (2026-09-28)
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

## D-011 Comments (2026-09-28)
From `issues/syntax.md` SYN-03. Eve comments are `#`, `##`, `**`, `(* ... *)` and `/* ... */`.
`#` and `##` start only at the beginning of a line, without indentation. `**` runs to the end of
the line and may follow code or be indented. `(* ... *)` is an expression comment; `/* ... */` is a
block comment. The `--` end-of-line comment and the `+- -+` box comment are removed; all `--`
comments in `.eve` files and tutorial examples were converted to `**`. Amended by D-014:
`(* ... *)` became `(** ... **)`.

## D-012 Identifiers and the driver header (2026-09-28)
From SYN-01, SYN-02. `-` is not allowed in identifiers, to avoid confusion with the `-` operator.
The driver header and the `process` keyword need no `:` (`driver a01_driver()`, `process`).
Amended by D-015: headers end with the keyword `is`.

## D-013 Not-equal is `<>`; `!` marks unsafe operations (2026-09-28)
From SYN-05. `<>` is the not-equal operator; `!=` is not Eve. `!` is the sigil for unsafe
operations (its placement: SYN-19). All `!=` in `.eve` files and tutorial examples became `<>`.

## D-014 Comments: nesting, expression comments, file header (2026-09-28)
From SYN-04, SYN-16, SYN-17, SYN-18.
- `/* ... */` does not nest: the first `*/` closes the comment.
- Expression comments are `(** ... **)` (not `(* ... *)`, which clashes with the vararg `*` in
  `f(*args)`). They may span lines.
- A file starts with `#!` (shebang: a free script of sequential statements, no `driver` or
  `process` needed), `#` (title) or `##` (subtitle).
- Box comments became block comments: `+-` → `/*-` and `-+` → `-*/` in 6 `.eve` files and in the
  tutorial examples; lines of dashes in examples became `**--…`.

## D-015 Declaration headers end with `is` (2026-09-28)
From SYN-15. A header ends with the keyword `is` instead of `:`: `driver name is`,
`driver name(params) is`, and the same for `aspect`, `module`, `function`, `routine`, `method`
and `constructor`. `()` is optional when there are no parameters. `process` has no colon.
Applied to every example: 94 + 61 headers in the tutorial, 53 in `.eve` files. Class headers with
a body still end in `:` (CLS-01 open).

## D-016 Control-flow blocks (2026-09-28)
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

## D-017 Assignment, visibility, unsafe calls, shift operators (2026-09-28)
From SYN-06, SYN-08, SYN-10, SYN-19.
- `=` is an expression: no type inference, returns its value, chains (`a = b = 5 : Integer`,
  `let a = b = c = y : Integer;`), copies/borrows a value; also binds typed parameters.
  `:=` infers the type, is a statement (not an expression), and evaluates the right side fully.
- In a declaration, a leading `_` marks a protected member and a leading `.` a public member;
  neither is part of the name. `$` is part of the name (system-wide variable).
- `name!()`: a function or method that may raise, has side effects, or bypasses safety checks.
- `<<` and `>>` are shift modifiers (change a value in place). `->` and `<-` are reserved, unused.

## D-018 Test file names use `_` (2026-09-28)
From SYN-14. Test files follow identifier rules: `a01_driver.eve`, `a02_comments.eve`,
`a03_print.eve` (+ `.out`); conventions `a01_feature.eve`, `b01_feature.eve`, `c01_feature.eve`.

## D-019 Lexical rules: escapes, identifiers, `**`, precedence (2026-09-28)
From SYN-20 to SYN-24.
- Escapes in `"…"` and `'…'`: `\` `\"` `\'` `\{` `\}` `\n` `\r` `\t` `\0` `\xHH` `\u{H…}`
  (1 to 6 hex digits). Any other `\` sequence is a lexical error. `"""…"""` text is raw (no
  escapes). The `&code;` and `\LF` / `\CRLF` forms are dropped.
- Identifiers are case-sensitive, at most 42 characters.
- `**` may appear anywhere, including column 0 and the first line (a row of `*****`).
- `option` was a keyword: a method could declare a second parameter set, passed by name after
  `option`: `method name(*args) option (params)`. Removed by D-029.
  `print` is such a method; its `separator` defaults to `","`.
- Operator precedence, highest first: `.` `()` `[]` · unary `-` `not` · `^` (right) · `*` `/` `%` ·
  `+` `-` · `..` · `<<` `>>` · `&&` · `||` · `==` `<>` `<` `>` `<=` `>=` `~` `is` `in` `eq` · `and` ·
  `xor` · `or` · `if … else`. May be revised.

## D-020 Jobs without handlers; `recover` decides (2026-09-28)
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

## D-021 `$` is the last index; indexing is 1-based (2026-09-30)
From COL-06. Idea from bee-lang (D1). Eve indexes lists, arrays, matrices and strings from 1.
- In an index, a bare `$` is the index of the last element: `a[$]`, `a[$ - 1]`, `mat[3, $]`.
  `#` is not an index symbol: it would clash with `#{…}` interpolation (`"#{a[#]}"`).
- `$` followed by an identifier character is still a system variable (`$error`, D-017); a bare `$`
  inside `[ ]` is the end anchor. `$` is only valid as an index or inside a range that is an index.
- Index 0 and negative indexes are errors (`a[0]`, `a[-1]`); use `a[$ - 2]` for relative access.

## D-022 Ranges: exclusive ends, postfix step, slices use `..` (2026-09-30)
From TYP-10, COL-08. Idea from bee-lang (D13).
- Range operators: `a..b` is [a, b]; `a..<b` is [a, b); `a>..b` is (a, b]; `a>..<b` is (a, b).
  Each is one token (longest match). Open ends keep `?`: `(0..?)`, `(?..0)`.
- The step is a second parenthesised value after the range: `(min..max)(step)`, for example
  `(0..10)(2)` or `(1..5)(0.1)[3]` (= 1.3). The `(min..max:step)` form is removed. The step also
  sets the precision (TYP-11). A range type is `Type Small = (0..1)(0.1) <: Range;`.
- A range is a value, not an array: `new a = (x..y)(n);` makes a range. The only way to put a
  range in an array is the builder (D-023).
- Slices use ranges as indexes: `base[6..$]`, `base[x..x + 3]`. The `[n:m]` form is removed, so `:`
  keeps its pair meaning only. Brackets never define a range or domain by themselves.
- Applied to demo/domain_demo.eve, demo/numeric_range.eve and the tutorial pages collections, control
  and types (`[#]` became `[$]`, `(a..b:step)` became `(a..b)(step)`, `[n:m]` became `[n..m]`).

## D-023 Arrays from ranges use the builder only (2026-09-30)
From a discussion of `[1..10](2)`. The builder `[x | x in (1..10)(2)]` is the only way to fill an
array from a range. The shorthands `[1..10]` and `[1..10](2)` are not Eve: a bracket after a value
is indexing or slicing (`a[1..10](2)` stays free for stepped slices), and brackets never define a
range (D-022). The array type stays `[]Integer` / `[10]Integer`: `new a := [x | x in (1..10)(2)]: []Integer;`.

## D-024 Cartesian product is `><` (2026-09-30)
From the matrix builder example. `a >< b` is the cartesian product of two collections or ranges: a
sequence of pairs in row-major order (the left operand is the outer loop), for example
`(x, y) in (1..4) >< (1..4)`. It is one token (longest match), not `>` then `<`. It is easy to confuse
with `<>` (not equal), so the compiler reports a hint when `><` has operands that are not
collections or ranges (`did you mean <>?`), and when `<>` has two collections or ranges. A builder can
also use several generators (`x in A and y in B`), which gives the same product without `><`.

## D-025 No routines: a method is any subprogram with side effects (2026-09-30)
Answers FUN-03, FUN-09, FUN-I1, TYP-17, CON-01, CMD-01. Amends D-015 and D-016.
- There are two subprogram keywords: `function` and `method`. `routine` (and procedure) is removed.
- A plain function has no side effects: it does not change globals or arguments and calls only plain
  functions. A function that has side effects or is not deterministic is marked `!` (D-027).
- A method may have side effects and may return a result, or none: `method name(params) => (@result: T) is`.
  Returning a result does not make it something else.
- A method can be declared in a class (with `@self`) or at module level, outside any class (no `@self`).
  A module-level method is public with a leading `.` (`method .write(...)`) and private with a leading `_`
  (D-017). Visibility of an unmarked name: D-035.
- A method is called as a statement, `name(args);`, with or without `()` when it has no arguments. There is
  no `call`. `call` only runs a shell command (command.html). An asynchronous method is a method started with `start` (D-026).
- Applied to every tutorial page, the demos (`routine_call.eve` became `method_call.eve`), the keyword
  tables and the Notepad++ UDL files.

## Q-012 How does an enclosed function use method state? (answered 2026-09-30 → D-027)
D-026 makes a function inside a method a closure. Can the enclosed function only read the state of the
method, or also change it? A function has no side effects (D-025), so a counter like `generator` in
functions.html (`let current += 1`) would have to be a method, or the method changes `current` itself.
How is a closure created and returned: `new f := make_counter(0);` where `make_counter` is a method
that returns a function? This decides the rewrite of the closures section (FUN-06).
**Answer:** The enclosed function has side effects, so it is a `!` function and may change the state (D-027).

## D-027 Functions with side effects or randomness end with `!` (2026-09-30)
Answers Q-012. Refines D-017 (`name!()`), D-025 and D-026.
- A plain function is deterministic and has no side effects. A function that has side effects, or is not
  deterministic (stochastic, for example `random!()`), ends with `!`: `name!()`. A plain function can not
  call a `!` function or a method.
- A method has no `!`: a method is assumed to have side effects all the time. A function that calls a
  method is unsafe and must use `!`.
- A method creates a function and encloses it. The enclosed function shares the state of the method and may
  change it, so its name ends with `!`. It is a closure, and a closure that returns a new value on every
  call is a generator: `new index! := generator(0); print index!();`.
- Only methods (and functions enclosed in them) have state. A plain function has none and can not be suspended.
- Applied to the closures section of functions.html (the `generator` example is now a method).
- Open: the exact lambda syntax of an enclosed function (`let next! := Function() => …`).

## D-028 Functions: results, defaults, arguments, lambda (2026-09-30)
From the FUN-01 to FUN-10 answers. Refines D-027.
- A function must have a result; a subprogram without a result is a method (FUN-01). A function can return
  a list of results `=> (@r1:T1, @r2:T2)`; `$result` is then the list `(result1, result2)`. `@` makes the result
  a reference, so `let v := f(x);` is valid and `let 2 := f(x);` is not (FUN-02).
- In a parameter list `=` defines a default value, `:=` executes an expression (FUN-04).
- Positional arguments go first; mandatory parameters need no name; optional parameters must be named (FUN-05).
- A function is an object of type `Function`, restricted if it is pure (FUN-06).
- There is no `Lambda` type. A lambda is a notation that creates a function in one statement: parentheses are
  mandatory, a list of expressions gives several results, and the type follows the parentheses: `():Type`,
  `():(Type, Type)`. A signature type is `Type BinEx = (p1, p2 :Integer):Integer <: Function;` (FUN-07, FUN-08).
- A lambda can be assigned to a function identifier; if the identifier is not defined, it is only a pointer,
  passed to a parameter `@param`. The keyword `function` must be followed by an identifier (FUN-10).
- Functions do not handle errors: only a process does. Use preconditions; a runtime error propagates to the
  process (FUN-03).
- Applied to functions.html (notes, arguments, lambda section, FUN-F1 and FUN-F2 fixes).

## D-029 One parameter list; parameters after a vararg are named (2026-09-30)
Replaces the `option` keyword of D-019; answers SYN-22 again.
- A method or function has one parameter list, never two: `f()()` does not exist and `option` is removed.
- Optional parameters may follow the vararg parameter. In a call they must be named with the pair
  operator: for `f(*x, y = ",")` the call is `f(x1, x2, x3, y: b)`. Without the name, `y` would be taken as
  one more element of `x`.
- `print` is `method print(*args, separator = ",")`: `print (1, 2, 3, separator: " ");` prints `1 2 3`.
- Not related: the step of a range, `(min..max)(step)`, is a value postfix of a range (D-022), not a
  second parameter list.
- Applied to syntax.html (print section) and the SYN-22 issue.

## D-030 Control page answers (2026-09-30)
From CTL-01 to CTL-16. Refines D-016 and D-020.
- **Job (CTL-01, 03, 16).** The label is optional. A job without a label starts with `job` and ends with a
  naked `done;`; its implicit name is `job<line>` (for example `job24`). A labeled job is
  `name: job` … `done job [name];` and `job` is required after `done`. Status values: `"none"` (never
  executed), `"pass"`, `"fail"`. The state is kept in the process map `jobs["name"].status`, `.error`,
  `.line`; `$error.job` is the failed job's name (a string). Nothing is reported automatically: the
  process reads the map in its `finalize` region (`finalize` was kept instead of `resolve`).
- **Interruptions (CTL-02, 15).** `stop` ends a job and nothing else; `break` ends a loop (an outer loop
  with a label); `exit` ends the process. `stop` inside a loop inside a job ends the job.
- **Match (CTL-07).** The optional `[Type]` is removed. `any` is removed: `when other do` runs only when
  no `when` matched; `then` runs after the match for any path. A `when` can test a range:
  `when (1..5) do`.
- **Loop scope (CTL-06, 08, 11, 12).** `if` and ladder open no scope. The `loop` header is optional; it
  holds the declarations, which live in the loop scope, survive all iterations and are visible in
  `then`. Without a header the `cycle` has no private scope (the parent scope is used). `cycle` starts
  the executable region; a `new` variable in it is created on the stack at every iteration. `for`
  creates an implicit scope for its control variable only if the loop has no header; the control
  variable is visible in `then`, not after `repeat`.
- **Repeat (CTL-05, 13).** `repeat [label] [while condition];` starts another iteration only while the
  condition is true. `repeat if` does not exist (fixed in control, algorithms, concurrency). `while` and
  `for` loops take no condition after `repeat`.
- **While else (CTL-10).** `else` runs only if the condition is false the first time. `then` runs every
  time the loop ends, also after `break`.
- **Removed earlier (CTL-04, 09, 14).** `then`/`loop` optional answer superseded by D-016; `next` starts
  the next iteration; `check` and `clean` are gone (D-020).
- Block summary table added to the page (CTL-I1). Images copied to `tutorial/img/` (CTL-F1).

Spec additions: `spec/syntax/statements.md` (blocks, repeat while, match ranges),
`spec/semantics/control.md` (job names and status map, loop scopes, then/else rules).

## D-032 Types page answers (2026-09-30)
From TYP-01 to TYP-22, TYP-I3. Applied to `tutorial/types.html`.
- Native types are `u8 u16 u32 u64`, `i8 i16 i32 i64`, `f32 f64` (no `i128`, no `f16`). Only core
  libraries use them; scripts use primitive types (TYP-01).
- Primitive sizes: `Byte` u8, `Short` i16, `Integer` i64, `Natural` u64, `Real` f64, `Float` f32,
  `Ordinal` named u16 values, `Symbol` one Unicode code point on 32 bits (max U+10FFFF), `Time`
  milliseconds of the day, `Duration` an object stored as i64 milliseconds (TYP-02).
- `Rational` is `3\4`: two Integers, evaluation postponed until needed, computed with a precision.
  `Complex` is reserved, not in 0.1. `Range` is composite, not a number (TYP-03).
- Literal types: decimal `Integer` (also non-negative); `0x…` and `0b…` `Natural`; `9.9` `Real`; `1/2` is a
  division, so `Real`; `3\4` `Rational`; `'a'` and `U+…` `Symbol`; `"a"` `String`; `''` the empty
  Symbol (NIL); `""` the empty String; `[1, 2, 3]` `Vector[Integer]`; `()` List, `{}` DataSet, `[]`
  Vector when empty. `Binary` and `Word` do not exist (TYP-04).
- Unicode literal: one form `U+` with 4 to 6 hex digits, up to `U+10FFFF`; `U-` is dropped (TYP-05).
- NIL is `''`, the empty ASCII symbol; Null is no value and is not a Symbol (TYP-06).
- Declaration order is `new a = 0 :Integer;` (space before `:` optional); `new x :Integer = 5;` is wrong
  (TYP-07). `new` declares and takes a type; `let` takes no type; `:=` executes an expression (TYP-08).
- A process has no name: it takes the name of its driver or aspect (TYP-09).
- `[x..y]` is slice notation, never a range or domain; a range type is `Type Small = (0..1)(0.1) <: Range;`
  (TYP-10, D-022). The zeros of a decimal range literal indicate its precision (TYP-11).
- A variant is created only with `new v :{Real | Integer};` (or a `class … <: Variant` type); `set`
  makes constants, which have one clear type; the variant takes a type when a value is assigned (TYP-12).
- `/` always returns `Real`; `new x = a / b :Integer;` converts the result (TYP-13). `parse` coerces to the
  type of the target: Integer loses the decimals, Real keeps them, no error (TYP-14).
- Template placeholders start with `#`: `#s` string, `#n` number, `#{a}` variable `a` (TYP-15).
- `is` can check a type (`x is Integer`) and also introduces a block; `type` is a function and a method
  (TYP-16, TYP-I3). `call` is for shell commands only (TYP-17, D-025).
- `True` and `False` are constants of type `Logic`, not `Byte` (TYP-18).
- Date (proposed, awaiting review): an object with `era` (BCE, CE), `year` (1 or more), `month`, `day`;
  built with `"…".parse(YMD)` or an object literal with a `:Date` hint (TYP-19).
- Time formats: `T12 = "hh:mm:ssxx, 999ms"`, `T24 = "hh:mm:ss, 999ms"`, xx is am or pm. Duration is an
  object with the fields `year, days, hours, min, sec, ms` (TYP-20).
- `as` formats a value one way; the reverse is `String.parse(format)` (TYP-21).
- "Operators are functions, dispatch on the left operand" is an implementation note, not a language rule
  (TYP-22).

Spec additions: `spec/semantics/types.md` and `types.json` (native and primitive types, Rational,
literal defaults, variants, coercion, division, `parse`); `spec/lexical/lexical.md` (numeric, `U+`,
Symbol, NIL, String, placeholder, date, time and Duration literals).

## D-033 Loops close with `done`; no `repeat`, no plain loop; `cycle` (2026-09-30)
Replaces the loop rows of D-016 and the `repeat` rules of D-030 (CTL-05, 08, 13). Author decision.
- Every block closes with `done`. A loop closes with `done loop [label];` (while and for).
- `repeat` is removed. The body opener `cycle` is replaced by `do`: `while c do`, `for x in r do`.
- `[label:] loop` is only the optional header of a `while` or `for` loop: label and declarations. There
  is no unconditional loop: an infinite loop is `while True do … done loop;`, left with `break`. The
  compiler accepts a constant `True` condition without a warning; its `else` never runs.
- `cycle [label] [if condition];` is a statement of a `while` loop: go to the next iteration (back to
  the condition). The compiler turns it into a jump. Using `cycle` outside a `while` loop is an error.
- `next [label] [if c];` is only for `for` loops (advance the index). `break` and `then` are unchanged.
- A do-while is `while True do … break if not c; … done loop;`.
- Applied to control (section "Unconditional Loop" removed, sidebar entry too), syntax and the other
  tutorial pages, `js/eve1.js`, `js/eve3.js` and the demos.

## D-034 Closers: `done label;` (2026-09-30)
Replaces the closers of D-016, D-020, D-030 (CTL-16) and D-033. Author decision.
- A job always has a label (the implicit name `job<line>` is removed) and closes with `done label;`.
- A block that has a label closes with `done label;`; a block without a label closes with `done;`.
  This holds for job, match, while and for loops (the label is the one of the block or of its `loop`
  header). `if` has no label and closes with `done;`.
- `done job`, `done match`, `done loop`, `done while` and `done if` do not exist. `if` cannot follow `done`.
- Labels of match, loops and parallel groups stay optional (confirmed for parallel); only job requires one.
- `parallel` follows the same rule, with an optional label: `[name:] parallel … fork … join [name];`. A labeled
  group closes with `join name;`, an unlabeled group with a naked `join;`.
- Applied to control, syntax, the other tutorial pages and the demos (41 closers converted).

## D-036 `let` declares, `:=` mutates, `new` calls a constructor (2026-10-01)
Author decision. Replaces the `new`/`let` rows of D-017 and D-032 (TYP-07, TYP-08) and the constructor form of CLS-03 to CLS-06.
- `let` declares a variable, like `var` in other languages: `let a := 0;`, `let a = 0 :Integer;`. It takes a type.
  `new` no longer declares variables. `set` is unchanged (constants, D-031).
- Mutation needs no keyword: `a := a + 1;`, `a += 2;`, `t['one'] := 1;`, `self.x += a;`. `let a := …;` on a name that
  already exists in the scope is an error (redeclaration).
- `new` calls a constructor and is an expression: `let p := new Point(1, 2);`. A bare class call `Point(1, 2)` is not a
  constructor call.
- A constructor and a destructor are declared inside the class body and have no name (the class is known). The
  constructor has two lists: `(@self)` first, then the parameters; there is no `=>` list:
  `constructor(@self)(x = 0, y = 0 :Real) is … return;`. `@self` has no type: it is always an object of the class.
  `new` passes the second list. The type list of a generic class belongs to the class header:
  `class Number(:T) <: Object is constructor(@self)(initialValue: T) …`, `new Number(:i32)(42)`.
  This changes CLS-03: constructors are no longer outside the class body.
- Inside a class body, an object method takes `@self` without a type. A type is needed only for an extension method,
  declared outside the class, possibly in another module: `method (@self: Error) .raise(...);`.
- `self` is declared by `@self`, so the constructor assigns it first: `self := new Object();`, or the superclass
  constructor, by its own name (`self := new Shape(name);`). `super` is not a keyword (CLS-06). `return` carries no
  value (CLS-05: `return @self;` was a mistake).
- A class header ends with `;` when it has no body, otherwise with `is` (CLS-01). `+=` adds attributes to the new type.
- Attributes: `let self.name := v;` creates a private object attribute (CLS-04); public members are declared with `.`.
- Applied to `demo/` (`let x …;` mutations became `x …;`, `new` declarations became `let`) and `class_point.eve`.
- Open: the form of a private hidden attribute created in a partial constructor, and whether `new` may name a class
  without a constructor (a prototype class has no instances).

Spec additions: `spec/syntax/declarations.md` (variable, class, constructor), `spec/syntax/statements.md` (`let`, `:=`, `new`).

## D-037 `end name;` closes a class and a module (2026-10-01)
Author decision. Refines D-036 and the closers of D-016.
- A module returns nothing, so it closes with `end module_name;`, not `return;`.
- A class is a declaration, not a subprogram: it closes with `end ClassName;` (a class without body ends with `;`
  on its header line). `return;` stays for the subprograms: method, function, routine, constructor, destructor.
- Closers now: `done [label];` control blocks (D-034), `join [name];` parallel groups, `return;` subprograms (and
  today driver and aspect), `end name;` class and module. Regions (`import`, `global`, `constant`, `initialize`,
  `recover`, `finalize`) have no closer: they end at the next region keyword. `type`, `def`, `set` are one line.
- Applied to demo, the tutorial examples (23 closers) and `class_point.eve`.
- Driver and aspect: `process main is … return;` then `end script_name;`. A script may declare other named
  processes; `main` is the entry point. `over` ends the process it is in (not the driver). Author answers.
- `start name(args);` runs a named process and waits. `apply aspect.main(args);` runs the main process of an aspect
  (serial; D-042 made the process explicit).
  `begin name(args);` inside `parallel … fork … join` starts a process or an aspect asynchronously. Running an
  aspect creates its `main` process, which can start sub-processes.
- Applied: every driver and aspect in demo, pattern, test and the tutorial (143 scripts) now has `process main is` and `end name;`.
- Open: `start` meant "start a method asynchronously" in syntax.html; that use is dropped (async methods need a
  keyword, probably `begin`). Does a started process share the driver globals, and how are its parameters and result
  passed back? Is `over N;` in a sub-process an exit code for the caller's `start`?

## D-038 `over;` has no code; process parameters and globals (2026-10-01)
Author decision. Answers the open questions of D-037. Replaces the `over N` rows of D-010.
- `over;` takes no value: it ends the process it is in with code 0. The forced abnormal exit with code 1 (`over 1;`)
  is now `panic;` (D-031). Exit codes: 0 `over;` or end of process, 1 `panic`, 2 failed `expect`
- A process can receive parameters, input and output. It returns no result: outputs are parameters marked `@`.
  `process name(n: Integer, @total: Integer) is … return;`.
- A process has access to the globals of its script: module globals if declared in a module, driver globals if declared in a driver, accesible with . operator if public.
- Applied: `over 0;` → `over;`, `over 1;` → `panic;` in demo, tests, test/readme.md and the tutorial.
- `start` pass a parameter list, outputs marked `@`: `start total(10, @sum);`,
  `begin total(10, @sum);` (the output is ready after the `join`).
- `panic` is global: it is an unhandled exception and ends the whole application, not only the process (D-031).

## D-039 Traits, abstract classes, partial methods (2026-10-01, proposed)
Proposed by the model after reviewing the partials section of classes.html. Awaiting author confirmation. Touches CLS-07 and CLS-08.
- Problem: "partial" meant trait, interface, abstract class and prototype constructor at once; a partial constructor
  carried state, so multiple inheritance had attribute conflicts; an unimplemented method returned `Null` at run time.
- Vocabulary: a **partial method** is a signature ending in `;`. An **abstract class** is a class with at least one partial method. A **trait** is `trait Name is … end Name;`.
- Trait: no attributes, properties, constructor or destructor (no state, no instances). It holds required methods (partial) and provided methods (with a body, which may call the required ones through `@self`). `@self` is untyped and means the adopting class. A trait can be generic (`trait Comparable(:T)`) and can be used as a type
  (`let p: Printable := c;`, `x is Printable`). `trait` is a keyword; it closes with `end` (D-037).
- Abstract class: has attributes and a constructor, cannot be created with `new`; only a subclass constructor calls
  it, by its name (`self := new Shape(name);`). The partial constructor is removed.
- Inheritance list `<: (A, B, …)`: at most one superclass that carries state (default `Object`), any number of traits
  (CLS-07). A method of the class wins over a trait method; two traits that provide the same method need an explicit
  implementation in the class, otherwise a compile error.
- A class with a constructor must implement every inherited partial method: a missing one is a compile error, never
  `Null` (CLS-08).
- The `for` loop uses the library trait `Iterable`.
- Applied to classes.html (partials section rewritten), syntax.html (keyword `trait`), collections.html.
- Open: adopting a trait for an existing type outside its declaration (an extension, in another module), for example
  `Integer` adopting `Printable`; and the exact list of library traits (`Iterable`, `Comparable`, `Printable`).
- Todo: library traits `Iterable`, `Comparable`, `Printable`: step S5.1a in `plan/phase-5-conformance.md`.

## D-040 Parameters belong to the main process; the process is indented (2026-10-01)
Author decision. Refines D-031 (indentation) and D-037/D-038 (process).
- A driver or aspect header has no parameter list: `driver name is`, `aspect name is`. The parameters move to the
  process: `process main(*args) is`. A module has no process and no parameters.
- Inside a driver or aspect the `process` is indented by 2 spaces, with its body, `recover`, `finalize` and `return;`;
  `end name;` is at column 0. The other regions (`import`, `alias`, `constant`, `global`) stay at column 0.
  A process in an example that has no driver or aspect (a fragment) stays at column 0.
- Applied to 133 scripts in demo, pattern, test and the tutorial; prose in topology, concurrency, databases.
- Open: a method declared before the process cannot read the process parameters (`demo/method_call.eve` still reads
  `args` inside `test`, which was already wrong).

## D-041 One scope: no import, alias, constant, global or variable regions (2026-10-01)
Author decision. Replaces the region rules of D-031 (TOP-02, TOP-03, TOP-05) and the layout of D-040.
- A driver, aspect or module has a single scope. The regions `import`, `alias`, `constant`, `global` and `globals`
  are removed. Their content is declared directly in the scope, in any order: `from … use …;` (import), `def` (alias),
  `set` (constant), `let` (variable), classes, functions, methods and processes.
- Everything between the header and `end name;` is indented by exactly 2 spaces. Only the header, `end name;` and
  the comments before the header start at column 0. A process keeps its own regions `recover` and `finalize`,
  aligned with `process`. A module keeps `initialize` and `finalize`, indented 2.
- A `process` fragment in an example with no driver or aspect is `process main is … return;` at column 0.
- Applied to demo, pattern, test and the tutorial (topology, syntax, compiler, functions, databases): 53 files.
  The "Script Regions" table of syntax.html lost four rows. `databases.html` imports with
  `from $evelib/db use (core as db, oracle as orcl);` (the old `import` block had no valid form).
- Fixed on the way: `demo/test_args.eve` (the method header lacked `is`; a stray `process` was inside it).
- Open: the keyword `type` region of the old patterns, the keyword `globals` in `pattern/declaration.eve` (old
  syntax, kept as is), and whether `from … use` may sit after a declaration (any order is assumed).

## D-044 Issue files and keyword table cleaned (2026-10-01)
Maintenance after D-036 to D-043.
- `issues/`: 116 resolved items (status closed, done or answered) and the answered CLS-01 to CLS-08 were removed. Their answers
  live in this file; the earlier text is in the git history. Open items that quoted the old syntax were rewritten
  (collections, concurrency, databases, processing, topology, classes). New open items: CLS-15 to CLS-17, CON-09, PRC-14.
  Cross-references to removed ids were replaced by decision numbers. `issues/README.md` has new totals.
- syntax.html keyword table: removed `import`, `global`, `constant`, `alias`, `begin`, `release`; added `def`, `end`,
  `destructor`. 115 words. The highlighter (eve1.js) follows.
- collections.html: element creation `h('c') := 3;` is a mutation, not a `let` declaration.

## D-045 `repeat` replaces `cycle`; `repeat N times` (2026-10-01)
Author decision. Replaces `cycle` of D-033 and reuses the word `repeat` that D-033 removed as a closer.
- `repeat [label] [N times] [if condition];` is a statement of every loop, `while` and `for`. It jumps to the
  beginning of the cycle: the loop condition (the range check in a `for`) is verified again and the body runs
  again. The control variable of a `for` is not incremented; `next` advances it.
- `cycle` is removed (keyword table 115 words). `repeat` outside a loop is an error.
- `N times` is an integer expression. It limits the consecutive repeats of the same cycle: after N repeats the
  statement is ignored and execution continues after it. The count restarts when a cycle ends without a repeat.
  Without `times` the number is not limited; a condition that stays true is a user error, like `while True`.
- Variables created by `let` in the `do` region are created again at each repetition; what must survive is
  declared in the `loop` header.
- Applied to control.html (patterns, notes, examples), syntax.html (keyword and meaning tables), `js/eve1.js`,
  `js/eve3.js`. The control summary table lost the columns "Opens scope" and "Condition after closer".
- Open: whether `N times` counts per cycle (as written) or per loop.

## D-048 `@` passes by reference, at the declaration and at the call (2026-10-01)
Author decision. Answers CON-02 and CON-10.
- `@` marks an input/output parameter and is required on its argument: `bar(1, 2, @output);`, by name
  `add(1, 2, op: @result);`, also for elements and slices: `@s[i]`, `@nxt[a..b]`. The argument is a reference to a
  variable, element or slice; `add(1, 2, result)` and `add(1, 2, @4)` are errors.
- An `@` parameter is in/out (the method sees the caller's value) and has no default value, so it is never optional.
- Without `@` an argument is passed by value, collections included: the method works on its own copy. This is the
  low-level idiom; `@` is the higher-level input/output abstraction. The VM may implement it as copy on write. Note
  the parallel with assignment: a parameter without `@` behaves like `::` (clone), one with `@` like `:=` (shared
  reference), see syntax.html "Assign Expression". `heat_bar` copies the next state with `cur :: nxt;` (D-049).
- In a parallel block this replaces the read-only sharing proposed in D-047: a task gets copies of its inputs and
  references only to the outputs it owns.
- Applied to concurrency.html (parameter list and text, examples `process_demo`, `output_params`, `shoulder_thread`,
  rules of parallel methods, `heat_bar` text), types.html and `demo/variant_params.eve` (`swap(@x, @y)`),
  `demo/output_params.eve` (call, missing comma, `set out :=`, `let result`, expected value 3).

## D-049 `::` is the only clone; no `clone` keyword; slices by `:=` are views (2026-10-01)
Author decision.
- The keyword `clone` is removed (keyword table 112 words). The clone operator `::` makes a deep copy of an object or
  a collection: `let copy :: original;`. `:=` shares the reference of an object or collection, and copies a native value.
- Slices follow the same rule (closes COL-08; `$` is the last index, D-021): `let v := base[a..b];` is a view over the elements of `base` (writing through it changes
  `base`); `let c :: base[a..b];` is a new collection with a copy of the elements.
- Matches the parameter rule of D-048: no `@` behaves like `::`, `@` like `:=`.
- Applied to syntax.html (keyword table, "Assign Expression"), collections.html ("Array slicing"), concurrency.html
  (`heat_bar` clones the next state with `cur :: nxt;`).

## D-054 Exceptions page, `$err_` and `$wrn_` constants (2026-10-02, proposed codes)
Author request. New tutorial page `exceptions.html` (topic 13, after the standard library; later topics renumbered).
- Predefined read-only constants: `$err_name` for each standard exception, `$wrn_name` for each warning; the value is
  the integer code, compared with `$error.code` in the `recover` region. Two tables, one for exceptions, one for
  warnings, with code, constant and message pattern. A new exception or warning must be added to its table first.
- The author wrote `@wrn_name`; read as `$wrn_name` (system constants use `$`). Confirm.
- Proposed (not decided): code ranges 1-9 statements (`panic` 1, `expect` 2, `assert` 3 as a warning), 10-127 system,
  128-255 project; the exit code of an unhandled error is its code. The list of standard codes and the message
  patterns are a first draft. `raise`, `warn` and the Exception module signatures stay open (PRC-08, PRC-09).

## D-058 Collections answers: ordinals, literals, sets, maps, strings (2026-10-02)
Author answers COL-01 to COL-20 (issues/collections.md). Closes COL-08 (D-022, D-049) and the list operations of COL-05.
- Ordinal: the first value is 0 (`{False, True}`: False = 0, True = 1). Capitalized names enter the enclosing scope (language rule).
- Literals: `(1,2,3)` is a list, never a tuple; `List(...)` is an optional constructor; `(x)` is a list of one element, not an
  expression (expressions use operators). `{}` is the empty DataSet, `{:}` the empty HashMap. Unquoted keys make an Object, quoted
  or numeric keys a HashMap (quoted = strings, unquoted = identifiers).
- Builders: generators combine with `and`; ranges with open ends such as `(2>..n)` are preferred to filters.
- Deconstruct: `_` is always Null; it can be written but the value is forgotten. `*` alone skips many elements and stays Null; `*rest` collects.
- Array types: Array (1 dimension), Matrix (2), Tensor (3 or more; a 3D tensor is an array of matrices). Slices are `[n..m]` only.
  `[*]` selects a whole dimension and is needed only for a matrix or tensor (`m[1..2][*]`, `m[*][1..2]`, never `[*][*]`); a slice
  takes one value with `:=`. A matrix or tensor also takes one absolute row-major index (`mat[124]`: row and column are computed).
- DataSet: sorted by value, `print` shows the order; a List is not sorted unless sorted explicitly. Operators `&=` and `|=` are removed
  (`||` union, `&&` intersection, `+=` / `-=` add and remove elements).
- HashMap: a sorted map (by key); the name stays HashMap, `Map` is too short. Assigning to a missing key creates it; `+=` on a missing
  key raises an error. Elements are created with brackets: `h['c'] := 3`.
- String is immutable; Text is a different, mutable type (a rope or similar). A mutable string is a collection of symbols or a Text.
  Concatenating a string with another literal gives a String (`"a" + 1`, `'a' + 1`). Class methods can be called with the class name or
  with an object: same method.
- Regular expressions: the match operator is `=~`, not-match `!~`; a string starting with `/` on the right is a regex.
- Applied: collections.html split in two: strings, text and regular expressions moved to the new strings.html (+ data/strings.json,
  index.html row 09, pages renumbered); new img/row-major.svg; example and typo fixes (COL-F1 to F4).
- Open: map type notation (`{}(String,Object)` or `{}(Type:Type)`), `&code;` escapes and Fortran-like formats (COL-15, COL-16),
  how an Object gets new attributes (replaced `&=` by `object.x := 1`), and the exact meaning of `-=` with a position
  (`lst -= lst[1]`). Spec work pending.

## D-059 Collections follow-ups; one interpolation form (2026-10-02)
Author answers COL-02, 03, 05, 14, 15; COL-16 "apply the proposal". Applied to the tutorial and `demo/`.
- Map type notation: `{:}(Type,Type)`, for example `{:}(String, Object)` (classes.html, collections.html).
- Builder: the first generator is a range or a collection; an optional condition follows, joined with `and`:
  `(x | x in (1..10) and x % 2 == 0)`. No `if` filter.
- `-=` removes by value (all equal elements): `lst -= lst[1]` removes every element equal to the first. Removing the first or the
  last element is done with `->` and `<-`. Capturing the removed element in the same statement is open (idea: `lst -> let e;`,
  and a `let` inside statements such as `while let x in (range)`).
- Objects: `object.x := 1` adds an attribute; an empty Object is the Null `let o :Object;`.
- Escapes: both `&code;` and `\u{H…}` are valid in strings (D-019 had dropped `&code;`; reinstated).
- Interpolation: `"#{expr}"` is the only form. `#s`, `#n`, `#`, `{a}`, `#(x)` and the template operator `?` are removed. Format after a
  colon, adapted from Fortran: `iW` integer, `fW.D` real, `sW` string, repeat count prefix for collections (`#{m:3i4}`: 3 per row).
  Literal `#{` is written `\#{`. Proposed by the model, to be refined in the specification.
- Applied: classes, collections, strings, types, command, syntax pages; demo/class_point, method_call, number_to_string,
  print_type, string_concat.

## D-060 Interpolation escapes `\s{}` `\#{}` `\b{}`; queue direction (2026-10-02)
Author answers COL-05, COL-16. Replaces the interpolation bullet of D-059 (`#{expr}` is gone) and extends D-019.
- Escapes with braces, one family: `\u{H…}` code point (D-019), `\s{expr}` any value as a string, `\#{expr}` a number, `\b{expr}`
  a boolean (True/False). The old `#{…}`, `#s`, `#n`, `{a}` and `?` do not exist. Literal braces stay `\{` and `\}`.
- Format after a colon, Fortran codes for numbers, Python-like alignment (proposed by the model, to be refined in the spec):
  `\s{e:[[fill]align][width][.max]}`, `\#{e:[[fill]align][flags][repeat]code[width][.digits]}`, `\b{e:[[fill]align][width][code]}`.
  align `<` `>` `^` (default left for string and boolean, right for number); fill is one character before the align;
  number codes `i f e x b`; flags `+` and `,` (thousands); repeat count puts N elements per row (`3i4`); boolean codes `tf` `yn` `01`.
  The width never truncates (Fortran `*****` overflow is not used); only `.max` cuts a string.
- Lists: the arrow points to the side the element leaves from. `<- lst` removes the first element, `lst ->` the last;
  `x <- lst` / `lst -> x` remove the first / last element equal to `x`. A queue enqueues at the end (`q <+ x`) and dequeues the first
  (`let e <- q`). A stack pushes at the end (`s <+ x`) and pops the last (`s -> let e`). The capture forms `let e <- lst;` and
  `lst -> let e;` are a proposal (a `let` inside a statement, also `while let x in (range)`): open.
- Applied: strings, collections, classes, types, command, syntax pages and the demos that used interpolation.

## Q-002 evidence (2026-10-02, script temp/kw_usage.py)
The table of syntax.html has 111 words (the text says 113 in D-046). Found in the examples (demo, pattern, test, code blocks of
the tutorial): `external` (D-056) is used and is **not** in the table. 30 words of the table are never used: `alter analyze append
ascend augment close cursor delete descend discard exit fetch group halt into item limit offset open order package pop rollback
select store switch trial view where xor`. Most belong to databases or to ideas that were dropped. Words that are probably
library methods now, not keywords: `print`, `read`, `write`, `raise`, `expect`, `add`, `del`, `pop` (D-053, D-055, D-060).
Question: which of these are reserved in 0.1 (listed as `reserved`, unused), which are removed, and which are methods?
Blocks: S2.4 (`keywords.json`).

## Q-013 Numbers: scientific notation and digit separators (2026-10-02)
The tutorial links "scientific notation" but defines no literal. Proposal: `1.5e3` and `2e-3` are Real literals (`e` or `E`, an
optional sign, digits; a literal with an exponent is always Real); `_` may separate digits (`1_000_000`, `0xFF_FF`), never at the
start, the end or next to `.`. Accept, change or reject?
Blocks: `lexical/lexical.md` (Integer, Real).

## Q-014 Strings: `&name;`, text literal (2026-10-02)
(a) Which forms of `&…;` are valid: only HTML names (`&alpha;`), or also `&#955;` and `&#x3BB;`? How do you write a literal
`&alpha;`: `\&alpha;`, or `&amp;alpha;`? (b) Is `"""…"""` of type `String` or `Text` (COL-15: Text is mutable)? (c) Proposal for the
line breaks of `"""`: the break after the opening quotes and the break before the closing quotes are not part of the text.
Blocks: `lexical/lexical.md` (String, Text literal).

## Q-015 Interpolation: end of the expression (2026-10-02)
In `\#{expr:format}` the colon is also the pair operator. Proposal: the expression ends at the first `:` or `}` outside brackets
and nested literals; a pair is written in parentheses. Accept?
Blocks: `lexical/lexical.md` (Interpolation).

## Q-016 Small lexical rules (2026-10-02)
Proposals, each yes or no: (a) a UTF-8 BOM at the start of a file is ignored; (b) `name!~x` reads as the suffix `!` then `~`, so the
operator `!~` needs a space before it; (c) a trailing comma in a list or collection literal is an error; (d) a `#` that is not in
column 1 is a lexical error (it was also "last index" and "digit in a pattern" in the old table, both removed); (e) identifiers are
ASCII only.
Blocks: `lexical/lexical.md`.

## Q-017 Operators `+>` and `<+`: which side is the list (2026-10-02)
D-060 gives `q <+ x` (append at the end), `s -> let e;` and `let e <- q;`. For the insert at the start, the old examples write
`queue +> "x"` (list on the left) while the arrow suggests the element goes to the start of the list on the right. Proposal:
`x +> lst` inserts `x` at the start of `lst`; `lst <+ x` appends at the end; `a <+ b` concatenates (b after a). Confirm the side of the list for `+>`.
Blocks: `operators.json` (`prepend`), `syntax/expressions.md`.

## D-061 Licenses: BUSL-1.1 for code, CC BY 4.0 for the specification (2026-10-02)
Author decision. Answers Q-006 and the open part of MAN-01; replaces the Apache 2.0 license of the repository and the CC BY-ND 4.0
of manifest.html.
- Code (`evevm/`, `script/`): Business Source License 1.1, text and parameters in `evevm/LICENSE`. Licensor Elucian Moise;
  Change License Apache 2.0; Change Date 2030-10-02. The Additional Use Grant (proposed by the model, to confirm) allows production
  use except offering the VM or a derivative as a competing commercial VM, interpreter or hosted service for Eve.
- Specification (`spec/`): CC BY 4.0, full legal code in `spec/LICENSE`. Adaptation is allowed, so the NoDerivatives bullets and
  the "implementation grant is needed because of ND" reasoning are gone; the grant and the trademark policy stay.
- Manual, demo, pattern, test, plan, issues, tools: CC BY 4.0 (assumed by the model, to confirm). Root `LICENSE` is a summary.
- Applied: LICENSE, README.md (section License), spec/index.md, evevm/README.md, tutorial manifest.html (License section, legal notice).
- Note: the scl repo, which holds the tutorial pages, has a GPL-3.0 `LICENSE`. Which license covers the tutorial text is open.

## D-062 Trademark policy (2026-10-02)
Author request. `TRADEMARK.md` at the repository root: "EVE", the logo and the branding are trademarks of Sage-Code Laboratory.
Free: implementing the language, "Built for EVE", "EVE compatible", "Runs EVE scripts", "Based on the EVE language specification",
accurate references, unmodified official software. "EVE Compiler / Interpreter / VM" and "EVE Compliant" need a stated spec version,
a passed conformance level and an unmodified-fork condition. Not allowed without written permission: a modified compiler, VM or
distribution under the EVE name, an incompatible dialect presented as EVE, a modified specification under the EVE title, registering the
mark, altering the logo. Applied: TRADEMARK.md, README.md, LICENSE, tutorial manifest.html. Open: confirm the legal entity name.

## Q-018 Regular expressions and the backslash (2026-10-02)
D-019 says any `\` sequence that is not an escape is a lexical error, and D-060 makes `\s{` an interpolation. A pattern such as
`"/\sis\s/"` (regex.html of the old tutorial, `\d`, `\w`) would then be an error. Options: (a) a pattern writes the backslash twice
(`"/\sis\s/"`); (b) a string that starts with `/` is a regex literal and keeps its backslashes (no escapes, no interpolation);
(c) a separate raw form. Recommended: (b), with `\"` still allowed for the quote. The tests a28 use patterns without a backslash until this is decided.
Blocks: `lexical/lexical.md` (Regular expression), `test/level1/a28_regex.eve`.

## Q-019 Assumptions of the level 1 tests a04 to a37 (2026-10-02)
Each one is a place where the tests state a rule that no decision gives yet; change the test or the spec when you answer:
(a) `1 / 0` raises an error (the demo `recover_demo.eve` assumes it; IEEE would give infinity) (a37);
(b) printing a DataSet is `{1,2,3}` without spaces, a list `(1,2,3)`, `print (1, 2, 3)` prints `1,2,3` (a05, a20);
(c) the formats of `\#{}`, `\s{}`, `\b{}` of D-060 (a11);
(d) `a <+ b` as an expression returns a new list and `x <- lst` removes the first element equal to `x` (a17);
(e) `m[5]` is the absolute row-major index of a matrix (D-058) and `g[1, *] := 5` assigns a row (a19; the test said `g[1][*]`,
    which D-058 gives another meaning: changed in D-063);
(f) `let v := [...]; let view := v[1..2];` is a view (D-049) (a18);
(g) a text literal drops the line break after the opening quotes and before the closing ones (a27, Q-014);
(h) `for (k: v) in map` visits the keys in order (a21); `p.z := 7` adds an attribute to an Object (a22);
(i) a function parameter after a defaulted one is named at the call: `greet("Eve", greeting: "Hi")` (a24).

## D-063 First execution of level 1: what running the tests taught (2026-10-02)
Model decisions taken while writing the interpreter (`evevm/src/interp.zig`); all of `test/level1/` (37 tests) passes. Each one is
a rule the tests needed and no decision gave; change the test or the rule when you answer.
- Author answer: `(x)` is grouping, not a list; `(x,)` is the list of one element (corrects D-058, which said `(x)` is a list).
  The tests use `(2 + 3) * 4` and `("yes" if c else "no")`; a17 checks `(5,)`.
- A symbol literal holds exactly one code point: `'one'` and `'zz'` are syntax errors ("use "..." for text"). a21 and a36 wrote
  strings in single quotes; they now use double quotes.
- Matrix indexes: `g[1]` is the absolute row-major index (D-058), so a row is `g[1, *]` and a column `g[*, 1]`. a19 said `g[1][*]`.
- `is` between two types compares them: `type(9 / 3) is Real`; `x is Null` and `a is b` test identity for references.
- Errors are `{code, message, job}` (D-055): `raise` gives 4, a failed `expect` 2, an error of the VM (index 0, missing key, division
  by zero, undefined name, bad operand) 4. `recover` can catch all of them; `$error.message`, `$error.code` and `$error.job`
  are available there. An unhandled error runs `finalize` and ends the process with its code; the message goes to stderr.
- In `recover`: `retry` runs the failed top-level statement of the process again (the job), `resume` goes on after it, reaching the
  end of `recover` ends the process (handled, `finalize` runs), `abort` ends it with the code of the error and skips `finalize`.
- `panic;` ends at once with code 1 (no `finalize`); `over;` ends with 0 (no `recover`, no `finalize`).
- Real numbers print in the shortest form that reads back (`3.5`, `0.25`; a whole Real prints without a point). Collections print
  `(1,2,3)` list, `[1,2,3]` array, `{1,2,3}` DataSet, `{'a':1}` map, `{x:1}` object, strings and symbols quoted inside a collection.
- `write (a, b)` writes the values with no separator; `print (a, b)` joins them with `,` (named argument `separator:`).
- Formats of the interpolation (D-060): `[fill][<|>|^][,][i|f]width[.precision]`; strings take a width, an alignment and a
  precision (a cut); a Logic takes `yn` (Yes/No), `01` or `tf`.
- `new C(args)` without a constructor fills the members in order or by name; with a constructor it runs it, and the object returned
  is `self` (its class is set to `C`). `new Object()` is an empty Object.
- Regular expressions: a small subset (literals, `.`, `^`, `$`, `[a-z]`, `\d \w \s`, `* + ?`, `|`), no groups, no back references.
- Command files (`.vmc`): see `manual/usage.md`. Comments are `#` at the start of a line and `**` to the end of a line; a line counts
  when it ends with a newline; while a script runs only `report` and `stop` are taken from the slot.
- Workflow: `eve -x -i file.vmc` without a script is serve mode; commands `load`, `parse`, `run`, `errors`, `ast`, `inspect`, `status`,
  `outdir`, `capture`, `log`, `clear`; `script/workflow.py` drives a whole level through one session and reads the reports.

## D-064 Matrix and tensor indexes: `[x, y]` is `[x][y]` (2026-10-03)
Author request. Corrects the matrix line of D-063 (`g[1][*]` is again a row).
- A matrix or a tensor takes its indexes in one pair of brackets separated by commas or in one pair of brackets per dimension:
  `m[x, y]` is `m[x][y]`, `t[x, y, z]` is `t[x][y][z]`; the forms mix (`t[x, y][z]`). Reading and writing are the same.
- Each index may be a number, `$`, a range or `*`, so a chain selects a part: `m[1..5][3]` is column 3 of rows 1 to 5 (5 elements),
  `m[3][1..5]` is row 3, columns 1 to 5. The result is an array; a part takes one value with `:=` (D-058).
- One pair of brackets with one index keeps D-058: `m[k]` is the absolute row-major index. Only a chain after it is a second dimension.
- On a value that is not a matrix (a map, a list, a 1-dimension array) each pair of brackets indexes the result of the previous one:
  `h["k"][2]`, `v[2..5][1]` (an element of the slice).
- Applied: spec/lexical/lexical.md, spec/lexical/delimiters.json, tutorial collections.html (Matrix indexes), evevm/src/interp.zig
  (`indexChain`), test a38_matrix_index.

## D-065 `demo/` is temporary (2026-10-03)
Author decision. `demo/` disappears when the test suite is complete: each demo either becomes a test in `test/levelN/` or is
dropped. No new demos are written; new examples go to `test/` as tests.
- 2026-10-03 review: all 45 demos were rewritten to the decisions up to D-064 (title line, `let` for changed globals, `:=` without a
  type, strings in `"…"`, `$`, `..<` and `>..`, `||` and `&&`, `{"k": v}` and `{:}`, `"""`, `.parse(F)`, `done;`, no redeclaration).
  29 run on the VM. 16 need VM work first: `as`, open ranges `(0..?)`, type notations `()T` `{:}(K,V)` `{A | B}`, Rational `3\4`,
  `wait 10ms`, process parameters, method varargs, `eq`, loop labels, symbol ranges, and the library (`floor`, `ceiling`, `round`,
  `format`, `parse`, `split()`, `$epsilon`, Time and Date).
- Not in the spec, removed from the demos: `all`/`any` before a collection, the string pipeline `"" <+ (…)`, chained comparisons
  `a <= x <= b`, `is` between two Integers, scientific notation (Q-013), `is Text` of a `"""` literal (Q-014).
- Open: D-028 says optional parameters are named at the call, D-048 calls `add(1, 2, @result)` with optional `p1, p2` by position.
  The tutorial copies of about 30 demos have the same errors as the demos had; they are not fixed yet.
