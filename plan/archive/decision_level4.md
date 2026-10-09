# Archive of decision_level4.md: settled entries, full text

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
Author decisions, answering the open questions of `version_map.md`. (1) **Generics and traits** (F-LNG-11, D-039) move from Version 0.2 to **Level 4, Version 0.3**. (2) The **bytecode** compiler and VM (F-VM-04), the portable **`.evb` file** (F-VM-07) and the **embedding API with a C ABI** (F-VM-08) move to a new **Version 0.7**, "Bytecode and embedding": all levels pass on the bytecode VM, an `.evb` file runs on another machine, a C program embeds the VM through the C ABI. (3) **One file**: `plan/features_inventory.md` is merged into `plan/version_map.md`, which now holds the levels, the versions and every feature with its status, grouped by version (108 features); the old file is removed and its links point to the new one. Consequences, open in the file: the generators (F-LNG-12, Version 0.4) need a method that can stop and continue and the bytecode VM is now later; and F-WEB-02 (Version 0.6) runs `.evb` code in the browser. Level 4 now covers parallel processing, streams, generics and traits.
