# eveux: the Eve native workbench

Status: **design with a first draft of the code**, 2026-10-18 (revision 2). `eveux` is the **graphical development environment of Eve**: a native desktop program written in Zig on the GUI library [dvui](https://github.com/david-vanderson/dvui), for Windows first and later Linux and macOS. It is an **independent tool**, like `evetx`: it is **not part of the language specification** (the machine API it uses is specified in `spec/library/machine.md`), and it has its own design folder, [design/](design/), with the drawings. The production web layer is `evewp` (`comp/evewp/README.md`); the old browser Workbench design is kept in `design/archive/workbench-design.md`.

## 1. What eveux is

A full IDE project with **embedded Eve functionality** and **debugging**:

| Area | What it does |
|---|---|
| **Edit** | Eve, SQL, JSON, XML, HTML, **JavaScript**, CSS, Markdown and plain text with syntax colors, find and replace, find in files, go to line, undo and redo, bracket matching, completion and hover docs for Eve |
| **Create** | New file from a template (Eve aspect, module, class, test; HTML page, **JavaScript module**, CSS; SQL script; JSON; Markdown; evewp application), new project (`project new`) |
| **Embedded Eve** | the compiler front end is **linked into the program**: live syntax and semantic checks while typing, outline and symbols, go to definition, docs from `**` comments, later format; scripts **run in the Eve machine** (a child process), never inside the window |
| **Run and debug** | **local only** (D-195): run, check, stop; breakpoints in the gutter, step into, over and out, variables, watch, call stack, console, output, all over the machine API of the local machine; one **tool bar that follows the file** (section 1.1) |
| **Preview** | Markdown (rendered, split with the source), HTML (rendered by a subset renderer, or in the browser), images and SVG, audio and video; a file of another kind opens a card |
| **Database** | a database file opens its tables; the data of a table in a grid; structure dialog; SQL tabs with a result grid and Eve types, commit and rollback; the object tree of a connection |
| **Source control** | status, side-by-side diff, stage, commit, branches, history (the `git` program is run for each action) |
| **Deploy** | a project that passed its tests goes to a machine or an evewp application, with a diff against the target, checks, versions and rollback |
| **Operate** | a remote machine is operated, never edited (D-195): status, schedules, jobs and last runs, live logs, versions, rollback; login (single sign-on, keyring) |

### 1.1 Working model and the tool bar (D-195, author, 2026-10-18)

**Code is always local.** It is edited, run, debugged and tested in the local machine. After a local test the project is **deployed** to a remote machine; there it is controlled by a **schedule** or by an **evewp** production application, and the UI no longer connects to it visually: it **operates** it (status, schedules, jobs, logs, versions, rollback). The same holds for evetx. The difference: evetx can run on the remote computer inside an SSH session and edit the files there; eveux is a window, so it reaches a remote machine only through the machine API, over `ssh host eve --stdio`, for deploy and operate (not written: TD-38).

**One tool bar, and it follows the active file** ([design-toolbar.svg](design/design-toolbar.svg)): Eve (Run, Stop, Debug, Check, Test, Deploy…; the step buttons appear only while debugging), SQL (connection, **Run**, Script, Explain, Commit, Rollback), database table, data file, document (Source, Split, Preview), image, audio and video. **Run is one slot** (F5 for Eve, Ctrl+Enter for a SQL statement), so the second Run of the SQL tab is gone. No machine selector, no search field and no machine name in the title: remote machines are in Tools > Machines and in the Deploy dialog. The buttons are the table `TOOLBARS` of `design/gen_svg.py`, one entry per file kind.

Roles of the family (author, 2026-10-18): **`eve` is the server; `eveux` and `evetx` are the clients; `evedb` is the backend of the server; `evewp` is the production web layer.** eveux is a client: it does not run Eve code itself and never holds a password.

## 2. Why native, and why dvui

The first design ran the Workbench in a browser, written in Eve. On 2026-10-18 the author moved the final test of the language to web development (`evewp`) and asked for a **native, platform independent GUI** for development, Windows first. A native client starts at once, has no web server on the computer (so no cookie, CSRF or CSP surface), shares real code with `evetx`, and can be built before level 7 because it needs only the machine API that exists.

dvui is an immediate-mode GUI toolkit in Zig, MIT licensed. The project follows its **main branch** (`0.6.0-dev`, commit `f68fa8a` of 2026-10-18), which needs Zig 0.17, our compiler since the same day (the tag v0.5.0 is the Zig 0.16 line). Checked in its source (v0.5.0, `src/widgets`): resizable panes, **docking**, **tabs**, a **tree**, a **data grid**, menus and floating menus, floating windows, suggestions (a completion list), scroll areas, a plot widget, a color picker, and a multi-line text entry with an optional **tree-sitter** highlighter and an image widget over stb_image. Not in dvui: undo and redo in the text entry, a code editor (gutter, bracket matching, find), Markdown, HTML, audio and video, grapheme clusters and right-to-left text; IME works only on the SDL and web backends. The analysis and the comparison with the browser design are in [design/notes/dvui.md](design/notes/dvui.md).

## 3. The screen

The window follows the layout of evetx with more panels. Drawings (`design/gen_svg.py` writes them; they are SVG, 1400 × 860):

| Drawing | Shows |
|---|---|
| [design.svg](design/design.svg) | the main window: explorer, tabs, editor with live checks, outline, problems, hover docs, jobs, console, status bar |
| [design-debug.svg](design/design-debug.svg) | paused at a breakpoint: variables, watch, call stack, breakpoints |
| [design-preview-md.svg](design/design-preview-md.svg) | Markdown: source and rendered side by side |
| [design-preview-html.svg](design/design-preview-html.svg) | HTML: source and the rendered page, Open in browser |
| [design-preview-image.svg](design/design-preview-image.svg) | an image or SVG: fit, zoom, pixel info |
| [design-preview-media.svg](design/design-preview-media.svg) | audio and video: the player |
| [design-db.svg](design/design-db.svg) | a database: tables, columns, the data grid |
| [design-toolbar.svg](design/design-toolbar.svg) | **the tool bar of each file kind** (D-195): Eve, SQL, table, data, document, image, media |
| [design-sql.svg](design/design-sql.svg) | a SQL tab: the editor and the result grid; its buttons are in the tool bar |
| [design-structure.svg](design/design-structure.svg) | the structure dialog of a table |
| [design-git.svg](design/design-git.svg) | source control: changes, side-by-side diff, commit, branches |
| [design-deploy.svg](design/design-deploy.svg) | the deploy dialog: files, checks, versions, options |
| [design-new.svg](design/design-new.svg) | New: Eve, web, data and document templates |
| [design-menu.svg](design/design-menu.svg) | the Run menu and the list of the other menus |
| [design-dialogs.svg](design/design-dialogs.svg) | login, settings, find in files, about |
| [design-architecture.svg](design/design-architecture.svg) | threads, embedded services, the machine, shared modules |

![main window](design/design.svg)

![architecture](design/design-architecture.svg)

The other drawings are in [design/](design/). Keys and menus: one table (`src/view/actions.zig`, to write) holds menu items, shortcuts and the command palette (Ctrl+Shift+P); F5 run, F6 check, F9 breakpoint, F10 over, F11 into, Shift+F11 out, Ctrl+B explorer, Ctrl+` console, Ctrl+Shift+F find in files.

## 4. Architecture

```
 eveux.exe  (one process, Zig)                                  other processes
+------------------------------------------------+     +--------------------------------+
| UI thread: the dvui frame loop (draws only)    |     | Local Eve machine (eve --stdio)|
|   shell + docking, editor, previews, grid, tree|     |   run, debug, sessions, db     |
| Embedded Eve services (evecm + evecp linked in)|     |   git, deploy, keyring, logins |
|   lexer, parser, check, outline, docs          |     +---------------+----------------+
| Worker threads, queues to and from the UI      |                     | HTTP, WebSocket, SSH stdio
|   machine link, file watcher, git runner,      |                     v
|   decoders (image, media), search in files     |     servers: eve -s, evedb child, evewp apps
| Shared with evetx: module `ide` (evecm)        |
+------------------------------------------------+
```

- **Rules.** (1) The UI thread never waits: no file, process or network call inside a frame. (2) A script runs in the child machine: a loop in the user's program cannot freeze the window and cannot crash it. (3) The compiler in the process only reads text: parse, check, outline, docs. (4) The window never sees a password or a token: the local machine holds them. (5) Every preview is a widget over a decoder that runs on a worker thread; a decoder that fails shows the file card.
- **One connection, on stdio**, exactly as evetx: the child `eve --stdio`, JSON-RPC 2.0, one message a line, `vm.output` notifications (`ide.link.Link`). A remote machine is reached by the local machine (HTTP, WebSocket, SSH `eve --stdio`), only to deploy and to operate (D-195); the code on it is never edited or run by hand. The messages are the machine API; new names (`deploy.*`, `fs.*`, `job.*`, `log.*`, `db.tree`, `db.describe`, `db.sample`, `dbg.*`) are listed in `src/machine/api.zig` with the proposals of `design/notes/elaboration.md` §6.
- **Local state** in the user cache `eve.db` (SQLite, F-DAT-13): layout, open tabs, theme, the list of machines without secrets, recent projects, the last manifest sent to each machine; the state of a server lives in its own core database.
- **Threading model.** dvui calls widgets every frame on the UI thread. Workers produce **messages** (a tree scanned, a file decoded, a git status, a machine event) into a queue; the UI thread takes them at the start of a frame and updates the state; a frame draws from the state. There is no shared mutable state and no lock in the drawing code.

### 4.1 Embedded Eve functionality

eveux links `evecm` and `evecp` (the common part and the compiler front end of this repository: `cmd → evevm → evecp → evecm`; eveux imports **evecp and evecm only**, not the VM). This gives, with no process hop and while the user types:

| Service | From | Use |
|---|---|---|
| diagnostics | `evecp` parser and `check` (the errors with file, line and column of `eve cp --check`) | red marks in the gutter, the Problems list |
| outline and symbols | the AST of the parser | the outline panel, go to symbol, go to definition, rename (later) |
| docs | `comp/evecp/src/doc.zig` (the `**` comments and the signatures) | hover and the completion list |
| keywords and operators | `spec/lexical/keywords.json` through `comp/evecm/src/ide/keywords.zig` | colors, completion |
| imports and libraries | the link step (`project.zig`: `lib/`, `$EVE_LIB_PATH`, the standard library folder) | open the file of a module, check across files |
| format (later) | a printer over the AST | Format on save |

What does **not** run in the process: the interpreter, the scheduler, databases, the network. `evecp` needs a small **tooling entry point** (to add: a function that takes a source text and a project root and returns diagnostics, an outline and the symbols in one pass, without writing files); the parser and the checker already exist and work on text. The standard library folder of the machine (`<prefix>/lib`) is found as the machine finds it.

### 4.2 Run and debug

Run, check and stop send `vm.run`, `vm.eval` and `vm.cancel` on a console session (`vm.open`); output arrives as `vm.output` and goes to the Console or Output tab. Debugging uses the debugger of the machine (`comp/evevm/src/debugger.zig`, F-TLS-04): the window sets breakpoints (`dbg.break`), starts (`dbg.start`), and on each stop asks for `dbg.locals` and `dbg.stack`; the yellow line, the Variables, Watch, Call stack and Breakpoints panels are drawn from the answers. Changing a variable while paused is allowed only with the machine's consent (an open question of the first design). Tasks of `parallel` aspects: step one task and hold the others (proposed).

## 5. Previews

A tab has a **viewer**, chosen from the kind of the file (`src/preview/kind.zig`, tested): text kinds open the editor; Markdown, HTML, images and SVG, audio and video, databases have their own viewer; anything else opens the card. The decoders run on worker threads.

| Kind | Viewer | Engine | First version | Later |
|---|---|---|---|---|
| Markdown | source / split / preview | `src/preview/markdown.zig` (parser written, tested) + a dvui drawer | headings, paragraphs, lists, code, quotes, rules, tables, links, images | nested lists, task lists, footnotes |
| HTML | source / split / preview | a **subset renderer**: block and inline layout, headings, lists, tables, links, images, colors, fonts, margins, `class` and `id` rules of a linked style sheet | no script, no forms, no iframes; **Open in browser** (`eve -u`) shows the real page | flexbox subset; optional embedded web view (WebView2 on Windows, WebKit on the others) as a separate step if the subset is not enough |
| CSS, JavaScript | editor | colorizers; check by a simple lexical scan | colors, bracket match, problems for unterminated strings | a syntax checker for JavaScript is not planned; the browser console is |
| Image | viewer | decoders: dvui uses stb_image (PNG, JPEG, BMP, GIF first frame); drawn as a texture | fit, zoom, pan, pixel info, checkerboard | animated GIF, EXIF |
| SVG | image viewer + source tab | convert to TinyVG (dvui's vector format) or a path rasterizer of our own *(to verify what svg2tvg supports)* | simple shapes and paths, text as placeholder | gradients, filters |
| Audio | player | the system decoder (Media Foundation on Windows) or a small library (miniaudio) | play, pause, seek, volume, length, tags | waveform |
| Video | player | the system decoder to a texture per frame | play, pause, seek, volume, speed | chapters; where no decoder exists, the card offers *Open with the system* |
| Database | tables and grid | `db.*` of the machine; SQLite and DuckDB files | tables, columns, data pages, structure | edit cells |

dvui has none of Markdown, HTML, SVG as such, audio or video: the first three are work in this project (the Markdown parser exists), the last two need an operating-system decoder behind a small interface (`src/preview/media.zig`, to write), written per platform. This is the largest platform-specific part and is why Windows (Media Foundation) comes first. evetx decided to show **no preview** (D-178); eveux reverses that for these kinds, as the author asked.

## 6. Reuse from evetx

The terminal client already solved the parts that have no screen. Surveyed 2026-10-18 (lines of `comp/evetx/src`, vaxis = the terminal library):

| File | Lines | vaxis | Use in eveux |
|---|---|---|---|
| `text.zig` | 616 | no | **as is**: the text buffer: lines, cursor, selection, insert, delete, **undo and redo** (checkpoints), match positions, display width of tabs and wide characters. The editor widget draws it. |
| `scan.zig` | 128 | no | **as is**: the Eve line scanner and the state of `/* */` and `(** **)` across lines (extracted from `view.zig` on 2026-10-18 for this purpose, with its tests). |
| `keywords.zig` | 109 | no | **as is**: generated from the spec; colors and completion. |
| `project.zig` | 207 | no | **as is**: the project tree (scan, expand, visible rows, database files with their tables as children). |
| `link.zig` | 217 | no | **as is**: the machine client: starts `eve --stdio`, sends `call(method, params)`, receives events (`output`, `done`, `failed`, `log`) on a thread. |
| `regex.zig` | 374 | no | **as is**: find and replace with patterns, find in files. |
| `grid.zig` | 163 | no | **as is**: the table model of data (TSV and DBF) that the grid widget draws. |
| `sqlstruct.zig` | 226 | no | **as is**: the SQL of the structure dialog (alter table text). |
| `cache.zig` | 152 | no | **as is**: the user cache folder, recent projects. |
| `options.zig` | 353 | via `theme` | **after a split**: the options and themes as data; the colors are vaxis types today. Split a neutral `Rgb` theme (data) from the vaxis mapping; eveux maps it to dvui colors. |
| `theme.zig` | 172 | yes | **split** as above: the three built-in themes become data shared by both. |
| `view.zig` | 3,000 | yes | **not reused**; the logic inside it (menus table, help text, the SQL scanner) moves to shared files when eveux needs it. |
| `app.zig` | 8,600 | yes | **not reused as is**: it mixes state and terminal events. The state types that have no terminal type (tabs, breakpoints, machine list) are the model for `comp/eveux/src/app.zig`; the key handling stays. |
| `main.zig` | 205 | yes | not reused (the terminal loop). |

**How it is shared (D-193, 2026-10-18):** the vaxis-free files of evetx moved to `comp/evecm/src/ide/` (text, scan, keywords, project, link, regex, grid, sqlstruct, cache), aggregated by `comp/evecm/src/ide.zig`. Inside `evecm` they are `evecm.ide` (the root build, where their 11 tests run with `zig build test`); `comp/eveux/build.zig` and `comp/evetx/build.zig` make the module `ide` from `b.path("../evecm/src/ide.zig")`, which needs no build options, and import it as `ide`. No copy: one set of files for both programs. A file that needs a screen type (`theme.zig`, `options.zig`) stays in its program until the neutral split of TD-33.

## 7. The code

```
comp/eveux/
  README.md  build.zig  build.zig.zon       this design; the build (dvui v0.5.0, module `ide`)
  design/
    gen_svg.py  *.svg                       the drawings (python comp/eveux/design/gen_svg.py)
    notes/                                  design-ideas.md (the author), elaboration.md, dvui.md
  src/
    main.zig                                the dvui app: window, frame loop            (draft)
    app.zig                                 state: tabs, project, machines, link         (written, tested)
    machine/api.zig                         the names of the machine messages           (written)
    view/                                   one file for each part of the screen
      shell.zig                             layout of the window                         (draft, not compiled)
      (menu, toolbar, explorer, tabs, status, dialogs, actions: to write)
    editor/
      lang.zig                              language of a tab, colored spans of a line   (written, tested; Eve only)
      (widget, html, css, js, json, xml, sql, md colorizers: to write)
    preview/
      kind.zig                              file kind and viewer                          (written, tested)
      markdown.zig                          Markdown subset to blocks and spans           (written, tested)
      (html, image, svg, media, card: to write)
    data/                                   tables, grid view, structure dialog           (to write)
    debug/                                  panels of the debugger                        (to write)
    vcs/git_status.zig                      parse of `git status`                         (written, tested)
    deploy/manifest.zig                     bundle manifest and diff, SHA-256             (written, tested)
    theme/                                  colors for dvui from the shared theme data    (to write)
  test/                                     cross-file tests (to write)
  assets/icons  assets/fonts                SVG icons, bundled fonts (to add)
```

**State of the draft (2026-10-18).** Written and tested with `zig test` (14 tests of eveux and the 9 of the shared files pass): `app`, `lang`, `kind`, `markdown`, `git_status`, `manifest`. With Developer Mode on (dvui needs symbolic links to fetch the `wayland` package of its SDL dependency) the whole program builds: `cd comp/eveux && zig build -p ../..` (or `./run.sh ux`) installs `bin/eveux.exe`, `zig build test` runs the six test roots, and `eve -ux [folder]` starts the window (a first stub: `main.zig`, `view/shell.zig`). The window is still the draft frame, not the IDE.

**Rules for the code** (as for evetx): the Zig comments are written for AI search with the tags of `CLAUDE.md` (`@eve-module`, `@spec`, `@feature`, `@decision`, `@tests`); no `// Zig tip:` blocks.

## 8. The editor widget

Built on `ide.text.Buffer` (lines, selection, undo and redo exist) and drawn by a **custom dvui widget**, not by `TextEntryWidget`, because the editor needs the gutter, glyph positions, per-line colors, bracket matching, folding, find marks and breakpoints. What the widget does: draw only the visible lines from the buffer, color each line with `lang.highlight` (the state `carry` of comments is kept for the first visible line by one pass over the lines above and updated line by line, as `evetx` does), draw the cursor and selection, handle keys, mouse, wheel and the clipboard, show the diagnostics of the embedded compiler as marks, scroll by pixel. Completion uses dvui's suggestion widget fed by the symbols and the keyword list. A 10 MB file draws only a screen of text each frame, so size is not a problem; the line scanner is linear in the line. The tree-sitter option of dvui's text entry is **not** used for Eve (the scanner of the repository is the source of colors); a tree-sitter grammar exists (`tools/tree-sitter-eve`) if a later widget wants it for HTML, CSS or JavaScript.

## 9. Database views

The explorer lists database files; a double click opens a **tables tab** (names, row counts, columns in Eve types) and a table opens a **data tab** (paged grid, sort, filter, the first rows with `db.sample`); the structure dialog edits fields and shows the `alter table` text (`sqlstruct.zig`); a **SQL tab** runs the statement under the cursor on a chosen connection (SQLite, an `evedb://` connection, PostgreSQL), with the result in a grid whose headers show the Eve types, copy as TSV, export CSV, JSON or an Eve `DataSet`, and Commit and Rollback for a statement that changes data. All of it goes through `db.*` messages of the machine; the window reads no database file itself. Which engine answers (SQLite in the machine, or the managed evedb child) is the machine's business and the tree shows it as a label (`design/notes/elaboration.md` §9).

## 10. Platforms and build

- **Windows (primary).** Backend SDL3 or DX11 (question 4). DX11 is one executable with no extra library and has no IME; SDL3 has IME and is the same code as the other systems. `zig build -p ../..` from `comp/eveux/` installs `bin/eveux.exe` (as evetx installs `bin/evetx.exe`); `-Dbackend=dx11` selects DX11.
- **Linux, macOS.** SDL3 (X11 and Wayland, Cocoa) or wio; later. Zig cross-compiles, so the build can be tried from Windows; real windows, clipboard, HiDPI and fonts need a real computer of each kind.
- **Fonts and text.** dvui draws one glyph per Unicode code point: Western, Greek, Cyrillic and Romanian letters are fine; combining marks, right-to-left and complex scripts are not. Eve's own text rules (ASCII names, Unicode in strings and comments) are covered; a CJK input method needs the SDL3 backend.
- **Zig version (done 2026-10-18).** The whole repository moved to Zig 0.17.0 and dvui to its main branch (TD-37); the pin is a commit, not a release.

## 11. Plan

| Step | Content | Gate |
|---|---|---|
| P0 | **Spike, two weeks at most**: build dvui v0.5.0 on Windows (needs Developer Mode, see section 7) with SDL3 and DX11; a window with menus, docking, tabs, a tree, the data grid with 1,000,000 virtual rows; a text view of a 10 MB file; Romanian letters and the clipboard; HiDPI; Linux and macOS builds | the numbers; go or stop |
| P1 | shared modules: `evecl` out of evetx; the theme split; evetx unchanged | evetx tests pass |
| P2 | shell: window, menus, docking, explorer over `ide.project`, tabs, status bar, the link to the local machine, run and the console | open a project, run a script |
| P3 | the editor widget with colors for Eve; the embedded diagnostics and outline; find and replace; save | edit and check a file |
| P4 | the other colorizers; Markdown preview; image and SVG viewer; the file card | open every kind |
| P5 | the database tabs, SQL tab, grid, structure dialog | direct SQL |
| P6 | debugger panels; breakpoints | debug a script |
| P7 | source control; deploy; login; jobs and logs | the flows of `design/notes/elaboration.md` |
| P8 | HTML renderer; audio and video; polish; Linux and macOS | version 1.0 per platform |

Features: F-TLS-19 (shell, editor, previews), F-TLS-20 (SQL and database), F-TLS-21 (jobs, logs, admin), F-TLS-22 (debugger) of `design/version_map.md`, F-TLS-31 (source control) and F-NET-10 (deploy) proposed in the elaboration. Tests: unit tests for the logic files (done for six), no automated screen tests (as evetx); a headless backend for screenshots is a question of the spike.

## 12. Findings, limits and risks

1. **The first finding (2026-10-18): the dvui fetch needs symbolic links (solved the same day by turning Developer Mode on; the program builds).** Zig cannot unpack the `wayland` package of dvui's SDL dependency on a Windows computer without Developer Mode (or an administrator); it fails for every backend. Options: turn Developer Mode on (Settings → For developers), or build on a machine that can and copy the package cache, or vendor a trimmed copy of dvui without the SDL dependency for the DX11 backend. This is a setup step for every Windows developer and for CI; it must be written in the manual.
2. **A code editor is real work.** dvui gives widgets, not an editor; the text model is reused, the drawing and interaction are new (section 8).
3. **No HTML engine.** The subset renderer will be wrong for real pages; Open in browser stays. A web view of the system is the escape, per platform.
4. **Audio and video need per-platform code** behind one interface.
5. **dvui is pre-1.0** and tied to the Zig version; the pin to v0.5.0 is safe and an upgrade costs work.
6. **IME and complex text** are weak (section 10).
7. **Automated testing** of the screen is not available; the logic has unit tests.
8. **Accessibility** depends on dvui's AccessKit flag.

## 13. Questions for the author

1. **Spike first.** Run P0 before building the shell, with the backend decision as one of its results? *Recommended: yes. It needs Developer Mode on one Windows computer.*
**Answer:**
2. **Developer Mode.** May the Windows development computers turn it on (needed to fetch dvui), or should a trimmed vendored copy of dvui be kept in the repository? *Recommended: turn it on; a vendored copy is a fork to maintain.*
**Answer:**
3. **Shared modules.** Done: the files moved to `comp/evecm/src/ide/` (module `ide`), not to a new `evecl/`; evetx and eveux import them.
**Answer:**
4. **Windows backend.** SDL3 by default (IME, same code everywhere), DX11 as an option? *Recommended: yes.*
**Answer:**
5. **HTML preview.** A subset renderer first and **Open in browser** for the real page, with a web view of the system only if the subset is not enough? *Recommended: yes.*
**Answer:**
6. **Audio and video.** Windows first with the system decoder (Media Foundation), other systems later, and the file card where no decoder exists? *Recommended: yes; or drop video from version 1.0 and keep audio and images.*
**Answer:**
7. **Embedded compiler.** Add a tooling entry point to `evecp` (diagnostics, outline and symbols from a text) as a small, separate step? *Recommended: yes; it also serves evetx.*
**Answer:**
8. **Level and schedule.** eveux is no longer level 7 work in Eve: start it after level 6 (version 0.5) with the native client? *Recommended: start P0 now, the rest after M4 of the library plan.*
**Answer:**
9. **JavaScript and CSS support.** Colors, bracket matching and simple lexical problems only, no JavaScript checker (the browser is the checker)? *Recommended: yes.*
**Answer:**
10. **Name.** Keep `eveux`? *Recommended: yes.*
**Answer:**
