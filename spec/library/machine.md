# The Eve machine: parts, doors, local and remote

Status: **0.1-draft**, level 5 (version 0.4), first step of the machine and its web server (F-NET-02, F-TLS-14). Design: `../../plan/design-service.md` sections 3a, 4 and 5, and `../../plan/design-packages.md` (the parts of `eve`). Tests: `test/level5/e95_web_hello` (the page, `e95_test1` IPC only, `e95_test2` HTTP only, `e95_test3` both). Decisions: D-162 (the doors, implemented and tested); D-163 to D-165 (2026-10-12: the parts of `eve`, the serving machine, the machine API, remote access, ACP), whose sections are marked with the level that brings them.

## The parts of `eve`

`eve` is one program, with one version (D-163, D-167). Its **first word** chooses a part:

| Part | Command | Does | Examples |
|---|---|---|---|
| runtime | `eve vm …`, or `eve` with a script or the options of this page | runs scripts, the REPL, the machine and its IPC door | `eve file.eve`, `eve -x f.eve`, `eve --listen`, `eve vm --api` |
| compiler | `eve cp …` | checks, documents and compiles source files; makes projects; runs nothing | `eve cp --check f.eve`, `eve cp --doc lib lib/doc`, `eve cp project new shop` |
| database | `eve db …` | the database commands (`database.md#admin-commands`), the stored procedures, the database door | `eve db serve --test`, `eve db sql shop "select 1"`, `eve db proc list` |
| UI | `eve ux …` | the web door, the Workbench, the AI agents (ACP) | `eve ux start`, `eve ux status`, `eve ux stop` |

- Without one of the four words, `eve` keeps the meaning it has today: `eve file.eve`, `-x`, `--listen`, `-loc`, `-rem` belong to the runtime; `--check`, `--doc` and `project` are synonyms of `eve cp …`; `--serve start`, `stop`, `restart` and `status` are synonyms of `eve ux …`.
- **A direct command** runs the parts it needs inside its own process and ends: `eve file.eve` compiles the script, runs it, and opens its databases in the same process.
- The words are read since 2026-10-12, before the split of the VM into modules: `vm` and `cp` select what the options already do, `ux` is `--serve`, and `eve db` has its first command, `eve db proc list` (`database.md#stored-procedures`). Tests: `e95_test4` (`eve ux start`, `eve ux stop`), `e102_test1` (`eve db proc list`).

## The machine

A **machine** is a process of `eve` that stays active and answers requests. It is a **singleton identified by its domain and the ports of its doors**: on one `domain:ipc_port` there is at most one machine, and on one HTTP port at most one. On `localhost` another machine may run with other ports. The machine has up to two **doors** to the same VM core:

| Door | Started by | Used by | Protocol |
|---|---|---|---|
| **IPC** | `--listen` | the CLI of the same computer | JSON-RPC 2.0 on a Unix domain socket, one message per line |
| **HTTP** | `--serve` | browsers, remote machines, the CLI with `-rem` | files of the web folder, and JSON-RPC 2.0 in `POST /rpc` |

`--listen --serve` opens both doors. `--listen` alone opens no web door. A remote machine opens HTTP and not IPC, unless `--ipc` says so; HTTPS is given by a reverse proxy in front of it (section "Remote access").

## The serving machine (level 6)

From level 6 a machine is the **serving machine** of D-164:

- **One process, its parts as tasks.** One process per domain and port, as above. Its active parts (runtime, database, UI) run as concurrent tasks of that process and call each other in the process, never through IPC. A part is active when its door is open, or when another active part needs it: a script that opens a connection makes the database part active.
- **One door per part:**

| Part | Door | Answers |
|---|---|---|
| runtime | IPC: the socket of this page | `vm.*` (section "The machine API") |
| database | IPC: its own socket, `<runtime>/eve-<domain>-<ipc_port>-db.sock` | `db.*` |
| UI | HTTP and WebSocket for the browser (section "The web door"); ACP for AI agents (section "AI agents") | pages, `POST /rpc`, routes |

- **Sessions.** Eve code runs in sessions. A session owns its interpreter and its heap, so two sessions never share a value. The machine runs one script at a time, as in level 5; several sessions at once, and the state they may share, come later in level 6.
- **Databases.** On a serving machine the database part owns the database files of the project. `-x` and `-loc` keep their meaning for databases too: `eve -x file.eve` opens the files in its own process (SQLite lets several processes share a file); `eve -loc -x file.eve` runs the script in the machine, whose database part opens them.

## Configuration

The file `eve.cfg` of the working folder (or the file of `-s`): one `key = value` per line, `#` starts a comment.

| Key | Default | Meaning |
|---|---|---|
| `domain` | `"localhost"` | the name of the machine; it names the socket |
| `ipc_port` | `4042` | the port that identifies the machine; the socket is `<runtime>/eve-<domain>-<ipc_port>.sock` |
| `http_port` | `8042` | the port of the HTTP door |
| `http_host` | `"localhost"` | the address that the HTTP door listens on |
| `web` | `"web"` | the web folder, relative to the folder of `eve.cfg` |
| `remote` | none | `host:port` that a bare `-rem` addresses |
| `eve_width` | `100` | the width of the `help` table and texts at the prompt, in characters (30 to 400); the variable `EVE_WIDTH` of the environment wins, and a narrower window wins over both |

`<runtime>` is `$XDG_RUNTIME_DIR`, else `$TMPDIR`, else `%TEMP%`, else `/tmp`. The ports come from the configuration only (an option `-s other.cfg` names another file); `-loc <port>` addresses the machine of another `ipc_port`.

## The options

| Option | Long form | Meaning |
|---|---|---|
| `--listen [word]` | | the IPC door: `start` (the default) starts a machine with the IPC door; `stop`, `restart` and `status` speak to the machine **through the IPC door only**, as `-loc` does (without it: `eve: no local machine`, exit 69) |
| `--serve [word]` | | the HTTP door: `start` (the default) starts a machine with the HTTP door; `stop`, `restart` and `status` speak to the machine through the IPC door, then the HTTP door of `localhost` |
| the words | | `stop` ends the machine (exit 0); `restart` stops it, if it runs, then starts it again in this process with the doors it had (the option on the line adds its door; with no machine running it starts like `start`); `status` prints the doors. `--listen --serve` starts a machine with both doors (D-169). Another word after a door is a usage error: `eve: nope: expected start, stop, restart or status after --listen or --serve`, exit 64 |
| `-loc [port]` | `--local` | the command is local: it never uses the network |
| `-rem [host:port]` | `--remote` | the command runs on a remote machine, found by its HTTP door |
| `-x file.eve [args]` | `--execute` | the script runs at once in this process: no machine is looked for |

Options are whole words and are not bundled: `-loc` is one option. The two doors have the same form, `--listen [word]` and `--serve [word]` (D-169: `-lsn [port]` was the IPC door until 2026-10-13 and is now an unknown option, exit 64). The client options have three letters (`-loc` local, `-rem` remote), so they never clash with the one-letter options of the CLI. A command without `-loc` and without `-rem` is local.

**Direct run.** `eve -x file.eve` (or `eve file.eve`) is the fast way to run a script: it does not read the doors of `eve.cfg`, asks no IPC socket and no HTTP port, and executes the script in the process of `eve`, which exits with the exit code of the script. A machine that listens on the same computer does not see the run and does not count it. To run the script in that machine, write `-loc -x` or `-rem -x`.

**In its own process.** `evevm [start|stop|restart|status] [-s file.cfg]` (the same program as `eve`, installed under a second name) starts a machine with both doors in a new process, without a window, with its output in `<runtime>/eve-<domain>-<ipc_port>.log`, and ends as soon as the IPC door answers. `stop` closes both doors of the machine of the process and tells every running script to stop at its next statement; in the prompt of `eve` the process stays, and the machine of another process (the one started by `evevm`) ends. `eve -ux` (it was `-u`, D-172) opens the user interface, the page of the HTTP door, starting the machine in its own process when no door answers.

**Start.** The machine prints one line per door (`eve: ipc localhost:4195`, `eve: http http://localhost:8095`) and stays active. Then it prints one line per request, the **log of the machine**: the door and the method (`eve: ipc status`), a script with its exit code and its duration (`eve: http run hello.eve: exit 0, 1 ms`, with `(waited 4712 ms for another script)` when it had to wait its turn), a page with its status (`eve: http GET /css/style.css: 200`). If a door of the new machine is taken by a running machine (something answers on the IPC socket, or on the HTTP port), the new one prints `eve: already running (…)` and ends with the exit code **75**. The HTTP door is tested by a `ping` and not by the bind, because some systems (Windows) let a second socket bind a port that listens. A socket left by a crash is found by a failed connect and removed.

**Local command.** `-loc` looks for the IPC socket of the configuration. If a machine listens there, the command is sent to it (a script runs in the machine, and `runs` counts it). If none listens, the command runs in a new machine inside the process: `eve -loc -x file.eve` executes the file by itself and exits. A command without `-loc` that cannot reach IPC also tries the HTTP door of `localhost`, so `eve --serve stop` ends a machine that has only HTTP. `-loc --serve status` and `-loc --serve stop` need the IPC door: without it they print `eve: no local machine` and exit **69**.

**Remote command.** `-rem host:port` sends the command to the HTTP door of that address. `-rem` without an address takes `remote` from `eve.cfg`; without it, the command prints `eve: -rem needs an address` and the exit code is 64. If nobody answers, the command prints `eve: no remote machine at host:port` and exits **69**: it never falls back to a local run. A script is sent as text, so a remote script has no local files (`import`, `asp/` and `lib/` are the folders of the remote machine).

**At a terminal.** When a person is at both ends (standard input and output are a terminal), `eve --listen` and `eve --serve` open the doors in threads of the same process and the **prompt comes back**: the window is the machine and a client at once, and the log lines of the requests appear between the prompts. The REPL commands `listen [word]` and `serve [word]` do the same from the prompt, with the words `start` (the default), `stop`, `restart` and `status`; `listen serve` opens both doors in one machine. A `stop` (from the prompt or from another window) closes the doors and the REPL goes on; `quit` ends the process and the doors with it. With a pipe, a file or a service manager the start still waits for the doors and the process ends on `stop`, as before.

**Status.** `eve --serve status` prints these lines and exits 0. Without a machine it prints `eve: not running` and exits 69.

```
machine: localhost ipc=4195 http=8095
ipc: listening           ** or: ipc: off
http: listening          ** or: http: off
runs: 3                  ** scripts run in the machine since it started
requests: 12             ** every request answered, `ping` and `status` included
uptime: 2 min 05 s
doing: idle, waiting for requests    ** or: doing: running hello.eve for 3 s
web: folder web at http://localhost:8095    ** only when the HTTP door is open
parts: vm ux
```

The first four lines are the first form of the answer; the lines after them come from `vm.stat` (fields `requests`, `uptime_ms`, `running`, `running_ms`, `web`, `http_host`). The machine serves each connection in a thread of its own, so a `status` is answered while a script runs on the same door; the scripts still run one at a time.

The REPL command `status` (and `eve --status`) prints the same lines under a header about the process: the script, the configuration file (`loaded`, or `not found, the defaults are in use`) and its ports, and `machine: running` or `machine: not running`, with the command that starts it.

## Channels

**IPC.** One JSON-RPC 2.0 message per line (a message holds no raw line break: JSON escapes it); the machine answers on a line and closes the connection. The file permissions of the socket are the security. **HTTP.** `POST /rpc` with the same message as body, answered with the same kind of message. A reply always travels on the connection of its request.

| Method | Params | Result |
|---|---|---|
| `ping` | none | `"pong"` |
| `status` | none | `{"ipc": bool, "http": bool, "runs": n, "domain": "…", "ipc_port": n, "http_port": n}` |
| `run` | `{"name": "file.eve", "source": "…text…", "args": []}` | `{"status": n, "output": "…", "errors": "…"}`: the exit code of the script, what it printed, the errors that nobody recovered |
| `stop` | none | `"stopping"`; the machine ends after the reply with exit code 0 |

A script runs in its own session; the machine runs one script at a time (the others wait). A CLI that sent a `run` prints `output` on the standard output and `errors` on the error output and ends with `status`. An error that nobody recovers has the exit code 4 (`../semantics/errors.md`).

## The machine API (level 6)

The methods of the machine are named by their part (D-165): `vm.` for the runtime, `db.` for the database. The four methods of the section "Channels" are the first names of `vm.ping`, `vm.stat`, `vm.run` and `vm.stop`; a machine answers both names until level 6 ends, then only the new ones. The params and the results of the four are those of "Channels".

| Method | Params | Result |
|---|---|---|
| `vm.ping` | none | `"pong"` (was `ping`) |
| `vm.stat` | none | the object of `status`, and `parts`, the active parts (`["vm"]`, or `["vm", "ux"]` with the web door); `sessions` comes when a machine runs several (was `status`, which keeps its first shape) |
| `vm.run` | `{"name", "source", "args"}` | `{"status", "output", "errors"}` (was `run`) |
| `vm.eval` | `{"session": id, "source": "…"}` | the value of an expression, or what a statement printed, in a session that stays open: the prompt over the wire |
| `vm.suspend`, `vm.resume` | `{"session": id}` | the session stops at its next statement / goes on (the debugger, F-TLS-04) |
| `vm.inspect` | `{"session": id, "what": "locals" \| "stack" \| "globals"}` | the names and the values, in JSON |
| `vm.cancel` | `{"session": id}` | the run of the session ends with `Abort` (`../semantics/errors.md`) |
| `vm.stop` | none | `"stopping"`; the machine ends (was `stop`) |
| `db.query`, `db.execute` | `{"connection", "sql", "args"}` | the rows / the number of rows changed (`database.md#direct-sql`) |
| `db.call` | `{"name": "module.procedure", "args": […]}` | the results of an Eve procedure of `proc/` (`database.md#stored-procedures`) |
| `db.proc.list`, `db.proc.reload` | none | the procedures of `proc/` / reads them again |
| `db.stat` | none | connections, open transactions, leases |

The params and the results of the new methods are made when a test needs them (author, 2026-10-12); a method that has no test yet answers the JSON-RPC error `-32601` (method not found).

## Remote access: a reverse proxy

`eve` holds **no TLS server** (D-165). Every door speaks plain JSON-RPC or plain HTTP, and listens only on a Unix socket or on loopback (`localhost`, `127.0.0.1`, `::1`) unless the configuration says otherwise.

- **HTTPS for remote clients** is given by a **reverse proxy** in front of the machine, such as Nginx, Caddy or Cloudflare Tunnel. It ends HTTPS and forwards to the loopback port of the HTTP door; WebSocket goes through it the same way.
- **The machine still checks who calls.** The login and the token of the machine (D-155) are checked by the machine, not by the proxy: the proxy carries the bytes, it does not decide who may run what.
- **Another address only on purpose.** A machine binds a `http_host` that is not loopback only when `eve.cfg` says that a proxy is in front of it *(proposed key: `behind_proxy = true`; level 6)*; otherwise it refuses to start, so a plain door is never opened to the network by accident.
- **The client side.** `eve -rem https://host` speaks HTTPS with the TLS client of Zig's standard library. `-rem host:port` without `https://` stays plain HTTP, for `localhost` and the tests.

## AI agents: ACP and the eve skills (level 6)

The UI part speaks the **Agent Client Protocol** (ACP) toward AI agents and IDEs, and turns what an agent asks into the exact calls of the machine API (D-165). `eve -rem` is the same kind of client without a browser.

- **Toward an AI agent**, the UI part is the ACP client: it starts the agent and opens a session on the project folder. It hands the agent the **eve skills**, the MCP server of the machine (`eve vm --api`), whose tools are the methods `vm.*` and `db.*`. It streams the answers of the agent to the browser and asks the user before an action that the agent wants to take.
- **Toward an IDE that speaks ACP**, the UI part answers as an agent: a request about the project becomes calls of the machine API on the local or a remote machine.
- **Credentials.** The API key or the OAuth login of the agent's provider is kept in the keyring of the system (D-155), never in the browser or in a file of the project.

## The web door

`GET` (and `HEAD`, without the body) returns the file of the web folder that the path names: `/` is `index.html`; the type comes from the extension (`html`, `css`, `js`, `json`, `svg`, `png`, `jpg`, `ico`, `txt`, `wasm`; any other is `application/octet-stream`). A path that is not a file of the web folder, or that leaves it (`..`), is `404`: no other folder of the project is served. `POST` is `/rpc` only; any other method or path is `405` or `404`. The body of a `POST` is read by its `Content-Length`, or in chunks when the request says `Transfer-Encoding: chunked` (D-168); a body larger than 16 MB is `413`. The web folder is organized for a single page application: `index.html` at the top and the folders `css/`, `js/`, `img/` and others as the application needs; the backend is Eve, the frontend is JavaScript. From level 6 the web door belongs to the UI part.

## Not yet

A connect time-out for the HTTP door (Zig 0.16 has none on Windows, where a refused connection to `localhost` takes about 2 s; the IPC door answers "nobody there" in about 50 ms), login (F-NET-06, F-NET-07), socket permissions set by the machine (today they are the defaults of the system), host names for `-rem` (today an IP address or `localhost`), WebSocket, the services and routes of the `service` script (level 6), `--ipc` on a remote machine, upload of a project (not a single file), shared state between scripts. Everything marked "level 6" above; the commands of `eve db` other than `proc list`.
