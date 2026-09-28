# Phase 2 — Specification Foundation

Goal: the spec skeleton, validated JSON data, and the lexical layer (everything a lexer needs).
Conventions are in `spec/README.md`.

### S2.1 Spec index and front matter `[!]` → Q-001, Q-006
- Create `spec/index.md`: reading order, version (`0.1-draft`), license, change log.
- Resolve `docs/` according to Q-001.

### S2.2 JSON schemas and validator `[ ]`
- `spec/schema/keywords.schema.json`, `operators.schema.json`, `delimiters.schema.json`,
  `types.schema.json`, `builtins.schema.json`.
- `.claude/scripts/speccheck.py`:
  - every JSON validates (a stdlib-only check of required keys and types is enough);
  - ids are unique;
  - every `ref` points to an existing `##`/`###` heading anchor in `spec/`;
  - every `tutorial` URL points to an existing `id` in `tutorial/*.html`.
- Done when: `python .claude/scripts/speccheck.py` exits 0 on the skeleton.

### S2.3 `lexical/lexical.md` `[ ]`
Sources: `syntax.html` (Syntax Elements, Punctuation, Delimiters), `demo/comment_demo.eve`,
`demo/unicode_text.eve`, `demo/numeric_literals.eve`, `demo/text_literal.eve`.
Sections:
- Source text: UTF-8, CRLF/LF both valid, tab handling.
- Comments: `#` line, `**` title line, `--` end-of-line, `/* … */` block, `+--- … ---+` box.
  Define exactly where each may start, and how `--` differs from the `-` operator.
- Identifiers, sigils (`@`, `$`), case rules.
- Literals: integer, real, rational forms, strings (all quote kinds), symbols, collections.
- Tokens and whitespace, statement terminator `;`, line continuation.

### S2.4 `lexical/keywords.json` `[!]` → Q-002
- Extract candidates with a script: the tutorial table, plus words at statement start in
  `demo/`, `pattern/` and `test/`.
- Classify each: `region`, `declaration`, `statement`, `operator`, `modifier`, `reserved`.
- Record conflicts in Q-002; after the answer, write the JSON (`status` per word).

### S2.5 `lexical/operators.json` `[ ]`
Source: `syntax.html` (Operators, Numeric/Relation/Modifier/Logical operators, Table of truth).
- Per operator: `symbol`, `name`, `arity`, `precedence` (integer, higher binds tighter),
  `associativity`, `operandTypes`, `resultType`, `ref`.
- Include composite symbols (`:=`, `+=`, `=>`, `<:`, …) and word operators (`and`, `or`, `not`,
  `is`, `in`).
- Done when: every operator used in `demo/*.eve` appears in the file.

### S2.6 `lexical/delimiters.json` `[ ]`
- Comment, string, collection and grouping delimiters, with nesting rules and escape sequences.
