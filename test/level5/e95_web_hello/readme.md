# e95_web_hello: the Eve machine, its two doors and its first page

The rules are in `spec/library/machine.md` (D-162). The machine is a singleton: a second start on a door that a running machine holds fails with `already running` and the exit code 75, and `eve --serve stop` stops it. It has two doors: IPC (`-lsn`, a Unix socket) and HTTP (`--serve`, the files of `web/` and `POST /rpc`). The CLI reaches it with `-loc` (local, never the network) or `-rem host:port` (remote, HTTP only).

One project, four use cases, each an automatic test with its own expectations:

| Test | The machine | What the client checks |
|---|---|---|
| `e95_web_hello.eve` | `eve --serve` | the page says "Hello World" and "This is Eve"; CSS and JavaScript types; `HEAD`; 404 for a missing file and for `eve.cfg`; a second start fails with 75; `--serve stop` frees the port |
| `e95_test1.eve` | `eve -lsn` | IPC listening, HTTP off; `-loc -x` runs the script in the machine; `-rem` fails (69) because HTTP is off |
| `e95_test2.eve` | `eve --serve` | IPC off, HTTP listening; `-loc -x` runs the script by itself; `-rem -x` runs it in the machine; a remote error comes back with exit code 4 |
| `e95_test3.eve` | `eve -lsn --serve` | both doors; `-loc` goes through IPC, `-rem` through HTTP, the counter `runs` counts both |

All of them also check: `-rem` to a port where nobody listens fails with 69, `-rem` without an address is a usage error (64), a second start fails with 75, `--serve stop` ends the machine with 0, and after it `--serve status` says not running (69).

```
e95_web_hello/
  eve.cfg                  domain, ipc_port = 4195, http_port = 8095, web
  e95_web_hello.eve        the page (client check/hello.test.js)
  e95_test1.eve … 3        the doors (client check/modes.test.js ipc|http|both)
  web/                     the single page application (the frontend)
    index.html             Hello World / This is Eve
    css/style.css
    js/app.js
  check/
    hello.test.js          client of the page test
    modes.test.js          client of the door tests
    hello.eve              the script sent to the machine
    fail.eve               a script whose error nobody recovers
```

Runner keys (`script/runtest.py`): `"command"` starts the machine in the background when the test has a `"client"`; the client (Node.js 18 or later, no package) runs in the same folder with the variable `EVE` set to the VM; the test passes when the client exits 0, its output has the `"contains"` texts and the machine ended by itself with exit code 0. A machine still running after the client ended is killed and the exit code is 98; a failed client gives 99. `"timeout"` is 40 seconds here.
