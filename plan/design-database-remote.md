# Design: remote databases, the Eve server, drivers and ETL

Status: **draft for review**, 2026-10-10. Nothing here is decided. Level 5 (drivers, ETL) and level 6 (the Eve server), versions 0.4 and 0.5. Part 2 of 2; part 1 is [design-database-core.md](design-database-core.md) (SQLite, the `table` declaration, tracked records, transactions, direct SQL), whose terms this file uses. It builds on [design-database.md](archive/design-database.md), on the machine and its protocols in [design-service.md](design-service.md) (EWP, remote `apply`, rules of a remote machine), and on the data file types of Q-039. Questions for the author are at the end.

## 1. Three ways to reach a database

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

The connection name in `eve.cfg` decides the path; the script is the same in every case:

```
# eve.cfg of the local machine (sketch)
database "shop"   = "sqlite://db/shop.db"               ** 1. local: the embedded engine
database "sales"  = "postgresql://etl@db1:5432/sales"   ** 2. direct: a driver on this machine
database "erp"    = "eve://prod/erp"                    ** 3. through the Eve server "prod"
database "test"   = "evedb://localhost/eve_test"        ** the Eve test database (DuckDB), a remote database
```

| Path | Driver runs on | Credentials live on | Use |
|---|---|---|---|
| 1. local | this machine (SQLite in the VM) | none | the Eve database, staging, small applications, tests |
| 2. direct | this machine | this machine (secrets, D-083) | a server-side ETL job, a developer machine with access |
| 3. through a server | the Eve server | the server only | desktops and edge machines that must not hold database passwords or reach the database network |

Path 3 is the diagram: the local app never sees a password or a database address; it holds memory tables and reads files, and the server holds the sessions, the drivers and a cache.

## 2. Drivers

### 2.1 Order

The author's answers (design-database.md §12 and question 8, Q-043i): open-source databases first, others by the community.

| Order | Database | Version | Note |
|---|---|---|---|
| 1 | SQLite | 0.4 | embedded in the VM (part 1, §2) |
| 2 | PostgreSQL | 0.4 | libpq; Supabase and Neon speak its protocol, so they come with it |
| 3 | MySQL, MariaDB | 0.5 | one driver (the MariaDB C connector reads both) |
| 4 | Cloudflare D1 | 0.5 | SQLite over HTTP, needs the HTTP client |
| 5 | MongoDB | later | not SQL: a document API of its own, not the ORM of part 1 |
| 6 | Oracle, SQL Server | community | through the driver interface below (question 1) |
| test | evedb (DuckDB) | 0.4 | the Eve test database: a separate Zig server around DuckDB that speaks the database frames of EWP (§5); the remote database of the level 5 tests, with fault injection ([evedb/README.md](../evedb/README.md)) |

The diagram names Oracle as a remote database. The author's answer leaves Oracle to the community; the interface below is what such a driver implements, so Oracle can come without a change in the core.

### 2.2 The driver interface

A driver is a Zig module that implements one interface (a table of functions), so the core, the ORM and the server never depend on a vendor:

| Function | Purpose |
|---|---|
| `open(url, secret)`, `close` | a connection; the pool is in the core |
| `begin(isolation, read_only)`, `commit`, `rollback` | transactions (part 1, §8) |
| `prepare(sql)`, `bind(index, value)`, `step` / `fetch(batch)` | statements; values always bound, never in the text |
| `execute_batch(stmt, rows)` | array binding for the grouped updates of part 1, §7.2 |
| `bulk_load(table, columns, stream)` | the fastest path: `COPY` for PostgreSQL, `LOAD DATA LOCAL` or multi-row insert for MySQL, a prepared insert in a transaction for SQLite |
| `describe(table)` | the catalog: columns, types, nullability, keys, foreign keys, for the mapping validation (part 1, §5) |
| `quote(name)`, `placeholder(n)`, `returning` | the dialect: `"x"` or `` `x` ``, `?` or `$1`, `returning` or `LAST_INSERT_ID()` |
| `type_map` | the column types of part 1, §4.2 for this database |
| `classify(error)` | the SQL state and vendor code to an Eve error class, and whether it is transient |

`classify` matters for `retry`: a lost connection (`08xxx`), a serialization failure (`40001`), a deadlock (`40P01`, MySQL 1213) and a lock time-out are transient; a constraint (`23xxx`) and a syntax error (`42xxx`) are not.

## 3. The local Eve app

What runs on the machine of the user, or on an edge machine:

- **Memory tables.** Free `Table(:T)` buffers for files and transforms, and bound tables whose session is on the server (path 3). Tracking (dirty fields, states, restore on rollback) happens here, in the local VM: only the changes travel.
- **Ingestion.** Files and streams in the formats of Q-039 (`Csv`, `Json`, `Xml`, `Dat`), read as Unicode streams (§6.1).
- **Its own SQLite.** The local Eve database for checkpoints and run history, and `stage.db` for staging (part 1, §2.1). A local app can work offline against its stage and send the result when the server is reachable.

## 4. The Eve server

An Eve machine that listens (`--listen`, design-service.md §3) and declares databases in its `eve.cfg`. It adds two services: the session manager and the cache.

### 4.1 The ACID session manager

A **remote session** is the server side of a session of part 1, §6: one per client process and per connection name. The server:

1. **Opens** it at the first request of the client process, takes a connection from its pool for that database, and gives it a **lease** (30 s by default): the client renews it with `PING` while it works. A lease that runs out rolls back the open transaction and frees the connection, so a client that crashed never holds locks for long.
2. **Runs the transaction** for the client's job. The client sends its flushes as change sets (§5); the server turns them into SQL with the same generator as the local core (part 1, §7), runs them, and returns the generated keys, the new versions and the row counts.
3. **Commits** at the client's `done`, `stop` or `commit;`. Each transaction has an id chosen by the client (a UUID). In the same transaction as the data, the server writes that id into a small table of the target database, `eve_tx`, installed by `db prepare`. The commit is therefore recorded *with* the data.
4. **Resolves doubt.** When the connection breaks after the client sent `COMMIT` but before it got the answer, the client does not know whether the job is committed. On reconnect it asks `STATUS <id>`; the server looks for the id in `eve_tx`. Found: the job passed. Not found: it was rolled back, and the job fails with a transient `ConnectionError`, so `retry` is right. Without `eve_tx` (a database where Eve may not create tables) the answer is "unknown" and the job fails with `CommitError` (`partial: True`): an administrator checks.
5. **Isolates** clients: two remote sessions never share a connection or a transaction; the isolation level and the locks are those of the database (part 1, §8.3).
6. **Limits** what a client can do: only the databases listed for the project, the rights of the database user of the server (Q-043f), the rules of a remote machine (design-service.md §10), and limits on sessions per client and on the length of a transaction.

**Two ways to work with a server**, and when to choose each:

| | Data shipping: remote session | Function shipping: remote `apply` |
|---|---|---|
| What travels | records and change sets | an aspect name, its arguments, its `@` outputs (design-service.md §7) |
| Where the job runs | on the local machine | on the server, next to the database |
| Good for | interactive work, a few thousand records, data that comes from the local machine (files, user input) | large loads and transforms of data already in databases; anything that reads more than it returns |
| Transactions | the local job; the server holds the database transaction | the remote job; nothing open across the network |

A bulk ETL of millions of rows between two databases should be a remote `apply`: the rows never cross the network twice.

### 4.2 The local database cache

The server keeps copies of chosen remote tables in `db/cache.db` (SQLite, part 1, §2.1). The cache is for **reference data**: tables that are read often and changed rarely (countries, currencies, products, price lists). It is declared on the `table` (proposal P9):

```eve
table countries: Country in "erp" is
  key (code);
  cached 1h;                 ** read from the server's cache, refreshed every hour
end countries;
```

- A cached table is loaded whole into the cache at its first use, then refreshed when its time is up. When the table has a `version` or an update-time column, the refresh reads only the rows changed since (`where version > ?`).
- `find!`, `scan!` and `where!` on a cached table read the cache. The `where!` condition runs on SQLite, so it must be portable SQL; debug mode prepares it on both engines and reports a condition that only the remote database understands.
- A write to a cached table goes to the remote database, in the job's transaction, and updates the cache after the commit (write-through). Changes made by other systems are seen at the next refresh: the cache is never the authority, and debug mode warns when a job writes to a cached table with `$isolation` stronger than read committed.
- `db cache list`, `db cache refresh <table>`, `db cache clear` administer it.
- The client does not cache by itself in version 0.5; a cached table of a local connection (path 1 or 2) is accepted and does nothing (question 3).

## 5. The protocol

Path 3 uses EWP, the Eve Wire Protocol of design-service.md §9: frames with a length, a type and a stream number, values in a compact binary form, tables column by column. The database adds these frame types to `HELLO`, `APPLY`, `RESULT`, `ERROR`, `BATCH`, `CREDIT`, `CANCEL`, `PING`, `CLOSE`:

| Frame | From | Content |
|---|---|---|
| `OPEN` | client | connection name, client process id; answer: session id, lease, mapping fingerprints of the tables |
| `BEGIN` | client | transaction id, isolation, read only |
| `QUERY` | client | table or SQL, parameters, batch size; answer: `BATCH` frames under `CREDIT` (back-pressure) |
| `CHANGES` | client | one table: inserts as full rows; updates grouped by dirty set, with only the dirty columns, the key and the version; deletes as keys |
| `APPLIED` | server | per record: generated keys, new version, or the error of that record |
| `COMMIT`, `ROLLBACK` | client | the transaction id |
| `STATUS` | client | a transaction id; answer: committed, rolled back, unknown |

Only dirty columns travel: an update of one field of a record of fifty fields sends one value, the key and the version. The mapping validation of part 1, §5 runs on the server (it has the catalog) and its result travels in the answer to `OPEN`: in production a `MappingError` stops the client before its first statement, as it would locally.

## 6. ETL

The cycle of the author's goals (databases.html): load data from files, transform it, transfer it to a remote database, and in the other direction report data from the database into files.

```
files ──read──▶ records ──transform──▶ stage (SQLite) ──transfer──▶ remote tables
  ▲                                                                        │
  └──────────────write◀── records ◀──────── report (query) ◀──────────────┘
```

### 6.1 Unicode streams

Every file is read as a stream of bytes, decoded to code points, then parsed into units (rows, objects, elements). The decoding rules are the same for every format:

| Point | Rule |
|---|---|
| Encoding | a BOM decides (UTF-8, UTF-16 LE/BE, UTF-32); otherwise the option `encoding:`; otherwise UTF-8. No guessing from the content: explicit over implicit |
| Supported encodings | UTF-8, UTF-16 LE/BE, UTF-32, ISO-8859-1, Windows-1252 in version 0.4; others later |
| Invalid bytes | `invalid: "error"` (default): `FormatError` with line, column and byte offset; `"replace"`: U+FFFD, counted in the run log; `"reject"`: the whole unit goes to the rejects (§6.3) |
| Normalization | `normalize: "nfc"` composes the text (é as one code point); recommended for key fields, because two spellings of the same name are different keys. Default: none, the text is kept as read |
| Line endings | LF, CRLF and CR are read; written as LF unless `eol: "crlf"` (Q-039f) |
| Fixed width (`Dat`) | widths count code points, not bytes; `width_unit: "byte"` for legacy single-byte files |
| Size | a file is never read whole: the stream reads blocks and the parser gives one unit at a time, so a 20 GB file needs the memory of one batch |

### 6.2 Reading into records

The record class is the layout of the file, as it is the layout of the table (one class, several mappings, part 1, §3.2):

```eve
new rows := csv.read!(:Order)("in/orders.csv", encoding: "windows-1252", columns: {"Order No": "id", "Total": "amount"});
new docs := json.read!(:Order)("in/orders.jsonl");               ** JSON Lines or an array of objects
new nodes := xml.read!(:Order)("in/orders.xml", unit: "orders/order");
new lines := dat.read!(:Order)("in/orders.dat", widths: (8, 10, 12, 20, 25));
```

- **Column = value for files.** A CSV header name or a JSON key maps to the field of the same name; `columns:` renames, the same rule as `column … as` for tables. A `Dat` file maps by position, in field order. An XML element maps its child elements and attributes by name.
- Each value is converted from text to the field type with the canonical formats (§6.5): `12.50` to `Decimal`, `2026-10-10T08:00:00Z` to `Instant`. A missing value of a `T?` field is `null`; of a `T` field it is an error of that row.
- The checks of the header (a missing or unknown column) run at the first unit, like the first row of a query: in debug mode all of them are listed, in production the first one stops the read with a `FormatError`.

### 6.3 Transform and rejects

- A transform is a pure function from one record to another (`function to_target(o: Order) => (@t: Target)`), applied in a loop or a comprehension. Pure functions can run in the parallel aspects of the transfer without any lock.
- A unit that can't be read or converted, or a record whose `validate` fails, is not an error of the whole job when the read has a rejects output: `csv.read!(:Order)(path, rejects: @bad)`. `bad` is a `Table(:Reject)` with the source, line, column, the text of the unit and the reason, written at the end to `out/<run>_rejects.csv`. `max_rejects: 100` turns the 101st reject into an error of the job. Every count goes to the run log (lineage, F-DAT-06).

### 6.4 Transfer

The pattern for a large load to a remote database. Each step is a job, so each step is a transaction and a restart point.

1. **Stage.** Load the file into a `temporary` table of `stage.db` (part 1, §3.2) with `load!`. The file is read once; a restart reads the stage, not the file.
2. **Check and shape in SQL.** Deduplicate, join reference data, compute totals with SQL on SQLite: `database.connect("stage").query!(:Target)("select … from stage_orders group by …")`.
3. **Prepare the target** with one job of the driver: `db prepare` or `sales.prepare(tables)` disables indexes, constraints and triggers of the target tables (author's answer, Q-043g).
4. **Transfer** in parallel groups, one group per level of the table hierarchy, in the order written by the developer: head tables first, then the tables that depend on them, the leaf tables last (author's answer to question 6). Each aspect has its own connection (part 1, §6.1) and loads its tables with `load!(mode: "upsert")` in batches, with `commit;` and a checkpoint per batch in the target (part 1, §8.5).
5. **Activate** with a closing job of the driver: `sales.activate(tables)`, `sales.reindex(tables)` (enable constraints and triggers, rebuild the indexes). A constraint that fails now names the rows that break it; the job fails and the data stays for inspection.
6. **Record** the counts of every step in the run log and the lineage table of the Eve database.

Upserts make every step safe to run twice, so a failed run starts again from its last checkpoint and never duplicates a row (at least once, effectively once).

### 6.5 Reports: the reverse direction

A report reads a query stream and writes a file with the same record class and the same options:

```eve
new rows := sales.query!(:Order)("select id, customer_id, amount, status, created from orders where created >= ?", since);
csv.write("out/orders.csv", rows, encoding: "utf-8", bom: False, eol: "lf");
json.write("out/orders.jsonl", rows);
dat.write("out/orders.dat", rows, widths: (8, 10, 12, 20, 25));
```

- The writer takes a stream, so a report of millions of rows needs the memory of one batch.
- A report job sets `$read_only = True`: one consistent snapshot, no locks (part 1, §8.3).
- `bom: True` for spreadsheets that need it; UTF-8 without BOM by default.

### 6.6 Reversibility

The same class and the same options give a lossless round trip in both directions: `read(write(rows))` gives the same records, and `write(read(file))` gives the same file when the file is in **canonical form**. The canonical form, which every writer produces:

| Value | Written as |
|---|---|
| `Integer`, `Natural` | decimal digits, `-` when negative |
| `Decimal` | digits with the scale of the value (`12.50`), never an exponent |
| `Real` | the shortest text that reads back to the same bits |
| `Logic` | `true`, `false` (configurable: `logic: ("Y", "N")`) |
| `Instant` | ISO 8601 UTC with `Z`; `DateTime` with its offset; `Date`, `Time` ISO |
| `null` | CSV: an empty field without quotes; `""` (quoted) is the empty string, so `null` and `""` stay different. `Dat`: a field of spaces is `null` for a `T?` field (option `null:`). JSON: `null` |
| field order | the order of the class; CSV header with the column names after `columns:` renames |
| quotes (CSV) | only when the value holds the separator, a quote or a line break |
| text | the encoding and the normalization of the options |

A conformance test of level 5 writes and reads back each format with every type of the table and compares; a second test reads a canonical file, writes it, and compares the bytes.

## 7. Failures across the layers

| Failure | What happens | Recovery |
|---|---|---|
| a SQL error in the job | rollback, memory restored (part 1, §8.2) | `recover`: `retry` if transient |
| the local app crashes during a job | the lease runs out, the server rolls back | the next run restarts from the checkpoint |
| the network breaks before `COMMIT` | the lease runs out, the server rolls back; the client job fails, transient | `retry` |
| the network breaks after `COMMIT` was sent | the client asks `STATUS` on reconnect (§4.1) | committed: the job passed; rolled back: `retry`; unknown: `CommitError` |
| the Eve server crashes | the database rolls back the open transactions when their connections drop | the client reconnects; `retry` |
| the remote database restarts | `ConnectionError`, transient | `retry after` (P5) |
| a mapping mismatch in production | `MappingError` at `OPEN`, before any statement | refused for retry: fix the code or the schema |
| the cache is stale | reads may be up to the refresh time old (§4.2) | `db cache refresh`; never use a cached table for a decision that needs the current value |
| two databases in one job, the second commit fails | `CommitError(partial)` | refused for retry; avoid with one target per job (part 1, §8.6) |

## 8. Example: a file into a remote database through the server

```eve
# load the orders of a shop file into the ERP, through the server "prod"
driver orders_upload is
  class Order = {id: Integer, customer_id: Integer, amount: Decimal, created: Instant} <: Record is
    method validate(@self) is
      expect self.amount >= 0d;
    return;
  end Order;

  table stage_orders: Order in "stage" is
    key (id);
    temporary;
  end stage_orders;

  table orders: Order in "erp" is      ** "erp" = "eve://prod/erp" in eve.cfg
    key (id);
  end orders;

  process main(path: String) is
    stage: job
    do
      new bad := Table(:Reject)();
      stage_orders.load!(csv.read!(:Order)(path, encoding: "utf-8", normalize: "nfc", rejects: @bad, max_rejects: 100), mode: "upsert");
      csv.write("out/orders_rejects.csv", bad) if bad.count() > 0;
    done stage;

    transfer: job
      new since := checkpoint.read!(:Integer)("orders_upload", db: "erp", default: 0);
    do
      for batch in stage_orders.scan!("id > ? order by id", since).batch(5000) do
        orders.load!(batch, mode: "upsert");             ** one CHANGES frame per batch
        checkpoint.write("orders_upload", batch[-1].id, db: "erp");
        commit;                                          ** P2: batch and checkpoint together
      done;
    done transfer;

  recover
    retry after 5s if $error.transient and $error.attempt < 5;
    abort;
  return;
end orders_upload;
```

Here `checkpoint` writes into the target database (`db: "erp"`, the table `eve_checkpoint` of `db prepare`), so the checkpoint and the batch commit together (part 1, §8.5). The `stage` job reads the file once; a failure of `transfer` restarts at the last committed batch.

## 9. What changes

| Change | Kind |
|---|---|
| connection URLs `sqlite://`, `postgresql://`, `mysql://`, `eve://<machine>/<name>` | configuration |
| driver interface (§2.2); drivers SQLite, PostgreSQL (0.4), MySQL and MariaDB (0.5) | VM |
| remote sessions, leases, `eve_tx`, `STATUS`; frames `OPEN`, `BEGIN`, `QUERY`, `CHANGES`, `APPLIED`, `COMMIT`, `ROLLBACK`, `STATUS` | server, EWP (level 6) |
| `cached <duration>;` clause of `table` (P9); `db cache` commands | syntax, server |
| reader options `encoding`, `invalid`, `normalize`, `columns`, `rejects`, `max_rejects`, `unit`, `widths`, `width_unit`; writer options `bom`, `eol`, `logic`, `null` | modules `csv`, `json`, `xml`, `dat` (Q-039) |
| `Reject` record class and the rejects file | standard library |
| canonical text form of every type (§6.6), with round-trip tests | spec, tests of level 5 |
| `eve_tx` and `eve_checkpoint` tables installed in a target by `db prepare` | admin commands |

## Questions for the author

1. **Oracle.** The diagram names Oracle; your answer to design-database.md §12 leaves it to the community. Keep Oracle out of the core plan, with the driver interface open to a community driver?
**Answer:**
2. **Path 3 in version 0.4 or 0.5.** The server path needs the listening machine and EWP (level 6). Proposed: paths 1 and 2 in version 0.4, path 3 with the server in version 0.5. Agree?
**Answer:**
3. **Cache on the client.** Only the server caches (as in the diagram), or may a local app also cache reference tables in its own SQLite, for offline work?
**Answer:**
4. **Tables in the target.** May Eve install `eve_tx` and `eve_checkpoint` in a target database with `db prepare`? Without them, a broken commit is "unknown" and a checkpoint can't commit with its batch.
**Answer:**
5. **Rejects.** A rejects output per read (proposed), or one rejects file per run for all reads?
**Answer:**
6. **Unicode normalization.** Off by default (proposed, the text is kept as read), or NFC by default on every read?
**Answer:**
