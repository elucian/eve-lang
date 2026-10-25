//! @eve-module bytes: the text forms and the search of the type Bytes (hex, Base64, the canonical print)
//! @spec spec/library/bytes.md#bytes
//! @feature F-LNG-13
//! @decision D-221
//! @tests test/level5/e139_bytes_basics, test/level5/e140_bytes_errors, test/level5/e141_bytes_file
//! A Bytes value keeps its bytes in a heap string block (heap.zig), so these functions only read bytes and write text; they allocate the result they return.
const std = @import("std");
const Io = std.Io;

/// The most bytes the canonical print shows; a longer value shows its length after `…`.
pub const print_max: usize = 64;

/// The value of one hexadecimal digit, or null when `c` is not one.
fn nibble(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}

// @eve-fn Bytes.from_hex
// @spec spec/library/bytes.md#bytes
// @feature F-LNG-13
// @test test/level5/e139_bytes_basics
/// The bytes of hexadecimal text (two digits a byte, upper or lower case); null when the length is odd or a digit is not hexadecimal. The result is allocated with `gpa`.
pub fn fromHex(gpa: std.mem.Allocator, text: []const u8) error{OutOfMemory}!?[]u8 {
    if (text.len % 2 != 0) return null;
    for (text) |c| if (nibble(c) == null) return null;
    const out = try gpa.alloc(u8, text.len / 2);
    for (out, 0..) |*b, k| b.* = nibble(text[2 * k]).? * 16 + nibble(text[2 * k + 1]).?;
    return out;
}

/// The hexadecimal text of `b`: two lower-case digits a byte, no separator.
pub fn writeHex(w: *Io.Writer, b: []const u8) Io.Writer.Error!void {
    for (b) |x| try w.print("{x:0>2}", .{x});
}

// @eve-impl the canonical print of a Bytes: `0x` and the hexadecimal digits, then `…(n bytes)` past print_max
// @spec spec/library/bytes.md#bytes
// @feature F-LNG-13
// @test test/level5/e139_bytes_basics
/// The canonical print of `b`: `0x` and its digits, at most `print_max` bytes, then the length when it is longer.
pub fn writePrint(w: *Io.Writer, b: []const u8) Io.Writer.Error!void {
    try w.writeAll("0x");
    try writeHex(w, b[0..@min(b.len, print_max)]);
    if (b.len > print_max) try w.print("…({d} bytes)", .{b.len});
}

/// The Base64 text of `b`: the standard alphabet with padding (RFC 4648), or the URL alphabet without padding when `url` is set. Allocated with `gpa`.
pub fn toBase64(gpa: std.mem.Allocator, b: []const u8, url: bool) error{OutOfMemory}![]u8 {
    const enc = if (url) std.base64.url_safe_no_pad.Encoder else std.base64.standard.Encoder;
    const out = try gpa.alloc(u8, enc.calcSize(b.len));
    _ = enc.encode(out, b);
    return out;
}

// @eve-fn Bytes.from_base64
// @spec spec/library/bytes.md#bytes
// @feature F-LNG-13
// @test test/level5/e140_bytes_errors
/// The bytes of standard Base64 text with its padding; null when the text is not Base64. The result is allocated with `gpa`.
pub fn fromBase64(gpa: std.mem.Allocator, text: []const u8) error{OutOfMemory}!?[]u8 {
    const dec = std.base64.standard.Decoder;
    const size = dec.calcSizeForSlice(text) catch return null;
    const out = try gpa.alloc(u8, size);
    dec.decode(out, text) catch {
        gpa.free(out);
        return null;
    };
    return out;
}

/// The position of the first `needle` in `b`, counted from 1 as `find` does for a String; 0 when there is none.
pub fn indexOf(b: []const u8, needle: []const u8) usize {
    const at = std.mem.indexOf(u8, b, needle) orelse return 0;
    return at + 1;
}

test "spec: bytes.md#bytes hex reads both cases and rejects odd length and other digits" {
    const gpa = std.testing.allocator;
    const out = (try fromHex(gpa, "DeadBEEF")).?;
    defer gpa.free(out);
    try std.testing.expectEqualSlices(u8, &.{ 0xde, 0xad, 0xbe, 0xef }, out);
    try std.testing.expect((try fromHex(gpa, "abc")) == null);
    try std.testing.expect((try fromHex(gpa, "0g")) == null);
}

test "spec: bytes.md#bytes canonical print shows at most 64 bytes" {
    const gpa = std.testing.allocator;
    var aw: Io.Writer.Allocating = .init(gpa);
    defer aw.deinit();
    try writePrint(&aw.writer, &.{ 0x01, 0xab });
    try std.testing.expectEqualStrings("0x01ab", aw.written());
    aw.clearRetainingCapacity();
    const long: [100]u8 = @splat(0);
    try writePrint(&aw.writer, &long);
    try std.testing.expectEqual(@as(usize, 2 + 2 * print_max + "…(100 bytes)".len), aw.written().len);
    try std.testing.expect(std.mem.endsWith(u8, aw.written(), "…(100 bytes)"));
}

test "spec: bytes.md#bytes Base64 standard with padding and URL without padding" {
    const gpa = std.testing.allocator;
    const std_text = try toBase64(gpa, &.{ 0xde, 0xad, 0xbe, 0xef }, false);
    defer gpa.free(std_text);
    try std.testing.expectEqualStrings("3q2+7w==", std_text);
    const url_text = try toBase64(gpa, &.{ 0xde, 0xad, 0xbe, 0xef }, true);
    defer gpa.free(url_text);
    try std.testing.expectEqualStrings("3q2-7w", url_text);
    const back = (try fromBase64(gpa, "3q2+7w==")).?;
    defer gpa.free(back);
    try std.testing.expectEqualSlices(u8, &.{ 0xde, 0xad, 0xbe, 0xef }, back);
    try std.testing.expect((try fromBase64(gpa, "!!")) == null);
}

test "spec: bytes.md#bytes index_of counts from 1 and gives 0 for no match" {
    try std.testing.expectEqual(@as(usize, 3), indexOf(&.{ 0xde, 0xad, 0xbe, 0xef }, &.{0xbe}));
    try std.testing.expectEqual(@as(usize, 0), indexOf(&.{0xde}, &.{0x01}));
}
