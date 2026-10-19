# Focus: level 5 (Version 0.4, data and database)

Status 2026-10-10. Level 5 has two parts. Part 1 is ready to implement; part 2 waits for the answers to the open questions below. Answer on the `**Answer:**` lines of each question; a confirmed question becomes a `D-nnn` in [decision_level5.md](../decision/level5.md).

## Part 1: generics, overloading, macros (ready)

Settled: D-147 to D-149 (generic subprograms and overloading, [declarations.md](../../spec/syntax/declarations.md#generic-subprograms-and-overloading)) and D-152 (Eve macro). Tests e01 to e22 in [test/level5](../../test/level5/readme.md): 0 of 22 pass, no open question blocks them. The next step is the VM (`comp/evevm/`).

## Part 2: data language and database layer (blocked by answers)

Suggested order of answering: each question builds on the one above it.

| # | Question | What it decides | Points |
|---|---|---|---|
| 1 | [Q-044 Data language: features and versions](../decision/level5.md#q-044-data-language-features-and-versions-2026-10-09) | Version and shape of generators, record types, time types, Decimal and `T?`, Bytes, files and paths, JSON and CSV, HTTP client, secrets, shell, compression | (a) to (k) |
| 2 | [Q-039 Data file types](../decision/level5.md#q-039-data-file-types-json-csv-txt-xml-html-htmt-2026-10-08-was-numbered-q-038-an-id-taken-by-level-2) | `JSON`, `CSV`, `TXT`, `XML`, `HTML`, `HTMT`: names, the `Iterable` protocol, reading a row, modules, encoding, errors | (a) to (g) |
| 3 | [Q-046 Database ORM and ACID](../decision/level5.md#q-046-database-orm-and-acid-the-language-proposals-of-the-two-design-files-2026-10-10) | `table` declaration, `commit;`, `rollback;`, `$isolation`, `retry after`, fatal errors, record methods, `cached`, naming by D-089 | (a) to (j) |
| 4 | [Q-043 Database layer: rules](../decision/level5.md#q-043-database-layer-the-answers-of-design-databasemd-as-rules-2026-10-09) | Eve database engine, transactions, records, checkpoints, admin commands; (c) and (d) are replaced by Q-046 | (a) to (h) |
| 5 | [Q-024 The system library](../decision/level5.md#q-024-the-system-library-names-and-members-2026-10-06) | Names and members of the standard modules that the points above use | |

Answered and not blocking: [Q-045 Eve macro](../decision/level5.md#q-045-eve-macro-hybrid-script-aspects-and-a-driver-in-one-file-2026-10-10) (D-152).

## Design files behind the questions

- [design-database-core.md](../design-database-core.md): SQLite, mapping, tracked records, transactions, direct SQL; ends with its own questions.
- [design-database-remote.md](../design-database-remote.md): drivers, the Eve server, protocol, ETL; ends with its own questions.
- [comp/evedb/README.md](../../comp/evedb/README.md): the test database around DuckDB.
- [design-database.md](design-database.md): first draft with the author's answers (2026-10-05).
- Features: F-DAT-01 to F-DAT-12 in [version_map.md](../version_map.md).

## Not blocking level 5

These belong to later levels: [Q-028 Networking](../decision/level6.md) (level 6), [Q-027 Templates](../decision/level7.md), Q-047 and Q-048 (eveux, level 7).
