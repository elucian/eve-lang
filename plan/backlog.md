# Backlog

The log is split in 7 files + This file. Ids are shared and keep counting across both (an id not found here is in the  other file); a new entry goes to the file of its topic:

- [decision_level1.md](decision_level1.md): the project (formats, repositories, licenses, the VM, tests) and the language of a single script (lexical rules, control flow, types, collections, functions, classes, errors in a driver). Matches `test/level1`.
- [decision_level2.md](decision_level2.md): programs made of several files: processes, aspects, modules and imports, libraries, multitasking and parallel aspects. Matches `test/level2`.
- Levels 3 to 7 (data, parallel, database, server, web): [decision_level3.md](decision_level3.md), [decision_level4.md](decision_level4.md), [decision_level5.md](decision_level5.md), [decision_level6.md](decision_level6.md), [decision_level7.md](decision_level7.md); the table of all levels is in decision_level3.md and [version_map.md](version_map.md).

## Next Ideas, add here:

Ideas that are not designed yet, kept out of the language until a feature needs them. Answers review point `RPJ-X04` (`review/01-project.md`): Eve is verbose, but it does not reserve words for fun. A word leaves this file only together with a decision (`D-nnn`) that gives it a meaning, an example in the tutorial, and a place in the version map.

## Reserved words without a design

From the Q-002 evidence (`plan/decision_level1.md`, 2026-10-02): 30 words of the keyword table of `syntax.html` are used in no example. Proposal: remove the words of the first two groups from the keyword table and keep them here; keep the third group reserved, because the tutorial already gives them a meaning.

| Group | Words | Origin |
|---|---|---|
| Database statements | `alter`, `analyze`, `cursor`, `delete`, `fetch`, `group`, `into`, `limit`, `offset`, `order`, `rollback`, `select`, `view`, `where` | the old SQL-like database design; the database layer (`F-DAT-01`) is a library, so these become method names, not keywords |
| Collection operations | `append`, `ascend`, `augment`, `descend`, `discard`, `item`, `pop`, `store` | list and sort operations; Eve uses operators (`<+`, `+>`, `<-`, `->`) and methods |
| Documented, not yet tested | `exit` (ends the process, D-030), `halt` (debug breakpoint, `manual/usage.md`), `xor` (operator, D-019) | keep reserved; add tests when the test suites resume |
| Other | `close`, `open`, `package`, `switch`, `trial` | files (`open`/`close` become `fs` methods), packages (`F-TLS-10`), `match` replaced `switch`, `trial` is a bee word |

## Ideas waiting for a design

- **Oracle driver (2026-10-10, D-159).** Postponed. The diagram of the database layer names Oracle; the driver interface stays open (`spec/library/database.md#drivers-and-the-server`) so that Oracle can come without a change in the core.
- **Two databases in one job (2026-10-10, D-158).** Technical debt: version 0.4 writes to one connection per job. A job that writes to two databases needs a rule for the commit of both (no two-phase commit in the open-source databases), a coordinator or an outbox table. Until then: two jobs, stage in one and move in the next.
- **PRN and PDF, output formats for reports (2026-10-10, D-157).** Todo: specify the **style** (fonts and sizes, margins, headers and footers, page numbers, columns and their alignment, the title) and the **limits** (the width of a line, the lines per page, what happens to a value longer than its field: cut, wrap or error). They are for output only, written from the same record classes and streams as `CSV`, `JSON` and `TXT` (`txt` is the plain fixed-length format, no style). Question to settle: how much of the style is the language (options of the writer, a style record) and how much is the UX (`eveux`, a print dialog, a template). A report in `HTML` or `HTMT` with a style sheet may cover part of it. Level 5 or later, no version yet.
- Inline `new` in other statements: `let a, new b := f();`, `while new x <- q do` (D-077, open).
- `then` region for the repeat loop (D-074, open).
- Data types for ETL beyond Decimal: Instant, DateTime with zone, Bytes, Uuid, Record (`RTY-D01`, version 2).
- Type conversion libraries (`RTY-D01`, version 2).
