# Decisions, level 2: a project of a driver and aspects (version 0.1)

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. When a question is answered, turn it into a decision with the date and keep the question text for history. Plan steps reference these ids. **Read cheaply:** `python script/plan.py list` prints every id; `python script/plan.py show D-087` prints one entry from here or from `archive/` (settled entries, full text); `python script/plan.py status` lists what is open.

The log is split by level; ids are shared and keep counting across the files (an id not found here is in another file). A new entry goes to the file of its topic. The levels are in [version_map.md](version_map.md). Settled and implemented entries move to [archive/decision_level2.md](archive/decision_level2.md); this file keeps the scope, the newest decisions and the open questions.

## Scope

Level 2 tests a project of **one driver and its aspects** (`test/level2`, prefix `b`). A driver calls an aspect with `apply`, passes arguments by position, by name and by spreading, reads results from its `@` outputs, and recovers the errors that the aspect raises. The aspect is a file in `asp/` with its own state, created at each call, and its own procedures and functions, which level 1 already teaches for a driver (a24, a25, a56, a64 to a73). **Lambdas and closures** are also level 2 (D-109), with `apply` and aspects: they use the subprograms of an aspect.

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
