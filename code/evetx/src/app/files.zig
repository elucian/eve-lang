//! @eve-module evetx.app.files
//! @feature F-TLS-24
//! @decision D-173
//! @see code/evetx/src/app.zig:App
//! Files and tabs: open, close, save, and the list of a folder.
const std = @import("std");
const Io = std.Io;
const vaxis = @import("vaxis");
const Key = vaxis.Key;
const ide = @import("ide");
const project = ide.project;
const text = ide.text;
const App = @import("../app.zig").App;
const types = @import("types.zig");
const Panel = types.Panel;
const FolderItem = types.FolderItem;
const FolderView = types.FolderView;
const Tab = types.Tab;
const extensionOf = types.extensionOf;
const cardLabel = types.cardLabel;

// ------------------------------------------------------------ files and tabs

/// Open a file of the project in a tab (or go to its tab when it is open).
pub fn openFile(self: *App, rel: []const u8) !void {
    if (std.mem.indexOfScalar(u8, rel, '#')) |h| return self.openSqliteTable(rel[0..h], rel[h + 1 ..]);
    for (self.tabs.items, 0..) |t, i| {
        if (std.mem.eql(u8, t.path, rel)) {
            self.active = i;
            self.focus = if (t.buf != null or t.table != null) .editor else .tree;
            return;
        }
    }
    var tab: Tab = .{ .path = try self.gpa.dupe(u8, rel) };
    errdefer self.gpa.free(tab.path);
    tab.eve = std.ascii.eqlIgnoreCase(extensionOf(rel), "eve");
    tab.sql = std.ascii.eqlIgnoreCase(extensionOf(rel), "sql");
    const full = try self.fullPath(rel);
    defer self.gpa.free(full);

    const size: u64 = if (Io.Dir.cwd().statFile(self.io, full, .{})) |st| st.size else |_| 0;
    if (std.ascii.eqlIgnoreCase(extensionOf(rel), "dbf")) {
        // a DBF file is a legacy format: it is not shown, it is imported into a database (D-184)
        tab.card = .{ .kind = "DBF file", .size = size, .note = "A legacy file. Select a database and use EDIT > Import… to read it." };
    } else if (cardLabel(rel)) |label| {
        tab.card = .{ .kind = label, .size = size, .note = if (std.ascii.eqlIgnoreCase(extensionOf(rel), "db") or std.ascii.eqlIgnoreCase(extensionOf(rel), "duckdb") or std.ascii.eqlIgnoreCase(extensionOf(rel), "sqlite")) "The list of tables comes with step T7 (README.md §8)." else "No preview in evetx. The rendered file is shown by eveux (eve -ux)." };
    } else if (Io.Dir.cwd().readFileAlloc(self.io, full, self.gpa, .limited(8 << 20))) |bytes| {
        defer self.gpa.free(bytes);
        if (std.mem.indexOfScalar(u8, bytes[0..@min(bytes.len, 4096)], 0) != null) {
            tab.card = .{ .kind = "binary file", .size = size, .note = "Not text: evetx does not open it in the editor." };
        } else {
            var b = try text.Buffer.init(self.gpa);
            errdefer b.deinit();
            try b.load(bytes);
            if (b.tabs_replaced) self.setMessage("{s}: tabs were replaced by spaces", .{rel});
            tab.buf = b;
        }
    } else |err| {
        tab.card = .{ .kind = "file", .size = size, .note = @errorName(err) };
    }
    try self.tabs.insert(self.gpa, 0, tab);
    self.active = 0;
    self.tab_first = 0;
    self.focus = if (tab.buf != null or tab.table != null) .editor else .tree;
    self.saveSession() catch {};
}

pub fn closeTab(self: *App, index: usize) void {
    if (index >= self.tabs.items.len) return;
    var t = self.tabs.orderedRemove(index);
    if (t.buf) |*b| b.deinit();
    if (t.table) |tv| {
        tv.release();
        self.gpa.destroy(tv);
    }
    if (t.folder) |fv| self.freeFolder(fv);
    if (t.label.len > 0) self.gpa.free(t.label);
    self.gpa.free(t.path);
    if (self.active >= self.tabs.items.len and self.tabs.items.len > 0) self.active = self.tabs.items.len - 1;
    if (self.tabs.items.len == 0) self.active = 0;
    self.saveSession() catch {};
}

pub fn newFile(self: *App) !void {
    var b = try text.Buffer.init(self.gpa);
    errdefer b.deinit();
    try self.tabs.insert(self.gpa, 0, .{ .path = try self.gpa.dupe(u8, ""), .buf = b, .eve = true, .editing = true });
    self.active = 0;
    self.tab_first = 0;
    self.focus = .editor;
}

pub fn save(self: *App) !void {
    const t = self.activeTab() orelse return;
    // saving ends the editing of the window
    defer t.editing = false;
    if (t.table != null) {
        self.setMessage("a table of a database is saved at once, with each change", .{});
        return;
    }
    if (t.buf == null) return;
    if (t.virtual) {
        self.setMessage("{s} is a read-only window", .{t.path});
        return;
    }
    if (t.path.len == 0) {
        self.openOverlay(.save_as);
        return;
    }
    try self.writeTab(t, t.path);
    self.setMessage("saved {s}", .{t.path});
}

pub fn writeTab(self: *App, t: *Tab, rel: []const u8) !void {
    const b = &t.buf.?;
    const bytes = try b.toBytes(self.gpa);
    defer self.gpa.free(bytes);
    const full = try self.fullPath(rel);
    defer self.gpa.free(full);
    try Io.Dir.cwd().writeFile(self.io, .{ .sub_path = full, .data = bytes });
    b.dirty = false;
}

pub fn saveAs(self: *App, rel: []const u8) !void {
    if (rel.len > 0 and std.ascii.eqlIgnoreCase(extensionOf(rel), "dbf")) {
        self.setMessage("DBF files are not made here: import them into a database (EDIT > Import)", .{});
        return;
    }
    const t = self.activeTab() orelse return;
    if (t.buf == null or rel.len == 0) return;
    if (t.virtual) {
        self.setMessage("{s} is a read-only window", .{t.path});
        return;
    }
    try self.writeTab(t, rel);
    t.editing = false;
    if (!std.mem.eql(u8, t.path, rel)) {
        self.gpa.free(t.path);
        t.path = try self.gpa.dupe(u8, rel);
        t.eve = std.ascii.eqlIgnoreCase(extensionOf(rel), "eve");
        t.sql = std.ascii.eqlIgnoreCase(extensionOf(rel), "sql");
    }
    self.setMessage("saved {s}", .{rel});
}

// ------------------------------------------------------------ the list of a folder

pub fn freeFolder(self: *App, fv: *FolderView) void {
    for (fv.items.items) |it| self.gpa.free(it.name);
    fv.items.deinit(self.gpa);
    self.gpa.free(fv.dir);
    self.gpa.destroy(fv);
}

/// Read the content of folder `dir_rel` (a path in the project, "" for the project folder) into a new list.
pub fn loadFolder(self: *App, dir_rel: []const u8) !*FolderView {
    const gpa = self.gpa;
    const fv = try gpa.create(FolderView);
    errdefer gpa.destroy(fv);
    fv.* = .{ .dir = try gpa.dupe(u8, dir_rel) };
    errdefer self.freeFolderItems(fv);
    const full = if (dir_rel.len == 0) try gpa.dupe(u8, if (self.root.len == 0) "." else self.root) else try self.fullPath(dir_rel);
    defer gpa.free(full);
    var dir = try Io.Dir.cwd().openDir(self.io, full, .{ .iterate = true });
    defer dir.close(self.io);
    var it = dir.iterate();
    while (try it.next(self.io)) |e| {
        const is_dir = e.kind == .directory;
        if (!is_dir and e.kind != .file) continue;
        const st = dir.statFile(self.io, e.name, .{}) catch null;
        const name = try gpa.dupe(u8, e.name);
        errdefer gpa.free(name);
        try fv.items.append(gpa, .{ .name = name, .is_dir = is_dir, .size = if (st) |s| s.size else 0, .created = if (st) |s| s.ctime.toSeconds() else 0 });
    }
    std.mem.sort(FolderItem, fv.items.items, {}, struct {
        fn less(_: void, x: FolderItem, y: FolderItem) bool {
            if (x.is_dir != y.is_dir) return x.is_dir;
            return std.ascii.lessThanIgnoreCase(x.name, y.name);
        }
    }.less);
    if (dir_rel.len > 0) try fv.items.insert(gpa, 0, .{ .name = try gpa.dupe(u8, ".."), .is_dir = true, .size = 0, .created = 0 });
    return fv;
}

pub fn freeFolderItems(self: *App, fv: *FolderView) void {
    for (fv.items.items) |it| self.gpa.free(it.name);
    fv.items.deinit(self.gpa);
    self.gpa.free(fv.dir);
}

/// A folder was clicked in the tree: the Main Panel shows its content (a tab for each folder).
pub fn showFolder(self: *App, dir_rel: []const u8) !void {
    const gpa = self.gpa;
    const fv = try self.loadFolder(dir_rel);
    errdefer self.freeFolder(fv);
    const shown: []const u8 = if (dir_rel.len == 0) (if (self.project_name.len > 0) self.project_name else "project") else std.fs.path.basename(dir_rel);
    const label = try gpa.dupe(u8, shown);
    errdefer gpa.free(label);
    // a folder that is already open in a tab is shown again there (refreshed); another folder gets a new tab
    for (self.tabs.items, 0..) |*t, i| {
        if (t.folder) |old| {
            if (!std.mem.eql(u8, t.path, dir_rel)) continue;
            self.freeFolder(old);
            t.folder = fv;
            if (t.label.len > 0) gpa.free(t.label);
            t.label = label;
            self.active = i;
            return;
        }
    }
    try self.tabs.insert(gpa, 0, .{ .path = try gpa.dupe(u8, dir_rel), .folder = fv, .label = label });
    self.active = 0;
    self.tab_first = 0;
}

/// The path in the project of an item of a folder list.
pub fn folderItemPath(self: *App, fv: *const FolderView, i: usize) ![]u8 {
    const name = fv.items.items[i].name;
    if (fv.dir.len == 0) return self.gpa.dupe(u8, name);
    return std.fmt.allocPrint(self.gpa, "{s}/{s}", .{ fv.dir, name });
}

/// Enter or a second click on a row: a folder is shown, a file is opened.
pub fn openFolderItem(self: *App, fv: *FolderView, i: usize) !void {
    if (i >= fv.items.items.len) return;
    const it = fv.items.items[i];
    if (it.is_dir and std.mem.eql(u8, it.name, "..")) {
        const dir_copy = try self.gpa.dupe(u8, std.fs.path.dirname(fv.dir) orelse "");
        defer self.gpa.free(dir_copy);
        return self.showFolder(dir_copy);
    }
    const rel = try self.folderItemPath(fv, i);
    defer self.gpa.free(rel);
    if (it.is_dir) return self.showFolder(rel);
    try self.openFile(rel);
}

pub fn folderListKey(self: *App, fv: *FolderView, key: Key) !void {
    const n = fv.items.items.len;
    if (try self.markKey(key)) return;
    if (n == 0) return;
    if (key.matches(Key.up, .{})) fv.sel = fv.sel -| 1 else if (key.matches(Key.down, .{})) fv.sel = @min(fv.sel + 1, n - 1) else if (key.matches(Key.page_up, .{})) fv.sel = fv.sel -| 10 else if (key.matches(Key.page_down, .{})) fv.sel = @min(fv.sel + 10, n - 1) else if (key.matches(Key.home, .{})) fv.sel = 0 else if (key.matches(Key.end, .{})) fv.sel = n - 1 else if (key.matches(Key.enter, .{}) or key.matches(Key.space, .{})) try self.openFolderItem(fv, fv.sel) else if (key.matches(Key.backspace, .{}) and fv.dir.len > 0) {
        const up = try self.gpa.dupe(u8, std.fs.path.dirname(fv.dir) orelse "");
        defer self.gpa.free(up);
        try self.showFolder(up);
    }
}

/// The file selected in the folder list of the active tab (its path in the project, copied), or null.
pub fn folderSelectedFile(self: *App) ?[]u8 {
    const t = self.activeTab() orelse return null;
    const fv = t.folder orelse return null;
    if (fv.sel >= fv.items.items.len or fv.items.items[fv.sel].is_dir) return null;
    return self.folderItemPath(fv, fv.sel) catch null;
}

/// Open the file that is selected in a folder list, if the active tab is a folder list and a file is selected.
pub fn adoptFolderSelection(self: *App) !void {
    const rel = self.folderSelectedFile() orelse return;
    defer self.gpa.free(rel);
    try self.openFile(rel);
}

/// Can Run work now? (An Eve file is open, or selected in a folder list.)
pub fn canRun(self: *App) bool {
    if (self.folderSelectedFile()) |rel| {
        defer self.gpa.free(rel);
        return std.ascii.eqlIgnoreCase(extensionOf(rel), "eve");
    }
    const t = self.activeTab() orelse return false;
    return t.eve and t.buf != null;
}
