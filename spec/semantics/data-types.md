# Data file types

Status: **0.1-draft**, level 5 (the data language, D-125; version 0.4). Written from the proposals of Q-039 and Q-044 and from `../../design/design-database-remote.md` (ETL), **as proposed**: the author has not answered yet, and the choices are listed in `../../design/archive/review-2026-10-04/level5.md`. Sources: the author's request of 2026-10-08. Tests: `test/level5`. The basic types and modules that these types use are in `../library/data-language.md`; the database side is in `../library/database.md`.

## What they are

Six types describe the content of a file that a program loads and parses in memory. A value of one of these types is made by **opening** a file or a stream of bytes (for example the body of an HTTP response); the type tells the parser how to read it and what a traversal gives back.

| Type | The file | A traversal gives | Version |
|---|---|---|---|
| `CSV` | text with separated fields, usually a header row | a `Row` | 0.4 |
| `JSON` | JSON text, or JSON Lines | a `Node` (an object, an array, a scalar), depth first | 0.4 |
| `TXT` | fixed-length text, file extension `.txt`: a simple text file | a `Row` | 0.4 |
| `XML` | XML text | a `Node` (an element), depth first | 0.5 |
| `HTML` | HTML text; also the safe page of the templates | a `Node` | level 7 (0.6) |
| `HTMT` | an HTML template, file extension `.htmt`: HTML with `{expression}` holes | the nodes of the template; rendering fills the holes | level 7 (0.6) |

## Rules

- **One ancestor.** Every one of these types is derived from `Document(:U) <: (Object, Iterable(:U))`, where `U` is the unit: `CSV` and `TXT` give a `Row`, `JSON`, `XML` and `HTML` give a `Node`. They are written mostly in Eve in the standard library; the compiler knows only the ancestor and the traversal protocol.
- **Traversal protocol.** The library trait `Iterable(:U)` (level 4, D-145): a class gives its next unit, or `null` at the end. A `for` loop reads any `Iterable`. The unit is valid inside the body (a `clone` keeps it longer).
- **Buffered load.** Opening a file reads nothing but the first block. The parser reads a block, hands out the units one by one and reads the next block when the buffer is empty, so the memory used does not depend on the size of the file. `.all()` asks for the whole content on purpose.
- **Errors.** A unit that is not well formed raises a `FormatError` with `line` and `column`, when the loop reaches it: the units before it have been given already. The file is closed when the loop ends, by `break` or by an error.
- **`HTML` is one type**: a parsed document tree. A rendered template gives an `HTML` value too; text placed in it is always a text node, so it is escaped when the value is written. There is no second name for the safe page.

## Names of the types

The name of a type is the usual name of its format, in capitals when the format is an acronym: `CSV`, `JSON`, `XML`, `HTML`, `HTMT`, `TXT` (D-157). A type name does not have to be one capital letter followed by lower case; the convention is only that it starts with an upper-case letter. The module of a format has the same name in lower case (`csv`, `json`, `xml`, `html`, `txt`).

## TXT: fixed-length text

A `TXT` file is a simple text file where each field has a fixed width and each record is one line. It is the fixed-length format (it replaces `Dat`), read and written with the options `widths:` (the width of each field, in the order of the class), `width_unit:` and `null:`. It has no style, no page and no font: it is plain text.

```eve
txt.write("out/orders.txt", rows, widths: (8, 10, 12, 20));
new lines := txt.read!(:Order)("in/orders.txt", widths: (8, 10, 12, 20));
```

## Output formats for reports: PRN and PDF (backlog)

`PRN` (a print-out file, extension `.prn`) and `PDF` are formats for **output only**, for data reporting: a report that a person reads or a printer prints. They are planned and **not specified yet**: the style (fonts, sizes, margins, headers and footers, page numbers, columns and their alignment) and the limits (the width of a line, the lines per page, what happens to a value longer than its field) are a todo, recorded in `../../design/backlog.md`. What is already clear: what only changes the look belongs to the style of the report (and to the UX, `eveux`), not to a data format like `TXT`; the report is written from the same record classes and streams as the data files.

## Reading a unit

A `Row` reads by name and by position, `row["name"]`, `row[2]`, and the value is a `String` (nothing is converted unless the program asks, `row["total"].real()`). `row.name` exists only for records. **Typed reading** decodes into a record class, with the field types of the class:

```eve
class Order = {id: Integer, customer_id: Integer, amount: Decimal, created: Instant} <: Record;

new rows := csv.read!(:Order)("in/orders.csv", encoding: "windows-1252", columns: {"Order No": "id", "Total": "amount"});
new docs := json.read!(:Order)("in/orders.jsonl");                 ** JSON Lines or an array of objects
new lines := txt.read!(:Order)("in/orders.txt", widths: (8, 10, 12, 20));
for o in rows do print "{o.id}: {o.amount}"; done;
```

The record class is the layout of the file, as it is the layout of a table (one class, several mappings). A CSV header name or a JSON key maps to the field of the same name; `columns:` renames, the rule of `column … as` for tables. A `TXT` file maps by position, in field order, and its layout is the record type with the widths of the fields in declaration order. An XML element maps its child elements and attributes by name. Each value is converted from text to the field type with the canonical forms below. A missing value of a `T?` field is `null`; of a `T` field it is an error of that row. The header is checked at the first unit: in debug mode every difference is listed, in production the first one stops the read with a `FormatError`.

## Modules

One module per format: `csv`, `json`, `txt`, `xml`, `html`. Each has

| Function | Meaning |
|---|---|
| `open(source)` | untyped: gives the document (`CSV`, `JSON`, …), rows by position or name |
| `read!(:T)(source, options…)` | typed: gives a `Stream(:T)`; a read of a file carries `!` (D-089) |
| `write(path, rows, options…)` | writes a stream or a table; a write without a result has no `!` |

The `source` is a path or a `Stream(:Bytes)`, such as the body of an HTTP response. A `.gz` path is decompressed on the fly (`../library/data-language.md#compression`).

## Unicode streams

Every file is read as a stream of bytes, decoded to code points, then parsed into units.

| Point | Rule |
|---|---|
| Encoding | a BOM decides (UTF-8, UTF-16 LE/BE, UTF-32); otherwise the option `encoding:`; otherwise UTF-8. No guessing from the content |
| Supported | UTF-8, UTF-16 LE/BE, UTF-32, ISO-8859-1, Windows-1252 |
| Invalid bytes | `invalid: "error"` (default): `FormatError` with line, column and byte offset; `"replace"`: U+FFFD, counted in the run log; `"reject"`: the unit goes to the rejects |
| Normalization | `normalize: "nfc"` composes the text in memory; recommended for key fields. Default: none. The source file is never changed, in any case |
| Line endings | LF, CRLF and CR are read; written as LF unless `eol: "crlf"` |
| Fixed width (`TXT`) | widths count code points; `width_unit: "byte"` for legacy single-byte files |
| Size | a file is never read whole: the stream reads blocks and the parser gives one unit at a time |

## Transform and rejects

A transform is a pure function from one record to another (`function to_target(o: Order) => (@t: Target)`), applied in a loop or a comprehension; pure functions run in the parallel aspects of a transfer with no lock. A unit that can't be read or converted, or a record whose `validate` fails, is not an error of the whole job when the read has a rejects output (D-159): `csv.read!(:Order)(path, rejects: "out/orders_rejects.csv")`, or `rejects: @bad` with a `Table(:Reject)`. The output is created **in batches**: one reject batch for each batch read, with the source, line, column, the text of the unit and the reason, written when the batch is done, so the memory stays small. `max_rejects: 100` turns the 101st reject into an error of the job. Every count goes to the run log (lineage).

### What NFC is

The same letter can be written in Unicode in two ways: `é` as one code point (U+00E9), or as `e` followed by a combining accent (U+0065 U+0301). They look the same and are different strings, so as keys they are two different keys. **NFC** (Normalization Form C, canonical composition) rewrites the text to the composed form, one code point wherever one exists, so equal-looking text compares equal. `normalize: "nfc"` does it to the values in memory; the default is to keep the text as it was read, and the file is never changed.

## Reports: the other direction

A report reads a query stream and writes a file with the same record class and the same options:

```eve
new rows := sales.query!(:Order)("select id, customer_id, amount, created from orders where created >= ?", since);
csv.write("out/orders.csv", rows, encoding: "utf-8", bom: False, eol: "lf");
json.write("out/orders.jsonl", rows);
txt.write("out/orders.txt", rows, widths: (8, 10, 12, 20));
```

The writer takes a stream, so a report of millions of rows needs the memory of one batch. A report job sets `$read_only = True`. `bom: True` is for spreadsheets that need it.

## Canonical form and round trip

The same class and the same options give a lossless round trip: `read(write(rows))` gives the same records, and `write(read(file))` gives the same file when the file is in **canonical form**, which every writer produces:

| Value | Written as |
|---|---|
| `Integer`, `Natural` | decimal digits, `-` when negative |
| `Decimal` | digits with the scale of the value (`12.50`), never an exponent |
| `Real` | the shortest text that reads back to the same bits |
| `Logic` | `true`, `false` (`logic: ("Y", "N")` changes it) |
| `Instant` | ISO 8601 UTC with `Z`; `DateTime` with its offset; `Date`, `Time` ISO |
| `null` | CSV: an empty field without quotes (`""` is the empty string); `TXT`: a field of spaces for a `T?` field (option `null:`); JSON: `null` |
| field order | the order of the class; the CSV header uses the names after `columns:` |
| quotes (CSV) | only when the value holds the separator, a quote or a line break |

## The formats in detail

These rules fix the text of the files that the writers produce (the canonical form) and that the readers accept. The tests of level 5 compare these bytes.

**CSV.** The separator is `,` (option `sep:`), the quote is `"`. The writer always writes a header line with the names of the fields (after the renames of `columns:`; `header: False` leaves it out), then one line per record, every line ended with LF (also the last). A value is quoted only when it holds the separator, a quote or a line break; a quote inside is doubled (`""`). `null` is an empty field, the empty string is `""`. No BOM unless `bom: True`. The reader accepts a header in any order of the columns (it maps by name), LF and CRLF, and quoted fields with line breaks.

**JSON.** A path that ends in `.jsonl` or `.ndjson` (or `lines: True`) is JSON Lines: one object per line, no space after `:` or `,`, the keys in the order of the fields of the class, ended with LF. Any other path is one array of objects, written as `[`, then one object per line ended with `,` except the last, then `]`. A `Decimal` is a JSON number with its scale (`12.50`), an `Instant` or a `Date` is a string in the canonical form, `null` is `null`, a string is escaped as JSON requires (`\"`, `\\`, `\n`, and `\uXXXX` for the control characters; other code points are written as UTF-8). The reader takes any JSON whitespace and maps the keys by name.

**TXT.** Each field takes exactly its width in code points. A string, a `Date`, an `Instant` and a `Logic` are left-aligned and filled with spaces on the right; an `Integer`, a `Decimal` and a `Real` are right-aligned and filled with spaces on the left; `null` is spaces. A value longer than its width is a `FormatError` (`overflow: "cut"` cuts it). The fields follow each other with no separator, the line is ended with LF and **not trimmed**. The reader slices each line by the widths, trims the spaces and converts; a field of only spaces is `null` for a `T?` field and an error otherwise.

**Errors of a reader.** A `FormatError` has `format` (`"CSV"`, …), `line`, `column` and `reason`; `line` counts from 1 and the header is line 1. A CSV line with more or fewer fields than the header, or a value that does not convert to the type of its field, is an error of that line.

## Local ETL: files and a local SQLite database

The smallest ETL needs no server and no network: a project reads files of `data/in/`, loads them into a local application database (a SQLite file of `db/`, for example `db/cache.db`, declared in `eve.cfg` as `database "cache" = "sqlite://db/cache.db"`), transforms the data with SQL, and writes the result as files into `data/out/`. The core database (`db/local.db`) keeps only the logs and the metadata (D-159); the data goes to the application database, which a test may recreate at every run with `script("sql/schema.sql")`.

```eve
new cache := database.connect("cache");
cache.script("sql/schema.sql");
load: job
do
  for s in csv.read!(:Sale)("data/in/sales.csv") do
    new n := cache.execute!("insert into sales (id, product, qty) values (?, ?, ?)", s.id, s.product, s.qty);
  done;
done load;                                     ** the job is one transaction: commit at done, rollback on an error
new lines := cache.query!(:Line)("select id, product, qty * unit_cents as total_cents from sales where qty > 0 order by id");
json.write("data/out/lines.json", lines);
```

- `csv.read!(:Sale)(path)` reads the rows into records of the class `Sale`; the columns are matched to the members by name (rule above), a missing column is an error before the first row, and an unquoted empty field is `null` (only for an optional member, otherwise a `ConvertError`).
- `query!(:Line)(sql, args…)` matches the result columns to the members of `Line` by name; a `NULL` in a member that is not optional is a `ConvertError`. Arguments are bound to the `?` placeholders in order (`Integer`, `Real`, `String`, `Logic` and `null`).
- `json.write(path, rows)` writes the array (or JSON Lines) of the rules above and makes the folders of the path.
- The test `test/level5/e56_etl_csv_sqlite_json` does exactly this and compares the file written to `data/out/`.
- *Version 0.4 reads and writes in memory:* `csv.read!` and `query!` return a `List` of records, not a lazy `Stream`; a file or a result larger than memory waits for the streams (data-language.md, open points).

## ETL: the cycle

```
files ──read──▶ records ──transform──▶ stage (evedb) ──transfer──▶ remote tables
  ▲                                                                        │
  └──────────────write◀── records ◀──────── report (query) ◀──────────────┘
```

Each step is a job, so each is a transaction and a restart point (`../library/database.md#transactions`):

1. **Stage.** Load the file into a `temporary` table of the staging database (`evedb`, DuckDB) with `load!`. The file is read once; a restart reads the stage.
2. **Check and shape in SQL.** Deduplicate, join and total with SQL in the staging database.
3. **Prepare the target** with one job, only on a connection that Eve owns (an `evedb` database or `exclusive` in `eve.cfg`): `sales.prepare(tables)` disables indexes, constraints and triggers. On any other connection Eve does not do it: the constraints stay on, the load works, slower, and gives more failures on an active database.
4. **Transfer** in parallel groups, one per level of the table hierarchy, head tables first and leaf tables last, in the order the developer writes. Each aspect has its own connection and loads with `load!(mode: "upsert")` in batches, with `commit;` and a checkpoint per batch in the target.
5. **Activate** (the same connections): `sales.activate(tables)`, `sales.reindex(tables)`. A constraint that fails now names the rows that break it; the job fails and the data stays for inspection.
6. **Record** the counts of every step in the run log and the lineage table of the Eve database.

Upserts make every step safe to run twice: a failed run starts again from its last checkpoint and never duplicates a row.

```eve
# load the orders of a shop file into the ERP
primary aspect orders_upload is
  class Order = {id: Integer, customer_id: Integer, amount: Decimal, created: Instant} <: Record is
    method validate(@self) is
      expect self.amount >= 0d;
    return;
  end Order;

  table stage_orders: Order in "stage" is key (id); temporary; end stage_orders;
  table orders: Order in "erp" is key (id); end orders;

  process main(path: String) is
    stage: job
    do
      stage_orders.load!(csv.read!(:Order)(path, normalize: "nfc", rejects: "out/orders_rejects.csv", max_rejects: 100), mode: "upsert");
    done stage;

    transfer: job
      new since := checkpoint.read!(:Integer)("orders_upload", default: 0);
    do
      for batch in stage_orders.scan!("id > ? order by id", since).batch(5000) do
        orders.load!(batch, mode: "upsert");
        commit;
        checkpoint.write("orders_upload", batch[-1].id);
      done;
    done transfer;

  recover
    retry after 5s if $error.transient and $error.attempt < 5;
    abort;
  return;
end orders_upload;
```

## Open points

All in `../../design/archive/review-2026-10-04/level5.md`: the layout of a `TXT` file, the position of `XML` (0.5) and `HTML` (0.6), the module for compression.
