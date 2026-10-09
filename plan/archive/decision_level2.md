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
Author decision. Answers Q-021; the design is [design-multitasking.md](../design-multitasking.md).
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
**Status:** design drafted in [design-multitasking.md](../design-multitasking.md): generators one level deep (A), no cooperative block (B dropped); cooperative tasks are generators taking turns; a waiting started aspect gives its core away. Approved: D-067.

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

## Q-022 Assumptions of the level 2 tests b01 to b19 (2026-10-03; answered 2026-10-07 → D-112)
The level 2 tests (project tests, D-073) follow D-066, D-068 and D-072. These rules are assumed without a decision; confirm or correct each one (the test named after it changes with the answer):
(a) An import that fails on a name conflict (`use (*)`) raises `$err_module`; it happens before the process, so nothing can recover it and the exit code is 30 (b06).
**answer** Discard this feature. However the risk remain. We have improved modules with export, to mitigate this issue.
(b) Reading a private member of a module (`counter.total`) is a runtime error `$err_access`, exit code 21; it could also be a check-time error (exit 65) (b09).
**answer** This is a compiler time error. But maybe also a runtime error? Why.
(c) The keys of a map spread into named arguments are symbols named like the parameters: `apply add3(a: 10, *m)` with `m := {'b': 20, 'c': 30}` (b14).
**answer** good feature, we keep it/ is in tutorial? accepted.
(d) `$error.line` is the line of the `raise` in the aspect file, not the `apply` line of the driver (b15).
**answer** Correct, the originator line of error, with the stack trace that include the aspect name that failed.
(e) A driver may declare an extension method for a class imported from a module, and `use (m(*))` brings the class in as a bare name (`Point`) (b18).
**answer** Correct, though in practice we expect classes to be extended in modules. User can extend classes usually in aspects.
(f) `log_err` and `log_wrn` write `out/error.log` and `out/warning.log`, one message per line, no time stamp (b19; the names and the line format are open since D-057).
**answer** the error.log and warning.log can have data signature in filename. Add runtime data signature.
(g) Aspects are found in `asp/` and modules in the folder named by the import path, both relative to the folder of the driver (the project root, D-055, D-073).
**answer** modules are searched in lib/ if there is no path specified. We can also create $eve_lib_path, a comma separated list of folders like PATH of the operating system. EVE will search in this path to find a library with name specified. Also can search in standard library actually this is first where search for.

## D-082 `eve --doc` replaces `eved` (2026-10-05)
Author decision. Replaces the separate tool `eved` of D-053; the rules of the generated documentation do not change.
- Every function of the Eve tools is a command of `eve`: there is no second program. The documentation generator is the command `doc`: `eve --doc <folder | file.eve> [output folder]` on the command line, `doc …` in the REPL (every REPL command is also a `--<command>` option, `manual/usage.md`).
- It writes `<name>.md` for the file given, or for each `.eve` file directly in the folder; the output folder is `doc` by default and is created when missing. Exit status 0, 64 (path missing), 66 (can't read).
- Code: `evevm/src/doc.zig` (moved from `evevm/doc/eved.zig`, with Zig tips), the jump-table entry `doc` and the handler `cmdDoc` in `cli.zig`. `zig build doc` runs `eve --doc lib doc`. The build no longer makes `eved.exe`; `evevm/doc/eved.zig` and `bin/eved.*` are deleted. The declarations recognized now also include `generator` and `service`.
- Checked: `zig build test` passes; `zig build doc` regenerates `doc/io.md` and `doc/exception.md` unchanged; `eve --doc lib/io.eve <folder>` writes the same page.
- Applied: evevm README, `evevm/doc/README.md`, `evevm/lib/README.md`, `manual/usage.md` (command table, section "Documentation: doc"), tutorial modules.html, `plan/features_inventory.md` (F-TLS-07, F-DOC-05), `tools/TODO-vscode-plugin.md`.

## Q-037 Shape of the stack trace of an aspect error (2026-10-07; answered 2026-10-07 → D-113)
D-112 (d): `$error.line` is the line of the original `raise`, and the trace names the aspect. What is the trace? Proposal: `$error.trace` is a list of `(unit, line)` pairs, innermost first, for example `(("fail", 6), ("b17_aspect_trace", 8))`; `$error.unit` is the name of the aspect where it started. What is printed for an unhandled error: one line per pair on the error output, after the message?
**Answer:**
Yes, the error first, followed by error stack list in order of call, 
line x in function y
line x in procedure y
line z in aspect (aspect name)
in job label/ parallel label, loop label...
(whatever the block that host the aspect)

## Q-038 Where an aspect may extend a class (2026-10-07; answered 2026-10-07 → D-113)
Answer (e) says users extend classes in aspects. An extension method is private to the file that declares it (D-072). Is an extension method of an aspect visible only inside that aspect, and gone when `main` returns (state per call)? Classes across files are level 3, so this waits there; it is recorded to avoid a surprise.
**Answer:**
Yes, the method dissapears from the object. The returning objects will contain only the data they have accumulated if objects are pass back as output parameters or attached to channels. Methods attached are temporarly useful only in the aspect that assign them these features. With modules things are different if module is available (imported) the procedures are available where modules are imported but only if they are part of export.

## Q-039 Signature of the log file names (2026-10-07; answered 2026-10-07 → D-113)
D-112 (f): `error.log` and `warning.log` get a run signature. Proposal: the date of the run, `out/error_2026-10-07.log`, and several runs on the same day append to the same file. Alternative: date and time, `error_2026-10-07_14-30-05.log`, one file per run. Which one, and what is the signature when the program runs in the REPL?
**Answer:**
The date and time is also part of OS so is not required in the file name. Only the date is good enaugh. Because we have groups in log, that show the run number and the time. Make the logs: json so that a tool can use these files and create a html report in a UI. That we do not have yet.

## Q-040 Shape of the JSON log (2026-10-07; answered 2026-10-07 → D-114)
D-113: `error_<date>.log` and `warning_<date>.log` are JSON, grouped by run. Proposal: one JSON document per file, updated at each run (a run that starts on the same date appends a group):
```
{"runs": [{"run": 1, "time": "14:30:05", "script": "b09_log_files", "messages": [{"line": 6, "unit": "main", "text": "disk full"}]}]}
```
The first field of a group is the number of the run of that day. Alternative: JSON Lines (one object per line, appended, never rewritten), which is safer when two runs write at once and keeps the old rule "one message per line". Which one, and which fields does a message carry (`line`, `unit`, `level`)?
**Answer:**
One json per run, name is run-log-<date>.json it hase messages, message type, warning/error, the line, unit, level and the message itself. Organized on run data last runs appended at the end of the file.
Ok approved.

## D-113 Aspect error trace, extension methods of an aspect, JSON log files (2026-10-07, implemented 2026-10-07)
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
- The date is UTC, in the file name and in `time`. The test runner understands `{date}` in a file name and JSON file expectations (`script/runtest.py`, "files"); b09 uses both.
- Applied: `spec/semantics/aspects.md` (Log files), `test/level2/b09_log_files`, `script/runtest.py`.
- **Implemented** (VM, 2026-10-07): `$error.line`; the trace in `Report.trace` printed after the error on stderr (`line n in function f`, `procedure`, `method`, `aspect`, `driver`, `in job label`); `log_err` and `log_wrn` collect messages and the session appends the run to `out/run-log-<date>.json` (`vm.zig`, `writeRunLog`). `$error.unit` and `$error.trace` as variables are not implemented yet.

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
- Applied: `test/level2`, `test/level3`, `test/readme.md`, `plan/version_map.md`, `plan/version_map.md` (F-STR-01 and F-STR-03 to v0.2), `plan/decision_level3.md`. Not yet applied: the tutorial (modules.html says `$EVE_LIB`, and the `use (*)` conflict), `spec/`, the VM.

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

## D-136 The tests have pages in the tutorial, generated from the tests (2026-10-08)
Author decision. The last phase of the tutorial (Phase 8) has three pages: **Demos & Examples** (`examples.html`, only the demos that are in the scl repository, `tutorial/demo/`), **Feature Tests** (`features.html`, the conformity tests of every level, with the description and a link to each file on GitHub), **Smoke Test and Performance** (`quality.html`, one page: the smoke tests, the benchmarks with the times against Python, and the history of the runs, one table for each level; sidebar on three levels). When a test is added, removed or changed, or a benchmark run is saved, these pages must be updated: they are written by `script/genpages.py` from the files themselves (the description of a test is its first comment line; the level names come from `plan/version_map.md`; the times from `test/bmark/history.json`), and `runtest.py` and `bmark.py --save` call it after every run. Only the part between `<!-- GEN:BEGIN -->` and `<!-- GEN:END -->` is written, the text around it is edited by hand; the sidebars are `tutorial/data/features.json` and `quality.json`. `python script/genpages.py --check` tells whether a page is out of date. The pages are in the scl repository: commit them with `git -C tutorial`. Sources of the pages: the first line of each test file, so keep it a good description.
