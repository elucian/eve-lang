# eveux: elaboration of the design ideas

> **Update 2026-10-18.** Written for the browser Workbench. Since then eveux is the **native** client (`code/eveux/README.md`) and the web side is **evewp** (`code/evewp/README.md`). The server side of this file (source control, deploy with manifest and versions, the machine messages of section 6, the backends of section 9, the silent rule) stands unchanged. Where it says "browser", "WebSocket to the page" or "one-time key", read: the native window on the stdio door.

Status: **proposal for confirmation**, 2026-10-18, revised the same day after the author's corrections of `design-ideas.md` (eve is the server; eveux and evetx are the clients; evedb is the backend of the server). It elaborates `code/eveux/design-ideas.md` and checks every idea against the design that exists (`code/eveux/README.md`, `design/design-service.md` §7, §15 to §17, `spec/library/machine.md`, `design/design-packages.md`, D-154, D-155, D-160, D-162 to D-165, D-171, D-172, D-185 to D-189). **Nothing in `spec/`, the tutorial or the code was changed for it.** After the answers of section 10, the accepted parts move into `code/eveux/README.md` and the plan.

## 1. The ideas, in one paragraph

Two places. On the **developer's computer**: eveux, with the local file system, a local Git repository (branches, commits, diff) and the preferences of the screen. On a **server**: a daemon that holds the deployed code, the Eve runtime and ETL engine, a job orchestrator (start, stop, schedule), the real-time stream of the logs, and the connectors and schema introspection of the data sources. The developer edits and versions **locally**, **deploys** when ready (a Git push to a staging remote, or a fast direct file sync or bundle), then **controls** the server from the editor: starts jobs, reads live logs, previews processed data. Transport: WebSocket, SSH or gRPC. `evedb` is the server, `eveux` the client. eveux (like evetx) refuses to start silent; only `evedb` can run silent; `evedb` serves HTTP, `eveux` and `evedb` consume HTTP; every machine can be controlled by IPC.

## 2. Reading the ideas against the existing design

| # | Idea | Verdict | Why |
|---|---|---|---|
| 1 | Edit locally with the local file system | **Confirmed, with a correction** | A browser has no access to the local file system or to Git. The "local" tier is therefore two programs: the browser page and the **local Eve machine** (`evevm`), which already runs the Workbench (`eve --setup eveux --serve`, README §4). The machine does the file and Git work; the browser only shows it. |
| 2 | Local Git: branches, commits, diff | **Confirmed, new** | Fits D-160 (Eve is project oriented, `git init`, `.gitignore` that keeps `db/*.db` and `log/*.db` out). It is not in the README yet: new section "Source control" (section 4 here). |
| 3 | Deploy by Git push to a staging remote | **Not as the default** | It would make the remote machine a Git server (a Git daemon or SSH access, branches, hooks) and ties Eve to Git on every server. See section 5. |
| 4 | Deploy by a direct file sync or bundle | **Confirmed: this is `--upload` (D-171)** | `eve --upload` already sends `web/`, `proc/`, `sql/`, `server/` and the modules they import; a remote machine runs only what is on it. Elaborated with a manifest, versions and a diff (section 5). |
| 5 | Remote daemon: deployment target, runtime and ETL engine, job orchestrator, log streaming, connectors and schema introspection | **Confirmed: it is the serving machine** | `eve -s` (D-185): runtime + database + UI parts in one process (D-164). Each item has a place in the machine (section 6); four are missing (jobs API, log tail, file commands, database tree). |
| 6 | Transport WebSocket / SSH / gRPC (the corrected text lists IPC, SSH and WebSocket) | **gRPC is gone in the corrected text; confirmed** | WebSocket: yes (browser to local machine; JSON-RPC messages of the lasting doors). SSH: yes, already designed (`ssh host eve --stdio`, evetx). **gRPC: no**: it needs HTTP/2, Protocol Buffers and a C++ or Zig library that the project does not have, for a gain over JSON-RPC that Eve does not need. See section 7. |
| 7 | Roles: eve the server; eveux and evetx the clients; evedb the backend of the server | **Confirmed by the author's correction** | Matches the serving machine of D-164 (`eve -s`, the runtime part is the daemon) and the clients of D-172. evedb is not a second server for the clients: only `eve` talks to them. The consequences for evedb (spawned or embedded, not a network daemon of its own for the clients) are section 9. |
| 8 | eveux refuses to start silent, like evetx | **Confirmed, with the reason** | The Workbench needs a user session: the keyring (Windows Credential Manager, Secret Service) belongs to a logged-in user and a Windows service has none; the one-time key (README §6.1) is printed on a console and the browser is opened for that user. `eve -s` with the eveux project, and evetx with `-s`, are a usage error (exit 64) with this explanation. |
| 9 | Only evedb can start and run silent | **Rule restated, still to confirm** (Q-2) | `eve -s` makes the **machine** silent too (service, daemon, foreground, D-185). Read as: *servers run silent (the `eve` daemon and the evedb it manages); programs with a screen (eveux, evetx, the REPL) never do.* |
| 10 | evedb serves HTTP; eveux and evedb consume HTTP | **Dropped by the correction** | The only HTTP door is the one of `eve` (`POST /rpc`, WebSocket, routes). evedb gets no HTTP door; eveux reaches the database through `db.*` of the machine (the recommendation of the first version of this file). |
| 11 | All machines can be controlled using IPC | **True for the same computer; across computers the same messages travel on another door** | IPC is a Unix socket (D-162), local only. The messages are one set, JSON-RPC 2.0 `vm.*` and `db.*`; the doors are IPC (same computer), stdio (a child, or over SSH), HTTP and WebSocket (other computers, behind a reverse proxy for TLS, D-189). So "control by IPC" becomes "control with the machine API on whichever door reaches the machine". |

## 3. The elaborated architecture

```
 DEVELOPER'S COMPUTER                                         SERVER (one or many)
+------------------------------------------------+          +-----------------------------------------------+
| Browser: eveux page (JS, CSS)                  |          | Eve machine, service mode (eve -s)            |
|   editor, explorer, git panel, jobs, logs      |          |   runtime part   vm.*   run, jobs, debug      |
|        | WebSocket + HTTP (localhost only)     |          |   database part  db.*   tree, describe, query |
|        v                                       |          |   UI part        HTTP / WebSocket / routes    |
| Local Eve machine (evevm, eveux project in Eve)|  HTTP    |   deployed code: versions, manifest           |
|   files   -> fs module, watch                  |  /rpc,   |   eve.cfg, users, roles, audit                |
|   git     -> os.run! ("git", args, no shell)   |  WebSocket|  logs, schedule                              |
|   deploy  -> bundle, manifest, upload          | -------> |                                               |
|   login   -> keyring, tokens                   | or SSH   | evedb: the database server of the machine     |
|   many remote connections                      | stdio    |   PostgreSQL protocol, EWP-db                 |
| Local files + .git + preferences               |          +-----------------------------------------------+
+------------------------------------------------+
```

Rules of the picture:

- **The browser never talks to a remote machine and never holds a secret.** Everything passes through the local machine, which holds the logins in the keyring (README §6, design-service.md §15). This stays as designed.
- **One set of messages.** The browser to the local machine, and the local machine to a remote one, speak the same JSON-RPC 2.0 (`vm.*`, `db.*`, and the additions of section 6); only the door differs (spec/library/machine.md, "Lasting doors"). evetx already uses them over stdio.
- **The local machine is a client of the remote ones**, the browser a client of the local machine. With the author's correction the roles are: **eve is the server; eveux and evetx are the clients; evedb is the backend of the server.** "eveux is the client" is true of the pair browser + local machine.
- **Git is local.** The remote machine needs no Git.

## 4. The local tier: files, source control, preferences

**Workspace.** A workspace is the folder of an Eve project (D-160) on the local computer, opened by the local machine. The explorer shows two roots side by side: the **local project** (files on this computer) and each **remote machine** (what is deployed there), so a file is always shown with where it is. Today README §7 shows only machines; the local project is a machine too (`localhost`), so no new concept is needed: the local project is "machine local".

**What the local machine needs from the library** (all in the plan of `design/design-libraries.md`): `fs` list, stat, glob, copy and a **watch** (to see an edit made outside eveux; TD gap of the audit), `os.run!` with a time-out and streamed output for Git (TD-9, TD-27), `crypto.sha256_file!` for hashes (done), `ws` for the browser (M4).

**Source control panel** (a view of Git, not a Git implementation; every action is `git` run by `os.run!` with an argument list, no shell, in the project folder only):

| Action | Command run |
|---|---|
| status, changed files | `git status --porcelain=v2 -z` |
| diff of a file or of the commit | `git diff`, `git diff --cached`; shown as a side-by-side or unified view |
| stage, unstage, discard | `git add`, `git restore --staged`, `git restore` (discard asks for confirmation) |
| commit | `git commit -m` (message from the panel; author from the Git configuration) |
| branches | `git branch`, `git switch`, `git switch -c`; the current branch is in the status bar |
| history of a file or of the project | `git log --format=...` |
| initialise | `git init` (already done by `new project`, D-160) |

The panel is shown only when the folder is inside a Git repository and `git` is found; otherwise it offers `git init` or says that Git is not installed. A merge, a rebase or a conflict is not solved in eveux at 0.1: the panel says "use your Git tool" and shows the conflicted files. Credentials of Git remotes (GitHub, GitLab) belong to Git's own helpers, never to eveux.

**Preferences.** Layout, open tabs, theme, font size, recent projects, the list of machines without secrets, the last manifest sent to each machine: tables of the user cache `eve.db` in the user data folder (F-DAT-15, SQLite, as the corrected `design-ideas.md` says), written by the local machine, one set per user. What belongs to a server (users, roles, sessions, jobs, deploy versions) is in that server's core database (section 9).

## 5. Deployment

**Principle.** Deploy sends the **server side of the project** to a machine, which checks and keeps it under a version. It is `--upload` of D-171 with a manifest. Git is the source of the version number, not the transport.

**Steps** (button *Deploy to…* in the Machines menu, and `eve --upload`):

1. **Choose the machine and, if wanted, the commit** (default: the working tree; a dirty tree is allowed for a test machine and refused for a machine marked `production` in its `eve.cfg` without a clean commit).
2. **Build the bundle**: the files of `web/`, `proc/`, `sql/`, `server/` and the modules they import (the rule of Q-052 a), never `db/*.db`, `log/`, `eve.env` or anything in `.gitignore`.
3. **Manifest**: for each file its path, size and SHA-256, and for the bundle the project name, the Git commit id, the branch, whether the tree was clean, the user, the time and the version of Eve. The local cache `eve.db` (F-DAT-15) keeps the last manifest sent to each machine.
4. **Diff against the machine** (`deploy.plan`): the remote returns its current manifest; eveux shows files *added*, *changed* and *removed*, and only the changed files are sent (a "fast sync"). The first deploy sends everything.
5. **Send** (`deploy.apply`), one request or a stream of batches; the remote writes into a staging folder.
6. **Check on the remote**: `eve cp --check` of the whole bundle under the remote's rules and capabilities (F-NET-05). Errors come back with file and line and are shown in the Problems tab; nothing is activated.
7. **Activate**: the remote switches to the new version atomically (a folder per version and a pointer), reloads `proc/` and the routes, and keeps the previous versions (a number set in its `eve.cfg`, default 5).
8. **Result** in the Output tab and the job history: version, commit, files changed, time.

**Rollback**: *Machines → Versions* lists the versions of a machine with commit and user; *Activate this version* switches back with no upload. **Dry run**: steps 1 to 4 and the remote check without activation.

**Why not `git push` to a remote.** It needs Git and a writable repository on every server, gives no check under the machine's rules before the code is live, and cannot send a dirty tree for a test. It stays possible as an *option* later: a machine may have a `deploy_hook` that pulls from a Git URL (a CI style deploy), but it is not the default path (Q-5).

**No binaries.** Eve is interpreted from source in the first versions, so "checked-out code / binaries" is "the deployed source version". A signed compiled form (`.evb`) is the WebAssembly work of level 7 (F-WEB-02) and would be one more file kind of the bundle.

## 6. The remote tier: what the machine must offer

| Idea | The machine part | Messages | State |
|---|---|---|---|
| Deployment target | runtime | `deploy.plan`, `deploy.apply`, `deploy.versions`, `deploy.activate` | **new** (with F-NET-09) |
| Files of the machine (browse, read, save, delete) | runtime | `fs.list`, `fs.read`, `fs.write`, `fs.delete` (README question 6) | **new**, limited to the allowed folders |
| Run and stop a program, output as it runs | runtime | `vm.run`, `vm.eval`, `vm.cancel`, `vm.stop` with `"stream": true` and `vm.output` | **done** (e95_test5) |
| Job orchestrator: start, stop, schedule | runtime | `job.list`, `job.start`, `job.stop`, `job.schedule.*`, `job.runs` | **new**; the schedule is in `eve.cfg` (design-service.md §11), Q-050 |
| Real-time log streaming | runtime | `log.list`, `log.tail` (subscribe, pushes `log.line`) | **new** (module `log`, library plan E8) |
| Debugger | runtime | `dbg.*` | **new** (F-TLS-04) |
| Connectors and schema introspection | database | `db.query`, `db.execute`, `db.call`, `db.stat` exist; `db.tree`, `db.describe`, `db.sample` (preview of N rows) | **partly done** |
| Preview of processed data | database | `db.sample(connection, table, n)` and the paged `db.query` | **new** (small) |
| Users, roles, audit | runtime | `user.*`, `audit.list` (README §6.5) | **new**, level 7 |

The names are proposals; they follow D-165 (a prefix by part). Rules of a remote machine (design-service.md §10) still apply: a method the machine does not allow answers an error that eveux shows.

## 7. Transport and security

| Link | Transport | Login |
|---|---|---|
| browser to local machine | HTTP + WebSocket on `localhost`, session cookie, CSRF token, one-time key (README §6.1, §15) | the key |
| local machine to a remote machine on the same network or the Internet | JSON-RPC over HTTP (`POST /rpc`) and WebSocket, **behind a reverse proxy for TLS** (D-189: no TLS in the machine; level 8) | token from the login of the machine (level 7) |
| local machine to a remote machine by SSH | `ssh host eve --stdio` (the stdio door): SSH does the login and the encryption; nothing to open on the server | the SSH login |
| same computer, a command line or a script | IPC socket | the operating system user |

SSH is the safest first way to reach a real server (no port, no proxy, no Eve login) and is already built for evetx; eveux can use it as a second kind of connection in *Machines → Add machine* ("by SSH"). gRPC is not planned (section 2, row 6). Until level 7 login exists, remote connections are localhost tests only (D-189).

## 8. Process rules ("silent")

| Program | May run silent? | Why |
|---|---|---|
| Eve machine, service mode (`eve -s`) | yes | a server: log file, pid file, no console (D-185) |
| evedb (stand-alone `evedb serve` or `eve -s -db --serve`; or the child that eve manages) | yes | a server, or a backend of one |
| eveux (the local machine running the Workbench) | **no**: `eve -s` with the eveux project is exit 64 | needs the user session (keyring), a console for the one-time key, a browser to open |
| evetx, the REPL | **no** | they are the screen |

So "only evedb runs silent" is read as "only **servers and their backends** run silent", and the machine that serves eveux on the developer's computer is a client in this respect (Q-2).

## 9. The backends of the server: SQLite and evedb

The corrected `design-ideas.md` ends with a verdict: *keep eve as the server daemon; SQLite embedded in eve for operational metadata, preferences, session states, workspace configurations and the local catalog; evedb (DuckDB) for heavy columnar ETL, "embedded or managed by eve", not a network server daemon of its own.* Against the existing design:

| Part of the verdict | Verdict | Notes |
|---|---|---|
| eve is the central execution server and hosts the REPL; evetx and eveux are its clients over IPC, SSH and WebSocket | **Confirmed** | as sections 3 and 7 |
| SQLite is embedded in eve (D-156, D-187) | **Confirmed** | The **core database** of a project (`db/`, D-156 to D-159) already holds logs, checkpoints, users, run history. Add: the deploy versions and manifests, the job state, session records. |
| SQLite holds *user preferences, session states, workspace configurations* | **Confirmed, in two places** (Q-4) | *On the server* (the core database of the machine): users, roles, sessions, jobs, deploy versions, audit. *On the developer's computer* (`eve.db` of the user cache, F-DAT-15): the layout, open tabs, theme, the list of machines **without secrets**, recent projects, the last manifest sent to each machine. A preference follows the person to a new computer only if it is also stored on a machine they use; that is a choice for later (sync of preferences). |
| evedb (DuckDB) runs heavy analytical ETL | **Confirmed** | `Memory` tables, `Memory.store/load` as column batches, a group-by 55 times faster than SQLite (D-187). |
| eve **embeds or spawns** evedb; evedb is not a network daemon for the clients | **Changes the current use, keeps the code** | Today `evedb` is a **separate program** that answers as PostgreSQL on port 5432 and on the EWP-db control port, and the Eve driver `evedb://` connects to it (D-186, D-187). A user starts it by hand or as a service. The verdict makes it a **managed backend**: see the two options below. |

**Two ways for eve to "embed or spawn" evedb**

| Option | What | For | Against |
|---|---|---|---|
| **A. Spawn (recommended)** | `eve` starts `evedb` as a **child process** on first use of `evedb://managed` (or when a pipeline needs the columnar engine), on a private endpoint: a Unix socket or named pipe in the runtime folder, or a random loopback port, with a random token. It stops it when idle or at exit, restarts it when it crashes, and reports it in `vm.stat`. | DuckDB stays out of `eve.exe` (D-187: the binary stays small, the build stays fast); a crash or a runaway query in DuckDB cannot take the machine down; the protocol and the driver already exist and are tested (f01, f02, `evedb_check.py`); the memory limit and the thread count of DuckDB are set per child; the same `evedb` is still usable alone as the test database. | A process hop (measured: 1,000,000 rows in 0.23 s through column batches, so cheap for ETL); one more thing to supervise. |
| **B. Embed** | link DuckDB into `eve.exe` and call it in the process. | no process boundary, one binary. | contradicts D-187 ("DuckDB lives only in evedb", "never in the VM"); the prebuilt DuckDB library is large next to `eve.exe`; a DuckDB crash is an Eve crash; a C++ runtime in the build; it undoes the benefit of keeping the engines apart. |

What option A adds to the plan (new, small, not started): `evedb` gets a **managed mode** (listen only on the private endpoint given by the parent, exit when the parent dies, no configuration file needed); `eve` gets a **supervisor** in the database part (start, health check, stop, restart); the driver gets the URL `evedb://managed/<name>`; `vm.stat` shows the child. The existing server mode (`evedb serve --config`, port 5432, `eve -s -db --serve`) stays: it is how a team shares a test database, how a PostgreSQL client reaches it, and what the level 6 tests use. Nothing about the clients changes: **eveux and evetx never talk to evedb**; they send `db.*` and `vm.*` to `eve`, which uses SQLite or the managed evedb.

**Which engine for which request from eveux.** A SQL tab on a SQLite connection or on the core database goes to SQLite. A SQL tab on an `evedb://` connection, the result of a pipeline held in a `Memory` table, and the preview of processed data (`db.sample`) go to the managed evedb. The object tree shows both, each labelled with its engine.

## 10. What would change when confirmed (not done)

- `code/eveux/README.md`: add *Source control* (§4 here) and *Deployment* (§5) sections; rewrite §4 "Architecture" as the two-tier picture with the local machine named; add the silent rule to §6.1; add the new messages of §6 to §4.1; add SSH as a kind of connection in §6; mark the questions answered.
- `spec/features/`: new features **F-TLS-31 eveux source control** and **F-NET-10 deploy (plan, apply, versions, rollback)**; the messages `fs.*`, `job.*`, `log.*`, `db.tree`, `db.describe`, `db.sample` added to F-NET-08.
- `design/design-service.md` §7 and §16: the deploy steps (manifest, diff, staging, check, activate, versions) replace the one line "Deploy".
- `spec/library/machine.md`: the new methods, when they are built (level 6 for `deploy.*`, `fs.*`, `log.*`, `db.tree`; level 7 for the rest).
- `design/design-libraries.md`: `fs` watch/stat/glob and `os.run!` streaming and time-out move from debt to the milestones M4/M6.
- Tests: `test/level6` (deploy design/apply between two machines on localhost, `fs.*`, `log.tail`), `test/level7` (the Git panel against a temporary repository).
- `spec/features/` and `drivers/duckdb/README.md`: F-DAT-12 gets the managed mode (option A of section 9); `design/design-packages.md` (D-164) names the supervisor of the database part.
- `code/eveux/README.md` section 7 (explorer): label each connection with its engine (SQLite, evedb).

## 11. Questions for the author

Each has the model's recommendation first; the answer line is yours.

**Answered by your corrections of `design-ideas.md`:** which program is the server (eve; eveux and evetx are clients; evedb is its backend); evedb has no HTTP door of its own (the only HTTP door is the one of eve); gRPC is not used (IPC, SSH and WebSocket).

1. **Managed evedb.** Option A of section 9 (eve spawns evedb as a child on a private endpoint; DuckDB stays out of `eve.exe`), or option B (DuckDB linked into `eve.exe`)? *Recommended: A. B reverses D-187.*
**Answer:**
2. **Silent.** Is the rule "servers run silent (eve, and the evedb it manages), programs with a screen never do"? *Recommended: yes.*
**Answer:**
3. **The stand-alone evedb.** Keep `evedb serve` (port 5432, PostgreSQL clients, the level 6 tests) next to the managed mode? *Recommended: yes.*
**Answer:**
4. **Where preferences live.** Layout and open tabs in `eve.db` on the developer's computer; users, roles, sessions, jobs and deploy versions in the core database of each server (section 9)? *Recommended: yes; no synchronisation of preferences between computers at 0.1.*
**Answer:**
5. **Deploy.** Bundle upload with manifest, diff and versions as the default (section 5), `git push` only later as an optional hook? *Recommended: yes.*
**Answer:**
6. **Production machines.** May a machine refuse the deploy of a dirty Git tree (marked `production` in its `eve.cfg`)? *Recommended: yes.*
**Answer:**
7. **SSH as a connection kind** in eveux (`ssh host eve --stdio`): version 0.1 of eveux for tests on localhost, real servers with the login of level 7? *Recommended: yes.*
**Answer:**
8. **Merge and conflicts.** Left to the user's own Git tool at 0.1 (section 4)? *Recommended: yes.*
**Answer:**
9. **Versions kept on a machine.** Default 5, set in `eve.cfg`? *Recommended: yes.*
**Answer:**
10. **Rollback and the database.** A rollback activates old code only; it does not undo migrations of the database (those have their own `db migrate`, F-DAT-10). Confirm? *Recommended: yes; the deploy plan lists pending migrations and never runs them without a separate command.*
**Answer:**
