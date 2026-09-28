# Eve language repository

Eve is a domain-specific scripting language (data processing, test automation).
This repo holds the language **examples and docs**; there is no compiler here.

- `demo/` ~45 small `.eve` examples; `pattern/` syntax patterns; `test/level1-3/` conformity tests
- `docs/` Markdown docs (`docs/index.md` + mostly empty stub pages in core/db/net/os/std)
- `tools/`, `files/` Notepad++ syntax (UDL) XML; `doc.sh` scaffolds the docs tree
- Eve file shape: `driver name:` … `process` … `return;`. Comments: `#` line, `**` title,
  `--` end of line, `/* … */` block, `+---- … ----+` box.
- **Line endings:** working tree is CRLF (`core.autocrlf=true`), index is LF. Keep CRLF.

## Token budget rules

1. **Orient cheaply.** `repomap.py` / `outline.py` first, then `Read` with `offset`/`limit`.
   Don't read a whole file to change a few lines.
2. **Search before reading:** Grep tool, or `bee-ed search … --count` / `--name-only`.
3. **Edit without reading.** The Edit tool requires a prior Read. `bee-ed edit`,
   `multiedit.py` and `splice.py` don't. When grep output already shows the exact text, edit directly.
4. **Batch.** Several edits → one `multiedit.py` call. A tree-wide pattern → `bee-ed sed`.
   A structured or repetitive refactor → write a one-off Python script in the scratchpad.
5. **Verify with summaries, not re-reads:** tool output, `git diff --stat`, `git diff -U1 <file>`.
6. `--dry-run` output is a short summary on every command. Use it before any tree-wide `sed`.

## Which tool

| Task | Command |
|---|---|
| What files exist, sizes, titles | `python .claude/scripts/repomap.py [dir] [--ext .eve,.md] [--dirs]` |
| Headings / declarations + line numbers | `python .claude/scripts/outline.py <file-or-dir> [--depth 2]` |
| One-line or single-span unique edit | `bee-ed edit <file> '<old>' '<new>'` |
| Multi-line edits, several files, atomic | `python .claude/scripts/multiedit.py <<'EOF' … EOF` |
| Rewrite / insert / delete lines by number | `python .claude/scripts/splice.py <file> replace A B --expect '<text in line A>' <<'EOF'` |
| Regex replace across files | `bee-ed sed '<re2>' '<repl>' <dir-or-glob> --dry-run`, then without `--dry-run` |
| Regex search | `bee-ed search '<re2>' '*.eve' [--count]` |
| Create a new file in chunks | `bee-ed append <file> --new <<'EOF'` then `bee-ed append <file> <<'EOF'` |
| Move a doc + fix all links to it | `python .claude/scripts/mdlinks.py rename <old> <new> --git-mv` |
| Broken links / anchors | `python .claude/scripts/mdlinks.py check [docs]` |
| HTML tag balance in `.md` | `bee-ed balance <file>` |

Every script has full usage in its docstring (`python .claude/scripts/<name>.py -h`).
All of them preserve CRLF/LF and the final newline, and write atomically.

### multiedit spec (markers at column 0, no blank separator lines)

```
@@@ FILE docs/index.md
@@@ OLD
exact text, must occur exactly once
@@@ NEW
replacement (empty = delete)
@@@ OLD all
replaced at every occurrence
@@@ NEW
new text
@@@ FILE demo/hello_world.eve
...
```
If any OLD is missing or ambiguous, **nothing** is written and every problem is listed.

## bee-ed notes

- Requires the **fixed build** in `C:\Users\eluci\sage-code\ed-tool\bin` (2026-09-28). The older
  copy in `bee-lang\bin` mangles CRLF and walks `.git`. Check which one runs:
  `bee-ed edit --help` must mention "Line endings are handled".
- Every command keeps CRLF/LF and the final newline. Multi-line `edit` works on CRLF files.
- `sed` matches the whole file: use `(?m)` for per-line `^`/`$` (CRLF files are matched as LF).
  Replacement `$1`/`${name}`, literal `$` = `$$`. RE2: no lookaround or backreferences.
- Masks: `*.md` = that base name at any depth; `docs/*.md` = one level only (pass `docs` to recurse);
  a literal file path = exactly that file. `.git` is never entered.
- `apply` handles multi-file patches and shifted hunks, but `multiedit.py`/`splice.py` are cheaper
  because you don't have to write a diff.
- Arguments: `@path` reads a file (a missing `@x.txt` is an error), `@@x` is the literal `@x`,
  Eve names like `@self` stay literal. Text starting with `-` is fine; `--` ends flags.
- Git Bash rewrites arguments that start with `/` (e.g. `/*` Eve comments). The project settings
  set `MSYS_NO_PATHCONV=1`, so always use repo-relative or `C:/…` paths, never `/c/…`.
- Quote patterns in single quotes. For text containing `'`, pipe it via `@-` with `printf '%s'`:
  `printf '%s' "it's" | bee-ed edit f.md @- 'it is'`. Don't use a heredoc for `@-`: its trailing
  newline becomes part of `<old>`. `multiedit.py` has no quoting issues at all.
