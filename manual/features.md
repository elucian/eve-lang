# Features

Every feature of Eve has a code `F-<area>-<nn>` and belongs to a level. Its **stage** says how far it is:

| Stage | Meaning |
|---|---|
| validated | implemented in `eve`, and its tests pass |
| drafted | specified, or its tests are written; the implementation is missing or partial |
| planned | named for a level; work has not started |

Each level has a page of its own, with every feature described and an example that runs.

## Summary

<!-- GEN:summary -->
| Level | Validated | Drafted | Planned | Total |
|---|---|---|---|---|
| Level 1 | 14 | 5 | 0 | 19 |
| Level 2 | 3 | 0 | 0 | 3 |
| Level 3 | 5 | 8 | 1 | 14 |
| Level 4 | 5 | 8 | 2 | 15 |
| Level 5 | 7 | 14 | 8 | 29 |
| Level 6 | 0 | 6 | 23 | 29 |
| Level 7 | 0 | 2 | 8 | 10 |
| All levels | 13 | 5 | 7 | 25 |
| **All** | **47** | **48** | **49** | **144** |
<!-- /GEN:summary -->

## By level

<!-- GEN:list -->
### [Level 1: The language of a single script](levels/level1.md)

A script that runs from its first line to its last, with no user subprograms and no classes. It has declarations and assignment, expressions and operators, control flow, strings with interpolation, the primitive types and the collections, and jobs with error recovery. This level is the core of the lexical and syntactic specification, the first lexer and parser, and the tree-walking interpreter, which stay the reference for the bytecode machine.

| Code | Feature | Stage | What it is |
|---|---|---|---|
| `F-LIB-01` | Console I/O | drafted | print, write, read, error, warning, log_err, log_wrn. |
| `F-LIB-02` | Exception module | drafted | Error, Warning, raise, expect, assert, warn, code constants. |
| `F-LIB-13` | DataMap methods | validated | has, get(k), get(k, default), keys, values, delete. |
| `F-LNG-01` | Script shapes | validated | Aspect with process main, title/subtitle header, comments; no free script and no #!. |
| `F-LNG-02` | Declarations and assignment | validated | let, set,:=, =,:: clone, views. |
| `F-LNG-03` | Expressions and operators | validated | Arithmetic, logic, comparison, ranges, membership, precedence. |
| `F-LNG-04` | Control flow | validated | if, match, while, for, loop … repeat [while c], labels, break, skip. |
| `F-LNG-05` | Jobs and error recovery | validated | Jobs, recover with retry/resume/abort, finalize, raise, expect, over, panic, exit codes. |
| `F-LNG-06` | Primitive types | validated | Integer, Natural, Real, Logic, Symbol, String, ordinals, type checks with is. |
| `F-LNG-07` | Collections | validated | List, Array, Matrix, DataSet, HashMap, Object, slices, builders, deconstruction. |
| `F-LNG-08` | Strings and interpolation | validated | Escapes, text literal """, placeholders {name}, {literal}, simple expressions and formats {n % i5}, code points {U+H}, HTML entities &name;, regular expressions (subset). |
| `F-SPEC-01` | Lexical specification | validated | Tokens, comments, literals, escapes, placeholders, keywords, operators, delimiters as Markdown + JSON. |
| `F-SPEC-02` | Grammar (EBNF) | validated | Declarations, statements, expressions, modules and imports, checked against every.eve test by script/grammarcheck.py (199 of 199 files of levels 1 to 4 and the smoke test). |
| `F-SPEC-03` | Core semantics | drafted | Types, scopes, control flow, jobs and recover, topology, collections and objects. |
| `F-STR-05` | Command-line parameters of a script | drafted | -p/--param mapped to main parameters, eve script.eve -h from  @param comments. |
| `F-STR-07` | System variables | drafted | The register ($error, environment names such as $HOME, $epsilon, $err_/$wrn_ constants). |
| `F-STR-12` | Exit code of the program | validated | over n; and exit n; give the exit code: 0, or 6 to 125 (1 to 5 belong to the machine); anything else is $err_argument. |
| `F-VM-01` | Lexer and parser | validated | Source to syntax tree, errors with file, line and column (lexer.zig, parser.zig). |
| `F-VM-02` | Tree-walking interpreter | validated | Runs levels 1 to 3, the smoke test and the benchmarks (interp.zig, project.zig); 193 tests. |

### [Level 2: A project: subprograms and aspects](levels/level2.md)

A script becomes a project: functions, procedures, lambdas and closures, and aspects, the units of work that `apply` calls with copy-in parameters, with errors recovered across `apply` and a log per call. Configuration files belong here. 

| Code | Feature | Stage | What it is |
|---|---|---|---|
| `F-LNG-09` | Functions and methods | validated | Pure functions, ! functions, procedures, @ parameters, defaults, varargs, named arguments, lambdas, closures, recursion. |
| `F-STR-02` | Aspects (serial) | validated | apply, state per call, @ outputs, named and spread arguments, errors and over/panic across apply, exclusive by default, concurrent kind. |
| `F-STR-06` | Configuration files | validated | .cfg with $key = value, loaded with -s. |

### [Level 3: Modules and classes](levels/level3.md)

Programs in several files: modules and imports, local libraries, managed and direct modules, extension methods, and then classes and methods with constructors, visibility and inheritance. The standard library of the language is also written as modules from this level on. 

| Code | Feature | Stage | What it is |
|---|---|---|---|
| `F-DOC-05` | Library reference | drafted | Generated by eve --doc for every standard module. |
| `F-LIB-03` | Strings, math, collections and type conversions | drafted | split, join, format, parse, floor, round, sort, search. |
| `F-LNG-10` | Classes | validated | Attributes, constructors, new, methods with @self, inheritance, visibility; a class hosts only methods and only a method has @self. |
| `F-LNG-15` | Typed exceptions | drafted | Error classes with fields, recover by type, exit-code mapping. |
| `F-LNG-16` | Static checks | drafted | Name resolution, arity, visibility and type errors before the run (exit 65). |
| `F-LNG-19` | Managed and direct modules | validated | managed module / direct module (default), per-member thread safety proved by the compiler, a concurrent aspect calls only safe members. |
| `F-LNG-22` | External routines and errors of modules | validated | An external routine of a module whose name is that of a native module (os, fs, crypto,...) is bound to the native of the same name; an error raised in a module names the file of the module and the... |
| `F-SPEC-04` | Library specification | drafted | Built-ins and standard modules as signatures. |
| `F-STR-01` | Modules and imports | validated | module, from … use (…), aliases, m,, singletons, initialize/recover/finalize, export, private members, circular imports, $err_module. |
| `F-STR-03` | Extension methods | validated | method name(@self: Class) outside the class. |
| `F-STR-04` | Projects and search paths | drafted | Project root $EVE_HOME, asp/, lib/, data/, web/ (templates), out/, $EVE_LIB, $EVE_LIB_PATH. |
| `F-TLS-02` | REPL | drafted | Prompt, file completion, commands check, execute, help, quit; 2026-10-13: the full-screen interface at a terminal (upper part with scrollback, command line between two rules, status bar with Ready /... |
| `F-TLS-03` | Interactive interpreter | planned | Evaluate Eve statements and expressions typed at the prompt, keep the session scope. |
| `F-VM-03` | Library loader and `external` bindings | drafted | Load.eve library modules and bind external declarations to Zig. |

### [Level 4: Parallel processing](levels/level4.md)

Many cores and many waits: parallel groups, channels, streams with back-pressure, tasks in a job (`async`, `spawn`, `await`), deadlines and cancellation, and region memory. Generics for classes, traits and abstract classes also arrive here. The results of parallel code must be deterministic: it is 

| Code | Feature | Stage | What it is |
|---|---|---|---|
| `F-LIB-11` | Logging and observability | planned | Structured logs, job events, run reports, trace ids. |
| `F-LIB-12` | Testing module `test` | validated | Checks that print ok/FAIL, counters, summary that raises. |
| `F-LNG-11` | Traits, abstract classes, generics | drafted | trait, required methods, abstract classes, class Name(:T) with Box(:Integer)(5), constraints (:T <: Comparable), library traits Iterable, Stream, Comparable, Printable. |
| `F-LNG-17` | Stream type | drafted | Stream(:T) <: Iterable(:T), read by for with back-pressure; at level 4 Channel(:T) is the stream, and lists get batch(n) and split(k). |
| `F-LNG-18` | `Atomic(:T)` | drafted | A class of the standard library that wraps the atomic of the machine, for Logic, numbers, references and ordinals; class Name <: Atomic(:T). |
| `F-MTK-01` | Parallel aspects | validated | parallel … do start … done, barrier, data rules, errors as a job. |
| `F-MTK-02` | Worker pool and scheduler | drafted | $cores, M:N, a waiting aspect gives its core away. |
| `F-MTK-03` | Channels | validated | Channel(:T), send, receive, close, pipelines, deadlock detection, time-out. |
| `F-MTK-04` | Tasks in a job | validated | async subprograms, spawn, await; the tasks of a job share its core. |
| `F-MTK-05` | Deadlines and cancellation | validated | Per-group time limits, cancel or collect errors. |
| `F-SPEC-05` | Multitasking semantics | drafted | semantics/multitasking.md: parallel groups, channels, tasks in a job, durations, determinism. |
| `F-TLS-04` | Debugger | drafted | Debug mode, halt breakpoints, step, print variables, reports. |
| `F-TLS-08` | Formatter and linter | planned | eve fmt, eve lint. |
| `F-TLS-09` | Editor support | drafted | Syntax colors for VS Code and GitHub, then a language server. |
| `F-VM-05` | Region memory | drafted | Arena per aspect call, job and request; long-lived heap for modules and channels. |

### [Level 5: Data and database](levels/level5.md)

The data language and the ETL core: real data with the right types (`Decimal`, `Instant`, records, tables, `Secret`), files and formats (CSV, JSON, text), the HTTP client, generators, generic functions, overloading and the Eve macro, and the database layer with connections, query streams, bulk loads, transactions per job, checkpoints, lineage and the Eve database. It is done when JSON and CSV round-trip, a killed load restarts from its checkpoint, level 5 passes against SQLite and a PostgreSQL server, and `db backup` and `db restore` round-trip.

| Code | Feature | Stage | What it is |
|---|---|---|---|
| `F-DAT-01` | Database layer | drafted | Connect, parameterized query as a stream, execute, transactions, bulk load. |
| `F-DAT-03` | ETL pipeline model | drafted | Extract, transform, load with jobs and aspects; dead-letter output; the pattern taught in the tutorial. |
| `F-DAT-04` | Checkpoints and restart | drafted | Resume a failed pipeline at the last committed batch. |
| `F-DAT-05` | Columnar tables | drafted | Table type with typed columns, Arrow-compatible. |
| `F-DAT-06` | Data lineage and run reports | planned | Inputs, outputs, row counts, durations per job and aspect. |
| `F-DAT-08` | The Eve database | planned | The core database: one per project in its db/ folder (default local.db, name set in eve.cfg, system variable $EVE_CORE_DB), SQLite embedded (3.54.0, compiled into the VM from the amalgamation... |
| `F-DAT-09` | Database admin commands | planned | db list, db add, db test, db info, db tables, db describe, db sql, db create, db backup, db restore, db export, db import, db compact, db runs. |
| `F-DAT-10` | Schema migrations | planned | Numbered SQL scripts in db/migrations/<name>/, applied by db migrate and recorded in the Eve database. |
| `F-DAT-11` | Record-table mapping | validated | table declarations binding record classes to tables, tracked records with dirty fields, updates of the changed fields only, mapping validated in debug mode and refused in production. |
| `F-DAT-13` | `sql function` | drafted | An Eve function marked sql function is registered on every SQLite and DuckDB connection and called from SQL; deterministic, one result, SQL types, not overloaded; SQL NULL only for nullable types; an... |
| `F-DAT-14` | Stored procedures | drafted | Native procedures in sql/ called through external signatures; Eve procedures in proc/, run by the database part, listed by eve db proc list, reloaded by eve db proc reload, called by db.call... |
| `F-DOC-02` | Tutorial, data client part | planned | Files, formats, streams, HTTP client, ETL pipelines. |
| `F-LIB-04` | Files and paths | drafted | fs and path modules, text and bytes, line streams, globbing. |
| `F-LIB-05` | Data formats | drafted | JSON and CSV read/write, decode into records; later XML, Parquet. |
| `F-LIB-06` | Time and dates | drafted | now, parse, format, zones, durations. |
| `F-LIB-07` | Shell commands | drafted | call with pipes, and a safe run(cmd, args, cwd). |
| `F-LIB-08` | Secrets | drafted | A Secret type and secret.get from environment, file or vault. |
| `F-LIB-09` | Compression and archives | planned | Gzip, zip, stream codecs (manifest). |
| `F-LNG-12` | Generators | validated | Methods with yield, Generator(:T), use in for and builders. |
| `F-LNG-13` | Data types for ETL | drafted | Decimal, Instant/DateTime with zone, Date, Time, Duration, Bytes, Uuid. |
| `F-LNG-14` | Record types and optional values | drafted | Typed records for rows, JSON objects and messages; T?. State: records, null in plain fields and printing of null are tested; the full optional type is in spec/library/data-language.md. |
| `F-LNG-20` | Generic functions and procedures | validated | A first parameter list of types, function largest(:T <: Comparable)(items:T), called largest(xs) (types inferred) or largest(:Integer)(xs); also procedures, methods and processes; no type list on a... |
| `F-LNG-21` | Overloading | validated | Functions, procedures and methods share a name with different signatures: number and types of the parameters, and the result type of a function; resolved at compile time, the call must match one... |
| `F-NET-01` | HTTP client | planned | Requests, headers, JSON bodies, time-outs, TLS. |
| `F-STR-09` | Eve macro (hybrid script) | validated | One self-contained file: shared declarations and several aspects, exactly one of them primary; apply (level 2) and parallel/start (level 4) inside it; a concurrent aspect uses only the thread-safe... |
| `F-STR-10` | Unified aspect | validated | No driver keyword, no free script, no #!; the kinds exclusive, concurrent and primary; main and private processes; calls between aspects at most three levels deep and without a cycle; a concurrent... |
| `F-STR-11` | `recover` in a function, procedure and method | validated | The end of recover handles the error and the routine returns normally; abort passes it on; no recover in a constructor, generator or lambda. |
| `F-VM-06` | Efficient collections | planned | Hashed and sorted maps, sets, ropes for Text. |
| `F-VM-11` | One `eve`, its source in modules | drafted | The modules evecm, evecp, evevm, evedb, eveux and cmd with one build; one binary whose first word chooses the part, eve vm, cp, db, ux; the serving machine as one process. |

### [Level 6: The Eve machine and the server](levels/level6.md)

The Eve machine and the server: setup from a folder, control by scripts and by other machines through the doors (IPC, stdio, HTTP), sessions and the machine API `vm.*`, services and routes written in Eve, the editors' link to the machine, and the clients of the machine: `eve` with a user (`-u`, `-a`), the terminal IDE evetx and the native workbench eveux. Capabilities and the Eve Wire Protocol are still open. 

| Code | Feature | Stage | What it is |
|---|---|---|---|
| `F-DAT-15` | The user cache `eve.db` | planned | A SQLite cache of the user (<user data folder>/eve/meta/eve.db): projects, machines without secrets, history of commands, upload manifest; the Meta interface of evecm, implemented by evedb; rebuilt... |
| `F-DOC-03` | Tutorial, network and web part | planned | Client and server, services, protocol, security, HTML, WebAssembly. |
| `F-LIB-10` | Encryption and hashing | drafted | Hashes, HMAC, symmetric encryption (manifest). |
| `F-NET-02` | HTTP server | drafted | Routes, request and response records, static files, one state per request. |
| `F-NET-03` | Eve Wire Protocol (EWP) | planned | Framed binary protocol for Eve-to-Eve calls and data streams, flow control, resumable streams. |
| `F-NET-04` | Remote apply | planned | Run an aspect on another node with a deadline and an idempotency key. |
| `F-NET-05` | Capabilities and sandbox | planned | Fs, net, db, shell permissions per project and per aspect. |
| `F-NET-06` | Authentication | planned | Tokens, sessions, TLS certificates for services. |
| `F-NET-07` | Machine login: single sign-on and the keyring | planned | From one local machine, a login per remote machine: single sign-on (OpenID Connect), an account of the machine, or a machine token; the renewal token kept in the keyring of the operating system... |
| `F-NET-08` | The machine API | drafted | JSON-RPC 2.0 methods named by part: vm.ping, vm.stat, vm.run, vm.eval, vm.suspend, vm.resume, vm.inspect, vm.cancel, vm.stop; db.; the first names of answered until level 6; no TLS in the machine, a... |
| `F-NET-09` | Credentials, connect and upload | planned | Two ways to give credentials: the unversioned eve.env of the project, or a user name and password or a connection string username/password@machine_name; eve --connect before eve --upload; the upload... |
| `F-NET-10` | Time-outs of the waiting calls | drafted | Socket.set_timeout(ms) (a read fails with $err_timeout), service.idle(ms) and the reply 408, os.run! with timeout_ms (status 124). |
| `F-SPEC-06` | Network semantics and protocol | planned | Remote apply, services, Eve Wire Protocol. |
| `F-STR-08` | Service script kind | planned | Long-running entry point with routes handled by aspects. |
| `F-TLS-12` | Machine setup | planned | --setup <folder>, the machine folder, eve.cfg, built-in defaults, identity domain + port, external checksum, setup reload. |
| `F-TLS-13` | Remote control | planned | --listen, eve -c, -rem, -u upload (2026-10-14: the user interface is -ux and the terminal IDE -tx; the upload of is --upload), send between machines, sessions and driver memory spaces (load... |
| `F-TLS-14` | Local HTTP | planned | serve on port 8042, pages of the web folder, routes of service scripts. |
| `F-TLS-15` | Eve API for AI | planned | eve --api, an MCP server whose tools are the commands of the machine. |
| `F-TLS-19` | eveux, the RAD Workbench: shell | planned | an Eve project (service script, aspects, modules) run by the local machine, with a browser part in plain JavaScript and CSS: screen and menus, editor with syntax colors for Eve, SQL, JSON, XML and... |
| `F-TLS-20` | eveux: direct SQL and database tree | planned | SQL mode of the command window and SQL tabs, results in a grid with Eve types, Commit and Rollback, the database object tree of the connections of a machine, import wizard (code/eveux/ §7... |
| `F-TLS-21` | eveux: jobs, logs and admin | planned | job browser and scheduler forms over the remote scheduler of every connected machine, live run output, stage view of the aspects, resume from checkpoint, log inspector, admin pages of a machine... |
| `F-TLS-22` | eveux: debugger | planned | breakpoints in the gutter, step into, over and out, variable inspector, watch window, call stack; needs the debugger of the machine (F-TLS-04) and the commands proposed in. |
| `F-TLS-24` | evetx, the terminal IDE: files, editor, run, machines | drafted | eve -tx: a full-screen TUI on libvaxis (Zig package, no binding); the title and the main menu (click, or Ctrl+Enter; Save and Save As), two searches under the title bar, each above its panel (names... |
| `F-TLS-26` | REPL: selected machine | planned | select <machine>, the machine in the status bar (Ready: connection: local), Ctrl+Left/Right and F1 (local), F2, F3 to change machine, Ctrl+Up/Down for the history of commands, help and Tab by machine... |
| `F-TLS-27` | evetx: debugger | planned | Breakpoints in the gutter and the Breaks tab (remove, double click to jump), Step into, Step out, Continue, Stop, the Watch tab; needs the debugger of the machine (F-TLS-04 b); the same API serves... |
| `F-TLS-28` | evetx: databases | planned | A database file in the tree opens a table list in a tab; the data of a table in a new tab; the structure of a table in a dialog that is a grid with headers and bordered cells, a drop-down for the... |
| `F-TLS-29` | evetx: file card | planned | A text file opens in the editor as source (Markdown too); any other file, images, SVG, audio and video included, opens a card with its facts and no preview; the rendered view is in eveux. |
| `F-TLS-30` | Service mode | drafted | eve -s: the machine with no user interface, silent, both doors, a log and a pid file; a Windows service under the Service Control Manager, a Linux daemon, or the foreground form... |
| `F-TLS-31` | eveux: source control | planned | Code started: code/eveux/src/vcs/git_status.zig. |

### [Level 7: The web](levels/level7.md)

The web: safe HTML templates, Eve in the browser, and the Eve Web Portal evewp, written in Eve with no JavaScript, as the last and hardest test of the language. Level 7 is the server: evedb, the Eve machine with DuckDB inside, and the portal. The development clients evetx (terminal) and eveux (native window) belong to level 6. Nothing here is built yet; the first step is a trial build of the machine for WebAssembly. It will be 

| Code | Feature | Stage | What it is |
|---|---|---|---|
| `F-DAT-12` | evedb, the Eve test database | drafted | A database server in Zig around DuckDB, outside the VM, that speaks the database frames of EWP; the remote database of the level 5 tests, with fault injection and a statement log... |
| `F-TLS-23` | New project | drafted | project init <folder> and project new <folder>: init also works on an existing project and never overwrites; new fails on a non-empty folder. |
| `F-VM-09` | WebAssembly build | planned | The VM compiled to wasm32 with host imports. |
| `F-VM-12` | Process supervision API | planned | os handles for spawn with limits, wait, kill and signals, status of a child through its IPC door; used by the host of evewp. |
| `F-WEB-01` | HTML templates | planned | HTML type, context-aware escaping, template files, components. |
| `F-WEB-02` | Eve in the browser | planned | The WASM VM runs signed.evb code with limited capabilities, dom module. |
| `F-WEB-03` | Tutorial playground | planned | A "Run" button on tutorial examples using the WASM VM. |
| `F-WEB-05` | evewp: edge and host | planned | The Eve Web Portal as the production edge: host table by Host header (domains, subdomains, wildcards), static files, proxy to the Eve machine of each application, request log and limits; the host... |
| `F-WEB-06` | evewp: monitor | planned | A graphic health server written in Eve: connections, requests, domains, users, applications, memory, logs, alerts; SVG charts and pages with no JavaScript, live updates through the framework... |
| `F-WEB-07` | The Eve Web framework | planned | Eve (a dialect with a browser profile) written once and compiled to WebAssembly modules that run in the page: stage W1 the VM in Wasm running source or.evb, stage W2 a typed subset compiled to Wasm... |

### [All levels: Tools, documents, bytecode and release](levels/all.md)

Work that does not belong to one level. The tools: the command line, the test runner, the documentation generator, the smoke test and the benchmarks; the documents: the tutorial, the compiler manual, the specification tables and the licenses; the second engine, the bytecode compiler and machine, the portable `.evb` file and the embedding API; and the road to a stable release: package manager, hardening, the compiler registry and the compiler course. A feature here is checked at every level, for example by running all levels on both engines.

| Code | Feature | Stage | What it is |
|---|---|---|---|
| `F-DAT-07` | Database synchronization | planned | Keep two databases consistent (manifest). |
| `F-DOC-01` | Tutorial, language part | drafted | The topic pages reviewed and consistent with the decisions. |
| `F-DOC-04` | Compiler manual | drafted | Implement, usage, generated feature tables, implemented features. |
| `F-DOC-06` | Compiler course | planned | The student track: milestones, bytecode, memory, scheduling, WASM (compiler.html). |
| `F-DOC-07` | Manual generator | validated | generator/evegen.py builds the manual from the features of the specification, the tracking files of the tests and the benchmark history, writes an index of the specification and... |
| `F-SPEC-07` | Machine-readable tables with schemas | validated | JSON schemas, script/speccheck.py. |
| `F-SPEC-08` | Conformance levels | drafted | Level 1 (a single script), level 2 (functions, procedures, lambdas, aspects), level 3 (modules, classes), levels 4 to 7, with the expected-output convention. |
| `F-SPEC-09` | Compiler registry and approval | planned | How a third-party implementation claims a spec version and a level (S6.3, S6.4). |
| `F-SPEC-10` | Licenses and trademark | validated | BUSL-1.1 code, CC BY-NC-SA 4.0 spec and documents, TRADEMARK.md. |
| `F-TLS-01` | Command line (CLI) | validated | eve script.eve, --check, --execute, -h, -v, -s, -d, -x, -i, -t, exit codes 64–66. |
| `F-TLS-05` | Command files and serve mode | validated | (scheduled for removal, replaced by F-TLS-13):.vmc slot, workflow commands load, parse, run, errors, ast, inspect, status. |
| `F-TLS-06` | Test runner | validated | script/runtest.py for levels, project tests, several drivers per project, /@expect/ blocks, reports in JSON for the tests that fail, and the result of every run in the tracking file of the suite... |
| `F-TLS-07` | Documentation generator `eve --doc` | validated | Markdown from  comments and signatures, a command of the VM. |
| `F-TLS-10` | Package manager | planned | Library folders, versions, dependencies, a registry. |
| `F-TLS-16` | Smoke test | validated | 16 small scripts, one feature each, in less than a second, independent of the other tests. |
| `F-TLS-17` | Benchmarks | validated | One per level with a twin in Python, a history of the runs. |
| `F-TLS-18` | Tutorial pages of the tests | validated | features.html and quality.html generated from the tests and the benchmarks (script/genpages.py). |
| `F-TLS-32` | Test tracking files | validated | One JSON file per suite, test/<suite>/<suite>.json, for the levels and for the special tests (smoke, bytecode, scaffold): status, runs, failures, date and reason of every test, and the features of... |
| `F-VM-04` | Bytecode compiler and VM | drafted | Register machine with 32-bit instructions. |
| `F-VM-07` | Portable bytecode file `.evb` | planned | Versioned, hashed, with debug lines and capabilities. |
| `F-VM-08` | Embedding API | planned | The VM as a library with a C ABI (the C ABI is the contract of the embedding). |
| `F-VM-10` | Cross-platform releases | drafted | Windows, Linux, macOS binaries from one build; script/release.py bumps versions. |
| `F-VM-13` | Engine selection and equivalence tests | validated | --engine tree\\|bc and EVE_ENGINE; runtest.py --both and bmark.py --both run every test and benchmark on both engines and require equal results; eve --disasm and the golden listings... |
| `F-VM-14` | Sampling profiler | validated | EVE_PROFILE=1 prints the functions with the most samples (Windows, symbols from the.pdb); the optimization steps R1 to R4 were chosen with it. |
| `F-WEB-04` | Web application kit | planned | Service + EWP feed + browser client, deployment guide. |
<!-- /GEN:list -->
