# Phase 7 — The web and the server products (level 7)

> Written 2026-10-20. Starts after `phase-6-machine.md` stage S6.6 (authentication) for the parts that serve users; the spike S7.0 and the database items may start earlier. Level 7 is the server side of the web: the Eve Web Portal (`code/evewp/`, design only), the browser runtime, and the DuckDB test database. The rule of a step, the sizes and the common gate are those of `phase-1-5-stabilize.md`; tests go in `test/level7/`.

Where the work stands: two tests pass (`g01`, `g02`, evedb columnar); `drivers/duckdb/` is the DuckDB server (D-203, D-204); `project init` and `new` are done; everything else is design (`design/components/evewp/README.md`). The review (R2-L7-R01) asks for a go or no-go before any web work.

## Stage 0 — Decide

### S7.0 WebAssembly spike `[ ]` (S, two days)
- **Feature:** F-VM-09. **Change:** build the VM (or a small core) for `wasm32`, run `hello.eve` in a page, report: size, what had to be cut (threads, sockets, SQLite), speed. **Go or no-go for D-193 and F-WEB-02, F-WEB-03, F-WEB-07.** A no-go moves those features to the backlog; the rest of this phase stands.
- **Gate:** a page that prints `Hello World!` from a `.eve` file; the report in `design/`.

### S7.1 Questions `[!]` (S, the author)
- Q-027 (templates: the `HTML` type and template files) and Q-048 (login) before S7.3 and S7.6.

## Stage 1 — Database server products

### S7.2 evedb and DuckDB `[ ]` (M)
- **Features:** F-DAT-12, F-DAT-13 (DuckDB part), F-DAT-05 (Arrow), S8.10a of phase 8. **Change:** `sql function` registered on DuckDB connections; the batch protocol (`QUERYB`, `LOAD`) with the driver `evedb://` fully tested; DuckDB linked statically (S8.10a) or the finding recorded; fault injection and the statement log tested.
- **Tests:** `script/evedb_check.py`, `script/pg_check.py`, and `test/level7/g0x` tests that use `evedb://`.

## Stage 2 — The Eve Web Portal (server side)

### S7.3 HTML templates `[ ]` (M)
- **Feature:** F-WEB-01. **Change (needs Q-027):** the `HTML` type, context-aware escaping (text, attribute, URL, script), template files with components.
- **Tests:** an injection test per context (`<script>` in a name is escaped); a page rendered from a template equals the expected HTML byte for byte.

### S7.4 Process supervision `[ ]` (M)
- **Feature:** F-VM-12. **Change:** `os` handles for spawn with limits, wait, kill and signals; the status of a child through its IPC door (the host of evewp uses it).
- **Tests:** a child killed by a limit; a child that ends by itself reports its exit code.

### S7.5 evewp edge and host `[ ]` (L)
- **Feature:** F-WEB-05. **Change:** written in Eve: the host table by `Host` header (domains, subdomains, wildcards), static files, proxy to the Eve machine of each application, request log and limits; an application per folder with versions, start and supervision, deploy and rollback. Behind a reverse proxy for TLS (the outbound TLS client of `http` is TD-11).
- **Needs:** S6.6 (authentication), S6.7 (capabilities), S7.4.
- **Tests:** two applications on two domains; a deploy then a rollback; a crash restarts the application.

### S7.6 evewp monitor `[ ]` (M)
- **Feature:** F-WEB-06. **Change:** the health server written in Eve: connections, requests, domains, users, applications, memory, logs, alerts, as SVG charts and pages with no JavaScript, updates through the framework. Needs S7.3 and F-LIB-11 (logging, phase 1-5).

## Stage 3 — Eve in the browser (only after a go in S7.0)

### S7.7 Browser runtime `[ ]` (L)
- **Features:** F-WEB-02, F-WEB-07. **Change:** the Wasm VM runs signed `.evb` code with limited capabilities and a `dom` module; the framework compiles Eve with a browser profile to Wasm (stage W1 the VM running source or `.evb`, stage W2 a typed subset compiled to Wasm), shared modules with the server, a fixed generated loader shim. Needs the `.evb` format (S8.12 of phase 8) and S7.3.

### S7.8 Tutorial playground `[ ]` (S)
- **Feature:** F-WEB-03. **Change:** a Run button on tutorial examples using the Wasm VM. The tutorial is last in the order of work, so this is the last step of the phase.

## Close level 7

### S7.9 Close `[ ]` (S)
- F-DOC-03 (the web part of the tutorial), F-TLS-23 (project init, remaining item: the writer of the minimal fallback log); update `spec/index.md` with the web pages; `evegen status` shows level 7 with no `open` feature, or the dropped ones recorded in the spec page of the feature.

## Order

S7.0 → S7.1 → S7.2 (parallel with S7.3, S7.4) → S7.5 → S7.6 → (go) S7.7 → S7.8 → S7.9.
