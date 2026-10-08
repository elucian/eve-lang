# Phase 3 — Syntax

Goal: a complete, testable grammar. EBNF lives in fenced `ebnf` blocks, so a tool can extract it; the prose explains each rule with an example taken from `demo/` or `pattern/`.

### S3.1 Grammar skeleton `[x]` `grammar.md` written (levels 1 and 2), checked by S3.6 (D-115)
- `spec/syntax/grammar.md`: notation section (the EBNF dialect used), then the top rule
  `script = header { region } ;` with every nonterminal stubbed and linked to its topic file.

### S3.2 `syntax/regions.md` `[x]` retired 2026-10-08: regions are legacy (D-041, D-094 Q-004); the script structure is in `grammar.md`
Sources: `topology.html` (Scripts, Regions, Import Region, Process), `syntax.html#regions`, `pattern/declaration.eve`.
- Script headers: `driver`, `module`, `aspect` (confirm the aspect header).
- Regions: `import`, `global`/`globals`, `type`, `process`, `recover`, `return`; order, which are optional, and which may repeat.

### S3.3 `syntax/statements.md` `[x]` written, checked by S3.6 (D-115)
Source: `syntax.html#statements`, `control.html`.
- Single-line and multi-line statements, blocks and `end …` terminators, labels.
- Control statements: `if`/`else`, `case`/`when`, `repeat`/`while`/`for`/`loop`, `break`,
  `skip`, `exit`, `return`, `pass`.

### S3.4 `syntax/expressions.md` `[x]` written, checked by S3.6 (D-115)
- Precedence climbing driven by `lexical/operators.json` (no duplicate precedence table here).
- Assignment forms (`:=`, `=`, compound), the ternary, calls, member access, indexing,
  collection literals, string patterns (`"x=#n" ? (x)`).

### S3.5 `syntax/declarations.md` `[x]` written, checked by S3.6 (D-115)
Sources: `types.html`, `classes.html`, `functions.html`, `multitasking.html`.
- Variable declarations (`let`, typed forms, D-036), `type`, `class` (with `<:`), `constructor` constructors, `function`, `routine`, closures, lambdas, generics.

### S3.6 Grammar check against the examples `[x]` 2026-10-08 (D-115): `python script/grammarcheck.py`, 139/139 files of level 1 and 2; open: Q-037, and the grammar of levels 3 to 7
- Build a parser from the EBNF with `lark` (a Python library): `script/grammarcheck.py`.
- Parse every file in `test/` (`demo/` is deleted, D-099), and list the failures.
- For each failure, decide whether the grammar or the example is wrong (`decision_level1.md`, `decision_level2.md`), then fix it.
- Done when: all examples parse, or each remaining failure has a decision id.
