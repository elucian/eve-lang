# Phase 6 — Compiler Track for Students

Goal: a student can pick an implementation language, build an Eve compiler or interpreter in stages, and prove it with the conformance suite. The public entry point is the tutorial page `tutorial/compiler.html` (T1.1).

### S6.1 Compiler kit `[-]`
- Moved to M7.5 (`manual/implement.md`, D-004): how to implement belongs in the manual, not in the normative spec.

### S6.2 Test-runner contract `[~]`
2026-09-28: runner exists as `script/runtest.py` (D-009): `<eve> <file.eve> [args]` from the repo root, exit code and stdout compared, `--eve` selects the implementation. Still open: write the contract down in `spec/conformance/README.md` and settle Q-005 and Q-010.
- A command-line contract every implementation provides, for example `<impl> run <file.eve>`, with exit code 0 on success and stdout compared to the expected output. The contract is defined here; each manual documents it in `usage.md` (M7.6).
- ~~`conformance/run.py`~~ `script/runtest.py`: runs the suite against any implementation that follows the contract, and prints a pass/fail table per level.

### S6.3 Compiler registry `[ ]`
- `spec/conformance/compilers.json`: `name`, `author`, `language`, `repo`, `specVersion`,
  `levelPassed`, `lastVerified`.
- Rendered on the compiler page as a table (generated, not hand-edited).

### S6.4 Approval process `[ ]`
- Turn the "Approval" idea in `test/readme.md` into rules: who verifies, how results are
  published, and how a compiler loses approval when the spec moves on.

### S6.5 Sample implementation notes `[ ]`
- Per recommended language: a short "starter" note with project layout, lexer and parser approach, and libraries. Written only after S3.6, so it reflects the real grammar.
