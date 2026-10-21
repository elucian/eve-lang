# Eve Language Specification

This folder holds the **normative specification** of Eve: the reference any Eve compiler or interpreter must follow. This specification is self-contained: it needs nothing outside this folder to be understood or implemented. The tutorial (published at <https://sagecode.org/projects/eve/>) is a separate, non-normative teaching text; it teaches the language, this specification defines it. When the two disagree, the specification wins and the tutorial is fixed.

License: [CC BY-NC-SA 4.0](LICENSE). Status: **draft**.

## Why Markdown + JSON

The specification is written for two readers: people (students, compiler authors) and programs (compilers, test runners, highlighters, AI agents).

| Format | Used for | Rule |
|---|---|---|
| Markdown (`.md`) | Prose: rules, rationale, examples, grammar | One topic per file; stable `##` headings are link targets |
| JSON (`.json`) | Tables a compiler loads: keywords, operators, delimiters; the features of each level; the index | Data only, no prose beyond a short `summary` field |
| EBNF in Markdown | Grammar | Fenced blocks tagged `ebnf`, so a tool can extract them |

Nothing here is HTML. Every JSON file must validate against its schema in `schema/`.

## Layout

```
spec/
  README.md            this file
  index.md             table of contents, reading order, change log
  spec.json            index of every page: title, status, size, sections with their line (generated)
  lexical/             lexical.md, keywords.json, operators.json, delimiters.json
  syntax/              grammar.md, declarations.md, statements.md, expressions.md
  semantics/           types, data-types, variables, control, errors, aspects, modules, multitasking
  library/             the standard library and the machine: one page per module
  conformance/         README.md: the levels and the form of a test
  features/            level1.json .. level7.json, all.json, and a folder per file with one page per feature
  schema/              JSON Schemas of the data files
```

A **feature** is a unit of the language or of the tools that has a stable code `F-<area>-<nn>`. `features/levelN.json` lists the features of level N with their `status` (`done`, `partial`, `open`, `dropped`), a one-line `summary`, the `doc` page that describes the feature (`features/levelN/F-XXX-nn.md`) and the `spec` pages and anchors that define it. Whether a feature is tested is not written here: a test names the features it checks.

The specification refers to nothing outside this folder: no tests, no plans, no decision records. Programs find a rule by reading `spec.json` first (it gives the line of every section, so a section can be read alone) and then the page.

## JSON conventions

- Top-level object: `{ "$schema": "...", "specVersion": "0.1-draft", "items": [ ... ] }`.
- Every item has a stable `id` (never reused), a `status` (`stable`, `draft`, `reserved`,
  `deprecated`) and a `ref` to the Markdown section that defines it (`"syntax/regions.md#driver"`).
- Optional `tutorial` holds the URL of a tutorial section that teaches the item. It is a courtesy link, not part of the definition: ignore it when you implement the item.
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

The specification uses `MAJOR.MINOR` plus an optional `-draft` suffix. A compiler states the version it implements (for example "Eve 0.1") and the conformance level it passes (see `conformance/`). Items keep their `id` across versions; removals go through `deprecated`.
