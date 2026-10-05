# Features inventory

The list of every large feature of Eve: language, virtual machine, tools, library, data, network and web, and documentation. Small rules belong to the decisions (`D-nnn`) and the spec; this file tracks the requirements that make a release. The versions are in [version_map.md](version_map.md). This answers review point `RPJ-R06` (`review/01-project.md`).

## How to use it

- Each feature has a stable code `F-<area>-<nn>`. Codes are never renumbered or reused; a dropped feature keeps its line, struck through, with the reason.
- `[x]` means implemented in `bin/eve.exe` (or delivered, for documents and tools) and covered by tests where tests apply. `[ ]` means open; *partial* in the text says what exists.
- `vX.Y` is the target version. Each version completes one or two levels (level 1 and 2: 0.1; 3: 0.2; 4: 0.3; 5: 0.4; 6: 0.5; 7: 0.6), see the version map. Moving a feature to another version is changed here and in the map together.
- A new large feature is added here first, then planned in a phase file, then decided (`D-nnn`), then built.
- Status checked on 2026-10-04: level 1 38/38 pass, VM tests 11/11 pass, level 2 0/19 pass, level 3 empty.

## 1. Specification and standard (`SPEC`)

- [ ] **F-SPEC-01 Lexical specification**: tokens, comments, literals, escapes, interpolation, keywords, operators, delimiters as Markdown + JSON. *Partial:* `spec/lexical/` written; `keywords.json` blocked on Q-002. · v0.1
- [ ] **F-SPEC-02 Grammar (EBNF)**: regions, declarations, statements, expressions, checked against every `.eve` file (phase 3). · v0.1
- [ ] **F-SPEC-03 Core semantics**: types, scopes, control flow, jobs and `recover`, topology, collections and objects (phase 4). *Partial:* `semantics/variables.md`. · v0.1
- [ ] **F-SPEC-04 Library specification**: built-ins and standard modules as signatures (`spec/library/`). · v0.2
- [ ] **F-SPEC-05 Multitasking semantics**: generators, parallel aspects, channels (`semantics/multitasking.md`). · v0.3
- [ ] **F-SPEC-06 Network semantics and protocol**: remote `apply`, services, Eve Wire Protocol (`spec/protocol/`). · v0.5
- [x] **F-SPEC-07 Machine-readable tables with schemas**: JSON schemas, `script/speccheck.py`. · v0.1
- [ ] **F-SPEC-08 Conformance levels**: level 1 (single script), level 2 (project: modules, aspects), levels 3 to 7 (data, parallel, database, server, web; `plan/version_map.md`), with the expected-output convention (Q-005). *Partial:* level 1 suite done, level 2 written, level 3 empty. · v0.1 (levels 1–2), v1.0 (levels 3–7)
- [ ] **F-SPEC-09 Compiler registry and approval**: how a third-party implementation claims a spec version and a level (S6.3, S6.4). · v1.0
- [x] **F-SPEC-10 Licenses and trademark**: BUSL-1.1 code, CC BY-NC-SA 4.0 spec and documents, TRADEMARK.md (D-061, D-062, D-078). · v0.1

## 2. Language core (`LNG`)

- [x] **F-LNG-01 Script shapes**: driver with `process main`, free script `#!`, title/subtitle header, comments (D-014, D-037, D-040). · v0.1
- [x] **F-LNG-02 Declarations and assignment**: `let`, `set`, `:=`, `=`, `::` clone, views (D-036, D-049). · v0.1
- [x] **F-LNG-03 Expressions and operators**: arithmetic, logic, comparison, ranges, membership, precedence (D-019, D-022). · v0.1
- [x] **F-LNG-04 Control flow**: `if`, `match`, `while`, `for`, `loop … repeat [while c]`, labels, `break`, `skip` (D-034, D-074). · v0.1
- [x] **F-LNG-05 Jobs and error recovery**: jobs, `recover` with `retry`/`resume`/`abort`, `finalize`, `raise`, `expect`, `over`, `panic`, exit codes (D-020, D-055, D-063). · v0.1
- [x] **F-LNG-06 Primitive types**: Integer, Natural, Real, Logic, Symbol, String, ordinals, type checks with `is` (D-032). *Rational, Duration, Time, Date not yet.* · v0.1
- [x] **F-LNG-07 Collections**: List, Array, Matrix, DataSet, HashMap, Object, slices, builders, deconstruction (D-058, D-064). · v0.1
- [x] **F-LNG-08 Strings and interpolation**: escapes, text literal `"""`, `\s{}` `\#{}` `\b{}` with formats, regular expressions (subset) (D-060). · v0.1
- [x] **F-LNG-09 Functions and methods**: pure functions, `!` functions, methods, `@` parameters, defaults, varargs, named arguments, lambdas, closures (D-025 to D-029, D-048, D-070). · v0.1
- [x] **F-LNG-10 Classes**: attributes, constructors, `new`, methods with `@self` (D-036). · v0.1
- [ ] **F-LNG-11 Traits, abstract classes, generics**: `trait`, partial methods, `class Name(:T)`, library traits `Iterable`, `Comparable`, `Printable` (D-039, proposed). · v0.2
- [ ] **F-LNG-12 Generators**: methods with `yield`, `Generator(:T)`, use in `for` and builders (D-067). · v0.2
- [ ] **F-LNG-13 Data types for ETL**: Decimal, Instant/DateTime with zone, Date, Time, Duration, Bytes, Uuid (review `RTY-R01`; needs a decision). · v0.2
- [ ] **F-LNG-14 Record types and optional values**: typed records for rows, JSON objects and messages; `T?` (review `RTY-R01`, `RTY-R02`; needs a decision). · v0.2
- [ ] **F-LNG-15 Typed exceptions**: error classes with fields, `recover` by type, exit-code mapping (review `RST-R01`; `exception.eve` draft exists). · v0.2
- [ ] **F-LNG-16 Static checks**: name resolution, arity, visibility and type errors before the run (exit 65). · v0.2
- [ ] **F-LNG-17 Stream type**: `Stream(:T)` shared by generators, files, queries and channels (review `RMT-R02`). · v0.3

## 3. Program structure (`STR`)

- [ ] **F-STR-01 Modules and imports**: `module`, `from … use (…)`, aliases, `(*)`, singletons, `initialize`/`finalize`, private members (D-068, D-072; tests b01–b09). · v0.1
- [ ] **F-STR-02 Aspects (serial)**: `apply`, state per call, `@` outputs, named and spread arguments, errors and `over`/`panic` across `apply` (D-066, D-072; tests b10–b17). · v0.1
- [ ] **F-STR-03 Extension methods**: `method _name(@self: Class)` at module level (D-072; test b18). · v0.1
- [ ] **F-STR-04 Projects and search paths**: project root, `asp/`, `lib/`, `data/`, `out/`, `$EVE_LIB`, `$EVE_ASP`, `$EVE_OUT` (D-055, D-073). · v0.1
- [ ] **F-STR-05 Command-line parameters of a script**: `-p`/`--param` mapped to `main` parameters, `eve script.eve -h` from `** @param` comments (D-055). · v0.1
- [ ] **F-STR-06 Configuration files**: `.cfg` with `$key = value`, loaded with `-s` (D-031). · v0.1
- [ ] **F-STR-07 System variables**: the 0.1 register (`$error`, environment, `$EVE_*`, `$err_`/`$wrn_` constants) (D-071). *Partial:* `$error` works. · v0.1
- [ ] **F-STR-08 Service script kind**: long-running entry point with routes handled by aspects (review `RNW-R02`; needs a decision). · v0.5

## 4. Multitasking (`MTK`)

- [ ] **F-MTK-01 Parallel aspects**: `parallel … do start … done`, barrier, data rules, errors as a job (D-066). · v0.3
- [ ] **F-MTK-02 Worker pool and scheduler**: `$cores`, M:N, a waiting aspect gives its core away (D-067). · v0.3
- [ ] **F-MTK-03 Channels**: `Channel(:T)`, send, receive, close, pipelines, deadlock detection, time-out (D-051). · v0.3
- [ ] **F-MTK-04 Cooperative tasks**: generators taking turns, module `task` (`round_robin`, `until`) (D-067). · v0.3
- [ ] **F-MTK-05 Deadlines and cancellation**: per-group time limits, cancel or collect errors (review `RMT-R01`). · v0.3

## 5. Virtual machine and runtime (`VM`)

- [x] **F-VM-01 Lexer and parser**: source to syntax tree, errors with file, line and column (`lexer.zig`, `parser.zig`). · v0.1
- [x] **F-VM-02 Tree-walking interpreter**: runs all of level 1 (`interp.zig`). · v0.1
- [ ] **F-VM-03 Library loader and `external` bindings**: load `.eve` library modules and bind `external` declarations to Zig (D-053, D-056). · v0.1
- [ ] **F-VM-04 Bytecode compiler and VM**: compact bytecode, heap frames (needed by generators and scheduling; review `RVM-R01`). · v0.2
- [ ] **F-VM-05 Region memory**: arena per aspect call, job and request; long-lived heap for modules and channels (review `RVM-R02`). · v0.3
- [ ] **F-VM-06 Efficient collections**: hashed and sorted maps, sets, ropes for Text (review `RVM-R04`). · v0.2
- [ ] **F-VM-07 Portable bytecode file `.evb`**: versioned, hashed, with debug lines and capabilities (review `RVM-R05`). · v0.6
- [ ] **F-VM-08 Embedding API**: the VM as a library with a C ABI (review `RVM-R07`). · v0.5
- [ ] **F-VM-09 WebAssembly build**: the VM compiled to `wasm32` with host imports (review `RVM-R06`). · v0.6
- [ ] **F-VM-10 Cross-platform releases**: Windows, Linux, macOS binaries from one build; `script/release.py` bumps versions. *Partial:* Windows build, release script. · v0.1

## 6. Tools (`TLS`)

- [x] **F-TLS-01 Command line (CLI)**: `eve script.eve`, `--check`, `--execute`, `-h`, `-v`, `-s`, `-d`, `-x`, `-i`, `-t`, exit codes 64–66 (`manual/usage.md`). · v0.1
- [ ] **F-TLS-02 REPL**: prompt, file completion, commands `check`, `execute`, `setup`, `help`, `quit`. *Partial:* scaffold; `compile`, `debug`, `begin`, `enter`, `print`, `resume`, `stop`, `clear`, `setup` not implemented. · v0.2
- [ ] **F-TLS-03 Interactive interpreter**: evaluate Eve statements and expressions typed at the prompt, keep the session scope. · v0.2
- [ ] **F-TLS-04 Debugger**: debug mode, `halt` breakpoints, step, print variables, reports (`manual/usage.md`). · v0.3
- [x] **F-TLS-05 Command files and serve mode** (scheduled for removal, replaced by F-TLS-13, D-083): `.vmc` slot, workflow commands `load`, `parse`, `run`, `errors`, `ast`, `inspect`, `status` (D-063; tests v01–v11). · v0.1
- [x] **F-TLS-06 Test runner**: `script/runtest.py` for levels, project tests, `expect.json`, `.out`, reports in `temp/output/`; `script/workflow.py` (D-009, D-073). · v0.1
- [x] **F-TLS-07 Documentation generator `eve --doc`**: Markdown from `**` comments and signatures, a command of the VM (D-053, D-082). · v0.1
- [ ] **F-TLS-08 Formatter and linter**: `eve fmt`, `eve lint` (indentation, style rules; review `RSY-R06`). · v0.3
- [ ] **F-TLS-09 Editor support**: syntax colors for VS Code and GitHub, then a language server (`tools/TODO-vscode-plugin.md`). *Partial:* tutorial highlighters `eve1.js`, `eve3.js`. · v0.3
- [ ] **F-TLS-10 Package manager**: library folders, versions, dependencies, a registry. · v0.9
- [ ] ~~**F-TLS-11 Daemon mode**~~: replaced by F-TLS-13, a machine that listens (D-083).
- [ ] **F-TLS-12 Machine setup**: `--setup <folder>`, the machine folder, `eve.cfg`, built-in defaults, identity domain + port, external checksum, `setup` reload (D-083). · v0.5
- [ ] **F-TLS-13 Remote control**: `--listen`, `eve -c`, `-r`, `-u` upload, `send` between machines, sessions and driver memory spaces (`load`, `dismiss`); then the removal of `.vmc` command files (D-083). · v0.5
- [ ] **F-TLS-14 Local HTTP**: `serve` on port 8042, pages of the web folder, routes of `service` scripts (D-083). · v0.5
- [ ] **F-TLS-15 Eve API for AI**: `eve --api`, an MCP server whose tools are the commands of the machine (D-083). · v0.5

## 7. Standard library (`LIB`)

- [ ] **F-LIB-01 Console I/O**: `print`, `write`, `read`, `error`, `warning`, `log_err`, `log_wrn` (D-053, D-057). *Partial:* `print`/`write` in the VM, `io.eve` draft, log files open (b19). · v0.1
- [ ] **F-LIB-02 Exception module**: `Error`, `Warning`, `raise`, `expect`, `assert`, `warn`, code constants (D-054 to D-056). *Partial:* `exception.eve` draft. · v0.1
- [ ] **F-LIB-03 Strings, math, collections and type conversions**: `split`, `join`, `format`, `parse`, `floor`, `round`, sort, search (S5.1). · v0.1
- [ ] **F-LIB-04 Files and paths**: `fs` and `path` modules, text and bytes, line streams, globbing (review `RIO-R01`). · v0.2
- [ ] **F-LIB-05 Data formats**: JSON and CSV read/write, decode into records; later XML, Parquet. · v0.2
- [ ] **F-LIB-06 Time and dates**: `now`, parse, format, zones, durations. · v0.2
- [ ] **F-LIB-07 Shell commands**: `call` with pipes, and a safe `run(cmd, args, cwd)` (command.html; review `RIO-R03`). · v0.2
- [ ] **F-LIB-08 Secrets**: a `Secret` type and `secret.get` from environment, file or vault (review `RIO-R01`). · v0.2
- [ ] **F-LIB-09 Compression and archives**: gzip, zip, stream codecs (manifest). · v0.2
- [ ] **F-LIB-10 Encryption and hashing**: hashes, HMAC, symmetric encryption (manifest). · v0.5
- [ ] **F-LIB-11 Logging and observability**: structured logs, job events, run reports, trace ids (review `RST-R07`, `RNW-R09`). · v0.3

## 8. Data and ETL (`DAT`)

- [ ] **F-DAT-01 Database layer**: connect, parameterized query as a stream, execute, transactions, bulk load (databases.html; review `RIO-R02`). · v0.4
- [ ] **F-DAT-02 Database drivers**: PostgreSQL and SQLite first, then MySQL and Oracle. · v0.4 (PostgreSQL, SQLite), v0.9 (others)
- [ ] **F-DAT-03 ETL pipeline model**: extract, transform, load with jobs and aspects; dead-letter output; the pattern taught in the tutorial (review `RIO-R04`). · v0.4
- [ ] **F-DAT-04 Checkpoints and restart**: resume a failed pipeline at the last committed batch (review `RIO-R05`). · v0.4
- [ ] **F-DAT-05 Columnar tables**: `Table` type with typed columns, Arrow-compatible (review `RTY-R06`). · v0.4
- [ ] **F-DAT-06 Data lineage and run reports**: inputs, outputs, row counts, durations per job and aspect (review `RIO-R06`). · v0.4
- [ ] **F-DAT-07 Database synchronization**: keep two databases consistent (manifest). · v0.9
- [ ] **F-DAT-08 The Eve database**: one database per machine in its `db/` folder, SQLite embedded (DuckDB optional), for checkpoints, run history, lineage, staging and small applications (`plan/design-database.md`). · v0.4
- [ ] **F-DAT-09 Database admin commands**: `db list`, `db add`, `db test`, `db info`, `db tables`, `db describe`, `db sql`, `db create`, `db backup`, `db restore`, `db export`, `db import`, `db compact`, `db runs`. · v0.4
- [ ] **F-DAT-10 Schema migrations**: numbered SQL scripts in `db/migrations/<name>/`, applied by `db migrate` and recorded in the Eve database. · v0.4
- [ ] **F-DAT-11 Record-table mapping**: record types with `TABLE` and `KEY`; `find`, `save!`, `remove!`, one SQL statement each. · v0.4

## 9. Network and server (`NET`)

- [ ] **F-NET-01 HTTP client**: requests, headers, JSON bodies, time-outs, TLS (review `RNW-R10`). · v0.2
- [ ] **F-NET-02 HTTP server**: routes, request and response records, static files, one state per request (review `RNW-R02`). · v0.5
- [ ] **F-NET-03 Eve Wire Protocol (EWP)**: framed binary protocol for Eve-to-Eve calls and data streams, flow control, resumable streams (review `RNW-R04`). · v0.5
- [ ] **F-NET-04 Remote apply**: run an aspect on another node with a deadline and an idempotency key (review `RNW-R01`). · v0.5
- [ ] **F-NET-05 Capabilities and sandbox**: fs, net, db, shell permissions per project and per aspect (review `RNW-R08`). · v0.5
- [ ] **F-NET-06 Authentication**: tokens, sessions, TLS certificates for services. · v0.5

## 10. Web (`WEB`)

- [ ] **F-WEB-01 HTML templates**: `Html` type, context-aware escaping, template files, components (review `RNW-R05`). · v0.6
- [ ] **F-WEB-02 Eve in the browser**: the WASM VM runs signed `.evb` code with limited capabilities, `dom` module (review `RNW-R06`). · v0.6
- [ ] **F-WEB-03 Tutorial playground**: a "Run" button on tutorial examples using the WASM VM. · v0.6
- [ ] **F-WEB-04 Web application kit**: service + EWP feed + browser client, deployment guide. · v0.9

## 11. Documentation (`DOC`)

- [ ] **F-DOC-01 Tutorial, language part**: 19 topic pages reviewed and consistent with the decisions (phase 1, T1.10). *Partial:* 5 pages reviewed and answered. · v0.1
- [ ] **F-DOC-02 Tutorial, data client part**: files, formats, streams, HTTP client, ETL pipelines (review `RTU` phase T1). · v0.2
- [ ] **F-DOC-03 Tutorial, network and web part**: client and server, services, protocol, security, HTML, WebAssembly (review `RTU` phases T2, T3). · v0.5–v0.6
- [ ] **F-DOC-04 Compiler manual**: implement, usage, generated feature tables, implemented features (phase 7). *Partial:* `manual/usage.md`. · v0.1
- [ ] **F-DOC-05 Library reference**: generated by `eve --doc` for every standard module. *Partial:* io, exception. · v0.2
- [ ] **F-DOC-06 Compiler course**: the student track: milestones, bytecode, memory, scheduling, WASM (compiler.html). · v1.0
