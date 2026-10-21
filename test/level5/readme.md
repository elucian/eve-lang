# test Level 5

This level tests level 5, version 0.0.5 (D-167; the feature map still calls it "Version 0.4" until its headings are renumbered): the generic subprograms and the overloading (D-147 to D-149), the Eve macro (D-152), the generators, then the data language and the database layer: data files, `Decimal`, `Instant`, `Secret`, connections, the ORM, transactions, checkpoints, the stored procedures and the SQL functions written in Eve (D-166), the commands `project init` and `project new`, and the first step of the machine (its IPC and HTTP doors and the machine API, D-162, D-165). The database tests run against **application SQLite files** of each test (`eve.cfg` declares the connection, `db/` holds the file); the core database of the project (`db/local.db`, D-156) is used only by the checkpoints. The staging database is a DuckDB database (D-159); until the VM loads DuckDB on demand (D-166), e92 uses a SQLite file in its place.

**Single files and folders.** A test of the language alone is a single file; a test that needs aspects is an **Eve macro** (D-152), so it stays one file. A test is a folder (D-073) when it needs files next to it: a project (`asp/`, `lib/`, `proc/`, search paths), data files (`out/`, `data/`), a database (`eve.cfg`, `db/`, `sql/`) or the client of a machine (`check/`, `web/`). About half of the tests are folders. The expectations are in the `/*@expect*/` block at the end of the main file; a folder may hold variations `eNN_testK.eve` with their own block (e95, e102). Test names start with `e`.

**Keys of the expectations used here** (`spec/conformance/README.md`): `stdout`, `contains`, `syntax_error` for the compile errors; `files` (content, line endings ignored) and `bytes` (exact bytes: CRLF, a BOM, trailing spaces; e37, e80, e82); `command` to run a command of `eve` with no script (e54, e55, e102_test1, e95); `client` for a program that drives a running machine (e95_test1 to e95_test4, Node.js 18 or later).

| Tests | Part |
|---|---|
| e01 to e15, e57 to e60 | generic functions, procedures, methods and processes; overloading; extension methods |
| e16 to e22, e61 to e65 | the Eve macro |
| e23 to e26, e66 to e72, e104 | generators: `for`, `next()`/`value`/`done`/`close()`, laziness, errors, `yield` outside a generator |
| e27 to e30, e73 to e79, e103, e105 to e107 | `Decimal` (exact, never mixed with `Real` by an operator: a compile error; converted by `d.real()`, `r.decimal()` and `:=`), `Instant` and `time.now!()`, `Secret` (prints `***`, never joined to a text), optional fields and `null` |
| e31 to e38, e80 to e86 | data files: `fs`, CSV, JSON Lines and arrays, TXT, NFC, encodings, rejects, the methods of a stream (the protocol of a generator) |
| e39 to e45 | compile errors of the database declarations |
| e46 to e53, e87 to e94 | the ORM on SQLite: dirty fields, optimistic locking and `retry`, `rollback;`, `update` blocks, `validate`, the mapping version, `commit;` and checkpoints, reads, writes, reference order, `load!`, temporary tables, work outside a job |
| e54, e55 | the commands `project init` and `project new` (F-TLS-23) |
| e56 | a local ETL: CSV to SQLite to JSON (its own `readme.md`) |
| e95 | the machine: IPC and HTTP doors, `--listen`, `--serve` and their words, `-loc`, `-rem`, the machine API `vm.*` with the first names, `eve ux start`/`stop` (D-162, D-163, D-165) |
| e96 to e102 | `sql function` (registration, errors and `$err_sql`, NULL only for nullable types, compile rules), Eve stored procedures in `proc/`, `eve db proc list` (D-166) |

Not written yet, because they need a running server, DuckDB in the VM or more of the design: the HTTP client, `os.run`, gzip, DuckDB staging and `prepare`/`activate`, `external` procedures (they need a database with stored procedures), the Eve server (level 6), `retry after`, `BatchError`, `$isolation`, XML, PRN and PDF.

## Tests

The tests and the result of the last run are in `level5.json` of this folder (written by the test runner after every run).
