# Decisions, level 7: web, HTML and WebAssembly (version 0.6)

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. Ids are shared by all the decision files ([level 1](decision_level1.md), [2](decision_level2.md), [3](decision_level3.md), [4](decision_level4.md), [5](decision_level5.md), [6](decision_level6.md), 7); the list of levels is in [decision_level3.md](decision_level3.md) and [version_map.md](version_map.md).

## Scope

Eve produces safe HTML and runs in the browser. A service returns HTML built from templates that escape every value by context; the Eve machine itself is compiled to WebAssembly, so Eve code runs in a page, and the tutorial gets a "Run" button on its examples. Tests: `test/level7`, prefix `g`.

Features: F-WEB-01 to F-WEB-04, F-VM-07, F-VM-09, F-DOC-03 (web part), F-TLS-19 to F-TLS-22 (the RAD Workbench eveux, written in Eve, D-154).

## Draft features

1. **The HTML type.** A value of type `HTML` is produced only by templates or by `html.escape`; `res.body` of a route accepts `HTML` for pages, so text from users can't inject scripts (review RNW-R05).
2. **Templates.** Template files (`.htmt`) or template literals where `{expr}` is escaped by context: text, attribute, URL, script.
3. **The VM in WebAssembly.** `evevm` compiled to `wasm32`, with host functions for the console, fetch and timers (review RVM-R06).
4. **Portable bytecode** `.evb`: versioned, with a hash and the capabilities it needs; what a browser downloads from a machine (review RVM-R05).
5. **Tutorial playground.** A "Run" button on the examples of the tutorial, with the VM in WebAssembly.

## Open questions

- Templates as separate files, as literals in Eve code, or both: Q-027 below.
- Which Eve code may run in a browser: pure functions only, or aspects with limited capabilities?

- Q-027 Templates [open]
- D-154 eveux, the RAD Workbench, is written in Eve: the final test of the language, in level 7
## Q-027 Templates (2026-10-06)
The page templates.html teaches string templates (today) and proposes HTML templates: files `.htmt` or literals, `{expr}` escaped by context (text, attribute, URL, script), the type `HTML`, components as functions that return `HTML`, the module `html` with `html.render` and `html.write`. Questions: files, literals or both? The extension and the module name? Loops and conditions inside a template (`{for o in orders}`)? Is `HTML` required by the functions that send a page?

**Answer:**

## D-154 eveux, the RAD Workbench, is written in Eve: the final test of the language, in level 7 (2026-10-10)
Author decision, reviewing the first draft of `eveux/README.md` (Q-047): "We use Eve to build eveux as ultimate test of Eve capability and a stress test. Therefore is in level 7 that is actually last level." (1) The server part of eveux is an Eve project (a service script, aspects, modules) run by the local Eve machine; the browser part stays plain JavaScript and plain CSS. No separate Zig program, no Zig web toolkit for eveux: what is not Eve code is a feature of `evevm` (`serve`, WebSocket, connections, login), so every Eve program gets it. (2) eveux is the acceptance test and the stress test of level 7 and of Version 0.6: its tests are in `test/level7`, its stress run is a benchmark `p7a_eveux`; a failure is fixed in the language or the VM, not worked around. (3) Features F-TLS-19 to F-TLS-22 move from Version 0.5 to Version 0.6. (4) The tutorial keeps the page `eveux.html` in phase 6 (Internet features). Related: D-155 (the login to remote machines).

## D-193 evewp, the Eve Web Portal, replaces the Workbench as the level 7 project; eveux becomes a native Zig client (2026-10-18)

Author decision (2026-10-18): "Create evewp for a new module, Eve Portal, that replaces the Eve Workbench as a production server, that uses Eve but no JavaScript. We create an Eve framework that enables Eve (a dialect) to be compiled in WebAssembly modules and run on the client, making web development the ultimate Eve test. Refactor the tutorial to replace eveux with evewp; the eveux folder is free for a native Zig implementation. Move the old eveux readme to evewp and create a new readme for eveux." The idea note of the author (`evewp/wp-design-ideas.md`): a production web server, reverse proxy and monitoring gateway; subdomain multi-tenancy with one folder for each application; static files and a proxy to the Eve daemon; a graphic health monitor; not a development layer but a deploy layer. Earlier the same day the author fixed the roles: **eve is the server; eveux and evetx are the clients; evedb is the backend of the server** (`eveux/design-ideas.md`).

Read as rules:

- (1) **evewp** (`evewp/README.md`) is the level 7 project and the final test and stress test of Eve (the role of D-154, which it replaces): a production **edge** (hosts, static files, proxy), **host** (applications in folders, versions, supervision, deploy) and **monitor** (health, traffic, domains, users), written in Eve with native byte loops in the system library, plus the **Eve Web framework**: Eve with a browser profile compiled to WebAssembly (stage W1: the VM in Wasm; stage W2: a typed subset compiled to Wasm), no JavaScript written by the developer. Features F-WEB-05 to F-WEB-07 and F-VM-12; F-VM-09, F-WEB-01 to F-WEB-03 are its base.
- (2) **eveux** (`eveux/README.md`) is the **native graphical development client** in Zig on dvui, for Windows first, then Linux and macOS; a client of the machine like evetx, on the stdio door. Its functional specification is the browser Workbench design, kept in `evewp/workbench-design.md`; the features F-TLS-19 to F-TLS-22 stay and become Zig work, not level 7 Eve work. The folder `eveux/` holds the new design, the author's notes, the elaboration (source control, deploy) and the dvui analysis with its spike.
- (3) **The tutorial** page `eveux.html` becomes `evewp.html`; the tutorial words that said eveux for the web part say evewp.
- (4) **Older documents** (`plan/design-service.md`, `design-packages.md`, `decision_level5.md`, `decision_level6.md`, `spec/library/machine.md`, `database.md`): where they say eveux for the browser Workbench, read evewp; where they say eveux for the editor, SQL console, jobs and debugger, read the native eveux. They are not rewritten one by one.
- (5) *Proposed, to confirm* (questions of `evewp/README.md` §14 and `eveux/README.md` §8): the part word `eve ux` becomes `eve wp` for the web part; TLS stays with the reverse proxy; the framework syntax is left to the author after a first prototype; `await` stays out of the browser profile until the VM can suspend.

Not done in this round: the spec pages for the browser profile and the framework, the plan details of the machine messages (`deploy.*`, `fs.*`, `job.*`, `log.*`), and the spike of eveux.
