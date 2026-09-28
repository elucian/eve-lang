# Eve language repository

Eve is a domain-specific scripting language (data processing, test automation).
This repo holds the language **examples and docs**; there is no compiler here.

- `spec/` **the Eve specification being written**: Markdown + JSON, normative. Conventions in
  `spec/README.md`.
- `plan/` **permanent step-by-step plan** for the tutorial and the spec. For improvement work,
  start with `plan/README.md`, take the next open step, and update its status mark when done.
  Open questions for the author are in `plan/decisions.md`.
- `demo/` ~45 small `.eve` examples; `pattern/` syntax patterns; `test/level1-3/` conformity tests
- `docs/` Markdown docs (`docs/index.md` + mostly empty stub pages in core/db/net/os/std)
- `tools/`, `files/` Notepad++ syntax (UDL) XML; `doc.sh` scaffolds the docs tree
- `tutorial/` **junction** to `C:\Users\eluci\sage-code\scl\projects\eve`: the published Eve
  tutorial (17 HTML pages), owned by the `scl` repo. See "Tutorial" below.
- Eve file shape: `driver name:` … `process` … `return;`. Comments: `#` line, `**` title,
  `--` end of line, `/* … */` block, `+---- … ----+` box.
- **Line endings:** working tree is CRLF (`core.autocrlf=true`), index is LF. Keep CRLF.

## Tutorial (`tutorial/` → scl repo)

The tutorial is the reference that the new specification in this repo builds on. It is
maintained here but **versioned in the scl repo** (branch `main`). It is git-ignored in eve-lang.

- Edit files through `tutorial/…` as usual. Commit with `git -C tutorial …`, which resolves to the
  scl repo. Never `git add` it from eve-lang.
- Pages are large (up to ~1,600 lines). Run `outline.py tutorial/<page>.html --depth 3` first,
  then read by line range. `repomap.py tutorial --ext .html` lists all the pages with titles.
- Links are followed only when named: `bee-ed … tutorial` and `outline.py tutorial` enter it;
  a plain `*.html`, or a script run on `.`, stays inside eve-lang.
- Check markup after edits: `bee-ed balance tutorial/<page>.html`. As of 2026-09-28, option,
  syntax, topology, collections, functions, databases and concurrency already had imbalances.
- Anything deleted **inside** `tutorial/` is deleted from the scl repo. To drop just the link,
  use `rm tutorial` (tested: the target stays intact). To recreate it:
  `cmd /c mklink /J tutorial C:\Users\eluci\sage-code\scl\projects\eve`.

## Token budget rules

1. **Orient cheaply.** `repomap.py` / `outline.py` first, then `Read` with `offset`/`limit`.
   Don't read a whole file to change a few lines.
2. **Search before reading:** Grep tool, or `bee-ed search … --count` / `--name-only`.
3. **Edit without reading.** The Edit tool requires a prior Read. `bee-ed edit`,
   `multiedit.py` and `splice.py` don't. When grep output already shows the exact text, edit directly.
4. **Batch.** Several edits → one `multiedit.py` call. A tree-wide pattern → `bee-ed sed`.
   A structured or repetitive refactor → write a one-off Python script in `temp/`.
5. **Temporary files go in `temp/`.** That covers one-off scripts, multiedit specs, splice input,
   and captured output. Its contents are git-ignored (only `temp/.gitkeep` is tracked), and the
   `.claude/scripts` walkers skip it. Don't use the system temp dir or the session scratchpad.
   With `bee-ed`, name target dirs (`demo docs`) rather than `*` so `temp/` isn't matched.
6. **Verify with summaries, not re-reads:** tool output, `git diff --stat`, `git diff -U1 <file>`.
7. `--dry-run` output is a short summary on every command. Use it before any tree-wide `sed`.

## Which tool

| Task | Command |
|---|---|
| What files exist, sizes, titles | `python .claude/scripts/repomap.py [dir] [--ext .eve,.md] [--dirs]` |
| Headings (md/html) / Eve declarations + line numbers | `python .claude/scripts/outline.py <file-or-dir> [--depth 2]` |
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
