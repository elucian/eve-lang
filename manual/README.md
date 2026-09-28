# Eve Compiler Manual

This folder is the **manual of an Eve implementation**: how the compiler is built, how to use
it, and which parts of the specification it supports. It replaces the old `docs/` skeleton
(decision D-004 in [`../plan/decisions.md`](../plan/decisions.md)).

| Source | Role | Format |
|---|---|---|
| `tutorial/` | Teaches the language | HTML (scl repo) |
| [`spec/`](../spec/README.md) | Defines the language (normative) | Markdown, EBNF, JSON |
| `manual/` | Documents one implementation of the spec | Markdown, with generated tables |

The manual never restates a language rule. It links to the spec section that defines the rule
and says how the implementation handles it. Other Eve compilers can copy this folder's layout
and generator for their own manual (D-003: many compilers, one specification).

Status: **skeleton**. The first Eve implementation is a **virtual machine written in Zig** that
runs Eve source as a scripting language (D-006). Its source is in `evevm/`, and the build
produces `bin/eve.exe`, the official Eve implementation (D-007). It is being built now, and this
manual is written alongside it (D-005). There is no compiler yet. Steps are in
[`../plan/phase-7-manual.md`](../plan/phase-7-manual.md).

## Layout (planned)

```
manual/
  README.md            this file
  implement.md         how to implement: architecture, milestones, spec files per milestone
  usage.md             how to use: command line, options, exit codes, diagnostics
  implemented.md       what was implemented: release notes per version
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

Rows are spec features, columns are implementations, so one table compares every compiler that
has a support file. A generated file starts with a comment naming its generator and inputs.
Running the generator with `--check` fails when a table is out of date, or when a support file
names a feature id that the spec does not define.

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
