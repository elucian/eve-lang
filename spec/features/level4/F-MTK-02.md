# F-MTK-02 Worker pool and scheduler

`$cores`, M:N, a waiting aspect gives its core away.

*Done:* stage B. Up to `$cores` tasks run at the same time; a waiting task gives its core to the next ready one; the tasks of a job and the generators of a task share the core of their creator.

## Built

- `$cores` (the hardware cores, at most 16; `EVE_CORES=n` sets it for a run, `1` gives the baton of stage A), `$max_parallel` (the tasks of a group that run at a time; a start beyond it waits), the rule that only the primary aspect fans out (tests d25, d26, d31, d40, d48, d49).
- Lanes and permits (`task.zig`): the tasks that share a heap take turns; the lanes run in parallel, one permit for each core, handed in the order of `start`.
- Channels with a lock and a heap of their own for the messages; `Atomic` variables exact under `let` on every core (tests d15, d50, d51); the database layer with one connection and one lock (test d54); `p4a_parallel_sum` 165 ms to 80 ms.
- Every test of level 4 gives the same result in 50 runs, on 1, 2 and all cores.

## Missing

- A thread sanitizer run (the toolchain has none on Windows, TD-98).
