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

## Q-072 to Q-077 The libraries of step S15.30 (answered 2026-10-21 → D-214)
The plan of the libraries (a folder library next to `sys/`, the order core, math, stats, time, text, business, engineering, data, ids, and the recipe of one library step) is `design/design-libraries.md` section 0. Questions: Q-072 layout of a large library (`lib/<domain>/` imported with `from lib/math use (trig)`); Q-073 which basic functions stay global (`abs`, `min`, `max`, `sqrt`, `pow`) and which are `math.`; Q-074 the types `Rational`, `Complex`, `Quantity` as language types or as library classes; Q-075 a seeded generator for `random`; Q-076 the order of the libraries and which comes third; Q-077 whether the pages follow ISO 80000, ISO 4217 and the spreadsheet names of the financial functions. Each has a proposal in the section; the author answers in place there or here.

## D-214 Answers to Q-072 to Q-077: the layout and the rules of the libraries (2026-10-21)
Author decision (2026-10-21), in `design/design-libraries.md` section 0.6:
- **Q-072:** yes, sub-folders for domain and sub-domain: `lib/math/trig` and so on, imported by path.
- **Q-073:** "Only `math.`": `abs`, `min`, `max`, `sqrt`, `pow` and the other functions of mathematics are functions of the module `math`, not global names. The global functions that exist stay (`floor`, `ceiling`, `round`, `type`).
- **Q-074:** `Rational`, `Quantity` and `Complex` are types of the language (not library classes).
- **Q-075:** a seeded generator and an unseeded one. With the seed the output is reproducible; without it the value can not be predicted but its type can. A test states an unpredictable value with a type in braces: `{Integer}`, `{String}`, `{Any}` for any value (a feature of the test runner to build with the library `random`, step L2).
- **Q-076:** the order of the libraries is accepted (L1 core, L2 math, L3 stats, L4 time, L5 text, L6 business, L7 engineering, L8 data, L9 ids).
- **Q-077:** yes, the pages follow the standards: ISO 80000 (units and quantities), ISO 4217 (currency codes, mandatory for financial pipelines), and the names and arguments of Excel and OpenDocument for the financial functions (`NPV`, `IRR`, `PMT`).

## D-215 A folder library has a specification module that re-exports its submodules (2026-10-24)
Author decision (2026-10-24): `lib/math.eve` and the folder `lib/math/` have the same name by convention; the folder holds the submodules and the parent module re-exports them, "like a specification in Ada". The form is `from basic export (*);` or `from trig export (sin, cos);` inside the module (spec/semantics/modules.md#re-export, test c43). The parent also gives access to the submodules as members: `math.basic.sqrt(x)` (c45). A name listed after `export` that the submodule does not export is a compile error.

## D-216 Import forms: bare names and the folder name, `alias`, and the first import wins (2026-10-24)
Author decision (2026-10-24), spec/semantics/modules.md#import: (1) `from lib/math use (*)` gives the merged modules as bare names and also under the name of the folder (`sqrt(x)` and `math.sqrt(x)`); (2) `from lib/math use (*) alias m` gives only `m.sqrt(x)`; (3) a name given by two imports is no longer a compile error: the first import wins, the second stays hidden and the compiler writes a warning `$wrn_hidden` (code 8); the modules of a folder are taken in the order of their file names; (4) the compile-time warnings get constants `$wrn_name` and a table in spec/semantics/errors.md#warnings-of-the-compiler, that grows with the features (TD-67: no warning list in the diagnostics yet). Tests c18, c44, c45.

## D-217 The type Rational: the literal `3\4`, exact, two 64-bit integers (2026-10-24)
Author decision (2026-10-24): `a\b` is the literal of the type `Rational` (spec/semantics/types.md#rational, F-LNG-30). Exact `+ - * /` and `^` with a whole exponent; the result of two Rationals or a Rational and an Integer is a Rational, with a Real it is a Real, with a Decimal an error (compile time when the types are known). A numerator or denominator beyond 64 bits is `$err_overflow`, never a rounding (TD-69: no big fractions). Measured: about 25 ns an operation, 10 to 15 times faster than Python's `fractions` (test/bmark/p1e_rational.eve). Library: the module `rational`. Tests c46 to c49, bc19.

## D-218 The type Complex: the imaginary literal `i99`, a sum in parentheses (2026-10-24)
Author decision (2026-10-24): "the literal for a complex number is a parenthesis, `(10 + i99)`". The only new token is the imaginary literal, the letter `i` and a number written together (`i99`, `i2.5`, `i1e3`): a name that is `i` and digits is therefore never a variable (TD-70). Two f64; `+ - * /` and `^`; `==` without order (`<` is a compile error); a Decimal never mixes; printing in the form of the literal. Library: the module `complex`; `math.abs(z)` is the modulus (spec/semantics/types.md#complex, F-LNG-31). Tests c50 to c53, bc20.

## D-219 The random generator and the placeholders of the test runner (2026-10-24)
Answer to the part of Q-075 that was left open: one generator for the process, xoshiro256** seeded through SplitMix64, so a seed gives the same numbers on every machine and release; `random.seed(n)` is a procedure (no `!`: D-101), the functions that give a value end with `!`. Without a seed the generator starts from the operating system. A test states an unpredictable value by its type in braces in the expected output: `{Integer}`, `{Real}`, `{Logic}`, `{String}`, `{Any}` (script/runtest.py; with `--both` the two engines may print different values for such a test). Tests a113 to a115.

## D-220 A call of a pure numeric library function is made without a scope (2026-10-24)
Optimization of TD-71, measured before and after (alternating runs, 15 each, ReleaseSafe): a loop of 300,000 calls of `math.abs` 232 to 165 ms (-29%), `p1f_complex` 119 to 97 ms (-19%), calls of user functions unchanged (`p3a_modules` 83 and 84 ms). `invokeWith` calls the functions of the modules `basic`, `explog`, `trig`, `numtheory`, `rational` and `complex` with the values (`dlib.fastResolve`, `fastCall`; the code is cached in `Func.fast`). What is left is the general cost of a call, about 0.3 microseconds (TD-72).
