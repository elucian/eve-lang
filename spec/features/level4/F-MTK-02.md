# F-MTK-02 Worker pool and scheduler

`$cores`, M:N, a waiting aspect gives its core away.

*Partial:* stage A, one core with a baton (task.zig): a waiting task gives the core away; `$cores` and `$max_parallel` wait for stage B.
