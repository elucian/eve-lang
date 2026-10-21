# evetx: status for level 6

The state of the work on evetx, the terminal IDE (F-TLS-24, F-TLS-27 to F-TLS-29). Marks: `[x]` done, `[ ]` to do, `[-]` dropped. The features in full are in [README.md](../design/components/evetx/README.md) §11. Last update: 2026-10-16.

## Plan steps (README.md §8)

- [x] T0 Spike: libvaxis pinned for Zig 0.16, builds on Windows
- [x] T1 Skeleton: frame, menu bar, three panels, status bar; `eve -tx` starts it
- [x] T2 Text buffer with undo (no automated tests, D-178)
- [x] T3 Tree and editor: tabs, Eve and SQL colors, Save, Save As, Find, Replace, GoTo, help windows
- [x] T3b File card for binary files (D-178)
- [x] T4 Run and the Tools Panel: Console, Stdout, Stderr, SQL; Run does not block the screen
- [-] T5 Remote machines and upload: moved out of 0.0.6 (2026-10-16); waits for a lasting machine connection and login
- [x] T6 Debugger, local: Run, Halt, Next, Step, Exit, Trace through `eve debug`; Breaks and Watch tabs
- [ ] T6 Debugger: breakpoints in aspect and module files
- [x] T7 Databases, local: SQLite tables and views in the tree, read-only grid, structure dialog, create, drop, rename
- [ ] T7 Query (F7, a find that filters tables or data)
- [ ] T8 Documents: the evetx section of `manual/usage.md`, the tutorial page, `spec/features/`

## Cuts and changes of 2026-10-16

- [x] Border delay timer removed: a locked layout does not move; open the lock (or Ctrl+L) to drag a border
- [x] Markdown preview removed (`md.zig`, the eye button, WINDOW > Preview); eveux renders Markdown (D-178)
- [x] The preview button is now **Properties** (`i` on the Main Panel): the facts of the current file in a small dialog
- [x] Properties renames a file, a folder, a DBF table or a table of a SQLite file; File > Rename… and Rename… of a tab open the same dialog
- [x] Remote machines removed: the registration form, the machine name and its dropdown on the toolbar, the MACHINE menu, Alt+1 to Alt+3
- [x] Upload removed (FILE menu and the popup menu of a tab)
- [x] Themes: the 13 themes exported to [themes/](../code/evetx/assets/themes) as JSON files
- [x] Themes: three built-in themes, Dark Theme, Gray Theme, Light Theme (from Dark Sage, Shades of Gray, Light Sage); they cannot be changed, renamed or removed
- [x] Themes: a change of a color of a built-in theme makes a custom theme `Dark Custom1`, `Gray Custom1`, `Light Custom1`, …
- [x] Themes: many custom themes (up to 24); Rename, Remove, Export (JSON), Import (JSON; a name that is taken gets a number)
- [x] Themes: the custom themes are kept in the user cache (`evetx-themes.json`); `zig test src/options.zig` checks the JSON round trip
- [x] Fixed: the debug path was freed twice when evetx ended
- [x] README.md and the Shortcuts help brought up to date

## Changes of 2026-10-16 (second round)

- [x] Tab row of the Main Panel: `<` at the left, `>` at the right (in place of the `i` button); they shift the tabs when they do not fit; the row follows the active tab
- [x] Info… in the popup menu of a tab (the `i` button is gone): title `File: <name>` (or `Table:`, `View:`, `Folder:`), a rule, the properties
- [x] Info: Rename makes the name a field in its place; the folder is a property, changed with Move
- [x] Info: Move opens the folder selector (the Open Folder dialog, now with four uses) and moves the file inside the project
- [x] Theme Export and Import open the folder selector with the `.json` files and a file name field (the theme name for Export, the chosen file for Import)
- [x] A file that is not a theme opens the pop-up "Operation failed"; OK closes it and goes back to Options

## Changes of 2026-10-16 (third round)

- [x] `return` has the color of the keywords (`procedure`): it closes a block, it is not an interruption
- [x] Folder selector: a rule under the title, a vertical scroll bar when the folders do not fit
- [x] Info dialog: the hint is on the row above the buttons (it was under them)
- [x] Table grid: `│` between the columns, `#` instead of Record, no types in the header, widths fitted to the data (trimmed in proportion when there is no room, never under 12), every other row on a discreet background

## The machine API for evetx and eveux (2026-10-16)

- [x] The stdio door: `eve --stdio`, a machine of one client on its standard input and output (local first; over SSH `ssh host eve --stdio`)
- [x] The IPC door keeps its connection: many messages per connection (the CLI that sends one and closes still works)
- [x] Notifications `vm.output`: the output of `vm.run`, `vm.eval`, `vm.shell` streams with `"stream": true`
- [x] Sessions: `vm.open`, `vm.eval`, `vm.close`, a default session per connection, a folder per session (`cd`)
- [x] `vm.shell`, and `shell <command>` / `!<command>` at the prompt of eve and in a session: the command runs, eve stays
- [x] `vm.run` by path, `vm.cancel`, `vm.stat` with `door` and `sessions`; the quick methods answered at once, the others in order
- [x] evetx: the console through its machine (`src/link.zig`); no `$` mode; `exit` closes evetx; Halt sends `vm.cancel`
- [x] Test `e95_test5` (the stdio door, 23 checks); spec `library/machine.md#lasting-doors`; `manual/usage.md`; eveux README
- [ ] Runs through the machine: a working folder of the session for the files a script opens (today the folder of the machine)
- [ ] The debugger as methods (`dbg.*`, `dbg.paused` notifications) instead of `eve debug` as a process
- [ ] `db.tables`, `db.rows`, `db.describe` in JSON, so evetx stops reading the text of `eve db sql -t`
- [ ] WebSocket on the HTTP door with the same messages (eveux), after login (F-NET-06)

## TODO

- [ ] Export over an existing file replaces it without asking (ask first?)

- [ ] **SQLite structure dialog loses indexes and triggers** on Apply: recreate them, or refuse when the table has any
- [ ] **Wide characters:** the emoji icons of the tree and the tabs are two cells wide in some terminals; use one-cell symbols
- [ ] Remove the Query stub (F7, SEARCH > Query…) or build it
- [x] DBF support decided (D-184): a file decoder only for legacy ingestion; creation removed 2026-10-17
- [ ] D-184: Import command (CSV, TXT, DBF, XLS, JSON) into a database; then remove the DBF structure dialog and the DBF writing code
- [ ] D-184: SQLite `:memory:` query engine with tuned PRAGMAs; native columnar (SoA) tables for the pipelines; the grid reads from them, not from `dbf.Table`
- [ ] Decide on the `$` shell mode of the console (keep the one-shot `shell <command>`; interactive commands hang)
- [ ] Old options: a custom theme saved by an older evetx (`color.*` lines of `evetx-options.txt`) is not read any more; make it again or import a theme file
- [ ] Split `app.zig` (about 6,500 lines) into parts: debugger, SQL panel, dialogs, tree actions, menu
- [ ] `spec/features/`: F-TLS-24, F-TLS-27, F-TLS-28, F-TLS-29 still say "open" or "partial" with old notes
- [ ] T8 documents (see above)

## Later: the machine connection (for T5 and eveux)

Today the machine answers one JSON-RPC message per connection and closes it: right for `status`, `run`, `stop`, not enough for an IDE, which needs the output of a run as it comes and the place where the debugger stopped. That is why evetx runs `eve` and `eve debug` as child processes.

- [x] Keep the connection open and let the machine send notifications (`vm.output`; `dbg.paused`, `dbg.end` with the debugger methods)
- [ ] The same messages over a WebSocket of the HTTP door (eveux needs it, D-155); the IPC and stdio doors have them
- [ ] The `@debug` lines of `eve debug` become `dbg.*` methods, one for one
- [ ] `db.tables`, `db.rows`, `db.describe` answer in JSON, so evetx stops reading the text of `eve db sql -t`
- [ ] Login (Q-048) before any remote run or upload; then T5
