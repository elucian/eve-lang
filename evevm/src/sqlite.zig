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

    // Zig tip: `sqlite3_changes` answers with a C `int`; `@intCast` makes it the `i64` that Eve uses.
    /// The number of rows that the last INSERT, UPDATE or DELETE changed.
    pub fn changes(self: *Db) i64 {
        return @intCast(c.sqlite3_changes(self.handle));
    }

    // Zig tip: `user` is a `*anyopaque`, a pointer to "something": C knows no Zig types, so the pointer
    // travels through SQLite untyped and the callback gets it back with `Call.userData`, then turns it into
    // the right type with `@ptrCast(@alignCast(...))`. The last three arguments of the C function are the
    // step and final functions of an aggregate and a destructor: none here, so `null`.
    /// Adds a scalar function `name` with `nargs` arguments to SQL on this connection (a `sql function`, D-166).
    /// It is deterministic, so SQLite may use it in indexes and may call it fewer times.
    pub fn createFunction(self: *Db, name: [:0]const u8, nargs: u8, user: *anyopaque, func: FnCallback) Error!void {
        const flags = c.SQLITE_UTF8 | c.SQLITE_DETERMINISTIC;
        if (c.sqlite3_create_function_v2(self.handle, name.ptr, nargs, flags, user, func, null, null, null) != c.SQLITE_OK) return error.Exec;
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

    /// Binds a 64-bit float to the parameter `index`.
    pub fn bindReal(self: *Stmt, index: u16, value: f64) Error!void {
        if (c.sqlite3_bind_double(self.handle, index, value) != c.SQLITE_OK) return error.Step;
    }

    /// Binds NULL to the parameter `index`.
    pub fn bindNull(self: *Stmt, index: u16) Error!void {
        if (c.sqlite3_bind_null(self.handle, index) != c.SQLITE_OK) return error.Step;
    }

    // Zig tip: `SQLITE_TRANSIENT` tells SQLite to copy the text at once, so the Zig slice may be freed
    // right after the call. The C header defines it as the pointer value -1, which Zig cannot translate,
    // hence `@ptrFromInt(std.math.maxInt(usize))`, the same bits as -1. `@ptrCast` changes the pointer
    // type; `@alignCast` asserts the alignment. `?*const fn` is how C passes a destructor.
    /// Binds a text to the parameter `index`; SQLite keeps its own copy.
    pub fn bindText(self: *Stmt, index: u16, value: []const u8) Error!void {
        const transient: c.sqlite3_destructor_type = @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(std.math.maxInt(usize)))));
        if (c.sqlite3_bind_text(self.handle, index, value.ptr, @intCast(value.len), transient) != c.SQLITE_OK) return error.Step;
    }

    /// The number of columns of the result.
    pub fn columnCount(self: *Stmt) u16 {
        return @intCast(c.sqlite3_column_count(self.handle));
    }

    /// The name of column `col`, as the query names it (`as total`).
    pub fn columnName(self: *Stmt, col: u16) []const u8 {
        return std.mem.span(c.sqlite3_column_name(self.handle, col));
    }

    /// The storage class of the value in column `col` of the current row.
    pub const Kind = enum { integer, real, text, blob, null };

    // Zig tip: a `switch` on a C constant needs the constants to be known at compile time; they are
    // (`c.SQLITE_INTEGER` is a translated `#define`), and `else` covers every other value.
    pub fn columnKind(self: *Stmt, col: u16) Kind {
        return switch (c.sqlite3_column_type(self.handle, col)) {
            c.SQLITE_INTEGER => .integer,
            c.SQLITE_FLOAT => .real,
            c.SQLITE_TEXT => .text,
            c.SQLITE_BLOB => .blob,
            else => .null,
        };
    }

    /// The float value of column `col` of the current row.
    pub fn columnReal(self: *Stmt, col: u16) f64 {
        return c.sqlite3_column_double(self.handle, col);
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

// Zig tip: `callconv(.c)` gives a Zig function the calling convention of C, so a C library can call it
// through a pointer. Its parameter types must be C types: `c_int`, and `[*c]` pointers, which may be null
// and may be indexed like an array. SQLite calls such a function for each row where SQL calls it.
/// The C signature of a SQL function written in Zig: the call, the number of arguments, the arguments.
pub const FnCallback = *const fn (ctx: ?*CallHandle, argc: c_int, argv: [*c]?*ArgHandle) callconv(.c) void;

// Zig tip: `pub const X = c.y;` gives a C type a Zig name. A file that writes a callback can then spell its
// parameter types (`?*sqlite.CallHandle`) without importing the C header itself.
/// The C handle of one call of a SQL function, and of one of its arguments.
pub const CallHandle = c.sqlite3_context;
pub const ArgHandle = c.sqlite3_value;

// Zig tip: a struct with one field wraps a C pointer, so the rest of the VM uses methods (`arg.int()`)
// and never imports the C header itself: only this file knows SQLite's C API.
/// One argument of a call of a SQL function.
pub const Arg = struct {
    handle: ?*c.sqlite3_value,

    // Zig tip: `kind` relies on the same Zig feature as `Stmt.columnKind`: see the tip there.
    /// The storage class of the argument: the same kinds as a column.
    pub fn kind(self: Arg) Stmt.Kind {
        return switch (c.sqlite3_value_type(self.handle)) {
            c.SQLITE_INTEGER => .integer,
            c.SQLITE_FLOAT => .real,
            c.SQLITE_TEXT => .text,
            c.SQLITE_BLOB => .blob,
            else => .null,
        };
    }

    // Zig tip: a method may take the struct by value (`self: Arg`) when it changes nothing: the struct is one pointer,
    // so the copy costs nothing. `real` and `text` below do the same.
    /// The integer value of the argument.
    pub fn int(self: Arg) i64 {
        return c.sqlite3_value_int64(self.handle);
    }

    // Zig tip: `real` relies on the same Zig feature as `int` above: see the tip there.
    /// The float value of the argument.
    pub fn real(self: Arg) f64 {
        return c.sqlite3_value_double(self.handle);
    }

    // Zig tip: `text` relies on the same Zig feature as `Stmt.columnText`: see the tip there. The slice
    // borrows SQLite's memory, valid until the function returns: copy it to keep it.
    /// The text of the argument; "" for NULL.
    pub fn text(self: Arg) []const u8 {
        const ptr = c.sqlite3_value_text(self.handle);
        if (ptr == null) return "";
        const len: usize = @intCast(c.sqlite3_value_bytes(self.handle));
        return ptr[0..len];
    }
};

// Zig tip: `Call` relies on the same Zig feature as `Arg` above: a struct around one C pointer, so no other file needs
// the C header. Its methods take `self` by value, as `Arg.int` does.
/// One call of a SQL function: it gives back the user pointer of `createFunction` and takes the result.
pub const Call = struct {
    handle: ?*c.sqlite3_context,

    // Zig tip: `?*anyopaque` is an optional untyped pointer: the caller checks it (`.?`) and gives it a type with
    // `@ptrCast(@alignCast(...))`, see `createFunction`.
    /// The pointer given to `createFunction`.
    pub fn userData(self: Call) ?*anyopaque {
        return c.sqlite3_user_data(self.handle);
    }

    // Zig tip: a function that returns `void` and can not fail needs no `!`: the C call gives no status to check.
    /// The result is an integer.
    pub fn resultInt(self: Call, v: i64) void {
        c.sqlite3_result_int64(self.handle, v);
    }

    // Zig tip: `resultReal` relies on the same Zig feature as `resultInt` above: see the tip there.
    /// The result is a float.
    pub fn resultReal(self: Call, v: f64) void {
        c.sqlite3_result_double(self.handle, v);
    }

    // Zig tip: `resultNull` relies on the same Zig feature as `resultInt` above: see the tip there.
    /// The result is NULL.
    pub fn resultNull(self: Call) void {
        c.sqlite3_result_null(self.handle);
    }

    // Zig tip: `resultText` uses the "transient" destructor of `Stmt.bindText` (see the tip there): SQLite
    // copies the text at once, so the Zig memory may be freed right after the call.
    /// The result is a text; SQLite keeps its own copy.
    pub fn resultText(self: Call, v: []const u8) void {
        const transient: c.sqlite3_destructor_type = @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(std.math.maxInt(usize)))));
        c.sqlite3_result_text(self.handle, v.ptr, @intCast(v.len), transient);
    }

    // Zig tip: a slice carries its length, so the message goes to C as a pointer and a length (`msg.ptr`,
    // `msg.len`) and needs no zero byte at its end.
    /// The call failed: the statement that made it stops with this message.
    pub fn resultError(self: Call, msg: []const u8) void {
        c.sqlite3_result_error(self.handle, msg.ptr, @intCast(msg.len));
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

test "sqlite: binds text, null and real, and reads the names and kinds of the columns" {
    var db = try Db.open(":memory:");
    defer db.close();
    try db.exec("create table t (id integer primary key, name text, price real)");
    var ins = try db.prepare("insert into t (id, name, price) values (?, ?, ?)");
    try ins.bindInt(1, 7);
    try ins.bindText(2, "Smith, Bob");
    try ins.bindNull(3);
    try std.testing.expect(!try ins.step());
    ins.finalize();
    try std.testing.expectEqual(@as(i64, 1), db.changes());

    var q = try db.prepare("select name as who, price from t");
    defer q.finalize();
    try std.testing.expectEqual(@as(u16, 2), q.columnCount());
    try std.testing.expectEqualStrings("who", q.columnName(0));
    try std.testing.expect(try q.step());
    try std.testing.expectEqual(Stmt.Kind.text, q.columnKind(0));
    try std.testing.expectEqual(Stmt.Kind.null, q.columnKind(1));
    try std.testing.expectEqualStrings("Smith, Bob", q.columnText(0));
}

// Zig tip: a test may declare a function inside a struct and take its address: `twice.call` has the C
// calling convention, so it can be given to SQLite. `std.testing.expectError` checks that a call fails
// with that exact error.
test "sqlite: a function written in Zig is called from SQL, and its error stops the statement" {
    var db = try Db.open(":memory:");
    defer db.close();
    const twice = struct {
        fn call(ctx: ?*c.sqlite3_context, argc: c_int, argv: [*c]?*c.sqlite3_value) callconv(.c) void {
            const k = Call{ .handle = ctx };
            if (argc != 1) return k.resultError("one argument");
            const a = Arg{ .handle = argv[0] };
            if (a.kind() == .null) return k.resultError("NULL is refused");
            k.resultInt(a.int() * 2);
        }
    };
    var marker: u8 = 0;
    try db.createFunction("twice", 1, &marker, twice.call);
    var q = try db.prepare("select twice(21)");
    try std.testing.expect(try q.step());
    try std.testing.expectEqual(@as(i64, 42), q.columnInt(0));
    q.finalize();
    var bad = try db.prepare("select twice(null)");
    defer bad.finalize();
    try std.testing.expectError(error.Step, bad.step());
    try std.testing.expectEqualStrings("NULL is refused", db.errorMessage());
}
