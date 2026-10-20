//! DuckDB, the engine of evedb (README.md §3): a thin binding over its C API (`duckdb.h`).
//! The prebuilt library is a dependency of build.zig.zon; build.zig links it.
const std = @import("std");

const c = @import("duckdb_c");

pub const Error = error{ Open, Connect, Query, Prepare, Bind } || std.mem.Allocator.Error;

/// The version of the DuckDB library, for example "v1.5.6".
pub fn libVersion() []const u8 {
    return std.mem.span(c.duckdb_library_version());
}

/// One database: a file, or in memory when the path is null.
pub const Database = struct {
    handle: c.duckdb_database = null,

    /// Opens (and creates when missing) a database file; `null` opens an in-memory database.
    pub fn open(path: ?[:0]const u8) Error!Database {
        var db: Database = .{};
        const c_path: [*c]const u8 = if (path) |p| p.ptr else null;
        if (c.duckdb_open(c_path, &db.handle) != c.DuckDBSuccess) return error.Open;
        return db;
    }

    /// Closes the database; every connection must be closed first.
    pub fn close(self: *Database) void {
        c.duckdb_close(&self.handle);
    }

    /// A new connection: evedb gives one to each session (README.md §4).
    pub fn connect(self: *Database) Error!Connection {
        var conn: Connection = .{};
        if (c.duckdb_connect(self.handle, &conn.handle) != c.DuckDBSuccess) return error.Connect;
        return conn;
    }
};

/// One connection; DuckDB runs the transactions of different connections side by side (MVCC).
pub const Connection = struct {
    handle: c.duckdb_connection = null,
    /// The text and the kind of the last error (DuckDB frees its own copy with the result, so the text is kept here).
    err_buf: [512]u8 = undefined,
    err_len: usize = 0,
    err_kind: c_uint = 0,

    /// The message of the last failed statement.
    pub fn lastError(self: *const Connection) []const u8 {
        return self.err_buf[0..self.err_len];
    }

    fn keepError(self: *Connection, msg: [*c]const u8, kind: c_uint) void {
        const text: []const u8 = if (msg == null) "unknown error" else std.mem.span(msg);
        const n = @min(text.len, self.err_buf.len);
        @memcpy(self.err_buf[0..n], text[0..n]);
        self.err_len = n;
        self.err_kind = kind;
    }

    /// Closes the connection.
    pub fn close(self: *Connection) void {
        c.duckdb_disconnect(&self.handle);
    }

    /// Runs SQL and returns its whole result; free it with `Result.deinit`.
    pub fn query(self: *Connection, sql: [:0]const u8) Error!Result {
        var res: Result = .{ .raw = undefined };
        if (c.duckdb_query(self.handle, sql.ptr, &res.raw) != c.DuckDBSuccess) {
            self.keepError(c.duckdb_result_error(&res.raw), c.duckdb_result_error_type(&res.raw));
            c.duckdb_destroy_result(&res.raw);
            return error.Query;
        }
        return res;
    }

    /// Compile a statement with `?` parameters (the first is 1).
    pub fn prepare(self: *Connection, sql: [:0]const u8) Error!Prepared {
        var p: Prepared = .{};
        if (c.duckdb_prepare(self.handle, sql.ptr, &p.raw) != c.DuckDBSuccess) {
            self.keepError(c.duckdb_prepare_error(p.raw), 0);
            c.duckdb_destroy_prepare(&p.raw);
            return error.Prepare;
        }
        return p;
    }

    /// Run a prepared statement; on failure the message is kept as for `query`.
    pub fn run(self: *Connection, p: *Prepared) Error!Result {
        var res: Result = .{ .raw = undefined };
        if (c.duckdb_execute_prepared(p.raw, &res.raw) != c.DuckDBSuccess) {
            self.keepError(c.duckdb_result_error(&res.raw), c.duckdb_result_error_type(&res.raw));
            c.duckdb_destroy_result(&res.raw);
            return error.Query;
        }
        return res;
    }

    /// Runs SQL whose result is not needed (DDL, insert, update).
    pub fn exec(self: *Connection, sql: [:0]const u8) Error!void {
        var res = try self.query(sql);
        res.deinit();
    }
};

/// A bulk inserter into one table of a connection.
pub const Appender = struct {
    raw: c.duckdb_appender = null,

    /// Start appending to `table` (in the schema `main`).
    pub fn create(conn: *Connection, table: [:0]const u8) Error!Appender {
        var a: Appender = .{};
        if (c.duckdb_appender_create(conn.handle, null, table.ptr, &a.raw) != c.DuckDBSuccess) {
            conn.keepError(c.duckdb_appender_error(a.raw), 0);
            _ = c.duckdb_appender_destroy(&a.raw);
            return error.Query;
        }
        return a;
    }

    /// The message of the last failure of the appender.
    pub fn lastError(self: *Appender) []const u8 {
        const p = c.duckdb_appender_error(self.raw);
        return if (p == null) "the appender failed" else std.mem.span(p);
    }

    pub fn appendNull(self: *Appender) Error!void {
        if (c.duckdb_append_null(self.raw) != c.DuckDBSuccess) return error.Bind;
    }

    pub fn appendBool(self: *Appender, v: bool) Error!void {
        if (c.duckdb_append_bool(self.raw, v) != c.DuckDBSuccess) return error.Bind;
    }

    pub fn appendInt(self: *Appender, v: i64) Error!void {
        if (c.duckdb_append_int64(self.raw, v) != c.DuckDBSuccess) return error.Bind;
    }

    pub fn appendReal(self: *Appender, v: f64) Error!void {
        if (c.duckdb_append_double(self.raw, v) != c.DuckDBSuccess) return error.Bind;
    }

    pub fn appendText(self: *Appender, v: []const u8) Error!void {
        if (c.duckdb_append_varchar_length(self.raw, v.ptr, v.len) != c.DuckDBSuccess) return error.Bind;
    }

    pub fn appendBlob(self: *Appender, v: []const u8) Error!void {
        if (c.duckdb_append_blob(self.raw, v.ptr, v.len) != c.DuckDBSuccess) return error.Bind;
    }

    pub fn appendDate(self: *Appender, days: i32) Error!void {
        if (c.duckdb_append_date(self.raw, .{ .days = days }) != c.DuckDBSuccess) return error.Bind;
    }

    pub fn appendTimestamp(self: *Appender, micros: i64) Error!void {
        if (c.duckdb_append_timestamp(self.raw, .{ .micros = micros }) != c.DuckDBSuccess) return error.Bind;
    }

    pub fn endRow(self: *Appender) Error!void {
        if (c.duckdb_appender_end_row(self.raw) != c.DuckDBSuccess) return error.Bind;
    }

    /// Write what is buffered into the table (in the transaction of the connection).
    pub fn flush(self: *Appender) Error!void {
        if (c.duckdb_appender_flush(self.raw) != c.DuckDBSuccess) return error.Query;
    }

    pub fn deinit(self: *Appender) void {
        _ = c.duckdb_appender_destroy(&self.raw);
    }
};

/// A prepared statement.
pub const Prepared = struct {
    raw: c.duckdb_prepared_statement = null,

    pub fn deinit(self: *Prepared) void {
        c.duckdb_destroy_prepare(&self.raw);
    }

    /// How many parameters the statement has.
    pub fn paramCount(self: *Prepared) u64 {
        return c.duckdb_nparams(self.raw);
    }

    /// The number of columns the statement will return.
    pub fn columnCount(self: *Prepared) u64 {
        return c.duckdb_prepared_statement_column_count(self.raw);
    }

    pub fn columnName(self: *Prepared, i: u64) []const u8 {
        const p = c.duckdb_prepared_statement_column_name(self.raw, i);
        defer c.duckdb_free(@ptrCast(@constCast(p)));
        return std.mem.span(p);
    }

    pub fn columnType(self: *Prepared, i: u64) c_uint {
        return c.duckdb_prepared_statement_column_type(self.raw, i);
    }

    pub fn bindNull(self: *Prepared, i: u64) Error!void {
        if (c.duckdb_bind_null(self.raw, i) != c.DuckDBSuccess) return error.Bind;
    }

    pub fn bindBool(self: *Prepared, i: u64, v: bool) Error!void {
        if (c.duckdb_bind_boolean(self.raw, i, v) != c.DuckDBSuccess) return error.Bind;
    }

    pub fn bindInt(self: *Prepared, i: u64, v: i64) Error!void {
        if (c.duckdb_bind_int64(self.raw, i, v) != c.DuckDBSuccess) return error.Bind;
    }

    pub fn bindReal(self: *Prepared, i: u64, v: f64) Error!void {
        if (c.duckdb_bind_double(self.raw, i, v) != c.DuckDBSuccess) return error.Bind;
    }

    pub fn bindText(self: *Prepared, i: u64, v: [:0]const u8) Error!void {
        if (c.duckdb_bind_varchar(self.raw, i, v.ptr) != c.DuckDBSuccess) return error.Bind;
    }
};

/// A materialized result: rows and columns read by index.
pub const Result = struct {
    raw: c.duckdb_result,

    /// Frees the result.
    pub fn deinit(self: *Result) void {
        c.duckdb_destroy_result(&self.raw);
    }

    /// The number of rows.
    pub fn rowCount(self: *Result) u64 {
        return c.duckdb_row_count(&self.raw);
    }

    pub fn columnCount(self: *Result) u64 {
        return c.duckdb_column_count(&self.raw);
    }

    pub fn columnName(self: *Result, col: u64) []const u8 {
        return std.mem.span(c.duckdb_column_name(&self.raw, col));
    }

    /// The DuckDB type of a column (`c.DUCKDB_TYPE_*`).
    pub fn columnType(self: *Result, col: u64) c_uint {
        return c.duckdb_column_type(&self.raw, col);
    }

    /// The rows an `insert`, `update` or `delete` changed.
    pub fn rowsChanged(self: *Result) u64 {
        return c.duckdb_rows_changed(&self.raw);
    }

    pub fn isNull(self: *Result, col: u64, row: u64) bool {
        return c.duckdb_value_is_null(&self.raw, col, row);
    }

    pub fn real(self: *Result, col: u64, row: u64) f64 {
        return c.duckdb_value_double(&self.raw, col, row);
    }

    pub fn boolean(self: *Result, col: u64, row: u64) bool {
        return c.duckdb_value_boolean(&self.raw, col, row);
    }

    pub fn uint(self: *Result, col: u64, row: u64) u64 {
        return c.duckdb_value_uint64(&self.raw, col, row);
    }

    /// The days since 1970-01-01 of a date cell.
    pub fn days(self: *Result, col: u64, row: u64) i32 {
        return c.duckdb_value_date(&self.raw, col, row).days;
    }

    /// The micro seconds of a timestamp cell.
    pub fn micros(self: *Result, col: u64, row: u64) i64 {
        return c.duckdb_value_timestamp(&self.raw, col, row).micros;
    }

    /// The text of a cell (any type), copied with `gpa`; null for NULL.
    pub fn text(self: *Result, gpa: std.mem.Allocator, col: u64, row: u64) Error!?[]u8 {
        if (self.isNull(col, row)) return null;
        const p = c.duckdb_value_varchar(&self.raw, col, row);
        if (p == null) return null;
        defer c.duckdb_free(p);
        return try gpa.dupe(u8, std.mem.span(p));
    }

    /// The bytes of a BLOB cell, copied with `gpa`.
    pub fn blob(self: *Result, gpa: std.mem.Allocator, col: u64, row: u64) Error![]u8 {
        const b = c.duckdb_value_blob(&self.raw, col, row);
        defer if (b.data != null) c.duckdb_free(b.data);
        if (b.data == null) return try gpa.alloc(u8, 0);
        const bytes: [*]const u8 = @ptrCast(b.data);
        return try gpa.dupe(u8, bytes[0..b.size]);
    }

    /// The value at `col`, `row` as a 64-bit integer (0 for NULL).
    pub fn int(self: *Result, col: u64, row: u64) i64 {
        return c.duckdb_value_int64(&self.raw, col, row);
    }
};

test "duckdb: a memory database stores and reads back rows" {
    var db = try Database.open(null);
    defer db.close();
    var conn = try db.connect();
    defer conn.close();

    try conn.exec("create table t (id bigint primary key, amount decimal(12, 2), big hugeint)");
    try conn.exec("insert into t values (1, 12.50, 170141183460469231731687303715884105727), (2, 7.25, -1)");
    var res = try conn.query("select id from t order by id");
    defer res.deinit();
    try std.testing.expectEqual(@as(u64, 2), res.rowCount());
    try std.testing.expectEqual(@as(i64, 2), res.int(0, 1));
}

test "duckdb: an upsert updates the row with the same key" {
    var db = try Database.open(null);
    defer db.close();
    var conn = try db.connect();
    defer conn.close();

    try conn.exec("create table t (id bigint primary key, n bigint)");
    try conn.exec("insert into t values (1, 10)");
    try conn.exec("insert into t values (1, 20) on conflict (id) do update set n = excluded.n");
    var res = try conn.query("select n from t where id = 1");
    defer res.deinit();
    try std.testing.expectEqual(@as(i64, 20), res.int(0, 0));
}

test "duckdb: a bad statement is an error" {
    try std.testing.expect(std.mem.startsWith(u8, libVersion(), "v1."));
    var db = try Database.open(null);
    defer db.close();
    var conn = try db.connect();
    defer conn.close();
    try std.testing.expectError(error.Query, conn.query("select * from missing_table"));
}

test "duckdb: a prepared statement with parameters, a kept error and typed cells" {
    var db = try Database.open(null);
    defer db.close();
    var conn = try db.connect();
    defer conn.close();
    try conn.exec("create table t (id bigint primary key, name varchar, price decimal(10, 2), ts timestamp)");
    var ins = try conn.prepare("insert into t values (?, ?, 12.50, '2026-10-17 08:00:00')");
    defer ins.deinit();
    try ins.bindInt(1, 7);
    try ins.bindText(2, "bolt");
    var r0 = try conn.run(&ins);
    r0.deinit();
    try ins.bindInt(1, 7);
    try ins.bindText(2, "dup");
    try std.testing.expectError(error.Query, conn.run(&ins));
    try std.testing.expect(std.mem.indexOf(u8, conn.lastError(), "Constraint") != null);
    var res = try conn.query("select id, name, price, ts from t");
    defer res.deinit();
    try std.testing.expectEqual(@as(u64, 4), res.columnCount());
    try std.testing.expectEqual(@as(c_uint, c.DUCKDB_TYPE_DECIMAL), res.columnType(2));
    const price = (try res.text(std.testing.allocator, 2, 0)).?;
    defer std.testing.allocator.free(price);
    try std.testing.expectEqualStrings("12.50", price);
    try std.testing.expect(res.micros(3, 0) > 0);
    try std.testing.expectError(error.Prepare, conn.prepare("select * from nowhere"));
}
