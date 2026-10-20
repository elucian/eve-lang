//! @eve-module evetx.app.menu
//! @feature F-TLS-24
//! @decision D-173
//! @see code/evetx/src/app.zig:App
//! Overlays and the main menu.
const std = @import("std");
const vaxis = @import("vaxis");
const ide = @import("ide");
const text = ide.text;
const App = @import("../app.zig").App;
const types = @import("types.zig");
const Overlay = types.Overlay;
const MenuCmd = types.MenuCmd;
const MenuRow = types.MenuRow;
const sep = types.sep;
const menu_window = types.menu_window;
const menus = types.menus;
const help_shortcuts = types.help_shortcuts;
const help_manual = types.help_manual;
const help_tutorial = types.help_tutorial;

// ------------------------------------------------------------ overlays and the menu

pub fn openOverlay(self: *App, which: Overlay) void {
    if (which == .save_as) {
        // a table is saved as a new table, or as a view when it is a filter; a text file goes to the folder selector
        if (self.activeTable() != null) return self.openTableSaveAs();
        return self.openSaveChooser();
    }
    if (which == .save_as) {
        const untitled = if (self.activeTab()) |t| t.path.len == 0 else false;
        const dir = self.targetDir();
        if (untitled and dir.len > 0 and self.saveas_in.buf.firstHalf().len + self.saveas_in.buf.secondHalf().len == 0) {
            self.saveas_in.insertSliceAtCursor(dir) catch {};
            self.saveas_in.insertSliceAtCursor("/") catch {};
        }
    }
    self.overlay = which;
    self.dlg_field = 0;
}

/// How many rows menu `m` has now.
pub fn rowCount(self: *const App, m: usize) usize {
    const base = menus[m].items.len;
    if (m == menu_window and self.tabs.items.len > 0) return base + 1 + @min(self.tabs.items.len, 9);
    return base;
}

/// Row `k` of menu `m`. The title of a window is a slice of the tab, valid while the tab is open.
pub fn rowAt(self: *const App, m: usize, k: usize) MenuRow {
    const items = menus[m].items;
    if (k < items.len) return items[k];
    if (k == items.len) return sep;
    const t = k - items.len - 1;
    return .{ .label = self.tabs.items[t].title(), .cmd = .window_pick, .arg = t };
}

/// The first row of menu `m` that is a command (not a separator).
pub fn firstItem(self: *const App, m: usize) usize {
    var k: usize = 0;
    while (k < self.rowCount(m)) : (k += 1) {
        if (self.rowAt(m, k).cmd != null) return k;
    }
    return 0;
}

/// Open menu `i` of the bar (a click, F10 or Alt and its letter) with its first command selected.
pub fn openMenu(self: *App, i: usize) void {
    self.overlay = .menu;
    self.menu_top = i;
    self.menu_sel = self.firstItem(i);
}

/// The menu whose letter is `c` (upper or lower case), if there is one.
pub fn menuByLetter(c: u21) ?usize {
    if (c > 127) return null;
    const lower = std.ascii.toLower(@intCast(c));
    for (menus, 0..) |m, i| {
        if (std.ascii.toLower(m.label[0]) == lower) return i;
    }
    return null;
}

pub fn notYet(self: *App, what: []const u8, step: []const u8) void {
    self.setMessage("{s}: not yet ({s}, README.md §8)", .{ what, step });
}

pub fn runMenu(self: *App, cmd: MenuCmd, arg: usize) !void {
    self.overlay = .none;
    if (!self.menuEnabled(cmd)) {
        if (cmd == .rename_file) self.openRename() else self.setMessage("this command does not apply to the window that is open", .{});
        return;
    }
    switch (cmd) {
        .open_project => self.openProjectDialog(),
        .open_folder => self.openFolderDialog(),
        .new_file => self.openNewDialog(),
        .new_folder => self.openNewKind(.folder),
        .new_database => self.openNewKind(.database),
        .create_table => self.openCreateTable(),
        .import_data => self.openImport(),
        .rename_file => self.openRename(),
        .delete_file => self.openDelete(),
        .move_marked => try self.startMove(),
        .select_all => try self.markAll(),
        .select_row => try self.markCurrent(true),
        .unselect_row => try self.markCurrent(false),
        .unselect_all => self.clearSelection(),
        .drop_table => try self.dropTable(""),
        .data_structure => try self.dataStructure(),
        .data_append => try self.dataAppend(1),
        .data_append_n => self.openAppendN(),
        .data_delete => try self.dataDelete(),
        .data_edit => self.dataEditOrOpen(),
        .save_all => self.saveAll(),
        .next_panel => self.rotatePanel(1),
        .save => try self.save(),
        .save_as => self.openOverlay(.save_as),
        .close_tab => self.closeTab(self.active),
        .quit => self.quit = true,
        .undo => try self.undoRedo(true),
        .redo => try self.undoRedo(false),
        .close_all => self.closeAll(),
        .close_clean => self.closeClean(0, self.tabs.items.len),
        .find_text => self.openOverlay(.find_text),
        .find_file => self.openOverlay(.find_file),
        .replace => self.openOverlay(.replace),
        .toggle_hidden => self.show_hidden = !self.show_hidden,
        .toggle_wrap => {
            self.wrap = !self.wrap;
            self.follow = true;
        },
        .goto_line => self.openOverlay(.goto),
        .query => self.notYet("Query SQL", "T7"),
        .filter_table => self.openFilter(),
        .close_project => self.closeProject(),
        .close_window => self.closeTab(self.active),
        .find_files => self.notYet("Find in files", "later"),
        .replace_files => self.notYet("Replace in files", "later"),
        .compact => self.compact(),
        .run => try self.runActive(),
        .check_file => try self.checkActive(),
        .dbg_next => try self.debugCommand("next"),
        .dbg_step => try self.debugCommand("step"),
        .dbg_exit => try self.debugCommand("exit"),
        .dbg_trace => try self.debugCommand("trace"),
        .stop => try self.haltRun(),
        .clear_panel => try self.clearPanel(),
        .breakpoint => try self.toggleBreakpoint(),
        .select_window => self.nextTab(1),
        .modify => self.startModify(false),
        .freeze => self.freezeLayout(),
        .toggle_tree => self.togglePanel(.tree),
        .toggle_main => self.togglePanel(.main),
        .toggle_tools => self.togglePanel(.tools),
        .window_pick => self.pickWindow(arg),
        .shortcuts => try self.openVirtual("Shortcuts", help_shortcuts),
        .manual => try self.openVirtual("Manual", help_manual),
        .tutorial => try self.openVirtual("Tutorial", help_tutorial),
        .about => self.openOverlay(.about),
        .options => self.openOptions(),
    }
}

pub fn menuMove(self: *App, delta: isize) void {
    var i: isize = @intCast(self.menu_sel);
    const n: isize = @intCast(self.rowCount(self.menu_top));
    while (true) {
        i = @mod(i + delta, n);
        if (self.rowAt(self.menu_top, @intCast(i)).cmd != null) break;
    }
    self.menu_sel = @intCast(i);
}

pub fn menuSide(self: *App, delta: isize) void {
    const n: isize = menus.len;
    const to: usize = @intCast(@mod(@as(isize, @intCast(self.menu_top)) + delta, n));
    self.openMenu(to);
}
