//! DuckDB, the engine of evedb (README.md §3): a thin binding over its C API (`duckdb.h`).
//! The prebuilt library is a dependency of build.zig.zon; build.zig links it.
const std = @import("std");

// Zig tip: `@import("duckdb_c")` is a module made by build.zig from the C header
// (`addTranslateC`), not a file of this folder. C types and functions are its fields.
const c = @import("duckdb_c");

// Zig tip: an error set names the ways a function can fail. `Error!Database` means "an
// error of this set, or a Database"; the caller deals with the error, often with `try`.
pub const Error = error{ Open, Connect, Query };

// Zig tip: `std.mem.span` turns a C string (a pointer that ends at a zero byte) into a Zig
// slice that knows its length, so the rest of the code never counts bytes by hand.
/// The version of the DuckDB library, for example "v1.5.6".
pub fn libVersion() []const u8 {
    return std.mem.span(c.duckdb_library_version());
}

// Zig tip: a struct with methods: `db.connect()` calls `connect(&db)`. The handle is a C
// pointer that starts as `null` and is filled by `duckdb_open`.
/// One database: a file, or in memory when the path is null.
pub const Database = struct {
    handle: c.duckdb_database = null,

    // Zig tip: `?[:0]const u8` is an optional string: a zero-terminated slice or `null`.
    // `if (path) |p| p.ptr else null` unwraps it for C, which takes a plain nullable pointer.
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

    /// Closes the connection.
    pub fn close(self: *Connection) void {
        c.duckdb_disconnect(&self.handle);
    }

    // Zig tip: `undefined` leaves a variable without a value: C fills it. Reading it before
    // that is a bug that safe builds may catch, so it is used only for output parameters.
    /// Runs SQL and returns its whole result; free it with `Result.deinit`.
    pub fn query(self: *Connection, sql: [:0]const u8) Error!Result {
        var res: Result = .{ .raw = undefined };
        if (c.duckdb_query(self.handle, sql.ptr, &res.raw) != c.DuckDBSuccess) {
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

    /// The value at `col`, `row` as a 64-bit integer (0 for NULL).
    pub fn int(self: *Result, col: u64, row: u64) i64 {
        return c.duckdb_value_int64(&self.raw, col, row);
    }
};

// Zig tip: `defer` runs its statement when the test ends, by any path, also when an
// expectation fails, so the connection and the database are always closed (in reverse order).
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
