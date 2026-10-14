//! The tree of the files of a project: what the left panel shows.
const std = @import("std");
const Io = std.Io;

// Zig tip: `?u32` is an optional: it holds a `u32` or `null`. `parent` is null for the root. To
// use an optional you unwrap it: `if (e.parent) |p| ...` runs only when it holds a value, and `p`
// is the number inside.
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
};

// Zig tip: a `const` array of slices written at file level is checked and sized by the compiler.
// A folder with one of these names is not shown: they are generated files or other people's code.
const ignored = [_][]const u8{ ".git", ".zig-cache", "zig-out", "zig-pkg", "node_modules", "temp" };

const max_entries = 6000;
const max_depth = 12;

/// The files of a project, scanned once at the start (and again when asked).
pub const Tree = struct {
    // Zig tip: an arena allocator gives out memory that is all freed together, with one call to
    // `deinit`. Every name of the tree lives in it, so no name is freed one by one. An arena must
    // not be copied after it gave out memory, so the `Tree` is created in place (see App.create).
    arena: std.heap.ArenaAllocator,
    entries: std.ArrayList(Entry) = .empty,

    // Zig tip: `.init(gpa)` after a field name has no type in front of it: Zig knows the field is an
    // arena, so `.init` means `ArenaAllocator.init`. The `Tree` is returned by value, which is fine
    // until something is allocated from the arena.
    pub fn init(gpa: std.mem.Allocator) Tree {
        return .{ .arena = .init(gpa) };
    }

    // Zig tip: `deinit` is the usual name of the function that gives resources back. Freeing the arena
    // frees every name of the tree at once; nothing else has to be freed.
    pub fn deinit(self: *Tree) void {
        self.arena.deinit();
    }

    // Zig tip: `!void` is an error union: the function returns nothing, or an error. The caller
    // must handle it with `try` (pass the error up), `catch` (decide here), or `if (...) |_| else |err|`.
    /// Scan the folder `root` (a path from the current folder) and fill `entries`.
    pub fn scan(self: *Tree, io: Io, root: []const u8, root_name: []const u8) !void {
        const a = self.arena.allocator();
        self.entries.clearRetainingCapacity();
        try self.entries.append(a, .{ .name = try a.dupe(u8, root_name), .path = "", .depth = 0, .is_dir = true, .parent = null, .expanded = true });
        var dir = try Io.Dir.cwd().openDir(io, root, .{ .iterate = true });
        defer dir.close(io);
        try self.scanDir(io, dir, "", 1, 0);
    }

    // Zig tip: a function that calls itself cannot have an inferred error set (`!void`), because the
    // compiler would have to know the set before it has read the body. `anyerror!void` says "any
    // error", which is what a recursive function names. It still has to be handled by the caller.
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
        // Zig tip: `std.mem.sort` takes a context value and a `lessThan` function. An anonymous
        // struct holding a function is the usual way to write that function next to its use.
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
            try self.entries.append(a, .{ .name = item.name, .path = path, .depth = depth, .is_dir = item.is_dir, .parent = parent, .expanded = false });
            if (item.is_dir) {
                var sub = dir.openDir(io, item.name, .{ .iterate = true }) catch continue;
                defer sub.close(io);
                try self.scanDir(io, sub, path, depth + 1, index);
            }
        }
    }

    // Zig tip: `self: *const Tree` promises that the function only reads the tree. `out:
    // *std.ArrayList(u32)` is an out parameter: the caller owns the list and this function fills it.
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

    // Zig tip: `while (cur) |p| : (cur = ...)` loops while an optional holds a value; the part after
    // the colon runs after every turn. Here it climbs from a folder to its parent until the root,
    // where the optional is null.
    fn isShown(self: *const Tree, index: u32) bool {
        var cur = self.entries.items[index].parent;
        while (cur) |p| : (cur = self.entries.items[p].parent) {
            if (!self.entries.items[p].expanded) return false;
        }
        return true;
    }

    // Zig tip: `var i = index + 1; while (i < n) : (i += 1)` is a counting loop written with `while`.
    // Because the entries are in depth-first order, the entries after `index` with a bigger depth
    // are its content; the first entry that is not deeper decides if `index` has a younger sibling.
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

    // Zig tip: A function that takes `self: *Tree` (not `*const`) may change the tree. Writing
    // `self.entries.items[p].expanded = true` changes the element in place.
    /// Open every folder above entry `index`, so that the entry is shown.
    pub fn expandTo(self: *Tree, index: u32) void {
        var cur = self.entries.items[index].parent;
        while (cur) |p| : (cur = self.entries.items[p].parent) {
            self.entries.items[p].expanded = true;
        }
    }
};

// Zig tip: `for (ignored) |bad|` visits every element of the array. Slices are compared with
// `std.mem.eql(u8, a, b)`: `==` on slices would compare the pointers, not the letters.
fn isIgnored(name: []const u8) bool {
    for (ignored) |bad| {
        if (std.mem.eql(u8, name, bad)) return true;
    }
    return false;
}
