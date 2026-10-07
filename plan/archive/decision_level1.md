# Archive of decision_level1.md: settled entries, full text

## D-001 Specification formats (2026-09-28)
The specification is written in Markdown for prose and JSON for machine-readable tables, with the grammar as EBNF in fenced `ebnf` blocks. No HTML in `spec/`. See `spec/README.md`.

## D-004 `docs/` becomes `manual/`, the compiler manual (2026-09-28)
Answers Q-001. `docs/` is renamed `manual/`: the manual of an Eve implementation, covering how to implement it, how to use it, what was implemented, and which features it supports. The feature tables are generated from the spec (JSON items and `ebnf` rules) joined with a support file per implementation, never edited by hand. The empty stubs and `doc.sh` are removed. See `manual/README.md` and `plan/phase-7-manual.md`.

## D-005 The manual documents the first Eve compiler, not yet built (2026-09-28)
Answers Q-007. No Eve implementation exists; the first compiler is being built now, together with the spec. `manual/` is written alongside it: `implement.md` and the feature tables come first, `usage.md` and `implemented.md` fill in as the compiler runs and ships versions. Until then every feature counts as `no`.

## D-006 First implementation: an Eve VM written in Zig (2026-09-28)
Answers Q-008 in part. The first Eve implementation is a virtual machine written in Zig that runs Eve source as a scripting language. There is no ahead-of-time compiler yet. `manual/` documents this VM; the feature tables have one column for it. A compiler can come later as a second implementation with its own support file.

## D-007 `evevm/` source, `bin/eve.exe` official implementation (2026-09-28)
Answers Q-009. The Zig source of the Eve virtual machine lives in `evevm/` in this repo. The build produces `bin/eve.exe` (`bin/eve` on Unix), the official Eve implementation. Its implementation id in the manual is `eve` (support file `manual/support/eve.json`). `bin/` holds build output only; `*.exe` is already git-ignored.

## D-008 Shebang line (2026-09-28)
Eve files run as scripts, so a file may start with a shebang line, for example
`#!/usr/bin/env eve`. It is a comment: `#` already starts a line comment, and the VM ignores the line. The spec states it in `lexical/lexical.md` (S2.3): only the first line of a file is an interpreter directive; `#!` on a later line is an ordinary `#` comment.

## D-002 Tutorial stays in the scl repo (2026-09-28)
The tutorial remains HTML, published from `scl/projects/eve`, and is edited here through the `tutorial/` junction. It is git-ignored in eve-lang.

## D-003 Many compilers, one specification (2026-09-28)
Eve has no single reference implementation. Any compiler is valid if it implements a stated spec version and passes the conformance level it claims. Students are expected to build their own.

## Q-001 Fate of `docs/` (answered 2026-09-28 → D-004)
`docs/` holds an older Markdown documentation skeleton: `index.md` plus 20 empty stub pages (core, db, net, os, std) created by `doc.sh`. Options:
(a) delete `docs/` and `doc.sh`, since `spec/` replaces them;
(b) keep `docs/` for user-level guides (database, network, OS) and link to `spec/`.
Recommended: (a) for the empty stubs, and move any real content into `spec/`.
Blocks: T1.2 cleanup of eve-lang, S2.1.
Answer: neither; rename to `manual/` as the compiler manual (D-004).
**todo** Remove old doc folder, we have replace it with /manual folder
**Done 2026-10-06 (D-096):** `docs/` no longer exists; the empty `doc/` folder was removed.

## Q-002 Canonical keyword list (answered 2026-10-06 → D-094)
The tutorial table (`syntax.html#keywords`) has duplicates (`constant`, `method`, `reset`, `add`, `del`, `pop`) and a typo (`labe`). It lacks words the examples use at region level (`driver`, `module`, `type`, `globals`). Which words are reserved in 0.1, and which are contextual (reserved only in some regions)?
Blocks: S2.4.
**todo** Remove unused keywords, replace or add the missing keywords. With description! 

## Q-003 Stray files in the tutorial folder (answered 2026-10-06 → D-094)
`tutorial/quiz.txt` (AI chat transcript), `tutorial/output.log` (UTF-16 PowerShell error log) and `tutorial/databases.md` (AI review prompts) are not tutorial pages. Delete them, or move useful parts (quiz questions) into a proper page?
Blocks: T1.2.
**todo** cleanup is required, move useful content in current back-log, plan or issues.

## Q-004 `global` or `globals` (answered 2026-10-06 → D-094)
`pattern/declaration.eve` uses both `globals` and `global`. Are they two region keywords with different meanings, or one keyword with a legacy spelling?
Blocks: S3.2.
**todo**
regions are legacy design. globals and global keywords are not reserved and must be retired.

## Q-005 Expected-output convention for tests (answered 2026-10-06 → D-094)
How does a test state its expected result? Options: (a) `expect` statements inside the script (already used in `demo/shared_state.eve`); (b) a sibling `.out` file with the exact stdout;
(c) both: `expect` for logic, `.out` for print formatting.
Recommended: (c).
Blocks: S5.2.
Status 2026-09-28: `script/runtest.py` implements (c): `expect` failures surface as a non-zero exit code, `<name>.out` holds the stdout, and a per-level `expect.json` holds exit codes and arguments. Confirm, or say what to change.
**answer**
The expect.json do not scale with many tests we have. A refactory is required. We use comment blocks /*@expect  */ that contain json for expectations. Each different kind of expectations: standard output, standard error, exit code, introspection states, e.t.c.

## Q-006 Specification license (answered 2026-10-06 → D-061, D-078)
The eve-lang repo is Apache 2.0. Does the specification use the same license, or a documentation license (for example CC BY 4.0) so other compilers can quote it freely?
Blocks: S2.1.
**answer** Resolved, this question must be retired.

## Q-007 Which implementation does `manual/` document? (answered 2026-09-28 → D-005)
The old README says the MD docs are "specific to EVE virtual machine hosted in this repository", but there is no compiler here. What is the implementation's name (the manual uses the placeholder `evec`), in which repository does its code live, and in which language is it written?
Blocks: M7.7; the support file name in M7.3.
**Answer:** Implementation language is Zig, the manual must document features of eve VM, that is a JIT compiler and an interpreter and a server in one single machine. It even has a database and a http server inside.

## Q-009 Name and repository of the Eve VM (answered 2026-09-28 → D-007)
What are the VM's name and executable name (the manual uses the placeholder `eve-vm`), and does its Zig code live in this repo (for example `vm/`) or in its own repository?
Blocks: M7.6 (command-line examples), the support file name in M7.3.
**Answer:** source folder `evevm/`, executable `bin/eve.exe`, the official implementation (D-007).

## Q-010 Exit codes of an Eve process (answered 2026-09-28 → D-010)
The tutorial lists `exit`, `over` and `panic` as ways to interrupt a program, but gives no exit codes. Does `over N;` end the process with exit code N? Which codes do `exit`, `panic`, a failed `expect` and an unhandled error produce? `test/level1/expect.json` assumes `over 1;` → 1 (a02). The VM stub uses 70 for "not implemented"; the spec could reserve a range for VM failures.
Blocks: S5.2, the exit codes in `expect.json`.
**Answer:** `over` = 0, `over 1` = 1 (abnormal), failed `expect` = 2 (error), failed `assert` = 3 (warning) (D-010).

## D-009 Test runner and test-driven workflow (2026-09-28)
Tests are written first, then run on the VM with `python script/runtest.py <level|all|test>`. Reports go to `temp/output/*.md` (not versioned). A failing result leads to a fix in the VM, the spec or the test, one feature at a time. Utility and test scripts live in `script/` (moved from `.claude/scripts/`). Usage and conventions: `test/readme.md`.

## D-010 Process exit codes (2026-09-28)
Answers Q-010. **Corrected 2026-10-06 (D-094):** `over N;` does not exist (D-038); the code 1 is `panic;`. The table below is the corrected one.

| Code | Cause | Meaning |
|---|---|---|
| 0 | end of `process`, `over` or `over 0;` | normal exit |
| 1 | `panic;` | forced, abnormal exit: incorrect parameters or environment. Not an error, but the job fails |
| 2 | failed `expect` | error |
| 3 | failed `assert` | warning |

Still open: the code of `exit`; whether a failed `assert` stops the process or only sets the final code; which code wins when several apply. An unhandled error ends the process with the code of the error (D-063). The VM stub uses 70 for "not implemented", outside this range.

## D-011 Comments (2026-09-28)
From `issues/syntax.md` SYN-03. Eve comments are `#`, `##`, `**`, `(* ... *)` and `/* ... */`. `#` and `##` start only at the beginning of a line, without indentation. `**` runs to the end of the line and may follow code or be indented. `(* ... *)` is an expression comment; `/* ... */` is a block comment. The `--` end-of-line comment and the `+- -+` box comment are removed; all `--` comments in `.eve` files and tutorial examples were converted to `**`. Amended by D-014: `(* ... *)` became `(** ... **)`.

## D-012 Identifiers and the driver header (2026-09-28)
From SYN-01, SYN-02. `-` is not allowed in identifiers, to avoid confusion with the `-` operator. The driver header and the `process` keyword need no `:` (`driver a01_driver()`, `process`). Amended by D-015: headers end with the keyword `is`.

## D-013 Not-equal is `<>`; `!` marks unsafe operations (2026-09-28)
From SYN-05. `<>` is the not-equal operator; `!=` is not Eve. `!` is the sigil for unsafe
operations (its placement: SYN-19). All `!=` in `.eve` files and tutorial examples became `<>`.

## D-014 Comments: nesting, expression comments, file header (2026-09-28)
From SYN-04, SYN-16, SYN-17, SYN-18.
- `/* ... */` does not nest: the first `*/` closes the comment.
- Expression comments are `(** ... **)` (not `(* ... *)`, which clashes with the vararg `*` in `f(*args)`). They may span lines.
- A file starts with `#!` (shebang: a free script of sequential statements, no `driver` or `process` needed), `#` (title) or `##` (subtitle).
- Box comments became block comments: `+-` → `/*-` and `-+` → `-*/` in 6 `.eve` files and in the tutorial examples; lines of dashes in examples became `**--…`.

## D-015 Declaration headers end with `is` (2026-09-28)
From SYN-15. A header ends with the keyword `is` instead of `:`: `driver name is`,
16. 
`driver name(params) is`, and the same for `aspect`, `module`, `function`, `routine`, `method` and `constructor`. `()` is optional when there are no parameters. `process` has no colon. Applied to every example: 94 + 61 headers in the tutorial, 53 in `.eve` files. Class headers with a body still end in `:` (CLS-01 open).

## D-016 Control-flow blocks (2026-09-28)
**Superseded in part (D-094):** the closers by D-034 (`done label;`), the loops by D-033 and D-074 (`while c do`, `for x in r do`, `loop … do … repeat`), `skip` by D-074, the job by D-020 and D-034, the parallel group by D-090 (`do`/`start`/`done`, not `fork`/`begin`/`join`). Read the table below as history.
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

Interruptions: `break` leaves a loop, `next` starts the next iteration, `stop` ends a job without error. `then` now means "after the block completed"; branches use `do`. Removed: `try`, `catch`, `resolve`, `skip`, `split`, `run`, `cycle label:` as a header. All tutorial pages and `.eve` files were converted; syntax.html keyword, block and interruption tables were rebuilt.

## D-017 Assignment, visibility, unsafe calls, shift operators (2026-09-28)
**Superseded in part (D-094):** the `=` expression and the chain `a = b = 5` by D-079; the prefixes `.` and `_` by D-085 (`public`, `protected`, `private`); the meaning of `!` by D-087 (non-deterministic, for functions) and D-081 (unsafe, for methods).
From SYN-06, SYN-08, SYN-10, SYN-19.
- `=` is an expression: no type inference, returns its value, chains (`a = b = 5 : Integer`, `let a = b = c = y : Integer;`), copies/borrows a value; also binds typed parameters. `:=` infers the type, is a statement (not an expression), and evaluates the right side fully.
- In a declaration, a leading `_` marks a protected member and a leading `.` a public member; neither is part of the name. `$` is part of the name (system-wide variable).
- `name!()`: a function or method that may raise, has side effects, or bypasses safety checks.
- `<<` and `>>` are shift modifiers (change a value in place). `->` and `<-` are reserved, unused.

## D-018 Test file names use `_` (2026-09-28)
From SYN-14. Test files follow identifier rules: `a01_driver.eve`, `a02_comments.eve`,
`a03_print.eve` (+ `.out`); conventions `a01_feature.eve`, `b01_feature.eve`, `c01_feature.eve`.

## D-019 Lexical rules: escapes, identifiers, `**`, precedence (2026-09-28)
From SYN-20 to SYN-24.
- Escapes in `"…"` and `'…'`: `\` `\"` `\'` `\{` `\}` `\n` `\r` `\t` `\0` `\xHH` `\u{H…}`
  (1 to 6 hex digits). Any other `\` sequence is a lexical error. `"""…"""` text is raw (no escapes). The `&code;` and `\LF` / `\CRLF` forms are dropped.
- Identifiers are case-sensitive, at most 42 characters.
- `**` may appear anywhere, including column 0 and the first line (a row of `*****`).
- `option` was a keyword: a method could declare a second parameter set, passed by name after `option`: `method name(*args) option (params)`. Removed by D-029. `print` is such a method; its `separator` defaults to `","`.
- Operator precedence, highest first: `.` `()` `[]` · unary `-` `not` · `^` (right) · `*` `/` `%` · `+` `-` · `..` `+-` · `<<` `>>` · `&&` · `||` · `==` `<>` `<` `>` `<=` `>=` `=~` `is` `in` `eq` · `and` · `xor` · `or` · `if … else` (corrected 2026-10-06: `~` became `=~`, `+-` added, D-079; the table is the one of syntax.html).

## D-020 Jobs without handlers; `recover` decides (2026-09-28)
Replaces the job handlers of D-016. Answers PRC-01, PRC-04, CTL-14; partly PRC-02, CTL-03.
- A job is `label: job` [declarations] `do` … `done job [label];`. The `error`, `other error`, `check` and `clean` clauses are removed; `error`, `check` and `clean` are no longer keywords. Write jobs that do not fail. Jobs are used only in a process (driver or aspect), at the top level, not nested; routines, functions and methods have none. The label is required.
- A job passes at `done` or `stop` and fails when an error is raised in it (also from a called routine or method). The status is recorded automatically.
- Any error in a process jumps to its `recover` region. There, normal control statements
  (`if`, `match`) on `$error` (`$error.job` is the failed job's label) choose one of:
  - `retry`: run the failed job again, from its declarations;
  - `resume`: the error is handled, the job stays failed, the process continues after its `done`;
  - `abort`: end the process, run `finalize`, propagate the error to the calling process.
- `retry` and `resume` need a failed job; an error outside a job can only be aborted. Raising an error in `recover` aborts with that error. Reaching the end of `recover` handles the error: the process ends normally. A process without `recover` aborts on every error.
- `finalize` runs once when the process ends (`return`, `exit`, end of `recover`, `abort`), not after `over` or `panic`. Preconditions use `over 1 if condition;` (the old `abort if`).
- `resume` keeps its coroutine meaning (`resume name;`); the bare `resume;` in `recover` is the job form. Open: exit code of an aborted driver (D-010). Applied to control.html, processing.html, syntax.html (keyword tables).

## D-021 Indexing is 1-based (2026-09-30)
From COL-06. Idea from bee-lang (D1). Eve indexes lists, arrays, matrices and strings from 1.
- The last element is `a[-1]`, the one before it `a[-2]` (negative indexes count from the end, D-079). `#` is not an index symbol: it would clash with `#{…}` interpolation.
- `$` is only the prefix of a system variable (`$error`, D-017).
- Index 0 is an error (`a[0]`).

## D-022 Ranges: exclusive ends, postfix step, slices use `..` (2026-09-30)
From TYP-10, COL-08. Idea from bee-lang (D13).
- Range operators: `a..b` is [a, b]; `a..<b` is [a, b); `a>..b` is (a, b]; `a>..<b` is (a, b). Each is one token (longest match). Open ends keep `?`: `(0..?)`, `(?..0)`.
- The step is a second parenthesised value after the range: `(min..max)(step)`, for example `(0..10)(2)` or `(1..5)(0.1)[3]` (= 1.3). The `(min..max:step)` form is removed. The step also sets the precision (TYP-11). A range type is `Type Small = (0..1)(0.1) <: Range;`.
- A range is a value, not an array: `new a = (x..y)(n);` makes a range. The only way to put a range in an array is the builder (D-023).
- Slices use ranges as indexes: `base[6..-1]`, `base[x..x + 3]`. The `[n:m]` form is removed, so `:` keeps its pair meaning only. Brackets never define a range or domain by themselves.
- Applied to demo/domain_demo.eve, demo/numeric_range.eve and the tutorial pages collections, control and types (`(a..b:step)` became `(a..b)(step)`, `[n:m]` became `[n..m]`).

## D-023 Arrays from ranges use the builder only (2026-09-30)
From a discussion of `[1..10](2)`. The builder `[x | x in (1..10)(2)]` is the only way to fill an array from a range. The shorthands `[1..10]` and `[1..10](2)` are not Eve: a bracket after a value is indexing or slicing (`a[1..10](2)` stays free for stepped slices), and brackets never define a range (D-022). The array type stays `[]Integer` / `[10]Integer`: `new a := [x | x in (1..10)(2)]: []Integer;`.

## D-024 Cartesian product is `><` (2026-09-30)
From the matrix builder example. `a >< b` is the cartesian product of two collections or ranges: a sequence of pairs in row-major order (the left operand is the outer loop), for example `(x, y) in (1..4) >< (1..4)`. It is one token (longest match), not `>` then `<`. It is easy to confuse with `<>` (not equal), so the compiler reports a hint when `><` has operands that are not collections or ranges (`did you mean <>?`), and when `<>` has two collections or ranges. A builder can also use several generators (`x in A and y in B`), which gives the same product without `><`.

## D-025 No routines: a method is any subprogram with side effects (2026-09-30)
**Superseded (D-094):** by D-086. Every subprogram outside a class is a function; a method belongs to a class; there are no module-level methods.
Answers FUN-03, FUN-09, FUN-I1, TYP-17, CON-01, CMD-01. Amends D-015 and D-016.
- There are two subprogram keywords: `function` and `method`. `routine` (and procedure) is removed.
- A plain function has no side effects: it does not change globals or arguments and calls only plain functions. A function that has side effects or is not deterministic is marked `!` (D-027).
- A method may have side effects and may return a result, or none: `method name(params) => (@result: T) is`. Returning a result does not make it something else.
- A method can be declared in a class (with `@self`) or at module level, outside any class (no `@self`). A module-level method is public with a leading `.` (`method .write(...)`) and private with a leading `_` (D-017). Visibility of an unmarked name: D-035.
- A method is called as a statement, `name(args);`, with or without `()` when it has no arguments. There is no `call`. `call` only runs a shell command (command.html). An asynchronous method is a method started with `start` (D-026).
- Applied to every tutorial page, the demos (`routine_call.eve` became `method_call.eve`), the keyword tables and the Notepad++ UDL files.

## Q-012 How does an enclosed function use method state? (answered 2026-09-30 → D-027)
D-026 makes a function inside a method a closure. Can the enclosed function only read the state of the method, or also change it? A function has no side effects (D-025), so a counter like `generator` in functions.html (`let current += 1`) would have to be a method, or the method changes `current` itself. How is a closure created and returned: `new f := make_counter(0);` where `make_counter` is a method that returns a function? This decides the rewrite of the closures section (FUN-06).
**Answer:** The enclosed function has side effects, so it is a `!` function and may change the state (D-027).

## D-027 Functions with side effects or randomness end with `!` (2026-09-30)
**Superseded (D-094):** by D-087. `!` on a function means non-deterministic only; a function with a result changes nothing.
Answers Q-012. Refines D-017 (`name!()`), D-025 and D-026.
- A plain function is deterministic and has no side effects. A function that has side effects, or is not deterministic (stochastic, for example `random!()`), ends with `!`: `name!()`. A plain function can not call a `!` function or a method.
- A method has no `!`: a method is assumed to have side effects all the time. A function that calls a method is unsafe and must use `!`.
- A method creates a function and encloses it. The enclosed function shares the state of the method and may change it, so its name ends with `!`. It is a closure, and a closure that returns a new value on every call is a generator: `new index! := generator(0); print index!();`.
- Only methods (and functions enclosed in them) have state. A plain function has none and can not be suspended.
- Applied to the closures section of functions.html (the `generator` example is now a method).
- Open: the exact lambda syntax of an enclosed function (`let next! := Function() => …`).

## D-028 Functions: results, defaults, arguments, lambda (2026-09-30)
**Amended (D-094):** the first bullet ("a function must have a result") by D-086; the lambda bullets are Q-025 (open).
From the FUN-01 to FUN-10 answers. Refines D-027.
- A function must have a result; a subprogram without a result is a method (FUN-01). A function can return a list of results `=> (@r1:T1, @r2:T2)`; `$result` is then the list `(result1, result2)`. `@` makes the result a reference, so `let v := f(x);` is valid and `let 2 := f(x);` is not (FUN-02).
- In a parameter list `=` defines a default value, `:=` executes an expression (FUN-04).
- Positional arguments go first; mandatory parameters need no name; optional parameters must be named (FUN-05).
- A function is an object of type `Function`, restricted if it is pure (FUN-06).
- There is no `Lambda` type. A lambda is a notation that creates a function in one statement: parentheses are mandatory, a list of expressions gives several results, and the type follows the parentheses: `():Type`, `():(Type, Type)`. A signature type is `Type BinEx = (p1, p2 :Integer):Integer <: Function;` (FUN-07, FUN-08).
- A lambda can be assigned to a function identifier; if the identifier is not defined, it is only a pointer, passed to a parameter `@param`. The keyword `function` must be followed by an identifier (FUN-10).
- Functions do not handle errors: only a process does. Use preconditions; a runtime error propagates to the process (FUN-03).
- Applied to functions.html (notes, arguments, lambda section, FUN-F1 and FUN-F2 fixes).
**answer** Sounds perfect. So perfect that I'm thinking again what if we keep this as it is and we create routines after all.

## D-029 One parameter list; parameters after a vararg are named (2026-09-30)
Replaces the `option` keyword of D-019; answers SYN-22 again.
- A method or function has one parameter list, never two: `f()()` does not exist and `option` is removed.
- Optional parameters may follow the vararg parameter. In a call they must be named with the pair operator: for `f(*x, y = ",")` the call is `f(x1, x2, x3, y: b)`. Without the name, `y` would be taken as one more element of `x`.
- `print` is `method print(*args, separator = ",")`: `print (1, 2, 3, separator: " ");` prints `1 2 3`.
- Not related: the step of a range, `(min..max)(step)`, is a value postfix of a range (D-022), not a second parameter list.
- Applied to syntax.html (print section) and the SYN-22 issue.

## D-030 Control page answers (2026-09-30)
**Amended (D-094):** the optional job label and the name `job<line>` by D-034 (the label is required); `cycle` and `repeat [label]` by D-033 and D-074; "`any` is removed" stays; `stop`, `break` and `exit` stay.
From CTL-01 to CTL-16. Refines D-016 and D-020.
- **Job (CTL-01, 03, 16).** The label is optional. A job without a label starts with `job` and ends with a naked `done;`; its implicit name is `job<line>` (for example `job24`). A labeled job is `name: job` … `done job [name];` and `job` is required after `done`. Status values: `"none"` (never executed), `"pass"`, `"fail"`. The state is kept in the process map `jobs["name"].status`, `.error`, `.line`; `$error.job` is the failed job's name (a string). Nothing is reported automatically: the process reads the map in its `finalize` region (`finalize` was kept instead of `resolve`).
- **Interruptions (CTL-02, 15).** `stop` ends a job and nothing else; `break` ends a loop (an outer loop with a label); `exit` ends the process. `stop` inside a loop inside a job ends the job.
- **Match (CTL-07).** The optional `[Type]` is removed. `any` is removed: `when other do` runs only when no `when` matched; `then` runs after the match for any path. A `when` can test a range: `when (1..5) do`.
- **Loop scope (CTL-06, 08, 11, 12).** `if` and ladder open no scope. The `loop` header is optional; it holds the declarations, which live in the loop scope, survive all iterations and are visible in `then`. Without a header the `cycle` has no private scope (the parent scope is used). `cycle` starts the executable region; a `new` variable in it is created on the stack at every iteration. `for` creates an implicit scope for its control variable only if the loop has no header; the control variable is visible in `then`, not after `repeat`.
- **Repeat (CTL-05, 13).** `repeat [label] [while condition];` starts another iteration only while the condition is true. `repeat if` does not exist (fixed in control, algorithms, concurrency). `while` and `for` loops take no condition after `repeat`.
- **While else (CTL-10).** `else` runs only if the condition is false the first time. `then` runs every time the loop ends, also after `break`.
- **Removed earlier (CTL-04, 09, 14).** `then`/`loop` optional answer superseded by D-016; `next` starts the next iteration; `check` and `clean` are gone (D-020).
- Block summary table added to the page (CTL-I1). Images copied to `tutorial/img/` (CTL-F1).

Spec additions: `spec/syntax/statements.md` (blocks, repeat while, match ranges),
`spec/semantics/control.md` (job names and status map, loop scopes, then/else rules).

## D-032 Types page answers (2026-09-30)
**Amended (D-094):** `Symbol` is `Rune`, `NIL` is `nil`, `HashMap` is `DataMap`, Rational moves to version 2, `Null` is a type and `null` its value (D-080); the declaration order of TYP-07 is `new a = 0 :Integer;` (D-076, D-079); `U-` is dropped.
From TYP-01 to TYP-22, TYP-I3. Applied to `tutorial/types.html`.
- Native types are `u8 u16 u32 u64`, `i8 i16 i32 i64`, `f32 f64` (no `i128`, no `f16`). Only core libraries use them; scripts use primitive types (TYP-01).
- Primitive sizes: `Byte` u8, `Short` i16, `Integer` i64, `Natural` u64, `Real` f64, `Float` f32, `Ordinal` named u16 values, `Symbol` one Unicode code point on 32 bits (max U+10FFFF), `Time` milliseconds of the day, `Duration` an object stored as i64 milliseconds (TYP-02).
- `Rational` is `3\4`: two Integers, evaluation postponed until needed, computed with a precision. `Complex` is reserved, not in 0.1. `Range` is composite, not a number (TYP-03).
- Literal types: decimal `Integer` (also non-negative); `0x…` and `0b…` `Natural`; `9.9` `Real`; `1/2` is a division, so `Real`; `3\4` `Rational`; `'a'` and `U+…` `Symbol`; `"a"` `String`; `''` the empty Symbol (NIL); `""` the empty String; `[1, 2, 3]` `Vector[Integer]`; `()` List, `{}` DataSet, `[]` Vector when empty. `Binary` and `Word` do not exist (TYP-04).
- Unicode literal: one form `U+` with 4 to 6 hex digits, up to `U+10FFFF`; `U-` is dropped (TYP-05).
- NIL is `''`, the empty ASCII symbol; Null is no value and is not a Symbol (TYP-06).
- Declaration order is `new a = 0 :Integer;` (space before `:` optional); `new x :Integer = 5;` is wrong (TYP-07). `new` declares and takes a type; `let` takes no type; `:=` executes an expression (TYP-08).
- A process has no name: it takes the name of its driver or aspect (TYP-09).
- `[x..y]` is slice notation, never a range or domain; a range type is `Type Small = (0..1)(0.1) <: Range;` (TYP-10, D-022). The zeros of a decimal range literal indicate its precision (TYP-11).
- A variant is created only with `new v :{Real | Integer};` (or a `class … <: Variant` type); `set` makes constants, which have one clear type; the variant takes a type when a value is assigned (TYP-12).
- `/` always returns `Real`; `new x = a / b :Integer;` converts the result (TYP-13). `parse` coerces to the type of the target: Integer loses the decimals, Real keeps them, no error (TYP-14).
- Template placeholders start with `#`: `#s` string, `#n` number, `#{a}` variable `a` (TYP-15).
- `is` can check a type (`x is Integer`) and also introduces a block; `type` is a function and a method (TYP-16, TYP-I3). `call` is for shell commands only (TYP-17, D-025).
- `True` and `False` are constants of type `Logic`, not `Byte` (TYP-18).
- Date (proposed, awaiting review): an object with `era` (BCE, CE), `year` (1 or more), `month`, `day`; built with `"…".parse(YMD)` or an object literal with a `:Date` hint (TYP-19).
- Time formats: `T12 = "hh:mm:ssxx, 999ms"`, `T24 = "hh:mm:ss, 999ms"`, xx is am or pm. Duration is an object with the fields `year, days, hours, min, sec, ms` (TYP-20).
- `as` formats a value one way; the reverse is `String.parse(format)` (TYP-21).
- "Operators are functions, dispatch on the left operand" is an implementation note, not a language rule (TYP-22).

Spec additions: `spec/semantics/types.md` and `types.json` (native and primitive types, Rational, literal defaults, variants, coercion, division, `parse`); `spec/lexical/lexical.md` (numeric, `U+`, Symbol, NIL, String, placeholder, date, time and Duration literals).

## D-033 Loops close with `done`; no `repeat`, no plain loop; `cycle` (2026-09-30)
Replaces the loop rows of D-016 and the `repeat` rules of D-030 (CTL-05, 08, 13). Author decision.
- Every block closes with `done`. A loop closes with `done loop [label];` (while and for).
- `repeat` is removed. The body opener `cycle` is replaced by `do`: `while c do`, `for x in r do`.
- `[label:] loop` is only the optional header of a `while` or `for` loop: label and declarations. There is no unconditional loop: an infinite loop is `while True do … done loop;`, left with `break`. The compiler accepts a constant `True` condition without a warning; its `else` never runs.
- `cycle [label] [if condition];` is a statement of a `while` loop: go to the next iteration (back to the condition). The compiler turns it into a jump. Using `cycle` outside a `while` loop is an error.
- `next [label] [if c];` is only for `for` loops (advance the index). `break` and `then` are unchanged.
- A do-while is `while True do … break if not c; … done loop;`.
- Applied to control (section "Unconditional Loop" removed, sidebar entry too), syntax and the other tutorial pages, `js/eve1.js`, `js/eve3.js` and the demos.

## D-034 Closers: `done label;` (2026-09-30)
Replaces the closers of D-016, D-020, D-030 (CTL-16) and D-033. Author decision.
- A job always has a label (the implicit name `job<line>` is removed) and closes with `done label;`.
- A block that has a label closes with `done label;`; a block without a label closes with `done;`. This holds for job, match, while and for loops (the label is the one of the block or of its `loop` header). `if` has no label and closes with `done;`.
- `done job`, `done match`, `done loop`, `done while` and `done if` do not exist. `if` cannot follow `done`.
- Labels of match, loops and parallel groups stay optional (confirmed for parallel); only job requires one.
- `parallel` follows the same rule, with an optional label: `[name:] parallel … fork … join [name];`. A labeled group closes with `join name;`, an unlabeled group with a naked `join;`.
- Applied to control, syntax, the other tutorial pages and the demos (41 closers converted).

## D-036 `let` declares, `:=` mutates, `new` calls a constructor (2026-10-01)
Replaced by D-076 (`new` declares, `let` executes, a class call constructs). Author decision. Replaces the `new`/`let` rows of D-017 and D-032 (TYP-07, TYP-08) and the constructor form of CLS-03 to CLS-06.
- `let` declares a variable, like `var` in other languages: `let a := 0;`, `let a = 0 :Integer;`. It takes a type. `new` no longer declares variables. `set` is unchanged (constants, D-031).
- Mutation needs no keyword: `a := a + 1;`, `a += 2;`, `t['one'] := 1;`, `self.x += a;`. `let a := …;` on a name that already exists in the scope is an error (redeclaration).
- `new` calls a constructor and is an expression: `let p := new Point(1, 2);`. A bare class call `Point(1, 2)` is not a constructor call.
- A constructor and a destructor are declared inside the class body and have no name (the class is known). The constructor has two lists: `(@self)` first, then the parameters; there is no `=>` list: `constructor(@self)(x = 0, y = 0 :Real) is … return;`. `@self` has no type: it is always an object of the class. `new` passes the second list. The type list of a generic class belongs to the class header: `class Number(:T) <: Object is constructor(@self)(initialValue: T) …`, `new Number(:i32)(42)`. This changes CLS-03: constructors are no longer outside the class body.
- Inside a class body, an object method takes `@self` without a type. A type is needed only for an extension method, declared outside the class, possibly in another module: `method (@self: Error) .raise(...);`.
- `self` is declared by `@self`, so the constructor assigns it first: `self := new Object();`, or the superclass constructor, by its own name (`self := new Shape(name);`). `super` is not a keyword (CLS-06). `return` carries no value (CLS-05: `return @self;` was a mistake).
- A class header ends with `;` when it has no body, otherwise with `is` (CLS-01). `+=` adds attributes to the new type.
- Attributes: `let self.name := v;` creates a private object attribute (CLS-04); public members are declared with `.`.
- Applied to `demo/` (`let x …;` mutations became `x …;`, `new` declarations became `let`) and `class_point.eve`.
- Open: the form of a private hidden attribute created in a partial constructor, and whether `new` may name a class without a constructor (a prototype class has no instances).

Spec additions: `spec/syntax/declarations.md` (variable, class, constructor), `spec/syntax/statements.md` (`let`, `:=`, `new`).

## D-037 `end name;` closes a class and a module (2026-10-01)
Author decision. Refines D-036 and the closers of D-016.
- A module returns nothing, so it closes with `end module_name;`, not `return;`.
- A class is a declaration, not a subprogram: it closes with `end ClassName;` (a class without body ends with `;` on its header line). `return;` stays for the subprograms: method, function, routine, constructor, destructor.
- Closers now: `done [label];` control blocks (D-034), `join [name];` parallel groups, `return;` subprograms (and today driver and aspect), `end name;` class and module. Regions (`import`, `global`, `constant`, `initialize`, `recover`, `finalize`) have no closer: they end at the next region keyword. `type`, `def`, `set` are one line.
- Applied to demo, the tutorial examples (23 closers) and `class_point.eve`.
- Driver and aspect: `process main is … return;` then `end script_name;`. A script may declare other named processes; `main` is the entry point. `over` ends the process it is in (not the driver). Author answers.
- `start name(args);` runs a named process and waits. `apply aspect.main(args);` runs the main process of an aspect (serial; D-042 made the process explicit). `begin name(args);` inside `parallel … fork … join` starts a process or an aspect asynchronously. Running an aspect creates its `main` process, which can start sub-processes.
- Applied: every driver and aspect in demo, pattern, test and the tutorial (143 scripts) now has `process main is` and `end name;`.
- Open: `start` meant "start a method asynchronously" in syntax.html; that use is dropped (async methods need a keyword, probably `begin`). Does a started process share the driver globals, and how are its parameters and result passed back? Is `over N;` in a sub-process an exit code for the caller's `start`?

## D-038 `over;` has no code; process parameters and globals (2026-10-01)
Author decision. Answers the open questions of D-037. Replaces the `over N` rows of D-010.
- `over;` takes no value: it ends the process it is in with code 0. The forced abnormal exit with code 1 (`over 1;`) is now `panic;` (D-031). Exit codes: 0 `over;` or end of process, 1 `panic`, 2 failed `expect`
- A process can receive parameters, input and output. It returns no result: outputs are parameters marked `@`. `process name(n: Integer, @total: Integer) is … return;`.
- A process has access to the globals of its script: module globals if declared in a module, driver globals if declared in a driver, accesible with . operator if public.
- Applied: `over 0;` → `over;`, `over 1;` → `panic;` in demo, tests, test/readme.md and the tutorial.
- `start` pass a parameter list, outputs marked `@`: `start total(10, @sum);`,
  `begin total(10, @sum);` (the output is ready after the `join`).
- `panic` is global: it is an unhandled exception and ends the whole application, not only the process (D-031).

## D-040 Parameters belong to the main process; the process is indented (2026-10-01)
Author decision. Refines D-031 (indentation) and D-037/D-038 (process).
- A driver or aspect header has no parameter list: `driver name is`, `aspect name is`. The parameters move to the process: `process main(*args) is`. A module has no process and no parameters.
- Inside a driver or aspect the `process` is indented by 2 spaces, with its body, `recover`, `finalize` and `return;`; `end name;` is at column 0. The other regions (`import`, `alias`, `constant`, `global`) stay at column 0. A process in an example that has no driver or aspect (a fragment) stays at column 0.
- Applied to 133 scripts in demo, pattern, test and the tutorial; prose in topology, concurrency, databases.
- Open: a method declared before the process cannot read the process parameters (`demo/method_call.eve` still reads `args` inside `test`, which was already wrong).

## D-041 One scope: no import, alias, constant, global or variable regions (2026-10-01)
Author decision. Replaces the region rules of D-031 (TOP-02, TOP-03, TOP-05) and the layout of D-040.
- A driver, aspect or module has a single scope. The regions `import`, `alias`, `constant`, `global` and `globals` are removed. Their content is declared directly in the scope, in any order: `from … use …;` (import), `def` (alias), `set` (constant), `let` (variable), classes, functions, methods and processes.
- Everything between the header and `end name;` is indented by exactly 2 spaces. Only the header, `end name;` and the comments before the header start at column 0. A process keeps its own regions `recover` and `finalize`, aligned with `process`. A module keeps `initialize` and `finalize`, indented 2.
- A `process` fragment in an example with no driver or aspect is `process main is … return;` at column 0.
- Applied to demo, pattern, test and the tutorial (topology, syntax, compiler, functions, databases): 53 files. The "Script Regions" table of syntax.html lost four rows. `databases.html` imports with `from $evelib/db use (core as db, oracle as orcl);` (the old `import` block had no valid form).
- Fixed on the way: `demo/test_args.eve` (the method header lacked `is`; a stray `process` was inside it).
- Open: the keyword `type` region of the old patterns, the keyword `globals` in `pattern/declaration.eve` (old syntax, kept as is), and whether `from … use` may sit after a declaration (any order is assumed).

## D-044 Issue files and keyword table cleaned (2026-10-01)
Maintenance after D-036 to D-043.
- `issues/`: 116 resolved items (status closed, done or answered) and the answered CLS-01 to CLS-08 were removed. Their answers live in this file; the earlier text is in the git history. Open items that quoted the old syntax were rewritten (collections, concurrency, databases, processing, topology, classes). New open items: CLS-15 to CLS-17, CON-09, PRC-14. Cross-references to removed ids were replaced by decision numbers. `issues/README.md` has new totals.
- syntax.html keyword table: removed `import`, `global`, `constant`, `alias`, `begin`, `release`; added `def`, `end`, `destructor`. 115 words. The highlighter (eve1.js) follows.
- collections.html: element creation `h('c') := 3;` is a mutation, not a `let` declaration.

## D-045 `repeat` replaces `cycle`; `repeat N times` (2026-10-01)
Replaced by D-074 (`repeat` closes a loop tested at the end; `skip`). Author decision. Replaces `cycle` of D-033 and reuses the word `repeat` that D-033 removed as a closer.
- `repeat [label] [N times] [if condition];` is a statement of every loop, `while` and `for`. It jumps to the beginning of the cycle: the loop condition (the range check in a `for`) is verified again and the body runs again. The control variable of a `for` is not incremented; `next` advances it.
- `cycle` is removed (keyword table 115 words). `repeat` outside a loop is an error.
- `N times` is an integer expression. It limits the consecutive repeats of the same cycle: after N repeats the statement is ignored and execution continues after it. The count restarts when a cycle ends without a repeat. Without `times` the number is not limited; a condition that stays true is a user error, like `while True`.
- Variables created by `let` in the `do` region are created again at each repetition; what must survive is declared in the `loop` header.
- Applied to control.html (patterns, notes, examples), syntax.html (keyword and meaning tables), `js/eve1.js`, `js/eve3.js`. The control summary table lost the columns "Opens scope" and "Condition after closer".
- Open: whether `N times` counts per cycle (as written) or per loop.

## D-048 `@` passes by reference, at the declaration and at the call (2026-10-01)
Author decision. Answers CON-02 and CON-10.
- `@` marks an input/output parameter and is required on its argument: `bar(1, 2, @output);`, by name `add(1, 2, op: @result);`, also for elements and slices: `@s[i]`, `@nxt[a..b]`. The argument is a reference to a variable, element or slice; `add(1, 2, result)` and `add(1, 2, @4)` are errors.
- An `@` parameter is in/out (the method sees the caller's value) and has no default value, so it is never optional.
- Without `@` an argument is passed by value, collections included: the method works on its own copy. This is the low-level idiom; `@` is the higher-level input/output abstraction. The VM may implement it as copy on write. Note the parallel with assignment: a parameter without `@` behaves like `::` (clone), one with `@` like `:=` (shared reference), see syntax.html "Assign Expression". `heat_bar` copies the next state with `cur :: nxt;` (D-049).
- In a parallel block this replaces the read-only sharing proposed in D-047: a task gets copies of its inputs and references only to the outputs it owns.
- Applied to concurrency.html (parameter list and text, examples `process_demo`, `output_params`, `shoulder_thread`, rules of parallel methods, `heat_bar` text), types.html and `demo/variant_params.eve` (`swap(@x, @y)`), `demo/output_params.eve` (call, missing comma, `set out :=`, `let result`, expected value 3).

## D-049 `::` is the only clone; no `clone` keyword; slices by `:=` are views (2026-10-01)
Author decision.
- The keyword `clone` is removed (keyword table 112 words). The clone operator `::` makes a deep copy of an object or a collection: `let copy :: original;`. `:=` shares the reference of an object or collection, and copies a native value.
- Slices follow the same rule (closes COL-08): `let v := base[a..b];` is a view over the elements of `base` (writing through it changes `base`); `let c :: base[a..b];` is a new collection with a copy of the elements.
- Matches the parameter rule of D-048: no `@` behaves like `::`, `@` like `:=`.
- Applied to syntax.html (keyword table, "Assign Expression"), collections.html ("Array slicing"), concurrency.html (`heat_bar` clones the next state with `cur :: nxt;`).

## D-058 Collections answers: ordinals, literals, sets, maps, strings (2026-10-02)
**Corrected (D-094):** `(x)` is grouping, not a list; the list of one element is `(x,)` (D-063). `HashMap` is `DataMap` (D-080). `!~` does not exist (D-079).
Author answers COL-01 to COL-20 (issues/collections.md). Closes COL-08 (D-022, D-049) and the list operations of COL-05.
- Ordinal: the first value is 0 (`{False, True}`: False = 0, True = 1). Capitalized names enter the enclosing scope (language rule).
- Literals: `(1,2,3)` is a list, never a tuple; `List(...)` is an optional constructor; `(x,)` is a list of one element. `{}` is the empty DataSet, `{:}` the empty HashMap. Unquoted keys make an Object, quoted or numeric keys a HashMap (quoted = strings, unquoted = identifiers).
- Builders: generators combine with `and`; ranges with open ends such as `(2>..n)` are preferred to filters.
- Deconstruct: `_` is always Null; it can be written but the value is forgotten. `*` alone skips many elements and stays Null; `*rest` collects.
- Array types: Array (1 dimension), Matrix (2), Tensor (3 or more; a 3D tensor is an array of matrices). Slices are `[n..m]` only. `[*]` selects a whole dimension and is needed only for a matrix or tensor (`m[1..2][*]`, `m[*][1..2]`,  `[*][*]` possible but [*] is the same thing, ); a slice takes one value with `:=`. A matrix or tensor also takes one absolute row-major index (`mat[124]`: row and column are computed).
- DataSet: sorted by value, `print` shows the order; a List is not sorted unless sorted explicitly. Operators `&=` and `|=` are removed (`||` union, `&&` intersection, `+=` / `-=` add and remove elements).
- HashMap: a sorted map (by key); the name stays HashMap, `Map` is too short. Assigning to a missing key creates it; `+=` on a missing key raises an error. Elements are created with brackets: `h['c'] := 3`.
- String is immutable; Text is a different, mutable type (a rope or similar). A mutable string is a collection of symbols or a Text. Concatenating a string with another literal gives a String (`"a" + 1`, `'a' + 1`). Class methods can be called with the class name or with an object: same method.
- Regular expressions: the match operator is `=~`, not-match `!~`; a string starting with `/` on the right is a regex.
- Applied: collections.html split in two: strings, text and regular expressions moved to the new strings.html (+ data/strings.json, index.html row 09, pages renumbered); new img/row-major.svg; example and typo fixes (COL-F1 to F4).
- Open: map type notation (`{}(String,Object)` or `{}(Type:Type)`), `&code;` escapes and Fortran-like formats (COL-15, COL-16), how an Object gets new attributes (replaced `&=` by `object.x := 1`), and the exact meaning of `-=` with a position (`lst -= lst[1]`). Spec work pending.

## D-059 Collections follow-ups; one interpolation form (2026-10-02)
Author answers COL-02, 03, 05, 14, 15; COL-16 "apply the proposal". Applied to the tutorial and `demo/`.
- Map type notation: `{:}(Type,Type)`, for example `{:}(String, Object)` (classes.html, collections.html).
- Builder: the first generator is a range or a collection; an optional condition follows, joined with `and`: `(x | x in (1..10) and x % 2 == 0)`. No `if` filter.
- `-=` removes by value (all equal elements): `lst -= lst[1]` removes every element equal to the first. Removing the first or the last element is done with `->` and `<-`. Capturing the removed element in the same statement is open (idea: `lst -> let e;`, and a `let` inside statements such as `while let x in (range)`).
- Objects: `object.x := 1` adds an attribute; an empty Object is the Null `let o :Object;`.
- Escapes: both `&code;` and `\u{H…}` are valid in strings (D-019 had dropped `&code;`; reinstated).
- Interpolation: `"#{expr}"` is the only form. `#s`, `#n`, `#`, `{a}`, `#(x)` and the template operator `?` are removed. Format after a colon, adapted from Fortran: `iW` integer, `fW.D` real, `sW` string, repeat count prefix for collections (`#{m:3i4}`: 3 per row). Literal `#{` is written `\#{`. Proposed by the model, to be refined in the specification.
- Applied: classes, collections, strings, types, command, syntax pages; demo/class_point, method_call, number_to_string, print_type, string_concat.

## D-060 Interpolation escapes `\s{}` `\#{}` `\b{}`; queue direction (2026-10-02)
Author answers COL-05, COL-16. Replaces the interpolation bullet of D-059 (`#{expr}` is gone) and extends D-019.
- Escapes with braces, one family: `\u{H…}` code point (D-019), `\s{expr}` any value as a string, `\#{expr}` a number, `\b{expr}` a boolean (True/False). The old `#{…}`, `#s`, `#n`, `{a}` and `?` do not exist. Literal braces stay `\{` and `\}`.
- Format after a colon, Fortran codes for numbers, Python-like alignment (proposed by the model, to be refined in the spec): `\s{e:[[fill]align][width][.max]}`, `\#{e:[[fill]align][flags][repeat]code[width][.digits]}`, `\b{e:[[fill]align][width][code]}`. align `<` `>` `^` (default left for string and boolean, right for number); fill is one character before the align; number codes `i f e x b`; flags `+` and `,` (thousands); repeat count puts N elements per row (`3i4`); boolean codes `tf` `yn` `01`. The width never truncates (Fortran `*****` overflow is not used); only `.max` cuts a string.
- Lists: the arrow points to the side the element leaves from. `<- lst` removes the first element, `lst ->` the last; `x <- lst` / `lst -> x` remove the first / last element equal to `x`. A queue enqueues at the end (`q <+ x`) and dequeues the first (`let e <- q`). A stack pushes at the end (`s <+ x`) and pops the last (`s -> let e`). The capture forms `let e <- lst;` and `lst -> let e;` are a proposal (a `let` inside a statement, also `while let x in (range)`): open.
- Applied: strings, collections, classes, types, command, syntax pages and the demos that used interpolation.

## Q-013 Numbers: scientific notation and digit separators (answered 2026-10-06 → D-095)
The tutorial links "scientific notation" but defines no literal. Proposal: `1.5e3` and `2e-3` are Real literals (`e` or `E`, an optional sign, digits; a literal with an exponent is always Real); `_` may separate digits (`1_000_000`, `0xFF_FF`), never at the start, the end or next to `.`. Accept, change or reject?
Blocks: `lexical/lexical.md` (Integer, Real).
**answer** Partial accept `2e-3`, `1.5e3` are valid and are always by default double float. Underscore _ in numbers is not accepted. We accept string literals in format "1,000,000"z that is how we can represent large numbers this is a nummber because has the "z" or "r" or "d" or whatever data we want.

## Q-014 Strings: `&name;`, text literal (answered 2026-10-06 → D-095)
(a) Which forms of `&…;` are valid: only HTML names (`&alpha;`), or also `&#955;` and `&#x3BB;`? How do you write a literal `&alpha;`: `\&alpha;`, or `&amp;alpha;`? (b) Is `"""…"""` of type `String` or `Text` (COL-15: Text is mutable)? (c) Proposal for the line breaks of `"""`: the break after the opening quotes and the break before the closing quotes are not part of the text.
Blocks: `lexical/lexical.md` (String, Text literal). 
**answer**
a) HTML names are valid also &# codes are valid. We write `&alpha;` the & character itself is "\&" or "&amp;" both forms are supported.
b) """...""" is type Text and is similar to <text>, <xml> <html> <data> <code> all these tags automaticly create a Text type literal.
c) I agree, the first breack and the last breack are removed if present by the compiler. Same for <tags>.

## Q-015 Interpolation: end of the expression (answered 2026-10-06 → D-095)
In `\#{expr:format}` the colon is also the pair operator. Proposal: the expression ends at the first `:` or `}` outside brackets and nested literals; a pair is written in parentheses. Accept?
Blocks: `lexical/lexical.md` (Interpolation).
**answer** Another proposal was to replace : with & and I accepted that proposal. `\#{expr % format}`.

## Q-016 Small lexical rules (answered 2026-10-06 → D-095)
Proposals, each yes or no: (a) a UTF-8 BOM at the start of a file is ignored; (b) `name!~x` reads as the suffix `!` then `~`, so the operator `!~` needs a space before it; (c) a trailing comma in a list or collection literal is an error; (d) a `#` that is not in column 1 is a lexical error (it was also "last index" and "digit in a pattern" in the old table, both removed); (e) identifiers are ASCII only.
Blocks: `lexical/lexical.md`.
**answer** operator !~ was removed from list of operators. # uses zero indentation and is not an error. Indentation position in EVE is significant. So ## is also allowed. # is a title comment #! is first, in a script (before any comments). 
(c) a trialing comma in alist is not an error (a,b,c,) is a good list (a,) is a good list (a,b,c) is also a good list. Identifiers are ASCII only that is true.

## D-061 Licenses: BUSL-1.1 for code, CC BY 4.0 for the specification (2026-10-02)
The CC BY 4.0 part is replaced by D-078 (CC BY-NC-SA 4.0).
Author decision. Answers Q-006 and the open part of MAN-01; replaces the Apache 2.0 license of the repository and the CC BY-ND 4.0 of manifest.html.
- Code (`evevm/`, `script/`): Business Source License 1.1, text and parameters in `evevm/LICENSE`. Licensor Elucian Moise; Change License Apache 2.0; Change Date 2030-10-02. The Additional Use Grant (proposed by the model, to confirm) allows production use except offering the VM or a derivative as a competing commercial VM, interpreter or hosted service for Eve.
- Specification (`spec/`): CC BY 4.0, full legal code in `spec/LICENSE`. Adaptation is allowed, so the NoDerivatives bullets and the "implementation grant is needed because of ND" reasoning are gone; the grant and the trademark policy stay.
- Manual, demo, pattern, test, plan, issues, tools: CC BY 4.0 (assumed by the model, to confirm). Root `LICENSE` is a summary.
- Applied: LICENSE, README.md (section License), spec/index.md, evevm/README.md, tutorial manifest.html (License section, legal notice).
- Note: the scl repo, which holds the tutorial pages, has a GPL-3.0 `LICENSE`. Which license covers the tutorial text is open.

## D-062 Trademark policy (2026-10-02)
Author request. `TRADEMARK.md` at the repository root: "EVE", the logo and the branding are trademarks of Sage-Code Laboratory. Free: implementing the language, "Built for EVE", "EVE compatible", "Runs EVE scripts", "Based on the EVE language specification", accurate references, unmodified official software. "EVE Compiler / Interpreter / VM" and "EVE Compliant" need a stated spec version, a passed conformance level and an unmodified-fork condition. Not allowed without written permission: a modified compiler, VM or distribution under the EVE name, an incompatible dialect presented as EVE, a modified specification under the EVE title, registering the mark, altering the logo. Applied: TRADEMARK.md, README.md, LICENSE, tutorial manifest.html. Open: confirm the legal entity name.

## Q-018 Regular expressions and the backslash (answered 2026-10-06 → D-097)
D-019 says any `\` sequence that is not an escape is a lexical error, and D-060 makes `\s{` an interpolation. A pattern such as `"/\sis\s/"` (regex.html of the old tutorial, `\d`, `\w`) would then be an error. Options: (a) a pattern writes the backslash twice (`"/\sis\s/"`); (b) a string that starts with `/` is a regex literal and keeps its backslashes (no escapes, no interpolation);
**answer** this sounds good.
(c) a separate raw form. Recommended: (b), with `\"` still allowed for the quote. The tests a28 use patterns without a backslash until this is decided.
Blocks: `lexical/lexical.md` (Regular expression), `test/level1/a28_regex.eve`.

## Q-019 Assumptions of the level 1 tests a04 to a37 (answered 2026-10-06 → D-096)
Each one is a place where the tests state a rule that no decision gives yet; change the test or the spec when you answer:
(a) `1 / 0` raises an error (the demo `recover_demo.eve` assumes it; IEEE would give infinity) (a37);
**answer** correct, we do not handle infinity, so this is ont possible. Rational number 1\0 is also not supported.
(b) printing a DataSet is `{1,2,3}` without spaces, a list `(1,2,3)`, `print (1, 2, 3)` prints `1,2,3` (a05, a20);
**answer** yes print can have a "sep" parameter but this works only with multiple arguments, not for lists.
(c) the formats of `\#{}`, `\s{}`, `\b{}` of D-060 (a11);
**answer** `\#{}` will be replaced with `\n{}` for number, other will be as specified.
(d) `a <+ b` as an expression returns a new list and `x <- lst` removes the first element equal to `x` (a17);

**answer** this is a mistake. let x <- lst, remove first element and create/assign x while let -> y remove last element of list and create/update y. To remove first element without capture we use _ <- or -> _ for last element. Removing first element = x we do not cover yet.
Fix the mistake.
**answer** the expression a <+ b, it depends what is a and if used with let or with new. Normal with let, but if user by mistake used new a <+ b; will trigger an error if a exist and will create a new list if a do not exist and append b into it.
(e) `m[5]` is the absolute row-major index of a matrix (D-058) and `g[1, *] := 5` assigns a row (a19; the test said `g[1][*]`, which D-058 gives another meaning: changed in D-063);
**answer** Use logic. How we can get all elements from a row? We specify [1] the row and [*] all the columns on that row, and is equivalent to g[1, *]. If other interpretation is possible clarify.
(f) `let v := [...]; let view := v[1..2];` is a view (D-049) (a18);
**answer** `let v := [...];` is a valid design pattern to create a dynamic array. new view := v[min..max]; Is a new variable tha hold a view (slice) of several elements in the array. new c :: v[min..max] create a clone of the slice (deep copy). So this is just a confirmation.    
(g) a text literal drops the line break after the opening quotes and before the closing ones (a27, Q-014);
**answer** confirmed
(h) `for (k: v) in map` visits the keys in order (a21); `p.z := 7` adds an attribute to an Object (a22);
**no longer true** new self.z := 7; that will add a new attribute to the object. You can't add attribute outside of a method or constructor. That would breack the encapsulation rules.
(i) a function parameter after a defaulted one is named at the call: `greet("Eve", greeting: "Hi")` (a24).
**answer** confirm. We ise pair-up operator ":" to call optional parameters by name. when function/method use only optional parameters, calling by position is possible, but it could mess-up the code runtime, so refactory is preffered method when signature of functions change. 

## D-063 First execution of level 1: what running the tests taught (2026-10-02)
Model decisions taken while writing the interpreter (`evevm/src/interp.zig`); all of `test/level1/` (37 tests) passes. Each one is a rule the tests needed and no decision gave; change the test or the rule when you answer.
- Author answer: `(x)` is grouping, not a list; `(x,)` is the list of one element (corrects D-058, which said `(x)` is a list). The tests use `(2 + 3) * 4` and `("yes" if c else "no")`; a17 checks `(5,)`.
- A symbol literal holds exactly one code point: `'one'` and `'zz'` are syntax errors ("use "..." for text"). a21 and a36 wrote strings in single quotes; they now use double quotes.
- Matrix indexes: `g[1]` is the absolute row-major index (D-058), so a row is `g[1, *]` and a column `g[*, 1]`. a19 said `g[1][*]`. *(Corrected by D-064: `g[1][*]` is a row again.)*
- `is` between two types compares them: `type(9 / 3) is Real`; `x is Null` and `a is b` test identity for references.
- Errors are `{code, message, job}` (D-055): `raise` gives 4, a failed `expect` 2, an error of the VM (index 0, missing key, division by zero, undefined name, bad operand) 4. `recover` can catch all of them; `$error.message`, `$error.code` and `$error.job` are available there. An unhandled error runs `finalize` and ends the process with its code; the message goes to stderr.
- In `recover`: `retry` runs the failed job again, `resume` goes on after it, reaching the end of `recover` ends the process (handled, `finalize` runs), `abort` ends it with the code of the error. **Corrected 2026-10-06 (D-094):** `abort` runs `finalize` (D-020, syntax.html); the first text said it skips it.
- `panic;` ends at once with code 1 (no `finalize`); `over;` ends with 0 (no `recover`, no `finalize`).
- Real numbers print in the shortest form that reads back (`3.5`, `0.25`; a whole Real prints without a point). Collections print `(1,2,3)` list, `[1,2,3]` array, `{1,2,3}` DataSet, `{'a':1}` map, `{x:1}` object, strings and symbols quoted inside a collection.
- `write (a, b)` writes the values with no separator; `print (a, b)` joins them with `,` (named argument `separator:`).
- Formats of the interpolation (D-060): `[fill][<|>|^][,][i|f]width[.precision]`; strings take a width, an alignment and a precision (a cut); a Logic takes `yn` (Yes/No), `01` or `tf`.
- `new C(args)` without a constructor fills the members in order or by name; with a constructor it runs it, and the object returned is `self` (its class is set to `C`). `new Object()` is an empty Object. *(Replaced by D-076 and D-084: `new` declares, the class call `C(args)` constructs.)*
- Regular expressions: a small subset (literals, `.`, `^`, `$`, `[a-z]`, `\d \w \s`, `* + ?`, `|`), no groups, no back references.
- Command files (`.vmc`): see `manual/usage.md`. Comments are `#` at the start of a line and `**` to the end of a line; a line counts when it ends with a newline; while a script runs only `report` and `stop` are taken from the slot.
- Workflow: `eve -x -i file.vmc` without a script is serve mode; commands `load`, `parse`, `run`, `errors`, `ast`, `inspect`, `status`, `outdir`, `capture`, `log`, `clear`; `script/workflow.py` drives a whole level through one session and reads the reports.

## D-064 Matrix and tensor indexes: `[x, y]` is `[x][y]` (2026-10-03)
Note (D-094): the end anchor `$` was replaced by negative indexes (D-079): `m[3, -1]` is the last column of row 3.
Author request. Corrects the matrix line of D-063 (`g[1][*]` is again a row).
- A matrix or a tensor takes its indexes in one pair of brackets separated by commas or in one pair of brackets per dimension: `m[x, y]` is `m[x][y]`, `t[x, y, z]` is `t[x][y][z]`; the forms mix (`t[x, y][z]`). Reading and writing are the same.
- Each index may be a number, a range or `*`, so a chain selects a part: `m[1..5][3]` is column 3 of rows 1 to 5 (5 elements), `m[3][1..5]` is row 3, columns 1 to 5. The result is an array; a part takes one value with `:=` (D-058).
- One pair of brackets with one index keeps D-058: `m[k]` is the absolute row-major index. Only a chain after it is a second dimension.
- On a value that is not a matrix (a map, a list, a 1-dimension array) each pair of brackets indexes the result of the previous one: `h["k"][2]`, `v[2..5][1]` (an element of the slice).
- Applied: spec/lexical/lexical.md, spec/lexical/delimiters.json, tutorial collections.html (Matrix indexes), evevm/src/interp.zig (`indexChain`), test a38_matrix_index.

## D-065 `demo/` is temporary (2026-10-03)
**Replaced (D-094):** by D-075: the demos are kept, never run, only analysed.
Author decision. `demo/` disappears when the test suite is complete: each demo either becomes a test in `test/levelN/` or is dropped. No new demos are written; new examples go to `test/` as tests.
- 2026-10-03 review: all 45 demos were rewritten to the decisions up to D-064 (title line, `let` for changed globals, `:=` without a type, strings in `"…"`, `$`, `..<` and `>..`, `||` and `&&`, `{"k": v}` and `{:}`, `"""`, `.parse(F)`, `done;`, no redeclaration). 29 run on the VM. 16 need VM work first: `as`, open ranges `(0..?)`, type notations `()T` `{:}(K,V)` `{A | B}`, Rational `3\4`, `wait 10ms`, process parameters, method varargs, `eq`, loop labels, symbol ranges, and the library (`floor`, `ceiling`, `round`, `format`, `parse`, `split()`, `$epsilon`, Time and Date).
- Not in the spec, removed from the demos: `all`/`any` before a collection, the string pipeline `"" <+ (…)`, chained comparisons `a <= x <= b`, `is` between two Integers, scientific notation (Q-013), `is Text` of a `"""` literal (Q-014).
- Open: D-028 says optional parameters are named at the call, D-048 calls `add(1, 2, @result)` with optional `p1, p2` by position. The tutorial copies of about 30 demos have the same errors as the demos had; they are not fixed yet.

## D-069 Methods page; Multitasking after Classes (2026-10-03)
Author decision. Methods get their own tutorial chapter, and Multitasking moves lower, after the chapters it builds on.
- New page `methods.html` (06, after Functions), with `data/methods.json`: the sections Methods (now "Declaration", id `declaration`), Side Effects and Parameters, moved unchanged from the top of `multitasking.html`, plus a short introduction.
- New index order: 05 Functions, 06 Methods, 07 Modules, 08 Classes, 09 Collections, 10 Strings, 11 Control Flow, 12 Processing, 13 Multitasking, 14 Algorithms; Compiler is 19. Multitasking comes after Processing because its parallel groups start aspects. Read next: Functions → Methods → Modules, Processing → Multitasking → Algorithms.
- `multitasking.html` now starts with Generators; its introduction points to Methods. CON-02, CON-03 and CON-10 (parameters) are retired from `issues/multitasking.md` (D-048, D-070).

## D-070 Default values of parameters (2026-10-03)
Author decision. Answers CON-03; refines D-028 ("`=` defines a default value, `:=` executes an expression").
- An optional parameter has a default value, given in one of two forms: `param = value :Type` (a value and an explicit type) or `param := expression` (any expression; the type is inferred from it). The second form is used mostly for its type inference.
- A parameter without a default is mandatory; an `@` parameter never has a default (D-048).
- Already taught this way in methods.html (Parameters); no page change.

## D-074 Loop tested at the end: `loop … do … repeat [while c];`; `skip` (2026-10-04)
Author decision. Replaces the `repeat` statement of D-045 (`repeat [label] [N times] [if c];`), the do-while of D-033 (`while True do … break if not c; … done;`) and `next` (D-033). Restores the author's original design of D-016/D-030 (`repeat` closes a loop) and `skip` (removed by D-016). Eve does not have to be regular: it has to be logical and expressive. `done` is not the only closer anyway (`return`, `end`).
- **Three loops.** `while c do … done;` tests at the start; `for x in r do … done;` visits a range or a collection; `[label:] loop [declarations] do … repeat [label] [while c];` tests at the end, so the body runs at least once. A bare `repeat;` loops until `break`: this is the infinite loop (`while True do` stays valid but is no longer the idiom).
- **`repeat` is only a closer.** It closes the `loop … do` block and nothing else. The statement form inside a body and `N times` are removed.
- **`skip [label] [if c];`** goes to the continuation point of the loop: in a `for` it advances to the next element, in a `while` it tests the condition again, in a `repeat` loop it runs the test at the end (with a bare `repeat;` it starts the next cycle). It replaces `next`, which is no longer a keyword (free for `g.next()` of generators, D-067).
- `break [label] [if c];` is unchanged. The `loop` header keeps its role for `while` and `for` (label and declarations, D-033): after the declarations, `while` or `for` starts a loop tested at the start, `do` starts a loop tested at the end.
- A `repeat` loop has no `else` (the body always runs) and no `then` region. Open: should it have a `then`, and where would it go.
- Keywords: `skip` added, `next` removed; `repeat` changes meaning.
- Applied: control.html (While Loop, new section Repeat Loop, For Loop, block summary), syntax.html (keyword and meaning tables), algorithms, topology and multitasking pages (`while True do` became `loop do … repeat;`), `js/eve1.js`, `js/eve3.js`, `plan/design-multitasking.md`, VM (`parser.zig`, `ast.zig`, `interp.zig`), test a14 (`next` → `skip`), new test a39_repeat.

## D-075 Mission, role of the tutorial, demos kept (2026-10-04) *(demos: replaced by D-099, `demo/` retired)*
Author decision. Answers review points RPJ-D01, RPJ-R03, RPJ-R04 and RPJ-R07 (`review/01-project.md`); replaces the "demo/ disappears" part of D-065.
- **Mission.** Eve is an enterprise ETL client/server platform. Teaching is not its primary goal. For ambitious developers who want to master the craft it is a complete project: language, VM, server, protocol, web.
- **Many implementations.** The specification must let a specialist write another compiler or interpreter, which may be native rather than a VM, and may be more restrictive (a subset that passes a stated conformance level).
- **Spec and tutorial.** The goal is a self-sufficient specification. The tutorial becomes independent didactic material for learning Eve, not the source of truth. Until the spec reaches that state, the tutorial stays in development, linked as `tutorial/` (scl repo), and is the reference the spec is built from. The source of truth moves to the spec together with the license change of the code (Change Date 2030-10-02, D-061).
- **Priority now: the tutorial.** VM (Zig) and test-suite work is postponed until the author has read the review.
- **Demos are kept.** `demo/` stays as a source of ideas, a comparison point for the new spec, and inspiration for test suites. Demo files are not tests: they are not run or parsed by the VM, and are checked only by static code analysis (scripts that read the text).

## D-076 `new` declares, `let` executes, a class call constructs (2026-10-04)
**Changed by D-096:** `let` creates a missing name by type inference (Q-017); `new` on an existing name stays an error.
Author decision. Replaces the `let`/`new` rows of D-036 and restores the author's original design, aligned with bee (`spec/02-statements.md` of bee-lang). Answers the capture proposal of D-060 (`let e <- q`).
- **`new` creates.** `new x := 0;` (inferred type), `new x = 0 :Integer;` (explicit type), `new copy :: original;` (clone), `new self.x := x;` (object attribute). In an assignment, `new` creates the names that are missing and uses those that exist: `new lst -> x;` takes the last element of the existing `lst` into a new variable `x`; `new e <- q;` dequeues into a new `e`. (The `new lst -> x;` form is replaced by D-077.) Most of the time the new value comes from a literal, an expression or a constructor, by a left or right assignment. Redeclaring a name in the same scope is an error.
- **`let` executes.** `let` triggers an assignment or an expression on names that exist: `let x := 1;`, `let x += 2;`, `let x << 2;`, `let lst -> x;`, `let _ <- q;` (D-077). It works with unary and binary operators and with method and function calls (`let f(x);` runs `f` and drops its result). `let` on a name that does not exist is an error.
- **`let` is required for a mutation.** A bare `x := 1;` or `x += 1;` is a syntax error: every statement that changes a value starts with `let`. A bare call stays valid: `save(data);`, `print x;`. *(Applied from the author's description; the author confirmed only the constructor point in the session: confirm.)*
- **Constructor.** A class called like a function builds an object: `new p := Point(1, 2);`, generic `new n := Number(:i32)(42);`, in a constructor `let self := Object();` or `let self := Shape(name);`. `new` is no longer an expression; `new Point(1, 2)` is not Eve.
- `set` (constants) and `def` (aliases) are unchanged. A generator object is made by a call: `new g := count_to(3);` (D-067).
- Applied to the tutorial only (all pages: 468 code lines converted by `temp/d076_tutorial.py`, then the prose of syntax, classes, control, compiler, manifest, modules, multitasking, topology, types, functions, collections). The VM, the tests and `demo/` still follow D-036: their update is postponed (D-075).

## D-077 Inline `new`: one statement changes a variable and creates another (2026-10-04)
**Changed by D-096:** an arrow never removes by value (`lst.delete(v)` does), and `let lst -> e;` captures into `e`, created when missing.
Author idea. Refines D-076 and D-060 (removing elements with `<-` and `->`).
- **The statement keyword belongs to the first name.** `new` when the first name is created, `let` when it changes.
- **Inline `new` marks a created name on the right side.** `let lst -> new x;` removes the last element of `lst` into a new variable `x`. It replaces `new lst -> x;` of D-076 (no implicit creation of missing names: every created name is marked by `new`).
- **A `new` statement may change the names it reads from.** `new x <- lst;` creates `x` with the first element of `lst` and removes that element from the list; `let` is not needed for the change of `lst`.
- **New name or existing name decides the operation.** With an inline or leading `new`, the arrow captures an element: `new x <- lst;` (first), `let lst -> new x;` (last). With a name that exists, the arrow removes by value (D-060): `let x <- lst;` removes the first element equal to `x`, `let lst -> x;` the last one. To drop the element, the target is `_`, which swallows the result (D-058: `_` is always Null, a value written to it is forgotten): `let _ <- lst;` removes the first element, `let lst -> _;` the last one. `_` is a sink, not an existing name, so the arrow removes by position, never by value. There are no bare forms (`let <- lst;`, `let lst ->;`). Author decision, 2026-10-04.
- Open: where else an inline `new` is allowed (other operators such as `let a, new b := f();`, or `for`/`while` headers such as `while new x <- q do`).
- Applied: collections.html (list removal note, queue and stack examples: `let stack -> new e;`, `let 'z' <- lst;`), syntax.html (assignment keywords text, `let` and `new` rows).

## D-078 CC BY-NC-SA 4.0 for the specification and the documents; mission (2026-10-05)
Author decision. Replaces the CC BY 4.0 part of D-061 (the code stays BUSL-1.1). Answers review point RPJ-R05.
- **License.** The specification, the tutorial text, the manual, the examples, the tests, the plans and the scripts are under Creative Commons Attribution-NonCommercial-ShareAlike 4.0 (CC BY-NC-SA 4.0). Learning, teaching, research and non-profit use and adaptation are allowed, with credit and under the same license. A commercial implementation or product needs written permission from the author. Contributions back to the official specification and tutorial are requested (the license itself cannot make them mandatory).
- `spec/LICENSE` holds the official legal code (downloaded from https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode.txt) after a short project preamble. Applied also to README.md, spec/index.md, spec/README.md, TRADEMARK.md, tutorial manifest.html (License section, Implementation Grant, Reference Code License, Legal Notice), plan/features_inventory.md.
- **Mission.** "Eve is a data-centric DSL built for internet ETL pipelines. It provides a gradual typing JIT compiler and virtual machine. This new language delivers a unified syntax for data transforming and routing between local client and server backend." Applied to README.md, tutorial manifest.html (intro) and index.html (description and hero).
- **scl repository (resolved 2026-10-05).** The GPL-3.0 `LICENSE` of scl is replaced by `LICENSE.md`, the Sage-Code Laboratory licensing by asset type: documentation and prose under CC BY-NC-SA 4.0; code snippets, examples and executable tutorial code under the Apache License 2.0. Full texts in `scl/LICENSES/`. So the code blocks of the Eve tutorial are Apache 2.0, while its text, the specification, the tests and `demo/` stay CC BY-NC-SA 4.0. Applied: scl `LICENSE.md`, `LICENSES/`, `legal.html` (section Platform Assets), tutorial manifest.html, eve-lang README.md.

## D-079 Last element `[-1]`, approximate match `=~`, range `+-`, light assignment `=` (2026-10-05)
Author decision, from the answers to review points RSY-D02, RSY-D03, RSY-D05 and RSY-X01 (`review/02-syntax.md`) and the answers of 2026-10-05.
- **Negative indexes count from the end.** `a[-1]` is the last element; `a[-x]` is `a[N + 1 - x]` with `N = a.count()`, so `a[-N]` is `a[1]`. Collections stay 1-based. `a[0]`, and any index outside `-N..N`, is an out-of-bounds error. A slice may mix both: `a[1..-1]` is the whole array, `a[2..-2]` drops the first and the last element. `$` is only the prefix of system variables.
- **`=~` is the approximate match, `==` the exact one.** The `=` in front gives the reader a clue: `==` is precise, `=~` is approximate. For text, `s =~ /regex/` matches a regular expression. For numbers, `x =~ b +- 0.01` is true when `x` is within `0.01` of `b`; the tolerance is optional, `x =~ b` uses the system variable `$epsilon`. `~` alone and `!~` are removed; the negation is `not (s =~ /regex/)`.
- **`+-` builds a range.** `b +- t` is the closed range `(b - t)..(b + t)`, so it is also valid elsewhere: `x in b +- t`. It has the precedence of `..`.
- **`=` is the light assignment, for initial values.** It gives the first value of a variable from a data literal: `new a = 5;` (type inferred from the literal), `new a = 0 :Integer;` (explicit type), and the default of a parameter (D-070). It does not change a variable: `let x = 5;` is an error, because the user must not have to choose between `=` and `:=` for the same job; a change uses `:=` (expression) or `::` (clone). When `=` in a declaration is followed by an expression instead of a literal, the compiler warns and treats it as `:=`. `==` stays the equality test.
- **`=` is not an expression.** It returns no value and does not chain: `a = b = 5` is removed (D-017). Several variables in one declaration, preferred form: `new a = 1, b = 2 :Integer;`, the same as `new (a = 1, b = 2) :Integer;` (the type applies to every name). Also valid: one value for all, `new (a, b, c) = 5 :Integer;` or `new (a, b, c) = 1;`; one value each, `new (a, b) = (1, 2);`.
- **Removed:** `repeat N times` (already gone from the tutorial by D-074). The statement suffix `if` stays (`break if c;`, `skip if c;`).
- Applied to the tutorial: syntax.html (literal table, operator list and table, precedence, Initial Value, Several Variables), collections.html (negative indexes, slices, matrix examples, `set (x, y, z) = 2`), classes.html (`set (m, n) = 1`), strings.html (regex operators). The VM and the tests are not changed (D-075).

## D-080 Types: DataMap, Rune, Null and null, Decimal, number suffixes, string append, data-loss warnings (2026-10-05)
Author decision, from the answers to review points RTY-D02, RTY-D03, RTY-D04, RTY-D05, RTY-X01, RTY-X02, RTY-R02, RTY-R03, RTY-R04 and RTY-R07 (`review/03-types-data.md`) and the answers of 2026-10-05. Impact counts are occurrences in the tutorial pages (2026-10-05).
- **`HashMap` becomes `DataMap`** (29 occurrences: collections 16, types 3, classes 2, exceptions, methods, syntax). A DataMap is sorted by key and may nest (a value can be another DataMap or a collection). A literal with quoted keys, `{"key": "value"}`, is a DataMap; this is how Eve parses JSON objects. Empty map `{:}`, type notation `{:}(String, Integer)` unchanged. List stays the only unsorted collection.
- **Objects and records.** A literal with unquoted keys and no record type, `{key: "value"}`, creates an Object: the way to make an implicit object. A record type is declared before use, and a record literal names its type: `new p = {name: "Ann", age: 30} :Person;`.
- **`Symbol` becomes `Rune`** (48 occurrences: types 18, collections 12, syntax 10, strings 6, compiler, template). One Unicode code point on 32 bits, literal `'a'` or `U+0061`.
- **`NIL` becomes `nil`**: the empty rune `''`.
- **`Real` is an IEEE-754 double** (64 bits), stated in the types table.
- **`Logic` stays the name** of the type of `True` and `False` (not Boolean). It is an ordinal type: `False = 0`, `True = 1` (D-058).
- **`Null` is a type, `null` its only value.** Names are case sensitive: `Null` (the type) and `null` (the value) are different names, and Eve has no rule that constants are upper or lower case. `null` means that no object exists: nothing is allocated. `o is Null` tests the type, `o == null` the value. A zero value is not null: the object exists. `0`, `""`, `''` (nil), `()`, `{}`, `[]` are all values, not null. A variable declared without a value gets the zero value of its type (an empty collection for a collection), never `null`. The tutorial phrases "Null DataSet", "Null list", "Null object == {}" become "empty …".
- **Optional types** `T?`: `new age: Integer?;` may hold `null`; a plain `Integer` never does. Described in types.html with examples (new section after Variants).
- **Decimal is in version 1**: an exact base-10 number for money and SQL `NUMERIC`, written with the suffix `d`: `12.50d`. **Rational moves to version 2** (types.html marks its section "planned, version 2").
- **Number suffixes**, on base-10 literals only (`b`, `d`, `f` are also hexadecimal digits, so a hexadecimal literal takes no suffix):

| Suffix | Type | Example |
|---|---|---|
| none | Integer, or Real when the literal has a point | `42`, `3.14` |
| `d` | Decimal | `12.50d` |
| `r` | Real, IEEE-754 double precision | `5r` |
| `f` | Float, IEEE-754 single precision | `1.5f` |
| `b` | Byte | `255b`; `0b` is the Byte zero, `0b0` the binary literal zero |
| `w` | Short (word) | `11w` |
| `n` | Natural | `42n` |
| `z` | Huge: signed integer on 128 bits, the same on every OS (name to confirm) | `-9000000000000000000z` |
- **Strings and `+`.** `"a" + "b"` concatenates two strings and is the same as `"a" <+ "b"` (append) or `"a" +> "b"` (put in front of). Between a string and a number `+` is a compile-time type error (explicit over implicit): `s <+ 1` appends the number converted to a string (`"a" <+ 1` is `"a1"`), `1 +> s` puts it in front (`"1a"`).
- **Conversions do what the developer asked.** `Integer.parse("3.7")` gives `3` with no run-time error: the developer asked for an Integer. In debug mode the compiler (or the VM) reports a warning "possible data loss" with the line. The same holds for `new x = a / b :Integer;`.

- **`Huge`** (name to confirm) is a signed integer on 128 bits (`i128`), the same on every OS, so a script gives the same result on every machine; suffix `z`.
- Applied to the tutorial: types.html (primitive table: Real IEEE-754, Decimal, Huge, Rational planned for version 2; numeric categories; number suffixes; Rune section; zero values; composite table Null row; new section "Null and Optional Types"; data-loss warning of `parse`), collections.html (DataMap, Rune, empty instead of Null), strings.html (Null strings with `String?`, concatenation with `+`, `<+`, `+>`), classes.html (DataMap, `null`, optional `T?`), syntax.html, exceptions.html, methods.html, manifest.html, compiler.html, template.html, `data/collections.json`, `data/types.json`. The VM and the tests are not changed (D-075).

## D-084 Construction: the constructor's result is `@self`; construct up the chain (2026-10-05)
Author decision, from the discussion of `review/focus.md` F2 (review points RSB-D03, RSB-R04). Replaces the constructor form of D-036 (`constructor(@self)(params)`, two parameter lists, which D-029 forbids).
- **The constructor is a subprogram whose result is the new object.** Its result is written in the header like the result of a function (D-028): `constructor(name: String) => (@self) is … return;`. The type of `@self` is the class and is not written. One parameter list: the arguments of the class call `Point(1, 2)`.
- **The construction is the first statement.** `let self := Object();` in a class derived directly from `Object`; `let self := Superclass(arguments);` in a subclass. `self` is empty (like any result before it is set) until then: using it before is a compile error; a missing or second construction is a compile error; `self` can't be replaced afterwards.
- **Construct up the chain.** The object is allocated once, at the root of the chain (`Object()`), and handed down: each superclass constructor returns it, each subclass receives it and initializes its own part. There is no `super` keyword and no `@self` parameter in the constructor.
- **The outermost class call decides the class.** `new c := Circle(…)` starts the construction with the target class Circle; inside the chain, `Shape(name)` and `Object()` build that object instead of a new one, and `Object()` allocates the memory of the target class (all fields, zero values). Outside a constructor, a class call creates a new object as usual. For the VM, every constructor is an ordinary function returning an object; the target class is its one hidden argument.
- **Attributes.** The attributes of the class signature exist after the construction and are set with `let self.x := v;`; an attribute that is not in the signature is created with `new self.extra := v;` (D-076).
- **A class without a constructor** is filled by name, inherited attributes included: `new c := Circle(name: "wheel", radius: 2.5);` (D-063).
- **Methods and the destructor keep `@self` as their parameter**: a method receives the object, the constructor produces it. A chainable method writes `@self` in its result list too, `method add(@self, x: T) => (@self) is … return;`: the result is the object itself, and `return @self;` is not Eve (D-036: `return` carries no value).
- Open (F2 in `review/focus.md`): RSB-D03 also proposed an implicit `self` in methods inside a class body; today `@self` in the parameter list is what tells an object method from a class method.
- Applied: tutorial classes.html (design pattern, notes, object methods, parameters example, new section Construction with the chain step by step and its rules, attributes, the Point example with its methods moved out of the constructor and its output corrected, the tracking example, the inheritance pattern with a superclass filled by name, the abstract class and trait examples, the generic Number class rewritten, method chaining), exceptions.html (class Error), databases.html (constructor of the session), syntax.html (keyword `constructor`), `data/classes.json` (entry Construction; the partials entries now point to Abstract Class and Traits).

## D-085 `generator` keyword; visibility by words; `export`; methods belong to classes (2026-10-05)
Author decisions, `review/focus.md` F1 and F3 (review points RSB-R03, RSB-X02, RSB-X01, RSB-R05). Eve moves towards a hybrid of functional and object-oriented programming: functions become stronger and more prominent, methods bind to classes. Replaces the generator rule of D-067 (a method that contains `yield`), the `.` and `_` prefixes of D-017, D-035 and D-072, and the module-level methods of D-025 and D-042.
- **`generator`** is a keyword: `generator count_to(n: Integer) => (@x: Integer) is … return;`. `yield` is allowed only in a generator; in a function or a method it is a compile error. A generator can belong to a class: `public generator walk(@self) => (@node: Node) is …`.
- **Visibility in a class** is a word in front of the declaration: `public`, `protected` (the class and its subclasses), `private` (the default when no word is written). It applies to methods, generators and class properties. The attributes of the class signature are public. The prefixes `.` and `_` are gone; `!` stays for unsafe functions and methods.
- **`export` in a module**, symmetric to the `use` list of an import: `export (VERSION, Point, square, shift);` lists the members other scripts may use: constants, classes, functions (plain and unsafe), extension methods, channels. A member that is not exported is private. A variable can't be exported.
- **At module level there are functions and extension methods.** A method belongs to a class: declared in its body, or at module (or aspect) level as an extension method, whose first parameter is `@self` with the class type, `method shift(@self: Point, dx, dy: Real) is …`. An extension method can be used only inside the module or aspect that declares it; exported by a module, it can be used by every script that imports the module. Module state is changed by unsafe functions: `function tick!() is … return;` (D-081 said unsafe methods).
- Applied to the tutorial: modules.html (skeleton with `export`, members table, extension methods, no public variables, unsafe functions, the counter example with `tick!` and `count!`, the journal channel, the io library), classes.html (new section Visibility, class properties and methods with `public`/`private`, the examples), exceptions.html (module exception with `export`), topology.html, multitasking.html (generators: declaration, ping/pong, rules; module state), functions.html (closure example renamed `make_counter`, the unsafe method row), methods.html (unsafe methods), syntax.html (prefix tables, keywords `generator`, `export`, `public`, `protected`, `private`, and their meanings), library.html and databases.html (prefixes removed), index.html, `js/eve1.js` and `js/eve3.js` (new keywords, and the types DataMap, Rune, Decimal, Huge of D-080).
- Model readings to confirm: (a) an unsafe function may have no result (`function tick!() is`), which relaxes D-028 ("a function must have a result") for `!` functions; (b) `export` is one list per module, not a word in front of each declaration; (c) reading a variable of a module that can change needs a `!` function (`count!()`), because a plain function is deterministic.
- Open: subprograms that are not in a class and are not in a module, the helper methods of drivers and aspects (the chapter methods.html, examples in processing, topology, types, functions): do they become functions (`!` when they have side effects), as "methods bind to classes" suggests? And `print`, `write`, `read` of the system library: as unsafe functions every call would read `print! x`; proposal: the system library verbs stay statements, outside this rule.

## D-086 Functions with or without result; methods belong to classes; Methods chapter after Classes (2026-10-05)
**Changed by D-100:** a function without result is now a procedure, keyword `procedure`.
Author decision, answers the open points of D-085. Replaces the rule of D-028 "a function must have a result; a subprogram without result is a method", the free methods of D-025, and the meaning of `!` on functions of D-027.
- **Every subprogram outside a class is a function.** The helper methods of drivers, aspects and modules become functions. A method belongs to a class: an object method in its body, or an extension method at module or aspect level.
- **Three kinds of functions.** A plain function has a result and no side effects; it is deterministic and always safe in parallel processing. A function with a result and side effects, or not deterministic, ends with `!`. A **function without result** does work (prints, writes, changes `@` parameters or the state of a module); it needs no `!`, is called as a statement, and its parentheses can be left out when it has no arguments (`foo;`).
- **`print`, `write`, `read`** of the system library are functions without result: no `!`, called as statements, as before.
- **Parallel safety.** A function that changes the state of a module, with or without a result, can't be used by an aspect started in a parallel group; the compiler sees it in the code (refines D-081, which marked such subprograms with `!`).
- **Extension methods are static, not monkey patching.** The class never changes; the compiler resolves an extension method from the declarations and imports of the calling script; only the scripts that declare or import it see it; it can't hide a method of the class (compile error); it sees only the public members of the class. They are safe.
- **Closures** are created by functions: `function make_counter(start: Integer) => (@next!: Function)`.
- **Tutorial order.** Methods move after Classes and are about methods of classes and extension methods: 05 Functions, 06 Modules, 07 Classes, 08 Methods, 09 Collections. The material on side effects and parameters moves from methods.html to functions.html.
- Applied: functions.html (three kinds of functions, new sections Functions without result and Parameters, closures by functions, the subprogram table), methods.html (rewritten: extension methods, where they can be used, static not monkey patching, unsafe methods), modules.html (`tick` and `trace` without `!`, members table, module state), multitasking.html, classes.html, index.html (order), the free methods of databases, processing, topology, types, template and library pages (now functions), syntax.html (`function`, `method` and `!` rows), `data/functions.json`, `data/methods.json`.

## D-087 `!` means non-deterministic; command–query separation; closures and generators (2026-10-05)
**Changed by D-101:** a function that creates a closure always ends with `!`.
Author decision. Refines D-086 and replaces the meaning of `!` on functions of D-027 ("side effects or not deterministic").
- **`!` on a function means one thing: non-deterministic.** Its result can differ for the same arguments: randomness, time, a module variable that changes, a closure that counts. `random!()`, `next!()`, `count!()`.
- **Command–query separation.** A function that returns a result changes nothing (not a global, not a module variable, not its parameters). A function that changes something returns nothing: the function without result of D-086, which needs no `!`. So a function with a result is either plain (deterministic) or `!` (non-deterministic), and both are safe in parallel processing; only functions without result and methods can change state.
- **Closures.** The function that creates a closure is deterministic: for the same arguments it returns an equivalent closure and changes nothing, so it has no `!` (`function make_counter(start: Integer) => (@next!: Function)`). A closure that changes the state it encloses is non-deterministic and its name ends with `!` (`next!`); a closure that always gives the same result needs none.
- **Generators** stay a keyword, `generator`, a kind of function (or of method, in a class). Calling a generator is deterministic and has no `!`: it returns an equivalent generator object; the object is what moves on. A generator is declared where a function or a method can be: in a class with `public` or `private`; in a module, exported with `export` or private; in a driver or an aspect, private to that script.
- `!` on a method keeps its meaning of D-081: the method changes shared state and can't run in parallel.
- Model reading to confirm: a function with a result can't change its `@` parameters (command–query separation); input/output parameters belong to functions without result and to methods.
- Applied: functions.html (the three kinds, notes, closures, subprogram table), modules.html (members table, module state, `count!`), syntax.html (the `!` rows), multitasking.html (where a generator is declared; why it has no `!`).

## D-088 Issue cleanup: names, split of the types page, library functions (2026-10-06)
Housekeeping of `issues/` after D-084 to D-087; applies answers that were clear.
- **Names (IDX-02).** "EVE" is the machine name (the Eve virtual machine, the `eve` command is lower case); "eve" is the language name in file names and commands; "Eve" is written at the beginning of a sentence or a statement. Existing pages are not rewritten wholesale: correct them when a page is revised.
- **Index (IDX-01).** The accepted order of 2026-09-28 is superseded by the order of D-086; Date and Time is topic 04 (below).
- **Types page split (TYP-I2, plan T1.11).** Calendar Date, Time & Duration and Quick Format moved from `types.html` to the new `datetime.html` ("Eve Date and Time", `data/datetime.json`); `types.html` keeps a pointer. The Date proposal (TYP-19, with `era`) still waits for the author's review. The index has 21 topics.
- **Template (TPL-I1, plan T1.8).** `template.html` rebuilt from `functions.html`, title "Eve Language Tutorial".
- **Library page (LIB-03 to LIB-06, D-053, D-057).** library.html now shows `read(@v, prompt)`, `write(*args, sep, eol := False)`, `print(*args, sep, eol := True)`, `error`, `warning`, `log_err`, `log_wrn`, escapes with `&code;`; sections "Standard input" and "Standard output".
- **Fixes applied** from the issue files: classes (comments `**`, `type(x)` in lower case, typos, `<> ` in prose, examples), command, databases, algorithms (`root`, `10^-2`, `abs`), processing, compiler (lexer section follows D-011/D-014/D-019).
- **Conflicts found.** CLS-17 (constructor shape) is settled by D-084; the purity rules of D-027 are replaced by D-087; the conformance table of compiler.html lists three levels while `test/` has seven (CMP-F3); `$CWD` and `$OS_PWD` both still exist (CMD-05).

## D-091 Index in seven phases; Topology and Object Oriented pages split (2026-10-06)
Author decision: reorganize the tutorial into learning phases and split two large pages.
- **Phases (index.html):** 1 Core Language (Manifest, Syntax, Types, Date and Time, Control, Strings, Collections); 2 Topology (Scripts, Drivers, Aspects, Modules); 3 Functional Programming (Functions, Algorithms); 4 Object Oriented Features (Objects, Classes, Inheritance, Generics, Partials, Methods); 5 Enterprise Features (Processing, Exceptions, Databases); 6 System Features (Multitasking, Shell Commands, Server); 7 Implementation & Tools (Compiler, Standard Library, System Library, EVE VM). 29 topics. A credit line follows the table.
- **`classes.html` split** into objects (intro, comparing, object type, attributes), classes (signature, members, visibility, constructor), inheritance (inheritance, class tree), generics, partials (abstract classes, traits) and methods (extension methods, unsafe methods, method chaining).
- **`topology.html` removed**, split into scripts (project, free scripts, regions, constants, process), drivers, aspects, modules (library section added) and vm (configuration, system variables, modes). Links and sidebars are updated; the order of "Read next" follows the index.
- **Free scripts** are described on scripts.html: first line `#!`, sequential statements, no driver, no process, no `return`, no subprograms, no jobs; the script ends at the end of the file (SPEC-03).
- **New pages:** System Library (`syslib.html`: the modules that connect a program to the machine; names are Q-024 in decision_level3.md) and EVE VM (`vm.html`). Standard Library moved to the last phase.
- Not changed: the spec, issues and plan files that still say `topology.html` (the variable register `spec/semantics/variables.md` cites it as a source).

## D-092 Functional programming phase: seven pages (2026-10-06)
Author decision: the phase has the pages Functions, Generators, Closures, Expressions (lambdas), Callbacks, Asynchronous Functions, and Algorithms.
- **functions.html** keeps the declaration, the three kinds, functions without result and parameters; new sections "Calling a function" (in an expression, as a statement, positional and named arguments, recursion) and "Anonymous and self-calling functions" (proposed form `(lambda)(arguments)`).
- **generators.html** moved from multitasking.html (declaration, use, rules, cooperative tasks) with a comparison table and new examples (infinite, reading step by step). multitasking.html keeps a pointer and the parts about threads and channels.
- **closures.html** and **lambdas.html** moved from functions.html. The signature of a callback ("Lambda signature") moved to **callbacks.html**, which is new: the idea, the type of a callback, a callback with a state, rules and patterns.
- **async.html** is new: Eve has no `async` and `await` (D-051, D-067); waiting gives the core away, and `start` in a parallel group is the asynchronous call. Comparison table with languages that have `async`.
- Every new page has **TODO** notes (blue boxes) for the work still to do. The links and sidebars of the other pages are updated.

## Q-025 Anonymous functions, functions inside functions, asynchronous functions (answered 2026-10-06 → D-096, follow-up Q-033)
(a) Is `(lambda)(arguments)` the form of an anonymous self-calling function? May a lambda call itself, and with which word? 
**answer** no, the function that is anonymous can't call itself recoursively. ()(); is correct call of anonymous lambda function. This is why we can't have two sets of parameters for optional parameters and we must use parameter by name instead.
(b) The closure example uses an old body form (`Function() => (@result: Integer):` and two `return;`): what is the current form of a function made inside a function? 
**answer** this is what we need to establish. we invent things here. a function that create other functions is a higher order function formed method factory. So the function created can be a deterministic lambda expression, but usually is a closure. The closure use same syntax as a regular function, it ends with return; if is the last in the parent functions we end up with two returns, one aligned with parent function keyword one with child function keyword (two spaces). This is why in Eve spaces are mandatory. To improve readability and avoid having two returns on the same row. (though this is possible, is not a good practice).

(c) Keep Eve without `async` and `await`, or add asynchronous functions: (1) none, as today; (2) `start` of a function returns a future-like `Result(:T)` read with `.get()`; (3) `async function`, callable only with `start` in a group.
**Answer:**
We design asynchronous functions. We can start asynchronous functions in a driver or in an aspect. Asynchronous functions are not executed in parallel blocks, that would span them over many cores. Asynchronous functions work on the same core. one that is lauched do some work and release the core allow the processor to lauch another function and then wait for all to finish. We use job without "parallel" so a simple job can start asynchronous functions using "start" keyword, but these kind of functions do not return a result. They are result-less and rellay on in/out @params. 

## D-093 Phases: Enterprise and System merged; Internet added; Shell Commands last (2026-10-06)
Author decision. Index phases now: 1 Core Language, 2 Topology, 3 Functional Programming, 4 Object Oriented Features, 5 Enterprise & System Features (Processing, Exceptions, Databases, Multitasking), 6 Internet Features (Templates, Networking, Protocols, Server), 7 Implementation & Tools (Compiler, Standard Library, System Library, EVE VM, Shell Commands). 37 topics.
- **New pages:** templates.html (string templates today; HTML templates, the `Html` type and context escaping: proposed), networking.html and protocols.html (not designed yet: layers, client, server, safety; HTTP, EWP, data formats). Each has "Not designed yet" or "Proposed" notes and TODO boxes; questions Q-027 (templates) and Q-028 (networking, protocols) are in decision_level7.md.
- **Server** moves from System to Internet; **Shell Commands** (command.html) moves to the last phase.

## D-094 Level 1 audit: answers to Q-002 to Q-006, corrections, specification and tests (2026-10-06)
Review of this file by the model, at the author's request: every question checked, every decision compared with the later ones. Applied the answers written in the file (`todo`, `answer`) and rewrote the level 1 specification and tests.
- **Q-002 keywords.** Remove the unused words, add the missing ones, give every word a description. Done in `spec/lexical/keywords.json`: 70 words with category, status, summary and reference. Removed: the 30 words that no example uses (`alter analyze append ascend close cursor delete descend discard fetch group halt into item limit offset open order package pop rollback select store switch trial view where`), `add del reset by case step to with within on label rest result record object cancel commit create insert feature augment external`, `any`. `print`, `read`, `write` are library functions (D-086). Added: `type`, `def`, `set`, `new`, `let`, `from`, `use`, `export`, `public`, `protected`, `private`, `generator`, `trait`, `destructor`, `parallel`, `assert`. `True`, `False` and `null` are constants, not keywords. Words of the levels 2 to 7 (`aspect`, `module`, `apply`, `start`, `parallel`, `yield`, `call`) are reserved from level 1. The tutorial table of `syntax.html` is to be regenerated from this file. The databases words come back with the database level, when a decision gives them a construct.
**answer** we do not need to list all the keywords in a single place. Split the keyword list on phases. So user is not overwelmed with lists in a tutorial. **todo** make a list of keywords in one of first or seconnd page in a phase closer to the articles where the keywords will be explained.
- **Q-003 stray files.** Done: `quiz.txt`, `output.log` and `databases.md` no longer exist in `tutorial/`.
**answer** good I will check
- **Q-004 `global`, `globals`.** Regions are legacy (D-041): the words are not reserved and are retired; `pattern/declaration.eve` keeps them as a legacy sample only.
- **Q-005 expected output.** Replaces `expect.json`: the expectations are comment blocks `/*@expect { json } */` inside the test (standard output, standard error, exit code, syntax error, states). Defined in `spec/conformance/README.md`; `script/runtest.py` reads the blocks (the old `expect.json` is still read, for level 2); `test/level1/expect.json` was removed. Open: the key `state`  (introspection of `jobs`) is planned, not implemented.
- **Q-006 license.** Retired, answered by D-061 and D-078.
- **Corrections of earlier decisions** (each one has a note at its heading): D-010 (`panic` is code 1, not `over 1`), D-016, D-017, D-025, D-027, D-028, D-030, D-032, D-058, D-063 (`abort` runs `finalize`; `new C(args)` replaced; matrix index), D-064, D-065, D-019 (precedence table). The tutorial pattern of the job (`done job [job_name];`, control.html) still contradicts D-034 (`done name;`): to fix in the page.
- **Questions still waiting for the author** (no answer was written when this entry was made; Q-013 to Q-017 were answered afterwards, D-095): Q-018 (backslash in regular expressions), Q-019 (a to i; only the `(x)` point was answered, D-063), Q-025 (anonymous functions, `async`), Q-026 (callbacks). The specification states each of them as *(proposed)* and the tests avoid them (no scientific notation, no lambda, no backslash in patterns).
- **New questions.**
  - **Q-029 `type`, `Type` and `class`.** The tutorial writes `Type Small = (0..1)(0.1) <: Range;` and `Type BinEx = … <: Function;` with a capital T, declares an ordinal with `class Color = {Red, Green} <: Ordinal;`, and the keyword table has no `type`. D-041 names `type` as a one-line declaration. Which spelling, and does an ordinal use `class` or `type`? The spec uses `type` (proposed) and `class` for ordinals.
**answer** I see no scenario where Type can be a keyword. we use "class" instead. When we use Type is not a keyword is a pattern example of any type and it must be replaced with a real type. (Or at least this is what is going to be) At this time these are mistakes. type(x) will return the type of x. For example: x is Type (is a logical expression, like: (x is Integer) will retunr true if x is integer. class Color = {Red, Green} is a short hend for class Color = {Red:1, Green:2} <: Ordinals (Default of ordinals starts from 1) is an exception from the rule that say {a,b} is a DataMap. When we define a class we need to specify the superclass, superclass is mandatory. 

  - **Q-030 unary minus and power.** The precedence table puts unary `-` above `^`, so `-2 ^ 2` is `(-2) ^ 2 = 4`. Most languages give `-4`. Keep the table, or put `^` above the unary minus?
  **answer** Wait what?  4 - 2^2 = 0 ? I agree.  But also (4 == -2^2). So what we do? If there is a term in front of "-" then I agree because - become an operation. But if - is unary It must be apply first. Other languages are all wrong.  What if user say: 4 - -2^2 what is the result of this operation? I say: (4 - -2^2 == 0) you say 8. Who is right?
  - **Q-031 assumptions of the rewritten tests.** (a) `new a, b :Integer;` declares several names without a value;
  - **answer** default value is zero and table of zeros is provided for every tipe.
   (b) `.count()` for collections and `.length()` for strings (D-079 names `count`, the tutorial `length` for strings); 
  **answer** yes correct

  (c) `let 'z' <- m;` and `let m -> 'x';` remove by value, with a rune literal as the value (the tutorial has `let 'z' <- lst;`); 
**answer** replace this feature with a function. collection.delete("x") instead; That will remove an element by value if collection has values or by key. when collection has key value pairs. We do not provide a function to delete by value into DataMap yet.
(d) `new q, r := divmod(17, 5);` takes the several results of a function; 
**answer** correct

(e) `skip outer if …;` continues the outer loop, with the label on a `loop` header (`outer: loop for …`); 
**answer** correct
(f) `pick: match n one … done pick;`; **answer** correct

(g) an unhandled error has code 4 and the message goes to the error output (D-063); 
**answer** correct

(h) a failed `assert` gives the final code 3 (whether it stops the process is open, D-010); 
**answer** is a runtime error, It must stop the process because error code is 3 if unhandled. I agree. Change my tutorial here.
(i) numbers of different numeric types compare by value (`9 / 3 == 3`); 
**answer** possible in Eve. Yes. This is a feature not a bug.

(j) `jobs["j1"].status` is readable after the job; 
**answe** Correct, this is a feature of Eve to organize work in batches and be able to near down the error location my job label. That is a good reason to use jobs in first place. Also parallel blocks are jobs. In the same list of jobs. Now I'm thinking most blocks have labels why not all to be present in jobs[] what if a loop fail and is not in a job, can I see if failed? The only thing is I have not thought so deep yet. We stay with "job" and "paralle" for now.

(k) `new p.z := 7;` adds an attribute to an Object; (l) the interpolation formats of a11 are still the draft of D-060.
**answere** recended, I do not want this feature is not safe. We do not create new properties for objects ourside of objects. We can only access properties of object if they are not private. Private properties of objects and classes are defined inside the class: new self.property is automatic private. In class signature we define public properties Class x:{p:Integer},  p is public. 

- **Specification written** (version 0.1-draft, level 1): `spec/syntax/grammar.md` (EBNF), `declarations.md`, `statements.md`, `expressions.md`; `spec/semantics/control.md`, `errors.md`, `types.md`; `spec/conformance/README.md`; `spec/lexical/keywords.json`; `lexical.md` and the JSON tables brought to D-063 to D-087 (Rune, `nil`, `null`, DataMap, suffixes, `=~` and `+-`, no `!~`, no `.`/`_` prefixes, no `$` index).
- **Tests rewritten**: `test/level1/` has 54 tests (a01 to a54), all in the syntax of D-076 to D-093, expectations in `/*@expect*/` blocks. a25 became "functions without result" (D-086), a06 `new_set_let`, a21 `datamap`; new: a40 extension method, a41 inheritance, a42 visibility, a43 to a48 negative tests (`syntax_error`), a49 `stop`, a50 `exit`, a51 unhandled error, a52 `assert`, a53 `abort`, a54 `panic`. Lambdas, closures, generators and formats are not tested (open questions). Result on the current VM: 17 pass and 37 fail; the VM still reads the syntax of D-036, and a negative test passes there only because every script is refused: the VM must be fixed next, test by test.

## D-095 Lexical answers: exponent, `&` references, Text literal, interpolation format, small rules (2026-10-06)
Author answers to Q-013 to Q-017, applied by the model to `spec/lexical/lexical.md`, `spec/semantics/types.md` and `test/level1/` (a09, a10, a11, a17, a27).
- **Q-013.** `2e-3` and `1.5e3` are valid and always `Real` (double). The digit separator `_` is not accepted. A large number is a string followed by a type suffix: `"1,000,000"z`, `"12.50"d` (the commas are separators; the suffix makes it a number).
- **Q-014.** `&alpha;`, `&#955;` and `&#x3BB;` are valid; the ampersand is `\&` or `&amp;`. `"""…"""` has the type `Text`; the tags `<text>`, `<xml>`, `<html>`, `<data>`, `<code>` also create a `Text` literal. The first and the last line break are removed.
- **Q-015.** The format of an interpolation follows `%`, not `:`: `\#{expr % format}`. The answer says "replace `:` with `&`" and then writes `%`: the model used `%`. `%` is also the remainder, so a remainder inside the expression needs parentheses: `\#{(a % b) % i5}`. Confirm `%` and the parentheses.
**answer** My mistake & I wanted to say %. We do not support expressions inside placeholders at all just variables. We replace # with '\n{}` so % has one meaning in placehoders, it is the format operator. And now # is just used in comments.

- **Q-016.** (b) moot, `!~` is removed. (c) A trailing comma is allowed: `(a, b, c,)`, `(a,)`. (e) Identifiers are ASCII only. (d) The answer says `#` is a title at zero indentation and not an error; the model kept "a `#` that is not in column 1 is an error"; the BOM point (a) is unanswered: confirm both.
**answer** confirmed, Avoid UTF-8 BOM in modern systems, web APIs, build tools, and software repositories. Save files as standard UTF-8 (without BOM) but if there is a BOM ignore it. Is job of formater to remove wrong encodings in the source files. EVE is bit using Unicode operators or Unicode identifiers but Unicode strings are possible. I do not understand the term "column" we do not use that term we ise "indentation" And intentation is 0 spaces, it starts from 0 that is column 1 for you?

- **Q-017.** The answer defends the capture forms (`let list -> new e;`, `new x <- list;`) and does not change them; the side of the list for `+>` is not answered, `x +> lst` stays as written. The sentence "`let list -> e;` is equivalent to `let list -> let e`" would make `e` a new name, while D-077 says an existing name removes by value. 
**answer** the +> and <+ are well documented in tutorial, why don't you look? These operators can add at beginning or end of a list using let. Also  "let list -> e;" is the correct syntax to create an element e, and also modify the list. Even if in fact I suppose to use "let list -> new e" this riggor is not required. e can become a new handler of an existing object and may or may not be prior defined. This kind of exceptions are allowed. If user by mistake use let instead of new with native variable is permited. I have decide this right here. 

Confirm D-077.
**answer** You make me change my mind. I will allow let to change one or more variables in an expression, because "let" for me means enable or allow. This is a powerful mechanism to "implicit" create variables when there is need it and use type inference when is neaded to make the program work and keep expressive simple syntax comprehensive. See answer on Q-17

- Not answered yet: Q-018, Q-019, Q-025, Q-026, Q-029, Q-030, Q-031. *(Update: all but Q-018 answered, applied in D-096.)*

## D-096 Answers of 2026-10-06 applied: placeholders, list arrows, `let`, `class` types, `assert`, unary minus, callbacks, asynchronous functions (2026-10-06)
Author answers written in this file (Q-001, Q-002, Q-019, Q-025, Q-026, Q-029 to Q-031, and the D-095 follow-ups on Q-015 to Q-017), applied by the model to the tutorial first, then to the specification. The tests (`test/level1/`) and the VM are not changed: the list of test changes is in `spec/conformance/README.md`.
- **Placeholders (Q-015, Q-019c).** `\#{}` becomes `\n{}`. A placeholder holds a name, never an expression or a call: `\s{name}`, `\n{count}`, `\b{flag}`; the format follows the format operator `%`: `\n{pi % f8.2}`. `#` is used only in comments. Model readings: an attribute path (`\n{p.x}`, `\n{self.value}`) and a system variable (`\s{$HOME}`) count as names; `\n{` always starts a placeholder, so a line feed followed by a brace is `\n\{`. Examples that inserted a call or a literal now use a variable or `+` (objects, partials, types, strings). Applied to every tutorial page (the copies in `tutorial/demo/` are not changed), `lexical.md`, `delimiters.json`, `types.md`.
- **List arrows (Q-019d, Q-017, Q-031c).** `let x <- lst;` removes the first element into `x`, `let lst -> y;` the last one into `y`; `_` drops it. An arrow never removes by value: `lst.delete(v)` removes the first element equal to `v`, and on a DataMap `delete(k)` removes a key (no delete by value for a DataMap yet). `let a <+ b;` appends; `new a <+ b;` creates a list `a` holding `b` and is an error when `a` exists. `x +> lst` puts `x` in front (as in the tutorial, D-080). Applied: collections.html (Append, Alter a list, the note, the stack), syntax.html, `statements.md`, `expressions.md`, `operators.json`.
- **`let` creates a missing name (Q-017, "Confirm D-077").** One `let` may change several names and creates a name that does not exist, with the type inferred: `let lst -> e;`. `new` before the name stays as the explicit form; `new` on an existing name is an error. Relaxes D-076 ("`let` on a name that does not exist is an error") and D-077 ("every created name is marked by `new`"). Applied: syntax.html (Assign Keywords), collections.html, `statements.md`, `declarations.md`, `keywords.json`.
- **No `type` keyword (Q-029).** User types are declared with `class` and the superclass after `<:` is mandatory: `class Small = (0..1)(0.1) <: Range;`, `class BinEx = (p1, p2: Integer): Integer <: Function;`. `type(x)` is a library function; `x is Integer` tests a type. Ordinals start at 1: `class Color = {Red, Green} <: Ordinal;` is `{Red:1, Green:2}`; in a class declaration `{Red, Green}` is the exception to "plain values in braces are a DataSet". Applied: types.html, callbacks.html, collections.html (Ordinal), `declarations.md`, `grammar.md` (rule `class-shape`, `type-decl` removed), `types.md`, `keywords.json` (`type` removed).
- **Function types and callbacks (Q-026).** The old form with `<:` stays, with `class` (above); a parameter typed with a function class is checked at compile time and a function with another signature is rejected. A named function is passed by name. callbacks.html: the type section, the closure of the state example, a new section "Collections and callbacks" with the methods `each`, `map`, `filter`, `reduce`, `sort` and a complete example (a design proposal, Q-032), rules and patterns. Still open: a method of an object as a callback.
- **Anonymous functions (Q-025a).** `(lambda)(arguments)` is the call of an anonymous function; it can't call itself. This is why a function never has two parameter lists and optional parameters are named at the call. Applied: functions.html (Proposed box and TODO removed), `expressions.md`, `grammar.md` (`primary`).
- **Closures (Q-025b).** A closure is declared like any function, inside its creator, and ends with its own `return;`; the two `return;` lines are told apart by indentation. Model reading: the inner function has the name of the result parameter (`=> (@next!: Function)` and `function next!() … return;`), which makes it the result. Applied: closures.html (counter example, note), callbacks.html. The parameter `start` of `make_counter` was renamed `first`: `start` is a keyword.
- **Asynchronous functions (Q-025c).** A function without result started with `start` in a plain `job` of a driver or an aspect; the functions of a job share its core, one gives it away when it waits; `done name;` waits for all; inputs by value, outputs by `@`. `start` in a `parallel` group still starts an aspect on another core. Applied: async.html (new section and example, compare table), `statements.md`, `keywords.json`.
- **`assert` is an error (Q-031h).** A failed `assert` is a run-time error with code 3: the process goes to `recover` and ends with exit code 3 when it is not recovered. Model reading: the constant becomes `$err_assert` (class `AssertError`) in the table of exceptions, and `$wrn_assert` is removed. Applied: processing.html, exceptions.html, syntax.html, `errors.md`, `statements.md`, `variables.md`, `keywords.json`.
- **Unary minus first (Q-030).** `-2 ^ 2` is `4`; with an operand on its left `-` is the subtraction: `4 - 2 ^ 2` and `4 - -2 ^ 2` are both `0`. The precedence table did not change; the grammar did (`power = unary [^ power]`, it gave `-(2 ^ 2)` before). Applied: syntax.html (Operator Precedence), `expressions.md`, `grammar.md`, `operators.json`.
- **Division by zero (Q-019a).** Always an error, also for Real: no infinity, no NaN; `1\0` is not supported. Applied: types.html (Pitfalls), `expressions.md`.
- **Printing (Q-019b).** `sep` goes between several arguments only; a list given as one argument prints as a list. The tutorial now says `sep` everywhere (syntax.html said `separator`) and library.html takes the defaults of D-063: `","` for `print`, `""` for `write` (it said `" "` for both). Applied: syntax.html, library.html, `statements.md`.
- **Attributes (Q-019h, Q-031k).** Code outside a class can't add an attribute: `new p.z := 7;` is an error. `new self.z := 7;` in a constructor or a method creates a private attribute; the attributes of the class signature are public. Applied: objects.html, `declarations.md`, `expressions.md`, `types.md`.
- **Zero values (Q-031a).** `new a, b :Integer;` gives `0` to both; a table of zero values for every type is in types.html (new section) and `types.md`. Model reading: the zero value of an ordinal is its first value.
- **Confirmed, no change needed:** Q-019e (`g[1, *]` is `g[1][*]`, a row, D-064), Q-019f (`new view := v[a..b]` is a view, `new c :: v[a..b]` a clone; an example was added to collections.html), Q-019g, Q-019i, Q-031b (`.count()`, `.length()`), Q-031d, e, f, g, i, j.
- **Lexical (Q-016).** A BOM is ignored; a formatter removes it. "Column 1" is now "indentation 0" in the tutorial and the spec; an indented `#` is a lexical error. Applied: syntax.html (Encoding, Comment Forms), `lexical.md`, `delimiters.json`.
- **Keywords by phase (answer to D-094, Q-002).** The tutorial no longer has one table of all keywords. syntax.html lists the core keywords (Script Structure, Assign Keywords, Blocks, Statements, Operator Keywords) and a table of where the other phases list theirs; a section "Keywords of this phase" was added to scripts.html (phase 2), functions.html (3), classes.html (4), processing.html (5) and compiler.html (7, only `call`); phase 6 has no keywords. The stale words of the old table (`feature`, `augment`, `pop`, `halt`, `add`, `del` …) are gone. `keywords.json` has 71 words: `type` removed, `exclusive` and `concurrent` (D-090) added. Generated by `temp/kw_tables.py`.
- **Other fixes:** Q-001 (`doc/`, an empty folder, removed); control.html (the job closes with `done [job_name];`, not `done job [job_name];`, D-034; a broken `<code>` tag).
- **New questions:** and Q-033 below.

## Q-032 Collection methods that take a callback (answered 2026-10-06 → D-103)
The answer to Q-026 asks for a design. Proposed in callbacks.html ("Collections and callbacks"): `c.each(action)` (a function without result, returns nothing), `c.map(f)`, `c.filter(test)`, `c.reduce(f, start)` and `c.sort(by)` (`by(a, b)` is True when `a` goes first). All but `each` return a new collection or a value and do not change `c`; on a DataMap the element is a pair and `map`/`filter` keep the keys. Accept, rename or change? Should `sort` sort in place instead (a method that changes the list returns nothing, D-087)? And can a method of an object be passed as a callback (`obj.method`)?
Blocks: callbacks.html, `library/builtins.md`.
**answer** Too many questions here. 

## Q-033 Readings to confirm after D-096 (2026-10-06; a answered → D-103, b moot → D-102)
Each point is a model reading applied in D-096; say yes or correct it.
(a) A placeholder may hold an attribute path and a system variable (`\n{p.x}`, `\s{$HOME}`), not only a plain variable.
(b) `\n{` always starts a placeholder; a line feed followed by a brace is written `\n\{`.
(c) Asynchronous functions: is any function without result allowed after `start` in a job, or is it marked in its declaration? When one of them fails, do the others finish before the process goes to `recover`?
(d) A closure becomes the result because it has the name of the result parameter (`@next!` and `function next!()`).
(e) `let` creates a missing name in every `let` statement (`let y := 5;` with no `y`), or only on the right side of a capture (`let lst -> e;`)?
(f) The zero value of an ordinal is its first value.
(g) May the shorthand omit the superclass, `class Color = {Red, Green};`, or is `<: Ordinal` required as for every class?
(h) A failed `assert` has the constant `$err_assert` and the class `AssertError` (it was the warning `$wrn_assert`).
(i) `lst.delete(v)` removes the first element equal to `v` (`-=` removes all of them).
(j) The default `sep` of `print` is `","` and of `write` `""` (D-063); library.html said `" "` for both.

## D-097 Regex literal: a string that starts with `/` keeps its backslashes (2026-10-06)
Author decision, answers Q-018 with option (b), chosen after the model pointed out that routes and paths also start with `/`.
- **Rule.** Every string literal whose first character is `/` is a regex literal: raw, the backslashes are kept (`"/\sis\s/"`), no escape sequences and no placeholders (`\s{2}` is a pattern, not a placeholder); the only escape is `\"`.
- **It is a String.** The rule is lexical. A regex literal can be stored, passed and concatenated with ordinary strings; the right operand of `=~` is a pattern when its value starts with `/`, also when built by concatenation. Only the literal that starts with `/` is raw: `"/\s" + word + "\s/"`.
- **Paths and routes** that start with `/` follow the same rule: a value is inserted by concatenation (`"/data/" + name + ".csv"`), and `{id}` in a route stays text. A route given as a regular expression is possible (author: "why not?"); its rules are not designed yet.
- Applied: tutorial strings.html (Regular Expressions: the rule, a built pattern, a path), syntax.html (String Delimiters, Escape Sequences), server.html (note on paths); spec `lexical.md`, `types.md`, `expressions.md`, `index.md`, `conformance/README.md` (a28 may now use backslashes). No demo uses a pattern or a string that starts with `/` (only a comment in `demo/shared_state.eve`), so `demo/` and `tutorial/demo/` are unchanged. Tests not changed.

## D-098 Tests brought to D-096 and D-097 by static analysis (2026-10-06)
Author request: fix the existing tests without running the VM. A survey script looked for every form that D-096 and D-097 changed; the fixes are `temp/fix_level1_d096.py` and `temp/fix_level2.py`.
- **Level 1.** `\#{…}` became `\n{…}` in every test; a11 puts its expressions in variables (`\n{sum}`, `\n{big % ,i9}`); a05 uses `sep:` and prints a list as one argument; a07 checks the unary minus (`-2 ^ 2 == 4`, `4 - -2 ^ 2 == 0`); a16 counts the ordinals from 1; a17 uses `m.delete('z')` and the capture `let m -> last;`; a22 no longer adds an attribute from outside; a28 uses backslashes in regex literals, a built pattern and a path; a37 divides a Real by zero; a52 checks that `assert` stops the process (code 3, the line after it never prints). a43 became `a43_let_creates_name` (positive: `let lst -> e;` creates `e`); a55 `attribute_outside` is new (negative: `new p.z := 7;`).
- **Level 2** was still in the syntax of D-036 and D-072. Now: modules with `export (…)` and no `.` prefixes; `set` and `new` declarations; `let` for every change; `function tick()` and `function count!()` (D-087), so the drivers read `counter.count!()` into a variable before a placeholder; every aspect is `exclusive aspect` (D-090); the extension method is `method shift(@self: Point, …)`; the constructor is `constructor(…) => (@self)` with `let self := Object();` (D-084); `Point(1, 2)` without `new`. The line numbers that b15 expects did not move.
- **Expectations.** The `expect.json` of every level 2 folder moved into a `/*@expect*/` block at the end of its driver, `note` included; the empty `test/level2/expect.json` was removed (answer to Q-005: `expect.json` does not scale). The runner still reads `expect.json` (legacy), but no test uses it; `test/vm/expect.json` (tests of the VM, not of the language) is unchanged.
- `status.json` and the lists in `readme.md` were synchronised by `runtest.update_status([], "-")`, which reads the files and runs nothing. `test/readme.md`, `test/level2/readme.md` and `spec/conformance/README.md` describe the change.

## D-099 `demo/` retired: every demo has a home (2026-10-06)
Author decision: `demo/` was spent into `tutorial/demo/` and `test/`; it is no longer needed. Replaces D-075 for the demos ("kept as ideas"). A static comparison of the 45 demos with the tests and the tutorial found eight demos whose feature no test had; they became the new tests a56 to a63, in the current syntax. Two demos stay with the tutorial because the spec has not decided their feature yet (Date and Time, the operator `as`).

| Demo | Home now |
|---|---|
| assign_demo | a06, a23, a46 |
| class_point | tutorial/demo/class_point.eve, a26 |
| comment_demo | a02 |
| compare_strings | a08, a10 |
| date_demo, time_demo | tutorial datetime.html (no test: Date, Time and `as` are not decided) |
| domain_demo, numeric_range | **a63_range_domain** |
| explicit_coercion, string_to_number | **a57_conversion** |
| expression_demo | a05, a07 |
| fibonacci | tutorial/demo/fibonacci.eve, **a56_recursion** |
| function_params | a24 |
| hello_world | tutorial/demo/hello_world.eve, a03 |
| implicit_coercion, print_type, type_check | a07 |
| list_concat, list_join | a17 |
| list_iteration, while_demo | a13, a14 |
| list_split, test_string, unicode_text, string_concat | a10 |
| map_init_demo, map_iteration | a21 |
| method_call, test_args | **a60_process_args** |
| multi_line | **a62_multi_line** |
| null_strings | **a59_optional_null** (rewritten to D-080: no null string, `String?` holds null) |
| number_to_string | a47 |
| numeric_literals | a09 |
| object_comparison | a22, a26 |
| output_params | a25 |
| over_demo | a30 |
| recover_demo | a31, a37 |
| set_demo, set_operations | a20 |
| shared_state | a28 (`=~` with a tolerance); writing `$epsilon` is open (variables.md, point 6) |
| symbol_range | **a58_rune_range** |
| syntax_elements | a01 |
| text_literal | a27 |
| variant_params, variant_type | **a61_variant** |

- References updated: CLAUDE.md, plan/README.md, plan/phase-5-conformance.md (S5.3), tools/TODO-vscode-plugin.md, the example of `script/multiedit.py`, `spec/conformance/README.md` (coverage table). Old decisions, reviews and issues that mention `demo/` are history and are not changed.
- **Not done yet:** deleting the folder. It is ready: `git rm -r demo` removes the 45 files (they stay in the history).

## D-100 A subprogram without result is a procedure (2026-10-06)
Author decision, after Ada: "functions that do not return a result are procedures". Replaces the "function without result" of D-086 and D-087; the rest of D-086 and D-087 stays (plain function, `!` function, command–query separation). The author will define asynchronous procedures and asynchronous functions later.
- **Keyword `procedure`.** `procedure name(parameters) is … return;` declares a subprogram outside a class that has no result; it does work (prints, writes, changes `@` parameters or the state of a module), is called as a statement, needs no `!`, and its parentheses may be left out when it has no arguments (`foo;`). `function` now always has a result, `=> (@r: T)`. A `function` without a result list and a `procedure` with one are compile errors.
- **Library.** `print`, `write` and `read` are procedures.
- **Asynchronous work.** What async.html called an "asynchronous function" (Q-025c) is an asynchronous procedure, started with `start` in a plain job. The section is marked as waiting for the author's details.
- **Applied, tutorial.** 30 declarations renamed by `temp/procedures.py` (pages, `tutorial/demo/`, tests); prose of functions.html (intro, phase 3 keyword table with the new row `procedure`, the two kinds of functions and procedures, notes, section "Procedures", id `#procedures`, subprogram table), callbacks.html (the `each` action is a procedure; the closure of the state example is `procedure report` and its type `Reporter = (done: Integer) <: Procedure`), async.html (section "Asynchronous procedures", id `#async-procedures`), modules.html (members table, module state), library.html, syntax.html (`print` is a procedure; `is` ends `procedure p is`), classes.html, multitasking.html (thread safety of every subprogram), index.html, the sidebars, and the highlighters `js/eve1.js` and `js/eve3.js`.
- **Applied, spec.** `declarations.md` (section "Functions and procedures"), `statements.md`, `grammar.md` (rule `procedure`; `function` requires its results), `types.md` (type `Procedure`), `errors.md`, `control.md`, `keywords.json` (73 words with `procedure`).
- **Applied, tests.** a25 renamed `a25_procedure`; new negative test a64 `function_without_result`; the counters of level 2, a60 and a61 declare procedures.
- **New questions:** Q-034 below.

## Q-002 evidence (2026-10-02, script temp/kw_usage.py)
The table of syntax.html has 111 words (the text says 113 in D-046). Found in the examples (demo, pattern, test, code blocks of the tutorial): `external` (D-056) is used and is **not** in the table. 30 words of the table are never used: `alter analyze append ascend augment close cursor delete descend discard exit fetch group halt into item limit offset open order package pop rollback select store switch trial view where xor`. Most belong to databases or to ideas that were dropped. Words that are probably library methods now, not keywords: `print`, `read`, `write`, `raise`, `expect`, `add`, `del`, `pop` (D-053, D-055, D-060). Question: which of these are reserved in 0.1 (listed as `reserved`, unused), which are removed, and which are methods?
Blocks: S2.4 (`keywords.json`).

## Q-034 Procedures: points to confirm (answered 2026-10-06 → D-101)
Model readings applied in D-100; say yes or correct them.
(a) The type of a procedure is `Procedure`, as `Function` is the type of a function; a procedure signature is `class Reporter = (done: Integer) <: Procedure;`, and a callback without result, such as the action of `each`, is a procedure.
(b) Methods keep one keyword, `method`, with or without a result. Or should a class also tell them apart (as Ada does with its primitive operations)?
(c) A procedure never ends with `!` (`!` marks a result that can differ); `procedure p!()` is a compile error.
(d) A closure without result is a procedure declared inside a function (`procedure report(done: Integer) is` inside `every`).
(e) Can a procedure be a closure returned by another procedure, or only by a function (a procedure has no result to return it in)?

## D-101 Answers to Q-034: no procedure references, closures are functions (2026-10-06)
Author answers to Q-034, applied to the tutorial and the specification.
- **(a) No references to procedures.** Eve holds no pointers to procedures, has no procedure callbacks and declares no subtypes of procedures: a procedure can't be passed, stored or returned, and the type `Procedure` of D-100 is removed. A callback is always a function. callbacks.html: a note says so; the state example is now a closure function, `function every!(n) => (@due!: Due)` with `class Due = (): Logic <: Function;`, and the receiver `procedure load(rows, due!: Due)` prints; the collection method `each` is dropped from the proposal (Q-032): work done for every element is a procedure called in a `for` loop, and the orders example does that.
- **(b) Methods unchanged.** A method belongs to a class and may have a result or not; the keyword stays `method`.
- **(c) A procedure never ends with `!`.** It is made for side effects and is never deterministic; `procedure p!()` is a compile error (new negative test a65).
- **(d) Only functions create closures, and a closure is a function.** A function that creates a closure always ends with `!` (`make_counter!`), even when it could be called deterministic: these higher-order functions are not optimized. Replaces the rule of D-087 "the function that creates a closure is deterministic and has no `!`".
- **(e) A procedure can create closures** and give them out through `@` output parameters; the closures are functions. closures.html has a new section "Closures from a procedure" (`procedure make_pair(first, @up!, @down!)`, two closures that share one counter), which also closes the TODO "several closures that share one variable".
- Also fixed: the rename script of D-100 missed headers whose parameters hold `()` (`procedure each(items: ()Integer, …)` in callbacks.html) and the library signatures that end with `;` (`error`, `warning`, `log_err`, `log_wrn` in library.html): they are procedures now.
- Applied, spec: `declarations.md` (procedures without `!`, no references to procedures, closures), `grammar.md`, `types.md` (`Procedure` removed), `conformance/README.md`.

## D-102 Placeholders are `{name}` and `{name % format}`; literal braces are escaped (2026-10-06)
Author decision, to stop the errors that the placeholders with a letter caused (`\n{` against the line feed `\n`, `\s{` against the regex class `\s`). Replaces the forms `\s{name}`, `\n{name}` and `\b{name}` of D-096 (which replaced `\#{expr:format}` of D-060).
- **One form.** `{name}` inserts the value of a name, written by its type (a string as it is, a number in digits, a boolean as True or False); `{name % format}` adds a format, whose codes depend on the type. A placeholder holds a name only, as in D-096: a variable, a constant, a system variable (`{$HOME}`) or an attribute path (`{p.x}`, Q-033a).
- **Braces are escaped.** In a string every unescaped `{` opens a placeholder; a brace that does not open a valid one (`"{1, 2}"`, `"{}"`) and a lone `}` are lexical errors. A literal brace is `\{` or `\}`. `\u{…}` stays an escape. The text literal and the regex literal are raw: no placeholders, no escape for braces (`"/\d{3}/"` keeps its count).
- **Static check.** `temp/check_placeholders.py` reads every string of the tests, of `tutorial/demo/` and of the code blocks of the tutorial, and reports a brace that does not open a valid placeholder: 0 problems after the change. The scan found one string with literal braces, `"I can write Greek: {α,β,γ,δ}"` in strings.html, now escaped.
- **Applied, tutorial.** 121 placeholders converted by `temp/d102_convert.py` (pages, `tutorial/demo/`, which still had `\#{…}`, and tests); prose of strings.html (table, rules, the formats by type, the note on raw literals, the older forms), syntax.html, types.html, templates.html (the HTML templates already used `{o.id}`), datetime.html, command.html.
- **Applied, spec.** `lexical.md` (Interpolation, escapes, lexical errors), `types.md`, `delimiters.json` (one item `placeholder` instead of three), `operators.json` (`%`), `conformance/README.md`.
- **Tests.** a11 checks an escaped brace next to a placeholder (`"both = \{{n}\}"` gives `both = {42}`); new negative test a66 `bad_placeholder`.

## D-103 Collection methods confirmed; methods are not values; functions in a class; placeholders select members (2026-10-06)
Author answers to Q-032 and Q-033 (a).
- **Q-032 confirmed.** The collection methods `map(f)`, `filter(test)`, `reduce(f, start)` and `sort(by)` take a function as callback and return a new collection or a value; there is no `each` (D-101). callbacks.html loses its "Proposed" box and the TODO.
- **Methods are not values.** A method can't be handled like a function: no references to methods, no method type; it is never passed, stored or returned, and never a callback. The work of a method is given as a callback through a lambda that calls it: `shapes.map((s) => (s.area()))`. This answers the open point of Q-026 (`obj.method` as a callback). With D-101, only functions are values.
- **Functions in a class.** A class body may declare functions, and its methods may use lambda expressions. They are private to the class and never exported. A class can't host procedures (author correction, same day): a `procedure` in a class body is a compile error. classes.html has a new section "Functions in a class" (`Circle` with a local `square`), methods.html a note, `declarations.md` two rules.
- **Q-033 (a) answered.** A placeholder selects a member with `.` and `[]`: `{p.x}`, `{a[1]}`, `{a[-1]}`, `{a[i]}`, `{m[key]}`, and a part by a range, `{a[2..4]}`; no operators, no calls, no other expression. An index is an integer, a name, a quoted key or a range; the quotes of a key are escaped, `{m[\"key\"]}`, as every double quote inside a string is (author correction, same day). Applied: strings.html, `lexical.md` (grammar `member`, `index`, `bound`; the open point is closed), a11 (`{lst[2]}`, `{lst[-1]}`, `{lst[2..3]}`), `temp/check_placeholders.py`.
- Q-033 (b) is moot after D-102 (no `\n{`). The points (c) to (j) of Q-033 are answered in D-104.

## Q-017 Operators `+>` and `<+`: which side is the list (answered 2026-10-07 → D-095, D-107)
D-060 gives `q <+ x` (append at the end), `s -> let e;` and `let e <- q;`. For the insert at the start, the old examples write `queue +> "x"` (list on the left) while the arrow suggests the element goes to the start of the list on the right. Proposal: `x +> lst` inserts `x` at the start of `lst`; `lst <+ x` appends at the end; `a <+ b` concatenates (b after a). Confirm the side of the list for `+>`.
Blocks: `operators.json` (`prepend`), `syntax/expressions.md`.
**answer** I do not see the problem. `let list -> e;` is equivalent to "let list -> let e";  or alternative `let list -> new e;` is a new syntax that enable me to extract from a collection last element (left element) but right element is very straight forward "new x <- list" has a secondary effect list is loosing an element. 

## D-104 Answers to Q-033 (c) to (j): async, spawn, await; let in a loop; ordinals (2026-10-07)
Author answers to Q-033, recorded in `plan/Q-033.md`.
- **(c) Asynchronous subprograms.** Keyword `async` declares an asynchronous function or procedure. In a job, `spawn f(args);` starts it as a task and the job goes on; `await f(args);` starts it and waits for it at once, in serial mode. A job is split into tasks; the tasks of a job share its core and give it away when they wait; the `done` of the job waits for every spawned task. `start` stays for aspects in a `parallel` group (several cores). Replaces "no `async` and `await`" of D-051 and D-067; `suspend` is still not used. Applied: async.html, `statements.md`. Open points are in Q-035 below.
- **(d) Confirmed.** A closure becomes the result because it has the name of the result parameter (`@next!`, `function next!()`).
- **(e) `let` creates a missing name only on the right side of a capture** (`let lst -> e;`), not in every `let` statement (`let y := 5;` with no `y` is an error). Reason: in a loop, `new` would make a new thing each turn and the same thing would overwrite the previous one. With a capture in a loop the name `e` is created at the first turn and exists in the next ones: it is assigned, not created again. Usually `e` is declared before the extraction. If `e` is a native variable its value is overwritten; if it is a reference, the reference is changed and the old object is counted for removal (zap) at the end of the scope.
- **(f) Confirmed.** The zero value of an ordinal is its first value.
- **(g) `<: Ordinal` is required** for the shorthand too; the shorthand only means that the first value is not assigned, so it is 1. A value that starts with an upper-case letter leaves the class: once the class is imported with `import Color(*)`, its values are public and are constants of the importing scope, used as `Red`, not `Color.Red`. Already in `declarations.md`, `lexical.md`, `types.md`.
- **(h) Confirmed.** A failed `assert` has the constant `$err_assert` and the class `AssertError`; `$wrn_assert` is gone.
- **(i) `lst.delete(v)` removes every element equal to `v`**, like `-=` (`statements.md`).
- **(j) Defaults of `sep`:** `","` for `print`, `""` for `write` (D-063). library.html already said so; the signatures of `io` in modules.html were fixed to agree.

## D-105 Tutorial: Subprograms page with Procedures, end of phase 2; mandatory before optional (2026-10-07)
Author requests, applied to the tutorial.
- **Subprograms (topic 12, end of phase 2).** New page `subprograms.html`: Eve says "subprogram", never "subroutine"; the kinds (procedure, function, generator, method), parameters and arguments, by value, by reference (`@`), optional, vararg, order, result parameters. The parameter rules were removed from `functions.html` (sections Formal parameters, Function arguments, Parameters, Subprograms compared) and are in one place.
- **Order rule.** Mandatory parameters come first, optional parameters follow; a mandatory parameter after an optional one is a compile error. Optional parameters may still follow a vararg (D-029). Applied: `subprograms.html`, `declarations.md`; the example `add` now has mandatory `p1, p2`.
- **No procedural phase.** A separate phase "Procedural Programming" would have one page, so Subprograms is the last page of phase 2, renamed "Eve Code Topology" (index.html, syntax.html). `procedure` is listed in the keyword table of scripts.html. The page ends with an h2 "Procedures" with h3 subsections: the procedure is inherited from the procedural paradigm, but Eve does not use the original design (procedures combine with functions, hold state and can be asynchronous, so pure procedural programming can't be demonstrated). The section Procedures moved out of `functions.html`. Phases keep their numbers 1 to 7; topics 12 to 37 become 13 to 38.
- Asynchronous procedures and functions stay with async.html; they are not explained on the new pages.
- **Order rule replaced by D-106** (Q-036): a mandatory parameter may follow an optional one, but the call names it.
