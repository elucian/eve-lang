# Archive of level4.md: settled entries, full text

## D-089 Thread safety is decided by the compiler; `!` means stochastic; generators; atomic and mutex (2026-10-06)
Author decision. Separates determinism from thread safety (refines D-081, D-086, D-087).
- **`!` marks a stochastic function**: its result can differ for the same arguments (random, time, a changing value). A function without `!` is deterministic. `!` says nothing about thread safety: a stochastic function can be thread safe and a deterministic one may not be. The tutorial said "non-deterministic"; it now says "stochastic".
- **The compiler decides** whether every function and generator is thread safe, on the call graph (own arguments and locals: safe; a plain module variable: not safe; atomic variable, mutex or channel: safe; a caller is safe only if all its callees are). It fails the program when an aspect that is started in a parallel group can call a function that is not thread safe. `apply` (serial mode) has no such rule. Replaces "a plain function is always safe" and "a function that changes module state can't be used in parallel".
- **Generators.** A generator declared in a driver or an aspect is private, runs on one core and needs neither thread safety nor determinism. A generator exported by a module must be thread safe.
- **Atomic variables** (`Atomic(:T)`, operating system guarantees, no lock, no deadlock) and **`Mutex`** are documented with advantages, penalties and examples (multitasking.html, "Thread safety"; demos in `tutorial/demo/`). Proposed API, to review: `Atomic`: `add`, `set`, `get!`, `swap!`, `fetch_add!`, `compare_swap!`; `Mutex`: `acquire`, `release`, used with `defer`. Proposed deadlock rules: a task holds one mutex at a time (the compiler rejects nesting), and a wait is limited by `$timeout`.
- Applied: multitasking.html (Thread safety, generator rule, data rules), functions.html, modules.html, syntax.html and others (wording "stochastic"); `tutorial/demo/` with 18 demo files.

## D-090 `exclusive aspect` and `concurrent aspect` (2026-10-06)
Author answer to Q-023, a sixth alternative: "double down", so the author learns by pain, for a greater good. Every aspect declares what it is, with a mandatory keyword; the compiler signals the errors.
- **`exclusive aspect name is`**: runs alone, in serial mode, with `apply`. It may use any function and any module. `start` of an exclusive aspect is a compile error.
- **`concurrent aspect name is`**: may be started in a parallel group (and also applied). The compiler checks it at its declaration and fails when it can reach a function or generator that is not thread safe (D-089), naming the chain of calls.
- **`aspect` alone is an error.** A script begins with `driver`, `exclusive aspect`, `concurrent aspect` or `module`. `exclusive` and `concurrent` are reserved words.
- Applied: topology.html (kinds of scripts, skeleton), multitasking.html (Thread safety: "Marking an aspect", all started aspects are concurrent), modules.html, processing.html, syntax.html (reserved words), the highlighters `eve1.js` and `eve3.js`, and the demos in `tutorial/demo/`.
- **Not yet changed (parked):** `spec/`, `test/`, `demo/` and `manual/` still write plain `aspect` (9 files with declarations); the VM is paused. Change them when the spec work resumes.
**answer** plain aspects are analyzed at compile time and if unsafe, error will be created if start is used for these aspects.

## Q-023 How is an aspect marked as thread safe or not? (answered: D-090)
The compiler checks every aspect at `start` (D-089). Do we also mark the aspect in its own header, so that the error is reported where the aspect is written? Alternatives:

**Answer:**
Alternative option: I like double down on things because this is how humans learn. With pain! For a greater good. So we mark an aspect woth keywords: We have two kind of aspects: exclusive / concurrent so we create two new keywords: exclusive/ concurent instead of serial/parallel. User declare he wants an exclusive aspect or a concurent aspect, then the compiler will signal errors if situations make the aspect non concurent.

## Q-035 Asynchronous subprograms: open points (2026-10-07, level 4; answered: D-143)
Questions left by D-104 (c); also a TODO box in async.html.

(a) How does a spawned `async function` give its result: `new r := await f(x);` for an awaited one, and for a spawned one a result ready after the `done` of the job?

(b) Can an `async` subprogram be called without `spawn` or `await`? **Answer:** no; it must be started with `spawn` or `await`.

(c) Can `spawn` and `await` be used outside a job?

(d) When one task of a job fails, do the other tasks finish before the process goes to `recover`?

## D-138 Answers to the version map; one file for versions and features (2026-10-08)
Author decisions, answering the open questions of `version_map.md`. (1) **Generics and traits** (F-LNG-11, D-039) move from Version 0.2 to **Level 4, Version 0.3**. (2) The **bytecode** compiler and VM (F-VM-04), the portable **`.evb` file** (F-VM-07) and the **embedding API with a C ABI** (F-VM-08) move to a new **Version 0.7**, "Bytecode and embedding": all levels pass on the bytecode VM, an `.evb` file runs on another machine, a C program embeds the VM through the C ABI. (3) **One file**: `design/features_inventory.md` is merged into `design/version_map.md`, which now holds the levels, the versions and every feature with its status, grouped by version (108 features); the old file is removed and its links point to the new one. Consequences, open in the file: the generators (F-LNG-12, Version 0.4) need a method that can stop and continue and the bytecode VM is now later; and F-WEB-02 (Version 0.6) runs `.evb` code in the browser. Level 4 now covers parallel processing, streams, generics and traits.

## D-140 Parallel groups: syntax, rules, output and errors (2026-10-08)
Model solution, written at the author's request ("solutions, not questions"; readability first, safety second, performance last). It keeps the syntax of the tutorial (D-066, D-081, D-090, D-130) and fills its gaps, so the tests can be written first (TDD). The author may revise any point. Specification: `spec/semantics/multitasking.md`; tests d04 to d11, d25, d26.
- **Syntax.** `[label:] parallel [on error cancel] [within duration] { declaration } do { statement } done [label];`, the options in this order. A labelled group closes with `done label;`, an unlabelled one with `done;` (like the loops, D-034). The declarations between `parallel` and `do` are local to the group and are dropped at `done`; a value needed after `done` (an output, a channel to read later) is declared before the group.
- **Where.** A group is written in the `process main` of the driver, or in the `main` of an aspect that the driver starts (one level, D-081 rule 9). `start` is written only in the `do` region of a group, at any depth of `if`, `for`, `while` and `match` inside it, but not in a function or a procedure called from there: the starts of a group are visible in the group. `start` outside a group is a compile error (exit 65).
- **What.** `start` starts only a `concurrent aspect` (D-090, D-130): starting an exclusive aspect, also one without a kind word, is a compile error that names the aspect. The aspect is checked for thread safety at its declaration (D-089, D-129, D-137).
- **Nesting.** An aspect started by the driver may hold one group with at most 2 `start` statements, none of them inside a loop (the count is static, so the compiler checks it). An aspect started by an aspect is a leaf: a group in a leaf is a compile error. `$max_parallel` (default 8) limits the tasks of one driver group at run time: a start beyond it waits for a free place, it is not an error.
- **Data.** Inputs by value, copied at `start` (D-048). Each `@` output belongs to one task: the compiler rejects the same variable, or the same constant element, given to two starts of a group (`$err_output` 43, exit 65); the VM checks computed elements at `start` and raises `$err_output` at run time. A `Channel` is the only object two tasks may share (D-141).
- **Output.** A task writes into its own buffer; at `done` the buffers are written to the standard output **in the order of `start`**, one task after the other, then the driver goes on. The printed result of a group is therefore the same at every run and on any number of cores. Reason: readability of the output and repeatable tests weigh more than seeing the lines early. `log_err`/`log_wrn` go to the error output at once, with the aspect name in front.
- **Errors.** A failing task never stops its siblings. At `done`, when at least one task failed, the group raises one `ParallelError`, code `$err_parallel` 45, message `{n} of {m} tasks failed`, `$error.job` the label of the group (empty without a label). `$error.errors` is a list of error records `{index, aspect, code, message, job, line}`, one per failed task, **in the order of `start`** (not in the order of failure). `index` is the start number in the group, from 1.
- **`on error cancel`.** After the first failure, the tasks not yet begun are not begun and the running ones are stopped at their next wait or at their next statement; a cancelled task is not an error and is not listed. `$error.cancelled` holds the number of cancelled tasks.
- **`within duration`.** When the time is over, every task still running is stopped and gets a `TimeoutError` (`$err_timeout` 41, message `Time-out after {duration}`) in `$error.errors`. Durations are the literals of D-144.
- **Recovery.** As for a job (D-066): in `recover`, `retry` runs the whole group again, `resume` goes on after its `done`. Without `recover`, the process ends with exit 4 and the error output lists every item of `$error.errors`, one per line.

## D-141 Channels: rules completed (2026-10-08)
Model solution, completes D-051. Specification: `spec/semantics/multitasking.md#channels`; tests d12 to d14.
- **Create.** `new jobs := Channel(:Integer)(capacity: 100);`, optional `senders: n` (default 1). `capacity` is required (explicit memory bound). A channel is created before a group or in its declarations and passed to tasks with `@`; the parameter is declared `@jobs: Channel(:Integer)`.
- **Operations** as in the tutorial: `ch.send(v);`, `ch.receive(@x);`, `for x in ch do … done;`, `ch.close();`, `ch.count()`. Values are copied on send.
- **Automatic close (safety).** When a task ends, normally or with an error, the VM closes every channel the task has sent into and has not closed. A failing producer therefore never leaves its consumers waiting until the time-out. An explicit `close()` stays good style: it ends the stream early and documents the intent. A second `close()` by the same task does nothing.
- **Errors.** `send` into a closed channel and `receive` from a closed, empty channel raise `ChannelError`, code `$err_channel` 46, message `Channel {name} is closed`. The `for` loop never raises it: it ends when the channel is closed and empty. With `senders: n`, the channel closes after `n` closes; a close beyond `n` raises `ChannelError`.
- **Order.** The values of one sender keep their order. With several senders the interleaving depends on timing: a test (and a careful program) combines them with an operation that does not depend on the order (a sum, a count, a sort) or sends the index with the value.
- **`count()`** is for monitoring only; its value depends on timing, so tests never print it.
- **Deadlock.** When every unfinished task of a group waits on a channel (or on `done` of an inner group) and no timer is pending, nothing can move. The VM stops the waiting tasks; each gets a `DeadlockError` (`$err_deadlock` 42) whose message names the task, the operation and the channel: `Deadlock: consume waits to receive from jobs`. They appear in `$error.errors` of the `ParallelError`, in the order of `start`. The name of a channel is the name of the variable that created it.
- **Time-out.** A wait on a channel longer than `$timeout` (default 60s; an aspect may shadow it with `set $timeout = 5s;`, D-081 rule 8) raises `TimeoutError` in that task.

## D-142 Streams and the split of data (2026-10-08)
Model solution; answers the open question of this file (a stream as the input of a group; the author: "the batch must be defined how large it is"). Specification: `spec/semantics/multitasking.md#streams-and-batches`; test d16.
- **No new syntax.** The split is written by the program with two methods of lists, and the size is always written at the call (no default, explicit): `rows.batch(n)` returns a list of lists of `n` elements each, the last one shorter; `rows.split(k)` returns `k` lists of nearly equal length (the first ones one element longer), in the order of `rows`. Both are deterministic.
- **Pattern** (Bulk Synchronous Parallel, D-047): `new parts := rows.split(4); new sums: [4]Integer; parallel do for i in (1..4) do start sum_part(parts[i], @sums[i]); done; done;`. The results are indexed, so their combination after `done` does not depend on timing.
- **`Stream(:T)` in Version 0.3** is a library trait (D-145) that extends `Iterable(:T)`: it is what `for x in s do` reads, value by value, waiting when the next value is not ready (back-pressure). In Version 0.3, `Channel(:T)` is the only stream; lists and ranges are `Iterable`. Generators, file lines and query results adopt `Stream` in Version 0.4 (level 5), with the operators `map`, `filter`, `merge`, `window` and the `parallel(n)` stage (draft feature 2), because their sources arrive there. `batch(n)` on a channel waits for Version 0.4 too.
- `F-LNG-17` in `version_map.md` is reduced to this part; the rest moves to Version 0.4.
