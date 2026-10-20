//! @eve-module evetx.app.dialogs
//! @feature F-TLS-24
//! @decision D-173
//! @see code/evetx/src/app.zig:App
//! Auto save, undo, the tab menu, and the project and folder dialogs.
const std = @import("std");
const Io = std.Io;
const vaxis = @import("vaxis");
const Key = vaxis.Key;
const ide = @import("ide");
const project = ide.project;
const theme = @import("../theme.zig");
const App = @import("../app.zig").App;
const types = @import("types.zig");
const Overlay = types.Overlay;
const FbMode = types.FbMode;
const Tab = types.Tab;
const tab_menu_rows = types.tab_menu_rows;

// ------------------------------------------------------------ auto save

pub fn anyDirtyFile(self: *const App) bool {
    for (self.tabs.items) |t| {
        if (!t.virtual and t.path.len > 0 and t.buf != null and t.buf.?.dirty) return true;
    }
    return false;
}

/// Called all the time by `tick`: saves the files that have changes when the auto save time is over.
pub fn autoSaveTick(self: *App) void {
    if (self.options.autosave_s == 0 or !self.anyDirtyFile()) {
        self.autosave_at = null;
        return;
    }
    const now = self.nowMs();
    const at = self.autosave_at orelse {
        self.autosave_at = now + @as(i64, self.options.autosave_s) * 1000;
        return;
    };
    if (now < at) return;
    self.autosave_at = null;
    var n: usize = 0;
    for (self.tabs.items) |*t| {
        if (t.table != null) continue;
        if (t.virtual or t.path.len == 0 or t.buf == null or !t.buf.?.dirty) continue;
        self.writeTab(t, t.path) catch continue;
        n += 1;
    }
    if (n > 0) self.setMessage("auto saved {d} file(s)", .{n});
}

// ------------------------------------------------------------ undo and closing many windows

/// Ctrl+U (undo) and Ctrl+Y (redo) on the current window.
pub fn undoRedo(self: *App, undo: bool) !void {
    const b = self.activeBuffer() orelse return;
    if (self.activeTab().?.virtual) return;
    const done = if (undo) try b.undo() else try b.redo();
    if (!done) self.setMessage("nothing to {s}", .{if (undo) "undo" else "redo"});
    self.follow = true;
}

/// Close the windows `lo` to `hi - 1` that have no unsaved changes.
pub fn closeClean(self: *App, lo: usize, hi: usize) void {
    var kept: usize = 0;
    var i = @min(hi, self.tabs.items.len);
    while (i > lo) {
        i -= 1;
        const t = self.tabs.items[i];
        if (t.buf != null and t.buf.?.dirty) kept += 1 else self.closeTab(i);
    }
    if (kept > 0) self.setMessage("{d} window(s) with unsaved changes were kept", .{kept});
}

/// Window > Close All: closes every window, unless one has unsaved changes.
pub fn closeAll(self: *App) void {
    var dirty: usize = 0;
    for (self.tabs.items) |t| {
        if (t.buf != null and t.buf.?.dirty) dirty += 1;
    }
    if (dirty > 0) {
        self.setMessage("{d} window(s) have unsaved changes: save them, or use Close Clean", .{dirty});
        return;
    }
    while (self.tabs.items.len > 0) self.closeTab(0);
}

/// A right click on a tab: open its popup menu there.
pub fn openTabMenu(self: *App, tab: usize, m: vaxis.Mouse) void {
    self.tab_menu_tab = tab;
    self.tab_menu_sel = 0;
    self.tab_menu_x = @intCast(@max(m.col, 0));
    self.tab_menu_y = @intCast(@max(m.row + 1, 0));
    self.overlay = .tab_menu;
}

/// Run row `i` of the popup menu of a tab.
pub fn runTabMenu(self: *App, i: usize) !void {
    const tab = self.tab_menu_tab;
    self.overlay = .none;
    if (tab >= self.tabs.items.len or i >= tab_menu_rows.len) return;
    switch (tab_menu_rows[i].cmd) {
        .save => {
            self.active = tab;
            try self.save();
        },
        .save_as => {
            self.active = tab;
            self.openOverlay(.save_as);
        },
        .info => {
            self.active = tab;
            self.openInfo();
        },
        .rename => {
            self.active = tab;
            self.focus = .editor;
            self.openRename();
        },
        .sep => {},
        .close_this => self.closeTab(tab),
        .close_right => self.closeClean(tab + 1, self.tabs.items.len),
        .close_left => self.closeClean(0, tab),
        .close_clean => self.closeClean(0, self.tabs.items.len),
    }
}

// ------------------------------------------------------------ dialogs: projects and folders

/// Close the dialog that is open. The Find File dialog puts the tree back as it was.
pub fn closeOverlay(self: *App) void {
    // Esc in the Info dialog first leaves the name field; the folder selector and the pop-up go back to their dialog
    if (self.overlay == .properties and self.prop_editing) {
        self.prop_editing = false;
        return;
    }
    if (self.overlay == .filter and self.flt_pick) {
        self.flt_pick = false;
        return;
    }
    if (self.overlay == .open_folder and self.fb_mode != .project) return self.chooserDone();
    if (self.overlay == .alert) {
        self.overlay = self.alert_back;
        return;
    }
    // Esc in the structure dialog first leaves the cell or the type list that is open
    if (self.overlay == .sq_structure and (self.sq_editing or self.sq_drop)) {
        self.sq_editing = false;
        self.sq_drop = false;
        return;
    }
    if (self.overlay == .find_file) self.filesCancel();
    if (self.overlay == .settings) {
        // Esc in the field under the list of themes closes the field only
        if (self.opt_edit != .none) {
            self.opt_edit = .none;
            return;
        }
        // Cancel: the options (the themes too) go back to what they were when the dialog opened
        self.options = self.opt_backup;
        self.applyOptions();
    }
    self.overlay = .none;
}

/// File > Open project: the list of the known projects.
pub fn openProjectDialog(self: *App) void {
    self.proj_sel = 0;
    self.proj_top = 0;
    self.openOverlay(.open_project);
}

/// File > Open Folder: the folder browser, which starts in the project folder, or in the current folder.
pub fn openFolderDialog(self: *App) void {
    self.fb_mode = .project;
    if (self.fb_path == null) self.fbLoad(if (self.root.len > 0) self.root else ".");
    self.openOverlay(.open_folder);
    self.dlg_field = 1;
}

/// Open project `i` of the list and move it to the top of the list.
pub fn openCached(self: *App, i: usize) !void {
    if (i >= self.cache.projects.items.len) return;
    const path = try self.gpa.dupe(u8, self.cache.projects.items[i]);
    defer self.gpa.free(path);
    self.overlay = .none;
    self.cache.add(path) catch {};
    try self.openProject(path);
}

/// Take the selected project out of the list (its folder and files stay).
pub fn forgetProject(self: *App) !void {
    const n = self.cache.projects.items.len;
    if (self.proj_sel >= n) return;
    const name = try self.gpa.dupe(u8, App.baseName(self.cache.projects.items[self.proj_sel]));
    defer self.gpa.free(name);
    try self.cache.forget(self.proj_sel);
    self.proj_sel = @min(self.proj_sel, self.cache.projects.items.len -| 1);
    self.setMessage("forgotten: {s} (the folder stays on the disk)", .{name});
}

/// The button Open as project of the folder browser: the folder joins the list and opens.
pub fn openHere(self: *App) !void {
    const shown = self.fb_path orelse return;
    const path = try self.gpa.dupe(u8, shown);
    defer self.gpa.free(path);
    self.overlay = .none;
    self.cache.add(path) catch |err| self.setMessage("project cache: {s}", .{@errorName(err)});
    try self.openProject(path);
}

/// Open the folder selector for `mode` in the folder `start`; Cancel and Esc go back to the dialog `back`.
pub fn openChooser(self: *App, mode: FbMode, back: Overlay, start: []const u8) void {
    self.fb_mode = mode;
    self.fb_back = back;
    self.fbLoad(start);
    self.overlay = .open_folder;
    self.dlg_field = if (mode == .theme_export or mode == .save_as) 2 else 1;
}

/// The folder selector is done: back to the dialog that opened it; the next Open Folder lists folders only.
pub fn chooserDone(self: *App) void {
    self.overlay = self.fb_back;
    self.fb_mode = .project;
    for (self.fb_files.items) |e| self.gpa.free(e);
    self.fb_files.clearRetainingCapacity();
}

/// Does the folder selector have a file name field (and list the theme files)?
pub fn fbHasName(self: *const App) bool {
    return self.fb_mode == .theme_export or self.fb_mode == .theme_import or self.fb_mode == .save_as;
}

/// The main button of the folder selector (and F2).
pub fn fbOk(self: *App) !void {
    switch (self.fb_mode) {
        .project => try self.openHere(),
        .move_to => try self.moveHere(),
        .move_many => try self.moveManyHere(),
        .save_as => try self.saveHere(),
        .theme_export => try self.exportTheme(),
        .theme_import => try self.importTheme(),
    }
}

/// The last part of a path.
pub fn baseName(path: []const u8) []const u8 {
    const cut = std.mem.lastIndexOfAny(u8, path, "/\\");
    return if (cut) |i| path[i + 1 ..] else path;
}

/// Show folder `path` in the browser: read its sub folders, and put its real path in the field.
/// A folder that cannot be read leaves the browser as it was.
pub fn fbLoad(self: *App, path: []const u8) void {
    var dir = Io.Dir.cwd().openDir(self.io, path, .{ .iterate = true }) catch |err| {
        self.setMessage("cannot open '{s}': {s}", .{ path, @errorName(err) });
        return;
    };
    defer dir.close(self.io);
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const n = dir.realPath(self.io, &buf) catch |err| {
        self.setMessage("cannot read '{s}': {s}", .{ path, @errorName(err) });
        return;
    };
    const abs = self.gpa.dupe(u8, buf[0..n]) catch return;
    self.fbClear();
    const with_files = self.fbHasName();
    var it = dir.iterate();
    while (it.next(self.io) catch null) |e| {
        if (self.fb_entries.items.len + self.fb_files.items.len >= 20000) break;
        const list = if (e.kind == .directory) &self.fb_entries else if (with_files and e.kind == .file and (self.fb_mode == .save_as or std.ascii.endsWithIgnoreCase(e.name, ".json"))) &self.fb_files else continue;
        const name = self.gpa.dupe(u8, e.name) catch break;
        list.append(self.gpa, name) catch {
            self.gpa.free(name);
            break;
        };
    }
    const by_name = struct {
        fn less(_: void, a: []u8, b: []u8) bool {
            return std.ascii.lessThanIgnoreCase(a, b);
        }
    }.less;
    std.mem.sort([]u8, self.fb_entries.items, {}, by_name);
    std.mem.sort([]u8, self.fb_files.items, {}, by_name);
    if (self.fb_path) |old| self.gpa.free(old);
    self.fb_path = abs;
    self.fb_sel = 0;
    self.fb_top = 0;
    self.project_in.clearRetainingCapacity();
    self.project_in.insertSliceAtCursor(abs) catch {};
}

pub fn fbClear(self: *App) void {
    for (self.fb_entries.items) |e| self.gpa.free(e);
    self.fb_entries.clearRetainingCapacity();
    for (self.fb_files.items) |e| self.gpa.free(e);
    self.fb_files.clearRetainingCapacity();
}

/// Is there a folder above the one shown? (Not at the root of a drive.)
pub fn fbHasParent(self: *const App) bool {
    const p = self.fb_path orelse return false;
    return std.fs.path.dirname(p) != null;
}

/// The rows of the browser: `..` first when there is a parent, then the sub folders, then the theme files.
pub fn fbRowCount(self: *const App) usize {
    return self.fb_entries.items.len + self.fb_files.items.len + @intFromBool(self.fbHasParent());
}

/// The name shown in row `i`.
pub fn fbRowName(self: *const App, i: usize) []const u8 {
    var k = i;
    if (self.fbHasParent()) {
        if (k == 0) return "..";
        k -= 1;
    }
    if (k < self.fb_entries.items.len) return self.fb_entries.items[k];
    return self.fb_files.items[k - self.fb_entries.items.len];
}

/// Is row `i` a file (not `..`, not a folder)?
pub fn fbRowIsFile(self: *const App, i: usize) bool {
    return i >= @intFromBool(self.fbHasParent()) + self.fb_entries.items.len;
}

/// A file row that is selected puts its name in the name field.
pub fn fbPickName(self: *App) void {
    if (!self.fbHasName() or self.fb_sel >= self.fbRowCount() or !self.fbRowIsFile(self.fb_sel)) return;
    self.fb_name.clearRetainingCapacity();
    self.fb_name.insertSliceAtCursor(self.fbRowName(self.fb_sel)) catch {};
}

pub fn fbUp(self: *App) void {
    const p = self.fb_path orelse return;
    const parent = std.fs.path.dirname(p) orelse return;
    const copy = self.gpa.dupe(u8, parent) catch return;
    defer self.gpa.free(copy);
    self.fbLoad(copy);
}

/// Go into the folder of row `i` (or up, for `..`); a file row is chosen: Import reads it, Export takes its name.
pub fn fbEnterRow(self: *App, i: usize) !void {
    if (i >= self.fbRowCount()) return;
    if (self.fbRowIsFile(i)) {
        self.fb_sel = i;
        self.fbPickName();
        if (self.fb_mode == .theme_import) return self.fbOk();
        self.dlg_field = 2;
        return;
    }
    const name = self.fbRowName(i);
    if (std.mem.eql(u8, name, "..")) return self.fbUp();
    const p = self.fb_path orelse return;
    const joined = std.fs.path.join(self.gpa, &.{ p, name }) catch return;
    defer self.gpa.free(joined);
    self.fbLoad(joined);
}

/// The keys of the project list.
pub fn projectKey(self: *App, key: Key) !void {
    const n = self.cache.projects.items.len;
    if (key.matches(Key.enter, .{})) return self.openCached(self.proj_sel);
    if (key.matches(Key.delete, .{}) or key.matches('f', .{})) return self.forgetProject();
    if (key.matches('i', .{}) or key.matches(Key.insert, .{})) return self.openFolderDialog();
    if (n == 0) return;
    if (key.matches(Key.up, .{})) self.proj_sel = self.proj_sel -| 1 else if (key.matches(Key.down, .{})) self.proj_sel = @min(self.proj_sel + 1, n - 1) else if (key.matches(Key.page_up, .{})) self.proj_sel = self.proj_sel -| 8 else if (key.matches(Key.page_down, .{})) self.proj_sel = @min(self.proj_sel + 8, n - 1) else if (key.matches(Key.home, .{})) self.proj_sel = 0 else if (key.matches(Key.end, .{})) self.proj_sel = n - 1;
}

/// The keys of the folder browser: Tab goes from the path field to the list (and to the name field), F2 is the main button.
pub fn folderKey(self: *App, key: Key) !void {
    const fields: u8 = if (self.fbHasName()) 3 else 2;
    if (key.matches(Key.tab, .{})) {
        self.dlg_field = (self.dlg_field + 1) % fields;
        return;
    }
    if (key.matches(Key.f2, .{})) return self.fbOk();
    if (self.dlg_field == 2) {
        if (key.matches(Key.enter, .{})) return self.fbOk();
        return self.fb_name.update(.{ .key_press = key });
    }
    if (self.dlg_field == 0) {
        if (key.matches(Key.enter, .{})) {
            const typed = try self.project_in.toOwnedContents(self.gpa);
            defer self.gpa.free(typed);
            self.fbLoad(std.mem.trim(u8, typed, " \""));
            self.dlg_field = 1;
        } else if (key.matches(Key.down, .{})) {
            self.dlg_field = 1;
        } else try self.project_in.update(.{ .key_press = key });
        return;
    }
    const n = self.fbRowCount();
    if (key.matches(Key.enter, .{}) or key.matches(Key.right, .{})) return self.fbEnterRow(self.fb_sel);
    if (key.matches(Key.left, .{}) or key.matches(Key.backspace, .{})) return self.fbUp();
    if (n == 0) return;
    if (key.matches(Key.up, .{})) self.fb_sel = self.fb_sel -| 1 else if (key.matches(Key.down, .{})) self.fb_sel = @min(self.fb_sel + 1, n - 1) else if (key.matches(Key.page_up, .{})) self.fb_sel = self.fb_sel -| 8 else if (key.matches(Key.page_down, .{})) self.fb_sel = @min(self.fb_sel + 8, n - 1) else if (key.matches(Key.home, .{})) self.fb_sel = 0 else if (key.matches(Key.end, .{})) self.fb_sel = n - 1;
    self.fbPickName();
}
