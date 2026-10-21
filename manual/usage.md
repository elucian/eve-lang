# Using the Eve virtual machine

How to run Eve scripts with the Eve virtual machine (`bin/eve.exe`). The language rules are in the pages of the levels and the reference pages of this manual; this page covers the tool only. Status: **first execution**: the command line, the REPL, `check`, `execute` (a tree-walking interpreter), the slot of command files and the workflow commands work; `compile`, `debug`, `begin`, `enter`, `print`, `resume`, `stop`, `clear` and `setup` still echo "not yet implemented".

## Command line

```
eve [options]                      start the REPL
eve [options] <script.eve> [args]  execute a script (same as -x)
eve [options] --<command> [args]   run one command and exit, without the REPL
```

| Option | Description |
|---|---|
| `-h`, `--help` | display the help and exit: page 1 is the quick help (options), then `-- press enter for more --` and page 2 lists the `--<command>` options; both pages start with the title `EVE - Version: <version>`. When the output is piped, both pages are written without waiting |
| `-v`, `--version` | display the title `EVE - Version: <version>` and exit; the version is written once, in the root `build.zig.zon` |
| `-e file.cfg`, `--setup file.cfg` | setup: load the configuration file (the same file the `setup` command loads), for a script, a command or a door |
| `-s [file.cfg]` | the **service**, and only that: the machine with no user interface, silent, both doors, log in `<runtime>/eve-<domain>-<ipc_port>.log` (Windows service, Linux daemon; see "The service" below). The file after it is the configuration of the service; with a script, a command or a door `-s` is a usage error (exit 64) |
| `-m size` | memory for the process |
| `--engine tree\|bc` | the engine that runs the script: the tree walker (default) or the bytecode machine (`bc`, also `EVE_ENGINE=bc`). The bytecode machine is under construction: it runs what it translates and leaves the rest to the tree walker; both give the same output |
| `-d` | debug mode: `halt` statements work (otherwise they are ignored) |
| `-x` | execute the script now, in this process: same as `--execute` (the script is parsed first, see below). It never looks for a machine (no IPC or HTTP lookup): the fast way to run a script |

Every REPL command below is also a command-line option, so a command can run without the interface: `eve --check script.eve`, `eve -d --execute script.eve -e file.cfg`. A bare `eve` starts the REPL with the prompt `eve:> ` (with a configuration file: `eve -e file.cfg`; `eve -s file.cfg` is the service); `quit` or `exit` (or the end of the input) ends it. At the prompt the **Tab** key completes the last word of the line with file names. A command that takes a file says which kind: `check`, `compile`, `debug` and `execute` complete `.eve` files, `setup` (and any word after `-e`, `--setup` or `-s`) completes `.cfg` files; other commands do not complete. `check examples` followed by Tab shows the first `.eve` file of that folder (sub-folders too, with a trailing `/`), and every further Tab shows the next one; after the last it starts again with the first. Any other key ends the cycle, so you can edit the name. The command name itself is not completed. Editing keys: Backspace, Enter, Ctrl-C (drops the line), Ctrl-D or Ctrl-Z on an empty line (ends the REPL). This works when `eve` runs in a real terminal (Windows Terminal, PowerShell, cmd, Linux, macOS); when the input is a pipe or a file, or in a Git Bash window (mintty, which hides the console from Windows programs), the line is read plainly and Tab is not available (use `winpty eve` there).

`--disasm file.eve` (also `eve cp disasm`) writes the bytecode of a script as a listing. Environment variables for the developer of the machine: `EVE_ENGINE=bc` (the bytecode machine), `EVE_BC_TRACE=1` (say why a program runs on the tree walker), `EVE_PROFILE=1` (a sampling profile on Windows), `EVE_MEMSTATS=1` and `EVE_GC_VERIFY=1` (the memory).

`--debug` is the command that runs a script in debug mode; `-d` is the flag that turns debug mode on for any command.

### Dry run: find syntax errors

`eve --check script.eve` reads and compiles the script in memory, reports every syntax error with file, line and column, and never executes it. It exits with 0 when the script parses and 65 when it does not. Editors and test tools use it as a dry run: a script with a syntax error exits 65 and nothing runs.

### Execute: parse first

`eve -x script.eve` (or `eve script.eve`, or `--execute`) always parses the script first, exactly as `--check` does. A syntax error is reported as `file:line:col: error: text`, the exit status is 65 and nothing runs. Only a correct script is executed: the parser builds the syntax tree and the interpreter walks it (`code/evevm/src/parser.zig`, `ast.zig`, `interp.zig`). The execution loop is the statement loop: before every statement the machine looks into the slot (see below). What the script prints goes to the standard output; errors that no `recover` handled go to the standard error as `file:line: error <code>: message`, and the exit status is the code of the error (see [Exit codes](#exit-codes)).

What the interpreter implements is the whole of level 1 of the language ([Tests](tests.md)): aspects (every program is a `primary aspect`, there is no free script), `let` and `set`, the operators, interpolation with formats, `if`, `while`, `loop`, `for`, `match`, ordinals, lists, arrays, matrices, slices and views, DataSets, HashMaps, Objects, functions, methods, classes with constructors, regular expressions, `expect`, `over`, `panic`, `raise`, `recover`, `finalize` and jobs with `retry` and `resume`. Rules chosen while writing it, to confirm, are in. Regular expressions are a small subset: literals, `.`, `^`, `$`, classes `[a-z]`, `\d \w \s`, the quantifiers `* + ?`, and `|` between whole alternatives (no groups).

### Documentation: doc

`eve --doc <folder | file.eve> [output folder]` writes one Markdown page, `<name>.md`, for each `.eve` file: the file given, or the files found directly in the folder. The output folder is `doc` by default and is created when it does not exist. A page holds the comment above the header of the script as its summary, then one section for each declaration, with the signature line as the title and the comment block right above it (`#`/`##` at column 0, `**`, `/* … */`). In the REPL the command is `doc lib doc`. The command reports one line per page, `doc: io.eve -> doc/io.md`. Exit status: 0, 64 when the path is missing, 66 when the file or folder can't be read. It replaces the separate tool `eved`; `zig build doc` in `code/evevm/` runs `eve --doc lib doc` to regenerate the library reference.

`eve --project init <folder>` makes a project, or completes an existing one (F-TLS-23): the folder, if absent, with `db`, `log`, `meta`, `data/in`, `data/out`, `test`, `asp`, `lib`, `src`, `doc` and `web`, the first driver `<name>.eve`, `eve.cfg`, `meta/project.json` and a `.gitignore`. It never overwrites: a file that exists is kept, so it can run on a project that has work in it and adds only what is missing. Outside a Git repository it also runs `git init`. `eve --project new <folder>` does the same but fails when the folder exists and is not empty. One line per file, `create` or `keep`. Exit status: 0, 64 for a bad command line, 73 when the folder can't be made or, for `new`, is not empty. In the REPL the command is `project init shop`.

## Session commands and the workflow

The machine has a few commands of its own, besides running a script. They work at the REPL prompt and, one line per message, through `vm.eval` on a lasting door of the machine (the IPC door or `eve --stdio`, see "The machine" below). The command files of earlier versions (`.vmc`, `eve -i file.vmc`, `-t`, "serve mode") are gone: a program that wants to drive the machine with a series of commands talks to it over the stdio door, in one process, with no file to poll.

| Command | Effect |
|---|---|
| `report` | print the state: `report: pc <line of the last statement>, <n> statements, running` (or `idle`) |
| `stop`, `quit`, `exit` | stop the machine: leave the running script before its end (the machine prints `<script>: stopped`) |
| `load <file>` | load a script, forgetting the previous one (reports `<name>: loaded`) |
| `parse [file]` | parse the loaded script (or load and parse `file`): `<name>: parse ok, <n> nodes`, or `file:line:col: error: text` |
| `run [file]` | execute the script; a script that was not parsed is parsed first, and a syntax error stops the run. With `capture on` it reports `<name>: run, exit <code>` and keeps the output in a file |
| `errors` | report the errors of the script: syntax error, raised errors, failed `expect` (also the ones `recover` handled) |
| `ast [depth]` | write the syntax tree, one node per line, to `<outdir>/<name>.ast` (default depth 64; deeper nodes show as `... n more`) |
| `inspect` | write the introspection report `<outdir>/<name>.inspect`: node counts by kind, depth, the declarations, the result of the run, the global variables and the variables of the last process with their type and value |
| `listen [word]`, `serve [word]` | open (`start`, the default), `stop`, `restart` or show (`status`) the IPC door and the HTTP door from the prompt, which stays: the doors run in threads of the REPL, so the next command can already talk to them (`listen serve` opens both in one machine). `quit` ends the doors with the REPL |
| `status` | show the state of the machine in one page: the version, the script (loaded, parsed, running or finished, errors), the folder of the reports, the configuration (`eve.cfg` loaded or the defaults), the ports of the two doors and, when a machine answers on them, what it is doing (idle, or the script it runs and for how long), its requests, its uptime and its parts. It also adds one line for the script to `<outdir>/summary.log` (`name`, `parse=ok/FAIL`, `run=<exit code>`, `steps=`, `errors=` separated by tabs), when a script is loaded. The probe of a door that nobody listens on can take about 2 seconds on Windows |
| `outdir <dir>` | set the folder of the report files (default `temp/output`); created when missing |
| `capture on` / `capture off` | keep what a script prints in `<outdir>/<name>.out` (the session) or write it to the standard output |
| `log <text>` | add a line of text to `summary.log` (a marker between scripts) |
| `clear` | forget the current script |
| `help` | list the commands |
| anything else | printed as `unknown command: <text>` and ignored |

Commands are lowercase. While a script runs, only `report`, `stop`, `quit` and `exit` are taken; another command answers `busy`. A line may end with an Eve comment (`report ** why`); a line that holds only a comment, or nothing, is ignored.

### Workflow: one machine, many scripts, then the reports

A client can run a series of scripts in **one machine**: it starts `eve --stdio`, opens a session (`vm.open`) and sends, for each script, the lines `load <script>`, `parse`, `run`, `errors`, `ast 6`, `inspect`, `status`, each as one `vm.eval`; then `vm.stop`. The reports stay in the folder: `<name>.out` (what the script printed), `.err` (errors), `.ast`, `.inspect`, and `summary.log` for the whole session. The test tools of the source tree run every level of tests this way.

The same is open to any program: start `eve --stdio` (or connect to the IPC door of a running machine), send `{"jsonrpc": "2.0", "id": 1, "method": "vm.open", "params": {"cwd": "…"}}`, then one `vm.eval` per line with the `session` it answered. One process serves the whole series, so a series of commands costs no start of `eve` per command.

Code: `code/evevm/src/vm.zig` (the session), `code/evevm/src/channel.zig` (`vm.eval`).

## Modes

| Mode | Command | Version |
|---|---|---|
| Run a script | `eve script.eve` | 0.1 |
| Console REPL | `eve` | scaffold (commands not implemented) |
| Dry run | `eve --check script.eve` | scaffold |
| Daemon (service) | `eve` with parameters | planned, about 0.9 |

Eve 0.1 only runs one primary aspect at a time (or an exclusive aspect, for testing it alone). The same program serves all modes, depending on how it is called.

## Console REPL (scaffold)

**The look of the prompt.** At a terminal `eve` starts with a banner (the logo, the version, the specification version) and the line `Ready. Type help (or ?) and Enter for commands.` The `help` command draws a table of two columns, the command and a short description, with a line between the commands; the description fits one row at the default width. `help <command>` (also `? <command>` and `<command> ?`) shows the page of one command: its syntax, a text, its options or sub-commands with their explanation, and examples. `?` is an ordinary key: type it and press Enter for the table, or type `? listen` or `listen ?` and Enter for one command. Tab completes file names. With a pipe or a file the banner, the colors and the box characters are left out (the table is drawn with `+`, `-` and `|`), so scripts that read the output see plain text.

**The width of the table and the texts** is 100 characters. Another width is set by the variable `EVE_WIDTH` of the environment (`EVE_WIDTH=80 eve`) or by `eve_width = 80` in `eve.cfg` (30 to 400); the environment wins. The table and the texts never go beyond the window: in a narrower window the descriptions wrap inside their column and the free text wraps at the window. When the window is resized, the table and the help pages already on the screen are drawn again for the new width; the output of scripts and commands is kept as it was written.

**The screen.** At a terminal the REPL uses the whole window (the alternate screen: when `eve` ends, the terminal shows what it showed before). The **upper part** holds the output of the commands and the scripts, and the log of the machine when `listen` or `serve` is open; it keeps its own scrollback of 50,000 lines. Under it, four rows never leave the window: a rule, the **command line**, a rule, and the **status bar**. Page Up and Page Down scroll the upper part by a page, the Up and Down arrows by a line (the wheel of the mouse sends the arrows in most terminals), Home goes to the top and End back to the end; typing or Enter also returns to the end, and while the view is back the right of the status bar says how many lines up it is. A line is never wrapped below 120 characters: a longer line is split at 120, a shorter one is shown whole, and a window narrower than the line cuts its end on the screen (the scrollback keeps all of it, so widen the window to at least 120 columns). The status bar says `Ready`; while a command runs it says `Running…` (blinking, drawn by the terminal) and the name of the command; when the command ends it says `Ready` and `last run: <command> <time>`. The `clear` command empties the upper part and keeps the bars. A pipe or a file gets none of this: plain lines, no colors.

**The font** belongs to the terminal, not to the program: `eve` writes UTF-8 text with box-drawing and block characters and cannot choose how the window draws them. Use a fixed-width font that has these characters, such as **DejaVu Sans Mono** (the monospaced DejaVu; the old bitmap font called `fixed` has no box or block characters). In Windows Terminal: Settings, Profiles, Appearance, Font face. In the classic Windows console: Properties, Font (only fonts that the console lists). On Linux and macOS: the profile of the terminal. On Windows `eve` switches the console output to UTF-8 and turns colors on while the prompt runs, and restores both when it ends.

The REPL (read, execute, print, loop) has a menu and a command line. It checks, debugs and executes a script. It is meant to work with the `eve` command on Linux, Windows and macOS. A configuration file is given with `-s`, and the memory for the process with `-m`.

```
~/eve
eve:> setup file.cfg
eve:> check ~/path/aspect_name.eve
eve:> debug ~/path/aspect_name.eve -e file.cfg
eve:> execute ~/path/aspect_name.eve -e file.cfg -m 2048GB
```

The command options are not designed yet. The basic commands are (in the code they are the entries of one jump table, `code/evevm/src/cli.zig`; an entry that is not written yet prints `<name> command, not yet implemented`):

| Command | Description |
|---|---|
| `check` | check the syntax and compile a script in memory, do not execute it |
| `doc` | write the Markdown documentation of a `.eve` file, or of the `.eve` files of a folder |
| `project` | `project init <folder>` (keeps existing files) or `project new <folder>` (fails on a non-empty folder): make a project with the standard layout |
| `compile` | compile a script to bytecode (not designed yet) |
| `debug` | execute the main process in debug mode |
| `execute` | execute the main process in production mode |
| `begin` | start the `main` process of the aspect that is run, step by step |
| `enter` | the enter key: execute the next step |
| `print` | display the value of a global variable, it can't print locals |
| `resume` | continue running until a `halt` statement is encountered |
| `report` | create a debugging report about the system state |
| `stop` | stop the run but do not clean the memory |
| `clear` | stop the run and clean the memory |
| `setup` | load the configuration file and set the `$` variables |
| `help` | display the menu |
| `shell <command>`, `!<command>` | run a command of the system in the current folder; the prompt stays in eve |
| `quit`, `exit` | stop the machine and exit from the REPL (back to the shell) |

`halt` inside a script stops it so it can be debugged later. It works only in debug mode (`-d` or the `debug` command), where it returns to the prompt and `resume` or `enter` continue; outside debug mode it is ignored, so a forgotten `halt` never blocks a production run. It can be conditioned with `if` to make a breakpoint. Remove `halt` statements from mature software.

Debugging ideas, not decided yet: `halt "label"` so the prompt shows which breakpoint was reached; `print` of locals while halted; `eve --check` in a commit hook to reject scripts with syntax errors.

In debug mode the configuration can be modified and reloaded with `setup`. The REPL must be in the "ready" state when the settings are reloaded, otherwise it reports an error.

## The machine: `--listen`, `--serve`, `-loc`, `-rem`

**One command, no prompt.** `eve <command> [args]` is the same as `eve --<command> [args]`: the command runs once and `eve` ends with its exit status, it does not start the prompt (`eve check a.eve`, `eve status`, `eve stop`, `eve project new sales`). A word that ends in `.eve` is a script and runs as before (`eve a.eve`). Only `eve` alone starts the prompt.

**The service: `eve -s`.** `eve -s [file.cfg]` starts the machine as a **service**: no prompt, nothing on the standard output, both doors open, the log in `<runtime>/eve-<domain>-<ipc_port>.log` and the pid in `<runtime>/eve-<domain>-<ipc_port>.pid`. From a console it starts the machine in a process of its own and ends silent with status 0 (`already running` and status 75 when one runs). Under the Windows Service Control Manager it is the service (`sc create eve binPath= "C:\eve\bin\eve.exe -s C:\eve\eve.cfg" start= auto`, then `sc start eve`). With `EVE_SERVICE=foreground` the process itself is the machine, for a container or a systemd unit of `Type=simple`; on Linux a unit of `Type=forking` with `PIDFile=` works with the plain form. To stop: `eve --serve stop`, `sc stop eve`, `SIGTERM`, `systemctl stop eve`. A word after `-s` that ends in `.cfg` is the configuration of the service; `-s` takes nothing else (a script, a command, `-x` or a door with `-s` is a usage error, exit 64), and a configuration for them is `-e file.cfg`.

**The machine in its own process: `evevm`.** `evevm` starts the machine with both doors (the same as `eve --listen --serve`) in a **new process** and returns to the prompt of the system at once; the machine goes on without a window. It waits until the IPC door answers and prints where the machine listens and where its log is (`<runtime>/eve-<domain>-<ipc_port>.log`; when the start fails, the last lines of the log are shown). `evevm stop`, `evevm restart` and `evevm status` work on that machine, `-e file.cfg` names another configuration, and a second `evevm` says `already running` (exit status 75). `evevm` is the same file as `eve`, installed under a second name by `zig build`.

**Stop: `stop` and `eve stop`.** `stop` closes the IPC door and the HTTP door **together** and tells every script that runs in the machine to stop at its next statement; the program does **not** exit, so at the prompt you can open the doors again with `listen` or `serve`. When this process has no door open, `stop` stops the machine of another process (the one `evevm` started), and that machine ends. `eve stop` from the system prompt does the same. With nothing to stop it says so (exit status 69).

**The user interfaces: `-ux` and `-tx`.** `eve -ux [folder]` (or `eve ux [folder]`; it was `-u`, then the web page) starts the native workbench, `eveux`, on a project folder and waits until it ends, exactly as `-tx` does for `evetx`; the rest of the line belongs to eveux. The web page of the machine is now `eve ux start` (also `stop`, `restart`, `status`: the HTTP door), and the browser is opened by hand (the old `-ux` opening of the page is TD-36). `eve -tx [folder]` (or `eve tx [folder]`) starts the terminal IDE, `evetx`, on a project folder (the current one by default) and waits until it ends; `evetx` and `eveux` are separate programs for now (`code/evetx/README.md`, `code/eveux/README.md`), found beside `eve` in `bin/` (build them from their folders with `zig build -p../..`, or `./run.sh tx` and `./run.sh ux`; eveux needs Developer Mode on Windows to fetch dvui); when one is missing, `eve` says so and exits with 69. **`eve --kill`** (or `eve kill`) stops every other program that runs from the same `bin/` folder (`eve`, `evevm`, `evetx`, `eveux`, `evedb`), so that a build can replace the files: Windows refuses to overwrite a running `.exe` (AccessDenied). The three `build.zig` files run the same script (`script/stop_eve.ps1`) before they install, so `zig build -p.` and `zig build -p../..` need no manual stop; the terminal that started the program is not touched, only the program ends.

An `eve` that stays active and answers requests is a **machine** (rules: the machine). It reads `domain`, `ipc_port` (4042), `http_port` (8042), `http_host`, `web` and `remote` from `eve.cfg` of the working folder, or from the file of `-s`.

| Option | Meaning |
|---|---|
| `--listen [start\|stop\|restart\|status]` | the IPC door (a Unix socket `<runtime>/eve-<domain>-<ipc_port>.sock`): start a machine with it (the default), or stop, restart or ask the machine through it only |
| `--serve [start\|stop\|restart\|status]` | the HTTP door: the files of the web folder and JSON-RPC in `POST /rpc`; `--listen --serve` opens both doors |
| `--serve stop`, `status`, `restart`, `start` | stop the machine, print its doors, the count of the scripts it ran, its requests, uptime and what it is doing now, stop and start again, start |
| `-loc [port]`, `--local` | local command, never the network: through IPC when a machine listens, otherwise run by this process |
| `-rem [host:port]`, `--remote` | run the command on the HTTP door of that machine (`remote` of `eve.cfg` without an address); fails when nobody answers |
| `--stdio` | a machine for the program that starts it: JSON-RPC on the standard input and output, one message per line; it ends at the end of its input or on `vm.stop`. evetx starts one; over SSH: `ssh host eve --stdio`. Its log goes to the error output when `EVE_LOG` is set |

The two doors have the same form, `--listen [word]` and `--serve [word]`; the ports come from `eve.cfg`. The client options have three letters (`-loc` local, `-rem` remote; `-ls`, `-lo`, `-r` until 2026-10-11 and `-lsn` until 2026-10-13 are unknown options now). Without `-loc` or `-rem`, `eve -x file.eve` never looks for a machine: it executes the script at once in its own process, even when a machine listens.

```
eve --listen --serve                    ** start: prints "eve: ipc localhost:4042" and "eve: http http://localhost:8042"
eve -loc -x report.eve                  ** run report.eve in the local machine (or by itself without one)
eve -rem 127.0.0.1:8042 -x report.eve   ** send report.eve as text to the HTTP door and run it there
eve --serve status
eve --serve stop
```

A script run in a machine prints into the answer: `eve` writes it on its standard output, the errors that nobody recovered on its error output, and ends with the exit code of the script.

**Commands of the system at the prompt.** `shell <command>` and `!<command>` run a command line in the shell of the system (`SHELL`, else `cmd.exe` on Windows), in the current folder, show its output while it comes, and come back to the prompt of eve: `!git status`, `!zig build -p .`. The command gets no input. `exit` (and `quit`) leave eve for the shell. The machine offers the same to IDEs: `vm.shell`, and `!<command>` in a session (`spec/library/machine.md#lasting-doors`).

## Daemon (planned)

The machine can run as a service. In service mode several primary aspects run in parallel; each one is independent, with its own scope, and can't communicate with the others.

## Exit codes

The aspect that is run captures the exit code of a process that ends with an error:

| Code | Cause |
|---|---|
| 0 | end of `process` or `over;` |
| 6 to 125 | `over n;` or `exit n;`: the exit code the script chose (1 to 5 belong to the machine) |
| 1 | `panic;` |
| 2 | failed `expect` |
| 3 | failed `assert` |
| 4 | `raise`, or an error of the script that no `recover` handled (index 0, missing key, division by zero, undefined name); the code of the error is in the message, never the exit code |
| 5 | unexpected stop: Ctrl+C; a `halt` breakpoint (debug mode only) that the user ends with Ctrl+C or `stop` instead of resuming; recursion too deep; out of memory; hard time-out |
| 64 | bad command line (unknown option, missing value) |
| 65 | `--check` found syntax errors, or `execute`/`run` refused a script that does not parse |
| 66 | the script file cannot be read |
| 69 | the machine: nobody answers (`-rem` with no machine at that address, `--serve status` or `stop` with no machine) |
| 75 | the machine: a running machine already holds a door of the new one (`already running`) |
| 70 | not implemented (the stub VM, outside the Eve range) |

**The debugger: `eve debug <file.eve>` (F-TLS-04).** The script runs under the debugger and stops before its first statement. The commands are read from the standard input, one per line: `run` (start, or go on until the next breakpoint), `halt` (stop the program at once; the run ends as stopped), `next` (execute the statement without going down into the calls), `step` (go into the call of the line), `exit` (finish the subprogram and stop in its caller), `trace` (go on automatically, writing each statement, until the next breakpoint), `break <line>` and `clear <line|all>`. The debugger writes lines that begin with `@debug` on the standard output, between the lines of the program: `@debug paused <line> <depth> <text>`, `@debug trace <line> <depth>`, `@debug break <n>`, `@debug end <status>`. Only the main task is debugged; the tasks of `parallel` and `spawn` run free. In `evetx` the toolbar buttons Run, Halt, Next, Step, Exit and Trace send these commands (keys F5, Shift+F5, F8, F11, Shift+F11, Shift+F8), the line where the program stopped has an arrow in the gutter, and the breakpoints of the gutter are sent to the debugger.

**The debugger, more (2026-10-15).** Each time `eve debug` stops it first writes the variables that the program can see: `@debug vars`, then one `@debug var name=value` line each (the names `$epsilon`, `_` and `jobs` and the functions are left out). `trace` is slow on purpose: it waits 400 ms after each statement. **`eve db sql <file|:memory:> <statement>`** runs SQL statements (separated by `;`) on a SQLite file and prints each result as a table (`ok, N changes` for a statement without rows); it is the tool of the SQL panel of `evetx`.

**Debugger: `delay <ms>`.** The debugger command `delay <ms>` sets the wait after each statement of `trace` (400 ms at first, at most 10000). In `evetx` it is the option Trace delay (Options > Timers), sent at the first stop.

**`eve db sql` options.** `eve db sql [-t] [--last] [-f <script>] <file|:memory:> [<statement>]`: `-t` writes the rows as text with a tab between the cells (a header line first), `--last` writes only the result of the last statement, `-f` reads statements from a file before the ones typed. Everything after `db` belongs to the command, so these options are not read as options of `eve`.
