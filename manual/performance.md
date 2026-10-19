# Performance

How fast `eve` runs, measured with the ReleaseSafe build on one machine. Compare only runs of the same machine.

## Last run

The total time of the benchmarks of each level of the language, against their twins in Python.

<!-- GEN:summary (script/genmanual.py) -->
Run of 2026-10-13 11:44, version 0.0.3 (commit `505c7dc`), `eve.exe` 3.5 MB.

| Benchmarks | Eve | Python | Eve / Python |
|---|---|---|---|
| Level 1 | 308 ms | 165 ms | 1.9x |
| Level 2 | 118 ms | 101 ms | 1.2x |
| Level 3 | 228 ms | 117 ms | 1.9x |
| Level 4 | 751 ms | 618 ms | 1.2x |
| Level 5 | 91 ms | 112 ms | 0.8x |
<!-- /GEN:summary -->

## Benchmarks

A benchmark is a small Eve program that does one kind of work many times: arithmetic and loops, function calls, collections, strings, classes, parallel work, database reads and writes, the machine and the network. The levels follow the versions of Eve, as the tests do, so each version adds the benchmarks of its own features. Every benchmark has a **twin written in Python** that does the same work, the reference for the comparison.

<!-- GEN:benchmarks (script/genmanual.py) -->
| Benchmark | Level | What it measures |
|---|---|---|
| `p1a_arith` | 1 | integer and real arithmetic, `for` and `while` loops, variables |
| `p1b_calls` | 1 | function calls, recursion (`fib(20)`), parameter binding |
| `p1c_collections` | 1 | list appends and iteration (60,000 elements), DataMap and DataSet |
| `p1d_strings` | 1 | string appends, placeholders, regular expression matches |
| `p2a_aspects` | 2 | 5,000 `apply` of an aspect with two inputs and one output (a new scope and a new boot for each call) |
| `p2b_closures` | 2 | a closure called 50,000 times, a lambda called 50,000 times, a function that makes closures 2,000 times |
| `p2c_procedures` | 2 | 30,000 calls of a procedure with `@` parameters, a function with defaults and a vararg procedure |
| `p3a_modules` | 3 | 50,000 calls of module functions (`mathx.square`, `mathx.clamp`) and 50,000 reads of a module constant |
| `p3b_objects` | 3 | 5,000 objects of a class and of its subclass, 50,000 method calls, 20,000 extension method calls |
| `p3c_module_state` | 3 | 50,000 calls of a module procedure that changes private state and 50,000 reads of it |
| `p4a_parallel_sum` | 4 | 5 rounds of a parallel group that sums 200,000 integers in 4 parts (`split`, `start`, inputs copied by value) |
| `p4b_channel` | 4 | 50,000 messages from a producer through 2 workers to a collector (two channels of capacity 100, back-pressure) |
| `p4c_groups` | 4 | 250 parallel groups of 4 started aspects each (a task, a thread and an output buffer per start) |
| `p4d_tasks` | 4 | 50 jobs that spawn 20 async procedures each and wait for them at done (the tasks of a job share one core) |
| `p4e_garbage` | 4 | 200,000 iterations that each build a string and a list and drop them; watch the peak memory |
| `p5a_sql_function` | 5 | 20,000 rows made in SQL, then a query that calls a sql function on each row, three times (60,000 calls) |
<!-- /GEN:benchmarks -->

## Benchmark results

The median time of several runs of each benchmark and of its Python twin, and the peak memory of `eve`. **Eve / Python** below 1 means Eve is faster.

<!-- GEN:results (script/genmanual.py) -->
| Benchmark | Eve | Python | Eve / Python | Peak memory |
|---|---|---|---|---|
| `p1a_arith` | 202 ms | 57 ms | 3.5x | 5.4 MB |
| `p1b_calls` | 65 ms | 35 ms | 1.9x | 5.4 MB |
| `p1c_collections` | 23 ms | 33 ms | 0.7x | 7.2 MB |
| `p1d_strings` | 18 ms | 41 ms | 0.4x | 5.7 MB |
| `p2a_aspects` | 11 ms | 27 ms | 0.4x | 5.4 MB |
| `p2b_closures` | 51 ms | 37 ms | 1.4x | 6.8 MB |
| `p2c_procedures` | 57 ms | 37 ms | 1.5x | 5.4 MB |
| `p3a_modules` | 102 ms | 41 ms | 2.5x | 5.5 MB |
| `p3b_objects` | 89 ms | 40 ms | 2.3x | 5.5 MB |
| `p3c_module_state` | 37 ms | 36 ms | 1.0x | 5.4 MB |
| `p4a_parallel_sum` | 235 ms | 80 ms | 2.9x | 39.5 MB |
| `p4b_channel` | 69 ms | 223 ms | 0.3x | 5.5 MB |
| `p4c_groups` | 130 ms | 122 ms | 1.1x | 7.6 MB |
| `p4d_tasks` | 124 ms | 109 ms | 1.1x | 7.4 MB |
| `p4e_garbage` | 192 ms | 85 ms | 2.3x | 5.4 MB |
| `p5a_sql_function` | 91 ms | 112 ms | 0.8x | 8.6 MB |
<!-- /GEN:results -->

## By version

<!-- GEN:history (script/genmanual.py) -->
The last saved run of each version; the set of benchmarks grows with the versions.

| Version | Date | Benchmarks | Eve total | Python total | Eve / Python |
|---|---|---|---|---|---|
| 0.0.1 | 2026-10-08 | 10 | 966 ms | 594 ms | 1.6x |
| 0.0.2 | 2026-10-09 | 15 | 1599 ms | 1309 ms | 1.2x |
| 0.0.3 | 2026-10-13 | 16 | 1496 ms | 1114 ms | 1.3x |
<!-- /GEN:history -->
