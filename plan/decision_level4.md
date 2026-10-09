# Decisions, level 4: parallel processing and streams (version 0.3)

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. Ids are shared by all the decision files ([level 1](decision_level1.md), [2](decision_level2.md), [3](decision_level3.md), 4, [5](decision_level5.md), [6](decision_level6.md), [7](decision_level7.md)); the list of levels is in [decision_level3.md](decision_level3.md) and [version_map.md](version_map.md).

## Scope

A driver uses several cores: it starts aspects in parallel groups, passes data through channels, and processes large data as streams of batches with back-pressure. A waiting aspect gives its core to another one. Memory is freed per aspect call and per job (region memory). Level 4 tests (`test/level4`, prefix `d`) are deterministic: the same input gives the same output and the same errors in the same order, whatever the scheduling.

Features: F-MTK-01 to F-MTK-05, F-LNG-17, F-VM-05, F-SPEC-05.

Decisions already taken in other files: D-047, D-048 (data rules of parallel work), D-051 (channels), D-066 (parallel aspects), D-067 (multitasking, generators, a waiting aspect gives its core away), D-081 (unsafe methods, all errors of a group, `on error cancel`, `within`, `$timeout` per aspect, `$cores`, `$max_parallel`, one level of nesting).

## Draft features

1. **Stream type.** `Stream(:T)` is the common type of generators, file lines, query results, channels and network streams: `for x in s do … done;` reads any of them, with back-pressure (review RMT-R02).
2. **Dataflow operators.** `map`, `filter`, `batch(n)`, `partition(k)`, `merge`, `window(time)` on streams, and a `parallel(n)` stage, so many ETL scripts need no explicit parallel group (review RMT-R04).
3. **Generators feed channels.** A producer aspect turns a generator into a channel (D-067 rule 6); a helper of the library does it in one line.
4. **Local scheduler.** The worker pool and its event loop, one implementation for files, sockets, databases and timers (review RMT-R03).
5. **Region memory.** One arena per aspect call and per job, freed at the end; long-lived memory only for modules and channels (review RVM-R02). Fits the driver memory space of D-083.
6. **Deadlock and time-out reports.** A deadlock or a time-out names the waiting aspects and the channel in `$error.errors`.

Status of the draft features (2026-10-08): 1 and 2 are cut to Version 0.3 and the rest moves to Version 0.4 (D-142); 3 moves to Version 0.4 with the generators; 4 and 5 are the stages A to C of the VM (D-144); 6 is in D-140 and D-141.

**Ready to implement (2026-10-08).** Specification: `spec/semantics/multitasking.md`, the grammar `parallel-processing-level-4` and `traits-and-generic-classes-level-4` in `spec/syntax/grammar.md`, `spec/syntax/declarations.md#traits-and-generic-classes`. Tests: d01 to d03 (thread safety, pass), d04 to d26 (written first, they fail until the VM has them; the compile-error tests check the message in `stderr`, so a parser that does not know the syntax yet does not pass them). Order of work: d04 to d11, d25, d26 (groups, stage A), d12 to d16 (channels, atomics, split), d17 to d19 (tasks in a job), d20 to d24 (traits and generic classes), then `runtest.py --repeat`, stage B and the benchmark `p4a_parallel_sum`.

- Q-023 How is an aspect marked as thread safe or not? (answered: D-090)
- Q-035 Asynchronous subprograms: open points
- D-089 Thread safety is decided by the compiler; `!` means stochastic; generators; atomic and mutex
- D-090 `exclusive aspect` and `concurrent aspect`
- D-138 Answers to the version map; one file for versions and features

- Q-023 How is an aspect marked as thread safe or not? (answered: D-090)
- Q-035 Asynchronous subprograms: open points
- D-089 Thread safety is decided by the compiler; `!` means stochastic; generators; atomic and mutex
- D-090 `exclusive aspect` and `concurrent aspect`
- D-138 Answers to the version map; one file for versions and features
- D-140 Parallel groups: syntax, rules, output and errors
- D-141 Channels: rules completed
- D-142 Streams and the split of data
- D-143 Asynchronous tasks in a job
- D-144 Determinism, durations and the stages of the VM
- D-145 Traits, abstract classes and generic classes in Version 0.3
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

## D-143 Asynchronous tasks in a job (2026-10-08)
Model solution; answers Q-035 (a), (c), (d) and keeps the author's answer (b). Specification: `spec/semantics/multitasking.md#tasks-in-a-job`; tests d17 to d19.
- **(a) Results.** An `async procedure` gives its results by `@` parameters, ready after the `done` of the job (or at once after `await`). An `async function` is only awaited, in an expression: `new size := await measure(path);`. `spawn` of a function is a compile error, because its result would be lost; the program spawns a procedure with an `@` output instead. One way for each case keeps the reading simple.
- **(b)** (author) An `async` subprogram is called only with `spawn` or `await`; a plain call is a compile error.
- **(c) Where.** `spawn` only in the `do` region of a job (a labelled job, D-034), in a driver, an aspect or an async subprogram. `await` anywhere in a process, a job or an async subprogram: it starts the task and waits for it at once. Outside a job it behaves like a plain call that may give the core away while it waits.
- **(d) Errors.** A failing task does not stop the other tasks of the job. The `done` of the job waits for every spawned task, then raises a `ParallelError` (45) whose `$error.errors` lists the failed tasks in the order of `spawn`, with `aspect` empty and the subprogram name in the message. An error of the main flow of the job (including an `await`) ends the main flow; the job still waits for its spawned tasks, then raises the error of the main flow, or a `ParallelError` with it as item 0 when tasks failed too.
- **Core.** The tasks of a job share the core of the job: one runs at a time and switches only when it waits (D-104). There is no data race between them, so they may write the variables of the job; still, one `@` output belongs to one task, as in a group.
- **Words.** `async` is contextual (only before `function` or `procedure`, D-116); `spawn` and `await` are reserved, because `await f(x)` would otherwise read as a call of a function named `await`.

## D-144 Determinism, durations and the stages of the VM (2026-10-08)
Model solution. Specification: `spec/semantics/multitasking.md#determinism` and `#implementation-notes`.
- **Rule of the language.** A program whose result does not depend on the order of the values of several senders gives the same output and the same errors at every run (D-140 output and error order, D-141 order per sender). Level 4 tests are written that way and must pass 100 runs in a row (exit of Version 0.3): the runner gets an option `--repeat N`.
- **Durations.** A duration literal is an integer followed at once by a unit: `ms`, `s`, `m`, `h` (`10ms`, `30s`, `2m`). Its type is `Duration`; level 4 uses it in `within`, `wait` and `$timeout`; arithmetic and the time types stay in level 5 (D-125). Replaces "there is no lexical form for a duration" in `lexical.md`.
- **Stage A of the VM, one core.** Every started aspect and every spawned task runs on its own interpreter thread, but only the thread that holds the **baton** runs. The baton passes only when the running task waits (full or empty channel, `wait`, `await`, inner `done`, end of the task), to the next ready task in the order of `start`. The result is deterministic by construction, pipelines with more stages than cores work, and deadlock is simple to detect (every unfinished task waits and no timer is pending). It needs no change of the tree-walking interpreter: each OS thread keeps its own Zig call stack.
- **Stage B, many cores.** Up to `$cores` batons. Shared structures become thread safe: channels (mutex and condition), `Atomic(:T)` (the atomics of the machine, D-132), the module table (read only after the link step). The same tests must pass. A benchmark `p4a_parallel_sum` and its Python twin measure the gain.
- **Stage C, region memory (F-VM-05).** Each task allocates in its own arena, freed when the task ends; outputs and channel values are copied into the arena of the receiver. Done after stage B, when the benchmarks show it pays.
- **Not in Version 0.3:** `Mutex` (D-089 proposal): atomics and channels cover the level, and a lock is the main source of deadlocks. The module `task` (`round_robin`, `until`) goes with the generators to Version 0.4.

## D-145 Traits, abstract classes and generic classes in Version 0.3 (2026-10-08)
Model solution; adopts D-039 for level 4 and settles its open points. Specification: `spec/syntax/declarations.md#traits-and-generic-classes`; tests d20 to d24.
- **Trait.** `trait Printable is … end Printable;` holds method signatures that end with `;` (required) and methods with a body (provided, they may call the required ones through `self`). No attributes, no constructor, no instance. Every method of a trait is public. A trait is a type: `new p: Printable := pt;`, `pt is Printable`.
- **Adopting.** `class Point = {x: Integer, y: Integer} <: (Object, Printable) is`: the list after `<:` has one class (with state) first, then any number of traits. A method of the class wins over a provided method. Two traits that provide the same method name force the class to write it, otherwise a compile error. A class that can be created must implement every required method, otherwise a compile error that names the class and the method (never `Null` at run time).
- **Abstract class.** A class with at least one required method (a signature with `;`). Calling its constructor is allowed only as the first statement of a subclass constructor (`let self := Shape(name);`); anywhere else it is a compile error.
- **Generic class.** `class Box(:T) = {item: T} <: Object is`. The type argument is always written when an object is made, `Box(:Integer)(5)`, like `Channel(:Integer)(capacity: 10)`: no inference in Version 0.3. A constraint is written `(:T <: Comparable)`. Generic functions outside a class wait for Version 0.4; a method of a generic class may use `T`.
- **Library traits of Version 0.3:** `Iterable(:T)` (read by `for`), `Stream(:T) <: Iterable(:T)` (D-142), `Comparable` (`method compare(@self, other) => (@result: Integer);`) and `Printable` (`method describe(@self) => (@result: String);`, used by `print` and by `{x}` in a string). The basic types adopt `Comparable` and `Printable` in the library. Adopting a trait for an existing type outside its declaration waits for Version 0.4.
