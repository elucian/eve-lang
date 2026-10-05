# Design: the Eve machine, its command channels, local web serving, the AI API and `service` scripts

Status: the decided points are recorded as **D-083** (`plan/decision_level2.md`) and taught in the tutorial page server.html (2026-10-05). The rest of this note is background and proposals.

**Decided by the author (2026-10-05):** `eve -c <command>` (`--command`) sends a command to a running machine and `eve -x file.eve` parses and executes a script, as today; `-r <machine>` names a remote machine; the default ports are 4042 for commands and data and 8042 for HTML; a running machine keeps one driver memory space (DMS) per loaded driver; `eve -u file -r <machine>` uploads a file; an AI may call all the commands; `panic` returns a listening machine or the prompt to waiting; `route` is a keyword; the tutorial gets one page, server.html; `route` has a one-line form (`apply <aspect>`) and a block form (`route name(req, @res) on <method> "<path>" is … end name;`) for every HTTP method. Also: the machine has one mode and starts locally or remotely; a machine is its configuration file, its identity is domain + port and its label is `$EVE_NAME`; starting on a taken address is an error; the checksum of the configuration is kept outside the file; a running machine applies a changed configuration on the command `setup` when its identity stays the same; `eve` runs without a configuration file, with built-in defaults; `eve --setup <folder>` reads the machine in that folder or creates it (configuration file and folders) when it does not exist; there is no separate `make` command; the machine folder holds `eve.cfg`, `web/`, `out/`, `data/`, `lib/`, `asp/`, and the machine is named after the folder; a machine folder is a project folder: one machine per project; a client/server application is two projects, one client and one server, which can live in the same repository with the README files at its root; it receives commands on a port (`--listen`); `eve` itself is the program that sends a command to a running machine (`eve -c <command>`), from a shell or Python script or from another Eve machine; a machine can talk to many machines on different ports and domain names; `serve` gives local HTTP on a configurable port with pages from a configured folder; there is an Eve API usable as an MCP server for AI; the command files (`.vmc`) are scheduled for removal. It answers review points RST-R03 (a `service` script), RMT-D01 (a remote machine has its own rules), RMT-D03 (data over the network, explained), RMT-R03 (a local and a remote scheduler) and RST-D01. Target versions in `plan/version_map.md`: F-TLS-11 (daemon, now `--listen`), F-STR-08, F-NET-02 to F-NET-06. Questions for the author are collected at the end.

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

The command files (`eve -i file.vmc`, the slot of D-063) are **scheduled for removal**: a script that wants to drive a machine sends commands to its port instead (section 3).

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

**Which machine.** Without more options `-c` goes to the machine of the configuration file (`-s file.cfg`, section 4): its `$EVE_DOMAIN` and `$EVE_PORT`. A remote machine is given by host and port, or by a name from the configuration:

```
eve -c "run sales_load" -r etl1.example.com:4042
eve -c "run sales_load" -r prod          ** "prod" is defined in eve.cfg
```

**Machine to machine.** A running machine can do the same: send many commands to other machines and receive their answers, on different ports and domain names. At the prompt or in a command, `send prod "run sales_load"`; in a script, a library call such as `eve.send("prod", "run sales_load")` returns the answer and the status. A machine keeps one connection per partner, so a long conversation does not reconnect for each command.

**Protocol (first version).** One command per line, the same text as at the prompt; the answer is the text the prompt would show, then an end marker with the exit status. The structured protocol EWP (section 9) comes later on the same port, for remote `apply` and data streams.

**Sessions and driver memory spaces.** One machine has one state, shared by all the commands it receives; two independent sessions in parallel are two machines, with two configuration files (two projects, section 4). Inside a machine, each driver has its own **driver memory space** (DMS): its globals, its loaded modules, the state of its aspects.

- `load sales.eve` creates the DMS of the driver; it stays until `dismiss sales.eve`. `run sales.eve` then reuses it, so a second run sees what the first one left (open connections, caches).
- `run other.eve` for a driver that is not loaded creates a temporary DMS, runs the driver and frees the DMS at the end.
- A machine can hold several loaded drivers at once, each in its own DMS; they never see each other's memory.

A DMS is also the natural unit of memory for the VM: everything a driver allocates is freed together when its DMS is cleared (review RVM-R02).

**Safe by default.** The listener binds to `localhost` unless the configuration names another address; a connection must present the token of the configuration (`$EVE_TOKEN`); over a network it uses TLS.

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

**Identity.** The identity of a machine is its address: **domain + port**, `$EVE_DOMAIN:$EVE_PORT` (for example `localhost:4142`, `etl1.example.com:4042`). `$EVE_DOMAIN` is `localhost`, a domain name or an IP address. Two programs can't bind the same port on one host, so the address is unique without any checksum. `$EVE_NAME` is the label of the machine: what people, logs, `send` and `-r` use (`etl-server`); the machine checks at connection time that the name and the address agree. `$EVE_HTTP_PORT` is the port of `serve`.

**Start.** `eve -s server.cfg --listen` (or `--serve`) first checks that the domain and the ports of the configuration are free. If one is already taken, by a running Eve machine or by another program, `eve` ends with an error and does not start. Otherwise it starts the machine, reserves its ports and listens. From then on, any request or command that reaches it, from a browser, a script, another machine or a route, gets an answer.

**Send.** `eve -s server.cfg -c <command>` does not start anything: it connects to the machine at the address of the configuration and sends the command. The running machine keeps its state (loaded scripts, sessions, services) between commands.

```
eve -s server.cfg --listen              ** starts etl-server on localhost:4142 (and 8142 for serve)
eve -s server.cfg --listen              ** error: localhost:4142 is already taken
eve -s server.cfg -c load sales.eve"   ** the command goes to etl-server
eve -s server.cfg -c run"              ** same machine, same state
eve -s client.cfg -c send etl-server \"report\""   ** the client machine talks to the server machine
```

**Checksum.** When a machine reads its configuration file, it computes a checksum of the file and keeps it **outside** the file, in `$EVE_OUT/<name>.sum` (the `out/` folder of the machine). Writing the checksum into the file would change the file, and so the checksum, without end. When the file has no stored checksum, or a different one, `eve` writes the new value into the `.sum` file. The configuration file itself is never written by the machine, so it can be kept under version control.

**Configuration changes while running.** A running machine reads its configuration again only on the command `setup` (`eve -s server.cfg -c "setup"`): it compares the checksum, applies the changes (folders, limits, token, `serve` port, schedules) without a restart, and stores the new checksum. The identity can't change this way: if the domain or the port in the file is now different, the file describes another machine; `setup` reports it and changes nothing, and that new machine is started with `--listen` on its own address.

**Without a configuration file.** `eve` can run with no configuration at all: the default values are built into the machine (name `eve`, domain `localhost`, `--listen` port 4042, `serve` port 8042, folders `web` and `out` in the current folder). Without `-s`, `eve` does its best to execute the command with these values.

**Set up a machine.** `eve --setup <folder>` (short `-s`) gives the machine its folder. The folder holds everything the machine needs: its configuration file `eve.cfg` and its folders (`web/`, `out/`, `data/`, `lib/`, `asp/`).

- If the folder already holds a configuration, `--setup` reads it: this is how an existing machine is chosen.
- If it does not, `--setup` creates the folder, the configuration file and the folders: a new machine, named after the last folder of the path, with the default values and ports that are free on this computer, so it does not collide with the machines already set up here. The user edits `eve.cfg` if needed.
- `--setup` also accepts the configuration file itself (`-s server/eve.cfg`), as `-s file.cfg` does today.

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
| **Upload** | A file is sent to a remote machine, like a `load` there: it is compiled by the remote machine, under its rules, and kept for the next commands. | `eve -u sales_load.eve -r prod` |
| **Run** | The remote machine runs a driver now, or on its schedule. The caller gets the exit code and the run log. | `eve -c "run sales_load.eve" -r prod` |
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

- **Authentication**: a token from the configuration (`$EVE_TOKEN`) for `--listen` and remote calls, or a TLS client certificate between machines.
- **Authorization**: the configuration says who may deploy, run or call which project, and which routes of `serve` are public.
- **Secrets**: never in scripts; given to a project as `Secret` values (review RIO-R01), which never print and never travel back.
- **Local first**: `--listen`, `serve` and the API bind to `localhost` unless the configuration opens them to the network.

## 13. What changes

| Change | Kind |
|---|---|
| Commands `listen`, `send`, `serve`, `api`, `deploy`, `dismiss` (replaces `clear`) (and `--listen`, `--serve`, `--api`); `eve -c <command> [-r machine]` | machine (`manual/usage.md`) |
| Command files `.vmc`, option `-i`, "serve mode" of D-063 | removed; the tests in `test/vm` and `script/workflow.py` move to `eve -x` |
| `$EVE_NAME`, `$EVE_DOMAIN`, `$EVE_PORT`, `$EVE_HTTP_PORT`, `$EVE_WEB`, `$EVE_TOKEN`; the checksum file `out/<name>.sum` of the machine folder | configuration, system variables |
| Command `setup` (`--setup <folder or file>`, `-s`): create, choose or reload a machine | machine |
| Script kind `service`, keyword `route` | syntax |
| `apply … at <node> [within <time>];` | syntax, remote apply |
| Classes `Request`, `Response`; `net.stream` | library (`http`, `net`) |

## 14. Order of work

1. `serve` with static files from the web folder: the smallest useful step, it lets drivers publish HTML reports locally.
2. `--api`: the MCP server over standard input and output, with `eve_check`, `eve_run`, `eve_doc`; it reuses the jump table.
3. `--listen` with the line protocol and the token, and `eve -x` to send commands; then the `.vmc` slot is removed and `test/vm` and `script/workflow.py` use `eve -x`; `send` between machines, `deploy` and `run`; the remote scheduler.
4. `service` scripts and routes in `serve`.
5. The HTTP client in scripts (`http`, `json`), remote `apply`, then EWP streams.

## Questions for the author

Answered on 2026-10-05 (recorded above): `panic` (a listening machine or the prompt goes on; the `eve -c` process ends with exit code 1 so the calling script sees the failure), the words `service`, `route`, `at`, `-c` sends a command and `-x` executes a file, `-r` (`--remote`) names a remote machine, ports 4042 (commands, uploads and later the data protocol EWP, all on one port) and 8042 (HTML), the web folder, sessions and driver memory spaces, the AI may call all the commands, the deploy unit, source is uploaded with `-u` and compiled remotely, routes in two forms (one line or a block) for every HTTP method, the command `dismiss` frees the DMS of a loaded driver (it replaces the planned `clear`), one tutorial page, server.html.

