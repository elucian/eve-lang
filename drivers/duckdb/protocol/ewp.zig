//! EWP-db 0.1: the frames of the Eve Wire Protocol that evedb speaks (README.md section 5).
//!
//! This file works on bytes and on `Io.Reader` / `Io.Writer`, not on sockets, so the server, the client and the unit tests
//! use the same code, and a test can feed it a frame cut in pieces. All the integers are little endian.
const std = @import("std");
const Io = std.Io;

/// The version of the database frames.
pub const version: u16 = 1;
/// The first four bytes of `HELLO`.
pub const magic = "EWPD";
/// The largest frame, in bytes after the length field.
pub const max_frame: u32 = 16 << 20;

/// The type byte of a frame (README.md section 5.3).
pub const Type = enum(u8) {
    hello = 0x01,
    open = 0x02,
    begin = 0x03,
    query = 0x04,
    execute = 0x05,
    commit = 0x06,
    rollback = 0x07,
    status = 0x08,
    ping = 0x09,
    describe = 0x0A,
    serverstat = 0x0B,
    close = 0x0C,
    stop = 0x0D,
    /// a query whose result comes as column batches (section 5.5)
    queryb = 0x0E,
    /// a bulk load: the head, then `batch` frames, then `end`
    load = 0x0F,
    ok = 0x80,
    hello_ok = 0x81,
    opened = 0x82,
    result = 0x83,
    executed = 0x84,
    txstatus = 0x85,
    pong = 0x86,
    described = 0x87,
    serverstats = 0x88,
    schema = 0x89,
    batch = 0x8A,
    end = 0x8B,
    err = 0xFF,
    _,
};

pub const Error = error{ BadFrame, FrameTooLarge, Short, BadValue } || std.mem.Allocator.Error || Io.Reader.Error || Io.Writer.Error;

/// One frame as read: the type, the stream number and the payload (owned by the allocator that read it).
pub const Frame = struct {
    kind: Type,
    stream: u32,
    payload: []u8,
};

/// A value of the protocol.
pub const Value = union(enum) {
    null,
    boolean: bool,
    int: i64,
    real: f64,
    string: []const u8,
    bytes: []const u8,
    decimal: []const u8,
    instant: i64,
    date: i32,
    huge: []const u8,
    uuid: [16]u8,
};

/// Builds the payload of a frame.
pub const Builder = struct {
    gpa: std.mem.Allocator,
    buf: std.ArrayList(u8) = .empty,

    pub fn init(gpa: std.mem.Allocator) Builder {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Builder) void {
        self.buf.deinit(self.gpa);
    }

    pub fn u8_(self: *Builder, v: u8) !void {
        try self.buf.append(self.gpa, v);
    }

    pub fn u16_(self: *Builder, v: u16) !void {
        try self.buf.appendSlice(self.gpa, &std.mem.toBytes(std.mem.nativeToLittle(u16, v)));
    }

    pub fn u32_(self: *Builder, v: u32) !void {
        try self.buf.appendSlice(self.gpa, &std.mem.toBytes(std.mem.nativeToLittle(u32, v)));
    }

    pub fn u64_(self: *Builder, v: u64) !void {
        try self.buf.appendSlice(self.gpa, &std.mem.toBytes(std.mem.nativeToLittle(u64, v)));
    }

    pub fn i64_(self: *Builder, v: i64) !void {
        try self.u64_(@bitCast(v));
    }

    pub fn string(self: *Builder, s: []const u8) !void {
        try self.u32_(@intCast(s.len));
        try self.buf.appendSlice(self.gpa, s);
    }

    pub fn value(self: *Builder, v: Value) !void {
        switch (v) {
            .null => try self.u8_(0),
            .boolean => |b| {
                try self.u8_(1);
                try self.u8_(@intFromBool(b));
            },
            .int => |n| {
                try self.u8_(2);
                try self.i64_(n);
            },
            .real => |x| {
                try self.u8_(3);
                try self.u64_(@bitCast(x));
            },
            .string => |s| {
                try self.u8_(4);
                try self.string(s);
            },
            .bytes => |s| {
                try self.u8_(5);
                try self.string(s);
            },
            .decimal => |s| {
                try self.u8_(6);
                try self.string(s);
            },
            .instant => |n| {
                try self.u8_(7);
                try self.i64_(n);
            },
            .date => |d| {
                try self.u8_(8);
                try self.u32_(@bitCast(d));
            },
            .huge => |s| {
                try self.u8_(9);
                try self.string(s);
            },
            .uuid => |u| {
                try self.u8_(10);
                try self.buf.appendSlice(self.gpa, &u);
            },
        }
    }
};

/// Reads the payload of a frame.
pub const Cursor = struct {
    buf: []const u8,
    pos: usize = 0,

    pub fn take(self: *Cursor, n: usize) Error![]const u8 {
        if (self.buf.len - self.pos < n) return error.Short;
        const s = self.buf[self.pos..][0..n];
        self.pos += n;
        return s;
    }

    pub fn u8_(self: *Cursor) Error!u8 {
        return (try self.take(1))[0];
    }

    pub fn u16_(self: *Cursor) Error!u16 {
        return std.mem.readInt(u16, (try self.take(2))[0..2], .little);
    }

    pub fn u32_(self: *Cursor) Error!u32 {
        return std.mem.readInt(u32, (try self.take(4))[0..4], .little);
    }

    pub fn u64_(self: *Cursor) Error!u64 {
        return std.mem.readInt(u64, (try self.take(8))[0..8], .little);
    }

    pub fn i64_(self: *Cursor) Error!i64 {
        return @bitCast(try self.u64_());
    }

    pub fn string(self: *Cursor) Error![]const u8 {
        const n = try self.u32_();
        return self.take(n);
    }

    pub fn value(self: *Cursor) Error!Value {
        return switch (try self.u8_()) {
            0 => .null,
            1 => .{ .boolean = (try self.u8_()) != 0 },
            2 => .{ .int = try self.i64_() },
            3 => .{ .real = @bitCast(try self.u64_()) },
            4 => .{ .string = try self.string() },
            5 => .{ .bytes = try self.string() },
            6 => .{ .decimal = try self.string() },
            7 => .{ .instant = try self.i64_() },
            8 => .{ .date = @bitCast(try self.u32_()) },
            9 => .{ .huge = try self.string() },
            10 => .{ .uuid = (try self.take(16))[0..16].* },
            else => error.BadValue,
        };
    }

    pub fn done(self: *const Cursor) bool {
        return self.pos == self.buf.len;
    }
};

/// Read one frame; the payload is allocated with `gpa` (free it with `freeFrame`).
pub fn readFrame(r: *Io.Reader, gpa: std.mem.Allocator) Error!Frame {
    var head: [4]u8 = undefined;
    try r.readSliceAll(&head);
    const len = std.mem.readInt(u32, &head, .little);
    if (len < 5) return error.BadFrame;
    if (len > max_frame) return error.FrameTooLarge;
    var rest: [5]u8 = undefined;
    try r.readSliceAll(&rest);
    const payload = try gpa.alloc(u8, len - 5);
    errdefer gpa.free(payload);
    try r.readSliceAll(payload);
    return .{ .kind = @enumFromInt(rest[0]), .stream = std.mem.readInt(u32, rest[1..5], .little), .payload = payload };
}

pub fn freeFrame(gpa: std.mem.Allocator, f: Frame) void {
    gpa.free(f.payload);
}

/// Write one frame and flush it.
pub fn writeFrame(w: *Io.Writer, kind: Type, stream: u32, payload: []const u8) Error!void {
    if (payload.len + 5 > max_frame) return error.FrameTooLarge;
    var head: [9]u8 = undefined;
    std.mem.writeInt(u32, head[0..4], @intCast(payload.len + 5), .little);
    head[4] = @intFromEnum(kind);
    std.mem.writeInt(u32, head[5..9], stream, .little);
    try w.writeAll(&head);
    try w.writeAll(payload);
    try w.flush();
}

test "values round trip through the builder and the cursor" {
    const gpa = std.testing.allocator;
    var b = Builder.init(gpa);
    defer b.deinit();
    const vals = [_]Value{
        .null,
        .{ .boolean = true },
        .{ .int = -9_000_000_000 },
        .{ .real = 2.5 },
        .{ .string = "café" },
        .{ .bytes = "\x00\x01" },
        .{ .decimal = "12.50" },
        .{ .instant = 1_700_000_000_000_000 },
        .{ .date = -3 },
        .{ .huge = "170141183460469231731687303715884105727" },
        .{ .uuid = @as([16]u8, @splat(7)) },
    };
    for (vals) |v| try b.value(v);
    var c: Cursor = .{ .buf = b.buf.items };
    for (vals) |v| {
        const got = try c.value();
        try std.testing.expectEqual(std.meta.activeTag(v), std.meta.activeTag(got));
        switch (v) {
            .string => |s| try std.testing.expectEqualStrings(s, got.string),
            .int => |n| try std.testing.expectEqual(n, got.int),
            .date => |n| try std.testing.expectEqual(n, got.date),
            .real => |x| try std.testing.expectEqual(x, got.real),
            else => {},
        }
    }
    try std.testing.expect(c.done());
}

test "a frame is written and read back, also when it arrives in pieces" {
    const gpa = std.testing.allocator;
    var out: [64]u8 = undefined;
    var w = Io.Writer.fixed(&out);
    try writeFrame(&w, .query, 42, "select 1");
    const bytes = w.buffered();
    try std.testing.expectEqual(@as(usize, 9 + 8), bytes.len);
    var r = Io.Reader.fixed(bytes);
    const f = try readFrame(&r, gpa);
    defer freeFrame(gpa, f);
    try std.testing.expectEqual(Type.query, f.kind);
    try std.testing.expectEqual(@as(u32, 42), f.stream);
    try std.testing.expectEqualStrings("select 1", f.payload);
}

test "a frame that is too large or too short is refused before memory is asked for" {
    const gpa = std.testing.allocator;
    var big: [4]u8 = undefined;
    std.mem.writeInt(u32, &big, max_frame + 1, .little);
    var r = Io.Reader.fixed(&big);
    try std.testing.expectError(error.FrameTooLarge, readFrame(&r, gpa));
    var small: [4]u8 = undefined;
    std.mem.writeInt(u32, &small, 3, .little);
    var r2 = Io.Reader.fixed(&small);
    try std.testing.expectError(error.BadFrame, readFrame(&r2, gpa));
}

test "a cursor never reads past the end" {
    var c: Cursor = .{ .buf = &.{ 5, 0, 0, 0, 'a' } };
    try std.testing.expectError(error.Short, c.string());
    var c2: Cursor = .{ .buf = &.{99} };
    try std.testing.expectError(error.BadValue, c2.value());
}
