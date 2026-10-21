# eve: the command

Code: [`code/eve/`](../../../code/eve/). This folder holds the design, the notes and the user documents of the component; the code folder holds only code.

The only place that imports every module (design/design-packages.md §3). Nothing else lives here.

| File | Holds |
|---|---|
| `eve.zig` | the entry point: the name the program was started with, the options, the choice between the REPL, a script, the machine and the commands; it starts `evetx` for `-tx` |
| `cli.zig` | the command table, dispatch and the REPL loop (the commands of the REPL are also command-line options) |
| `options.zig` | the command line: the options, the part words `vm`, `cp`, `db`, `ux`, `tx` (D-163, D-172), the command words |
| `context.zig` | the shared types (`Context`, `Handler`, `Command`) and the exit codes |
| `vm_cmds.zig`, `cp_cmds.zig`, `db_cmds.zig`, `ui_cmds.zig` | the commands of each part: the runtime, the compiler, the database, the REPL itself |
| `help.zig` | the help pages of `eve -h` and of `help` |

Build from the repository root: `zig build -p .`.
