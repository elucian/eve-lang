# Eve Specification

Version **0.1-draft**. License: [CC BY-NC-SA 4.0](LICENSE) (D-078). Conventions: [README](README.md).

## Reading order

| Part | File | State |
|---|---|---|
| Lexical structure | [lexical/lexical.md](lexical/lexical.md) | first draft (2026-10-02); Q-013 to Q-016 and Q-018 answered (D-095 to D-097) |
| Operators | [lexical/operators.json](lexical/operators.json) | first draft; Q-017 answered (D-107) |
| Delimiters | [lexical/delimiters.json](lexical/delimiters.json) | first draft |
| Keywords | [lexical/keywords.json](lexical/keywords.json) | 70 words, level 1 (D-094) |
| Grammar | [syntax/grammar.md](syntax/grammar.md) | EBNF of level 1, first draft (2026-10-06) |
| Declarations, statements, expressions | [declarations.md](syntax/declarations.md), [statements.md](syntax/statements.md), [expressions.md](syntax/expressions.md) | level 1, first draft |
| System variables | [semantics/variables.md](semantics/variables.md) | register, grows with each new variable (D-071); open points 1 to 6 |
| Types | [semantics/types.md](semantics/types.md) | level 1, first draft |
| Control flow, errors | [semantics/control.md](semantics/control.md), [semantics/errors.md](semantics/errors.md) | level 1, first draft; open points marked *(proposed)* |
| Conformance | [conformance/README.md](conformance/README.md) | test format (`/*@expect*/`), levels, coverage of level 1 |
| Aspects | [semantics/aspects.md](semantics/aspects.md) | level 2, first draft (2026-10-07); open points 1 to 4 |
| Modules and libraries | [semantics/modules.md](semantics/modules.md) | level 3, first draft (2026-10-08); tests c01 to c28; open points 1 to 4 |
| Data file types | [semantics/data-types.md](semantics/data-types.md) | level 3, proposal (2026-10-08): `Json`, `Csv`, `Dat`, `Xml`, `Html`, `Htmlt`; Q-038 |
| Standard library | [library/atomic.md](library/atomic.md) | `Atomic(:T)`, first draft (2026-10-08); the rest of the library is not started |
| Other semantics | `semantics/*` | levels 3 to 7 not started |
| Library | `library/*` | not started (phase 5) |

Check the data files with `python script/speccheck.py`.

## Sources of the rules

Every rule comes from a decision in [`../plan/decision_level1.md`](../plan/decision_level1.md) or [`../plan/decision_level2.md`](../plan/decision_level2.md) (`D-nnn`), or is marked *(proposed)* and listed as a question (`Q-nnn`). The tutorial is not a source: it follows this specification.

## Change log

| Date | Change |
|---|---|
| 2026-10-02 | Lexical structure, operators and delimiters (S2.2, S2.3, S2.5, S2.6); `speccheck.py` |
| 2026-10-03 | Register of system variables, `semantics/variables.md` (D-071) |
| 2026-10-07 | Level 2: aspects, `apply`, spreading, errors across `apply`, trace, log files (D-112, D-113); modules move to level 3 |
| 2026-10-06 | Level 1: keywords, grammar, declarations, statements, expressions, types, control, errors, conformance (D-094); lexical rules and operator tables follow D-063 to D-087 |
