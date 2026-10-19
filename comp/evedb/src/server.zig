//! The evedb server (README.md sections 4 to 8): the listener, the frame loop of a connection, sessions with leases,
//! transactions with `eve_tx`, faults and the statement log.
const std = @import("std");
const Io = std.Io;
const net = Io.net;
const duckdb = @import("duckdb.zig");
const ewp = @import("ewp.zig");
const types = @import("types.zig");
const cells_mod = @import("cells.zig");
const fault = @import("fault.zig");
const batch = @import("batch.zig");
const pgserver = @import("pgserver.zig");

// Zig tip: a `struct` groups named fields, and may hold functions (its methods) and constants; a field with a default value
// may be left out when a value is made with `.{ ... }`.
/// One database of the configuration file: the name a PostgreSQL client asks for, and the file.
pub const DbMap = struct { name: []const u8, path: []const u8 };

// Zig tip: `Config` relies on the same Zig feature as `DbMap` above: see the tip there.
/// How the server was started.
pub const Config = struct {
    host: []const u8 = "127.0.0.1",
    /// The port of the EWP-db frames (0 asks the system; `ewp` false switches it off).
    port: u16 = 8044,
    ewp: bool = true,
    /// The PostgreSQL port (README.md section 5A): 5432 is the port of PostgreSQL; 0 asks the system; `pg` false switches it off.
    pg: bool = true,
    pg_port: u16 = 5432,
    data_dir: []const u8 = "data",
    test_mode: bool = false,
    lease_ms: u32 = 30_000,
    token: []const u8 = "",
    /// The login of the PostgreSQL port: the user, the password and how the password is asked ("trust": not at all).
    user: []const u8 = "",
    password: []const u8 = "",
    auth: @import("pgserver.zig").Auth = .trust,
    /// The databases of the configuration file; when the list is empty, a name is the file `<data_dir>/<name>.duckdb`.
    databases: []const DbMap = &.{},
};

// Zig tip: `Db` relies on the same Zig feature as `DbMap` above: see the tip there.
/// One database file that is open, with the connection that writes the statement log.
pub const Db = struct {
    name: []u8,
    db: duckdb.Database,
    log_conn: duckdb.Connection,
    log_lock: Io.Mutex = .init,
    seq: u64 = 0,
};

// Zig tip: a session is plain data guarded by two things: `busy` (a mutex held by the thread that handles a frame of this
// session, so the reaper never closes the DuckDB connection under its feet) and the atomic `deadline` (read by the reaper
// without the mutex). `closed` is set when the connection of DuckDB is gone, and every later frame answers `LeaseExpired`.
/// One client session.
pub const Session = struct {
    id: u64,
    db: *Db,
    conn: duckdb.Connection,
    tx: ?[16]u8 = null,
    deadline: std.atomic.Value(i64),
    busy: Io.Mutex = .init,
    closed: bool = false,
    expired: bool = false,
    faults: fault.List = .{},
};

// Zig tip: `Server` relies on the same Zig feature as `DbMap` above: see the tip there.
pub const Server = struct {
    gpa: std.mem.Allocator,
    io: Io,
    cfg: Config,
    lock: Io.Mutex = .init,
    dbs: std.StringHashMapUnmanaged(*Db) = .empty,
    sessions: std.AutoHashMapUnmanaged(u64, *Session) = .empty,
    /// The faults of scope all.
    all_faults: fault.List = .{},
    /// The transactions that are open now (their ids), for `STATUS`.
    open_tx: std.ArrayList([16]u8) = .empty,
    next_id: u64 = 1,
    statements: std.atomic.Value(u64) = .init(0),
    stopping: std.atomic.Value(bool) = .init(false),
    listener: ?net.Server = null,
    pg_listener: ?net.Server = null,
    pg_bound_port: u16 = 0,
    /// The port that was bound (the system chooses it when the configuration says 0).
    bound_port: u16 = 0,
    started: i64 = 0,

    // Zig tip: a function declared inside a struct whose first parameter is the struct (`self: *T`) is a method: `x.f()`
    // calls `f(&x)`.
    pub fn now(self: *const Server) i64 {
        return Io.Timestamp.now(self.io, .awake).toMilliseconds();
    }
};

// ---------------------------------------------------------------------------------------------------------------- helpers

// Zig tip: `defer` runs its statement when the scope ends, by any path (a `return`, an error, the end of the block), so a
// free or a close is written once, next to what it undoes.
fn sendError(w: *Io.Writer, stream: u32, class: []const u8, state: []const u8, transient: bool, msg: []const u8) void {
    var b = ewp.Builder.init(std.heap.page_allocator);
    defer b.deinit();
    b.string(class) catch return;
    b.string(state) catch return;
    b.u8_(@intFromBool(transient)) catch return;
    b.string(msg) catch return;
    ewp.writeFrame(w, .err, stream, b.buf.items) catch {};
}

// Zig tip: the result type `!T` (or `Error!T`) is an error union: a value or an error. `try f()` passes the error to the
// caller; `f() catch …` handles it in place.
fn sendOk(w: *Io.Writer, stream: u32) !void {
    try ewp.writeFrame(w, .ok, stream, "");
}

// Zig tip: a plain function: the types of the parameters and of the result are written out, and Zig has no default
// arguments, so a call always passes every parameter.
/// A database name is letters, digits and `_`: no name can leave the data folder.
pub fn validName(name: []const u8) bool {
    if (name.len == 0 or name.len > 64) return false;
    for (name) |ch| if (!(std.ascii.isAlphanumeric(ch) or ch == '_')) return false;
    return true;
}

// Zig tip: `for (a, b) |x, y|` walks two slices of the same length side by side (`0..` gives the index); the lengths are
// checked in safe builds.
fn constantTimeEql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var diff: u8 = 0;
    for (a, b) |x, y| diff |= x ^ y;
    return diff == 0;
}

// Zig tip: the first keyword of a statement names its kind, and the first word after `into`, `update`, `from` or `table`
// names the table; both are cut from the text without parsing SQL, which is enough for a log that a test reads.
fn statementKind(sql: []const u8) []const u8 {
    const t = std.mem.trimStart(u8, sql, " \t\r\n(");
    var end: usize = 0;
    while (end < t.len and std.ascii.isAlphabetic(t[end])) end += 1;
    return t[0..end];
}

// Zig tip: `a orelse b` unwraps an optional: the value when there is one, else `b` (which may be `return` or `continue`,
// leaving the function or the loop).
fn statementTable(buf: []u8, sql: []const u8) []const u8 {
    const words = [_][]const u8{ "into ", "update ", "from ", "table " };
    var best: ?usize = null;
    for (words) |w| {
        var i: usize = 0;
        while (i + w.len <= sql.len) : (i += 1) {
            if (std.ascii.eqlIgnoreCase(sql[i .. i + w.len], w) and (i == 0 or !std.ascii.isAlphanumeric(sql[i - 1]))) {
                const at = i + w.len;
                if (best == null or at < best.?) best = at;
                break;
            }
        }
    }
    const start = best orelse return "";
    var s = start;
    while (s < sql.len and (sql[s] == ' ' or sql[s] == '"')) s += 1;
    var e = s;
    while (e < sql.len and (std.ascii.isAlphanumeric(sql[e]) or sql[e] == '_' or sql[e] == '.')) e += 1;
    const n = @min(e - s, buf.len);
    for (sql[s..][0..n], 0..) |ch, k| buf[k] = std.ascii.toLower(ch);
    return buf[0..n];
}

// ---------------------------------------------------------------------------------------------------------------- databases

// Zig tip: with a configuration file the names a client may ask for are the ones listed in it; each has its own file. Without
// one a name is a file of the data folder. `openDbPg` is for the PostgreSQL port: an unknown name is an error (the client gets
// `database does not exist`), where the frames of EWP-db create the file in test mode.
/// Open (once) the database a PostgreSQL client asked for.
pub fn openDbPg(srv: *Server, name: []const u8) !*Db {
    if (srv.cfg.databases.len > 0) {
        for (srv.cfg.databases) |m| {
            if (std.mem.eql(u8, m.name, name)) {
                const z = try srv.gpa.dupeSentinel(u8, m.path, 0);
                defer srv.gpa.free(z);
                return openDbAt(srv, m.name, z);
            }
        }
        return error.NoSuchDatabase;
    }
    if (!validName(name)) return error.NoSuchDatabase;
    if (!srv.cfg.test_mode) {
        const path = try dbPath(srv, name);
        defer srv.gpa.free(path);
        Io.Dir.cwd().access(srv.io, path, .{}) catch return error.NoSuchDatabase;
    }
    return openDb(srv, name);
}

// Zig tip: `dbPath` relies on the same Zig feature as `sendOk` above: see the tip there.
fn dbPath(srv: *Server, name: []const u8) ![:0]u8 {
    return std.fmt.allocPrintSentinel(srv.gpa, "{s}/{s}.duckdb", .{ srv.cfg.data_dir, name }, 0);
}

// Zig tip: a database is opened once, on its first `OPEN`, and kept for the life of the server. `getOrPut` finds the entry
// or makes the place for it. The tables every database has (`eve_tx`, and in test mode the schema `eve_log`) are made here,
// on the connection that also writes the statement log.
fn openDb(srv: *Server, name: []const u8) !*Db {
    const path = try dbPath(srv, name);
    defer srv.gpa.free(path);
    return openDbAt(srv, name, path);
}

// Zig tip: `errdefer` runs its statement only when the function leaves with an error, so what was made before the failure
// is freed and nothing leaks; on success it does nothing.
fn openDbAt(srv: *Server, name: []const u8, path: [:0]const u8) !*Db {
    srv.lock.lockUncancelable(srv.io);
    defer srv.lock.unlock(srv.io);
    if (srv.dbs.get(name)) |d| return d;
    if (std.fs.path.dirname(path)) |dir| Io.Dir.cwd().createDirPath(srv.io, dir) catch {};
    const d = try srv.gpa.create(Db);
    errdefer srv.gpa.destroy(d);
    d.* = .{ .name = try srv.gpa.dupe(u8, name), .db = try duckdb.Database.open(path), .log_conn = undefined };
    errdefer d.db.close();
    d.log_conn = try d.db.connect();
    errdefer d.log_conn.close();
    try d.log_conn.exec("create table if not exists eve_tx (id varchar primary key, committed timestamp)");
    if (srv.cfg.test_mode) {
        try d.log_conn.exec("create schema if not exists eve_log");
        try d.log_conn.exec("create table if not exists eve_log.statements (session bigint, tx varchar, seq bigint, kind varchar, tbl varchar, rows bigint, sql varchar, ts timestamp)");
        const row = d.log_conn.query("select coalesce(max(seq), 0) from eve_log.statements") catch null;
        if (row) |r| {
            var rr = r;
            d.seq = @intCast(rr.int(0, 0));
            rr.deinit();
        }
    }
    try srv.dbs.put(srv.gpa, d.name, d);
    return d;
}

// Zig tip: the log is written on its own connection, so the line stays when the transaction of the session rolls back: a
// test wants to see what was *sent*. The statement is a prepared one with parameters, so the SQL text of the client cannot
// break the log statement. A failure to log is ignored: logging must never fail a request.
pub fn logStatement(srv: *Server, s: *Session, sql: []const u8, rows: i64) void {
    if (!srv.cfg.test_mode) return;
    const d = s.db;
    d.log_lock.lockUncancelable(srv.io);
    defer d.log_lock.unlock(srv.io);
    d.seq += 1;
    var tb: [96]u8 = undefined;
    const tbl = statementTable(&tb, sql);
    var txbuf: [40]u8 = undefined;
    const tx: []const u8 = if (s.tx) |id| std.fmt.bufPrint(&txbuf, "{x}", .{id}) catch "" else "";
    var p = d.log_conn.prepare("insert into eve_log.statements values (?, ?, ?, ?, ?, ?, ?, now())") catch return;
    defer p.deinit();
    const a = srv.gpa;
    const tx_z = a.dupeSentinel(u8, tx, 0) catch return;
    defer a.free(tx_z);
    const kind_z = a.dupeSentinel(u8, statementKind(sql), 0) catch return;
    defer a.free(kind_z);
    const tbl_z = a.dupeSentinel(u8, tbl, 0) catch return;
    defer a.free(tbl_z);
    const sql_z = a.dupeSentinel(u8, sql, 0) catch return;
    defer a.free(sql_z);
    p.bindInt(1, @intCast(s.id)) catch return;
    p.bindText(2, tx_z) catch return;
    p.bindInt(3, @intCast(d.seq)) catch return;
    p.bindText(4, kind_z) catch return;
    p.bindText(5, tbl_z) catch return;
    p.bindInt(6, rows) catch return;
    p.bindText(7, sql_z) catch return;
    var r = d.log_conn.run(&p) catch return;
    r.deinit();
}

// ---------------------------------------------------------------------------------------------------------------- sessions

// Zig tip: `newSession` relies on the same Zig feature as `openDbAt` above: see the tip there.
pub fn newSession(srv: *Server, d: *Db) !*Session {
    const s = try srv.gpa.create(Session);
    errdefer srv.gpa.destroy(s);
    s.* = .{ .id = 0, .db = d, .conn = try d.db.connect(), .deadline = .init(srv.now() + srv.cfg.lease_ms) };
    srv.lock.lockUncancelable(srv.io);
    defer srv.lock.unlock(srv.io);
    s.id = srv.next_id;
    srv.next_id += 1;
    try srv.sessions.put(srv.gpa, s.id, s);
    return s;
}

// Zig tip: `forgetTx` relies on the same Zig feature as `sendError` above: see the tip there.
fn forgetTx(srv: *Server, id: [16]u8) void {
    srv.lock.lockUncancelable(srv.io);
    defer srv.lock.unlock(srv.io);
    for (srv.open_tx.items, 0..) |t, i| {
        if (std.mem.eql(u8, &t, &id)) {
            _ = srv.open_tx.swapRemove(i);
            return;
        }
    }
}

// Zig tip: closing a session rolls back what is open (a DuckDB connection that is closed with a transaction open rolls it
// back too, but doing it explicitly keeps the list of open transactions right), closes the DuckDB connection and takes the
// session out of the table. The caller holds `busy`.
pub fn closeSession(srv: *Server, s: *Session) void {
    if (!s.closed) {
        if (s.tx) |id| {
            s.conn.exec("rollback") catch {};
            forgetTx(srv, id);
            s.tx = null;
        }
        s.conn.close();
        s.closed = true;
    }
    srv.lock.lockUncancelable(srv.io);
    _ = srv.sessions.remove(s.id);
    srv.lock.unlock(srv.io);
}

// Zig tip: `reaper` relies on the same Zig feature as `sendError` above: see the tip there.
// ---------------------------------------------------------------------------------------------------------------- batches

// Zig tip: a query of the columnar path sends three kinds of frames on one stream: the schema, one batch for each data chunk
// of DuckDB, and the end with the number of rows. The client reads until the end; nothing has to be held for the whole
// result on either side but one chunk.
/// `QUERYB`: run the statement and send its result as column batches (section 5.5).
fn handleQueryB(srv: *Server, s: *Session, w: *Io.Writer, f: ewp.Frame) !Outcome {
    const a = srv.gpa;
    var c: ewp.Cursor = .{ .buf = f.payload };
    const sql = try c.string();
    const params = try readParams(&c, a);
    defer a.free(params);
    _ = c.u32_() catch 0; // the batch size the client would like: DuckDB's chunks decide in this version
    var res: duckdb.Result = undefined;
    if (!runStatement(srv, s, w, f.stream, sql, params, &res)) return .go_on;
    defer res.deinit();
    var cells = cells_mod.Cells.init(a, &res) catch {
        sendError(w, f.stream, "DatabaseError", "HY001", false, "out of memory");
        return .go_on;
    };
    defer cells.deinit();
    if (cells.firstUnsupported()) |k| {
        var msg: [200]u8 = undefined;
        const text = std.fmt.bufPrint(&msg, "column {s} has a type that evedb does not send (a list, a struct, a map): cast it to varchar", .{res.columnName(k)}) catch "a column has a type that evedb does not send";
        sendError(w, f.stream, "DatabaseError", "0A000", false, text);
        return .go_on;
    }
    var b = ewp.Builder.init(a);
    defer b.deinit();
    const heads = try a.alloc(batch.Head, cells.ncols);
    defer a.free(heads);
    for (heads, 0..) |*h, k| h.* = .{ .name = res.columnName(k), .wire = cells.wireOf(k) };
    try batch.writeSchema(&b, heads);
    try ewp.writeFrame(w, .schema, f.stream, b.buf.items);
    var total: u64 = 0;
    for (0..cells.chunkCount()) |ci| {
        b.buf.clearRetainingCapacity();
        try cells.encodeChunk(&b, ci);
        try ewp.writeFrame(w, .batch, f.stream, b.buf.items);
        total += cells.chunkRows(ci);
    }
    b.buf.clearRetainingCapacity();
    try b.u64_(total);
    try ewp.writeFrame(w, .end, f.stream, b.buf.items);
    logStatement(srv, s, sql, @intCast(total));
    return .go_on;
}

// Zig tip: `switch` must cover every value of what it tests (or have `else`); the compiler checks it, so a new case can not
// be forgotten. A prong can be an expression that gives the result.
fn sqlType(wire: batch.Wire) []const u8 {
    return switch (wire) {
        .boolean => "BOOLEAN",
        .int => "BIGINT",
        .real => "DOUBLE",
        .text => "VARCHAR",
        .date => "DATE",
        .timestamp => "TIMESTAMP",
        .decimal => "DECIMAL(38, 10)",
        .blob => "BLOB",
    };
}

// Zig tip: `quoteName` relies on the same Zig feature as `sendOk` above: see the tip there.
fn quoteName(out: *std.ArrayList(u8), a: std.mem.Allocator, name: []const u8) !void {
    try out.append(a, '"');
    for (name) |ch| {
        if (ch == '"') try out.append(a, '"');
        try out.append(a, ch);
    }
    try out.append(a, '"');
}

// Zig tip: a load is a conversation of many frames: the head (the table and its columns), the batches, the end. They come
// pipelined, without waiting for an answer, and the server answers once, at the end. After a failure the following batches
// are read and dropped, so the stream stays in step; the answer is then the error. The values go into DuckDB through the
// Appender (no SQL for each row), in the transaction of the session.
/// `LOAD`: append the column batches that follow to a table (made first when the head asks for it).
fn handleLoad(srv: *Server, s: *Session, r: *Io.Reader, w: *Io.Writer, f: ewp.Frame) !Outcome {
    const a = srv.gpa;
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    const aa = arena.allocator();
    var c: ewp.Cursor = .{ .buf = f.payload };
    const table = try c.string();
    const create = try c.u8_();
    const heads = try batch.readSchema(&c, aa);
    var failed = false;
    var err_class: []const u8 = "DatabaseError";
    var err_state: []const u8 = "HY000";
    var err_msg: std.ArrayList(u8) = .empty;
    if (!validName(table)) {
        failed = true;
        err_class = "ProtocolError";
        err_state = "42602";
        try err_msg.appendSlice(aa, "a table name is letters, digits and _");
    }
    if (!failed and create == 1) {
        var sql: std.ArrayList(u8) = .empty;
        try sql.appendSlice(aa, "create table ");
        try quoteName(&sql, aa, table);
        try sql.appendSlice(aa, " (");
        for (heads, 0..) |h, k| {
            if (k > 0) try sql.appendSlice(aa, ", ");
            try quoteName(&sql, aa, h.name);
            try sql.append(aa, ' ');
            try sql.appendSlice(aa, sqlType(h.wire));
        }
        try sql.append(aa, ')');
        s.conn.exec(try aa.dupeSentinel(u8, sql.items, 0)) catch {
            failed = true;
            const cls = types.classify(s.conn.err_kind, s.conn.lastError());
            err_class = cls.name;
            err_state = cls.state;
            try err_msg.appendSlice(aa, s.conn.lastError());
        };
    }
    var app: ?duckdb.Appender = null;
    if (!failed) {
        app = duckdb.Appender.create(&s.conn, try aa.dupeSentinel(u8, table, 0)) catch blk: {
            failed = true;
            try err_msg.appendSlice(aa, s.conn.lastError());
            break :blk null;
        };
    }
    defer if (app) |*ap| ap.deinit();
    var total: u64 = 0;
    while (true) {
        const g = ewp.readFrame(r, a) catch return .drop;
        defer ewp.freeFrame(a, g);
        if (g.kind == .end) break;
        if (g.kind != .batch or g.stream != f.stream) {
            sendError(w, f.stream, "ProtocolError", "08P01", false, "a load is followed by batches and an end");
            return .drop;
        }
        if (failed) continue;
        var bc: ewp.Cursor = .{ .buf = g.payload };
        var frame_arena: std.heap.ArenaAllocator = .init(a);
        defer frame_arena.deinit();
        const got = batch.readBatch(&bc, frame_arena.allocator(), heads) catch {
            failed = true;
            err_class = "ProtocolError";
            err_state = "08P01";
            try err_msg.appendSlice(aa, "a batch does not match the columns of the load");
            continue;
        };
        const ap = &app.?;
        var row: usize = 0;
        rows: while (row < got.rows) : (row += 1) {
            for (heads, got.views) |h, v| {
                const ok = if (!v.isValid(row)) ap.appendNull() else switch (h.wire) {
                    .boolean => ap.appendBool(v.boolean(row)),
                    .int => ap.appendInt(v.int(row)),
                    .real => ap.appendReal(v.real(row)),
                    .date => ap.appendDate(@intCast(v.int(row))),
                    .timestamp => ap.appendTimestamp(v.int(row)),
                    .text, .decimal => ap.appendText(v.text(row)),
                    .blob => ap.appendBlob(v.text(row)),
                };
                ok catch {
                    failed = true;
                    try err_msg.appendSlice(aa, ap.lastError());
                    break :rows;
                };
            }
            ap.endRow() catch {
                failed = true;
                try err_msg.appendSlice(aa, ap.lastError());
                break :rows;
            };
        }
        if (!failed) total += got.rows;
    }
    if (!failed) {
        if (app) |*ap| ap.flush() catch {
            failed = true;
            try err_msg.appendSlice(aa, ap.lastError());
        };
    }
    if (failed) {
        const first = if (std.mem.indexOfScalar(u8, err_msg.items, '\n')) |nl| err_msg.items[0..nl] else err_msg.items;
        sendError(w, f.stream, err_class, err_state, false, first);
        return .go_on;
    }
    _ = srv.statements.fetchAdd(1, .monotonic);
    const what = try std.fmt.allocPrint(aa, "load into {s}: {d} rows", .{ table, total });
    logStatement(srv, s, what, @intCast(total));
    var b = ewp.Builder.init(a);
    defer b.deinit();
    try b.i64_(@intCast(total));
    try ewp.writeFrame(w, .executed, f.stream, b.buf.items);
    return .go_on;
}

// Zig tip: `reaper` relies on the same Zig feature as `sendError` above: see the tip there.
/// The reaper: every second, roll back the sessions whose lease ran out.
fn reaper(srv: *Server) void {
    while (!srv.stopping.load(.acquire)) {
        Io.sleep(srv.io, .fromMilliseconds(250), .awake) catch {};
        const now = srv.now();
        var dead: std.ArrayList(*Session) = .empty;
        defer dead.deinit(srv.gpa);
        srv.lock.lockUncancelable(srv.io);
        var it = srv.sessions.valueIterator();
        while (it.next()) |sp| {
            if (sp.*.deadline.load(.acquire) < now) dead.append(srv.gpa, sp.*) catch {};
        }
        srv.lock.unlock(srv.io);
        for (dead.items) |s| {
            if (!s.busy.tryLock()) continue;
            defer s.busy.unlock(srv.io);
            if (s.closed) continue;
            s.expired = true;
            closeSession(srv, s);
        }
    }
}

// ---------------------------------------------------------------------------------------------------------------- statements

// Zig tip: a cast is written with a builtin: `@intCast` checks (in safe builds) that the number fits the smaller type,
// `@bitCast` keeps the bits and changes the type, `@truncate` keeps the low bits.
fn civilFromDays(days: i64) struct { y: i64, m: u8, d: u8 } {
    const z = days + 719468;
    const era = @divFloor(z, 146097);
    const doe = z - era * 146097;
    const yoe = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const doy = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp = @divFloor(5 * doy + 2, 153);
    const d: u8 = @intCast(doy - @divFloor(153 * mp + 2, 5) + 1);
    const m: u8 = @intCast(if (mp < 10) mp + 3 else mp - 9);
    return .{ .y = yoe + era * 400 + @as(i64, if (m <= 2) 1 else 0), .m = m, .d = d };
}

// Zig tip: each parameter is bound by its kind. A date or an instant is sent as text in the form DuckDB reads
// (`YYYY-MM-DD`, `YYYY-MM-DD HH:MM:SS.ffffff`), a decimal, a huge number and a uuid as their text. Bytes are not accepted as
// parameters in 0.1 (a `ProtocolError`). The text is made zero-terminated because the C function wants that.
fn bindParams(srv: *Server, p: *duckdb.Prepared, params: []const ewp.Value) !void {
    const a = srv.gpa;
    for (params, 1..) |v, i| {
        const k: u64 = i;
        switch (v) {
            .null => try p.bindNull(k),
            .boolean => |x| try p.bindBool(k, x),
            .int => |x| try p.bindInt(k, x),
            .real => |x| try p.bindReal(k, x),
            .string, .decimal, .huge => |s| {
                const z = try a.dupeSentinel(u8, s, 0);
                defer a.free(z);
                try p.bindText(k, z);
            },
            .date => |d| {
                const c = civilFromDays(d);
                const z = try std.fmt.allocPrintSentinel(a, "{d:0>4}-{d:0>2}-{d:0>2}", .{ @as(u64, @intCast(@max(c.y, 0))), c.m, c.d }, 0);
                defer a.free(z);
                try p.bindText(k, z);
            },
            .instant => |us| {
                const secs = @divFloor(us, 1_000_000);
                const frac: u64 = @intCast(us - secs * 1_000_000);
                const days = @divFloor(secs, 86400);
                const rem: u64 = @intCast(secs - days * 86400);
                const c = civilFromDays(days);
                const z = try std.fmt.allocPrintSentinel(a, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}.{d:0>6}", .{ @as(u64, @intCast(@max(c.y, 0))), c.m, c.d, rem / 3600, rem % 3600 / 60, rem % 60, frac }, 0);
                defer a.free(z);
                try p.bindText(k, z);
            },
            .uuid => |u| {
                const z = try std.fmt.allocPrintSentinel(a, "{x}-{x}-{x}-{x}-{x}", .{ u[0..4], u[4..6], u[6..8], u[8..10], u[10..16] }, 0);
                defer a.free(z);
                try p.bindText(k, z);
            },
            .bytes => return error.Bind,
        }
    }
}

const Outcome = enum { go_on, drop };

// Zig tip: `replyDbError` relies on the same Zig feature as `validName` above: see the tip there.
fn replyDbError(srv: *Server, s: *Session, w: *Io.Writer, stream: u32) void {
    _ = srv;
    const msg = s.conn.lastError();
    const cls = types.classify(s.conn.err_kind, msg);
    sendError(w, stream, cls.name, cls.state, cls.transient, msg);
}

// Zig tip: `switch` must cover every value of what it tests (or have `else`); the compiler checks it, so a new case can not
// be forgotten. A prong can be an expression that gives the result.
fn faultError(w: *Io.Writer, stream: u32, kind: fault.Kind) void {
    switch (kind) {
        .conflict => sendError(w, stream, "ConflictError", "40001", true, "Conflict on update (fault injected)"),
        .deadlock => sendError(w, stream, "DeadlockError", "40P01", true, "deadlock detected (fault injected)"),
        else => sendError(w, stream, "DatabaseError", "HY000", false, "fault"),
    }
}

// Zig tip: `takeFault` relies on the same Zig feature as `sendError` above: see the tip there.
/// Take a one-shot fault of the session or of the server (scope all).
pub fn takeFault(srv: *Server, s: *Session, kind: fault.Kind, point: ?[]const u8) ?fault.Fault {
    if (s.faults.take(kind, point)) |f| return f;
    srv.lock.lockUncancelable(srv.io);
    defer srv.lock.unlock(srv.io);
    return srv.all_faults.take(kind, point);
}

// Zig tip: `QUERY` and `EXECUTE` share their start: the faults that fire before the statement runs, the preparation and the
// binding. They differ in what they send back, so the shared part answers `true` when the statement ran and left a result
// in `out`; on `false` the error frame was already sent.
fn runStatement(srv: *Server, s: *Session, w: *Io.Writer, stream: u32, sql: []const u8, params: []const ewp.Value, out: *duckdb.Result) bool {
    if (s.faults.items.items.len > 0 or srv.all_faults.items.items.len > 0) {
        for ([_]fault.Kind{ .conflict, .deadlock }) |k| {
            var hit = false;
            if (k == .conflict) {
                // a conflict waits for a statement that names its table
                for (s.faults.items.items, 0..) |f, i| {
                    if (f.kind == .conflict and fault.List.namesTable(sql, f.pointText())) {
                        _ = s.faults.items.orderedRemove(i);
                        hit = true;
                        break;
                    }
                }
            } else hit = takeFault(srv, s, .deadlock, null) != null;
            if (hit) {
                faultError(w, stream, k);
                return false;
            }
        }
    }
    const sql_z = srv.gpa.dupeSentinel(u8, sql, 0) catch {
        sendError(w, stream, "DatabaseError", "HY001", false, "out of memory");
        return false;
    };
    defer srv.gpa.free(sql_z);
    var p = s.conn.prepare(sql_z) catch {
        replyDbError(srv, s, w, stream);
        return false;
    };
    defer p.deinit();
    bindParams(srv, &p, params) catch {
        sendError(w, stream, "ProtocolError", "08P01", false, "a parameter can not be bound");
        return false;
    };
    out.* = s.conn.run(&p) catch {
        replyDbError(srv, s, w, stream);
        return false;
    };
    _ = srv.statements.fetchAdd(1, .monotonic);
    return true;
}

// Zig tip: `readParams` relies on the same Zig feature as `openDbAt` above: see the tip there.
fn readParams(c: *ewp.Cursor, gpa: std.mem.Allocator) ![]ewp.Value {
    const n = try c.u32_();
    if (n > 65535) return error.BadValue;
    const out = try gpa.alloc(ewp.Value, n);
    errdefer gpa.free(out);
    for (out) |*v| v.* = try c.value();
    return out;
}

// ---------------------------------------------------------------------------------------------------------------- frames

// Zig tip: `handleQuery` relies on the same Zig feature as `sendError` above: see the tip there.
fn handleQuery(srv: *Server, s: *Session, w: *Io.Writer, f: ewp.Frame) !Outcome {
    const a = srv.gpa;
    var c: ewp.Cursor = .{ .buf = f.payload };
    const sql = try c.string();
    const params = try readParams(&c, a);
    defer a.free(params);
    const limit = try c.u32_();
    var res: duckdb.Result = undefined;
    if (!runStatement(srv, s, w, f.stream, sql, params, &res)) return .go_on;
    defer res.deinit();
    var cells = cells_mod.Cells.init(a, &res) catch {
        sendError(w, f.stream, "DatabaseError", "HY001", false, "out of memory");
        return .go_on;
    };
    defer cells.deinit();
    if (cells.firstUnsupported()) |k| {
        var msg: [160]u8 = undefined;
        const text = std.fmt.bufPrint(&msg, "column {s} has a type that evedb 0.1 does not send (a list, a struct, a map, a bit string or a time with a zone): cast it to varchar", .{res.columnName(k)}) catch "a column has a type that evedb 0.1 does not send";
        sendError(w, f.stream, "DatabaseError", "0A000", false, text);
        return .go_on;
    }
    const ncols = res.columnCount();
    const total = res.rowCount();
    const rows: u64 = if (limit != 0) @min(total, limit) else total;
    var b = ewp.Builder.init(a);
    defer b.deinit();
    try b.u16_(@intCast(ncols));
    for (0..ncols) |col| {
        try b.string(res.columnName(col));
        try b.string(types.eveType(res.columnType(col)));
    }
    try b.u32_(@intCast(rows));
    for (0..rows) |row| {
        for (0..ncols) |col| try cells.append(&b, col, row);
    }
    try b.u8_(@intFromBool(rows < total));
    logStatement(srv, s, sql, @intCast(rows));
    try ewp.writeFrame(w, .result, f.stream, b.buf.items);
    return .go_on;
}

// Zig tip: `handleExecute` relies on the same Zig feature as `sendError` above: see the tip there.
fn handleExecute(srv: *Server, s: *Session, w: *Io.Writer, f: ewp.Frame) !Outcome {
    const a = srv.gpa;
    var c: ewp.Cursor = .{ .buf = f.payload };
    const sql = try c.string();
    const params = try readParams(&c, a);
    defer a.free(params);
    if (fault.isFaultStatement(sql)) {
        if (!srv.cfg.test_mode) {
            sendError(w, f.stream, "DatabaseError", "42501", false, "pragma eve_fault is allowed only in test mode");
            return .go_on;
        }
        const ft = fault.parse(sql) catch {
            sendError(w, f.stream, "DatabaseError", "42601", false, "bad pragma eve_fault: pragma eve_fault('kind', 'point', arg)");
            return .go_on;
        };
        if (ft.kind == .lease_expire) {
            s.deadline.store(0, .release);
        } else if (ft.all) {
            srv.lock.lockUncancelable(srv.io);
            defer srv.lock.unlock(srv.io);
            try srv.all_faults.add(a, ft);
        } else try s.faults.add(a, ft);
        var b = ewp.Builder.init(a);
        defer b.deinit();
        try b.i64_(0);
        try ewp.writeFrame(w, .executed, f.stream, b.buf.items);
        return .go_on;
    }
    if (takeFault(srv, s, .drop, "execute") != null) return .drop;
    var res: duckdb.Result = undefined;
    if (!runStatement(srv, s, w, f.stream, sql, params, &res)) return .go_on;
    defer res.deinit();
    const changed: i64 = @intCast(res.rowsChanged());
    logStatement(srv, s, sql, changed);
    var b = ewp.Builder.init(a);
    defer b.deinit();
    try b.i64_(changed);
    try ewp.writeFrame(w, .executed, f.stream, b.buf.items);
    return .go_on;
}

// Zig tip: `handleBegin` relies on the same Zig feature as `sendOk` above: see the tip there.
fn handleBegin(srv: *Server, s: *Session, w: *Io.Writer, f: ewp.Frame) !Outcome {
    var c: ewp.Cursor = .{ .buf = f.payload };
    const idb = try c.take(16);
    const isolation = try c.u8_();
    const read_only = try c.u8_();
    if (s.tx != null) {
        sendError(w, f.stream, "ProtocolError", "25001", false, "a transaction is open in this session");
        return .go_on;
    }
    if (isolation != 0) {
        sendError(w, f.stream, "ProtocolError", "0A000", false, "only the default isolation exists in evedb 0.1");
        return .go_on;
    }
    if (takeFault(srv, s, .drop, "begin") != null) return .drop;
    s.conn.exec(if (read_only != 0) "begin transaction read only" else "begin transaction") catch {
        replyDbError(srv, s, w, f.stream);
        return .go_on;
    };
    s.tx = idb[0..16].*;
    srv.lock.lockUncancelable(srv.io);
    srv.open_tx.append(srv.gpa, s.tx.?) catch {};
    srv.lock.unlock(srv.io);
    try sendOk(w, f.stream);
    return .go_on;
}

// Zig tip: `handleCommit` relies on the same Zig feature as `sendError` above: see the tip there.
fn handleCommit(srv: *Server, s: *Session, w: *Io.Writer, f: ewp.Frame) !Outcome {
    var c: ewp.Cursor = .{ .buf = f.payload };
    const idb = try c.take(16);
    const id = s.tx orelse {
        sendError(w, f.stream, "ProtocolError", "25P01", false, "no transaction is open");
        return .go_on;
    };
    if (!std.mem.eql(u8, &id, idb)) {
        sendError(w, f.stream, "ProtocolError", "25P01", false, "the transaction id is not the open one");
        return .go_on;
    }
    if (takeFault(srv, s, .drop, "before_commit") != null) return .drop;
    if (takeFault(srv, s, .commit_fail, null) != null) {
        s.conn.exec("rollback") catch {};
        forgetTx(srv, id);
        s.tx = null;
        sendError(w, f.stream, "CommitError", "40000", true, "the commit failed and the transaction was rolled back (fault injected)");
        return .go_on;
    }
    // the id is written in the same transaction as the data
    var hex: [33]u8 = undefined;
    const idtext = std.fmt.bufPrintSentinel(&hex, "{x}", .{id}, 0) catch unreachable;
    var p = s.conn.prepare("insert into eve_tx values (?, now())") catch {
        replyDbError(srv, s, w, f.stream);
        return .go_on;
    };
    defer p.deinit();
    p.bindText(1, idtext) catch {};
    var r = s.conn.run(&p) catch {
        replyDbError(srv, s, w, f.stream);
        s.conn.exec("rollback") catch {};
        forgetTx(srv, id);
        s.tx = null;
        return .go_on;
    };
    r.deinit();
    s.conn.exec("commit") catch {
        replyDbError(srv, s, w, f.stream);
        s.conn.exec("rollback") catch {};
        forgetTx(srv, id);
        s.tx = null;
        return .go_on;
    };
    forgetTx(srv, id);
    s.tx = null;
    if (takeFault(srv, s, .drop, "after_commit") != null) return .drop;
    try sendOk(w, f.stream);
    return .go_on;
}

// Zig tip: `handleRollback` relies on the same Zig feature as `sendOk` above: see the tip there.
fn handleRollback(srv: *Server, s: *Session, w: *Io.Writer, f: ewp.Frame) !Outcome {
    const id = s.tx orelse {
        sendError(w, f.stream, "ProtocolError", "25P01", false, "no transaction is open");
        return .go_on;
    };
    s.conn.exec("rollback") catch {};
    forgetTx(srv, id);
    s.tx = null;
    try sendOk(w, f.stream);
    return .go_on;
}

// Zig tip: `handleStatus` relies on the same Zig feature as `sendError` above: see the tip there.
fn handleStatus(srv: *Server, s: *Session, w: *Io.Writer, f: ewp.Frame) !Outcome {
    var c: ewp.Cursor = .{ .buf = f.payload };
    const idb = (try c.take(16))[0..16].*;
    var code: u8 = 2;
    if (takeFault(srv, s, .status_unknown, null) == null) {
        code = 1;
        srv.lock.lockUncancelable(srv.io);
        for (srv.open_tx.items) |t| if (std.mem.eql(u8, &t, &idb)) {
            code = 3;
        };
        srv.lock.unlock(srv.io);
        if (code == 1) {
            var hex: [33]u8 = undefined;
            const idtext = std.fmt.bufPrintSentinel(&hex, "{x}", .{idb}, 0) catch unreachable;
            var p = s.conn.prepare("select count(*) from eve_tx where id = ?") catch {
                replyDbError(srv, s, w, f.stream);
                return .go_on;
            };
            defer p.deinit();
            p.bindText(1, idtext) catch {};
            var r = s.conn.run(&p) catch {
                replyDbError(srv, s, w, f.stream);
                return .go_on;
            };
            defer r.deinit();
            if (r.int(0, 0) > 0) code = 0;
        }
    }
    var b = ewp.Builder.init(srv.gpa);
    defer b.deinit();
    try b.u8_(code);
    try ewp.writeFrame(w, .txstatus, f.stream, b.buf.items);
    return .go_on;
}

// Zig tip: `handleDescribe` relies on the same Zig feature as `sendError` above: see the tip there.
fn handleDescribe(srv: *Server, s: *Session, w: *Io.Writer, f: ewp.Frame) !Outcome {
    var c: ewp.Cursor = .{ .buf = f.payload };
    const table = try c.string();
    if (!validName(table)) {
        sendError(w, f.stream, "ProtocolError", "42602", false, "a table name is letters, digits and _");
        return .go_on;
    }
    const sql = try std.fmt.allocPrintSentinel(srv.gpa, "select name, type, \"notnull\", pk from pragma_table_info('{s}')", .{table}, 0);
    defer srv.gpa.free(sql);
    var res = s.conn.query(sql) catch {
        replyDbError(srv, s, w, f.stream);
        return .go_on;
    };
    defer res.deinit();
    const n = res.rowCount();
    if (n == 0) {
        sendError(w, f.stream, "DatabaseError", "42P01", false, "there is no such table");
        return .go_on;
    }
    var b = ewp.Builder.init(srv.gpa);
    defer b.deinit();
    try b.u16_(@intCast(n));
    for (0..n) |row| {
        const name = (try res.text(srv.gpa, 0, row)) orelse try srv.gpa.dupe(u8, "");
        defer srv.gpa.free(name);
        const ty = (try res.text(srv.gpa, 1, row)) orelse try srv.gpa.dupe(u8, "");
        defer srv.gpa.free(ty);
        try b.string(name);
        try b.string(types.eveTypeOfName(ty));
        try b.string(ty);
        try b.u8_(@intFromBool(!res.boolean(2, row)));
        try b.u8_(@intFromBool(res.boolean(3, row)));
    }
    try ewp.writeFrame(w, .described, f.stream, b.buf.items);
    return .go_on;
}

// Zig tip: a connection is a loop that reads one frame, handles it and writes the answer. The session is kept in a local
// optional: `HELLO` and `OPEN` come first, and every other frame needs the session. `busy` is taken for the length of
// one frame and released while the loop waits for the next, which is when the reaper may act. A lease that ran out while
// the loop waited makes the next frame answer `LeaseExpired` and end the connection.
/// Serve one connection until it closes, a fault drops it, or the server stops.
fn connection(srv: *Server, stream: net.Stream) void {
    defer stream.close(srv.io);
    const a = srv.gpa;
    const rbuf = a.alloc(u8, 64 * 1024) catch return;
    defer a.free(rbuf);
    var reader = stream.reader(srv.io, rbuf);
    var wbuf: [8192]u8 = undefined;
    var writer = stream.writer(srv.io, &wbuf);
    const r = &reader.interface;
    const w = &writer.interface;
    var session: ?*Session = null;
    var hello = false;
    defer if (session) |s| {
        s.busy.lockUncancelable(srv.io);
        closeSession(srv, s);
        s.busy.unlock(srv.io);
        // the session object is not freed: the reaper may still hold its address (a few bytes per session)
    };
    while (!srv.stopping.load(.acquire)) {
        const f = ewp.readFrame(r, a) catch |e| {
            if (e == error.FrameTooLarge or e == error.BadFrame) sendError(w, 0, "ProtocolError", "08P01", false, "bad frame");
            return;
        };
        defer ewp.freeFrame(a, f);
        if (!hello) {
            if (f.kind != .hello) {
                sendError(w, f.stream, "ProtocolError", "08P01", false, "HELLO must come first");
                return;
            }
            var c: ewp.Cursor = .{ .buf = f.payload };
            const m = c.take(4) catch return;
            const ver = c.u16_() catch return;
            _ = c.string() catch return;
            const token = c.string() catch return;
            if (!std.mem.eql(u8, m, ewp.magic) or ver != ewp.version) {
                sendError(w, f.stream, "ProtocolError", "08P01", false, "not EWP-db version 1");
                return;
            }
            if (!srv.cfg.test_mode and !constantTimeEql(token, srv.cfg.token)) {
                sendError(w, f.stream, "AuthError", "28000", false, "the token is wrong");
                return;
            }
            var b = ewp.Builder.init(a);
            defer b.deinit();
            b.u16_(ewp.version) catch return;
            b.string("evedb 0.2") catch return;
            b.u8_(@intFromBool(srv.cfg.test_mode)) catch return;
            ewp.writeFrame(w, .hello_ok, f.stream, b.buf.items) catch return;
            hello = true;
            continue;
        }
        if (f.kind == .open) {
            if (session != null) {
                sendError(w, f.stream, "ProtocolError", "08P01", false, "the session is open already");
                return;
            }
            var c: ewp.Cursor = .{ .buf = f.payload };
            const name = c.string() catch return;
            _ = c.u32_() catch return;
            if (!validName(name)) {
                sendError(w, f.stream, "ProtocolError", "42602", false, "a database name is letters, digits and _");
                return;
            }
            const d = openDb(srv, name) catch |e| {
                sendError(w, f.stream, "DatabaseError", "58030", false, @errorName(e));
                return;
            };
            session = newSession(srv, d) catch return;
            var b = ewp.Builder.init(a);
            defer b.deinit();
            b.u64_(session.?.id) catch return;
            b.u32_(srv.cfg.lease_ms) catch return;
            ewp.writeFrame(w, .opened, f.stream, b.buf.items) catch return;
            continue;
        }
        if (f.kind == .serverstat or f.kind == .close) {
            if (f.kind == .close) {
                sendOk(w, f.stream) catch {};
                return;
            }
            var b = ewp.Builder.init(a);
            defer b.deinit();
            srv.lock.lockUncancelable(srv.io);
            const nd: u32 = @intCast(srv.dbs.count());
            const ns: u32 = @intCast(srv.sessions.count());
            const nt: u32 = @intCast(srv.open_tx.items.len);
            srv.lock.unlock(srv.io);
            b.u32_(nd) catch return;
            b.u32_(ns) catch return;
            b.u32_(nt) catch return;
            b.u64_(srv.statements.load(.monotonic)) catch return;
            b.u64_(@intCast(srv.now() - srv.started)) catch return;
            ewp.writeFrame(w, .serverstats, f.stream, b.buf.items) catch return;
            continue;
        }
        if (f.kind == .stop) {
            if (!srv.cfg.test_mode and srv.cfg.token.len == 0) {
                sendError(w, f.stream, "AuthError", "28000", false, "stop needs test mode or a token");
                continue;
            }
            sendOk(w, f.stream) catch {};
            stopServer(srv);
            return;
        }
        const s = session orelse {
            sendError(w, f.stream, "ProtocolError", "08P01", false, "OPEN must come first");
            return;
        };
        s.busy.lockUncancelable(srv.io);
        defer s.busy.unlock(srv.io);
        if (s.closed) {
            sendError(w, f.stream, "LeaseExpired", "08003", true, "the lease of the session ran out and its transaction was rolled back");
            return;
        }
        s.deadline.store(srv.now() + srv.cfg.lease_ms, .release);
        if (s.faults.peek(.delay)) |d| Io.sleep(srv.io, .fromMilliseconds(d.arg), .awake) catch {};
        const outcome: Outcome = (if (f.kind == .load) handleLoad(srv, s, r, w, f) else handle(srv, s, w, f)) catch |e| blk: {
            switch (e) {
                error.Short, error.BadValue => sendError(w, f.stream, "ProtocolError", "08P01", false, "the payload of the frame is wrong"),
                else => return,
            }
            break :blk .go_on;
        };
        if (outcome == .drop) return;
    }
}

// Zig tip: `handle` relies on the same Zig feature as `sendError` above: see the tip there.
fn handle(srv: *Server, s: *Session, w: *Io.Writer, f: ewp.Frame) !Outcome {
    switch (f.kind) {
        .begin => return handleBegin(srv, s, w, f),
        .query => return handleQuery(srv, s, w, f),
        .queryb => return handleQueryB(srv, s, w, f),
        .execute => return handleExecute(srv, s, w, f),
        .commit => return handleCommit(srv, s, w, f),
        .rollback => return handleRollback(srv, s, w, f),
        .status => return handleStatus(srv, s, w, f),
        .describe => return handleDescribe(srv, s, w, f),
        .ping => {
            var b = ewp.Builder.init(srv.gpa);
            defer b.deinit();
            try b.u32_(srv.cfg.lease_ms);
            try ewp.writeFrame(w, .pong, f.stream, b.buf.items);
            return .go_on;
        },
        else => {
            sendError(w, f.stream, "ProtocolError", "08P01", false, "unknown frame type");
            return .go_on;
        },
    }
}

// Zig tip: `wake` relies on the same Zig feature as `validName` above: see the tip there.
fn wake(srv: *Server, port: u16) void {
    if (port == 0) return;
    if (net.IpAddress.parse(srv.cfg.host, port)) |addr| {
        if (addr.connect(srv.io, .{ .mode = .stream })) |c| c.close(srv.io) else |_| {}
    } else |_| {}
}

// Zig tip: `stopServer` relies on the same Zig feature as `validName` above: see the tip there.
/// Ask the accept loops to end: set the flag, then connect once to each port so that `accept` returns.
pub fn stopServer(srv: *Server) void {
    if (srv.stopping.swap(true, .acq_rel)) return;
    wake(srv, srv.bound_port);
    wake(srv, srv.pg_bound_port);
}

// Zig tip: `listenPortOf` relies on the same Zig feature as `validName` above: see the tip there.
pub fn listenPortOf(listener: *const net.Server) u16 {
    return listener.socket.address.getPort();
}

// Zig tip: a server has up to two ports: the frames of EWP-db (the test control: `STATUS`, `evedb stop`, tokens) and the
// PostgreSQL port that a driver uses. Each has its accept loop; the PostgreSQL loop runs on a thread of its own, the EWP-db
// loop on the calling thread (or, when it is switched off, the calling thread just waits for the stop). `ready` is called
// once with the ports that were bound (a configured port 0 asks the system to choose).
/// Bind and run until stopped.
// Zig tip: on Windows `SO_REUSEADDR` lets a second socket take a port that is already listening, so binding is no lock there:
// the server first tries to connect to its own port, and a port that answers means another server runs (the error
// `AddressInUse`, which the command line reports). Elsewhere the option only skips the wait after a restart.
fn checkFree(srv: *Server, port: u16) !void {
    if (port == 0) return;
    const addr = try net.IpAddress.parse(srv.cfg.host, port);
    if (addr.connect(srv.io, .{ .mode = .stream })) |c| {
        c.close(srv.io);
        return error.AddressInUse;
    } else |_| {}
}

const reuse = @import("builtin").os.tag != .windows;

// Zig tip: `run` relies on the same Zig feature as `sendOk` above: see the tip there.
pub fn run(srv: *Server, ready: *const fn (ewp_port: u16, pg_port: u16, test_mode: bool) void) !void {
    srv.started = srv.now();
    if (srv.cfg.ewp) try checkFree(srv, srv.cfg.port);
    if (srv.cfg.pg) try checkFree(srv, srv.cfg.pg_port);
    if (srv.cfg.ewp) {
        const addr = try net.IpAddress.parse(srv.cfg.host, srv.cfg.port);
        srv.listener = try addr.listen(srv.io, .{ .reuse_address = reuse });
        srv.bound_port = listenPortOf(&srv.listener.?);
    }
    if (srv.cfg.pg) {
        const addr = try net.IpAddress.parse(srv.cfg.host, srv.cfg.pg_port);
        srv.pg_listener = try addr.listen(srv.io, .{ .reuse_address = reuse });
        srv.pg_bound_port = listenPortOf(&srv.pg_listener.?);
    }
    ready(srv.bound_port, srv.pg_bound_port, srv.cfg.test_mode);
    const rt = try std.Thread.spawn(.{}, reaper, .{srv});
    var pg_thread: ?std.Thread = null;
    if (srv.cfg.pg) pg_thread = try std.Thread.spawn(.{}, pgserver.acceptLoop, .{srv});
    if (srv.cfg.ewp) {
        while (true) {
            const stream = srv.listener.?.accept(srv.io) catch |e| switch (e) {
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
        srv.listener.?.deinit(srv.io);
    } else {
        while (!srv.stopping.load(.acquire)) Io.sleep(srv.io, .fromMilliseconds(200), .awake) catch {};
    }
    if (pg_thread) |t| t.join();
    rt.join();
    // let the connection threads finish their frame, then close what is open
    Io.sleep(srv.io, .fromMilliseconds(200), .awake) catch {};
    srv.lock.lockUncancelable(srv.io);
    var dit = srv.dbs.valueIterator();
    while (dit.next()) |d| {
        d.*.log_conn.close();
        d.*.db.close();
    }
    srv.lock.unlock(srv.io);
}
