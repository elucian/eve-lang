# Multitasking: parallel groups, channels and tasks

Status: **0.1-draft**, level 4 (version 0.3). Sources: D-047, D-048, D-051, D-066, D-067, D-081, D-089, D-090, D-104, D-129, D-130, D-132, D-140 to D-145, D-152 (Eve macro). Tests: `test/level4` (d01 to d35). Grammar: [`../syntax/grammar.md#parallel-processing-level-4`](../syntax/grammar.md#parallel-processing-level-4). Thread safety of modules: [`modules.md#managed-and-direct-modules`](modules.md#managed-and-direct-modules).

Eve has two ways to do several things at once. A **parallel group** starts aspects on several cores. A **job with tasks** runs asynchronous subprograms on one core, taking turns while they wait. **Channels** connect tasks that run at the same time. The tutorial calls the first **concurrency** (`concurrency.html`) and the second **multitasking** (`multitasking.html`), two pages of phase 5 (D-146). Generators and the module `task` are level 5 (version 0.4).

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

| Place | Group | `start` |
|---|---|---|
| a process of the aspect run by a command (level 1, a primary aspect) | yes | any number (`$max_parallel` at a time) |
| a process of an aspect it calls (level 2) | yes, one group | at most 2 `start` statements, none in a loop |
| a process of an aspect called from there (level 3, a leaf) | no | no |
| an applied aspect that is not in the first two levels, a function, a procedure, a method | no | no |
| outside the `do` region of a group | | no |

The levels are those of the calls between aspects (D-179: at most three, no cycle). Only the call of an aspect makes a level; a private process started in a group is a task of that group and counts in its limit of 2 at level 2, but it is not a level. A primary aspect is serial: its processes are applied and a `start` of one of them is a compile error; its groups start aspects.

A violation is a compile error (exit 65). `$max_parallel` (default 8) is not a compile rule: a start beyond it waits until a task of the group has ended.

### What can be started

`start` starts a `concurrent aspect`, or a private process of the concurrent aspect in which it is written (D-179). An aspect without a kind word is `exclusive` (D-130), a `primary` aspect is run by a command (D-181), and starting either is a compile error that names the aspect. A private process of an exclusive or primary aspect is applied, and a `start` of it is a compile error. A concurrent aspect is checked at its declaration: it fails to compile when it can reach a function or procedure that is not thread safe (D-089, D-129, D-137). A private process that is started uses only the thread-safe names of its aspect: constants, atomic variables, channels and thread-safe subprograms; any other aspect-level name is a compile error that names it and the chain of calls. A private process that is only applied uses every name of its aspect.

In an **Eve macro** (level 5, D-152) the aspects share the top-level declarations of the file. A concurrent aspect uses only the thread-safe ones: constants, classes, atomic variables, channels, and subprograms that the compiler proves safe (`../syntax/declarations.md#eve-macro-level-5`; tests e17 to e20).

### Data rules

- **Inputs by value.** The arguments are evaluated at `start` and copied: the task works on its own copy and the process that started it may go on changing its variables.
- **One owner for each output.** An `@` argument is a reference that belongs to one task. The compiler rejects the same variable, or the same element with a constant index, given to two starts of a group. The VM checks elements with a computed index at `start`. Both report `$err_output` 43: `Output {name} is given to two tasks of the group`.
- **Channels** are the only objects that several tasks may share (see below).
- **Modules are shared**: every task sees the same copy of a module. A concurrent aspect calls only thread-safe members (`modules.md`). The variables of a managed module are `Atomic(:T)` (D-132), so `let count += 1;` from several tasks gives the exact total.
- An aspect sees no variable of the aspect that calls it, and its state belongs to one task (D-066).

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

`Channel(:T)` is a generic class of the core library (D-145). `capacity` is required; `senders` (default 1) is the number of closes after which the channel is closed. A channel is created before a group or in its declarations and passed to tasks with `@`: the parameter is declared `@jobs: Channel(:Integer)`.

| Operation | Meaning |
|---|---|
| `ch.send(v);` | put a copy of `v` at the end; wait while the channel is full |
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

`Stream(:T)` is a library trait that extends `Iterable(:T)`: `for x in s do` reads it value by value and waits when the next value is not ready (back-pressure). In version 0.3, `Channel(:T)` is the only stream; lists and ranges are `Iterable`. Generators, file lines and query results become streams in version 0.4 (D-142).

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

An asynchronous subprogram runs as a task that shares the core of its caller (D-104, D-143).

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
- The tasks of a job run one at a time and switch only when one waits, so they need no lock. One `@` output still belongs to one task.
- A failing task does not stop the others. The `done` of the job raises a `ParallelError` (45) that lists the failed tasks in the order of `spawn` (`aspect` is empty, the message names the subprogram). An error of the main flow of the job ends the main flow; the job waits for its tasks, then raises that error, or a `ParallelError` with it as item 0 when tasks failed too.

## Compile errors

Each is a compile error (exit 65). The message holds the text of the second column, so a test can check it.

| Rule | Message holds | Test |
|---|---|---|
| `start` of an exclusive aspect | `{aspect} is exclusive` | d06 |
| `start` outside a group | `start is allowed only in the do region of a parallel group` | d07 |
| the same output given to two starts | `Output {name} is given to two tasks of the group` | d08 |
| more than 2 starts, or a start in a loop, in the group of an aspect | `{aspect} starts more than 2 aspects` | d26 |
| a group in a function, a procedure or a method | `parallel is allowed only in a process` | d32 |
| a group in an aspect of the third level (a leaf) | `{aspect} is a leaf` | d31 |
| `start` or `apply` of a primary aspect | `a primary aspect is run by a command: it can't be applied or started` | b45, e109 |
| `start` of a private process in a primary or an exclusive aspect | `a primary aspect is serial: apply {name}` | d38 |
| a started private process uses a plain aspect-level name | `the concurrent aspect '{aspect}' uses '{name}', which is not thread safe` | d37 |
| a concurrent aspect run by a command, or called from a concurrent aspect | `a concurrent aspect is called from a primary or an exclusive aspect` | d39, d40 |
| `spawn` of an async function | `{name} is a function: use await` | d18 |
| a plain call of an async subprogram | `{name} is async: use spawn or await` | d19 |
| a concurrent aspect that reaches an unsafe member | `{member}, which is not thread safe` | d01, d03 |
| a concurrent aspect of a macro that uses an unsafe shared name | `uses '{name}', which is not thread safe`, `calls '{name}', which is not thread safe` | e19, e20 |

## Durations

A duration literal is an integer followed at once by a unit: `ms`, `s`, `m`, `h` (`10ms`, `30s`, `2m`, `1h`). Its type is `Duration`. Level 4 uses durations in `within`, `wait duration;` and `$timeout`; their arithmetic and the time types are level 5 (D-125, D-144).

## Determinism

A program whose result does not depend on the order of values from several senders gives the same output and the same errors at every run, on any number of cores: the output of a group is written in the order of `start`, `$error.errors` is in the order of `start`, and one sender keeps its order. Level 4 tests rely on nothing else and must pass 100 runs in a row (`runtest.py --repeat 100`).

## Implementation notes

Not normative (D-144). An implementation may reach the rules above in stages.

1. **Stage A, one core.** Each task runs on its own interpreter thread, but only the thread holding the baton runs. The baton passes when the running task waits (channel, `wait`, `await`, inner `done`, end of task), to the next ready task in the order of `start`. Deterministic by construction; a deadlock is "every unfinished task waits and no timer is pending".
2. **Stage B, many cores.** Up to `$cores` batons. Channels use a mutex and a condition; `Atomic(:T)` uses the atomics of the machine; the module table is read only after the link step.
3. **Stage C, memory.** The reference VM frees memory while it runs (D-151): values are reference counted and freed at the safe point of the region that made them (the end of a statement, of a pass of a loop, of a `done`); a tracing collector frees cycles at `done`. While the tasks of a group or a job run, nothing is freed: the zero counts wait until `done`. An arena per task, freed when the task ends, is a later step.

`Mutex` is not part of version 0.3.

## Open points

The `parallel(n)` stage and the operators `map`, `filter`, `merge`, `window` on streams (version 0.4). Generators feeding channels (version 0.4). A channel exported by a managed module.
