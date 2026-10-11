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
