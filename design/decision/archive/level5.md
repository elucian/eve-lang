# Archive of level5.md: settled entries, full text

## Q-024 The system library: names and members (2026-10-06)
Moved from level 3 on 2026-10-08: the modules it names (`fs`, `path`, `time`, `secret`, `http`, `database`) are the data language and the database layer of level 5 (D-125); `task` goes to version 0.4 too (D-144).
The page `syslib.html` lists the modules that connect a program to the machine: `io`, `exception`, `fs`, `path`, `time`, `secret`, `task`, `database`, `http`, with their level and status; only `io` and `exception` are drafted (`code/evevm/lib/`). Are these the names and the split you want (for example one `fs` and `path`, or one `file` module)? Is the shell `call` part of the system library or of the language? Which module holds the time types (`time`), given that Date and Time have their own page?

**Proposed (2026-10-09), one line per point; confirm or correct each:**
- (a) Modules: `io`, `exception`, `fs` (files, folders and paths in one module, Q-044f), `time` (`Instant`, `DateTime`, the clock, formats; `Date`, `Time` and `Duration` are built-in types), `secret`, `database`, `http` (client in Version 0.4), `csv`, `json`, `txt` (Q-039e), `os` (`run` by argument list, environment). `task` stays planned with the generators (D-144).
- (b) `call` stays a statement of the language (level 3); `os.run` is the safe form for programs that build arguments.
- (c) The time types live in the module `time`; the page Date and Time (datetime.html) teaches them, syslib.html points to it.

**Answer:** Sounds good.

## Q-045 Eve macro (hybrid script): aspects and a driver in one file (2026-10-10)
Author proposal (2026-10-10): a **hybrid script** (the author's words: "macro hybrid script") is a self-contained script that holds its aspects and its driver in one file, so a small parallel job needs no project folder and no `asp/`. Today a file holds one declaration (driver, aspect or module) and a `#!` free script holds no driver and no aspect (`spec/syntax/declarations.md`, D-014, D-091). The example of the author, written with the rules of the spec (2-space indentation, `**` comments inside a body, outputs declared before the group):

```eve
#!/usr/bin/env eve
# Pipeline: two workers in parallel, one file

concurrent aspect job_worker_1 is
  process main(@res: Result) is
    ** internal sequential job logic
  return;
end job_worker_1;

concurrent aspect job_worker_2 is
  process main(@res: Result) is
    ** internal sequential job logic
  return;
end job_worker_2;

# Driver executing parallel tasks
driver pipeline_driver is
  process main is
    new r1: Result;
    new r2: Result;
    p_exec: parallel
    do
      start job_worker_1(@r1);
      start job_worker_2(@r2);
    done p_exec;
  return;
end pipeline_driver;
```

Three things of the original example do not compile under the current rules: (1) `# Internal sequential job logic` is indented, and `#` is a comment only at indentation 0, elsewhere a lexical error (Q-016d, `spec/lexical/lexical.md`), so a body uses `**`; (2) `r1` and `r2` were declared between `parallel` and `do`, so they are dropped at `done` and the results are lost (D-140): an output is declared before the group; (3) `Result` is declared nowhere (point d).

**Proposed description.**
- **Kind.** A hybrid script is a file of several top-level declarations: any number of aspects (exclusive or concurrent) and exactly one driver. It runs like a driver: `eve pipeline.eve` (or `./pipeline.eve` with the shebang) runs `process main` of its driver, which takes the command-line arguments.
- **Self-contained.** Its aspects are private to the file: no other driver can `apply` or `start` them, and the file can not be imported or export anything (as a free script, D-126). It may import modules (`from lib use …`) inside its declarations, as a driver does.
- **Name lookup.** An aspect named in `apply` or `start` is searched first in the file, then in `asp/` and the project root (`spec/semantics/aspects.md`). An aspect of the file with the name of an aspect file of the project is a compile error, so the reader never wonders which one runs.
- **Rules unchanged.** Each aspect keeps its own scope and state (D-066): it sees no variable of the driver nor of another aspect of the file. `start` still starts only a concurrent aspect, checked for thread safety (D-090, D-130, D-140); nesting, data rules, output order and errors of the groups are those of `multitasking.md`.
- **Compile errors (exit 65).** Two drivers in one file; aspects without a driver; a statement outside a declaration; a name used twice at the top level.
- **Level.** With `apply` only, a hybrid script is level 2; with `parallel` and `start`, level 4. Tests: one in `test/level2` (an exclusive aspect applied), one in `test/level4` (this example), and the compile errors above. Feature F-STR-09 in `feature_map.md`.

(a) Is "hybrid script" the name, or is "macro" part of it (`macro script`)? Does a keyword mark the file, or is it known from its content (several top-level declarations, one of them a driver)? Proposed: no keyword, the content decides; the name in the documentation is "hybrid script". 

**Answer:** Use the term **Eve macro**; the description says that an Eve macro is a hybrid script. Proposal accepted: no keyword, the content decides (2026-10-10).

(b) Line 1: is the shebang `#!` required, allowed or forbidden? Today `#!` means a free script with no driver. Proposed: allowed and optional; a `#!` file with a top-level `driver` is a hybrid script, without one it stays a free script; a file without `#!` may also be hybrid (line 1 a `#` title). 

**Answer:** Proposal accepted (2026-10-10).

(c) Order of the declarations: must the driver come last, after the aspects it uses? Proposed: any order (one scope per file, D-041); the style guide puts the aspects first and the driver last, as in the example. 

**Answer:** Proposal accepted (2026-10-10).

(d) Shared types and helpers: `Result` must be known to the aspects and to the driver. May a hybrid script hold top-level classes, functions and constants (`set`) shared by all its declarations? Proposed: yes, they form an implicit private module of the file: classes, functions, procedures and constants, no variables (`new`); a concurrent aspect may call them under the thread-safety rules of a managed module (D-089, D-132). 

**Answer:** Proposal accepted, with a change: declarations outside the aspects and the driver are shared, variables included. A concurrent aspect may use only atomic variables and thread-safe variables, functions and procedures (2026-10-10).

(e) Version: proposed Version 0.4 (level 5 work), because the VM loads aspects from files today (`project.zig`) and the change is small: the parser accepts several declarations, the project table registers the aspects of the file first. 

**Answer:** Proposal accepted: Version 0.4 (2026-10-10).

## D-156 The core database: one per project, in its `db/` folder, `$EVE_CORE_DB` (2026-10-10)
Author decision, given while the database layer was specified (level 5, F-DAT-08). Changes where the Eve database lives (it was one per machine, D-083) and what it holds.
- **One per project.** Each project has a `db/` folder. It holds the **core database** of the project, a SQLite file. The core database drives the Eve UX (`eveux`, D-154) and holds the logs of the ETL runs and the local cache. *(Changed by D-159: it holds logs and metadata, never data, so no cache of data.)*
- **The file name has a default:** `local`, with the extension that SQLite programs prefer. SQLite has no required extension; this specification writes `local.db` *(proposed, see `review_level5.md`)*.
- **The name can be configured** in the configuration file of the machine (`eve.cfg`, key `core_db` *(proposed)*) and is loaded as the system variable `$EVE_CORE_DB`, a `String` with the path of the file. The connection name `"eve"` of `database.connect("eve")` and of `table … in "eve"` is the core database.
- **Consequence for the roles of SQLite files** (`spec/library/database.md`): the cache of reference tables was to be part of the core database (it was a separate file `cache.db`); **changed by D-159**: the core database holds no data, the staging database and the cache are `evedb` (DuckDB) databases.
Applied (2026-10-10): `spec/library/database.md`, `semantics/variables.md`, `design/design-database-core.md`, tutorial `databases.html`, `design/feature_map.md` (F-DAT-08).

## D-159 Remote databases: no offline work, SQLite only for logs and metadata, no tables in a target (2026-10-10)
Author answers to the six questions at the end of `design/design-database-remote.md`.
- **1. Oracle** goes to the backlog, postponed (`backlog/ideas.md`).
- **2. Path 3 in version 0.5** (the Eve server); paths 1 and 2 in version 0.4. Agreed.
- **3. No offline work.** A local Eve session must be connected to a remote session. Without a remote server the local Eve does the job, and the test is local: the same Eve works as client and as server, with the core SQLite database and another database, DuckDB (`evedb`), connected. **Data is never loaded in SQLite**: it stores the logs and the metadata. (Consequence by the model: staging and the cache of reference tables are `evedb` databases; the core database holds no cache of data, D-156 is changed.)
- **4. Eve installs no metadata table in a target database.** The target may be kept by a DBA. Exception: when the Eve machine has exclusive access to the remote database, or it is an `evedb` database, Eve may speed up bulk loads (disable triggers, deactivate indexes, and more). Otherwise, with all the constraints on, Eve works, slower, and gives more failures on an active database. (Consequences by the model: no `eve_tx`, `eve_checkpoint` or `eve_schema`; the checkpoints are in the core database and the batches of a `commit;` load must be idempotent; the status of a transaction after a lost `COMMIT` is asked from the database when the driver can answer, else `CommitError`; the schema version comes from a query given in `eve.cfg`; `prepare`, `activate` and `reindex` work only on an exclusive connection.)
- **5. Rejects:** the output is created in batches, one reject batch for each batch read.
- **6. Unicode normalization:** the source file stays untouched, normalization is off by default. The author asked what NFC is: explained in `spec/semantics/data-types.md` and `etl.html`.
Applied (2026-10-10): `spec/library/database.md`, `spec/semantics/data-types.md`, `spec/semantics/variables.md`, tutorial `databases.html` and `etl.html`; points to review in `review_level5.md`.

## D-158 Database layer: the answers of the author to design-database-core.md (2026-10-10)
Author answers to the seven questions at the end of `design/design-database-core.md`. They settle part of Q-046 and Q-043.
- **1. The `table` declaration is the mapping (confirms Q-046a).** The declaration maps a table onto a class, the class does not map to the table. Classes stay pristine (D-123): plain data and methods.
- **2. Production check: trust the file.** The VM does not read the catalog. The database has a version signature of its schema, and the mapping file has a version too; when the two versions differ, the user must validate the mapping again. (The model completed this as: the schema version is raised by `db migrate` (a query given in `eve.cfg` for a database kept by a DBA, D-159, no table `eve_schema`), `db/mappings.json` stores the version it was validated against, a difference is a `MappingError`, and `db validate` is a new admin command. These details are to be reviewed.)
- **3. A nullable column must be nullable in the model.** An error (confirms the proposal).
- **4. Memory remains changed after a rollback.** The proposal of restoring memory is rejected. The user re-reads the record from the database, creates another record, compares the records to find what is wrong, or discards the changes by hand. (The model completed this as: the records of the job are detached and keep their values.)
- **5. The `update` block.** `update` starts the modification of a record using `let`, and removes the need to repeat the record name for every field, like `with … do … done`. The choice of the author: `update table do … done;` *(read by the model as `update <record> do … done;`: one record, the names of its fields in scope; to review)*.
- **6. Batch failures.** When a record of a batch fails, the failing records are returned as a collection (their ids) and passed to `recover`, which can count them, log them and decide. After `resume` the next batch is processed; after `retry` only the batch that failed is processed again. *(The model: a `BatchError` with `failed`, read as `$error.failed`; `retry` starts from the checkpoint; `resume` follows D-020; to review.)*
- **7. One connection per job.** A job writes to one connection; there is no write to two databases in one job. The feature stays in the backlog as technical debt.
Applied (2026-10-10): `spec/library/database.md`, `spec/syntax/grammar.md`, `spec/semantics/errors.md`, `spec/lexical/keywords.json` (`update`), the tutorial pages `databases.html`, `processing.html` and `exceptions.html`; the points to review are in `review_level5.md`.

## D-157 Names of the file types: CSV, JSON, XML, HTML, HTMT, TXT; PRN and PDF are output formats (2026-10-10)
Author decision, revised the same day. A type name is not one capital letter followed by lower case: all letters can be capitals. The file types are `CSV`, `JSON`, `XML`, `HTML`, `HTMT` (an HTML template, file extension `.htmt`; the name is chosen on purpose, "because it is more fun") and `TXT`, a simple text file with fixed-length fields, which replaces `Dat` (extension `.txt`). The modules are lower case: `csv`, `json`, `xml`, `html`, `txt`. `PRN` (extension `.prn`) and `PDF` are formats for **output only**, for data reporting; their style and limits are a todo in the backlog (`backlog/ideas.md`). The font and the look belong to the style of the report and to the UX, not to a data format.
Applied (2026-10-10): `spec/semantics/data-types.md`, `spec/library/data-language.md`, `spec/semantics/types.md`, `spec/index.md`, the tutorial pages `etl.html`, `types.html`, `templates.html`, `syslib.html`, `protocols.html`, and the plan files of level 5 and 7. Not changed: the archived files and `review/` (history).

## D-152 Eve macro: a hybrid script with shared declarations, aspects and one driver (2026-10-10)
Author answers to Q-045. Version 0.4, feature F-STR-09.
- **Name.** An **Eve macro** is a hybrid script: one self-contained file that holds shared declarations, any number of aspects (exclusive or concurrent) and exactly one driver. No keyword marks it: a file with a top-level `driver` and other top-level declarations is a macro. It runs like a driver: `eve pipeline.eve` runs `process main` of its driver, which takes the command-line arguments.
- **Line 1.** The shebang `#!` is optional. A `#!` file with a top-level `driver` is a macro; without one it stays a free script (D-014, D-091). A macro may also start with a `#` title.
- **Order.** The top-level declarations come in any order (one scope per file, D-041). Style: shared declarations first, then the aspects, the driver last.
- **Shared declarations.** Every declaration outside the aspects and the driver (`class`, `function`, `procedure`, `set` constants and `new` variables) is shared by all the declarations of the file. An exclusive aspect and the driver use them freely. A **concurrent aspect** uses only the thread-safe ones: atomic variables (`Atomic(:T)`, D-132), thread-safe variables, and functions and procedures that the compiler proves thread safe (D-089, D-129, D-137). Using any other shared name from a concurrent aspect is a compile error that names it, as for a member of a module (d01, d03).
- **Self-contained.** The aspects of a macro are private to it: no other driver can `apply` or `start` them. A macro can not be imported and exports nothing (D-126). Its declarations may import modules (`from lib use …`).
- **Name lookup.** An aspect named in `apply` or `start` is searched first in the file, then in `asp/` and the project root. An aspect of the file with the name of an aspect file of the project is a compile error.
- **Rules unchanged.** Each aspect keeps its own scope and state (D-066) and sees no variable of the driver or of another aspect; the shared declarations are the only common names. `start` starts only a concurrent aspect; the rules of the parallel groups are those of `multitasking.md` (D-140).
- **Compile errors (exit 65).** Two drivers in one file; aspects or shared declarations without a driver (in a file without `#!`); a statement outside a declaration; a name declared twice at the top level; a concurrent aspect that uses a shared name that is not thread safe.
- **Tests.** One macro with an exclusive aspect applied (level 2 rules), the example of Q-045 with `Result` declared at the top (level 4 rules), a concurrent aspect that adds to a shared `Atomic(:Integer)`, and the compile errors above: `test/level5`, e16 to e22 (written first, 2026-10-10); e04 became a macro, so level 5 has no project folder left. Specification: `spec/syntax/declarations.md#eve-macro-level-5`.

## Q-039 Data file types: JSON, CSV, TXT, XML, HTML, HTMT (2026-10-08; was numbered Q-038, an id taken by level 2)
Author request: types for the files that a program loads and parses in memory: HTML, XML, HTMT (HTML template), CSV, DAT (fixed width data) and JSON. The load is buffered and works in loops, a kind of traversal: row by row, or element by element (object by object) for JSON. All of them are derived with `<:` and defined mostly in Eve, at a later time. A first proposal is in `spec/semantics/data-types.md` and in the section "Data File Types" of `types.html`. Open points:
- (a) The names: `JSON`, `CSV`, `TXT`, `XML`, `HTML`, `HTMT`. `HTML` is also the safe page type of the templates (Q-027, level 7): one type, or `HTML` for the parsed file and another name for the safe page?
- (b) The common ancestor of the six classes (`Source`? `Document`?) and the traversal protocol: what a class must define so that `for unit in value do` works (an iterator, a generator?).
- (c) How a unit is read: `row["name"]`, `row.name`, `row[2]`; the type of a field (String until converted, or declared in a layout).
- (d) `TXT`: how the layout of the fixed width fields is declared (a class, a list of widths, a file).
- (e) The modules (`csv`, `json`, ...) or a single `load`; reading a stream from the network as well as a file; writing a file of these types.
- (f) Encoding and the line ending; the error when a unit is not well formed (raised when the loop reaches it).
- (g) Levels: `CSV` and `JSON` in level 5 (D-125, was level 3), `HTML` and `HTMT` with the templates (level 7, version 0.6), `XML` and `TXT` open.
**Proposed (2026-10-09), one line per point; confirm or correct each:**
- (a) One type `HTML`: a parsed document tree. A rendered template gives an `HTML` value too; text placed in it is always a text node, so it is escaped when the value is written. No second name for the safe page.
- (b) The ancestor is `Document(:U) <: (Object, Iterable(:U))`, where `U` is the unit: `CSV` and `TXT` give a `Row`, `JSON`, `XML` and `HTML` give a `Node`. The protocol is the library trait `Iterable(:U)` of level 4 (D-145): a class gives its next unit or `null` at the end; `for` reads any `Iterable`.
- (c) A `Row` reads by name and by position, `row["name"]`, `row[2]`, and the value is a `String`. Typed reading decodes into a record (Q-043c): `csv.read(:Order)(path)` gives a `Stream(:Order)` and the fields are typed, `o.amount`. `row.name` is only for records.
- (d) The layout of a `TXT` file is a record type and the widths of its fields in declaration order: `txt.read(:Line)(path, widths: (4, 10, 20))`; untyped, `txt.open(path, widths: (4, 10, 20))` gives rows read by position.
- (e) One module per format, `csv`, `json`, `txt`, `xml`, `html`, each with `open(source)` (untyped), `read(:T)(source)` (typed) and `write!(path, rows)`. The source is a path or a `Stream(:Bytes)`, such as the body of an HTTP response.
- (f) UTF-8 by default, other encodings with `encoding:`; LF and CRLF are both read, writing uses LF unless `eol: "crlf"`. A unit that is not well formed raises `FormatError` with `line` and `column`, when the loop reaches it.
- (g) `CSV`, `JSON` and `TXT` in level 5 (Version 0.4; fixed-width files are common input of ETL), `XML` in Version 0.5, `HTML` and `HTMT` with the templates in level 7 (Version 0.6).

**Answer:** Agreed

## Q-043 Database layer: the answers of design-database.md as rules (2026-10-09)
Note 2026-10-10: (c) and (d) are replaced by Q-046, the robust ORM asked by the author ([design-database-core.md](../design-database-core.md)).
The author answered the eight questions at the end of [design-database.md](../archive/design-database.md) (answers written in that file). This entry turns each answer into rules for the specification; the parts marked **Proposed** are the model's completions, to be confirmed one by one. After confirmation they become a decision and are applied to `spec/`, the tutorial (`databases.html`, `syslib.html`) and the tests of level 5.

(a) **Engine.** Author: only SQLite is embedded; DuckDB is a separate project, an independent Eve driver imported as a dependency; no engine of our own (postponed indefinitely). **Proposed:** the Eve database of a machine is one SQLite file per name in its `db/` folder, opened with `database.connect("eve")`; DuckDB is removed from F-DAT-08 and design-database.md §9 and becomes a library outside the VM (a later version, not 0.4). 

**Answer:** Agreed. DuckDB can be implemented in later version can be level7 item.  

(b) **Transactions.** Author: a transaction is the hidden purpose of a job. **Proposed:** no new syntax and no `job on`. Inside a job, the first write (a `!` method) on a connection begins a transaction on it; the job commits every open transaction at `done` or `stop` and rolls them back when it fails, before `recover` runs; `retry` runs the job again in a new transaction. Outside a job every write commits by itself. There are no `begin!`, `commit!` or `rollback!` methods in version 0.4: a long load is split into several jobs, and the last job that passed is the checkpoint (`jobs["name"].status`). A transient error (`DatabaseError.transient`: lost connection, deadlock, time-out) is the case for `retry`. 

**Answer:** Agreed

(c) **Records.** Author: a class of type `Record`, and an optional `Table` that is a buffer of records. **Proposed:** `class Order = {id: Integer, amount: Decimal} <: Record;` declares a row type (fields only, optional fields `T?`, no methods in version 0.4). `Table(:T)` is a library class: an in-memory buffer of records of one type, filled with `<+`, read by `for`, given to `load!` in batches (`Table(:Order)(capacity: 10000)`). `Table` is the buffer, never the name of a database table: the constants `TABLE` and `KEY` of design-database.md §7 are dropped (see d). 

**Answer:** Agreed

(d) **Mapping.** Author: no complex ORM; the user writes bare SQL and handles the complexity with smart jobs. **Proposed:** version 0.4 has no mapping methods: `find`, `save!` and `remove!` (design-database.md §7) are dropped, F-DAT-11 is dropped. What remains: `query(:T)(sql, params…)` gives a `Stream(:T)` of records matched by column name, `query(sql)` gives DataMaps, `query_one(:T)` gives a `T?`, `execute!(sql, params…)` gives the number of rows, and `load!(table, rows, mode: "insert" | "upsert" | "merge", key: (…))` writes in bulk. Parameters are always separate (`?`); SQL built with placeholders `{…}` is a compile warning. 

**Answer:** Agreed

(e) **Scripts and stored procedures.** Author: DDL is supported by scripts that Eve loads and sends to the database (install or alter a structure, disable indexes, prepare a bulk load); Eve may install stored procedures and call them through `external` functions with a signature, used in processes. **Proposed:** `sales.script!("sql/prepare.sql")` sends a SQL script file of the project (folder `sql/`) statement by statement, in the transaction of the job when the database has transactional DDL. A stored procedure is declared with `external` (D-056) and the name of the connection: `external procedure archive_orders(before: Date) in "sales";`, and the function below; the name in the database is the Eve name, or is given with `as "etl.archive_orders"`. Such a declaration is called in a process, a job or a procedure, like any input/output; a stored procedure without a result is declared as a `procedure`, one with a result as a `!` function (its result depends on the database, D-087): `external function total_sales!(region: String) => (@total: Decimal) in "sales";`. 

**Answer:** Agreed

(f) **`db sql` rights.** **Proposed:** Eve adds no rights layer: `db sql <name> "<statement>"` and `db script <name> <file>` run with the rights of the database user of the connection in `eve.cfg`; a read-only connection is a read-only database user. 

**Answer:** Agreed

Note 2026-10-10 on (g): point (2) below is void. It rests on the old meaning of `!` (D-081, "unsafe"); since D-089 `!` marks a stochastic function and the compiler decides thread safety, so an aspect that writes on its own connection needs no exception (design-database-core.md §6.1).

(g) **Parallel loads.** Author: no parallel pipelines inside one aspect; an aspect connects and runs its process in serial mode, a second aspect needs a second connection. The driver prepares the database with one aspect, then starts parallel groups that load independent groups of tables in hierarchy order (head tables first, then the tables that depend on them, the leaf tables last), and a closing job of the driver finalizes (reindex, enable constraints and triggers). **Proposed:** (1) a `Connection` is never passed to a started aspect or shared: each aspect connects by name; (2) exception to D-081: a `concurrent aspect` may call the `!` methods of a connection it opened itself, because it shares no state with its siblings; (3) one parallel group per level of the hierarchy, in the order written by the developer (D-140); (4) the methods `prepare!(tables)`, `activate!(tables)` and `reindex!(tables)` of `Connection` do what the commands `db prepare`, `db activate` and `db reindex` do (h). A test of level 5 shows the whole pattern with SQLite. 

**Answer:** Agreed

(h) **Commands.** Author: the `db` prefix is welcome; `db alter`, `db create`, `db prepare` (prepare a bulk load), `db activate` (enable the constraints again), `db reindex` (rebuild the indexes). **Proposed:** the list is `db list`, `db add`, `db remove`, `db test`, `db info`, `db tables`, `db describe`, `db sql`, `db script`, `db create` (a new database, empty or from a script), `db alter` (apply a DDL script), `db prepare` (disable indexes, constraints and triggers of the named tables), `db activate` (enable constraints and triggers), `db reindex`, `db migrate`, `db backup`, `db restore`, `db export`, `db import`, `db compact`, `db runs`. 

**Answer:**  Agreed

(i) **Drivers.** Author: SQLite first, then PostgreSQL, MySQL, MariaDB, MongoDB, then others; hosted providers Supabase, Neon and Cloudflare before other clouds. **Proposed:** Version 0.4: SQLite and PostgreSQL; Supabase and Neon speak the PostgreSQL protocol, so they come with it (a test against one of them). Then MySQL and MariaDB (one driver, Version 0.5), Cloudflare D1 (SQLite over HTTP, needs the HTTP client), then MongoDB: it is not SQL, so it gets a document API of its own (`find(:T)(filter)`, `insert!`), designed when it is planned. Oracle, SQL Server and ODBC come after. F-DAT-02 and design-database.md §12 follow this order. 

**Answer:** SQLite and PostgreSQL level5 others level8 and level9.

## Q-044 Data language: features and versions (2026-10-09)
The draft features of the section "Data language" above and its two open questions. **Proposed** for each feature: the version, and the shape when it is not settled yet.

(a) **Generators** (feature 1). The keyword `generator` (author's answer to review RSB-R03): `generator count_to(n: Integer) => (@x: Integer) is … yield x; … return;`, replacing the detection of `yield` in a method (D-067). Version 0.4, built on the baton tasks of stage A (D-144): a generator is a task that stops at `yield` and continues at the next read, so the tree walker can run it and F-LNG-12 does not wait for the bytecode (answers the open question "Generators and the bytecode" of feature_map.md). 

**Answer:** Agree, Generators are level4.

(b) **Record types** (feature 2). As Q-043c. Version 0.4. 

**Answer:** Yes,

(c) **Time types** (feature 3 and the open question of the names). `Date`, `Time` and `Duration` keep the names of the tutorial (datetime.html) and of level 4 (`30s`); `Instant` is a point in time in UTC (not Timestamp); `DateTime` is a date and a time with a zone (not LocalTime). Parsing and formats use the format codes of strings. Module `time`. Version 0.4. 

**Answer:** Agreed.

(d) **Decimal and optional types** (D-080, F-LNG-13, F-LNG-14). `Decimal` (`12.50d`) for SQL `NUMERIC` and `T?` for nullable columns are needed by the database layer: Version 0.4. 

**Answer:** Yes, level4

(e) **Bytes** (feature 4). Version 0.4: files, the network and compressed streams need it. 

**Answer:** Yes agreed.

(f) **Files and paths** (feature 5). Version 0.4, one module `fs` that also holds the path functions (`fs.join`, `fs.name`, `fs.parent`) and the operator `/`, instead of two modules `fs` and `path` (see Q-024). 

**Answer:** Agreed

(g) **JSON and CSV** (feature 6). Version 0.4, as the types `JSON` and `CSV` of Q-039. 

**Answer:** Agreed

(h) **HTTP client** (feature 7). Version 0.4, the client only (`http.get`, `http.post`, `http.request`, `HttpError.status`); the server stays in Version 0.5 with the service kind. 

**Answer:** Level 6.

(i) **Secrets** (feature 8). Version 0.4: every connection with a password needs it. 

**Answer:** With PostgreSQL, until we connect to databases not early.

(j) **Shell by argument list** (feature 9). Version 0.4: `run(command, arguments, cwd: dir)` gives the exit code and the output; `call` stays as it is (level 3). 

**Answer:** Agreed.

(k) **Compression** (feature 10). A gzip reader in Version 0.4 (`.csv.gz` files are common input of ETL), the rest (zip, writers) in Version 0.5. 

**Answer:** Level 5.

## Q-046 Database ORM and ACID: the language proposals of the two design files (2026-10-10)
Author request (2026-10-10): a robust ORM of Eve's own, aligned with the object model; SQLite as the core database and cache; the layers local app, Eve server (ACID session manager, cache) and remote database; mapping validated against the database in debug mode, a hard stop in production; updates that write only the changed fields; rollback rules; ETL with Unicode, transfer to a remote database, and reports back to files; new control statements where ACID needs them. The design is split in [design-database-core.md](../design-database-core.md) (SQLite, mapping, tracked records, transactions, direct SQL) and [design-database-remote.md](../design-database-remote.md) (drivers, the Eve server, protocol, ETL); each ends with its own questions. This request replaces Q-043c and Q-043d (no mapping); the other points of Q-043 stay. **Proposed**, one line per point; confirm or correct each:

(a) **P1 `table` declaration**: `table customers: Customer in "sales" is key (id); generated (id); version version; column name as "cust_name"; reference f to t; read only; temporary; end customers;`, a contextual keyword; `customers` is a `Table(:Customer)` bound to the database table (core §3.2). Replaces the constants `TABLE` and `KEY`, which D-123 forbids in a class body.

**Answer:** Agreed

(b) **P2 `commit;`** inside a job: flush, commit, new transaction; a job with `commit;` keeps a checkpoint in the same database (core §8.5).

**Answer:** Agreed

(c) **P3 `rollback;`** inside a job (also `rollback if cond;`): undo, the records keep their values and are detached (D-158), the job ends with the new status `rolled back` (P8), the process continues after `done` (core §8.2).

**Answer:** Agreed

(d) **P4 `$isolation`, `$lock_timeout`, `$read_only`**, set in the declarations of a job (core §8.3).

**Answer:** Agreed

(e) **P5 `retry after <duration>;`** and `$error.attempt` (core §11).

**Answer:** Agreed

(f) **P6 fatal errors**: `retry` and `resume` are refused for `MappingError` and for a partial `CommitError`; the process aborts, exit code 4 (core §5.3, §8.6).

**Answer:** Interesting. Intermediate type FatalError, that is inherited by MappingError and CommitError. If resume is isued, it has no effect, the resume fail and the error is not handled, it propagate.

(g) **P7 record methods**: a class derived from `Record` may declare methods; `validate` runs before every write (core §7.4). Changes Q-043c (records without methods).

**Answer:** Interesting. A record with methods that are triggered by writes on update or insert. Never thought of it. May be useful. Agreed.

(h) **P9 `cached <duration>;`** clause of `table`, served by the SQLite cache of the Eve server (remote §4.2).

**Answer:** Agreed. Cached in memory? 

(i) **Rules without new syntax**: tracked records with dirty fields and originals, updates of the dirty fields only, statement cache per dirty set, flush order by `reference`, records detached on rollback (D-158), optimistic `version` check, one session per connection and per process (core §6 to §8).

**Answer:** Agreed. Level5

(j) **Names by D-089** (2026-10-10): `!` marks a stochastic result, so every read of a database or a file carries it (`find!`, `where!`, `scan!`, `count!`, `query!`, `query_one!`, `checkpoint.read!`, `csv.read!`), a write without a result has none (`add`, `remove`, `flush`, `script`, `prepare`, `activate`, `reindex`, `checkpoint.write`, `csv.write`), and a write that returns counts keeps it (`execute!`, `load!`, like `Atomic.swap!`). Thread safety is decided by the compiler and does not depend on `!`. This also corrects Q-039e and Q-043d, written with the old meaning. Note: the tutorial page methods.html still teaches "a method whose name ends with `!` is an unsafe method" (D-081), which D-089 replaced.

**Answer:**
Yes, we must fix the tutorial "!" in not necesarly unsafe, is just a function that can't be optimized by memoization and has to be check if is used in parallel. So compiler must do a sofisticated lookup to mark a function trade safe but no attempt to optimize these functions. While a function witout !, could be optimizes using memoization especially if the parameters are a limited number of values: A small range or an ordinal. If the function has a large number of possible values, no memoization is possible. A special kind of memoization is possible in Eve using the SQL Light engine.
