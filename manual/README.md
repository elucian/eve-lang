# Eve manual

This is the manual of **Eve**, a scripting language for data processing and test automation, and of its first implementation: the Eve virtual machine, `eve`, written in Zig. The language is taught by the [tutorial](https://sagecode.org/projects/eve/index.html); this manual says how to install and use the programs, which features work, and how well.

## Contents

| Page | What it covers |
|---|---|
| [Using eve](usage.md) | the command line, the REPL, the machine and the service, the exit codes |
| [Features](features.md) | every feature of Eve and how far it is: validated, drafted, design, planned |
| [Tests](tests.md) | the conformance tests of each level and the smoke tests: how many pass |
| [Performance](performance.md) | the benchmarks, against twin programs in Python |
| [Release notes](releases/README.md) | what each release delivered |

## The programs

| Program | Component or driver | What it is |
|---|---|---|
| `eve` | [evevm](evevm/README.md), [evecp](evecp/README.md), [evecm](evecm/README.md) | runs Eve programs, the REPL, the machine and the service; the compiler front end and the common part are built in |
| `evecp` | [evecp](evecp/README.md) | the compiler front end as a program: check a script, write documentation, make a project |
| `evedb` | driver [duckdb](drivers/duckdb/README.md) | a database server around DuckDB that answers as PostgreSQL; the test and analytic database of Eve |
| `evetx` | [evetx](evetx/README.md) | the terminal IDE: tree, editor, run and debug, data tables |
| `eveux` | [eveux](eveux/README.md) | the native graphical workbench (early draft) |
| `evewp` | [evewp](evewp/README.md) | the Eve Web Portal: hosting, monitoring and the web framework (design; not in the distribution yet) |

A distribution holds `bin/` (the programs and `duckdb.dll`), `lib/` (the standard library in Eve, found by `eve` beside `bin/`), `manual/` (this manual) and `tools/` (syntax colors for VS Code, Zed and Tree-sitter, and the typing aids).

## Progress

Written by the release tooling at every release, never by hand.

<!-- GEN:progress (script/relnotes.py) -->
State of the working tree on 2026-10-20, version 0.0.7, not a release; last release: no release notes yet.

**Tests.** 436 of 441 conformance and smoke tests pass (the last run of each suite; [summary](tests.md)):

| Tests | Total | Pass | % |
|---|---|---|---|
| Level 1 | 76 | 74 | 97% |
| Level 2 | 78 | 77 | 98% |
| Level 3 | 62 | 62 | 100% |
| Level 4 | 50 | 50 | 100% |
| Level 5 | 117 | 115 | 98% |
| Level 6 | 14 | 14 | 100% |
| Level 7 | 2 | 2 | 100% |
| Smoke | 21 | 21 | 100% |
| Bytecode | 20 | 20 | 100% |
| Scaffold | 1 | 1 | 100% |

**Features.** By level and stage (the stages and every feature: [features](features.md)):

| Level | Validated | Drafted | Design | Planned | Total |
|---|---|---|---|---|---|
| Level 1 | 14 | 5 | 0 | 0 | 19 |
| Level 2 | 2 | 1 | 0 | 0 | 3 |
| Level 3 | 5 | 8 | 0 | 1 | 14 |
| Level 4 | 5 | 8 | 0 | 2 | 15 |
| Level 5 | 7 | 14 | 0 | 8 | 29 |
| Level 6 | 0 | 6 | 0 | 23 | 29 |
| Level 7 | 0 | 2 | 0 | 8 | 10 |
| All levels | 13 | 5 | 0 | 7 | 25 |
| **All** | **46** | **49** | **0** | **49** | **144** |

**Performance.** Total median time of the benchmarks of each level, ReleaseSafe build, run of 2026-10-19 17:49 (commit `b3019cb`), against the twins in Python and against nothing (first run). Every benchmark: [performance report](performance.md).

| Benchmarks | Eve | Python | Eve / Python | Change |
|---|---|---|---|---|
| Level 1 | 138 ms | 202 ms | 0.7x | - |
| Level 2 | 91 ms | 112 ms | 0.8x | - |
| Level 3 | 141 ms | 128 ms | 1.1x | - |
| Level 4 | 550 ms | 697 ms | 0.8x | - |
| Level 5 | 80 ms | 136 ms | 0.6x | - |
| Level 6 | 2297 ms | 11313 ms | 0.2x | - |
<!-- /GEN:progress -->

## Links

<!-- GEN:links (script/relnotes.py) -->
- [Using eve: the command line](usage.md)
- [Features and their stage](features.md)
- [Tests: summary](tests.md)
- [Performance report](performance.md)
- [Release notes](releases/README.md)
- [Level 1: features and examples](levels/level1.md)
- [Level 2: features and examples](levels/level2.md)
- [Level 3: features and examples](levels/level3.md)
- [Level 4: features and examples](levels/level4.md)
- [Level 5: features and examples](levels/level5.md)
- [Level 6: features and examples](levels/level6.md)
- [Level 7: features and examples](levels/level7.md)
- [All levels: tools and documents](levels/all.md)
- [Reference: keywords](reference/keywords.md)
- [Reference: operators](reference/operators.md)
- [Reference: delimiters](reference/delimiters.md)
- [Component: evevm](evevm/README.md)
- [Component: evecp](evecp/README.md)
- [Component: evecm](evecm/README.md)
- [Component: evetx](evetx/README.md)
- [Component: eveux](eveux/README.md)
- [Component: evewp](evewp/README.md)
- [Driver: duckdb](drivers/duckdb/README.md)
- [Tutorial: topics](https://sagecode.org/projects/eve/index.html)
- [Tutorial: feature tests](https://sagecode.org/projects/eve/features.html)
- [Tutorial: smoke test and performance](https://sagecode.org/projects/eve/quality.html)
- [Tutorial: the Eve VM](https://sagecode.org/projects/eve/vm.html)
<!-- /GEN:links -->
