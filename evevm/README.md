# evevm — the Eve virtual machine

The first Eve implementation (D-006, D-007 in `../plan/decisions.md`): a virtual machine written
in Zig that runs Eve scripts. It builds `bin/eve.exe` at the repo root, the official `eve`
command. Manual: [`../manual/README.md`](../manual/README.md).

Status: skeleton. `eve --version` and `eve --help` work; running a script is not implemented yet.

## Build

Requires Zig 0.16.0 (`winget install zig.zig`). Run from this folder:

| Command | Result |
|---|---|
| `zig build -p ..` | builds and installs `../bin/eve.exe` |
| `zig build` | builds `zig-out/bin/eve.exe` (local, git-ignored) |
| `zig build run -- --version` | builds and runs `eve` with arguments |
| `zig build test` | runs the unit tests |
| `zig build -p .. -Doptimize=ReleaseSafe` | release build |

## Layout

| Path | Contents |
|---|---|
| `build.zig`, `build.zig.zon` | build script and package manifest |
| `src/root.zig` | the VM library module (`evevm`): lexer, parser, interpreter as they land |
| `src/main.zig` | the `eve` command line, a thin front end over the library |
| `lib/` | the Eve standard library, mostly written in Eve ([README](lib/README.md)) |
| `doc/` | `eved.zig`, the Eve doc tool in Zig, and the library documentation it generates (`zig build doc`); the `.md` pages are never edited by hand |
