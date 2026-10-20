//! @eve-module evetx.app.tree
//! @feature F-TLS-24
//! @decision D-173
//! @see code/evetx/src/app.zig:App
//! Marks and moving files in the tree.
const std = @import("std");
const Io = std.Io;
const vaxis = @import("vaxis");
const Key = vaxis.Key;
const ide = @import("ide");
const project = ide.project;
const sqlstruct = ide.sqlstruct;
const App = @import("../app.zig").App;
const types = @import("types.zig");
const Panel = types.Panel;
const Action = types.Action;
const Layout = types.Layout;
const extensionOf = types.extensionOf;

// ------------------------------------------------------------ marks and moving files in the tree

pub fn isMarked(self: *const App, path: []const u8) bool {
    for (self.marks.items) |p| {
        if (std.mem.eql(u8, p, path)) return true;
    }
    return false;
}

pub fn clearMarks(self: *App) void {
    for (self.marks.items) |p| self.gpa.free(p);
    self.marks.clearRetainingCapacity();
}

/// A press on a row of the tree.
pub fn treePress(self: *App, idx: u32, m: vaxis.Mouse) !void {
    self.focus = .tree;
    const e = self.tree.entries.items[idx];
    if (m.mods.ctrl) {
        self.selected = idx;
        if (e.parent == null) return;
        for (self.marks.items, 0..) |p, i| {
            if (std.mem.eql(u8, p, e.path)) {
                self.gpa.free(p);
                _ = self.marks.orderedRemove(i);
                return;
            }
        }
        try self.marks.append(self.gpa, try self.gpa.dupe(u8, e.path));
        return;
    }
    if (e.kind == .table) {
        // a table of a database is never dragged: it is selected, and a double click opens it
        self.clearMarks();
        self.selected = idx;
        const now = self.nowMs();
        const double = self.last_click_row == idx and now - self.last_click_ms < 400;
        self.last_click_row = if (double) null else idx;
        self.last_click_ms = now;
        if (double) try self.openEntry(idx);
        return;
    }
    if (!self.isMarked(e.path)) self.clearMarks();
    self.selected = idx;
    // the icon is the cell after the connection lines: 3 cells for each level of depth, from column 1
    const icon_col: i32 = @as(i32, self.tree_rect.x) + 1 + 3 * @as(i32, e.depth) - @as(i32, @intCast(self.tree_left));
    self.tdrag_icon = m.col == icon_col or m.col == icon_col + 1; // the emoji takes two cells
    self.tdrag_src = idx;
    self.tdrag_active = false;
    self.tdrag_over = null;
}

/// The button was released on a row of the tree without a drag.
pub fn treeClick(self: *App, idx: u32) !void {
    const e = &self.tree.entries.items[idx];
    const now = self.nowMs();
    const double = self.last_click_row == idx and now - self.last_click_ms < 400;
    self.last_click_row = if (double) null else idx;
    self.last_click_ms = now;
    // a file or a folder: a double click opens it, a single click only selects it (Enter opens it too)
    if (double) return self.openEntry(idx);
    if (!e.is_dir and e.kind != .db) return;
    if (self.tdrag_icon) {
        self.tdrag_icon = false;
        if (e.parent == null) return;
        e.expanded = !e.expanded;
        if (e.kind == .db and e.expanded) try self.loadDbTables(idx);
    }
}

/// The row of the tree under the pointer, or null.
pub fn treeRowAt(self: *const App, m: vaxis.Mouse) ?u32 {
    if (!self.tree_rect.contains(m.col, m.row)) return null;
    const k = self.tree_top + @as(usize, @intCast(@as(i32, m.row) - self.tree_rect.y));
    if (k >= self.visible.items.len) return null;
    return self.visible.items[k];
}

pub fn treeDragTo(self: *App, m: vaxis.Mouse) void {
    self.tdrag_active = true;
    self.tdrag_over = self.treeRowAt(m);
}

/// The button was released: open the row (no drag), or ask whether to move the files to the folder under the pointer.
pub fn treeRelease(self: *App) !void {
    const src = self.tdrag_src orelse return;
    const active = self.tdrag_active;
    const over = self.tdrag_over;
    self.tdrag_src = null;
    self.tdrag_active = false;
    self.tdrag_over = null;
    if (!active) {
        self.clearMarks();
        return self.treeClick(src);
    }
    const target = over orelse return;
    const te = self.tree.entries.items[target];
    const dest = if (te.is_dir) te.path else (std.fs.path.dirname(te.path) orelse "");
    const dragged = self.tree.entries.items[src].path;
    // a dragged row that is not marked moves alone; a marked one takes all the marked rows with it
    if (!self.isMarked(dragged)) {
        self.clearMarks();
        if (self.tree.entries.items[src].parent != null) try self.marks.append(self.gpa, try self.gpa.dupe(u8, dragged));
    }
    try self.askMove(dest);
}

/// Ask whether to move the marked files and folders into the folder `dest` (a path in the project, "" for its root).
pub fn askMove(self: *App, dest: []const u8) !void {
    for (self.move_srcs.items) |p| self.gpa.free(p);
    self.move_srcs.clearRetainingCapacity();
    for (self.marks.items) |p| try self.addMoveSource(p, dest);
    if (self.move_srcs.items.len == 0) {
        self.setMessage("nothing to move there", .{});
        return;
    }
    if (self.move_dest) |old| self.gpa.free(old);
    self.move_dest = try self.gpa.dupe(u8, dest);
    const shown: []const u8 = if (dest.len == 0) "the project folder" else dest;
    if (self.move_srcs.items.len == 1) {
        self.askConfirm(.move_files, 0, "Move {s} to {s}?", .{ self.move_srcs.items[0], shown });
    } else {
        self.askConfirm(.move_files, 0, "Move {d} files to {s}?", .{ self.move_srcs.items.len, shown });
    }
}

/// The path of the row under the cursor: of the folder tab when it has the keyboard, else of the tree.
pub fn currentRowPath(self: *App) ?[]u8 {
    if (self.focus != .tree) {
        if (self.activeTab()) |t| {
            if (t.folder) |fv| {
                if (fv.sel >= fv.items.items.len or std.mem.eql(u8, fv.items.items[fv.sel].name, "..")) return null;
                return self.folderItemPath(fv, fv.sel) catch null;
            }
        }
        if (self.focus == .editor) return null;
    }
    if (self.selected >= self.tree.entries.items.len) return null;
    const e = self.tree.entries.items[self.selected];
    if (e.parent == null) return null;
    return self.gpa.dupe(u8, e.path) catch null;
}

/// Mark (`on`) or unmark a path; marking twice does nothing.
pub fn setMark(self: *App, path: []const u8, on: bool) !void {
    for (self.marks.items, 0..) |p, i| {
        if (std.mem.eql(u8, p, path)) {
            if (!on) {
                self.gpa.free(p);
                _ = self.marks.orderedRemove(i);
            }
            return;
        }
    }
    if (on) try self.marks.append(self.gpa, try self.gpa.dupe(u8, path));
}

/// The row under the cursor moves one row down (like the file managers do after a mark).
pub fn stepDown(self: *App) void {
    if (self.focus != .tree) {
        if (self.activeTab()) |t| {
            if (t.folder) |fv| {
                fv.sel = @min(fv.sel + 1, fv.items.items.len -| 1);
                return;
            }
        }
    }
    const rows = self.visible.items;
    for (rows, 0..) |r, i| {
        if (r == self.selected) {
            self.selected = rows[@min(i + 1, rows.len - 1)];
            break;
        }
    }
    self.tree_follow = true;
}

/// Empty the selection: the marked files and folders, and the selected rows of the table in the window.
pub fn clearSelection(self: *App) void {
    self.clearMarks();
    if (self.activeTable()) |tv| tv.sel.clearRetainingCapacity();
}

/// Select (`+`) or unselect (`-`) the row under the cursor, then go to the next row.
pub fn markCurrent(self: *App, on: bool) !void {
    if (self.focus != .tree) {
        if (self.activeTable()) |tv| {
            if (tv.t.records == 0) return;
            if (on) try tv.sel.put(self.gpa, tv.row, {}) else _ = tv.sel.swapRemove(tv.row);
            tv.row = @min(tv.row + 1, tv.t.records - 1);
            self.setMessage("{d} selected", .{tv.sel.count()});
            return;
        }
    }
    const path = self.currentRowPath() orelse return;
    defer self.gpa.free(path);
    try self.setMark(path, on);
    self.stepDown();
    if (self.marks.items.len > 0) self.setMessage("{d} selected", .{self.marks.items.len});
}

/// Select all the rows of the folder tab, or all the rows beside the one selected in the tree.
pub fn markAll(self: *App) !void {
    if (self.focus != .tree) {
        if (self.activeTable()) |tv| {
            var r: usize = 0;
            while (r < tv.t.records) : (r += 1) try tv.sel.put(self.gpa, r, {});
            self.setMessage("{d} selected", .{tv.sel.count()});
            return;
        }
        if (self.activeTab()) |t| {
            if (t.folder) |fv| {
                for (fv.items.items, 0..) |it, i| {
                    if (std.mem.eql(u8, it.name, "..")) continue;
                    const path = try self.folderItemPath(fv, i);
                    defer self.gpa.free(path);
                    try self.setMark(path, true);
                }
                self.setMessage("{d} selected", .{self.marks.items.len});
                return;
            }
        }
    }
    if (self.selected >= self.tree.entries.items.len) return;
    const parent = self.tree.entries.items[self.selected].parent orelse return;
    for (self.tree.entries.items) |e| {
        if (e.parent != null and e.parent.? == parent) try self.setMark(e.path, true);
    }
    self.setMessage("{d} selected", .{self.marks.items.len});
}

/// Keys of the selection in a folder tab and in the tree: + select, - unselect, * select all, / unselect all.
pub fn markKey(self: *App, key: Key) !bool {
    if (key.mods.ctrl or key.mods.alt) return false;
    const c = key.codepoint;
    if (c == '+' or c == Key.kp_add) {
        try self.markCurrent(true);
    } else if (c == '-' or c == Key.kp_subtract) {
        try self.markCurrent(false);
    } else if (c == '*' or c == Key.kp_multiply) {
        try self.markAll();
    } else if (c == '/' or c == Key.kp_divide) {
        self.clearSelection();
        self.setMessage("selection cleared", .{});
    } else return false;
    return true;
}

/// Save As… (Ctrl+Shift+S, F4): choose the folder in the list and type the name.
pub fn openSaveChooser(self: *App) void {
    const typed = self.saveas_in.toOwnedContents(self.gpa) catch return;
    defer self.gpa.free(typed);
    self.saveas_in.clearRetainingCapacity();
    const path: []const u8 = if (self.activeTab()) |t| t.path else "";
    const name: []const u8 = if (typed.len > 0) std.fs.path.basename(typed) else std.fs.path.basename(path);
    const dir_rel: []const u8 = if (typed.len > 0 and std.fs.path.dirname(typed) != null) std.fs.path.dirname(typed).? else if (path.len > 0) (std.fs.path.dirname(path) orelse "") else self.targetDir();
    const start = if (dir_rel.len == 0) self.gpa.dupe(u8, if (self.root.len > 0) self.root else ".") catch return else self.fullPath(dir_rel) catch return;
    defer self.gpa.free(start);
    self.fb_mode = .save_as;
    self.fb_name.clearRetainingCapacity();
    self.fb_name.insertSliceAtCursor(name) catch {};
    self.openChooser(.save_as, .none, start);
}

/// The Save button of the selector: save the window as the name typed in the folder shown.
pub fn saveHere(self: *App) !void {
    const gpa = self.gpa;
    const raw = try self.fb_name.toOwnedContents(gpa);
    defer gpa.free(raw);
    const name = std.mem.trim(u8, raw, " \"");
    if (name.len == 0) {
        self.setMessage("type the name of the file", .{});
        return;
    }
    const dest = self.fb_path orelse return;
    const dir_rel = (try self.projectRel(dest)) orelse {
        self.setMessage("{s} is outside the project: choose a folder of the project", .{dest});
        return;
    };
    defer gpa.free(dir_rel);
    const rel = if (dir_rel.len == 0) try gpa.dupe(u8, name) else try std.fmt.allocPrint(gpa, "{s}/{s}", .{ dir_rel, name });
    self.chooserDone();
    if (self.save_rel) |old| gpa.free(old);
    self.save_rel = rel;
    const same = if (self.activeTab()) |t| std.mem.eql(u8, t.path, rel) else false;
    const full = try self.fullPath(rel);
    defer gpa.free(full);
    const exists = if (Io.Dir.cwd().statFile(self.io, full, .{})) |_| true else |_| false;
    if (exists and !same and !std.ascii.eqlIgnoreCase(extensionOf(rel), "dbf")) {
        self.askConfirm(.replace_file, 0, "Replace the existing file {s}?", .{rel});
        return;
    }
    try self.saveAs(rel);
}

/// File > Move…: the marked rows (or the row under the cursor) go to a folder chosen in the folder selector.
pub fn startMove(self: *App) !void {
    if (self.marks.items.len == 0) {
        const path = self.currentRowPath() orelse {
            self.setMessage("Move: select files or folders first (+ on a row, * for all)", .{});
            return;
        };
        defer self.gpa.free(path);
        try self.setMark(path, true);
    }
    const first = self.marks.items[0];
    const dir_rel = std.fs.path.dirname(first) orelse "";
    const start = if (dir_rel.len == 0) try self.gpa.dupe(u8, if (self.root.len > 0) self.root else ".") else try self.fullPath(dir_rel);
    defer self.gpa.free(start);
    self.openChooser(.move_many, .none, start);
}

/// The folder selector of Move…: ask to move the marked rows into the folder shown.
pub fn moveManyHere(self: *App) !void {
    const dest = self.fb_path orelse return;
    const dir_rel = (try self.projectRel(dest)) orelse {
        self.setMessage("{s} is outside the project: choose a folder of the project", .{dest});
        return;
    };
    defer self.gpa.free(dir_rel);
    self.chooserDone();
    try self.askMove(dir_rel);
}

/// A press on a row of a folder tab: Ctrl+click marks it; a plain press selects it and may start a drag to the tree.
pub fn folderPress(self: *App, i: usize, m: vaxis.Mouse) !void {
    self.focus = .editor;
    const t = self.activeTab() orelse return;
    const fv = t.folder orelse return;
    if (i >= fv.items.items.len) return;
    if (m.mods.ctrl) {
        fv.sel = i;
        if (std.mem.eql(u8, fv.items.items[i].name, "..")) return;
        const path = try self.folderItemPath(fv, i);
        defer self.gpa.free(path);
        try self.setMark(path, !self.isMarked(path));
        return;
    }
    self.fdrag = i;
    self.fdrag_was_sel = fv.sel == i;
    fv.sel = i;
    self.tdrag_active = false;
    self.tdrag_over = null;
}

/// The button was released after a press on a folder row: open the row (a second click), or drop it on the tree.
pub fn folderRelease(self: *App) !void {
    const i = self.fdrag orelse return;
    const active = self.tdrag_active;
    const over = self.tdrag_over;
    self.fdrag = null;
    self.tdrag_active = false;
    self.tdrag_over = null;
    const t = self.activeTab() orelse return;
    const fv = t.folder orelse return;
    if (i >= fv.items.items.len) return;
    if (!active) {
        if (self.fdrag_was_sel) try self.openFolderItem(fv, i);
        return;
    }
    const target = over orelse return;
    if (std.mem.eql(u8, fv.items.items[i].name, "..")) return;
    const te = self.tree.entries.items[target];
    const dest = if (te.is_dir) te.path else (std.fs.path.dirname(te.path) orelse "");
    const path = try self.folderItemPath(fv, i);
    defer self.gpa.free(path);
    if (!self.isMarked(path)) {
        self.clearMarks();
        try self.marks.append(self.gpa, try self.gpa.dupe(u8, path));
    }
    try self.askMove(dest);
}

/// Show the folder tabs again after files moved.
pub fn reloadFolders(self: *App) void {
    for (self.tabs.items) |*t| {
        const old = t.folder orelse continue;
        const dir = self.gpa.dupe(u8, old.dir) catch continue;
        defer self.gpa.free(dir);
        const nf = self.loadFolder(dir) catch continue;
        nf.sel = @min(old.sel, nf.items.items.len -| 1);
        self.freeFolder(old);
        t.folder = nf;
    }
}

pub fn addMoveSource(self: *App, path: []const u8, dest: []const u8) !void {
    const parent = std.fs.path.dirname(path) orelse "";
    if (std.mem.eql(u8, parent, dest)) return;
    if (std.mem.eql(u8, path, dest)) return;
    if (dest.len > path.len and std.mem.startsWith(u8, dest, path) and dest[path.len] == '/') return;
    try self.move_srcs.append(self.gpa, try self.gpa.dupe(u8, path));
}

/// Yes of the move dialog: move the files, then fix the tabs, the breakpoints and the tree.
pub fn performMove(self: *App) void {
    const dest = self.move_dest orelse return;
    var moved: usize = 0;
    var skipped: usize = 0;
    for (self.move_srcs.items) |src| {
        const base = std.fs.path.basename(src);
        const new_rel = if (dest.len == 0) self.gpa.dupe(u8, base) catch continue else std.fmt.allocPrint(self.gpa, "{s}/{s}", .{ dest, base }) catch continue;
        defer self.gpa.free(new_rel);
        const old_full = self.fullPath(src) catch continue;
        defer self.gpa.free(old_full);
        const new_full = self.fullPath(new_rel) catch continue;
        defer self.gpa.free(new_full);
        if (Io.Dir.cwd().statFile(self.io, new_full, .{})) |_| {
            skipped += 1;
            continue;
        } else |_| {}
        Io.Dir.rename(Io.Dir.cwd(), old_full, Io.Dir.cwd(), new_full, self.io) catch {
            skipped += 1;
            continue;
        };
        moved += 1;
        self.retarget(src, new_rel);
    }
    self.clearMarks();
    self.refreshTree();
    self.reloadFolders();
    self.saveSession() catch {};
    if (skipped > 0) self.setMessage("moved {d}, {d} skipped (the name exists in the folder)", .{ moved, skipped }) else self.setMessage("moved {d} file(s)", .{moved});
}

/// A file or folder was moved from `old` to `new`: open tabs and breakpoints inside it get the new path.
pub fn retarget(self: *App, old: []const u8, new: []const u8) void {
    for (self.tabs.items) |*t| {
        const np = self.movedPath(t.path, old, new) orelse continue;
        self.gpa.free(t.path);
        t.path = np;
        t.eve = std.ascii.eqlIgnoreCase(extensionOf(np), "eve");
        t.sql = std.ascii.eqlIgnoreCase(extensionOf(np), "sql");
    }
    for (self.breakpoints.items) |*b| {
        const np = self.movedPath(b.path, old, new) orelse continue;
        self.gpa.free(b.path);
        b.path = np;
    }
}

pub fn movedPath(self: *App, path: []const u8, old: []const u8, new: []const u8) ?[]u8 {
    if (std.mem.eql(u8, path, old)) return self.gpa.dupe(u8, new) catch null;
    if (path.len > old.len and std.mem.startsWith(u8, path, old) and path[old.len] == '/') {
        return std.fmt.allocPrint(self.gpa, "{s}{s}", .{ new, path[old.len..] }) catch null;
    }
    return null;
}

/// The border under the pointer is active when the layout is unlocked; set the shape of the pointer.
pub fn refreshHover(self: *App, m: vaxis.Mouse) void {
    self.hover_split = if (self.modify) self.splitAt(m) else null;
    const cand = self.hover_split orelse {
        self.pointer = .default;
        return;
    };
    self.pointer = if (cand == .tree_split) .@"ew-resize" else .@"ns-resize";
}

/// The lock of the toolbar: locked means the layout is frozen; unlocked it can be modified (Window > Layout modify).
pub fn toggleLock(self: *App) void {
    if (self.modify) self.freezeLayout() else self.startModify(false);
}

pub fn hover(self: *App, m: vaxis.Mouse) void {
    if (self.overlay == .none) {
        // over a border between panels the pointer is a double arrow while the layout is unlocked
        self.refreshHover(m);
        return;
    }
    self.hover_split = null;
    self.pointer = .default;
    if (self.overlay != .menu and self.overlay != .tab_menu) return;
    var i = self.hits.items.len;
    while (i > 0) {
        i -= 1;
        const h = self.hits.items[i];
        if (!h.rect.contains(m.col, m.row)) continue;
        switch (h.action) {
            .menu_top => |t| if (t != self.menu_top) self.openMenu(t),
            .menu_item => |r| self.menu_sel = r,
            .tabmenu_item => |r| self.tab_menu_sel = r,
            else => {},
        }
        return;
    }
}

pub fn activate(self: *App, action: Action) !void {
    switch (action) {
        .tree_row => |i| {
            self.focus = .tree;
            try self.openEntry(i);
        },
        .tab => |i| {
            // a click on a tab gives the Main Panel the keyboard, whatever the window holds (a folder list too)
            self.active = i;
            self.focus = .editor;
        },
        .tab_close => |i| self.closeTab(i),
        .bottom => |t| {
            self.bottom = t;
            self.focus = switch (t) {
                .console => .console,
                .breaks => .breaks,
                .sql => .sql,
                else => self.focus,
            };
        },
        .tab_shift => |d| {
            if (d < 0) self.tab_first -|= 1 else if (self.tab_more_right) self.tab_first += 1;
        },
        .prop_btn => |b| switch (b) {
            .rename => if (self.prop_editing) try self.doRename() else self.startRename(),
            .move => try self.openMove(),
        },
        .folder_row => |i| {
            self.focus = .editor;
            const t = self.activeTab() orelse return;
            const fv = t.folder orelse return;
            if (fv.sel == i) try self.openFolderItem(fv, i) else fv.sel = i;
        },
        .folder_scroll => |d| {
            const t = self.activeTab() orelse return;
            const fv = t.folder orelse return;
            switch (d) {
                .up => fv.top -|= 8,
                .down => fv.top = @min(fv.top + 8, fv.items.items.len -| 1),
                else => {},
            }
        },
        .log_scroll => |d| {
            const log = self.shownLog();
            const half = @max(1, self.console_rect.h / 2);
            switch (d) {
                .up => log.scroll +|= half,
                .down => log.scroll -|= half,
                else => {},
            }
        },
        .break_scroll => |d| switch (d) {
            .up => self.break_top -|= 3,
            .down => self.break_top += 3,
            else => {},
        },
        .menu_top => |t| {
            if (self.overlay == .menu and self.menu_top == t) self.overlay = .none else self.openMenu(t);
        },
        .menu_item => |i| {
            const row = self.rowAt(self.menu_top, i);
            if (row.cmd) |c| try self.runMenu(c, row.arg);
        },
        .dlg_field => |f| self.dlg_field = f,
        .nop => {},
        .lock_toggle => self.toggleLock(),
        .opt => |o| try self.optAction(o),
        .tabmenu_item => |i| try self.runTabMenu(i),
        .tree_scroll => |d| {
            const half = @max(1, self.tree_rect.h / 2);
            switch (d) {
                .left => self.tree_left -|= 10,
                .right => self.tree_left += 10,
                .up => self.tree_top -|= half,
                .down => self.tree_top += half,
            }
        },
        .table_scroll => |d| {
            if (self.activeTab()) |t| {
                if (t.table) |tv| switch (d) {
                    .up => tv.top -|= 8,
                    .down => tv.top = @min(tv.top + 8, tv.t.records -| 1),
                    .left => tv.left -|= 1,
                    .right => tv.left = @min(tv.left + 1, tv.t.fields.len -| 1),
                };
            }
        },
        .scroll => |d| {
            const b = self.activeBuffer() orelse return;
            self.follow = false;
            const half = @max(1, self.editor_rect.h / 2);
            switch (d) {
                .left => b.left -|= 10,
                .right => b.left = @min(b.left + 10, self.hbar_content -| self.editor_rect.w),
                .up => b.top -|= half,
                .down => b.top = @min(b.top + half, b.lineCount() - 1),
            }
        },
        .dlg => |d| switch (d) {
            .ok => try self.overlayKey(.{ .codepoint = Key.enter }),
            .forget => try self.forgetProject(),
            .browse => self.openFolderDialog(),
            .open_here => try self.fbOk(),
            .filter_add => self.filterAdd(),
            .filter_remove => self.filterRemove(),
        },
        .filter_row => |i| self.filterSelect(i),
        .filter_col => |i| self.filterSelect(i),
        .filter_pick => |i| self.filterPickChoose(i),
        .proj_row => |i| {
            if (self.proj_sel == i) try self.openCached(i) else self.proj_sel = i;
        },
        // the arrows of the folder selector move the selection half a list, and the list follows it
        .fb_scroll => |d| {
            const n = self.fbRowCount();
            if (n > 0) switch (d) {
                .up => self.fb_sel -|= 8,
                .down => self.fb_sel = @min(self.fb_sel + 8, n - 1),
                else => {},
            };
        },
        .fb_row => |i| {
            self.dlg_field = 1;
            if (self.fb_sel == i) try self.fbEnterRow(i) else {
                self.fb_sel = i;
                self.fbPickName();
            }
        },
        .panel_focus => |p| self.focusPanel(p),
        .panel_hide => |p| self.togglePanel(p),
        .panel_max => |p| self.toggleMaximize(p),
        .wiz_choice => |i| self.wiz_choice = i,
        .sq_cell => |c| {
            self.sq_row = c.row;
            self.sq_col = c.col;
            self.sq_drop = false;
            if (self.sq_editing) self.sq_editing = false;
            if (c.col == 2 or c.col == 3) self.sqStartEdit() catch {};
        },
        .sq_drop_open => {
            self.sq_col = 1;
            self.sqStartEdit() catch {};
        },
        .sq_pick => |i| {
            if (i < sqlstruct.types.len) self.sq_cols.items[self.sq_row].setType(sqlstruct.types[i]);
            self.sq_drop = false;
        },
        .sq_ix_field => |i| {
            self.sq_ix_focus = 0;
            self.sq_ix_cur = i;
            self.sqIdxToggle(i);
        },
        .sq_ix_row => |i| {
            self.sq_ix_focus = 1;
            self.sq_ix_sel = i;
        },
        .sq_ix_unique => self.sq_ix_uniq = !self.sq_ix_uniq,
        .sq_ix_add => self.sqIdxAdd() catch {},
        .sq_ix_remove => self.sqIdxRemove(),
        .sq_btn => |b| switch (b) {
            .prev => if (self.sq_new) self.sqGoPage(-1) else {
                self.sq_row = self.sq_row -| 10;
            },
            .next => if (self.sq_new) self.sqGoPage(1) else {
                self.sq_row = @min(self.sq_row + 10, self.sq_cols.items.len - 1);
            },
            .add => self.sqAdd() catch {},
            .remove => self.sqRemove(),
            .up => self.sqMove(-1),
            .down => self.sqMove(1),
            .apply => try self.sqApply(),
        },
        .break_toggle => |i| self.toggleBreakpointEnabled(i),
        .break_trash => |i| {
            if (i < self.breakpoints.items.len) self.askConfirm(.delete_breakpoint, i, "Remove the breakpoint {s}:{d}?", .{ self.breakpoints.items[i].path, self.breakpoints.items[i].line });
        },
        .clear_panel => try self.clearPanel(),
        .confirm => |yes| {
            if (yes) self.confirmYes() else self.overlay = .none;
        },
        .break_row => |i| {
            if (self.break_sel == i) try self.jumpToBreakpoint(i) else self.break_sel = i;
            self.focus = .breaks;
        },
        .close_overlay => self.closeOverlay(),
        .button => |b| switch (b) {
            .run => try self.runButton(),
            .halt => try self.haltRun(),
            .next => try self.debugCommand("next"),
            .step => try self.debugCommand("step"),
            .exit => try self.debugCommand("exit"),
            .trace => try self.debugCommand("trace"),
            .replace => try self.replaceOne(),
            .replace_all => try self.replaceEvery(),
        },
    }
}
