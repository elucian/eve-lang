# Eve Specification

Status: **draft**. License: [CC BY-NC-SA 4.0](LICENSE) (D-078). Conventions: [README](README.md).

## Reading order

The specification is written level by level (the levels are in `design/feature_map.md`). Each page names its tests in `test/levelN/`.

| Level | Part | File | State |
|---|---|---|---|
| 1 | Lexical structure, operators, delimiters, keywords | [lexical/lexical.md](lexical/lexical.md), [operators.json](lexical/operators.json), [delimiters.json](lexical/delimiters.json), [keywords.json](lexical/keywords.json) | written; checked by `script/speccheck.py` |
| 1 | Grammar (EBNF) | [syntax/grammar.md](syntax/grammar.md) | every test file of levels 1 to 6 parses (`script/grammarcheck.py`) |
| 1 | Declarations, statements, expressions | [declarations.md](syntax/declarations.md), [statements.md](syntax/statements.md), [expressions.md](syntax/expressions.md) | written |
| 1 | Types, control flow, errors and exit codes | [types.md](semantics/types.md), [control.md](semantics/control.md), [errors.md](semantics/errors.md) | written |
| 1 | System variables | [semantics/variables.md](semantics/variables.md) | the register; a new variable is added here first (D-071); open points 1 to 6 |
| 1 | Strings | [library/strings.md](library/strings.md) | written; gaps in `backlog/library-gaps.md` (G-7) |
| 1 to 7 | Conformance | [conformance/README.md](conformance/README.md) | the test format (`/*@expect*/`) and the levels |
| 2 | Aspects, `apply`, errors across `apply` | [semantics/aspects.md](semantics/aspects.md) | written; tests b01 to b59 |
| 3 | Modules, imports, libraries, managed modules | [semantics/modules.md](semantics/modules.md) | written; tests c01 to c38 |
| 3 | `Atomic(:T)` | [library/atomic.md](library/atomic.md) | written |
| 4 | Parallel groups, channels, tasks, traits, generic classes | [semantics/multitasking.md](semantics/multitasking.md), [syntax/declarations.md](syntax/declarations.md#traits-and-generic-classes) | written; tests d01 to d40 |
| 5 | Generic subprograms, overloading, Eve macro | [syntax/declarations.md](syntax/declarations.md#generic-subprograms-and-overloading) | written; tests e01 to e22 |
| 5 | Data file types, ETL | [semantics/data-types.md](semantics/data-types.md) | written; open points of Q-039 and Q-044 |
| 5 | Data language: types, files, formats, generators | [library/data-language.md](library/data-language.md) | written; open points of Q-044 and Q-046 |
| 5 | Data engines, the columnar table, `load` and `store` | [library/data-engines.md](library/data-engines.md) | first draft (D-184) |
| 5 | Database layer: records, `table`, `commit`, stored procedures, `sql function` | [library/database.md](library/database.md) | written; open points of Q-043 and Q-046 |
| 6 | The machine: doors, `vm.*` and `db.*`, sessions, services, the reverse proxy, ACP | [library/machine.md](library/machine.md) | written; the doors and the API are implemented |
| 6 | Standard modules in Eve and in the VM | [registry.md](library/registry.md), [os.md](library/os.md), [net.md](library/net.md), [crypto.md](library/crypto.md), [http.md](library/http.md), [route.md](library/route.md), [rpc.md](library/rpc.md), [config.md](library/config.md), [test.md](library/test.md) | written (D-189); tests f01 to f15 |
| 7 | Web | none yet | not started |

Check the data files with `python script/speccheck.py` and the grammar with `python script/grammarcheck.py`.

## Sources of the rules

Every rule comes from a decision in [`../design/decision/level1.md`](../design/decision/level1.md) or [`../design/decision/level2.md`](../design/decision/level2.md) (`D-nnn`), or is marked *(proposed)* and listed as a question (`Q-nnn`). The tutorial is not a source: it follows this specification.

## Change log

| Date | Change |
|---|---|
| 2026-10-02 | Lexical structure, operators and delimiters (S2.2, S2.3, S2.5, S2.6); `speccheck.py` |
| 2026-10-03 | Register of system variables, `semantics/variables.md` (D-071) |
| 2026-10-07 | Level 2: aspects, `apply`, spreading, errors across `apply`, trace, log files (D-112, D-113); modules move to level 3 |
| 2026-10-10 | Level 5 data and database: `library/database.md`, `library/data-language.md`, `semantics/data-types.md` rewritten; `table`, `commit`, `rollback`, `retry after`, `$isolation`, `$lock_timeout`, `$read_only`, error codes 50 to 57; listed in `design/archive/review-2026-10-04/level5.md` |
| 2026-10-10 | Eve macro: a hybrid script with shared declarations, aspects and one driver (D-152); tests e16 to e22, e04 is now a macro |
| 2026-10-14 | The unified aspect: no `driver` keyword, no free script, no `#!`; kinds `exclusive`, `concurrent` and `primary`; private processes; calls between aspects, three levels, no cycle (D-179 to D-182); the macro has one primary aspect |
| 2026-10-09 | No self-calling lambdas (D-147); generic functions, procedures, methods and processes (D-148); overloading (D-149); tests e01 to e15 |
| 2026-10-12 | The parts of `eve` and the serving machine, the machine API `vm.*` and `db.*`, remote access through a reverse proxy, ACP (`library/machine.md`, D-163 to D-165); stored procedures in `sql/` and `proc/`, `external`, `sql function` (`library/database.md`, D-166); keywords `sql` and `external` (contextual) |
| 2026-10-06 | Level 1: keywords, grammar, declarations, statements, expressions, types, control, errors, conformance (D-094); lexical rules and operator tables follow D-063 to D-087 |
