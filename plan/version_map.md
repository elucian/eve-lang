# Version map

One scale for all the versions of Eve. Each version completes one or two **levels**: a level is a group of features with its own decision log (`plan/decision_levelN.md`) and its own conformance tests (`test/levelN/`). Each version lists its features (codes from [features_inventory.md](features_inventory.md)) and an exit criterion. A version is released by `script/release.py` when every feature in its row is `[x]` in the inventory and its exit criterion passes. This answers review point `RPJ-R06` (`review/01-project.md`). Revised 2026-10-05: one level per stage, the database at level 5, before the server.

## Levels

| Level | Topic | Version | Decisions | Tests |
|---|---|---|---|---|
| 1 | the language of a single script | 0.1 | [decision_level1.md](decision_level1.md) | `test/level1` (a) |
| 2 | a project: aspects, modules, imports, libraries | 0.1 | [decision_level2.md](decision_level2.md) | `test/level2` (b) |
| 3 | data language: types, records, generators, files, formats, HTTP client | 0.2 | [decision_level3.md](decision_level3.md) | `test/level3` (c) |
| 4 | parallel processing and streams | 0.3 | [decision_level4.md](decision_level4.md) | `test/level4` (d) |
| 5 | database layer and the Eve database | 0.4 | [decision_level5.md](decision_level5.md) | `test/level5` (e) |
| 6 | the Eve machine and the server | 0.5 | [decision_level6.md](decision_level6.md) | `test/level6` (f) |
| 7 | web: HTML and WebAssembly | 0.6 | [decision_level7.md](decision_level7.md) | `test/level7` (g) |

## Versions that were named before

The decisions used several scales. They map to this one as follows:

| Old wording | Where | Version here |
|---|---|---|
| "0.1", "version 1", "not in 0.1" | D-050, D-031 | 0.1 is the first release; "not in 0.1" features are placed below |
| "version 2" (generators, module `task`) | D-067 | 0.2 for generators, 0.3 for `task` *(to confirm)* |
| "about 0.9" (VM modes: REPL, service, exclusive) | D-031, TOP-14 | REPL 0.2, the listening machine 0.5 (D-083) |
| "planned" (parallel aspects, channels) | D-050, D-051, D-066 | 0.3 |

The spec version follows the release: Eve spec 0.1 is the spec of release 0.1. Version 1.0 freezes the language; until then a minor version may change the syntax, but only through a decision and a migration script.

## Overview

| Version | Levels | Name | Goal | Status |
|---|---|---|---|---|
| 0.1 | 1, 2 | Core client | Run a whole Eve project: one driver, modules and aspects, error recovery | in progress |
| 0.2 | 3 | Data language | Real data with the right types: Decimal, time, records, optional values; files, JSON, CSV, HTTP client; generators on a bytecode VM | planned |
| 0.3 | 4 | Parallel | Many cores, many waits: parallel groups, channels, streams with back-pressure, region memory | planned |
| 0.4 | 5 | Database | The ETL core: connections, query streams, bulk loads, transactions per job, checkpoints, lineage, the Eve database and its admin commands | planned |
| 0.5 | 6 | Server | The Eve machine: setup, remote control, `serve`, services and routes, the API for AI | planned |
| 0.6 | 7 | Web | Safe HTML and Eve in the browser | planned |
| 0.9 | 1–7 | Release candidate | Package manager, more database drivers, web kit, hardening | planned |
| 1.0 | 1–7 | Stable | Frozen language, every level passes, registry for other implementations | planned |

## 0.1 Core client

Levels: 1, 2. Goal: Run a whole Eve project: one driver, modules and aspects, error recovery.

| Area | Features |
|---|---|
| Spec | F-SPEC-01, F-SPEC-02, F-SPEC-03, F-SPEC-07 ✓, F-SPEC-08 (levels 1–2), F-SPEC-10 ✓ |
| Language | F-LNG-01 ✓, F-LNG-02 ✓, F-LNG-03 ✓, F-LNG-04 ✓, F-LNG-05 ✓, F-LNG-06 ✓, F-LNG-07 ✓, F-LNG-08 ✓, F-LNG-09 ✓, F-LNG-10 ✓ |
| Structure | F-STR-01, F-STR-02, F-STR-03, F-STR-04, F-STR-05, F-STR-06, F-STR-07 |
| VM | F-VM-01 ✓, F-VM-02 ✓, F-VM-03, F-VM-10 |
| Tools | F-TLS-01 ✓, F-TLS-05 ✓, F-TLS-06 ✓, F-TLS-07 ✓ |
| Library | F-LIB-01, F-LIB-02, F-LIB-03 |
| Docs | F-DOC-01, F-DOC-04 |

Exit: level 1 and level 2 pass; `spec/` has the grammar and the semantics of every tested feature (no test relies on an unanswered `Q-nnn`); binaries for Windows and Linux.

## 0.2 Data language

Levels: 3. Goal: Real data with the right types: Decimal, time, records, optional values; files, JSON, CSV, HTTP client; generators on a bytecode VM.

| Area | Features |
|---|---|
| Spec | F-SPEC-04 |
| Language | F-LNG-11, F-LNG-12, F-LNG-13, F-LNG-14, F-LNG-15, F-LNG-16 |
| VM | F-VM-04, F-VM-06 |
| Tools | F-TLS-02, F-TLS-03 |
| Library | F-LIB-04, F-LIB-05, F-LIB-06, F-LIB-07, F-LIB-08, F-LIB-09 |
| Network | F-NET-01 |
| Docs | F-DOC-02, F-DOC-05 |

Exit: level 1 to 3 pass on the bytecode VM; JSON and CSV round-trip tests; an HTTP call against a local test server.

## 0.3 Parallel

Levels: 4. Goal: Many cores, many waits: parallel groups, channels, streams with back-pressure, region memory.

| Area | Features |
|---|---|
| Spec | F-SPEC-05 |
| Language | F-LNG-17 |
| Multitasking | F-MTK-01, F-MTK-02, F-MTK-03, F-MTK-04, F-MTK-05 |
| VM | F-VM-05 |
| Tools | F-TLS-04, F-TLS-08, F-TLS-09 |
| Library | F-LIB-11 |

Exit: parallel tests are deterministic over 100 runs; a pipeline with more stages than cores completes.

## 0.4 Database

Levels: 5. Goal: The ETL core: connections, query streams, bulk loads, transactions per job, checkpoints, lineage, the Eve database and its admin commands.

| Area | Features |
|---|---|
| Data | F-DAT-01, F-DAT-02 (PostgreSQL, SQLite), F-DAT-03, F-DAT-04, F-DAT-05, F-DAT-06, F-DAT-08, F-DAT-09, F-DAT-10, F-DAT-11 |

Exit: level 5 passes against the Eve database (SQLite) and a PostgreSQL server; a killed load restarts from its checkpoint; `db backup` and `db restore` round-trip.

## 0.5 Server

Levels: 6. Goal: The Eve machine: setup, remote control, `serve`, services and routes, the API for AI.

| Area | Features |
|---|---|
| Spec | F-SPEC-06 |
| Structure | F-STR-08 |
| VM | F-VM-08 |
| Tools | F-TLS-12, F-TLS-13, F-TLS-14, F-TLS-15 |
| Library | F-LIB-10 |
| Network | F-NET-02, F-NET-03, F-NET-04, F-NET-05, F-NET-06 |
| Docs | F-DOC-03 (server part, tutorial server.html) |

Exit: a client project and a server project talk on `localhost`; a route answers HTTP; `eve --api` answers an MCP client; `.vmc` files are removed.

## 0.6 Web

Levels: 7. Goal: Safe HTML and Eve in the browser.

| Area | Features |
|---|---|
| VM | F-VM-07, F-VM-09 |
| Web | F-WEB-01, F-WEB-02, F-WEB-03 |
| Docs | F-DOC-03 (web part) |

Exit: tutorial examples run in the browser; templates pass an escaping test suite; the browser VM refuses `fs` and `shell`.

## 0.9 Release candidate

Levels: 1–7. Goal: Package manager, more database drivers, web kit, hardening.

| Area | Features |
|---|---|
| Tools | F-TLS-10 |
| Data | F-DAT-02 (others), F-DAT-07 |
| Web | F-WEB-04 |

Exit: no open `Q-nnn` on a feature of 0.1 to 0.6; performance and memory baselines recorded.

## 1.0 Stable

Levels: 1–7. Goal: Frozen language, every level passes, registry for other implementations.

| Area | Features |
|---|---|
| Spec | F-SPEC-08 (levels 3–7), F-SPEC-09 |
| Docs | F-DOC-06 |

Exit: the language is frozen; every level passes; one implementation other than `evevm` is registered against the spec.

## Open questions

- Confirm the order of the levels: data (3), parallel (4), database (5), server (6), web (7). The alternative puts the database before parallel processing, so a single-threaded database layer ships one version earlier, and parallel loads come with level 4 after it.
- Confirm the mapping of "version 2" (D-067) to 0.2/0.3.
- The data types (F-LNG-13, F-LNG-14), the service kind (F-STR-08) and the network features come from the review; each needs a decision before it is specified.
- The bytecode VM (F-VM-04) is placed before generators because the tree walker can't suspend a method (`design-multitasking.md` §5). If generators must ship on the tree walker, move F-VM-04 to 0.3.
