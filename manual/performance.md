# Performance

How fast `eve` runs, measured with the ReleaseSafe build on one machine. Compare only runs of the same machine.

## Last run

The total time of the benchmarks of each level of the language, against their twins in Python.

<!-- GEN:summary -->
Run of 2026-10-19 17:49, version 0.0.7, `eve.exe` 4.0 MB.

| Benchmarks | Eve | Python | Eve / Python |
|---|---|---|---|
| Level 1 | 138 ms | 202 ms | 0.7x |
| Level 2 | 91 ms | 112 ms | 0.8x |
| Level 3 | 141 ms | 128 ms | 1.1x |
| Level 4 | 550 ms | 697 ms | 0.8x |
| Level 5 | 80 ms | 136 ms | 0.6x |
| Level 6 | 2297 ms | 11313 ms | 0.2x |
<!-- /GEN:summary -->

## Benchmarks

A benchmark is a small Eve program that does one kind of work many times: arithmetic and loops, function calls, collections, strings, classes, parallel work, database reads and writes, the machine and the network. The levels follow the versions of Eve, as the tests do, so each version adds the benchmarks of its own features. Every benchmark has a **twin written in Python** that does the same work, the reference for the comparison.

<!-- GEN:benchmarks -->
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
| `p6a_evedb_store` | 6 | 1,000,000 rows made by DuckDB, read through evedb:// into a Memory table of four columns, then one sum |
| `p6b_evedb_load` | 6 | 200,000 rows read into a Memory table, then loaded into a new evedb table as column batches, and counted |
| `p6c_pg_records` | 6 | 100,000 rows read from evedb as records through postgres://, and a loop that adds one field of each |
| `p6d_olap_groupby` | 6 | 1,000,000 rows in evedb, then ten group-by queries over all of them (sum and count by region) |
| `p6e_http_requests` | 6 | 300 requests (GET with a path parameter, GET with a query, POST with a body), each on its own connection |
<!-- /GEN:benchmarks -->

## Benchmark results

The median time of several runs of each benchmark and of its Python twin, and the peak memory of `eve`. **Eve / Python** below 1 means Eve is faster.

<!-- GEN:results -->
| Benchmark | Eve | Python | Eve / Python | Peak memory |
|---|---|---|---|---|
| `p1a_arith` | 64 ms | 66 ms | 1.0x | 5.9 MB |
| `p1b_calls` | 41 ms | 47 ms | 0.9x | 6.0 MB |
| `p1c_collections` | 19 ms | 38 ms | 0.5x | 8.0 MB |
| `p1d_strings` | 16 ms | 51 ms | 0.3x | 6.3 MB |
| `p2a_aspects` | 11 ms | 31 ms | 0.4x | 5.9 MB |
| `p2b_closures` | 36 ms | 40 ms | 0.9x | 7.4 MB |
| `p2c_procedures` | 43 ms | 42 ms | 1.0x | 6.0 MB |
| `p3a_modules` | 58 ms | 43 ms | 1.4x | 6.0 MB |
| `p3b_objects` | 54 ms | 44 ms | 1.2x | 6.1 MB |
| `p3c_module_state` | 29 ms | 42 ms | 0.7x | 6.0 MB |
| `p4a_parallel_sum` | 111 ms | 84 ms | 1.3x | 40.3 MB |
| `p4b_channel` | 61 ms | 230 ms | 0.3x | 6.1 MB |
| `p4c_groups` | 134 ms | 147 ms | 0.9x | 8.2 MB |
| `p4d_tasks` | 131 ms | 143 ms | 0.9x | 8.0 MB |
| `p4e_garbage` | 113 ms | 93 ms | 1.2x | 6.0 MB |
| `p5a_sql_function` | 80 ms | 136 ms | 0.6x | 9.2 MB |
| `p6a_evedb_store` | 812 ms | 2124 ms | 0.4x | 56.2 MB |
| `p6b_evedb_load` | 345 ms | 7795 ms | 0.0x | 16.5 MB |
| `p6c_pg_records` | 190 ms | 329 ms | 0.6x | 81.7 MB |
| `p6d_olap_groupby` | 666 ms | 624 ms | 1.1x | 6.1 MB |
| `p6e_http_requests` | 283 ms | 441 ms | 0.6x | 51.8 MB |
<!-- /GEN:results -->

## By version

<!-- GEN:history -->
The last saved run of each version; the set of benchmarks grows with the versions.

| Version | Date | Benchmarks | Eve total | Python total | Eve / Python |
|---|---|---|---|---|---|
| 0.0.7 | 2026-10-19 | 21 | 3297 ms | 12590 ms | 0.3x |
<!-- /GEN:history -->
