# F-DAT-14 Stored procedures

Native procedures in `sql/` called through `external` signatures; Eve procedures in `proc/`, run by the database part, listed by `eve db proc list`, reloaded by `eve db proc reload`, called by `db.call` (`spec/library/database.md#stored-procedures`).

*Partial (2026-10-12):* a module of `proc/` is imported and its `sql function`s registered, `eve db proc list`. Not yet: `external` at run time (no database with stored procedures in the tests), `proc reload`, `db.call`.

## Missing

- `external` at run time against a database with stored procedures (PostgreSQL).
- `proc reload` and `db.call`.
