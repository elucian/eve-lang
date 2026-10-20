//! @eve-module ide.cache
//! @decision D-193
//! The user cache of evetx: the list of the projects it knows. A project is added when a folder is
//! imported (File > Open Folder) and leaves the list when the user forgets it. Forgetting never
//! touches the files of the project.
//!
//! This is the first form of the cache: a text file `evetx-projects.txt`, one absolute path per line,
//! the project used last first, in the folder `<user data folder>/eve/meta/` where the design
//! (README.md §5) puts `eve.db`. When the `Meta` interface of `evecm` exists the list moves into it.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const Allocator = std.mem.Allocator;

/// The most projects the list keeps; the oldest one goes when a new one comes.
const max_projects = 50;

pub const Cache = struct {
    gpa: Allocator,
    io: Io,
    /// The folder of the cache file (owned); empty when the system gave no user folder, and then
    /// the list lives only while evetx runs.
    dir: []u8,
    /// The absolute paths of the projects, the last used first (every path is owned).
    projects: std.ArrayList([]u8) = .empty,

    // Zig tip: `env.get("NAME")` returns an optional string (`?[]const u8`): null when the variable
    // does not exist. `orelse` chains pick the first variable that is set. `std.fmt.allocPrint`
    // builds the text in memory the caller owns, so `init` hands the folder name to the struct.
    /// Make the cache; the folder is the user data folder of the system (`LOCALAPPDATA` on Windows,
    /// `XDG_DATA_HOME` or `~/.local/share` elsewhere) plus `eve/meta`.
    pub fn init(gpa: Allocator, io: Io, env: *const std.process.Environ.Map) !Cache {
        const base: ?[]const u8 = if (builtin.os.tag == .windows)
            (env.get("LOCALAPPDATA") orelse env.get("APPDATA"))
        else
            env.get("XDG_DATA_HOME");
        const dir: []u8 = if (base) |b|
            try std.fmt.allocPrint(gpa, "{s}/eve/meta", .{b})
        else if (builtin.os.tag != .windows and env.get("HOME") != null)
            try std.fmt.allocPrint(gpa, "{s}/.local/share/eve/meta", .{env.get("HOME").?})
        else
            try gpa.dupe(u8, "");
        return .{ .gpa = gpa, .io = io, .dir = dir };
    }

    // Zig tip: `deinit` gives back what the struct owns: each path, then the list, then the folder.
    pub fn deinit(self: *Cache) void {
        for (self.projects.items) |p| self.gpa.free(p);
        self.projects.deinit(self.gpa);
        self.gpa.free(self.dir);
    }

    // Zig tip: `catch return` ends the function quietly on any error: a missing or unreadable cache
    // file is not a problem, the list is just empty. `std.mem.splitScalar` walks the lines.
    /// Read the list from the file (a missing file is an empty list).
    pub fn load(self: *Cache) void {
        if (self.dir.len == 0) return;
        const path = std.fmt.allocPrint(self.gpa, "{s}/evetx-projects.txt", .{self.dir}) catch return;
        defer self.gpa.free(path);
        const bytes = Io.Dir.cwd().readFileAlloc(self.io, path, self.gpa, .limited(1 << 20)) catch return;
        defer self.gpa.free(bytes);
        var it = std.mem.splitScalar(u8, bytes, '\n');
        while (it.next()) |l| {
            const t = std.mem.trim(u8, l, " \r\t");
            if (t.len == 0 or self.projects.items.len >= max_projects) continue;
            const copy = self.gpa.dupe(u8, t) catch return;
            self.projects.append(self.gpa, copy) catch {
                self.gpa.free(copy);
                return;
            };
        }
    }

    // Zig tip: `std.ArrayList(u8)` used as a string builder: `appendSlice` adds text and `toOwnedSlice`
    // hands the bytes to the caller. `defer out.deinit(gpa)` still runs after it and frees nothing
    // extra, because `toOwnedSlice` left the list empty.
    /// Write the list to the file; creates the folder the first time.
    pub fn save(self: *Cache) !void {
        if (self.dir.len == 0) return;
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(self.gpa);
        for (self.projects.items) |p| {
            try out.appendSlice(self.gpa, p);
            try out.append(self.gpa, '\n');
        }
        try Io.Dir.cwd().createDirPath(self.io, self.dir);
        const path = try std.fmt.allocPrint(self.gpa, "{s}/evetx-projects.txt", .{self.dir});
        defer self.gpa.free(path);
        try Io.Dir.cwd().writeFile(self.io, .{ .sub_path = path, .data = out.items });
    }

    // Zig tip: `?[]u8` is an optional owned slice: null when the file does not exist. The caller
    // frees the bytes. `catch return null` turns any read error into "no file".
    /// The content of a file of the cache folder, or null.
    pub fn readFile(self: *Cache, name: []const u8) ?[]u8 {
        if (self.dir.len == 0) return null;
        const path = std.fmt.allocPrint(self.gpa, "{s}/{s}", .{ self.dir, name }) catch return null;
        defer self.gpa.free(path);
        return Io.Dir.cwd().readFileAlloc(self.io, path, self.gpa, .limited(1 << 20)) catch null;
    }

    /// Write a file of the cache folder (the folder is created the first time).
    pub fn writeFile(self: *Cache, name: []const u8, data: []const u8) !void {
        if (self.dir.len == 0) return;
        try Io.Dir.cwd().createDirPath(self.io, self.dir);
        const path = try std.fmt.allocPrint(self.gpa, "{s}/{s}", .{ self.dir, name });
        defer self.gpa.free(path);
        try Io.Dir.cwd().writeFile(self.io, .{ .sub_path = path, .data = data });
    }

    /// The project of the last session (`project=` in `evetx-session.txt`) when its folder still
    /// exists; the caller frees the path.
    pub fn lastProject(self: *Cache) ?[]u8 {
        const bytes = self.readFile("evetx-session.txt") orelse return null;
        defer self.gpa.free(bytes);
        var it = std.mem.splitScalar(u8, bytes, '\n');
        while (it.next()) |raw| {
            const l = std.mem.trimEnd(u8, raw, "\r");
            if (!std.mem.startsWith(u8, l, "project=")) continue;
            const path = l["project=".len..];
            var d = Io.Dir.cwd().openDir(self.io, path, .{}) catch return null;
            d.close(self.io);
            return self.gpa.dupe(u8, path) catch null;
        }
        return null;
    }

    /// The index of `path` in the list, if it is there (letters of different case count as the same on every system: a project folder is the same folder).
    pub fn find(self: *const Cache, path: []const u8) ?usize {
        for (self.projects.items, 0..) |p, i| {
            if (std.ascii.eqlIgnoreCase(p, path)) return i;
        }
        return null;
    }

    // Zig tip: `orderedRemove` returns the removed item, which the list owned, so the code frees it.
    // `insert(gpa, 0, copy)` puts the new item first and moves the others one place on.
    /// Put `path` first in the list (adding it, or moving it when it is known) and save.
    pub fn add(self: *Cache, path: []const u8) !void {
        if (self.find(path)) |i| self.gpa.free(self.projects.orderedRemove(i));
        const copy = try self.gpa.dupe(u8, path);
        errdefer self.gpa.free(copy);
        try self.projects.insert(self.gpa, 0, copy);
        if (self.projects.items.len > max_projects) self.gpa.free(self.projects.pop().?);
        try self.save();
    }

    /// Take project `index` out of the list and save. The folder and its files stay where they are.
    pub fn forget(self: *Cache, index: usize) !void {
        if (index >= self.projects.items.len) return;
        self.gpa.free(self.projects.orderedRemove(index));
        try self.save();
    }
};
