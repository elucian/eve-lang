//! @eve-module evetx.app.structure
//! @feature F-TLS-28
//! @decision D-173
//! @see code/evetx/src/app.zig:App
//! The structure of a SQLite table: columns, indexes, apply.
const std = @import("std");
const vaxis = @import("vaxis");
const Key = vaxis.Key;
const ide = @import("ide");
const text = ide.text;
const sqlstruct = ide.sqlstruct;
const App = @import("../app.zig").App;
const types = @import("types.zig");
const IndexDef = types.IndexDef;

// ------------------------------------------------------------ the structure of a SQLite table

/// SQL:> alter table <name>, or DATA > Structure on a table of a database: open the dialog of its columns.
pub fn openSqStructure(self: *App, db_rel: []const u8, table: []const u8) !void {
    const gpa = self.gpa;
    const sql = try std.fmt.allocPrint(gpa, "pragma table_info(\"{s}\");", .{table});
    defer gpa.free(sql);
    const out = try self.eveText(&.{ "db", "sql", "-t", db_rel, sql });
    defer gpa.free(out);
    self.sq_cols.clearRetainingCapacity();
    self.sq_orig.clearRetainingCapacity();
    sqlstruct.parseTableInfo(gpa, out, &self.sq_cols) catch {};
    if (self.sq_cols.items.len == 0) {
        const msg = try std.fmt.allocPrint(gpa, "alter table: there is no table {s} in {s}", .{ table, db_rel });
        defer gpa.free(msg);
        try self.sql_log.add(gpa, msg, .err);
        return;
    }
    try self.sq_orig.appendSlice(gpa, self.sq_cols.items);
    if (self.sq_db) |old| gpa.free(old);
    if (self.sq_table) |old| gpa.free(old);
    self.sq_db = try gpa.dupe(u8, db_rel);
    self.sq_table = try gpa.dupe(u8, table);
    self.sq_row = 0;
    self.sq_col = 0;
    self.sq_editing = false;
    self.sq_drop = false;
    self.sq_error = null;
    self.sq_new = false;
    self.openOverlay(.sq_structure);
}

/// The dialog of a new SQLite table in the file `db_rel`; `name` may be empty.
pub fn openSqStructureNew(self: *App, db_rel: []const u8, name: []const u8) !void {
    const gpa = self.gpa;
    self.sq_cols.clearRetainingCapacity();
    self.sq_orig.clearRetainingCapacity();
    self.sq_idx.clearRetainingCapacity();
    var c: sqlstruct.Col = .{ .pk = true, .notnull = true };
    c.setName("id");
    c.setType("INTEGER");
    try self.sq_cols.append(gpa, c);
    if (self.sq_db) |old| gpa.free(old);
    if (self.sq_table) |old| gpa.free(old);
    self.sq_db = try gpa.dupe(u8, db_rel);
    self.sq_table = try gpa.dupe(u8, name);
    self.sq_name_in.clearRetainingCapacity();
    self.sq_desc_in.clearRetainingCapacity();
    try self.sq_name_in.insertSliceAtCursor(name);
    self.sq_row = 0;
    self.sq_col = 0;
    self.sq_editing = false;
    self.sq_drop = false;
    self.sq_error = null;
    self.sq_new = true;
    self.sq_page = 0;
    self.sq_ix_cur = 0;
    self.sq_ix_mask = 0;
    self.sq_ix_uniq = false;
    self.sq_ix_sel = 0;
    self.sq_ix_focus = 0;
    self.dlg_field = 0;
    self.openOverlay(.sq_structure);
}

/// The name typed in the first page of the dialog of a new table (a copy that the caller frees).
pub fn sqTypedName(self: *App) ![]u8 {
    const raw = try self.sq_name_in.toOwnedContents(self.gpa);
    defer self.gpa.free(raw);
    return self.gpa.dupe(u8, std.mem.trim(u8, raw, " "));
}

/// Is the name of the new table good? (for the Next and Create buttons)
pub fn sqNameOk(self: *App) bool {
    const name = self.sqTypedName() catch return false;
    defer self.gpa.free(name);
    return App.tableNameError(name) == null;
}

/// Go to the page before (-1) or after (+1) in the dialog of a new table.
pub fn sqGoPage(self: *App, delta: i8) void {
    self.sq_error = null;
    self.sq_editing = false;
    self.sq_drop = false;
    const to: i16 = @as(i16, self.sq_page) + delta;
    if (to < 0 or to > 2) return;
    if (to > 0) {
        const name = self.sqTypedName() catch return;
        defer self.gpa.free(name);
        if (App.tableNameError(name)) |msg| {
            self.sq_error = msg;
            self.sq_page = 0;
            return;
        }
    }
    self.sq_page = @intCast(to);
    if (self.sq_page == 2) {
        self.sq_ix_cur = @min(self.sq_ix_cur, self.sq_cols.items.len -| 1);
        if (self.sq_cols.items.len < 64) self.sq_ix_mask &= (@as(u64, 1) << @intCast(self.sq_cols.items.len)) - 1;
    }
}

/// The keys of the page "name and description" of a new table.
pub fn sqInfoKey(self: *App, key: Key) !void {
    if (key.matches('s', .{ .ctrl = true })) return self.sqApply();
    if (key.matches(Key.tab, .{}) or key.matches(Key.down, .{}) or key.matches(Key.up, .{})) {
        self.dlg_field = 1 - self.dlg_field;
        return;
    }
    if (key.matches(Key.enter, .{})) {
        if (self.dlg_field == 0) {
            self.dlg_field = 1;
        } else self.sqGoPage(1);
        return;
    }
    self.sq_error = null;
    const ti = if (self.dlg_field == 0) &self.sq_name_in else &self.sq_desc_in;
    try ti.update(.{ .key_press = key });
}

/// The text of a column list for an index: the names of the ticked fields, separated by commas.
pub fn sqIndexColsText(self: *App, buf: []u8) []const u8 {
    var len: usize = 0;
    for (self.sq_cols.items, 0..) |col, i| {
        if (i >= 64 or self.sq_ix_mask & (@as(u64, 1) << @intCast(i)) == 0) continue;
        const nm = col.nameS();
        const gap: usize = if (len > 0) 1 else 0;
        if (len + gap + nm.len > buf.len) break;
        if (gap == 1) {
            buf[len] = ',';
            len += 1;
        }
        @memcpy(buf[len..][0..nm.len], nm);
        len += nm.len;
    }
    return buf[0..len];
}

/// Add the index made of the ticked fields to the list.
pub fn sqIdxAdd(self: *App) !void {
    self.sq_error = null;
    var cols_buf: [160]u8 = undefined;
    const cols = self.sqIndexColsText(&cols_buf);
    if (cols.len == 0) {
        self.sq_error = "tick at least one field for the index (Space)";
        return;
    }
    const table = try self.sqTypedName();
    defer self.gpa.free(table);
    var ix: IndexDef = .{ .unique = self.sq_ix_uniq };
    @memcpy(ix.cols[0..cols.len], cols);
    ix.cols_len = @intCast(cols.len);
    var nb: [112]u8 = undefined;
    var w: usize = 0;
    const head = std.fmt.bufPrint(&nb, "ix_{s}{s}", .{ table, if (self.sq_ix_uniq) "_u" else "" }) catch {
        self.sq_error = "the name of the table is too long for an index";
        return;
    };
    w = head.len;
    for (cols) |ch| {
        if (w >= nb.len) break;
        nb[w] = if (ch == ',') '_' else ch;
        w += 1;
    }
    @memcpy(ix.name[0..w], nb[0..w]);
    ix.name_len = @intCast(w);
    for (self.sq_idx.items) |o| {
        if (std.ascii.eqlIgnoreCase(o.nameS(), ix.nameS())) {
            self.sq_error = "this index is in the list already";
            return;
        }
    }
    try self.sq_idx.append(self.gpa, ix);
    self.sq_ix_sel = self.sq_idx.items.len - 1;
    self.sq_ix_mask = 0;
    self.sq_ix_uniq = false;
    self.setMessage("index {s} added to the list", .{ix.nameS()});
}

/// Take the index selected in the list out of it.
pub fn sqIdxRemove(self: *App) void {
    if (self.sq_idx.items.len == 0) return;
    _ = self.sq_idx.orderedRemove(@min(self.sq_ix_sel, self.sq_idx.items.len - 1));
    self.sq_ix_sel = @min(self.sq_ix_sel, self.sq_idx.items.len -| 1);
}

pub fn sqIdxToggle(self: *App, i: usize) void {
    if (i >= self.sq_cols.items.len or i >= 64) return;
    self.sq_ix_mask ^= @as(u64, 1) << @intCast(i);
}

/// The keys of the page "indexes" of a new table.
pub fn sqIndexKey(self: *App, key: Key) !void {
    if (key.matches('s', .{ .ctrl = true })) return self.sqApply();
    if (key.matches(Key.tab, .{})) {
        self.sq_ix_focus = 1 - self.sq_ix_focus;
        return;
    }
    if (self.sq_ix_focus == 1) {
        const n = self.sq_idx.items.len;
        if (key.matches(Key.up, .{})) self.sq_ix_sel = self.sq_ix_sel -| 1 else if (key.matches(Key.down, .{})) self.sq_ix_sel = @min(self.sq_ix_sel + 1, n -| 1) else if (key.matches(Key.delete, .{})) self.sqIdxRemove();
        return;
    }
    const n = self.sq_cols.items.len;
    if (key.matches(Key.up, .{})) self.sq_ix_cur = self.sq_ix_cur -| 1 else if (key.matches(Key.down, .{})) self.sq_ix_cur = @min(self.sq_ix_cur + 1, n - 1) else if (key.matches(Key.page_up, .{})) self.sq_ix_cur = self.sq_ix_cur -| 7 else if (key.matches(Key.page_down, .{})) self.sq_ix_cur = @min(self.sq_ix_cur + 7, n - 1) else if (key.matches(Key.space, .{})) self.sqIdxToggle(self.sq_ix_cur) else if (key.matches('u', .{})) self.sq_ix_uniq = !self.sq_ix_uniq else if (key.matches(Key.enter, .{}) or key.matches(Key.insert, .{})) try self.sqIdxAdd() else if (key.matches(Key.delete, .{})) self.sqIdxRemove();
}

pub fn sqChanges(self: *const App) usize {
    var n: usize = 0;
    for (self.sq_cols.items, 0..) |c, i| {
        const same = i < self.sq_orig.items.len and c.src == self.sq_orig.items[i].src and std.meta.eql(c, self.sq_orig.items[i]);
        if (!same) n += 1;
    }
    if (self.sq_orig.items.len > self.sq_cols.items.len) n += self.sq_orig.items.len - self.sq_cols.items.len;
    return n;
}

pub fn sqAdd(self: *App) !void {
    var c: sqlstruct.Col = .{};
    var n: usize = self.sq_cols.items.len + 1;
    var nb: [24]u8 = undefined;
    while (true) : (n += 1) {
        const name = std.fmt.bufPrint(&nb, "column{d}", .{n}) catch "column";
        var used = false;
        for (self.sq_cols.items) |o| {
            if (std.ascii.eqlIgnoreCase(o.nameS(), name)) used = true;
        }
        if (!used) {
            c.setName(name);
            break;
        }
    }
    c.setType("TEXT");
    const at = self.sq_row + 1;
    try self.sq_cols.insert(self.gpa, at, c);
    self.sq_row = at;
    self.sq_col = 0;
}

pub fn sqRemove(self: *App) void {
    if (self.sq_cols.items.len <= 1) {
        self.sq_error = "a table needs at least one column";
        return;
    }
    _ = self.sq_cols.orderedRemove(self.sq_row);
    self.sq_row = @min(self.sq_row, self.sq_cols.items.len - 1);
}

pub fn sqMove(self: *App, delta: isize) void {
    const to_i: isize = @as(isize, @intCast(self.sq_row)) + delta;
    if (to_i < 0 or to_i >= self.sq_cols.items.len) return;
    const to: usize = @intCast(to_i);
    std.mem.swap(sqlstruct.Col, &self.sq_cols.items[self.sq_row], &self.sq_cols.items[to]);
    self.sq_row = to;
}

pub fn sqStartEdit(self: *App) !void {
    const c = &self.sq_cols.items[self.sq_row];
    self.sq_error = null;
    switch (self.sq_col) {
        1 => {
            self.sq_drop = true;
            self.sq_drop_sel = 0;
            for (sqlstruct.types, 0..) |t, i| {
                if (std.ascii.eqlIgnoreCase(t, c.typeS())) self.sq_drop_sel = i;
            }
        },
        2 => c.notnull = !c.notnull,
        3 => c.pk = !c.pk,
        else => {
            self.sq_edit.clearRetainingCapacity();
            try self.sq_edit.insertSliceAtCursor(if (self.sq_col == 0) c.nameS() else c.defaultS());
            self.sq_editing = true;
        },
    }
}

pub fn sqCommit(self: *App) !void {
    const raw = try self.sq_edit.toOwnedContents(self.gpa);
    defer self.gpa.free(raw);
    const t = std.mem.trim(u8, raw, " ");
    const c = &self.sq_cols.items[self.sq_row];
    self.sq_editing = false;
    if (self.sq_col == 0) c.setName(t) else c.setDefault(t);
    self.sq_error = sqlstruct.check(c);
}

/// The keys of the structure dialog of a SQLite table.
pub fn sqKey(self: *App, key: Key) !void {
    // a new table has three pages: Ctrl+Left and Ctrl+Right move between them; the first and the last have their own keys
    if (self.sq_new and !self.sq_editing and !self.sq_drop) {
        if (key.matches(Key.right, .{ .ctrl = true })) return self.sqGoPage(1);
        if (key.matches(Key.left, .{ .ctrl = true })) return self.sqGoPage(-1);
        if (self.sq_page == 0) return self.sqInfoKey(key);
        if (self.sq_page == 2) return self.sqIndexKey(key);
    }
    if (self.sq_editing) {
        if (key.matches(Key.enter, .{})) return self.sqCommit();
        try self.sq_edit.update(.{ .key_press = key });
        return;
    }
    const kn = sqlstruct.types.len;
    if (self.sq_drop) {
        if (key.matches(Key.up, .{})) self.sq_drop_sel = (self.sq_drop_sel + kn - 1) % kn else if (key.matches(Key.down, .{})) self.sq_drop_sel = (self.sq_drop_sel + 1) % kn else if (key.matches(Key.enter, .{})) {
            self.sq_cols.items[self.sq_row].setType(sqlstruct.types[self.sq_drop_sel]);
            self.sq_drop = false;
        }
        return;
    }
    const n = self.sq_cols.items.len;
    if (key.matches(Key.up, .{ .ctrl = true })) return self.sqMove(-1);
    if (key.matches(Key.down, .{ .ctrl = true })) return self.sqMove(1);
    if (key.matches(Key.up, .{})) self.sq_row = self.sq_row -| 1 else if (key.matches(Key.down, .{})) self.sq_row = @min(self.sq_row + 1, n - 1) else if (key.matches(Key.left, .{})) self.sq_col = self.sq_col -| 1 else if (key.matches(Key.right, .{}) or key.matches(Key.tab, .{})) self.sq_col = @min(self.sq_col + 1, 4) else if (key.matches(Key.page_up, .{})) self.sq_row = self.sq_row -| 10 else if (key.matches(Key.page_down, .{})) self.sq_row = @min(self.sq_row + 10, n - 1) else if (key.matches(Key.enter, .{}) or key.matches(Key.space, .{})) try self.sqStartEdit() else if (key.matches(Key.insert, .{})) try self.sqAdd() else if (key.matches(Key.delete, .{})) self.sqRemove() else if (key.matches('s', .{ .ctrl = true })) try self.sqApply();
}

/// The Apply button of the SQLite structure dialog: check the columns and ask before the table is rebuilt.
pub fn sqApply(self: *App) !void {
    self.sq_error = null;
    if (self.sq_new) {
        const name = try self.sqTypedName();
        defer self.gpa.free(name);
        if (App.tableNameError(name)) |msg| {
            self.sq_error = msg;
            self.sq_page = 0;
            return;
        }
        if (self.sq_table) |old| self.gpa.free(old);
        self.sq_table = try self.gpa.dupe(u8, name);
    }
    const items = self.sq_cols.items;
    for (items, 0..) |c, i| {
        if (sqlstruct.check(&c)) |msg| {
            self.sq_error = msg;
            self.sq_row = i;
            if (self.sq_new) self.sq_page = 1;
            return;
        }
        for (items[0..i]) |o| {
            if (std.ascii.eqlIgnoreCase(o.nameS(), c.nameS())) {
                self.sq_error = "two columns have the same name";
                self.sq_row = i;
                self.sq_page = 1;
                return;
            }
        }
    }
    if (self.sqChanges() == 0) {
        self.sq_error = "nothing to apply";
        return;
    }
    if (self.sq_new) return self.sqApplyNow();
    self.askConfirm(.apply_sqlite, 0, "Rebuild table {s}? Its indexes and triggers are not kept.", .{self.sq_table orelse ""});
}

pub fn sqApplyNow(self: *App) !void {
    const gpa = self.gpa;
    const db = self.sq_db orelse return;
    const table = self.sq_table orelse return;
    const base = if (self.sq_new) try sqlstruct.buildCreate(gpa, table, self.sq_cols.items) else try sqlstruct.buildScript(gpa, table, self.sq_cols.items, self.sq_orig.items);
    defer gpa.free(base);
    // the indexes of a new table go after the table, one statement each
    var sb: std.ArrayList(u8) = .empty;
    defer sb.deinit(gpa);
    try sb.appendSlice(gpa, base);
    if (self.sq_new) {
        for (self.sq_idx.items) |ix| {
            try sb.print(gpa, " create {s}index \"{s}\" on \"{s}\" (", .{ if (ix.unique) "unique " else "", ix.nameS(), table });
            var it = std.mem.splitScalar(u8, ix.colsS(), ',');
            var first = true;
            while (it.next()) |cn| {
                if (!first) try sb.appendSlice(gpa, ", ");
                first = false;
                try sb.print(gpa, "\"{s}\"", .{cn});
            }
            try sb.appendSlice(gpa, ");");
        }
    }
    const script = sb.items;
    const out = try self.eveText(&.{ "db", "sql", db, script });
    defer gpa.free(out);
    if (std.mem.indexOf(u8, out, "error:") != null) {
        self.sq_error = "SQLite refused the change (see the SQL panel)";
        if (self.sq_new) self.sq_page = 0;
        try self.sql_log.addBlock(gpa, out, .err);
        self.openOverlay(.sq_structure);
        return;
    }
    self.overlay = .none;
    if (self.sq_new) {
        const desc = self.sq_desc_in.toOwnedContents(gpa) catch null;
        defer if (desc) |d| gpa.free(d);
        self.metaCreated(db, table, if (desc) |d| std.mem.trim(u8, d, " ") else "");
    } else self.metaTouch(db, table);
    // the table is shown again with its new columns
    const key = try std.fmt.allocPrint(gpa, "{s}#{s}", .{ db, table });
    defer gpa.free(key);
    for (self.tabs.items, 0..) |t, i| {
        if (std.mem.eql(u8, t.path, key)) {
            self.closeTab(i);
            break;
        }
    }
    if (self.sq_new) try self.refreshDbTables(db);
    try self.openSqliteTable(db, table);
    const msg = try std.fmt.allocPrint(gpa, "{s}: {s}, {d} columns", .{ key, if (self.sq_new) "table created" else "structure changed", self.sq_cols.items.len });
    defer gpa.free(msg);
    try self.sql_log.add(gpa, msg, .info);
    self.setMessage("{s}", .{msg});
}
