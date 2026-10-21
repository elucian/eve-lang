# Technical debt of the tools

Same rules as `backlog/tech-debt.md` (author's word, 2026-10-18): one line for each shortcut, gap or postponed piece of `tools/`, with id, what, why, where and when to pay; remove a line when it is paid. The ids are shared with `backlog/tech-debt.md`, which points here (TD-T).

| Id | Debt | Why left | Where | Pay |
|---|---|---|---|---|
| TD-16 | The Zed extension (`tools/zed-eve`) was checked with the Tree-sitter CLI only, not loaded in Zed; the grammar `rev` is a local commit; no bracket matching, indents, outline | the author tests editors by hand | `tools/zed-eve/README.md` | when the grammar gets its own repository |
| TD-18 | The license and publisher of the editor tools are placeholders: VS Code `UNLICENSED`, publisher `sage-code`; the Tree-sitter grammar says MIT (chosen by the model, not the author); the repository URL `github.com/sagecode/eve-lang` is a guess | the author has not chosen | `tools/vscode-eve/package.json`, `tools/tree-sitter-eve/package.json`, `tools/zed-eve/extension.toml` | before publishing |
| TD-19 | Three generators write the same word lists (`script/genidekeywords.py`, `tools/zed-eve/gen_zed.py`, `tools/vscode-eve/gen_vscode.py`) and each keeps its own copy of the type list | speed | the three files | move the type list to `spec/lexical/` or `spec/semantics/types.json` when the next editor is added |
| TD-20 | The VS Code extension was packaged (`vsce package`) and its grammar checked with `vscode-textmate`, but it was not installed in VS Code and looked at by eye | the author tests editors by hand | `tools/vscode-eve/` | at the first install |
| TD-21 | `tools/tree-sitter-eve/src/parser.c` is generated and committed; the hook cannot rebuild it, so it can lag `grammar.js` after a keyword change | the Tree-sitter CLI needs a C compiler (on this machine a `zig cc` wrapper in `temp/`) | `tools/tree-sitter-eve/src/`, `.githooks/pre-commit` | when the grammar gets its own repository and a CI job |
| TD-22 | GitHub Linguist (colors on GitHub), Sublime Text, JetBrains, Notepad++, highlight.js and Prism are not done; the TextMate grammar of `tools/vscode-eve` is the source for most of them | order of work | `backlog/vscode-plugin.md` steps 2 and "Other editors" | after level 6 |
| TD-23 | No language server: no diagnostics from `eve cp --check`, no run or debug command, no `eve --doc` hover in VS Code or Zed | big, needs the machine API (F-NET-08) | `tools/` | level 7 |
