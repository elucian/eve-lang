# Decisions, level 5: data language, database layer and the Eve database (version 0.4)

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. Ids are shared by all the decision files ([level 1](level1.md), [2](level2.md), [3](level3.md), [4](level4.md), 5, [6](level6.md), [7](level7.md)); the list of levels is in [decision_level3.md](level3.md) and [feature_map.md](../feature_map.md).

## Scope

The core of Eve as an ETL tool: a driver connects to databases by name, reads query results as streams of typed records, writes with bulk loads, upserts and merges, keeps transactions per job, restarts a failed load at its last checkpoint, and records the lineage of every run. Each machine has its own database, the Eve database, administered with `db` commands. Level 5 comes after parallel processing (level 4), which the large loads use, and before the server (level 6). Tests: `test/level5`, prefix `e`; they run against the Eve database (SQLite), so they need no database server.

Features: F-DAT-01 to F-DAT-11, F-LIB-08 (secrets of the connections), F-LIB-11 (lineage in the run log).

Design for review (2026-10-10): [design-database-core.md](../design-database-core.md), [design-database-remote.md](../design-database-remote.md) and [drivers/duckdb/README.md](../../drivers/duckdb/README.md) (the test database around DuckDB). First draft, archived with the author's answers: [design-database.md](../archive/design-database.md) (2026-10-05).

Decisions already taken in other files: D-020 (jobs and `recover`), D-080 (Decimal, optional types, DataMap), D-081 (error classes, `defer`, unsafe methods, run log), D-083 (machine folder, configuration, remote commands).

## Draft features

The design note holds the details; in short:

1. **Connections by name** from the machine configuration, passwords as secrets (`database.connect("sales")`).
2. **Queries as streams of records**: `query(:Order)("select … where x = ?", v)`, parameters never interpolated.
3. **Writes**: `execute!`, `load!` in the modes insert, upsert and merge.
4. **Transactions per job**, with `retry` of transient errors (`DatabaseError.transient`).
5. **Light mapping** between record types and tables (`TABLE`, `KEY`; `find`, `save!`, `remove!`), replacing the ORM of the old tutorial page.
6. **Checkpoints** in the Eve database, for restartable pipelines.
7. **The Eve database**: SQLite embedded in the VM (DuckDB optional), in the folder `db/` of the machine.
8. **Admin commands** `db list`, `db add`, `db remove`, `db test`, `db info`, `db tables`, `db describe`, `db sql`, `db create`, `db migrate`, `db backup`, `db restore`, `db export`, `db import`, `db compact`, `db runs`.
9. **Schema migrations** in `db/migrations/<name>/`.
10. **Drivers**: SQLite and PostgreSQL first, then MySQL, SQL Server and Oracle through ODBC.

## Open questions

Answered by the author in [design-database.md](../archive/design-database.md); the rules that follow are proposed in Q-043 for confirmation. The eight questions were: the engine of the Eve database, transactions bound to jobs, the record syntax, the extent of the mapping, the rights of `db sql`, parallel writes with their own connection, the `db` prefix of the commands, the order of the drivers.

## Data language (moved from level 3, D-125)

The features below were drafted for level 3 and moved to level 5 on 2026-10-08. They are proposals: each becomes a `D-nnn` when the author confirms it.

### Draft features

Proposals waiting for a decision. Each becomes a `D-nnn` here when the author confirms it.

1. **Keyword `generator`.** A generator is declared with its own keyword instead of being a method that contains `yield` (author's answer to review RSB-R03, not yet applied): `generator count_to(n: Integer) => (@x: Integer) is … return;`. Replaces the detection rule of D-067.
2. **Record types.** `class Order = {id: Integer, amount: Decimal} <: Record;` declares a row type; a literal with its type hint builds a record (D-080). Used by JSON, CSV and the database layer (level 5).
3. **Time types.** Instant (a point in time, UTC), DateTime with a zone, Date, Time, Duration, with parsing and formats (review RTY-R01).
4. **Bytes.** An immutable byte buffer, with views, for files and the network (review RTY-R01).
5. **Files and paths.** Modules `fs` and `path`: read and write text and bytes, lines as a stream, list a folder, glob; the `/` operator joins paths (D-031).
6. **JSON and CSV.** `json.parse` gives a DataMap (D-080), `json.decode(:T)` a record; `csv.read(:T)` a stream of records, with the header and the separator as options; both write back.
7. **HTTP client.** `http.get`, `http.post`, `http.request` with headers, a JSON body, a time-out; a status error is an `HttpError` with the field `status` (D-081).
8. **Secrets.** A `Secret` value that never prints and never travels to a log, read from the machine configuration (D-083).
9. **Shell by argument list.** `run("ls", ("-l", path), cwd: dir)` returns the exit code and the output, next to `call` (review RIO-R03).
10. **Compression.** gzip and zip readers and writers as streams.

### Open questions

- Which of the draft features belong to version 0.4, and which move later? *(proposed in Q-044)*
- The name of the time types (Instant or Timestamp; DateTime or LocalTime). *(proposed in Q-044c)*

- Q-024 The system library: names and members [open; proposals 2026-10-09]
- Q-039 Data file types: JSON, CSV, TXT, XML, HTML, HTMT [open; proposals 2026-10-09]
- Q-043 Database layer: the answers of design-database.md as rules [open; proposals]
- Q-044 Data language: features and versions [open; proposals]
- Q-045 Eve macro (hybrid script): aspects and a driver in one file (answered: D-152)
- D-152 Eve macro: a hybrid script with shared declarations, aspects and one driver
- D-156 The core database: one per project, in its `db/` folder, `$EVE_CORE_DB`
- D-157 Names of the file types: CSV, JSON, XML, HTML, HTMT, TXT; PRN and PDF are output formats
- D-158 Database layer: the answers of the author to design-database-core.md
- D-159 Remote databases: no offline work, SQLite only for logs and metadata, no tables in a target
- D-168 The answers of 2026-10-13: `$err_sql`, `null` prints `null`, `time.now!()`, Decimal and Real conversions, the rules the tests use, chunked bodies
- Q-046 Database ORM and ACID: the language proposals of the two design files [open; proposals]
Note 2026-10-10: the proposals of Q-024, Q-039, Q-043, Q-044 and Q-046 are written in the specification (`spec/library/database.md`, `spec/library/data-language.md`, `spec/semantics/data-types.md`) and taught in the tutorial (`databases.html`, `etl.html`) as proposed, still not decided. The choices made for the author are in [review_level5.md](../archive/review-2026-10-04/level5.md).


## D-162 The machine: doors, `-loc`, `-rem`, `-lsn`, `--serve` (2026-10-11)
Author decision (the options and the two doors) with the choices that settle the open details of `design/design-service.md` section 3a. The spec is `spec/library/machine.md`. (1) The machine is a singleton by `domain:ipc_port`; IPC (`-lsn`) and HTTP (`--serve`) are two doors of one VM core. (2) `-loc` never uses the network and, without a machine, runs the command in a new machine inside the process; `-rem` fails when no remote machine answers: exit 69, `eve: no remote machine at host:port`. (3) A second start fails with `already running`, exit 75. (4) `--serve start|stop|restart|status`; `start` is `--serve`; a start on a machine that runs is refused, `restart` changes the doors. (5) The messages are JSON-RPC 2.0, one per line on IPC, in `POST /rpc` on HTTP; methods `ping`, `status`, `run`, `stop`. (6) The socket is `<runtime>/eve-<domain>-<ipc_port>.sock`; on Windows a Unix socket too (no named pipe in this version). (7) The machine runs one script at a time, each in its own session; shared state and several clients are level 6. (8) A remote script is sent as text. (9) `eve.cfg` keys `domain`, `ipc_port`, `http_port`, `http_host`, `web`, `remote`. (10) Revised by the author the same day: the short options have three letters, `-lsn` (`--listen`), `-loc` (`--local`), `-rem` (`--remote`), instead of `-ls`, `-lo`, `-r`; the old names are unknown options (exit 64). `-x` alone never looks for IPC or HTTP: it executes the script at once in the process, the fast way to run a script. Tests: `test/level5/e95_web_hello` and `e95_test1` to `e95_test3`.

## D-168 The answers of 2026-10-13: `$err_sql`, `null` prints `null`, `time.now!()`, Decimal and Real conversions, the rules the tests use, chunked bodies (2026-10-13)
Author answers to the six questions left by the review of the level 5 tests (2026-10-12). (1) The error of a `sql function` is **`$err_sql`** (code 59), like every other error code, not `$sql_error`. (2) **`null` is the value, `Null` the type:** `print` writes `null`, `type(x)` of it gives `Null`; the tests e81, e82 and the VM printed `Null` until now. (3) The clock is **`time.now!()`**: it gives another value at each call (D-087); `time.now()` is refused. (4) **Decimal and Real** are converted by `d.real()` and `r.decimal()`, and implicitly by `:=` (to a variable that holds the other kind, or with a type hint); an operator between them stays a compile error (D-110). `r.decimal()` gives the Decimal of the shortest text of the Real. (5) The rules that the tests used without a spec are written in it: the scale of a Decimal division (the larger scale plus 6, at most 18, half away from zero), `%` and an Integer with a Decimal; the fraction of an Instant to the microsecond, trailing zeros cut; `fs.list!` sorted by name; a new row has the version 1. (6) The web door reads a request body sent in chunks (`Transfer-Encoding: chunked`). Spec: `library/data-language.md`, `library/database.md`, `library/machine.md`, `semantics/errors.md`. Tests: e105 (conversions), e106 (`null`), e107 (`time.now!`), e95_test4 (chunks), and e75, e81, e82, e97, e98 updated.
