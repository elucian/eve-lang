# Phase 5 — Library and Conformance

Goal: a conformance suite that decides objectively whether a compiler implements Eve.
`test/readme.md` already defines three levels (a01…, b01…, c01…); this phase formalizes them.

### S5.1 `library/builtins.md` + `builtins.json` `[ ]`
Source: `library.html`, `command.html`, and calls in `demo/*.eve` (`print`, `write`, `trunc`,
`round`, `floor`, `ceiling`, …).
- Per function: `name`, `params` (name, type, mode), `returns`, `errors`, `ref`.

### S5.1a Library traits `Iterable`, `Comparable`, `Printable` `[!]` → D-039
Source: D-039, `classes.html` (traits), `collections.html` (the `for` loop).
- Define each trait: required methods, provided methods, generic parameter (`Comparable(:T)`).
- `Iterable`: what the `for` loop calls; which collections adopt it. `Comparable`: which operators (`<`, `>`, `==`)
  derive from the required method. `Printable`: relation to `string()`, `print`, and the `?` template.
- Decide first: may a type adopt a trait outside its declaration (`Integer` adopting `Printable`)? Then write
  `library/traits.md` and `traits.json`, and add the matching Iterable text to `collections.html`.

### S5.2 `conformance/README.md` `[!]` → Q-005
- Levels 1–3, file naming, the `driver` per test rule, the expected-output convention.
- Test metadata header comment: `** spec: syntax/regions.md#driver, level: 1`.

### S5.3 Level 1 suite `[ ]`
- Move or copy the qualifying `demo/*.eve` files into `test/level1/` with expected output.
- One test per lexical and syntax rule from phases 2–3; list coverage in `conformance/README.md`.

### S5.4 Level 2 suite `[ ]`
- Multi-script tests: drivers with aspects and modules, imports, error recovery.

### S5.5 Level 3 skeleton `[ ]`
- Files, databases, network: define tests with fake or local resources, so they run offline.
