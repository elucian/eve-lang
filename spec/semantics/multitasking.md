# Multitasking: parallel groups, channels and tasks

Status: **draft**, level 4. (Eve macro). Grammar: [`../syntax/grammar.md#parallel-processing-level-4`](../syntax/grammar.md#parallel-processing-level-4). Thread safety of modules: [`modules.md#managed-and-direct-modules`](modules.md#managed-and-direct-modules).

Eve has two ways to do several things at once. A **parallel group** starts aspects on several cores. A **job with tasks** runs asynchronous subprograms on one core, taking turns while they wait. **Channels** connect tasks that run at the same time. The tutorial calls the first **concurrency** (`concurrency.html`) and the second **multitasking** (`multitasking.html`), two pages of phase 5. Generators and the module `task` are level 5.

| Word | Meaning |
|---|---|
| task | one started aspect, one started private process of a concurrent aspect, or one spawned asynchronous subprogram |
| group | a block `parallel … do … done` that starts tasks and waits for all of them |
| barrier | the closing `done` of a group or a job: the process that opened it waits there until every task has ended |
| channel | a queue of fixed capacity that tasks of a group share |

## Parallel groups

```eve
[label:] parallel [on error cancel] [within duration]
  ** declarations, local to the group
do
  start aspect_name(arguments);
  ...
done [label];
```

- The options come in this order: label, `parallel`, `on error cancel`, `within`. A labelled group closes with `done label;`, an unlabelled one with `done;`.
- The declarations between `parallel` and `do` belong to the group and are dropped at `done`. A value needed after `done` is declared before the group.
- The `do` region holds ordinary statements and `start` statements. `start` may sit at any depth of `if`, `for`, `while` and `match` inside the `do` region, but not inside a function or procedure called from there.
- A process runs its groups one after the other: a group begins when the statement before it has ended.

### Where a group is allowed

Only the primary aspect fans out. An exclusive aspect is serial from end to end, and a concurrent aspect is a leaf of the work that may start its own private processes.

| Place | Group | `start` |
|---|---|---|
| a process of the primary aspect (the aspect run by a command) | yes | the concurrent aspects it calls, any number (`$max_parallel` at a time) |
| a process of a concurrent aspect | yes | its own private processes only |
| a process of an exclusive aspect | no | no |
| a function, a procedure, a method | no | no |
| outside the `do` region of a group | | no |

A concurrent aspect is called (`apply` or `start`, alone or in a group) only from the primary aspect: an exclusive aspect and another concurrent aspect do not call one, and a command does not run one. The chain of calls between aspects is at most three levels, with no cycle. A violation is a compile error (exit 65). There is no limit on the number of `start` statements of a group, and `start` may sit in a loop; `$max_parallel` (default 8) is not a compile rule: a start beyond it waits until a task of the group has ended.

### What can be started

`start` starts a `concurrent aspect`, or a private process of the concurrent aspect in which it is written. An aspect without a kind word is `exclusive`, a `primary` aspect is run by a command, and starting either is a compile error that names the aspect. A private process of an exclusive or primary aspect is applied, and a `start` of it is a compile error. A concurrent aspect is checked at its declaration: it fails to compile when it can reach a function or procedure that is not thread safe. A private process that is started uses only the thread-safe names of its aspect: constants, atomic variables, channels and thread-safe subprograms; any other aspect-level name is a compile error that names it and the chain of calls. A private process that is only applied uses every name of its aspect.

In an **Eve macro** (level 5) the aspects share the top-level declarations of the file. A concurrent aspect uses only the thread-safe ones: constants, classes, atomic variables, channels, and subprograms that the compiler proves safe (`../syntax/declarations.md#eve-macro-level-5`; tests e17 to e20).

### Data rules

- **Inputs by value.** The arguments are evaluated at `start` and copied: the task works on its own copy and the process that started it may go on changing its variables.
- **One owner for each output.** An `@` argument belongs to one task: the task works on its own variable and its value is copied to the output variable at `done`, so the process that started the task reads the result after `done`, not before. The compiler rejects the same variable, or the same element with a constant index, given to two starts of a group. The VM checks elements with a computed index at `start`. Both report `$err_output` 43: `Output {name} is given to two tasks of the group`.
- **Values do not cross tasks by reference.** The inputs, the outputs and the messages of a channel are copies: a list, a map or an object that one task changes is never seen changed by another. A function value given to a task keeps the variables it closes over as they were when it was given. Constants (`set`) are shared, and nobody can change them.
- **Channels** are the only objects that several tasks may share (see below).
- **Modules are shared**: every task sees the same copy of a module. A concurrent aspect calls only thread-safe members (`modules.md`). The variables of a managed module are `Atomic(:T)`, so `let count += 1;` from several tasks gives the exact total: reading an atomic variable and changing it with `let` are indivisible steps, on any number of cores. An atomic variable holds a scalar (a Logic, a number, a symbol or an ordinal); another type is an error.
- An aspect sees no variable of the aspect that calls it, and its state belongs to one task.

### Output

A task writes `print` and `write` into its own buffer. At `done`, the buffers are written to the standard output in the **order of `start`**, task after task; then the process that opened the group goes on. The output of a group is the same at every run and on any number of cores. `log_err` and `log_wrn` write to the error output at once, with the aspect name in front.

### Errors

A failing task never stops the other tasks. At `done`, when at least one task failed, the group raises one error:

| Member | Value |
|---|---|
| `$error.code` | `$err_parallel` 45 (`$error is ParallelError`) |
| `$error.message` | `{n} of {m} tasks failed` |
| `$error.job` | the label of the group, empty without a label |
| `$error.errors` | one record `{index, aspect, code, message, job, line}` per failed task, **in the order of `start`** |
| `$error.cancelled` | the number of tasks stopped by `on error cancel` |

`index` is the start number of the task in the group, from 1. In `recover`, `retry` runs the whole group again and `resume` goes on after its `done`. Without `recover`, the process ends with exit 4 and the error output lists the items, one per line.

```eve
recover
  print $error.message;                 ** 2 of 4 tasks failed
  for e in $error.errors do
    print "{e.index} {e.aspect}: {e.message}";
  done;
```

- **`on error cancel`**: after the first failure, the tasks not yet begun are not begun and the running ones are stopped at their next wait or statement. A cancelled task is not an error and is not listed; `$error.cancelled` counts them.
- **`within duration`**: when the time is over, every task still running is stopped and gets a `TimeoutError` (`$err_timeout` 41, `Time-out after {duration}`) in `$error.errors`.

## Channels

```eve
new jobs := Channel(:Integer)(capacity: 100);
new results := Channel(:Integer)(capacity: 100, senders: 4);
```

`Channel(:T)` is a generic class of the core library. `capacity` is required; `senders` (default 1) is the number of closes after which the channel is closed. A channel is created before a group or in its declarations and passed to tasks with `@`: the parameter is declared `@jobs: Channel(:Integer)`.

| Operation | Meaning |
|---|---|
| `ch.send(v);` | put a copy of `v` at the end; wait while the channel is full; the receiver gets a copy of its own |
| `ch.receive(@x);` | take the first value into `x`; wait while the channel is empty |
| `for x in ch do … done;` | receive the values one by one; the loop ends when the channel is closed and empty |
| `ch.close();` | this sender has finished |
| `ch.count()` | the number of values waiting; for monitoring only, never in a test |

- **Automatic close.** When a task ends, normally or with an error, the VM closes every channel the task has sent into and not closed. A failing producer never leaves its consumers waiting. A second `close()` by the same task does nothing.
- **Errors.** `send` into a closed channel, `receive` from a closed and empty channel, and a close beyond `senders` raise `ChannelError`, `$err_channel` 46: `Channel {name} is closed`. The name is the name of the variable that created the channel.
- **Order.** The values of one sender keep their order. The values of several senders are interleaved in any order: combine them with an operation that does not depend on the order, or send the index with the value.
- **Deadlock.** When every unfinished task waits on a channel and no timer is pending, the VM stops the waiting tasks. Each gets a `DeadlockError` (`$err_deadlock` 42) that names it: `Deadlock: consume waits to receive from jobs`. They appear in the `ParallelError` of the group, in the order of `start`.
- **Time-out.** A wait on a channel longer than `$timeout` (default `60s`) raises `TimeoutError` in that task. An aspect may write `set $timeout = 5s;`, which shadows the value of the primary aspect inside that aspect.
- After `done`, the process may still read what is left in a closed channel with `for`.

## Streams and batches

`Stream(:T)` is a library trait that extends `Iterable(:T)`: `for x in s do` reads it value by value and waits when the next value is not ready (back-pressure). In level 4, `Channel(:T)` is the only stream; lists and ranges are `Iterable`. Generators, file lines and query results become streams in level 5.

A group splits its data by hand, with two methods of lists. The size is always written at the call:

| Method | Result |
|---|---|
| `lst.batch(n)` | a list of lists of `n` elements, the last one shorter |
| `lst.split(k)` | `k` lists of nearly equal length, the first ones one element longer, in the order of `lst` |

```eve
new parts := rows.split(4);
new sums: [4]Integer;
parallel
do
  for i in (1..4) do
    start sum_part(parts[i], @sums[i]);
  done;
done;
new total := 0;
for s in sums do let total += s; done;
```

## Tasks in a job

An asynchronous subprogram runs as a task that shares the core of its caller.

```eve
async procedure load(path: String, @text: String) is … return;
async function measure(path: String) => (@result: Integer) is … return;

loading: job
do
  spawn load("one.csv", @a);         ** the job goes on
  spawn load("two.csv", @b);
  new n := await measure("three.csv");   ** starts it and waits
done loading;                        ** waits for every spawned task
```

- An `async` subprogram is called only with `spawn` or `await`; a plain call is a compile error.
- `spawn` starts an `async procedure`, only in the `do` region of a job. Spawning a function is a compile error: its result would be lost.
- `await` starts an async procedure (statement) or an async function (in an expression) and waits for it at once. It is allowed in a process, a job and an async subprogram.
- The tasks of a job run one at a time and switch only when one waits, so they need no lock: they share the core, the variables and the output of their caller, and they take turns with it. One `@` output still belongs to one task.
- A failing task does not stop the others. The `done` of the job raises a `ParallelError` (45) that lists the failed tasks in the order of `spawn` (`aspect` is empty, the message names the subprogram). An error of the main flow of the job ends the main flow; the job waits for its tasks, then raises that error, or a `ParallelError` with it as item 0 when tasks failed too.

## Compile errors

Each is a compile error (exit 65). The message holds the text of the second column, so a test can check it.

| Rule | Message holds | Test |
|---|---|---|
| `start` of an exclusive aspect | `{aspect} is exclusive` | d06 |
| `start` outside a group | `start is allowed only in the do region of a parallel group` | d07 |
| the same output given to two starts | `Output {name} is given to two tasks of the group` | d08 |
| a group in an exclusive aspect | `an exclusive aspect is serial` | d26 |
| a group in a function, a procedure or a method | `parallel is allowed only in a process` | d32 |
| `start` or `apply` of a primary aspect | `a primary aspect is run by a command: it can't be applied or started` | b45, e109 |
| `start` of a private process in a primary or an exclusive aspect | `a primary aspect is serial: apply {name}` | d38 |
| a started private process uses a plain aspect-level name | `the concurrent aspect '{aspect}' uses '{name}', which is not thread safe` | d37 |
| a concurrent aspect run by a command, or called from an exclusive or a concurrent aspect | `a concurrent aspect is called only from the primary aspect` | d39, d40, d48 |
| `spawn` of an async function | `{name} is a function: use await` | d18 |
| a plain call of an async subprogram | `{name} is async: use spawn or await` | d19 |
| a concurrent aspect that reaches an unsafe member | `{member}, which is not thread safe` | d01, d03 |
| a concurrent aspect of a macro that uses an unsafe shared name | `uses '{name}', which is not thread safe`, `calls '{name}', which is not thread safe` | e19, e20 |

## Durations

A duration literal is an integer followed at once by a unit: `us`, `ms`, `s`, `m`, `h` (`10ms`, `30s`, `2m`, `1h`). Its type is `Duration`, a count of microseconds, printed in ISO 8601 (`PT30S`). Level 4 uses durations in `within`, `wait duration;` and `$timeout`; an `Integer` of milliseconds is still accepted there. The arithmetic and the other time types are in [../library/time.md](../library/time.md).

## Determinism

A program whose result does not depend on the order of values from several senders gives the same output and the same errors at every run, on any number of cores: the output of a group is written in the order of `start`, `$error.errors` is in the order of `start`, and one sender keeps its order. Level 4 tests rely on nothing else and must pass 100 runs in a row (`runtest.py --repeat 100`).

## Implementation notes

Not normative. An implementation may reach the rules above in stages.

1. **Stage A, one core.** Each task runs on its own interpreter thread, but only the thread holding the baton runs. The baton passes when the running task waits (channel, `wait`, `await`, inner `done`, end of task), to the next ready task in the order of `start`. Deterministic by construction; a deadlock is "every unfinished task waits and no timer is pending". It is the behaviour of a machine with one core (`$cores` is 1).
2. **Stage B, many cores.** Up to `$cores` tasks run at the same time. A started aspect and the tasks of the job and the generators it creates form a **lane**: the tasks of a lane take turns on one core (as in stage A), the lanes run in parallel. A permit for each core goes from a task that waits to the next ready task whose lane is idle, in the order of `start`. A channel has a lock; `Atomic(:T)` variables are read and changed under one lock of the machine; the modules are loaded before the first task that needs them starts, so the module table is read only while tasks run; the database layer has one connection for the run, and the tasks take turns in it.
3. **Stage C, memory.** The reference VM frees memory while it runs: values are reference counted and freed at the safe point of the region that made them (the end of a statement, of a pass of a loop, of a `done`); a tracing collector frees cycles. A started aspect has a heap of its own: it frees its garbage while it runs, and the whole heap goes at once when the task has ended and its parent has copied the outputs. The inputs, the outputs and the messages of a channel are copied from one heap to another, and nothing else crosses; a channel keeps its messages in a heap of its own. The tasks of a job and the generators of a task share the heap of their creator, and nothing is freed while one of them lives.

`Mutex` is not part of level 4.

## Open points

The `parallel(n)` stage and the operators `map`, `filter`, `merge`, `window` on streams (level 5). Generators feeding channels (level 5). A channel exported by a managed module.
