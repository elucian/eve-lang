# Tests

The behavior of `eve` is settled by conformance tests: each test is an Eve program with the output it must give. The **levels** follow the versions of Eve (level 1 is the language of one script, level 2 programs made of several files, level 3 modules and classes, level 4 parallel work and generics, level 5 the data language and the database, level 6 the machine and the server, level 7 the web). The **smoke** suite runs the main features together, in a few larger programs. The **bytecode** suite tests the bytecode machine, and **scaffold** the commands that make a new project.

## Summary

<!-- GEN:summary -->
556 of 557 tests pass; last run 2026-10-25 14:34.

| Suite | Tests | Pass | Fail | % | Last run |
|---|---|---|---|---|---|
| Level 1 | 96 | 96 | 0 | 100% | 2026-10-25 |
| Level 2 | 81 | 81 | 0 | 100% | 2026-10-25 |
| Level 3 | 81 | 81 | 0 | 100% | 2026-10-25 |
| Level 4 | 50 | 50 | 0 | 100% | 2026-10-25 |
| Level 5 | 187 | 186 | 1 | 99% | 2026-10-25 |
| Level 6 | 14 | 14 | 0 | 100% | 2026-10-25 |
| Level 7 | 2 | 2 | 0 | 100% | 2026-10-25 |
| Smoke | 21 | 21 | 0 | 100% | 2026-10-25 |
| Bytecode | 24 | 24 | 0 | 100% | 2026-10-25 |
| Scaffold | 1 | 1 | 0 | 100% | 2026-10-20 |
| **All** | **557** | **556** | **1** | **99%** |  |
<!-- /GEN:summary -->

## Tests that do not pass

<!-- GEN:failing -->
| Suite | Test | Status | What it tests | Reason |
|---|---|---|---|---|
| Level 5 | `e129_meta_zone` | FAIL | the library zone over the meta database: exists, canonical, offset, abbreviation, is_dst, names; the entries of meta.info; errors | exit code 2, expected 0; stdout differs |
<!-- /GEN:failing -->
