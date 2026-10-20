# evetx: the Eve text user interface

Status: **design for review**, eighth draft 2026-10-13 (D-174 to D-178). **Implementation in progress** (D-178): what works is in §11, the checklist in [status-level6.md](../../backlog/evetx-status.md). **Cut on 2026-10-16:** remote machines, upload, the Markdown preview and the border delay are out of the program; the sections below that describe the machines (§1, §3 Machines, T5) are design for later. Planned for **level 6** (version 0.0.6, phase B of [design-packages.md](../../design/design-packages.md), step B6). Recorded as Q-050, D-173 to D-178, Q-053 to Q-057 in [decision_level6.md](../../design/decision/level6.md); features F-TLS-24, F-TLS-27 and F-TLS-28 of [feature_map.md](../../design/feature_map.md). **Changed by the author on 2026-10-13 (D-173):** evetx is a **project IDE in the terminal**: a tree of the project files, an editor, run and debug buttons, a bottom panel, and database tabs. It is not a machine manager any more: the machines are chosen with F1 to F3. The first draft (a machines list in the sidebar, a Run view) is replaced; schedules and the management of runs stay in `eveux` (D-172).

## 1. What evetx is

`evetx` is a **full-screen terminal application** (TUI), written in Zig on the library **libvaxis**, in which a person works on **one Eve project** at a time:

- browses the files of the project in a **tree** (folders open and close);
- **edits** a file in the right panel, which opens at a click on the file;
- **runs** a program and **debugs** it (breakpoints, step into, step out, continue, stop, watch);
- reads **Console**, **Watch**, **Stderr**, **Stdout** and **Breaks** in the bottom panel;
- sees a **file card** (name, type, size) for a file that is not text: image, SVG, audio, video (no preview; `eveux` shows them rendered);
- opens a **database file** of the project, sees its tables, browses their data in tabs and edits the structure in a dialog;
- *later, not in this version (cut 2026-10-16):* **connects** to a remote machine, **uploads** the server side of the project, and runs and debugs there; the machine is chosen with **F1** (local), **F2** (a remote machine), **F3** (another one).

It works over SSH and needs nothing but a terminal: started inside an SSH session on the remote computer, it edits the files that are there. Code is local, a tested project is deployed, and a deployed project is operated by schedules or evewp, not run by hand (D-195). It is the terminal sibling of the browser Workbench [eveux](../eveux/README.md): the same machine API, another screen.

| | `eveux` (level 7) | `evetx` (level 6) |
|---|---|---|
| Screen | browser (HTML, JavaScript, CSS) | terminal (libvaxis) |
| Written in | Eve (D-154) plus a small Zig door | Zig, with one dependency: libvaxis |
| Edit, run, debug | yes | yes |
| Databases | tree, SQL grid, import | tables, data tabs, structure dialog |
| **Schedules, run history, job browser** | **yes** (F-TLS-21, D-172) | **no** |

`evetx` does **not** run the user's code itself. Every run, step and query is a call of the machine API (`vm.*`, `db.*`, D-165) to the selected machine, the same call `eve -c … -rem <machine>` sends. What `evetx` can do is what the machine allows to the logged-in user. The code in the drawings is only illustrative.

## 2. The drawings

| Drawing | Shows |
|---|---|
| [design.svg](design/design.svg) | the main screen: file tree, editor tabs, run and debug buttons, bottom panel, status line |
| [design-debug.svg](design/design-debug.svg) | paused at a breakpoint: yellow arrow, Watch tab, Run off and the step buttons on |
| [design-breaks.svg](design/design-breaks.svg) | the Breaks tab: select a breakpoint, Remove it, or double-click to jump to it |
| [design-db.svg](design/design-db.svg) | a database file selected: its tables in a tab |
| [design-data.svg](design/design-data.svg) | the data of a table in a new tab |
| [design-structure.svg](design/design-structure.svg) | the structure dialog: a grid with headers and bordered cells, the type chosen from a list |
| [design-calendar.svg](design/design-calendar.svg) | the Default cell of a date or time field with its calendar |
| [design-menu.svg](design/design-menu.svg) | the main menu (a click on the title, or Ctrl+Enter) with the shortcuts, Save and Save As |
| [design-help.svg](design/design-help.svg) | the help dialog (Ctrl+/) |
| [design-goto.svg](design/design-goto.svg) | the `#` button: go to a line or a record |
| [design-filecard.svg](design/design-filecard.svg) | the file card of a binary file (image, SVG, audio, video) |
| [design-dialogs.svg](design/design-dialogs.svg) | select project, connect, upload, the data flow and the keys |

![the main screen](design/design.svg)

![debugging](design/design-debug.svg)

![the Breaks tab](design/design-breaks.svg)

![a database file: the tables](design/design-db.svg)

![the data of a table](design/design-data.svg)

![the structure of a table](design/design-structure.svg)

![the calendar](design/design-calendar.svg)

![the main menu](design/design-menu.svg)

![the help dialog](design/design-help.svg)

![go to a line](design/design-goto.svg)

![a file card](design/design-filecard.svg)




![dialogs and data flow](design/design-dialogs.svg)

All the drawings are in [design/](design/). They are written by `design/gen_svg.py`; change a drawing there and run `python code/evetx/design/gen_svg.py` from the repository root, or edit an SVG by hand.

## 3. The screen

```
┌ title ▾ (menu) · project ───────────────────────── F1 local  F2 prod  F3 test ┐
│ Files [______] │ Find [______][code] Replace [______] [Replace] [Replace all] [#] │
├───────────────┬────────────────────────────────────────────────────────────────┤
│ project files │ tabs: file · file · table list · table data                    │
│  (tree)       │ editor, or table list, or table data                           │
│               │ [Run] [Step into] [Step out] [Continue] [Stop]      buttons    │
│               │ bottom tabs: Console · Watch · Stderr · Stdout · Breaks        │
├───────────────┴────────────────────────────────────────────────────────────────┤
│ ▕ state ▕ file or table name ▕ Ln, Col · Record, Field ▕ [?] [⚙] ▏  (inset)   │
└────────────────────────────────────────────────────────────────────────────────┘
```

**Title and main menu.** The title `evetx ▾` at the top left is a button: a click opens the **main menu**, and **Ctrl+Enter** opens the same menu from the keyboard. It lists File (Open project, New file, **Save**, **Save As**, Close tab, Quit), Edit (Undo, Redo, Find, Replace), Run, Machine (Connect, Upload, Next machine) and Help (Help, Settings), each with its shortcut ([design-menu.svg](design/design-menu.svg); the shortcuts are proposed, Q-054 a).

**The two searches and the `#` button** (under the title bar): the bar is split in two, and **each search sits above the panel it searches** (D-175, D-176, [design.svg](design/design.svg)).

| Control | Above | Does | Behavior |
|---|---|---|---|
| **Files** (left) | the file tree | finds a **file name** | **the names that start with the letters typed** (not the text anywhere): the tree **goes to the first match while you type**, opening the folders that lead to it, and keeps the rest of the tree in place; the matches are amber, the header says `1 of 2`; ↓ and ↑ go to the next and previous match, Enter opens the file, Esc clears the field and restores the folders as they were |
| **Find** (right) | the right panel | searches **code, table names or data**, by the tab that is open (the scope follows the tab) | an editor: the text of the file; a table list: the tables (the list is filtered); a data tab: **every column of the table**, global; a small tag in the field says `code`, `tables` or `data` |
| **Replace**, **Replace all** (right) | the right panel | replace in the text of an editor | on only for an editor; off in a table list and a data tab |
| **#** (right end) | the right panel | **jumps**: to a **line number** in an editor, to a **record** (its number, or its id) in a data tab | a small prompt under the button (Enter jumps, Esc closes; [design-goto.svg](design/design-goto.svg), [design-data.svg](design/design-data.svg)) |

**The data search.** It is global: it looks in **every column**. A `*` inside the text stands for any text (`op*n` finds `open`); a search that is a **number** finds by number (an id, a quantity, an amount equal to it). In the drawing `op*n` leaves the 3 rows whose status is `open`, and the database does the filtering (Q-056 c).

**Files that are not text** (D-178). **There is no preview in evetx and no preview button.** A text file (Eve, SQL, JSON, Markdown, HTML, any text) opens in the editor **as source**. Any other file, **including images, SVG, audio and video**, opens a **file card** with its facts: name, type, path, size, modification time, and which side it is on (local or server). The card says that **the rendered file is shown by `eveux`** (`eve -ux`), which draws images, SVG, Markdown and HTML properly ([design-filecard.svg](design/design-filecard.svg)).

**Settings** are opened by the gear of the status bar and by the menu (Q-054 b); the top bar no longer has a gear. Which field has the keyboard is shown by its blue border (Q-055 b).

**Status bar** (bottom, drawn as a bordered inset box with divided cells): the state (`Ready: connection: prod`, `Paused · connection: prod`, `Running…`), the **name of the file or table** that is selected, and the **place**: `Ln 8, Col 12` in an editor, `Record 1043 of 1,204 · Field: amount` in a data tab, `Table 1 of 4: orders` in a table list, `Field 5 of 9: amount` in the structure dialog. At the right, a button **?** (the help dialog, **Ctrl+/**) and a **gear** (settings, Q-054 b).

**Console** (bottom tab): it has **the design of the console of evevm** (`manual/usage.md`, "The screen"): the upper part is the output with its own scrollback (PgUp, PgDn, a scroll bar), then a rule, the command line `eve:> `, and a rule. Ctrl+Up and Ctrl+Down walk the history; Tab completes. The `Ready` and `Running…` state is in the status bar of the application (Q-054 h).

**Sidebar: the files of the project.** A tree: a folder opens and closes (click, Enter or the arrows) and shows its sub-folders and files. A click on a file opens it for editing in the right panel, in a tab. The server-side folders (`proc/`, `server/`, `sql/`, `web/`, Q-052 a) carry a blue dot: they are what the upload sends. `eve.env` is shown dimmed as ignored. A database file (`.db`, `.duckdb`) opens a table list instead of an editor.

**Tabs of the right panel.** Three kinds, and only three:

| Tab | Content |
|---|---|
| a **file** | the editor; the name shows a mark when the file is changed and not saved |
| a **table list** | the tables of a database file; opened by selecting the file in the tree |
| a **table data** | the rows of one table, page by page |

**The structure of a table is never a tab.** It is edited in a dialog (§6).

**Buttons above the bottom panel:** **Run**, **Step into**, **Step out**, **Continue**, **Stop** (keys proposed: F5, F11, Shift+F11, F8, Shift+F5; F9 toggles a breakpoint). Which are on depends on the state: idle (only Run), paused (all but Run), running (only Stop). Step over is not in the author's list (Q-053 e).

**Bottom panel, five tabs.**

| Tab | Content |
|---|---|
| **Console** | the command line of the machine (`eve:>`), its answers, `select`, `upload`, `db …`; Ctrl+Up and Ctrl+Down walk the history |
| **Watch** | expressions with value and type, from the paused session; add and remove expressions |
| **Stderr** | what the run wrote to the error stream |
| **Stdout** | what the run wrote to the output stream |
| **Breaks** | every breakpoint of the project: on or off, file and line, the source line; select one to **Remove** it, or double-click (or Enter, or **Go to**) to open the file at that line |

**Breakpoints.** A click on the gutter (or F9) puts a red dot on a line and adds it to **Breaks**; the same again removes it. A paused line has a yellow arrow and background.

**Machines** (*design for later: not in this version, cut 2026-10-16; **replaced by D-195 (2026-10-18)**: code is local, a remote machine is deployed to and operated, nothing is run by hand on it; the text below and its drawings are kept until the Machines view is drawn, TD-39*). The top bar shows `F1 local`, `F2 prod`, `F3 test`; the selected one is green. The status line says `Ready: connection: local` or `Ready: connection: prod` (the same words as the REPL, D-171). **F1** is the local machine, **F2** a remote machine, **F3** another one; **Ctrl+Left** and **Ctrl+Right** go through all of them. Run and debug act on the selected machine; on a remote one **only a program that was uploaded can run** (D-171), and Tab completes only stored procedures and code on the server.

**Dialogs.**

- **Select project** (`p`): the projects the user has opened, from the user cache (§5); filter, Open, New, Browse, Forget.
- **Connect** (F2 the first time, or `c`): the user name in clear and the password as stars, never kept; not asked when the `eve.env` of the project has an entry for the machine (D-172).
- **Upload** (`u`): lists what would be sent (changed files only: the server side and the modules it imports), with Send, Dry run and Cancel.
- **Structure** (§6).

**Rules.** Keyboard first, the mouse where the terminal sends it; a destructive action asks first and names the machine; colors and box drawing degrade on a poor terminal.

## 4. Databases in tabs

1. **Select a database file** in the tree: a **table list** tab opens (table or view, columns, rows). Enter on a table opens its **data** in a new tab; `S` opens its **structure** dialog; `N` makes a new table.
2. **The data tab** is a grid read page by page (PgUp, PgDn, Home, End), with a filter (`/`) and a sort (`s`). It is for browsing; the structure is not shown in it.
3. A database file is opened by the machine that owns it: the local machine for a local file, the remote one for a file on the server. The calls are the `db.*` methods (D-165), with the methods that the table list, the paging and the structure need added to the API (Q-053 c).

## 5. The user cache and where things live

`evetx` is a module of the split (D-163): **`evetx` imports `evecm` only**, like `eveux`, and the package libvaxis. The build refuses other imports. libvaxis is already a Zig library: there is no binding, no C and no `@cImport`; it is a dependency of this module alone, so a build without `evetx` does not fetch it.

- It reaches a machine only through the JSON-RPC client of `code/evecm/wire`; one task per machine (`std.Io`), so a slow machine never freezes the screen.
- The list of projects and machines, the history of commands and the upload manifest are in the **user cache** `eve.db` (SQLite, `<user data folder>/eve/meta/eve.db`), reached through the `Meta` interface of `evecm`, implemented by `evedb`, wired by `cmd` (Q-052 b). It holds no password and no token.
- Started by **`eve -tx`** (D-172); `eve tx` stays a synonym, and `./run.sh evetx` is the shortcut. `eve -ux` starts eveux, the native workbench (D-193; it was the web UI, now `eve ux start`). A direct command, not a serving part (D-164).
- The line editor of `code/evecm/term` stays for the REPL; `evetx` takes the terminal (raw mode, alternate screen) only while it runs.

```
code/evetx/
├── README.md
├── design/             the SVG drawings and gen_svg.py
└── src/
    ├── root.zig        the module entry
    ├── model.zig       the state: tree, tabs, buffers, breakpoints, machines; pure data
    ├── update.zig      event + model → new model + requests; pure
    ├── view.zig        model → cells (libvaxis widgets)
    ├── editor.zig      the text buffer: lines, cursor, selection, undo; pure
    ├── client.zig      one task per machine: calls, timers, replies as events
    └── dialogs.zig     project, connect, upload, structure
```

- **Elm-style loop.** Key, mouse, resize and machine replies are events in one queue; `update` is a pure function; `view` only draws.
- **No automated tests** (D-178): the author tests the screen by hand. The code keeps the model and update free of the terminal, because that is also the clearest way to write it, not for tests.
- **Zig is taught here:** every function, test and type gets its `// Zig tip:` block (`CLAUDE.md`).

## 6. The structure dialog

A **grid** with a header row and **bordered cells** ([design-structure.svg](design/design-structure.svg)): one **row per field**, one **column per attribute**: number, Name, Type, Not null, Key, Default. It is generated from the columns of the table.

- Arrows move from cell to cell; Enter edits the cell; Space switches a box (Not null).
- **Type** is chosen from a list: the **button in the cell** opens a drop-down of the types (↑ ↓ and Enter choose). The list is the types of the engine of the file, SQLite or DuckDB (Q-054 e).
- **Default** of a date or time field has a **calendar button** ([design-calendar.svg](design/design-calendar.svg)): a month, a day, and a time for TIMESTAMP and TIME; **Today** and **Now** give the expressions of the engine, a chosen day gives a fixed value (Q-054 f).
- When there are more fields than rows, **Next page** and **Previous page** show the others; the header says `Fields 1–6 of 9 · page 1 of 2`.
- **Add field** and **Remove field** change the list; **Apply** sends the changes, **Cancel** drops them. A line says `1 change pending`, and **S** shows the SQL that Apply will run. SQLite changes some things only by rebuilding the table (a new type for a column), DuckDB allows more; the dialog says what Apply will do (Q-053 d).

## 7. What the machine must give (Q-053 b, c)

| Need | Existing | To add |
|---|---|---|
| run, stop, suspend, resume, inspect, eval | `vm.run`, `vm.stop`, `vm.suspend`, `vm.resume`, `vm.inspect`, `vm.eval` (D-165) | the output of a run as two streams (stdout, stderr) |
| breakpoints, step | F-TLS-04 (open): `halt` breakpoints | set and clear a breakpoint by file and line; step into, step out; the paused place; eval in the paused frame |
| list the programs on a machine | none | `vm.programs` (D-172 point 7) |
| tables, rows, structure | `db.query`, `db.execute`, `db.stat`, `db.proc.list` | list tables and views with counts; a page of rows; describe a table; change a table |

## 8. Work plan (level 6, version 0.0.6)

Each step ends with the usual checks: the ReleaseSafe build, `runtest.py all`, `bmark.py --check`, `zig build test`. Dependencies on B1 to B4: [design-packages.md](../../design/design-packages.md) §10, step B6.

| Step | Work | Done when |
|---|---|---|
| **T0 Spike** | libvaxis as a dependency; a tree, a text area, tabs, a dialog; keys, mouse and resize; Windows Terminal and Linux | builds with Zig 0.16 on both; the decision on Q-053 a is written |
| **T1 Skeleton** | module `evetx`, the option `-tx`, the shortcut in `run.sh`, the arrow checked by the build; the frame with top bar, sidebar, tabs, bottom panel, status | `eve -tx` opens and closes cleanly; the terminal is restored after a crash and Ctrl-C |
| **T2 Model and editor buffer** | events, model, update, the text buffer with undo; tests with no terminal | scripted key sequences give the expected model and text |
| **T3 Tree and editor** | the tree of the project, tabs, open a file at a click, edit, save and Save As, syntax colors; the title and the main menu, the find and replace bar, the status bar, the help dialog | a project is browsed, a file edited, found, replaced and saved; the menu and the help open by key and by click |
| **T3b File card** | text files open as source, any other file opens a file card (D-178); no preview | an image, an SVG and a video open a card |
| **T4 Run and the bottom panel** | Run on the local machine, the Console with the design of evevm, Stdout, Stderr | a program runs from the screen and its output shows in the right tab |
| **T5 Machines, project, upload** (*moved out of 0.0.6 on 2026-10-16: it waits for a lasting machine connection and login*) | F1 to F3, the status line, the connect dialog, the user cache and the select project dialog, upload, run on a remote machine (needs B3 and the `Meta` interface) | two local machines on two loopback ports; an upload; a run of an uploaded program; a program not uploaded is refused |
| **T6 Debugger** | breakpoints, Breaks tab, step into, step out, continue, stop, Watch, the paused line (needs the machine debugger, F-TLS-04, and B2) | a program is paused at a breakpoint, stepped, watched and resumed to its end |
| **T7 Databases** | table list, data tab, the structure grid with the type list and the calendar (needs the `db.*` additions) | a table of a local SQLite file is listed, browsed in a tab, and a column is renamed in the grid |
| **T8 Polish and documents** | filters, small windows, no-color mode, key help; `manual/usage.md`; the tutorial page; `feature_map.md` | a session script passes; `mdlinks.py check manual` clean |

If level 6 is too full, **T6 and T7 are the first to move** to the next version; the author decides (Q-053 a).

## 9. Open points

Q-053 in `design/questions.md`: the size of the scope, the debugger of the machine, the methods to add, the structure changes, step over, what the editor must do, where a run goes when the file is local. Q-050 to Q-052 stay open for the registry, the layout and the user cache.

## 10. Risks

| Risk | Answer |
|---|---|
| libvaxis does not build with Zig 0.16, or on Windows | the spike T0 first; a pinned commit or a patch; the module is the only user |
| **An IDE is a large scope for one level** | the steps are ordered so that each is usable alone; T6 and T7 can move; the editor stays plain (Q-053 f) |
| The debugger of the machine does not exist yet | T6 waits for F-TLS-04; the screen can be built with a fake machine first |
| Two UIs (`evetx`, `eveux`) with the same features | they share only the machine API and the rules of D-171; no code is shared (Eve and JavaScript on one side, Zig on the other), so their screens may differ |
| A breakpoint on a line of a file that differs from the copy on the server | the upload manifest (hashes) tells; a run on a remote machine warns when the local file is changed and not uploaded |
| Table structure changes that SQLite cannot do in place | the dialog says what Apply will do; a rebuild asks first |
| **Keys the terminal cannot tell:** Ctrl+Enter is often the same as Enter, Ctrl+/ the same as Ctrl+_, Ctrl+Shift+S the same as Ctrl+S | libvaxis uses the enhanced keyboard protocol where the terminal has it; T0 tests Windows Terminal, the Windows console and Linux; F10 (menu) and F12 (help) are the fallback (Q-054 a) |
| No tests | the author tests by hand (D-178); a mistake shows on the screen first |

## 11. Implementation (D-178)

Started 2026-10-13, as a **separate Zig program** in this folder until the split of design-packages.md (phase A) exists: `build.zig` and `build.zig.zon` here, built from `code/evetx/` with `zig build -p ../..` into `bin/evetx.exe` (like `evedb`). Run it as `evetx [project-folder]` (the default is the current folder). When the root `build.zig` is made (step A7) the folder becomes the module `evetx`, the option `eve -tx` starts it, and the module imports `evecm` only. libvaxis is pinned in `build.zig.zon` to the commit `5b0c724` (2026-10-07), the last one for Zig 0.16 (its `main` branch has moved to Zig 0.17). **There are no automated tests** (D-178): the author tests the screen by hand.

**Source** (`src/`): `main.zig` (the event loop), `app.zig` (state, keys, mouse, run, console, searches, menu), `view.zig` (all the drawing; it records the clickable places), `theme.zig` (the colors of the drawings and the three built-in themes), `options.zig` (the options, the custom themes and the theme files; its own test: `zig test src/options.zig`), `dbf.zig` (DBF tables; `zig test src/dbf.zig`). The files that have no screen library are shared with eveux and live in `code/evecm/src/ide/` (module `ide`, tests in the root `zig build test`): `text.zig` (the text buffer of the editor), `project.zig` (the tree of files), `scan.zig` (the colors of a line), `link.zig` (the machine of evetx: `eve --stdio` and its messages), `cache.zig` (the user cache folder), `grid.zig`, `regex.zig`, `sqlstruct.zig` (the SQL of the structure dialog of a SQLite table), `keywords.zig` (**generated** from `spec/lexical/keywords.json` by `gen_keywords.py`; run it again when the keywords change).


### Features now (2026-10-16)

- **Project.** The tree of the project (folders, files, icons, connection lines, scroll bars; the server-side folders are marked); File > Open project (the list of known projects) and Open Folder (a folder browser); the session (open files, cursors, layout, breakpoints) comes back at the next start; Ctrl+click marks files and a drag moves them to a folder; a click on a folder makes it the working folder of the console and lists it in the Main Panel.
- **Editor.** Tabs; Eve and SQL colors; selection by mouse and keys, copy, cut, paste (the system clipboard with OSC 52, bracketed paste); Undo and Redo (Ctrl+U, Ctrl+Y); moves by word; Wrap text and Show hidden; tabs kept as tabs; line numbers; Find, Replace, GoTo, Find File; Auto save.
- **Files.** File > New… with a wizard by extension (`.eve`, `.sql`, `.dbf`, `.db`); Save, Save As; **Info** (Info… in the popup menu of a tab; File > Rename… and Rename… of a tab open it with the name ready to edit): a small dialog titled `File: <name>` (or `Table:`, `View:`, `Folder:`), a rule, then the facts: name, kind, folder, size, date of the last change, lines and line ends, records. **Rename** turns the name into a field in its place (a file, a folder, a DBF table, or a table of a SQLite file with `alter table … rename to …`); **Move** opens the folder selector and moves the file to the folder chosen in the project (the folder is a fact of its own, not part of the name); Delete…; a file card for binary files (D-178).
- **Tabs.** The tab row of the Main Panel has `<` at the left and `>` at the right (where the Info button was): when the tabs do not fit, they shift the row one tab left or right; the row follows the active tab when it changes.
- **Run and debug.** Run, Halt, Next, Step, Exit and Trace on the toolbar, driving `eve debug <file>`; breakpoints in the gutter and the Breaks tab (on and off, trash); the Watch tab; the Console (`eve:>`, `cd`, history, Tab completion, `!<command>` and `shell <command>` through the machine, `exit` closes evetx), Stdout, Stderr, and the SQL panel; a run command waits for the run delay.
- **Data.** The grid of a table: `#` (the record number, `*` for a deleted one), the names of the fields (no types), `│` between the columns, a discreet background on every other row; a column is as wide as its data needs, and when the fields do not fit the ones wider than 12 cells are trimmed in proportion (never under 12), then the grid scrolls sideways. DBF tables (edit a cell, append and delete rows, the structure dialog, New DBF); SQLite files in the tree (tables and views, a read-only grid of up to 5000 rows, the structure dialog, Create table, Drop table, rename in Properties).
- **Screen.** The menu bar FILE, EDIT, SEARCH, RUN, WINDOW and HELP; one folder selector for Open Folder, Move and the theme files (a rule under the title, a scroll bar when the folders do not fit); the pop-up of a failed operation; the Tree, Main and Tools panels (hide, maximize); the layout lock on the toolbar (open: the borders can be dragged and the arrow keys resize; locked: the layout does not move); the help windows (Shortcuts, Manual, Tutorial); About.
- **Options** (HELP > Options, Ctrl+,). *Theme*: three built-in themes, **Dark Theme**, **Gray Theme** and **Light Theme**, which cannot be changed, renamed or removed; a change of a color of a built-in theme makes a **custom theme** named after it (`Dark Custom1`, `Gray Custom1`, `Light Custom2`, …); a custom theme can be **renamed** and **removed**; any theme can be **exported** to a JSON file and a theme file can be **imported** (a name that is taken gets a number). Export and Import open the folder selector with the theme files (`.json`) under the folders and a file name field (the name of the theme for Export, the file chosen for Import); a file that is not a theme opens the pop-up **Operation failed** with the reason, and its OK goes back to Options. *Colors*: the 28 colors one by one with red, green and blue sliders and a palette. *Timers*: Auto save, Run delay, Trace delay. The options are in the user cache (`evetx-options.txt`), the custom themes in `evetx-themes.json`, exported themes go by default to `<user data folder>/eve/themes/`.
- **Theme files.** One JSON object: `{"name": "Dark Navy", "base": "dark", "colors": {"panel": "#161c24", …}}` with the 28 slots of `theme.Slot` (a missing slot takes the color of the built-in theme of the same `base`: `dark`, `gray` or `light`). The folder [themes/](themes/) holds the 13 themes of the earlier versions (Dark Navy, Dark Forest, Dark Cave, Dark Sage, Dark Okaida, Dark Twilight, Light Desert, Light Town, Light Pastel, Light Sage, Light Retro, Turbo Pascal, Shades of Gray), ready to import.

**Removed on 2026-10-16** (to progress faster; [status-level6.md](../../backlog/evetx-status.md)): the remote machines (the registration form, the machine name and its dropdown on the toolbar, the MACHINE menu, Alt+1 to Alt+3; `evetx-machines.txt` is no longer read); Upload (FILE menu and the popup menu of a tab); the Markdown preview (`md.zig`, the eye button, WINDOW > Preview; eveux renders Markdown, D-178); the Border delay timer (a locked layout does not move: open the lock to drag a border); ten of the thirteen themes (now files of `themes/`).

**Not yet:** Query (F7); breakpoints in aspect and module files (only the main script is debugged); remote machines and upload (T5, after a lasting machine connection and login, Q-048); the database tabs through the `db.*` methods of the machine (today every action starts `eve db sql`). **Known limits:** a column is one character cell, so wide characters (the emoji icons) can be drawn out of place; Ctrl+Enter, Ctrl+/ and Ctrl+Shift+S need a terminal with the enhanced keyboard protocol (F10 and F12 work everywhere, Q-054 a); Windows Terminal ignores the pointer shape (OSC 22).

### The machine of evetx (2026-10-16)

evetx talks to **one machine of its own**: the first time the console needs it, evetx starts `eve --stdio` as its child (`src/link.zig`) and speaks JSON-RPC with it on the pipes, one message per line; a worker thread does the waiting, so the screen never stops. The machine ends when evetx ends (the end of its input), and is started again if it ended. The same messages work over SSH (`ssh host eve --stdio`) and, later, from eveux through a WebSocket (`spec/library/machine.md#lasting-doors`).

- **The console stays in eve.** The `$` shell mode is gone. `!<command>` or `shell <command>` runs a command of the system (the machine's `vm.shell`), in the working folder of the console; its output comes line by line while it runs, and the prompt stays `eve:>`. Without a machine (eve not in the PATH) evetx runs the command in its own shell. `exit` and `quit` close evetx: back to the command shell that started it.
- **The commands of a session** (`load`, `parse`, `ast`, `inspect`, `errors`, `status`, `report`, `help`, `outdir`, `capture`, `log`) go to `vm.eval` in the default session of the machine, which keeps the loaded script between them; the output streams into the Console and the Stdout tab, the log of the machine into the Stderr tab.
- **Runs keep their process.** `run <file>`, Run (F5), Check (F6) and Debug still start `eve` as a process in the folder of the script, so a script finds its own `eve.cfg` and files, and Halt ends it. They move to the machine when its sessions have a working folder for the files a script opens, and the debugger becomes methods (`dbg.*`).
- **Halt** cancels a request of the machine too (`vm.cancel`), and the toolbar shows it as running while it is not answered.

### Log of the work

Each paragraph below describes the screen on its date; what was removed later is listed above.

**Layout and input rework (2026-10-14):** a classic menu bar of upper case names (FILE, EDIT, SEARCH, RUN, MACHINE, and HELP at the right side: Shortcuts, Manual, Tutorial, About, Options). F10 or Alt plus the first letter opens a menu; Left and Right change menu, Up and Down and Enter choose, a letter jumps to another menu, the mouse hovers and clicks. The hot letters are amber; they are underlined when Alt is pressed or a menu is open (on Windows the Alt key alone is a key event). The SEARCH menu holds Find Text (Ctrl+F), Find File (Ctrl+P), Replace (Ctrl+H, Tab between the fields), GoTo (Ctrl+G) and Query (Ctrl+L, not yet); they are small dialogs at the top right and replace the search bar. Every panel has a border (blue where the keys go): the files tree, the editor with its tabs, the bottom panel. The tree has a folder and a file picture and connection lines (`├─ └─ │`). A middle click on a tab closes it.

**Dialogs and the project cache (2026-10-14):** every dialog has a × button at the right of its title and buttons at the bottom (the one that Enter does is green). File > Open project lists the known projects (Open, Import folder…, Forget, Cancel; Enter, Del, I); File > Open Folder (Ctrl+Shift+O) is a folder browser with the path field, the sub folders and Open as project, which adds the folder to the cache and opens it. The cache is for now the text file `evetx-projects.txt` (one absolute path per line, last used first) in `<user data folder>/eve/meta/` (`LOCALAPPDATA` on Windows); it moves into `eve.db` with the `Meta` interface. Alt+Left and Alt+Right change the active panel (Alt+Tab belongs to the operating system); the Run buttons belong to the Tools Panel and go when it is hidden.

**Editor and status bar (2026-10-14):** a click puts the cursor at the pointer, a drag selects (Shift+click extends), Shift with the arrows, Home, End, PgUp and PgDn selects, Ctrl+A selects all, Ctrl+C and Ctrl+X copy (the text goes to the clipboard of the system with OSC 52 too), Ctrl+V pastes; a paste made by the terminal arrives between two markers (bracketed paste) and is inserted as one piece. The status bar has the state, a fixed panel `Ln 9999, Col 999` and, aligned to the right, quick information about the current window (file, kind, lines, line ends, modified) or the project. The active window title is drawn in inverted colors. `.db`, `.duckdb`, `.sqlite` files have a disk icon in the tree. The About dialog shows the version of the root `build.zig.zon`. The MACHINE menu lists only the machines that are connected.

**Word moves and run commands (2026-10-14):** Ctrl+Left and Ctrl+Right move by word, with Shift they select. Run (F5, the button, RUN > Run) and Check syntax (F6) do not start at once: the command (`run <file>`, `--check <file>`) is typed in the prompt of the Console, shown in the status bar with a countdown, and starts after three seconds; Enter starts it now, Esc cancels it, typing keeps the text and stops the countdown. Every command goes into the console history (Ctrl+Up). The debugger commands (step, continue, stop) wait for the machine debugger (T6).

**Wrap, thin scroll bars and breakpoints by click (2026-10-14):** Edit > Wrap cuts long lines at the right edge (the cursor keys still move by line). Without it the horizontal bar is one row of thin line (`─` track, `━` thumb) with `<` and `>` buttons that scroll ten columns; the vertical bar is a thin line too (`│`, `┃`). With wrap the horizontal bar goes and the vertical one gets `^` and `v` buttons that scroll half a page. A click on a line number or the space next to it sets a breakpoint, a click on the red circle removes it.

**Session and bar glyphs (2026-10-14):** evetx writes where the user is to `evetx-session.txt` in the cache folder (the project, panel sizes and visibility, wrap, the open files with the cursor and the first line shown, the open folders of the tree, the selected row, the breakpoints), when the program ends and when a file opens or closes. A start with no folder reopens the last project and puts everything back; a start with a folder restores the session only if it is the same project. The scroll bars use a light shade `░` for the track, a full block `█` for the thumb and the triangles `▲ ▼ ◄ ►` for the buttons; the glyphs are constants at the top of `scrollBars` in `view.zig`.

**Tree bars, scroll limit and hidden characters (2026-10-14):** the tree gets a vertical and a horizontal bar (with ▲ ▼ ◀ ▶) when its rows do not fit; the connection lines, the pictures and the names scroll together. The editor scrolls down only until three empty rows are left under the last line. Edit > Show hidden characters draws a middle dot for a space, `→` for a tab and `↵` (`␍↵` for Windows line ends) at the end of each line. Tabs are no longer replaced by spaces when a file is read: they are kept, shown up to the next tab stop of four cells, and written back unchanged.

**Layout by mouse (2026-10-14):** over a border between panels the pointer becomes a double arrow (OSC 22 `ew-resize` / `ns-resize`, for terminals that support it) and the border is painted amber. A press on it starts Layout modify; drag to resize; three seconds after the button is released the layout freezes by itself. The WINDOW menu has Layout modify (Ctrl+L) and Layout freeze (Ctrl+F, while in modify mode; elsewhere Ctrl+F is Find Text); in modify mode the plain arrow keys resize (Left and Right the Tree Panel, Up and Down the Tools Panel). Query moved to F7 because Ctrl+L is now the layout.

**Undo, tab menu, layout handle (2026-10-14):** Undo is Ctrl+U and Redo Ctrl+Y (snapshots of the text taken before a change; a run of typing or of erasing is one step; 100 steps). Layout freeze is Ctrl+Z; the layout items are a group of their own in the WINDOW menu, which also has Close All and Close Clean. A right click on a tab opens its popup menu (Save, Save As, Close this, Close right, Close left, Close clean; the closing ones keep the windows with unsaved changes). Windows Terminal ignores the escape code that changes the mouse pointer (OSC 22), so the toolbar above the Tools Panel has a double-arrow handle (⇕): drag it up or down.

**Options (2026-10-14):** the Options dialog (HELP > Options, Ctrl+,) has three tabs. *Theme*: Dark Navy, Dark Forest, Dark Cave, Dark Sage, Dark Okaida, Dark Twilight (SCL tutorial and the PrismJS themes), Light Desert, Light Town, Light Pastel, Light Sage (a colorful theme: sage greens, flower purple, sun and earth), Light Retro, Turbo Pascal (blue and yellow), Shades of Gray (the 16 grays 00,11,…,ff) and Custom, with a sample; a choice is applied at once and goes back on Cancel. *Colors*: the 28 colors (keyword, control word, interruption, operator word, type, and the four kinds of comment and title as in the tutorial) of a theme one by one, with a red/green/blue selector (click on a slider, or r, g, b and the arrows) and a palette; editing a color of a ready-made theme copies it to Custom. *Timers*: Auto Save (seconds, 0 = off; saves the files with changes) and Run Delay (seconds before a Run command typed in the console starts). The font cannot be changed: it belongs to the terminal. The options are for the tool and the user, not for a project; they are saved in the user cache (`evetx-options.txt`, for now a text file like the project list; they move into `eve.db`). The colors in `theme.zig` are variables, so a theme changes the whole screen in the next frame.

**Layout by the toolbar and Run in the script folder (2026-10-15):** the free space of the toolbar (after the Run buttons) and the ⇕ handle are part of the border between the Main Panel and the Tools Panel: under the pointer both the bottom border of the Main Panel and the top border of the Tools Panel are painted amber, and press and drag changes the layout. Run (F5) and Check (F6) first write `cd <folder of the script>` in the console and change its working folder, then `run <file>`; `eve` therefore loads the `eve.cfg` of that sub-project. `cd <folder>` also works by hand in the console (`cd` alone shows the folder).

**Toolbar, lock and border delay (2026-10-15):** the toolbar of the Tools Panel has Run, Debug, Step and Follow. While a program runs, Run becomes **■ Stop** (red) and ends the process; Run no longer blocks the screen (a worker thread runs `eve` and collects its output, `RunJob` in `app.zig`). Debug and Step wait for the debugger (T6). Follow keeps the console on the newest output. At the right end: the link to the machine (`↔ Local` green when connected, `← → off` red when not) and the lock (🔒 the layout is frozen, 🔓 the borders can be moved; a click toggles it, as Ctrl+L and Ctrl+F do). On a locked layout a border between panels is painted and can be dragged only after the pointer rested on it for the **Border delay** (Options > Timers, 5 s at first, 0 = at once); an unlocked layout reacts at once.

**Machines (2026-10-15):** the machines are a list in order of registration (the first, Local, is always there), kept in `evetx-machines.txt` of the user cache (`address<TAB>port`). On the toolbar, at the right: the gear (opens the registration form), the name of the machine in use with ▾ (a dropdown of the registered machines) and the lock; the gear and the name are green when the machine is connected and red when not (only Local is connected until step T5). MACHINE > Register… (Ctrl+K) opens the same form. The form has a table of the machines, a last row for a new one, the Address and Port fields, and the buttons **Save** (on when a new machine is present or the selected one is modified), **Select** (on when the selected machine is not the one in use; uses it and closes, saving nothing) and **Close** (closes, saving nothing). Upload… is in the FILE menu and in the popup menu of a tab, after Save As. A dialog is centered over the Main Panel when it fits in it with 10% to spare, and in the whole window when it does not. The ⇕ handle is gone: the lock does that work.

**Debugger (2026-10-15):** the toolbar buttons are Run / Halt, Next, Step, Exit, Trace and Follow, and they drive `eve debug <file>` (`code/evevm/src/debugger.zig`, `manual/usage.md`). Next, Step, Exit or Trace with no session starts one: the script stops before its first statement (the editor shows an arrow in the gutter and the line in the selection color). While stopped, Run goes on to the next breakpoint, Halt ends the program (`halt`), Next steps over, Step goes into a call, Exit leaves the subprogram, Trace goes on until the next breakpoint. The breakpoints of the gutter are sent at the first stop, and a breakpoint set or removed during the session is sent at once. The output of the program shows in the Console while it runs. Keys: F5 Run, Shift+F5 Halt, F8 Next, F11 Step, Shift+F11 Exit, Shift+F8 Trace. Not yet: the Watch tab (variables), and breakpoints in aspect or module files (only the main script is debugged).

**Debugger, second round (2026-10-15):** the toolbar is Run, Halt, Next, Step, Exit, Trace, all of the same width; Follow is gone. While a program runs, Run reads **● Running**, red and blinking, Halt is active (otherwise gray) and the other buttons wait. Run starts the debugger when the file has breakpoints (it stops at the first one), and runs normally otherwise. Trace with no session starts the debugger and traces at once (slowly: 400 ms a statement, the arrow in the gutter follows). The Watch tab shows the variables of the stop. Every list has a scroll bar with arrows (the logs of the Tools Panel and the Breaks tab joined the tree and the editor). The **SQL** tab of the Tools Panel runs the typed statement with `eve db sql` on `:memory:` or on the file chosen with `use <file.db>`, with SQL colors in the input and the history; `.sql` files open with SQL colors in the editor (a `/* */` comment is colored on its own line only).

**Third round (2026-10-15):** Options > Timers is a grid (Timer, Value, Change, Description side by side) with a new **Trace delay** (50 ms steps, 400 ms at first, sent to the debugger as `delay`). In the Breaks tab each row has a check box (`[x]` on, `[ ]` off: the debugger skips it and the gutter shows a gray circle instead of the red one; Space switches it) and a trash icon; the trash, the Del key and the tool Clear on the Breaks tab ask first, in the **confirmation dialog** (`App.askConfirm(what, arg, message...)`, Yes/No, keys Y and N, reusable: a new question is a value of `Confirm` and a branch of `confirmYes`). The tool **Clear** (`⌫ Clear` at the right of the tab strip, RUN > Clear panel) empties the panel that is shown: Console, SQL, Stdout, Stderr, Watch. In the Console, `exit` stops eve and the prompt becomes `$`: the lines go to the shell that started evetx (`$SHELL`, else `cmd.exe`) in the folder of the console; `eve` brings the prompt `eve:>` back, `eve <arguments>` runs eve once; `quit` closes evetx.

**DBF tables (2026-10-15, replaced by D-184 on 2026-10-17):** `code/evetx/src/dbf.zig` reads the old DBF format of dBASE III and FoxPro 2.x (version byte 0x03: a 32-byte header, 32 bytes for each field, records of text with a deletion mark, the byte 0x1A at the end; types C, N, F, D, L, M) and has its own tests (`zig test src/dbf.zig` from `code/evetx/`). By D-184 DBF is **only a file decoder for legacy ingestion**: it is never a query engine or a storage structure. Queries run in SQLite `:memory:` with tuned PRAGMAs, the computational pipelines use native columnar (SoA) tables, and a DBF file enters a database through EDIT > Import… (not built yet). **Done (2026-10-17):** `dbf.zig` moved to `drivers/duckdb/src/` as a stream decoder and an encoder; evetx has no DBF code any more: a `.dbf` file in the tree shows a file card that says to import it; the grid shows only the tables of SQLite, held by `src/grid.zig` (columns of text, one buffer and one offset array for each); the structure dialog of DBF, Save, Compact, Drop, Append and Delete of DBF, and the SQL copy of a DBF table are gone. **EDIT > Import…** (enabled when a database is selected) asks for a CSV, TXT, JSON or DBF file and runs `db import`; the table is named after the file. Tests of DBF files are in Python: `python script/dbf_check.py`. The spec is `spec/library/data-engines.md`.

**Files, folders and data (2026-10-15):** every panel has a discrete line under its tab strip (the tree, under its title bar). **File > New…** (Ctrl+N) is the one way to make a file: it asks for the name, in the folder that is selected in the tree (the folder itself, or the folder of the selected file), and starts the wizard of the type read from the extension: `.dbf` the structure dialog (fields), `.eve` a wizard (primary aspect, aspect or module, valid templates), `.sql` a wizard (empty, create table, select, insert), `.db`/`.sqlite` a SQLite database, anything else an empty file (`.md` and `.json` start with one line). Save As of an untitled file starts in that folder too. **Clicking a folder is a `cd`:** it becomes the working folder of the console, and the line `cd <folder>` is written there, at the `eve:>` prompt and at the shell `$` prompt alike; Run, Check and Debug at the `$` prompt bring eve back first. **Drag and drop in the tree:** Ctrl+click marks several files; dragging a file (or the marked ones) onto a folder asks `Move … to <folder>?` and moves them (a name that exists in the folder is not overwritten); open tabs and breakpoints follow the moved files. A plain click opens on release, so a drag does not open or fold what it picks up. The drop folder is painted green while you drag. **DATA menu** (for a DBF table): Append row (Ins), Append rows… (a number), Edit cell (Enter; Enter saves it, Esc leaves), Delete / recall row (Del). Every change is written to the file at once. The toolbar no longer has the gear: the drop-down of the machine name ends with **Register…**.

**`shell` (2026-10-15):** at the `eve:>` prompt of the Console, `shell <command>` runs one line in the shell that started evetx (in the working folder of the console), shows its output, and leaves the console at the eve prompt; `shell` alone is the same as `exit` (the `$` prompt).

**Tab in the Console (2026-10-15):** Tab completes the file or folder name that starts with the letters before the cursor (in the working folder, or in the folder of a path typed with `/`): one match is completed (a folder gets a `/`), several are completed as far as they agree and listed in the console. It works at the `eve:>` prompt and at the `$` prompt.

**View, Clear and DATA (2026-10-15):** the three buttons at the right of a panel title are equally spaced: `▤ + ×` on the Main Panel and `↺ + ×` on the Tools Panel (↺ is the Clear tool; `▤` is **View**, active on `.md` files, gray on other files). View shows the Markdown file **rendered** and runs it full screen: the Tree Panel stays, the Tools Panel steps aside, and the Main Panel goes down to the bottom bar. The renderer is `code/evetx/src/md.zig` (its own test: `zig test src/md.zig`): headings (underlined), wrapped paragraphs, bullet and numbered lists, block quotes, fenced code, rules and tables, and in the text **bold**, *italic*, `code`, links and images. Keys on the page: arrows, Page Up and Down, Space, Home, End scroll; Esc or V (or the View button again) goes back to the editor. The DATA menu is now the second menu (after FILE) and starts with **Structure…**, which opens the fields dialog of the DBF table that is open.

**Menus, bars and wrapping (2026-10-15):** the View button of the Main Panel is the eye 👁. The DATA menu is merged into EDIT, as a separate group at its end (Structure…, Append row, Append rows…, Edit cell, Delete / recall row); WINDOW has **Preview** (`[x]` while the page is shown). The scroll bar of the tree could not be dragged far: the view was pulled back to the selected row at every frame, and the thumb did not follow the pointer to the ends. Now the tree shows the selected row only after a key, a click or a search, and the pointer places the middle of the thumb (the same rule for the editor bars), so the thumb and the first and last rows are reached. The Console, Stdout, Stderr, Watch and SQL panels wrap long lines to the width of the panel (the prompt only on the first row, the other rows under the text); the scroll bar counts lines.

**Shortcuts, SQLite in the tree, SQL on the selection (2026-10-15):** **Ctrl+Space** appends a new row at the end of a DBF table, or a new empty line at the end of a text file (the cursor goes there). What the libraries log no longer lands on the screen: `std_options.logFn` keeps it, and the message bar shows it and the Stderr tab records it; the Windows console key that the keyboard library does not know (Ctrl+Space as code 0x40) is turned into Ctrl+Space, and a Ctrl or Alt shortcut that nothing uses says `unknown shortcut: Ctrl+K` in the bar and in Stderr. **A SQLite file** (`.db`, `.sqlite`, `.sqlite3`) in the tree opens like a folder (💾 / 💽) and lists its tables and views (▦), read with `eve db sql`; a click on a table opens its rows (up to 5000) in the Main Panel as a read-only grid (the tab is `file.db#table`); the scroll bars follow the new rows. **EDIT > Structure…** (or `SQL:> alter table <name>` while a SQLite file is selected) opens the **structure dialog of a SQLite table**: a bordered grid of Name, Type (a list), Not null, Key and Default; Apply asks first and rebuilds the table (new table, rows copied under the old names, old table dropped, new one renamed; indexes and triggers are not kept). **SQL follows the selection:** the SQL panel works on the table that is open in the Main Panel, else on the row selected in the tree: a SQLite file or one of its tables goes to that file; a DBF table is copied into a memory database for the statement, so `select * from tbl where code like 'A%'` works on it (read only). The target is written on the rule of the panel; `use <file.db>` overrides it, `use auto` gives the selection back. The VM command `eve db sql` has new options for this: `-t` (rows as tab separated text), `--last` (only the result of the last statement) and `-f <script>` (statements from a file).

**Bars, preview and Tab (2026-10-15):** the eye is drawn with the emoji selector (U+FE0F) so it takes its two cells whole. A short scroll bar (3 to 5 rows) now keeps both arrows at its ends. The thumb of the rendered page and of a table grid can be dragged (the same rule as the tree: the pointer holds the middle of the thumb). Preview no longer un-maximizes the Main Panel: with the tree hidden, the page opens in the same view. **`alter table`** needs no name when a table is open or selected (it is that table); with a name, a database that is selected owns it, else it is a DBF file looked for in the folder of the console, the folder of the open table or of the selection, and the project folder. **Tab in the SQL prompt** puts the first table whose name starts with the letters before the cursor (the first table when none are typed), and each next Tab the next one, going round: the tables of the selected database, or the DBF tables of the current folder.

**Sample tables, Create table, Drop table (2026-10-15):** `test/project` now has tables to try the structure dialog on: `data/customers.dbf` (8 records, one deleted; numeric, character, date and logical fields), `data/orders.dbf` (12 records), `data/empty.dbf` (one field, no records), `db/shop.db` (SQLite: `customers`, `orders`, `items` and the view `big_orders`) and `db/empty.db` (no table). They are made by `python script/mk_project_fixtures.py`, which makes them again if you spoil them. The EDIT menu has **Edit structure…**, **Create table…** and **Drop table…**; the SQL panel understands `create table [name]`, `drop table [name]` and `alter table [name]` (a full `create table t (a int)` with a column list goes to the database as it is). **Create table** follows the tree: with a database (or one of its tables) selected it makes a SQLite table, with its structure dialog for the columns (it starts with `id INTEGER` as the key); with a folder selected it makes a DBF table in that folder, and the DBF structure dialog opens after the run delay. **Drop table** acts on the table that is open or selected (or the one named, in the selected database or in the current folder) and always asks first; for a DBF table the file is deleted, for a SQLite table `drop table` (or `drop view`) is run and the tree is read again.

**Folder list, icons, shadow (2026-10-15):** a click on a folder of the tree shows its content in the Main Panel, as a list: icon, name, description (Eve program, DBF table, SQLite database, Folder, …), creation date (UTC) and size in KB, with `..` to go up. There is one such tab, and it follows the clicks. Arrows, Page Up and Down, Home and End move; Enter or a second click opens a file or goes into a folder; Backspace goes up. **The file that is selected in the list drives the buttons:** Preview (◉) is active for a Markdown file and Run (with Next, Step, Exit and Trace) for an Eve file; pressing one opens the file first. The tabs have the same icons as the tree (📂 folder, 💾 database or DBF table, ▦ table of a database, 📜 Eve file, 📄 other), and a table of a database is named `shop.orders` on its tab. The Preview button is now the narrow sign ◉: a wide emoji on the border row (the eye) was drawn in half and moved the right border when the window was resized. In a **light theme** dialogs and popup menus cast a shadow (a darker background on the cells at their right and below, the text kept) so they look raised. The debug and info lines that libraries log are dropped; only warnings and errors reach the message bar.

**Rename and Delete (2026-10-15):** FILE now groups the file commands between rules: Save, Save As…, **Rename…**, **Delete…**, Upload…; the popup menu of a tab has Rename… before Upload… and a rule above the Close group. Rename and Delete work on the file you point at: the row selected in the tree when the tree has the keyboard, else the file of the tab (or the file selected in a folder list). Rename opens a field with the path of the file in the project: change the name, or the folder (it must exist), and press Enter; a name that exists is never overwritten; open tabs, breakpoints and the tree follow. Delete asks first (the Yes/No dialog) and deletes a file, not a folder. In EDIT, *Wrap* is now **Wrap text** and *Show hidden characters* is **Show hidden**.
