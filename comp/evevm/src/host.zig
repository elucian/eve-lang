//! The `Host` of an interpreter: the table of functions that lets the database layer (evedb) use it
//! without importing it (comp/evecm/src/iface.zig). Every function takes the interpreter back from the
//! `*anyopaque` and calls the method of the same name.
const std = @import("std");
const evecm = @import("evecm");
const iface = evecm.iface;
const value = evecm.value;
const decimal = evecm.decimal;
const interp = @import("interp.zig");
const Interp = interp.Interp;

const Host = iface.Host;
const Node = evecm.ast.Node;
const Value = value.Value;
const Signal = value.Signal;

// Zig tip: `@ptrCast(@alignCast(p))` is the way back from `*anyopaque` to a typed pointer: `@alignCast`
// states the alignment that the real type needs (checked in a safe build) and `@ptrCast` changes the
// type. It is only correct because this file is the only one that puts an `*Interp` into the pointer.
fn me(p: *anyopaque) *Interp {
    return @ptrCast(@alignCast(p));
}

fn arena(p: *anyopaque) std.mem.Allocator {
    return me(p).a;
}
fn temp(p: *anyopaque) std.mem.Allocator {
    return me(p).t;
}
fn heap(p: *anyopaque) *evecm.heap.Heap {
    return me(p).h;
}
fn io(p: *anyopaque) ?std.Io {
    return me(p).io;
}
fn base(p: *anyopaque) Host {
    return of(me(p).base());
}
fn dataSlot(p: *anyopaque) *?*anyopaque {
    return &me(p).base().data_slot;
}
fn currentJob(p: *anyopaque) []const u8 {
    return me(p).current_job;
}
fn typeArgs(p: *anyopaque) []const *const Node {
    return me(p).type_args;
}
fn lastReport(p: *anyopaque) ?*value.Report {
    const r = &me(p).reports;
    return if (r.items.len == 0) null else &r.items[r.items.len - 1];
}
fn failMsg(p: *anyopaque, code: u8, msg: []const u8) Signal {
    return me(p).failMsg(code, msg);
}
fn eval(p: *anyopaque, n: *const Node) Signal!Value {
    return me(p).eval(n);
}
fn lookup(p: *anyopaque, name: []const u8) Signal!Value {
    return me(p).lookup(name);
}
fn define(p: *anyopaque, name: []const u8, v: Value, constant: bool) Signal!void {
    return me(p).define(name, v, constant);
}
fn setField(p: *anyopaque, o: *value.Object, name: []const u8, v: Value) Signal!void {
    return me(p).setField(o, name, v);
}
fn text(p: *anyopaque, v: Value) Signal![]const u8 {
    return me(p).text(v);
}
fn newStr(p: *anyopaque, bytes: []const u8) Signal!Value {
    return me(p).newStr(bytes);
}
fn newObject(p: *anyopaque) Signal!*value.Object {
    return me(p).newObject();
}
fn newList(p: *anyopaque, items: []const Value, array: bool) Signal!*value.List {
    return me(p).newList(items, array);
}
fn listAppend(p: *anyopaque, l: *value.List, v: Value) Signal!void {
    return me(p).listAppend(l, v);
}
fn setCell(p: *anyopaque, c: *Value, v: Value) void {
    me(p).setCell(c, v);
}
fn iterate(p: *anyopaque, v: Value) Signal![]const Value {
    return me(p).iterate(v);
}
fn callMethod(p: *anyopaque, recv: Value, name: []const u8, args: []const *const Node) Signal!Value {
    return me(p).callMethod(recv, name, args);
}
fn invokeWith(p: *anyopaque, f: *value.Func, recv: ?Value, args: []const value.Arg) Signal!Value {
    return me(p).invokeWith(f, recv, args);
}
fn overflow(p: *anyopaque) Signal {
    return me(p).overflow();
}
fn fromSqlText(p: *anyopaque, raw: []const u8, m: *const Node) Signal!Value {
    return me(p).fromSqlText(raw, m);
}
fn decFromReal(p: *anyopaque, x: f64) Signal!decimal.Dec {
    return me(p).decFromReal(x);
}

// Zig tip: a `const` of struct type at file level with function names as values is built at compile
// time; its address (`&vtable`) is the same for every interpreter, so a `Host` is just two pointers.
const vtable: Host.VTable = .{
    .arena = arena,
    .temp = temp,
    .heap = heap,
    .io = io,
    .base = base,
    .data_slot = dataSlot,
    .current_job = currentJob,
    .type_args = typeArgs,
    .last_report = lastReport,
    .fail_msg = failMsg,
    .eval = eval,
    .lookup = lookup,
    .define = define,
    .set_field = setField,
    .text = text,
    .new_str = newStr,
    .new_object = newObject,
    .new_list = newList,
    .list_append = listAppend,
    .set_cell = setCell,
    .iterate = iterate,
    .call_method = callMethod,
    .invoke_with = invokeWith,
    .overflow = overflow,
    .from_sql_text = fromSqlText,
    .dec_from_real = decFromReal,
};

/// The host of an interpreter.
pub fn of(it: *Interp) Host {
    return .{ .ptr = it, .vt = &vtable };
}
