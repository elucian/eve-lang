//! @eve-module evetx.app.filter
//! @feature F-TLS-28
//! @decision D-173
//! @see code/evetx/src/app.zig:App
//! The filter of a table.
const std = @import("std");
const vaxis = @import("vaxis");
const Key = vaxis.Key;
const ide = @import("ide");
const grid = ide.grid;
const regex = ide.regex;
const App = @import("../app.zig").App;
const types = @import("types.zig");
const TableView = types.TableView;
const FilterRow = types.FilterRow;

// ------------------------------------------------------------ the filter of a table

/// Search > Filter…: choose columns and the values or patterns their cells must match; Enter shows the rows that match.
pub fn openFilter(self: *App) void {
    const t = self.tableTab() orelse return;
    const tv = t.table orelse return;
    for (self.flt_rows.items) |r| self.gpa.free(r.pat);
    self.flt_rows.clearRetainingCapacity();
    if (self.flt_src) |old| self.gpa.free(old);
    self.flt_src = null;
    if (self.flt_replace) |old| self.gpa.free(old);
    self.flt_replace = null;
    if (self.flt_view) |old| self.gpa.free(old);
    self.flt_view = null;
    if (std.mem.startsWith(u8, t.path, "filter:") and tv.filter_src.len > 0) {
        // Alter filter: the dialog starts with the filters of this window and works on the table it came from
        var open = false;
        for (self.tabs.items) |o| {
            if (o.table != null and std.mem.eql(u8, o.path, tv.filter_src)) open = true;
        }
        if (!open) {
            self.setMessage("open the table {s} first: the filter works on it", .{tv.filter_src});
            return;
        }
        self.flt_src = self.gpa.dupe(u8, tv.filter_src) catch return;
        self.flt_replace = self.gpa.dupe(u8, t.path) catch return;
        for (tv.filter_rows) |r| self.filterPush(r.col, r.pat);
    } else {
        self.flt_src = self.gpa.dupe(u8, t.path) catch return;
        // every field is in the filter, with no pattern, until the last patterns of the table are put back
        for (0..tv.t.fields.len) |c| self.filterPush(c, "");
        self.filtersLoad(self.flt_src.?);
    }
    self.flt_sel = 0;
    self.flt_pick = false;
    self.flt_in.clearRetainingCapacity();
    if (self.flt_rows.items.len > 0) self.flt_in.insertSliceAtCursor(self.flt_rows.items[0].pat) catch {};
    self.openOverlay(.filter);
}

/// Put `pat` in the row of column `col`, when the filter has that field.
pub fn filterSetPat(self: *App, col: usize, pat: []const u8) void {
    for (self.flt_rows.items) |*r| {
        if (r.col != col) continue;
        const copy = self.gpa.dupe(u8, pat) catch return;
        self.gpa.free(r.pat);
        r.pat = copy;
    }
}

pub fn filterPush(self: *App, col: usize, pat: []const u8) void {
    const copy = self.gpa.dupe(u8, pat) catch return;
    self.flt_rows.append(self.gpa, .{ .col = col, .pat = copy }) catch self.gpa.free(copy);
}

/// Put the filters last applied to the table `src` in the dialog.
pub fn filtersLoad(self: *App, src: []const u8) void {
    const bytes = self.cache.readFile("evetx-filters.txt") orelse return;
    defer self.gpa.free(bytes);
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw| {
        var f = std.mem.splitScalar(u8, std.mem.trimEnd(u8, raw, "\r"), '\t');
        const key = f.next() orelse continue;
        if (!std.mem.eql(u8, key, src)) continue;
        const col = std.fmt.parseInt(usize, f.next() orelse continue, 10) catch continue;
        self.filterSetPat(col, f.next() orelse "");
    }
}

/// Remember the filters of the dialog for the table `src`.
pub fn filtersStore(self: *App, src: []const u8) void {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(self.gpa);
    if (self.cache.readFile("evetx-filters.txt")) |bytes| {
        defer self.gpa.free(bytes);
        var lines = std.mem.splitScalar(u8, bytes, '\n');
        while (lines.next()) |raw| {
            if (raw.len == 0) continue;
            const cut = std.mem.indexOfScalar(u8, raw, '\t') orelse continue;
            if (std.mem.eql(u8, raw[0..cut], src)) continue;
            out.appendSlice(self.gpa, raw) catch return;
            out.append(self.gpa, '\n') catch return;
        }
    }
    for (self.flt_rows.items) |r| {
        if (r.pat.len == 0) continue;
        const line = std.fmt.allocPrint(self.gpa, "{s}\t{d}\t{s}\n", .{ src, r.col, r.pat }) catch return;
        defer self.gpa.free(line);
        for (line[0 .. line.len - 1]) |*c| {
            if (c.* == '\r') c.* = ' ';
        }
        out.appendSlice(self.gpa, line) catch return;
    }
    self.cache.writeFile("evetx-filters.txt", out.items) catch {};
}

pub fn filterTable(self: *App) ?*TableView {
    const src = self.flt_src orelse return null;
    for (self.tabs.items) |t| {
        if (std.mem.eql(u8, t.path, src)) return t.table;
    }
    return null;
}

/// The name of column `c` of the table being filtered (the real name of a SQLite column).
pub fn filterColName(self: *App, c: usize) []const u8 {
    const tv = self.filterTable() orelse return "";
    if (c < tv.colnames.len) return tv.colnames[c];
    if (c < tv.t.fields.len) return tv.t.fields[c].nameSlice();
    return "";
}

/// The title of the tab of the table being filtered.
pub fn filterTableTitle(self: *App) []const u8 {
    const src = self.flt_src orelse return "";
    for (self.tabs.items) |t| {
        if (std.mem.eql(u8, t.path, src)) return t.title();
    }
    return "";
}

pub fn filterCommit(self: *App) void {
    if (self.flt_sel >= self.flt_rows.items.len) return;
    const raw = self.flt_in.toOwnedContents(self.gpa) catch return;
    const row = &self.flt_rows.items[self.flt_sel];
    self.gpa.free(row.pat);
    row.pat = raw;
}

pub fn filterSelect(self: *App, i: usize) void {
    if (i >= self.flt_rows.items.len) return;
    self.filterCommit();
    self.flt_sel = i;
    self.flt_in.clearRetainingCapacity();
    self.flt_in.insertSliceAtCursor(self.flt_rows.items[i].pat) catch {};
}

/// The columns of the table that are not in the filter, in the order of the table.
pub fn filterMissing(self: *App, buf: *[256]usize) []usize {
    const tv = self.filterTable() orelse return buf[0..0];
    var n: usize = 0;
    for (0..@min(tv.t.fields.len, 256)) |c| {
        var in = false;
        for (self.flt_rows.items) |r| {
            if (r.col == c) in = true;
        }
        if (!in) {
            buf[n] = c;
            n += 1;
        }
    }
    return buf[0..n];
}

/// The names of the fields that are not in the filter, for the list of Add field.
pub fn filterMissingCol(self: *App, k: usize) ?usize {
    var buf: [256]usize = undefined;
    const m = self.filterMissing(&buf);
    return if (k < m.len) m[k] else null;
}

/// Add field: open the list of the fields that were taken out.
pub fn filterAdd(self: *App) void {
    self.filterCommit();
    var buf: [256]usize = undefined;
    if (self.filterMissing(&buf).len == 0) {
        self.setMessage("all the fields of the table are in the filter", .{});
        return;
    }
    self.flt_pick = true;
    self.flt_pick_sel = 0;
}

/// A field was chosen in the list: it goes back into the filter, at its place in the table.
pub fn filterPickChoose(self: *App, k: usize) void {
    self.flt_pick = false;
    const col = self.filterMissingCol(k) orelse return;
    const empty = self.gpa.dupe(u8, "") catch return;
    var at: usize = self.flt_rows.items.len;
    for (self.flt_rows.items, 0..) |r, i| {
        if (r.col > col) {
            at = i;
            break;
        }
    }
    self.flt_rows.insert(self.gpa, at, .{ .col = col, .pat = empty }) catch {
        self.gpa.free(empty);
        return;
    };
    self.flt_sel = at;
    self.flt_in.clearRetainingCapacity();
}

/// Remove field: the selected field leaves the filter (and the view that is made from it).
pub fn filterRemove(self: *App) void {
    if (self.flt_sel >= self.flt_rows.items.len) return;
    if (self.flt_rows.items.len <= 1) {
        self.setMessage("a filter keeps at least one field", .{});
        return;
    }
    const gone = self.flt_rows.orderedRemove(self.flt_sel);
    self.gpa.free(gone.pat);
    self.flt_sel = @min(self.flt_sel, self.flt_rows.items.len -| 1);
    self.flt_in.clearRetainingCapacity();
    if (self.flt_rows.items.len > 0) self.flt_in.insertSliceAtCursor(self.flt_rows.items[self.flt_sel].pat) catch {};
}

pub fn filterKey(self: *App, key: Key) !void {
    if (self.flt_pick) {
        // the list of the fields that can be added back
        var buf: [256]usize = undefined;
        const n = self.filterMissing(&buf).len;
        if (key.matches(Key.up, .{})) self.flt_pick_sel = self.flt_pick_sel -| 1;
        if (key.matches(Key.down, .{})) self.flt_pick_sel = @min(self.flt_pick_sel + 1, n -| 1);
        if (key.matches(Key.enter, .{})) self.filterPickChoose(self.flt_pick_sel);
        return;
    }
    if (key.matches(Key.enter, .{})) return self.filterApply();
    if (key.matches(Key.up, .{})) return self.filterSelect(self.flt_sel -| 1);
    if (key.matches(Key.down, .{})) return self.filterSelect(@min(self.flt_sel + 1, self.flt_rows.items.len -| 1));
    if (key.matches(Key.tab, .{})) return self.filterSelect((self.flt_sel + 1) % @max(1, self.flt_rows.items.len));
    if (key.matches(Key.tab, .{ .shift = true })) return self.filterSelect((self.flt_sel + self.flt_rows.items.len -| 1) % @max(1, self.flt_rows.items.len));
    if (key.matches(Key.insert, .{}) or key.matches('n', .{ .ctrl = true })) return self.filterAdd();
    if (key.matches('d', .{ .ctrl = true })) return self.filterRemove();
    if (self.flt_rows.items.len == 0) return;
    try self.flt_in.update(.{ .key_press = key });
}

pub const Matcher = struct {
    col: usize,
    re: ?regex.Regex,
    lit: []const u8,

    fn test_(m: *const Matcher, cell: []const u8) bool {
        if (m.re) |*re| return re.find(cell);
        return std.ascii.findIgnoreCase(cell, m.lit) != null;
    }
};

/// Enter of the filter dialog: a new window with the rows that match every filter.
pub fn filterApply(self: *App) !void {
    const gpa = self.gpa;
    self.filterCommit();
    const tv = self.filterTable() orelse {
        self.overlay = .none;
        return;
    };
    var ms: std.ArrayList(App.Matcher) = .empty;
    defer {
        for (ms.items) |*m| if (m.re) |*re| re.deinit();
        ms.deinit(gpa);
    }
    for (self.flt_rows.items) |r| {
        if (r.pat.len == 0) continue;
        const re: ?regex.Regex = regex.Regex.compile(gpa, r.pat) catch null;
        try ms.append(gpa, .{ .col = r.col, .re = re, .lit = r.pat });
    }
    if (ms.items.len == 0 and self.flt_rows.items.len >= tv.t.fields.len) {
        self.setMessage("type a value or a pattern in a field, or take a field out", .{});
        return;
    }
    var tsv: std.ArrayList(u8) = .empty;
    defer tsv.deinit(gpa);
    for (self.flt_rows.items, 0..) |fr, i| {
        if (i > 0) try tsv.append(gpa, '\t');
        try tsv.appendSlice(gpa, self.filterColName(fr.col));
    }
    try tsv.append(gpa, '\n');
    var kept: usize = 0;
    var kept_rows: std.ArrayList(usize) = .empty;
    defer kept_rows.deinit(gpa);
    var kept_ids: std.ArrayList(i64) = .empty;
    defer kept_ids.deinit(gpa);
    var r: usize = 0;
    while (r < tv.t.records) : (r += 1) {
        if (tv.t.deleted(r)) continue;
        var ok = true;
        for (ms.items) |*m| {
            var b: [16]u8 = undefined;
            if (!m.test_(std.mem.trim(u8, tv.t.display(r, m.col, &b), " "))) {
                ok = false;
                break;
            }
        }
        if (!ok) continue;
        kept += 1;
        try kept_rows.append(gpa, r);
        if (tv.rowids.len == tv.t.records) try kept_ids.append(gpa, tv.rowids[r]);
        for (self.flt_rows.items, 0..) |fr, i| {
            if (i > 0) try tsv.append(gpa, '\t');
            var b: [16]u8 = undefined;
            for (std.mem.trim(u8, tv.t.display(r, fr.col, &b), " ")) |ch| try tsv.append(gpa, if (ch == '\t' or ch == '\n' or ch == '\r') ' ' else ch);
        }
        try tsv.append(gpa, '\n');
    }
    const table = try grid.fromTsv(gpa, tsv.items);
    var nv: TableView = .{ .t = table, .readonly = true };
    var keep = false;
    defer if (!keep) nv.release();
    // what Save As needs later: the table, the filters, the records, the real names of the columns
    nv.filter_src = try gpa.dupe(u8, self.flt_src.?);
    var rows: std.ArrayList(FilterRow) = .empty;
    errdefer rows.deinit(gpa);
    for (self.flt_rows.items) |fr| {
        try rows.append(gpa, .{ .col = fr.col, .pat = try gpa.dupe(u8, fr.pat) });
    }
    nv.filter_rows = try rows.toOwnedSlice(gpa);
    nv.kept = try kept_rows.toOwnedSlice(gpa);
    nv.kept_ids = try kept_ids.toOwnedSlice(gpa);
    const names = try gpa.alloc([]u8, tv.t.fields.len);
    for (names, 0..) |*n, c| n.* = try gpa.dupe(u8, self.filterColName(c));
    nv.colnames = names;
    self.filtersStore(self.flt_src.?);
    // Alter table on a view: the view is dropped and made again with the new filters
    if (self.flt_view) |vn| {
        const src = self.flt_src.?;
        const h = std.mem.indexOfScalar(u8, src, '#') orelse src.len;
        const db = try gpa.dupe(u8, src[0..h]);
        defer gpa.free(db);
        const base = try gpa.dupe(u8, if (h < src.len) src[h + 1 ..] else "");
        defer gpa.free(base);
        const view_name = try gpa.dupe(u8, vn);
        defer gpa.free(view_name);
        const tid = try App.sqlQuoted(gpa, base, '"');
        defer gpa.free(tid);
        var snapshot = false;
        const sel = try self.selectSqlFor(tid, &nv, &snapshot);
        defer gpa.free(sel);
        self.overlay = .none;
        if (!self.runDb(&.{ "drop", "view", db, view_name })) return;
        if (!self.runDb(&.{ "create", "view", db, view_name, sel })) return;
        self.metaTouch(db, view_name);
        const key = try std.fmt.allocPrint(gpa, "{s}#{s}", .{ db, view_name });
        defer gpa.free(key);
        var i = self.tabs.items.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.tabs.items[i].path, key)) self.closeTab(i);
        }
        self.refreshDbTables(db) catch {};
        try self.openSqliteTable(db, view_name);
        self.setMessage("view {s} altered{s}", .{ view_name, if (snapshot) " (the pattern is a regular expression: it lists the rows found now)" else "" });
        return;
    }
    // Alter filter replaces the rows of the window that was altered; Filter opens a new window
    if (self.flt_replace) |rp| {
        for (self.tabs.items, 0..) |*t, i| {
            if (t.table != null and std.mem.eql(u8, t.path, rp)) {
                t.table.?.release();
                keep = true;
                t.table.?.* = nv;
                self.active = i;
                self.focus = .editor;
                self.overlay = .none;
                self.setMessage("filter: {d} of {d} rows match", .{ kept, tv.t.records });
                return;
            }
        }
    }
    const view = try gpa.create(TableView);
    errdefer gpa.destroy(view);
    view.* = nv;
    keep = true;
    self.flt_count += 1;
    const key = try std.fmt.allocPrint(gpa, "filter:{d}:{s}", .{ self.flt_count, self.flt_src.? });
    errdefer gpa.free(key);
    const label = try gpa.dupe(u8, self.filterTableTitle());
    errdefer gpa.free(label);
    try self.tabs.insert(gpa, 0, .{ .path = key, .table = view, .label = label });
    self.active = 0;
    self.tab_first = 0;
    self.focus = .editor;
    self.overlay = .none;
    self.setMessage("filter: {d} of {d} rows match", .{ kept, tv.t.records });
}
