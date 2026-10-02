# Eve Specification

Version **0.1-draft**. License: to be decided (Q-006). Conventions: [README](README.md).

## Reading order

| Part | File | State |
|---|---|---|
| Lexical structure | [lexical/lexical.md](lexical/lexical.md) | first draft (2026-10-02); open points Q-013 to Q-016 |
| Operators | [lexical/operators.json](lexical/operators.json) | first draft; open Q-017 |
| Delimiters | [lexical/delimiters.json](lexical/delimiters.json) | first draft |
| Keywords | `lexical/keywords.json` | blocked on Q-002 (evidence collected) |
| Grammar | `syntax/grammar.md`, `regions.md`, `statements.md`, `expressions.md`, `declarations.md` | not started (phase 3) |
| Semantics | `semantics/*` | not started (phase 4) |
| Library | `library/*` | not started (phase 5) |

Check the data files with `python script/speccheck.py`.

## Sources of the rules

Every rule comes from a decision in [`../plan/decisions.md`](../plan/decisions.md) (`D-nnn`), from the tutorial
(`tutorial/`), or is marked *(proposed)* and listed as a question (`Q-nnn`). When the tutorial and this
specification disagree, this specification wins.

## Change log

| Date | Change |
|---|---|
| 2026-10-02 | Lexical structure, operators and delimiters (S2.2, S2.3, S2.5, S2.6); `speccheck.py` |
