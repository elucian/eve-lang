# Data engines and legacy files

Status: **first draft (2026-10-17)**, decision D-184. The behaviour below is implemented in the machine (`evedb/src/columnar.zig`, `dbf.zig`, `importer.zig`, and the commands `eve db import` and `eve db export`). The Eve syntax is decided in Q-059 (`plan/decision_level6.md`) and shown in the section "The `Memory` class" below: this page defines what the operations do and what they are called in the machine, not how a script writes them.

## Two engines

**Where each one lives (D-187).** SQLite is compiled into every `eve` and holds its own state. DuckDB lives only in the evedb server, which owns the DuckDB files; a script reaches them through `evedb://` (column batches, the fast path) or `postgres://` (other tools). `../../evedb/README.md` sections 3A and 3B give the roles and the layout of the files.

| Engine | What it is for | Where the data lives |
|---|---|---|
| Query engine | Dynamic SQL, relational indexes, joins, the planner | SQLite, in a file or in `:memory:` |
| Columnar tables | The computational pipelines of Eve: filters, sums, sorts and joins over many rows | A native struct of arrays in the memory of the machine |

The two engines never share storage and never convert by themselves: data moves between them only through the explicit operations `load` and `store` (below).

## The query engine: SQLite `:memory:`

Every `:memory:` database is opened with these PRAGMAs, set by `Db.open` (`tuneMemory`). They trade durability for speed, which is right for a database that disappears with the process:

| PRAGMA | Value | Why |
|---|---|---|
| `journal_mode` | `MEMORY` | the rollback journal stays in memory; `OFF` was proposed in D-184 (d), but it makes `rollback` unsafe, and a job rolls back |
| `synchronous` | `OFF` | no wait for the disk |
| `temp_store` | `MEMORY` | temporary tables and indexes stay in memory |
| `cache_size` | large (negative value: kibibytes) | the pages stay in the cache |
| `locking_mode` | `EXCLUSIVE` | one connection owns the database |

A database that is a file is not tuned by the machine: it keeps the defaults of SQLite (a durable journal and `synchronous=FULL`); a different mode for files (`WAL` with `synchronous=NORMAL` was proposed in D-184 (d)) waits until the files of the tests can be checked with it. Relational indexing is SQLite's: `create index`, unique indexes and the query planner.

## The `Memory` class

A columnar table is declared like a class, with field names and types, derived from `Memory` (answer to Q-059 (a)); a column is named by its field (Q-059 (c)):

```eve
class Sales = {id: Integer, region: String, price: Real, paid: Logic, note: String?} <: Memory;

new s := Sales();                          ** an empty table: one column for each field
s.add(1, "north", 2.5, True, null);        ** one value for each field, in the order of the class
print s.price.sum();                       ** a column is the field: s.price
new big := s.take(s.price.filter(">", 2.0));
s.load(shop, "sales");                     ** explicit: the table becomes the SQLite table `sales`
new back := Sales();
back.store(shop, "select id, region, price, paid, note from sales where price > ?", 2.0);
```

| Field type | Column | Note |
|---|---|---|
| `Integer`, `Natural`, `Short`, `Byte`, `Huge` | INTEGER | |
| `Real`, `Float` | REAL | a whole number is accepted and converted |
| `Logic` | BOOLEAN | |
| `String` | TEXT | |
| `T?` | the column of `T` | only an optional field accepts `null` (the cell is NULL) |
| `Decimal`, `Instant`, other types | none yet | an error when the table is made; keep a `Decimal` as `Real` or `String` |

Methods of the table:

| Method | Result |
|---|---|
| `add(v1, …, vn)` | appends one row; there must be one value for each field and each value must fit its field; a row that does not fit changes nothing |
| `count()`, `length()` | the number of rows |
| `take(rows)` | a new table of the same class with the rows of the list `rows`, in its order |
| `load(connection, name)` | makes the SQLite table `name` (it must not exist) and inserts all the rows; answers the number of rows; inside a job it is part of the transaction |
| `store(connection, select, params…)` | appends the rows of the `select` (with `?` parameters); the query must have a column named like each field; answers the number of rows |

Methods of a column (`s.price`):

| Method | Result |
|---|---|
| `count()` | the number of cells that are not NULL |
| `sum()` | the sum (Integer for a whole column, Real for a Real column); NULL cells are skipped |
| `min()`, `max()` | the smallest or largest cell that is not NULL, or `null` when there is none |
| `at(row)` | the cell, or `null` for a NULL; an index error outside the table |
| `filter(op, value)` | the list of the numbers of the rows that match, in order; `op` is the text `"="`, `"<>"`, `"<"`, `"<="`, `">"` or `">="`; a number column takes a number, a `String` column a `String` (compared byte by byte), a `Logic` column `True` or `False`; a NULL never matches |

Tests: `test/level5/e111_memory_table`.

## The columnar table

A columnar table has named columns of one type each, and a number of rows. Layout:

- a column of `INTEGER`, `BOOLEAN`, `DATE` or `TIMESTAMP` is one contiguous array of 64 bit integers (a date is the number of days since 1970-01-01, a timestamp the number of seconds since 1970-01-01 00:00:00 UTC, a boolean 0 or 1);
- a column of `REAL` is one contiguous array of 64 bit floats;
- a column of `TEXT` is one byte buffer with all the texts one after the other, and an array of offsets (`cell i` is `bytes[offs[i] .. offs[i + 1]]`);
- every column has a **validity bitmap**, one bit for each cell: 1 for a value, 0 for NULL. A NULL still takes its place in the array, so every column has the same length and a row number means the same cell in all of them.

There is no object for a row. The operations work on one column at a time:

| Operation | Result |
|---|---|
| `count` of a column | the number of cells that are not NULL |
| `sum` of an integer or a real column | the sum of the cells that are not NULL (an integer sum wraps on overflow) |
| `min`, `max` of an integer column | the smallest and the largest cell that is not NULL, or nothing when there is none |
| `filter` an integer column with `=`, `<>`, `<`, `<=`, `>`, `>=` and a value | the **selection**: the numbers of the rows that match, in order; a NULL never matches |
| `take` a selection | a new table with those rows, the columns copied one at a time |

## Moving data between the engines

On an `evedb://` connection `load` and `store` move **column batches** (the arrays of the columns and their NULL bitmaps), not rows: a fixed-width column is copied whole, and the load goes to DuckDB's Appender. Measured (`../../evedb/README.md` section 5.6): 1,000,000 rows into a `Memory` table in 0.23 s, 3.4 times faster than from a local SQLite file.

| Operation | What it does |
|---|---|
| `load` a table into a SQLite database as the name `n` | makes the table `n` (it must not exist) and inserts every row in **one transaction** with one prepared statement; a date is stored as the text `YYYY-MM-DD`, a timestamp as `YYYY-MM-DD HH:MM:SS`, a boolean as 0 or 1; on any error nothing is kept |
| `store` the answer of a query | makes a columnar table from the rows of a `select`: a column takes the type of the first value that is not NULL (integer, real, otherwise text); a value of another type in that column is stored as NULL |

The copy is **explicit** (answer of the author to D-184 (c)): a script that wants a table in SQLite says `load`, a script that wants the rows of a query as columns says `store`.

## Files: legacy ingestion

| Format | Extension | Notes |
|---|---|---|
| CSV | `.csv` | comma; quotes `"`, a doubled quote inside; the first row is the names; an empty cell is NULL; a short row is padded with NULL |
| Text | `.txt`, `.tsv`, `.tab` | the delimiter is the one that appears most in the first line among tab, comma, semicolon and bar |
| JSON | `.json` | an array of objects (or an object that has one array); the columns are the keys in the order they first appear; a missing key or `null` is NULL; a nested object or array is kept as JSON text |
| DBF | `.dbf` | dBASE III, FoxBASE and FoxPro 2.x; the file declares the types: `N` without decimals is an integer, `N` and `F` with decimals a real, `D` a date, `L` a boolean, the rest text; a blank number, date or logical is NULL; deleted records are skipped; memo fields are read as the text `(memo)` (the `.FPT` file is not read); a text that is not valid UTF-8 is read as Latin-1 |
| XLS, XLSX | `.xls`, `.xlsx` | **not read yet**: save the sheet as CSV |

The types of a CSV, TXT or JSON column are found by looking at all its values, narrowest first: boolean words (`true`, `false`), integers (no leading zero: `007` stays text), reals, dates `YYYY-MM-DD`, then text. A column where every cell is empty is text.

**DBF is a decoder and an encoder, nothing more.** It is read as a stream of records (a forward reader over the bytes of the file) that gives each cell to the importer, and written from cells for an export. It is never an execution engine, never a table that is edited, never the storage of data in memory.

The tests of DBF files are written in Python (`script/dbf_check.py`): it makes DBF files with `struct`, independently of the Zig code, imports and exports them and checks the result.

The commands (`eve db …`, also typed at the prompt as `db …`):

| Command | Does |
|---|---|
| `db import <file.db> <file> [table]` | reads the file (by its extension) and loads it into the database as a new table; the name defaults to the file name with every character that is not a letter or a digit turned into `_`; answers `imported N rows, M columns into <table>` |
| `db export <file.db> <table> <file>` | stores the table as columns and writes it as CSV, TXT, JSON or DBF (by the extension); a DBF column of text is as wide as its longest value (254 at most), a number is `N(18)` or `N(20,6)`, names are cut to ten bytes |

An import that fails (a file that is not of its format, a table that exists) changes nothing.

In a script the same import is a method of the connection (answer to Q-059 (d)): `shop.import("data/items.csv", "items")` loads the file as the new table `items` and answers the number of rows. It runs in a savepoint, so inside the transaction of a job it is undone by `rollback;` with the rest. The formats are the same; a spreadsheet must be exported to CSV first (Q-059 (e)). Test: `test/level5/e110_connection_import`.

## Open points

`Decimal` and `Instant` fields in a `Memory` table (and the columns DECIMAL and TIMESTAMP in the importers); a streaming import for files that do not fit in memory. XLS and XLSX are not read: the user exports to CSV (Q-059 (e)).
