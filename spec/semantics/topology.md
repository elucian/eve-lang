# Topology of a program

Status: **draft**, level 1 to 3. How the files of an Eve program fit together. The pieces have their own pages; this page shows the whole.

## The pieces

| Piece | File | What it is | Page |
|---|---|---|---|
| script | `name.eve` | one `primary aspect`: the declarations and `process main` | [declarations.md](../syntax/declarations.md#scripts) |
| aspect | `asp/name.eve` | an `exclusive` (default) or `concurrent` unit with its own state, started with `apply` | [aspects.md](aspects.md) |
| module | `lib/name.eve` | declarations to share, not run: `module name is`, `export (…)` | [modules.md](modules.md) |
| class | in a script or a module | data and methods; traits and generics at level 4 | [declarations.md](../syntax/declarations.md) |
| library | a folder of modules | the standard library, `$EVE_LIB`, the folders of `$EVE_LIB_PATH` | [modules.md](modules.md) |
| project | a folder | `asp/`, `lib/`, `data/`, `out/` around a script | [project-layout.md](project-layout.md) |

## Who calls and who sees

- A command runs the `main` of a **primary** aspect. It runs no module and no concurrent aspect.
- A primary aspect starts other aspects with `apply` and imports modules with `from … use`. A module is bound to the aspect that imports it.
- An aspect has its own scope and state, created at each call and dropped when its `main` returns. It reads nothing of its caller except its arguments and gives back only its `@` parameters ([scopes.md](scopes.md#visibility)).
- Functions, procedures and classes live in the aspect or module that declares them. A module shows only what it exports.
- Parallel work (concurrent aspects, `start`, groups, channels) is the subject of [multitasking.md](multitasking.md).

## Where a module is searched

An import without a path searches, in this order: the standard library, `$EVE_LIB` (the `lib` folder of the project), then each folder of `$EVE_LIB_PATH` ([modules.md](modules.md)). A path that does not start with `/` is relative to `$EVE_HOME`, the folder of the aspect run by the command ([variables.md](variables.md#system-variables)).
