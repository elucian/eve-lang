//! Columnar tables in memory (D-184): the table of Eve's computational pipelines.
//!
//! The layout is a struct of arrays (SoA): each column owns one contiguous array of its own type (64 bit integers, 64 bit
//! floats, or an array of offsets over one byte buffer for text), and a bitmap that says which cells are not NULL. There is no
//! object for a row; a column is the unit of the filter, the sum, the sort and the join, and a loop over one array is the
//! kind of loop the compiler can vectorize. SQLite `:memory:` is the other engine (the query engine): the two meet only
//! through `toSqlite` (load) and `fromQuery` (store), which are explicit calls, never done by themselves.
const std = @import("std");
const sqlite = @import("sqlite.zig");

/// The type of a column.
pub const Kind = enum { integer, real, boolean, date, timestamp, text };

const Data = union(enum) {
    ints: std.ArrayList(i64),
    reals: std.ArrayList(f64),
    text: struct { offs: std.ArrayList(u32), bytes: std.ArrayList(u8) },
};

/// One column: a name, a type, the values and the bitmap of the cells that are not NULL.
pub const Column = struct {
    name: []u8,
    kind: Kind,
    data: Data,
    /// One bit for each cell: 1 when the cell holds a value, 0 for NULL.
    valid: std.ArrayList(u64) = .empty,
    len: usize = 0,

    fn setValid(self: *Column, gpa: std.mem.Allocator, on: bool) !void {
        if (self.len % 64 == 0) try self.valid.append(gpa, 0);
        if (on) self.valid.items[self.len / 64] |= @as(u64, 1) << @intCast(self.len % 64);
    }

    /// Is the cell `row` a value (not NULL)?
    pub fn isValid(self: *const Column, row: usize) bool {
        return self.valid.items[row / 64] >> @intCast(row % 64) & 1 == 1;
    }
};

/// A comparison for `filterInt`.
pub const Cmp = enum { eq, ne, lt, le, gt, ge };

pub const Table = struct {
    gpa: std.mem.Allocator,
    cols: std.ArrayList(Column) = .empty,
    rows: usize = 0,

    pub fn init(gpa: std.mem.Allocator) Table {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Table) void {
        for (self.cols.items) |*c| {
            self.gpa.free(c.name);
            switch (c.data) {
                .ints => |*a| a.deinit(self.gpa),
                .reals => |*a| a.deinit(self.gpa),
                .text => |*t| {
                    t.offs.deinit(self.gpa);
                    t.bytes.deinit(self.gpa);
                },
            }
            c.valid.deinit(self.gpa);
        }
        self.cols.deinit(self.gpa);
    }

    /// Add a column (before the first row); the answer is its number.
    pub fn addColumn(self: *Table, name: []const u8, kind: Kind) !usize {
        const copy = try self.gpa.dupe(u8, name);
        errdefer self.gpa.free(copy);
        const data: Data = switch (kind) {
            .integer, .boolean, .date, .timestamp => .{ .ints = .empty },
            .real => .{ .reals = .empty },
            .text => .{ .text = .{ .offs = .empty, .bytes = .empty } },
        };
        try self.cols.append(self.gpa, .{ .name = copy, .kind = kind, .data = data });
        if (kind == .text) try self.cols.items[self.cols.items.len - 1].data.text.offs.append(self.gpa, 0);
        return self.cols.items.len - 1;
    }

    pub fn appendInt(self: *Table, col: usize, v: i64) !void {
        const c = &self.cols.items[col];
        try c.data.ints.append(self.gpa, v);
        try c.setValid(self.gpa, true);
        c.len += 1;
    }

    pub fn appendReal(self: *Table, col: usize, v: f64) !void {
        const c = &self.cols.items[col];
        try c.data.reals.append(self.gpa, v);
        try c.setValid(self.gpa, true);
        c.len += 1;
    }

    pub fn appendText(self: *Table, col: usize, v: []const u8) !void {
        const c = &self.cols.items[col];
        try c.data.text.bytes.appendSlice(self.gpa, v);
        try c.data.text.offs.append(self.gpa, @intCast(c.data.text.bytes.items.len));
        try c.setValid(self.gpa, true);
        c.len += 1;
    }

    pub fn appendNull(self: *Table, col: usize) !void {
        const c = &self.cols.items[col];
        switch (c.data) {
            .ints => |*a| try a.append(self.gpa, 0),
            .reals => |*a| try a.append(self.gpa, 0),
            .text => |*t| try t.offs.append(self.gpa, @intCast(t.bytes.items.len)),
        }
        try c.setValid(self.gpa, false);
        c.len += 1;
    }

    /// Close the row: every column has one more cell.
    pub fn endRow(self: *Table) void {
        self.rows += 1;
        for (self.cols.items) |c| std.debug.assert(c.len == self.rows);
    }

    pub fn int(self: *const Table, col: usize, row: usize) i64 {
        return self.cols.items[col].data.ints.items[row];
    }

    pub fn real(self: *const Table, col: usize, row: usize) f64 {
        return self.cols.items[col].data.reals.items[row];
    }

    pub fn text(self: *const Table, col: usize, row: usize) []const u8 {
        const t = self.cols.items[col].data.text;
        return t.bytes.items[t.offs.items[row]..t.offs.items[row + 1]];
    }

    pub fn isNull(self: *const Table, col: usize, row: usize) bool {
        return !self.cols.items[col].isValid(row);
    }

    // ---------------------------------------------------------------- column kernels

    /// The sum of the integer cells that are not NULL.
    pub fn sumInt(self: *const Table, col: usize) i64 {
        const c = &self.cols.items[col];
        var s: i64 = 0;
        for (c.data.ints.items, 0..) |v, i| {
            if (c.isValid(i)) s +%= v;
        }
        return s;
    }

    /// The sum of the real cells that are not NULL.
    pub fn sumReal(self: *const Table, col: usize) f64 {
        const c = &self.cols.items[col];
        var s: f64 = 0;
        for (c.data.reals.items, 0..) |v, i| {
            if (c.isValid(i)) s += v;
        }
        return s;
    }

    /// How many cells of the column are not NULL.
    pub fn countValid(self: *const Table, col: usize) usize {
        const c = &self.cols.items[col];
        var n: usize = 0;
        for (c.valid.items) |w| n += @popCount(w);
        return n;
    }

    /// The smallest and the largest integer cell that is not NULL, or null when the column has none.
    pub fn minMaxInt(self: *const Table, col: usize) ?[2]i64 {
        const c = &self.cols.items[col];
        var lo: i64 = std.math.maxInt(i64);
        var hi: i64 = std.math.minInt(i64);
        var any = false;
        for (c.data.ints.items, 0..) |v, i| {
            if (!c.isValid(i)) continue;
            any = true;
            lo = @min(lo, v);
            hi = @max(hi, v);
        }
        return if (any) .{ lo, hi } else null;
    }

    /// The smallest and the largest real cell that is not NULL, or null when the column has none.
    pub fn minMaxReal(self: *const Table, col: usize) ?[2]f64 {
        const c = &self.cols.items[col];
        var lo: f64 = std.math.inf(f64);
        var hi: f64 = -std.math.inf(f64);
        var any = false;
        for (c.data.reals.items, 0..) |v, i| {
            if (!c.isValid(i)) continue;
            any = true;
            lo = @min(lo, v);
            hi = @max(hi, v);
        }
        return if (any) .{ lo, hi } else null;
    }

    /// The rows where the real cell compares to `v` (NULL cells never match), in order.
    pub fn filterReal(self: *const Table, col: usize, cmp: Cmp, v: f64, out: *std.ArrayList(u32)) !void {
        const c = &self.cols.items[col];
        for (c.data.reals.items, 0..) |x, i| {
            if (!c.isValid(i)) continue;
            const hit = switch (cmp) {
                .eq => x == v,
                .ne => x != v,
                .lt => x < v,
                .le => x <= v,
                .gt => x > v,
                .ge => x >= v,
            };
            if (hit) try out.append(self.gpa, @intCast(i));
        }
    }

    /// The rows where the text cell is equal (`.eq`) or not equal (`.ne`) to `v`, or compares to it byte by byte.
    pub fn filterText(self: *const Table, col: usize, cmp: Cmp, v: []const u8, out: *std.ArrayList(u32)) !void {
        const c = &self.cols.items[col];
        for (0..c.len) |i| {
            if (!c.isValid(i)) continue;
            const o = std.mem.order(u8, self.text(col, i), v);
            const hit = switch (cmp) {
                .eq => o == .eq,
                .ne => o != .eq,
                .lt => o == .lt,
                .le => o != .gt,
                .gt => o == .gt,
                .ge => o != .lt,
            };
            if (hit) try out.append(self.gpa, @intCast(i));
        }
    }

    /// The rows where the integer cell compares to `v` (NULL cells never match), in order.
    pub fn filterInt(self: *const Table, col: usize, cmp: Cmp, v: i64, out: *std.ArrayList(u32)) !void {
        const c = &self.cols.items[col];
        const items = c.data.ints.items;
        switch (cmp) {
            .eq => for (items, 0..) |x, i| if (c.isValid(i) and x == v) try out.append(self.gpa, @intCast(i)),
            .ne => for (items, 0..) |x, i| if (c.isValid(i) and x != v) try out.append(self.gpa, @intCast(i)),
            .lt => for (items, 0..) |x, i| if (c.isValid(i) and x < v) try out.append(self.gpa, @intCast(i)),
            .le => for (items, 0..) |x, i| if (c.isValid(i) and x <= v) try out.append(self.gpa, @intCast(i)),
            .gt => for (items, 0..) |x, i| if (c.isValid(i) and x > v) try out.append(self.gpa, @intCast(i)),
            .ge => for (items, 0..) |x, i| if (c.isValid(i) and x >= v) try out.append(self.gpa, @intCast(i)),
        }
    }

    /// A new table with the rows of the selection, in its order (the columns are copied one at a time).
    pub fn take(self: *const Table, sel: []const u32) !Table {
        var out = Table.init(self.gpa);
        errdefer out.deinit();
        for (self.cols.items, 0..) |c, k| {
            _ = try out.addColumn(c.name, c.kind);
            for (sel) |r| {
                if (!c.isValid(r)) {
                    try out.appendNull(k);
                    continue;
                }
                switch (c.data) {
                    .ints => try out.appendInt(k, self.int(k, r)),
                    .reals => try out.appendReal(k, self.real(k, r)),
                    .text => try out.appendText(k, self.text(k, r)),
                }
            }
        }
        out.rows = sel.len;
        return out;
    }

    // ---------------------------------------------------------------- the two engines meet

    /// Load the table into `db` as the table `name` (made new); the rows are inserted in one transaction.
    pub fn toSqlite(self: *const Table, db: *sqlite.Db, name: []const u8) !void {
        var arena = std.heap.ArenaAllocator.init(self.gpa);
        defer arena.deinit();
        const a = arena.allocator();
        var sql: std.ArrayList(u8) = .empty;
        try sql.appendSlice(a, "create table ");
        try quote(&sql, a, name);
        try sql.appendSlice(a, " (");
        for (self.cols.items, 0..) |c, k| {
            if (k > 0) try sql.appendSlice(a, ", ");
            try quote(&sql, a, c.name);
            try sql.appendSlice(a, switch (c.kind) {
                .integer => " INTEGER",
                .boolean => " BOOLEAN",
                .real => " REAL",
                .date => " DATE",
                .timestamp => " TIMESTAMP",
                .text => " TEXT",
            });
        }
        try sql.appendSlice(a, ")");
        // a savepoint works alone and also inside the transaction of a job, where `begin` would be refused
        try db.exec("savepoint eve_load");
        errdefer db.exec("rollback to eve_load; release eve_load") catch {};
        try db.exec(try a.dupeSentinel(u8, sql.items, 0));
        if (self.cols.items.len > 0) {
            var ins: std.ArrayList(u8) = .empty;
            try ins.appendSlice(a, "insert into ");
            try quote(&ins, a, name);
            try ins.appendSlice(a, " values (");
            for (self.cols.items, 0..) |_, k| try ins.appendSlice(a, if (k == 0) "?" else ",?");
            try ins.appendSlice(a, ")");
            var st = try db.prepare(try a.dupeSentinel(u8, ins.items, 0));
            defer st.finalize();
            for (0..self.rows) |r| {
                for (self.cols.items, 0..) |c, k| {
                    const idx: u16 = @intCast(k + 1);
                    if (!c.isValid(r)) {
                        try st.bindNull(idx);
                        continue;
                    }
                    switch (c.kind) {
                        .integer, .boolean => try st.bindInt(idx, self.int(k, r)),
                        .real => try st.bindReal(idx, self.real(k, r)),
                        .text => try st.bindText(idx, self.text(k, r)),
                        .date => {
                            var b: [16]u8 = undefined;
                            try st.bindText(idx, formatDate(&b, self.int(k, r)));
                        },
                        .timestamp => {
                            var b: [24]u8 = undefined;
                            try st.bindText(idx, formatTimestamp(&b, self.int(k, r)));
                        },
                    }
                }
                _ = try st.step();
                try st.reset();
            }
        }
        try db.exec("release eve_load");
    }

    /// Store the answer of a query in a new table (explicit): the rows of `sql` become columns.
    pub fn fromQuery(gpa: std.mem.Allocator, db: *sqlite.Db, sql: [:0]const u8) !Table {
        var st = try db.prepare(sql);
        defer st.finalize();
        var t = Table.init(gpa);
        errdefer t.deinit();
        const n = st.columnCount();
        var made = false;
        while (try st.step()) {
            if (!made) {
                for (0..n) |k| {
                    const kind: Kind = switch (st.columnKind(@intCast(k))) {
                        .integer => .integer,
                        .real => .real,
                        else => .text,
                    };
                    _ = try t.addColumn(st.columnName(@intCast(k)), kind);
                }
                made = true;
            }
            for (0..n) |k| {
                const idx: u16 = @intCast(k);
                const have = st.columnKind(idx);
                if (have == .null) {
                    try t.appendNull(k);
                    continue;
                }
                switch (t.cols.items[k].kind) {
                    .integer => if (have == .integer) try t.appendInt(k, st.columnInt(idx)) else try t.appendNull(k),
                    .real => if (have == .real or have == .integer) try t.appendReal(k, st.columnReal(idx)) else try t.appendNull(k),
                    else => try t.appendText(k, st.columnText(idx)),
                }
            }
            t.endRow();
        }
        if (!made) {
            for (0..n) |k| _ = try t.addColumn(st.columnName(@intCast(k)), .text);
        }
        return t;
    }
};

fn quote(w: *std.ArrayList(u8), a: std.mem.Allocator, name: []const u8) !void {
    try w.append(a, '"');
    for (name) |ch| {
        if (ch == '"') try w.append(a, '"');
        try w.append(a, ch);
    }
    try w.append(a, '"');
}

/// The number of days since 1970-01-01 of a calendar date.
pub fn daysFromCivil(year: i64, month: u8, day: u8) i64 {
    const y = if (month <= 2) year - 1 else year;
    const era = @divFloor(y, 400);
    const yoe = y - era * 400;
    const mp: i64 = @mod(@as(i64, month) + 9, 12);
    const doy = @divFloor(153 * mp + 2, 5) + day - 1;
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + doe - 719468;
}

/// The calendar date of a number of days since 1970-01-01.
pub fn civilFromDays(days: i64) struct { year: i64, month: u8, day: u8 } {
    const z = days + 719468;
    const era = @divFloor(z, 146097);
    const doe = z - era * 146097;
    const yoe = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const doy = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp = @divFloor(5 * doy + 2, 153);
    const d: u8 = @intCast(doy - @divFloor(153 * mp + 2, 5) + 1);
    const m: u8 = @intCast(if (mp < 10) mp + 3 else mp - 9);
    const y = yoe + era * 400 + @as(i64, if (m <= 2) 1 else 0);
    return .{ .year = y, .month = m, .day = d };
}

/// `YYYY-MM-DD` for a number of days (the text is written in `buf`).
pub fn formatDate(buf: *[16]u8, days: i64) []const u8 {
    const c = civilFromDays(days);
    return std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}", .{ @as(u64, @intCast(@max(c.year, 0))), c.month, c.day }) catch "";
}

/// `YYYY-MM-DD HH:MM:SS` for a number of seconds.
pub fn formatTimestamp(buf: *[24]u8, secs: i64) []const u8 {
    const days = @divFloor(secs, 86400);
    const rem: u64 = @intCast(secs - days * 86400);
    const c = civilFromDays(days);
    return std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{ @as(u64, @intCast(@max(c.year, 0))), c.month, c.day, rem / 3600, rem % 3600 / 60, rem % 60 }) catch "";
}

/// The days of `YYYY-MM-DD` (nothing after the date is read), or null when the text is not a date.
pub fn parseDate(s: []const u8) ?i64 {
    if (s.len < 10 or s[4] != '-' or s[7] != '-') return null;
    const y = std.fmt.parseInt(i64, s[0..4], 10) catch return null;
    const m = std.fmt.parseInt(u8, s[5..7], 10) catch return null;
    const d = std.fmt.parseInt(u8, s[8..10], 10) catch return null;
    if (m < 1 or m > 12 or d < 1 or d > 31) return null;
    return daysFromCivil(y, m, d);
}

test "a column keeps NULL apart from zero and the kernels skip it" {
    var t = Table.init(std.testing.allocator);
    defer t.deinit();
    const a = try t.addColumn("qty", .integer);
    const b = try t.addColumn("name", .text);
    const values = [_]?i64{ 5, null, 0, 12 };
    const names = [_][]const u8{ "bolt", "nut", "", "washer" };
    for (values, names) |v, n| {
        if (v) |x| try t.appendInt(a, x) else try t.appendNull(a);
        try t.appendText(b, n);
        t.endRow();
    }
    try std.testing.expectEqual(@as(i64, 17), t.sumInt(a));
    try std.testing.expectEqual(@as(usize, 3), t.countValid(a));
    try std.testing.expectEqual([2]i64{ 0, 12 }, t.minMaxInt(a).?);
    var sel: std.ArrayList(u32) = .empty;
    defer sel.deinit(std.testing.allocator);
    try t.filterInt(a, .ge, 5, &sel);
    try std.testing.expectEqualSlices(u32, &.{ 0, 3 }, sel.items);
    var small = try t.take(sel.items);
    defer small.deinit();
    try std.testing.expectEqual(@as(usize, 2), small.rows);
    try std.testing.expectEqualStrings("washer", small.text(b, 1));
}

test "real and text kernels skip NULL" {
    var t = Table.init(std.testing.allocator);
    defer t.deinit();
    const p = try t.addColumn("price", .real);
    const n = try t.addColumn("name", .text);
    for ([_]?f64{ 2.5, null, 7.25 }, [_][]const u8{ "b", "a", "c" }) |v, name| {
        if (v) |x| try t.appendReal(p, x) else try t.appendNull(p);
        try t.appendText(n, name);
        t.endRow();
    }
    try std.testing.expectEqual([2]f64{ 2.5, 7.25 }, t.minMaxReal(p).?);
    var sel: std.ArrayList(u32) = .empty;
    defer sel.deinit(std.testing.allocator);
    try t.filterReal(p, .gt, 3, &sel);
    try std.testing.expectEqualSlices(u32, &.{2}, sel.items);
    sel.clearRetainingCapacity();
    try t.filterText(n, .ge, "b", &sel);
    try std.testing.expectEqualSlices(u32, &.{ 0, 2 }, sel.items);
}

test "a table goes to SQLite and comes back as columns" {
    var t = Table.init(std.testing.allocator);
    defer t.deinit();
    const id = try t.addColumn("id", .integer);
    const price = try t.addColumn("price", .real);
    const day = try t.addColumn("day", .date);
    const name = try t.addColumn("name", .text);
    for (0..3) |i| {
        try t.appendInt(id, @intCast(i + 1));
        if (i == 1) try t.appendNull(price) else try t.appendReal(price, 1.5 * @as(f64, @floatFromInt(i + 1)));
        try t.appendInt(day, daysFromCivil(2026, 10, @intCast(15 + i)));
        try t.appendText(name, "x y");
        t.endRow();
    }
    var db = try sqlite.Db.open(":memory:");
    defer db.close();
    try t.toSqlite(&db, "items");
    var back = try Table.fromQuery(std.testing.allocator, &db, "select id, price, day, name from items order by id");
    defer back.deinit();
    try std.testing.expectEqual(@as(usize, 3), back.rows);
    try std.testing.expect(back.isNull(1, 1));
    try std.testing.expectEqual(@as(f64, 4.5), back.real(1, 2));
    try std.testing.expectEqualStrings("2026-10-16", back.text(2, 1));
}

test "dates round trip through days" {
    const d = daysFromCivil(2024, 2, 29);
    var b: [16]u8 = undefined;
    try std.testing.expectEqualStrings("2024-02-29", formatDate(&b, d));
    try std.testing.expectEqual(d, parseDate("2024-02-29").?);
    try std.testing.expectEqual(@as(i64, 0), daysFromCivil(1970, 1, 1));
}
