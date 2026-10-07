# Decisions, level 2: aspects, modules, libraries

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. When a question is answered, turn it into a decision with the date and keep the question text for history. Plan steps reference these ids. **Read cheaply:** `python script/plan.py list` prints every id; `python script/plan.py show D-087` prints one entry from here or from `archive/` (settled entries, full text); `python script/plan.py status` lists what is open.

The log is split in two files. Ids are shared and keep counting across both (an id not found here is in the other file); a new entry goes to the file of its topic:

- [decision_level1.md](decision_level1.md): the project (formats, repositories, licenses, the VM, tests) and the language of a single script (lexical rules, control flow, types, collections, functions, classes, errors in a driver). Matches `test/level1`.
- [decision_level2.md](decision_level2.md): programs made of several files: processes, aspects, modules and imports, libraries, multitasking and parallel aspects. Matches `test/level2`.
- Levels 3 to 7 (data, parallel, database, server, web): [decision_level3.md](decision_level3.md), [decision_level4.md](decision_level4.md), [decision_level5.md](decision_level5.md), [decision_level6.md](decision_level6.md), [decision_level7.md](decision_level7.md); the table of all levels is in decision_level3.md and [version_map.md](version_map.md).

## Q-022 Assumptions of the level 2 tests b01 to b19 (2026-10-03)
The level 2 tests (project tests, D-073) follow D-066, D-068 and D-072. These rules are assumed without a decision; confirm or correct each one (the test named after it changes with the answer):
(a) An import that fails on a name conflict (`use (*)`) raises `$err_module`; it happens before the process, so nothing can recover it and the exit code is 30 (b06).
(b) Reading a private member of a module (`counter.total`) is a runtime error `$err_access`, exit code 21; it could also be a check-time error (exit 65) (b09).
(c) The keys of a map spread into named arguments are symbols named like the parameters: `apply add3(a: 10, *m)` with `m := {'b': 20, 'c': 30}` (b14).
(d) `$error.line` is the line of the `raise` in the aspect file, not the `apply` line of the driver (b15).
(e) A driver may declare an extension method for a class imported from a module, and `use (m(*))` brings the class in as a bare name (`Point`) (b18).
(f) `log_err` and `log_wrn` write `out/error.log` and `out/warning.log`, one message per line, no time stamp (b19; the names and the line format are open since D-057).
(g) Aspects are found in `asp/` and modules in the folder named by the import path, both relative to the folder of the driver (the project root, D-055, D-073).
**Answer:** _(open)_

## D-082 `eve --doc` replaces `eved` (2026-10-05)
Author decision. Replaces the separate tool `eved` of D-053; the rules of the generated documentation do not change.
- Every function of the Eve tools is a command of `eve`: there is no second program. The documentation generator is the command `doc`: `eve --doc <folder | file.eve> [output folder]` on the command line, `doc …` in the REPL (every REPL command is also a `--<command>` option, `manual/usage.md`).
- It writes `<name>.md` for the file given, or for each `.eve` file directly in the folder; the output folder is `doc` by default and is created when missing. Exit status 0, 64 (path missing), 66 (can't read).
- Code: `evevm/src/doc.zig` (moved from `evevm/doc/eved.zig`, with Zig tips), the jump-table entry `doc` and the handler `cmdDoc` in `cli.zig`. `zig build doc` runs `eve --doc lib doc`. The build no longer makes `eved.exe`; `evevm/doc/eved.zig` and `bin/eved.*` are deleted. The declarations recognized now also include `generator` and `service`.
- Checked: `zig build test` passes; `zig build doc` regenerates `doc/io.md` and `doc/exception.md` unchanged; `eve --doc lib/io.eve <folder>` writes the same page.
- Applied: evevm README, `evevm/doc/README.md`, `evevm/lib/README.md`, `manual/usage.md` (command table, section "Documentation: doc"), tutorial modules.html, `plan/features_inventory.md` (F-TLS-07, F-DOC-05), `tools/TODO-vscode-plugin.md`.

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
