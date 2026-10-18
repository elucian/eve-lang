# test/project: a live Eve machine to try by hand

This folder is **not a test**: the runner never runs it. It is one Eve project, made by `eve --project init`, where you start a real machine and talk to it with the commands of the CLI and with a browser, to see how the machine reacts and to ask for improvements. The rules are in [`spec/library/machine.md`](../../spec/library/machine.md) (D-162); the automatic tests of the same rules are in [`test/level5/e95_web_hello`](../level5/e95_web_hello/readme.md). The old content of this folder, the shell test of `project init`, moved to [`test/scaffold`](../scaffold/readme.md).

Every output below was captured from real runs on Windows 11 (2026-10-11).

## Setup

Build the VM once (from the root of the repository), then open **two terminals in this folder**: the machine reads `eve.cfg` of the current folder, so always run `eve` from `test/project`.

```
cd evevm && zig build -p ..          # installs bin/eve.exe
cd ../test/project
```

Make `eve` short in both terminals:

```
Set-Alias eve ..\..\bin\eve.exe      # PowerShell
alias eve=../../bin/eve.exe          # Git Bash
```

Terminal 1 holds the machine: it stays active and prints its log. Terminal 2 sends the commands. Stop the machine with `eve --serve stop` from terminal 2, or Ctrl+C in terminal 1 (the next start removes the socket that Ctrl+C leaves behind).

## The project

```
test/project/
  eve.cfg            domain localhost, ipc_port 4042, http_port 8042, web "web", remote "127.0.0.1:8042"
  project.eve        the main script of the project
  src/hello.eve      prints two lines
  src/args.eve       prints its arguments
  src/slow.eve       takes 5 seconds (one line per second)
  src/fail.eve       an error that nobody recovers (exit code 4)
  src/broken.eve     a syntax error (exit code 65)
  src/report.eve     writes web/report.html, served at once by the HTTP door
  web/index.html     the page: Hello World, This is Eve, the status of the machine, a box to run Eve code
  web/css/style.css
  web/js/app.js      plain JavaScript: JSON-RPC calls to POST /rpc
  asp/ lib/ data/ db/ doc/ log/ meta/ test/   the standard layout (empty)
```

## 1. No machine yet

Without a machine, a script runs in the process of `eve`, as always. The commands that need a machine say so and end with **69**.

```
> eve -x src/hello.eve
Hello from Eve
2 + 3 = 5

> eve -loc -x src/hello.eve          # --local: no machine on IPC, so this process runs it
Hello from Eve
2 + 3 = 5

> eve --serve status
eve: not running                     (exit 69)

> eve -loc --serve status
eve: no local machine                (exit 69)

> eve -rem -x src/hello.eve          # --remote never runs locally: it fails
eve: no remote machine at 127.0.0.1:8042    (exit 69)

> eve -rem 127.0.0.1:9999 -x src/hello.eve
eve: no remote machine at 127.0.0.1:9999    (exit 69)
```

`-rem` without an address uses `remote` of `eve.cfg`. On Windows an answer "nobody there" through HTTP takes about 2 seconds (the system retries a refused connection to `localhost`); through IPC it takes about 50 ms.

## 2. IPC only: `eve --listen`

The machine opens the IPC door (a Unix socket) and no web door.

```
terminal 1> eve --listen
eve: ipc localhost:4042
```

```
terminal 2> eve --serve status
machine: localhost ipc=4042 http=8042
ipc: listening
http: off
runs: 0

> eve -loc -x src/hello.eve          # runs in the machine, through IPC
Hello from Eve
2 + 3 = 5

> eve -loc -x src/args.eve one two
2 argument(s)
- one
- two

> eve --serve status                 # the machine counted both scripts
...
runs: 2

> eve -rem -x src/hello.eve          # HTTP is off: remote fails
eve: no remote machine at 127.0.0.1:8042    (exit 69)

> eve --listen                       # a second machine on the same port
eve: already running (ipc localhost:4042)   (exit 75)

> eve -loc --serve stop
eve: stopped
```

Terminal 1 shows the log of the machine, one line per request, and the machine ends:

```
eve: ipc status
eve: ipc run hello.eve: exit 0, 1 ms
eve: ipc run args.eve: exit 0, 1 ms
eve: ipc status
eve: ipc stop
```

## 3. HTTP only: `eve --serve`, the web server

```
terminal 1> eve --serve
eve: http http://localhost:8042
```

Open **http://localhost:8042** in a browser. The page says *Hello World* and *This is Eve*, shows the status of the machine (refreshed every 2 seconds), and has a box where you type Eve code and press **Run**: the code runs in the machine, and its output and exit code come back to the page. Try a `raise "x";` or a syntax error in the box. Then:

- http://localhost:8042/css/style.css: served as `text/css`
- http://localhost:8042/report.html: 404 until you run `src/report.eve` (section 6)
- http://localhost:8042/eve.cfg: always 404, only the `web/` folder is served

```
terminal 2> eve --serve status
machine: localhost ipc=4042 http=8042
ipc: off
http: listening
runs: 0

> eve -loc --serve status            # --local needs IPC, and IPC is off
eve: no local machine                (exit 69)

> eve -loc -x src/hello.eve          # no IPC: this process runs it, the machine does not count it
Hello from Eve
2 + 3 = 5

> eve -rem -x src/hello.eve          # remote: the text of the script goes over HTTP
Hello from Eve
2 + 3 = 5

> eve --serve                        # a second web server on the same port
eve: already running (http localhost:8042)  (exit 75)
```

Terminal 1 also logs the pages: `eve: http GET /: 200`, `eve: http GET /css/style.css: 200`, `eve: http GET /eve.cfg: 404`, and every call of the page: `eve: http vm.stat`.

## 4. Both doors: `eve --listen --serve`

```
terminal 1> eve --listen --serve
eve: ipc localhost:4042
eve: http http://localhost:8042
```

Now the CLI uses IPC by default (fast) and the browser and `-rem` use HTTP. The log tells which door each request used:

```
terminal 2> eve -loc -x src/hello.eve     →  terminal 1: eve: ipc run hello.eve: exit 0, 1 ms
            eve -rem -x src/hello.eve     →  terminal 1: eve: http run hello.eve: exit 0, 1 ms
            eve -x src/hello.eve          →  no line: without -loc or -rem, -x runs in this process
```

`eve --serve status` shows `ipc: listening`, `http: listening`, and `eve --listen` and `eve --serve` both answer `already running` (exit 75). `eve --listen status` and `eve --listen stop` speak through the IPC door only; `eve --serve status` and `stop` try IPC, then HTTP.

## 5. Local and remote execution, what comes back

The output of a script that runs in the machine comes back to your terminal, its errors come back on the error output, and `eve` ends with the exit code of the script. The script runs in the folder of the **machine**, not of the client: on a real remote machine, its files are the files over there.

```
> eve -rem -x src/args.eve one two   # the arguments travel with the script
2 argument(s)
- one
- two

> eve -rem -x src/fail.eve
before the error
fail.eve:5: error 4: something went wrong
  line 5 in driver fail                      (exit 4)

> eve -rem -x src/broken.eve         # the machine refuses a script that does not parse
broken.eve:5:14: error: unexpected ';' in an expression    (exit 65)
```

| Command | Where the script runs |
|---|---|
| `eve -x f.eve` | in this process, always, at once: no IPC or HTTP lookup (the fast way) |
| `eve -loc -x f.eve` | in the machine through IPC; without IPC, in this process (never the network) |
| `eve -rem -x f.eve` | in the machine of `remote` (`eve.cfg`) through HTTP; nobody there: exit 69 |
| `eve -rem host:port -x f.eve` | in the machine at that address through HTTP; nobody there: exit 69 |

## 6. Publish a page from a script

```
> eve -rem -x src/report.eve
report: web/report.html written (4 rows)
open http://localhost:8042/report.html
```

Reload http://localhost:8042/report.html: the page is there at once, written by the script into the web folder of the machine. (`web/report.html` is ignored by git.)

## 7. One script at a time

The machine runs one script at a time; a second one waits for its turn. With the machine of section 4, start the slow script in terminal 2 and, within 5 seconds, a short one in a third terminal:

```
terminal 2> eve -loc -x src/slow.eve       # prints second 1 … second 5, slow: done
terminal 3> eve -rem -x src/hello.eve      # answers only after slow.eve ended
```

The log shows the wait:

```
eve: ipc run slow.eve: exit 0, 5025 ms
eve: http run hello.eve: exit 0, 0 ms (waited 4712 ms for another script)
```

## 8. Stop, restart, a second machine

```
> eve --serve stop                   # ends the machine (exit 0); then status says: eve: not running (69)
> eve --serve restart                # stops the machine and starts it again HERE, with the same doors
eve: stopped, starting again
eve: ipc localhost:4042
eve: http http://localhost:8042
```

`restart` makes the terminal where you typed it the new machine: it does not return. With no machine running, it starts like `--serve`.

A second machine runs next to the first on another IPC port, named in another configuration file (`second.cfg` of this folder: `ipc_port = 4043`); `-loc <port>` addresses it:

```
terminal 3> eve -e second.cfg --listen
eve: ipc localhost:4043

terminal 2> eve -loc 4043 --serve status
machine: localhost ipc=4043 http=8042
ipc: listening
http: off
runs: 0
> eve -loc 4043 -x src/hello.eve
> eve -loc 4043 --serve stop         # stops only the machine of port 4043
```

## 9. JSON-RPC by hand

Both doors speak JSON-RPC 2.0; on HTTP it is `POST /rpc`. With `curl` (on Windows `curl.exe`; put the message in a file to avoid quoting trouble):

```
> curl -s -X POST http://localhost:8042/rpc --data-binary '{"jsonrpc":"2.0","id":1,"method":"status"}'
{"jsonrpc":"2.0","id":1,"result":{"ipc":false,"http":true,"runs":0,"domain":"localhost","ipc_port":4042,"http_port":8042}}

> curl -s -X POST http://localhost:8042/rpc --data-binary @run.json      # {"jsonrpc":"2.0","id":2,"method":"run","params":{"name":"x.eve","source":"…"}}
{"jsonrpc":"2.0","id":2,"result":{"status":0,"output":"hi\n","errors":""}}

> curl -s -X POST http://localhost:8042/rpc --data-binary '{"jsonrpc":"2.0","id":3,"method":"nothing"}'
{"jsonrpc":"2.0","id":3,"error":{"code":-32601,"message":"method not found"}}

> curl -s -i -X PUT http://localhost:8042/
HTTP/1.1 405 Method Not Allowed
```

The methods are those of the machine API (D-165): `vm.ping`, `vm.stat` (the doors, the runs and the active parts), `vm.run` and `vm.stop`. Their first names `ping`, `status`, `run` and `stop` (D-162) are still answered until level 6 ends; an unknown method is the JSON-RPC error `-32601`. The page of `web/` uses the new names.

## All the commands

| Command | Does |
|---|---|
| `eve --listen` | start a machine with the IPC door (`eve -e other.cfg --listen` for the ports of another file) |
| `eve --serve` | start a machine with the HTTP door (the web server) |
| `eve --listen --serve` | start a machine with both doors |
| `eve --listen status`, `stop`, `restart` | the same words as `--serve`, through the IPC door only |
| `eve --serve status` | the doors and the number of scripts the machine ran |
| `eve --serve stop` | end the machine |
| `eve --serve restart` | end it and start it again in this terminal, with the same doors |
| `eve -loc [port] …` | force local: IPC, or this process; never the network |
| `eve -rem [host:port] …` | force remote: HTTP only; fails when nobody answers |
| `eve -x file.eve [args]` | run a script in this process, at once: it never looks for a machine |

| Exit code | Meaning |
|---|---|
| 0 | done |
| 4 | the script raised an error that nobody recovered |
| 64 | bad command line (`-rem` with no address and no `remote` in `eve.cfg`) |
| 65 | the script does not parse |
| 69 | nobody answers: no machine there |
| 75 | already running: a machine holds that door |

## What to look at, and what is not there yet

- **HTTPS:** never in the machine (D-165). Remote clients reach it through a reverse proxy (Nginx, Caddy, Cloudflare Tunnel) that ends HTTPS and forwards to the loopback port.
- **Not yet:** login (anyone on this computer who reaches the port can run code in the machine: keep `http_host = "localhost"`), host names for `-rem` (an IP address or `localhost` only), services and routes, WebSocket, sending a whole project with `-rem` (only the text of one script travels; its `import` and `apply` find the files of the machine).
- **Windows:** a refused HTTP connection takes about 2 s, so `eve --serve status` with no machine, and every start of `--serve` (it first asks the port whether someone is there), take 2 s. The IPC door answers in about 50 ms.
- **Ideas to try:** stop the machine while the page is open (the status turns red), run `slow.eve` from the page and `hello.eve` from the CLI at the same time, run two machines on two ports, kill the machine with Ctrl+C and start it again.

Write what you would like to change as a question or a request; the decisions go to `plan/decision_level5.md` and the rules to `spec/library/machine.md`.
