# Decisions, level 3: data language (version 0.2)

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. Ids are shared by all the decision files and keep counting across them; a new entry goes to the file of its topic. The levels and their versions are in [version_map.md](version_map.md).

| File | Level | Topic | Version | Tests |
|---|---|---|---|---|
| [decision_level1.md](decision_level1.md) | 1 | the project, and the language of a single script | 0.1 | `test/level1` (a) |
| [decision_level2.md](decision_level2.md) | 2 | a project: aspects, and the procedures and functions inside them | 0.1 | `test/level2` (b) |
| [decision_level3.md](decision_level3.md) | 3 | modules and imports, libraries, data language: types, records, generators, files, formats, HTTP client | 0.2 | `test/level3` (c) |
| [decision_level4.md](decision_level4.md) | 4 | parallel processing and streams | 0.3 | `test/level4` (d) |
| [decision_level5.md](decision_level5.md) | 5 | database layer and the Eve database | 0.4 | `test/level5` (e) |
| [decision_level6.md](decision_level6.md) | 6 | the Eve machine and the server | 0.5 | `test/level6` (f) |
| [decision_level7.md](decision_level7.md) | 7 | web: HTML and WebAssembly | 0.6 | `test/level7` (g) |

## Scope

A driver reads and writes real data with the right types: Decimal, dates and times, records, optional values; it reads files, JSON and CSV, calls web services over HTTP, and produces values lazily with generators. The bytecode VM arrives at this level, because generators need a method that can stop and continue.

Moved from level 2 (D-112, 2026-10-07): modules, imports, libraries, extension methods across files and the library search path (`lib/`, `$EVE_LIB_PATH`, the standard library first). Tests c01 to c09; features F-STR-01 and F-STR-03.

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

## Q-024 The system library: names and members (2026-10-06)
The page `syslib.html` lists the modules that connect a program to the machine: `io`, `exception`, `fs`, `path`, `time`, `secret`, `task`, `database`, `http`, with their level and status; only `io` and `exception` are drafted (`evevm/lib/`). Are these the names and the split you want (for example one `fs` and `path`, or one `file` module)? Is the shell `call` part of the system library or of the language? Which module holds the time types (`time`), given that Date and Time have their own page?
**Answer:**

## Q-038 Data file types: Json, Csv, Dat, Xml, Html, Htmlt (2026-10-08)
Author request: types for the files that a program loads and parses in memory: HTML, XML, HTMLT (HTML template), CSV, DAT (fixed width data) and JSON. The load is buffered and works in loops, a kind of traversal: row by row, or element by element (object by object) for JSON. All of them are derived with `<:` and defined mostly in Eve, at a later time. A first proposal is in `spec/semantics/data-types.md` and in the section "Data File Types" of `types.html`. Open points:
- (a) The names: `Json`, `Csv`, `Dat`, `Xml`, `Html`, `Htmlt`. `Html` is also the safe page type of the templates (Q-027): one type, or `Html` for the parsed file and another name for the safe page?
- (b) The common ancestor of the six classes (`Source`? `Document`?) and the traversal protocol: what a class must define so that `for unit in value do` works (an iterator, a generator?).
- (c) How a unit is read: `row["name"]`, `row.name`, `row[2]`; the type of a field (String until converted, or declared in a layout).
- (d) `Dat`: how the layout of the fixed width fields is declared (a class, a list of widths, a file).
- (e) The modules (`csv`, `json`, ...) or a single `load`; reading a stream from the network as well as a file; writing a file of these types.
- (f) Encoding and the line ending; the error when a unit is not well formed (raised when the loop reaches it).
- (g) Levels: `Csv` and `Json` in level 3, `Html` and `Htmlt` with the templates (0.6), `Xml` and `Dat` open.
**Answer:**

## D-123 A class hosts only methods; only a method has @self (2026-10-08)
Author decision. Inside a class body only `constructor`, `destructor` and `method` are declared: a `function` or a `procedure` there is a compile error (before, D-103 allowed private functions). A function or a procedure can not be bound to a class with `@self`: `@self` belongs to methods only, in the class body or outside it as an extension method (D-086). A helper of a class is a private method or a function outside the class. Tests: c15 (procedure in a class), c16 (function with `@self`), c17 (function in a class). The parser reports both errors. Applied: `syntax/declarations.md`.
