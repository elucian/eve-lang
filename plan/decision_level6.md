# Decisions, level 6: the Eve machine and the server (version 0.5)

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. Ids are shared by all the decision files ([level 1](decision_level1.md), [2](decision_level2.md), [3](decision_level3.md), [4](decision_level4.md), [5](decision_level5.md), 6, [7](decision_level7.md)); the list of levels is in [decision_level3.md](decision_level3.md) and [version_map.md](version_map.md).

## Scope

One Eve machine, started locally or remotely: set up from its folder, controlled from scripts and from other machines, serving HTTP with `service` scripts, scheduling drivers, and offering its commands to AI assistants as an MCP server. A client/server application is two projects, a client and a server. Tests: `test/level6`, prefix `f`; a test is a pair of projects (client and server) started on `localhost` with different ports.

Features: F-TLS-11 to F-TLS-15, F-STR-08, F-NET-02 to F-NET-06, F-VM-08, F-LIB-10, F-SPEC-06.

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
