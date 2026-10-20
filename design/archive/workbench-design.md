# eveux: the Eve RAD Workbench

Status: **design for review**, second draft 2026-10-10. Nothing is built yet. Changed by the author on 2026-10-10 (D-154, D-155): **eveux is written in Eve**, as the final test and the stress test of the language, so it belongs to **level 7**, the last level (Version 0.6); Zig is used only for the Eve virtual machine `evevm`, which from one local instance works with many remote machines and logs in to each of them with its own credentials, by single sign-on, keeping them in the keyring of the operating system after the first login. The Workbench uses the terms of [design-service.md](../design-service.md): machine, machine folder, command port 4042, `serve` port 8042, driver memory space (DMS), run log, remote scheduler; the login to remote machines is its section 15. Features F-TLS-19 to F-TLS-22 of [version_map.md](../version_map.md); open points at the end and in Q-047 ([decision_level6.md](../decision/level6.md)). Tutorial page: `eveux.html`, phase 6.

## 1. What eveux is

`eveux` is a **rapid application development (RAD) workbench for Eve that runs in a web browser**, and it is **an Eve project**: service scripts, aspects and modules written in Eve, run by the local Eve machine, plus the browser part in plain JavaScript and plain CSS with no framework and no build step. A person starts the local machine with the Workbench, opens it in the browser, and works with one or more Eve machines from one window:

- writes Eve, SQL, JSON, XML and HTML in an editor with syntax colors;
- runs a script, or steps through it line by line and watches its variables;
- types machine commands and SQL in a command window and sees the answer as a table;
- browses the databases of a machine as a tree of objects;
- loads and imports files;
- schedules drivers as jobs, follows them while they run, and reads their logs, as in Jenkins, but with the knowledge of Eve (aspects, jobs, checkpoints, error codes);
- logs in to remote machines with single sign-on, and manages their users when it is their admin.

The Workbench never runs the user's code itself. Every action on a machine is a command sent to that machine, the same command a person types at `eve:>` or sends with `eve -c`. What the Workbench can do is therefore exactly what the machine allows (design-service.md §10): a remote machine refuses debug mode and the shell unless its configuration allows them, and the Workbench shows the refusal.

## 2. The final test of Eve

The author's reason for writing eveux in Eve: a real application, used every day, is the hardest test a language can get. eveux needs every level of the language at once, so it is the acceptance test of level 7 and of Version 0.6, and a **stress test** of the virtual machine.

| Level | What eveux uses |
|---|---|
| 1 | strings and placeholders, collections, control flow, jobs with `recover` and `retry` everywhere a machine can fail |
| 2 | one aspect per group of routes (files, SQL, jobs, logs, debug, machines, users), lambdas and closures for sorting and filters of the grid |
| 3 | modules (`machines`, `grid`, `streams`, `colors`), classes (`Machine`, `ResultPage`, `Job`, `Run`) and their methods |
| 4 | requests answered in parallel, live streams of output and logs through channels, generics (`Page(:T)`) |
| 5 | JSON in and out, CSV and JSON import, files, the database layer and SQL on any connection, the Eve database of the machine, the HTTP client |
| 6 | `serve`, the `service` script and its routes, a local machine that works with many remote machines, login with single sign-on and the keyring, the remote scheduler, the debugger commands |
| 7 | HTML templates and the `HTML` type for the pages, WebSocket for the live streams; later a playground tab with Eve in the browser |

**Stress goals** (measured by the tests of `test/level7` and by a benchmark, `p7a_eveux`, with the rules of `test/bmark`):

- 10 remote machines connected at once, each with its own login, from one local machine;
- 20 browser tabs open, each following a live log or a run;
- a query of 1,000,000 rows read page by page, a log of 200 MB followed to its end;
- 95% of the API answers under 100 ms on `localhost` while the above runs;
- 8 hours of continuous use with flat memory (the reference counting of D-151 tested for leaks under a real load; `EVE_MEMSTATS=1` at the end).

A failure of eveux is first a question about Eve: a missing feature, a slow path or a leak of the VM. It is fixed in the language or in the VM, not worked around in eveux.

## 3. Goals and non-goals

| Goals | Non-goals |
|---|---|
| one window for the daily work of an Eve developer and of an ETL operator | a general IDE for other languages (the editor colors five languages, it does not compile them) |
| the server part written only in Eve, run by the local machine | a server part in Zig, Python or JavaScript |
| the browser part in plain JavaScript (ES modules) and plain CSS, loaded directly | React, Vue, Angular, npm packages, bundlers, a Node.js build |
| works with the local machine and with many remote machines, each with its own login | replacing the command line: everything stays possible with `eve -c` |
| a job browser as useful as Jenkins for Eve drivers, with Eve's own knowledge | a CI server for other build tools; plugins |
| SQL against any connection of a machine, results as a grid | a DBA tool for vendor features (tablespaces, replication) |
| safe by default: `localhost`, a login per remote machine, roles, no secret ever sent to the browser | public internet access to the Workbench |

## 4. Architecture

```
+---------------------------+  HTTP,      +------------------------------+  EWP / 4042  +-----------------------+
| Browser                   |  WebSocket  | Local Eve machine (evevm)    |  TLS, login  | Remote machine prod   |
|  index.html, css/, js/    | ----------> |  serve on localhost:8042     | -----------> |  users, roles, jobs,  |
|  menu, editor, panels     |  JSON       |  eveux project, in Eve:      |              |  logs, databases      |
|                           | <---------- |   service eveux_api (routes) | -----------> +-----------------------+
+---------------------------+             |   aspects, modules           |              | Remote machine etl2   |
                                          |  connections to many machines|              +-----------------------+
                                          |  credentials: OS keyring     |
                                          +------------------------------+
```

- **Browser.** One page, `index.html`, loads `js/app.js` as an ES module. Every panel is a module. No inline script, so a strict Content Security Policy is possible (§15).
- **The eveux project.** A machine folder (design-service.md §4) holding the service script `eveux_api` with the routes of §14, its aspects, its modules and the web folder. It runs on the **local machine** of the user: `eve --setup eveux --serve`.
- **The local machine (evevm, Zig).** It serves HTTP and WebSocket, runs the routes, and holds the **connections to the remote machines**: one connection per machine, each with its own login, single sign-on and credentials kept in the keyring of the operating system (design-service.md §15). eveux asks the machine to connect, to send a command, to stream a run; it never sees a password or a token.
- **Remote machines.** Eve machines started with `--listen`. They own their users, roles, files, jobs, logs and databases, and check every command against their own rules.

### 4.1 What eveux needs from the virtual machine

**The machine API for both IDEs (2026-10-16).** evetx and eveux speak the same messages to the machine; only the transport differs. evetx starts its own machine on the **stdio door** (`eve --stdio`: no port, no socket, and over SSH `ssh host eve --stdio`, where SSH does the login); eveux will use the **WebSocket** of the HTTP door once the machine has its login. On both, a connection lasts, carries many requests, gets the output of a run while it runs (`vm.output`), keeps a session per tab, and can cancel what runs (`vm.cancel`). The rules are in `spec/library/machine.md#lasting-doors`; the test is `test/level5/e95_web_hello/e95_test5.eve`. So the Command window, the run output and the jobs of eveux are built on calls that evetx already uses every day.

Everything that is not Eve code is a feature of `evevm`, so that every Eve program gets it, not only eveux:

| Need | Where |
|---|---|
| `serve`, `service` and routes, static files of the web folder | F-TLS-14, F-NET-02 (level 6) |
| WebSocket in `serve`, so a route can push lines to the browser | new, with F-NET-02 (question 3); it will carry the messages of the **lasting doors** unchanged (below) |
| connections to many machines from one local machine, `send`, upload | F-TLS-13 (level 6) |
| login to a machine: credentials, single sign-on, keyring | F-NET-07 (level 6, D-155) |
| a *watched run*: the output, the log and the debugger events of a run stream back on the connection | **started 2026-10-16**: `"stream": true` on `vm.run`, `vm.eval`, `vm.shell` sends `vm.output` notifications on the IPC and stdio doors (`spec/library/machine.md#lasting-doors`); the log and the debugger events come next |
| a prompt per tab: the state of the Command window kept between commands | **started 2026-10-16**: sessions (`vm.open`, `vm.eval`, `vm.close`; a default session per connection) |
| commands of the system from the Command window | **started 2026-10-16**: `vm.shell` (the IPC and stdio doors only until login; through the HTTP door after F-NET-06) |
| debugger commands: `break`, `step into`, `step out`, `locals`, `stack` | F-TLS-04 (Q-047) |
| file commands on a machine: `files`, `read`, `save`, `delete` | F-TLS-13 (question 6) |
| HTML templates and `HTML` | F-WEB-01 (level 7) |

## 5. The screen

```
+-------------------------------------------------------------------------------------------+
| Eve Workbench  File  Edit  View  Run  Debug  Database  Jobs  Machines  Admin  Help [dev1] |
+------------------+--------------------------------------------------+---------------------+
| EXPLORER         | sales_load.eve x | orders.sql | eve.cfg          | VARIABLES           |
|  v machine dev1  |  1 # sales load                                  |  v globals          |
|    v project     |  2 driver sales_load is                          |     total  1240.50  |
|      sales.eve   |  3   process main is                             |     rows   [12]     |
|      asp/        |* 4     new total := 0.0;            <- current   |  v locals (main)    |
|    v databases   |  5     for r in rows do                          |     r   {id: 7 ...} |
|      v eve (db)  |  6       let total += r.amount;                  | WATCH               |
|        > tables  |  ...                                             |   total > 1000  yes |
|      v test      +--------------------------------------------------+ CALL STACK          |
|        > tables  | COMMAND | OUTPUT | RESULTS | PROBLEMS | LOG      |   main  line 4      |
|    > jobs        | eve:> run sales_load.eve                         |                     |
|    > logs        | sql test> select region, sum(amount) from ...    |                     |
|  > machine prod  | +--------+---------+                             |                     |
|                  | | region | sum     |   3 rows, 4 ms              |                     |
+------------------+--------------------------------------------------+---------------------+
| dev1 localhost:4042  connected  |  Eve 0.6.0  |  Ln 4, Col 7  |  eve  |  LF  |  ana (SSO) |
+-------------------------------------------------------------------------------------------+
```

- **Menu bar** at the top; the name of the active machine at the right.
- **Explorer** at the left: the machines, their project folders, databases, jobs and logs as one tree (§7). A remote machine that is not logged in shows a lock; a click opens its login (§6).
- **Editor** in the center, with tabs (§8).
- **Bottom panel** with tabs: Command, Output, Results, Problems, Log (§9, §10).
- **Debug side bar** at the right, visible while debugging: Variables, Watch, Call stack, Breakpoints (§11).
- **Status bar**: machine and connection, version of the machine, cursor, language of the tab, line ending, the user on the active machine and how they logged in.
- Panels are resized by dragging their borders; the layout and the open tabs are kept per user.
- One dark theme and one light theme, chosen in View; colors are CSS custom properties (`--ux-bg`, `--ux-keyword`, ...), so a theme is one small CSS file.

### 5.1 Menus

| Menu | Items |
|---|---|
| File | New file, Open (file dialog), Open recent, Save, Save as, Save all, Upload to machine, Import data, Close tab |
| Edit | Undo, Redo, Cut, Copy, Paste, Find, Replace, Go to line, Toggle comment, Format (later, with F-TLS-08) |
| View | Explorer, Command, Output, Results, Log, Debug side bar, Theme, Font size, Reset layout |
| Run | Check (`check`), Run (`run`), Run with arguments, Stop (`stop`), Load driver (`load`), Dismiss (`dismiss`), Generate docs (`doc`) |
| Debug | Start debugging (`debug`), Step into, Step over, Step out, Continue (`resume`), Stop, Toggle breakpoint, Add watch, Report (`report`) |
| Database | New SQL tab, Connect, Refresh tree, Describe table, Export result, Import file into table |
| Jobs | Job browser, New job, Run now, Build history, Scheduler calendar, Log inspector |
| Machines | Add machine, Log in, Log out, Forget credentials, Test connection |
| Admin | Users, Roles, Registration, Sessions, Audit log of the active machine (visible to its admins only) |
| Help | Help topics, Keyboard shortcuts, Eve tutorial (link), Report an issue, About |

Every item also has a keyboard shortcut (F5 run, F9 breakpoint, F10 step over, F11 step into, Shift+F11 step out, Ctrl+Enter run the SQL under the cursor, Ctrl+` command window) and a command name, so the menu, the shortcuts and a command palette (Ctrl+Shift+P) share one table, `js/actions.js`.

## 6. Login, single sign-on and users

People log in to **machines**, not to the Workbench: users, passwords and roles belong to each remote machine, and the local machine keeps one login per remote machine (design-service.md §15). The Workbench is the screen of these logins.

### 6.1 Opening the Workbench

`eve --setup eveux --serve` starts the local machine with the Workbench on `http://localhost:8042/` and opens the browser with a **one-time link** (`/?key=…`) that the machine prints on its console. The key becomes a session cookie; another program or another user of the same computer that does not hold the key can't use the Workbench (question 5). The local machine is the user's own: no password is asked for it.

### 6.2 Login form of a remote machine

The first time a remote machine is opened, the login form asks for:

- **Single sign-on** (a button, "Sign in with <provider>"), when the machine trusts an identity provider: the local machine opens the page of the provider in the browser, the person signs in there (with the provider's own second factor), and the remote machine receives a proof of identity, never the password;
- or **user name and password of the machine**, for a machine without single sign-on;
- **Remember on this computer**: the credentials the remote machine gave back are kept in the keyring of the operating system (Windows Credential Manager, the Secret Service of Linux), so the next time the connection opens without a form.

**Log out** ends the session on the remote machine and deletes the credentials from the keyring; **Forget credentials** only deletes them from the keyring. Five failed logins lock the account on that machine for 15 minutes; the message never says whether the user exists.

### 6.3 Registration

Each remote machine chooses how people get an account (`$EVE_REGISTRATION` in its configuration):

| Setting | Effect |
|---|---|
| `closed` (default) | only an admin of the machine creates accounts |
| `approval` | a first login by single sign-on, or the form "Create an account", makes an account that waits until an admin approves it and gives it a role |
| `open` | a first login by single sign-on makes an account with the role `viewer` |

### 6.4 The first admin

The first admin of a machine is made on that machine's own console, when it is set up: `eve --setup <folder>` asks for the first admin's name, and, with single sign-on, the identity at the provider that becomes admin. Nothing else can create the first admin. `eve --reset-admin` (console only) does it again when the admin is lost.

### 6.5 Roles

| Right | viewer | operator | developer | admin |
|---|---|---|---|---|
| read files, logs, job history, database tree | yes | yes | yes | yes |
| run SQL `select` | yes | yes | yes | yes |
| run jobs now, stop a run, resume from a checkpoint | | yes | yes | yes |
| edit and save files, upload, import data | | | yes | yes |
| run and debug scripts, change data with SQL, edit jobs and schedules | | | yes | yes |
| manage users, roles, registration and sessions of the machine | | | | yes |

Roles are kept by each machine, so a person can be developer on `dev1` and viewer on `prod`. With single sign-on a machine may give roles from the groups of the provider (`group "etl-dev" is developer`). The Workbench hides what the role does not allow, and the machine refuses it anyway.

### 6.6 Admin pages

For the active machine, to its admins: users (list, create, disable, reset password, role), registration setting, sessions (who is logged in, end a session), audit log (logins, failed logins, role changes, runs, SQL that changed data, uploads). Each page is a set of machine commands (`user add`, `user role`, `session end`, ...), so an admin can do the same with `eve -c … -rem prod`.

## 7. Explorer: machines, files and the database object tree

The tree is loaded lazily: a node asks the machine for its children when it is opened.

```
machine dev1 (localhost:4042)
  project            the machine folder: eve.cfg, *.eve, asp/, lib/, web/, data/, out/
  databases
    eve              the Eve database of the machine (SQLite)
      tables
        orders       columns with Eve types, keys, indexes
      views
      checkpoints    eve_checkpoint
      run history
    test             evedb://localhost:8044/eve_test
      schemas > main > tables > ...
  jobs               the schedule of the machine (section 10)
  logs               out/run_*.log
machine prod (etl1.example.com:4042)   logged in as ana (single sign-on)
machine etl2 (etl2.example.com:4042)   locked: log in
```

- A table node shows its columns **in Eve types** (`Integer`, `Decimal`, `Instant`; the mapping check of design-database-core.md §5), its keys and indexes, and its row count on demand.
- Context menu of a table: Select first 100 rows, Count, Describe, Generate the Eve record class, Generate `insert`/`update` SQL, Import file into table, Export to CSV/JSON. Context menu of a file: Open, Run, Debug, Check, Upload to another machine, Rename, Delete (with confirmation).
- The tree uses only what a machine already offers for its connections (names from its `eve.cfg`, never a password).

## 8. Editor and syntax colors

### 8.1 The editor

A plain-JavaScript editor, `js/editor/`, made of a `<textarea>` that holds the text and the cursor, laid exactly over a `<pre>` that shows the colored text; the browser does the typing, selection, undo and accessibility, the editor does the colors. This is the smallest editor that works without a library.

- line numbers in a gutter; a click on the gutter sets a breakpoint (§11);
- tabs of files, a dot on a changed tab, Ctrl+S saves to the machine;
- find and replace with regular expressions, go to line, toggle comment with the comment mark of the language;
- indentation with two spaces for Eve, as in the tutorial; LF kept, CRLF shown in the status bar;
- the errors of `check` underlined in red, listed in Problems; a click goes to the line;
- only the visible lines are colored again after a change, so a file of 10,000 lines stays fluid.

### 8.2 Colorizer

One tokenizer engine, `js/editor/highlight.js`, driven by a **table per language**: a list of rules (regular expression → token class) and states for multi-line tokens. The output is `<span class="tk-keyword">` and so on; the colors come from the theme.

| Language | File | Notes |
|---|---|---|
| Eve | `lang/eve.js` | keywords, types and operators from `spec/lexical/keywords.json`, generated by `script/genkeywords.py` like the tutorial highlighter `eve1.js`; comments `#`/`##` at column 0, `**`, `(** **)`, `/* */`; strings, placeholders `{…}` inside strings, regex literals, `$` variables, `@` parameters |
| SQL | `lang/sql.js` | keywords of SQL:2016 and of SQLite, PostgreSQL and DuckDB; `--` and `/* */` comments; strings, quoted identifiers, numbers, `?` and `:name` parameters |
| JSON | `lang/json.js` | keys and string values in different colors, numbers, `true`/`false`/`null`; errors marked |
| XML | `lang/xml.js` | tags, attributes, values, comments, CDATA, processing instructions, entities |
| HTML | `lang/html.js` | the XML rules plus `<script>` and `<style>` blocks, void elements |

The language of a tab comes from the file extension (`.eve`, `.sql`, `.json`, `.xml`, `.html`/`.htm`, `.cfg` as Eve); the status bar can change it. The same colorizer colors the command window and the code shown in the log inspector.

## 9. Command window and direct SQL

The **Command** tab is a console with history (Up/Down), completion of command names and file names (Tab, as the REPL), and two modes:

| Prompt | Mode | What a line does |
|---|---|---|
| `eve:>` | machine | sent as one command to the active machine (`run sales.eve`, `load`, `status`, `send prod "report"`); the answer is printed |
| `sql test>` | SQL | sent as SQL to the connection `test` of the active machine; `sql <connection>` enters the mode, `exit` leaves it |

- A script from the command line: `run sales_load.eve --region EU`, the arguments as on `eve -x`; the output streams into the console while it runs, and Ctrl+C sends `stop`.
- **Direct SQL, WYSIWYG.** The answer of a `select` opens in the **Results** tab as a grid, the way it will look in a report: column names with their Eve types, numbers aligned right, `null` in grey, dates in ISO form, long text cut with a tooltip. The grid sorts and filters, pages through large results (the first 1,000 rows, then more on demand), copies cells as tab-separated text, and exports CSV, JSON or an Eve `DataSet` literal. A statement that changes data answers with the number of rows; with the role developer it runs inside a transaction and the Results tab shows **Commit** and **Rollback** buttons, so nothing changes by accident (question 7).
- In an SQL editor tab, Ctrl+Enter runs the statement under the cursor and Ctrl+Shift+Enter runs the whole file; several results open as several result tabs.

## 10. Jobs: scheduler and browser

The job browser shows the **remote scheduler** of a machine (design-service.md §11) and the runs of its drivers. Jenkins has jobs, builds, console output and a stage view; eveux maps them onto Eve:

| Jenkins | Eve Workbench |
|---|---|
| job | a driver with a schedule and parameters (`schedule "sales_load" at "02:00" every day`) |
| build | a run of the driver, numbered, with its run log `run_<driver>_<datetime>.log` (D-081) |
| stage view | the **aspects** applied by the driver, as columns, with the time and the result of each, per run |
| console output | the run log, streamed live while the run goes on |
| build status ball | exit code: green 0, yellow finished with warnings, red an error code (D-081), grey stopped |
| rebuild | Run again with the same parameters |
| (none) | **Resume from checkpoint**: a failed job of the database layer restarts from its last committed checkpoint, not from the start |
| (none) | the Eve error class and code of a failure, linked to its meaning in the exceptions table |
| (none) | rows read, written and rejected per aspect, from the lineage of the database layer |
| (none) | one dashboard for the jobs of **all** the machines the user is logged in to |

### 10.1 Pages

- **Dashboard**: every job of every connected machine with its last status, last success, last failure, last duration, next run, a weather icon for the last five runs, and buttons Run now and Disable.
- **Job page**: description, schedule, parameters, retry policy (`retry 3 after 5min`), alert (mail or webhook, later), the stage view of the last 20 runs, the trend of durations.
- **Run page**: live log, stage view of this run, the parameters, who started it (schedule or user), the exit code, the checkpoints, Stop, Resume from checkpoint, Download log.
- **Calendar**: the schedule of all jobs on a day or a week, to see when two heavy loads collide.
- **New job / edit job**: a form that writes the `schedule` lines of the machine configuration, then sends `setup` so the machine applies it without a restart (D-083).

### 10.2 Log inspector

The **Log** tab and the Log inspector page read the run logs of `out/` and the log of the machine:

- a list of log files with driver, date, size, exit code; filter by driver, date and status;
- a viewer that loads big files by parts (the first and last 1,000 lines, then on scroll) and follows a growing file (tail);
- levels in colors (info, warning, error), a filter by level and by text or regular expression;
- an error line `file:line: error <code>: message` becomes two links: the source line, opened in the editor, and the meaning of the code;
- Eve code and SQL quoted in a log are colored by the colorizer;
- two runs of the same job side by side, to see what changed between a good run and a bad one.

## 11. Debugger, variable inspector and watch window

The debugger of the Workbench is a face of the debugger of the machine (F-TLS-04, `manual/usage.md`): `debug`, `begin`, `enter`, `resume`, `print`, `report`, `stop`, and `halt` in the code. The Workbench adds what a screen makes easy:

| Action | Machine command | Notes |
|---|---|---|
| Start debugging (F5 on a debug tab) | `debug <file>` | debug mode, stops at the first breakpoint or `halt` |
| Step from the start | `begin <file>` | stops before the first statement of `process main` |
| Step over (F10) | `enter` | the next statement of the same subprogram |
| Step into (F11) | `step into` (new) | enters the function, procedure or method called on the line |
| Step out (Shift+F11) | `step out` (new) | runs to the end of the current subprogram |
| Continue (F8) | `resume` | to the next breakpoint or `halt` |
| Toggle breakpoint (F9, gutter click) | `break <file>:<line> [if <condition>]` (new) | a breakpoint that is not written in the file, unlike `halt` |
| Variables | `print`, `locals` (new) | globals of the DMS and locals of the selected frame; records, lists and maps open as trees; long lists in pages of 100 |
| Watch | `print <expression>` | each watch expression is evaluated at every stop; a changed value is highlighted |
| Call stack | `stack` (new) | the frames, with file and line; a click selects the frame for Variables |
| Report | `report` | the debugging report of the machine, in a tab |

- The current line is highlighted in the editor; the tab of the file opens by itself when the program stops in another file (a module or an aspect).
- A value can be changed while stopped (`let` typed in the command window, in debug mode only, question 8).
- Breakpoints are kept per user and per file, and sent again when a debug run starts.
- Parallel aspects (level 4): the call stack shows one entry per task; stepping one task holds the others (question 9).
- Debug mode exists on the local machine; a remote machine refuses it unless its configuration allows it (design-service.md §10). The Debug menu is greyed with the reason.

The new commands (`step into`, `step out`, `break`, `locals`, `stack`) belong to the machine, not to the Workbench, so that the REPL and `eve -c` get them too. They are proposals for the author (Q-047).

## 12. Files: open, upload and import

The **file dialog** is a modal window with two sources:

1. **On a machine**: a tree of the folders the machine allows (the project folder and its `data/`, `out/`, `web/`), a list of files with size and date, a filter by type (`.eve`, `.sql`, `.json`, `.xml`, `.html`, `.csv`, all), a path field, and New folder. Open puts the file into an editor tab.
2. **From this computer**: a drop zone and a Browse button (`<input type="file">`); the files are uploaded into the chosen folder (`-u` upload of D-083 for `.eve` files, a plain file copy for data).

**Import data** is a wizard on top of the dialog: choose a CSV or JSON file, see the first 20 rows, choose the target connection and table (new or existing), map the columns and their Eve types (guessed from the data, changeable), choose the mode (`append`, `replace`, `upsert` with a key, as `load!` of the database layer), and run. The import is a run of the machine and appears in the job history with its log.

## 13. Help and About

- **Help** opens a side window with the help topics of the Workbench (one Markdown file per topic in `web/help/`, shown as HTML), the keyboard shortcuts, and links to the Eve tutorial and to `manual/`. F1 in the editor opens the tutorial page of the keyword under the cursor.
- **About** is a dialog with the Eve logo and the versions:

```
Eve RAD Workbench    eveux 0.1.0   (on Eve 0.6.0, the local machine)
Machine prod         Eve 0.6.0     (answer of the command "version")
Databases            SQLite 3.54.0, evedb 0.2 / DuckDB 1.5.6
Browser              Firefox 140
(c) 2026 Sage-Code Laboratory, Elucian Moise.  License: BUSL
```

The version of eveux is a constant of its project; the version of each machine is asked when it connects.

## 14. The service in Eve

The browser talks only to the local machine; the local machine talks to the remote ones. The API is one `service` script with its routes (design-service.md §8); the work of each group of routes is an aspect. A sketch, with the syntax of the tutorial page Server:

```eve
# eveux API
service eveux_api is
  from "lib" use (machines, grid);

  route command(req: Request, @res: Response) on post "/api/machines/{m}/command" is
    new answer := machines.send!(req.params["m"], req.json()["command"]);
    let res.body := answer.json();
  end command;

  route post "/api/machines/{m}/sql" apply run_sql;
  route get "/api/machines/{m}/jobs" apply list_jobs;
  route post "/api/machines/{m}/login" apply login;

  initialize
    machines.open($EVE_HOME);
end eveux_api;
```

| Method and path | Does |
|---|---|
| `GET /api/me` | the logins of this browser session: machine, user, role, how they logged in |
| `GET /api/machines`, `POST /api/machines/{m}/login`, `POST /api/machines/{m}/logout` | the machines of the configuration; login (form or single sign-on), logout |
| `GET /api/machines/{m}/files?path=`, `GET`/`PUT`/`DELETE /api/machines/{m}/file?path=` | browse, read, save, delete |
| `POST /api/machines/{m}/upload` | multipart upload |
| `POST /api/machines/{m}/command` | one machine command, its answer and exit status |
| `POST /api/machines/{m}/sql` | one statement on a connection; a result set with Eve types, paged |
| `GET /api/machines/{m}/db/{conn}/tree?node=` | children of a node of the object tree |
| `GET`/`POST /api/machines/{m}/jobs`, `GET /api/machines/{m}/jobs/{job}/runs` | jobs and their runs |
| `GET /api/machines/{m}/logs/{file}?from=` | a part of a log |
| `GET`/`POST /api/machines/{m}/users`, ... | admin of a machine |
| `GET /api/about` | versions |
| `GET /ws` | one WebSocket per tab: live run output, log tail, debugger events (`stopped`, `continued`, `output`, `ended`), job status changes |

Every request that changes something carries the CSRF token of the session in a header; the WebSocket checks the session cookie and the origin at the upgrade.

## 15. Security

- **Local only.** The local machine serves the Workbench on `localhost`; the one-time key of §6.1 keeps other users of the same computer out. The Workbench is not meant to be opened to a network: a team shares remote machines, not a Workbench.
- **Credentials.** Kept by the local machine in the keyring of the operating system, never in a file of the project, never sent to the browser (design-service.md §15). The browser holds only its session cookie.
- **Sessions** of the browser: a random 256-bit id in a cookie `HttpOnly; SameSite=Strict`, ended when the local machine stops.
- **CSRF** token per session; **CSP** `default-src 'self'` with no inline script or style (the reason the JavaScript has no inline handlers).
- **Escaping.** Every value from a machine, a file or a database is inserted as text (`textContent`), never as HTML; pages made on the server are `HTML` values of templates (F-WEB-01); the colorizer escapes before it wraps tokens.
- **Rights.** The roles of §6.5 are checked by the remote machine; the audit log is the machine's.

## 16. Inside

eveux is a machine folder, so the local machine runs it as any other Eve project:

```
code/eveux/
  README.md            this design
  eve.cfg              the configuration of the local machine that runs the Workbench: serve, the remote machines by name
  eveux_api.eve        the service script: the routes of section 14
  asp/                 one aspect per group of routes: files, sql, tree, jobs, logs, debug, machines, users, about
  lib/                 modules: machines (connections, login), grid (result pages), streams (WebSocket), colors (keyword lists)
  web/
    index.html         the only page; an HTML template when F-WEB-01 exists
    css/               eveux.css (layout), theme-dark.css, theme-light.css, tokens.css (colors of the tokens)
    js/
      app.js           start, session, layout
      api.js           fetch wrapper (CSRF, errors), WebSocket client
      actions.js       one table: menu items, shortcuts, palette
      menu.js, dialog.js, splitter.js, tabs.js, tree.js, grid.js
      editor/          editor.js, highlight.js, lang/eve.js, sql.js, json.js, xml.js, html.js
      panels/          explorer.js, command.js, results.js, problems.js, log.js, debug.js, watch.js
      pages/           login.js, register.js, admin.js, jobs.js, run.js, filedialog.js, import.js, help.js, about.js
    help/              Markdown help topics
    img/               eve-logo.svg, icons (SVG)
test/level7/           the tests of eveux (prefix g): its API driven by Eve scripts with the HTTP client, a local and two remote machines on localhost
test/bmark/            p7a_eveux.eve: the stress run of section 2, with its twin
```

- **Language and rules.** The server part is Eve only: no Zig, no Python in `code/eveux/`. The JavaScript is ES2022 modules with JSDoc types, so an editor can check it, with no compile step; the CSS uses custom properties, grid and flexbox, no preprocessor.
- **Browsers.** The last two versions of Firefox, Chrome, Edge and Safari.
- **Size goal.** The web part under 300 KB before compression.

## 17. Versions

eveux is built during Version 0.6 (level 7). Its parts can start as soon as the features they need pass their tests, and each part is a test of those features:

| eveux | Needs | Content |
|---|---|---|
| 0.1 | level 6: `serve`, routes, connections, login | the screen, menus, editor with the five colorizers, file dialog and upload, command window, login with single sign-on and the keyring, Help and About (F-TLS-19) |
| 0.2 | level 5: database layer | direct SQL with the result grid, database object tree, import wizard (F-TLS-20) |
| 0.3 | level 6: remote scheduler, watched runs | job browser, scheduler forms, live run output, log inspector, admin pages (F-TLS-21) |
| 0.4 | F-TLS-04, the debugger commands | debugger: breakpoints, stepping, variables, watch, call stack (F-TLS-22) |
| 1.0 | level 7 | every test of `test/level7` passes and the stress goals of section 2 are met: the exit of Version 0.6 |

## Questions for the author

Answered on 2026-10-10 (D-154, D-155): eveux is written in Eve, as the final test and stress test of the language, in level 7; Zig only for `evevm`, which handles many remote machines from one local machine, with a login per machine, single sign-on and the keyring of the operating system. Questions 1 (a separate Zig program), 4 (a Zig web toolkit) and 9 (port 8046) of the first draft fall away: the Workbench is an Eve project on the `serve` port of the local machine.

1. **Browser part.** Plain JavaScript and CSS in the browser (proposed, as in the request), or parts written in Eve and run by the VM in WebAssembly (F-WEB-02), for example the colorizer?
**Answer:**
2. **JavaScript or TypeScript.** Plain JavaScript modules with JSDoc types and no build step (proposed), or TypeScript compiled by `tsc` (a build step and Node.js on the developer's computer)?
**Answer:**
3. **WebSocket.** Live output needs a push channel to the browser: WebSocket in `serve` (proposed), or Server-Sent Events (simpler, one direction)? *(2026-10-16: the machine already pushes `vm.output` notifications on its lasting doors; WebSocket would carry the same messages both ways, which SSE cannot: `vm.cancel` while a run streams.)*
**Answer:**
4. **Watched runs.** A run started from the Workbench streams its output, log and debugger events: on the line protocol of the command port first (proposed), or only with EWP (F-NET-03)?
**Answer:**
5. **Opening the Workbench.** A one-time key printed by the local machine (proposed, as Jupyter does), or the identity of the user of the operating system?
**Answer:**
6. **File commands of the machine.** `files`, `read`, `save`, `delete` on the machine folder as new machine commands (proposed, so `eve -c` has them too)?
**Answer:**
7. **SQL that changes data.** Inside a transaction with Commit and Rollback buttons (proposed), or auto-commit as in most SQL consoles?
**Answer:**
8. **Change a variable while debugging.** Allowed with `let` in debug mode (proposed), or read-only inspection?
**Answer:**
9. **Debugging parallel aspects.** Step one task and hold the others (proposed), or let the others run?
**Answer:**
10. **Name.** "Eve RAD Workbench" for the product, `eveux` for the folder: confirm, or another name?
**Answer:**
