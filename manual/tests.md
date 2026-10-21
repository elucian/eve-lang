# Tests

The behavior of `eve` is settled by conformance tests: each test is an Eve program with the output it must give. The **levels** follow the versions of Eve (level 1 is the language of one script, level 2 programs made of several files, level 3 modules and classes, level 4 parallel work and generics, level 5 the data language and the database, level 6 the machine and the server, level 7 the web). The **smoke** suite runs the main features together, in a few larger programs. The **bytecode** suite tests the bytecode machine, and **scaffold** the commands that make a new project.

## Summary

<!-- GEN:summary -->
443 of 443 tests pass; last run 2026-10-21 11:12.

| Suite | Tests | Pass | Fail | % | Last run |
|---|---|---|---|---|---|
| Level 1 | 78 | 78 | 0 | 100% | 2026-10-21 |
| Level 2 | 78 | 78 | 0 | 100% | 2026-10-20 |
| Level 3 | 62 | 62 | 0 | 100% | 2026-10-20 |
| Level 4 | 50 | 50 | 0 | 100% | 2026-10-20 |
| Level 5 | 117 | 117 | 0 | 100% | 2026-10-20 |
| Level 6 | 14 | 14 | 0 | 100% | 2026-10-21 |
| Level 7 | 2 | 2 | 0 | 100% | 2026-10-20 |
| Smoke | 21 | 21 | 0 | 100% | 2026-10-20 |
| Bytecode | 20 | 20 | 0 | 100% | 2026-10-21 |
| Scaffold | 1 | 1 | 0 | 100% | 2026-10-20 |
| **All** | **443** | **443** | **0** | **100%** |  |
<!-- /GEN:summary -->

## Tests that do not pass

<!-- GEN:failing -->
None: every test of the last run passes.
<!-- /GEN:failing -->
