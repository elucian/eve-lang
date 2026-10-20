//! @eve-module evetx.app.props
//! @feature F-TLS-24
//! @decision D-173
//! @see code/evetx/src/app.zig:App
//! Properties, rename, move, and which menu commands are enabled.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const vaxis = @import("vaxis");
const ide = @import("ide");
const project = ide.project;
const text = ide.text;
const App = @import("../app.zig").App;
const types = @import("types.zig");
const Panel = types.Panel;
const describeName = types.describeName;
const Tab = types.Tab;
const MenuCmd = types.MenuCmd;

// ------------------------------------------------------------ properties, rename and delete

/// The file, folder or table that File > Rename and File > Delete work on, or null.
pub fn fileTarget(self: *App) ?[]u8 {
    if (self.focus == .tree and self.selected < self.tree.entries.items.len) {
        const e = self.tree.entries.items[self.selected];
        if (e.parent != null) return self.gpa.dupe(u8, e.path) catch null;
    }
    return self.propsTarget();
}

/// The file of the Info dialog of the active tab: the file selected in a folder list (else the folder of the list), or
/// the file (or table) of the tab.
pub fn propsTarget(self: *App) ?[]u8 {
    if (self.folderSelectedFile()) |rel| return rel;
    const t = self.activeTab() orelse return null;
    if (t.folder) |fv| return if (fv.dir.len == 0) null else self.gpa.dupe(u8, fv.dir) catch null;
    if (t.virtual or t.path.len == 0) return null;
    return self.gpa.dupe(u8, t.path) catch null;
}

/// File > Rename…: the Info dialog of the file or table that is pointed at, with its name ready to edit.
pub fn openRename(self: *App) void {
    if (!self.menuEnabled(.rename_file)) {
        self.setMessage("Rename works on one file or folder: {d} are selected (/ clears the selection)", .{self.marks.items.len});
        return;
    }
    const rel = self.fileTarget() orelse {
        self.setMessage("Rename: select a file in the tree, or open one (a new file must be saved first)", .{});
        return;
    };
    self.openPropertiesOf(rel, true);
}

/// Info… of the popup menu of a tab: the Info dialog of the file of the active tab.
pub fn openInfo(self: *App) void {
    const rel = self.propsTarget() orelse {
        self.setMessage("Info: this window is not a file on the disk (a new file must be saved first)", .{});
        return;
    };
    self.openPropertiesOf(rel, false);
}

/// Open the Info dialog of `rel` (a path in the project, or `db#table`); takes `rel`. `edit` opens the name for editing.
pub fn openPropertiesOf(self: *App, rel: []u8, edit: bool) void {
    if (self.rename_from) |old| self.gpa.free(old);
    self.rename_from = rel;
    self.props = .{};
    if (std.mem.indexOfScalar(u8, rel, '#')) |h| self.tableFacts(rel[0..h], rel[h + 1 ..]) else self.fileFacts(rel);
    self.prop_editing = false;
    self.openOverlay(.properties);
    if (edit) self.startRename();
}

/// The name of the Info dialog: the last part of the path, or the name of the table.
pub fn infoName(self: *const App) []const u8 {
    const rel = self.rename_from orelse return "";
    if (std.mem.indexOfScalar(u8, rel, '#')) |h| return rel[h + 1 ..];
    return std.fs.path.basename(rel);
}

/// The Rename button: the name of the Info dialog becomes a field in its place; Enter renames, Esc leaves it.
pub fn startRename(self: *App) void {
    if (self.props.is_view) {
        self.setMessage("{s} is a view: a view cannot be renamed, drop it and create it again", .{self.infoName()});
        return;
    }
    self.saveas_in.clearRetainingCapacity();
    self.saveas_in.insertSliceAtCursor(self.infoName()) catch {};
    self.prop_editing = true;
}

/// The facts of a file of the project.
pub fn fileFacts(self: *App, rel: []const u8) void {
    const p = &self.props;
    p.place = std.fs.path.dirname(rel) orelse "";
    const full = self.fullPath(rel) catch return;
    defer self.gpa.free(full);
    const st = Io.Dir.cwd().statFile(self.io, full, .{}) catch {
        p.kind = "not on the disk";
        return;
    };
    p.kind = describeName(std.fs.path.basename(rel), st.kind == .directory);
    if (st.kind != .directory) p.size = st.size;
    p.modified = st.mtime.toSeconds();
    for (self.tabs.items) |t| {
        if (!std.mem.eql(u8, t.path, rel)) continue;
        if (t.buf) |b| {
            p.lines = b.lineCount();
            p.line_ends = if (b.crlf) "CRLF (Windows)" else "LF";
            p.unsaved = b.dirty;
        }
        if (t.table) |tv| {
            p.records = tv.t.records;
            p.fields = tv.t.fields.len;
        }
    }
}

/// The facts of the table (or view) `table` of the SQLite file `db`.
pub fn tableFacts(self: *App, db: []const u8, table: []const u8) void {
    const gpa = self.gpa;
    const p = &self.props;
    p.place = db;
    p.kind = "SQLite table";
    const lit = std.mem.replaceOwned(u8, gpa, table, "'", "''") catch return;
    defer gpa.free(lit);
    const q1 = std.fmt.allocPrint(gpa, "select type from sqlite_master where name = '{s}';", .{lit}) catch return;
    defer gpa.free(q1);
    if (self.eveText(&.{ "db", "sql", "-t", db, q1 })) |out| {
        defer gpa.free(out);
        if (std.mem.eql(u8, App.secondLine(out), "view")) {
            p.kind = "SQLite view";
            p.is_view = true;
        }
    } else |_| {}
    const ident = std.mem.replaceOwned(u8, gpa, table, "\"", "\"\"") catch return;
    defer gpa.free(ident);
    const q2 = std.fmt.allocPrint(gpa, "select count(*) from \"{s}\";", .{ident}) catch return;
    defer gpa.free(q2);
    if (self.eveText(&.{ "db", "sql", "-t", db, q2 })) |out| {
        defer gpa.free(out);
        p.records = std.fmt.parseInt(u64, App.secondLine(out), 10) catch null;
    } else |_| {}
}

/// The second line of a text, trimmed ("" when there is none): the value under the header of `eve db sql -t`.
pub fn secondLine(out: []const u8) []const u8 {
    var it = std.mem.splitScalar(u8, out, '\n');
    _ = it.next();
    return std.mem.trim(u8, it.next() orelse "", " \r\t");
}

/// Enter in the name field of the Info dialog: rename the file on the disk, or the table in its database.
pub fn doRename(self: *App) !void {
    const gpa = self.gpa;
    const old = self.rename_from orelse return;
    const raw = try self.saveas_in.toOwnedContents(gpa);
    defer gpa.free(raw);
    const name = std.mem.trim(u8, raw, " ");
    self.prop_editing = false;
    if (std.mem.indexOfScalar(u8, old, '#')) |h| return self.renameTable(old[0..h], old[h + 1 ..], name);
    if (std.mem.indexOfAny(u8, name, "/\\") != null) {
        self.setMessage("a name has no folder in it: use Move to change the folder", .{});
        return;
    }
    if (name.len == 0 or std.mem.eql(u8, name, std.fs.path.basename(old))) return;
    const new_rel = if (std.fs.path.dirname(old)) |d| try std.fmt.allocPrint(gpa, "{s}/{s}", .{ d, name }) else try gpa.dupe(u8, name);
    defer gpa.free(new_rel);
    if (try self.moveFile(old, new_rel)) self.openPropertiesOf(try gpa.dupe(u8, new_rel), false);
}

/// Rename or move the file (or folder) `old` to `new`, two paths in the project.
pub fn moveFile(self: *App, old: []const u8, new: []const u8) !bool {
    const gpa = self.gpa;
    const old_full = try self.fullPath(old);
    defer gpa.free(old_full);
    const new_full = try self.fullPath(new);
    defer gpa.free(new_full);
    if (Io.Dir.cwd().statFile(self.io, new_full, .{})) |_| {
        self.setMessage("{s} exists already", .{new});
        return false;
    } else |_| {}
    Io.Dir.rename(Io.Dir.cwd(), old_full, Io.Dir.cwd(), new_full, self.io) catch |err| {
        self.setMessage("cannot move {s} to {s}: {s}", .{ old, new, @errorName(err) });
        return false;
    };
    self.retarget(old, new);
    self.refreshTree();
    self.saveSession() catch {};
    self.setMessage("{s} is now {s}", .{ old, new });
    return true;
}

/// The Move button of the Info dialog: the folder selector, to choose where the file goes.
pub fn openMove(self: *App) !void {
    const rel = self.rename_from orelse return;
    if (std.mem.indexOfScalar(u8, rel, '#') != null) {
        self.setMessage("a table moves with its database file", .{});
        return;
    }
    const dir_rel = std.fs.path.dirname(rel) orelse "";
    const start = if (dir_rel.len == 0) try self.gpa.dupe(u8, if (self.root.len > 0) self.root else ".") else try self.fullPath(dir_rel);
    defer self.gpa.free(start);
    self.openChooser(.move_to, .properties, start);
}

/// The path in the project of the folder `abs` ("" for the project folder), or null when it is outside the project.
pub fn projectRel(self: *App, abs: []const u8) !?[]u8 {
    var dir = Io.Dir.cwd().openDir(self.io, if (self.root.len > 0) self.root else ".", .{}) catch return null;
    defer dir.close(self.io);
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const n = dir.realPath(self.io, &buf) catch return null;
    const root = buf[0..n];
    if (abs.len < root.len) return null;
    const same = if (builtin.os.tag == .windows) std.ascii.eqlIgnoreCase(abs[0..root.len], root) else std.mem.eql(u8, abs[0..root.len], root);
    if (!same) return null;
    if (abs.len == root.len) return try self.gpa.dupe(u8, "");
    if (abs[root.len] != '/' and abs[root.len] != '\\') return null;
    const rel = try self.gpa.dupe(u8, abs[root.len + 1 ..]);
    std.mem.replaceScalar(u8, rel, '\\', '/');
    return rel;
}

/// Move here (the folder selector opened by Move): the file goes to the folder shown, then the Info dialog comes back.
pub fn moveHere(self: *App) !void {
    const gpa = self.gpa;
    const old = self.rename_from orelse return;
    const dest = self.fb_path orelse return;
    const dir_rel = (try self.projectRel(dest)) orelse {
        self.setMessage("{s} is outside the project: choose a folder of the project", .{dest});
        return;
    };
    defer gpa.free(dir_rel);
    const base = std.fs.path.basename(old);
    const new_rel = if (dir_rel.len == 0) try gpa.dupe(u8, base) else try std.fmt.allocPrint(gpa, "{s}/{s}", .{ dir_rel, base });
    defer gpa.free(new_rel);
    self.chooserDone();
    if (std.mem.eql(u8, new_rel, old)) return;
    if (std.mem.startsWith(u8, new_rel, old) and new_rel.len > old.len and new_rel[old.len] == '/') {
        self.setMessage("a folder cannot go into itself", .{});
        return;
    }
    if (try self.moveFile(old, new_rel)) self.openPropertiesOf(try gpa.dupe(u8, new_rel), false);
}

/// Rename the table `old` of the SQLite file `db` to `new`.
pub fn renameTable(self: *App, db: []const u8, old: []const u8, new: []const u8) !void {
    const gpa = self.gpa;
    if (new.len == 0 or std.mem.eql(u8, new, old)) return;
    if (self.props.is_view) {
        self.setMessage("{s} is a view: a view cannot be renamed, drop it and create it again", .{old});
        return;
    }
    if (std.mem.indexOfAny(u8, new, "\"#/\\") != null) {
        self.setMessage("a table name cannot hold \" # / or \\", .{});
        return;
    }
    const sql = try std.fmt.allocPrint(gpa, "alter table \"{s}\" rename to \"{s}\";", .{ old, new });
    defer gpa.free(sql);
    const out = try self.eveText(&.{ "db", "sql", db, sql });
    defer gpa.free(out);
    if (std.mem.indexOf(u8, out, "error:") != null) {
        self.setMessage("{s}", .{std.mem.trim(u8, out, " \r\n")});
        return;
    }
    const old_key = try std.fmt.allocPrint(gpa, "{s}#{s}", .{ db, old });
    defer gpa.free(old_key);
    var was_open = false;
    for (self.tabs.items, 0..) |t, i| {
        if (std.mem.eql(u8, t.path, old_key)) {
            self.closeTab(i);
            was_open = true;
            break;
        }
    }
    // `db` and `old` are slices of `rename_from`, which stays until the dialog shows the table under its new name
    try self.refreshDbTables(db);
    if (was_open) try self.openSqliteTable(db, new);
    self.setMessage("renamed table {s} to {s}", .{ old, new });
    self.openPropertiesOf(try std.fmt.allocPrint(gpa, "{s}#{s}", .{ db, new }), false);
}

/// Can the command of a menu row run now? Rename works on one item: it is off while several are selected.
pub fn menuEnabled(self: *App, cmd: MenuCmd) bool {
    const has_project = self.root.len > 0 and self.tree.entries.items.len > 0;
    const tabs = self.tabs.items.len;
    const tab = self.activeTab();
    const text_tab = if (tab) |t| t.buf != null and !t.virtual else false;
    const table = self.activeTable();
    const editable_table = if (table) |tv| !tv.readonly else false;
    return switch (cmd) {
        // File
        .new_file, .new_folder, .new_database, .find_file, .toggle_hidden, .find_files, .replace_files => has_project,
        .create_table, .import_data => has_project and self.selectedDb() != null,
        .save => if (tab) |t| text_tab or (t.table != null and !t.virtual) else false,
        .save_as => text_tab or (table != null and !self.isOverview()),
        .save_all => self.anyDirtyFile(),
        .select_all, .select_row, .unselect_row, .unselect_all => has_project or (if (tab) |t| t.folder != null or t.table != null else false),
        .rename_file => self.hasFileTarget() and self.marks.items.len <= 1,
        .delete_file, .move_marked => self.hasFileTarget() or self.marks.items.len > 0,
        .close_tab, .close_window, .close_all, .close_clean => tabs > 0,
        .close_project => self.root.len > 0 and self.selected < self.tree.entries.items.len and self.tree.entries.items[self.selected].parent == null,
        // Edit
        .undo, .redo => text_tab,
        .data_structure => if (table != null) !self.isOverview() else false,
        .drop_table => (table != null and !self.isOverview() and !std.mem.startsWith(u8, tab.?.path, "filter:")) or self.selectedDb() != null,
        .compact => table != null or self.selectedDb() != null,
        .data_append, .data_append_n, .data_delete => editable_table,
        .data_edit => text_tab or editable_table or self.isOverview() or (if (tab) |t| t.folder != null else false) or (self.focus == .tree and has_project),
        // Search: Find and Replace work in a text file that can be edited
        .find_text, .replace => text_tab,
        .goto_line => self.activeBuffer() != null,
        // Filter and Query work on the table of the window, or on the table that is selected in the tree and is open
        .query => self.tableTab() != null,
        .filter_table => self.tableTab() != null,
        // Run
        .run, .check_file => self.canRun() or self.job != null,
        .dbg_next, .dbg_step, .dbg_exit, .dbg_trace => self.canRun() or self.job != null,
        .stop => self.job != null or self.running,
        .breakpoint => if (tab) |t| t.buf != null and t.eve else false,
        // Window
        .select_window => tabs > 1 or self.activePanel() == .tools,
        .next_panel => self.shownPanels() > 1,
        else => true,
    };
}

pub fn shownPanels(self: *const App) u8 {
    var n: u8 = 0;
    for ([_]Panel{ .tree, .main, .tools }) |p| {
        if (self.isShown(p)) n += 1;
    }
    return n;
}

/// Is there a file or folder that Rename, Delete and Move can work on?
pub fn hasFileTarget(self: *App) bool {
    if (self.focus == .tree) {
        return self.selected < self.tree.entries.items.len and self.tree.entries.items[self.selected].parent != null;
    }
    const t = self.activeTab() orelse return false;
    if (t.folder != null) return t.path.len > 0;
    return !t.virtual and t.path.len > 0 and !std.mem.startsWith(u8, t.path, "filter:") and t.path[t.path.len - 1] != '#';
}

/// The window of the table that Filter and Query work on: the table selected in the tree when it is open, else the table
/// of the active window (the list of the tables of a database is not a table to filter).
pub fn tableTab(self: *App) ?*Tab {
    if (self.focus == .tree and self.selected < self.tree.entries.items.len) {
        const e = self.tree.entries.items[self.selected];
        for (self.tabs.items) |*t| {
            if (t.table != null and std.mem.eql(u8, t.path, e.path)) return t;
        }
    }
    const t = self.activeTab() orelse return null;
    if (t.table == null or self.isOverview()) return null;
    return t;
}

/// EDIT > Compact: vacuum and optimize a SQLite database.
pub fn compact(self: *App) void {
    if (self.sqlView()) |st| return self.compactDb(st.db);
    if (self.selectedDb()) |db| {
        const copy = self.gpa.dupe(u8, db) catch return;
        defer self.gpa.free(copy);
        return self.compactDb(copy);
    }
    self.setMessage("Compact: select a SQLite database", .{});
}

pub fn compactDb(self: *App, db: []const u8) void {
    if (!self.runSql(db, "vacuum;")) return;
    _ = self.runSql(db, "pragma optimize;");
    self.setMessage("{s} compacted (vacuum, optimize)", .{db});
}
