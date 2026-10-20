//! @eve-module evetx.view.find_dialogs
//! @feature F-TLS-24
//! @decision D-173
//! @see code/evetx/src/view.zig:draw
//! About, go to, the two searches, replace, Save As and the project and folder dialogs.
const std = @import("std");
const vaxis = @import("vaxis");
const Window = vaxis.Window;
const app_mod = @import("../app.zig");
const App = app_mod.App;
const theme = @import("../theme.zig");
const ide = @import("ide");
const text = ide.text;
const dialogs_m = @import("dialogs.zig");
const settings_m = @import("settings.zig");
const sidebar_m = @import("sidebar.zig");
const view_m = @import("../view.zig");
const widgets_m = @import("widgets.zig");
const sub = widgets_m.sub;
const fillWith = widgets_m.fillWith;
const put = widgets_m.put;
const addHit = widgets_m.addHit;
const button = widgets_m.button;
const field = widgets_m.field;
const clipText = view_m.clipText;
const vBar = sidebar_m.vBar;
const setPbar = sidebar_m.setPbar;
const dialog = dialogs_m.dialog;
const topDialog = dialogs_m.topDialog;
const buttonRow = dialogs_m.buttonRow;
const ok_btn = dialogs_m.ok_btn;
const eve_version = settings_m.eve_version;

pub fn about(app: *App, win: Window) !void {
    const box = dialog(app, win, 56, 11, "About");
    _ = put(box, 2, 2, "evetx: the Eve terminal IDE", theme.onBold(theme.bright, theme.panel));
    _ = put(box, 2, 3, app.fmt("Version {s}", .{eve_version}), theme.onBold(theme.green, theme.panel));
    _ = put(box, 2, 5, "A text user interface for Eve projects (level 6).", theme.on(theme.text, theme.panel));
    _ = put(box, 2, 6, "Built on libvaxis. (c) Sage-Code Laboratory", theme.on(theme.dim, theme.panel));
    try buttonRow(app, box, box.height -| 2, &.{.{ .label = "Close", .action = .close_overlay, .primary = true }});
}

pub fn gotoBox(app: *App, win: Window) !void {
    const box = topDialog(app, win, 40, 5, "GoTo");
    try field(app, box, 1, 0, box.width -| 2, &app.goto_in, 0, true);
    _ = put(box, 1, 1, "Line, or line:column (42 or 42:7)", theme.on(theme.dim, theme.panel));
    try buttonRow(app, box, 2, &.{
        .{ .label = "Go", .action = ok_btn, .primary = true },
        .{ .label = "Close", .action = .close_overlay },
    });
}

pub fn findTextBox(app: *App, win: Window) !void {
    const box = topDialog(app, win, 46, 5, "Find Text");
    try field(app, box, 1, 0, box.width -| 2, &app.find_in, 0, true);
    _ = put(box, 1, 1, "Enter finds the next match", theme.on(theme.dim, theme.panel));
    try buttonRow(app, box, 2, &.{
        .{ .label = "Next", .action = ok_btn, .primary = true },
        .{ .label = "Close", .action = .close_overlay },
    });
}

pub fn findFileBox(app: *App, win: Window) !void {
    const box = topDialog(app, win, 52, 6, "Find File");
    try field(app, box, 1, 0, box.width -| 2, &app.files_in, 0, true);
    const typed = app.files_in.buf.firstHalf().len + app.files_in.buf.secondHalf().len;
    if (typed > 0 and app.selected < app.tree.entries.items.len) {
        const e = app.tree.entries.items[app.selected];
        _ = put(box, 1, 1, clipText(e.path, box.width -| 3), theme.on(theme.green, theme.panel));
    } else {
        _ = put(box, 1, 1, "Type the first letters of a file name", theme.on(theme.dim, theme.panel));
    }
    _ = put(box, 1, 2, "Up, Down next match", theme.on(theme.dim, theme.panel));
    try buttonRow(app, box, 3, &.{
        .{ .label = "Open", .action = ok_btn, .primary = true },
        .{ .label = "Close", .action = .close_overlay },
    });
}

pub fn replaceBox(app: *App, win: Window) !void {
    const box = topDialog(app, win, 52, 6, "Replace");
    _ = put(box, 1, 0, "Find", theme.on(theme.dim, theme.panel));
    try field(app, box, 10, 0, box.width -| 11, &app.find_in, 0, app.dlg_field == 0);
    _ = put(box, 1, 1, "Replace", theme.on(theme.dim, theme.panel));
    try field(app, box, 10, 1, box.width -| 11, &app.replace_in, 1, app.dlg_field == 1);
    try buttonRow(app, box, 2, &.{
        .{ .label = "Replace", .action = .{ .button = .replace }, .primary = true },
        .{ .label = "Replace all", .action = .{ .button = .replace_all } },
        .{ .label = "Close", .action = .close_overlay },
    });
    _ = put(box, 1, 3, "Tab switches the field", theme.on(theme.dim, theme.panel));
}

pub fn saveAsBox(app: *App, win: Window) !void {
    const box = dialog(app, win, 64, 9, "Save As");
    _ = put(box, 2, 2, "File path, relative to the project folder:", theme.on(theme.text, theme.panel));
    const f = sub(box, 2, 3, box.width -| 4, 1);
    fillWith(f, theme.bar);
    app.saveas_in.drawWithStyle(f, theme.on(theme.bright, theme.bar));
    try buttonRow(app, box, box.height -| 2, &.{
        .{ .label = "Save", .action = ok_btn, .primary = true },
        .{ .label = "Cancel", .action = .close_overlay },
    });
}

/// File > Open project: the projects of the cache, one row each.
pub fn projectBox(app: *App, win: Window) !void {
    const box = dialog(app, win, 76, 19, "Open project");
    const dim = theme.on(theme.dim, theme.panel);
    _ = put(box, 2, 2, "Known projects. Import a folder to add one; Forget takes it off the list.", dim);
    const n = app.cache.projects.items.len;
    const list_h: u16 = box.height -| 9;
    if (app.proj_sel < app.proj_top) app.proj_top = app.proj_sel;
    if (app.proj_sel >= app.proj_top + list_h) app.proj_top = app.proj_sel + 1 - list_h;
    if (n <= list_h) app.proj_top = 0;
    const frame = sub(box, 1, 4, box.width -| 2, list_h);
    fillWith(frame, theme.deep);
    if (n == 0) {
        _ = put(frame, 2, 1, "No projects yet.", theme.on(theme.text, theme.deep));
        _ = put(frame, 2, 2, "Press I, or the button Import folder…, to choose a folder.", theme.on(theme.dim, theme.deep));
    }
    var r: u16 = 0;
    while (r < list_h and app.proj_top + r < n) : (r += 1) {
        const i = app.proj_top + r;
        const path = app.cache.projects.items[i];
        const sel = i == app.proj_sel;
        const bg = if (sel) theme.selected else theme.deep;
        const row = sub(frame, 0, r, frame.width, 1);
        fillWith(row, bg);
        const c = put(row, 1, 0, "📁 ", theme.on(theme.amber, bg));
        _ = put(row, c, 0, clipText(App.baseName(path), 20), theme.onBold(if (sel) theme.bright else theme.text, bg));
        _ = put(row, c + 22, 0, clipText(path, frame.width -| (c + 24)), theme.on(if (sel) theme.text else theme.dim, bg));
        try addHit(app, frame, 0, r, frame.width, 1, .{ .proj_row = i });
    }
    if (n > list_h) _ = put(box, box.width -| 12, 3, app.fmt("{d} projects", .{n}), dim);
    _ = put(box, 2, box.height -| 4, "Enter opens · Del forgets · I imports a folder · a second click opens", dim);
    try buttonRow(app, box, box.height -| 2, &.{
        .{ .label = "Open", .action = ok_btn, .primary = true },
        .{ .label = "Import folder…", .action = .{ .dlg = .browse } },
        .{ .label = "Forget", .action = .{ .dlg = .forget } },
        .{ .label = "Cancel", .action = .close_overlay },
    });
}

/// File > Open Folder: a browser of folders. The field shows the path; the list shows the sub
/// folders; Open as project adds the folder to the cache and opens it.
/// The folder selector: Open Folder, Move (a file of the Info dialog), Export and Import of a theme.
pub fn folderBox(app: *App, win: Window) !void {
    const with_name = app.fbHasName();
    const title: []const u8, const ok_label: []const u8 = switch (app.fb_mode) {
        .project => .{ "Open Folder", "Open as project" },
        .move_to => .{ app.fmt("Move {s} to a folder", .{app.infoName()}), "Move here" },
        .move_many => .{ app.fmt("Move {d} selected to a folder", .{app.marks.items.len}), "Move here" },
        .save_as => .{ "Save As", "Save" },
        .theme_export => .{ "Export theme", "Export" },
        .theme_import => .{ "Import theme", "Import" },
    };
    const box = dialog(app, win, 78, 22, title);
    const dim = theme.on(theme.dim, theme.panel);
    _ = put(box, 0, 1, repeat("─", 200), theme.on(theme.line, theme.panel));
    _ = put(box, 2, 2, "Folder", dim);
    try field(app, box, 10, 2, box.width -| 12, &app.project_in, 0, app.dlg_field == 0);
    const n = app.fbRowCount();
    const list_h: u16 = box.height -| @as(u16, if (with_name) 11 else 9);
    if (app.fb_sel < app.fb_top) app.fb_top = app.fb_sel;
    if (app.fb_sel >= app.fb_top + list_h) app.fb_top = app.fb_sel + 1 - list_h;
    if (n <= list_h) app.fb_top = 0;
    const frame = sub(box, 1, 4, box.width -| 2, list_h);
    fillWith(frame, theme.deep);
    // the last column of the list is the scroll bar when the rows do not fit
    const need_bar = n > list_h;
    const row_w: u16 = if (need_bar) frame.width -| 1 else frame.width;
    var r: u16 = 0;
    while (r < list_h and app.fb_top + r < n) : (r += 1) {
        const i = app.fb_top + r;
        const sel = i == app.fb_sel;
        const bg = if (sel) (if (app.dlg_field == 1) theme.selected else theme.bar) else theme.deep;
        const row = sub(frame, 0, r, row_w, 1);
        fillWith(row, bg);
        const name = app.fbRowName(i);
        if (std.mem.eql(u8, name, "..")) {
            _ = put(row, 1, 0, "↑  ..", theme.on(theme.dim, bg));
        } else if (app.fbRowIsFile(i)) {
            const c = put(row, 1, 0, "📄 ", theme.on(theme.text, bg));
            _ = put(row, c, 0, clipText(name, frame.width -| 6), theme.on(if (sel) theme.bright else theme.text, bg));
        } else {
            const c = put(row, 1, 0, "📁 ", theme.on(theme.amber, bg));
            _ = put(row, c, 0, clipText(name, frame.width -| 6), theme.on(if (sel) theme.bright else theme.text, bg));
        }
        try addHit(app, frame, 0, r, row_w, 1, .{ .fb_row = i });
    }
    if (need_bar) setPbar(app, .fbox, vBar(app, frame, frame.width - 1, list_h, n, app.fb_top, list_h, .{ .fb_scroll = .up }, .{ .fb_scroll = .down }, false), n, list_h);
    if (with_name) {
        _ = put(box, 2, box.height -| 6, "File name", dim);
        try field(app, box, 13, box.height -| 6, box.width -| 15, &app.fb_name, 2, app.dlg_field == 2);
    }
    const count = app.fb_entries.items.len;
    const info = switch (app.fb_mode) {
        .project => app.fmt("{d} folders · Enter in · Backspace up · Tab field/list · F2 open as project", .{count}),
        .move_to, .move_many => app.fmt("{d} folders · Enter in · Backspace up · F2 moves here", .{count}),
        .save_as => app.fmt("{d} folders · {d} files · click a file for its name · Tab next field · F2 save", .{ count, app.fb_files.items.len }),
        else => app.fmt("{d} folders · {d} theme files · Tab next field · F2 {s}", .{ count, app.fb_files.items.len, ok_label }),
    };
    _ = put(box, 2, box.height -| 4, clipText(info, box.width -| 4), dim);
    try buttonRow(app, box, box.height -| 2, &.{
        .{ .label = ok_label, .action = .{ .dlg = .open_here }, .primary = true },
        .{ .label = "Cancel", .action = .close_overlay },
    });
}

// @test the tests of the shared files (code/evecm/src/ide/) run with `zig build test` at the repository root

/// `piece` repeated `n` times, at compile time (Zig 0.17 removed the operator `**`).
pub fn repeat(comptime piece: []const u8, comptime n: usize) *const [piece.len * n]u8 {
    const S = struct {
        const value = blk: {
            var a: [piece.len * n]u8 = undefined;
            for (0..n) |i| @memcpy(a[i * piece.len ..][0..piece.len], piece);
            break :blk a;
        };
    };
    return &S.value;
}
