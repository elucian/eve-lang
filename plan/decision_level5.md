# Decisions, level 5: database layer and the Eve database (version 0.4)

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. Ids are shared by all the decision files ([level 1](decision_level1.md), [2](decision_level2.md), [3](decision_level3.md), [4](decision_level4.md), 5, [6](decision_level6.md), [7](decision_level7.md)); the list of levels is in [decision_level3.md](decision_level3.md) and [version_map.md](version_map.md).

## Scope

The core of Eve as an ETL tool: a driver connects to databases by name, reads query results as streams of typed records, writes with bulk loads, upserts and merges, keeps transactions per job, restarts a failed load at its last checkpoint, and records the lineage of every run. Each machine has its own database, the Eve database, administered with `db` commands. Level 5 comes after parallel processing (level 4), which the large loads use, and before the server (level 6). Tests: `test/level5`, prefix `e`; they run against the Eve database (SQLite), so they need no database server.

Features: F-DAT-01 to F-DAT-11, F-LIB-08 (secrets of the connections), F-LIB-11 (lineage in the run log).

Design for review: [design-database.md](design-database.md) (2026-10-05).

Decisions already taken in other files: D-020 (jobs and `recover`), D-080 (Decimal, optional types, DataMap), D-081 (error classes, `defer`, unsafe methods, run log), D-083 (machine folder, configuration, remote commands).

## Draft features

The design note holds the details; in short:

1. **Connections by name** from the machine configuration, passwords as secrets (`database.connect("sales")`).
2. **Queries as streams of records**: `query(:Order)("select … where x = ?", v)`, parameters never interpolated.
3. **Writes**: `execute!`, `load!` in the modes insert, upsert and merge.
4. **Transactions per job**, with `retry` of transient errors (`DatabaseError.transient`).
5. **Light mapping** between record types and tables (`TABLE`, `KEY`; `find`, `save!`, `remove!`), replacing the ORM of the old tutorial page.
6. **Checkpoints** in the Eve database, for restartable pipelines.
7. **The Eve database**: SQLite embedded in the VM (DuckDB optional), in the folder `db/` of the machine.
8. **Admin commands** `db list`, `db add`, `db remove`, `db test`, `db info`, `db tables`, `db describe`, `db sql`, `db create`, `db migrate`, `db backup`, `db restore`, `db export`, `db import`, `db compact`, `db runs`.
9. **Schema migrations** in `db/migrations/<name>/`.
10. **Drivers**: SQLite and PostgreSQL first, then MySQL, SQL Server and Oracle through ODBC.

## Open questions

The eight questions at the end of [design-database.md](design-database.md): the engine of the Eve database, transactions bound to jobs, the record syntax, the extent of the mapping, the rights of `db sql`, parallel writes with their own connection, the `db` prefix of the commands, the order of the drivers.
