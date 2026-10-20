//! @eve-module ide.sqlstruct
//! @decision D-193
//! @tests code/evecm/src/ide/sqlstruct.zig (zig build test)
//! The structure of a SQLite table as the structure dialog edits it: a list of columns (name, type, not null, key,
//! default), read from the result of `pragma table_info`, and the SQL script that rebuilds the table with the new
//! columns. SQLite changes some things only by making a new table, copying the rows and renaming (a new type for a column,
//! a changed key), so the script always does that, which keeps the data of the columns that stay.
const std = @import("std");

pub const max_name = 47;
pub const max_type = 27;
pub const max_default = 39;

/// The types in the list of the dialog.
pub const types = [_][]const u8{ "INTEGER", "BIGINT", "REAL", "TEXT", "BLOB", "NUMERIC", "BOOLEAN", "DATE", "TIMESTAMP", "DECIMAL(12,2)" };

/// One column of the table.
pub const Col = struct {
    name: [48]u8 = @as([48]u8, @splat(0)),
    ty: [28]u8 = @as([28]u8, @splat(0)),
    notnull: bool = false,
    pk: bool = false,
    dflt: [40]u8 = @as([40]u8, @splat(0)),
    /// The place of this column in the table as it is now (null for a new column).
    src: ?usize = null,

    pub fn nameS(self: *const Col) []const u8 {
        return std.mem.sliceTo(&self.name, 0);
    }
    pub fn typeS(self: *const Col) []const u8 {
        return std.mem.sliceTo(&self.ty, 0);
    }
    pub fn defaultS(self: *const Col) []const u8 {
        return std.mem.sliceTo(&self.dflt, 0);
    }
    pub fn setName(self: *Col, s: []const u8) void {
        fill(&self.name, s);
    }
    pub fn setType(self: *Col, s: []const u8) void {
        fill(&self.ty, s);
    }
    pub fn setDefault(self: *Col, s: []const u8) void {
        fill(&self.dflt, s);
    }
};

fn fill(dst: []u8, s: []const u8) void {
    @memset(dst, 0);
    const n = @min(s.len, dst.len - 1);
    @memcpy(dst[0..n], s[0..n]);
}

/// A message about what is wrong with a column, or null.
pub fn check(c: *const Col) ?[]const u8 {
    const n = c.nameS();
    if (n.len == 0) return "a column needs a name";
    if (std.mem.indexOfScalar(u8, n, '"') != null) return "a name has no double quote";
    if (c.typeS().len == 0) return "a column needs a type";
    return null;
}

/// Read the columns from the text of `pragma table_info` (tab separated, with a header line).
pub fn parseTableInfo(gpa: std.mem.Allocator, tsv: []const u8, out: *std.ArrayList(Col)) !void {
    var lines = std.mem.splitScalar(u8, tsv, '\n');
    _ = lines.next(); // header
    var idx: usize = 0;
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len == 0) continue;
        var f = std.mem.splitScalar(u8, line, '\t');
        _ = f.next(); // cid
        const name = f.next() orelse "";
        const ty = f.next() orelse "";
        const nn = f.next() orelse "0";
        const dv = f.next() orelse "";
        const pk = f.next() orelse "0";
        var c: Col = .{ .notnull = std.mem.eql(u8, nn, "1"), .pk = !std.mem.eql(u8, pk, "0") and pk.len > 0, .src = idx };
        c.setName(name);
        c.setType(if (ty.len == 0) "TEXT" else ty);
        c.setDefault(dv);
        try out.append(gpa, c);
        idx += 1;
    }
}

fn quoteIdent(w: *std.ArrayList(u8), gpa: std.mem.Allocator, name: []const u8) !void {
    try w.append(gpa, '"');
    try w.appendSlice(gpa, name);
    try w.append(gpa, '"');
}

fn writeColumns(w: *std.ArrayList(u8), gpa: std.mem.Allocator, cols: []const Col, pk_count: usize) !void {
    for (cols, 0..) |c, i| {
        if (i > 0) try w.appendSlice(gpa, ", ");
        try quoteIdent(w, gpa, c.nameS());
        try w.append(gpa, ' ');
        try w.appendSlice(gpa, c.typeS());
        if (c.pk and pk_count == 1) {
            try w.appendSlice(gpa, " primary key");
        } else if (c.notnull) try w.appendSlice(gpa, " not null");
        if (c.defaultS().len > 0) {
            try w.appendSlice(gpa, " default ");
            try w.appendSlice(gpa, c.defaultS());
        }
    }
    if (pk_count > 1) {
        try w.appendSlice(gpa, ", primary key (");
        var first = true;
        for (cols) |c| {
            if (!c.pk) continue;
            if (!first) try w.appendSlice(gpa, ", ");
            first = false;
            try quoteIdent(w, gpa, c.nameS());
        }
        try w.append(gpa, ')');
    }
}

/// The script that makes the table `table` with the columns `cols` (a new table, nothing to copy).
pub fn buildCreate(gpa: std.mem.Allocator, table: []const u8, cols: []const Col) ![]u8 {
    var w: std.ArrayList(u8) = .empty;
    errdefer w.deinit(gpa);
    var pk_count: usize = 0;
    for (cols) |c| pk_count += @intFromBool(c.pk);
    try w.appendSlice(gpa, "create table ");
    try quoteIdent(&w, gpa, table);
    try w.appendSlice(gpa, " (");
    try writeColumns(&w, gpa, cols, pk_count);
    try w.appendSlice(gpa, ");");
    return w.toOwnedSlice(gpa);
}

/// The script that gives table `table` the columns `cols`, keeping the data of the columns that come from the old table
/// (`orig` holds the old columns: a `src` is a place in it, so a renamed column is read under its old name).
pub fn buildScript(gpa: std.mem.Allocator, table: []const u8, cols: []const Col, orig: []const Col) ![]u8 {
    var w: std.ArrayList(u8) = .empty;
    errdefer w.deinit(gpa);
    var pk_count: usize = 0;
    for (cols) |c| pk_count += @intFromBool(c.pk);
    try w.appendSlice(gpa, "pragma foreign_keys = off; begin; create table ");
    try quoteIdent(&w, gpa, "__evetx_new");
    try w.appendSlice(gpa, " (");
    try writeColumns(&w, gpa, cols, pk_count);
    try w.appendSlice(gpa, "); ");
    // copy the rows of the columns that stay
    var any = false;
    for (cols) |c| any = any or c.src != null;
    if (any) {
        try w.appendSlice(gpa, "insert into ");
        try quoteIdent(&w, gpa, "__evetx_new");
        try w.appendSlice(gpa, " (");
        var first = true;
        for (cols) |c| {
            if (c.src == null) continue;
            if (!first) try w.appendSlice(gpa, ", ");
            first = false;
            try quoteIdent(&w, gpa, c.nameS());
        }
        try w.appendSlice(gpa, ") select ");
        first = true;
        for (cols) |c| {
            if (c.src == null) continue;
            if (!first) try w.appendSlice(gpa, ", ");
            first = false;
            try quoteIdent(&w, gpa, orig[c.src.?].nameS());
        }
        try w.appendSlice(gpa, " from ");
        try quoteIdent(&w, gpa, table);
        try w.appendSlice(gpa, "; ");
    }
    try w.appendSlice(gpa, "drop table ");
    try quoteIdent(&w, gpa, table);
    try w.appendSlice(gpa, "; alter table ");
    try quoteIdent(&w, gpa, "__evetx_new");
    try w.appendSlice(gpa, " rename to ");
    try quoteIdent(&w, gpa, table);
    try w.appendSlice(gpa, "; commit; pragma foreign_keys = on;");
    return w.toOwnedSlice(gpa);
}

test "table info and the rebuild script" {
    const gpa = std.testing.allocator;
    var cols: std.ArrayList(Col) = .empty;
    defer cols.deinit(gpa);
    try parseTableInfo(gpa, "cid\tname\ttype\tnotnull\tdflt_value\tpk\n0\tid\tINTEGER\t1\t\t1\n1\tname\tTEXT\t0\t\t0\n", &cols);
    try std.testing.expectEqual(@as(usize, 2), cols.items.len);
    try std.testing.expect(cols.items[0].pk and cols.items[0].notnull);
    var orig: std.ArrayList(Col) = .empty;
    defer orig.deinit(gpa);
    try orig.appendSlice(gpa, cols.items);
    cols.items[1].setName("title");
    var extra: Col = .{};
    extra.setName("qty");
    extra.setType("INTEGER");
    try cols.append(gpa, extra);
    const script = try buildScript(gpa, "items", cols.items, orig.items);
    defer gpa.free(script);
    try std.testing.expect(std.mem.indexOf(u8, script, "\"id\" INTEGER primary key") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "select \"id\", \"name\" from \"items\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "rename to \"items\"") != null);
}

test "the script of a new table" {
    const gpa = std.testing.allocator;
    var id: Col = .{ .pk = true, .notnull = true };
    id.setName("id");
    id.setType("INTEGER");
    var title: Col = .{ .notnull = true };
    title.setName("title");
    title.setType("TEXT");
    const script = try buildCreate(gpa, "notes", &.{ id, title });
    defer gpa.free(script);
    try std.testing.expectEqualStrings("create table \"notes\" (\"id\" INTEGER primary key, \"title\" TEXT not null);", script);
}
