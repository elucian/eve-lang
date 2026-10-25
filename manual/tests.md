# Tests

The behavior of `eve` is settled by conformance tests: each test is an Eve program with the output it must give. The **levels** follow the versions of Eve (level 1 is the language of one script, level 2 programs made of several files, level 3 modules and classes, level 4 parallel work and generics, level 5 the data language and the database, level 6 the machine and the server, level 7 the web). The **smoke** suite runs the main features together, in a few larger programs. The **bytecode** suite tests the bytecode machine, and **scaffold** the commands that make a new project.

## Summary

<!-- GEN:summary -->
541 of 548 tests pass; last run 2026-10-25 11:14.

| Suite | Tests | Pass | Fail | % | Last run |
|---|---|---|---|---|---|
| Level 1 | 96 | 96 | 0 | 100% | 2026-10-24 |
| Level 2 | 81 | 81 | 0 | 100% | 2026-10-24 |
| Level 3 | 80 | 80 | 0 | 100% | 2026-10-24 |
| Level 4 | 50 | 50 | 0 | 100% | 2026-10-24 |
| Level 5 | 179 | 172 | 7 | 96% | 2026-10-25 |
| Level 6 | 14 | 14 | 0 | 100% | 2026-10-24 |
| Level 7 | 2 | 2 | 0 | 100% | 2026-10-24 |
| Smoke | 21 | 21 | 0 | 100% | 2026-10-24 |
| Bytecode | 24 | 24 | 0 | 100% | 2026-10-25 |
| Scaffold | 1 | 1 | 0 | 100% | 2026-10-20 |
| **All** | **548** | **541** | **7** | **98%** |  |
<!-- /GEN:summary -->

## Tests that do not pass

<!-- GEN:failing -->
| Suite | Test | Status | What it tests | Reason |
|---|---|---|---|---|
| Level 5 | `e142_uuid_basics` | FAIL | Uuid: parsed from text in any case, with or without hyphens and braces; printed in lower case with hyphens; a version and 16 bytes | exit code 65, expected 0; stdout differs |
| Level 5 | `e143_uuid_errors` | FAIL | Uuid errors: a text that is not a Uuid, bytes of another length, the time of a version other than 7, a namespace that is not a Uuid | exit code 65, expected 0; stdout differs |
| Level 5 | `e144_uuid_v7_time` | FAIL | a version 7 Uuid carries the time it was made: a later one sorts after an earlier one, and its instant is the moment of the call | exit code 65, expected 0; stdout differs |
| Level 5 | `e146_optional_narrow` | FAIL | a test against null narrows the optional name inside the block: its type is the plain one there; a test with and narrows the right side | stdout differs |
| Level 5 | `e151_fs_glob` | FAIL | fs.glob!: a pattern of names, `*` and `?` inside one segment of a path, sorted by name in the byte order; a folder that does not exist gives no name (data-language.md#files-and-paths) | exit code 4, expected 0; stdout differs |
| Level 5 | `e152_gzip_readers` | FAIL | the readers of csv, json, txt and fs.lines! decompress a path that ends in.gz; a file that is not gzip is $err_format (data-language.md#compression) | stdout differs |
| Level 5 | `e155_test3` | FAIL | $optimization is read only in the script: a script can not set the level | exit code 4, expected 65 |
<!-- /GEN:failing -->
