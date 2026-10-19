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

// Zig tip: an `enum(u8)` gives each frame type its byte; the `_` at the end makes it non-exhaustive, so a byte that no
// frame uses can be held in the enum and answered with a `ProtocolError` instead of being undefined behaviour.
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

// Zig tip: a `struct` groups named fields, and may hold functions (its methods) and constants; a field with a default value
// may be left out when a value is made with `.{ ... }`.
/// One frame as read: the type, the stream number and the payload (owned by the allocator that read it).
pub const Frame = struct {
    kind: Type,
    stream: u32,
    payload: []u8,
};

// Zig tip: a value is a tagged union, one shape for each tag of section 5.2. A slice inside it (`string`, `bytes`) borrows
// the bytes of the frame, so a value read from a frame is valid as long as the frame is.
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

// Zig tip: `Builder` collects the payload of a frame in a growing list. Every method appends and returns nothing; the
// allocator is stored once, so the calls stay short. `buf.items` is the finished payload.
/// Builds the payload of a frame.
pub const Builder = struct {
    gpa: std.mem.Allocator,
    buf: std.ArrayList(u8) = .empty,

    // Zig tip: a plain function: the types of the parameters and of the result are written out, and Zig has no default
    // arguments, so a call always passes every parameter.
    pub fn init(gpa: std.mem.Allocator) Builder {
        return .{ .gpa = gpa };
    }

    // Zig tip: a function declared inside a struct whose first parameter is the struct (`self: *T`) is a method: `x.f()`
    // calls `f(&x)`.
    pub fn deinit(self: *Builder) void {
        self.buf.deinit(self.gpa);
    }

    // Zig tip: the result type `!T` (or `Error!T`) is an error union: a value or an error. `try f()` passes the error to
    // the caller; `f() catch …` handles it in place.
    pub fn u8_(self: *Builder, v: u8) !void {
        try self.buf.append(self.gpa, v);
    }

    // Zig tip: `u16_` relies on the same Zig feature as `u8_` above: see the tip there.
    pub fn u16_(self: *Builder, v: u16) !void {
        try self.buf.appendSlice(self.gpa, &std.mem.toBytes(std.mem.nativeToLittle(u16, v)));
    }

    // Zig tip: `u32_` relies on the same Zig feature as `u8_` above: see the tip there.
    pub fn u32_(self: *Builder, v: u32) !void {
        try self.buf.appendSlice(self.gpa, &std.mem.toBytes(std.mem.nativeToLittle(u32, v)));
    }

    // Zig tip: `u64_` relies on the same Zig feature as `u8_` above: see the tip there.
    pub fn u64_(self: *Builder, v: u64) !void {
        try self.buf.appendSlice(self.gpa, &std.mem.toBytes(std.mem.nativeToLittle(u64, v)));
    }

    // Zig tip: `i64_` relies on the same Zig feature as `u8_` above: see the tip there.
    pub fn i64_(self: *Builder, v: i64) !void {
        try self.u64_(@bitCast(v));
    }

    // Zig tip: `string` relies on the same Zig feature as `u8_` above: see the tip there.
    pub fn string(self: *Builder, s: []const u8) !void {
        try self.u32_(@intCast(s.len));
        try self.buf.appendSlice(self.gpa, s);
    }

    // Zig tip: `value` relies on the same Zig feature as `u8_` above: see the tip there.
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

// Zig tip: `Cursor` reads a payload from the front. Each read checks that the bytes are there and answers `error.Short`
// when they are not, so a frame that lies about a length can never read past its end. The slices it answers point into
// the payload, nothing is copied.
/// Reads the payload of a frame.
pub const Cursor = struct {
    buf: []const u8,
    pos: usize = 0,

    // Zig tip: `take` relies on the same Zig feature as `u8_` above: see the tip there.
    pub fn take(self: *Cursor, n: usize) Error![]const u8 {
        if (self.buf.len - self.pos < n) return error.Short;
        const s = self.buf[self.pos..][0..n];
        self.pos += n;
        return s;
    }

    // Zig tip: `u8_` relies on the same Zig feature as `u8_` above: see the tip there.
    pub fn u8_(self: *Cursor) Error!u8 {
        return (try self.take(1))[0];
    }

    // Zig tip: `u16_` relies on the same Zig feature as `u8_` above: see the tip there.
    pub fn u16_(self: *Cursor) Error!u16 {
        return std.mem.readInt(u16, (try self.take(2))[0..2], .little);
    }

    // Zig tip: `u32_` relies on the same Zig feature as `u8_` above: see the tip there.
    pub fn u32_(self: *Cursor) Error!u32 {
        return std.mem.readInt(u32, (try self.take(4))[0..4], .little);
    }

    // Zig tip: `u64_` relies on the same Zig feature as `u8_` above: see the tip there.
    pub fn u64_(self: *Cursor) Error!u64 {
        return std.mem.readInt(u64, (try self.take(8))[0..8], .little);
    }

    // Zig tip: `i64_` relies on the same Zig feature as `u8_` above: see the tip there.
    pub fn i64_(self: *Cursor) Error!i64 {
        return @bitCast(try self.u64_());
    }

    // Zig tip: `string` relies on the same Zig feature as `u8_` above: see the tip there.
    pub fn string(self: *Cursor) Error![]const u8 {
        const n = try self.u32_();
        return self.take(n);
    }

    // Zig tip: `value` relies on the same Zig feature as `u8_` above: see the tip there.
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

    // Zig tip: `done` relies on the same Zig feature as `deinit` above: see the tip there.
    pub fn done(self: *const Cursor) bool {
        return self.pos == self.buf.len;
    }
};

// Zig tip: `readSliceAll` fills a buffer completely or fails; the length is checked against the limit *before* memory is
// asked for, so a client cannot make the server allocate 4 GiB with four bytes. The frame header is 5 bytes after the
// length: the type and the stream number.
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

// Zig tip: `freeFrame` relies on the same Zig feature as `init` above: see the tip there.
pub fn freeFrame(gpa: std.mem.Allocator, f: Frame) void {
    gpa.free(f.payload);
}

// Zig tip: `writeFrame` relies on the same Zig feature as `u8_` above: see the tip there.
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

// Zig tip: a `test` block is compiled only by `zig build test`; `try std.testing.expect…` fails the test, with the values,
// when a check is false.
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

// Zig tip: test "a frame is written and read back, also when it arrives in pieces" relies on the same Zig feature as test
// "values round trip through the builder and the cursor" above: see the tip there.
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

// Zig tip: test "a frame that is too large or too short is refused before memory is asked for" relies on the same Zig
// feature as test "values round trip through the builder and the cursor" above: see the tip there.
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

// Zig tip: test "a cursor never reads past the end" relies on the same Zig feature as test "values round trip through the
// builder and the cursor" above: see the tip there.
test "a cursor never reads past the end" {
    var c: Cursor = .{ .buf = &.{ 5, 0, 0, 0, 'a' } };
    try std.testing.expectError(error.Short, c.string());
    var c2: Cursor = .{ .buf = &.{99} };
    try std.testing.expectError(error.BadValue, c2.value());
}
