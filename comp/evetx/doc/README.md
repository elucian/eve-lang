# evetx: the Eve terminal IDE

`evetx` is a full-screen terminal application for working on one Eve project: a file tree, an editor with tabs, run and debug, a console, and database tables in a grid. It needs nothing but a terminal, so it also works inside an SSH session on another computer. It does not run Eve code itself: every run, step and query goes to the Eve machine (`eve`), as a client.

## Starting it

```
evetx [project-folder]        the current folder by default
eve -tx [project-folder]      the same, started by eve from its own folder
```

The session (open files, cursors, layout, breakpoints) comes back at the next start.

## The screen

| Panel | Holds |
|---|---|
| Tree Panel | the folders and files of the project; Ctrl+click selects, a drag moves files to a folder |
| Main Panel | the open files in tabs: the editor, the grid of a table, the card of a file that is not text |
| Tools Panel | Console (`eve:>`), Watch, Stderr, Stdout, Breaks and the SQL panel |

The menu bar has FILE, EDIT, SEARCH, RUN, WINDOW and HELP (F10, or Alt and the first letter). The panels can be hidden, maximized and resized (open the layout lock on the tool bar to drag a border).

## What it does

- **Edit:** Eve and SQL colors, selection by mouse and keys, the system clipboard, undo and redo, find, replace, go to line, find file, auto save.
- **Files:** new file by kind (`.eve`, `.sql`, `.dbf`, `.db`), save as, rename, move, an Info card (kind, size, date, lines, records).
- **Run and debug:** Run, Halt, Next, Step, Exit and Trace on the tool bar; breakpoints in the gutter; watch; the console with history and Tab completion.
- **Data:** DBF tables (edit cells, add and delete rows, the structure dialog) and SQLite files (tables and views in a read-only grid).
- **Options** (F2 or Ctrl+,): three built-in themes (Dark, Gray, Light), custom themes, import and export of theme files (JSON).

## Help inside the program

HELP opens three windows; their texts are the files of this folder:

- [shortcuts.txt](shortcuts.txt): every key
- [manual.txt](manual.txt): the manual of evetx
- [tutorial.txt](tutorial.txt): a first session, step by step

## Limits

Only the main script is debugged (no breakpoints in aspects and modules yet). Remote machines and upload were removed from this version; the database tabs start `eve db sql` for each action. Ctrl+Enter, Ctrl+/ and Ctrl+Shift+S need a terminal with the enhanced keyboard protocol (F10 and F4 work everywhere); Windows keeps Alt+Tab for itself (use Ctrl+Tab). Wide characters such as emoji may be drawn out of place.

## Building

From the source tree: `./run.sh build evetx` installs `bin/evetx.exe` (Zig 0.17.0; the library libvaxis is fetched by the build).
