# Database layer

Status: **0.1-draft**, level 5 (version 0.4). Sources: the author's request of 2026-10-10 (Q-046), Q-043, D-020, D-080, D-089, D-116, D-123, D-151; stored procedures, SQL functions and the database part of `eve`: D-163, D-166 (2026-10-12). Design notes: `../../design/design-database-core.md` and `../../design/design-database-remote.md`. Every rule on this page was written from the design **as proposed**: the author has not confirmed it yet, and the points that needed a choice are listed in `../../design/archive/review-2026-10-04/level5.md`. Tests: `test/level5` (prefix `e`, the database tests follow the generic ones). Grammar: `../syntax/grammar.md#database-declarations-and-statements-level-5`.

## Layers

A program reaches a database by a **connection name**. The name is declared in `eve.cfg` with a URL; the script never sees the URL, the driver or the password (D-083). The same code runs on every path:

| Path | URL | Driver runs on | Version |
|---|---|---|---|
| 1. local | `evedb://localhost/shop` | the local Eve is client and server: the core SQLite database in the VM for logs and metadata, an `evedb` (DuckDB) database for the data | 0.4 |
| 2. direct | `postgresql://etl@db1:5432/sales` | the machine of the program | 0.4 |
| 3. through an Eve server | `eve://prod/erp` | the Eve server, which holds the credentials, the sessions and a cache (an `evedb` database) | 0.5 (level 6) |
| test | `evedb://localhost/eve_test` | `evedb`, the Eve test database (DuckDB), a remote database for the tests | 0.4 |

**The database part of `eve`** (D-163, D-166). The database layer is a part of the one program `eve`, reached by `eve db …` (section "Admin commands"); `evedb` is no longer a separate program. SQLite is embedded in `eve`. The DuckDB library, the engine of `evedb` databases, is loaded only when the first DuckDB connection of a run opens: a program that uses no DuckDB database starts without it, and when the library is missing, that first connection fails with a `ConnectionError` that names it.

SQLite is the core database (Q-043a), but it **never holds ETL data** (D-159): it stores the logs and the metadata. Data is never loaded in SQLite. The roles of the files, in the `db/` folder of the **project** (D-156):

| Role | Where | Content |
|---|---|---|
| **Core database** | SQLite, default `db/local.db`; the name is set in `eve.cfg` and read as `$EVE_CORE_DB` | the logs of the ETL runs (run history, lineage), the **checkpoints**, the metadata (the mappings, the schema versions, the descriptions of the catalogs), the data of the Eve UX (`eveux`) and the journal of transactions of the machine |
| **Staging** | an `evedb` database (DuckDB), connection `"stage"` | the temporary tables of an ETL run: the files loaded once, deduplicated and joined in SQL before the transfer |
| **Cache** | an `evedb` database, kept by the Eve server | copies of remote reference tables (`cached`) |
| **Application data** | the databases that the user connects: PostgreSQL, `evedb`, … | the data |

There is no offline work: a local Eve session is connected to a remote session, or, when there is **no remote server**, the local Eve does the job and plays both the client and the server, with the core SQLite database and an `evedb` (DuckDB) database connected. The tests of level 5 run this way. The VM opens the core database with `journal_mode = WAL`, `foreign_keys = ON`, `busy_timeout = $lock_timeout`, `synchronous = FULL`, and `STRICT` for the tables that Eve creates.

## Configuration: `eve.cfg`

The connections are declared in the configuration file `eve.cfg` of the machine and of the project (the project file adds to the machine file and wins on the same name). *(Proposed: the author has given only the system variable `$EVE_CORE_DB`, D-156.)* A line has one setting; a line that starts with `#` or `**` is a comment; a value is a string in double quotes.

```
core_db = "db/local.db"                                    ** the core database, read as $EVE_CORE_DB
database "shop"  = "sqlite://db/shop.db"                 ** a connection name and its URL
database "sales" = "postgresql://etl@db1:5432/sales" exclusive
database "sales" schema_version = "select max(version) from flyway_schema_history"
```

| Setting | Meaning |
|---|---|
| `core_db = "<path>"` | the file of the core database; default `db/local.db`; its value is `$EVE_CORE_DB` |
| `database "<name>" = "<url>"` | declares a connection; the URL has the scheme of a driver (`sqlite`, `postgresql`, `evedb`, `eve`) |
| `exclusive` after the URL | Eve owns the database: `prepare`, `activate` and `reindex` work (an `evedb` database is always exclusive) |
| `database "<name>" schema_version = "<sql>"` | the query that returns the schema version of the database, for the validation of the mapping in production |

A `sqlite://` connection is also the way to keep an **application database** of a project, for example `database "cache" = "sqlite://db/cache.db"`: a local file, no server, no network, used by the local ETL (`../semantics/data-types.md#local-etl-files-and-a-local-sqlite-database`, test e56). The folder of the file is made when it is missing, and `database.connect("cache")` opens it with foreign keys on. In version 0.4 the VM reads only `sqlite://` URLs; another scheme is an error that names it.

**The mapping file `db/mappings.json`** (written by debug mode, committed with the code, read in production):

```json
{ "connections": { "shop": { "schema_version": 3, "tables": { "customers": "9f2c…" } } } }
```

`schema_version` is the version the mapping was validated against and `tables` holds the fingerprint of each mapped table. When the file or the entry of a connection does not exist, the VM reads the catalog at the first use and validates the mapping once (the run log records a warning), so a project without the file still works. A SQLite file is created at the first use of its connection, with its folder; its schema version is `PRAGMA user_version` (0 for a new file).

A password is never in the file: it is a `Secret` of the machine (`data-language.md#secrets`). A connection name that is used by a `table` or by `database.connect` and is not declared is a run-time error `$err_database` at the first use, before any statement.

## Records

A row type is a class derived from `Record`:

```eve
class Customer = {id: Integer, name: String, city: String?, version: Integer} <: Record;
```

- A field of type `T?` may hold `null`; a field of type `T` never does (D-080).
- A record class may declare methods (D-123); the fields are the mapped data, methods are never mapped. A method `validate(@self)` is called before every write (section "Validation").
- A record made by a literal, `{id: 0, name: "Ann", city: null, version: 0} :Customer`, is **detached**: plain data. A record read by `find!` or `where!` is **tracked** by the session of its connection.

## The `table` declaration

A class says what a row is; a `table` declaration says where the rows live. It binds a record class to a table of a named connection and declares a name, an object of the library class `Table(:Class)`. `table` is a contextual keyword (D-116): a keyword only at the start of a declaration. A `table` is declared in a driver, an aspect, a module or an Eve macro, like a class.

```eve
table customers: Customer in "sales" is
  key (id);
  generated (id);
  version version;
  column name as "cust_name";
end customers;

table orders: Order in "sales" is
  key (id);
  generated (id, created);
  reference customer_id to customers;
end orders;

table countries: Country in "sales";            ** short form: key (id), no other clause
```

| Clause | Meaning | Default |
|---|---|---|
| `in "<connection>"` | the connection name of `eve.cfg`; `"eve"` is the Eve database | required |
| `as "<schema.table>"` after the class | the name in the database when it differs from the declared name | the declared name |
| `key (f, …)` | the primary key or a unique key, used by `find!`, update and delete | `(id)` when the class has a field `id`, else required |
| `generated (f, …)` | columns the database fills (identity, default, trigger): never written, read back after an insert | none |
| `version f` | an integer or timestamp column for optimistic locking | none: the last writer wins |
| `column f as "<name>"` | the column of a field that has another name | the field name |
| `reference f to t` | a foreign key to another declared table: orders the flush, is validated | none |
| `read only` | no write method; `add`, `remove` and a change of a field are errors | writable |
| `temporary` | only `in "stage"`: the VM creates the table from the class at first use. A user table is never in the core database (`"eve"`), whose tables are Eve's own and `read only` | the table exists |
| `cached <duration>` | the Eve server keeps the table in its cache (an `evedb` database) and refreshes it after the duration (version 0.5) | not cached |

**Compile errors and their messages** (exit code 65; the tests check the words in bold, an implementation may add to them):

| Error | Message |
|---|---|
| an unknown field in `key`, `generated`, `version`, `column` or `reference` | `**unknown field** {name} in {clause} of {table}` |
| a cycle of `reference` clauses | `**reference cycle**: {tables}` |
| `temporary` outside the staging database | `**temporary is allowed only** in the staging database` |
| `commit;` or `rollback;` outside the `do` region of a job | `**commit is allowed only in a job**` (likewise `rollback`) |
| a change of a `key` or `generated` field | `field {name} **can not be changed**` |
| `add` or a change on a `read only` table | `table {name} **is read only**` |
| a job that writes to two connections | `job {name} writes to {a} and {b}: **one connection per job**` |
| a `null` for a field that is not optional | `{field} is not optional` |

Also compile errors: `generated` or `version` on a key field, and a table declared twice with the same name. A cycle of `reference` clauses is broken with a nullable key filled by a second update.

## Column = value mapping

1. The column of a field is its name, or the name of `column f as "…"`. There is no case conversion and no plural rule. Generated SQL always quotes identifiers, so the match is exact and case sensitive. A difference of case only is reported with the fix, never guessed.
2. Every field type has a family of compatible column types:

| Eve field | Column (PostgreSQL / SQLite STRICT / MySQL) | Lossless |
|---|---|---|
| `Integer` | `bigint` / `INTEGER` / `BIGINT` | yes; narrower integers are read fine and written with a range check |
| `Natural` | `bigint` with `check >= 0` | yes |
| `Decimal` | `numeric(p, s)` / `TEXT` / `DECIMAL(p, s)` | yes, the scale is kept (`12.50d` stays `12.50`); SQLite stores the text form, never a `REAL` |
| `Real` | `double precision` / `REAL` / `DOUBLE` | yes |
| `Logic` | `boolean` / `INTEGER` 0-1 / `TINYINT(1)` | yes |
| `String` | `text`, `varchar(n)` | yes; `varchar(n)` adds a length check before the write |
| `Instant` | `timestamptz` / `TEXT` ISO 8601 UTC / `TIMESTAMP` UTC | yes |
| `DateTime` | `timestamp` and a zone column, or `TEXT` with offset | yes |
| `Date`, `Time` | `date`, `time` / `TEXT` ISO | yes |
| `Duration` | `interval` / `INTEGER` nanoseconds / `BIGINT` | yes |
| `Bytes` | `bytea` / `BLOB` | yes |
| `Uuid` | `uuid` / `TEXT` / `CHAR(36)` | yes |
| `T?` | the same type, `NULL` allowed | `null` ⇄ `NULL` |

A pair outside this table (a `String` field and a `numeric` column) is a mapping error. So is a pair that can lose data (an `Integer` field and a `numeric(30)` column): a mapping is an ask that must be safe for every row, not for the rows of today.

3. The compiler turns each `table` declaration into a **plan**: the ordered list of `(field, column, converter)`. Eve never writes `select *`: a read selects the columns of the plan in plan order, and a write takes its parameters from the fields of the plan in the order of the statement. A value is always a parameter, never text inside the SQL.
4. For direct SQL, `query!(:T)(sql, …)` builds the plan at the first row from the names of the result columns, with the same name rules; a missing or an extra column is an error at the first row, with its name.

## Mapping validation

The goal: recognize the database structure while developing, and stop hard in production when the code and the database disagree, before a single row is written with a wrong mapping.

| Check | Severity |
|---|---|
| the table (a view, for `read only`) exists | error |
| every field has its column | error |
| the type pair is in the table above and is lossless | error |
| a nullable column mapped to a field that is not optional | error |
| a `NOT NULL` column without default and without a field | error |
| a column without a field, nullable or with a default | warning |
| `key` is the primary key or a unique key | error |
| `version` is an integer or timestamp column | error |
| `generated` fields are identity, default or trigger columns | warning |
| `reference` matches a foreign key of the database | warning |
| a `varchar(n)` shorter than a value seen in debug runs | warning |
| a name that matches only when case is ignored | error, with the fix |

- **Debug mode** (`eve -d`, the `debug` command): the compiler connects to every database that a `table` names and runs all the checks. It collects the differences of all the tables before it stops, prints for each one the line of the declaration and a fix (the corrected field, the `column … as` clause, or the class and `table` text generated from the database, as `db describe <name> <table> --eve` prints them). Errors stop the compilation (exit code 65), warnings are printed. After a run without errors, the compiler writes the **mapping** to `db/mappings.json`, which is committed with the code: for each connection the schema version of the database it was validated against, and for each mapped table a fingerprint (a hash of its columns, types, nullability and keys).
- **Production mode** (the default): the compiler does not connect, and the VM **trusts the file** `db/mappings.json` (D-158). The database carries a **schema version**, a number that `db migrate` raises with every migration (SQLite and `evedb`: their own version number; other databases: the query `schema_version` that the connection gives in `eve.cfg`, for example the migration table of the DBA, because **Eve installs no table in a target database** (D-159); with no query, the version is a hash of the catalog, read once at the first use), and the mapping file records the schema version it was validated against, per connection. When the VM opens a connection for the first time, before the first statement of the program goes to it, it reads the schema version (one cheap query) and compares it with the file. **Equal:** the mapping is trusted and no catalog is read. **Different:** the program stops with a `MappingError` ("schema version {a}, mapping validated for {b}: validate the mapping again"), and the user validates the mapping again in debug mode (`eve -d`, or `db validate <name>`) and commits the new file. A `MappingError` stops the program before it has read or written a row through that connection. `recover` runs, so the error is written to the run log, but `retry` and `resume` are refused (the process aborts, exit code 4). The checks of the table above run only in debug mode. A change made to the database outside `db migrate` does not change the schema version: the run does not see it, and debug mode finds it.
- A value that the converter can't take at row level (a text that is not a UUID, a number larger than the field) is a `ConvertError` with the table, the column and the key of the row: a data error, recoverable like any other.

## Sessions and tracked records

A **session** is the connection of one process to one connection name, with its transaction and the buffers of its bound tables. It is opened by the first use of the name in the process (a method of a `table`, or `database.connect("sales")`) and closed when the process ends. Each process has its own sessions, so each aspect has its own connections: a started aspect never shares a session with its siblings. A session is never shared state, so parallel loads need no special rule: the compiler decides thread safety on the call graph (D-089), `!` plays no part in it. A concurrent aspect may use the shared `table` declarations (constants, no data); it may not keep tracked records in a shared variable or pass a `Connection` to a started aspect.

### States of a record

`customers.status(c)` gives an ordinal of the library type `RecordStatus`:

| Status | Meaning | Becomes |
|---|---|---|
| `detached` | not known to a session | `added` by `customers <+ r` |
| `added` | waiting to be inserted | `clean` after the flush; `detached` by `detach` |
| `clean` | read from the database, not changed since | `dirty` by a change to a field |
| `dirty` | at least one field differs from the value read | `clean` after the flush, or when every field is changed back |
| `removed` | waiting to be deleted | `detached` after the flush |
| `stale` | an update found another version in the database | `clean` by `refresh` |

### Dirty fields

A tracked record carries a header the program can't see: its session, its status, a **dirty set** (one bit per field of the plan) and the **original values** of the fields changed so far.

- `let c.city := "Lyon";` compares the new value with the original. When they differ, the bit is set and the original is kept (only at the first change of that field). When the new value equals the original, the bit is cleared: a field set back makes the record clean again.
- Equality is the equality of values of the type: strings by code points, `Decimal` by value (`1.50d` equals `1.5d`), `Real` by bits (a `NaN` read and written back is not a change).
- A change to a field of a `read only` table, a `generated` field or a `key` field is a compile error when the compiler sees it, a run-time error otherwise. Changing a key is a delete and an insert: write it so.
- The memory of a bound table is an identity map: a second `find!(42)` returns the same record. Clean records are held weakly (the VM counts references, D-151), so a clean record the program no longer uses is freed; a changed record is held until it is written. A report uses `scan!`, which tracks nothing.

### The `update` block

`update c do … done;` changes several fields of one tracked record without repeating its name (D-158):

```eve
new c := customers.find!(42);
update c do
  let city := "Lyon";            ** the field c.city
  let name := "Ann Smith";       ** the field c.name
done;
```

Inside the block, the names of the fields of the record are in scope, and `let city := v;` sets the field `city` of the record `c`. The block is a way of writing: the record is the same tracked record, the dirty rules and the statements sent are the same as for `let c.city := v;`. At `done` the method `validate` of the record runs, so the error is found at the end of the block, with all the fields changed together. The record may be of a bound table or detached. Changing a `key`, a `generated` field or a field of a `read only` table is an error, as everywhere. A block works on **one** record; to change two records, write two blocks (a field name always means the field of the innermost block). The target is a record; a set-based update of a whole table is SQL (`execute!`).

### Methods of a table

| Method | Result | SQL (when) |
|---|---|---|
| `find!(key…)` | `T?`, tracked | `select <plan> … where <key> = ?` now, unless the record is in the buffer |
| `find!(key…, lock: True)` | `T?`, tracked, locked until the commit | `… for update` (PostgreSQL, MySQL); on SQLite the job holds the write lock already |
| `where!(cond, args…)` | `Stream(:T)`, tracked | `select <plan> … where <cond>`; flushes this table first so the job reads its own changes |
| `scan!(cond, args…)` | `Stream(:T)`, not tracked | the same select, the records are detached |
| `count!(cond, args…)` | `Integer` | `select count(*) …` |
| `t <+ r`, `add(r)` | none; the record is `added` | `insert` at the flush |
| `remove(r)`, `remove(key…)` | none | `delete` at the flush |
| `refresh(r)` | none; the record is `clean` | `select` now; local changes are dropped |
| `detach(r)` | none; the record is `detached` | none |
| `status(r)` | `RecordStatus` | none |
| `flush()` | none | writes the pending changes of this table now, in the transaction |
| `load!(rows, mode: "insert" \| "upsert" \| "merge")` | counts | the bulk path of the driver, with the plan and the key of the declaration; the rows are not tracked |
| `prepare(tables)`, `activate(tables)`, `reindex(tables)` | none | disable, enable and rebuild the indexes, constraints and triggers of a bulk load (a method of `Connection`). Only on a connection that Eve owns: an `evedb` database or a connection with `exclusive` in `eve.cfg`. On any other connection they do nothing and the run log gets a warning: the constraints stay on, the load works, slower, and gives more failures on an active database |

Names follow D-089: `!` marks a stochastic result, and every read of a database is one (the same call can give other rows tomorrow), so `find!`, `where!`, `scan!`, `count!` and `query!` carry it. A write that returns nothing has no `!` (`add`, `remove`, `refresh`, `flush`, `script`, `prepare`, `activate`, `reindex`); a write that returns counts keeps it (`load!`, `execute!`). `cond` is the SQL text after `where`, with `?` placeholders and the arguments apart; a `{…}` placeholder of Eve inside it is a compile warning (SQL injection).

A **free** table, `new batch := Table(:Order)(capacity: 10000);`, is a plain buffer for ETL with no database: `let batch <+ order;` appends and `for o in batch do … done;` reads in order. When it grows over `capacity` it spills its oldest part to a temporary SQLite file and reads it back in order.

## SQL that writes only what changed

For a dirty record whose `city` changed, with a `version` clause:

```sql
update "customers" set "city" = ?, "version" = "version" + 1
where "id" = ? and "version" = ?
returning "version"
```

- `set` lists **only the dirty fields**, in plan order, then the version. `where` uses the key and the version when the table has one. A record with no dirty field writes nothing.
- An **insert** leaves the generated fields out and reads them back (`returning`, or `LAST_INSERT_ID()` for MySQL); every other field is written, `null` included.
- A **delete** is `delete from … where <key> [and <version>]`.
- The session keeps one prepared statement per `(table, dirty set)` pair. At a flush the records of a table are grouped by their dirty set and each group is sent as one batch (array binding or one multi-row statement).
- **Order of a flush:** inserts in `reference` order (customers before orders), then updates in the same order, then deletes in the reverse order. When a flush succeeds, added records become `clean` with their generated fields filled, removed records become `detached`.

### Validation

When a record class declares `method validate(@self)`, the flush calls it for every added or dirty record before the SQL is sent. It uses `expect` and `raise` like any method; a failure is an error in the job, with the key of the record in the message. The constraints of the database stay the last word.

## Transactions

**A job is a transaction** (Q-043b). The first statement of a job that uses a connection begins a transaction on it (`BEGIN`, or `BEGIN IMMEDIATE` on SQLite when the job writes); the connection is **enlisted** in the job. At `done` or `stop` the job flushes every enlisted session, then commits every enlisted connection; a failed flush or commit fails the job. Outside a job a tracked change or a write method is written and committed at once, one statement at a time (debug mode warns). Jobs are not nested (D-020), so there is no nested transaction and no savepoint in version 0.4.

| Event | Database | Tracked records in memory | Then |
|---|---|---|---|
| `done`, `stop` | flush, commit | `clean` | the process continues |
| `commit;` in the job | flush, commit, a new transaction begins | `clean` | the job continues |
| `rollback;` in the job | rollback | keep their values; the records of the job are detached | the job ends with status `rolled back`, the process continues after `done`; `recover` is not involved |
| an error in the job (a statement, SQL, `expect`, `validate`, a called routine) | rollback | keep their values; the records of the job are detached | `recover` runs with `$error.job` |
| `retry` in `recover` | (already rolled back) | (already detached) | the job runs again from its declarations, in a new transaction |
| `resume`, `abort` | (already rolled back) | (already detached) | as in `../semantics/errors.md#recover` |
| a lost connection | the server rolls back | keep their values; detached | `DatabaseError` with `transient: True` |
| `panic`, Ctrl+C, kill, power loss | the database rolls back when the connection drops; SQLite recovers its WAL at the next open | gone | nothing runs (D-081) |

**Memory after a rollback** (D-158). A rollback does not change the records in memory: their fields keep the values they had, also the changed ones. The records that the job read, added or changed are **detached** (plain data, no longer tracked), because they may not match the database any more. The program decides what to do: read the data again from the database (`find!` gives a new record), make another record, compare the two to find what went wrong, or discard the changes by hand. A `retry` runs the job again from its declarations, and its reads give fresh records.

**Statements.** `commit;` and `rollback;` are contextual keywords (D-116), allowed only in the `do` region of a job at the top level of a process; both take the conditional suffix, `rollback if dry_run;`. The job status `rolled back` is a value of `jobs["name"].status` next to `"pass"` and `"fail"`, and is written to the run log.

**Isolation and locks** are the defaults of the database (read committed for PostgreSQL and MySQL, serializable for SQLite). A job changes them in its declarations with the system variables `$isolation` (`"read committed"`, `"repeatable read"`, `"serializable"`, `"snapshot"`), `$lock_timeout` (a duration) and `$read_only` (a `Logic`: a read-only transaction, a consistent snapshot, no locks on PostgreSQL), shadowed in the job as `$timeout` is shadowed by an aspect (D-081). A serialization failure or a deadlock is a `DeadlockError`, transient.

**Optimistic locking.** With `version v`, a new row is written with the version 1, every update and delete has `and "v" = ?` with the version that was read, and every update increases it by 1. When the statement changes no row, someone else changed the row: the record becomes `stale` and the job fails with a `ConflictError` (not transient). A rollback detaches the records of the job (see above), so a `retry` reads them fresh. Without `version` the last writer wins; debug mode warns once per table written by more than one job of the project.

**Long loads.** A job that loads millions of rows commits each batch with `commit;`. A `retry` would run the job again from its declarations and load the committed batches twice, so a job with `commit;` keeps a **checkpoint** in the core database, written after the commit of the batch, and starts from it. The checkpoint and the batch are in two databases, so a crash between the two commits loads the last batch a second time: the writes of a batch must be **idempotent** (`mode: "upsert"` or `"merge"` by key; at least once, effectively once):

```eve
load: job
  new since := checkpoint.read!(:Instant)("orders", default: Instant.epoch);
do
  for batch in source.where!("created > ?", since).batch(10000) do
    for o in batch do
      let target <+ to_target(o);
    done;
    commit;
    checkpoint.write("orders", batch[-1].created);
  done;
done load;
```

`checkpoint.read!` and `checkpoint.write` use the core database: Eve does not install a checkpoint table in a target (D-159), and a write to the core database (logs, checkpoints) is not counted as the write connection of the job. Debug mode warns when a job has `commit;` and its writes are not idempotent (inserts rather than upserts).

**One connection per job** (D-158). A job writes to one connection. It may read from other connections: the transaction there only reads, and there is nothing to commit. A write to a second connection is a compile error when the compiler sees it (`job {name} writes to {a} and {b}: one connection per job`), a run-time `DatabaseError` otherwise. To move data between two databases, use two jobs: stage in one job, move in the next. Writing to two databases in one job is not supported in version 0.4; it is technical debt in `../../design/backlog.md`.

**Batch errors.** When some records of a batch fail (a constraint, a conversion, `validate`) in `flush()` or `load!`, the batch is rolled back and the job fails with a `BatchError`. Its field `failed` is a collection of `{key, reason}`, one for each failing record, and `recover` reads it as `$error.failed`: it can count the failures, log the records and decide. `retry` runs the job again from its declarations: with `commit;` and a checkpoint per batch (above), the batches already committed are not processed again, only the failed batch and the ones after it. `resume` ends the job as failed and the process goes on after `done`.

## Direct SQL

Everything that is not rows is SQL. These methods of `Connection` run in the transaction of the session and are never tracked:

| Method | Result |
|---|---|
| `query!(:T)(sql, args…)` | `Stream(:T)`, columns matched by name |
| `query!(sql, args…)` | `Stream(:DataMap)` |
| `query_one!(:T)(sql, args…)` | `T?` |
| `execute!(sql, args…)` | the number of rows changed |
| `load!(table, rows, mode: …, key: (…))` | counts of inserted, updated and deleted rows |
| `script(path)` | runs a SQL file of the project (folder `sql/`), statement by statement |

A direct write on a table with pending tracked changes flushes that table first. It does not update the records in the buffer: the program calls `refresh`; debug mode warns when a direct write names a table that has tracked records. Native stored procedures are declared with `external` and run in the transaction of the job (section "Stored procedures"). `$query` holds the text of the last SQL statement of the process, and in debug mode `$trace` prints every statement with its parameters (secrets masked) and its duration.

## Stored procedures

There are two kinds of stored procedures (D-166):

| Kind | Written in | Folder of the project | Runs in | Called from Eve |
|---|---|---|---|---|
| **native** | the language of the database: PL/pgSQL, PL/SQL, T-SQL, … | `sql/` | the database | through an `external` declaration |
| **Eve procedure** | Eve | `proc/` | the database part of `eve`, next to a SQLite or DuckDB database | as a module; over IPC with `db.call` |

**Native procedures.** The files of `sql/` are sent to the database by `script(path)`, `eve db script` or `eve db migrate`; Eve does not read their language. A program calls a native procedure through an `external` declaration, which brings only its signature into Eve (Q-043e):

```eve
external procedure archive_orders(before: Date) in "sales";
external function total_sales!(region: String) => (@total: Decimal) in "sales" as "etl.total_sales";
```

- A procedure without a result is an `external procedure`. One with a result is an `external function` whose name ends with `!`, because its result depends on the database (D-087).
- The name in the database is the Eve name, or the string after `as`.
- The call runs in the transaction of the job, like `execute!`. The arguments and the results are converted by the column = value mapping; a database error is a `DatabaseError`.
- This works for every database that has stored procedures. For the databases other than SQLite and DuckDB, this is the only kind: the database part of `eve` is a wrapper that sends the call.

**Eve procedures.** A module in the folder `proc/` of a project is a module of Eve stored procedures: its exported procedures and functions are the procedures. The forms of the call below were proposed with D-166 and chosen as the most convenient (author, 2026-10-12).

```eve
module orders is
  export (archive, total!);

  procedure archive(before: Date) is
    ...
  return;
  ...
end orders;
```

- The database part checks the modules of `proc/` with the compiler, keeps them compiled and runs them next to a SQLite or DuckDB database: in the process of a direct run (`eve -x`), and in the database part of the machine with `-loc` and on a serving machine (`machine.md`). On an Eve server (path 3, level 6) they run on the server, near its databases.
- A program calls them as a module, `from proc use (orders);` and then `orders.archive(cutoff);`. The call runs in the transaction of the job that makes it.
- Over IPC, `db.call` runs one: `{"name": "orders.archive", "args": ["2026-01-01"]}` (`machine.md`).
- `eve db proc list` prints the modules of `proc/`, their exported procedures with their signatures, and the hash of each module. `eve db proc reload` reads `proc/` again on a serving machine; a call that is running finishes with the code it started with.
- An exported function of `proc/` that is a `sql function` can also be called from SQL (next section).

## SQL functions

A `sql function` is an Eve function that SQLite and DuckDB can call from SQL (D-166). `sql` is a contextual keyword (D-116): a keyword only before `function`, a free name elsewhere.

```eve
sql function tax(amount: Decimal, country: String) => (@result: Decimal) is
  let result := amount * rate(country);
return;
```

```eve
class Taxed = {id: Integer, tax: Decimal} <: Record;
new rows := shop.query!(:Taxed)("select id, tax(amount, country) as tax from orders");
```

- **Registration.** When the database part opens a SQLite or DuckDB connection, it registers **every** `sql function` of the program (the driver, its aspects, the modules it imports, and the modules of `proc/`), through the C API of the engine: `sqlite3_create_function_v2` for SQLite, the scalar functions of DuckDB. The name in SQL is the Eve name; a connection opened before a module is loaded gets its functions when the module is loaded.
- **Rules checked by the compiler.** A `sql function` has no `!`: it is deterministic (D-087), and it does no input or output and opens no connection. It is not generic and not overloaded: SQL finds a function by its name. It has exactly one result. Its parameters and its result have the types of the column = value mapping (section "Column = value mapping"). **SQL `NULL` maps only to a nullable type:** a parameter of type `T?` receives `NULL` as `null`, and a result of type `T?` that is `null` is returned as `NULL`. When SQL gives `NULL` to a parameter of type `T`, the mapping fails: the function is not called and the statement stops with `$err_sql` (below).
- **Errors.** An error in a `sql function` is an exception that stops the query: the engine abandons the statement, and the method that ran it (`query!`, `query_one!`, `execute!`, `load!`) raises the error **`$err_sql`** (code 59, class `SqlError` <: `DatabaseError`). Its message names the function and gives the message of the Eve error, or the reason the mapping failed: `SQL function tax failed: Division by zero`. Like any database error it can be recovered, retried or resumed.
- **Threads.** An engine may call a `sql function` from several threads at once: DuckDB runs a query on worker threads. The VM protects the session: it runs one call at a time with a session mutex, or hands the calls to a pool of interpreters that each own their heap (D-166). The order and the number of the calls are not specified; this is why a `sql function` has no `!`.
- **Other databases.** PostgreSQL, MySQL and the other drivers get no Eve functions. For them a `sql function` is an ordinary Eve function: the program reads the data into the process, changes it in Eve and writes it back with `load!` (in bulk) or one row at a time.

## Errors

| Class | Fields | Transient | `retry` and `resume` |
|---|---|---|---|
| `DatabaseError` | `sqlstate`, `vendor_code`, `transient`, `sql`, `table` | depends | allowed |
| `ConnectionError` <: `DatabaseError` | `host` | yes | allowed |
| `ConstraintError` <: `DatabaseError` | `constraint`, `key` | no | allowed |
| `ConflictError` <: `DatabaseError` | `key`, `version` | no | allowed; a retry reads fresh records |
| `DeadlockError`, `TimeoutError` | | yes | allowed |
| `ConvertError` | `table`, `column`, `key` | no | allowed |
| `MappingError` <: `DatabaseError` | `differences` (a list, one line each) | no | **refused**: the process aborts, exit code 4 |
| `BatchError` <: `DatabaseError` | `failed` (a collection of `{key, reason}`), `batch` | no | allowed: a retry starts from the checkpoint |
| `CommitError` <: `DatabaseError` | `transaction` | no | **refused**: the answer to `COMMIT` was lost and the status can not be found |

A driver classifies a native error: a lost connection (`08xxx`), a serialization failure (`40001`), a deadlock (`40P01`, MySQL 1213) and a lock time-out are transient; a constraint (`23xxx`) and a syntax error (`42xxx`) are not.

## Drivers and the server

**The evedb driver** (version 0.5, level 6, D-187). A connection whose URL starts with `evedb://` (`database "wh" = "evedb://host:8044/warehouse"`, `evedb://token@host:8044/warehouse` for a server with a token) speaks the native protocol of evedb, the server that owns the DuckDB databases. It has the methods of the other drivers (`execute!`, `query!`, `query_one!`, `script`, `close`, the transaction of a job) with typed parameters, and the fast path for large data: `s.store(wh, select, params…)` and `s.load(wh, name)` on a `Memory` table move the rows as column batches (`data-engines.md`). Details: `../../evedb/README.md` sections 5.5 and 5C; tests: `test/level6/f02_evedb_columnar`.

**The PostgreSQL driver** (version 0.5, level 6, D-186). A connection whose URL starts with `postgres://` or `postgresql://` (`database "shop" = "postgres://user:password@host:5432/shop"`) speaks the PostgreSQL protocol, to a PostgreSQL server or to evedb, the Eve test database that answers as one. The login is trust, password, md5 or SCRAM-SHA-256; there is no TLS yet. On such a connection `execute!`, `query!`, `query_one!`, `script` and `close` work as on SQLite, and a job begins a transaction at its first statement and commits or rolls it back at its end. The parameters `?` are sent as literals with their quotes doubled. `table` declarations, tracked records and `import` work on SQLite connections only: on a PostgreSQL connection they are an error. Details: `../../evedb/README.md` section 5B; tests: `test/level6/f01_pg_driver`, `script/pg_check.py`.

A driver implements one interface: `open`/`close`, `begin`/`commit`/`rollback`, `prepare`/`bind`/`step`, `execute_batch`, `bulk_load`, `describe` (the catalog, for the validation), the dialect (`quote`, `placeholder`, `returning`), the type map and `classify`. Order: SQLite (embedded) and PostgreSQL in version 0.4 (Supabase and Neon speak its protocol); MySQL and MariaDB, Cloudflare D1 in 0.5; MongoDB later, with an API of its own. Oracle is postponed (backlog); SQL Server by the community through the interface.

Path 3 (version 0.5, level 6): the **Eve server** holds the sessions, the drivers and the cache. A remote session has a lease (30 s by default) renewed by `PING`, and a lease that runs out rolls back the transaction. Each transaction has an id chosen by the client, kept in the journal of the core database of the server. Eve installs no table in the target database, so after a break at `COMMIT` the client asks `STATUS <id>` and the server asks the database when the driver can answer (PostgreSQL: `txid_status`): committed means the job passed, rolled back means a transient `ConnectionError` (so `retry` is right). When the driver can not answer, the status is "unknown" and the job fails with a fatal `CommitError`: an administrator checks. Only the dirty columns travel in a `CHANGES` frame. The frames `OPEN`, `BEGIN`, `QUERY`, `CHANGES`, `APPLIED`, `COMMIT`, `ROLLBACK` and `STATUS` extend EWP (`../../design/design-service.md`). A **cached** table (`cached 1h;`) is read from the cache of the server (an `evedb` database) and written through to the remote database; the cache is never the authority, and `db cache list`, `refresh` and `clear` administer it.

## Admin commands

The commands are words of the database part: `eve db <command>` (D-163). `db list`, `db add`, `db remove`, `db test`, `db info`, `db tables`, `db describe`, `db sql`, `db import`, `db export` (files into and out of a table: see [data-engines.md](data-engines.md)), `db script`, `db create`, `db create-table`, `db migrate`, `db backup`, `db prepare`, `db activate`, `db reindex` (these three only on an exclusive connection), `db validate`, `db cache` (Q-043h), `db proc list`, `db proc reload` (D-166), `db serve` (the test database of the remote path, the former `evedb serve`). `db sql` and `db script` run with the rights of the database user of the connection (Q-043f). Schema changes go through scripts and `db migrate` (`db/migrations/<name>/`); the ORM never changes a schema at run time.

## Open points

All in `../../design/archive/review-2026-10-04/level5.md` and in Q-043 and Q-046 of `../../design/decision/level5.md`: the shape of the `table` declaration, the production check at first use, nullable columns against non-optional fields, the restore of memory on rollback, savepoints, two databases in one job, Oracle (postponed), the client cache (no), 
