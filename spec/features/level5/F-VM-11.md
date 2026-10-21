# F-VM-11 One `eve`, its source in modules

The modules `evecm`, `evecp`, `evevm`, `evedb`, `eveux` and `cmd` with one build; one binary whose first word chooses the part, `eve vm`, `cp`, `db`, `ux`; the serving machine as one process.

*Partial (2026-10-13):* the modules `evecm`, `evecp`, `evevm`, `evedb` and `cmd` exist in one root build (arrows checked by the build); the values and the heap are in `evecm`; the database layer is `evedb` behind the interfaces `Host` and `Data`; the configuration and the wire are cut from `server.zig`; not yet: the cut of the machine and of `cli.zig`, the native calling convention, `eveux` and `evetx` in the root build, the part words.

## Missing

- The cut of the machine and of `cli.zig`, the native calling convention.
- `eveux` and `evetx` in the root build; the part words `eve vm`, `cp`, `db`, `ux`.
