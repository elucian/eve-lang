# eveux, second design: a native GUI in Zig with dvui

> **Update 2026-10-18.** This analysis became the base of `eveux/README.md`: the author moved the browser Workbench to **evewp** (the Eve Web Portal, a production web server and a web framework in Eve, `evewp/README.md`) and made `eveux` the native Zig client. So the conflict with D-154 of section 7 is resolved by the move: the final test of Eve is evewp (option 2a for eveux, with the language test kept in evewp). The comparison table, the dvui facts and the spike (sections 2, 6, 9) stay valid.

Status: **proposal for comparison**, 2026-10-18. It is the second design of eveux, next to the first one (`eveux/README.md` with `eveux/design-elaboration.md`: a browser Workbench written in Eve, D-154). **Nothing in `spec/`, the tutorial, the plan or the code was changed for it.** The facts about dvui come from its public repository (links at the end); what I could not confirm from there is marked *to verify* and is the content of the spike in section 9.

## 1. The idea

eveux becomes a **native desktop program written in Zig** on [dvui](https://github.com/david-vanderson/dvui), an immediate-mode GUI toolkit (MIT license). It is the graphical sibling of evetx: the same job (a client of the Eve machine: edit, run, debug, jobs, logs, databases), in a window instead of a terminal. It is built for **Windows first**, with Linux and macOS as later ports of the same code.

What stays from the first design (everything about the *server* side): Eve is the server, eveux and evetx are clients, evedb is the backend of the server; one set of JSON-RPC messages (`vm.*`, `db.*` and the additions of `design-elaboration.md` §6: `deploy.*`, `fs.*`, `job.*`, `log.*`); the local machine holds the logins and the keyring; local Git and deploy as in `design-elaboration.md` §4 and §5. Only the **client** changes.

What does not stay: D-154 says eveux is written in Eve as the final test of the language, with no Zig in `eveux/`. A dvui eveux is Zig. That is the main cost of this design (section 7).

## 2. dvui in short (checked 2026-10-18)

| Item | What the repository says |
|---|---|
| Kind | immediate-mode GUI in Zig, for whole applications or for tool windows over an existing program or game |
| License | MIT (with TinyVG, same author terms) |
| Zig | the branch `main` (version `0.6.0-dev`) needs **Zig 0.17**; the tag **v0.5.0** is "tested with Zig 0.16.0", the version of this project |
| Backends | SDL3, SDL2, SDL3 GPU, Raylib (C and raylib-zig), **DX11** (Windows, Win32 binding), GLFW + OpenGL, wio (OpenGL or Vulkan), pugl (OpenGL), Web (WebAssembly); each as *app* (dvui runs the loop), *standalone* or *on top* of another program |
| Widgets | single and multi-line text entry, number entry, text layout with styled and clickable parts, floating windows, menus, popups and context menus, scroll areas, buttons, links, tooltips, sliders, checkboxes, radio buttons, toasts, resizable panes, dropdown, combo box, reorderable lists, a **data grid**, group boxes; native file dialogs through tinyfiledialogs |
| Not listed | a **tree** widget, **tabs**, docking, a **code editor** (line numbers, syntax colors, find and replace, folding), a terminal-like console |
| Text | FreeType or stb_truetype; one glyph per Unicode code point; **no grapheme clusters, no right-to-left or mixed direction** |
| Input | most widgets work by keyboard; **IME only on the SDL and web backends** (not on DX11) |
| Accessibility | screen reader support through AccessKit with `-Daccesskit`; high-contrast themes; no integration with the operating system beyond that |
| Optional | a `tree-sitter` build flag for the text widgets (tree-sitter dependencies for JSON and Zig are in `build.zig.zon`); *to verify* what it gives |
| Size of the project | about 1.7k stars, 4,200 commits, 86 open issues; a devlog; featured projects such as Fizzy, Graphl and a podcast player. Pre-1.0: the version is `0.x` and the Zig requirement moves with the compiler |

## 3. Architecture

```
 DEVELOPER'S COMPUTER                                                SERVER (one or many)
+---------------------------------------------+                  +----------------------------------+
| eveux.exe (Zig, dvui, DX11 / SDL3 backend)  |                  | Eve machine (eve -s)             |
|   UI: menus, panes, tabs, tree, editor,     |   stdio / IPC    |   runtime  vm.*  deploy.* job.*  |
|       grid, console, debug panels           |  (JSON-RPC)      |   database db.*  SQLite + evedb  |
|   machine client (shared with evetx)        | <--------------> |   UI part: HTTP / WebSocket door |
+----------------+----------------------------+                  +----------------------------------+
                 | child process, stdio                                      ^
                 v                                                           | HTTP /rpc, WebSocket,
+---------------------------------------------+      or SSH stdio             | or ssh host eve --stdio
| Local Eve machine (eve --stdio)             | ---------------------------->-+
|   files, git (os.run!), deploy, keyring,    |
|   logins, connections to remote machines    |
+---------------------------------------------+
```

- **Process model.** `eveux.exe` starts the local machine as its child on the **stdio door** (`eve --stdio`), exactly as evetx does. No port, no socket, no web server on the computer: the **web security surface of the first design disappears** (one-time key, session cookie, CSRF, CSP, Origin checks). The window is the only client of that machine.
- **Remote machines.** As before the program never talks to a remote machine itself; the local machine does, with the logins in the keyring. SSH (`ssh host eve --stdio`) works as a second kind of connection, unchanged.
- **Silent rule.** eveux never runs silent (it is a window). `eve -s` with a UI is refused as before.
- **A shared Zig library for the clients.** evetx already has a machine client (`evetx/src/link.zig`: starts `eve --stdio`, sends JSON-RPC, reads `vm.output`). It would move to a module of its own (for example `evecl`, imported by evetx and eveux; the arrows of `build.zig` allow it). The text buffer of evetx (`text.zig`), the comment and string scanner (`Scan`, `Carry`, fixed on 2026-10-18), the keyword list generated from the spec (`keywords.zig`), the project tree logic (`project.zig`) and the theme colors (`theme.zig`) are independent of the screen and can be shared the same way. This is the strongest argument for this design: **half of the client logic exists, tested, in Zig.**
- **Where dvui code lives.** `eveux/` becomes a Zig module like `evetx/`: `src/main.zig`, `view/*.zig` (one file for each panel), the dvui dependency pinned to the tag v0.5.0 in `eveux/build.zig.zon` (a dependency of this module alone, like libvaxis for evetx).

## 4. Screen and widgets

The screen of `eveux/README.md` §5 (menu bar, explorer, tabbed editor, bottom panel, debug side bar, status bar) carries over. What dvui gives and what must be built:

| Part | dvui | To build |
|---|---|---|
| Menu bar, context menus, tooltips, toasts, dialogs | yes | style and shortcuts table (one table for menu, keys and palette, as `js/actions.js` was planned) |
| Panes with draggable borders | yes (resizable panes) | layout persistence in `eve.db` |
| Tabs of the editor and of the bottom panel | not listed | a tab bar widget from buttons and a scroll area (small) |
| Explorer tree (machines, files, database objects) | not listed | a tree widget with lazy children, icons, context menu, keyboard navigation (medium) |
| **Code editor** | multi-line text entry only | **a custom widget**: line numbers, gutter with breakpoints, syntax colors (the shared scanner for Eve; a scanner each for SQL, JSON, XML, HTML), current line, matching brackets, find and replace, go to line, undo and redo, selection, large files, tabs and indentation, Unicode. **The largest single piece of work (large).** |
| Command window and output | text layout | a scrollback with colors, input line, history (medium) |
| Result grid for SQL | a data grid | paging, sorting, filtering, Eve types, copy as TSV; *to verify* that the grid virtualises rows for 1,000,000 results (the first design pages in the browser too) |
| Debugger panels (variables, watch, call stack) | list and tree parts | a tree for variables (reuses the explorer tree) |
| Job browser, calendar of the scheduler, log viewer | scroll areas, lists | calendar widget (medium); log viewer with follow mode (small) |
| Help and About | text layout | the help pages are Markdown: **no Markdown or HTML renderer** in dvui; a small Markdown subset renderer (headings, paragraphs, lists, code, links) is needed (medium) |
| File dialogs | native (tinyfiledialogs) | none |
| Import wizard, login forms, admin pages | forms of widgets | many small windows (medium) |

## 5. Platforms

| Platform | Backend | Notes |
|---|---|---|
| **Windows (primary)** | **DX11** (no extra library: a single `eveux.exe` and the Win32 binding) or **SDL3** (built from source by the Zig build, so no DLL to ship; has IME) | The DX11 backend has no IME (CJK input). Normal keyboards, dead keys and AltGr for Romanian and other European letters arrive as character events and work; *to verify* with a sample. |
| Linux | SDL3 (X11 and Wayland) or wio (OpenGL or Vulkan) | the repository only mentions Linux in notes about Wayland and X11; *to verify* by building the examples |
| macOS | SDL3 or GLFW | not mentioned in the README; *to verify* (this is the weakest evidence) |
| Web | dvui Web backend (WebAssembly) | possible later: the same code in a browser, without JavaScript; useful for the playground of level 7 (F-WEB-03), not a goal now |

Zig cross-compiles, so the Linux and macOS binaries can be built from the Windows machine for testing the build; the *behavior* of windows, clipboard, HiDPI and fonts on those systems needs a real computer of each kind (the repository says nothing about clipboard or HiDPI: *to verify*). The Windows-first order of the author is respected: nothing in the design depends on a Windows API except the optional DX11 backend; with SDL3 as the default, the port is a build option.

## 6. Pros and cons against the first design (browser, in Eve)

| Topic | First design: browser + Eve (D-154) | Second design: native dvui in Zig |
|---|---|---|
| **Purpose of D-154** (eveux as the final test and stress test of Eve) | **kept**: the server of the Workbench is a big Eve program (routes, aspects, modules) | **lost** for the UI: the application is Zig. Partly regained only if the logic layer stays in Eve (option 2b below) |
| Language and team | Eve for the server, JavaScript and CSS for the page (two more languages to maintain) | Zig only; one language, the same as evetx and the VM. But "the team does not know Zig" (CLAUDE.md, the old didactic rule) |
| Code shared with evetx | none (JavaScript) | **a lot**: machine client, text buffer, scanner, keywords, project tree, themes |
| Editor quality | the page can use the browser's text engine: Unicode, IME, bidirectional text, accessibility, fonts, emoji, selection, spell check; a code editor widget still has to be written in JavaScript (or a library is adopted) | must be **written from the text widget up**; no grapheme clusters, no RTL, IME only on SDL; the largest work item |
| Look, themes, layout | CSS: rich layout, easy themes, HTML help pages, Markdown, SVG | dvui themes and a custom look; no HTML/Markdown/SVG renderer; layout is code |
| Start-up and weight | a local web server plus a browser tab; opening takes a moment; browser memory | one executable, starts at once; small memory; GPU drawn |
| Large data (1,000,000 rows, 200 MB logs) | the DOM needs virtual lists written by hand | immediate mode draws only what is visible by design; the data grid *to verify* |
| Security surface | localhost HTTP and WebSocket, cookie, CSRF, CSP, one-time key, Origin check, XSS discipline (escape everything) | none of that: stdio to a child process; the only input is the machine's own JSON |
| Remote use of the Workbench | possible (not intended: "local only") | not possible without a remote desktop; SSH to the servers still works |
| Automated tests | strong: the API of the Workbench is driven by Eve scripts and the HTTP client (`test/level7`), the page by a headless browser | weak: like evetx, the screen is tested by hand; the machine client and the widgets' logic (buffer, scanner, tree model) have unit tests; a headless backend of dvui for screenshots is *to verify* |
| Accessibility | the browser's (screen readers, zoom, high contrast) for free | AccessKit flag, keyboard navigation; behind the browser |
| Ecosystem and risk | stable web platform for decades | dvui is pre-1.0 (0.6.0-dev), moves with Zig (main needs 0.17, v0.5.0 is the 0.16 line), small team; our pin to v0.5.0 is safe, an upgrade costs work each time |
| Distribution | `eve` plus a folder of web files; any browser | a second executable per platform, with the platform matrix of section 5 |
| Reuse by users | none outside eveux | a base: the same dvui could draw Eve-made tools, dashboards for ETL, and the Web backend gives the same UI in a browser |
| Fit with the schedule | level 7 needs the whole Eve stack first (`serve`, WebSocket, login, HTML templates) | needs only the stdio door and the machine API that exist now (evetx runs on them), so it can **start before level 7** |

**Summary.** The native design is faster to start, lighter, safer by construction and shares real code with evetx, and it removes the web stack. It gives up the language acceptance test of D-154, the free text engine and accessibility of the browser, and the automated tests of the first design, and it takes on the cost of building a code editor and a tree on a young toolkit. The first design is slower to reach and heavier at run time, but it is the one that makes eveux "the final test of Eve".

## 7. The conflict with D-154, and three ways out

D-154 (2026-10-10): eveux is **written in Eve**, in level 7, "Zig only for the VM". A dvui eveux contradicts it, so the author must choose:

- **2a. Replace.** The native client replaces the browser Workbench. D-154 is revised: the final test of Eve becomes something else (for example the library work now in progress, which already acts as one: `test`, `config`, `rpc`, `http`, `route`, `service` found seven gaps). Simplest; loses the big application test.
- **2b. Native shell, logic in Eve.** The window is Zig; the *logic* of the Workbench (machines, jobs, deploy, grids, source control) stays a big Eve project that the local machine runs, exposing its results as JSON-RPC `ux.*` methods that the Zig window calls. The window is thin; Eve keeps the stress test (server side only: aspects, modules, `http`, `route`, `rpc`, database, tasks, streams). The cost is two programs again, but no JavaScript and no web stack.
- **2c. Both.** The browser Workbench (first design, in Eve) stays the language acceptance test at level 7 and may be a smaller product; the native client is the day-to-day tool, built first because it needs less of Eve. Both speak the same API, which is the point of keeping the API clean (`design-elaboration.md` §6). This is the most work.

A fourth idea, **an Eve binding for dvui** (Eve code that draws immediate-mode widgets, run in-process), would make the UI itself Eve code. It needs the interpreter linked into the window program, a widget API in Eve and a frame loop in the baton scheduler: a large research item, not proposed now.

## 8. Plan of the native design (if chosen)

| Step | Content | Gate |
|---|---|---|
| P0 | **Spike, two weeks at most**: build dvui v0.5.0 with Zig 0.16 on Windows (DX11 and SDL3 backends); open a window with menus, panes, a tab bar, a tree, the data grid with 1,000,000 virtual rows, a multi-line text entry with a 1 MB file, the `tree-sitter` flag, a Romanian text sample, clipboard and HiDPI; build the same on Linux and macOS (cross compile, then run if a machine is at hand) | the numbers and the list of *to verify* items answered; go or stop |
| P1 | module `evecl` (machine client) taken out of evetx; evetx uses it; unit tests | evetx behaves as before |
| P2 | `eveux` shell: window, menu table, panes, tabs, explorer tree over `vm.*` and `fs.*`, status bar, connection to the local machine on stdio | opens a project, runs a script, shows its output |
| P3 | **Editor widget** on the shared buffer and scanner: colors for Eve first, then SQL, JSON, XML; gutter; find and replace; undo | edit and save a project file; comparable to evetx's editor |
| P4 | Command window, SQL tab with the grid, database tree (`db.*`) | direct SQL on SQLite and evedb |
| P5 | Jobs, logs, source control panel, deploy dialog, login (level 7) | the flows of `design-elaboration.md` §4 to §6 |
| P6 | Debugger panels; Help (Markdown subset); packaging; Linux port; macOS port | the exit of eveux 1.0 for each platform |

## 9. What the spike must answer (the *to verify* list)

1. Does v0.5.0 build with our Zig 0.16 build on Windows, with each backend, and what does it add to the build time and to the size of the executable?
2. How good is the multi-line text entry as the base of an editor: speed with 1 MB and 10 MB, selection, scrolling, undo and redo, tab key, access to the cursor and the glyph positions (needed for gutter, brackets and colors), custom styled runs per line?
3. What does the `tree-sitter` flag give, and is it a path to colors for Eve (a grammar exists now: `tools/tree-sitter-eve`)?
4. Does the data grid virtualise rows, sort, resize and select cells?
5. Windows input: dead keys, AltGr, Romanian letters (ă â î ș ț), clipboard with Unicode text, drag and drop of files, HiDPI scaling, window state saved and restored.
6. SDL3 on Windows: IME, and the effect of building SDL from source on the build.
7. Linux and macOS: does the same code open, draw, take keys and the clipboard on a real machine?
8. A headless or testing backend for screenshot tests.

## 10. Recommendation

Do not decide on paper. **Run the spike P0**, which costs little, and decide with its numbers. Meanwhile keep the server work (the `design-elaboration.md` API) as the single contract, because it serves both clients. If the editor widget and the platform checks go well, the best split looks like **2c**: the native dvui client as the working tool, early and shared with evetx, and the browser Workbench in Eve kept for level 7 as the acceptance test of the language that D-154 wants. If the author puts the weight on the language test, keep the first design and let evetx remain the fast client.

## 11. Questions for the author

1. **Direction.** Spike first (recommended), or choose now between the first design, 2a, 2b and 2c?
**Answer:**
2. **D-154.** If a native client is built, is "eveux is written in Eve" given up (2a), kept for the logic (2b), or kept as a second, browser product (2c)?
**Answer:**
3. **Name.** Both products named `eveux`, or the native one gets another name (for example `evegx`)?
**Answer:**
4. **Backend on Windows.** DX11 (single executable, no IME) or SDL3 (IME, one more library built from source) as the default?
**Answer:**
5. **Zig version.** Pin dvui v0.5.0 on Zig 0.16 now and move to 0.17 with the rest of the project later?
**Answer:**
6. **Shared code.** Take `evecl` (machine client), the text buffer, scanner and keywords out of evetx into shared modules, in the spike or after it?
**Answer:**
7. **Help and Markdown.** A small Markdown renderer of our own, or help shown in the browser (`eve -u`) while the app has a native About only?
**Answer:**

Sources: [dvui repository (main)](https://github.com/david-vanderson/dvui), [dvui v0.5.0 (Zig 0.16)](https://github.com/david-vanderson/dvui/tree/v0.5.0), [dvui `build.zig.zon`](https://raw.githubusercontent.com/david-vanderson/dvui/main/build.zig.zon), [dvui license](https://raw.githubusercontent.com/david-vanderson/dvui/main/LICENSE).
