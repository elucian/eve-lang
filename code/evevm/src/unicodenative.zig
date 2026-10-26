//! @eve-module unicodenative: the module `unicode` (nfc, is_nfc, width)
//! @spec spec/library/text.md#module-unicode
//! @feature F-LIB-03
//! @decision D-236
//! @tests test/level3/c84_text_unicode
const std = @import("std");
const interp = @import("interp.zig");
const nfc = @import("evecm").nfc;

const Interp = interp.Interp;
const Value = interp.Value;
const Signal = interp.Signal;
const Node = interp.Node;
const err_argument = interp.err_argument;

const wide = [_][2]u21{
    .{ 0x1100, 0x115F },   .{ 0x2E80, 0x303E },   .{ 0x3041, 0x33FF },   .{ 0x3400, 0x4DBF },   .{ 0x4E00, 0x9FFF },
    .{ 0xA000, 0xA4CF },   .{ 0xAC00, 0xD7A3 },   .{ 0xF900, 0xFAFF },   .{ 0xFE30, 0xFE6F },   .{ 0xFF00, 0xFF60 },
    .{ 0xFFE0, 0xFFE6 },   .{ 0x1F300, 0x1F64F }, .{ 0x1F900, 0x1F9FF }, .{ 0x20000, 0x3FFFD },
};

const zero = [_][2]u21{
    .{ 0x0300, 0x036F }, .{ 0x1AB0, 0x1AFF }, .{ 0x1DC0, 0x1DFF }, .{ 0x200B, 0x200F }, .{ 0x20D0, 0x20FF },
    .{ 0xFE00, 0xFE0F }, .{ 0xFE20, 0xFE2F },
};

/// The columns that a code point takes on a terminal: 0 for a control or a combining mark, 2 for a wide one, else 1.
pub fn columns(cp: u21) usize {
    if (cp < 32 or (cp >= 0x7F and cp < 0xA0)) return 0;
    for (zero) |r| if (cp >= r[0] and cp <= r[1]) return 0;
    for (wide) |r| if (cp >= r[0] and cp <= r[1]) return 2;
    return 1;
}

// @eve-fn unicode.nfc, unicode.is_nfc, unicode.width
// @spec spec/library/text.md#module-unicode
pub fn unicodeModule(it: *Interp, name: []const u8, _: []const *const Node, args: []const *const Node) Signal!?Value {
    const eql = std.mem.eql;
    if (!(eql(u8, name, "nfc") or eql(u8, name, "is_nfc") or eql(u8, name, "width"))) return null;
    if (args.len != 1) return it.failWith(err_argument, "unicode.{s} takes a text", .{name});
    const v = try it.eval(args[0]);
    if (v != .str) return it.failWith(err_argument, "unicode.{s}: the argument is a String", .{name});
    if (eql(u8, name, "is_nfc")) return @as(?Value, .{ .bool = nfc.isNormalized(it.t, v.str) });
    if (eql(u8, name, "nfc")) return @as(?Value, try it.newStr(nfc.normalize(it.t, v.str) catch return error.OutOfMemory));
    var total: usize = 0;
    var view = std.unicode.Utf8View.init(v.str) catch return it.failWith(err_argument, "unicode.width: the text is not valid UTF-8", .{});
    var cps = view.iterator();
    while (cps.nextCodepoint()) |cp| total += columns(cp);
    return @as(?Value, .{ .int = @intCast(total) });
}
