# F-VM-05 Region memory

Arena per aspect call, job and request; long-lived heap for modules and channels.

*Done:* the values are reference counted and freed at the safe points of their region (statement, pass of a loop, `done`); a tracing collector frees cycles; scratch memory per statement; a started aspect has a heap of its own that it frees while it runs and that goes whole at the end of the task; a channel keeps its messages in a heap of its own.

## Built

- A heap for each started aspect: a task that makes garbage in a loop peaks at 7 MB (1.1 GB before); the inputs, the outputs and the messages are copied between heaps (tests d51, d52, d53); `EVE_GC_VERIFY=1` is clean on the tests of levels 4 and 5.

## Missing

- The tasks of a job and the generators share the heap of their creator, and nothing is freed while one lives (TD-95).
