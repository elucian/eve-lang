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

| File | Level | What it measures |
|---|---|---|
| `p1a_arith.eve` | 1 | integer and real arithmetic, `for` and `while` loops, variables |
| `p1b_calls.eve` | 1 | function calls, recursion (`fib(20)`), parameter binding |
| `p1c_collections.eve` | 1 | list appends and iteration (60,000 elements), DataMap and DataSet |
| `p1d_strings.eve` | 1 | string appends, placeholders, regular expression matches |
| level 2 | 2 | planned: import of a module, `apply` of an aspect, a call through an extension method |
| level 3 | 3 | planned: read and parse a CSV and a JSON file, decimal arithmetic, optional values |
| level 4 | 4 | planned: a parallel group of aspects, a channel with 100,000 messages, a stream |
| level 5 | 5 | planned: insert and select 10,000 rows in the Eve database |
| level 6 | 6 | planned: 1,000 requests to a local `service` script |
| level 7 | 7 | planned: render an HTML template 1,000 times |

A new level adds a file `p<level><letter>_<name>.eve`; `script/bmark.py` finds it by its name. Keep a benchmark between 50 ms and 2 s: long enough to measure, short enough to run at every commit.

## History

The measured runs are in `history.json` (date, version, commit, build, median and best time of each benchmark). Whoever saves a run adds a paragraph for the version under "Notes by version" (what changed in the VM, whether the benchmarks got faster, appreciation, or slower, depreciation, and why a drop of more than 10% happened), then a row in the table of its build. The tables stay slim: the change against the previous row of the same level and build is written in the notes, not in a column.

### Notes by version

**0.0.1 (2026-10-07), baseline.** First measure, right after level 1 passed 82 of 82. Tree-walking interpreter: names are found by a linear scan of the scopes, values are copied as tagged unions, the static check runs once before the run. `p1a_arith` (500,000 loop turns) dominates the total. The ReleaseSafe build is about 4.6 times faster than Debug on the same code; compare versions on ReleaseSafe and use Debug only to develop. No earlier version exists, so there is no appreciation or depreciation yet.

### Debug build (`zig build -p ..`)

| Level | Version | Date | Total (median) |
|---|---|---|---|
| **Level 1** | | | |
| | 0.0.1 | 2026-10-07 | 1843 ms |
| **Level 2** | | | |
| | not measured | | |

### Optimized build (`zig build -Doptimize=ReleaseSafe`)

| Level | Version | Date | Total (median) |
|---|---|---|---|
| **Level 1** | | | |
| | 0.0.1 | 2026-10-07 | 400 ms |
| **Level 2** | | | |
| | not measured | | |

Ideas to watch, in the order of their likely gain: variable lookup by slot instead of by name (the scan of the scopes shows in `p1a_arith` and `p1b_calls`); no copy of the argument list for each call; the string append that builds a new string each time (`p1d_strings`); the static check should cost almost nothing against the run, so its time is part of every benchmark.
