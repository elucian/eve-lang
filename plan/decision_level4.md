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
