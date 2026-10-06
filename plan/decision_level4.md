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

## Open questions

- Does a parallel group accept a stream as input and split it among its aspects by itself (`parallel for batch in rows do start load(batch); done;`), or is the split always written by hand?

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

## Q-023 How is an aspect marked as thread safe or not? (answered: D-090)
The compiler checks every aspect at `start` (D-089). Do we also mark the aspect in its own header, so that the error is reported where the aspect is written? Alternatives:
(a) **No mark, inference only.** The error appears at `start`, with the chain of calls. No new word. Risk: a change in a library module makes an aspect unsafe far from where it is written.
(b) **Default checked, opt-out keyword:** `aspect x is` must be thread safe (checked at the declaration); `serial aspect y is` may use any function and can only be applied, never started. Safe by default, one word for the exception; "serial mode" is already the name of `apply`.
(c) **Default serial, opt-in keyword:** `parallel aspect x is` is checked at the declaration and may be started; plain `aspect y is` can only be applied. Nothing is parallel by accident; one more word for every parallel aspect.
(d) **Comment annotation:** `** @safe` above the aspect, like `** @param` above `main`. No new keyword, but a comment would change the meaning of the program, which comments do not do elsewhere.
(e) **Attribute in the header:** `aspect x is thread_safe` or `aspect x is serial`. Keeps the word order of the other headers; a long line when combined with other clauses.
Recommendation: (a) plus the opt-in check of (c): inference by default, and `parallel aspect x is` makes the compiler verify the aspect where it is written. Beginners write nothing; library authors get the early error.
**Answer:**
Alternative option: I like double down on things because this is how humans learn. With pain! For a greater good. So we mark an aspect woth keywords: We have two kind of aspects: exclusive / concurrent so we create two new keywords: exclusive/ concurent instead of serial/parallel. User declare he wants an exclusive aspect or a concurent aspect, then the compiler will signal errors if situations make the aspect non concurent.
