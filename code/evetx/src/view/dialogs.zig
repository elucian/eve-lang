//! @eve-module evetx.view.dialogs
//! @feature F-TLS-24
//! @decision D-173
//! @see code/evetx/src/view.zig:draw
//! The dialogs: filter, tab menu, properties, confirm, new file, wizards, structure of a table.
const std = @import("std");
const vaxis = @import("vaxis");
const Window = vaxis.Window;
const app_mod = @import("../app.zig");
const App = app_mod.App;
const Action = app_mod.Action;
const theme = @import("../theme.zig");
const ide = @import("ide");
const sqlstruct = ide.sqlstruct;
const text = ide.text;
const Style = theme.Style;
const find_dialogs_m = @import("find_dialogs.zig");
const main_panel_m = @import("main_panel.zig");
const sidebar_m = @import("sidebar.zig");
const tools_m = @import("tools.zig");
const view_m = @import("../view.zig");
const widgets_m = @import("widgets.zig");
const sub = widgets_m.sub;
const boxed = widgets_m.boxed;
const fillWith = widgets_m.fillWith;
const put = widgets_m.put;
const addHit = widgets_m.addHit;
const button = widgets_m.button;
const field = widgets_m.field;
const clipText = view_m.clipText;
const blank = sidebar_m.blank;
const dateText = main_panel_m.dateText;
const sizeText = tools_m.sizeText;
const repeat = find_dialogs_m.repeat;

// ------------------------------------------------------------------ overlays

/// Make the rectangle of a dialog a click that does nothing, so a click on its text does not close it.
pub fn solid(app: *App, win: Window, x: u16, y: u16, w: u16, h: u16) void {
    addHit(app, win, x, y, w, h, .nop) catch {};
}

/// The × button that closes a dialog.
pub fn closeButton(app: *App, win: Window, x: u16, y: u16, style: Style) void {
    _ = put(win, x, y, " × ", style);
    addHit(app, win, x, y, 3, 1, .close_overlay) catch {};
}

/// Draw the shadow of a box at (x, y) of `win`, `w` cells wide and `h` rows high (light themes only).
pub fn shadow(win: Window, x: u16, y: u16, w: u16, h: u16) void {
    if (!theme.isLight()) return;
    var cy: u16 = y + 1;
    while (cy <= y + h and cy < win.height) : (cy += 1) {
        if (x + w < win.width) darken(win, x + w, cy);
    }
    var bx: u16 = x + 1;
    while (bx <= x + w and bx < win.width) : (bx += 1) {
        if (y + h < win.height) darken(win, bx, y + h);
    }
}

pub fn darken(win: Window, col: u16, row: u16) void {
    var cell = win.readCell(col, row) orelse vaxis.Cell{ .char = .{ .grapheme = " ", .width = 1 } };
    cell.style.bg = theme.line;
    cell.style.fg = theme.text;
    win.writeCell(col, row, cell);
}

// Returns the window inside the dialog so that the caller draws its lines at fixed rows.
// `@min(w, win.width -| 2)` keeps it inside a small window.
/// A dialog in the middle of the screen: returns the inside, the first row holds the title and the × button.
pub fn dialog(app: *App, win: Window, w: u16, h: u16, title: []const u8) Window {
    const ww = @min(w, win.width -| 2);
    const hh = @min(h, win.height -| 2);
    // A small dialog (it fits in the Main Panel with 10% to spare) is centered over the Main Panel; a large one in the
    // whole window, the command window.
    const main = app.layout.main;
    const small = main.w > 0 and @as(u32, ww) * 10 <= @as(u32, main.w) * 9 and @as(u32, hh) * 10 <= @as(u32, main.h) * 9;
    const x = if (small) main.x + (main.w - ww) / 2 else (win.width - ww) / 2;
    const y = if (small) main.y + (main.h - hh) / 2 else (win.height - hh) / 2;
    solid(app, win, x, y, ww, hh);
    shadow(win, x, y, ww, hh);
    const box = boxed(win, x, y, ww, hh, theme.blue);
    fillWith(box, theme.panel);
    const head = sub(box, 0, 0, box.width, 1);
    fillWith(head, theme.selected);
    _ = put(head, 1, 0, title, theme.onBold(theme.bright, theme.selected));
    closeButton(app, head, head.width -| 3, 0, theme.on(theme.bright, theme.selected));
    return box;
}

/// A small dialog at the top right of the screen: returns the inside.
pub fn topDialog(app: *App, win: Window, w: u16, h: u16, title: []const u8) Window {
    const ww = @min(w, win.width -| 2);
    const x = win.width -| ww;
    solid(app, win, x, 1, ww, h);
    shadow(win, x, 1, ww, h);
    const box = boxed(win, x, 1, ww, h, theme.blue);
    fillWith(box, theme.panel);
    _ = put(win, x + 2, 1, app.fmt(" {s} ", .{title}), theme.onBold(theme.bright, theme.deep));
    closeButton(app, win, x + ww -| 5, 1, theme.onBold(theme.bright, theme.deep));
    return box;
}

pub const Btn = struct { label: []const u8, action: Action, primary: bool = false, enabled: bool = true };

/// A row of buttons at the right end of row `y` of a dialog.
pub fn buttonRow(app: *App, box: Window, y: u16, specs: []const Btn) !void {
    var total: u16 = 0;
    for (specs) |b| total += box.gwidth(b.label) + 3;
    var x: u16 = box.width -| (total + 1);
    for (specs) |b| {
        const style = if (!b.enabled) theme.on(theme.faint, theme.panel) else if (b.primary) theme.onBold(theme.bright, theme.green_bg) else theme.on(theme.text, theme.bar);
        x = try button(app, box, x, y, b.label, style, if (b.enabled) b.action else .nop) + 1;
    }
}

pub const ok_btn: Action = .{ .dlg = .ok };

/// The filter dialog: one row for each filter (a column and a value or pattern), buttons under the list.
pub fn filterBox(app: *App, win: Window) !void {
    const box = dialog(app, win, 74, 20, app.fmt("{s} · {s}", .{ if (app.flt_view) |vn| app.fmt("Alter view {s} of", .{vn}) else if (app.flt_replace != null) "Alter filter" else "Filter", app.filterTableTitle() }));
    const dim = theme.on(theme.dim, theme.panel);
    _ = put(box, 2, 2, "Field", dim);
    _ = put(box, 20, 2, "Value or regular expression (empty: the field is shown, not filtered)", dim);
    const list_h: u16 = box.height -| 9;
    const n = app.flt_rows.items.len;
    const first: usize = if (app.flt_sel >= list_h) app.flt_sel + 1 - list_h else 0;
    var r: u16 = 0;
    while (r < list_h and first + r < n) : (r += 1) {
        const i = first + r;
        const sel = i == app.flt_sel;
        const bg = if (sel) theme.selected else theme.panel;
        const y: u16 = 3 + r;
        fillWith(sub(box, 1, y, box.width -| 2, 1), bg);
        try addHit(app, box, 1, y, box.width -| 2, 1, .{ .filter_row = i });
        const row = app.flt_rows.items[i];
        _ = put(box, 2, y, clipText(app.fmt("{s}", .{app.filterColName(row.col)}), 15), theme.onBold(if (sel) theme.bright else theme.blue, bg));
        try addHit(app, box, 2, y, 16, 1, .{ .filter_col = i });
        if (sel) {
            const f = sub(box, 20, y, box.width -| 22, 1);
            fillWith(f, theme.bar);
            app.flt_in.drawWithStyle(f, theme.on(theme.bright, theme.bar));
        } else {
            _ = put(box, 20, y, clipText(app.fmt("{s}", .{row.pat}), box.width -| 23), theme.on(theme.text, bg));
        }
    }
    // the list of the fields that are out of the filter: one is chosen to come back
    if (app.flt_pick) {
        var k: usize = 0;
        while (app.filterMissingCol(k) != null) : (k += 1) {}
        const h: u16 = @intCast(@min(k, list_h) + 2);
        const pick = boxed(box, 16, 3, 28, h, theme.blue);
        solid(app, box, 16, 3, 28, h);
        fillWith(pick, theme.panel);
        var row: u16 = 0;
        while (row < h -| 2) : (row += 1) {
            const idx: usize = if (app.flt_pick_sel >= row + 1 and app.flt_pick_sel + 1 > h - 2) app.flt_pick_sel + 1 - (h - 2) + row else row;
            const col = app.filterMissingCol(idx) orelse break;
            const on = idx == app.flt_pick_sel;
            const bg = if (on) theme.selected else theme.panel;
            fillWith(sub(pick, 0, row, pick.width, 1), bg);
            _ = put(pick, 1, row, clipText(app.fmt("{s}", .{app.filterColName(col)}), 24), theme.on(if (on) theme.bright else theme.text, bg));
            try addHit(app, pick, 0, row, pick.width, 1, .{ .filter_pick = idx });
        }
    }
    _ = put(box, 2, box.height -| 6, "Up, Down, Tab: field · Insert: add a field back · Ctrl+D: take the field out · Enter: filter", dim);
    _ = put(box, 2, box.height -| 5, "A cell matches when the value is in it (case ignored). Patterns: ^ $ . * + ? [a-z] ( | ) \\d", dim);
    try buttonRow(app, box, box.height -| 2, &.{
        .{ .label = "Add field", .action = .{ .dlg = .filter_add } },
        .{ .label = "Remove field", .action = .{ .dlg = .filter_remove }, .enabled = n > 1 },
        .{ .label = "Filter", .action = ok_btn, .primary = true },
        .{ .label = "Cancel", .action = .close_overlay },
    });
}

/// The popup menu of a tab (right click on its title).
pub fn tabMenuBox(app: *App, win: Window) !void {
    var lw: u16 = 0;
    for (app_mod.tab_menu_rows) |row| lw = @max(lw, win.gwidth(row.label));
    const w: u16 = lw + 4;
    const h: u16 = @intCast(app_mod.tab_menu_rows.len + 2);
    const x = @min(app.tab_menu_x, win.width -| w);
    const y = @min(app.tab_menu_y, win.height -| h);
    solid(app, win, x, y, w, h);
    shadow(win, x, y, w, h);
    const box = boxed(win, x, y, w, h, theme.blue);
    fillWith(box, theme.panel);
    for (app_mod.tab_menu_rows, 0..) |row, i| {
        const r: u16 = @intCast(i);
        const sel = app.tab_menu_sel == i;
        const bg = if (sel) theme.selected else theme.panel;
        const line = sub(box, 0, r, box.width, 1);
        fillWith(line, bg);
        if (row.cmd == .sep) {
            _ = put(box, 0, r, repeat("─", 60), theme.on(theme.line, theme.panel));
            continue;
        }
        _ = put(line, 1, 0, row.label, theme.on(if (sel) theme.bright else theme.text, bg));
        try addHit(app, box, 0, r, box.width, 1, .{ .tabmenu_item = i });
    }
}

/// The Info dialog (Info… of a tab, File > Rename…): `File: name` (or `Table:`, `View:`, `Folder:`), a rule, the facts.
pub fn propertiesBox(app: *App, win: Window) !void {
    const p = app.props;
    const is_table = if (app.rename_from) |r| std.mem.indexOfScalar(u8, r, '#') != null else false;
    const is_folder = std.mem.eql(u8, p.kind, "Folder");
    var facts: [8][2][]const u8 = undefined;
    var n: usize = 0;
    facts[n] = .{ "Kind", p.kind };
    n += 1;
    facts[n] = .{ if (is_table) "Database" else "Folder", if (p.place.len == 0) "(project folder)" else p.place };
    n += 1;
    if (p.size) |s| {
        facts[n] = .{ "Size", sizeText(app, s) };
        n += 1;
    }
    if (p.modified > 0) {
        facts[n] = .{ "Modified", app.fmt("{s} UTC", .{dateText(app, p.modified)}) };
        n += 1;
    }
    if (p.lines) |l| {
        facts[n] = .{ "Lines", app.fmt("{d}{s}", .{ l, if (p.unsaved) " (unsaved changes)" else "" }) };
        n += 1;
        facts[n] = .{ "Line ends", p.line_ends };
        n += 1;
    }
    if (p.records) |r| {
        facts[n] = .{ if (is_table) "Rows" else "Records", app.fmt("{d}", .{r}) };
        n += 1;
    }
    if (p.fields) |f| {
        facts[n] = .{ "Fields", app.fmt("{d}", .{f}) };
        n += 1;
    }
    const what: []const u8 = if (p.is_view) "View" else if (is_table) "Table" else if (is_folder) "Folder" else "File";
    const h: u16 = @intCast(9 + n);
    const box = dialog(app, win, 70, h, app.fmt("{s}: {s}", .{ what, app.infoName() }));
    const dim = theme.on(theme.dim, theme.panel);
    _ = put(box, 0, 1, repeat("─", 200), theme.on(theme.line, theme.panel));
    _ = put(box, 2, 2, "Name", dim);
    if (app.prop_editing) {
        const f = sub(box, 13, 2, box.width -| 15, 1);
        fillWith(f, theme.bar);
        app.saveas_in.drawWithStyle(f, theme.on(theme.bright, theme.bar));
    } else {
        _ = put(box, 13, 2, clipText(app.infoName(), box.width -| 15), theme.onBold(theme.bright, theme.panel));
    }
    for (facts[0..n], 0..) |fact, i| {
        const y: u16 = @intCast(3 + i);
        _ = put(box, 2, y, fact[0], dim);
        _ = put(box, 13, y, clipText(fact[1], box.width -| 15), theme.on(theme.text, theme.panel));
    }
    const hint = if (app.prop_editing) "Enter renames · Esc leaves the name" else if (is_table) "r rename · Esc closes · a table moves with its database" else "r rename · m move to another folder · Esc closes";
    // the buttons are on the row `box.height - 2`; the hint goes on the row above them
    if (app.message) |m| {
        _ = put(box, 2, box.height -| 3, clipText(m, box.width -| 4), theme.on(theme.amber, theme.panel));
    } else _ = put(box, 2, box.height -| 3, hint, dim);
    try buttonRow(app, box, box.height -| 2, &.{
        .{ .label = "Rename", .action = .{ .prop_btn = .rename }, .primary = app.prop_editing, .enabled = !p.is_view },
        .{ .label = "Move", .action = .{ .prop_btn = .move }, .enabled = !is_table and !app.prop_editing },
        .{ .label = "Close", .action = .close_overlay },
    });
}

/// The confirmation dialog: a message and Yes / No. Reused by every question (`App.askConfirm`).
pub fn confirmBox(app: *App, win: Window) !void {
    const msg = app.confirm_msg orelse "Are you sure?";
    const w: u16 = @max(40, win.gwidth(msg) + 6);
    const box = dialog(app, win, w, 7, "Confirm");
    _ = put(box, 2, 2, msg, theme.on(theme.text, theme.panel));
    try buttonRow(app, box, box.height -| 2, &.{
        .{ .label = "Yes", .action = .{ .confirm = true }, .primary = true },
        .{ .label = "No", .action = .{ .confirm = false } },
    });
}

/// File > New…: the name of the new file, folder or database.
pub fn newBox(app: *App, win: Window) !void {
    const box = dialog(app, win, 70, 11, switch (app.new_kind) {
        .file => "New file",
        .folder => "New folder",
        .database => "New SQLite database",
        .table_copy => "Save table as",
        .import_data => "Import a file into the database",
    });
    const dim = theme.on(theme.dim, theme.panel);
    const dir = app.targetDir();
    if (app.new_kind == .import_data) {
        _ = put(box, 2, 1, app.fmt("Database: {s}", .{app.selectedDb() orelse ""}), theme.on(theme.text, theme.panel));
    } else _ = put(box, 2, 1, app.fmt("Folder: {s}/", .{if (dir.len == 0) "(the project folder)" else dir}), theme.on(theme.text, theme.panel));
    _ = put(box, 2, 3, switch (app.new_kind) {
        .file => "Name, with its extension:",
        .folder => "Name of the folder:",
        .database => "Name of the database (.db when no extension):",
        .table_copy => "Name of the new table, or of the view when the table is filtered:",
        .import_data => "File to import (path in the project):",
    }, dim);
    const f = sub(box, 2, 4, box.width -| 4, 1);
    fillWith(f, theme.bar);
    app.saveas_in.drawWithStyle(f, theme.on(theme.bright, theme.bar));
    _ = put(box, 2, 6, switch (app.new_kind) {
        .file => ".eve  .sql  .db  start a wizard · .md .json .txt ... start empty",
        .folder => "The folder is made inside the folder shown above.",
        .database => "The database starts with the table eve_meta (descriptions and dates of the tables).",
        .table_copy => "A filter becomes a view; a table is copied with its records.",
        .import_data => "CSV, TXT, JSON, DBF: a new table named after the file (XLS: save as CSV)",
    }, dim);
    try buttonRow(app, box, box.height -| 2, &.{
        .{ .label = "Next", .action = ok_btn, .primary = true },
        .{ .label = "Cancel", .action = .close_overlay },
    });
}

/// The wizard of an Eve file or an SQL file: a name and what to start from.
pub fn wizardBox(app: *App, win: Window) !void {
    const choices = app_mod.App.wizardChoices(app.wiz_kind);
    const title = if (app.wiz_kind == .eve) "New Eve file" else "New SQL script";
    const box = dialog(app, win, 70, @intCast(choices.len + 12), title);
    const dim = theme.on(theme.dim, theme.panel);
    _ = put(box, 2, 1, app.fmt("File: {s}", .{app.wiz_path orelse ""}), dim);
    _ = put(box, 2, 3, if (app.wiz_kind == .eve) "Name of the aspect or module" else "Name of the table", theme.on(theme.text, theme.panel));
    const f = sub(box, 2, 4, box.width -| 4, 1);
    fillWith(f, theme.bar);
    app.wiz_name.drawWithStyle(f, theme.on(theme.bright, theme.bar));
    _ = put(box, 2, 6, "Start from (Up and Down choose):", theme.on(theme.text, theme.panel));
    for (choices, 0..) |c, i| {
        const sel = i == app.wiz_choice;
        const bg = if (sel) theme.selected else theme.panel;
        const row = sub(box, 1, @intCast(7 + i), box.width -| 2, 1);
        fillWith(row, bg);
        _ = put(row, 1, 0, if (sel) "◉" else "○", theme.on(theme.blue, bg));
        _ = put(row, 3, 0, c, theme.on(if (sel) theme.bright else theme.text, bg));
        try addHit(app, box, 1, @intCast(7 + i), box.width -| 2, 1, .{ .wiz_choice = i });
    }
    try buttonRow(app, box, box.height -| 2, &.{
        .{ .label = "Create", .action = ok_btn, .primary = true },
        .{ .label = "Cancel", .action = .close_overlay },
    });
}

/// DATA > Append rows…: how many blank rows.
pub fn appendNBox(app: *App, win: Window) !void {
    const box = dialog(app, win, 44, 8, "Append rows");
    _ = put(box, 2, 1, "How many blank rows?", theme.on(theme.text, theme.panel));
    const f = sub(box, 2, 2, 12, 1);
    fillWith(f, theme.bar);
    app.goto_in.drawWithStyle(f, theme.on(theme.bright, theme.bar));
    try buttonRow(app, box, box.height -| 2, &.{
        .{ .label = "Append", .action = ok_btn, .primary = true },
        .{ .label = "Cancel", .action = .close_overlay },
    });
}

/// Previous, Next, Create and Cancel of the dialog of a new table.
pub fn wizardButtons(app: *App, box: Window) !void {
    const ok = app.sqNameOk();
    try buttonRow(app, box, box.height -| 2, &.{
        .{ .label = "◄ Previous", .action = .{ .sq_btn = .prev }, .enabled = app.sq_page > 0 },
        .{ .label = "Next ►", .action = .{ .sq_btn = .next }, .enabled = app.sq_page < 2 and ok },
        .{ .label = "Create", .action = .{ .sq_btn = .apply }, .primary = true, .enabled = ok },
        .{ .label = "Cancel", .action = .close_overlay },
    });
}

/// The first and the last page of the dialog of a new table.
pub fn newTablePages(app: *App, box: Window) !void {
    const dim = theme.on(theme.dim, theme.panel);
    const txt = theme.on(theme.text, theme.panel);
    if (app.sq_page == 0) {
        _ = put(box, 2, 1, "Step 1 of 3 · Name and description", theme.onBold(theme.bright, theme.panel));
        _ = put(box, 2, 3, app.fmt("In the database {s}", .{app.sq_db orelse ""}), txt);
        _ = put(box, 2, 5, "Name of the table:", dim);
        try field(app, box, 2, 6, box.width -| 4, &app.sq_name_in, 0, app.dlg_field == 0);
        _ = put(box, 2, 8, "Description:", dim);
        try field(app, box, 2, 9, box.width -| 4, &app.sq_desc_in, 1, app.dlg_field == 1);
        _ = put(box, 2, 11, "Letters, digits and _; it begins with a letter. Tab changes field · Enter or Next shows the fields.", dim);
    } else {
        _ = put(box, 2, 1, "Step 3 of 3 · Indexes", theme.onBold(theme.bright, theme.panel));
        _ = put(box, 2, 2, "Tab changes list · Space ticks a field · U unique · Enter adds the index · Del removes · Ctrl+S creates", dim);
        _ = put(box, 2, 4, "Indexes of the table", dim);
        const n = app.sq_idx.items.len;
        if (n == 0) _ = put(box, 2, 5, "no index yet", dim);
        const first: usize = if (app.sq_ix_sel >= 5) app.sq_ix_sel - 4 else 0;
        var r: usize = first;
        while (r < @min(n, first + 5)) : (r += 1) {
            const ix = &app.sq_idx.items[r];
            const y: u16 = @intCast(5 + r - first);
            const sel = r == app.sq_ix_sel;
            const bg = if (sel and app.sq_ix_focus == 1) theme.bar else if (sel) theme.selected else theme.panel;
            const row = sub(box, 2, y, box.width -| 4, 1);
            fillWith(row, bg);
            _ = put(row, 1, 0, clipText(app.fmt("{s}  ({s}){s}", .{ ix.nameS(), ix.colsS(), if (ix.unique) "  unique" else "" }), row.width -| 2), theme.on(theme.text, bg));
            try addHit(app, box, 2, y, box.width -| 4, 1, .{ .sq_ix_row = @intCast(r) });
        }
        _ = put(box, 2, 11, "New index: tick one or more fields", dim);
        const cols = app.sq_cols.items;
        const per: usize = 7;
        const fstart = (app.sq_ix_cur / per) * per;
        var i: usize = fstart;
        while (i < @min(cols.len, fstart + per)) : (i += 1) {
            const y: u16 = @intCast(12 + i - fstart);
            const cur = i == app.sq_ix_cur and app.sq_ix_focus == 0;
            const bg = if (cur) theme.bar else theme.panel;
            const ticked = i < 64 and app.sq_ix_mask & (@as(u64, 1) << @intCast(i)) != 0;
            const row = sub(box, 2, y, 44, 1);
            fillWith(row, bg);
            _ = put(row, 1, 0, app.fmt("{s} {s}  {s}", .{ if (ticked) "[x]" else "[ ]", cols[i].nameS(), cols[i].typeS() }), theme.on(theme.text, bg));
            try addHit(app, box, 2, y, 44, 1, .{ .sq_ix_field = @intCast(i) });
        }
        const ux: u16 = 52;
        _ = put(box, ux, 12, app.fmt("{s} Unique", .{if (app.sq_ix_uniq) "[x]" else "[ ]"}), txt);
        try addHit(app, box, ux, 12, 14, 1, .sq_ix_unique);
        var cb: [160]u8 = undefined;
        const chosen = app.sqIndexColsText(&cb);
        _ = put(box, ux, 14, "Fields of the index:", dim);
        _ = put(box, ux, 15, if (chosen.len == 0) "(none ticked)" else clipText(chosen, box.width -| ux -| 3), txt);
        try buttonRow(app, box, box.height -| 4, &.{
            .{ .label = "+ Add index", .action = .sq_ix_add },
            .{ .label = "− Remove index", .action = .sq_ix_remove, .enabled = n > 0 },
        });
    }
    if (app.sq_error) |e| _ = put(box, 2, 21, clipText(e, box.width -| 4), theme.on(theme.red, theme.panel));
    try wizardButtons(app, box);
}

/// The structure dialog of a SQLite table.
pub fn sqStructureBox(app: *App, win: Window) !void {
    const box = dialog(app, win, 92, 28, if (app.sq_new) app.fmt("New table in {s}  (SQLite)", .{app.sq_db orelse ""}) else app.fmt("Structure of {s}  ({s}, SQLite)", .{ app.sq_table orelse "", app.sq_db orelse "" }));
    const dim = theme.on(theme.dim, theme.panel);
    const line = theme.on(theme.line, theme.panel);
    if (app.sq_new and app.sq_page != 1) {
        try newTablePages(app, box);
        return;
    }
    const cols = app.sq_cols.items;
    const n = cols.len;
    const per: usize = 10;
    const page = app.sq_row / per;
    const pages = (n + per - 1) / per;
    const first = page * per;
    const last = @min(first + per, n);
    if (app.sq_new) {
        _ = put(box, 2, 1, app.fmt("Step 2 of 3 · Fields · columns {d}–{d} of {d}", .{ first + 1, last, n }), theme.on(theme.text, theme.panel));
    } else _ = put(box, 2, 1, app.fmt("Columns {d}–{d} of {d} · page {d} of {d}", .{ first + 1, last, n, page + 1, pages }), theme.on(theme.text, theme.panel));
    _ = put(box, 2, 2, "arrows move · Enter edits · Space switches a box · Ins adds · Del removes · Ctrl+Up/Down moves · Ctrl+S applies", dim);
    const widths = [_]u16{ 4, 22, 18, 10, 6, 22 };
    const heads = [_][]const u8{ "#", "Name", "Type", "Not null", "Key", "Default" };
    const hl = repeat("─", 40);
    var rule_buf: [3][320]u8 = undefined;
    const marks = [3][3][]const u8{ .{ "┌", "┬", "┐" }, .{ "├", "┼", "┤" }, .{ "└", "┴", "┘" } };
    var rules: [3][]const u8 = undefined;
    for (marks, 0..) |m, ri| {
        var len: usize = 0;
        for (widths, 0..) |w, k| {
            const mark = if (k == 0) m[0] else m[1];
            @memcpy(rule_buf[ri][len..][0..mark.len], mark);
            len += mark.len;
            @memcpy(rule_buf[ri][len..][0 .. 3 * w], hl[0 .. 3 * w]);
            len += 3 * w;
        }
        @memcpy(rule_buf[ri][len..][0..m[2].len], m[2]);
        len += m[2].len;
        rules[ri] = app.fmt("{s}", .{rule_buf[ri][0..len]});
    }
    const gx: u16 = 2;
    _ = put(box, gx, 4, rules[0], line);
    _ = put(box, gx, 5, "│", line);
    var cx: u16 = gx + 1;
    var col_x: [6]u16 = undefined;
    for (widths, 0..) |w, k| {
        col_x[k] = cx;
        _ = put(box, cx, 5, app.fmt(" {s}", .{heads[k]}), theme.onBold(theme.bright, theme.panel));
        _ = put(box, cx + w, 5, "│", line);
        cx += w + 1;
    }
    _ = put(box, gx, 6, rules[1], line);
    var r: usize = first;
    while (r < last) : (r += 1) {
        const y: u16 = @intCast(7 + r - first);
        const c = cols[r];
        const selrow = r == app.sq_row;
        _ = put(box, gx, y, "│", line);
        const texts = [6][]const u8{
            app.fmt("{d}", .{r + 1}),
            app.fmt("{s}", .{c.nameS()}),
            app.fmt("{s}", .{c.typeS()}),
            if (c.notnull) "[x]" else "[ ]",
            if (c.pk) "[x]" else "[ ]",
            app.fmt("{s}", .{c.defaultS()}),
        };
        for (widths, 0..) |w, k| {
            const sel_cell = selrow and k > 0 and app.sq_col == k - 1;
            const bg = if (sel_cell) theme.bar else if (selrow) theme.selected else theme.panel;
            const cell = sub(box, col_x[k], y, w, 1);
            fillWith(cell, bg);
            if (app.sq_editing and sel_cell) {
                app.sq_edit.drawWithStyle(cell, theme.on(theme.bright, theme.bar));
            } else {
                _ = put(cell, 1, 0, clipText(texts[k], w -| 2), theme.on(if (sel_cell) theme.bright else theme.text, bg));
            }
            if (k == 2) {
                _ = put(cell, w -| 2, 0, "▾", theme.onBold(theme.amber, bg));
                try addHit(app, box, col_x[k] + w -| 2, y, 2, 1, .sq_drop_open);
            }
            if (k > 0) try addHit(app, box, col_x[k], y, if (k == 2) w -| 2 else w, 1, .{ .sq_cell = .{ .row = @intCast(r), .col = @intCast(k - 1) } });
            _ = put(box, col_x[k] + w, y, "│", line);
        }
    }
    _ = put(box, gx, @intCast(7 + last - first), rules[2], line);
    const changes = app.sqChanges();
    _ = put(box, 2, 20, if (changes == 0) "no changes yet" else app.fmt("{d} change(s) pending: Apply rebuilds the table", .{changes}), theme.on(theme.amber, theme.panel));
    if (app.sq_error) |e| _ = put(box, 2, 21, clipText(e, box.width -| 4), theme.on(theme.red, theme.panel));
    if (app.sq_new) {
        try buttonRow(app, box, box.height -| 4, &.{
            .{ .label = "+ Add field", .action = .{ .sq_btn = .add } },
            .{ .label = "− Remove field", .action = .{ .sq_btn = .remove } },
        });
        try wizardButtons(app, box);
    } else {
        try buttonRow(app, box, box.height -| 4, &.{
            .{ .label = "◄ Previous page", .action = .{ .sq_btn = .prev } },
            .{ .label = "Next page ►", .action = .{ .sq_btn = .next } },
            .{ .label = "+ Add field", .action = .{ .sq_btn = .add } },
            .{ .label = "− Remove field", .action = .{ .sq_btn = .remove } },
        });
        try buttonRow(app, box, box.height -| 2, &.{
            .{ .label = "Apply", .action = .{ .sq_btn = .apply }, .primary = true, .enabled = changes > 0 },
            .{ .label = "Cancel", .action = .close_overlay },
        });
    }
    if (app.sq_drop) {
        const dw: u16 = 22;
        const dh: u16 = @intCast(sqlstruct.types.len + 2);
        const dx = col_x[2];
        const dy: u16 = @intCast(7 + app.sq_row - first + 1);
        solid(app, box, dx, dy, dw, dh);
        const dbox = boxed(box, dx, dy, dw, dh, theme.blue);
        fillWith(dbox, theme.panel);
        for (sqlstruct.types, 0..) |t, i| {
            const sel = i == app.sq_drop_sel;
            const bg = if (sel) theme.selected else theme.panel;
            const row = sub(dbox, 0, @intCast(i), dbox.width, 1);
            fillWith(row, bg);
            _ = put(row, 1, 0, t, theme.on(if (sel) theme.bright else theme.text, bg));
            try addHit(app, dbox, 0, @intCast(i), dbox.width, 1, .{ .sq_pick = @intCast(i) });
        }
    }
}
