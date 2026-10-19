# Drivers

Separate projects that give Eve access to database engines. A driver is **not a component** of Eve: it has its own build, it is not linked into `eve.exe`, and `eve` talks to it only through a documented protocol. The code that connects Eve to a database, the **client drivers** (`sqlite://`, `postgres://`, `evedb://`), is inside the runtime (`comp/evevm/src/db/`), because it builds Eve values; the table of those drivers is `comp/evevm/src/db/driver.zig` (D-200).

| Project | What it is | Program |
|---|---|---|
| [duckdb](duckdb/README.md) | a database server around DuckDB that answers as a PostgreSQL server and speaks the native protocol of Eve (column batches, test faults, a statement log); the test and analytic database of Eve | `bin/evedb.exe` (with `bin/duckdb.dll` until DuckDB is linked into it, S8.10a) |

## How a driver is shared with Eve

The wire protocol between a driver and the client driver of Eve is a Zig module, `ewp_protocol` (`duckdb/protocol/`), made by the build of the driver and by the root build from the same files (D-199). There is one protocol and one place to change it; `script/evedb_check.py` checks it from the other side, written from the protocol document alone.

## Building

From the root of the repository: `./run.sh build duckdb` (or from `drivers/duckdb`: `zig build -p ../..`). `eve db serve <cfg>` and `eve -s -db --serve <cfg>` start the server found beside `eve.exe`.

## License

The same license as the components: the Business Source License 1.1, [`comp/LICENSE`](../comp/LICENSE). A driver has no license file of its own (D-200).
