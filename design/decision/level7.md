# Decisions, level 7: web, HTML and WebAssembly (version 0.6)

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. Ids are shared by all the decision files ([level 1](level1.md), [2](level2.md), [3](level3.md), [4](level4.md), [5](level5.md), [6](level6.md), 7); the list of levels is in [decision_level3.md](level3.md) and [version_map.md](../version_map.md).

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
Author decision, reviewing the first draft of `code/eveux/README.md` (Q-047): "We use Eve to build eveux as ultimate test of Eve capability and a stress test. Therefore is in level 7 that is actually last level." (1) The server part of eveux is an Eve project (a service script, aspects, modules) run by the local Eve machine; the browser part stays plain JavaScript and plain CSS. No separate Zig program, no Zig web toolkit for eveux: what is not Eve code is a feature of `evevm` (`serve`, WebSocket, connections, login), so every Eve program gets it. (2) eveux is the acceptance test and the stress test of level 7 and of Version 0.6: its tests are in `test/level7`, its stress run is a benchmark `p7a_eveux`; a failure is fixed in the language or the VM, not worked around. (3) Features F-TLS-19 to F-TLS-22 move from Version 0.5 to Version 0.6. (4) The tutorial keeps the page `eveux.html` in phase 6 (Internet features). Related: D-155 (the login to remote machines).

## D-193 evewp, the Eve Web Portal, replaces the Workbench as the level 7 project; eveux becomes a native Zig client (2026-10-18)

Author decision (2026-10-18): "Create evewp for a new module, Eve Portal, that replaces the Eve Workbench as a production server, that uses Eve but no JavaScript. We create an Eve framework that enables Eve (a dialect) to be compiled in WebAssembly modules and run on the client, making web development the ultimate Eve test. Refactor the tutorial to replace eveux with evewp; the eveux folder is free for a native Zig implementation. Move the old eveux readme to evewp and create a new readme for eveux." The idea note of the author (`code/evewp/wp-design-ideas.md`): a production web server, reverse proxy and monitoring gateway; subdomain multi-tenancy with one folder for each application; static files and a proxy to the Eve daemon; a graphic health monitor; not a development layer but a deploy layer. Earlier the same day the author fixed the roles: **eve is the server; eveux and evetx are the clients; evedb is the backend of the server** (`code/eveux/design/notes/design-ideas.md`).

Read as rules:

- (1) **evewp** (`code/evewp/README.md`) is the level 7 project and the final test and stress test of Eve (the role of D-154, which it replaces): a production **edge** (hosts, static files, proxy), **host** (applications in folders, versions, supervision, deploy) and **monitor** (health, traffic, domains, users), written in Eve with native byte loops in the system library, plus the **Eve Web framework**: Eve with a browser profile compiled to WebAssembly (stage W1: the VM in Wasm; stage W2: a typed subset compiled to Wasm), no JavaScript written by the developer. Features F-WEB-05 to F-WEB-07 and F-VM-12; F-VM-09, F-WEB-01 to F-WEB-03 are its base.
- (2) **eveux** (`code/eveux/README.md`) is the **native graphical development client** in Zig on dvui, for Windows first, then Linux and macOS; a client of the machine like evetx, on the stdio door. Its functional specification is the browser Workbench design, kept in `design/archive/workbench-design.md`; the features F-TLS-19 to F-TLS-22 stay and become Zig work, not level 7 Eve work. The folder `code/eveux/` holds the new design, the author's notes, the elaboration (source control, deploy) and the dvui analysis with its spike.
- (3) **The tutorial** page `eveux.html` becomes `evewp.html`; the tutorial words that said eveux for the web part say evewp.
- (4) **Older documents** (`design/design-service.md`, `design-packages.md`, `decision_level5.md`, `decision_level6.md`, `spec/library/machine.md`, `database.md`): where they say eveux for the browser Workbench, read evewp; where they say eveux for the editor, SQL console, jobs and debugger, read the native eveux. They are not rewritten one by one.
- (5) *Proposed, to confirm* (questions of `code/evewp/README.md` §14 and `code/eveux/README.md` §8): the part word `eve ux` becomes `eve wp` for the web part; TLS stays with the reverse proxy; the framework syntax is left to the author after a first prototype; `await` stays out of the browser profile until the VM can suspend.

Not done in this round: the spec pages for the browser profile and the framework, the plan details of the machine messages (`deploy.*`, `fs.*`, `job.*`, `log.*`), and the spike of eveux.

## D-194 Order of the work, second change: plan, design, user interfaces, refactor, optimize, test, spec, compiler, manual, tutorial (2026-10-18)

Author decision (2026-10-18): "Update the plan and cleanup the plan. The priority has change, we update tutorial last, we make plans first, we modify the design second, we create user interfaces, we refactor, we optimize, we test we update spec we progress the compiler."

Read as rules:

- (1) **Order of the work, the highest first:** (1) the plan (`design/`), (2) the design (`design/design-*.md`, the README and `design/` of each program), (3) the user interfaces (`code/evetx/`, `code/eveux/`, `code/evewp/`), (4) refactor, (5) optimize (`test/bmark/`), (6) test (`test/`), (7) the specification (`spec/`), (8) the compiler (`code/evecp/`, `code/evevm/`, `code/evecm/`, `drivers/duckdb/`, `code/eve/`: the language and the machine progress), (9) the manual (`manual/`), (10) the tutorial (`tutorial/`), last. It replaces D-190 (1). The next piece of work is taken from the highest rank that has open work; it is a ranking of what to do first, not a pipeline that every feature goes through.
- (2) **The spec follows the tests.** D-190 wrote spec text before the failing test; now the behavior is settled by the tests and the code, and the spec page is written or corrected after them (rank 7). The spec stays normative once written: when it and the tutorial disagree, the spec wins.
- (3) **The manual is not named in the order**; it is placed ninth, before the tutorial, where D-190 had it (after the implementation). *To confirm.*
- (4) **Optimization is allowed.** The restriction of 2026-10-07 ("do not optimize early", until level 2 passes) is over: levels 1 to 5 pass. The benchmark rules of CLAUDE.md stay (measure before and after, ReleaseSafe build, `bmark.py --check`).
- (5) **Cleaned in the same round:** the focus of `design/README.md` (it still said "tutorial first", 2026-10-07), the phases table (a rank for each phase), the old notes "tutorial first" in `design/design-unified-aspect.md` and `design/review/focus.md`, TD-13 (paid by D-192) removed from `backlog/tech-debt.md`, and `design/focus-level5.md` (level 5 passes: 115 of 115) moved to `design/archive/`.

## D-195 Code is local; a tested project is deployed and then operated; one tool bar that follows the file (2026-10-18)

Author decision (2026-10-18): "The user interface is too bloated as is designed now, we have two run buttons in eveux. The one button run SQL the other run the code. I need a dynamic toolbar that change by file type. The code is always local, this I can tell. I also can tell we need to upload code on the remote machine after the code is locally tested first. After we upload the code is controlled by a schedule or by production websites created with evewp. Because I can no longer connect visually to the code. This is true for both user interface evetx and eveux. The difference is with evetx I can connect over SSH and work remote while with eveux I can't do this."

Read as rules:

- (1) **Code is local.** A project is edited, run, debugged and tested in the **local** machine (the child `eve --stdio` of the program), on the computer of the user. Run and Debug never target a remote machine.
- (2) **Deploy after a local test.** A project that passed its tests is uploaded to a remote machine (Tools > Deploy…: diff against the target, checks, versions, rollback; `code/eveux/design/design-deploy.svg`). A remote machine receives only deployed bundles.
- (3) **After the upload the code is operated, not edited.** On the remote machine the code is controlled by a **schedule** (`eveux` for schedules and runs, F-TLS-21) or by a **production web application made with evewp**. The UI no longer connects to the running code visually: no remote Run, no remote debugger, no remote editor in eveux. What it shows of a remote machine: status, schedules (pause, resume), jobs and their last runs, live logs, versions and rollback, health. This holds for **evetx and eveux**. It replaces the rule of D-171 and of the evetx README ("Machines", cut 2026-10-16) that Run and debug act on the selected machine and that on a remote one only an uploaded program can run: now nothing is run by hand on a remote machine.
- (4) **SSH.** `evetx` is a terminal program: started inside an SSH session on the remote computer (`ssh host`, then `evetx project/` or `eve -tx project/`) it reads and edits the files that are there, so the administrator can work remote. `eveux` is a window and cannot run in a session; it reaches a remote machine through the machine API, with the stdio door over SSH (`ssh host eve --stdio`, `spec/library/machine.md#lasting-doors`), **for deploy and operate only**. *Not written:* `ide.link.Link` starts `<exe> --stdio` and cannot take a command with arguments (TD-38).
- (5) **One tool bar, and it follows the active file.** The buttons depend on the kind of the file (drawing `code/eveux/design/design-toolbar.svg`, table `TOOLBARS` of `code/eveux/design/gen_svg.py`): Eve (Run, Stop, Debug, Check, Test, Deploy…; the step buttons only while debugging), SQL (connection, **Run**, Script, Explain, Commit, Rollback), database table (Describe, Structure, Import, Export, Refresh), data file (Grid or Text, filter, Load into table, Save as), document (Source, Split, Preview, Open in browser), image (zoom, fit, rotate), audio and video (player). **Run is one slot:** F5 runs an Eve file in the local machine, Ctrl+Enter runs a SQL statement; the second Run button of the SQL tab is gone. A button that cannot be used in the state is dimmed or absent.
- (6) **Out of the bar** (less bloat): the machine selector `F1 local · F2 prod · F3 test` (remote machines live in Tools > Machines and in the Deploy dialog), the search field (Ctrl+Shift+F and the ⌕ icon), the machine name in the title bar, and the menu item "Run on machine ▸". The status bar keeps `Ready: local`.
- (7) **Not done in this round:** a drawing of **Machines** (operate: status, schedules, jobs, logs, versions) for eveux and evetx; the evetx drawings and README still show the machine selector, the run on a remote machine and the Connect dialog (TD-39); the toolbar in the window code (`code/eveux/src/view/shell.zig`, TD-40).

## D-196 Order of the work by case; visual design leads the interfaces (2026-10-18)

Author decision (2026-10-18): "Feel free to optimize the order for most efficient progress by case. I like to lead by visual design like I progress the evetx."

Read as rules:

- (1) **The ranks of D-194 decide what to take next; the way through one piece of work depends on its kind.** A screen or an interface feature (evetx, eveux, evewp): **visual design first** (a drawing, `code/evetx/design/gen_svg.py` or `code/eveux/design/gen_svg.py`, reviewed by the author) → plan entry (files, machine messages, debt) → code → tests of the logic → spec of the new messages → manual → tutorial. A language or compiler feature: plan → design (a decision with examples) → failing test → compiler → spec → manual → tutorial. A library module: plan (`design/design-libraries.md`) → failing test → native or Eve code → spec page → manual. A bug: failing test, then the fix. A refactor: tests green, move, tests green; no change of behavior; its own commit. An optimization: `bmark.py` before, the change, `bmark.py` after.
- (2) **The drawing is the contract of an interface.** The code follows the drawing; a change of the screen starts as a change of the drawing and of its generator, and the README of the program names the drawing.
- (3) **D-194 stays as the default order** when a piece of work has no kind above.
