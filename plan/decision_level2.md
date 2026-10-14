# Decisions, level 2: a project of a driver and aspects (version 0.1)

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. When a question is answered, turn it into a decision with the date and keep the question text for history. Plan steps reference these ids. **Read cheaply:** `python script/plan.py list` prints every id; `python script/plan.py show D-087` prints one entry from here or from `archive/` (settled entries, full text); `python script/plan.py status` lists what is open.

The log is split by level; ids are shared and keep counting across the files (an id not found here is in another file). A new entry goes to the file of its topic. The levels are in [version_map.md](version_map.md). Settled and implemented entries move to [archive/decision_level2.md](archive/decision_level2.md); this file keeps the scope, the newest decisions and the open questions.

## Scope

Level 2 tests a project of **one driver and its aspects** (`test/level2`, prefix `b`). A driver calls an aspect with `apply`, passes arguments by position, by name and by spreading, reads results from its `@` outputs, and recovers the errors that the aspect raises. The aspect is a file in `asp/` with its own state, created at each call, and its own procedures and functions, which level 1 already teaches for a driver (b30, b31, b32, b33 to b39). **Lambdas and closures** are also level 2 (D-109), with `apply` and aspects: they use the subprograms of an aspect.

Features: F-STR-02 (aspects, serial), F-STR-04 (project folders, `asp/`), F-STR-05 to F-STR-07, F-LIB-01 (`log_err`, `log_wrn`). Not in level 2: modules, imports, libraries, classes and methods across files (**level 3**, D-112); parallel groups and concurrent aspects (level 4, D-090); the machine and the server (level 6).

Consequence: with no modules, an aspect is self-contained. It can't apply another aspect (D-066) and has no module to share code with, so shared code waits for level 3.

## Where the earlier decisions are

All settled, in the archive (`python script/plan.py show <id>`): D-066 (an aspect is an encapsulated machine with one `main`), D-072 (aspect errors, import forms, extension methods, test folders), D-073 (a test is a project folder), D-068 (modules, now level 3), D-082 (`eve --doc`, implemented), D-113 (trace, extension methods in an aspect) and D-114 (the run log), implemented, D-090 (`exclusive aspect`, `concurrent aspect`), Q-022 (answered, D-112). D-083 (the Eve machine) moved to [decision_level6.md](decision_level6.md).

- Q-011 Default visibility of a module-level method (answered 2026-09-30 → D-035)
- Q-020 Level 2 suite: what must be decided first
- Q-021 Suspended methods, `yield` and cooperative multitasking
- Q-022 Assumptions of the level 2 tests b01 to b19
- D-026 No coroutines: generators, threads, suspended methods
- D-031 Topology page answers
- D-035 Module-level visibility: `.` is public, no prefix is private
- Q-037 Shape of the stack trace of an aspect error
- Q-038 Where an aspect may extend a class
- Q-039 Signature of the log file names
- Q-040 Shape of the JSON log
- D-042 `apply aspect.main(args);` names the process
- D-043 Single main process in a driver; aspects host named processes; `start` replaces `begin`
- D-046 `parallel` uses `do` and `done`; `fork` and `join` removed
- D-047 Parallel methods inside a process; aspects run serially; BSP
- D-050 Concurrency is not implemented in version 1
- D-051 No asynchronous methods; one concurrency tutorial with groups, BSP and channels
- D-052 Processes raise errors; env variables; REPL moved to the manual
- D-053 Library in Eve, documented by eved
- D-055 Processing answers: interruptions, raise, aspects, command line
- D-056 `external` declarations; exception.eve
- D-057 io library: error and warning, log files, $EVE_OUT
- D-066 An aspect is an encapsulated machine with one `main`; parallel blocks start aspects
- D-067 Multitasking: generators with `yield`, parallel aspects, no coroutines
- D-068 Modules page; modules are singletons without public variables
- D-071 Register of system variables
- D-072 Level 2 answers: aspect errors, imports, extension methods, test folders
- D-073 A test can be a folder: a whole Eve project
- D-081 Process end, exit codes, error classes, imports, `defer`, unsafe methods, parallel errors and l
- D-082 `eve --doc` replaces `eved`
- D-112 Level 2 is aspects; modules move to level 3
- D-113 Aspect error trace, extension methods of an aspect, JSON log files
- D-114 The run log: one JSON file per date, one object per run
- D-122 Functions and procedures are level 2, classes and methods are level 3
- D-124 A single-script test is a file, also in levels 2 and 3
- D-133 A test project can have several drivers
- D-134 The smoke test is self-contained and checks the fundamentals
- D-135 The smoke test is organized by feature; the old v tests are removed
- D-136 The tests have pages in the tutorial, generated from the tests
- D-149 Overloading of functions, procedures and methods; the signature
- Q-042 Generic subprograms and overloading: rules added by the specification (answered: D-150)
- D-150 Rules of the generic subprograms and of overloading, confirmed

## D-149 Overloading of functions, procedures and methods; the signature (2026-10-09)
Author decision (2026-10-09), follows D-148 (a lambda has no type list; work that differs by type is written as overloaded functions). Feature F-LNG-21.
- **Overloading.** Several functions, procedures or methods may have the same name when their signatures differ.
- **Signature.** The number of parameters and the types of the parameters; for a function (it has a result) also the type of the result. A procedure has no result: its signature is its parameters only.
- **Compile time.** The signature is selected at compile time, never at run time by the type of a value. The call picks it by the number and types of the arguments; for functions that differ only by the result type, the type expected at the call decides: `new n := parse(s) :Integer;`, `new r := parse(s) :Real;`.
- **Unique.** The call must identify exactly one signature. A call that matches two signatures, or none, is a compile error that lists the candidates; this covers defaults and varargs (`f(x: Integer)` and `f(x: Integer, y := 1)` are ambiguous for `f(5)`).
- **Functions and procedures.** A function name and a procedure name are always distinct: a function and a procedure can not share a name.
- **Methods.** A method without a result (called like a procedure, as a statement) and a method with a result (called like a function, in an expression) may share a name: they are different methods. The place of the call selects one: `log.flush();` as a statement, `new n := log.flush();` in an expression.
- **Version 0.4** (author, 2026-10-09), with the generic functions (F-LNG-20).

## Q-042 Generic subprograms and overloading: rules added by the specification (2026-10-09)
Model proposals written into `spec/syntax/declarations.md#generic-subprograms-and-overloading` as *(proposed)*, and used by the tests e01 to e15.

(a) The type parameters are inferred from the arguments only, not from the type expected for the result: `function make(:T)() => (@result: ()T)` is always called `make(:Integer)()`.

**Answer:** Confirmed (2026-10-09).

(b) The names of the parameters, their defaults and the `@` marks are not part of the signature: `f(a: Integer)` and `f(b: Integer)` are the same signature (a compile error).

**Answer:** Confirmed (2026-10-09).

(c) Processes, constructors, lambdas and function variables are not overloaded.

**Answer:** Confirmed (2026-10-09).

(d) An extension method may overload a method of the class with another signature; with the same signature it is a compile error (it would replace the method, `methods.html`).

**Answer:** Confirmed (2026-10-09).

(e) When a generic subprogram and a plain one with the same name both accept the arguments, the plain one wins (it fits exactly), instead of a compile error for an ambiguous call.

**Answer:** Confirmed (2026-10-09).

(f) The messages of the compile errors: `can not infer the type T of make`, `a lambda has no type list`, `ambiguous call of f`, `no signature of half matches`, `report is both a function and a procedure`, `half is declared twice with the same signature`.

**Answer:** Confirmed (2026-10-09).
All correct assumptions. Confirmed by Author.

## D-150 Rules of the generic subprograms and of overloading, confirmed (2026-10-09)
Author decision: the six proposals of Q-042 are confirmed as written. (a) A type parameter is inferred from the arguments only, never from the type expected for the result. (b) The names of the parameters, their defaults and the `@` marks are not part of a signature. (c) Processes, constructors, lambdas and function variables are not overloaded. (d) An extension method may overload a method of its class with another signature; with the same signature it is a compile error. (e) When a generic subprogram and a plain one both accept the arguments, the plain one wins. (f) The compile errors say `can not infer the type T of make`, `a lambda has no type list`, `ambiguous call of f`, `no signature of half matches`, `report is both a function and a procedure`, `half is declared twice with the same signature`. Applied: `spec/syntax/declarations.md#generic-subprograms-and-overloading` (the *(proposed)* marks are removed), `tutorial/methods.html`, tests e01 to e15.

## Q-058 The unified aspect: one executable kind, no driver, no macro, no free script (2026-10-14) (answered 2026-10-14 → D-179)
Author proposal (2026-10-14): the aspect is the one unit of execution. A file is an aspect or a module; a "driver" is the aspect the machine runs first, a "macro" is an aspect with shared declarations and several named processes, `apply a(…)` and `start a(…)` run `a.main`, `apply a.p(…)` and `start a.p(…)` run a named process, and inside an aspect a process starts its siblings by their bare names in a `parallel` group. Three rules: race safety of the shared state, a bounded task tree, arguments by value. It replaces D-012, D-037, D-040, the scopes of D-043, D-066, the free script of D-014, D-091 and D-126, and D-152; D-140 is adjusted (depth from the root). Plan, rules made precise and the size of the work: `plan/design-unified-aspect.md`. To decide, recommendation first: (a) a process with a leading dot is public (`process .ingest`), `main` always, the others only for siblings; or every process public. (b) one aspect per file; or private helper aspects in the file. (c) `exclusive`/`concurrent` per aspect; or per process. (d) any aspect may apply another, cycles are compile errors; or only the root applies. (e) depth as in D-140 counted from the root; or one level only. (f) `eve pipeline.eve:ingest args`; or an option `-e ingest`. (g) `driver` removed, a migration error for one version; or a synonym of `aspect`. (h) free scripts removed, `#!` legal on line 1 of an aspect; or `#!` + statements as a short form of `process main`. (i) level 1 teaches `aspect` with `main`, level 2 named processes, level 4 sibling `start`, F-STR-09 (macro) dropped for F-STR-10.
**Answer:** in `plan/design-unified-aspect.md` §4 of 2026-10-14, recorded as D-179: aspects are called by name only, `main` is the one entry point, the other processes are private; macros stay, free scripts and `#!` go; 3 levels of calls, no cycle.

## D-179 The unified aspect: no `driver` keyword, no free script, private processes (2026-10-14)
Author decision, answers to Q-058 (the author's own words are in `plan/design-unified-aspect.md` of that date). Replaces D-012, D-037 and D-040 (the `driver` header), the driver scope of D-043, the free script of D-014, D-091 and D-126, and the `#!` of D-152; refines D-066 and D-140.
- **One kind that runs.** A script is an aspect (one, or several in a macro) or a module. `driver` is no longer a keyword: any aspect can be a driver, and "driver" stays in the text as a role, the aspect that is run first and calls the others.
- **Encapsulated (D-066 kept).** An aspect is called by its name only (`apply a(…)`, `start a(…)`), `process main` is its one public entry point, and the dot is never applied to an aspect. Every other process of the aspect is private: only the processes of the same aspect call it, by its bare name; started ones run on the state of the aspect and use only its thread-safe names. `exclusive`/`concurrent` stays a word of the aspect (D-090, D-130).
- **Calls.** Any aspect may apply or start another. An aspect can't call itself and no chain of calls comes back to an aspect in it (compile error). At most 3 levels: the root aspect, an aspect it calls, and one called from there.
- **Free script and `#!` removed.** Line 1 is a `#` title or a `##` subtitle, or the code itself. Eve does not compete with Bash or Python as a shell script language.
- **The Eve macro stays** (D-152): shared declarations and several aspects in one file, for demos and tests; its driver is its `primary aspect` (D-180).
- Rules made precise and the plan of the work (steps U1 to U8): `plan/design-unified-aspect.md`. Not yet applied.

## Q-059 The details of D-179: the driver of a macro, private processes and levels (2026-10-14) (answered 2026-10-14 → D-180)
(a) A macro has no `driver` keyword any more: which of its aspects does `eve file.eve` run? Recommended: the aspect that has the name of the file (the tests already name the driver like the file, D-133); without one, a compile error. Other: the last aspect of the file; or the one aspect that no other aspect of the file calls. (b) Does a private process count as a level? Recommended: an `apply` of a private process does not (it is serial, like a procedure call); a `start` of one counts as a task level for the limits of D-140, so an aspect of level 3 may not start its private processes. Other: private processes never count.
**Answer:** (a) a `primary` aspect is the entry point of a macro; (b) only a call of an aspect is a level, never a private process. Recorded as D-180.

## D-180 `primary aspect`: the entry point of a macro; levels count aspects only (2026-10-14)
Author answers to Q-059. Refines D-152 and D-179.
- **`primary aspect name is`.** In a macro the entry point is marked with `primary` in front of `aspect`, in the place of `exclusive` or `concurrent`: a primary aspect is neither. `primary` is used only in a macro. A macro has exactly one primary aspect; none or two is a compile error, and `primary` in a file with one aspect is a compile error. `eve file.eve` runs its `main`; it is the root of the run, so no aspect applies or starts it.
- **Levels.** Only an `apply` or a `start` of an aspect makes a level (3 at most, D-179); a call of a private process, applied or started, never does. In a macro the calls between its aspects count like any other.
- **Serial.** A primary aspect exists only in a macro and is serial: its processes are exclusive (applied, never started), but its parallel groups start aspects (author, 2026-10-14).
- **Reserved.** `primary`, `exclusive` and `concurrent` are reserved keywords, all three of the same design (D-090); `primary` goes into `spec/lexical/keywords.json` with them.
- Details: `plan/design-unified-aspect.md` rules 2, 7 and 8. Not yet applied.
