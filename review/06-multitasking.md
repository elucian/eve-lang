# 06 Multitasking (`RMT`)

## Advantages

**RMT-A01 No shared mutable memory between parallel units.** Inputs by value, one owner per `@` output, channels as the only shared object, values copied on send (D-047, D-048, D-051, D-066). This is the actor/CSP discipline that makes Erlang and Go servers robust, without locks in the language.

**RMT-A02 Bulk Synchronous Parallel as the default pattern.** `parallel … do start … done` with `done` as the barrier is deterministic, deadlock-free (tasks never wait for each other) and easy to teach. It matches batch ETL perfectly (partition, transform, merge).

**RMT-A03 Waiting gives the core away, invisibly.** D-067: I/O, `wait`, channels release the worker (M:N scheduling). Code stays sequential, no `async`/`await` colouring. This is the Go/Erlang model, and the right one for a server that calls databases and services.

**RMT-A04 Generators are not coroutines.** Laziness without a second stack per task (D-067 rule 1).

## Disadvantages

**RMT-D01 Only the driver `main` can start work.** A server needs concurrency per request (thousands of in-flight aspects started by the network loop, not by `main`). The current rule must be generalized (`RST-R03`).

**answer** We have not design the server yet. Some applcation need to be executed on client (with different rules), one command is to push code to the server and make the server compile the scripts received and execute them. So the server can have it's own rules. The "server" script is not yet even defined.

**RMT-D02 "A failed aspect does not stop the others; `done` raises the *first* error".** *Applied 2026-10-05: D-081.* D-055, D-066. In fan-out calls (50 services), the user needs all errors and partial results, plus cancellation when one failure makes the rest useless. Neither cancellation nor deadlines exist (only a global `$timeout` on channel waits, D-051). 

**answer** parallel aspects are designed to fail and not block other siblings. The conclusion that process must fail is done in recover region of the process. In this region, information about each aspect in the "parallel job" must exist. Maybe a json like structure? With all errors in the parallel job that failed not only first error.

**RMT-D03 Channels are bounded but unnamed across processes.** `Channel(:T)(capacity, senders)` lives inside one VM. The ETL/server future needs the same abstraction across machines (a network stream with back-pressure), and the current API (`send`, `receive(@x)`, `close`, `count`) has no notion of a remote end, of failure, or of acknowledgement.

**answer** I do not understant the issue properly, we need a document md that explain the issue the sollution suggested. Using multiple servers is something I have not anticipated. We need a client/server protocol that I know. We can probably send data over network, receive data over network, maybe on parallel streams, put data together. e.t.c.

**RMT-D04 Generators and channels don't compose.** A generator can't be passed to `start` (D-067 rule 6), so a streaming source must be wrapped in a producer aspect + channel. Correct, but the common case (stream rows from a file to N workers) needs three constructs.

**answer** Need research. I see no alternatives.

**RMT-D05 Not in 0.1.** D-050. The headline features of a data-processing language (parallel steps, streams) are designed but absent, and the VM architecture that would support them (tree walker on the Zig stack) has to be replaced first (`RVM-D01`).

**answer** Current VM design is subject to refactoring.

## Antipatterns

**RMT-X01 Global time-out.** *Applied 2026-10-05: D-081.* `$timeout` for every channel wait (D-051). Time-outs belong to an operation or a scope (a request has 2 s, a nightly job 2 h), not to the process.

**answer** Agree, what we do? We define $timeout per aspect? A new timeout defined in Aspect would be private to the aspect shadow the driver timeout. 

**RMT-X02 "First error wins".** *Applied 2026-10-05: D-081.* Discards information and depends on scheduling order, so the same failing run can report different errors: non-deterministic diagnostics in a design that is otherwise deterministic.

**answer** agree we will capture all errors in a parallel job.

## Recommendations

**RMT-R01 Structured concurrency with cancellation and deadlines.** *Applied 2026-10-05: D-081.* `parallel within 2s on error cancel do … done;` — policies: `cancel` (first error cancels siblings), `collect` (wait for all, raise an `AggregateError` with every failure and keep successful outputs). `$error.errors` lists them in index order: deterministic.

**answer** ok, good.

**RMT-R02 Streams as a first-class type unifying generators and channels.** `Stream(:T)` with `for x in s`, produced by a generator, a channel, a file reader, a database cursor, or a network connection. Back-pressure built in. ETL then reads: `for row in csv.read("in.csv") do … done;` regardless of source.

**answer** ok, sound good. Details must be elaborated.

**RMT-R03 One scheduler for local and remote waits.** Implement the worker pool and the "give the core away" rule once in the VM, on top of an event loop (io_uring/IOCP/kqueue via Zig `std.Io`), so the same scheduler later serves sockets.

**answer** A scheduler was in back on my mint for a while now. Of course wee need a scheduler. One local one remote.

**RMT-R04 Dataflow operators in the library.** `map`, `filter`, `batch(n)`, `partition(k)`, `merge`, `window(time)` on `Stream`, with a `parallel(n)` stage. Many ETL scripts then need no explicit `parallel` block at all.

**answer** ok, good. We need to define data streams and data flow operators. I already say an aspect can run parallel work but I do not know if these will be other aspects. Probably yes because now we can paralellize processes only and one aspect has a single process.

**RMT-R05 Bring a minimal generator into 0.1, keep parallel for 0.3.** Generators are single-threaded and give lazy file and query reading, which 0.1 clients need. Parallel aspects wait for the bytecode VM.

**answer** no problem, we define generator with methods or after methods.
