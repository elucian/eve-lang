//! A client of the frames of section 5, for `evedb sql --connect`, `evedb status`, `evedb stop` and the Zig tests.
const std = @import("std");
const Io = std.Io;
const net = Io.net;
const ewp = @import("ewp.zig");

pub const Error = error{ Connect, Server, Protocol } || ewp.Error;

/// The rows of a `RESULT`, all owned by the arena the call was given.
pub const Rows = struct {
    names: [][]const u8,
    types: [][]const u8,
    /// Row after row: `cells[row * names.len + col]`.
    cells: []ewp.Value,
    truncated: bool,

    pub fn rowCount(self: Rows) usize {
        return if (self.names.len == 0) 0 else self.cells.len / self.names.len;
    }
};

/// An open connection.
pub const Conn = struct {
    io: Io,
    gpa: std.mem.Allocator,
    stream: net.Stream,
    rbuf: []u8,
    wbuf: []u8,
    reader: net.Stream.Reader,
    writer: net.Stream.Writer,
    next: u32 = 1,
    /// The last error frame: class, SQL state, message (owned by `gpa`).
    err_class: []u8 = &.{},
    err_state: []u8 = &.{},
    err_msg: []u8 = &.{},
    err_transient: bool = false,

    /// Connect to `host:port` and say `HELLO` with the token.
    pub fn connect(io: Io, gpa: std.mem.Allocator, host_port: []const u8, token: []const u8) Error!*Conn {
        const colon = std.mem.lastIndexOfScalar(u8, host_port, ':') orelse return error.Connect;
        const port = std.fmt.parseInt(u16, host_port[colon + 1 ..], 10) catch return error.Connect;
        const host = if (std.mem.eql(u8, host_port[0..colon], "localhost")) "127.0.0.1" else host_port[0..colon];
        const addr = net.IpAddress.parse(host, port) catch return error.Connect;
        const stream = addr.connect(io, .{ .mode = .stream }) catch return error.Connect;
        const c = try gpa.create(Conn);
        errdefer gpa.destroy(c);
        const rbuf = try gpa.alloc(u8, 64 * 1024);
        errdefer gpa.free(rbuf);
        const wbuf = try gpa.alloc(u8, 8192);
        errdefer gpa.free(wbuf);
        c.* = .{ .io = io, .gpa = gpa, .stream = stream, .rbuf = rbuf, .wbuf = wbuf, .reader = stream.reader(io, rbuf), .writer = stream.writer(io, wbuf) };
        var b = ewp.Builder.init(gpa);
        defer b.deinit();
        try b.buf.appendSlice(gpa, ewp.magic);
        try b.u16_(ewp.version);
        try b.string("evedb-client");
        try b.string(token);
        const f = try c.request(.hello, b.buf.items);
        ewp.freeFrame(gpa, f);
        return c;
    }

    pub fn deinit(self: *Conn) void {
        self.stream.close(self.io);
        self.gpa.free(self.rbuf);
        self.gpa.free(self.wbuf);
        self.gpa.free(self.err_class);
        self.gpa.free(self.err_state);
        self.gpa.free(self.err_msg);
        self.gpa.destroy(self);
    }

    fn keepError(self: *Conn, f: ewp.Frame) void {
        var c: ewp.Cursor = .{ .buf = f.payload };
        const class = c.string() catch "";
        const state = c.string() catch "";
        const transient = (c.u8_() catch 0) != 0;
        const msg = c.string() catch "";
        self.gpa.free(self.err_class);
        self.gpa.free(self.err_state);
        self.gpa.free(self.err_msg);
        self.err_class = self.gpa.dupe(u8, class) catch &.{};
        self.err_state = self.gpa.dupe(u8, state) catch &.{};
        self.err_msg = self.gpa.dupe(u8, msg) catch &.{};
        self.err_transient = transient;
    }

    /// Send one frame and read the answer. An `ERROR` frame becomes `error.Server` with the details in `err_*`.
    pub fn request(self: *Conn, kind: ewp.Type, payload: []const u8) Error!ewp.Frame {
        const stream = self.next;
        self.next += 1;
        try ewp.writeFrame(&self.writer.interface, kind, stream, payload);
        const f = try ewp.readFrame(&self.reader.interface, self.gpa);
        if (f.kind == .err) {
            self.keepError(f);
            ewp.freeFrame(self.gpa, f);
            return error.Server;
        }
        if (f.stream != stream) {
            ewp.freeFrame(self.gpa, f);
            return error.Protocol;
        }
        return f;
    }

    /// Write the first frame of a new stream; answers the stream number.
    pub fn send(self: *Conn, kind: ewp.Type, payload: []const u8) Error!u32 {
        const stream = self.next;
        self.next += 1;
        try ewp.writeFrame(&self.writer.interface, kind, stream, payload);
        return stream;
    }

    /// Write one more frame on a stream that is open.
    pub fn sendOn(self: *Conn, kind: ewp.Type, stream: u32, payload: []const u8) Error!void {
        try ewp.writeFrame(&self.writer.interface, kind, stream, payload);
    }

    /// Read the next frame of `stream` (free it with `ewp.freeFrame(conn.gpa, f)`).
    pub fn receive(self: *Conn, stream: u32) Error!ewp.Frame {
        const f = try ewp.readFrame(&self.reader.interface, self.gpa);
        if (f.kind == .err) {
            self.keepError(f);
            ewp.freeFrame(self.gpa, f);
            return error.Server;
        }
        if (f.stream != stream) {
            ewp.freeFrame(self.gpa, f);
            return error.Protocol;
        }
        return f;
    }

    fn simple(self: *Conn, kind: ewp.Type, payload: []const u8) Error!void {
        const f = try self.request(kind, payload);
        ewp.freeFrame(self.gpa, f);
    }

    /// Open the database `name`; answers the session id.
    pub fn open(self: *Conn, name: []const u8) Error!u64 {
        var b = ewp.Builder.init(self.gpa);
        defer b.deinit();
        try b.string(name);
        try b.u32_(0);
        const f = try self.request(.open, b.buf.items);
        defer ewp.freeFrame(self.gpa, f);
        var c: ewp.Cursor = .{ .buf = f.payload };
        return c.u64_();
    }

    pub fn begin(self: *Conn, id: [16]u8, read_only: bool) Error!void {
        var b = ewp.Builder.init(self.gpa);
        defer b.deinit();
        try b.buf.appendSlice(self.gpa, &id);
        try b.u8_(0);
        try b.u8_(@intFromBool(read_only));
        try self.simple(.begin, b.buf.items);
    }

    pub fn commit(self: *Conn, id: [16]u8) Error!void {
        try self.simple(.commit, &id);
    }

    pub fn rollback(self: *Conn, id: [16]u8) Error!void {
        try self.simple(.rollback, &id);
    }

    pub fn ping(self: *Conn) Error!void {
        try self.simple(.ping, "");
    }

    pub fn stop(self: *Conn) Error!void {
        try self.simple(.stop, "");
    }

    /// 0 committed, 1 rolled back, 2 unknown, 3 in progress.
    pub fn status(self: *Conn, id: [16]u8) Error!u8 {
        const f = try self.request(.status, &id);
        defer ewp.freeFrame(self.gpa, f);
        var c: ewp.Cursor = .{ .buf = f.payload };
        return c.u8_();
    }

    /// Run a statement that changes rows; answers the rows changed.
    pub fn execute(self: *Conn, sql: []const u8, params: []const ewp.Value) Error!i64 {
        var b = ewp.Builder.init(self.gpa);
        defer b.deinit();
        try b.string(sql);
        try b.u32_(@intCast(params.len));
        for (params) |p| try b.value(p);
        const f = try self.request(.execute, b.buf.items);
        defer ewp.freeFrame(self.gpa, f);
        var c: ewp.Cursor = .{ .buf = f.payload };
        return c.i64_();
    }

    /// Run a query; the rows are allocated in `arena`.
    pub fn query(self: *Conn, arena: std.mem.Allocator, sql: []const u8, params: []const ewp.Value, limit: u32) Error!Rows {
        var b = ewp.Builder.init(self.gpa);
        defer b.deinit();
        try b.string(sql);
        try b.u32_(@intCast(params.len));
        for (params) |p| try b.value(p);
        try b.u32_(limit);
        const f = try self.request(.query, b.buf.items);
        defer ewp.freeFrame(self.gpa, f);
        var c: ewp.Cursor = .{ .buf = f.payload };
        const ncols = try c.u16_();
        const names = try arena.alloc([]const u8, ncols);
        const tys = try arena.alloc([]const u8, ncols);
        for (names, tys) |*n, *t| {
            n.* = try arena.dupe(u8, try c.string());
            t.* = try arena.dupe(u8, try c.string());
        }
        const nrows = try c.u32_();
        const cells = try arena.alloc(ewp.Value, @as(usize, nrows) * ncols);
        for (cells) |*cell| {
            const v = try c.value();
            // the strings of a value point into the frame, which is freed here: copy them into the arena
            cell.* = switch (v) {
                .string => |s| .{ .string = try arena.dupe(u8, s) },
                .bytes => |s| .{ .bytes = try arena.dupe(u8, s) },
                .decimal => |s| .{ .decimal = try arena.dupe(u8, s) },
                .huge => |s| .{ .huge = try arena.dupe(u8, s) },
                else => v,
            };
        }
        const truncated = (try c.u8_()) != 0;
        return .{ .names = names, .types = tys, .cells = cells, .truncated = truncated };
    }

    /// The counters of the server: databases, sessions, open transactions, statements, uptime in milliseconds.
    pub fn serverStat(self: *Conn) Error![5]u64 {
        const f = try self.request(.serverstat, "");
        defer ewp.freeFrame(self.gpa, f);
        var c: ewp.Cursor = .{ .buf = f.payload };
        return .{ try c.u32_(), try c.u32_(), try c.u32_(), try c.u64_(), try c.u64_() };
    }
};

/// Write a value as text, for the output of `evedb sql --connect`.
pub fn writeValue(w: *Io.Writer, v: ewp.Value) !void {
    switch (v) {
        .null => try w.writeAll("NULL"),
        .boolean => |b| try w.writeAll(if (b) "true" else "false"),
        .int => |n| try w.print("{d}", .{n}),
        .real => |x| try w.print("{d}", .{x}),
        .string, .decimal, .huge => |s| try w.writeAll(s),
        .bytes => |s| try w.print("<{d} bytes>", .{s.len}),
        .instant => |n| try w.print("{d}us", .{n}),
        .date => |d| try w.print("day {d}", .{d}),
        .uuid => |u| try w.print("{x}", .{u}),
    }
}
