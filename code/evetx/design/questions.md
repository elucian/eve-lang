# Questions of the evetx design

The questions of `design/decision/level6.md` about evetx, the terminal IDE, moved here on 2026-10-20 at the author's request ("move these questions into the evetx project for design, some of them are already implemented"). The author answers them when working on evetx. The design is `README.md` of this folder's parent and the drawings in this folder; the settled decisions D-173 to D-178 are in `design/decision/archive/level6.md`. `python script/plan.py show Q-053` finds an entry here.

Notes of the author kept from the review list of level 6:

- Q-050 evetx, a terminal UI over libvaxis for the projects of many machines [open]
- Q-052 Proposals after D-172: the project layout (`server/`), the user cache `eve.db`, the options `-tx` and `-ux` [open]
- Q-053 The size and the needs of the evetx IDE [open]
- Q-054 The details of D-174: keys, the gear, search scope, types, the calendar, the console [open]

## Q-050 evetx, a terminal UI over libvaxis for the projects of many machines (2026-10-13, open)

Author request (2026-10-13): "create evetx a full TUI using zig binding to existing library libvaxis. This will enable project management and schedule management for one or more remote eve machines … a full-screen TUI using zig binding to existing library libvaxis. This will enable project management and schedule management for one or more remote eve machines … prepare the plan implementation for level6". Changed by the author the same day: "Move schedule to eveux. Eve ux manage runs, evetx can run for debug purpose and test." Design: `code/evetx/README.md`; plan: `design/design-packages.md` revision 6, step B6. Proposals, for the author:

- (1) libvaxis is already a Zig library, so there is no binding to write: it is a package dependency of the module `evetx` only;

- (2) `evetx` imports `evecm` only, like `eveux`, and is the part word `eve tx` with the shortcut `./run.sh evetx` (proposed as D-170);

- (3) settled: schedules and the management of runs (job browser, run history, logs) are `eveux` work (F-TLS-21), so the schedule methods of the machine API are designed with `eveux`, not in step B2; `evetx` manages machines and projects and has a Run view for debug and test;

- (4) the registry of machines, the credential store (keyring) and the login flow go down to `code/evecm/wire`, so `eve -rem`, `eveux` and `evetx` share them (moves part of D-155);

- (5) project deploy: settled by D-171, the upload of `web/`, `proc/` and `sql/` after `--connect` (details in Q-051);

- (6) libvaxis with Zig 0.16 and Windows is unchecked: the spike T0 decides, with a pinned commit, a patch or a thin terminal layer as fallbacks.

**answer** We already have a design with Zig 0.17, we maintain the evetx document.

## Q-052 Proposals after D-172: the project layout (`server/`), the user cache `eve.db`, the options `-tx` and `-ux` (2026-10-13)

Proposals for the author.

- **(a) Layout: one project, a `server/` folder.** The author asked for an opinion between `src/server` with `src/local`, and `<project>/local/src` with `<project>/server/src`. Proposal: **neither tree.**
  - (1) `proc/`, `sql/` and `web/` stay at the root of the project: they are server-side by their nature (D-166), and `project init` makes them already (D-160).
  - (2) Add one folder **`server/`** for the Eve programs that run on a server: the scheduled drivers and the `service` script.
  - (3) Everything else (`<name>.eve` at the root, `asp/`, `src/`, `test/`, `doc/`) stays local.
  - (4) **The upload sends `web/`, `proc/`, `sql/`, `server/` and every module they import or link**, found by the compiler (`evecp` link), not by folder: a `proc/` module that imports `lib/text.eve` needs that file on the server, and a rule by folder would miss it or ship the whole `lib/`. Why not two trees: `lib/` and `eve.cfg` are shared by both sides, so two trees duplicate them or break the imports; `src/` is already "other sources" in D-160, and moving the three server folders under it would break `sql/schema.sql` of the tests. A real client/server **application** (two programs, two teams) stays what design-service.md §1 says: two projects, one client and one server, in one repository.

- **(b) The user cache `eve.db`.** The author: Eve keeps the projects in a cache, in a `meta` folder, as a SQLite table; this seems to need SQLite in evevm after all. Findings: SQLite is **already embedded** in `eve` (the core database, D-156; D-166); DuckDB is the part loaded on demand. What is missing is not SQLite but a **store of the user**, not of a project: proposal `<user data folder>/eve/meta/eve.db` (Windows `%LOCALAPPDATA%\eve\meta\eve.db`, Linux `$XDG_DATA_HOME/eve/meta/eve.db`), different from the `meta/` folder of a project (which is versioned). It holds the tables `project` (name, path, layout version, last opened, last machine), `machine` (name, address, user, last connection; **no password and no token**), `history` (commands per project and machine, for Ctrl+Up), `manifest` (file hashes of the last upload per project and machine, so an upload sends changed files only and the Projects view shows in sync, changed, new). It is a **cache**: delete it and the projects return as they are opened. The arrows of design-packages.md §3 hold if evecm gets a small interface `Meta` (like `Data`, §8), evedb implements it with the SQLite it already has, and `cmd` connects it; evetx and evevm never import evedb. It is **level 6** (step B3, before the Machines and Projects views of evetx).

- **(c) `-tx` and `-ux`.** Options as D-169 made `--listen` and `--serve`; the part words `eve tx` and `eve ux` of D-163 stay as synonyms (`eve ux start` and `eve -ux` are the same). `-u` is removed rather than kept, because the author finds it unclear.

- **(d) The shape of `eve.env`.** Proposal: `{ "prod": { "user": "ana", "password": "…" }, "test": { "user": "ana", "password": "…" } }`; a value may be `"$NAME"`, read from the real environment, so a CI system gives the secrets without a file; the file is read only by `eve` of this project, and on Unix it must be mode 600 or it is refused. `project init` and `project new` add it to `.gitignore` and write a template without secrets.

- **(e) More ideas.** The history of commands in the cache also gives `history` and the search with Ctrl+R; the manifest gives a `diff` of local and server in the Projects view; a `dry run` of the upload that lists what would be sent; the status line of the REPL and evetx share one component.

**Answer:**

Ok, eveux and evetx will have user login dialog. eve will have -u --user, and -a --adming two ways to enter username, the password is a dialog, machine will ask the password (secret field) with stars.

## Q-053 The size and the needs of the evetx IDE (2026-10-13)

Proposals and questions for the author, from the design of D-173.

- **(a) Size.** An editor, a debugger and a database browser are three programs in one. Is all of it level 6 (version 0.0.6) with the split, the bytecode and the machine API, or does the first release of evetx have the file tree, the editor, run, the bottom panel, the machines and the upload (steps T0 to T5) and the debugger and the database tabs (T6, T7) follow in the next version? Proposal: order the work as in `code/evetx/README.md` §8 so that each step is usable alone, and decide at T5 whether T6 and T7 stay in 0.0.6.

- **(b) The debugger of the machine** (F-TLS-04) is open: today `halt` breakpoints and `vm.suspend` and `vm.resume` exist, nothing sets a breakpoint by file and line, steps into or out, or evaluates in the paused frame. Proposal: add to the machine API, after B2: set and clear a breakpoint by file and line, step into, step out, continue (the `vm.resume`), the paused place, evaluation in the paused frame, and the two streams of a run (stdout, stderr); the names are the author's to choose. These are also what `eveux` needs (F-TLS-22), so one API serves both.

- **(c) The database methods.** `db.query` and `db.execute` exist; the table list, a page of rows, the description of a table and the change of a table need methods or `db …` commands (F-DAT-09 has `db tables` and `db describe`). Proposal: `db.tables`, `db.rows` (a page), `db.describe` and `db.alter`, named by the author.

- **(d) What "edit structure" may do.** Rename a column, add a column and drop a column are easy in SQLite 3.35 and later; a new type or a new key needs the rebuild of the table (copy, drop, rename); DuckDB allows more. Proposal: the dialog lists what Apply will do, shows the SQL on request, and asks before a rebuild or a drop of a column with data; a table of a remote machine is changed only by a user whose role allows it (D-155 §15.4).

- **(e) Step over.** The author lists Run, Step into, Step out, Continue and Stop. Most debuggers have Step over (next line). Add it, as a sixth button, or not?

- **(f) What the editor must do** in the first version. Proposal: plain text with syntax colors for Eve, SQL and JSON; cursor, selection, copy and paste, undo and redo, search and replace in a file, save, a mark for an unsaved file, line numbers and the breakpoint gutter; no completion, no folding, no multiple cursors. Completion from the language server (F-TLS-09) later.

- **(g) Where a run goes when the file is local.** On the local machine (F1) the program runs from the file on disk. On a remote machine (F2, F3) it must be uploaded first (D-171). Proposal: when the file is changed and not uploaded, Run on a remote machine says so and offers Upload and run; a breakpoint is checked against the hash of the file on the server, so a breakpoint never lands on a different line.

- **(h) Keys.** F5 run, F8 continue, F9 breakpoint, F11 step into, Shift+F11 step out, Shift+F5 stop (drawn in the SVG, proposed). They are used by IDEs, but Windows Terminal and some SSH clients or multiplexers take some F-keys; check them as in Q-051 i.

- **(i) Two UIs.** `eveux` (level 7) has the same editor, debugger and database features (F-TLS-19 to F-TLS-22). Should the design of the debugger and of the database dialogs be written once, in the machine API and in a page of the spec, so that both screens follow it?

**Answer:**
Please move these questionns in /evetx project for design, some of them are aleady implemented.

## Q-054 The details of D-174: keys, the gear, search scope, types, the calendar, the console (2026-10-13)

Proposals and questions for the author.

- **(a) Keys the terminal cannot tell.** A classic terminal sends the same bytes for Ctrl+Enter as for Enter, and for Ctrl+/ as for Ctrl+_ (and Ctrl+Shift+S as Ctrl+S, Ctrl+, as a comma). They work only where the terminal speaks an enhanced keyboard protocol, which libvaxis uses when it can. The spike T0 tests Windows Terminal, the Windows console and a Linux terminal. Proposal: keep Ctrl+Enter and Ctrl+/ as asked, and add **F10** (menu) and **F12** (help) as keys that every terminal sends; the title and the `?` button work with the mouse anyway. The shortcuts of the menu (Ctrl+O, Ctrl+N, Ctrl+S, Ctrl+Shift+S, Ctrl+W, Ctrl+Q, Ctrl+Z, Ctrl+Y, Ctrl+F, Ctrl+H, Ctrl+K, Ctrl+U, Ctrl+,) are my proposals; the F-keys of the debugger are in Q-053 h.

- **(b) The gear in two places.** The author asks for a gear in the tool bar (top right) and in the status bar (bottom right). Do both open the same Settings dialog, or is one for the application (colors, keys, tab size) and the other for the project (machines, `eve.env`, upload rules)? Proposal: both open one dialog with two pages, Application and Project. What Settings holds is not decided: proposal: colors (a dark and a light theme, a no-color mode), borders (box drawing or ASCII), tab size and spaces or tabs, mouse on or off, the keys that can be changed, the user cache folder, the machines list (name, address, user; no secrets).

- **(c) The scope of Find.** In an editor: the text of the file (Enter next, Shift+Enter previous). In a table list: it filters the tables. In a data tab: it filters the rows (the database does the work, `db.rows`). Replace and Replace all are only for an editor and are off in the other tabs. Search in all the files of a project is not drawn; proposal: later.

- **(d) One menu.** The drawing has one list of sections (File, Edit, Run, Machine, Help) opened both by a click on the title and by Ctrl+Enter. Or does Ctrl+Enter open a menu bar with drop-downs (File, Edit, …) and the title a different list? Proposal: one menu. "Sage/Save-As" is read as Save and Save As.

- **(e) The types in the list.** The types of the engine of the file (SQLite: INTEGER, REAL, TEXT, BLOB, NUMERIC and the common names; DuckDB: its long list), or the types of Eve (`Integer`, `Decimal`, `Text`, `Boolean`, `Instant`, …) mapped to the engine by the data language? Proposal: the engine's own names in the list, and the Eve type that goes with it shown beside the cell, since the file is read by other programs too.

- **(f) What the calendar writes.** A chosen day gives a fixed value (`'2026-10-13'`); **Today** and **Now** give the expressions of the engine (`CURRENT_DATE`, `CURRENT_TIMESTAMP`). The Default cell shows which of the two it is. Is that the author's intention?

- **(g) The status bar.** Name of the file or table, then the place: `Ln, Col` in an editor; `Record n of N · Field: name` in a data tab; `Table k of n` in a table list; `Field n of m: name` in the structure dialog. Add the encoding and the line ending (`UTF-8 · LF`) for an editor?

- **(h) The console of evevm.** Its design is the REPL screen of `manual/usage.md` (the upper part with a scrollback of 50,000 lines, a rule, the command line `eve:> `, a rule). In evetx the machine runs the commands (`vm.*`, or the command channel of `eve -c`), and the `Ready` and `Running…` state moves into the status bar of the application. To use the same code and not only the same look, the scrollback buffer and the line editor of the REPL (today `line.zig` and `terminal.zig`) go to `code/evecm/term`, which D-163 already plans; libvaxis draws the screen in evetx and the REPL keeps its own drawing. Agree?

**Answer:**
Move this to /evetx folder when I work onn evetx I will respond
