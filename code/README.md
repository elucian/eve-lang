# code

The source code of the Eve implementation, one folder per component. The design, the state of the work and the user documents of each component are in [`design/components/`](../design/components/README.md) (more detail than here). The database drivers are separate projects in [`drivers/`](../drivers/README.md).

| Component | What it is | Built by |
|---|---|---|
| [eve](eve/) | the `eve` command: entry point, options, the commands of each part, the help pages; the only place that imports every module | root `build.zig` |
| [evecm](evecm/) | the common part: values and heap, decimals, time, Unicode, data codecs, configuration and wire of a machine, the editor parts that need no screen | root `build.zig` (module) |
| [evecp](evecp/) | the compiler front end: lexer, parser, static checks, project link, `check`, `doc`, `project init/new`; also a program of its own | root `build.zig` (module) and its own `build.zig` |
| [evevm](evevm/) | the runtime: interpreter, bytecode machine, tasks, native library modules, the machine (IPC, HTTP, stdio), REPL, database layer | root `build.zig` |
| [evetx](evetx/) | the terminal IDE on libvaxis | its own `build.zig` |
| [eveux](eveux/) | the native graphical workbench on dvui (early draft) | its own `build.zig` |
| evewp | the Eve Web Portal, written in Eve; design only, no code yet (`design/components/evewp/`) | not built |

## Structure of a component

Every component has the same shape. Nothing but code is here: the README, the design and the user documents are in `design/components/<component>/`.

```
code/<component>/
  src/            all the Zig source of the component (no .zig file at the root of the component)
  build.zig       only a component that is also built as a program of its own, with its own dependencies
  build.zig.zon     (evecp, evetx, eveux); the others are built by the root build.zig
  assets/         optional: data files that belong to the code (evetx: assets/themes/)
```

Tests are Zig `test` blocks next to the code they cover. Generated code carries a header that names its generator (`script/`); tools that write code live in `script/`, not here.

## License

All the components are under one license, the Business Source License 1.1: [LICENSE](LICENSE). The code becomes Apache License 2.0 on the Change Date written there.
