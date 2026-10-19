# Eve manual

This is the manual of **Eve**, a scripting language for data processing and test automation, and of its first implementation: the Eve virtual machine, `eve`, written in Zig. The language itself is defined by the [specification](https://github.com/elucian/eve-lang/blob/master/spec/index.md) and taught by the [tutorial](https://sagecode.org/projects/eve/index.html); this manual says how to install and use the programs, which features work, and how well.

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
State of the working tree on 2026-10-19, version 0.0.7, not a release; last release: no release notes yet.

**Tests.** 399 of 399 conformance and smoke tests pass (the last run of each suite; [summary](tests.md)):

| Tests | Total | Pass | % |
|---|---|---|---|
| Level 1 | 68 | 68 | 100% |
| Level 2 | 78 | 78 | 100% |
| Level 3 | 56 | 56 | 100% |
| Level 4 | 47 | 47 | 100% |
| Level 5 | 117 | 117 | 100% |
| Level 6 | 12 | 12 | 100% |
| Level 7 | 0 | 0 | - |
| Smoke | 21 | 21 | 100% |

**Features.** By target version and stage (the stages and every feature: [features](features.md)):

| Version | Validated | Drafted | Design | Planned | Total |
|---|---|---|---|---|---|
| Version 0.1 | 23 | 10 | 0 | 0 | 33 |
| Version 0.2 | 4 | 8 | 0 | 1 | 13 |
| Version 0.3 | 5 | 8 | 0 | 2 | 15 |
| Version 0.4 | 2 | 8 | 9 | 12 | 31 |
| Version 0.5 | 0 | 5 | 11 | 7 | 23 |
| Version 0.6 | 0 | 1 | 8 | 4 | 13 |
| Version 0.7 | 0 | 0 | 3 | 0 | 3 |
| Version 0.9 | 0 | 0 | 0 | 3 | 3 |
| Version 1.0 | 0 | 0 | 0 | 2 | 2 |
| **All** | **34** | **40** | **31** | **31** | **136** |

**Performance.** TODO: no saved ReleaseSafe benchmark run of 0.0.7. Run `python script/bmark.py --build ReleaseSafe --eve temp/rel/bin/eve.exe --save`, then this script again. Benchmarks: [performance report](performance.md).
<!-- /GEN:progress -->

## Links

<!-- GEN:links (script/relnotes.py) -->
- [Using eve: the command line](usage.md)
- [Features and their stage](features.md)
- [Tests: summary](tests.md)
- [Performance report](performance.md)
- [Release notes](releases/README.md)
- [Component: evevm](evevm/README.md)
- [Component: evecp](evecp/README.md)
- [Component: evecm](evecm/README.md)
- [Component: evetx](evetx/README.md)
- [Component: eveux](eveux/README.md)
- [Component: evewp](evewp/README.md)
- [Driver: duckdb](drivers/duckdb/README.md)
- [Specification: contents](https://github.com/elucian/eve-lang/blob/master/spec/index.md)
- [Specification: conventions](https://github.com/elucian/eve-lang/blob/master/spec/README.md)
- [Tutorial: topics](https://sagecode.org/projects/eve/index.html)
- [Tutorial: feature tests](https://sagecode.org/projects/eve/features.html)
- [Tutorial: smoke test and performance](https://sagecode.org/projects/eve/quality.html)
- [Tutorial: the Eve VM](https://sagecode.org/projects/eve/vm.html)
<!-- /GEN:links -->
