# evetx: the Eve text user interface

Status: **design for review**, first draft 2026-10-13. Nothing is built yet. Planned for **level 6** (version 0.0.6, phase B of [design-packages.md](../plan/design-packages.md), step B6). Recorded as Q-050 in [decision_level6.md](../plan/decision_level6.md); features F-TLS-24 and F-TLS-25 of [version_map.md](../plan/version_map.md).

## 1. What evetx is

`evetx` is a **full-screen terminal application** (TUI) that manages **projects and schedules on one or more Eve machines**, local or remote, from a shell or an SSH session. It is the terminal sibling of the browser Workbench [eveux](../eveux/README.md): the same machines, the same API, another screen.

| | `eveux` | `evetx` |
|---|---|---|
| Screen | browser (HTML, JavaScript, CSS) | terminal (libvaxis) |
| Written in | Eve (D-154) plus a small Zig door | Zig, with one dependency: libvaxis |
| Level | 7 | 6 |
| Needs | a browser and the HTTP door | only a terminal; works over SSH |
| Focus | editor, SQL, debugger, jobs | machines, projects, schedules, runs and logs |

`evetx` does **not** run user code and holds no state of its own about a machine. Every action is a call of the machine API (`vm.*`, `db.*`, D-165) to the machine it manages, the same call `eve -c … -rem <machine>` sends. What `evetx` can do is therefore exactly what the machine allows to the logged-in user.

## 2. Where it lives in the architecture

`evetx` is one more **module** of the split (D-163), and one more word of the command: `eve tx`, with the shortcut `./run.sh evetx <args>`.

```
cmd ──► evetx ──► evecm      (and libvaxis, a package dependency)
```

- **`evetx` imports `evecm` only**, like `eveux`: it never imports `evevm`, `evedb` or `evecp`. The build refuses another import. It reaches a machine only through the JSON-RPC client of `evecm/wire`, so it behaves the same against the local machine and a remote one.
- **`libvaxis` is already a Zig library.** There is nothing to bind: no C, no `@cImport`, no wrapper. It is a dependency in the root `build.zig.zon` and an import of the module `evetx` alone, so no other module (and not `evecm`) can use it, and a build without `evetx` does not fetch it. If the library is missing or too old for the Zig version, only `eve tx` is affected.
- **The line editor of `evecm/term` stays** for the REPL. `evetx` takes the terminal for itself (raw mode, alternate screen) only while `eve tx` runs.
- **A direct command, not a serving part.** `eve tx` is a client process that opens the screen, talks to machines, and ends when the user quits. It does not join the serving machine of D-164.

## 3. What the user sees

One screen, four areas: a **machines list** on the left, the **view** of the selected machine on the right, a **log or output pane** at the bottom, a **status line** with the key help.

| View | Shows and does | Machine calls (proposed) |
|---|---|---|
| **Machines** | the machines of the registry (name, address, state, version, load); add, remove, log in, log out; connect again from the keyring without a form (F-NET-07, D-155) | `vm.ping`, `vm.stat` |
| **Projects** | the projects deployed on the machine (name, driver files, last run, state); upload a project folder; run a driver now; stop, suspend, resume or cancel a running one | `vm.run`, `vm.suspend`, `vm.resume`, `vm.cancel`, `vm.stop`, the upload of `-u` |
| **Schedules** | the schedules of the remote scheduler (driver, rule, next run, last result); add, change, pause, resume and delete one; run one now | the `sched.*` methods, see §5 |
| **Runs and logs** | the history of runs (start, duration, exit code), the run log of one run, and a live tail of a running one | `vm.stat`, the run log stream |
| **Console** | one line to evaluate Eve on the machine and see the answer; the same as `eve -c` | `vm.eval` |
| **Databases** (later) | the connections of the machine and a statement box | `db.stat`, `db.query` |

Rules of the screen:

- **Keyboard first:** arrows and `j`/`k`, `Tab` between areas, `Enter` to open, `/` to filter, `:` for a command line (the commands of `eve:>`), `?` for help, `q` to leave. The mouse works where the terminal sends it (click to select, wheel to scroll).
- **Many machines at once:** the list refreshes every machine on a timer; a slow or lost machine shows its state and never blocks the screen.
- **Never a surprise:** a destructive action (delete a schedule, stop a running job, log out) asks first and names the machine.
- **Colors and glyphs** degrade: no color terminal, no Unicode box drawing, or a small window still gives a usable screen.

## 4. How it is built

```
evetx/
├── README.md
└── src/
    ├── root.zig        the module entry: run(argv, io) for dispatch.zig
    ├── model.zig       the state: machines, selection, views; pure data, no terminal
    ├── update.zig      event + model → new model + requests; pure, no terminal
    ├── view.zig        model → cells drawn with libvaxis widgets
    ├── client.zig      one task per machine: calls, timers, replies as events
    └── registry.zig    the machine registry and the credentials (see §5)
```

- **Elm-style loop.** Terminal events (key, mouse, resize) and machine replies are all *events* in one queue. `update` is a pure function from `(model, event)` to a new model and a list of requests; `view` only draws the model. This is the shape libvaxis was built for, and it gives the tests a place to stand.
- **One task per machine** (`std.Io` tasks, as in D-164) sends the calls and the timer polls; a reply or an error comes back as an event. The screen task never waits on the network.
- **Tests without a terminal.** `model.zig` and `update.zig` import neither libvaxis nor the network, so `zig build test` runs scripted event sequences against them and compares the model. A fake machine (a `Dispatcher` of `evecm` that answers canned replies) tests `client.zig`. Only `view.zig` needs a real terminal; it is checked by hand and by a screen snapshot taken from the libvaxis virtual screen when the library offers one.
- **Zig is taught here:** every function, test and type gets its `// Zig tip:` block (see `CLAUDE.md`). The first tips this module needs: tagged unions for events, `switch` on them, `std.Io` tasks, and a package `dependency` in `build.zig`.

## 5. Open points, for the author (Q-050)

1. **Schedule API.** The machine has a remote scheduler on paper (design-service.md §11, `schedule "x" at "02:00" every day` in `eve.cfg`) but **no API to read or change it**. Proposal: add `sched.list`, `sched.add`, `sched.update`, `sched.remove`, `sched.pause`, `sched.resume`, `sched.runs` to the machine API of step B2, with the `eve.cfg` lines as the stored form. `evetx` and `eveux` then share one API. The names and the stored form are the author's to decide.
2. **Where the machine registry and the keyring client live.** D-155 puts login and the keyring in `eveux`, which `evetx` must not import. Proposal: the registry of machines, the credential store (Windows Credential Manager, Linux Secret Service) and the login flow go down to `evecm/wire`, used by `eve -rem`, `eveux` and `evetx` alike. This moves a part of D-155 and the module table of design-packages.md §3.
3. **Project deploy.** Does `evetx` upload a project folder file by file with the upload of `-u`, or does the machine get a `deploy` command (the open question of `decision_level6.md`)? The Projects view needs one of them.
4. **libvaxis and Zig 0.16.** The repository uses Zig 0.16. libvaxis follows the Zig releases, but its support for 0.16 and for Windows consoles is **not yet checked**. Step T0 of the plan is a one-day spike that decides it; the fallbacks are a pinned commit, a small patch kept in the repository, or a thin terminal layer of our own.
5. **Name.** `evetx` (text UI) is the name of the author's request; `eve tx` is the part word. No clash with the other words (`vm`, `cp`, `db`, `ux`).

## 6. Work plan (level 6, version 0.0.6)

Each step ends with the usual checks: the ReleaseSafe build, `runtest.py all`, `bmark.py --check` (the interpreter is not touched, so no change is expected), and `zig build test`. Full table with the dependencies on B1 to B4: [design-packages.md](../plan/design-packages.md) §10, step B6.

| Step | Work | Done when |
|---|---|---|
| **T0 Spike** | add libvaxis as a dependency, draw a window with a list and a text input, read keys and resize, on Windows Terminal and on Linux | builds with Zig 0.16 on both; the decision on §5 point 4 is written down |
| **T1 Skeleton** | module `evetx`, the part word `tx`, the shortcut `evetx` in `run.sh`, the arrow checked by the build; empty screen with status line and help | `./run.sh evetx` opens and closes cleanly; the terminal is restored after a crash and after Ctrl-C |
| **T2 Model and update** | events, model, update and their unit tests, with no terminal | scripted key sequences give the expected model |
| **T3 Machines view** | the registry, `vm.ping` and `vm.stat` per machine, login from the keyring (needs B3 and F-NET-07) | two local machines on two loopback ports are listed with their state; one lost machine does not freeze the screen |
| **T4 Projects and runs** | the project list, run, stop, suspend, resume, cancel, the run history and the live log (needs B2) | a test project is run and followed to its end from the screen |
| **T5 Schedules** | the Schedules view over `sched.*` (needs the decision of §5 point 1 and the scheduler of F-TLS-13) | a schedule is added, paused, run now and deleted on a test machine |
| **T6 Console and polish** | the console line, filters, mouse, small windows, no-color mode, key help | a session script (keys in, snapshot out) passes |
| **T7 Documents** | `manual/usage.md` (`eve tx`), a tutorial page after the spec, the README updated, `version_map.md` | `mdlinks.py check manual` clean |

## 7. Risks

| Risk | Answer |
|---|---|
| libvaxis does not build with Zig 0.16, or on Windows | the spike T0 comes first; a pinned commit or a patch; the module is the only user, so the loss is one part, not the build |
| A new dependency to fetch | `evetx` is a lazy dependency: only a build that includes `evetx` fetches it |
| The screen freezes on a slow machine | one task per machine; the screen task only reads events |
| A broken terminal after a crash | restore the terminal in `defer` and in the panic handler; tested in T1 |
| The module grows into a second Workbench | the scope is machines, projects, schedules, runs and logs; the editor, SQL grid and debugger stay in `eveux` (level 7) |
| Tests hard to write for a screen | the model/update/view split of §4: only the drawing is untested by machine |
