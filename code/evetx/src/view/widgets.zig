//! @eve-module evetx.view.widgets
//! @feature F-TLS-24
//! @decision D-173
//! @see code/evetx/src/view.zig:draw
//! The drawing primitives: sub windows, boxes, text, buttons and fields that record their hit rectangles.
const vaxis = @import("vaxis");
const Window = vaxis.Window;
const TextInput = vaxis.widgets.TextInput;
const app_mod = @import("../app.zig");
const App = app_mod.App;
const Action = app_mod.Action;
const Rect = app_mod.Rect;
const theme = @import("../theme.zig");
const ide = @import("ide");
const text = ide.text;
const Style = theme.Style;
const dialogs_m = @import("dialogs.zig");
const find_dialogs_m = @import("find_dialogs.zig");
const dialog = dialogs_m.dialog;
const repeat = find_dialogs_m.repeat;

// ------------------------------------------------------------------ helpers

/// A child window at a place of `win`, without a border.
pub fn sub(win: Window, x: u16, y: u16, w: u16, h: u16) Window {
    return win.child(.{ .x_off = @intCast(x), .y_off = @intCast(y), .width = w, .height = h });
}

/// A child window with a one-cell border; the result is the inside.
pub fn boxed(win: Window, x: u16, y: u16, w: u16, h: u16, border: theme.Color) Window {
    return win.child(.{
        .x_off = @intCast(x),
        .y_off = @intCast(y),
        .width = w,
        .height = h,
        .border = .{ .where = .all, .glyphs = .single_square, .style = theme.on(border, theme.panel) },
    });
}

pub fn fillWith(win: Window, bg: theme.Color) void {
    win.fill(.{ .style = .{ .bg = bg } });
}

/// Print `s` at (col, row) of `win` on one line; returns the column after it.
pub fn put(win: Window, col: u16, row: u16, s: []const u8, style: Style) u16 {
    const r = win.printSegment(.{ .text = s, .style = style }, .{ .col_offset = col, .row_offset = row, .wrap = .none });
    return r.col;
}

/// Print `s` so that it ends at column `end` (right aligned).
pub fn putRight(win: Window, end: u16, row: u16, s: []const u8, style: Style) void {
    const w = win.gwidth(s);
    _ = put(win, end -| w, row, s, style);
}

pub fn absRect(win: Window, x: u16, y: u16, w: u16, h: u16) Rect {
    return .{ .x = @intCast(@as(i32, win.x_off) + x), .y = @intCast(@as(i32, win.y_off) + y), .w = w, .h = h };
}

pub fn addHit(app: *App, win: Window, x: u16, y: u16, w: u16, h: u16, action: Action) !void {
    try app.hits.append(app.gpa, .{ .rect = absRect(win, x, y, w, h), .action = action });
}

/// A button of a given width (the label is centered).
pub fn fixedButton(app: *App, win: Window, x: u16, label: []const u8, w: u16, style: Style, action: Action) !u16 {
    const spaces = repeat(" ", 40);
    const gw = win.gwidth(label);
    const left: usize = @min(spaces.len, (w -| gw) / 2);
    const right: usize = @min(spaces.len, w -| gw -| left);
    return button(app, win, x, 0, app.fmt("{s}{s}{s}", .{ spaces[0..left], label, spaces[0..right] }), style, action);
}

/// A button: ` label ` on a background; clickable.
pub fn button(app: *App, win: Window, x: u16, y: u16, label: []const u8, style: Style, action: Action) !u16 {
    const w = win.gwidth(label) + 2;
    _ = put(win, x, y, " ", style);
    _ = put(win, x + 1, y, label, style);
    _ = put(win, x + 1 + win.gwidth(label), y, " ", style);
    try addHit(app, win, x, y, w, 1, action);
    return x + w;
}

/// A one-line input field of a dialog. The focused one shows its cursor; the others show their text.
pub fn field(app: *App, win: Window, x: u16, y: u16, w: u16, ti: *TextInput, which: u8, focused: bool) !void {
    if (w < 3) return;
    const f = sub(win, x, y, w, 1);
    fillWith(f, if (focused) theme.bar else theme.deep);
    if (focused) {
        ti.drawWithStyle(f, theme.on(theme.bright, theme.bar));
    } else {
        const first = ti.buf.firstHalf();
        const c = put(f, 1, 0, first, theme.on(theme.text, theme.deep));
        _ = put(f, c, 0, ti.buf.secondHalf(), theme.on(theme.text, theme.deep));
    }
    try addHit(app, win, x, y, w, 1, .{ .dlg_field = which });
}
