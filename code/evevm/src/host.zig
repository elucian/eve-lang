//! @eve-module evevm.host
//! @decision D-198
//! @tests the tests of code/evevm/src/db/ (they build values and raise errors through a `Host`)
//! The `Host` of the database layer: the part of the interpreter that `evevm.db` uses (memory, the heap, evaluating an
//! argument, errors, building values). A `Host` is one pointer to the interpreter and every method calls the interpreter
//! directly. It replaces the table of functions that lived in `code/evecm/src/iface.zig` (S8.4): the layer is a part of
//! this module now, so nothing needs to hide the interpreter behind a pointer cast.
const std = @import("std");
const evecm = @import("evecm");
const value = evecm.value;
const decimal = evecm.decimal;
const interp = @import("interp.zig");
const Interp = interp.Interp;

const Node = evecm.ast.Node;
const Value = value.Value;
const Signal = value.Signal;

// @eve-impl one connection for the run, guarded by one lock: the tasks of a run take turns in the database layer (design-task-heap.md, Q3)
// @invariant the thread that holds the lock may enter again (a query can call an Eve `sql function`, which can query)
var db_mutex: std.Io.Mutex = .init;
var db_owner: std.atomic.Value(usize) = .init(0);
var db_depth: u32 = 0;

/// Take the lock of the database layer; without an `io` there is one task and nothing to wait for.
pub fn enterDb(io: ?std.Io) void {
    const i = io orelse return;
    const me: usize = std.Thread.getCurrentId();
    if (db_owner.load(.acquire) == me) {
        db_depth += 1;
        return;
    }
    db_mutex.lockUncancelable(i);
    db_owner.store(me, .release);
    db_depth = 1;
}

/// Give the lock of the database layer back.
pub fn leaveDb(io: ?std.Io) void {
    const i = io orelse return;
    db_depth -= 1;
    if (db_depth == 0) {
        db_owner.store(0, .release);
        db_mutex.unlock(i);
    }
}

/// The services of the interpreter that the database layer uses.
pub const Host = struct {
    it: *Interp,

    /// The arena of the run: lives until the script is unloaded.
    pub fn arena(h: Host) std.mem.Allocator {
        return h.it.a;
    }
    /// Memory for the work of one statement.
    pub fn temp(h: Host) std.mem.Allocator {
        return h.it.t;
    }
    pub fn heap(h: Host) *evecm.heap.Heap {
        return h.it.h;
    }
    pub fn io(h: Host) ?std.Io {
        return h.it.io;
    }
    /// The host of the driver's interpreter: the one that keeps the state of the database layer.
    pub fn base(h: Host) Host {
        return of(h.it.base());
    }
    /// Where the database layer keeps its own state, in the driver's interpreter.
    pub fn dataSlot(h: Host) *?*anyopaque {
        return &h.it.base().data_slot;
    }
    pub fn currentJob(h: Host) []const u8 {
        return h.it.current_job;
    }
    /// The type arguments of the library call being made: `(:Row)` in `csv.read!(:Row)(path)`.
    pub fn typeArgs(h: Host) []const *const Node {
        return h.it.type_args;
    }
    /// The last error that was raised, to read its message.
    pub fn lastReport(h: Host) ?*value.Report {
        const r = &h.it.reports;
        return if (r.items.len == 0) null else &r.items[r.items.len - 1];
    }

    /// Raise an error with a code and a message.
    pub fn failWith(h: Host, code: u16, comptime fmt: []const u8, args: anytype) Signal {
        const msg = std.fmt.allocPrint(h.arena(), fmt, args) catch return error.OutOfMemory;
        return h.it.failMsg(code, msg);
    }
    pub fn fail(h: Host, comptime fmt: []const u8, args: anytype) Signal {
        return h.failWith(value.err_raise, fmt, args);
    }
    pub fn eval(h: Host, n: *const Node) Signal!Value {
        return h.it.eval(n);
    }
    pub fn lookup(h: Host, name: []const u8) Signal!Value {
        return h.it.lookup(name);
    }
    pub fn define(h: Host, name: []const u8, v: Value, constant: bool) Signal!void {
        return h.it.define(name, v, constant);
    }
    pub fn setField(h: Host, o: *value.Object, name: []const u8, v: Value) Signal!void {
        return h.it.setField(o, name, v);
    }
    pub fn text(h: Host, v: Value) Signal![]const u8 {
        return h.it.text(v);
    }
    pub fn newStr(h: Host, bytes: []const u8) Signal!Value {
        return h.it.newStr(bytes);
    }
    pub fn newObject(h: Host) Signal!*value.Object {
        return h.it.newObject();
    }
    pub fn newList(h: Host, items: []const Value, array: bool) Signal!*value.List {
        return h.it.newList(items, array);
    }
    pub fn listAppend(h: Host, l: *value.List, v: Value) Signal!void {
        return h.it.listAppend(l, v);
    }
    pub fn setCell(h: Host, c: *Value, v: Value) void {
        h.it.setCell(c, v);
    }
    pub fn iterate(h: Host, v: Value) Signal![]const Value {
        return h.it.iterate(v);
    }
    pub fn callMethod(h: Host, recv: Value, name: []const u8, args: []const *const Node) Signal!Value {
        return h.it.callMethod(recv, name, args);
    }
    pub fn invokeWith(h: Host, f: *value.Func, recv: ?Value, args: []const value.Arg) Signal!Value {
        return h.it.invokeWith(f, recv, args);
    }
    pub fn overflow(h: Host) Signal {
        return h.it.overflow();
    }
    pub fn fromSqlText(h: Host, raw: []const u8, m: *const Node) Signal!Value {
        return h.it.fromSqlText(raw, m);
    }
    pub fn decFromReal(h: Host, x: f64) Signal!decimal.Dec {
        return h.it.decFromReal(x);
    }
};

/// The host of an interpreter.
pub fn of(it: *Interp) Host {
    return .{ .it = it };
}
