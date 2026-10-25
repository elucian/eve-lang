# F-VM-05 Region memory

Arena per aspect call, job and request; long-lived heap for modules and channels.

*Partial:* the values are reference counted and freed at the safe points of their region (statement, pass of a loop, `done`), a tracing collector frees cycles at `done`, scratch memory per statement; nothing is freed while tasks run; benchmarks peak at 4.4 to 6.6 MB (`p4a_parallel_sum` 39 MB). Open: an arena per task.

## Missing

- An arena per task, so memory is freed while tasks run (`p4a_parallel_sum` peaks at 39 MB). It comes with stage B, as both need a heap that each task owns.
- Built: `EVE_GC_VERIFY=1` is clean on the tests of levels 4 and 5.
