//! `Memory` tables in Eve scripts (D-184, Q-059): a class derived from `Memory` is a columnar table.
//!
//!     class Sales = {id: Integer, region: String, price: Real, note: String?} <: Memory;
//!     new s := Sales();
//!     s.add(1, "north", 2.5, null);
//!     print s.price.sum();
//!     new big := s.take(s.price.filter(">", 2.0));
//!     s.load(shop, "sales");                      ** the explicit move into SQLite
//!     s.store(shop, "select id, region, price, note from sales");   ** and back, by column name
//!
//! The object has one field for each declared field; the field holds a `Column` object, so `s.price.sum()` is a method of the
//! column, named by the field (the answer to Q-059 (c)). The data is a `columnar.Table` kept in the state of the database layer.
const std = @import("std");
const evecm = @import("evecm");
const ast = evecm.ast;
const value = evecm.value;
const Host = evecm.iface.Host;
const Node = ast.Node;
const Value = value.Value;
const Object = value.Object;
const Class = value.Class;
const Signal = value.Signal;
const columnar = @import("columnar.zig");
const sqlite = @import("sqlite.zig");
const conn = @import("conn.zig");
const orm = @import("orm.zig");
const state = @import("state.zig").state;
const ewpdriver = @import("ewpdriver.zig");

const err_argument = value.err_argument;
const err_convert = value.err_convert;
const err_null = value.err_null;
const err_index = value.err_index;
const err_io = value.err_io;

// Zig tip: the columns live outside the heap of the interpreter, in the general purpose allocator of the program, because a
// column grows by doubling and the arena of a run never gives memory back. They are freed when the run ends (`closeAll`).
const gpa = std.heap.smp_allocator;

// Zig tip: `a orelse b` unwraps an optional: the value when there is one, else `b` (which may be `return` or `continue`,
// leaving the function or the loop).
/// Is this class derived from `Memory`?
pub fn isMemoryClass(cls: *const Class) bool {
    const n = cls.node orelse return false;
    return n.kids.len > 1 and n.kids[1].tag == .name and std.mem.eql(u8, n.kids[1].text, "Memory");
}

// Zig tip: a plain function: the types of the parameters and of the result are written out, and Zig has no default
// arguments, so a call always passes every parameter.
pub fn isMemory(_: Host, v: Value) bool {
    return v == .object and v.object.class != null and isMemoryClass(v.object.class.?) and value.fieldOf(v.object, "handle") != null;
}

// Zig tip: `isColumn` relies on the same Zig feature as `isMemoryClass` above: see the tip there.
pub fn isColumn(it: Host, v: Value) bool {
    const cc = state(it).column_class orelse return false;
    return v == .object and v.object.class == cc;
}

// Zig tip: `members` relies on the same Zig feature as `isMemory` above: see the tip there.
fn members(cls: *const Class) []const *const Node {
    return cls.node.?.kids[0].kids;
}

// Zig tip: the type of a field decides the type of its column: whole numbers are INTEGER, `Real` and `Float` are REAL, `Logic`
// is BOOLEAN, `String` is TEXT. A `Decimal` or an `Instant` has no column yet, and the error says so (a `Decimal` can be kept
// as a `Real` or as a `String`).
fn kindOf(it: Host, m: *const Node) Signal!columnar.Kind {
    const ty = ast.baseType(m.ty);
    const eql = std.mem.eql;
    if (eql(u8, ty, "Integer") or eql(u8, ty, "Natural") or eql(u8, ty, "Short") or eql(u8, ty, "Byte") or eql(u8, ty, "Huge")) return .integer;
    if (eql(u8, ty, "Real") or eql(u8, ty, "Float")) return .real;
    if (eql(u8, ty, "Logic")) return .boolean;
    if (eql(u8, ty, "String")) return .text;
    return it.failWith(err_argument, "a Memory table can not hold the field {s}: {s} (use Integer, Real, Logic or String)", .{ m.text, ty });
}

// Zig tip: a cast is written with a builtin: `@intCast` checks (in safe builds) that the number fits the smaller type,
// `@bitCast` keeps the bits and changes the type, `@truncate` keeps the low bits.
fn idxOf(obj: *Object, field: []const u8) usize {
    return @intCast(value.intOf(value.fieldOf(obj, field).?));
}

// Zig tip: `tableOf` relies on the same Zig feature as `isMemory` above: see the tip there.
fn tableOf(it: Host, obj: *Object) *columnar.Table {
    return state(it).mems.items[idxOf(obj, "handle")];
}

// Zig tip: `columnObject` relies on the same Zig feature as `kindOf` above: see the tip there.
fn columnObject(it: Host, mem: usize, k: usize, name: []const u8) Signal!Value {
    const b = state(it);
    if (b.column_class == null) {
        const cls = try it.arena().create(Class);
        cls.* = .{ .name = "Column" };
        b.column_class = cls;
    }
    const obj = try it.newObject();
    try it.setField(obj, "table", .{ .int = @intCast(mem) });
    try it.setField(obj, "col", .{ .int = @intCast(k) });
    try it.setField(obj, "name", try it.newStr(name));
    obj.class = b.column_class;
    return .{ .object = obj };
}

// Zig tip: `wrap` relies on the same Zig feature as `kindOf` above: see the tip there.
/// Make the object of a table that is already in the state: its fields are the columns.
fn wrap(it: Host, cls: *Class, mem: usize) Signal!Value {
    const obj = try it.newObject();
    try it.setField(obj, "handle", .{ .int = @intCast(mem) });
    for (members(cls), 0..) |m, k| try it.setField(obj, m.text, try columnObject(it, mem, k, m.text));
    obj.class = cls;
    return .{ .object = obj };
}

// Zig tip: `register` relies on the same Zig feature as `kindOf` above: see the tip there.
fn register(it: Host, t: *columnar.Table) Signal!usize {
    const b = state(it);
    try b.mems.append(it.base().arena(), t);
    return b.mems.items.len - 1;
}

// Zig tip: `errdefer` runs its statement only when the function leaves with an error, so what was made before the failure
// is freed and nothing leaks; on success it does nothing.
/// `Sales()`: when the class is derived from `Memory`, an empty table with a column for each field; else null.
pub fn memoryNew(it: Host, cls: *Class) Signal!?Value {
    if (!isMemoryClass(cls)) return null;
    const t = try gpa.create(columnar.Table);
    t.* = columnar.Table.init(gpa);
    errdefer {
        t.deinit();
        gpa.destroy(t);
    }
    for (members(cls)) |m| _ = try t.addColumn(m.text, try kindOf(it, m));
    return try wrap(it, cls, try register(it, t));
}

// Zig tip: `closeAll` relies on the same Zig feature as `isMemory` above: see the tip there.
/// At the end of the run: free the tables.
pub fn closeAll(it: Host) void {
    const b = state(it);
    for (b.mems.items) |t| {
        t.deinit();
        gpa.destroy(t);
    }
    b.mems.clearRetainingCapacity();
}

// Zig tip: the result type `?T` is an optional: a value or `null`. The caller must unwrap it (`if (x) |v|`, `orelse`), so a
// missing value can never be used by accident.
fn isWhole(v: Value) ?i64 {
    return switch (v) {
        .int, .nat, .byte, .short, .huge => |n| n,
        else => null,
    };
}

// Zig tip: a row is checked in full before any column is touched, so a wrong value in the third field cannot leave the first
// two columns one cell longer than the rest. `optional` comes from the declaration of the field (`String?`).
fn check(it: Host, kind: columnar.Kind, optional: bool, name: []const u8, v: Value) Signal!void {
    if (v == .nil) {
        if (!optional) return it.failWith(err_null, "{s} is not optional: a Memory table can not hold null there", .{name});
        return;
    }
    const ok = switch (kind) {
        .integer => isWhole(v) != null,
        .real => isWhole(v) != null or v == .real or v == .float,
        .boolean => v == .bool,
        .text => v == .str,
        else => false,
    };
    if (!ok) return it.failWith(err_convert, "the field {s} can not take a {s}", .{ name, value.typeName(v) });
}

// Zig tip: `put` relies on the same Zig feature as `kindOf` above: see the tip there.
fn put(t: *columnar.Table, k: usize, v: Value) Signal!void {
    if (v == .nil) return t.appendNull(k);
    switch (t.cols.items[k].kind) {
        .integer => try t.appendInt(k, isWhole(v).?),
        .real => try t.appendReal(k, if (isWhole(v)) |n| @floatFromInt(n) else if (v == .real) v.real else v.float),
        .boolean => try t.appendInt(k, @intFromBool(v.bool)),
        .text => try t.appendText(k, v.str),
        else => unreachable,
    }
}

// Zig tip: `addRow` relies on the same Zig feature as `kindOf` above: see the tip there.
fn addRow(it: Host, cls: *Class, t: *columnar.Table, row: []const Value) Signal!void {
    const ms = members(cls);
    for (ms, row, 0..) |m, v, k| try check(it, t.cols.items[k].kind, ast.isOptional(m.ty), m.text, v);
    for (row, 0..) |v, k| try put(t, k, v);
    t.endRow();
}

// Zig tip: `connectionOf` relies on the same Zig feature as `kindOf` above: see the tip there.
fn connectionOf(it: Host, v: Value) Signal!struct { idx: usize, db: *sqlite.Db } {
    const b = state(it);
    if (v != .object or v.object.class == null or v.object.class != b.conn_class) return it.failWith(err_argument, "expected a connection", .{});
    const idx = idxOf(v.object, "handle");
    const db = b.dbs.items[idx];
    if (db.handle == null) return it.fail("the connection is closed", .{});
    return .{ .idx = idx, .db = db };
}

// Zig tip: `memoryCall` relies on the same Zig feature as `memoryNew` above: see the tip there.
/// A method of a `Memory` table.
pub fn memoryCall(it: Host, obj: *Object, name: []const u8, args: []const *const Node) Signal!Value {
    const eql = std.mem.eql;
    const cls = obj.class.?;
    const t = tableOf(it, obj);
    if (eql(u8, name, "count") or eql(u8, name, "length")) return .{ .int = @intCast(t.rows) };
    if (eql(u8, name, "add")) {
        const ms = members(cls);
        if (args.len != ms.len) return it.failWith(err_argument, "{s}.add takes {d} values, one for each field", .{ cls.name, ms.len });
        const row = try it.temp().alloc(Value, args.len);
        for (args, row) |a, *slot| slot.* = try it.eval(a);
        try addRow(it, cls, t, row);
        return .nil;
    }
    if (eql(u8, name, "take")) {
        if (args.len != 1) return it.failWith(err_argument, "take needs the list of rows", .{});
        const rows = try it.iterate(try it.eval(args[0]));
        const sel = try it.temp().alloc(u32, rows.len);
        for (rows, sel) |r, *slot| {
            const n = isWhole(r) orelse return it.failWith(err_argument, "take: a row number is a whole number", .{});
            if (n < 0 or n >= t.rows) return it.failWith(err_index, "take: row {d} is not in the table", .{n});
            slot.* = @intCast(n);
        }
        var out = t.take(sel) catch return error.OutOfMemory;
        errdefer out.deinit();
        const nt = try gpa.create(columnar.Table);
        nt.* = out;
        return try wrap(it, cls, try register(it, nt));
    }
    if (eql(u8, name, "load")) {
        if (args.len != 2) return it.failWith(err_argument, "load needs a connection and a table name", .{});
        const target = try it.eval(args[0]);
        const table = try it.text(try it.eval(args[1]));
        // an evedb connection takes the columns as batches (the fast path of D-187)
        if (ewpdriver.evOf(it, target)) |ev| return ewpdriver.load(it, ev, t, table);
        const c = try connectionOf(it, target);
        try conn.enlist(it, c.idx, c.db);
        try orm.flushConn(it, c.idx);
        t.toSqlite(c.db, table) catch return it.failWith(err_io, "DatabaseError: {s}", .{c.db.errorMessage()});
        return .{ .int = @intCast(t.rows) };
    }
    if (eql(u8, name, "store")) {
        if (args.len < 2) return it.failWith(err_argument, "store needs a connection and a select", .{});
        const source = try it.eval(args[0]);
        const sql = try it.text(try it.eval(args[1]));
        if (ewpdriver.evOf(it, source)) |ev| return ewpdriver.store(it, ev, cls, t, sql, args[2..]);
        const c = try connectionOf(it, source);
        var params: std.ArrayList(Value) = .empty;
        for (args[2..]) |a| try params.append(it.temp(), try it.eval(a));
        try conn.enlist(it, c.idx, c.db);
        try orm.flushConn(it, c.idx);
        var st = c.db.prepare(try it.temp().dupeZ(u8, sql)) catch
            return it.failWith(err_io, "DatabaseError: {s}: {s}", .{ c.db.errorMessage(), sql });
        defer st.finalize();
        try conn.bindAll(it, c.db, &st, params.items);
        const ms = members(cls);
        const colmap = try it.temp().alloc(u16, ms.len);
        for (ms, colmap) |m, *slot| {
            slot.* = for (0..st.columnCount()) |j| {
                if (std.mem.eql(u8, st.columnName(@intCast(j)), m.text)) break @intCast(j);
            } else return it.failWith(err_convert, "DatabaseError: the query has no column '{s}' for {s}", .{ m.text, cls.name });
        }
        const row = try it.temp().alloc(Value, ms.len);
        var n: i64 = 0;
        while (st.step() catch return it.failWith(err_io, "DatabaseError: {s}: {s}", .{ c.db.errorMessage(), sql })) {
            for (ms, colmap, row) |m, j, *slot| slot.* = try conn.columnValue(it, &st, j, m, cls.name);
            try addRow(it, cls, t, row);
            n += 1;
        }
        return .{ .int = n };
    }
    return it.fail("a Memory table has no method '{s}'", .{name});
}

// Zig tip: `cmpOf` relies on the same Zig feature as `kindOf` above: see the tip there.
fn cmpOf(it: Host, op: []const u8) Signal!columnar.Cmp {
    const eql = std.mem.eql;
    if (eql(u8, op, "=") or eql(u8, op, "==")) return .eq;
    if (eql(u8, op, "<>") or eql(u8, op, "!=")) return .ne;
    if (eql(u8, op, "<")) return .lt;
    if (eql(u8, op, "<=")) return .le;
    if (eql(u8, op, ">")) return .gt;
    if (eql(u8, op, ">=")) return .ge;
    return it.failWith(err_argument, "filter: '{s}' is not a comparison (= <> < <= > >=)", .{op});
}

// Zig tip: `defer` runs its statement when the scope ends, by any path (a `return`, an error, the end of the block), so a
// free or a close is written once, next to what it undoes.
/// A method of a column: `s.price.sum()`.
pub fn columnCall(it: Host, obj: *Object, name: []const u8, args: []const *const Node) Signal!Value {
    const eql = std.mem.eql;
    const b = state(it);
    const t = b.mems.items[idxOf(obj, "table")];
    const k = idxOf(obj, "col");
    const kind = t.cols.items[k].kind;
    if (eql(u8, name, "count")) return .{ .int = @intCast(t.countValid(k)) };
    if (eql(u8, name, "sum")) {
        return switch (kind) {
            .integer => .{ .int = t.sumInt(k) },
            .real => .{ .real = t.sumReal(k) },
            else => it.failWith(err_argument, "sum: {s} is not a number column", .{t.cols.items[k].name}),
        };
    }
    if (eql(u8, name, "min") or eql(u8, name, "max")) {
        const hi = eql(u8, name, "max");
        switch (kind) {
            .integer => return if (t.minMaxInt(k)) |m| .{ .int = m[@intFromBool(hi)] } else .nil,
            .real => return if (t.minMaxReal(k)) |m| .{ .real = m[@intFromBool(hi)] } else .nil,
            else => return it.failWith(err_argument, "{s}: {s} is not a number column", .{ name, t.cols.items[k].name }),
        }
    }
    if (eql(u8, name, "at")) {
        if (args.len != 1) return it.failWith(err_argument, "at needs a row number", .{});
        const n = isWhole(try it.eval(args[0])) orelse return it.failWith(err_argument, "at: a row number is a whole number", .{});
        if (n < 0 or n >= t.rows) return it.failWith(err_index, "at: row {d} is not in the table", .{n});
        const r: usize = @intCast(n);
        if (t.isNull(k, r)) return .nil;
        return switch (kind) {
            .integer => .{ .int = t.int(k, r) },
            .boolean => .{ .bool = t.int(k, r) != 0 },
            .real => .{ .real = t.real(k, r) },
            else => try it.newStr(t.text(k, r)),
        };
    }
    if (eql(u8, name, "filter")) {
        if (args.len != 2) return it.failWith(err_argument, "filter needs a comparison and a value: price.filter(\">\", 2.0)", .{});
        const cmp = try cmpOf(it, try it.text(try it.eval(args[0])));
        const v = try it.eval(args[1]);
        var sel: std.ArrayList(u32) = .empty;
        defer sel.deinit(gpa);
        switch (kind) {
            .integer => try t.filterInt(k, cmp, isWhole(v) orelse return it.failWith(err_argument, "filter: the value must be a whole number", .{}), &sel),
            .boolean => try t.filterInt(k, cmp, if (v == .bool) @intFromBool(v.bool) else return it.failWith(err_argument, "filter: the value must be a Logic", .{}), &sel),
            .real => try t.filterReal(k, cmp, if (isWhole(v)) |n| @floatFromInt(n) else if (v == .real) v.real else if (v == .float) v.float else return it.failWith(err_argument, "filter: the value must be a number", .{}), &sel),
            else => try t.filterText(k, cmp, if (v == .str) v.str else return it.failWith(err_argument, "filter: the value must be a String", .{}), &sel),
        }
        const out = try it.newList(&.{}, false);
        for (sel.items) |r| try it.listAppend(out, .{ .int = r });
        return .{ .list = out };
    }
    return it.fail("a column has no method '{s}'", .{name});
}
