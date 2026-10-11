# Decisions, level 6: the Eve machine and the server (version 0.5)

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. Ids are shared by all the decision files ([level 1](decision_level1.md), [2](decision_level2.md), [3](decision_level3.md), [4](decision_level4.md), [5](decision_level5.md), 6, [7](decision_level7.md)); the list of levels is in [decision_level3.md](decision_level3.md) and [version_map.md](version_map.md).

## Scope

One Eve machine, started locally or remotely: set up from its folder, controlled from scripts and from other machines, serving HTTP with `service` scripts, scheduling drivers, and offering its commands to AI assistants as an MCP server. A client/server application is two projects, a client and a server. Tests: `test/level6`, prefix `f`; a test is a pair of projects (client and server) started on `localhost` with different ports.

Features: F-TLS-11 to F-TLS-15, F-STR-08, F-NET-02 to F-NET-07 (F-NET-07: a login per remote machine, single sign-on, the keyring, D-155), F-VM-08, F-LIB-10, F-SPEC-06.

Decisions: **D-083** (below): one machine and one mode, `-x`, `-c`, `-r`, `-u`, `send`, `--setup` and the machine folder, identity domain + port, ports 4042 and 8042, sessions and driver memory spaces (`load`, `dismiss`), `serve`, `service` and `route`, `panic` on a listening machine, the API for AI. Design and reasons: [design-service.md](design-service.md). Tutorial: server.html. Related: D-081 (exit codes, run log).

## Draft features

1. **Removal of command files.** `.vmc`, `-i` and the old "serve mode" (D-063) go away once `--listen` and `eve -c` work; `test/smoke` and `script/workflow.py` move to `eve -c`.
2. **Remote scheduler.** `schedule "<driver>" at "02:00" every day` in `eve.cfg` of a listening machine; retries and alerts on failure.
3. **EWP, the Eve Wire Protocol**, on port 4042 after the line protocol: remote `apply … at <machine> within <time>;`, data streams with credit, parallel streams that restart after a broken connection (review RNW-R04).
4. **Capabilities.** The resources a project may use on a machine (folders, hosts, databases, shell), listed in its configuration and checked when code is uploaded (review RNW-R08).
5. **Request and Response classes** of the `http` module, used by routes.
6. **System variables** of the machine to add to the register (D-071): `$EVE_NAME`, `$EVE_DOMAIN`, `$EVE_PORT`, `$EVE_HTTP_PORT`, `$EVE_WEB`, `$EVE_TOKEN`.

## Open questions

- Is the remote scheduler part of version 0.5, or later?
- Does `deploy` exist as a command of its own, or is uploading every file of a project with `-u` enough?

- Q-028 Networking and protocols [open]
- Q-047 Eve RAD Workbench (eveux): program, toolkit and the commands it needs from the machine (answered in part: D-154, D-155) [open]
- D-155 One local machine, many remote machines: a login per machine, single sign-on, the keyring of the system
- Q-048 Machine login: the details of D-155 [open]
- D-160 Eve is project oriented: the command `new project <folder>` and the project folders
- D-083 The Eve machine: command channels, setup, remote control, serve, services, API for AI
## D-083 The Eve machine: command channels, setup, remote control, serve, services, API for AI (2026-10-05)
Author decisions, reached in the discussion of `plan/design-service.md` (2026-10-05), which keeps the details and the reasons. Taught in the new tutorial page server.html (topic 19, Compiler becomes 20), marked "planned, version 0.5". Not implemented: VM work waits (D-075).
- **One machine, one mode.** `eve` starts locally or remotely; what it does depends on its commands and its configuration.
- **Commands.** `eve -x file.eve` parses and executes a script; `eve -c "<command>"` (`--command`) sends one command to a running machine and prints its answer; `-r <machine>` (`--remote`) names a remote machine by address or by a name of the configuration; `eve -u <file>` (`--upload`) sends a source file that the receiving machine compiles under its own rules; at the prompt, `send <machine> "<command>"`. Command files (`.vmc`, `-i`, the "serve mode" of D-063) are scheduled for removal; scripts drive a machine with `eve -c`.
- **Setup.** `eve --setup <folder>` (`-s`) chooses the machine of a folder, or creates it (`eve.cfg`, `web/`, `out/`, `data/`, `lib/`, `asp/`, named after the folder, free ports) when it does not exist; `setup` at the prompt or with `-c` reads the configuration again. Without a configuration `eve` uses built-in defaults. A machine folder is a project folder: one machine per project; a client/server application is two projects (client and server) that can live in one repository, README at the root.
- **Identity.** Domain + port (`$EVE_DOMAIN:$EVE_PORT`); `$EVE_NAME` is the label. Starting on a taken address is an error. The checksum of the configuration is kept outside the file (`out/<name>.sum`); `setup` applies changes that keep the identity.
- **Ports.** 4042 for commands, uploads and later the data protocol (`$EVE_PORT`); 8042 for HTML (`$EVE_HTTP_PORT`).
- **Sessions.** One machine, one state; parallel sessions are two machines. Each driver has its own driver memory space (DMS): `load` creates it, `dismiss` frees it (replaces the planned `clear`); `run` of a driver that is not loaded uses a temporary DMS.
- **Serve.** `serve` starts HTTP on `$EVE_HTTP_PORT` with the pages of the web folder and the routes of `service` scripts; `serve stop` ends it.
- **Services and routes.** A `service` script (a fourth kind of script, shaped like a module) declares routes with the keyword `route`: one line, `route get "/orders" apply list_orders;`, or a block, `route name(req: Request, @res: Response) on <method> "<path>" is … end name;`, for every HTTP method (get, post, put, patch, delete).
- **panic.** At the prompt it returns to the prompt; with `eve -x` it ends the process (exit code 1); on a listening machine it ends the request or the job and the machine goes on listening, while `eve -c` ends with exit code 1.
- **API for AI.** `eve --api` is an MCP server; every command of the machine is a tool; an AI has the rights of a person at the prompt.
- New system variables to add to the register (D-071) when specified: `$EVE_NAME`, `$EVE_DOMAIN`, `$EVE_PORT`, `$EVE_HTTP_PORT`, `$EVE_WEB`, `$EVE_TOKEN`.

## Q-028 Networking and protocols (2026-10-06)
Moved from level 7 on 2026-10-08: the Eve Wire Protocol, sockets and the server are level 6 (F-NET-02 to F-NET-06, draft feature 3); the HTTP client is level 5 (F-NET-01).
The pages networking.html and protocols.html collect ideas that are not designed: the layers (names, connection, protocol, data), the type `Url`, the module `net` and `http`, capabilities in the project file, `Secret`, the Eve Wire Protocol (frames HELLO, APPLY, RESULT, ERROR, BATCH, CREDIT, CANCEL, PING, CLOSE; CBOR payloads; resume by batch number), HTTP/1.1 and HTTP/2, WebSocket for browsers. Questions: do sockets exist in the language or only protocols? Is EWP wanted, or only HTTP with JSON? Which level takes the HTTP client (3) and which the server (6)? Names of the error classes of the network?

**Answer:**

## Q-047 Eve RAD Workbench (eveux): program, toolkit and the commands it needs from the machine (answered in part: D-154, D-155)
Author request (2026-10-10): a full RAD workbench in the folder `eveux/`, in plain JavaScript and plain CSS with a Zig web toolkit, presented in phase 6 of the tutorial: menu, login form, user registration, admin user, database object tree, code editor, command window, file dialog to load and import files, job scheduler and browser, log inspector "similar to Jenkins or better", direct SQL from the command line with the result in a WYSIWYG grid, Help and About with the version, syntax colors for HTML, JSON, XML, Eve and SQL, scripts run from the command line, step-by-step run, variable inspector and watch window. Design: [eveux/README.md](../eveux/README.md); tutorial: eveux.html; features F-TLS-19 to F-TLS-22.
Proposals, each with its question in the design file: (1) a separate Zig program `bin/eveux.exe` on port 8046 that talks to Eve machines on their command port, not a folder served by `eve serve`; (2) plain JavaScript modules with JSDoc types and no build step, not TypeScript compiled by `tsc`; (3) a *watched run* on the line protocol of the command port, so output, logs and debugger events stream to the Workbench before EWP exists; (4) our own toolkit `modules/zweb/` on `std.http`, shared with `eve serve` and evedb; (5) new machine commands for files (`files`, `read`, `save`, `delete`); (6) SQL that changes data runs in a transaction with Commit and Rollback buttons; (7) `let` on a variable while halted in debug mode; (8) stepping one parallel task holds the others. New debugger commands of the machine, so that the REPL and `eve -c` get them too: `step into`, `step out`, `break <file>:<line> [if <condition>]`, `locals`, `stack` (F-TLS-04).

**Answer:** (2026-10-10, in part) "We use Eve to build eveux as ultimate test of Eve capability and a stress test. Therefore is in level 7 that is actually last level. Zig is used for making a full capable eve virtual machine evevm that can handle from a local instance multiple remote evevm machines." Proposals (1) and (4) fall away: eveux is an Eve project run by the local machine, with no Zig program and no Zig toolkit of its own (D-154); the login to remote machines is D-155. The other proposals stay open, as questions 1 to 10 of `eveux/README.md`.

## D-155 One local machine, many remote machines: a login per machine, single sign-on, the keyring of the system (2026-10-10)
Author decision, given while reviewing eveux: "Zig is used for making a full capable eve virtual machine evevm that can handle from a local instance multiple remote evevm machines. Different connection credentials allow login to a remote machine using single signon and local credential keyring for windows or linux to store credentials after first login." (1) `evevm` is the full machine: from one local instance it works with many remote machines at once, one connection and one session per remote machine. (2) Each remote machine is entered with its own credentials; a person logs in by single sign-on. (3) After the first login the local machine keeps the credentials in the keyring of the operating system: Windows Credential Manager, the Secret Service of Linux. Design: `plan/design-service.md` §15. Feature F-NET-07 (Version 0.5). The proposals of the details are Q-048.

## Q-048 Machine login: the details of D-155 (2026-10-10)
Proposals in `plan/design-service.md` §15, for the author: (a) single sign-on by **OpenID Connect** (authorization code with PKCE in the browser, device code without a browser), so Entra ID, Keycloak, Okta and Google work; Kerberos and the integrated login of a Windows domain later, or also in the first version? (b) The keyring holds the **renewal token** that the remote machine gives back, never the password nor the token of the provider; a renewal token expires after 30 days without use. (c) **Without a keyring** (a Linux server with no desktop session): ask at each start, or read a machine token from the environment; never a plain file. Or allow an encrypted file? (d) **Users and roles** live in the Eve database of each listening machine (`viewer`, `operator`, `developer`, `admin`), with the registration setting `$EVE_REGISTRATION` (`closed`, `approval`, `open`) and a mapping of provider groups to roles. (e) New commands of the machine: `login`, `logout`, `forget`, `whoami`, `user add`, `user role`, `session end`; the option `--login` of `eve -c`. (f) The method of each remote machine is written in the configuration of the local machine: `machine prod at "etl1.example.com:4042" login sso`. (g) macOS Keychain in the same version, or later?

**Answer:**

## D-160 Eve is project oriented: the command `new project <folder>` and the project folders (2026-10-11)
Author decision: "Eve is project oriented. When you start using Eve you must install, then you create and initialize one or more projects. To start a project you install Git and then initialize it with a command: `new project <folder>`. The folder must be empty, or if it is not present it is created. The command creates the Eve folders of the project: {asp, doc, lib, db, web, src, log}. A .gitignore template is necessary for Eve projects: it excludes the .db files, so we do not version database files from `db/` nor from `log/`."

Recorded as feature F-TLS-23; not implemented yet. Points to settle when it is built (proposals, for the author): (a) an existing non-empty folder is an error, nothing is written; (b) the command also runs `git init` when Git is found, and says so when it is not; (c) the template excludes `db/*.db` and `log/*.db` (with the usual `-wal`, `-shm` and `-journal` companions of SQLite, D-156) and keeps each empty folder with a `.gitkeep`; (d) the core database of D-156 is created in `db/` on the first run, not by the command.
