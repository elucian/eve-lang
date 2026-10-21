# F-MTK-02 Worker pool and scheduler

`$cores`, M:N, a waiting aspect gives its core away.

*Partial:* stage A, one core with a baton (task.zig): a waiting task gives the core away; `$cores` and `$max_parallel` wait for stage B.

## Missing

- Stage B: several cores, `$cores`, `$max_parallel` (`$cores` is undefined today).
- `--repeat 20` of every level 4 test.
