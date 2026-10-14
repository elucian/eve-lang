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
// have it. A click on the field gives it the focus (`dlg_field`).
/// A one-line input field of a dialog. The focused one shows its cursor; the others show their text.
fn field(app: *App, win: Window, x: u16, y: u16, w: u16, ti: *TextInput, which: u8, focused: bool) !void {
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

// ------------------------------------------------------------------ the whole screen

// Zig tip: `switch (app.overlay)` ends the drawing with whatever is open over the screen. An
// overlay is modal: the hits of the screen under it are forgotten, so a click cannot reach them.
// `std.math.clamp(W / 4, 26, 40)` keeps the sidebar between 26 and 40 cells; integer division drops
// the remainder.
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

    // row 0 is the menu bar, the last three rows are the status bar, the panels are between
    const mh = H - 1 - 3;
    try menuBar(app, win);
    try sidebar(app, win, sw, mh);
    try rightPanel(app, win, sw, mh);
    try statusBar(app, win);

    if (app.overlay == .none) return;
    app.hits.clearRetainingCapacity();
    switch (app.overlay) {
        .none => {},
        .menu => {
            try menuBar(app, win);
            try menuDrop(app, win);
        },
        .help => help(app, win),
        .settings => settings(app, win),
        .about => about(app, win),
        .goto => try gotoBox(app, win),
        .save_as => saveAsBox(app, win),
        .find_text => try findTextBox(app, win),
        .find_file => try findFileBox(app, win),
        .replace => try replaceBox(app, win),
    }
}

// Zig tip: `app_mod.menus[0..i]` is a slice of the first `i` menus; `for (slice) |m|` adds up their
// widths. A menu is drawn as ` NAME `, so it is two cells wider than its label.
/// The column of menu `i` in the bar: the menus follow each other from the left, the last one
/// (HELP) is at the right side.
fn menuX(W: u16, i: usize) u16 {
    const menus = app_mod.menus;
    if (i == menus.len - 1) return W -| @as(u16, @intCast(menus[i].label.len + 3));
    var x: u16 = 1;
    for (menus[0..i]) |m| x += @intCast(m.label.len + 2);
    return x;
}

// Zig tip: A style is a struct, so `var hot = theme.onBold(...)` makes a copy that can be changed
// field by field: `hot.ul_style = .single` adds an underline to this copy only.
/// The classic menu bar: upper case names, the first letter is the Alt key. The letter has its own
/// color; when the user presses Alt, or while a menu is open, it is underlined too.
fn menuBar(app: *App, win: Window) !void {
    const W = win.width;
    const bar = sub(win, 0, 0, W, 1);
    fillWith(bar, theme.bar);
    const in_use = app.overlay == .menu or app.alt_hint;
    var left_end: u16 = 0;
    for (app_mod.menus, 0..) |m, i| {
        const x = menuX(W, i);
        const w: u16 = @intCast(m.label.len + 2);
        const on = app.overlay == .menu and app.menu_top == i;
        const bg = if (on) theme.selected else theme.bar;
        const plain = theme.on(if (on) theme.bright else theme.text, bg);
        var hot = theme.onBold(theme.amber, bg);
        if (in_use) hot.ul_style = .single;
        _ = put(bar, x, 0, " ", plain);
        _ = put(bar, x + 1, 0, m.label[0..1], hot);
        _ = put(bar, x + 2, 0, m.label[1..], plain);
        _ = put(bar, x + w - 1, 0, " ", plain);
        try addHit(app, win, x, 0, w, 1, .{ .menu_top = i });
        if (i + 1 < app_mod.menus.len) left_end = x + w;
    }
    // the machines: F1 local, F2 and F3 for remote machines (they come with step T5)
    const names = [_][]const u8{ "F1 local", "F2 —", "F3 —" };
    const help_x = menuX(W, app_mod.menus.len - 1);
    const wide = help_x >= left_end + 33;
    if (wide) {
        var x: u16 = help_x - 31;
        for (names, 0..) |n, i| {
            try machineButton(app, win, bar, x, n, i);
            x += 10;
        }
    } else {
        const i: usize = app.machine - 1;
        try machineButton(app, win, bar, help_x -| 11, names[i], i);
    }
}

// Zig tip: A helper that draws one thing and records its hit keeps the loop above short. The
// machine number of the click is `i + 1`, narrowed to the `u8` of the action.
fn machineButton(app: *App, win: Window, bar: Window, x: u16, name: []const u8, i: usize) !void {
    const on = app.machine == i + 1;
    const s = app.fmt(" {s} ", .{name});
    _ = put(bar, x, 0, s, if (on) theme.onBold(theme.bright, theme.green_bg) else theme.on(theme.dim, theme.bar));
    try addHit(app, win, x, 0, 10, 1, .{ .machine = @intCast(i + 1) });
}

// Zig tip: A slice can be cut at a byte that is inside a UTF-8 character; the continuation bytes
// of a character all look like `10xxxxxx`, so `(s[n] & 0xC0) == 0x80` tells that `n` is not a
// place where a character starts, and the loop steps back.
/// `s` cut to at most `max` bytes, at the start of a character.
fn clipText(s: []const u8, max: usize) []const u8 {
    if (s.len <= max) return s;
    var n = max;
    while (n > 0 and (s[n] & 0xC0) == 0x80) n -= 1;
    return s[0..n];
}

// Zig tip: A string literal is an array of bytes; the compiler joins neighbours at compile time
// with `++`. The tree glyphs are each three bytes of UTF-8, and `put` counts them as one cell.
const vbar = "│  ";
const blank = "   ";
const tee = "├─ ";
const corner = "└─ ";

// Zig tip: a function may take a struct by value (`e: Entry`) when it only reads a few fields. The
// result is a string literal, which lives for the whole program, so nothing is allocated.
/// The picture of an entry: a folder (open or closed) or a file, by its kind.
fn iconOf(e: @import("project.zig").Entry) []const u8 {
    if (e.is_dir) return if (e.expanded) "📂" else "📁";
    if (e.name.len > 4 and std.ascii.eqlIgnoreCase(e.name[e.name.len - 4 ..], ".eve")) return "📜";
    return "📄";
}

// Zig tip: `try app.tree.visibleRows(...)` fills a list kept in the app, so no list is made in
// every frame. The ancestors of a row are collected in a small array on the stack, from the parent
// up to the root; `chain[k - 1]` then walks them from the outside in, as the lines are drawn.
fn sidebar(app: *App, win: Window, sw: u16, mh: u16) !void {
    const focused = app.overlay == .none and app.focus == .tree;
    const box = boxed(win, 0, 1, sw, mh, if (focused) theme.blue else theme.line);
    fillWith(box, theme.deep);
    _ = put(win, 2, 1, " Files ", theme.onBold(if (focused) theme.bright else theme.dim, theme.deep));
    const rows_h = box.height;
    const list = box;
    app.tree_rect = absRect(list, 0, 0, list.width, list.height);

    try app.tree.visibleRows(app.gpa, &app.visible);
    var sel_pos: usize = 0;
    for (app.visible.items, 0..) |r, i| {
        if (r == app.selected) sel_pos = i;
    }
    if (sel_pos < app.tree_top) app.tree_top = sel_pos;
    if (sel_pos >= app.tree_top + rows_h) app.tree_top = sel_pos + 1 - rows_h;
    if (app.visible.items.len > rows_h) app.tree_top = @min(app.tree_top, app.visible.items.len - rows_h) else app.tree_top = 0;

    const q: []const u8 = if (app.overlay == .find_file) try app.files_in.toOwnedContents(app.frame.allocator()) else "";
    const lines = theme.on(theme.faint, theme.deep);

    var r: u16 = 0;
    while (r < rows_h and app.tree_top + r < app.visible.items.len) : (r += 1) {
        const idx = app.visible.items[app.tree_top + r];
        const e = app.tree.entries.items[idx];
        const is_sel = idx == app.selected;
        const bg = if (is_sel) (if (focused or app.overlay == .find_file) theme.selected else theme.bar) else theme.deep;
        const row = sub(list, 0, r, list.width, 1);
        fillWith(row, bg);
        const line_style = if (is_sel) theme.on(theme.dim, bg) else lines;
        var x: u16 = 1;
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
                x = put(row, x, 0, if (app.tree.isLast(chain[k - 2])) blank else vbar, line_style);
            }
            x = put(row, x, 0, if (app.tree.isLast(idx)) corner else tee, line_style);
        }
        const folder_color = if (is_sel) theme.bright else theme.amber;
        x = put(row, x, 0, iconOf(e), theme.on(folder_color, bg));
        x += 1;
        const color = if (is_sel) theme.bright else if (std.mem.eql(u8, e.name, "eve.env")) theme.dim else if (e.is_dir) theme.bright else theme.text;
        if (q.len > 0 and e.parent != null and e.name.len >= q.len and std.ascii.eqlIgnoreCase(e.name[0..q.len], q)) {
            const c = put(row, x, 0, e.name[0..q.len], theme.onBold(theme.amber, bg));
            _ = put(row, c, 0, e.name[q.len..], theme.on(color, bg));
        } else {
            _ = put(row, x, 0, e.name, if (e.is_dir) theme.onBold(color, bg) else theme.on(color, bg));
        }
        if (e.is_dir and e.depth == 1 and isServerSide(e.name)) _ = put(row, list.width -| 3, 0, "●", theme.on(theme.blue, bg));
        try addHit(app, list, 0, r, list.width, 1, .{ .tree_row = idx });
    }
}

// Zig tip: `for ([_][]const u8{ ... }) |s|` loops over an array written in place. The four names
// are the folders that the upload sends (README.md §3).
fn isServerSide(name: []const u8) bool {
    for ([_][]const u8{ "proc", "sql", "web", "server" }) |s| {
        if (std.mem.eql(u8, name, s)) return true;
    }
    return false;
}

// Zig tip: The heights are computed from the room that is left: `mh -| (1 + bb)` cannot go below
// zero. Each part is a bordered box (`boxed`) and its inside is drawn by its own function. A box
// is blue when it has the keyboard, so the user sees where the keys go.
fn rightPanel(app: *App, win: Window, sw: u16, mh: u16) !void {
    const W = win.width;
    const rw = W - sw;
    const bb: u16 = @max(7, mh / 3);
    const eh: u16 = mh -| (1 + bb);

    const live = app.overlay == .none;
    const box = boxed(win, sw, 1, rw, eh, if (live and app.focus == .editor) theme.blue else theme.line);
    fillWith(box, theme.deep);
    try tabStrip(app, box);
    try editorArea(app, sub(box, 0, 1, box.width, box.height -| 1));
    try debugBar(app, win, sw, 1 + eh, rw);
    try bottomPanel(app, win, sw, 2 + eh, rw, bb);
}

// Zig tip: `break` leaves the loop when the next tab would not fit. A tab and its `×` are two hits
// on neighbouring cells, so a click on either does its own action (and a middle click closes).
fn tabStrip(app: *App, box: Window) !void {
    const rw = box.width;
    const strip = sub(box, 0, 0, rw, 1);
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
        try addHit(app, strip, x, 0, w, 1, .{ .tab = i });
        _ = put(strip, x + w, 0, "× ", style);
        try addHit(app, strip, x + w, 0, 2, 1, .{ .tab_close = i });
        x += w + 3;
    }
}

// Zig tip: `const tab = app.activeTab() orelse { ...; return; };` unwraps the optional, or draws
// the welcome text and returns. After this line `tab` is a plain pointer.
fn editorArea(app: *App, ed: Window) !void {
    fillWith(ed, theme.deep);
    const tab = app.activeTab() orelse {
        _ = put(ed, 2, 0, "Click a file in the tree, or press Ctrl+N for a new file.", theme.on(theme.dim, theme.deep));
        _ = put(ed, 2, 2, "F10 menu · Alt+letter · Ctrl+F find · Ctrl+P find file · F5 run", theme.on(theme.faint, theme.deep));
        app.editor_rect = .{};
        return;
    };
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
fn debugBar(app: *App, win: Window, x0: u16, y: u16, rw: u16) !void {
    const bar = sub(win, x0, y, rw, 1);
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
fn bottomPanel(app: *App, win: Window, x0: u16, y: u16, rw: u16, bb: u16) !void {
    const live = app.overlay == .none and (app.focus == .console or app.focus == .breaks);
    const box = boxed(win, x0, y, rw, bb, if (live) theme.blue else theme.line);
    fillWith(box, theme.deep);
    const strip = sub(box, 0, 0, box.width, 1);
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
        try addHit(app, strip, x, 0, w, 1, .{ .bottom = t });
        x += w + 1;
    }
    const body = sub(box, 0, 1, box.width, box.height -| 1);
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
        .breaks => try breaksPanel(app, body),
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
fn breaksPanel(app: *App, body: Window) !void {
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
        try addHit(app, row, 0, 0, body.width, 1, .{ .break_row = i });
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

// Zig tip: `addHit(...) catch {}` ignores an error on purpose: the empty block after `catch` is the
// whole handler. It is right here because the only error is "out of memory", and the worst result
// is that a click inside the dialog closes it.
/// Make the rectangle of a dialog a click that does nothing, so a click on its text does not close it.
fn solid(app: *App, win: Window, x: u16, y: u16, w: u16, h: u16) void {
    addHit(app, win, x, y, w, h, .nop) catch {};
}

// Zig tip: Returns the window inside the dialog so that the caller draws its lines at fixed rows.
// `@min(w, win.width -| 2)` keeps it inside a small window.
/// A dialog in the middle of the screen: returns the inside, the first row holds the title.
fn dialog(app: *App, win: Window, w: u16, h: u16, title: []const u8) Window {
    const ww = @min(w, win.width -| 2);
    const hh = @min(h, win.height -| 2);
    const x = (win.width - ww) / 2;
    const y = (win.height - hh) / 2;
    solid(app, win, x, y, ww, hh);
    const box = boxed(win, x, y, ww, hh, theme.blue);
    fillWith(box, theme.panel);
    const head = sub(box, 0, 0, box.width, 1);
    fillWith(head, theme.selected);
    _ = put(head, 1, 0, title, theme.onBold(theme.bright, theme.selected));
    putRight(head, head.width -| 1, 0, "Esc closes", theme.on(theme.text, theme.selected));
    return box;
}

// Zig tip: The search dialogs sit at the top right, under the menu bar, so the code stays visible
// while the user searches. The title is written over the top border of the box, in the parent
// window, one cell after the corner.
/// A small dialog at the top right of the screen: returns the inside.
fn topDialog(app: *App, win: Window, w: u16, h: u16, title: []const u8) Window {
    const ww = @min(w, win.width -| 2);
    const x = win.width -| ww;
    solid(app, win, x, 1, ww, h);
    const box = boxed(win, x, 1, ww, h, theme.blue);
    fillWith(box, theme.panel);
    _ = put(win, x + 2, 1, app.fmt(" {s} ", .{title}), theme.onBold(theme.bright, theme.deep));
    return box;
}

// Zig tip: `@max(a, b)` takes the larger of two numbers; a `for`
// over the rows finds the widest label and shortcut, so the box fits its content.
/// The drop-down of the open menu, under its name in the bar.
fn menuDrop(app: *App, win: Window) !void {
    const m = app_mod.menus[app.menu_top];
    var lw: u16 = 0;
    var kw: u16 = 0;
    for (m.items) |row| {
        lw = @max(lw, win.gwidth(row.label));
        kw = @max(kw, win.gwidth(row.key));
    }
    const w: u16 = @max(22, lw + kw + 6);
    const x = @min(menuX(win.width, app.menu_top), win.width -| w);
    const h: u16 = @intCast(m.items.len + 2);
    solid(app, win, x, 1, w, h);
    const box = boxed(win, x, 1, w, h, theme.blue);
    fillWith(box, theme.panel);
    for (m.items, 0..) |row, i| {
        const r: u16 = @intCast(i);
        if (row.cmd == null) {
            _ = put(box, 0, r, "─" ** 100, theme.on(theme.line, theme.panel));
            continue;
        }
        const sel = app.menu_sel == i;
        const bg = if (sel) theme.selected else theme.panel;
        const line = sub(box, 0, r, box.width, 1);
        fillWith(line, bg);
        _ = put(line, 1, 0, row.label, theme.on(if (sel) theme.bright else theme.text, bg));
        putRight(line, line.width -| 1, 0, row.key, theme.on(if (sel) theme.bright else theme.dim, bg));
        try addHit(app, box, 0, r, box.width, 1, .{ .menu_item = i });
    }
}

// Zig tip: A `const` array of string literals in the function: each line is a `[]const u8` in the
// program, so nothing is allocated. `l[0] != ' '` tells a heading from an indented line.
fn help(app: *App, win: Window) void {
    const box = dialog(app, win, 96, 26, "Shortcuts");
    const lines = [_][]const u8{
        "Menu",
        "  F10, Ctrl+Enter   open the menu bar          Alt + letter   open a menu: F E S R M H",
        "  Left, Right       next menu                  Up, Down, Enter   choose; Esc closes",
        "Files and editing",
        "  Ctrl+S save   Ctrl+Shift+S save as   Ctrl+N new file   Ctrl+W close tab   Ctrl+Q quit",
        "Search (menu SEARCH)",
        "  Ctrl+F find text (Enter next)   Ctrl+P find file (Up/Down next match, Enter opens)",
        "  Ctrl+H replace (Tab between the fields, Enter finds or replaces one)",
        "  Ctrl+G go to line (42 or 42:7)   Ctrl+L query (later)",
        "Run and debug",
        "  F5 run the .eve file   F9 breakpoint   F8, F11, Shift+F11, Shift+F5: debugger (later)",
        "Machines",
        "  F1 local   F2, F3 remote machines (later)   Ctrl+Left, Ctrl+Right next machine (later)",
        "Console",
        "  Enter runs `eve <line>`   Ctrl+Up, Ctrl+Down history   PgUp, PgDn scroll   clear",
        "Tree",
        "  Up, Down, Left, Right move   Enter or Space opens or closes   a click does the same",
        "Mouse",
        "  click, wheel in the tree, the editor and the console; middle click closes a tab",
    };
    for (lines, 0..) |l, i| {
        const head = l[0] != ' ';
        _ = put(box, 1, @intCast(2 + i), l, if (head) theme.onBold(theme.blue, theme.panel) else theme.on(theme.text, theme.panel));
    }
}

// Zig tip: A placeholder dialog (Q-054 b): the same `dialog` helper, two lines of text, no
// controls.
fn settings(app: *App, win: Window) void {
    const box = dialog(app, win, 56, 9, "Options");
    _ = put(box, 2, 2, "Not yet: colors, tab size, keys and the machines list", theme.on(theme.text, theme.panel));
    _ = put(box, 2, 3, "come with the Options dialog (Q-054 b).", theme.on(theme.text, theme.panel));
}

fn about(app: *App, win: Window) void {
    const box = dialog(app, win, 56, 9, "About");
    _ = put(box, 2, 2, "evetx: the Eve terminal IDE", theme.onBold(theme.bright, theme.panel));
    _ = put(box, 2, 3, "A text user interface for Eve projects (level 6).", theme.on(theme.text, theme.panel));
    _ = put(box, 2, 5, "Built on libvaxis. Esc or Enter closes.", theme.on(theme.dim, theme.panel));
}

// Zig tip: The text field is the one of the `App` (`goto_in`), drawn with `drawWithStyle`; the
// dialog never needs the keyboard focus, because an overlay takes the keys first.
fn gotoBox(app: *App, win: Window) !void {
    const box = topDialog(app, win, 36, 4, "GoTo");
    try field(app, box, 1, 0, box.width -| 2, &app.goto_in, 0, true);
    _ = put(box, 1, 1, "Line, or line:column (42 or 42:7)", theme.on(theme.dim, theme.panel));
}

fn findTextBox(app: *App, win: Window) !void {
    const box = topDialog(app, win, 46, 4, "Find Text");
    try field(app, box, 1, 0, box.width -| 2, &app.find_in, 0, true);
    _ = put(box, 1, 1, "Enter finds the next match · Esc closes", theme.on(theme.dim, theme.panel));
}

// Zig tip: `app.tree.entries.items[app.selected]` is the entry that the search moved to; the dialog
// shows its path so that the user sees the answer before pressing Enter.
fn findFileBox(app: *App, win: Window) !void {
    const box = topDialog(app, win, 52, 5, "Find File");
    try field(app, box, 1, 0, box.width -| 2, &app.files_in, 0, true);
    const typed = app.files_in.buf.firstHalf().len + app.files_in.buf.secondHalf().len;
    if (typed > 0 and app.selected < app.tree.entries.items.len) {
        const e = app.tree.entries.items[app.selected];
        _ = put(box, 1, 1, clipText(e.path, box.width -| 3), theme.on(theme.green, theme.panel));
    } else {
        _ = put(box, 1, 1, "Type the first letters of a file name", theme.on(theme.dim, theme.panel));
    }
    _ = put(box, 1, 2, "Up, Down next match · Enter opens", theme.on(theme.dim, theme.panel));
}

fn replaceBox(app: *App, win: Window) !void {
    const box = topDialog(app, win, 50, 6, "Replace");
    _ = put(box, 1, 0, "Find", theme.on(theme.dim, theme.panel));
    try field(app, box, 10, 0, box.width -| 11, &app.find_in, 0, app.dlg_field == 0);
    _ = put(box, 1, 1, "Replace", theme.on(theme.dim, theme.panel));
    try field(app, box, 10, 1, box.width -| 11, &app.replace_in, 1, app.dlg_field == 1);
    const btn = theme.on(theme.text, theme.bar);
    var x: u16 = 1;
    x = try button(app, box, x, 2, "Replace", btn, .{ .button = .replace });
    _ = try button(app, box, x + 1, 2, "Replace all", btn, .{ .button = .replace_all });
    _ = put(box, 1, 3, "Tab switches the field · Esc closes", theme.on(theme.dim, theme.panel));
}

// Zig tip: A dialog with one field. The key handling is in `App.overlayKey`: Enter saves under the
// typed path, Esc closes.
fn saveAsBox(app: *App, win: Window) void {
    const box = dialog(app, win, 64, 7, "Save As");
    _ = put(box, 2, 2, "File path, relative to the project folder:", theme.on(theme.text, theme.panel));
    const f = sub(box, 2, 3, box.width -| 4, 1);
    fillWith(f, theme.bar);
    app.saveas_in.drawWithStyle(f, theme.on(theme.bright, theme.bar));
}
