# Phase 6 — The machine and the server (level 6)

> Written 2026-10-20. Starts when `phase-1-5-stabilize.md` has closed levels 1 to 5 (the stages S6.0 and S6.1 may start earlier, they only test what exists). Level 6 is the Eve machine as a server and its clients; the web (level 7) is `phase-7-web.md`. The rule of a step, the sizes and the common gate are those of `phase-1-5-stabilize.md`; tests are in `test/level6/` and in `test/level5/e95_web_hello` for the doors.

Where the work stands: the machine runs with two doors (IPC and HTTP), `POST /rpc` with `vm.ping`, `vm.stat`, `vm.run`, `vm.stop`, `vm.eval`, sessions and streamed output, `eve -s` as a service, the `net`, `http`, `route`, `rpc`, `config`, `os`, `crypto` modules. 14 level 6 tests pass. Not started: the wire protocol, remote apply, authentication, capabilities, machine login. Level 6 has two tracks: the **machine** (stages S6.0 to S6.9), which closes level 6, and the **clients** (S6.10 to S6.13, evetx and eveux), which follow the machine API and need the author's hands-on check of every screen.

## Stage 0 — Safe by default

### S6.0 The doors `[x]` (S) — done 2026-10-27: the foreign Host and Origin rule was in `machine.rpcAllowed`; added `os.run!` refused for a script sent over HTTP (`Session.restricted`), the test `f17_http_door`
- **Features:** F-NET-02, F-NET-10 (security). **Change:** the rule for the doors is loopback only, another address only on purpose (`config.zig`, `http_host`); mark it normative in `library/machine.md`. A page in the user's browser can post to `http://localhost:<port>/rpc`: refuse a foreign `Host` and `Origin`; `vm.eval` and `os.run!` are unreachable from the HTTP door until authentication exists (S6.6).
- **Tests:** raw requests with a foreign `Host`, a foreign `Origin`, and `vm.eval` over HTTP (all refused); the IPC door still answers locally.

### S6.1 Time-outs and concurrency of the server `[ ]` (M)
- **Feature:** F-NET-10. **Missing:** `accept!` has no time-out (TD-27); `service.serve` handles one connection at a time (TD-29); each waiting `net` call starts a helper thread (TD-28); `os.run!` streams nothing (TD-9). Measure first (`bmark.py`, `p6e_http_requests`), then fix in this order: time-out on `accept!`, many connections, streaming `run!`.
- **Tests:** a client that sends nothing is cut; 50 parallel requests all answered; `run!` output arrives before the program ends.

## Stage 1 — The specification of the network

### S6.2 Network semantics and the Eve Wire Protocol `[ ]` (L)
- **Features:** F-SPEC-06, F-NET-03. **Change:** write `spec/protocol/` (framing, flow control, resumable streams, errors, versions) from what `drivers/duckdb/protocol/` and the machine API already speak, so the spec follows the code and the tests; then bring the machine's own use of it in line. Q-028 is answered (D-208): the client is level 5, the server level 6; follow the design and confirm it with tests.
- **Gate:** each frame kind has a spec anchor and a test (`"client"` tests against a running machine).

## Stage 2 — The machine

### S6.3 Machine setup and local HTTP `[ ]` (M)
- **Features:** F-TLS-12, F-TLS-14, F-DAT-15. **Missing:** `--setup <folder>`, the machine folder, built-in defaults, identity (domain + port), `setup` reload without restart; `serve` pages of the web folder and the routes of services; the user cache `eve.db` (projects, machines without secrets, history of commands, upload manifest; rebuilt if deleted).
- **Tests:** two machines with different domains on one host; delete `eve.db` and the machine rebuilds it.

### S6.4 The machine API complete `[ ]` (M)
- **Features:** F-NET-08, F-TLS-30. **Missing:** `vm.suspend`, `vm.resume`, `vm.inspect`, `vm.cancel` as specified; `db.*` over JSON (the additions evetx needs); the schedule methods; service mode on Linux (daemon) and Windows (service) tested by `script/service_check.py` in CI.
- **Tests:** one test per method; a method that does not exist answers `-32601`.

### S6.5 Service script kind `[~]` (M) — 2026-10-27: D-242 and Q-100 answered; done: `Route(...)` registers itself (static `set`, dynamic `new`), `service.serve(server, count)`, classes of a module run in the scope of their module (`Class.home`), test `f18_route_register`; left: `eve -s` of a primary aspect with routes listens by itself on the HTTP port and never ends, a route that leaves with its variable, a duplicate route is an error
- **Feature:** F-STR-08. **Change:** decide (question to the author) whether `service` is a kind of file or stays a route table served by `service.serve`; then implement, with the checks that a service never ends by itself and a route aspect is a `concurrent` aspect.
**answer** (recorded as D-242 and Q-100 in `design/decision/level6.md`, 2026-10-27)
A primary aspect is a service. It must define routes. We need a type Route that can be used to define variables of type route. These variables once created are autoregistering into the routing table of the VM. I do not know how but I don't want to have a vizible routing table we register the routes using primary aspect. 

- **Tests:** a service project with three routes; a route that raises an error answers 500 and the service goes on.

## Stage 3 — Trust

### S6.6 Authentication and machine login `[ ]` (L)
- **Features:** F-NET-06, F-NET-07, F-NET-09. **Change (needs Q-048 answered):** tokens and sessions for the doors; users and roles in the Eve database of the machine; `login`, `logout`, `forget`, `whoami`; the renewal token in the keyring of the operating system; `eve.env` and the connection string `username/password@machine`. Single sign-on (OpenID Connect) is the last item. TLS stays in the reverse proxy; the machine has none (TD-11 is level 7/9).
- **Gate:** S6.0 tests now pass with a token and fail without; password hashing and symmetric encryption in `crypto` (TD-5, F-LIB-10) are done first.

### S6.7 Capabilities and sandbox `[ ]` (L)
- **Feature:** F-NET-05. **Change:** permissions for `fs`, `net`, `db` and shell per project and per aspect (the door `it.allow(...)`, TD-10); a remote machine runs only what is uploaded to it.
- **Tests:** an aspect without the `fs` permission cannot read a file (compile or run error with a code); the same aspect with the permission can.

### S6.8 Remote apply and control `[ ]` (L)
- **Features:** F-NET-04, F-TLS-13, F-NET-09 (upload). **Change:** `apply` on another node with a deadline and an idempotency key; `eve -c`, `-rem`, `--connect`, `--upload` (server side: `web/`, `proc/`, `sql/`, `server/` and what they import), `send` between machines, sessions and driver memory (`load`, `dismiss`).
- **Tests:** two machines on loopback; a deadline that expires gives `$err_timeout`; the same idempotency key twice runs once.

### S6.9 AI API and REPL on a machine `[ ]` (M)
- **Features:** F-TLS-15, F-TLS-26. **Change:** `eve --api`, an MCP server whose tools are the machine commands (needs S6.4, S6.6); in the REPL `select <machine>`, the machine in the status bar, history, Tab by machine.
- **Gate:** the tools list matches the API methods.

## Clients (follow the machine API; the author checks every screen)

### S6.10 `evetx` includes the compiler `[ ]` — this is S8.8 of `phase-8-architecture.md`.
### S6.11 `eveux` includes the compiler `[ ]` — this is S8.9.
### S6.12 `evetx` features `[ ]` (L)
- **Features:** F-TLS-24 (rest), F-TLS-27 (debugger), F-TLS-28 (databases), F-TLS-29 (file card). Needs the debugger protocol (S8.11) and the `db.*` additions (S6.4). Q-053 and Q-054 give the open details. Drawing first (D-196), then code, then the headless smoke test.
### S6.13 `eveux` features `[ ]` (L)
- **Features:** F-TLS-19 (shell), F-TLS-20 (SQL and database tree), F-TLS-21 (jobs, logs, admin), F-TLS-22 (debugger), F-TLS-31 (source control). The window is a draft (TD-35, TD-40, TD-41); Q-047 is answered and the drawings exist for part of it. Do after S6.12 so the two clients share the debugger protocol.

## Close level 6

### S6.14 Close `[ ]` (S)
- F-DOC-03 (the tutorial, network part, last in the order of work); update `spec/index.md`; `evegen status` shows level 6 with no `open` feature that is not a client feature; each client feature has either `done` or an item in `backlog/tech-debt.md`.

## Order

S6.0 → S6.1 → S6.2 → S6.3 → S6.4 → S6.5 → (S6.6 → S6.7 → S6.8 → S6.9). The clients start with S6.10 and S6.11 (phase 8) as soon as S6.4 is stable and run in parallel with S6.6 to S6.9; they are not on the path of level 6 as a server.
