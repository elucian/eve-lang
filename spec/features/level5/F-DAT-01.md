# F-DAT-01 Database layer

Connect, parameterized query as a stream, execute, transactions, bulk load. *Specified and taught (2026-10-10):* `spec/library/database.md`, `databases.html`; the VM has none of it yet.

*Partial (2026-10-11):* `database.connect` of a `sqlite://` connection in `eve.cfg`, `script`, `execute!`, `query!(:T)`, `query_one!(:T)`, `close`, a job as a transaction (commit at `done`, rollback on error), `csv.read!(:T)` and `json.write` (`.json` array, `.jsonl` lines); results are lists, not streams; no `table`, ORM, `load!`, `commit;` or other drivers.
