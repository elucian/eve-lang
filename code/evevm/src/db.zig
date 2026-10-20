//! @eve-module evevm.db
//! @decision D-198, D-199
//! @tests the tests of the files in code/evevm/src/db/
//! The database layer of Eve inside the runtime (was the module `evedb`, design-packages.md §3): SQLite (the core database
//! and the databases of a script), the object-relational layer (`table`, records, transactions of a job), the connections,
//! the `sql function`s, the drivers `postgres://` and `evedb://` and the `Memory` tables. It is a part of `evevm`; the
//! DuckDB server is a separate program (`drivers/duckdb/`). The interpreter calls this layer directly and the layer reaches the
//! interpreter through `Host` (`host.zig`): the interfaces `Data` and `Host` of `evecm` are gone (S8.3, S8.4).
const std = @import("std");
const evecm = @import("evecm");
const value = evecm.value;
const Host = @import("host.zig").Host;
const Signal = value.Signal;
const Node = evecm.ast.Node;

/// SQLite, bound for Zig.
pub const sqlite = @import("db/sqlite.zig");
/// Connections, statements and `sql function`s.
pub const conn = @import("db/conn.zig");
/// Tables, records and the transaction of a job.
pub const orm = @import("db/orm.zig");
pub const state = @import("db/state.zig");
/// Columnar tables in memory, the tables of the computational pipelines (D-184).
pub const columnar = @import("db/columnar.zig");
/// The DBF file decoder and encoder: legacy ingestion only (D-184).
pub const dbf = @import("db/dbf.zig");
/// CSV, TXT, JSON and DBF files into a columnar table and into SQLite (D-184).
pub const importer = @import("db/importer.zig");
/// `Memory` tables in scripts (D-184).
pub const memory = @import("db/memory.zig");
/// The PostgreSQL protocol (client) and the Eve driver for `postgres://` connections (evedb README section 5B).
pub const pgclient = @import("db/pgclient.zig");
pub const pgdriver = @import("db/pgdriver.zig");
/// The Eve driver for evedb's native protocol, with the column batches of `Memory` tables (evedb README section 5.5).
pub const ewpdriver = @import("db/ewpdriver.zig");
/// The table of the drivers: `sqlite`, `postgres://`, `evedb://` (D-200).
pub const driver = @import("db/driver.zig");
pub const batch = @import("ewp_protocol").batch;

/// Every table of the program is known before the first is declared: the order of the inserts depends on them all.
pub fn declareTables(it: Host, kids: []const *const Node) Signal!void {
    const st = state.state(it);
    for (kids) |d| if (d.tag == .table_decl) try st.table_nodes.append(it.base().arena(), d);
    for (kids) |d| if (d.tag == .table_decl) try orm.declareTable(it, d);
}

pub fn closeDatabases(it: Host) void {
    driver.closeAll(it);
    memory.closeAll(it);
}

test {
    _ = sqlite;
    _ = conn;
    _ = orm;
    _ = columnar;
    _ = dbf;
    _ = importer;
    _ = memory;
    _ = pgclient;
    _ = pgdriver;
    _ = ewpdriver;
    _ = driver;
    _ = batch;
}
