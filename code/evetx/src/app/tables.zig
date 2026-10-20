//! @eve-module evetx.app.tables
//! @feature F-TLS-28
//! @decision D-173
//! @see code/evetx/src/app.zig:App
//! Close project, delete, create and drop table, alter table, the SQL tab and its target, the tree.
const std = @import("std");
const Io = std.Io;
const vaxis = @import("vaxis");
const ide = @import("ide");
const project = ide.project;
const App = @import("../app.zig").App;
const types = @import("types.zig");
const Tab = types.Tab;

/// File > Close project: close all the windows and empty the tree (File > Open project opens another).
pub fn closeProject(self: *App) void {
    if (self.root.len == 0) return;
    for (self.tabs.items) |t| {
        if (t.buf != null and t.buf.?.dirty) {
            self.setMessage("save or close the changed files first", .{});
            return;
        }
    }
    const empty_name = self.gpa.dupe(u8, "") catch return;
    const empty_root = self.gpa.dupe(u8, "") catch {
        self.gpa.free(empty_name);
        return;
    };
    self.saveSession() catch {};
    while (self.tabs.items.len > 0) self.closeTab(0);
    for (self.breakpoints.items) |b| self.gpa.free(b.path);
    self.breakpoints.clearRetainingCapacity();
    if (self.saved_open) |snap| self.gpa.free(snap);
    self.saved_open = null;
    self.tree.deinit();
    self.tree = project.Tree.init(self.gpa);
    self.gpa.free(self.project_name);
    self.gpa.free(self.root);
    if (self.work_dir) |c| self.gpa.free(c);
    self.work_dir = null;
    self.project_name = empty_name;
    self.root = empty_root;
    self.selected = 0;
    self.tree_top = 0;
    self.focus = .tree;
    self.setMessage("project closed", .{});
}

/// The paths to delete, copied into `move_srcs` (the list is free while a question is open): the selected rows, else the
/// row under the cursor. Tables (`db#table`) and the project folder are left out.
pub fn deleteTargets(self: *App) !void {
    for (self.move_srcs.items) |p| self.gpa.free(p);
    self.move_srcs.clearRetainingCapacity();
    if (self.marks.items.len > 0) {
        for (self.marks.items) |p| {
            if (std.mem.indexOfScalar(u8, p, '#') != null) continue;
            try self.move_srcs.append(self.gpa, try self.gpa.dupe(u8, p));
        }
    } else if (self.fileTarget()) |rel| {
        if (std.mem.indexOfScalar(u8, rel, '#') != null) self.gpa.free(rel) else try self.move_srcs.append(self.gpa, rel);
    }
}

/// File > Delete…: ask first; Yes deletes the selected files and folders (a folder with its content).
pub fn openDelete(self: *App) void {
    self.deleteTargets() catch return;
    const n = self.move_srcs.items.len;
    if (n == 0) {
        self.setMessage("Delete: select files or folders (a table is dropped with EDIT > Drop table…)", .{});
        return;
    }
    var folders: usize = 0;
    for (self.move_srcs.items) |rel| {
        const full = self.fullPath(rel) catch continue;
        defer self.gpa.free(full);
        const st = Io.Dir.cwd().statFile(self.io, full, .{}) catch continue;
        if (st.kind == .directory) folders += 1;
    }
    if (n == 1) {
        const what: []const u8 = if (folders == 1) "the folder and everything in it" else "the file";
        self.askConfirm(.delete_file, 0, "Delete {s} {s}? It cannot be recovered.", .{ what, self.move_srcs.items[0] });
    } else if (folders == 0) {
        self.askConfirm(.delete_file, 0, "Delete {d} files? They cannot be recovered.", .{n});
    } else {
        self.askConfirm(.delete_file, 0, "Delete {d} items ({d} folders with their content)? They cannot be recovered.", .{ n, folders });
    }
}

/// Close the windows of a file, and of the files inside a folder, that is going away.
pub fn closeTabsUnder(self: *App, path: []const u8) void {
    var i = self.tabs.items.len;
    while (i > 0) {
        i -= 1;
        const tp = self.tabs.items[i].path;
        const same = std.mem.eql(u8, tp, path);
        const inside = tp.len > path.len and std.mem.startsWith(u8, tp, path) and tp[path.len] == '/';
        if (same or inside) self.closeTab(i);
    }
}

/// The Yes of the delete dialog: delete the files and folders, close their windows, scan the tree again.
pub fn performDelete(self: *App) void {
    var done: usize = 0;
    var failed: usize = 0;
    for (self.move_srcs.items) |rel| {
        const full = self.fullPath(rel) catch continue;
        defer self.gpa.free(full);
        // a folder inside a folder that went before is already gone
        const st = Io.Dir.cwd().statFile(self.io, full, .{}) catch continue;
        const res = if (st.kind == .directory) Io.Dir.cwd().deleteTree(self.io, full) else Io.Dir.cwd().deleteFile(self.io, full);
        res catch {
            failed += 1;
            continue;
        };
        self.closeTabsUnder(rel);
        done += 1;
    }
    self.clearMarks();
    self.refreshTree();
    self.reloadFolders();
    self.selected = @min(self.selected, @as(u32, @intCast(self.tree.entries.items.len -| 1)));
    if (failed > 0) self.setMessage("deleted {d}, {d} failed", .{ done, failed }) else self.setMessage("deleted {d} item(s)", .{done});
}

// ------------------------------------------------------------ create table and drop table

/// The SQLite file that is selected in the tree (the file itself, or the file of a table), or null.
pub fn selectedDb(self: *const App) ?[]const u8 {
    if (self.selected >= self.tree.entries.items.len) return null;
    const e = self.tree.entries.items[self.selected];
    return switch (e.kind) {
        .db => e.path,
        .table => e.path[0 .. std.mem.indexOfScalar(u8, e.path, '#') orelse e.path.len],
        .normal => null,
    };
}

/// Why `name` cannot be the name of a table, or null when it can.
pub fn tableNameError(name: []const u8) ?[]const u8 {
    if (name.len == 0) return "the table needs a name";
    if (!(std.ascii.isAlphabetic(name[0]) or name[0] == '_')) return "a table name begins with a letter";
    for (name) |c| {
        if (!(std.ascii.isAlphanumeric(c) or c == '_')) return "a table name has letters, digits and _ only";
    }
    if (name.len > 47) return "the name is too long (47 characters at most)";
    if (std.ascii.startsWithIgnoreCase(name, "eve_")) return "names that begin with eve_ are kept for Eve";
    return null;
}

/// EDIT > Create table…: the dialog of a new table (name and description, fields, indexes) in the selected database.
pub fn openCreateTable(self: *App) void {
    self.createTableNamed("") catch {};
}

/// Open the dialog of a new table `name` (it may be empty) in the database that is selected in the tree.
pub fn createTableNamed(self: *App, name: []const u8) !void {
    const db = self.selectedDb() orelse {
        self.setMessage("select a database in the tree first: tables are made in a SQLite database", .{});
        return;
    };
    const copy = try self.gpa.dupe(u8, db);
    defer self.gpa.free(copy);
    try self.openSqStructureNew(copy, name);
}

/// The tables of a database of the tree are read again (and the database is opened), after one was made or dropped.
pub fn refreshDbTables(self: *App, db_rel: []const u8) !void {
    for (self.tree.entries.items, 0..) |*e, i| {
        if (e.kind == .db and std.mem.eql(u8, e.path, db_rel)) {
            e.expanded = true;
            try self.loadDbTables(@intCast(i));
            return;
        }
    }
}

/// Ask whether to drop a table: the current one, or the one called `name`.
pub fn dropTable(self: *App, name: []const u8) !void {
    const gpa = self.gpa;
    var db: ?[]const u8 = null;
    var table: []const u8 = name;
    if (name.len == 0) {
        if (self.activeTab()) |t| {
            if (t.table != null) {
                if (std.mem.indexOfScalar(u8, t.path, '#')) |h| {
                    db = t.path[0..h];
                    table = t.path[h + 1 ..];
                }
            }
        }
        if (db == null and self.selected < self.tree.entries.items.len) {
            const e = self.tree.entries.items[self.selected];
            if (e.kind == .table) {
                const h = std.mem.indexOfScalar(u8, e.path, '#') orelse 0;
                db = e.path[0..h];
                table = e.path[h + 1 ..];
            }
        }
        if (db == null) {
            self.setMessage("drop table: no table is open or selected", .{});
            try self.sql_log.add(gpa, "drop table: no table is open or selected; open one, or write its name", .err);
            return;
        }
    } else switch (self.sqlTarget()) {
        .sqlite => |d| db = d,
        else => {
            try self.sql_log.add(gpa, "drop table: select a database in the tree (tables are in SQLite)", .err);
            return;
        },
    }
    if (self.drop_a) |old| gpa.free(old);
    if (self.drop_b) |old| gpa.free(old);
    self.drop_b = null;
    self.drop_a = try gpa.dupe(u8, db.?);
    self.drop_b = try gpa.dupe(u8, table);
    self.askConfirm(.drop_table, 0, "Drop the table {s} of {s}? Its rows are lost.", .{ table, db.? });
}

/// The Yes of the drop dialog: drop the table of the database; close its tab; fix the tree.
pub fn performDrop(self: *App) void {
    const gpa = self.gpa;
    const a_path = self.drop_a orelse return;
    const table = self.drop_b orelse return;
    const sql = std.fmt.allocPrint(gpa, "drop table \"{s}\";", .{table}) catch return;
    defer gpa.free(sql);
    var out = self.eveText(&.{ "db", "sql", a_path, sql }) catch return;
    if (std.mem.indexOf(u8, out, "view") != null) {
        gpa.free(out);
        const sql2 = std.fmt.allocPrint(gpa, "drop view \"{s}\";", .{table}) catch return;
        defer gpa.free(sql2);
        out = self.eveText(&.{ "db", "sql", a_path, sql2 }) catch return;
    }
    defer gpa.free(out);
    if (std.mem.startsWith(u8, out, "error:")) {
        self.setMessage("{s}", .{std.mem.trim(u8, out, " \r\n")});
        self.sql_log.addBlock(gpa, out, .err) catch {};
        return;
    }
    const key = std.fmt.allocPrint(gpa, "{s}#{s}", .{ a_path, table }) catch return;
    defer gpa.free(key);
    self.closeTabByPath(key);
    self.refreshDbTables(a_path) catch {};
    self.setMessage("dropped {s} of {s}", .{ table, a_path });
}

pub fn closeTabByPath(self: *App, path: []const u8) void {
    for (self.tabs.items, 0..) |t, i| {
        if (std.mem.eql(u8, t.path, path)) {
            self.closeTab(i);
            return;
        }
    }
}

// ------------------------------------------------------------ alter table and the Tab of the SQL panel

/// The working folder of the console as a path in the project ("" for the project folder).
pub fn workDirRel(self: *const App) []const u8 {
    const w = self.work_dir orelse return "";
    if (std.mem.eql(u8, w, self.root)) return "";
    if (w.len > self.root.len + 1 and std.mem.startsWith(u8, w, self.root) and w[self.root.len] == '/') return w[self.root.len + 1 ..];
    return "";
}

/// The folder of the table that is open or selected, else the target folder of the tree.
pub fn currentFolder(self: *const App) []const u8 {
    if (self.tabs.items.len > 0) {
        const t = self.tabs.items[@min(self.active, self.tabs.items.len - 1)];
        if (t.table != null and std.mem.indexOfScalar(u8, t.path, '#') == null) return std.fs.path.dirname(t.path) orelse "";
    }
    return self.targetDir();
}

/// `alter table [name]`: open the structure dialog of that table.
pub fn alterTable(self: *App, name: []const u8) !void {
    const gpa = self.gpa;
    if (name.len == 0) {
        if (self.activeTab()) |t| {
            if (t.table != null) {
                if (std.mem.indexOfScalar(u8, t.path, '#')) |h| return self.openSqStructure(t.path[0..h], t.path[h + 1 ..]);
            }
        }
        if (self.selected < self.tree.entries.items.len) {
            const e = self.tree.entries.items[self.selected];
            if (e.kind == .table) {
                const h = std.mem.indexOfScalar(u8, e.path, '#') orelse return;
                return self.openSqStructure(e.path[0..h], e.path[h + 1 ..]);
            }
        }
        try self.sql_log.add(gpa, "alter table: no table is open or selected; open one, or write its name", .err);
        return;
    }
    switch (self.sqlTarget()) {
        .sqlite => |db| {
            const copy = try gpa.dupe(u8, db);
            defer gpa.free(copy);
            try self.openSqStructure(copy, name);
        },
        else => try self.sql_log.add(gpa, "alter table: select a database in the tree (tables are in SQLite)", .err),
    }
}

/// The names of the tables that SQL can reach now: the tables of the database that is the target, or the DBF tables of
/// the current folder. Sorted; the caller frees the names and the list.
pub fn sqlTableNames(self: *App) !std.ArrayList([]u8) {
    const gpa = self.gpa;
    var out: std.ArrayList([]u8) = .empty;
    errdefer {
        for (out.items) |n| gpa.free(n);
        out.deinit(gpa);
    }
    switch (self.sqlTarget()) {
        .sqlite => |db| {
            const text_out = try self.eveText(&.{ "db", "sql", "-t", db, "select name from sqlite_master where type in ('table','view') and name not like 'sqlite_%' and name not like 'eve\\_%' escape '\\' order by name;" });
            defer gpa.free(text_out);
            if (std.mem.startsWith(u8, text_out, "error:")) return out;
            var lines = std.mem.splitScalar(u8, text_out, '\n');
            _ = lines.next();
            while (lines.next()) |raw| {
                const n = std.mem.trim(u8, raw, " \r");
                if (n.len > 0) try out.append(gpa, try gpa.dupe(u8, n));
            }
        },
        else => {},
    }
    return out;
}

/// Tab in the SQL panel: complete the word with the next table whose name starts with the letters typed.
pub fn sqlTab(self: *App) !void {
    const gpa = self.gpa;
    if (!self.sql_tab_active) {
        const first = self.sql_in.buf.firstHalf();
        var start: usize = first.len;
        while (start > 0 and first[start - 1] != ' ' and first[start - 1] != '(' and first[start - 1] != ',') start -= 1;
        const word = first[start..];
        if (self.sql_tab_prefix) |old| gpa.free(old);
        self.sql_tab_prefix = try gpa.dupe(u8, word);
        self.sql_tab_len = std.unicode.utf8CountCodepoints(word) catch word.len;
        self.sql_tab_idx = 0;
        self.sql_tab_active = true;
    } else self.sql_tab_idx += 1;
    const prefix = self.sql_tab_prefix orelse "";
    var names = self.sqlTableNames() catch return;
    defer {
        for (names.items) |n| gpa.free(n);
        names.deinit(gpa);
    }
    var matches: std.ArrayList([]u8) = .empty;
    defer matches.deinit(gpa);
    for (names.items) |n| {
        if (n.len >= prefix.len and std.ascii.eqlIgnoreCase(n[0..prefix.len], prefix)) try matches.append(gpa, n);
    }
    if (matches.items.len == 0) {
        self.setMessage("no table starts with '{s}'", .{prefix});
        self.sql_tab_active = false;
        return;
    }
    const pick = matches.items[self.sql_tab_idx % matches.items.len];
    for (0..self.sql_tab_len) |_| self.sql_in.deleteBeforeCursor();
    try self.sql_in.insertSliceAtCursor(pick);
    self.sql_tab_len = std.unicode.utf8CountCodepoints(pick) catch pick.len;
}

// ------------------------------------------------------------ the target of SQL

pub const SqlTarget = union(enum) { memory, sqlite: []const u8 };

pub fn sqlTarget(self: *const App) App.SqlTarget {
    if (self.sql_db) |d| return if (std.mem.eql(u8, d, ":memory:")) .memory else .{ .sqlite = d };
    if (self.tabs.items.len > 0) {
        const t = self.tabs.items[@min(self.active, self.tabs.items.len - 1)];
        if (t.table != null) {
            if (std.mem.indexOfScalar(u8, t.path, '#')) |h| return .{ .sqlite = t.path[0..h] };
        }
    }
    if (self.selected < self.tree.entries.items.len) {
        const e = self.tree.entries.items[self.selected];
        switch (e.kind) {
            .db => return .{ .sqlite = e.path },
            .table => return .{ .sqlite = e.path[0 .. std.mem.indexOfScalar(u8, e.path, '#') orelse e.path.len] },
            .normal => {},
        }
    }
    return .memory;
}

/// What the SQL panel says about its target.
pub fn sqlTargetText(self: *const App) []const u8 {
    return switch (self.sqlTarget()) {
        .memory => "memory (forgotten after each command)",
        .sqlite => |p| p,
    };
}

// ------------------------------------------------------------ the tree

/// The tree after a file was made: scanned again, the open folders kept.
pub fn refreshTree(self: *App) void {
    var open: std.ArrayList([]u8) = .empty;
    defer {
        for (open.items) |p| self.gpa.free(p);
        open.deinit(self.gpa);
    }
    for (self.tree.entries.items) |e| {
        if (e.is_dir and e.expanded) {
            const copy = self.gpa.dupe(u8, e.path) catch continue;
            open.append(self.gpa, copy) catch self.gpa.free(copy);
        }
    }
    self.tree.scan(self.io, self.root, self.project_name) catch return;
    for (self.tree.entries.items) |*e| {
        for (open.items) |p| {
            if (e.is_dir and std.mem.eql(u8, e.path, p)) e.expanded = true;
        }
    }
}
