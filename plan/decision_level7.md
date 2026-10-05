# Decisions, level 7: web, HTML and WebAssembly (version 0.6)

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. Ids are shared by all the decision files ([level 1](decision_level1.md), [2](decision_level2.md), [3](decision_level3.md), [4](decision_level4.md), [5](decision_level5.md), [6](decision_level6.md), 7); the list of levels is in [decision_level3.md](decision_level3.md) and [version_map.md](version_map.md).

## Scope

Eve produces safe HTML and runs in the browser. A service returns HTML built from templates that escape every value by context; the Eve machine itself is compiled to WebAssembly, so Eve code runs in a page, and the tutorial gets a "Run" button on its examples. Tests: `test/level7`, prefix `g`.

Features: F-WEB-01 to F-WEB-04, F-VM-07, F-VM-09, F-DOC-03 (web part).

## Draft features

1. **The Html type.** A value of type `Html` is produced only by templates or by `html.escape`; `res.body` of a route accepts `Html` for pages, so text from users can't inject scripts (review RNW-R05).
2. **Templates.** Template files (`.evh`) or template literals where `{expr}` is escaped by context: text, attribute, URL, script.
3. **The VM in WebAssembly.** `evevm` compiled to `wasm32`, with host functions for the console, fetch and timers (review RVM-R06).
4. **Portable bytecode** `.evb`: versioned, with a hash and the capabilities it needs; what a browser downloads from a machine (review RVM-R05).
5. **Tutorial playground.** A "Run" button on the examples of the tutorial, with the VM in WebAssembly.

## Open questions

- Templates as separate files, as literals in Eve code, or both?
- Which Eve code may run in a browser: pure functions only, or aspects with limited capabilities?
