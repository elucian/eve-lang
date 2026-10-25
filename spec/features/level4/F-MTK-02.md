# F-MTK-02 Worker pool and scheduler

`$cores`, M:N, a waiting aspect gives its core away.

*Partial:* stage A, one core with a baton (task.zig): a waiting task gives the core away; `$cores` and `$max_parallel` wait for stage B.

## Built

- Stage A (one baton, deterministic), `$cores` (the hardware cores, at most 16), `$max_parallel` (the tasks of a group that run at a time; a start beyond it waits), the rule that only the primary aspect fans out (tests d25, d26, d31, d40, d48, d49). Every test of level 4 gives the same result in 20 runs.

## Missing

- Stage B: the tasks on several cores at once. It needs a heap and an interpreter that several threads can use; today they are shared by the tasks and used by one at a time.
