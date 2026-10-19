//! @eve-module ide.grid
//! @decision D-193
//! @tests comp/evecm/src/ide/grid.zig (zig build test)
//! The table that the grid of the Main Panel shows (D-184): the rows that a SQLite query returned, kept in memory as columns.
//!
//! The layout is columnar (a struct of arrays): each column owns one byte buffer with all its cells one after the other, and
//! one array of offsets that says where each cell starts. A column is read without touching the other columns, and the table
//! has no object for a row. The grid does not change the data: a change goes to the database with SQL and the table is read
//! again. DBF is not here: a legacy file is decoded and imported by `evedb`, it is never the table of a window.
const std = @import("std");

pub const max_fields = 255;

// Zig tip: a field owns its name (a slice that was allocated), so a name can be as long as the database allows. `width` is
// the number of cells the widest value (or the name) needs, worked out once when the table is read.
/// One column of the table: its name and the width it asks for in the grid.
pub const Field = struct {
    name: []u8,
    width: u16 = 4,

    pub fn nameSlice(self: *const Field) []const u8 {
        return self.name;
    }
};

// Zig tip: `offs` has one entry more than there are cells: cell `i` is `data[offs[i]..offs[i + 1]]`, so the length of a cell
// is a subtraction and the last cell needs no special case.
const Column = struct {
    data: []u8 = &.{},
    offs: []u32 = &.{},
};

pub const Table = struct {
    gpa: std.mem.Allocator,
    fields: []Field,
    cols: []Column,
    records: u32,

    /// Free the names, the cells and the offsets.
    pub fn deinit(self: *Table) void {
        for (self.fields) |f| self.gpa.free(f.name);
        self.gpa.free(self.fields);
        for (self.cols) |c| {
            self.gpa.free(c.data);
            self.gpa.free(c.offs);
        }
        self.gpa.free(self.cols);
    }

    // Zig tip: the buffer argument is kept from the days when a cell had to be formatted; a text cell is returned as it is,
    // a slice of the column buffer, so nothing is copied and the slice lives as long as the table.
    /// The text of a cell (empty outside the table).
    pub fn display(self: *const Table, row: usize, col: usize, buf: *[16]u8) []const u8 {
        _ = buf;
        return self.cell(row, col);
    }

    pub fn cell(self: *const Table, row: usize, col: usize) []const u8 {
        if (col >= self.cols.len or row >= self.records) return "";
        const c = self.cols[col];
        return c.data[c.offs[row]..c.offs[row + 1]];
    }

    /// A record is never marked deleted here: rows that are deleted are gone from the database.
    pub fn deleted(self: *const Table, row: usize) bool {
        _ = self;
        _ = row;
        return false;
    }
};

// Zig tip: the text is read twice. The first pass counts the records and the widest cell of each column; the second copies
// each cell into its column buffer, whose size is known by then, so nothing grows while it is filled. `errdefer` frees what
// was made when a later allocation fails. An empty text (no header) gives a table with no column.
/// A table from tab separated text: the first line holds the names of the columns; a short line is padded with empty cells.
pub fn fromTsv(gpa: std.mem.Allocator, tsv: []const u8) std.mem.Allocator.Error!Table {
    var lines = std.mem.splitScalar(u8, tsv, '\n');
    const head_line = std.mem.trimEnd(u8, lines.next() orelse "", "\r");
    var n: usize = 0;
    if (head_line.len > 0 or tsv.len > 0) {
        n = std.mem.count(u8, head_line, "\t") + 1;
        if (n > max_fields) n = max_fields;
    }
    var records: u32 = 0;
    const sizes = try gpa.alloc(usize, n);
    defer gpa.free(sizes);
    @memset(sizes, 0);
    const widths = try gpa.alloc(usize, n);
    defer gpa.free(widths);
    var hp = std.mem.splitScalar(u8, head_line, '\t');
    for (widths) |*w| w.* = if (hp.next()) |h0| h0.len else 0;
    var body = lines;
    while (body.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len == 0) continue;
        records += 1;
        var cp = std.mem.splitScalar(u8, line, '\t');
        for (0..n) |k| {
            const c = cp.next() orelse "";
            sizes[k] += c.len;
            widths[k] = @max(widths[k], c.len);
        }
    }
    const fields = try gpa.alloc(Field, n);
    var made_fields: usize = 0;
    errdefer {
        for (fields[0..made_fields]) |f| gpa.free(f.name);
        gpa.free(fields);
    }
    const cols = try gpa.alloc(Column, n);
    var made_cols: usize = 0;
    errdefer {
        for (cols[0..made_cols]) |c| {
            gpa.free(c.data);
            gpa.free(c.offs);
        }
        gpa.free(cols);
    }
    var hp2 = std.mem.splitScalar(u8, head_line, '\t');
    for (0..n) |k| {
        fields[k] = .{ .name = try gpa.dupe(u8, hp2.next() orelse ""), .width = @intCast(std.math.clamp(widths[k], 4, 254)) };
        made_fields += 1;
        cols[k] = .{ .data = try gpa.alloc(u8, sizes[k]), .offs = try gpa.alloc(u32, records + 1) };
        made_cols += 1;
        cols[k].offs[0] = 0;
    }
    var row: usize = 0;
    var fill = try gpa.alloc(u32, n);
    defer gpa.free(fill);
    @memset(fill, 0);
    var again = std.mem.splitScalar(u8, tsv, '\n');
    _ = again.next();
    while (again.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len == 0) continue;
        var cp = std.mem.splitScalar(u8, line, '\t');
        for (0..n) |k| {
            const c = cp.next() orelse "";
            @memcpy(cols[k].data[fill[k]..][0..c.len], c);
            fill[k] += @intCast(c.len);
            cols[k].offs[row + 1] = fill[k];
        }
        row += 1;
    }
    return .{ .gpa = gpa, .fields = fields, .cols = cols, .records = records };
}

test "fromTsv keeps the columns apart" {
    var t = try fromTsv(std.testing.allocator, "id\tname\n1\tann\n2\t\n3\tcleo\textra\n");
    defer t.deinit();
    try std.testing.expectEqual(@as(usize, 2), t.fields.len);
    try std.testing.expectEqual(@as(u32, 3), t.records);
    var b: [16]u8 = undefined;
    try std.testing.expectEqualStrings("ann", t.display(0, 1, &b));
    try std.testing.expectEqualStrings("", t.display(1, 1, &b));
    try std.testing.expectEqualStrings("cleo", t.display(2, 1, &b));
    try std.testing.expectEqualStrings("3", t.cell(2, 0));
    try std.testing.expectEqual(@as(u16, 4), t.fields[0].width);
}

test "an empty text is a table with no column" {
    var t = try fromTsv(std.testing.allocator, "");
    defer t.deinit();
    try std.testing.expectEqual(@as(usize, 0), t.fields.len);
    try std.testing.expectEqual(@as(u32, 0), t.records);
}
