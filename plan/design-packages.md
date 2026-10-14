# Plan: one `eve`, its source split into modules

Status: **approved by the author**, 2026-10-12 (revision 5): recorded as Q-049 and D-163 to D-167 in `decision_level6.md`. The author has answered all sixteen questions of revisions 1 to 3 and reviewed revision 4; the answers and the review are kept word for word in the appendix. Nothing in the code, the spec or the tutorial has changed yet. Once the author approves, §1 is recorded as Q-049 and decisions D-163 to D-167 in `plan/decision_level6.md`, and the work starts at step A0 (§10).

- **Revision 1** split the monolith into packages under `src/`.
- **Revision 2** made four programs on one core.
- **Revision 3** made one `eve.exe` with a dispatcher and modules.
- **Revision 4** adds the author's last answers:
  - a serving machine is **one process** whose parts run as concurrent tasks;
  - `eve.exe` is a **multi-call binary** (the name it was started with chooses the part; replaced in revision 5);
  - the machine API `vm.*`;
  - `-rem` and eveux **translate ACP into machine calls**;
  - `proc/` and `sql/` folders;
  - DuckDB loaded on demand;
  - version N = level N;
  - `cmd/` without `src/`.
- **Revision 6** (2026-10-13) adds the module **`evetx`**, a full-screen terminal **project IDE** over libvaxis: a tree of the project files, an editor, run and debug buttons, a bottom panel (Console, Watch, Stderr, Stdout, Breaks), database tabs and a structure dialog, machines chosen with F1 to F3: `eve -tx`, level 6, step B6 (D-172, D-173; proposals Q-050 to Q-053; design and drawings in [evetx/README.md](../evetx/README.md)). Schedules and the management of runs belong to `eveux`. Everything else of revision 5 stands.
- **Revision 5** follows the author's review of revision 4:
  - **no links**: the first word after `eve` chooses the part, and the root `run.sh` gets the shortcuts `eve`, `evevm`, `evecp`, `evedb` and `eveux`; users write their own start scripts (§4);
  - **no TLS in `eve.exe`**: the machine speaks plain JSON-RPC/HTTP on loopback, and a reverse proxy gives HTTPS to remote clients (§5, §6);
  - **`sql function`s called by DuckDB threads** are guarded by a session mutex or a thread-safe execution pool, measured in A9 before query concurrency grows (§7).

Related: [design-service.md](design-service.md), [design-database-core.md](design-database-core.md), [design-database-remote.md](design-database-remote.md), [spec/library/machine.md](../spec/library/machine.md) (D-162), [evedb/README.md](../evedb/README.md), [eveux/README.md](../eveux/README.md), [version_map.md](version_map.md), [manual/release/README.md](../manual/release/README.md) (D-153).

## 1. Decisions to record

| Id (proposed) | Decision | From answers |
|---|---|---|
| **D-163** Modules and one binary | The source is split into the modules `evecm` (leaf: values, heap, codecs, interfaces, wire), `evecp` (compiler), `evevm` (runtime), `evedb` (database), `eveux` (UI), plus `cmd` (the entry point), with one root `build.zig`. The arrows of §3 are checked by the build. One executable `bin/eve.exe`; its first word chooses the part: `eve vm`, `eve cp`, `eve db`, `eve ux` (and `eve file.eve` is `eve vm file.eve`, as today). No links: the root `run.sh` has a shortcut per part, and users write their own start scripts. The Eve standard library is in `lib/`. `evecm` holds Zig code only; data belongs to projects. | 2, 3, 4, 5, 6, 12, 16, review of revision 4 |
| **D-164** The serving machine | A serving machine is **one process**. Its active parts (runtime, database, UI) run as concurrent tasks and call each other in process, through interfaces. Each part opens its own **door** to the outside: **IPC** for evevm and for evedb, HTTP/WebSocket and **ACP** for eveux. D-162 stays: one machine per domain and port; `-x` runs in the process of the command; `-loc` goes to the machine. | 11, 1, 1a |
| **D-165** The machine API | evevm started with `-lsn` exposes a JSON-RPC 2.0 machine API over a Unix socket, or plain HTTP bound to loopback; **`eve.exe` holds no TLS server**, and a remote machine is reached through a reverse proxy (Nginx, Caddy, Cloudflare Tunnel) that gives HTTPS: `vm.ping`, `vm.stat`, `vm.run`, `vm.eval`, `vm.suspend`, `vm.resume`, `vm.inspect`, `vm.cancel`, `vm.stop`. The database part answers `db.*`. `eve -rem` and eveux are **clients**: they speak ACP to AI agents and IDEs and turn the intent of the agent into the exact `vm.*` calls of the remote evevm. | 1, 1a, review of revision 4 |
| **D-166** Stored procedures and `sql function` | **Two kinds of stored procedures:** native ones (PL/SQL, PL/pgSQL, …) in the `sql/` folder of a project, called through `external` declarations (signature only); and Eve procedures in its `proc/` folder, run by evedb for SQLite and DuckDB. **`sql function name`** (new keyword `sql`) marks an Eve function that evedb registers as a SQL function in SQLite and DuckDB through their C API. Other databases get no custom functions: their data is brought into the process, changed in Eve, and written back in bulk or row by row. SQLite is linked into `eve.exe`; DuckDB is loaded only when a DuckDB connection opens. A `sql function` that DuckDB calls from its worker threads runs under a session mutex or a thread-safe execution pool. | 7, 10, 14, 15, review of revision 4 |
| **D-170** (proposed, Q-050; scope by D-173) The terminal UI | A new module `evetx` (the option `eve -tx`, D-172; the word `eve tx`; shortcut `./run.sh evetx`) is a full-screen TUI built on the Zig library libvaxis, a package dependency of that module alone (nothing to bind: libvaxis is Zig). It is a **project IDE**: file tree, editor, run and debug, database tabs with a structure dialog, and the machine chosen with F1 to F3. It imports `evecm` only, like `eveux`, and reaches machines through the machine API (`vm.*`, `db.*`). Schedules and runs are `eveux` work. It belongs to level 6, version 0.0.6, step B6. | the author's requests of 2026-10-13 |
| **D-167** Versions | One version for everything. It is written once (the root `build.zig.zon`), and the release notes stay in `manual/release/` (D-153). **Version N is level N**: today 0.0.3 (levels 1 to 3); 0.0.4 is level 4, 0.0.5 level 5, 0.0.6 level 6. The split lands in 0.0.5 and 0.0.6; the bytecode (F-VM-04, F-VM-07) moves to 0.0.6. The headings of `version_map.md` (today "Version 0.4 = Level 5") are renumbered to match, which revises D-138. | 8, 9, 13 |

**Decisions that change:**

- **D-162** stays, and its four methods are renamed into `vm.*` (§6).
- **D-159** changes: SQLite and DuckDB both belong to the evedb module of `eve.exe`, and DuckDB is loaded on demand.
- **D-154 and D-155** change: Zig is in `eveux/src`, and the Workbench in Eve is in `eveux/app`.
- **D-138** changes: the version names and the bytecode move to 0.0.6.

## 2. The layout

```
eve-lang/
├── build.zig, build.zig.zon     one build: zig build -p . → bin/eve.exe
├── run.sh                       build, tests, and the shortcuts eve, evevm, evecp, evedb, eveux (§4)
├── evecm/   README.md, src/      leaf module: values, heap, codecs, interfaces, wire, terminal
├── evecp/   README.md, src/      compiler module
├── evevm/   README.md, src/      runtime module
├── evedb/   README.md, src/      database module (SQLite embedded, DuckDB on demand)
├── eveux/   README.md, src/, app/   UI module; app/ is the Workbench (Eve, JavaScript, CSS)
├── evetx/   README.md, design/, src/   terminal IDE module (libvaxis): files, editor, run and debug, databases (level 6)
├── lib/     *.eve, README.md, doc/   the Eve standard library; doc/ generated by eve --doc
├── cmd/     eve.zig, dispatch.zig    the entry point: no src/, nothing else lives there (answer 16)
└── bin/     eve.exe, the DuckDB library
```

- **Each module folder** may hold its own `doc/`, `lib/`, `web/` or other folders (answer 5).
- **Everything that is built goes to `bin/`,** so one entry in `PATH` serves every test project.
- **Folders that stay:** `spec/`, `plan/`, `manual/`, `test/`, `script/`.
- **A project folder** (not the repository) holds `db/`, `data/`, and, when it has databases, `sql/` and `proc/` (§7).

## 3. The modules and their arrows

```
                 cmd (eve.zig, dispatch.zig: imports all, wires the interfaces)
       ┌────────┬───┴────┬─────────┐
       ▼        ▼        ▼         │
     evevm    evedb    eveux       │
       │ ╲      │        │         │
       ▼  ▼     ▼        │         │
     evecp ◄────┘        │         │
       │                 │         │
       ▼                 ▼         │
     evecm ◄───────────────────────┘   (imports only std)
```

**The arrows:**

| Module | May import |
|---|---|
| `cmd` | every module |
| `evevm` | `evecp`, `evecm` |
| `evedb` | `evecp` (to check `proc/` and `sql function`s), `evecm` |
| `eveux` | `evecm` only |
| `evetx` | `evecm` only (and the package libvaxis) |
| `evecp` | `evecm` |
| `evecm` | `std` only |

Each arrow is an `addImport` in the root `build.zig`, so a wrong import is a build error.

**The rules:**

- **Shared code goes down.** Code used by two modules goes down to the lowest module that both of them import.
- **The parts never import each other.** evevm and evedb never import each other; eveux imports neither. They meet through the interfaces of `evecm` (§8), and only `cmd/dispatch.zig` connects them.
- **Folders become modules when they grow.** `evecm` starts as one module with folders (`value/`, `codec/`, `iface/`, `wire/`, `term/`); a folder that grows becomes a module of its own (answer 6).

| Module | Holds |
|---|---|
| **evecm** | values and heap (D-151); `Signal` and the error codes; the syntax tree (until the bytecode, §10 B5); Decimal, Instant, NFC, CSV, JSON; the reader of `eve.cfg`; the version (a build option from `build.zig.zon`); the interfaces of §8; JSON-RPC 2.0, the transports (Unix socket, TCP, HTTP), the singleton by domain and port; the line editor and the terminal |
| **evecp** | lexer, parser, check, overload, the link of a driver with its aspects, `doc`, `project init/new`, the list of `sql function`s of a program; in 0.0.6 the bytecode emitter and the `.evb` writer |
| **evevm** | the interpreter, the baton tasks (D-144), scratch memory, the natives of `lib/` (`io`, `fs`, streams), sessions, the machine and its IPC door with the `vm.*` methods, `-loc`, the REPL, the debugger, the MCP server of the eve skills; in 0.0.6 the bytecode VM |
| **evedb** | SQLite (embedded), DuckDB (loaded on demand), connections, statements, the ORM and the transactions bound to jobs, `sql function` registration, `proc/` and `sql/`, the `db.*` methods and their IPC door, fault injection and the statement log of the test database |
| **eveux** | HTTP and WebSocket, the web folder, the ACP client and the translation into `vm.*`, login and the keyring (D-155), HTML responses; `app/` is the Workbench |
| **evetx** | the terminal screen (libvaxis): file tree, tabs, the text buffer of the editor, the bottom panel, the debug buttons, the database tabs and the structure dialog; the model and update of the screen, one client task per machine; the machine registry, the credentials and the user cache come through `evecm` (Q-050, Q-052 b) |
| **cmd** | `eve.zig`: the options, the help pages, the choice of part by the first word. `dispatch.zig`: builds the parts, connects their interfaces, starts the serving machine. |

## 4. `eve`, its parts, and `run.sh`

**One command, a word per part** (revision 5: no links). `eve.zig` reads the first word: `vm`, `cp`, `db` or `ux` choose a part, anything else keeps today's meaning (a script path, an option, a command such as `project`):

| Part | Command | Examples | Today |
|---|---|---|---|
| runtime | `eve vm …`, or `eve` with a script or the options of today | `eve file.eve`, `eve -x f.eve`, `eve --listen`, `eve vm --api` | the same |
| compiler | `eve cp …` | `eve cp --check f.eve`, `eve cp --doc lib lib/doc`, `eve cp --compile f.eve` (0.0.6), `eve cp project new …` | `eve --check`, `eve --doc` and `eve project` stay as synonyms |
| database | `eve db …` | `eve db serve --test`, `eve db sql <name> "…"`, `eve db describe …`, `eve db proc list`, `eve db proc reload` | the commands of `evedb.exe` |
| UI | `eve -ux`, `eve ux …` | `eve -ux`, `eve ux start`, `eve ux stop`, `eve ux status` | `-u` (replaced by `-ux`, D-172), `eve --serve start`, … (synonyms) |
| text UI | `eve -tx`, `eve tx …` | `eve -tx`, `eve -tx -rem prod` (opens on that machine) | new in 0.0.6 (D-172) |

`eve` with its options of today does not change, so the tests, the tutorial and `spec/library/machine.md` keep working. A `#!` script keeps `#!/usr/bin/env eve`.

**`run.sh` at the root** gets one shortcut per part, which pass every other argument through (`"$@"`):

| `run.sh` | Runs |
|---|---|
| `./run.sh eve <args>` | `bin/eve <args>` |
| `./run.sh evevm <args>` | `bin/eve vm <args>` |
| `./run.sh evecp <args>` | `bin/eve cp <args>` |
| `./run.sh evedb <args>` | `bin/eve db <args>` |
| `./run.sh eveux <args>` | `bin/eve ux <args>` |
| `./run.sh evetx <args>` | `bin/eve tx <args>` |

- The shortcuts do **not** change the working folder (the `build` and test words of `run.sh` still do), so a relative path in the arguments means the folder the user is in: `../../run.sh evevm main.eve` works from inside a test project.
- The words come before the default of `run.sh` (a test name or a level for `runtest.py`); no test is named `eve…`, so nothing clashes.
- On Windows `run.sh` runs in Git Bash, as today.
- **Users write their own start scripts**: a project keeps, for example, `start.sh` with `eve db serve --port 8044 &` and `eve --listen --serve`, with the options its machine needs. `eve project new` can write such a script in the new project (a template, decided in A8).

## 5. The serving machine: one process, parts as tasks

A **direct command** (`eve file.eve`, `eve -x`, `evecp --check`, `evedb sql …`) runs in the process of the command. It uses only the parts it needs, called as functions. Same speed as today.

**A serving machine** (`eve --listen`, `eve --serve`, `evedb serve`, or several of them on one line) is one process per domain and port (D-162: the singleton; a second start fails with exit 75).

- **Active parts.** A part is active when its door is open or when another active part needs it: a run that opens a database activates evedb.
- **Concurrency.** Parts and doors run as concurrent tasks of `std.Io`, the I/O interface of Zig 0.16 that `server.zig` already uses.
- **Calls between parts** are function calls through the interfaces of `evecm`, never IPC.

| Part | Door to the outside | Serves |
|---|---|---|
| evevm | **IPC**: JSON-RPC 2.0 on a Unix socket, one message per line (D-162); plain HTTP (`POST /rpc`) on loopback, behind a reverse proxy for remote clients | `vm.*` |
| evedb | **IPC**: its own socket, `<runtime>/eve-<domain>-<port>-db.sock`; TCP for a remote database later | `db.*`, the EWP database frames |
| eveux | HTTP and WebSocket for the browser; **ACP** toward agents and IDEs | the web folder, routes, the Workbench |

**Sessions and threads:**

- **Sessions.** Eve code runs in **sessions**. A session owns its interpreter and its heap, so two sessions never share values: the heap needs no locks. Inside a session the baton tasks of D-144 run as today.
- **Phase B1:** the machine runs **one script at a time** (D-162, point 7: "waited N ms for another script").
- **Later in level 6:** several sessions in parallel, one per task, with shared state as a separate decision.
- **The database part** owns the connections and the files of the project. Calls from a session go through `Data` (§8) under the lock of each connection; SQLite is compiled serialized (`SQLITE_THREADSAFE=1`).
- **No TLS in the machine** (review of revision 4). Every door listens in plain text, and by default only on loopback (`127.0.0.1`, `::1`) or on a Unix socket. Remote clients reach it through a **reverse proxy** that ends HTTPS (Nginx, Caddy, Cloudflare Tunnel) and forwards to the loopback port; WebSocket goes through the same proxy. So `eve.exe` compiles no C TLS library. To bind a non-loopback address, `eve.cfg` must say so (`http_host` with `behind_proxy = true`, names decided in B3); a machine never opens a plain door to the network by accident. The login and the token of D-155 are still checked by the machine itself: the proxy carries the bytes, it does not decide who may run what.
- **`-x` and `-loc`** (D-162) also hold for databases. `-x` opens the SQLite files in its own process; `-loc` sends the run to the machine, whose evedb part owns the files. SQLite allows several processes on one file (WAL), so both stay correct; only `-loc` gets one owner.

## 6. The APIs and ACP

### 6.1 The machine API `vm.*` (answer 1a)

JSON-RPC 2.0, the same messages on every transport. The four methods of D-162 are renamed into the namespace; the new ones come from the answer.

| Method | Params | Result | Today |
|---|---|---|---|
| `vm.ping` | none | `{"pong": true, "version": "…"}` | `ping` |
| `vm.stat` | none | doors, runs, sessions, memory, active parts | `status` |
| `vm.run` | `file` or `source`, `args` | exit code, output, duration | `run` |
| `vm.eval` | `session`, `source` (a statement or an expression) | value or output: the REPL over the wire | new |
| `vm.suspend`, `vm.resume` | `session` | the session stops at its next safe point / continues | new (debugger, F-TLS-04) |
| `vm.inspect` | `session`, `what`: `locals`, `stack`, `globals`, `heap` | the values as JSON | new |
| `vm.cancel` | `session` | the run ends with `Abort` | new |
| `vm.stop` | none | the machine ends (exit 0) | `stop` |

**`db.*`:**

| Method | Purpose |
|---|---|
| `db.query`, `db.execute` | direct SQL |
| `db.call` | an Eve procedure of `proc/` or a native one of `sql/` |
| `db.proc.list`, `db.proc.reload` | the Eve procedures |
| `db.stat` | connections, transactions, leases |

**Transition:** during 0.0.5 the old names `ping`, `status`, `run` and `stop` are accepted as synonyms, so the Node.js client of e95 keeps working; e95 moves to the new names in B2, and the synonyms are removed in 0.0.6.

### 6.2 ACP: eveux and `-rem` as clients (answers 1 and 1a)

The **Agent Client Protocol** is JSON-RPC 2.0 between a client (an editor) and an agent (an AI), usually a subprocess of the client. The answer to 1a gives eveux and `eve -rem` one role: **speak ACP outward, `vm.*` inward**.

**Toward AI agents** (first; the chat panel of the Workbench). eveux is the ACP *client*. Calls from eveux to the agent:

| Call | Purpose |
|---|---|
| `initialize` | agree on the version and the capabilities |
| `authenticate` | the API key or the OAuth login of the user, from the keyring of the system (D-155), never in the browser |
| `session/new` | opens a session on the project folder and hands the agent the **eve skills**: the MCP server of evevm (design-service.md §6), whose tools are the `vm.*` and `db.*` methods |
| `session/prompt` | sends the chat panel |
| `session/cancel` | stops a running turn |

Calls from the agent to eveux:

| Call | What eveux does |
|---|---|
| `session/update` | streams to the browser over WebSocket |
| `session/request_permission` | shows a dialog |
| `fs/read_text_file`, `fs/write_text_file` | answers from the project folder and the open editor buffers |

**Toward IDEs** (second, level 6 or later). An IDE that speaks ACP (an editor with an agent panel) can drive Eve through eveux, which then plays the *agent* end. A prompt about the project becomes `vm.*` calls (`vm.run`, `vm.eval`, `vm.inspect`) on the local or the remote machine.

**`eve -rem <machine>`** is the same client without the browser. It turns the CLI command into the `vm.*` calls of the remote evevm, over HTTPS to the reverse proxy in front of it, with the login and the keyring of D-155. HTTPS is needed only on the client side, which Zig's standard library has (`std.http.Client` with its TLS client); the server side stays plain behind the proxy.

All three share `evecm/wire`: one JSON-RPC layer, the transports, the singleton, the login.

## 7. The database

| Engine | How it is linked | Custom Eve functions | Stored procedures |
|---|---|---|---|
| SQLite | embedded, compiled from the amalgamation (as today) | `sql function` | `proc/` (Eve, run by evedb) |
| DuckDB | its library is loaded with `std.DynLib` when the first DuckDB connection opens; `eve hello.eve` starts without it | `sql function` | `proc/` (Eve, run by evedb) |
| PostgreSQL, Oracle, MySQL, … (drivers, design-database-remote.md) | | none: the data comes into the process, Eve changes it, and it goes back in bulk or row by row | `sql/` (native), called with `external` |

**`sql function`** (D-166):

```eve
sql function tax(amount: Decimal, country: String): Decimal is
  ...
end tax;
```

- **Register.** The checker collects them. When evedb opens a SQLite or DuckDB connection, it registers each one through the C API (`sqlite3_create_function_v2`, the DuckDB scalar function API). Then `select tax(amount, country) from orders` runs Eve inside the engine.
- **Types.** The arguments and the result must have SQL types (design-database-core.md §4); the checker refuses others.
- **Purity.** A `sql function` is pure (no `!`): the engine may call it any number of times, in any order.
- **Re-entry.** The call re-enters the interpreter of the session that runs the statement, so no heap safe point may run inside it.
- **Threads** (review of revision 4). DuckDB runs a query on worker threads, which may call a registered `sql function` at the same time, while the session that sent the query waits. The Zig runtime is not thread safe there (the heap, the reference counts, the baton). So every change of the session's state is protected: first by an explicit **session mutex** (one call into the interpreter at a time), or by a **thread-safe execution pool** (calls queued to interpreters that each own their heap). A9 measures the cost of the lock with the benchmark `p5x_sql_function` on DuckDB with 1 and with N threads. Only if the throughput is good enough does query concurrency grow; otherwise those queries run with DuckDB on one thread (`SET threads = 1`) until the pool exists.
- **Observation** (the author owns the syntax): D-116 prefers contextual keywords. `sql` is needed only before `function`, so it can be contextual and leave `sql` free as a name.

**Folders of a project with databases** (answers 7 and 14):

| Folder | Holds | Used how |
|---|---|---|
| `sql/` | native procedures and scripts in the database's language, and the migrations of F-DAT-10 | evedb creates them in the database; Eve calls them through `external` |
| `proc/` | Eve modules whose public procedures are **Eve stored procedures** | evedb checks them with evecp, keeps them compiled, and runs them for SQLite and DuckDB: from a script, through `db.call`, or from SQL (a procedure that is also a `sql function`). `evedb proc reload` reads them again. |

## 8. The interfaces in `evecm`

An interface is a struct with a context pointer and a table of functions, the shape of `std.mem.Allocator` and `std.Io`.

| Interface | Implemented by | Called by | Purpose |
|---|---|---|---|
| `Host` | evevm | evedb (`sql function`, `proc/`), the natives of `lib/` | `gpa`, `heap`, `io`, `raise`, `warn`, `call(func, args)`, `classOf` |
| `Native` calling convention | every native library | evevm | `fn (host, args) Signal!Value`. The arguments arrive **evaluated**: positional values, named options, type arguments resolved to `*Class`. Today a library call receives the syntax nodes of its arguments (`[]const *const Node`), which a bytecode VM can't give. |
| `Data` | evedb | evevm | the `database` library, connection and table methods, `beforeChange`/`afterChange` of tracked records, `enlist`, `commitJob`, `endJob`, `close`. It may be absent (WebAssembly, F-VM-09). |
| `Roots` | evevm | the tracing collector of the heap | the interpreter marks its frames, globals and tasks; today `heap.zig` imports `interp.zig` |
| `Meta` | evedb (SQLite, `eve.db` in the user data folder) | evevm, evetx, eveux (through `cmd`) | the cache of the user: projects, machines (no secrets), history of commands, upload manifest (Q-052 b); level 6 |
| `Dispatcher` | evevm (`vm.*`), evedb (`db.*`) | the doors of `evecm/wire`, eveux, the MCP server | one JSON-RPC message in, one reply out; in process, a function call |

## 9. Where every file goes

| Today | Lines | Goes to |
|---|---|---|
| `evevm/src/ast.zig` | 341 | `evecm/src/` (moves to `evecp` with the bytecode) |
| `decimal.zig`, `instant.zig`, `version.zig` | 356 | `evecm/src/`; the version string comes from a build option |
| `nfc.zig`, `nfc_data.zig` | 4,078 | `evecm/src/codec/` (`script/gen_nfc.py` writes the new path) |
| `heap.zig` | 859 | `evecm/src/`, with `Roots` |
| `interp.zig` lines 31–325 | ~300 | **cut** → `evecm/src/value.zig`, `signal.zig` |
| `interp.zig`, the rest | ~4,200 | `evevm/src/interp.zig`; its database fields (`dbs`, `core_db`, `tables`, `tracks`, `pending`) move to evedb |
| `task.zig`, `scratch.zig`, `vm.zig` | 1,149 | `evevm/src/` (`vm.zig` becomes `session.zig`) |
| `data.zig` | 403 | **cut** → `evecm/src/codec/csv.zig`, `json.zig`; `evedb/src/url.zig` |
| `dlib.zig` 1–1050 | ~1,050 | **cut** → `evevm/src/lib/stream.zig`, `fs.zig` |
| `dlib.zig` 1050–1271 | ~220 | **cut** → `evedb/src/conn.zig` |
| `orm.zig`, `sqlite.zig` | 1,224 | `evedb/src/` |
| `evedb/src/duckdb.zig`, `main.zig` | 169 | `evedb/src/duckdb.zig` (loaded with `std.DynLib`); `main.zig` becomes the `db` commands |
| `lexer.zig`, `parser.zig`, `check.zig`, `overload.zig`, `project.zig` | 4,775 | `evecp/src/` (`project.zig` becomes `link.zig`; its `env_lib_path` goes to `evecm`) |
| `doc.zig`, `scaffold.zig` | 509 | `evecp/src/` |
| `server.zig` | 641 | **cut** → `evecm/src/wire/` (config, JSON-RPC, transports, singleton); `evevm/src/machine.zig` (`vm.*`, `-loc`, `-rem`); `eveux/src/http.zig` (the web folder, `POST /rpc`) |
| `cli.zig` | 756 | **cut** → `cmd/eve.zig` (options, help, the part word); the command table of each part in its module |
| `line.zig`, `terminal.zig` | 361 | `evecm/src/term/` |
| `main.zig`, `root.zig` | 200 | `cmd/eve.zig`, `cmd/dispatch.zig`; one `root.zig` per module |
| `evevm/lib/`, `evevm/doc/` | | `lib/`, `lib/doc/` |
| `evevm/build.zig(.zon)`, `evedb/build.zig(.zon)` | | the root `build.zig` and `build.zig.zon` (`sqlite`, and the three `duckdb_*` as lazy dependencies) |

## 10. Work plan

**After every step:**

- the ReleaseSafe build;
- `runtest.py all`;
- `EVE_GC_VERIFY=1 runtest.py all` on the Debug build when values, the heap or sessions changed;
- `bmark.py --check` against the baseline of A0;
- `zig build test` (one test step per module from A7 on).

A step is done when all of them pass. A slowdown above 10% is explained in `test/bmark/README.md` or fixed before the next step.

**Every step:**

- Every moved function, type or test keeps its `// Zig tip:`; a cut file gets the tips its new half needs. New code gets tips: the vtable pattern, `*anyopaque`, `@ptrCast`, `std.DynLib`, `std.Thread.Mutex`, `std.Io` tasks.
- Cuts and moves are separate commits, so `git log --follow` still works.
- `plan/version_map.md` is updated when a feature changes stage.

### Phase A, version 0.0.5 (level 5): the split, `eve db`, `sql function`, `proc/`

What the user sees: `eve vm`, `eve cp`, `eve db` (the former `evedb.exe`), `eve ux`, the shortcuts of `run.sh`, `sql function`, `proc/`. Everything else behaves as today.

| Step | Work | Done when |
|---|---|---|
| **A0 Baseline** | Commit the work in progress (e95, `server.zig`, `test/project`, the other changes not yet committed). Record the tests, `bmark.py` (ReleaseSafe), the size of `eve.exe` and the time of `zig build test`. | `git status` clean; baseline numbers in `test/bmark/` |
| **A1 Values out of the interpreter** | `value.zig`, `signal.zig` (still in `evevm/src`); `interp.zig` re-exports them at first; `heap.zig` takes `Roots`. | GC verify passes; no file but `interp.zig` imports `interp.zig` for a type |
| **A2 Codecs** | Cut `data.zig` into CSV, JSON and connection URLs. | tests pass |
| **A3 Native calling convention** | `Host`, `Args`, `Native`; the interpreter evaluates the arguments before a library call. Convert `fs`, streams, `database`, connection and table methods one at a time, with a shim for the old signature until the last one. | no library function takes `[]const *const Node`; error positions unchanged (the expect blocks check them) |
| **A4 Database behind `Data`** | Cut `dlib.zig`; the ORM and the connections sit behind `Data`; the database fields leave `Interp`; a flag on a tracked object is checked before the indirect call on `setField`. | only the database files import `sqlite.zig`; level 5 tests and `p5*` benchmarks within 5% |
| **A5 Compiler entry point** | `compile` and `compileProject` wrap lexer, parser, check and link; `vm.Session`, `check`, `doc` and `scaffold` use them. | tests pass |
| **A6 Wire and commands** | Cut `server.zig` (config, JSON-RPC, transports, singleton, machine, HTTP door) and `cli.zig` (options and help in one place, a command table per part). | e95 (IPC, HTTP, both) passes |
| **A7 Flat move** | Root `build.zig` and `build.zig.zon`; `git mv` into `evecm/src`, `evecp/src`, `evevm/src`, `evedb/src`, `eveux/src`, `cmd/`, `lib/`; the old `build.zig` files go; the version comes from `build.zig.zon`; DuckDB through `std.DynLib`. | `zig build -p .` builds `bin/eve.exe`; every arrow of §3 holds (the build refuses others); `zig build test` per module; `eve hello.eve` runs without the DuckDB library |
| **A8 Parts and `run.sh`** | The first word `vm`, `cp`, `db`, `ux` chooses the part; `eve db …` takes over the commands of `evedb.exe`; the old forms stay as synonyms; `run.sh` gets the shortcuts of §4; `runtest.py` starts `eve db serve --test`; `eve project new` may write a start script. | `./run.sh evedb --version` prints the version of `eve`; the shortcuts work from a test project with relative paths; the remote-path tests run against `eve db serve --test` |
| **A9 `sql function`** | Spec first: the keyword (contextual or reserved, the author's choice) in `spec/lexical/keywords.json`, a page in `spec/library/`; tests (level 5, after e95) for SQLite and DuckDB; then the code: the checker collects them, evedb registers them, `Host.call` runs them. A benchmark `p5x_sql_function` with its Python twin (`sqlite3.Connection.create_function`). | the tests pass on both engines; the benchmark is in the table |
| **A10 Stored procedures** | Spec and tests first: `sql/` (native, through `external`) and `proc/` (Eve, run by evedb); `evedb proc list` and `evedb proc reload`; calls from a script and from SQL. | the tests pass |
| **A11 Tools and documents** | `runtest.py`, `bmark.py` (build from the root), `release.py`, `relnotes.py`, `gen_nfc.py`, `genkeywords.py`; `CLAUDE.md`; the READMEs of the modules; `manual/usage.md` (the parts, `run.sh`, `eve db`); `version_map.md` renumbered (D-167); a paragraph in `test/bmark/README.md` (speed and size against A0) | `mdlinks.py check manual` and `relnotes.py --check` clean. The release itself only when the author asks (D-153). |

### Phase B, version 0.0.6 (level 6): the serving machine, the APIs, ACP, the bytecode

| Step | Work | Done when |
|---|---|---|
| **B1 One serving process** | `dispatch.zig` starts the machine with its active parts as `std.Io` tasks; the doors of §5; calls between parts through the interfaces; the database door and `-loc` for databases; one script at a time. | e95 passes; new tests: a run that opens a database through the machine; `vm.stat` lists the active parts |
| **B2 `vm.*` and `db.*`** | The methods of §6.1; the old names accepted, then removed; `spec/library/machine.md` updated; the Node.js client of e95 moved to the new names. | tests for `vm.eval`, `vm.suspend`/`vm.resume`, `vm.inspect`, `vm.cancel`, `db.call` |
| **B3 Remote** | Every door on loopback by default; the `eve.cfg` keys to bind another address behind a proxy; `eve -rem` over HTTPS with the TLS client of the standard library, the user cache `eve.db` (`Meta`, Q-052 b); login by the two methods of D-171 and D-172 (`eve.env`, or parameters) and the keyring (F-NET-07, D-155, Q-051); `eve --connect` and `eve --upload` (the folders `web/`, `proc/`, `sql/` and the programs), `eve -rem … db install|migrate`; in the REPL `select <machine>`, the machine in the status bar, Ctrl+Left/Right to change it, Ctrl+Up/Down for the history of commands, `help` and Tab by machine (design-service.md §16); an example configuration for Caddy and Nginx in `manual/` (HTTPS, WebSocket, the loopback port). | a test with a local machine and a "remote" one on another loopback port (plain HTTP); a manual check through Caddy with HTTPS; a machine refuses a non-loopback bind without the `eve.cfg` key |
| **B4 ACP and the eve skills** | The MCP server of evevm (`--api`, design-service.md §6) with `vm.*` and `db.*` as tools; the ACP client in eveux (§6.2) with a test agent; then the agent end for IDEs. | a scripted ACP agent session runs a script and reads its output through eveux |
| **B5 Bytecode** | The instructions and the `.evb` format (version, hash, debug lines, capabilities) in `evecm`; the emitter and `evecp --compile` in `evecp`; the bytecode VM in `evevm`; a function value holds a code reference; `ast.zig` moves to `evecp`. | every level passes on the tree walker and on the bytecode VM; an `.evb` made on one machine runs on another |
| **B6 evetx, the terminal IDE** | Module `evetx` over libvaxis, in the sub-steps T0 to T8 of [evetx/README.md](../evetx/README.md) §8: T0 a spike (libvaxis with Zig 0.16 on Windows and Linux; may start any time), T1 skeleton and `-tx`, T2 model and editor buffer (pure, tested without a terminal), T3 file tree and editor (with the title and main menu, the two searches (file names by prefix; code, tables or data), the `#` jump, the inset status bar and the help dialog, D-174 to D-176), T3b preview of Markdown and images (D-177), T4 run and the bottom panel (the console with the design of evevm), T5 machines (F1 to F3), the user cache, project dialog and upload (needs B3), T6 debugger (needs B2 and the machine debugger, F-TLS-04, Q-053 b), T7 database tabs and the structure grid with the type list and the calendar (needs the `db.*` additions, Q-053 c), T8 polish and documents. If level 6 is too full, T6 and T7 move first (Q-053 a). No schedule screen: schedules are `eveux` work. | a session on two local machines: open a project, edit a file, upload it, run it, set a breakpoint, step, watch and continue, browse a table and rename a column; `zig build test` for `evetx` passes; the arrow `evetx` → `evecm` only is held by the build |
| **B7 Documents** | as A11, for the machine, the APIs, ACP, the bytecode and `eve tx` | as A11 |

## 11. Spec, manual, tutorial

| Where | Phase | Change |
|---|---|---|
| `plan/decision_level6.md` | before A0 | Q-049 and D-163 to D-167 (§1) |
| `evetx/README.md`, `manual/usage.md`, tutorial page | B6, B7 | `eve tx`, the views, the keys; the page after the spec of `sched.*` |
| `plan/version_map.md` | A0 and A11 | the headings renumbered (version N = level N); a feature for the split (F-VM-11); `sql function`, Eve procedures, the parts of `eve`, the machine API, the ACP client as features; F-VM-04 and F-VM-07 to 0.0.6; F-DAT-12 (evedb is part of `eve`) |
| `spec/lexical/keywords.json`, a page in `spec/library/` | A9, A10 | `sql`, `sql function`, `sql/` and `proc/` |
| `spec/library/machine.md` | B1, B2, B3 | the parts, their doors, `vm.*` and `db.*`; "HTTPS outside `localhost`" becomes "HTTPS by a reverse proxy" |
| `manual/usage.md` | A8, B2, B3 | `eve vm`, `cp`, `db`, `ux`, the shortcuts of `run.sh`, start scripts, the machine API, the proxy examples |
| tutorial | after the spec of each step | the database page (`sql function`, procedures), the server page (`vm.*`, ACP). The command `eve` does not change, so the other pages stay. |
| `CLAUDE.md`, READMEs | A7, A11 | build from the root, the modules, `bin/` |

## 12. Risks

| Risk | Where | Answer |
|---|---|---|
| Indirect calls on hot paths | A3, A4 | a flag before the call; `bmark.py --check` after each step |
| A value freed too early after the moves | A1, A3, A4, B1 | `EVE_GC_VERIFY=1` on the whole suite |
| DuckDB worker threads call `sql function`s at the same time | A9 | a session mutex or a thread-safe execution pool; the lock cost is measured before query concurrency grows; DuckDB on one thread for those queries until then |
| DuckDB library missing | A7 | loaded on demand; an error only when a DuckDB connection opens |
| No TLS server in Zig's standard library | B3 | no C TLS library in `eve.exe`: plain JSON-RPC/HTTP on loopback, a reverse proxy (Nginx, Caddy, Cloudflare Tunnel) for remote HTTPS |
| A plain door exposed to the network by mistake | B3 | loopback by default; another address only with an explicit `eve.cfg` key; the machine checks login and token itself |
| libvaxis does not build with Zig 0.16 or on Windows | B6 (T0) | a spike first; a pinned commit or a patch; the library is a dependency of `evetx` alone, so the loss is one part, not the build |
| `evecm` becomes the new monolith | every step | new code goes to the highest module that can hold it; a growing folder of `evecm` becomes a module |
| Parts in one process share a crash | B1 | sessions are isolated by their heaps; a panic in a session ends the session, not the machine (as `panic` does today for a listening machine, D-083) |

## Appendix: the author's answers

1. **ACP.** What is ACP in "eveux receives API calls using ACP"?
**Answer:**
I think Agent Client Protocol (ACP), to enable an AI agent to interact with eve, ux editor. It will enable user to bind eveux using an API key or OAuth and use AI to manage the eve environment using eve skills. Same interface can ve used by evevm to control form CLI a remote evevm.

1a. **Remote control.** One JSON-RPC layer with the machine methods of D-162, or should a remote evevm speak the ACP methods as an agent?
**Answer:**
evevm daemon (-lsn): Exposes a robust JSON-RPC machine API (D-162) over Unix sockets or secure HTTP/TLS. It understands commands like vm.eval, vm.suspend, vm.inspect, and vm.stat.

eve -rem / eveux: Acts as the client that speaks ACP to AI agents or IDEs, translating agent intent into the precise D-162 JSON-RPC calls required by the remote evevm instance.

2. **Layout.** Answered by the author's layout of 2026-10-12: flat modules, `cmd/` for the entry point, one `eve.exe`.

3. **The command people type.**
**Answer:** Yes, the new executable is evevm. Correct.
*Revision 3:* the executable is `eve.exe` again. *Revision 5:* `evevm` is the shortcut `./run.sh evevm` for `eve vm` (§4).

4. **Database path.**
**Answer:** Only projects contain /data folder. There is no data in the core. Core condain zig code not data.

5. **The Workbench folder.**
**Answer:** Correct. Every project can have it's own /src folder /doc /lib /web or module folders. However all executables go in root/bin folder for easy path/finding. Eventual with alias so I can issue commands from any test project.

6. **Several modules.**
**Answer:** Multiple modules.

7. **Stored procedures.**
**Answer:** Stored procedures are 2 kind. One kind will be in sql folder, these will be native to the database language for example pl/sql code or pg/sql code. The other kind of stored procedures are just native eve code modules that can be ingested by SQL and will be executed remote by the evedb. That's the purpose of evedb to hold stored procedures for interacting with SQLLight and DuckDB. For other databases evedb is a wrapper it will be able to execute stored procedures using "external" we bring just the signature in Eve.

8. **Bytecode timing.**
**Answer:** Move bytecode in version 6. This refactory will be part of version 5 and version 6.

9. **Versions.**
**Answer:** One single version for all programs. We need a common place where we keep the version number and release notes for each release.

10. **Syntax of `sql function`.**
**Answer:**
Both SQLLight and DuckDB enable C binding to functions all we need is to mark special functions to be registered for this purpose. We use:
"sql function name" a new keyword "sql". This enable creation of custom functions. Compiler will register these functions using Zig to C embeding. For other databases, we do not support custom eve functions yet. We just retrive data, modify using eve and push data back in bulk or one row at a time. We bring data to the process in this case. So we hope DuckDB with custom functions will be much faster.

11. **Serving parts.** Each serving part its own process talking over IPC, or one serving process holding all parts as threads?
**Answer:**
One serving process holding active parts as concurrent threads/tasks within a single process is superior to spawning separate local daemons communicating over IPC.

12. **Commands and aliases.**
**Answer:**
Multi-Call Binaries: Filesystem symlinks or hard links (evecp, evedb, evevm, eveux) point directly to eve.exe. Startup logic inspects argv[0] to route execution without flags.

13. **Version numbers.**
**Answer:** Level 5 will be version 5 and level 6 will be version 6. Now we are on version 3. Because version 4 and 5 are not yet stabile so I can't release yet.

14. **Eve procedures.**
**Answer:** ok, evedb projects can have a proc folder as well as a sql folder.

15. **DuckDB at start.**
**Answer:** Yes, DuckDB is loaded only if a DuckDB is issued. Though SQLight is different, it is embedded.

16. **`cmd/build.zig`.**
**Answer:** one build.zig in root. Is the src necesary though? Maybe just cmd will do if no other folders belong in cmd.

### Review of revision 4 (2026-10-12)

**Links.** Instead of hard links, modify run.sh from the root that will run eve, run evedb, run evevm, run eveux with other parameters pass through. User can create it's own scripts to start eve with proper parameters.

**TLS.** 2. Native TLS Server LimitationsRisk: Zig’s standard library provides a TLS client (primarily for package fetching) but lacks a fully baked built-in TLS server implementation.   Mitigation: Avoid compiling heavy external C-TLS libraries directly into the core binary. Instead, implement a clean local plaintext JSON-RPC/HTTP socket for loopback operations (-lsn), and mandate a lightweight reverse proxy (such as Nginx, Caddy, or Cloudflare Tunnel) in front of the machine for remote HTTPS (-rem) exposure.

**DuckDB.** 3. DuckDB Worker Thread ReentrancyRisk: DuckDB executes worker threads that can invoke registered evesql callback functions concurrently, threatening thread safety within the Zig runtime.Mitigation: Protect state mutations with an explicit session-level mutex or thread-safe execution pool. Benchmark the locking overhead in milestone A9 to verify if it satisfies throughput requirements before scaling query concurrency.

## 13. Progress

**2026-10-13, refactoring in the modules of §3 (commits `Split the VM into modules` to `evecm gets the configuration reader`):**

| Step | State |
|---|---|
| A0 baseline | done: 349 of 349 tests, benchmarks of the ReleaseSafe build |
| A1 values out of the interpreter | **done**: `evecm/value.zig` and `heap.zig`, with the pure helpers on values; `interp.zig` names them again |
| A2 codecs | `data.zig` is in `evecm` whole; the cut into `csv`, `json`, `url` is not made |
| A3 native calling convention | not started: the libraries still receive the syntax nodes of their arguments |
| A4 database behind `Data` | **done**: the module `evedb` (`sqlite`, `conn`, `orm`, `state`), the interfaces `Host` and `Data` in `evecm/iface.zig`, `evevm/host.zig`; the fourteen database fields of `Interp` became `evedb`'s `State` |
| A5 compiler entry point | not started (`evecp` exposes its parts) |
| A6 wire and commands | **half**: `evecm/config.zig` and `evecm/wire.zig` are cut from `server.zig`; the machine stays in `evevm/server.zig`; `cli.zig` is whole in `cmd/` |
| A7 flat move | **done**: root `build.zig` and `build.zig.zon`, the modules `evecm`, `evecp`, `evevm`, `evedb`, `cmd`; the version is written once; `lib/` moved; the arrows are enforced by the `.imports` of the build. The standalone `evedb.exe` (DuckDB) and `evetx` still have their own builds |
| A8 parts and `run.sh` | not started (the words `vm`, `cp`, `db`, `ux`, `-tx` are in `cmd/cli.zig` or to do) |

**2026-10-14:** `interp.zig` (4,293 lines) is split by concern: the struct, its fields, init, errors, scopes, regions, counted containers and the construction of values stay in `interp.zig` (about 1,000 lines); the methods of each section are plain functions `fn (it: *Interp, ...)` in `evevm/src/interp/` (`show`, `expr`, `collections`, `calls`, `stmt`, `script`, `parallel`, `generators`, `datatypes`), named again in the struct (`pub const eval = part_expr.eval;`), so every call `it.eval(n)` is unchanged.

The speed is unchanged (an alternating A/B timing of the builds before and after the cuts); the unit tests of every module pass with `zig build test`.
