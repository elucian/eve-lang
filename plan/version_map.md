# Version map and features

Two different things are numbered here, and they are never mixed: a **level** is a group of features (Level 1 to Level 7) and a **version** is a release (Version 0.1 to Version 1.0). A level is tested by `test/levelN/`; a version is released when its levels pass. Each version completes one or two levels: a level is a group of features with its own decision log (`plan/decision_levelN.md`) and its own conformance tests (`test/levelN/`). Each version below lists its features, with their codes and status, and an exit criterion. A version is released by `script/release.py` when every feature of its section below is `✓ done`.

This file is the one place to track the project: the levels, the versions and **every feature** with its status. The decisions are in `plan/decision_level1.md` to `decision_level7.md`, the steps of the plan in `plan/phase-*.md`.

## How to read the features

- Each feature has a stable code `F-<area>-<nn>` (areas: SPEC specification, LNG language, STR structure, MTK multitasking, VM virtual machine, TLS tools, LIB library, DAT data, NET network, WEB web, DOC documentation). Codes are never renumbered or reused; a dropped feature keeps its line, with the reason.
- **Status**: `✓ done` means implemented in `bin/eve.exe` (or delivered, for documents and tools) and covered by tests where tests apply; `partial` says in the description what exists; `open` is not started; `dropped` is not wanted any more.
- A feature belongs to **one version**. Moving it is changed here, in its section, and noted in the description with the decision.
- A new large feature is added here first, then planned in a phase file, then decided (`D-nnn`), then built.
- Status checked on 2026-10-09: level 1 65/65, level 2 63/63, level 3 50/50, level 4 42/42 (stage A of D-144: one core, deterministic), smoke 16/16: 235 tests pass on the VM; the benchmarks are in `test/bmark`.

## Levels

| Level | Topic | Released in | Decisions | Tests |
|---|---|---|---|---|
| Level 1 | the language of a single script (no user subprograms and no classes, D-122) | Version 0.1 | [decision_level1.md](decision_level1.md) | `test/level1` (a) |
| Level 2 | a project: functions, procedures, lambdas and closures (D-122), and aspects | Version 0.1 | [decision_level2.md](decision_level2.md) | `test/level2` (b) |
| Level 3 | modules and imports, local libraries, then classes and methods (D-122) | Version 0.2 | [decision_level3.md](decision_level3.md) | `test/level3` (c) |
| Level 4 | parallel processing and streams, generics and traits (D-138) | Version 0.3 | [decision_level4.md](decision_level4.md) | `test/level4` (d) |
| Level 5 | data language (types, records, generators, files, formats, HTTP client), database layer and the Eve database (D-125) | Version 0.4 | [decision_level5.md](decision_level5.md) | `test/level5` (e) |
| Level 6 | the Eve machine and the server | Version 0.5 | [decision_level6.md](decision_level6.md) | `test/level6` (f) |
| Level 7 | web: HTML and WebAssembly; the RAD Workbench eveux, written in Eve, the final test (D-154) | Version 0.6 | [decision_level7.md](decision_level7.md) | `test/level7` (g) |

## Versions that were named before

The decisions used several scales. They map to this one as follows:

| Old wording | Where | Version here |
|---|---|---|
| "0.1", "version 1", "not in 0.1" | D-050, D-031 | Version 0.1 is the first release; "not in 0.1" features are placed below |
| "version 2" (generators, module `task`) | D-067 | generators: Version 0.4, level 5, with the data language (D-125); `task`: Version 0.3, level 4 *(to confirm)* |
| "about 0.9" (VM modes: REPL, service, exclusive) | D-031, TOP-14 | REPL Version 0.2, the listening machine Version 0.5 (D-083) |
| "planned" (parallel aspects, channels) | D-050, D-051, D-066 | Version 0.3, level 4 |

The spec version follows the release: Eve spec 0.1 is the spec of release 0.1. Version 1.0 freezes the language; until then a minor version may change the syntax, but only through a decision and a migration script.

## Overview

| Version | Levels | Name | Goal | Features done | Status |
|---|---|---|---|---|---|
| Version 0.1 | Levels 1 and 2 | Core client | Run a project: one driver and its aspects, error recovery across `apply`. | 23 of 33 | in progress |
| Version 0.2 | Level 3 | Modules and classes | Programs in several files: modules and imports, local libraries, classes and methods (D-122, D-125). | 4 of 13 | in progress |
| Version 0.3 | Level 4 | Parallel | Many cores, many waits: parallel groups, channels, streams with back-pressure, region memory. Generics and traits (D-039, D-138). | 0 of 14 | planned |
| Version 0.4 | Level 5 | Data and database | The data language (real data with the right types, files, JSON, CSV, HTTP client, generators) and the ETL core: connections, query streams, bulk loads, transactions per job, checkpoints, lineage, the Eve database and its admin commands. | 0 of 29 | planned |
| Version 0.5 | Level 6 | Server | The Eve machine: setup, remote control of many machines with login and single sign-on, `serve`, services and routes, the API for AI. | 0 of 22 | planned |
| Version 0.6 | Level 7 | Web | Safe HTML and Eve in the browser; the RAD Workbench eveux, written in Eve, as the final test of the language. | 0 of 8 | planned |
| Version 0.7 | Levels 1 to 7 | Bytecode and embedding | The bytecode compiler and VM, the portable `.evb` file and the embedding API with a C ABI; every level passes on the bytecode VM. | 0 of 3 | planned |
| Version 0.9 | Levels 1 to 7 | Release candidate | Package manager, more database drivers, web kit, hardening. | 0 of 3 | planned |
| Version 1.0 | Levels 1 to 7 | Stable | Frozen language, every level passes, registry for other implementations. | 0 of 2 | planned |

## Version 0.1: Core client (levels 1 and 2)

Levels 1 and 2. Goal: Run a project: one driver and its aspects, error recovery across `apply`.

23 of 33 features done.

| Code | Feature | Status | Description |
|---|---|---|---|
| F-DOC-01 | Tutorial, language part | partial | the topic pages reviewed and consistent with the decisions (phase 1, T1.10). *Partial:* 38 topic pages and the generated pages of Phase 8 (demos, feature tests, smoke and performance); a few pages still describe old forms. |
| F-DOC-04 | Compiler manual | partial | implement, usage, generated feature tables, implemented features (phase 7). *Partial:* `manual/usage.md`. |
| F-LIB-01 | Console I/O | partial | `print`, `write`, `read`, `error`, `warning`, `log_err`, `log_wrn` (D-053, D-057). *Partial:* `print`, `write`, `log_err` and `log_wrn` (run log, D-114) work; `read`, `error` and `warning` are missing; `io.eve` is a draft. |
| F-LIB-02 | Exception module | partial | `Error`, `Warning`, `raise`, `expect`, `assert`, `warn`, code constants (D-054 to D-056). *Partial:* `raise`, `expect`, `assert` and the `$err_` constants are in the interpreter; `exception.eve` is a draft that is not loaded. |
| F-LNG-01 | Script shapes | ✓ done | aspect with `process main`, title/subtitle header, comments; no free script and no `#!` since D-179 (earlier D-014, D-037, D-040). |
| F-LNG-02 | Declarations and assignment | ✓ done | `let`, `set`, `:=`, `=`, `::` clone, views (D-036, D-049). |
| F-LNG-03 | Expressions and operators | ✓ done | arithmetic, logic, comparison, ranges, membership, precedence (D-019, D-022). |
| F-LNG-04 | Control flow | ✓ done | `if`, `match`, `while`, `for`, `loop … repeat [while c]`, labels, `break`, `skip` (D-034, D-074). |
| F-LNG-05 | Jobs and error recovery | ✓ done | jobs, `recover` with `retry`/`resume`/`abort`, `finalize`, `raise`, `expect`, `over`, `panic`, exit codes (D-020, D-055, D-063). |
| F-LNG-06 | Primitive types | ✓ done | Integer, Natural, Real, Logic, Symbol, String, ordinals, type checks with `is` (D-032). *Rational, Duration, Time, Date not yet.* |
| F-LNG-07 | Collections | ✓ done | List, Array, Matrix, DataSet, HashMap, Object, slices, builders, deconstruction (D-058, D-064). |
| F-LNG-08 | Strings and interpolation | ✓ done | escapes, text literal `"""`, placeholders `{name}`, `{literal}`, simple expressions and formats `{n % i5}`, code points `{U+H}`, HTML entities `&name;`, regular expressions (subset) (D-060, D-102, D-119, D-120, D-121). |
| F-LNG-09 | Functions and methods | ✓ done | pure functions, `!` functions, procedures, `@` parameters, defaults, varargs, named arguments, lambdas, closures, recursion (D-025 to D-029, D-048, D-070, D-100, D-101). A lambda is not called where it is written (D-147). Conformity level 2 since D-122. |
| F-SPEC-01 | Lexical specification | ✓ done | tokens, comments, literals, escapes, placeholders, keywords, operators, delimiters as Markdown + JSON (`spec/lexical/`, `keywords.json` D-094; code points `{U+H}` D-119; checked by `script/speccheck.py`). |
| F-SPEC-02 | Grammar (EBNF) | ✓ done | declarations, statements, expressions, modules and imports (`spec/syntax/grammar.md`), checked against every `.eve` test by `script/grammarcheck.py` (199 of 199 files of levels 1 to 4 and the smoke test). |
| F-SPEC-03 | Core semantics | partial | types, scopes, control flow, jobs and `recover`, topology, collections and objects. *Partial:* `semantics/` has variables, types, control, errors, aspects, modules and data-types (a proposal); scopes, topology and collections are missing. |
| F-SPEC-07 | Machine-readable tables with schemas | ✓ done | JSON schemas, `script/speccheck.py`. |
| F-SPEC-08 | Conformance levels | partial | level 1 (a single script), level 2 (functions, procedures, lambdas, aspects), level 3 (modules, classes), levels 4 to 7 (parallel, data and database, server, web; `plan/version_map.md`, D-122, D-125), with the expected-output convention (Q-005). *Partial:* suites of levels 1 to 3 done, level 4 has 3 tests, a smoke test and benchmarks exist (D-135); levels 5 to 7 are empty. (Version 0.1 (levels 1–2), v0.2 (level 3), v1.0 (levels 4–7)) |
| F-SPEC-10 | Licenses and trademark | ✓ done | BUSL-1.1 code, CC BY-NC-SA 4.0 spec and documents, TRADEMARK.md (D-061, D-062, D-078). |
| F-STR-02 | Aspects (serial) | ✓ done | `apply`, state per call, `@` outputs, named and spread arguments, errors and `over`/`panic` across `apply`, `exclusive` by default, `concurrent` kind (D-066, D-090, D-130; tests b01 to b29). |
| F-STR-05 | Command-line parameters of a script | partial | `-p`/`--param` mapped to `main` parameters, `eve script.eve -h` from `** @param` comments (D-055). *Partial:* the arguments after the script name go to `process main`; `-p` and the generated help are not implemented. |
| F-STR-06 | Configuration files | partial | `.cfg` with `$key = value`, loaded with `-s` (D-031). *Partial:* `-s` is accepted by the command line, the `setup` command is a stub. |
| F-STR-07 | System variables | partial | the register (`$error`, environment names such as `$HOME`, `$epsilon`, `$err_`/`$wrn_` constants) (D-071). *Partial:* `$error`, `$epsilon` and the `$err_`/`$wrn_` constants work; the environment names and `$EVE_*` are undefined. |
| F-TLS-01 | Command line (CLI) | ✓ done | `eve script.eve`, `--check`, `--execute`, `-h`, `-v`, `-s`, `-d`, `-x`, `-i`, `-t`, exit codes 64–66 (`manual/usage.md`). |
| F-TLS-05 | Command files and serve mode | ✓ done | (scheduled for removal, replaced by F-TLS-13, D-083): `.vmc` slot, workflow commands `load`, `parse`, `run`, `errors`, `ast`, `inspect`, `status` (D-063). The tests v01 to v11 were removed (D-135): no test covers it now. |
| F-TLS-06 | Test runner | ✓ done | `script/runtest.py` for levels, project tests, several drivers per project (D-133), `/*@expect*/` blocks, reports in `temp/output/`, the status in `status.json` and in each `readme.md` (D-009, D-073, D-094). |
| F-TLS-07 | Documentation generator `eve --doc` | ✓ done | Markdown from `**` comments and signatures, a command of the VM (D-053, D-082). |
| F-TLS-16 | Smoke test | ✓ done | 16 small scripts, one feature each, in less than a second, independent of the other tests (`test/smoke`, D-134, D-135). |
| F-TLS-17 | Benchmarks | ✓ done | one per level with a twin in Python, a history of the runs (`script/bmark.py`, `test/bmark`). Levels 1 to 3 measured. |
| F-TLS-18 | Tutorial pages of the tests | ✓ done | `features.html` and `quality.html` generated from the tests and the benchmarks (`script/genpages.py`, D-136). |
| F-VM-01 | Lexer and parser | ✓ done | source to syntax tree, errors with file, line and column (`lexer.zig`, `parser.zig`). |
| F-VM-02 | Tree-walking interpreter | ✓ done | runs levels 1 to 3, the smoke test and the benchmarks (`interp.zig`, `project.zig`); 193 tests. |
| F-VM-10 | Cross-platform releases | partial | Windows, Linux, macOS binaries from one build; `script/release.py` bumps versions. *Partial:* Windows build, release script. |

Exit: level 1 and level 2 pass; `spec/` has the grammar and the semantics of every tested feature (no test relies on an unanswered `Q-nnn`); binaries for Windows and Linux.

## Version 0.2: Modules and classes (level 3)

Level 3. Goal: Programs in several files: modules and imports, local libraries, classes and methods (D-122, D-125).

4 of 13 features done.

| Code | Feature | Status | Description |
|---|---|---|---|
| F-DOC-05 | Library reference | partial | generated by `eve --doc` for every standard module. *Partial:* io, exception. |
| F-LIB-03 | Strings, math, collections and type conversions | partial | `split`, `join`, `format`, `parse`, `floor`, `round`, sort, search (S5.1). *Partial:* `split`, `join`, `length`, `count`, `parse`, `floor`, `ceiling`, `round`, `abs`, `min`, `max`, `sqrt` work; sort and search are missing. |
| F-LNG-10 | Classes | ✓ done | attributes, constructors, `new`, methods with `@self`, inheritance, visibility; a class hosts only methods and only a method has `@self` (D-036, D-123). Conformity level 3 since D-122. |
| F-LNG-15 | Typed exceptions | partial | error classes with fields, `recover` by type, exit-code mapping (review `RST-R01`). *Partial:* `$error` with code, message, line and job, the codes `$err_*`, exit codes 1 to 4; `exception.eve` is a draft that the VM does not load. |
| F-LNG-16 | Static checks | partial | name resolution, arity, visibility and type errors before the run (exit 65). *Partial:* undefined names, constants, `apply` arguments, exports, free statements in modules, managed modules and concurrent aspects (`check.zig`, `project.zig`); the type checks are few. |
| F-LNG-19 | Managed and direct modules | ✓ done | `managed module` / `direct module` (default), per-member thread safety proved by the compiler, a concurrent aspect calls only safe members (D-129). Tests c26 to c30, c33, d01 to d03; a bare name from `m(*)` or `*` is checked like `m.name`. |
| F-SPEC-04 | Library specification | partial | built-ins and standard modules as signatures (`spec/library/`). *Partial:* `library/atomic.md`. |
| F-STR-01 | Modules and imports | ✓ done | `module`, `from … use (…)`, aliases, `m(*)`, `(*)`, singletons, `initialize`/`recover`/`finalize`, `export`, private members, circular imports, `$err_module` (D-041, D-068, D-072, D-112, D-126, D-131; tests c01 to c31). A module is identified by its file, whatever the spelling of the path (c32). *Open:* the standard library is not searched. |
| F-STR-03 | Extension methods | ✓ done | `method name(@self: Class)` outside the class (D-072, D-086; tests c09, c11). |
| F-STR-04 | Projects and search paths | partial | project root `$EVE_HOME`, `asp/`, `lib/`, `data/`, `web/` (templates), `out/`, `$EVE_LIB`, `$EVE_LIB_PATH` (D-055, D-073, D-128, D-131). *Partial:* `asp/`, `lib/`, `out/` and `EVE_LIB_PATH` from the environment work; the variables are not readable from a script; `data/` and `web/` wait for level 5. |
| F-TLS-02 | REPL | partial | prompt, file completion, commands `check`, `execute`, `help`, `quit`; *2026-10-13:* the full-screen interface at a terminal (upper part with scrollback, command line between two rules, status bar with Ready / Running / time of the last run, Page Up and Down, resize), `help` as a table with a line between commands and `help <command>` pages that wrap to the window (`EVE_WIDTH`, `eve_width`), `clear`, `stop`, `listen`, `serve`, `status`, `eve <command>` without the prompt. *Partial:* `compile`, `debug`, `begin`, `enter`, `print`, `resume`, `setup` not implemented. |
| F-TLS-03 | Interactive interpreter | open | evaluate Eve statements and expressions typed at the prompt, keep the session scope. |
| F-VM-03 | Library loader and `external` bindings | partial | load `.eve` library modules and bind `external` declarations to Zig (D-053, D-056). *Partial:* project modules are loaded (`project.zig`); `external` is not implemented, `print` and the exception names are built into the interpreter. |

Exit: levels 1 to 3 pass (modules c01–c09 and c18–c31, classes c10–c17 included): done on 2026-10-08, 50 of 50. Open for the release: the open features above.

## Version 0.3: Parallel (level 4)

Level 4. Goal: Many cores, many waits: parallel groups, channels, streams with back-pressure, region memory. Generics and traits (D-039, D-138).

4 of 14 features done (2026-10-08, stage A of D-144), 5 partial.

| Code | Feature | Status | Description |
|---|---|---|---|
| F-LIB-12 | Testing module `test` | done | checks that print `ok`/`FAIL`, counters, `summary` that raises (`spec/library/test.md`, `lib/test.eve`, test f03; D-189, 2026-10-18). |
| F-LIB-11 | Logging and observability | open | structured logs, job events, run reports, trace ids (review `RST-R07`, `RNW-R09`). |
| F-LNG-11 | Traits, abstract classes, generics | partial | `trait`, required methods, abstract classes, `class Name(:T)` with `Box(:Integer)(5)`, constraints `(:T <: Comparable)`, library traits `Iterable`, `Stream`, `Comparable`, `Printable` (D-039, D-145, tests d20 to d24). Moved from Version 0.2 to Level 4 (D-138). *Partial:* traits, abstract classes, generic classes with erased type arguments and the library traits work (d20 to d24, d34, d35); a constraint is not checked yet, generic functions wait for Version 0.4. |
| F-LNG-17 | Stream type | partial | `Stream(:T) <: Iterable(:T)`, read by `for` with back-pressure; in Version 0.3 `Channel(:T)` is the stream, and lists get `batch(n)` and `split(k)` (D-142, test d16). Generators, files and queries adopt it in Version 0.4, with `map`, `filter`, `merge`, `window`, `parallel(n)` (review `RMT-R02`). *Partial:* `for` on a channel, `batch`, `split` (d12, d16). |
| F-LNG-18 | `Atomic(:T)` | partial | a class of the standard library that wraps the atomic of the machine, for Logic, numbers, references and ordinals; `class Name <: Atomic(:T)` (D-132). *Partial:* the declaration and the check of managed modules work, the value is a plain value; the operations (`add`, `get!`, `swap!`) need threads. |
| F-MTK-01 | Parallel aspects | ✓ done | `parallel … do start … done`, barrier, data rules, errors as a job (D-066). *Done (stage A):* groups, labels, data rules, one owner per output (compile and run time), output in the order of start, ParallelError, nesting of one level; tests d04 to d11, d25 to d27, d31, d32. |
| F-MTK-02 | Worker pool and scheduler | partial | `$cores`, M:N, a waiting aspect gives its core away (D-067). *Partial:* stage A, one core with a baton (task.zig): a waiting task gives the core away; `$cores` and `$max_parallel` wait for stage B. |
| F-MTK-03 | Channels | ✓ done | `Channel(:T)`, send, receive, close, pipelines, deadlock detection, time-out (D-051). *Done:* send, receive, close, count, `senders`, automatic close, ChannelError 46, deadlock report, `$timeout`; tests d12 to d14, d28 to d30. |
| F-MTK-04 | Tasks in a job | ✓ done | `async` subprograms, `spawn`, `await`; the tasks of a job share its core (D-104, D-143, tests d17 to d19). The module `task` (`round_robin`, `until`) moves to Version 0.4 with the generators (D-144). *Done:* tests d17 to d19, d33. |
| F-MTK-05 | Deadlines and cancellation | ✓ done | per-group time limits, cancel or collect errors (review `RMT-R01`). *Done:* `on error cancel`, `within`; tests d10, d11. |
| F-SPEC-05 | Multitasking semantics | partial | `semantics/multitasking.md`: parallel groups, channels, tasks in a job, durations, determinism (D-140 to D-144). *Partial:* generators wait for Version 0.4. |
| F-TLS-04 | Debugger | partial | debug mode, `halt` breakpoints, step, print variables, reports (`manual/usage.md`). |
| F-TLS-08 | Formatter and linter | open | `eve fmt`, `eve lint` (indentation, style rules; review `RSY-R06`). |
| F-TLS-09 | Editor support | partial | syntax colors for VS Code and GitHub, then a language server (`tools/TODO-vscode-plugin.md`). *Partial:* tutorial highlighters `eve1.js`, `eve3.js`. |
| F-VM-05 | Region memory | partial | arena per aspect call, job and request; long-lived heap for modules and channels (review `RVM-R02`). *Partial (D-151):* the values are reference counted and freed at the safe points of their region (statement, pass of a loop, `done`), a tracing collector frees cycles at `done`, scratch memory per statement; nothing is freed while tasks run; benchmarks peak at 4.4 to 6.6 MB (`p4a_parallel_sum` 39 MB). Open: an arena per task. |

Exit: parallel tests are deterministic over 100 runs; a pipeline with more stages than cores completes.

## Version 0.4: Data and database (level 5)

Level 5. Goal: The data language (real data with the right types, files, JSON, CSV, HTTP client, generators) and the ETL core: connections, query streams, bulk loads, transactions per job, checkpoints, lineage, the Eve database and its admin commands.

0 of 29 features done.

| Code | Feature | Status | Description |
|---|---|---|---|
| F-DAT-01 | Database layer | partial | connect, parameterized query as a stream, execute, transactions, bulk load (databases.html; review `RIO-R02`). *Specified and taught (2026-10-10):* `spec/library/database.md`, `databases.html`; the VM has none of it yet. *Partial (2026-10-11, test e56):* `database.connect` of a `sqlite://` connection in `eve.cfg`, `script`, `execute!`, `query!(:T)`, `query_one!(:T)`, `close`, a job as a transaction (commit at `done`, rollback on error), `csv.read!(:T)` and `json.write` (`.json` array, `.jsonl` lines); results are lists, not streams; no `table`, ORM, `load!`, `commit;` or other drivers. |
| F-DAT-02 | Database drivers | open | PostgreSQL and SQLite first (SQLite for external files; Eve data goes to `evedb`, D-159), then MySQL; Oracle is postponed (`plan/backlog.md`). (Version 0.4 (PostgreSQL, SQLite), v0.9 (others)) | *PostgreSQL (2026-10-17, D-186):* the Eve driver `postgres://` (`evedb/src/pgclient.zig`, `pgdriver.zig`): logins trust, password, md5, SCRAM-SHA-256; `execute!`, `query!`, `query_one!`, `script`, jobs; not yet the ORM, TLS, a pool; tested against evedb (`test/level6/f01_pg_driver`).
| F-DAT-03 | ETL pipeline model | open | extract, transform, load with jobs and aspects; dead-letter output; the pattern taught in the tutorial (review `RIO-R04`). *Specified and taught (2026-10-10):* `spec/semantics/data-types.md`, `etl.html`; the VM has none of it yet. |
| F-DAT-04 | Checkpoints and restart | open | resume a failed pipeline at the last committed batch (review `RIO-R05`). *Specified (2026-10-10):* checkpoints in the target database, `commit;` in a job (`spec/library/database.md#transactions`). |
| F-DAT-05 | Columnar tables | open | `Table` type with typed columns, Arrow-compatible (review `RTY-R06`). |
| F-DAT-06 | Data lineage and run reports | open | inputs, outputs, row counts, durations per job and aspect (review `RIO-R06`). |
| F-DAT-08 | The Eve database | open | the core database: one per project in its `db/` folder (default `local.db`, name set in `eve.cfg`, system variable `$EVE_CORE_DB`, D-156), SQLite embedded (3.54.0, compiled into the VM from the amalgamation, `evevm/src/sqlite.zig`; DuckDB is not in the VM: it is the separate test database `evedb`, F-DAT-12), for checkpoints, run history, lineage and metadata, never ETL data (staging and the cache are `evedb` databases, D-159) (`plan/design-database.md`). |
| F-DAT-09 | Database admin commands | open | `db list`, `db add`, `db test`, `db info`, `db tables`, `db describe`, `db sql`, `db create`, `db backup`, `db restore`, `db export`, `db import`, `db compact`, `db runs`. *Specified (2026-10-10):* the list in `spec/library/database.md#admin-commands`, with `db create-table`, `db prepare`, `db activate`, `db reindex`, `db cache`. |
| F-DAT-10 | Schema migrations | open | numbered SQL scripts in `db/migrations/<name>/`, applied by `db migrate` and recorded in the Eve database. |
| F-DAT-11 | Record-table mapping | open | `table` declarations binding record classes to tables, tracked records with dirty fields, updates of the changed fields only, mapping validated in debug mode and refused in production (`plan/design-database-core.md`, Q-046). *Specified and taught (2026-10-10), as proposed in Q-046:* `spec/library/database.md`, `databases.html`; review points in `plan/review_level5.md`. |
| F-DAT-12 | evedb, the Eve test database | partial | a database server in Zig around DuckDB, outside the VM, that speaks the database frames of EWP; the remote database of the level 5 tests, with fault injection and a statement log (`evedb/README.md`). *Partial (2026-10-18):* detailed design in `evedb/README.md`; version 0.3 (D-187): column batches on the native protocol (`QUERYB`, `LOAD` into DuckDB's Appender), the driver `evedb://` with `Memory.store` and `Memory.load`, measured by `script/evedb_bench.py` (1,000,000 rows into a `Memory` table in 0.23 s; a group-by 55 times faster than SQLite), `test/level6/f02_evedb_columnar`; triggers and stored procedures in evedb dropped. Version 0.2 (D-186): evedb answers the **PostgreSQL protocol** on port 5432 (logins trust, password, md5; simple and extended query; types, errors, transactions), a configuration file, `eve db serve` and `eve -s -db --serve`; tested by `script/pg_check.py` (psycopg2, pg8000) and `test/level6/f01_pg_driver`; stored procedures and triggers in Eve designed (version 0.3). Version 0.1 built: the server of the EWP-db frames, sessions with leases, `eve_tx` and `STATUS`, error classes, seven faults, the statement log, tokens, and the commands `serve`, `create`, `sql`, `describe`, `snapshot`, `reset`, `status`, `stop`; 16 unit tests and 66 protocol checks in Python (`script/evedb_check.py`). Not yet: the Eve driver `evedb://`, change sets (`CHANGES`/`APPLIED`), `BATCH`/`CREDIT`, the appender, `drift`, import and export, service mode (0.2). |
| F-DAT-13 | `sql function` | partial | an Eve function marked `sql function` is registered on every SQLite and DuckDB connection and called from SQL; deterministic, one result, SQL types, not overloaded; SQL `NULL` only for nullable types; an error stops the query with `$err_sql` (code 59) (D-166, `spec/library/database.md#sql-functions`). *Partial (2026-10-12):* SQLite done, tests e96 to e101; DuckDB waits for the VM to load it (D-166). |
| F-DAT-14 | Stored procedures | partial | native procedures in `sql/` called through `external` signatures; Eve procedures in `proc/`, run by the database part, listed by `eve db proc list`, reloaded by `eve db proc reload`, called by `db.call` (D-166, `spec/library/database.md#stored-procedures`). *Partial (2026-10-12):* a module of `proc/` is imported and its `sql function`s registered, `eve db proc list`; tests e102, e102_test1. Not yet: `external` at run time (no database with stored procedures in the tests), `proc reload`, `db.call`. |
| F-VM-11 | One `eve`, its source in modules | partial | the modules `evecm`, `evecp`, `evevm`, `evedb`, `eveux` and `cmd` with one build; one binary whose first word chooses the part, `eve vm`, `cp`, `db`, `ux`; the serving machine as one process (D-163, D-164, `plan/design-packages.md`; phases A and B). *Partial (2026-10-13):* the modules `evecm`, `evecp`, `evevm`, `evedb` and `cmd` exist in one root build (arrows checked by the build); the values and the heap are in `evecm`; the database layer is `evedb` behind the interfaces `Host` and `Data`; the configuration and the wire are cut from `server.zig`; not yet: the cut of the machine and of `cli.zig`, the native calling convention, `eveux` and `evetx` in the root build, the part words (`plan/design-packages.md` §13). |
| F-DOC-02 | Tutorial, data client part | open | files, formats, streams, HTTP client, ETL pipelines (review `RTU` phase T1). |
| F-LIB-04 | Files and paths | open | `fs` and `path` modules, text and bytes, line streams, globbing (review `RIO-R01`). |
| F-LIB-05 | Data formats | open | JSON and CSV read/write, decode into records; later XML, Parquet. |
| F-LIB-06 | Time and dates | open | `now`, parse, format, zones, durations. |
| F-LIB-07 | Shell commands | partial | `call` with pipes, and a safe `run(cmd, args, cwd)` (command.html; review `RIO-R03`). *Partial (2026-10-18, D-189):* module `os` with `run!` (no shell), `env!`, `hostname!`, `pid!`, `platform` (`spec/library/os.md`, test f05). |
| F-LIB-08 | Secrets | open | a `Secret` type and `secret.get` from environment, file or vault (review `RIO-R01`). *Specified (2026-10-10):* `spec/library/data-language.md#secrets`. |
| F-LIB-09 | Compression and archives | open | gzip, zip, stream codecs (manifest). |
| F-LNG-20 | Generic functions and procedures | open | a first parameter list of types, `function largest(:T <: Comparable)(items: ()T)`, called `largest(xs)` (types inferred) or `largest(:Integer)(xs)`; also procedures, methods and processes; no type list on a lambda, overloaded functions instead; possible because self-calling lambdas are removed (D-145, D-147, D-148). Tests e01 to e04, e14, e15 (written first). |
| F-LNG-21 | Overloading | open | functions, procedures and methods share a name with different signatures: number and types of the parameters, and the result type of a function; resolved at compile time, the call must match one signature; a function and a procedure never share a name, a method with a result and one without may (D-149, D-150). Tests e05 to e13 (written first). |
| F-LNG-12 | Generators | open | methods with `yield`, `Generator(:T)`, use in `for` and builders (D-067). |
| F-LNG-13 | Data types for ETL | open | Decimal, Instant/DateTime with zone, Date, Time, Duration, Bytes, Uuid (review `RTY-R01`; needs a decision). |
| F-LNG-14 | Record types and optional values | open | typed records for rows, JSON objects and messages; `T?` (review `RTY-R01`, `RTY-R02`; needs a decision). |
| F-NET-01 | HTTP client | open | requests, headers, JSON bodies, time-outs, TLS (review `RNW-R10`). |
| F-VM-06 | Efficient collections | open | hashed and sorted maps, sets, ropes for Text (review `RVM-R04`). |
| F-STR-09 | Eve macro (hybrid script) | open | one self-contained file: shared declarations and several aspects, exactly one of them `primary`; `apply` (level 2) and `parallel`/`start` (level 4) inside it; a concurrent aspect uses only the thread-safe shared names (D-152, D-180; tests e16 to e22, e108, e109). |
| F-STR-10 | Unified aspect | ✓ done | no `driver` keyword, no free script, no `#!`; the kinds `exclusive`, `concurrent` and `primary`; `main` and private processes; calls between aspects at most three levels deep and without a cycle; a concurrent aspect is called from a primary or an exclusive aspect; a primary aspect is run by a command (D-179 to D-183; tests a04, b15, b24, b45 to b54, c24, d36 to d40, e21, e61, e108, e109). |
| F-STR-11 | `recover` in a function, procedure and method | ✓ done | the end of `recover` handles the error and the routine returns normally; `abort` passes it on; no `recover` in a constructor, generator or lambda (D-192, Q-065; `spec/semantics/errors.md`; tests b55 to b59, c34 to c36; 2026-10-18). |

Exit: JSON and CSV round-trip tests; an HTTP call against a local test server; level 5 passes against the Eve database (SQLite) and a PostgreSQL server; a killed load restarts from its checkpoint; `db backup` and `db restore` round-trip.

## Version 0.5: Server (level 6)

Level 6. Goal: The Eve machine: setup, remote control of many machines with login and single sign-on, `serve`, services and routes, the API for AI.

0 of 23 features done.

| Code | Feature | Status | Description |
|---|---|---|---|
| F-DOC-03 | Tutorial, network and web part | open | client and server, services, protocol, security, HTML, WebAssembly (review `RTU` phases T2, T3). (Version 0.5 –v0.6) |
| F-LIB-10 | Encryption and hashing | partial | hashes, HMAC, symmetric encryption (manifest). *Partial (2026-10-18, D-189):* module `crypto` with sha256, sha512, sha256_file!, hmac_sha256, hex and Base64, random_hex!, same (`spec/library/crypto.md`, `evevm/src/syslib.zig`, test f04); not yet symmetric encryption and password hashing. |
| F-NET-02 | HTTP server | partial | routes, request and response records, static files, one state per request (review `RNW-R02`). *Partial (2026-10-11, D-162):* the machine with its two doors, IPC (`--listen`, was `-lsn` until D-169) and HTTP (`--serve`: the web folder, `POST /rpc`), JSON-RPC methods `ping`, `status`, `run`, `stop`, the client options `-loc` and `-rem` (`spec/library/machine.md`); tests `e95_web_hello` and `e95_test1` to `e95_test3` pass. *2026-10-13:* the machine at the prompt (`listen`, `serve`, `stop`, the doors in threads, one thread per connection), `evevm` (the machine in its own process, log in a file) and `eve -u` (open the web page). Not yet: routes and `service` scripts, HTTPS, login, WebSocket. |
| F-NET-03 | Eve Wire Protocol (EWP) | open | framed binary protocol for Eve-to-Eve calls and data streams, flow control, resumable streams (review `RNW-R04`). |
| F-NET-04 | Remote apply | open | run an aspect on another node with a deadline and an idempotency key (review `RNW-R01`). |
| F-NET-05 | Capabilities and sandbox | open | fs, net, db, shell permissions per project and per aspect (review `RNW-R08`). |
| F-NET-06 | Authentication | open | tokens, sessions, TLS certificates for services. |
| F-NET-07 | Machine login: single sign-on and the keyring | open | from one local machine, a login per remote machine: single sign-on (OpenID Connect), an account of the machine, or a machine token; the renewal token kept in the keyring of the operating system (Windows Credential Manager, Linux Secret Service) after the first login; commands `login`, `logout`, `forget`, `whoami`; users, roles and registration of a listening machine in its Eve database (D-155, `plan/design-service.md` §15, Q-048). |
| F-NET-08 | The machine API | partial | JSON-RPC 2.0 methods named by part: `vm.ping`, `vm.stat`, `vm.run`, `vm.eval`, `vm.suspend`, `vm.resume`, `vm.inspect`, `vm.cancel`, `vm.stop`; `db.*`; the first names of D-162 answered until level 6; no TLS in the machine, a reverse proxy for remote HTTPS; ACP outward (D-165, `spec/library/machine.md#the-machine-api`). *Partial (2026-10-12):* `vm.ping`, `vm.stat` (with the active parts), `vm.run`, `vm.stop` and the first names, `-32601` for another method; test e95_test4. *2026-10-13:* `vm.stat` adds `requests`, `uptime_ms`, `running`, `running_ms`, `web`; `stop` cancels the running scripts. *2026-10-16:* the lasting doors (`spec/library/machine.md#lasting-doors`): the stdio door `eve --stdio` (an IDE starts the machine as its child; over SSH `ssh host eve --stdio`), the IPC connection stays open, `vm.output` notifications (`"stream": true`), sessions `vm.open`, `vm.eval`, `vm.close` (a default session per connection), `vm.shell`, `vm.cancel`, `vm.run` by `path`, `vm.stat` with `door` and `sessions`; `shell <command>` and `!<command>` at the prompt; test e95_test5; evetx uses it for its console. Not yet: WebSocket, `dbg.*`, `db.*` in JSON. |
| F-SPEC-06 | Network semantics and protocol | open | remote `apply`, services, Eve Wire Protocol (`spec/protocol/`). |
| F-STR-08 | Service script kind | open | long-running entry point with routes handled by aspects (review `RNW-R02`; needs a decision). |
| F-TLS-12 | Machine setup | open | `--setup <folder>`, the machine folder, `eve.cfg`, built-in defaults, identity domain + port, external checksum, `setup` reload (D-083). |
| F-TLS-13 | Remote control | open | `--listen`, `eve -c`, `-rem`, `-u` upload (*2026-10-14: the user interface is `-ux` and the terminal IDE `-tx` (D-172); the upload of D-083 is `--upload` (D-171)*), `send` between machines, sessions and driver memory spaces (`load`, `dismiss`); then the removal of `.vmc` command files (D-083; *done 2026-10-18, D-188: a series of commands goes through `eve --stdio` and `vm.eval`*). |
| F-TLS-14 | Local HTTP | open | `serve` on port 8042, pages of the web folder, routes of `service` scripts (D-083). |
| F-TLS-24 | evetx, the terminal IDE: files, editor, run, machines | partial | `eve -tx`: a full-screen TUI on libvaxis (Zig package, no binding); the title and the main menu (click, or Ctrl+Enter; Save and Save As), two searches under the title bar, each above its panel (names that start with the typed letters over the tree, the tree going to the match; code, tables or global data with `*` and numbers over the right panel, with Replace), a `#` button to jump to a line or a record, and the gear of the status bar, the file tree of the project, an editor in tabs, Run, the bottom panel (Console with the design of evevm, Watch, Stderr, Stdout, Breaks), the inset status bar (name, place, `?` help on Ctrl+/, gear), the machine chosen with F1 to F3, connect, the user cache and the select project dialog, upload; no schedules and no run history, those are eveux (F-TLS-21); imports `evecm` only (D-173, D-174, Q-050 to Q-054, `evetx/README.md`, `plan/design-packages.md` step B6). *Partial (2026-10-13, D-178):* a separate program `evetx/` built with `zig build -p ..` (libvaxis pinned for Zig 0.16): the frame, the tree, the editor with Eve colors, the two searches, `#`, the menu, the help, the file card, breakpoints in the gutter, Run and the console through `eve`; not yet the machines F2 and F3, upload, the debugger, the database tabs, Undo (`evetx/README.md` §11). |
| F-TLS-27 | evetx: debugger | open | breakpoints in the gutter and the Breaks tab (remove, double click to jump), Step into, Step out, Continue, Stop, the Watch tab; needs the debugger of the machine (F-TLS-04, Q-053 b); the same API serves F-TLS-22 (D-173). |
| F-TLS-28 | evetx: databases | open | a database file in the tree opens a table list in a tab; the data of a table in a new tab; the structure of a table in a dialog that is a grid with headers and bordered cells, a drop-down for the type, a calendar for the default of a date or time, and pages of fields; needs the `db.*` additions (Q-053 c, d; D-173, D-174). |
| F-TLS-29 | evetx: file card | open | a text file opens in the editor as source (Markdown too); any other file, images, SVG, audio and video included, opens a card with its facts and no preview; the rendered view is in eveux (D-178). |

| F-NET-09 | Credentials, connect and upload | open | two ways to give credentials: the unversioned `eve.env` of the project, or a user name and password or a connection string `username/password@machine_name`; `eve --connect` before `eve --upload`; the upload sends the server side (`web/`, `proc/`, `sql/`, `server/` and what they import: Q-052 a); `eve -rem … db install|migrate`; a remote machine runs only what is on it (D-171, Q-051, `plan/design-service.md` §16). |
| F-TLS-26 | REPL: selected machine | open | `select <machine>`, the machine in the status bar (`Ready: connection: local`), Ctrl+Left/Right and F1 (local), F2, F3 to change machine, Ctrl+Up/Down for the history of commands, `help` and Tab by machine (only stored procedures and code on the server on a remote one) (D-171). |
| F-DAT-13 | The user cache `eve.db` | open | a SQLite cache of the user (`<user data folder>/eve/meta/eve.db`): projects, machines without secrets, history of commands, upload manifest; the `Meta` interface of `evecm`, implemented by evedb; rebuilt if deleted (D-172, Q-052 b). |
| F-TLS-30 | Service mode | partial | `eve -s`: the machine with no user interface, silent, both doors, a log and a pid file; a Windows service under the Service Control Manager, a Linux daemon, or the foreground form (`EVE_SERVICE=foreground`); `-s file.cfg` is the service reading that file, and `-s` takes nothing else; the configuration of a script, a command or a door is `-e file.cfg` (`--setup`), and the command files `.vmc` are removed (D-188, 2026-10-18) (D-185, `plan/design-service.md` section 17, `spec/library/machine.md`). *Partial (2026-10-17):* the console and foreground forms tested on Windows (`script/service_check.py`); the Service Control Manager form compiles, run needs an administrator; the POSIX code compiles for Linux, not run; not yet: Event Log, run as another user, log rotation, `evedb serve -s`. |
| F-TLS-15 | Eve API for AI | open | `eve --api`, an MCP server whose tools are the commands of the machine (D-083). |

Exit: a local machine logs in to two remote machines on `localhost`, one by single sign-on, and connects again from the keyring without a form; a client project and a server project talk on `localhost`; a route answers HTTP; `eve --api` answers an MCP client; `.vmc` files are removed.

## Version 0.6: Web (level 7)

Level 7. Goal: Safe HTML and Eve in the browser; the RAD Workbench eveux, written in Eve, as the final test of the language.

0 of 8 features done.

| Code | Feature | Status | Description |
|---|---|---|---|
| F-VM-09 | WebAssembly build | open | the VM compiled to `wasm32` with host imports (review `RVM-R06`). |
| F-TLS-19 | eveux, the RAD Workbench: shell | open | an Eve project (service script, aspects, modules) run by the local machine, with a browser part in plain JavaScript and CSS: screen and menus, editor with syntax colors for Eve, SQL, JSON, XML and HTML, file dialog and upload, command window, login to remote machines with single sign-on and the keyring, Help and About with the versions; written in Eve as the final test and stress test of the language (D-154, `eveux/README.md`, Q-047). |
| F-TLS-20 | eveux: direct SQL and database tree | open | SQL mode of the command window and SQL tabs, results in a grid with Eve types, Commit and Rollback, the database object tree of the connections of a machine, import wizard (`eveux/README.md` §7, §9, §12). |
| F-TLS-21 | eveux: jobs, logs and admin | open | job browser and scheduler forms over the remote scheduler of every connected machine, live run output, stage view of the aspects, resume from checkpoint, log inspector, admin pages of a machine (`eveux/README.md` §6.6, §10). *2026-10-13 (Q-050): eveux owns schedule management and the management of runs; the schedule methods of the machine API are designed with it; evetx only runs a driver for debug and test (F-TLS-24).* |
| F-TLS-22 | eveux: debugger | open | breakpoints in the gutter, step into, over and out, variable inspector, watch window, call stack; needs the debugger of the machine (F-TLS-04) and the commands proposed in Q-047 (`eveux/README.md` §11). |
| F-TLS-23 | New project | partial | `project init <folder>` and `project new <folder>` (D-160 names it `new project`): `init` also works on an existing project and never overwrites; `new` fails on a non-empty folder. Makes `db`, `log`, `meta`, `data/in`, `data/out`, `test`, `asp`, `lib`, `src`, `doc`, `web`, the files `<name>.eve`, `eve.cfg`, `meta/project.json` and a `.gitignore`, and runs `git init` outside a repository. *Partial:* done and tested (`evevm/src/scaffold.zig`, tests e54, e55); the writer of the minimal fallback log is not written (`plan/design-project-layout.md`). |
| F-WEB-01 | HTML templates | open | `HTML` type, context-aware escaping, template files, components (review `RNW-R05`). |
| F-WEB-02 | Eve in the browser | open | the WASM VM runs signed `.evb` code with limited capabilities, `dom` module (review `RNW-R06`). |
| F-WEB-03 | Tutorial playground | open | a "Run" button on tutorial examples using the WASM VM. |

Exit: tutorial examples run in the browser; templates pass an escaping test suite; the browser VM refuses `fs` and `shell`; eveux passes the tests of `test/level7` and meets its stress goals (`eveux/README.md` §2).

## Version 0.7: Bytecode and embedding (levels 1 to 7)

Levels 1 to 7. Goal: The bytecode compiler and VM, the portable `.evb` file and the embedding API with a C ABI; every level passes on the bytecode VM.

0 of 3 features done.

| Code | Feature | Status | Description |
|---|---|---|---|
| F-VM-04 | Bytecode compiler and VM | open | compact bytecode, heap frames (needed by generators and scheduling; review `RVM-R01`). Moved from Version 0.4 to Version 0.7 (D-138). |
| F-VM-07 | Portable bytecode file `.evb` | open | versioned, hashed, with debug lines and capabilities (review `RVM-R05`). Moved from Version 0.6 to Version 0.7 (D-138). |
| F-VM-08 | Embedding API | open | the VM as a library with a C ABI (the C ABI is the contract of the embedding) (review `RVM-R07`). Moved from Version 0.5 to Version 0.7 (D-138). |

Exit: levels 1 to 7 pass on the bytecode VM and on the tree walker; an `.evb` file made on one machine runs on another; a C program embeds the VM through the C ABI.

## Version 0.9: Release candidate (levels 1 to 7)

Levels 1 to 7. Goal: Package manager, more database drivers, web kit, hardening.

0 of 3 features done.

| Code | Feature | Status | Description |
|---|---|---|---|
| F-DAT-07 | Database synchronization | open | keep two databases consistent (manifest). |
| F-TLS-10 | Package manager | open | library folders, versions, dependencies, a registry. |
| F-WEB-04 | Web application kit | open | service + EWP feed + browser client, deployment guide. |

Exit: no open `Q-nnn` on a feature of 0.1 to 0.6; performance and memory baselines recorded.

## Version 1.0: Stable (levels 1 to 7)

Levels 1 to 7. Goal: Frozen language, every level passes, registry for other implementations.

0 of 2 features done.

| Code | Feature | Status | Description |
|---|---|---|---|
| F-DOC-06 | Compiler course | open | the student track: milestones, bytecode, memory, scheduling, WASM (compiler.html). |
| F-SPEC-09 | Compiler registry and approval | open | how a third-party implementation claims a spec version and a level (S6.3, S6.4). |

Exit: the language is frozen; every level passes; one implementation other than `evevm` is registered against the spec.

## Dropped features

| Code | Feature | Reason |
|---|---|---|
| F-TLS-11 | Daemon mode | replaced by F-TLS-13, a machine that listens (D-083). |

## Open questions

Decided on 2026-10-08 and removed from this list: the order of the levels (Level 3 modules and classes, Level 4 parallel, Level 5 data language and database, D-122, D-125), the place of the generators (Level 5, Version 0.4), generics and traits (Level 4, Version 0.3) and the bytecode, `.evb` and the C ABI (Version 0.7), D-138.

- The data types (F-LNG-13, F-LNG-14), the service kind (F-STR-08) and the network features come from the review; each needs a decision before it is specified.
- **Generators and the bytecode.** F-LNG-12 (Version 0.4) needs a method that can stop and continue, which the tree walker can not do (`design-multitasking.md` §5), and the bytecode VM (F-VM-04) is now in Version 0.7. Either the generators are built on the tree walker (a separate thread or a continuation), or F-LNG-12 moves to Version 0.7. *Proposed by D-144:* the baton threads of stage A give the tree walker a task that stops and continues, so a generator can be such a task and F-LNG-12 stays in Version 0.4.
- **The web and `.evb`.** F-WEB-02 (Version 0.6) runs signed `.evb` code in the browser, and `.evb` (F-VM-07) is now in Version 0.7. Does Version 0.6 run source in the browser, or does F-WEB-02 move to Version 0.7?
- Features left open in Version 0.2 (Level 3): the REPL (F-TLS-02, F-TLS-03), `sort` and search (F-LIB-03), the standard library as modules (F-VM-03), the variables `$EVE_*` (F-STR-04, F-STR-07): confirm that they stay in Version 0.2 or move them.
