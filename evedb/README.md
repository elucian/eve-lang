# evedb: the Eve test database

Status: **design for review**, 2026-10-10. The author decided that evedb stays in this repository (question 1). The build exists: DuckDB 1.5.6 is a dependency, `zig build -p ..` installs `bin/evedb.exe` and `bin/duckdb.dll`, and `evedb` runs a self-check (`zig build test`: 4 tests); the server is not written yet. The Eve database layer is designed in [design-database-core.md](../plan/design-database-core.md) and [design-database-remote.md](../plan/design-database-remote.md); this file uses their terms. Feature F-DAT-12 of [version_map.md](../plan/version_map.md).

## 1. What evedb is

`evedb` is a small database server written in Zig around **DuckDB**, tuned for Eve. It is a separate program (`bin/evedb.exe`), never linked into the Eve virtual machine.

The author's decisions behind it:

- **SQLite is the core database** of Eve, embedded in the VM (Q-043a): the Eve database, the cache, staging, local applications.
- **DuckDB is the secondary database**: "a DuckDB Zig binding implementation that can be an alternative database for remote database usage optimized for Eve … a secondary project not embedded in the core VM … an independent database engine used by Eve as an alternative to other databases" (answer to question 1 of the first draft, [archive/design-database.md](../plan/archive/design-database.md)).
- **First use: a test database tuned to work as a remote database** (2026-10-10). The remote path of the Eve database layer (sessions, change sets, commit and doubt, the mapping check in production, parallel loads, ETL transfers) needs a remote database in every test run. PostgreSQL can play it, but it needs an installation, it can't be told to fail on cue, and it does not speak Eve. evedb can do all three.

## 2. Goals and non-goals

| Goals | Non-goals |
|---|---|
| a remote database for the level 5 tests, started by the test runner on `localhost` in a fraction of a second | a replacement for PostgreSQL or MySQL in production OLTP |
| speaks the database frames of EWP (design-database-remote.md §5) natively: no vendor protocol, no driver library on the Eve side | the PostgreSQL wire protocol, ODBC, JDBC |
| Eve types end to end, with no lossy conversion | types Eve does not have |
| **fault injection**: make a commit fail, a connection drop, a conflict happen, exactly when a test asks | random chaos |
| a **statement log** that a test can read, to prove what SQL the ORM sent (only the dirty columns, the batches, the order of the flush) | an audit log for production |
| later: an analytic database for Eve (columnar, fast aggregates, Parquet and CSV in and out), as the author planned | being embedded in the VM |

## 3. Why DuckDB

| DuckDB gives | evedb uses it for |
|---|---|
| a C API (`duckdb.h`) over a prebuilt library, stable across versions | the binding in Zig |
| ACID transactions with MVCC and optimistic concurrency: two transactions that change the same row conflict at the commit | the `ConflictError` and transient-error paths of the tests, without tricks |
| column storage and the **Appender** API (rows appended in column batches) | the bulk path of `load!`; EWP sends tables column by column, so a `BATCH` frame maps to an appender chunk with little copying |
| `HUGEINT` (128-bit), `UBIGINT`, `DECIMAL(p, s)` up to 38 digits, `TIMESTAMPTZ`, `DATE`, `TIME`, `INTERVAL`, `UUID`, `BLOB`, `BOOLEAN` | a native column type for every Eve type, `Huge` included |
| `INSERT … ON CONFLICT DO UPDATE` | upserts of `load!(mode: "upsert")` |
| `information_schema` and `duckdb_columns()` | the catalog for the mapping check |
| reads and writes of CSV, JSON and Parquet in SQL | fixtures of the tests now; the analytic role later |
| one file per database, or `:memory:` | a fresh database per test in milliseconds |

Limits that the design accepts: one process opens a DuckDB file for writing (evedb is that process; its sessions are connections inside it); many small single-row transactions are slower than on PostgreSQL (fine for tests and bulk ETL); the checks of unique indexes on updated key columns are stricter than in PostgreSQL (the ORM never updates a key, design-database-core.md §6.3).

## 4. Tuned for Eve

1. **EWP natively.** evedb listens on a TCP port and answers the frames `HELLO`, `OPEN`, `BEGIN`, `QUERY`, `BATCH`, `CREDIT`, `CHANGES`, `APPLIED`, `COMMIT`, `ROLLBACK`, `STATUS`, `PING`, `CLOSE`, `ERROR`. On the Eve side the driver `evedb://` is thin: it is the remote-session client of design-database-remote.md §4.1 with no Eve server in between. evedb is therefore the **first implementation of the server side of the remote session protocol**; the Eve server of level 6 can reuse its code (question 2).
2. **Eve types on the wire and in the catalog.** Values travel in Eve's binary form and land in the matching DuckDB type with no text round trip:

| Eve | DuckDB |
|---|---|
| `Integer` | `BIGINT` |
| `Natural` | `UBIGINT` |
| `Huge` | `HUGEINT` |
| `Decimal` | `DECIMAL(p, s)` |
| `Real`, `Float` | `DOUBLE`, `FLOAT` |
| `Logic` | `BOOLEAN` |
| `String` | `VARCHAR` |
| `Instant` | `TIMESTAMPTZ` |
| `DateTime` | `TIMESTAMPTZ` + offset column (question 4) |
| `Date`, `Time` | `DATE`, `TIME` |
| `Duration` | `INTERVAL` |
| `Uuid` | `UUID` |
| `Bytes` | `BLOB` |

   `describe` answers in Eve types, so the mapping check of design-database-core.md §5 is exact, and `evedb describe eve_test orders --eve` prints the record class and the `table` declaration of a table.
3. **The Eve tables built in.** `eve_tx` (committed transaction ids, for `STATUS`) and `eve_checkpoint` (checkpoints committed with their batch) exist in every evedb database; no `db prepare` is needed (design-database-remote.md §4.1, design-database-core.md §8.5).
4. **Sessions with leases.** One session per client process and connection name, one DuckDB connection per session, a lease renewed by `PING`; a lease that runs out rolls back. The same rules as the session manager of the Eve server.
5. **Errors in Eve classes.** Each DuckDB error is classified with a SQL state: a transaction conflict is `40001` (transient, a `retry`), a constraint is `23xxx`, a missing table `42P01`. The `ERROR` frame carries the class name, so the client raises `ConflictError`, `ConstraintError` or `DeadlockError` directly.

## 5. Fault injection

A test of rollback, retry or doubt needs a failure at an exact point. In **test mode** (`evedb serve --test`), a session accepts `pragma eve_fault(…)` statements, sent with `execute!` like any SQL; outside test mode they are an error. The fault fires once, at the next matching point of that session (or of every session with `scope := 'all'`).

| Fault | Fires | Tests |
|---|---|---|
| `drop` at `'begin'`, `'changes'`, `'before_commit'`, `'after_commit'` | the server closes the connection at that point | lost connection → transient → `retry`; **doubt**: `after_commit` makes the client ask `STATUS` and find the job committed |
| `conflict` on a table | the next update of that table reports `40001` | optimistic locking, `ConflictError`, `retry` reads fresh records |
| `deadlock` | the next statement fails with a transient deadlock | `DeadlockError`, `retry after` |
| `commit_fail` | the commit fails, the transaction rolls back | job failure at `done`, memory restored |
| `status_unknown` | `STATUS` answers "unknown" | `CommitError(partial)`, refused for retry |
| `delay` of a duration | each frame waits | time-outs, `$lock_timeout`, leases |
| `lease_expire` | the lease ends now | rollback by the server |
| `drift` on a table: add a column, change a type, drop a column | the schema changes before the next `OPEN` | schema drift line (warning), `MappingError` (error) in production |

```eve
** a level 5 test: the network breaks after the commit was sent
new test := database.connect("test");
test.execute!("pragma eve_fault('drop', 'after_commit')");
```

## 6. Statement log

In test mode every statement that evedb runs is written to the table `eve_log.statements`: session, transaction id, sequence, kind (`insert`, `update`, `delete`, `select`, `load`), table, the columns written, the number of rows, and the SQL text. A test reads it to check what the ORM sent:

```eve
** only the dirty field and the version were written
class Logged = {columns: String} <: Record;
new last := test.query_one!(:Logged)("select columns from eve_log.statements where kind = 'update' order by seq desc limit 1");
expect last != null and last.columns == "city,version";
```

This is how the conformance tests prove the rules that are otherwise invisible: updates of the dirty fields only, one batch per dirty set, inserts before updates before deletes, nothing sent for an unchanged record.

## 7. Commands

| Command | Meaning |
|---|---|
| `evedb serve [--port 8044] [--data <folder>] [--test]` | listen; `--test` allows faults and the statement log and listens on `localhost` only |
| `evedb create <name> [from <script.sql>]` | a new database file in the data folder |
| `evedb sql <name> "<statement>"` | run one statement and print the result |
| `evedb describe <name> <table> [--eve]` | the columns in Eve types; `--eve` prints the class and the `table` declaration |
| `evedb snapshot <name> <file>`, `evedb reset <name> from <file>` | save a database and put it back, for the fixtures of a test suite |
| `evedb import <name> <table> <file>`, `evedb export <name> <table> <file>` | CSV, JSON, Parquet, through DuckDB |
| `evedb status` | sessions, leases, open transactions |

The test runner (`script/runtest.py 5`) starts `evedb serve --test` with a fresh data folder, resets the fixtures before each test that names the connection `"test"`, and stops it at the end.

## 8. Inside

```
evedb/
  README.md          this design
  build.zig          (later) builds bin/evedb.exe: zig build -p ..
  build.zig.zon
  src/
    main.zig         command line
    server.zig       listener, one task per client connection
    ewp.zig          frames: read, write, values in Eve's binary form (shared with evevm later, question 2)
    session.zig      sessions, leases, transactions, eve_tx, STATUS
    duckdb.zig       the binding over the C API: database, connection, prepared statement, appender, result chunks
    types.zig        Eve type ⇄ DuckDB type, value conversion
    catalog.zig      describe, Eve class text
    changes.zig      CHANGES frames to SQL: the statement generator of design-database-core.md §7
    fault.zig        pragma eve_fault, the fault points
    log.zig          eve_log.statements
```

- **Dependencies.** The prebuilt DuckDB library of each system is a lazy dependency of `build.zig.zon` (`duckdb_windows_amd64`, `duckdb_linux_amd64`, `duckdb_osx_universal`, release v1.5.6, checked by hash): `zig build` downloads only the one of the target, into `zig-pkg/` (git-ignored). To move to a new DuckDB release, replace the three URLs and hashes with `zig fetch --save=<name> <url>`.

- **Binding.** The build translates `duckdb.h` (`addTranslateC`) and links the prebuilt DuckDB library of a pinned version (`duckdb.dll` on Windows, `libduckdb.so`, `libduckdb.dylib`). DuckDB is C++, so building it from source with `zig c++` is possible but slow; the prebuilt library comes first (question 3).
- **Language and rules.** Zig 0.16, like `evevm/`. Every function, test, type and non-obvious declaration gets its `// Zig tip:` comment, as in the VM (question 5).
- **Concurrency.** One DuckDB database object per database file, one DuckDB connection per session; DuckDB runs the transactions of different connections in parallel with MVCC.
- **Tests.** Zig unit tests in the source files (`zig build test`); the Eve conformance tests of the remote path stay in `test/level5` and run against evedb.

## 9. Versions

| evedb | With Eve | Content |
|---|---|---|
| 0.1 | 0.4 (level 5) | `serve --test`, sessions and leases, `OPEN`, `BEGIN`, `QUERY`, `CHANGES`, `COMMIT`, `ROLLBACK`, `STATUS`, Eve types, `describe`, appender loads, upserts, faults, statement log, `create`, `snapshot`, `reset` |
| 0.2 | 0.5 (level 6) | tokens, several clients, `import`/`export`, the protocol code shared with the Eve server |
| later | | the analytic database: Parquet, large aggregates, TLS, users and rights |

## Questions for the author

1. **Place.** `evedb/` in the eve-lang repository, next to `evevm/`, building `bin/evedb.exe` (proposed), or a repository of its own from the start?
**Answer:** (2026-10-10) evedb stays in this repository. Yes, here. The effort is the same, we will encapsulate more /tools here anyhow.
2. **Shared protocol code.** The frames of EWP are written once and used by the VM (client and Eve server) and by evedb: a shared Zig module (for example `ewp/` at the root), or a copy in each program until the protocol is stable?
**Answer:**
Good idea, create foder: modules where different eve zig projects can reuse.
3. **DuckDB library.** A prebuilt DuckDB library of a pinned version (proposed, and installed this way on 2026-10-10), or DuckDB built from source with the Zig toolchain?
**Answer:**
I preffer DuckDB build from source.
4. **`DateTime` with a zone.** DuckDB keeps `TIMESTAMPTZ` as an instant and drops the offset. Store the offset in a second column, or map `DateTime` to text?
**Answer:**
We store offset in a second column.
5. **Zig tips.** Does the teaching rule of `evevm/` (`// Zig tip:` before every function, test and type) apply to `evedb/` too (proposed)?
**Answer:**
Yes, we continue to add Zig tips.
6. **Port.** `8044` as the default port of evedb (the Eve machine serves HTTP on 8042, design-service.md)?
**Answer:**
Yes sounds good.
