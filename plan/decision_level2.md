# Decisions, level 2: a project of a driver and aspects (version 0.1)

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. When a question is answered, turn it into a decision with the date and keep the question text for history. Plan steps reference these ids. **Read cheaply:** `python script/plan.py list` prints every id; `python script/plan.py show D-087` prints one entry from here or from `archive/` (settled entries, full text); `python script/plan.py status` lists what is open.

The log is split by level; ids are shared and keep counting across the files (an id not found here is in another file). A new entry goes to the file of its topic. The levels are in [version_map.md](version_map.md). Settled and implemented entries move to [archive/decision_level2.md](archive/decision_level2.md); this file keeps the scope, the newest decisions and the open questions.

## Scope

Level 2 tests a project of **one driver and its aspects** (`test/level2`, prefix `b`). A driver calls an aspect with `apply`, passes arguments by position, by name and by spreading, reads results from its `@` outputs, and recovers the errors that the aspect raises. The aspect is a file in `asp/` with its own state, created at each call, and its own procedures and functions, which level 1 already teaches for a driver (b30, b31, b32, b33 to b39). **Lambdas and closures** are also level 2 (D-109), with `apply` and aspects: they use the subprograms of an aspect.

Features: F-STR-02 (aspects, serial), F-STR-04 (project folders, `asp/`), F-STR-05 to F-STR-07, F-LIB-01 (`log_err`, `log_wrn`). Not in level 2: modules, imports, libraries, classes and methods across files (**level 3**, D-112); parallel groups and concurrent aspects (level 4, D-090); the machine and the server (level 6).

Consequence: with no modules, an aspect is self-contained. It can't apply another aspect (D-066) and has no module to share code with, so shared code waits for level 3.

## Where the earlier decisions are

All settled, in the archive (`python script/plan.py show <id>`): D-066 (an aspect is an encapsulated machine with one `main`), D-072 (aspect errors, import forms, extension methods, test folders), D-073 (a test is a project folder), D-068 (modules, now level 3), D-082 (`eve --doc`, implemented), D-113 (trace, extension methods in an aspect) and D-114 (the run log), implemented, D-090 (`exclusive aspect`, `concurrent aspect`), Q-022 (answered, D-112). D-083 (the Eve machine) moved to [decision_level6.md](decision_level6.md).

## D-112 Level 2 is aspects; modules move to level 3 (2026-10-07)
Author decisions: the scope of level 2, and the answers to Q-022 (full text in the archive).
- **Scope.** Level 2 is aspects with their procedures and functions (version 0.1). Modules, imports, libraries, classes and methods across files move to level 3 (version 0.2), with the data language. `test/level2` keeps `apply`; the module tests are now `test/level3/c01` to `c09`.
- **Tests renumbered.** Level 2: b01 `apply_aspect`, b02 `apply_output`, b03 `apply_state`, b04 `apply_named_args`, b05 `apply_spread`, b06 `aspect_error`, b07 `aspect_over`, b08 `aspect_panic`, b09 `log_files`. Level 3: c01 `import_module`, c02 `import_string_path`, c03 `import_alias`, c04 `import_members`, c05 `import_all`, c06 `module_lifecycle`, c07 `module_singleton`, c08 `module_private`, c09 `extension_method`. The conflict test (old b06) is deleted.
- **(a) Name conflict.** The failure of `use (*)` on a name conflict is discarded. The risk stays; `export` in modules reduces it (level 3).
- **(b) Private member.** Reading a private member of a module is an error at check time (exit 65); nothing runs. There is no runtime `$err_access` for it, because Eve has no way to build a member name at run time. c08 expects exit 65 and no output.
- **(c) Spread of a map.** `apply add3(a: 10, *m)`: the keys of the map are symbols named like the parameters. Accepted, part of level 2 (b05).
- **(d) Error line.** `$error.line` is the line of the original `raise`, in the aspect file. The stack trace includes the name of the aspect that failed. The shape of the trace is settled in D-113.
- **(e) Extension of an imported class.** A driver may extend a class imported from a module and `use (m(*))` brings the class in as a bare name (c09). In practice classes are extended in modules; a user extends them in aspects (see D-113). Level 3.
- **(f) Log files.** `log_err` and `log_wrn` write `out/error.log` and `out/warning.log`, one message per line. The file names carry a run signature (date of the run). The format is D-113 and D-114.
- **(g) Search paths.** Aspects are found in `asp/` of the project (level 2). Modules are searched in the standard library first, then in `lib/` when the import gives no path; `$EVE_LIB_PATH`, a list of folders separated like the PATH of the operating system, adds more folders (level 3). `$EVE_LIB_PATH` replaces `$EVE_LIB` of the register (D-071) when level 3 is specified.
- **`exclusive aspect`.** The tests write `exclusive aspect name is`, as D-090 requires (the keyword is not an open point).
- Applied: `test/level2`, `test/level3`, `test/readme.md`, `plan/version_map.md`, `plan/features_inventory.md` (F-STR-01 and F-STR-03 to v0.2), `plan/decision_level3.md`. Not yet applied: the tutorial (modules.html says `$EVE_LIB`, and the `use (*)` conflict), `spec/`, the VM.

## Tests of level 2

29 tests (2026-10-07), all pass on the VM (`python script/runtest.py 2`). Positive tests print and check; negative tests (`n`) are a compile error, exit 65, and nothing runs; each was checked to fail with the right message (missing aspect, too many arguments, `apply` in an aspect, unknown parameter, missing argument, wrong type, no kind word, second process, undefined name).

| Code | Test | What it shows |
|---|---|---|
| b01 | `apply_aspect` | `apply` runs `main` of an aspect |
| b02 | `apply_output` | results come back through `@` |
| b03 | `apply_state` | a new state at each `apply` |
| b04 | `apply_named_args` | positional, named, default arguments |
| b05 | `apply_spread` | `*list` and `*map` |
| b06 | `aspect_error` | an error raised again at the `apply` line, `$error.line` |
| b07 | `aspect_over` | `over` in an aspect |
| b08 | `aspect_panic` | `panic` ends the application, exit 1 |
| b09 | `log_files` | the run log, JSON (D-114) |
| b10 | `aspect_function` | a function of the aspect, with an optional parameter |
| b11 | `aspect_procedure` | a procedure changes an aspect-level variable; the driver's variable stays |
| b12 | `aspect_fresh_state` | main and a procedure share a list; the next call starts empty |
| b13 n | `aspect_missing` | `apply` of a missing aspect |
| b14 n | `aspect_too_many_args` | too many positional arguments |
| b15 n | `aspect_apply_aspect` | `apply` inside an aspect (D-066) |
| b16 | `aspect_recover` | an aspect recovers its own error |
| b17 | `aspect_trace` | error first, then frames: function, aspect (D-113); exit 4 |
| b18 | `lambda` | called at once, passed, held by a function type (D-109) |
| b19 | `closure` | two counters made by a function of an aspect (D-101, D-109) |
| b20 n | `aspect_unknown_param` | an argument named like no parameter |
| b21 n | `aspect_missing_arg` | a missing mandatory argument |
| b22 n | `aspect_wrong_type` | an argument of the wrong type |
| b23 n | `aspect_no_kind` | `aspect` without `exclusive` or `concurrent` (D-090) |
| b24 n | `aspect_second_process` | a second process in an aspect |
| b25 n | `aspect_driver_variable` | an aspect reading a driver variable |
| b26 | `aspect_finalize` | `finalize` runs on return and on `over` |
| b27 | `aspect_concurrent` | a `concurrent aspect` applied serially |
| b28 | `aspect_folder` | `apply tools/hello()` before `asp/` |
| b29 | `aspect_output_named` | a mandatory `@` parameter after an optional one is named (D-106) |

Not tested yet: the trace order of `b17` is checked only as presence of the lines (the runner has no ordered check); `$error.trace` and `$error.unit` as variables (not implemented); a spread that fails at run time (the error code is open, `semantics/aspects.md`); `abort` in the `recover` of an aspect; the search in `$EVE_ASP`.

## Open questions

None for level 2.

## D-122 Functions and procedures are level 2, classes and methods are level 3 (2026-10-08)
Author decision. The scope of D-112 ("level 2 is aspects with their procedures and functions") is applied to the tests, which had kept the subprograms in level 1.
- **Level 1** is the language of a single script: the process `main`, variables, types, collections, control flow, strings, errors. It has no user `function`, `procedure`, lambda or class (a class that declares an Ordinal or a Variant stays: a16).
- **Level 2** adds the subprograms: functions, procedures, parameters (by name, default, vararg, `@` output), recursion, `exit`, `over` and `defer` inside a procedure, lambdas and closures (D-109), together with the aspects. Moved from level 1: a24, a25, a56, a64, a65, a69, a70, a71, a72, a73, a79 to b30 to b40 and a61 (variant parameters) to b41. New: b42 `defer_procedure` (the original a74) and b43 `vararg_procedure` (the second half of a60).
- **Level 3** is where modules come first, then the local libraries, and then classes and methods. Moved from level 1: a26 `class`, a40 `extension_method`, a41 `inheritance`, a42 `visibility`, a55 `attribute_outside`, a67 `procedure_in_class` to c10 to c15. The order of the level: modules and imports (c01 to c09), then classes.
- **`defer`** (D-117 g) is a statement of a subprogram, so it moves to level 2: a74 is removed from level 1 and the VM does not run a `defer` at the end of `main`. `keywords.json` is unchanged.
- **Level 1 numbers keep their gaps** (a24, a25, a26, a40 to a42, a55, a56, a61, a64, a65, a67, a69 to a74 and a79 are free); the other tests keep their codes so that the references stay valid. The old codes in D-0xx entries were replaced by the new ones.
- **To do:** the spec files still describe functions and classes as level 1 (`syntax/declarations.md`, `grammar.md`, `statements.md`): mark the parts with the level; the tutorial order (Subprograms before Classes) is as it was; the VM runs the tests of any level and does not gate the features by level.

## D-124 A single-script test is a file, also in levels 2 and 3 (2026-10-08)
Author decision. A test is a folder (D-073) only when it needs a project: aspects (`asp/`), libraries (`lib/`), data (`data/`) or an output folder (`out/`). A test of a single script is a plain file `test/levelN/code_name.eve`, as in level 1. The name of a test, file or folder, is `code_name` (`b30_function`), and the driver inside has the same name. Applied: b13, b18, b30 to b43 (level 2) and c10 to c17 (level 3); the folder tests with `asp/` or `lib/` stay folders. The runner already reads both forms.

## D-133 A test project can have several drivers (2026-10-08)
Author decision. One test project (a folder with `asp/`, `lib/`, `data/`, `web/`) can have several drivers. Each driver is a variation, another use case of the same libraries and aspects, so one set of modules or aspects is reused. The files of the variations are named with the code of the folder: `b05_test1.eve`, `b05_test2.eve`, ... next to the main driver `b05_apply_spread.eve`. Each file is a test of its own: the driver inside is named like the file, the expectations are in its `/*@expect*/` block (the `expect.json` of the folder belongs to the main driver only), it has its own row in `readme.md` and `status.json`, and it runs with the folder as working directory. Runner: `runtest.py b05` runs the main driver and its variations, `runtest.py b05_test2` one variation, a level runs them all. Applies to every level with project tests. Examples: b01_test1, c01_test1, c01_test2. Review of 2026-10-08: a variation was added to every positive project test that has a second use case (b02 to b08, b10 to b12, b14, b16, b20, b21, b26 to b29; c02 to c09, c18, c22 (two), c28 to c30; d02), 29 level 2 tests, 14 level 3 tests and 1 level 4 test. The negative tests b14, b20 and b21 got the corrected call of the same aspect. Not varied: tests with no project (b09, b13, b18), tests whose one aspect or module is the error (b15, b17, b19, b22 to b25, c19 to c21, c23 to c27, d01). Applied: `script/runtest.py`, `test/readme.md`, the readmes of levels 2 and 3.

## D-134 The smoke test is self-contained and checks the fundamentals (2026-10-08)
Author decision. The smoke test is independent of the tests of the levels. It has five scripts, `topology.eve`, `logic.eve`, `numeric.eve`, `string.eve` and `collection.eve`, in `test/smoke/`: functions with no parameters and extremely simple logic (`True` is `True`, `0 == 0`), the zero values and the extreme values of each type, the operators and the literals. It is very fast (under a second) and shows that the program compiles, parses and has no logical fallacy or contradiction. The workflow tests of the machine (v07, v09, v10) load their own scripts from `test/smoke/slot/` (`hello.eve`, `fails.eve`, `jobs.eve`) and check the lines of the report, not the number of nodes of a tree, so a change of the tree no longer breaks them (the cause of the failures of 2026-10-08). Applied: `test/smoke/`, `readme.md`.

## D-135 The smoke test is organized by feature; the old v tests are removed (2026-10-08)
Author decision. The tests v01 to v11 (the slot commands and the command-file workflow of the machine) had little value and are removed, with `test/smoke/slot/` and the `expect.json` of the folder. The smoke test is a set of small scripts, one feature each, with extremely simple logic: `topology`, `logic`, `numeric`, `string`, `collection`, `variables`, `operators`, `control`, `subprograms`, `errors`, `types`, `objects`, `placeholders` and one project folder, `project/` (a module, an aspect, `safe` and `Atomic`). 16 tests with `constants` and `constant_assign`, under a second. Codes: `s01` to `s16` in the order `topology`, `logic`, `numeric`, `string`, `collection`, `variables`, `constants`, `constant_assign`, `operators`, `control`, `subprograms`, `errors`, `types`, `objects`, `placeholders`, `project` (files `s01_topology.eve`, ..., folder `s16_project/`). The tools of the machine (slot, `-x -i` command files, `ast`, `inspect`) have no test now; the runner still reads the key `"serve"`. Replaces the last part of D-134.
