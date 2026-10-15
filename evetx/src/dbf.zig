//! DBF files: the old table format of dBASE III, FoxBASE and FoxPro 2.x (F-DAT, evetx). One file is one table:
//!
//!   header   32 bytes: version (0x03), the date of the last change (YY MM DD), the number of records (u32),
//!            the length of the header (u16), the length of a record (u16), the rest is reserved
//!   fields   32 bytes each: name (11 bytes, 0 padded), type (C N F D L M), reserved (4), length (u8), decimals (u8),
//!            14 reserved; then the byte 0x0D ends the list
//!   records  one deletion byte (space, or `*` for a deleted record), then the fields side by side as text
//!   end      the byte 0x1A
//!
//! Types: C character, N numeric (text with a decimal point), F float (as N), D date (YYYYMMDD), L logical (T F Y N ?),
//! M memo (a pointer into a .FPT file; this module keeps the pointer and does not read or write the .FPT). Everything is
//! text, so a table can be read with a few lines and no number conversion.
const std = @import("std");

/// The version byte that this module writes: FoxPro 2.x / dBASE III without memo.
pub const version_plain: u8 = 0x03;
pub const max_fields = 255;
pub const max_name = 10;

/// The types that a person can choose for a new field. M is kept when a table has it, but cannot be created.
pub const kinds = "CNFDLM";

// Zig tip: a struct whose fields have defaults can be created with only the fields that matter: `.{ .kind = 'N' }`.
// The name is a fixed array of 11 bytes (as in the file), padded with zeros; `nameSlice` gives the text part.
/// One field (column) of a table.
pub const Field = struct {
    name: [11]u8 = [_]u8{0} ** 11,
    kind: u8 = 'C',
    length: u8 = 10,
    decimals: u8 = 0,

    pub fn nameSlice(self: *const Field) []const u8 {
        return std.mem.sliceTo(&self.name, 0);
    }

    /// Set the name, upper case, at most 10 bytes.
    pub fn setName(self: *Field, s: []const u8) void {
        self.name = [_]u8{0} ** 11;
        const n = @min(s.len, max_name);
        for (s[0..n], 0..) |c, i| self.name[i] = std.ascii.toUpper(c);
    }
};

/// The width of the column of a field when the table is drawn, in cells.
pub fn displayWidth(f: *const Field) u16 {
    const wide: usize = switch (f.kind) {
        'D' => 10,
        'M' => 6,
        else => f.length,
    };
    return @intCast(std.math.clamp(@max(f.nameSlice().len, wide), 4, 30));
}

/// The name of a type, for the lists of the structure dialog.
pub fn kindName(k: u8) []const u8 {
    return switch (k) {
        'C' => "Character",
        'N' => "Numeric",
        'F' => "Float",
        'D' => "Date",
        'L' => "Logical",
        'M' => "Memo (kept, not created)",
        else => "?",
    };
}

/// The length and decimals that a field gets when its type is chosen.
pub fn defaultsFor(k: u8, f: *Field) void {
    f.kind = k;
    switch (k) {
        'C' => {
            if (f.length == 0 or f.length > 254) f.length = 10;
            f.decimals = 0;
        },
        'N', 'F' => {
            f.length = 10;
            f.decimals = 0;
        },
        'D' => {
            f.length = 8;
            f.decimals = 0;
        },
        'L' => {
            f.length = 1;
            f.decimals = 0;
        },
        else => {
            f.length = 10;
            f.decimals = 0;
        },
    }
}

/// A message about what is wrong with a field, or null when it is fine.
pub fn checkField(f: *const Field) ?[]const u8 {
    const name = f.nameSlice();
    if (name.len == 0) return "a field needs a name";
    if (!(std.ascii.isAlphabetic(name[0]) or name[0] == '_')) return "a name begins with a letter or _";
    for (name) |c| {
        if (!(std.ascii.isAlphanumeric(c) or c == '_')) return "a name has letters, digits and _ only";
    }
    switch (f.kind) {
        'C' => if (f.length == 0 or f.length > 254) return "Character: length 1 to 254",
        'N', 'F' => {
            if (f.length == 0 or f.length > 20) return "Numeric: length 1 to 20";
            if (f.decimals > 0 and f.decimals + 2 > f.length) return "Numeric: decimals must leave room for the point";
        },
        'D' => if (f.length != 8) return "Date: length 8",
        'L' => if (f.length != 1) return "Logical: length 1",
        'M' => if (f.length != 10) return "Memo: length 10",
        else => return "unknown type: C N F D L M",
    }
    return null;
}

pub const Error = error{ NotDbf, Damaged } || std.mem.Allocator.Error;

/// A table in memory: the bytes of the file, owned, and the structure read from them.
pub const Table = struct {
    gpa: std.mem.Allocator,
    bytes: []u8,
    fields: []Field,
    /// Where each field starts inside a record (the deletion byte is the first).
    offsets: []u16,
    records: u32,
    header_len: u16,
    record_len: u16,
    version: u8,

    // Zig tip: `load` takes over the memory of `bytes` (the table frees it in `deinit`). The checks come first and
    // return an error before anything is allocated, so a damaged file leaves nothing to clean up except the caller's bytes.
    /// Read the structure of a table from the bytes of a file.
    pub fn load(gpa: std.mem.Allocator, bytes: []u8) Error!Table {
        if (bytes.len < 33) return error.NotDbf;
        const version = bytes[0];
        // 0x03 dBASE III / FoxBASE+ / FoxPro 2.x, 0x83 with a memo file, 0xF5 FoxPro 2.x with a memo, 0x30 Visual FoxPro
        switch (version) {
            0x03, 0x83, 0xF5, 0x30, 0x8B, 0x02, 0xFB => {},
            else => return error.NotDbf,
        }
        const records = std.mem.readInt(u32, bytes[4..8], .little);
        const header_len = std.mem.readInt(u16, bytes[8..10], .little);
        const record_len = std.mem.readInt(u16, bytes[10..12], .little);
        if (header_len < 33 or header_len > bytes.len or record_len == 0) return error.Damaged;
        const nfields = (header_len - 33) / 32;
        if (nfields > max_fields) return error.Damaged;
        const fields = try gpa.alloc(Field, nfields);
        errdefer gpa.free(fields);
        const offsets = try gpa.alloc(u16, nfields);
        errdefer gpa.free(offsets);
        var off: u16 = 1;
        for (0..nfields) |i| {
            const d = bytes[32 + i * 32 ..][0..32];
            fields[i] = .{ .kind = d[11], .length = d[16], .decimals = d[17] };
            const name = std.mem.sliceTo(d[0..11], 0);
            fields[i].name = [_]u8{0} ** 11;
            @memcpy(fields[i].name[0..name.len], name);
            offsets[i] = off;
            off += d[16];
        }
        if (off > record_len) return error.Damaged;
        // a file that was cut: only the records that are all there count
        const room = (bytes.len - header_len) / record_len;
        return .{ .gpa = gpa, .bytes = bytes, .fields = fields, .offsets = offsets, .records = @intCast(@min(records, room)), .header_len = header_len, .record_len = record_len, .version = version };
    }

    pub fn deinit(self: *Table) void {
        self.gpa.free(self.bytes);
        self.gpa.free(self.fields);
        self.gpa.free(self.offsets);
    }

    fn record(self: *const Table, row: usize) []const u8 {
        const start = @as(usize, self.header_len) + row * self.record_len;
        return self.bytes[start..][0..self.record_len];
    }

    // Zig tip: `gpa.realloc` grows (or shrinks) the block of memory and may move it, so every slice taken from `bytes` before
    // is stale after it; the table keeps no such slices (it computes them from `bytes` each time). The new records are
    // blank: a space for the deletion mark, and blanks in every field (`?` for a logical, the dBASE "unknown").
    /// Add `n` blank records at the end; the end byte and the count in the header follow.
    pub fn appendRecords(self: *Table, n: u32) std.mem.Allocator.Error!void {
        const old_end = @as(usize, self.header_len) + @as(usize, self.records) * self.record_len;
        const new_len = old_end + @as(usize, n) * self.record_len + 1;
        self.bytes = try self.gpa.realloc(self.bytes, @max(new_len, self.bytes.len));
        var at = old_end;
        for (0..n) |_| {
            const rec = self.bytes[at..][0..self.record_len];
            @memset(rec, ' ');
            for (self.fields, 0..) |f, c| {
                if (f.kind == 'L') rec[self.offsets[c]] = '?';
            }
            at += self.record_len;
        }
        self.bytes[at] = 0x1A;
        self.records += n;
        std.mem.writeInt(u32, self.bytes[4..8], self.records, .little);
        self.bytes = try self.gpa.realloc(self.bytes, new_len);
    }

    /// The bytes of the file as they should be written (the header count is kept up to date).
    pub fn fileBytes(self: *const Table) []const u8 {
        const end = @as(usize, self.header_len) + @as(usize, self.records) * self.record_len;
        return self.bytes[0..@min(self.bytes.len, end + 1)];
    }

    /// Mark the record deleted, or recall it.
    pub fn toggleDeleted(self: *Table, row: usize) void {
        const start = @as(usize, self.header_len) + row * self.record_len;
        self.bytes[start] = if (self.bytes[start] == '*') ' ' else '*';
    }

    /// Put `text` into a cell, converted to the type of the field (a bad number or date leaves the cell blank).
    pub fn setCell(self: *Table, row: usize, col: usize, new_text: []const u8) void {
        const start = @as(usize, self.header_len) + row * self.record_len + self.offsets[col];
        const f = &self.fields[col];
        const dst = self.bytes[start..][0..f.length];
        convert(dst, 'C', new_text, f);
    }

    /// Is the record deleted (marked with `*`)?
    pub fn deleted(self: *const Table, row: usize) bool {
        return self.record(row)[0] == '*';
    }

    /// The bytes of a cell, as they are in the file.
    pub fn raw(self: *const Table, row: usize, col: usize) []const u8 {
        return self.record(row)[self.offsets[col]..][0..self.fields[col].length];
    }

    // Zig tip: the text of a cell is a slice of the file bytes when it can be (trimmed of blanks); a date is written
    // into the small buffer the caller gives, as `YYYY-MM-DD`. Nothing is allocated, so the drawing code can call this
    // for every cell of every frame.
    /// The text to show for a cell. `buf` holds a date.
    pub fn display(self: *const Table, row: usize, col: usize, buf: *[16]u8) []const u8 {
        const f = &self.fields[col];
        const r = self.raw(row, col);
        switch (f.kind) {
            'D' => {
                if (r.len != 8 or std.mem.trim(u8, r, " ").len == 0) return "";
                return std.fmt.bufPrint(buf, "{s}-{s}-{s}", .{ r[0..4], r[4..6], r[6..8] }) catch "";
            },
            'L' => return switch (r[0]) {
                'T', 't', 'Y', 'y' => "T",
                'F', 'f', 'N', 'n' => "F",
                else => "?",
            },
            'M' => return if (std.mem.trim(u8, r, " 0").len == 0) "" else "(memo)",
            'N', 'F' => return std.mem.trim(u8, r, " "),
            else => return std.mem.trimEnd(u8, r, " \x00"),
        }
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

/// What to put in a field of the new table: the field, and the place of the field it comes from in the old table.
pub const Spec = struct { field: Field, src: ?usize = null };

fn putHeader(out: *std.ArrayList(u8), gpa: std.mem.Allocator, specs: []const Spec, records: u32, date: [3]u8, record_len: u16) !void {
    var head = [_]u8{0} ** 32;
    head[0] = version_plain;
    head[1] = date[0];
    head[2] = date[1];
    head[3] = date[2];
    std.mem.writeInt(u32, head[4..8], records, .little);
    const header_len: u16 = @intCast(32 + 32 * specs.len + 1);
    std.mem.writeInt(u16, head[8..10], header_len, .little);
    std.mem.writeInt(u16, head[10..12], record_len, .little);
    try out.appendSlice(gpa, &head);
    for (specs) |s| {
        var d = [_]u8{0} ** 32;
        @memcpy(d[0..11], &s.field.name);
        d[11] = s.field.kind;
        d[16] = s.field.length;
        d[17] = s.field.decimals;
        try out.appendSlice(gpa, &d);
    }
    try out.append(gpa, 0x0D);
}

// Zig tip: a number is written without `fmt` so the number of decimals can be a run-time value: the value is scaled to a
// whole number, rounded, and the point is put in by hand. The text is right-aligned in the field; a number too wide for
// the field is shown as a row of `*`, the way dBASE does.
fn putNumber(dst: []u8, value: f64, decimals: u8) void {
    @memset(dst, ' ');
    var scale: f64 = 1;
    for (0..decimals) |_| scale *= 10;
    const scaled: i64 = @intFromFloat(@round(value * scale));
    var digits: [32]u8 = undefined;
    var n: usize = 0;
    var mag: u64 = @abs(scaled);
    while (mag > 0 or n <= decimals) : (mag /= 10) {
        digits[n] = '0' + @as(u8, @intCast(mag % 10));
        n += 1;
        if (n == decimals and decimals > 0) {
            digits[n] = '.';
            n += 1;
        }
    }
    if (scaled < 0) {
        digits[n] = '-';
        n += 1;
    }
    if (n > dst.len) {
        @memset(dst, '*');
        return;
    }
    for (0..n) |i| dst[dst.len - 1 - i] = digits[i];
}

/// Convert the text of a cell of the old table to the new field `f` (`dst` is exactly `f.length` bytes).
fn convert(dst: []u8, old_kind: u8, old: []const u8, f: *const Field) void {
    const trimmed = std.mem.trim(u8, old, " \x00");
    switch (f.kind) {
        'C' => {
            @memset(dst, ' ');
            const n = @min(dst.len, trimmed.len);
            @memcpy(dst[0..n], trimmed[0..n]);
        },
        'N', 'F' => {
            const v = std.fmt.parseFloat(f64, trimmed) catch {
                @memset(dst, ' ');
                return;
            };
            putNumber(dst, v, f.decimals);
        },
        'D' => {
            @memset(dst, ' ');
            if (old_kind == 'D' and trimmed.len == 8) {
                @memcpy(dst, trimmed);
            } else if (trimmed.len == 10 and trimmed[4] == '-' and trimmed[7] == '-') {
                @memcpy(dst[0..4], trimmed[0..4]);
                @memcpy(dst[4..6], trimmed[5..7]);
                @memcpy(dst[6..8], trimmed[8..10]);
            }
        },
        'L' => {
            dst[0] = if (old_kind == 'L' and trimmed.len > 0) std.ascii.toUpper(trimmed[0]) else '?';
        },
        else => {
            @memset(dst, ' ');
            if (old_kind == 'M') @memcpy(dst, old[0..@min(dst.len, old.len)]);
        },
    }
}

// Zig tip: the new file is built in memory in one `ArrayList` and written by the caller in one call. For each record of
// the old table, each new field is filled from the old field it comes from (`src`), converted to the new type; a field
// with no source (a new one) is blank. The deletion marks stay. `appendNTimes` adds a run of one byte.
/// Build the bytes of a table with the structure `specs`, filled from `old` (null for a new empty table).
pub fn rebuild(gpa: std.mem.Allocator, old: ?*const Table, specs: []const Spec, date: [3]u8) Error![]u8 {
    var record_len: usize = 1;
    for (specs) |s| record_len += s.field.length;
    if (record_len > 65535) return error.Damaged;
    const records: u32 = if (old) |t| t.records else 0;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try putHeader(&out, gpa, specs, records, date, @intCast(record_len));
    for (0..records) |row| {
        const old_t = old.?;
        try out.append(gpa, if (old_t.deleted(row)) '*' else ' ');
        for (specs) |s| {
            const at = out.items.len;
            try out.appendNTimes(gpa, ' ', s.field.length);
            const dst = out.items[at..][0..s.field.length];
            if (s.src) |c| convert(dst, old_t.fields[c].kind, old_t.raw(row, c), &s.field);
        }
    }
    try out.append(gpa, 0x1A);
    return out.toOwnedSlice(gpa);
}

// Zig tip: a result of SQL arrives as text: a header line with the names and a line for each row, cells separated by tabs.
// The grid of the Main Panel already draws a `Table`, so the result is turned into one in memory: every column is a
// Character field as wide as its widest cell (at most 250), and the cells are set with `setCell`. A name longer than ten
// bytes is cut, because a field name in this format has ten. The arena holds the temporary lists and goes away at the end.
/// A table in memory from tab separated text: the first line holds the column names.
pub fn fromTsv(gpa: std.mem.Allocator, tsv: []const u8, date: [3]u8) Error!Table {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var lines = std.mem.splitScalar(u8, tsv, '\n');
    const head_line = std.mem.trimEnd(u8, lines.next() orelse "", "\r");
    var names: std.ArrayList([]const u8) = .empty;
    var hp = std.mem.splitScalar(u8, head_line, '\t');
    while (hp.next()) |n| try names.append(a, n);
    if (names.items.len > max_fields) names.shrinkRetainingCapacity(max_fields);
    var rows: std.ArrayList([]const []const u8) = .empty;
    const widths = try a.alloc(usize, names.items.len);
    @memset(widths, 1);
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len == 0) continue;
        const cells = try a.alloc([]const u8, names.items.len);
        var cp = std.mem.splitScalar(u8, line, '\t');
        for (cells, 0..) |*c, k| {
            c.* = cp.next() orelse "";
            widths[k] = @max(widths[k], c.len);
        }
        try rows.append(a, cells);
    }
    const specs = try a.alloc(Spec, names.items.len);
    for (specs, 0..) |*sp, k| {
        sp.* = .{ .field = .{ .kind = 'C', .length = @intCast(@min(widths[k], 250)) } };
        const n = @min(names.items[k].len, max_name);
        @memcpy(sp.field.name[0..n], names.items[k][0..n]);
    }
    const bytes = try rebuild(gpa, null, specs, date);
    var t = try Table.load(gpa, bytes);
    errdefer t.deinit();
    try t.appendRecords(@intCast(rows.items.len));
    for (rows.items, 0..) |cells, r| {
        for (cells, 0..) |c, k| t.setCell(r, k, c);
    }
    return t;
}

fn sqlQuote(w: *std.ArrayList(u8), gpa: std.mem.Allocator, s: []const u8) !void {
    try w.append(gpa, '\'');
    for (s) |c| {
        if (c == '\'') try w.append(gpa, '\'');
        try w.append(gpa, c);
    }
    try w.append(gpa, '\'');
}

// Zig tip: SQL over a DBF table is done by SQLite on a copy: this makes the statements that build the copy, a `create table`
// and `insert` statements of 500 rows each. Deleted records are left out. A numeric field becomes INTEGER or REAL (a blank
// or unreadable value is NULL), a date becomes `YYYY-MM-DD`, a logical `T` or `F`. Names are quoted, so any field name works.
/// The SQL that makes the table `name` with the records of `t` (the deleted ones are left out).
pub fn toSql(gpa: std.mem.Allocator, t: *const Table, name: []const u8) std.mem.Allocator.Error![]u8 {
    var w: std.ArrayList(u8) = .empty;
    errdefer w.deinit(gpa);
    try w.appendSlice(gpa, "create table \"");
    try w.appendSlice(gpa, name);
    try w.appendSlice(gpa, "\" (");
    for (t.fields, 0..) |f, c| {
        if (c > 0) try w.appendSlice(gpa, ", ");
        try w.append(gpa, '"');
        try w.appendSlice(gpa, f.nameSlice());
        try w.appendSlice(gpa, "\" ");
        try w.appendSlice(gpa, switch (f.kind) {
            'N' => if (f.decimals > 0) "real" else "integer",
            'F' => "real",
            else => "text",
        });
    }
    try w.appendSlice(gpa, ");\n");
    var in_batch: usize = 0;
    var buf: [16]u8 = undefined;
    var row: usize = 0;
    while (row < t.records) : (row += 1) {
        if (t.deleted(row)) continue;
        if (in_batch == 0) {
            try w.appendSlice(gpa, "insert into \"");
            try w.appendSlice(gpa, name);
            try w.appendSlice(gpa, "\" values\n");
        } else try w.appendSlice(gpa, ",\n");
        try w.append(gpa, '(');
        for (t.fields, 0..) |f, c| {
            if (c > 0) try w.append(gpa, ',');
            const shown = t.display(row, c, &buf);
            switch (f.kind) {
                'N', 'F' => {
                    if (shown.len == 0 or (std.fmt.parseFloat(f64, shown) catch null) == null) {
                        try w.appendSlice(gpa, "NULL");
                    } else try w.appendSlice(gpa, shown);
                },
                'D' => if (shown.len == 0) try w.appendSlice(gpa, "NULL") else try sqlQuote(&w, gpa, shown),
                'L' => if (shown[0] == '?') try w.appendSlice(gpa, "NULL") else try sqlQuote(&w, gpa, shown),
                'M' => try w.appendSlice(gpa, "NULL"),
                else => try sqlQuote(&w, gpa, shown),
            }
        }
        try w.append(gpa, ')');
        in_batch += 1;
        if (in_batch == 500) {
            try w.appendSlice(gpa, ";\n");
            in_batch = 0;
        }
    }
    if (in_batch > 0) try w.appendSlice(gpa, ";\n");
    return w.toOwnedSlice(gpa);
}

// Zig tip: the test goes both ways: a result in text becomes a table, and the table becomes SQL; the checks look at the
// cells and at a few pieces of the SQL.
test "a table from tab separated text, and its SQL" {
    const gpa = std.testing.allocator;
    var t = try fromTsv(gpa, "a\tb\n1\tx y\n2\tit's\n", .{ 26, 1, 1 });
    defer t.deinit();
    try std.testing.expectEqual(@as(u32, 2), t.records);
    var buf: [16]u8 = undefined;
    try std.testing.expectEqualStrings("it's", t.display(1, 1, &buf));
    const sql = try toSql(gpa, &t, "q");
    defer gpa.free(sql);
    try std.testing.expect(std.mem.indexOf(u8, sql, "create table \"q\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "'it''s'") != null);
}

// Zig tip: a `test` block is a function that `zig test` runs; `std.testing.allocator` fails the test if memory leaks.
test "an empty table can be built and read back" {
    const gpa = std.testing.allocator;
    var f1: Field = .{ .kind = 'C', .length = 6 };
    f1.setName("name");
    var f2: Field = .{ .kind = 'N', .length = 8, .decimals = 2 };
    f2.setName("price");
    const specs = [_]Spec{ .{ .field = f1 }, .{ .field = f2 } };
    const bytes = try rebuild(gpa, null, &specs, .{ 26, 10, 15 });
    var t = try Table.load(gpa, bytes);
    defer t.deinit();
    try std.testing.expectEqual(@as(usize, 2), t.fields.len);
    try std.testing.expectEqualStrings("PRICE", t.fields[1].nameSlice());
    try std.testing.expectEqual(@as(u32, 0), t.records);
}

// Zig tip: `expectEqualStrings` compares two byte slices and prints both when they differ.
test "rebuild keeps the data, converts it and marks deleted records" {
    const gpa = std.testing.allocator;
    var f1: Field = .{ .kind = 'C', .length = 5 };
    f1.setName("code");
    var f2: Field = .{ .kind = 'N', .length = 6, .decimals = 1 };
    f2.setName("qty");
    const specs = [_]Spec{ .{ .field = f1 }, .{ .field = f2 } };
    const empty = try rebuild(gpa, null, &specs, .{ 26, 1, 1 });
    // two records by hand: "A1   " 12.5 and "B2   " 3.0 (deleted)
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(gpa);
    try bytes.appendSlice(gpa, empty[0 .. empty.len - 1]);
    gpa.free(empty);
    std.mem.writeInt(u32, bytes.items[4..8], 2, .little);
    try bytes.appendSlice(gpa, " A1     12.5");
    try bytes.appendSlice(gpa, "*B2      3.0");
    try bytes.append(gpa, 0x1A);
    var t = try Table.load(gpa, try bytes.toOwnedSlice(gpa));
    defer t.deinit();
    try std.testing.expectEqual(@as(u32, 2), t.records);
    try std.testing.expect(t.deleted(1));
    var buf: [16]u8 = undefined;
    try std.testing.expectEqualStrings("A1", t.display(0, 0, &buf));
    try std.testing.expectEqualStrings("12.5", t.display(0, 1, &buf));
    // qty becomes Character(8), code becomes second; a new Logical field is added; the order changes
    var g1: Field = .{ .kind = 'C', .length = 8 };
    g1.setName("qty");
    var g2: Field = .{ .kind = 'C', .length = 3 };
    g2.setName("code");
    var g3: Field = .{ .kind = 'L', .length = 1 };
    g3.setName("ok");
    const specs2 = [_]Spec{ .{ .field = g1, .src = 1 }, .{ .field = g2, .src = 0 }, .{ .field = g3 } };
    const out = try rebuild(gpa, &t, &specs2, .{ 26, 1, 2 });
    var t2 = try Table.load(gpa, out);
    defer t2.deinit();
    try std.testing.expectEqual(@as(u32, 2), t2.records);
    try std.testing.expectEqualStrings("12.5", t2.display(0, 0, &buf));
    try std.testing.expectEqualStrings("A1", t2.display(0, 1, &buf));
    try std.testing.expectEqualStrings("?", t2.display(0, 2, &buf));
    try std.testing.expect(t2.deleted(1));
}

// Zig tip: the array `b` is filled by the function through the slice `&b`; the test then compares it with the text.
test "numbers are right aligned with their decimals" {
    var b: [8]u8 = undefined;
    putNumber(&b, 3.14159, 2);
    try std.testing.expectEqualStrings("    3.14", &b);
}

// Zig tip: `x != null` is true when an optional holds a value; here, a message about a bad field.
test "checks of a field" {
    var f: Field = .{ .kind = 'N', .length = 5, .decimals = 4 };
    f.setName("x1");
    try std.testing.expect(checkField(&f) != null);
    f.decimals = 2;
    try std.testing.expect(checkField(&f) == null);
    f.setName("1x");
    try std.testing.expect(checkField(&f) != null);
}

// Zig tip: the test builds a table, appends rows, edits a cell, and reads it back; `defer t.deinit()` frees the bytes even
// when an expectation fails.
test "append rows and set a cell" {
    const gpa = std.testing.allocator;
    var f1: Field = .{ .kind = 'C', .length = 5 };
    f1.setName("a");
    var f2: Field = .{ .kind = 'N', .length = 6, .decimals = 1 };
    f2.setName("b");
    const bytes = try rebuild(gpa, null, &[_]Spec{ .{ .field = f1 }, .{ .field = f2 } }, .{ 26, 1, 1 });
    var t = try Table.load(gpa, bytes);
    defer t.deinit();
    try t.appendRecords(2);
    try std.testing.expectEqual(@as(u32, 2), t.records);
    t.setCell(1, 0, "xyz");
    t.setCell(1, 1, "2.25");
    var buf: [16]u8 = undefined;
    try std.testing.expectEqualStrings("xyz", t.display(1, 0, &buf));
    try std.testing.expectEqualStrings("2.3", t.display(1, 1, &buf));
    t.toggleDeleted(0);
    try std.testing.expect(t.deleted(0));
    try std.testing.expectEqual(@as(u8, 0x1A), t.fileBytes()[t.fileBytes().len - 1]);
}
