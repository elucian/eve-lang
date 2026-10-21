# Decisions, level 4: parallel processing and streams (version 0.3)

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. Ids are shared by all the decision files ([level 1](level1.md), [2](level2.md), [3](level3.md), 4, [5](level5.md), [6](level6.md), [7](level7.md)); the list of levels is in [decision_level3.md](level3.md) and spec/features.

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
- D-138 Answers to the feature map; one file for versions and features

- Q-023 How is an aspect marked as thread safe or not? (answered: D-090)
- Q-035 Asynchronous subprograms: open points
- D-089 Thread safety is decided by the compiler; `!` means stochastic; generators; atomic and mutex
- D-090 `exclusive aspect` and `concurrent aspect`
- D-138 Answers to the feature map; one file for versions and features
- D-140 Parallel groups: syntax, rules, output and errors
- D-141 Channels: rules completed
- D-142 Streams and the split of data
- D-143 Asynchronous tasks in a job
- D-144 Determinism, durations and the stages of the VM
- D-145 Traits, abstract classes and generic classes in Version 0.3
- D-147 No self-calling lambdas; the second parameter list of a subprogram is for types
- Q-041 Generic functions and procedures: open points (answered: D-148)
- D-148 Generic functions, procedures and processes: form, inference, no generic lambdas
- D-151 Memory of the VM: reference counting first, a tracing collector as backup, garbage collected at `done`

## Q-041 Generic functions and procedures: open points (2026-10-09)

(a) Is the form of D-147 right: `function name(:T, :U)(parameters) => (@result: T)`, with constraints `(:T <: Comparable)` as for classes? 

**Answer:** The form is right.

(b) Must the type list always be written at the call, `largest(:Integer)(xs)`, or may it be inferred from the arguments, `largest(xs)`? (Generic classes: always written in Version 0.3, D-145.) 

**Answer:** The type list uses type inference; it is not mandatory at the call.

(c) May a method of a class have its own type list, besides the one of a generic class? May a lambda have one? 

**Answer:** A lambda function does not accept a type list. Instead we can use an overloaded function signature; the formula is most probably different for different types anyhow. Methods can take a type list (2026-10-09).

(d) Does a process of an aspect accept a type list? 

**Answer:** A process can take a type list.

## D-148 Generic functions, procedures and processes: form, inference, no generic lambdas (2026-10-09)
Author answers to Q-041. Version 0.4, feature F-LNG-20.
- **Form.** A function, a procedure, a method or a process may have a first parameter list of types before its value parameters: `function largest(:T <: Comparable)(items: ()T) => (@result: T) is … return;`. Constraints are written as for generic classes (D-145).
- **Inference.** The type list at the call is optional: `largest(numbers)` infers `T` from the arguments; `largest(:Integer)(numbers)` writes it. When the type can not be inferred, the type list is required (compile error otherwise). This differs from generic classes, where the type argument is always written in Version 0.3 (D-145).
- **Processes.** A process takes a type list: in the aspect `sorter`, `process main(:T <: Comparable)(data: ()T) is … return;`, applied as `apply sorter(rows);` or `apply sorter(:Row)(rows);`. The `main` of a driver has no type list: nothing calls it.
- **Methods.** A method may have its own type list, besides the one of its generic class: `method convert(:U)(@self) => (@result: Box(:U))`.
- **No generic lambdas.** A lambda has no type list. Work that differs by type is written as **overloaded functions**: several functions with the same name and different parameter types, since the formula is most probably different for each type anyway. Overloading and the signature: D-149.

## Roundup of level 4 (2026-10-08): stage A implemented on the VM
**Implemented.** Level 4 passes 42 of 42 (d01 to d35 with variations), 100 runs in a row with `runtest.py --repeat 100`; all levels pass (235 tests). Stage A of D-144: `code/evevm/src/task.zig` is the scheduler (one thread per task, one baton); `interp.zig` has the groups, `start`, the channels, `spawn`/`await` in a job, `wait`, the time-outs and the ParallelError with its items; `project.zig` checks `start` (concurrent aspects only, one level, at most 2 starts in an aspect, one owner per output); `check.zig` checks `spawn`, `await`, async calls, traits and abstract classes.

**Fixes found on the way.** (1) The compile errors of the VM go to the standard output, so the compile-error tests check `contains`, not `stderr`. (2) A list of lists was indexed like a matrix; `isMatrix` now asks for an array of arrays, as `types.md` says (D-064). (3) A parameter named `jobs` was hidden by the map of the job states; the parameter wins. (4) `let r := a if c else b;` reads the `if` as the suffix of the statement; d24 writes the conditional in parentheses.

**Open for Version 0.3:** stage B (`$cores` threads, `$max_parallel`), the check of a type constraint `(:T <: Comparable)`, region memory (F-VM-05), the benchmark `p4a_parallel_sum`.

## D-151 Memory of the VM: reference counting first, a tracing collector as backup, garbage collected at `done` (2026-10-09)
Author decision (2026-10-09): "use reference counting as much as possible and the garbage collector only as backup; usually garbage is collected at `done`". Implemented in the reference VM (`code/evevm/src/heap.zig`, `scratch.zig`, `interp.zig`); it completes stage C of D-144 for one core. Not a rule of the language: a program cannot see when memory is freed.
- **Reference counting.** Every value that needs memory (string, list, map, object, function, range, channel) counts its holders: variables, elements, entries, fields, closures. A value whose count falls to zero is freed at the next **safe point** of its **region**, not at once, because the interpreter may still hold it for a moment while it computes an expression. A region is a block, a loop or a process; its safe points are the end of each statement, the end of each pass of a loop, and `done`. Variables and scopes are freed when their call or block ends, unless a closure captured them.
- **Tracing collector as backup.** Reference counting cannot free a cycle (a function that closes over the scope that holds it). The tracing collector marks what the scopes reach and frees the rest of the region; it runs at the `done` of a job, of a parallel group and of a process, and when many objects were made since its last run.
- **Tasks.** While the tasks of a group or a job run (stage A, one heap), nothing is freed; the zero counts wait in a list and are freed at `done`. An arena per task is a later step (F-VM-05).
- **Scratch memory.** Buffers that live during one statement (the text being printed, the cells of an index, the arguments of a call) are taken from a scratch memory released at the end of the statement.
- **Checks.** `EVE_GC_VERIFY=1` checks every free of the reference count against a trace (a value still reachable means a holder forgot to count it); the whole suite passes with it on the Debug build. `EVE_MEMSTATS=1` prints what the heap made, freed and kept. `bmark.py` reports the peak memory: every benchmark peaks between 4.4 and 6.6 MB (was up to 174 MB), `p4a_parallel_sum` 39 MB (was 130 MB); the level totals are 25 to 46% faster than the last saved run (test/bmark/README.md, version 0.0.2).
