//! @eve-module evevm.db.driver
//! @spec spec/library/database.md
//! @decision D-200
//! @tests code/evevm/src/db/driver.zig
//! The table of the drivers of `database.connect`. A driver is one value of `Driver`: it says which URLs are its own, opens
//! a connection, owns the connection objects it made, finishes the transactions of a job and closes what the run left open.
//! `eve.cfg` maps a name to a URL (`database "shop" = "postgres://eve@host/shop"`) and the scheme of the URL chooses the driver.
//!
//! To add a driver: write its file with the functions of `Driver`, make a `pub const driver: Driver` in it, and add it to
//! `table` below. Nothing else in the interpreter or in the database layer changes.
const std = @import("std");
const Io = std.Io;
const evecm = @import("evecm");
const value = evecm.value;
const data = evecm.data;
const Host = @import("../host.zig").Host;
const conn = @import("conn.zig");
const pgdriver = @import("pgdriver.zig");
const ewpdriver = @import("ewpdriver.zig");

const Node = evecm.ast.Node;
const Value = value.Value;
const Object = value.Object;
const Signal = value.Signal;

/// What a driver offers. Every function takes the `Host` of the interpreter that makes the call.
pub const Driver = struct {
    /// The scheme as written in `eve.cfg`, without `://`: `sqlite`, `postgres`, `evedb`.
    scheme: []const u8,
    /// Is the URL one of this driver's?
    is_url: *const fn ([]const u8) bool,
    /// `database.connect(name)` for a name whose URL is this driver's: the name and the URL.
    connect: *const fn (Host, []const u8, []const u8) Signal!Value,
    /// Is the value a connection object that this driver made?
    is_object: *const fn (Host, Value) bool,
    /// A method of one of its connection objects.
    call: *const fn (Host, *Object, []const u8, []const *const Node) Signal!Value,
    /// At `done`: commit what the job began on its connections, or roll it back (`false`).
    finish_transactions: *const fn (Host, bool) void,
    /// At the end of the run: close the connections that the script left open.
    close_all: *const fn (Host) void,
};

/// The drivers, in the order they are asked. A URL belongs to the first driver whose `is_url` says yes.
pub const table = [_]Driver{ conn.driver, pgdriver.driver, ewpdriver.driver };

// @eve-impl the schemes for the message of a URL that no driver knows: `sqlite://, postgres://, evedb://`
const schemes = blk: {
    var s: []const u8 = "";
    for (table, 0..) |d, i| s = s ++ (if (i == 0) "" else ", ") ++ d.scheme ++ "://";
    break :blk s;
};

/// `database.connect(name)`: the `Connection` of the name; the database is opened once per run.
// @eve-fn database.connect
// @spec spec/library/database.md
pub fn connect(it: Host, args: []const *const Node) Signal!Value {
    if (args.len != 1) return it.fail("database.connect takes the name of a connection", .{});
    const name = try it.text(try it.eval(args[0]));
    const io = it.io() orelse return it.fail("database.connect: no input/output handle", .{});
    const cfg = Io.Dir.cwd().readFileAlloc(io, "eve.cfg", it.temp(), .limited(1 << 20)) catch
        return it.failWith(value.err_file, "database.connect: eve.cfg not found in the project folder", .{});
    const url = data.connectionUrl(cfg, name) orelse
        return it.failWith(value.err_key, "database.connect: no connection '{s}' in eve.cfg", .{name});
    inline for (table) |d| {
        if (d.is_url(url)) return d.connect(it, name, url);
    }
    return it.failWith(value.err_argument, "database.connect: '{s}' has no driver: the drivers are " ++ schemes, .{url});
}

/// Is the value a connection object of any driver?
pub fn isConnection(it: Host, v: Value) bool {
    inline for (table) |d| {
        if (d.is_object(it, v)) return true;
    }
    return false;
}

/// A method of a connection object: `script`, `execute!`, `query!`, `query_one!`, `close`, ...
pub fn connectionCall(it: Host, obj: *Object, name: []const u8, args: []const *const Node) Signal!Value {
    inline for (table) |d| {
        if (d.is_object(it, .{ .object = obj })) return d.call(it, obj, name, args);
    }
    return it.fail("{s}: not a connection of any driver", .{name});
}

/// At `done`: every driver commits or rolls back what the job began.
pub fn finishTransactions(it: Host, ok: bool) void {
    inline for (table) |d| d.finish_transactions(it, ok);
}

/// At the end of the run: every driver closes what the script left open.
pub fn closeAll(it: Host) void {
    inline for (table) |d| d.close_all(it);
}

// @test the table has one entry per scheme and every scheme is claimed by exactly its own driver
test "each url belongs to one driver" {
    const urls = [_][]const u8{ "sqlite://db/cache.db", "postgres://eve@localhost/shop", "postgresql://eve@localhost/shop", "evedb://localhost:8044/wh" };
    const owner = [_]usize{ 0, 1, 1, 2 };
    for (urls, owner) |u, want| {
        var hits: usize = 0;
        var who: usize = 0;
        inline for (table, 0..) |d, i| {
            if (d.is_url(u)) {
                hits += 1;
                who = i;
            }
        }
        try std.testing.expectEqual(@as(usize, 1), hits);
        try std.testing.expectEqual(want, who);
    }
    var none: usize = 0;
    inline for (table) |d| {
        if (d.is_url("mysql://localhost/x")) none += 1;
    }
    try std.testing.expectEqual(@as(usize, 0), none);
}
