# Design: the unified aspect (no driver keyword, no free script)

Status: **decided by the author (2026-10-14): D-179**, answers to Q-058 (`design/decision/level2.md`). The details are settled by **D-180** (answers to Q-059). This file holds the rules made precise and the plan of the work.

## 1. The idea

The **aspect** is the one kind of script that runs. A file holds aspects (one, or several in a macro) or a module. The word `driver` is no longer a keyword; the aspect that is run first by a command is a `primary aspect` (D-181), a kind of aspect like `exclusive` and `concurrent`. The free script and the shebang `#!` are removed. The Eve macro stays (demos, tests).

An aspect stays **encapsulated** (D-066): it is called by its name only, and `process main` is its one public entry point. An aspect may also have **private processes** that only its own processes call, by their bare names:

```eve
concurrent aspect pipeline is
  new record_count = 0 :Integer;   ** not used by a started process (rule 1)

  process ingest(source: String) is
    print ("Ingesting ", source);
  return;

  process extract(target: String) is
    print ("Extracting ", target);
  return;

  ** the one entry point: it orchestrates the private processes
  process main is
    parallel
    do
      start ingest("db_01");
      start extract("s3_out");
    done;
  return;
end pipeline;

** run by a command: eve etl.eve
primary aspect etl is
  process main is
    apply pipeline();
  return;
end etl;
```

A private process is started only inside a concurrent aspect, so the parallel work of `pipeline` is one level below the primary aspect `etl`, which is serial and cannot call itself or be called.

From another aspect: `apply pipeline();` or `start pipeline();` runs `pipeline.main`. Writing `pipeline.ingest` is a compile error: the dot is never applied to an aspect. From the command line: `eve pipeline.eve` runs `main`, and the arguments after the file go to the parameters of `main`, as for a driver today.

## 2. What changes

| Decision | Today | After D-179 |
|---|---|---|
| D-012, D-037, D-040 | `driver name is … end name;` is the script that runs | `aspect name is`; any aspect can be run, and the one run first is the driver |
| D-043 (scopes) | only the driver has a global scope | the state of the root aspect is the scope of the run; modules bind to it |
| D-066 | one process `main`; only the driver applies or starts aspects | `main` plus private processes; any aspect may call another, 3 levels at most, no cycle. Kept: called by name only, nothing public but `main`, the dot never applied to an aspect, a new state per call |
| D-014, D-091, D-126 (free script part) | a `#!` file of free statements runs | removed; line 1 is a `#` title or a `##` subtitle, or the code itself; `#!` is a compile error |
| D-152 (Eve macro) | shared declarations + aspects + one driver, `#!` optional | kept: shared declarations and several aspects; the entry point is the one `primary aspect` of the file (D-180, D-181); `#!` removed |
| D-140 (where, nesting) | a group in the driver `main` or in the `main` of an aspect it starts | a group in any process; the levels count from the root aspect (rule 2) |
| D-133 | variations are several drivers of one project | several root aspects of one project, the same rule |

Kept as they are: `exclusive` / `concurrent` per aspect and the default exclusive (D-090, D-130); a new state per call (D-066); inputs by value and one owner per `@` output (D-048, D-140); output buffers in the order of `start`, `ParallelError`, `on error cancel`, `within` (D-140); the thread-safety checks of modules (D-129, D-137).

## 3. Rules

1. **State race safety.** A private process that is **started** uses only the thread-safe names of its aspect: `Atomic(:T)` variables, `Channel`s, constants (`set`), and the functions and procedures that the compiler proves thread safe. Any other aspect-level name in a started process, or in what it calls, is a compile error that names the name and the chain of calls. This is the D-152 rule for a concurrent aspect of a macro, applied to a process; the checker already has it. A process that is only **applied** (serial) uses every name of its aspect.
2. **Three levels.** The root aspect is level 1. An aspect it calls (`apply` or `start`) is level 2, and an aspect called from there is level 3. An aspect of level 3 calls no other aspect: the compiler follows the calls from the root and fails at a fourth level, printing the chain. Only a call of an aspect makes a level; a call of a private process (`apply` or `start`) never does (D-180). In a macro, the calls between its aspects count like any other. The limits of D-140 on the parallel groups count on the same levels.
3. **Parameter isolation.** Arguments of `start` are copied at the start (D-048); each `@` output has one owner in a group; a `Channel` is the only object shared by two tasks. Unchanged.
4. **No cycle.** An aspect does not call itself, and no chain of calls comes back to an aspect already in it. The linker (`comp/evecp/src/project.zig`) reads every aspect reached and reports the chain (exit 65).
5. **Private processes.** Every process except `main` is private: it is called only by a process of the same aspect, by its bare name (`apply ingest(…)`, `start ingest(…)`). Every aspect has a `main`; an aspect without one is a compile error.
6. **Instances.** A call from another aspect makes a new state of the aspect (its declarations are evaluated), runs `main` and drops the state when `main` returns (D-066). The private processes called by `main` work on the **same** state: that is the shared state of the picture.
7. **The kind word.** `exclusive` (the default), `concurrent` and `primary` are reserved words of the same design, written before `aspect` in any file (D-181). An exclusive aspect is called with `apply`; a concurrent aspect with `apply` or `start`; a primary aspect is run by a command and **no aspect applies or starts it** (compile error). A private process can be started only in a `concurrent aspect`; in an `exclusive` or `primary` aspect it is applied, and a `start` of it is a compile error. A primary aspect is serial: its processes are exclusive, but its parallel groups start aspects.
8. **The primary aspect** (D-180, D-181, D-182). A command (`eve file.eve`) also runs an exclusive aspect, for testing; it does not run a concurrent aspect, and a concurrent aspect is called only from a primary or an exclusive aspect (D-182, D-183). It is designed to be executed first and can run alone: `eve file.eve` runs its `main`, which takes the command-line arguments, and its state is the scope of the run. A project may hold several (one for each use case). In a macro there is exactly one; none or two is a compile error. It is the root of the run, so a call of it by an aspect is a compile error.
9. **Errors and exit.** `exit` leaves the current process, `over` ends the whole run (D-111), and the exit code of the run is that of the root `main` (D-010). An error that a started process does not recover goes to its group (D-140); in an applied process it goes to the caller.

## 4. Settled by D-180 (answers to Q-059)

- **(a) The driver of a macro.** **answer** A macro has a "primary" aspect that is not exclusive not concurent. primary aspect is the entry point of a macro and primary is used instead of concurent or exclusive only for the macro type of script. Rule 8.
- **(b) Private processes and levels.** **answer** no, apply for private processes do not count as levels. Only apply/start an aspect is a level not sibling processes. In a macro, calling aspects also count as levels. Rule 2.
- **Corrected by D-181:** `primary` is a kind of aspect for any file, not only for a macro; it is serial, its processes are exclusive, but it can start aspects in parallel blocks (rule 7); no aspect applies or starts it. `primary`, `exclusive` and `concurrent` are reserved keywords, of the same design.

## 5. What it touches (counted 2026-10-14)

| Place | Size | Change |
|---|---|---|
| `test/` drivers | 376 files (L1 65, L2 63, L3 50, L4 42, L5 114, smoke 16, project 7, scaffold 3, bmark 16) | `driver x is` → `aspect x is`, mechanical; check the expectations that name a driver |
| free scripts | `test/level1/a04_free_script.eve`, `test/level3/c24_import_free_script/lib/tool.eve` | a04 becomes the negative test of `#!` and of free statements; c24 is dropped or becomes "import an aspect" |
| macros | 8 files (e04, e16 to e22) | the `driver` becomes an aspect; `#!` removed (e17) |
| tutorial | 43 pages write `driver`; topology, processing, multitasking/concurrency, syntax, the macro section, the highlighter `js/eve1.js` | the word stays where it names the role; the keyword goes |
| spec | `lexical.md` (file header), `syntax/declarations.md` (Scripts, Process, Eve macro), `syntax/grammar.md`, `lexical/keywords.json`, `semantics/aspects.md`, `semantics/multitasking.md`, `semantics/modules.md` | rules of section 3 |
| compiler | `comp/evecp/src/parser.zig` (65 places: `driver`, `macro`, free script), `check.zig` (34), `project.zig` (30), `lexer.zig` (`#!`), `scaffold.zig` (13), `doc.zig` | one aspect node with `main` and private processes |
| VM | `comp/evevm/src/interp.zig`, `interp/script.zig`, `interp/parallel.zig`, `vm.zig`, `task.zig` | the root aspect, private processes on the same state |
| tools | `comp/eve/`, `script/runtest.py` (7 places), `script/grammarcheck.py`, `pattern/declaration.eve`, `comp/evetx/gen_keywords.py`, `manual/usage.md` | names |

## 6. Plan of the work

One step per session, in the order of the project (D-194: plan, design, user interfaces, refactor, optimize, test, spec, compiler, manual, tutorial last).

- **U0 Decision.** D-179 and D-180 written (2026-10-14). Nothing blocks the work.
- **U1 Tutorial.** topology.html (two kinds of scripts: aspect and module; the driver as a role), processing.html (the root aspect, calls by name, 3 levels, no cycle), multitasking/concurrency (private processes started from `main`, rules 1 and 7), syntax.html (`driver` out of the keywords, no `#!`), the macro section (no `driver`, no `#!`), every other page: `driver name is` → `aspect name is` by a script in `temp/`, checked with `git -C tutorial diff --stat`; `genkeywords.py`; `bee-ed balance` on every changed page; sidebars in `tutorial/data/`.
  **[x] 2026-10-14 done:** 80 files in the scl repo (not committed yet). `driver name is` became `aspect name is` in the code blocks of 31 pages and in `tutorial/demo/*.eve`; the 8 macro demos use `primary aspect` and no `#!`; `free_script.eve` became `word_count.eve`. Rewritten by hand: drivers.html (the driver as a role), aspects.html (private processes, 3 levels, kinds), scripts.html (section "Running an aspect" replaces "Free scripts", anchor `#run-aspect`), macro.html (primary aspect, no free script), syntax.html (no `#!`, keyword rows), concurrency.html (levels, private processes), processing.html, and short edits in 9 other pages. *Author, same day:* the page drivers.html is dissolved (its text is in aspects.html, "Run an aspect", and in macro.html); the tutorial no longer insists on the word driver: the first wording (a primary role for any aspect) was corrected the same day by D-181: `primary` is a kind of aspect; chapters 10 to 44 moved up by one (index, examples, demo comments); `driver_args.eve` became `aspect_args.eve`. The run log still has the field `driver` (U7). *Left for later steps:* the highlighter `js/eve1.js` (U2, `genkeywords.py` after `keywords.json` has `primary` and no `driver`), `features.html` (generated from the tests, U3), the sidebar JSON of drivers/aspects (headings unchanged), the demos with a `primary aspect` do not run until U4.
- **U2 Spec.** lexical.md (no `#!`), declarations.md, grammar.md (`script = { aspect } | module`; `process` repeated in an aspect), keywords.json (`driver` removed, `primary` added as a reserved word beside `exclusive` and `concurrent`), aspects.md (private processes, instances, levels, cycles), multitasking.md (levels from the root, rule 1 for a process); `speccheck.py`, `grammarcheck.py`.
  **[x] 2026-10-14 done** (commit 899a708): `lexical.md` (no `#!`), `delimiters.json` (shebang removed), `keywords.json` (`driver` removed, `primary` added, the three kind words no longer contextual), `grammar.md` (`script = aspect | module`, `kind`, macro with a primary aspect), `declarations.md` (Scripts, Eve macro), `aspects.md` (kinds, private processes, calls, levels, command), `multitasking.md` (levels, private processes started), `modules.md`, `variables.md`, `statements.md`, `data-types.md`, `index.md`, `README.md`; `speccheck.py` and `mdlinks.py check spec` pass. *Not run:* `grammarcheck.py` (needs the tests of U3 first). *Settled after:* a concurrent aspect is called only from a primary or an exclusive aspect (D-183); the groups and the levels are Q-061.
- **U3 Tests first.** A one-off script `temp/migrate_driver.py` rewrites the headers of the 376 files and lists every expectation that names a driver; a04, c24, e04, e16 to e22 by hand. New tests at the next free numbers. L2 `b45`+: a private process applied by `main`; `a.p` from outside (error); an aspect without `main` (error); an aspect that calls itself and a cycle of two (errors); a fourth level (error); an aspect run directly by `eve` that calls others. L4 `d36`+: private processes started from `main` sharing an `Atomic`; a started private process that touches a plain variable (error); a start in an exclusive aspect (error). L5 `e108`+: the pipeline of section 1 in a macro with a `primary aspect`; a macro without a primary aspect, with two, an `apply` and a `start` of a primary aspect (errors), a `start` of a private process of a primary aspect (error), a file with one primary aspect (runs); calls between the aspects of a macro that reach a fourth level (error).
  **[x] 2026-10-14 done (tests written first, they fail until U4 and U5):** `temp/migrate_driver.py` turned 374 `driver x is` headers of 484 files into `primary aspect x is`; comments that name the driver were reworded; a04 (now `a04_shebang_error`), c24 (`c24_import_aspect`), e21 (`e21_macro_two_primary`), e61 (`e61_macro_needs_primary`) renamed and rewritten; e17 lost its `#!`; d32 expects `parallel is allowed only in a process`; b15 is now a positive test (an aspect applies an aspect). New: b45 to b54 (primary not applied, three levels, cycle, self call, four levels, private process, shared state of private processes, dot on an aspect, no `main`, an exclusive aspect run alone), d36 to d40 (private processes started in a concurrent aspect, plain variable error, primary starts a private process, concurrent run by a command, concurrent calls concurrent), e108, e109 (macro with a primary aspect). d25, d26 and d31 were adapted to D-183 with the reading recommended in Q-061 (the aspect that opens a group is exclusive; the leaves are concurrent). The error messages of the new tests are in `spec/semantics/aspects.md` ("Compile errors of the calls"). `status.json` and the readmes are regenerated by `runtest.py` after U4.
- **U4 Parser.** `comp/evecp/src/parser.zig`: one `aspect` node with `main` and private processes; `driver` is no longer a keyword and `primary` is one (a name like any other); `#!` on line 1 fails; the free-script branch removed; the macro keeps its aspects and runs its `primary aspect` (rule 8); `lexer.zig`, `doc.zig`. Unit tests.
  **[x] 2026-10-14 done:** `ast.zig` (one `aspect` tag with `public` = concurrent and `primary`; `.driver` and `.script` removed), `lexer.zig` (a `#!` line is refused), `parser.zig` (`primary` reserved and `driver` a plain name; `isAspectStart`, an aspect with `main` and private processes, the macro with exactly one primary aspect, no free script, the dot on an aspect refused, `parallel` only in a process); unit tests updated.
- **U5 Checker and linker.** `check.zig`: bare calls of private processes, `a.p` rejected, rule 1 for a started process (the D-152 check moved from the macro aspect to the process), rule 7; `project.zig`: the root aspect, calls from any aspect, levels (rule 2), cycles (rule 4).
  **[x] 2026-10-14 done:** `check.zig` (the rule "an aspect can't apply another" removed; `startedSafety` for the private processes a concurrent aspect starts), `project.zig` (`walkAspect`, `callOf`, `groupRules`: private processes in `sel`, a primary aspect never called, concurrent called only from primary or exclusive, cycle, itself, three levels, the group rules by level, an aspect can't be imported); two new unit tests.
- **U6 Interpreter.** `interp/script.zig`, `interp.zig`: the root aspect; a private process works on the state of its aspect; `interp/parallel.zig`, `task.zig`: a started private process gets that state but reaches only its thread-safe names (rule 1 makes this safe: the reference counts of D-151 are not atomic, so a plain value is never shared between tasks). `EVE_GC_VERIFY=1 python script/runtest.py all` on the Debug build.
  **[x] 2026-10-14 done:** `runRoot` runs the `main` of the root aspect; `applyPrivate`, `runPrivate` and `startPrivate` run a private process in the scope of the aspect state (`it.unit`); `Started` has `proc` and `unit`. Debug build with `EVE_GC_VERIFY=1`: levels 2 and 4 pass.
- **U7 Tools.** `comp/eve/` (help texts), `scaffold.zig` (`project init`, `project new` write an aspect), `runtest.py`, `grammarcheck.py`, `pattern/declaration.eve`, `comp/evetx/gen_keywords.py`, `manual/usage.md`.
  **[x] 2026-10-14 done in part:** scaffold writes a `primary aspect`; `doc.zig` knows the kind words; `manual/usage.md`, `design/version_map.md` (F-STR-10), `runtest.py` and `genpages.py` wording. *Left:* the `driver` field of the run log and the label `driver` in `processing.html` (output format, a later release).
- **U8 Close.** `runtest.py all` and `smoke` on the ReleaseSafe build; `bmark.py --check` before U4 and after U6; `design/version_map.md`: F-STR-09 (macro) updated, a new feature F-STR-10 "Unified aspect"; the breaking change for the next release notes (`driver` → `aspect`, no free script, no `#!`).
  **[x] 2026-10-14 done:** ReleaseSafe `runtest.py all`: 366 pass, 0 fail; smoke 16/16; `bmark.py --check`: no slowdown above 14% on any benchmark, level totals within 8%, `eve.exe` -0.4%; `zig build test` passes. `bmark.py --save` is left for the release.

## 7. Risks

- **Shared state between threads.** Rule 1 must hold in the checker before U6, or a started private process can touch a non-atomic reference count. The macro tests e19 and e20 already prove the mechanism for `Atomic`.
- **The size of the migration.** 376 test files and 43 pages: done by scripts, verified by the test runner and by `git diff --stat`, never by hand.
