# Eve language repository

Eve is a domain-specific scripting language (data processing, test automation).
This repo holds the language **examples, spec and manual**, and the first implementation: the
Eve virtual machine, written in Zig 0.17 as modules (`evecm` the common part, `evecp` the compiler, `evevm` the runtime, `eve` the command (was `cmd`); one root `build.zig`, D-163), built to `bin/eve.exe` (runs level 1: 73/73 tests, level 2: 78/78 tests, level 3: 58/58 tests, level 4: 47/47 tests, level 5: 117/117 tests (e01 to e22: generics, overloading, macros; e23 to e53 and e57 to e94, e103 to e107: data language and database layer; e54 and e55: `project init` and `project new`; e56: local ETL CSV to SQLite to JSON; e95: the machine, IPC, HTTP and stdio doors, the machine API `vm.*` (sessions, `vm.shell`, streamed output), a project with five use cases run by a Node.js client; e96 to e102: `sql function`, `$err_sql`, Eve stored procedures in `proc/`, `eve db proc list`), level 6: 15/15, smoke: 21 tests: the language, then tasks, generics, data files, the database and the machine; 409 tests agree on the tree walker and on the bytecode machine: `python script/runtest.py all --both`). `eve vm|cp|db|ux` choose a part (D-163); `./run.sh evevm|evecp|evedb|eveux <args>` are shortcuts.
Build and test from the repository root: `zig build -p .` (installs `bin/eve.exe`), `zig build test` (the unit tests of every module). The version is written once, in the root `build.zig.zon`. The arrows between the modules are the `.imports` of `build.zig`: `cmd` → `evevm` → `evecp` → `evecm`; a module that is not listed cannot be imported.
**Components live in `comp/`** (2026-10-19): `code/eve`, `code/evecm`, `code/evecp`, `code/evevm` (the modules of `eve`, built by the root `build.zig`, which also takes the database layer from `code/evevm/src/db.zig`), and `drivers/duckdb`, `code/evetx`, `code/eveux` (programs with their own `build.zig`: `./run.sh build <part>`, or `zig build -p ../..` from their folder), and `code/evewp` (design only). Each has `README.md` (design, state of the work) and `doc/` (the user documentation copied into the manual). `code/README.md` lists them; `code/LICENSE` (Business Source License 1.1) covers all of them. `./run.sh build` builds `eve` and `evevm` only; `./run.sh build all` every part; no build runs the tests. **Drivers live in `drivers/`** (`drivers/duckdb`: the DuckDB server, built by `./run.sh build duckdb`); the client drivers (`sqlite://`, `postgres://`, `evedb://`) are inside `code/evevm/src/db/`, one value of `Driver` each in the table `driver.zig`.
Every text file is LF, in the index and in the working tree (`.gitattributes`); only `.bat`/`.cmd`/`.ps1` are CRLF.

**Priority of the work (D-194, 2026-10-18; replaces D-190):** (1) plan (`design/`), (2) design, (3) user interfaces (`evetx`, `eveux`, `evewp`), (4) refactor, (5) optimize, (6) test, (7) specification (`spec/`), (8) compiler (the language and the machine progress), (9) manual (`manual/`), (10) tutorial (`tutorial/`) last. Take the next piece of work from the highest rank that has open work. The spec follows the tests: behavior is settled by tests and code, then the spec page is written or corrected. By case (D-196): an interface feature starts with a drawing (visual design leads); a language feature with a plan entry and a failing test; a refactor and an optimization with a measure before and after. The manual and the tutorial may lag. The old "tutorial first" focus is over.

**Technical debt (2026-10-18):** every shortcut, gap or postponed piece gets a line in `backlog/tech-debt.md` (id, what, why, where, when to pay) in the same commit; language gaps found by the standard library go in `backlog/library-gaps.md`.

**Zig comments for AI (D-190, replaces the `// Zig tip:` rule):** comments in the Zig modules (`code/evecm/`, `code/evecp/`, `code/evevm/`, `code/eve/`, `drivers/duckdb/`, `code/evetx/`) are written for AI that searches the code, not to teach people. Existing `// Zig tip:` blocks stay until the code under them changes; write no new ones. Every new, refactored or touched function, type, test and file gets what follows, in consecutive `//` lines above any `///` doc comment, one tag per line, `grep`-able:
- file head: `//! @eve-module <name>` (`code/evevm/src/dlib.zig`: library calls), then `//! @spec <path>#<anchor>`, `//! @feature F-XXX-nn`, `//! @decision D-nnn`, `//! @tests test/levelN/<name>`; a one-line `//!` purpose.
- function or type: `// @eve-fn <module>.<name>` (the Eve-visible name, when there is one) or `// @eve-impl <what>`; `// @spec <path>#<anchor>` (the exact rule it implements); `// @feature F-XXX-nn`; `// @decision D-nnn` when a decision shaped it; `// @test <test name>`; `// @perf hot` when speed matters; `// @invariant <fact that must hold>`; `// @see <file>:<symbol>` for the other side of a contract (Eve side or Zig side).
- Only the tags that apply; say what and where, never how Zig works. Tag values are exact (real paths, real ids, real names) so `grep -rn "@feature F-NET-02"` or `grep -rn "@eve-fn fs\."` finds every place of a feature. Add a missing tag when you touch the code.

- `drivers/duckdb/` **the Eve test database** (F-DAT-12; was `code/evedb`, moved to `drivers/` on 2026-10-19, D-198, D-200; not a component, no license file of its own, the license of `code/LICENSE` applies): a separate Zig program around DuckDB (prebuilt library v1.5.6, a lazy dependency of `drivers/duckdb/build.zig.zon`), never in the VM. Version 0.3 (2026-10-18, D-187): DuckDB lives only in evedb (SQLite stays in `eve`); the native protocol sends **column batches** and the driver `evedb://` uses them for `Memory.store`/`load` (`python script/evedb_bench.py` measures it); no triggers or procedures in evedb. Version 0.2 (D-186): evedb **answers as a PostgreSQL server** on port 5432 (configuration file `evedb.cfg`; start with `evedb serve --config evedb.cfg`, `eve db serve evedb.cfg`, or `eve -s -db --serve evedb.cfg` as a service), the Eve driver `postgres://` is in the module `evedb` (`pgclient.zig`, `pgdriver.zig`), plus the EWP-db control port, sessions, faults, statement log. Tests: `python script/evedb_check.py` (EWP-db), `python script/pg_check.py` (psycopg2, pg8000, the Eve driver; `pip install psycopg2-binary pg8000`), `test/level6/f01_pg_driver`, and `zig build test`; a demo in `drivers/duckdb/demo/`. Build and test from `drivers/duckdb/`: `zig build -p ../..` (installs `bin/evedb.exe` and `bin/duckdb.dll`), `zig build test`. Same Zig comment rules as `code/evevm/`. Design in `drivers/duckdb/README.md`; the database layer itself in `design/design-database-core.md` and `design/design-database-remote.md`.
- `code/evetx/` **the Eve terminal IDE** (F-TLS-24, F-TLS-27 to F-TLS-29, level 6, D-173 to D-178): a full-screen TUI over the Zig library libvaxis (pinned in `code/evetx/build.zig.zon`, a dependency of that module alone): file tree, editor, run, the two searches, menu, file card, and later the debugger, the machines and the database tabs; schedules and runs are `eveux`. **Started** (D-178) as a separate program: build and run from `code/evetx/` with `zig build -p ../..` (installs `bin/evetx.exe`) and `evetx [folder]`, or `eve -tx [folder]` (`eve tx`), which starts it from beside `eve`; unit tests only for the pure parts (`zig build test` in `code/evetx/`: the comment scanner, grid, options), the author tests the screen by hand; same Zig comment rules as `code/evevm/` (AI tags). Design and drawings: `code/evetx/README.md`, `code/evetx/design/`; the state of the work is `code/evetx/README.md` §11; `code/evetx/gen_keywords.py` writes `src/keywords.zig` from the spec; the files with no screen library (text, scan, keywords, project, link, regex, grid, sqlstruct, cache) live in `code/evecm/src/ide/` (aggregated by `code/evecm/src/ide.zig`, also `evecm.ide`) and both `evetx` and `eveux` import them as the module `ide`; their tests run in the root `zig build test`.
- `code/eveux/` **the Eve native workbench** (F-TLS-19 to F-TLS-22, D-193): the graphical development client of the Eve machine, a native Zig program on the GUI library dvui (Windows first, then Linux and macOS), a client like evetx on the stdio door. **Working model (D-195):** code is local; a tested project is deployed to a machine and then operated (schedules, evewp), never edited or run by hand there; one tool bar follows the file kind (`code/eveux/design/design-toolbar.svg`). **Design and a first draft** (2026-10-18): `code/eveux/README.md` (design, reuse from evetx, the code, plan), `code/eveux/design/` (SVG drawings written by `design/gen_svg.py`, notes: the author's `design-ideas.md`, `elaboration.md`, `dvui.md`), `code/eveux/src/` (six logic files with unit tests: `zig test --dep ide -Mroot=<file> -Mide=../evecm/src/ide.zig` from `code/eveux/`; the window files build with Developer Mode on, which dvui needs to be fetched: `cd code/eveux && zig build -p ../..` or `./run.sh ux` installs `bin/eveux.exe`; `eve -ux [folder]` starts it, like `-tx` starts evetx). An independent tool, not part of the specification. Same Zig comment rules as `code/evevm/`.
- `code/evewp/` **the Eve Web Portal** (F-WEB-05 to F-WEB-07, F-VM-12, level 7, D-193): the production web layer **written in Eve** with no JavaScript: edge (hosts by domain and subdomain, static files, proxy), host (applications in folders, versions, supervision, deploy), monitor (health, traffic, domains), and the Eve Web framework (Eve compiled to WebAssembly for the browser). It is the final test and stress test of the language (the role of D-154, which it replaces). **Design only**: `code/evewp/README.md`; the old browser Workbench design is `design/archive/workbench-design.md`; the author's notes are `code/evewp/wp-design-ideas.md`; tutorial page `evewp.html`.
- **SQLite is the core database**, compiled into the VM from the amalgamation (3.54.0, dependency `sqlite` of the root `build.zig.zon`; binding `code/evevm/src/db/sqlite.zig`, linked into the module `evedb` only; `eve.exe` gets it through `cmd`). Zig 0.17 keeps fetched packages in `zig-pkg/` (git-ignored); the first build compiles SQLite (about 3 minutes), later builds use the cache.
- `spec/` **the Eve specification being written**: Markdown + JSON, normative. Conventions in
  `spec/README.md`.
- `design/version_map.md` **one file to track the project** (D-138): levels, versions and every feature (`F-<area>-<nn>`) with its status; update it when a feature is done or moved.
- `design/` (was `plan/`, 2026-10-19) **the plan and the design**: the phases (`phase-*.md`), the design notes (`design-*.md`), the version map, the release policy (`release.md`), how the manual is made (`manual.md`). For improvement work run `python script/plan.py status` (open steps and questions, ~50 lines; don't read the logs whole), take the next open step, and update its status mark when done (rules: `design/README.md`). Subfolders:
  - `design/decision/level1.md` … `level7.md`: the decisions and open questions for the author (ids shared); settled entries in `design/decision/archive/`; `python script/plan.py show D-087` prints one entry from either place.
  - `design/issues/` one file per tutorial page: questions and fixes from the page review (T1.10); the author answers by editing `**Answer:**` lines; answers become decisions.
  - `design/review/` the review prompts and reviews; `design/archive/` superseded designs; `design/template/` the templates of the generators (release notes, the generated manual pages, the distribution README, an issue page).
- `backlog/` **work not scheduled yet**: `tech-debt.md` (TD-nn), `library-gaps.md` (G-n), `ideas.md` (ideas and reserved words without a design), `tools-tech-debt.md`, and the notes of the components (`evedb-ideas*.md`, `evetx-requests.md`, `evetx-status.md`, `vscode-plugin.md`); index in `backlog/README.md`.
- `comp/<component>/doc/` **the user documentation of each component** (`evevm`, `evecp`, `evecm`, `evetx`, `eveux`, `evewp`; the drivers have `drivers/<name>/doc/`, copied into `manual/drivers/<name>/`); `comp/<component>/README.md` stays the design and the state of the work. `script/genmanual.py` copies each `doc/` into `manual/<component>/`: edit the original, never the copy. A doc links to the other manual pages as they sit in the manual (`../usage.md`), so check links in `manual/`, not in the source folder. `code/evetx/doc/*.txt` are also embedded in `evetx.exe` (its help windows).
- `demo/` **deleted** (D-099): every demo has a home in `test/level1/` or in the tutorial (`tutorial/demo/`, datetime.html); the list is the tutorial page `examples.html` (Demos & Examples). `test/level1-7/` conformity tests, expectations in `/*@expect*/` blocks
- `manual/` **the user manual**, shipped in every distribution, so it names no folder of the repository (`design/`, `backlog/`, `test/`, `script/`). By hand: `README.md` (front page), `usage.md`, the notes `release/vX.Y.Z.md`. Generated by `script/genmanual.py`: `features.md`, `tests.md`, `performance.md` and `manual/<component>/`. How it is made: `design/manual.md`; the release policy: `design/release.md` (D-153).
- `dist/` **git-ignored**, written by `./run.sh dist` (`script/dist.py`): the current release unzipped (`dist/eve-X.Y.Z-windows-x64/`), its zip and `SHA256SUMS.txt`, older zips in `dist/archive/`; `./run.sh release` publishes the zip with `gh`.
- `script/` Python scripts: the test runner (`runtest.py`) and the token-saving utilities below.
- `tools/` typing aids (`alt-codes.md`), the editor plugins (`zed-eve/`, `vscode-eve/`, `tree-sitter-eve/`) and their debt (`backlog/tools-tech-debt.md`)
- `tutorial/` **junction** to `C:\Users\eluci\sage-code\scl\projects\eve`: the published Eve
  tutorial (44 topic pages), owned by the `scl` repo. See "Tutorial" below.
- Eve file shape: line 1 is `#!` (free script), `#` title or `##` subtitle; then `driver name is`
  … `  process main is` … `  return;`, `end name;`. Comments: `#`/`##` at column 0, `**` to end of line, `(** … **)`
  expression, `/* … */` block (no nesting). `--` and `+- -+` boxes are gone (D-011, D-014).
  Control flow: D-016 in `design/decision/level1.md`.
- **Line endings:** LF everywhere (`.gitattributes`: `* text=auto eol=lf`, which overrides `core.autocrlf=true`); CRLF only for Windows scripts (`.bat`, `.cmd`, `.ps1`). New files are written LF. A `#!` script must be LF to run on Unix.
- **Markdown prose is not hard-wrapped:** one line per paragraph and per list item (an author answer or a `(a)` item keeps its own line). To reflow a wrapped file: `python temp/unwrap_md.py <files>`.

## VM workflow: speed and performance watch

- **Test with the ReleaseSafe build** (about 4.6 times faster than Debug). Build it once per change: `zig build -Doptimize=ReleaseSafe -p temp/rel` (from the root), then run the tests with `python script/runtest.py 1 --eve temp/rel/bin/eve.exe` (also `all`, `smoke`). Use the Debug build (`zig build -p ../..`, `bin/eve.exe`) only to debug a failure: it keeps safety checks and stack traces readable.
- **Watch performance at every feature or optimization of the VM.** Before and after the change run `python script/bmark.py --build ReleaseSafe --eve temp/rel/bin/eve.exe` (add `--check` to fail on a slowdown above 25%). When a version is done, run it with `--save` (updates `test/bmark/history.json` and the table of the README) and add a paragraph to "Notes by version" in `test/bmark/README.md`: what changed, appreciation or depreciation, and why a drop of more than 10% happened. `--save` also records the size of `eve.exe` (table "Size of eve.exe"); explain a growth of more than 10%. Compare only runs of the same build on the same machine.
- **Profile with `EVE_PROFILE=1`** (`code/evevm/src/profile.zig`, Windows): `EVE_PROFILE=1 temp/rel/bin/eve.exe -x file.eve` prints the functions with the most samples to the error output; use it before an optimization to see where the time goes, and run `fib(29)`-size loads to get a few hundred samples.
- **Two engines (D-201, `design/design-bytecode.md`):** the tree walker is the reference, the register machine (`code/evecm/src/op.zig`, `chunk.zig`, `code/evecp/src/emit.zig`, `code/evevm/src/bcvm.zig`) is under construction and runs what it translates, the rest through a bridge (TD-46). `--engine bc` or `EVE_ENGINE=bc` selects it; `python script/runtest.py all --both` and `python script/bmark.py --both` must stay green and equal; `eve --disasm file.eve` lists the bytecode and `python script/bctest.py` compares the listings of `test/bytecode/` with their goldens. A change of the emitter or of the interpreter runs `--both` before the commit.
- **Memory of the VM** (D-151, `code/evevm/src/heap.zig`): values are reference counted; every place that stores a value in the interpreter counts it (`setVar`, `setCell`, `listAppend`, `setField`, `mapPut`) and lets the old one go. After a change to how the interpreter stores values, run the suite on the Debug build with `EVE_GC_VERIFY=1 python script/runtest.py all`: it checks every free against a trace and stops on a value that a holder forgot to count. `EVE_MEMSTATS=1` prints what the heap made, freed and kept; `bmark.py` reports the peak memory of each benchmark.
- **Every benchmark has a twin in Python** (`test/bmark/ref/<name>.py`); the report shows the ratio Eve / Python. Level 6 (`p6a` to `p6d`: evedb column batches, bulk load, records over PostgreSQL, OLAP group-by) needs `evedb.exe` beside `eve.exe` (for `temp/rel`: `zig build -Doptimize=ReleaseSafe -p ../../temp/rel` in `drivers/duckdb/`); `bmark.py` starts it with `test/bmark/evedb.cfg` and stops it; the twins need psycopg2. A new level or a new kind of work adds a benchmark `p<level><letter>_<name>.eve` with its twin and a `** perf:` description line.
- **Optimization is rank 5 of the order** (D-194; the "do not optimize early" rule of 2026-10-07 ended when level 2 passed). Measure before and after, as above. Slot-resolved variables wait for the final scope rules. Fix first any benchmark that falls more than 10 times behind Python, it points to an accidental quadratic cost. The first planned optimization is variable lookup by slot, resolved in `check.zig`.

## Releases (D-153; full policy and steps: `design/release.md`)

A release is made only when the author asks for it ("release", "cut 0.0.3"). Then follow the steps of `design/release.md` in order, and stop at the first one that fails: report it, don't work around it.

- **Before:** the tree is committed (`git status` clean); otherwise ask whether to commit the work first or leave it out of the release.
- **Order matters:** `script/release.py` (bump, build, unit tests) → `runtest.py all` on the ReleaseSafe build → `bmark.py --save` and its paragraph in `test/bmark/README.md` → statuses in `design/version_map.md` → `script/relnotes.py` → hand-written parts → `relnotes.py --check` and `mdlinks.py check manual` → commit and tag. `relnotes.py` reads what the earlier steps saved (`status.json`, `history.json`, `version_map.md`); run it earlier and the notes show stale numbers.
- **Generated, never hand-edited:** the `GEN:` blocks of `manual/releases/vX.Y.Z.md`, `manual/README.md`, `manual/releases/README.md`, and the pages `manual/features.md`, `tests.md`, `performance.md`, `manual/<component>/`. A wrong stage is fixed in the row of `version_map.md`, then the notes are generated again.
- **Written by hand** (every `TODO` of the notes): Highlights in plain words with feature codes; Decisions (the `D-nnn` settled since the previous release: compare `python script/plan.py list` with the Decisions of the previous notes); Breaking changes and migration; Known issues (failing tests with their reason, features that went back a stage); Performance notes (two to four lines from the bmark paragraph). Also update the manual pages that describe what changed (`manual/usage.md` for commands and options).
- **Facts only:** numbers come from the generated blocks; never round them up, never call a feature validated whose tests fail. A drop in speed above 10% is explained, not hidden.
- **A tagged release is a record:** never edit `vX.Y.Z.md` after its tag (`relnotes.py` refuses); a correction goes into the next notes.
- **Commit and tag** only on the author's word: `git commit -am "Release X.Y.Z"`, `git tag vX.Y.Z`; the tutorial pages that `runtest.py`/`bmark.py` regenerated are committed in the scl repo (`git -C tutorial`). Don't push unless asked.
- **Between releases** `python script/relnotes.py --manual` refreshes the progress paragraph of the manual from the working tree (it says "not a release").
- **Links in `manual/`:** only to pages of `manual/` (relative, exact case: Windows hides a wrong case, GitHub does not); the specification as `https://github.com/elucian/eve-lang/blob/master/spec/<page>.md`, the tutorial as `https://sagecode.org/projects/eve/<page>.html`. Never a path to `design/`, `backlog/` or `test/`: the manual travels in the distribution.

## Tutorial (`tutorial/` → scl repo)

The tutorial is the reference that the new specification in this repo builds on. It is
maintained here but **versioned in the scl repo** (branch `main`). It is git-ignored in eve-lang.

- Edit files through `tutorial/…` as usual. Commit with `git -C tutorial …`, which resolves to the
  scl repo. Never `git add` it from eve-lang.
- Pages are large (up to ~1,600 lines). Run `outline.py tutorial/<page>.html --depth 3` first,
  then read by line range. `repomap.py tutorial --ext .html` lists all the pages with titles.
- Links are followed only when named: `bee-ed … tutorial` and `outline.py tutorial` enter it;
  a plain `*.html`, or a script run on `.`, stays inside eve-lang.
- **Headings and sidebar:** every `<h1>`/`<h2>`/`<h3>` of a page has an `id`; when you change a page, update its navigation bar in `tutorial/data/<page>.json` (h1 = root, h2 = children, h3 = children of their h2, `"link": "#<id>"`).
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
| Tutorial pages of the tests (`features.html`, `quality.html`) | `python script/genpages.py [--check]`; **generated**: `runtest.py` and `bmark.py --save` call it, never edit the part between `GEN:BEGIN` and `GEN:END` by hand (D-136) |
| Run tests on the VM (TDD) | `python script/runtest.py 1` / `all` / `a03` → reports in `temp/output/` |
| Performance of the VM (per level) | `python script/bmark.py [--save]` → `test/bmark/`, notes per version in its README |
| Release notes, progress and links of the manual | `python script/relnotes.py [X.Y.Z] [--manual] [--check]` → `manual/releases/vX.Y.Z.md`, `manual/README.md` (D-153) |
| Generated pages of the manual, copies of the component docs | `python script/genmanual.py [--out DIR] [--check]`; all generated docs at once: `./run.sh build manual` |
| Distribution (zip, archive of older ones) and its publication | `./run.sh dist` (`script/dist.py`), `./run.sh release` (`script/publish.py`, needs `gh`) |

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
