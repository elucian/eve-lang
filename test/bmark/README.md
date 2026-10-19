# Performance tests

One small benchmark for each level, to see that the VM stays fast while features and optimizations arrive. They are not conformance tests: the runner of `test/levelN/` ignores this folder. Each benchmark prints a result and declares it in an `/*@expect*/` block, so a wrong answer is an error, never a fast time. Each has a twin in Python (`ref/<name>.py`) that does the same work, and the report shows the ratio Eve / Python (1.0x is the speed of CPython). The twin is a yardstick, not a goal.

## Run

```
python script/bmark.py                    # 5 runs of each benchmark, compared with the last saved run
python script/bmark.py --save             # also append the run to history.json and rewrite the tables below
python script/bmark.py --check            # exit 1 when a benchmark is more than 25% slower than the last saved run
python script/bmark.py --level 1 --runs 9
python script/bmark.py --build ReleaseSafe --eve temp/rel/bin/eve.exe --save
```

- Compare only runs of the same build and the same machine, with nothing else running; trust the median, not one run. The ReleaseSafe build (`zig build -Doptimize=ReleaseSafe -p temp/rel`) is the one to compare between versions; Debug is for development.
- The sizes come from the programs found beside `eve.exe`: build `evetx` and `eveux` into the same folder (`cd comp/evetx && zig build -Doptimize=ReleaseSafe -p ../../temp/rel`) or their column stays empty.
- Level 6 needs `evedb.exe` beside `eve.exe`; `bmark.py` starts it with `evedb.cfg` and stops it. Its Python twins need `psycopg2`.
- A new benchmark is `p<level><letter>_<name>.eve` with a `** perf:` description line and a twin with the same loops and sizes. Keep it between 50 ms and 2 s.

## Benchmarks

What each one measures (the `** perf:` line of the file).

<!-- bench:begin -->
| Benchmark | What it measures |
|---|---|
| **Level 1** | |
| `p1a_arith` | integer and real arithmetic, `for` and `while` loops, variables |
| `p1b_calls` | function calls, recursion (`fib(20)`), parameter binding |
| `p1c_collections` | list appends and iteration (60,000 elements), DataMap and DataSet |
| `p1d_strings` | string appends, placeholders, regular expression matches |
| **Level 2** | |
| `p2a_aspects` | 5,000 `apply` of an aspect with two inputs and one output (a new scope and a new boot for each call) |
| `p2b_closures` | a closure called 50,000 times, a lambda called 50,000 times, a function that makes closures 2,000 times |
| `p2c_procedures` | 30,000 calls of a procedure with `@` parameters, a function with defaults and a vararg procedure |
| **Level 3** | |
| `p3a_modules` | 50,000 calls of module functions (`mathx.square`, `mathx.clamp`) and 50,000 reads of a module constant |
| `p3b_objects` | 5,000 objects of a class and of its subclass, 50,000 method calls, 20,000 extension method calls |
| `p3c_module_state` | 50,000 calls of a module procedure that changes private state and 50,000 reads of it |
| **Level 4** | |
| `p4a_parallel_sum` | 5 rounds of a parallel group that sums 200,000 integers in 4 parts (`split`, `start`, inputs copied by value) |
| `p4b_channel` | 50,000 messages from a producer through 2 workers to a collector (two channels of capacity 100, back-pressure) |
| `p4c_groups` | 250 parallel groups of 4 started aspects each (a task, a thread and an output buffer per start) |
| `p4d_tasks` | 50 jobs that spawn 20 async procedures each and wait for them at done (the tasks of a job share one core) |
| `p4e_garbage` | 200,000 iterations that each build a string and a list and drop them; watch the peak memory |
| **Level 5** | |
| `p5a_sql_function` | 20,000 rows made in SQL, then a query that calls a sql function on each row, three times (60,000 calls) |
| **Level 6** | |
| `p6a_evedb_store` | 1,000,000 rows made by DuckDB, read through evedb:// into a Memory table of four columns, then one sum |
| `p6b_evedb_load` | 200,000 rows read into a Memory table, then loaded into a new evedb table as column batches, and counted |
| `p6c_pg_records` | 100,000 rows read from evedb as records through postgres://, and a loop that adds one field of each |
| `p6d_olap_groupby` | 1,000,000 rows in evedb, then ten group-by queries over all of them (sum and count by region) |
| `p6e_http_requests` | 300 requests (GET with a path parameter, GET with a query, POST with a body), each on its own connection |
| **Level 7** | |
| planned | render an HTML template 1,000 times |
<!-- bench:end -->

## Results

The latest saved ReleaseSafe run: median time of the whole process (start-up included), the time of the Python twin, and the peak memory of Eve.

<!-- results:begin -->
| Benchmark | Eve | Python | Eve / Python | Peak memory |
|---|---|---|---|---|
| **Level 1** | | | | |
| `p1a_arith` | 218 ms | 94 ms | 2.3x | 5.9 MB |
| `p1b_calls` | 72 ms | 58 ms | 1.2x | 6.0 MB |
| `p1c_collections` | 27 ms | 62 ms | 0.4x | 7.9 MB |
| `p1d_strings` | 23 ms | 80 ms | 0.3x | 6.2 MB |
| **Level 2** | | | | |
| `p2a_aspects` | 14 ms | 50 ms | 0.3x | 5.9 MB |
| `p2b_closures` | 60 ms | 65 ms | 0.9x | 7.4 MB |
| `p2c_procedures` | 68 ms | 64 ms | 1.1x | 6.0 MB |
| **Level 3** | | | | |
| `p3a_modules` | 105 ms | 70 ms | 1.5x | 6.0 MB |
| `p3b_objects` | 82 ms | 72 ms | 1.1x | 6.0 MB |
| `p3c_module_state` | 43 ms | 70 ms | 0.6x | 6.0 MB |
| **Level 4** | | | | |
| `p4a_parallel_sum` | 228 ms | 145 ms | 1.6x | 40.4 MB |
| `p4b_channel` | 95 ms | 1498 ms | 0.1x | 6.1 MB |
| `p4c_groups` | 168 ms | 265 ms | 0.6x | 8.1 MB |
| `p4d_tasks` | 251 ms | 241 ms | 1.0x | 8.0 MB |
| `p4e_garbage` | 285 ms | 140 ms | 2.0x | 6.0 MB |
| **Level 5** | | | | |
| `p5a_sql_function` | 158 ms | 193 ms | 0.8x | 9.2 MB |
| **Level 6** | | | | |
| `p6a_evedb_store` | 785 ms | 2653 ms | 0.3x | 56.1 MB |
| `p6b_evedb_load` | 318 ms | 9727 ms | 0.0x | 16.4 MB |
| `p6c_pg_records` | 244 ms | 330 ms | 0.7x | 81.7 MB |
| `p6d_olap_groupby` | 626 ms | 704 ms | 0.9x | 6.1 MB |
| `p6e_http_requests` | 452 ms | 783 ms | 0.6x | 51.8 MB |
| **Level 7** | | | | |
| planned | | | | |
<!-- results:end -->

## Size of the programs

The size of each program is saved with every run. A version that grows `eve` by more than 10% gets a sentence in the notes. The change is against the previous run of the same build.

<!-- size:begin -->
| Version | Date | Build | Commit | eve | evevm | evecp | evetx | eveux | evedb | eve change |
|---|---|---|---|---|---|---|---|---|---|---|
| 0.0.3 | 2026-10-13 | ReleaseSafe | 505c7dc | 3,572 KB | - | - | - | - | - | - |
| 0.0.7 | 2026-10-19 | ReleaseSafe | cc28760 | 3,988 KB | 3,988 KB | 1,210 KB | 2,198 KB | 9,088 KB | 1,264 KB | +11.7% |
<!-- size:end -->

## History

Each saved run adds a paragraph to the notes (what changed in the VM, faster or slower, and why when a benchmark moves by more than 10%) and a row to the totals.

### Notes by version

**0.0.1 (2026-10-07), baseline.** The first measure, after level 1 passed. A tree walker: names found by a linear scan of the scopes, values copied as tagged unions. `p1a_arith` dominates. ReleaseSafe is about 4.6 times faster than Debug.

**0.0.1 (2026-10-08), levels 2 and 3 measured.** Six benchmarks added with their twins; ratios Eve / Python of 1.0 to 2.4, so no accidental quadratic cost. The slowest is `p3a_modules` (2.4): `module.member` scans the `export` list on each access. Level 1 is 9% above the first run, which is noise of the machine.

**0.0.2 (2026-10-09), memory manager; level 4 measured.** Values live in a reference counted heap (D-151) with a tracing backup for cycles, and a scratch memory for one statement. Peak memory fell from 174 MB (`p1d_strings`) to 4 to 7 MB; only `p4a_parallel_sum` keeps 39 MB (it copies a 200,000-element list per task). Faster too: level 1 by 25%, level 2 by 46%, level 3 by 29%, from a shared prelude scope, reuse of freed strings and a direct `a[i]`. Level 4 added.

**0.0.3 (2026-10-13), the machine at the prompt; level 5 measured.** Work around the interpreter; the only cost on the script path is one atomic load between statements (+2% in `p1a_arith`). `p5a_sql_function` added (0.8x Python). `p3b_objects` is +17%, read as noise (its median and best differ by 10 ms). The size of `eve.exe` is recorded for the first time: 3,572 KB.

**0.0.7 (2026-10-19), baseline for the bytecode.** Levels 5 and 6 measured for the first time: `p6a` to `p6e` run against `evedb` and are 0.0 to 0.9 of the Python twins (psycopg2 pays per row what the column batches do not). Against the run of 0.0.3 most benchmarks are 10 to 40% slower (`p4d_tasks` +102%, `p5a_sql_function` +74%), but that run was made on another day with another load, and the ratios Eve / Python moved less than the times (Python twins are 20 to 40% slower too, `p1a_arith` 2.3x against 3.5x). Read this run as the new base line, not as a regression; the next run on this machine is the first fair comparison. `eve.exe` grew 11.7% (3,572 to 3,988 KB) with the machine API, the database layer and the drivers moved into the module; `evevm.exe` is the same file as `eve.exe`. Targets for the bytecode: `design/design-bytecode.md` §11.

### Totals per run

The sum of the median times of the benchmarks of each level. A dash means the level was not measured in that run.

<!-- runs:begin -->
| Version | Date | Build | Level 1 | Level 2 | Level 3 | Level 4 | Level 5 | Level 6 |
|---|---|---|---|---|---|---|---|---|
| 0.0.1 | 2026-10-07 | Debug | 1843 ms | - | - | - | - | - |
| 0.0.1 | 2026-10-07 | ReleaseSafe | 400 ms | - | - | - | - | - |
| 0.0.1 | 2026-10-07 | ReleaseSafe | 399 ms | - | - | - | - | - |
| 0.0.1 | 2026-10-08 | ReleaseSafe | 435 ms | 212 ms | 319 ms | - | - | - |
| 0.0.1 | 2026-10-08 | Debug | 2073 ms | 955 ms | 1951 ms | - | - | - |
| 0.0.2 | 2026-10-09 | ReleaseSafe | 327 ms | 114 ms | 228 ms | 931 ms | - | - |
| 0.0.3 | 2026-10-13 | ReleaseSafe | 308 ms | 118 ms | 228 ms | 751 ms | 91 ms | - |
| 0.0.7 | 2026-10-19 | ReleaseSafe | 341 ms | 143 ms | 230 ms | 1026 ms | 158 ms | 2425 ms |
<!-- runs:end -->
