//! The PostgreSQL face of evedb (README.md section 5A): a server of the PostgreSQL frontend/backend protocol, version 3.0, over
//! DuckDB. A client library for PostgreSQL (psql, psycopg2, pg8000, JDBC, the Eve driver) connects to port 5432, logs in, and
//! runs SQL; DuckDB answers. Only a minimal set is built (README.md 5A.2): the startup, the authentication modes trust,
//! password and md5, the simple query protocol, a basic extended protocol with text parameters, transactions, and errors with
//! SQL states. No TLS, no COPY, no cancel, no LISTEN.
const std = @import("std");
const Io = std.Io;
const net = Io.net;
const server = @import("server.zig");
const duckdb = @import("duckdb.zig");
const cells_mod = @import("cells.zig");
const types = @import("types.zig");
const fault = @import("fault.zig");

const Server = server.Server;
const Session = server.Session;

pub const Auth = enum { trust, password, md5 };

// ---------------------------------------------------------------------------------------------------------------- messages

// Zig tip: a PostgreSQL message is one type byte, a 4-byte length (counting itself, big endian) and the body. `Out` builds the
// bytes of many messages in one list and sends them with one write, so an answer to a query is one network call. `begin`
// opens a message and remembers where its length goes; `end` writes the length once the body is known.
const Out = struct {
    gpa: std.mem.Allocator,
    buf: std.ArrayList(u8) = .empty,
    at: usize = 0,

    // Zig tip: a function declared inside a struct whose first parameter is the struct (`self: *T`) is a method: `x.f()`
    // calls `f(&x)`.
    fn deinit(self: *Out) void {
        self.buf.deinit(self.gpa);
    }

    // Zig tip: the result type `!T` (or `Error!T`) is an error union: a value or an error. `try f()` passes the error to
    // the caller; `f() catch …` handles it in place.
    fn begin(self: *Out, kind: u8) !void {
        try self.buf.append(self.gpa, kind);
        self.at = self.buf.items.len;
        try self.buf.appendNTimes(self.gpa, 0, 4);
    }

    // Zig tip: `end` relies on the same Zig feature as `Out` above: see the tip there.
    fn end(self: *Out) void {
        const len: u32 = @intCast(self.buf.items.len - self.at);
        std.mem.writeInt(u32, self.buf.items[self.at..][0..4], len, .big);
    }

    // Zig tip: `i16_` relies on the same Zig feature as `begin` above: see the tip there.
    fn i16_(self: *Out, v: i16) !void {
        try self.buf.appendSlice(self.gpa, &std.mem.toBytes(std.mem.nativeToBig(i16, v)));
    }

    // Zig tip: `i32_` relies on the same Zig feature as `begin` above: see the tip there.
    fn i32_(self: *Out, v: i32) !void {
        try self.buf.appendSlice(self.gpa, &std.mem.toBytes(std.mem.nativeToBig(i32, v)));
    }

    // Zig tip: `u8_` relies on the same Zig feature as `begin` above: see the tip there.
    fn u8_(self: *Out, v: u8) !void {
        try self.buf.append(self.gpa, v);
    }

    // Zig tip: `cstr` relies on the same Zig feature as `begin` above: see the tip there.
    fn cstr(self: *Out, s: []const u8) !void {
        try self.buf.appendSlice(self.gpa, s);
        try self.buf.append(self.gpa, 0);
    }

    // Zig tip: `raw` relies on the same Zig feature as `begin` above: see the tip there.
    fn raw(self: *Out, s: []const u8) !void {
        try self.buf.appendSlice(self.gpa, s);
    }

    // Zig tip: `flush` relies on the same Zig feature as `begin` above: see the tip there.
    fn flush(self: *Out, w: *Io.Writer) !void {
        try w.writeAll(self.buf.items);
        try w.flush();
        self.buf.clearRetainingCapacity();
    }
};

// Zig tip: `readI32` relies on the same Zig feature as `Out` above: see the tip there.
fn readI32(b: []const u8) i32 {
    return std.mem.readInt(i32, b[0..4], .big);
}

// Zig tip: `readI16` relies on the same Zig feature as `Out` above: see the tip there.
fn readI16(b: []const u8) i16 {
    return std.mem.readInt(i16, b[0..2], .big);
}

// Zig tip: `Msg` relies on the same Zig feature as `Out` above: see the tip there.
const Msg = struct { kind: u8, body: []u8 };

// Zig tip: `readMsg` relies on the same Zig feature as `Msg` above: see the tip there.
fn readMsg(r: *Io.Reader, gpa: std.mem.Allocator) !Msg {
    var head: [5]u8 = undefined;
    try r.readSliceAll(&head);
    const len = readI32(head[1..5]);
    if (len < 4 or len > 64 << 20) return error.BadMessage;
    const body = try gpa.alloc(u8, @intCast(len - 4));
    errdefer gpa.free(body);
    try r.readSliceAll(body);
    return .{ .kind = head[0], .body = body };
}

// Zig tip: `errorResponse` relies on the same Zig feature as `begin` above: see the tip there.
/// An error message: severity, SQL state and text.
fn errorResponse(out: *Out, fatal: bool, state: []const u8, msg: []const u8) !void {
    try out.begin('E');
    try out.u8_('S');
    try out.cstr(if (fatal) "FATAL" else "ERROR");
    try out.u8_('V');
    try out.cstr(if (fatal) "FATAL" else "ERROR");
    try out.u8_('C');
    try out.cstr(state);
    try out.u8_('M');
    try out.cstr(msg);
    try out.u8_(0);
    out.end();
}

// Zig tip: `readyForQuery` relies on the same Zig feature as `begin` above: see the tip there.
fn readyForQuery(out: *Out, st: u8) !void {
    try out.begin('Z');
    try out.u8_(st);
    out.end();
}

// Zig tip: `commandComplete` relies on the same Zig feature as `begin` above: see the tip there.
fn commandComplete(out: *Out, tag: []const u8) !void {
    try out.begin('C');
    try out.cstr(tag);
    out.end();
}

// Zig tip: `parameterStatus` relies on the same Zig feature as `begin` above: see the tip there.
fn parameterStatus(out: *Out, name: []const u8, value: []const u8) !void {
    try out.begin('S');
    try out.cstr(name);
    try out.cstr(value);
    out.end();
}

// ---------------------------------------------------------------------------------------------------------------- statements

// Zig tip: `splitStatements` relies on the same Zig feature as `begin` above: see the tip there.
/// Split the text of a simple query at the `;` that are outside quotes, comments and `$$` strings.
fn splitStatements(gpa: std.mem.Allocator, text: []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var start: usize = 0;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        const c = text[i];
        if (c == '\'' or c == '"') {
            i += 1;
            while (i < text.len and text[i] != c) i += 1;
        } else if (c == '-' and i + 1 < text.len and text[i + 1] == '-') {
            while (i < text.len and text[i] != '\n') i += 1;
        } else if (c == '/' and i + 1 < text.len and text[i + 1] == '*') {
            i += 2;
            while (i + 1 < text.len and !(text[i] == '*' and text[i + 1] == '/')) i += 1;
            i += 1;
        } else if (c == '$' and i + 1 < text.len and text[i + 1] == '$') {
            i += 2;
            while (i + 1 < text.len and !(text[i] == '$' and text[i + 1] == '$')) i += 1;
            i += 1;
        } else if (c == ';') {
            try out.append(gpa, text[start..i]);
            start = i + 1;
        }
    }
    if (start < text.len) try out.append(gpa, text[start..]);
    return out.toOwnedSlice(gpa);
}

// Zig tip: `for (a, b) |x, y|` walks two slices of the same length side by side (`0..` gives the index); the lengths are
// checked in safe builds.
fn word(text: []const u8, n: usize, buf: []u8) []const u8 {
    var it = std.mem.tokenizeAny(u8, text, " \t\r\n(;");
    var k: usize = 0;
    while (it.next()) |w| : (k += 1) {
        if (k == n) {
            const m = @min(w.len, buf.len);
            for (w[0..m], 0..) |ch, j| buf[j] = std.ascii.toLower(ch);
            return buf[0..m];
        }
    }
    return "";
}

// Zig tip: `upper` relies on the same Zig feature as `word` above: see the tip there.
fn upper(buf: []u8, s: []const u8) []const u8 {
    const m = @min(s.len, buf.len);
    for (s[0..m], 0..) |ch, j| buf[j] = std.ascii.toUpper(ch);
    return buf[0..m];
}

const Kind = enum { empty, ack, begin, commit, rollback, count, rows, command, show, fault_pragma };

// Zig tip: a plain function: the types of the parameters and of the result are written out, and Zig has no default
// arguments, so a call always passes every parameter.
fn kindOf(sql: []const u8) Kind {
    var b: [24]u8 = undefined;
    const w = word(sql, 0, &b);
    if (w.len == 0) return .empty;
    if (fault.isFaultStatement(sql)) return .fault_pragma;
    const eq = std.mem.eql;
    if (eq(u8, w, "begin") or eq(u8, w, "start")) return .begin;
    if (eq(u8, w, "commit") or eq(u8, w, "end")) return .commit;
    if (eq(u8, w, "rollback") or eq(u8, w, "abort")) return .rollback;
    if (eq(u8, w, "set") or eq(u8, w, "reset") or eq(u8, w, "discard") or eq(u8, w, "deallocate") or eq(u8, w, "listen") or eq(u8, w, "unlisten") or eq(u8, w, "lock")) return .ack;
    if (eq(u8, w, "show")) return .show;
    if (eq(u8, w, "insert") or eq(u8, w, "update") or eq(u8, w, "delete")) {
        if (std.ascii.indexOfIgnoreCase(sql, "returning") != null) return .rows;
        return .count;
    }
    if (eq(u8, w, "create") or eq(u8, w, "drop") or eq(u8, w, "alter") or eq(u8, w, "truncate") or eq(u8, w, "attach") or eq(u8, w, "detach") or eq(u8, w, "checkpoint") or eq(u8, w, "vacuum") or eq(u8, w, "analyze") or eq(u8, w, "comment") or eq(u8, w, "grant") or eq(u8, w, "revoke") or eq(u8, w, "copy") or eq(u8, w, "use") or eq(u8, w, "load") or eq(u8, w, "install")) return .command;
    return .rows;
}

// Zig tip: `f() catch x` uses `x` when `f` fails; `catch {}` drops the error on purpose. Zig refuses to compile an error
// that nobody handles.
/// The command tag of a statement that returns no rows.
fn commandTag(buf: []u8, sql: []const u8, kind: Kind, n: u64) []const u8 {
    var b0: [24]u8 = undefined;
    var b1: [24]u8 = undefined;
    const w0 = word(sql, 0, &b0);
    const eq = std.mem.eql;
    if (kind == .count) {
        if (eq(u8, w0, "insert")) return std.fmt.bufPrint(buf, "INSERT 0 {d}", .{n}) catch "INSERT 0 0";
        var ub: [24]u8 = undefined;
        return std.fmt.bufPrint(buf, "{s} {d}", .{ upper(&ub, w0), n }) catch "UPDATE 0";
    }
    var up0: [24]u8 = undefined;
    var up1: [24]u8 = undefined;
    const second = word(sql, 1, &b1);
    if (kind == .command and second.len > 0 and (eq(u8, w0, "create") or eq(u8, w0, "drop") or eq(u8, w0, "alter"))) {
        return std.fmt.bufPrint(buf, "{s} {s}", .{ upper(&up0, w0), upper(&up1, second) }) catch "CREATE";
    }
    return upper(buf, w0);
}

// Zig tip: the connection keeps what a statement left: the open result (DuckDB's, and the cells that read it), freed when the
// reply has been sent. `Run` is the outcome of running one statement: nothing to say, an acknowledgement, a count, a result
// set, or a failure whose message is already known.
const Run = struct {
    kind: Kind = .ack,
    res: ?duckdb.Result = null,
    cells: ?cells_mod.Cells = null,
    changed: u64 = 0,
    failed: bool = false,
    err_state: []const u8 = "",
    err_len: usize = 0,
    err_buf: [600]u8 = undefined,
    drop: bool = false,

    // Zig tip: `deinit` relies on the same Zig feature as `deinit` above: see the tip there.
    fn deinit(self: *Run) void {
        if (self.cells) |*c| c.deinit();
        if (self.res) |*r| r.deinit();
        self.cells = null;
        self.res = null;
    }

    // Zig tip: `fail` relies on the same Zig feature as `Run` above: see the tip there.
    fn fail(self: *Run, state: []const u8, msg: []const u8) void {
        self.failed = true;
        self.err_state = state;
        const first = if (std.mem.indexOfScalar(u8, msg, '\n')) |nl| msg[0..nl] else msg;
        const n = @min(first.len, self.err_buf.len);
        @memcpy(self.err_buf[0..n], first[0..n]);
        self.err_len = n;
    }

    // Zig tip: the message is kept in the fixed buffer of the struct and read back through this method, because a slice that
    // pointed into the buffer would still point to the old place after the struct is copied (returned by value).
    fn message(self: *const Run) []const u8 {
        return self.err_buf[0..self.err_len];
    }
};

// Zig tip: `sqlState` relies on the same Zig feature as `kindOf` above: see the tip there.
fn sqlState(cls: types.ErrorClass) []const u8 {
    return cls.state;
}

// Zig tip: `Param` relies on the same Zig feature as `Out` above: see the tip there.
/// One parameter: its text (null for NULL), and the type number the client gave (0: not given).
const Param = struct { text: ?[]const u8, oid: u32 };

// Zig tip: `bindParam` relies on the same Zig feature as `Param` above: see the tip there.
fn bindParam(srv: *Server, p: *duckdb.Prepared, i: u64, prm: Param) !void {
    const a = srv.gpa;
    const t = prm.text orelse return p.bindNull(i);
    switch (prm.oid) {
        20, 21, 23 => if (std.fmt.parseInt(i64, std.mem.trim(u8, t, " "), 10)) |n| return p.bindInt(i, n) else |_| {},
        700, 701 => if (std.fmt.parseFloat(f64, std.mem.trim(u8, t, " "))) |x| return p.bindReal(i, x) else |_| {},
        16 => return p.bindBool(i, t.len > 0 and (t[0] == 't' or t[0] == 'T' or t[0] == '1' or t[0] == 'y')),
        else => {},
    }
    const z = try a.dupeZ(u8, t);
    defer a.free(z);
    try p.bindText(i, z);
}

// Zig tip: running a statement is the same for the simple and the extended protocol: the faults that fire before it, the
// preparation, the binding of the parameters, the run, the statement log. The result stays open in `Run` for the caller to
// send. A failure becomes `Run.failed` with a SQL state taken from `types.classify`.
fn runStatement(srv: *Server, s: *Session, sql: []const u8, params: []const Param) Run {
    var r: Run = .{};
    r.kind = kindOf(sql);
    const a = srv.gpa;
    switch (r.kind) {
        .empty, .ack => return r,
        // the settings that drivers ask for are answered here; any other SHOW goes to DuckDB
        .show => if (showValue(showName(sql)) != null) return r,
        .fault_pragma => {
            if (!srv.cfg.test_mode) {
                r.fail("42501", "pragma eve_fault is allowed only in test mode");
                return r;
            }
            const ft = fault.parse(sql) catch {
                r.fail("42601", "bad pragma eve_fault: pragma eve_fault('kind', 'point', arg)");
                return r;
            };
            if (ft.kind == .lease_expire) {
                s.deadline.store(0, .release);
            } else if (ft.all) {
                srv.lock.lockUncancelable(srv.io);
                defer srv.lock.unlock(srv.io);
                srv.all_faults.add(a, ft) catch {};
            } else s.faults.add(a, ft) catch {};
            return r;
        },
        else => {},
    }
    if (server.takeFault(srv, s, .drop, "execute") != null and r.kind != .begin and r.kind != .commit and r.kind != .rollback) {
        r.drop = true;
        return r;
    }
    if (r.kind == .begin and server.takeFault(srv, s, .drop, "begin") != null) {
        r.drop = true;
        return r;
    }
    if (r.kind == .commit) {
        if (server.takeFault(srv, s, .drop, "before_commit") != null) {
            r.drop = true;
            return r;
        }
        if (server.takeFault(srv, s, .commit_fail, null) != null) {
            s.conn.exec("rollback") catch {};
            r.fail("40000", "the commit failed and the transaction was rolled back (fault injected)");
            return r;
        }
    }
    // faults that name a table or any statement
    for (s.faults.items.items, 0..) |f, i| {
        if (f.kind == .conflict and fault.List.namesTable(sql, f.pointText())) {
            _ = s.faults.items.orderedRemove(i);
            r.fail("40001", "Conflict on update (fault injected)");
            return r;
        }
    }
    if (server.takeFault(srv, s, .deadlock, null) != null) {
        r.fail("40P01", "deadlock detected (fault injected)");
        return r;
    }
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    var exec_sql = rewriteBytea(arena.allocator(), sql) catch sql;
    if (r.kind == .begin) exec_sql = "begin transaction";
    if (r.kind == .rollback) exec_sql = "rollback";
    if (r.kind == .commit) exec_sql = "commit";
    const sql_z = a.dupeZ(u8, exec_sql) catch {
        r.fail("53200", "out of memory");
        return r;
    };
    defer a.free(sql_z);
    var p = s.conn.prepare(sql_z) catch {
        const cls = types.classify(s.conn.err_kind, s.conn.lastError());
        r.fail(sqlState(cls), s.conn.lastError());
        return r;
    };
    defer p.deinit();
    for (params, 1..) |prm, i| bindParam(srv, &p, i, prm) catch {
        r.fail("22023", "a parameter can not be bound");
        return r;
    };
    var res = s.conn.run(&p) catch {
        const cls = types.classify(s.conn.err_kind, s.conn.lastError());
        r.fail(sqlState(cls), s.conn.lastError());
        return r;
    };
    _ = srv.statements.fetchAdd(1, .monotonic);
    if (r.kind == .rows or r.kind == .show) {
        if (res.columnCount() == 0) {
            r.kind = .command;
            res.deinit();
        } else {
            r.cells = cells_mod.Cells.init(a, &res) catch {
                res.deinit();
                r.fail("53200", "out of memory");
                return r;
            };
            r.res = res;
            if (r.cells.?.firstUnsupported() != null) {
                r.deinit();
                r.fail("0A000", "a column has a type that evedb does not send (a list, a struct, a map): cast it to varchar");
                return r;
            }
        }
        server.logStatement(srv, s, sql, if (r.res) |*rr| @intCast(rr.rowCount()) else 0);
    } else {
        r.changed = res.rowsChanged();
        res.deinit();
        server.logStatement(srv, s, sql, @intCast(r.changed));
    }
    return r;
}

// Zig tip: `sendRowDescription` relies on the same Zig feature as `begin` above: see the tip there.
fn sendRowDescription(out: *Out, r: *Run) !void {
    const res = &r.res.?;
    const n = res.columnCount();
    try out.begin('T');
    try out.i16_(@intCast(n));
    for (0..n) |c| {
        try out.cstr(res.columnName(c));
        try out.i32_(0);
        try out.i16_(0);
        const oid = cells_mod.pgOid(r.cells.?.types[c]);
        try out.i32_(@intCast(oid));
        try out.i16_(cells_mod.pgSize(oid));
        try out.i32_(-1);
        try out.i16_(0);
    }
    out.end();
}

// Zig tip: `sendRows` relies on the same Zig feature as `Param` above: see the tip there.
fn sendRows(srv: *Server, out: *Out, r: *Run) !u64 {
    const res = &r.res.?;
    const n = res.columnCount();
    const rows = res.rowCount();
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(srv.gpa);
    for (0..rows) |row| {
        try out.begin('D');
        try out.i16_(@intCast(n));
        for (0..n) |c| {
            text.clearRetainingCapacity();
            const present = try r.cells.?.appendPgText(&text, srv.gpa, c, row);
            if (!present) {
                try out.i32_(-1);
            } else {
                try out.i32_(@intCast(text.items.len));
                try out.raw(text.items);
            }
        }
        out.end();
    }
    return rows;
}

// Zig tip: `showName` relies on the same Zig feature as `kindOf` above: see the tip there.
/// The name of the setting after SHOW.
fn showName(sql: []const u8) []const u8 {
    const t = std.mem.trim(u8, sql, " \t\r\n;");
    return std.mem.trim(u8, t[@min(4, t.len)..], " \t\r\n");
}

// Zig tip: PostgreSQL writes bytes as `'\x0102'::bytea` (hexadecimal digits after `\x`), where DuckDB reads `\x` as the start of one
// escaped byte. The literal is rewritten to `unhex('0102')`, which DuckDB turns into the same bytes. Only that exact shape is
// rewritten; the text is copied as it is otherwise.
/// The SQL with the bytea literals of PostgreSQL written for DuckDB.
fn rewriteBytea(a: std.mem.Allocator, sql: []const u8) ![]const u8 {
    if (std.mem.indexOf(u8, sql, "::bytea") == null) return sql;
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < sql.len) {
        if (sql[i] == '\'' and i + 2 < sql.len and sql[i + 1] == '\\' and sql[i + 2] == 'x') {
            var j = i + 3;
            while (j < sql.len and std.ascii.isHex(sql[j])) j += 1;
            if (j < sql.len and sql[j] == '\'' and std.mem.startsWith(u8, sql[j + 1 ..], "::bytea")) {
                try out.appendSlice(a, "unhex('");
                try out.appendSlice(a, sql[i + 3 .. j]);
                try out.appendSlice(a, "')");
                i = j + 1 + "::bytea".len;
                continue;
            }
        }
        try out.append(a, sql[i]);
        i += 1;
    }
    return out.items;
}

// Zig tip: the result type `?T` is an optional: a value or `null`. The caller must unwrap it (`if (x) |v|`, `orelse`), so a
// missing value can never be used by accident.
// A pretend answer for `show`: the settings that drivers ask after the startup.
fn showValue(name: []const u8) ?[]const u8 {
    const t = [_][2][]const u8{
        .{ "server_version", "16.4" },
        .{ "transaction isolation level", "read committed" },
        .{ "transaction_isolation", "read committed" },
        .{ "standard_conforming_strings", "on" },
        .{ "client_encoding", "UTF8" },
        .{ "server_encoding", "UTF8" },
        .{ "timezone", "UTC" },
        .{ "datestyle", "ISO, MDY" },
        .{ "search_path", "\"$user\", public" },
        .{ "integer_datetimes", "on" },
        .{ "max_identifier_length", "63" },
    };
    for (t) |row| if (std.ascii.eqlIgnoreCase(row[0], name)) return row[1];
    return null;
}

// Zig tip: `reply` relies on the same Zig feature as `begin` above: see the tip there.
/// Send the answer of one statement; the transaction state letter is updated. False when the connection must end.
fn reply(srv: *Server, out: *Out, c: *Conn, sql: []const u8, r: *Run, send_description: bool) !void {
    if (r.drop) return error.Dropped;
    if (r.failed) {
        try errorResponse(out, false, r.err_state, r.message());
        if (c.in_tx) c.failed = true;
        return;
    }
    var tagbuf: [64]u8 = undefined;
    switch (r.kind) {
        .empty => {
            try out.begin('I');
            out.end();
        },
        .fault_pragma => try commandComplete(out, "PRAGMA"),
        .ack => {
            var b0: [24]u8 = undefined;
            var up0: [24]u8 = undefined;
            try commandComplete(out, upper(&up0, word(sql, 0, &b0)));
        },
        .begin => {
            c.in_tx = true;
            c.failed = false;
            try commandComplete(out, "BEGIN");
        },
        .commit => {
            const was_failed = c.failed;
            c.in_tx = false;
            c.failed = false;
            try commandComplete(out, if (was_failed) "ROLLBACK" else "COMMIT");
        },
        .rollback => {
            c.in_tx = false;
            c.failed = false;
            try commandComplete(out, "ROLLBACK");
        },
        .count, .command => try commandComplete(out, commandTag(&tagbuf, sql, r.kind, r.changed)),
        .show => {
            // the setting names come from the text after SHOW
            const rest = showName(sql);
            if (r.res != null) {
                if (send_description) try sendRowDescription(out, r);
                const n = try sendRows(srv, out, r);
                var b: [32]u8 = undefined;
                try commandComplete(out, std.fmt.bufPrint(&b, "SELECT {d}", .{n}) catch "SELECT");
            } else if (showValue(rest)) |v| {
                try out.begin('T');
                try out.i16_(1);
                try out.cstr(rest);
                try out.i32_(0);
                try out.i16_(0);
                try out.i32_(25);
                try out.i16_(-1);
                try out.i32_(-1);
                try out.i16_(0);
                out.end();
                try out.begin('D');
                try out.i16_(1);
                try out.i32_(@intCast(v.len));
                try out.raw(v);
                out.end();
                try commandComplete(out, "SHOW");
            } else {
                try errorResponse(out, false, "42704", "unrecognized configuration parameter");
            }
        },
        .rows => {
            if (send_description) try sendRowDescription(out, r);
            const n = try sendRows(srv, out, r);
            var b: [32]u8 = undefined;
            try commandComplete(out, std.fmt.bufPrint(&b, "SELECT {d}", .{n}) catch "SELECT");
        },
    }
}

// ---------------------------------------------------------------------------------------------------------------- connection

// Zig tip: `Stmt` relies on the same Zig feature as `Out` above: see the tip there.
const Stmt = struct { sql: []u8, oids: []u32 };

// Zig tip: `Portal` relies on the same Zig feature as `Out` above: see the tip there.
const Portal = struct {
    sql: []u8,
    params: []Param,
    /// The result when `Describe` already ran the statement.
    run: ?Run = null,
};

// Zig tip: `Conn` relies on the same Zig feature as `Out` above: see the tip there.
/// The state of one client connection.
const Conn = struct {
    in_tx: bool = false,
    failed: bool = false,
    stmts: std.StringHashMapUnmanaged(Stmt) = .empty,
    portals: std.StringHashMapUnmanaged(Portal) = .empty,
};

// Zig tip: `txState` relies on the same Zig feature as `kindOf` above: see the tip there.
fn txState(c: *const Conn) u8 {
    if (c.failed) return 'E';
    if (c.in_tx) return 'T';
    return 'I';
}

// Zig tip: `freePortal` relies on the same Zig feature as `kindOf` above: see the tip there.
fn freePortal(gpa: std.mem.Allocator, p: *Portal) void {
    gpa.free(p.sql);
    for (p.params) |prm| if (prm.text) |t| gpa.free(t);
    gpa.free(p.params);
    if (p.run) |*r| r.deinit();
}

// Zig tip: `freeConn` relies on the same Zig feature as `kindOf` above: see the tip there.
fn freeConn(gpa: std.mem.Allocator, c: *Conn) void {
    var si = c.stmts.iterator();
    while (si.next()) |e| {
        gpa.free(e.key_ptr.*);
        gpa.free(e.value_ptr.sql);
        gpa.free(e.value_ptr.oids);
    }
    c.stmts.deinit(gpa);
    var pi = c.portals.iterator();
    while (pi.next()) |e| {
        gpa.free(e.key_ptr.*);
        freePortal(gpa, e.value_ptr);
    }
    c.portals.deinit(gpa);
}

// Zig tip: `md5hex` relies on the same Zig feature as `kindOf` above: see the tip there.
fn md5hex(out: *[32]u8, parts: []const []const u8) void {
    var h = std.crypto.hash.Md5.init(.{});
    for (parts) |p| h.update(p);
    var d: [16]u8 = undefined;
    h.final(&d);
    out.* = std.fmt.bytesToHex(d, .lower);
}

// Zig tip: `startup` relies on the same Zig feature as `Param` above: see the tip there.
fn startup(srv: *Server, r: *Io.Reader, w: *Io.Writer, out: *Out) !?struct { db: []const u8, user: []const u8 } {
    const a = srv.gpa;
    while (true) {
        var head: [4]u8 = undefined;
        try r.readSliceAll(&head);
        const len = readI32(&head);
        if (len < 8 or len > 10000) return null;
        const body = try a.alloc(u8, @intCast(len - 4));
        defer a.free(body);
        try r.readSliceAll(body);
        const code = readI32(body[0..4]);
        if (code == 80877103) {
            // SSLRequest: no TLS here
            try w.writeAll("N");
            try w.flush();
            continue;
        }
        if (code == 80877102) return null; // CancelRequest
        if (code != 196608) {
            try errorResponse(out, true, "08P01", "unsupported frontend protocol; evedb speaks 3.0");
            try out.flush(w);
            return null;
        }
        var user: []const u8 = "";
        var db: []const u8 = "";
        var it = std.mem.splitScalar(u8, body[4..], 0);
        while (it.next()) |key| {
            if (key.len == 0) break;
            const val = it.next() orelse break;
            if (std.mem.eql(u8, key, "user")) user = try a.dupe(u8, val);
            if (std.mem.eql(u8, key, "database")) db = try a.dupe(u8, val);
        }
        if (db.len == 0) db = user;
        return .{ .db = db, .user = user };
    }
}

// Zig tip: `authenticate` relies on the same Zig feature as `Param` above: see the tip there.
fn authenticate(srv: *Server, r: *Io.Reader, w: *Io.Writer, out: *Out, user: []const u8) !bool {
    const a = srv.gpa;
    const cfg = srv.cfg;
    if (cfg.auth == .trust) return true;
    if (cfg.user.len > 0 and !std.mem.eql(u8, cfg.user, user)) {
        try errorResponse(out, true, "28000", "role does not exist or the password is wrong");
        try out.flush(w);
        return false;
    }
    var salt: [4]u8 = undefined;
    if (cfg.auth == .password) {
        try out.begin('R');
        try out.i32_(3);
        out.end();
    } else {
        const ns: u64 = @truncate(@as(u96, @bitCast(Io.Timestamp.now(srv.io, .real).toNanoseconds())));
        std.mem.writeInt(u32, &salt, @truncate(ns ^ (ns >> 29) ^ 0x9e3779b9), .big);
        try out.begin('R');
        try out.i32_(5);
        try out.raw(&salt);
        out.end();
    }
    try out.flush(w);
    const m = try readMsg(r, a);
    defer a.free(m.body);
    if (m.kind != 'p') return false;
    const given = std.mem.sliceTo(m.body, 0);
    var ok = false;
    if (cfg.auth == .password) {
        ok = std.mem.eql(u8, given, cfg.password);
    } else {
        var inner: [32]u8 = undefined;
        md5hex(&inner, &.{ cfg.password, user });
        var outer: [32]u8 = undefined;
        md5hex(&outer, &.{ &inner, &salt });
        var want: [35]u8 = undefined;
        @memcpy(want[0..3], "md5");
        @memcpy(want[3..], &outer);
        ok = std.mem.eql(u8, given, &want);
    }
    if (!ok) {
        try errorResponse(out, true, "28P01", "password authentication failed");
        try out.flush(w);
    }
    return ok;
}

// Zig tip: `paramCount` relies on the same Zig feature as `kindOf` above: see the tip there.
fn paramCount(sql: []const u8) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < sql.len) : (i += 1) {
        if (sql[i] == '\'') {
            i += 1;
            while (i < sql.len and sql[i] != '\'') i += 1;
        } else if (sql[i] == '$' and i + 1 < sql.len and std.ascii.isDigit(sql[i + 1])) {
            var j = i + 1;
            var v: usize = 0;
            while (j < sql.len and std.ascii.isDigit(sql[j])) : (j += 1) v = v * 10 + (sql[j] - '0');
            n = @max(n, v);
            i = j - 1;
        }
    }
    return n;
}

// Zig tip: `binaryParam` relies on the same Zig feature as `begin` above: see the tip there.
/// Decode a parameter sent in binary (format 1) into text; integers, floats, booleans and text are understood.
fn binaryParam(gpa: std.mem.Allocator, oid: u32, b: []const u8) ![]u8 {
    switch (oid) {
        21 => if (b.len == 2) return std.fmt.allocPrint(gpa, "{d}", .{readI16(b)}),
        23 => if (b.len == 4) return std.fmt.allocPrint(gpa, "{d}", .{readI32(b)}),
        20 => if (b.len == 8) return std.fmt.allocPrint(gpa, "{d}", .{std.mem.readInt(i64, b[0..8], .big)}),
        700 => if (b.len == 4) return std.fmt.allocPrint(gpa, "{d}", .{@as(f32, @bitCast(std.mem.readInt(u32, b[0..4], .big)))}),
        701 => if (b.len == 8) return std.fmt.allocPrint(gpa, "{d}", .{@as(f64, @bitCast(std.mem.readInt(u64, b[0..8], .big)))}),
        16 => if (b.len == 1) return gpa.dupe(u8, if (b[0] != 0) "t" else "f"),
        25, 1043, 1042, 0 => return gpa.dupe(u8, b),
        else => {},
    }
    return error.BadMessage;
}

// Zig tip: `connection` relies on the same Zig feature as `Param` above: see the tip there.
fn connection(srv: *Server, stream: net.Stream) void {
    defer stream.close(srv.io);
    const a = srv.gpa;
    const rbuf = a.alloc(u8, 64 * 1024) catch return;
    defer a.free(rbuf);
    var reader = stream.reader(srv.io, rbuf);
    var wbuf: [16 * 1024]u8 = undefined;
    var writer = stream.writer(srv.io, &wbuf);
    const r = &reader.interface;
    const w = &writer.interface;
    var out: Out = .{ .gpa = a };
    defer out.deinit();
    const su = (startup(srv, r, w, &out) catch return) orelse return;
    if (!(authenticate(srv, r, w, &out, su.user) catch return)) return;
    // the database: the name the client asked for
    const d = server.openDbPg(srv, su.db) catch {
        errorResponse(&out, true, "3D000", "database does not exist") catch return;
        out.flush(w) catch {};
        return;
    };
    const s = server.newSession(srv, d) catch return;
    defer {
        s.busy.lockUncancelable(srv.io);
        server.closeSession(srv, s);
        s.busy.unlock(srv.io);
    }
    // the welcome
    out.begin('R') catch return;
    out.i32_(0) catch return;
    out.end();
    const params = [_][2][]const u8{
        .{ "server_version", "16.4 (evedb 0.2 on DuckDB)" },
        .{ "server_encoding", "UTF8" },
        .{ "client_encoding", "UTF8" },
        .{ "DateStyle", "ISO, MDY" },
        .{ "integer_datetimes", "on" },
        .{ "standard_conforming_strings", "on" },
        .{ "TimeZone", "UTC" },
        .{ "is_superuser", "on" },
        .{ "session_authorization", "evedb" },
    };
    for (params) |p| parameterStatus(&out, p[0], p[1]) catch return;
    out.begin('K') catch return;
    out.i32_(@intCast(s.id)) catch return;
    out.i32_(@intCast(s.id *% 2654435761 & 0x7fffffff)) catch return;
    out.end();
    readyForQuery(&out, 'I') catch return;
    out.flush(w) catch return;

    var conn: Conn = .{};
    defer freeConn(a, &conn);
    var skip_until_sync = false;
    while (!srv.stopping.load(.acquire)) {
        const m = readMsg(r, a) catch return;
        defer a.free(m.body);
        s.busy.lockUncancelable(srv.io);
        defer s.busy.unlock(srv.io);
        if (s.closed) {
            errorResponse(&out, true, "57P01", "the session was closed (lease ran out)") catch return;
            out.flush(w) catch {};
            return;
        }
        s.deadline.store(srv.now() + srv.cfg.lease_ms, .release);
        if (s.faults.peek(.delay)) |dl| Io.sleep(srv.io, .fromMilliseconds(dl.arg), .awake) catch {};
        // a Terminate, a dropped connection (fault), a bad message or a write that failed all end the connection
        handleMessage(srv, s, &conn, &out, m, &skip_until_sync) catch return;
        out.flush(w) catch return;
    }
}

// Zig tip: `handleMessage` relies on the same Zig feature as `Param` above: see the tip there.
fn handleMessage(srv: *Server, s: *Session, c: *Conn, out: *Out, m: Msg, skip: *bool) !void {
    const a = srv.gpa;
    if (skip.* and m.kind != 'S' and m.kind != 'X') return; // after an error the extended messages are skipped up to Sync
    switch (m.kind) {
        'X' => return error.Terminate,
        'Q' => {
            const text = std.mem.sliceTo(m.body, 0);
            const stmts = try splitStatements(a, text);
            defer a.free(stmts);
            var any = false;
            for (stmts) |st| {
                const t = std.mem.trim(u8, st, " \t\r\n");
                if (t.len == 0) continue;
                any = true;
                if (c.failed and kindOf(t) != .rollback and kindOf(t) != .commit) {
                    try errorResponse(out, false, "25P02", "current transaction is aborted, commands ignored until end of transaction block");
                    break;
                }
                var run = runStatement(srv, s, t, &.{});
                defer run.deinit();
                try reply(srv, out, c, t, &run, true);
                if (run.failed) break;
                // a drop after the commit: the commit is real, the answer is not sent
                if (run.kind == .commit and server.takeFault(srv, s, .drop, "after_commit") != null) return error.Dropped;
            }
            if (!any) {
                try out.begin('I');
                out.end();
            }
            try readyForQuery(out, txState(c));
        },
        'P' => {
            // Parse: statement name, query, parameter types
            var cur = std.mem.splitScalar(u8, m.body, 0);
            const name = cur.next() orelse return error.BadMessage;
            const query = cur.next() orelse return error.BadMessage;
            const consumed = name.len + 1 + query.len + 1;
            if (m.body.len < consumed + 2) return error.BadMessage;
            const nt: usize = @intCast(readI16(m.body[consumed..]));
            const n = @max(nt, paramCount(query));
            const oids = try a.alloc(u32, n);
            @memset(oids, 0);
            for (0..nt) |i| oids[i] = @intCast(readI32(m.body[consumed + 2 + 4 * i ..]));
            const key = try a.dupe(u8, name);
            const sql = try a.dupe(u8, query);
            if (c.stmts.fetchRemove(name)) |old| {
                a.free(old.key);
                a.free(old.value.sql);
                a.free(old.value.oids);
            }
            try c.stmts.put(a, key, .{ .sql = sql, .oids = oids });
            try out.begin('1');
            out.end();
        },
        'B' => try handleBind(srv, c, out, m, a),
        'D' => {
            const kind = m.body[0];
            const name = std.mem.sliceTo(m.body[1..], 0);
            if (kind == 'S') {
                const st = c.stmts.get(name) orelse {
                    try errorResponse(out, false, "26000", "prepared statement does not exist");
                    skip.* = true;
                    return;
                };
                try out.begin('t');
                try out.i16_(@intCast(st.oids.len));
                for (st.oids) |o| try out.i32_(@intCast(if (o == 0) 25 else o));
                out.end();
                // the columns: ask DuckDB to prepare the statement
                const z = try a.dupeZ(u8, st.sql);
                defer a.free(z);
                var p = s.conn.prepare(z) catch {
                    try out.begin('n');
                    out.end();
                    return;
                };
                defer p.deinit();
                const ncol = p.columnCount();
                const k = kindOf(st.sql);
                if (ncol == 0 or (k != .rows and k != .show)) {
                    try out.begin('n');
                    out.end();
                } else {
                    try out.begin('T');
                    try out.i16_(@intCast(ncol));
                    for (0..ncol) |i| {
                        try out.cstr(p.columnName(i));
                        try out.i32_(0);
                        try out.i16_(0);
                        const oid = cells_mod.pgOid(p.columnType(i));
                        try out.i32_(@intCast(oid));
                        try out.i16_(cells_mod.pgSize(oid));
                        try out.i32_(-1);
                        try out.i16_(0);
                    }
                    out.end();
                }
            } else {
                const pt = c.portals.getPtr(name) orelse {
                    try errorResponse(out, false, "34000", "portal does not exist");
                    skip.* = true;
                    return;
                };
                if (pt.run == null) pt.run = runStatement(srv, s, pt.sql, pt.params);
                const rr = &pt.run.?;
                if (rr.failed) {
                    try errorResponse(out, false, rr.err_state, rr.message());
                    if (c.in_tx) c.failed = true;
                    skip.* = true;
                    return;
                }
                if (rr.drop) return error.Dropped;
                if (rr.res != null and (rr.kind == .rows or rr.kind == .show)) {
                    try sendRowDescription(out, rr);
                } else {
                    try out.begin('n');
                    out.end();
                }
            }
        },
        'E' => {
            const name = std.mem.sliceTo(m.body, 0);
            const pt = c.portals.getPtr(name) orelse {
                try errorResponse(out, false, "34000", "portal does not exist");
                skip.* = true;
                return;
            };
            if (pt.run == null) pt.run = runStatement(srv, s, pt.sql, pt.params);
            const rr = &pt.run.?;
            // the answer was sent at Describe time as a description; the rows and the tag go now
            if (c.failed and rr.kind != .rollback and rr.kind != .commit) {
                try errorResponse(out, false, "25P02", "current transaction is aborted, commands ignored until end of transaction block");
                skip.* = true;
                return;
            }
            try reply(srv, out, c, pt.sql, rr, false);
            if (rr.failed) skip.* = true;
            if (rr.kind == .commit and !rr.failed and server.takeFault(srv, s, .drop, "after_commit") != null) return error.Dropped;
            rr.deinit();
            pt.run = .{ .kind = .ack };
            pt.run.?.failed = false;
        },
        'C' => {
            const kind = m.body[0];
            const name = std.mem.sliceTo(m.body[1..], 0);
            if (kind == 'S') {
                if (c.stmts.fetchRemove(name)) |old| {
                    a.free(old.key);
                    a.free(old.value.sql);
                    a.free(old.value.oids);
                }
            } else if (c.portals.fetchRemove(name)) |old| {
                a.free(old.key);
                var v = old.value;
                freePortal(a, &v);
            }
            try out.begin('3');
            out.end();
        },
        'S' => {
            skip.* = false;
            try readyForQuery(out, txState(c));
        },
        'H' => {},
        else => {
            try errorResponse(out, false, "0A000", "this message type is not supported by evedb");
            try readyForQuery(out, txState(c));
        },
    }
}

// Zig tip: `handleBind` relies on the same Zig feature as `Msg` above: see the tip there.
fn handleBind(srv: *Server, c: *Conn, out: *Out, m: Msg, a: std.mem.Allocator) !void {
    _ = srv;
    var pos: usize = 0;
    const portal_name = std.mem.sliceTo(m.body, 0);
    pos += portal_name.len + 1;
    const stmt_name = std.mem.sliceTo(m.body[pos..], 0);
    pos += stmt_name.len + 1;
    const st = c.stmts.get(stmt_name) orelse {
        try errorResponse(out, false, "26000", "prepared statement does not exist");
        return;
    };
    const nfmt: usize = @intCast(readI16(m.body[pos..]));
    pos += 2;
    const fmts = try a.alloc(i16, nfmt);
    defer a.free(fmts);
    for (0..nfmt) |i| {
        fmts[i] = readI16(m.body[pos..]);
        pos += 2;
    }
    const np: usize = @intCast(readI16(m.body[pos..]));
    pos += 2;
    const prms = try a.alloc(Param, np);
    var made: usize = 0;
    errdefer {
        for (prms[0..made]) |prm| if (prm.text) |t| a.free(t);
        a.free(prms);
    }
    for (0..np) |i| {
        const len = readI32(m.body[pos..]);
        pos += 4;
        const oid: u32 = if (i < st.oids.len) st.oids[i] else 0;
        if (len < 0) {
            prms[i] = .{ .text = null, .oid = oid };
        } else {
            const raw = m.body[pos .. pos + @as(usize, @intCast(len))];
            pos += @intCast(len);
            const f: i16 = if (nfmt == 0) 0 else if (nfmt == 1) fmts[0] else fmts[i];
            const text = if (f == 1) try binaryParam(a, oid, raw) else try a.dupe(u8, raw);
            prms[i] = .{ .text = text, .oid = oid };
        }
        made += 1;
    }
    const key = try a.dupe(u8, portal_name);
    const sql = try a.dupe(u8, st.sql);
    if (c.portals.fetchRemove(portal_name)) |old| {
        a.free(old.key);
        var v = old.value;
        freePortal(a, &v);
    }
    try c.portals.put(a, key, .{ .sql = sql, .params = prms });
    try out.begin('2');
    out.end();
}

// Zig tip: `switch` must cover every value of what it tests (or have `else`); the compiler checks it, so a new case can not
// be forgotten. A prong can be an expression that gives the result.
/// The accept loop of the PostgreSQL port: one thread for each client, until the server stops.
pub fn acceptLoop(srv: *Server) void {
    while (true) {
        const stream = srv.pg_listener.?.accept(srv.io) catch |e| switch (e) {
            error.SocketNotListening => break,
            else => continue,
        };
        if (srv.stopping.load(.acquire)) {
            stream.close(srv.io);
            break;
        }
        const t = std.Thread.spawn(.{}, connection, .{ srv, stream }) catch {
            stream.close(srv.io);
            continue;
        };
        t.detach();
    }
    srv.pg_listener.?.deinit(srv.io);
}

// Zig tip: a `test` block is compiled only by `zig build test`; `try std.testing.expect…` fails the test, with the values,
// when a check is false.
test "statements are split outside quotes and comments" {
    const gpa = std.testing.allocator;
    const parts = try splitStatements(gpa, "select 'a;b'; -- x; y\nselect 2; select $$c;d$$");
    defer gpa.free(parts);
    try std.testing.expectEqual(@as(usize, 3), parts.len);
}

// Zig tip: test "the kind of a statement" relies on the same Zig feature as test "statements are split outside quotes and
// comments" above: see the tip there.
test "the kind of a statement" {
    try std.testing.expectEqual(Kind.count, kindOf("insert into t values (1)"));
    try std.testing.expectEqual(Kind.rows, kindOf("insert into t values (1) returning id"));
    try std.testing.expectEqual(Kind.command, kindOf("CREATE TABLE t (id int)"));
    try std.testing.expectEqual(Kind.ack, kindOf("set extra_float_digits = 3"));
    try std.testing.expectEqual(Kind.begin, kindOf("BEGIN"));
    try std.testing.expectEqual(Kind.rows, kindOf("with x as (select 1) select * from x"));
    try std.testing.expectEqual(Kind.fault_pragma, kindOf("pragma eve_fault('drop', 'begin')"));
}

// Zig tip: test "a bytea literal of PostgreSQL is rewritten for DuckDB" relies on the same Zig feature as test "statements
// are split outside quotes and comments" above: see the tip there.
test "a bytea literal of PostgreSQL is rewritten for DuckDB" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("insert into t values (1, unhex('0102'))", try rewriteBytea(arena.allocator(), "insert into t values (1, '\\x0102'::bytea)"));
    try std.testing.expectEqualStrings("select 1", try rewriteBytea(arena.allocator(), "select 1"));
}

// Zig tip: test "command tags" relies on the same Zig feature as test "statements are split outside quotes and comments"
// above: see the tip there.
test "command tags" {
    var b: [64]u8 = undefined;
    try std.testing.expectEqualStrings("INSERT 0 3", commandTag(&b, "insert into t values (1)", .count, 3));
    try std.testing.expectEqualStrings("DELETE 2", commandTag(&b, "delete from t", .count, 2));
    try std.testing.expectEqualStrings("CREATE TABLE", commandTag(&b, "create table t (a int)", .command, 0));
    try std.testing.expectEqual(@as(usize, 3), paramCount("select $1, '$9', $3, $2"));
}
