# Decisions, level 6: the Eve machine and the server (version 0.5)

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. Ids are shared by all the decision files ([level 1](level1.md), [2](level2.md), [3](level3.md), [4](level4.md), [5](level5.md), 6, [7](level7.md)); the list of levels is in [decision_level3.md](level3.md) and spec/features.

## Scope

One Eve machine, started locally or remotely: set up from its folder, controlled from scripts and from other machines, serving HTTP with `service` scripts, scheduling drivers, and offering its commands to AI assistants as an MCP server. A client/server application is two projects, a client and a server. Tests: `test/level6`, prefix `f`; a test is a pair of projects (client and server) started on `localhost` with different ports.

Features: F-TLS-11 to F-TLS-15, F-TLS-19 to F-TLS-22 and F-TLS-31 (eveux, moved here by D-205), F-STR-08, F-NET-02 to F-NET-07 (F-NET-07: a login per remote machine, single sign-on, the keyring, D-155), F-VM-08, F-LIB-10, F-SPEC-06.

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

- Q-028 Networking and protocols (answered 2026-10-21 → D-208, the question is in level7.md)
- Q-050, Q-052, Q-053 and Q-054 (evetx) moved on 2026-10-20 to `design/components/evetx/design/questions.md`; read them there (`python script/plan.py show Q-053` finds them)
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
- D-173 evetx is a project IDE in the terminal: file tree, editor, run and debug, database tabs (2026-10-13)
- D-174 evetx: menu, find and replace bar, inset status bar, grid dialog, console of evevm (2026-10-13)
- D-175 evetx: two searches, each aligned with the panel it searches (2026-10-13)
- Q-055 The details of D-175: matching, keys, and the search of file contents (answered → D-176)
- D-176 The answers to Q-055: names that start with the letters, a global data search, `#` instead of the gear (2026-10-13)
- Q-056 The details of D-176: the type-ahead keys, `#`, the wildcard and the number (answered: all agreed → D-177)
- D-177 evetx: the preview button; Markdown, images and SVG are previewed; HTML, audio and video are not (2026-10-13)
- Q-057 The details of D-177: SVG, image formats, the Markdown subset, the view, the cards (closed by D-178)
- D-178 evetx: no preview, a file card for binary files; no tests; implementation starts (2026-10-13)
- D-188 `-s` is only the service, `-e` (`--setup`) the configuration file; the command files `.vmc` are removed (2026-10-18)
- D-184 Data engines: SQLite :memory: for queries, a native columnar table for pipelines, DBF only as a legacy file decoder (2026-10-17)
- Q-059 The Eve syntax of the columnar table, `load` and `store` [answered, implemented 2026-10-17]
- D-197 The component `cmd` is renamed `eve` (2026-10-19)
- Q-067 A simpler architecture: one runtime, a shared compiler, the compiler inside the editors [answered → D-198]
- D-198 The architecture: one runtime with SQLite, the compiler as a program, the DuckDB server leaves (2026-10-19)
**answer** modified

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
So many alternatives. We keep the credential in eve client SQLLight, password checksum. evevm and evedb will do this job. To spin a service user must provide os credentials, user can start evedb like a normal eve machine and manage credentials. We create command set: -a --admin superuser, eve enter admin mode, in this mode it can ask a set of commands like: create user <username>/<password>, alter user <username>/<password>, remove user <username>. Later we add more fields about users that will be stored secured in SQLLight and managed remote using a management form in user interface.  

## Q-065 Catching an error inside Eve code (2026-10-18, answered 2026-10-21 → D-207)

The standard library found that `recover` exists only at the end of a process (and aspect), so a function can not catch an error (`backlog/library-gaps.md` G-4). A server must turn the error of a handler into an error answer and go on. Options, for the author to choose (the syntax is the author's):

- (a) `recover` allowed at the end of a function and a procedure, like a process: `function f() => (@r: T) is … recover … return;`.
- (b) a `try` form for a block or an expression: `try … recover … done;`.
- (c) no change in the language: every handler is an **aspect** (an aspect recovers its own error, D-072), run with `apply`; `rpc.dispatch` and the routes then take aspects, not lambdas.
- (d) a native `call_safe(f, args)` in the library that gives a result record with the error (no syntax).
**Answer:**
I agree with (a). Any subprogram like a process can have a recover region. A function, procedure or method can have a recover region.

## D-201 Bytecode: a register machine, a project bundle, the tree walker kept as the reference (2026-10-19)

Author answers to Q-B1 to Q-B9 of `design/design-bytecode.md`. Settled:

- **Register machine** (Q-B1), 32-bit instructions.
- **Versions** (Q-B2): the refactoring ladder R0 to R8 and the first stages of the VM in the current line; the `.evb` file and the embedding in 0.7 (`spec/features/`). `design-packages.md` B5 now points to the design.
- **The tree walker is kept as the reference engine** (Q-B3): once stable it needs no maintenance, and it stays the oracle of the tests.
- **One bundle per project** (Q-B4): Eve projects are small.
- **JIT in version 0.8** (Q-B5); **change of the `Value` layout in version 0.8** (Q-B6); **tail calls in version 0.10** (Q-B7); a depth limit by configuration, `StackOverflow` as a language error.
- **Targets** (Q-B8): those of §11, with +10% accepted in this phase; the risky and expensive steps are avoided; optimization stops after R4 if the result is good enough.
- **Order of the ladder** (Q-B9): R0, R1, R2, test, R4, test.
- **Order of the work:** the blockers left in levels 5 and 6 come before the bytecode.

## D-202 Answers to the issues on classes, `command` and `option` (2026-10-20)
Author answers to `design/issues/classes.md`, `command.md` and `option.md`; the suggestions of 2026-10-20 were accepted unless a line below says otherwise.
- (1) **CLS-09, several type parameters.** A generic class may take several type parameters in one list: `class Pair(:K, :V) = {key: K, value: V} <: Object is`, used as `Pair(:String, :Integer)(key: "a", value: 1)`. The prefix forms (`()Type`, `{}(K:V)`) stay the notation of the library collections. Spec: `spec/syntax/declarations.md#traits-and-generic-classes`; test `test/level4/d41_generic_class_two_params`.
- (2) **CLS-13.** A property and a method of one class may not share a name: a compile error (exit 65). Implemented in `check.zig` (`propertyMethodClash`); test `test/level3/c39_property_method_same_name`.
- (3) **CLS-14, destructors.** A destructor runs when the last reference is released, at the next safe point of the region (D-151), and for the objects still alive at the end of the run; the newest object first; a class runs its own destructor and then those of its parent classes; once per object. An error in a destructor is dropped. An object that only the tracing collector finds (a cycle) runs its destructor before it is freed. Implemented (`Heap.finalize`, `Interp.runDestructor`); test `test/level3/c41_destructor`.
- (4) **CLS-15, adopting a trait outside the class.** Level 4 (the author's word), with the form `adopt Trait for Type is … end adopt;` that holds the methods the trait requires; visible only where its module is imported, like the extension methods (D-086). Spec: `spec/syntax/declarations.md#traits-and-generic-classes`; test `test/level4/d42_adopt_trait`.
- (5) **CLS-16, library traits.** `Iterable`, `Stream`, `Comparable` and `Printable` are defined as in `declarations.md`; they can be written as Eve files in the library, and the library may add traits as it grows (plan step S5.1a). No new rule.
- (6) **CLS-17b, hidden state.** A private attribute needs a constructor in the same class (a class without one is filled by name). Exception: `set` in the body of a partial class defines a **constant** of the class, initialized automatically once, when the class is declared; it is read as `ClassName.NAME`. Spec: `declarations.md#classes-and-objects`; tests `test/level3/c40_private_attribute_needs_constructor` and `c42_class_constant`.
- (7) **CMD-04.** There is no shell `export` statement; `export` only makes the members of a module public. A program started with `os.run!` gets variables through a map argument: `os.run!(command, args, cwd, timeout_ms, env)` (library gap G-10, closed). Spec: `spec/library/os.md`; test `test/level6/f16_os_env`.
- (8) **CMD-05.** `$OS_PWD` stays, read-only; `$CWD` is dropped. Spec: `spec/semantics/variables.md`; test `test/level1/a93_os_pwd`.
- (9) **OPT-01, OPT-02.** The lexer stays ASCII only. The Unicode symbols are removed from the tutorial; the page `option.html` is to be removed by the author, and `design/issues/option.md` goes with it.

## D-205 `eve` has a user and a GUI at level 6: `-u`, `-a`, the password asked in a dialog, credentials in the SQLite of the client; evetx and eveux are level 6 work (2026-10-20)

Author decision (2026-10-20), answers to Q-048, Q-052 (c) and the review of level 6: "So many alternatives. We keep the credential in the eve client SQLite, password checksum. evevm and evedb will do this job. To spin a service the user must provide OS credentials; the user can start evedb like a normal eve machine and manage credentials. We create a command set: `-a --admin` superuser, eve enters admin mode, and in this mode it can ask a set of commands like: create user <username>/<password>, alter user <username>/<password>, remove user <username>. Later we add more fields about users that will be stored secured in SQLite and managed remotely using a management form in the user interface." And: "eveux and evetx will have a user login dialog. eve will have `-u --user` and `-a --admin`, two ways to enter the username; the password is a dialog, the machine will ask the password (secret field) with stars." And: "eve in level 6 will have user and GUI. I will continue working on evetx and eveux on level 6, while level 7 is all about the server."

Read as rules:

- (1) **The credential store is the SQLite database of the `eve` client**, and it holds a **checksum of the password**, never the password. `evevm` and `evedb` do the checking; a machine that listens keeps its users the same way.

- (2) **Two options enter the username:** `-u` and `--user <name>` for a user, `-a` and `--admin` for the superuser. (`-u` was removed by D-172 because its old meaning was unclear; it comes back with this meaning.) **The password is never an argument:** the machine asks for it in a dialog, a secret field that shows stars. `eve.env` of D-172 stays for CI.

- (3) **Admin mode.** With `-a`, `eve` enters admin mode and accepts: `create user <username>/<password>`, `alter user <username>/<password>`, `remove user <username>`. Later: more fields of a user, stored secured in SQLite and managed remotely by a form in the user interface.

- (4) **Starting a service needs the OS credentials of the user.** The user can start evedb like a normal Eve machine and manage the credentials of its users the same way.

- (5) **evetx and eveux have a login dialog** (user, password with stars) and use the same store and the same commands; the login flow goes down to `code/evecm/wire` (Q-050 point 4).

- (6) **The alternatives of Q-048 are set aside:** single sign-on by OpenID Connect, the keyring with a renewal token, roles `viewer` to `admin`, `$EVE_REGISTRATION`, `login`/`logout`/`whoami`, the macOS Keychain. They are not built; they stay as ideas (`backlog/ideas.md`) for when the simple scheme is not enough.

- (7) **Levels.** `eve` with a user and the GUI clients, evetx (`-tx`) and eveux (`-ux`), are developed at **level 6**; the features F-TLS-19 to F-TLS-22 and F-TLS-31 (eveux) moved from level 7 to level 6 in `spec/features/`. **Level 7 is all about the server** (evedb, D-203 and D-204, and the portal). This changes the level of D-154 and D-193 for eveux.

Not done by this decision: the code of `-u`/`-a` and the dialogs (a plan entry and a failing test first, D-194), and the tests of level 6 for them.

## D-207 Answer to Q-065: a function, a procedure and a method can have a `recover` region (2026-10-21)
Author decision (2026-10-21): option (a). "Any subprogram like a process can have a recover region. A function, procedure or method can have a recover region." No `try`, no `call_safe`. **Already built and specified** before the answer: `semantics/errors.md#recover-in-a-function-procedure-or-method` and the tests b55 to b58 (`recover` in a function, the result after `recover`, the error that propagates, `retry` refused). Nothing to do in step S15.31 for this question; the library gap G-4 is closed.

