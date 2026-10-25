//! SQLite connections: the methods of a `Connection`, the transaction of a job, the
//! statements, and the `sql function`s that SQLite calls (spec/library/database.md). Part of evedb;
//! it works on SQLite in this version. The interpreter is reached through `Host`.
const std = @import("std");
const Io = std.Io;
const evecm = @import("evecm");
const ast = evecm.ast;
const value = evecm.value;
const data = evecm.data;
const decimal = evecm.decimal;
const Host = @import("../host.zig").Host;
const Heap = evecm.heap.Heap;
const sqlite = @import("sqlite.zig");
const orm = @import("orm.zig");
const importer = @import("importer.zig");
const Driver = @import("driver.zig").Driver;
const state = @import("state.zig").state;

const Node = ast.Node;
const Value = value.Value;
const Class = value.Class;
const Object = value.Object;
const List = value.List;
const Signal = value.Signal;
const err_file = value.err_file;
const err_io = value.err_io;
const err_key = value.err_key;
const err_argument = value.err_argument;
const err_convert = value.err_convert;
const err_null = value.err_null;

/// The class named by the type argument of a library call (`(:Row)`): it must be a record class.
pub fn recordClass(it: Host, targs: []const *const Node, what: []const u8) Signal!*Class {
    if (targs.len != 1) return it.failWith(err_argument, "{s} needs the record class as a type argument: {s}(:Row)(...)", .{ what, what });
    const v = try it.lookup(targs[0].text);
    if (v != .class or v.class.node == null) return it.failWith(err_argument, "{s}: '{s}' is not a record class", .{ what, targs[0].text });
    return v.class;
}

const metalib = @import("../metalib.zig");

pub const isOptional = ast.isOptional;
pub const baseType = ast.baseType;

/// Open the SQLite file that `eve.cfg` declares for `name` (`database "cache" = "sqlite://db/cache.db"`), once.
/// Returns the place of the database in the list of the run. In production the schema version is checked.
pub fn openConnection(it: Host, name: []const u8) Signal!usize {
    const b = state(it);
    if (b.conn_names.get(name)) |idx| {
        if (b.dbs.items[idx].handle != null) return idx;
    }
    if (std.mem.eql(u8, name, "meta")) {
        // the meta database: the connection of the library, with every table copied in (D-222, D-225)
        const mdb = try it.arena().create(sqlite.Db);
        mdb.* = (try metalib.connection(it.it)).*;
        try b.dbs.append(it.arena(), mdb);
        try b.tx.append(it.arena(), false);
        const midx = b.dbs.items.len - 1;
        try b.conn_names.put(it.arena(), "meta", midx);
        return midx;
    }
    const io = it.io() orelse return it.fail("database.connect: no input/output handle", .{});
    const cfg = Io.Dir.cwd().readFileAlloc(io, "eve.cfg", it.temp(), .limited(1 << 20)) catch
        return it.failWith(err_file, "database.connect: eve.cfg not found in the project folder", .{});
    const url = data.connectionUrl(cfg, name) orelse
        return it.failWith(err_key, "database.connect: no connection '{s}' in eve.cfg", .{name});
    const path = data.sqlitePath(url) orelse
        return it.failWith(err_argument, "database.connect: '{s}' is not a sqlite:// connection; no other driver yet", .{url});
    if (std.fs.path.dirname(path)) |dir| Io.Dir.cwd().createDirPath(io, dir) catch {};
    const db = try it.arena().create(sqlite.Db);
    db.* = sqlite.Db.open(try it.temp().dupeSentinel(u8, path, 0)) catch
        return it.failWith(err_io, "DatabaseError: cannot open {s}", .{path});
    _ = db.exec("pragma foreign_keys = on") catch {};
    try checkMapping(it, name, db);
    for (b.sql_funcs.items) |sf| try addSqlFunction(it, db, sf);
    try b.dbs.append(it.arena(), db);
    try b.tx.append(it.arena(), false);
    const idx = b.dbs.items.len - 1;
    try b.conn_names.put(it.arena(), try it.arena().dupe(u8, name), idx);
    return idx;
}

fn checkMapping(it: Host, name: []const u8, db: *sqlite.Db) Signal!void {
    const io = it.io() orelse return;
    const text = Io.Dir.cwd().readFileAlloc(io, "db/mappings.json", it.temp(), .limited(1 << 20)) catch return;
    var diag: data.JsonDiag = .{};
    const docs = data.parseJsonDocuments(it.temp(), text, &diag) catch return;
    if (docs.len == 0 or docs[0] != .object) return;
    var declared: ?i64 = null;
    for (docs[0].object) |top| {
        if (!std.mem.eql(u8, top.key, "connections") or top.value != .object) continue;
        for (top.value.object) |conn| {
            if (!std.mem.eql(u8, conn.key, name) or conn.value != .object) continue;
            for (conn.value.object) |field| {
                if (std.mem.eql(u8, field.key, "schema_version") and field.value == .number) declared = std.fmt.parseInt(i64, field.value.number, 10) catch null;
            }
        }
    }
    const want = declared orelse return;
    var st = db.prepare("pragma user_version") catch return;
    defer st.finalize();
    const row = st.step() catch return;
    const actual: i64 = if (row) st.columnInt(0) else 0;
    if (actual != want) {
        return it.failWith(54, "Mapping of the connection {s} does not match the database: schema version {d}, mapping validated for {d}: validate the mapping again (eve -d, or db validate {s}) and commit db/mappings.json", .{ name, actual, want, name });
    }
}

/// The SQLite driver of the table (`driver.zig`): the core database and the `sqlite://` files of a script.
pub const driver: Driver = .{
    .scheme = "sqlite",
    .is_url = isSqliteUrl,
    .connect = sqliteConnect,
    .is_object = isSqliteObject,
    .call = connectionCall,
    .finish_transactions = finishTransactions,
    .close_all = closeDatabases,
};

fn isSqliteUrl(url: []const u8) bool {
    return data.sqlitePath(url) != null;
}

fn isSqliteObject(it: Host, v: Value) bool {
    return v == .object and v.object.class != null and v.object.class == state(it).conn_class;
}

/// `database.connect(name)` for a `sqlite://` URL: the `Connection` of the name (the database is opened once per run).
fn sqliteConnect(it: Host, name: []const u8, url: []const u8) Signal!Value {
    _ = url;
    const idx = try openConnection(it, name);
    const b = state(it);
    if (b.conn_class == null) {
        const cls = try it.arena().create(Class);
        cls.* = .{ .name = "Connection" };
        b.conn_class = cls;
    }
    const obj = try it.newObject();
    try it.setField(obj, "name", try it.newStr(name));
    try it.setField(obj, "handle", .{ .int = @intCast(idx) });
    obj.class = b.conn_class;
    return .{ .object = obj };
}

/// The first statement of a job that uses a connection begins a transaction on it (database.md#transactions).
/// Outside a job each statement commits at once.
pub fn enlist(it: Host, idx: usize, db: *sqlite.Db) Signal!void {
    const b = state(it);
    if (it.currentJob().len == 0 or b.tx.items[idx]) return;
    db.exec("begin") catch return it.failWith(err_io, "DatabaseError: begin: {s}", .{db.errorMessage()});
    b.tx.items[idx] = true;
}

/// At `done`: commit every transaction the job began on SQLite, or roll it back when the job failed.
pub fn finishTransactions(it: Host, ok: bool) void {
    const b = state(it);
    for (b.dbs.items, 0..) |db, i| {
        if (!b.tx.items[i]) continue;
        b.tx.items[i] = false;
        db.exec(if (ok) "commit" else "rollback") catch {};
    }
}

/// At the end of the run: close the SQLite databases that the script left open.
pub fn closeDatabases(it: Host) void {
    for (state(it).dbs.items) |db| db.close();
}

/// Bind the arguments of a statement to its `?` placeholders (the first is 1).
pub fn bindAll(it: Host, db: *sqlite.Db, st: *sqlite.Stmt, params: []const Value) Signal!void {
    for (params, 1..) |p, i| {
        const k: u16 = @intCast(i);
        const r = switch (p) {
            .nil => st.bindNull(k),
            .bool => |x| st.bindInt(k, @intFromBool(x)),
            .int, .nat, .byte, .short, .huge => |n| st.bindInt(k, n),
            .real, .float => |x| st.bindReal(k, x),
            .dec, .instant, .date, .time, .dur, .zone, .dtm => st.bindText(k, try it.text(p)),
            .str => |s| st.bindText(k, s),
            else => return it.fail("SQL parameter {d}: a {s} can not be bound", .{ i, value.typeName(p) }),
        };
        r catch return it.failWith(err_io, "DatabaseError: bind: {s}", .{db.errorMessage()});
    }
}

/// The value of column `col` of the current row of `st`, for the member `m` of the class `class_name`.
pub fn columnValue(it: Host, st: *sqlite.Stmt, col: u16, m: *const Node, class_name: []const u8) Signal!Value {
    return switch (st.columnKind(col)) {
        .null => if (isOptional(m.ty)) .nil else return it.failWith(err_null, "DatabaseError: column '{s}' is NULL but the member of {s} is not optional", .{ m.text, class_name }),
        .integer => if (std.mem.eql(u8, baseType(m.ty), "Logic")) .{ .bool = st.columnInt(col) != 0 } else if (std.mem.eql(u8, baseType(m.ty), "Decimal")) .{ .dec = decimal.fromInt(st.columnInt(col)) orelse return it.overflow() } else .{ .int = st.columnInt(col) },
        .real => if (std.mem.eql(u8, baseType(m.ty), "Decimal")) .{ .dec = try it.decFromReal(st.columnReal(col)) } else .{ .real = st.columnReal(col) },
        .text => try it.fromSqlText(st.columnText(col), m),
        .blob => return it.fail("a BLOB column can not be read yet", .{}),
    };
}

/// Run one statement with its parameters. A statement with columns is read into records of `cls`;
/// without `cls` it must have none. Gives the rows, and the number of rows changed through `changed`.
pub fn runStatement(it: Host, db: *sqlite.Db, sql: []const u8, params: []const Value, cls: ?*Class, changed: *i64) Signal!*List {
    var st = db.prepare(try it.temp().dupeSentinel(u8, sql, 0)) catch
        return it.failWith(err_io, "DatabaseError: {s}: {s}", .{ db.errorMessage(), sql });
    defer st.finalize();
    try bindAll(it, db, &st, params);
    const out = try it.newList(&.{}, false);
    var colmap: []usize = &.{};
    var members: []const *const Node = &.{};
    if (cls) |c| {
        members = c.node.?.kids[0].kids;
        colmap = try it.temp().alloc(usize, members.len);
        for (members, 0..) |m, k| {
            colmap[k] = for (0..st.columnCount()) |j| {
                if (std.mem.eql(u8, st.columnName(@intCast(j)), m.text)) break j;
            } else return it.failWith(err_convert, "DatabaseError: the query has no column '{s}' for {s}", .{ m.text, c.name });
        }
    }
    // a `sql function` called by this statement runs in this interpreter (D-166)
    const b = state(it);
    const saved_caller = b.sql_caller;
    b.sql_caller = it;
    defer b.sql_caller = saved_caller;
    b.sql_fail = null;
    b.sql_signal = null;
    while (st.step() catch return stepFailed(it, db, sql)) {
        const c = cls orelse return it.fail("a statement that returns rows needs a record class: query!(:Row)(...)", .{});
        const obj = try it.newObject();
        for (members, colmap) |m, j| {
            const col: u16 = @intCast(j);
            const v = try columnValue(it, &st, col, m, c.name);
            try it.setField(obj, m.text, v);
        }
        obj.class = c;
        try it.listAppend(out, .{ .object = obj });
    }
    changed.* = db.changes();
    return out;
}

/// A statement stopped: by a `sql function` (the signal it ended with, or `$err_sql`), or by the database.
fn stepFailed(it: Host, db: *sqlite.Db, sql: []const u8) Signal {
    const b = state(it);
    if (b.sql_signal) |e| {
        b.sql_signal = null;
        return e;
    }
    if (b.sql_fail) |msg| {
        b.sql_fail = null;
        return it.failWith(value.err_sql, "{s}", .{msg});
    }
    return it.failWith(err_io, "DatabaseError: {s}: {s}", .{ db.errorMessage(), sql });
}

// ---- sql function: Eve functions that SQL calls (database.md#sql-functions, D-166) -----------------------

/// A `sql function` of the program: the function value, the interpreter that declared it and its name in SQL.
pub const SqlFn = struct {
    it: Host,
    func: *value.Func,
    name: [:0]const u8,
};

/// Keep a `sql function` and register it on every open connection; `openConnection` registers it on the next ones.
pub fn registerSqlFunction(it: Host, f: *value.Func) Signal!void {
    const b = state(it);
    const sf = try it.arena().create(SqlFn);
    sf.* = .{ .it = it, .func = f, .name = try it.arena().dupeSentinel(u8, f.node.text, 0) };
    Heap.retain(.{ .func = f });
    try b.sql_funcs.append(it.arena(), sf);
    for (b.dbs.items) |db| if (db.handle != null) try addSqlFunction(it, db, sf);
}

/// Register one `sql function` on one connection.
fn addSqlFunction(it: Host, db: *sqlite.Db, sf: *SqlFn) Signal!void {
    const n: u8 = @intCast(sf.func.node.kids[0].kids.len);
    db.createFunction(sf.name, n, sf, sqlCallback) catch
        return it.failWith(err_io, "DatabaseError: cannot add the sql function {s}: {s}", .{ sf.name, db.errorMessage() });
}

/// SQLite calls this for each call of a `sql function` in a statement.
fn sqlCallback(ctx: ?*sqlite.CallHandle, argc: c_int, argv: [*c]?*sqlite.ArgHandle) callconv(.c) void {
    const call = sqlite.Call{ .handle = ctx };
    const sf: *SqlFn = @ptrCast(@alignCast(call.userData().?));
    const b = state(sf.it);
    const it = b.sql_caller orelse sf.it;
    sqlRun(it, sf, call, argv[0..@intCast(argc)]) catch |e| {
        if (e == error.Raise) {
            // an error raised by the function: keep its message for `$err_sql`; the error itself is handled
            if (b.sql_fail == null) if (it.lastReport()) |r| {
                r.handled = true;
                b.sql_fail = std.fmt.allocPrint(it.arena(), "SQL function {s} failed: {s}", .{ sf.name, r.message }) catch null;
            };
        } else b.sql_signal = e;
        call.resultError(b.sql_fail orelse "the sql function stopped");
    };
}

/// Convert the arguments by the types of the parameters, run the function, and give its result to SQL.
fn sqlRun(it: Host, sf: *SqlFn, call: sqlite.Call, argv: []const ?*sqlite.ArgHandle) Signal!void {
    const eql = std.mem.eql;
    const b = state(it);
    const prms = sf.func.node.kids[0].kids;
    const args = try it.temp().alloc(value.Arg, prms.len);
    for (prms, argv, 0..) |q, raw, i| {
        const a = sqlite.Arg{ .handle = raw };
        const ty = baseType(q.ty);
        const is_int = eql(u8, ty, "Integer") or eql(u8, ty, "Natural");
        const is_real = eql(u8, ty, "Real") or eql(u8, ty, "Float");
        const v: Value = switch (a.kind()) {
            .null => if (isOptional(q.ty)) .nil else {
                b.sql_fail = try std.fmt.allocPrint(it.arena(), "SQL function {s} failed: NULL for the parameter {s}: {s}; declare it {s}?", .{ sf.name, q.text, ty, ty });
                return error.Raise;
            },
            .integer => if (eql(u8, ty, "Logic"))
                .{ .bool = a.int() != 0 }
            else if (eql(u8, ty, "Decimal"))
                .{ .dec = decimal.fromInt(a.int()) orelse return it.overflow() }
            else if (eql(u8, ty, "Real"))
                .{ .real = @floatFromInt(a.int()) }
            else if (eql(u8, ty, "Float"))
                .{ .float = @floatFromInt(a.int()) }
            else if (is_int)
                .{ .int = a.int() }
            else
                return sqlMismatch(it, sf, q, "an INTEGER"),
            .real => if (eql(u8, ty, "Decimal"))
                .{ .dec = try it.decFromReal(a.real()) }
            else if (eql(u8, ty, "Float"))
                .{ .float = a.real() }
            else if (is_real)
                .{ .real = a.real() }
            else
                return sqlMismatch(it, sf, q, "a REAL"),
            .text => if (is_int or is_real or eql(u8, ty, "Logic")) return sqlMismatch(it, sf, q, "a TEXT") else try it.fromSqlText(a.text(), q),
            .blob => return sqlMismatch(it, sf, q, "a BLOB"),
        };
        args[i] = .{ .value = v };
    }
    const res = try it.invokeWith(sf.func, null, args);
    switch (res) {
        .nil => call.resultNull(),
        .bool => |x| call.resultInt(@intFromBool(x)),
        .int, .nat, .byte, .short, .huge => |n| call.resultInt(n),
        .real, .float => |x| call.resultReal(x),
        .dec, .instant => call.resultText(try it.text(res)),
        .str => |s| call.resultText(s),
        else => {
            b.sql_fail = try std.fmt.allocPrint(it.arena(), "SQL function {s} failed: its result is a {s}, which SQL does not have", .{ sf.name, value.typeName(res) });
            return error.Raise;
        },
    }
}

/// A SQL value that does not fit the type of a parameter: the call fails with `$err_sql`.
fn sqlMismatch(it: Host, sf: *SqlFn, q: *const Node, kind: []const u8) Signal {
    const ty = if (q.ty) |t| t.text else "String";
    state(it).sql_fail = std.fmt.allocPrint(it.arena(), "SQL function {s} failed: {s} for the parameter {s}: {s}", .{ sf.name, kind, q.text, ty }) catch return error.OutOfMemory;
    return error.Raise;
}

/// The methods of a `Connection`: `script`, `execute!`, `query!`, `query_one!` and `close`.
pub fn connectionCall(it: Host, conn: *Object, name: []const u8, args: []const *const Node) Signal!Value {
    const eql = std.mem.eql;
    const targs = it.typeArgs();
    const idx: usize = @intCast(value.intOf(value.fieldOf(conn, "handle").?));
    const b = state(it);
    const db = b.dbs.items[idx];
    if (eql(u8, name, "close")) {
        db.close();
        return .nil;
    }
    if (db.handle == null) return it.fail("the connection is closed", .{});
    if (args.len == 0) return it.fail("{s} needs a SQL text or a path", .{name});
    const first = try it.text(try it.eval(args[0]));
    try enlist(it, idx, db);
    // a direct write on a table with pending tracked changes flushes them first (database.md, direct SQL)
    if (eql(u8, name, "script") or eql(u8, name, "execute!")) try orm.flushConn(it, idx);
    if (eql(u8, name, "script")) {
        const io = it.io() orelse return it.fail("script: no input/output handle", .{});
        const sql = Io.Dir.cwd().readFileAlloc(io, first, it.temp(), .limited(16 << 20)) catch |e|
            return it.failWith(err_file, "cannot read {s}: {s}", .{ first, @errorName(e) });
        db.exec(try it.temp().dupeSentinel(u8, sql, 0)) catch return it.failWith(err_io, "DatabaseError: {s}: {s}", .{ db.errorMessage(), first });
        return .nil;
    }
    // @decision D-184
    if (eql(u8, name, "import")) {
        if (args.len != 2) return it.fail("import needs a file path and a table name", .{});
        const table = try it.text(try it.eval(args[1]));
        try orm.flushConn(it, idx);
        const io = it.io() orelse return it.fail("import: no input/output handle", .{});
        const format = importer.formatOf(first) orelse
            return it.failWith(err_file, "cannot import {s}: the formats are .csv .txt .tsv .json .dbf (save a spreadsheet as CSV)", .{first});
        const bytes = Io.Dir.cwd().readFileAlloc(io, first, it.temp(), .limited(1 << 30)) catch |e|
            return it.failWith(err_file, "cannot read {s}: {s}", .{ first, @errorName(e) });
        const res = importer.importInto(it.temp(), db, bytes, format, table) catch |e| switch (e) {
            error.Exec => return it.failWith(err_io, "DatabaseError: {s}", .{db.errorMessage()}),
            else => return it.failWith(err_file, "cannot import {s}: {s}", .{ first, @errorName(e) }),
        };
        return .{ .int = @intCast(res.rows) };
    }
    var params: std.ArrayList(Value) = .empty;
    for (args[1..]) |a| try params.append(it.temp(), try it.eval(a));
    var changed: i64 = 0;
    if (eql(u8, name, "execute!")) {
        _ = try runStatement(it, db, first, params.items, null, &changed);
        return .{ .int = changed };
    }
    if (eql(u8, name, "query!") or eql(u8, name, "query_one!")) {
        const cls = try recordClass(it, targs, name);
        const rows = try runStatement(it, db, first, params.items, cls, &changed);
        if (eql(u8, name, "query!")) return .{ .list = rows };
        const e = rows.elems();
        return if (e.len == 0) .nil else e[0];
    }
    return it.fail("a Connection has no method '{s}'", .{name});
}
