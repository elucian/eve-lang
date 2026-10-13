# Eve Compiler Manual

This folder is the **manual of an Eve implementation**: how the compiler is built, how to use it, and which parts of the specification it supports. It replaces the old `docs/` skeleton (decision D-004 in [`../plan/decision_level1.md`](../plan/decision_level1.md)).

| Source | Role | Format |
|---|---|---|
| [Tutorial](https://sagecode.org/projects/eve/index.html) | Teaches the language | HTML (scl repo, published on sagecode.org) |
| [`spec/`](../spec/README.md) | Defines the language (normative) | Markdown, EBNF, JSON |
| [`test/`](../test/readme.md) | Conformance tests of every level, smoke tests, benchmarks | Eve, with `/*@expect*/` blocks |
| `manual/` | Documents one implementation of the spec | Markdown, with generated tables |

The manual never restates a language rule. It links to the spec section that defines the rule and says how the implementation handles it. Other Eve compilers can copy this folder's layout and generator for their own manual (D-003: many compilers, one specification).

Status: **in progress**. Usage of the machine: [usage.md](usage.md). Releases: [release/](release/README.md), one notes file per release (D-153). The first Eve implementation is a **virtual machine written in Zig** that runs Eve source as a scripting language (D-006). Its source is in `evevm/`, and the build produces `bin/eve.exe`, the official Eve implementation (D-007). It is being built now, and this manual is written alongside it (D-005). There is no compiler yet. Steps are in [`../plan/phase-7-manual.md`](../plan/phase-7-manual.md).

## Progress and performance

Updated at every release by `script/relnotes.py` from the tests, the [version map](../plan/version_map.md) and the saved benchmark runs; never edited by hand. The stages of a feature (design, drafted, validated) are defined in the [release policy](release/README.md#stages-of-a-feature).

<!-- GEN:progress (script/relnotes.py) -->
Progress at release 0.0.3 (2026-10-13); full record: [release notes 0.0.3](release/v0.0.3.md).

**Tests.** 349 of 349 conformance and smoke tests pass (the status that `script/runtest.py` saved):

| Tests | Total | Pass | % |
|---|---|---|---|
| [Level 1](../test/level1/readme.md) | 66 | 66 | 100% |
| [Level 2](../test/level2/readme.md) | 63 | 63 | 100% |
| [Level 3](../test/level3/readme.md) | 50 | 50 | 100% |
| [Level 4](../test/level4/readme.md) | 42 | 42 | 100% |
| [Level 5](../test/level5/readme.md) | 112 | 112 | 100% |
| [Level 6](../test/level6/readme.md) | 0 | 0 | - |
| [Level 7](../test/level7/readme.md) | 0 | 0 | - |
| [Smoke](../test/smoke/readme.md) | 16 | 16 | 100% |

**Features.** By target version and stage (stages: [policy](release/README.md)):

| Version | Validated | Drafted | Design | Planned | Total |
|---|---|---|---|---|---|
| Version 0.1 | 23 | 10 | 0 | 0 | 33 |
| Version 0.2 | 4 | 8 | 0 | 1 | 13 |
| Version 0.3 | 4 | 7 | 1 | 2 | 14 |
| Version 0.4 | 0 | 8 | 8 | 13 | 29 |
| Version 0.5 | 0 | 2 | 5 | 8 | 15 |
| Version 0.6 | 0 | 1 | 4 | 4 | 9 |
| Version 0.7 | 0 | 0 | 3 | 0 | 3 |
| Version 0.9 | 0 | 0 | 0 | 3 | 3 |
| Version 1.0 | 0 | 0 | 0 | 2 | 2 |
| **All** | **31** | **36** | **21** | **33** | **121** |

**Performance.** Total median time of the benchmarks of each level, ReleaseSafe build, run of 2026-10-13 11:44 (commit `505c7dc`), against the twins in Python and against version 0.0.2 (2026-10-09). Notes by version and history: [test/bmark/README.md](../test/bmark/README.md).

| Benchmarks | Eve | Python | Eve / Python | Change |
|---|---|---|---|---|
| Level 1 | 308 ms | 165 ms | 1.9x | -6% (faster) |
| Level 2 | 118 ms | 101 ms | 1.2x | +4% |
| Level 3 | 228 ms | 117 ms | 1.9x | +0% |
| Level 4 | 751 ms | 618 ms | 1.2x | -19% (faster) |
| Level 5 | 91 ms | 112 ms | 0.8x | - |
<!-- /GEN:progress -->

## Links

The specification, the tutorial and the readme file of every test folder. Generated from the files that git tracks, so the case of each path is exact.

<!-- GEN:links (script/relnotes.py) -->
- [Specification: conventions](../spec/README.md)
- [Specification: contents](../spec/index.md)
- [Conformance tests: format](../spec/conformance/README.md)
- [Tests: how to run them](../test/readme.md)
- [Tests: level 1](../test/level1/readme.md)
- [Tests: level 2](../test/level2/readme.md)
- [Tests: level 3](../test/level3/readme.md)
- [Tests: level 4](../test/level4/readme.md)
- [Tests: level 5](../test/level5/readme.md)
- [Tests: level 6](../test/level6/readme.md)
- [Tests: level 7](../test/level7/readme.md)
- [Tests: project](../test/project/readme.md)
- [Tests: scaffold](../test/scaffold/readme.md)
- [Tests: smoke](../test/smoke/readme.md)
- [Tutorial: topics](https://sagecode.org/projects/eve/index.html)
- [Tutorial: feature tests](https://sagecode.org/projects/eve/features.html)
- [Tutorial: smoke test and performance](https://sagecode.org/projects/eve/quality.html)
- [Tutorial: the Eve VM](https://sagecode.org/projects/eve/vm.html)
- [Performance: benchmarks and notes by version](../test/bmark/README.md)
- [Versions and features](../plan/version_map.md)
<!-- /GEN:links -->

## Layout (planned)

```
manual/
  README.md            this file
  implement.md         how to implement: architecture, milestones, spec files per milestone
  usage.md             how to use: command line, options, exit codes, diagnostics
  release/
    README.md          the release policy: stages of a feature, steps of a release, links (D-153)
    template.md        the template of the release notes
    vX.Y.Z.md          the notes of each release (generated parts + hand-written parts)
  support/
    <impl>.json        support data: spec feature id -> status (hand-edited, the input)
  features/            GENERATED from spec/ + support/, never edited by hand
    README.md          summary: supported / partial / missing per category
    keywords.md        from spec/lexical/keywords.json
    operators.md       from spec/lexical/operators.json
    delimiters.md      from spec/lexical/delimiters.json
    grammar.md         from the ebnf blocks in spec/syntax/*.md, one row per rule
    types.md           from spec/semantics/types.json
    builtins.md        from spec/library/builtins.json
  schema/
    support.schema.json
```

## Feature tables

Every table in `features/` is generated. The generator reads:

1. **Spec JSON** (`spec/**/*.json`): one row per item, using its `id`, `status` and `ref`.
2. **Spec grammar**: one row per rule defined in a fenced `ebnf` block.
3. **Support data** (`support/*.json`): the status of each feature in each implementation.

Rows are spec features, columns are implementations, so one table compares every compiler that has a support file. A generated file starts with a comment naming its generator and inputs. Running the generator with `--check` fails when a table is out of date, or when a support file names a feature id that the spec does not define.

### Feature ids

A feature id is `<source>:<id>`, so ids stay unique across files:

| Source | Example | Taken from |
|---|---|---|
| `keyword` | `keyword:driver` | `spec/lexical/keywords.json` |
| `operator` | `operator:assign` | `spec/lexical/operators.json` |
| `delimiter` | `delimiter:block-comment` | `spec/lexical/delimiters.json` |
| `rule` | `rule:statement` | `ebnf` blocks in `spec/syntax/` |
| `type` | `type:Integer` | `spec/semantics/types.json` |
| `builtin` | `builtin:print` | `spec/library/builtins.json` |

### Support data

```json
{
  "$schema": "../schema/support.schema.json",
  "implementation": "eve",
  "version": "0.1.0",
  "specVersion": "0.1-draft",
  "features": {
    "keyword:driver": { "status": "yes" },
    "rule:statement": { "status": "partial", "note": "no line continuation yet" }
  }
}
```

| Status | Meaning |
|---|---|
| `yes` | Implemented and covered by conformance tests |
| `partial` | Implemented with limits; `note` says which |
| `planned` | Scheduled for a named version |
| `no` | Not implemented. A feature missing from the file counts as `no` |
