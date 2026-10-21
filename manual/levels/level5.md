<!-- Generated from the specification, the tests and the benchmarks. Do not edit this page. -->

# Level 5: Data and database

The data language and the ETL core: real data with the right types (`Decimal`, `Instant`, records, tables, `Secret`), files and formats (CSV, JSON, text), the HTTP client, generators, generic functions, overloading and the Eve macro, and the database layer with connections, query streams, bulk loads, transactions per job, checkpoints, lineage and the Eve database. It is done when JSON and CSV round-trip, a killed load restarts from its checkpoint, level 5 passes against SQLite and a PostgreSQL server, and `db backup` and `db restore` round-trip.

| Code | Feature | Stage |
|---|---|---|
| [`F-DAT-01`](#f-dat-01-database-layer) | Database layer | drafted |
| [`F-DAT-03`](#f-dat-03-etl-pipeline-model) | ETL pipeline model | drafted |
| [`F-DAT-04`](#f-dat-04-checkpoints-and-restart) | Checkpoints and restart | drafted |
| [`F-DAT-05`](#f-dat-05-columnar-tables) | Columnar tables | drafted |
| [`F-DAT-06`](#f-dat-06-data-lineage-and-run-reports) | Data lineage and run reports | planned |
| [`F-DAT-08`](#f-dat-08-the-eve-database) | The Eve database | planned |
| [`F-DAT-09`](#f-dat-09-database-admin-commands) | Database admin commands | planned |
| [`F-DAT-10`](#f-dat-10-schema-migrations) | Schema migrations | planned |
| [`F-DAT-11`](#f-dat-11-record-table-mapping) | Record-table mapping | validated |
| [`F-DAT-13`](#f-dat-13-sql-function) | `sql function` | drafted |
| [`F-DAT-14`](#f-dat-14-stored-procedures) | Stored procedures | drafted |
| [`F-DOC-02`](#f-doc-02-tutorial-data-client-part) | Tutorial, data client part | planned |
| [`F-LIB-04`](#f-lib-04-files-and-paths) | Files and paths | drafted |
| [`F-LIB-05`](#f-lib-05-data-formats) | Data formats | drafted |
| [`F-LIB-06`](#f-lib-06-time-and-dates) | Time and dates | drafted |
| [`F-LIB-07`](#f-lib-07-shell-commands) | Shell commands | drafted |
| [`F-LIB-08`](#f-lib-08-secrets) | Secrets | drafted |
| [`F-LIB-09`](#f-lib-09-compression-and-archives) | Compression and archives | planned |
| [`F-LNG-12`](#f-lng-12-generators) | Generators | validated |
| [`F-LNG-13`](#f-lng-13-data-types-for-etl) | Data types for ETL | drafted |
| [`F-LNG-14`](#f-lng-14-record-types-and-optional-values) | Record types and optional values | drafted |
| [`F-LNG-20`](#f-lng-20-generic-functions-and-procedures) | Generic functions and procedures | validated |
| [`F-LNG-21`](#f-lng-21-overloading) | Overloading | validated |
| [`F-NET-01`](#f-net-01-http-client) | HTTP client | planned |
| [`F-STR-09`](#f-str-09-eve-macro-hybrid-script) | Eve macro (hybrid script) | validated |
| [`F-STR-10`](#f-str-10-unified-aspect) | Unified aspect | validated |
| [`F-STR-11`](#f-str-11-recover-in-a-function-procedure-and-method) | `recover` in a function, procedure and method | validated |
| [`F-VM-06`](#f-vm-06-efficient-collections) | Efficient collections | planned |
| [`F-VM-11`](#f-vm-11-one-eve-its-source-in-modules) | One `eve`, its source in modules | drafted |

## F-DAT-01 Database layer

Stage: **drafted**.

Connect, parameterized query as a stream, execute, transactions, bulk load. *Specified and taught (2026-10-10):*, `databases.html`; the VM has none of it yet.

*Partial (2026-10-11):* `database.connect` of a `sqlite://` connection in `eve.cfg`, `script`, `execute!`, `query!(:T)`, `query_one!(:T)`, `close`, a job as a transaction (commit at `done`, rollback on error), `csv.read!(:T)` and `json.write` (`.json` array, `.jsonl` lines); results are lists, not streams; no `table`, ORM, `load!`, `commit;` or other drivers.

## F-DAT-03 ETL pipeline model

Stage: **drafted**.

Extract, transform, load with jobs and aspects; dead-letter output; the pattern taught in the tutorial. *Specified and taught (2026-10-10):*, `etl.html`. *State (2026-10-20):* a local ETL runs, a bad row goes to the rejects with a limit, streams have `map`, `filter` and the like; the pipeline stages with back-pressure over a database and the lineage report (F-DAT-06) are not done.

## F-DAT-04 Checkpoints and restart

Stage: **drafted**.

Resume a failed pipeline at the last committed batch. *Specified (2026-10-10):* checkpoints in the target database, `commit;` in a job. *State:* `commit;` with a checkpoint is tested; restart of a killed load from its checkpoint is not tested yet.

## F-DAT-05 Columnar tables

Stage: **drafted**.

`Table` type with typed columns, Arrow-compatible. *State:* the `Memory` table with typed columns and the column batches of evedb exist; Arrow compatibility does not.

## F-DAT-06 Data lineage and run reports

Stage: **planned**.

Inputs, outputs, row counts, durations per job and aspect.

## F-DAT-08 The Eve database

Stage: **planned**.

The core database: one per project in its `db/` folder (default `local.db`, name set in `eve.cfg`, system variable `$EVE_CORE_DB`), SQLite embedded (3.54.0, compiled into the VM from the amalgamation; DuckDB is not in the VM: it is the separate test database `evedb`, F-DAT-12), for checkpoints, run history, lineage and metadata, never ETL data (staging and the cache are `evedb` databases).

## F-DAT-09 Database admin commands

Stage: **planned**.

`db list`, `db add`, `db test`, `db info`, `db tables`, `db describe`, `db sql`, `db create`, `db backup`, `db restore`, `db export`, `db import`, `db compact`, `db runs`. *Specified (2026-10-10):* the list in, with `db create-table`, `db prepare`, `db activate`, `db reindex`, `db cache`.

## F-DAT-10 Schema migrations

Stage: **planned**.

Numbered SQL scripts in `db/migrations/<name>/`, applied by `db migrate` and recorded in the Eve database.

## F-DAT-11 Record-table mapping

Stage: **validated**.

`table` declarations binding record classes to tables, tracked records with dirty fields, updates of the changed fields only, mapping validated in debug mode and refused in production.

## F-DAT-13 `sql function`

Stage: **drafted**.

An Eve function marked `sql function` is registered on every SQLite and DuckDB connection and called from SQL; deterministic, one result, SQL types, not overloaded; SQL `NULL` only for nullable types; an error stops the query with `$err_sql` (code 59).

*Partial (2026-10-12):* SQLite done; DuckDB waits for the VM to load it.

## F-DAT-14 Stored procedures

Stage: **drafted**.

Native procedures in `sql/` called through `external` signatures; Eve procedures in `proc/`, run by the database part, listed by `eve db proc list`, reloaded by `eve db proc reload`, called by `db.call`.

*Partial (2026-10-12):* a module of `proc/` is imported and its `sql function`s registered, `eve db proc list`. Not yet: `external` at run time (no database with stored procedures in the tests), `proc reload`, `db.call`.

## F-DOC-02 Tutorial, data client part

Stage: **planned**.

Files, formats, streams, HTTP client, ETL pipelines.

## F-LIB-04 Files and paths

Stage: **drafted**.

`fs` and `path` modules, text and bytes, line streams, globbing. *State:* `fs` files, folders and lines work; a `path` module, bytes and globbing are not done.

## F-LIB-05 Data formats

Stage: **drafted**.

JSON and CSV read/write, decode into records; later XML, Parquet. *State:* JSON, JSON lines, CSV (options, rejects, encodings) and fixed-width text work; XML and Parquet are not done.

## F-LIB-06 Time and dates

Stage: **drafted**.

`now`, parse, format, zones, durations.

An example that runs, and what it prints:

```eve
# an Instant prints in the canonical form; a bad text is the error parse
primary aspect e28_instant is
  process main is
    print Instant.epoch;
    new t:= Instant.parse("2026-10-10T08:00:00Z");
    print t;
    expect t > Instant.epoch;
    print Instant.parse("yesterday");
    print "not reached";
  recover
    new c:= $error.code;
    print "code: {c}";
  return;
end e28_instant;
```

```text
1970-01-01T00:00:00Z
2026-10-10T08:00:00Z
code: 15
```

## F-LIB-07 Shell commands

Stage: **drafted**.

`call` with pipes, and a safe `run(cmd, args, cwd)`.

*Partial (2026-10-18):* module `os` with `run!` (no shell), `env!`, `hostname!`, `pid!`, `platform`.

An example that runs, and what it prints:

```eve
# os.run! with a time-out: the child is killed, status 124 (TD-9, TD-27)
primary aspect f15_os_timeout is
  process main is
    new quick:= os.run!("eve", ("--version",), "", 5000);
    print quick.status;
    new r:= os.run!("sleep", ("5",), "", 300);
    if os.platform == "windows" do
      let r:= os.run!("ping", ("-n", "6", "127.0.0.1"), "", 300);
    done;
    print r.status;
    print r.err.contains("Time-out after 300 ms");
  return;
end f15_os_timeout;
```

```text
0
124
True
```

## F-LIB-08 Secrets

Stage: **drafted**.

A `Secret` type and `secret.get` from environment, file or vault. *Specified (2026-10-10):*.

An example that runs, and what it prints:

```eve
# a Secret is never printed: print and interpolation write ***
primary aspect e29_secret_masked is
  process main is
    new s:= Secret("hunter2");
    print s;
    print "token: {s}";
  return;
end e29_secret_masked;
```

```text
***
token: ***
```

## F-LIB-09 Compression and archives

Stage: **planned**.

Gzip, zip, stream codecs (manifest).

## F-LNG-12 Generators

Stage: **validated**.

Methods with `yield`, `Generator(:T)`, use in `for` and builders.

An example that runs, and what it prints:

```eve
# a generator gives its values one at a time to a for loop
primary aspect e23_generator_for is
  generator count_to(n: Integer) => (@x: Integer) is
    for i in (1..n) do
      let x:= i;
      yield;
    done;
  return;

  generator squares(n: Integer) => (@x: Integer) is
    for i in (1..n) do
      yield i * i;
    done;
  return;

  process main is
    for v in count_to(3) do
      print v;
    done;
    new total:= 0;
    for s in squares(4) do
      let total += s;
    done;
    print "sum of squares: {total}";
  return;
end e23_generator_for;
```

```text
1
2
3
sum of squares: 30
```

## F-LNG-13 Data types for ETL

Stage: **drafted**.

Decimal, Instant/DateTime with zone, Date, Time, Duration, Bytes, Uuid.

An example that runs, and what it prints:

```eve
# a Decimal keeps its scale, adds exactly and compares by value
primary aspect e27_decimal_scale is
  process main is
    print 12.50d;
    print 0.10d + 0.20d;
    print 1.5d * 2.00d;
    expect 1.50d == 1.5d;
    expect 0.10d + 0.20d == 0.30d;
    new price:= 19.99d;
    print "price: {price}";
  return;
end e27_decimal_scale;
```

```text
12.50
0.30
3.000
price: 19.99
```

## F-LNG-14 Record types and optional values

Stage: **drafted**.

Typed records for rows, JSON objects and messages; `T?`. *State:* records, `null` in plain fields and printing of `null` are tested; the full optional type is in.

An example that runs, and what it prints:

```eve
# a field with ? holds null; a plain field never does; null is tested before use
primary aspect e77_optional_fields is
  class Customer = {id: Integer, name: String, city: String?} <: Record;

  process main is
    new a:= {id: 1, name: "Ann", city: null}:Customer;
    new b:= {id: 2, name: "Bob", city: "Lyon"}:Customer;
    for c in (a, b) do
      if c.city == null do
        print "{c.name}: no city";
      else
        print "{c.name}: {c.city}";
      done;
    done;
  return;
end e77_optional_fields;
```

```text
Ann: no city
Bob: Lyon
```

## F-LNG-20 Generic functions and procedures

Stage: **validated**.

A first parameter list of types, `function largest(:T <: Comparable)(items:T)`, called `largest(xs)` (types inferred) or `largest(:Integer)(xs)`; also procedures, methods and processes; no type list on a lambda, overloaded functions instead; possible because self-calling lambdas are removed. All its tests pass (2026-10-20, see Tests).

An example that runs, and what it prints:

```eve
# a generic function has a list of types before its parameters; the call infers the types or writes them
primary aspect e01_generic_function is
  function largest(:T <: Comparable)(items: T) => (@result: T) is
    let result:= items[1];
    for x in items do
      let result:= x if x.compare(result) > 0;
    done;
  return;
  
  function first(:T)(items: T) => (@result: T) is
    let result:= items[1];
  return;

  process main is
    print largest((3, 9, 2));               ** T is inferred: Integer
    print largest(:String)(("b", "c", "a"));  ** T is written
    print first((7, 8));
    print first(:String)(("x", "y"));
  return;
end e01_generic_function;

    
```

```text
9
c
7
x
```

## F-LNG-21 Overloading

Stage: **validated**.

Functions, procedures and methods share a name with different signatures: number and types of the parameters, and the result type of a function; resolved at compile time, the call must match one signature; a function and a procedure never share a name, a method with a result and one without may. All its tests pass (2026-10-20, see Tests).

An example that runs, and what it prints:

```eve
# functions and procedures share a name when the types of their parameters differ
primary aspect e05_overload_types is
  function half(x: Integer) => (@result: Integer) is
    new h:= x / 2:Integer;
    let result:= h;
  return;

  function half(x: Real) => (@result: Real) is
    let result:= x / 2.0;
  return;

  procedure show(x: Integer) is
    print "Integer {x}";
  return;

  procedure show(x: String) is
    print "String {x}";
  return;

  process main is
    print half(8);
    print half(9.0);
    show(3);
    show("three");
  return;
end e05_overload_types;
```

```text
4
4.5
Integer 3
String three
```

## F-NET-01 HTTP client

Stage: **planned**.

Requests, headers, JSON bodies, time-outs, TLS.

## F-STR-09 Eve macro (hybrid script)

Stage: **validated**.

One self-contained file: shared declarations and several aspects, exactly one of them `primary`; `apply` (level 2) and `parallel`/`start` (level 4) inside it; a concurrent aspect uses only the thread-safe shared names.

An example that runs, and what it prints:

```eve
# an Eve macro: shared declarations, an exclusive aspect and the primary aspect in one file

set step = 5:Integer;
new total:= 0;

function twice(x: Integer) => (@result: Integer) is
  let result:= x * 2;
return;

# add_step: an exclusive aspect runs alone, so it changes a shared variable
exclusive aspect add_step is
  process main(times: Integer) is
    for i in (1..times) do
      let total += step;
    done;
  return;
end add_step;

primary aspect e16_macro_apply is
  process main is
    apply add_step(3);
    apply add_step(1);
    print "total: {total}";
    print "twice: {twice(total)}";
  return;
end e16_macro_apply;
```

```text
total: 20
twice: 40
```

## F-STR-10 Unified aspect

Stage: **validated**.

No `driver` keyword, no free script, no `#!`; the kinds `exclusive`, `concurrent` and `primary`; `main` and private processes; calls between aspects at most three levels deep and without a cycle; a concurrent aspect is called from a primary or an exclusive aspect; a primary aspect is run by a command.

## F-STR-11 `recover` in a function, procedure and method

Stage: **validated**.

The end of `recover` handles the error and the routine returns normally; `abort` passes it on; no `recover` in a constructor, generator or lambda (2026-10-18).

An example that runs, and what it prints:

```eve
# a function and a procedure can have a recover region: the error is handled inside, the caller goes on
primary aspect b55_function_recover is
  function half(n: Integer) => (@result: Integer) is
    let result:= 100 / n;
  recover
    print "recovered: {$error.message}";
    let result:= -1;
  return;

  procedure shout(text: String) is
    raise "no shouting: {text}";
  recover
    print "procedure recovered: {$error.message}";
  return;

  process main is
    print half(4);
    print half(0);
    shout("hi");
    print "after";
  return;
end b55_function_recover;
```

```text
25
recovered: Division by zero
-1
procedure recovered: no shouting: hi
after
```

## F-VM-06 Efficient collections

Stage: **planned**.

Hashed and sorted maps, sets, ropes for Text.

## F-VM-11 One `eve`, its source in modules

Stage: **drafted**.

The modules `evecm`, `evecp`, `evevm`, `evedb`, `eveux` and `cmd` with one build; one binary whose first word chooses the part, `eve vm`, `cp`, `db`, `ux`; the serving machine as one process.

*Partial (2026-10-13):* the modules `evecm`, `evecp`, `evevm`, `evedb` and `cmd` exist in one root build (arrows checked by the build); the values and the heap are in `evecm`; the database layer is `evedb` behind the interfaces `Host` and `Data`; the configuration and the wire are cut from `server.zig`; not yet: the cut of the machine and of `cli.zig`, the native calling convention, `eveux` and `evetx` in the root build, the part words.
