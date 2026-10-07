# Archive of decision_level2.md: settled entries, full text

## Q-011 Default visibility of a module-level method (answered 2026-09-30 → D-035)
D-025 says `.` is public and `_` is private. What is a method with no prefix: private to the module, or public? The same question applies to functions and classes at module level.
Status: answered again 2026-10-03 → D-072 (extension methods).
**Answer:** `_` can be used (new decision) to show that a method belong to a class. Is a class extension method, private for a class. Withowt prefix the method is private to the driver aspect or module.

## D-026 No coroutines: generators, threads, suspended methods (2026-09-30)
Follows D-025. The word "coroutine" is not used, because it came with "routine".
- A method started with `start` is an **asynchronous method**: it runs in a secondary thread and can be suspended with `suspend` and continued with `resume`. A suspended method waits for a signal.
- A method that produces its values one batch at a time is a **generator**.
- A function can not be suspended and has no state. Only a method has state and can be suspended.
- A function declared inside a method is enclosed by it and can use the state of that method. This is the closure system of Eve: the method holds the state, the enclosed function is the closure.
- Applied to concurrency, syntax and topology pages and the concurrency and topology issues. The closures section of functions.html still describes the old rule (closures created by a function): Q-012.

## D-031 Topology page answers (2026-09-30)
From TOP-01 to TOP-16. Applied to topology.html, with one canonical skeleton each for driver, aspect and module (TOP-I1).
- Indentation is mandatory: 2 spaces, an error otherwise (TOP-01). Region keywords start at column 0.
- Regions are decided per kind of script (TOP-02). A class is not a region: `class Name = {…} <: Type;` on one line; the `class` region with `NewType = {} <: Type;` is not allowed (TOP-06). Process end regions: `recover`, `finalize` (`release` is gone); a module ends with `finalize`.
- `set` creates constants of the global scope. It is allowed directly after `#!` or after the header (TOP-03), and in any declaration region. The `constant` region is a visual delimiter for constants only; global variables use `new` in the `global` region (interpretation of TOP-05). Declarations may sit directly under the header at 2 spaces; they belong to the global scope bound to the process scope (TOP-05). Constant names are not enforced (TOP-05).
- `def Alias = library.Member;` creates an alias; `def` is a new keyword. An alias of a parameterized class is not supported (TOP-04).
- `:=` executes an expression and is allowed in global regions; the "no inference in global" restriction is removed (TOP-07).
- OS environment variables are visible as `$NAME` (TOP-08).
- `over` ends with 0; `panic` ends with 1 (no `panic N`, no `panic 0`); a failed `expect` ends with 2; `raise` ends with a code greater than 0 (TOP-09).
- An aspect has a mandatory process. A library and a module have none; a module can be imported, not applied (TOP-10).
- A library is a folder of modules; a module is one script file with header `module name is`, named like the file. The term "crate" is dropped (TOP-11).
- A path is a string; `/` is a "smart concatenation" that becomes `\` on Windows (TOP-12).
- `.cfg` files hold `$key = value` with Eve literals and `#` comments (TOP-13).
- VM parameters, REPL, service and exclusive modes are planned (about 0.9), not in 0.1 (TOP-14). Script operations: `parse`, `debug` (debug mode) and `execute` (production mode); `load` is removed (TOP-15).
- Only a driver defines globals. Aspects and modules define public (prefix `.`) and private members, reached as `alias.member`, so equal names in two modules do not conflict (TOP-16).
- Open: the 0.1 list and types of built-in system variables (TOP-08); whether an aspect returns a result or an error code to the driver (TOP-10). **answer** (→ D-072) The aspect will return an Exception object, The exception object can have code 0 (no orror/success) or an error code > 0, message and line number. All Exception object provide.
- 
Spec additions:
- `spec/semantics/topology.md`: projects, libraries, modules, imports and paths (TOP-10 to TOP-12), exit codes (TOP-09), VM operations (TOP-15).
- `spec/syntax/regions.md`: regions and order per script kind, indentation rule, `def`, `set`/`new`, `:=` in global regions (TOP-01 to TOP-07).
- `spec/semantics/scopes.md`: system variables (TOP-08), public and private members (TOP-16).
- `manual/usage.md`: VM modes and options, planned (TOP-14).

## D-035 Module-level visibility: `.` is public, no prefix is private (2026-09-30)
Answers Q-011. Author decision.
- A module-level method, function or class is public only if its name starts with `.` in its declaration (`method .write(...)`). Without the dot it is private to the module.
- `_` stays the protected prefix of class members (D-017); a module-level name needs no `_`.

## D-042 `apply aspect.main(args);` names the process (2026-10-01)
Author decision. Replaces the `apply name to (args);` form of D-016 and D-038.
- `apply` runs a process of an aspect and waits. The process is named: `apply aspect_name.main(args);`. The `to` form and the form without parentheses are removed; `()` is always written.
- Applied to processing.html (execution section, examples), syntax.html (keyword table).
- Open: `begin aspect_name(args);` in a parallel group should probably become `begin aspect_name.main(args);` too.
- Question, not decided: methods at module level (D-017, D-035). Recommendation: keep them. A module is a singleton, so a module-level method is a method of that singleton, without `@self`, like a class method. Scripts need free helper methods without a wrapper class, and extension methods (`method (@self: Error) .raise(...)`) are declared outside classes. Removing them would force a class for every helper.

## D-043 Single main process in a driver; aspects host named processes; `start` replaces `begin` (2026-10-01)
Author decision. Replaces `begin` and the named-process `start` of D-037/D-038, and the `.main` of D-042.
- A driver has exactly one process, `main`: a single-thread master. It may define methods (also asynchronous ones) but no other process.
- An aspect hosts one or more named processes and has no `main`. Parameters belong to each process (D-040).
- `apply aspect.process(args);` runs a process in serial mode (waits). `start aspect.process(args);` runs it in parallel, inside `parallel … fork … join`; people expect an `end` after `begin`, so `begin` is removed from the language. `join` closes the group. Output parameters (`@`) are ready after `apply`, or after the `join` for `start`.
- Inside an aspect, a process can call a sibling by its bare name (assumed from the model, not stated).
- Scopes: only the driver defines a global scope. Each process of an aspect has its own scope, no globals, and data arrives by parameters; parallel runs never share variables. The scope of a module is bound to the scope of the driver or aspect that imports it (before: to the process).
- Aspect-level `let` variables are initial values copied into each process scope (assumed).
- `start name(args);` also stays for asynchronous methods (concurrency.html), joined by `wait all;`. The same keyword now launches two kinds of concurrent work; the target tells them apart.
- Applied to processing.html (apply forms, parallel examples), topology.html (driver, aspect, process, module scope), syntax.html (keywords `apply`, `start`, `fork`; `begin` removed), concurrency.html; the highlighter drops `begin`.
- Aspect examples use the process names `run` and `show`; the aspect `output_params` in concurrency.html became a driver.
- Open: aspect member visibility (`.` public) now that aspects have no shared scope, and the demo files that apply aspects, if any are written.

## D-046 `parallel` uses `do` and `done`; `fork` and `join` removed (2026-10-01)
Author decision, aligns the parallel group with the control statements. Replaces the `fork`/`join` words of D-034 and D-043.
- `[name:] parallel` declarations `do` … `start aspect.process(args);` … `done [name];`. The declarations (shared data such as `let s: ()Integer;`) come before `do`; `start` is allowed in the `do` region.
- `done [name];` waits for all the processes started in the group, as `join` did; a labeled group closes with `done name;`, an unlabeled group with `done;`. Output parameters (`@`) are ready after the `done`.
- `fork` and `join` are no longer keywords (keyword table 113 words).
- Applied to processing.html (author edit and notes), control.html (summary table), syntax.html (keyword table, meaning table, block terminators), `js/eve1.js`, issues CON-09 and PRC-07.

## D-047 Parallel methods inside a process; aspects run serially; BSP (2026-10-01)
Author decision (first three bullets); the rules after them are proposed to make it safe and implementable. Replaces `start aspect.process(args);` of D-043 and D-046 and refines the answer to CON-04 (methods were single-core only).
- `apply aspect.process(args);` is the only way to run a process of an aspect: serial, the caller waits. Aspects are never started; `start aspect.process()` is an error.
- One process can span several cores. Parallel work is done by methods: `start method(args);` in the `do` region of a `[name:] parallel … do … done [name];` block. `done` is a barrier: it waits for every method started in the group.
- A method called by its bare name runs on the core of its caller; `suspend`, `resume` and `wait` stay cooperative on that core (CON-08 answer unchanged).
- Proposed, VM: a started method is a task; tasks run on a pool of worker threads, size `$cores` (default: the hardware cores, set in the driver configuration). More tasks than cores are queued.
- Proposed, data rules (no data race by construction, so no locks): arguments are evaluated at `start`; a collection or object passed as input is shared read only and the process can't modify it until `done`. An `@` argument belongs to one task: two tasks of a group can't receive the same variable, element or overlapping slice as output (compiler where provable, VM check at `start` otherwise). Changed by D-048: inputs are passed by value, so the process may go on changing them; the "read only until `done`" rule is dropped. A started method can't change driver globals, can't `suspend` and can't contain a `parallel` block (no nesting). It may call methods by name (same worker) and print (any order).
- Proposed, errors (answers the open part of PRC-07 for methods): when a task raises, the tasks not yet begun are cancelled, the running ones finish, `done` raises the first error in the process, and later groups don't begin.
- Bulk Synchronous Parallel (BSP) is the recommended pattern: one parallel block = one superstep (compute on own data, write own outputs, barrier at `done`); the process combines or redistributes between blocks; an iterative algorithm puts the block in a loop. Tasks never wait for each other, so a group can't deadlock, and combining in index order makes results deterministic.
- Proposed, channels (CON-05): not in version 1. Streams are read in batches, one batch per superstep. The author's producer-consumer example was replaced; its problems are listed in CON-05.
- Call site: `@` before an output argument (`start square(i, @s[i]);`), decided in D-048.
- Applied to concurrency.html (intro, asynchronous methods, new section "Parallel methods" with "Bulk Synchronous Parallel", examples `parallel_sum` and `heat_bar`; "Multi Threading" removed), processing.html (section "Parallel execution", examples with methods), syntax.html (`parallel`, `start`), topology.html (driver, process, aspect).

## D-050 Concurrency is not implemented in version 1 (2026-10-01)
Author decision. Same treatment as the VM modes of TOP-14: designed, planned, not in 0.1.
- Not in 0.1: asynchronous methods (`suspend`, `resume`, `wait all`, `wait name`) and parallel methods (`parallel`, `start`, D-047). Their keywords stay reserved. A method in 0.1 runs to completion on the core of its caller; a process runs on one core; aspects run with `apply` (serial).
- In 0.1: methods, side effects, parameters, `@` by reference and by-value arguments (D-048), `::` and views (D-049).
- The Zig VM needs no scheduler, coroutine stack or worker pool for 0.1.
- Spec: `semantics/concurrency.md` (S4.5) keeps the design in a section marked "planned, not in 0.1".
- Open: `wait duration;` as a plain pause of the process, outside concurrency, in 0.1 or not.
- Applied: notes in concurrency.html (asynchronous and parallel methods) and processing.html (parallel execution), plan S4.5, issues/concurrency.md header.

## D-051 No asynchronous methods; one concurrency tutorial with groups, BSP and channels (2026-10-01)
Author decision. Replaces the cooperative methods of D-047 (`suspend`, `resume name`, `wait all`, `wait name`) and the "no channels" proposal of D-047. Still not in 0.1 (D-050).
- A method called by its name runs to completion on the core of its caller. `suspend` is removed (keyword table 111 words, highlighters); `resume` keeps only its `recover` meaning; `wait 10ms;` stays as a pause (open, D-050).
- concurrency.html is the single tutorial for parallel work: methods and parameters, Parallel model, Parallel groups (moved from processing.html, with the diagram `img/eve-parallel.svg`), Data rules, Errors and time-out, Workers, Bulk Synchronous Parallel, Channels (with `img/eve-pipeline.svg`), Choosing a model. processing.html keeps a short "Parallel execution" section that points there.
- Channels: `new Channel(:T)(capacity: n[, senders: m])`; `ch.send(v);` waits while full; `for x in ch do` receives until closed and empty; `ch.receive(@x);`; `ch.close();` (the channel closes after the m-th close); `ch.count()`. A channel is passed with `@` and is the only object several tasks of a group may share. Values are copied on send; order is kept per sender. Collect results inside the group: reading after `done` from a full channel deadlocks.
- Scheduling: a task waiting on a channel gives its core to another task (M:N), so a pipeline with more stages than `$cores` works. Deadlock (every unfinished task waits on a channel) is detected and raised at `done`; a channel wait longer than `$timeout` raises a time-out error.
- Models: task group, BSP, pipeline; a comparison table recommends groups or BSP first, channels for streams.
- Applied also to functions.html (asynchronous method row became "parallel method", column "Can be suspended" removed), syntax.html (`suspend`, `resume`, `yield`, `wait`, `start` rows), topology.html (driver, aspect process), `js/eve1.js`, `js/eve3.js`. Issues: CON-04, CON-05 answered, CON-06 partly, CON-08 obsolete, CON-11 updated, CON-12 new.

## D-052 Processes raise errors; env variables; REPL moved to the manual (2026-10-01)
Author answers TOP-08, TOP-10, TOP-I2. Refines D-031, D-043.
- Environment variables of the OS are visible as `$NAME` (TOP-08). The list and the types of the 0.1 system variables are still open.
- Processes are sequential, so a process, also of an aspect, can raise errors; they propagate to the caller. The driver captures the exit code of `panic`, `raise`, `expect` and `assert` (TOP-10). Replaces "an aspect can't raise".
- The REPL and daemon text moved from topology.html to `manual/usage.md` (TOP-I2); the tutorial keeps a pointer.
- index.html: the quiz and certification section is removed (out of date).
- Applied: topology.html, index.html, manual/usage.md. Issues TOP-10 and TOP-I2 done; TOP-08 stays open for the list.

## D-053 Library in Eve, documented by eved (2026-10-02)
The tool `eved` is replaced by the command `eve --doc` (D-082).
Author answers LIB-01 to LIB-06.
- The library is mostly written in Eve, in `evevm/lib/` (README.md documents it). Only primitives that need the machine are native: a routine whose signature ends in `;`.
- Documentation is generated, not written: `evevm/doc/` holds Markdown made from the comments (`**` blocks above a declaration) and the signatures. The tool is `eved` (Eve doc), written in Zig, in `evevm/doc/eved.zig`, next to its output; `zig build doc`.
- LIB-01: built-ins are both functions and methods; public methods in a string module, possibly a `String` class. LIB-02: `truncate`, `fill`, `erase` return a new string; old references stay valid; garbage collected.
- LIB-03/04: `read` is callable as a statement. `routine .write(*args:String, sep:=" ", eol:=False)` writes at the current position; `print` adds a new line by default. Both write to stdout.
- LIB-05: new `log_err()` and `log_wrn()` for the `recover` region (corrected by D-057: they write log files). An unhandled error at the end of a driver goes to stderr: last error and call stack in debug mode, only the message otherwise.
- LIB-06: a backslash escapes, a double backslash is one backslash; `&code;` sends any HTML character code. Spec pending.
- Applied: `evevm/lib/io.eve` (draft), lib and doc READMEs, `eved` with a unit test. Not yet applied: tutorial library.html, the string module, `spec/library/builtins.*`.

## D-055 Processing answers: interruptions, raise, aspects, command line (2026-10-02)
Author answers PRC-02, 03, 06 to 11, 13, 14. Replaces parts of D-010, D-038, D-043.
- Exit codes: `return` and `over;` 0, `panic` 1, failed `expect` 2, failed `assert` 3 (a warning: the process goes on), `raise` 4 by default or the code of the exception. An exception is an object `{code, message}`; its code is also the exit code. `abort` does not run `finalize` (before, it did). `finalize` runs after `return`, `exit`, and when `recover` ends normally; it is skipped by `over`, `panic`, `abort`.
- `raise`: every form is valid (constructor `raise Type("m")`, constant `raise ($Type, "m")`, `raise (23, "m")`, `raise {code: 23, message: "m"}`, `raise "m"`); `raise` is an overloaded method; `$Type` is the code constant.
- Processes can not be recursive, methods can. An aspect is never run: only its processes, with `apply`.
- One parallel group at a time; a failed method does not stop the others; `done` waits, then raises the error to `recover`, or to `finalize` when there is no `recover`.
- Aspects are found by name: with a folder if given, else folder `asp`, the project root, then `lib`; `$EVE_ASP` sets the place (also used for libraries). An aspect has one implicit singleton scope (declarations hoisted), created by the first `apply`, kept until `reset aspect_name;` or `reset all;` (new statements).
- Command line: `-p value` for a short parameter name, `--param value` for a long one; values are Eve literals; `** @param x: "description"` above `main` feeds `eve script.eve -h`.
- Exception module: rewritten as a valid class on `exceptions.html`; the code constant for the default is `$err_raise` = 4, so warnings moved to 5 to 7 (changes D-054).
- Applied: processing.html, topology.html, exceptions.html, data/processing.json. Spec work pending.

## D-056 `external` declarations; exception.eve (2026-10-02)
Author decision. A declaration with the keyword `external` in front (`external .print(...)`) keeps only the signature; the body is implemented in Zig by the virtual machine, and the compiler creates the external library. It replaces the trailing `;` proposed in D-053. `evevm/lib/exception.eve` (module `exception`: Error, Warning, Call, `raise`, `expect`, `assert`, `warn`, constants `$err_name` and `$wrn_name`) and `io.eve` use it; `eved` documents it. exceptions.html: tables have plain cells, no `<code>`; the module is `exception` in lower case.

## D-057 io library: error and warning, log files, $EVE_OUT (2026-10-02)
Author correction of D-053 (LIB-05). `error(message)` and `warning(message)` write to stderr (as the tutorial already says). `log_err(message)` and `log_wrn(message)` do not print: they create log files in the output folder, `out` by default. The system variable `$EVE_OUT` sets the output folder. Open: the names of the log files and their line format. Applied: evevm/lib/io.eve, evevm/lib/README.md, topology.html (system variables).

## D-066 An aspect is an encapsulated machine with one `main`; parallel blocks start aspects (2026-10-03)
Author decision (plan/design-issues.md). Answers Q-020 (a), (b), (c), PRC-14, CON-09, CON-11 (who is started). Replaces D-042 and the aspect part of D-043 (named processes), the parallel methods of D-047, and the singleton scope and `reset` of D-055.
- **Same shape.** A driver and an aspect have the same form: declarations, then one `process main(params) is … return;`, closed by `end name;`. Every aspect has exactly one process, and its name is always `main`: one aspect, one process. Helper work is done by methods and functions.
- **Encapsulated.** Nothing in an aspect is public and the dot operator is never applied to an aspect. Data goes in by the parameters of `main` and comes out by its `@` outputs.
- **State per call.** Each `apply` (or `start`) creates the state of the aspect, aspect-level declarations included; it is dropped when `main` returns. A second call sees nothing of the first. `reset` is removed (keyword unused).
- **Calls.** `apply name(args);` runs the aspect and waits. Only the `main` of the driver may `apply` or `start` an aspect: an aspect can't apply or start another aspect, so recursion between aspects is impossible. Code that several aspects share goes in modules.
- **Parallel.** `[label:] parallel` declarations `do` … `start name(args);` … `done [label];` is allowed only in the `main` of the driver and is not nested. It starts aspects on several cores. Methods and functions always run serially, on the core of their caller, and can't be started. The data rules of D-047 still hold with aspects in place of methods: inputs by value, one owner for each `@` output, `done` is the barrier; BSP is the recommended pattern (one block = one superstep).
- **Errors.** A parallel block behaves like a job and may have a label (`$error.job` names it). When an aspect fails, the others go on; `done` waits for all of them, then raises the first error to `recover`. In `recover`, `retry` runs the whole block again and `resume` continues after it, as for a job.
- Still not in version 1 (D-050). Suspended methods and cooperative multitasking: Q-021.
- Applied to concurrency.html (parallel model, groups, data rules, errors, BSP, channels: every example has its worker as an aspect file), processing.html (aspect execution, scope, parallel note), topology.html (process, drivers, aspects, skeleton with one `main`), syntax.html (`process`, `parallel`, `apply`, `start`; `reset` marked unused), functions.html ("parallel method" row removed), exceptions.html (`$err_process` message). No `.eve` file applies or starts an aspect, so demos, tests and the VM are unchanged.

## D-067 Multitasking: generators with `yield`, parallel aspects, no coroutines (2026-10-03)
Author decision. Answers Q-021; the design is [design-multitasking.md](design-multitasking.md).
- The topic and the tutorial chapter are named **Multitasking**: `concurrency.html` became `multitasking.html` (data file `data/multitasking.json`, index row), `issues/concurrency.md` became `issues/multitasking.md` (CON ids kept), spec step S4.5 is `semantics/multitasking.md`. Eve has no coroutines, `async`, `await` or `suspend`.
- **Generators.** A method becomes a generator because its body contains `yield`; it declares one result. `result := expression; yield;` is the explicit form, `yield expression;` the short form; both are valid. A call creates a `Generator(:T)` object without `new` (`let g := count_to(3);`); `new` is for the objects of a class. Use: `for v in g`, comprehensions, `g.next()`, `g.value`, `g.done`, `g.close()`. A generator called as a statement is an error. `yield` only in the generator's own body (one level: not a coroutine), lazy body, inputs by value, errors raised in the caller, never copied, not an argument of `apply` or `start`.
- **Cooperative tasks** are generators that take turns on one core; the library module `task` (`round_robin`, `until`) is documented now and implemented in version 2.
- **Parallel aspects** (D-066): a started aspect that waits (input/output, `wait`, channel) gives its worker to another task, so a group can overlap many waits on a few cores. Done by the VM, invisible in the language.
- **Versions.** Generators are designed and taught in the tutorial now; their specification is postponed to version 2. `yield` is reserved until then.
- Applied to multitasking.html (head, title, introduction, new section Generators with Declaration, Use, Rules, Cooperative tasks, Generators and channels; "Parallel model" heading became "Parallel aspects", id kept; Workers; two new rows in "Choosing a model"), index.html, processing.html (link), syntax.html (`yield` row), functions.html (closures point to Generators); issues, plan phases 1, 3, 4, plan README and spec README follow the rename.

## Q-020 Level 2 suite: what must be decided first (2026-10-03)
Level 2 tests drivers with aspects and modules, imports and error recovery (S5.4). Each test is a driver with a folder of aspects and modules. These points block it; answer each one:
(a) **Aspect scope.** D-043 says each process of an aspect has its own scope and aspect-level `let` values are copied into it; D-055 says an aspect is a singleton whose scope lives from the first `apply` until `reset`. Which one? With the singleton, does a second `apply` see the values left by the first one?
**answer** I think I answered before to this. `reset` is obsolete. Aspect variables are private the main() process of the aspect. The declaration zone provide variables that can be shared by all process members. Because inside an aspect everything is sequentioal there are no race conditions. One apply create one scope, second apply create a new scope. (New instance of same aspect) Perfect izolation between executions.

(b) **What `.` means in an aspect.** Can the driver read `aspect.member` after `apply`, or only the `@` outputs (PRC-14 point 1)?
**answer** Cancel this feature. Aspect members can't be accessed with ".", and can't be defined with "." because none are public. One aspect must have one entry point, the main() process this is also not public, but implicit called when one aspect is applied. 

(c) **Sibling processes.** Can a process of an aspect call another process of the same aspect by its bare name, and how is that different from `apply` (D-043, assumed)?
**answer** Retired. One aspect has a single process main(). 

(d) **Errors across `apply`.** An error raised in an aspect process without `recover`: does it go to the `recover` of the driver process at the `apply` line, with which `$error.job` and `$error.code`? Does `panic` in an aspect end the driver (D-038 says yes)?
    **answer** yes, panic stop the process, and suddenly the application crash. The driver also panic. The driver will trigger a memory cleanup and exit.
    Does `over;` in an aspect end only that process? Over, end the aspect. If is used in driver, end driver. 
    
(e) **Import syntax.** The pages show `from $path/library_name use (*);` and `from $user_path use (module_name, …);`, while D-031 says a path is a string. Is the path a string (`from "lib/util" use (*);`), an unquoted path, or both? Is `use (m as x)` the alias form? **answer** yes this is the alias form
    Is a member reached as `m.name` or, with `(*)`, as a bare `name`? **answer** yes when alias is used  m.name when use (*) is used the public members (methods) are used without alias. This is how system methods enter the language as statements.
    
(f) **Module life cycle.** When does `initialize` run (first import, once per driver?), when does a module `finalize` run, and can a module read the globals of the driver that imports it ("bound to the scope of the driver", D-043)?
**answer** No, module members are agnostic of host, we use parameters to communicate with module.

(g) **Where aspects and modules are found in a test.** D-055: a folder given by the caller, else `asp`, the project root, then `lib`. What is the project root of `test/level2/b07_x.eve`: its folder? Proposal: each test has a folder `test/level2/b07_x/` with its aspects and modules, named in the test with `set $EVE_ASP = "b07_x";` or found by default in a folder named like the driver. Ok, for each test that need additional files create a folder like "b07" with subfolders "lib", "asp"
(h) **Names and placement.** Level 2 already holds `b01`–`b06` (VM slot commands) and `c01`–`c05` (VM workflow), which are tests of the VM tools, not of the language, and `c` is the prefix of level 3 (D-018). Proposal: move them to `test/vm/` (`v01`…) and keep `b01`… in level 2 for aspects and modules. **answer** agree withi this
    
(i) **Arguments.** `apply a.p(value, *list_args)` and `(param: value, *map_args)` (processing.html): is spreading a map into named  parameters part of 0.1? **answer** yes spreading is part of level2.

**Status:** (a), (b), (c) decided by D-066: state per `apply`, no public members, one process `main` per aspect.
    (d) to (i) decided by D-072 (2026-10-03).

## Q-021 Suspended methods, `yield` and cooperative multitasking (2026-10-03)
The author wants suspended methods back (generators that keep their state, cooperative multitasking); D-051 removed `suspend`. Two designs, both on one core, no locks, using the reserved word `yield`: (A) **Generators.** A method that contains `yield` is a generator. `yield;` hands its outputs to the caller and freezes its state. `for v in count_to(5) do … done;` iterates; `let g := new count_to(5);` makes a suspended instance, `g.next()` runs it to the next `yield` (False after `return`) and `g.x` reads the output. (B) **A plus cooperative tasks.** A block (keyword to choose, for example `concurrent do … done;`) runs several methods on one core and switches at `yield` and at a full or empty channel. `parallel` puts aspects on cores, the new block interleaves methods on one core. Recommendation: decide B, specify A for 0.1 (A is a subset of B). Questions: A or B; the keyword of the block; are generators in version 1 (they need no threads)?
**Answer:** The chapter is renamed Multitasking. `yield` is used for generators. No coroutines.
**Status:** design drafted in [design-multitasking.md](design-multitasking.md): generators one level deep (A), no cooperative block (B dropped); cooperative tasks are generators taking turns; a waiting started aspect gives its core away. Approved: D-067.

## D-068 Modules page; modules are singletons without public variables (2026-10-03)
Author decision. Answers Q-020 (f) for the life cycle; refines D-035 (visibility) and D-043 (module scope).
- New tutorial chapter `modules.html` (07, after Functions; index rows 07 to 17 became 08 to 18), with `data/modules.json`: declaration, public and private members, singletons, import, modules and parallel aspects, library modules (`external`), and a table that compares drivers, aspects and modules. The Modules section of topology.html is now a summary that links to it.
- **Singleton.** A module is loaded once, at the first import; every later import (driver, aspect or module) uses the same copy. `initialize` runs once, right after loading; `finalize` runs once, when the driver ends, after its process, in the reverse order of initialization.
- **No instances.** A module is not a class: `let m := new module_name;` is an error. Several objects with their own state come from a public class of the module.
- **No public variables**, because a module is shared and a public variable is not safe when tasks run at the same time: `let .name …` is an error. Public members are constants (`set .NAME = v :T;`), classes, functions, methods and channels (`set .name := new Channel(:T)(capacity: n);`: the reference is constant, the channel is safe for several tasks).
- Proposed (not stated by the author): a started aspect can't change the private variables of a module, like the driver globals (D-047); a module method that changes private state is called by the driver or by an applied aspect. Written in modules.html and in the data rules of multitasking.html.
- Every example process is named `main` (`process main is`): fixed 7 fragments in classes, collections, library and strings (`process test`, `list_join`, `list_split`, `demo_numbers`, `map_append`, `test_error`, `unicode_text`).
- Also: syntax.html (`.` prefix row), multitasking.html (data rule "Modules are shared"), functions.html (read next). `data/topology.json` had a trailing comma after the author removed "Running an Aspect"; the comma was removed.
- Open: the import path, string or `$path/name` (Q-020 e); `from "lib" use (counter);` is used in the examples.

## D-071 Register of system variables (2026-10-03)
Author decision. Answers TOP-08 (the list of the 0.1 system variables was open).
- `spec/semantics/variables.md` is the register of the system variables: name, type, meaning, default, status (0.1, draft, later, question), VM support and source. It lists the 19 variables and the 2 constant families found in the tutorial, the decisions and `evevm/lib`, and 13 `$` names that are not system variables (placeholders, examples).
- A new system variable is added to the register first, then used in a page, a test or the VM.
- Tutorial: the table "System Variables" of syntax.html is the only list of system variables in the tutorial (status 0.1, draft and later; the question rows wait). topology.html lost its two lists and links to it, like exceptions.html and command.html. `$object` left the table (open point 4); databases.html `$evelib` → `$EVE_LIB`.
- Proposed for 0.1: `$error`, `$NAME` (environment), `$EVE_LIB`, `$EVE_ASP`, `$EVE_OUT`, and the `$err_`/`$wrn_` constants. Six open points (duplicates `$OS_PWD`/`$CWD`, `$MY_LIB`/`$MY_LOG`, the two meanings of `$trace`, `$object` next to `@self`, folder types, which variables a driver may set) are in the register.

## D-072 Level 2 answers: aspect errors, imports, extension methods, test folders (2026-10-03)
Author decision. Answers Q-020 (d) to (i), TOP-10 and Q-011 again; refines D-035, D-052, D-055, D-066, D-068. Follow-up questions were answered in the session the same day.
- **Aspect errors (d, TOP-10).** An error the aspect does not recover ends it and is raised again in the driver at the `apply` line; the driver's `recover` reads it in `$error`, an exception object with `code`, `message` and `line` (new field). A `main` that returns normally means code 0. `over;` in an aspect ends the aspect and the driver goes on after `apply`; in the driver it ends the program. `panic;` in an aspect ends the application: the driver panics too, frees the memory and exits with code 1.
- **Aspect scope (a, b, c)** confirmed: one `apply`, one new scope; aspect-level declarations are shared by `main` and the methods of the aspect only; `main` is implicit, not public; no member is public; no sibling processes.
- **Import path (e).** Both forms: unquoted folder names joined by `/` (`lib/db`, `$EVE_LIB/db`) or a string expression (`"lib"`, `$root_path/"lib"`).
- **Import list (e).** `use (m)`: members as `m.name`; `use (m as x)`: `x.name`; `use (m(*))`: the public members of `m` without prefix; `use (*)`: every module of the folder, namespaces merged. A name conflict makes the import fail; the modules are then listed one by one. Standard modules enter the language this way (`print`).
- **Modules and the host (f).** A module can't read the globals of the script that imports it; it communicates through parameters.
- **Extension methods (Q-011).** A module-level `method _name(@self: ClassName …)` extends the class: called as `obj.name(…)`, private to the declaring module. Inside a class `_` still means protected; no prefix is private (D-035).
- **Spreading (i).** `apply a(value, *list_args)` and `apply a(param: value, *map_args)` are part of level 2 (0.1).
- **Test folders (g).** A level 2 test that needs more files has a folder named by its code, `test/level2/b07/`, with `asp/` and `lib/`. Proposed (VM): the project root of a driver is its own folder, and the VM also searches `<folder>/<code>/asp` and `<folder>/<code>/lib`; to confirm when the first test is written.
- **VM tests moved (h).** `b01`–`b06` and `c01`–`c05` are now `test/vm/v01`–`v11` (`runtest.py vm`); level 2 is empty and keeps `b01…` for aspects and modules.
- Applied: processing.html (Errors of an aspect), modules.html (Import table and syntax, notes, extension methods), syntax.html (`_` rows, `$error.line`), spec/semantics/variables.md (`$error.line`), test/vm, test/readme.md, manual/usage.md, script/runtest.py. VM: `$error.line`, `apply`, imports and extension methods are not implemented.

## D-073 A test can be a folder: a whole Eve project (2026-10-03)
Author decision. Replaces the test-folder part of D-072 (g) (a folder named by the code next to the test file).
- A project test is a folder `test/levelN/<name>/` that contains the driver `<name>.eve`. The folder is the project root: `asp/` (aspects), `lib/` (modules), `data/` (input), `out/` (files written by the test, `$EVE_OUT`), or any other folder the project needs. Aspects and modules are found as D-055 says, from that root.
- Its expectations are in `<name>/expect.json`, one object with the keys of the level file, plus `"files"`: `{"out/report.txt": "text" or [lines]}`, files that must exist after the run with that content.
- `script/runtest.py` finds both shapes (`<name>.eve` and `<name>/<name>.eve`), runs a project test as `eve <name>.eve` from its folder, and empties `out/` before each run. `out/` is git-ignored.
- Level 2 and level 3 tests are project tests; a single `.eve` file stays valid at every level (level 1, `vm`).
- Applied: script/runtest.py, .gitignore, test/readme.md, test/level2/readme.md. Checked with a throwaway project test (runs from its folder, `out/` emptied, missing file reported).

## D-081 Process end, exit codes, error classes, imports, `defer`, unsafe methods, parallel errors and limits (2026-10-05)
Author decision, from the answers to review points RST-D03, RST-D04, RST-D05, RST-D06, RST-X01, RST-X02, RST-X03, RST-R02, RST-R04, RST-R05, RST-R06, RST-R07 (`review/05-structure-errors.md`) and RMT-D02, RMT-X01, RMT-X02, RMT-R01 (`review/06-multitasking.md`), and the answers of 2026-10-05. Replaces the `finalize` rules of D-055 and D-063 and the exit-code rules of D-010, D-038 and D-055. The `service` script (RST-R03) gets its own decision.

**1. `finalize` runs on every way out** except `panic` and an unexpected stop: `return`, `over` (was skipped), `exit`, `abort` (was skipped), the normal end of `recover`.

**2. Exit codes are separate from error codes.** The exit code of a process is a small number; the code of an error (`$error.code`, the `$err_` constants) identifies the error and is never used as an exit code.

| Exit code | Meaning |
|---|---|
| 0 | normal end (`return`, `over`, end of `recover`) |
| 1 | `panic` |
| 2 | failed `expect`, not recovered |
| 3 | failed `assert`, when the process ends because of it |
| 4 | unhandled error (`raise` or run-time error, not recovered); `abort` ends with 2 or 4, as its error |
| 5 | unexpected stop: Ctrl+C in the interpreter; a `halt` breakpoint (active in debug mode only, ignored in production) that the user ends with Ctrl+C or `stop` instead of resuming; recursion too deep; out of memory; hard time-out |

The command-line errors of the VM (64, 65, 66, 70, `manual/usage.md`) are not exit codes of a process.

**3. Error classes.** Errors are organized in classes derived from `Error`, and every class has a code. `recover` tests the class with `is` (`if $error is IoError do retry; done;`) or compares the code with a constant. The class names of the standard errors (`Panic`, `ExpectError`, `IndexError`, `KeyError`, `DivideError`, `OverflowError`, `ConvertError`, `ParseError`, `NullError`, `ArgumentError`, `FileError`, `AccessError`, `IoError`, `ModuleError`, `ProcessError`, `MemoryError`, `TimeoutError`, `DeadlockError`, `OutputError`, `RecursionError` 44, `ParallelError` 45) were proposed by the model: confirm or rename. A project defines its own classes with codes of the project range.

**4. Imports.** The system library (`io`, `exception`, …) is imported implicitly, a fixed versioned list; every other library is imported by name. In debug mode the compiler warns on `use (m(*))` and `use (*)`; both stay valid.

**5. `defer`** (new keyword). `defer statement;` in a method, function or process runs when the subprogram ends, by any path except `panic`; several run in reverse order.

**6. Unsafe methods.** A private variable of a module is written in `initialize`, and after that only by an unsafe method, whose name ends with `!` (`method .tick!()`, called `counter.tick!();`). Methods may now carry `!` (D-027 gave `!` to functions only); on a method it means "unsafe for parallel processing". An aspect that calls an unsafe method, directly or through other calls, can be applied but not started; the compiler checks the call graph. Shared state between parallel aspects goes through a channel.

**7. Errors of a parallel group.** A failing aspect never blocks its siblings. `done` raises one `ParallelError` whose `$error.errors` lists every failed aspect in the order of `start`: `{index, aspect, code, message, line}`. Policy `parallel on error cancel do … done;` cancels the unfinished aspects after the first error; `parallel within 30s do … done;` sets a deadline. The default waits for all.

**8. Time-out per aspect.** An aspect may set `set $timeout = 5s;`, which shadows the driver value inside that aspect only.

**9. Parallel limits.** One level: an aspect started by the driver may start at most 2 leaf aspects; a leaf starts none; an aspect never applies another. `$max_parallel` (default 8 aspects per parallel group of the driver) and `$cores` (default the hardware cores, at most 16) are set in the `.cfg` file of the driver. When no core is free, a `start` waits until one is. The compiler warns when it can see that a group starts too many aspects.

**10. Jobs are observable.** Every run of a driver writes `$EVE_OUT/run_<driver>_<datetime>.log` (author: the file name; datetime `YYYYMMDD_HHMMSS` of the start). Every job, `apply`, `start` and parallel group writes a start line and an end line, one JSON object per line, with the fields `time`, `driver`, `process`, `job`, `kind`, `event`, `status`, `attempt`, `duration`, `line`, `code`, `message` (fields chosen by the model). Applied in processing.html, section Run log.

Applied to the tutorial: processing.html (interruption table and text, recover table, parallel errors, finalize, new section Defer), exceptions.html (Error members, new section Error Classes, class column and codes 44, 45 in Standard Exceptions, new section Exit Codes, code ranges), modules.html (unsafe methods, the counter example, imports and system library), multitasking.html (group syntax, one-level rule, unsafe methods, errors, policies, deadline, time-out, workers and limits), methods.html (new section Unsafe methods), functions.html (subprogram table), syntax.html (keywords `defer`, `cancel`, `within`; meaning of `defer`; `$timeout`, `$cores`, `$max_parallel`), sidebars of processing, exceptions and methods. Also `spec/semantics/variables.md` and `manual/usage.md` (exit codes). The VM and the tests are not changed (D-075).
