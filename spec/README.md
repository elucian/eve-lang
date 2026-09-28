# Eve Language Specification

This folder holds the **normative specification** of Eve: the reference any Eve compiler or
interpreter must follow. The tutorial (`tutorial/`, published at
<https://sagecode.org/projects/eve/>) teaches the language; this specification defines it.
When the two disagree, the specification wins. Record the conflict in
[`../plan/decisions.md`](../plan/decisions.md) and fix the tutorial.

Status: **0.1-draft**, being built step by step according to [`../plan/`](../plan/README.md).

## Why Markdown + JSON

The specification is written for two readers: people (students, compiler authors) and programs
(compilers, test runners, highlighters, AI agents).

| Format | Used for | Rule |
|---|---|---|
| Markdown (`.md`) | Prose: rules, rationale, examples, grammar | One topic per file; stable `##` headings are link targets |
| JSON (`.json`) | Tables a compiler loads: keywords, operators, delimiters, types, built-ins | Data only, no prose beyond a short `summary` field |
| EBNF in Markdown | Grammar | Fenced blocks tagged `ebnf`, so a tool can extract them |

Nothing here is HTML. Every JSON file must validate against its schema in `schema/`.

## Layout (planned)

```
spec/
  README.md            this file
  index.md             table of contents, reading order, version history
  lexical/
    lexical.md         source text, encoding, line endings, comments, identifiers, literals
    keywords.json      reserved words with category and status
    operators.json     symbols, arity, precedence, associativity
    delimiters.json    comment, string and collection delimiters
  syntax/
    grammar.md         complete EBNF grammar
    regions.md         script regions: driver, module, aspect, import, global, process, ...
    statements.md
    expressions.md
    declarations.md    types, classes, functions, routines
  semantics/
    types.md, types.json
    scopes.md          names, sigils, globals, system variables
    topology.md        projects, scripts, drivers, aspects, modules, execution
    control.md         control flow, errors, recovery
    concurrency.md
  library/
    builtins.md, builtins.json
  conformance/
    README.md          test levels, file conventions, expected-output format
  schema/
    *.schema.json      JSON Schemas for the data files
```

Files appear here as the plan steps complete; a missing file means that step is still open.

## JSON conventions

- Top-level object: `{ "$schema": "...", "specVersion": "0.1-draft", "items": [ ... ] }`.
- Every item has a stable `id` (never reused), a `status` (`stable`, `draft`, `reserved`,
  `deprecated`) and a `ref` to the Markdown section that defines it (`"syntax/regions.md#driver"`).
- Optional `tutorial` holds the URL of the tutorial section that teaches the item.
- Keys are `camelCase`. Arrays are sorted by `id` unless order carries meaning (precedence).

Example (`lexical/keywords.json`):

```json
{
  "$schema": "../schema/keywords.schema.json",
  "specVersion": "0.1-draft",
  "items": [
    {
      "id": "driver",
      "category": "region",
      "status": "stable",
      "ref": "syntax/regions.md#driver",
      "tutorial": "https://sagecode.org/projects/eve/topology.html#drivers"
    }
  ]
}
```

## Versioning

The specification uses `MAJOR.MINOR` plus an optional `-draft` suffix. A compiler states the
version it implements (for example "Eve 0.1") and the conformance level it passes
(see `conformance/`). Items keep their `id` across versions; removals go through `deprecated`.
