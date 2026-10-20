# evewp: the Eve Web Portal

`evewp` is the production web layer of Eve: the place where finished Eve applications are hosted, served and watched. It is written in Eve itself, with only its hot loops (copying bytes between sockets, sending files, compressing) in native modules; that makes it the largest program in Eve and the stress test of the language.

**Status: design.** Nothing of evewp is built yet, and the distribution holds no evewp program. The command words that will start it are not settled. This page says what it is for.

## The four parts

| Part | Does |
|---|---|
| Edge | receives the public HTTP traffic of one or many domains and subdomains, routes each request by its host name to the application that owns it, serves static files, and passes dynamic requests to the Eve machine of the application |
| Host | keeps each application in its own folder with its versions; starts, watches, restarts and stops the machine of each application; receives deploys from `eveux` |
| Monitor | a health dashboard: connected users, served domains, request rates, errors, memory, the state of every application, logs and alerts |
| Web framework | the client side of a web application written in Eve and compiled to WebAssembly, so a developer writes no JavaScript |

## What it is not

Not an editor or an IDE (that is `eveux` and `evetx`), not a CDN, not a general container platform (an application is an Eve project, not any program), and not a replacement for the service manager of the operating system (`eve -s` still runs under it).

## Planned versions

| Version | Content |
|---|---|
| 0.1 | Edge: the host table, static files, a proxy to one application, the request log, limits, `/healthz` |
| 0.2 | Monitor: metrics, dashboard pages drawn with SVG, alerts |
| 0.3 | Host: application folders, versions, supervision, deploy, rollback, many applications |
| 0.4 | Pages: HTML templates, forms, sessions, the login of the dashboard, roles |
| 0.5 | Framework, first step: the Eve machine in WebAssembly in the browser, live dashboard over WebSocket |
| 0.6 | Framework, second step: a typed subset of Eve compiled to WebAssembly |
| 1.0 | the web level of Eve is complete and evewp meets its load goals |
