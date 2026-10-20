//! @eve-module evetx.app.data
//! @feature F-TLS-28
//! @decision D-173
//! @see code/evetx/src/app.zig:App
//! The DATA menu: append, delete and edit records.
const std = @import("std");
const vaxis = @import("vaxis");
const ide = @import("ide");
const text = ide.text;
const App = @import("../app.zig").App;
const types = @import("types.zig");
const TableView = types.TableView;

// ------------------------------------------------------------ the DATA menu

/// The table of the active tab.
pub fn activeTable(self: *App) ?*TableView {
    const t = self.activeTab() orelse return null;
    return t.table;
}

/// DATA > Append row(s): blank records at the end of the table; the last one is selected.
pub fn dataAppend(self: *App, n: u32) !void {
    const tv = self.activeTable() orelse {
        self.setMessage("DATA works on a table of a database: open one", .{});
        return;
    };
    if (tv.readonly) return self.readonlyMessage();
    if (tv.t.fields.len == 0) {
        self.setMessage("the table has no fields yet: SQL:> alter table <name>", .{});
        return;
    }
    if (self.activeTab()) |t| t.editing = true;
    if (self.sqlView()) |st| {
        const sql = try std.fmt.allocPrint(self.gpa, "insert into \"{s}\" default values;", .{st.table});
        defer self.gpa.free(sql);
        var k: u32 = 0;
        while (k < n) : (k += 1) {
            if (!self.runSql(st.db, sql)) break;
        }
        self.metaTouch(st.db, st.table);
        self.reloadSqlite(tv, st.db, st.table);
        tv.row = tv.t.records -| 1;
        self.setMessage("{d} row(s) added to {s}", .{ k, st.table });
        return;
    }
    self.readonlyMessage();
}

/// DATA > Append rows…: ask how many.
pub fn openAppendN(self: *App) void {
    if (self.activeTable() == null) {
        self.setMessage("DATA works on a table of a database: open one", .{});
        return;
    }
    self.goto_in.clearRetainingCapacity();
    self.openOverlay(.append_n);
}

pub fn appendNEnter(self: *App) !void {
    const raw = try self.goto_in.toOwnedContents(self.gpa);
    defer self.gpa.free(raw);
    const n = std.fmt.parseInt(u32, std.mem.trim(u8, raw, " "), 10) catch 0;
    if (n == 0 or n > 100000) {
        self.setMessage("a number of rows from 1 to 100000", .{});
        return;
    }
    self.overlay = .none;
    try self.dataAppend(n);
}

/// DATA > Delete / recall row: mark the selected record deleted, or take the mark away.
pub fn dataDelete(self: *App) !void {
    const tv = self.activeTable() orelse {
        self.setMessage("DATA works on a table of a database: open one", .{});
        return;
    };
    if (tv.readonly) return self.readonlyMessage();
    if (tv.row >= tv.t.records) return;
    if (self.activeTab()) |t| t.editing = true;
    const n_sel = tv.sel.count();
    if (self.sqlView()) |st| {
        const n_del: usize = if (n_sel > 0) n_sel else 1;
        self.askConfirm(.delete_rows, 0, "Delete {d} row(s) from {s}? It cannot be recovered.", .{ n_del, st.table });
        return;
    }
    self.readonlyMessage();
}

/// The Yes of "Delete rows": delete the selected rows (or the current one) from the SQLite table.
pub fn performDeleteRows(self: *App) void {
    const st = self.sqlView() orelse return;
    const tv = st.tv;
    var ids: std.ArrayList(i64) = .empty;
    defer ids.deinit(self.gpa);
    if (tv.sel.count() > 0) {
        for (tv.sel.keys()) |r| {
            if (r < tv.rowids.len) ids.append(self.gpa, tv.rowids[r]) catch return;
        }
    } else if (tv.row < tv.rowids.len) ids.append(self.gpa, tv.rowids[tv.row]) catch return;
    var at: usize = 0;
    while (at < ids.items.len) {
        const end = @min(at + 400, ids.items.len);
        var sql: std.ArrayList(u8) = .empty;
        defer sql.deinit(self.gpa);
        const head = std.fmt.allocPrint(self.gpa, "delete from \"{s}\" where rowid in (", .{st.table}) catch return;
        defer self.gpa.free(head);
        sql.appendSlice(self.gpa, head) catch return;
        for (ids.items[at..end], 0..) |id, k| {
            var nb: [24]u8 = undefined;
            const num = std.fmt.bufPrint(&nb, "{s}{d}", .{ if (k > 0) "," else "", id }) catch return;
            sql.appendSlice(self.gpa, num) catch return;
        }
        sql.appendSlice(self.gpa, ");") catch return;
        if (!self.runSql(st.db, sql.items)) break;
        at = end;
    }
    self.metaTouch(st.db, st.table);
    self.reloadSqlite(tv, st.db, st.table);
    self.setMessage("{d} row(s) deleted from {s}", .{ at, st.table });
}

/// DATA > Edit cell: the selected cell becomes a text field with its value.
pub fn dataEdit(self: *App) void {
    const tv = self.activeTable() orelse {
        self.setMessage("DATA works on a table of a database: open one", .{});
        return;
    };
    // the list of the tables of a database: the table of the row is opened
    if (self.sqlView()) |st| {
        if (st.table.len == 0) {
            if (tv.row >= tv.t.records) return;
            var nb: [16]u8 = undefined;
            const name = self.gpa.dupe(u8, std.mem.trim(u8, tv.t.display(tv.row, 0, &nb), " ")) catch return;
            defer self.gpa.free(name);
            const db = self.gpa.dupe(u8, st.db) catch return;
            defer self.gpa.free(db);
            self.openSqliteTable(db, name) catch |err| self.setMessage("error: {s}", .{@errorName(err)});
            return;
        }
    }
    if (tv.readonly) return self.readonlyMessage();
    if (tv.row >= tv.t.records or tv.col >= tv.t.fields.len) return;
    if (tv.sel.contains(tv.row)) {
        self.setMessage("a selected row is not edited: unselect it first (Ctrl+click or -)", .{});
        return;
    }
    var buf: [16]u8 = undefined;
    self.tbl_edit.clearRetainingCapacity();
    self.tbl_edit.insertSliceAtCursor(tv.t.display(tv.row, tv.col, &buf)) catch return;
    if (self.activeTab()) |t| t.editing = true;
    self.tbl_editing = true;
    self.focus = .editor;
}

/// File > Save All (Ctrl+A): save every window of a file that has unsaved changes.
pub fn saveAll(self: *App) void {
    var saved: usize = 0;
    var failed: usize = 0;
    var untitled: usize = 0;
    for (self.tabs.items) |*t| {
        if (t.table != null) continue;
        if (t.virtual or t.buf == null or !t.buf.?.dirty) continue;
        if (t.path.len == 0) {
            untitled += 1;
            continue;
        }
        self.writeTab(t, t.path) catch {
            failed += 1;
            continue;
        };
        saved += 1;
    }
    if (failed > 0) self.setMessage("saved {d}, {d} failed", .{ saved, failed }) else if (untitled > 0) self.setMessage("saved {d}; {d} new file(s) need Save As first", .{ saved, untitled }) else if (saved == 0) self.setMessage("nothing to save", .{}) else self.setMessage("saved {d} file(s)", .{saved});
}

/// Edit > Edit cell, file or table (Enter): open the file or table that is selected, or edit the cell.
pub fn dataEditOrOpen(self: *App) void {
    if (self.focus == .tree) {
        if (self.selected >= self.tree.entries.items.len) return;
        const e = self.tree.entries.items[self.selected];
        if (e.is_dir and e.kind != .db) {
            self.setMessage("a folder is not edited: File > Rename changes its name", .{});
            return;
        }
        self.openEntry(self.selected) catch |err| self.setMessage("error: {s}", .{@errorName(err)});
        return;
    }
    if (self.activeTab()) |t| {
        if (t.folder) |fv| {
            if (fv.sel >= fv.items.items.len) return;
            if (fv.items.items[fv.sel].is_dir) {
                self.setMessage("a folder is not edited: File > Rename changes its name", .{});
                return;
            }
            self.openFolderItem(fv, fv.sel) catch |err| self.setMessage("error: {s}", .{@errorName(err)});
            return;
        }
    }
    // Start Editing / Stop Editing of the window: a text file switches its mode, a table in editing mode stops
    if (self.activeTab()) |t| {
        if (t.buf != null and !t.virtual) {
            t.editing = !t.editing;
            self.setMessage("{s}", .{if (t.editing) "editing: Esc or Save stops it" else "editing stopped"});
            return;
        }
        if (t.table != null and t.editing) {
            t.editing = false;
            self.tbl_editing = false;
            self.setMessage("editing stopped", .{});
            return;
        }
    }
    self.dataEdit();
}

pub fn commitCell(self: *App, tv: *TableView) !void {
    const raw = try self.tbl_edit.toOwnedContents(self.gpa);
    defer self.gpa.free(raw);
    const val = std.mem.trim(u8, raw, " ");
    self.tbl_editing = false;
    if (self.sqlView()) |st| {
        if (tv.readonly or tv.row >= tv.rowids.len or tv.col >= tv.colnames.len) return self.readonlyMessage();
        var buf: [16]u8 = undefined;
        if (std.mem.eql(u8, std.mem.trim(u8, tv.t.display(tv.row, tv.col, &buf), " "), val)) return;
        const col = try App.sqlQuoted(self.gpa, tv.colnames[tv.col], '"');
        defer self.gpa.free(col);
        const lit = if (val.len == 0 or std.mem.eql(u8, val, "NULL")) try self.gpa.dupe(u8, "NULL") else try App.sqlQuoted(self.gpa, val, '\'');
        defer self.gpa.free(lit);
        const sql = try std.fmt.allocPrint(self.gpa, "update \"{s}\" set {s} = {s} where rowid = {d};", .{ st.table, col, lit, tv.rowids[tv.row] });
        defer self.gpa.free(sql);
        if (self.runSql(st.db, sql)) {
            self.metaTouch(st.db, st.table);
            self.reloadSqlite(tv, st.db, st.table);
        }
        return;
    }
    self.readonlyMessage();
}
