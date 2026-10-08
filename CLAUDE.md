# Eve language repository

Eve is a domain-specific scripting language (data processing, test automation).
This repo holds the language **examples, spec and manual**, and the first implementation: the
Eve virtual machine, written in Zig 0.16 in `evevm/`, built to `bin/eve.exe` (runs level 1: 65/65 tests, level 2: 62/62 tests, level 3: 47/47 tests, level 4: 3 tests, smoke: 16 tests).
Build and test from `evevm/`: `zig build -p ..` (installs `bin/eve.exe`), `zig build test`.
`.zig`/`.zon`/`.sh` files are LF (`.gitattributes`), unlike the rest of the repo.
**Zig is taught here (didactic project):** the team does not know Zig. Every function, test, type
and non-obvious declaration you write or change in `evevm/` gets a `// Zig tip:` comment block just
before it (Zig has no block comments; use consecutive `//` lines, above any `///` doc comment),
explaining the language feature it shows: error unions, optionals, comptime, slices, allocators,
`defer`, and so on. Explain in plain words, one idea per tip, do not repeat a tip the file already
has; refer to it instead. Keep the tips correct for Zig 0.16.

- `spec/` **the Eve specification being written**: Markdown + JSON, normative. Conventions in
  `spec/README.md`.
- `plan/` **permanent step-by-step plan** for the tutorial and the spec. For improvement work,
  run `python script/plan.py status` (open steps and questions, ~50 lines; don't read the logs
  whole), take the next open step, and update its status mark when done (rules: `plan/README.md`).
  Decisions and open questions for the author are in `plan/decision_level1.md` (project, single
  script) and `plan/decision_level2.md` (processes, aspects, modules, libraries); ids are shared.
  `python script/plan.py show D-087` prints one entry, also from `plan/archive/` (settled, full text).
- `issues/` one file per tutorial page: questions and fixes from the page review (T1.10). The
  author answers by editing `**Answer:**` lines; answers become decisions in `plan/decision_levelN.md`.
- `demo/` **deleted** (D-099): every demo has a home in `test/level1/` or in the tutorial (`tutorial/demo/`, datetime.html); the list is the tutorial page `examples.html` (Demos & Examples). `pattern/` syntax patterns; `test/level1-7/` conformity tests, expectations in `/*@expect*/` blocks
- `manual/` **compiler manual** (was `docs/`): how to implement and use an implementation;
  `manual/features/` tables are generated from `spec/` + `manual/support/*.json`, never hand-edited.
  Conventions in `manual/README.md`.
- `script/` Python scripts: the test runner (`runtest.py`) and the token-saving utilities below.
- `tools/` typing aids (`alt-codes.md`)
- `tutorial/` **junction** to `C:\Users\eluci\sage-code\scl\projects\eve`: the published Eve
  tutorial (38 topic pages), owned by the `scl` repo. See "Tutorial" below.
- Eve file shape: line 1 is `#!` (free script), `#` title or `##` subtitle; then `driver name is`
  … `  process main is` … `  return;`, `end name;`. Comments: `#`/`##` at column 0, `**` to end of line, `(** … **)`
  expression, `/* … */` block (no nesting). `--` and `+- -+` boxes are gone (D-011, D-014).
  Control flow: D-016 in `plan/decision_level1.md`.
- **Line endings:** working tree is CRLF (`core.autocrlf=true`), index is LF. Keep CRLF.
- **Markdown prose is not hard-wrapped:** one line per paragraph and per list item (an author answer or a `(a)` item keeps its own line). To reflow a wrapped file: `python temp/unwrap_md.py <files>`.

## VM workflow: speed and performance watch

- **Test with the ReleaseSafe build** (about 4.6 times faster than Debug). Build it once per change: `cd evevm && zig build -Doptimize=ReleaseSafe -p ../temp/rel`, then run the tests with `python script/runtest.py 1 --eve temp/rel/bin/eve.exe` (also `all`, `smoke`). Use the Debug build (`zig build -p ..`, `bin/eve.exe`) only to debug a failure: it keeps safety checks and stack traces readable.
- **Watch performance at every feature or optimization of the VM.** Before and after the change run `python script/bmark.py --build ReleaseSafe --eve temp/rel/bin/eve.exe` (add `--check` to fail on a slowdown above 25%). When a version is done, run it with `--save` (updates `test/bmark/history.json` and the table of the README) and add a paragraph to "Notes by version" in `test/bmark/README.md`: what changed, appreciation or depreciation, and why a drop of more than 10% happened. Compare only runs of the same build on the same machine.
- **Every benchmark has a twin in Python** (`test/bmark/ref/<name>.py`); the report shows the ratio Eve / Python. A new level or a new kind of work adds a benchmark `p<level><letter>_<name>.eve` with its twin and a `** perf:` description line.
- **Do not optimize early** (decision of 2026-10-07): until level 2 passes its tests, change the interpreter for correctness, not for speed (slot-resolved variables wait for the final scope rules). Do fix a benchmark that falls more than 10 times behind Python, it points to an accidental quadratic cost. The first planned optimization is variable lookup by slot, resolved in `check.zig`.

## Tutorial (`tutorial/` → scl repo)

The tutorial is the reference that the new specification in this repo builds on. It is
maintained here but **versioned in the scl repo** (branch `main`). It is git-ignored in eve-lang.

- Edit files through `tutorial/…` as usual. Commit with `git -C tutorial …`, which resolves to the
  scl repo. Never `git add` it from eve-lang.
- Pages are large (up to ~1,600 lines). Run `outline.py tutorial/<page>.html --depth 3` first,
  then read by line range. `repomap.py tutorial --ext .html` lists all the pages with titles.
- Links are followed only when named: `bee-ed … tutorial` and `outline.py tutorial` enter it;
  a plain `*.html`, or a script run on `.`, stays inside eve-lang.
- Check markup after edits: `bee-ed balance tutorial/<page>.html`. As of 2026-09-30, all
  pages balance; raw `<`/`>` in code blocks must be written `&lt;`/`&gt;`.
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
   `script/` walkers skip it. Don't use the system temp dir or the session scratchpad.
   With `bee-ed`, name target dirs (`demo manual`) rather than `*` so `temp/` isn't matched.
6. **Verify with summaries, not re-reads:** tool output, `git diff --stat`, `git diff -U1 <file>`.
7. `--dry-run` output is a short summary on every command. Use it before any tree-wide `sed`.

## Which tool

| Task | Command |
|---|---|
| What files exist, sizes, titles | `python script/repomap.py [dir] [--ext .eve,.md] [--dirs]` |
| Headings (md/html) / Eve declarations + line numbers | `python script/outline.py <file-or-dir> [--depth 2]` |
| One-line or single-span unique edit | `bee-ed edit <file> '<old>' '<new>'` |
| Multi-line edits, several files, atomic | `python script/multiedit.py <<'EOF' … EOF` |
| Rewrite / insert / delete lines by number | `python script/splice.py <file> replace A B --expect '<text in line A>' <<'EOF'` |
| Regex replace across files | `bee-ed sed '<re2>' '<repl>' <dir-or-glob> --dry-run`, then without `--dry-run` |
| Regex search | `bee-ed search '<re2>' '*.eve' [--count]` |
| Create a new file in chunks | `bee-ed append <file> --new <<'EOF'` then `bee-ed append <file> <<'EOF'` |
| Move a doc + fix all links to it | `python script/mdlinks.py rename <old> <new> --git-mv` |
| Broken links / anchors | `python script/mdlinks.py check [manual]` |
| HTML tag balance in `.md` | `bee-ed balance <file>` |
| Check the grammar of `spec/syntax/grammar.md` against the tests | `python script/grammarcheck.py [files]` (needs `pip install lark`) |
| Refresh the keyword lists of the tutorial highlighter (`tutorial/js/eve1.js`) from `spec/lexical/keywords.json` | `python script/genkeywords.py` (`speccheck.py` reports a stale file; the pre-commit hook in `.githooks/` runs it; `git config core.hooksPath .githooks` once per clone) |
| Tutorial pages of the tests (`tests.html`, `smoke.html`, `performance.html`) | `python script/genpages.py [--check]`; **generated**: `runtest.py` and `bmark.py --save` call it, never edit the part between `GEN:BEGIN` and `GEN:END` by hand (D-136) |
| Run tests on the VM (TDD) | `python script/runtest.py 1` / `all` / `a03` → reports in `temp/output/` |
| Performance of the VM (per level) | `python script/bmark.py [--save]` → `test/bmark/`, notes per version in its README |

Every script has full usage in its docstring (`python script/<name>.py -h`).
All of them preserve CRLF/LF and the final newline, and write atomically.

### multiedit spec (markers at column 0, no blank separator lines)

```
@@@ FILE manual/README.md
@@@ OLD
exact text, must occur exactly once
@@@ NEW
replacement (empty = delete)
@@@ OLD all
replaced at every occurrence
@@@ NEW
new text
@@@ FILE test/level1/a03_print.eve
...
```
If any OLD is missing or ambiguous, **nothing** is written and every problem is listed.

## bee-ed notes

- Requires the **fixed build** in `C:\Users\eluci\sage-code\ed-tool\bin` (2026-09-28). The older
  copy in `bee-lang\bin` mangles CRLF and walks `.git`. Check which one runs:
  `bee-ed edit --help` must mention "Line endings are handled".
- Every command keeps CRLF/LF and the final newline. Multi-line `edit` works on CRLF files.
- `sed` matches the whole file: use `(?m)` for per-line `^`/`$`. With the old copy on PATH (see
  above; still the case 2026-09-28), `$` does not match before `\r` in CRLF files: write
  `([ \t]*\r?)$` and keep `\r` inside the group, or the CR is dropped.
  Replacement `$1`/`${name}`, literal `$` = `$$`. RE2: no lookaround or backreferences.
- Masks: `*.md` = that base name at any depth; `spec/*.md` = one level only (pass `spec` to recurse);
  a literal file path = exactly that file. `.git` is never entered.
- `apply` handles multi-file patches and shifted hunks, but `multiedit.py`/`splice.py` are cheaper
  because you don't have to write a diff.
- Arguments: `@path` reads a file (a missing `@x.txt` is an error), `@@x` is the literal `@x`,
  Eve names like `@self` stay literal. With the old copy, an argument starting with `-` is taken as
  a flag and `--` is rejected: pass such text as `@file` (`printf '%s' '-x' > temp/a.txt`).
- Git Bash rewrites arguments that start with `/` (e.g. `/*` Eve comments). The project settings
  set `MSYS_NO_PATHCONV=1`, so always use repo-relative or `C:/…` paths, never `/c/…`.
- Quote patterns in single quotes. For text containing `'`, pipe it via `@-` with `printf '%s'`:
  `printf '%s' "it's" | bee-ed edit f.md @- 'it is'`. Don't use a heredoc for `@-`: its trailing
  newline becomes part of `<old>`. `multiedit.py` has no quoting issues at all.
