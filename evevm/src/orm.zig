//! The database layer of the language (spec/library/database.md): `table` declarations, records that a session
//! tracks (dirty fields, optimistic locking), the methods of a table, the transaction of a job, `commit;` and
//! `rollback;`, and the checkpoints of the core database. Everything works on SQLite in this version.
//! The functions take the interpreter, like those of dlib.zig; `interp.zig` calls the few entry points.
const std = @import("std");
const Io = std.Io;
const ast = @import("ast.zig");
const interp = @import("interp.zig");
const dlib = @import("dlib.zig");
const data = @import("data.zig");
const sqlite = @import("sqlite.zig");
const decimal = @import("decimal.zig");
const instant = @import("instant.zig");

const Node = ast.Node;
const Interp = interp.Interp;
const Value = interp.Value;
const Class = interp.Class;
const Object = interp.Object;
const Signal = interp.Signal;
const Heap = @import("heap.zig").Heap;

/// The error code of a `ConflictError`: someone else changed the row (errors.md).
pub const err_conflict = 53;
/// The error code of a `MappingError`: the code and the database disagree (errors.md).
pub const err_mapping = 54;
const err_argument = interp.err_argument;
const err_io = interp.err_io;

// Zig tip: the states of a record are an `enum`; `@tagName(status)` gives the name for `status(r)`. The names are
// those of the specification (database.md, states of a record).
/// The state of a record in the session of its table.
pub const Status = enum { detached, added, clean, dirty, removed, stale };

/// What the compiler knows about a `table` declaration, turned into a plan: for each field of the class its
/// column, and which fields are the key, generated, or the version.
pub const Table = struct {
    name: []const u8,
    node: *const Node,
    cls: *Class,
    conn_name: []const u8,
    /// The name in the database, possibly `schema.table`.
    db_name: []const u8,
    members: []const *const Node,
    columns: []const []const u8,
    keys: []const usize,
    generated: []const usize,
    version: ?usize,
    read_only: bool,
    temporary: bool,
    /// How far the table is from the tables it does not reference: inserts go in this order, deletes in the reverse.
    depth: usize,
    created: bool = false,
    /// The records of the session by the text of their key (the identity map).
    identity: std.StringHashMapUnmanaged(*Track) = .empty,
};

/// One record known to a session.
pub const Track = struct {
    table: *Table,
    obj: *Object,
    status: Status,
    /// The value each changed field had when the record was read or last written (null for a field not changed).
    orig: []?Value,
    conn: usize,
    in_pending: bool = false,
};

fn tableOf(it: *Interp, o: *Object) *Table {
    return it.base().tables.items[@intCast(Interp.intOf(Interp.fieldOf(o, "handle").?))];
}

/// Is the value the object of a `table`?
pub fn isTable(it: *Interp, v: Value) bool {
    return v == .object and v.object.class != null and v.object.class == it.base().table_class;
}

// ---- declaring ------------------------------------------------------------------------------

fn findClause(n: *const Node, word: []const u8) ?*const Node {
    for (n.kids[3..]) |cl| if (std.mem.eql(u8, cl.text, word)) return cl;
    return null;
}

fn memberIndex(members: []const *const Node, name: []const u8) ?usize {
    for (members, 0..) |m, i| if (std.mem.eql(u8, m.text, name)) return i;
    return null;
}

// Zig tip: the depth of a table is one more than the deepest table it references (`reference f to t`); the
// checker refused cycles, so the recursion ends. The tables are found by name in the nodes of the declarations
// that the interpreter keeps in `b.table_nodes`.
fn depthOf(it: *Interp, n: *const Node) usize {
    var d: usize = 0;
    for (n.kids[3..]) |cl| {
        if (!std.mem.eql(u8, cl.text, "reference")) continue;
        for (it.base().table_nodes.items) |other| {
            if (std.mem.eql(u8, other.text, cl.kids[1].text) and other != n) d = @max(d, depthOf(it, other) + 1);
        }
    }
    return d;
}

/// A `table` declaration at the start of the driver: make its plan and the variable that names it.
pub fn declareTable(it: *Interp, n: *const Node) Signal!void {
    const b = it.base();
    const cv = try it.lookup(n.kids[0].text);
    if (cv != .class or cv.class.node == null) return it.fail("table {s}: {s} is not a record class", .{ n.text, n.kids[0].text });
    const members = cv.class.node.?.kids[0].kids;
    const columns = try it.a.alloc([]const u8, members.len);
    for (members, columns) |m, *c| c.* = m.text;
    for (n.kids[3..]) |cl| {
        if (std.mem.eql(u8, cl.text, "column")) {
            if (memberIndex(members, cl.kids[0].text)) |i| columns[i] = cl.kids[1].text;
        }
    }
    var keys: std.ArrayList(usize) = .empty;
    if (findClause(n, "key")) |cl| {
        for (cl.kids) |f| try keys.append(it.a, memberIndex(members, f.text) orelse return it.fail("unknown field {s} in key of {s}", .{ f.text, n.text }));
    } else if (memberIndex(members, "id")) |i| try keys.append(it.a, i);
    var gen: std.ArrayList(usize) = .empty;
    if (findClause(n, "generated")) |cl| {
        for (cl.kids) |f| try gen.append(it.a, memberIndex(members, f.text) orelse return it.fail("unknown field {s} in generated of {s}", .{ f.text, n.text }));
    }
    const version: ?usize = if (findClause(n, "version")) |cl| memberIndex(members, cl.kids[0].text) else null;
    const t = try it.a.create(Table);
    t.* = .{
        .name = n.text,
        .node = n,
        .cls = cv.class,
        .conn_name = n.kids[1].text,
        .db_name = if (n.kids[2].tag == .str) n.kids[2].text else n.text,
        .members = members,
        .columns = columns,
        .keys = keys.items,
        .generated = gen.items,
        .version = version,
        .read_only = findClause(n, "read only") != null,
        .temporary = findClause(n, "temporary") != null,
        .depth = depthOf(it, n),
    };
    if (b.table_class == null) {
        const cls = try it.a.create(Class);
        cls.* = .{ .name = "Table" };
        b.table_class = cls;
    }
    try b.tables.append(it.a, t);
    const obj = try it.newObject();
    obj.class = b.table_class;
    try it.setField(obj, "name", try it.newStr(n.text));
    try it.setField(obj, "handle", .{ .int = @intCast(b.tables.items.len - 1) });
    try it.define(n.text, .{ .object = obj }, true);
}

// ---- SQL text ---------------------------------------------------------------------------------

// Zig tip: generated SQL always quotes identifiers, so the names match exactly and a name that is a keyword of
// SQL is still a name (database.md, column = value mapping, rule 1). A quote inside a name is doubled.
fn quote(it: *Interp, buf: *std.ArrayList(u8), name: []const u8) Signal!void {
    try buf.append(it.t, '"');
    for (name) |ch| {
        if (ch == '"') try buf.append(it.t, '"');
        try buf.append(it.t, ch);
    }
    try buf.append(it.t, '"');
}

/// The table name of the database, `"schema"."table"` when it has a dot.
fn quoteTable(it: *Interp, buf: *std.ArrayList(u8), t: *const Table) Signal!void {
    if (std.mem.indexOfScalar(u8, t.db_name, '.')) |dot| {
        try quote(it, buf, t.db_name[0..dot]);
        try buf.append(it.t, '.');
        try quote(it, buf, t.db_name[dot + 1 ..]);
    } else try quote(it, buf, t.db_name);
}

/// `select "col" as "field", … from "table"`: the plan in the order of the fields (database.md, rule 3).
fn selectPlan(it: *Interp, t: *const Table) Signal!std.ArrayList(u8) {
    var buf: std.ArrayList(u8) = .empty;
    try buf.appendSlice(it.t, "select ");
    for (t.members, t.columns, 0..) |m, c, i| {
        if (i > 0) try buf.appendSlice(it.t, ", ");
        try quote(it, &buf, c);
        try buf.appendSlice(it.t, " as ");
        try quote(it, &buf, m.text);
    }
    try buf.appendSlice(it.t, " from ");
    try quoteTable(it, &buf, t);
    return buf;
}

fn sqlType(m: *const Node) []const u8 {
    const ty = dlib.baseType(m.ty);
    const eql = std.mem.eql;
    if (eql(u8, ty, "Integer") or eql(u8, ty, "Natural") or eql(u8, ty, "Short") or eql(u8, ty, "Byte") or eql(u8, ty, "Logic")) return "integer";
    if (eql(u8, ty, "Real") or eql(u8, ty, "Float")) return "real";
    return "text";
}

// Zig tip: a `temporary` table is the only table that the VM creates: from the class, at the first use (database.md,
// the table declaration). The columns follow the type table of the specification; the key is the primary key.
fn ensureTemporary(it: *Interp, t: *Table, db: *sqlite.Db) Signal!void {
    if (!t.temporary or t.created) return;
    var buf: std.ArrayList(u8) = .empty;
    try buf.appendSlice(it.t, "create table if not exists ");
    try quoteTable(it, &buf, t);
    try buf.appendSlice(it.t, " (");
    for (t.members, t.columns, 0..) |m, c, i| {
        if (i > 0) try buf.appendSlice(it.t, ", ");
        try quote(it, &buf, c);
        try buf.append(it.t, ' ');
        try buf.appendSlice(it.t, sqlType(m));
        if (!dlib.isOptional(m.ty)) try buf.appendSlice(it.t, " not null");
    }
    try buf.appendSlice(it.t, ", primary key (");
    for (t.keys, 0..) |k, i| {
        if (i > 0) try buf.appendSlice(it.t, ", ");
        try quote(it, &buf, t.columns[k]);
    }
    try buf.appendSlice(it.t, "))");
    db.exec(try it.t.dupeZ(u8, buf.items)) catch return it.failWith(err_io, "DatabaseError: {s}", .{db.errorMessage()});
    t.created = true;
}

/// The connection of a table, opened at its first use (with the check of the mapping), and its handle.
fn connOf(it: *Interp, t: *Table) Signal!usize {
    const idx = try dlib.openConnection(it, t.conn_name);
    const db = it.base().dbs.items[idx];
    try ensureTemporary(it, t, db);
    return idx;
}

// ---- records and the session ------------------------------------------------------------------

/// The text of the key of a record, for the identity map.
fn keyText(it: *Interp, t: *const Table, values: []const Value) Signal![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    for (values, 0..) |v, i| {
        if (i > 0) try buf.append(it.t, 0x1f);
        try buf.appendSlice(it.t, try it.text(v));
    }
    _ = t;
    return buf.items;
}

fn keyOf(it: *Interp, t: *const Table, obj: *Object) Signal![]const u8 {
    const values = try it.t.alloc(Value, t.keys.len);
    for (t.keys, values) |k, *v| v.* = Interp.fieldOf(obj, t.members[k].text) orelse .nil;
    return keyText(it, t, values);
}

fn trackOf(it: *Interp, obj: *Object) ?*Track {
    return it.base().tracks.get(obj);
}

/// Start to track `obj` in the session of the table. The session holds a reference until the record is released.
fn track(it: *Interp, t: *Table, obj: *Object, status: Status, conn: usize) Signal!*Track {
    const b = it.base();
    const tr = try it.a.create(Track);
    tr.* = .{ .table = t, .obj = obj, .status = status, .orig = try it.a.alloc(?Value, t.members.len), .conn = conn };
    for (tr.orig) |*o| o.* = null;
    Heap.retain(.{ .object = obj });
    try b.tracks.put(it.a, obj, tr);
    try b.track_list.append(it.a, tr);
    return tr;
}

fn clearOrig(it: *Interp, tr: *Track) void {
    for (tr.orig) |*o| {
        if (o.*) |v| it.h.release(v);
        o.* = null;
    }
}

/// The session lets the record go: no longer tracked, no longer held.
fn untrack(it: *Interp, tr: *Track) void {
    const b = it.base();
    clearOrig(it, tr);
    _ = b.tracks.remove(tr.obj);
    for (b.track_list.items, 0..) |x, i| if (x == tr) {
        _ = b.track_list.swapRemove(i);
        break;
    };
    for (b.pending.items, 0..) |x, i| if (x == tr) {
        _ = b.pending.orderedRemove(i);
        break;
    };
    if (keyOf(it, tr.table, tr.obj)) |key| {
        _ = tr.table.identity.remove(key);
    } else |_| {}
    it.h.release(.{ .object = tr.obj });
}

fn pend(it: *Interp, tr: *Track) Signal!void {
    if (tr.in_pending) return;
    tr.in_pending = true;
    try it.base().pending.append(it.a, tr);
}

/// Make the objects read from the database tracked records, one by one; a record already in the identity map is
/// given again (the same object), so the program never holds two copies of a row (database.md, dirty fields).
fn trackRows(it: *Interp, t: *Table, conn: usize, rows: *interp.List) Signal!void {
    const items = rows.elems();
    for (items, 0..) |row, i| {
        const key = try keyOf(it, t, row.object);
        if (t.identity.get(key)) |known| {
            it.setCell(&rows.elems()[i], .{ .object = known.obj });
            continue;
        }
        const tr = try track(it, t, row.object, .clean, conn);
        try t.identity.put(it.a, try it.a.dupe(u8, key), tr);
    }
}

// ---- reading ----------------------------------------------------------------------------------

fn paramsOf(it: *Interp, nodes: []const *const Node) Signal![]Value {
    var out: std.ArrayList(Value) = .empty;
    for (nodes) |n| try out.append(it.t, try it.eval(n));
    return out.items;
}

fn writeAccess(it: *Interp, t: *Table, what: []const u8) Signal!void {
    if (t.read_only) return it.fail("table {s} is read only: {s} is refused", .{ t.name, what });
}

/// `t.find!(key…)`: the record with this key, tracked, or null.
fn find(it: *Interp, t: *Table, args: []const *const Node) Signal!Value {
    if (args.len != t.keys.len) return it.failWith(err_argument, "{s}.find! takes {d} value(s): the key", .{ t.name, t.keys.len });
    const conn = try connOf(it, t);
    const db = it.base().dbs.items[conn];
    try dlib.enlist(it, conn, db);
    const values = try paramsOf(it, args);
    if (t.identity.get(try keyText(it, t, values))) |known| {
        return if (known.status == .removed) .nil else .{ .object = known.obj };
    }
    var buf = try selectPlan(it, t);
    try buf.appendSlice(it.t, " where ");
    for (t.keys, 0..) |k, i| {
        if (i > 0) try buf.appendSlice(it.t, " and ");
        try quote(it, &buf, t.columns[k]);
        try buf.appendSlice(it.t, " = ?");
    }
    var changed: i64 = 0;
    const rows = try dlib.runStatement(it, db, buf.items, values, t.cls, &changed);
    if (rows.elems().len == 0) return .nil;
    try trackRows(it, t, conn, rows);
    return rows.elems()[0];
}

/// `t.where!(cond, args…)` (tracked) and `t.scan!(cond, args…)` (not tracked): the rows as a list.
fn where(it: *Interp, t: *Table, args: []const *const Node, tracked: bool) Signal!Value {
    if (args.len < 1) return it.failWith(err_argument, "{s}.where! takes the condition: a SQL text after where, with ? placeholders", .{t.name});
    const conn = try connOf(it, t);
    const db = it.base().dbs.items[conn];
    try dlib.enlist(it, conn, db);
    const cond = try it.text(try it.eval(args[0]));
    const values = try paramsOf(it, args[1..]);
    if (tracked) try flushConn(it, conn); // the job reads its own changes
    var buf = try selectPlan(it, t);
    try buf.appendSlice(it.t, " where ");
    try buf.appendSlice(it.t, cond);
    var changed: i64 = 0;
    const rows = try dlib.runStatement(it, db, buf.items, values, t.cls, &changed);
    if (tracked) try trackRows(it, t, conn, rows);
    return .{ .list = rows };
}

fn count(it: *Interp, t: *Table, args: []const *const Node) Signal!Value {
    const conn = try connOf(it, t);
    const db = it.base().dbs.items[conn];
    try dlib.enlist(it, conn, db);
    const cond = if (args.len >= 1) try it.text(try it.eval(args[0])) else "1 = 1";
    const values: []const Value = if (args.len >= 1) try paramsOf(it, args[1..]) else &[_]Value{};
    try flushConn(it, conn);
    var buf: std.ArrayList(u8) = .empty;
    try buf.appendSlice(it.t, "select count(*) from ");
    try quoteTable(it, &buf, t);
    try buf.appendSlice(it.t, " where ");
    try buf.appendSlice(it.t, cond);
    var st = db.prepare(try it.t.dupeZ(u8, buf.items)) catch return it.failWith(err_io, "DatabaseError: {s}", .{db.errorMessage()});
    defer st.finalize();
    try dlib.bindAll(it, db, &st, values);
    const row = st.step() catch return it.failWith(err_io, "DatabaseError: {s}", .{db.errorMessage()});
    return .{ .int = if (row) st.columnInt(0) else 0 };
}

// ---- writing: add, remove, change --------------------------------------------------------------

/// The class of the record may declare `validate(@self)`: it runs before every write (database.md, validation).
pub fn validate(it: *Interp, obj: *Object) Signal!void {
    const cls = obj.class orelse return;
    if (Interp.classRoutine(cls, "validate") != null) _ = try it.callMethod(.{ .object = obj }, "validate", &.{});
}

/// `let t <+ record;` and `t.add(record)`: the record waits to be inserted at the next flush.
pub fn tableAdd(it: *Interp, tobj: *Object, item: Value) Signal!void {
    const t = tableOf(it, tobj);
    try writeAccess(it, t, "add");
    if (item == .list) {
        for (item.list.elems()) |e| try tableAdd(it, tobj, e);
        return;
    }
    if (item != .object or item.object.class != t.cls) return it.fail("{s} takes records of the class {s}, not a {s}", .{ t.name, t.cls.name, Interp.typeName(item) });
    if (trackOf(it, item.object)) |tr| {
        if (tr.status == .removed) {
            tr.status = .dirty;
            return;
        }
        return; // already in a session
    }
    const conn = try connOf(it, t);
    const tr = try track(it, t, item.object, .added, conn);
    try pend(it, tr);
    if (it.current_job.len == 0) try flushConn(it, conn); // outside a job a write is committed at once
}

fn remove(it: *Interp, t: *Table, args: []const *const Node) Signal!void {
    try writeAccess(it, t, "remove");
    if (args.len == 0) return it.failWith(err_argument, "{s}.remove takes a record or a key", .{t.name});
    var rec = try it.eval(args[0]);
    if (rec != .object or rec.object.class != t.cls) {
        rec = try find(it, t, args);
        if (rec == .nil) return;
    }
    const tr = trackOf(it, rec.object) orelse {
        const conn = try connOf(it, t);
        const nt = try track(it, t, rec.object, .removed, conn);
        try pend(it, nt);
        if (it.current_job.len == 0) try flushConn(it, conn);
        return;
    };
    if (tr.status == .added) {
        untrack(it, tr); // never written: forget it
        return;
    }
    tr.status = .removed;
    try pend(it, tr);
    if (it.current_job.len == 0) try flushConn(it, tr.conn);
}

/// A field of a tracked record is about to change (`let c.city := v;`, or a field name in an update block). The new
/// value is compared with the original: a different value makes the record dirty, the original again makes it clean.
pub fn beforeChange(it: *Interp, obj: *Object, field: []const u8, new: Value) Signal!void {
    const tr = trackOf(it, obj) orelse return;
    const t = tr.table;
    const i = memberIndex(t.members, field) orelse return;
    if (t.read_only) return it.fail("field {s} can not be changed: table {s} is read only", .{ field, t.name });
    for (t.keys) |k| if (k == i and tr.status != .added) return it.fail("field {s} can not be changed: it is the key of {s}; a key change is a delete and an insert", .{ field, t.name });
    for (t.generated) |g| if (g == i) return it.fail("field {s} can not be changed: the database generates it in {s}", .{ field, t.name });
    if (tr.status == .added or tr.status == .removed) return;
    const old = Interp.fieldOf(obj, field) orelse .nil;
    if (tr.orig[i]) |o| {
        // changed before: back to the original makes the field clean again
        if (Interp.eq(o, new)) {
            it.h.release(o);
            tr.orig[i] = null;
            var any = false;
            for (tr.orig) |x| if (x != null) {
                any = true;
            };
            if (!any) tr.status = .clean;
        }
        return;
    }
    if (Interp.eq(old, new)) return;
    Heap.retain(old);
    tr.orig[i] = old;
    tr.status = .dirty;
    try pend(it, tr);
}

/// After the change: outside a job each change is written at once, one statement at a time.
pub fn afterChange(it: *Interp, obj: *Object) Signal!void {
    const tr = trackOf(it, obj) orelse return;
    if (it.current_job.len == 0 and tr.status == .dirty) try flushConn(it, tr.conn);
}

/// Is any record tracked? (A cheap test before the hooks of an assignment.)
pub fn active(it: *Interp) bool {
    return it.base().tracks.count() > 0;
}

// ---- flush: the changes go to the database -------------------------------------------------------

fn lessDepth(_: void, a: *Track, b: *Track) bool {
    return a.table.depth < b.table.depth;
}

fn moreDepth(_: void, a: *Track, b: *Track) bool {
    return a.table.depth > b.table.depth;
}

fn conflict(it: *Interp, t: *const Table, obj: *Object) Signal {
    const key = keyOf(it, t, obj) catch "?";
    const ver: Value = if (t.version) |v| (Interp.fieldOf(obj, t.members[v].text) orelse .nil) else .nil;
    const vtext = it.text(ver) catch "?";
    return it.failWith(err_conflict, "Row {s} of {s} was changed by someone else (version {s})", .{ key, t.name, vtext });
}

/// Run one write statement; when the statement has a RETURNING clause, read the row into the fields `ret`.
fn writeStatement(it: *Interp, db: *sqlite.Db, sql: []const u8, params: []const Value, t: *const Table, ret: []const usize, obj: *Object) Signal!i64 {
    var st = db.prepare(try it.t.dupeZ(u8, sql)) catch return it.failWith(interp.err_io, "DatabaseError: {s}: {s}", .{ db.errorMessage(), sql });
    defer st.finalize();
    try dlib.bindAll(it, db, &st, params);
    const row = st.step() catch {
        const msg = db.errorMessage();
        if (std.mem.indexOf(u8, msg, "constraint") != null) return it.failWith(52, "Constraint violated on {s}: {s}", .{ t.name, msg });
        return it.failWith(interp.err_io, "DatabaseError: {s}: {s}", .{ msg, sql });
    };
    if (row) {
        for (ret, 0..) |m, col| {
            const v = try dlib.columnValue(it, &st, @intCast(col), t.members[m], t.cls.name);
            try it.setField(obj, t.members[m].text, v);
        }
        // with `returning` the statement is not finished after its first row: SQLite counts the changed rows only
        // when it is done, and until then `changes()` still gives the count of the previous write (which made a
        // conflict look like a success, or a success like a conflict, in a retried job)
        while (st.step() catch return it.failWith(interp.err_io, "DatabaseError: {s}: {s}", .{ db.errorMessage(), sql })) {}
    }
    return db.changes();
}

fn doInsert(it: *Interp, tr: *Track) Signal!void {
    const t = tr.table;
    const db = it.base().dbs.items[tr.conn];
    try dlib.enlist(it, tr.conn, db); // a write outside a transaction would be committed before a later record fails
    try validate(it, tr.obj);
    var cols: std.ArrayList(u8) = .empty;
    var marks: std.ArrayList(u8) = .empty;
    var params: std.ArrayList(Value) = .empty;
    var ret: std.ArrayList(usize) = .empty;
    var first = true;
    for (t.members, 0..) |m, i| {
        var is_gen = false;
        for (t.generated) |g| if (g == i) {
            is_gen = true;
        };
        if (is_gen) {
            try ret.append(it.t, i);
            continue;
        }
        if (!first) {
            try cols.appendSlice(it.t, ", ");
            try marks.appendSlice(it.t, ", ");
        }
        first = false;
        try quote(it, &cols, t.columns[i]);
        try marks.append(it.t, '?');
        // a new row has the version 1 (database.md, optimistic locking)
        if (t.version != null and t.version.? == i) {
            try params.append(it.t, .{ .int = 1 });
            try ret.append(it.t, i);
        } else try params.append(it.t, Interp.fieldOf(tr.obj, m.text) orelse .nil);
    }
    var sql: std.ArrayList(u8) = .empty;
    try sql.appendSlice(it.t, "insert into ");
    try quoteTable(it, &sql, t);
    if (first) {
        try sql.appendSlice(it.t, " default values");
    } else {
        try sql.appendSlice(it.t, " (");
        try sql.appendSlice(it.t, cols.items);
        try sql.appendSlice(it.t, ") values (");
        try sql.appendSlice(it.t, marks.items);
        try sql.append(it.t, ')');
    }
    if (ret.items.len > 0) {
        try sql.appendSlice(it.t, " returning ");
        for (ret.items, 0..) |m, k| {
            if (k > 0) try sql.appendSlice(it.t, ", ");
            try quote(it, &sql, t.columns[m]);
        }
    }
    _ = try writeStatement(it, db, sql.items, params.items, t, ret.items, tr.obj);
}

fn whereKey(it: *Interp, t: *const Table, sql: *std.ArrayList(u8), params: *std.ArrayList(Value), obj: *Object, version: ?Value) Signal!void {
    try sql.appendSlice(it.t, " where ");
    for (t.keys, 0..) |k, i| {
        if (i > 0) try sql.appendSlice(it.t, " and ");
        try quote(it, sql, t.columns[k]);
        try sql.appendSlice(it.t, " = ?");
        try params.append(it.t, Interp.fieldOf(obj, t.members[k].text) orelse .nil);
    }
    if (t.version) |v| {
        try sql.appendSlice(it.t, " and ");
        try quote(it, sql, t.columns[v]);
        try sql.appendSlice(it.t, " = ?");
        try params.append(it.t, version orelse (Interp.fieldOf(obj, t.members[v].text) orelse .nil));
    }
}

// Zig tip: the statement of an update lists only the dirty fields, in the order of the plan, then the version
// (`"version" = "version" + 1`); the `where` has the key and the version that was read. A statement that changes
// no row means that someone else changed (or removed) the row: a ConflictError, and the record becomes `stale`.
fn doUpdate(it: *Interp, tr: *Track) Signal!void {
    const t = tr.table;
    const db = it.base().dbs.items[tr.conn];
    try dlib.enlist(it, tr.conn, db); // a write outside a transaction would be committed before a later record fails
    try validate(it, tr.obj);
    var sql: std.ArrayList(u8) = .empty;
    var params: std.ArrayList(Value) = .empty;
    try sql.appendSlice(it.t, "update ");
    try quoteTable(it, &sql, t);
    try sql.appendSlice(it.t, " set ");
    var first = true;
    for (t.members, 0..) |m, i| {
        if (tr.orig[i] == null) continue;
        if (!first) try sql.appendSlice(it.t, ", ");
        first = false;
        try quote(it, &sql, t.columns[i]);
        try sql.appendSlice(it.t, " = ?");
        try params.append(it.t, Interp.fieldOf(tr.obj, m.text) orelse .nil);
    }
    if (first) return; // nothing is dirty: nothing is written
    var ret: [1]usize = undefined;
    var n_ret: usize = 0;
    if (t.version) |v| {
        try sql.appendSlice(it.t, ", ");
        try quote(it, &sql, t.columns[v]);
        try sql.appendSlice(it.t, " = ");
        try quote(it, &sql, t.columns[v]);
        try sql.appendSlice(it.t, " + 1");
        ret[0] = v;
        n_ret = 1;
    }
    try whereKey(it, t, &sql, &params, tr.obj, null);
    if (n_ret > 0) {
        try sql.appendSlice(it.t, " returning ");
        try quote(it, &sql, t.columns[ret[0]]);
    }
    const changed = try writeStatement(it, db, sql.items, params.items, t, ret[0..n_ret], tr.obj);
    if (changed == 0) {
        tr.status = .stale;
        return conflict(it, t, tr.obj);
    }
}

fn doDelete(it: *Interp, tr: *Track) Signal!void {
    const t = tr.table;
    const db = it.base().dbs.items[tr.conn];
    try dlib.enlist(it, tr.conn, db); // a write outside a transaction would be committed before a later record fails
    var sql: std.ArrayList(u8) = .empty;
    var params: std.ArrayList(Value) = .empty;
    try sql.appendSlice(it.t, "delete from ");
    try quoteTable(it, &sql, t);
    try whereKey(it, t, &sql, &params, tr.obj, null);
    const changed = try writeStatement(it, db, sql.items, params.items, t, &.{}, tr.obj);
    if (changed == 0 and t.version != null) {
        tr.status = .stale;
        return conflict(it, t, tr.obj);
    }
}

// Zig tip: the order of a flush (database.md): inserts in the order of the references (customers before orders),
// then updates in the same order, then deletes in the reverse order. `std.mem.sort` is stable enough for this
// here because the pending list is already in the order of the changes. The records that were written are taken
// out of the pending list; the others (another connection) stay.
/// Write the pending changes of the connection `only` (all connections when null) to the database.
pub fn flushConn(it: *Interp, only: ?usize) Signal!void {
    const b = it.base();
    if (b.pending.items.len == 0) return;
    var inserts: std.ArrayList(*Track) = .empty;
    var updates: std.ArrayList(*Track) = .empty;
    var deletes: std.ArrayList(*Track) = .empty;
    for (b.pending.items) |tr| {
        if (only) |c| if (tr.conn != c) continue;
        switch (tr.status) {
            .added => try inserts.append(it.t, tr),
            .dirty => try updates.append(it.t, tr),
            .removed => try deletes.append(it.t, tr),
            else => {},
        }
    }
    std.mem.sort(*Track, inserts.items, {}, lessDepth);
    std.mem.sort(*Track, updates.items, {}, lessDepth);
    std.mem.sort(*Track, deletes.items, {}, moreDepth);
    for (inserts.items) |tr| {
        try doInsert(it, tr);
        tr.status = .clean;
        tr.in_pending = false;
        const key = try keyOf(it, tr.table, tr.obj);
        try tr.table.identity.put(it.a, try it.a.dupe(u8, key), tr);
    }
    for (updates.items) |tr| {
        try doUpdate(it, tr);
        clearOrig(it, tr);
        tr.status = .clean;
        tr.in_pending = false;
    }
    for (deletes.items) |tr| {
        try doDelete(it, tr);
        tr.in_pending = false;
        untrack(it, tr);
    }
    var k: usize = 0;
    while (k < b.pending.items.len) {
        if (!b.pending.items[k].in_pending) _ = b.pending.orderedRemove(k) else k += 1;
    }
}

// ---- the other methods of a table ------------------------------------------------------------------

fn refresh(it: *Interp, t: *Table, args: []const *const Node) Signal!void {
    if (args.len != 1) return it.failWith(err_argument, "{s}.refresh takes a record", .{t.name});
    const rec = try it.eval(args[0]);
    if (rec != .object) return it.failWith(err_argument, "{s}.refresh takes a record", .{t.name});
    const tr = trackOf(it, rec.object) orelse return it.fail("the record is not tracked: nothing to refresh", .{});
    const conn = tr.conn;
    const db = it.base().dbs.items[conn];
    var buf = try selectPlan(it, t);
    var params: std.ArrayList(Value) = .empty;
    try whereKey(it, t, &buf, &params, rec.object, .nil);
    // refresh reads by the key only, whatever the version is
    var sql: std.ArrayList(u8) = .empty;
    try sql.appendSlice(it.t, buf.items);
    if (t.version != null) {
        const cut = std.mem.lastIndexOf(u8, sql.items, " and ").?;
        sql.shrinkRetainingCapacity(cut);
        _ = params.pop();
    }
    var changed: i64 = 0;
    const rows = try dlib.runStatement(it, db, sql.items, params.items, t.cls, &changed);
    if (rows.elems().len == 0) return it.fail("refresh: the row of {s} no longer exists", .{t.name});
    const fresh = rows.elems()[0].object;
    for (t.members) |m| try it.setField(rec.object, m.text, Interp.fieldOf(fresh, m.text) orelse .nil);
    clearOrig(it, tr);
    tr.status = .clean;
}

fn statusOf(it: *Interp, args: []const *const Node) Signal!Value {
    if (args.len != 1) return it.failWith(err_argument, "status takes a record", .{});
    const rec = try it.eval(args[0]);
    if (rec != .object) return it.newStr("detached");
    const tr = trackOf(it, rec.object) orelse return it.newStr("detached");
    return it.newStr(@tagName(tr.status));
}

fn detach(it: *Interp, args: []const *const Node) Signal!void {
    if (args.len != 1) return it.failWith(err_argument, "detach takes a record", .{});
    const rec = try it.eval(args[0]);
    if (rec == .object) if (trackOf(it, rec.object)) |tr| untrack(it, tr);
}

// Zig tip: `load!` is the bulk path: the rows are written without being tracked, with the key of the declaration.
// "insert" adds the rows; "upsert" and "merge" insert and, when the key exists, update the other columns
// (`on conflict (key) do update set …`). The counts are the rows the statements changed; a row that was inserted
// and a row that was updated are told apart by asking the database whether the key was there before.
/// `t.load!(rows, mode: …)`: write many rows at once, not tracked; the result has `inserted`, `updated` and `deleted`.
fn load(it: *Interp, t: *Table, args: []const *const Node) Signal!Value {
    try writeAccess(it, t, "load!");
    if (args.len < 1) return it.failWith(err_argument, "{s}.load! takes the rows", .{t.name});
    const rows = try it.iterate(try it.eval(args[0]));
    var mode: []const u8 = "insert";
    for (args[1..]) |a| {
        if (a.tag == .pair and a.kids[0].tag == .name and std.mem.eql(u8, a.kids[0].text, "mode")) {
            const mv = try it.eval(a.kids[1]);
            if (mv != .str) return it.failWith(err_argument, "load!: mode is \"insert\", \"upsert\" or \"merge\"", .{});
            mode = mv.str;
        }
    }
    const upsert = std.mem.eql(u8, mode, "upsert") or std.mem.eql(u8, mode, "merge");
    if (!upsert and !std.mem.eql(u8, mode, "insert")) return it.failWith(err_argument, "load!: mode is \"insert\", \"upsert\" or \"merge\"", .{});
    const conn = try connOf(it, t);
    const db = it.base().dbs.items[conn];
    try dlib.enlist(it, conn, db);
    try flushConn(it, conn);
    var inserted: i64 = 0;
    var updated: i64 = 0;
    for (rows) |row| {
        if (row != .object or row.object.class != t.cls) return it.fail("{s}.load! takes records of the class {s}", .{ t.name, t.cls.name });
        try validate(it, row.object);
        var existed = false;
        if (upsert) {
            var probe: std.ArrayList(u8) = .empty;
            var pp: std.ArrayList(Value) = .empty;
            try probe.appendSlice(it.t, "select 1 from ");
            try quoteTable(it, &probe, t);
            try whereKeyOnly(it, t, &probe, &pp, row.object);
            var st = db.prepare(try it.t.dupeZ(u8, probe.items)) catch return it.failWith(err_io, "DatabaseError: {s}", .{db.errorMessage()});
            defer st.finalize();
            try dlib.bindAll(it, db, &st, pp.items);
            existed = st.step() catch false;
        }
        var cols: std.ArrayList(u8) = .empty;
        var marks: std.ArrayList(u8) = .empty;
        var params: std.ArrayList(Value) = .empty;
        var sets: std.ArrayList(u8) = .empty;
        var first = true;
        for (t.members, 0..) |m, i| {
            var is_gen = false;
            for (t.generated) |g| if (g == i) {
                is_gen = true;
            };
            if (is_gen) continue;
            if (!first) {
                try cols.appendSlice(it.t, ", ");
                try marks.appendSlice(it.t, ", ");
            }
            first = false;
            try quote(it, &cols, t.columns[i]);
            try marks.append(it.t, '?');
            try params.append(it.t, Interp.fieldOf(row.object, m.text) orelse .nil);
            var is_key = false;
            for (t.keys) |k| if (k == i) {
                is_key = true;
            };
            if (!is_key) {
                if (sets.items.len > 0) try sets.appendSlice(it.t, ", ");
                try quote(it, &sets, t.columns[i]);
                try sets.appendSlice(it.t, " = excluded.");
                try quote(it, &sets, t.columns[i]);
            }
        }
        var sql: std.ArrayList(u8) = .empty;
        try sql.appendSlice(it.t, "insert into ");
        try quoteTable(it, &sql, t);
        try sql.appendSlice(it.t, " (");
        try sql.appendSlice(it.t, cols.items);
        try sql.appendSlice(it.t, ") values (");
        try sql.appendSlice(it.t, marks.items);
        try sql.append(it.t, ')');
        if (upsert) {
            try sql.appendSlice(it.t, " on conflict (");
            for (t.keys, 0..) |k, i| {
                if (i > 0) try sql.appendSlice(it.t, ", ");
                try quote(it, &sql, t.columns[k]);
            }
            if (sets.items.len > 0) {
                try sql.appendSlice(it.t, ") do update set ");
                try sql.appendSlice(it.t, sets.items);
            } else try sql.appendSlice(it.t, ") do nothing");
        }
        _ = try writeStatement(it, db, sql.items, params.items, t, &.{}, row.object);
        if (existed) updated += 1 else inserted += 1;
    }
    const out = try it.newObject();
    try it.setField(out, "inserted", .{ .int = inserted });
    try it.setField(out, "updated", .{ .int = updated });
    try it.setField(out, "deleted", .{ .int = 0 });
    return .{ .object = out };
}

fn whereKeyOnly(it: *Interp, t: *const Table, sql: *std.ArrayList(u8), params: *std.ArrayList(Value), obj: *Object) Signal!void {
    try sql.appendSlice(it.t, " where ");
    for (t.keys, 0..) |k, i| {
        if (i > 0) try sql.appendSlice(it.t, " and ");
        try quote(it, sql, t.columns[k]);
        try sql.appendSlice(it.t, " = ?");
        try params.append(it.t, Interp.fieldOf(obj, t.members[k].text) orelse .nil);
    }
}

/// The methods of a `table`: `find!`, `where!`, `scan!`, `count!`, `add`, `remove`, `refresh`, `detach`, `status`, `flush`, `load!`.
pub fn tableCall(it: *Interp, tobj: *Object, name: []const u8, args: []const *const Node) Signal!Value {
    const t = tableOf(it, tobj);
    const eql = std.mem.eql;
    if (eql(u8, name, "find!")) return find(it, t, args);
    if (eql(u8, name, "where!")) return where(it, t, args, true);
    if (eql(u8, name, "scan!")) return where(it, t, args, false);
    if (eql(u8, name, "count!")) return count(it, t, args);
    if (eql(u8, name, "add")) {
        if (args.len != 1) return it.failWith(err_argument, "{s}.add takes a record", .{t.name});
        try tableAdd(it, tobj, try it.eval(args[0]));
        return .nil;
    }
    if (eql(u8, name, "remove")) {
        try remove(it, t, args);
        return .nil;
    }
    if (eql(u8, name, "refresh")) {
        try refresh(it, t, args);
        return .nil;
    }
    if (eql(u8, name, "detach")) {
        try detach(it, args);
        return .nil;
    }
    if (eql(u8, name, "status")) return statusOf(it, args);
    if (eql(u8, name, "flush")) {
        try flushConn(it, try connOf(it, t));
        return .nil;
    }
    if (eql(u8, name, "load!")) return load(it, t, args);
    return it.fail("a table has no method '{s}'", .{name});
}

// ---- the transaction of a job -----------------------------------------------------------------------

/// Drop every tracked record that is clean (a job is over; the records of a rolled back job are detached).
fn releaseSession(it: *Interp, all: bool) void {
    const b = it.base();
    var i = b.track_list.items.len;
    while (i > 0) {
        i -= 1;
        const tr = b.track_list.items[i];
        if (all or tr.status == .clean) untrack(it, tr);
    }
}

// Zig tip: the end of a job (database.md, transactions): when the job went well, every enlisted session is flushed
// and then every enlisted connection is committed; when the flush fails the job fails and everything is rolled
// back. When the job failed or ended by `rollback;`, the database rolls back and the records are detached (they
// keep their values in memory, D-158). The function returns the error of the flush so the caller can fail the job.
/// `done` of a job: flush and commit, or roll back.
pub fn endJob(it: *Interp, ok: bool) Signal!void {
    if (ok) {
        flushConn(it, null) catch |e| {
            dlib.finishTransactions(it, false);
            releaseSession(it, true);
            return e;
        };
        dlib.finishTransactions(it, true);
        releaseSession(it, false);
    } else {
        dlib.finishTransactions(it, false);
        releaseSession(it, true);
    }
}

/// `commit;` in a job: flush, commit, and a new transaction begins at the next statement.
pub fn commitJob(it: *Interp) Signal!void {
    try flushConn(it, null);
    dlib.finishTransactions(it, true);
}

// ---- checkpoints (database.md, long loads) -----------------------------------------------------------

/// The core database of the project: the file `core_db` of `eve.cfg`, `db/local.db` by default (D-156). A checkpoint
/// is written outside the transaction of the job (the core database is not the write connection of the job).
fn coreDb(it: *Interp) Signal!*sqlite.Db {
    const b = it.base();
    if (b.core_db) |db| return db;
    const io = it.io orelse return it.fail("checkpoint: no input/output handle", .{});
    var path: []const u8 = "db/local.db";
    if (Io.Dir.cwd().readFileAlloc(io, "eve.cfg", it.t, .limited(1 << 20))) |cfg| {
        var lines = std.mem.splitScalar(u8, cfg, '\n');
        while (lines.next()) |raw| {
            const line = std.mem.trim(u8, raw, " \t\r");
            if (!std.mem.startsWith(u8, line, "core_db")) continue;
            const eq_at = std.mem.indexOfScalar(u8, line, '=') orelse continue;
            const rest = std.mem.trim(u8, line[eq_at + 1 ..], " \t");
            if (rest.len >= 2 and rest[0] == '"') {
                if (std.mem.indexOfScalarPos(u8, rest, 1, '"')) |end| path = try it.a.dupe(u8, rest[1..end]);
            }
        }
    } else |_| {}
    if (std.fs.path.dirname(path)) |dir| Io.Dir.cwd().createDirPath(io, dir) catch {};
    const db = try it.a.create(sqlite.Db);
    db.* = sqlite.Db.open(try it.t.dupeZ(u8, path)) catch return it.failWith(err_io, "DatabaseError: cannot open the core database {s}", .{path});
    db.exec("create table if not exists eve_checkpoint (name text primary key, value text not null, updated text not null) strict") catch
        return it.failWith(err_io, "DatabaseError: {s}", .{db.errorMessage()});
    b.core_db = db;
    return db;
}

/// `checkpoint.write(name, value)` and `checkpoint.read!(:T)(name, default: v)`.
pub fn checkpointCall(it: *Interp, name: []const u8, targs: []const *const Node, args: []const *const Node) Signal!?Value {
    const eql = std.mem.eql;
    if (!eql(u8, name, "write") and !eql(u8, name, "read!")) return null;
    const db = try coreDb(it);
    if (args.len < 1) return it.failWith(err_argument, "checkpoint.{s} takes a name", .{name});
    const key = try it.text(try it.eval(args[0]));
    if (eql(u8, name, "write")) {
        if (args.len != 2) return it.failWith(err_argument, "checkpoint.write takes a name and a value", .{});
        const v = try it.eval(args[1]);
        const io = it.io orelse return it.fail("checkpoint: no input/output handle", .{});
        var aw: Io.Writer.Allocating = .init(it.t);
        instant.write(&aw.writer, @intCast(@divFloor(Io.Timestamp.now(io, .real).toNanoseconds(), 1000))) catch return error.OutOfMemory;
        var st = db.prepare("insert into eve_checkpoint (name, value, updated) values (?, ?, ?) on conflict (name) do update set value = excluded.value, updated = excluded.updated") catch
            return it.failWith(err_io, "DatabaseError: {s}", .{db.errorMessage()});
        defer st.finalize();
        st.bindText(1, key) catch return it.failWith(err_io, "DatabaseError: {s}", .{db.errorMessage()});
        st.bindText(2, try it.text(v)) catch return it.failWith(err_io, "DatabaseError: {s}", .{db.errorMessage()});
        st.bindText(3, aw.written()) catch return it.failWith(err_io, "DatabaseError: {s}", .{db.errorMessage()});
        _ = st.step() catch return it.failWith(err_io, "DatabaseError: {s}", .{db.errorMessage()});
        return .nil;
    }
    var fallback: ?Value = null;
    for (args[1..]) |a| {
        if (a.tag == .pair and a.kids[0].tag == .name and eql(u8, a.kids[0].text, "default")) fallback = try it.eval(a.kids[1]);
    }
    var st = db.prepare("select value from eve_checkpoint where name = ?") catch return it.failWith(err_io, "DatabaseError: {s}", .{db.errorMessage()});
    defer st.finalize();
    st.bindText(1, key) catch return it.failWith(err_io, "DatabaseError: {s}", .{db.errorMessage()});
    const row = st.step() catch return it.failWith(err_io, "DatabaseError: {s}", .{db.errorMessage()});
    if (!row) return fallback orelse .nil;
    const text = st.columnText(0);
    const ty: []const u8 = if (targs.len == 1) targs[0].text else "String";
    if (eql(u8, ty, "Integer")) return .{ .int = std.fmt.parseInt(i64, text, 10) catch return it.failWith(interp.err_convert, "checkpoint {s}: '{s}' is not an Integer", .{ key, text }) };
    if (eql(u8, ty, "Decimal")) return .{ .dec = decimal.parse(text) orelse return it.failWith(interp.err_convert, "checkpoint {s}: '{s}' is not a Decimal", .{ key, text }) };
    if (eql(u8, ty, "Instant")) return .{ .instant = instant.parse(text) orelse return it.failWith(interp.err_convert, "checkpoint {s}: '{s}' is not an Instant", .{ key, text }) };
    if (eql(u8, ty, "Real")) return .{ .real = std.fmt.parseFloat(f64, text) catch return it.failWith(interp.err_convert, "checkpoint {s}: '{s}' is not a Real", .{ key, text }) };
    return try it.newStr(text);
}

/// At the end of the run: the core database is closed.
pub fn closeCore(it: *Interp) void {
    if (it.base().core_db) |db| db.close();
}
