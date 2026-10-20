//! @eve-module evetx.app.search
//! @feature F-TLS-24
//! @decision D-173
//! @see code/evetx/src/app.zig:App
//! The two searches (names, text), replace and go to line.
const std = @import("std");
const vaxis = @import("vaxis");
const ide = @import("ide");
const App = @import("../app.zig").App;

// ------------------------------------------------------------ the two searches

/// The Files search: the tree goes to the first name that starts with the typed letters and opens the way to it.
pub fn filesChanged(self: *App) !void {
    const q = try self.files_in.toOwnedContents(self.gpa);
    defer self.gpa.free(q);
    if (q.len == 0) {
        self.filesRestore();
        return;
    }
    if (self.saved_open == null) {
        const snap = try self.gpa.alloc(bool, self.tree.entries.items.len);
        for (self.tree.entries.items, 0..) |e, i| snap[i] = e.expanded;
        self.saved_open = snap;
    }
    if (self.nextMatch(q, 0, 1)) |i| self.selectEntry(i);
}

/// The first entry at or after `from` (going `step` entries at a time, wrapping) whose name starts with `q`.
pub fn nextMatch(self: *App, q: []const u8, from: usize, step: isize) ?u32 {
    const n: isize = @intCast(self.tree.entries.items.len);
    var i: isize = @intCast(from);
    var k: isize = 0;
    while (k < n) : (k += 1) {
        const idx: usize = @intCast(@mod(i, n));
        const e = self.tree.entries.items[idx];
        if (e.parent != null and e.name.len >= q.len and std.ascii.eqlIgnoreCase(e.name[0..q.len], q)) return @intCast(idx);
        i += step;
    }
    return null;
}

pub fn selectEntry(self: *App, i: u32) void {
    self.tree_follow = true;
    self.tree.expandTo(i);
    self.selected = i;
}

pub fn filesStep(self: *App, step: isize) !void {
    const q = try self.files_in.toOwnedContents(self.gpa);
    defer self.gpa.free(q);
    if (q.len == 0 or self.tree.entries.items.len == 0) return;
    const from: isize = @as(isize, @intCast(self.selected)) + step;
    if (self.nextMatch(q, @intCast(@mod(from, @as(isize, @intCast(self.tree.entries.items.len)))), step)) |i| self.selectEntry(i);
}

pub fn filesRestore(self: *App) void {
    if (self.saved_open) |snap| {
        for (self.tree.entries.items, 0..) |*e, i| {
            if (i < snap.len) e.expanded = snap[i];
        }
        self.gpa.free(snap);
        self.saved_open = null;
    }
}

pub fn filesCancel(self: *App) void {
    self.filesRestore();
    self.files_in.clearRetainingCapacity();
    self.focus = .tree;
}

pub fn findNext(self: *App) !void {
    const b = self.activeBuffer() orelse return;
    const q = try self.find_in.toOwnedContents(self.gpa);
    defer self.gpa.free(q);
    if (!b.findNext(q)) self.setMessage("not found: {s}", .{q});
}

pub fn replaceOne(self: *App) !void {
    const b = self.activeBuffer() orelse return;
    if (self.activeTab().?.virtual) return self.setMessage("a read-only window cannot be changed", .{});
    const q = try self.find_in.toOwnedContents(self.gpa);
    defer self.gpa.free(q);
    const w = try self.replace_in.toOwnedContents(self.gpa);
    defer self.gpa.free(w);
    try b.checkpoint(.other);
    if (!try b.replaceMatch(q, w)) self.setMessage("no more matches", .{});
}

pub fn replaceEvery(self: *App) !void {
    const b = self.activeBuffer() orelse return;
    if (self.activeTab().?.virtual) return self.setMessage("a read-only window cannot be changed", .{});
    const q = try self.find_in.toOwnedContents(self.gpa);
    defer self.gpa.free(q);
    const w = try self.replace_in.toOwnedContents(self.gpa);
    defer self.gpa.free(w);
    try b.checkpoint(.other);
    const n = try b.replaceAll(q, w);
    self.setMessage("{d} replaced", .{n});
}

/// The `#` prompt: `42` or `42:7` goes to a line (and a column).
pub fn gotoEnter(self: *App) !void {
    const s = try self.goto_in.toOwnedContents(self.gpa);
    defer self.gpa.free(s);
    self.goto_in.clearRetainingCapacity();
    self.overlay = .none;
    const b = self.activeBuffer() orelse {
        self.setMessage("# works in an editor (records of a table come with step T7)", .{});
        return;
    };
    const t = std.mem.trim(u8, s, " ");
    const colon = std.mem.indexOfScalar(u8, t, ':');
    const line = std.fmt.parseInt(usize, if (colon) |c| t[0..c] else t, 10) catch {
        self.setMessage("not a line number: {s}", .{t});
        return;
    };
    const col = if (colon) |c| std.fmt.parseInt(usize, t[c + 1 ..], 10) catch 0 else 0;
    b.gotoLine(line, col);
    self.focus = .editor;
}
