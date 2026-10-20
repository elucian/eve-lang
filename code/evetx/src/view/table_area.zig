//! @eve-module evetx.view.table_area
//! @feature F-TLS-24
//! @decision D-173
//! @see code/evetx/src/view.zig:draw
//! The grid of a table window.
const std = @import("std");
const vaxis = @import("vaxis");
const Window = vaxis.Window;
const app_mod = @import("../app.zig");
const App = app_mod.App;
const theme = @import("../theme.zig");
const ide = @import("ide");
const grid = ide.grid;
const text = ide.text;
const dialogs_m = @import("dialogs.zig");
const find_dialogs_m = @import("find_dialogs.zig");
const main_panel_m = @import("main_panel.zig");
const sidebar_m = @import("sidebar.zig");
const view_m = @import("../view.zig");
const widgets_m = @import("widgets.zig");
const sub = widgets_m.sub;
const fillWith = widgets_m.fillWith;
const put = widgets_m.put;
const putRight = widgets_m.putRight;
const absRect = widgets_m.absRect;
const addHit = widgets_m.addHit;
const field = widgets_m.field;
const clipText = view_m.clipText;
const hasExt = sidebar_m.hasExt;
const vBar = sidebar_m.vBar;
const setPbar = sidebar_m.setPbar;
const hBar = sidebar_m.hBar;
const dateText = main_panel_m.dateText;
const dialog = dialogs_m.dialog;
const repeat = find_dialogs_m.repeat;

/// The Main Panel shows the content of a folder: icon, name, description, date made, size in KB.
pub fn folderArea(app: *App, ed: Window, fv: *app_mod.FolderView) !void {
    const dim = theme.on(theme.dim, theme.deep);
    const head = theme.onBold(theme.bright, theme.bar2);
    const w: usize = ed.width;
    const size_w: usize = 11;
    const date_w: usize = 17;
    const desc_w: usize = 22;
    const fixed = 4 + desc_w + date_w + size_w + 4;
    const name_w: usize = if (w > fixed + 12) w - fixed else 12;
    const x_desc: u16 = @intCast(4 + name_w + 1);
    const x_date: u16 = @intCast(x_desc + desc_w + 1);
    const x_size: u16 = @intCast(x_date + date_w + 1);
    fillWith(sub(ed, 0, 0, ed.width, 1), theme.bar2);
    _ = put(ed, 1, 0, "Name", head);
    _ = put(ed, x_desc, 0, "Description", head);
    _ = put(ed, x_date, 0, "Created (UTC)", head);
    _ = put(ed, x_size, 0, "Size", head);
    _ = put(ed, 0, 1, repeat("─", 400), theme.on(theme.line, theme.deep));
    const rows: usize = ed.height -| 2;
    if (rows == 0) return;
    if (fv.sel < fv.top) fv.top = fv.sel;
    if (fv.sel >= fv.top + rows) fv.top = fv.sel + 1 - rows;
    const n = fv.items.items.len;
    if (n == 0) _ = put(ed, 2, 3, "This folder is empty.", dim);
    var r: usize = 0;
    while (r < rows and fv.top + r < n) : (r += 1) {
        const i = fv.top + r;
        const it = fv.items.items[i];
        const sel = i == fv.sel;
        const marked = !std.mem.eql(u8, it.name, "..") and app.isMarked(app.fmt("{s}{s}{s}", .{ fv.dir, if (fv.dir.len > 0) "/" else "", it.name }));
        const bg = if (sel) theme.selected else if (marked) theme.sel_bg else theme.deep;
        const y: u16 = @intCast(2 + r);
        fillWith(sub(ed, 0, y, ed.width, 1), bg);
        if (marked) _ = put(ed, 0, y, "+", theme.onBold(theme.green, bg));
        _ = put(ed, 1, y, if (it.is_dir) "📁" else tabIconOfName(it.name), theme.on(theme.amber, bg));
        const fg = if (sel) theme.bright else if (it.is_dir) theme.bright else theme.text;
        _ = put(ed, 4, y, clipText(it.name, name_w), if (it.is_dir) theme.onBold(fg, bg) else theme.on(fg, bg));
        _ = put(ed, x_desc, y, clipText(app_mod.describeName(it.name, it.is_dir), desc_w), theme.on(theme.dim, bg));
        _ = put(ed, x_date, y, dateText(app, it.created), theme.on(theme.dim, bg));
        if (!it.is_dir) {
            const kb = app.fmt("{d}.{d} KB", .{ it.size / 1024, (it.size % 1024) * 10 / 1024 });
            putRight(ed, @intCast(x_size + size_w), y, kb, theme.on(theme.text, bg));
        }
        try addHit(app, ed, 0, y, ed.width -| 1, 1, .{ .folder_row = i });
    }
    if (n > rows) setPbar(app, .folder, vBar(app, ed, ed.width - 1, ed.height, n, fv.top, rows, .{ .folder_scroll = .up }, .{ .folder_scroll = .down }, false), n, rows);
}

/// The icon for a file name (the same as the tree and the tabs).
pub fn tabIconOfName(name: []const u8) []const u8 {
    if (hasExt(name, &.{ ".db", ".duckdb", ".sqlite", ".sqlite3", ".dbf" })) return "💾";
    if (hasExt(name, &.{".eve"})) return "📜";
    return "📄";
}

/// The width a field asks for in the grid of a table.
pub fn naturalWidth(f: *const grid.Field) u16 {
    return @intCast(std.math.clamp(@max(f.name.len, f.width), 4, 254));
}

/// The widths of the columns of a table for `room` cells; also says whether all of them fit.
pub fn columnWidths(app: *App, t: *const grid.Table, room: usize) struct { widths: []u16, fit: bool } {
    const widths = app.frame.allocator().alloc(u16, t.fields.len) catch return .{ .widths = &.{}, .fit = true };
    var total: usize = 0;
    for (t.fields, widths) |*f, *w| {
        w.* = naturalWidth(f);
        total += w.* + 1;
    }
    if (total > room) {
        var spare: usize = 0;
        for (widths) |w| spare += w -| 12;
        const cut_by = @min(total - room, spare);
        if (spare > 0) {
            total = 0;
            for (widths) |*w| {
                const above: usize = w.* -| 12;
                w.* -= @intCast((above * cut_by + spare - 1) / spare);
                total += w.* + 1;
            }
        }
    }
    return .{ .widths = widths, .fit = total <= room };
}

/// The Main Panel shows a table: `#`, the names of the fields, then the records, with scroll bars.
pub fn tableArea(app: *App, ed: Window, tv: *app_mod.TableView) void {
    const t = &tv.t;
    app.tbl_rect = .{};
    app.tbl_widths = &.{};
    const dim = theme.on(theme.dim, theme.deep);
    if (t.fields.len == 0) {
        _ = put(ed, 2, 1, "This table has no fields yet.", theme.on(theme.text, theme.deep));
        _ = put(ed, 2, 2, "SQL:> alter table <name>  opens the dialog where you make them.", dim);
        return;
    }
    const num_w = app_mod.rownumW(t.records);
    const num_d = app_mod.rownumDigits(t.records);
    // the room for the fields: the width less the record numbers and the vertical scroll bar
    const room: usize = (ed.width -| 1) -| num_w;
    const cw = columnWidths(app, t, room);
    const widths = cw.widths;
    if (widths.len != t.fields.len) return;
    app.tbl_widths = widths;
    const need_h = !cw.fit;
    const body_h: u16 = ed.height -| 2 -| @as(u16, if (need_h) 1 else 0);
    if (body_h == 0) return;
    // keep the selected cell on the screen
    if (tv.row < tv.top) tv.top = tv.row;
    if (tv.row >= tv.top + body_h) tv.top = tv.row + 1 - body_h;
    if (tv.col < tv.left) tv.left = tv.col;
    while (tv.left < tv.col) {
        var used: usize = 0;
        for (widths[tv.left .. tv.col + 1]) |w| used += w + 1;
        if (used <= room) break;
        tv.left += 1;
    }
    const line = theme.on(theme.line, theme.deep);
    // the header: `#`, then the names of the fields; the rule under it crosses the separators
    const head = theme.onBold(theme.bright, theme.bar2);
    const head_line = theme.on(theme.line, theme.bar2);
    fillWith(sub(ed, 0, 0, ed.width, 1), theme.bar2);
    _ = put(ed, (num_w - 1 -| 4) / 2, 0, "rec#", head);
    _ = put(ed, num_w - 1, 0, "│", head_line);
    _ = put(ed, 0, 1, repeat("─", 400), line);
    _ = put(ed, num_w - 1, 1, "┼", line);
    var x: u16 = num_w;
    var shown: usize = 0;
    var c = tv.left;
    while (c < t.fields.len) : (c += 1) {
        const w = widths[c];
        if (x + w > ed.width -| 1) break;
        const sel = c == tv.col;
        _ = put(ed, x, 0, app.fmt("{s}", .{clipText(t.fields[c].nameSlice(), w)}), if (sel) theme.onBold(theme.deep, theme.blue) else head);
        _ = put(ed, x + w, 0, "│", head_line);
        _ = put(ed, x + w, 1, "┼", line);
        x += w + 1;
        shown += 1;
    }
    // the records
    const body = sub(ed, 0, 2, ed.width, body_h);
    app.tbl_rect = absRect(ed, 0, 2, ed.width -| 1, body_h);
    var r: u16 = 0;
    while (r < body_h) : (r += 1) {
        const idx = tv.top + r;
        const odd = idx % 2 == 1;
        const cur = idx == tv.row and idx < t.records;
        const marked = tv.sel.contains(idx);
        const row_bg = if (cur) theme.bar2 else if (marked) theme.bar else if (odd) theme.panel else theme.deep;
        fillWith(sub(body, 0, r, body.width, 1), row_bg);
        const sep = theme.on(theme.line, row_bg);
        // the separators go down to the bottom of the grid, so the columns stay drawn under the last record
        _ = put(body, num_w - 1, r, "│", sep);
        var sx: u16 = num_w;
        var k0 = tv.left;
        while (k0 < tv.left + shown) : (k0 += 1) {
            sx += widths[k0];
            _ = put(body, sx, r, "│", sep);
            sx += 1;
        }
        if (idx >= t.records) continue;
        const gone = t.deleted(idx);
        // the first cell is the selection column; the number is right aligned after it, red when the record is deleted
        if (marked) _ = put(body, 0, r, "+", theme.onBold(theme.green, row_bg));
        const num = app.fmt("{d}", .{idx + 1});
        _ = put(body, 1 + num_d -| @as(u16, @intCast(num.len)), r, num, theme.on(if (gone) theme.red else theme.faint, row_bg));
        var cx: u16 = num_w;
        var k = tv.left;
        while (k < tv.left + shown) : (k += 1) {
            const w = widths[k];
            var buf: [16]u8 = undefined;
            const shown_text = clipText(t.display(idx, k, &buf), w);
            // `buf` is on this frame's stack: the text is copied before `put` keeps a pointer to it
            const copy = app.fmt("{s}", .{shown_text});
            const bg = if (cur and k == tv.col) theme.sel_bg else row_bg;
            if (cur and k == tv.col and app.tbl_editing) {
                const cell = sub(body, cx, r, w, 1);
                fillWith(cell, theme.bar);
                app.tbl_edit.drawWithStyle(cell, theme.on(theme.bright, theme.bar));
                cx += w + 1;
                continue;
            }
            const style = if (cur and k == tv.col) theme.onBold(theme.bright, bg) else theme.on(if (gone) theme.faint else theme.text, bg);
            if (cur and k == tv.col) fillWith(sub(body, cx, r, w, 1), bg);
            _ = put(body, cx, r, copy, style);
            cx += w + 1;
        }
    }
    app.tbl_rows = body_h;
    app.tbl_cols = shown;
    if (t.records > body_h) app.tblv_rect = vBar(app, body, body.width - 1, body.height, t.records, tv.top, body_h, .{ .table_scroll = .up }, .{ .table_scroll = .down }, false);
    if (need_h) app.tblh_rect = hBar(app, ed, ed.height - 1, ed.width -| 1, t.fields.len, tv.left, shown, .{ .table_scroll = .left }, .{ .table_scroll = .right });
    if (t.records == 0) _ = put(ed, num_w + 1, 2, if (tv.readonly) "No rows." else "No records. The structure is changed with  SQL:> alter table <name>", dim);
}
