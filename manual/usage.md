# Using the Eve virtual machine

How to run Eve scripts with the Eve virtual machine (`bin/eve.exe`, source in `evevm/`). The language rules
are in [`spec/`](../spec/README.md); this page covers the tool only. Status: **skeleton**, only the first
mode exists (D-031).

## Modes

| Mode | Command | Version |
|---|---|---|
| Run a script | `eve script.eve` | 0.1 |
| Console REPL | `eve` | planned, about 0.9 |
| Daemon (service) | `eve` with parameters | planned, about 0.9 |

Eve 0.1 only runs one driver script. The same program serves all modes, depending on how it is called.

## Console REPL (planned)

The REPL (read, execute, print, loop) has a menu and a command line. It parses, debugs and executes a
script. It is meant to work with the `eve` command on Linux, Windows and macOS. A configuration file is given
with `-c`, and the memory for the process with `-m`.

```
~/eve -c file.cfg
eve:> parse ~/path/driver_name.eve
eve:> debug ~/path/driver_name.eve -c file.cfg
eve:> execute ~/path/driver_name.eve -c file.cfg -m 2048GB
```

The command options are not designed yet. The basic commands are:

| Command | Description |
|---|---|
| `parse` | check the syntax and compile a script in memory, do not execute it |
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
| `quit` | stop the machine and exit from the REPL |

`halt` inside a script stops it so it can be debugged later. It works only in debug mode, and it can be
conditioned with `if` to make a breakpoint. Remove `halt` statements from mature software.

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
| 70 | not implemented (the stub VM, outside the Eve range) |
