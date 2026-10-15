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
    // the kinds of words and comments, as in the SCL tutorial highlighter
    control, interrupt, oper, type_name, title, subtitle, comment_expr, comment_block,
};

pub const slot_count = @typeInfo(Slot).@"enum".fields.len;

/// The values of all the colors of a theme, `0xRRGGBB`, in the order of `Slot`.
pub const Palette = [slot_count]u24;

/// What each color is for, as the Colors tab of the Options dialog says it.
pub const slot_labels = [slot_count][]const u8{
    "Panel background", "Editor background", "Active bar",   "Tab bar",      "Borders",
    "Text",             "Dim text",          "Faint text",   "Bright text",  "Selection (interface)",
    "Selection (text)", "Accent blue",       "Green",        "Green button", "Red",
    "Amber",            "Keyword",           "String",       "Number",       "Comment (**)",
    "Control word",     "Interruption",      "Operator word", "Type",        "Title (#)",
    "Subtitle (##)",    "Comment (** **)",   "Comment (/* */)",
};

pub const Theme = struct { name: []const u8, colors: Palette };

/// The themes that come with evetx. The Custom theme (id `themes.len`) lives in the options.
pub const themes = [_]Theme{
    .{ .name = "Dark Navy", .colors = .{ 0x161c24, 0x0c1015, 0x243447, 0x1a2531, 0x3b4756, 0xa9b7c6, 0x6c7a89, 0x4b5866, 0xe6edf3, 0x2b4a6b, 0x264f78, 0x5aa9e6, 0x58c08a, 0x2f6f4f, 0xd9534f, 0xe0b341, 0xc792ea, 0x98c379, 0xd19a66, 0x6c7a89, 0x82aaff, 0xf07178, 0x89ddff, 0x7fdbca, 0x5fd7a0, 0xa9b7c6, 0x7a8fa8, 0x5f8a8a } },
    .{ .name = "Dark Forest", .colors = .{ 0x141f18, 0x0d1410, 0x1f3a2b, 0x172a20, 0x365244, 0xb4c7b8, 0x6f8a78, 0x4a6354, 0xe8f3ea, 0x2c5a3f, 0x2a5a40, 0x6bb5d9, 0x7bd88f, 0x2f7a4a, 0xd96b5f, 0xd9b84a, 0xb8d96b, 0xa8d08d, 0xe0a96d, 0x6f8a78, 0x6bd9c0, 0xe8836f, 0xd9b84a, 0x7fd0a8, 0x8be28f, 0xa9c4a9, 0x7aa58a, 0x5f9a7a } },
    .{ .name = "Dark Cave", .colors = .{ 0x15151a, 0x0b0b0e, 0x2a2a33, 0x1d1d24, 0x40404c, 0xb8b8c4, 0x7a7a88, 0x55555f, 0xf0f0f5, 0x3a3a52, 0x41416b, 0x8a9be0, 0x6fcf97, 0x2f6b4f, 0xe06c75, 0xd8a657, 0xd19cf0, 0x9ccf8a, 0xe0a070, 0x7a7a88, 0x8a9be0, 0xe06c75, 0xe0a070, 0x6fcfcf, 0x6fcf97, 0xb8b8c4, 0x8a8aa0, 0x6a7a8a } },
    .{ .name = "Dark Sage", .colors = .{ 0x171c22, 0x0e1216, 0x25323f, 0x1b252e, 0x3a4753, 0xd0d6dc, 0x7a8794, 0x505b66, 0xffffff, 0x2a4560, 0x264f78, 0x00bfff, 0x3cb371, 0x2f6f4f, 0xf08080, 0xffa500, 0xffa500, 0xf0e060, 0xda9cf0, 0x8f98a3, 0x00bfff, 0xf08080, 0xf08080, 0x4fd8e0, 0x00e676, 0xc0c0c0, 0x9cc7ff, 0x20b2aa } },
    .{ .name = "Dark Okaida", .colors = .{ 0x1e1f1a, 0x272822, 0x3e3d32, 0x33342b, 0x49483e, 0xf8f8f2, 0x8f908a, 0x5f5f55, 0xffffff, 0x49483e, 0x4a4a3c, 0x66d9ef, 0xa6e22e, 0x4a6a1a, 0xf92672, 0xe6db74, 0xf92672, 0xa6e22e, 0xae81ff, 0x8292a2, 0x66d9ef, 0xfd971f, 0xe6db74, 0x7ee0d0, 0xa6e22e, 0xc8c8c0, 0x9aa6b8, 0x6e7e8e } },
    .{ .name = "Dark Twilight", .colors = .{ 0x1d1d1f, 0x141414, 0x2b2a2d, 0x222124, 0x3d3b3e, 0xe0dcd4, 0x8a8590, 0x5f5a60, 0xf8f8f8, 0x3a3744, 0x3b3a4e, 0x7587a6, 0x8f9d6a, 0x4a5230, 0xcf6a4c, 0xe9c062, 0xcda869, 0x8f9d6a, 0xcf6a4c, 0x7a757c, 0x7587a6, 0xe0715a, 0xdad085, 0xac885c, 0xe9c062, 0xb3a99a, 0x8a8590, 0x6f6a72 } },
    .{ .name = "Light Desert", .colors = .{ 0xe6d6b4, 0xfffaf0, 0xcdb487, 0xdcc79d, 0x9a8458, 0x2e2314, 0x5e4c32, 0x8f7d5e, 0x000000, 0xd9b872, 0xe8c872, 0x1a5a8c, 0x3a6a22, 0x9ccf92, 0xa82418, 0x8f5a00, 0x7a1f8f, 0x3a6a10, 0xa04800, 0x6e5e44, 0x1a5a8c, 0xa82418, 0x7a4400, 0x0d6464, 0x2a6a22, 0x5e4c32, 0x6a5a2a, 0x5a6a4a } },
    .{ .name = "Light Town", .colors = .{ 0xdde4ee, 0xffffff, 0xbccbe0, 0xcfd9e8, 0x8296b0, 0x1a2634, 0x4a5a6e, 0x8090a4, 0x000000, 0xa8c6ea, 0xbcd6f6, 0x0f55aa, 0x1d7a46, 0x96d4b4, 0xb02a1c, 0x8a5400, 0x6a2a9e, 0x1d6a2a, 0xa03e0e, 0x5a6a7e, 0x0f55aa, 0xb02a1c, 0xa03e0e, 0x00686a, 0x1d7a46, 0x4a5a6e, 0x55657a, 0x3f7070 } },
    .{ .name = "Light Pastel", .colors = .{ 0xeadcf0, 0xfffbfe, 0xd4bfe6, 0xe2d2ee, 0xa88cc0, 0x33274a, 0x63547a, 0x9a8cb0, 0x160c28, 0xc8b0e6, 0xdcc6f4, 0x2f63c0, 0x2f8a60, 0xa8dcc0, 0xc4324a, 0x9a6410, 0x8a2fc0, 0x3a8a3a, 0xc05a20, 0x7a6c92, 0x2f63c0, 0xc4324a, 0xc05a20, 0x1a8080, 0x2f8a60, 0x63547a, 0x7a6c92, 0x5a8a8a } },
    // Light Sage: sage leaves (greens), the flower (purple, mauve), the sun (yellow, ochre) and the earth (browns)
    .{ .name = "Light Sage", .colors = .{ 0xb9cf94, 0xeaf1d2, 0x8fb06a, 0xa6c07e, 0x5f7f3e, 0x1f2a12, 0x485a2c, 0x7a8c5a, 0x000000, 0xf0d870, 0xf2dc78, 0x4a3fb0, 0x2e6e1e, 0x8cc46a, 0xb0301c, 0xb87800, 0x7a2aa8, 0x8a5018, 0xc05a00, 0x5f7a48, 0x1f6a2a, 0xc03018, 0xb04a90, 0x1a6a70, 0x2a6a10, 0x5a3a7a, 0x8a6a1a, 0x7a5a38 } },
    .{ .name = "Light Retro", .colors = .{ 0xc0c0c0, 0xfffbe6, 0x8098d0, 0xa8b8d8, 0x606060, 0x000000, 0x404040, 0x808080, 0x000000, 0x7090d0, 0x8aa4e0, 0x0000a8, 0x006000, 0x90d890, 0xa80000, 0x805000, 0x780078, 0x006000, 0x983800, 0x585858, 0x0000a8, 0xa80000, 0x805000, 0x005858, 0x006000, 0x303030, 0x484848, 0x406040 } },
    .{ .name = "Turbo Pascal", .colors = .{ 0x26379a, 0x1c2a88, 0x3d52c8, 0x2f3fa8, 0x7f8fd8, 0xf0e060, 0xb0b8e0, 0x8088c0, 0xffffff, 0x2f8f8f, 0x2a9d9d, 0x5cc8f0, 0x55d055, 0x1f7f3f, 0xf06060, 0xf0c040, 0xffffff, 0x55e0e0, 0xe090e0, 0xa8b0d8, 0xc8e8ff, 0xff7070, 0xf0a060, 0x70f0f0, 0x90ee90, 0xd0d0e8, 0xa0b0e0, 0x90c0c0 } },
    .{ .name = "Shades of Gray", .colors = .{ 0x333333, 0x222222, 0x666666, 0x444444, 0x888888, 0xcccccc, 0x999999, 0x777777, 0xffffff, 0x555555, 0x666666, 0xeeeeee, 0xbbbbbb, 0x555555, 0xffffff, 0xdddddd, 0xffffff, 0xdddddd, 0xaaaaaa, 0x777777, 0x999999, 0xeeeeee, 0x888888, 0xbbbbbb, 0xffffff, 0xcccccc, 0x888888, 0x777777 } },
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
pub var control: Color = fromHex(themes[0].colors[20]);
pub var interrupt: Color = fromHex(themes[0].colors[21]);
pub var oper: Color = fromHex(themes[0].colors[22]);
pub var type_name: Color = fromHex(themes[0].colors[23]);
pub var title: Color = fromHex(themes[0].colors[24]);
pub var subtitle: Color = fromHex(themes[0].colors[25]);
pub var comment_expr: Color = fromHex(themes[0].colors[26]);
pub var comment_block: Color = fromHex(themes[0].colors[27]);

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
        .control => control,
        .interrupt => interrupt,
        .oper => oper,
        .type_name => type_name,
        .title => title,
        .subtitle => subtitle,
        .comment_expr => comment_expr,
        .comment_block => comment_block,
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

// Zig tip: the brightness of a color is a weighted sum of its three bytes (green counts most, as the eye sees it); a theme is
// light when the background of the editor is brighter than the middle. A color that is not `.rgb` counts as dark.
/// Is the theme in use a light one? (Dialogs then get a shadow, so they stand out like a raised card.)
pub fn isLight() bool {
    return switch (deep) {
        .rgb => |c| (@as(u32, c[0]) * 299 + @as(u32, c[1]) * 587 + @as(u32, c[2]) * 114) / 1000 > 140,
        else => false,
    };
}
