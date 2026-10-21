# Eve language repository

Eve is a domain-specific scripting language (data processing, test automation). This repo holds the language **examples, spec and manual** and the first implementation: the Eve virtual machine in Zig 0.17, built to `bin/eve.exe`. Status, test counts and features: `spec/features/`, `python script/plan.py status`. **Full guide (every rule that is not here): `design/dev-guide.md`**; read it by section (`python script/outline.py design/dev-guide.md`), never whole.

## Build and test (from the repository root)

- Build: `zig build -p .` (Debug, `bin/eve.exe`); unit tests: `zig build test`. Version: `build.zig.zon`. First build: SQLite, about 3 minutes.
- **Test on ReleaseSafe** (4.6 times faster): `zig build -Doptimize=ReleaseSafe -p temp/rel`, then `python script/runtest.py 1 --eve temp/rel/bin/eve.exe` (`1`..`6`, `all`, `smoke`, one test name). Debug only to debug a failure.
- Two engines (D-201): every conformance test runs on the tree walker only; the bytecode machine has its own tests, `python script/bctest.py` (golden listings and `runtest.py bytecode`), and the benchmarks run on it. Run `bctest.py` after a change of `emit.zig`, `op.zig` or `bcvm.zig`; `runtest.py all --both` before a release (`test/readme.md`).
- Spec, tests, manual: `python generator/evegen.py all` writes `spec/spec.json` and the manual; `python generator/evegen.py check` verifies the links and the separation.
- Performance: before and after a VM change run `python script/bmark.py --build ReleaseSafe --eve temp/rel/bin/eve.exe --check`. Details: `design/dev-guide.md` "VM workflow".
- Parts with their own `build.zig` (`drivers/duckdb`, `code/evetx`, `code/eveux`): `./run.sh build <part>`.

## Layout (one line each; details in the README of the folder)

- `code/` the components, `code/README.md`: `evecm` (common), `evecp` (compiler), `evevm` (runtime), `eve` (command), `evetx` (terminal IDE), `eveux` (native workbench), `evewp` (web portal, design only). Each has `README.md` (design, state) and `doc/` (user docs, copied to `manual/<component>/` by `generator/evegen.py`: edit the original). License: `code/LICENSE`.
- `drivers/duckdb/` the Eve test database (evedb); client drivers are in `code/evevm/src/db/`.
- `spec/` the specification (Markdown + JSON, normative; conventions in `spec/README.md`); `spec/features/` the features per level; `spec/spec.json` the index of pages and sections. `lib/` the standard library in Eve. `test/level1-7/` conformity tests (`/*@expect*/` blocks), each suite with a tracking file `test/<suite>/<suite>.json` (its `features` field links a test to the spec), `test/bmark/` benchmarks. The spec, the tests and the manual never name `design/`; only `generator/evegen.py` reads spec and tests and writes the manual.
- `design/` the plan and the design (`README.md`, `phase-8-architecture.md`, `design-*.md`, `decision/levelN.md` open questions and newest decisions, `decision/index.md` settled ones, `release.md`, `manual.md`). `backlog/` unscheduled work (`tech-debt.md`, `library-gaps.md`, `ideas.md`).
- `manual/` the user manual, shipped in every distribution: it names no folder of the repo (`design/`, `test/`, `script/`). `script/` Python tools. `tools/` editor plugins. `dist/`, `temp/` git-ignored.
- `tutorial/` junction to the scl repo (published tutorial, last in the order of work). Commit it with `git -C tutorial`; never `git add` it here. Rules: `design/dev-guide.md`.
- Eve file shape (D-179): line 1 is a `#` title or `##` subtitle (no `#!`, no `driver`); then `primary aspect name is` … `  process main is` … `  return;`, `end name;`. Skills: `eve-primer` (language), `eve-test-loop` (build, tests), `zig-split-file`.

## Rules of the work

- **Order (D-194):** (1) plan, (2) design, (3) user interfaces, (4) refactor, (5) optimize, (6) test, (7) spec, (8) compiler, (9) manual, (10) tutorial last. Take the next piece from the highest rank with open work. The spec follows the tests. An interface feature starts with a drawing; a language feature with a feature entry and a failing test; a refactor or optimization with a measure before and after (D-196).
- **Technical debt:** every shortcut or postponed piece gets a line in `backlog/tech-debt.md` (id, what, why, where, when to pay) in the same commit; language gaps found by the library go in `backlog/library-gaps.md`.
- **Commit on `master`**, no branches. Commit and push only when asked. A release only when asked: follow `design/release.md` step by step and stop at the first failure.
- **Line endings:** LF everywhere (`.gitattributes`); CRLF only for `.bat`, `.cmd`, `.ps1`. **Markdown:** one line per paragraph and list item.
- **Scratch files go in `temp/`**, never the system temp.
- **Authors own the syntax and decisions:** do not replace the author's syntax with a proposal; raise a question (`design/decision/`), let the author decide.

## Code written for AI (D-190, extended by `design/design-ai-context.md`)

The Zig modules and the Eve library (`lib/`) are read by AI that searches: write code cheap to find and to read, linked to the specification:

- **Link code to spec.** Every new, refactored or touched function, type, test and file carries `grep`-able tags in consecutive `//` lines above any `///` comment (in Eve files: `**` lines), one tag per line, **exact values** (real path, real id, real name):
  - file head: `//! @eve-module <name>`, `//! @spec <path>#<anchor>`, `//! @feature F-XXX-nn`, `//! @decision D-nnn`, `//! @tests test/levelN/<name>`, then a one-line `//!` purpose.
  - function or type: `// @eve-fn <module>.<name>` (the Eve-visible name) or `// @eve-impl <what>`; `// @spec <path>#<anchor>` (the exact rule it implements); `// @feature`; `// @decision`; `// @test <test name>`; `// @perf hot`; `// @invariant <fact that must hold>`; `// @see <file>:<symbol>` (the other side of a contract).
  - Only the tags that apply. No spec anchor yet: write the page and anchor or add a line to `backlog/tech-debt.md`. Add a missing tag whenever you touch the code. Search: `grep -rn "@feature F-NET-02"`. `python script/tagcheck.py` checks every `@spec`, `@feature` and `@decision` (the pre-commit hook runs it).
- **Comments say what, where and why, never how Zig works.** No teaching comments, no `// Zig tip:`, no comment that repeats the code. A comment over three lines belongs in `design/` or a README: link it with `@see`.
- **Shape for search:** one concern per file, and split a file that passes about 800 lines before adding to it; unique, descriptive names (no `helper`, `util`, `tmp`); tests next to the code they cover, named after the rule (`test "spec: <anchor> ..."`).

## Budget of the context (read less, edit exactly)

1. **Orient cheaply:** `python script/repomap.py [dir]`, `python script/outline.py <file> --depth 2`, then Read with `offset`/`limit`. Never read `design/decision/level*.md`, `spec/spec.json` or `manual/*.md` generated pages whole: `python script/plan.py show D-nnn`, `plan.py status`, `plan.py feature F-XXX-nn`, `plan.py features open 6` (one line per feature). A feature's status is its `status` in `spec/features/<level>.json`; `spec/spec.json` gives the line of each section of the spec. Measure the context: `python script/ctxsize.py`.
2. **Search before reading:** Grep tool; for a feature, grep its tag (`@feature`, `@spec`) to land on the code and the rule at once.
3. **Edit without re-reading:** `python script/multiedit.py` (several edits, atomic), `python script/splice.py` (by line number), `bee-ed edit|sed|search|append` (tools and quirks: `design/dev-guide.md` "Which tool" and "bee-ed notes"). Write patch scripts to `temp/*.py` with raw strings; quote regexes (an unquoted backslash is lost in the shell).
4. **Verify with summaries**: `git diff --stat`, `git diff -U1 <file>`, test summaries (`temp/output/`); do not re-read an edited file.
5. **Do not spawn sub-agents** unless the author asks; they start cold and cost more than a direct search.
