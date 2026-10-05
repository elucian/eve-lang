# Phase 7 — Compiler Manual

Goal: `manual/` documents an Eve implementation: how to implement it, how to use it, what was implemented, and which spec features it supports, in tables generated from `spec/`. Layout and conventions are in `manual/README.md`. Decision: D-004.

### M7.1 Rename `docs/` to `manual/` `[x]`
2026-09-28: `docs/index.md` → `manual/README.md` (rewritten as the manual's conventions), 20 empty stub pages and `doc.sh` removed, links in `README.md` and `CLAUDE.md` updated.

### M7.2 Support schema `[ ]` (after S2.2)
- `manual/schema/support.schema.json`: `implementation`, `version`, `specVersion`, `features` (map of feature id → `{ status, note?, since? }`).
- Extend `speccheck.py`, or add a manual check, so every support file validates.

### M7.3 Feature table generator `[ ]` (after S2.2 and one spec JSON file, e.g. S2.4)
- `manual/generate.py` (stdlib only): reads `spec/**/*.json`, the `ebnf` blocks in `spec/syntax/` and `manual/support/*.json`; writes `manual/features/*.md`.
- One table per source; rows = feature id, spec status, spec link; one column per implementation.
- `features/README.md`: counts per category and implementation (yes / partial / planned / no).
- `--check`: exit 1 when a generated file is stale or a support file names an unknown feature id.
- Done when: `python manual/generate.py --check` exits 0, and editing a spec JSON item makes it exit 1 until the generator runs again.

### M7.4 Grammar rows `[ ]` (after S3.6)
- Extract rule names from `ebnf` blocks (`name = … ;`) so each grammar rule becomes a row.
- Link each row to the heading that holds the block.

### M7.5 How to implement: `implement.md` `[ ]`
- Architecture of the Zig VM (D-006): lexer, parser, checker, the VM's internal code form
  (bytecode or tree), interpreter loop, runtime and memory management.
- Zig specifics: toolchain version, `zig build` steps, the `evevm/` source layout, and how the build installs `bin/eve.exe` (D-007).
- Milestones M1–M7 from `tutorial/compiler.html`, each mapped to spec files and the test level it must pass. This takes over S6.1: the compiler kit lives here, and the tutorial page links to it.

### M7.6 How to use: `usage.md` `[ ]` (after S6.2)
- Command line of `bin/eve.exe`, options, exit codes, diagnostics format. Must include the test-runner contract from S6.2, so the conformance runner can drive the implementation.
- Running a script directly: shebang line `#!/usr/bin/env eve` plus `chmod +x` on Unix, file association for `.eve` on Windows (D-008).

### M7.7 What was implemented: `implemented.md` `[ ]` (from the first compiler release, D-005)
- Release notes per version: features added (as feature ids), spec version, conformance level.
- No implementation exists yet (D-005); start the file with the first release.

### M7.8 Library guides `[ ]` (after S5.1)
- The old stubs covered database, network, OS and standard-library topics. Recreate them as usage guides only when `spec/library/` defines those modules, each with its generated table.
