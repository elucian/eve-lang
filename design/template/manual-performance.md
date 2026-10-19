<!-- Template of manual/performance.md (script/genmanual.py). Made into the page when the page is missing; afterwards only the GEN blocks are written again. -->
# Performance

How fast `eve` runs, measured with the ReleaseSafe build on one machine. Compare only runs of the same machine.

## Last run

The total time of the benchmarks of each level of the language, against their twins in Python.

<!-- GEN:summary (script/genmanual.py) -->
<!-- /GEN:summary -->

## Benchmarks

A benchmark is a small Eve program that does one kind of work many times: arithmetic and loops, function calls, collections, strings, classes, parallel work, database reads and writes, the machine and the network. The levels follow the versions of Eve, as the tests do, so each version adds the benchmarks of its own features. Every benchmark has a **twin written in Python** that does the same work, the reference for the comparison.

<!-- GEN:benchmarks (script/genmanual.py) -->
<!-- /GEN:benchmarks -->

## Benchmark results

The median time of several runs of each benchmark and of its Python twin, and the peak memory of `eve`. **Eve / Python** below 1 means Eve is faster.

<!-- GEN:results (script/genmanual.py) -->
<!-- /GEN:results -->

## By version

<!-- GEN:history (script/genmanual.py) -->
<!-- /GEN:history -->
