# Design: a heap per task and the scheduler on several cores (S15.41 stage B)

Status: **built** 2026-10-26 (section 9 says what differs from this draft); the author answered Q1 to Q3 (section 8). Features: F-MTK-02, F-VM-05. Debt: TD-94. Decisions behind it: D-144 (stages A to C), D-151 (reference counts and regions), D-206 (only the primary aspect fans out). Spec rules it must keep: `spec/semantics/multitasking.md#data-rules` (inputs by value, one owner for each output, channels the only shared objects) and `#determinism`. Nothing here changes the language; it changes how the machine keeps those rules.

## 1. Where we are

- One `Heap` (`code/evecm/src/heap.zig`) serves the whole run. Its counts, `objs` table, pools, regions and `seq` are plain integers, so only one thread may touch it. The baton of `task.zig` guarantees that: only one task runs at a time.
- While any task lives, `Heap.pause()` stops every free; the zero counts wait in `deferred` until `done`. That is why `p4a_parallel_sum` peaks at 39 MB (TD-94 says 47 MB: measure again before the work) and why the peak grows with the rounds of a group.
- A task already has its own `Interp` (`newChild` in `interp/parallel.zig`): its own scratch memory, its own scope stack and its own output buffer. It shares `h`, `global`, `modules`, `aspects` and the root's tables.
- The border rules are already the ones a per-task heap needs: inputs are deep copies (`ownInputs`, `Interp.clone`), a channel `send` copies (`clone` in `send`), an output is owned by one task (`ownOutputs`). The only breach is the shared heap itself: a copy is made in the same heap as the original.

## 2. The model

**One `Heap` for each task that can run in parallel with its creator.** The root task keeps the heap of the run. A task started by `start` or `spawn` gets a new `Heap` over the same allocator, made by `newChild`. A generator body is a coroutine of its caller and never runs at the same time, so it keeps the heap of the caller (`GenState` gets no heap of its own).

**Invariant** (`@invariant`): an unpinned object is referenced only by objects of its own heap and by the interpreter of its own task. Pinned objects (literals, constants, module scopes, the global scope, interned strings) are read only after the link step and may be referenced from every heap.

What follows from the invariant:

- **Pinned objects never change a count.** `retain`, `release` and `drop` return at once on a pinned object. Today they count it, which is a data race as soon as two tasks read the same constant list. The flag is written before the first task starts and only read afterwards.
- **Per-heap everything else.** Counts, `objs`, pools, regions, zero count tables, the tracing collector and its roots (the scope stack of the task) belong to the heap. A task frees at its own safe points while it runs. `pause`, `resume_` and `deferred` disappear; so does the rule "nothing is freed while tasks run".
- **A task heap ends in one step.** When the task has ended and its parent has taken what it needs (section 3), the parent runs the destructors (`finalizeAll`) and `deinit`s the heap. No reference counting is done for the garbage left in it; that is the arena of F-VM-05.
- **Debug check.** `Obj` gets an `owner: u16` (it fits in the padding after `idx`; the header does not grow). In Debug and with `EVE_GC_VERIFY=1`, every store of a reference into a list, map, object, scope or variable asserts `owner == this heap or pinned`. This finds a breach at the store, not at a crash.

## 3. The borders

| Border | Today | In stage B |
|---|---|---|
| Input of `start`/`spawn` | deep copy, same heap | deep copy made with the child's heap as target, on the parent thread before the thread starts (the spawn gives the happens-before) |
| Output (`@x`) at `done` | the parent's variable is written directly by the child | the child stores into its own copy; at `join` the parent thread deep-copies the final value into its heap, then drops the child heap |
| Return value of a `spawn` read by `await` | same heap | as an output: copied at `await` |
| Channel message | `clone` in `send`, the copy is held by the channel | the sender builds the message in a small **message heap** owned by the channel slot; the receiver deep-copies it into its own heap and the message heap is dropped. Two copies; the first can later become a move (below) |
| Module and global data | shared | read only and pinned after the link; managed module variables are `Atomic` cells outside any heap |
| Text output | per-task buffer | unchanged; `log_err`/`log_wrn` write under one mutex |

A value that is a scalar or a pinned string crosses without a copy.

**Option for later, only if a benchmark asks (D-196): adopt instead of copy.** At `join` the child heap runs a last trace whose roots are only the outputs, then the parent *adopts* the survivors (its `objs` table appends them and relabels `idx`, `seq` and `owner`: a pass without allocation). It turns the copy of a big output (a 200,000-element list) into a pass over the live objects. The first version copies, because it needs no new heap operation and it is easy to verify with `EVE_GC_VERIFY=1`.

## 4. The scheduler

- **B1, a heap per task with the baton unchanged.** Everything in sections 2 and 3, still one core. The tests of level 4 must give the same results and the same order as today. This isolates the memory work from the thread work, and it is where a breach of the invariant shows, deterministically.
- **B2, `$cores` batons.** `Sched.current` becomes a count of running tasks, at most `$cores`; a ready queue in the order of creation replaces `pick`. A blocked task parks on the condition of the scheduler; a task that becomes ready (a message, a close, a task ended) is queued and wakes a runner if one is free. `progress` becomes atomic. `$cores = 1` must give exactly the stage A interleaving, and it is the mode of the debugger and of `--repeat` baselines.
- **Channels** get a mutex and two conditions each, and the buffer holds message heaps. `ch.count` reads under the lock.
- **Deadlock** is decided under the scheduler mutex when the last runner is about to park: every unfinished task waits on a channel or a join, no timer, no `io` wait pending. This is the rule of today, evaluated at the moment the running count falls to zero. Time-outs and cancel (D-140, D-141) keep their messages and their order in `$error.errors` (order of `start`).
- **Determinism** (spec `#determinism`) is kept by the rules that are already there: the output of a group is written in the order of `start`, the errors are listed in that order, one sender keeps its order. A program that depends on anything else is not deterministic by spec, on any number of cores.
- **`io` waits** (`netlib.zig` `offload`) already use a helper thread and `ioDone`; with several runners they no longer stop the others.

## 5. Shared state to audit before B2

Each item is either made read only after the link, put behind a mutex, or made per task. To check one by one (the list is from reading `Interp`, not from a full audit):

1. The allocator `gpa`: it must be safe from several threads in every build mode.
2. `Heap.statics` (interned literals): filled at load time; any later call of `static` needs a mutex or a move to load time.
3. `Interp.overloads`, `object_class`, `data_slot` (the database state of the run, connections), the profiler, the stream and job tables: they live in the root `Interp`. Decide for each: read only, per task, or locked. A database connection used from two tasks needs its own rule (per task connection, or a lock): it is the largest open item.
4. The module table: read only after the link (spec note, stage B).
5. `Atomic(:T)`: cells with `std.atomic.Value`, payload limited to scalars in stage B (open question Q1).
6. The debugger and `--step` hooks: they set `$cores = 1`.
7. The bytecode engine has no scheduler code; check how a run on `--engine bytecode` reaches `parallel.zig` (the benchmarks run on it) and that the child `Interp` it makes gets its own heap too.
8. Destructors (CLS-14): `finalizeAll` of a task heap runs on the thread that drops the heap, which must not run a destructor that touches another heap.

## 6. Measures and gate

Before the work (D-196): `EVE_MEMSTATS=1` on `p4a_parallel_sum` (peak bytes and objects), time on 1 core, `bmark.py --check` baseline on ReleaseSafe.

- **Memory:** the peak of `p4a_parallel_sum` must not grow with the number of rounds (5 today; test with 20), and must fall under the 39 MB of today. A new test with a task that makes garbage in a loop checks `peak_live` against a bound.
- **Speed:** `bmark.py --check` (no benchmark more than 10% slower with `$cores = 1`); `p4a_parallel_sum` on 4 cores faster than on 1, the ratio recorded in the feature page.
- **Gate:** `runtest.py --repeat 20` of every test of level 4 on `$cores = 1` and on `$cores = 8`; `EVE_GC_VERIFY=1` on levels 4 and 5; a stress of the channel tests at `--repeat 200`. Try a thread sanitizer build in Debug (`-fsanitize-thread`) if the Zig 0.17 toolchain on Windows supports it; if not, say so in `tech-debt.md`.

## 7. Steps, tests first (D-194)

1. **B0 tests (failing first):** (a) a task loop that makes garbage keeps `peak_live` flat; (b) 4 tasks add 100,000 each to an `Atomic(:Integer)`: exact total at every run (the missing `Atomic` tests of S15.40 are the same); (c) a nested list/object through a channel arrives equal and independent (changing it in the receiver does not change the sender's); (d) an output list of a task is equal and independent after `done`; (e) deadlock and time-out reports on `$cores = 8`; (f) `$cores = 1` and `$cores = 8` print the same.
2. **B1:** `owner` field and the Debug assertion; pinned objects skip counting; `newChild` makes a heap; borders of section 3; remove `pause`/`resume_`/`deferred`. Gate with the baton.
3. **B2:** the scheduler of section 4 and the channel locks.
4. **B3:** the audit of section 5 closed item by item; each fix with a test or a line in `tech-debt.md`.
5. **B4:** measures and gate of section 6; update `spec/features/level4/F-VM-05.md` and `F-MTK-02.md`, the implementation notes of `multitasking.md` (stage C paragraph), TD-94, `design/design-bytecode.md` (the line that leaves room for this).

## 8. Questions for the author

- **Q1. What may an `Atomic` hold in stage B?** `modules.md` names Logic, numbers, references and ordinals. A reference to an object would point into some heap and break the invariant. Proposal: scalars only in stage B (the reference case stays in the spec as not yet supported, with a compile error), because nothing in the tests needs it.
**answer** correct, we need only scallars to be atomic. 
- **Q2. Destructors on copies.** A copy of an object with a destructor (input, message, output) runs its own destructor, as an input copy does today. Keep that (each copy is a value, each ends once), or mark copies as non-finalizing? Proposal: keep.
**answer** Yes good proposal.
- **Q3. Database connections used by tasks.** One connection for the run guarded by a lock (simple, serial), or one per task (parallel, needs the driver to allow it, and SQLite and DuckDB differ)? Proposal: a lock first, per-task connections as a later step with its own measure.
**answer** one connection for the run is good.

## 9. As built (2026-10-26)

What differs from sections 1 to 7, and the measures.

- **Lanes, not only heaps.** `multitasking.md#tasks-in-a-job` says the tasks of a job share the core and the variables of their caller, so a `spawn` task and a generator do not get a heap: they join the **lane** of their creator (`task.Lane`), share its heap (`Heap.pause` while one lives, TD-95) and take turns with it. A started aspect or private process starts a new lane with a heap of its own. The permits (`$cores`) go to lanes.
- **Scheduler** (`code/evevm/src/task.zig`): one mutex and one condition; a parked thread sleeps until a permit is *granted* to it (`granted`), so `EVE_CORES=1` keeps the order of stage A. `bump` (a channel change) takes the lock only when a permit is free and a task waits on a channel; a `join` waits on `finishes`, not on `progress`; a task spins a few microseconds (`spinFor`) before it parks. Every wait reads the counter before it looks at the state it waits for, so no wake-up is lost.
- **Channels**: one heap for each channel (not for each message) and a spin lock; `send` copies into the channel heap, `receive` copies out and frees in the channel heap. A channel is pinned in the heap that made it.
- **Pinned objects**: the unit scope of an aspect that starts a private process, its constants and its functions are pinned (`shareUnit`); constants defined in a pinned scope are pinned deep (`Interp.define`); a copy shares only pinned objects of the root heap (`transfer.zig`). A function is copied with its closure (a snapshot, cycles kept by a memo), so a lambda can be an input (TD-99).
- **Modules** are loaded by the root task before the aspect that needs them starts (`startAspect`); the tables of the root interpreter (overloads, loaded modules, generators, streams, sockets, classes made on first use) are guarded by one spin lock (`Interp.lockShared`). The mark "this String is a Text" moved into the string header, so it crosses a border and the shared hash table is gone.
- **Atomic variables**: `Var.atomic`, set by `declare` from the type; read and changed under one spin lock (`value.atomic_lock`); a non-scalar value is an error at declaration (Q1; TD-97).
- **Database** (Q3): one connection for the run and one re-entrant lock (`host.enterDb`) taken at the calls from the interpreter (TD-96).
- **Tests** written first: d50 (atomic 4 x 50,000), d51 (channel copy), d52 (outputs copy), d53 (garbage in six tasks), d54 (four tasks on one connection). d49 and d28_test2 depended on the order of tasks that now run at the same time; they were rewritten to check what the spec promises (d49 counts the tasks inside a gauge; d28_test2 closes the channel in one group and sends in the next).
- **Measures** (ReleaseSafe, this machine, 12 cores): `p4a_parallel_sum` 165 to 80 ms; `p4c_groups` 167 to 120 ms; `p4b_channel` 80 ms before and 75 ms now (95 to 105 ms with `EVE_CORES=1`); a task that makes garbage in a loop (six tasks, 60,000 rounds) peaks at 6.6 MB, it was 1,094 MB; the peak of `p4a_parallel_sum` is the same 47.6 MB (it is the 200,000-element lists, not the tasks) and does not grow with the rounds.
- **Gate**: all 626 tests pass on both engines for levels 4 and 5 (`--both`); level 4 `--repeat 50` on 12 cores and `--repeat 30` on 2; the channel tests `--repeat 150`; `EVE_GC_VERIFY=1` on levels 4 and 5 with `--repeat 20`; `bctest.py` equal. No thread sanitizer on this toolchain (TD-98).

