# Review: level 5, data language and database layer

Date 2026-10-10. For the author. You asked to implement the design of level 5 in the tutorial and the specification, taking the most logical alternative where a decision was missing. This file lists what was written, every choice I made for you, and what to check first. Nothing here is a decision: no `D-nnn` was created and no `Q-nnn` was closed. Answer on the `**Answer:**` lines of Q-024, Q-039, Q-043, Q-044 and Q-046 in [decision_level5.md](decision_level5.md) (the entry point is [focus-level5.md](focus-level5.md)); a point that you reject needs a change in the files below.

## What was written

| Where | What |
|---|---|
| [spec/library/database.md](../spec/library/database.md) (new) | layers and connection URLs, SQLite roles, `Record`, the `table` declaration, mapping and its validation (debug and production), sessions, tracked records, writing only changed fields, transactions (`commit;`, `rollback;`, isolation, optimistic lock, checkpoints, two databases), direct SQL, errors, drivers, the Eve server, admin commands |
| [spec/library/data-language.md](../spec/library/data-language.md) (new) | generators, time types, `Decimal` and `T?`, `Bytes`, `fs`, the HTTP client, `Secret`, `os.run`, gzip, the module list |
| [spec/semantics/data-types.md](../spec/semantics/data-types.md) (rewritten) | `CSV`, `JSON`, `TXT`, `XML`, `HTML`, `HTMT`, the ancestor `Document`, typed reading, Unicode streams, rejects, reports, canonical form, the ETL cycle with an example |
| [spec/syntax/grammar.md](../spec/syntax/grammar.md), [declarations.md](../spec/syntax/declarations.md) | `table`, `commit`, `rollback`, `retry after`; section "Table declaration" |
| [spec/semantics/control.md](../spec/semantics/control.md), [errors.md](../spec/semantics/errors.md), [variables.md](../spec/semantics/variables.md) | job as a transaction, status `rolled back`, `retry after`, `$error.attempt`, fatal errors, error codes 50 to 57, `$isolation`, `$lock_timeout`, `$read_only`, `$trace` |
| [spec/lexical/keywords.json](../spec/lexical/keywords.json) | 14 contextual words (below); `eve1.js` of the tutorial regenerated |
| [spec/index.md](../spec/index.md), [spec/conformance/README.md](../spec/conformance/README.md), [plan/version_map.md](version_map.md) | rows, change log, notes on F-DAT-01, 03, 04, 09, 11 and F-LIB-08 (statuses unchanged: the VM has none of it) |
| tutorial `databases.html` (rewritten), `etl.html` (new, topic 42), `processing.html`, `exceptions.html`, `syslib.html`, `index.html` | the pages that teach it; the sidebar `data/databases.json` and `data/etl.json` regenerated |

Checks run: `speccheck.py` (0 problems), `grammarcheck.py` (156/156 files parse), `genkeywords.py`, `mdlinks.py check spec`, `bee-ed balance` on every edited page. Not done: no conformance test (the VM has no SQLite binding for this, no files or formats), no `GEN:` table, no commit.

## Choices I made (most logical alternative)

Items that your answers or the designs left open, in the order of importance. Each says what I did and what to change if you disagree.

1. **Every `Q-043`/`Q-046`/`Q-044`/`Q-039` proposal is written as proposed.** The `table` declaration shape (Q-046a), `commit;`, `rollback;`, `$isolation`, `retry after`, record methods and the rest. If you change the shape of `table`, change `database.md`, the grammar, `declarations.md` and the two tutorial pages.
2. **Contextual keywords added to `keywords.json` (D-116):** `after`, `cached`, `column`, `commit`, `generated`, `key`, `only`, `read`, `reference`, `rollback`, `table`, `temporary`, `to`, `version`. The grammar checker demanded them. They are contextual, so fields named `key` or `version` still work, but `read` and `to` as contextual words are the weakest part: `read only` could be one clause word (`readonly`). Decide.
3. **Error codes 50 to 57** (`DatabaseError` 50, `ConnectionError` 51, `ConstraintError` 52, `ConflictError` 53, `MappingError` 54, `CommitError` 55, `FormatError` 56, `HttpError` 57). The designs name the classes but no codes. The existing classes keep their codes: `DeadlockError` 42, `TimeoutError` 41, `ConvertError` 14 ($err_convert). `MappingError` and a partial `CommitError` end with exit code 4 (as the design says).
4. **Names of library calls that the designs only sketch:** `fs.read!`, `fs.read_bytes!`, `fs.lines!`, `fs.write`, `fs.append`, `fs.list!`, `fs.glob!`, `fs.exists!`, `fs.join`, `fs.name`, `fs.parent`, `fs.extension`; `http.get!`, `http.post!`, `http.request!`, `HttpResponse` with `status`, `headers`, `body`, `check()`; `secret.get`; `os.run` giving `{code, out, err}`; `gzip.open!`; `Instant.epoch`, `time.now()`. All follow D-089 (a read has `!`, a write has none). I did not decide the full member lists: Q-024 only names the modules.
5. **`os.run` and not `run`.** Q-044j writes `run(command, arguments, cwd: dir)`, Q-024b writes `os.run`. I used the module form `os.run`.
6. **`csv.read!(:T)(...)`, with `!`.** Q-039e wrote `csv.read(:Order)` without it; the later text of Q-046j (D-089) puts `!` on every read of a file. I used `!`; `open` is untyped, and `write` has none.
7. **`Document(:U)`, `Row`, `Node`, `Reject` and `Stream(:Bytes)`** are the library classes as in Q-039b; their members are not specified beyond the table in `data-types.md`.
8. **The rejects output** is an output parameter of the read, `rejects: @bad`, a `Table(:Reject)`. Per read (design question 5 of the remote note), not per run.
9. **TXT** is level 5 (0.4) with `widths:`; `XML` is 0.5 and `HTML`, `HTMT` 0.6 (Q-039g). Before the proposal Q-039g left `XML` and `TXT` open.
10. **Normalization off by default** (remote question 6). **Cache on the server only** (remote question 3): a `cached` clause on a local connection is accepted and does nothing. **Path 3 in 0.5** (remote question 2): the spec says so. **Oracle by the community** (remote question 1). **`eve_tx` and `eve_checkpoint` may be installed by `db prepare`** (remote question 4): the spec says `CommitError(partial)` when absent.
11. **Core design questions 1 to 7:** I took the proposed side of each: a separate `table` declaration (1), the mapping verified at first use in production plus the fingerprint file for drift reports (2), a nullable column mapped to a non-optional field is an **error** (3), memory restored on rollback (4), no `update record:` block (5), no savepoints in 0.4 (6), two databases in one job allowed with `CommitError(partial)` and a debug warning (7).
12. **`Table(:T)` free buffer** `Table(:Order)(capacity: 10000)` with spill to a SQLite file: written as in the core design §4.4.
13. **Scope of `commit;` and `rollback;`:** only the `do` region of a top-level job, with the `if` suffix. A `commit;` outside a job is a compile error (my reading of "inside a job"). `rollback` is not an error and `recover` does not run (design §8.2).
14. **`$error.transient`** is used in the examples of the designs but was not a listed field of `$error`. I listed it next to `$error.attempt` in `errors.md`.
15. **Tutorial pages were rewritten from the design, not extended.** The old `databases.html` had a Models section with an Oracle session class, a table of `connect`/`disconnect`/`query`/`commit`/`rollback`, and Concepts (Mapping, Tables, Records, Structure, Sessions) with `Append`, `Update`, `Delete`. The new page keeps the headings Append, Update and Delete, but the Oracle session-class pattern and the method table are gone. If you want them back as history, they are in `git -C tutorial log -p -- databases.html`.

## D-156 (core database), applied after your note

Your note of 2026-10-10 is recorded as D-156. Open choices I made, check them: (1) the extension is `.db`, so the default file is `db/local.db` (SQLite has no preferred extension; `.sqlite` or `.sqlite3` are the usual alternatives); (2) the key of `eve.cfg` is `core_db` and the variable holds the path of the file, relative to `$EVE_HOME`; (3) the cache is now a table set in the core database, not a separate `cache.db`, so the logs, the UX data and the cache share one file and one writer (WAL keeps readers free, but a long cache refresh can delay a log write; the design had split them for that); (4) staging `stage.db` and the application databases stay separate files; (5) it was one database per machine in the machine folder (D-083), it is now one per project, so a machine with several projects has several core databases and the Eve server of path 3 needs its own project.

## D-159 (answers to design-database-remote.md), applied

Your six answers are applied. What I had to decide, check it:

1. **Where the data lives (answer 3), the biggest change.** "Data is never loaded in SQLite" means: the core SQLite database holds logs, checkpoints, metadata, the UX data and the journal. Staging (`"stage"`) and the cache of the server are `evedb` (DuckDB) databases; the `temporary` clause is only for `"stage"`. D-156 said the core database holds "the local cache": that is changed to metadata only. I kept a `sqlite://` driver for SQLite files that belong to other applications; Eve itself puts no data there. Level 5 tests: SQLite for the core, `evedb` for data (the scope line of `decision_level5.md` and `CLAUDE.md` still say "against the Eve database (SQLite)"; not edited).
2. **No table in the target (answer 4).** Consequences I derived: (a) the checkpoint is in the core database and is written *after* the commit of the batch, so a crash between the two commits loads the last batch twice; the batch must be an upsert or merge, and debug mode warns on `commit;` with inserts; (b) the option `db:` of `checkpoint.read!` and `checkpoint.write` is gone; (c) a write to the core database is not counted by "one connection per job" (D-158); (d) the schema version of a target comes from a query that `eve.cfg` gives (`schema_version`), else a hash of the catalog; (e) after a lost `COMMIT` the server asks the database if the driver can (PostgreSQL has `txid_status`), else a fatal `CommitError`.
3. **Exclusive access (answer 4).** `prepare`, `activate` and `reindex` run only on an `evedb` database or on a connection with `exclusive` in `eve.cfg` (the key is mine). On other connections they do nothing and the run log gets a warning, so one script works on both.
4. **Rejects (answer 5).** Per read, written in batches (a reject batch for each batch read), to a file (`rejects: "path"`) or a table (`rejects: @bad`).
5. **NFC (answer 6).** Explained in the spec and in `etl.html`: the file is never changed, normalization is off, and `normalize: "nfc"` acts on the values in memory.
6. **Oracle** is in the backlog. **Path 3 in 0.5** needed no change. **No offline work:** the local Eve is client and server (`database.md`, section on the layers).

## D-158 (answers to design-database-core.md), applied

Your seven answers are applied; what I had to complete is below. Check these:

1. **Schema version (answer 2).** You said the database has a version signature of the schema and the mapping has a version too. I defined the schema version as a number raised by `db migrate` (`PRAGMA user_version` on SQLite, a table `eve_schema` on other databases, installed by `db prepare`), stored per connection in `db/mappings.json` with the fingerprints, and compared at the first use of the connection. A difference is a `MappingError` (fatal, exit code 4). I added the admin command `db validate <name>`. A change of the database outside `db migrate` is not seen in production (trust the file) and is found in debug mode.
2. **Memory after a rollback (answer 4).** Records keep their values, and the records of the job are *detached* (my addition: otherwise the identity map would return the old object at the next `find!`).
3. **The `update` block (answer 5), the biggest doubt.** You wrote `update table do … done;`. I implemented `update c do … done;` with `c` a record: the names of its fields are in scope, it is only a way of writing, and `validate` runs at `done`. If you meant a set-based update of a table (`update customers where … do`), or `with (record1, record2) do`, it is a different feature: say which. A block over two records is not supported; the inner block wins for a field name.
4. **Batch errors (answer 6).** New class `BatchError` (code 58) with `failed` (a collection of `{key, reason}`) and `batch`; `recover` reads it as `$error.failed`. The failed batch is rolled back; earlier batches stay committed (with `commit;` and a checkpoint). `retry` restarts at the checkpoint, so only the failed batch and the ones after it run again: this matches your "only the batch that failed is reprocessed". **Conflict:** you want `resume` to go on with the *next batch*, but `resume` today (D-020) ends the failed job and continues after its `done`. To get your behavior the loop needs a different rule (for example `load!(…, on_error: "continue")` that collects the failures and goes on, then raises at the end). I kept D-020 and listed the gap in the tutorial. Decide.
5. **One connection per job (answer 7).** A job writes to one connection; it may read from others. The second write is a compile error (or a run-time `DatabaseError`). `CommitError` lost its `partial` and `committed` fields: it remains only for a lost answer to `COMMIT` on path 3, fatal. The technical debt is in `plan/backlog.md`.
6. **Answers 1 and 3** (the declaration maps the table to the class, classes pristine; nullable in the database is nullable in the model) confirm what was written; nothing changed.
7. `update` is now a contextual keyword in `keywords.json`.

## D-157 (names of the file types, TXT, PRN and PDF), applied after your notes

Check: (1) the template type is `HTMT` (an HTML template), a name you chose on purpose; I first read it as a typo of `HTMLT` and changed it back. The extension of a template file is `.htmt` (your answer); it was `.evh` in the tutorial, now changed in `templates.html`, `examples.html`, the demo file `demo/order.htmt` and `decision_level7.md`. (2) `TXT` is the fixed-length format (it replaces `Dat`, and for a moment `PRN`): extension `.txt`, module `txt`, options `widths:`, `width_unit:`, `null:`, no style and no page. The examples `orders.dat` are now `orders.txt`. (3) `PRN` and `PDF` are only named, as output formats; I removed the options I had invented for them (`limit:`, `overflow:`, `page_lines:`, `header:`) and put the style and limits in the backlog as a todo. (4) A `TXT` unit is a `Row`, like `CSV`. (5) The archive and `review/` keep the old names (history).

## The tests e23 to e53 (TDD, for your review)

31 tests (e23 to e53) were written from the spec, all fail now (`test/level5/readme.md` lists them). Please review the expectations, not the code: each is a statement of what the spec says. What to look at:

1. **Spec rules I had to add to make a test exact** (all marked proposed): the byte layout of CSV, JSON Lines and TXT (`semantics/data-types.md#the-formats-in-detail`); `Decimal` arithmetic and the print of an `Instant` (`library/data-language.md#details-used-by-the-tests`); `Secret(text)`; the standard modules in scope without an import; `eve.cfg` and `db/mappings.json` (`library/database.md`); the words of the compile errors (table in `database.md`).
2. **Grammar changes the tests needed** (found by `grammarcheck.py`): `name!(...)` as a statement and `name!(:T)(...)` with type arguments (the calls `shop.execute!(…)` and `csv.read!(:Row)(path)`), and `.done` after a dot (the flag of a generator, which is also the keyword that closes a block). Inequality is `<>`.
3. **Negative tests** pass for the wrong reason on a VM that does not know the syntax, so each declares the words of its message (`contains`).
4. **Database tests** use a SQLite file of the test through `sqlite://` (external file, D-159), not `evedb`: no server is needed. Their schema version is 0 (a new file), so `db/mappings.json` says 0 and no catalog is read; e52 says 2 to get the `MappingError`.
5. **Not written**: HTTP, `os.run`, gzip, encodings, `evedb` staging, `prepare`/`activate`, `retry after`, `BatchError`, `TXT` `overflow`, the Eve server; the generic ORM paths with `load!`, `scan!` and `where!` streams are only touched by e53 and e46.
6. **Doubts in the expectations**: e46 relies on a direct write flushing the pending change first (spec: Direct SQL); e53 relies on `checkpoint.write` of the core database in the same job as a write to `shop` (allowed, D-159); e33 prints a `Decimal` read from `3` as `3`; e28 expects the parse error code 15.

## Tutorial pages updated after D-156 to D-159 (2026-10-10)

`databases.html` (new section Configuration: `eve.cfg` and `mappings.json`), `etl.html`, `evedb.html` (SQLite for logs and metadata, DuckDB for data, `exclusive`, `eve_tx` only), `eveux.html` and `server.html` (core database), `generators.html` (version 0.4, level 5), `networking.html` (the HTTP client at level 5, `http.get!`), `protocols.html` (formats and levels), `syslib.html` (standard modules in scope, `Secret`), `vm.html` (`$EVE_CORE_DB`), `types.html` (file types, pointer to `etl.html`), `datetime.html` (new section `Instant` and `DateTime`), `command.html` (new section `os.run`), `processing.html`, `exceptions.html`. Still to do in the tutorial: a daily-report example (a `CSV` that fills an `HTMT`, `types.html` and `templates.html`), the example of each file type, and the page `library.html`. The README of `evedb/` (code, not touched) still says that the Eve database holds the cache and staging.

## Contradictions I found in the notes

- **Q-043b** says "the first write (a `!` method)" begins a transaction: the old meaning of `!` (D-081). The spec says the first use of the connection in a job. Q-043g (2) is void for the same reason.
- **Q-043c and Q-043d** (records without methods, no mapping) are replaced by Q-046. The spec follows Q-046, so `find`, `save!` and `remove!` do not exist.
- **Retry loops:** the old text said "count the attempts in a local variable" (`processing.html`); with `$error.attempt` the counter is built in. I left the old bullet in place.
- **Tests:** `CLAUDE.md` says level 5 has 22 tests, all generic or macro. There is no test for the data language and the database layer; I did not invent expected outputs.

## Not done, and why

- **Conformance tests** `e23` onward: they need expected output from a VM that has no database, file-format or time binding yet. They are the next step; I suggest the order: `Decimal` and `T?`, then `CSV` round trip in canonical form, then SQLite `table` mapping.
- **Other tutorial pages** that still describe level 5 as planned or older: `networking.html` ("the version map puts the HTTP client at level 3"), `generators.html` ("Designed, not in Eve 0.1... version 2"), `datetime.html` (only `Date`, `Time`, `Duration`; no `Instant`/`DateTime` rules), `types.html` (`Decimal`, `T?`), `library.html`, `features.html`. Say if you want them aligned now.
- **Release notes, `manual/`:** untouched.
- **Commit:** nothing is committed. The tutorial files are in the `scl` repo (`git -C tutorial`); `data/server.json`, `server.html`, `classes.html`, `index.html` also hold edits from before this work.

## What to check first

1. The `table` declaration (Q-046a) and the clause words in `keywords.json` (choice 2).
2. The error codes 50 to 57 and the exit code 4 rule (choice 3).
3. The member names of `fs`, `http`, `os`, `secret` (choice 4).
4. `etl.html`, the new topic 42: title, place in the roadmap, and whether it should be a page of its own.
