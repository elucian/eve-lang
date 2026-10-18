//! Legacy and plain-file ingestion (D-184): CSV, TXT, JSON and DBF files become a columnar table, and the columnar table is
//! loaded into SQLite with the explicit `toSqlite`. The decoders only read: a file is never kept as a table.
//!
//! The steps are always the same: a decoder fills a `Raw` (names and text cells), `build` turns it into a columnar table with a
//! type for each column (declared by the file, as DBF does, or found by looking at all the values), and `importInto` loads it.
//! XLS and XLSX are not read yet (they are zip and binary containers): save the sheet as CSV.
const std = @import("std");
const columnar = @import("columnar.zig");
const dbf = @import("dbf.zig");
const sqlite = @import("sqlite.zig");

/// The formats this module can read.
pub const Format = enum { csv, txt, json, dbf };

// Zig tip: the result type `?T` is an optional: a value or `null`. The caller must unwrap it (`if (x) |v|`, `orelse`), so a
// missing value can never be used by accident.
/// The format of a file, from its extension; null when it is not one this module reads.
pub fn formatOf(path: []const u8) ?Format {
    const ext = std.fs.path.extension(path);
    if (std.ascii.eqlIgnoreCase(ext, ".csv")) return .csv;
    if (std.ascii.eqlIgnoreCase(ext, ".txt") or std.ascii.eqlIgnoreCase(ext, ".tsv") or std.ascii.eqlIgnoreCase(ext, ".tab")) return .txt;
    if (std.ascii.eqlIgnoreCase(ext, ".json")) return .json;
    if (std.ascii.eqlIgnoreCase(ext, ".dbf")) return .dbf;
    return null;
}

pub const Error = error{ BadFile, Empty } || dbf.Error || std.mem.Allocator.Error;

// Zig tip: a cell is `?[]const u8`: null is NULL (an empty cell of a CSV, a `null` of JSON). All the slices point into the
// arena of the import, so nothing is freed one by one.
/// The text cells of a file, before the types are known.
const Raw = struct {
    names: [][]const u8,
    /// All the cells, row after row: `cells[row * names.len + col]`.
    cells: []?[]const u8,
    /// The type of each column when the file declares it (DBF); null when the values decide.
    kinds: ?[]columnar.Kind = null,

    // Zig tip: a plain function: the types of the parameters and of the result are written out, and Zig has no default
    // arguments, so a call always passes every parameter.
    fn rows(self: Raw) usize {
        return if (self.names.len == 0) 0 else self.cells.len / self.names.len;
    }
};

// Zig tip: the characters of the first line decide the delimiter of a TXT file: the one that appears most (a tab, a comma, a
// semicolon or a bar), a tab when none appears. A `switch` on a byte needs the cases to be constants.
fn sniff(first: []const u8) u8 {
    var best: u8 = '\t';
    var best_n: usize = 0;
    for ("\t,;|") |d| {
        const n = std.mem.count(u8, first, &.{d});
        if (n > best_n) {
            best = d;
            best_n = n;
        }
    }
    return best;
}

// Zig tip: the CSV reader is a loop over the bytes with two states: inside a quoted cell, a doubled quote is one quote and the
// delimiter and the line breaks are text; outside, the delimiter ends a cell and a line break ends a row. A cell without
// quotes that is empty is NULL; a quoted empty cell is an empty text. The cells are copied into the arena only when they hold
// a doubled quote; otherwise they are slices of the file.
/// Read delimited text into rows of cells; the first row holds the names.
fn readDelimited(a: std.mem.Allocator, bytes: []const u8, delim: u8) Error!Raw {
    var all: std.ArrayList(?[]const u8) = .empty;
    var widths: std.ArrayList(usize) = .empty;
    var i: usize = 0;
    // skip a byte order mark
    if (bytes.len >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF) i = 3;
    var row_len: usize = 0;
    while (i < bytes.len) {
        // one cell
        var cell: ?[]const u8 = null;
        if (bytes[i] == '"') {
            i += 1;
            var buf: std.ArrayList(u8) = .empty;
            while (i < bytes.len) : (i += 1) {
                if (bytes[i] == '"') {
                    if (i + 1 < bytes.len and bytes[i + 1] == '"') {
                        try buf.append(a, '"');
                        i += 1;
                        continue;
                    }
                    i += 1;
                    break;
                }
                try buf.append(a, bytes[i]);
            }
            cell = buf.items;
        } else {
            const start = i;
            while (i < bytes.len and bytes[i] != delim and bytes[i] != '\n' and bytes[i] != '\r') i += 1;
            if (i > start) cell = bytes[start..i];
        }
        try all.append(a, cell);
        row_len += 1;
        // what ends the cell
        if (i < bytes.len and bytes[i] == delim) {
            i += 1;
            if (i >= bytes.len) {
                try all.append(a, null);
                row_len += 1;
            }
            continue;
        }
        if (i < bytes.len and bytes[i] == '\r') i += 1;
        if (i < bytes.len and bytes[i] == '\n') i += 1;
        // a blank line is not a row
        if (row_len == 1 and all.items[all.items.len - 1] == null) {
            _ = all.pop();
            row_len = 0;
            continue;
        }
        try widths.append(a, row_len);
        row_len = 0;
    }
    if (row_len > 0) try widths.append(a, row_len);
    if (widths.items.len == 0) return error.Empty;
    const ncols = widths.items[0];
    // rows are made as wide as the header: a short row gets NULL cells, a long one loses its extra cells
    var cells: std.ArrayList(?[]const u8) = .empty;
    var at: usize = 0;
    for (widths.items, 0..) |w, r| {
        if (r == 0) {
            at += w;
            continue;
        }
        for (0..ncols) |c| try cells.append(a, if (c < w) all.items[at + c] else null);
        at += w;
    }
    const names = try a.alloc([]const u8, ncols);
    for (names, 0..) |*n, c| {
        const raw = std.mem.trim(u8, all.items[c] orelse "", " \t");
        n.* = if (raw.len == 0) try std.fmt.allocPrint(a, "column{d}", .{c + 1}) else raw;
    }
    try uniqueNames(a, names);
    return .{ .names = names, .cells = cells.items };
}

// Zig tip: two columns with the same name cannot be in a table, so the second becomes `name_2`, the third `name_3`. The
// comparison ignores case because SQLite does.
fn uniqueNames(a: std.mem.Allocator, names: [][]const u8) !void {
    for (names, 0..) |*n, i| {
        var k: usize = 2;
        var candidate = n.*;
        while (true) {
            var clash = false;
            for (names[0..i]) |o| {
                if (std.ascii.eqlIgnoreCase(o, candidate)) clash = true;
            }
            if (!clash) break;
            candidate = try std.fmt.allocPrint(a, "{s}_{d}", .{ n.*, k });
            k += 1;
        }
        n.* = candidate;
    }
}

// Zig tip: `std.json.parseFromSlice(std.json.Value, ...)` reads any JSON into a tree of `Value`s that lives in the arena.
// The file must be an array of objects (or an object with one array in it); the columns are the keys, in the order they first
// appear. A number is kept as its own text, so the types are found later like for CSV; a nested object or array is written back
// as JSON text.
fn readJson(a: std.mem.Allocator, bytes: []const u8) Error!Raw {
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, a, bytes, .{}) catch return error.BadFile;
    var list = parsed;
    if (list == .object) {
        var it = list.object.iterator();
        var found: ?std.json.Value = null;
        while (it.next()) |e| {
            if (e.value_ptr.* == .array) {
                found = e.value_ptr.*;
                break;
            }
        }
        list = found orelse return error.BadFile;
    }
    if (list != .array) return error.BadFile;
    var names: std.ArrayList([]const u8) = .empty;
    for (list.array.items) |row| {
        if (row != .object) return error.BadFile;
        var it = row.object.iterator();
        while (it.next()) |e| {
            var seen = false;
            for (names.items) |n| {
                if (std.mem.eql(u8, n, e.key_ptr.*)) seen = true;
            }
            if (!seen) try names.append(a, e.key_ptr.*);
        }
    }
    if (names.items.len == 0) return error.Empty;
    var cells: std.ArrayList(?[]const u8) = .empty;
    for (list.array.items) |row| {
        for (names.items) |n| {
            const v = row.object.get(n) orelse {
                try cells.append(a, null);
                continue;
            };
            try cells.append(a, switch (v) {
                .null => null,
                .bool => |b| if (b) "true" else "false",
                .integer => |x| try std.fmt.allocPrint(a, "{d}", .{x}),
                .float => |x| try std.fmt.allocPrint(a, "{d}", .{x}),
                .number_string => |s| s,
                .string => |s| s,
                else => try std.json.Stringify.valueAlloc(a, v, .{}),
            });
        }
    }
    return .{ .names = names.items, .cells = cells.items };
}

// Zig tip: a DBF file declares its types, so the columns are made from them: N without decimals is an integer, N or F with
// decimals a real, D a date, L a boolean, the rest text. A blank cell is NULL. `Stream` reads the records one by one; each cell
// is copied into the arena because the stream's buffer changes.
fn readDbf(a: std.mem.Allocator, bytes: []const u8) Error!Raw {
    var s = try dbf.Stream.init(bytes);
    const fs = s.fields();
    if (fs.len == 0) return error.Empty;
    const names = try a.alloc([]const u8, fs.len);
    const kinds = try a.alloc(columnar.Kind, fs.len);
    for (fs, 0..) |f, i| {
        names[i] = try a.dupe(u8, f.nameSlice());
        kinds[i] = switch (f.kind) {
            'N', 'F' => if (f.decimals == 0 and f.length <= 18) .integer else .real,
            'D' => .date,
            'L' => .boolean,
            else => .text,
        };
    }
    try uniqueNames(a, names);
    var cells: std.ArrayList(?[]const u8) = .empty;
    var buf: [16]u8 = undefined;
    while (s.next()) {
        for (0..fs.len) |i| {
            const t = s.cell(i, &buf);
            try cells.append(a, if (t.len == 0 and kinds[i] != .text) null else try utf8Copy(a, t));
        }
    }
    return .{ .names = names, .cells = cells.items, .kinds = kinds };
}

// Zig tip: an old DBF file stores its text in the code page of the machine that made it (the header says which one with a
// byte that this reader does not use). A text that is valid UTF-8 is kept as it is; any other text is read as Latin-1, where
// each byte is the code point of the same number, and written as UTF-8 (a byte from 0x80 to 0xFF takes two bytes). `utf8Encode`
// writes a code point into a buffer and answers how many bytes it used.
/// Copy a text into the arena as UTF-8: as it is when it is valid UTF-8, else read as Latin-1.
fn utf8Copy(a: std.mem.Allocator, t: []const u8) ![]const u8 {
    if (std.unicode.utf8ValidateSlice(t)) return a.dupe(u8, t);
    var out: std.ArrayList(u8) = .empty;
    for (t) |b| {
        var enc: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(b, &enc) catch unreachable;
        try out.appendSlice(a, enc[0..n]);
    }
    return out.items;
}

// Zig tip: `isBoolWord` relies on the same Zig feature as `rows` above: see the tip there.
fn isBoolWord(s: []const u8) bool {
    return std.ascii.eqlIgnoreCase(s, "true") or std.ascii.eqlIgnoreCase(s, "false");
}

// Zig tip: `f() catch x` uses `x` when `f` fails; `catch {}` drops the error on purpose. Zig refuses to compile an error
// that nobody handles.
fn isInteger(s: []const u8) bool {
    const body = if (s.len > 0 and s[0] == '-') s[1..] else s;
    if (body.len == 0 or (body.len > 1 and body[0] == '0')) return false;
    for (body) |ch| {
        if (ch < '0' or ch > '9') return false;
    }
    _ = std.fmt.parseInt(i64, s, 10) catch return false;
    return true;
}

// Zig tip: `isReal` relies on the same Zig feature as `isInteger` above: see the tip there.
fn isReal(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |ch| {
        if (!(std.ascii.isDigit(ch) or ch == '.' or ch == '-' or ch == '+' or ch == 'e' or ch == 'E')) return false;
    }
    if (s.len > 1 and s[0] == '0' and s[1] != '.') return false;
    _ = std.fmt.parseFloat(f64, s) catch return false;
    return true;
}

// Zig tip: the kind of a column is the narrowest one that all its values fit, tried in order: boolean words, integers, reals,
// dates, and text for anything else. A column where every cell is NULL is text. One pass over the column decides.
fn inferKind(raw: Raw, col: usize) columnar.Kind {
    var all_bool = true;
    var all_int = true;
    var all_real = true;
    var all_date = true;
    var any = false;
    const n = raw.names.len;
    for (0..raw.rows()) |r| {
        const cell = raw.cells[r * n + col] orelse continue;
        any = true;
        if (!isBoolWord(cell)) all_bool = false;
        if (!isInteger(cell)) all_int = false;
        if (!isReal(cell)) all_real = false;
        if (cell.len != 10 or columnar.parseDate(cell) == null) all_date = false;
    }
    if (!any) return .text;
    if (all_bool) return .boolean;
    if (all_int) return .integer;
    if (all_real) return .real;
    if (all_date) return .date;
    return .text;
}

// Zig tip: `errdefer` runs its statement only when the function leaves with an error, so what was made before the failure
// is freed and nothing leaks; on success it does nothing.
/// Turn the text cells into a columnar table with a type for each column.
fn build(gpa: std.mem.Allocator, raw: Raw) Error!columnar.Table {
    var t = columnar.Table.init(gpa);
    errdefer t.deinit();
    const n = raw.names.len;
    for (raw.names, 0..) |name, c| {
        const kind = if (raw.kinds) |k| k[c] else inferKind(raw, c);
        _ = try t.addColumn(name, kind);
    }
    for (0..raw.rows()) |r| {
        for (0..n) |c| {
            const cell = raw.cells[r * n + c] orelse {
                try t.appendNull(c);
                continue;
            };
            switch (t.cols.items[c].kind) {
                .integer => if (std.fmt.parseInt(i64, std.mem.trim(u8, cell, " "), 10)) |v| try t.appendInt(c, v) else |_| try t.appendNull(c),
                .real => if (std.fmt.parseFloat(f64, std.mem.trim(u8, cell, " "))) |v| try t.appendReal(c, v) else |_| try t.appendNull(c),
                .boolean => try t.appendInt(c, if (std.ascii.eqlIgnoreCase(cell, "true") or std.mem.eql(u8, cell, "1")) 1 else 0),
                .date => if (columnar.parseDate(cell)) |d| try t.appendInt(c, d) else try t.appendNull(c),
                .timestamp => try t.appendNull(c),
                .text => try t.appendText(c, cell),
            }
        }
        t.endRow();
    }
    return t;
}

// Zig tip: `defer` runs its statement when the scope ends, by any path (a `return`, an error, the end of the block), so a
// free or a close is written once, next to what it undoes.
/// Decode the bytes of a file into a columnar table (not yet in a database).
pub fn parse(gpa: std.mem.Allocator, bytes: []const u8, format: Format) Error!columnar.Table {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const raw = switch (format) {
        .csv => try readDelimited(a, bytes, ','),
        .txt => blk: {
            const first = bytes[0..(std.mem.indexOfScalar(u8, bytes, '\n') orelse bytes.len)];
            break :blk try readDelimited(a, bytes, sniff(first));
        },
        .json => try readJson(a, bytes),
        .dbf => try readDbf(a, bytes),
    };
    return build(gpa, raw);
}

// Zig tip: `Result` relies on the same Zig feature as `Raw` above: see the tip there.
/// What an import made.
pub const Result = struct { rows: usize, cols: usize };

// Zig tip: `importInto` relies on the same Zig feature as `parse` above: see the tip there.
/// Read a file and load it into `db` as the new table `table` (explicit load, in one transaction).
pub fn importInto(gpa: std.mem.Allocator, db: *sqlite.Db, bytes: []const u8, format: Format, table: []const u8) !Result {
    var t = try parse(gpa, bytes, format);
    defer t.deinit();
    try t.toSqlite(db, table);
    return .{ .rows = t.rows, .cols = t.cols.items.len };
}

// Zig tip: an export reads the table into columns first (the explicit store, `fromQuery`) and then writes them in the format
// asked for. The three writers walk the same columns: CSV quotes a cell that holds a comma, a quote or a line break, JSON writes
// numbers as numbers and NULL as null, and DBF gives each column a width found from its values (names are cut to ten bytes).
/// The bytes of the table `table` of `db` in the format `format` (CSV, JSON or DBF); the caller frees them.
pub fn exportBytes(gpa: std.mem.Allocator, db: *sqlite.Db, table: []const u8, format: Format, date: [3]u8) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const sql = try std.fmt.allocPrintSentinel(a, "select * from \"{s}\"", .{table}, 0);
    var t = try columnar.Table.fromQuery(gpa, db, sql);
    defer t.deinit();
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    switch (format) {
        .csv, .txt => {
            const d: u8 = if (format == .csv) ',' else '\t';
            for (t.cols.items, 0..) |c, k| {
                if (k > 0) try out.append(gpa, d);
                try csvCell(&out, gpa, c.name, d);
            }
            try out.append(gpa, '\n');
            for (0..t.rows) |r| {
                for (t.cols.items, 0..) |_, k| {
                    if (k > 0) try out.append(gpa, d);
                    if (t.isNull(k, r)) continue;
                    const cell = try cellText(a, &t, k, r);
                    try csvCell(&out, gpa, cell, d);
                }
                try out.append(gpa, '\n');
            }
        },
        .json => {
            try out.appendSlice(gpa, "[");
            for (0..t.rows) |r| {
                try out.appendSlice(gpa, if (r == 0) "\n  {" else ",\n  {");
                for (t.cols.items, 0..) |c, k| {
                    if (k > 0) try out.appendSlice(gpa, ", ");
                    try jsonString(&out, gpa, c.name);
                    try out.appendSlice(gpa, ": ");
                    if (t.isNull(k, r)) {
                        try out.appendSlice(gpa, "null");
                    } else switch (c.kind) {
                        .integer, .real => try out.appendSlice(gpa, try cellText(a, &t, k, r)),
                        else => try jsonString(&out, gpa, try cellText(a, &t, k, r)),
                    }
                }
                try out.append(gpa, '}');
            }
            try out.appendSlice(gpa, if (t.rows == 0) "]\n" else "\n]\n");
        },
        .dbf => {
            if (t.cols.items.len == 0 or t.cols.items.len > dbf.max_fields) return error.BadFile;
            const fields = try a.alloc(dbf.Field, t.cols.items.len);
            for (t.cols.items, 0..) |c, k| {
                var f: dbf.Field = .{};
                f.setName(c.name);
                switch (c.kind) {
                    .integer => f = withKind(f, 'N', 18, 0),
                    .real => f = withKind(f, 'N', 20, 6),
                    else => {
                        var widest: usize = 1;
                        for (0..t.rows) |r| {
                            if (!t.isNull(k, r)) widest = @max(widest, t.text(k, r).len);
                        }
                        f = withKind(f, 'C', @intCast(@min(widest, 254)), 0);
                    },
                }
                fields[k] = f;
            }
            var w = dbf.Writer.init(gpa, fields, date);
            defer w.deinit();
            const cells = try a.alloc([]const u8, fields.len);
            for (0..t.rows) |r| {
                for (t.cols.items, 0..) |c, k| {
                    cells[k] = if (t.isNull(k, r)) "" else switch (c.kind) {
                        .real => try std.fmt.allocPrint(a, "{d:.6}", .{t.real(k, r)}),
                        else => try cellText(a, &t, k, r),
                    };
                }
                try w.add(cells);
            }
            out.deinit(gpa);
            return w.finish();
        },
    }
    return out.toOwnedSlice(gpa);
}

// Zig tip: `withKind` relies on the same Zig feature as `rows` above: see the tip there.
fn withKind(f: dbf.Field, kind: u8, length: u8, decimals: u8) dbf.Field {
    var g = f;
    g.kind = kind;
    g.length = length;
    g.decimals = decimals;
    return g;
}

// Zig tip: `cellText` relies on the same Zig feature as `readDelimited` above: see the tip there.
fn cellText(a: std.mem.Allocator, t: *const columnar.Table, col: usize, row: usize) ![]const u8 {
    return switch (t.cols.items[col].kind) {
        .integer, .boolean, .date, .timestamp => try std.fmt.allocPrint(a, "{d}", .{t.int(col, row)}),
        .real => try std.fmt.allocPrint(a, "{d}", .{t.real(col, row)}),
        .text => t.text(col, row),
    };
}

// Zig tip: `csvCell` relies on the same Zig feature as `readDelimited` above: see the tip there.
fn csvCell(out: *std.ArrayList(u8), gpa: std.mem.Allocator, cell: []const u8, delim: u8) !void {
    const plain = std.mem.indexOfAny(u8, cell, "\"\r\n") == null and std.mem.indexOfScalar(u8, cell, delim) == null;
    if (plain) return out.appendSlice(gpa, cell);
    try out.append(gpa, '"');
    for (cell) |ch| {
        if (ch == '"') try out.append(gpa, '"');
        try out.append(gpa, ch);
    }
    try out.append(gpa, '"');
}

// Zig tip: `jsonString` relies on the same Zig feature as `readDelimited` above: see the tip there.
fn jsonString(out: *std.ArrayList(u8), gpa: std.mem.Allocator, s: []const u8) !void {
    try out.append(gpa, '"');
    for (s) |ch| switch (ch) {
        '"' => try out.appendSlice(gpa, "\\\""),
        '\\' => try out.appendSlice(gpa, "\\\\"),
        '\n' => try out.appendSlice(gpa, "\\n"),
        '\r' => try out.appendSlice(gpa, "\\r"),
        '\t' => try out.appendSlice(gpa, "\\t"),
        else => if (ch < 0x20) try out.print(gpa, "\\u{x:0>4}", .{ch}) else try out.append(gpa, ch),
    };
    try out.append(gpa, '"');
}

// Zig tip: a `test` block is compiled only by `zig build test`; `try std.testing.expect…` fails the test, with the values,
// when a check is false.
test "export: csv quotes, json types, and a dbf that reads back" {
    var db = try sqlite.Db.open(":memory:");
    defer db.close();
    try db.exec("create table t (id integer, name text, price real); insert into t values (1, 'a, b', 2.5), (2, null, null);");
    const csv = try exportBytes(std.testing.allocator, &db, "t", .csv, .{ 126, 1, 1 });
    defer std.testing.allocator.free(csv);
    try std.testing.expectEqualStrings("id,name,price\n1,\"a, b\",2.5\n2,,\n", csv);
    const json = try exportBytes(std.testing.allocator, &db, "t", .json, .{ 126, 1, 1 });
    defer std.testing.allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"price\": 2.5") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"name\": null") != null);
    const bytes = try exportBytes(std.testing.allocator, &db, "t", .dbf, .{ 126, 1, 1 });
    defer std.testing.allocator.free(bytes);
    var db2 = try sqlite.Db.open(":memory:");
    defer db2.close();
    const res = try importInto(std.testing.allocator, &db2, bytes, .dbf, "back");
    try std.testing.expectEqual(@as(usize, 2), res.rows);
}

// Zig tip: test "csv: quotes, a doubled quote, a short row and the types found" relies on the same Zig feature as test
// "export: csv quotes, json types, and a dbf that reads back" above: see the tip there.
test "csv: quotes, a doubled quote, a short row and the types found" {
    const csv = "id,name,price,day\n1,\"Smith, J\",2.5,2026-10-01\n2,\"say \"\"hi\"\"\",,2026-10-02\n3,plain\n";
    var t = try parse(std.testing.allocator, csv, .csv);
    defer t.deinit();
    try std.testing.expectEqual(@as(usize, 3), t.rows);
    try std.testing.expectEqual(columnar.Kind.integer, t.cols.items[0].kind);
    try std.testing.expectEqual(columnar.Kind.real, t.cols.items[2].kind);
    try std.testing.expectEqual(columnar.Kind.date, t.cols.items[3].kind);
    try std.testing.expectEqualStrings("Smith, J", t.text(1, 0));
    try std.testing.expectEqualStrings("say \"hi\"", t.text(1, 1));
    try std.testing.expect(t.isNull(2, 1));
    try std.testing.expect(t.isNull(3, 2));
}

// Zig tip: test "txt: the delimiter is found, a leading zero stays text" relies on the same Zig feature as test "export:
// csv quotes, json types, and a dbf that reads back" above: see the tip there.
test "txt: the delimiter is found, a leading zero stays text" {
    var t = try parse(std.testing.allocator, "code;qty\n007;5\n010;6\n", .txt);
    defer t.deinit();
    try std.testing.expectEqual(columnar.Kind.text, t.cols.items[0].kind);
    try std.testing.expectEqual(columnar.Kind.integer, t.cols.items[1].kind);
    try std.testing.expectEqualStrings("007", t.text(0, 0));
}

// Zig tip: test "json: an array of objects with different keys" relies on the same Zig feature as test "export: csv quotes,
// json types, and a dbf that reads back" above: see the tip there.
test "json: an array of objects with different keys" {
    var t = try parse(std.testing.allocator, "[{\"a\":1,\"b\":\"x\"},{\"a\":2,\"c\":true},{\"a\":null}]", .json);
    defer t.deinit();
    try std.testing.expectEqual(@as(usize, 3), t.cols.items.len);
    try std.testing.expectEqual(@as(usize, 3), t.rows);
    try std.testing.expectEqual(columnar.Kind.integer, t.cols.items[0].kind);
    try std.testing.expectEqual(columnar.Kind.boolean, t.cols.items[2].kind);
    try std.testing.expect(t.isNull(0, 2));
}

// Zig tip: test "dbf goes through the stream into SQLite" relies on the same Zig feature as test "export: csv quotes, json
// types, and a dbf that reads back" above: see the tip there.
test "dbf goes through the stream into SQLite" {
    var f1: dbf.Field = .{ .kind = 'C', .length = 8 };
    f1.setName("name");
    var f2: dbf.Field = .{ .kind = 'N', .length = 6, .decimals = 2 };
    f2.setName("price");
    var f3: dbf.Field = .{ .kind = 'N', .length = 4 };
    f3.setName("qty");
    const fields = [_]dbf.Field{ f1, f2, f3 };
    var w = dbf.Writer.init(std.testing.allocator, &fields, .{ 126, 10, 17 });
    defer w.deinit();
    try w.add(&.{ "bolt", "1.50", "10" });
    try w.add(&.{ "nut", "0.25", "" });
    const bytes = try w.finish();
    defer std.testing.allocator.free(bytes);
    var db = try sqlite.Db.open(":memory:");
    defer db.close();
    const res = try importInto(std.testing.allocator, &db, bytes, .dbf, "parts");
    try std.testing.expectEqual(@as(usize, 2), res.rows);
    var back = try columnar.Table.fromQuery(std.testing.allocator, &db, "select name, price, qty from parts order by name");
    defer back.deinit();
    try std.testing.expectEqual(@as(f64, 1.5), back.real(1, 0));
    try std.testing.expect(back.isNull(2, 1));
}

// Zig tip: test "a DBF text in Latin-1 becomes UTF-8" relies on the same Zig feature as test "export: csv quotes, json
// types, and a dbf that reads back" above: see the tip there.
test "a DBF text in Latin-1 becomes UTF-8" {
    var f1: dbf.Field = .{ .kind = 'C', .length = 6 };
    f1.setName("name");
    var w = dbf.Writer.init(std.testing.allocator, &.{f1}, .{ 126, 1, 1 });
    defer w.deinit();
    try w.add(&.{"caf\xe9"});
    const bytes = try w.finish();
    defer std.testing.allocator.free(bytes);
    var t = try parse(std.testing.allocator, bytes, .dbf);
    defer t.deinit();
    try std.testing.expectEqualStrings("caf\xc3\xa9", t.text(0, 0));
}
