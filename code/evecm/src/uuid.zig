//! @eve-module uuid: the 128-bit identifier behind the type Uuid (parse, canonical text, versions 3, 4, 5 and 7)
//! @spec spec/library/bytes.md#uuid
//! @feature F-LNG-13
//! @decision D-221
//! @tests test/level5/e142_uuid_basics, test/level5/e143_uuid_errors, test/level5/e144_uuid_v7_time
//! A Uuid is 16 bytes (RFC 9562), held in the value itself: the functions here are pure and take the random bytes and the clock from the caller.
const std = @import("std");
const Io = std.Io;
const Md5 = std.crypto.hash.Md5;
const Sha1 = std.crypto.hash.Sha1;

pub const Bytes16 = [16]u8;

/// The hyphen positions of the canonical text: 8-4-4-4-12 digits.
const hyphens = [_]usize{ 8, 13, 18, 23 };

/// The value of one hexadecimal digit, or null when `c` is not one.
fn nibble(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}

// @eve-fn Uuid.parse
// @spec spec/library/bytes.md#uuid
// @feature F-LNG-13
// @test test/level5/e142_uuid_basics
// @test test/level5/e143_uuid_errors
/// The 16 bytes of a Uuid text: 32 hexadecimal digits, or 36 with the hyphens in the canonical places, in any case and optionally in braces; null for any other text.
pub fn parse(text_in: []const u8) ?Bytes16 {
    var text = text_in;
    if (text.len >= 2 and text[0] == '{' and text[text.len - 1] == '}') text = text[1 .. text.len - 1];
    var digits: [32]u8 = undefined;
    if (text.len == 36) {
        var k: usize = 0;
        for (text, 0..) |c, i| {
            if (std.mem.indexOfScalar(usize, &hyphens, i) != null) {
                if (c != '-') return null;
                continue;
            }
            if (nibble(c) == null) return null;
            digits[k] = c;
            k += 1;
        }
    } else if (text.len == 32) {
        for (text, 0..) |c, i| {
            if (nibble(c) == null) return null;
            digits[i] = c;
        }
    } else return null;
    var out: Bytes16 = undefined;
    for (&out, 0..) |*b, i| b.* = nibble(digits[2 * i]).? * 16 + nibble(digits[2 * i + 1]).?;
    return out;
}

// @eve-impl the canonical text of a Uuid: lower-case digits in 8-4-4-4-12 groups
// @spec spec/library/bytes.md#uuid
// @feature F-LNG-13
// @test test/level5/e142_uuid_basics
/// The canonical text of `u`: `550e8400-e29b-41d4-a716-446655440000`.
pub fn write(w: *Io.Writer, u: Bytes16) Io.Writer.Error!void {
    for (u, 0..) |b, i| {
        if (i == 4 or i == 6 or i == 8 or i == 10) try w.writeByte('-');
        try w.print("{x:0>2}", .{b});
    }
}

/// The version of `u`: the high nibble of byte 7 (RFC 9562); 0 for the nil Uuid.
pub fn version(u: Bytes16) u8 {
    return u[6] >> 4;
}

/// The Unix time in microseconds that a version 7 Uuid carries (its first 48 bits are milliseconds, big-endian).
pub fn timeOf7(u: Bytes16) i64 {
    var ms: i64 = 0;
    for (u[0..6]) |b| ms = ms * 256 + b;
    return ms * 1000;
}

/// Set the version and the RFC 9562 variant (`10` in the top bits of byte 9).
fn stamp(out: *Bytes16, ver: u8) void {
    out[6] = (out[6] & 0x0f) | (ver << 4);
    out[8] = (out[8] & 0x3f) | 0x80;
}

/// A version 4 Uuid from 16 random bytes (the caller draws them from the system generator).
pub fn v4(random: Bytes16) Bytes16 {
    var out = random;
    stamp(&out, 4);
    return out;
}

/// A version 7 Uuid: the milliseconds of the clock, then random bits; a later time sorts later as bytes.
pub fn v7(ms: u64, random: Bytes16) Bytes16 {
    var out = random;
    var k: usize = 6;
    while (k > 0) : (k -= 1) {
        out[k - 1] = @truncate(ms >> @intCast(8 * (6 - k)));
    }
    stamp(&out, 7);
    return out;
}

/// A version 3 Uuid (MD5) of `name` in the namespace `ns`.
pub fn v3(ns: Bytes16, name: []const u8) Bytes16 {
    var h = Md5.init(.{});
    h.update(&ns);
    h.update(name);
    var digest: [Md5.digest_length]u8 = undefined;
    h.final(&digest);
    var out: Bytes16 = digest[0..16].*;
    stamp(&out, 3);
    return out;
}

/// A version 5 Uuid (SHA-1, the first 16 bytes of the digest) of `name` in the namespace `ns`.
pub fn v5(ns: Bytes16, name: []const u8) Bytes16 {
    var h = Sha1.init(.{});
    h.update(&ns);
    h.update(name);
    var digest: [Sha1.digest_length]u8 = undefined;
    h.final(&digest);
    var out: Bytes16 = digest[0..16].*;
    stamp(&out, 5);
    return out;
}

test "spec: bytes.md#uuid parse accepts both cases, braces and missing hyphens, and rejects the rest" {
    const u = parse("550E8400-e29b-41d4-a716-446655440000").?;
    try std.testing.expectEqual(@as(u8, 0x55), u[0]);
    try std.testing.expect(parse("{550e8400e29b41d4a716446655440000}") != null);
    try std.testing.expect(parse("550e8400-e29b-41d4-a716-44665544000") == null);
    try std.testing.expect(parse("550e8400e29b-41d4-a716-446655440000x") == null);
    try std.testing.expect(parse("xyz") == null);
}

test "spec: bytes.md#uuid the canonical text is lower case with hyphens" {
    const gpa = std.testing.allocator;
    var aw: Io.Writer.Allocating = .init(gpa);
    defer aw.deinit();
    try write(&aw.writer, parse("550E8400E29B41D4A716446655440000").?);
    try std.testing.expectEqualStrings("550e8400-e29b-41d4-a716-446655440000", aw.written());
}

test "spec: bytes.md#uuid v5 and v3 match the published vectors for the DNS namespace" {
    const dns = parse("6ba7b810-9dad-11d1-80b4-00c04fd430c8").?;
    const gpa = std.testing.allocator;
    var aw: Io.Writer.Allocating = .init(gpa);
    defer aw.deinit();
    try write(&aw.writer, v5(dns, "www.example.com"));
    try std.testing.expectEqualStrings("2ed6657d-e927-568b-95e1-2665a8aea6a2", aw.written());
    aw.clearRetainingCapacity();
    try write(&aw.writer, v3(dns, "www.example.com"));
    try std.testing.expectEqualStrings("5df41881-3aed-3515-88a7-2f4a814cf09e", aw.written());
    try std.testing.expectEqual(@as(u8, 5), version(v5(dns, "x")));
    try std.testing.expectEqual(@as(u8, 3), version(v3(dns, "x")));
}

test "spec: bytes.md#uuid version 4 and 7 carry their version and variant, and v7 carries its time" {
    const rnd: Bytes16 = @splat(0xff);
    const four = v4(rnd);
    try std.testing.expectEqual(@as(u8, 4), version(four));
    try std.testing.expectEqual(@as(u8, 0xbf), four[8]);
    const seven = v7(1_700_000_000_123, rnd);
    try std.testing.expectEqual(@as(u8, 7), version(seven));
    try std.testing.expectEqual(@as(i64, 1_700_000_000_123_000), timeOf7(seven));
    try std.testing.expect(std.mem.order(u8, &v7(1_700_000_000_122, rnd), &seven) == .lt);
}
