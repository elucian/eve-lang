# 10 Plan: extend the tutorial for client-server ETL and the web (`RTU`)

Today the tutorial has 19 topics: 01 Manifest, 02 Syntax, 03 Data Types, 04 Topology, 05 Functions, 06 Methods, 07 Modules, 08 Classes, 09 Collections, 10 Strings, 11 Control Flow, 12 Processing, 13 Multitasking, 14 Algorithms, 15 Standard Library, 16 Exceptions, 17 Shell Commands, 18 Databases, 19 Compiler (D-069).

This plan adds a third part, **"Eve on the network"**, and revises the pages it depends on. It follows the rules of `plan/README.md` (one step per session, status marks, decisions before pages) and can be moved there as `plan/phase-8-network.md` when the author accepts it. Each step names the review points it implements.

## Principles

- **Decide, then teach.** Every new page starts as a design note in `plan/` with questions (`Q-nnn`); the page is written after the decision. Pages for features not in the current version carry a banner "planned for 0.x" (as multitasking does for parallel aspects).
- **Client first.** Part A (client) is useful with the 0.1/0.2 VM; Part B (server) and Part C (browser) are taught as designs until the VM supports them.
- **One running example across the new pages:** *"orders"*: read CSV orders from a folder and a REST API, clean them, load them into PostgreSQL, publish a daily HTML report, then (part B) serve the same data over HTTP and EWP, and (part C) show a live dashboard in the browser with Eve compiled to WebAssembly. Every page adds one piece; the full project lives as a level 3 project test (D-073).
- **Every example runs** (or is marked "design") and has a test in `test/level3/` once the VM supports it.

## Phase T0 — prerequisites (fix before extending)

| Step | Work | Implements |
|---|---|---|
| RTU-S01 `[ ]` | Rewrite databases.html in the current dialect; replace the ORM with SQL-first, parameterized, streaming access; remove credentials from code | `RIO-D02`, `RIO-X01`, `RIO-X02`, `RIO-R02` |
| RTU-S02 `[ ]` | Fix command.html: argument-list `run`, `cwd`, no `cd` across calls, injection warning | `RIO-D03`, `RIO-R03` |
| RTU-S03 `[ ]` | Manifest: replace the capability list with the real roadmap (client, server, web) and the version map | `RPJ-D05`, `RPJ-R06` |
| RTU-S04 `[ ]` | Data Types: add Decimal, Instant/DateTime/Zone, Bytes, Uuid, Record, `T?` (after decisions) | `RTY-R01`, `RTY-R02` |
| RTU-S05 `[ ]` | Standard Library: one table of 0.1 modules with signatures (`fs`, `path`, `json`, `csv`, `http`, `db`, `time`, `secret`) | `RIO-R01` |
| RTU-S06 `[ ]` | Exceptions: typed errors, `finalize` always runs, error data fields | `RST-R01`, `RST-R02` |

## Phase T1 — Part A: Eve as a data client (pages 20–24)

| Step | New page | Content | Implements |
|---|---|---|---|
| RTU-S10 `[ ]` | 20 **Files and Paths** (`files.html`) | `fs`, `path`, text vs bytes, encodings, line streams, globbing, atomic writes, `data/` and `out/` folders | `RIO-R01` |
| RTU-S11 `[ ]` | 21 **Data Formats** (`formats.html`) | JSON (parse, print, decode into records), CSV (header, types, errors per row), round-trip rules, binary basics, gzip | `RTY-R05`, `RIO-R01` |
| RTU-S12 `[ ]` | 22 **Streams** (`streams.html`) | `Stream(:T)` from generators, files, queries; `map/filter/batch/partition`; back-pressure; link to Multitasking | `RMT-R02`, `RMT-R04` |
| RTU-S13 `[ ]` | 23 **HTTP Client** (`http.html`) | URLs, requests, headers, JSON bodies, status errors as typed errors, timeouts, retries with jobs, pagination with generators, secrets for tokens | `RNW-R10`, `RST-A02` |
| RTU-S14 `[ ]` | 24 **ETL Pipelines** (`etl.html`) | Extract/Transform/Load with jobs and aspects; idempotent loads; checkpoints; dead-letter files in `recover`; run report in `finalize`; BSP partitioning; the full *orders* client | `RIO-R04`, `RIO-R05`, `RIO-R06` |

Revisions in the same phase: Processing (jobs as ETL steps, observability, `RST-R07`), Multitasking (deadlines, cancellation, error collection, `RMT-R01`), Databases (bulk load from a Stream, transactions as blocks).

## Phase T2 — Part B: Eve as a server (pages 25–28, "design, planned for 0.4")

| Step | New page | Content | Implements |
|---|---|---|---|
| RTU-S20 `[ ]` | 25 **Client and Server** (`network.html`) | the architecture: client VM, server VM, nodes; aspects as the unit of distribution; local, parallel and remote `apply`; failure, deadlines, idempotency | `RNW-R01`, `RNW-X02` |
| RTU-S21 `[ ]` | 26 **Services** (`service.html`) | the `service` script kind, routes, request/response records, per-request state, lifecycle, static files, configuration | `RNW-R02`, `RST-R03` |
| RTU-S22 `[ ]` | 27 **Eve Wire Protocol** (`protocol.html`) | why HTTP for the web and EWP for data; frames, `APPLY`/`RESULT`/`BATCH`/`CREDIT`; value encoding; columnar batches; resumable streams; a session trace | `RNW-R03`, `RNW-R04` |
| RTU-S23 `[ ]` | 28 **Security** (`security.html`) | capabilities in the project file, per-aspect grants, secrets, TLS, auth tokens, input validation with record types, sandboxing | `RNW-R08`, `RSB-R06` |

Revisions: Topology (the `service` kind, project file with capabilities, `web/` folder), Modules (immutable after `initialize`, `RST-R05`), Exceptions (network error types).

## Phase T3 — Part C: Eve on the web (pages 29–31, "design, planned for 0.5")

| Step | New page | Content | Implements |
|---|---|---|---|
| RTU-S30 `[ ]` | 29 **HTML Templates** (`html.html`) | the `Html` type, context-aware escaping, template files, components as functions, a report page for *orders* | `RNW-R05` |
| RTU-S31 `[ ]` | 30 **Eve and WebAssembly** (`wasm.html`) | the VM compiled to WASM, `.evb` bytecode, what runs in the browser (pure functions, capability-limited aspects), host imports | `RNW-R06`, `RVM-R05`, `RVM-R06` |
| RTU-S32 `[ ]` | 31 **Web Applications** (`webapp.html`) | the full *orders* app: service + EWP feed + browser dashboard in Eve/WASM; deployment; observability | `RNW-R07`, `RNW-R09` |
| RTU-S33 `[ ]` | Playground | a "Run" button on tutorial examples using the WASM VM (scl site) | `RNW-R06` step 1 |

## Phase T4 — integration

| Step | Work |
|---|---|
| RTU-S40 `[ ]` | index.html: three parts (Language 01–19, Data client 20–24, Network and web 25–31); data/*.json sidebars; read-next chains |
| RTU-S41 `[ ]` | Compiler page: bytecode, region memory, scheduler, WASM target as chapters of the student track (`RVM-R01`, `RVM-R02`) |
| RTU-S42 `[ ]` | `issues/` file for each new page, reviewed like the others (T1.10) |
| RTU-S43 `[ ]` | Level 3 project tests for *orders* (client part first), with `data/` inputs and `out/` golden files (D-073) |
| RTU-S44 `[ ]` | Spec stubs: `spec/library/*.md` for each module, `spec/semantics/network.md`, `spec/protocol/ewp.md` |

## Decisions needed before writing (proposed `Q` list)

| Code | Question | Blocks |
|---|---|---|
| RTU-Q01 | Accept a syntax moratorium for 0.1 (`RPJ-R01`)? | everything (examples must not churn) |
| RTU-Q02 | Data types: Decimal, Instant/DateTime/Zone, Bytes, Uuid, Record, `T?` — which in 0.1? | S04, S11, S14 |
| RTU-Q03 | Conversions fail loudly (`RTY-R03`)? | S11, S14 |
| RTU-Q04 | `Stream(:T)` as the common type of generators, files, queries and channels? | S12 |
| RTU-Q05 | `finalize` always runs except `panic`; typed errors? | S06, S14 |
| RTU-Q06 | Remote `apply … at node within t` (or another form)? | S20 |
| RTU-Q07 | `service` as a new script kind, or a library on a driver? | S21 |
| RTU-Q08 | EWP: CBOR + Arrow IPC, or an Eve-specific encoding? | S22 |
| RTU-Q09 | Capability model: project file + per-aspect declaration? | S23 |
| RTU-Q10 | WASM order: VM in browser first, AOT later? | S31 |

## Suggested order and size

T0 (6 sessions) → T1 (5 pages + 3 revisions, ~10 sessions) → T2 (4 pages, design only, ~6 sessions) → T3 (3 pages + playground, ~6 sessions) → T4 (~4 sessions). The VM work that makes Part A real (library modules, generators, bytecode) runs in parallel and turns "design" banners into runnable examples one by one.
