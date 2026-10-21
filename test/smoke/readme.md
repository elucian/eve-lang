# EVE Smoke Test

The quick test, check that the machine and the language are sane (D-134, D-135). It runs in about a second and does not depend on the tests of the levels. It is the portable part: any implementation of Eve should pass it first.

## Architecture

Each script is a driver with small functions and very simple `expect` lines, one feature each. A failed `expect` is an absurd and obvious error. Add a line when a bug is found that a smoke script should have caught. The first comment line of each script is its description in the list below.

The scripts go from the language to the machine. s01 to s16 are the language itself (the portable part). s17 to s20 are what the levels 4 and 5 added: tasks in a job, generics and traits, data files (CSV and JSON Lines), and the database of the machine (SQLite, a job that rolls back, a Memory table there and back). s21 is the machine (2026-10-18): the runner starts `eve --listen` in its folder, and `check/client.py` (Python) runs a script on it with `-loc`, drives `eve --stdio` with `vm.eval` (the way that replaced the command files, D-188), and stops it with `--listen stop`. evedb is not in the smoke test: it needs its own program and DuckDB; the level 6 tests f01 and f02 cover it.

Run it with `python script/runtest.py smoke`.

## Test Status

## Tests

The tests and the result of the last run are in `smoke.json` of this folder (written by the test runner after every run).
