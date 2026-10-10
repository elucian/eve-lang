//! SQLite, the core database of Eve (design-database-core.md §2): a thin binding over the C API.
//! The C source is the SQLite amalgamation, a dependency of build.zig.zon compiled by build.zig.
const std = @import("std");

// Zig tip: `@import("sqlite_c")` is not a file: build.zig translates `sqlite3.h` into Zig
// declarations (`addTranslateC`) and gives the result this module name. Every C function and
// constant of the header is then a field of `c`: `c.sqlite3_open_v2`, `c.SQLITE_OK`.
const c = @import("sqlite_c");

// Zig tip: an error set lists the errors a function may return. A function that returns
// `Error!Db` returns either an error of this set or a `Db`; the caller must handle both,
// usually with `try`, which passes the error up.
pub const Error = error{ Open, Exec, Prepare, Step };

// Zig tip: `[*:0]const u8` is a C string seen from Zig: a pointer to bytes that ends at a zero
// byte. `std.mem.span` turns it into a slice (`[]const u8`), which knows its length.
/// The version of the SQLite library linked into the VM, for example "3.54.0".
pub fn libVersion() []const u8 {
    return std.mem.span(c.sqlite3_libversion());
}

// Zig tip: a `struct` with methods. A function declared inside a struct whose first parameter
// is the struct (`self: *Db`) is called with a dot: `db.exec(...)`. The field `handle` is an
// optional pointer (`?*T`): it may be `null`, and Zig makes us check before we use it.
/// One open database: a file, or ":memory:".
pub const Db = struct {
    handle: ?*c.sqlite3,

    // Zig tip: `[:0]const u8` is a slice with a zero byte after its last element, so it can
    // be passed to C as a string with `.ptr`. A string literal such as ":memory:" has this
    // type already.
    /// Opens (and creates when missing) a database.
    pub fn open(path: [:0]const u8) Error!Db {
        var handle: ?*c.sqlite3 = null;
        const flags = c.SQLITE_OPEN_READWRITE | c.SQLITE_OPEN_CREATE;
        // Zig tip: `&handle` passes the address of a local variable, so the C function can
        // write the new handle into it (an output parameter, as `@` outputs are in Eve).
        if (c.sqlite3_open_v2(path.ptr, &handle, flags, null) != c.SQLITE_OK) {
            // SQLite returns a handle even on failure; it must be closed.
            _ = c.sqlite3_close(handle);
            return error.Open;
        }
        return .{ .handle = handle };
    }

    // Zig tip: a method that takes `self: *Db` (a pointer) may change the struct; here it
    // sets the handle to null so a second close does nothing.
    /// Closes the database. Safe to call twice.
    pub fn close(self: *Db) void {
        _ = c.sqlite3_close(self.handle);
        self.handle = null;
    }

    // Zig tip: `_ = expr;` drops a result on purpose. Zig refuses to compile an ignored
    // non-void value, so forgetting to check a result is never silent.
    /// Runs SQL that returns no rows (one or several statements separated by `;`).
    pub fn exec(self: *Db, sql: [:0]const u8) Error!void {
        if (c.sqlite3_exec(self.handle, sql.ptr, null, null, null) != c.SQLITE_OK) return error.Exec;
    }

    /// The text of the last error of this database, for messages.
    pub fn errorMessage(self: *Db) []const u8 {
        return std.mem.span(c.sqlite3_errmsg(self.handle));
    }

    /// Compiles one SQL statement; run it with `step` and release it with `finalize`.
    pub fn prepare(self: *Db, sql: [:0]const u8) Error!Stmt {
        var stmt: ?*c.sqlite3_stmt = null;
        // Zig tip: `@intCast` converts an integer to the type the context needs (here the
        // C `int` of the length) and checks, in safe builds, that the value fits.
        const len: c_int = @intCast(sql.len);
        if (c.sqlite3_prepare_v2(self.handle, sql.ptr, len, &stmt, null) != c.SQLITE_OK) return error.Prepare;
        return .{ .handle = stmt };
    }
};

/// One compiled statement: `step` gives the rows one by one.
pub const Stmt = struct {
    handle: ?*c.sqlite3_stmt,

    /// Releases the statement.
    pub fn finalize(self: *Stmt) void {
        _ = c.sqlite3_finalize(self.handle);
        self.handle = null;
    }

    // Zig tip: `Error!bool` combines an error union with a plain result: `true` (a row is
    // ready), `false` (no more rows) or an error. `try stmt.step()` gives the `bool`.
    /// Runs the statement to the next row: true when a row is ready, false at the end.
    pub fn step(self: *Stmt) Error!bool {
        return switch (c.sqlite3_step(self.handle)) {
            c.SQLITE_ROW => true,
            c.SQLITE_DONE => false,
            else => error.Step,
        };
    }

    /// Binds a 64-bit integer to the parameter `index` (the first `?` is 1).
    pub fn bindInt(self: *Stmt, index: u16, value: i64) Error!void {
        if (c.sqlite3_bind_int64(self.handle, index, value) != c.SQLITE_OK) return error.Step;
    }

    /// The integer value of column `col` (the first column is 0) of the current row.
    pub fn columnInt(self: *Stmt, col: u16) i64 {
        return c.sqlite3_column_int64(self.handle, col);
    }

    // Zig tip: a C pointer that may be null arrives as `[*c]const u8`. Comparing it with
    // `null` first, then slicing `ptr[0..len]`, makes a Zig slice that borrows the C memory:
    // valid only until the next `step` or `finalize`.
    /// The text of column `col` of the current row; "" for NULL. Valid until the next step.
    pub fn columnText(self: *Stmt, col: u16) []const u8 {
        const ptr = c.sqlite3_column_text(self.handle, col);
        if (ptr == null) return "";
        const len: usize = @intCast(c.sqlite3_column_bytes(self.handle, col));
        return ptr[0..len];
    }
};

// Zig tip: `defer` runs its statement when the scope ends, by any path, also when `try`
// returns an error: the database is closed even if an expectation fails. (Eve has the same
// statement, D-081.)
test "sqlite: a memory database stores and reads back a row" {
    var db = try Db.open(":memory:");
    defer db.close();
    try db.exec("create table t (id integer primary key, name text not null) strict");
    try db.exec("insert into t (name) values ('Ann')");

    var stmt = try db.prepare("select id, name from t where id = ?");
    defer stmt.finalize();
    try stmt.bindInt(1, 1);
    try std.testing.expect(try stmt.step());
    try std.testing.expectEqual(@as(i64, 1), stmt.columnInt(0));
    try std.testing.expectEqualStrings("Ann", stmt.columnText(1));
    try std.testing.expect(!try stmt.step());
}

test "sqlite: the settings of the build are active" {
    try std.testing.expect(std.mem.startsWith(u8, libVersion(), "3."));
    var db = try Db.open(":memory:");
    defer db.close();
    // Foreign keys are on by default (SQLITE_DEFAULT_FOREIGN_KEYS=1 in build.zig).
    var stmt = try db.prepare("pragma foreign_keys");
    defer stmt.finalize();
    try std.testing.expect(try stmt.step());
    try std.testing.expectEqual(@as(i64, 1), stmt.columnInt(0));
    // Double-quoted strings are names, never text (SQLITE_DQS=0): "nope" is an unknown column.
    try std.testing.expectError(error.Prepare, db.prepare("select \"nope\""));
}
