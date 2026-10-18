//! The configuration file of evedb (README.md section 5A.3): one `key = value` per line, `#` or `**` starts a comment, and one
//! `database "name" = "file"` line for each database a client may ask for. The syntax is the one of `eve.cfg`.
//!
//!     # evedb.cfg
//!     port = 5432                  # the PostgreSQL port
//!     host = "127.0.0.1"
//!     user = "eve"
//!     password = "secret"
//!     auth = "md5"                 # trust, password or md5
//!     test = true                  # faults and the statement log
//!     control_port = 8044          # the EWP-db port of the tests, "off" to close it
//!     database "shop" = "data/shop.duckdb"
const std = @import("std");
const server = @import("server.zig");
const pgserver = @import("pgserver.zig");

pub const Error = error{ BadLine, BadValue, OutOfMemory };

// Zig tip: a plain function: the types of the parameters and of the result are written out, and Zig has no default
// arguments, so a call always passes every parameter.
fn unquote(s: []const u8) []const u8 {
    const t = std.mem.trim(u8, s, " \t\r");
    if (t.len >= 2 and t[0] == '"' and t[t.len - 1] == '"') return t[1 .. t.len - 1];
    return t;
}

// Zig tip: `s[a..b]` is a slice: a pointer and a length into memory that someone else owns; nothing is copied, and the
// bounds are checked in safe builds.
fn cut(line: []const u8) []const u8 {
    var in_q = false;
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        if (line[i] == '"') in_q = !in_q;
        if (!in_q and line[i] == '#') return line[0..i];
        if (!in_q and line[i] == '*' and i + 1 < line.len and line[i + 1] == '*') return line[0..i];
    }
    return line;
}

// Zig tip: the result type `!T` (or `Error!T`) is an error union: a value or an error. `try f()` passes the error to the
// caller; `f() catch …` handles it in place.
fn truth(v: []const u8) Error!bool {
    if (std.mem.eql(u8, v, "true") or std.mem.eql(u8, v, "yes") or std.mem.eql(u8, v, "on")) return true;
    if (std.mem.eql(u8, v, "false") or std.mem.eql(u8, v, "no") or std.mem.eql(u8, v, "off")) return false;
    return error.BadValue;
}

// Zig tip: the text is read line by line into a `Config`; the strings in it are slices of the text (nothing is copied), so
// the text must live as long as the configuration. The list of databases is built in an `ArrayList` and handed over as a
// slice. An unknown key is an error, so a typo does not go unnoticed. `base` is the folder of the file: a relative path of a
// database is relative to it, so a configuration works from any working folder.
/// Parse the text of a configuration file over the values already in `cfg`.
pub fn parse(arena: std.mem.Allocator, text: []const u8, base: []const u8, cfg: *server.Config) Error!void {
    var dbs: std.ArrayList(server.DbMap) = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, cut(raw), " \t\r");
        if (line.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse return error.BadLine;
        const key = std.mem.trim(u8, line[0..eq], " \t");
        const val = unquote(line[eq + 1 ..]);
        if (std.mem.startsWith(u8, key, "database")) {
            const name = unquote(std.mem.trim(u8, key["database".len..], " \t"));
            if (name.len == 0 or !server.validName(name)) return error.BadValue;
            const path = if (std.fs.path.isAbsolute(val) or base.len == 0) try arena.dupe(u8, val) else try std.fmt.allocPrint(arena, "{s}/{s}", .{ base, val });
            try dbs.append(arena, .{ .name = name, .path = path });
        } else if (std.mem.eql(u8, key, "port")) {
            cfg.pg_port = std.fmt.parseInt(u16, val, 10) catch return error.BadValue;
        } else if (std.mem.eql(u8, key, "control_port")) {
            if (std.mem.eql(u8, val, "off")) cfg.ewp = false else cfg.port = std.fmt.parseInt(u16, val, 10) catch return error.BadValue;
        } else if (std.mem.eql(u8, key, "host")) {
            cfg.host = val;
        } else if (std.mem.eql(u8, key, "data")) {
            cfg.data_dir = val;
        } else if (std.mem.eql(u8, key, "user")) {
            cfg.user = val;
        } else if (std.mem.eql(u8, key, "password")) {
            cfg.password = val;
        } else if (std.mem.eql(u8, key, "token")) {
            cfg.token = val;
        } else if (std.mem.eql(u8, key, "auth")) {
            cfg.auth = std.meta.stringToEnum(pgserver.Auth, val) orelse return error.BadValue;
        } else if (std.mem.eql(u8, key, "test")) {
            cfg.test_mode = try truth(val);
        } else if (std.mem.eql(u8, key, "lease")) {
            cfg.lease_ms = (std.fmt.parseInt(u32, val, 10) catch return error.BadValue) * 1000;
        } else return error.BadLine;
    }
    if (dbs.items.len > 0) cfg.databases = try dbs.toOwnedSlice(arena);
}

// Zig tip: a `test` block is compiled only by `zig build test`; `try std.testing.expect…` fails the test, with the values,
// when a check is false.
test "a configuration file" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var cfg: server.Config = .{};
    try parse(arena.allocator(),
        \\# a test
        \\port = 5433          ** the PostgreSQL port
        \\user = "eve"
        \\password = "se#cret"
        \\auth = "md5"
        \\test = true
        \\control_port = off
        \\database "shop" = "data/shop.duckdb"
        \\database "log" = "log.duckdb"
    , "cfgdir", &cfg);
    try std.testing.expectEqual(@as(u16, 5433), cfg.pg_port);
    try std.testing.expectEqualStrings("se#cret", cfg.password);
    try std.testing.expect(cfg.auth == .md5 and cfg.test_mode and !cfg.ewp);
    try std.testing.expectEqual(@as(usize, 2), cfg.databases.len);
    try std.testing.expectEqualStrings("cfgdir/data/shop.duckdb", cfg.databases[0].path);
    try std.testing.expectEqualStrings("cfgdir/log.duckdb", cfg.databases[1].path);
    try std.testing.expectError(error.BadLine, parse(arena.allocator(), "colour = red", "", &cfg));
    try std.testing.expectError(error.BadValue, parse(arena.allocator(), "auth = secret", "", &cfg));
}
