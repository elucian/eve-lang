# Design: the Eve machine, its command channels, local web serving, the AI API and `service` scripts

Status: the decided points are recorded as **D-083** (`plan/decision_level6.md`) and taught in the tutorial page server.html (2026-10-05). The rest of this note is background and proposals.

**Decided by the author (2026-10-05):** `eve -c <command>` (`--command`) sends a command to a running machine and `eve -x file.eve` parses and executes a script, as today; `-rem <machine>` names a remote machine; the default ports are 4042 for commands and data and 8042 for HTML; a running machine keeps one driver memory space (DMS) per loaded driver; `eve -u file -rem <machine>` uploads a file; an AI may call all the commands; `panic` returns a listening machine or the prompt to waiting; `route` is a keyword; the tutorial gets one page, server.html; `route` has a one-line form (`apply <aspect>`) and a block form (`route name(req, @res) on <method> "<path>" is … end name;`) for every HTTP method. Also: the machine has one mode and starts locally or remotely; a machine is its configuration file, its identity is domain + port and its label is `$EVE_NAME`; starting on a taken address is an error; the checksum of the configuration is kept outside the file; a running machine applies a changed configuration on the command `setup` when its identity stays the same; `eve` runs without a configuration file, with built-in defaults; `eve --setup <folder>` reads the machine in that folder or creates it (configuration file and folders) when it does not exist; there is no separate `make` command; the machine folder holds `eve.cfg`, `web/`, `out/`, `data/`, `lib/`, `asp/`, and the machine is named after the folder; a machine folder is a project folder: one machine per project; a client/server application is two projects, one client and one server, which can live in the same repository with the README files at its root; it receives commands on a port (`--listen`); `eve` itself is the program that sends a command to a running machine (`eve -c <command>`), from a shell or Python script or from another Eve machine; a machine can talk to many machines on different ports and domain names; `serve` gives local HTTP on a configurable port with pages from a configured folder; there is an Eve API usable as an MCP server for AI; the command files (`.vmc`) are scheduled for removal. It answers review points RST-R03 (a `service` script), RMT-D01 (a remote machine has its own rules), RMT-D03 (data over the network, explained), RMT-R03 (a local and a remote scheduler) and RST-D01. Target versions in `plan/version_map.md`: F-TLS-11 (daemon, now `--listen`), F-STR-08, F-NET-02 to F-NET-06. Questions for the author are collected at the end.

## 1. One machine, one mode

There is one Eve virtual machine, `eve`, and it has **one mode**. It starts **locally** (on the user's workstation) or **remotely** (on another host, a server), and in both places it is the same program with the same commands. It does not switch between "client mode" and "server mode": what it does depends only on the commands it receives and on its configuration file.

- A local machine runs scripts, answers the prompt, and may serve web pages on `localhost` (section 5).
- A remote machine is an `eve` started with `--listen` on a host: it waits for commands on a port (section 3), runs deployed projects, schedules drivers, and serves HTTP to other computers.
- A local machine talks to a remote one by sending it commands: deploy a project, run a driver, apply an aspect, exchange data (section 7).

## 2. Where commands come from

The machine is driven by **commands**: the entries of its jump table (`check`, `execute`, `doc`, `load`, `run`, `report`, …, `manual/usage.md`). The same commands arrive through five channels:

| Channel | How | Status |
|---|---|---|
| Command line | `eve --check script.eve`: one command, run by a new machine that exits after it | exists |
| Prompt | `eve` starts the REPL, `eve:> check script.eve`, like a chat prompt that takes commands | exists |
| Port | a running machine started with `--listen` receives commands from the network; `eve -c <command>` sends one (section 3) | new |
| Another machine | a machine sends commands to other machines and reads their answers (section 3) | new |
| API for AI | `eve --api`: the commands as tools of an MCP server, for AI assistants | new, section 6 |

The command files (`eve -i file.vmc`, the slot of D-063) are **removed** (D-188, 2026-10-18): a program that wants to drive a machine with a series of commands talks to it over the stdio door (`eve --stdio`, `vm.open` and `vm.eval`) or the IPC door instead (section 3); `script/workflow.py` does so.

Whatever the channel, a command does the same thing and gives the same answer; only the transport differs.

## 3. Commands over the network: `--listen` and `eve -x`

**Receive.** `eve --listen <port>` (or `eve:> listen <port>`) starts a machine that stays active and accepts commands on that port, from other programs and from other Eve machines. It keeps running until it receives `stop` or the operating system stops it. This replaces the "daemon mode" planned in `manual/usage.md`.

**Send.** `eve` is also the program that sends a command to an active machine: `eve -c <command>` connects to the machine, sends one command, prints the answer, and exits with the status of that command. Each call is one command; a sequence of commands is a sequence of calls:

```
eve --listen 4042 &                 ** start a machine that waits for commands
eve -c "load sales.eve"             ** first command
eve -c "run"                        ** a new command, same machine, same session
eve -c "report"
eve -c "stop"                       ** the machine ends
```

The program that sends the commands is a shell script or a Python script (`subprocess.run(["eve", "-c", "run"])`), which reads the answer and the exit status of each call. This is how the test runner and the workflow scripts will drive the machine once `.vmc` files are removed.

**Which machine.** Without more options `-c` goes to the machine of the configuration file (`-e file.cfg`, section 4): its `$EVE_DOMAIN` and `$EVE_PORT`. A remote machine is given by host and port, or by a name from the configuration:

```
eve -c "run sales_load" -rem etl1.example.com:4042
eve -c "run sales_load" -rem prod        ** "prod" is defined in eve.cfg
```

**Machine to machine.** A running machine can do the same: send many commands to other machines and receive their answers, on different ports and domain names. At the prompt or in a command, `send prod "run sales_load"`; in a script, a library call such as `eve.send("prod", "run sales_load")` returns the answer and the status. A machine keeps one connection per partner, so a long conversation does not reconnect for each command.

**Protocol (first version).** One command per line, the same text as at the prompt; the answer is the text the prompt would show, then an end marker with the exit status. The structured protocol EWP (section 9) comes later on the same port, for remote `apply` and data streams.

**Sessions and driver memory spaces.** One machine has one state, shared by all the commands it receives; two independent sessions in parallel are two machines, with two configuration files (two projects, section 4). Inside a machine, each driver has its own **driver memory space** (DMS): its globals, its loaded modules, the state of its aspects.

- `load sales.eve` creates the DMS of the driver; it stays until `dismiss sales.eve`. `run sales.eve` then reuses it, so a second run sees what the first one left (open connections, caches).
- `run other.eve` for a driver that is not loaded creates a temporary DMS, runs the driver and frees the DMS at the end.
- A machine can hold several loaded drivers at once, each in its own DMS; they never see each other's memory.

A DMS is also the natural unit of memory for the VM: everything a driver allocates is freed together when its DMS is cleared (review RVM-R02).

**Safe by default.** The listener binds to `localhost` unless the configuration names another address; a connection must present the token of the configuration (`$EVE_TOKEN`); over a network it uses TLS.

## 3a. Local, remote and listener: `-loc`, `-rem`, `-lsn` (author, 2026-10-11)

**Revised by D-169 (2026-10-13):** `-lsn [port]` is now `--listen [start|stop|restart|status]`, the same form as `--serve`; the ports come from `eve.cfg` only. The text below keeps the first form as it was decided.

A command of the CLI goes to a machine. Three options choose which one; the short names have three letters, one per option, so they read as words and never clash with the one-letter options `-h -v -d -x -s -m -i -t -c` (options are not bundled, so `-lsn` is one option, not `-l -s -n`). They were `-lo`, `-r` and `-ls` until the revision of the same day (D-162). `-x` alone never looks for a machine: it is the fast way to run a script.

| Option | Long | Meaning |
|---|---|---|
| (none) | | **local**, like `-loc` |
| `-loc [port]` | `--local [port]` | force the command to be local: never uses the network. `--local <port>` addresses the local machine on that port |
| `-rem [domain[:port]]` | `--remote` | find a remote machine and run there. **Fails** if no remote machine is found (exit code, message: to choose). `--remote <domain>` addresses another domain |
| `-lsn [port]` | `--listen` | start a machine that **listens on the IPC channel only**; no HTTP, no UX |
| `--serve` | | start the HTTP/HTTPS server (the files of `web/`, the Eve UX). `-lsn --serve` opens both channels |

**Local command when no machine listens.** `-loc` does not fail: it starts a new machine inside the process, runs the command and exits; when the command is not a complete one (no script, no command) the machine stays in RPC mode, and takes commands. When a machine listens on the IPC channel of that domain and port, the CLI sends the command there and the IPC channel has priority over everything else: it answers at once, with no web overhead.

**Channels.**

1. **IPC**: a Unix domain socket (also on Windows 10 and later; no named pipe), named from the domain and the port: `<runtime dir>/eve-<domain>-<port>.sock`. The messages are JSON-RPC 2.0, one per frame (length first). The file permissions of the socket are the security (owner only). Binding the socket is the singleton lock (section 5): a second machine on the same domain and port fails with `already running`; a socket left by a crash is found by a failed connect and removed. A **remote machine does not listen on IPC by default**; `--ipc` turns it on.
2. **HTTP/HTTPS**: the same JSON-RPC 2.0 messages in `POST /rpc` on the API address, and the pages and the WebSocket of the UX on the web address. Needs a login (D-155) and TLS outside `localhost`.

The two addresses may be split: the API on `api.<domain>:<api port>` and the UX on `<domain>:<web port>` (defaults 4042 and 8042). A reply always travels on the connection of its request; a job that lasts returns a run id and the client reads the result by polling or a WebSocket on the API address (a reply on another address is a callback, not part of this design).

**How the CLI finds the machine.** No port scan. Local: the address is `--local <port>`, else the `eve.cfg` of the project, else the default 4042; the name of the socket follows. Remote: `--remote <domain>` is looked up in the `remote` entries of `eve.cfg` (URL, ports, login), else `https://api.<domain>:<port>`; a bare `--remote` takes the `remote` named in `eve.cfg`, and without one it fails. Login and the keyring: D-155.

A machine never blocks itself: it listens while it runs a script. What several clients may do to the shared state of one machine at the same time is a rule of level 6 (to decide).

Open: the exit code and message of `-rem` without a machine; the exact socket directory per system; the form of `--local <port>` when `eve.cfg` names another domain; whether `-lsn` and `--serve` can be started apart on a machine that already runs (`eve --serve start`).

## 4. Machine identity: configuration, ports, singleton

A machine **is its configuration file**. The file says what the machine is called, where it is, and which ports it uses. Two configuration files make two machines, also on the same computer: this is how a client and a server are tested on one workstation, with different ports.

```
# client.cfg                          # server.cfg
$EVE_NAME      = "etl-client"         $EVE_NAME      = "etl-server"
$EVE_DOMAIN    = "localhost"          $EVE_DOMAIN    = "localhost"
$EVE_PORT      = 4042                 $EVE_PORT      = 4142
$EVE_HTTP_PORT = 8042                 $EVE_HTTP_PORT = 8142
$EVE_WEB       = "web"                $EVE_WEB       = "server/web"
$EVE_OUT       = "out/client"         $EVE_OUT       = "out/server"
$EVE_TOKEN     = "…"                  $EVE_TOKEN     = "…"
```

**Identity.** The identity of a machine is its address: **domain + port**, `$EVE_DOMAIN:$EVE_PORT` (for example `localhost:4142`, `etl1.example.com:4042`). `$EVE_DOMAIN` is `localhost`, a domain name or an IP address. Two programs can't bind the same port on one host, so the address is unique without any checksum. `$EVE_NAME` is the label of the machine: what people, logs, `send` and `-rem` use (`etl-server`); the machine checks at connection time that the name and the address agree. `$EVE_HTTP_PORT` is the port of `serve`.

**Start.** `eve -e server.cfg --listen` (or `--serve`) first checks that the domain and the ports of the configuration are free. If one is already taken, by a running Eve machine or by another program, `eve` ends with an error and does not start. Otherwise it starts the machine, reserves its ports and listens. From then on, any request or command that reaches it, from a browser, a script, another machine or a route, gets an answer.

**Send.** `eve -e server.cfg -c <command>` does not start anything: it connects to the machine at the address of the configuration and sends the command. The running machine keeps its state (loaded scripts, sessions, services) between commands.

```
eve -e server.cfg --listen              ** starts etl-server on localhost:4142 (and 8142 for serve)
eve -e server.cfg --listen              ** error: localhost:4142 is already taken
eve -e server.cfg -c load sales.eve"   ** the command goes to etl-server
eve -e server.cfg -c run"              ** same machine, same state
eve -e client.cfg -c send etl-server \"report\""   ** the client machine talks to the server machine
```

**Checksum.** When a machine reads its configuration file, it computes a checksum of the file and keeps it **outside** the file, in `$EVE_OUT/<name>.sum` (the `out/` folder of the machine). Writing the checksum into the file would change the file, and so the checksum, without end. When the file has no stored checksum, or a different one, `eve` writes the new value into the `.sum` file. The configuration file itself is never written by the machine, so it can be kept under version control.

**Configuration changes while running.** A running machine reads its configuration again only on the command `setup` (`eve -e server.cfg -c "setup"`): it compares the checksum, applies the changes (folders, limits, token, `serve` port, schedules) without a restart, and stores the new checksum. The identity can't change this way: if the domain or the port in the file is now different, the file describes another machine; `setup` reports it and changes nothing, and that new machine is started with `--listen` on its own address.

**Without a configuration file.** `eve` can run with no configuration at all: the default values are built into the machine (name `eve`, domain `localhost`, `--listen` port 4042, `serve` port 8042, folders `web` and `out` in the current folder). Without `-s`, `eve` does its best to execute the command with these values.

**Set up a machine.** `eve --setup <folder>` (short `-e`, D-188) gives the machine its folder. The folder holds everything the machine needs: its configuration file `eve.cfg` and its folders (`web/`, `out/`, `data/`, `lib/`, `asp/`).

- If the folder already holds a configuration, `--setup` reads it: this is how an existing machine is chosen.
- If it does not, `--setup` creates the folder, the configuration file and the folders: a new machine, named after the last folder of the path, with the default values and ports that are free on this computer, so it does not collide with the machines already set up here. The user edits `eve.cfg` if needed.
- `--setup` also accepts the configuration file itself (`-e server/eve.cfg`), as `-e file.cfg` does today.

```
eve --setup ./evemachine/local                  ** creates the machine "local" (or reads it)
eve --setup ./evemachine/server --listen        ** creates or reads "server", then starts it
eve -s ./evemachine/server -c run sales.eve"   ** sends a command to the running "server"
```

The command `setup` at the prompt, or sent with `-c "setup"`, does the same for a running machine: it reads the configuration again (see above). There is one command for creating, choosing and reloading a machine.

**One machine per project.** A machine folder is a project folder (D-073): the drivers, aspects, modules and services of one project, and the configuration of the one machine that runs them. Another project is another machine, with its own domain and port. A client/server application is therefore **two projects**, a client and a server, which can stay in the same repository:

```
sales_app/                  ** one repository
  README.md                 ** the application: what it does, how to start both machines
  client/                   ** project and machine "client"
    eve.cfg                 ** localhost:4042, serve 8042
    sales_load.eve          ** driver: reads files, sends batches to the server
    asp/  lib/  data/  out/  web/
  server/                   ** project and machine "server"
    eve.cfg                 ** etl1.example.com:4142, serve 8142
    orders_api.eve          ** service
    asp/  lib/  data/  out/  web/
```

To test on one workstation, both configurations use `localhost` with different ports; in production `server/eve.cfg` names the server's domain. Deploying the server project to a remote host means copying the `server/` folder there and running `eve --setup server --listen`.

## 5. `serve`: local HTTP

**Dual mode and singleton (author, 2026-10-11).** A machine is a **singleton identified by its domain and port**. When the configuration names `localhost`, another machine can be started on `localhost` with a different port; on one port there is only one machine. The one machine has two doors to the same VM core and the same shared state: a command channel for the CLI clients (`eve -x file.eve`, `eve -c …`) through IPC, a Unix socket or TCP, and an HTTP/WebSocket server for the browser (the files of the web folder, and the Eve UX, `eveux/`).

```
                  ┌────────────────────────────────────────┐
                  │              eve --serve               │
  eve -x file.eve ├───────► IPC / Unix socket / TCP        │
  (CLI client)    │                   │                    │
                  │             EVE VM core                │
                  │           (shared state)               │
                  │                   │                    │
  http://localhost├───────► HTTP / WebSocket server        │
  (browser)       └────────────────────────────────────────┘
```

The command is `eve --serve` (the name stays). If a machine already runs on that domain and port, `eve --serve` **fails** (message `already running`) and does not start a second one. The machine is controlled with `eve --serve stop`, `eve --serve start` and `eve --serve restart`. Open details: the protocol of the command channel (IPC, Unix socket or TCP: to choose), the exit code of a refused start, the keys of `eve.cfg` (`http_port`, `http_host`, `web` are used by the test `e95_web_hello`), how a CLI client finds the running machine, and what `start` means for a machine that is already running (nothing, exit 0?). First test: `test/level5/e95_web_hello`.

`eve:> serve` (or `eve --serve`) starts an HTTP server inside the machine. By default it listens on **http://localhost:8042**; the port is set in the configuration file. It serves:

1. **Static files** from the web folder named in the configuration: HTML pages, CSS, scripts, images, WebAssembly. A request for `/reports/today.html` returns `<web folder>/reports/today.html`.
2. **Services**: routes declared by `service` scripts (section 8), answered by Eve aspects, for example `GET /orders/42` returns JSON.

The machine stays usable while it serves: the prompt keeps accepting commands, and `serve stop` ends the HTTP server. A driver can write HTML files into the web folder (a daily report) and a browser on the same computer reads them at once.

Configuration (sketch; every new `$` name goes to the register `spec/semantics/variables.md` first, D-071):

```
# eve.cfg (the full set is in section 4)
$EVE_HTTP_PORT = 8042          ** port of serve
$EVE_WEB       = "web"         ** folder of the pages that serve returns
$EVE_OUT       = "out"         ** output folder: run logs, files written by drivers
```

## 6. The Eve API: an MCP server for AI

`eve --api` starts the machine as an **MCP server** (Model Context Protocol), so that an AI assistant (Claude Code, Claude Desktop, other MCP clients) can work with Eve directly: check a script, run it, read its errors and its run log, generate its documentation. MCP is an open protocol based on JSON-RPC 2.0; the assistant starts `eve --api` and talks to it on standard input and output, or connects to it over HTTP (on the `serve` port, path `/mcp`).

The API publishes the commands of the jump table as MCP **tools**, with typed parameters and JSON results, plus a few read-only **resources**:

| MCP tool | Command | Result |
|---|---|---|
| `eve_check` | `check <file>` | ok, or the syntax errors with line and column |
| `eve_run` | `execute <file> [args]` | exit code, standard output, errors |
| `eve_doc` | `doc <folder or file> [out]` | the pages written |
| `eve_ast` | `load` + `ast` | the syntax tree, for an AI that reasons about the code |
| `eve_inspect` | `load` + `inspect` | the introspection report |
| `eve_runlog` | — | the lines of a run log of `$EVE_OUT` |
| `eve_serve` | `serve` / `serve stop` | the URL served |

| MCP resource | Content |
|---|---|
| `eve://manual/usage` | the manual of the machine |
| `eve://spec/…` | the specification files (lexical rules, keywords, operators) |
| `eve://project/…` | the scripts of the current project folder |

The API follows the rules of section 10: it works inside the project folder, it can't call the shell unless the configuration allows it, and every run has a time limit. An AI never gets more rights than a user at the prompt.

## 7. What a local machine does with a remote one

| Use | What happens | Example |
|---|---|---|
| **Deploy** | The local machine sends a project (drivers, aspects, modules, services) to the remote one, which checks and compiles it under its own rules and keeps it, with a version. | `eve:> deploy sales_etl to prod` |
| **Upload** | A file is sent to a remote machine, like a `load` there: it is compiled by the remote machine, under its rules, and kept for the next commands. | `eve -u sales_load.eve -rem prod` |
| **Run** | The remote machine runs a driver now, or on its schedule. The caller gets the exit code and the run log. | `eve -c "run sales_load.eve" -rem prod` |
| **Call** | A driver applies an aspect that runs on the remote machine, with its parameters and `@` outputs, as a local `apply` would. | `apply load_orders(batch, @count) at prod within 30s;` |
| **Stream** | A driver sends or receives a large amount of data as a stream of batches, possibly on several connections. | read 10 million rows in batches of 10 000 |
| **Serve** | The remote machine answers HTTP from browsers and other systems: JSON, files, HTML pages. | `GET /orders/42` |

The command forms are examples; the commands are decided with the manual. `prod` is a name from the configuration (address, port, token), never written in a script.

## 8. The `service` script

A service is a fourth kind of script, next to driver, aspect and module. It has no `process main`: it declares **routes**, and each route names an aspect that answers the request. `serve` loads the services of the project and creates a new state of the aspect for every request (the rule of D-066: one `apply`, one new scope), so two requests never share variables.

```eve
# orders service
service orders_api is
  from "lib" use (orders);

  set PAGE = 50;

  route get    "/orders"        apply list_orders;
  route get    "/orders/{id}"   apply get_order;
  route post   "/orders"        apply create_order;

  initialize
    orders.connect($ORDERS_DB);
  finalize
    orders.disconnect();
end orders_api;
```

```eve
# answer GET /orders/{id}
aspect get_order is
  process main(req: Request, @res: Response) is
    new id := req.params["id"];
    new o := orders.find(id);
    if o == null do
      let res.status := 404;
    else
      let res.body := o.json();
    done;
  return;
end get_order;
```

Rules (proposals):

- A service has the shape of a module: declarations, `initialize` and `finalize`, closed by `end name;`. Its private state is shared by all requests, so it follows the module rule: written in `initialize`, then only by unsafe `!` methods (D-081). Most services keep their state in a database.
- A route has two forms, both with the keyword `route`:
  - one line, which names an aspect in its own file: `route <method> "<path>" apply <aspect>;`. The aspect receives a `Request` and fills an `@res: Response`; the same aspect can also run in a driver;
  - a block, which holds the handler code: `route <name>(req: Request, @res: Response) on <method> "<path>" is … end <name>;`. Shorter for small handlers, and the path stays next to the code.
- The method is any HTTP method: `get` (read), `post` (create), `put` (replace), `patch` (change a part), `delete`. `{id}` in the path becomes `req.params["id"]`; the body of a `post`, `put` or `patch` is `req.body`, and `req.json()` reads it as a DataMap.

```eve
# block routes in a service
service orders_api is
  from "lib" use (orders);

  route get_order(req: Request, @res: Response) on get "/orders/{id}" is
    new o := orders.find(req.params["id"]);
    if o == null do
      let res.status := 404;
    else
      let res.body := o.json();
    done;
  end get_order;

  route create_order(req: Request, @res: Response) on post "/orders" is
    new id := orders.create!(req.json());
    let res.status := 201;
    let res.body := {"id": id}.json();
  end create_order;
end orders_api;
```
- Static pages need no route: `serve` returns the files of the web folder (section 5).
- The aspects of a service run in parallel, one per request, on the worker pool (`$cores`). A request waiting for a database gives its core away (D-067).
- An error that the aspect does not recover becomes a response `500`; the message goes to the log, not to the browser.

## 9. Data over the network and protocols

### Data over the network, explained (RMT-D03)

Inside one machine, aspects exchange data through parameters, `@` outputs and channels (D-051). A channel is a queue with a capacity: the sender waits when it is full, the receiver waits when it is empty. That waiting is called **back-pressure**: a fast producer can't flood a slow consumer. Between two machines the same three things are needed:

1. **Parameters and outputs** of a remote `apply`: one message out with the arguments, one message back with the `@` outputs or the error.
2. **A stream**: a sequence of batches (for example 10 000 rows each) over one connection. The receiver tells the sender how many batches it can accept now (a *credit*): the channel capacity over the network.
3. **Parallel streams**: a large transfer split over several connections. Every batch carries its stream number and its sequence number, so the receiver **puts the data together** in order, and after a broken connection the transfer restarts from the last batch received.

```eve
new rows := net.stream(:Order)(node: "prod", name: "orders_2026", batch: 10000);
for batch in rows do
  load(batch);
done;
```

### Protocols

| Partner | Protocol | Port |
|---|---|---|
| Browsers, REST clients, other systems | HTTP, bodies in JSON or HTML | `serve`, 8042 by default |
| `eve -x`, scripts and Eve machines sending commands | the command line, one command per line (first version) | `--listen` |
| Eve machines exchanging data | EWP, the Eve Wire Protocol (later) | `--listen` |
| AI assistants | MCP (JSON-RPC 2.0) | standard input and output, or `/mcp` on the `serve` port |

EWP in plain words: a connection carries **frames**; a frame says its length, its type, which stream it belongs to, then its content. The types are few: `HELLO`, `APPLY`, `RESULT`, `ERROR`, `BATCH`, `CREDIT`, `CANCEL`, `PING`, `CLOSE`. Values travel in a compact binary form, tables column by column. Details: review RNW-R04.

## 10. Rules of a remote machine

The author's point (RMT-D01): code received by a remote machine is compiled and run under that machine's own rules, set in its configuration.

| Rule | Local machine | Remote machine (`--listen`) |
|---|---|---|
| Console | `print`, `read` work | `print` goes to the log; `read` is an error |
| `panic` | at the prompt: ends the script and returns to the prompt; in a one-shot run (`eve -x file.eve`): ends the process, exit code 1 | ends the request or the job, the machine goes back to listening |
| `halt`, debug mode | allowed | never |
| Shell (`call`) | allowed | denied unless the configuration allows it |
| Files | any path the user can open | only the folders of the project (`data/`, `out/`, the web folder) |
| Network, databases | any | only the hosts and databases listed for the project |
| Limits | `$cores`, `$max_parallel` | also memory and time per request, requests in parallel |

The allowed resources of a project are its **capabilities** (review RNW-R08). The machine refuses a deployed script that uses a capability it was not given, before it runs. The API for AI (section 6) follows the same rules on a local machine.

## 11. Schedulers (RMT-R03)

- **Local scheduler**: the worker pool of one machine, which runs started aspects on `$cores` workers and gives a waiting aspect's core to another (D-067, D-081).
- **Remote scheduler**: a machine that listens runs deployed drivers at given times, keeps their run logs (`run_<driver>_<datetime>.log`, D-081), and retries or alerts on failure:

```
# eve.cfg of a remote machine (sketch)
schedule "sales_load"  at "02:00" every day
schedule "orders_sync" every 15min
```

## 12. Security

- **Authentication**: people log in to each remote machine by single sign-on or with an account of that machine, and the local machine keeps the credentials in the keyring of the operating system (section 15, D-155); a token from the configuration (`$EVE_TOKEN`) or a TLS client certificate for machines and scripts.
- **Authorization**: the configuration says who may deploy, run or call which project, and which routes of `serve` are public.
- **Secrets**: never in scripts; given to a project as `Secret` values (review RIO-R01), which never print and never travel back.
- **Local first**: `--listen`, `serve` and the API bind to `localhost` unless the configuration opens them to the network.

## 13. What changes

| Change | Kind |
|---|---|
| Commands `listen`, `send`, `serve`, `api`, `deploy`, `dismiss` (replaces `clear`) (and `--listen`, `--serve`, `--api`); `eve -c <command> [-rem machine]` | machine (`manual/usage.md`) |
| Command files `.vmc`, option `-i`, "serve mode" of D-063 | removed (D-188); `script/workflow.py` uses `eve --stdio` |
| `$EVE_NAME`, `$EVE_DOMAIN`, `$EVE_PORT`, `$EVE_HTTP_PORT`, `$EVE_WEB`, `$EVE_TOKEN`; the checksum file `out/<name>.sum` of the machine folder | configuration, system variables |
| Command `setup` (`--setup <folder or file>`, `-e`): create, choose or reload a machine | machine |
| Script kind `service`, keyword `route` | syntax |
| `apply … at <node> [within <time>];` | syntax, remote apply |
| Classes `Request`, `Response`; `net.stream` | library (`http`, `net`) |

## 14. Order of work

1. `serve` with static files from the web folder: the smallest useful step, it lets drivers publish HTML reports locally.
2. `--api`: the MCP server over standard input and output, with `eve_check`, `eve_run`, `eve_doc`; it reuses the jump table.
3. `--listen` with the line protocol and the token, and `eve -x` to send commands; then the `.vmc` slot is removed and `test/smoke` and `script/workflow.py` use `eve -x`; `send` between machines, `deploy` and `run`; the remote scheduler.
4. `service` scripts and routes in `serve`.
5. The HTTP client in scripts (`http`, `json`), remote `apply`, then EWP streams.

## 15. One local machine, many remote machines: login, single sign-on, keyring

**Decided by the author (2026-10-10, D-155):** the Eve virtual machine (`evevm`, written in Zig) is a full machine that, from one local instance, works with many remote machines at once. Each remote machine is entered with its own connection credentials; a person logs in by **single sign-on**, and the local machine keeps the credentials in the **keyring of the operating system** (Windows, Linux) after the first login. The details below are proposals (Q-048).

### 15.1 Connections

The configuration of a local machine names the remote machines it works with, by address, never with a secret:

```
# eve.cfg of a local machine (sketch)
machine prod at "etl1.example.com:4042" login sso
machine etl2 at "etl2.example.com:4042" login password
machine test at "localhost:4142"        login token
```

- The local machine keeps **one connection per remote machine**, opened on first use and kept open (TLS over the network); `send prod "…"`, `eve -c … -rem prod`, uploads and the Workbench share it.
- Each connection has its **own session**: the user, the role and the rights on that machine. Being admin on `dev1` gives nothing on `prod`.
- A connection that breaks is opened again with the stored credentials, without asking the person, as long as they are valid.

### 15.2 Login

| Method | How | What the remote machine sees |
|---|---|---|
| `sso` | the local machine opens the page of the identity provider in the browser (OpenID Connect, authorization code with PKCE; the device code on a computer without a browser); the person signs in there, with the provider's second factor | a signed identity token of the provider, which it checks against the providers it trusts |
| `password` | user name and password of an account of the remote machine, sent once over TLS | the password, once; it answers with a session token |
| `token` | a machine token (`$EVE_TOKEN`), for scripts, schedules and machine-to-machine calls | the token |

In every method the remote machine answers with **its own credentials**: a short session token and a longer **renewal token**, bound to this user and this local machine. The password and the identity token of the provider are never stored.

Commands of the machine (also options of `eve`):

```
eve:> login prod              ** first login: opens the single sign-on page, or asks for the password
eve:> logout prod             ** ends the session on prod and deletes the stored credentials
eve:> forget prod             ** deletes the stored credentials only
eve:> whoami prod             ** user, role and login method on prod
eve -c "run sales.eve" -rem prod --login  ** log in first when no credentials are stored
```

### 15.3 The keyring

After the first login the local machine stores the **renewal token** (never a password) in the credential store of the operating system, under the identity of the remote machine (domain + port, section 4) and the user:

| System | Store | Interface used by `evevm` |
|---|---|---|
| Windows | Credential Manager | `CredWriteW`, `CredReadW`, `CredDeleteW` of `advapi32` (target `eve:etl1.example.com:4042:ana`) |
| Linux | Secret Service (GNOME Keyring, KWallet) | the D-Bus API `org.freedesktop.secrets` (collection `login`, attributes `eve-machine`, `eve-user`) |
| macOS (later) | Keychain | `SecItemAdd`, `SecItemCopyMatching` |

- The next connection reads the token from the keyring and renews it in the background; the person sees no form until the token is revoked or expires (30 days without use, by default; the remote machine decides).
- The keyring is unlocked by the login of the operating system, so the secret is protected by the session of the person, not by a file of Eve.
- **Without a keyring** (a Linux server without a desktop session), the machine asks at each start, or uses a machine token from the environment; it never writes a token to a plain file (question 3 of Q-048).

### 15.4 Users of a remote machine

A listening machine keeps its **users and roles** in its Eve database (SQLite, F-DAT-08): the accounts, their roles (`viewer`, `operator`, `developer`, `admin`), the identity providers it trusts, the mapping of provider groups to roles, the registration setting (`closed`, `approval`, `open`), the sessions and the audit log. The first admin is created on its own console by `eve --setup`; the other accounts by its admins (`user add`, `user role`, `session end`), from the prompt, from `eve -c … -rem`, or from the Workbench (eveux, D-154). The token of the configuration (`$EVE_TOKEN`) stays for machines and scripts; people log in.

## 16. Credentials, connect, upload, and the selected machine (D-171)

**Decided by the author (2026-10-13, D-171, details in Q-051).** This section completes §15 for the first version: two ways to give credentials, the commands `--connect` and `--upload`, and the machine chosen in the REPL.

### 16.1 Credentials: two methods

| Method | Where the secret is | When |
|---|---|---|
| **`eve.env`** | a JSON file of the project with one entry per machine; not versioned (in `.gitignore`); one file per project | the file has an entry for the machine |
| **dialog** | two prompts: the user name in clear, the password hidden with stars; never on a command line | there is no entry |

Single sign-on is level 7 (D-172). The shape of `eve.env` (Q-052 d): `{ "prod": { "user": "ana", "password": "…" } }`. The secret never goes into a script nor into `eve.cfg` (§12).

### 16.2 From a command line

```
eve --connect prod                      ** open the connection: eve.env, or the dialog; a session token is kept, not the password
eve --upload                            ** send web/, proc/, sql/, server/ and the modules they import to prod (Q-052 a)
eve -rem prod db install                ** install the database on prod
eve -rem prod db migrate                ** migrate it
eve -rem prod run sales_load.eve        ** run a program that is already on prod
```

- `--upload` without a connection is an error that says to `--connect` first.
- A command reaches a remote machine **only with `-rem`**. Without it the command is local.
- A remote machine runs only a program that exists on it. `run x.eve -rem prod` where `x.eve` was never uploaded is refused (Q-051 k); the local file is not sent as a side effect.

### 16.3 In the REPL

The REPL has a **selected machine**, `local` at the start.

```
eve:> select prod        ** the commands now go to prod
eve:> select local
```

- **Status bar:** `Ready: connection: local` or `Ready: connection: prod`; while a command runs, `Running…` and the machine too, so it is always clear where a command runs.
- **Ctrl+Left, Ctrl+Right** change the selected machine in turn: local, remote1, remote2, … (Q-051 h). **F1** selects the local machine, **F2** a remote machine, **F3** another machine (D-172).
- **Ctrl+Up, Ctrl+Down** show the previous and the next command issued, to edit and send again.
- **`help`** shows the commands that make sense for the selected machine: on a remote one, not the local file and check commands.
- **Tab** on a remote machine completes the stored procedures and the code on the server (D-172 point 7), not the local files.
- The REPL is started by `eve`; the terminal UI by `eve -tx` (screen: `evetx/design/design.svg`), the web UI by `eve -ux` (D-172).
- A program that was not uploaded cannot be run on a remote machine.

## 17. Service mode: `eve -s` (D-185, 2026-10-17)

Until level 5 `eve` was a command line, a REPL, or a graphic interface (`-ux`, `-tx`). A server needs a fourth way: **no interface at all**. `eve -s` starts the machine as a **service**: no prompt, nothing written on the standard output, the log in a file, the doors of `eve.cfg` open (IPC and HTTP). On Windows it is a **service** of the Service Control Manager; on Linux and macOS it is a **daemon** that a shell or an init system starts.

**The option.** `-s` used to mean `-s file.cfg`, the configuration file (F-STR-06). The author decided (2026-10-17) that bare `-s` is the service, and then (2026-10-18, D-188) that `-s` is **only** the service: the configuration file is `-e file.cfg` (`--setup file.cfg`). The reading:

| Command line | Meaning |
|---|---|
| `eve -s` | the service, configuration `eve.cfg` of the working folder |
| `eve -s file.cfg` | the service, configuration `file.cfg` (a file name that ends in `.cfg`) |
| `eve -s file.cfg script.eve`, `eve -s file.cfg --check a.eve`, `eve --listen -s file.cfg` | a usage error (exit 64): `-s` takes nothing else (D-188) |
| `eve -e file.cfg script.eve`, `eve -e file.cfg --check a.eve`, `eve --listen -e file.cfg` | the configuration only |
| `eve -s -db --serve evedb.cfg` | evedb as a service (D-186) |

A consequence to know: `eve -s file.cfg` used to open the REPL with that configuration; it now starts the service. The REPL with a configuration file is `eve -e file.cfg` (D-188).

**Three ways to start, one machine.**

| Start | What happens |
|---|---|
| from a console or a shell: `eve -s` | the machine is started in a **process of its own**, detached from the terminal (no console window on Windows; a new process group on POSIX systems, `SIGHUP` ignored), with its output in the log file; `eve -s` waits until the IPC door answers, prints **nothing** and ends with status 0. If a machine runs already: `already running` on the error output, status 75. If it does not start in ten seconds: the last lines of the log on the error output, status 69 |
| by the Service Control Manager | `eve.exe -s [file.cfg]` is registered as the service; the process calls `StartServiceCtrlDispatcher`, reports `START_PENDING` and then `RUNNING`, runs the machine in the process, and reports `STOPPED` when Windows asks it to stop (`STOP` and `SHUTDOWN` controls) |
| in the foreground: `EVE_SERVICE=foreground eve -s` | the process **is** the machine (for a container, or `Type=simple` of systemd); it ends with status 0 on `SIGTERM`, `SIGINT` or `vm.stop`, and stays in the foreground of its parent |

How the process knows it was started by the Service Control Manager: it asks for the dispatcher first; outside the Service Control Manager Windows answers error 1063 and the second form is used.

**What the service does.**

- **Silent.** Nothing on the standard output or the standard error once the machine runs; the only place for messages is the log. The starter (`eve -s` from a console) writes to the error output only when it fails.
- **Log.** `<runtime>/eve-<domain>-<ipc_port>.log` (the same file as `evevm start`): the doors, one line per request, the stop. The file is made new at each start.
- **Pid file.** `<runtime>/eve-<domain>-<ipc_port>.pid` with the pid and a line break, written when the machine is up and removed when it stops. On POSIX systems the starter writes it too (so `Type=forking` with `PIDFile=` works). Windows does not need it.
- **Doors.** Both, as `--listen --serve`: the IPC door for the local CLI and the IDEs, the HTTP door for browsers and remote machines (`http_host` of the configuration, `localhost` by default: a service on a server sets it).
- **Stop.** Any of: `eve --serve stop` (or `--listen stop`, `evevm stop`, the method `vm.stop`), `sc stop eve` on Windows, `SIGTERM` or `SIGINT` in the foreground form, `systemctl stop`. The scripts that run are told to stop at their next statement (`vm.cancel`), the doors close, the socket file and the pid file are removed.
- **One machine.** A second `eve -s` on the same `domain:ipc_port` finds the first and ends with `already running`.

**Install recipes.**

```
:: Windows (an elevated prompt); the name is the one the Service Control Manager shows
sc create eve binPath= "C:\eve\bin\eve.exe -s C:\eve\eve.cfg" start= auto DisplayName= "Eve machine"
sc description eve "The Eve machine: scripts, the IPC door and the HTTP door"
sc failure eve reset= 86400 actions= restart/5000/restart/30000//
sc start eve        :: and: sc stop eve, sc delete eve
```

```
# Linux: /etc/systemd/system/eve.service (the daemon form)
[Unit]
Description=The Eve machine
After=network.target
[Service]
Type=forking
ExecStart=/opt/eve/bin/eve -s /etc/eve/eve.cfg
PIDFile=/run/eve-localhost-4042.pid
Environment=XDG_RUNTIME_DIR=/run
Restart=on-failure
[Install]
WantedBy=multi-user.target
# the foreground form instead: Type=simple, Environment=EVE_SERVICE=foreground, no PIDFile
```

A service has no user: it runs as `LocalSystem` on Windows unless `sc config eve obj= …` says otherwise, and as the user of the unit file on Linux. The machine does not drop privileges itself (question C).

**evedb.** The database server (`evedb/README.md`) will take the same option, `evedb serve -s`, with the same three forms, in version 0.2: the code is `evevm/src/service.zig`, to move into the shared folder `modules/` (question D).

**Tests.** `python script/service_check.py`: start from a console (silent, status 0, both doors), the second start, the stop, the log, the foreground form (silent, pid file, clean stop), `SIGTERM` on POSIX systems, and the Service Control Manager (create, start, query, stop, delete) when the script runs elevated. Unit tests of the option: `cmd/cli.zig`, "options: -s is the service or the configuration file". *State of 2026-10-17:* the console form, the foreground form and the log and pid file are tested on Windows; the Service Control Manager form compiles and is not yet run (the test machine had no administrator rights); the POSIX code compiles for `x86_64-linux-gnu` and is not yet run.

**Questions for the author (service mode).** **(A)** The REPL with a configuration file. Bare `eve -s file.cfg` is now the service. Should the REPL with a file get an option (for example `--repl`, or `-s file.cfg -i`... the letters are taken), or is `setup file.cfg` at the prompt enough? **(B)** The foreground form is selected by the variable `EVE_SERVICE=foreground`, because an option would be new syntax. Keep the variable, or choose an option (`--foreground`)? **(C)** Run as another user, drop privileges, and the Windows Event Log (start, stop, errors) instead of only the file: wanted in version 0.5? **(D)** `evedb serve -s` in 0.2 and `modules/service` as the shared code: agreed? **(E)** Rotation of the log (size or day) and a restart policy of the machine itself (the init system restarts it today): needed now?

## Questions for the author

Answered on 2026-10-05 (recorded above): `panic` (a listening machine or the prompt goes on; the `eve -c` process ends with exit code 1 so the calling script sees the failure), the words `service`, `route`, `at`, `-c` sends a command and `-x` executes a file, `-rem` (`--remote`) names a remote machine, ports 4042 (commands, uploads and later the data protocol EWP, all on one port) and 8042 (HTML), the web folder, sessions and driver memory spaces, the AI may call all the commands, the deploy unit, source is uploaded with `-u` and compiled remotely, routes in two forms (one line or a block) for every HTTP method, the command `dismiss` frees the DMS of a loaded driver (it replaces the planned `clear`), one tutorial page, server.html.

