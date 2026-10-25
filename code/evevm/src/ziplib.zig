//! @eve-module ziplib: zip archives with deflated entries, no Zip64 (`zip.write`, `zip.list!`, `zip.read!`)
//! @spec spec/library/data-language.md#compression
//! @feature F-LIB-09
//! @tests test/level5/e166_zip
//! Pure byte work: the archive is built and read in memory; dlib.zig does the files and the Eve values.
const std = @import("std");
const flate = std.compress.flate;

pub const Entry = struct { name: []const u8, data: []const u8 };

pub const WriteError = error{ OutOfMemory, TooBig, BadName };
pub const ReadError = error{ OutOfMemory, NotZip, Missing };

const local_sig: u32 = 0x04034b50;
const central_sig: u32 = 0x02014b50;
const end_sig: u32 = 0x06054b50;
const utf8_flag: u16 = 0x0800;
/// 1980-01-01, the first date a zip can hold: the archive has no clock, so equal input gives equal bytes.
const dos_date: u16 = 0x0021;

fn put16(out: *std.ArrayList(u8), gpa: std.mem.Allocator, v: u16) !void {
    try out.appendSlice(gpa, &std.mem.toBytes(std.mem.nativeToLittle(u16, v)));
}

fn put32(out: *std.ArrayList(u8), gpa: std.mem.Allocator, v: u32) !void {
    try out.appendSlice(gpa, &std.mem.toBytes(std.mem.nativeToLittle(u32, v)));
}

fn deflateRaw(gpa: std.mem.Allocator, content: []const u8) error{OutOfMemory}![]u8 {
    var out = std.Io.Writer.Allocating.initCapacity(gpa, content.len / 2 + 64) catch return error.OutOfMemory;
    errdefer out.deinit();
    const window = try gpa.alloc(u8, flate.max_window_len);
    defer gpa.free(window);
    var enc = flate.Compress.init(&out.writer, window, .raw, .default) catch return error.OutOfMemory;
    enc.writer.writeAll(content) catch return error.OutOfMemory;
    enc.finish() catch return error.OutOfMemory;
    return out.toOwnedSlice();
}

fn nameLess(_: void, a: Entry, b: Entry) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}

fn goodName(name: []const u8) bool {
    if (name.len == 0 or name.len > 65535 or name[0] == '/' or std.mem.indexOfScalar(u8, name, '\\') != null) return false;
    var parts = std.mem.splitScalar(u8, name, '/');
    while (parts.next()) |p| if (std.mem.eql(u8, p, "..")) return false;
    return true;
}

// @eve-fn zip.write
// @spec spec/library/data-language.md#compression
/// The archive of `entries`, in the order of their names. An archive over 4 GB or with more than 65,535 entries is `TooBig`.
pub fn write(gpa: std.mem.Allocator, entries: []Entry) WriteError![]u8 {
    if (entries.len > 65535) return error.TooBig;
    std.mem.sort(Entry, entries, {}, nameLess);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    const Info = struct { crc: u32, csize: u32, usize: u32, offset: u32 };
    const infos = try gpa.alloc(Info, entries.len);
    defer gpa.free(infos);
    for (entries, 0..) |e, i| {
        if (!goodName(e.name)) return error.BadName;
        if (e.data.len > std.math.maxInt(u32) or out.items.len > std.math.maxInt(u32)) return error.TooBig;
        const body = try deflateRaw(gpa, e.data);
        defer gpa.free(body);
        if (body.len > std.math.maxInt(u32) or out.items.len + body.len + e.name.len + 30 > std.math.maxInt(u32)) return error.TooBig;
        infos[i] = .{ .crc = std.hash.Crc32.hash(e.data), .csize = @intCast(body.len), .usize = @intCast(e.data.len), .offset = @intCast(out.items.len) };
        try put32(&out, gpa, local_sig);
        try put16(&out, gpa, 20);
        try put16(&out, gpa, utf8_flag);
        try put16(&out, gpa, 8);
        try put16(&out, gpa, 0);
        try put16(&out, gpa, dos_date);
        try put32(&out, gpa, infos[i].crc);
        try put32(&out, gpa, infos[i].csize);
        try put32(&out, gpa, infos[i].usize);
        try put16(&out, gpa, @intCast(e.name.len));
        try put16(&out, gpa, 0);
        try out.appendSlice(gpa, e.name);
        try out.appendSlice(gpa, body);
    }
    const cd_start = out.items.len;
    for (entries, infos) |e, info| {
        try put32(&out, gpa, central_sig);
        try put16(&out, gpa, 20);
        try put16(&out, gpa, 20);
        try put16(&out, gpa, utf8_flag);
        try put16(&out, gpa, 8);
        try put16(&out, gpa, 0);
        try put16(&out, gpa, dos_date);
        try put32(&out, gpa, info.crc);
        try put32(&out, gpa, info.csize);
        try put32(&out, gpa, info.usize);
        try put16(&out, gpa, @intCast(e.name.len));
        try put16(&out, gpa, 0);
        try put16(&out, gpa, 0);
        try put16(&out, gpa, 0);
        try put16(&out, gpa, 0);
        try put32(&out, gpa, 0);
        try put32(&out, gpa, info.offset);
        try out.appendSlice(gpa, e.name);
    }
    const cd_size = out.items.len - cd_start;
    if (out.items.len > std.math.maxInt(u32)) return error.TooBig;
    try put32(&out, gpa, end_sig);
    try put16(&out, gpa, 0);
    try put16(&out, gpa, 0);
    try put16(&out, gpa, @intCast(entries.len));
    try put16(&out, gpa, @intCast(entries.len));
    try put32(&out, gpa, @intCast(cd_size));
    try put32(&out, gpa, @intCast(cd_start));
    try put16(&out, gpa, 0);
    return out.toOwnedSlice(gpa);
}

fn get16(b: []const u8, at: usize) u16 {
    return std.mem.readInt(u16, b[at..][0..2], .little);
}

fn get32(b: []const u8, at: usize) u32 {
    return std.mem.readInt(u32, b[at..][0..4], .little);
}

const Central = struct { name: []const u8, method: u16, csize: u32, usize: u32, crc: u32, offset: u32 };

/// The central directory of an archive: the entries in the order they are stored.
fn directory(gpa: std.mem.Allocator, archive: []const u8) ReadError![]Central {
    if (archive.len < 22) return error.NotZip;
    // the end record is at the end, before a comment of at most 65,535 bytes
    var at: usize = archive.len - 22;
    const lowest = archive.len -| (22 + 65535);
    while (get32(archive, at) != end_sig) : (at -= 1) {
        if (at == lowest) return error.NotZip;
    }
    const count = get16(archive, at + 10);
    const cd_size = get32(archive, at + 12);
    const cd_start = get32(archive, at + 16);
    if (@as(u64, cd_start) + cd_size > archive.len) return error.NotZip;
    const found = try gpa.alloc(Central, count);
    errdefer gpa.free(found);
    var p: usize = cd_start;
    for (found) |*c| {
        if (p + 46 > archive.len or get32(archive, p) != central_sig) return error.NotZip;
        const n = get16(archive, p + 28);
        const extra = get16(archive, p + 30);
        const comment = get16(archive, p + 32);
        if (p + 46 + n > archive.len) return error.NotZip;
        c.* = .{
            .name = archive[p + 46 ..][0..n],
            .method = get16(archive, p + 10),
            .crc = get32(archive, p + 16),
            .csize = get32(archive, p + 20),
            .usize = get32(archive, p + 24),
            .offset = get32(archive, p + 42),
        };
        p += 46 + @as(usize, n) + extra + comment;
    }
    return found;
}

// @eve-fn zip.list!
// @spec spec/library/data-language.md#compression
/// The names of the entries, sorted; they point into `archive`. Free the slice with `gpa`.
pub fn list(gpa: std.mem.Allocator, archive: []const u8) ReadError![][]const u8 {
    const dir = try directory(gpa, archive);
    defer gpa.free(dir);
    const names = try gpa.alloc([]const u8, dir.len);
    for (dir, names) |c, *n| n.* = c.name;
    std.mem.sort([]const u8, names, {}, struct {
        fn less(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.less);
    return names;
}

// @eve-fn zip.read!
// @spec spec/library/data-language.md#compression
/// The content of the entry `name`: `Missing` when there is none, `NotZip` when the archive or the entry is damaged or uses another method than deflate or stored.
pub fn read(gpa: std.mem.Allocator, archive: []const u8, name: []const u8) ReadError![]u8 {
    const dir = try directory(gpa, archive);
    defer gpa.free(dir);
    for (dir) |c| {
        if (!std.mem.eql(u8, c.name, name)) continue;
        const at: usize = c.offset;
        if (at + 30 > archive.len or get32(archive, at) != local_sig) return error.NotZip;
        const start = at + 30 + get16(archive, at + 26) + get16(archive, at + 28);
        if (@as(u64, start) + c.csize > archive.len) return error.NotZip;
        const stored = archive[start..][0..c.csize];
        const content: []u8 = switch (c.method) {
            0 => try gpa.dupe(u8, stored),
            8 => blk: {
                var input: std.Io.Reader = .fixed(stored);
                var dec: flate.Decompress = .init(&input, .raw, &.{});
                break :blk dec.reader.allocRemaining(gpa, .limited(c.usize)) catch |e| switch (e) {
                    error.OutOfMemory => return error.OutOfMemory,
                    else => return error.NotZip,
                };
            },
            else => return error.NotZip,
        };
        errdefer gpa.free(content);
        if (content.len != c.usize or std.hash.Crc32.hash(content) != c.crc) return error.NotZip;
        return content;
    }
    return error.Missing;
}

test "spec: data-language.md#compression an archive lists its sorted names and gives each entry back" {
    const a = std.testing.allocator;
    var entries = [_]Entry{ .{ .name = "b.txt", .data = "second" }, .{ .name = "a/x.bin", .data = "\x00\x01\xff" }, .{ .name = "empty", .data = "" } };
    const archive = try write(a, &entries);
    defer a.free(archive);
    const names = try list(a, archive);
    defer a.free(names);
    try std.testing.expectEqual(@as(usize, 3), names.len);
    try std.testing.expectEqualStrings("a/x.bin", names[0]);
    try std.testing.expectEqualStrings("b.txt", names[1]);
    const got = try read(a, archive, "b.txt");
    defer a.free(got);
    try std.testing.expectEqualStrings("second", got);
    const none = try read(a, archive, "empty");
    defer a.free(none);
    try std.testing.expectEqual(@as(usize, 0), none.len);
    try std.testing.expectError(error.Missing, read(a, archive, "nope"));
    try std.testing.expectError(error.NotZip, list(a, "not a zip file at all, not even close"));
}
