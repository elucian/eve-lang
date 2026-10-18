# evewp: the Eve Web Portal

Status: **design for review**, first draft 2026-10-18. Nothing is built. It replaces the browser Workbench as the level 7 project (the old design is kept in [workbench-design.md](workbench-design.md)); the idea notes of the author are in [wp-design-ideas.md](wp-design-ideas.md). The development tool is now the native `eveux` (see `eveux/README.md`).

## 1. What evewp is

`evewp` is the **production web layer of Eve**. It is not a development tool: it is where finished Eve applications are hosted, seen and watched. It has four parts:

| Part | Does |
|---|---|
| **Edge** | receives the public HTTP traffic of one or many domains and subdomains, routes it by the `Host` header to the application that owns it, serves static files, and proxies dynamic requests to the Eve machine of the application |
| **Host** | keeps each application in its own folder, with versions; starts, watches, restarts and stops the Eve machine of each application; receives deploys from `eveux` and `eve --upload` |
| **Monitor** | a graphic health server: who is connected, which domains are served, request rates, errors, memory, state of every application, logs, alerts. It reads the telemetry of the machines through their IPC door |
| **Web framework** | the way to write the *client side* of a web application **in Eve**: Eve (a dialect, section 7) compiled to WebAssembly modules that run in the browser, with no JavaScript written by the developer |

evewp is **written in Eve**. Its hot loops (copying bytes between sockets, sending a file, compressing) are native modules of the system library in Zig, as the rule of `plan/design-libraries.md` says (Zig for primitives and speed, Eve for policy and composition); everything else is Eve code. That makes evewp the **final test and stress test of the language**: the role that D-154 gave to the Workbench, now given to a web server that real traffic uses every day. Web development is the ultimate test because it needs everything at once: network, text, concurrency, data, security, time, and the compiler targets.

What evewp is **not**: not an editor or an IDE (that is `eveux`, `evetx`); not a CDN; not a general container platform (an application is an Eve project, not any program); not a replacement for the operating system's service manager (on a computer, `eve -s` still runs under it).

## 2. The family

| Program | Language | Role | Where it runs |
|---|---|---|---|
| `eve` | Zig | the **server**: runtime, compiler, REPL, the machine with its doors | developer's computer and servers |
| `evedb` | Zig | the database backend of `eve` (DuckDB; SQLite is inside `eve`) | beside `eve` |
| `evetx` | Zig | terminal client of the machine (development) | developer's computer |
| `eveux` | Zig (dvui) | native graphical client of the machine (development) | developer's computer |
| **`evewp`** | **Eve** | **production edge, host and monitor; the web framework** | **servers** |

Development flows left to right: edit and test with `eveux` or `evetx`, deploy (`design-elaboration.md` §5 of `eveux/`), and the application runs under `evewp`. The deploy target of that design is an application folder of evewp.

## 3. Architecture

```
  Internet                                   SERVER (one computer, or several)
 +-----------+      TLS      +------------------+
 | browsers  | ------------> | reverse proxy    |  Caddy, Nginx or Cloudflare Tunnel (D-189: level 8)
 +-----------+   (HTTPS)     | TLS, certificates|
                             +--------+---------+
                                      | HTTP on loopback
                                      v
        +-----------------------------+---------------------------------+
        | evewp (an Eve program: eve -s, the portal project)            |
        |   Edge:    host table, static files, proxy, request log, limits|
        |   Host:    apps/, versions, supervisor, deploy receiver        |
        |   Monitor: metrics store, dashboard pages, alerts, /healthz    |
        +--------+-----------------------+-------------------+----------+
                 | IPC / loopback        | IPC               | IPC
                 v                       v                   v
        +----------------+      +----------------+    +----------------+
        | app1.example   |      | app2.example   |    | admin.example  |
        | eve -s (own    |      | eve -s         |    | (the evewp     |
        |  process)      |      |                |    |  dashboard app)|
        |  + evedb child |      |  + evedb child |    +----------------+
        +----------------+      +----------------+
```

- **Process isolation.** The edge and the monitor never run application code. Each application is an Eve machine in its own process (`eve -s`), so a crash, a runaway loop or a memory leak in one application cannot stop the edge, the dashboard or the other applications. Resource limits (memory, CPU time, open files) are set for each child by the host.
- **TLS.** The decision D-189 stands: the Eve machine holds no TLS server and no C TLS library; HTTPS comes from a **reverse proxy in front of evewp** (level 8 in the backlog). evewp trusts the headers `X-Forwarded-*` only from the addresses of that proxy. Terminating TLS inside evewp would need a TLS server that Zig's standard library does not have (it has a client; to verify) or a C library; it is a question for the author (Q-3), not a part of the first versions.
- **One program, many roles.** evewp is one Eve project. The edge, the host and the monitor are aspects that run as tasks (`spawn`, `start`), so a slow dashboard page cannot stop the edge.
- **The monitor is an application too.** The dashboard is served at a domain of its own (`admin.example`, or a path), by the same machinery as any application, and is the first customer of the framework.

## 4. Written in Eve: what is Eve and what is native

| Layer | Eve or Zig | Notes |
|---|---|---|
| Host table, routing rules, limits, redirects, access rules | **Eve** | policy: a table, `match`, records |
| Static file serving: headers (ETag, `Cache-Control`, `Range`, `Content-Type`), directory index, precompressed files | **Eve** over native `fs` and a native **file send** | the decision is Eve; the copy of the bytes is native (`sendfile` or a loop) |
| Proxy to an application | **Eve** policy + native **byte pump** between two sockets | headers, timeouts, retries, health in Eve; the streaming of bodies in Zig |
| HTTP parsing and writing | **Eve** today (`lib/http.eve`, measured 0.54 s for 300 requests against 0.90 s for a Python server in `p6e`); Zig if a later benchmark falls ten times behind | |
| WebSocket | native framing (`ws`, M4), Eve for messages | |
| Compression (gzip, brotli) | native | |
| TLS | the reverse proxy (above) | |
| Supervision of applications | **Eve** over native `os` (spawn, wait, kill, limits, `vm.stat` through IPC) | `os.run!` becomes a process handle API (TD-9) |
| Metrics store and aggregation | **Eve** over the core SQLite database (`evewp.db`): one row each minute, rings by size | |
| Dashboard pages | **Eve** templates (`HTML` type, F-WEB-01) with **SVG** charts made by Eve code | no JavaScript: the first versions refresh the page; the Wasm framework gives live updates |
| Logs | **Eve** module `log` (E8) | access log in a common format, error log, rotation |

The library work already done covers the base: `net`, `http`, `route`, `service`, `rpc`, `json`, `config`, `crypto`, `os`, `test`, string functions, `recover` in functions (see `plan/design-libraries.md`). What evewp adds to the library plan is in section 10.

## 5. The hosting model

```
/srv/eve/                          the portal folder (the evewp project)
  portal.cfg                       domains, ports, proxy addresses, limits, alert targets
  evewp.db                         metrics, events, audit (SQLite)
  log/                             access.log, error.log, portal.log
  apps/
    shop/                          one folder for each application
      app.cfg                      domains, the machine settings, limits, health path
      versions/
        41/  42/  43/              deployed versions (the bundle of `eve --upload`)
      current                      the number of the active version
      shared/                      data that survives deploys: db/, data/, uploads/
      run/                         the IPC socket, the pid file
      log/
    blog/
```

**`portal.cfg`** (one `key = value` per line, read by the `config` module): the public address the edge listens on (loopback, behind the proxy), the addresses of the proxies it trusts, the default application, global limits (connections, header size, body size, requests a second for each address), the name of the dashboard domain, and the alert targets.

**`app.cfg`** for each application: `domains = shop.example.com, www.shop.example.com`, a wildcard `*.shop.example.com` for tenants, an optional path prefix, `static = web` (the folder served directly), `machine = on` (an Eve machine for the dynamic routes) or `off` (static only), limits (`memory`, `cpu`, `files`, `connections`), the health path (`/healthz`), the number of versions kept (default 5), the environment (`production` refuses a deploy of a dirty Git tree).

**Routing.** The edge reads the `Host` header and takes the first match in this order: exact domain, wildcard domain, the default application, else a plain 404 page. Inside an application: a file of its static folder first (when the path has a file), then the dynamic proxy, then 404. A redirect from `www` or from HTTP is a rule in `app.cfg`.

**Life of an application.** `deployed` → `starting` → `healthy` → (`degraded` | `stopped` | `crashed`) → `restarting`. The host starts the machine, waits for the health path, switches the edge to it, and only then stops the old process (the old version keeps answering the requests it has). A crash restarts with a growing delay and gives up after a number of failures (`failed`, an alert). `stop`, `start`, `restart` and `rollback` are commands of the dashboard and of the machine API.

**Deploy.** `eveux` or `eve --upload` sends a bundle with a manifest (`eveux/design-elaboration.md` §5); evewp checks it with the compiler under the rules of the application, writes `versions/N`, and activates it atomically (`current`). A rollback activates an older number, with no upload. Database migrations are not run by a deploy; the plan lists them.

## 6. Monitoring

| Group | Numbers |
|---|---|
| Connections | open client connections, new each second, by domain; open proxy connections to each application |
| Traffic | requests a second, bytes in and out, status classes (2xx, 3xx, 4xx, 5xx), top paths, slowest paths |
| Latency | median, 95th and 99th percentile of the edge and of each application |
| Users | distinct clients in the last minute and hour (by address, or by session when the application reports it) |
| Domains | each domain, its application, its certificate state as told by the proxy, requests, errors |
| Applications | state, version, uptime, restarts, memory, CPU, open files, the counters of `vm.stat` (requests, running, sessions, door), the log tail |
| Portal | its own memory, tasks, queue length, store size |
| Events | deploys, restarts, crashes, rollbacks, limit hits, alerts |

**Sources.** The edge counts what it sees. The applications are asked with `vm.stat` through their IPC door (a low-overhead local call every few seconds); the operating system gives memory and CPU of a process. Nothing is sampled from inside the application code.

**Pages.** Overview (the health of everything on one screen), Domains, Applications, one application (versions, deploy history, logs, limits), Logs (search and tail), Alerts, Settings. The charts are **SVG** written by Eve code from the store; a table is plain HTML. **Alerts** (an application down, 5xx above a rate, latency above a limit, restarts above a number, disk or memory low) go out through the `http` client to a webhook, and by mail later.

**No JavaScript.** Until the Wasm framework exists, the pages refresh with a header or a meta element (a few seconds) and use plain links and forms. With the framework the dashboard gets live charts and a log tail pushed over WebSocket, still with no JavaScript written by us.

**Health.** `GET /healthz` of the portal (and of each application) answers the state in a few bytes for the load balancer or the proxy.

## 7. The Eve Web framework

The aim: write the client side of a web application **in Eve**, share code with the server, and run it in the browser as WebAssembly. The test of the language is complete when the same modules (types, validation, formatting, business rules) run on both sides.

### 7.1 The honest limit: "no JavaScript"

A WebAssembly module cannot touch the page or the network by itself: the browser exposes the DOM, `fetch`, timers and events only as JavaScript functions, and a Wasm module must be started by a few lines of JavaScript. The standard has no direct DOM binding yet. So the design is: **no JavaScript written by the developer**; the toolchain adds one small, fixed, generated **loader shim** (a few kilobytes, the same for every application, versioned with Eve) that instantiates the module and gives it the host functions of section 7.4. The shim is part of evewp, tested by evewp, and served as a static file. It is the only JavaScript in the system, and it contains no application logic. The page needs the Content Security Policy `script-src 'self' 'wasm-unsafe-eval'` (no inline scripts, no `eval`).

### 7.2 The dialect "Eve-Web"

The language is the same; the **libraries and the permissions** differ. A module compiled for the browser is checked against a profile:

| Removed (compile error in the browser profile) | Added |
|---|---|
| `fs`, `os`, `net` sockets, `database` and SQL connections, `secret`, `crypto` keys of the machine, shell `call`, `parallel` and `start` of aspects (threads) | `dom` (find, create, set text and attributes, classes, events), `http.get!` and `post!` over the browser's `fetch`, `storage` (local and session storage), `time` and timers, `rpc` over `fetch` and WebSocket, `url`, `form`, console output |
| anything that needs a `Secret` or an operating-system right | a **capability list** in the module manifest (F-NET-05): what the module may call, checked by the compiler and again by the loader |

Rules: the same types (`Integer`, `Decimal`, `Instant`, collections, records, classes) with the same results on both sides; `HTML` values are escaped by context (F-WEB-01); no global mutable state shared with other modules (module state is per page); errors work as everywhere (`recover` in functions, D-192). Code that is not allowed in the browser can still live in the same module family: the compiler decides by the profile which functions go to which side (a function that calls `database` is server-only; one that calls `dom` is client-only; pure functions are shared).

### 7.3 Compilation: two stages

| Stage | What is sent to the browser | For | Against |
|---|---|---|---|
| **W1. The VM in WebAssembly** (F-VM-09, F-WEB-02, already planned) | `evevm` compiled to `wasm32` (about the size of the interpreter without SQLite, *to measure*) and the program as source or as portable bytecode `.evb` (signed, with its capabilities) | the full language of the profile, early, the same behavior as the server, the **playground** (F-WEB-03) | an interpreter inside an interpreter's host: slower than native Wasm; the download of the VM (cached once for all pages) |
| **W2. Eve to WebAssembly** (new) | a Wasm module compiled from a **typed subset** of Eve: `Integer`, `Real`, `Logic`, strings, records, lists, functions with known types; dynamic parts call into a small runtime module | speed and small downloads for the hot code (validation, formatting, parsing, charts); no interpreter in the page | a compiler backend (`eve cp --target wasm`), a memory manager inside Wasm (reference counting as in D-151), dynamic features (`Any`, overloading by run-time type) need the runtime or are excluded from the subset |

**Order**: W1 first, because it uses what the plan already has (`evevm` in Zig builds for `wasm32`; the host functions; `.evb` from the bytecode compiler of 0.0.6/0.7) and gives the whole language; W2 later, module by module, behind the same loader and manifest, so a page can mix both. The user does not choose: a module marked `compile = wasm` in the manifest is built with W2 when it fits the subset, else with W1, and the compiler says which.

Open technical points of W1: the interpreter runs each task on an OS thread (`task.zig`, the baton), and a browser Wasm module has no threads (shared memory needs special headers) and cannot block. In the browser profile an Eve program is a set of **event handlers that run to completion** on the one thread; `async` and `await` become promises of the host (a call to `fetch` returns to the event loop and the handler continues in a new turn). That needs the interpreter to suspend a handler at an `await`: by running tasks as resumable frames, or by compiling `await` points into a state machine. This is the largest open problem (Q-5). `parallel`, `start` and `spawn` of threads are not in the profile.

### 7.4 The browser runtime

The loader shim (section 7.1) provides host functions to the module, all small and generic: `dom.*` (a handle for each element, never the element itself), `events.listen`, `http.fetch`, `timers.*`, `storage.*`, `console.write`, `memory` for strings (UTF-8 in the module's memory, copied by the shim). The module exports `main` and one entry for each handler. The runtime is the same for W1 and W2. A page with no client module needs no shim and no Wasm at all.

### 7.5 The programming model (proposed; the syntax is the author's, Q-4)

Pages are made on the server: a route returns an `HTML` value from a template (Q-027), with the data of the request. **Interactive parts** ("islands") are Eve modules compiled for the browser and attached to an element of the page. The server renders the first state, so the page works without Wasm and is quick to appear; the module takes over the element, runs the handlers and updates the parts that change. A form without a module is a plain form that posts to a route.

A sketch with the syntax that exists today (no new syntax is proposed here):

```eve
# shared/money.eve: runs on both sides
module money is
  export (format, valid_amount);
  function valid_amount(text: String) => (@result: Logic) is
    let result := text =~ "/^[0-9]+(\.[0-9]{1,2})?$/";
  return;
  function format(value: Decimal) => (@result: String) is
    let result := "{value} EUR";
  return;
end money;
```

```eve
# client/cart.eve: compiled to WebAssembly, attached to <div id="cart">
module cart is
  from lib use (dom, http, money);
  export (on_add, on_pay);
  procedure on_add(item: String) is
    dom.text("#count", "{Integer.parse(dom.text("#count")) + 1}");
  return;
  procedure on_pay() is
    new answer := http.post!("/api/pay", dom.form("#pay"));
    dom.text("#status", if answer.status == 200 then "paid" else "failed");
  recover
    dom.text("#status", "network error");
  return;
end cart;
```

Proposed, not decided: a way to bind handlers in the template (an attribute such as `on:click="cart.on_add(item)"` checked by the compiler), reactive state (a value that re-renders its part when changed), and a `component` form. They are syntax and belong to the author (Q-4); the framework can start with explicit `dom` calls, as above.

**Talking to the server.** The browser module calls routes with `http` and calls typed methods with `rpc` (JSON-RPC 2.0 over `fetch` or one WebSocket). Because the types are shared, a bad field is caught by the same `valid_*` function on both sides. Sessions use a cookie set by the server (`HttpOnly`, `SameSite=Strict`); the CSRF token travels in a header added by the shim from a `<meta>` value.

### 7.6 Budgets (to measure, not promises)

A page with no client module: no Wasm. The shim: a few kilobytes. W1: one VM download cached for all pages and applications of a domain. W2: a module of a few tens of kilobytes for typical hot code. Start-up: the module compiles while the HTML is already visible (streaming compilation). These numbers go into the benchmark `p7b` once a prototype exists.

## 8. Security

- **Edge.** Limits on header size, body size, connections and rate for each address and each domain; slow-client time-outs (`timeout:` of `net`, TD-27); only the proxy addresses may set `X-Forwarded-*`; the `Host` header is checked against the host table (an unknown host never reaches an application).
- **Applications.** One process each, with limits and its own user when the system allows; the IPC socket of an application is readable only by evewp.
- **Pages.** Every value inserted in a page is escaped by context (the `HTML` type); CSP without inline script; `wasm-unsafe-eval` only for the framework's shim; cookies `HttpOnly`, `SameSite=Strict`, `Secure` behind HTTPS.
- **Wasm modules.** Signed bundles with a capability list; the loader refuses a module that asks for more than the page's policy; modules run in the browser sandbox with no access to the machine.
- **Dashboard.** Login (level 7 `auth`), roles (read only, operator, admin), audit of every start, stop, deploy and rollback; no secret is shown.
- **Secrets.** Never in a bundle or a log; `Secret` values stay on the server.

## 9. Relation to the decisions and the plan

| Item | Change |
|---|---|
| **D-154** (the Workbench in Eve is the final test of the language, level 7) | Moves to **evewp**: the final test is a production web server and a Wasm web framework in Eve. The browser Workbench is replaced by the native `eveux` for development. Recorded as D-193 (proposed). |
| **D-189** (no TLS in the machine; reverse proxy at level 8) | Kept: the proxy is in front of evewp. evewp is the *Eve-side* edge behind it. |
| F-VM-09 (WebAssembly build), F-WEB-01 (HTML templates), F-WEB-02 (Eve in the browser), F-WEB-03 (playground) | Become the core of evewp 0.4 to 0.6; F-WEB-02 is split in W1 and W2. |
| F-TLS-19 to F-TLS-22 (the Workbench features: editor, SQL, jobs, debugger) | Belong to the native `eveux`; the job browser and log inspector that need a server view (F-TLS-21) are also pages of the evewp dashboard. |
| F-NET-02, F-STR-08, F-TLS-14 | Done in part by `net`, `http`, `route`, `service` (level 6); evewp is their user. |
| F-TLS-30 (service mode) | Each application and evewp itself run as `eve -s`. |
| New features | **F-WEB-05** evewp edge and host; **F-WEB-06** evewp monitor; **F-WEB-07** the Eve Web framework (profile, W1 loader and runtime, W2 compiler); **F-VM-12** supervisor API of `os` (spawn, limits, wait, kill). F-WEB-04 (web application kit) is the guide that uses them. |

## 10. What the library needs (adds to `plan/design-libraries.md`)

| Need | Where | Milestone |
|---|---|---|
| `ws` WebSocket framing | Zig | M4 (planned) |
| `streams`, one task for each connection, keep-alive, time-outs | Eve + Zig `net` | M4 (TD-27, TD-29) |
| file send, byte pump between sockets, gzip | Zig | new, M4 |
| process handles: spawn with limits, wait, kill, signals, `vm.stat` over IPC | Zig `os` + Eve | new |
| `log` (access and error logs, rotation), `pager` | Eve | M6 (planned) |
| `html` (type, templates, escaping by context) | Eve + Zig scanner | M7, Q-027 |
| `svg` helpers for charts | Eve | new, small |
| `session`, `cookie`, `auth` | Eve (+ `crypto`) | level 7 |
| `dom`, `events`, `storage`, `fetch` host functions and the loader shim | Zig (Wasm host) + the shim | evewp 0.5 |
| the profile checker, `eve cp --target wasm`, `.evb` writer | Zig (evecp) | with F-VM-04/07 and F-WEB-02 |

## 11. Tests and benchmarks

`test/level7` (prefix `g`): evewp is tested through its own HTTP surface by Eve scripts (host routing with a `Host` header, static files and caching headers, proxy to a test application, a crash and restart, a deploy and a rollback, the dashboard pages, limits and rate limiting, alerts to a local webhook). The Wasm framework is tested by compiling modules and running them in a headless Wasm engine that is part of the test (a small host written for the tests, or a browser driven by a script), with the shared modules proven equal on both sides. Benchmarks: `p7a_evewp` (requests a second through the edge for static and proxied routes, with the Python twin), `p7b_wasm` (start-up and speed of W1 and W2 against native for a validation function). The stress goals of the old design carry over, rewritten for a server: 10,000 concurrent idle connections, 1,000 requests a second through the edge on a small computer, a week of flat memory (`EVE_MEMSTATS`).

## 12. Versions

| evewp | Content | Needs |
|---|---|---|
| 0.1 | Edge: host table, static files, proxy to one application, request log, limits, `/healthz` | level 6 modules, `ws` not needed, file send and byte pump |
| 0.2 | Monitor: the metrics store, the dashboard pages with SVG, refresh without JavaScript, alerts | `log`, `os` handles, `vm.stat` over IPC |
| 0.3 | Host: the folder model, versions, supervisor, deploy receiver, rollback, many applications | deploy messages (`deploy.*`), `eve -s` per application |
| 0.4 | Pages: `HTML` templates, forms, sessions, login of the dashboard, roles | F-WEB-01, `auth` |
| 0.5 | Framework W1: the VM in WebAssembly, the loader shim, `dom`, the playground, live dashboard over WebSocket | F-VM-09, `.evb` or source in the browser, `ws` |
| 0.6 | Framework W2: the typed subset compiled to Wasm; shared modules; the budgets met | the backend of `evecp` |
| 1.0 | every test of `test/level7` passes and the stress goals are met: the exit of version 0.6 of Eve | |

## 13. Risks

- **A Wasm interpreter that suspends** (section 7.3): the thread-based tasks do not exist in the browser; resumable handlers are real work in the VM.
- **The compiler backend of W2** is a large project of its own; W1 must carry the first releases.
- **"No JavaScript"** is true for the developer, not for the system (section 7.1); the claim in the tutorial must say it.
- **TLS** depends on the proxy (Q-3); a single-binary deployment is not possible until a TLS server exists.
- **Performance in Eve**: the edge is a hot path; the plan is to measure early (`p7a`) and move byte loops to Zig, not to hope.
- **Scope**: edge, host, monitor and framework are four projects; the versions of section 12 order them so each one is useful alone.

## 14. Questions for the author

1. **Name and scope.** "Eve Web Portal (evewp)" as the production edge, host, monitor **and** the web framework in one program, or the framework as a separate module (for example `evewf`) used by evewp? *Recommended: one folder `evewp/`, the framework as a library inside it, split later if it grows.*
**Answer:**
2. **Written in Eve.** The edge, host and monitor in Eve with native byte loops in the system library (section 4), not a Zig program (the first idea note suggested Zig)? *Recommended: Eve, as you asked; the rule keeps speed where it matters.*
**Answer:**
3. **TLS.** Keep the reverse proxy in front (D-189) for all versions, or plan a native TLS server module (a C library or a Zig implementation) so evewp can terminate TLS itself? *Recommended: proxy for 0.x; decide again at 1.0.*
**Answer:**
4. **Framework syntax.** Start with explicit `dom` calls (section 7.5) and let the author decide the template event binding, reactive state and `component` syntax after the first prototype? *Recommended: yes.*
**Answer:**
5. **Wasm and tasks.** In the browser profile, are programs event handlers that run to completion, with `await` suspending through a resumable frame in the VM? Or should `await` be left out of the profile at first (callbacks only)? *Recommended: leave `await` out of 0.5, add it when the VM can suspend.*
**Answer:**
6. **W1 before W2.** Run source or `.evb` in a Wasm VM first, the typed-subset compiler later? *Recommended: yes.*
**Answer:**
7. **The loader shim.** Accept one fixed, generated JavaScript file (a few kilobytes) as part of the system, and state "no JavaScript written by the developer" in the tutorial? *Recommended: yes.*
**Answer:**
8. **Multi-tenant.** Subdomain routing with one folder and one Eve machine for each application, as in section 5; or several applications in one machine? *Recommended: one machine each (isolation).*
**Answer:**
9. **Command words.** The part word `eve ux` (D-163, the web door and the UI) becomes `eve wp`? And `./run.sh eveux` stays for the native client? *Recommended: yes.*
**Answer:**
10. **First version.** Start with 0.1 (edge, static, proxy) or with 0.2 (the monitor, the part most visible)? *Recommended: 0.1 then 0.2, they share the request counters.*
**Answer:**
