# Features

Every feature of Eve has a code `F-<area>-<nn>` and the version that should deliver it. Its **stage** says how far it is:

| Stage | Meaning |
|---|---|
| validated | implemented in `eve`, and its tests pass |
| drafted | specified, or its tests are written; the implementation is missing or partial |
| design | decided or proposed in writing; nothing is built yet |
| planned | named for a version; work has not started |

## Summary

<!-- GEN:summary (script/genmanual.py) -->
| Version | Validated | Drafted | Design | Planned | Total |
|---|---|---|---|---|---|
| Version 0.1 | 25 | 10 | 0 | 0 | 35 |
| Version 0.2 | 5 | 8 | 0 | 1 | 14 |
| Version 0.3 | 5 | 8 | 0 | 2 | 15 |
| Version 0.4 | 6 | 9 | 0 | 15 | 30 |
| Version 0.5 | 0 | 6 | 0 | 18 | 24 |
| Version 0.6 | 0 | 1 | 0 | 13 | 14 |
| Version 0.7 | 2 | 1 | 0 | 2 | 5 |
| Version 0.9 | 0 | 0 | 0 | 3 | 3 |
| Version 1.0 | 0 | 0 | 0 | 2 | 2 |
| **All** | **43** | **43** | **0** | **56** | **142** |
<!-- /GEN:summary -->

## By version

<!-- GEN:list (script/genmanual.py) -->
### Version 0.1

| Code | Feature | Stage |
|---|---|---|
| `F-DOC-01` | Tutorial, language part | drafted |
| `F-DOC-04` | Compiler manual | drafted |
| `F-LIB-01` | Console I/O | drafted |
| `F-LIB-02` | Exception module | drafted |
| `F-LNG-01` | Script shapes | validated |
| `F-LNG-02` | Declarations and assignment | validated |
| `F-LNG-03` | Expressions and operators | validated |
| `F-LNG-04` | Control flow | validated |
| `F-LNG-05` | Jobs and error recovery | validated |
| `F-LNG-06` | Primitive types | validated |
| `F-LNG-07` | Collections | validated |
| `F-LNG-08` | Strings and interpolation | validated |
| `F-LNG-09` | Functions and methods | validated |
| `F-SPEC-01` | Lexical specification | validated |
| `F-SPEC-02` | Grammar (EBNF) | validated |
| `F-SPEC-03` | Core semantics | drafted |
| `F-SPEC-07` | Machine-readable tables with schemas | validated |
| `F-SPEC-08` | Conformance levels | drafted |
| `F-SPEC-10` | Licenses and trademark | validated |
| `F-STR-02` | Aspects (serial) | validated |
| `F-STR-05` | Command-line parameters of a script | drafted |
| `F-STR-06` | Configuration files | drafted |
| `F-STR-07` | System variables | drafted |
| `F-TLS-01` | Command line (CLI) | validated |
| `F-TLS-05` | Command files and serve mode | validated |
| `F-TLS-06` | Test runner | validated |
| `F-TLS-07` | Documentation generator `eve --doc` | validated |
| `F-TLS-16` | Smoke test | validated |
| `F-TLS-17` | Benchmarks | validated |
| `F-TLS-18` | Tutorial pages of the tests | validated |
| `F-VM-01` | Lexer and parser | validated |
| `F-VM-02` | Tree-walking interpreter | validated |
| `F-VM-10` | Cross-platform releases | drafted |
| `F-STR-12` | Exit code of the program | validated |
| `F-LIB-13` | DataMap methods | validated |

### Version 0.2

| Code | Feature | Stage |
|---|---|---|
| `F-DOC-05` | Library reference | drafted |
| `F-LIB-03` | Strings, math, collections and type conversions | drafted |
| `F-LNG-10` | Classes | validated |
| `F-LNG-15` | Typed exceptions | drafted |
| `F-LNG-16` | Static checks | drafted |
| `F-LNG-19` | Managed and direct modules | validated |
| `F-SPEC-04` | Library specification | drafted |
| `F-STR-01` | Modules and imports | validated |
| `F-STR-03` | Extension methods | validated |
| `F-STR-04` | Projects and search paths | drafted |
| `F-TLS-02` | REPL | drafted |
| `F-TLS-03` | Interactive interpreter | planned |
| `F-VM-03` | Library loader and `external` bindings | drafted |
| `F-LNG-22` | External routines and errors of modules | validated |

### Version 0.3

| Code | Feature | Stage |
|---|---|---|
| `F-LIB-12` | Testing module `test` | validated |
| `F-LIB-11` | Logging and observability | planned |
| `F-LNG-11` | Traits, abstract classes, generics | drafted |
| `F-LNG-17` | Stream type | drafted |
| `F-LNG-18` | `Atomic(:T)` | drafted |
| `F-MTK-01` | Parallel aspects | validated |
| `F-MTK-02` | Worker pool and scheduler | drafted |
| `F-MTK-03` | Channels | validated |
| `F-MTK-04` | Tasks in a job | validated |
| `F-MTK-05` | Deadlines and cancellation | validated |
| `F-SPEC-05` | Multitasking semantics | drafted |
| `F-TLS-04` | Debugger | drafted |
| `F-TLS-08` | Formatter and linter | planned |
| `F-TLS-09` | Editor support | drafted |
| `F-VM-05` | Region memory | drafted |

### Version 0.4

| Code | Feature | Stage |
|---|---|---|
| `F-DAT-01` | Database layer | drafted |
| `F-DAT-03` | ETL pipeline model | planned |
| `F-DAT-04` | Checkpoints and restart | planned |
| `F-DAT-05` | Columnar tables | planned |
| `F-DAT-06` | Data lineage and run reports | planned |
| `F-DAT-08` | The Eve database | planned |
| `F-DAT-09` | Database admin commands | planned |
| `F-DAT-10` | Schema migrations | planned |
| `F-DAT-11` | Record-table mapping | planned |
| `F-DAT-12` | evedb, the Eve test database | drafted |
| `F-DAT-13` | `sql function` | drafted |
| `F-DAT-14` | Stored procedures | drafted |
| `F-VM-11` | One `eve`, its source in modules | drafted |
| `F-DOC-02` | Tutorial, data client part | planned |
| `F-LIB-04` | Files and paths | planned |
| `F-LIB-05` | Data formats | planned |
| `F-LIB-06` | Time and dates | drafted |
| `F-LIB-07` | Shell commands | drafted |
| `F-LIB-08` | Secrets | drafted |
| `F-LIB-09` | Compression and archives | planned |
| `F-LNG-20` | Generic functions and procedures | validated |
| `F-LNG-21` | Overloading | validated |
| `F-LNG-12` | Generators | validated |
| `F-LNG-13` | Data types for ETL | drafted |
| `F-LNG-14` | Record types and optional values | planned |
| `F-NET-01` | HTTP client | planned |
| `F-VM-06` | Efficient collections | planned |
| `F-STR-09` | Eve macro (hybrid script) | validated |
| `F-STR-10` | Unified aspect | validated |
| `F-STR-11` | `recover` in a function, procedure and method | validated |

### Version 0.5

| Code | Feature | Stage |
|---|---|---|
| `F-DOC-03` | Tutorial, network and web part | planned |
| `F-LIB-10` | Encryption and hashing | drafted |
| `F-NET-02` | HTTP server | drafted |
| `F-NET-03` | Eve Wire Protocol (EWP) | planned |
| `F-NET-04` | Remote apply | planned |
| `F-NET-05` | Capabilities and sandbox | planned |
| `F-NET-06` | Authentication | planned |
| `F-NET-07` | Machine login: single sign-on and the keyring | planned |
| `F-NET-08` | The machine API | drafted |
| `F-SPEC-06` | Network semantics and protocol | planned |
| `F-STR-08` | Service script kind | planned |
| `F-TLS-12` | Machine setup | planned |
| `F-TLS-13` | Remote control | planned |
| `F-TLS-14` | Local HTTP | planned |
| `F-TLS-24` | evetx, the terminal IDE: files, editor, run, machines | drafted |
| `F-TLS-27` | evetx: debugger | planned |
| `F-TLS-28` | evetx: databases | planned |
| `F-TLS-29` | evetx: file card | planned |
| `F-NET-09` | Credentials, connect and upload | planned |
| `F-TLS-26` | REPL: selected machine | planned |
| `F-DAT-15` | The user cache `eve.db` | planned |
| `F-TLS-30` | Service mode | drafted |
| `F-TLS-15` | Eve API for AI | planned |
| `F-NET-10` | Time-outs of the waiting calls | drafted |

### Version 0.6

| Code | Feature | Stage |
|---|---|---|
| `F-VM-09` | WebAssembly build | planned |
| `F-TLS-19` | eveux, the RAD Workbench: shell | planned |
| `F-TLS-20` | eveux: direct SQL and database tree | planned |
| `F-TLS-21` | eveux: jobs, logs and admin | planned |
| `F-TLS-22` | eveux: debugger | planned |
| `F-TLS-31` | eveux: source control | planned |
| `F-TLS-23` | New project | drafted |
| `F-WEB-01` | HTML templates | planned |
| `F-WEB-02` | Eve in the browser | planned |
| `F-WEB-03` | Tutorial playground | planned |
| `F-WEB-05` | evewp: edge and host | planned |
| `F-WEB-06` | evewp: monitor | planned |
| `F-WEB-07` | The Eve Web framework | planned |
| `F-VM-12` | Process supervision API | planned |

### Version 0.7

| Code | Feature | Stage |
|---|---|---|
| `F-VM-04` | Bytecode compiler and VM | drafted |
| `F-VM-07` | Portable bytecode file `.evb` | planned |
| `F-VM-13` | Engine selection and equivalence tests | validated |
| `F-VM-14` | Sampling profiler | validated |
| `F-VM-08` | Embedding API | planned |

### Version 0.9

| Code | Feature | Stage |
|---|---|---|
| `F-DAT-07` | Database synchronization | planned |
| `F-TLS-10` | Package manager | planned |
| `F-WEB-04` | Web application kit | planned |

### Version 1.0

| Code | Feature | Stage |
|---|---|---|
| `F-DOC-06` | Compiler course | planned |
| `F-SPEC-09` | Compiler registry and approval | planned |
<!-- /GEN:list -->
