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
- `option` was a keyword: a method could declare a second parameter set, passed by name after
  `option`: `method name(*args) option (params)`. Removed by D-029.
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

### D-021 `$` is the last index; indexing is 1-based (2026-09-30)
From COL-06. Idea from bee-lang (D1). Eve indexes lists, arrays, matrices and strings from 1.
- In an index, a bare `$` is the index of the last element: `a[$]`, `a[$ - 1]`, `mat[3, $]`.
  `#` is not an index symbol: it would clash with `#{…}` interpolation (`"#{a[#]}"`).
- `$` followed by an identifier character is still a system variable (`$error`, D-017); a bare `$`
  inside `[ ]` is the end anchor. `$` is only valid as an index or inside a range that is an index.
- Index 0 and negative indexes are errors (`a[0]`, `a[-1]`); use `a[$ - 2]` for relative access.

### D-022 Ranges: exclusive ends, postfix step, slices use `..` (2026-09-30)
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

### D-023 Arrays from ranges use the builder only (2026-09-30)
From a discussion of `[1..10](2)`. The builder `[x | x in (1..10)(2)]` is the only way to fill an
array from a range. The shorthands `[1..10]` and `[1..10](2)` are not Eve: a bracket after a value
is indexing or slicing (`a[1..10](2)` stays free for stepped slices), and brackets never define a
range (D-022). The array type stays `[]Integer` / `[10]Integer`: `new a := [x | x in (1..10)(2)]: []Integer;`.

### D-024 Cartesian product is `><` (2026-09-30)
From the matrix builder example. `a >< b` is the cartesian product of two collections or ranges: a
sequence of pairs in row-major order (the left operand is the outer loop), for example
`(x, y) in (1..4) >< (1..4)`. It is one token (longest match), not `>` then `<`. It is easy to confuse
with `<>` (not equal), so the compiler reports a hint when `><` has operands that are not
collections or ranges (`did you mean <>?`), and when `<>` has two collections or ranges. A builder can
also use several generators (`x in A and y in B`), which gives the same product without `><`.

### D-025 No routines: a method is any subprogram with side effects (2026-09-30)
Answers FUN-03, FUN-09, FUN-I1, TYP-17, CON-01, CMD-01. Amends D-015 and D-016.
- There are two subprogram keywords: `function` and `method`. `routine` (and procedure) is removed.
- A plain function has no side effects: it does not change globals or arguments and calls only plain
  functions. A function that has side effects or is not deterministic is marked `!` (D-027).
- A method may have side effects and may return a result, or none: `method name(params) => (@result: T) is`.
  Returning a result does not make it something else.
- A method can be declared in a class (with `@self`) or at module level, outside any class (no `@self`).
  A module-level method is public with a leading `.` (`method .write(...)`) and private with a leading `_`
  (D-017). Visibility of an unmarked name: Q-011.
- A method is called as a statement, `name(args);`, with or without `()` when it has no arguments. There is
  no `call`. `call` only runs a shell command (command.html). An asynchronous method is a method started with `start` (D-026).
- Applied to every tutorial page, the demos (`routine_call.eve` became `method_call.eve`), the keyword
  tables and the Notepad++ UDL files.

### Q-011 Default visibility of a module-level method (2026-09-30)
D-025 says `.` is public and `_` is private. What is a method with no prefix: private to the module, or
public? The same question applies to functions and classes at module level.
**Answer:** _(open)_

### D-026 No coroutines: generators, threads, suspended methods (2026-09-30)
Follows D-025. The word "coroutine" is not used, because it came with "routine".
- A method started with `start` is an **asynchronous method**: it runs in a secondary thread and can be
  suspended with `suspend` and continued with `resume`. A suspended method waits for a signal.
- A method that produces its values one batch at a time is a **generator**.
- A function can not be suspended and has no state. Only a method has state and can be suspended.
- A function declared inside a method is enclosed by it and can use the state of that method. This is the
  closure system of Eve: the method holds the state, the enclosed function is the closure.
- Applied to concurrency, syntax and topology pages and the concurrency and topology issues. The closures
  section of functions.html still describes the old rule (closures created by a function): Q-012.

### Q-012 How does an enclosed function use method state? (answered 2026-09-30 → D-027)
D-026 makes a function inside a method a closure. Can the enclosed function only read the state of the
method, or also change it? A function has no side effects (D-025), so a counter like `generator` in
functions.html (`let current += 1`) would have to be a method, or the method changes `current` itself.
How is a closure created and returned: `new f := make_counter(0);` where `make_counter` is a method
that returns a function? This decides the rewrite of the closures section (FUN-06).
**Answer:** The enclosed function has side effects, so it is a `!` function and may change the state (D-027).

### D-027 Functions with side effects or randomness end with `!` (2026-09-30)
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

### D-028 Functions: results, defaults, arguments, lambda (2026-09-30)
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

### D-029 One parameter list; parameters after a vararg are named (2026-09-30)
Replaces the `option` keyword of D-019; answers SYN-22 again.
- A method or function has one parameter list, never two: `f()()` does not exist and `option` is removed.
- Optional parameters may follow the vararg parameter. In a call they must be named with the pair
  operator: for `f(*x, y = ",")` the call is `f(x1, x2, x3, y: b)`. Without the name, `y` would be taken as
  one more element of `x`.
- `print` is `method print(*args, separator = ",")`: `print (1, 2, 3, separator: " ");` prints `1 2 3`.
- Not related: the step of a range, `(min..max)(step)`, is a value postfix of a range (D-022), not a
  second parameter list.
- Applied to syntax.html (print section) and the SYN-22 issue.

### D-030 Control page answers (2026-09-30)
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

### D-031 Topology page answers (2026-09-30)
From TOP-01 to TOP-16. Applied to topology.html, with one canonical skeleton each for driver, aspect and module (TOP-I1).
- Indentation is mandatory: 2 spaces, an error otherwise (TOP-01). Region keywords start at column 0.
- Regions are decided per kind of script (TOP-02). A class is not a region: `class Name = {…} <: Type;` on one line;
  the `class` region with `NewType = {} <: Type;` is not allowed (TOP-06). Process end regions: `recover`, `finalize`
  (`release` is gone); a module ends with `finalize`.
- `set` creates constants of the global scope. It is allowed directly after `#!` or after the header (TOP-03), and in any
  declaration region. The `constant` region is a visual delimiter for constants only; global variables use `new` in the
  `global` region (interpretation of TOP-05). Declarations may sit directly under the header at 2 spaces; they belong to
  the global scope bound to the process scope (TOP-05). Constant names are not enforced (TOP-05).
- `def Alias = library.Member;` creates an alias; `def` is a new keyword. An alias of a parameterized class is not
  supported (TOP-04).
- `:=` executes an expression and is allowed in global regions; the "no inference in global" restriction is removed (TOP-07).
- OS environment variables are visible as `$NAME` (TOP-08).
- `over` ends with 0; `panic` ends with 1 (no `panic N`, no `panic 0`); a failed `expect` ends with 2; `raise` ends with a code
  greater than 0 (TOP-09).
- An aspect has a mandatory process. A library and a module have none; a module can be imported, not applied (TOP-10).
- A library is a folder of modules; a module is one script file with header `module name is`, named like the file. The term
  "crate" is dropped (TOP-11).
- A path is a string; `/` is a "smart concatenation" that becomes `\` on Windows (TOP-12).
- `.cfg` files hold `$key = value` with Eve literals and `#` comments (TOP-13).
- VM parameters, REPL, service and exclusive modes are planned (about 0.9), not in 0.1 (TOP-14). Script operations: `parse`,
  `debug` (debug mode) and `execute` (production mode); `load` is removed (TOP-15).
- Only a driver defines globals. Aspects and modules define public (prefix `.`) and private members, reached as
  `alias.member`, so equal names in two modules do not conflict (TOP-16).
- Open: the 0.1 list and types of built-in system variables (TOP-08); whether an aspect returns a result or an error code to
  the driver (TOP-10).

Spec additions:
- `spec/semantics/topology.md`: projects, libraries, modules, imports and paths (TOP-10 to TOP-12), exit codes (TOP-09),
  VM operations (TOP-15).
- `spec/syntax/regions.md`: regions and order per script kind, indentation rule, `def`, `set`/`new`, `:=` in global regions
  (TOP-01 to TOP-07).
- `spec/semantics/scopes.md`: system variables (TOP-08), public and private members (TOP-16).
- `manual/usage.md`: VM modes and options, planned (TOP-14).

### D-032 Types page answers (2026-09-30)
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
