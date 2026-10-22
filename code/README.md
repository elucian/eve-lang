# code

The source code of the Eve implementation, one folder per component. The design, the state of the work and the user documents of each component are in [`design/components/`](../design/components/README.md) (more detail than here). The database drivers are separate projects in [`drivers/`](../drivers/README.md).

| Component | What it is | Built by |
|---|---|---|
| [eve](eve/) | the `eve` command: entry point, options, the commands of each part, the help pages; the only place that imports every module | `build.zig`; the root `build.zig` forwards its steps here |
| [evecm](evecm/) | the common part: values and heap, decimals, time, Unicode, data codecs, configuration and wire of a machine, the editor parts that need no screen | package `evecm` |
| [evecp](evecp/) | the compiler front end: lexer, parser, static checks, project link, `check`, `doc`, `project init/new`; also a program of its own | package `evecp` (also a program) |
| [evevm](evevm/) | the runtime: interpreter, bytecode machine, tasks, native library modules, the machine (IPC, HTTP, stdio), REPL, database layer | package `evevm` |
| [evetx](evetx/) | the terminal IDE on libvaxis | its own `build.zig` |
| [eveux](eveux/) | the native graphical workbench on dvui (early draft) | its own `build.zig` |
| evewp | the Eve Web Portal, written in Eve; design only, no code yet (`design/components/evewp/`) | not built |

## Structure of a component

Every component has the same shape. Nothing but code is here: the README, the design and the user documents are in `design/components/<component>/`.

```
code/<component>/
  src/            all the Zig source of the component (no .zig file at the root of the component)
  build.zig       the package: it exposes the module of the component and runs its unit tests (`zig build test` here)
  build.zig.zon   the dependencies on other components
  assets/         optional: data files that belong to the code (evetx: assets/themes/)
```

Every component is a Zig package. `eve` (`code/eve/build.zig`) makes the command `eve` from the modules of `evecm`, `evecp` and `evevm` and is the only package listed in the root `build.zig.zon`; the root `build.zig` forwards its steps (`install`, `run`, `doc`, `eve`, `evevm`, `test`) to it, so `zig build -p .` from the root and `zig build -p ../..` from `code/eve/` do the same. The arrows between the components are their `build.zig.zon` files. `evecp`, `evetx` and `eveux` also build a program of their own. `evetx` and `eveux` still take `evecm` by path (backlog `TD-61`). Tests are Zig `test` blocks next to the code they cover. Generated code carries a header that names its generator (`script/`); tools that write code live in `script/`, not here.

## License

All the components are under one license, the Business Source License 1.1: [LICENSE](LICENSE). The code becomes Apache License 2.0 on the Change Date written there.
