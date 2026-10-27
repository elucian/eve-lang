# Performance tests

One small benchmark for each level, to see that the VM stays fast while features and optimizations arrive. They are not conformance tests: the runner of `test/levelN/` ignores this folder. Each benchmark prints a result and declares it in an `/*@expect*/` block, so a wrong answer is an error, never a fast time. Each has a twin in Python (`ref/<name>.py`) that does the same work, and the report shows the ratio Eve / Python (1.0x is the speed of CPython). The twin is a yardstick, not a goal.

## Run

```
python script/bmark.py                    # 5 runs of each benchmark, compared with the last saved run
python script/bmark.py --save             # also append the run to history.json and rewrite the tables below
python script/bmark.py --check            # exit 1 when a benchmark is more than 25% slower than the last saved run
python script/bmark.py --level 1 --runs 9
python script/bmark.py --build ReleaseSafe --eve temp/rel/bin/eve.exe --both --save   # also the bytecode machine (column BCode)
```

- Compare only runs of the same build and the same machine, with nothing else running; trust the median, not one run. The ReleaseSafe build (`zig build -Doptimize=ReleaseSafe -p temp/rel`) is the one to compare between versions; Debug is for development.
- The sizes come from the programs found beside `eve.exe`: build `evetx` and `eveux` into the same folder (`cd code/evetx && zig build -Doptimize=ReleaseSafe -p ../../temp/rel`) or their column stays empty.
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
| `p1e_rational` | exact fractions (`Rational`): a telescoping sum of 200,000 fractions, 20,000 runs of Newton's square root of 2 in fractions, 100,000 comparisons; the twin uses Python's `fractions.Fraction` |
| `p1f_complex` | complex numbers (`Complex`): the Mandelbrot iteration `z * z + c` on a grid of 70 by 40 points, up to 100 iterations; the twin uses Python's `complex` |
| `p1g_dates` | dates (`Date`): for 40,000 consecutive days the year, month, day, weekday and ISO week, `add_months` and a difference of days; the twin uses Python's `datetime.date` |
| `p1h_time_format` | patterns: 20,000 dates written as dd/MM/yyyy and read back, 20,000 instants written as ISO text with milliseconds; the twin uses `strftime` and `strptime` |
| `p1i_zone_offsets` | time zones: `zone.offset` for 60,000 instants (1900 to 2100) in three zones, read from the meta database; the twin uses `zoneinfo` |
| `p1j_datetime` | `DateTime`: 60,000 instants seen in America/New_York with the hour, the day and the offset, and `time.make` for every 20th; the twin uses `zoneinfo` |
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

The latest saved ReleaseSafe run, median time of the whole process (start-up included): **Eve** is the tree walker, **BCode** the bytecode machine (`--both`, the output must be equal), **Python** the twin, **EVE/PT** the ratio Eve / Python, **Mem** the peak memory of Eve.

<!-- results:begin -->
| Benchmark | Eve | BCode | Python | EVE/PT | Mem |
|---|---|---|---|---|---|
| **Level 1** | | | | | |
| `p1a_arith` | 108 ms | 43 ms | 95 ms | 1.1x | 6.1 MB |
| `p1b_calls` | 86 ms | 30 ms | 54 ms | 1.6x | 6.2 MB |
| `p1c_collections` | 30 ms | 20 ms | 60 ms | 0.5x | 8.2 MB |
| `p1d_strings` | 24 ms | 26 ms | 104 ms | 0.2x | 6.5 MB |
| **Level 2** | | | | | |
| `p2a_aspects` | 18 ms | 19 ms | 57 ms | 0.3x | 6.1 MB |
| `p2b_closures` | 68 ms | 67 ms | 66 ms | 1.0x | 7.6 MB |
| `p2c_procedures` | 80 ms | 111 ms | 67 ms | 1.2x | 6.2 MB |
| **Level 3** | | | | | |
| `p3a_modules` | 162 ms | 109 ms | 74 ms | 2.2x | 6.2 MB |
| `p3b_objects` | 98 ms | 117 ms | 61 ms | 1.6x | 6.3 MB |
| `p3c_module_state` | 62 ms | 57 ms | 68 ms | 0.9x | 6.2 MB |
| **Level 4** | | | | | |
| `p4a_parallel_sum` | 194 ms | 181 ms | 156 ms | 1.2x | 47.4 MB |
| `p4b_channel` | 95 ms | 134 ms | 353 ms | 0.3x | 6.3 MB |
| `p4c_groups` | 242 ms | 251 ms | 386 ms | 0.6x | 8.4 MB |
| `p4d_tasks` | 218 ms | 218 ms | 313 ms | 0.7x | 8.3 MB |
| `p4e_garbage` | 181 ms | 111 ms | 186 ms | 1.0x | 6.2 MB |
| **Level 5** | | | | | |
| `p5a_sql_function` | 131 ms | 148 ms | 240 ms | 0.5x | 9.4 MB |
| **Level 6** | | | | | |
| `p6a_evedb_store` | 826 ms | 769 ms | - | - | 56.3 MB |
| `p6b_evedb_load` | 337 ms | 325 ms | - | - | 16.7 MB |
| `p6c_pg_records` | 229 ms | 259 ms | - | - | 81.9 MB |
| `p6d_olap_groupby` | 625 ms | 907 ms | - | - | 6.3 MB |
| `p6e_http_requests` | 449 ms | 502 ms | 986 ms | 0.5x | 52.0 MB |
| **Level 7** | | | | | |
| planned | | | | | |
<!-- results:end -->

## Size of the programs

The size of each program is saved with every run. A version that grows `eve` by more than 10% gets a sentence in the notes. The change is against the previous run of the same build.

<!-- size:begin -->
| Version | 0.0.7 | 0.0.8 |
|---|---|---|
| Date | 2026-10-19 | 2026-10-21 |
| Build | ReleaseSafe | ReleaseSafe |
| Commit | b3019cb | 43003a9 |
| eve | 4,055 KB | 4,199 KB |
| evevm | 4,055 KB | 4,199 KB |
| evecp | 1,210 KB | 1,210 KB |
| evetx | 2,198 KB | 2,198 KB |
| eveux | 9,088 KB | 9,088 KB |
| evedb | 1,264 KB | 1,264 KB |
| eve change | - | +3.6% |
<!-- size:end -->

## History

Each saved run adds a paragraph to the notes (what changed in the VM, faster or slower, and why when a benchmark moves by more than 10%) and a row to the totals. `history.json` keeps the last 5 versions: one run of each build for an older version, the last two runs for the newest. The tables below show the last two runs.

### Notes by version

**0.0.7 (2026-10-19), baseline for the bytecode.** The first run of the ladder (design/design-bytecode.md), before any change. Levels 5 and 6 are measured for the first time: `p6a` to `p6e` run against `evedb` and are 0.0 to 0.9 of the Python twins (psycopg2 pays per row what the column batches do not). `eve.exe` is 3,988 KB; `evevm.exe` is the same file. Runs of earlier versions were removed on 2026-10-19: they were made on another load and did not cover levels 5 and 6.

**0.0.7 (2026-10-19), R0 and R1 of the bytecode ladder.** R0, the base line: `Value` is 24 bytes, `Node` 80 (104 after R1), `Var` 56, `Scope` 64, `Func` 40 (unit test `value sizes`). R1: the parser sets an `Op` on every binary and compound-assignment node and converts plain number literals once; `applyOp` does integer and real arithmetic and integer comparison without comparing the operator text. Measured against the commit before, same machine, alternating builds, 9 runs: `p1a_arith` 195 to 75 ms (3.0x to 1.1x Python), `p1b_calls` 62 to 45 ms, `p1c_collections` 22 to 18 ms, `p1d_strings` 15 to 14 ms. A first try of the net time-out (`set_timeout`) made `p6e_http_requests` 10 times slower, because a task with a time-out made the scheduler poll in 1 ms steps (about 15 ms on Windows); the scheduler now waits on its condition up to the timer, and `p6e` is 394 ms. `eve.exe` +0.4%. The absolute times of this row are lower than the first 0.0.7 row because the machine was less loaded; read the ratios Eve / Python.

**0.0.7 (2026-10-19), R3 and R4.** R3 (a cheaper statement prologue) was measured before it was written: a build with the debugger, hook and cancel tests removed from `tick` is not faster (`p1a_arith` 82 against 84 ms, `p1b_calls` 59 against 51 ms, inside the noise of 15 runs), so R3 is dropped. R4 (calls without a scope allocation) needs the slots of R2; without them only two small changes were made: the bindings of a call are allocated once (`ensureTotalCapacity`) and the test for `floor`, `ceiling` and `round` compares the name before it searches the scopes. A 830,000-call `fib(27)` takes 255 ms with R1 (352 ms before R1) and 262 ms with R4: no measurable gain, the changes stay because they are free. The cost of a call, about 300 ns, is in the allocations and the name lookups that R2 removes.

**0.0.7 (2026-10-19), R2 and a profiler.** `EVE_PROFILE=1 eve -x file.eve` samples the main thread every millisecond and prints the functions with most samples (Windows, symbols from the `.pdb`). The profile of `fib` and of `p1a` to `p4e` showed that the time was in comparisons of text, not in the scope search itself: the name of a variable (`Scope.find`), the operator of an assignment (`:=`, `::`, `<+`) and the name of a type (`Integer`, `Real`: `zero` and `coerce` run at every call for the result variable). Three changes: `nameEql` compares the length and the first byte before the text; the parser puts an `Op` on every assignment (`set`, `copy`, `push_back`, `push_front`) and a `TypeKind` on every type node. Full slot resolution in `check.zig` was not done: a block has no scope of its own and a `new` adds its binding when it runs, so the position of a variable depends on the path taken (design/design-bytecode.md, R2). Against the build before R1, same machine, alternating, 9 runs: `p1a_arith` 193 to 73 ms, `p1b_calls` 65 to 46, `p2c_procedures` 62 to 51, `p3a_modules` 97 to 75, `p3b_objects` 76 to 66, `p3c_module_state` 46 to 35; level 4 unchanged (`p4c`, `p4d` equal to the old build). `eve.exe` unchanged in size (4,000 KB).

**0.0.7 (2026-10-19), the bytecode machine, stage B5.2.** `--engine bc` runs `process main` and the functions it calls on the register machine when the emitter translates them; the rest stays with the tree walker. Not saved in the history yet (`bmark.py --engine bc` refuses `--save`). Median of 9 runs, whole process: `p1a_arith` 70 to 26 ms, `p1b_calls` 46 to 15 ms (start-up is 7 ms of each); the other benchmarks use constructs that are not translated yet and keep their time.

**0.0.7 (2026-10-19), BCode column.** `bmark.py --both` runs each benchmark on the tree walker and on the bytecode machine, refuses a run whose outputs differ, and saves both. Only the constructs of stage B5.2 are native, so most benchmarks equal the tree walker; where the bridge is used it costs: `p1c_collections` 18.6 to 23.2 ms, `p4e_garbage` 113 to 135 ms, `p2a_aspects` 11.4 to 12.2 ms. `p1a_arith` 64 to 26 ms and `p1b_calls` 41 to 16 ms. The run is the first with `Mem` and `EVE/PT` as column names. Level 6 is 20% above the earlier row (evedb on this load), BCode equal to Eve there.

**0.0.8 (2026-10-21), first alpha release, a loaded machine.** The saved run is 55% to 177% slower than the last 0.0.7 run (levels 1 to 5), but the code is not: the machine was busy (CPU 71% from other programs during the run). A side by side run under the same load, the ReleaseSafe build of b3019cb (the last saved 0.0.7 run) against 0.0.8, each with the benchmarks of its own commit, 7 runs alternated, median: `p1a_arith` 103.2 against 103.9 ms, `p1b_calls` 65.6 against 68.8, `p1c_collections` 26.6 against 26.1, `p2b_closures` 58.8 against 61.8, `p3a_modules` 89.7 against 90.7, `p4a_parallel_sum` 178.1 against 181.9: 0.0.8 is 0% to 5% slower, inside the noise, after D-213 (one scope per loop) and the built-in library of step L1. Level 6 (`evedb`, PostgreSQL, HTTP) moved by -6% to +59%, the same load. `eve.exe` is 4,199 KB (+3.6%, the library functions in corelib.zig). Compare the next release with a run on a quiet machine, not with this one.

**0.0.8 (2026-10-26), the `call` instruction (B5.3a, design/design-bytecode.md §16).** Not saved: the machine was loaded (CPU 77% from other programs), and wall times moved by 2 to 3 times between runs of the same binary. Measured instead as the minimum of the CPU cycles of the process over 9 alternated runs of the binary of d77ed0c and the new one (`QueryProcessCycleTime`; the CPU time of Windows counts in 15.6 ms steps and is too coarse): `p3a_modules` -19%, `p1k_zone_dense` -19%, `p3c_module_state` -18%, `p1f_complex` -17%, `p2c_procedures` -16%, `p1g_dates` -14%, `p1i_zone_offsets` -10%, the rest within ±3% (`p5a_sql_function` moves by ±15% from run to run, the database). Two findings on the loop itself: an arm added to `execute` made `p1a_arith` 7% slower with an identical listing, and a test written as the complement of a list of tags was slower than the list (OPT-25 of design/design-bytecode-opt.md). `eve.exe` size unchanged within 1%.

**0.0.8 (2026-10-26), routines by themselves (B5.3b, design/design-bytecode.md §16).** Not saved (the machine was loaded); measured as the minimum of the CPU cycles over 9 alternated runs against the binary of d77ed0c: `p3a_modules` -47%, `p1k_zone_dense` -35%, `p1i_zone_offsets` -28%, `p3c_module_state` -23%, `p2c_procedures` -22%, `p1f_complex` -14%, `p1g_dates` -6%; `p1b_calls` +5% (a heap region per call, OPT-28 of design/design-bytecode-opt.md) and `p1h_time_format` +5% (the adapter of library natives, OPT-12); the rest within ±3%. Two dead ends on the way, both in the notes of the optimization page: taking the register pointer again at every instruction (`p1a_arith` +24%, replaced by a stack per nested run) and resolving the target of a call twice (`p1f_complex` +22%).

### Totals per run

The sum of the median times of the benchmarks of each level. A dash means the level was not measured in that run.

<!-- runs:begin -->
| Version | Date | Level 1 | Level 2 | Level 3 | Level 4 | Level 5 | Level 6 |
|---|---|---|---|---|---|---|---|
| 0.0.7 | 2026-10-19 | 138 ms | 91 ms | 141 ms | 550 ms | 80 ms | 2297 ms |
| 0.0.8 | 2026-10-21 | 248 ms | 165 ms | 322 ms | 930 ms | 131 ms | 2467 ms |
<!-- runs:end -->

## Rational speed (2026-10-24, F-LNG-30)

Exact fractions are as cheap as floats in the VM, because the work is two 64-bit multiplications and a GCD of 64-bit numbers (`code/evecm/src/rational.zig`): addition takes the GCD of the denominators first (Knuth 4.5.1), multiplication reduces across before it multiplies, so a result in lowest terms comes without a second reduction and the products stay inside 128 bits.

| Measure | Result |
|---|---|
| Native, one addition or division of fractions (Zig, ReleaseFast) | about 25 ns (a `Real` addition is 1 ns) |
| `p1e_rational` (about 1.3 million operations on the bytecode machine) | 80 to 120 ms; the same loops on `Real` take 150 to 235 ms in the same session: the interpreter dispatch costs more than the fraction |
| `p1e_rational` against Python `fractions.Fraction` | 0.07x to 0.1x: 10 to 15 times faster |
| Before the GCD-first addition (one 128-bit GCD per operation) | 860 ns per addition: 35 times slower |

Run `python script/bmark.py --level 1` to repeat it. The correctness side is `test/level3/c46` to `c49` (literals, 100 laws, Farey counts, harmonic numbers up to the overflow at n = 47, Bernoulli numbers B20 and B30, 300 sorted fractions: all checked against Python's `fractions`) and the 200,000 random operations of the unit test `random operands agree with the plain formula` in `rational.zig`.

**Complex (2026-10-24, F-LNG-31).** `p1f_complex` runs at about 1.3x the time of CPython's built-in `complex` (110 ms against 84 ms); the loop `z = z * z + c` alone costs 1.35x the same loop on `Real`. Most of the time is the call `math.abs(z)` of a library module in the loop condition (TD-71), not the arithmetic.
