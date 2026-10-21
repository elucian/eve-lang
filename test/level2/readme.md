# test Level 2

Drivers with aspects: `apply`, arguments, results, state per call, errors across the call, log files (D-066, D-072; modules moved to level 3). A test that needs aspects, libraries or data is a folder, a whole Eve project; a test of a single script is a file in this folder (D-124). A project folder may hold more drivers, `b01_test1.eve`, `b01_test2.eve`, ...: variations that use the same aspects and libraries in other use cases (D-133). For a project test
(D-073): `b01_import/b01_import.eve` is the driver, with its expectations in a `/*@expect*/` block at the end (D-094, D-098), and `asp/`, `lib/`,
`web/` (templates), `data/`, `out/` hold what the project needs. The test runs from its folder; `out/` is emptied before each run.

## Tests

The tests and the result of the last run are in `level2.json` of this folder (written by the test runner after every run).
