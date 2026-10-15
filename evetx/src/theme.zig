//! The colors and styles of evetx. The colors are variables, not constants: the Options dialog changes
//! them while the program runs (a theme, or the individual colors of the Custom theme), and every
//! drawing function reads them again in the next frame.
const std = @import("std");
const vaxis = @import("vaxis");

// Zig tip: `vaxis.Cell.Color` is a tagged union: `.default`, `.index` (the 256 colors of a
// terminal) or `.rgb` (true color, three bytes). A tagged union holds exactly one of its fields
// and remembers which one, so a `switch` on it is checked by the compiler.
pub const Color = vaxis.Cell.Color;
pub const Style = vaxis.Cell.Style;

// Zig tip: A function whose parameters are known when the program is compiled can also be called by
// the compiler: the initial values of the variables below are such calls. `hex >> 16` moves the red
// byte down, `& 0xff` keeps one byte, and `@intCast` narrows the number to the `u8` of the color.
/// A color from `0xRRGGBB`.
pub fn fromHex(hex: u24) Color {
    return .{ .rgb = .{ @intCast(hex >> 16), @intCast((hex >> 8) & 0xff), @intCast(hex & 0xff) } };
}

// Zig tip: An enum names the colors that a theme sets. `slot_count` is computed by the compiler from
// the number of fields of the enum, so adding a color here is enough for the tables below to ask for
// one more value (a table of the wrong length is a compile error).
/// The colors that a theme sets, in the order of the tables below.
pub const Slot = enum {
    panel, deep, bar, bar2, line, text, dim, faint, bright, selected, sel_bg,
    blue, green, green_bg, red, amber, keyword, string, number, comment,
};

pub const slot_count = @typeInfo(Slot).@"enum".fields.len;

/// The values of all the colors of a theme, `0xRRGGBB`, in the order of `Slot`.
pub const Palette = [slot_count]u24;

/// What each color is for, as the Colors tab of the Options dialog says it.
pub const slot_labels = [slot_count][]const u8{
    "Panel background", "Editor background", "Active bar",   "Tab bar",      "Borders",
    "Text",             "Dim text",          "Faint text",   "Bright text",  "Selection (interface)",
    "Selection (text)", "Accent blue",       "Green",        "Green button", "Red",
    "Amber",            "Keyword",           "String",       "Number",       "Comment",
};

pub const Theme = struct { name: []const u8, colors: Palette };

/// The themes that come with evetx. The Custom theme (id `themes.len`) lives in the options.
pub const themes = [_]Theme{
    .{ .name = "Dark Navy", .colors = .{ 0x161c24, 0x0c1015, 0x243447, 0x1a2531, 0x3b4756, 0xa9b7c6, 0x6c7a89, 0x4b5866, 0xe6edf3, 0x2b4a6b, 0x264f78, 0x5aa9e6, 0x58c08a, 0x2f6f4f, 0xd9534f, 0xe0b341, 0xc792ea, 0x98c379, 0xd19a66, 0x6c7a89 } },
    .{ .name = "Dark Forest", .colors = .{ 0x141f18, 0x0d1410, 0x1f3a2b, 0x172a20, 0x365244, 0xb4c7b8, 0x6f8a78, 0x4a6354, 0xe8f3ea, 0x2c5a3f, 0x2a5a40, 0x6bb5d9, 0x7bd88f, 0x2f7a4a, 0xd96b5f, 0xd9b84a, 0xb8d96b, 0xa8d08d, 0xe0a96d, 0x6f8a78 } },
    .{ .name = "Dark Cave", .colors = .{ 0x15151a, 0x0b0b0e, 0x2a2a33, 0x1d1d24, 0x40404c, 0xb8b8c4, 0x7a7a88, 0x55555f, 0xf0f0f5, 0x3a3a52, 0x41416b, 0x8a9be0, 0x6fcf97, 0x2f6b4f, 0xe06c75, 0xd8a657, 0xd19cf0, 0x9ccf8a, 0xe0a070, 0x7a7a88 } },
    .{ .name = "Light Desert", .colors = .{ 0xece0c8, 0xfaf3e3, 0xd9c7a3, 0xe3d5b6, 0xb9a57e, 0x4a3b28, 0x7d6a50, 0xa8977b, 0x1c140a, 0xe2c58c, 0xf0d9a0, 0x2f6f9f, 0x4f7f3a, 0xa8d5a2, 0xc0392b, 0xb8741a, 0x8e3a9e, 0x4e7d2c, 0xb5651d, 0x8a7a60 } },
    .{ .name = "Light Town", .colors = .{ 0xe9edf2, 0xfbfcfd, 0xd0d9e4, 0xdfe5ed, 0xa9b6c6, 0x2d3a4a, 0x5f6f82, 0x93a1b3, 0x0b1520, 0xb9d0ee, 0xcfe2fa, 0x1f6fbf, 0x2e8b57, 0xa9dcc0, 0xc0392b, 0xb9770e, 0x7b3fb0, 0x2f7a3a, 0xb0541a, 0x7a8a9c } },
    .{ .name = "Light Pastel", .colors = .{ 0xf3e9f2, 0xfffafc, 0xe1d3ec, 0xecdff2, 0xc9b6d6, 0x4b3f5c, 0x7d6f90, 0xa99cba, 0x241a33, 0xd7c5ee, 0xe6d6f7, 0x5b8fd6, 0x5fae8a, 0xbfe6d2, 0xe07a8a, 0xd9a24a, 0xb06bd6, 0x6fae6a, 0xd98a5a, 0x9a8cac } },
    .{ .name = "Light Retro", .colors = .{ 0xc8c8c8, 0xf0ecd6, 0xa8b8d8, 0xb8c4dc, 0x808080, 0x202020, 0x555555, 0x909090, 0x000000, 0x8fa8d8, 0x9fb4e0, 0x0000a0, 0x007000, 0xa0e0a0, 0xb00000, 0x906000, 0x800080, 0x007000, 0xa04000, 0x707070 } },
};

/// The id of the Custom theme (the ids of the others are their places in `themes`).
pub const custom_id: u8 = themes.len;

// The colors in use. They start as Dark Navy; `apply` changes them.
pub var panel: Color = fromHex(themes[0].colors[0]);
pub var deep: Color = fromHex(themes[0].colors[1]);
pub var bar: Color = fromHex(themes[0].colors[2]);
pub var bar2: Color = fromHex(themes[0].colors[3]);
pub var line: Color = fromHex(themes[0].colors[4]);
pub var text: Color = fromHex(themes[0].colors[5]);
pub var dim: Color = fromHex(themes[0].colors[6]);
pub var faint: Color = fromHex(themes[0].colors[7]);
pub var bright: Color = fromHex(themes[0].colors[8]);
pub var selected: Color = fromHex(themes[0].colors[9]);
pub var sel_bg: Color = fromHex(themes[0].colors[10]);
pub var blue: Color = fromHex(themes[0].colors[11]);
pub var green: Color = fromHex(themes[0].colors[12]);
pub var green_bg: Color = fromHex(themes[0].colors[13]);
pub var red: Color = fromHex(themes[0].colors[14]);
pub var amber: Color = fromHex(themes[0].colors[15]);
pub var keyword: Color = fromHex(themes[0].colors[16]);
pub var string: Color = fromHex(themes[0].colors[17]);
pub var number: Color = fromHex(themes[0].colors[18]);
pub var comment: Color = fromHex(themes[0].colors[19]);

// Zig tip: `inline for` unrolls the loop at compile time, one copy of the body for each field of
// `Slot`. In each copy `f.name` is a string known to the compiler, and `@field(@This(), f.name)`
// names the variable of that name in this file, so one loop sets all the variables without a line
// for each of them.
/// Put the colors of a palette in use.
pub fn apply(p: Palette) void {
    inline for (@typeInfo(Slot).@"enum".fields, 0..) |f, i| {
        @field(@This(), f.name) = fromHex(p[i]);
    }
}

// Zig tip: `@enumFromInt` turns the number of a slot back into the enum value, and a `switch` over
// the enum must name every slot: adding a color to `Slot` without adding it here is a compile error.
/// The color in use for slot number `slot`.
pub fn colorOf(slot: usize) Color {
    return switch (@as(Slot, @enumFromInt(slot))) {
        .panel => panel,
        .deep => deep,
        .bar => bar,
        .bar2 => bar2,
        .line => line,
        .text => text,
        .dim => dim,
        .faint => faint,
        .bright => bright,
        .selected => selected,
        .sel_bg => sel_bg,
        .blue => blue,
        .green => green,
        .green_bg => green_bg,
        .red => red,
        .amber => amber,
        .keyword => keyword,
        .string => string,
        .number => number,
        .comment => comment,
    };
}

// Zig tip: a function can return a struct literal with only some fields written: the others take
// their default values (`.bold = false`, and so on, see Style in libvaxis).
/// A style from a foreground and a background color.
pub fn on(fg: Color, bg: Color) Style {
    return .{ .fg = fg, .bg = bg };
}

// Zig tip: `pub` makes a declaration visible to the other files; without it a function or constant
// belongs to its file only. The body is one expression: a struct literal whose type comes from the
// return type.
/// The same, in bold.
pub fn onBold(fg: Color, bg: Color) Style {
    return .{ .fg = fg, .bg = bg, .bold = true };
}
