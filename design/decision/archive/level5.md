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
- **Level.** With `apply` only, a hybrid script is level 2; with `parallel` and `start`, level 4. Tests: one in `test/level2` (an exclusive aspect applied), one in `test/level4` (this example), and the compile errors above. Feature F-STR-09 in `version_map.md`.

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
Applied (2026-10-10): `spec/library/database.md`, `semantics/variables.md`, `design/design-database-core.md`, tutorial `databases.html`, `design/version_map.md` (F-DAT-08).

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
