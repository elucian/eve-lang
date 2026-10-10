# Design: the Eve database layer and the Eve database

Status: **superseded and archived on 2026-10-10.** The main design is now [design-database-core.md](../design-database-core.md) (SQLite, the ORM, transactions, direct SQL), [design-database-remote.md](../design-database-remote.md) (drivers, the Eve server, ETL) and [evedb/README.md](../../evedb/README.md) (DuckDB as the secondary database: the Eve test database). This file stays as the record of the author's answers. Two of its premises are obsolete: DuckDB is not an option of the VM (answer to question 1: it is the separate project `evedb`), and question 6 reads `!` as "unsafe for parallel" (D-081), which D-089 replaced: `!` marks a stochastic function and the compiler decides thread safety.
First draft: 2026-10-05. Nothing here is decided. Level 5, version 0.4 (`plan/version_map.md`), before the server (level 6). Features F-DAT-01 to F-DAT-11 (`plan/version_map.md`). It replaces the ORM sketch of the tutorial page databases.html (review RIO-D02, RIO-X01, RIO-R02). Questions for the author are collected at the end.

## 1. Why the database layer is the core of Eve

An ETL tool exists to move data between databases reliably: read from one or several sources, transform, and load into a target, again and again, without losing a row and without loading one twice. Every other feature of Eve (jobs with `retry`, aspects, parallel groups, streams, the run log, the machine and its scheduler) serves this movement. The database layer is where these features meet the data.

The design has two parts:

1. **The database layer**: how a script connects to databases, reads, writes, loads in bulk, and keeps transactions, for any supported database (PostgreSQL, Oracle, MySQL, SQL Server, SQLite).
2. **The Eve database**: a database that belongs to each Eve machine, kept in its machine folder, for the data of Eve itself (staging tables, checkpoints, run history, lineage, cached datasets) and for small applications. It is administered with machine commands (section 9).

## 2. Principles

- **SQL first.** Eve talks to a database in SQL, with parameters. No hidden ORM that writes SQL behind the developer's back; a light mapping between record types and tables is optional (section 7).
- **Streams, not lists.** A query returns a stream of rows read in batches; a 100-million-row table never has to fit in memory (`Stream(:T)`, review RMT-R02).
- **Set-based loads.** Writing many rows is one bulk operation (insert, upsert, merge), not a loop of single inserts.
- **Typed rows.** A row is a record of a declared type, so the compiler checks field names and the VM converts column types (Decimal for `NUMERIC`, Instant for timestamps).
- **Jobs are transactions.** A job that writes to a database commits when it ends at `done` and rolls back when it fails; `recover` decides to `retry` (D-020). A transient error (lost connection, deadlock) is a natural `retry`.
- **Restartable.** A long load records checkpoints, so a run that failed restarts at the last committed batch, not at the beginning (F-DAT-04).
- **Credentials never in scripts.** Connections are named in the configuration of the machine; passwords are secrets.

## 3. Connections

A connection is named in the configuration of the machine (`eve.cfg`) and opened by its name. The script never contains an address or a password:

```
# eve.cfg (sketch)
database "sales"   = "postgresql://etl@db1.example.com:5432/sales"
database "erp"     = "oracle://etl@erp.example.com:1521/ERP"
database "eve"     = "eve://local"          ** the Eve database of this machine
secret   "sales"   = file "secrets/sales.key"
```

```eve
new sales := database.connect("sales");      ** a Connection, from the configuration
defer sales.close();                         ** released at the end, by any path (D-081)
```

- A connection is an object of the class `Connection` of the standard module `database`.
- A pool of connections per name is kept by the machine; `connect` takes one from the pool.
- `database.connect` raises a `DatabaseError` (class of D-081) with the code of the database when it fails.

## 4. Reading: queries as streams

```eve
# typed rows: a record type declared once
class Order = {id: Integer, customer: String, amount: Decimal, created: Instant} <: Record;

new rows := sales.query(:Order)("select id, customer, amount, created from orders where created >= ?", since);
for o in rows do
  print o.id, o.amount;
done;
```

- `query(:T)(sql, params…)` returns a `Stream(:T)`: rows are fetched in batches (`batch: 10000` by default) while the loop runs.
- The parameters are passed separately (`?` placeholders). Building SQL with interpolation (`\s{…}` inside the SQL text) is reported by the compiler as a warning: it is the classic SQL injection.
- Without a type, `query(sql)` gives rows as DataMaps (`row["id"]`).
- `query_one(:T)(sql, …)` returns one record or `null` (an optional `T?`, D-080).
- Columns are matched to fields by name; a missing or extra column is an error at the first row, with the column name.

## 5. Writing: statements, bulk load, upsert

```eve
** one statement
new n := sales.execute!("update orders set status = ? where id = ?", "paid", id);

** many rows at once, from a stream or a collection
sales.load!("orders_stage", rows, mode: "insert");                       ** bulk insert
sales.load!("orders", rows, mode: "upsert", key: ("id",));               ** insert or update by key
sales.load!("orders", rows, mode: "merge", key: ("id",), delete: True);  ** make the table equal to the rows
```

- Methods that change a database end with `!` (unsafe, D-081): an aspect that calls them can be applied, and is started in parallel only on its own connection (question 6).
- `load!` uses the fastest path of each database (COPY for PostgreSQL, array binding for Oracle, multi-row insert otherwise) and reports the number of rows inserted, updated and deleted.
- `mode: "merge"` with `delete: True` is the full synchronization of a table, the "database synchronization" goal of the manifest (F-DAT-07).

## 6. Transactions and jobs

A job is the unit of work, so it is also the unit of a transaction:

```eve
process main is
  new sales := database.connect("sales");
  defer sales.close();

  load_orders: job
    sales.begin!();
    sales.load!("orders", extract(), mode: "upsert", key: ("id",));
    sales.commit!();
  done load_orders;

recover
  sales.rollback!();
  if $error is DatabaseError and $error.transient do
    retry;                       ** lost connection, deadlock: run the job again
  done;
return;
```

The explicit `begin!`/`commit!`/`rollback!` above shows the mechanism. Proposal (question 2): a job declared with a connection does it by itself, `load_orders: job on sales … done load_orders;`, commits at `done`, rolls back on an error before `recover` runs.

## 7. Mapping record types and tables

The light mapping replaces the ORM of the old databases.html. A record type can name its table and key; the connection then offers short methods for the common cases, and the SQL is still visible in `$trace` (debug mode):

```eve
class Customer = {id: Integer, name: String, city: String?} <: Record is
  set TABLE = "customers";
  set KEY   = ("id",);
end Customer;

new c := sales.find(:Customer)(42);            ** select … where id = 42, or null
sales.save!(c);                                ** upsert by KEY
sales.remove!(:Customer)(42);                  ** delete by KEY
```

No lazy loading, no automatic mirroring of objects into the database, no hidden cache: a call is one SQL statement.

## 8. ETL pipelines

A pipeline puts the pieces together: extract with a query stream, transform with pure functions, load in batches, record checkpoints, write the run log.

```eve
# copy orders from the ERP into the sales warehouse
driver orders_sync is
  class ErpOrder = {order_no: String, cust: String, total: Decimal, ts: Instant} <: Record;

  function to_order(e: ErpOrder) => (@o: Order) is
    let o := {id: Integer.parse(e.order_no), customer: e.cust, amount: e.total, created: e.ts} :Order;
  return;

  process main is
    new erp   := database.connect("erp");
    new sales := database.connect("sales");
    defer erp.close();
    defer sales.close();

    copy: job
      new since := checkpoint.read(:Instant)("orders_sync", default: Instant.epoch);
      new rows  := erp.query(:ErpOrder)("select order_no, cust, total, ts from orders where ts > ?", since);
      for batch in rows.batch(10000) do
        sales.load!("orders", (to_order(e) | e in batch), mode: "upsert", key: ("id",));
        checkpoint.write!("orders_sync", batch[-1].ts);     ** committed with the batch
      done;
    done copy;
  recover
    retry if $error.transient;
  return;
end orders_sync;
```

- `checkpoint` keeps its values in the Eve database of the machine (section 9), so a restarted run continues after the last committed batch.
- Every job writes its lines into the run log (D-081); the loads also record their row counts there: the lineage of the run (F-DAT-06).
- With parallel streams (level 4), the extraction can be split by a key range into several aspects, each with its own connection.

## 9. The Eve database

Each machine has its own database, the **Eve database**, in the folder `db/` of the machine folder (D-083). It is a normal database for scripts (`database.connect("eve")`) and it also holds the data of the machine itself:

| Content | Used by |
|---|---|
| checkpoints of pipelines | `checkpoint.read`, `checkpoint.write!` |
| run history: one row per run and per job, the index of the run logs | `eve -c "runs"`, the scheduler |
| lineage: rows read and written per job, per table | reports, audits |
| staging tables | pipelines that load in two steps (stage, then merge) |
| datasets of a service | small applications served by `serve` |

Engine (question 1): the proposal is to **embed an existing engine** in the virtual machine rather than write one: SQLite (one file, everywhere, very small) as the default, and optionally DuckDB (column store, much faster for analytics and large ETL staging). Both are C libraries that Zig links directly. Writing a new database engine is a project of its own, not a step of Eve 0.4.

**answer** We chose SQLite to embed into Eve machine by default and we postpone DuckDB for later. We can have a DuckDB Zig binding implementation that can be an alternative database for remote database ussage optimized for Eve but it will be a secondary project not embedded in core VM machine. It will be independent database engine just used by EVE as alternative to other database.

## 10. Admin commands

The databases of a machine are administered with machine commands, at the prompt, with `eve -c`, or remotely with `-r` (D-083). They all start with `db`:

| Command | Meaning |
|---|---|
| `db list` | the databases of the machine: the names of `eve.cfg` and the Eve database, with their state (reachable or not) |
| `db add <name> <url>` | add a connection to the configuration (the password goes to the secrets, never to `eve.cfg`) |
| `db remove <name>` | remove a connection from the configuration |
| `db test <name>` | open a connection and report the server, its version and the time it took |
| `db info <name>` | size, number of tables, last backup, open connections of the pool |
| `db tables <name>` | the tables and views, with their row counts |
| `db describe <name> <table>` | the columns of a table: name, type, null, key; and the Eve record type that matches it |
| `db sql <name> "<statement>"` | run one SQL statement and print the result (rights: question 5) |
| `db create <name>` | create a new Eve database in `db/` |
| `db migrate <name>` | apply the migration scripts of `db/migrations/<name>/` that were not applied yet, in order |
| `db backup <name> [file]` | copy the database to a file (default `out/<name>_<datetime>.bak`) |
| `db restore <name> <file>` | replace the database with a backup |
| `db export <name> <table> <file>` | write a table to CSV or JSON |
| `db import <name> <table> <file>` | load a CSV or JSON file into a table |
| `db compact <name>` | reclaim the free space of an Eve database |
| `db runs [driver]` | the run history from the Eve database |

Examples:

```
eve -c "db test sales"
eve -c "db describe sales orders" -r prod
eve -c "db backup eve" -r prod
```

`db describe` can also write the Eve record type of a table (`db describe sales orders --eve`), so a developer starts from the real schema instead of typing it.

## 11. Schema migrations

The schema of an Eve database, or of a target database owned by the project, evolves with the project. Migration scripts are SQL files in `db/migrations/<name>/`, named with a number (`001_create_orders.sql`, `002_add_status.sql`). `db migrate` applies the ones not applied yet, each in a transaction, and records them in the Eve database. A project deployed on another machine (`eve -u`, D-083) brings its migrations with it.

## 12. Drivers

| Database | First version (0.4) | How |
|---|---|---|
| Eve database | yes | SQLite embedded (DuckDB optional) |
| SQLite | yes | the same embedded engine |
| PostgreSQL | yes | libpq, the C client library |
| MySQL, MariaDB | later | the C client library, or ODBC |
| SQL Server | later | ODBC |
| Oracle | later | ODBC or OCI |

ODBC covers most of the others with one driver; a native client is added where speed matters (bulk load).

**answer** we provide support only for open source databases. SQLLite is embeded, DuckDB has a special wrapper a different project we will support with drivers. PostgreSQL yes, MySQL, MariaDB yes. Other databases will be supported by community later. 

## 13. Errors

Database errors are classes of the exception module (D-081): `DatabaseError` with the fields `sqlstate` (the standard 5-character code), `vendor_code`, `transient` (`True` for a lost connection, a deadlock, a time-out: worth a `retry`), and subclasses `ConnectionError`, `ConstraintError` (duplicate key, foreign key), `TypeError` (a column that can't be converted to the field type). The run log records the error of a failed job with its SQL state.

## 14. Security

- Connections and passwords live in the machine configuration and its secrets, never in scripts or in git.
- Every connection uses the rights of a database user chosen for the project: read-only for sources, write rights only on the target tables.
- `db sql`, `db restore` and `db remove` are admin commands: on a listening machine they need the admin token.
- Parameters, never interpolation, in SQL; the compiler warns on interpolated SQL text.

## 15. What changes

| Change | Kind |
|---|---|
| Module `database`: `connect`, `Connection` (`query`, `query_one`, `execute!`, `load!`, `begin!`, `commit!`, `rollback!`, `find`, `save!`, `remove!`, `tables`, `columns`), `checkpoint` | standard library |
| Record types `class T = {…} <: Record`, with `TABLE` and `KEY` constants | language (types, D-080) |
| `job on <connection>` (proposal) | syntax |
| `DatabaseError` and its subclasses | exception module |
| `database "<name>" = "<url>"`, `secret "<name>" = …` in `eve.cfg` | configuration |
| `db/` folder of the machine (Eve database, migrations) | machine (D-083) |
| Commands `db list`, `db add`, `db test`, `db describe`, `db sql`, `db migrate`, `db backup`, … | machine |
| Tutorial databases.html rewritten from this design | tutorial (RTU-S01) |

## Questions for the author

1. **Engine of the Eve database.** Embed SQLite (and optionally DuckDB) in the VM, or do you want Eve to have its own storage engine? An own engine is a large project of its own; SQLite gives a working Eve database in version 0.4.
**answer** we embed only SQLite, DuckDB will be used in a different project special design to be independent with EVE driver that can be imported and used as dependency. We postpone indefinitly creation of our own engine.
2. **Transactions.** A job that names a connection (`name: job on sales … done name;`) commits at `done` and rolls back on an error, or explicit `begin!`/`commit!`/`rollback!` only?
**answer** that is the hidden purpose of a job, to do a tranzation.
3. **Record types.** `class Order = {…} <: Record;` as the declaration of a row type, with optional `TABLE` and `KEY` constants: is this the record syntax you want (D-080 left the record declaration open)?
**answer** I think this is just right. A class of type Record. and Optional "Table" that is a buffer of records.
4. **The mapping.** Is the light mapping of section 7 (`find`, `save!`, `remove!`, one SQL statement each) enough, or do you want more of the old ORM (memory tables, sessions, mirroring)?
**answer** Not complex ORM model. User can use bare SQL and handle the complexity using smart jobs.
5. **`db sql` rights.** Any SQL statement for an admin, or only `select` unless the configuration allows changes?
**answer** DDL will be supported using scripts. Eve can load scripts and send the script to database for execution. This will install a structure, alter a structure, disable indexes prepare database for bulk insert/update migration" Eve may install stoded procedures (is supported) and call stored procedures. We need external functions to map to stored procedures with signature, these external functions can be used in processes.
6. **Parallel and connections.** Methods that write end with `!`, which forbids starting the aspect in parallel (D-081). A parallel load is still the main speed-up of ETL. Proposal: an aspect that opens its own connection may write with `!` methods and be started in parallel, because it shares no state with its siblings. Accept this exception?
**answer** EVE is not aiming for parallel pipelines in one aspect, we need reliability. An aspect can connect to a database and execute one process in serial mode, another aspect need a new connection to resolve a second aspect in parallel. The proces is this, database is prepared for bulk operations by the driver with one aspect, then parallel aspects can be started to load in bulk data into the database in independent groups of tables in parallel. First the head tables, in first parallel group, then direct related tables in second parallel group and so on organized by the developer in hyerarchi order, last leaf tables will be added also in parallel, then a closing job issued by the driver will finalize (reindex, enable constraints, enable triggers) 
7. **Command names.** `db …` as a prefix for every database command (`db list`, `db backup`), or separate words (`databases`, `backup`)?
**anwwer** Yes, db prefix is welcome, db alter, db create, db prepare, to prepare bulk load, to activate, db reindex - to rebuild indexes  db activate to reactivate constrains.  
8. **Order of drivers.** SQLight first then PostgreSQL  then MySQL, then MariaDB then MangoDB and then other. We connect to providers like supabase, neon, claudflare before other cloud providers.
