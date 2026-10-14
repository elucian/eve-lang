//! The colors and styles of evetx, the same as in the drawings of `design/` (design.svg).
const vaxis = @import("vaxis");

// Zig tip: `vaxis.Cell.Color` is a tagged union: `.default`, `.index` (the 256 colors of a
// terminal) or `.rgb` (true color, three bytes). A tagged union holds exactly one of its fields
// and remembers which one, so a `switch` on it is checked by the compiler.
pub const Color = vaxis.Cell.Color;
pub const Style = vaxis.Cell.Style;

// Zig tip: a `comptime` parameter must be known when the program is compiled. `rgb(0x0f141a)` is
// therefore evaluated by the compiler, and the constants below cost nothing at run time.
// `@intCast` narrows an integer to the type that the context needs (here `u8`); in a safe build
// it checks that the value fits.
fn rgb(comptime hex: u24) Color {
    return .{ .rgb = .{ @intCast(hex >> 16), @intCast((hex >> 8) & 0xff), @intCast(hex & 0xff) } };
}

pub const background = rgb(0x0f141a);
pub const panel = rgb(0x161c24);
pub const deep = rgb(0x0c1015);
pub const line = rgb(0x3b4756);
pub const text = rgb(0xa9b7c6);
pub const dim = rgb(0x6c7a89);
pub const faint = rgb(0x4b5866);
pub const bright = rgb(0xe6edf3);
pub const bar = rgb(0x243447);
pub const bar2 = rgb(0x1a2531);
pub const blue = rgb(0x5aa9e6);
pub const green = rgb(0x58c08a);
pub const green_bg = rgb(0x2f6f4f);
pub const red = rgb(0xd9534f);
pub const amber = rgb(0xe0b341);
pub const selected = rgb(0x2b4a6b);
pub const current_line = rgb(0x4a3f12);
pub const sel_bg = rgb(0x264f78);
pub const keyword = rgb(0xc792ea);
pub const string = rgb(0x98c379);
pub const number = rgb(0xd19a66);
pub const comment = rgb(0x6c7a89);

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
