//! evedb: the database layer of Eve (design-packages.md §3). It holds SQLite (the core database
//! and the databases of a script), the object-relational layer (`table`, records, transactions of
//! a job), the connections and the `sql function`s. It imports `evecm` only: the interpreter is
//! reached through the `Host` interface and reaches this module through `Data`.
const std = @import("std");
const evecm = @import("evecm");
const iface = evecm.iface;
const value = evecm.value;
const Host = iface.Host;
const Signal = value.Signal;
const Node = evecm.ast.Node;

/// SQLite, bound for Zig.
pub const sqlite = @import("sqlite.zig");
/// Connections, statements and `sql function`s.
pub const conn = @import("conn.zig");
/// Tables, records and the transaction of a job.
pub const orm = @import("orm.zig");
pub const state = @import("state.zig");

// Zig tip: each entry of `data` is a small function that has the signature of the interface and
// calls the real one. A function `fn (Host, ...) T` cannot be taken from a function that has other
// parameters, and the wrappers also hide the layout of the files behind the table.
fn isConnection(it: Host, v: value.Value) bool {
    return v == .object and v.object.class != null and v.object.class == state.state(it).conn_class;
}

/// Every table of the program is known before the first is declared: the order of the inserts depends on them all.
fn declareTables(it: Host, kids: []const *const Node) Signal!void {
    const st = state.state(it);
    for (kids) |d| if (d.tag == .table_decl) try st.table_nodes.append(it.base().arena(), d);
    for (kids) |d| if (d.tag == .table_decl) try orm.declareTable(it, d);
}

fn closeDatabases(it: Host) void {
    for (state.state(it).dbs.items) |db| db.close();
}

/// The table of functions that the interpreter calls: set `evevm.interp.data_api = &evedb.data` at the start.
pub const data: iface.Data = .{
    .connect = conn.connect,
    .connection_call = conn.connectionCall,
    .is_connection = isConnection,
    .checkpoint_call = orm.checkpointCall,
    .is_table = orm.isTable,
    .table_call = orm.tableCall,
    .table_add = orm.tableAdd,
    .declare_tables = declareTables,
    .before_change = orm.beforeChange,
    .after_change = orm.afterChange,
    .active = orm.active,
    .commit_job = orm.commitJob,
    .end_job = orm.endJob,
    .register_sql_function = conn.registerSqlFunction,
    .close_core = orm.closeCore,
    .close_databases = closeDatabases,
};

test {
    _ = sqlite;
    _ = conn;
    _ = orm;
}
