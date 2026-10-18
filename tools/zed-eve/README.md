# Eve for Zed

Syntax colors for `.eve` files in the [Zed](https://zed.dev) editor: comments (`#` title, `**`, `(** **)`, `/* */` over several lines), strings, numbers, keywords, control words, operators, types, `$system` variables and `@references`.

## Parts

| Path | What |
|---|---|
| `extension.toml` | the extension: id `eve`, the grammar and where it comes from |
| `languages/eve/config.toml` | the language: name, `.eve`, line comment `**`, brackets, 2 spaces |
| `languages/eve/highlights.scm` | which node gets which color (**generated**) |
| `../tree-sitter-eve/grammar.js` | the Tree-sitter grammar (**generated**); `src/` is its generated parser |
| `gen_zed.py` | writes the grammar and the queries from `spec/lexical/keywords.json` |

The grammar reads a file as a list of tokens; it is for colors, not a second parser of the language (the compiler is `evecp`).

## Install for development

1. Commit the repository (Zed builds the grammar from a commit): `extension.toml` names the commit in `rev` and the folder in `path`.
2. In Zed: command palette → `zed: install dev extension` → choose the folder `tools/zed-eve`.
3. Open a `.eve` file: the language shows as **Eve**. Errors of the extension are in `zed: open log`.

No Rust is needed: the extension has no code, only a language and a grammar. Zed compiles the grammar to WebAssembly itself.

## When the keywords change

`python tools/zed-eve/gen_zed.py`, then `cd tools/tree-sitter-eve && npx tree-sitter-cli generate` to make `src/parser.c` again, commit, and put the new commit in `rev` of `extension.toml`. The pre-commit hook (`.githooks/pre-commit`) runs `gen_zed.py` when `spec/lexical/keywords.json` is committed, but cannot run the Tree-sitter CLI.

## Test the grammar

`cd tools/tree-sitter-eve && tree-sitter parse ../../test/level3/c34_module_recover/lib/safe.eve` prints the tokens. 400 files of `test/` and `lib/` parse without an error node. On Windows the CLI needs a C compiler for `parse`; with Zig installed set `CC` to a wrapper that runs `zig cc -target x86_64-windows-gnu` and drops the `--target` option.

## Not done

- Not checked by loading it in Zed (the author's machine); the grammar and queries are checked with the Tree-sitter CLI only.
- No bracket matching (the brackets are named tokens, not anonymous nodes), no indentation queries, no outline, no language server.
- `#` is a title at column 1 only in Eve; the grammar takes `#` to the end of the line anywhere.
- The block-comment toggle is not configured (the format of `block_comment` changed between Zed versions).
- Publishing to the Zed extension gallery needs the grammar in its own public repository (`tools/tree-sitter-eve`).
