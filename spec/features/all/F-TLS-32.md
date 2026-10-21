# F-TLS-32 Test tracking files

One JSON file per suite, `test/<suite>/<suite>.json`, for the levels and for the special tests (smoke, bytecode, scaffold): status, runs, failures, date and reason of every test, and the features of the specification that the test checks. The runner writes it after every run and the manual generator reads it.
