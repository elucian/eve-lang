# eveux: the Eve native workbench

`eveux` is the graphical development client of Eve: a native window program written in Zig on the GUI library dvui. Like `evetx`, it is a client of the Eve machine: it never runs Eve code inside the window and never holds a password.

**Status: early draft.** The program builds and opens a window, but the window is a stub: the shell, the editor, the previews and the database views are designed, not written. This page describes what eveux is for; the list of what works grows with each release (see [Features](../features.md)).

## Starting it

```
eveux [project-folder]
eve -ux [project-folder]      the same, started by eve from its own folder
```

## The working model

Code is always local: it is edited, run, debugged and tested on this computer. A project that passed its tests is **deployed** to a machine, and there it runs by a schedule or behind the Eve Web Portal (`evewp`); eveux then **operates** it (status, schedules, jobs, logs, versions, rollback) and does not edit it.

## What it will do

| Area | Content |
|---|---|
| Edit | Eve, SQL, JSON, XML, HTML, JavaScript, CSS, Markdown and text with colors; find and replace; completion and hover docs for Eve |
| Embedded checks | the Eve compiler front end is linked into the program: errors, outline and symbols while typing |
| Run and debug | on the local machine: run, check, stop, breakpoints, step, variables, watch, call stack, console |
| Preview | Markdown, HTML, images and SVG, audio and video |
| Database | tables in a grid, the structure dialog, SQL tabs with results in Eve types, commit and rollback |
| Source control | status, diff, stage, commit, branches, history (through `git`) |
| Deploy and operate | deploy with a diff against the target, versions and rollback; schedules, jobs and logs of a remote machine |

One tool bar follows the kind of the active file: Run, Stop, Debug, Check, Test and Deploy for Eve; Run, Script, Explain, Commit and Rollback for SQL; Source, Split and Preview for documents.

## Platforms

Windows first (the DX11 or SDL3 backend); Linux and macOS later, with SDL3. Building on Windows needs Developer Mode on (the fetch of dvui makes symbolic links). From the source tree: `./run.sh build eveux` installs `bin/eveux.exe`.
