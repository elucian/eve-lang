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


## Q-039 Data file types: JSON, CSV, TXT, XML, HTML, HTMT (2026-10-08; was numbered Q-038, an id taken by level 2)
Author request: types for the files that a program loads and parses in memory: HTML, XML, HTMT (HTML template), CSV, DAT (fixed width data) and JSON. The load is buffered and works in loops, a kind of traversal: row by row, or element by element (object by object) for JSON. All of them are derived with `<:` and defined mostly in Eve, at a later time. A first proposal is in `spec/semantics/data-types.md` and in the section "Data File Types" of `types.html`. Open points:
- (a) The names: `JSON`, `CSV`, `TXT`, `XML`, `HTML`, `HTMT`. `HTML` is also the safe page type of the templates (Q-027, level 7): one type, or `HTML` for the parsed file and another name for the safe page?
- (b) The common ancestor of the six classes (`Source`? `Document`?) and the traversal protocol: what a class must define so that `for unit in value do` works (an iterator, a generator?).
- (c) How a unit is read: `row["name"]`, `row.name`, `row[2]`; the type of a field (String until converted, or declared in a layout).
- (d) `TXT`: how the layout of the fixed width fields is declared (a class, a list of widths, a file).
- (e) The modules (`csv`, `json`, ...) or a single `load`; reading a stream from the network as well as a file; writing a file of these types.
- (f) Encoding and the line ending; the error when a unit is not well formed (raised when the loop reaches it).
- (g) Levels: `CSV` and `JSON` in level 5 (D-125, was level 3), `HTML` and `HTMT` with the templates (level 7, version 0.6), `XML` and `TXT` open.
**Proposed (2026-10-09), one line per point; confirm or correct each:**
- (a) One type `HTML`: a parsed document tree. A rendered template gives an `HTML` value too; text placed in it is always a text node, so it is escaped when the value is written. No second name for the safe page.
- (b) The ancestor is `Document(:U) <: (Object, Iterable(:U))`, where `U` is the unit: `CSV` and `TXT` give a `Row`, `JSON`, `XML` and `HTML` give a `Node`. The protocol is the library trait `Iterable(:U)` of level 4 (D-145): a class gives its next unit or `null` at the end; `for` reads any `Iterable`.
- (c) A `Row` reads by name and by position, `row["name"]`, `row[2]`, and the value is a `String`. Typed reading decodes into a record (Q-043c): `csv.read(:Order)(path)` gives a `Stream(:Order)` and the fields are typed, `o.amount`. `row.name` is only for records.
- (d) The layout of a `TXT` file is a record type and the widths of its fields in declaration order: `txt.read(:Line)(path, widths: (4, 10, 20))`; untyped, `txt.open(path, widths: (4, 10, 20))` gives rows read by position.
- (e) One module per format, `csv`, `json`, `txt`, `xml`, `html`, each with `open(source)` (untyped), `read(:T)(source)` (typed) and `write!(path, rows)`. The source is a path or a `Stream(:Bytes)`, such as the body of an HTTP response.
- (f) UTF-8 by default, other encodings with `encoding:`; LF and CRLF are both read, writing uses LF unless `eol: "crlf"`. A unit that is not well formed raises `FormatError` with `line` and `column`, when the loop reaches it.
- (g) `CSV`, `JSON` and `TXT` in level 5 (Version 0.4; fixed-width files are common input of ETL), `XML` in Version 0.5, `HTML` and `HTMT` with the templates in level 7 (Version 0.6).

**Answer:**

## Q-043 Database layer: the answers of design-database.md as rules (2026-10-09)
Note 2026-10-10: (c) and (d) are replaced by Q-046, the robust ORM asked by the author ([design-database-core.md](../design-database-core.md)).
The author answered the eight questions at the end of [design-database.md](../archive/design-database.md) (answers written in that file). This entry turns each answer into rules for the specification; the parts marked **Proposed** are the model's completions, to be confirmed one by one. After confirmation they become a decision and are applied to `spec/`, the tutorial (`databases.html`, `syslib.html`) and the tests of level 5.

(a) **Engine.** Author: only SQLite is embedded; DuckDB is a separate project, an independent Eve driver imported as a dependency; no engine of our own (postponed indefinitely). **Proposed:** the Eve database of a machine is one SQLite file per name in its `db/` folder, opened with `database.connect("eve")`; DuckDB is removed from F-DAT-08 and design-database.md §9 and becomes a library outside the VM (a later version, not 0.4). 

**Answer:**  

(b) **Transactions.** Author: a transaction is the hidden purpose of a job. **Proposed:** no new syntax and no `job on`. Inside a job, the first write (a `!` method) on a connection begins a transaction on it; the job commits every open transaction at `done` or `stop` and rolls them back when it fails, before `recover` runs; `retry` runs the job again in a new transaction. Outside a job every write commits by itself. There are no `begin!`, `commit!` or `rollback!` methods in version 0.4: a long load is split into several jobs, and the last job that passed is the checkpoint (`jobs["name"].status`). A transient error (`DatabaseError.transient`: lost connection, deadlock, time-out) is the case for `retry`. 

**Answer:** 

(c) **Records.** Author: a class of type `Record`, and an optional `Table` that is a buffer of records. **Proposed:** `class Order = {id: Integer, amount: Decimal} <: Record;` declares a row type (fields only, optional fields `T?`, no methods in version 0.4). `Table(:T)` is a library class: an in-memory buffer of records of one type, filled with `<+`, read by `for`, given to `load!` in batches (`Table(:Order)(capacity: 10000)`). `Table` is the buffer, never the name of a database table: the constants `TABLE` and `KEY` of design-database.md §7 are dropped (see d). 

**Answer:** 

(d) **Mapping.** Author: no complex ORM; the user writes bare SQL and handles the complexity with smart jobs. **Proposed:** version 0.4 has no mapping methods: `find`, `save!` and `remove!` (design-database.md §7) are dropped, F-DAT-11 is dropped. What remains: `query(:T)(sql, params…)` gives a `Stream(:T)` of records matched by column name, `query(sql)` gives DataMaps, `query_one(:T)` gives a `T?`, `execute!(sql, params…)` gives the number of rows, and `load!(table, rows, mode: "insert" | "upsert" | "merge", key: (…))` writes in bulk. Parameters are always separate (`?`); SQL built with placeholders `{…}` is a compile warning. 

**Answer:** 

(e) **Scripts and stored procedures.** Author: DDL is supported by scripts that Eve loads and sends to the database (install or alter a structure, disable indexes, prepare a bulk load); Eve may install stored procedures and call them through `external` functions with a signature, used in processes. **Proposed:** `sales.script!("sql/prepare.sql")` sends a SQL script file of the project (folder `sql/`) statement by statement, in the transaction of the job when the database has transactional DDL. A stored procedure is declared with `external` (D-056) and the name of the connection: `external procedure archive_orders(before: Date) in "sales";`, and the function below; the name in the database is the Eve name, or is given with `as "etl.archive_orders"`. Such a declaration is called in a process, a job or a procedure, like any input/output; a stored procedure without a result is declared as a `procedure`, one with a result as a `!` function (its result depends on the database, D-087): `external function total_sales!(region: String) => (@total: Decimal) in "sales";`. 

**Answer:** 

(f) **`db sql` rights.** **Proposed:** Eve adds no rights layer: `db sql <name> "<statement>"` and `db script <name> <file>` run with the rights of the database user of the connection in `eve.cfg`; a read-only connection is a read-only database user. 

**Answer:** 

Note 2026-10-10 on (g): point (2) below is void. It rests on the old meaning of `!` (D-081, "unsafe"); since D-089 `!` marks a stochastic function and the compiler decides thread safety, so an aspect that writes on its own connection needs no exception (design-database-core.md §6.1).

(g) **Parallel loads.** Author: no parallel pipelines inside one aspect; an aspect connects and runs its process in serial mode, a second aspect needs a second connection. The driver prepares the database with one aspect, then starts parallel groups that load independent groups of tables in hierarchy order (head tables first, then the tables that depend on them, the leaf tables last), and a closing job of the driver finalizes (reindex, enable constraints and triggers). **Proposed:** (1) a `Connection` is never passed to a started aspect or shared: each aspect connects by name; (2) exception to D-081: a `concurrent aspect` may call the `!` methods of a connection it opened itself, because it shares no state with its siblings; (3) one parallel group per level of the hierarchy, in the order written by the developer (D-140); (4) the methods `prepare!(tables)`, `activate!(tables)` and `reindex!(tables)` of `Connection` do what the commands `db prepare`, `db activate` and `db reindex` do (h). A test of level 5 shows the whole pattern with SQLite. 

**Answer:** 

(h) **Commands.** Author: the `db` prefix is welcome; `db alter`, `db create`, `db prepare` (prepare a bulk load), `db activate` (enable the constraints again), `db reindex` (rebuild the indexes). **Proposed:** the list is `db list`, `db add`, `db remove`, `db test`, `db info`, `db tables`, `db describe`, `db sql`, `db script`, `db create` (a new database, empty or from a script), `db alter` (apply a DDL script), `db prepare` (disable indexes, constraints and triggers of the named tables), `db activate` (enable constraints and triggers), `db reindex`, `db migrate`, `db backup`, `db restore`, `db export`, `db import`, `db compact`, `db runs`. 

**Answer:** 

(i) **Drivers.** Author: SQLite first, then PostgreSQL, MySQL, MariaDB, MongoDB, then others; hosted providers Supabase, Neon and Cloudflare before other clouds. **Proposed:** Version 0.4: SQLite and PostgreSQL; Supabase and Neon speak the PostgreSQL protocol, so they come with it (a test against one of them). Then MySQL and MariaDB (one driver, Version 0.5), Cloudflare D1 (SQLite over HTTP, needs the HTTP client), then MongoDB: it is not SQL, so it gets a document API of its own (`find(:T)(filter)`, `insert!`), designed when it is planned. Oracle, SQL Server and ODBC come after. F-DAT-02 and design-database.md §12 follow this order. 

**Answer:** 

## Q-044 Data language: features and versions (2026-10-09)
The draft features of the section "Data language" above and its two open questions. **Proposed** for each feature: the version, and the shape when it is not settled yet.

(a) **Generators** (feature 1). The keyword `generator` (author's answer to review RSB-R03): `generator count_to(n: Integer) => (@x: Integer) is … yield x; … return;`, replacing the detection of `yield` in a method (D-067). Version 0.4, built on the baton tasks of stage A (D-144): a generator is a task that stops at `yield` and continues at the next read, so the tree walker can run it and F-LNG-12 does not wait for the bytecode (answers the open question "Generators and the bytecode" of feature_map.md). 

**Answer:** 

(b) **Record types** (feature 2). As Q-043c. Version 0.4. 

**Answer:** 

(c) **Time types** (feature 3 and the open question of the names). `Date`, `Time` and `Duration` keep the names of the tutorial (datetime.html) and of level 4 (`30s`); `Instant` is a point in time in UTC (not Timestamp); `DateTime` is a date and a time with a zone (not LocalTime). Parsing and formats use the format codes of strings. Module `time`. Version 0.4. 

**Answer:** 

(d) **Decimal and optional types** (D-080, F-LNG-13, F-LNG-14). `Decimal` (`12.50d`) for SQL `NUMERIC` and `T?` for nullable columns are needed by the database layer: Version 0.4. 

**Answer:** 

(e) **Bytes** (feature 4). Version 0.4: files, the network and compressed streams need it. 

**Answer:** 

(f) **Files and paths** (feature 5). Version 0.4, one module `fs` that also holds the path functions (`fs.join`, `fs.name`, `fs.parent`) and the operator `/`, instead of two modules `fs` and `path` (see Q-024). 

**Answer:** 

(g) **JSON and CSV** (feature 6). Version 0.4, as the types `JSON` and `CSV` of Q-039. 

**Answer:** 

(h) **HTTP client** (feature 7). Version 0.4, the client only (`http.get`, `http.post`, `http.request`, `HttpError.status`); the server stays in Version 0.5 with the service kind. 

**Answer:** 

(i) **Secrets** (feature 8). Version 0.4: every connection with a password needs it. 

**Answer:** 

(j) **Shell by argument list** (feature 9). Version 0.4: `run(command, arguments, cwd: dir)` gives the exit code and the output; `call` stays as it is (level 3). 

**Answer:** 

(k) **Compression** (feature 10). A gzip reader in Version 0.4 (`.csv.gz` files are common input of ETL), the rest (zip, writers) in Version 0.5. 

**Answer:** 

## Q-046 Database ORM and ACID: the language proposals of the two design files (2026-10-10)
Author request (2026-10-10): a robust ORM of Eve's own, aligned with the object model; SQLite as the core database and cache; the layers local app, Eve server (ACID session manager, cache) and remote database; mapping validated against the database in debug mode, a hard stop in production; updates that write only the changed fields; rollback rules; ETL with Unicode, transfer to a remote database, and reports back to files; new control statements where ACID needs them. The design is split in [design-database-core.md](../design-database-core.md) (SQLite, mapping, tracked records, transactions, direct SQL) and [design-database-remote.md](../design-database-remote.md) (drivers, the Eve server, protocol, ETL); each ends with its own questions. This request replaces Q-043c and Q-043d (no mapping); the other points of Q-043 stay. **Proposed**, one line per point; confirm or correct each:

(a) **P1 `table` declaration**: `table customers: Customer in "sales" is key (id); generated (id); version version; column name as "cust_name"; reference f to t; read only; temporary; end customers;`, a contextual keyword; `customers` is a `Table(:Customer)` bound to the database table (core §3.2). Replaces the constants `TABLE` and `KEY`, which D-123 forbids in a class body.

**Answer:**

(b) **P2 `commit;`** inside a job: flush, commit, new transaction; a job with `commit;` keeps a checkpoint in the same database (core §8.5).

**Answer:**

(c) **P3 `rollback;`** inside a job (also `rollback if cond;`): undo, the records keep their values and are detached (D-158), the job ends with the new status `rolled back` (P8), the process continues after `done` (core §8.2).

**Answer:**

(d) **P4 `$isolation`, `$lock_timeout`, `$read_only`**, set in the declarations of a job (core §8.3).

**Answer:**

(e) **P5 `retry after <duration>;`** and `$error.attempt` (core §11).

**Answer:**

(f) **P6 fatal errors**: `retry` and `resume` are refused for `MappingError` and for a partial `CommitError`; the process aborts, exit code 4 (core §5.3, §8.6).

**Answer:**

(g) **P7 record methods**: a class derived from `Record` may declare methods; `validate` runs before every write (core §7.4). Changes Q-043c (records without methods).

**Answer:**

(h) **P9 `cached <duration>;`** clause of `table`, served by the SQLite cache of the Eve server (remote §4.2).

**Answer:**

(i) **Rules without new syntax**: tracked records with dirty fields and originals, updates of the dirty fields only, statement cache per dirty set, flush order by `reference`, records detached on rollback (D-158), optimistic `version` check, one session per connection and per process (core §6 to §8).

**Answer:**

(j) **Names by D-089** (2026-10-10): `!` marks a stochastic result, so every read of a database or a file carries it (`find!`, `where!`, `scan!`, `count!`, `query!`, `query_one!`, `checkpoint.read!`, `csv.read!`), a write without a result has none (`add`, `remove`, `flush`, `script`, `prepare`, `activate`, `reindex`, `checkpoint.write`, `csv.write`), and a write that returns counts keeps it (`execute!`, `load!`, like `Atomic.swap!`). Thread safety is decided by the compiler and does not depend on `!`. This also corrects Q-039e and Q-043d, written with the old meaning. Note: the tutorial page methods.html still teaches "a method whose name ends with `!` is an unsafe method" (D-081), which D-089 replaced.

**Answer:**
Yes, we must fix the tutorial "!" in not necesarly unsafe, is just a function that can't be optimized by memoization and has to be check if is used in parallel. So compiler must do a sofisticated lookup to mark a function trade safe but no attempt to optimize these functions. While a function witout !, could be optimizes using memoization especially if the parameters are a limited number of values: A small range or an ordinal. If the function has a large number of possible values, no memoization is possible. A special kind of memoization is possible in Eve using the SQL Light engine.

## D-162 The machine: doors, `-loc`, `-rem`, `-lsn`, `--serve` (2026-10-11)
Author decision (the options and the two doors) with the choices that settle the open details of `design/design-service.md` section 3a. The spec is `spec/library/machine.md`. (1) The machine is a singleton by `domain:ipc_port`; IPC (`-lsn`) and HTTP (`--serve`) are two doors of one VM core. (2) `-loc` never uses the network and, without a machine, runs the command in a new machine inside the process; `-rem` fails when no remote machine answers: exit 69, `eve: no remote machine at host:port`. (3) A second start fails with `already running`, exit 75. (4) `--serve start|stop|restart|status`; `start` is `--serve`; a start on a machine that runs is refused, `restart` changes the doors. (5) The messages are JSON-RPC 2.0, one per line on IPC, in `POST /rpc` on HTTP; methods `ping`, `status`, `run`, `stop`. (6) The socket is `<runtime>/eve-<domain>-<ipc_port>.sock`; on Windows a Unix socket too (no named pipe in this version). (7) The machine runs one script at a time, each in its own session; shared state and several clients are level 6. (8) A remote script is sent as text. (9) `eve.cfg` keys `domain`, `ipc_port`, `http_port`, `http_host`, `web`, `remote`. (10) Revised by the author the same day: the short options have three letters, `-lsn` (`--listen`), `-loc` (`--local`), `-rem` (`--remote`), instead of `-ls`, `-lo`, `-r`; the old names are unknown options (exit 64). `-x` alone never looks for IPC or HTTP: it executes the script at once in the process, the fast way to run a script. Tests: `test/level5/e95_web_hello` and `e95_test1` to `e95_test3`.

## D-168 The answers of 2026-10-13: `$err_sql`, `null` prints `null`, `time.now!()`, Decimal and Real conversions, the rules the tests use, chunked bodies (2026-10-13)
Author answers to the six questions left by the review of the level 5 tests (2026-10-12). (1) The error of a `sql function` is **`$err_sql`** (code 59), like every other error code, not `$sql_error`. (2) **`null` is the value, `Null` the type:** `print` writes `null`, `type(x)` of it gives `Null`; the tests e81, e82 and the VM printed `Null` until now. (3) The clock is **`time.now!()`**: it gives another value at each call (D-087); `time.now()` is refused. (4) **Decimal and Real** are converted by `d.real()` and `r.decimal()`, and implicitly by `:=` (to a variable that holds the other kind, or with a type hint); an operator between them stays a compile error (D-110). `r.decimal()` gives the Decimal of the shortest text of the Real. (5) The rules that the tests used without a spec are written in it: the scale of a Decimal division (the larger scale plus 6, at most 18, half away from zero), `%` and an Integer with a Decimal; the fraction of an Instant to the microsecond, trailing zeros cut; `fs.list!` sorted by name; a new row has the version 1. (6) The web door reads a request body sent in chunks (`Transfer-Encoding: chunked`). Spec: `library/data-language.md`, `library/database.md`, `library/machine.md`, `semantics/errors.md`. Tests: e105 (conversions), e106 (`null`), e107 (`time.now!`), e95_test4 (chunks), and e75, e81, e82, e97, e98 updated.
