//! @eve-module manifest: the list of files of a bundle and the diff against another list
//! @spec design/components/eveux/design/notes/elaboration.md#5-deployment
//! @feature F-NET-10
//! @decision D-193
//! @tests zig test src/deploy/manifest.zig (from code/eveux/)
//! Pure data: the scanner of the project makes `Entry` values (path, size, SHA-256 in hex); `diff` says what a deploy sends.
//! The machine returns its own manifest (`deploy.plan`), so the same type is read from JSON there.
const std = @import("std");

pub const Entry = struct { path: []const u8, size: u64, sha256: []const u8 };

pub const Change = enum { added, changed, removed, same };

pub const Item = struct { path: []const u8, change: Change, size: u64 };

// @eve-fn diff
/// Compare the files to send (`local`) with the files the target has (`remote`). The result is sorted by path; `same` files
/// are included so the dialog can say "12 files unchanged".
pub fn diff(a: std.mem.Allocator, local: []const Entry, remote: []const Entry) std.mem.Allocator.Error![]const Item {
    var out: std.ArrayList(Item) = .empty;
    var remote_map: std.StringHashMapUnmanaged(Entry) = .empty;
    for (remote) |r| try remote_map.put(a, r.path, r);
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    for (local) |l| {
        try seen.put(a, l.path, {});
        const kind: Change = if (remote_map.get(l.path)) |r|
            (if (std.mem.eql(u8, r.sha256, l.sha256)) .same else .changed)
        else
            .added;
        try out.append(a, .{ .path = l.path, .change = kind, .size = l.size });
    }
    for (remote) |r| if (!seen.contains(r.path)) try out.append(a, .{ .path = r.path, .change = .removed, .size = r.size });
    std.mem.sort(Item, out.items, {}, lessByPath);
    return out.items;
}

fn lessByPath(_: void, x: Item, y: Item) bool {
    return std.mem.lessThan(u8, x.path, y.path);
}

// @eve-fn hashHex
/// The SHA-256 of `bytes` as 64 lower-case hex digits, in memory of `a`.
pub fn hashHex(a: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error![]const u8 {
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const out = try a.alloc(u8, digest.len * 2);
    const hex = "0123456789abcdef";
    for (digest, 0..) |b, i| {
        out[i * 2] = hex[b >> 4];
        out[i * 2 + 1] = hex[b & 15];
    }
    return out;
}

test "added, changed, removed and same" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const local = [_]Entry{
        .{ .path = "server/sales_load.eve", .size = 1200, .sha256 = "bb" },
        .{ .path = "web/app.js", .size = 2100, .sha256 = "cc" },
        .{ .path = "eve.cfg", .size = 90, .sha256 = "aa" },
    };
    const remote = [_]Entry{
        .{ .path = "server/sales_load.eve", .size = 1100, .sha256 = "b0" },
        .{ .path = "eve.cfg", .size = 90, .sha256 = "aa" },
        .{ .path = "web/old.css", .size = 300, .sha256 = "dd" },
    };
    const items = try diff(a, &local, &remote);
    try std.testing.expectEqual(@as(usize, 4), items.len);
    try std.testing.expectEqualStrings("eve.cfg", items[0].path);
    try std.testing.expectEqual(Change.same, items[0].change);
    try std.testing.expectEqual(Change.changed, items[1].change);
    try std.testing.expectEqual(Change.added, items[2].change);
    try std.testing.expectEqual(Change.removed, items[3].change);
}

test "hash of an empty text" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const h = try hashHex(arena.allocator(), "");
    try std.testing.expectEqualStrings("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", h);
}
