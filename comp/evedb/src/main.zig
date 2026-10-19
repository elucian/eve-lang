//! `evedb`: the Eve test database (README.md). The commands of section 9: `serve`, `create`, `sql`, `describe`, `snapshot`,
//! `reset`, `status`, `stop`; with no command it runs a self-check of the DuckDB library.
const std = @import("std");
const Io = std.Io;

const duckdb = @import("duckdb.zig");
const protocol = @import("ewp_protocol");
const ewp = protocol.ewp;
const types = @import("types.zig");
const fault = @import("fault.zig");
const server = @import("server.zig");
const client = protocol.client;
const cfgfile = @import("cfg.zig");
const pgserver = @import("pgserver.zig");

// Zig tip: `std_options` of the root file tunes the standard library at compile time. On Windows Zig 0.16 does not map a refused
// connection, and a Debug build would print a stack trace each time the server checks that its port is free (README.md section 9);
// the server handles that error itself, so the trace is turned off, as in `eve`.
pub const std_options: std.Options = .{ .unexpected_error_tracing = false };

/// The version of evedb itself (README.md section 12).
pub const version = "0.2.0";

// Zig tip: the server's `ready` callback has no state of its own, so it uses a global that `serve` sets before it starts:
// the writer of the standard output. It prints one line with the port that was bound, which a test reads to know where to
// connect (the port 0 asks the system for a free one).
var ready_out: ?*Io.Writer = null;

fn ready(ewp_port: u16, pg_port: u16, test_mode: bool) void {
    const w = ready_out orelse return;
    if (pg_port != 0) w.print("evedb: postgres on port {d}{s}\n", .{ pg_port, if (test_mode) " (test mode)" else "" }) catch {};
    if (ewp_port != 0) w.print("evedb: listening on port {d}{s}\n", .{ ewp_port, if (test_mode) " (test mode)" else "" }) catch {};
    w.flush() catch {};
}

const usage =
    \\usage: evedb serve [--config evedb.cfg] [--port 5432] [--control-port 8044] [--no-pg] [--host 127.0.0.1] [--data data]
    \\                    [--test] [--lease 30] [--token T] [--user U --password P --auth trust|password|md5]
    \\       evedb create <name> [--data data]
    \\       evedb sql [--data data] [--connect host:port [--token T]] <name> "<statement>"
    \\       evedb describe [--data data] <name> <table>
    \\       evedb snapshot [--data data] <name> <file>      evedb reset [--data data] <name> <file>
    \\       evedb status [--connect host:port] [--token T]  evedb stop [--connect host:port] [--token T]
    \\       evedb --version
    \\
;

const Opts = struct {
    /// The PostgreSQL port and the port of the EWP-db frames; null: the value of the configuration file or the default.
    pg_port: ?u16 = null,
    control_port: ?u16 = null,
    no_pg: bool = false,
    config: ?[]const u8 = null,
    user: ?[]const u8 = null,
    password: ?[]const u8 = null,
    auth: ?pgserver.Auth = null,
    port: u16 = 8044,
    host: []const u8 = "127.0.0.1",
    data: []const u8 = "data",
    connect: []const u8 = "127.0.0.1:8044",
    token: []const u8 = "",
    lease_s: u32 = 30,
    test_mode: bool = false,
    words: []const []const u8 = &.{},
};

fn parse(arena: std.mem.Allocator, args: []const []const u8, token_env: []const u8) !?Opts {
    var o: Opts = .{ .token = token_env };
    var words: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--test")) {
            o.test_mode = true;
        } else if (std.mem.eql(u8, a, "--no-pg")) {
            o.no_pg = true;
        } else if (std.mem.eql(u8, a, "--port") or std.mem.eql(u8, a, "--control-port") or std.mem.eql(u8, a, "--config") or std.mem.eql(u8, a, "--user") or std.mem.eql(u8, a, "--password") or std.mem.eql(u8, a, "--auth") or std.mem.eql(u8, a, "--host") or std.mem.eql(u8, a, "--data") or std.mem.eql(u8, a, "--connect") or std.mem.eql(u8, a, "--token") or std.mem.eql(u8, a, "--lease")) {
            i += 1;
            if (i >= args.len) return null;
            if (std.mem.eql(u8, a, "--port")) o.pg_port = std.fmt.parseInt(u16, args[i], 10) catch return null;
            if (std.mem.eql(u8, a, "--control-port")) o.control_port = std.fmt.parseInt(u16, args[i], 10) catch return null;
            if (std.mem.eql(u8, a, "--config")) o.config = args[i];
            if (std.mem.eql(u8, a, "--user")) o.user = args[i];
            if (std.mem.eql(u8, a, "--password")) o.password = args[i];
            if (std.mem.eql(u8, a, "--auth")) o.auth = std.meta.stringToEnum(pgserver.Auth, args[i]) orelse return null;
            if (std.mem.eql(u8, a, "--host")) o.host = args[i];
            if (std.mem.eql(u8, a, "--data")) o.data = args[i];
            if (std.mem.eql(u8, a, "--connect")) o.connect = args[i];
            if (std.mem.eql(u8, a, "--token")) o.token = args[i];
            if (std.mem.eql(u8, a, "--lease")) o.lease_s = std.fmt.parseInt(u32, args[i], 10) catch return null;
        } else try words.append(arena, a);
    }
    o.words = words.items;
    return o;
}

fn dbFile(arena: std.mem.Allocator, o: Opts, name: []const u8) ![:0]u8 {
    if (!server.validName(name)) return error.BadName;
    return std.fmt.allocPrintSentinel(arena, "{s}/{s}.duckdb", .{ o.data, name }, 0);
}

fn openDirect(arena: std.mem.Allocator, io: Io, o: Opts, name: []const u8) !struct { db: duckdb.Database, conn: duckdb.Connection } {
    const path = try dbFile(arena, o, name);
    Io.Dir.cwd().createDirPath(io, o.data) catch {};
    var db = try duckdb.Database.open(path);
    errdefer db.close();
    const conn = try db.connect();
    return .{ .db = db, .conn = conn };
}

// Zig tip: a result is printed as text cells with a tab between them, the first line holds the column names. `Result.text`
// turns any cell into text (NULL is `null`, printed as NULL), so the command works for every type.
fn printResult(arena: std.mem.Allocator, out: *Io.Writer, res: *duckdb.Result) !void {
    const ncols = res.columnCount();
    if (ncols == 0) return;
    for (0..ncols) |c| {
        if (c > 0) try out.writeByte('\t');
        try out.writeAll(res.columnName(c));
    }
    try out.writeByte('\n');
    for (0..res.rowCount()) |r| {
        for (0..ncols) |c| {
            if (c > 0) try out.writeByte('\t');
            if (try res.text(arena, c, r)) |t| try out.writeAll(t) else try out.writeAll("NULL");
        }
        try out.writeByte('\n');
    }
}

fn copyFile(io: Io, arena: std.mem.Allocator, from: []const u8, to: []const u8) !void {
    const bytes = try Io.Dir.cwd().readFileAlloc(io, from, arena, .limited(1 << 32));
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = to, .data = bytes });
}

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const io = init.io;
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .initStreaming(.stdout(), io, &stdout_buffer);
    const out = &stdout_file_writer.interface;
    defer out.flush() catch {};
    const args = try init.minimal.args.toSlice(arena);
    const rest = args[@min(1, args.len)..];
    if (rest.len == 0) {
        // the self-check of version 0.0.1: the library loads and answers
        var db = try duckdb.Database.open(null);
        defer db.close();
        var conn = try db.connect();
        defer conn.close();
        var res = try conn.query("select 40 + 2");
        defer res.deinit();
        try out.print("evedb {s}, DuckDB {s}, self-check {d}\n", .{ version, duckdb.libVersion(), res.int(0, 0) });
        return 0;
    }
    if (std.mem.eql(u8, rest[0], "--version") or std.mem.eql(u8, rest[0], "-v")) {
        try out.print("evedb {s}, DuckDB {s}\n", .{ version, duckdb.libVersion() });
        return 0;
    }
    const token_env = init.environ_map.get("EVEDB_TOKEN") orelse "";
    const o = (try parse(arena, rest[1..], token_env)) orelse {
        try out.writeAll(usage);
        return 64;
    };
    const cmd = rest[0];
    const w = o.words;

    if (std.mem.eql(u8, cmd, "serve")) {
        // the configuration file first, then the options of the command line over it (README.md 5A.3)
        var cfg: server.Config = .{};
        if (o.config) |path| {
            const text = Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(1 << 20)) catch {
                try out.print("evedb: cannot read the configuration file {s}\n", .{path});
                return 66;
            };
            const base = std.fs.path.dirname(path) orelse "";
            cfgfile.parse(arena, text, base, &cfg) catch |e| {
                try out.print("evedb: {s}: {s}\n", .{ path, @errorName(e) });
                return 65;
            };
        }
        if (o.pg_port) |v| cfg.pg_port = v;
        if (o.control_port) |v| cfg.port = v;
        if (o.no_pg) cfg.pg = false;
        if (o.user) |v| cfg.user = v;
        if (o.password) |v| cfg.password = v;
        if (o.auth) |v| cfg.auth = v;
        if (o.test_mode) cfg.test_mode = true;
        if (o.token.len > 0) cfg.token = o.token;
        if (o.lease_s != 30) cfg.lease_ms = o.lease_s * 1000;
        if (!std.mem.eql(u8, o.data, "data")) cfg.data_dir = o.data;
        if (!std.mem.eql(u8, o.host, "127.0.0.1")) cfg.host = o.host;
        // test mode listens on the local computer only
        if (cfg.test_mode) cfg.host = "127.0.0.1";
        // the EWP-db port is the control port of the tests: outside test mode it opens only with a token
        if (!cfg.test_mode and cfg.token.len == 0) cfg.ewp = false;
        if (cfg.auth != .trust and cfg.password.len == 0) {
            try out.writeAll("evedb: the authentication mode needs a password (password = \"...\" in the configuration file, or --password)\n");
            return 64;
        }
        if (!cfg.test_mode and cfg.auth == .trust and cfg.token.len == 0 and !std.mem.eql(u8, cfg.host, "127.0.0.1")) {
            try out.writeAll("evedb: a server that is not on 127.0.0.1 needs auth = md5 or password, or a token\n");
            return 64;
        }
        var srv: server.Server = .{ .gpa = std.heap.smp_allocator, .io = io, .cfg = cfg };
        ready_out = out;
        server.run(&srv, ready) catch |e| {
            if (e == error.AddressInUse) {
                try out.print("evedb: a server runs already on {s} port {d} or {d}\n", .{ srv.cfg.host, srv.cfg.pg_port, srv.cfg.port });
                return 75;
            }
            try out.print("evedb: cannot serve on {s}: {s}\n", .{ srv.cfg.host, @errorName(e) });
            return 69;
        };
        try out.writeAll("evedb: stopped\n");
        return 0;
    }
    if (std.mem.eql(u8, cmd, "create") and w.len == 1) {
        var d = openDirect(arena, io, o, w[0]) catch |e| {
            try out.print("evedb: cannot create {s}: {s}\n", .{ w[0], @errorName(e) });
            return 66;
        };
        defer d.db.close();
        defer d.conn.close();
        try d.conn.exec("create table if not exists eve_tx (id varchar primary key, committed timestamp)");
        try out.print("evedb: database {s} is in {s}\n", .{ w[0], o.data });
        return 0;
    }
    if (std.mem.eql(u8, cmd, "sql") and w.len == 2) {
        if (!std.mem.eql(u8, o.connect, "127.0.0.1:8044") or hasFlag(rest, "--connect")) {
            const c = client.Conn.connect(io, arena, o.connect, o.token) catch {
                try out.print("evedb: no server at {s}\n", .{o.connect});
                return 69;
            };
            defer c.deinit();
            _ = c.open(w[0]) catch {
                try out.print("evedb: cannot open {s}: {s}\n", .{ w[0], c.err_msg });
                return 66;
            };
            const rows = c.query(arena, w[1], &.{}, 0) catch {
                try out.print("evedb: error {s}: {s}\n", .{ c.err_class, c.err_msg });
                return 65;
            };
            for (rows.names, 0..) |n, i| {
                if (i > 0) try out.writeByte('\t');
                try out.writeAll(n);
            }
            try out.writeByte('\n');
            for (0..rows.rowCount()) |r| {
                for (0..rows.names.len) |i| {
                    if (i > 0) try out.writeByte('\t');
                    try client.writeValue(out, rows.cells[r * rows.names.len + i]);
                }
                try out.writeByte('\n');
            }
            return 0;
        }
        var d = openDirect(arena, io, o, w[0]) catch |e| {
            try out.print("evedb: cannot open {s}: {s}\n", .{ w[0], @errorName(e) });
            return 66;
        };
        defer d.db.close();
        defer d.conn.close();
        const sql = try arena.dupeSentinel(u8, w[1], 0);
        var res = d.conn.query(sql) catch {
            try out.print("evedb: error: {s}\n", .{d.conn.lastError()});
            return 65;
        };
        defer res.deinit();
        try printResult(arena, out, &res);
        return 0;
    }
    if (std.mem.eql(u8, cmd, "describe") and w.len == 2) {
        if (!server.validName(w[1])) {
            try out.writeAll("evedb: a table name is letters, digits and _\n");
            return 64;
        }
        var d = openDirect(arena, io, o, w[0]) catch |e| {
            try out.print("evedb: cannot open {s}: {s}\n", .{ w[0], @errorName(e) });
            return 66;
        };
        defer d.db.close();
        defer d.conn.close();
        const sql = try std.fmt.allocPrintSentinel(arena, "select name, type, \"notnull\", pk from pragma_table_info('{s}')", .{w[1]}, 0);
        var res = d.conn.query(sql) catch {
            try out.print("evedb: error: {s}\n", .{d.conn.lastError()});
            return 65;
        };
        defer res.deinit();
        if (res.rowCount() == 0) {
            try out.print("evedb: there is no table {s}\n", .{w[1]});
            return 65;
        }
        try out.writeAll("name\teve type\tduckdb type\tnullable\tkey\n");
        for (0..res.rowCount()) |r| {
            const name = (try res.text(arena, 0, r)) orelse "";
            const ty = (try res.text(arena, 1, r)) orelse "";
            try out.print("{s}\t{s}\t{s}\t{s}\t{s}\n", .{ name, types.eveTypeOfName(ty), ty, if (res.boolean(2, r)) "no" else "yes", if (res.boolean(3, r)) "yes" else "no" });
        }
        return 0;
    }
    if ((std.mem.eql(u8, cmd, "snapshot") or std.mem.eql(u8, cmd, "reset")) and w.len == 2) {
        const path = dbFile(arena, o, w[0]) catch {
            try out.writeAll("evedb: a database name is letters, digits and _\n");
            return 64;
        };
        if (std.mem.eql(u8, cmd, "snapshot")) {
            {
                var d = openDirect(arena, io, o, w[0]) catch |e| {
                    try out.print("evedb: cannot open {s}: {s}\n", .{ w[0], @errorName(e) });
                    return 66;
                };
                defer d.db.close();
                defer d.conn.close();
                d.conn.exec("checkpoint") catch {};
            }
            copyFile(io, arena, path, w[1]) catch |e| {
                try out.print("evedb: cannot copy: {s}\n", .{@errorName(e)});
                return 73;
            };
            try out.print("evedb: snapshot of {s} in {s}\n", .{ w[0], w[1] });
        } else {
            const wal = try std.fmt.allocPrint(arena, "{s}.wal", .{path});
            Io.Dir.cwd().deleteFile(io, wal) catch {};
            copyFile(io, arena, w[1], path) catch |e| {
                try out.print("evedb: cannot copy: {s}\n", .{@errorName(e)});
                return 66;
            };
            try out.print("evedb: {s} reset from {s}\n", .{ w[0], w[1] });
        }
        return 0;
    }
    if ((std.mem.eql(u8, cmd, "status") or std.mem.eql(u8, cmd, "stop")) and w.len == 0) {
        const c = client.Conn.connect(io, arena, o.connect, o.token) catch {
            try out.print("evedb: no server at {s}\n", .{o.connect});
            return 69;
        };
        defer c.deinit();
        if (std.mem.eql(u8, cmd, "stop")) {
            c.stop() catch {
                try out.print("evedb: {s}\n", .{c.err_msg});
                return 77;
            };
            try out.writeAll("evedb: stopping\n");
            return 0;
        }
        const st = c.serverStat() catch {
            try out.print("evedb: {s}\n", .{c.err_msg});
            return 65;
        };
        try out.print("databases: {d}\nsessions: {d}\nopen transactions: {d}\nstatements: {d}\nuptime: {d} ms\n", .{ st[0], st[1], st[2], st[3], st[4] });
        return 0;
    }
    try out.writeAll(usage);
    return 64;
}

fn hasFlag(args: []const []const u8, flag: []const u8) bool {
    for (args) |a| if (std.mem.eql(u8, a, flag)) return true;
    return false;
}

// Zig tip: tests live only in files the compiler reaches; `_ = duckdb;` in an unnamed test block makes `zig build test`
// run the tests of every module that evedb is made of.
test {
    _ = duckdb;
    _ = ewp;
    _ = types;
    _ = @import("cells.zig");
    _ = fault;
    _ = server;
    _ = cfgfile;
    _ = pgserver;
    _ = client;
}
