//! @eve-module ide.project
//! @decision D-193
//! The tree of the files of a project: what the left panel shows.
const std = @import("std");
const Io = std.Io;

/// What an entry is besides a file or a folder.
pub const Kind = enum { normal, db, table };

/// One file or folder. The entries are kept in depth-first order (a folder, then its content),
/// so the entries below a folder are the ones that follow it with a bigger `depth`.
pub const Entry = struct {
    name: []const u8,
    /// The path relative to the project folder, with `/`; empty for the root.
    path: []const u8,
    depth: u16,
    is_dir: bool,
    /// Index of the folder that holds this entry; null for the root.
    parent: ?u32,
    expanded: bool,
    kind: Kind = .normal,
};

/// Does the name end like a SQLite database file?
pub fn isSqliteName(name: []const u8) bool {
    for ([_][]const u8{ ".db", ".sqlite", ".sqlite3" }) |ext| {
        if (name.len > ext.len and std.ascii.eqlIgnoreCase(name[name.len - ext.len ..], ext)) return true;
    }
    return false;
}

const ignored = [_][]const u8{ ".git", ".zig-cache", "zig-out", "zig-pkg", "node_modules", "temp" };

const max_entries = 6000;
const max_depth = 12;

/// The files of a project, scanned once at the start (and again when asked).
pub const Tree = struct {
    arena: std.heap.ArenaAllocator,
    entries: std.ArrayList(Entry) = .empty,

    pub fn init(gpa: std.mem.Allocator) Tree {
        return .{ .arena = .init(gpa) };
    }

    pub fn deinit(self: *Tree) void {
        self.arena.deinit();
    }

    /// Scan the folder `root` (a path from the current folder) and fill `entries`.
    pub fn scan(self: *Tree, io: Io, root: []const u8, root_name: []const u8) !void {
        const a = self.arena.allocator();
        self.entries.clearRetainingCapacity();
        try self.entries.append(a, .{ .name = try a.dupe(u8, root_name), .path = "", .depth = 0, .is_dir = true, .parent = null, .expanded = true });
        var dir = try Io.Dir.cwd().openDir(io, root, .{ .iterate = true });
        defer dir.close(io);
        try self.scanDir(io, dir, "", 1, 0);
    }

    fn scanDir(self: *Tree, io: Io, dir: Io.Dir, rel: []const u8, depth: u16, parent: u32) anyerror!void {
        if (depth > max_depth) return;
        const a = self.arena.allocator();

        const Item = struct { name: []const u8, is_dir: bool };
        var items: std.ArrayList(Item) = .empty;
        defer items.deinit(a);

        var it = dir.iterate();
        while (try it.next(io)) |e| {
            const is_dir = e.kind == .directory;
            if (!is_dir and e.kind != .file) continue;
            if (is_dir and isIgnored(e.name)) continue;
            try items.append(a, .{ .name = try a.dupe(u8, e.name), .is_dir = is_dir });
        }
        std.mem.sort(Item, items.items, {}, struct {
            fn less(_: void, x: Item, y: Item) bool {
                if (x.is_dir != y.is_dir) return x.is_dir;
                return std.ascii.lessThanIgnoreCase(x.name, y.name);
            }
        }.less);

        for (items.items) |item| {
            if (self.entries.items.len >= max_entries) return;
            const path = if (rel.len == 0) item.name else try std.fmt.allocPrint(a, "{s}/{s}", .{ rel, item.name });
            const index: u32 = @intCast(self.entries.items.len);
            const kind: Kind = if (!item.is_dir and isSqliteName(item.name)) .db else .normal;
            try self.entries.append(a, .{ .name = item.name, .path = path, .depth = depth, .is_dir = item.is_dir, .parent = parent, .expanded = false, .kind = kind });
            if (item.is_dir) {
                var sub = dir.openDir(io, item.name, .{ .iterate = true }) catch continue;
                defer sub.close(io);
                try self.scanDir(io, sub, path, depth + 1, index);
            }
        }
    }

    /// Fill `out` with the indices of the rows that the panel shows: an entry is shown when every
    /// folder above it is open.
    pub fn visibleRows(self: *const Tree, gpa: std.mem.Allocator, out: *std.ArrayList(u32)) !void {
        out.clearRetainingCapacity();
        for (self.entries.items, 0..) |e, i| {
            if (e.parent) |p| {
                if (!self.entries.items[p].expanded or !self.isShown(p)) continue;
            }
            try out.append(gpa, @intCast(i));
        }
    }

    fn isShown(self: *const Tree, index: u32) bool {
        var cur = self.entries.items[index].parent;
        while (cur) |p| : (cur = self.entries.items[p].parent) {
            if (!self.entries.items[p].expanded) return false;
        }
        return true;
    }

    /// True when no entry after `index` has the same parent: the tree draws `└─` for it and not `├─`.
    pub fn isLast(self: *const Tree, index: u32) bool {
        const depth = self.entries.items[index].depth;
        var i: usize = index + 1;
        while (i < self.entries.items.len) : (i += 1) {
            const d = self.entries.items[i].depth;
            if (d == depth) return false;
            if (d < depth) return true;
        }
        return true;
    }

    /// Put the tables of the database entry `index` in the tree. Returns how many entries the list grew by (it may be negative).
    pub fn setTables(self: *Tree, index: u32, names: []const []const u8) !isize {
        const a = self.arena.allocator();
        const db = self.entries.items[index];
        var old: usize = 0;
        while (index + 1 + old < self.entries.items.len and self.entries.items[index + 1 + old].kind == .table and self.entries.items[index + 1 + old].parent == index) old += 1;
        const fresh = try a.alloc(Entry, names.len);
        for (names, 0..) |n, i| {
            fresh[i] = .{
                .name = try a.dupe(u8, n),
                .path = try std.fmt.allocPrint(a, "{s}#{s}", .{ db.path, n }),
                .depth = db.depth + 1,
                .is_dir = false,
                .parent = index,
                .expanded = false,
                .kind = .table,
            };
        }
        try self.entries.replaceRange(a, index + 1, old, fresh);
        const delta: isize = @as(isize, @intCast(names.len)) - @as(isize, @intCast(old));
        for (self.entries.items[index + 1 + names.len ..]) |*e| {
            if (e.parent) |p| {
                if (p > index) e.parent = @intCast(@as(isize, @intCast(p)) + delta);
            }
        }
        return delta;
    }

    /// Open every folder above entry `index`, so that the entry is shown.
    pub fn expandTo(self: *Tree, index: u32) void {
        var cur = self.entries.items[index].parent;
        while (cur) |p| : (cur = self.entries.items[p].parent) {
            self.entries.items[p].expanded = true;
        }
    }
};

fn isIgnored(name: []const u8) bool {
    for (ignored) |bad| {
        if (std.mem.eql(u8, name, bad)) return true;
    }
    return false;
}
