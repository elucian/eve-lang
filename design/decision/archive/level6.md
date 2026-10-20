# Archive of level6.md: settled entries, full text

## D-083 The Eve machine: command channels, setup, remote control, serve, services, API for AI (2026-10-05)

Author decisions, reached in the discussion of `design/design-service.md` (2026-10-05), which keeps the details and the reasons. Taught in the new tutorial page server.html (topic 19, Compiler becomes 20), marked "planned, version 0.5". Not implemented: VM work waits (D-075).

- **One machine, one mode.** `eve` starts locally or remotely; what it does depends on its commands and its configuration.

- **Commands.** `eve -x file.eve` parses and executes a script; `eve -c "<command>"` (`--command`) sends one command to a running machine and prints its answer; `-rem <machine>` (`--remote`) names a remote machine by address or by a name of the configuration; `eve -u <file>` (`--upload`) sends a source file that the receiving machine compiles under its own rules; at the prompt, `send <machine> "<command>"`. Command files (`.vmc`, `-i`, the "serve mode" of D-063) are scheduled for removal; scripts drive a machine with `eve -c`.

- **Setup.** `eve --setup <folder>` (`-s`) chooses the machine of a folder, or creates it (`eve.cfg`, `web/`, `out/`, `data/`, `lib/`, `asp/`, named after the folder, free ports) when it does not exist; `setup` at the prompt or with `-c` reads the configuration again. Without a configuration `eve` uses built-in defaults. A machine folder is a project folder: one machine per project; a client/server application is two projects (client and server) that can live in one repository, README at the root.

- **Identity.** Domain + port (`$EVE_DOMAIN:$EVE_PORT`); `$EVE_NAME` is the label. Starting on a taken address is an error. The checksum of the configuration is kept outside the file (`out/<name>.sum`); `setup` applies changes that keep the identity.

- **Ports.** 4042 for commands, uploads and later the data protocol (`$EVE_PORT`); 8042 for HTML (`$EVE_HTTP_PORT`).

- **Sessions.** One machine, one state; parallel sessions are two machines. Each driver has its own driver memory space (DMS): `load` creates it, `dismiss` frees it (replaces the planned `clear`); `run` of a driver that is not loaded uses a temporary DMS.

- **Serve.** `serve` starts HTTP on `$EVE_HTTP_PORT` with the pages of the web folder and the routes of `service` scripts; `serve stop` ends it.

- **Services and routes.** A `service` script (a fourth kind of script, shaped like a module) declares routes with the keyword `route`: one line, `route get "/orders" apply list_orders;`, or a block, `route name(req: Request, @res: Response) on <method> "<path>" is … end name;`, for every HTTP method (get, post, put, patch, delete).

- **panic.** At the prompt it returns to the prompt; with `eve -x` it ends the process (exit code 1); on a listening machine it ends the request or the job and the machine goes on listening, while `eve -c` ends with exit code 1.

- **API for AI.** `eve --api` is an MCP server; every command of the machine is a tool; an AI has the rights of a person at the prompt.

- New system variables to add to the register (D-071) when specified: `$EVE_NAME`, `$EVE_DOMAIN`, `$EVE_PORT`, `$EVE_HTTP_PORT`, `$EVE_WEB`, `$EVE_TOKEN`.

## D-155 One local machine, many remote machines: a login per machine, single sign-on, the keyring of the system (2026-10-10)

Author decision, given while reviewing eveux: "Zig is used for making a full capable eve virtual machine evevm that can handle from a local instance multiple remote evevm machines. Different connection credentials allow login to a remote machine using single signon and local credential keyring for windows or linux to store credentials after first login." (1) `evevm` is the full machine: from one local instance it works with many remote machines at once, one connection and one session per remote machine. (2) Each remote machine is entered with its own credentials; a person logs in by single sign-on. (3) After the first login the local machine keeps the credentials in the keyring of the operating system: Windows Credential Manager, the Secret Service of Linux. Design: `design/design-service.md` §15. Feature F-NET-07 (Version 0.5). The proposals of the details are Q-048.

## D-160 Eve is project oriented: the command `new project <folder>` and the project folders (2026-10-11)

Author decision: "Eve is project oriented. When you start using Eve you must install, then you create and initialize one or more projects. To start a project you install Git and then initialize it with a command: `new project <folder>`. The folder must be empty, or if it is not present it is created. The command creates the Eve folders of the project: {asp, doc, lib, db, web, src, log}. A .gitignore template is necessary for Eve projects: it excludes the .db files, so we do not version database files from `db/` nor from `log/`."

Recorded as feature F-TLS-23; not implemented yet. Points to settle when it is built (proposals, for the author):

- (a) an existing non-empty folder is an error, nothing is written;

- (b) the command also runs `git init` when Git is found, and says so when it is not;

- (c) the template excludes `db/*.db` and `log/*.db` (with the usual `-wal`, `-shm` and `-journal` companions of SQLite, D-156) and keeps each empty folder with a `.gitkeep`;

- (d) the core database of D-156 is created in `db/` on the first run, not by the command.

## Q-049 Splitting the monolith: modules, the parts of `eve`, the serving machine (2026-10-12, answered → D-163 to D-167)

Author request (2026-10-12): "decouple the monolith evevm into parts: core, evecp, evevm, evedb, eveux … evevm will use IPC and eveux will host http server receive api calls using ACP". Five revisions of `design/design-packages.md` in one day; the author answered sixteen questions and reviewed revision 4; the answers are in the appendix of that file, word for word. Approved by the author on 2026-10-12 ("plan is approved"). The decisions are D-163 to D-167; the work plan (phases A and B, steps A0 to B6) is §10 of the design.

## D-163 Modules and one binary: `eve vm`, `eve cp`, `eve db`, `eve ux` (2026-10-12)

Author decisions (Q-049, answers 2 to 6, 12, 16, review of revision 4).

- (1) The source of the VM is split into Zig modules at the root of the repository, with one `build.zig`: `evecm` (the leaf: values, heap, codecs, interfaces, wire, terminal; Zig code only, no data), `evecp` (compiler), `evevm` (runtime), `evedb` (database), `eveux` (UI), and `code/eve/` (the entry point `eve.zig` and `dispatch.zig`, no `src/`). The Eve standard library is in `lib/`.

- (2) The arrows are checked by the build: `evevm` imports `evecp` and `evecm`; `evedb` imports `evecp` and `evecm`; `eveux` imports `evecm` only; `evecp` imports `evecm`; only `cmd` imports every module and connects the parts through the interfaces of `evecm`.

- (3) **One executable**, `bin/eve.exe`, so there is one version. Its first word chooses the part: `eve vm …` (the default: `eve file.eve`, `-x`, `-lsn` are as before), `eve cp …` (check, doc, compile, `project`), `eve db …` (the commands of the former `evedb.exe`), `eve ux …` (the UI; `--serve` stays as a synonym).

- (4) No links in `bin/`: the root `run.sh` gets the shortcuts `eve`, `evevm`, `evecp`, `evedb`, `eveux`, which pass the other arguments through and keep the working folder; users write their own start scripts.

Design: `design/design-packages.md` §2 to §4, §9.

## D-164 The serving machine: one process, its parts as tasks (2026-10-12)

Author decisions (Q-049, answers 1, 1a, 11).

- (1) A direct command (`eve file.eve`, `eve cp --check`, `eve db sql …`) runs the parts it needs inside its own process.

- (2) A **serving machine** is one process per domain and port (D-162: the singleton, exit 75 on a second start). Its active parts (runtime, database, UI) run as concurrent tasks and call each other in process, through interfaces, never through IPC.

- (3) Each part opens its own door: **IPC** for the runtime (`vm.*`) and for the database (`db.*`), HTTP and WebSocket for the browser and **ACP** for AI agents in the UI part.

- (4) Eve code runs in sessions; a session owns its interpreter and its heap, so sessions share no values; the machine runs one script at a time first (D-162 point 7).

- (5) `-x` and `-loc` keep their meaning, also for databases: `-x` opens the database files in its own process, `-loc` sends the work to the machine, whose database part then owns the files.

Design: `design/design-packages.md` §5.

## D-165 The machine API `vm.*`, `db.*`; ACP outward; no TLS in `eve` (2026-10-12)

Author decisions (Q-049, answers 1 and 1a, review of revision 4).

- (1) evevm started with `-lsn` exposes a JSON-RPC 2.0 machine API: `vm.ping`, `vm.stat`, `vm.run`, `vm.eval`, `vm.suspend`, `vm.resume`, `vm.inspect`, `vm.cancel`, `vm.stop`; the methods `ping`, `status`, `run` and `stop` of D-162 are their old names, accepted until level 6. The database part answers `db.query`, `db.execute`, `db.call`, `db.proc.list`, `db.proc.reload`, `db.stat`.

- (2) `eve -rem` and the UI part are **clients**: they speak ACP (the Agent Client Protocol) to AI agents and IDEs, and turn the intent of the agent into the exact `vm.*` calls of the remote machine; the agent receives the **eve skills** as the MCP server of the machine.

- (3) `eve` holds **no TLS server** and compiles no C TLS library: every door is plain JSON-RPC or HTTP, on loopback or a Unix socket by default; remote HTTPS is given by a reverse proxy (Nginx, Caddy, Cloudflare Tunnel) in front of the machine; a non-loopback address needs an explicit key in `eve.cfg`; the machine still checks the login and the token (D-155). `eve -rem` uses the TLS client of Zig's standard library.

Design: `design/design-packages.md` §5, §6.

## D-166 Stored procedures, `sql function`, SQLite embedded and DuckDB on demand (2026-10-12)

Author decisions (Q-049, answers 7, 10, 14, 15, review of revision 4).

- (1) **Two kinds of stored procedures**: native ones in the language of the database (PL/SQL, PL/pgSQL, …) in the `sql/` folder of a project, called from Eve through `external` declarations that bring only the signature; and **Eve procedures**, Eve modules in the `proc/` folder of a project, run by the database part for SQLite and DuckDB. For other databases the database part is a wrapper that calls their native procedures.

- (2) **`sql function name`**, with the new keyword `sql` (contextual, D-116: a keyword only before `function`), marks an Eve function that the database part registers as a SQL function of SQLite and DuckDB through their C API. Other databases get no custom Eve functions: their data is brought into the process, changed in Eve, and written back in bulk or one row at a time.

- (3) A `sql function` that DuckDB calls from its worker threads runs under a session mutex or a thread-safe execution pool; the cost is measured (step A9) before query concurrency grows.

- (4) SQLite is embedded in `eve`; the DuckDB library is loaded only when a DuckDB connection opens.

Revises D-159 (DuckDB was a separate program, `evedb.exe`). Design: `design/design-packages.md` §7.

## D-167 One version; version N is level N; the split in 0.0.5 and 0.0.6, the bytecode in 0.0.6 (2026-10-12)

Author decisions (Q-049, answers 8, 9, 13).

- (1) One version for everything, written once in the root `build.zig.zon`; the release notes stay in `manual/releases/` (D-153).

- (2) **Version N is level N**: the release 0.0.3 holds levels 1 to 3; 0.0.4 is level 4, 0.0.5 level 5, 0.0.6 level 6.

- (3) The split is part of 0.0.5 (phase A) and 0.0.6 (phase B); the bytecode compiler and VM and the `.evb` file (F-VM-04, F-VM-07) move to 0.0.6. The headings of `version_map.md` ("Version 0.4 = Level 5") are renumbered to match (step A11); revises D-138.

## D-169 `--listen [word]` replaces `-lsn [port]`: the two doors take the same words (2026-10-13)

Author decision: "I want to bring symmetry in eve parameters. `-lsn [port]` is not symmetric with `--serve`. Let's replace `-lsn` with `--listen` and `[port]` with `<command>`: `--listen status | stop`." Revises point 10 of D-162.

- (1) The IPC door is `--listen [word]`, the HTTP door `--serve [word]`; the words are the same: `start` (the default), `stop`, `restart`, `status`; `--listen --serve` starts a machine with both doors.

- (2) `--listen stop|restart|status` speaks to the machine through the IPC door only, as `-loc` does (no IPC door: `eve: no local machine`, exit 69); `--serve stop|restart|status` tries the IPC door, then the HTTP door of `localhost`, as before.

- (3) The ports come from the configuration only: `-lsn <port>` is gone; a machine on another port has its own file (`eve -s second.cfg --listen`), and `-loc <port>` still addresses it.

- (4) `-lsn` is an unknown option (exit 64), like `-ls`, `-lo` and `-r` before it; a word after a door that is not one of the four is a usage error (exit 64).

Spec: `spec/library/machine.md`; manual: `manual/usage.md`; tests: e95_test1 to e95_test3 (`--listen status`, `--listen stop`, `-lsn` refused), `test/project` (`second.cfg`).

## D-171 Two ways to give credentials; `--connect` before `--upload`; `-rem` always; `select` in the REPL (2026-10-13)

Author decision (2026-10-13), given while reviewing the plan of `evetx`: "We use 2 authentification methods. Method one is using environment variable secrets in eve.env file that are not versioned and is one for project. If eve.env do not exist, evevm need parameters for credentials, username & password or connection string that use username/password@machine_name A single string. For remote access evevm must connect to remote machine so: eve --connect <credentials> must be issues before we can use eve --upload command. The upload command will deploy /web folder /proc folder /sql folder. Then we call eve -rem db commands to install or migrate the database. If we use local eve to send commands to remote server we alwais must use -rem option, an equivalent must be use in repl now is not clear what command are running where. We better have a select <machine-name> and the status bar will show what machine we have selected: ready: connection: local or ready: Connection <machine>, Using ctrl + arrows up down we show previous next command we have issued so we can edit and resend a command. ctrl+ lef/ ctlr+ right will change the machine remote1, remote2, local so we can issue commands to a remote machine, a second remote machine or local. If we issue help for local machine we have some commands for remote machine we show only commands that make sense for the remote machine. If I press tab, only stored procedured will be shown or code that is on the server. A program that is not uploaded first can't be executed remote. It must exist on the server."

Read as rules:

- (1) **Credentials, two methods.**
  - (a) The file `eve.env` of the project holds the secrets as environment variables; it is **not versioned** and there is **one per project**.
  - (b) When `eve.env` does not exist, evevm needs the credentials as parameters: a user name and a password, or one **connection string** `username/password@machine_name`.

- (2) **`eve --connect <credentials>`** opens the connection to a remote machine and must be issued before `eve --upload`.

- (3) **`eve --upload`** deploys the folders `web/`, `proc/` and `sql/` of the project.

- (4) Then the commands `eve -rem … db …` install or migrate the database.

- (5) **A local `eve` that sends a command to a remote machine always uses `-rem`.**

- (6) **In the REPL** the equivalent is `select <machine-name>`: the status bar shows the selected machine, `Ready: connection: local` or `Ready: connection: <machine>`. **Ctrl+Up** and **Ctrl+Down** show the previous and next command issued, to edit and send again. **Ctrl+Left** and **Ctrl+Right** change the machine in turn (local, remote1, remote2, …), so a command goes to a remote machine, a second remote machine or the local one.

- (7) **`help`** shows, for a remote machine, only the commands that make sense there.

- (8) **Tab** on a remote machine completes only stored procedures and code that exist on the server.

- (9) **A program that was not uploaded cannot run on a remote machine**: it must exist on the server.

Open points and gaps: Q-051. Design: `design/design-service.md` §16. Features F-NET-09 and F-TLS-26.

## Q-051 The details of D-171: its place next to D-155, names and gaps (2026-10-13)

Proposals and questions for the author.

- **(a) D-155.** D-155 and §15 of design-service.md describe single sign-on (OpenID Connect) and the renewal token in the keyring of the operating system. D-171 names two methods: `eve.env` and parameters. Is single sign-on still wanted (as a third method, later), or does D-171 replace §15.2? Proposal: the two methods of D-171 are the first version; `eve --connect` gets a session token from the machine and keeps **that token, never the password**, in the keyring (D-155 point 3), so a later `eve --upload` or `eve -rem …` is a new process that finds the connection; single sign-on follows in a later version.

- **(b) The password on a command line** is seen in the shell history and in the list of processes. Proposal: `user/password@machine` is accepted, but `user@machine` asks for the password at the terminal, and `eve.env` is the way for scripts.

- **(c) Names in `eve.env`.** One file per project, several remote machines: which variables? Proposal: `EVE_CONNECT_<machine>` holding the connection string of that machine, or a pair `EVE_<MACHINE>_USER` and `EVE_<MACHINE>_PASSWORD`. `project init` and `project new` add `eve.env` to `.gitignore` (F-TLS-23) and write a template without secrets. The syntax is the author's to choose.

- **(d) `machine_name`** in the connection string: a name that the local `eve.cfg` maps to an address (`machine prod at "etl1.example.com:4042"`, §15.1), or `host:port` written there? Proposal: both, a name first.

- **(e) What `--upload` sends.** The text lists `web/`, `proc/` and `sql/`. A remote machine runs only what is on it (point 9), so the Eve programs themselves (drivers, aspects, modules, `lib/`) and perhaps `eve.cfg` must be uploaded too. Confirm; and is an upload the whole project every time, or only the files whose hash changed (proposal: changed files only)?

- **(f) Short letter.** `-u` opens the user interface now; the upload is `--upload` only until a letter is chosen (open since F-TLS-13).

- **(g) The database commands.** `eve -rem prod db install` and `eve -rem prod db migrate`: are these the names, and do they run the migrations of `sql/` (F-DAT-10) through the `db.*` door of D-165? The order of words: the option `-rem prod` before the part word `db`.

- **(h) Order of the machines for Ctrl+Left and Ctrl+Right:** the order of the `machine` lines in `eve.cfg`, or the order of `connect`? Does the list wrap round (local after the last remote)? Proposal: local first, then the machines in the order of `eve.cfg`, wrapping. Only connected machines take part.

- **(i) Ctrl+Up and Ctrl+Down.** Up and Down scroll the output by a line today (`manual/usage.md`, the screen); Ctrl+Up and Ctrl+Down become the history of commands, as asked. Some terminals use Ctrl+arrows themselves; the keys are checked in Windows Terminal, the Windows console and a Linux terminal.

- **(j) What Tab lists on a remote machine.** The names of the stored procedures (`db.proc.list`, D-165) and the programs on the server: this needs one more method of the machine API (proposal: `vm.programs`, listing the uploaded programs and their `proc/` modules).

- **(k) What a refused run says.** Running a program that is not on the server is an error with its own code; proposal: `$err_not_deployed`, the number decided when the spec is written.

- **(l) "Always -rem".** Confirm the reading: without `-rem` a command is always local, also when a connection exists; with `-rem` it never falls back to local.

  **Answer** (2026-10-13, points a, b, c, e, f, i, j; d, g, h, k and l are still open):

1. Single sign on is for level 7, until then we have 2 ways to connect.

2. Ok, no user password in command line but dialog will show two prompts: username (in clear) and password: hidden with stars so nobody can see the password.

3. eve.env can be json, having one entry/vmachine

4. Yes upload must send only part that is server related. proc are server related. Other eve files the project have are designed to run from local vm. On local machine. Do you want to split src/server src/local or use eve-project/local/src and eve-project/server/src I need an opinion.

5. --upload is good but -u is not clear, so we change it. eve -tx start the evetx while eve -ux start the webux.

6. agree, offer also f1 - local machine f2 remote machine f3 another machine.

7. agree

## D-172 The answers to Q-051: two ways until level 7, a dialog for the password, `eve.env` in JSON, `-tx` and `-ux`, F1 to F3 (2026-10-13)

Author answers to Q-051 (points a, b, c, e, f, i, j; the words are in Q-051).

- (1) **Single sign-on is for level 7.** Until then there are two ways to connect: `eve.env`, and the dialog of point 2. D-155 point 2 (single sign-on) and §15.2 of design-service.md wait for level 7.

- (2) **No password on a command line.** `eve --connect <machine>` shows a dialog with two prompts: the user name in clear, and the password hidden with stars. The connection string `username/password@machine_name` of D-171 is therefore not accepted on a command line.

- (3) **`eve.env` is a JSON file with one entry per machine.** It is not versioned.

- (4) **`--upload` sends only the part that is related to the server.** `proc/` is server-related; the other Eve files of a project are designed to run on the local machine. How the project folders mark the two sides is Q-052 (a).

- (5) **`--upload` stays; `-u` is replaced:** `eve -tx` starts evetx, the terminal UI; `eve -ux` starts the web UI (what `-u` did).

- (6) **Keys:** Ctrl+Left and Ctrl+Right change machine, Ctrl+Up and Ctrl+Down walk the history of commands (Q-051 i agreed), and in addition **F1 selects the local machine, F2 a remote machine, F3 another machine.**

- (7) **Tab on a remote machine** lists only stored procedures and code on the server (Q-051 j agreed): the machine API gets one method for it.

Applied 2026-10-14: `-ux` replaces `-u` (now an unknown option) and `-tx` (also the word `tx`) starts `evetx` beside `eve`, in `code/eve/options.zig` and `code/eve/eve.zig`, with `manual/usage.md` and `spec/library/machine.md`. Design: `design/design-service.md` §16, `code/evetx/README.md`, `code/evetx/design.svg`. Features F-NET-09, F-TLS-26, F-TLS-24.

## D-173 evetx is a project IDE in the terminal: file tree, editor, run and debug, database tabs (2026-10-13)

Author design (2026-10-13), after reviewing the first drawing of evetx: "The left sidebar do not include machines, it include the project files, in a tree where each folder can be oben or cloosed and show the subfolders and the files. When I click one file the file opens automaticly for edit in the right panel. The bottom pannel has console, watch, stderr, stdout. Above bottom pannel there are buttons to run, step into step out, continue, stop. I can place breack points. The breackpoints are also listed in bottom pannel, breaks. If I select a breakpoinnt I can remove it or double click to jump to it in code. When I select a database file I can see the tables, I can edit structure or browse the data in new tabs. Tabs can open table list or table of data but can't show the structure. Structure is editted in a generated dialog with all the fields like an inspector, if more fields are available, the buttons allow me do see next page of fields. Make some more svg to show more design."

Read as rules:

- (1) **The sidebar is the file tree of the project**, not a list of machines; a folder opens and closes; a click on a file opens it for editing in the right panel.

- (2) **The bottom panel has five tabs:** Console, Watch, Stderr, Stdout, Breaks.

- (3) **Above the bottom panel are the buttons** Run, Step into, Step out, Continue, Stop.

- (4) **Breakpoints** are placed in the code and listed in the Breaks tab; a selected breakpoint can be removed, and a double click jumps to it in the code.

- (5) **A database file opens its tables;** the structure can be edited and the data browsed, **in new tabs**; **tabs show only a table list or the data of a table, never a structure**.

- (6) **The structure is edited in a generated dialog**, one group of fields per column like an inspector, with buttons for the next and the previous page of fields.

- (7) The machine is not in the sidebar: F1, F2 and F3 and the status line choose it (D-171, D-172).

This **replaces the scope of the first draft** (a machines list and a Run view) and changes the table of Q-050: **evetx has an editor, a debugger and a database browser**; schedules, run history and the job browser stay in `eveux` (D-172). Drawings: `code/evetx/design/*.svg`; design: `code/evetx/README.md`. Features F-TLS-24, F-TLS-27, F-TLS-28.

## D-174 evetx: menu, find and replace bar, inset status bar, grid dialog, console of evevm (2026-10-13)

Author design (2026-10-13), after reviewing the drawings of D-173: "The bottom bar need work, it can show the file/tabe name selected, lien/column, record #/field name Make it look bordered inset. The top toolbar under the title bar can show a search field, a replace field, replace, replace all buttons, In right side we can show a gear icon (settings) The application has a menu, Activate the menu with ctrl+enter. Activate the help dialog with "ctrl+/" Bottom bar has one button on right side that display ? and settings (gear) The dialog for fields should display a grid with headers and bordered cells for fields and attributes of each field. With button for type selection a drop down appear to select the tipe, Default value for date/time has a calendar. If I click the left top title of app a main menu appears with shortcuts. Sage/Save-As. The console show eve console that looks different, we already have a design for eve console in evevm use the same design. Eve prompt with top side scrollable."

Read as rules:

- (1) **Status bar:** bordered, drawn inset; it shows the name of the selected file or table, the line and column, and the record number and field name; at the right a button `?` (help) and a gear (settings).

- (2) **Tool bar under the title bar:** a search field, a replace field, the buttons Replace and Replace all, and at the right a gear icon (settings).

- (3) **Menu:** the application has a menu, opened by **Ctrl+Enter**; a click on the title at the top left also opens a main menu, with the shortcuts, including Save and Save As.

- (4) **Help dialog:** **Ctrl+/**.

- (5) **The field dialog is a grid** with headers and bordered cells: the fields as rows, their attributes as columns; the type is chosen with a button that opens a drop-down; the default value of a date or time field has a calendar.

- (6) **The Console tab uses the design of the console of evevm:** the output scrolls in the upper part, with the `eve:>` prompt below.

Drawings: `code/evetx/design/*.svg` (new: `design-menu.svg`, `design-help.svg`, `design-calendar.svg`; changed: `design.svg`, `design-structure.svg` and the others); design: `code/evetx/README.md` §3 and §6. Features F-TLS-24, F-TLS-28.

## D-175 evetx: two searches, each aligned with the panel it searches (2026-10-13)

Author design (2026-10-13), after reviewing the drawings of D-174: "The search bar must enable searching file names in the left tree and another find in the right side pannel. The search fields are aligned witht he search context. The right side search can search table names, dara or code."

Read as rules:

- (1) The bar under the title bar has **two search fields**.

- (2) The **left** field is aligned with the file tree and searches **file names**.

- (3) The **right** field is aligned with the right panel and searches **table names, data or code**, by what the panel shows.

- (4) The replace field and the buttons belong to the right search (the code), as in D-174.

This **refines Q-054 (c)**, which proposed one Find field for the tab that is open. Drawings: `design.svg` (a file search `load` filters the tree; a find `total` in the code), `design-db.svg` (a find `ord` filters the tables), `design-data.svg` (a find `open` filters the rows); design: `code/evetx/README.md` §3. Feature F-TLS-24.

## Q-055 The details of D-175: matching, keys, and the search of file contents (2026-10-13)

Proposals and questions for the author.

- **(a) How a file-name search matches.** Proposal: the text anywhere in the name, ignoring the case, over the whole tree (also folders that are closed, which open to show a match); the tree keeps the folders that lead to a match; Esc clears the field; a click on a match opens the file as usual. A pattern (`*.eve`) or a fuzzy match later.

- **(b) Keys.** Proposal: **Ctrl+P** puts the cursor in the Files search ("go to file", as in many editors), **Ctrl+F** in the Find search; Tab moves between the two; Enter in Find goes to the next match and Shift+Enter to the previous; Esc leaves a field and clears it.

- **(c) The scope tag.** The scope (`code`, `tables`, `data`) follows the tab and cannot be set by hand. Or should it be a choice, for example to search the data of the table whose structure is open? Proposal: follows the tab only.

- **(d) Search in the contents of all the files of the project** (not only the open file) is not in the request. Proposal: later, as a result list in the bottom panel (a tab Search), with a double click to jump to the line.

- **(e) The data search.** It filters the rows in the database, on every column or on the one that has the cursor? Proposal: every text column, with `column:value` to name one.

  **Answer** (2026-10-13):

1 file name must start with letters I type. It will open the tree in position while I type.

2 Ok

3. Agree

4. good initiative

5. I agree, search is global in this case, it may support * inside string to search a pattern. If is a number search by number.

6. The gear top right is no good, make it a # instead it will jump to line number (jump) or record ID.number.

## D-176 The answers to Q-055: names that start with the letters, a global data search, `#` instead of the gear (2026-10-13)

Author answers to Q-055 (the words are under Q-055).

- (1) **The file search matches names that start with the typed letters**, not the text anywhere; **the tree opens in position while the letters are typed.**

- (2) The keys of Q-055 (b) are accepted: Ctrl+P for the Files search, Ctrl+F for the Find search, Tab between the two, Enter and Shift+Enter for the next and previous match, Esc clears.

- (3) The scope of the right search follows the tab.

- (4) The search in the contents of all the files of the project is a good idea, for later (a Search tab in the bottom panel).

- (5) **The data search is global** (every column); it **supports `*` inside the text to search a pattern**; **a number is searched by number.**

- (6) **The gear at the top right goes; in its place a `#` button that jumps to a line number (in an editor) or to a record, by id or number (in a data tab).** The gear of the status bar stays and opens Settings (answers Q-054 b in part: Settings is opened from the status bar and the menu).

Drawings: `design.svg` (a file search `sal`), `design-data.svg` (a data search `op*n`, the prompt of `#`), `design-goto.svg`. Design: `code/evetx/README.md` §3. Feature F-TLS-24.

## Q-056 The details of D-176: the type-ahead keys, `#`, the wildcard and the number (2026-10-13)

Proposals and questions for the author.

- **(a) The tree while typing.** Proposal: the folders that lead to the first match open, the other folders keep their state; ↓ and ↑ move to the next and previous match; Enter opens the file in a tab and ends the search; Esc clears the field and puts the folders back as they were; the match is not case-sensitive; the search covers the folders that are closed. A name that matches in two folders is two matches.

- **(b) `#` in an editor.** Proposal: a line number (`42`), or `42:7` for a line and a column; a number beyond the end goes to the last line.

- **(c) `#` in a data tab: record number or id.** Two different things: the position of the row in the result (record 1043 of 1,204) and the value of the key column (`id` 1043). Proposal: `1043` jumps to the **record number**; `id 1043` or `#1043` jumps to the row whose **primary key** is 1043, and says so when no row has it.

- **(d) `#` elsewhere.** In a table list: the table number; in the structure dialog: the field number; in the Breaks tab: off. Proposal as stated.

- **(e) The wildcard.** `*` stands for any text, `?` for one character, a backslash makes one of them a letter; the search is not case-sensitive for text. Is `?` wanted? It is a `LIKE` pattern for SQLite and DuckDB (`%` and `_`), so the database does the work.

- **(f) A number.** A search that is a number finds the rows where a **numeric column is equal** to it; it also finds text that contains the digits? Proposal: numbers only (an id, a quantity, an amount); a range `10..20` and a comparison `>5` later.

- **(g) The same wildcard in code.** The find in an editor is plain text in this draft; should `*` work there too? Proposal: no, plain text, with a regular expression switch later.

  **Answer** (2026-10-13): Agree with all proposals. Good ideas.

## D-177 evetx: the preview button; Markdown, images and SVG are previewed; HTML, audio and video are not (2026-10-13)

Author design (2026-10-13), with the agreement to all the proposals of Q-056: "One more. A preview for md files the preview button is next to #. Selecting a SVG/image/md file will show a preview but not html preview. That would be out of scope. Audio files or videos may be present but we do not preview them here."

Read as rules:

- (1) **All the proposals of Q-056 are accepted**: the tree while typing (the folders to the first match open, Up and Down move, Enter opens, Esc restores), `#` as a line (and `line:column`) in an editor and as a record number or `id` in a data tab, `#` in a table list and in the structure dialog, `*` and `?` as wildcards, a number as an equal numeric value, plain text in code.

- (2) A **preview button is next to `#`** in the bar under the title bar.

- (3) **Selecting a Markdown, image or SVG file shows a preview.**

- (4) **There is no HTML preview** (out of scope).

- (5) **Audio and video files may be in a project, and evetx does not preview them.** Drawings: `design-preview-md.svg`, `design-preview-image.svg`, `design-preview-none.svg`; design: `code/evetx/README.md` §3.

Feature F-TLS-29.

## Q-057 The details of D-177: SVG, image formats, the Markdown subset, the view, the cards (2026-10-13)

Proposals and questions for the author.

- **(a) SVG.** Drawing an SVG as a picture needs a rasterizer: the Zig standard library has none, and libvaxis shows decoded pixels, not vectors. Options:
  - (1) a **small rasterizer of our own** for the subset that the project's drawings use (rectangles, circles, lines, paths, text, fills and strokes), written in Zig, a project of its own;
  - (2) an **external converter** if one is installed (`rsvg-convert`, Inkscape), with the source shown when it is not;
  - (3) show the **source of the SVG** (it is XML text) in a read-only tab with its size and `viewBox`, and the picture only in `eveux` (the browser draws SVG itself). Proposal: (3) in the first version, (1) later if the author wants it.

- **(b) Image formats and the drawing.** PNG, JPEG and GIF (the first frame); BMP and WebP later. The picture is drawn with the graphics protocol of the terminal (kitty, and sixel where the terminal has it) when libvaxis finds one, and in half-block cells (two pixels per character cell, in true color) when it does not. The spike T0 checks this on Windows Terminal and on Linux; a decoder library is a package, to be chosen (libvaxis uses `zigimg` for its images).

- **(c) The Markdown subset.** Headings, emphasis and strong text, inline code, code blocks, bullet and numbered lists, block quotes, rules, tables, links (shown as text, Enter opens a linked `.md` or image in a tab), and images (a line `[image: alt text]`; Enter opens it). Raw HTML inside Markdown is shown as plain text, in line with the answer that HTML is out of scope.

- **(d) The view.** The drawing splits the tab (source left, rendered text right). Or does the button switch the whole tab between the source and the rendered text? Proposal: the button cycles source, split, preview.

- **(e) What a click does.** Proposal: a Markdown file opens as source, with the split preview on if the user left it on; an image opens as a read-only preview tab; an SVG as in (a).

- **(f) Audio, video and other binary files** (and large or unknown files): a tab with a card (name, type, size, and the length of a media file when its header gives it cheaply), no playback, the preview button off. Or should these files not open at all, with a message in the status bar? Proposal: the card.

- **(g) Limits.** An image above, say, 20 MB or 8,000 pixels a side is not decoded; the card says so.

- **(h) Live update.** The Markdown preview is drawn again a moment after the last key.

- **(i) The preview of the other tabs.** The button is off in a table list, a data tab and the structure dialog.

  **Answer** (2026-10-13): see D-178: no preview at all; a file card for binary files, SVG included.

## D-178 evetx: no preview, a file card for binary files; no tests; implementation starts (2026-10-13)

Author decision (2026-10-13): "I agree. Let's display just a file card for binary files including svg and we do not show a preview, so the preview button is not necesary. We will respove these issues using eveux that will be able to show the content properlyr endered. Let's start implementation. This app do not need testing, I will manually test visual aspects of this app. Create a design folder for all svg immages and move them in code/evetx/design then start making this tui app."

Read as rules:

- (1) **Binary files show a file card**, **SVG included**; **there is no preview** in evetx and **the preview button is dropped** (D-177 points 2 to 5 and Q-057 are replaced). A text file, Markdown included, opens as source in the editor.

- (2) **`eveux` shows the rendered content** (images, SVG, Markdown, HTML).

- (3) **evetx has no automated tests**; the author tests the visual side by hand. The `// Zig tip:` comments of `CLAUDE.md` still apply.

- (4) **The drawings are in `code/evetx/design/`**, with their generator `gen_svg.py`.

- (5) **Implementation starts** (F-TLS-24). Since the split of D-163 is not made yet, evetx begins as a separate Zig program in `code/evetx/` with its own `build.zig`, and joins the root build at step A7.

Feature F-TLS-29 becomes the file card.

## D-184 Data engines: SQLite :memory: for queries, a native columnar table for pipelines, DBF only as a legacy file decoder (2026-10-17)

Author decision (2026-10-17), which changes the decision to add DBF (evetx README §11, "DBF tables"): "In-Memory Query Engine: use SQLite :memory: with tuned PRAGMAs for dynamic SQL support and relational indexing. High-Speed Vectorized In-Memory Tables: use a native Zig columnar (SoA) memory layout for EVE's custom computational pipelines. Legacy Ingestion: keep DBF only as a file-decoder stream, legacy file ingestion is required; never use it as an active execution engine or storage structure."

Read as rules:

- (1) **The query engine is SQLite `:memory:`**, opened with tuned PRAGMAs (for example `journal_mode`, `synchronous`, `temp_store`, `cache_size`; the values are measured, not guessed). Dynamic SQL and relational indexes (`create index`, unique indexes, the planner) are SQLite's; a file database is opened or attached into it when the work needs the data of a file.

- (2) **The tables of Eve's own computational pipelines are native Zig columnar tables**: a struct of arrays (SoA), one contiguous typed array for each column (integers, floats, booleans, dates; text as an offset array over one byte buffer) with a validity bitmap for NULL, processed a column at a time (vectorized) and without a row object. A column is the unit of the filter, the sort, the join and the aggregate.

- (3) **DBF is a decoder only.** `dbf.zig` becomes a stream that reads a DBF file record by record and hands the values to the importer (the columnar table or SQLite); it never keeps the grid, never writes a DBF file, never runs a query and is never the storage of a table that the person edits. Legacy ingestion stays required, together with the other import formats (CSV, TXT, XLS, JSON); the Import command (EDIT > Import…) is where they enter, into a database.

- (4) **Consequences for evetx** (done on 2026-10-17: DBF files cannot be created any more; to do): the grid of a table reads from the columnar table or a SQLite cursor, not from the DBF structure `dbf.Table` (today also the model of the grid of a SQLite table); the DBF structure dialog, the DBF branches of Save, Save As, Append, Delete and Compact, and the DBF writing code (`rebuild`, `pack`, `subset`, `fileBytes`) are removed after the Import command reads a DBF file; tests of DBF files are written in Python (a script that makes sample DBF files and checks what the importer reads), not in Zig.

- (5) **Replaced:** the DBF paragraph of `code/evetx/README.md` §11 (a DBF table as an editable table with its own structure dialog) and the open point "Decide on DBF support" of `backlog/evetx-status.md`.

**Done (2026-10-17):** the DBF code moved from `evetx` to `drivers/duckdb/src/dbf.zig` as a stream decoder and an encoder (no table, no editing); `evetx` shows only tables of SQLite (a column-wise `grid.zig`) and has EDIT > Import…; `columnar.zig` (types: INTEGER, REAL, BOOLEAN, DATE, TIMESTAMP, TEXT; answer (a)); `importer.zig` (CSV, TXT, JSON, DBF; XLS and XLSX not read); `eve db import` and `eve db export`; `:memory:` databases are tuned in `Db.open`, with `journal_mode=MEMORY` and not `OFF` because `OFF` makes `rollback` unsafe (the one change to (d)); DBF tests are in Python (`script/dbf_check.py`). The syntax in a script is Q-059.

Questions for the author.

- **(a) Columnar types.** Which column types does the first version have (INTEGER 64, REAL 64, BOOLEAN, DATE, TIMESTAMP, TEXT, DECIMAL)? Proposal: the first five, TEXT as offsets over one buffer, DECIMAL later.

  **answer** Agree

- **(b) Where the columnar table is used first.** The pipelines of `eve` (the ETL of test e56) or the grid of evetx? Proposal: the pipelines first, evetx reads a page of rows through the machine API.

  **answer** Agree

- **(c) Moving data between the two engines.** A columnar table loads into SQLite `:memory:` (bulk insert in one transaction) and a query result reads back into columns; should the copy be explicit (`load`, `store`) or hidden?

  **answer** The copy should be explicit. Create the code and document the functionality in /tutorial and /spec.

- **(d) PRAGMA set.** Proposal: `journal_mode=OFF`, `synchronous=OFF`, `temp_store=MEMORY`, `cache_size` large, `locking_mode=EXCLUSIVE` for `:memory:` only; a file database keeps WAL and `synchronous=NORMAL`.

  **answer** Sounds good.

- **(e) When DBF code goes.** Remove the writing code at once, or after the importer reads DBF? Proposal: after, so the sample tables of `test/project` can still be opened.

**Answer:**

**answer** Keep the code for import/export dbf in evedb but remove the vizualization,  and dbf structure edit dialog from evetx. Evetx will be able to view tables in SQLLight.

## Q-059 The Eve syntax of the columnar table, `load` and `store` (2026-10-17)

D-184 (c) asks for the code and for the tutorial and the spec. The code is done in Zig (`drivers/duckdb/src/columnar.zig`, `importer.zig`, `dbf.zig`; the commands `eve db import` and `eve db export`; 

the PRAGMAs of `:memory:` in `sqlite.zig`), and the behaviour is written in `spec/library/data-engines.md` and in the tutorial page `databases.html` (section "Data engines and files"). What is **not** written is how an Eve script names these things, because the syntax is the author's to choose. Questions. 

- **(a) The type.** A name for the columnar table (`Columns`, `Frame`, `Table`, a generic `Columnar(:T)`)? Declared with columns by name and type, or built from a record type?

- **(b) The two moves.** `load` a table into a connection as a name and `store` the answer of a query: methods of the table (`t.load(conn, "items")`, `Columns.store(conn.query...)`), methods of the connection, or statements?

  **answer** load and store are methods so yes. 

- **(c) The kernels.** `count`, `sum`, `min`, `max`, `filter` with a comparison and `take`: methods of the column, with the column named by a string or a field?

  **answer** Yes.

- **(d) The import.** Is `db import` also a call in a script (`conn.import(path, table)`), or only a command?

  **answer** yes, import in script with metthod of connection.

- **(e) XLS.** Read `.xlsx` (a zip of XML files; the standard library has a zip reader) in the first version, or only CSV? Proposal for (e): `.xlsx` later, `.xls` never.

**Answer:**

**answer** no, user must export to intermediate format, then we use supported formats to load the data.

**Done after the answers (2026-10-17):** (d) `conn.import(path, table)` is a method of the connection (`drivers/duckdb/src/conn.zig`, test e110); (e) only CSV, TXT, JSON and DBF are read, a spreadsheet is exported first. **Still open:**

- (a) the name and the declaration of the columnar table, and (c) whether a kernel names its column by a string or by a field (the answer "Yes" does not choose).

- (b) says `load` and `store` are methods, which needs the type of (a) to hang them on.

**Answers of 2026-10-17 and what was built:** (a) the type is a class derived from `Memory`, defined with field names and types; (c) a column is named by its field (`s.price.sum()`). Built: `drivers/duckdb/src/memory.zig` (`new s := Sales();`, `add`, `count`, `take`, `load`, `store`, and the column methods `count`, `sum`, `min`, `max`, `at`, `filter`), hooks `memory_new`, `is_memory`, `memory_call`, `is_column`, `column_call` in `Data` (`code/evecm/src/iface.zig`), test `e111_memory_table`; spec in `spec/library/data-engines.md`, tutorial in `databases.html`. Choices of mine, to confirm: `add` takes the values in the order of the fields; `store` matches the columns of the select to the fields by name and appends; `filter` takes the comparison as a text (`">"`) and answers the rows; `Decimal` and `Instant` fields are refused for now.

## D-185 Service mode: `eve -s`, the machine without a user interface, a Windows service or a Linux daemon; evedb detailed design and version 0.1 (2026-10-17)

Author decision (2026-10-17): "Level6 include evedb design and testing. Create a detailed design of evedb and build it properly. We test it. Until now eve was run as cli/repl or eveux graphic interface now include -s to start it as a service (silent mode). In service mode there is no user interface, the machine listen or serve in silent mode as a service on windows or as a daemon in linux. Review Level6 requirements and round up the /tutorial and /spec." Answers to the questions of the session: bare `-s` is the service and `-s file.cfg` keeps naming the configuration file (the service then reads that file); the first slice of evedb to build is "design now, build the 0.1 core".

Read as rules:

- (1) **`eve -s` is the service** (`design/design-service.md` section 17, `spec/library/machine.md` "Service mode"): no prompt, no output, both doors, a log file and a pid file; started from a console it runs in a process of its own and ends silent; started by the Service Control Manager it is the service; with `EVE_SERVICE=foreground` it is the machine in the foreground.

- (2) **`-s file.cfg` alone is the service** reading the file; with a script, a command, `-x` or a machine option it is only the configuration. This changes the old meaning of `eve -s file.cfg` (the REPL with that configuration).

- (3) **evedb has a detailed design and a first build** (`drivers/duckdb/README.md`): the frames of EWP-db 0.1 (a frame has a length, a type and a stream; values with a tag; 13 request and 9 answer types), sessions with leases, transactions recorded in `eve_tx`, `STATUS` for the doubt after a broken commit, the error classes with SQL states, seven fault kinds, the statement log, and the commands `serve`, `create`, `sql`, `describe`, `snapshot`, `reset`, `status`, `stop`. Tests: `python script/evedb_check.py` (a Python client written from the document, 66 checks) and the unit tests of `drivers/duckdb/`.

- (4) **Level 6 requirements reviewed** (`design/version_map.md`): F-TLS-30 (service mode) added; F-DAT-12 is partial, 0.1 built; the remaining level 6 features are unchanged and open.

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

## D-187 SQLite in eve, DuckDB in evedb; column batches on the native protocol and the driver `evedb://`; no triggers or procedures in evedb (2026-10-18)

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

## D-188 `-s` is only the service, `-e` (`--setup`) the configuration file; the command files `.vmc` are removed (2026-10-18)

Author question (2026-10-18): "One question is -s conflicting between --silent mode and --setup? if yes what we can change? we can rename --setup to --init and use -i instead of -s for initialization." Then: "Question is -e a good candidate for --setup? if yes implement this change. Is evc kind of script useful? or we can just use sh or python scripts to call eve many times and use eve protocol to execute a series of commands instead of a script file. You chose. If is better to keep evc for improved performance keep it but take a note about this."

The conflict was real: `-s file.cfg` was the configuration when something else came with it and the service when it came alone (D-185), so `eve -s prod.cfg` started a service where the author may have wanted a configuration. `-i` was taken by the command files, and "init" already means "create" in `project init`.

Read as rules:

- (1) **`-s [file.cfg]` is the service and only the service.** A `.cfg` after it is the configuration of the service. With a script, a command, `-x` or a door, `-s` is a usage error (exit 64, "`-s` starts the service and takes only a configuration file"). The one exception is the database part: `eve -s -db --serve evedb.cfg` (D-186).

- (2) **`-e file.cfg`, long form `--setup file.cfg`, is the configuration file** for a script, a command or a door: `eve -e prod.cfg --listen`, `eve -x job.eve -e prod.cfg`, `evevm start -e prod.cfg`. `-e` was free; Tab completes `.cfg` files after it. The REPL command `setup` keeps its name.

- (3) **The command files are removed:** `.vmc`, `-i`, `-t` and the "serve mode" of D-063 (`eve -x -i file.vmc`), with the slot of `code/evevm/src/vm.zig`. `-i` and `-t` are now unknown options (exit 64). The session commands (`load`, `parse`, `run`, `errors`, `ast`, `inspect`, `status`, `report`, `stop`, ...) stay, at the prompt and through `vm.eval`.

- (4) **A series of commands goes to one machine over a lasting door,** not through a file: `eve --stdio` (JSON-RPC 2.0, one message per line), `vm.open`, then one `vm.eval` per command line, then `vm.stop`. `script/workflow.py` does this for a whole test level.

Note on performance (asked by the author): the `.vmc` file was not faster. Its gain was one process for many scripts, and the stdio door keeps that gain: one `eve` serves the whole series, with no start per command. The file had costs of its own: the machine polled it every 25 ms, read it whole at each look (limit 1 MB), and needed an idle timeout (`-t`) to end a forgotten session. Calling `eve` once per command from a shell or Python script would be slower (one process start each); the stdio door or the IPC door of a running machine is the fast way. Measured: `python script/workflow.py 1 2` runs 139 tests in one process; 135 pass, and the 3 that fail are the known failures of level 2 (b16, b19, b21).

Changed: `code/eve/options.zig`, `code/eve/cli.zig` (unit tests of the options), `code/eve/help.zig`, `code/eve/eve.zig`, `code/eve/context.zig`, `code/eve/vm_cmds.zig`, `code/evevm/src/vm.zig`, `code/evevm/src/daemon.zig` (`evevm start -e file.cfg`), `code/evevm/src/helptext.zig`, `script/workflow.py`, `script/runtest.py` (the key `"serve"` of `expect.json`, unused, is gone), `script/service_check.py`. Docs: `manual/usage.md`, `spec/library/machine.md`, `design/design-service.md`, `test/project/readme.md`, the tutorial pages `server.html` and `compiler.html`.

## D-189 Libraries of level 6: the Zig/Eve rule, the answers to Q-064, the order of work (2026-10-18)

The plan is `design/design-libraries.md`. Author answers (2026-10-18), read as rules:

- (1) **The rule:** Zig for primitives, hot paths and C or OS interaction; Eve for policy and composition; a module may be split in two (an Eve API over `external` Zig primitives). Performance comes before purity.
- (2) **Signature files** `lib/<name>.eve` (no bodies) for the Zig modules (`fs`, `csv`, `json`, `txt`, `time`, `secret`, `database`, `checkpoint`): accepted.
- (3) **The registry** replacing the string chain of `libraryCall` is the single refactor; a small loss in speed is acceptable.
- (4) **HTTPS:** no TLS in the machine; the Workbench is HTTP on `127.0.0.1` (level 7); production behind a reverse proxy (level 8, backlog); the outbound TLS client for external APIs and OIDC issuers is level 9, backlog (technical debt until Zig is mature). **S9 `tls` leaves level 6.**
- (5) **Names** accepted as written. **`test` and `regex` are in level 6** (very important).
- (6) **No login in level 6:** two machines connect on `localhost` without login; level 6 is not production ready and is tested locally. Login (SSO, keyring, `auth`, `oidc`) moves to **level 7**, with a remote Linux machine to simulate production. **M5 of the plan moves to level 7.**

## D-190 Order of the work and comments for AI (2026-10-18)

- (1) **Priority of the work, changed on 2026-10-18:** (1) the plan (`design/`), (2) the specification (`spec/`), (3) tests and implementation, (4) the manual (`manual/`), (5) the tutorial (`tutorial/`), last. Before: the tutorial first (the FOCUS of 2026-10-07). A feature starts as a plan entry, then spec text, then a failing test and the code; the manual and the tutorial follow and may lag. **The order was replaced by D-194 (2026-10-18)**; rule (2) below stands.
- (2) **Zig comments are written for AI, not for humans.** The `// Zig tip:` teaching blocks (CLAUDE.md, 2026-10) stop for new and touched code; existing tips stay until the code around them changes. A comment says what feature the code implements and where the specification is, in a form that `grep` finds. The convention is in CLAUDE.md ("Zig comments for AI").

## D-191 External signatures in modules; a native that returns nothing is a procedure; the prefix `.` is legacy (2026-10-18)

Author questions (2026-10-18): "Have I decided to use `export` in modules to make members public? ... I have also introduced public, protected, private for methods"; "Should the write be a procedure though? It returns nothing so why is a function? ... Public `.` is legacy and flag it for retirement until all code migrates to the new convention."

Read as rules:

- (1) **D-085 stands.** A module member is public only if the module lists it in `export (…)`; `public`, `protected`, `private` are words for the members of a class. The prefix `.` (public) and `_` (protected) are **legacy**.
- (2) **Legacy to retire** (flag `@legacy retire` in the code, `grep -rn "@legacy"`): the `.` prefix accepted by `eve --doc` (`code/evecp/src/doc.zig`, `startsDeclaration`). Retire when no file in `lib/`, `test/`, `manual/` or `spec/` starts a declaration with `.`; the tutorial migrates last (D-190). `lib/io.eve` and `lib/exception.eve` still have draft forms (`*args`, `@v`, `external set $error`) that the parser does not read; they are documentation of statements of the language and migrate with the `io` and `exception` spec pages.
- (3) **`external function` and `external procedure` in a module** (grammar `module-external`, parser `declarationInDriver`, node flag `is_external`): a signature ending with `;`, no body. A native that returns nothing is a **procedure** (`fs.write`, `fs.append`, `fs.write_bytes`, `fs.make_dir`, `fs.move`, `fs.remove`, `csv.write`, `json.write`, `txt.write`, `checkpoint.write`); a native with a result is a function. A reserved word may be the name of an external and stand in `export (…)`.
- (4) **Not yet:** a user module that declares `external` has no native bound (a call is a run-time error, c31). Binding the externals of `lib/<module>.eve` to the `natives` table of `code/evevm/src/dlib.zig` (they take the argument nodes, not evaluated values) is the next step of M1; until then the standard modules are prelude values and their `lib/*.eve` files are read by `eve --doc`, `script/libcheck.py` and as a check that they parse (tests c29 to c31).
**answer** User can't define externals yet. This is technical debt. Test that try to use externals must fail to pass these are negative tests. Only standard libraries use externals for now. Add a technical debt.

## D-192 `recover` in a function, procedure and method (2026-10-18)

Author answer to Q-065 (2026-10-18): "I agree with (a). Any subprogram like a process can have a recover region. A function, procedure or method can have a recover region."

Read as rules (the details marked *proposed* are the model's completions; the specification is `spec/semantics/errors.md#recover-in-a-function-procedure-or-method`):

- (1) A function, a procedure and a method can end with a `recover` region before `return;`; `$error` is available.
- (2) *(proposed)* The end of `recover` handles the error and the routine returns normally; a function gives its result variables as they are (the zero value when nothing set them).
- (3) *(proposed)* `abort;` passes the error on; an error raised in `recover` replaces it; `retry` and `resume` are a run-time error outside a job; `defer` runs after `recover`.
- (4) *(proposed)* No `recover` in a constructor, a generator or a lambda; no `finalize` in a routine (`defer` does that).
- (5) The implementation: parser (`routineOf`, the handler is `kids[4]`), interpreter (`runRoutine`). Tests: level 2 `b55` to `b59`, level 3 `c34` to `c36`. Feature F-STR-11. Consequence: `rpc.dispatch` (`lib/rpc.eve`) turns a handler error into a `-32603` answer; G-4 and TD-13 are closed by it.

**Please confirm or correct (2) to (4).**

## D-197 The component `cmd` is renamed `eve` (2026-10-19)

Author decision (2026-10-19): "I need cmd to be renamed to eve. That is good idea." The folder `code/cmd/` is now `code/eve/`: the source of the program `eve.exe` carries the name of the program, as `evedb`, `evetx` and `eveux` do. Nothing else changed: it is still the only module that imports every other one. Applied 2026-10-19 (root `build.zig`, `code/README.md`, the READMEs, `CLAUDE.md`).

## Q-067 A simpler architecture: one runtime, a shared compiler, the compiler inside the editors (2026-10-19, answered → D-198)

Author request (2026-10-19): "I want to simplify the architecture and I do not know how. … how is evevm function without evedb? and how is evedb function without evecp. I want better integration between evetx and evecp so that evetx can compile and run eve in process for better debugging experience. The same eveux should include evecp, actually evecm and evecp should be common. Except if you think the compiler produce bytecode. I suggest evevm and evedb to be combined into one. It will be able to execute bytecode. evetx and eveux will include evecp. I suggest evecp to have its own build and will create exe but I can call evecp using eve command."

**How it works today.**

- `evevm` alone cannot reach a database. The interpreter calls the database through the interface `Data` of `evecm`; `eve` (was `cmd`) plugs the database layer in at start (`interp.data_api = &evedb.data`). Without it, `database.connect` has nothing to call.
- The database layer of `evedb` needs no compiler. It receives SQL text and values that the interpreter already computed, through the interface `Host` (evaluate an argument, make a value, raise an error). It imports only `evecm`, and SQLite is linked into it alone.
- `drivers/duckdb/` holds two unrelated things under one name: that database layer (a module of `eve.exe`) and the `evedb` server program (DuckDB, PostgreSQL protocol; it imports no Eve module).
- `evecp` is linked only into `eve.exe`. `evetx` and `eveux` import the editor part of `evecm` and ask a machine for every check, run and step (D-178, D-193).

**Proposal (the model's), to confirm point by point:**

```
evecm   the common part (leaf)                        every program
evecp   the compiler: source -> checked tree -> later bytecode    eve, evecp, evetx, eveux
evevm   the runtime: interpreter (later the bytecode machine),
        the library natives, the database layer, SQLite, the drivers,
        the machine and its doors                      eve (and evetx, eveux if (d) is in process)
eve     the command (D-197)                            bin/eve.exe, bin/evevm.exe
evedb   only the DuckDB server program                 bin/evedb.exe
evetx, eveux   the editors                             bin/evetx.exe, bin/eveux.exe

eve ──► evevm ──► evecp ──► evecm
evecp.exe, evetx, eveux ──► evecp ──► evecm
```

- (a) **One runtime.** The database layer (`sqlite`, `conn`, `orm`, `state`, the drivers `pgclient`, `pgdriver`, `ewpdriver`, `memory`, `columnar`, …) moves from `drivers/duckdb/src/` into `code/evevm/src/db/`, with SQLite linked into `evevm`. The interfaces `Host` and `Data` go (or stay inside `evevm` only); `drivers/duckdb/` keeps only the server. *Model: yes.* Gain: one runtime that will execute the bytecode, no plug-in step in `eve`, no folder that holds two programs. Cost: the unit tests of `evevm` compile SQLite (cached after the first build).
- (b) **`evecp` is a program too.** `code/evecp/` gets its own `build.zig` and `bin/evecp.exe` (check, doc, project init/new, later `compile` to a bytecode file); `eve cp <args>` runs the same code inside `eve` (no second process), as `eve` needs the compiler anyway to run a source file. *Model: yes.*
- (c) **The compiler inside the editors.** `evetx` and `eveux` import `evecp`: diagnostics, outline, symbols and go-to-definition while typing, with no machine. Needs the entry point of TD-34 (one call: text in, diagnostics, outline and symbols out). *Model: yes.*
- (d) **Run and debug: in the editor process, or in a child machine?** In process means the editors import `evevm` too. *Model: a child machine, with a better debug protocol.* A script that loops, takes all the memory or hits a safety panic of the VM would stop the editor with it and lose unsaved work; a script that prints would draw over the screen of `evetx`; the debug experience depends on the protocol (breakpoints in every file, step, the variables and the call stack as structured messages), not on the process. The child is `eve --stdio`, already started by evetx. If the author wants in process anyway: the VM runs in a thread of the editor, its output goes to the Console panel, and a crash of the script still ends the editor.
- (e) **Bytecode.** The compiler produces the bytecode and the runtime executes it (step B5 of `design/design-packages.md`); the syntax tree then lives in `evecp`. Order: (a) first, then (b) and (c), bytecode after; (d) changes only the editors.
- (f) **`evecm` stays the common part** of every program; its editor part (`ide`) stays where it is.

**Answer:**
a) evevm need SQLite in process, for used define functions in Eve to work properly. SQL is embedded in vm. evedb contains just DuckDB and does not support embeded eve user define functions in SQL. So is zig based. Because has nothing to do with eve, and behave like a driver, we move it and rename to /drivers/duckdb So is no longer a component of eve but a separated project. 
b) Yes, evecp is a binary program that can compile Eve code to bytecode. Make it independent build.
d) Debug and run In a child machine.
e) correct.
f) ok

## D-198 The architecture: one runtime with SQLite, the compiler as a program, the DuckDB server leaves (2026-10-19)

Author answers to Q-067 (2026-10-19). Settled:

- **(a) One runtime, SQLite inside.** `evevm` needs SQLite in process so that the user-defined functions written in Eve (`sql function`) work inside SQL. The database layer of `drivers/duckdb/src/` moves into `evevm` with SQLite. The DuckDB server contains DuckDB only and cannot run Eve functions in SQL; it has nothing to do with Eve and behaves like a driver. It is moved and renamed **`drivers/duckdb`**: a separate Zig project, no longer a component of Eve.
- **(b) The compiler is a program.** `evecp` gets its own build and its own binary; the binary compiles Eve source to bytecode. `eve cp` runs the same code inside `eve` (the model's reading of the earlier request "I can call evecp using eve command").
- **(c) The editors include `evecp`.** Not in the answer lines; taken from the request ("evetx and eveux will include evecp"). To confirm in Q-068 (1).
- **(d) Run and debug in a child machine.** The editors do not run Eve in their own process. A richer debug protocol is a separate piece of work.
- **(e) Bytecode: correct.** The compiler produces it, the runtime executes it. The timing stays as in `design/design-packages.md` §10 B5 (version 6), after the changes of this decision.
- **(f) `evecm` stays the common part** of every program.

Consequences: the interfaces `Host` and `Data` (`code/evecm/src/iface.zig`) lose their reason to exist once the database layer is inside `evevm` and are removed in two steps; `drivers/duckdb/` becomes only the DuckDB server and leaves `comp/`. The plan, in stages with a halt after each: [phase-8-architecture.md](../phase-8-architecture.md).
