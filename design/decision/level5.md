# Decisions, level 5: data language, database layer and the Eve database (version 0.4)

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. Ids are shared by all the decision files ([level 1](level1.md), [2](level2.md), [3](level3.md), [4](level4.md), 5, [6](level6.md), [7](level7.md)); the list of levels is in [decision_level3.md](level3.md) and spec/features.

## Scope

The core of Eve as an ETL tool: a driver connects to databases by name, reads query results as streams of typed records, writes with bulk loads, upserts and merges, keeps transactions per job, restarts a failed load at its last checkpoint, and records the lineage of every run. Each machine has its own database, the Eve database, administered with `db` commands. Level 5 comes after parallel processing (level 4), which the large loads use, and before the server (level 6). Tests: `test/level5`, prefix `e`; they run against the Eve database (SQLite), so they need no database server.

Features: F-DAT-01 to F-DAT-11, F-LIB-08 (secrets of the connections), F-LIB-11 (lineage in the run log).

Design for review (2026-10-10): [design-database-core.md](../design-database-core.md), [design-database-remote.md](../design-database-remote.md) and [drivers/duckdb/README.md](../../drivers/duckdb/README.md) (the test database around DuckDB). First draft, archived with the author's answers: design-database.md (2026-10-05).

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

Answered by the author in design-database.md; the rules that follow are proposed in Q-043 for confirmation. The eight questions were: the engine of the Eve database, transactions bound to jobs, the record syntax, the extent of the mapping, the rights of `db sql`, parallel writes with their own connection, the `db` prefix of the commands, the order of the drivers.

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
Note 2026-10-10: the proposals of Q-024, Q-039, Q-043, Q-044 and Q-046 are written in the specification (`spec/library/database.md`, `spec/library/data-language.md`, `spec/semantics/data-types.md`) and taught in the tutorial (`databases.html`, `etl.html`) as proposed, still not decided. The choices made for the author are in review_level5.md.


## D-162 The machine: doors, `-loc`, `-rem`, `-lsn`, `--serve` (2026-10-11)
Author decision (the options and the two doors) with the choices that settle the open details of `design/design-service.md` section 3a. The spec is `spec/library/machine.md`. (1) The machine is a singleton by `domain:ipc_port`; IPC (`-lsn`) and HTTP (`--serve`) are two doors of one VM core. (2) `-loc` never uses the network and, without a machine, runs the command in a new machine inside the process; `-rem` fails when no remote machine answers: exit 69, `eve: no remote machine at host:port`. (3) A second start fails with `already running`, exit 75. (4) `--serve start|stop|restart|status`; `start` is `--serve`; a start on a machine that runs is refused, `restart` changes the doors. (5) The messages are JSON-RPC 2.0, one per line on IPC, in `POST /rpc` on HTTP; methods `ping`, `status`, `run`, `stop`. (6) The socket is `<runtime>/eve-<domain>-<ipc_port>.sock`; on Windows a Unix socket too (no named pipe in this version). (7) The machine runs one script at a time, each in its own session; shared state and several clients are level 6. (8) A remote script is sent as text. (9) `eve.cfg` keys `domain`, `ipc_port`, `http_port`, `http_host`, `web`, `remote`. (10) Revised by the author the same day: the short options have three letters, `-lsn` (`--listen`), `-loc` (`--local`), `-rem` (`--remote`), instead of `-ls`, `-lo`, `-r`; the old names are unknown options (exit 64). `-x` alone never looks for IPC or HTTP: it executes the script at once in the process, the fast way to run a script. Tests: `test/level5/e95_web_hello` and `e95_test1` to `e95_test3`.

## D-168 The answers of 2026-10-13: `$err_sql`, `null` prints `null`, `time.now!()`, Decimal and Real conversions, the rules the tests use, chunked bodies (2026-10-13)
Author answers to the six questions left by the review of the level 5 tests (2026-10-12). (1) The error of a `sql function` is **`$err_sql`** (code 59), like every other error code, not `$sql_error`. (2) **`null` is the value, `Null` the type:** `print` writes `null`, `type(x)` of it gives `Null`; the tests e81, e82 and the VM printed `Null` until now. (3) The clock is **`time.now!()`**: it gives another value at each call (D-087); `time.now()` is refused. (4) **Decimal and Real** are converted by `d.real()` and `r.decimal()`, and implicitly by `:=` (to a variable that holds the other kind, or with a type hint); an operator between them stays a compile error (D-110). `r.decimal()` gives the Decimal of the shortest text of the Real. (5) The rules that the tests used without a spec are written in it: the scale of a Decimal division (the larger scale plus 6, at most 18, half away from zero), `%` and an Integer with a Decimal; the fraction of an Instant to the microsecond, trailing zeros cut; `fs.list!` sorted by name; a new row has the version 1. (6) The web door reads a request body sent in chunks (`Transfer-Encoding: chunked`). Spec: `library/data-language.md`, `library/database.md`, `library/machine.md`, `semantics/errors.md`. Tests: e105 (conversions), e106 (`null`), e107 (`time.now!`), e95_test4 (chunks), and e75, e81, e82, e97, e98 updated.

## Q-081 to Q-090 The types for data of step S15.50 (answered 2026-10-24 → D-221)
The plan is `design/design-data-types.md` (representation, steps D0 to D6, the rules of `T?`), the drafts of the pages are `spec/library/time.md` and `spec/library/bytes.md`. Questions, each with the proposal of the page in section 6 of the plan: Q-081 literals of `Date`, `Time` and `DateTime`; Q-082 `Duration` as a type of microseconds instead of the integer of milliseconds; Q-083 `Date` plus an integer of days; Q-084 the letters of the patterns; Q-085 the zone data built into `eve.exe`; Q-086 equality and text of a `DateTime`; Q-087 `Bytes` indexing and literal; Q-088 the versions of `Uuid`; Q-089 the rules of `T?` and the operator `??`; Q-090 the printed form of a `Duration`.
**answer**

## D-221 Answers to Q-081 to Q-090: the types for data (2026-10-24)
Author decision (2026-10-24): all the proposals of `design/design-data-types.md` section 6 are accepted. Q-081 no literal for `Date`, `Time`, `DateTime` (made by functions and `parse`); Q-082 `Duration` is a type of microseconds and `30s` is no longer an `Integer`; Q-083 `Date + Integer` is days and `Date - Date` an `Integer`; Q-084 the patterns use the letters `yyyy-MM-dd HH:mm:ss`; Q-085 **the zone data is built into the Eve machine** (`eve.exe`), from a release of the IANA database; Q-086 a `DateTime` equals another when the instants are equal, the text has the offset; Q-087 `Bytes` is indexed from 1 as a `List`, no literal; Q-088 `Uuid` v4, v7, v3, v5; Q-089 the rules of `T?` (narrowing after `<> null`, `??` for a default); Q-090 a `Duration` prints in **ISO 8601** (`PT1H30M`).
Step D0 is built the same day: the type `Duration`, the units `us ms s m h`, the operators with `Duration` and `Instant`, the functions `seconds`, `millis`, `micros`, `sleep` of `time`, `Duration.parse`; `within`, `wait`, `$timeout` and `set_timeout` take a `Duration` and the old integer of milliseconds (no warning yet: TD-73). Tests e120 to e122.
Step D1 is built (2026-10-24): `Date` (days since 1970, year 1 to 9999, proleptic Gregorian) and `Time` (microseconds of the day) with `code/evecm/src/calendar.zig`, the operators (`Date + Integer`, `Date - Date`, `Time + Duration` that wraps, `Time - Time`), the functions of the module `time` and as methods (`d.year()`, `d.add_months(1)`), `Date.parse`, `Time.parse`, the readers and writers of CSV and JSON, the SQLite parameters and columns. 220 dates checked against Python's `datetime` (e125), the whole range of 3.65 million days round-trips in a unit test, benchmark `p1g_dates` (0.4x CPython's `datetime`). Tests e123 to e126, bc22.
Step D3 is built (2026-10-24): the patterns of `spec/library/time.md#patterns`, `code/evecm/src/timefmt.zig` (compile, format, parse; no allocation), `time.format`, `time.parse`, `Date.parse(text, pattern)`, `Time.parse(text, pattern)`, `Instant.parse(text, pattern)`, the methods `d.format(...)` and the placeholders `{d % dd/MM/yyyy}`. 160 instants against Python in six patterns and 640 round trips (e128), the table of letters and the errors (e127); benchmark `p1h_time_format` (0.15x of `strftime`/`strptime`). Open: the zone letters, with D2.

## Q-091 to Q-096 The meta database: reference data in a SQLite file (answered 2026-10-24 → D-222)
From the author's idea (embedded SQLite file with countries, time zones, phone prefixes and other universal data, folder `lib/meta`). The plan, the measures (IANA 2026.5: 345 zones, 346 KB compiled, 105 KB as rules), the tables, the layout and the steps M0.1 to M0.3 are in `design/design-meta-database.md`. Questions: Q-091 direction (one embedded read-only file, the database `meta` and the modules of `lib/meta/`, an override file); Q-092 sources (IANA, CLDR, libphonenumber) and a committed generated file; Q-093 content of version 1; Q-094 compressed or not; Q-095 folders; Q-096 order (M0.1, D2, M0.2, M0.3).
**answer**

## D-222 Answers to Q-091 to Q-096: the meta database, and the `.db` files in Git LFS (2026-10-24)
Author decision (2026-10-24): all proposals of `design/design-meta-database.md` section 8 are accepted. Q-091 one embedded read-only SQLite file `meta.db`, readable as the database `meta` and through the modules of `lib/meta/`, with an optional override file; Q-092 the sources are IANA tzdata, Unicode CLDR and libphonenumber, built by a script (`tools/meta/build_meta.py`) whose output is committed; Q-093 the tables of version 1; Q-095 the folders `lib/meta/` and `tools/meta/`; Q-096 the order M0.1, D2, M0.2, M0.3. **Q-094 changed:** the data is **not compressed**: the file is kept populated, embedded as it is and opened without a copy; the size is carried by **Git LFS, for every `*.db` file** (`.gitattributes`: `*.db filter=lfs diff=lfs merge=lfs -text`, like `*.duckdb` and `*.svg`). Consequences: a clone needs `git lfs pull` before the build (the build of `eve.exe` stops with a message when `lib/meta/meta.db` is still a pointer); `ci.yml` checks out with `lfs: true`; `script/wsl-gate.py` runs `git lfs pull` and stops when git-lfs is missing; the three `.db` files that were committed before (`test/level5/e96_sql_function/test.db`, `test/project/db/empty.db`, `shop.db`) become pointers at the next `git add --renormalize .`.
Step M0.1 is built (2026-10-24): `tools/meta/build_meta.py` writes `lib/meta/meta.db` (344 KB, deterministic: the same sources give the same bytes) from the IANA release 2026e (345 zones, 253 links, 17,057 transitions, 418 country rows); the file is embedded with an anonymous import (`@embedFile("meta_db")`, a build error with a clear message when it is still an LFS pointer) and opened read only without a copy (`sqlite3_deserialize`); `code/evecm/src/zone.zig` (types, transitions, the POSIX rule of the future); the modules `zone` and `meta` of `lib/meta/`; `database.connect("meta")` as a read only SQL database. Checked against Python's `zoneinfo` (same release): 32 zones, 140 instants each, offsets and abbreviations (e130), and 240,000 random instants in 12 zones (e131). Tests e129 to e132, benchmark `p1i_zone_offsets`. Also: the module `time` and `zone` take the fast call of D-220, and the operators of Instant, Duration, Date and Time have a short path (zone loop -29%, time arithmetic -20%).
Step D2 is built (2026-10-24): the values `Zone` (an id: 0 is `Z`, a number with the top bit set is a fixed offset, any other is an entry of the registry of zones in memory) and `DateTime` (an instant and a zone, 16 bytes); `zone.resolveLocal` of `code/evecm/src/zone.zig` (one instant, two, or a gap); `time.zone`, `at_zone`, `make`, `date_of`, `time_of`, `instant_of`, `zone_of`, `offset_of`, `local_zone!`, `today!(zone)`; `DateTime.parse` (ISO, with an optional `[Region]`) and `parse` with a zone; the letters `X`, `VV`, `z`; the operators and the compile errors; the readers and writers of CSV, JSON and SQLite; `zone.offset(zone_value, ...)` without a search by name (TD-77 closed). Checked against Python's `zoneinfo`: the wall-clock text of 90 instants in 12 zones and the instant of 60 local times in each (e135, 1800 checks). Tests e133 to e137, benchmark `p1j_datetime` (0.4x of `zoneinfo`).

## D-223 The schema of the meta database: continents, countries, and a foreign key from the zone to its country (2026-10-24)
Author's correction (2026-10-24): the first schema (D-222, M0.1) was not sound: a zone pointed at a country code that no table held. Schema version 2: `continent(code, name)` with two-letter codes (`AF AN AS EU NA OC SA`); `country(code, alpha3, numeric, name, continent)` with the 249 officially assigned ISO 3166-1 codes, the names and the continents from Unicode CLDR 49.0.0 (the containment tree, Antarctica apart); `zone.country` is a foreign key to `country` (null for the names that are no place: `UTC`, `EST5EDT`, `US/Eastern`, ...); the table `zone_country` is gone (a link has a country of its own, as `zone.tab` gives one to each name). `pragma foreign_key_check` is empty, and the builder refuses a file that fails it. The sources are fetched by `build_meta.py --fetch DIR` (pinned releases: tzdata 2026.5, CLDR 49.0.0). Test `e138_meta_schema`.

## D-224 Gzip and zip are level 5 (2026-10-25)
Author decision (2026-10-25): the gzip writer and zip are level 5, as the plan of S15.51 says; the spec of `spec/library/data-language.md#compression` moves them from level 6 to level 5 and states their API as proposed until built. Built before the decision: the gzip reader and `gzip.open!` (tests e152, e154).
