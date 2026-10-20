# Decisions, level 7: web, HTML and WebAssembly (version 0.6)

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. Ids are shared by all the decision files ([level 1](level1.md), [2](level2.md), [3](level3.md), [4](level4.md), [5](level5.md), [6](level6.md), 7); the list of levels is in [decision_level3.md](level3.md) and [feature_map.md](../feature_map.md).

## Scope

Level 7 is the server: evedb, the Eve machine with DuckDB inside, and the web portal. Eve produces safe HTML and runs in the browser. A service returns HTML built from templates that escape every value by context; the Eve machine itself is compiled to WebAssembly, so Eve code runs in a page, and the tutorial gets a "Run" button on its examples. Tests: `test/level7`, prefix `g`.

Features: F-WEB-01 to F-WEB-04, F-VM-07, F-VM-09, F-DOC-03 (web part), the server (evedb, D-203, D-204). The Workbench eveux (F-TLS-19 to F-TLS-22, F-TLS-31) moved to level 6 (D-205).

## Draft features

1. **The HTML type.** A value of type `HTML` is produced only by templates or by `html.escape`; `res.body` of a route accepts `HTML` for pages, so text from users can't inject scripts (review RNW-R05).
2. **Templates.** Template files (`.htmt`) or template literals where `{expr}` is escaped by context: text, attribute, URL, script.
3. **The VM in WebAssembly.** `evevm` compiled to `wasm32`, with host functions for the console, fetch and timers (review RVM-R06).
4. **Portable bytecode** `.evb`: versioned, with a hash and the capabilities it needs; what a browser downloads from a machine (review RVM-R05).
5. **Tutorial playground.** A "Run" button on the examples of the tutorial, with the VM in WebAssembly.

## Open questions

- Templates as separate files, as literals in Eve code, or both: Q-027 below.
- Which Eve code may run in a browser: pure functions only, or aspects with limited capabilities?

- Q-027 Templates [open]
- D-154 eveux, the RAD Workbench, is written in Eve: the final test of the language, in level 7
## Q-027 Templates (2026-10-06)
The page templates.html teaches string templates (today) and proposes HTML templates: files `.htmt` or literals, `{expr}` escaped by context (text, attribute, URL, script), the type `HTML`, components as functions that return `HTML`, the module `html` with `html.render` and `html.write`. Questions: files, literals or both? The extension and the module name? Loops and conditions inside a template (`{for o in orders}`)? Is `HTML` required by the functions that send a page?

**Answer:**

## D-154 eveux, the RAD Workbench, is written in Eve: the final test of the language, in level 7 (2026-10-10)
Author decision, reviewing the first draft of `code/eveux/README.md` (Q-047): "We use Eve to build eveux as ultimate test of Eve capability and a stress test. Therefore is in level 7 that is actually last level." (1) The server part of eveux is an Eve project (a service script, aspects, modules) run by the local Eve machine; the browser part stays plain JavaScript and plain CSS. No separate Zig program, no Zig web toolkit for eveux: what is not Eve code is a feature of `evevm` (`serve`, WebSocket, connections, login), so every Eve program gets it. (2) eveux is the acceptance test and the stress test of level 7 and of Version 0.6: its tests are in `test/level7`, its stress run is a benchmark `p7a_eveux`; a failure is fixed in the language or the VM, not worked around. (3) Features F-TLS-19 to F-TLS-22 move from Version 0.5 to Version 0.6. (4) The tutorial keeps the page `eveux.html` in phase 6 (Internet features). Related: D-155 (the login to remote machines).

## D-193 evewp, the Eve Web Portal, replaces the Workbench as the level 7 project; eveux becomes a native Zig client (2026-10-18)

Author decision (2026-10-18): "Create evewp for a new module, Eve Portal, that replaces the Eve Workbench as a production server, that uses Eve but no JavaScript. We create an Eve framework that enables Eve (a dialect) to be compiled in WebAssembly modules and run on the client, making web development the ultimate Eve test. Refactor the tutorial to replace eveux with evewp; the eveux folder is free for a native Zig implementation. Move the old eveux readme to evewp and create a new readme for eveux." The idea note of the author (`code/evewp/wp-design-ideas.md`): a production web server, reverse proxy and monitoring gateway; subdomain multi-tenancy with one folder for each application; static files and a proxy to the Eve daemon; a graphic health monitor; not a development layer but a deploy layer. Earlier the same day the author fixed the roles: **eve is the server; eveux and evetx are the clients; evedb is the backend of the server** (`code/eveux/design/notes/design-ideas.md`).

Read as rules:

- (1) **evewp** (`code/evewp/README.md`) is the level 7 project and the final test and stress test of Eve (the role of D-154, which it replaces): a production **edge** (hosts, static files, proxy), **host** (applications in folders, versions, supervision, deploy) and **monitor** (health, traffic, domains, users), written in Eve with native byte loops in the system library, plus the **Eve Web framework**: Eve with a browser profile compiled to WebAssembly (stage W1: the VM in Wasm; stage W2: a typed subset compiled to Wasm), no JavaScript written by the developer. Features F-WEB-05 to F-WEB-07 and F-VM-12; F-VM-09, F-WEB-01 to F-WEB-03 are its base.
- (2) **eveux** (`code/eveux/README.md`) is the **native graphical development client** in Zig on dvui, for Windows first, then Linux and macOS; a client of the machine like evetx, on the stdio door. Its functional specification is the browser Workbench design, kept in `design/archive/workbench-design.md`; the features F-TLS-19 to F-TLS-22 stay and become Zig work, not level 7 Eve work. The folder `code/eveux/` holds the new design, the author's notes, the elaboration (source control, deploy) and the dvui analysis with its spike.
- (3) **The tutorial** page `eveux.html` becomes `evewp.html`; the tutorial words that said eveux for the web part say evewp.
- (4) **Older documents** (`design/design-service.md`, `design-packages.md`, `decision_level5.md`, `decision_level6.md`, `spec/library/machine.md`, `database.md`): where they say eveux for the browser Workbench, read evewp; where they say eveux for the editor, SQL console, jobs and debugger, read the native eveux. They are not rewritten one by one.
- (5) *Proposed, to confirm* (questions of `code/evewp/README.md` §14 and `code/eveux/README.md` §8): the part word `eve ux` becomes `eve wp` for the web part; TLS stays with the reverse proxy; the framework syntax is left to the author after a first prototype; `await` stays out of the browser profile until the VM can suspend.

Not done in this round: the spec pages for the browser profile and the framework, the plan details of the machine messages (`deploy.*`, `fs.*`, `job.*`, `log.*`), and the spike of eveux.

## D-194 Order of the work, second change: plan, design, user interfaces, refactor, optimize, test, spec, compiler, manual, tutorial (2026-10-18)

Author decision (2026-10-18): "Update the plan and cleanup the plan. The priority has change, we update tutorial last, we make plans first, we modify the design second, we create user interfaces, we refactor, we optimize, we test we update spec we progress the compiler."

Read as rules:

- (1) **Order of the work, the highest first:** (1) the plan (`design/`), (2) the design (`design/design-*.md`, the README and `design/` of each program), (3) the user interfaces (`code/evetx/`, `code/eveux/`, `code/evewp/`), (4) refactor, (5) optimize (`test/bmark/`), (6) test (`test/`), (7) the specification (`spec/`), (8) the compiler (`code/evecp/`, `code/evevm/`, `code/evecm/`, `drivers/duckdb/`, `code/eve/`: the language and the machine progress), (9) the manual (`manual/`), (10) the tutorial (`tutorial/`), last. It replaces D-190 (1). The next piece of work is taken from the highest rank that has open work; it is a ranking of what to do first, not a pipeline that every feature goes through.
- (2) **The spec follows the tests.** D-190 wrote spec text before the failing test; now the behavior is settled by the tests and the code, and the spec page is written or corrected after them (rank 7). The spec stays normative once written: when it and the tutorial disagree, the spec wins.
- (3) **The manual is not named in the order**; it is placed ninth, before the tutorial, where D-190 had it (after the implementation). *To confirm.*
- (4) **Optimization is allowed.** The restriction of 2026-10-07 ("do not optimize early", until level 2 passes) is over: levels 1 to 5 pass. The benchmark rules of CLAUDE.md stay (measure before and after, ReleaseSafe build, `bmark.py --check`).
- (5) **Cleaned in the same round:** the focus of `design/README.md` (it still said "tutorial first", 2026-10-07), the phases table (a rank for each phase), the old notes "tutorial first" in `design/design-unified-aspect.md` and `design/archive/review-2026-10-04/focus.md`, TD-13 (paid by D-192) removed from `backlog/tech-debt.md`, and `design/focus-level5.md` (level 5 passes: 115 of 115) moved to `design/archive/`.

## D-195 Code is local; a tested project is deployed and then operated; one tool bar that follows the file (2026-10-18)

Author decision (2026-10-18): "The user interface is too bloated as is designed now, we have two run buttons in eveux. The one button run SQL the other run the code. I need a dynamic toolbar that change by file type. The code is always local, this I can tell. I also can tell we need to upload code on the remote machine after the code is locally tested first. After we upload the code is controlled by a schedule or by production websites created with evewp. Because I can no longer connect visually to the code. This is true for both user interface evetx and eveux. The difference is with evetx I can connect over SSH and work remote while with eveux I can't do this."

Read as rules:

- (1) **Code is local.** A project is edited, run, debugged and tested in the **local** machine (the child `eve --stdio` of the program), on the computer of the user. Run and Debug never target a remote machine.
- (2) **Deploy after a local test.** A project that passed its tests is uploaded to a remote machine (Tools > Deploy…: diff against the target, checks, versions, rollback; `code/eveux/design/design-deploy.svg`). A remote machine receives only deployed bundles.
- (3) **After the upload the code is operated, not edited.** On the remote machine the code is controlled by a **schedule** (`eveux` for schedules and runs, F-TLS-21) or by a **production web application made with evewp**. The UI no longer connects to the running code visually: no remote Run, no remote debugger, no remote editor in eveux. What it shows of a remote machine: status, schedules (pause, resume), jobs and their last runs, live logs, versions and rollback, health. This holds for **evetx and eveux**. It replaces the rule of D-171 and of the evetx README ("Machines", cut 2026-10-16) that Run and debug act on the selected machine and that on a remote one only an uploaded program can run: now nothing is run by hand on a remote machine.
- (4) **SSH.** `evetx` is a terminal program: started inside an SSH session on the remote computer (`ssh host`, then `evetx project/` or `eve -tx project/`) it reads and edits the files that are there, so the administrator can work remote. `eveux` is a window and cannot run in a session; it reaches a remote machine through the machine API, with the stdio door over SSH (`ssh host eve --stdio`, `spec/library/machine.md#lasting-doors`), **for deploy and operate only**. *Not written:* `ide.link.Link` starts `<exe> --stdio` and cannot take a command with arguments (TD-38).
- (5) **One tool bar, and it follows the active file.** The buttons depend on the kind of the file (drawing `code/eveux/design/design-toolbar.svg`, table `TOOLBARS` of `code/eveux/design/gen_svg.py`): Eve (Run, Stop, Debug, Check, Test, Deploy…; the step buttons only while debugging), SQL (connection, **Run**, Script, Explain, Commit, Rollback), database table (Describe, Structure, Import, Export, Refresh), data file (Grid or Text, filter, Load into table, Save as), document (Source, Split, Preview, Open in browser), image (zoom, fit, rotate), audio and video (player). **Run is one slot:** F5 runs an Eve file in the local machine, Ctrl+Enter runs a SQL statement; the second Run button of the SQL tab is gone. A button that cannot be used in the state is dimmed or absent.
- (6) **Out of the bar** (less bloat): the machine selector `F1 local · F2 prod · F3 test` (remote machines live in Tools > Machines and in the Deploy dialog), the search field (Ctrl+Shift+F and the ⌕ icon), the machine name in the title bar, and the menu item "Run on machine ▸". The status bar keeps `Ready: local`.
- (7) **Not done in this round:** a drawing of **Machines** (operate: status, schedules, jobs, logs, versions) for eveux and evetx; the evetx drawings and README still show the machine selector, the run on a remote machine and the Connect dialog (TD-39); the toolbar in the window code (`code/eveux/src/view/shell.zig`, TD-40).

## D-196 Order of the work by case; visual design leads the interfaces (2026-10-18)

Author decision (2026-10-18): "Feel free to optimize the order for most efficient progress by case. I like to lead by visual design like I progress the evetx."

Read as rules:

- (1) **The ranks of D-194 decide what to take next; the way through one piece of work depends on its kind.** A screen or an interface feature (evetx, eveux, evewp): **visual design first** (a drawing, `code/evetx/design/gen_svg.py` or `code/eveux/design/gen_svg.py`, reviewed by the author) → plan entry (files, machine messages, debt) → code → tests of the logic → spec of the new messages → manual → tutorial. A language or compiler feature: plan → design (a decision with examples) → failing test → compiler → spec → manual → tutorial. A library module: plan (`design/design-libraries.md`) → failing test → native or Eve code → spec page → manual. A bug: failing test, then the fix. A refactor: tests green, move, tests green; no change of behavior; its own commit. An optimization: `bmark.py` before, the change, `bmark.py` after.
- (2) **The drawing is the contract of an interface.** The code follows the drawing; a change of the screen starts as a change of the drawing and of its generator, and the README of the program names the drawing.
- (3) **D-194 stays as the default order** when a piece of work has no kind above.

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

## evedb: the enterprise Eve machine with DuckDB (decisions and questions moved from level 6 on 2026-10-20)

Index of the entries of this section: D-185, Q-062, D-186, Q-063, D-187, D-200, Q-068, D-199, D-203, D-204 (the newest, it settles the conflict between D-186 and D-187).

## D-185 Service mode: `eve -s`, the machine without a user interface, a Windows service or a Linux daemon; evedb detailed design and version 0.1 (2026-10-17)

Author decision (2026-10-17): "Level6 include evedb design and testing. Create a detailed design of evedb and build it properly. We test it. Until now eve was run as cli/repl or eveux graphic interface now include -s to start it as a service (silent mode). In service mode there is no user interface, the machine listen or serve in silent mode as a service on windows or as a daemon in linux. Review Level6 requirements and round up the /tutorial and /spec." Answers to the questions of the session: bare `-s` is the service and `-s file.cfg` keeps naming the configuration file (the service then reads that file); the first slice of evedb to build is "design now, build the 0.1 core".

Read as rules:

- (1) **`eve -s` is the service** (`design/design-service.md` section 17, `spec/library/machine.md` "Service mode"): no prompt, no output, both doors, a log file and a pid file; started from a console it runs in a process of its own and ends silent; started by the Service Control Manager it is the service; with `EVE_SERVICE=foreground` it is the machine in the foreground.

- (2) **`-s file.cfg` alone is the service** reading the file; with a script, a command, `-x` or a machine option it is only the configuration. This changes the old meaning of `eve -s file.cfg` (the REPL with that configuration).

- (3) **evedb has a detailed design and a first build** (`drivers/duckdb/README.md`): the frames of EWP-db 0.1 (a frame has a length, a type and a stream; values with a tag; 13 request and 9 answer types), sessions with leases, transactions recorded in `eve_tx`, `STATUS` for the doubt after a broken commit, the error classes with SQL states, seven fault kinds, the statement log, and the commands `serve`, `create`, `sql`, `describe`, `snapshot`, `reset`, `status`, `stop`. Tests: `python script/evedb_check.py` (a Python client written from the document, 66 checks) and the unit tests of `drivers/duckdb/`.

- (4) **Level 6 requirements reviewed** (`design/feature_map.md`): F-TLS-30 (service mode) added; F-DAT-12 is partial, 0.1 built; the remaining level 6 features are unchanged and open.

Not done in this round, and why: the **Eve driver** `evedb://` (the connection code of `conn.zig` takes SQLite handles; it needs a second backend), `CHANGES`/`APPLIED` and `BATCH`/`CREDIT` (evedb 0.2), `evedb serve -s` (0.2), and a live run of the Service Control Manager form and of the POSIX forms (no administrator rights and no Linux on the test machine; both compile).

## Q-062 The details of D-185: the REPL with a configuration file, the foreground form, privileges and the event log, evedb as a service (2026-10-17)

Proposals and questions for the author.

- **(A) The REPL with a configuration file.** `eve -s file.cfg` is now the service. Proposal: the REPL with a file is `setup file.cfg` at the prompt (it exists); no new option.

  **answer** we start with -s: eve -s file.cfg and this option into eve.

- **(B) The foreground form.** `--foreground` replaces the `EVE_SERVICE=foreground` variable to keep the symmetry with other `eve` options.

  **answer** optio  --foreground is better

- **(C) Privileges and logs.** Run as another user, drop privileges after binding a port, write to the Windows Event Log: in version 0.5, or later?

  **answer** In version 0.6

- **(D) evedb as a service.** `evedb serve -s` in 0.2 with the same three forms, the code shared in the folder `modules/` (answer 2 of the evedb questions)?

- **(E) The log.** A new file at each start today; rotation by size or by day, and a restart policy of the machine itself (the init system restarts it today)?

- **(F) evedb 0.1 questions A to C** are at the end of `drivers/duckdb/README.md`: the prebuilt DuckDB library accepted for 0.1, a token in test mode, the shape of the `evedb://` driver.

**Answer:**

## D-186 evedb behaves like PostgreSQL: the PostgreSQL protocol on port 5432, the Eve driver `postgres://`, a configuration file, `eve -s -db --serve`, stored procedures and triggers in Eve (designed) (2026-10-17)

Author decision (2026-10-17): "Modify the design, so that my remote fake database based on DukeDB behave like a PostgreSQL database. Implement a minimal set that I can use to simulate a driver. Create a driver in eve library for pg protocol and load the driver in eveux to demonstrate a remote connection on port 5432. I can start evedb using evedb.exe or eve -s -db --serve config.file the config file will tell the database name, file location. evedb can be enhanced using eve stored procedures and triggers. Improve evedb design to specify these features."

Read as rules:

- (1) **evedb answers the PostgreSQL protocol** (version 3.0) on port 5432 (`drivers/duckdb/README.md` section 5A): startup, logins trust, password and md5, the simple and the extended query protocol, transactions with the aborted state, `SHOW`, errors with SQL states, rows in the text format with the type numbers of PostgreSQL; DuckDB answers the SQL. The EWP-db frames stay on a second port, the control port.

- (2) **The Eve driver for PostgreSQL** is part of the database layer of `eve` (`drivers/duckdb/src/pgclient.zig`, `pgdriver.zig`, section 5B): `postgres://` URLs, logins trust, password, md5 and SCRAM-SHA-256, `execute!`, `query!`, `query_one!`, `script`, `close`, jobs; it works with evedb and with PostgreSQL.

- (3) **The configuration file** of evedb (section 9) names the PostgreSQL port, the login, the test mode, the control port and its token, and the databases (`database "shop" = "data/shop.duckdb"`).

- (4) **Three ways to start:** `evedb serve --config evedb.cfg`, `eve db serve evedb.cfg` (foreground), `eve -s -db --serve evedb.cfg` (service, silent; `-db --serve` is read as the part word `db` and its command `serve`).

- (5) **eveux is not built**, so the demonstration is the smallest page of the machine (`drivers/duckdb/demo/web/index.html`), which sends Eve scripts to `vm.run`; they reach evedb on port 5432 through the driver.

- (6) **Stored procedures and triggers in Eve** are designed (section 12, version 0.3): evedb hosts an Eve machine (`eve --stdio`) for the modules of `proc/`; `CALL`, scalar `sql function`s registered in DuckDB per data chunk, a connection back into the caller's transaction, and `CREATE TRIGGER` (a subset of PostgreSQL's) emulated with `RETURNING`, temporary tables and savepoints.

Tests: `python script/pg_check.py` (32 checks: psycopg2, pg8000, the Eve driver, the start forms), `test/level6/f01_pg_driver` (the first test of level 6), the unit tests of `drivers/duckdb/` and of the root build (the SCRAM example of RFC 7677, the URL, the configuration file, the statement splitter, the command tags).

## Q-063 The details of D-186 (2026-10-17)

Proposals and questions for the author; they are also at the end of `drivers/duckdb/README.md`.

- **(a) The control port.** Keep EWP-db as the control port of the tests, or move the control to SQL on the PostgreSQL port (`pragma eve_stop`, `select * from eve_status()`) and drop EWP-db? Proposal: keep it until the change sets are decided.

- **(b) `select version()`.** Answer `PostgreSQL 16.4 (evedb 0.2 on DuckDB v1.5.6)` for tools that test the word PostgreSQL? Proposal: yes.

- **(c) Names of section 12** (open again: D-187 is reverted, D-203). `database.caller()` (the connection of a procedure back to the calling session), `raise … with state "P0001"`, the keys `procedures`, `eve`, `procedure_timeout`.

- **(d) One Eve host per server** (answered by D-203: evedb is an Eve machine).

- **(e) The ORM on PostgreSQL.** `table` declarations and tracked records on a `postgres://` connection: in 0.5 (they need the change sets of `design-database-core.md` §7 sent as SQL), or later?

- **(f) TLS** for the driver and for evedb, needed before eveux?

**Answer:**

## D-187 SQLite in eve, DuckDB in evedb; column batches on the native protocol and the driver `evedb://`; no triggers or procedures in evedb (2026-10-18)

**Status: reverted by the author on 2026-10-20 (D-203). Kept here as the record; none of its rules stands.**

Author decision (2026-10-18), after reading `backlog/evedb-ideas.md` and the review of it: "I want maximum performance protocol between evedb and eve. If evedb is running the DuckDB performance must be better for OLAP operations or masive data transfers and data caches. … Make it explicit how the files for DuckDB will look like and how we will acess/create DuckDB databases. I understand that triggers are no good and is better to have Eve communicating with the dump database for better bulk operations and simplified design." Then: "Ok, go ahead" with the three steps proposed (record the decision, rewrite the design, build phase 1 and measure).

Read as rules:

- (1) **SQLite stays in every `eve`** for its own state (the core database, job state, small caches, small local data); **DuckDB lives only in evedb**, which owns the DuckDB files: nothing else opens them (`drivers/duckdb/README.md` sections 3A and 3B, with the layout of the files and how a database is made and reached).

- (2) **The fast path between eve and evedb is the native protocol with column batches** (section 5.5): `QUERYB` answers a schema, one batch per DuckDB data chunk and an end; `LOAD` sends a schema, batches and an end, pipelined, into DuckDB's Appender. A batch is column by column: a validity bitmap and the values (1 or 8 bytes, or offsets and bytes for text), the layout of DuckDB's vectors and of Eve's `Memory` tables, so a fixed-width column is copied whole.

- (3) **The driver `evedb://`** (section 5C): `execute!`, `query!`, `query_one!`, `script`, jobs, typed parameters bound by DuckDB, and `Memory.store` / `Memory.load` over the batches.

- (4) **The PostgreSQL protocol stays** for other tools (D-186).

- (5) **Shared memory only after a benchmark asks for it**: the benchmark (section 5.6) shows the socket is not the bottleneck, so it is not built.

- (6) **No triggers and no stored procedures in evedb** (section 12): the logic is in Eve jobs working on sets, reusable SQL is a DuckDB macro; the design of D-186 point 6 is withdrawn.

Measured (section 5.6, 1,000,000 rows, ReleaseSafe builds): column batches into a `Memory` table 0.23 s (4.4 million rows per second, 3.4 times a local SQLite file); records about 0.6 to 0.7 million rows per second on every protocol (the cost of objects); a group-by in DuckDB 9 ms against 0.5 s in SQLite; bulk load 1.5 million rows per second (Appender) against 1.0 million (SQLite).

Tests: `script/evedb_check.py` (75 checks, the batches included), `test/level6/f02_evedb_columnar`, `script/evedb_bench.py`, the unit tests (`batch.zig`, the URL of `evedb://`).

## D-200 Drivers: the DuckDB server stays an executable with DuckDB embedded, launched by eve; a driver table; documentation of every driver (2026-10-19)

**Status: superseded in part by D-203** (evedb is the Eve machine with DuckDB, not a server that has nothing to do with Eve; `duckdb.dll` ships for now; the static embedding waits for a way to link it). The driver table, the documentation of every driver and the root license stand.

Author answers to Q-068 points 2 and 6 and to `design/design-drivers.md` (2026-10-19). Settled:

- **DuckDB stays a server.** The program is `evedb.exe`; `eve` launches it (alternative A of Q-068 6: `eve db serve evedb.cfg` and `eve -s -db --serve evedb.cfg` stay). The configuration file tells the server where to store the files and which options to use.
- **DuckDB is embedded in `evedb.exe`.** "Instead of using DuckDB.dll we should embed DuckDB using zig bindings into evedb.exe." The binding `duckdb.zig` stays; the library is linked **statically**, so the zip no longer needs `duckdb.dll` (35 MB beside the program). How (the prebuilt static libraries, or the amalgamation compiled by Zig) is not known yet: stage S8.10a starts with a spike (does it link, how long does it build, how big is the program) and reports before the change is made. Until then the DLL ships (D-199 4).
- **The root license applies to `drivers/`.** No `LICENSE` file in `drivers/` (D-199 3). The root `README.md` names `drivers/` in the sentence about the license of the code, and the Licensed Work line of `code/LICENSE` names it (S8.5).
- **Every driver is documented.** One manual page for each driver: the client drivers `sqlite://`, `postgres://`, `evedb://` (the URL, the options, the types, what is supported) and the DuckDB server (the commands, the configuration file). Written in S8.10 and kept with the driver.
- **A driver table is approved** ("This is good, add to plan"): one struct of functions per driver, chosen by the URL scheme, in place of the `if` chains of `conn.zig`. Stage S8.4a.
- **The recommendation of `design-drivers.md` is accepted:** client drivers are embedded in `evevm`, the DuckDB engine is a server, no Eve driver DLLs.

## D-203 evedb is the Eve machine with DuckDB inside; D-187 is reverted; D-186 stands; all evedb decisions are level 7 (2026-10-20)

Author decision (2026-10-20): "I want to revert D-187 and resolve the conflict to D-186. When we compile evedb, it will include Eve parts to support Eve procedures, functions and business logic inside. That means evedb behaves like evevm, it can be used to serve a web portal and is a database embedded in a monolithic structure. It is not necessary to spin evevm and evedb, because evedb has the same code as evevm plus the database DuckDB. evedb is the enterprise version of Eve, that runs as a server, while evevm is the light version of Eve that is usually running as a client. For now, because Zig does not have a proper ABI, we use and deploy duckdb.dll with evedb in the release dist folder. Move evedb to level 7, all decisions and questions."

The author's notes in the review list of level 6 agree: D-187 "reverted", D-186 "approved", D-198 "modified"; Q-063: "evedb will respond like a PostgreSQL database on the same protocol but will also respond on the http protocol and can listen to other Eve commands on the IPC protocol. It all depends on how the user configures evedb, it is like a swiss knife, can do this or that."; Q-062: "eve -s will start evedb, that is the silent service and not evevm, because evedb has evevm functionality + enterprise OLAP database functionality."

Read as rules:

- (1) **D-187 is reverted.** Its six rules no longer stand as decisions: the split "SQLite in eve, DuckDB only in evedb", the column batches as the fast path, the driver `evedb://` as designed there, "shared memory only after a benchmark", and above all "no triggers and no stored procedures in evedb". What was built under it stays in the tree until the author says to keep or remove it (TD-52).

- (2) **D-186 stands** (approved), including point (6): **stored procedures and triggers in Eve**, evedb hosts the Eve machine. The points of Q-063 that D-187 had closed (c: names of the procedures, triggers and `database.caller()`; d: one Eve host per server) are open again, and (d) is answered by (3).

- (3) **evedb is one program with the code of evevm plus DuckDB** (monolithic). It runs Eve procedures, functions and business logic inside, and can serve a web portal (evewp, level 7); no second process for the Eve part. It answers the PostgreSQL protocol (D-186), HTTP and the IPC commands of the Eve machine, as configured. `eve -s` starts evedb (Q-062).

- (4) **Two editions of Eve:** evedb is the enterprise edition, a server with the OLAP database; evevm is the light edition, usually a client (SQLite inside for its own state and for `sql function`, D-166).

- (5) **DuckDB ships as `duckdb.dll` beside evedb in the dist folder, for now**, because Zig has no stable ABI to link the library statically. This replaces the plan of D-200 to embed DuckDB in `evedb.exe` (stage S8.10a) until a way to link it exists; the DLL stays in the zip (D-199 4).

- (6) **Superseded in part:** D-198 (a) ("the DuckDB server contains DuckDB only, has nothing to do with Eve, behaves like a driver, is renamed `drivers/duckdb`") and D-200 ("DuckDB stays a server executable launched by eve"). The folder `drivers/duckdb/` keeps its name until the author decides on the layout of evedb.

- (7) **Level 7.** Every decision and question about evedb belongs to level 7 and is in this file: D-185, Q-062, D-186, Q-063, D-187 (reverted), D-200 (in part), D-203.

Not done by this decision: `drivers/duckdb/README.md` (sections 3A, 3B, 5.5 to 5.6, 12 and the architecture) and `design/design-drivers.md` still describe D-187 and D-198 (a); TD-52.

## Q-068 Points the answers to Q-067 leave open (2026-10-19, answered → D-199, D-200)

Each point is needed by one stage only (in brackets); the stages before it can go on.

1. **(c) The editors include `evecp`** (S8.6 to S8.8). Confirm: yes (the request said so; the answer lines skipped it). 
**answer** yes the text editor and the ide eveux will have the compiler.
2. **The program of the DuckDB driver** (S8.4). The folder is `drivers/duckdb`. The program is `evedb.exe` today, and the tests, the scripts and the manual use that name. 
**answer** keep it like it is until I figer out if a driver is executable or a dll. Where is the driver?
**Reply (model):** There are two things with the name evedb. (1) The **client side**: the code that makes `database.connect("evedb://…")` and `"postgres://…"` work (`ewpdriver.zig`, `pgdriver.zig`, now in `drivers/duckdb/src/`). It is already compiled into `eve.exe`; S8.2 moves it to `code/evevm/src/db/`. 
(2) The **server**: `bin/evedb.exe`, a separate program that loads `bin/duckdb.dll` (35 MB) and listens on ports. `eve.exe` never loads the DLL; it talks to the server over a socket.
Three ways to have DuckDB: **executable server** (today: DuckDB stays out of `eve.exe`; many clients; the PostgreSQL face; faults for tests; cost: a second process), **embedded** (`eve.exe` loads DuckDB: no second process, the fastest, but `eve.exe` needs the DLL, and it reverses D-187 "DuckDB lives only in evedb"), **plug-in DLL** loaded by `eve` at run time (small `eve.exe`; Zig offers only the C ABI for it, and the project switched native extension loading off for SQLite on purpose). Stages S8.1 to S8.4 do not depend on the choice, and S8.5 only moves the folder. Kept as it is, as you say. The question "DLL files or embedded?" is analysed in [design-drivers.md](../design-drivers.md), with a recommendation: client drivers embedded in `evevm`, the DuckDB engine a server for now, no Eve plug-in DLLs.

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

## D-204 The client is levels 1 to 6, the server starts at level 7; the pieces of D-187 are kept and moved to level 7 with their tests (2026-10-20)

Author decision (2026-10-20): "Yes, move the D-187 pieces to level 7, we preserve the code and explain everything, including the tests; D-199 and Q-068 too. I figured out that evedb is the server and evevm is the client. We stay with the client in versions 1 to 6 and we move to the server part starting with level 7."

Read as rules:

- (1) **evevm (`eve`) is the client, evedb is the server.** Levels 1 to 6 build and test the client: the language, the data layer with SQLite, the Eve machine that other machines control, the client drivers (`sqlite://`, `postgres://`, `evedb://`). The server part, evedb as the Eve machine with DuckDB inside (D-203), starts at level 7.

- (2) **The built pieces of D-187 stay in the tree, unchanged,** and belong to level 7: `drivers/duckdb/src/batch.zig` and the `QUERYB` and `LOAD` batches of the native protocol, the driver `evedb://` with `Memory.store` and `Memory.load` (`code/evevm/src/db/`), `script/evedb_check.py` (75 checks), `script/evedb_bench.py`, the measures of section 5.6 of `drivers/duckdb/README.md`. Their rules are no longer decisions in the sense of D-187; they are the working fast path and the base of the server.

- (3) **The tests moved from level 6 to level 7 and were renamed** (test names of level 7 start with `g`): `test/level6/f01_pg_driver` is now `test/level7/g01_pg_driver` (an Eve script over `postgres://` against `eve db serve evedb.cfg`, md5, a job that rolls back), and `test/level6/f02_evedb_columnar` is now `test/level7/g02_evedb_columnar` (typed parameters, records, a job and the column batches over `evedb://`). Both start evedb, so they are server tests. Run them with `python script/runtest.py g01` and `g02`.

- (4) **The feature F-DAT-12 (evedb)** moved from the level 5 section to the level 7 section of `design/feature_map.md`; its `Tests` line is `level7: g01 g02`. `F-TLS-30` (service mode, `eve -s`) stays in level 6 as the machine; what `eve -s` starts as the enterprise edition is D-203.

- (5) **D-199 and Q-068** (the answers about the editors, the license, the server in `bin/`, the protocol module) moved to level 7 with the other evedb entries. The author's notes on them (quoted): D-199: It looks like the drivers are actually components used by evevm and evedb, should be moved into evecm then? If they are eve code, no, if they are zig or c code, yes.

- (6) **Explained where it is used:** `drivers/duckdb/README.md` (status paragraph), `spec/library/database.md` (the two driver paragraphs say level 7), `test/level7/readme.md`, TD-52.
