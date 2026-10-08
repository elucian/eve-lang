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

The eight questions at the end of [design-database.md](design-database.md): the engine of the Eve database, transactions bound to jobs, the record syntax, the extent of the mapping, the rights of `db sql`, parallel writes with their own connection, the `db` prefix of the commands, the order of the drivers.

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

- Which of the draft features belong to version 0.2, and which move later?
- The name of the time types (Instant or Timestamp; DateTime or LocalTime).

### Q-038 Data file types: Json, Csv, Dat, Xml, Html, Htmlt (2026-10-08)
Author request: types for the files that a program loads and parses in memory: HTML, XML, HTMLT (HTML template), CSV, DAT (fixed width data) and JSON. The load is buffered and works in loops, a kind of traversal: row by row, or element by element (object by object) for JSON. All of them are derived with `<:` and defined mostly in Eve, at a later time. A first proposal is in `spec/semantics/data-types.md` and in the section "Data File Types" of `types.html`. Open points:
- (a) The names: `Json`, `Csv`, `Dat`, `Xml`, `Html`, `Htmlt`. `Html` is also the safe page type of the templates (Q-027): one type, or `Html` for the parsed file and another name for the safe page?
- (b) The common ancestor of the six classes (`Source`? `Document`?) and the traversal protocol: what a class must define so that `for unit in value do` works (an iterator, a generator?).
- (c) How a unit is read: `row["name"]`, `row.name`, `row[2]`; the type of a field (String until converted, or declared in a layout).
- (d) `Dat`: how the layout of the fixed width fields is declared (a class, a list of widths, a file).
- (e) The modules (`csv`, `json`, ...) or a single `load`; reading a stream from the network as well as a file; writing a file of these types.
- (f) Encoding and the line ending; the error when a unit is not well formed (raised when the loop reaches it).
- (g) Levels: `Csv` and `Json` in level 3, `Html` and `Htmlt` with the templates (0.6), `Xml` and `Dat` open.
**Answer:**

