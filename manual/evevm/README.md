# evevm: the Eve virtual machine

`evevm` is the runtime of Eve: the part of `eve.exe` that runs Eve programs. It is a tree-walking interpreter written in Zig, with the standard library, the SQLite database engine and the machine (a long-running `eve` that answers requests) built in. The command line itself is described in [Using eve](../usage.md).

## The programs

| Program | What it is |
|---|---|
| `bin/eve.exe` | the `eve` command: runs a script, starts the REPL, runs one command, or becomes a machine |
| `bin/evevm.exe` | the same file under another name: started as `evevm`, it starts the machine in a new process (both doors open) and returns at once |
| `lib/` | the standard library written in Eve (`http`, `route`, `rpc`, `service`, `config`, `test`) and the signatures of the native modules (`lib/sys/`); `eve` finds it beside its own folder, at `<bin>/../lib` |

## Running a program

```
eve hello.eve              run a script (parsed first; a syntax error stops it with exit status 65)
eve --check hello.eve      find syntax errors without running anything
eve                        the REPL, prompt eve:>
eve -v                     the version
```

Every program is a `primary aspect`; it may apply aspects and import modules of its project. The exit status follows the conventions of [Using eve](../usage.md) (0 success, 64 usage error, 65 syntax error, and so on).

## The machine

An `eve` that stays active and answers requests is a **machine**. It has two doors: an **IPC door** (port 4042 by default) for the `eve` commands of the same computer, and an **HTTP door** (port 8042) for clients over the network. The ports, the domain and the web folder come from `eve.cfg` of the working folder, or from the file given with `-s` or `-e`.

| Command | Meaning |
|---|---|
| `eve --listen --serve` | a machine in this window, with both doors |
| `evevm` | a machine in its own process, without a window |
| `eve -s eve.cfg` | the machine as a service (Windows) or daemon (Linux): silent, a log file in the runtime folder |
| `eve status`, `eve stop` | ask the machine of this computer for its state, or stop it |
| `eve -c "<command>" -rem <machine>` | send one command to a remote machine |

The clients `evetx` (terminal) and `eveux` (window) talk to the machine through the same calls (`vm.*`, `db.*`); they never run Eve code themselves.

## Memory

Values are reference counted, and a tracing collector frees cycles. A started aspect has a heap of its own, which it frees while it runs and which goes whole when the task ends. These environment variables help to look inside and to steer a run:

| Variable | Effect |
|---|---|
| `EVE_MEMSTATS=1` | at the end, print what the heap made, freed and kept |
| `EVE_GC_VERIFY=1` | check every free against a trace (slow; for the developers of the machine) |
| `EVE_CORES=n` | the tasks of parallel groups that run at the same time, instead of `$cores` (the hardware cores, at most 16); `1` runs the tasks one at a time, in the order of `start` |

## Building

Requires Zig 0.17.0. From the root of the source tree: `./run.sh build` (or `zig build eve evevm -p .`) installs `bin/eve.exe`, `bin/evevm.exe` and `lib/`. `zig build -Doptimize=ReleaseSafe` is the build used for the measures of [Performance](../performance.md).

## Status and limits

Levels 1 to 5 of the language run (the language of one script, programs of several files, modules and classes, parallel work and generics, the data language and the database); level 6 (the machine and the server) is in progress. See [Features](../features.md) and [Tests](../tests.md). There is no compiler to native code yet: `eve` interprets the syntax tree.

## License

Business Source License 1.1 (the file `LICENSE` of the distribution). The code becomes Apache 2.0 on the Change Date written there.
