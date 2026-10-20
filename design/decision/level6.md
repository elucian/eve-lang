# Decisions, level 6: the Eve machine and the server (version 0.5)

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. Ids are shared by all the decision files ([level 1](level1.md), [2](level2.md), [3](level3.md), [4](level4.md), [5](level5.md), 6, [7](level7.md)); the list of levels is in [decision_level3.md](level3.md) and [version_map.md](../version_map.md).

## Scope

One Eve machine, started locally or remotely: set up from its folder, controlled from scripts and from other machines, serving HTTP with `service` scripts, scheduling drivers, and offering its commands to AI assistants as an MCP server. A client/server application is two projects, a client and a server. Tests: `test/level6`, prefix `f`; a test is a pair of projects (client and server) started on `localhost` with different ports.

Features: F-TLS-11 to F-TLS-15, F-STR-08, F-NET-02 to F-NET-07 (F-NET-07: a login per remote machine, single sign-on, the keyring, D-155), F-VM-08, F-LIB-10, F-SPEC-06.

Decisions: **D-083** (below): one machine and one mode, `-x`, `-c`, `-rem`, `-u`, `send`, `--setup` and the machine folder, identity domain + port, ports 4042 and 8042, sessions and driver memory spaces (`load`, `dismiss`), `serve`, `service` and `route`, `panic` on a listening machine, the API for AI. Design and reasons: [design-service.md](../design-service.md). Tutorial: server.html. Related: D-081 (exit codes, run log).

## Draft features

1. **Removal of command files.** Done (D-188, 2026-10-18): `.vmc`, `-i`, `-t` and the old "serve mode" (D-063) are gone; `script/workflow.py` uses `eve --stdio`.
2. **Remote scheduler.** `schedule "<driver>" at "02:00" every day` in `eve.cfg` of a listening machine; retries and alerts on failure.
3. **EWP, the Eve Wire Protocol**, on port 4042 after the line protocol: remote `apply … at <machine> within <time>;`, data streams with credit, parallel streams that restart after a broken connection (review RNW-R04).
4. **Capabilities.** The resources a project may use on a machine (folders, hosts, databases, shell), listed in its configuration and checked when code is uploaded (review RNW-R08).
5. **Request and Response classes** of the `http` module, used by routes.
6. **System variables** of the machine to add to the register (D-071): `$EVE_NAME`, `$EVE_DOMAIN`, `$EVE_PORT`, `$EVE_HTTP_PORT`, `$EVE_WEB`, `$EVE_TOKEN`.

## Open questions

- Is the remote scheduler part of version 0.5, or later?
- Does `deploy` exist as a command of its own, or is uploading every file of a project with `-u` enough?

- Q-028 Networking and protocols [open]
- Q-050 evetx, a terminal UI over libvaxis for the projects of many machines [open]
- Q-047 Eve RAD Workbench (eveux): program, toolkit and the commands it needs from the machine (answered in part: D-154, D-155) [open]
- D-155 One local machine, many remote machines: a login per machine, single sign-on, the keyring of the system
- Q-048 Machine login: the details of D-155 [open]
- D-160 Eve is project oriented: the command `new project <folder>` and the project folders
- D-083 The Eve machine: command channels, setup, remote control, serve, services, API for AI
- Q-049 Splitting the monolith: modules, the parts of `eve`, the serving machine (answered → D-163 to D-167)
- D-163 Modules and one binary: `eve vm`, `eve cp`, `eve db`, `eve ux`
- D-164 The serving machine: one process, its parts as tasks
- D-165 The machine API `vm.*`, `db.*`; ACP outward; no TLS in `eve`
- D-166 Stored procedures, `sql function`, SQLite embedded and DuckDB on demand
- D-167 One version; version N is level N; the split in 0.0.5 and 0.0.6, the bytecode in 0.0.6
- D-169 `--listen [word]` replaces `-lsn [port]`: the two doors take the same words
- D-171 Two ways to give credentials; `--connect` before `--upload`; `-rem` always; `select` in the REPL (2026-10-13)
- Q-051 The details of D-171: its place next to D-155, names and gaps (answered in part → D-172)
- D-172 The answers to Q-051: two ways until level 7, a dialog for the password, `eve.env` in JSON, `-tx` and `-ux`, F1 to F3
- Q-052 Proposals after D-172: the project layout (`server/`), the user cache `eve.db`, the options `-tx` and `-ux` [open]
- D-173 evetx is a project IDE in the terminal: file tree, editor, run and debug, database tabs (2026-10-13)
- Q-053 The size and the needs of the evetx IDE [open]
- D-174 evetx: menu, find and replace bar, inset status bar, grid dialog, console of evevm (2026-10-13)
- Q-054 The details of D-174: keys, the gear, search scope, types, the calendar, the console [open]
- D-175 evetx: two searches, each aligned with the panel it searches (2026-10-13)
- Q-055 The details of D-175: matching, keys, and the search of file contents (answered → D-176)
- D-176 The answers to Q-055: names that start with the letters, a global data search, `#` instead of the gear (2026-10-13)
- Q-056 The details of D-176: the type-ahead keys, `#`, the wildcard and the number (answered: all agreed → D-177)
- D-177 evetx: the preview button; Markdown, images and SVG are previewed; HTML, audio and video are not (2026-10-13)
- Q-057 The details of D-177: SVG, image formats, the Markdown subset, the view, the cards (closed by D-178)
- D-178 evetx: no preview, a file card for binary files; no tests; implementation starts (2026-10-13)
- D-188 `-s` is only the service, `-e` (`--setup`) the configuration file; the command files `.vmc` are removed (2026-10-18)
- D-187 SQLite in eve, DuckDB in evedb; column batches on the native protocol and the driver `evedb://`; no triggers or procedures in evedb (2026-10-18)
- D-186 evedb behaves like PostgreSQL: the PostgreSQL protocol on port 5432, the Eve driver `postgres://`, a configuration file, `eve -s -db --serve`, stored procedures and triggers in Eve (designed) (2026-10-17)
- Q-063 The details of D-186: EWP-db or SQL for the control, `version()`, the names of the procedures and triggers, one Eve host [open]
- D-185 Service mode: `eve -s`, the machine without a user interface, a Windows service or a Linux daemon; evedb detailed design and version 0.1 (2026-10-17)
- Q-062 The details of D-185: the REPL with a configuration file, the foreground form, privileges and the event log, evedb as a service [open]
- D-184 Data engines: SQLite :memory: for queries, a native columnar table for pipelines, DBF only as a legacy file decoder (2026-10-17)
- Q-059 The Eve syntax of the columnar table, `load` and `store` [answered, implemented 2026-10-17]
- D-197 The component `cmd` is renamed `eve` (2026-10-19)
- Q-067 A simpler architecture: one runtime, a shared compiler, the compiler inside the editors [answered → D-198]
- D-198 The architecture: one runtime with SQLite, the compiler as a program, the DuckDB server leaves (2026-10-19)
- Q-068 Points the answers to Q-067 leave open [answered → D-199, D-200]
- D-200 Drivers: the DuckDB server stays an executable with DuckDB embedded, launched by eve; a driver table; documentation of every driver (2026-10-19)
- D-199 Answers to Q-068: the editors include evecp; no license file in drivers/; the server ships in bin/; the protocol is a module imported by evevm (2026-10-19)


## Q-028 Networking and protocols (2026-10-06)

Moved from level 7 on 2026-10-08: the Eve Wire Protocol, sockets and the server are level 6 (F-NET-02 to F-NET-06, draft feature 3); the HTTP client is level 5 (F-NET-01).

The pages networking.html and protocols.html collect ideas that are not designed: the layers (names, connection, protocol, data), the type `Url`, the module `net` and `http`, capabilities in the project file, `Secret`, the Eve Wire Protocol (frames HELLO, APPLY, RESULT, ERROR, BATCH, CREDIT, CANCEL, PING, CLOSE; CBOR payloads; resume by batch number), HTTP/1.1 and HTTP/2, WebSocket for browsers. Questions: do sockets exist in the language or only protocols? Is EWP wanted, or only HTTP with JSON? Which level takes the HTTP client (3) and which the server (6)? Names of the error classes of the network?

**Answer:**

## Q-047 Eve RAD Workbench (eveux): program, toolkit and the commands it needs from the machine (answered in part: D-154, D-155)

Author request (2026-10-10): a full RAD workbench in the folder `code/eveux/`, in plain JavaScript and plain CSS with a Zig web toolkit, presented in phase 6 of the tutorial: menu, login form, user registration, admin user, database object tree, code editor, command window, file dialog to load and import files, job scheduler and browser, log inspector "similar to Jenkins or better", direct SQL from the command line with the result in a WYSIWYG grid, Help and About with the version, syntax colors for HTML, JSON, XML, Eve and SQL, scripts run from the command line, step-by-step run, variable inspector and watch window. Design: [code/eveux/README.md](../../code/eveux/README.md); tutorial: eveux.html; features F-TLS-19 to F-TLS-22.

Proposals, each with its question in the design file:

- (1) a separate Zig program `bin/eveux.exe` on port 8046 that talks to Eve machines on their command port, not a folder served by `eve serve`;

- (2) plain JavaScript modules with JSDoc types and no build step, not TypeScript compiled by `tsc`;

- (3) a *watched run* on the line protocol of the command port, so output, logs and debugger events stream to the Workbench before EWP exists;

- (4) our own toolkit `modules/zweb/` on `std.http`, shared with `eve serve` and evedb;

- (5) new machine commands for files (`files`, `read`, `save`, `delete`);

- (6) SQL that changes data runs in a transaction with Commit and Rollback buttons;

- (7) `let` on a variable while halted in debug mode;

- (8) stepping one parallel task holds the others. New debugger commands of the machine, so that the REPL and `eve -c` get them too: `step into`, `step out`, `break <file>:<line> [if <condition>]`, `locals`, `stack` (F-TLS-04).

  **Answer:** (2026-10-10, in part) "We use Eve to build eveux as ultimate test of Eve capability and a stress test. Therefore is in level 7 that is actually last level. Zig is used for making a full capable eve virtual machine evevm that can handle from a local instance multiple remote evevm machines." Proposals (1) and (4) fall away: eveux is an Eve project run by the local machine, with no Zig program and no Zig toolkit of its own (D-154); the login to remote machines is D-155. The other proposals stay open, as questions 1 to 10 of `code/eveux/README.md`.

## Q-048 Machine login: the details of D-155 (2026-10-10)

Proposals in `design/design-service.md` §15, for the author:

- (a) single sign-on by **OpenID Connect** (authorization code with PKCE in the browser, device code without a browser), so Entra ID, Keycloak, Okta and Google work; Kerberos and the integrated login of a Windows domain later, or also in the first version?

- (b) The keyring holds the **renewal token** that the remote machine gives back, never the password nor the token of the provider; a renewal token expires after 30 days without use.

- (c) **Without a keyring** (a Linux server with no desktop session): ask at each start, or read a machine token from the environment; never a plain file. Or allow an encrypted file?

- (d) **Users and roles** live in the Eve database of each listening machine (`viewer`, `operator`, `developer`, `admin`), with the registration setting `$EVE_REGISTRATION` (`closed`, `approval`, `open`) and a mapping of provider groups to roles.

- (e) New commands of the machine: `login`, `logout`, `forget`, `whoami`, `user add`, `user role`, `session end`; the option `--login` of `eve -c`.

- (f) The method of each remote machine is written in the configuration of the local machine: `machine prod at "etl1.example.com:4042" login sso`.

- (g) macOS Keychain in the same version, or later?

**Answer:**

## Q-050 evetx, a terminal UI over libvaxis for the projects of many machines (2026-10-13, open)

Author request (2026-10-13): "create evetx a full TUI using zig binding to existing library libvaxis. This will enable project management and schedule management for one or more remote eve machines … a full-screen TUI using zig binding to existing library libvaxis. This will enable project management and schedule management for one or more remote eve machines … prepare the plan implementation for level6". Changed by the author the same day: "Move schedule to eveux. Eve ux manage runs, evetx can run for debug purpose and test." Design: `code/evetx/README.md`; plan: `design/design-packages.md` revision 6, step B6. Proposals, for the author:

- (1) libvaxis is already a Zig library, so there is no binding to write: it is a package dependency of the module `evetx` only;

- (2) `evetx` imports `evecm` only, like `eveux`, and is the part word `eve tx` with the shortcut `./run.sh evetx` (proposed as D-170);

- (3) settled: schedules and the management of runs (job browser, run history, logs) are `eveux` work (F-TLS-21), so the schedule methods of the machine API are designed with `eveux`, not in step B2; `evetx` manages machines and projects and has a Run view for debug and test;

- (4) the registry of machines, the credential store (keyring) and the login flow go down to `code/evecm/wire`, so `eve -rem`, `eveux` and `evetx` share them (moves part of D-155);

- (5) project deploy: settled by D-171, the upload of `web/`, `proc/` and `sql/` after `--connect` (details in Q-051);

- (6) libvaxis with Zig 0.16 and Windows is unchecked: the spike T0 decides, with a pinned commit, a patch or a thin terminal layer as fallbacks.

Not answered yet.

## Q-052 Proposals after D-172: the project layout (`server/`), the user cache `eve.db`, the options `-tx` and `-ux` (2026-10-13)

Proposals for the author.

- **(a) Layout: one project, a `server/` folder.** The author asked for an opinion between `src/server` with `src/local`, and `<project>/local/src` with `<project>/server/src`. Proposal: **neither tree.**
  - (1) `proc/`, `sql/` and `web/` stay at the root of the project: they are server-side by their nature (D-166), and `project init` makes them already (D-160).
  - (2) Add one folder **`server/`** for the Eve programs that run on a server: the scheduled drivers and the `service` script.
  - (3) Everything else (`<name>.eve` at the root, `asp/`, `src/`, `test/`, `doc/`) stays local.
  - (4) **The upload sends `web/`, `proc/`, `sql/`, `server/` and every module they import or link**, found by the compiler (`evecp` link), not by folder: a `proc/` module that imports `lib/text.eve` needs that file on the server, and a rule by folder would miss it or ship the whole `lib/`. Why not two trees: `lib/` and `eve.cfg` are shared by both sides, so two trees duplicate them or break the imports; `src/` is already "other sources" in D-160, and moving the three server folders under it would break `sql/schema.sql` of the tests. A real client/server **application** (two programs, two teams) stays what design-service.md §1 says: two projects, one client and one server, in one repository.

- **(b) The user cache `eve.db`.** The author: Eve keeps the projects in a cache, in a `meta` folder, as a SQLite table; this seems to need SQLite in evevm after all. Findings: SQLite is **already embedded** in `eve` (the core database, D-156; D-166); DuckDB is the part loaded on demand. What is missing is not SQLite but a **store of the user**, not of a project: proposal `<user data folder>/eve/meta/eve.db` (Windows `%LOCALAPPDATA%\eve\meta\eve.db`, Linux `$XDG_DATA_HOME/eve/meta/eve.db`), different from the `meta/` folder of a project (which is versioned). It holds the tables `project` (name, path, layout version, last opened, last machine), `machine` (name, address, user, last connection; **no password and no token**), `history` (commands per project and machine, for Ctrl+Up), `manifest` (file hashes of the last upload per project and machine, so an upload sends changed files only and the Projects view shows in sync, changed, new). It is a **cache**: delete it and the projects return as they are opened. The arrows of design-packages.md §3 hold if evecm gets a small interface `Meta` (like `Data`, §8), evedb implements it with the SQLite it already has, and `cmd` connects it; evetx and evevm never import evedb. It is **level 6** (step B3, before the Machines and Projects views of evetx).

- **(c) `-tx` and `-ux`.** Options as D-169 made `--listen` and `--serve`; the part words `eve tx` and `eve ux` of D-163 stay as synonyms (`eve ux start` and `eve -ux` are the same). `-u` is removed rather than kept, because the author finds it unclear.

- **(d) The shape of `eve.env`.** Proposal: `{ "prod": { "user": "ana", "password": "…" }, "test": { "user": "ana", "password": "…" } }`; a value may be `"$NAME"`, read from the real environment, so a CI system gives the secrets without a file; the file is read only by `eve` of this project, and on Unix it must be mode 600 or it is refused. `project init` and `project new` add it to `.gitignore` and write a template without secrets.

- **(e) More ideas.** The history of commands in the cache also gives `history` and the search with Ctrl+R; the manifest gives a `diff` of local and server in the Projects view; a `dry run` of the upload that lists what would be sent; the status line of the REPL and evetx share one component.

Not answered yet.

**Answer:**

## Q-053 The size and the needs of the evetx IDE (2026-10-13)

Proposals and questions for the author, from the design of D-173.

- **(a) Size.** An editor, a debugger and a database browser are three programs in one. Is all of it level 6 (version 0.0.6) with the split, the bytecode and the machine API, or does the first release of evetx have the file tree, the editor, run, the bottom panel, the machines and the upload (steps T0 to T5) and the debugger and the database tabs (T6, T7) follow in the next version? Proposal: order the work as in `code/evetx/README.md` §8 so that each step is usable alone, and decide at T5 whether T6 and T7 stay in 0.0.6.

- **(b) The debugger of the machine** (F-TLS-04) is open: today `halt` breakpoints and `vm.suspend` and `vm.resume` exist, nothing sets a breakpoint by file and line, steps into or out, or evaluates in the paused frame. Proposal: add to the machine API, after B2: set and clear a breakpoint by file and line, step into, step out, continue (the `vm.resume`), the paused place, evaluation in the paused frame, and the two streams of a run (stdout, stderr); the names are the author's to choose. These are also what `eveux` needs (F-TLS-22), so one API serves both.

- **(c) The database methods.** `db.query` and `db.execute` exist; the table list, a page of rows, the description of a table and the change of a table need methods or `db …` commands (F-DAT-09 has `db tables` and `db describe`). Proposal: `db.tables`, `db.rows` (a page), `db.describe` and `db.alter`, named by the author.

- **(d) What "edit structure" may do.** Rename a column, add a column and drop a column are easy in SQLite 3.35 and later; a new type or a new key needs the rebuild of the table (copy, drop, rename); DuckDB allows more. Proposal: the dialog lists what Apply will do, shows the SQL on request, and asks before a rebuild or a drop of a column with data; a table of a remote machine is changed only by a user whose role allows it (D-155 §15.4).

- **(e) Step over.** The author lists Run, Step into, Step out, Continue and Stop. Most debuggers have Step over (next line). Add it, as a sixth button, or not?

- **(f) What the editor must do** in the first version. Proposal: plain text with syntax colors for Eve, SQL and JSON; cursor, selection, copy and paste, undo and redo, search and replace in a file, save, a mark for an unsaved file, line numbers and the breakpoint gutter; no completion, no folding, no multiple cursors. Completion from the language server (F-TLS-09) later.

- **(g) Where a run goes when the file is local.** On the local machine (F1) the program runs from the file on disk. On a remote machine (F2, F3) it must be uploaded first (D-171). Proposal: when the file is changed and not uploaded, Run on a remote machine says so and offers Upload and run; a breakpoint is checked against the hash of the file on the server, so a breakpoint never lands on a different line.

- **(h) Keys.** F5 run, F8 continue, F9 breakpoint, F11 step into, Shift+F11 step out, Shift+F5 stop (drawn in the SVG, proposed). They are used by IDEs, but Windows Terminal and some SSH clients or multiplexers take some F-keys; check them as in Q-051 i.

- **(i) Two UIs.** `eveux` (level 7) has the same editor, debugger and database features (F-TLS-19 to F-TLS-22). Should the design of the debugger and of the database dialogs be written once, in the machine API and in a page of the spec, so that both screens follow it?

**Answer:**

## Q-054 The details of D-174: keys, the gear, search scope, types, the calendar, the console (2026-10-13)

Proposals and questions for the author.

- **(a) Keys the terminal cannot tell.** A classic terminal sends the same bytes for Ctrl+Enter as for Enter, and for Ctrl+/ as for Ctrl+_ (and Ctrl+Shift+S as Ctrl+S, Ctrl+, as a comma). They work only where the terminal speaks an enhanced keyboard protocol, which libvaxis uses when it can. The spike T0 tests Windows Terminal, the Windows console and a Linux terminal. Proposal: keep Ctrl+Enter and Ctrl+/ as asked, and add **F10** (menu) and **F12** (help) as keys that every terminal sends; the title and the `?` button work with the mouse anyway. The shortcuts of the menu (Ctrl+O, Ctrl+N, Ctrl+S, Ctrl+Shift+S, Ctrl+W, Ctrl+Q, Ctrl+Z, Ctrl+Y, Ctrl+F, Ctrl+H, Ctrl+K, Ctrl+U, Ctrl+,) are my proposals; the F-keys of the debugger are in Q-053 h.

- **(b) The gear in two places.** The author asks for a gear in the tool bar (top right) and in the status bar (bottom right). Do both open the same Settings dialog, or is one for the application (colors, keys, tab size) and the other for the project (machines, `eve.env`, upload rules)? Proposal: both open one dialog with two pages, Application and Project. What Settings holds is not decided: proposal: colors (a dark and a light theme, a no-color mode), borders (box drawing or ASCII), tab size and spaces or tabs, mouse on or off, the keys that can be changed, the user cache folder, the machines list (name, address, user; no secrets).

- **(c) The scope of Find.** In an editor: the text of the file (Enter next, Shift+Enter previous). In a table list: it filters the tables. In a data tab: it filters the rows (the database does the work, `db.rows`). Replace and Replace all are only for an editor and are off in the other tabs. Search in all the files of a project is not drawn; proposal: later.

- **(d) One menu.** The drawing has one list of sections (File, Edit, Run, Machine, Help) opened both by a click on the title and by Ctrl+Enter. Or does Ctrl+Enter open a menu bar with drop-downs (File, Edit, …) and the title a different list? Proposal: one menu. "Sage/Save-As" is read as Save and Save As.

- **(e) The types in the list.** The types of the engine of the file (SQLite: INTEGER, REAL, TEXT, BLOB, NUMERIC and the common names; DuckDB: its long list), or the types of Eve (`Integer`, `Decimal`, `Text`, `Boolean`, `Instant`, …) mapped to the engine by the data language? Proposal: the engine's own names in the list, and the Eve type that goes with it shown beside the cell, since the file is read by other programs too.

- **(f) What the calendar writes.** A chosen day gives a fixed value (`'2026-10-13'`); **Today** and **Now** give the expressions of the engine (`CURRENT_DATE`, `CURRENT_TIMESTAMP`). The Default cell shows which of the two it is. Is that the author's intention?

- **(g) The status bar.** Name of the file or table, then the place: `Ln, Col` in an editor; `Record n of N · Field: name` in a data tab; `Table k of n` in a table list; `Field n of m: name` in the structure dialog. Add the encoding and the line ending (`UTF-8 · LF`) for an editor?

- **(h) The console of evevm.** Its design is the REPL screen of `manual/usage.md` (the upper part with a scrollback of 50,000 lines, a rule, the command line `eve:> `, a rule). In evetx the machine runs the commands (`vm.*`, or the command channel of `eve -c`), and the `Ready` and `Running…` state moves into the status bar of the application. To use the same code and not only the same look, the scrollback buffer and the line editor of the REPL (today `line.zig` and `terminal.zig`) go to `code/evecm/term`, which D-163 already plans; libvaxis draws the screen in evetx and the REPL keeps its own drawing. Agree?

**Answer:**

## Q-063 The details of D-186 (2026-10-17)

Proposals and questions for the author; they are also at the end of `drivers/duckdb/README.md`.

- **(a) The control port.** Keep EWP-db as the control port of the tests, or move the control to SQL on the PostgreSQL port (`pragma eve_stop`, `select * from eve_status()`) and drop EWP-db? Proposal: keep it until the change sets are decided.

- **(b) `select version()`.** Answer `PostgreSQL 16.4 (evedb 0.2 on DuckDB v1.5.6)` for tools that test the word PostgreSQL? Proposal: yes.

- **(c) Names of section 12** (closed by D-187: no procedures or triggers in evedb). `database.caller()` (the connection of a procedure back to the calling session), `raise … with state "P0001"`, the keys `procedures`, `eve`, `procedure_timeout`.

- **(d) One Eve host per server** (closed by D-187: no Eve host in evedb).

- **(e) The ORM on PostgreSQL.** `table` declarations and tracked records on a `postgres://` connection: in 0.5 (they need the change sets of `design-database-core.md` §7 sent as SQL), or later?

- **(f) TLS** for the driver and for evedb, needed before eveux?

**Answer:**

## Q-065 Catching an error inside Eve code (2026-10-18)

The standard library found that `recover` exists only at the end of a process (and aspect), so a function can not catch an error (`backlog/library-gaps.md` G-4). A server must turn the error of a handler into an error answer and go on. Options, for the author to choose (the syntax is the author's):

- (a) `recover` allowed at the end of a function and a procedure, like a process: `function f() => (@r: T) is … recover … return;`.
- (b) a `try` form for a block or an expression: `try … recover … done;`.
- (c) no change in the language: every handler is an **aspect** (an aspect recovers its own error, D-072), run with `apply`; `rpc.dispatch` and the routes then take aspects, not lambdas.
- (d) a native `call_safe(f, args)` in the library that gives a result record with the error (no syntax).

**Model's lean:** (c) for level 6, because it needs nothing new and matches how a service script is designed (one aspect per group of routes); (a) later if functions need it.

**Answer:**
I agree with (a). Any subprogram like a process can have a recover region. A function, procedure or method can have a recover region.

## Q-066 String functions: plain text or regular expression (2026-10-18)

The tutorial (`strings.html`, String functions) lists `String.find(pattern: Regex)`, `String.count(pattern)` and `String.replace(pattern, cargo)`, and says a string literal that starts with `/` is a regex literal. The standard library needs `trim`, `upper`, `lower`, `starts_with`, `ends_with`, `contains`, `find` and `replace` now (config files, routes, headers), before the regex engine (S11) exists, and a path such as `"/data"` must not be read as a pattern. `spec/library/strings.md` takes the **plain text** reading for these functions and keeps the regex forms for the module `regex` (`regex.find`, `regex.replace`, `regex.count`) and the operator `=~`.

- (a) Plain text for the string methods, regex in the module `regex`: confirm or change.
- (b) `find` gives `0` when there is no occurrence (proposed); or an optional/`Null` result.
- (c) `upper` and `lower` ASCII only for now; full Unicode case mapping later.

**Answer:**

## Q-068 Points the answers to Q-067 leave open (2026-10-19, answered → D-199, D-200)

Each point is needed by one stage only (in brackets); the stages before it can go on.

1. **(c) The editors include `evecp`** (S8.6 to S8.8). Confirm: yes (the request said so; the answer lines skipped it). 
**answer** yes 
2. **The program of the DuckDB driver** (S8.4). The folder is `drivers/duckdb`. The program is `evedb.exe` today, and the tests, the scripts and the manual use that name. 
**answer** keep it like it is until I figer out if a driver is executable or a dll. Where is the driver?
**Reply (model):** There are two things with the name evedb. (1) The **client side**: the code that makes `database.connect("evedb://…")` and `"postgres://…"` work (`ewpdriver.zig`, `pgdriver.zig`, now in `drivers/duckdb/src/`). It is already compiled into `eve.exe`; S8.2 moves it to `code/evevm/src/db/`. (2) The **server**: `bin/evedb.exe`, a separate program that loads `bin/duckdb.dll` (35 MB) and listens on ports. `eve.exe` never loads the DLL; it talks to the server over a socket. Three ways to have DuckDB: **executable server** (today: DuckDB stays out of `eve.exe`; many clients; the PostgreSQL face; faults for tests; cost: a second process), **embedded** (`eve.exe` loads DuckDB: no second process, the fastest, but `eve.exe` needs the DLL, and it reverses D-187 "DuckDB lives only in evedb"), **plug-in DLL** loaded by `eve` at run time (small `eve.exe`; Zig offers only the C ABI for it, and the project switched native extension loading off for SQLite on purpose). Stages S8.1 to S8.4 do not depend on the choice, and S8.5 only moves the folder. Kept as it is, as you say. The question "DLL files or embedded?" is analysed in [design-drivers.md](../design-drivers.md), with a recommendation: client drivers embedded in `evevm`, the DuckDB engine a server for now, no Eve plug-in DLLs.
3. **The license of `drivers/`** (S8.4). `code/LICENSE` (BUSL 1.1) covers `comp/` and the root README puts everything else under CC BY-NC-SA, which is not right for code. *Model: the same BUSL 1.1* for `drivers/`, with its own `LICENSE` file; or another license of your choice.
**answer** No license file.
4. **Does the distribution ship the driver?** (S8.4). Today `bin/evedb.exe` and `bin/duckdb.dll` (35 MB) are in the zip. *Model: yes, as an optional driver in `bin/`.* 
**answer** Why we need an optional driver?  
**Reply (model):** "Optional" was my word, and there is no good reason for it: `eve.exe` runs every script without the server because SQLite is built in, but nothing is gained by leaving the server out of the zip. It ships in `bin/` with the other programs.
5. **The protocol files shared by the driver and the Eve side** (S8.1, S8.4): `ewp.zig`, `batch.zig`, `client.zig`, about 800 lines, the wire protocol between the server and the native driver `evedb://`. *Model: each side keeps its own copy*, and the protocol document with its test (`script/evedb_check.py`) is the contract; the copy is a line of technical debt. Or the driver project exports them as a Zig package that `evevm` imports.
**answer** Yes second. The driver is imported in evevm. Once we implement a new driver it will be included in VM.
6. **The command words** `eve db serve <cfg>` and `eve -s -db --serve <cfg>` (S8.4). They start the server program found beside `eve.exe`. *Model: keep them as launchers* of the driver; `eve db import|export|sql|proc list` stay, since they work on the database layer inside `evevm`.
**answer:** Is there any alternative? If not yes.
**Reply (model):** Yes, there are alternatives, so please pick (needed by S8.5 only): **(A)** keep both words as launchers of the server (today: `eve -s -db` reuses the service mode of `eve`: silent, a log file, the Windows service manager); **(B)** drop them: the user runs `evedb serve --config evedb.cfg` and registers `evedb.exe` with the service manager itself (`sc create … binPath= "…\evedb.exe serve --config …"`); `evedb` then needs its own service mode and log; **(C)** if DuckDB is embedded (point 2), `eve db serve` runs the server inside `eve`. *Model: (A) for now*: (B) and (C) need work that is not planned, and (A) is a few lines of `code/eve/db_cmds.zig`. `eve db import|export|sql|proc list` stay in every case.
**Answer:**

## D-199 Answers to Q-068: the editors include evecp; no license file in drivers/; the server ships in bin/; the protocol is a module imported by evevm (2026-10-19)

Author answers to Q-068 (2026-10-19). Settled:

- **(1) The editors include `evecp`: yes.** `evetx` and `eveux` import it (S8.6 to S8.9).
- **(3) `drivers/` has no `LICENSE` file of its own.** Consequence: the root `README.md` must say which license covers the code of `drivers/` (today it says everything outside `comp/` is CC BY-NC-SA, which would reach it). *Model: name `drivers/` in the sentence about `code/LICENSE` (BUSL 1.1) and add it to the Licensed Work of that file;* to confirm when S8.5 writes it.
- **(4) The server ships in the distribution.** From "why do we need an optional driver?": no option; `bin/evedb.exe` and `bin/duckdb.dll` are in the zip.
- **(5) The protocol is shared as a module, not copied.** "The driver is imported in evevm. Once we implement a new driver it will be included in VM." Drivers are code that `evevm` imports. The three files of the protocol (`ewp.zig`, `batch.zig`, `client.zig`) become the Zig module `ewp_protocol` (S8.1, in place), imported by the server project and by the Eve side in `evevm`. No second copy. The root build and the server's build each make the module from the same files by path, so the root build does not fetch the DuckDB library (it is a lazy dependency of the server's build only).

Still open in Q-068: **(2)** whether the DuckDB driver is an executable server, embedded, or a library (the folder is `drivers/duckdb` and the program stays `evedb.exe` meanwhile), and **(6)** the command words (alternatives A, B, C in the reply). Both are needed by S8.5 only.
**answer** 
DuckDB is executable evedb.exe and is launch using eve launcher, but instead of using DuckDB.dll we should embed DuckDB uzing zig bindings into evedb.exe. evedb.exe can be called using eve command to read a configuration file that tell server where to store the files and what options to use. (If DuckDB has options) We need documentation for every driver.

Root License apply to drivers.  
Driver table is approved.

## D-200 Drivers: the DuckDB server stays an executable with DuckDB embedded, launched by eve; a driver table; documentation of every driver (2026-10-19)

Author answers to Q-068 points 2 and 6 and to `design/design-drivers.md` (2026-10-19). Settled:

- **DuckDB stays a server.** The program is `evedb.exe`; `eve` launches it (alternative A of Q-068 6: `eve db serve evedb.cfg` and `eve -s -db --serve evedb.cfg` stay). The configuration file tells the server where to store the files and which options to use.
- **DuckDB is embedded in `evedb.exe`.** "Instead of using DuckDB.dll we should embed DuckDB using zig bindings into evedb.exe." The binding `duckdb.zig` stays; the library is linked **statically**, so the zip no longer needs `duckdb.dll` (35 MB beside the program). How (the prebuilt static libraries, or the amalgamation compiled by Zig) is not known yet: stage S8.10a starts with a spike (does it link, how long does it build, how big is the program) and reports before the change is made. Until then the DLL ships (D-199 4).
- **The root license applies to `drivers/`.** No `LICENSE` file in `drivers/` (D-199 3). The root `README.md` names `drivers/` in the sentence about the license of the code, and the Licensed Work line of `code/LICENSE` names it (S8.5).
- **Every driver is documented.** One manual page for each driver: the client drivers `sqlite://`, `postgres://`, `evedb://` (the URL, the options, the types, what is supported) and the DuckDB server (the commands, the configuration file). Written in S8.10 and kept with the driver.
- **A driver table is approved** ("This is good, add to plan"): one struct of functions per driver, chosen by the URL scheme, in place of the `if` chains of `conn.zig`. Stage S8.4a.
- **The recommendation of `design-drivers.md` is accepted:** client drivers are embedded in `evevm`, the DuckDB engine is a server, no Eve driver DLLs.

## D-201 Bytecode: a register machine, a project bundle, the tree walker kept as the reference (2026-10-19)

Author answers to Q-B1 to Q-B9 of `design/design-bytecode.md`. Settled:

- **Register machine** (Q-B1), 32-bit instructions.
- **Versions** (Q-B2): the refactoring ladder R0 to R8 and the first stages of the VM in the current line; the `.evb` file and the embedding in 0.7 (`version_map.md`). `design-packages.md` B5 now points to the design.
- **The tree walker is kept as the reference engine** (Q-B3): once stable it needs no maintenance, and it stays the oracle of the tests.
- **One bundle per project** (Q-B4): Eve projects are small.
- **JIT in version 0.8** (Q-B5); **change of the `Value` layout in version 0.8** (Q-B6); **tail calls in version 0.10** (Q-B7); a depth limit by configuration, `StackOverflow` as a language error.
- **Targets** (Q-B8): those of §11, with +10% accepted in this phase; the risky and expensive steps are avoided; optimization stops after R4 if the result is good enough.
- **Order of the ladder** (Q-B9): R0, R1, R2, test, R4, test.
- **Order of the work:** the blockers left in levels 5 and 6 come before the bytecode.
