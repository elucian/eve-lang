//! Drawing: reads the state of `App` and draws the screen of design/design.svg. It also records
//! the clickable places (`app.hits`) and the areas that scroll, for the mouse.
const std = @import("std");
const vaxis = @import("vaxis");
const Window = vaxis.Window;
const TextInput = vaxis.widgets.TextInput;

const app_mod = @import("app.zig");
const App = app_mod.App;
const Action = app_mod.Action;
const Rect = app_mod.Rect;
const theme = @import("theme.zig");
const text = @import("text.zig");
const keywords = @import("keywords.zig");

const Style = theme.Style;

// ------------------------------------------------------------------ helpers

// Zig tip: `win.child(.{...})` makes a window that is a part of its parent: drawing outside it is
// clipped. `@intCast(x)` converts a `u16` to the wider signed type that libvaxis wants for the
// offset.
/// A child window at a place of `win`, without a border.
fn sub(win: Window, x: u16, y: u16, w: u16, h: u16) Window {
    return win.child(.{ .x_off = @intCast(x), .y_off = @intCast(y), .width = w, .height = h });
}

// Zig tip: A struct literal can nest another: `.border = .{ .where = .all, ... }`. `child` draws
// the border on the parent and returns the window inside it, one cell smaller on every side.
/// A child window with a one-cell border; the result is the inside.
fn boxed(win: Window, x: u16, y: u16, w: u16, h: u16, border: theme.Color) Window {
    return win.child(.{
        .x_off = @intCast(x),
        .y_off = @intCast(y),
        .width = w,
        .height = h,
        .border = .{ .where = .all, .glyphs = .single_square, .style = theme.on(border, theme.deep) },
    });
}

// Zig tip: `.{ .style = .{ .bg = bg } }` is a `Cell` with only its style written; the other fields
// take their defaults, so the cell is a space with that background.
fn fillWith(win: Window, bg: theme.Color) void {
    win.fill(.{ .style = .{ .bg = bg } });
}

// Zig tip: `printSegment` draws text from a column and row and returns where it stopped. The text
// must stay valid until the screen is rendered: libvaxis keeps the pointer, so strings are
// formatted into the frame arena.
/// Print `s` at (col, row) of `win` on one line; returns the column after it.
fn put(win: Window, col: u16, row: u16, s: []const u8, style: Style) u16 {
    const r = win.printSegment(.{ .text = s, .style = style }, .{ .col_offset = col, .row_offset = row, .wrap = .none });
    return r.col;
}

// Zig tip: `end -| w` is saturating subtraction: when the text is wider than the room, the column
// is 0 and not a crash.
/// Print `s` so that it ends at column `end` (right aligned).
fn putRight(win: Window, end: u16, row: u16, s: []const u8, style: Style) void {
    const w = win.gwidth(s);
    _ = put(win, end -| w, row, s, style);
}

// Zig tip: Window offsets are absolute cell positions. `@as(i32, win.x_off) + x` widens the signed
// offset first, then adds the `u16`; `@intCast` brings it back to `u16` for the rectangle.
fn absRect(win: Window, x: u16, y: u16, w: u16, h: u16) Rect {
    return .{ .x = @intCast(@as(i32, win.x_off) + x), .y = @intCast(@as(i32, win.y_off) + y), .w = w, .h = h };
}

// Zig tip: `try app.hits.append(app.gpa, ...)` can fail with out of memory, so the function
// returns `!void`. The list lives in the `App` and is emptied at the start of each frame.
fn addHit(app: *App, win: Window, x: u16, y: u16, w: u16, h: u16, action: Action) !void {
    try app.hits.append(app.gpa, .{ .rect = absRect(win, x, y, w, h), .action = action });
}

// Zig tip: The label is drawn between two spaces, and the same rectangle is registered as a hit.
// `x + w` is the column after the button, so buttons can be placed one after another.
/// A button: ` label ` on a background; clickable.
fn button(app: *App, win: Window, x: u16, y: u16, label: []const u8, style: Style, action: Action) !u16 {
    const w = win.gwidth(label) + 2;
    _ = put(win, x, y, " ", style);
    _ = put(win, x + 1, y, label, style);
    _ = put(win, x + 1 + win.gwidth(label), y, " ", style);
    try addHit(app, win, x, y, w, 1, action);
    return x + w;
}

// Zig tip: `ti: *TextInput` is the widget of libvaxis. Only the focused field is drawn with
// `drawWithStyle`, because that call also sets the cursor of the terminal and only one field can
// have it.
/// A one-line input field. The focused one shows its cursor; the others show their text.
fn field(app: *App, win: Window, x: u16, y: u16, w: u16, ti: *TextInput, which: app_mod.Focus, placeholder: []const u8) !void {
    if (w < 3) return;
    const f = sub(win, x, y, w, 1);
    const focused = app.focus == which and app.overlay == .none;
    fillWith(f, if (focused) theme.bar else theme.deep);
    if (focused) {
        ti.drawWithStyle(f, theme.on(theme.bright, theme.bar));
    } else {
        const first = ti.buf.firstHalf();
        const second = ti.buf.secondHalf();
        if (first.len + second.len == 0) {
            _ = put(f, 1, 0, placeholder, theme.on(theme.faint, theme.deep));
        } else {
            const c = put(f, 1, 0, first, theme.on(theme.text, theme.deep));
            _ = put(f, c, 0, second, theme.on(theme.text, theme.deep));
        }
    }
    try addHit(app, win, x, y, w, 1, .{ .field = which });
}

// ------------------------------------------------------------------ the whole screen

// Zig tip: `switch (app.overlay)` ends the drawing with whatever is open over the screen.
// `std.math.clamp(W / 4, 26, 40)` keeps the sidebar between 26 and 40 cells; integer division
// drops the remainder.
pub fn draw(app: *App, win: Window) !void {
    app.beginFrame();
    app.hits.clearRetainingCapacity();
    win.hideCursor();
    fillWith(win, theme.panel);
    const W = win.width;
    const H = win.height;
    if (W < 70 or H < 18) {
        _ = put(win, 1, 1, "evetx needs a window of at least 70 x 18 cells.", theme.on(theme.amber, theme.panel));
        return;
    }
    const sw: u16 = std.math.clamp(W / 4, 26, 40);

    try titleBar(app, win);
    try toolBar(app, win, sw);

    const mh = H - 2 - 3;
    try sidebar(app, win, sw, mh);
    try rightPanel(app, win, sw, mh);
    try statusBar(app, win);

    switch (app.overlay) {
        .none => {},
        .menu => try menu(app, win),
        .help => help(win),
        .settings => settings(win),
        .goto => try gotoBox(app, win),
        .save_as => saveAsBox(app, win),
    }
}

// Zig tip: `for (names, 0..) |n, i|` gives the element and its index. `@intCast(i + 1)` narrows
// the `usize` index to the `u8` of the action.
fn titleBar(app: *App, win: Window) !void {
    const W = win.width;
    const bar = sub(win, 0, 0, W, 1);
    fillWith(bar, theme.bar);
    const open = app.overlay == .menu;
    _ = put(bar, 0, 0, " evetx ▾ ", if (open) theme.onBold(theme.bright, theme.selected) else theme.onBold(theme.bright, theme.bar));
    try addHit(app, win, 0, 0, 9, 1, .menu_title);
    const label = app.fmt("project: {s}", .{app.project_name});
    _ = put(bar, 11, 0, label, theme.on(theme.text, theme.bar));
    // the machines: F1 local, F2 and F3 for remote machines (they come with step T5)
    const names = [_][]const u8{ "F1 local", "F2 —", "F3 —" };
    var x: u16 = W -| (3 * 11 + 1);
    for (names, 0..) |n, i| {
        const on = app.machine == i + 1;
        const s = app.fmt(" {s} ", .{n});
        _ = put(bar, x, 0, s, if (on) theme.onBold(theme.bright, theme.green_bg) else theme.on(theme.dim, theme.bar));
        try addHit(app, win, x, 0, 10, 1, .{ .machine = @intCast(i + 1) });
        x += 11;
    }
}

// Zig tip: Positions are computed in a running `x`. `std.math.clamp` keeps each field between a
// smallest and a largest width, so a narrow window still draws every control.
fn toolBar(app: *App, win: Window, sw: u16) !void {
    const W = win.width;
    const bar = sub(win, 0, 1, W, 1);
    fillWith(bar, theme.bar2);
    _ = put(bar, 1, 0, "Files", theme.on(theme.dim, theme.bar2));
    try field(app, bar, 7, 0, sw -| 8, &app.files_in, .files, "file names");
    _ = put(bar, sw, 0, "│", theme.on(theme.line, theme.bar2));

    var x: u16 = sw + 2;
    _ = put(bar, x, 0, "Find", theme.on(theme.dim, theme.bar2));
    x += 5;
    const fw: u16 = std.math.clamp((W -| x) / 4, 14, 30);
    try field(app, bar, x, 0, fw, &app.find_in, .find, "find in code");
    _ = put(bar, x + fw - 6, 0, "code", theme.on(theme.dim, theme.bar));
    x += fw + 2;
    _ = put(bar, x, 0, "Replace", theme.on(theme.dim, theme.bar2));
    x += 8;
    const rw: u16 = std.math.clamp((W -| x) / 5, 12, 22);
    try field(app, bar, x, 0, rw, &app.replace_in, .replace, "replace with");
    x += rw + 1;
    const btn = theme.on(theme.text, theme.bar);
    x = try button(app, bar, x, 0, "Replace", btn, .{ .button = .replace });
    x += 1;
    _ = try button(app, bar, x, 0, "Replace all", btn, .{ .button = .replace_all });
    _ = try button(app, bar, W -| 5, 0, "#", btn, .{ .button = .goto });
}

// Zig tip: `try app.tree.visibleRows(...)` fills a list kept in the app, so no list is made in
// every frame. `defer` is not used for `q` because it must live until render: it is allocated from
// the frame arena.
fn sidebar(app: *App, win: Window, sw: u16, mh: u16) !void {
    const box = boxed(win, 0, 2, sw, mh, theme.line);
    fillWith(box, theme.deep);
    _ = put(box, 1, 0, "Project files", theme.onBold(theme.bright, theme.deep));
    const rows_h = box.height -| 3;
    const list = sub(box, 0, 1, box.width, rows_h);
    app.tree_rect = absRect(list, 0, 0, list.width, list.height);

    try app.tree.visibleRows(app.gpa, &app.visible);
    var sel_pos: usize = 0;
    for (app.visible.items, 0..) |r, i| {
        if (r == app.selected) sel_pos = i;
    }
    if (sel_pos < app.tree_top) app.tree_top = sel_pos;
    if (sel_pos >= app.tree_top + rows_h) app.tree_top = sel_pos + 1 - rows_h;
    if (app.visible.items.len > rows_h) app.tree_top = @min(app.tree_top, app.visible.items.len - rows_h) else app.tree_top = 0;

    const q = try app.files_in.toOwnedContents(app.frame.allocator());

    var r: u16 = 0;
    while (r < rows_h and app.tree_top + r < app.visible.items.len) : (r += 1) {
        const idx = app.visible.items[app.tree_top + r];
        const e = app.tree.entries.items[idx];
        const is_sel = idx == app.selected;
        const bg = if (is_sel) (if (app.focus == .tree or app.focus == .files) theme.selected else theme.bar) else theme.deep;
        const row = sub(list, 0, r, list.width, 1);
        fillWith(row, bg);
        const indent: u16 = e.depth * 2;
        const glyph: []const u8 = if (e.is_dir) (if (e.expanded) "▾" else "▸") else " ";
        _ = put(row, 1 + indent, 0, glyph, theme.on(theme.dim, bg));
        const color = if (is_sel) theme.bright else if (std.mem.eql(u8, e.name, "eve.env")) theme.dim else theme.text;
        const nx = 3 + indent;
        if (q.len > 0 and e.parent != null and e.name.len >= q.len and std.ascii.eqlIgnoreCase(e.name[0..q.len], q)) {
            const c = put(row, nx, 0, e.name[0..q.len], theme.onBold(theme.amber, bg));
            _ = put(row, c, 0, e.name[q.len..], theme.on(color, bg));
        } else {
            _ = put(row, nx, 0, e.name, theme.on(color, bg));
        }
        if (e.is_dir and e.depth == 1 and isServerSide(e.name)) _ = put(row, list.width -| 3, 0, "●", theme.on(theme.blue, bg));
        try addHit(app, list, 0, r, list.width, 1, .{ .tree_row = idx });
    }
    _ = put(box, 1, box.height -| 2, "● server side: sent by upload", theme.on(theme.dim, theme.deep));
    _ = put(box, 1, box.height -| 1, "Enter or click opens, Ctrl+P finds", theme.on(theme.dim, theme.deep));
}

// Zig tip: `for ([_][]const u8{ ... }) |s|` loops over an array written in place. The four names
// are the folders that the upload sends (README.md §3).
fn isServerSide(name: []const u8) bool {
    for ([_][]const u8{ "proc", "sql", "web", "server" }) |s| {
        if (std.mem.eql(u8, name, s)) return true;
    }
    return false;
}

// Zig tip: The heights are computed from the room that is left: `mh -| (3 + bb)` cannot go below
// zero. Each part is a child window, drawn by its own function.
fn rightPanel(app: *App, win: Window, sw: u16, mh: u16) !void {
    const W = win.width;
    const rw = W - sw;
    const right = sub(win, sw, 2, rw, mh);
    const bb: u16 = @max(7, mh / 3);
    const eh: u16 = mh -| (3 + bb);

    try tabStrip(app, right, rw);
    const ed = sub(right, 0, 1, rw, eh);
    try editorArea(app, right, ed);
    try debugBar(app, right, 1 + eh, rw);
    try bottomPanel(app, right, 2 + eh, rw, bb);
}

// Zig tip: `break` leaves the loop when the next tab would not fit. A tab and its `×` are two hits
// on neighbouring cells, so a click on either does its own action.
fn tabStrip(app: *App, right: Window, rw: u16) !void {
    const strip = sub(right, 0, 0, rw, 1);
    fillWith(strip, theme.bar2);
    if (app.tabs.items.len == 0) {
        _ = put(strip, 1, 0, "no file open", theme.on(theme.faint, theme.bar2));
        return;
    }
    var x: u16 = 0;
    for (app.tabs.items, 0..) |t, i| {
        const active = i == app.active;
        const style = if (active) theme.onBold(theme.bright, theme.bar) else theme.on(theme.text, theme.bar2);
        const dirty: []const u8 = if (t.buf != null and t.buf.?.dirty) "● " else "";
        const label = app.fmt(" {s}{s} ", .{ dirty, t.title() });
        const w = strip.gwidth(label);
        if (x + w + 3 > rw) break;
        _ = put(strip, x, 0, label, style);
        try addHit(app, right, x, 0, w, 1, .{ .tab = i });
        _ = put(strip, x + w, 0, "× ", style);
        try addHit(app, right, x + w, 0, 2, 1, .{ .tab_close = i });
        x += w + 3;
    }
}

// Zig tip: `const tab = app.activeTab() orelse { ...; return; };` unwraps the optional, or draws
// the welcome text and returns. After this line `tab` is a plain pointer.
fn editorArea(app: *App, right: Window, ed: Window) !void {
    fillWith(ed, theme.deep);
    const tab = app.activeTab() orelse {
        _ = put(ed, 2, 1, "Click a file in the tree, or press Ctrl+N for a new file.", theme.on(theme.dim, theme.deep));
        _ = put(ed, 2, 3, "Ctrl+Enter menu · Ctrl+/ help · F5 run · Ctrl+P find a file", theme.on(theme.faint, theme.deep));
        app.editor_rect = .{};
        return;
    };
    _ = right;
    if (tab.buf) |*b| {
        try editor(app, ed, tab, b);
    } else {
        app.editor_rect = .{};
        card(app, tab, ed);
    }
}

// Zig tip: `b.follow(rows, cols)` scrolls the buffer so the cursor is inside the window.
// `code.showCursor(col, row)` tells the terminal where the cursor is; the view hides the cursor at
// the start of every frame.
fn editor(app: *App, ed: Window, tab: *app_mod.Tab, b: *text.Buffer) !void {
    var digits: u16 = 1;
    var n = b.lineCount();
    while (n >= 10) : (n /= 10) digits += 1;
    const gutter: u16 = digits + 3;
    const rows = ed.height;
    const cols = ed.width -| gutter;
    b.follow(rows, cols);
    const code = sub(ed, gutter, 0, cols, rows);
    app.editor_rect = absRect(ed, gutter, 0, cols, rows);
    const focused = app.focus == .editor and app.overlay == .none;

    var r: u16 = 0;
    while (r < rows and b.top + r < b.lineCount()) : (r += 1) {
        const ln = b.top + r + 1;
        const is_cur = (b.top + r) == b.row;
        const row_bg = if (is_cur and focused) theme.bar2 else theme.deep;
        const line_win = sub(ed, 0, r, ed.width, 1);
        fillWith(line_win, row_bg);
        if (app.hasBreakpoint(tab.path, ln)) _ = put(line_win, 0, 0, "●", theme.on(theme.red, row_bg));
        const num = app.fmt("{d}", .{ln});
        _ = put(line_win, gutter - 2 - @as(u16, @intCast(num.len)), 0, num, theme.on(if (is_cur) theme.bright else theme.dim, row_bg));
        const line = b.lineAt(b.top + r);
        const start = text.Buffer.byteAtDisplay(line, b.left);
        const cw = sub(code, 0, r, cols, 1);
        drawCode(cw, line, start, tab.eve, row_bg);
        if (b.match) |m| {
            if (m.row == b.top + r) {
                const mc = text.Buffer.displayWidth(line[0..m.col]);
                if (mc >= b.left) {
                    const end = @min(line.len, m.col + m.len);
                    _ = put(cw, @intCast(mc - b.left), 0, line[m.col..end], theme.on(theme.deep, theme.amber));
                }
            }
        }
    }
    if (focused) code.showCursor(@intCast(b.displayCol() - b.left), @intCast(b.row - b.top));
}

// Zig tip: A hand-written scanner: `while (i < s.len)` looks at the byte at `i`, finds the end `j`
// of the token, picks a style, prints `s[i..j]` and moves on. No allocation: the tokens are slices
// of the line.
/// Draw one line of text from byte `start`. Eve files get colors for comments, strings, numbers and keywords.
fn drawCode(w: Window, line: []const u8, start: usize, eve: bool, bg: theme.Color) void {
    const s = line[start..];
    const plain = theme.on(theme.text, bg);
    if (!eve) {
        _ = put(w, 0, 0, s, plain);
        return;
    }
    if (start == 0 and line.len > 0 and line[0] == '#') {
        _ = put(w, 0, 0, s, theme.on(theme.comment, bg));
        return;
    }
    var col: u16 = 0;
    var i: usize = 0;
    while (i < s.len) {
        const c = s[i];
        var j = i + 1;
        var style = plain;
        if (c == '"') {
            while (j < s.len and s[j] != '"') j += 1;
            if (j < s.len) j += 1;
            style = theme.on(theme.string, bg);
        } else if (c == '*' and i + 1 < s.len and s[i + 1] == '*') {
            j = s.len;
            style = theme.on(theme.comment, bg);
        } else if (std.ascii.isDigit(c)) {
            while (j < s.len and (std.ascii.isDigit(s[j]) or s[j] == '.' or s[j] == '_')) j += 1;
            style = theme.on(theme.number, bg);
        } else if (std.ascii.isAlphabetic(c) or c == '_') {
            while (j < s.len and (std.ascii.isAlphanumeric(s[j]) or s[j] == '_')) j += 1;
            if (isKeyword(s[i..j])) style = theme.on(theme.keyword, bg);
        } else {
            // a character that is not a word: one UTF-8 character at a time
            const n = std.unicode.utf8ByteSequenceLength(c) catch 1;
            j = @min(s.len, i + n);
        }
        col = put(w, col, 0, s[i..j], style);
        i = j;
    }
}

// Zig tip: `keywords.words` is a generated array (keywords.zig). A linear search over 99 short
// words is fast enough for the few lines on the screen.
fn isKeyword(word: []const u8) bool {
    for (keywords.words) |k| {
        if (std.mem.eql(u8, k, word)) return true;
    }
    return false;
}

// Zig tip: The card of D-178: facts and no preview. `ed.width -| 4` and `@min(..., 64)` keep the
// box inside a narrow window; the function returns early when there is no room.
/// The card of a file that is not text: its facts, and no preview (D-178).
fn card(app: *App, tab: *app_mod.Tab, ed: Window) void {
    const w: u16 = @min(ed.width -| 4, 64);
    const h: u16 = 9;
    if (ed.height < h + 2 or w < 30) return;
    const x = (ed.width - w) / 2;
    const y = (ed.height - h) / 2;
    const box = boxed(ed, x, y, w, h, theme.line);
    fillWith(box, theme.deep);
    _ = put(box, 2, 0, tab.title(), theme.onBold(theme.bright, theme.deep));
    _ = put(box, 2, 1, tab.card.kind, theme.on(theme.text, theme.deep));
    _ = put(box, 2, 3, "Path", theme.on(theme.dim, theme.deep));
    _ = put(box, 10, 3, tab.path, theme.on(theme.text, theme.deep));
    _ = put(box, 2, 4, "Size", theme.on(theme.dim, theme.deep));
    _ = put(box, 10, 4, sizeText(app, tab.card.size), theme.on(theme.text, theme.deep));
    _ = put(box, 2, 5, "Side", theme.on(theme.dim, theme.deep));
    _ = put(box, 10, 5, if (isServerPath(tab.path)) "server (sent by upload)" else "local (not sent by upload)", theme.on(theme.text, theme.deep));
    _ = put(box, 2, box.height -| 1, tab.card.note, theme.on(theme.dim, theme.deep));
}

// Zig tip: `std.mem.indexOfScalar(u8, path, '/') orelse return false` finds the first slash or
// leaves; `path[0..cut]` is then the first folder of the path.
fn isServerPath(path: []const u8) bool {
    const cut = std.mem.indexOfScalar(u8, path, '/') orelse return false;
    return isServerSide(path[0..cut]);
}

// Zig tip: `size >> 20` shifts the bits right by 20, which divides by 1,048,576. The tenth of a
// unit is `(size & mask) * 10 >> 20`; this is integer arithmetic, with no floating point.
fn sizeText(app: *App, size: u64) []const u8 {
    if (size >= 1 << 20) return app.fmt("{d}.{d} MB ({d} bytes)", .{ size >> 20, (size & ((1 << 20) - 1)) * 10 >> 20, size });
    if (size >= 1 << 10) return app.fmt("{d}.{d} KB ({d} bytes)", .{ size >> 10, (size & 1023) * 10 >> 10, size });
    return app.fmt("{d} bytes", .{size});
}

// Zig tip: The debugger buttons are drawn dimmed: they exist so that the screen is as designed,
// and a click says "not yet". Only Run works (F5).
fn debugBar(app: *App, right: Window, y: u16, rw: u16) !void {
    const bar = sub(right, 0, y, rw, 1);
    fillWith(bar, theme.panel);
    const on = theme.onBold(theme.bright, theme.green_bg);
    const off = theme.on(theme.faint, theme.panel);
    var x: u16 = 0;
    x = try button(app, bar, x, 0, "▶ Run", if (app.running) off else on, .{ .button = .run });
    x += 1;
    x = try button(app, bar, x, 0, "↓ Step into", off, .{ .button = .step_into });
    x += 1;
    x = try button(app, bar, x, 0, "↑ Step out", off, .{ .button = .step_out });
    x += 1;
    x = try button(app, bar, x, 0, "▶▶ Continue", off, .{ .button = .cont });
    x += 1;
    _ = try button(app, bar, x, 0, "■ Stop", off, .{ .button = .stop });
    putRight(bar, rw, 0, "F5 run · F9 breakpoint ", theme.on(theme.dim, theme.panel));
}

// Zig tip: `for (tabs, names) |t, n|` walks two arrays of the same length together. The label is a
// different string for the Breaks tab when there are breakpoints.
fn bottomPanel(app: *App, right: Window, y: u16, rw: u16, bb: u16) !void {
    const strip = sub(right, 0, y, rw, 1);
    fillWith(strip, theme.bar2);
    const tabs = [_]app_mod.BottomTab{ .console, .watch, .stderr, .stdout, .breaks };
    const names = [_][]const u8{ "Console", "Watch", "Stderr", "Stdout", "Breaks" };
    var x: u16 = 0;
    for (tabs, names) |t, n| {
        const label = if (t == .breaks and app.breakpoints.items.len > 0)
            app.fmt(" {s} ({d}) ", .{ n, app.breakpoints.items.len })
        else
            app.fmt(" {s} ", .{n});
        const on = app.bottom == t;
        _ = put(strip, x, 0, label, if (on) theme.onBold(theme.bright, theme.bar) else theme.on(theme.text, theme.bar2));
        const w = strip.gwidth(label);
        try addHit(app, right, x, 0, w, 1, .{ .bottom = t });
        x += w + 1;
    }
    const body = sub(right, 0, y + 1, rw, bb -| 1);
    fillWith(body, theme.deep);
    switch (app.bottom) {
        .console => try consolePanel(app, body),
        .stdout => logPanel(app, body, &app.stdout_log, "nothing yet: run a program (F5)"),
        .stderr => logPanel(app, body, &app.stderr_log, "nothing yet: run a program (F5)"),
        .watch => {
            _ = put(body, 2, 1, "The debugger is not connected yet: Watch needs the machine debugger", theme.on(theme.dim, theme.deep));
            _ = put(body, 2, 2, "(F-TLS-04, step T6 of README.md §8).", theme.on(theme.dim, theme.deep));
            app.console_rect = .{};
        },
        .breaks => try breaksPanel(app, body, right, y + 1),
    }
}

// Zig tip: A `switch` on the kind of line gives each kind its color. The prompt `eve:> ` is drawn
// separately from the text so that it can have its own style.
fn logLine(w: Window, row: u16, l: app_mod.LogLine) void {
    switch (l.kind) {
        .input => {
            const c = put(w, 1, row, "eve:> ", theme.onBold(theme.green, theme.deep));
            _ = put(w, c + 1, row, l.text, theme.on(theme.bright, theme.deep));
        },
        .out => _ = put(w, 1, row, l.text, theme.on(theme.text, theme.deep)),
        .err => _ = put(w, 1, row, l.text, theme.on(theme.red, theme.deep)),
        .info => _ = put(w, 1, row, l.text, theme.on(theme.dim, theme.deep)),
    }
}

// Zig tip: The last `rows` lines are shown, `scroll` lines above the end. `log.scroll =
// @min(log.scroll, total -| 1)` keeps the scroll inside the log. The thumb of the scroll bar is
// integer arithmetic on the sizes.
/// Draw the last lines of a log into `w` (the line `scroll` lines above the end is the last one shown).
fn drawLog(app: *App, w: Window, log: *app_mod.Log) void {
    app.console_rect = absRect(w, 0, 0, w.width, w.height);
    const rows: usize = w.height;
    const total = log.lines.items.len;
    log.scroll = @min(log.scroll, total -| 1);
    const end = total - log.scroll;
    const first = end -| rows;
    var r: u16 = 0;
    var i = first;
    while (i < end) : (i += 1) {
        logLine(w, r, log.lines.items[i]);
        r += 1;
    }
    // the scroll bar: a thumb at the place of the view in the log
    if (total > rows and w.width > 2) {
        const h: usize = w.height;
        const thumb_h = @max(1, h * rows / total);
        const thumb_y = (h - thumb_h) * end / total;
        var k: usize = 0;
        while (k < thumb_h) : (k += 1) _ = put(w, w.width - 1, @intCast(thumb_y + k), "▐", theme.on(theme.line, theme.deep));
    }
}

// Zig tip: One function serves the Stdout and the Stderr tabs: the log to show is a parameter, a
// `*app_mod.Log` pointer.
fn logPanel(app: *App, body: Window, log: *app_mod.Log, empty: []const u8) void {
    if (log.lines.items.len == 0) {
        _ = put(body, 2, 1, empty, theme.on(theme.faint, theme.deep));
        app.console_rect = absRect(body, 0, 0, body.width, body.height);
        return;
    }
    drawLog(app, body, log);
}

// Zig tip: `"─" ** 400` repeats a string at compile time (`**` is array repetition), which gives a
// rule longer than any window; the window clips it.
/// The console of evevm: the output scrolls above, then a rule and the prompt `eve:> `.
fn consolePanel(app: *App, body: Window) !void {
    const h = body.height;
    if (h < 3) return;
    const out = sub(body, 0, 0, body.width, h - 2);
    drawLog(app, out, &app.console);
    _ = put(body, 0, h - 2, "─" ** 400, theme.on(theme.line, theme.deep));
    const prompt = if (app.running) "Running… " else "eve:> ";
    _ = put(body, 1, h - 1, prompt, theme.onBold(if (app.running) theme.amber else theme.green, theme.deep));
    const pw: u16 = @intCast(body.gwidth(prompt));
    const line = sub(body, 1 + pw, h - 1, body.width -| (2 + pw), 1);
    fillWith(line, theme.deep);
    if (app.focus == .console and app.overlay == .none) {
        app.console_in.drawWithStyle(line, theme.on(theme.bright, theme.deep));
    } else {
        const first = app.console_in.buf.firstHalf();
        const c = put(line, 0, 0, first, theme.on(theme.text, theme.deep));
        _ = put(line, c, 0, app.console_in.buf.secondHalf(), theme.on(theme.text, theme.deep));
    }
}

// Zig tip: `app.breakpoints.items` is a slice; `for (slice, 0..) |bp, i|` gives each breakpoint
// and its number. `row` is a child window of one line, filled with the selected color when it is
// the selected row.
fn breaksPanel(app: *App, body: Window, right: Window, body_y: u16) !void {
    app.console_rect = .{};
    _ = put(body, 1, 0, "On  File : line", theme.on(theme.dim, theme.deep));
    if (app.breakpoints.items.len == 0) {
        _ = put(body, 2, 2, "No breakpoints. Press F9 on a line of the editor.", theme.on(theme.faint, theme.deep));
        return;
    }
    app.breaks_rect = absRect(body, 0, 1, body.width, body.height -| 2);
    for (app.breakpoints.items, 0..) |bp, i| {
        if (i + 2 > body.height) break;
        const r: u16 = @intCast(i + 1);
        const sel = i == app.break_sel;
        const row = sub(body, 0, r, body.width, 1);
        fillWith(row, if (sel) theme.selected else theme.deep);
        const s = app.fmt("[x] {s} : {d}", .{ bp.path, bp.line });
        _ = put(row, 1, 0, s, theme.on(if (sel) theme.bright else theme.text, if (sel) theme.selected else theme.deep));
        try addHit(app, right, 0, body_y + r, body.width, 1, .{ .break_row = i });
    }
    _ = put(body, 1, body.height -| 1, "Enter or a second click jumps · Del removes", theme.on(theme.dim, theme.deep));
}

// Zig tip: The bar is a box with a border (`boxed`), and its inside is one row split by `│`
// characters. The message of the last action, `Running…` or `Ready` takes the first cell.
fn statusBar(app: *App, win: Window) !void {
    const W = win.width;
    const H = win.height;
    const box = boxed(win, 0, H - 3, W, 3, theme.line);
    fillWith(box, theme.deep);
    const w = box.width;
    const dark = theme.on(theme.text, theme.deep);
    const name_x: u16 = @min(34, w / 3);
    const place_x: u16 = @min(name_x + 38, w * 2 / 3);
    const btn_x: u16 = w -| 9;

    // the state
    if (app.message) |m| {
        _ = put(box, 1, 0, m, theme.onBold(theme.amber, theme.deep));
    } else if (app.running) {
        _ = put(box, 1, 0, "Running…", theme.onBold(theme.amber, theme.deep));
    } else {
        const s = app.fmt("Ready: connection: {s}", .{if (app.machine == 1) "local" else "remote"});
        _ = put(box, 1, 0, s, theme.onBold(theme.green, theme.deep));
    }
    _ = put(box, name_x - 1, 0, "│", theme.on(theme.line, theme.deep));
    _ = put(box, place_x - 1, 0, "│", theme.on(theme.line, theme.deep));
    _ = put(box, btn_x - 1, 0, "│", theme.on(theme.line, theme.deep));

    // the name of the selected file, and the place in it
    if (app.activeTab()) |t| {
        _ = put(box, name_x + 1, 0, if (t.path.len == 0) "untitled" else t.path, theme.on(theme.bright, theme.deep));
        if (t.buf) |*b| {
            const s = app.fmt("Ln {d}, Col {d}", .{ b.row + 1, b.displayCol() + 1 });
            _ = put(box, place_x + 1, 0, s, dark);
        } else {
            const s = app.fmt("{s} · {s}", .{ t.card.kind, sizeText(app, t.card.size) });
            _ = put(box, place_x + 1, 0, s, dark);
        }
    }
    // the help and settings buttons
    const bs = theme.on(theme.text, theme.bar);
    _ = put(box, btn_x, 0, " ? ", bs);
    try addHit(app, box, btn_x, 0, 3, 1, .{ .button = .help });
    _ = put(box, btn_x + 4, 0, " ⚙ ", bs);
    try addHit(app, box, btn_x + 4, 0, 3, 1, .{ .button = .settings });
}

// ------------------------------------------------------------------ overlays

// Zig tip: Returns the window inside the dialog so that the caller draws its lines at fixed rows.
// `@min(w, win.width -| 2)` keeps it inside a small window.
/// A dialog in the middle of the screen: returns the inside, the first row holds the title.
fn dialog(win: Window, w: u16, h: u16, title: []const u8) Window {
    const ww = @min(w, win.width -| 2);
    const hh = @min(h, win.height -| 2);
    const x = (win.width - ww) / 2;
    const y = (win.height - hh) / 2;
    const box = boxed(win, x, y, ww, hh, theme.blue);
    fillWith(box, theme.panel);
    const head = sub(box, 0, 0, box.width, 1);
    fillWith(head, theme.selected);
    _ = put(head, 1, 0, title, theme.onBold(theme.bright, theme.selected));
    putRight(head, head.width -| 1, 0, "Esc closes", theme.on(theme.text, theme.selected));
    return box;
}

// Zig tip: The menu clears the hits of the screen first (`app.hits.clearRetainingCapacity()`) so
// that a click goes to the menu or closes it, and never reaches what is under it.
fn menu(app: *App, win: Window) !void {
    app.hits.clearRetainingCapacity();
    const rows = app_mod.menu_rows;
    const w: u16 = 36;
    const h: u16 = @intCast(rows.len + 2);
    const box = boxed(win, 0, 1, w, @min(h, win.height -| 2), theme.blue);
    fillWith(box, theme.panel);
    for (rows, 0..) |row, i| {
        if (i + 1 > box.height) break;
        const r: u16 = @intCast(i);
        if (row.cmd == null) {
            const s = std.ascii.allocUpperString(app.frame.allocator(), row.label) catch row.label;
            _ = put(box, 1, r, s, theme.onBold(theme.dim, theme.panel));
            continue;
        }
        const sel = app.menu_sel == i;
        const bg = if (sel) theme.selected else theme.panel;
        const line = sub(box, 0, r, box.width, 1);
        fillWith(line, bg);
        _ = put(line, 2, 0, row.label, theme.on(if (sel) theme.bright else theme.text, bg));
        putRight(line, line.width -| 1, 0, row.key, theme.on(if (sel) theme.bright else theme.dim, bg));
        try addHit(app, box, 0, r, box.width, 1, .{ .menu_item = i });
    }
}

// Zig tip: A `const` array of string literals in the function: each line is a `[]const u8` in the
// program, so nothing is allocated. `l[0] != ' '` tells a heading from an indented line.
fn help(win: Window) void {
    const box = dialog(win, 96, 24, "Help — keys");
    const lines = [_][]const u8{
        "Windows",
        "  Ctrl+Enter, F10   main menu (or click the title)     Ctrl+/, F12   this help",
        "  Ctrl+,            settings                           Ctrl+Q        quit",
        "Files and editing",
        "  Ctrl+S save   Ctrl+Shift+S save as   Ctrl+N new file   Ctrl+W close tab",
        "  Ctrl+P file search (names that start with the letters; Up/Down next match, Enter opens)",
        "  Ctrl+F find in the file (Enter next)   Ctrl+H replace (Enter replaces one)",
        "  Ctrl+G go to line (42 or 42:7), the # button",
        "Run and debug",
        "  F5 run the .eve file   F9 breakpoint   F8, F11, Shift+F11, Shift+F5: debugger (later)",
        "Machines",
        "  F1 local   F2, F3 remote machines (later)   Ctrl+Left, Ctrl+Right next machine (later)",
        "Console",
        "  Enter runs `eve <line>`   Ctrl+Up, Ctrl+Down history   PgUp, PgDn scroll   clear",
        "Tree",
        "  Up, Down, Left, Right move   Enter or Space opens or closes   a click does the same",
    };
    for (lines, 0..) |l, i| {
        const head = l[0] != ' ';
        _ = put(box, 1, @intCast(2 + i), l, if (head) theme.onBold(theme.blue, theme.panel) else theme.on(theme.text, theme.panel));
    }
}

// Zig tip: A placeholder dialog (Q-054 b): the same `dialog` helper, two lines of text, no
// controls.
fn settings(win: Window) void {
    const box = dialog(win, 56, 9, "Settings");
    _ = put(box, 2, 2, "Not yet: colors, tab size, keys and the machines list", theme.on(theme.text, theme.panel));
    _ = put(box, 2, 3, "come with the Settings dialog (Q-054 b).", theme.on(theme.text, theme.panel));
}

// Zig tip: The text field is the one of the `App` (`goto_in`), drawn with `drawWithStyle`; the
// dialog never needs the keyboard focus, because an overlay takes the keys first.
fn gotoBox(app: *App, win: Window) !void {
    const w: u16 = 34;
    const x = win.width -| (w + 1);
    const box = boxed(win, x, 2, w, 4, theme.blue);
    fillWith(box, theme.panel);
    _ = put(box, 1, 0, "Go to line (42 or 42:7)", theme.onBold(theme.bright, theme.panel));
    const f = sub(box, 1, 1, box.width -| 2, 1);
    fillWith(f, theme.bar);
    app.goto_in.drawWithStyle(f, theme.on(theme.bright, theme.bar));
}

// Zig tip: A dialog with one field. The key handling is in `App.overlayKey`: Enter saves under the
// typed path, Esc closes.
fn saveAsBox(app: *App, win: Window) void {
    const box = dialog(win, 64, 7, "Save As");
    _ = put(box, 2, 2, "File path, relative to the project folder:", theme.on(theme.text, theme.panel));
    const f = sub(box, 2, 3, box.width -| 4, 1);
    fillWith(f, theme.bar);
    app.saveas_in.drawWithStyle(f, theme.on(theme.bright, theme.bar));
}
