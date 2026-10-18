# eveux: the Eve native workbench

Status: **design for review**, 2026-10-18. Nothing is built. `eveux` is the **graphical development client of Eve**, a native desktop program written in Zig on the GUI library [dvui](https://github.com/david-vanderson/dvui), for Windows first and later Linux and macOS. It replaces the browser "RAD Workbench" of the first design (kept in [../evewp/workbench-design.md](../evewp/workbench-design.md)); the web side of Eve, including the final test of the language, moved to [evewp](../evewp/README.md) (the Eve Web Portal).

The files of this folder:

| File | What |
|---|---|
| `README.md` | this design |
| [design-ideas.md](design-ideas.md) | the notes of the author (two tiers, deploy flow, eve as the server, SQLite and evedb as backends) |
| [design-elaboration.md](design-elaboration.md) | the idea notes checked against the plan: source control, deploy with manifest and versions, the machine messages, the backends, ten questions. Written for the browser design; every part that is about the server or the flow stands, the browser parts are replaced by this document |
| [design-native-dvui.md](design-native-dvui.md) | dvui in detail, the comparison with the browser design, the spike P0 |

## 1. What eveux is

`eveux` is to the graphical desktop what `evetx` is to the terminal: a **client of the Eve machine**. The machine does the work (files, Git, compile, run, debug, jobs, databases, deploy, logins); eveux shows it and takes the commands. Roles of the family (confirmed by the author, 2026-10-18): **`eve` is the server; `eveux` and `evetx` are the clients; `evedb` is the backend of the server; `evewp` is the production web layer.**

| It does | How |
|---|---|
| Edit Eve, SQL, JSON, XML, HTML, Markdown with syntax colors | a code editor widget on the shared text buffer and scanner |
| Run, check, debug (breakpoints, step, variables, watch, call stack) | `vm.run`, `vm.eval`, `dbg.*` with `vm.output` streamed |
| Command window and direct SQL with a result grid | a session of the machine (`vm.open`, `vm.eval`), `db.query` |
| Explorer: the local project, remote machines, databases, jobs, logs | `fs.*`, `db.tree`, `job.*`, `log.*` |
| Source control (status, diff, stage, commit, branches) | the local machine runs `git` with an argument list |
| Deploy to a machine or to an evewp application, with a diff, versions and rollback | `deploy.*` (`design-elaboration.md` §5) |
| Log in to remote machines (single sign-on, keyring) | the local machine holds the logins; the window never sees a secret |
| Jobs, schedule, live logs | `job.*`, `log.tail` |

It is a **development** tool. Production hosting, domains, monitoring and the web framework are `evewp`.

## 2. Why native, and why dvui

The first design ran the Workbench in a browser, written in Eve. Two things changed (2026-10-18): the author wants the final test of Eve to be **web development** (evewp, with an Eve framework compiled to WebAssembly), and wants a **native, platform independent GUI** for development. A native client starts at once, needs no web server on the computer (so none of the cookie, CSRF and CSP surface), shares real code with `evetx`, and can be built before level 7 because it needs only the machine API that exists (the stdio door).

dvui: an immediate-mode GUI toolkit in Zig, MIT licensed. The tag **v0.5.0 is tested with Zig 0.16**, our compiler; the main branch needs Zig 0.17. Backends: DX11 (Windows only, no extra library), SDL3 and SDL2, Raylib, GLFW, wio (OpenGL, Vulkan), pugl, Web. The details, the limits (no grapheme clusters or right-to-left text, IME only on SDL, no tree, tabs or code editor widgets) and the comparison with the browser design are in [design-native-dvui.md](design-native-dvui.md).

## 3. Architecture

```
 DEVELOPER'S COMPUTER                                                SERVERS
+---------------------------------------------+                  +--------------------------------+
| eveux.exe (Zig, dvui; DX11 or SDL3 backend) |                  | Eve machine (eve -s)           |
|   panes, menus, tabs, explorer, editor,     |                  |   runtime  vm.* deploy.* job.* |
|   console, grid, debugger, git, deploy      |                  |   database db.*  (SQLite,      |
|   machine client library (shared, evecl)    |                  |            evedb managed)      |
+----------------+----------------------------+                  +----------------+---------------+
                 | child process, stdio (JSON-RPC 2.0)                            ^
                 v                                                                | HTTP /rpc, WebSocket,
+---------------------------------------------+      or ssh host eve --stdio     | or SSH stdio
| Local Eve machine (eve --stdio)             | -------------------------------->+
|   files, git (os.run!), deploy, keyring,    |
|   logins, connections to the servers        |
+---------------------------------------------+
```

- **One connection to one local machine, on stdio**, exactly as `evetx` does (`evetx/src/link.zig`). No port, no socket, no web server. The local machine is the only holder of logins and keys; the window never talks to a server directly. A remote machine is reached by the local machine over HTTP and WebSocket (with the proxy in front) or by SSH (`ssh host eve --stdio`).
- **The same messages** as every client: `vm.*`, `db.*` and the additions of `design-elaboration.md` §6 (`deploy.*`, `fs.*`, `job.*`, `log.*`, `dbg.*`, `db.tree`, `db.describe`, `db.sample`). The machine API is the contract; eveux and evetx differ only in drawing.
- **Silent rule.** eveux is a window and never runs silent.
- **Shared Zig modules** taken out of `evetx` so both clients use them: `evecl` (the machine client: start `eve --stdio`, send requests, receive `vm.output`), the text buffer (`text.zig`), the Eve scanner and keywords (`Scan`, `Carry`, `keywords.zig`, generated from `spec/lexical/keywords.json`), the project tree (`project.zig`) and the theme colors. The arrows of `build.zig` allow it: both clients import them; `evecl` imports only `evecm`.
- **Local state** in the user cache `eve.db` (F-DAT-13, SQLite): layout, open tabs, theme, the list of machines without secrets, recent projects, the last manifest sent to each machine. State of a server lives in that server's core database.

## 4. The screen

The layout of the first design carries over (a menu bar, an explorer at the left, a tabbed editor in the center, a bottom panel with Command, Output, Results, Problems and Log, a debug side bar at the right, a status bar with the machine, the version and the user); the menus and the shortcut table are the ones of `evewp/workbench-design.md` §5, now drawn by dvui. One table holds menu items, shortcuts and the command palette. Two themes (dark, light) as small files of colors; the color names are those of `evetx` themes so a theme is shared.

| Part | dvui | To build |
|---|---|---|
| menus, popups, tooltips, toasts, dialogs, resizable panes, native file dialogs | yes | the shortcut table, layout persistence |
| tabs | no | a tab bar widget |
| explorer tree (lazy children, icons, context menu) | no | a tree widget; reused by the database tree and the debugger variables |
| **code editor** | multi-line text entry only | a custom widget: gutter with line numbers and breakpoints, colors, find and replace, brackets, undo and redo, large files; the largest work item |
| command window | text layout | scrollback, input line, history |
| SQL result grid | a data grid | virtual rows, sort, filter, Eve types, copy; to verify at 1,000,000 rows |
| help and About | text layout | a small Markdown renderer |

## 5. Platforms

| Platform | Backend | State |
|---|---|---|
| **Windows (primary)** | DX11 (single executable, no IME) or SDL3 (IME, built from source by the Zig build) | to choose in the spike (Q-4) |
| Linux | SDL3 (X11, Wayland) or wio | later; to verify |
| macOS | SDL3 or GLFW | later; the weakest evidence in the dvui repository |

Zig cross-compiles, so the build of the other systems can be tested from Windows; windows, clipboard, HiDPI and fonts need a real computer of each kind. Windows is first (the author's order); nothing in the design depends on a Windows API except the optional DX11 backend.

## 6. Relation to the other programs

- **evetx** stays: the terminal client for SSH and quick work, and the source of the shared modules. Both clients follow the same machine API and the same menus.
- **evewp** is where applications are deployed to; eveux has a *Deploy to* command for an evewp application and shows its state (a read-only view of the evewp dashboard data, `job.*`/`log.*` of the application's machine).
- **eve** gives the doors; `eve -ux` starts eveux (as `eve -tx` starts evetx), from beside `eve`.
- The first design (browser, Eve): the editor, SQL console, debugger and job pages it described are now this program. Its sections are not lost: the login rules (`workbench-design.md` §6), the explorer (§7), the editor colors (§8), the command window (§9), jobs (§10), the debugger (§11) and files and import (§12) are the functional specification of eveux; only the drawing and the transport change.

## 7. Plan

| Step | Content | Gate |
|---|---|---|
| P0 | **Spike, two weeks at most** (`design-native-dvui.md` §9): dvui v0.5.0 on Zig 0.16, both Windows backends, a text entry with 1 MB, a data grid with 1,000,000 virtual rows, the tree-sitter flag, Romanian letters and the clipboard, HiDPI, a Linux and a macOS build | the numbers and the answers; go or stop |
| P1 | `evecl` and the other shared modules out of evetx; evetx uses them | evetx unchanged |
| P2 | shell: window, menu table, panes, tabs, explorer over `vm.*` and `fs.*`, status bar | open a project, run a script, see its output |
| P3 | editor widget with colors for Eve, then SQL, JSON, XML | edit and save a file |
| P4 | command window, SQL tab and grid, database tree | direct SQL on SQLite and on evedb |
| P5 | source control, deploy, jobs, logs, login | the flows of `design-elaboration.md` |
| P6 | debugger, help, packaging, Linux and macOS ports | version 1.0 on each platform |

The features are F-TLS-19 to F-TLS-22 of `plan/version_map.md` (editor and shell, SQL and database tree, jobs and logs, debugger), moved from level 7 to the time after the spike; F-TLS-31 (source control) and F-NET-10 (deploy) are the proposals of `design-elaboration.md`. Tests: unit tests for the machine client, the buffer, the scanner and the tree model (`zig build test` in `eveux/`); the screen is tested by hand, as evetx is; a headless backend for screenshots is a question of the spike.

## 8. Questions for the author

1. **Spike first?** Run P0 before building, with the dvui backend decision (DX11 or SDL3) as one of its results? *Recommended: yes.*
**Answer:**
2. **Shared modules.** Take `evecl`, the buffer, the scanner and the keywords out of evetx now (P1) or after the spike? *Recommended: after the spike says go; the work is the same and a stop costs nothing.*
**Answer:**
3. **Level.** eveux is no longer a level 7 project written in Eve: it can start as soon as the stdio door and the machine API serve it. Keep the features F-TLS-19 to F-TLS-22 in version 0.6, or move them to version 0.5 (level 6) with the native client? *Recommended: version 0.5, level 6 test for the machine messages, the client unit-tested.*
**Answer:**
4. **Windows backend.** DX11 (one executable, no IME) or SDL3 (IME and the same code on the other systems)? *Recommended: SDL3 by default, because the port is then a build option; DX11 kept as an option for a smaller executable.*
**Answer:**
5. **Help.** A Markdown subset renderer of our own in the first version, or help in the browser (`eve -u`) with a native About only? *Recommended: browser help first.*
**Answer:**
6. **Zig version.** Pin dvui v0.5.0 on Zig 0.16 and move to 0.17 with the rest of the project? *Recommended: yes.*
**Answer:**
7. **Name.** Keep `eveux` for the native client, as the folder is now free for it? *Recommended: yes.*
**Answer:**
