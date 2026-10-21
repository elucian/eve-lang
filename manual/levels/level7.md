<!-- Generated from the specification, the tests and the benchmarks. Do not edit this page. -->

# Level 7: The web

The web: safe HTML templates, Eve in the browser, and the Eve Web Portal evewp, written in Eve with no JavaScript, as the last and hardest test of the language. Level 7 is the server: evedb, the Eve machine with DuckDB inside, and the portal. The development clients evetx (terminal) and eveux (native window) belong to level 6. Nothing here is built yet; the first step is a trial build of the machine for WebAssembly. It will be 

| Code | Feature | Stage |
|---|---|---|
| [`F-DAT-12`](#f-dat-12-evedb-the-eve-test-database) | evedb, the Eve test database | drafted |
| [`F-TLS-23`](#f-tls-23-new-project) | New project | drafted |
| [`F-VM-09`](#f-vm-09-webassembly-build) | WebAssembly build | planned |
| [`F-VM-12`](#f-vm-12-process-supervision-api) | Process supervision API | planned |
| [`F-WEB-01`](#f-web-01-html-templates) | HTML templates | planned |
| [`F-WEB-02`](#f-web-02-eve-in-the-browser) | Eve in the browser | planned |
| [`F-WEB-03`](#f-web-03-tutorial-playground) | Tutorial playground | planned |
| [`F-WEB-05`](#f-web-05-evewp-edge-and-host) | evewp: edge and host | planned |
| [`F-WEB-06`](#f-web-06-evewp-monitor) | evewp: monitor | planned |
| [`F-WEB-07`](#f-web-07-the-eve-web-framework) | The Eve Web framework | planned |

## F-DAT-12 evedb, the Eve test database

Stage: **drafted**.

A database server in Zig around DuckDB, outside the VM, that speaks the database frames of EWP; the remote database of the level 5 tests, with fault injection and a statement log.

*Partial (2026-10-18):* detailed design in; version 0.3: column batches on the native protocol (`QUERYB`, `LOAD` into DuckDB's Appender), the driver `evedb://` with `Memory.store` and `Memory.load`, measured by (1,000,000 rows into a `Memory` table in 0.23 s; a group-by 55 times faster than SQLite),; triggers and stored procedures in evedb dropped. Version 0.2: evedb answers the **PostgreSQL protocol** on port 5432 (logins trust, password, md5; simple and extended query; types, errors, transactions), a configuration file, `eve db serve` and `eve -s -db --serve`; tested by (psycopg2, pg8000) and; stored procedures and triggers in Eve designed (version 0.3). Version 0.1 built: the server of the EWP-db frames, sessions with leases, `eve_tx` and `STATUS`, error classes, seven faults, the statement log, tokens, and the commands `serve`, `create`, `sql`, `describe`, `snapshot`, `reset`, `status`, `stop`; 16 unit tests and 66 protocol checks in Python. Not yet: the Eve driver `evedb://`, change sets (`CHANGES`/`APPLIED`), `BATCH`/`CREDIT`, the appender, `drift`, import and export, service mode (0.2).

*Moved to level 7 (2026-10-20):* evedb is the server; levels 1 to 6 are the client. The column batches of are kept with their tests.

## F-TLS-23 New project

Stage: **drafted**.

`project init <folder>` and `project new <folder>`: `init` also works on an existing project and never overwrites; `new` fails on a non-empty folder. Makes `db`, `log`, `meta`, `data/in`, `data/out`, `test`, `asp`, `lib`, `src`, `doc`, `web`, the files `<name>.eve`, `eve.cfg`, `meta/project.json` and a `.gitignore`, and runs `git init` outside a repository.

*Partial:* done and tested; the writer of the minimal fallback log is not written.

## F-VM-09 WebAssembly build

Stage: **planned**.

The VM compiled to `wasm32` with host imports.

## F-VM-12 Process supervision API

Stage: **planned**.

`os` handles for spawn with limits, wait, kill and signals, status of a child through its IPC door; used by the host of evewp.

## F-WEB-01 HTML templates

Stage: **planned**.

`HTML` type, context-aware escaping, template files, components.

## F-WEB-02 Eve in the browser

Stage: **planned**.

The WASM VM runs signed `.evb` code with limited capabilities, `dom` module.

## F-WEB-03 Tutorial playground

Stage: **planned**.

A "Run" button on tutorial examples using the WASM VM.

## F-WEB-05 evewp: edge and host

Stage: **planned**.

The Eve Web Portal as the production edge: host table by `Host` header (domains, subdomains, wildcards), static files, proxy to the Eve machine of each application, request log and limits; the host keeps each application in its own folder with versions, starts and supervises its machine, receives deploys, rollback ( sections 3, 5). Behind a reverse proxy for TLS.

## F-WEB-06 evewp: monitor

Stage: **planned**.

A graphic health server written in Eve: connections, requests, domains, users, applications, memory, logs, alerts; SVG charts and pages with no JavaScript, live updates through the framework ( section 6).

## F-WEB-07 The Eve Web framework

Stage: **planned**.

Eve (a dialect with a browser profile) written once and compiled to WebAssembly modules that run in the page: stage W1 the VM in Wasm running source or `.evb`, stage W2 a typed subset compiled to Wasm; shared modules with the server; a fixed generated loader shim, no JavaScript written by the developer ( section 7). Needs F-VM-09, F-WEB-01, F-WEB-02.
