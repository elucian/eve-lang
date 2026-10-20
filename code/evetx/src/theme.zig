//! The colors and styles of evetx. The colors are variables, not constants: the Options dialog changes
//! them while the program runs (a theme, or the individual colors of a custom theme), and every
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

pub const slot_count = std.meta.fieldNames(Slot).len;

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

// Zig tip: an enum without values written is numbered by the compiler (0, 1, 2); `@tagName(b)` gives the name of a value
// as text ("dark"), which is how the theme files write it.
/// The kind of a theme: a changed copy of a built-in theme is named after it (`Dark Custom1`).
pub const Base = enum { dark, gray, light };

// Zig tip: a struct written on one line; `name` is a `[]const u8` that points at a string literal of the program, so a
// built-in theme needs no memory of its own.
/// A built-in theme.
pub const Theme = struct { name: []const u8, base: Base, colors: Palette };

/// The themes that come with evetx, in the order of the Options dialog. They cannot be changed, renamed or removed: a change
/// of a color makes a custom copy. More themes are files of the folder `code/evetx/themes/`, which Options > Import reads.
pub const themes = [_]Theme{
    .{ .name = "Dark Theme", .base = .dark, .colors = .{ 0x171c22, 0x0e1216, 0x25323f, 0x1b252e, 0x3a4753, 0xd0d6dc, 0x7a8794, 0x505b66, 0xffffff, 0x2a4560, 0x264f78, 0x00bfff, 0x3cb371, 0x2f6f4f, 0xf08080, 0xffa500, 0xffa500, 0xf0e060, 0xda9cf0, 0x8f98a3, 0x00bfff, 0xf08080, 0xf08080, 0x4fd8e0, 0x00e676, 0xc0c0c0, 0x9cc7ff, 0x20b2aa } },
    .{ .name = "Gray Theme", .base = .gray, .colors = .{ 0x333333, 0x222222, 0x666666, 0x444444, 0x888888, 0xcccccc, 0x999999, 0x777777, 0xffffff, 0x555555, 0x666666, 0xeeeeee, 0xbbbbbb, 0x555555, 0xffffff, 0xdddddd, 0xffffff, 0xdddddd, 0xaaaaaa, 0x777777, 0x999999, 0xeeeeee, 0x888888, 0xbbbbbb, 0xffffff, 0xcccccc, 0x888888, 0x777777 } },
    .{ .name = "Light Theme", .base = .light, .colors = .{ 0xb9cf94, 0xeaf1d2, 0x8fb06a, 0xa6c07e, 0x5f7f3e, 0x1f2a12, 0x485a2c, 0x7a8c5a, 0x000000, 0xf0d870, 0xf2dc78, 0x4a3fb0, 0x2e6e1e, 0x8cc46a, 0xb0301c, 0xb87800, 0x7a2aa8, 0x8a5018, 0xc05a00, 0x5f7a48, 0x1f6a2a, 0xc03018, 0xb04a90, 0x1a6a70, 0x2a6a10, 0x5a3a7a, 0x8a6a1a, 0x7a5a38 } },
};

// The colors in use. They start as the Dark Theme; `apply` changes them.
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
// `Slot`. In each copy `fname` is a string known to the compiler, and `@field(@This(), fname)`
// names the variable of that name in this file, so one loop sets all the variables without a line
// for each of them.
/// Put the colors of a palette in use.
pub fn apply(p: Palette) void {
    inline for (comptime std.meta.fieldNames(Slot), 0..) |fname, i| {
        @field(@This(), fname) = fromHex(p[i]);
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
// Zig tip: the colour of the border of the panel that has the keyboard. The palette blue of the light theme is a dark indigo
// that hardly shows against the green background, so a light theme gets a clear blue of its own; the others keep their blue.
/// The colour of the border of the active panel.
pub fn accent() Color {
    return if (isLight()) fromHex(0x0064ff) else blue;
}

pub fn isLight() bool {
    return switch (deep) {
        .rgb => |c| (@as(u32, c[0]) * 299 + @as(u32, c[1]) * 587 + @as(u32, c[2]) * 114) / 1000 > 140,
        else => false,
    };
}
