---
name: zig-split-file
description: Split a big Zig file of this repo by concern (step A6 of design/design-ai-context.md). Use when ctxsize.py warns about a file over 2,000 lines, or before adding to a file near 800 lines.
---

# Split a big Zig file

Two tools in `script/` do the mechanical move; both take a plan file in `temp/` and print a dry run unless `--apply` is given. They run `zig fmt` on what they write. Check the file with `python script/ctxsize.py` first.

| The file is | Tool | Plan keys |
|---|---|---|
| One big `struct` whose methods are `fn name(self: *T, ...)` (evetx `App`, the `Parser`) | `python script/splitzig.py temp/split_x.py` | `SRC STRUCT TYPES TYPES_RANGE TYPES_HEAD IMPORT_PREFIX CHUNKS` |
| Top-level free functions and constants (evetx `view.zig`) | `python script/splitfree.py temp/split_x.py` | `SRC MODDIR IMPORT_LINES REEXPORT CHUNKS` |

Examples that worked: `script/splitplans/split_app.py` (App into `code/evetx/src/app/*.zig`), `script/splitplans/split_view.py` (view into `code/evetx/src/view/*.zig`), `script/splitplans/split_parser.py` (Parser into `code/evecp/src/parser/*.zig`). These plans are the record of the splits already done (line numbers refer to the files before the split); for a new file write a plan in `temp/` from the pattern: `CHUNKS = [(file, first_line, last_line, head_lines)]`, one chunk per `// ----` section, found with `grep -nE '^    (pub )?fn |^// ---' file`.

## How a struct split works

A method group becomes free functions with `*T` as first parameter in a new file; the struct keeps `pub const name = mod.name;` aliases, so `self.name()`, `T.name()` and every outside caller still work. Code before the struct (types, menus) goes whole into the `TYPES` file and is re-exported. Bare uses of a sibling decl inside a moved method become `T.name`.

## Checklist

1. Clean tree (`git status`); build and test pass before you start.
2. Choose chunks at section comments; a chunk starts at its first `///` or `// @` line (the tool moves the start up for you). Chunk ends at the line before the next chunk; the last chunk ends before the struct's closing `};`.
3. Dry run, then `--apply`, then build. Expected fixes by hand: a private decl of the core or of a type that a new file uses must become `pub`; `Parser`-like private structs the new files import must be `pub const`.
4. Verify behavior: `zig build test`, then the conformance sweep and `bctest.py` for evecp/evevm (`eve-test-loop` skill). A pure move changes no test result.
5. Heads: each new file has `//! @eve-module`, `@feature`, `@decision`, `@see` (the plan writes them); run `python script/tagcheck.py`.
6. Update `design/design-ai-context.md` (step A6 mark and measure) and, if a size limit changed, `script/ctxsize.py`.

## Pitfalls seen

- String literals: a rewrite that qualifies names must skip strings, char literals and comments; an early version turned the message "has no process main" into "has no Parser.process main". Always run the conformance tests.
- Edit tools and shells in this setup can eat backslashes in scripts you write with a heredoc; write patch scripts with the Write tool, or build backslashes with `chr(92)`.
- Zig reports shadowing: a local named like the import alias of the new files (for example `types`) is an error; name the types import after its file (`consts`).
- A struct-level `const` or nested type moves with its group and gets an alias too; use it as `T.Name` from other files.
