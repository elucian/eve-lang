# Decisions, level 1: project and single script

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. When a question is answered, turn it into a decision with the date and keep the question text for history. Plan steps reference these ids. **Read cheaply:** the index below lists every id; `python script/plan.py show D-087` prints one entry from here or from `archive/` (settled entries, full text); `python script/plan.py status` lists what is open.

The log is split in two files. Ids are shared and keep counting across both (an id not found here is in the other file); a new entry goes to the file of its topic:

- [decision_level1.md](decision_level1.md): the project (formats, repositories, licenses, the VM, tests) and the language of a single script (lexical rules, control flow, types, collections, functions, classes, errors in a driver). Matches `test/level1`.
- [decision_level2.md](decision_level2.md): programs made of several files: processes, aspects, modules and imports, libraries, multitasking and parallel aspects. Matches `test/level2`.
- Levels 3 to 7 (data, parallel, database, server, web): [decision_level3.md](decision_level3.md), [decision_level4.md](decision_level4.md), [decision_level5.md](decision_level5.md), [decision_level6.md](decision_level6.md), [decision_level7.md](decision_level7.md); the table of all levels is in decision_level3.md and [version_map.md](version_map.md).

<!-- index:begin -->
## Index (every id; full text: `python script/plan.py show ID`)

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
- D-007 `evevm/` source, `bin/eve.exe` official implementation
- Q-007 Which implementation does `manual/` document? (answered 2026-09-28 → D-005)
- D-008 Shebang line
- Q-008 Implementation language and name of the first compiler (answered in part 2026-09-28 → D-006) [open]
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
- Q-026 Callbacks and collection operations (answered in part 2026-10-06 → D-096, follow-up Q-032) [open]
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
- D-054 Exceptions page, `$err_` and `$wrn_` constants [open]
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
<!-- index:end -->

## Q-008 Implementation language and name of the first compiler (answered in part 2026-09-28 → D-006)
Which language is the first Eve compiler written in, what is it called (the manual uses the placeholder `evec` for its support file), and does its code live in this repo or its own? Doesn't block the generator (M7.3); blocks M7.5 architecture details and M7.6.
**Answer:** Zig; the first implementation is a VM, not a compiler (D-006). Name and repository → Q-009.

## D-039 Traits, abstract classes, partial methods (2026-10-01, proposed)
Proposed by the model after reviewing the partials section of classes.html. Awaiting author confirmation. Touches CLS-07 and CLS-08.
- Problem: "partial" meant trait, interface, abstract class and prototype constructor at once; a partial constructor carried state, so multiple inheritance had attribute conflicts; an unimplemented method returned `Null` at run time.
- Vocabulary: a **partial method** is a signature ending in `;`. An **abstract class** is a class with at least one partial method. A **trait** is `trait Name is … end Name;`.
- Trait: no attributes, properties, constructor or destructor (no state, no instances). It holds required methods (partial) and provided methods (with a body, which may call the required ones through `@self`). `@self` is untyped and means the adopting class. A trait can be generic (`trait Comparable(:T)`) and can be used as a type (`let p: Printable := c;`, `x is Printable`). `trait` is a keyword; it closes with `end` (D-037).
- Abstract class: has attributes and a constructor, cannot be created with `new`; only a subclass constructor calls it, by its name (`self := new Shape(name);`). The partial constructor is removed.
- Inheritance list `<: (A, B, …)`: at most one superclass that carries state (default `Object`), any number of traits (CLS-07). A method of the class wins over a trait method; two traits that provide the same method need an explicit implementation in the class, otherwise a compile error.
- A class with a constructor must implement every inherited partial method: a missing one is a compile error, never `Null` (CLS-08).
- The `for` loop uses the library trait `Iterable`.
- Applied to classes.html (partials section rewritten), syntax.html (keyword `trait`), collections.html.
- Open: adopting a trait for an existing type outside its declaration (an extension, in another module), for example `Integer` adopting `Printable`; and the exact list of library traits (`Iterable`, `Comparable`, `Printable`).
- Todo: library traits `Iterable`, `Comparable`, `Printable`: step S5.1a in `plan/phase-5-conformance.md`.

## D-054 Exceptions page, `$err_` and `$wrn_` constants (2026-10-02, proposed codes)
Author request. New tutorial page `exceptions.html` (topic 13, after the standard library; later topics renumbered).
- Predefined read-only constants: `$err_name` for each standard exception, `$wrn_name` for each warning; the value is the integer code, compared with `$error.code` in the `recover` region. Two tables, one for exceptions, one for warnings, with code, constant and message pattern. A new exception or warning must be added to its table first.
- The author wrote `@wrn_name`; read as `$wrn_name` (system constants use `$`). Confirm.
- Proposed (not decided): code ranges 1-9 statements (`panic` 1, `expect` 2, `assert` 3 as a warning), 10-127 system, 128-255 project; the exit code of an unhandled error is its code. The list of standard codes and the message patterns are a first draft. `raise`, `warn` and the Exception module signatures stay open (PRC-08, PRC-09).

## Q-026 Callbacks and collection operations (answered in part 2026-10-06 → D-096, follow-up Q-032)
Which collection operations take a callback (`map`, `filter`, `sort(by)`, `reduce`, `each`)? Is a named function passed as a value (`each(items, double)`)? Which declaration of a function type stays: `Type BinEx = (p1, p2: Integer): Integer <: Function;` (old) or `Type Reporter = (done: Integer) is Function;` (new)? Can a method of an object be passed as a callback?.
**Answer:**
Many questions here. Good questions. Make a design, yes some of collections, need callbacks. We need examples of usecases, be connstructive. We use old design <: We consider Function object. The "is" operator is used only to design a body. In this case I see a signature that force a particular parameter list, left to implement later. If a parameter use predefined type of function, that type is checked on compilation. If function signature do not match, is rejected.

## Q-036 Where does an `@` parameter go? (answered 2026-10-07 → D-106)
An `@` parameter has no default, so by D-105 it is mandatory and must come before the optional parameters; but D-048 and the older tests put outputs last (`add(p1 = 0, p2 = 1: Integer, @op: Integer)`). Is `@` exempt from the order rule (outputs last, after optionals and varargs), or must every `@` parameter come before the first optional one?
**Answer:** The output parameters are input/output parameters; Eve has no pure output parameters. A mandatory parameter can be after optional ones, but the call must use a named argument for it, they can't be positional parameters: after optional parameters they must be called with names. Confirmed.

## D-106 Order of parameters: a mandatory parameter after optional ones is named at the call (2026-10-07)
Author answer to Q-036; replaces the order rule of D-105.
- Every `@` parameter is an input/output parameter; there are no pure output parameters.
- A mandatory parameter may be declared after optional parameters (typically `@op`), but the call must give it by name: `add(1, 2, op: @result)`; `add(1, 2, @result)` is an error. Mandatory parameters before the first optional one stay positional.
- Confirmed by the author the same day: such parameters can't be positional; after optional parameters they must be called with names. That's all.
- Applied: `subprograms.html` (Optional, Order, by reference), `declarations.md`.

## D-107 The list stays after `+>` and before `<+` (2026-10-07)
Author answer to Q-017: the operators are suggestive arrows, so the direction tells the side. `x +> lst` puts `x` in front of the list (the list is after the arrow); `lst <+ x` appends `x` (the list is before the arrow). This is the proposal of Q-017 and what the spec and tests already used (`operators.json`, `statements.md`, a10); only the rule is added to `expressions.md` and collections.html.

## D-108 Date, Time and `as` are outside level 1 (2026-10-07)
Author agreed with the proposal. `Date`, `Time` and the operator `as` (format and conversion) are left to level 3, the data language (version 0.2, "Decimal, time, records"). The word `as` stays reserved in `keywords.json`, so the level 1 grammar is closed without them and no level 1 test covers them. Applied: `spec/conformance/README.md`. The tutorial page datetime.html keeps the examples.

## D-109 Error codes, system variables, lambdas and closures (2026-10-07)
Author answers for level 1.
- **Error codes.** Accepted as drafted in exceptions.html (D-054): `$err_panic` 1, `$err_expect` 2, `$err_assert` 3, `$err_raise` 4, `$err_index` 10, `$err_key` 11, `$err_divide` 12, `$err_overflow` 13 …; warnings `$wrn_deprecated` 5, `$wrn_truncate` 6, `$wrn_unused` 7. Rule: one code for one defined error, so index, key, division and overflow have their own error codes (`$error.code`); a35 to a37 check them. **Correction (same day, author):** exit codes are not error codes (D-081). The exit codes are 0 end/`over`, 1 `panic`, 2 failed `expect`, 3 failed `assert`, 4 any other unhandled error, 5 unexpected stop (Ctrl+C, halted or timed-out program, outage). `over;` runs `finalize`. My first version of `errors.md` had lost D-081 (unhandled error "with the code of the error", `over` skipping `finalize`, no code 5); fixed in `errors.md`, `statements.md`, `keywords.json`, a33, a51, compiler.html, exceptions.html.
- An undefined name and an operand of the wrong type are compile errors: see D-110.
- **System variables.** A driver can set `$epsilon` and any other system variable, and can define its own `$name` variables (variables.md, point 6 closed).
- **Lambdas and closures belong to level 2**, not level 1 (conformance/README.md).
- **`exit;` ends with code 0**, like `return` (author, same day); `finalize` runs. Closes the open point of D-010.

## D-110 Eve is a compiler: names and types are checked before the run (2026-10-07)
Author answer. Eve first analyzes the whole script, it does not interpret line by line like Python. An undefined name and an operand of the wrong type are **compile errors**: the script does not start, the VM reports the message and exits with 65 (as a44, a45, a47); they are never error values, can't be caught by `recover` and have no `$err_` code. Applied: `errors.md` (the list of run-time errors no longer has them).

## D-111 `exit` leaves the current subprogram or process; `over` ends the whole process (2026-10-07)
Author question and answers. Since `over` runs `finalize` (D-081), the two statements had no difference.
- **`exit;`** leaves the subprogram or process it is written in and gives control back to the caller: an early `return` in a function, procedure or method (a function keeps the results assigned so far; `defer` runs); in `main` of a driver the program ends with code 0 and `finalize` runs; in the main process of an aspect it ends the aspect.
- **`over;`** ends the whole process it is in, from any depth (also from a function that the process called), with code 0; no `recover`, `finalize` runs. In an aspect the driver continues after `apply`; in the driver the program ends.
- `panic;` stays the abnormal end of the whole application (code 1, no `finalize`).
- Applied: `statements.md`, `keywords.json`, `errors.md`, syntax.html, processing.html; tests a69 (`exit` in a procedure) and a70 (`over` from a procedure).
