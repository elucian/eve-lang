//! The Eve driver for PostgreSQL (README.md section 5B): `database "shop" = "postgres://user:password@host:5432/db"` in `eve.cfg`,
//! `database.connect("shop")` in a script. The connection speaks the PostgreSQL protocol to evedb or to any PostgreSQL server.
//!
//! Version 0.1 covers what a script does with a remote database through a connection: `execute!`, `query!`, `query_one!`,
//! `script`, `close`, and the transaction of a job (`BEGIN` at the first statement, `COMMIT` or `ROLLBACK` at the end). The
//! mapped tables (`table` declarations, tracked records) work on SQLite connections only; on this one they are an error with
//! that message. The parameters (`?`) are written into the SQL text as literals, with the quotes doubled, as a driver that uses
//! the simple query protocol does.
const std = @import("std");
const Io = std.Io;
const evecm = @import("evecm");
const ast = evecm.ast;
const value = evecm.value;
const Host = @import("../host.zig").Host;
const Driver = @import("driver.zig").Driver;
const Node = ast.Node;
const Value = value.Value;
const Object = value.Object;
const Class = value.Class;
const Signal = value.Signal;
const pgclient = @import("pgclient.zig");
const conn = @import("conn.zig");
const state = @import("state.zig").state;

const err_argument = value.err_argument;
const err_file = value.err_file;
const err_io = value.err_io;
const err_null = value.err_null;
const err_convert = value.err_convert;

/// Is the URL one of PostgreSQL?
pub fn isPgUrl(url: []const u8) bool {
    return std.mem.startsWith(u8, url, "postgres://") or std.mem.startsWith(u8, url, "postgresql://");
}

/// Open the connection `name` of `eve.cfg` (once per run) and give it its object.
pub fn connectPg(it: Host, name: []const u8, url_text: []const u8) Signal!Value {
    const b = state(it);
    if (b.pg_names.get(name)) |idx| {
        if (!b.pgs.items[idx].closed) return makeObject(it, name, idx);
    }
    const io = it.io() orelse return it.fail("database.connect: no input/output handle", .{});
    const url = pgclient.parseUrl(it.temp(), url_text) orelse return it.failWith(err_argument, "database.connect: '{s}' is not a postgres:// URL", .{url_text});
    const c = pgclient.Client.connect(io, std.heap.smp_allocator, url) catch |e| switch (e) {
        error.Auth => return it.failWith(err_io, "DatabaseError: login to {s}:{d} failed: {s}", .{ url.host, url.port, "wrong user or password" }),
        error.Unsupported => return it.failWith(err_io, "DatabaseError: {s}:{d} asks for a login this driver does not know", .{ url.host, url.port }),
        else => return it.failWith(err_io, "DatabaseError: cannot connect to {s}:{d} ({s})", .{ url.host, url.port, @errorName(e) }),
    };
    try b.pgs.append(it.arena(), c);
    const idx = b.pgs.items.len - 1;
    try b.pg_names.put(it.arena(), try it.arena().dupe(u8, name), idx);
    return makeObject(it, name, idx);
}

fn makeObject(it: Host, name: []const u8, idx: usize) Signal!Value {
    const b = state(it);
    if (b.pg_class == null) {
        const cls = try it.arena().create(Class);
        cls.* = .{ .name = "Connection" };
        b.pg_class = cls;
    }
    const obj = try it.newObject();
    try it.setField(obj, "name", try it.newStr(name));
    try it.setField(obj, "handle", .{ .int = @intCast(idx) });
    obj.class = b.pg_class;
    return .{ .object = obj };
}

pub fn isPgObject(it: Host, v: Value) bool {
    const cls = state(it).pg_class orelse return false;
    return v == .object and v.object.class == cls;
}

/// At the end of a job: commit or roll back the transactions that the job began on PostgreSQL connections.
pub fn finishTransactions(it: Host, ok: bool) void {
    for (state(it).pgs.items) |c| {
        if (!c.job_tx or c.closed) continue;
        c.job_tx = false;
        var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
        defer arena.deinit();
        _ = c.query(arena.allocator(), if (ok) "commit" else "rollback") catch {};
    }
}

pub fn closeAll(it: Host) void {
    for (state(it).pgs.items) |c| {
        if (!c.closed) c.close();
    }
}

/// The SQL with its `?` replaced by the literals of the parameters.
pub fn interpolate(it: Host, a: std.mem.Allocator, sql: []const u8, params: []const Value, scs: bool) Signal![]u8 {
    var out: std.ArrayList(u8) = .empty;
    var k: usize = 0;
    var i: usize = 0;
    while (i < sql.len) : (i += 1) {
        const ch = sql[i];
        if (ch == '\'' or ch == '"') {
            try out.append(a, ch);
            i += 1;
            while (i < sql.len) : (i += 1) {
                try out.append(a, sql[i]);
                if (sql[i] == ch) {
                    if (i + 1 < sql.len and sql[i + 1] == ch) {
                        i += 1;
                        try out.append(a, sql[i]);
                        continue;
                    }
                    break;
                }
            }
        } else if (ch == '-' and i + 1 < sql.len and sql[i + 1] == '-') {
            while (i < sql.len and sql[i] != '\n') : (i += 1) try out.append(a, sql[i]);
            if (i < sql.len) try out.append(a, '\n');
        } else if (ch == '?') {
            if (k >= params.len) return it.failWith(err_argument, "the SQL has more ? than parameters ({d})", .{params.len});
            try literal(it, a, &out, params[k], scs);
            k += 1;
        } else try out.append(a, ch);
    }
    if (k != params.len) return it.failWith(err_argument, "the SQL has {d} ? and {d} parameters were given", .{ k, params.len });
    return out.items;
}

fn quoted(a: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8, scs: bool) !void {
    if (!scs) try out.append(a, 'E');
    try out.append(a, '\'');
    for (s) |ch| {
        if (ch == '\'') try out.append(a, '\'');
        if (ch == '\\' and !scs) try out.append(a, '\\');
        try out.append(a, ch);
    }
    try out.append(a, '\'');
}

fn literal(it: Host, a: std.mem.Allocator, out: *std.ArrayList(u8), v: Value, scs: bool) Signal!void {
    switch (v) {
        .nil => try out.appendSlice(a, "NULL"),
        .bool => |x| try out.appendSlice(a, if (x) "TRUE" else "FALSE"),
        .int, .nat, .byte, .short, .huge => |n| try out.print(a, "{d}", .{n}),
        .real, .float => |x| {
            if (std.math.isNan(x) or std.math.isInf(x)) {
                try quoted(a, out, if (std.math.isNan(x)) "NaN" else if (x > 0) "Infinity" else "-Infinity", scs);
            } else try out.print(a, "{d}", .{x});
        },
        .dec => try out.appendSlice(a, try it.text(v)),
        .str => |s| try quoted(a, out, s, scs),
        .instant => try quoted(a, out, try it.text(v), scs),
        else => return it.failWith(err_argument, "a {s} can not be a SQL parameter", .{value.typeName(v)}),
    }
}

fn rowValue(it: Host, cell: ?[]const u8, m: *const Node, class_name: []const u8) Signal!Value {
    const text = cell orelse {
        if (conn.isOptional(m.ty)) return .nil;
        return it.failWith(err_null, "DatabaseError: column '{s}' is NULL but the member of {s} is not optional", .{ m.text, class_name });
    };
    const ty = conn.baseType(m.ty);
    const eql = std.mem.eql;
    if (eql(u8, ty, "Logic")) return .{ .bool = text.len > 0 and (text[0] == 't' or text[0] == 'T' or text[0] == '1') };
    if (eql(u8, ty, "Integer") or eql(u8, ty, "Natural") or eql(u8, ty, "Short") or eql(u8, ty, "Byte") or eql(u8, ty, "Huge")) {
        const n = std.fmt.parseInt(i64, std.mem.trim(u8, text, " "), 10) catch return it.failWith(err_convert, "DatabaseError: column '{s}': '{s}' is not a whole number", .{ m.text, text });
        return .{ .int = n };
    }
    if (eql(u8, ty, "Real") or eql(u8, ty, "Float")) {
        const x = std.fmt.parseFloat(f64, std.mem.trim(u8, text, " ")) catch return it.failWith(err_convert, "DatabaseError: column '{s}': '{s}' is not a number", .{ m.text, text });
        return .{ .real = x };
    }
    if (eql(u8, ty, "String")) return it.newStr(text);
    return it.fromSqlText(text, m);
}

fn failServer(it: Host, c: *pgclient.Client, sql: []const u8) Signal {
    return it.failWith(err_io, "DatabaseError: {s} [{s}]: {s}", .{ c.errorMessage(), c.errorCode(), sql });
}

fn enlist(it: Host, c: *pgclient.Client) Signal!void {
    if (it.currentJob().len == 0 or c.job_tx) return;
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    _ = c.query(arena.allocator(), "begin") catch return failServer(it, c, "begin");
    c.job_tx = true;
}

/// A method of a PostgreSQL connection.
pub fn call(it: Host, obj: *Object, name: []const u8, args: []const *const Node) Signal!Value {
    const eql = std.mem.eql;
    const b = state(it);
    const idx: usize = @intCast(value.intOf(value.fieldOf(obj, "handle").?));
    const c = b.pgs.items[idx];
    if (eql(u8, name, "close")) {
        if (!c.closed) c.close();
        return .nil;
    }
    if (c.closed) return it.fail("the connection is closed", .{});
    if (args.len == 0) return it.fail("{s} needs a SQL text or a path", .{name});
    const first = try it.text(try it.eval(args[0]));
    try enlist(it, c);
    const a = it.temp();
    if (eql(u8, name, "script")) {
        const io = it.io() orelse return it.fail("script: no input/output handle", .{});
        const sql = Io.Dir.cwd().readFileAlloc(io, first, a, .limited(16 << 20)) catch |e|
            return it.failWith(err_file, "cannot read {s}: {s}", .{ first, @errorName(e) });
        _ = c.query(a, sql) catch |e| return if (e == error.Server) failServer(it, c, first) else it.failWith(err_io, "DatabaseError: {s}", .{@errorName(e)});
        return .nil;
    }
    if (eql(u8, name, "import")) return it.fail("import works on SQLite connections; load the file into SQLite or use COPY on the server", .{});
    var params: std.ArrayList(Value) = .empty;
    for (args[1..]) |p| try params.append(a, try it.eval(p));
    const sql = try interpolate(it, a, first, params.items, c.scs);
    if (eql(u8, name, "execute!")) {
        const res = c.query(a, sql) catch |e| return if (e == error.Server) failServer(it, c, first) else it.failWith(err_io, "DatabaseError: {s}", .{@errorName(e)});
        return .{ .int = @intCast(res.affected) };
    }
    if (eql(u8, name, "query!") or eql(u8, name, "query_one!")) {
        const cls = try conn.recordClass(it, it.typeArgs(), name);
        const members = cls.node.?.kids[0].kids;
        const res = c.query(a, sql) catch |e| return if (e == error.Server) failServer(it, c, first) else it.failWith(err_io, "DatabaseError: {s}", .{@errorName(e)});
        const colmap = try a.alloc(usize, members.len);
        for (members, colmap) |m, *slot| {
            slot.* = for (res.cols, 0..) |col, j| {
                if (eql(u8, col.name, m.text)) break j;
            } else return it.failWith(err_convert, "DatabaseError: the query has no column '{s}' for {s}", .{ m.text, cls.name });
        }
        const out = try it.newList(&.{}, false);
        for (res.rows) |row| {
            const obj_row = try it.newObject();
            for (members, colmap) |m, j| try it.setField(obj_row, m.text, try rowValue(it, row[j], m, cls.name));
            obj_row.class = cls;
            try it.listAppend(out, .{ .object = obj_row });
        }
        if (eql(u8, name, "query!")) return .{ .list = out };
        const e = out.elems();
        return if (e.len == 0) .nil else e[0];
    }
    return it.fail("a Connection has no method '{s}'", .{name});
}

/// The driver of the table (`driver.zig`) for `postgres://` URLs.
pub const driver: Driver = .{
    .scheme = "postgres",
    .is_url = isPgUrl,
    .connect = connectPg,
    .is_object = isPgObject,
    .call = call,
    .finish_transactions = finishTransactions,
    .close_all = closeAll,
};
