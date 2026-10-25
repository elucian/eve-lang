# Tests

The behavior of `eve` is settled by conformance tests: each test is an Eve program with the output it must give. The **levels** follow the versions of Eve (level 1 is the language of one script, level 2 programs made of several files, level 3 modules and classes, level 4 parallel work and generics, level 5 the data language and the database, level 6 the machine and the server, level 7 the web). The **smoke** suite runs the main features together, in a few larger programs. The **bytecode** suite tests the bytecode machine, and **scaffold** the commands that make a new project.

## Summary

<!-- GEN:summary -->
556 of 558 tests pass; last run 2026-10-25 15:01.

| Suite | Tests | Pass | Fail | % | Last run |
|---|---|---|---|---|---|
| Level 1 | 97 | 96 | 1 | 98% | 2026-10-25 |
| Level 2 | 81 | 81 | 0 | 100% | 2026-10-25 |
| Level 3 | 81 | 81 | 0 | 100% | 2026-10-25 |
| Level 4 | 50 | 50 | 0 | 100% | 2026-10-25 |
| Level 5 | 187 | 186 | 1 | 99% | 2026-10-25 |
| Level 6 | 14 | 14 | 0 | 100% | 2026-10-25 |
| Level 7 | 2 | 2 | 0 | 100% | 2026-10-25 |
| Smoke | 21 | 21 | 0 | 100% | 2026-10-25 |
| Bytecode | 24 | 24 | 0 | 100% | 2026-10-25 |
| Scaffold | 1 | 1 | 0 | 100% | 2026-10-20 |
| **All** | **558** | **556** | **2** | **99%** |  |
<!-- /GEN:summary -->

## Tests that do not pass

<!-- GEN:failing -->
| Suite | Test | Status | What it tests | Reason |
|---|---|---|---|---|
| Level 1 | `a116_eve_dir_asp` | FAIL | the variables $EVE_DIR (the folder of the Eve runtime) and $EVE_ASP (the aspect folder, "asp" by default) are read-only Strings | exit code 4, expected 0; stdout differs |
| Level 5 | `e132_meta_sql` | FAIL | the meta database as a read only SQL database: database.connect("meta") needs no eve.cfg; joins with the tables of the user's own data; a write is refused | exit code 4, expected 0 |
<!-- /GEN:failing -->
