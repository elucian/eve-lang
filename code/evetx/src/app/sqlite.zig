//! @eve-module evetx.app.sqlite
//! @feature F-TLS-28
//! @decision D-173
//! @see code/evetx/src/app.zig:App
//! SQLite databases in the tree: tables, overview, reading and changing them.
const std = @import("std");
const vaxis = @import("vaxis");
const ide = @import("ide");
const text = ide.text;
const grid = ide.grid;
const App = @import("../app.zig").App;
const types = @import("types.zig");
const Panel = types.Panel;
const TableView = types.TableView;

// ------------------------------------------------------------ SQLite databases in the tree

/// Run `eve <args>` and give back its output (the caller frees it).
pub fn eveText(self: *App, args: []const []const u8) ![]u8 {
    const gpa = self.gpa;
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(gpa);
    try argv.append(gpa, App.eve_exe);
    try argv.appendSlice(gpa, args);
    const cwd: std.process.Child.Cwd = if (self.root.len == 0 or std.mem.eql(u8, self.root, ".")) .inherit else .{ .path = self.root };
    const result = try std.process.run(gpa, self.io, .{ .argv = argv.items, .cwd = cwd });
    defer gpa.free(result.stderr);
    return result.stdout;
}

/// The tables and views of a database entry of the tree are listed (with `eve db sql`) and put under it.
pub fn loadDbTables(self: *App, index: u32) !void {
    const gpa = self.gpa;
    const db_rel = try gpa.dupe(u8, self.tree.entries.items[index].path);
    defer gpa.free(db_rel);
    const out = self.eveText(&.{ "db", "sql", "-t", db_rel, "select name from sqlite_master where type in ('table','view') and name not like 'sqlite_%' and name not like 'eve\\_%' escape '\\' order by name;" }) catch |err| {
        self.setMessage("cannot read {s}: {s}", .{ db_rel, @errorName(err) });
        return;
    };
    defer gpa.free(out);
    if (std.mem.startsWith(u8, out, "error:")) {
        self.setMessage("{s}: {s}", .{ db_rel, std.mem.trim(u8, out, " \r\n") });
        return;
    }
    var names: std.ArrayList([]const u8) = .empty;
    defer names.deinit(gpa);
    var lines = std.mem.splitScalar(u8, out, '\n');
    _ = lines.next(); // the header
    while (lines.next()) |raw| {
        const n = std.mem.trim(u8, raw, " \r");
        if (n.len > 0) try names.append(gpa, n);
    }
    const delta = try self.tree.setTables(index, names.items);
    if (self.selected > index and delta != 0) self.selected = @intCast(@as(isize, @intCast(self.selected)) + delta);
    if (names.items.len == 0) self.setMessage("{s} has no tables", .{db_rel});
}

/// The overview of a SQLite database as a read only grid: one row for each table or view.
pub fn buildDbOverview(self: *App, db_rel: []const u8) !TableView {
    const gpa = self.gpa;
    const sql1 = "select m.name, m.type, (select count(*) from pragma_table_info(m.name)), (select count(*) from pragma_index_list(m.name)) from sqlite_master m where m.type in ('table','view') and m.name not like 'sqlite_%' and m.name not like 'eve\\_%' escape '\\' order by m.name;";
    const list = try self.eveText(&.{ "db", "sql", "-t", db_rel, sql1 });
    defer gpa.free(list);
    if (std.mem.startsWith(u8, list, "error:")) {
        self.setMessage("{s}: {s}", .{ db_rel, std.mem.trim(u8, list, " \r\n") });
        return error.SqlFailed;
    }
    const Row = struct { name: []const u8, kind: []const u8, cols: []const u8, idx: []const u8 };
    var rows: std.ArrayList(Row) = .empty;
    defer rows.deinit(gpa);
    var lines = std.mem.splitScalar(u8, list, '\n');
    _ = lines.next();
    while (lines.next()) |raw| {
        const l = std.mem.trimEnd(u8, raw, "\r");
        if (l.len == 0) continue;
        var f = std.mem.splitScalar(u8, l, '\t');
        try rows.append(gpa, .{ .name = f.next() orelse "", .kind = f.next() orelse "", .cols = f.next() orelse "", .idx = f.next() orelse "" });
    }
    // the number of records of every table, in the order of the tables
    var csql: std.ArrayList(u8) = .empty;
    defer csql.deinit(gpa);
    for (rows.items) |r| {
        if (!std.mem.eql(u8, r.kind, "table")) continue;
        const lit = try App.sqlQuoted(gpa, r.name, '\'');
        defer gpa.free(lit);
        const ident = try App.sqlQuoted(gpa, r.name, '"');
        defer gpa.free(ident);
        const part = try std.fmt.allocPrint(gpa, "{s}select {s}, count(*) from {s}", .{ if (csql.items.len > 0) " union all " else "", lit, ident });
        defer gpa.free(part);
        try csql.appendSlice(gpa, part);
    }
    var counts: []u8 = try gpa.dupe(u8, "");
    defer gpa.free(counts);
    if (csql.items.len > 0) {
        try csql.append(gpa, ';');
        gpa.free(counts);
        counts = try self.eveText(&.{ "db", "sql", "-t", db_rel, csql.items });
    }
    const counts_ok = !std.mem.startsWith(u8, counts, "error:");
    const meta = try self.eveText(&.{ "db", "sql", "-t", db_rel, "select table_name, coalesce(description,''), coalesce(created,''), coalesce(changed,'') from eve_meta;" });
    defer gpa.free(meta);
    const meta_ok = !std.mem.startsWith(u8, meta, "error:");

    var tsv: std.ArrayList(u8) = .empty;
    defer tsv.deinit(gpa);
    try tsv.appendSlice(gpa, "NAME\tTYPE\tCOLS\tROWS\tINDEXES\tCREATED\tCHANGED\tDESCRIPT\n");
    var cl = std.mem.splitScalar(u8, if (counts_ok) counts else "", '\n');
    _ = cl.next();
    for (rows.items) |r| {
        var count: []const u8 = "-";
        if (std.mem.eql(u8, r.kind, "table") and counts_ok) {
            while (cl.next()) |raw| {
                const l = std.mem.trimEnd(u8, raw, "\r");
                if (l.len == 0) continue;
                count = if (std.mem.indexOfScalar(u8, l, '\t')) |tab| l[tab + 1 ..] else "-";
                break;
            }
        }
        var desc: []const u8 = "";
        var created: []const u8 = "-";
        var changed: []const u8 = "-";
        if (meta_ok) {
            var ml = std.mem.splitScalar(u8, meta, '\n');
            _ = ml.next();
            while (ml.next()) |raw| {
                var f = std.mem.splitScalar(u8, std.mem.trimEnd(u8, raw, "\r"), '\t');
                const nm = f.next() orelse continue;
                if (!std.mem.eql(u8, nm, r.name)) continue;
                desc = f.next() orelse "";
                const c1 = f.next() orelse "";
                const c2 = f.next() orelse "";
                if (c1.len > 0) created = c1;
                if (c2.len > 0) changed = c2;
                break;
            }
        }
        const line = try std.fmt.allocPrint(gpa, "{s}\t{s}\t{s}\t{s}\t{s}\t{s}\t{s}\t{s}\n", .{ r.name, r.kind, r.cols, count, if (std.mem.eql(u8, r.kind, "table")) r.idx else "-", created, changed, desc });
        defer gpa.free(line);
        try tsv.appendSlice(gpa, line);
    }
    const t = try grid.fromTsv(gpa, tsv.items);
    return .{ .t = t, .readonly = true };
}

/// Show the tables of the SQLite database `db_rel` in the Main Panel (a window whose path is `db#`).
pub fn showDatabase(self: *App, db_rel: []const u8) !void {
    const gpa = self.gpa;
    var view = self.buildDbOverview(db_rel) catch |err| {
        if (err != error.SqlFailed) self.setMessage("{s}: {s}", .{ db_rel, @errorName(err) });
        return;
    };
    errdefer view.release();
    const key = try std.fmt.allocPrint(gpa, "{s}#", .{db_rel});
    errdefer gpa.free(key);
    for (self.tabs.items, 0..) |t, i| {
        if (!std.mem.eql(u8, t.path, key)) continue;
        const tv = t.table.?;
        view.row = @min(tv.row, view.t.records -| 1);
        tv.release();
        tv.* = view;
        self.active = i;
        self.focus = .editor;
        gpa.free(key);
        return;
    }
    const tv = try gpa.create(TableView);
    errdefer gpa.destroy(tv);
    tv.* = view;
    const label = try std.fmt.allocPrint(gpa, "{s} tables", .{std.fs.path.stem(db_rel)});
    errdefer gpa.free(label);
    try self.tabs.insert(gpa, 0, .{ .path = key, .table = tv, .label = label });
    self.active = 0;
    self.tab_first = 0;
    self.focus = .editor;
}

/// Read the table `table` of the SQLite file `db_rel` into a view (at most 5000 rows).
pub fn readSqliteTable(self: *App, db_rel: []const u8, table: []const u8) !TableView {
    const gpa = self.gpa;
    var editable = true;
    const sql1 = try std.fmt.allocPrint(gpa, "select * from \"{s}\" order by rowid limit 5000;", .{table});
    defer gpa.free(sql1);
    const first = try self.eveText(&.{ "db", "sql", "-t", db_rel, sql1 });
    defer gpa.free(first);
    var plain: ?[]u8 = null;
    defer if (plain) |pl| gpa.free(pl);
    const out: []const u8 = blk: {
        if (!std.mem.startsWith(u8, first, "error:")) break :blk first;
        editable = false;
        const sql2 = try std.fmt.allocPrint(gpa, "select * from \"{s}\" limit 5000;", .{table});
        defer gpa.free(sql2);
        plain = try self.eveText(&.{ "db", "sql", "-t", db_rel, sql2 });
        break :blk plain.?;
    };
    if (std.mem.startsWith(u8, out, "error:")) {
        self.setMessage("{s}#{s}: {s}", .{ db_rel, table, std.mem.trim(u8, out, " \r\n") });
        return error.SqlFailed;
    }
    var t = try grid.fromTsv(gpa, out);
    errdefer t.deinit();
    var names: std.ArrayList([]u8) = .empty;
    errdefer {
        for (names.items) |n| gpa.free(n);
        names.deinit(gpa);
    }
    const head = std.mem.trimEnd(u8, out[0 .. std.mem.indexOfScalar(u8, out, '\n') orelse out.len], "\r");
    var hp = std.mem.splitScalar(u8, head, '\t');
    while (hp.next()) |n| {
        if (names.items.len >= t.fields.len) break;
        try names.append(gpa, try gpa.dupe(u8, n));
    }
    var ids: std.ArrayList(i64) = .empty;
    errdefer ids.deinit(gpa);
    if (editable) {
        const sql3 = try std.fmt.allocPrint(gpa, "select rowid from \"{s}\" order by rowid limit 5000;", .{table});
        defer gpa.free(sql3);
        const idout = try self.eveText(&.{ "db", "sql", "-t", db_rel, sql3 });
        defer gpa.free(idout);
        if (!std.mem.startsWith(u8, idout, "error:")) {
            var lines = std.mem.splitScalar(u8, idout, '\n');
            _ = lines.next();
            while (lines.next()) |raw| {
                const l = std.mem.trim(u8, raw, " \r");
                if (l.len == 0) continue;
                const v = std.fmt.parseInt(i64, l, 10) catch {
                    ids.clearRetainingCapacity();
                    break;
                };
                try ids.append(gpa, v);
            }
        }
        if (ids.items.len != t.records or names.items.len != t.fields.len) {
            editable = false;
            ids.clearRetainingCapacity();
        }
    }
    return .{ .t = t, .readonly = !editable, .colnames = try names.toOwnedSlice(gpa), .rowids = try ids.toOwnedSlice(gpa) };
}

/// Read the table again after a change of the database; the cursor stays where it was.
pub fn reloadSqlite(self: *App, tv: *TableView, db: []const u8, table: []const u8) void {
    var nv = self.readSqliteTable(db, table) catch return;
    nv.row = @min(tv.row, nv.t.records -| 1);
    nv.col = @min(tv.col, nv.t.fields.len -| 1);
    nv.top = tv.top;
    nv.left = tv.left;
    tv.release();
    tv.* = nv;
}

/// The database, the table and the view of the active tab, when it is a table of a SQLite database.
pub fn sqlView(self: *App) ?struct { db: []const u8, table: []const u8, tv: *TableView } {
    const t = self.activeTab() orelse return null;
    const tv = t.table orelse return null;
    if (std.mem.startsWith(u8, t.path, "filter:")) return null;
    const h = std.mem.indexOfScalar(u8, t.path, '#') orelse return null;
    return .{ .db = t.path[0..h], .table = t.path[h + 1 ..], .tv = tv };
}

/// A table was made in a SQLite database: write its row in `eve_meta`.
pub fn metaCreated(self: *App, db: []const u8, table: []const u8, desc: []const u8) void {
    const lit = App.sqlQuoted(self.gpa, table, '\'') catch return;
    defer self.gpa.free(lit);
    const dlit = App.sqlQuoted(self.gpa, desc, '\'') catch return;
    defer self.gpa.free(dlit);
    const sql = std.fmt.allocPrint(self.gpa, "create table if not exists eve_meta (table_name text primary key, description text, created text, changed text); insert into eve_meta (table_name, description, created, changed) values ({s}, {s}, datetime('now'), datetime('now')) on conflict(table_name) do update set description = excluded.description, changed = datetime('now');", .{ lit, dlit }) catch return;
    defer self.gpa.free(sql);
    if (self.eveText(&.{ "db", "sql", db, sql })) |out| self.gpa.free(out) else |_| {}
}

/// The data or the structure of a table of a SQLite database changed: move its `changed` date.
pub fn metaTouch(self: *App, db: []const u8, table: []const u8) void {
    const lit = App.sqlQuoted(self.gpa, table, '\'') catch return;
    defer self.gpa.free(lit);
    const sql = std.fmt.allocPrint(self.gpa, "update eve_meta set changed = datetime('now') where table_name = {s};", .{lit}) catch return;
    defer self.gpa.free(sql);
    if (self.eveText(&.{ "db", "sql", db, sql })) |out| self.gpa.free(out) else |_| {}
}

/// Run a `db` command of the machine (`db sql …`, `db create view …`); a refusal opens the pop-up.
pub fn runDb(self: *App, args: []const []const u8) bool {
    var echo: std.ArrayList(u8) = .empty;
    defer echo.deinit(self.gpa);
    echo.appendSlice(self.gpa, "db") catch return false;
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(self.gpa);
    argv.append(self.gpa, "db") catch return false;
    for (args) |w| {
        echo.append(self.gpa, ' ') catch return false;
        echo.appendSlice(self.gpa, w) catch return false;
        argv.append(self.gpa, w) catch return false;
    }
    self.console.add(self.gpa, echo.items, .input) catch {};
    const out = self.eveText(argv.items) catch |err| {
        self.fail("Cannot run the command: {s}.", .{@errorName(err)});
        return false;
    };
    defer self.gpa.free(out);
    if (std.mem.indexOf(u8, out, "error:") != null) {
        self.fail("{s}", .{std.mem.trim(u8, out, " \r\n")});
        return false;
    }
    return true;
}

/// Run one SQL statement on a database (`db sql <file> <statement>`).
pub fn runSql(self: *App, db: []const u8, sql: []const u8) bool {
    return self.runDb(&.{ "sql", db, sql });
}

pub fn sqlQuoted(a: std.mem.Allocator, s_: []const u8, q: u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    try out.append(a, q);
    for (s_) |c| {
        if (c == q) try out.append(a, q);
        try out.append(a, c);
    }
    try out.append(a, q);
    return out.toOwnedSlice(a);
}

/// Open the table `table` of the SQLite file `db_rel` in the Main Panel.
pub fn openSqliteTable(self: *App, db_rel: []const u8, table: []const u8) !void {
    const gpa = self.gpa;
    const key = try std.fmt.allocPrint(gpa, "{s}#{s}", .{ db_rel, table });
    errdefer gpa.free(key);
    for (self.tabs.items, 0..) |t, i| {
        if (std.mem.eql(u8, t.path, key)) {
            self.active = i;
            self.focus = .editor;
            gpa.free(key);
            return;
        }
    }
    const view = self.readSqliteTable(db_rel, table) catch |err| {
        if (err != error.SqlFailed) self.setMessage("{s}: {s}", .{ key, @errorName(err) });
        gpa.free(key);
        return;
    };
    const tv = try gpa.create(TableView);
    errdefer gpa.destroy(tv);
    tv.* = view;
    const label = try std.fmt.allocPrint(gpa, "{s}.{s}", .{ std.fs.path.stem(db_rel), table });
    errdefer gpa.free(label);
    try self.tabs.insert(gpa, 0, .{ .path = key, .table = tv, .label = label });
    self.active = 0;
    self.tab_first = 0;
    self.focus = .editor;
}
