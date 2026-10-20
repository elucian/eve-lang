//! @eve-module evetx.view.sidebar
//! @feature F-TLS-24
//! @decision D-173
//! @see code/evetx/src/view.zig:draw
//! The files tree panel and the scroll bars.
const std = @import("std");
const vaxis = @import("vaxis");
const Window = vaxis.Window;
const app_mod = @import("../app.zig");
const App = app_mod.App;
const Action = app_mod.Action;
const Rect = app_mod.Rect;
const theme = @import("../theme.zig");
const ide = @import("ide");
const Style = theme.Style;
const editor_m = @import("editor.zig");
const find_dialogs_m = @import("find_dialogs.zig");
const view_m = @import("../view.zig");
const widgets_m = @import("widgets.zig");
const sub = widgets_m.sub;
const fillWith = widgets_m.fillWith;
const put = widgets_m.put;
const absRect = widgets_m.absRect;
const addHit = widgets_m.addHit;
const clipText = view_m.clipText;
const panelBox = view_m.panelBox;
const titleButtons = view_m.titleButtons;
const glyph_v_track = editor_m.glyph_v_track;
const glyph_v_thumb = editor_m.glyph_v_thumb;
const glyph_h_track = editor_m.glyph_h_track;
const glyph_h_thumb = editor_m.glyph_h_thumb;
const glyph_up = editor_m.glyph_up;
const glyph_down = editor_m.glyph_down;
const glyph_left = editor_m.glyph_left;
const glyph_right = editor_m.glyph_right;
const repeat = find_dialogs_m.repeat;

pub const vbar = "│  ";
pub const blank = "   ";
pub const tee = "├─ ";
pub const corner = "└─ ";

/// Does `name` end with one of the endings?
pub fn hasExt(name: []const u8, endings: []const []const u8) bool {
    for (endings) |end| {
        if (name.len > end.len and std.ascii.eqlIgnoreCase(name[name.len - end.len ..], end)) return true;
    }
    return false;
}

/// The picture of an entry: a folder (open or closed) or a file, by its kind.
pub fn iconOf(e: ide.project.Entry) []const u8 {
    if (e.kind == .table) return "▦";
    if (e.kind == .db) return if (e.expanded) "💽" else "💾";
    if (e.is_dir) return if (e.expanded) "📂" else "📁";
    if (hasExt(e.name, &.{ ".db", ".duckdb", ".sqlite", ".sqlite3", ".dbf" })) return "💾";
    if (e.name.len > 4 and std.ascii.eqlIgnoreCase(e.name[e.name.len - 4 ..], ".eve")) return "📜";
    return "📄";
}

/// Draw `s` in one style at virtual column `vc` of a tree row, scrolled by `left`; `vc` moves to the end of `s`.
pub fn putScrolled(row: Window, vc: *usize, left: usize, width: usize, s: []const u8, style: Style) void {
    var it = (std.unicode.Utf8View.init(s) catch return).iterator();
    while (it.nextCodepointSlice()) |ch| {
        const w: usize = row.gwidth(ch);
        if (vc.* >= left and vc.* - left + w <= width) _ = put(row, @intCast(vc.* - left), 0, ch, style);
        vc.* += w;
    }
}

/// A vertical bar in column `x` of `win`, `h` rows tall.
pub fn vBar(app: *App, win: Window, x: u16, h: u16, total: usize, top: usize, visible: usize, up: Action, down: Action, flush: bool) Rect {
    const track = theme.on(theme.faint, theme.deep);
    const btn = theme.onBold(theme.text, theme.bar2);
    // a tall bar has a free row above the arrow; a short one (3 to 5 rows) has the arrows at its two ends
    const tall = h >= 6 and !flush;
    const buttons = h >= 3;
    const up_row: u16 = if (tall) 1 else 0;
    const y0: u16 = if (tall) 2 else if (buttons) 1 else 0;
    const span: u16 = if (tall) h - 3 else if (buttons) h - 2 else h;
    if (buttons) {
        _ = put(win, x, up_row, glyph_up, btn);
        addHit(app, win, x, up_row, 1, 1, up) catch {};
        _ = put(win, x, h - 1, glyph_down, btn);
        addHit(app, win, x, h - 1, 1, 1, down) catch {};
    }
    var y: u16 = 0;
    while (y < span) : (y += 1) _ = put(win, x, y0 + y, glyph_v_track, track);
    const th: usize = if (total > visible) @max(1, @as(usize, span) * visible / total) else span;
    const above = @min(top, total -| visible);
    const ty: usize = if (total > visible) (span - th) * above / (total - visible) else 0;
    var k: usize = 0;
    while (k < th) : (k += 1) _ = put(win, x, y0 + @as(u16, @intCast(ty + k)), glyph_v_thumb, theme.on(theme.dim, theme.deep));
    return absRect(win, x, y0, 1, span);
}

pub fn setPbar(app: *App, kind: app_mod.PbarKind, r: Rect, total: usize, visible: usize) void {
    app.pbar_rect = r;
    app.pbar_kind = kind;
    app.pbar_total = total;
    app.pbar_visible = visible;
}

/// A horizontal bar in row `y` of `win`, `w` cells wide, with ◀ and ▶ at the ends.
pub fn hBar(app: *App, win: Window, y: u16, w: u16, total: usize, left: usize, visible: usize, lft: Action, rgt: Action) Rect {
    const track = theme.on(theme.faint, theme.deep);
    const btn = theme.onBold(theme.text, theme.bar2);
    if (w < 6) return .{};
    _ = put(win, 0, y, glyph_left, btn);
    addHit(app, win, 0, y, 1, 1, lft) catch {};
    _ = put(win, w - 1, y, glyph_right, btn);
    addHit(app, win, w - 1, y, 1, 1, rgt) catch {};
    const hw = w - 2;
    var x: u16 = 0;
    while (x < hw) : (x += 1) _ = put(win, 1 + x, y, glyph_h_track, track);
    const tw: usize = if (total > visible) @max(1, @as(usize, hw) * visible / total) else hw;
    const tx: usize = if (total > visible) (hw - tw) * @min(left, total - visible) / (total - visible) else 0;
    var k: usize = 0;
    while (k < tw) : (k += 1) _ = put(win, 1 + @as(u16, @intCast(tx + k)), y, glyph_h_thumb, theme.on(theme.dim, theme.deep));
    return absRect(win, 1, y, hw, 1);
}

pub fn sidebar(app: *App, win: Window, place: Rect) !void {
    if (place.w == 0) return;
    const focused = app.overlay == .none and app.focus == .tree;
    const box = try panelBox(app, win, place, .tree);
    fillWith(box, theme.deep);
    const bar = sub(box, 0, 0, box.width, 1);
    fillWith(bar, theme.bar2);
    const title = if (app.project_name.len > 0) app.fmt(" Files · {s}", .{app.project_name}) else " Files";
    _ = put(bar, 0, 0, clipText(title, box.width -| 5), theme.onBold(if (focused) theme.bright else theme.dim, theme.bar2));
    try titleButtons(app, box, .tree);
    _ = put(box, 0, 1, repeat("─", 400), theme.on(theme.line, theme.deep));
    // the foot of the panel: a thin line and the machine that evetx works with (more machines come with level 7)
    const foot = box.height > 8;
    if (foot) {
        _ = put(box, 0, box.height - 2, repeat("─", 400), theme.on(theme.line, theme.deep));
        _ = put(box, 1, box.height - 1, "● local", theme.on(theme.green, theme.deep));
    }
    const list = sub(box, 0, 2, box.width, box.height -| (if (foot) @as(u16, 4) else @as(u16, 2)));

    try app.tree.visibleRows(app.gpa, &app.visible);
    const total = app.visible.items.len;
    var content: usize = 0;
    for (app.visible.items) |vi| {
        const e = app.tree.entries.items[vi];
        content = @max(content, 1 + 3 * @as(usize, e.depth) + 3 + list.gwidth(e.name));
    }
    app.tree_content = content;
    var need_v = total > list.height;
    const need_h = content > list.width -| @intFromBool(need_v);
    if (need_h and !need_v) need_v = total > list.height -| 1;
    const rows_h: u16 = list.height -| @intFromBool(need_h);
    const text_w: u16 = list.width -| @intFromBool(need_v);
    app.tree_rect = absRect(list, 0, 0, text_w, rows_h);

    var sel_pos: usize = 0;
    for (app.visible.items, 0..) |v, i| {
        if (v == app.selected) sel_pos = i;
    }
    if (app.tree_follow) {
        if (sel_pos < app.tree_top) app.tree_top = sel_pos;
        if (sel_pos >= app.tree_top + rows_h) app.tree_top = sel_pos + 1 - rows_h;
        app.tree_follow = false;
    }
    if (total > rows_h) app.tree_top = @min(app.tree_top, total - rows_h) else app.tree_top = 0;
    app.tree_left = if (content > text_w) @min(app.tree_left, content - text_w) else 0;
    const left = app.tree_left;

    const q: []const u8 = if (app.overlay == .find_file) try app.files_in.toOwnedContents(app.frame.allocator()) else "";
    const lines = theme.on(theme.faint, theme.deep);

    var r: u16 = 0;
    while (r < rows_h and app.tree_top + r < total) : (r += 1) {
        const idx = app.visible.items[app.tree_top + r];
        const e = app.tree.entries.items[idx];
        const is_sel = idx == app.selected;
        const marked = app.isMarked(e.path);
        const drop_here = app.tdrag_active and app.tdrag_over == idx;
        const bg = if (drop_here) theme.green_bg else if (is_sel) (if (focused or app.overlay == .find_file) theme.selected else theme.bar) else if (marked) theme.sel_bg else theme.deep;
        const row = sub(list, 0, r, text_w, 1);
        fillWith(row, bg);
        const line_style = if (is_sel) theme.on(theme.dim, bg) else lines;
        var vc: usize = 1;
        if (e.parent) |parent| {
            var chain: [16]u32 = undefined;
            var n: usize = 0;
            var cur: ?u32 = parent;
            while (cur) |p| : (cur = app.tree.entries.items[p].parent) {
                if (n < chain.len) {
                    chain[n] = p;
                    n += 1;
                }
            }
            var k = n;
            while (k > 1) : (k -= 1) {
                putScrolled(row, &vc, left, text_w, if (app.tree.isLast(chain[k - 2])) blank else vbar, line_style);
            }
            putScrolled(row, &vc, left, text_w, if (app.tree.isLast(idx)) corner else tee, line_style);
        }
        const folder_color = if (is_sel) theme.bright else theme.amber;
        putScrolled(row, &vc, left, text_w, iconOf(e), theme.on(folder_color, bg));
        vc += 1;
        const color = if (is_sel) theme.bright else if (std.mem.eql(u8, e.name, "eve.env")) theme.dim else if (e.is_dir) theme.bright else theme.text;
        if (q.len > 0 and e.parent != null and e.name.len >= q.len and std.ascii.eqlIgnoreCase(e.name[0..q.len], q)) {
            putScrolled(row, &vc, left, text_w, e.name[0..q.len], theme.onBold(theme.amber, bg));
            putScrolled(row, &vc, left, text_w, e.name[q.len..], theme.on(color, bg));
        } else {
            putScrolled(row, &vc, left, text_w, e.name, if (e.is_dir) theme.onBold(color, bg) else theme.on(color, bg));
        }
        if (e.is_dir and e.depth == 1 and isServerSide(e.name)) _ = put(row, text_w -| 3, 0, "●", theme.on(theme.blue, bg));
        try addHit(app, list, 0, r, text_w, 1, .{ .tree_row = idx });
    }

    app.tvbar_rect = .{};
    app.thbar_rect = .{};
    if (need_v) app.tvbar_rect = vBar(app, list, list.width - 1, rows_h, total, app.tree_top, rows_h, .{ .tree_scroll = .up }, .{ .tree_scroll = .down }, true);
    if (need_h) app.thbar_rect = hBar(app, list, list.height - 1, text_w, content, left, text_w, .{ .tree_scroll = .left }, .{ .tree_scroll = .right });
}

pub fn isServerSide(name: []const u8) bool {
    for ([_][]const u8{ "proc", "sql", "web", "server" }) |s| {
        if (std.mem.eql(u8, name, s)) return true;
    }
    return false;
}
