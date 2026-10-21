# Decisions, level 7: web, HTML and WebAssembly (version 0.6)

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. Ids are shared by all the decision files ([level 1](level1.md), [2](level2.md), [3](level3.md), [4](level4.md), [5](level5.md), [6](level6.md), 7); the list of levels is in [decision_level3.md](level3.md) and spec/features.

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

- D-154 eveux, the RAD Workbench, is written in Eve: the final test of the language, in level 7

## Q-027 Templates (2026-10-06, answered 2026-10-21 → D-209)
The page templates.html teaches string templates (today) and proposes HTML templates: files `.htmt` or literals, `{expr}` escaped by context (text, attribute, URL, script), the type `HTML`, components as functions that return `HTML`, the module `html` with `html.render` and `html.write`. Questions: files, literals or both? The extension and the module name? Loops and conditions inside a template (`{for o in orders}`)? Is `HTML` required by the functions that send a page?

**Answer:**
Template files contain simple HTML and {var} can inject in it a whole HTML fragmend, if var is a HTML fragment it can represent a table for example. No need for complexity. `{for o in orders}` is not a feature I want. Embeded templates are Text type. That is a literal. In text literals we have {} that is same kind of template. 


## Q-028 Networking and protocols (2026-10-06, answered 2026-10-21 → D-208)

Moved from level 7 on 2026-10-08: the Eve Wire Protocol, sockets and the server are level 6 (F-NET-02 to F-NET-06, draft feature 3); the HTTP client is level 5 (F-NET-01).

The pages networking.html and protocols.html collect ideas that are not designed: the layers (names, connection, protocol, data), the type `Url`, the module `net` and `http`, capabilities in the project file, `Secret`, the Eve Wire Protocol (frames HELLO, APPLY, RESULT, ERROR, BATCH, CREDIT, CANCEL, PING, CLOSE; CBOR payloads; resume by batch number), HTTP/1.1 and HTTP/2, WebSocket for browsers. Questions: do sockets exist in the language or only protocols? Is EWP wanted, or only HTTP with JSON? Which level takes the HTTP client (3) and which the server (6)? Names of the error classes of the network?

**Answer:**
Yes, HTTP client should be Level5 and Server Level6. Follow the design and improve or test to confirm the specification & implementation.


## Q-047 Eve RAD Workbench (eveux): program, toolkit and the commands it needs from the machine (answered in part: D-154, D-155)

Author request (2026-10-10): a full RAD workbench in the folder `code/eveux/` Design: [design/components/eveux/README.md](../components/eveux/README.md); tutorial: eveux.html; features F-TLS-19 to F-TLS-22.

  **Answer:** (2026-10-10, in part) "We use Eve to build eveux as ultimate test of Eve capability and a stress test. Details in: `code/eveux/README.md`.

## evedb: the enterprise Eve machine with DuckDB (decisions and questions moved from level 6 on 2026-10-20)

Index of the entries of this section: D-185, Q-062, D-186, Q-063, D-187, D-200, Q-068, D-199, D-203, D-204 (the newest, it settles the conflict between D-186 and D-187).

## Q-063 The details of D-186 (2026-10-17)

Proposals and questions for the author; they are also at the end of `drivers/duckdb/README.md`.

- **(a) The control port.** Keep EWP-db as the control port of the tests, or move the control to SQL on the PostgreSQL port (`pragma eve_stop`, `select * from eve_status()`) and drop EWP-db? Proposal: keep it until the change sets are decided.

- **(b) `select version()`.** Answer `PostgreSQL 16.4 (evedb 0.2 on DuckDB v1.5.6)` for tools that test the word PostgreSQL? Proposal: yes.

- **(c) Names of section 12** (open again: D-187 is reverted, D-203). `database.caller()` (the connection of a procedure back to the calling session), `raise … with state "P0001"`, the keys `procedures`, `eve`, `procedure_timeout`.

- **(d) One Eve host per server** (answered by D-203: evedb is an Eve machine).

- **(e) The ORM on PostgreSQL.** `table` declarations and tracked records on a `postgres://` connection: in 0.5 (they need the change sets of `design-database-core.md` §7 sent as SQL), or later?

- **(f) TLS** for the driver and for evedb, needed before eveux?

**Answer:**

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

- (4) **The feature F-DAT-12 (evedb)** moved from the level 5 section to the level 7 section of `spec/features/`; its `Tests` line is `level7: g01 g02`. `F-TLS-30` (service mode, `eve -s`) stays in level 6 as the machine; what `eve -s` starts as the enterprise edition is D-203.

- (5) **D-199 and Q-068** (the answers about the editors, the license, the server in `bin/`, the protocol module) moved to level 7 with the other evedb entries. The author's notes on them (quoted): D-199: It looks like the drivers are actually components used by evevm and evedb, should be moved into evecm then? If they are eve code, no, if they are zig or c code, yes.

- (6) **Explained where it is used:** `drivers/duckdb/README.md` (status paragraph), `spec/library/database.md` (the two driver paragraphs say level 7), `test/level7/readme.md`, TD-52.

## D-208 Answer to Q-028: the HTTP client is level 5, the server level 6 (2026-10-21)
Author decision (2026-10-21): "Yes, HTTP client should be Level 5 and Server Level 6. Follow the design and improve or test to confirm the specification & implementation." This is how the features already stand (F-NET-01 in level 5; the machine and its HTTP door in level 6; the evedb server of D-204 in level 7). Work: step S15.52 builds the client and tests it against the local test server; step S6.x of `phase-6-machine.md` confirms the server against the spec. The Eve Wire Protocol frames (HELLO, APPLY, RESULT, BATCH, ...) and WebSocket stay as designed in `spec/library/rpc.md` and `net.md`; nothing new is decided about them.

## D-209 Answer to Q-027: a template is a text with `{var}`, no loops (2026-10-21)
Author decision (2026-10-21): "Template files contain simple HTML and {var} can inject in it a whole HTML fragment, if var is a HTML fragment it can represent a table for example. No need for complexity. `{for o in orders}` is not a feature I want. Embedded templates are Text type. That is a literal. In text literals we have {} that is the same kind of template."

Read as rules: (1) a template file is a plain text file (HTML) with `{name}` holes; a template literal in Eve code is an ordinary text literal, whose `{expr}` holes already exist, so a template is a `Text`; (2) a value may be a whole fragment (a table built before and inserted); (3) no loops and no conditions inside a template: the program builds the fragment in Eve and inserts it; (4) there is no separate language, no `.htmt` syntax, no component functions and no type `HTML` unless a later decision asks for them. Open for level 7 (`phase-7-web.md`): whether `{x}` escapes text by default and how a fragment is marked as already safe; the author has not said.

