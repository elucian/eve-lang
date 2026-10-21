<!-- Generated from the specification, the tests and the benchmarks. Do not edit this page. -->

# Level 6: The Eve machine and the server

The Eve machine and the server: setup from a folder, control by scripts and by other machines through the doors (IPC, stdio, HTTP), sessions and the machine API `vm.*`, services and routes written in Eve, the editors' link to the machine, and the clients of the machine: `eve` with a user (`-u`, `-a`), the terminal IDE evetx and the native workbench eveux. Capabilities and the Eve Wire Protocol are still open. 

| Code | Feature | Stage |
|---|---|---|
| [`F-DAT-15`](#f-dat-15-the-user-cache-evedb) | The user cache `eve.db` | planned |
| [`F-DOC-03`](#f-doc-03-tutorial-network-and-web-part) | Tutorial, network and web part | planned |
| [`F-LIB-10`](#f-lib-10-encryption-and-hashing) | Encryption and hashing | drafted |
| [`F-NET-02`](#f-net-02-http-server) | HTTP server | drafted |
| [`F-NET-03`](#f-net-03-eve-wire-protocol-ewp) | Eve Wire Protocol (EWP) | planned |
| [`F-NET-04`](#f-net-04-remote-apply) | Remote apply | planned |
| [`F-NET-05`](#f-net-05-capabilities-and-sandbox) | Capabilities and sandbox | planned |
| [`F-NET-06`](#f-net-06-authentication) | Authentication | planned |
| [`F-NET-07`](#f-net-07-machine-login-single-sign-on-and-the-keyring) | Machine login: single sign-on and the keyring | planned |
| [`F-NET-08`](#f-net-08-the-machine-api) | The machine API | drafted |
| [`F-NET-09`](#f-net-09-credentials-connect-and-upload) | Credentials, connect and upload | planned |
| [`F-NET-10`](#f-net-10-time-outs-of-the-waiting-calls) | Time-outs of the waiting calls | drafted |
| [`F-SPEC-06`](#f-spec-06-network-semantics-and-protocol) | Network semantics and protocol | planned |
| [`F-STR-08`](#f-str-08-service-script-kind) | Service script kind | planned |
| [`F-TLS-12`](#f-tls-12-machine-setup) | Machine setup | planned |
| [`F-TLS-13`](#f-tls-13-remote-control) | Remote control | planned |
| [`F-TLS-14`](#f-tls-14-local-http) | Local HTTP | planned |
| [`F-TLS-15`](#f-tls-15-eve-api-for-ai) | Eve API for AI | planned |
| [`F-TLS-19`](#f-tls-19-eveux-the-rad-workbench-shell) | eveux, the RAD Workbench: shell | planned |
| [`F-TLS-20`](#f-tls-20-eveux-direct-sql-and-database-tree) | eveux: direct SQL and database tree | planned |
| [`F-TLS-21`](#f-tls-21-eveux-jobs-logs-and-admin) | eveux: jobs, logs and admin | planned |
| [`F-TLS-22`](#f-tls-22-eveux-debugger) | eveux: debugger | planned |
| [`F-TLS-24`](#f-tls-24-evetx-the-terminal-ide-files-editor-run-machines) | evetx, the terminal IDE: files, editor, run, machines | drafted |
| [`F-TLS-26`](#f-tls-26-repl-selected-machine) | REPL: selected machine | planned |
| [`F-TLS-27`](#f-tls-27-evetx-debugger) | evetx: debugger | planned |
| [`F-TLS-28`](#f-tls-28-evetx-databases) | evetx: databases | planned |
| [`F-TLS-29`](#f-tls-29-evetx-file-card) | evetx: file card | planned |
| [`F-TLS-30`](#f-tls-30-service-mode) | Service mode | drafted |
| [`F-TLS-31`](#f-tls-31-eveux-source-control) | eveux: source control | planned |

## F-DAT-15 The user cache `eve.db`

Stage: **planned**.

A SQLite cache of the user (`<user data folder>/eve/meta/eve.db`): projects, machines without secrets, history of commands, upload manifest; the `Meta` interface of `evecm`, implemented by evedb; rebuilt if deleted ( b).

## F-DOC-03 Tutorial, network and web part

Stage: **planned**.

Client and server, services, protocol, security, HTML, WebAssembly. (levels 6 and 7)

## F-LIB-10 Encryption and hashing

Stage: **drafted**.

Hashes, HMAC, symmetric encryption (manifest).

*Partial (2026-10-18):* module `crypto` with sha256, sha512, sha256_file!, hmac_sha256, hex and Base64, random_hex!, same; not yet symmetric encryption and password hashing.

## F-NET-02 HTTP server

Stage: **drafted**.

Routes, request and response records, static files, one state per request.

*Partial (2026-10-11):* the machine with its two doors, IPC (`--listen`, was `-lsn` until) and HTTP (`--serve`: the web folder, `POST /rpc`), JSON-RPC methods `ping`, `status`, `run`, `stop`, the client options `-loc` and `-rem`; tests `e95_web_hello` and `e95` to `e95` pass. *2026-10-13:* the machine at the prompt (`listen`, `serve`, `stop`, the doors in threads, one thread per connection), `evevm` (the machine in its own process, log in a file) and `eve -u` (open the web page). Not yet: routes and `service` scripts, HTTPS, login, WebSocket. *2026-10-18:* HTTP and routes in Eve: the system module `net` (TCP), the Eve modules `http`, `route` and `service` (`http.md`, `route.md`; benchmark p6e: 0.72 s for 300 requests against 0.5 s for Python). Not yet: keep-alive, one task for each connection, the machine's own routes in Eve (`f11`).

An example that runs, and what it prints:

```eve
# a client that sends nothing gets a 408 after the idle time and the next client is served (TD-29)
primary aspect f14_service_idle is
  from lib use (http, route, service);

  async procedure run_server(server: Listener, routes: Any, count: Integer) is
    service.serve(server, routes, count);
  return;

  process main is
    service.idle(150);
    new routes:= (route.get("/hello", (req, p) => (route.text("hello"))), route.get("/x", (req, p) => (route.text("x"))));
    new server:= net.listen!("127.0.0.1", 0);
    work: job
    do
      spawn run_server(server, routes, 2);
      new silent:= net.connect!("127.0.0.1", server.port);
      print silent.read_line!;
      new a:= http.get!("http://127.0.0.1:{server.port}/hello");
      print "{a.status} {a.body}";
      silent.close;
    done work;
    server.close;
  return;
end f14_service_idle;
```

```text
HTTP/1.1 408 Request Time-out
200 hello
```

## F-NET-03 Eve Wire Protocol (EWP)

Stage: **planned**.

Framed binary protocol for Eve-to-Eve calls and data streams, flow control, resumable streams.

## F-NET-04 Remote apply

Stage: **planned**.

Run an aspect on another node with a deadline and an idempotency key.

## F-NET-05 Capabilities and sandbox

Stage: **planned**.

Fs, net, db, shell permissions per project and per aspect.

## F-NET-06 Authentication

Stage: **planned**.

Tokens, sessions, TLS certificates for services.

## F-NET-07 Machine login: single sign-on and the keyring

Stage: **planned**.

From one local machine, a login per remote machine: single sign-on (OpenID Connect), an account of the machine, or a machine token; the renewal token kept in the keyring of the operating system (Windows Credential Manager, Linux Secret Service) after the first login; commands `login`, `logout`, `forget`, `whoami`; users, roles and registration of a listening machine in its Eve database.

## F-NET-08 The machine API

Stage: **drafted**.

JSON-RPC 2.0 methods named by part: `vm.ping`, `vm.stat`, `vm.run`, `vm.eval`, `vm.suspend`, `vm.resume`, `vm.inspect`, `vm.cancel`, `vm.stop`; `db.*`; the first names of answered until level 6; no TLS in the machine, a reverse proxy for remote HTTPS; ACP outward.

*Partial (2026-10-12):* `vm.ping`, `vm.stat` (with the active parts), `vm.run`, `vm.stop` and the first names, `-32601` for another method. *2026-10-13:* `vm.stat` adds `requests`, `uptime_ms`, `running`, `running_ms`, `web`; `stop` cancels the running scripts. *2026-10-16:* the lasting doors: the stdio door `eve --stdio` (an IDE starts the machine as its child; over SSH `ssh host eve --stdio`), the IPC connection stays open, `vm.output` notifications (`"stream": true`), sessions `vm.open`, `vm.eval`, `vm.close` (a default session per connection), `vm.shell`, `vm.cancel`, `vm.run` by `path`, `vm.stat` with `door` and `sessions`; `shell <command>` and `!<command>` at the prompt; evetx uses it for its console. Not yet: WebSocket, `dbg.*`, `db.*` in JSON.

## F-NET-09 Credentials, connect and upload

Stage: **planned**.

Two ways to give credentials: the unversioned `eve.env` of the project, or a user name and password or a connection string `username/password@machine_name`; `eve --connect` before `eve --upload`; the upload sends the server side (`web/`, `proc/`, `sql/`, `server/` and what they import: a); `eve -rem … db install|migrate`; a remote machine runs only what is on it.

## F-NET-10 Time-outs of the waiting calls

Stage: **drafted**.

`Socket.set_timeout(ms)` (a read fails with `$err_timeout`), `service.idle(ms)` and the reply `408`, `os.run!` with `timeout_ms` (status 124) (TD-27, TD-29).

*Open:* `accept!` has no time-out, one connection at a time (TD-29), no streaming `os.run!` (TD-9).

An example that runs, and what it prints:

```eve
# set_timeout: a read that waits too long fails with $err_timeout and the server goes on (TD-27)
primary aspect f13_net_timeout is
  async procedure slow_then_fast(server: Listener) is
    new silent:= server.accept!;
    silent.set_timeout(200);
    silent.read_line!;
    print "never";
  recover
    print "timed out: {$error.code}";
    silent.write("408\n");
    silent.close;
    new quick:= server.accept!;
    quick.set_timeout(2000);
    print "got: {quick.read_line!}";
    quick.close;
  return;

  process main is
    new server:= net.listen!("127.0.0.1", 0);
    work: job
    do
      spawn slow_then_fast(server);
      new a:= net.connect!("127.0.0.1", server.port);
      print a.read_line!;
      new b:= net.connect!("127.0.0.1", server.port);
      b.write("hello\n");
      b.close;
    done work;
    server.close;
  return;
end f13_net_timeout;
```

```text
timed out: 41
408
got: hello
```

## F-SPEC-06 Network semantics and protocol

Stage: **planned**.

Remote `apply`, services, Eve Wire Protocol.

## F-STR-08 Service script kind

Stage: **planned**.

Long-running entry point with routes handled by aspects. *2026-10-18:* a service is a route table (`route`) served by `service.serve` in an async procedure; `service` scripts as a kind of file are still to decide.

## F-TLS-12 Machine setup

Stage: **planned**.

`--setup <folder>`, the machine folder, `eve.cfg`, built-in defaults, identity domain + port, external checksum, `setup` reload.

## F-TLS-13 Remote control

Stage: **planned**.

`--listen`, `eve -c`, `-rem`, `-u` upload (*2026-10-14: the user interface is `-ux` and the terminal IDE `-tx`; the upload of is `--upload`*), `send` between machines, sessions and driver memory spaces (`load`, `dismiss`); then the removal of `.vmc` command files (*done 2026-10-18: a series of commands goes through `eve --stdio` and `vm.eval`*).

## F-TLS-14 Local HTTP

Stage: **planned**.

`serve` on port 8042, pages of the web folder, routes of `service` scripts.

## F-TLS-15 Eve API for AI

Stage: **planned**.

`eve --api`, an MCP server whose tools are the commands of the machine.

## F-TLS-19 eveux, the RAD Workbench: shell

Stage: **planned**.

** an Eve project (service script, aspects, modules) run by the local machine, with a browser part in plain JavaScript and CSS: screen and menus, editor with syntax colors for Eve, SQL, JSON, XML and HTML, file dialog and upload, command window, login to remote machines with single sign-on and the keyring, Help and About with the versions; written in Eve as the final test and stress test of the language.

## F-TLS-20 eveux: direct SQL and database tree

Stage: **planned**.

** SQL mode of the command window and SQL tabs, results in a grid with Eve types, Commit and Rollback, the database object tree of the connections of a machine, import wizard ( §7, §9, §12).

## F-TLS-21 eveux: jobs, logs and admin

Stage: **planned**.

** job browser and scheduler forms over the remote scheduler of every connected machine, live run output, stage view of the aspects, resume from checkpoint, log inspector, admin pages of a machine ( §6.6, §10). *2026-10-13: eveux owns schedule management and the management of runs; the schedule methods of the machine API are designed with it; evetx only runs a driver for debug and test (F-TLS-24).*

## F-TLS-22 eveux: debugger

Stage: **planned**.

** breakpoints in the gutter, step into, over and out, variable inspector, watch window, call stack; needs the debugger of the machine (F-TLS-04) and the commands proposed in ( §11).

## F-TLS-24 evetx, the terminal IDE: files, editor, run, machines

Stage: **drafted**.

`eve -tx`: a full-screen TUI on libvaxis (Zig package, no binding); the title and the main menu (click, or Ctrl+Enter; Save and Save As), two searches under the title bar, each above its panel (names that start with the typed letters over the tree, the tree going to the match; code, tables or global data with `*` and numbers over the right panel, with Replace), a `#` button to jump to a line or a record, and the gear of the status bar, the file tree of the project, an editor in tabs, Run, the bottom panel (Console with the design of evevm, Watch, Stderr, Stdout, Breaks), the inset status bar (name, place, `?` help on Ctrl+/, gear), the machine chosen with F1 to F3, connect, the user cache and the select project dialog, upload; no schedules and no run history, those are eveux (F-TLS-21); imports `evecm` only.

*Partial (2026-10-13):* a separate program built with `zig build -p../..` (libvaxis pinned for Zig 0.16): the frame, the tree, the editor with Eve colors, the two searches, `#`, the menu, the help, the file card, breakpoints in the gutter, Run and the console through `eve`; not yet the machines F2 and F3, upload, the debugger, the database tabs, Undo ( §11).

## F-TLS-26 REPL: selected machine

Stage: **planned**.

`select <machine>`, the machine in the status bar (`Ready: connection: local`), Ctrl+Left/Right and F1 (local), F2, F3 to change machine, Ctrl+Up/Down for the history of commands, `help` and Tab by machine (only stored procedures and code on the server on a remote one).

## F-TLS-27 evetx: debugger

Stage: **planned**.

Breakpoints in the gutter and the Breaks tab (remove, double click to jump), Step into, Step out, Continue, Stop, the Watch tab; needs the debugger of the machine (F-TLS-04 b); the same API serves F-TLS-22.

## F-TLS-28 evetx: databases

Stage: **planned**.

A database file in the tree opens a table list in a tab; the data of a table in a new tab; the structure of a table in a dialog that is a grid with headers and bordered cells, a drop-down for the type, a calendar for the default of a date or time, and pages of fields; needs the `db.*` additions ( c, d).

## F-TLS-29 evetx: file card

Stage: **planned**.

A text file opens in the editor as source (Markdown too); any other file, images, SVG, audio and video included, opens a card with its facts and no preview; the rendered view is in eveux.

## F-TLS-30 Service mode

Stage: **drafted**.

`eve -s`: the machine with no user interface, silent, both doors, a log and a pid file; a Windows service under the Service Control Manager, a Linux daemon, or the foreground form (`EVE_SERVICE=foreground`); `-s file.cfg` is the service reading that file, and `-s` takes nothing else; the configuration of a script, a command or a door is `-e file.cfg` (`--setup`), and the command files `.vmc` are removed (2026-10-18).

*Partial (2026-10-17):* the console and foreground forms tested on Windows; the Service Control Manager form compiles, run needs an administrator; the POSIX code compiles for Linux, not run; not yet: Event Log, run as another user, log rotation, `evedb serve -s`.

## F-TLS-31 eveux: source control

Stage: **planned**.

Code started:.

*Moved to level 6 (2026-10-20):* the clients evetx and eveux are developed at level 6; level 7 is the server.
