<!-- Generated from the specification, the tests and the benchmarks. Do not edit this page. -->

# Level 4: Parallel processing

Many cores and many waits: parallel groups, channels, streams with back-pressure, tasks in a job (`async`, `spawn`, `await`), deadlines and cancellation, and region memory. Generics for classes, traits and abstract classes also arrive here. The results of parallel code must be deterministic: it is 

| Code | Feature | Stage |
|---|---|---|
| [`F-LIB-11`](#f-lib-11-logging-and-observability) | Logging and observability | planned |
| [`F-LIB-12`](#f-lib-12-testing-module-test) | Testing module `test` | validated |
| [`F-LNG-11`](#f-lng-11-traits-abstract-classes-generics) | Traits, abstract classes, generics | validated |
| [`F-LNG-17`](#f-lng-17-stream-type) | Stream type | drafted |
| [`F-LNG-18`](#f-lng-18-atomict) | `Atomic(:T)` | drafted |
| [`F-MTK-01`](#f-mtk-01-parallel-aspects) | Parallel aspects | validated |
| [`F-MTK-02`](#f-mtk-02-worker-pool-and-scheduler) | Worker pool and scheduler | validated |
| [`F-MTK-03`](#f-mtk-03-channels) | Channels | validated |
| [`F-MTK-04`](#f-mtk-04-tasks-in-a-job) | Tasks in a job | validated |
| [`F-MTK-05`](#f-mtk-05-deadlines-and-cancellation) | Deadlines and cancellation | validated |
| [`F-SPEC-05`](#f-spec-05-multitasking-semantics) | Multitasking semantics | drafted |
| [`F-TLS-04`](#f-tls-04-debugger) | Debugger | drafted |
| [`F-TLS-08`](#f-tls-08-formatter-and-linter) | Formatter and linter | validated |
| [`F-TLS-09`](#f-tls-09-editor-support) | Editor support | drafted |
| [`F-VM-05`](#f-vm-05-region-memory) | Region memory | validated |

## F-LIB-11 Logging and observability

Stage: **planned**.

Structured logs, job events, run reports, trace ids.

## Missing

- Structured logs, job events, run reports, trace ids (shared with F-DAT-06).
- A log file test per record kind.

## F-LIB-12 Testing module `test`

Stage: **validated**.

Checks that print `ok`/`FAIL`, counters, `summary` that raises (`lib/test.eve`).

## F-LNG-11 Traits, abstract classes, generics

Stage: **validated**.

`trait`, required methods, abstract classes, `class Name(:T)` with `Box(:Integer)(5)`, constraints `(:T <: Comparable)`, library traits `Iterable`, `Stream`, `Comparable`, `Printable`. Moved from Version 0.2 to Level 4.

*Done:* traits, abstract classes, generic classes and generic subprograms with erased type arguments, the constraint `(:T <: Comparable)` checked at compile time (written or inferred type argument, generic class: tests e58, d44, d45) and the library traits work.

## Missing

Nothing.

An example that runs, and what it prints:

```eve
# a class adopts a trait: it writes the required method and gets the provided one
primary aspect d20_trait is
  trait Describable is
    method describe(@self) => (@result: String);
    method show(@self) is
      print "<{self.describe}>";
    return;
  end Describable;

  class Point = {x: Integer, y: Integer} <: (Object, Describable) is
    public method describe(@self) => (@result: String) is
      let result:= "({self.x}, {self.y})";
    return;
  end Point;

  process main is
    new p:= Point(x: 1, y: 2);
    p.show;
    expect p is Describable;
    new d:= p:Describable;
    print d.describe;
  return;
end d20_trait;
```

```text
<(1, 2)>
(1, 2)
```

## F-LNG-17 Stream type

Stage: **drafted**.

`Stream(:T) <: Iterable(:T)`, read by `for` with back-pressure; at level 4 `Channel(:T)` is the stream, and lists get `batch(n)` and `split(k)`. Generators, files and queries adopt it at level 5, with `map`, `filter`, `merge`, `window`, `parallel(n)`.

*Partial:* `for` on a channel, `batch`, `split`.

## Missing

- Built in the library `data.stream` (generators over lists and generators): `map`, `filter`, `take`, `drop`, `chain`, `numbered`, `sliding`, `merge`. Not yet: `parallel(n)`, and the operators on the streams of files and queries.
- The level 4 part (`for` on a channel, `batch`, `split`) is done.

## F-LNG-18 `Atomic(:T)`

Stage: **drafted**.

A class of the standard library that wraps the atomic of the machine, for Logic, numbers, references and ordinals; `class Name <: Atomic(:T)`.

*Partial:* the declaration and the check of managed modules work, the value is a plain value; the operations (`add`, `get!`, `swap!`) need threads.

## Missing

- `add`, `get!`, `swap!` on real threads; the value is a plain value today.
- A counter under parallel tasks gives the same total at every run (`--repeat 5`).

## F-MTK-01 Parallel aspects

Stage: **validated**.

`parallel … do start … done`, barrier, data rules, errors as a job.

*Done (stage A):* groups, labels, data rules, one owner per output (compile and run time), output in the order of start, ParallelError, nesting of one level.

## F-MTK-02 Worker pool and scheduler

Stage: **validated**.

`$cores`, M:N, a waiting aspect gives its core away.

*Done:* stage B. Up to `$cores` tasks run at the same time; a waiting task gives its core to the next ready one; the tasks of a job and the generators of a task share the core of their creator.

## Built

- `$cores` (the hardware cores, at most 16; `EVE_CORES=n` sets it for a run, `1` gives the baton of stage A), `$max_parallel` (the tasks of a group that run at a time; a start beyond it waits), the rule that only the primary aspect fans out (tests d25, d26, d31, d40, d48, d49).
- Lanes and permits (`task.zig`): the tasks that share a heap take turns; the lanes run in parallel, one permit for each core, handed in the order of `start`.
- Channels with a lock and a heap of their own for the messages; `Atomic` variables exact under `let` on every core (tests d15, d50, d51); the database layer with one connection and one lock (test d54); `p4a_parallel_sum` 165 ms to 80 ms.
- Every test of level 4 gives the same result in 50 runs, on 1, 2 and all cores.

## Missing

- A thread sanitizer run (the toolchain has none on Windows, TD-98).

## F-MTK-03 Channels

Stage: **validated**.

`Channel(:T)`, send, receive, close, pipelines, deadlock detection, time-out.

*Done:* send, receive, close, count, `senders`, automatic close, ChannelError 46, deadlock report, `$timeout`.

## F-MTK-04 Tasks in a job

Stage: **validated**.

`async` subprograms, `spawn`, `await`; the tasks of a job share its core. The module `task` (`round_robin`, `until`) moves to level 5 with the generators.

*Done:*.

An example that runs, and what it prints:

```eve
# spawn starts async procedures in a job, await waits for an async function; done waits for every task
primary aspect d17_job_spawn is
  async procedure square(n: Integer, @r: Integer) is
    wait 10ms;                         ** the core goes to the next task
    let r:= n * n;
  return;

  async function double(n: Integer) => (@result: Integer) is
    wait 5ms;
    let result:= n * 2;
  return;

  process main is
    new a, b, c:Integer;
    work: job
    do
      spawn square(3, @a);
      spawn square(4, @b);
      let c:= await double(5);
    done work;
    print "{a} {b} {c}";
  return;
end d17_job_spawn;
```

```text
9 16 10
```

## F-MTK-05 Deadlines and cancellation

Stage: **validated**.

Per-group time limits, cancel or collect errors.

*Done:* `on error cancel`, `within`.

## F-SPEC-05 Multitasking semantics

Stage: **drafted**.

`semantics/multitasking.md`: parallel groups, channels, tasks in a job, durations, determinism.

*Partial:* generators are level 5 (F-LNG-12).

## Built

- The page follows the rule that only the primary aspect fans out and a concurrent aspect is called only from it (where-a-group-is-allowed), with `$cores` and `$max_parallel`.

## Missing

- Generators are level 5 (F-LNG-12).

## F-TLS-04 Debugger

Stage: **drafted**.

Debug mode, `halt` breakpoints, step, print variables, reports (`manual/usage.md`).

## Missing

- The remaining debugger commands of `manual/usage.md`.
- A test per command.

## F-TLS-08 Formatter and linter

Stage: **validated**.

`eve fmt`, `eve lint`.

*Done:* `eve fmt [--check]` writes the layout of scripts (trailing white space, blank lines, line endings, the end of the file; idempotent on every file of the test folders) and `eve lint` reports unused variables, parameters, loop variables and imports, as specified in [tools.md](../../semantics/tools.md) (tests d46, d47).

## Missing

Nothing for the first version. A language server is not part of level 4.

## F-TLS-09 Editor support

Stage: **drafted**.

Syntax colors for VS Code and GitHub, then a language server.

*Partial:* tutorial highlighters `eve1.js`, `eve3.js`.

## Missing

- Syntax colors for VS Code and GitHub.
- The language server is not part of level 4 (backlog).

## F-VM-05 Region memory

Stage: **validated**.

Arena per aspect call, job and request; long-lived heap for modules and channels.

*Done:* the values are reference counted and freed at the safe points of their region (statement, pass of a loop, `done`); a tracing collector frees cycles; scratch memory per statement; a started aspect has a heap of its own that it frees while it runs and that goes whole at the end of the task; a channel keeps its messages in a heap of its own.

## Built

- A heap for each started aspect: a task that makes garbage in a loop peaks at 7 MB (1.1 GB before); the inputs, the outputs and the messages are copied between heaps (tests d51, d52, d53); `EVE_GC_VERIFY=1` is clean on the tests of levels 4 and 5.

## Missing

- The tasks of a job and the generators share the heap of their creator, and nothing is freed while one lives (TD-95).
