# Decisions, level 5: data language, database layer and the Eve database (version 0.4)

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. Ids are shared by all the decision files ([level 1](decision_level1.md), [2](decision_level2.md), [3](decision_level3.md), [4](decision_level4.md), 5, [6](decision_level6.md), [7](decision_level7.md)); the list of levels is in [decision_level3.md](decision_level3.md) and [version_map.md](version_map.md).

## Scope

The core of Eve as an ETL tool: a driver connects to databases by name, reads query results as streams of typed records, writes with bulk loads, upserts and merges, keeps transactions per job, restarts a failed load at its last checkpoint, and records the lineage of every run. Each machine has its own database, the Eve database, administered with `db` commands. Level 5 comes after parallel processing (level 4), which the large loads use, and before the server (level 6). Tests: `test/level5`, prefix `e`; they run against the Eve database (SQLite), so they need no database server.

Features: F-DAT-01 to F-DAT-11, F-LIB-08 (secrets of the connections), F-LIB-11 (lineage in the run log).

Design for review: [design-database.md](design-database.md) (2026-10-05).

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

Answered by the author in [design-database.md](design-database.md); the rules that follow are proposed in Q-043 for confirmation. The eight questions were: the engine of the Eve database, transactions bound to jobs, the record syntax, the extent of the mapping, the rights of `db sql`, parallel writes with their own connection, the `db` prefix of the commands, the order of the drivers.

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
- Q-039 Data file types: Json, Csv, Dat, Xml, Html, Htmlt [open; proposals 2026-10-09]
- Q-043 Database layer: the answers of design-database.md as rules [open; proposals]
- Q-044 Data language: features and versions [open; proposals]
## Q-039 Data file types: Json, Csv, Dat, Xml, Html, Htmlt (2026-10-08; was numbered Q-038, an id taken by level 2)
Author request: types for the files that a program loads and parses in memory: HTML, XML, HTMLT (HTML template), CSV, DAT (fixed width data) and JSON. The load is buffered and works in loops, a kind of traversal: row by row, or element by element (object by object) for JSON. All of them are derived with `<:` and defined mostly in Eve, at a later time. A first proposal is in `spec/semantics/data-types.md` and in the section "Data File Types" of `types.html`. Open points:
- (a) The names: `Json`, `Csv`, `Dat`, `Xml`, `Html`, `Htmlt`. `Html` is also the safe page type of the templates (Q-027, level 7): one type, or `Html` for the parsed file and another name for the safe page?
- (b) The common ancestor of the six classes (`Source`? `Document`?) and the traversal protocol: what a class must define so that `for unit in value do` works (an iterator, a generator?).
- (c) How a unit is read: `row["name"]`, `row.name`, `row[2]`; the type of a field (String until converted, or declared in a layout).
- (d) `Dat`: how the layout of the fixed width fields is declared (a class, a list of widths, a file).
- (e) The modules (`csv`, `json`, ...) or a single `load`; reading a stream from the network as well as a file; writing a file of these types.
- (f) Encoding and the line ending; the error when a unit is not well formed (raised when the loop reaches it).
- (g) Levels: `Csv` and `Json` in level 5 (D-125, was level 3), `Html` and `Htmlt` with the templates (level 7, version 0.6), `Xml` and `Dat` open.
**Proposed (2026-10-09), one line per point; confirm or correct each:**
- (a) One type `Html`: a parsed document tree. A rendered template gives an `Html` value too; text placed in it is always a text node, so it is escaped when the value is written. No second name for the safe page.
- (b) The ancestor is `Document(:U) <: (Object, Iterable(:U))`, where `U` is the unit: `Csv` and `Dat` give a `Row`, `Json`, `Xml` and `Html` give a `Node`. The protocol is the library trait `Iterable(:U)` of level 4 (D-145): a class gives its next unit or `null` at the end; `for` reads any `Iterable`.
- (c) A `Row` reads by name and by position, `row["name"]`, `row[2]`, and the value is a `String`. Typed reading decodes into a record (Q-043c): `csv.read(:Order)(path)` gives a `Stream(:Order)` and the fields are typed, `o.amount`. `row.name` is only for records.
- (d) The layout of a `Dat` file is a record type and the widths of its fields in declaration order: `dat.read(:Line)(path, widths: (4, 10, 20))`; untyped, `dat.open(path, widths: (4, 10, 20))` gives rows read by position.
- (e) One module per format, `csv`, `json`, `dat`, `xml`, `html`, each with `open(source)` (untyped), `read(:T)(source)` (typed) and `write!(path, rows)`. The source is a path or a `Stream(:Bytes)`, such as the body of an HTTP response.
- (f) UTF-8 by default, other encodings with `encoding:`; LF and CRLF are both read, writing uses LF unless `eol: "crlf"`. A unit that is not well formed raises `FormatError` with `line` and `column`, when the loop reaches it.
- (g) `Csv`, `Json` and `Dat` in level 5 (Version 0.4; fixed-width files are common input of ETL), `Xml` in Version 0.5, `Html` and `Htmlt` with the templates in level 7 (Version 0.6).
**Answer:**

## Q-024 The system library: names and members (2026-10-06)
Moved from level 3 on 2026-10-08: the modules it names (`fs`, `path`, `time`, `secret`, `http`, `database`) are the data language and the database layer of level 5 (D-125); `task` goes to version 0.4 too (D-144).
The page `syslib.html` lists the modules that connect a program to the machine: `io`, `exception`, `fs`, `path`, `time`, `secret`, `task`, `database`, `http`, with their level and status; only `io` and `exception` are drafted (`evevm/lib/`). Are these the names and the split you want (for example one `fs` and `path`, or one `file` module)? Is the shell `call` part of the system library or of the language? Which module holds the time types (`time`), given that Date and Time have their own page?
**Proposed (2026-10-09), one line per point; confirm or correct each:**
- (a) Modules: `io`, `exception`, `fs` (files, folders and paths in one module, Q-044f), `time` (`Instant`, `DateTime`, the clock, formats; `Date`, `Time` and `Duration` are built-in types), `secret`, `database`, `http` (client in Version 0.4), `csv`, `json`, `dat` (Q-039e), `os` (`run` by argument list, environment). `task` stays planned with the generators (D-144).
- (b) `call` stays a statement of the language (level 3); `os.run` is the safe form for programs that build arguments.
- (c) The time types live in the module `time`; the page Date and Time (datetime.html) teaches them, syslib.html points to it.
**Answer:**

## Q-043 Database layer: the answers of design-database.md as rules (2026-10-09)
The author answered the eight questions at the end of [design-database.md](design-database.md) (answers written in that file). This entry turns each answer into rules for the specification; the parts marked **Proposed** are the model's completions, to be confirmed one by one. After confirmation they become a decision and are applied to `spec/`, the tutorial (`databases.html`, `syslib.html`) and the tests of level 5.
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
(g) **Parallel loads.** Author: no parallel pipelines inside one aspect; an aspect connects and runs its process in serial mode, a second aspect needs a second connection. The driver prepares the database with one aspect, then starts parallel groups that load independent groups of tables in hierarchy order (head tables first, then the tables that depend on them, the leaf tables last), and a closing job of the driver finalizes (reindex, enable constraints and triggers). **Proposed:** (1) a `Connection` is never passed to a started aspect or shared: each aspect connects by name; (2) exception to D-081: a `concurrent aspect` may call the `!` methods of a connection it opened itself, because it shares no state with its siblings; (3) one parallel group per level of the hierarchy, in the order written by the developer (D-140); (4) the methods `prepare!(tables)`, `activate!(tables)` and `reindex!(tables)` of `Connection` do what the commands `db prepare`, `db activate` and `db reindex` do (h). A test of level 5 shows the whole pattern with SQLite. 
**Answer:** 
(h) **Commands.** Author: the `db` prefix is welcome; `db alter`, `db create`, `db prepare` (prepare a bulk load), `db activate` (enable the constraints again), `db reindex` (rebuild the indexes). **Proposed:** the list is `db list`, `db add`, `db remove`, `db test`, `db info`, `db tables`, `db describe`, `db sql`, `db script`, `db create` (a new database, empty or from a script), `db alter` (apply a DDL script), `db prepare` (disable indexes, constraints and triggers of the named tables), `db activate` (enable constraints and triggers), `db reindex`, `db migrate`, `db backup`, `db restore`, `db export`, `db import`, `db compact`, `db runs`. 
**Answer:** 
(i) **Drivers.** Author: SQLite first, then PostgreSQL, MySQL, MariaDB, MongoDB, then others; hosted providers Supabase, Neon and Cloudflare before other clouds. **Proposed:** Version 0.4: SQLite and PostgreSQL; Supabase and Neon speak the PostgreSQL protocol, so they come with it (a test against one of them). Then MySQL and MariaDB (one driver, Version 0.5), Cloudflare D1 (SQLite over HTTP, needs the HTTP client), then MongoDB: it is not SQL, so it gets a document API of its own (`find(:T)(filter)`, `insert!`), designed when it is planned. Oracle, SQL Server and ODBC come after. F-DAT-02 and design-database.md §12 follow this order. 
**Answer:** 

## Q-044 Data language: features and versions (2026-10-09)
The draft features of the section "Data language" above and its two open questions. **Proposed** for each feature: the version, and the shape when it is not settled yet.
(a) **Generators** (feature 1). The keyword `generator` (author's answer to review RSB-R03): `generator count_to(n: Integer) => (@x: Integer) is … yield x; … return;`, replacing the detection of `yield` in a method (D-067). Version 0.4, built on the baton tasks of stage A (D-144): a generator is a task that stops at `yield` and continues at the next read, so the tree walker can run it and F-LNG-12 does not wait for the bytecode (answers the open question "Generators and the bytecode" of version_map.md). 
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
(g) **JSON and CSV** (feature 6). Version 0.4, as the types `Json` and `Csv` of Q-039. 
**Answer:** 
(h) **HTTP client** (feature 7). Version 0.4, the client only (`http.get`, `http.post`, `http.request`, `HttpError.status`); the server stays in Version 0.5 with the service kind. 
**Answer:** 
(i) **Secrets** (feature 8). Version 0.4: every connection with a password needs it. 
**Answer:** 
(j) **Shell by argument list** (feature 9). Version 0.4: `run(command, arguments, cwd: dir)` gives the exit code and the output; `call` stays as it is (level 3). 
**Answer:** 
(k) **Compression** (feature 10). A gzip reader in Version 0.4 (`.csv.gz` files are common input of ETL), the rest (zip, writers) in Version 0.5. 
**Answer:** 
