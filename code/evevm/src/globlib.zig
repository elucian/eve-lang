//! @eve-module globlib: `fs.glob!(pattern)`, the names that a pattern like `in/*.csv` finds, sorted in the byte order of UTF-8
//! @spec spec/library/data-language.md#files-and-paths
//! @feature F-LIB-04
//! @tests test/level5/e151_fs_glob
//! `*` matches any run of characters and `?` one character, inside one segment of a path; the segments are split by `/`. A pattern without a wildcard names one path, which is given only when it exists.
const std = @import("std");
const Io = std.Io;
const interp = @import("interp.zig");
const Interp = interp.Interp;
const Signal = interp.Signal;

/// True when `name` matches `pattern`, where `*` is any run of bytes and `?` one byte.
pub fn matches(pattern: []const u8, name: []const u8) bool {
    if (pattern.len == 0) return name.len == 0;
    switch (pattern[0]) {
        '*' => {
            var k: usize = 0;
            while (k <= name.len) : (k += 1) {
                if (matches(pattern[1..], name[k..])) return true;
            }
            return false;
        },
        '?' => return name.len > 0 and matches(pattern[1..], name[1..]),
        else => return name.len > 0 and name[0] == pattern[0] and matches(pattern[1..], name[1..]),
    }
}

/// True when a segment of a pattern holds a wildcard.
pub fn hasWildcard(segment: []const u8) bool {
    return std.mem.indexOfAny(u8, segment, "*?") != null;
}

/// The path `base/name`; `base` empty is the working folder.
fn joinPath(it: *Interp, base: []const u8, name: []const u8) Signal![]const u8 {
    if (base.len == 0) return name;
    if (base[base.len - 1] == '/') return std.fmt.allocPrint(it.t, "{s}{s}", .{ base, name });
    return std.fmt.allocPrint(it.t, "{s}/{s}", .{ base, name });
}

/// Collect into `out` the paths of `segments` under `base`; a wildcard segment reads the folder.
fn walk(it: *Interp, io: Io, base: []const u8, segments: []const []const u8, out: *std.ArrayList([]const u8)) Signal!void {
    if (segments.len == 0) {
        try out.append(it.t, base);
        return;
    }
    const seg = segments[0];
    if (!hasWildcard(seg)) {
        const path = try joinPath(it, base, seg);
        if (segments.len == 1) {
            // a plain name is given only when it exists
            std.Io.Dir.cwd().access(io, path, .{}) catch return;
            try out.append(it.t, path);
            return;
        }
        return walk(it, io, path, segments[1..], out);
    }
    const dir_path = if (base.len == 0) "." else base;
    var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch return;
    defer dir.close(io);
    var names: std.ArrayList([]const u8) = .empty;
    var iter = dir.iterate();
    while (iter.next(io) catch null) |entry| {
        if (matches(seg, entry.name)) try names.append(it.t, try it.t.dupe(u8, entry.name));
    }
    std.mem.sort([]const u8, names.items, {}, lessThan);
    for (names.items) |name| {
        const path = try joinPath(it, base, name);
        if (segments.len == 1) {
            try out.append(it.t, path);
        } else {
            try walk(it, io, path, segments[1..], out);
        }
    }
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

// @eve-fn fs.glob!
// @spec spec/library/data-language.md#files-and-paths
// @feature F-LIB-04
// @test test/level5/e151_fs_glob
// @invariant the names are sorted by byte order of UTF-8; a missing folder gives no name, not an error
/// The names that `pattern` finds, as a List of Strings; a folder that does not exist gives an empty List.
pub fn glob(it: *Interp, pattern: []const u8) Signal![]const []const u8 {
    const io = it.io orelse return it.fail("fs.glob!: no input/output handle", .{});
    var segments: std.ArrayList([]const u8) = .empty;
    var parts = std.mem.splitScalar(u8, pattern, '/');
    while (parts.next()) |p| if (p.len > 0) try segments.append(it.t, p);
    var out: std.ArrayList([]const u8) = .empty;
    if (segments.items.len == 0) return out.items;
    const root = if (pattern.len > 0 and pattern[0] == '/') "/" else "";
    try walk(it, io, root, segments.items, &out);
    std.mem.sort([]const u8, out.items, {}, lessThan);
    return out.items;
}

test "spec: data-language.md#files-and-paths a wildcard matches runs of characters inside one name" {
    try std.testing.expect(matches("*.csv", "a.csv"));
    try std.testing.expect(matches("*.csv", ".csv"));
    try std.testing.expect(!matches("*.csv", "a.csv.gz"));
    try std.testing.expect(matches("?.txt", "c.txt"));
    try std.testing.expect(!matches("?.txt", "cc.txt"));
    try std.testing.expect(matches("a*b*c", "aXbYc"));
    try std.testing.expect(!matches("a", ""));
    try std.testing.expect(matches("", ""));
}
