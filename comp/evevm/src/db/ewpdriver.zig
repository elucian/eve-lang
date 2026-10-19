//! The Eve driver for evedb's native protocol (README.md section 5.5, D-187): `database "wh" = "evedb://host:8044/warehouse"`.
//!
//! The same methods as the other drivers (`execute!`, `query!`, `query_one!`, `script`, `close`, the transaction of a job), with
//! the parameters sent as typed values (no SQL text is built). And the fast path that the PostgreSQL protocol does not have:
//! `Memory.store(wh, select)` reads the result as **column batches** straight into the columns of a `Memory` table, and
//! `Memory.load(wh, name)` sends the columns as batches that evedb gives to DuckDB's Appender.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const evecm = @import("evecm");
const ast = evecm.ast;
const value = evecm.value;
const Host = @import("../host.zig").Host;
const Node = ast.Node;
const Value = value.Value;
const Object = value.Object;
const Class = value.Class;
const Signal = value.Signal;
const protocol = @import("ewp_protocol");
const ewp = protocol.ewp;
const batch = protocol.batch;
const client = protocol.client;
const columnar = @import("columnar.zig");
const conn = @import("conn.zig");
const state = @import("state.zig").state;

const err_argument = value.err_argument;
const err_file = value.err_file;
const err_io = value.err_io;
const err_null = value.err_null;
const err_convert = value.err_convert;

// Zig tip: a `struct` groups named fields, and may hold functions (its methods) and constants; a field with a default value
// may be left out when a value is made with `.{ ... }`.
/// One open connection: the client of the frames and the transaction a job began on it.
pub const Ev = struct {
    c: *client.Conn,
    tx: ?[16]u8 = null,
    closed: bool = false,
};

// Zig tip: a plain function: the types of the parameters and of the result are written out, and Zig has no default
// arguments, so a call always passes every parameter.
/// Is the URL one of evedb's native protocol?
pub fn isEvUrl(url: []const u8) bool {
    return std.mem.startsWith(u8, url, "evedb://");
}

// Zig tip: a URL is cut with `indexOfScalar` and slices: `evedb://token@host:port/database`; every part is a slice of the URL,
// nothing is allocated. The token (the secret of a server that is not in test mode) is optional.
/// The parts of `evedb://[token@]host:port/database`.
pub fn parseUrl(url: []const u8) ?struct { token: []const u8, host_port: []const u8, database: []const u8 } {
    if (!isEvUrl(url)) return null;
    var rest = url["evedb://".len..];
    var token: []const u8 = "";
    if (std.mem.lastIndexOfScalar(u8, rest, '@')) |at| {
        token = rest[0..at];
        rest = rest[at + 1 ..];
    }
    const sl = std.mem.indexOfScalar(u8, rest, '/') orelse return null;
    const host_port = rest[0..sl];
    const database = rest[sl + 1 ..];
    if (database.len == 0 or std.mem.indexOfScalar(u8, host_port, ':') == null) return null;
    return .{ .token = token, .host_port = host_port, .database = database };
}

// Zig tip: the result type `!T` (or `Error!T`) is an error union: a value or an error. `try f()` passes the error to the
// caller; `f() catch …` handles it in place.
/// Open the connection `name` of `eve.cfg` (once per run) and give it its object.
pub fn connectEv(it: Host, name: []const u8, url_text: []const u8) Signal!Value {
    const b = state(it);
    if (b.ev_names.get(name)) |idx| {
        if (!b.evs.items[idx].closed) return makeObject(it, name, idx);
    }
    const io = it.io() orelse return it.fail("database.connect: no input/output handle", .{});
    const u = parseUrl(url_text) orelse return it.failWith(err_argument, "database.connect: '{s}' is not an evedb://host:port/database URL", .{url_text});
    const c = client.Conn.connect(io, std.heap.smp_allocator, u.host_port, u.token) catch |e| switch (e) {
        error.Server => return it.failWith(err_io, "DatabaseError: evedb at {s} refused the login", .{u.host_port}),
        else => return it.failWith(err_io, "DatabaseError: cannot connect to evedb at {s} ({s})", .{ u.host_port, @errorName(e) }),
    };
    _ = c.open(u.database) catch return it.failWith(err_io, "DatabaseError: evedb at {s}: {s}", .{ u.host_port, c.err_msg });
    const ev = try it.arena().create(Ev);
    ev.* = .{ .c = c };
    try b.evs.append(it.arena(), ev);
    const idx = b.evs.items.len - 1;
    try b.ev_names.put(it.arena(), try it.arena().dupe(u8, name), idx);
    return makeObject(it, name, idx);
}

// Zig tip: `makeObject` relies on the same Zig feature as `connectEv` above: see the tip there.
fn makeObject(it: Host, name: []const u8, idx: usize) Signal!Value {
    const b = state(it);
    if (b.ev_class == null) {
        const cls = try it.arena().create(Class);
        cls.* = .{ .name = "Connection" };
        b.ev_class = cls;
    }
    const obj = try it.newObject();
    try it.setField(obj, "name", try it.newStr(name));
    try it.setField(obj, "handle", .{ .int = @intCast(idx) });
    obj.class = b.ev_class;
    return .{ .object = obj };
}

// Zig tip: `a orelse b` unwraps an optional: the value when there is one, else `b` (which may be `return` or `continue`,
// leaving the function or the loop).
pub fn isEvObject(it: Host, v: Value) bool {
    const cls = state(it).ev_class orelse return false;
    return v == .object and v.object.class == cls;
}

// Zig tip: `evOf` relies on the same Zig feature as `parseUrl` above: see the tip there.
/// The connection behind an object (null when the value is no evedb connection).
pub fn evOf(it: Host, v: Value) ?*Ev {
    if (!isEvObject(it, v)) return null;
    const idx: usize = @intCast(value.intOf(value.fieldOf(v.object, "handle").?));
    return state(it).evs.items[idx];
}

var tx_counter = std.atomic.Value(u64).init(0);

// Zig tip: a transaction id must be unique, not secret: the clock, a counter and the address of the connection go through
// SHA-256, and the first 16 bytes are the id. `std.mem.asBytes` sees any value as its bytes.
fn newTxId(io: Io, ev: *Ev) [16]u8 {
    var h = std.crypto.hash.sha2.Sha256.init(.{});
    const ns = Io.Timestamp.now(io, .real).toNanoseconds();
    const n = tx_counter.fetchAdd(1, .monotonic);
    h.update(std.mem.asBytes(&ns));
    h.update(std.mem.asBytes(&n));
    h.update(std.mem.asBytes(&ev));
    var d: [32]u8 = undefined;
    h.final(&d);
    return d[0..16].*;
}

// Zig tip: `failServer` relies on the same Zig feature as `isEvUrl` above: see the tip there.
fn failServer(it: Host, ev: *Ev, what: []const u8) Signal {
    return it.failWith(err_io, "DatabaseError: {s} [{s} {s}]: {s}", .{ ev.c.err_msg, ev.c.err_class, ev.c.err_state, what });
}

// Zig tip: a job's first statement on the connection begins a transaction with an id of the client (`BEGIN`), and the end of
// the job commits or rolls it back by that id, as the other drivers do. The id lets a client ask `STATUS` after a broken commit.
fn enlist(it: Host, ev: *Ev) Signal!void {
    if (it.currentJob().len == 0 or ev.tx != null) return;
    const io = it.io() orelse return;
    const id = newTxId(io, ev);
    ev.c.begin(id, false) catch return failServer(it, ev, "begin");
    ev.tx = id;
}

// Zig tip: `finishTransactions` relies on the same Zig feature as `isEvObject` above: see the tip there.
/// At the end of a job: commit or roll back what the job began on evedb connections.
pub fn finishTransactions(it: Host, ok: bool) void {
    for (state(it).evs.items) |ev| {
        const id = ev.tx orelse continue;
        ev.tx = null;
        if (ev.closed) continue;
        if (ok) ev.c.commit(id) catch {} else ev.c.rollback(id) catch {};
    }
}

// Zig tip: `closeAll` relies on the same Zig feature as `isEvUrl` above: see the tip there.
pub fn closeAll(it: Host) void {
    for (state(it).evs.items) |ev| {
        if (ev.closed) continue;
        ev.closed = true;
        ev.c.deinit();
    }
}

// Zig tip: an Eve value becomes a typed value of the protocol, so the server binds it as a parameter of the prepared statement:
// no quoting, no SQL text is built. A `Decimal` travels as its exact text, an `Instant` as micro seconds.
fn toWire(it: Host, v: Value) Signal!ewp.Value {
    return switch (v) {
        .nil => .null,
        .bool => |x| .{ .boolean = x },
        .int, .nat, .byte, .short, .huge => |n| .{ .int = n },
        .real, .float => |x| .{ .real = x },
        .dec => .{ .decimal = try it.text(v) },
        .str => |s| .{ .string = s },
        .instant => |us| .{ .instant = us },
        else => it.failWith(err_argument, "a {s} can not be a SQL parameter", .{value.typeName(v)}),
    };
}

// Zig tip: `wireText` relies on the same Zig feature as `connectEv` above: see the tip there.
fn wireText(a: std.mem.Allocator, v: ewp.Value) ![]const u8 {
    return switch (v) {
        .null => "",
        .boolean => |b| if (b) "true" else "false",
        .int => |n| try std.fmt.allocPrint(a, "{d}", .{n}),
        .real => |x| try std.fmt.allocPrint(a, "{d}", .{x}),
        .string, .decimal, .huge, .bytes => |s| s,
        .instant => |n| try std.fmt.allocPrint(a, "{d}", .{n}),
        .date => |d| try std.fmt.allocPrint(a, "{d}", .{d}),
        .uuid => |u| try std.fmt.allocPrint(a, "{x}", .{u}),
    };
}

// Zig tip: a value of a row becomes the value of a member of the record class: the member's type decides, as in the SQLite
// driver. Numbers and booleans arrive typed and need no parsing; a decimal arrives as its text and is read by the same function
// the other drivers use for text columns. NULL goes only into an optional member.
fn rowValue(it: Host, v: ewp.Value, m: *const Node, class_name: []const u8) Signal!Value {
    if (v == .null) {
        if (conn.isOptional(m.ty)) return .nil;
        return it.failWith(err_null, "DatabaseError: column '{s}' is NULL but the member of {s} is not optional", .{ m.text, class_name });
    }
    const ty = conn.baseType(m.ty);
    const eql = std.mem.eql;
    if (eql(u8, ty, "Logic")) return switch (v) {
        .boolean => |b| .{ .bool = b },
        .int => |n| .{ .bool = n != 0 },
        else => it.failWith(err_convert, "DatabaseError: column '{s}' is not a Logic", .{m.text}),
    };
    if (eql(u8, ty, "Integer") or eql(u8, ty, "Natural") or eql(u8, ty, "Short") or eql(u8, ty, "Byte") or eql(u8, ty, "Huge")) {
        switch (v) {
            .int => |n| return .{ .int = n },
            .date => |d| return .{ .int = d },
            .instant => |n| return .{ .int = n },
            else => {},
        }
    }
    if (eql(u8, ty, "Real") or eql(u8, ty, "Float")) {
        switch (v) {
            .real => |x| return .{ .real = x },
            .int => |n| return .{ .real = @floatFromInt(n) },
            .decimal => |s| return .{ .real = std.fmt.parseFloat(f64, s) catch return it.failWith(err_convert, "DatabaseError: column '{s}': '{s}' is not a number", .{ m.text, s }) },
            else => {},
        }
    }
    if (eql(u8, ty, "Instant") and v == .instant) return .{ .instant = v.instant };
    if (eql(u8, ty, "Decimal") and v == .real) return .{ .dec = try it.decFromReal(v.real) };
    const text = wireText(it.temp(), v) catch return error.OutOfMemory;
    if (eql(u8, ty, "String")) return it.newStr(text);
    return it.fromSqlText(text, m);
}

// Zig tip: `splitStatements` relies on the same Zig feature as `connectEv` above: see the tip there.
fn splitStatements(a: std.mem.Allocator, text: []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var start: usize = 0;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        const ch = text[i];
        if (ch == '\'' or ch == '"') {
            i += 1;
            while (i < text.len and text[i] != ch) i += 1;
        } else if (ch == '-' and i + 1 < text.len and text[i + 1] == '-') {
            while (i < text.len and text[i] != '\n') i += 1;
        } else if (ch == ';') {
            try out.append(a, text[start..i]);
            start = i + 1;
        }
    }
    if (start < text.len) try out.append(a, text[start..]);
    return out.items;
}

// Zig tip: `call` relies on the same Zig feature as `connectEv` above: see the tip there.
/// A method of an evedb connection.
pub fn call(it: Host, obj: *Object, name: []const u8, args: []const *const Node) Signal!Value {
    const eql = std.mem.eql;
    const ev = evOf(it, .{ .object = obj }).?;
    if (eql(u8, name, "close")) {
        if (!ev.closed) {
            ev.closed = true;
            ev.c.deinit();
        }
        return .nil;
    }
    if (ev.closed) return it.fail("the connection is closed", .{});
    if (args.len == 0) return it.fail("{s} needs a SQL text or a path", .{name});
    const first = try it.text(try it.eval(args[0]));
    try enlist(it, ev);
    const a = it.temp();
    if (eql(u8, name, "script")) {
        const io = it.io() orelse return it.fail("script: no input/output handle", .{});
        const text = Io.Dir.cwd().readFileAlloc(io, first, a, .limited(16 << 20)) catch |e|
            return it.failWith(err_file, "cannot read {s}: {s}", .{ first, @errorName(e) });
        for (splitStatements(a, text) catch return error.OutOfMemory) |st| {
            const t = std.mem.trim(u8, st, " \t\r\n");
            if (t.len == 0) continue;
            _ = ev.c.execute(t, &.{}) catch return failServer(it, ev, first);
        }
        return .nil;
    }
    if (eql(u8, name, "import")) return it.fail("import works on SQLite connections; on evedb use Memory.load or COPY ... FROM", .{});
    var params: std.ArrayList(ewp.Value) = .empty;
    for (args[1..]) |p| try params.append(a, try toWire(it, try it.eval(p)));
    if (eql(u8, name, "execute!")) {
        const n = ev.c.execute(first, params.items) catch return failServer(it, ev, first);
        return .{ .int = n };
    }
    if (eql(u8, name, "query!") or eql(u8, name, "query_one!")) {
        const cls = try conn.recordClass(it, it.typeArgs(), name);
        const members = cls.node.?.kids[0].kids;
        const rows = ev.c.query(a, first, params.items, 0) catch return failServer(it, ev, first);
        const colmap = try a.alloc(usize, members.len);
        for (members, colmap) |m, *slot| {
            slot.* = for (rows.names, 0..) |cn, j| {
                if (eql(u8, cn, m.text)) break j;
            } else return it.failWith(err_convert, "DatabaseError: the query has no column '{s}' for {s}", .{ m.text, cls.name });
        }
        const out = try it.newList(&.{}, false);
        const nc = rows.names.len;
        for (0..rows.rowCount()) |r| {
            const rec = try it.newObject();
            for (members, colmap) |m, j| try it.setField(rec, m.text, try rowValue(it, rows.cells[r * nc + j], m, cls.name));
            rec.class = cls;
            try it.listAppend(out, .{ .object = rec });
        }
        if (eql(u8, name, "query!")) return .{ .list = out };
        const e = out.elems();
        return if (e.len == 0) .nil else e[0];
    }
    return it.fail("a Connection has no method '{s}'", .{name});
}

// ---------------------------------------------------------------------------------------------------------------- Memory tables

const little = builtin.cpu.arch.endian() == .little;

// Zig tip: a validity bitmap of the wire has its first bit at bit 0 of byte 0; the bitmap of a column of a `Memory` table is a
// list of 64-bit words that grows with the column. The bits are moved one by one because the two rarely line up (the column
// may already hold 13 rows); this is the only loop per row of the fast path for fixed-width columns.
fn appendValidity(gpa: std.mem.Allocator, col: *columnar.Column, view: batch.View, n: usize) !void {
    for (0..n) |r| {
        if (col.len % 64 == 0) try col.valid.append(gpa, 0);
        if (view.isValid(r)) col.valid.items[col.len / 64] |= @as(u64, 1) << @intCast(col.len % 64);
        col.len += 1;
    }
}

// Zig tip: `switch` must cover every value of what it tests (or have `else`); the compiler checks it, so a new case can not
// be forgotten. A prong can be an expression that gives the result.
fn wireOfKind(k: columnar.Kind) batch.Wire {
    return switch (k) {
        .integer => .int,
        .real => .real,
        .boolean => .boolean,
        .text => .text,
        .date => .date,
        .timestamp => .timestamp,
    };
}

// Zig tip: the fast case is a column whose wire type is already the type of the field: eight bytes per value on the wire and
// eight bytes per value in the column, so `@memcpy` moves the whole batch of the column at once (`sliceAsBytes` sees the new
// part of the array as bytes). Any other pair goes value by value with a conversion.
/// Append the values of one column of a batch to a column of a `Memory` table.
fn appendColumn(it: Host, gpa: std.mem.Allocator, col: *columnar.Column, wire: batch.Wire, view: batch.View, n: usize, optional: bool) Signal!void {
    if (!optional and view.valid != null) {
        for (0..n) |r| if (!view.isValid(r)) return it.failWith(err_null, "{s} is not optional: the query gave NULL", .{col.name});
    }
    switch (col.data) {
        .ints => |*arr| {
            const old = arr.items.len;
            try arr.resize(gpa, old + n);
            const dst = arr.items[old..];
            if ((wire == .int or wire == .date or wire == .timestamp) and little) {
                @memcpy(std.mem.sliceAsBytes(dst), view.fixed[0 .. n * 8]);
            } else for (dst, 0..) |*d, r| d.* = switch (wire) {
                .int, .date, .timestamp => view.int(r),
                .boolean => @intFromBool(view.boolean(r)),
                .real => @intFromFloat(view.real(r)),
                else => if (!view.isValid(r)) 0 else std.fmt.parseInt(i64, view.text(r), 10) catch return it.failWith(err_convert, "the field {s} can not take '{s}'", .{ col.name, view.text(r) }),
            };
        },
        .reals => |*arr| {
            const old = arr.items.len;
            try arr.resize(gpa, old + n);
            const dst = arr.items[old..];
            if (wire == .real and little) {
                @memcpy(std.mem.sliceAsBytes(dst), view.fixed[0 .. n * 8]);
            } else for (dst, 0..) |*d, r| d.* = switch (wire) {
                .real => view.real(r),
                .int, .date, .timestamp => @floatFromInt(view.int(r)),
                .boolean => if (view.boolean(r)) 1 else 0,
                else => if (!view.isValid(r)) 0 else std.fmt.parseFloat(f64, view.text(r)) catch return it.failWith(err_convert, "the field {s} can not take '{s}'", .{ col.name, view.text(r) }),
            };
        },
        .text => |*t| {
            for (0..n) |r| {
                if (view.isValid(r)) switch (wire) {
                    .text, .decimal, .blob => try t.bytes.appendSlice(gpa, view.text(r)),
                    .int, .date, .timestamp => try t.bytes.print(gpa, "{d}", .{view.int(r)}),
                    .real => try t.bytes.print(gpa, "{d}", .{view.real(r)}),
                    .boolean => try t.bytes.appendSlice(gpa, if (view.boolean(r)) "true" else "false"),
                };
                try t.offs.append(gpa, @intCast(t.bytes.items.len));
            }
        },
    }
    try appendValidity(gpa, col, view, n);
}

// Zig tip: `defer` runs its statement when the scope ends, by any path (a `return`, an error, the end of the block), so a
// free or a close is written once, next to what it undoes.
/// `Memory.store(wh, select, params…)` on an evedb connection: the result comes as column batches into the table.
pub fn store(it: Host, ev: *Ev, cls: *Class, t: *columnar.Table, sql: []const u8, args: []const *const Node) Signal!Value {
    try enlist(it, ev);
    const a = it.temp();
    var params: std.ArrayList(ewp.Value) = .empty;
    for (args) |p| try params.append(a, try toWire(it, try it.eval(p)));
    var b = ewp.Builder.init(a);
    try b.string(sql);
    try b.u32_(@intCast(params.items.len));
    for (params.items) |p| try b.value(p);
    try b.u32_(@intCast(batch.batch_rows));
    const stream = ev.c.send(.queryb, b.buf.items) catch return failServer(it, ev, sql);
    const members = cls.node.?.kids[0].kids;
    var heads: []batch.Head = &.{};
    var colmap: []usize = &.{};
    var total: i64 = 0;
    var failure: ?Signal = null;
    while (true) {
        const f = ev.c.receive(stream) catch |e| {
            if (e == error.Server) return failServer(it, ev, sql);
            return it.failWith(err_io, "DatabaseError: the connection to evedb broke ({s})", .{@errorName(e)});
        };
        defer ewp.freeFrame(ev.c.gpa, f);
        var cur: ewp.Cursor = .{ .buf = f.payload };
        switch (f.kind) {
            .schema => {
                const h = batch.readSchema(&cur, a) catch return it.fail("evedb sent a bad schema", .{});
                // the names point into the frame, which is freed: keep copies
                heads = try a.alloc(batch.Head, h.len);
                for (h, heads) |src, *dst| dst.* = .{ .name = try a.dupe(u8, src.name), .wire = src.wire };
                colmap = try a.alloc(usize, members.len);
                for (members, colmap) |m, *slot| {
                    var found: ?usize = null;
                    for (heads, 0..) |hd, j| {
                        if (std.mem.eql(u8, hd.name, m.text)) found = j;
                    }
                    slot.* = found orelse blk: {
                        failure = it.failWith(err_convert, "DatabaseError: the query has no column '{s}' for {s}", .{ m.text, cls.name });
                        break :blk 0;
                    };
                }
            },
            .batch => {
                if (failure != null) continue;
                var fa: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
                defer fa.deinit();
                const got = batch.readBatch(&cur, fa.allocator(), heads) catch return it.fail("evedb sent a bad batch", .{});
                for (members, colmap, 0..) |m, j, k| {
                    appendColumn(it, t.gpa, &t.cols.items[k], heads[j].wire, got.views[j], got.rows, conn.isOptional(m.ty)) catch |e| {
                        failure = e;
                        break;
                    };
                }
                if (failure != null) continue;
                t.rows += got.rows;
                total += @intCast(got.rows);
            },
            .end => break,
            else => return it.fail("evedb sent an unexpected frame in a result", .{}),
        }
    }
    if (failure) |e| return e;
    return .{ .int = total };
}

// Zig tip: a load is pipelined: the head, every batch and the end are written without waiting, and one answer is read at the
// end. Writing a whole column of a batch is one `appendSlice` of its bytes for the fixed-width types; the text column is its
// offsets (made relative to the first row of the batch) and its bytes.
/// `Memory.load(wh, name)` on an evedb connection: the columns go as batches to DuckDB's Appender, in a new table.
pub fn load(it: Host, ev: *Ev, t: *const columnar.Table, table: []const u8) Signal!Value {
    try enlist(it, ev);
    const a = it.temp();
    var b = ewp.Builder.init(a);
    try b.string(table);
    try b.u8_(1);
    const heads = try a.alloc(batch.Head, t.cols.items.len);
    for (t.cols.items, heads) |c, *h| h.* = .{ .name = c.name, .wire = wireOfKind(c.kind) };
    try batch.writeSchema(&b, heads);
    const stream = ev.c.send(.load, b.buf.items) catch return failServer(it, ev, table);
    var start: usize = 0;
    while (start < t.rows) {
        const n = @min(batch.batch_rows, t.rows - start);
        b.buf.clearRetainingCapacity();
        try b.u32_(@intCast(n));
        for (t.cols.items) |*c| {
            var all = true;
            for (start..start + n) |r| if (!c.isValid(r)) {
                all = false;
                break;
            };
            if (all) {
                try b.u8_(0);
            } else {
                try b.u8_(1);
                const bits_at = b.buf.items.len;
                try b.buf.appendNTimes(a, 0, batch.validityBytes(n));
                for (0..n) |r| if (c.isValid(start + r)) {
                    b.buf.items[bits_at + r / 8] |= @as(u8, 1) << @intCast(r % 8);
                };
            }
            switch (c.data) {
                .ints => |arr| {
                    if (c.kind == .boolean) {
                        for (arr.items[start .. start + n]) |v| try b.u8_(@intFromBool(v != 0));
                    } else if (little) {
                        try b.buf.appendSlice(a, std.mem.sliceAsBytes(arr.items[start .. start + n]));
                    } else for (arr.items[start .. start + n]) |v| try b.i64_(v);
                },
                .reals => |arr| {
                    if (little) {
                        try b.buf.appendSlice(a, std.mem.sliceAsBytes(arr.items[start .. start + n]));
                    } else for (arr.items[start .. start + n]) |v| try b.u64_(@bitCast(v));
                },
                .text => |tx| {
                    const base = tx.offs.items[start];
                    for (tx.offs.items[start .. start + n + 1]) |o| try b.u32_(o - base);
                    try b.buf.appendSlice(a, tx.bytes.items[base..tx.offs.items[start + n]]);
                },
            }
        }
        ev.c.sendOn(.batch, stream, b.buf.items) catch return failServer(it, ev, table);
        start += n;
    }
    ev.c.sendOn(.end, stream, "") catch return failServer(it, ev, table);
    const f = ev.c.receive(stream) catch |e| {
        if (e == error.Server) return failServer(it, ev, table);
        return it.failWith(err_io, "DatabaseError: the connection to evedb broke ({s})", .{@errorName(e)});
    };
    defer ewp.freeFrame(ev.c.gpa, f);
    var cur: ewp.Cursor = .{ .buf = f.payload };
    const rows = cur.i64_() catch return it.fail("evedb sent a bad answer to a load", .{});
    return .{ .int = rows };
}

// Zig tip: a `test` block is compiled only by `zig build test`; `try std.testing.expect…` fails the test, with the values,
// when a check is false.
test "an evedb URL" {
    const u = parseUrl("evedb://s3cret@127.0.0.1:8044/warehouse").?;
    try std.testing.expectEqualStrings("s3cret", u.token);
    try std.testing.expectEqualStrings("127.0.0.1:8044", u.host_port);
    try std.testing.expectEqualStrings("warehouse", u.database);
    try std.testing.expect(parseUrl("evedb://127.0.0.1:8044/") == null);
    try std.testing.expect(parseUrl("postgres://x") == null);
    try std.testing.expectEqualStrings("", parseUrl("evedb://localhost:8044/wh").?.token);
}
