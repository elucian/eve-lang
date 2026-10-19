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
| `p1a_arith` | 70 ms | 80 ms | 0.9x | 5.9 MB |
| `p1b_calls` | 45 ms | 45 ms | 1.0x | 6.0 MB |
| `p1c_collections` | 17 ms | 42 ms | 0.4x | 8.0 MB |
| `p1d_strings` | 15 ms | 59 ms | 0.3x | 6.3 MB |
| **Level 2** | | | | |
| `p2a_aspects` | 10 ms | 37 ms | 0.3x | 5.9 MB |
| `p2b_closures` | 40 ms | 49 ms | 0.8x | 7.4 MB |
| `p2c_procedures` | 46 ms | 47 ms | 1.0x | 6.0 MB |
| **Level 3** | | | | |
| `p3a_modules` | 65 ms | 50 ms | 1.3x | 6.0 MB |
| `p3b_objects` | 58 ms | 53 ms | 1.1x | 6.1 MB |
| `p3c_module_state` | 31 ms | 48 ms | 0.7x | 6.0 MB |
| **Level 4** | | | | |
| `p4a_parallel_sum` | 120 ms | 97 ms | 1.2x | 40.4 MB |
| `p4b_channel` | 62 ms | 462 ms | 0.1x | 6.1 MB |
| `p4c_groups` | 177 ms | 124 ms | 1.4x | 8.1 MB |
| `p4d_tasks` | 176 ms | 153 ms | 1.1x | 8.0 MB |
| `p4e_garbage` | 144 ms | 103 ms | 1.4x | 6.0 MB |
| **Level 5** | | | | |
| `p5a_sql_function` | 106 ms | 168 ms | 0.6x | 9.2 MB |
| **Level 6** | | | | |
| `p6a_evedb_store` | 633 ms | 1768 ms | 0.4x | 56.2 MB |
| `p6b_evedb_load` | 273 ms | 7536 ms | 0.0x | 16.5 MB |
| `p6c_pg_records` | 174 ms | 268 ms | 0.7x | 81.7 MB |
| `p6d_olap_groupby` | 512 ms | 533 ms | 1.0x | 6.2 MB |
| `p6e_http_requests` | 328 ms | 451 ms | 0.7x | 51.8 MB |
| **Level 7** | | | | |
| planned | | | | |
<!-- results:end -->

## Size of the programs

The size of each program is saved with every run. A version that grows `eve` by more than 10% gets a sentence in the notes. The change is against the previous run of the same build.

<!-- size:begin -->
| Version | 0.0.7 | 0.0.7 | 0.0.7 |
|---|---|---|---|
| Date | 2026-10-19 | 2026-10-19 | 2026-10-19 |
| Build | ReleaseSafe | ReleaseSafe | ReleaseSafe |
| Commit | cc28760 | 810aae5 | 320a228 |
| eve | 3,988 KB | 4,002 KB | 4,000 KB |
| evevm | 3,988 KB | 4,002 KB | 4,000 KB |
| evecp | 1,210 KB | 1,210 KB | 1,210 KB |
| evetx | 2,198 KB | 2,198 KB | 2,198 KB |
| eveux | 9,088 KB | 9,088 KB | 9,088 KB |
| evedb | 1,264 KB | 1,264 KB | 1,264 KB |
| eve change | - | +0.4% | -0.0% |
<!-- size:end -->

## History

Each saved run adds a paragraph to the notes (what changed in the VM, faster or slower, and why when a benchmark moves by more than 10%) and a row to the totals.

### Notes by version

**0.0.7 (2026-10-19), baseline for the bytecode.** The first run of the ladder (design/design-bytecode.md), before any change. Levels 5 and 6 are measured for the first time: `p6a` to `p6e` run against `evedb` and are 0.0 to 0.9 of the Python twins (psycopg2 pays per row what the column batches do not). `eve.exe` is 3,988 KB; `evevm.exe` is the same file. Runs of earlier versions were removed on 2026-10-19: they were made on another load and did not cover levels 5 and 6.

**0.0.7 (2026-10-19), R0 and R1 of the bytecode ladder.** R0, the base line: `Value` is 24 bytes, `Node` 80 (104 after R1), `Var` 56, `Scope` 64, `Func` 40 (unit test `value sizes`). R1: the parser sets an `Op` on every binary and compound-assignment node and converts plain number literals once; `applyOp` does integer and real arithmetic and integer comparison without comparing the operator text. Measured against the commit before, same machine, alternating builds, 9 runs: `p1a_arith` 195 to 75 ms (3.0x to 1.1x Python), `p1b_calls` 62 to 45 ms, `p1c_collections` 22 to 18 ms, `p1d_strings` 15 to 14 ms. A first try of the net time-out (`set_timeout`) made `p6e_http_requests` 10 times slower, because a task with a time-out made the scheduler poll in 1 ms steps (about 15 ms on Windows); the scheduler now waits on its condition up to the timer, and `p6e` is 394 ms. `eve.exe` +0.4%. The absolute times of this row are lower than the first 0.0.7 row because the machine was less loaded; read the ratios Eve / Python.

**0.0.7 (2026-10-19), R3 and R4.** R3 (a cheaper statement prologue) was measured before it was written: a build with the debugger, hook and cancel tests removed from `tick` is not faster (`p1a_arith` 82 against 84 ms, `p1b_calls` 59 against 51 ms, inside the noise of 15 runs), so R3 is dropped. R4 (calls without a scope allocation) needs the slots of R2; without them only two small changes were made: the bindings of a call are allocated once (`ensureTotalCapacity`) and the test for `floor`, `ceiling` and `round` compares the name before it searches the scopes. A 830,000-call `fib(27)` takes 255 ms with R1 (352 ms before R1) and 262 ms with R4: no measurable gain, the changes stay because they are free. The cost of a call, about 300 ns, is in the allocations and the name lookups that R2 removes.

**0.0.7 (2026-10-19), R2 and a profiler.** `EVE_PROFILE=1 eve -x file.eve` samples the main thread every millisecond and prints the functions with most samples (Windows, symbols from the `.pdb`). The profile of `fib` and of `p1a` to `p4e` showed that the time was in comparisons of text, not in the scope search itself: the name of a variable (`Scope.find`), the operator of an assignment (`:=`, `::`, `<+`) and the name of a type (`Integer`, `Real`: `zero` and `coerce` run at every call for the result variable). Three changes: `nameEql` compares the length and the first byte before the text; the parser puts an `Op` on every assignment (`set`, `copy`, `push_back`, `push_front`) and a `TypeKind` on every type node. Full slot resolution in `check.zig` was not done: a block has no scope of its own and a `new` adds its binding when it runs, so the position of a variable depends on the path taken (design/design-bytecode.md, R2). Against the build before R1, same machine, alternating, 9 runs: `p1a_arith` 193 to 73 ms, `p1b_calls` 65 to 46, `p2c_procedures` 62 to 51, `p3a_modules` 97 to 75, `p3b_objects` 76 to 66, `p3c_module_state` 46 to 35; level 4 unchanged (`p4c`, `p4d` equal to the old build). `eve.exe` unchanged in size (4,000 KB).

**0.0.7 (2026-10-19), the bytecode machine, stage B5.2.** `--engine bc` runs `process main` and the functions it calls on the register machine when the emitter translates them; the rest stays with the tree walker. Not saved in the history yet (`bmark.py --engine bc` refuses `--save`). Median of 9 runs, whole process: `p1a_arith` 70 to 26 ms, `p1b_calls` 46 to 15 ms (start-up is 7 ms of each); the other benchmarks use constructs that are not translated yet and keep their time.

### Totals per run

The sum of the median times of the benchmarks of each level. A dash means the level was not measured in that run.

<!-- runs:begin -->
| Version | Date | Build | Commit | Level 1 | Level 2 | Level 3 | Level 4 | Level 5 | Level 6 |
|---|---|---|---|---|---|---|---|---|---|
| 0.0.7 | 2026-10-19 | ReleaseSafe | cc28760 | 341 ms | 143 ms | 230 ms | 1026 ms | 158 ms | 2425 ms |
| 0.0.7 | 2026-10-19 | ReleaseSafe | 810aae5 | 164 ms | 112 ms | 175 ms | 657 ms | 107 ms | 2072 ms |
| 0.0.7 | 2026-10-19 | ReleaseSafe | 320a228 | 148 ms | 97 ms | 154 ms | 678 ms | 106 ms | 1920 ms |
<!-- runs:end -->
