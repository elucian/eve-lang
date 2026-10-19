# Design: how database drivers are implemented

Question of the author (2026-10-19, Q-068 point 2): how can drivers be implemented, and what is the best way: individual DLL files, or embedded in `evevm`? Status: **accepted** in D-200 (2026-10-19): client drivers embedded, DuckDB a server with DuckDB embedded in `evedb.exe`, a driver table, no Eve driver DLLs.

## What a driver is in Eve

A driver lets `database.connect("name")` talk to a database. `eve.cfg` maps the name to a URL, and the scheme of the URL chooses the driver:

| Scheme | Driver | Where it is today |
|---|---|---|
| `sqlite://` | SQLite, compiled in (C amalgamation) | `eve.exe` |
| `postgres://` | PostgreSQL client, written in Zig over TCP; also reaches evedb | `eve.exe` (`pgclient.zig`, `pgdriver.zig`) |
| `evedb://` | the native protocol of the DuckDB server (column batches) | `eve.exe` (`ewpdriver.zig`) |
| `duckdb` engine | DuckDB itself | `evedb.exe` + `duckdb.dll`, a **separate process** (a server) |

So there are already two kinds of thing: the **client driver** (Zig code that maps the database to Eve values: records, jobs, transactions, types) and the **engine** behind it. The client driver is always code inside the VM, because it builds Eve values. The question is only about the engine, and about where future client drivers live.

## Facts that decide it

1. **The boundary is not a C interface.** The code that builds Eve values uses the interpreter through `Host` and `Data` (about 47 function slots) and passes Zig allocators, the heap and syntax-tree nodes. Zig 0.17 has no stable ABI. A driver in its own DLL would need a **new C-ABI layer** for all of that, with the exact same compiler and Eve version on both sides. D-198 removes `Host` and `Data` to simplify; a DLL driver brings them back, harder.
2. **Reference-counted memory is shared.** A driver that keeps or frees a value wrongly corrupts the VM. The project already needs `EVE_GC_VERIFY` to find such errors inside one module; across a DLL they would be harder to find.
3. **Pure-protocol drivers are small.** The PostgreSQL client, the evedb client and their glue are about 1,250 lines of Zig. `eve.exe` is 3.9 MB with SQLite inside. A DLL saves almost nothing.
4. **The heavy engine is the exception.** `duckdb.dll` is 35 MB. Only DuckDB (and in the future vendor libraries such as Oracle's client or ODBC) is large enough for the question to matter.
5. **Native code loaded by name is a risk.** SQLite is built with extension loading **off** on purpose. A driver chosen by a name in `eve.cfg` and loaded from a DLL would reopen that door.
6. **Nothing loads a library at run time today** (no `DynLib` in the code), and every platform needs its own form (`.dll`, `.so`, `.dylib`).

## The ways to have a driver

| Way | `eve.exe` | Eve ABI needed | Isolation | Judgment |
|---|---|---|---|---|
| **A. Embedded** in `evevm`: Zig code (or C compiled in) | grows by the size of the driver | no | none needed | **Best for every driver that speaks a wire protocol or is a small library**: PostgreSQL, MySQL/MariaDB, SQL Server (TDS), SQLite |
| **B. Separate server process** with a protocol (today's `evedb.exe`) | unchanged | no, only the wire protocol | full: a crash stays in the server | **Best for a big engine** such as DuckDB; also gives the PostgreSQL face and the faults for tests. Cost: a socket per call (column batches make it cheap) and no Eve code inside the SQL |
| **C. Glue in `evevm`, vendor library loaded at first use** (`DynLib` on `duckdb.dll`, through DuckDB's own C API) | stays small; needs the DLL only if used | no: the C API of the vendor is the ABI | none: a crash of the library takes `eve` with it | The way to have DuckDB **inside** Eve, if wanted: in process, fastest, and `sql function` in Eve could work on DuckDB through its scalar-function API (not tried; the binding does not use it today). Reverses D-187 |
| **D. An Eve driver DLL** (a plug-in with an Eve ABI) | smallest | **yes, a new one** | none | **Not recommended** (facts 1, 2, 5). Reconsider only when third parties must ship drivers without rebuilding `eve` |

## Recommendation

1. **Embed every client driver in `evevm`** (way A), as the author said in D-199 (5): "once we implement a new driver it will be included in VM". A new driver is one Zig file in `evevm/src/db/` plus its protocol module.
2. **Keep the DuckDB engine as a server** (way B) for now. It costs nothing to change later, because the Eve side is the client driver `evedb://`, which does not care what is behind the socket.
3. **If DuckDB must run inside Eve** (Eve functions in SQL, or the speed of no socket), build **way C**, not D. The vendor's C API is already a stable ABI; no Eve ABI is invented.
4. **Do not build Eve driver DLLs** (way D) until a third party needs it.

## A step that helps in every case

Adding a driver today means editing `conn.zig` in about five places: `if (pgdriver.isPgUrl(url))`, the same for the object test, the method call, the end of a transaction, and the state. A small **driver table** (one struct of functions per driver, chosen by the URL scheme) makes a driver one file and one line in the table. It would be a stage after the interfaces `Host` and `Data` are gone (S8.4), because it is simpler to write when the driver may call the interpreter directly. *Not in the plan yet: the author decides.*
**answer** This is good, add to plan.

## What is not decided

- Whether DuckDB stays a server (B) or also gets an in-process form (C): Q-068 point 2. Nothing in S8.1 to S8.4 depends on it; S8.5 only moves the folder.
**answer** DuckDB stay a server.
