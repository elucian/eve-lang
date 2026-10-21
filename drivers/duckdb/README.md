# evedb: the Eve test database

Status (2026-10-20): **level 7** (D-203, D-204). evedb is the **server** of Eve: one program with the code of evevm plus DuckDB, the enterprise edition; `eve` (evevm) is the light edition, the client of levels 1 to 6. Everything that was built stays in the tree and is explained here. Written in order: version 0.1 (the EWP-db frames, sessions, faults, statement log), **version 0.2: evedb behaves like a PostgreSQL server** (sections 5A and 5B, D-186, in force), **version 0.3: column batches** on the native protocol (section 5.5), the driver `evedb://` (section 5C) and the measurements (section 5.6). Version 0.3 was decided by D-187, which the author **reverted** on 2026-10-20 (D-203): the code and its tests are **kept** as the fast path of an evedb that stays a plain engine today, and the rules of D-187 that say "no stored procedures and no triggers in evedb" and "no Eve in evedb" (sections 3A, 3B and 12) are **void**: evedb hosts the Eve machine for procedures, functions and business logic (D-186 point 6). The static embedding of DuckDB (D-200) waits: `duckdb.dll` ships beside `evedb.exe` for now. Where a section below says that stored procedures or triggers are dropped, read it as not yet written, not as refused. Feature F-DAT-12 of spec/features, level 7; tests `test/level7/g01_pg_driver` and `g02_evedb_columnar`, `script/pg_check.py`, `script/evedb_check.py`, `script/evedb_bench.py`. The author decided that evedb stays in this repository (question 1). The Eve database layer is designed in [design-database-core.md](../../design/design-database-core.md) and [design-database-remote.md](../../design/design-database-remote.md); this file uses their terms. The service mode of the machine, which evedb shares, is in [design-service.md](../../design/design-service.md) section 17 and [spec/library/machine.md](../../spec/library/machine.md).

**What lives in `drivers/duckdb/`** (since 2026-10-19, D-198): the **program `evedb`** (`bin/evedb.exe`, its own `build.zig`, DuckDB): the database server of this document, and `protocol/`, the module `ewp_protocol` (the frames, the column batches and a client) that the server shares with the driver `evedb://` of `eve`. The database layer of `eve` (SQLite, connections, tables and records, the drivers) moved into the runtime: `code/evevm/src/db/`. The program never links into the virtual machine; the virtual machine never links DuckDB. The folder moved from `code/evedb` to `drivers/duckdb` on 2026-10-19 (S8.5): the server is a driver project, not a component of Eve.

## 1. What evedb is

`evedb` is a small database server written in Zig around **DuckDB**, tuned for Eve. Since version 0.2 it **behaves like a PostgreSQL server**: it listens on port 5432 and speaks the PostgreSQL frontend/backend protocol (section 5A), so the PostgreSQL client of any language (libpq, psycopg2, pg8000, JDBC) and the **Eve driver for PostgreSQL** (section 5B) use it as a remote PostgreSQL database; DuckDB answers the SQL. A second port, the **control port**, speaks the database frames of the Eve Wire Protocol (EWP-db, section 5): the test runner uses it for `STATUS`, the counters and `stop`. Each client gets a **session** with its own DuckDB connection, a **lease** and transactions; faults can be injected and every statement is logged, on both ports.

The author's decisions behind it:

- **SQLite is the core database** of Eve, embedded in the VM (Q-043a): the Eve database, the cache, staging, local applications.
- **DuckDB is the secondary database**: "a DuckDB Zig binding implementation that can be an alternative database for remote database usage optimized for Eve … a secondary project not embedded in the core VM … an independent database engine used by Eve as an alternative to other databases".
- **First use: a test database tuned to work as a remote database** (2026-10-10). The remote path of the database layer (sessions, change sets, commit and doubt, the mapping check in production, parallel loads, ETL transfers) needs a remote database in every test run. PostgreSQL can play it, but it needs an installation, it can't be told to fail on cue, and it does not speak Eve. evedb can do all three.

## 2. Goals and non-goals

| Goals | Non-goals |
|---|---|
| a remote database for the tests of levels 5 and 6, started by the test runner on `localhost` in a fraction of a second | a replacement for PostgreSQL or MySQL in production OLTP |
| speaks the database frames of EWP natively: no vendor protocol, no driver library on the Eve side | the PostgreSQL wire protocol, ODBC, JDBC |
| Eve types end to end, with no lossy conversion | types Eve does not have |
| **fault injection**: make a commit fail, a connection drop, a conflict happen, exactly when a test asks | random chaos |
| a **statement log** that a test can read, to prove what SQL the ORM sent | an audit log for production |
| runs as a **service** (Windows) or **daemon** (Linux) like the machine, silent, with a log file | a user interface |
| later: an analytic database for Eve (columnar, Parquet and CSV in and out) | being embedded in the VM |

## 3. Why DuckDB

| DuckDB gives | evedb uses it for |
|---|---|
| a C API (`duckdb.h`) over a prebuilt library, stable across versions | the binding in Zig (`src/duckdb.zig`) |
| ACID transactions with MVCC and optimistic concurrency: two transactions that change the same row conflict at the commit | the `ConflictError` and transient-error paths of the tests, without tricks |
| column storage and the **Appender** API | the bulk path of `load!` (version 0.2) |
| `HUGEINT` (128-bit), `UBIGINT`, `DECIMAL(p, s)` up to 38 digits, `TIMESTAMPTZ`, `DATE`, `TIME`, `INTERVAL`, `UUID`, `BLOB`, `BOOLEAN` | a native column type for every Eve type, `Huge` included |
| `INSERT … ON CONFLICT DO UPDATE` | upserts |
| `information_schema` and `duckdb_columns()` | the catalog for the mapping check (`DESCRIBE`) |
| reads and writes of CSV, JSON and Parquet in SQL | fixtures now; the analytic role later |
| one file per database, or `:memory:` | a fresh database per test in milliseconds |

Limits that the design accepts: one process opens a DuckDB file for writing (evedb is that process; its sessions are connections inside it); many small single-row transactions are slower than on PostgreSQL (fine for tests and bulk ETL).

## 3A. SQLite and DuckDB: who does what (D-184, D-187)

| | SQLite, inside every `eve` | DuckDB, inside the `evedb` server only |
|---|---|---|
| Storage | rows, in pages of a B-tree | compressed columns, in row groups of about 122,000 rows |
| Strong at | reading and writing one row, small transactions, a tiny library (compiled into `eve.exe`), no setup | scanning, filtering, joining and aggregating millions of rows on every core; reading and writing Parquet, CSV and JSON files in SQL |
| Weak at | analytics on large tables (one thread, row storage) | many single-row inserts and point updates; a large library |
| Concurrency | many readers and one writer, across processes (WAL) | **one process writes a database file**; that process is evedb |
| Holds | the core database of a project (`db/local.db`: checkpoints, run history, lineage), job state, configuration state, small reference caches (`db/cache.db`), the data of small local applications | the warehouse tables, the staging of large loads, large data caches (snapshots of remote tables, results of heavy queries), the files of the analytic exports |

**Why both.** With DuckDB only, every `eve` would carry a large library, and two scripts could not write the same small project file (DuckDB locks a file to one process). With SQLite only, the ETL and the analytics of large data would be slow. So `eve` stays small and keeps SQLite for its own state, and the heavy data lives in one place, the evedb server, which owns the DuckDB files. Nothing else opens them: every access goes through evedb.

## 3B. The files of DuckDB and how they are reached

```
project/
  eve.cfg                       the connections of the scripts
  db/local.db                   SQLite: the core database of eve
  db/cache.db                   SQLite: small reference caches
  evedb.cfg                     the server: ports, login, test mode, the databases
  data/                         owned by evedb (no other program opens these files)
    warehouse.duckdb            one DuckDB database is one file: its schemas, tables, views, sequences, macros
    warehouse.duckdb.wal        the write-ahead log of DuckDB, while changes wait for a checkpoint
    staging.duckdb              another database (a load lands here, then moves to the warehouse in SQL)
    exports/sales_2026.parquet  files that DuckDB reads and writes directly (`COPY … TO`, `read_parquet(...)`)
```

Inside one `.duckdb` file every database also has the table `eve_tx` (the committed transaction ids of section 6) and, in test mode, the schema `eve_log` (the statement log of section 8.2).

| To | Do |
|---|---|
| make a database | `evedb create warehouse` (the file `data/warehouse.duckdb`), or a line `database "warehouse" = "data/warehouse.duckdb"` in `evedb.cfg` (made at the first connection in test mode) |
| reach it from a script, fast | `database "wh" = "evedb://127.0.0.1:8044/warehouse"` in `eve.cfg` (the native protocol, section 5C; `evedb://token@host:8044/warehouse` for a server with a token) |
| reach it from any other tool | `postgres://user:password@host:5432/warehouse` (section 5A) |
| look at it by hand | `evedb sql warehouse "select …"` (directly on the file, when no server has it open), or `evedb sql --connect host:8044 warehouse "…"` |
| copy it | `evedb snapshot warehouse file`, `evedb reset warehouse file` |

## 4. Architecture

```
            client (eve driver evedb://, evedb sql, a test in Python)
                         |  TCP, EWP frames (section 5)
   +---------------------v----------------------------------------------+
   | evedb process                                                      |
   |  listener ── one thread per connection ── frame loop               |
   |                    |                                               |
   |            session table (id → Session)      reaper thread         |
   |                    |                         (leases, 1 s tick)    |
   |  Session: DuckDB connection, open transaction id, fault list, seq  |
   |                    |                                               |
   |  Databases: name → duckdb.Database (one per file, opened once)     |
   |  each database has eve_tx, and in test mode the schema eve_log     |
   +--------------------------------------------------------------------+
```

- **One process, one DuckDB database object per file**, opened at the first `OPEN` of its name and kept until the server stops. Each session has its own DuckDB connection; DuckDB runs the transactions of different connections in parallel (MVCC).
- **One thread per client connection** (`std.Thread`). A session belongs to one connection at a time; a client that reconnects after a drop opens a new session and asks `STATUS` about its transaction.
- **The reaper thread** wakes every second and rolls back the open transaction of any session whose lease ran out, closes its DuckDB connection and forgets it.
- **Sources** (`drivers/duckdb/src/`):

| File | Holds |
|---|---|
| `main.zig` | the command line (section 9) |
| `ewp.zig` | frames: length, type, stream; the values in Eve's binary form; reading and writing (no sockets: it works on byte buffers, so Python and Zig tests can both check it) |
| `server.zig` | the listener, the frame loop of a connection, `HELLO`, tokens |
| `session.zig` | sessions, leases, transactions, `eve_tx`, `STATUS` |
| `duckdb.zig` | the binding over the C API: database, connection, prepared statement, results |
| `types.zig` | DuckDB type ⇄ Eve type name, value conversion to frames |
| `errors.zig` | DuckDB error → class, SQL state, transient flag |
| `fault.zig` | `pragma eve_fault`, the fault points |
| `log.zig` | the statement log (`eve_log.statements`) |
| `client.zig` | a client of the frames, used by `evedb sql --connect`, `evedb status` and the Zig tests |

- **Concurrency rules.** The session table and the fault lists are guarded by a mutex; a session is used by one thread at a time (its connection thread, or the reaper after the lease ran out, which takes the session out of the table first).
- **Language and rules.** Zig 0.16, like `code/evevm/`; every function, test, type and non-obvious declaration has its `// Zig tip:` comment (question 5).

## 5. The native protocol: EWP-db

EWP is the Eve Wire Protocol of [design-service.md](../../design/design-service.md) section 9 (F-NET-03). The database frames of version 0.1 are fixed here; the general frames (`APPLY`, `RESULT`, `CANCEL`) join when EWP is written as a whole. All integers are **little endian**.

### 5.1 Frame

```
+----------------+--------+----------------+-----------------------+
| length  u32    | type u8| stream  u32    | payload (length - 5)  |
+----------------+--------+----------------+-----------------------+
```

`length` counts the bytes after itself (type, stream, payload); the largest frame is 16 MiB (a bigger one is a protocol error and the connection closes). `stream` is chosen by the client for each request; every answer to that request carries the same number. A frame from the server that answers nothing (none in 0.1) would have stream 0. A **string** is `u32` length then UTF-8 bytes; a **list** is `u32` count then items.

### 5.2 Values

A value is a tag and its data:

| Tag | Eve type | Data |
|---|---|---|
| 0 | `null` | none |
| 1 | `Logic` | `u8` (0 or 1) |
| 2 | `Integer` | `i64` |
| 3 | `Real` | `f64` |
| 4 | `String` | string |
| 5 | `Bytes` | `u32` length, bytes |
| 6 | `Decimal` | string, the decimal text (`12.50`) |
| 7 | `Instant` | `i64`, microseconds since 1970-01-01T00:00:00Z |
| 8 | `Date` | `i32`, days since 1970-01-01 |
| 9 | `Huge` | string, the decimal text of the 128-bit integer (0.1; a binary form comes later) |
| 10 | `Uuid` | 16 bytes |

Parameters of `QUERY` and `EXECUTE` are values; the result of a `QUERY` is rows of values, with the Eve type name of each column in its header, so the client builds Eve values with no guessing.

### 5.3 Frames

| Type | Name | From | Payload | Answer |
|---|---|---|---|---|
| 0x01 | `HELLO` | client | magic `EWPD` (4 bytes), version `u16`, client name (string), token (string) | `HELLO_OK` |
| 0x02 | `OPEN` | client | database name (string), client process id `u32` | `OPENED` |
| 0x03 | `BEGIN` | client | transaction id (16 bytes, a UUID), isolation `u8` (0 default), read only `u8` | `OK` |
| 0x04 | `QUERY` | client | SQL (string), parameters (list of values), row limit `u32` (0: no limit) | `RESULT` |
| 0x05 | `EXECUTE` | client | SQL (string), parameters (list of values) | `EXECUTED` |
| 0x06 | `COMMIT` | client | transaction id | `OK` |
| 0x07 | `ROLLBACK` | client | transaction id | `OK` |
| 0x08 | `STATUS` | client | transaction id | `TXSTATUS` |
| 0x09 | `PING` | client | none | `PONG` |
| 0x0A | `DESCRIBE` | client | table name (string) | `DESCRIBED` |
| 0x0B | `SERVERSTAT` | client | none | `SERVERSTATS` |
| 0x0C | `CLOSE` | client | none | `OK`, then the server closes the connection |
| 0x0D | `STOP` | client | none | `OK`, then the server stops (test mode, or a server with a token) |
| 0x0E | `QUERYB` | client | SQL (string), parameters (list of values), batch size wished `u32` | `SCHEMA`, `BATCH`…, `END` (section 5.5) |
| 0x0F | `LOAD` | client | table (string), create `u8` (1: make the table), schema (section 5.5); then `BATCH` frames and `END` on the same stream, without waiting | `EXECUTED` (the rows appended) or `ERROR` |
| 0x80 | `OK` | server | none | |
| 0x81 | `HELLO_OK` | server | version `u16`, server name (string), test mode `u8` | |
| 0x82 | `OPENED` | server | session id `u64`, lease in milliseconds `u32` | |
| 0x83 | `RESULT` | server | column count `u16`; per column: name (string), Eve type (string); row count `u32`; the values row by row; truncated `u8` (1 if the row limit cut the result) | |
| 0x84 | `EXECUTED` | server | rows changed `i64` | |
| 0x85 | `TXSTATUS` | server | `u8`: 0 committed, 1 rolled back, 2 unknown, 3 in progress (the transaction is open in a session now) | |
| 0x86 | `PONG` | server | lease in milliseconds `u32` (renewed) | |
| 0x87 | `DESCRIBED` | server | column count `u16`; per column: name, Eve type, DuckDB type, nullable `u8`, primary key `u8` | |
| 0x88 | `SERVERSTATS` | server | databases `u32`, sessions `u32`, open transactions `u32`, statements run `u64`, uptime in milliseconds `u64` | |
| 0x89 | `SCHEMA` | server | the schema of a columnar result (section 5.5) | |
| 0x8A | `BATCH` | both | some rows, column by column (section 5.5) | |
| 0x8B | `END` | both | from the server: the number of rows `u64`; from the client (after a load): nothing | |
| 0xFF | `ERROR` | server | class (string), SQL state (5 characters as a string), transient `u8`, message (string) | |

`QUERY` answers a result whole in one `RESULT`, row by row with a tag for every value: right for records and small results. Large results and loads use the column batches of section 5.5. Flow control is TCP's (a slow reader makes the server wait in its write); explicit `CREDIT` frames come only if a benchmark shows they are needed. `CHANGES` and `APPLIED` (the change sets of the ORM) wait: the client sends the SQL it generated with `EXECUTE`, which is what the statement log proves.

Any request before `HELLO`, `QUERY` before `OPEN`, or an unknown type is answered with `ERROR` class `ProtocolError` and the connection closes.

### 5.4 A conversation

```
client                              server
HELLO(EWPD,1,"eve-test","")   →
                              ←     HELLO_OK(1,"evedb 0.1",test=1)
OPEN("shop", pid)             →
                              ←     OPENED(session 7, lease 30000)
BEGIN(tx=9f3a…)               →
                              ←     OK
EXECUTE("insert into …", [..]) →
                              ←     EXECUTED(1)
COMMIT(tx=9f3a…)              →     (the server writes the id into eve_tx, in the same transaction, then commits)
                              ←     OK
```

**Doubt.** The connection breaks after `COMMIT` was sent and before `OK` came. The client connects again (`HELLO`, `OPEN`) and sends `STATUS(tx=9f3a…)`: `TXSTATUS committed` if the id is in `eve_tx`, `rolled back` if it is not and the session that ran it is gone, `unknown` when `eve_tx` is missing or the fault `status_unknown` is set.

### 5.5 Column batches: the fast path (version 0.3, D-187)

A query of the native protocol can answer **column by column**, and a client can load a table the same way. A batch has the layout that DuckDB uses inside, and that the `Memory` tables of Eve use (`code/evevm/src/db/columnar.zig`): one array for each column and a bitmap for NULL. The code of the format is `src/batch.zig`, shared by the server and by the driver inside `eve`.

**Schema** (frame `SCHEMA`, and the head of `LOAD`): the number of columns `u16`; for each a name (string) and a wire type `u8`:

| Wire type | Byte | Values |
|---|---|---|
| boolean | 1 | 1 byte per row (0 or 1) |
| int | 2 | 8 bytes per row, `i64` little endian (DuckDB's integers of every width) |
| real | 3 | 8 bytes per row, `f64` (DuckDB's `FLOAT` and `DOUBLE`) |
| text | 4 | offsets and bytes (below) |
| date | 5 | 8 bytes per row: days since 1970-01-01 |
| timestamp | 6 | 8 bytes per row: micro seconds since 1970-01-01 00:00:00 (UTC for `TIMESTAMPTZ`) |
| decimal | 7 | offsets and bytes: the exact text (`12.50`); also `HUGEINT`, `UBIGINT`, `UUID`-like types without a fixed form |
| blob | 8 | offsets and bytes |

**Batch** (frame `BATCH`): the number of rows `n` (`u32`); then for each column of the schema, in order: a validity flag `u8` (0: every row has a value; 1: a bitmap of `(n + 7) / 8` bytes follows, bit `i` of byte `i / 8`, least significant bit first, set when row `i` has a value), then the values: `n` bytes for a boolean, `8 * n` bytes for the fixed types, or for a text column `n + 1` offsets (`u32`, the first 0, the last the total length) and the bytes. A NULL row of a fixed column holds any value.

**Conversations.**

```
client                                     server
QUERYB(sql, params)            →
                               ←           SCHEMA(columns)
                               ←           BATCH (one per DuckDB data chunk, 2048 rows)
                               ←           BATCH …
                               ←           END(rows)

LOAD(table, create, schema)    →           (no answer yet)
BATCH                          →           each row goes to DuckDB's Appender: no SQL for each row
BATCH …                        →
END                            →
                               ←           EXECUTED(rows)   or ERROR (the batches after a failure are read and dropped)
```

**Why it is fast.**

- **No text.** A value is never written as text and parsed back, which is most of the cost of the PostgreSQL protocol.
- **One copy per column.** A `BIGINT`, `DOUBLE` or `TIMESTAMP` vector of DuckDB goes into the frame with one copy, and comes out into the column of a `Memory` table with one copy (`@memcpy`). The validity bitmap of DuckDB is, byte for byte, the bitmap of the wire on a little-endian computer.
- **No per-value tag.** There is no tag for each value and no object for each row.
- **Bulk loads skip SQL.** A load is pipelined (no round trip per batch) and goes through the Appender.
- **What still costs.** The text columns cost a loop per row (offsets) on both sides; the integers narrower than 64 bits are widened.

**Shared memory** (a ring of batches in memory both processes map, for eve and evedb on one computer) keeps the same batch layout, so it would change only the transport. It is built only if section 5.6 shows that the socket is the bottleneck.

### 5.6 Measured (phase 2 of D-187)

Run on 2026-10-18 by `python script/evedb_bench.py --eve temp/rel/bin/eve.exe --evedb temp/rel/bin/evedb.exe` (the ReleaseSafe builds, Windows, one computer, loopback TCP): a table of 1,000,000 rows (`id BIGINT`, `region VARCHAR`, `amount DOUBLE`, `paid BOOLEAN`), the same rows in a SQLite file; median of 3 runs, the time to start `eve` and connect subtracted.

| Operation | Rows | Seconds | Rows per second |
|---|---|---|---|
| transfer: evedb:// column batches -> Memory | 1000000 | 0.228 | 4,395,324 |
| transfer: SQLite file -> Memory | 1000000 | 0.784 | 1,276,084 |
| transfer: evedb:// row frames -> records | 100000 | 0.148 | 675,751 |
| transfer: PostgreSQL protocol -> records | 100000 | 0.179 | 557,888 |
| transfer: SQLite file -> records | 100000 | 0.135 | 742,693 |
| OLAP group-by: DuckDB (evedb) | 1000000 | 0.009 | 112,295,202 |
| OLAP group-by: SQLite | 1000000 | 0.503 | 1,988,737 |
| bulk load: Memory -> evedb (Appender) | 1000000 | 0.662 | 1,510,686 |
| bulk load: Memory -> SQLite | 1000000 | 1.000 | 999,533 |

What the numbers say:

- **Column batches are the fast path.** 1,000,000 rows reach a `Memory` table in 0.23 s: 3.4 times faster than reading the same rows from a local SQLite file, and about 6 to 8 times the rate of any path that makes records.
- **Records cost about the same on every protocol.** 0.56 to 0.74 million rows per second for evedb's row frames, the PostgreSQL protocol and SQLite alike: the cost is making one Eve object per row, not the wire. Large data goes to `Memory` tables, not to records.
- **OLAP belongs to DuckDB.** The group-by over 1,000,000 rows takes 9 ms in DuckDB and 0.5 s in SQLite, about 55 times longer.
- **Bulk loads.** The Appender takes 1.5 million rows per second, SQLite 1.0 million. The Appender is still fed value by value; `duckdb_append_data_chunk` (whole vectors at once) is the next step for it.
- **The socket is not the bottleneck.** About 25 MB in 0.23 s is far below what loopback TCP carries. The time goes into the text column (a loop per row) and the work of the VM, so **shared memory is not built** (D-187: phase 3 stays closed until a benchmark says otherwise).

## 5A. The PostgreSQL face (version 0.2, D-186)

A PostgreSQL client cannot tell evedb from a small PostgreSQL 16 server, as long as it stays inside the minimal set below. That set is what a driver needs: log in, run SQL with and without parameters, read typed rows, use transactions, and get errors with their SQL state. The code is `src/pgserver.zig`.

### 5A.1 What is answered

| Part of the protocol | evedb 0.2 |
|---|---|
| Startup | protocol 3.0; the parameters `user` and `database` (the database defaults to the user); `SSLRequest` is answered `N` (no TLS: the client goes on in clear, or stops if it demands TLS); `CancelRequest` closes the connection; after the login: `ParameterStatus` (`server_version` = `16.4 (evedb 0.2 on DuckDB)`, `server_encoding` and `client_encoding` = `UTF8`, `DateStyle` = `ISO, MDY`, `integer_datetimes` = `on`, `standard_conforming_strings` = `on`, `TimeZone` = `UTC`), `BackendKeyData`, `ReadyForQuery` |
| Login | `auth` of the configuration: `trust` (no password), `password` (cleartext, `AuthenticationCleartextPassword`), `md5` (`AuthenticationMD5Password`, the hash of PostgreSQL: `md5` + md5(md5(password + user) + salt)); one user and one password per server (`user`, `password`). A wrong user or password is `FATAL 28P01`. SCRAM-SHA-256 is not offered by the server (the Eve driver speaks it, for real PostgreSQL servers) |
| Simple query (`Query`) | one or several statements separated by `;` (a `;` inside quotes, a comment or `$$ … $$` is not a separator); for each: `RowDescription` and `DataRow`s, or nothing, then `CommandComplete`; `EmptyQueryResponse` for an empty text; the transaction state in `ReadyForQuery` (`I`, `T`, `E`) |
| Extended query | `Parse` (named or unnamed statements, the parameter types the client gives), `Bind` (parameters in text, and in binary for `int2`, `int4`, `int8`, `float4`, `float8`, `bool`, `text`), `Describe` (statement: `ParameterDescription` and the columns from DuckDB's preparation; portal: the columns of the result), `Execute` (all the rows: the row limit of `Execute` is not used), `Close`, `Sync`, `Flush`; after an error the messages are skipped up to `Sync`, as PostgreSQL does |
| Transactions | `BEGIN`, `START TRANSACTION`, `COMMIT`, `END`, `ROLLBACK`, `ABORT` go to DuckDB; after an error inside a transaction every statement is refused with `25P02` until `ROLLBACK` (`COMMIT` then answers `ROLLBACK`), as in PostgreSQL |
| Settings | `SET`, `RESET`, `DISCARD`, `DEALLOCATE`, `LISTEN`, `UNLISTEN`, `LOCK` are acknowledged and ignored; `SHOW` answers `server_version`, `transaction isolation level` (`read committed`), `standard_conforming_strings`, `client_encoding`, `server_encoding`, `timezone`, `datestyle`, `search_path`, `integer_datetimes`, `max_identifier_length`; any other `SHOW` goes to DuckDB |
| SQL | the dialect of DuckDB, which is close to PostgreSQL for tables, queries, `RETURNING`, `ON CONFLICT`, `$1` parameters, `::` casts; a bytes literal of PostgreSQL (`'\x0102'::bytea`) is rewritten to DuckDB's `unhex('0102')` |
| Command tags | `SELECT n`, `INSERT 0 n`, `UPDATE n`, `DELETE n`, `CREATE TABLE`, `DROP TABLE`, `ALTER TABLE`, `BEGIN`, `COMMIT`, `ROLLBACK`, `SET`, `SHOW`, and the first word of any other command |
| Errors | `ErrorResponse` with severity, SQL state (`C`) and message (`M`, the first line of DuckDB's message): `23000` constraint, `42P01` unknown table, `42601` syntax, `22018` conversion, `40001` conflict, `40P01` deadlock, `25P02` aborted transaction, `3D000` unknown database, `28P01` wrong password, `0A000` not supported |
| Faults and log | `pragma eve_fault(…)` (section 8.1) is accepted as a statement in test mode; every statement is written to the statement log (section 8.2) |

**Types.** Rows are sent in the text format of PostgreSQL, with the type number of PostgreSQL in `RowDescription`:

| DuckDB | PostgreSQL type (oid) | Text |
|---|---|---|
| `BOOLEAN` | `bool` (16) | `t`, `f` |
| `SMALLINT`, `TINYINT` | `int2` (21) | digits |
| `INTEGER` | `int4` (23) | digits |
| `BIGINT`, unsigned up to 32 bits | `int8` (20) | digits |
| `UBIGINT`, `HUGEINT`, `DECIMAL(p, s)` | `numeric` (1700) | digits, with `s` decimals |
| `FLOAT`, `DOUBLE` | `float4` (700), `float8` (701) | shortest decimal; `NaN`, `Infinity` |
| `DATE` | `date` (1082) | `YYYY-MM-DD` |
| `TIME` | `time` (1083) | `HH:MM:SS[.ffffff]` |
| `TIMESTAMP` | `timestamp` (1114) | `YYYY-MM-DD HH:MM:SS[.ffffff]` |
| `TIMESTAMP WITH TIME ZONE` | `timestamptz` (1184) | the same, with `+00` (the server is in UTC) |
| `INTERVAL` | `interval` (1186) | `n mons n days HH:MM:SS.ffffff` |
| `BLOB` | `bytea` (17) | `\x` and hexadecimal digits |
| `UUID` | `uuid` (2950) | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `VARCHAR`, `ENUM`, others | `text` (25) | the text |

A list, a struct, a map or a bit string is refused with `0A000` (cast it to `varchar` in the query).

### 5A.2 What is not there (version 0.2)

TLS; SCRAM on the server side; several users and roles; `COPY`; cancel requests; `LISTEN`/`NOTIFY`; the row limit of `Execute` (portals are run whole); the binary result format; the system catalogs of PostgreSQL beyond what DuckDB offers (`pg_catalog` is partial, so `psql`'s `\d` does not work; plain SQL does); `select version()` answers DuckDB's version (`v1.5.6`); `CREATE TRIGGER` and stored procedures (designed in section 12).

### 5A.3 Tested with

`script/pg_check.py` (32 checks) uses **psycopg2** (libpq, the C library of PostgreSQL: login with md5, the simple protocol, types, errors, transactions, the aborted state, faults) and **pg8000** (pure Python: the extended protocol, parameters, recovery after an error), then the Eve driver and the two start forms of `eve` (section 9). The level 7 test `test/level7/g01_pg_driver` runs an Eve script against `eve db serve evedb.cfg`.

## 5B. The Eve driver for PostgreSQL (version 0.2)

A connection of `eve.cfg` whose URL starts with `postgres://` or `postgresql://` is opened by the driver of `code/evevm/src/db/pgdriver.zig` and `pgclient.zig` (in the database layer of `eve`, not in the evedb program), which speaks the PostgreSQL protocol to evedb **or to any PostgreSQL server**:

```
database "shop" = "postgres://eve:secret@db.example.com:5432/shop"
```

| Part | Version 0.2 |
|---|---|
| URL | `postgres://user:password@host:port/database`; `%XX` in the user and the password; port 5432 and the user `postgres` by default; the database defaults to the user |
| Login | trust, cleartext password, md5, and **SCRAM-SHA-256** (the default of PostgreSQL 14 and later; checked against the example of RFC 7677); no TLS yet: a server that requires TLS refuses the connection |
| Methods | `execute!(sql, params…)` (the rows changed, from the command tag), `query!(:Row)(sql, params…)` and `query_one!(:Row)(…)` (records, the columns matched to the members by name), `script(path)` (a file of statements, sent as one simple query), `close()` |
| Parameters | each `?` outside quotes and comments is replaced by the literal of its value: `NULL`, `TRUE`/`FALSE`, numbers, a `Decimal` as its digits, a text or an `Instant` between single quotes with every quote doubled (and backslashes doubled when the server says `standard_conforming_strings = off`) |
| Values | read from the text of the rows by the type of the member: `Logic` from `t`/`f`, whole numbers and reals parsed, `String` as it is, `Decimal` and `Instant` by the same reader as SQLite text; NULL only into an optional member |
| Transactions | the first statement of a job sends `BEGIN`; the end of the job sends `COMMIT`, or `ROLLBACK` when it failed or said `rollback;` (as the SQLite driver, `database.md#transactions`); outside a job every statement commits by itself |
| Errors | `DatabaseError: <message> [<SQL state>]: <statement>`, code 22 |
| Not yet | `table` declarations and tracked records (the ORM works on SQLite connections), `import`, prepared statements of the server, TLS, a pool |

The browser demo `drivers/duckdb/demo/` shows the whole path: a page of the machine (`web/index.html`, standing in for the database tab of eveux, which is not built) sends Eve scripts to `vm.run`; they open `postgres://eve:demo@127.0.0.1:5432/shop` and evedb answers on port 5432.

## 5C. The Eve driver for evedb (version 0.3, D-187)

`database "wh" = "evedb://[token@]host:port/database"` in `eve.cfg` opens a connection of the native protocol (`code/evevm/src/db/ewpdriver.zig`, in the database layer of `eve`), on the control port of evedb (8044 by default).

| Method | Wire |
|---|---|
| `execute!(sql, params…)`, `query!(:Row)(…)`, `query_one!(:Row)(…)`, `script(path)`, `close()` | `EXECUTE`, `QUERY` (records); the parameters `?` are bound by DuckDB as typed values, so no SQL text is built and nothing needs quoting |
| a job | `BEGIN` with an id at the first statement, `COMMIT` or `ROLLBACK` at the end (and `STATUS` can tell later what happened, section 6) |
| `s.store(wh, select, params…)` on a `Memory` table `s` | `QUERYB`: the batches go straight into the columns of `s`, matched to its fields by name; an integer column into an `Integer` field and a real into a `Real` field are copied whole; other pairs are converted value by value (a decimal into a `Real`, anything into a `String`) |
| `s.load(wh, name)` | `LOAD` with create: the table `name` is made from the fields of the class (`Integer` → `BIGINT`, `Real` → `DOUBLE`, `Logic` → `BOOLEAN`, `String` → `VARCHAR`) and filled through the Appender |

**Not yet:** `table` declarations and tracked records on this connection (the ORM works on SQLite), TLS, a pool of connections.

## 6. Sessions, leases and transactions

1. **One session** per `OPEN`: a number, a DuckDB connection, the name of the database, the client's process id, a lease deadline. Closing the connection (or `CLOSE`) ends the session and rolls back an open transaction.
2. **Lease.** 30 s by default (`--lease`). Every frame from the client renews it; `PING` renews it without work. The reaper rolls back the transaction of a session whose lease ran out and answers `ERROR LeaseExpired` (transient) to the next frame of that connection, then closes it.
3. **Transaction.** `BEGIN` issues `BEGIN TRANSACTION` (read only: `START TRANSACTION READ ONLY`); the transaction id is the client's. At most one transaction is open in a session: a second `BEGIN` is `ProtocolError`. A statement outside `BEGIN` runs in autocommit.
4. **`COMMIT`.** In the same transaction as the data the server runs `insert into eve_tx values (?, now())` and then `COMMIT`. If the second step fails the transaction rolls back and the client gets the error; the id is not in `eve_tx`.
5. **`eve_tx`** (`id VARCHAR PRIMARY KEY, committed TIMESTAMP`) is created at the first `OPEN` of every database (no `db prepare` is needed), as is, in test mode, the schema `eve_log` (section 8).
6. **Isolation.** DuckDB's: snapshot isolation with optimistic conflict detection. The `isolation` byte of `BEGIN` is kept for the day another level exists; 0.1 accepts only 0.

## 7. Errors and Eve types

Each DuckDB failure is classified by the text of the error and its error type into a class, a SQL state and a transient flag. The `ERROR` frame carries them, so the client raises the right Eve error.

| Situation | Class | SQL state | Transient |
|---|---|---|---|
| a transaction conflict (`TransactionContext Error: Conflict on update`) | `ConflictError` | 40001 | yes |
| a deadlock | `DeadlockError` | 40P01 | yes |
| a constraint (`Constraint Error`: unique, not null, primary key, foreign key) | `ConstraintError` | 23000 | no |
| a missing table or column (`Catalog Error`) | `DatabaseError` | 42P01 | no |
| a syntax error (`Parser Error`) | `DatabaseError` | 42601 | no |
| a conversion (`Conversion Error`) | `ConvertError` | 22018 | no |
| the lease ran out | `LeaseExpired` | 08003 | yes |
| a fault `drop` | the connection closes, no frame | | yes (the client sees the break) |
| a bad frame | `ProtocolError` | 08P01 | no |
| anything else | `DatabaseError` | HY000 | no |

**Eve types.** `RESULT` and `DESCRIBED` name the Eve type of each column; the table is:

| DuckDB | Eve | | DuckDB | Eve |
|---|---|---|---|---|
| `BIGINT`, `INTEGER`, `SMALLINT`, `TINYINT` | `Integer` | | `DATE` | `Date` |
| `UBIGINT` | `Natural` | | `TIMESTAMP`, `TIMESTAMPTZ` | `Instant` |
| `HUGEINT` | `Huge` | | `VARCHAR` | `String` |
| `DOUBLE`, `FLOAT` | `Real`, `Float` | | `BLOB` | `Bytes` |
| `DECIMAL(p, s)` | `Decimal` | | `UUID` | `Uuid` |
| `BOOLEAN` | `Logic` | | other | `String` (the text form) |

`DateTime` with a zone keeps its offset in a second column (question 4); that is written with the ORM mapping in 0.2.

## 8. Fault injection and the statement log

### 8.1 Faults

In **test mode** (`evedb serve --test`) a session accepts `pragma eve_fault(kind, point, arg)` through `EXECUTE` (outside test mode it is an error). A fault fires **once**, at the next matching point of that session (`scope := 'all'` in the third place: every session). Faults wait in a list of the session.

| Fault | Point or argument | Effect | What it tests |
|---|---|---|---|
| `drop` | `'begin'`, `'execute'`, `'before_commit'`, `'after_commit'` | the server closes the connection at that point (`after_commit`: the commit is real, the answer is not sent) | lost connection → transient → `retry`; **doubt** with `STATUS` |
| `conflict` | a table name | the next `EXECUTE` that names that table fails with `ConflictError` (40001) | optimistic locking, `retry` |
| `deadlock` | none | the next statement fails with `DeadlockError` | `retry after` |
| `commit_fail` | none | the commit fails and the transaction rolls back | job failure at `done` |
| `status_unknown` | none | the next `STATUS` answers 2 | `CommitError(partial)`, refused for `retry` |
| `delay` | milliseconds | every frame of the session waits that long | time-outs, `$lock_timeout`, leases |
| `lease_expire` | none | the lease ends now | rollback by the server |

Version 0.2 adds `drift` (a column added, retyped or dropped before the next `OPEN`: the schema-drift tests of the production check). The statement is `pragma eve_fault('drop', 'after_commit', 0)`; it is answered `EXECUTED 0` and itself is not logged.

### 8.2 The statement log

In test mode every statement of a session is appended to `eve_log.statements` (`session BIGINT, tx VARCHAR, seq BIGINT, kind VARCHAR, tbl VARCHAR, rows BIGINT, sql VARCHAR, ts TIMESTAMP`). `kind` is the first keyword in lower case (`insert`, `update`, `delete`, `select`, `create`, …), `tbl` the first table after `into`, `update` or `from`, `rows` the rows changed or returned. The log is written by a separate connection, so a rollback does not remove its lines: a test sees what was **sent**, committed or not. A test reads it with `QUERY` like any table; version 0.2 adds the `columns` field (the columns written) from the change sets.

## 9. Commands, configuration and security

**Three ways to start evedb**, all with the same configuration file:

| Command | What runs |
|---|---|
| `evedb serve --config evedb.cfg` (options may follow and win over the file) | evedb in this window; it prints `evedb: postgres on port …` and `evedb: listening on port …` (the control port) and stays until it is stopped |
| `eve db serve evedb.cfg` | the same, started by `eve` from its own folder (`bin/evedb`), in the foreground; it ends with the status of evedb |
| `eve -s -db --serve evedb.cfg` (also `eve -s db serve evedb.cfg`) | **evedb as a service** (D-185, D-186): from a console it starts evedb detached and ends silent with status 0 when evedb says it is ready; `already running` (status 75) when a server answers on its ports; under the Windows Service Control Manager the `eve` process is the service and supervises evedb; with `EVE_SERVICE=foreground` the process supervises evedb in the foreground. The log is `<runtime>/evedb-<name of the configuration>.log` |

**The configuration file** (`src/cfg.zig`), the syntax of `eve.cfg`: `key = value`, `#` or `**` starts a comment, a `database` line for each database:

```
# evedb.cfg
port = 5432                          # the PostgreSQL port (0: the system chooses)
control_port = 8044                  # the EWP-db port; "off" closes it
host = "127.0.0.1"                   # the address to listen on
data = "data"                        # the folder of the databases that are not listed
user = "eve"                         # the user of the PostgreSQL port
password = "secret"
auth = "md5"                         # trust, password or md5
test = false                         # true: faults, the statement log, 127.0.0.1 only, databases made on demand
token = "…"                          # the secret of the control port (and of `evedb stop`)
lease = 30                           # seconds
database "shop" = "data/shop.duckdb" # a name a client may ask for, and its file (relative to the configuration file)
```

When `database` lines are given, a client may ask only for those names (`FATAL 3D000 database does not exist` otherwise); without them a name is the file `<data>/<name>.duckdb`, which must exist outside test mode. Outside test mode the control port opens only with a token. A server that listens on another address than `127.0.0.1` needs `auth = md5` or `password`. On Windows binding a port is no lock (`SO_REUSEADDR`), so evedb first connects to its own ports and refuses to start when one answers.

| Command | Meaning |
|---|---|
| `evedb serve [--config f] [--port 5432] [--control-port 8044] [--no-pg] [--host h] [--data d] [--test] [--lease s] [--token t] [--user u --password p --auth a]` | listen (section above) |
| `evedb create <name>` | a new database file in the data folder |
| `evedb sql <name> "<statement>"` | run one statement directly on the file (no server needed) and print the result |
| `evedb sql --connect <host:port> <name> "<statement>"` | the same through the control port of a running server |
| `evedb describe <name> <table>` | the columns in Eve types (directly on the file) |
| `evedb snapshot <name> <file>`, `evedb reset <name> <file>` | copy a database file out and put it back, for the fixtures of a test suite (the database must not be open in a server) |
| `evedb status [--connect host:port]` | the server counters (`SERVERSTAT`) |
| `evedb stop [--connect host:port] [--token t]` | ends a server (test mode, or with the token) |

**Security:** the token is a shared secret compared in constant time; there is no TLS in evedb (a reverse proxy gives it, as for the machine); `test = true` is for `localhost` and the test runner. Users, roles and TLS are a later version.

## 10. Testing

| Level | What | Where |
|---|---|---|
| unit | the codec (`ewp.zig`: every value, a frame split in pieces, a frame too large), the error classifier, the lease arithmetic, the fault list | `zig build test` in `drivers/duckdb/` |
| protocol | a **Python client** (`script/evedb_check.py`) written from section 5 alone, so it checks the document and the Zig code against each other: handshake, open, autocommit, transactions, rollback, `STATUS` after a commit and after a rollback, every fault, the statement log, lease expiry, two clients with a conflict, bad frames, a wrong token | `python script/evedb_check.py` (starts `bin/evedb.exe serve --test` on a free port with a fresh data folder) |
| column batches | `QUERYB` with every wire type and NULL bitmaps over several chunks, `LOAD` in three batches and read back, a refused load that leaves the stream in step, a load undone by `ROLLBACK` (part of the protocol client) | `python script/evedb_check.py` |
| speed | the benchmark of section 5.6: column batches, records over three protocols, OLAP in DuckDB and SQLite, bulk loads | `python script/evedb_bench.py --eve temp/rel/bin/eve.exe --evedb temp/rel/bin/evedb.exe` |
| PostgreSQL | psycopg2 and pg8000 against the PostgreSQL port, the Eve driver, the two start forms of `eve` (section 5A.3) | `python script/pg_check.py` |
| Eve | `test/level7/g01_pg_driver`: `eve db serve evedb.cfg` and an Eve script over `postgres://` with md5, a job that rolls back | `python script/runtest.py g01` |

## 11. Service mode

`eve -s -db --serve evedb.cfg` (section 9) makes evedb a service with the code of the machine's service mode (`code/evevm/src/service.zig`, design-service.md section 17): the same three forms (console, Service Control Manager, foreground) and the same silent behaviour; the supervised program is evedb instead of the machine. On Windows: `sc create evedb binPath= "C:\eve\bin\eve.exe -s -db --serve C:\eve\evedb.cfg" start= auto`. On Linux: a systemd unit of `Type=simple` with `Environment=EVE_SERVICE=foreground` and `ExecStart=/opt/eve/bin/eve -s -db --serve /etc/eve/evedb.cfg`. *Tested:* the console form (`script/pg_check.py`); the Service Control Manager form compiles and needs an administrator to run.

## 12. Logic lives in Eve, not in evedb (D-187)

A design of stored procedures and triggers written in Eve and run by evedb (an Eve machine hosted by the server, a connection back into the caller's transaction, `CREATE TRIGGER` emulated with `RETURNING` and temporary tables) was written in version 0.2 and **dropped** by the author (2026-10-18). It made evedb complex and slow on bulk work, and it hid logic in the database.

The rules instead:

- **evedb is a plain engine.** It stores data, runs SQL, takes bulk loads, gives column batches, and keeps the sessions, the faults and the statement log of the tests. It runs no Eve code.
- **The logic is in Eve jobs**, which work on sets: a `select` into a `Memory` table, the work on its columns, a `load` or one set-based `insert … select` / `update … from`, all in the transaction of the job. A check that a trigger would make is a step of the job; an audit trail is a table the job writes.
- **Reusable SQL** is a DuckDB macro (`create macro vat(amount, country) as …`), stored in the database file and called from any SQL; it needs no code of evedb.
- The Eve stored procedures of the machine (`proc/`, D-166) stay what they are: procedures of the machine, run by `eve`, against its databases.

## 13. Versions

| evedb | With Eve | Content |
|---|---|---|
| 0.1 (built) | 0.5 (level 6) | `serve [--test]`, EWP-db frames of section 5.3 except `CHANGES`, `APPLIED`, `BATCH`, `CREDIT`; sessions, leases, `eve_tx`, `STATUS`; Eve types; `DESCRIBE`; the faults `drop`, `conflict`, `deadlock`, `commit_fail`, `status_unknown`, `delay`, `lease_expire`; the statement log; `create`, `sql`, `describe`, `snapshot`, `reset`, `status`, `stop`; tokens |
| 0.2 (built) | 0.5 | **the PostgreSQL face** (section 5A) on port 5432 with trust, password and md5 logins, the simple and the extended protocol; the **Eve driver for PostgreSQL** (section 5B, with SCRAM-SHA-256 for real servers); the configuration file; `eve db serve` and `eve -s -db --serve` (service); the control port opens only with a token outside test mode |
| **0.3** (this build) | 0.5 | **column batches** (`QUERYB`, `LOAD`, `SCHEMA`, `BATCH`, `END`; section 5.5), the Appender, the driver **`evedb://`** with `Memory.store` and `Memory.load` (section 5C), the benchmark (section 5.6); stored procedures and triggers dropped (section 12) |
| 0.4 | 0.5 | SCRAM on the server, several users, shared memory if the benchmark asks for it, `CREDIT` if needed |
| 0.5 | 0.6 | `CHANGES`/`APPLIED`, `BATCH`/`CREDIT`, the appender, `drift`, `import`/`export` (CSV, JSON, Parquet), the protocol code shared with the machine (`modules/`) |
| later | | the analytic database: Parquet, large aggregates, TLS, users and rights |

## Questions for the author

1. **Place.** `drivers/duckdb/` in the eve-lang repository. **Answer:** (2026-10-10) evedb stays in this repository.
2. **Shared protocol code.** **Answer:** create a folder `modules` where different eve Zig projects can reuse. (`ewp.zig` is written to move there in 0.2; today it is in `drivers/duckdb/src/` because the machine does not speak EWP yet.)
3. **DuckDB library.** **Answer:** I prefer DuckDB built from source. *Status:* the prebuilt library v1.5.6 is what builds today (a source build with `zig c++` takes tens of minutes and its result is the same API); this stays until a source build is attempted. **New question A:** is the prebuilt library acceptable for 0.1?
4. **`DateTime` with a zone.** **Answer:** we store the offset in a second column.
5. **Zig tips.** **Answer:** yes, we continue to add Zig tips.
6. **Port.** **Answer:** yes, 8044.
7. **New question B: the test token.** In `--test` mode no token is needed (localhost only). Should the runner pass one anyway, so a test also checks the token path? (Proposal: no; `evedb_check.py` has its own token tests on a second server.)
8. **New question C: the `evedb://` driver.** Version 0.1 delivers the server and its tests. The Eve driver (`database "test" = "evedb://host:8044/name"`) needs the connection code of `conn.zig` to talk through frames instead of SQLite handles; proposal: `execute!`, `query!`, `query_one!` and `script` first, `table` declarations and tracked records with `CHANGES` in 0.2.
9. **New question D: the PostgreSQL face (D-186).** Done in 0.2 as the main protocol of evedb; EWP-db stays as the control port. Should EWP-db go entirely once the test runner can do the same through SQL (`select * from eve_status()`, `pragma eve_stop`)? Proposal: keep it until the change sets (`CHANGES`) are decided, then decide.
10. **New question E: `select version()`.** Some tools test `version()` for the word `PostgreSQL`. Answer `PostgreSQL 16.4 (evedb 0.2 on DuckDB v1.5.6)` (a rewrite of the call), or leave DuckDB's `v1.5.6`? Proposal: rewrite it.
11. **Question F (closed by D-187):** the names of the stored procedures and triggers of evedb: the design was dropped.
12. **Question G (closed by D-187):** no Eve host in evedb.
13. **New question H: the port of `evedb://`.** The native protocol uses the control port (8044). Give it its own name in `evedb.cfg` (`native_port`) and keep `control_port` as a second name, or keep one port? Proposal: one port, renamed `native_port` in the next version, `control_port` kept as an alias.
