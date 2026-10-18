//! DBF files, the old table format of dBASE III, FoxBASE and FoxPro 2.x, kept for legacy ingestion only (D-184).
//!
//! This module is a file decoder and a file encoder. It is never a table that a person edits, never a query engine and never
//! the storage of data in memory: `Stream` walks the records of a file once and hands each cell to the importer, and `Writer`
//! builds the bytes of a file from cells for an export. The data lives in SQLite `:memory:` or in a columnar table.
//!
//!   header   32 bytes: version (0x03), the date of the last change (YY MM DD), the number of records (u32),
//!            the length of the header (u16), the length of a record (u16), the rest is reserved
//!   fields   32 bytes each: name (11 bytes, 0 padded), type (C N F D L M), reserved (4), length (u8), decimals (u8),
//!            14 reserved; then the byte 0x0D ends the list
//!   records  one deletion byte (space, or `*` for a deleted record), then the fields side by side as text
//!   end      the byte 0x1A
//!
//! Types: C character, N numeric (text with a decimal point), F float (as N), D date (YYYYMMDD), L logical (T F Y N ?),
//! M memo (a pointer into a .FPT file; the pointer is read as text and the .FPT file is not read).
const std = @import("std");

pub const max_fields = 255;
pub const max_name = 10;

/// The version byte that the encoder writes: FoxPro 2.x / dBASE III without memo.
pub const version_plain: u8 = 0x03;

pub const Error = error{ NotDbf, Damaged };

// Zig tip: a struct whose fields have defaults can be created with only the fields that matter: `.{ .kind = 'N' }`.
// The name is a fixed array of 11 bytes (as in the file), padded with zeros; `nameSlice` gives the text part.
/// One field (column) of a file.
pub const Field = struct {
    name: [11]u8 = @splat(0),
    kind: u8 = 'C',
    length: u8 = 10,
    decimals: u8 = 0,

    // Zig tip: a function declared inside a struct whose first parameter is the struct (`self: *T`) is a method: `x.f()`
    // calls `f(&x)`.
    pub fn nameSlice(self: *const Field) []const u8 {
        return std.mem.sliceTo(&self.name, 0);
    }

    // Zig tip: `setName` relies on the same Zig feature as `Field` above: see the tip there.
    pub fn setName(self: *Field, s: []const u8) void {
        self.name = @splat(0);
        const n = @min(s.len, max_name);
        @memcpy(self.name[0..n], s[0..n]);
    }
};

// Zig tip: `Stream` borrows the bytes of the file (it never copies them) and keeps its place in them: `next` moves to the
// next record that is not deleted and returns `true`, then `cell(i)` is a slice of the file bytes, trimmed of the blanks of
// the format. Nothing is allocated, so the stream needs no `deinit`; the fields are in a fixed array of 255.
/// A forward reader of the records of a DBF file held in memory.
pub const Stream = struct {
    bytes: []const u8,
    fields_buf: [max_fields]Field = undefined,
    offsets: [max_fields]u16 = undefined,
    nfields: usize,
    records: u32,
    header_len: u16,
    record_len: u16,
    at: u32 = 0,
    current: []const u8 = &.{},

    // Zig tip: the result type `!T` (or `Error!T`) is an error union: a value or an error. `try f()` passes the error to
    // the caller; `f() catch …` handles it in place.
    /// Read the header of the file.
    pub fn init(bytes: []const u8) Error!Stream {
        if (bytes.len < 33) return error.NotDbf;
        // 0x03 dBASE III / FoxBASE+ / FoxPro 2.x, 0x83 with a memo file, 0xF5 FoxPro 2.x with a memo, 0x30 Visual FoxPro
        switch (bytes[0]) {
            0x03, 0x83, 0xF5, 0x30, 0x8B, 0x02, 0xFB => {},
            else => return error.NotDbf,
        }
        const records = std.mem.readInt(u32, bytes[4..8], .little);
        const header_len = std.mem.readInt(u16, bytes[8..10], .little);
        const record_len = std.mem.readInt(u16, bytes[10..12], .little);
        if (header_len < 33 or header_len > bytes.len or record_len == 0) return error.Damaged;
        const nfields = (header_len - 33) / 32;
        if (nfields > max_fields) return error.Damaged;
        var s: Stream = .{ .bytes = bytes, .nfields = nfields, .records = 0, .header_len = header_len, .record_len = record_len };
        var off: u16 = 1;
        for (0..nfields) |i| {
            const d = bytes[32 + i * 32 ..][0..32];
            var f: Field = .{ .kind = d[11], .length = d[16], .decimals = d[17] };
            f.setName(std.mem.sliceTo(d[0..11], 0));
            s.fields_buf[i] = f;
            s.offsets[i] = off;
            off += d[16];
        }
        if (off > record_len) return error.Damaged;
        // a file that was cut: only the records that are all there count
        const room = (bytes.len - header_len) / record_len;
        s.records = @intCast(@min(records, room));
        return s;
    }

    // Zig tip: `fields` relies on the same Zig feature as `nameSlice` above: see the tip there.
    pub fn fields(self: *const Stream) []const Field {
        return self.fields_buf[0..self.nfields];
    }

    // Zig tip: `next` relies on the same Zig feature as `Field` above: see the tip there.
    /// Move to the next record that is not deleted; false at the end.
    pub fn next(self: *Stream) bool {
        while (self.at < self.records) {
            const start = @as(usize, self.header_len) + @as(usize, self.at) * self.record_len;
            self.at += 1;
            const rec = self.bytes[start..][0..self.record_len];
            if (rec[0] == '*') continue;
            self.current = rec;
            return true;
        }
        return false;
    }

    // Zig tip: `cell` relies on the same Zig feature as `Stream` above: see the tip there.
    /// The text of field `i` of the current record, trimmed. A date is `YYYY-MM-DD` and a logical `1` or `0`, written in
    /// `buf`; a date or a logical that is blank or unreadable is the empty text.
    pub fn cell(self: *const Stream, i: usize, buf: *[16]u8) []const u8 {
        const f = &self.fields_buf[i];
        const r = self.current[self.offsets[i]..][0..f.length];
        switch (f.kind) {
            'D' => {
                if (r.len != 8 or std.mem.trim(u8, r, " ").len == 0) return "";
                return std.fmt.bufPrint(buf, "{s}-{s}-{s}", .{ r[0..4], r[4..6], r[6..8] }) catch "";
            },
            'L' => return switch (r[0]) {
                'T', 't', 'Y', 'y' => "1",
                'F', 'f', 'N', 'n' => "0",
                else => "",
            },
            'M' => return if (std.mem.trim(u8, r, " 0").len == 0) "" else "(memo)",
            'N', 'F' => return std.mem.trim(u8, r, " "),
            else => return std.mem.trimEnd(u8, r, " \x00"),
        }
    }
};

// Zig tip: the encoder is told its fields first, then each row as a list of texts; every cell is cut or padded to the width
// of its field (numbers on the right, the rest on the left). `finish` hands over the bytes, which the caller owns and frees.
/// Builds the bytes of a DBF file from rows of text.
pub const Writer = struct {
    gpa: std.mem.Allocator,
    fields: []const Field,
    body: std.ArrayList(u8) = .empty,
    records: u32 = 0,
    date: [3]u8,

    // Zig tip: a plain function: the types of the parameters and of the result are written out, and Zig has no default
    // arguments, so a call always passes every parameter.
    pub fn init(gpa: std.mem.Allocator, fields: []const Field, date: [3]u8) Writer {
        return .{ .gpa = gpa, .fields = fields, .date = date };
    }

    // Zig tip: `deinit` relies on the same Zig feature as `nameSlice` above: see the tip there.
    pub fn deinit(self: *Writer) void {
        self.body.deinit(self.gpa);
    }

    // Zig tip: `add` relies on the same Zig feature as `init` above: see the tip there.
    /// Add a record: one text for each field (an empty text is a blank cell).
    pub fn add(self: *Writer, cells: []const []const u8) !void {
        try self.body.append(self.gpa, ' ');
        for (self.fields, 0..) |f, i| {
            const raw = if (i < cells.len) cells[i] else "";
            var text = raw[0..@min(raw.len, f.length)];
            var tmp: [10]u8 = undefined;
            // a date is written YYYYMMDD
            if (f.kind == 'D' and raw.len >= 10 and raw[4] == '-') {
                @memcpy(tmp[0..4], raw[0..4]);
                @memcpy(tmp[4..6], raw[5..7]);
                @memcpy(tmp[6..8], raw[8..10]);
                text = tmp[0..8];
            }
            if (f.kind == 'L') text = if (raw.len > 0 and (raw[0] == '1' or raw[0] == 'T' or raw[0] == 't')) "T" else if (raw.len > 0) "F" else "?";
            const pad = f.length - text.len;
            if (f.kind == 'N' or f.kind == 'F') try self.body.appendNTimes(self.gpa, ' ', pad);
            try self.body.appendSlice(self.gpa, text);
            if (f.kind != 'N' and f.kind != 'F') try self.body.appendNTimes(self.gpa, ' ', pad);
        }
        self.records += 1;
    }

    // Zig tip: `finish` relies on the same Zig feature as `Writer` above: see the tip there.
    /// The bytes of the whole file.
    pub fn finish(self: *Writer) ![]u8 {
        const header_len: u16 = @intCast(32 + self.fields.len * 32 + 1);
        var rec_len: u16 = 1;
        for (self.fields) |f| rec_len += f.length;
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.gpa);
        try out.appendNTimes(self.gpa, 0, 32);
        out.items[0] = version_plain;
        @memcpy(out.items[1..4], &self.date);
        std.mem.writeInt(u32, out.items[4..8], self.records, .little);
        std.mem.writeInt(u16, out.items[8..10], header_len, .little);
        std.mem.writeInt(u16, out.items[10..12], rec_len, .little);
        for (self.fields) |f| {
            var d: [32]u8 = @splat(0);
            @memcpy(d[0..11], &f.name);
            d[11] = f.kind;
            d[16] = f.length;
            d[17] = f.decimals;
            try out.appendSlice(self.gpa, &d);
        }
        try out.append(self.gpa, 0x0D);
        try out.appendSlice(self.gpa, self.body.items);
        try out.append(self.gpa, 0x1A);
        return out.toOwnedSlice(self.gpa);
    }
};

// Zig tip: the date of the header is three bytes, the year since 1900. `std.time.epoch` turns seconds since 1970 into a
// calendar day. The result is a plain array, so the caller needs no allocation.
/// The bytes YY MM DD of a moment given in seconds since 1970.
pub fn headerDate(secs: i64) [3]u8 {
    const es = std.time.epoch.EpochSeconds{ .secs = @intCast(@max(secs, 0)) };
    const yd = es.getEpochDay().calculateYearDay();
    const md = yd.calculateMonthDay();
    return .{ @intCast(@mod(yd.year, 100)), @intFromEnum(md.month), md.day_index + 1 };
}

// Zig tip: a `test` block is compiled only by `zig build test`; `try std.testing.expect…` fails the test, with the values,
// when a check is false.
test "the encoder and the stream agree" {
    var f1: Field = .{ .kind = 'C', .length = 8 };
    f1.setName("name");
    var f2: Field = .{ .kind = 'N', .length = 6, .decimals = 2 };
    f2.setName("price");
    var f3: Field = .{ .kind = 'D', .length = 8 };
    f3.setName("day");
    var f4: Field = .{ .kind = 'L', .length = 1 };
    f4.setName("ok");
    const fields = [_]Field{ f1, f2, f3, f4 };
    var w = Writer.init(std.testing.allocator, &fields, .{ 126, 10, 17 });
    defer w.deinit();
    try w.add(&.{ "bolt", "1.50", "2026-10-17", "1" });
    try w.add(&.{ "nut", "", "", "0" });
    const bytes = try w.finish();
    defer std.testing.allocator.free(bytes);
    var s = try Stream.init(bytes);
    try std.testing.expectEqual(@as(usize, 4), s.fields().len);
    var buf: [16]u8 = undefined;
    try std.testing.expect(s.next());
    try std.testing.expectEqualStrings("bolt", s.cell(0, &buf));
    try std.testing.expectEqualStrings("1.50", s.cell(1, &buf));
    try std.testing.expectEqualStrings("2026-10-17", s.cell(2, &buf));
    try std.testing.expectEqualStrings("1", s.cell(3, &buf));
    try std.testing.expect(s.next());
    try std.testing.expectEqualStrings("", s.cell(1, &buf));
    try std.testing.expect(!s.next());
}

// Zig tip: test "a deleted record is skipped and a text that is not DBF is refused" relies on the same Zig feature as test
// "the encoder and the stream agree" above: see the tip there.
test "a deleted record is skipped and a text that is not DBF is refused" {
    var f1: Field = .{ .kind = 'C', .length = 4 };
    f1.setName("a");
    var w = Writer.init(std.testing.allocator, &.{f1}, .{ 126, 1, 1 });
    defer w.deinit();
    try w.add(&.{"one"});
    try w.add(&.{"two"});
    const bytes = try w.finish();
    defer std.testing.allocator.free(bytes);
    // mark the first record deleted
    bytes[32 + 32 + 1] = '*';
    var s = try Stream.init(bytes);
    var buf: [16]u8 = undefined;
    try std.testing.expect(s.next());
    try std.testing.expectEqualStrings("two", s.cell(0, &buf));
    try std.testing.expect(!s.next());
    try std.testing.expectError(error.NotDbf, Stream.init("this is not a dbf file at all, just words"));
}
