# Using the Eve virtual machine

How to run Eve scripts with the Eve virtual machine (`bin/eve.exe`, source in `evevm/`). The language rules
are in [`spec/`](../spec/README.md); this page covers the tool only. Status: **skeleton**: the command line,
the help and the REPL work; every command only echoes "not yet implemented" (D-031).

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
| greater than 0 | `raise` |
| 64 | bad command line (unknown option, missing value) |
| 65 | `--check` found syntax errors |
| 70 | not implemented (the stub VM, outside the Eve range) |
