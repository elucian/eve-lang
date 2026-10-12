# Project layout, `project init` and the fallback log (F-TLS-23)

Author request (2026-10-11), on top of D-160 (`new project <folder>`): define the folders of an Eve project, a minimal fallback log in `log/`, the extended log in the local SQLite database in `db/`, a `meta/` folder, a `data/` folder split in `in` and `out`, and a `test/` folder for the test database (`evedb`). Implemented as the command `project init <folder>` (`evevm/src/scaffold.zig`, tests `test/level5/e54_project_init`, `e55_project_new_not_empty` and the shell test `test/scaffold/run.sh`). Status: the author answered the questions on 2026-10-11 (see the end); the layout is implemented.

## The layout

| Folder or file | Content | Versioned |
|---|---|---|
| `<name>.eve` | the first driver, with `process main` (the name comes from the folder) | yes |
| `eve.cfg` | the configuration of the project (`core_db`, `fallback_log`, connections), in the project root; there is no `config/` folder (too many folders) | yes |
| `db/` | the core database, SQLite, `db/local.db` (D-156, renamed): the extended log (run history, errors, lineage), checkpoints, metadata. Never data (D-159) | no (`.gitignore`) |
| `log/` | the minimal fallback log `log/eve.log` | no (`.gitignore`) |
| `meta/` | the description of the project: `meta/project.json` (name, layout version, Eve version); the home of the mapping file and the schema versions (now `db/mappings.json` in the level 5 tests, to move) | **yes**, it is committed |
| `data/in/`, `data/out/` | files that the jobs read and write (CSV, JSON Lines, TXT); the content is not versioned | no (`.gitkeep` only) |
| `test/` | the files of the test databases: `evedb` (DuckDB) files, the second test database next to the SQLite core | no (`.gitkeep` only) |
| `asp/`, `lib/`, `src/`, `doc/`, `web/` | aspects, modules, other sources, documentation, web templates (D-160) | yes |
| `.gitignore` | made if absent; leaves out `db/*.db`, `db/*.db-*` (SQLite companions), `log/*.log*`, `log/*.db`, `data/in/*`, `data/out/*`, `test/*`; an empty folder is kept by `.gitkeep` | yes |

Other folders worth a decision, not created today: `tmp/` (scratch of a run, always ignored), `sql/` (SQL scripts; the level 5 tests already use `sql/schema.sql`), `out/` (the report folder of the tests, replaced by `data/out/` in a project), `secrets/` (never versioned; but the OS keyring of D-155 is the better place).

## `project init <folder>` and `project new <folder>`

`eve --project init <folder>` or `project init <folder>` in the REPL; the same with `new`.

- **`init`** works on a new folder and on an existing project, empty or not. It makes the folder when it is absent, the missing folders of the table, and the missing files `<name>.eve`, `eve.cfg`, `meta/project.json`, `.gitignore`. It **never overwrites**: a file that exists is kept (`keep` in the log), so it can be run on an older project to add what is missing, and no work is lost.
- **`new`** fails (exit 73, nothing written) when the folder exists and is not empty; otherwise it does what `init` does.
- **Git:** the check looks at the folder **and all its parents** (`git rev-parse --git-dir`), so many projects can live in one versioned folder such as `test/` and none of them gets its own `.git` (test e54 checks this). When no repository holds the folder, the command runs `git init` after it has written the `.gitignore`; inside a repository it leaves Git alone; when Git is not installed it says so (`git not found: install Git, then run git init`) and the project is made anyway.
- The log has one line per file, `create` or `keep`, then the Git line, then a count. Exit status 64 for a bad command line, 73 when the folder cannot be made (or, for `new`, is not empty). The core database is not created by the command, but on the first run (D-160 d).

## The minimal fallback log

The fallback log is for the case where the extended log in `db/local.db` cannot be used: the database is corrupt, locked or missing, or the VM is not yet up.

- **Scope:** only fatal crashes, unhandled panics and critical startup failures (database corruption, a missing configuration file, a port that cannot be bound). Not warnings, not job errors: those go to the extended log.
- **Format:** plain text, append-only, one event per line: `2026-10-11T14:03:22Z FATAL <where>: <message>`, ISO-8601 in UTC with the `Z`; a message has no newline (it is escaped), so `grep` and `tail` are enough to read it.
- **Rotation:** at 5 MB (`fallback_log_max`) the file is renamed to `eve.log.1` (the older `eve.log.1` is replaced) and a new `eve.log` starts, so the disk use is at most two files.
- **Writing:** open for append, write one line, flush at once; the writer never allocates and never fails the VM: when the file itself can not be written, the line goes to stderr.
- **Where:** `fallback_log` in `eve.cfg`, default `log/eve.log`; when the configuration is the thing that is missing, the VM uses `log/eve.log` of the working folder.
- **Extended log:** in the core database `db/local.db` (SQLite), tables owned by Eve; it is the log that `eveux` shows.

The writer is **not implemented yet** (only the folder, the keys of `eve.cfg` and the `.gitignore` are).

## Answers of the author (2026-10-11)

- **Command:** `project init` is the main command because a project may already exist; `project new` fails on a non-empty folder, `project init` never does and never overwrites (D-160 a).
- **Git:** if no repository holds the folder, make the `.gitignore` and run `git init` (D-160 b).
- **Core database:** `db/local.db`, not `db/eve.db` (D-156 changed; spec and plan files renamed).
- **Configuration:** `eve.cfg` stays in the project root; no `config/` folder.
- **`meta/`** is versioned and takes the mapping file and the schema versions. *Still to do:* the VM reads `db/mappings.json` today (tests e46 to e53); moving it to `meta/mappings.json` changes those tests and the VM, and waits for the author's word.
