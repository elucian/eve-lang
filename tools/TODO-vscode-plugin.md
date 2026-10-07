# TODO: VS Code plugin and GitHub syntax colors for Eve

Reminder written 2026-10-02. Goal: make the `.eve` extension recognized and colored in VS Code and on GitHub.

## Is `.eve` taken on GitHub?

Checked 2026-10-02 against `lib/linguist/languages.yml` and `heuristics.yml` of github-linguist/linguist (main):
**no language uses `.eve`**, and no heuristic mentions it. So GitHub shows `.eve` files as plain text today. Not checked:
the real use of the extension in the wild (GitHub code search needs a login). Check it by hand:
<https://github.com/search?q=path%3A*.eve&type=code>. Several unrelated projects may use `.eve` (an older "Eve" language, game or
simulation data), which is fine as long as Linguist has no entry for it; a heuristic may be needed if one is found.

## Step 1: grammar and plugin (VS Code)

- [ ] Create `tools/vscode-eve/` (publisher id, name `eve`, display name "Eve Language").
- [ ] `syntaxes/eve.tmLanguage.json`: TextMate grammar, scope name `source.eve`. Generate the word lists from the specification
      (`spec/lexical/keywords.json`, `operators.json`, `delimiters.json`) so the colors never drift from the language. Keywords
      wait for Q-002 (S2.4). Scopes: comments (`#` title at column 1, `##`, `**`, `(** **)`, `/* */`), strings with the escapes
      `\n \xHH \u{} &name;` and the interpolation `\s{} \#{} \b{}`, text literal `"""`, symbols `'a'` and `U+03B2`, numbers
      (`0x`, `0b`, real, rational `3\4`), constants `True False Null`, sigils (`$name`, `@name`, `name!`), types (capitalized
      names), operators (longest match: `..<`, `>..<`, `><`, `=~`, `!~`, `<-`, `->`).
- [ ] `language-configuration.json`: line comment `**`, block comment `/* */`, brackets `() [] {}`, auto-closing pairs, indentation
      (2 spaces, `is` opens a block, `done`/`return`/`end` close).
- [ ] `snippets/eve.json`: `driver`, `process`, `method`, `function`, `class`, `if`, `while`, `for`, `match`, `job`, `expect`.
- [ ] `package.json` with `contributes.languages` (id `eve`, extensions `[".eve"]`, first line `^#!.*\beve\b`) and `grammars`.
- [ ] Test on `tutorial/demo/**/*.eve`, `pattern/*.eve` and `test/**/*.eve` (the same files the throwaway parser of S3.6 reads).
- [ ] Package with `vsce package`; publish to the VS Code Marketplace and to Open VSX (VSCodium).
- [ ] Later: language server (diagnostics from `eve parse`), run and debug commands, the `eve --doc` documentation.

## Step 2: GitHub (Linguist)

GitHub colors a language with a TextMate grammar through the Linguist project. The Linguist rules (check
`CONTRIBUTING.md` of the repository first, they change): the extension must be used in a large number of public repositories
(200 or more at last check), the grammar must have an open license, and the pull request adds the language, a sample set and
the grammar.

- [ ] Publish the grammar in its own public repository (example: `sagecode/eve-grammar`) under a permissive license
      (MIT or Apache 2.0, since a grammar is copied into Linguist).
- [ ] Collect samples from `tutorial/demo/` and `test/` (real, varied programs; no generated files).
- [ ] Wait for the extension to be used by enough public repositories (the tutorial, the examples and student projects help).
- [ ] Pull request to github-linguist/linguist: entry in `lib/linguist/languages.yml` (`Eve`, type `programming`, `extensions: [".eve"]`,
      `tm_scope: source.eve`, `ace_mode: text`, `color`), grammar as a vendored submodule (`script/add-grammar`), samples in
      `samples/Eve/`. If `.eve` is shared with another language, add a rule to `heuristics.yml`.
- [ ] Until it is merged GitHub shows `.eve` files as plain text; a `.gitattributes` line (`*.eve linguist-language=...`) can
      only name a language that Linguist already knows, so there is nothing to add yet.
- [ ] Also useful: `eve-lang` topic and repository description, so people can find the examples.

## Other editors (reuse the same grammar)

- [ ] Notepad++ UDL (the author already keeps UDL files), Sublime Text (`.sublime-syntax` or the tmLanguage), Vim, JetBrains
      (TextMate bundle import), Prism.js (`tutorial/js/eve1.js`, regenerate from the keyword JSON), highlight.js.

## Notes

- Name: the plugin published by the project may use the name "Eve Language". A plugin published by a third party must follow
  `TRADEMARK.md` (for example "Eve language support", not "Official EVE").
- The extension id of the plugin and the Linguist name must match the language name used in the specification: "Eve".
