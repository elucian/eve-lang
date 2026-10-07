# Decisions, level 2: a project of a driver and aspects (version 0.1)

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. When a question is answered, turn it into a decision with the date and keep the question text for history. Plan steps reference these ids. **Read cheaply:** `python script/plan.py list` prints every id; `python script/plan.py show D-087` prints one entry from here or from `archive/` (settled entries, full text); `python script/plan.py status` lists what is open.

The log is split by level; ids are shared and keep counting across the files (an id not found here is in another file). A new entry goes to the file of its topic. The levels are in [version_map.md](version_map.md). Settled and implemented entries move to [archive/decision_level2.md](archive/decision_level2.md); this file keeps the scope, the newest decisions and the open questions.

## Scope

Level 2 tests a project of **one driver and its aspects** (`test/level2`, prefix `b`). A driver calls an aspect with `apply`, passes arguments by position, by name and by spreading, reads results from its `@` outputs, and recovers the errors that the aspect raises. The aspect is a file in `asp/` with its own state, created at each call, and its own procedures and functions, which level 1 already teaches for a driver (a24, a25, a56, a64 to a73). **Lambdas and closures** are also level 2 (D-109), with `apply` and aspects: they use the subprograms of an aspect.

Features: F-STR-02 (aspects, serial), F-STR-04 (project folders, `asp/`), F-STR-05 to F-STR-07, F-LIB-01 (`log_err`, `log_wrn`). Not in level 2: modules, imports, libraries, classes and methods across files (**level 3**, D-112); parallel groups and concurrent aspects (level 4, D-090); the machine and the server (level 6).

Consequence: with no modules, an aspect is self-contained. It can't apply another aspect (D-066) and has no module to share code with, so shared code waits for level 3.

## Where the earlier decisions are

All settled, in the archive (`python script/plan.py show <id>`): D-066 (an aspect is an encapsulated machine with one `main`), D-072 (aspect errors, import forms, extension methods, test folders), D-073 (a test is a project folder), D-068 (modules, now level 3), D-082 (`eve --doc`, implemented), D-090 (`exclusive aspect`, `concurrent aspect`), Q-022 (answered, D-112). D-083 (the Eve machine) moved to [decision_level6.md](decision_level6.md).

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

## D-113 Aspect error trace, extension methods of an aspect, JSON log files (2026-10-07)
Author answers to Q-037, Q-038 and Q-039 (full text in the archive). Refines D-112 (d), (e) and (f).
- **Trace of an error.** An unhandled error prints the error first (message, code), then the stack of calls in order of call, innermost first, one line per frame: `line x in function y`, `line x in procedure y`, `line z in aspect <name>`, then the block that hosts the call: `in job <label>`, `in parallel <label>`, `in loop <label>`. `$error.line` and `$error.unit` describe the first frame; `$error.trace` holds the whole list (names as proposed in D-113, to confirm when the spec of `$error` is written).
- **Extension methods in an aspect.** A method that an aspect attaches to a class is temporary: it is visible only in that aspect and disappears from the object when `main` returns (state per call). An object given back through an `@` output or a channel keeps only the data it accumulated, not the methods. In a module it is different (level 3): an imported module makes its methods available where it is imported, but only those that it exports.
- **Log files.** The file name carries only the date of the run, because the time belongs to the operating system: `out/error_<date>.log` and `out/warning_<date>.log` (replaced by D-114). The content is JSON, so that a tool can read it and make an HTML report (that tool does not exist yet). The file is divided into groups, one per run, which show the run number and the time. The names and the shape are in D-114.
- Test b17 (trace) and b09 (log files) follow these rules; b09 follows D-114.

## D-114 The run log: one JSON file per date, one object per run (2026-10-07)
Author answer to Q-040 (full text in the archive). Replaces the file names of D-113 and the plain `error.log` and `warning.log` of D-057.
- **One file per date**, `out/run-log-<date>.json` (`<date>` is `YYYY-MM-DD`), for errors and warnings together. It is a JSON array with **one object per run**; a new run is appended at the end of the file.
- **A run object** has `run` (the number of the run in that file, from 1), `time` (start time, `HH:MM:SS`), `script` (the name of the driver) and `messages`, a list in the order written.
- **A message** has `type` (`"error"` or `"warning"`: `log_err` writes the first, `log_wrn` the second), `line` (the line of the call, in its file), `unit` (the unit that holds the line: the driver or aspect name for `main`, otherwise the function or procedure), `level` and `message` (the text). `level` is read as the depth in the stack of calls (0 for `main`): proposed, to confirm.
- A run that writes no message adds nothing to the file.
- The test runner understands `{date}` in a file name and JSON file expectations (`script/runtest.py`, "files"); b09 uses both.
- Applied: `spec/semantics/aspects.md` (Log files), `test/level2/b09_log_files`, `script/runtest.py`.

## Test plan for level 2

b01 to b09 exist. Planned, to write when the syntax is confirmed (all fail first, D-094):

| Code | Test | What it shows |
|---|---|---|
| b10 | `aspect_function` | a function of the aspect, declared at aspect level and called by `main` |
| b11 | `aspect_procedure` | a procedure of the aspect that changes an aspect-level variable; the driver sees nothing of it |
| b12 | `aspect_fresh_state` | two `apply` of the same aspect: the aspect-level variable starts again (with b03) |
| b13 | `aspect_missing` | `apply` of an aspect that is not in `asp/`: check-time error, exit 65 |
| b14 | `aspect_bad_args` | wrong count or unknown name of an argument: check-time error, exit 65 |
| b15 | `aspect_apply_aspect` | `apply` inside an aspect is a check-time error (D-066) |
| b16 | `aspect_recover` | an aspect recovers its own error with `recover`; the driver never sees it |
| b17 | `aspect_trace` | the error raised again in the driver names the aspect and the line of the `raise` (D-113) |
| b18 | `lambda` | an anonymous function `(x) => (x * 2)`, called at once and passed as an argument |
| b19 | `closure` | a function declared in a function keeps the state of its parent (D-101); it is a `!` function |

## Open questions

None for level 2.
