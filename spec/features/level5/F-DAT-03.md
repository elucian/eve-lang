# F-DAT-03 ETL pipeline model

Extract, transform, load with jobs and aspects; dead-letter output; the pattern taught in the tutorial. *Specified and taught (2026-10-10):* `spec/semantics/data-types.md`, `etl.html`. *State (2026-10-20):* a local ETL runs, a bad row goes to the rejects with a limit, streams have `map`, `filter` and the like; the pipeline stages with back-pressure over a database and the lineage report (F-DAT-06) are not done.

## Missing

- Pipeline stages with back-pressure over a database.
- The lineage and run report (F-DAT-06).
- A test: ETL from CSV to SQLite with a report that matches the row counts.
