# Feature map

The map of Eve in two parts: the **levels** and the **features**. A level is a group of features that is tested together by `test/levelN/` (Level 1 to Level 7), plus a group for the work that spans all levels. Each level has a paragraph below, and each feature has a subtitle and a paragraph under its level. Versions and release numbers are not used here: what is done is what the tests and the code show.

This file is the one place to track the project: the levels and **every feature** with its status. The decisions are in `design/decision/level1.md` to `level7.md`, the steps of the plan in `design/phase-*.md`.

## How to read the features

- Each feature has a stable code `F-<area>-<nn>` (areas: SPEC specification, LNG language, STR structure, MTK multitasking, VM virtual machine, TLS tools, LIB library, DAT data, NET network, WEB web, DOC documentation). Codes are never renumbered or reused; a dropped feature keeps its line, with the reason.
- **Status**: `✓ done` means implemented in `bin/eve.exe` (or delivered, for documents and tools) and covered by tests where tests apply; `partial` says in the description what exists; `open` is not started; `dropped` is not wanted any more. Test results are in `manual/tests.md` (`python script/runtest.py all --both`).
- A feature belongs to **one level**, or to "All levels" when it is a tool, a document, the bytecode machine or the release. To move it, move its subtitle under another level and note the decision in its paragraph.
- **Where to edit (2026-10-20).** Every feature is a subtitle `### F-XXX-nn Name` with a `**Status:**` line, an optional `**Tests:**` line (`level5: e23 e24`, the tests of the feature) and a paragraph. The table of levels, the table of each level and the counts are **generated** from the subtitles by `python script/featmap.py --write` (the pre-commit hook runs it): edit the Status line of the feature, never the table. The code of a table row links to its subtitle. `python script/featmap.py --verify` compares each Status with the results of its Tests line, `--evidence` lists features whose code carries `@feature` tags but whose status is `open`, `--check` finds a stale table.
- A new large feature is added here first, then planned in a phase file, then decided (`D-nnn`), then built.

## Levels

The status of a level is derived from its features: planned when none is started, in progress, done when every feature is done.

<!-- GEN:levels -->
| Level | Name | Status | Features done | Decisions | Tests |
|---|---|---|---|---|---|
| [Level 1](#level-1-the-language-of-a-single-script) | The language of a single script | in progress | 14 of 19 | [level1.md](decision/level1.md) | `test/level1` (a) |
| [Level 2](#level-2-a-project-subprograms-and-aspects) | A project: subprograms and aspects | in progress | 2 of 3 | [level2.md](decision/level2.md) | `test/level2` (b) |
| [Level 3](#level-3-modules-and-classes) | Modules and classes | in progress | 5 of 14 | [level3.md](decision/level3.md) | `test/level3` (c) |
| [Level 4](#level-4-parallel-processing) | Parallel processing | in progress | 5 of 15 | [level4.md](decision/level4.md) | `test/level4` (d) |
| [Level 5](#level-5-data-and-database) | Data and database | in progress | 7 of 30 | [level5.md](decision/level5.md) | `test/level5` (e) |
| [Level 6](#level-6-the-eve-machine-and-the-server) | The Eve machine and the server | in progress | 0 of 24 | [level6.md](decision/level6.md) | `test/level6` (f) |
| [Level 7](#level-7-the-web) | The web | in progress | 0 of 14 | [level7.md](decision/level7.md) | `test/level7` (g) |
| [All levels](#all-levels-tools-documents-bytecode-and-release) | Tools, documents, bytecode and release | in progress | 11 of 23 | - | - |
<!-- /GEN:levels -->

## Level 1: The language of a single script

A script that runs from its first line to its last, with no user subprograms and no classes (D-122). It has declarations and assignment, expressions and operators, control flow, strings with interpolation, the primitive types and the collections, and jobs with error recovery. This level is the core of the lexical and syntactic specification, the first lexer and parser, and the tree-walking interpreter, which stay the reference for the bytecode machine. It is tested by `test/level1` (the `a` series) and is done when the level passes and `spec/` gives the grammar and the semantics of every tested feature, with no test that relies on an unanswered `Q-nnn`.

<!-- GEN:features -->
14 of 19 features done (5 partial).

| Code | Feature | Status |
|---|---|---|
| [F-LIB-01](#f-lib-01-console-io) | Console I/O | partial |
| [F-LIB-02](#f-lib-02-exception-module) | Exception module | partial |
| [F-LNG-01](#f-lng-01-script-shapes) | Script shapes | ✓ done |
| [F-LNG-02](#f-lng-02-declarations-and-assignment) | Declarations and assignment | ✓ done |
| [F-LNG-03](#f-lng-03-expressions-and-operators) | Expressions and operators | ✓ done |
| [F-LNG-04](#f-lng-04-control-flow) | Control flow | ✓ done |
| [F-LNG-05](#f-lng-05-jobs-and-error-recovery) | Jobs and error recovery | ✓ done |
| [F-LNG-06](#f-lng-06-primitive-types) | Primitive types | ✓ done |
| [F-LNG-07](#f-lng-07-collections) | Collections | ✓ done |
| [F-LNG-08](#f-lng-08-strings-and-interpolation) | Strings and interpolation | ✓ done |
| [F-SPEC-01](#f-spec-01-lexical-specification) | Lexical specification | ✓ done |
| [F-SPEC-02](#f-spec-02-grammar-ebnf) | Grammar (EBNF) | ✓ done |
| [F-SPEC-03](#f-spec-03-core-semantics) | Core semantics | partial |
| [F-STR-05](#f-str-05-command-line-parameters-of-a-script) | Command-line parameters of a script | partial |
| [F-STR-07](#f-str-07-system-variables) | System variables | partial |
| [F-VM-01](#f-vm-01-lexer-and-parser) | Lexer and parser | ✓ done |
| [F-VM-02](#f-vm-02-tree-walking-interpreter) | Tree-walking interpreter | ✓ done |
| [F-STR-12](#f-str-12-exit-code-of-the-program) | Exit code of the program | ✓ done |
| [F-LIB-13](#f-lib-13-datamap-methods) | DataMap methods | ✓ done |
<!-- /GEN:features -->

### F-LIB-01 Console I/O

**Status:** partial
**Tests:** level1: a03 a05

`print`, `write`, `read`, `error`, `warning`, `log_err`, `log_wrn` (D-053, D-057).

*Partial:* `print`, `write`, `log_err` and `log_wrn` (run log, D-114) work; `read`, `error` and `warning` are missing; `io.eve` is a draft.

### F-LIB-02 Exception module

**Status:** partial

`Error`, `Warning`, `raise`, `expect`, `assert`, `warn`, code constants (D-054 to D-056).

*Partial:* `raise`, `expect`, `assert` and the `$err_` constants are in the interpreter; `exception.eve` is a draft that is not loaded.

### F-LNG-01 Script shapes

**Status:** ✓ done
**Tests:** level1: a01-a05 a60

Aspect with `process main`, title/subtitle header, comments; no free script and no `#!` since D-179 (earlier D-014, D-037, D-040).

### F-LNG-02 Declarations and assignment

**Status:** ✓ done
**Tests:** level1: a06 a43-a46 a80 a81

`let`, `set`, `:=`, `=`, `::` clone, views (D-036, D-049).

### F-LNG-03 Expressions and operators

**Status:** ✓ done
**Tests:** level1: a07-a09 a76 a78 a83 a84

Arithmetic, logic, comparison, ranges, membership, precedence (D-019, D-022).

### F-LNG-04 Control flow

**Status:** ✓ done
**Tests:** level1: a12-a15 a39 a63 a92

`if`, `match`, `while`, `for`, `loop … repeat [while c]`, labels, `break`, `skip` (D-034, D-074).

### F-LNG-05 Jobs and error recovery

**Status:** ✓ done
**Tests:** level1: a29-a37 a49 a51 a75

Jobs, `recover` with `retry`/`resume`/`abort`, `finalize`, `raise`, `expect`, `over`, `panic`, exit codes (D-020, D-055, D-063).

### F-LNG-06 Primitive types

**Status:** ✓ done
**Tests:** level1: a07 a09 a16 a57-a59 a76

Integer, Natural, Real, Logic, Symbol, String, ordinals, type checks with `is` (D-032). *Rational, Duration, Time, Date not yet.*

### F-LNG-07 Collections

**Status:** ✓ done
**Tests:** level1: a17-a23 a38 a82 a88

List, Array, Matrix, DataSet, HashMap, Object, slices, builders, deconstruction (D-058, D-064).

### F-LNG-08 Strings and interpolation

**Status:** ✓ done
**Tests:** level1: a10 a11 a27 a28 a48 a62 a66 a86 a87

Escapes, text literal `"""`, placeholders `{name}`, `{literal}`, simple expressions and formats `{n % i5}`, code points `{U+H}`, HTML entities `&name;`, regular expressions (subset) (D-060, D-102, D-119, D-120, D-121).

### F-SPEC-01 Lexical specification

**Status:** ✓ done

Tokens, comments, literals, escapes, placeholders, keywords, operators, delimiters as Markdown + JSON (`spec/lexical/`, `keywords.json` D-094; code points `{U+H}` D-119; checked by `script/speccheck.py`).

### F-SPEC-02 Grammar (EBNF)

**Status:** ✓ done

Declarations, statements, expressions, modules and imports (`spec/syntax/grammar.md`), checked against every `.eve` test by `script/grammarcheck.py` (199 of 199 files of levels 1 to 4 and the smoke test).

### F-SPEC-03 Core semantics

**Status:** partial

Types, scopes, control flow, jobs and `recover`, topology, collections and objects.

*Partial:* `semantics/` has variables, types, control, errors, aspects, modules and data-types (a proposal); scopes, topology and collections are missing.

### F-STR-05 Command-line parameters of a script

**Status:** partial
**Tests:** level1: a60

`-p`/`--param` mapped to `main` parameters, `eve script.eve -h` from `** @param` comments (D-055).

*Partial:* the arguments after the script name go to `process main`; `-p` and the generated help are not implemented.

### F-STR-07 System variables

**Status:** partial
**Tests:** level1: a77

The register (`$error`, environment names such as `$HOME`, `$epsilon`, `$err_`/`$wrn_` constants) (D-071).

*Partial:* `$error`, `$epsilon` and the `$err_`/`$wrn_` constants work; the environment names and `$EVE_*` are undefined.

### F-VM-01 Lexer and parser

**Status:** ✓ done

Source to syntax tree, errors with file, line and column (`lexer.zig`, `parser.zig`).

### F-VM-02 Tree-walking interpreter

**Status:** ✓ done

Runs levels 1 to 3, the smoke test and the benchmarks (`interp.zig`, `project.zig`); 193 tests.

### F-STR-12 Exit code of the program

**Status:** ✓ done
**Tests:** level1: a50 a53 a54 a89 a90

`over n;` and `exit n;` give the exit code: 0, or 6 to 125 (1 to 5 belong to the machine); anything else is `$err_argument` (`spec/semantics/errors.md#ending-the-process`; G-2; tests a89, a90).

### F-LIB-13 DataMap methods

**Status:** ✓ done
**Tests:** level1: a21 a88

`has`, `get(k)`, `get(k, default)`, `keys`, `values`, `delete` (`spec/semantics/types.md#datamap-methods`; G-5; test a88). `method` is a contextual word, usable as a name (D-116; G-6; test a91).

## Level 2: A project: subprograms and aspects

A script becomes a project: functions, procedures, lambdas and closures (D-122), and aspects, the units of work that `apply` calls with copy-in parameters, with errors recovered across `apply` and a log per call. Configuration files belong here. It is tested by `test/level2` (the `b` series, each test a folder when it needs several files) and is done when a driver and its aspects run as one project.

<!-- GEN:features -->
2 of 3 features done (1 partial).

| Code | Feature | Status |
|---|---|---|
| [F-LNG-09](#f-lng-09-functions-and-methods) | Functions and methods | ✓ done |
| [F-STR-02](#f-str-02-aspects-serial) | Aspects (serial) | ✓ done |
| [F-STR-06](#f-str-06-configuration-files) | Configuration files | partial |
<!-- /GEN:features -->

### F-LNG-09 Functions and methods

**Status:** ✓ done
**Tests:** level2: b18 b19 b30-b44 b55-b59

Pure functions, `!` functions, procedures, `@` parameters, defaults, varargs, named arguments, lambdas, closures, recursion (D-025 to D-029, D-048, D-070, D-100, D-101). A lambda is not called where it is written (D-147). Conformity level 2 since D-122.

### F-STR-02 Aspects (serial)

**Status:** ✓ done
**Tests:** level2: b01-b17 b20-b29 b45-b54

`apply`, state per call, `@` outputs, named and spread arguments, errors and `over`/`panic` across `apply`, `exclusive` by default, `concurrent` kind (D-066, D-090, D-130; tests b01 to b29).

### F-STR-06 Configuration files

**Status:** partial

`.cfg` with `$key = value`, loaded with `-s` (D-031).

*Partial:* `-s` is accepted by the command line, the `setup` command is a stub.

## Level 3: Modules and classes

Programs in several files: modules and imports, local libraries, managed and direct modules, extension methods, and then classes and methods (D-122, D-125) with constructors, visibility and inheritance. The standard library of the language is also written as modules from this level on. It is tested by `test/level3` (the `c` series) and is done when levels 1 to 3 pass and the modules and classes have their specification pages.

<!-- GEN:features -->
5 of 14 features done (8 partial).

| Code | Feature | Status |
|---|---|---|
| [F-DOC-05](#f-doc-05-library-reference) | Library reference | partial |
| [F-LIB-03](#f-lib-03-strings-math-collections-and-type-conversions) | Strings, math, collections and type conversions | partial |
| [F-LNG-10](#f-lng-10-classes) | Classes | ✓ done |
| [F-LNG-15](#f-lng-15-typed-exceptions) | Typed exceptions | partial |
| [F-LNG-16](#f-lng-16-static-checks) | Static checks | partial |
| [F-LNG-19](#f-lng-19-managed-and-direct-modules) | Managed and direct modules | ✓ done |
| [F-SPEC-04](#f-spec-04-library-specification) | Library specification | partial |
| [F-STR-01](#f-str-01-modules-and-imports) | Modules and imports | ✓ done |
| [F-STR-03](#f-str-03-extension-methods) | Extension methods | ✓ done |
| [F-STR-04](#f-str-04-projects-and-search-paths) | Projects and search paths | partial |
| [F-TLS-02](#f-tls-02-repl) | REPL | partial |
| [F-TLS-03](#f-tls-03-interactive-interpreter) | Interactive interpreter | open |
| [F-VM-03](#f-vm-03-library-loader-and-external-bindings) | Library loader and `external` bindings | partial |
| [F-LNG-22](#f-lng-22-external-routines-and-errors-of-modules) | External routines and errors of modules | ✓ done |
<!-- /GEN:features -->

### F-DOC-05 Library reference

**Status:** partial

Generated by `eve --doc` for every standard module.

*Partial:* io, exception.

### F-LIB-03 Strings, math, collections and type conversions

**Status:** partial

`split`, `join`, `format`, `parse`, `floor`, `round`, sort, search (S5.1).

*Partial:* `split`, `join`, `length`, `count`, `parse`, `floor`, `ceiling`, `round`, `abs`, `min`, `max`, `sqrt` work; sort and search are missing.

### F-LNG-10 Classes

**Status:** ✓ done
**Tests:** level3: c10 c12-c17 c35 c36 c39-c42

Attributes, constructors, `new`, methods with `@self`, inheritance, visibility; a class hosts only methods and only a method has `@self` (D-036, D-123). Conformity level 3 since D-122.

### F-LNG-15 Typed exceptions

**Status:** partial

Error classes with fields, `recover` by type, exit-code mapping (review `RST-R01`).

*Partial:* `$error` with code, message, line and job, the codes `$err_*`, exit codes 1 to 4; `exception.eve` is a draft that the VM does not load.

### F-LNG-16 Static checks

**Status:** partial

Name resolution, arity, visibility and type errors before the run (exit 65).

*Partial:* undefined names, constants, `apply` arguments, exports, free statements in modules, managed modules and concurrent aspects (`check.zig`, `project.zig`); the type checks are few.

### F-LNG-19 Managed and direct modules

**Status:** ✓ done
**Tests:** level3: c26-c31 c33

`managed module` / `direct module` (default), per-member thread safety proved by the compiler, a concurrent aspect calls only safe members (D-129). Tests c26 to c30, c33, d01 to d03; a bare name from `m(*)` or `*` is checked like `m.name`.

### F-SPEC-04 Library specification

**Status:** partial

Built-ins and standard modules as signatures (`spec/library/`).

*Partial:* `library/atomic.md`.

### F-STR-01 Modules and imports

**Status:** ✓ done
**Tests:** level3: c01-c09 c18-c28 c32 c34 c37

`module`, `from … use (…)`, aliases, `m(*)`, `(*)`, singletons, `initialize`/`recover`/`finalize`, `export`, private members, circular imports, `$err_module` (D-041, D-068, D-072, D-112, D-126, D-131; tests c01 to c31). A module is identified by its file, whatever the spelling of the path (c32).

*Open:* the standard library is not searched.

### F-STR-03 Extension methods

**Status:** ✓ done
**Tests:** level3: c09 c11

`method name(@self: Class)` outside the class (D-072, D-086; tests c09, c11).

### F-STR-04 Projects and search paths

**Status:** partial

Project root `$EVE_HOME`, `asp/`, `lib/`, `data/`, `web/` (templates), `out/`, `$EVE_LIB`, `$EVE_LIB_PATH` (D-055, D-073, D-128, D-131).

*Partial:* `asp/`, `lib/`, `out/` and `EVE_LIB_PATH` from the environment work; the variables are not readable from a script; `data/` and `web/` wait for level 5.

### F-TLS-02 REPL

**Status:** partial

Prompt, file completion, commands `check`, `execute`, `help`, `quit`; *2026-10-13:* the full-screen interface at a terminal (upper part with scrollback, command line between two rules, status bar with Ready / Running / time of the last run, Page Up and Down, resize), `help` as a table with a line between commands and `help <command>` pages that wrap to the window (`EVE_WIDTH`, `eve_width`), `clear`, `stop`, `listen`, `serve`, `status`, `eve <command>` without the prompt.

*Partial:* `compile`, `debug`, `begin`, `enter`, `print`, `resume`, `setup` not implemented.

### F-TLS-03 Interactive interpreter

**Status:** open

Evaluate Eve statements and expressions typed at the prompt, keep the session scope.

### F-VM-03 Library loader and `external` bindings

**Status:** partial

Load `.eve` library modules and bind `external` declarations to Zig (D-053, D-056).

*Partial:* project modules are loaded (`project.zig`); `external` is not implemented, `print` and the exception names are built into the interpreter.

### F-LNG-22 External routines and errors of modules

**Status:** ✓ done
**Tests:** level3: c29-c31 c38

An `external` routine of a module whose name is that of a native module (`os`, `fs`, `crypto`, ...) is bound to the native of the same name; an error raised in a module names the file of the module and the call lines end with `of <file>` (`spec/semantics/modules.md#members`, `errors.md#where-an-error-is-reported`; G-1, G-3; tests c37, c38).

## Level 4: Parallel processing

Many cores and many waits: parallel groups, channels, streams with back-pressure, tasks in a job (`async`, `spawn`, `await`), deadlines and cancellation, and region memory. Generics for classes, traits and abstract classes also arrive here (D-039, D-138). The results of parallel code must be deterministic: it is tested by `test/level4` (the `d` series) and the exit test is that the tests give the same output over 100 runs and that a pipeline with more stages than cores completes.

<!-- GEN:features -->
5 of 15 features done (8 partial).

| Code | Feature | Status |
|---|---|---|
| [F-LIB-12](#f-lib-12-testing-module-test) | Testing module `test` | done |
| [F-LIB-11](#f-lib-11-logging-and-observability) | Logging and observability | open |
| [F-LNG-11](#f-lng-11-traits-abstract-classes-generics) | Traits, abstract classes, generics | partial |
| [F-LNG-17](#f-lng-17-stream-type) | Stream type | partial |
| [F-LNG-18](#f-lng-18-atomict) | `Atomic(:T)` | partial |
| [F-MTK-01](#f-mtk-01-parallel-aspects) | Parallel aspects | ✓ done |
| [F-MTK-02](#f-mtk-02-worker-pool-and-scheduler) | Worker pool and scheduler | partial |
| [F-MTK-03](#f-mtk-03-channels) | Channels | ✓ done |
| [F-MTK-04](#f-mtk-04-tasks-in-a-job) | Tasks in a job | ✓ done |
| [F-MTK-05](#f-mtk-05-deadlines-and-cancellation) | Deadlines and cancellation | ✓ done |
| [F-SPEC-05](#f-spec-05-multitasking-semantics) | Multitasking semantics | partial |
| [F-TLS-04](#f-tls-04-debugger) | Debugger | partial |
| [F-TLS-08](#f-tls-08-formatter-and-linter) | Formatter and linter | open |
| [F-TLS-09](#f-tls-09-editor-support) | Editor support | partial |
| [F-VM-05](#f-vm-05-region-memory) | Region memory | partial |
<!-- /GEN:features -->

### F-LIB-12 Testing module `test`

**Status:** done

Checks that print `ok`/`FAIL`, counters, `summary` that raises (`spec/library/test.md`, `lib/test.eve`, test f03; D-189, 2026-10-18).

### F-LIB-11 Logging and observability

**Status:** open

Structured logs, job events, run reports, trace ids (review `RST-R07`, `RNW-R09`).

### F-LNG-11 Traits, abstract classes, generics

**Status:** partial
**Tests:** level4: d20 d21 d22 d23 d24 d41-d43

`trait`, required methods, abstract classes, `class Name(:T)` with `Box(:Integer)(5)`, constraints `(:T <: Comparable)`, library traits `Iterable`, `Stream`, `Comparable`, `Printable` (D-039, D-145, tests d20 to d24). Moved from Version 0.2 to Level 4 (D-138).

*Partial:* traits, abstract classes, generic classes with erased type arguments and the library traits work (d20 to d24, d34, d35); a constraint is not checked yet, generic functions wait for Version 0.4.

### F-LNG-17 Stream type

**Status:** partial
**Tests:** level4: d16

`Stream(:T) <: Iterable(:T)`, read by `for` with back-pressure; at level 4 `Channel(:T)` is the stream, and lists get `batch(n)` and `split(k)` (D-142, test d16). Generators, files and queries adopt it at level 5, with `map`, `filter`, `merge`, `window`, `parallel(n)` (review `RMT-R02`).

*Partial:* `for` on a channel, `batch`, `split` (d12, d16).

### F-LNG-18 `Atomic(:T)`

**Status:** partial
**Tests:** level4: d15

A class of the standard library that wraps the atomic of the machine, for Logic, numbers, references and ordinals; `class Name <: Atomic(:T)` (D-132).

*Partial:* the declaration and the check of managed modules work, the value is a plain value; the operations (`add`, `get!`, `swap!`) need threads.

### F-MTK-01 Parallel aspects

**Status:** ✓ done
**Tests:** level4: d04 d05 d08 d09 d10 d25 d26 d31 d32

`parallel … do start … done`, barrier, data rules, errors as a job (D-066).

*Done (stage A):* groups, labels, data rules, one owner per output (compile and run time), output in the order of start, ParallelError, nesting of one level; tests d04 to d11, d25 to d27, d31, d32.

### F-MTK-02 Worker pool and scheduler

**Status:** partial

`$cores`, M:N, a waiting aspect gives its core away (D-067).

*Partial:* stage A, one core with a baton (task.zig): a waiting task gives the core away; `$cores` and `$max_parallel` wait for stage B.

### F-MTK-03 Channels

**Status:** ✓ done
**Tests:** level4: d12-d14 d28-d30

`Channel(:T)`, send, receive, close, pipelines, deadlock detection, time-out (D-051).

*Done:* send, receive, close, count, `senders`, automatic close, ChannelError 46, deadlock report, `$timeout`; tests d12 to d14, d28 to d30.

### F-MTK-04 Tasks in a job

**Status:** ✓ done
**Tests:** level4: d17-d19 d33

`async` subprograms, `spawn`, `await`; the tasks of a job share its core (D-104, D-143, tests d17 to d19). The module `task` (`round_robin`, `until`) moves to level 5 with the generators (D-144).

*Done:* tests d17 to d19, d33.

### F-MTK-05 Deadlines and cancellation

**Status:** ✓ done
**Tests:** level4: d10 d11 d30

Per-group time limits, cancel or collect errors (review `RMT-R01`).

*Done:* `on error cancel`, `within`; tests d10, d11.

### F-SPEC-05 Multitasking semantics

**Status:** partial

`semantics/multitasking.md`: parallel groups, channels, tasks in a job, durations, determinism (D-140 to D-144).

*Partial:* generators are level 5 (F-LNG-12).

### F-TLS-04 Debugger

**Status:** partial

Debug mode, `halt` breakpoints, step, print variables, reports (`manual/usage.md`).

### F-TLS-08 Formatter and linter

**Status:** open

`eve fmt`, `eve lint` (indentation, style rules; review `RSY-R06`).

### F-TLS-09 Editor support

**Status:** partial

Syntax colors for VS Code and GitHub, then a language server (`backlog/vscode-plugin.md`).

*Partial:* tutorial highlighters `eve1.js`, `eve3.js`.

### F-VM-05 Region memory

**Status:** partial

Arena per aspect call, job and request; long-lived heap for modules and channels (review `RVM-R02`).

*Partial (D-151):* the values are reference counted and freed at the safe points of their region (statement, pass of a loop, `done`), a tracing collector frees cycles at `done`, scratch memory per statement; nothing is freed while tasks run; benchmarks peak at 4.4 to 6.6 MB (`p4a_parallel_sum` 39 MB). Open: an arena per task.

## Level 5: Data and database

The data language and the ETL core: real data with the right types (`Decimal`, `Instant`, records, tables, `Secret`), files and formats (CSV, JSON, text), the HTTP client, generators, generic functions, overloading and the Eve macro, and the database layer with connections, query streams, bulk loads, transactions per job, checkpoints, lineage and the Eve database. It is tested by `test/level5` (the `e` series). It is done when JSON and CSV round-trip, a killed load restarts from its checkpoint, level 5 passes against SQLite and a PostgreSQL server, and `db backup` and `db restore` round-trip.

<!-- GEN:features -->
7 of 30 features done (15 partial).

| Code | Feature | Status |
|---|---|---|
| [F-DAT-01](#f-dat-01-database-layer) | Database layer | partial |
| [F-DAT-03](#f-dat-03-etl-pipeline-model) | ETL pipeline model | partial |
| [F-DAT-04](#f-dat-04-checkpoints-and-restart) | Checkpoints and restart | partial |
| [F-DAT-05](#f-dat-05-columnar-tables) | Columnar tables | partial |
| [F-DAT-06](#f-dat-06-data-lineage-and-run-reports) | Data lineage and run reports | open |
| [F-DAT-08](#f-dat-08-the-eve-database) | The Eve database | open |
| [F-DAT-09](#f-dat-09-database-admin-commands) | Database admin commands | open |
| [F-DAT-10](#f-dat-10-schema-migrations) | Schema migrations | open |
| [F-DAT-11](#f-dat-11-record-table-mapping) | Record-table mapping | done |
| [F-DAT-12](#f-dat-12-evedb-the-eve-test-database) | evedb, the Eve test database | partial |
| [F-DAT-13](#f-dat-13-sql-function) | `sql function` | partial |
| [F-DAT-14](#f-dat-14-stored-procedures) | Stored procedures | partial |
| [F-VM-11](#f-vm-11-one-eve-its-source-in-modules) | One `eve`, its source in modules | partial |
| [F-DOC-02](#f-doc-02-tutorial-data-client-part) | Tutorial, data client part | open |
| [F-LIB-04](#f-lib-04-files-and-paths) | Files and paths | partial |
| [F-LIB-05](#f-lib-05-data-formats) | Data formats | partial |
| [F-LIB-06](#f-lib-06-time-and-dates) | Time and dates | partial |
| [F-LIB-07](#f-lib-07-shell-commands) | Shell commands | partial |
| [F-LIB-08](#f-lib-08-secrets) | Secrets | partial |
| [F-LIB-09](#f-lib-09-compression-and-archives) | Compression and archives | open |
| [F-LNG-20](#f-lng-20-generic-functions-and-procedures) | Generic functions and procedures | done |
| [F-LNG-21](#f-lng-21-overloading) | Overloading | done |
| [F-LNG-12](#f-lng-12-generators) | Generators | done |
| [F-LNG-13](#f-lng-13-data-types-for-etl) | Data types for ETL | partial |
| [F-LNG-14](#f-lng-14-record-types-and-optional-values) | Record types and optional values | partial |
| [F-NET-01](#f-net-01-http-client) | HTTP client | open |
| [F-VM-06](#f-vm-06-efficient-collections) | Efficient collections | open |
| [F-STR-09](#f-str-09-eve-macro-hybrid-script) | Eve macro (hybrid script) | done |
| [F-STR-10](#f-str-10-unified-aspect) | Unified aspect | ✓ done |
| [F-STR-11](#f-str-11-recover-in-a-function-procedure-and-method) | `recover` in a function, procedure and method | ✓ done |
<!-- /GEN:features -->

### F-DAT-01 Database layer

**Status:** partial
**Tests:** level5: e39-e45 e48-e52 e110

Connect, parameterized query as a stream, execute, transactions, bulk load (databases.html; review `RIO-R02`). *Specified and taught (2026-10-10):* `spec/library/database.md`, `databases.html`; the VM has none of it yet.

*Partial (2026-10-11, test e56):* `database.connect` of a `sqlite://` connection in `eve.cfg`, `script`, `execute!`, `query!(:T)`, `query_one!(:T)`, `close`, a job as a transaction (commit at `done`, rollback on error), `csv.read!(:T)` and `json.write` (`.json` array, `.jsonl` lines); results are lists, not streams; no `table`, ORM, `load!`, `commit;` or other drivers.

### F-DAT-03 ETL pipeline model

**Status:** partial
**Tests:** level5: e56 e85 e86

Extract, transform, load with jobs and aspects; dead-letter output; the pattern taught in the tutorial (review `RIO-R04`). *Specified and taught (2026-10-10):* `spec/semantics/data-types.md`, `etl.html`. *State (2026-10-20):* a local ETL runs (CSV to SQLite to JSON, `test/level5/e56`), a bad row goes to the rejects with a limit (e35, e85), streams have `map`, `filter` and the like (e86); the pipeline stages with back-pressure over a database and the lineage report (F-DAT-06) are not done.

### F-DAT-04 Checkpoints and restart

**Status:** partial
**Tests:** level5: e53

Resume a failed pipeline at the last committed batch (review `RIO-R05`). *Specified (2026-10-10):* checkpoints in the target database, `commit;` in a job (`spec/library/database.md#transactions`). *State:* `commit;` with a checkpoint is tested (e53); restart of a killed load from its checkpoint is not tested yet.

### F-DAT-05 Columnar tables

**Status:** partial
**Tests:** level5: e111

`Table` type with typed columns, Arrow-compatible (review `RTY-R06`). *State:* the `Memory` table with typed columns and the column batches of evedb (e111, `test/level6/f02_evedb_columnar`) exist; Arrow compatibility does not.

### F-DAT-06 Data lineage and run reports

**Status:** open

Inputs, outputs, row counts, durations per job and aspect (review `RIO-R06`).

### F-DAT-08 The Eve database

**Status:** open

The core database: one per project in its `db/` folder (default `local.db`, name set in `eve.cfg`, system variable `$EVE_CORE_DB`, D-156), SQLite embedded (3.54.0, compiled into the VM from the amalgamation, `code/evevm/src/sqlite.zig`; DuckDB is not in the VM: it is the separate test database `evedb`, F-DAT-12), for checkpoints, run history, lineage and metadata, never ETL data (staging and the cache are `evedb` databases, D-159) (`design/design-database.md`).

### F-DAT-09 Database admin commands

**Status:** open

`db list`, `db add`, `db test`, `db info`, `db tables`, `db describe`, `db sql`, `db create`, `db backup`, `db restore`, `db export`, `db import`, `db compact`, `db runs`. *Specified (2026-10-10):* the list in `spec/library/database.md#admin-commands`, with `db create-table`, `db prepare`, `db activate`, `db reindex`, `db cache`.

### F-DAT-10 Schema migrations

**Status:** open

Numbered SQL scripts in `db/migrations/<name>/`, applied by `db migrate` and recorded in the Eve database.

### F-DAT-11 Record-table mapping

**Status:** done
**Tests:** level5: e46 e47 e87-e94

`table` declarations binding record classes to tables, tracked records with dirty fields, updates of the changed fields only, mapping validated in debug mode and refused in production (`design/design-database-core.md`, Q-046). *Specified and taught (2026-10-10), as proposed in Q-046:* `spec/library/database.md`, `databases.html`; review points in `design/archive/review-2026-10-04/level5.md`.

### F-DAT-12 evedb, the Eve test database

**Status:** partial
**Tests:** level6: f01 f02

A database server in Zig around DuckDB, outside the VM, that speaks the database frames of EWP; the remote database of the level 5 tests, with fault injection and a statement log (`drivers/duckdb/README.md`).

*Partial (2026-10-18):* detailed design in `drivers/duckdb/README.md`; version 0.3 (D-187): column batches on the native protocol (`QUERYB`, `LOAD` into DuckDB's Appender), the driver `evedb://` with `Memory.store` and `Memory.load`, measured by `script/evedb_bench.py` (1,000,000 rows into a `Memory` table in 0.23 s; a group-by 55 times faster than SQLite), `test/level6/f02_evedb_columnar`; triggers and stored procedures in evedb dropped. Version 0.2 (D-186): evedb answers the **PostgreSQL protocol** on port 5432 (logins trust, password, md5; simple and extended query; types, errors, transactions), a configuration file, `eve db serve` and `eve -s -db --serve`; tested by `script/pg_check.py` (psycopg2, pg8000) and `test/level6/f01_pg_driver`; stored procedures and triggers in Eve designed (version 0.3). Version 0.1 built: the server of the EWP-db frames, sessions with leases, `eve_tx` and `STATUS`, error classes, seven faults, the statement log, tokens, and the commands `serve`, `create`, `sql`, `describe`, `snapshot`, `reset`, `status`, `stop`; 16 unit tests and 66 protocol checks in Python (`script/evedb_check.py`). Not yet: the Eve driver `evedb://`, change sets (`CHANGES`/`APPLIED`), `BATCH`/`CREDIT`, the appender, `drift`, import and export, service mode (0.2).

### F-DAT-13 `sql function`

**Status:** partial
**Tests:** level5: e96-e101

An Eve function marked `sql function` is registered on every SQLite and DuckDB connection and called from SQL; deterministic, one result, SQL types, not overloaded; SQL `NULL` only for nullable types; an error stops the query with `$err_sql` (code 59) (D-166, `spec/library/database.md#sql-functions`).

*Partial (2026-10-12):* SQLite done, tests e96 to e101; DuckDB waits for the VM to load it (D-166).

### F-DAT-14 Stored procedures

**Status:** partial
**Tests:** level5: e102

Native procedures in `sql/` called through `external` signatures; Eve procedures in `proc/`, run by the database part, listed by `eve db proc list`, reloaded by `eve db proc reload`, called by `db.call` (D-166, `spec/library/database.md#stored-procedures`).

*Partial (2026-10-12):* a module of `proc/` is imported and its `sql function`s registered, `eve db proc list`; tests e102, e102_test1. Not yet: `external` at run time (no database with stored procedures in the tests), `proc reload`, `db.call`.

### F-VM-11 One `eve`, its source in modules

**Status:** partial

The modules `evecm`, `evecp`, `evevm`, `evedb`, `eveux` and `cmd` with one build; one binary whose first word chooses the part, `eve vm`, `cp`, `db`, `ux`; the serving machine as one process (D-163, D-164, `design/design-packages.md`; phases A and B).

*Partial (2026-10-13):* the modules `evecm`, `evecp`, `evevm`, `evedb` and `cmd` exist in one root build (arrows checked by the build); the values and the heap are in `evecm`; the database layer is `evedb` behind the interfaces `Host` and `Data`; the configuration and the wire are cut from `server.zig`; not yet: the cut of the machine and of `cli.zig`, the native calling convention, `eveux` and `evetx` in the root build, the part words (`design/design-packages.md` §13).

### F-DOC-02 Tutorial, data client part

**Status:** open

Files, formats, streams, HTTP client, ETL pipelines (review `RTU` phase T1).

### F-LIB-04 Files and paths

**Status:** partial
**Tests:** level5: e31 e84

`fs` and `path` modules, text and bytes, line streams, globbing (review `RIO-R01`). *State:* `fs` files, folders and lines work (e31, e84); a `path` module, bytes and globbing are not done.

### F-LIB-05 Data formats

**Status:** partial
**Tests:** level5: e32-e37 e80-e83

JSON and CSV read/write, decode into records; later XML, Parquet. *State:* JSON, JSON lines, CSV (options, rejects, encodings) and fixed-width text work (e32 to e37, e80 to e83); XML and Parquet are not done.

### F-LIB-06 Time and dates

**Status:** partial
**Tests:** level5: e28 e75 e107

`now`, parse, format, zones, durations.

### F-LIB-07 Shell commands

**Status:** partial
**Tests:** level6: f05 f15

`call` with pipes, and a safe `run(cmd, args, cwd)` (command.html; review `RIO-R03`).

*Partial (2026-10-18, D-189):* module `os` with `run!` (no shell), `env!`, `hostname!`, `pid!`, `platform` (`spec/library/os.md`, test f05).

### F-LIB-08 Secrets

**Status:** partial
**Tests:** level5: e29 e76 e79 e103

A `Secret` type and `secret.get` from environment, file or vault (review `RIO-R01`). *Specified (2026-10-10):* `spec/library/data-language.md#secrets`.

### F-LIB-09 Compression and archives

**Status:** open

Gzip, zip, stream codecs (manifest).

### F-LNG-20 Generic functions and procedures

**Status:** done
**Tests:** level5: e01 e02 e03 e04 e14 e58

A first parameter list of types, `function largest(:T <: Comparable)(items: ()T)`, called `largest(xs)` (types inferred) or `largest(:Integer)(xs)`; also procedures, methods and processes; no type list on a lambda, overloaded functions instead; possible because self-calling lambdas are removed (D-145, D-147, D-148). All its tests pass (2026-10-20, see Tests).

### F-LNG-21 Overloading

**Status:** done
**Tests:** level5: e05 e06 e07 e08 e09 e10 e57 e60

Functions, procedures and methods share a name with different signatures: number and types of the parameters, and the result type of a function; resolved at compile time, the call must match one signature; a function and a procedure never share a name, a method with a result and one without may (D-149, D-150). All its tests pass (2026-10-20, see Tests).

### F-LNG-12 Generators

**Status:** done
**Tests:** level5: e23 e24 e26 e66 e67 e68 e69 e70 e71

Methods with `yield`, `Generator(:T)`, use in `for` and builders (D-067).

### F-LNG-13 Data types for ETL

**Status:** partial
**Tests:** level5: e27 e28 e73 e74 e75 e105

Decimal, Instant/DateTime with zone, Date, Time, Duration, Bytes, Uuid (review `RTY-R01`; needs a decision).

### F-LNG-14 Record types and optional values

**Status:** partial
**Tests:** level5: e30 e106

Typed records for rows, JSON objects and messages; `T?` (review `RTY-R01`, `RTY-R02`). *State:* records, `null` in plain fields and printing of `null` are tested (e30, e106); the full optional type is in `spec/library/data-language.md`.

### F-NET-01 HTTP client

**Status:** open

Requests, headers, JSON bodies, time-outs, TLS (review `RNW-R10`).

### F-VM-06 Efficient collections

**Status:** open

Hashed and sorted maps, sets, ropes for Text (review `RVM-R04`).

### F-STR-09 Eve macro (hybrid script)

**Status:** done
**Tests:** level5: e16 e17 e18 e19 e20 e21 e22 e61 e62 e63 e64 e65 e108 e109

One self-contained file: shared declarations and several aspects, exactly one of them `primary`; `apply` (level 2) and `parallel`/`start` (level 4) inside it; a concurrent aspect uses only the thread-safe shared names (D-152, D-180; tests e16 to e22, e108, e109).

### F-STR-10 Unified aspect

**Status:** ✓ done

No `driver` keyword, no free script, no `#!`; the kinds `exclusive`, `concurrent` and `primary`; `main` and private processes; calls between aspects at most three levels deep and without a cycle; a concurrent aspect is called from a primary or an exclusive aspect; a primary aspect is run by a command (D-179 to D-183; tests a04, b15, b24, b45 to b54, c24, d36 to d40, e21, e61, e108, e109).

### F-STR-11 `recover` in a function, procedure and method

**Status:** ✓ done

The end of `recover` handles the error and the routine returns normally; `abort` passes it on; no `recover` in a constructor, generator or lambda (D-192, Q-065; `spec/semantics/errors.md`; tests b55 to b59, c34 to c36; 2026-10-18).

## Level 6: The Eve machine and the server

The Eve machine and the server: setup from a folder, control by scripts and by other machines through the doors (IPC, stdio, HTTP), sessions and the machine API `vm.*`, services and routes written in Eve, the editors' link to the machine, and the test database evedb that speaks the PostgreSQL protocol. Login with single sign-on per machine, capabilities and the Eve Wire Protocol are still open. It is tested by `test/level6` (the `f` series) and by the smoke test; it is done when a client project and a server project talk on `localhost`, a route answers HTTP, and the machine logs in to two remote machines.

<!-- GEN:features -->
0 of 24 features done (6 partial).

| Code | Feature | Status |
|---|---|---|
| [F-DOC-03](#f-doc-03-tutorial-network-and-web-part) | Tutorial, network and web part | open |
| [F-LIB-10](#f-lib-10-encryption-and-hashing) | Encryption and hashing | partial |
| [F-NET-02](#f-net-02-http-server) | HTTP server | partial |
| [F-NET-03](#f-net-03-eve-wire-protocol-ewp) | Eve Wire Protocol (EWP) | open |
| [F-NET-04](#f-net-04-remote-apply) | Remote apply | open |
| [F-NET-05](#f-net-05-capabilities-and-sandbox) | Capabilities and sandbox | open |
| [F-NET-06](#f-net-06-authentication) | Authentication | open |
| [F-NET-07](#f-net-07-machine-login-single-sign-on-and-the-keyring) | Machine login: single sign-on and the keyring | open |
| [F-NET-08](#f-net-08-the-machine-api) | The machine API | partial |
| [F-SPEC-06](#f-spec-06-network-semantics-and-protocol) | Network semantics and protocol | open |
| [F-STR-08](#f-str-08-service-script-kind) | Service script kind | open |
| [F-TLS-12](#f-tls-12-machine-setup) | Machine setup | open |
| [F-TLS-13](#f-tls-13-remote-control) | Remote control | open |
| [F-TLS-14](#f-tls-14-local-http) | Local HTTP | open |
| [F-TLS-24](#f-tls-24-evetx-the-terminal-ide-files-editor-run-machines) | evetx, the terminal IDE: files, editor, run, machines | partial |
| [F-TLS-27](#f-tls-27-evetx-debugger) | evetx: debugger | open |
| [F-TLS-28](#f-tls-28-evetx-databases) | evetx: databases | open |
| [F-TLS-29](#f-tls-29-evetx-file-card) | evetx: file card | open |
| [F-NET-09](#f-net-09-credentials-connect-and-upload) | Credentials, connect and upload | open |
| [F-TLS-26](#f-tls-26-repl-selected-machine) | REPL: selected machine | open |
| [F-DAT-15](#f-dat-15-the-user-cache-evedb) | The user cache `eve.db` | open |
| [F-TLS-30](#f-tls-30-service-mode) | Service mode | partial |
| [F-TLS-15](#f-tls-15-eve-api-for-ai) | Eve API for AI | open |
| [F-NET-10](#f-net-10-time-outs-of-the-waiting-calls) | Time-outs of the waiting calls | partial |
<!-- /GEN:features -->

### F-DOC-03 Tutorial, network and web part

**Status:** open

Client and server, services, protocol, security, HTML, WebAssembly (review `RTU` phases T2, T3). (levels 6 and 7)

### F-LIB-10 Encryption and hashing

**Status:** partial
**Tests:** level6: f04

Hashes, HMAC, symmetric encryption (manifest).

*Partial (2026-10-18, D-189):* module `crypto` with sha256, sha512, sha256_file!, hmac_sha256, hex and Base64, random_hex!, same (`spec/library/crypto.md`, `code/evevm/src/syslib.zig`, test f04); not yet symmetric encryption and password hashing.

### F-NET-02 HTTP server

**Status:** partial
**Tests:** level6: f10 f12 f14; level5: e95

Routes, request and response records, static files, one state per request (review `RNW-R02`).

*Partial (2026-10-11, D-162):* the machine with its two doors, IPC (`--listen`, was `-lsn` until D-169) and HTTP (`--serve`: the web folder, `POST /rpc`), JSON-RPC methods `ping`, `status`, `run`, `stop`, the client options `-loc` and `-rem` (`spec/library/machine.md`); tests `e95_web_hello` and `e95_test1` to `e95_test3` pass. *2026-10-13:* the machine at the prompt (`listen`, `serve`, `stop`, the doors in threads, one thread per connection), `evevm` (the machine in its own process, log in a file) and `eve -u` (open the web page). Not yet: routes and `service` scripts, HTTPS, login, WebSocket. *2026-10-18 (D-189):* HTTP and routes in Eve: the system module `net` (TCP), the Eve modules `http`, `route` and `service` (`spec/library/net.md`, `http.md`, `route.md`; tests f09, f10; benchmark p6e: 0.72 s for 300 requests against 0.5 s for Python). Not yet: keep-alive, one task for each connection, the machine's own routes in Eve (`f11`).

### F-NET-03 Eve Wire Protocol (EWP)

**Status:** open

Framed binary protocol for Eve-to-Eve calls and data streams, flow control, resumable streams (review `RNW-R04`).

### F-NET-04 Remote apply

**Status:** open

Run an aspect on another node with a deadline and an idempotency key (review `RNW-R01`).

### F-NET-05 Capabilities and sandbox

**Status:** open

Fs, net, db, shell permissions per project and per aspect (review `RNW-R08`).

### F-NET-06 Authentication

**Status:** open

Tokens, sessions, TLS certificates for services.

### F-NET-07 Machine login: single sign-on and the keyring

**Status:** open

From one local machine, a login per remote machine: single sign-on (OpenID Connect), an account of the machine, or a machine token; the renewal token kept in the keyring of the operating system (Windows Credential Manager, Linux Secret Service) after the first login; commands `login`, `logout`, `forget`, `whoami`; users, roles and registration of a listening machine in its Eve database (D-155, `design/design-service.md` §15, Q-048).

### F-NET-08 The machine API

**Status:** partial
**Tests:** level6: f07 f11

JSON-RPC 2.0 methods named by part: `vm.ping`, `vm.stat`, `vm.run`, `vm.eval`, `vm.suspend`, `vm.resume`, `vm.inspect`, `vm.cancel`, `vm.stop`; `db.*`; the first names of D-162 answered until level 6; no TLS in the machine, a reverse proxy for remote HTTPS; ACP outward (D-165, `spec/library/machine.md#the-machine-api`).

*Partial (2026-10-12):* `vm.ping`, `vm.stat` (with the active parts), `vm.run`, `vm.stop` and the first names, `-32601` for another method; test e95_test4. *2026-10-13:* `vm.stat` adds `requests`, `uptime_ms`, `running`, `running_ms`, `web`; `stop` cancels the running scripts. *2026-10-16:* the lasting doors (`spec/library/machine.md#lasting-doors`): the stdio door `eve --stdio` (an IDE starts the machine as its child; over SSH `ssh host eve --stdio`), the IPC connection stays open, `vm.output` notifications (`"stream": true`), sessions `vm.open`, `vm.eval`, `vm.close` (a default session per connection), `vm.shell`, `vm.cancel`, `vm.run` by `path`, `vm.stat` with `door` and `sessions`; `shell <command>` and `!<command>` at the prompt; test e95_test5; evetx uses it for its console. Not yet: WebSocket, `dbg.*`, `db.*` in JSON.

### F-SPEC-06 Network semantics and protocol

**Status:** open

Remote `apply`, services, Eve Wire Protocol (`spec/protocol/`).

### F-STR-08 Service script kind

**Status:** open

Long-running entry point with routes handled by aspects (review `RNW-R02`; needs a decision). *2026-10-18:* a service is a route table (`route`) served by `service.serve` in an async procedure; `service` scripts as a kind of file are still to decide.

### F-TLS-12 Machine setup

**Status:** open

`--setup <folder>`, the machine folder, `eve.cfg`, built-in defaults, identity domain + port, external checksum, `setup` reload (D-083).

### F-TLS-13 Remote control

**Status:** open

`--listen`, `eve -c`, `-rem`, `-u` upload (*2026-10-14: the user interface is `-ux` and the terminal IDE `-tx` (D-172); the upload of D-083 is `--upload` (D-171)*), `send` between machines, sessions and driver memory spaces (`load`, `dismiss`); then the removal of `.vmc` command files (D-083; *done 2026-10-18, D-188: a series of commands goes through `eve --stdio` and `vm.eval`*).

### F-TLS-14 Local HTTP

**Status:** open

`serve` on port 8042, pages of the web folder, routes of `service` scripts (D-083).

### F-TLS-24 evetx, the terminal IDE: files, editor, run, machines

**Status:** partial

`eve -tx`: a full-screen TUI on libvaxis (Zig package, no binding); the title and the main menu (click, or Ctrl+Enter; Save and Save As), two searches under the title bar, each above its panel (names that start with the typed letters over the tree, the tree going to the match; code, tables or global data with `*` and numbers over the right panel, with Replace), a `#` button to jump to a line or a record, and the gear of the status bar, the file tree of the project, an editor in tabs, Run, the bottom panel (Console with the design of evevm, Watch, Stderr, Stdout, Breaks), the inset status bar (name, place, `?` help on Ctrl+/, gear), the machine chosen with F1 to F3, connect, the user cache and the select project dialog, upload; no schedules and no run history, those are eveux (F-TLS-21); imports `evecm` only (D-173, D-174, Q-050 to Q-054, `code/evetx/README.md`, `design/design-packages.md` step B6).

*Partial (2026-10-13, D-178):* a separate program `code/evetx/` built with `zig build -p ../..` (libvaxis pinned for Zig 0.16): the frame, the tree, the editor with Eve colors, the two searches, `#`, the menu, the help, the file card, breakpoints in the gutter, Run and the console through `eve`; not yet the machines F2 and F3, upload, the debugger, the database tabs, Undo (`code/evetx/README.md` §11).

### F-TLS-27 evetx: debugger

**Status:** open

Breakpoints in the gutter and the Breaks tab (remove, double click to jump), Step into, Step out, Continue, Stop, the Watch tab; needs the debugger of the machine (F-TLS-04, Q-053 b); the same API serves F-TLS-22 (D-173).

### F-TLS-28 evetx: databases

**Status:** open

A database file in the tree opens a table list in a tab; the data of a table in a new tab; the structure of a table in a dialog that is a grid with headers and bordered cells, a drop-down for the type, a calendar for the default of a date or time, and pages of fields; needs the `db.*` additions (Q-053 c, d; D-173, D-174).

### F-TLS-29 evetx: file card

**Status:** open

A text file opens in the editor as source (Markdown too); any other file, images, SVG, audio and video included, opens a card with its facts and no preview; the rendered view is in eveux (D-178).

### F-NET-09 Credentials, connect and upload

**Status:** open

Two ways to give credentials: the unversioned `eve.env` of the project, or a user name and password or a connection string `username/password@machine_name`; `eve --connect` before `eve --upload`; the upload sends the server side (`web/`, `proc/`, `sql/`, `server/` and what they import: Q-052 a); `eve -rem … db install|migrate`; a remote machine runs only what is on it (D-171, Q-051, `design/design-service.md` §16).

### F-TLS-26 REPL: selected machine

**Status:** open

`select <machine>`, the machine in the status bar (`Ready: connection: local`), Ctrl+Left/Right and F1 (local), F2, F3 to change machine, Ctrl+Up/Down for the history of commands, `help` and Tab by machine (only stored procedures and code on the server on a remote one) (D-171).

### F-DAT-15 The user cache `eve.db`

**Status:** open

A SQLite cache of the user (`<user data folder>/eve/meta/eve.db`): projects, machines without secrets, history of commands, upload manifest; the `Meta` interface of `evecm`, implemented by evedb; rebuilt if deleted (D-172, Q-052 b).

### F-TLS-30 Service mode

**Status:** partial

`eve -s`: the machine with no user interface, silent, both doors, a log and a pid file; a Windows service under the Service Control Manager, a Linux daemon, or the foreground form (`EVE_SERVICE=foreground`); `-s file.cfg` is the service reading that file, and `-s` takes nothing else; the configuration of a script, a command or a door is `-e file.cfg` (`--setup`), and the command files `.vmc` are removed (D-188, 2026-10-18) (D-185, `design/design-service.md` section 17, `spec/library/machine.md`).

*Partial (2026-10-17):* the console and foreground forms tested on Windows (`script/service_check.py`); the Service Control Manager form compiles, run needs an administrator; the POSIX code compiles for Linux, not run; not yet: Event Log, run as another user, log rotation, `evedb serve -s`.

### F-TLS-15 Eve API for AI

**Status:** open

`eve --api`, an MCP server whose tools are the commands of the machine (D-083).

### F-NET-10 Time-outs of the waiting calls

**Status:** partial
**Tests:** level6: f13-f15

`Socket.set_timeout(ms)` (a read fails with `$err_timeout`), `service.idle(ms)` and the reply `408`, `os.run!` with `timeout_ms` (status 124) (`spec/library/net.md#time-outs`; TD-27, TD-29; tests f13, f14, f15).

*Open:* `accept!` has no time-out, one connection at a time (TD-29), no streaming `os.run!` (TD-9).

## Level 7: The web

The web: safe HTML templates, Eve in the browser, and the Eve Web Portal evewp, written in Eve with no JavaScript, as the last and hardest test of the language (D-193). The development clients evetx (terminal) and eveux (native window) are tools of this level in their later stages. Nothing here is built yet; the first step is a trial build of the machine for WebAssembly. It will be tested by `test/level7` (the `g` series).

<!-- GEN:features -->
0 of 14 features done (1 partial).

| Code | Feature | Status |
|---|---|---|
| [F-VM-09](#f-vm-09-webassembly-build) | WebAssembly build | open |
| [F-TLS-19](#f-tls-19-eveux-the-rad-workbench-shell) | eveux, the RAD Workbench: shell | open |
| [F-TLS-20](#f-tls-20-eveux-direct-sql-and-database-tree) | eveux: direct SQL and database tree | open |
| [F-TLS-21](#f-tls-21-eveux-jobs-logs-and-admin) | eveux: jobs, logs and admin | open |
| [F-TLS-22](#f-tls-22-eveux-debugger) | eveux: debugger | open |
| [F-TLS-31](#f-tls-31-eveux-source-control) | eveux: source control | open |
| [F-TLS-23](#f-tls-23-new-project) | New project | partial |
| [F-WEB-01](#f-web-01-html-templates) | HTML templates | open |
| [F-WEB-02](#f-web-02-eve-in-the-browser) | Eve in the browser | open |
| [F-WEB-03](#f-web-03-tutorial-playground) | Tutorial playground | open |
| [F-WEB-05](#f-web-05-evewp-edge-and-host) | evewp: edge and host | open |
| [F-WEB-06](#f-web-06-evewp-monitor) | evewp: monitor | open |
| [F-WEB-07](#f-web-07-the-eve-web-framework) | The Eve Web framework | open |
| [F-VM-12](#f-vm-12-process-supervision-api) | Process supervision API | open |
<!-- /GEN:features -->

### F-VM-09 WebAssembly build

**Status:** open

The VM compiled to `wasm32` with host imports (review `RVM-R06`).

### F-TLS-19 eveux, the RAD Workbench: shell

**Status:** open

*(2026-10-18, D-193: eveux is now a native Zig client on dvui, `code/eveux/README.md`; the text that follows describes the browser design, kept in `design/archive/workbench-design.md`, and is the functional specification of the native client.)* an Eve project (service script, aspects, modules) run by the local machine, with a browser part in plain JavaScript and CSS: screen and menus, editor with syntax colors for Eve, SQL, JSON, XML and HTML, file dialog and upload, command window, login to remote machines with single sign-on and the keyring, Help and About with the versions; written in Eve as the final test and stress test of the language (D-154, `code/eveux/README.md`, Q-047).

### F-TLS-20 eveux: direct SQL and database tree

**Status:** open

*(2026-10-18, D-193: eveux is now a native Zig client on dvui, `code/eveux/README.md`; the text that follows describes the browser design, kept in `design/archive/workbench-design.md`, and is the functional specification of the native client.)* SQL mode of the command window and SQL tabs, results in a grid with Eve types, Commit and Rollback, the database object tree of the connections of a machine, import wizard (`code/eveux/README.md` §7, §9, §12).

### F-TLS-21 eveux: jobs, logs and admin

**Status:** open

*(2026-10-18, D-193: eveux is now a native Zig client on dvui, `code/eveux/README.md`; the text that follows describes the browser design, kept in `design/archive/workbench-design.md`, and is the functional specification of the native client.)* job browser and scheduler forms over the remote scheduler of every connected machine, live run output, stage view of the aspects, resume from checkpoint, log inspector, admin pages of a machine (`code/eveux/README.md` §6.6, §10). *2026-10-13 (Q-050): eveux owns schedule management and the management of runs; the schedule methods of the machine API are designed with it; evetx only runs a driver for debug and test (F-TLS-24).*

### F-TLS-22 eveux: debugger

**Status:** open

*(2026-10-18, D-193: eveux is now a native Zig client on dvui, `code/eveux/README.md`; the text that follows describes the browser design, kept in `design/archive/workbench-design.md`, and is the functional specification of the native client.)* breakpoints in the gutter, step into, over and out, variable inspector, watch window, call stack; needs the debugger of the machine (F-TLS-04) and the commands proposed in Q-047 (`code/eveux/README.md` §11).

### F-TLS-31 eveux: source control

**Status:** open

The Git panel of eveux: the status of the working tree (`git status --porcelain=v1 -b` read by a worker thread, no shell), stage, commit, diff; the local tier of the two-tier design of `code/eveux/design/notes/elaboration.md` §4 (D-193). Test: `test/level7` against a temporary repository. Code started: `code/eveux/src/vcs/git_status.zig`.

### F-TLS-23 New project

**Status:** partial

`project init <folder>` and `project new <folder>` (D-160 names it `new project`): `init` also works on an existing project and never overwrites; `new` fails on a non-empty folder. Makes `db`, `log`, `meta`, `data/in`, `data/out`, `test`, `asp`, `lib`, `src`, `doc`, `web`, the files `<name>.eve`, `eve.cfg`, `meta/project.json` and a `.gitignore`, and runs `git init` outside a repository.

*Partial:* done and tested (`code/evevm/src/scaffold.zig`, tests e54, e55); the writer of the minimal fallback log is not written (`design/design-project-layout.md`).

### F-WEB-01 HTML templates

**Status:** open

`HTML` type, context-aware escaping, template files, components (review `RNW-R05`).

### F-WEB-02 Eve in the browser

**Status:** open

The WASM VM runs signed `.evb` code with limited capabilities, `dom` module (review `RNW-R06`).

### F-WEB-03 Tutorial playground

**Status:** open

A "Run" button on tutorial examples using the WASM VM.

### F-WEB-05 evewp: edge and host

**Status:** open

The Eve Web Portal as the production edge: host table by `Host` header (domains, subdomains, wildcards), static files, proxy to the Eve machine of each application, request log and limits; the host keeps each application in its own folder with versions, starts and supervises its machine, receives deploys, rollback (D-193, `code/evewp/README.md` sections 3, 5). Behind a reverse proxy for TLS (D-189).

### F-WEB-06 evewp: monitor

**Status:** open

A graphic health server written in Eve: connections, requests, domains, users, applications, memory, logs, alerts; SVG charts and pages with no JavaScript, live updates through the framework (`code/evewp/README.md` section 6).

### F-WEB-07 The Eve Web framework

**Status:** open

Eve (a dialect with a browser profile) written once and compiled to WebAssembly modules that run in the page: stage W1 the VM in Wasm running source or `.evb`, stage W2 a typed subset compiled to Wasm; shared modules with the server; a fixed generated loader shim, no JavaScript written by the developer (`code/evewp/README.md` section 7). Needs F-VM-09, F-WEB-01, F-WEB-02.

### F-VM-12 Process supervision API

**Status:** open

`os` handles for spawn with limits, wait, kill and signals, status of a child through its IPC door; used by the host of evewp (D-193).

## All levels: tools, documents, bytecode and release

Work that does not belong to one level. The tools: the command line, the test runner, the documentation generator, the smoke test and the benchmarks; the documents: the tutorial, the compiler manual, the specification tables and the licenses; the second engine, the bytecode compiler and machine, the portable `.evb` file and the embedding API; and the road to a stable release: package manager, hardening, the compiler registry and the compiler course. A feature here is checked at every level, for example by running all levels on both engines.

<!-- GEN:features -->
11 of 23 features done (5 partial).

| Code | Feature | Status |
|---|---|---|
| [F-DOC-01](#f-doc-01-tutorial-language-part) | Tutorial, language part | partial |
| [F-DOC-04](#f-doc-04-compiler-manual) | Compiler manual | partial |
| [F-SPEC-07](#f-spec-07-machine-readable-tables-with-schemas) | Machine-readable tables with schemas | ✓ done |
| [F-SPEC-08](#f-spec-08-conformance-levels) | Conformance levels | partial |
| [F-SPEC-10](#f-spec-10-licenses-and-trademark) | Licenses and trademark | ✓ done |
| [F-TLS-01](#f-tls-01-command-line-cli) | Command line (CLI) | ✓ done |
| [F-TLS-05](#f-tls-05-command-files-and-serve-mode) | Command files and serve mode | ✓ done |
| [F-TLS-06](#f-tls-06-test-runner) | Test runner | ✓ done |
| [F-TLS-07](#f-tls-07-documentation-generator-eve---doc) | Documentation generator `eve --doc` | ✓ done |
| [F-TLS-16](#f-tls-16-smoke-test) | Smoke test | ✓ done |
| [F-TLS-17](#f-tls-17-benchmarks) | Benchmarks | ✓ done |
| [F-TLS-18](#f-tls-18-tutorial-pages-of-the-tests) | Tutorial pages of the tests | ✓ done |
| [F-VM-10](#f-vm-10-cross-platform-releases) | Cross-platform releases | partial |
| [F-VM-04](#f-vm-04-bytecode-compiler-and-vm) | Bytecode compiler and VM | partial |
| [F-VM-07](#f-vm-07-portable-bytecode-file-evb) | Portable bytecode file `.evb` | open |
| [F-VM-13](#f-vm-13-engine-selection-and-equivalence-tests) | Engine selection and equivalence tests | ✓ done |
| [F-VM-14](#f-vm-14-sampling-profiler) | Sampling profiler | ✓ done |
| [F-VM-08](#f-vm-08-embedding-api) | Embedding API | open |
| [F-DAT-07](#f-dat-07-database-synchronization) | Database synchronization | open |
| [F-TLS-10](#f-tls-10-package-manager) | Package manager | open |
| [F-WEB-04](#f-web-04-web-application-kit) | Web application kit | open |
| [F-DOC-06](#f-doc-06-compiler-course) | Compiler course | open |
| [F-SPEC-09](#f-spec-09-compiler-registry-and-approval) | Compiler registry and approval | open |
<!-- /GEN:features -->

### F-DOC-01 Tutorial, language part

**Status:** partial

The topic pages reviewed and consistent with the decisions (phase 1, T1.10).

*Partial:* 38 topic pages and the generated pages of Phase 8 (demos, feature tests, smoke and performance); a few pages still describe old forms.

### F-DOC-04 Compiler manual

**Status:** partial

Implement, usage, generated feature tables, implemented features (phase 7).

*Partial:* `manual/usage.md`.

### F-SPEC-07 Machine-readable tables with schemas

**Status:** ✓ done

JSON schemas, `script/speccheck.py`.

### F-SPEC-08 Conformance levels

**Status:** partial

Level 1 (a single script), level 2 (functions, procedures, lambdas, aspects), level 3 (modules, classes), levels 4 to 7 (parallel, data and database, server, web; `design/feature_map.md`, D-122, D-125), with the expected-output convention (Q-005).

*Partial (2026-10-20):* suites of levels 1 to 6 exist and pass (see `manual/tests.md`), with a smoke test and benchmarks (D-135); level 7 has no tests; no list says which implementation passes which level (the registry, F-SPEC-09).

### F-SPEC-10 Licenses and trademark

**Status:** ✓ done

BUSL-1.1 code, CC BY-NC-SA 4.0 spec and documents, TRADEMARK.md (D-061, D-062, D-078).

### F-TLS-01 Command line (CLI)

**Status:** ✓ done

`eve script.eve`, `--check`, `--execute`, `-h`, `-v`, `-s`, `-d`, `-x`, `-i`, `-t`, exit codes 64–66 (`manual/usage.md`).

### F-TLS-05 Command files and serve mode

**Status:** ✓ done

(scheduled for removal, replaced by F-TLS-13, D-083): `.vmc` slot, workflow commands `load`, `parse`, `run`, `errors`, `ast`, `inspect`, `status` (D-063). The tests v01 to v11 were removed (D-135): no test covers it now.

### F-TLS-06 Test runner

**Status:** ✓ done

`script/runtest.py` for levels, project tests, several drivers per project (D-133), `/*@expect*/` blocks, reports in `temp/output/`, the status in `status.json` and in each `readme.md` (D-009, D-073, D-094).

### F-TLS-07 Documentation generator `eve --doc`

**Status:** ✓ done

Markdown from `**` comments and signatures, a command of the VM (D-053, D-082).

### F-TLS-16 Smoke test

**Status:** ✓ done

16 small scripts, one feature each, in less than a second, independent of the other tests (`test/smoke`, D-134, D-135).

### F-TLS-17 Benchmarks

**Status:** ✓ done

One per level with a twin in Python, a history of the runs (`script/bmark.py`, `test/bmark`). Levels 1 to 3 measured.

### F-TLS-18 Tutorial pages of the tests

**Status:** ✓ done

`features.html` and `quality.html` generated from the tests and the benchmarks (`script/genpages.py`, D-136).

### F-VM-10 Cross-platform releases

**Status:** partial

Windows, Linux, macOS binaries from one build; `script/release.py` bumps versions.

*Partial:* Windows build, release script.

### F-VM-04 Bytecode compiler and VM

**Status:** partial

Register machine with 32-bit instructions (`design/design-bytecode.md`, D-201). *Stage B5.2 (2026-10-19):* `code/evecm/src/op.zig`, `chunk.zig`, `code/evecp/src/emit.zig`, `code/evevm/src/bcvm.zig`; the core of level 1 is translated (numbers, text, variables, operators, `print`, `expect`, `if`, `while`, `for` over ranges, calls of the functions of the aspect), the rest runs on the tree walker through a bridge (TD-46); `p1a_arith` 64 to 26 ms, `p1b_calls` 41 to 16 ms.

*Stage B5.3 (2026-10-20):* lists, maps, sets, indexes and stores, `<+`, `.count()` and `.length()`, interpolation, `for` over a list, a map, a set or a string, the names of the aspect (`loadg`), the process `main` with `recover`, `retry`, `resume` and `finalize`, safe points; a fast case with the tree walker as the exact slow case (`xref`). 326 of 348 test programs run on the bytecode machine from the first line to the last; the others hold jobs, nested aspects, `panic`, private processes, lambdas and a few forms of `for` and `call` (`EVE_BC_TRACE=1` says which). Tests: `test/bytecode` (`python script/bctest.py`). *Open:* B5.4 to B5.6 (classes and closures, tasks, the data language), the typed forms of the instructions, `.evb`. Moved from level 5 to All levels (D-138).

### F-VM-07 Portable bytecode file `.evb`

**Status:** open

Versioned, hashed, with debug lines and capabilities (review `RVM-R05`). Moved from level 7 to All levels (D-138).

### F-VM-13 Engine selection and equivalence tests

**Status:** ✓ done

`--engine tree\|bc` and `EVE_ENGINE`; `runtest.py --both` and `bmark.py --both` run every test and benchmark on both engines and require equal results; `eve --disasm` and the golden listings `test/bytecode/*.lst` (`script/bctest.py`) (R8 of `design/design-bytecode.md`).

### F-VM-14 Sampling profiler

**Status:** ✓ done

`EVE_PROFILE=1` prints the functions with the most samples (Windows, symbols from the `.pdb`); the optimization steps R1 to R4 were chosen with it (`test/bmark/README.md`).

*Open:* Linux and macOS.

### F-VM-08 Embedding API

**Status:** open

The VM as a library with a C ABI (the C ABI is the contract of the embedding) (review `RVM-R07`). Moved from level 6 to All levels (D-138).

### F-DAT-07 Database synchronization

**Status:** open

Keep two databases consistent (manifest).

### F-TLS-10 Package manager

**Status:** open

Library folders, versions, dependencies, a registry.

### F-WEB-04 Web application kit

**Status:** open

Service + EWP feed + browser client, deployment guide.

### F-DOC-06 Compiler course

**Status:** open

The student track: milestones, bytecode, memory, scheduling, WASM (compiler.html).

### F-SPEC-09 Compiler registry and approval

**Status:** open

How a third-party implementation claims a spec version and a level (S6.3, S6.4).

## Dropped features

| Code | Feature | Reason |
|---|---|---|
| F-TLS-11 | Daemon mode | replaced by F-TLS-13, a machine that listens (D-083). |

## Open questions

Decided on 2026-10-08 and removed from this list: the order of the levels (Level 3 modules and classes, Level 4 parallel, Level 5 data language and database, D-122, D-125), the place of the generators (Level 5), generics and traits (Level 4) and the bytecode, `.evb` and the C ABI (All levels), D-138.

- The data types (F-LNG-13, F-LNG-14), the service kind (F-STR-08) and the network features come from the review; each needs a decision before it is specified.
- **The web and `.evb`.** F-WEB-02 (Level 7) runs signed `.evb` code in the browser, and `.evb` (F-VM-07) is in All levels. Does level 7 run source in the browser, or does F-WEB-02 wait for `.evb`?
- Features of Level 3 that are not done: the REPL (F-TLS-02, F-TLS-03), `sort` and search (F-LIB-03), the standard library as modules (F-VM-03), the variables `$EVE_*` (F-STR-04, F-STR-07): confirm that they stay in level 3 or move them.
