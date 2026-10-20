//! Column batches of EWP-db (README.md section 5.5, D-187): the fast path between eve and evedb.
//!
//! A batch carries some rows of a result (or of a load) **column by column**, in the layout DuckDB and the `Memory` tables of
//! Eve already use: for each column a validity bitmap (bit `i` set = row `i` holds a value, least significant bit first) and
//! then the values: one byte for a boolean, eight bytes (little endian) for an integer, a real, a date (days) or a timestamp
//! (micro seconds), and offsets plus one byte buffer for a text. A fixed-width column of a DuckDB vector is copied as it is,
//! and a fixed-width column of a `Memory` table is read back with one copy: no text, no per-value tag.
//!
//! This file holds the format only (no DuckDB, no Eve values), so the evedb program and the driver inside `eve` share it.
const std = @import("std");
const ewp = @import("ewp.zig");

/// The type of a column on the wire.
pub const Wire = enum(u8) {
    boolean = 1,
    int = 2,
    real = 3,
    text = 4,
    date = 5,
    timestamp = 6,
    /// a decimal as its text (`12.50`), exact
    decimal = 7,
    blob = 8,

    /// The bytes of one value of a fixed-width type, or null for the types sent as offsets and bytes.
    pub fn fixedWidth(self: Wire) ?usize {
        return switch (self) {
            .boolean => 1,
            .int, .real, .date, .timestamp => 8,
            .text, .decimal, .blob => null,
        };
    }
};

/// A column of the schema of a result or of a load.
pub const Head = struct { name: []const u8, wire: Wire };

/// The number of rows a producer puts in one batch when it decides (the last one may be smaller).
pub const batch_rows: usize = 16384;

/// The bytes of a validity bitmap of `n` rows.
pub fn validityBytes(n: usize) usize {
    return (n + 7) / 8;
}

/// Write a schema (frame `SCHEMA`, or the head of `LOAD`).
pub fn writeSchema(b: *ewp.Builder, cols: []const Head) !void {
    try b.u16_(@intCast(cols.len));
    for (cols) |c| {
        try b.string(c.name);
        try b.u8_(@intFromEnum(c.wire));
    }
}

/// Read a schema; the names are slices of the payload.
pub fn readSchema(c: *ewp.Cursor, a: std.mem.Allocator) ![]Head {
    const n = try c.u16_();
    const cols = try a.alloc(Head, n);
    for (cols) |*h| {
        const name = try c.string();
        const w = std.enums.fromInt(Wire, try c.u8_()) orelse return error.BadValue;
        h.* = .{ .name = name, .wire = w };
    }
    return cols;
}

/// One column of a decoded batch: views into the payload (unaligned, read with `readInt` or copied with `@memcpy`).
pub const View = struct {
    /// null: every row holds a value
    valid: ?[]const u8,
    /// the values of a fixed-width column (`n * width` bytes)
    fixed: []const u8 = &.{},
    /// the offsets (`(n + 1) * 4` bytes) and the bytes of a text column
    offs: []const u8 = &.{},
    bytes: []const u8 = &.{},

    pub fn isValid(self: View, row: usize) bool {
        const v = self.valid orelse return true;
        return (v[row / 8] >> @intCast(row % 8)) & 1 == 1;
    }

    pub fn int(self: View, row: usize) i64 {
        return std.mem.readInt(i64, self.fixed[row * 8 ..][0..8], .little);
    }

    pub fn real(self: View, row: usize) f64 {
        return @bitCast(std.mem.readInt(u64, self.fixed[row * 8 ..][0..8], .little));
    }

    pub fn boolean(self: View, row: usize) bool {
        return self.fixed[row] != 0;
    }

    pub fn text(self: View, row: usize) []const u8 {
        const a = std.mem.readInt(u32, self.offs[row * 4 ..][0..4], .little);
        const b = std.mem.readInt(u32, self.offs[(row + 1) * 4 ..][0..4], .little);
        return self.bytes[a..b];
    }
};

/// Read a batch: the number of rows and a view of each column.
pub fn readBatch(c: *ewp.Cursor, a: std.mem.Allocator, cols: []const Head) !struct { rows: usize, views: []View } {
    const n: usize = try c.u32_();
    const views = try a.alloc(View, cols.len);
    for (cols, views) |h, *v| {
        const flag = try c.u8_();
        v.* = .{ .valid = if (flag == 1) try c.take(validityBytes(n)) else null };
        if (h.wire.fixedWidth()) |w| {
            v.fixed = try c.take(n * w);
        } else {
            v.offs = try c.take((n + 1) * 4);
            const total = std.mem.readInt(u32, v.offs[n * 4 ..][0..4], .little);
            v.bytes = try c.take(total);
        }
    }
    return .{ .rows = n, .views = views };
}

test "a batch written by hand is read back" {
    const gpa = std.testing.allocator;
    var b = ewp.Builder.init(gpa);
    defer b.deinit();
    const cols = [_]Head{ .{ .name = "id", .wire = .int }, .{ .name = "name", .wire = .text } };
    try b.u32_(3);
    // id: all valid, 1 2 3
    try b.u8_(0);
    for ([_]i64{ 1, 2, 3 }) |v| try b.i64_(v);
    // name: row 1 is NULL
    try b.u8_(1);
    try b.u8_(0b101);
    for ([_]u32{ 0, 3, 3, 6 }) |o| try b.u32_(o);
    try b.buf.appendSlice(gpa, "annbob");
    var c: ewp.Cursor = .{ .buf = b.buf.items };
    const got = try readBatch(&c, gpa, &cols);
    defer gpa.free(got.views);
    try std.testing.expectEqual(@as(usize, 3), got.rows);
    try std.testing.expectEqual(@as(i64, 3), got.views[0].int(2));
    try std.testing.expect(!got.views[1].isValid(1));
    try std.testing.expectEqualStrings("bob", got.views[1].text(2));
    try std.testing.expect(c.done());
}
