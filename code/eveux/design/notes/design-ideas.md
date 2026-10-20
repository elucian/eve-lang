┌──────────────────────────────────────────────────────────┐
│ LOCAL (Developer Workstation)                            │
│ ┌──────────────────────────────────────────────────────┐ │
│ │ eveux (Local Editor / Browser UI)                    │ │
│ │  ├── Local File System Access                        │ │
│ │  ├── Local Git Repository (Branches, Commits, Diff)  │ │
│ │  └── UI / Workspace Preferences                      │ │
│ └──────────────────────────────────────────────────────┘ │
└────────────────────────────┬─────────────────────────────┘
                             │
                             │ (WebSocket / SSH / gRPC)
                             ▼
┌──────────────────────────────────────────────────────────┐
│ REMOTE (Server / Execution Node)                         │
│ ┌──────────────────────────────────────────────────────┐ │
│ │ Target Execution Daemon                              │ │
│ │  ├── Deployment Target (Checked-out Code / Binaries) │ │
│ │  ├── EVE Runtime & ETL Execution Engine              │ │
│ │  ├── Job Orchestrator (Start, Stop, Schedule)        │ │
│ │  ├── Real-Time Log Streaming (stdout/stderr)         │ │
│ │  └── Data Source Connectors & Schema Introspection   │ │
│ └──────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘

How Deployment & Execution Flow
Development: Edit code and manage branches locally via eveux and your local Git repository.

Sync / Deploy: When ready to run or test on the remote server, eveux triggers a sync operation (e.g., via git push to a staging remote or a fast direct file-sync/bundle transfer over your secure connection).

Remote Control: Once deployed, eveux connects to the remote daemon to start ETL jobs, inspect live logs, and preview processed data output directly within the editor dashboard.

The Correct Architecture: eve as Daemon, SQLite & DuckDB as Backends
The clean separation of state relies on eve acting as the central execution server, utilizing two distinct database engines based on workload:

┌─────────────────────────────────────────────────────────────┐
│ Clients: evetx (Terminal) / eveux (Web)                     │
└──────────────┬──────────────────────────────┬───────────────┘
               │ IPC / SSH / WebSocket        │
               ▼                              ▼
┌─────────────────────────────────────────────────────────────┐
│ eve (Core Server / Runtime Daemon)                          │
│ ├── Compiler & REPL Engine                                  │
│ ├── Session & Process Orchestrator                          │
│ ├── SQLite (Embedded) ──> Metadata, Configs, State Catalog  │
│ └── evedb (DuckDB)    ──> High-Throughput ETL Engine        │
└─────────────────────────────────────────────────────────────┘
1. SQLite (Embedded in eve)
Purpose: Operational metadata, user preferences, session states, workspace configurations, and local catalog tracking.

Why: Fast, zero-configuration, transactional, and perfect for lightweight relational state.

2. evedb / DuckDB (Embedded or Managed by eve)
Purpose: Heavy-duty analytical data processing and columnar ETL execution.

Why: It processes massive datasets instantly. Instead of making DuckDB a network server daemon, let eve embed or spawn evedb as an optimized computational engine when a data transformation pipeline runs.

Verdict
Keep eve as the server daemon. It hosts the REPL, processes client connections from code/evetx/eveux, uses SQLite for local operational state, and invokes evedb (DuckDB) strictly for data-heavy ETL execution.
