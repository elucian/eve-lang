# evevm — the Eve virtual machine

The first Eve implementation (D-006, D-007 in `../plan/decision_level1.md`): a virtual machine written in Zig that runs Eve scripts. It builds `bin/eve.exe` at the repo root, the official `eve`
command. Manual: [`../manual/README.md`](../manual/README.md).

Version: **0.0.2**. Status: level 1 passes (82 of 82 tests of `test/level1/`) and level 2 passes (29 of 29 tests of `test/level2/`, 2026-10-07): lexer, parser, a static check (`check.zig`, D-110), the link of a driver with its aspects (`project.zig`: `apply`, D-112) and a tree-walking interpreter with the run log. Levels 3 to 7 are not implemented.

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
| `src/lexer.zig`, `src/parser.zig`, `src/ast.zig` | tokens, syntax tree, the grammar of `spec/syntax/grammar.md` |
| `src/check.zig` | the static check before the run: names, scopes, procedures, parameter order, private methods |
| `src/interp.zig` | the tree-walking interpreter |
| `src/doc.zig` | the `doc` command: Markdown documentation of `.eve` files |
| `src/root.zig` | the VM library module (`evevm`): lexer, parser, interpreter as they land |
| `src/main.zig` | the `eve` command line, a thin front end over the library |
| `lib/` | the Eve standard library, mostly written in Eve ([README](lib/README.md)) |
| `doc/` | the library documentation, generated from `lib/` by `eve --doc` (`zig build doc`, D-082); the `.md` pages are never edited by hand |

## License

Business Source License 1.1, see [LICENSE](LICENSE). The code becomes Apache 2.0 on the Change Date.
