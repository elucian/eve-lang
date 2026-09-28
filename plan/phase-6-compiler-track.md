# Phase 6 — Compiler Track for Students

Goal: a student can pick an implementation language, build an Eve compiler or interpreter in
stages, and prove it with the conformance suite. The public entry point is the tutorial page
`tutorial/compiler.html` (T1.1).

### S6.1 Compiler kit `[ ]`
- `spec/conformance/compiler-kit.md`: milestones M1–M7 (as on the tutorial page), each mapped
  to the spec files and the test level it must pass.

### S6.2 Test-runner contract `[ ]`
- A command-line contract every implementation provides, for example `<impl> run <file.eve>`,
  with exit code 0 on success and stdout compared to the expected output.
- `conformance/run.py`: runs the suite against any implementation that follows the contract,
  and prints a pass/fail table per level.

### S6.3 Compiler registry `[ ]`
- `spec/conformance/compilers.json`: `name`, `author`, `language`, `repo`, `specVersion`,
  `levelPassed`, `lastVerified`.
- Rendered on the compiler page as a table (generated, not hand-edited).

### S6.4 Approval process `[ ]`
- Turn the "Approval" idea in `test/readme.md` into rules: who verifies, how results are
  published, and how a compiler loses approval when the spec moves on.

### S6.5 Sample implementation notes `[ ]`
- Per recommended language: a short "starter" note with project layout, lexer and parser approach,
  and libraries. Written only after S3.6, so it reflects the real grammar.
