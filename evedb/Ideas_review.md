I read `evedb/ideas4improvements.md`. Most of it is sound. One claim is wrong, and shared memory is premature. I haven't changed any file; this is analysis for you to decide on.

## 1. The ideas, one by one

| Idea | Verdict | Why |
|---|---|---|
| Two protocols: PostgreSQL for outside tools, a native Eve protocol for eve↔evedb | **Yes** | evedb already has both ports. The PostgreSQL port stays for psql, BI tools and other languages. The native port becomes the fast path. |
| "The native protocol skips SQL parsing and query planning" | **Wrong** | A query is still SQL, and DuckDB still parses and plans it. The real savings are elsewhere: no text conversion of every value, no row-by-row framing, and bulk loads that skip SQL entirely. Those savings are large. |
| Shared memory with lock-free ring buffers | **Later, only if measured** | It is the fastest way between two processes on one host, but only on one host. It needs separate Windows and POSIX code and careful crash handling. Loopback TCP or a Unix socket is probably not the bottleneck at first; converting values is. Build it only if a benchmark proves the socket is the limit. |
| Arrow-style column batches | **Yes, the key idea** | DuckDB already works in column batches of 2048 rows. Eve's `Memory` tables (`columnar.zig`) already use nearly the same layout: an array per column, a bitmap for NULL, offsets plus one buffer for text. Sending batches in that layout means almost no conversion on either side. |
| SQLite for job state and small data, DuckDB for heavy data | **Yes** | This matches D-184 and is the right split (section 2). |

**The current EWP-db is not fast yet.** Version 0.1 sends each value with its own tag, row by row, and the whole result in one frame. That works for testing, not for performance. The "BATCH/CREDIT" design was the right direction.

## 2. SQLite and DuckDB: why both

| | SQLite (inside `eve.exe`) | DuckDB (inside `evedb`) |
|---|---|---|
| Storage | Rows | Compressed columns, ~122,000 rows per row group |
| Strong at | Single-row reads and writes, small transactions, very small footprint, zero setup | Scans, aggregates and joins over millions of rows on all cores; reads Parquet, CSV and JSON files directly |
| Weak at | Large analytics: one thread and row storage make it slow on big scans | Many tiny single-row inserts; the library is large (tens of MB) |
| Concurrency | Many readers and one writer, across processes | **Only one process may write a database file** |
| Lives in | Every `eve`: the project's core database, job checkpoints, run history, configuration state, small lookup and reference caches | Only the `evedb` server: warehouse tables, staging of big loads, large data caches, results of OLAP queries |

Why not only one engine:
- **DuckDB only:** every `eve` would carry a large library. It would also lose SQLite's safe multi-process access to small project files.
- **SQLite only:** heavy ETL and analytics would be much slower.

So each `eve` stays small and keeps its own SQLite. Big data goes to evedb, which owns the DuckDB files. Because of the single-writer rule, **all access to a DuckDB file goes through evedb**; `eve` never opens one directly.

## 3. The fast protocol I recommend

**Phase 1: native columnar EWP over TCP or a Unix socket**
- **Results:** sent as column batches. Fixed-width columns (integers, reals, dates, timestamps) are copied byte for byte from DuckDB's vectors. Text is sent as offsets plus one buffer, and NULL as a bitmap. Batches are about 1 MB, with credits for flow control.
- **Bulk loads:** `eve` sends the same batches, and evedb feeds them straight into DuckDB's bulk insert, the Appender (no SQL per row).
- **Statements:** prepared once on the server, with binary parameters.
- **Compression:** an option for remote links only.

**Phase 2: a benchmark.** Run one query and one load of, say, 10 million rows three ways: over the PostgreSQL port, over native EWP, and with plain SQLite. That gives real numbers instead of guesses.

**Phase 3: shared memory, only if phase 2 shows the socket is the limit.** The batches would keep the same layout, so only the transport changes.

## 4. DuckDB files and how they are created and reached

```
project/
  eve.cfg                      the connections of the scripts
  db/local.db                  SQLite: core database of eve (checkpoints, runs)
  db/cache.db                  SQLite: small reference caches
  evedb.cfg                    the server: ports, login, databases
  data/                        owned by evedb only
    warehouse.duckdb           one DuckDB database = one file (tables, schemas, indexes)
    warehouse.duckdb.wal       DuckDB's write-ahead log, while changes wait for a checkpoint
    staging.duckdb
    exports/sales_2026.parquet files DuckDB reads and writes directly
```

**To create a database**, use one of:
- `evedb create warehouse`
- A line in `evedb.cfg`: `database "warehouse" = "data/warehouse.duckdb"`. The file is made on first open in test mode.

**To reach it from a script**, declare it in `eve.cfg` and use it like this:

```
database "wh" = "evedb://127.0.0.1:8044/warehouse"     ** native, fast (phase 1)
database "wh_pg" = "postgres://eve:pw@127.0.0.1:5432/warehouse"   ** compatible, slower
```

```eve
new wh := database.connect("wh");
new s := Sales();                       ** a Memory table (columnar)
s.store(wh, "select region, sum(amount) as total from sales group by region");   ** batches straight into columns
big.load(wh, "sales_2026");             ** Appender: no SQL per row
wh.execute!("copy sales to 'data/exports/sales.parquet' (format parquet)");
```

The `Memory` table type you already approved fits this naturally: DuckDB's batches and Eve's columns line up, so `load` and `store` are close to a memory copy.

## 5. Triggers and stored procedures

I agree with you: drop both from evedb (section 12 of its README).
- **Logic lives in Eve jobs**, which work set-based on whole tables or batches, not row by row.
- **evedb stays a simple engine:** storage, SQL, bulk in and out, sessions, faults and the statement log for tests.
- **Reusable SQL** can use DuckDB's own macros, which need no code from us.

This removes the hidden Eve machine inside evedb, the connection back into the caller's transaction, and the trigger emulation. The design becomes much simpler.

## What I would change, if you agree

1. **Record D-187** with:
   - the roles of SQLite and DuckDB;
   - all DuckDB access goes through evedb;
   - native columnar EWP as the eve↔evedb data path;
   - PostgreSQL kept for compatibility;
   - shared memory only after the benchmark;
   - no triggers or procedures.
2. **Rewrite evedb README sections 5 and 12:**
   - section 5 becomes the columnar batch frames and the Appender load;
   - section 12 shrinks to "logic in Eve jobs, SQL macros";
   - add a file-layout section.
3. **Build phase 1** (the `evedb://` driver with `store` and `load` for `Memory` tables), then the phase 2 benchmark.

Shall I go ahead with these three steps?