# 08 Data, I/O and the ETL model (`RIO`)

## Advantages

**RIO-A01 The language already has an ETL skeleton.** Jobs (steps with status and retry), aspects (isolated units with inputs/outputs), `parallel` + BSP (partitioned transforms), channels (pipelines), exit codes (scheduler integration), log files in `$EVE_OUT` (D-057). Few general-purpose languages have these in the core.

**RIO-A02 Project tests as folders with `data/` and `out/`.** D-073: input files in, expected files out, compared by the runner. This is exactly how ETL jobs should be tested (golden files).

**RIO-A03 Shell integration.** `call` with pipes (command.html) makes Eve usable as glue around existing tools on day one.

## Disadvantages

**RIO-D01 There is no data library.** `evevm/lib/` has `io.eve` (stdout, stdin, stderr, two log files) and `exception.eve`. No file API (open, read lines, write, list a folder, glob, stat), no path module beyond the "smart `/`" rule (D-031), no JSON, CSV, XML, Parquet, no compression, no HTTP client, no database driver. The manifest and databases.html describe all of them as goals. A client for internet ETL can't be written yet.

**RIO-D02 databases.html is a design sketch in an obsolete dialect.** It uses `class … = {…} <: orcl.Database is`, `update record1:` blocks with colons, `let demoDB = set db := new …`, `db.query(query_template ? source)` (the `?` template operator was removed by D-059), typos (`deleded1`), credentials passed as globals. Its ORM with "memory tables mirrored automatically in the database" is the hardest database abstraction to build and the one ETL needs least.

**RIO-D03 Shell `call` is injection-prone and stateless.** `call "cd \s{$HOME}/test"; call "ls -l *.dat" +> files;` (command.html): interpolating into a shell string is the classic injection hole, and `cd` in one `call` does not affect the next one (each call is a new shell), so the example does not do what it says.

**RIO-D04 `print` signature disagrees with itself.** `io.eve` declares `print(*args: String, sep := " ")`; D-029 says `print(*args, separator = ",")`; D-063 says `print (a, b)` joins with `,`. The parameter is named `sep` in one place and `separator` in the other, the default is a space in one and a comma in the other, and the `String` type of `args` contradicts printing numbers.

## Antipatterns

**RIO-X01 ORM-first database design.** Mapping tables to classes with automatic mirroring, record caching, sessions and "the compiler complains if the table does not exist" (databases.html). ORMs are the wrong default for ETL (set-based work, bulk loads, schema drift) and they make the compiler depend on a live database.

**RIO-X02 Credentials as script globals.** `new OracleSession(user:$user, password:$password, …)`. A secret in a variable is printed by the first debug `print`, logged by the first error report, and sent by the first remote call.

**RIO-X03 Row-at-a-time loops as the bulk path.** "For bulk operations… using an Eve loop" (`for record in table do record.delete() if …`). N round trips for N rows.

## Recommendations

**RIO-R01 Specify the 0.1 library surface (signatures only, then implement).**

| Module | Minimum |
|---|---|
| `fs` | `read_text`, `write_text`, `read_bytes`, `write_bytes`, `lines` (a Stream), `list`, `glob`, `exists`, `remove`, `move`, `mkdir` |
| `path` | `join`, `base`, `dir`, `ext`, `normalize`, `relative` (the `/` operator calls `join`) |
| `json` | `parse(text) -> Value`, `print(v, indent)`, `decode(text, :T)` into a record type |
| `csv` | `read(path, header, sep) -> Stream(Record)`, `write(path, rows)` |
| `http` | `get`, `post`, `request(method, url, headers, body, timeout)` returning `Response {status, headers, body}` |
| `db` | `connect(url, secret)`, `query(sql, params) -> Stream(Record)`, `execute`, `transaction do … done`, `bulk_load(table, stream)` |
| `time` | `now`, `parse`, `format`, zones |
| `secret` | `get(name)` from env, file or vault; a `Secret` type that never prints |
| `zip`/`gzip` | stream codecs |

**RIO-R02 SQL-first, parameterized, streaming database access.** `for row in db.query("select … where id = ?", id)`; typed decode into a `record`; bulk insert/upsert from a `Stream`; transactions as a block that commits at `done` and rolls back on error — reuse the job semantics (`retry` a transaction is natural). An ORM, if ever, is a library on top.

**RIO-R03 Shell by argument list, not string.** `run("ls", ["-l", path], cwd: dir) -> Result {code, out, err}`. Keep `call "…"` only as a lint-warned convenience.

**RIO-R04 An ETL pattern in the language reference.** Extract (sources → `Stream`), Transform (pure functions, parallel stages), Load (sinks with batching, idempotent upserts, checkpoints). Jobs give retries; `recover` gives dead-letter handling; `finalize` writes the run report. Teach this as *the* Eve way (`RTU`).

**RIO-R05 Checkpoints and idempotency.** A job can declare `checkpoint key` so a re-run after failure resumes at the last committed batch. This is the feature that makes a pipeline restartable and is rarely in the language anywhere.

**RIO-R06 Lineage for free.** Each job and each `apply` records inputs, outputs, row counts and durations into the run report (`RST-R07`); the server later shows it.
