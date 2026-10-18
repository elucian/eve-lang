//! The two interfaces between the runtime (evevm) and the database layer (evedb), which never
//! import each other (design-packages.md §3, §8). Both are a table of functions, the shape of
//! `std.mem.Allocator` and `std.Io`:
//!
//! - `Host` is what the interpreter offers to the database layer: memory, the heap, evaluation
//!   of an argument, errors, and the building of values. evevm fills it in.
//! - `Data` is what the database layer offers to the interpreter: the library `database`, the
//!   methods of a connection and of a table, the transaction of a job. evedb fills it in.
const std = @import("std");
const ast = @import("ast.zig");
const decimal = @import("decimal.zig");
const heap_mod = @import("heap.zig");
const HeapT = heap_mod.Heap;
const value = @import("value.zig");

const Node = ast.Node;
const Value = value.Value;
const Signal = value.Signal;

// Zig tip: an interface in Zig is a struct with a pointer to the thing that does the work
// (`ptr: *anyopaque`, a pointer whose type is forgotten) and a pointer to a table of functions
// (`vt`). The caller never sees the type behind `ptr`; each function of the table takes it back
// as its first argument and turns it into the real type with `@ptrCast`. The same pattern is in
// the standard library (`std.mem.Allocator`, `std.Io`), so it costs one indirect call.
/// The services of the interpreter that the database layer uses.
pub const Host = struct {
    ptr: *anyopaque,
    vt: *const VTable,

    pub const VTable = struct {
        // the state of the interpreter that the database layer reads
        arena: *const fn (*anyopaque) std.mem.Allocator,
        temp: *const fn (*anyopaque) std.mem.Allocator,
        heap: *const fn (*anyopaque) *HeapT,
        io: *const fn (*anyopaque) ?std.Io,
        base: *const fn (*anyopaque) Host,
        data_slot: *const fn (*anyopaque) *?*anyopaque,
        current_job: *const fn (*anyopaque) []const u8,
        type_args: *const fn (*anyopaque) []const *const Node,
        last_report: *const fn (*anyopaque) ?*value.Report,
        // what the database layer asks the interpreter to do
        fail_msg: *const fn (*anyopaque, u8, []const u8) Signal,
        eval: *const fn (*anyopaque, *const Node) Signal!Value,
        lookup: *const fn (*anyopaque, []const u8) Signal!Value,
        define: *const fn (*anyopaque, []const u8, Value, bool) Signal!void,
        set_field: *const fn (*anyopaque, *value.Object, []const u8, Value) Signal!void,
        text: *const fn (*anyopaque, Value) Signal![]const u8,
        new_str: *const fn (*anyopaque, []const u8) Signal!Value,
        new_object: *const fn (*anyopaque) Signal!*value.Object,
        new_list: *const fn (*anyopaque, []const Value, bool) Signal!*value.List,
        list_append: *const fn (*anyopaque, *value.List, Value) Signal!void,
        set_cell: *const fn (*anyopaque, *Value, Value) void,
        iterate: *const fn (*anyopaque, Value) Signal![]const Value,
        call_method: *const fn (*anyopaque, Value, []const u8, []const *const Node) Signal!Value,
        invoke_with: *const fn (*anyopaque, *value.Func, ?Value, []const value.Arg) Signal!Value,
        overflow: *const fn (*anyopaque) Signal,
        from_sql_text: *const fn (*anyopaque, []const u8, *const Node) Signal!Value,
        dec_from_real: *const fn (*anyopaque, f64) Signal!decimal.Dec,
    };

    // Zig tip: the wrappers below let the database code keep writing `it.eval(n)` and `it.newStr(s)`
    // as when `it` was the interpreter: a method of `Host` calls the function of the table with the
    // pointer. The getters that were fields (`it.t`) are methods now: `it.temp()`.
    /// The arena of the run: lives until the script is unloaded.
    pub fn arena(h: Host) std.mem.Allocator {
        return h.vt.arena(h.ptr);
    }
    /// Memory for the work of one statement.
    pub fn temp(h: Host) std.mem.Allocator {
        return h.vt.temp(h.ptr);
    }
    pub fn heap(h: Host) *HeapT {
        return h.vt.heap(h.ptr);
    }
    pub fn io(h: Host) ?std.Io {
        return h.vt.io(h.ptr);
    }
    /// The host of the driver's interpreter: the one that keeps the state of the database layer.
    pub fn base(h: Host) Host {
        return h.vt.base(h.ptr);
    }
    /// Where the database layer keeps its own state, in the driver's interpreter.
    pub fn dataSlot(h: Host) *?*anyopaque {
        return h.vt.data_slot(h.ptr);
    }
    pub fn currentJob(h: Host) []const u8 {
        return h.vt.current_job(h.ptr);
    }
    /// The type arguments of the library call being made: `(:Row)` in `csv.read!(:Row)(path)`.
    pub fn typeArgs(h: Host) []const *const Node {
        return h.vt.type_args(h.ptr);
    }
    /// The last error that was raised, to read its message.
    pub fn lastReport(h: Host) ?*value.Report {
        return h.vt.last_report(h.ptr);
    }

    /// Raise an error with a code and a message.
    pub fn failWith(h: Host, code: u8, comptime fmt: []const u8, args: anytype) Signal {
        const msg = std.fmt.allocPrint(h.arena(), fmt, args) catch return error.OutOfMemory;
        return h.vt.fail_msg(h.ptr, code, msg);
    }
    pub fn fail(h: Host, comptime fmt: []const u8, args: anytype) Signal {
        return h.failWith(value.err_raise, fmt, args);
    }
    pub fn eval(h: Host, n: *const Node) Signal!Value {
        return h.vt.eval(h.ptr, n);
    }
    pub fn lookup(h: Host, name: []const u8) Signal!Value {
        return h.vt.lookup(h.ptr, name);
    }
    pub fn define(h: Host, name: []const u8, v: Value, constant: bool) Signal!void {
        return h.vt.define(h.ptr, name, v, constant);
    }
    pub fn setField(h: Host, o: *value.Object, name: []const u8, v: Value) Signal!void {
        return h.vt.set_field(h.ptr, o, name, v);
    }
    pub fn text(h: Host, v: Value) Signal![]const u8 {
        return h.vt.text(h.ptr, v);
    }
    pub fn newStr(h: Host, bytes: []const u8) Signal!Value {
        return h.vt.new_str(h.ptr, bytes);
    }
    pub fn newObject(h: Host) Signal!*value.Object {
        return h.vt.new_object(h.ptr);
    }
    pub fn newList(h: Host, items: []const Value, array: bool) Signal!*value.List {
        return h.vt.new_list(h.ptr, items, array);
    }
    pub fn listAppend(h: Host, l: *value.List, v: Value) Signal!void {
        return h.vt.list_append(h.ptr, l, v);
    }
    pub fn setCell(h: Host, c: *Value, v: Value) void {
        h.vt.set_cell(h.ptr, c, v);
    }
    pub fn iterate(h: Host, v: Value) Signal![]const Value {
        return h.vt.iterate(h.ptr, v);
    }
    pub fn callMethod(h: Host, recv: Value, name: []const u8, args: []const *const Node) Signal!Value {
        return h.vt.call_method(h.ptr, recv, name, args);
    }
    pub fn invokeWith(h: Host, f: *value.Func, recv: ?Value, args: []const value.Arg) Signal!Value {
        return h.vt.invoke_with(h.ptr, f, recv, args);
    }
    pub fn overflow(h: Host) Signal {
        return h.vt.overflow(h.ptr);
    }
    pub fn fromSqlText(h: Host, raw: []const u8, m: *const Node) Signal!Value {
        return h.vt.from_sql_text(h.ptr, raw, m);
    }
    pub fn decFromReal(h: Host, x: f64) Signal!decimal.Dec {
        return h.vt.dec_from_real(h.ptr, x);
    }
};

// Zig tip: unlike `Host`, `Data` has no pointer of its own: the state of the database layer lives
// in the interpreter (`Host.dataSlot`), so one table of functions serves every interpreter, the
// driver's and the ones of the tasks. Every function receives the `Host` of the interpreter that
// makes the call.
/// What the database layer offers to the interpreter.
pub const Data = struct {
    /// `database.connect(name)`.
    connect: *const fn (Host, []const *const Node) Signal!Value,
    /// A method of a `Connection` object.
    connection_call: *const fn (Host, *value.Object, []const u8, []const *const Node) Signal!Value,
    is_connection: *const fn (Host, Value) bool,
    /// The library `checkpoint`.
    checkpoint_call: *const fn (Host, []const u8, []const *const Node, []const *const Node) Signal!?Value,
    is_table: *const fn (Host, Value) bool,
    table_call: *const fn (Host, *value.Object, []const u8, []const *const Node) Signal!Value,
    table_add: *const fn (Host, *value.Object, Value) Signal!void,
    /// The `table` declarations among the declarations of a driver or an aspect.
    declare_tables: *const fn (Host, []const *const Node) Signal!void,
    before_change: *const fn (Host, *value.Object, []const u8, Value) Signal!void,
    after_change: *const fn (Host, *value.Object) Signal!void,
    /// Does the session track records now (a job is open)?
    active: *const fn (Host) bool,
    commit_job: *const fn (Host) Signal!void,
    end_job: *const fn (Host, bool) Signal!void,
    register_sql_function: *const fn (Host, *value.Func) Signal!void,
    close_core: *const fn (Host) void,
    close_databases: *const fn (Host) void,
    /// A class derived from `Memory` makes a columnar table (null for any other class); the methods of that table and of its
    /// column objects (D-184).
    memory_new: *const fn (Host, *value.Class) Signal!?Value,
    is_memory: *const fn (Host, Value) bool,
    memory_call: *const fn (Host, *value.Object, []const u8, []const *const Node) Signal!Value,
    is_column: *const fn (Host, Value) bool,
    column_call: *const fn (Host, *value.Object, []const u8, []const *const Node) Signal!Value,
};
