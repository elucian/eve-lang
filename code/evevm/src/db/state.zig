//! The state of the database layer: what the interpreter used to keep in its own fields. One
//! `State` exists for a run, in the slot that the driver's interpreter gives (`Host.dataSlot`).
const std = @import("std");
const evecm = @import("evecm");
const value = evecm.value;
const Host = @import("../host.zig").Host;
const sqlite = @import("sqlite.zig");
const orm = @import("orm.zig");
const conn = @import("conn.zig");
const pgclient = @import("pgclient.zig");
const ewpdriver = @import("ewpdriver.zig");
const columnar = @import("columnar.zig");

pub const State = struct {
    /// The databases the script opened, by the handle number kept in its `Connection` objects, and whether a
    /// transaction of a job is open on each (database.md#transactions).
    dbs: std.ArrayList(*sqlite.Db) = .empty,
    tx: std.ArrayList(bool) = .empty,
    /// The declared tables and their objects, the connections by name, the class of the `Connection` objects.
    tables: std.ArrayList(*orm.Table) = .empty,
    table_nodes: std.ArrayList(*const evecm.ast.Node) = .empty,
    table_class: ?*value.Class = null,
    conn_names: std.StringHashMapUnmanaged(usize) = .empty,
    conn_class: ?*value.Class = null,
    /// The PostgreSQL connections of the program (`postgres://` in `eve.cfg`, README.md of evedb section 5B), by the handle
    /// number of their objects, their names, and the class of their objects.
    pgs: std.ArrayList(*pgclient.Client) = .empty,
    pg_names: std.StringHashMapUnmanaged(usize) = .empty,
    pg_class: ?*value.Class = null,
    /// The connections of evedb's native protocol (`evedb://`, README.md of evedb section 5.5), their names and their class.
    evs: std.ArrayList(*ewpdriver.Ev) = .empty,
    ev_names: std.StringHashMapUnmanaged(usize) = .empty,
    ev_class: ?*value.Class = null,
    /// The `Memory` tables of the program (columnar, D-184) by the handle number kept in their objects, and the class of their
    /// column objects.
    mems: std.ArrayList(*columnar.Table) = .empty,
    column_class: ?*value.Class = null,
    /// The `sql function`s of the program, registered on every SQLite connection (D-166); the interpreter that runs
    /// the statement now (a `sql function` runs there); and why the last call of one failed: the message of
    /// `$err_sql`, or a signal such as `Panic` that must go on once the statement has stopped.
    sql_funcs: std.ArrayList(*conn.SqlFn) = .empty,
    sql_caller: ?Host = null,
    sql_fail: ?[]const u8 = null,
    sql_signal: ?value.Signal = null,
    /// The records the session tracks and the changes that wait for a flush, the core database of the checkpoints.
    tracks: std.AutoHashMapUnmanaged(*value.Object, *orm.Track) = .empty,
    track_list: std.ArrayList(*orm.Track) = .empty,
    pending: std.ArrayList(*orm.Track) = .empty,
    core_db: ?*sqlite.Db = null,
};

/// The state of the run, made at the first use. It lives in the arena of the driver's interpreter.
pub fn state(it: Host) *State {
    const slot = it.base().dataSlot();
    if (slot.* == null) {
        const s = it.base().arena().create(State) catch @panic("out of memory");
        s.* = .{};
        slot.* = s;
    }
    return @ptrCast(@alignCast(slot.*.?));
}
