<!-- Generated from the specification, the tests and the benchmarks. Do not edit this page. -->

# Level 4: Parallel processing

Many cores and many waits: parallel groups, channels, streams with back-pressure, tasks in a job (`async`, `spawn`, `await`), deadlines and cancellation, and region memory. Generics for classes, traits and abstract classes also arrive here. The results of parallel code must be deterministic: it is 

| Code | Feature | Stage |
|---|---|---|
| [`F-LIB-11`](#f-lib-11-logging-and-observability) | Logging and observability | planned |
| [`F-LIB-12`](#f-lib-12-testing-module-test) | Testing module `test` | validated |
| [`F-LNG-11`](#f-lng-11-traits-abstract-classes-generics) | Traits, abstract classes, generics | drafted |
| [`F-LNG-17`](#f-lng-17-stream-type) | Stream type | drafted |
| [`F-LNG-18`](#f-lng-18-atomict) | `Atomic(:T)` | drafted |
| [`F-MTK-01`](#f-mtk-01-parallel-aspects) | Parallel aspects | validated |
| [`F-MTK-02`](#f-mtk-02-worker-pool-and-scheduler) | Worker pool and scheduler | drafted |
| [`F-MTK-03`](#f-mtk-03-channels) | Channels | validated |
| [`F-MTK-04`](#f-mtk-04-tasks-in-a-job) | Tasks in a job | validated |
| [`F-MTK-05`](#f-mtk-05-deadlines-and-cancellation) | Deadlines and cancellation | validated |
| [`F-SPEC-05`](#f-spec-05-multitasking-semantics) | Multitasking semantics | drafted |
| [`F-TLS-04`](#f-tls-04-debugger) | Debugger | drafted |
| [`F-TLS-08`](#f-tls-08-formatter-and-linter) | Formatter and linter | planned |
| [`F-TLS-09`](#f-tls-09-editor-support) | Editor support | drafted |
| [`F-VM-05`](#f-vm-05-region-memory) | Region memory | drafted |

## F-LIB-11 Logging and observability

Stage: **planned**.

Structured logs, job events, run reports, trace ids.

## F-LIB-12 Testing module `test`

Stage: **validated**.

Checks that print `ok`/`FAIL`, counters, `summary` that raises (`lib/test.eve`).

## F-LNG-11 Traits, abstract classes, generics

Stage: **drafted**.

`trait`, required methods, abstract classes, `class Name(:T)` with `Box(:Integer)(5)`, constraints `(:T <: Comparable)`, library traits `Iterable`, `Stream`, `Comparable`, `Printable`. Moved from Version 0.2 to Level 4.

*Partial:* traits, abstract classes, generic classes with erased type arguments and the library traits work; a constraint is not checked yet, generic functions wait for Version 0.4.

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

## F-LNG-18 `Atomic(:T)`

Stage: **drafted**.

A class of the standard library that wraps the atomic of the machine, for Logic, numbers, references and ordinals; `class Name <: Atomic(:T)`.

*Partial:* the declaration and the check of managed modules work, the value is a plain value; the operations (`add`, `get!`, `swap!`) need threads.

## F-MTK-01 Parallel aspects

Stage: **validated**.

`parallel … do start … done`, barrier, data rules, errors as a job.

*Done (stage A):* groups, labels, data rules, one owner per output (compile and run time), output in the order of start, ParallelError, nesting of one level.

## F-MTK-02 Worker pool and scheduler

Stage: **drafted**.

`$cores`, M:N, a waiting aspect gives its core away.

*Partial:* stage A, one core with a baton (task.zig): a waiting task gives the core away; `$cores` and `$max_parallel` wait for stage B.

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

## F-TLS-04 Debugger

Stage: **drafted**.

Debug mode, `halt` breakpoints, step, print variables, reports (`manual/usage.md`).

## F-TLS-08 Formatter and linter

Stage: **planned**.

`eve fmt`, `eve lint`.

## F-TLS-09 Editor support

Stage: **drafted**.

Syntax colors for VS Code and GitHub, then a language server.

*Partial:* tutorial highlighters `eve1.js`, `eve3.js`.

## F-VM-05 Region memory

Stage: **drafted**.

Arena per aspect call, job and request; long-lived heap for modules and channels.

*Partial:* the values are reference counted and freed at the safe points of their region (statement, pass of a loop, `done`), a tracing collector frees cycles at `done`, scratch memory per statement; nothing is freed while tasks run; benchmarks peak at 4.4 to 6.6 MB (`p4a_parallel_sum` 39 MB). Open: an arena per task.
