# Decisions, level 3: data language (version 0.2)

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. Ids are shared by all the decision files and keep counting across them; a new entry goes to the file of its topic. The levels and their versions are in [version_map.md](version_map.md).

| File | Level | Topic | Version | Tests |
|---|---|---|---|---|
| [decision_level1.md](decision_level1.md) | 1 | the project, and the language of a single script | 0.1 | `test/level1` (a) |
| [decision_level2.md](decision_level2.md) | 2 | a project: processes, aspects, modules, imports, libraries | 0.1 | `test/level2` (b) |
| [decision_level3.md](decision_level3.md) | 3 | data language: types, records, generators, files, formats, HTTP client | 0.2 | `test/level3` (c) |
| [decision_level4.md](decision_level4.md) | 4 | parallel processing and streams | 0.3 | `test/level4` (d) |
| [decision_level5.md](decision_level5.md) | 5 | database layer and the Eve database | 0.4 | `test/level5` (e) |
| [decision_level6.md](decision_level6.md) | 6 | the Eve machine and the server | 0.5 | `test/level6` (f) |
| [decision_level7.md](decision_level7.md) | 7 | web: HTML and WebAssembly | 0.6 | `test/level7` (g) |

## Scope

A driver reads and writes real data with the right types: Decimal, dates and times, records, optional values; it reads files, JSON and CSV, calls web services over HTTP, and produces values lazily with generators. The bytecode VM arrives at this level, because generators need a method that can stop and continue.

Features (`plan/features_inventory.md`): F-LNG-11 to F-LNG-16, F-LIB-03 to F-LIB-07, F-LIB-08 (secrets, for HTTP tokens), F-LIB-09, F-NET-01, F-VM-04, F-VM-06, F-TLS-02, F-TLS-03, F-SPEC-04, F-DOC-02, F-DOC-05.

Decisions already taken in other files: D-067 (generators, design), D-080 (DataMap, Rune, Null and optional types, Decimal, number suffixes), D-082 (`eve --doc`).

## Draft features

Proposals waiting for a decision. Each becomes a `D-nnn` here when the author confirms it.

1. **Keyword `generator`.** A generator is declared with its own keyword instead of being a method that contains `yield` (author's answer to review RSB-R03, not yet applied): `generator count_to(n: Integer) => (@x: Integer) is … return;`. Replaces the detection rule of D-067.
2. **Record types.** `class Order = {id: Integer, amount: Decimal} <: Record;` declares a row type; a literal with its type hint builds a record (D-080). Used by JSON, CSV and the database layer (level 5).
3. **Time types.** Instant (a point in time, UTC), DateTime with a zone, Date, Time, Duration, with parsing and formats (review RTY-R01).
4. **Bytes.** An immutable byte buffer, with views, for files and the network (review RTY-R01).
5. **Files and paths.** Modules `fs` and `path`: read and write text and bytes, lines as a stream, list a folder, glob; the `/` operator joins paths (D-031).
6. **JSON and CSV.** `json.parse` gives a DataMap (D-080), `json.decode(:T)` a record; `csv.read(:T)` a stream of records, with the header and the separator as options; both write back.
7. **HTTP client.** `http.get`, `http.post`, `http.request` with headers, a JSON body, a time-out; a status error is an `HttpError` with the field `status` (D-081).
8. **Secrets.** A `Secret` value that never prints and never travels to a log, read from the machine configuration (D-083).
9. **Shell by argument list.** `run("ls", ("-l", path), cwd: dir)` returns the exit code and the output, next to `call` (review RIO-R03).
10. **Compression.** gzip and zip readers and writers as streams.

## Open questions

- Which of the draft features belong to version 0.2, and which move later?
- The name of the time types (Instant or Timestamp; DateTime or LocalTime).
