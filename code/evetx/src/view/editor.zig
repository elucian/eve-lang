//! @eve-module evetx.view.editor
//! @feature F-TLS-24
//! @decision D-173
//! @see code/evetx/src/view.zig:draw
//! The code editor window and its scroll bars.
const std = @import("std");
const vaxis = @import("vaxis");
const Window = vaxis.Window;
const app_mod = @import("../app.zig");
const App = app_mod.App;
const theme = @import("../theme.zig");
const ide = @import("ide");
const text = ide.text;
const scan = ide.scan;
const Style = theme.Style;
const syntax_m = @import("syntax.zig");
const widgets_m = @import("widgets.zig");
const sub = widgets_m.sub;
const fillWith = widgets_m.fillWith;
const put = widgets_m.put;
const absRect = widgets_m.absRect;
const addHit = widgets_m.addHit;
const drawSelection = syntax_m.drawSelection;
const drawCode = syntax_m.drawCode;
const drawSql = syntax_m.drawSql;

/// The line with its tabs spread into spaces.
pub fn expandTabs(app: *App, line: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, line, '\t') == null) return line;
    const a = app.frame.allocator();
    var out: std.ArrayList(u8) = .empty;
    var col: usize = 0;
    for (line) |c| {
        if (c == '\t') {
            const w = text.Buffer.tab_width - col % text.Buffer.tab_width;
            out.appendNTimes(a, ' ', w) catch return line;
            col += w;
        } else {
            out.append(a, c) catch return line;
            if ((c & 0xC0) != 0x80) col += 1;
        }
    }
    return out.items;
}

/// Show the spaces, tabs and the line end of one line.
pub fn drawHidden(cw: Window, line: []const u8, left: usize, cols: usize, eol: []const u8, style: Style) void {
    var col: usize = 0;
    var i: usize = 0;
    while (i < line.len) {
        const c = line[i];
        const w: usize = if (c == '\t') text.Buffer.tab_width - col % text.Buffer.tab_width else 1;
        if (col >= left and col < left + cols) {
            if (c == ' ') _ = put(cw, @intCast(col - left), 0, "·", style);
            if (c == '\t') _ = put(cw, @intCast(col - left), 0, "→", style);
        }
        i += std.unicode.utf8ByteSequenceLength(c) catch 1;
        col += w;
    }
    if (col >= left and col < left + cols) _ = put(cw, @intCast(col - left), 0, eol, style);
}

/// The largest first line that the editor can show.
pub fn maxTop(b: *const text.Buffer, rows: usize, cols: usize, wrap: bool) usize {
    if (!wrap) return (b.lineCount() + 3) -| rows;
    if (rows <= 3) return b.lineCount() - 1;
    var used: usize = 0;
    var ln = b.lineCount();
    while (ln > 0) {
        ln -= 1;
        used += text.Buffer.segRows(b.lineAt(ln), cols);
        if (used >= rows - 3) return ln;
    }
    return 0;
}

pub fn followWrap(b: *text.Buffer, rows: usize, cols: usize) void {
    if (rows == 0 or cols == 0) return;
    b.left = 0;
    if (b.row < b.top) b.top = b.row;
    if (b.row - b.top >= rows) b.top = b.row + 1 - rows;
    const cur = b.lineAt(b.row);
    const seg = @min(b.displayCol() / cols, text.Buffer.segRows(cur, cols) - 1);
    while (b.top < b.row) {
        var used: usize = 0;
        var ln = b.top;
        while (ln < b.row) : (ln += 1) used += text.Buffer.segRows(b.lineAt(ln), cols);
        if (used + seg < rows) break;
        b.top += 1;
    }
}

pub fn editor(app: *App, ed: Window, tab: *app_mod.Tab, b: *text.Buffer) !void {
    var digits: u16 = 1;
    var n = b.lineCount();
    while (n >= 10) : (n /= 10) digits += 1;
    const gutter: u16 = digits + 3;
    const wrap = app.wrap;
    const rows = if (wrap) ed.height else ed.height -| 1;
    const cols = ed.width -| gutter -| 1;
    if (app.follow) {
        if (wrap) followWrap(b, rows, cols) else b.follow(rows, cols);
        app.follow = false;
    }
    if (wrap) b.left = 0;
    b.top = @min(b.top, maxTop(b, rows, cols, wrap));
    const code = sub(ed, gutter, 0, cols, rows);
    app.editor_rect = absRect(ed, gutter, 0, cols, rows);
    app.gutter_rect = absRect(ed, 0, 0, gutter, rows);
    const focused = app.focus == .editor and app.overlay == .none;

    var r: u16 = 0;
    var ln: usize = b.top;
    var lines_shown: usize = 0;
    var line_prev: []const u8 = "";
    // the state of comments at the first visible line, then line by line (a `/* ... */` may span lines)
    var carry: scan.Carry = if (tab.eve and !tab.sql) scan.carryAt(b, ln) else .none;
    while (r < rows and ln < b.lineCount()) : ({
        ln += 1;
        carry = scan.carryAfter(line_prev, carry);
    }) {
        const line = b.lineAt(ln);
        line_prev = line;
        const pieces: usize = if (wrap) text.Buffer.segRows(line, cols) else 1;
        const is_cur = ln == b.row;
        // the line where the debugger stopped the program has its own background and an arrow in the gutter
        const stopped = app.debugLine(tab.path) == ln + 1;
        const row_bg = if (stopped) theme.sel_bg else if (is_cur and focused) theme.bar2 else theme.deep;
        var seg: usize = 0;
        while (seg < pieces and r < rows) : ({
            seg += 1;
            r += 1;
        }) {
            const left: usize = if (wrap) seg * cols else b.left;
            const line_win = sub(ed, 0, r, ed.width, 1);
            fillWith(line_win, row_bg);
            if (seg == 0) {
                if (app.breakpointState(tab.path, ln + 1)) |on| _ = put(line_win, 0, 0, "●", theme.on(if (on) theme.red else theme.faint, row_bg));
                if (stopped) _ = put(line_win, 0, 0, "▶", theme.onBold(theme.amber, row_bg));
                const num = app.fmt("{d}", .{ln + 1});
                _ = put(line_win, gutter - 2 - @as(u16, @intCast(num.len)), 0, num, theme.on(if (is_cur) theme.bright else theme.dim, row_bg));
            }
            // `shown` is the line with its tabs spread into spaces: one cell for every character
            const shown = expandTabs(app, line);
            const start = text.Buffer.byteAtDisplay(shown, left);
            const cw = sub(code, 0, r, cols, 1);
            if (tab.sql) drawSql(cw, shown, start, row_bg) else drawCode(cw, shown, start, tab.eve, row_bg, carry);
            if (b.selection()) |sel| drawSelection(cw, line, shown, ln, sel, left);
            if (b.match) |m| {
                if (m.row == ln) {
                    const mc = text.Buffer.displayWidth(line[0..m.col]);
                    if (mc >= left) {
                        const ec = text.Buffer.displayWidth(line[0..@min(line.len, m.col + m.len)]);
                        const sb = text.Buffer.byteAtDisplay(shown, mc);
                        const eb = text.Buffer.byteAtDisplay(shown, ec);
                        _ = put(cw, @intCast(mc - left), 0, shown[sb..eb], theme.on(theme.deep, theme.amber));
                    }
                }
            }
            if (app.show_hidden) drawHidden(cw, line, left, cols, if (b.crlf) "␍↵" else "↵", theme.on(theme.faint, row_bg));
            if (focused and is_cur) {
                const dc = b.displayCol();
                const here: usize = if (wrap) @min(dc / cols, pieces - 1) else 0;
                if (!wrap or here == seg) {
                    const cc = if (wrap) @min(dc - seg * cols, cols - 1) else if (dc >= left) dc - left else cols;
                    if (cc < cols) code.showCursor(@intCast(cc), r);
                }
            }
        }
        lines_shown += 1;
    }
    scrollBars(app, ed, b, rows, cols, lines_shown);
}

pub const glyph_v_track = "░";
pub const glyph_v_thumb = "█";
pub const glyph_h_track = "░";
pub const glyph_h_thumb = "█";
pub const glyph_up = "▲";
pub const glyph_down = "▼";
pub const glyph_left = "◀";
pub const glyph_right = "▶";

/// The vertical bar at the right of the text and, unless the text wraps, the horizontal bar under it.
/// The rectangles of the tracks are saved in the app for the mouse.
pub fn scrollBars(app: *App, ed: Window, b: *text.Buffer, rows: u16, cols: u16, lines_shown: usize) void {
    app.vbar_rect = .{};
    app.hbar_rect = .{};
    if (rows < 6 or cols < 6) return;
    const v_track = theme.on(theme.faint, theme.deep);
    const h_track = theme.on(theme.faint, theme.deep);
    const thumb = theme.on(theme.dim, theme.deep);
    const btn = theme.onBold(theme.text, theme.bar2);

    // the vertical bar: ▲ in the first row of the text, the track, ▼ in the last
    const vx = ed.width - 1;
    const total = b.lineCount() + 3; // the text may scroll up until three empty rows are left
    const y0: u16 = 1;
    const span: u16 = rows - 2;
    _ = put(ed, vx, 0, glyph_up, btn);
    addHit(app, ed, vx, 0, 1, 1, .{ .scroll = .up }) catch {};
    _ = put(ed, vx, rows - 1, glyph_down, btn);
    addHit(app, ed, vx, rows - 1, 1, 1, .{ .scroll = .down }) catch {};
    app.vbar_rect = absRect(ed, vx, y0, 1, span);
    var y: u16 = 0;
    while (y < span) : (y += 1) _ = put(ed, vx, y0 + y, glyph_v_track, v_track);
    {
        const visible: usize = if (app.wrap) @max(1, lines_shown) else rows;
        const th: usize = if (total > visible) @max(1, @as(usize, span) * visible / total) else span;
        const above = @min(b.top, total -| visible);
        const ty: usize = if (total > visible) (span - th) * above / (total - visible) else 0;
        var k: usize = 0;
        while (k < th) : (k += 1) _ = put(ed, vx, y0 + @as(u16, @intCast(ty + k)), glyph_v_thumb, thumb);
    }
    if (app.wrap) return;

    // the horizontal bar: ◀, the track, ▶, from the left edge of the editor to the vertical bar
    const hy = ed.height - 1;
    var content: usize = b.left + cols;
    var r: usize = b.top;
    while (r < b.lineCount() and r < b.top + rows) : (r += 1) content = @max(content, text.Buffer.displayWidth(b.lineAt(r)) + 1);
    app.hbar_content = content;
    _ = put(ed, 0, hy, glyph_left, btn);
    addHit(app, ed, 0, hy, 1, 1, .{ .scroll = .left }) catch {};
    _ = put(ed, vx - 1, hy, glyph_right, btn);
    addHit(app, ed, vx - 1, hy, 1, 1, .{ .scroll = .right }) catch {};
    const hw = vx - 2;
    app.hbar_rect = absRect(ed, 1, hy, hw, 1);
    var x: u16 = 0;
    while (x < hw) : (x += 1) _ = put(ed, 1 + x, hy, glyph_h_track, h_track);
    const tw: usize = if (content > cols) @max(1, @as(usize, hw) * cols / content) else hw;
    const tx: usize = if (content > cols) (hw - tw) * @min(b.left, content - cols) / (content - cols) else 0;
    var k: usize = 0;
    while (k < tw) : (k += 1) _ = put(ed, 1 + @as(u16, @intCast(tx + k)), hy, glyph_h_thumb, thumb);
}
