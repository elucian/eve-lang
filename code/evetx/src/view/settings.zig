//! @eve-module evetx.view.settings
//! @feature F-TLS-24
//! @decision D-173
//! @see code/evetx/src/view.zig:draw
//! The settings dialog: theme, colors and timers.
const std = @import("std");
const vaxis = @import("vaxis");
const Window = vaxis.Window;
const app_mod = @import("../app.zig");
const options_mod = @import("../options.zig");
const App = app_mod.App;
const theme = @import("../theme.zig");
const ide = @import("ide");
const grid = ide.grid;
const text = ide.text;
const dialogs_m = @import("dialogs.zig");
const find_dialogs_m = @import("find_dialogs.zig");
const menu_m = @import("menu.zig");
const view_m = @import("../view.zig");
const widgets_m = @import("widgets.zig");
const sub = widgets_m.sub;
const fillWith = widgets_m.fillWith;
const put = widgets_m.put;
const addHit = widgets_m.addHit;
const button = widgets_m.button;
const field = widgets_m.field;
const clipText = view_m.clipText;
const dialog = dialogs_m.dialog;
const buttonRow = dialogs_m.buttonRow;
const hsvHex = menu_m.hsvHex;
const repeat = find_dialogs_m.repeat;

/// The Options dialog: Theme, Colors, Timers. The options belong to the user and to the tool; the
/// settings of Eve are in the configuration files of the project.
pub fn settings(app: *App, win: Window) !void {
    const box = dialog(app, win, 82, 27, "Options");
    const names = [_][]const u8{ "Theme", "Colors", "Timers" };
    var x: u16 = 2;
    for (names, 0..) |n, i| {
        const label = app.fmt(" {s} ", .{n});
        const w = box.gwidth(label);
        const open = app.opt_tab == i;
        _ = put(box, x, 2, label, if (open) theme.onBold(theme.deep, theme.blue) else theme.on(theme.text, theme.bar));
        try addHit(app, box, x, 2, w, 1, .{ .opt = .{ .tab = @intCast(i) } });
        x += w + 1;
    }
    _ = put(box, 0, 3, repeat("─", 200), theme.on(theme.line, theme.panel));
    const body = sub(box, 1, 4, box.width -| 2, box.height -| 8);
    switch (app.opt_tab) {
        0 => try themeTab(app, body),
        1 => try colorsTab(app, body),
        else => try timersTab(app, body),
    }
    const help = if (app.opt_edit != .none) "Enter applies the field · Esc closes it" else "Tab: next tab · arrows change the value · Enter saves · Esc cancels";
    _ = put(box, 2, box.height -| 4, help, theme.on(theme.dim, theme.panel));
    try buttonRow(app, box, box.height -| 2, &.{
        .{ .label = "Save", .action = .{ .opt = .ok }, .primary = true },
        .{ .label = "Defaults", .action = .{ .opt = .defaults } },
        .{ .label = "Cancel", .action = .close_overlay },
    });
}

/// The list of themes, the buttons under it (and the field of Rename, Export, Import), and a sample of the theme in use.
pub fn themeTab(app: *App, body: Window) !void {
    const dim = theme.on(theme.dim, theme.panel);
    const opt = &app.options;
    const builtins = theme.themes.len;
    const list_h: usize = 13;
    const rows_total = opt.count() + 1; // the rule between the two groups is a row
    const sel_row = opt.theme_id + @as(usize, if (opt.theme_id >= builtins) 1 else 0);
    const first: usize = if (sel_row + 1 > list_h) sel_row + 1 - list_h else 0;
    var r: usize = 0;
    while (r < list_h and first + r < rows_total) : (r += 1) {
        const row_i = first + r;
        const y: u16 = @intCast(r);
        if (row_i == builtins) {
            _ = put(body, 1, y, if (opt.n_custom == 0) "── no custom theme yet ──" else "── custom ──────────────", theme.on(theme.faint, theme.panel));
            continue;
        }
        const id: usize = if (row_i > builtins) row_i - 1 else row_i;
        const sel = opt.theme_id == id;
        const bg = if (sel) theme.selected else theme.panel;
        const row = sub(body, 0, y, 28, 1);
        fillWith(row, bg);
        _ = put(row, 1, 0, if (sel) "●" else "○", theme.on(theme.blue, bg));
        _ = put(row, 3, 0, clipText(opt.nameOf(id), 24), theme.on(if (sel) theme.bright else theme.text, bg));
        try addHit(app, body, 0, y, 28, 1, .{ .opt = .{ .theme = @intCast(id) } });
    }
    // the buttons: Rename and Remove only for a custom theme; Export and Import always
    const custom = !options_mod.Options.isBuiltin(opt.theme_id);
    const on = theme.on(theme.text, theme.bar);
    const off = theme.on(theme.faint, theme.panel);
    const by: u16 = @intCast(list_h + 1);
    var bx: u16 = 0;
    bx = try button(app, body, bx, by, "Rename", if (custom) on else off, if (custom) .{ .opt = .{ .theme_btn = .rename } } else .nop) + 1;
    bx = try button(app, body, bx, by, "Remove", if (custom) on else off, if (custom) .{ .opt = .{ .theme_btn = .remove } } else .nop) + 1;
    bx = try button(app, body, bx, by, "Export", on, .{ .opt = .{ .theme_btn = .export_file } }) + 1;
    _ = try button(app, body, bx, by, "Import", on, .{ .opt = .{ .theme_btn = .import_file } });
    if (app.opt_edit != .none) {
        _ = put(body, 1, by + 2, "New name", theme.onBold(theme.text, theme.panel));
        const f = sub(body, 13, by + 2, body.width -| 24, 1);
        fillWith(f, theme.bar);
        app.opt_in.drawWithStyle(f, theme.on(theme.bright, theme.bar));
        _ = try button(app, body, body.width -| 9, by + 2, "OK", theme.onBold(theme.bright, theme.green_bg), .{ .opt = .{ .theme_btn = .apply } });
    } else if (app.message) |m| {
        _ = put(body, 1, by + 2, clipText(m, body.width -| 2), theme.on(theme.amber, theme.panel));
    } else {
        _ = put(body, 1, by + 2, "n rename · Del remove · e export · i import (a JSON theme file)", dim);
    }
    // a sample, drawn with the colors in use
    const sx: u16 = 30;
    const sw: u16 = body.width -| (sx + 1);
    const sample = sub(body, sx, 0, sw, 10);
    fillWith(sample, theme.deep);
    const d = theme.deep;
    const dm = theme.on(theme.dim, d);
    _ = put(sample, 1, 0, "# title", theme.on(theme.title, d));
    _ = put(sample, 11, 0, "## sub", theme.on(theme.subtitle, d));
    var c = put(sample, 1, 1, "** line ", theme.on(theme.comment, d));
    c = put(sample, c, 1, "(** expr **) ", theme.on(theme.comment_expr, d));
    _ = put(sample, c, 1, "/* block */", theme.on(theme.comment_block, d));
    c = put(sample, 1, 2, "process", theme.on(theme.keyword, d));
    c = put(sample, c, 2, " main ", theme.on(theme.text, d));
    _ = put(sample, c, 2, "is", theme.on(theme.oper, d));
    c = put(sample, 1, 3, "if", theme.on(theme.control, d));
    c = put(sample, c, 3, " x ", theme.on(theme.text, d));
    c = put(sample, c, 3, "and", theme.on(theme.oper, d));
    c = put(sample, c, 3, " y ", theme.on(theme.text, d));
    c = put(sample, c, 3, "then ", theme.on(theme.control, d));
    _ = put(sample, c, 3, "return", theme.on(theme.interrupt, d));
    c = put(sample, 1, 4, "let n: ", theme.on(theme.text, d));
    c = put(sample, c, 4, "Integer", theme.on(theme.type_name, d));
    c = put(sample, c, 4, " = ", theme.on(theme.text, d));
    _ = put(sample, c, 4, "42", theme.on(theme.number, d));
    c = put(sample, 1, 5, "print(", theme.on(theme.text, d));
    c = put(sample, c, 5, "\"hello\"", theme.on(theme.string, d));
    _ = put(sample, c, 5, ");", theme.on(theme.text, d));
    _ = put(sample, 1, 6, " selected text ", theme.on(theme.bright, theme.sel_bg));
    c = put(sample, 1, 7, " Tab ", theme.onBold(theme.deep, theme.blue));
    c = put(sample, c + 1, 7, " other ", theme.on(theme.text, theme.bar2));
    c = put(sample, c + 1, 7, " Run ", theme.onBold(theme.bright, theme.green_bg));
    _ = put(sample, c + 1, 7, " error ", theme.on(theme.red, d));
    _ = put(sample, 1, 8, "warning", theme.on(theme.amber, d));
    _ = put(sample, 10, 8, "ok", theme.on(theme.green, d));
    _ = put(sample, 14, 8, "info", theme.on(theme.blue, d));
    if (custom) {
        _ = put(body, sx, 11, "A custom theme: the Colors tab changes it.", dim);
    } else {
        _ = put(body, sx, 11, "A built-in theme: a change on the Colors", dim);
        _ = put(body, sx, 12, "tab makes a copy (Dark Custom1, …).", dim);
    }
    _ = put(body, sx, 13, "The font belongs to the terminal.", dm);
}

/// The colors one by one, with a selector for the one that is selected.
pub fn colorsTab(app: *App, body: Window) !void {
    const dim = theme.on(theme.dim, theme.panel);
    const visible: usize = body.height;
    const first: usize = if (app.opt_slot + 1 > visible) app.opt_slot + 1 - visible else 0;
    var r: u16 = 0;
    while (r < visible and first + r < theme.slot_count) : (r += 1) {
        const i = first + r;
        const sel = app.opt_slot == i;
        const bg = if (sel) theme.selected else theme.panel;
        const row = sub(body, 0, r, 30, 1);
        fillWith(row, bg);
        _ = put(row, 1, 0, "██", theme.on(theme.colorOf(i), bg));
        _ = put(row, 4, 0, theme.slot_labels[i], theme.on(if (sel) theme.bright else theme.text, bg));
        try addHit(app, body, 0, r, 30, 1, .{ .opt = .{ .slot = @intCast(i) } });
    }
    const slot: usize = app.opt_slot;
    const hex: u24 = app.options.palette()[slot];
    const x0: u16 = 34;
    _ = put(body, x0, 0, theme.slot_labels[slot], theme.onBold(theme.bright, theme.panel));
    const swatch = sub(body, x0, 1, 14, 2);
    fillWith(swatch, theme.colorOf(slot));
    _ = put(body, x0 + 16, 1, app.fmt("#{x:0>6}", .{hex}), theme.onBold(theme.text, theme.panel));
    const builtin_theme = options_mod.Options.isBuiltin(app.options.theme_id);
    _ = put(body, x0 + 16, 2, clipText(app.options.nameOf(app.options.theme_id), body.width -| (x0 + 17)), theme.onBold(theme.text, theme.panel));
    if (builtin_theme) _ = put(body, x0, 9, "Built-in theme: a change makes a custom copy.", theme.on(theme.amber, theme.panel));
    // the three sliders: a click on a cell sets the value that the cell stands for
    const chan_names = [_][]const u8{ "R", "G", "B" };
    const chan_colors = [_]u24{ 0xd9534f, 0x58c08a, 0x5aa9e6 };
    var ch: u8 = 0;
    while (ch < 3) : (ch += 1) {
        const y: u16 = 4 + ch;
        const shift: u5 = @intCast(8 * (2 - @as(u5, @intCast(ch))));
        const value: u24 = (hex >> shift) & 0xff;
        const picked = app.opt_channel == ch;
        _ = put(body, x0, y, chan_names[ch], theme.onBold(if (picked) theme.amber else theme.dim, theme.panel));
        try addHit(app, body, x0, y, 2, 1, .{ .opt = .{ .channel = ch } });
        var k: u16 = 0;
        while (k < 32) : (k += 1) {
            const v: u8 = @intCast(@as(u32, k) * 255 / 31);
            const filled = v <= value;
            _ = put(body, x0 + 3 + k, y, if (filled) "█" else "░", theme.on(if (filled) theme.fromHex(chan_colors[ch]) else theme.faint, theme.panel));
            try addHit(app, body, x0 + 3 + k, y, 1, 1, .{ .opt = .{ .slider = .{ .ch = ch, .v = v } } });
        }
        _ = put(body, x0 + 36, y, app.fmt("{d:>3}", .{value}), theme.on(theme.text, theme.panel));
    }
    _ = put(body, x0, 8, "r, g, b choose a channel · Left, Right ±8 (Shift ±1)", dim);
    // the palette: 16 hues in three brightnesses, then 16 grays; a click sets the color
    _ = put(body, x0, 10, "Palette", dim);
    const levels = [_]f32{ 1.0, 0.78, 0.5 };
    var row: u16 = 0;
    while (row < 4) : (row += 1) {
        var col: u16 = 0;
        while (col < 16) : (col += 1) {
            const cell: u24 = if (row < 3)
                hsvHex(@as(f32, @floatFromInt(col)) / 16.0, 0.6, levels[row])
            else blk: {
                const g: u24 = @as(u24, col) * 255 / 15;
                break :blk (g << 16) | (g << 8) | g;
            };
            _ = put(body, x0 + col * 2, 11 + row, "██", theme.on(theme.fromHex(cell), theme.panel));
            try addHit(app, body, x0 + col * 2, 11 + row, 2, 1, .{ .opt = .{ .swatch = cell } });
        }
    }
}

/// Auto Save, Run Delay and Trace Delay.
pub fn timersTab(app: *App, body: Window) !void {
    const dim = theme.on(theme.dim, theme.panel);
    const head = theme.on(theme.faint, theme.panel);
    // a grid without lines: the columns are Timer, Value, Change and Description, each row is three lines tall
    _ = put(body, 2, 0, "Timer", head);
    _ = put(body, 15, 0, "Value", head);
    _ = put(body, 26, 0, "Change", head);
    _ = put(body, 50, 0, "Description", head);
    const labels = [_][]const u8{ "Auto save", "Run delay", "Trace delay" };
    const notes = [_][2][]const u8{
        .{ "Save changed files every so", "many seconds (off = never)." },
        .{ "Seconds between typing Run in", "the Console and running it." },
        .{ "Milliseconds between two", "statements while Trace runs." },
    };
    var row: u8 = 0;
    while (row < labels.len) : (row += 1) {
        const y: u16 = 2 + @as(u16, row) * 3;
        const sel = app.opt_row == row;
        _ = put(body, 2, y, labels[row], theme.onBold(if (sel) theme.bright else theme.text, theme.panel));
        const value: []const u8 = switch (row) {
            0 => if (app.options.autosave_s == 0) "off" else app.fmt("every {d} s", .{app.options.autosave_s}),
            1 => if (app.options.run_delay_s == 0) "at once" else app.fmt("{d} s", .{app.options.run_delay_s}),
            else => app.fmt("{d} ms", .{app.options.trace_ms}),
        };
        _ = put(body, 15, y, value, theme.onBold(theme.amber, theme.panel));
        const btn = theme.on(theme.text, theme.bar);
        var x: u16 = 26;
        switch (row) {
            0 => {
                x = try button(app, body, x, y, "-10", btn, .{ .opt = .{ .auto = -10 } }) + 1;
                x = try button(app, body, x, y, "-1", btn, .{ .opt = .{ .auto = -1 } }) + 1;
                x = try button(app, body, x, y, "+1", btn, .{ .opt = .{ .auto = 1 } }) + 1;
                _ = try button(app, body, x, y, "+10", btn, .{ .opt = .{ .auto = 10 } });
            },
            1 => {
                x = try button(app, body, x, y, "-1", btn, .{ .opt = .{ .delay = -1 } }) + 1;
                _ = try button(app, body, x, y, "+1", btn, .{ .opt = .{ .delay = 1 } });
            },
            else => {
                x = try button(app, body, x, y, "-50", btn, .{ .opt = .{ .trace = -50 } }) + 1;
                x = try button(app, body, x, y, "-10", btn, .{ .opt = .{ .trace = -10 } }) + 1;
                x = try button(app, body, x, y, "+10", btn, .{ .opt = .{ .trace = 10 } }) + 1;
                _ = try button(app, body, x, y, "+50", btn, .{ .opt = .{ .trace = 50 } });
            },
        }
        _ = put(body, 50, y, notes[row][0], dim);
        _ = put(body, 50, y + 1, notes[row][1], dim);
    }
    _ = put(body, 2, 12, "Up, Down choose the line · Left, Right change it (Auto save: 10 s steps, Trace: 50 ms).", dim);
    _ = put(body, 2, 14, "These options are for the tool and for you, not for a project. They are saved in your user", dim);
    _ = put(body, 2, 15, "cache. The settings of Eve are in the configuration files.", dim);
}

// @decision D-167
pub const eve_version = blk: {
    @setEvalBranchQuota(200_000);
    const zon = @embedFile("eve_zon");
    const key = ".version = \"";
    const at = std.mem.indexOf(u8, zon, key) orelse break :blk "?";
    const rest = zon[at + key.len ..];
    const len = std.mem.indexOfScalar(u8, rest, '"') orelse break :blk "?";
    break :blk rest[0..len];
};
