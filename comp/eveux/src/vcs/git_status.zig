//! @eve-module git_status: the output of `git status --porcelain=v1 -b` as a list of changed files
//! @spec comp/eveux/design/notes/elaboration.md#4-the-local-tier-files-source-control-preferences
//! @feature F-TLS-31
//! @decision D-193
//! @tests zig test src/vcs/git_status.zig (from comp/eveux/)
//! The window never runs git itself: a worker thread runs `git` with an argument list (no shell) in the project folder and
//! gives the text to this parser. Paths are slices of the output.
const std = @import("std");

pub const Change = enum { modified, added, deleted, renamed, untracked, conflicted, other };

pub const File = struct {
    /// The state in the index (staged) and in the working tree, as the two letters of git.
    index: u8,
    tree: u8,
    path: []const u8,

    pub fn staged(self: File) bool {
        return self.index != ' ' and self.index != '?';
    }

    // @eve-fn File.change
    /// The kind of change to show: the working tree wins over the index, `?` is untracked, `U` and both-sides are conflicts.
    pub fn change(self: File) Change {
        if (self.index == '?') return .untracked;
        if (self.index == 'U' or self.tree == 'U' or (self.index == 'A' and self.tree == 'A') or (self.index == 'D' and self.tree == 'D')) return .conflicted;
        const c = if (self.tree != ' ') self.tree else self.index;
        return switch (c) {
            'M' => .modified,
            'A' => .added,
            'D' => .deleted,
            'R' => .renamed,
            else => .other,
        };
    }
};

pub const Status = struct {
    /// The current branch; empty when the output has no branch line.
    branch: []const u8,
    files: []const File,
};

// @eve-fn parse
/// Parse the text of `git status --porcelain=v1 -b`: the first line `## branch...origin/branch [ahead 1]`, then `XY path`.
pub fn parse(a: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error!Status {
    var files: std.ArrayList(File) = .empty;
    var branch: []const u8 = "";
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len < 3) continue;
        if (line[0] == '#' and line[1] == '#') {
            const rest = std.mem.trim(u8, line[2..], " ");
            const end = std.mem.indexOf(u8, rest, "...") orelse std.mem.indexOfScalar(u8, rest, ' ') orelse rest.len;
            branch = rest[0..end];
            continue;
        }
        var path = line[3..];
        if (std.mem.indexOf(u8, path, " -> ")) |arrow| path = path[arrow + 4 ..];
        try files.append(a, .{ .index = line[0], .tree = line[1], .path = path });
    }
    return .{ .branch = branch, .files = files.items };
}

test "branch and changes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const out = "## master...origin/master [ahead 1]\n M server/sales_load.eve\nA  web/app.js\n?? doc/notes.txt\nR  old.eve -> new.eve\nUU lib/money.eve\n";
    const st = try parse(arena.allocator(), out);
    try std.testing.expectEqualStrings("master", st.branch);
    try std.testing.expectEqual(@as(usize, 5), st.files.len);
    try std.testing.expectEqual(Change.modified, st.files[0].change());
    try std.testing.expect(!st.files[0].staged());
    try std.testing.expect(st.files[1].staged());
    try std.testing.expectEqual(Change.untracked, st.files[2].change());
    try std.testing.expectEqualStrings("new.eve", st.files[3].path);
    try std.testing.expectEqual(Change.conflicted, st.files[4].change());
}

test "a repository with no change" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const st = try parse(arena.allocator(), "## dev\n");
    try std.testing.expectEqualStrings("dev", st.branch);
    try std.testing.expectEqual(@as(usize, 0), st.files.len);
}
