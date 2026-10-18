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

// Zig tip: an `enum(u8)` gives each wire type its byte on the wire. `fixedWidth` is a method of the enum: an enum may hold
// functions like a struct, and `switch (self)` must name every value.
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

    // Zig tip: the result type `?T` is an optional: a value or `null`. The caller must unwrap it (`if (x) |v|`, `orelse`),
    // so a missing value can never be used by accident.
    /// The bytes of one value of a fixed-width type, or null for the types sent as offsets and bytes.
    pub fn fixedWidth(self: Wire) ?usize {
        return switch (self) {
            .boolean => 1,
            .int, .real, .date, .timestamp => 8,
            .text, .decimal, .blob => null,
        };
    }
};

// Zig tip: a `struct` groups named fields, and may hold functions (its methods) and constants; a field with a default value
// may be left out when a value is made with `.{ ... }`.
/// A column of the schema of a result or of a load.
pub const Head = struct { name: []const u8, wire: Wire };

/// The number of rows a producer puts in one batch when it decides (the last one may be smaller).
pub const batch_rows: usize = 16384;

// Zig tip: a plain function: the types of the parameters and of the result are written out, and Zig has no default
// arguments, so a call always passes every parameter.
/// The bytes of a validity bitmap of `n` rows.
pub fn validityBytes(n: usize) usize {
    return (n + 7) / 8;
}

// Zig tip: the schema is written once, before the first batch: the count of columns, then a name and a type byte for each.
/// Write a schema (frame `SCHEMA`, or the head of `LOAD`).
pub fn writeSchema(b: *ewp.Builder, cols: []const Head) !void {
    try b.u16_(@intCast(cols.len));
    for (cols) |c| {
        try b.string(c.name);
        try b.u8_(@intFromEnum(c.wire));
    }
}

// Zig tip: `std.enums.fromInt` turns a byte into an enum value, or null for a byte that is no value of the enum, so a wrong
// type on the wire is an error, never undefined behaviour.
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

// Zig tip: `View` relies on the same Zig feature as `Head` above: see the tip there.
/// One column of a decoded batch: views into the payload (unaligned, read with `readInt` or copied with `@memcpy`).
pub const View = struct {
    /// null: every row holds a value
    valid: ?[]const u8,
    /// the values of a fixed-width column (`n * width` bytes)
    fixed: []const u8 = &.{},
    /// the offsets (`(n + 1) * 4` bytes) and the bytes of a text column
    offs: []const u8 = &.{},
    bytes: []const u8 = &.{},

    // Zig tip: `isValid` relies on the same Zig feature as `View` above: see the tip there.
    pub fn isValid(self: View, row: usize) bool {
        const v = self.valid orelse return true;
        return (v[row / 8] >> @intCast(row % 8)) & 1 == 1;
    }

    // Zig tip: `std.mem.readInt(T, bytes, .big)` reads an integer of a given byte order from bytes, whatever the order of
    // the processor; `writeInt` writes one.
    pub fn int(self: View, row: usize) i64 {
        return std.mem.readInt(i64, self.fixed[row * 8 ..][0..8], .little);
    }

    // Zig tip: `real` relies on the same Zig feature as `int` above: see the tip there.
    pub fn real(self: View, row: usize) f64 {
        return @bitCast(std.mem.readInt(u64, self.fixed[row * 8 ..][0..8], .little));
    }

    // Zig tip: `boolean` relies on the same Zig feature as `validityBytes` above: see the tip there.
    pub fn boolean(self: View, row: usize) bool {
        return self.fixed[row] != 0;
    }

    // Zig tip: `text` relies on the same Zig feature as `int` above: see the tip there.
    pub fn text(self: View, row: usize) []const u8 {
        const a = std.mem.readInt(u32, self.offs[row * 4 ..][0..4], .little);
        const b = std.mem.readInt(u32, self.offs[(row + 1) * 4 ..][0..4], .little);
        return self.bytes[a..b];
    }
};

// Zig tip: decoding a batch allocates only the small list of views; every view points into the payload of the frame, so a
// batch of a million values is read with no copy until the consumer copies what it keeps.
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

// Zig tip: a `test` block is compiled only by `zig build test`; `try std.testing.expect…` fails the test, with the values,
// when a check is false.
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
