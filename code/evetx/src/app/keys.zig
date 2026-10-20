//! @eve-module evetx.app.keys
//! @feature F-TLS-24
//! @decision D-173
//! @see code/evetx/src/app.zig:App
//! The keyboard: what each key does in each panel.
const std = @import("std");
const Io = std.Io;
const vaxis = @import("vaxis");
const TextInput = vaxis.widgets.TextInput;
const Key = vaxis.Key;
const ide = @import("ide");
const project = ide.project;
const text = ide.text;
const App = @import("../app.zig").App;
const types = @import("types.zig");
const Panel = types.Panel;
const TableView = types.TableView;
const Tab = types.Tab;
const tab_menu_rows = types.tab_menu_rows;

// ------------------------------------------------------------ keys

pub fn onKey(self: *App, key: Key) !void {
    if (key.codepoint == Key.left_alt or key.codepoint == Key.right_alt) {
        self.alt_hint = true;
        return;
    }
    self.alt_hint = false;
    self.follow = true;
    if (self.pasting) {
        // a paste made by the terminal arrives as keys: collect them until the paste ends
        if (key.text) |t| try self.paste_buf.appendSlice(self.gpa, t) else if (key.matches(Key.enter, .{})) try self.paste_buf.append(self.gpa, '\n') else if (key.matches(Key.tab, .{})) try self.paste_buf.append(self.gpa, '\t');
        return;
    }
    if (self.message) |m| {
        self.gpa.free(m);
        self.message = null;
    }
    if (self.overlay != .none) return self.overlayKey(key);

    if (self.modify and try self.modifyKey(key)) return;
    if ((key.matches(Key.enter, .{ .ctrl = true }) and !self.ctrlEnterOpens()) or key.matches(Key.f10, .{})) return self.openMenu(0);
    if (key.mods.alt and !key.mods.ctrl) {
        if (key.codepoint == Key.left) return self.rotatePanel(-1);
        if (key.codepoint == Key.right) return self.rotatePanel(1);
        if (key.codepoint == Key.tab) return self.nextTab(if (key.mods.shift) -1 else 1);
        if (key.codepoint == Key.page_up) return self.nextTab(-1);
        if (key.codepoint == Key.page_down) return self.nextTab(1);
        if (key.codepoint >= '1' and key.codepoint <= '9') return self.pickDigit(key.codepoint - '1');
        if (key.codepoint == 't') return self.activatePanel(.tree);
        if (key.codepoint == 'm') return self.activatePanel(.main);
        if (key.codepoint == 'o') return self.activatePanel(.tools);
        if (App.menuByLetter(key.codepoint)) |m| return self.openMenu(m);
    }
    if (key.matches(Key.tab, .{ .shift = true })) return self.nextTab(1);
    if (key.matches(Key.tab, .{}) and self.tabSwitchesPanel()) return self.rotatePanel(1);
    if (key.matches(Key.insert, .{ .ctrl = true })) return self.openAppendN();
    if (key.matches(Key.page_up, .{ .ctrl = true })) return self.nextTab(-1);
    if (key.matches(Key.page_down, .{ .ctrl = true })) return self.nextTab(1);
    if (key.matches(Key.tab, .{ .ctrl = true })) return self.nextTab(1);
    if (App.ctrlDigit(key)) |d| return self.pickDigit(d);
    if (key.matches('/', .{ .ctrl = true }) or key.matches(Key.f12, .{})) return self.runMenu(.shortcuts, 0);
    if (key.matches(',', .{ .ctrl = true }) or key.matches(Key.f2, .{})) return self.openOptions();
    if (key.matches('u', .{ .ctrl = true })) return self.undoRedo(true);
    if (key.matches('y', .{ .ctrl = true })) return self.undoRedo(false);
    if (key.matches('o', .{ .ctrl = true, .shift = true }) or key.matches(Key.f4, .{ .shift = true })) return self.openFolderDialog();
    if (key.matches('o', .{ .ctrl = true })) return self.openProjectDialog();
    if (key.matches('q', .{ .ctrl = true })) {
        self.quit = true;
        return;
    }
    if (key.matches('s', .{ .ctrl = true, .shift = true }) or key.matches(Key.f4, .{})) return self.openOverlay(.save_as);
    if (key.matches('s', .{ .ctrl = true })) return self.save();
    if (key.matches('a', .{ .ctrl = true })) return self.saveAll();
    if (key.matches('w', .{ .ctrl = true })) return self.closeTab(self.active);
    if (key.matches('n', .{ .ctrl = true })) return self.openNewDialog();
    if (self.searchShortcut(key)) return;
    if (key.matches(Key.f5, .{})) return self.runActive();
    if (key.matches(Key.f6, .{})) return self.checkActive();
    if (key.matches(Key.f7, .{})) return self.notYet("Query", "T7");
    if (key.matches(Key.f9, .{})) return self.toggleBreakpoint();
    if (key.matches(Key.f8, .{})) return self.debugCommand("next");
    if (key.matches(Key.f8, .{ .shift = true })) return self.debugCommand("trace");
    if (key.matches(Key.f11, .{})) return self.debugCommand("step");
    if (key.matches(Key.f11, .{ .shift = true })) return self.debugCommand("exit");
    if (key.matches(Key.f5, .{ .shift = true })) return self.haltRun();

    switch (self.focus) {
        .editor => try self.editorKey(key),
        .tree => try self.treeKey(key),
        .console => try self.consoleKey(key),
        .breaks => try self.breaksKey(key),
        .sql => try self.sqlKey(key),
    }
}

/// Alt+1 to Alt+9 (and Ctrl+1 to Ctrl+9 where the terminal sends them): go to window `d`.
pub fn pickDigit(self: *App, d: usize) void {
    if (d >= self.tabs.items.len) {
        self.setMessage("no window {d}", .{d + 1});
        return;
    }
    self.pickWindow(d);
}

/// Does the Tab key change the panel now?
pub fn tabSwitchesPanel(self: *App) bool {
    return switch (self.focus) {
        .tree, .breaks => true,
        .console, .sql => true,
        // a text file that is in editing mode keeps Tab for indenting, and a cell being typed keeps it; otherwise it leaves
        .editor => if (self.activeTab()) |t| !((t.buf != null and t.editing and !t.virtual) or self.tbl_editing) else true,
    };
}

/// Does Ctrl+Enter open the row under the cursor (the tree, the list of the tables of a database) instead of the menu?
pub fn ctrlEnterOpens(self: *App) bool {
    if (true) return false; // Enter opens now; Ctrl+Enter is the menu everywhere
    if (self.focus == .tree) return true;
    if (self.focus != .editor) return false;
    if (self.activeTab()) |t| {
        if (t.folder != null) return true;
    }
    return self.isOverview();
}

/// Is the window the list of the tables of a SQLite database?
pub fn isOverview(self: *App) bool {
    const t = self.activeTab() orelse return false;
    return t.table != null and t.path.len > 0 and t.path[t.path.len - 1] == '#';
}

/// Ctrl+1 to Ctrl+9 give 0 to 8.
pub fn ctrlDigit(key: Key) ?usize {
    if (!key.mods.ctrl or key.mods.alt) return null;
    if (key.codepoint >= '1' and key.codepoint <= '9') return key.codepoint - '1';
    if (key.base_layout_codepoint) |c| {
        if (c >= '1' and c <= '9') return c - '1';
    }
    return null;
}

/// Ctrl+F, Ctrl+P, Ctrl+H, Ctrl+G, Ctrl+L: open a search dialog. True when the key was one of them.
pub fn searchShortcut(self: *App, key: Key) bool {
    if (key.matches('f', .{ .ctrl = true })) self.openOverlay(.find_text) else if (key.matches('p', .{ .ctrl = true })) self.openOverlay(.find_file) else if (key.matches('h', .{ .ctrl = true })) self.openOverlay(.replace) else if (key.matches('g', .{ .ctrl = true })) self.openOverlay(.goto) else if (key.matches('l', .{ .ctrl = true })) self.startModify(false) else return false;
    return true;
}

/// The text of a field, valid until the end of the frame.
pub fn fieldText(self: *App, ti: *TextInput) []const u8 {
    const s = ti.toOwnedContents(self.frame.allocator()) catch return "";
    return std.mem.trim(u8, s, " ");
}

pub fn overlayKey(self: *App, key: Key) !void {
    if (key.matches(Key.escape, .{})) return self.closeOverlay();
    if (self.overlay != .menu and self.overlay != .tab_menu and self.overlay != .confirm and self.overlay != .sq_structure and self.overlay != .properties and self.overlay != .alert and self.overlay != .settings and self.overlay != .new_file and self.overlay != .wizard and self.overlay != .append_n and self.searchShortcut(key)) return;
    switch (self.overlay) {
        .menu => try self.menuKey(key),
        .tab_menu => {
            const n = tab_menu_rows.len;
            // the rule is not a row to stop on: the arrows step over it
            if (key.matches(Key.up, .{})) {
                self.tab_menu_sel = (self.tab_menu_sel + n - 1) % n;
                if (tab_menu_rows[self.tab_menu_sel].cmd == .sep) self.tab_menu_sel = (self.tab_menu_sel + n - 1) % n;
            } else if (key.matches(Key.down, .{})) {
                self.tab_menu_sel = (self.tab_menu_sel + 1) % n;
                if (tab_menu_rows[self.tab_menu_sel].cmd == .sep) self.tab_menu_sel = (self.tab_menu_sel + 1) % n;
            } else if (key.matches(Key.enter, .{})) try self.runTabMenu(self.tab_menu_sel);
        },
        .new_file => {
            if (key.matches(Key.enter, .{})) try self.newFromName() else try self.saveas_in.update(.{ .key_press = key });
        },
        .wizard => try self.wizardKey(key),
        .append_n => {
            if (key.matches(Key.enter, .{})) try self.appendNEnter() else try self.goto_in.update(.{ .key_press = key });
        },
        .sq_structure => try self.sqKey(key),
        .properties => {
            if (self.prop_editing) {
                if (key.matches(Key.enter, .{})) try self.doRename() else try self.saveas_in.update(.{ .key_press = key });
            } else if (key.matches(Key.f2, .{}) or key.matches('r', .{})) {
                self.startRename();
            } else if (key.matches('m', .{})) {
                try self.openMove();
            } else if (key.matches(Key.enter, .{})) self.overlay = .none;
        },
        .alert => if (key.matches(Key.enter, .{})) self.closeOverlay(),
        .confirm => {
            if (key.matches('y', .{}) or key.matches('Y', .{ .shift = true }) or key.matches(Key.enter, .{})) {
                self.confirmYes();
            } else if (key.matches('n', .{}) or key.matches('N', .{ .shift = true })) self.overlay = .none;
        },
        .settings => try self.optionsKey(key),
        .about => {
            if (key.matches(Key.enter, .{})) self.overlay = .none;
        },
        .open_project => try self.projectKey(key),
        .open_folder => try self.folderKey(key),
        .goto => {
            if (key.matches(Key.enter, .{})) try self.gotoEnter() else try self.goto_in.update(.{ .key_press = key });
        },
        .save_as => {
            if (key.matches(Key.enter, .{})) {
                const s = try self.saveas_in.toOwnedContents(self.gpa);
                defer self.gpa.free(s);
                self.saveas_in.clearRetainingCapacity();
                self.overlay = .none;
                try self.saveAs(std.mem.trim(u8, s, " "));
            } else try self.saveas_in.update(.{ .key_press = key });
        },
        .find_text => {
            if (key.matches(Key.enter, .{})) try self.findNext() else try self.find_in.update(.{ .key_press = key });
        },
        .find_file => try self.filesKey(key),
        .filter => try self.filterKey(key),
        .replace => try self.replaceKey(key),
        .none => {},
    }
}

/// The keys while a menu is open: arrows move, Enter runs, a letter opens another menu.
pub fn menuKey(self: *App, key: Key) !void {
    if (key.matches(Key.up, .{})) return self.menuMove(-1);
    if (key.matches(Key.down, .{})) return self.menuMove(1);
    if (key.matches(Key.left, .{})) return self.menuSide(-1);
    if (key.matches(Key.right, .{})) return self.menuSide(1);
    if (key.matches(Key.home, .{})) {
        self.menu_sel = self.firstItem(self.menu_top);
        return;
    }
    if (key.matches(Key.enter, .{})) {
        const row = self.rowAt(self.menu_top, self.menu_sel);
        if (row.cmd) |c| try self.runMenu(c, row.arg);
        return;
    }
    if (!key.mods.ctrl) {
        if (App.menuByLetter(key.codepoint)) |m| self.openMenu(m);
    }
}

/// The keys of a table: arrows move the cell, Page Up and Down a page, Home and End the first and last record.
pub fn tableKey(self: *App, tv: *TableView, key: Key) !void {
    if (self.tbl_editing) {
        if (key.matches(Key.enter, .{})) return self.commitCell(tv);
        if (key.matches(Key.escape, .{})) {
            // Esc leaves the cell without keeping what was typed, and ends the editing of the table
            self.tbl_editing = false;
            if (self.activeTab()) |t| t.editing = false;
            return;
        }
        try self.tbl_edit.update(.{ .key_press = key });
        return;
    }
    const rows = tv.t.records;
    const cols = tv.t.fields.len;
    const page: usize = 15;
    if (try self.markKey(key)) return;
    // Esc ends the editing of the table (Enter starts it again)
    if (key.matches(Key.escape, .{})) {
        if (self.activeTab()) |t| {
            if (t.editing) {
                t.editing = false;
                self.setMessage("editing stopped: Enter starts it again", .{});
            }
        }
        return;
    }
    if (self.isOverview()) {
        // the list of the tables: Enter says what the row is, Ctrl+Enter or Space opens the table
        if (key.matches(Key.enter, .{}) or key.matches(Key.space, .{})) return self.dataEdit();
        if (key.matches(Key.enter, .{ .ctrl = true })) {
            if (tv.row < tv.t.records) {
                var b0: [16]u8 = undefined;
                var b1: [16]u8 = undefined;
                var b2: [16]u8 = undefined;
                self.setMessage("{s} · {s} columns · {s} rows · Ctrl+Enter or a double click opens it", .{ tv.t.display(tv.row, 0, &b0), tv.t.display(tv.row, 2, &b1), tv.t.display(tv.row, 3, &b2) });
            }
            return;
        }
    }
    if (key.matches(Key.enter, .{})) return self.dataEdit();
    if (key.matches(Key.insert, .{})) return self.dataAppend(1);
    if (key.matches(Key.delete, .{})) return self.dataDelete();
    if (key.matches(Key.up, .{})) tv.row -|= 1 else if (key.matches(Key.down, .{})) tv.row = @min(tv.row + 1, rows -| 1) else if (key.matches(Key.left, .{})) tv.col -|= 1 else if (key.matches(Key.right, .{})) tv.col = @min(tv.col + 1, cols -| 1) else if (key.matches(Key.page_up, .{})) tv.row -|= page else if (key.matches(Key.page_down, .{})) tv.row = @min(tv.row + page, rows -| 1) else if (key.matches(Key.home, .{})) tv.row = 0 else if (key.matches(Key.end, .{})) tv.row = rows -| 1 else if (key.matches(Key.home, .{ .ctrl = true })) tv.col = 0 else if (key.matches(Key.end, .{ .ctrl = true })) tv.col = cols -| 1;
}

/// The keys of the editor: moving (Shift extends the selection), typing, copy and paste.
pub fn editorKey(self: *App, key: Key) !void {
    if (self.activeTab()) |t| {
        if (t.table) |tv| return self.tableKey(tv, key);
        if (t.folder) |fv| return self.folderListKey(fv, key);
    }
    const b = self.activeBuffer() orelse return;
    const tab = self.activeTab().?;
    // a window that is not in editing mode (or is read only) can be moved in and copied from, not changed
    const ro = tab.virtual or !tab.editing;
    if (key.matches('c', .{ .ctrl = true })) return self.copySelection(false);
    if (key.matches('x', .{ .ctrl = true })) return self.copySelection(!ro);
    if (key.matches('v', .{ .ctrl = true })) {
        if (ro) return self.needEditing(tab);
        return self.pasteClip();
    }
    if (key.matches('a', .{ .ctrl = true })) {
        b.selectAll();
        return;
    }
    var k = key;
    k.mods.shift = false;
    const here: text.Pos = .{ .row = b.row, .col = b.col };
    const page: isize = @max(1, @as(isize, self.editor_rect.h));
    const moved = blk: {
        if (k.matches(Key.left, .{ .ctrl = true })) b.wordLeft() else if (k.matches(Key.right, .{ .ctrl = true })) b.wordRight() else if (k.matches(Key.left, .{})) b.moveLeft() else if (k.matches(Key.right, .{})) b.moveRight() else if (k.matches(Key.up, .{})) b.moveRows(-1) else if (k.matches(Key.down, .{})) b.moveRows(1) else if (k.matches(Key.page_up, .{})) b.moveRows(-page) else if (k.matches(Key.page_down, .{})) b.moveRows(page) else if (k.matches(Key.home, .{})) b.home() else if (k.matches(Key.end, .{})) b.toEnd() else break :blk false;
        break :blk true;
    };
    if (moved) {
        if (!key.mods.shift) b.anchor = null else if (b.anchor == null) b.anchor = here;
        b.last_edit = .none;
        return;
    }
    if (key.matches(Key.escape, .{})) {
        b.anchor = null;
        if (tab.editing) {
            tab.editing = false;
            self.setMessage("editing stopped: Enter starts it again", .{});
        }
        return;
    }
    if (ro) {
        // Enter starts the editing; the keys that would change the text only say how to start
        if (!tab.virtual and key.matches(Key.enter, .{})) {
            tab.editing = true;
            self.setMessage("editing: Esc or Save stops it", .{});
        } else if (key.text != null or key.matches(Key.backspace, .{}) or key.matches(Key.delete, .{}) or key.matches(Key.tab, .{})) self.needEditing(tab);
        return;
    }
    const selected = b.selection() != null;
    if (key.matches(Key.enter, .{})) {
        try b.checkpoint(.other);
        _ = try b.deleteSelection();
        try b.newline();
    } else if (key.matches(Key.backspace, .{})) {
        try b.checkpoint(if (selected) .other else .erasing);
        if (!try b.deleteSelection()) try b.backspace();
    } else if (key.matches(Key.delete, .{})) {
        try b.checkpoint(if (selected) .other else .erasing);
        if (!try b.deleteSelection()) try b.delete();
    } else if (key.matches(Key.tab, .{})) {
        try b.checkpoint(if (selected) .other else .typing);
        _ = try b.deleteSelection();
        try b.insert("  ");
    } else if (key.mods.ctrl or key.mods.alt) {
        // a shortcut that is not ours: do not type its letter; say so
        self.unknownShortcut(key);
    } else if (key.text) |t| {
        try b.checkpoint(if (selected) .other else .typing);
        _ = try b.deleteSelection();
        try b.insert(t);
    }
}

/// Ctrl+C, and Ctrl+X when `cut` is true.
pub fn copySelection(self: *App, cut: bool) !void {
    const b = self.activeBuffer() orelse return;
    const t = (try b.selectedText(self.gpa)) orelse {
        self.setMessage("nothing is selected", .{});
        return;
    };
    errdefer self.gpa.free(t);
    const sys = try self.gpa.dupe(u8, t);
    if (self.clip) |c| self.gpa.free(c);
    self.clip = t;
    if (self.sys_clip) |c| self.gpa.free(c);
    self.sys_clip = sys;
    if (cut and !self.activeTab().?.virtual) {
        try b.checkpoint(.other);
        _ = try b.deleteSelection();
    }
}

/// Ctrl+V: insert the copied text. (A paste made by the terminal comes as keys: see `pasteEnd`.)
/// Say how to start editing (a text file that is not in editing mode got a key that changes the text).
pub fn needEditing(self: *App, tab: *Tab) void {
    if (tab.virtual) return self.setMessage("this window is read only", .{});
    self.setMessage("press Enter to start editing (Esc stops)", .{});
}

pub fn pasteClip(self: *App) !void {
    const b = self.activeBuffer() orelse return;
    if (self.activeTab().?.virtual or !self.activeTab().?.editing) return;
    const c = self.clip orelse {
        self.setMessage("nothing copied yet", .{});
        return;
    };
    try b.checkpoint(.other);
    try b.insertText(c);
}

/// The title of the terminal window: the program and the project.
pub fn windowTitle(self: *const App, buf: []u8) []const u8 {
    if (self.project_name.len == 0) return "EVE-TX";
    return std.fmt.bufPrint(buf, "EVE-TX · {s}", .{self.project_name}) catch "EVE-TX";
}

/// The main loop takes the text for the system clipboard (the caller frees it).
pub fn takeSystemClip(self: *App) ?[]u8 {
    const c = self.sys_clip;
    self.sys_clip = null;
    return c;
}

pub fn pasteStart(self: *App) void {
    self.pasting = true;
    self.paste_buf.clearRetainingCapacity();
}

/// The terminal ended a paste: the collected text goes to the dialog field, the console or the editor.
pub fn pasteEnd(self: *App) !void {
    self.pasting = false;
    const t = self.paste_buf.items;
    if (t.len == 0) return;
    if (self.overlay != .none or self.focus == .console or self.focus == .sql) {
        const ti: ?*TextInput = switch (self.overlay) {
            .none => if (self.focus == .sql) &self.sql_in else &self.console_in,
            .goto => &self.goto_in,
            .save_as, .new_file, .properties => &self.saveas_in,
            .sq_structure => if (self.sq_new and self.sq_page == 0) (if (self.dlg_field == 0) &self.sq_name_in else &self.sq_desc_in) else if (self.sq_editing) &self.sq_edit else null,
            .wizard => &self.wiz_name,
            .append_n => &self.goto_in,
            .filter => if (self.flt_rows.items.len > 0) &self.flt_in else null,
            .find_text => &self.find_in,
            .find_file => &self.files_in,
            .replace => if (self.dlg_field == 0) &self.find_in else &self.replace_in,
            .open_folder => if (self.dlg_field == 0) &self.project_in else if (self.dlg_field == 2) &self.fb_name else null,
            .settings => if (self.opt_edit != .none) &self.opt_in else null,
            else => null,
        };
        const field = ti orelse return;
        const line = t[0 .. std.mem.indexOfScalar(u8, t, '\n') orelse t.len];
        try field.insertSliceAtCursor(line);
        if (self.overlay == .find_file) try self.filesChanged();
        return;
    }
    if (self.focus == .editor) {
        const b = self.activeBuffer() orelse return;
        if (self.activeTab().?.virtual) return;
        if (!self.activeTab().?.editing) return self.needEditing(self.activeTab().?);
        try b.checkpoint(.other);
        try b.insertText(t);
    }
}

pub fn treeKey(self: *App, key: Key) !void {
    self.tree_follow = true;
    const rows = self.visible.items;
    if (rows.len == 0) return;
    var pos: usize = 0;
    for (rows, 0..) |r, i| {
        if (r == self.selected) pos = i;
    }
    const e = &self.tree.entries.items[self.selected];
    if (try self.markKey(key)) return;
    if (key.matches(Key.up, .{})) {
        self.selected = rows[if (pos > 0) pos - 1 else 0];
    } else if (key.matches(Key.down, .{})) {
        self.selected = rows[@min(pos + 1, rows.len - 1)];
    } else if (key.matches(Key.right, .{})) {
        if (e.is_dir) e.expanded = true;
        if (e.kind == .db and !e.expanded) {
            e.expanded = true;
            try self.loadDbTables(self.selected);
        }
    } else if (key.matches(Key.left, .{})) {
        if ((e.is_dir or e.kind == .db) and e.expanded and e.parent != null) e.expanded = false else if (e.parent) |p| self.selected = p;
    } else if (key.matches(Key.enter, .{}) or key.matches(Key.enter, .{ .ctrl = true }) or key.matches(Key.space, .{})) {
        // Enter says what is selected in the status bar and opens it (a folder in the Main Panel); it does not fold or unfold
        self.selectionInfo();
        try self.openEntry(self.selected);
    } else if (key.matches(Key.page_up, .{})) {
        self.selected = rows[pos -| 10];
    } else if (key.matches(Key.page_down, .{})) {
        self.selected = rows[@min(pos + 10, rows.len - 1)];
    } else if (key.mods.ctrl or key.mods.alt) {
        self.unknownShortcut(key);
    }
}

/// Enter in the tree: say in the status bar what is selected.
pub fn selectionInfo(self: *App) void {
    if (self.selected >= self.tree.entries.items.len) return;
    const e = self.tree.entries.items[self.selected];
    const what: []const u8 = if (e.kind == .table) "table" else if (e.kind == .db) "database" else if (e.is_dir) "folder" else "file";
    var size: u64 = 0;
    if (!e.is_dir and e.kind == .normal) {
        if (self.fullPath(e.path)) |full| {
            defer self.gpa.free(full);
            if (Io.Dir.cwd().statFile(self.io, full, .{})) |st| size = st.size else |_| {}
        } else |_| {}
    }
    if (size > 0) {
        self.setMessage("{s}: {s} · {d} bytes · Ctrl+Enter or a double click opens it", .{ what, e.path, size });
    } else self.setMessage("{s}: {s} · Ctrl+Enter or a double click opens it", .{ what, e.path });
}

pub fn openEntry(self: *App, index: u32) !void {
    const e = &self.tree.entries.items[index];
    self.selected = index;
    self.tree_follow = true;
    if (e.kind == .table) return self.openFile(e.path);
    if (e.kind == .db) {
        // the entry may move when the tables are put under it, so the path is copied first
        const db_path = try self.gpa.dupe(u8, e.path);
        defer self.gpa.free(db_path);
        // a database is shown as the list of its tables; the icon and the arrow keys fold and unfold it
        try self.showDatabase(db_path);
        return;
    }
    if (e.is_dir) {
        // the folder that is clicked becomes the working folder of the console, and its content fills the Main Panel
        try self.enterFolder(e.path);
        const folder_path = try self.gpa.dupe(u8, e.path);
        defer self.gpa.free(folder_path);
        try self.showFolder(folder_path);
    } else try self.openFile(e.path);
}

pub fn filesKey(self: *App, key: Key) !void {
    if (key.matches(Key.enter, .{})) {
        const had = self.saved_open != null;
        if (had) {
            self.gpa.free(self.saved_open.?);
            self.saved_open = null;
        }
        self.files_in.clearRetainingCapacity();
        self.focus = .tree;
        self.overlay = .none;
        return self.openEntry(self.selected);
    }
    if (key.matches(Key.down, .{})) return self.filesStep(1);
    if (key.matches(Key.up, .{})) return self.filesStep(-1);
    try self.files_in.update(.{ .key_press = key });
    try self.filesChanged();
}

pub fn replaceKey(self: *App, key: Key) !void {
    if (key.matches(Key.tab, .{}) or key.matches(Key.down, .{}) or key.matches(Key.up, .{})) {
        self.dlg_field = 1 - self.dlg_field;
        return;
    }
    if (key.matches(Key.enter, .{})) return if (self.dlg_field == 0) self.findNext() else self.replaceOne();
    const ti = if (self.dlg_field == 0) &self.find_in else &self.replace_in;
    try ti.update(.{ .key_press = key });
}

/// Tab in the console: complete the file or folder name that starts with the letters before the cursor. One match is
/// completed (a folder gets a `/`), several are completed as far as they agree and listed in the console.
pub fn consoleComplete(self: *App) !void {
    const gpa = self.gpa;
    const first = self.console_in.buf.firstHalf();
    var start: usize = first.len;
    while (start > 0 and first[start - 1] != ' ') start -= 1;
    const word = first[start..];
    const sep_at = std.mem.lastIndexOfAny(u8, word, "/\\");
    const dir_part = if (sep_at) |i| word[0 .. i + 1] else "";
    const prefix = if (sep_at) |i| word[i + 1 ..] else word;
    const base = self.work_dir orelse (if (self.root.len == 0) "." else self.root);
    const dir_path = if (dir_part.len > 0 and std.fs.path.isAbsolute(dir_part))
        try gpa.dupe(u8, dir_part)
    else if (dir_part.len > 0)
        try std.fmt.allocPrint(gpa, "{s}/{s}", .{ base, dir_part })
    else
        try gpa.dupe(u8, base);
    defer gpa.free(dir_path);
    var dir = Io.Dir.cwd().openDir(self.io, dir_path, .{ .iterate = true }) catch return;
    defer dir.close(self.io);
    const Match = struct { name: []u8, is_dir: bool };
    var found: std.ArrayList(Match) = .empty;
    defer {
        for (found.items) |m| gpa.free(m.name);
        found.deinit(gpa);
    }
    var it = dir.iterate();
    while (it.next(self.io) catch null) |e| {
        if (e.name.len < prefix.len or !std.ascii.eqlIgnoreCase(e.name[0..prefix.len], prefix)) continue;
        const copy = gpa.dupe(u8, e.name) catch break;
        found.append(gpa, .{ .name = copy, .is_dir = e.kind == .directory }) catch {
            gpa.free(copy);
            break;
        };
    }
    if (found.items.len == 0) {
        self.setMessage("no file or folder starts with '{s}'", .{prefix});
        return;
    }
    std.mem.sort(Match, found.items, {}, struct {
        fn less(_: void, a: Match, b: Match) bool {
            return std.ascii.lessThanIgnoreCase(a.name, b.name);
        }
    }.less);
    // the longest start that all the names share
    var common: usize = found.items[0].name.len;
    for (found.items[1..]) |m| {
        var k: usize = 0;
        while (k < common and k < m.name.len and std.ascii.toLower(m.name[k]) == std.ascii.toLower(found.items[0].name[k])) k += 1;
        common = k;
    }
    if (common > prefix.len) {
        try self.console_in.insertSliceAtCursor(found.items[0].name[prefix.len..common]);
    }
    if (found.items.len == 1) {
        if (found.items[0].is_dir) try self.console_in.insertSliceAtCursor("/");
        return;
    }
    if (common > prefix.len) return;
    // nothing more to add: show what there is
    var line: std.ArrayList(u8) = .empty;
    defer line.deinit(gpa);
    for (found.items) |m| {
        try line.appendSlice(gpa, m.name);
        if (m.is_dir) try line.append(gpa, '/');
        try line.appendSlice(gpa, "  ");
    }
    try self.console.add(gpa, std.mem.trimEnd(u8, line.items, " "), .info);
}

pub fn consoleKey(self: *App, key: Key) !void {
    if (key.matches(Key.escape, .{})) {
        // Esc cancels a waiting command, and clears the prompt
        if (self.pending_at != null) {
            self.cancelPending();
            self.console_in.clearRetainingCapacity();
            self.setMessage("command cancelled", .{});
        }
        self.focus = .editor;
        return;
    }
    if (key.matches(Key.enter, .{})) {
        self.cancelPending();
        return self.consoleEnter();
    }
    if (self.pending_at != null) self.cancelPending();
    // Right at the end of the line completes a file name (Tab leaves the panel)
    if (key.matches(Key.right, .{}) and self.console_in.buf.secondHalf().len == 0 and self.console_in.buf.firstHalf().len > 0) return self.consoleComplete();
    if (key.matches(Key.up, .{ .ctrl = true })) return self.historyStep(-1);
    if (key.matches(Key.down, .{ .ctrl = true })) return self.historyStep(1);
    if (key.matches(Key.page_up, .{})) {
        self.console.scroll +|= @max(1, self.console_rect.h / 2);
        return;
    }
    if (key.matches(Key.page_down, .{})) {
        self.console.scroll -|= @max(1, self.console_rect.h / 2);
        return;
    }
    try self.console_in.update(.{ .key_press = key });
}

pub fn breaksKey(self: *App, key: Key) !void {
    const n = self.breakpoints.items.len;
    if (n == 0) return;
    if (key.matches(Key.up, .{})) self.break_sel = self.break_sel -| 1 else if (key.matches(Key.down, .{})) self.break_sel = @min(self.break_sel + 1, n - 1) else if (key.matches(Key.enter, .{})) try self.jumpToBreakpoint(self.break_sel) else if (key.matches(Key.delete, .{})) {
        self.askConfirm(.delete_breakpoint, self.break_sel, "Remove the breakpoint {s}:{d}?", .{ self.breakpoints.items[self.break_sel].path, self.breakpoints.items[self.break_sel].line });
    } else if (key.matches(' ', .{})) self.toggleBreakpointEnabled(self.break_sel);
}
