# e56_etl_csv_sqlite_json: a local ETL, CSV to SQLite to JSON

A small ETL that runs on local storage only: no server, no network. It checks the whole path of a batch job with the smallest parts: **extract** a CSV file, **load** it into a local SQLite database, **transform** it with SQL, and **write** the result as JSON.

Run it with `python script/runtest.py e56`. The spec behind it is `spec/semantics/data-types.md#local-etl-files-and-a-local-sqlite-database`, `spec/library/database.md#direct-sql` and `#transactions`.

## The project folder

```
e56_etl_csv_sqlite_json/
  e56_etl_csv_sqlite_json.eve   the driver and its expectations (/*@expect*/ block)
  eve.cfg                       database "cache" = "sqlite://db/cache.db"
  data/in/sales.csv             the input: 4 sales, one with an empty region
  data/out/                     the output: lines.json, emptied before each run by the runner
  db/                           cache.db, the local database, made by the run (not versioned)
  sql/schema.sql                drops and creates the table `sales`
```

## What the driver does

1. `database.connect("cache")` reads `eve.cfg` and opens `db/cache.db` (the folder `db/` is made if it is missing).
2. `cache.script("sql/schema.sql")` creates the table `sales` again, so every run starts from an empty database.
3. The job `load` reads `data/in/sales.csv` with `csv.read!(:Sale)`: each row becomes a `Sale` record (columns matched by name; the empty `region` of the last row is `null` because the member is `String?`). Each record is inserted with `cache.execute!` and bound parameters. The job is one transaction: committed at `done`, rolled back when the job fails.
4. `cache.query!(:Line)` transforms with SQL: the total of each sale (`qty * unit_cents`), only the sales with `qty > 0`, in order of `id`.
5. `json.write("data/out/lines.json", lines)` writes one JSON array, one record per line.
6. `cache.query_one!(:Total)` reads the sum from the database, to prove the data really is in the file.

## Expected result

The printed lines: `loaded 4`, `written 3`, `total 1025`. The sale 2 has `qty` 0 and is left out of the JSON, but it is in the database (the total counts all four rows: 750 + 0 + 150 + 125).

`data/out/lines.json` (the runner compares it as JSON, so spacing does not matter):

```json
[
{"id":1,"product":"Widget","total_cents":750,"region":"North"},
{"id":3,"product":"Bolt, steel","total_cents":150,"region":"South"},
{"id":4,"product":"Nut","total_cents":125,"region":null}
]
```

The row `3,"Bolt, steel",10,15,South` has a quoted comma, and the row `4,Nut,25,5,` an empty unquoted field: the two rules of the CSV reader that matter most.

## What it needed in the VM

This test is the first to run the data language: `csv.read!(:T)(path)`, `json.write`, `database.connect`, and the `Connection` methods `script`, `execute!`, `query!(:T)`, `query_one!(:T)` and `close` (`code/evevm/src/interp.zig`, `data.zig`, `sqlite.zig`). The parser accepts the type argument on a library call, `x.f!(:T)(args)`. When it was written (2026-10-11) the results were lists in memory, `Decimal` and `Instant` columns, the `table` declaration and the ORM were not read yet. They are now (tests e46 to e53 and e86 to e94); what remains is that only `sqlite://` connections work and that a query result is a list in memory, not a lazy stream.
