# cmd: the `eve` command

The only place that imports every module (plan/design-packages.md §3). Nothing else lives here.

| File | Holds |
|---|---|
| `eve.zig` | the entry point: the name the program was started with, the options, the choice between the REPL, a script, the machine and the commands; it connects the parts: `interp.data_api = &evedb.data` |
| `cli.zig` | the options and the command table (the commands of the REPL are also command-line options) |

Build from the repository root: `zig build -p .`.
