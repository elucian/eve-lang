# Tests

The behavior of `eve` is settled by conformance tests: each test is an Eve program with the output it must give. The **levels** follow the versions of Eve (level 1 is the language of one script, level 2 programs made of several files, level 3 modules and classes, level 4 parallel work and generics, level 5 the data language and the database, level 6 the machine and the server, level 7 the web). The **smoke** suite runs the main features together, in a few larger programs. The **bytecode** suite tests the bytecode machine, and **scaffold** the commands that make a new project.

## Summary

<!-- GEN:summary -->
648 of 649 tests pass; last run 2026-10-27 23:04.

| Suite | Tests | Pass | Fail | % | Last run |
|---|---|---|---|---|---|
| Level 1 | 97 | 97 | 0 | 100% | 2026-10-25 |
| Level 2 | 81 | 81 | 0 | 100% | 2026-10-27 |
| Level 3 | 129 | 129 | 0 | 100% | 2026-10-26 |
| Level 4 | 62 | 62 | 0 | 100% | 2026-10-27 |
| Level 5 | 197 | 197 | 0 | 100% | 2026-10-27 |
| Level 6 | 16 | 15 | 1 | 93% | 2026-10-27 |
| Level 7 | 2 | 2 | 0 | 100% | 2026-10-25 |
| Smoke | 21 | 21 | 0 | 100% | 2026-10-25 |
| Bytecode | 43 | 43 | 0 | 100% | 2026-10-27 |
| Scaffold | 1 | 1 | 0 | 100% | 2026-10-20 |
| **All** | **649** | **648** | **1** | **99%** |  |
<!-- /GEN:summary -->

## Tests that do not pass

<!-- GEN:failing -->
| Suite | Test | Status | What it tests | Reason |
|---|---|---|---|---|
| Level 6 | `f18_route_register` | ERROR | a Route registers itself when it is made: a static route with set, a dynamic one with new in main, no table passed to the service (F-STR-08) | timeout after 10s |
<!-- /GEN:failing -->
