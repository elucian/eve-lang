//! @eve-module evetx.app.newfile
//! @feature F-TLS-24
//! @decision D-173
//! @see code/evetx/src/app.zig:App
//! New files, wizards, import, and Save As of a table.
const std = @import("std");
const Io = std.Io;
const vaxis = @import("vaxis");
const Key = vaxis.Key;
const ide = @import("ide");
const project = ide.project;
const text = ide.text;
const App = @import("../app.zig").App;
const types = @import("types.zig");
const TableView = types.TableView;
const NewKind = types.NewKind;
const WizKind = types.WizKind;
const extensionOf = types.extensionOf;

// ------------------------------------------------------------ new files and wizards

/// The folder of the project where a new file goes: the selected folder, or the folder of the selected file.
pub fn targetDir(self: *const App) []const u8 {
    if (self.selected >= self.tree.entries.items.len) return "";
    const e = self.tree.entries.items[self.selected];
    if (e.is_dir) return e.path;
    return std.fs.path.dirname(e.path) orelse "";
}

/// File > New…: ask for the name of the file; the type is read from its extension.
pub fn openNewDialog(self: *App) void {
    self.openNewKind(.file);
}

/// Save As… of a table window: ask for the name of the new table or view.
pub fn openTableSaveAs(self: *App) void {
    const t = self.activeTab() orelse return;
    const tv = t.table orelse return;
    self.new_kind = .table_copy;
    self.saveas_in.clearRetainingCapacity();
    const base = if (std.mem.startsWith(u8, t.path, "filter:") and tv.filter_src.len > 0) tv.filter_src else t.path;
    const stem = if (std.mem.indexOfScalar(u8, base, '#')) |h| base[h + 1 ..] else std.fs.path.stem(base);
    const suffix: []const u8 = if (std.mem.startsWith(u8, t.path, "filter:")) "_view" else "_copy";
    const dflt = std.fmt.allocPrint(self.gpa, "{s}{s}", .{ stem, suffix }) catch return;
    defer self.gpa.free(dflt);
    self.saveas_in.insertSliceAtCursor(dflt) catch {};
    self.overlay = .new_file;
    self.dlg_field = 0;
}

/// The SQL condition of a pattern that is plain text, optionally anchored with ^ and $, as a LIKE; null for any other pattern.
pub fn likeCondition(gpa: std.mem.Allocator, col: []const u8, pat: []const u8) !?[]u8 {
    var body = pat;
    var start = false;
    var end = false;
    if (body.len > 0 and body[0] == '^') {
        start = true;
        body = body[1..];
    }
    if (body.len > 0 and body[body.len - 1] == '$' and (body.len < 2 or body[body.len - 2] != '\\')) {
        end = true;
        body = body[0 .. body.len - 1];
    }
    if (std.mem.indexOfAny(u8, body, ".*+?[](){}|\\^$") != null) return null;
    var lit: std.ArrayList(u8) = .empty;
    defer lit.deinit(gpa);
    try lit.append(gpa, '\'');
    if (!start) try lit.append(gpa, '%');
    for (body) |c| {
        if (c == '%' or c == '_') try lit.append(gpa, '\\');
        if (c == '\'') try lit.append(gpa, '\'');
        try lit.append(gpa, c);
    }
    if (!end) try lit.append(gpa, '%');
    try lit.append(gpa, '\'');
    const id = try App.sqlQuoted(gpa, col, '"');
    defer gpa.free(id);
    return try std.fmt.allocPrint(gpa, "{s} like {s} escape '\\'", .{ id, lit.items });
}

/// The select of the filter window `tv` from the table `tid` (a quoted name): its fields, and a where for the patterns.
pub fn selectSqlFor(self: *App, tid: []const u8, tv: *const TableView, snapshot: *bool) ![]u8 {
    const gpa = self.gpa;
    var cols: std.ArrayList(u8) = .empty;
    defer cols.deinit(gpa);
    var conds: std.ArrayList(u8) = .empty;
    defer conds.deinit(gpa);
    for (tv.filter_rows) |fr| {
        const colname = if (fr.col < tv.colnames.len) tv.colnames[fr.col] else "";
        const id = try App.sqlQuoted(gpa, colname, '"');
        defer gpa.free(id);
        if (cols.items.len > 0) try cols.appendSlice(gpa, ", ");
        try cols.appendSlice(gpa, id);
        if (fr.pat.len == 0 or snapshot.*) continue;
        const cond = (try App.likeCondition(gpa, colname, fr.pat)) orelse {
            snapshot.* = true;
            continue;
        };
        defer gpa.free(cond);
        if (conds.items.len > 0) try conds.appendSlice(gpa, " and ");
        try conds.appendSlice(gpa, cond);
    }
    if (snapshot.*) {
        var ids: std.ArrayList(u8) = .empty;
        defer ids.deinit(gpa);
        for (tv.kept_ids, 0..) |rid, k| {
            var nb: [24]u8 = undefined;
            try ids.appendSlice(gpa, try std.fmt.bufPrint(&nb, "{s}{d}", .{ if (k > 0) "," else "", rid }));
        }
        return std.fmt.allocPrint(gpa, "select {s} from {s} where rowid in ({s})", .{ cols.items, tid, if (ids.items.len == 0) "0" else ids.items });
    }
    if (conds.items.len == 0) return std.fmt.allocPrint(gpa, "select {s} from {s}", .{ cols.items, tid });
    return std.fmt.allocPrint(gpa, "select {s} from {s} where {s}", .{ cols.items, tid, conds.items });
}

/// Alter table on a view: the filter dialog opens with the conditions of the view; Enter makes the view again.
pub fn alterView(self: *App, db: []const u8, view: []const u8, sql_text: []const u8) !void {
    const gpa = self.gpa;
    // the lower case copy is only for finding the keywords; the pieces are cut from the text itself
    const lower = try std.ascii.allocLowerString(gpa, sql_text);
    defer gpa.free(lower);
    const from_at = std.mem.lastIndexOf(u8, lower, " from ") orelse {
        self.setMessage("{s} is not a view that a filter can alter", .{view});
        return;
    };
    const where_at = std.mem.indexOf(u8, lower, " where ");
    var base_text = std.mem.trim(u8, sql_text[from_at + 6 .. where_at orelse sql_text.len], " ;\r\n");
    if (base_text.len > 1 and base_text[0] == '"') {
        const close = std.mem.indexOfScalarPos(u8, base_text, 1, '"') orelse base_text.len;
        base_text = base_text[1..close];
    }
    // the table the view reads has to be open: its window gives the names of the columns
    try self.openSqliteTable(db, base_text);
    const key = try std.fmt.allocPrint(gpa, "{s}#{s}", .{ db, base_text });
    defer gpa.free(key);
    var base_tv: ?*TableView = null;
    for (self.tabs.items) |t| {
        if (t.table != null and std.mem.eql(u8, t.path, key)) base_tv = t.table;
    }
    const btv = base_tv orelse return;
    for (self.flt_rows.items) |r| gpa.free(r.pat);
    self.flt_rows.clearRetainingCapacity();
    if (self.flt_src) |old| gpa.free(old);
    self.flt_src = try gpa.dupe(u8, key);
    if (self.flt_replace) |old| gpa.free(old);
    self.flt_replace = null;
    if (self.flt_view) |old| gpa.free(old);
    self.flt_view = try gpa.dupe(u8, view);
    // the fields of the select are the rows of the dialog (all of them for `*`); the conditions give the patterns
    const sel_at = std.mem.indexOf(u8, lower, "select ");
    if (sel_at) |sa| {
        const list = std.mem.trim(u8, sql_text[sa + 7 .. from_at], " ");
        if (!std.mem.eql(u8, list, "*")) {
            var names = std.mem.splitScalar(u8, list, ',');
            while (names.next()) |raw| {
                const nm = std.mem.trim(u8, raw, " \"");
                for (btv.colnames, 0..) |bn, i| {
                    if (std.mem.eql(u8, bn, nm)) self.filterPush(i, "");
                }
            }
        }
    }
    if (self.flt_rows.items.len == 0) {
        for (0..btv.t.fields.len) |c| self.filterPush(c, "");
    }
    if (where_at) |wa| {
        var parts = std.mem.splitSequence(u8, sql_text[wa + 7 ..], " and ");
        while (parts.next()) |raw| {
            const cond = std.mem.trim(u8, raw, " ;\r\n");
            if (cond.len < 3 or cond[0] != '"') continue;
            const col_end = std.mem.indexOfScalarPos(u8, cond, 1, '"') orelse continue;
            const col_name = cond[1..col_end];
            const like_at = std.mem.indexOf(u8, cond, " like '") orelse continue;
            const lit_start = like_at + 7;
            const lit_end = std.mem.lastIndexOf(u8, cond, "' escape") orelse continue;
            if (lit_end < lit_start) continue;
            var col: usize = 0;
            var found = false;
            for (btv.colnames, 0..) |n, i| {
                if (std.mem.eql(u8, n, col_name)) {
                    col = i;
                    found = true;
                }
            }
            if (!found) continue;
            var lit = cond[lit_start..lit_end];
            var pat: std.ArrayList(u8) = .empty;
            defer pat.deinit(gpa);
            if (lit.len == 0 or lit[0] != '%') try pat.append(gpa, '^') else lit = lit[1..];
            var anchored_end = true;
            if (lit.len > 0 and lit[lit.len - 1] == '%' and (lit.len < 2 or lit[lit.len - 2] != '\\')) {
                anchored_end = false;
                lit = lit[0 .. lit.len - 1];
            }
            var i: usize = 0;
            while (i < lit.len) : (i += 1) {
                if (lit[i] == '\\' and i + 1 < lit.len) i += 1;
                if (lit[i] == '\'' and i + 1 < lit.len and lit[i + 1] == '\'') i += 1;
                try pat.append(gpa, lit[i]);
            }
            if (anchored_end) try pat.append(gpa, '$');
            self.filterSetPat(col, pat.items);
        }
    }
    self.flt_sel = 0;
    self.flt_in.clearRetainingCapacity();
    if (self.flt_rows.items.len > 0) self.flt_in.insertSliceAtCursor(self.flt_rows.items[0].pat) catch {};
    self.openOverlay(.filter);
}

/// Make the table, view or copy that Save As asked for, named `name`.
pub fn tableSaveAs(self: *App, name: []const u8) !void {
    const gpa = self.gpa;
    const t = self.activeTab() orelse return;
    const tv = t.table orelse return;
    const is_filter = std.mem.startsWith(u8, t.path, "filter:");
    const src: []const u8 = if (is_filter) tv.filter_src else t.path;
    if (src.len == 0) return;
    if (std.mem.indexOfScalar(u8, src, '#')) |h| {
        const db = src[0..h];
        const table = src[h + 1 ..];
        if (name.len == 0 or !(std.ascii.isAlphabetic(name[0]) or name[0] == '_')) {
            self.setMessage("a name begins with a letter", .{});
            return;
        }
        for (name) |c| {
            if (!(std.ascii.isAlphanumeric(c) or c == '_')) {
                self.setMessage("a name has letters, digits and _ only", .{});
                return;
            }
        }
        const tid = try App.sqlQuoted(gpa, table, '"');
        defer gpa.free(tid);
        var snapshot = false;
        const sel = if (!is_filter) try std.fmt.allocPrint(gpa, "select * from {s}", .{tid}) else try self.selectSqlFor(tid, tv, &snapshot);
        defer gpa.free(sel);
        if (!self.runDb(&.{ "create", if (is_filter) "view" else "table", db, name, sel })) return;
        self.metaCreated(db, name, "");
        self.refreshDbTables(db) catch {};
        self.setMessage("{s} {s} made in {s}{s}", .{ if (is_filter) "view" else "table", name, db, if (snapshot) " (the pattern is a regular expression: it lists the rows found now)" else "" });
        return;
    }
    self.setMessage("Save As works on a table of a database: {s} is not one", .{src});
}

/// EDIT > Import…: ask for the file (CSV, TXT, JSON, DBF) to load into the selected database as a new table.
pub fn openImport(self: *App) void {
    const db = self.selectedDb() orelse {
        self.setMessage("select a database in the tree first: files are imported into a SQLite database", .{});
        return;
    };
    _ = db;
    self.new_kind = .import_data;
    self.saveas_in.clearRetainingCapacity();
    if (self.selected < self.tree.entries.items.len) {
        const e = self.tree.entries.items[self.selected];
        if (e.kind == .normal and !e.is_dir and App.isImportable(e.path)) self.saveas_in.insertSliceAtCursor(e.path) catch {};
    }
    self.overlay = .new_file;
    self.dlg_field = 0;
}

pub fn isImportable(path: []const u8) bool {
    const ext = extensionOf(path);
    for ([_][]const u8{ "csv", "txt", "tsv", "json", "dbf" }) |x| {
        if (std.ascii.eqlIgnoreCase(ext, x)) return true;
    }
    return false;
}

/// Import the file `rel` into the database selected in the tree.
pub fn importFile(self: *App, rel: []const u8) void {
    const db_sel = self.selectedDb() orelse {
        self.setMessage("select a database in the tree first", .{});
        return;
    };
    const gpa = self.gpa;
    const db = gpa.dupe(u8, db_sel) catch return;
    defer gpa.free(db);
    if (!App.isImportable(rel)) {
        self.fail("{s}: the formats are CSV, TXT, JSON and DBF. Save a spreadsheet (XLS) as CSV first.", .{rel});
        return;
    }
    if (!self.runDb(&.{ "import", db, rel })) return;
    const stem = gpa.dupe(u8, std.fs.path.stem(rel)) catch return;
    defer gpa.free(stem);
    for (stem) |*ch| {
        if (!std.ascii.isAlphanumeric(ch.*)) ch.* = '_';
    }
    const note = std.fmt.allocPrint(gpa, "imported from {s}", .{rel}) catch return;
    defer gpa.free(note);
    self.metaCreated(db, stem, note);
    self.refreshDbTables(db) catch {};
    self.setMessage("{s} imported into {s} as the table {s}", .{ rel, db, stem });
}

/// File > New file…, New folder…, New database…: ask for the name; `kind` says what is made.
pub fn openNewKind(self: *App, kind: NewKind) void {
    self.new_kind = kind;
    self.saveas_in.clearRetainingCapacity();
    self.openOverlay(.new_file);
}

/// The path in the project of a file `name` made in the target folder.
pub fn pathInTarget(self: *App, name: []const u8) ![]u8 {
    const dir = self.targetDir();
    if (dir.len == 0) return self.gpa.dupe(u8, name);
    return std.fmt.allocPrint(self.gpa, "{s}/{s}", .{ dir, name });
}

/// The name was typed in the New dialog: make the file in the target folder, with the wizard of its type.
pub fn newFromName(self: *App) !void {
    const raw = try self.saveas_in.toOwnedContents(self.gpa);
    defer self.gpa.free(raw);
    const name = std.mem.trim(u8, raw, " /\\");
    if (name.len == 0) return;
    if (self.new_kind == .table_copy) {
        self.overlay = .none;
        return self.tableSaveAs(name);
    }
    if (self.new_kind == .import_data) {
        self.overlay = .none;
        return self.importFile(name);
    }
    self.overlay = .none;
    const rel = try self.pathInTarget(name);
    defer self.gpa.free(rel);
    const full = try self.fullPath(rel);
    defer self.gpa.free(full);
    if (self.new_kind == .folder) {
        if (Io.Dir.cwd().statFile(self.io, full, .{})) |_| {
            self.setMessage("{s} exists already", .{rel});
            return;
        } else |_| {}
        Io.Dir.cwd().createDirPath(self.io, full) catch |err| {
            self.setMessage("cannot make the folder {s}: {s}", .{ rel, @errorName(err) });
            return;
        };
        self.refreshTree();
        self.setMessage("made the folder {s}", .{rel});
        return;
    }
    if (self.new_kind == .database) {
        // a name without an extension gets .db
        const db_rel = if (extensionOf(rel).len > 0) try self.gpa.dupe(u8, rel) else try std.fmt.allocPrint(self.gpa, "{s}.db", .{rel});
        defer self.gpa.free(db_rel);
        const db_full = try self.fullPath(db_rel);
        defer self.gpa.free(db_full);
        if (Io.Dir.cwd().statFile(self.io, db_full, .{})) |_| {
            self.setMessage("{s} exists already", .{db_rel});
            return;
        } else |_| {}
        return self.createSqlite(db_rel, db_full);
    }
    if (Io.Dir.cwd().statFile(self.io, full, .{})) |_| {
        self.setMessage("{s} exists already", .{rel});
        return;
    } else |_| {}
    var ext_buf: [16]u8 = undefined;
    const ext = std.ascii.lowerString(&ext_buf, extensionOf(rel)[0..@min(extensionOf(rel).len, ext_buf.len)]);
    if (std.mem.eql(u8, ext, "dbf")) {
        self.setMessage("DBF files are not made here: import them into a database (EDIT > Import)", .{});
        return;
    }
    if (std.mem.eql(u8, ext, "eve")) return self.openWizard(.eve, rel);
    if (std.mem.eql(u8, ext, "sql")) return self.openWizard(.sql, rel);
    if (std.mem.eql(u8, ext, "db") or std.mem.eql(u8, ext, "sqlite") or std.mem.eql(u8, ext, "sqlite3")) return self.createSqlite(rel, full);
    const stem = std.fs.path.stem(rel);
    const body = if (std.mem.eql(u8, ext, "md")) try std.fmt.allocPrint(self.gpa, "# {s}\n", .{stem}) else if (std.mem.eql(u8, ext, "json")) try self.gpa.dupe(u8, "{}\n") else try self.gpa.dupe(u8, "");
    defer self.gpa.free(body);
    try self.writeNew(rel, full, body);
}

/// Write a new text file, show it in the tree and open it.
pub fn writeNew(self: *App, rel: []const u8, full: []const u8, body: []const u8) !void {
    Io.Dir.cwd().writeFile(self.io, .{ .sub_path = full, .data = body }) catch |err| {
        self.setMessage("cannot make {s}: {s}", .{ rel, @errorName(err) });
        return;
    };
    self.refreshTree();
    try self.openFile(rel);
    self.setMessage("made {s}", .{rel});
}

/// A new SQLite database: `eve db sql` opens the file and writes its header.
pub fn createSqlite(self: *App, rel: []const u8, full: []const u8) !void {
    // eve_meta keeps what SQLite does not: the description, the creation and the last change of every table. Its name
    // starts with eve_, and evetx does not list the tables with that start.
    const argv = [_][]const u8{ App.eve_exe, "db", "sql", full, "pragma user_version = 1; create table if not exists eve_meta (table_name text primary key, description text, created text, changed text);" };
    const result = std.process.run(self.gpa, self.io, .{ .argv = &argv }) catch |err| {
        self.setMessage("cannot make {s}: {s}", .{ rel, @errorName(err) });
        return;
    };
    defer self.gpa.free(result.stdout);
    defer self.gpa.free(result.stderr);
    self.refreshTree();
    try self.openFile(rel);
    self.setMessage("made the SQLite database {s}", .{rel});
}

pub fn openWizard(self: *App, kind: WizKind, rel: []const u8) !void {
    if (self.wiz_path) |old| self.gpa.free(old);
    self.wiz_path = try self.gpa.dupe(u8, rel);
    self.wiz_kind = kind;
    self.wiz_choice = 0;
    self.wiz_name.clearRetainingCapacity();
    try self.wiz_name.insertSliceAtCursor(std.fs.path.stem(rel));
    self.openOverlay(.wizard);
}

/// The choices of the wizard of a kind of file, as the list shows them.
pub fn wizardChoices(kind: WizKind) []const []const u8 {
    return switch (kind) {
        .eve => &.{ "Primary aspect: a program with a main process", "Aspect: called with `apply`, takes arguments", "Module: functions and procedures to import" },
        .sql => &.{ "Empty script", "Create table", "Select", "Insert" },
    };
}

pub fn wizardKey(self: *App, key: Key) !void {
    const n = App.wizardChoices(self.wiz_kind).len;
    if (key.matches(Key.up, .{})) {
        self.wiz_choice = (self.wiz_choice + n - 1) % n;
    } else if (key.matches(Key.down, .{})) {
        self.wiz_choice = (self.wiz_choice + 1) % n;
    } else if (key.matches(Key.enter, .{})) {
        try self.wizardCreate();
    } else try self.wiz_name.update(.{ .key_press = key });
}

/// Create the file of the wizard with the text of the choice made.
pub fn wizardCreate(self: *App) !void {
    const rel = self.wiz_path orelse return;
    const raw = try self.wiz_name.toOwnedContents(self.gpa);
    defer self.gpa.free(raw);
    var name = std.mem.trim(u8, raw, " ");
    if (name.len == 0) name = std.fs.path.stem(rel);
    const gpa = self.gpa;
    const body = switch (self.wiz_kind) {
        .eve => switch (self.wiz_choice) {
            0 => try std.fmt.allocPrint(gpa, "# {s}: a program\nprimary aspect {s} is\n  process main is\n    print \"Hello from {s}\";\n  return;\nend {s};\n", .{ name, name, name, name }),
            1 => try std.fmt.allocPrint(gpa, "# {s}: an aspect, called with: apply {s}(\"Eve\");\nexclusive aspect {s} is\n  process main(who: String) is\n    print \"Hello, {{who}}!\";\n  return;\nend {s};\n", .{ name, name, name, name }),
            else => try std.fmt.allocPrint(gpa, "# {s}: a module, imported with: from lib use ({s});\nmodule {s} is\n  export (hello);\n\n  procedure hello() is\n    print \"Hello from {s}\";\n  return;\nend {s};\n", .{ name, name, name, name, name }),
        },
        .sql => switch (self.wiz_choice) {
            0 => try std.fmt.allocPrint(gpa, "-- {s}\n", .{name}),
            1 => try std.fmt.allocPrint(gpa, "-- {s}\ncreate table {s} (\n  id integer primary key,\n  name text not null\n);\n", .{ name, name }),
            2 => try std.fmt.allocPrint(gpa, "-- {s}\nselect *\nfrom {s}\nwhere 1 = 1\norder by 1;\n", .{ name, name }),
            else => try std.fmt.allocPrint(gpa, "-- {s}\ninsert into {s} (id, name)\nvalues (1, 'first');\n", .{ name, name }),
        },
    };
    defer gpa.free(body);
    const full = try self.fullPath(rel);
    defer gpa.free(full);
    self.overlay = .none;
    const path = try gpa.dupe(u8, rel);
    defer gpa.free(path);
    try self.writeNew(path, full, body);
}

pub fn readonlyMessage(self: *App) void {
    self.setMessage("this table is read only here: change it with SQL or its structure", .{});
}

/// DATA > Structure…: the dialog of the fields of the table that is open.
pub fn dataStructure(self: *App) !void {
    const t = self.activeTab() orelse return;
    if (t.table == null) {
        self.setMessage("Structure works on a table of a database: open one", .{});
        return;
    }
    // a filter window is altered with the filter dialog; so is a view of a database
    if (std.mem.startsWith(u8, t.path, "filter:")) return self.openFilter();
    const path = t.path;
    if (std.mem.indexOfScalar(u8, path, '#')) |h| {
        if (h + 1 >= path.len) {
            self.setMessage("open a table of the list (Enter), then its structure", .{});
            return;
        }
        const db = try self.gpa.dupe(u8, path[0..h]);
        defer self.gpa.free(db);
        const name = try self.gpa.dupe(u8, path[h + 1 ..]);
        defer self.gpa.free(name);
        const lit = try App.sqlQuoted(self.gpa, name, '\'');
        defer self.gpa.free(lit);
        const ask = try std.fmt.allocPrint(self.gpa, "select type, sql from sqlite_master where name = {s};", .{lit});
        defer self.gpa.free(ask);
        const out = try self.eveText(&.{ "db", "sql", "-t", db, ask });
        defer self.gpa.free(out);
        const body = if (std.mem.indexOfScalar(u8, out, '\n')) |nl| out[nl + 1 ..] else "";
        if (std.mem.startsWith(u8, body, "view\t")) return self.alterView(db, name, std.mem.trim(u8, body[5..], " \r\n"));
        return self.openSqStructure(db, name);
    }
}
