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
| `p1a_arith.eve` | 209 ms | 71 ms | 3.0x | integer and real arithmetic, `for` and `while` loops, variables |
| `p1b_calls.eve` | 96 ms | 47 ms | 2.0x | function calls, recursion (`fib(20)`), parameter binding |
| `p1c_collections.eve` | 29 ms | 45 ms | 0.6x | list appends and iteration (60,000 elements), DataMap and DataSet |
| `p1d_strings.eve` | 65 ms | 53 ms | 1.2x | string appends, placeholders, regular expression matches |
| **Level 2** | | | | |
| planned | | | | import of a module, `apply` of an aspect, a call through an extension method |
| **Level 3** | | | | |
| planned | | | | read and parse a CSV and a JSON file, decimal arithmetic, optional values |
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

### Table of runs

Columns: **Version** is the version of the VM; **Date** the day of the run; **Time (Debug Mode)** the total median time of the benchmarks of the level with the Debug build (`zig build -p ..`), the one used to develop; **Time (Optimized)** the same with the ReleaseSafe build (`zig build -Doptimize=ReleaseSafe`), the one to compare between versions. A run made in only one mode leaves the other cell with a dash. The change against the previous version is written in the notes above, not in a column.

| Version | Date | Time (Debug Mode) | Time (Optimized) |
|---|---|---|---|
| **Level 1** | | | |
| 0.0.1 | 2026-10-07 | 1843 ms | 400 ms |
| **Level 2** | | | |
| not measured | | - | - |

Ideas to watch, in the order of their likely gain: variable lookup by slot instead of by name (the scan of the scopes shows in `p1a_arith` and `p1b_calls`); no copy of the argument list for each call; the string append that builds a new string each time (`p1d_strings`); the static check should cost almost nothing against the run, so its time is part of every benchmark.
