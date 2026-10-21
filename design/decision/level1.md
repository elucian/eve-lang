# Decisions, level 1: project and single script

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. When a question is answered, turn it into a decision with the date and keep the question text for history. Plan steps reference these ids. **Read cheaply:** `python script/plan.py list` prints every id; `python script/plan.py show D-087` prints one entry from here or from `archive/` (settled entries, full text); `python script/plan.py status` lists what is open.

- D-001 Specification formats
- Q-001 Fate of `docs/` (answered 2026-09-28 → D-004)
- D-002 Tutorial stays in the scl repo
- Q-002 Canonical keyword list (answered 2026-10-06 → D-094)
- Q-002 evidence
- D-003 Many compilers, one specification
- Q-003 Stray files in the tutorial folder (answered 2026-10-06 → D-094)
- D-004 `docs/` becomes `manual/`, the compiler manual
- Q-004 `global` or `globals` (answered 2026-10-06 → D-094)
- D-005 The manual documents the first Eve compiler, not yet built
- Q-005 Expected-output convention for tests (answered 2026-10-06 → D-094)
- D-006 First implementation: an Eve VM written in Zig
- Q-006 Specification license (answered 2026-10-06 → D-061, D-078)
- D-007 `code/evevm/` source, `bin/eve.exe` official implementation
- Q-007 Which implementation does `manual/` document? (answered 2026-09-28 → D-005)
- D-008 Shebang line
- Q-008 Implementation language and name of the first compiler (answered 2026-09-28 → D-006, D-007)
- D-009 Test runner and test-driven workflow
- Q-009 Name and repository of the Eve VM (answered 2026-09-28 → D-007)
- D-010 Process exit codes
- Q-010 Exit codes of an Eve process (answered 2026-09-28 → D-010)
- D-011 Comments
- D-012 Identifiers and the driver header
- Q-012 How does an enclosed function use method state? (answered 2026-09-30 → D-027)
- D-013 Not-equal is `<>`; `!` marks unsafe operations
- Q-013 Numbers: scientific notation and digit separators (answered 2026-10-06 → D-095)
- D-014 Comments: nesting, expression comments, file header
- Q-014 Strings: `&name;`, text literal (answered 2026-10-06 → D-095)
- D-015 Declaration headers end with `is`
- Q-015 Interpolation: end of the expression (answered 2026-10-06 → D-095)
- D-016 Control-flow blocks
- Q-016 Small lexical rules (answered 2026-10-06 → D-095)
- D-017 Assignment, visibility, unsafe calls, shift operators
- Q-017 Operators `+>` and `<+`: which side is the list (answered 2026-10-07 → D-095, D-107)
- D-018 Test file names use `_`
- Q-018 Regular expressions and the backslash (answered 2026-10-06 → D-097)
- D-019 Lexical rules: escapes, identifiers, `**`, precedence
- Q-019 Assumptions of the level 1 tests a04 to a37 (answered 2026-10-06 → D-096)
- D-020 Jobs without handlers; `recover` decides
- D-021 Indexing is 1-based
- D-022 Ranges: exclusive ends, postfix step, slices use `..`
- D-023 Arrays from ranges use the builder only
- D-024 Cartesian product is `><`
- D-025 No routines: a method is any subprogram with side effects
- Q-025 Anonymous functions, functions inside functions, asynchronous functions (answered 2026-10-06 → 
- Q-026 Callbacks and collection operations (answered 2026-10-06 → D-096, D-103)
- D-027 Functions with side effects or randomness end with `!`
- D-028 Functions: results, defaults, arguments, lambda
- D-029 One parameter list; parameters after a vararg are named
- D-030 Control page answers
- D-032 Types page answers
- Q-032 Collection methods that take a callback (answered 2026-10-06 → D-103)
- D-033 Loops close with `done`; no `repeat`, no plain loop; `cycle`
- Q-033 Readings to confirm after D-096
- D-034 Closers: `done label;`
- Q-034 Procedures: points to confirm (answered 2026-10-06 → D-101)
- D-036 `let` declares, `:=` mutates, `new` calls a constructor
- Q-036 Where does an `@` parameter go? (answered 2026-10-07 → D-106)
- D-037 `end name;` closes a class and a module
- D-038 `over;` has no code; process parameters and globals
- D-039 Traits, abstract classes, partial methods [open]
- D-040 Parameters belong to the main process; the process is indented
- D-041 One scope: no import, alias, constant, global or variable regions
- D-044 Issue files and keyword table cleaned
- D-045 `repeat` replaces `cycle`; `repeat N times`
- D-048 `@` passes by reference, at the declaration and at the call
- D-049 `::` is the only clone; no `clone` keyword; slices by `:=` are views
- D-054 Exceptions page, `$err_` and `$wrn_` constants
- D-058 Collections answers: ordinals, literals, sets, maps, strings
- D-059 Collections follow-ups; one interpolation form
- D-060 Interpolation escapes `\s{}` `\#{}` `\b{}`; queue direction
- D-061 Licenses: BUSL-1.1 for code, CC BY 4.0 for the specification
- D-062 Trademark policy
- D-063 First execution of level 1: what running the tests taught
- D-064 Matrix and tensor indexes: `[x, y]` is `[x][y]`
- D-065 `demo/` is temporary
- D-069 Methods page; Multitasking after Classes
- D-070 Default values of parameters
- D-074 Loop tested at the end: `loop … do … repeat [while c];`; `skip`
- D-075 Mission, role of the tutorial, demos kept (2026-10-04)
- D-076 `new` declares, `let` executes, a class call constructs
- D-077 Inline `new`: one statement changes a variable and creates another
- D-078 CC BY-NC-SA 4.0 for the specification and the documents; mission
- D-079 Last element `[-1]`, approximate match `=~`, range `+-`, light assignment `=`
- D-080 Types: DataMap, Rune, Null and null, Decimal, number suffixes, string append, data-loss warning
- D-084 Construction: the constructor's result is `@self`; construct up the chain
- D-085 `generator` keyword; visibility by words; `export`; methods belong to classes
- D-086 Functions with or without result; methods belong to classes; Methods chapter after Classes
- D-087 `!` means non-deterministic; command–query separation; closures and generators
- D-088 Issue cleanup: names, split of the types page, library functions
- D-091 Index in seven phases; Topology and Object Oriented pages split
- D-092 Functional programming phase: seven pages
- D-093 Phases: Enterprise and System merged; Internet added; Shell Commands last
- D-094 Level 1 audit: answers to Q-002 to Q-006, corrections, specification and tests
- D-095 Lexical answers: exponent, `&` references, Text literal, interpolation format, small rules
- D-096 Answers of 2026-10-06 applied: placeholders, list arrows, `let`, `class` types, `assert`, unary
- D-097 Regex literal: a string that starts with `/` keeps its backslashes
- D-098 Tests brought to D-096 and D-097 by static analysis
- D-099 `demo/` retired: every demo has a home
- D-100 A subprogram without result is a procedure
- D-101 Answers to Q-034: no procedure references, closures are functions
- D-102 Placeholders are `{name}` and `{name % format}`; literal braces are escaped
- D-103 Collection methods confirmed; methods are not values; functions in a class; placeholders select
- D-104 Answers to Q-033 (c) to (j): async, spawn, await; let in a loop; ordinals
- D-105 Tutorial: Subprograms page with Procedures, end of phase 2; mandatory before optional
- D-106 Order of parameters: a mandatory parameter after optional ones is named at the call
- D-107 The list stays after `+>` and before `<+`
- D-108 Date, Time and `as` are outside level 1
- D-109 Error codes, system variables, lambdas and closures
- D-110 Eve is a compiler: names and types are checked before the run
- D-111 `exit` leaves the current subprogram or process; `over` ends the whole process
- D-115 Grammar checked against the examples (S3.6, 2026-10-08)
- D-116 Prefer contextual keywords to reserved keywords
- D-117 Answers to Q-037: syntax points found by the grammar check
- D-118 A scalar operator applies to every element of a List or Array
- D-120 A placeholder holds a name or any literal; its quotes are not escaped
- D-121 Simple expressions in placeholders

- D-001 Specification formats
- Q-001 Fate of `docs/` (answered 2026-09-28 → D-004)
- D-002 Tutorial stays in the scl repo
- Q-002 Canonical keyword list (answered 2026-10-06 → D-094)
- Q-002 evidence
- D-003 Many compilers, one specification
- Q-003 Stray files in the tutorial folder (answered 2026-10-06 → D-094)
- D-004 `docs/` becomes `manual/`, the compiler manual
- Q-004 `global` or `globals` (answered 2026-10-06 → D-094)
- D-005 The manual documents the first Eve compiler, not yet built
- Q-005 Expected-output convention for tests (answered 2026-10-06 → D-094)
- D-006 First implementation: an Eve VM written in Zig
- Q-006 Specification license (answered 2026-10-06 → D-061, D-078)
- D-007 `code/evevm/` source, `bin/eve.exe` official implementation
- Q-007 Which implementation does `manual/` document? (answered 2026-09-28 → D-005)
- D-008 Shebang line
- Q-008 Implementation language and name of the first compiler (answered 2026-09-28 → D-006, D-007)
- D-009 Test runner and test-driven workflow
- Q-009 Name and repository of the Eve VM (answered 2026-09-28 → D-007)
- D-010 Process exit codes
- Q-010 Exit codes of an Eve process (answered 2026-09-28 → D-010)
- D-011 Comments
- D-012 Identifiers and the driver header
- Q-012 How does an enclosed function use method state? (answered 2026-09-30 → D-027)
- D-013 Not-equal is `<>`; `!` marks unsafe operations
- Q-013 Numbers: scientific notation and digit separators (answered 2026-10-06 → D-095)
- D-014 Comments: nesting, expression comments, file header
- Q-014 Strings: `&name;`, text literal (answered 2026-10-06 → D-095)
- D-015 Declaration headers end with `is`
- Q-015 Interpolation: end of the expression (answered 2026-10-06 → D-095)
- D-016 Control-flow blocks
- Q-016 Small lexical rules (answered 2026-10-06 → D-095)
- D-017 Assignment, visibility, unsafe calls, shift operators
- Q-017 Operators `+>` and `<+`: which side is the list (answered 2026-10-07 → D-095, D-107)
- D-018 Test file names use `_`
- Q-018 Regular expressions and the backslash (answered 2026-10-06 → D-097)
- D-019 Lexical rules: escapes, identifiers, `**`, precedence
- Q-019 Assumptions of the level 1 tests a04 to a37 (answered 2026-10-06 → D-096)
- D-020 Jobs without handlers; `recover` decides
- D-021 Indexing is 1-based
- D-022 Ranges: exclusive ends, postfix step, slices use `..`
- D-023 Arrays from ranges use the builder only
- D-024 Cartesian product is `><`
- D-025 No routines: a method is any subprogram with side effects
- Q-025 Anonymous functions, functions inside functions, asynchronous functions (answered 2026-10-06 → 
- Q-026 Callbacks and collection operations (answered 2026-10-06 → D-096, D-103)
- D-027 Functions with side effects or randomness end with `!`
- D-028 Functions: results, defaults, arguments, lambda
- D-029 One parameter list; parameters after a vararg are named
- D-030 Control page answers
- D-032 Types page answers
- Q-032 Collection methods that take a callback (answered 2026-10-06 → D-103)
- D-033 Loops close with `done`; no `repeat`, no plain loop; `cycle`
- Q-033 Readings to confirm after D-096
- D-034 Closers: `done label;`
- Q-034 Procedures: points to confirm (answered 2026-10-06 → D-101)
- D-036 `let` declares, `:=` mutates, `new` calls a constructor
- Q-036 Where does an `@` parameter go? (answered 2026-10-07 → D-106)
- D-037 `end name;` closes a class and a module
- D-038 `over;` has no code; process parameters and globals
- D-039 Traits, abstract classes, partial methods
- D-040 Parameters belong to the main process; the process is indented
- D-041 One scope: no import, alias, constant, global or variable regions
- D-044 Issue files and keyword table cleaned
- D-045 `repeat` replaces `cycle`; `repeat N times`
- D-048 `@` passes by reference, at the declaration and at the call
- D-049 `::` is the only clone; no `clone` keyword; slices by `:=` are views
- D-054 Exceptions page, `$err_` and `$wrn_` constants
- D-058 Collections answers: ordinals, literals, sets, maps, strings
- D-059 Collections follow-ups; one interpolation form
- D-060 Interpolation escapes `\s{}` `\#{}` `\b{}`; queue direction
- D-061 Licenses: BUSL-1.1 for code, CC BY 4.0 for the specification
- D-062 Trademark policy
- D-063 First execution of level 1: what running the tests taught
- D-064 Matrix and tensor indexes: `[x, y]` is `[x][y]`
- D-065 `demo/` is temporary
- D-069 Methods page; Multitasking after Classes
- D-070 Default values of parameters
- D-074 Loop tested at the end: `loop … do … repeat [while c];`; `skip`
- D-075 Mission, role of the tutorial, demos kept (2026-10-04)
- D-076 `new` declares, `let` executes, a class call constructs
- D-077 Inline `new`: one statement changes a variable and creates another
- D-078 CC BY-NC-SA 4.0 for the specification and the documents; mission
- D-079 Last element `[-1]`, approximate match `=~`, range `+-`, light assignment `=`
- D-080 Types: DataMap, Rune, Null and null, Decimal, number suffixes, string append, data-loss warning
- D-084 Construction: the constructor's result is `@self`; construct up the chain
- D-085 `generator` keyword; visibility by words; `export`; methods belong to classes
- D-086 Functions with or without result; methods belong to classes; Methods chapter after Classes
- D-087 `!` means non-deterministic; command–query separation; closures and generators
- D-088 Issue cleanup: names, split of the types page, library functions
- D-091 Index in seven phases; Topology and Object Oriented pages split
- D-092 Functional programming phase: seven pages
- D-093 Phases: Enterprise and System merged; Internet added; Shell Commands last
- D-094 Level 1 audit: answers to Q-002 to Q-006, corrections, specification and tests
- D-095 Lexical answers: exponent, `&` references, Text literal, interpolation format, small rules
- D-096 Answers of 2026-10-06 applied: placeholders, list arrows, `let`, `class` types, `assert`, unary
- D-097 Regex literal: a string that starts with `/` keeps its backslashes
- D-098 Tests brought to D-096 and D-097 by static analysis
- D-099 `demo/` retired: every demo has a home
- D-100 A subprogram without result is a procedure
- D-101 Answers to Q-034: no procedure references, closures are functions
- D-102 Placeholders are `{name}` and `{name % format}`; literal braces are escaped
- D-103 Collection methods confirmed; methods are not values; functions in a class; placeholders select
- D-104 Answers to Q-033 (c) to (j): async, spawn, await; let in a loop; ordinals
- D-105 Tutorial: Subprograms page with Procedures, end of phase 2; mandatory before optional
- D-106 Order of parameters: a mandatory parameter after optional ones is named at the call
- D-107 The list stays after `+>` and before `<+`
- D-108 Date, Time and `as` are outside level 1
- D-109 Error codes, system variables, lambdas and closures
- D-110 Eve is a compiler: names and types are checked before the run
- D-111 `exit` leaves the current subprogram or process; `over` ends the whole process
- D-115 Grammar checked against the examples (S3.6, 2026-10-08)
- D-116 Prefer contextual keywords to reserved keywords
- D-117 Answers to Q-037: syntax points found by the grammar check
- D-118 A scalar operator applies to every element of a List or Array
- D-120 A placeholder holds a name or any literal; its quotes are not escaped
- D-121 Simple expressions in placeholders
- D-153 Release policy: release notes in `manual/releases/`, the manual updated at every release
- Q-069 `read` at the end of input (answered 2026-10-21 → D-210)
- Q-070 The draft files `lib/sys/io.eve` and `exception.eve`, `Error`, `Warning`, `warn`, `raise(code, message)` (answered 2026-10-21 → D-211)
- Q-071 Named parameters `-p` and the generated help `-h` of a script (answered 2026-10-21 → D-212)
- Q-072 to Q-077 The libraries of S15.30: layout, global names, types, random, order, reference standards (answered 2026-10-21 → D-214)

## D-153 Release policy: release notes in `manual/releases/`, the manual updated at every release (2026-10-10)
Author decision. Every release creates its **release notes** in `manual/releases/vX.Y.Z.md` and **updates the manual**. (1) The notes give each feature its code `F-<area>-<nn>` and one of three stages: `design` (decided or proposed in writing, nothing built), `drafted` (spec or tests written, implementation missing or partial), `validated` (implemented and tested, `✓ done`). The stage is read from the row of the feature in `spec/features/`, never written by hand. (2) The manual (`manual/README.md`) has a paragraph about the **progress** (tests per level, features per stage) and the **performance** achieved (benchmarks against the previous release and against Python), with a link to `test/bmark/README.md`. (3) The manual has **usable links** to `spec/`, the tutorial and the readme files of `test/`: relative links with the exact case for the files of this repository (the test folders hold `readme.md`), and the published pages `https://sagecode.org/projects/eve/…` for the tutorial, which is git-ignored here. (4) A tagged release is a record: its notes are never edited again. Tools: `script/relnotes.py` (generates the notes from `design/template/release-notes.md`, the progress and links of the manual; `--check` verifies the links and the TODOs), `script/release.py` (bumps the version). Policy and the steps of a release: `design/release.md`. Replaces the `implemented.md` of step M7.7 (`design/phase-7-manual.md`).

## D-161 `then` is removed from `match` and the loops (2026-10-11)
Author decision. `then` was redundant: the statements that followed it can be written after `done;`, in the scope of the process or job. `then` is no longer part of `match`, `while` or `for`; the VM refuses it with the error `'then' no longer exists: write the statements after 'done;'` (test `a85`). The word stays reserved so the message is clear. What changes for the program: the variables of a `loop` header and the control variable of a `for` are visible in the body and in `else`, not after `done;`; a value that is read after the loop is declared before it, in the process or job scope. Supersedes the `then` rows of D-016 and D-074.

## Q-069 `read` at the end of input (2026-10-21)
`read(@v, prompt)` (spec `syntax/statements.md`) reads one line from the standard input into `v` and is built into the interpreter (test `a96_read_line`, runner key `"stdin"`). The spec does not say what happens when the input is exhausted. **Implemented for now:** the error `$err_io` (22) is raised, so a loop reads until a `recover`. **Options:** (a) keep the error; (b) `v` becomes the empty text and a Logic function `eof()` tells the end; (c) `read` becomes a function that returns `Text?` with `null` at the end, which changes the form `read(@v)` that the spec has. The author decides; the test and the spec follow.
**answer** c) agree wit null at the end, data type Text? is fine.

## Q-070 The draft files `io.eve` and `exception.eve` (2026-10-21)
`lib/sys/io.eve` and `lib/sys/exception.eve` are drafts that the VM never loads (forms the parser cannot read: TD-2, TD-3), and they disagree with the language as built: `print`, `write`, `raise`, `expect`, `assert` are statements and `read`, `error`, `warning`, `log_err`, `log_wrn` are built-in calls. The drafts also name things that do not exist: the classes `Error` and `Warning` (`Error(9, "x")` is an undefined name), `warn`, `raise(code, message)` (open point PRC-08, PRC-09 of `semantics/errors.md`), `assert(cond, message)` with a custom message. **Options:** (a) delete both files and say in the library pages that these names are built in (no code change); (b) keep them as documentation, marked as such; (c) make the VM load them, which needs the classes, `warn` and `raise(code, message)` to be designed first (a language feature: feature entry and failing test). Recommended: (a) now, (c) later as part of the typed exceptions (F-LNG-15). The author decides; step S15.10 skips this part until then.
**answer** a) for first level but once implemented in lib, virtual machine load them and uses them implicit. 

## Q-071 Named parameters `-p` and the generated help `-h` of a script (2026-10-21)
The spec says the arguments after the file go to the parameters of `process main` (by position, works today) and the feature F-STR-05 promises `-p`/`--param` and `eve script.eve -h` built from `** @param` comments. Neither form is written anywhere, and today `eve file.eve -p n=3` answers `unknown option -p` and `eve file.eve -h` prints the help of `eve`. **Questions:** (1) the form of a named parameter: `-p name=value` (repeatable) or `--param name=value`; (2) how a value becomes the type of the parameter (`Integer`, `Decimal`, `Logic`, `String`, a list as `a,b,c`?); (3) the form of the comment: `** @param name: text` above `process main`, one line per parameter; (4) whether `-h` after the script name prints the help of the script (name, parameters with type, default and text) instead of the help of `eve`; (5) the exit code of a missing required parameter (64, usage). **Proposal:** `-p name=value` repeatable, the value parsed as an Eve literal of the declared type (text unquoted for String), `-h` prints the script help, a missing parameter without default exits 64 with the help. The author decides; the tests follow.
**answer** yes, that is the design -p name=value will work, the value can be an EVE literal and the type is converted to the required type. A logic type is True, False and a list type is param=(a,b,c) e.t.c. The comment @param above the main process of primary aspect name will describe each parameter that will be used in -h to create the help. 
** @param name:type; description 
This is the syntax for comments for parameters.

## D-210 Answer to Q-069: `read(prompt)` gives `String?`, `null` at the end of the input (2026-10-21)
Author decision (2026-10-21): option (c), "null at the end, data type Text? is fine". `read` is a function: `new line := read("name: ");` gives the line without its line end, or `null` when the input is exhausted. The form `read(@v, prompt)` of the first draft is gone. Built in; test a96, `spec/library/builtins.md`.

## D-211 Answer to Q-070: no draft files; the names are built in at level 1, the library may take them later (2026-10-21)
Author decision (2026-10-21): option (a) "for the first level, but once implemented in the library, the virtual machine loads them and uses them implicitly". `lib/sys/io.eve`, `lib/sys/exception.eve` and their generated pages are deleted; the built-in names are in `spec/library/builtins.md`. A later version may write them in Eve in a module that the machine loads on its own, without an import; the classes `Error` and `Warning`, `warn` and `raise(code, message)` wait for typed exceptions (F-LNG-15, step S15.31). TD-3 is closed.

## D-212 Answer to Q-071: `-p name=value` and the help made from `** @param` (2026-10-21)
Author decision (2026-10-21): "yes, that is the design: `-p name=value` will work, the value can be an Eve literal and the type is converted to the required type. A Logic is `True`, `False` and a list is `param=(a,b,c)`. The comment `@param` above the main process of the primary aspect describes each parameter and is used by `-h` to create the help." The comment syntax is `** @param name:type; description`. Built: `spec/semantics/aspects.md#parameters-on-the-command-line`, tests a98 to a100. The proposal's exit code 64 for a missing parameter stands. Not built: `-p` together with `-loc`/`-rem` (the parameters are not sent to the machine).

## D-213 A loop has one scope: a `new` in the body fails at the second cycle (2026-10-21)
Author decision (2026-10-21), answering the open point of `scopes.md` (TD-63): "A second iteration will fail because the variable already exists in the local scope. The loop does not create 2 scopes. Of course this is a runtime error but the compiler can't catch it. Tests should catch these kinds of errors of judgment. Fix both to behave the same in the VM."

Read as rules: (1) the header and all the cycles of a `while`, `for` or `loop` share one scope; (2) a `new` or `set` in the body creates its name once, and the same statement run again in that scope is a run-time error (it also hides an outer name at the first cycle); (3) no compile-time check; (4) the tree walker marks each variable with its declaring statement; the bytecode machine does not compile a program that declares in a loop body, so the tree walker runs it and both engines agree; (5) each attempt of a job has its own scope (a `retry` declares again). Built with tests a104 and a105; the library (`config`, `http`, `route`, `service`), 14 tests and 6 benchmarks that declared in a loop body were corrected (the name before the loop, `let` in the body). The text of the tutorial (scl repository) has the same examples to correct.

## Q-072 to Q-077 The libraries of step S15.30 (2026-10-21)
The plan of the libraries (a folder library next to `sys/`, the order core, math, stats, time, text, business, engineering, data, ids, and the recipe of one library step) is `design/design-libraries.md` section 0. Questions: Q-072 layout of a large library (`lib/<domain>/` imported with `from lib/math use (trig)`); Q-073 which basic functions stay global (`abs`, `min`, `max`, `sqrt`, `pow`) and which are `math.`; Q-074 the types `Rational`, `Complex`, `Quantity` as language types or as library classes; Q-075 a seeded generator for `random`; Q-076 the order of the libraries and which comes third; Q-077 whether the pages follow ISO 80000, ISO 4217 and the spreadsheet names of the financial functions. Each has a proposal in the section; the author answers in place there or here.

## D-214 Answers to Q-072 to Q-077: the layout and the rules of the libraries (2026-10-21)
Author decision (2026-10-21), in `design/design-libraries.md` section 0.6:
- **Q-072:** yes, sub-folders for domain and sub-domain: `lib/math/trig` and so on, imported by path.
- **Q-073:** "Only `math.`": `abs`, `min`, `max`, `sqrt`, `pow` and the other functions of mathematics are functions of the module `math`, not global names. The global functions that exist stay (`floor`, `ceiling`, `round`, `type`).
- **Q-074:** `Rational`, `Quantity` and `Complex` are types of the language (not library classes).
- **Q-075:** a seeded generator and an unseeded one. With the seed the output is reproducible; without it the value can not be predicted but its type can. A test states an unpredictable value with a type in braces: `{Integer}`, `{String}`, `{Any}` for any value (a feature of the test runner to build with the library `random`, step L2).
- **Q-076:** the order of the libraries is accepted (L1 core, L2 math, L3 stats, L4 time, L5 text, L6 business, L7 engineering, L8 data, L9 ids).
- **Q-077:** yes, the pages follow the standards: ISO 80000 (units and quantities), ISO 4217 (currency codes, mandatory for financial pipelines), and the names and arguments of Excel and OpenDocument for the financial functions (`NPV`, `IRR`, `PMT`).

