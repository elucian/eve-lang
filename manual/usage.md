# Using the Eve virtual machine

How to run Eve scripts with the Eve virtual machine (`bin/eve.exe`, source in `evevm/`). The language rules
are in [`spec/`](../spec/README.md); this page covers the tool only. Status: **first execution**: the command line, the REPL, `check`, `execute`
(a tree-walking interpreter that runs all of `test/level1/`), the slot of command files and the workflow commands
work; `compile`, `debug`, `begin`, `enter`, `print`, `resume`, `stop`, `clear` and `setup` still echo "not yet implemented" (D-031).

## Command line

```
eve [options]                      start the REPL
eve [options] <script.eve> [args]  execute a script (same as --execute)
eve [options] --<command> [args]   run one command and exit, without the REPL
```

| Option | Description |
|---|---|
| `-h`, `--help` | display the help and exit: page 1 is the quick help (options), then `-- press enter for more --` and page 2 lists the `--<command>` options; both pages start with the title `EVE - Version: <version>`. When the output is piped, both pages are written without waiting |
| `-v`, `--version` | display the title `EVE - Version: <version>` and exit; the version is hard-coded in `evevm/src/version.zig` |
| `-s file.cfg` | setup: load the configuration file (the same file the `setup` command loads) |
| `-m size` | memory for the process |
| `-d` | debug mode: `halt` statements work (otherwise they are ignored) |
| `-x` | execute the script: same as `--execute` (the script is parsed first, see below) |
| `-i file.vmc` | load a command file at startup: the machine interprets it from the first line and runs its commands in order (see [Command files](#command-files-vmc)) |
| `-t seconds` | serve mode only (`-x -i file.vmc` without a script): stop after this long without a command (default 30) |

Every REPL command below is also a command-line option, so a command can run without the interface:
`eve --check script.eve`, `eve -d --execute script.eve -s file.cfg`. A bare `eve` or `eve -s file.cfg`
starts the REPL with the prompt `eve:> `; `quit` or `exit` (or the end of the input) ends it.
At the prompt the **Tab** key completes the last word of the line with file names. A command that takes a
file says which kind: `check`, `compile`, `debug` and `execute` complete `.eve` files, `setup` (and any word
after `-s`) completes `.cfg` files; other commands do not complete. `check test/level1`
followed by Tab shows the first `.eve` file of that folder (sub-folders too, with a trailing `/`), and
every further Tab shows the next one; after the last it starts again with the first. Any other key ends the
cycle, so you can edit the name. The command name itself is not completed. Editing keys: Backspace, Enter,
Ctrl-C (drops the line), Ctrl-D or Ctrl-Z on an empty line (ends the REPL). This works when `eve` runs
in a real terminal (Windows Terminal, PowerShell, cmd, Linux, macOS); when the input is a pipe or a file,
or in a Git Bash window (mintty, which hides the console from Windows programs), the line is read plainly
and Tab is not available (use `winpty eve` there).

`--debug` is the command that runs a script in debug mode; `-d` is the flag that turns debug mode on
for any command.

### Dry run: find syntax errors

`eve --check script.eve` reads and compiles the script in memory, reports every syntax error with file,
line and column, and never executes it. It exits with 0 when the script parses and 65 when it does not.
The test runner uses it as a dry run over a whole test folder: `python script/runtest.py --check 1`
(a test whose `expect.json` entry has `"syntax_error": true` must exit 65).

### Execute: parse first

`eve -x script.eve` (or `eve script.eve`, or `--execute`) always parses the script first, exactly as
`--check` does. A syntax error is reported as `file:line:col: error: text`, the exit status is 65 and
nothing runs. Only a correct script is executed: the parser builds the syntax tree and the interpreter walks it
(`evevm/src/parser.zig`, `ast.zig`, `interp.zig`). The execution loop is the statement loop: before every
statement the machine looks into the slot (see below). What the script prints goes to the standard output;
errors that no `recover` handled go to the standard error as `file:line: error <code>: message`, and the exit status is
the code of the error (see [Exit codes](#exit-codes)).

What the interpreter implements is the whole of `test/level1/`: drivers and free scripts, `let` and `set`, the
operators, interpolation with formats, `if`, `while`, `loop`, `for`, `match`, ordinals, lists, arrays, matrices, slices
and views, DataSets, HashMaps, Objects, functions, methods, classes with constructors, regular expressions,
`expect`, `over`, `panic`, `raise`, `recover`, `finalize` and jobs with `retry` and `resume`. Rules chosen while
writing it, to confirm, are in D-063 (`plan/decision_level1.md`). Regular expressions are a small subset: literals, `.`,
`^`, `$`, classes `[a-z]`, `\d \w \s`, the quantifiers `* + ?`, and `|` between whole alternatives (no groups).

## Command files (`.vmc`)

A `.vmc` file (Virtual Machine Command) is a **script for the machine itself**, not for Eve: plain text, one
command per line, comments allowed. It is loaded at startup with `-i`:

```
eve -x -i level1.vmc               ** serve mode: no Eve script, the file is the program
eve -x script.eve -i control.vmc   ** run an Eve script; the file controls it
```

**Startup behavior.** `-i` names the file before anything else happens. As soon as the machine is ready it
starts interpreting the file: it runs the commands **in order, from the first line**, each one finishing
before the next begins (`load` before `parse` before `run`). Without an Eve script (serve mode) the file is the
whole program and the machine ends with its `stop`; if the file has no `stop`, the machine keeps waiting for
more lines until `-t` seconds (default 30) pass without a command, then it stops by itself with status 75. With an Eve
script on the command line, the script runs and the file is read between its statements (see the rules below).
The file is a **slot** as well: a batch file, a shell or a Python script can keep appending lines while the machine
works, and each new line is run when the machine reaches it. The file may not exist yet when the machine starts
(that means "no commands"). The machine remembers how far it has read, so a line is run once. Any program can write it: `echo report >> commands.vmc`, `Add-Content`, a Python
`open(..., "a")`. Only the end of the file may change: lines already read are not read again.

| Command | Effect |
|---|---|
| `report` | print the state: `report: pc <line of the last statement>, <n> statements, running` (or `idle`) |
| `stop`, `quit`, `exit` | stop the machine: leave the running script before its end (the machine prints `<script>: stopped by a command from the slot`) or end serve mode (`serve: stopped`) |
| `load <file>` | load a script, forgetting the previous one (reports `<name>: loaded`) |
| `parse [file]` | parse the loaded script (or load and parse `file`): `<name>: parse ok, <n> nodes`, or `file:line:col: error: text` |
| `run [file]` | execute the script; a script that was not parsed is parsed first, and a syntax error stops the run. With `capture on` it reports `<name>: run, exit <code>` and keeps the output in a file |
| `errors` | report the errors of the script: syntax error, raised errors, failed `expect` (also the ones `recover` handled) |
| `ast [depth]` | write the syntax tree, one node per line, to `<outdir>/<name>.ast` (default depth 64; deeper nodes show as `... n more`) |
| `inspect` | write the introspection report `<outdir>/<name>.inspect`: node counts by kind, depth, the declarations, the result of the run, the global variables and the variables of the last process with their type and value |
| `status` | add one line for the script to `<outdir>/summary.log`: `name`, `parse=ok/FAIL`, `run=<exit code>`, `steps=`, `errors=` separated by tabs |
| `outdir <dir>` | set the folder of the report files (default `temp/output`); created when missing |
| `capture on` / `capture off` | keep what a script prints in `<outdir>/<name>.out` (the session) or write it to the standard output |
| `log <text>` | add a line of text to `summary.log` (a marker between scripts) |
| `clear` | forget the current script |
| `help` | list the commands |
| anything else | printed as `slot: unknown command: <text>` and ignored |

Commands are lowercase. The same commands work at the REPL prompt (`load a.eve`, `parse`, `run`, `ast`, ...).
`print`, `resume`, `enter` and the other debugger commands of the REPL will join this table when the machine has state
to debug. While a script runs only `report`, `stop`, `quit` and `exit` (and comments, blank lines and unknown
words) are taken from the slot; any other command waits in the file, in order, until the script ends. A command is
never lost and never run in the middle of a script.

**Comments.** The marks are those of Eve itself:

```
# a line whose first character is # is a comment (leading blanks are allowed)
report ** from ** to the end of the line is a comment
** a whole line comment
                      (a blank line is ignored too)
```

A line that holds only a comment, or nothing, is ignored. `#` is a comment only at the start of a line
(`report # now` is an unknown command), because `**` is Eve's end-of-line comment. Windows line endings
(CRLF) are accepted.

**Writing safely.** A line counts only once it ends with a newline, so a program that is half way through
a line is never read half way: write the whole line with its newline in one operation. The file is read
whole at each look (limit 1 MB); keep it short, or start a new file for a new run. The extension `.vmc` belongs
to no operating system program: the file is read only by `eve -i`. At the REPL prompt Tab completes `.vmc` files after `-i`.

### Workflow: one machine, many scripts, then the reports

`eve -x -i level1.vmc` (execute with a slot and **no script**) is **serve mode**: the machine does not run
a script, it waits for commands and works through the file until `stop` (or until `-t` seconds pass without a
command). A command file can therefore drive the whole cycle for any number of files, one at a time:

```
# level1.vmc
outdir temp/workflow/level1       ** where the reports go
capture on                        ** keep the output of each script in a file
load test/level1/a03_print.eve
parse                             ** syntax errors are reported here
run                               ** execute the syntax tree
errors                            ** report what went wrong
ast 6                             ** introspection: the tree ...
inspect                           ** ... and what the script is made of, variables included
status                            ** one line in summary.log
load test/level1/a04_free_script.eve
...
stop                              ** the machine ends; the reports stay
```

After `stop` the machine is gone and the reports can be read: `<name>.out` (what the script printed), `.err`
(errors), `.ast`, `.inspect`, and `summary.log` for the whole session. `script/workflow.py` does the whole cycle for a
test level: it writes the command file, starts the machine once, waits for it to stop, compares each `.out` and exit
code with `expect.json`, and writes `<out>/<level>.report.md` that quotes the errors and the introspection of every
failing test: `python script/workflow.py 1` (reports in `temp/workflow/`). `python script/runtest.py` runs
one process per test instead; both must agree.

A level 2 test can run a session with the key `"serve"` in `expect.json`: the runner then starts
`eve -x -t 5 -i <command file>` (see `test/vm/v07`..`v11`).

Tests: `test/vm/v01`..`v11` (the command files are in `test/vm/slot/`). Code: `evevm/src/vm.zig`.

## Modes

| Mode | Command | Version |
|---|---|---|
| Run a script | `eve script.eve` | 0.1 |
| Console REPL | `eve` | scaffold (commands not implemented) |
| Dry run | `eve --check script.eve` | scaffold |
| Daemon (service) | `eve` with parameters | planned, about 0.9 |

Eve 0.1 only runs one driver script. The same program serves all modes, depending on how it is called.

## Console REPL (scaffold)

The REPL (read, execute, print, loop) has a menu and a command line. It checks, debugs and executes a
script. It is meant to work with the `eve` command on Linux, Windows and macOS. A configuration file is given
with `-s`, and the memory for the process with `-m`.

```
~/eve -s file.cfg
eve:> check ~/path/driver_name.eve
eve:> debug ~/path/driver_name.eve -s file.cfg
eve:> execute ~/path/driver_name.eve -s file.cfg -m 2048GB
```

The command options are not designed yet. The basic commands are (in the code they are the entries of one
jump table, `evevm/src/cli.zig`; an entry that is not written yet prints `<name> command, not yet implemented`):

| Command | Description |
|---|---|
| `check` | check the syntax and compile a script in memory, do not execute it |
| `compile` | compile a script to bytecode (not designed yet) |
| `debug` | execute the main process in debug mode |
| `execute` | execute the main process in production mode |
| `begin` | start the driver main process step by step execution |
| `enter` | the enter key: execute the next step |
| `print` | display the value of a global variable, it can't print locals |
| `resume` | continue running until a `halt` statement is encountered |
| `report` | create a debugging report about the system state |
| `stop` | stop the driver execution but do not clean the memory |
| `clear` | stop the driver and clean the memory |
| `setup` | load the configuration file and set the `$` variables |
| `help` | display the menu |
| `quit`, `exit` | stop the machine and exit from the REPL |

`halt` inside a script stops it so it can be debugged later. It works only in debug mode (`-d` or the
`debug` command), where it returns to the prompt and `resume` or `enter` continue; outside debug mode it is
ignored, so a forgotten `halt` never blocks a production run. It can be conditioned with `if` to make a
breakpoint. Remove `halt` statements from mature software.

Debugging ideas, not decided yet: `halt "label"` so the prompt shows which breakpoint was reached;
`print` of locals while halted; `eve --check` in a commit hook to reject scripts with syntax errors.

In debug mode the configuration can be modified and reloaded with `setup`. The REPL must be in the "ready"
state when the settings are reloaded, otherwise it reports an error.

## Daemon (planned)

The machine can run as a service. In service mode several drivers run in parallel; each driver is
independent, with its own scope, and can't communicate with the others.

## Exit codes

The driver captures the exit code of a process that ends with an error (D-010, D-038, D-052):

| Code | Cause |
|---|---|
| 0 | end of `process` or `over;` |
| 1 | `panic;` |
| 2 | failed `expect` |
| 3 | failed `assert` |
| 4 | `raise`, or an error of the script that no `recover` handled (index 0, missing key, division by zero, undefined name) |
| greater than 0 | `raise` with a code of its own (`raise (23, "message")`) |
| 64 | bad command line (unknown option, missing value) |
| 65 | `--check` found syntax errors, or `execute`/`run` refused a script that does not parse |
| 66 | the script file cannot be read |
| 70 | not implemented (the stub VM, outside the Eve range) |
