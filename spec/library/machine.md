# The Eve machine: doors, local and remote

Status: **0.1-draft**, level 5 (version 0.4), first step of the machine and its web server (F-NET-02, F-TLS-14). Design: `../../plan/design-service.md` sections 3a, 4 and 5. Tests: `test/level5/e95_web_hello` (the page, `e95_test1` IPC only, `e95_test2` HTTP only, `e95_test3` both). Decision: D-162.

## The machine

A **machine** is a process of `eve` that stays active and answers requests. It is a **singleton identified by its domain and the ports of its doors**: on one `domain:ipc_port` there is at most one machine, and on one HTTP port at most one. On `localhost` another machine may run with other ports. The machine has up to two **doors** to the same VM core:

| Door | Started by | Used by | Protocol |
|---|---|---|---|
| **IPC** | `-lsn` (`--listen`) | the CLI of the same computer | JSON-RPC 2.0 on a Unix domain socket, one message per line |
| **HTTP** | `--serve` | browsers, remote machines, the CLI with `-rem` | files of the web folder, and JSON-RPC 2.0 in `POST /rpc` |

`-lsn --serve` opens both doors. `-lsn` alone opens no web door. A remote machine opens HTTP (HTTPS outside `localhost`) and not IPC, unless `--ipc` says so.

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

`<runtime>` is `$XDG_RUNTIME_DIR`, else `$TMPDIR`, else `%TEMP%`, else `/tmp`. An option `-lsn <port>` replaces `ipc_port`.

## The options

| Option | Long form | Meaning |
|---|---|---|
| `-lsn [port]` | `--listen` | start a machine with the IPC door; it runs until `--serve stop` |
| `--serve` | | start a machine with the HTTP door; with `-lsn`, both doors |
| `--serve start`, `stop`, `restart`, `status` | | `start` is `--serve`; `stop` ends the machine (exit 0); `restart` stops it, if it runs, then starts it again in this process with the doors it had (`-lsn` on the same line adds the IPC door; with no machine running it starts like `--serve`); `status` prints the doors |
| `-loc [port]` | `--local` | the command is local: it never uses the network |
| `-rem [host:port]` | `--remote` | the command runs on a remote machine, found by its HTTP door |
| `-x file.eve [args]` | `--execute` | the script runs at once in this process: no machine is looked for |

Options are whole words and are not bundled: `-lsn` is one option. The three options of the machine have three letters each (`-lsn` listen, `-loc` local, `-rem` remote), so they never clash with the one-letter options of the CLI. A command without `-loc` and without `-rem` is local.

**Direct run.** `eve -x file.eve` (or `eve file.eve`) is the fast way to run a script: it does not read the doors of `eve.cfg`, asks no IPC socket and no HTTP port, and executes the script in the process of `eve`, which exits with the exit code of the script. A machine that listens on the same computer does not see the run and does not count it. To run the script in that machine, write `-loc -x` or `-rem -x`.

**Start.** The machine prints one line per door (`eve: ipc localhost:4195`, `eve: http http://localhost:8095`) and stays active. Then it prints one line per request, the **log of the machine**: the door and the method (`eve: ipc status`), a script with its exit code and its duration (`eve: http run hello.eve: exit 0, 1 ms`, with `(waited 4712 ms for another script)` when it had to wait its turn), a page with its status (`eve: http GET /css/style.css: 200`). If a door of the new machine is taken by a running machine (something answers on the IPC socket, or on the HTTP port), the new one prints `eve: already running (…)` and ends with the exit code **75**. The HTTP door is tested by a `ping` and not by the bind, because some systems (Windows) let a second socket bind a port that listens. A socket left by a crash is found by a failed connect and removed.

**Local command.** `-loc` looks for the IPC socket of the configuration. If a machine listens there, the command is sent to it (a script runs in the machine, and `runs` counts it). If none listens, the command runs in a new machine inside the process: `eve -loc -x file.eve` executes the file by itself and exits. A command without `-loc` that cannot reach IPC also tries the HTTP door of `localhost`, so `eve --serve stop` ends a machine that has only HTTP. `-loc --serve status` and `-loc --serve stop` need the IPC door: without it they print `eve: no local machine` and exit **69**.

**Remote command.** `-rem host:port` sends the command to the HTTP door of that address. `-rem` without an address takes `remote` from `eve.cfg`; without it, the command prints `eve: -rem needs an address` and the exit code is 64. If nobody answers, the command prints `eve: no remote machine at host:port` and exits **69**: it never falls back to a local run. A script is sent as text, so a remote script has no local files (`import`, `asp/` and `lib/` are the folders of the remote machine).

**Status.** `eve --serve status` prints these lines and exits 0. Without a machine it prints `eve: not running` and exits 69.

```
machine: localhost ipc=4195 http=8095
ipc: listening           ** or: ipc: off
http: listening          ** or: http: off
runs: 3                  ** scripts run in the machine since it started
```

## Channels

**IPC.** One JSON-RPC 2.0 message per line (a message holds no raw line break: JSON escapes it); the machine answers on a line and closes the connection. The file permissions of the socket are the security. **HTTP.** `POST /rpc` with the same message as body, answered with the same kind of message. A reply always travels on the connection of its request.

| Method | Params | Result |
|---|---|---|
| `ping` | none | `"pong"` |
| `status` | none | `{"ipc": bool, "http": bool, "runs": n, "domain": "…", "ipc_port": n, "http_port": n}` |
| `run` | `{"name": "file.eve", "source": "…text…", "args": []}` | `{"status": n, "output": "…", "errors": "…"}`: the exit code of the script, what it printed, the errors that nobody recovered |
| `stop` | none | `"stopping"`; the machine ends after the reply with exit code 0 |

A script runs in its own session; the machine runs one script at a time (the others wait). A CLI that sent a `run` prints `output` on the standard output and `errors` on the error output and ends with `status`. An error that nobody recovers has the exit code 4 (`../semantics/errors.md`).

## The web door

`GET` (and `HEAD`, without the body) returns the file of the web folder that the path names: `/` is `index.html`; the type comes from the extension (`html`, `css`, `js`, `json`, `svg`, `png`, `jpg`, `ico`, `txt`, `wasm`; any other is `application/octet-stream`). A path that is not a file of the web folder, or that leaves it (`..`), is `404`: no other folder of the project is served. `POST` is `/rpc` only; any other method or path is `405` or `404`. The web folder is organized for a single page application: `index.html` at the top and the folders `css/`, `js/`, `img/` and others as the application needs; the backend is Eve, the frontend is JavaScript.

## Not yet

A connect time-out for the HTTP door (Zig 0.16 has none on Windows, where a refused connection to `localhost` takes about 2 s; the IPC door answers "nobody there" in about 50 ms), HTTPS and login (F-NET-06, F-NET-07), socket permissions set by the machine (today they are the defaults of the system), host names for `-rem` (today an IP address or `localhost`), WebSocket, the services and routes of the `service` script (level 6), `--ipc` on a remote machine, upload of a project (not a single file), shared state between scripts.
