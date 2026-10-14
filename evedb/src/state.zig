//! The state of the database layer: what the interpreter used to keep in its own fields. One
//! `State` exists for a run, in the slot that the driver's interpreter gives (`Host.dataSlot`).
const std = @import("std");
const evecm = @import("evecm");
const value = evecm.value;
const Host = evecm.iface.Host;
const sqlite = @import("sqlite.zig");
const orm = @import("orm.zig");
const conn = @import("conn.zig");

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

// Zig tip: `@ptrCast(@alignCast(p))` turns the `*anyopaque` of the slot back into a `*State`: the
// interpreter keeps the pointer without knowing its type, and only this file knows it. `@alignCast`
// checks (in a safe build) that the address fits the alignment of `State`.
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
