# test Level 7

This level tests web: HTML templates and Eve in WebAssembly (version 0.6, design/decision/level7.md).

A test is a project folder (D-073): `test/level7/g01_feature/` holds the driver `g01_feature.eve` and its `expect.json`. Test names start with `g`. The first two tests are the server tests moved from level 6 on 2026-10-20 (D-204): `g01_pg_driver` (the Eve driver for PostgreSQL against evedb on port 5432) and `g02_evedb_columnar` (the driver `evedb://` and the column batches). Each one is a project folder with `evedb.cfg`, `eve.cfg` and `check/run.py`: the runner starts `eve db serve evedb.cfg`, the check waits for the port, runs the Eve script and stops evedb. They need `bin/evedb.exe` and `bin/duckdb.dll` next to the VM under test. The other features of this level are drafts.

## Tests

The tests and the result of the last run are in `level7.json` of this folder (written by the test runner after every run).
