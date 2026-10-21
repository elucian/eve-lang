# Eve Specification

Status: **draft**. License: [CC BY-NC-SA 4.0](LICENSE). Conventions: [README](README.md).

## Reading order

The specification is written level by level. The features of each level, with their status, are in [features/](features/level1.json) (`level1.json` to `level7.json`, `all.json`); each feature has a short Markdown page in the folder of its level. A machine-readable index of every page and section is `spec.json`.

| Level | Part | File | State |
|---|---|---|---|
| 1 | Lexical structure, operators, delimiters, keywords | [lexical/lexical.md](lexical/lexical.md), [operators.json](lexical/operators.json), [delimiters.json](lexical/delimiters.json), [keywords.json](lexical/keywords.json) | written; checked by `script/speccheck.py` |
| 1 | Grammar (EBNF) | [syntax/grammar.md](syntax/grammar.md) | written; every example program parses (`script/grammarcheck.py`) |
| 1 | Declarations, statements, expressions | [declarations.md](syntax/declarations.md), [statements.md](syntax/statements.md), [expressions.md](syntax/expressions.md) | written |
| 1 | Types, control flow, errors and exit codes | [types.md](semantics/types.md), [control.md](semantics/control.md), [errors.md](semantics/errors.md) | written |
| 1 | System variables | [semantics/variables.md](semantics/variables.md) | the register; a new variable is added here first |
| 1 | Strings | [library/strings.md](library/strings.md) | written |
| 1 to 7 | Conformance | [conformance/README.md](conformance/README.md) | the levels and the form of a test |
| 2 | Aspects, `apply`, errors across `apply` | [semantics/aspects.md](semantics/aspects.md) | written |
| 3 | Modules, imports, libraries, managed modules | [semantics/modules.md](semantics/modules.md) | written |
| 3 | `Atomic(:T)` | [library/atomic.md](library/atomic.md) | written |
| 4 | Parallel groups, channels, tasks, traits, generic classes | [semantics/multitasking.md](semantics/multitasking.md), [syntax/declarations.md](syntax/declarations.md#traits-and-generic-classes) | written |
| 5 | Generic subprograms, overloading, Eve macro | [syntax/declarations.md](syntax/declarations.md#generic-subprograms-and-overloading) | written |
| 5 | Data file types, ETL | [semantics/data-types.md](semantics/data-types.md) | written |
| 5 | Data language: types, files, formats, generators | [library/data-language.md](library/data-language.md) | written |
| 5 | Data engines, the columnar table, `load` and `store` | [library/data-engines.md](library/data-engines.md) | first draft |
| 5 | Database layer: records, `table`, `commit`, stored procedures, `sql function` | [library/database.md](library/database.md) | written |
| 6 | The machine: doors, `vm.*` and `db.*`, sessions, services, the reverse proxy, ACP | [library/machine.md](library/machine.md) | written; the doors and the API are implemented |
| 6 | Standard modules in Eve and in the VM | [registry.md](library/registry.md), [os.md](library/os.md), [net.md](library/net.md), [crypto.md](library/crypto.md), [http.md](library/http.md), [route.md](library/route.md), [rpc.md](library/rpc.md), [config.md](library/config.md), [test.md](library/test.md) | written |
| 7 | Web | none yet | not started |

Check the data files with `python script/speccheck.py` and the grammar with `python script/grammarcheck.py`. The index and the links between the specification, the tests and the manual are checked by `python generator/evegen.py check`.

## Sources of the rules

Every rule is stated in these pages. A rule that the author has not confirmed is marked *(proposed)*. The tutorial is not a source: it follows this specification.

## Change log

| Date | Change |
|---|---|
| 2026-10-02 | Lexical structure, operators and delimiters; `speccheck.py` |
| 2026-10-03 | Register of system variables, `semantics/variables.md` |
| 2026-10-06 | Level 1: keywords, grammar, declarations, statements, expressions, types, control, errors, conformance; lexical rules and operator tables follow |
| 2026-10-07 | Level 2: aspects, `apply`, spreading, errors across `apply`, trace, log files; modules move to level 3 |
| 2026-10-09 | No self-calling lambdas; generic functions, procedures, methods and processes; overloading |
| 2026-10-10 | Level 5 data and database: `library/database.md`, `library/data-language.md`, `semantics/data-types.md` rewritten; `table`, `commit`, `rollback`, `retry after`, `$isolation`, `$lock_timeout`, `$read_only`, error codes 50 to 57 |
| 2026-10-10 | Eve macro: a hybrid script with shared declarations, aspects and one driver |
| 2026-10-12 | The parts of `eve` and the serving machine, the machine API `vm.*` and `db.*`, remote access through a reverse proxy, ACP (`library/machine.md`); stored procedures in `sql/` and `proc/`, `external`, `sql function` (`library/database.md`); keywords `sql` and `external` (contextual) |
| 2026-10-14 | The unified aspect: no `driver` keyword, no free script, no `#!`; kinds `exclusive`, `concurrent` and `primary`; private processes; calls between aspects, three levels, no cycle; the macro has one primary aspect |
| 2026-10-20 | Features in `features/` (one JSON file and one folder of Markdown pages per level); `spec.json`, the index of the pages and sections; the spec names no test and no document outside itself |
