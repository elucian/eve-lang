# Performance tests

A small benchmark for each level. They are not conformance tests (the runner of `test/levelN/` ignores this folder): they check that the VM stays fast while features and optimizations arrive. Every benchmark prints a result and declares it in an `/*@expect*/` block, so a wrong answer is reported as an error, never as a fast time.

## Run

```
python script/bmark.py                    # 5 runs of every benchmark, the report compares with the last saved run
python script/bmark.py --save             # also append the run to history.json (do it for every version and optimization)
python script/bmark.py --check            # exit 1 when a benchmark is more than 25% slower than the last saved run
python script/bmark.py --level 1 --runs 9
python script/bmark.py --build ReleaseSafe --eve temp/rel/bin/eve.exe --save
```

A Debug build (`zig build -p ..`) and a ReleaseSafe build (`zig build -Doptimize=ReleaseSafe -p ../temp/rel`) are compared only with runs of the same build. Times depend on the machine and on its load: compare runs made on the same machine, with nothing else running, and trust the median of several runs, not one.

## Benchmarks

<!-- bench:begin -->
| Benchmark | Duration | Python | Eve / Python | What it measures |
|---|---|---|---|---|
| **Level 1** | | | | |
| `p1a_arith.eve` | 223 ms | 80 ms | 2.8x | integer and real arithmetic, `for` and `while` loops, variables |
| `p1b_calls.eve` | 111 ms | 54 ms | 2.1x | function calls, recursion (`fib(20)`), parameter binding |
| `p1c_collections.eve` | 29 ms | 54 ms | 0.5x | list appends and iteration (60,000 elements), DataMap and DataSet |
| `p1d_strings.eve` | 72 ms | 65 ms | 1.1x | string appends, placeholders, regular expression matches |
| **Level 2** | | | | |
| `p2a_aspects.eve` | 49 ms | 48 ms | 1.0x | 5,000 `apply` of an aspect with two inputs and one output (a new scope and a new boot for each call) |
| `p2b_closures.eve` | 66 ms | 55 ms | 1.2x | a closure called 50,000 times, a lambda called 50,000 times, a function that makes closures 2,000 times |
| `p2c_procedures.eve` | 96 ms | 60 ms | 1.6x | 30,000 calls of a procedure with `@` parameters, a function with defaults and a vararg procedure |
| **Level 3** | | | | |
| `p3a_modules.eve` | 148 ms | 62 ms | 2.4x | 50,000 calls of module functions (`mathx.square`, `mathx.clamp`) and 50,000 reads of a module constant |
| `p3b_objects.eve` | 82 ms | 57 ms | 1.4x | 5,000 objects of a class and of its subclass, 50,000 method calls, 20,000 extension method calls |
| `p3c_module_state.eve` | 90 ms | 59 ms | 1.5x | 50,000 calls of a module procedure that changes private state and 50,000 reads of it |
| **Level 4** | | | | |
| planned | | | | a parallel group of aspects, a channel with 100,000 messages, a stream |
| **Level 5** | | | | |
| planned | | | | insert and select 10,000 rows in the Eve database |
| **Level 6** | | | | |
| planned | | | | 1,000 requests to a local `service` script |
| **Level 7** | | | | |
| planned | | | | render an HTML template 1,000 times |
<!-- bench:end -->

The table is rewritten by `--save` from the last ReleaseSafe run and from the `** perf:` line of each file. A new level adds a file `p<level><letter>_<name>.eve`; `script/bmark.py` finds it by its name. Keep a benchmark between 50 ms and 2 s: long enough to measure, short enough to run at every commit.

## Reference language

Every benchmark has a twin written in Python, `ref/<name>.py`, that does the same work and prints the same result. `script/bmark.py` runs both, whole process against whole process (start-up included), and reports the ratio **Eve / Python**: 1.0x is the speed of CPython, 5x is five times slower. The twin is a permanent yardstick, not a goal: a machine and a Python version change, the ratio shows whether Eve moves toward or away from a mature interpreter when features and optimizations arrive. The times of Python are saved with each run in `history.json` (key `python`). A new benchmark adds its twin; a twin must keep the same work (same loops, same sizes) as the Eve file. Other reference languages can be added the same way (`ref/<name>.js`, ...) when someone needs them.

## History

The measured runs are in `history.json` (date, version, commit, build, median and best time of each benchmark). Whoever saves a run adds a paragraph for the version under "Notes by version" (what changed in the VM, whether the benchmarks got faster, appreciation, or slower, depreciation, and why a drop of more than 10% happened), then a row in the table of runs. The table stays slim: the change against the previous row of the same level and build is written in the notes, not in a column.

### Notes by version

**0.0.1 (2026-10-07), baseline.** First measure, right after level 1 passed 82 of 82. Tree-walking interpreter: names are found by a linear scan of the scopes, values are copied as tagged unions, the static check runs once before the run. `p1a_arith` (500,000 loop turns) dominates the total. The ReleaseSafe build is about 4.6 times faster than Debug on the same code; compare versions on ReleaseSafe and use Debug only to develop. No earlier version exists, so there is no appreciation or depreciation yet.

**0.0.1 (2026-10-08), levels 2 and 3 measured.** Six benchmarks were added with their Python twins: `p2a_aspects` (5,000 `apply`), `p2b_closures` (closure and lambda calls, closures made in a loop), `p2c_procedures` (`@` parameters, defaults, vararg), `p3a_modules` (calls and constants through a module), `p3b_objects` (objects, inheritance, methods, extension method) and `p3c_module_state` (private state of a module). Their ratios Eve / Python are 1.0 to 2.4, so no benchmark shows an accidental quadratic cost. The slowest is `p3a_modules` (2.4): `module.member` scans the `export` lists of the module on every access, then scans its scope by name; a table of members built when the module is loaded would remove the first scan. `apply` is cheap (1.0): a scope and the boot names per call. Level 1 is 9% above the first measure of 2026-10-07 (435 ms against 400 ms), inside the noise of the machine (the Python twins are 15 to 25% slower than in that run); the modules and classes of levels 2 and 3 do not touch the code that level 1 runs. A first run of this day was made with the laptop in power save mode (level 1 at 607 ms, Python twins 45 to 90% slower) and was discarded: measure with the laptop in normal power mode. The Debug build was measured the same day (levels 1, 2, 3: 2073, 955 and 1951 ms; level 1 is 12% above the first Debug measure). In Debug the ratios Eve / Python are higher (4 to 15; `p1a_arith`, `p3a_modules` and `p3c_module_state` are above 10), because the Debug build keeps every safety check; the ReleaseSafe ratios are 0.5 to 2.8, so none of them is an accidental quadratic cost.

### Table of runs

Columns: **Version** is the version of the VM; **Date** the day of the run; **Time (Debug Mode)** the total median time of the benchmarks of the level with the Debug build (`zig build -p ..`), the one used to develop; **Time (Optimized)** the same with the ReleaseSafe build (`zig build -Doptimize=ReleaseSafe`), the one to compare between versions. A run made in only one mode leaves the other cell with a dash. The change against the previous version is written in the notes above, not in a column.

| Version | Date | Time (Debug Mode) | Time (Optimized) |
|---|---|---|---|
| **Level 1** | | | |
| 0.0.1 | 2026-10-07 | 1843 ms | 400 ms |
| 0.0.1 | 2026-10-08 | 2073 ms | 435 ms |
| **Level 2** | | | |
| 0.0.1 | 2026-10-08 | 955 ms | 212 ms |
| **Level 3** | | | |
| 0.0.1 | 2026-10-08 | 1951 ms | 319 ms |

Ideas to watch, in the order of their likely gain: variable lookup by slot instead of by name (the scan of the scopes shows in `p1a_arith` and `p1b_calls`); no copy of the argument list for each call; the string append that builds a new string each time (`p1d_strings`); the static check should cost almost nothing against the run, so its time is part of every benchmark.
