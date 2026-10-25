# Phase 1-5 — Stabilize levels 1 to 5

> Written 2026-10-20. Goal: levels 1 to 5 complete and trustworthy: every feature of those levels is `done`, tested on both engines, and described in the spec. Levels 6 and 7 are in `phase-6-machine.md` and `phase-7-web.md`; the open architecture steps (S8.x) are in `phase-8-architecture.md`.

Where the work stands (`python generator/evegen.py status`): level 1 has 5 partial features, level 2 one, level 3 seven partial and one open, level 4 eight partial and two open, level 5 fourteen partial and eight open. 440 conformance tests, 20 bytecode tests and the scaffold test pass; the gaps are features with no test yet, not failing tests.

## The rule of a step

A step is done only when all of these hold. Nothing else counts.

1. **Failing test first.** The missing behavior is a test in `test/levelN/` with an `/*@expect*/` block and its `features` field in `test/levelN/levelN.json`. It fails before the work (a test that already passes tests nothing new).
2. The test passes on the tree walker, and on the bytecode machine (`python script/runtest.py <test> --both`).
3. The rule is in the spec (page and anchor, no reference to this folder) and the test has a `** spec:` line.
4. The `status` of the feature in `spec/features/levelN.json` is set (`done`, or `partial` with the remaining items named in its page); `python generator/evegen.py all` and `check` are clean.
5. A shortcut left behind is one line in `backlog/tech-debt.md`.

The common gate of every step: `zig build test`, `python script/runtest.py all --eve temp/rel/bin/eve.exe` (ReleaseSafe build), `python script/bctest.py`, and `python script/bmark.py --check` when the VM changed. A step that changes a rule the author has not decided first raises a question in `decision/levelN.md` and moves on to the next unblocked step.

Sizes: S is a day or less, M a few days, L a week or more (guesses, not measurements).

## Stage 0 — The base (do first)

### S15.0 Status audit `[x]` (M)
- **Change:** for each of the 40 `partial` or `open` features of levels 1 to 5, list the missing behaviors as items in the page of the feature (`spec/features/levelN/F-XXX-nn.md`, a "Missing" list). Set `done` where nothing is missing. Each item that is a behavior gets a failing test in the steps below.
- **Gate:** `python generator/evegen.py check -v` shows every `partial` feature with a "Missing" list; no `done` feature without a test.
- **Result (2026-10-21):** 47 features (not 40) are `partial` or `open` in levels 1 to 5; each page has a `## Missing` list, and `evegen check` fails when one is absent (levels 1 to 5). No feature of levels 1 to 5 was set to `done`: every one still has a missing item. Checked by running a probe script: `read`, `sort`, `$EVE_*`, `$cores`, `-p`, `Date`, `Duration`, `Uuid`, `Bytes`, `path`, `http`, `gzip` are undefined; `s[a..b]`, `upper`, `trim`, `replace`, `secret.get` (environment) and `time.now!` work, `time.parse` rejects ISO 8601, `os.platform` is not a member. The 18 warnings (`done` without a test) are all in the `all` level (tools and VM), outside this phase.

### S15.1 Safety net `[x]` (S)
- **Change:** CI runs `zig build test`, `runtest.py all --both`, `tagcheck.py` and `evegen check` on every push (Windows and Linux; `.github/workflows/ci.yml` exists, check it runs); find the flaky unit test (the binary run with `--listen`, review R2-VM-R01); make `python script/runtest.py all` print one summary line with the tracking-file diff.
- **Gate:** a pushed commit shows a green run on both systems.
- **State (2026-10-21):** the Linux gate exists: `python script/wsl-gate.py` (WSL, Ubuntu 24.04, Zig and Node installed in the home folder, the committed HEAD cloned to `~/eve-gate`, the steps of `ci.yml`, log in `temp/output-linux/gate.log`); `--quick` skips the unit tests. It found and fixed five Linux defects: `hostname!` buffer size, `libduckdb.so` not installed next to `evedb` (rpath `$ORIGIN`), the HTTP door without `SO_REUSEADDR` (a restart failed with `AddressInUse`), the tests starting `eve`/`python` by name (the runner now puts the machine under test first on PATH and makes a `python` link), the generator ordering paths by case on Linux; plus `bctest.py` rewriting the tracking file in CI (`--no-update`). `ci.yml` also builds `evedb`. Local gate green on both systems: Windows (unit tests, `all --both` 440, `bctest.py`) and Linux (all steps). GitHub run ff256b1 is green on Windows and Ubuntu; `continue-on-error` for Ubuntu is removed.
**TODO** detailed instructions to resolve the issues.

### S15.2 Open questions that block levels 1 to 5 `[x]` (S, the author)
- **Answered 2026-10-21:** Q-061 → D-206 (only the primary aspect starts concurrent aspects; an exclusive aspect starts nothing in parallel; a concurrent aspect may have private parallel processes), Q-065 → D-207 (option (a), a `recover` region in a function, procedure and method: already built, tests b55 to b58), Q-027 → D-209 (a template is a `Text` with `{var}`, no loops), Q-028 → D-208 (HTTP client level 5, server level 6).
- Q-069, Q-070 and Q-071 (S15.10, S15.11) were answered the same day: D-210, D-211, D-212. `python script/plan.py status` lists the questions that are still open.

## Level 1 — one script

### S15.10 Console and exceptions `[x]` (M)
- **Features:** F-LIB-01, F-LIB-02. **Missing:** `read` (a line from standard input, with an end-of-input value); `exception.eve` and `io.eve` are drafts the VM does not load: either load them or remove them and say in the spec that the names are built in.
- **Tests:** `read` with piped input (`"args"`/stdin key in the runner if needed); `Error` and `Warning` construction, `warn`.
- **State (2026-10-21): done.** `read(prompt)` gives `String?`, `null` at the end of the input (D-210, test a96, `spec/library/builtins.md`, runner key `"stdin"`). The draft files `io.eve` and `exception.eve` are deleted and the names are built in (D-211, TD-3 closed). The classes `Error`/`Warning`, `warn` and `raise(code, message)` move to S15.31 (F-LIB-02 stays `partial`, F-LIB-01 is `done`).

### S15.11 Command line and variables `[x]` (M)
- **Features:** F-STR-05, F-STR-07. **Missing:** `-p`/`--param` mapped to `main` parameters and `eve script.eve -h` from `** @param` comments; the `$EVE_*` variables (`$EVE_HOME`, `$EVE_LIB`, `$EVE_LIB_PATH`, `$EVE_CORE_DB`) readable from a script.
- **Tests:** a script with parameters, the generated help, each `$EVE_*` variable.
- **State (2026-10-21): done.** The `$EVE_*` variables (test a97, TD-60) and the parameters of a script: `-p name=value` with the types of `process main`, `-h` after the script, exit 64 for a missing parameter, comments `** @param name:Type; description` (D-212, tests a98 to a100, `semantics/aspects.md#parameters-on-the-command-line`). F-STR-05 is `done`; F-STR-07 stays `partial` (`$EVE_DIR`, `$EVE_ASP`). TD-62: `-p` with `-loc`/`-rem`.

### S15.12 Core semantics pages `[x]` (M)
- **Feature:** F-SPEC-03. **Missing pages in `spec/semantics/`:** scopes, topology, collections and objects. Write them from the tests and the tutorial; each rule gets an anchor that a test already names.
- **Gate:** every `** spec:` line of the level 1 tests resolves (`evegen check` has no spec error).
- **State (2026-10-21): done.** Pages `scopes.md`, `collections.md` and `topology.md`, written from the tests and from probes of the machine; the tests a17 to a23, a35, a36, a38, a45, a82, a83 and a88 name their anchors; new tests a101 to a103 (scopes). F-SPEC-03 is `done`. Found on the way and settled by the author (D-213, TD-63 closed): a loop has one scope, a `new` in its body fails at the second cycle, in both engines (tests a104, a105).
**answer**
DT-63. If a variable is created with new in internal scope it can hide the external variable but only one time. A second iteration will fail because the variable already exist in local scope. The loop do not create 2 scopes.

## Level 2 — a project

### S15.20 Configuration files `[x]` (S)
- **Feature:** F-STR-06. **Missing:** the `setup` command is a stub; `-s`/`-e file.cfg` load `$key = value` files (TD-26: end-of-line comments, sections, escapes in values).
- **Tests:** a project test that sets a port and a database path through a `.cfg`.
- **State (2026-10-21):** done. `-e`/`--setup file.cfg` and the REPL command `setup` load `$key = value` lines (Integer, Real, Logic, String with escapes, `#` comments, also at the end of a line) as read-only `$` variables; a missing file exits 66, a bad line 65. Tests b60 to b62, F-STR-06 is `done`. Sections were never specified and are not built (TD-26 is about the Eve library `config.parse` of the machine files, a different format).

## Level 3 — modules and classes

### S15.30 Library basics `[~]` (L, split into steps L0 to L9)
- **Features:** F-LIB-03, F-DOC-05, F-SPEC-04. **Missing:** `sort` and search on lists; the String gaps G-7 and TD-25 (slices `s[a..b]`, Unicode `upper`, `lower`, `trim`, `replace`); the other built-ins named in the spec; `eve --doc` for every standard module; one library page per module in `spec/library/` (strings, math, collections are missing).
- **Tests:** one per function; each page lists only functions that have a test.
- **Plan (2026-10-21, for review):** `design/design-libraries.md` section 0: L0 audit and corrections, L1 core (strings, lists, maps), L2 math, L3 stats, L4 time and calendar, L5 text and encoding, L6 business, L7 engineering, L8 data, L9 ids and compression; each library is one step with the recipe of section 0.5 (page first, failing tests, code, docs, gate). Questions Q-072 to Q-077 wait for the author. Nothing is built until the author has reviewed the steps; then one library at a time.
**agree** Document the libraries and finalize the design of libraries: design-libraries.md, if a library is large and has many aspects like math it can be a folder side by side with sys. Design a sofisticated library for general purpose data, math, bussines, statistics, engineering, no graphics or games yet.
- **State (2026-10-24):** L0, L1 and L2 are done. L2 (`lib/math/`, page `spec/library/math.md`): `basic`, `explog`, `trig`, `constants`, `numtheory`, `linear`, `random`, `rational`, `complex`, and the specification module `lib/math.eve` that re-exports them (D-215); tests a110 to a115, c43 to c53; the language features it needed: re-export, `use (*) alias`, first import wins with the warning `$wrn_hidden` (D-216), the types Rational (D-217) and Complex (D-218), the placeholders `{Type}` of the test runner (D-219), a call of a numeric library function without a scope (D-220). L3 statistics: the design is written for review (`design-libraries.md` section 0.8, questions Q-097 to Q-105 in `decision/level3.md`); the page and the tests wait for the answers. Next after L3: L4 time (needs S15.50).


### S15.31 Typed exceptions and static checks `[ ]` (M)
- **Features:** F-LNG-15, F-LNG-16. **Missing:** error classes with fields, `recover` by type, exit-code mapping (`recover` in a function, procedure and method is built: D-207); the type checks of `check.zig` (argument types, return types, assignment) before the run, exit 65.
- **Tests:** negative tests (`"syntax_error"`/exit 65) for each check; positive tests for the recover by type.

### S15.32 Projects, loader, `external` `[ ]` (M)
- **Features:** F-STR-04, F-VM-03. **Missing:** the project variables readable from a script (see S15.11); `data/` and `web/` folders; the loader binds `external` for user modules (TD-2, TD-3: forms the parser cannot read in `lib/sys/io.eve`, `exception.eve`).
- **Tests:** a module with an `external` bound to a native; a project that reads `data/` through `$EVE_HOME`.

### S15.33 REPL `[ ]` (M)
- **Features:** F-TLS-02, F-TLS-03. **Missing:** the interactive interpreter (statements and expressions typed at the prompt, a session scope); the commands `compile`, `debug`, `begin`, `enter`, `print`, `resume`, `setup`.
- **Gate:** a scripted session through `eve --stdio` and `vm.eval` (test with `command`/`client`); the remote-machine word `select` belongs to phase 6.

## Level 4 — parallel processing

### S15.40 Language side `[ ]` (M)
- **Features:** F-LNG-11, F-LNG-17, F-LNG-18. **Missing:** check of the generic constraint `(:T <: Comparable)` (compile error); `Stream` operators that level 4 owns (`batch`, `split` done); the `Atomic` operations `add`, `get!`, `swap!` on real threads (needs S15.41).
- **Tests:** constraint violated (exit 65); an atomic counter under parallel tasks gives the same total at every run (`--repeat 5`).

### S15.41 Scheduler and memory `[ ]` (L)
- **Features:** F-MTK-02, F-VM-05, F-SPEC-05. **Missing:** stage B of the scheduler (`$cores`, `$max_parallel`, several cores); an arena per task so memory is freed while tasks run (`p4a_parallel_sum` peaks at 39 MB); the multitasking spec, the checker and the tests brought to the rule of D-206 (first failing tests: an exclusive aspect with a `parallel` group or a `start` is a compile error; a concurrent aspect called from an exclusive aspect is a compile error; tests d39, d40 and the level 4 tests that break the rule are rewritten; the limit of D-140 goes away).
- **Gate:** `--repeat 20` of every `test/level4` test; `bmark.py --check` (no benchmark more than 10% slower); `EVE_GC_VERIFY=1` on levels 4 and 5.

### S15.42 Observability and tools `[ ]` (M)
- **Features:** F-LIB-11, F-TLS-04, F-TLS-08, F-TLS-09. **Missing:** structured logs, job events, run reports, trace ids (shared with F-DAT-06, S15.64); the debugger's remaining commands in `manual/usage.md`; `eve fmt` and `eve lint` (a first version: layout rules from `lexical.md`, unused names); a language server is not part of level 4 (backlog).
- **Tests:** a log file test per record kind; fmt idempotence on every file of `test/`.

## Level 5 — data and database

### S15.50 Types for data `[ ]` (M)
- **Features:** F-LNG-13, F-LNG-14, F-LIB-06. **Missing:** `Date`, `Time`, `Duration`, `Bytes`, `Uuid`, `Rational` where the spec names them; zones and parse/format in `time`; the full optional type `T?` (non-null checks at compile time).
- **Tests:** one per type and per conversion; the cases of `data-language.md`.
- **State (2026-10-24):** `Rational` is done (D-217, F-LNG-30) and `Complex` too (D-218, F-LNG-31); their data edges (JSON, CSV, SQL, command line) are TD-68 and TD-70. Open: `Date`, `Time`, `Duration`, `Bytes`, `Uuid`, zones and the optional type `T?`.
- **Design accepted (2026-10-24, D-221):** `design/design-data-types.md`, `spec/library/time.md`, `spec/library/bytes.md`; all proposals accepted, the printed `Duration` is ISO 8601, the zone data is built into the Eve machine. **D0 built:** the type `Duration` (microseconds), the units `us ms s m h`, the operators with `Instant`, `time.seconds/millis/micros/sleep`, `Duration.parse` (tests e120 to e122, bc21). **D1 built:** `Date` and `Time` (calendar, operators, `time` functions and methods, CSV/JSON/SQLite; tests e123 to e126, bc22, benchmark `p1g_dates`). **D3 built:** `format`, `parse`, the letters `yyyy MM dd DDD EEE HH hh a mm ss S ww Q X`, placeholders `{d % pattern}` (tests e127, e128, benchmark `p1h_time_format`). **M0.1 built** (D-222): the meta database with the time zones, `zone`, `meta`, `database.connect("meta")`. **D2 built:** `Zone`, `DateTime`, local time with gaps and overlaps, `local_zone!`, `today!(zone)`, the zone letters (tests e133 to e137, benchmark `p1j_datetime`). **D4 built (2026-10-24):** `Bytes` is a value of its own (the value, `0x` print, `Bytes.from_hex`, `Bytes.from_base64`, `Bytes.of`, `hex()`, `base64()`, `base64url()`, `text()`, `length()`, `index_of`, `contains`, `starts_with`, `ends_with`, index and slice from 1, `+`, `fs.read_bytes!`; tests e139 to e141, `spec/library/bytes.md`); what is not built is in TD-81 to TD-84 (`BytesBuilder`, `crypto`, `Stream(:Bytes)`, the SQL and file mappings, the compile-time `Bytes + String` error). **D5 built (2026-10-25):** `Uuid` is a value of 16 bytes (parse in any case, canonical text, versions 3, 4, 5 and 7, `u.version()`, `u.bytes()`, `Uuid.from_bytes`, `u.instant()`, the namespaces, `Uuid.nil`, the module `uuid`; tests e142 to e144, `spec/library/bytes.md#uuid`); the SQL and JSON mappings and the braces in Eve text are TD-86 and TD-85. **D6 built (2026-10-25):** the default `??` (lexer, parser level, tree walker; the bytecode engine bridges it), the checker rules of `types.md#narrowing-and-the-default` in `code/evecp/src/nullable.zig` and `check.zig`, tests e145 to e150; the open parts are TD-87. Every step D0 to D6 is built; S15.50 stays open until the mappings of TD-83 and TD-86 move to S15.51 and S15.60, and TD-87 is paid. Next: M0.2 and M0.3 of the meta database (`design-meta-database.md`).


### S15.51 Files, formats, compression `[ ]` (M)
- **Features:** F-LIB-04, F-LIB-05, F-LIB-09. **Missing:** the `path` module, bytes, globbing; the write side of every format; `gzip` (read, write, stream; TD-24) and zip. XML and Parquet move to the backlog unless the author asks.
- **Tests:** round trips (JSON and CSV write then read give the same rows); a gzip file read as a line stream.
- **State (2026-10-25):** first slice built: `fs.glob!` (test e151, `globlib.zig`), the gzip reader of `csv`, `json`, `txt` and `fs.lines!` for a `.gz` path (test e152, `gziplib.zig`; a file that is not gzip is `$err_format`), and the round trip of CSV and JSON records (test e153; it passed before the step and is kept as coverage). The `path` module of the plan does not exist by design: the path functions are in `fs` (data-language.md). **Second slice (2026-10-25):** `gzip.open!` as a `Stream(:Bytes)` in chunks of 64 KiB (test e154, `lib/sys/gzip.eve`, native `gzipModule` in `dlib.zig`); the write side of TXT is tested by e37 and e82. The author put the zip and gzip writers in level 5 (D-224; the spec states the proposed API, not built). Open: a `Stream(:Bytes)` as the source of a reader (TD-83), and streaming inflation (TD-88).

### S15.52 Edges: shell, secrets, HTTP client `[ ]` (M)
- **Features:** F-LIB-07, F-LIB-08, F-NET-01. **Missing:** `os` pipes/`call` beyond `run!`, and streaming output of `run!` (TD-9); `Secret` type and `secret.get` from environment and file (a vault is later); an HTTP client over `net` (requests, headers, JSON bodies, time-outs; TLS is TD-11 and waits for the decision in phase 6/7).
- **Tests:** a `Secret` never prints its value; the client against the local `service.serve` test server.

### S15.53 Collections speed `[ ]` (M)
- **Features:** F-VM-06 (and F-DAT-05 for the in-memory table). **Missing:** hashed and sorted maps, sets, ropes for text; the `Memory` table. Arrow compatibility is backlog.
- **Gate:** the benchmarks of collections and strings (`p1c`, `p1d`) improve or hold; `bmark.py --check`.

### S15.60 The Eve database and checkpoints `[ ]` (L)
- **Features:** F-DAT-08, F-DAT-04, F-DAT-01. **Missing:** the core database `db/local.db` with `$EVE_CORE_DB` (checkpoints, run history, metadata); restart of a killed load from its checkpoint (the test kills the process and starts it again); the rest of the connection layer named in `database.md` (bulk load options, savepoints are in the open points).
- **Tests:** kill-and-restart on a 100,000-row load ends with the same rows as an uninterrupted load.

### S15.61 Procedures and SQL functions `[ ]` (M)
- **Features:** F-DAT-13, F-DAT-14. **Missing:** `external` at run time against a database with stored procedures (PostgreSQL), `proc reload`, `db.call`; `sql function` on DuckDB belongs to phase 7.
- **Tests:** against SQLite and the PostgreSQL test server (`script/pg_check.py`).

### S15.62 Pipeline model and lineage `[ ]` (L)
- **Features:** F-DAT-03, F-DAT-06, F-LNG-17 (level 5 part). **Missing:** pipeline stages with back-pressure over a database; the lineage and run report (inputs, outputs, row counts, durations per job and aspect, stored in the core database); streams adopt `map`, `filter`, `merge`, `window`, `parallel(n)`.
- **Tests:** an ETL from CSV to SQLite with a report that matches the row counts.

### S15.63 Database admin and migrations `[ ]` (M)
- **Features:** F-DAT-09, F-DAT-10. **Missing:** the `db` commands of `database.md#admin-commands` (`list`, `add`, `test`, `info`, `tables`, `describe`, `sql`, `create`, `backup`, `restore`, `export`, `import`, `compact`, `runs`); numbered migrations in `db/migrations/<name>/` applied by `db migrate`.
- **Tests:** command tests (`"command"` key) on a temp project.

### S15.64 Close level 5 `[ ]` (S)
- **Features:** F-VM-11 (closed by S8.10), F-DOC-02 (the tutorial, last in the order of the work). Update `spec/index.md`; run the full gate on both engines; `evegen status` shows levels 1 to 5 with no `partial` or `open`.

## Order and dependencies

S15.0 → S15.1 → levels 1, 2, 3 (S15.10 to S15.33) → level 4 (S15.40 to S15.42) → level 5 (S15.50 to S15.64). Inside level 5: types (S15.50) before formats (S15.51); the Eve database (S15.60) before lineage (S15.62) and admin (S15.63). Steps of different levels that touch different files can run in parallel; the libraries (S15.30, S15.51, S15.52) share the `lib/` and `syslib.zig` files, so do them one after the other.
