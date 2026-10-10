# Design: the Eve database core (SQLite, mapping, tracked records, transactions, direct SQL)

Status: **draft for review**, 2026-10-10. Nothing here is decided. Level 5, version 0.4. Part 1 of 2; part 2 is [design-database-remote.md](design-database-remote.md) (drivers, the Eve server, remote databases, ETL). Both parts build on [design-database.md](archive/design-database.md) and the author's answers written there, and on the original memory-table model of the tutorial page databases.html. Questions for the author are at the end; the language proposals are collected in Q-046 of [decision_level5.md](decision_level5.md).

**What changed since design-database.md and Q-043.** On 2026-10-10 the author asked for a robust ORM of Eve's own: one that maps record classes to tables, validates the mapping against the real database in debug mode, refuses to run on a mismatch in production, tracks the changed fields of every record and writes only those. This replaces the proposals Q-043c and Q-043d (no mapping, `find`/`save!`/`remove!` dropped). The other points of Q-043 stay as they are: a job is a transaction (b), scripts and stored procedures (e), parallel loads by hierarchy (g), the `db` commands (h).

## 1. The layers

```
+-------------------------------------------------------+
| Local Eve App                                         |
|  - Memory Tables (Buffered Records)                   |
|  - Ingestion (XML, JSON, CSV, DAT via Unicode Streams)|
+-------------------------------------------------------+
                           |
                           v  (Eve RPC / Stream Protocol)
+-------------------------------------------------------+
| Eve Server                                            |
|  - ACID Session Manager                               |
|  - Local Database Cache                               |
+-------------------------------------------------------+
                           |
                           v  (Vendor Driver Connector)
+-------------------------------------------------------+
| Remote Database (PostgreSQL / Oracle / MySQL)         |
+-------------------------------------------------------+
```

Every box is an Eve machine or a database; every Eve machine embeds the same core. This file describes the core, which works alone on one machine with SQLite. Part 2 describes what is added when the database is remote, directly or through an Eve server.

| Layer | Where | This file | Part 2 |
|---|---|---|---|
| Record classes, `table` declarations, tracked records, sessions | every Eve program | ✓ | |
| SQLite: Eve database, cache, staging, local application data | every Eve machine | ✓ | the cache of the server |
| Transactions bound to jobs, rollback, isolation | every Eve program | ✓ | across the network |
| Direct SQL, scripts, stored procedures | every Eve program | ✓ | |
| Drivers (PostgreSQL, MySQL, …) | the machine that holds the credentials | | ✓ |
| Eve server: session manager, protocol | a listening Eve machine | | ✓ |
| ETL: ingestion, transform, transfer, reports | drivers and aspects | | ✓ |

The same Eve code runs on every layer: a script does not know whether `"sales"` is a SQLite file, a PostgreSQL server or a database behind an Eve server. Only `eve.cfg` knows.

## 2. SQLite is the core

The author decided to embed SQLite in the virtual machine (Q-043a). It is the core of the layer, not one driver among others: it is always there, it needs no server, and the conformance tests of level 5 run on it.

DuckDB is the **secondary** database and never part of the VM: it is the engine of `evedb`, a separate database server written in Zig and tuned for Eve, that plays the remote database in the tests of the remote path (part 2, and the design in [evedb/README.md](../evedb/README.md)).

### 2.1 Roles

| Role | File | Content |
|---|---|---|
| **Eve database** (system) | `db/eve.db` | run history, checkpoints, lineage, mapping fingerprints, migrations applied, the transaction journal of the server (part 2) |
| **Cache** | `db/cache.db` | copies of remote reference tables, kept by the Eve server (part 2, §4) |
| **Staging** | `db/stage.db`, connection `"stage"` | temporary tables of an ETL run: files loaded once, deduplicated and joined in SQL before the transfer (part 2, §6) |
| **Spill** | a temporary file | a memory table that grows over its capacity (§4.4) |
| **Application databases** | `db/<name>.db` | the data of small applications and services; `db create <name>` |

One file per role keeps the locks apart: a long ETL load in `stage.db` never blocks the run history in `eve.db`. A job may still write to several of them in one transaction: SQLite attaches them to one connection (`ATTACH`), and a commit over attached files in WAL mode is atomic per file only, so the rule of §8.6 (one target per transaction) applies to them too.

### 2.2 Settings chosen by the VM

| Setting | Value | Why |
|---|---|---|
| `journal_mode` | `WAL` | readers never block the writer; a crash leaves a consistent file |
| `synchronous` | `FULL` for `eve.db` and application databases, `NORMAL` for cache, stage | durability where it matters, speed where the data can be rebuilt |
| `foreign_keys` | `ON` | SQLite ignores foreign keys unless asked |
| `busy_timeout` | `$lock_timeout` (default 5s) | a second writer waits, then gets a transient `TimeoutError` |
| strict tables | `STRICT` for tables that Eve creates | SQLite otherwise stores a string in an integer column without a word |

SQLite has one writer per file. The VM opens a job that will write to a SQLite file with `BEGIN IMMEDIATE`: the write lock is taken at the start, so two jobs never deadlock by upgrading a read to a write half way. The compiler knows whether a job writes to a connection (it calls a write method or changes a tracked record); when it can't tell, the upgrade waits `busy_timeout`.

SQLite is linked from its C source by the Zig build (one amalgamation file, pinned version, recorded by `eve --version`). Every machine runs the same SQLite, so a test gives the same result everywhere.

## 3. The object model

```
Connection ─── one per connection name and per process (the session)
   │  query, query_one, execute!, script, load!   (direct SQL, untracked)
   │
   └── Table(:T) ─── one per `table` declaration: a database table seen as a buffer of records
          │  find, where, scan, count, add (<+), remove, refresh, detach, status, flush
          │
          └── T <: Record ─── a row: fields only, tracked when it comes from find or where
```

### 3.1 Records

A row type is a class derived from `Record` (author's answer to Q-043c):

```eve
class Customer = {id: Integer, name: String, city: String?, version: Integer} <: Record;
class Order    = {id: Integer, customer_id: Integer, amount: Decimal, status: String, created: Instant} <: Record;
```

- A field of type `T?` may hold `null` (a nullable column); a field of type `T` never does (D-080).
- A record literal names its type: `{id: 0, name: "Ann", city: null, version: 0} :Customer` (D-080).
- A record made by a literal is **detached**: plain data, not known to any database. A record read by `find!` or `where!` is **tracked** by the session of its connection (§6).
- A record class may declare methods (D-123), in particular `validate` (§7.4). The fields are the mapped data; methods are never mapped.

### 3.2 The `table` declaration (proposal P1)

A class says what a row is; a `table` declaration says where the rows live. It binds a record class to a table of a named connection and declares the name `customers`, an object of the library class `Table(:Customer)`:

```eve
table customers: Customer in "sales" is
  key (id);                      ** the primary key, one field or several
  generated (id);                ** filled by the database: never written, read back after insert
  version version;               ** optimistic lock: checked and increased by every update
  column name as "cust_name";    ** a field whose column has another name
end customers;

table orders: Order in "sales" is
  key (id);
  generated (id, created);
  reference customer_id to customers;   ** a foreign key: orders are written after customers
end orders;

table countries: Country in "sales";   ** short form: table name = declared name, key (id)
```

| Clause | Meaning | Default |
|---|---|---|
| `in "<connection>"` | the connection name of `eve.cfg`; `"eve"` is the Eve database | required |
| `as "<schema.table>"` after the class | the name in the database, when it differs | the declared name |
| `key (f, …)` | the primary key (or a unique key) used by `find!`, update and delete | `(id)` when the class has a field `id`, else required |
| `generated (f, …)` | columns the database fills (identity, default timestamp, trigger) | none |
| `version f` | an integer or timestamp column for optimistic locking (§8.4) | none: last writer wins |
| `column f as "<name>"` | rename one field | column name = field name |
| `reference f to t` | a foreign key to another declared table: orders the flush and is validated | none |
| `read only` | no write method; the compiler rejects `add`, `remove` and field changes | writable |
| `temporary` | (only `in "eve"` and `in "stage"`) the VM creates the table from the class at first use | the table exists |

Why a declaration and not constants in the class (design-database.md §7): a class hosts only methods (D-123), and the same record class often lives in several places (a CSV file, a staging table, a remote table). The class stays plain data; each `table` declaration is one mapping of it. A `table` is declared in a driver, a module or a macro (D-152), like a class; `table` is a contextual keyword (D-116): it is a keyword only at the start of a declaration.

The author's original model (databases.html) had a *memory table* with the same name as the database table, and the compiler complaining when the table does not exist. The `table` declaration keeps both ideas: `customers` is a memory table (the buffer of the tracked records) and the database is checked in debug mode (§5).

## 4. Column = value mapping

How a field of a record meets a column of a table, and a value meets a parameter.

### 4.1 Names

1. The column of a field is its name, or the name given by `column f as "…"`. There is no automatic case conversion and no plural rule: `Customer` maps to the table named in the declaration, `created_at` to `created_at`.
2. Generated SQL always quotes identifiers (`"cust_name"` for PostgreSQL and SQLite, `` `cust_name` `` for MySQL), so the match is exact and case sensitive, like Eve names. A column `CustName` matches only a field written `CustName` or a `column … as "CustName"`.
3. A difference of case only is reported in debug mode with the fix (`column custname as "CustName";`), never guessed.

### 4.2 Types

Every field type has a family of compatible column types. The driver knows the exact names of its database.

| Eve field | SQL column (PostgreSQL / SQLite STRICT / MySQL) | Lossless both ways |
|---|---|---|
| `Integer` (64 bits) | `bigint` / `INTEGER` / `BIGINT` | yes; `integer`, `smallint` read fine, written with a range check |
| `Natural` | `bigint` with `check >= 0` | yes |
| `Decimal` | `numeric(p, s)` / `TEXT` / `DECIMAL(p, s)` | yes; the scale is kept (`12.50d` stays `12.50`); SQLite stores the text form, never a REAL |
| `Real` | `double precision` / `REAL` / `DOUBLE` | yes |
| `Logic` | `boolean` / `INTEGER` 0-1 / `TINYINT(1)` | yes |
| `String` | `text`, `varchar(n)` / `TEXT` / `VARCHAR(n)`, `TEXT` | yes; `varchar(n)` adds a length check before the write |
| `Instant` | `timestamptz` / `TEXT` ISO 8601 UTC / `TIMESTAMP` UTC | yes |
| `DateTime` | `timestamp` + zone column, or `TEXT` with offset | yes |
| `Date`, `Time` | `date`, `time` / `TEXT` ISO / `DATE`, `TIME` | yes |
| `Duration` | `interval` / `INTEGER` nanoseconds / `BIGINT` | yes |
| `Bytes` | `bytea` / `BLOB` / `BLOB` | yes |
| `Uuid` | `uuid` / `TEXT` / `CHAR(36)` | yes |
| `T?` | the same, `NULL` allowed | `null` ⇄ `NULL` |

A pair outside this table (for example `String` field and `numeric` column) is a mapping error (§5). A pair that can lose data (`Integer` field and `numeric(30)` column) is also an error: Eve converts what the developer asked (D-080), and a mapping is an ask that must be safe for every row, not for the rows of today.

### 4.3 The mapping plan

The compiler turns each `table` declaration into a **plan**: the ordered list of `(field index, column name, converter)`. The plan is used everywhere:

- **Reading.** Eve never writes `select *`. `find!` and `where!` select the columns of the plan, in plan order, so the n-th value of a row goes to the n-th field of the plan: one converter call per value, no lookup by name per row.
- **Writing.** The parameters of an insert or an update are taken from the fields of the plan, in the same order as the columns of the statement (§7). A value is always a parameter (`?`, `$1`), never text inside the SQL.
- **Direct SQL** `query!(:T)(sql, …)`: the plan is built at the first row from the column names of the result (the same name rules), then cached for that statement; a missing or extra column is an error at the first row, with its name (design-database.md §4).

Example, for `customers` above:

| Field | Column | Converter | Written by |
|---|---|---|---|
| `id` | `id` | Integer ⇄ bigint | never (generated), used in `where!` |
| `name` | `cust_name` | String ⇄ text | insert, update when dirty |
| `city` | `city` | String? ⇄ text NULL | insert, update when dirty |
| `version` | `version` | Integer ⇄ integer | insert (1), update (`version + 1`) |

### 4.4 Memory tables and their buffer

`customers` is a `Table(:Customer)`: the buffer of the records of that table that the process holds now. The author's answer to Q-043c names `Table` the buffer of records; the same class serves without a database:

```eve
new batch := Table(:Order)(capacity: 10000);   ** a free buffer: no database, nothing tracked
let batch <+ order;                            ** append a record
for o in batch do … done;                      ** read in order
```

- A **bound** table (from a `table` declaration) holds the records its session tracks, so a second `find!(42)` returns the same record, not a second copy (the identity map). It holds clean records weakly: the VM counts references (D-151), and a clean record that the program no longer uses is freed. A changed record is held until it is written.
- A **free** table is a plain buffer for ETL. When it grows over `capacity`, it spills its oldest part to a temporary SQLite file and reads it back in order; the program sees no difference except speed.

## 5. Mapping validation: debug mode reports, production refuses

The goal of the author: recognize the database structure while developing, and crash hard in production when the code and the database disagree, before a single row is written with a wrong mapping.

### 5.1 What is checked

For every `table` declaration that the program uses (the link step knows them), against the catalog of the database (`information_schema` for PostgreSQL and MySQL, `pragma table_info` and `pragma foreign_key_list` for SQLite):

| Check | Severity |
|---|---|
| the table (or view, for `read only`) exists | error |
| every field has its column | error |
| the type pair is in the table of §4.2 and is lossless | error |
| a nullable column mapped to a field that is not optional (`String` for `text NULL`) | error: a `null` would stop the run at an unknown row |
| a `NOT NULL` column without default and without a field | error: every insert would fail |
| a column without a field, nullable or with a default | warning: never read, never written |
| `key` is the primary key or a unique key | error |
| `version` is an integer or timestamp column | error |
| `generated` fields are identity, default or trigger columns | warning |
| `reference` matches a foreign key of the database | warning (the database may have none) |
| a `varchar(n)` shorter than a value seen in debug runs | warning |
| a name that matches only when case is ignored | error, with the fix |

### 5.2 Debug mode (`eve -d`, the `debug` command)

- The **compiler** connects to each database named by a `table` declaration (the connection of `eve.cfg` on the developer's machine) and runs every check of §5.1. It collects all the differences of all the tables before it stops, so one run shows the whole picture.
- For each difference it prints the line of the declaration and a fix: the corrected field type, the `column … as` clause, or the whole class and `table` text generated from the database (the same as `db describe sales orders --eve`, design-database.md §10).
- Errors stop the compilation (exit code 65, like every compile error); warnings are printed and the run goes on.
- A table that does not exist yet can be written from the class: `db create-table sales customers` prints, and with `--apply` runs, the `create table` that matches the declaration. The ORM itself never changes a schema at run time; DDL goes through scripts (Q-043e).
- After a run without errors, the compiler records a **fingerprint** of each mapped table (a hash of its columns, types, nullability and keys) in the project (`db/mappings.json`, committed with the code).

### 5.3 Production mode (the default)

- The compiler does not connect to any database: the production database is usually not reachable from where the code is built.
- When a connection is opened for the first time in a run, before the first statement of the program goes to it, the VM reads the catalog of the tables mapped to that connection (one query per table) and runs the same checks.
- **Any error of §5.1 is a `MappingError`**: the program stops before it has read or written a row through that connection. `recover` runs, so the error is written to the run log, but `retry` and `resume` are refused for a `MappingError` (the process aborts, exit code 4): the schema will not repair itself, and a retry loop would hammer the database. Warnings go to the run log and the run continues.
- When the fingerprint of the live table differs from `db/mappings.json` but every check passes (for example a new nullable column), the run log records a **schema drift** line, so the team learns of the change before it becomes an error.
- At row level, a value that the converter can't take (a text that is not a valid UUID, a `numeric` value larger than the field allows) is a `ConvertError` with the table, the column and the key of the row: a data error, recoverable like any other.

## 6. Sessions and tracked records

### 6.1 One session per connection and per process

A **session** is the connection of one process to one connection name, with its transaction and the buffers of its bound tables. It is opened by the first use of the name in the process (a `table` method or `database.connect("sales")`) and closed when the process ends. There is no session object to pass around:

- Each process has its own sessions, so each aspect has its own connections, as the author asked (Q-043g): a started aspect never shares a session with its siblings. A session is therefore never shared state, and parallel loads need no special rule: the compiler decides thread safety on the call graph (D-089), as for any function. A concurrent aspect may read and write through its own sessions (each is local to its process) and use the shared `table` declarations, which are constants (a mapping, no data); it may not keep tracked records in a shared variable or pass a `Connection` to a started aspect. `!` plays no part in this: since D-089 it marks a stochastic result, not a write (the old reading of D-081 behind question 6 of the first draft and Q-043g (2) is obsolete).
- `database.connect("sales")` returns the `Connection` of the session, so direct SQL and tracked records of the same process run on the same connection, in the same transaction.

### 6.2 States of a record

The old tutorial page gave a record a status; it is read with `customers.status(c)`, an ordinal of the library type `RecordStatus` (a method of the table, so a column named `status` stays a plain field):

| Status | Meaning | Becomes |
|---|---|---|
| `detached` | not known to a session (made by a literal, or let go) | `added` by `customers <+ r` |
| `added` | waiting to be inserted | `clean` after the flush; `detached` by `detach` |
| `clean` | read from the database, not changed since | `dirty` by a change to a field |
| `dirty` | at least one field differs from the value read | `clean` after the flush, or when every field is changed back |
| `removed` | waiting to be deleted | `detached` after the flush |
| `stale` | an update found another version in the database (§8.4) | `clean` by `refresh` |

### 6.3 Dirty fields

Each tracked record carries a small header, invisible to the program: its session, its status, a **dirty set** (one bit per field of the plan) and the **original values** of the fields changed so far.

- `let c.city := "Lyon";` on a tracked record compares the new value with the original one. When they differ, the field's bit is set and its original value is kept (only on the first change of that field: no copy of the whole record). When the new value equals the original, the bit is cleared: setting a field back makes it clean again.
- Equality is the equality of values of the type: strings by code points, `Decimal` by value (`1.50d` equals `1.5d`, and the scale written is the new one only when the value changed), `Real` by bits (a `NaN` read and written back is not a change), records and collections are not field types.
- A change to a field of a `read only` table, a `generated` field or a `key` field is a compile error when the compiler sees it, a run-time error otherwise. Changing a key is a delete and an insert: write it so.
- Memory: the header is a few words; originals exist only for changed fields; clean records are freed when unused (§4.4). A job that reads ten million rows with `where!` and changes a few keeps only the changed ones. A read for a report uses `scan!`, which tracks nothing.

### 6.4 Methods of a bound table

| Method | Result | SQL (when) |
|---|---|---|
| `find!(key…)` | `T?`, tracked | `select <plan> from t where <key> = ?` (now, unless already in the buffer) |
| `find!(key…, lock: True)` | `T?`, tracked and locked until the commit | `… for update` (PostgreSQL, MySQL); on SQLite the job holds the write lock already |
| `where!(cond, args…)` | `Stream(:T)`, tracked | `select <plan> from t where <cond>`; flushes this table first so the job reads its own changes |
| `scan!(cond, args…)` | `Stream(:T)`, not tracked, read only | the same select, records are detached |
| `count!(cond, args…)` | `Integer` | `select count(*) …` |
| `t <+ r`, `add(r)` | none; the record is now `added` | `insert` at the flush |
| `remove(r)`, `remove(key…)` | | `delete` at the flush |
| `refresh(r)` | none; the record is `clean` | `select` now; local changes are dropped |
| `detach(r)` | none; the record is `detached` | none |
| `status(r)` | `RecordStatus` | none |
| `flush()` | none | writes the pending changes of this table now, in the transaction |
| `load!(rows, mode: "insert" \| "upsert" \| "merge")` | counts | the bulk path of the driver (§9) with the plan and the key of the declaration; the rows are not tracked |

Names follow D-089: `!` marks a stochastic result, and every read of the database is one (the same call can give other rows tomorrow), so `find!`, `where!`, `scan!`, `count!`, `query!` carry it. A write that returns nothing is a procedure-like method and has no `!` (`add`, `remove`, `refresh`, `flush`, `script`); a write that returns counts (`load!`, `execute!`) keeps it, as `Atomic.swap!` does. `!` says nothing about parallel use: the compiler decides thread safety (§6.1).

`cond` is the SQL text after `where`, with `?` placeholders and the arguments apart. A `{…}` placeholder of Eve inside it is a compile warning (SQL injection, design-database.md §4).

## 7. SQL that writes only what changed

### 7.1 The three statements

For a dirty `Customer` whose `city` changed, with the `version` clause:

```sql
update "customers" set "city" = ?, "version" = "version" + 1
where "id" = ? and "version" = ?
returning "version"
```

- `set` lists **only the dirty fields**, in plan order, then the version.
- `where!` uses the key, and the version when the table has one (§8.4).
- A record with no dirty field writes nothing. A job that reads and writes back the same values sends no `update` at all.

For an added record:

```sql
insert into "customers" ("cust_name", "city", "version") values (?, ?, 1)
returning "id"
```

- Generated fields are left out and read back with `returning` (PostgreSQL, SQLite 3.35+, MariaDB 10.5+; MySQL uses `LAST_INSERT_ID()`). Every other field is written, `null` included: an added record has no "unchanged" field.

For a removed record: `delete from "customers" where "id" = ? [and "version" = ?]`.

### 7.2 Statement cache and batches

The text of an update depends on the dirty set, so the session keeps one prepared statement per `(table, dirty set)` pair, and an insert and a delete statement per table. At a flush, the records of a table are grouped by their dirty set and each group is sent as one batch (array binding, or one multi-row statement): 10 000 records with the same changed field are one round trip, not 10 000.

### 7.3 Order of a flush

1. inserts, tables in `reference` order (customers before orders), records in the order they were added;
2. updates, in the same table order;
3. deletes, in the reverse order (orders before customers).

A cycle between `reference` clauses is a compile error; the developer breaks it with a nullable key filled by a second update.

When a flush succeeds, added records become `clean` with their generated fields filled, dirty records become `clean` and drop their originals, removed records become `detached`.

### 7.4 Validation before a write

When a record class declares `method validate(@self)`, the flush calls it for every added or dirty record before the SQL is sent. It uses `expect` and `raise` like any method; a failure is an error in the job (§8), with the record's key in the message. The database constraints stay the last word; `validate` gives a clear message before the round trip.

## 8. Transactions, commit and rollback

### 8.1 A job is a transaction

The author's answer to Q-043b: a transaction is the hidden purpose of a job. The rules:

- The first statement of a job that uses a connection begins a transaction on it (`BEGIN`, or `BEGIN IMMEDIATE` on SQLite when the job writes, §2.2). The connection is **enlisted** in the job.
- At `done` or `stop` the job **flushes** every enlisted session, then **commits** every enlisted connection. If a flush or a commit fails, the job fails (below).
- Outside a job, a tracked change or a write method is written and committed at once, one statement at a time. Debug mode warns: "write outside a job".
- Jobs are not nested (D-020), so there is no nested transaction. Savepoints are left for later (question 6).

### 8.2 When the rollback happens

| Event | Database | Tracked records in memory | Then |
|---|---|---|---|
| `done`, `stop` | flush, commit | `clean` | the process continues |
| `commit;` in the job (P2) | flush, commit, a new transaction begins | `clean`; the restore point moves here | the job continues |
| `rollback;` in the job (P3) | rollback | restored to the restore point | the job ends with status `rolled back`, the process continues after `done`; `recover` is not involved |
| an error in the job (a statement, a SQL error, `expect`, `validate`, a called routine) | rollback of every enlisted connection | restored to the restore point | `recover` runs with `$error.job` |
| `retry` in `recover` | (already rolled back) | (already restored) | the job runs again from its declarations, in a new transaction |
| `resume`, `abort` | (already rolled back) | (already restored) | as D-020 |
| a lost connection | the server rolls back by itself | restored | `DatabaseError` with `transient: True`: a case for `retry` |
| `panic`, Ctrl+C, kill, power loss | the database rolls back when the connection drops; SQLite recovers its WAL at the next open | gone | nothing runs (D-081) |

**Restoring memory** makes `retry` correct: the job runs again on the same data as the first time. At the restore point (the start of the job, or the last `commit;`) the session notes which records it tracks. A rollback puts back the original values of every field changed since, sets those records `clean` again, returns `removed` records to `clean`, and detaches the records that were added or first read since the restore point, clearing their generated fields. The old tutorial page said that memory stays changed after a rollback; with the originals kept by the dirty tracking, restoring costs little and removes a classic source of double updates.

### 8.3 Isolation and locks

- The isolation of a job is the default of the database (read committed for PostgreSQL and MySQL, serializable for SQLite), changed in the declarations of the job with a system variable (P4), in the way `$timeout` is shadowed by an aspect (D-081):

```eve
month_end: job
  set $isolation = "serializable";     ** or "read committed", "repeatable read", "snapshot"
  set $lock_timeout = 10s;
do
  …
done month_end;
```

- A serialization failure or a deadlock is a `DeadlockError`, transient: `retry`.
- `find!(key, lock: True)` locks the row until the commit (pessimistic); `$read_only = True` in the job declarations opens a read-only transaction (consistent reads for a report, no locks on PostgreSQL).

### 8.4 Optimistic locking

With `version v` in the `table` declaration, every update and delete has `and "v" = ?` with the version that was read, and every update increases it. When the statement changes no row, someone else changed the row since it was read: the record becomes `stale` and the job fails with a `ConflictError` (not transient: the same retry would fail the same way, unless the job reads the record again). Because a rollback detaches the records first read in the job (§8.2), a `retry` reads them fresh, so `retry` is right for a job that reads and then writes. A record read before the job and found stale needs `refresh`.

Without a `version` clause, the last writer wins; debug mode warns once per table that is written by more than one job of the project.

### 8.5 Long loads: `commit;` and checkpoints

A job that loads ten million rows should not hold one transaction for an hour. `commit;` inside a loop commits each batch. The risk: `retry` runs the job again from its declarations and would load the committed batches a second time. The rule: a job with `commit;` keeps a checkpoint, written **in the same transaction** as the batch, and starts from it:

```eve
** source and target are bound tables (`table` declarations); to_target is a pure function
load: job
  new since := checkpoint.read!(:Instant)("orders", db: "sales", default: Instant.epoch);
do
  for batch in source.where!("created > ?", since).batch(10000) do
    for o in batch do
      let target <+ to_target(o);
    done;
    checkpoint.write("orders", batch[-1].created, db: "sales");   ** the connection of target
    commit;                      ** the batch and the checkpoint, together
  done;
done load;
```

`checkpoint.read!` and `checkpoint.write` take the option `db:`, the connection that keeps the value (default `"eve"`); `db: "sales"` keeps it in the table `eve_checkpoint` of that database, so it commits with the batch. Debug mode warns when a job has `commit;` but writes no checkpoint and its writes are not idempotent (inserts rather than upserts). "In the same transaction" means in the same database: the checkpoint is in the target database (a table `eve_checkpoint` installed by `db prepare`), or the target is the Eve database. design-database.md §8 kept the checkpoint in the Eve database while loading a remote target: two databases, two commits, so a crash between them loads a batch twice. Either the checkpoint lives in the target, or the load is an upsert, which makes a second load of a batch harmless (at least once, but no duplicate).

### 8.6 Several databases in one job

A job may write to two connections. It commits them one after the other, in the order they were enlisted. Eve does not use two-phase commit (most open-source databases lack the coordinator, and in-doubt transactions need an administrator). If the second commit fails after the first succeeded, the job fails with a `CommitError` whose field `partial` is `True` and whose `committed` lists the connections already committed; `retry` and `resume` are refused for it, like a `MappingError`, because the job can't be undone. Debug mode warns on a job that writes to two connections. The safe patterns: one target per job (stage in one job, move in the next); or upserts on both sides so that a second run repairs the first.

## 9. Direct SQL

The ORM covers rows; everything else is SQL, as the author asked: "user can use bare SQL and handle the complexity using smart jobs". These methods of `Connection` stay as proposed in Q-043d; they run in the session's transaction and are never tracked:

| Method | Result |
|---|---|
| `query!(:T)(sql, args…)` | `Stream(:T)`; columns matched by name (§4.3) |
| `query!(sql, args…)` | `Stream(:DataMap)` |
| `query_one!(:T)(sql, args…)` | `T?` |
| `execute!(sql, args…)` | the number of rows changed |
| `load!(table, rows, mode: "insert" \| "upsert" \| "merge", key: (…))` | counts of inserted, updated, deleted rows; the bulk path of the driver |
| `script(path)` | runs a SQL file of the project (folder `sql/`), statement by statement (Q-043e) |

- A direct write on a table that has pending tracked changes flushes that table first, so the order of the program is the order in the database.
- A direct write does not update the records in the buffer; after `execute!("update customers …")` the program calls `refresh` on the records it still uses. Debug mode warns when a direct write names a table that has tracked records in the session.
- Stored procedures are declared with `external … in "sales"` (Q-043e) and run in the job's transaction.
- **Introspection** (the old page): `$query!` holds the text of the last SQL statement of the process, and in debug mode `$trace` prints every statement with its parameters (secrets masked) and its duration.

## 10. Errors

Classes of the exception module (D-081):

| Class | Fields | Transient | `retry`/`resume` |
|---|---|---|---|
| `DatabaseError` | `sqlstate`, `vendor_code`, `transient`, `sql`, `table` | depends | allowed |
| `ConnectionError` <: DatabaseError | `host` | yes | allowed |
| `ConstraintError` <: DatabaseError | `constraint`, `key` | no | allowed |
| `ConflictError` <: DatabaseError | `key`, `version` | no | allowed; a retry reads fresh records |
| `DeadlockError` (standard), `TimeoutError` (standard) | | yes | allowed |
| `ConvertError` (standard) | `table`, `column`, `key` | no | allowed |
| `MappingError` <: DatabaseError | `differences` (a list, one line each) | no | **refused**: the process aborts, exit code 4 |
| `CommitError` <: DatabaseError | `partial`, `committed` | no | **refused** when `partial` |

## 11. Language proposals

The new statements and declarations that this design needs. Each is a proposal for the author (Q-046), written with contextual keywords (D-116).

| Id | Proposal | Why |
|---|---|---|
| P1 | **`table` declaration**: `table name: Class in "connection" [as "schema.table"] is … end name;` with the clauses `key`, `generated`, `version`, `column … as`, `reference … to`, `read only`, `temporary` (§3.2) | binds a record class to a table without breaking D-123; the compiler can check it |
| P2 | **`commit;`** inside a job: flush, commit, start a new transaction (§8.5) | long loads in batches; was a statement of the old page |
| P3 | **`rollback;`** inside a job: undo to the restore point, the job ends with status `rolled back`, the process goes on (§8.2); also `rollback if $dry_run;` | dry runs, a batch that fails a business check without being an error |
| P4 | **`$isolation`, `$lock_timeout`, `$read_only`**, set in the declarations of a job (§8.3) | isolation per unit of work, in the way of `$timeout` |
| P5 | **`retry after <duration>;`** in `recover`, and the field `$error.attempt` (1 for the first run) | a deadlock or a lost connection needs a pause, and a retry needs a limit: `retry after 2s if $error.transient and $error.attempt < 5;` |
| P6 | **Fatal errors**: `retry` and `resume` are refused for a `MappingError` and a partial `CommitError` (§5.3, §8.6) | "crash hard" in production, without a retry loop |
| P7 | **Record methods**: a class derived from `Record` may declare methods, and `validate` is called before every write (§7.4) | Q-043c proposed records without methods in 0.4 |
| P8 | **Job status `rolled back`** next to passed and failed (D-020), in `jobs["name"].status` and the run log | the result of P3 |
| P9 | **`cached <duration>;`** clause of `table`: the Eve server keeps the table in its SQLite cache (part 2, §4.2) | reference data read often, changed rarely |

Not proposed, on purpose: a `transaction` block (the job is the transaction), lazy loading of related records (one call, one statement, design-database.md §7), automatic schema changes at run time (DDL goes through scripts, Q-043e), an `update record:` block as in the old page (a field assignment on a tracked record already is the update; question 5).

## 12. Example

```eve
# raise the prices of one category, with a dry run
driver reprice is
  class Product = {id: Integer, category: String, price: Decimal, version: Integer} <: Record is
    method validate(@self) is
      expect self.price > 0d;
    return;
  end Product;

  table products: Product in "shop" is
    key (id);
    version version;
  end products;

  process main(category: String, percent: Decimal, dry_run = False: Logic) is
    new changed := 0;

    reprice: job
      set $isolation = "repeatable read";
    do
      for p in products.where!("category = ?", category) do
        let p.price := (p.price * (100d + percent) / 100d).round(2);
        let changed += 1;
      done;
      print "{changed} products to change";
      rollback if dry_run;           ** P3: nothing written, the job ends rolled back
    done reprice;                    ** flush: one update per product, "set price, version"

  recover
    if $error is ConflictError do
      retry after 1s if $error.attempt < 3;    ** P5: read the products again
    else if $error is DeadlockError do
      retry after 2s if $error.attempt < 5;
    done;
    abort;
  return;
end reprice;
```

## 13. What changes

| Change | Kind |
|---|---|
| `table` declaration and its clauses (P1) | syntax, contextual keyword |
| `commit;`, `rollback;` in a job (P2, P3); job status `rolled back` (P8) | syntax and semantics of jobs (D-020) |
| `$isolation`, `$lock_timeout`, `$read_only` (P4) | system variables |
| `retry after`, `$error.attempt` (P5); fatal errors (P6) | `recover` (D-020) |
| `Record` with methods, `validate` (P7) | Q-043c |
| `Table(:T)` bound and free, `RecordStatus`, the methods of §6.4 | standard library, module `database` |
| `MappingError`, `ConflictError`, `CommitError`, `ConstraintError` | exception module |
| mapping validation in the compiler (debug) and the VM (production); `db/mappings.json` | compiler, VM |
| `db create-table` | admin command |
| SQLite in the VM, the files of §2.1, the settings of §2.2 | VM |
| F-DAT-11 kept (it was proposed for removal by Q-043d) | version map |
| tutorial databases.html rewritten from this design and part 2 | tutorial |

## Questions for the author

1. **The `table` declaration (P1).** Is a separate declaration right, or do you want the mapping in the class header, for example `class Customer = {…} <: sales.Table;` as in the old page? The declaration keeps classes plain (D-123) and lets one class map to a file, a staging table and a remote table.
**Answer:**
2. **Production check.** Verify the mapping at the first use of each connection (the catalog read costs one query per table), or only compare the fingerprint of `db/mappings.json` (cheaper, but it trusts the file)?
**Answer:**
3. **Strictness.** Is a nullable column mapped to a non-optional field an error (proposed), or a warning with a `NullError` at the row that holds a `null`?
**Answer:**
4. **Restoring memory on rollback** (§8.2): accepted, or keep the rule of the old page (memory stays changed, `refresh` by hand)?
**Answer:**
5. **`update record:` block** of the old page. Not proposed, because an assignment to a tracked field is already the update. Do you want the block anyway, for example to validate several fields together at its end?
**Answer:**
6. **Savepoints.** A job is a whole transaction; is a savepoint inside a job needed in version 0.4 (for example to skip one bad row without losing the batch), or is the rejects output of the loads (part 2, §6.3) enough?
**Answer:**
7. **Two databases in one job** (§8.6): warn and fail with `CommitError(partial)`, or forbid writing to two connections in one job?
**Answer:**
