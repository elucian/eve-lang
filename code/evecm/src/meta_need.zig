//! @eve-module meta_need: the tables of the meta database that a run needs, from the imports of `lib/meta` and the hints `** @meta require(...)` (D-226)
//! @spec spec/library/meta.md#loading-the-tables
//! @feature F-LIB-06
//! @decision D-226
//! @tests test/level5/e157_meta_hints
//! Pure: the compiler reads the hints and the module names, the database layer (metalib.zig) copies the tables named here.
const std = @import("std");

/// The tables of the meta database that a script can use, in the order of their bits.
pub const tables = [_][]const u8{ "zone", "zone_type", "zone_transition", "country", "continent", "meta_info", "zone_kind", "zone_span" };

/// A set of tables of the meta database, one bit per table of `tables`.
pub const Need = struct {
    mask: u16 = 0,

    pub const all: Need = .{ .mask = (1 << tables.len) - 1 };

    pub fn isEmpty(self: Need) bool {
        return self.mask == 0;
    }

    pub fn has(self: Need, index: usize) bool {
        return self.mask & (@as(u16, 1) << @intCast(index)) != 0;
    }

    pub fn merge(a: Need, b: Need) Need {
        return .{ .mask = a.mask | b.mask };
    }
};

/// The index of a table of `tables`, or null for a name that is not one.
pub fn indexOf(name: []const u8) ?usize {
    for (tables, 0..) |t, i| if (std.mem.eql(u8, t, name)) return i;
    return null;
}

/// The tables that a module of `lib/meta` reads (`zone`, `meta`, ...). A module of another folder needs none.
/// The key of a module is its path as the import wrote it (`lib/meta|meta`, `lib/meta/zone`) or its file (`file:…/lib/meta/meta.eve`).
pub fn ofModule(path: []const u8) Need {
    const prefix = "lib/meta";
    const at = std.mem.indexOf(u8, path, prefix) orelse return .{};
    var rest = path[at + prefix.len ..];
    if (rest.len == 0 or (rest[0] != '/' and rest[0] != '|' and rest[0] != '\\')) return .{};
    rest = rest[1..];
    const dot = std.mem.indexOfScalar(u8, rest, '.') orelse rest.len;
    const name = rest[0..dot];
    if (std.mem.eql(u8, name, "zone")) return ofNames(&.{ "zone", "zone_type", "zone_transition", "zone_kind", "zone_span" });
    if (std.mem.eql(u8, name, "meta")) return ofNames(&.{"meta_info"});
    if (std.mem.eql(u8, name, "country")) return ofNames(&.{ "country", "continent" });
    return .{};
}

fn ofNames(names: []const []const u8) Need {
    var n: Need = .{};
    for (names) |name| n.mask |= @as(u16, 1) << @intCast(indexOf(name).?);
    return n;
}

/// Where a hint names a table that does not exist: its line (from 1) and the name.
pub const Bad = struct { line: u32 = 0, name: []const u8 = "" };

/// The tables named by the hints of a script: each line `** @meta require(zone, country)` adds its tables, `require(*)` adds all.
/// A name that is not a table gives `error.UnknownTable` and its place in `bad`.
pub fn ofHints(src: []const u8, bad: *Bad) error{UnknownTable}!Need {
    var need: Need = .{};
    var lines = std.mem.splitScalar(u8, src, '\n');
    var line_no: u32 = 0;
    while (lines.next()) |raw| {
        line_no += 1;
        const line = std.mem.trim(u8, raw, " \t\r");
        if (!std.mem.startsWith(u8, line, "**")) continue;
        const at = std.mem.indexOf(u8, line, "@meta") orelse continue;
        const rest = std.mem.trimStart(u8, line[at + "@meta".len ..], " \t");
        if (!std.mem.startsWith(u8, rest, "require(")) continue;
        const close = std.mem.indexOfScalar(u8, rest, ')') orelse rest.len;
        const list = rest["require(".len..close];
        var names = std.mem.splitScalar(u8, list, ',');
        while (names.next()) |raw_name| {
            const name = std.mem.trim(u8, raw_name, " \t");
            if (name.len == 0) continue;
            if (std.mem.eql(u8, name, "*")) {
                need = need.merge(Need.all);
                continue;
            }
            const index = indexOf(name) orelse {
                bad.* = .{ .line = line_no, .name = name };
                return error.UnknownTable;
            };
            need.mask |= @as(u16, 1) << @intCast(index);
        }
    }
    return need;
}

test "spec: meta.md#loading-the-tables a module of lib/meta needs its tables" {
    const zone = ofModule("lib/meta/zone");
    try std.testing.expect(zone.has(indexOf("zone").?));
    try std.testing.expect(zone.has(indexOf("zone_transition").?));
    try std.testing.expect(!zone.has(indexOf("country").?));
    try std.testing.expect(ofModule("lib/math/basic").isEmpty());
    try std.testing.expect(ofModule("lib/meta/meta").has(indexOf("meta_info").?));
    // the keys of a run: the import as written, and the file of the module
    try std.testing.expect(ofModule("lib/meta|meta").has(indexOf("meta_info").?));
    try std.testing.expect(ofModule("file:C:/work/lib/meta/zone.eve").has(indexOf("zone_transition").?));
    try std.testing.expect(ofModule("lib/metal|zone").isEmpty());
}

test "spec: meta.md#loading-the-tables a hint names tables or all of them" {
    var bad: Bad = .{};
    const some = try ofHints("primary aspect a is\n** @meta require(zone, country)\n", &bad);
    try std.testing.expect(some.has(indexOf("country").?));
    try std.testing.expect(!some.has(indexOf("meta_info").?));
    const everything = try ofHints("** @meta require(*)\n", &bad);
    try std.testing.expectEqual(Need.all.mask, everything.mask);
    try std.testing.expect((try ofHints("print 1;\n", &bad)).isEmpty());
}

test "spec: meta.md#loading-the-tables an unknown table in a hint is refused with its line" {
    var bad: Bad = .{};
    try std.testing.expectError(error.UnknownTable, ofHints("print 1;\n** @meta require(zone, nosuch)\n", &bad));
    try std.testing.expectEqual(@as(u32, 2), bad.line);
    try std.testing.expectEqualStrings("nosuch", bad.name);
}
