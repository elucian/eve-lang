# F-DAT-13 `sql function`

An Eve function marked `sql function` is registered on every SQLite and DuckDB connection and called from SQL; deterministic, one result, SQL types, not overloaded; SQL `NULL` only for nullable types; an error stops the query with `$err_sql` (code 59) (`spec/library/database.md#sql-functions`).

*Partial (2026-10-12):* SQLite done; DuckDB waits for the VM to load it.

## Missing

- DuckDB: waits for the VM to load it (phase 7).
