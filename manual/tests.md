# Tests

The behavior of `eve` is settled by conformance tests: each test is an Eve program with the output it must give. The **levels** follow the versions of Eve (level 1 is the language of one script, level 2 programs made of several files, level 3 modules and classes, level 4 parallel work and generics, level 5 the data language and the database, level 6 the machine and the server, level 7 the web). The **smoke** suite runs the main features together, in a few larger programs. The **bytecode** suite tests the bytecode machine, and **scaffold** the commands that make a new project.

## Summary

<!-- GEN:summary -->
625 of 626 tests pass; last run 2026-10-26 03:05.

| Suite | Tests | Pass | Fail | % | Last run |
|---|---|---|---|---|---|
| Level 1 | 97 | 97 | 0 | 100% | 2026-10-25 |
| Level 2 | 81 | 81 | 0 | 100% | 2026-10-25 |
| Level 3 | 129 | 129 | 0 | 100% | 2026-10-26 |
| Level 4 | 62 | 61 | 1 | 98% | 2026-10-26 |
| Level 5 | 195 | 195 | 0 | 100% | 2026-10-26 |
| Level 6 | 14 | 14 | 0 | 100% | 2026-10-25 |
| Level 7 | 2 | 2 | 0 | 100% | 2026-10-25 |
| Smoke | 21 | 21 | 0 | 100% | 2026-10-25 |
| Bytecode | 24 | 24 | 0 | 100% | 2026-10-26 |
| Scaffold | 1 | 1 | 0 | 100% | 2026-10-20 |
| **All** | **626** | **625** | **1** | **99%** |  |
<!-- /GEN:summary -->

## Tests that do not pass

<!-- GEN:failing -->
| Suite | Test | Status | What it tests | Reason |
|---|---|---|---|---|
| Level 4 | `d49_max_parallel` | FAIL | $cores is the number of hardware cores (1 to 16) and $max_parallel the tasks of a group that run at a time (default 8): a start beyond it waits until a task of the group has ended | exit code 65, expected 0; stdout differs |
<!-- /GEN:failing -->
