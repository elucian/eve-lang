# Data language

Status: **0.1-draft**, level 5 (version 0.4, D-125). Written from the proposals of Q-044 and Q-024 **as proposed**: the author has not answered yet, and the choices are listed in `../../design/review/level5.md`. This page lists the types and the modules that the database layer (`database.md`) and the data files (`../semantics/data-types.md`) stand on. Tests: `test/level5`.

## Features and versions

| Feature | Version | Where it is defined |
|---|---|---|
| Generators | 0.4 | below |
| Record types | 0.4 | `database.md#records` |
| Time types `Date`, `Time`, `Duration`, `Instant`, `DateTime` | 0.4 | below |
| `Decimal` and optional types `T?` | 0.4 | below |
| `Bytes` | 0.4 | below |
| Files and paths, module `fs` | 0.4 | below |
| `JSON`, `CSV`, `TXT` | 0.4 | `../semantics/data-types.md` |
| HTTP client, module `http` | 0.4 | below |
| Secrets, module `secret` | 0.4 | below |
| Shell by argument list, module `os` | 0.4 | below |
| Compression: gzip reader | 0.4 | below |
| Compression: zip, writers; `XML` | 0.5 | |

## Generators

A generator is declared with the keyword `generator`: `generator count_to(n: Integer) => (@x: Integer) is … yield x; … return;`. It replaces the detection of `yield` in a method (D-067). A generator is a task that stops at `yield` and continues at the next read (the baton tasks of stage A, D-144), so the tree walker runs it. A generator is read with `for x in count_to(3) do … done;` or with `next()`; its call is deterministic, the object moves on, so its name carries no `!`. A generator is an `Iterable(:T)` (level 4). The files and queries of the data layer are generators of this kind: `Stream(:T)` adopts them.

## Time types

`Date`, `Time` and `Duration` keep the names of the tutorial page Date and Time (and `30s` of level 4). Two types are added by the module `time`:

| Type | Meaning |
|---|---|
| `Instant` | a point in time in UTC (not `Timestamp`); `Instant.epoch`, `time.now!()` (the clock gives another value at each call, so its name ends with `!`, D-087, D-168) |
| `DateTime` | a date and a time with a zone (not `LocalTime`) |

Parsing and formats use the format codes of strings. The canonical text forms are in `../semantics/data-types.md#canonical-form-and-round-trip`. The module `time` also holds the clock and `sleep`.

## Decimal and optional types

`Decimal` (`12.50d`) is exact base 10; it keeps its scale (`12.50d` is written `12.50`) and compares by value (`1.50d == 1.5d`). It maps to SQL `NUMERIC`. `T?` is a type that may hold `null`; a plain `T` never does (D-080). `null` is the value and `Null` its type: `print` writes `null` (alone, in a text and in a collection) and `type(x)` of it gives `Null` (D-168). A record field `city: String?` maps to a nullable column; a `T?` value used where a `T` is needed is tested first (`if c.city <> null do … done;`); the rules of optional types are in `../semantics/types.md`.

## Bytes

`Bytes` is an immutable sequence of bytes, indexed from zero. A `Stream(:Bytes)` is the source of the file readers, the body of an HTTP response and the input of the decompressors. Literals and slices follow the rules of lists of `Natural`. `Bytes` maps to `BLOB` and `bytea`.

## Files and paths

One module `fs` holds files, folders and paths (not two modules `fs` and `path`); the operator `/` joins paths.

| Function | Meaning |
|---|---|
| `fs.read!(path)`, `fs.read_bytes!(path)` | the whole text (`String`) or content (`Bytes`) of a file; a read carries `!` |
| `fs.lines!(path, encoding: …)` | the lines as a `Stream(:String)`, read by blocks |
| `fs.write(path, text)`, `fs.append(path, text)`, `fs.write_bytes(path, bytes)` | write; no result, no `!` |
| `fs.list!(dir)`, `fs.glob!(pattern)` | the names in a folder, a pattern like `in/*.csv`; sorted by name in the byte order of UTF-8, so a run gives the same order on every system (`fs.list!` today, test e84; `fs.glob!` when it is written) |
| `fs.exists!(path)`, `fs.size!(path)`, `fs.remove(path)`, `fs.move(from, to)`, `fs.make_dir(path)` | the usual operations |
| `fs.join(a, b)`, `a / b`, `fs.name(p)`, `fs.parent(p)`, `fs.extension(p)` | path functions, pure, no I/O |

A missing file is the error `$err_file` (20), a refused access `$err_access` (21), any other failure `$err_io` (22). A path with `..` that leaves the project folder is allowed only for the paths the machine permits (capabilities, level 6).

## HTTP client

The client only; the server is the service kind of level 6.

```eve
from "lib" use (http);
new answer := http.get!("https://api.example.com/orders", timeout: 10s, headers: {"Accept": "application/json"});
expect answer.status == 200;
for o in json.read!(:Order)(answer.body) do … done;      ** the body is a Stream(:Bytes)
```

`http.get!`, `http.post!(url, body: …)` and `http.request!(method, url, …)` give an `HttpResponse` with `status`, `headers` and `body`. A status of 400 or more is not an error by itself; `answer.check()` raises `HttpError` with `status`, `url` and the text of the body. A time-out raises `TimeoutError`, a refused or lost connection `ConnectionError` (transient). `https://` needs the outbound TLS client, which is level 9 (D-189, backlog): until then an `https://` URL raises `ConnectionError` with the reason "TLS client not available"; when it exists a certificate that does not match is an error. A header of type `Secret` goes on the wire but never to a log.

## Secrets

A `Secret` is a value that never appears in a log, a trace or an error message (it prints as `***`) and never in the source: the machine gives it to a project from its configuration (D-083). `secret.get("sales_password")` returns a `Secret`; its text is read only by a sink that accepts it (a connection of `eve.cfg`, an HTTP header). Every connection with a password needs it. Converting a `Secret` to a `String` is an error.

## Shell by argument list

`os.run(command, arguments, cwd: dir)` starts a program without a shell and gives a record `{code: Integer, out: String, err: String}`: no quoting problems, no injection. `call` (level 3) stays as it is, for a full command line. `os.run` is the safe form for programs that build arguments.

## Details used by the tests

- **`Decimal`.** `+` and `-` keep the larger scale (`0.10d + 0.20d` is `0.30d`), `*` adds the scales (`1.5d * 2.00d` is `3.000d`), a comparison compares the values (`1.50d == 1.5d` is `True`), and printing shows the scale of the value (`print 12.50d;` writes `12.50`). `/` gives the larger scale of the two plus 6 digits, at most 18, rounded half away from zero (`1d / 3d` is `0.333333d`, `10.00d / 4d` is `2.50000000d`); `%` gives the remainder with the sign of the divisor, at the larger scale; an `Integer` with a `Decimal` is a `Decimal` of scale 0 (`5 + 0.50d` is `5.50d`); a division by zero is `$err_divide`. A `Decimal` and a `Real` are never mixed without a conversion: an operator between them is a compile error (D-110). The conversion is explicit (D-168): `d.real()` gives the `Real` (it can lose digits), `r.decimal()` gives the `Decimal` of the shortest text of the `Real` (`0.1.decimal()` is `0.1d`, not the 55 digits of its binary value); and `:=` converts, to a variable that holds the other kind (`new r := 0.0; let r := price;`) or with a type hint (`new x := 3.75d :Real;`).
- **`Instant`.** `Instant.epoch` is 1970-01-01T00:00:00Z. Printing an `Instant` writes the canonical form, `2026-10-10T08:00:00Z` (ISO 8601, UTC, `Z`, no fraction when the fraction is zero; a fraction is written to the microsecond with its trailing zeros cut: `2026-10-10T08:00:00.5Z`, `…:00.123456Z`). `Instant.parse(text)` reads it; a text that is not an instant is the error `$err_parse`.
- **`Secret`.** `Secret(text)` makes a secret from a string (for a value read from an input; the text is not shown again). `print` and interpolation of a `Secret` write `***`. The text is read only by a sink that accepts a `Secret`. `secret.get(name)` returns the secret of the machine; a name that does not exist is the error `$err_key`.
- **`fs`.** A path is relative to the working folder (the project). `fs.write(path, text)` creates the folders of the path; `fs.read!(path)` of a missing file is `$err_file`; `fs.lines!(path)` gives the lines without their line ending.

## Compression

A gzip reader in version 0.4: a path that ends in `.gz` is decompressed on the fly by the readers of `csv`, `json`, `txt` and `fs.lines!`, and `gzip.open!(path)` gives a `Stream(:Bytes)`. Zip and writers are version 0.5.

## System library modules

The modules of this table are part of the standard library of the machine and are **in scope in every script without an import**, as `io` is (`print` comes from it): `fs.read!(path)`, `csv.read!(:T)(path)`, `database.connect("sales")`, `secret.get(name)`. A project module of the same name is a compile error (name conflict). *(Proposed: the import forms of `modules.md` need a path, and the standard modules have none.)*


| Module | Holds | Version |
|---|---|---|
| `io`, `exception` | standard streams; `Error`, `raise`, `expect` | 0.1 |
| `fs` | files, folders, paths | 0.4 |
| `time` | `Instant`, `DateTime`, the clock, formats | 0.4 |
| `secret` | `Secret` | 0.4 |
| `os` | `run`, the environment | 0.4 |
| `csv`, `json`, `txt` | the data files | 0.4 |
| `database` | connections, tables, transactions | 0.4 |
| `checkpoint` | `checkpoint.write(name, value)`, `checkpoint.read!(:T)(name, default: v)`: checkpoints in the core database (`database.md#transactions`) | 0.4 |
| `http` | the client | 0.4 |
| `task` | channels and the worker pool | 0.3 |
| `xml`, `html` | `XML`, `HTML` | 0.5, 0.6 |

## Open points


All in `../../design/review/level5.md`.

- **Streams.** `csv.read!`, `json.read!` and `query!` give a `Stream(:T)`. The first implementation (e56, `data-types.md#local-etl-files-and-a-local-sqlite-database`) returns a `List` with all the rows, so a `for` loop over the result and `.count()` work, and `Stream` as a lazy source is still to do.

## JSON text in memory: `json.parse` and `json.text`

Status: **0.1-draft**, level 6 (D-189), needed by `rpc` and the services. Tests: `test/level6/f06_json_text`.

`json.read!` and `json.write` work on files and records. Two functions work on a **text in memory** and on plain values, with no record class:

| Function | Result | Meaning |
|---|---|---|
| `json.parse(text: String)` | a value | the JSON text as one value: `null` is `null`, `true` and `false` are `Logic`, a number without a point or exponent is an `Integer` (a `Real` when it does not fit), any other number is a `Real`, a string is a `String`, an array is a `List`, an object is a `DataMap` with `String` keys; a text that is not well formed is `$err_format` with the line and the column |
| `json.text(value)` | `String` | the compact JSON text of a value: a `List` or a set is an array, a `DataMap` or an object with fields is an object, `Instant` and `Decimal` are written as in `json.write`; a `Secret`, a function or a channel is `$err_argument` |

| `json.valid(text: String)` | `Logic` | `True` when `json.parse` would accept the text; a function of Eve code can not catch an error (`backlog/library-gaps.md` G-4), so a library asks first |

A top-level array is **one** value here (`json.read!` takes its items as records). `json.text(json.parse(t))` gives back the same value, with the keys of an object in sorted order.
