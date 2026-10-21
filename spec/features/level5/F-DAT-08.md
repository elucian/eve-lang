# F-DAT-08 The Eve database

The core database: one per project in its `db/` folder (default `local.db`, name set in `eve.cfg`, system variable `$EVE_CORE_DB`), SQLite embedded (3.54.0, compiled into the VM from the amalgamation, `code/evevm/src/sqlite.zig`; DuckDB is not in the VM: it is the separate test database `evedb`, F-DAT-12), for checkpoints, run history, lineage and metadata, never ETL data (staging and the cache are `evedb` databases).
