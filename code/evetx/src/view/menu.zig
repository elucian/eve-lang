//! @eve-module evetx.view.menu
//! @feature F-TLS-24
//! @decision D-173
//! @see code/evetx/src/view.zig:draw
//! The drop down menus.
const std = @import("std");
const vaxis = @import("vaxis");
const Window = vaxis.Window;
const app_mod = @import("../app.zig");
const App = app_mod.App;
const theme = @import("../theme.zig");
const ide = @import("ide");
const text = ide.text;
const dialogs_m = @import("dialogs.zig");
const find_dialogs_m = @import("find_dialogs.zig");
const view_m = @import("../view.zig");
const widgets_m = @import("widgets.zig");
const sub = widgets_m.sub;
const boxed = widgets_m.boxed;
const fillWith = widgets_m.fillWith;
const put = widgets_m.put;
const putRight = widgets_m.putRight;
const addHit = widgets_m.addHit;
const menuX = view_m.menuX;
const solid = dialogs_m.solid;
const shadow = dialogs_m.shadow;
const repeat = find_dialogs_m.repeat;

/// The text of a menu row: its label, with a check box (panels) or a dot (the current window)
/// in front when the row has one.
pub fn rowLabel(app: *App, row: app_mod.MenuRow) []const u8 {
    const cmd = row.cmd orelse return row.label;
    return switch (cmd) {
        .toggle_tree => app.fmt("[{s}] {s}", .{ if (app.show_tree) "x" else " ", row.label }),
        .toggle_main => app.fmt("[{s}] {s}", .{ if (app.show_main) "x" else " ", row.label }),
        .toggle_tools => app.fmt("[{s}] {s}", .{ if (app.show_tools) "x" else " ", row.label }),
        .toggle_hidden => app.fmt("[{s}] {s}", .{ if (app.show_hidden) "x" else " ", row.label }),
        .toggle_wrap => app.fmt("[{s}] {s}", .{ if (app.wrap) "x" else " ", row.label }),
        .window_pick => app.fmt("{s} {s}", .{ if (row.arg == app.active) "●" else " ", row.label }),
        .filter_table => if (app.activeTab()) |t| (if (std.mem.startsWith(u8, t.path, "filter:")) "Alter filter…" else row.label) else row.label,
        .data_edit => if (app.activeTab()) |t| (if (t.editing) "Stop Editing" else row.label) else row.label,
        // Close names what it closes: a table, a folder list or a file
        .close_tab => if (app.activeTab()) |t| (if (t.table != null) "Close table" else if (t.folder != null) "Close folder" else "Close file") else row.label,
        else => row.label,
    };
}

/// The shortcut shown at the right of a row. A window has Ctrl and its number.
pub fn rowKey(app: *App, row: app_mod.MenuRow) []const u8 {
    if (row.cmd == .window_pick) return app.fmt("Ctrl+{d}", .{row.arg + 1});
    if (row.cmd == .data_edit) {
        if (app.activeTab()) |t| {
            if (t.editing) return "Esc";
        }
    }
    return row.key;
}

/// The drop-down of the open menu, under its name in the bar.
pub fn menuDrop(app: *App, win: Window) !void {
    const m = app.menu_top;
    const n = app.rowCount(m);
    var lw: u16 = 0;
    var kw: u16 = 0;
    var k: usize = 0;
    while (k < n) : (k += 1) {
        const row = app.rowAt(m, k);
        lw = @max(lw, win.gwidth(rowLabel(app, row)));
        kw = @max(kw, win.gwidth(rowKey(app, row)));
    }
    const w: u16 = @max(22, lw + kw + 6);
    const x = @min(menuX(win.width, m), win.width -| w);
    const h: u16 = @intCast(@min(n + 2, win.height -| 2));
    solid(app, win, x, 1, w, h);
    shadow(win, x, 1, w, h);
    const box = boxed(win, x, 1, w, h, theme.blue);
    fillWith(box, theme.panel);
    k = 0;
    while (k < n and k < box.height) : (k += 1) {
        const row = app.rowAt(m, k);
        const r: u16 = @intCast(k);
        if (row.cmd == null) {
            _ = put(box, 0, r, repeat("─", 100), theme.on(theme.line, theme.panel));
            continue;
        }
        const sel = app.menu_sel == k;
        const bg = if (sel) theme.selected else theme.panel;
        const line = sub(box, 0, r, box.width, 1);
        fillWith(line, bg);
        const enabled = app.menuEnabled(row.cmd.?);
        _ = put(line, 1, 0, rowLabel(app, row), theme.on(if (!enabled) theme.faint else if (sel) theme.bright else theme.text, bg));
        putRight(line, line.width -| 1, 0, rowKey(app, row), theme.on(if (!enabled) theme.faint else if (sel) theme.bright else theme.dim, bg));
        try addHit(app, box, 0, r, box.width, 1, .{ .menu_item = k });
    }
}

/// The color `0xRRGGBB` of a hue (0 to 1), a saturation and a value.
pub fn hsvHex(h: f32, s: f32, v: f32) u24 {
    const hh = h * 6.0;
    const i: u32 = @intFromFloat(@floor(hh));
    const f = hh - @floor(hh);
    const p = v * (1 - s);
    const q = v * (1 - s * f);
    const t = v * (1 - s * (1 - f));
    const rgb: [3]f32 = switch (i % 6) {
        0 => .{ v, t, p },
        1 => .{ q, v, p },
        2 => .{ p, v, t },
        3 => .{ p, q, v },
        4 => .{ t, p, v },
        else => .{ v, p, q },
    };
    const r: u24 = @intFromFloat(rgb[0] * 255);
    const g: u24 = @intFromFloat(rgb[1] * 255);
    const b: u24 = @intFromFloat(rgb[2] * 255);
    return (r << 16) | (g << 8) | b;
}
