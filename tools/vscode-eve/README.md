# Eve Language for VS Code

Syntax colors, snippets and editing rules for `.eve` files.

- **Colors:** comments (`#` title and `##` subtitle at column 1, `**` to the end of the line, `(** **)` and `/* */` over several lines), strings with escapes, `&name;` and `{interpolation}`, symbols, numbers (`0x1F`, `0b101`, `12.50d`), the keywords of the specification in classes (control, flow, declarations, modifiers, operator words), constants, types, `$system` variables, `@references`, function names, operators.
- **Editing:** `**` is the line comment, `/* */` the block comment, brackets and quotes close themselves, indentation grows after `is`, `do`, `then`, `else` and shrinks at `done`, `return`, `end`.
- **Snippets:** `primary`, `process`, `function`, `procedure`, `functionrecover`, `method`, `class`, `module`, `from`, `if`, `ifelse`, `while`, `for`, `match`, `job`, `recover`, `expect`, `print`.

## Files

| Path | What |
|---|---|
| `package.json` | the extension: language `eve`, grammar, snippets |
| `syntaxes/eve.tmLanguage.json` | the TextMate grammar, scope `source.eve` (**generated**) |
| `language-configuration.json` | comments, brackets, indentation, folding (**generated**) |
| `snippets/eve.json` | the snippets |
| `gen_vscode.py` | writes the two generated files from `spec/lexical/keywords.json` |

The same grammar is what GitHub Linguist needs (`backlog/vscode-plugin.md`, step 2) and can be imported by Sublime Text and JetBrains.

## Install

```
cd tools/vscode-eve
npx @vscode/vsce package          # makes eve-language-0.1.0.vsix
code --install-extension eve-language-0.1.0.vsix
```

For a quick try without packaging, open `tools/vscode-eve` in VS Code and press F5 (a development window with the extension loaded).

## When the keywords change

`python tools/vscode-eve/gen_vscode.py`. The pre-commit hook runs it when `spec/lexical/keywords.json` is committed.

## Check the grammar

The grammar was checked with `vscode-textmate` and `vscode-oniguruma` (the engine of VS Code) over 300 files of `test/` and `lib/`: no error, and the scopes of a sample (keywords, numbers, escapes, interpolation, a block comment over two lines, `$error`, `@self`) are as expected.

## Not done

- Not published to the Marketplace or Open VSX; `publisher` is `sage-code` as a placeholder and `license` is `UNLICENSED` until the author chooses the license of the tools.
- No language server (diagnostics from `eve cp --check`, run and debug commands) and no icon.
- `#` is a title at column 1 only, in Eve; the grammar uses `^#` so it matches this.
