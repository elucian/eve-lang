//! Drawing: reads the state of `App` and draws the screen of design/design.svg. It also records
//! the clickable places (`app.hits`) and the areas that scroll, for the mouse.
const std = @import("std");
const vaxis = @import("vaxis");
const Window = vaxis.Window;
const TextInput = vaxis.widgets.TextInput;

const app_mod = @import("app.zig");
const options_mod = @import("options.zig");
const App = app_mod.App;
const Action = app_mod.Action;
const Rect = app_mod.Rect;
const theme = @import("theme.zig");
const dbf = @import("dbf.zig");
const sqlstruct = @import("sqlstruct.zig");
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
// Zig tip: the label is padded with spaces on both sides to a fixed width, so a row of buttons has the same width for each.
// `" " ** 40` is a string of 40 spaces made when the program is compiled; `[0..n]` takes the first n of them.
/// A button of a given width (the label is centered).
fn fixedButton(app: *App, win: Window, x: u16, label: []const u8, w: u16, style: Style, action: Action) !u16 {
    const spaces = " " ** 40;
    const gw = win.gwidth(label);
    const left: usize = @min(spaces.len, (w -| gw) / 2);
    const right: usize = @min(spaces.len, w -| gw -| left);
    return button(app, win, x, 0, app.fmt("{s}{s}{s}", .{ spaces[0..left], label, spaces[0..right] }), style, action);
}

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
// The places of the panels come from `App.computeLayout`, so the mouse code sees the same ones.
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

    // row 0 is the menu bar, the last three rows are the status bar, the panels are between
    const l = app.computeLayout(W, H);
    try menuBar(app, win);
    try sidebar(app, win, l.tree);
    try mainPanel(app, win, l);
    try toolsPanel(app, win, l.tools);
    if (l.debug.w > 0) try debugBar(app, win, l.debug.x, l.debug.y, l.debug.w);
    try statusBar(app, win);

    drawSplitHint(app, win, l);
    if (app.overlay == .none) return;
    app.hits.clearRetainingCapacity();
    if (app.overlay == .alert) {
        // the pop-up of a failed operation is drawn over the dialog it goes back to; only its own button can be clicked
        try overlayBox(app, win, app.alert_back);
        app.hits.clearRetainingCapacity();
        return alertBox(app, win);
    }
    try overlayBox(app, win, app.overlay);
}

// Zig tip: the `switch` names every dialog; `.none` and `.alert` draw nothing here (`draw` handles the pop-up), so the
// function never calls itself, and its error set can be inferred by the compiler.
/// Draw the dialog `which`.
fn overlayBox(app: *App, win: Window, which: app_mod.Overlay) !void {
    switch (which) {
        .none, .alert => {},
        .menu => {
            try menuBar(app, win);
            try menuDrop(app, win);
        },
        .settings => try settings(app, win),
        .about => try about(app, win),
        .tab_menu => try tabMenuBox(app, win),
        .confirm => try confirmBox(app, win),
        .structure => try structureBox(app, win),
        .sq_structure => try sqStructureBox(app, win),
        .new_table => try newTableBox(app, win),
        .properties => try propertiesBox(app, win),
        .new_file => try newBox(app, win),
        .wizard => try wizardBox(app, win),
        .append_n => try appendNBox(app, win),
        .open_project => try projectBox(app, win),
        .open_folder => try folderBox(app, win),
        .goto => try gotoBox(app, win),
        .save_as => try saveAsBox(app, win),
        .find_text => try findTextBox(app, win),
        .find_file => try findFileBox(app, win),
        .replace => try replaceBox(app, win),
    }
}

// Zig tip: the message is cut into lines at the spaces, as many words as fit in `w` cells; `std.mem.tokenizeScalar` gives
// the words and skips runs of spaces. The lines live in a small array on the stack (at most 6), and the dialog is as tall
// as they need.
/// The pop-up of a failed operation: its title, the message, and OK, which closes it (and goes back to the dialog under it).
fn alertBox(app: *App, win: Window) !void {
    const msg = app.alert_msg orelse "The operation failed.";
    const w: usize = 56;
    var lines: [6][]const u8 = undefined;
    var n: usize = 0;
    var start: usize = 0;
    var end: usize = 0;
    var it = std.mem.tokenizeScalar(u8, msg, ' ');
    while (it.next()) |word| {
        const at = it.index - word.len;
        if (end > start and at + word.len - start > w) {
            if (n == lines.len) break;
            lines[n] = msg[start..end];
            n += 1;
            start = at;
        } else if (end == start) start = at;
        end = at + word.len;
    }
    if (end > start and n < lines.len) {
        lines[n] = msg[start..end];
        n += 1;
    }
    const box = dialog(app, win, @intCast(w + 6), @intCast(6 + n), "Operation failed");
    for (lines[0..n], 0..) |l, i| _ = put(box, 2, @intCast(1 + i), clipText(l, w + 2), theme.on(theme.bright, theme.panel));
    try buttonRow(app, box, box.height -| 2, &.{.{ .label = "OK", .action = ok_btn, .primary = true }});
}

// Zig tip: A terminal may not change the shape of the mouse pointer (the shape is asked for with an
// escape code that not every terminal knows), so the border under the pointer, or being dragged, is
// also painted in amber: the user sees what a click would take.
/// Paint the border between panels that is under the pointer.
fn drawSplitHint(app: *App, win: Window, l: app_mod.Layout) void {
    const which = (if (app.drag == .tree_split or app.drag == .tools_split) app.drag else null) orelse app.hover_split orelse return;
    if (app.overlay != .none) return;
    const style = theme.on(theme.amber, theme.deep);
    switch (which) {
        .tree_split => {
            var y: u16 = 2;
            while (y + 4 < win.height) : (y += 1) {
                _ = put(win, l.tree.w -| 1, y, "┃", style);
                _ = put(win, l.tree.w, y, "┃", style);
            }
        },
        .tools_split => {
            var x: u16 = l.tools.x + 1;
            while (x + 1 < l.tools.x + l.tools.w) : (x += 1) _ = put(win, x, l.tools.y, "━", style);
            // the bottom border of the Main Panel, above the toolbar, is the other side of the same border
            if (l.main.w > 0 and l.main.h > 0) {
                x = l.main.x + 1;
                while (x + 1 < l.main.x + l.main.w) : (x += 1) _ = put(win, x, l.main.y + l.main.h - 1, "━", style);
            }
        },
        else => {},
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
    }
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

// Zig tip: The border color tells the state of a panel: amber while Window > Modify is on, blue when
// the panel has the keyboard, grey otherwise. The panel also records a hit over its whole
// rectangle, drawn first, so a click on an empty place of the panel gives it the keyboard; the
// buttons and rows drawn later are on top of it.
/// Draw the border of a panel and return its inside.
fn panelBox(app: *App, win: Window, r: Rect, p: app_mod.Panel) !Window {
    const live = app.overlay == .none and app.activePanel() == p;
    const color = if (app.modify) theme.amber else if (live) theme.blue else theme.line;
    try addHit(app, win, r.x, r.y, r.w, r.h, .{ .panel_focus = p });
    return boxed(win, r.x, r.y, r.w, r.h, color);
}

// Zig tip: `if (cond) a else b` as an argument picks the text of the "maximize" button. The buttons
// are three cells wide (` + `, ` × `) and sit at the right end of the title bar; the Tree Panel has
// only the hide button.
/// The + (maximize) and × (hide) buttons at the right of the title bar of a panel.
fn titleButtons(app: *App, box: Window, p: app_mod.Panel) !void {
    const w = box.width;
    if (w < 8) return;
    const style = theme.on(theme.text, theme.bar2);
    _ = put(box, w - 3, 0, " × ", style);
    try addHit(app, box, w - 3, 0, 3, 1, .{ .panel_hide = p });
    if (p == .tree) return;
    _ = put(box, w - 6, 0, if (app.maximized == p) " – " else " + ", style);
    try addHit(app, box, w - 6, 0, 3, 1, .{ .panel_max = p });
    // the third button, at the same distance: the `>` of the tab row of the Main Panel (on when tabs are hidden at the
    // right, see `tabStrip`), the Clear of the Tools Panel
    if (w < 16) return;
    if (p == .main) {
        const can = app.tab_more_right;
        _ = put(box, w - 9, 0, " > ", if (can) theme.onBold(theme.bright, theme.bar2) else theme.on(theme.faint, theme.bar2));
        if (can) try addHit(app, box, w - 9, 0, 3, 1, .{ .tab_shift = 1 });
    } else {
        _ = put(box, w - 9, 0, " ↺ ", style);
        try addHit(app, box, w - 9, 0, 3, 1, .clear_panel);
    }
}

// Zig tip: A string literal is an array of bytes; the compiler joins neighbours at compile time
// with `++`. The tree glyphs are each three bytes of UTF-8, and `put` counts them as one cell.
const vbar = "│  ";
const blank = "   ";
const tee = "├─ ";
const corner = "└─ ";

// Zig tip: `&.{ ".db", ".sqlite" }` is a list of strings written in the call; the function receives
// it as a slice. Comparing the end of the name with each ending ignores upper and lower case.
/// Does `name` end with one of the endings?
fn hasExt(name: []const u8, endings: []const []const u8) bool {
    for (endings) |end| {
        if (name.len > end.len and std.ascii.eqlIgnoreCase(name[name.len - end.len ..], end)) return true;
    }
    return false;
}

// Zig tip: a function may take a struct by value (`e: Entry`) when it only reads a few fields. The
// result is a string literal, which lives for the whole program, so nothing is allocated.
/// The picture of an entry: a folder (open or closed) or a file, by its kind.
fn iconOf(e: @import("project.zig").Entry) []const u8 {
    if (e.kind == .table) return "▦";
    if (e.kind == .db) return if (e.expanded) "💽" else "💾";
    if (e.is_dir) return if (e.expanded) "📂" else "📁";
    if (hasExt(e.name, &.{ ".db", ".duckdb", ".sqlite", ".sqlite3", ".dbf" })) return "💾";
    if (e.name.len > 4 and std.ascii.eqlIgnoreCase(e.name[e.name.len - 4 ..], ".eve")) return "📜";
    return "📄";
}

// Zig tip: A part of a row of the tree is drawn character by character at a virtual column `vc` that
// does not depend on the scrolling; the cells left of `left` (the horizontal scroll) are skipped, and
// so are the cells that would pass the width. `std.unicode.Utf8View` walks the text one character at
// a time, and `gwidth` tells if a character takes one cell or two (the pictures take two).
/// Draw `s` in one style at virtual column `vc` of a tree row, scrolled by `left`; `vc` moves to the end of `s`.
fn putScrolled(row: Window, vc: *usize, left: usize, width: usize, s: []const u8, style: Style) void {
    var it = (std.unicode.Utf8View.init(s) catch return).iterator();
    while (it.nextCodepointSlice()) |ch| {
        const w: usize = row.gwidth(ch);
        if (vc.* >= left and vc.* - left + w <= width) _ = put(row, @intCast(vc.* - left), 0, ch, style);
        vc.* += w;
    }
}

// Zig tip: A bar is drawn from numbers only: how much there is (`total`), where the view starts
// (`top`) and how much it shows (`visible`). The vertical one has ▲ and ▼ with a free row above, and
// returns the rectangle of its track for the mouse; with fewer than six rows it is only a track.
/// A vertical bar in column `x` of `win`, `h` rows tall.
fn vBar(app: *App, win: Window, x: u16, h: u16, total: usize, top: usize, visible: usize, up: Action, down: Action) Rect {
    const track = theme.on(theme.faint, theme.deep);
    const btn = theme.onBold(theme.text, theme.bar2);
    // a tall bar has a free row above the arrow; a short one (3 to 5 rows) has the arrows at its two ends
    const tall = h >= 6;
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

/// A horizontal bar in row `y` of `win`, `w` cells wide, with ◀ and ▶ at the ends.
fn hBar(app: *App, win: Window, y: u16, w: u16, total: usize, left: usize, visible: usize, lft: Action, rgt: Action) Rect {
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

// Zig tip: The tree is scrolled in both directions when it does not fit. The two bars depend on each
// other (a bar takes a row or a column that the other one then lacks), so the need for the vertical
// bar is decided twice. `tree_left` is the first column shown; the rows are drawn with `putScrolled`
// so that the connection lines, the picture and the name all move together.
fn sidebar(app: *App, win: Window, place: Rect) !void {
    if (place.w == 0) return;
    const focused = app.overlay == .none and app.focus == .tree;
    const box = try panelBox(app, win, place, .tree);
    fillWith(box, theme.deep);
    const bar = sub(box, 0, 0, box.width, 1);
    fillWith(bar, theme.bar2);
    const title = if (app.project_name.len > 0) app.fmt(" Files · {s}", .{app.project_name}) else " Files";
    _ = put(bar, 0, 0, clipText(title, box.width -| 5), theme.onBold(if (focused) theme.bright else theme.dim, theme.bar2));
    try titleButtons(app, box, .tree);
    _ = put(box, 0, 1, "─" ** 400, theme.on(theme.line, theme.deep));
    const list = sub(box, 0, 2, box.width, box.height -| 2);

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
    if (need_v) app.tvbar_rect = vBar(app, list, list.width - 1, rows_h, total, app.tree_top, rows_h, .{ .tree_scroll = .up }, .{ .tree_scroll = .down });
    if (need_h) app.thbar_rect = hBar(app, list, list.height - 1, text_w, content, left, text_w, .{ .tree_scroll = .left }, .{ .tree_scroll = .right });
}

// Zig tip: `for ([_][]const u8{ ... }) |s|` loops over an array written in place. The four names
// are the folders that the upload sends (README.md §3).
fn isServerSide(name: []const u8) bool {
    for ([_][]const u8{ "proc", "sql", "web", "server" }) |s| {
        if (std.mem.eql(u8, name, s)) return true;
    }
    return false;
}

// Zig tip: A struct passed by value (`l: app_mod.Layout`) is a bundle of rectangles; the function
// reads the ones it needs. The Run buttons are drawn by `debugBar`.
/// The Main Panel: the windows as tabs and the editor.
fn mainPanel(app: *App, win: Window, l: app_mod.Layout) !void {
    const r = l.main;
    if (r.w == 0) return;
    const box = try panelBox(app, win, r, .main);
    fillWith(box, theme.deep);
    try tabStrip(app, box);
    try titleButtons(app, box, .main);
    _ = put(box, 0, 1, "─" ** 400, theme.on(theme.line, theme.deep));
    try editorArea(app, sub(box, 0, 2, box.width, box.height -| 2));
}

// Zig tip: a tab has the picture that its file has in the tree: a folder view the open folder, a table of a database the table
// sign, a database or DBF file the disk, an Eve file the scroll, anything else the page. The choice is made from the path.
/// The icon of a tab, the same as the one of the file in the tree.
fn tabIcon(t: app_mod.Tab) []const u8 {
    if (t.folder != null) return "📂";
    if (std.mem.indexOfScalar(u8, t.path, '#') != null) return "▦";
    if (hasExt(t.path, &.{ ".db", ".duckdb", ".sqlite", ".sqlite3", ".dbf" })) return "💾";
    if (hasExt(t.path, &.{".eve"})) return "📜";
    return "📄";
}

// Zig tip: the text is made in the frame arena (`app.fmt`), because libvaxis keeps a pointer to it until the frame is shown.
/// The text of a tab: its icon, a dot when it has unsaved changes, and its title (in the frame arena).
fn tabLabel(app: *App, t: app_mod.Tab) []const u8 {
    const dirty: []const u8 = if (t.buf != null and t.buf.?.dirty) "● " else "";
    return app.fmt(" {s} {s}{s} ", .{ tabIcon(t), dirty, t.title() });
}

// Zig tip: a tab takes its label and three more cells (`× ` and a space); the sum over the tabs `first` to `last` says
// whether they fit in `room` cells together.
/// Do the tabs `first` to `last` fit in `room` cells?
fn tabsFit(app: *App, strip: Window, first: usize, last: usize, room: u16) bool {
    var used: usize = 0;
    for (app.tabs.items[first .. last + 1]) |t| used += strip.gwidth(tabLabel(app, t)) + 3;
    return used <= room;
}

// Zig tip: `break` leaves the loop when the next tab would not fit. A tab and its `×` are two hits on neighbouring cells,
// so a click on either does its own action (and a middle click closes). The row starts at `tab_first`; when the active
// tab changes (`tab_seen`), the row moves just enough to show it, and the `<` and `>` buttons move it freely.
/// The tab row of the Main Panel: `<` at the left, the tabs, and (in `titleButtons`) `>` at the right.
fn tabStrip(app: *App, box: Window) !void {
    const strip = sub(box, 0, 0, box.width, 1);
    fillWith(strip, theme.bar2);
    const n = app.tabs.items.len;
    if (n == 0) {
        app.tab_first = 0;
        app.tab_more_right = false;
        _ = put(strip, 1, 0, "no file open", theme.on(theme.faint, theme.bar2));
        return;
    }
    // the tabs go between the `<` button (3 cells) and the buttons of the title (`>`, `+`, `×`: 10 cells from the right)
    const x0: u16 = 3;
    const room: u16 = box.width -| 10 -| x0;
    if (app.tab_first >= n) app.tab_first = n - 1;
    const active = @min(app.active, n - 1);
    if (app.tab_seen != active) {
        app.tab_seen = active;
        if (active < app.tab_first) app.tab_first = active;
        while (app.tab_first < active and !tabsFit(app, strip, app.tab_first, active, room)) app.tab_first += 1;
    }
    var x: u16 = x0;
    var i = app.tab_first;
    while (i < n) : (i += 1) {
        const t = app.tabs.items[i];
        const style = if (i == app.active) theme.onBold(theme.deep, theme.blue) else theme.on(theme.text, theme.bar2);
        const label = tabLabel(app, t);
        const w = strip.gwidth(label);
        if (x - x0 + w + 3 > room) break;
        _ = put(strip, x, 0, label, style);
        try addHit(app, strip, x, 0, w, 1, .{ .tab = i });
        _ = put(strip, x + w, 0, "× ", style);
        try addHit(app, strip, x + w, 0, 2, 1, .{ .tab_close = i });
        x += w + 3;
    }
    app.tab_more_right = i < n;
    const can_left = app.tab_first > 0;
    _ = put(strip, 0, 0, " < ", if (can_left) theme.onBold(theme.bright, theme.bar2) else theme.on(theme.faint, theme.bar2));
    if (can_left) try addHit(app, strip, 0, 0, 3, 1, .{ .tab_shift = -1 });
}

// Zig tip: A `const` array of string literals at file level is stored once in the program. All five
// rows have the same width (41 cells), so the logo is centered by its first row.
const logo_rows = [_][]const u8{
    "██████ ██  ██ ██████        ██████ ██  ██",
    "██     ██  ██ ██              ██    ████ ",
    "█████  ██  ██ █████  █████    ██     ██  ",
    "██      ████  ██              ██    ████ ",
    "██████   ██   ██████          ██   ██  ██",
};

// Zig tip: `(win.width -| w) / 2` centers: the saturating subtraction gives 0 when the text is wider
// than the window, so the text starts at the left edge instead of failing.
/// Print `s` in the middle of `row`.
fn center(win: Window, row: u16, s: []const u8, style: Style) void {
    _ = put(win, (win.width -| win.gwidth(s)) / 2, row, s, style);
}

/// The picture of the Main Panel when no window is open: the logo, and two lines under it. In a
/// small panel the logo is replaced by plain text.
fn logo(ed: Window) void {
    const dim = theme.on(theme.dim, theme.deep);
    if (ed.width < 43 or ed.height < 9) {
        if (ed.height < 3) return;
        const y: u16 = (ed.height - 3) / 2;
        center(ed, y, "EVE-TX", theme.onBold(theme.blue, theme.deep));
        center(ed, y + 1, "Text User Interface", theme.on(theme.text, theme.deep));
        center(ed, y + 2, "(c) Sage-Code Laboratory", dim);
        return;
    }
    const y0: u16 = (ed.height - 9) / 2;
    const x0: u16 = (ed.width - 41) / 2;
    for (logo_rows, 0..) |row, i| {
        _ = put(ed, x0, y0 + @as(u16, @intCast(i)), row, theme.onBold(theme.blue, theme.deep));
    }
    center(ed, y0 + 6, "Text User Interface", theme.on(theme.text, theme.deep));
    center(ed, y0 + 8, "(c) Sage-Code Laboratory", dim);
}

// Zig tip: `const tab = app.activeTab() orelse { ...; return; };` unwraps the optional, or draws
// the logo and returns. After this line `tab` is a plain pointer.
fn editorArea(app: *App, ed: Window) !void {
    fillWith(ed, theme.deep);
    app.vbar_rect = .{};
    app.hbar_rect = .{};
    app.tblv_rect = .{};
    app.tblh_rect = .{};
    const tab = app.activeTab() orelse {
        logo(ed);
        app.editor_rect = .{};
        return;
    };
    if (tab.buf) |*b| {
        try editor(app, ed, tab, b);
    } else if (tab.folder) |fv| {
        app.editor_rect = absRect(ed, 0, 0, ed.width, ed.height);
        try folderArea(app, ed, fv);
    } else if (tab.table) |tv| {
        app.editor_rect = .{};
        tableArea(app, ed, tv);
    } else {
        app.editor_rect = .{};
        card(app, tab, ed);
    }
}

// Zig tip: a date is split with `std.time.epoch`: `EpochSeconds` gives the day (year, month, day) and the seconds of that day
// (hour, minute). Nothing is allocated: the text is made in the frame arena.
/// `YYYY-MM-DD HH:MM` for a moment given in seconds since 1970 (UTC), or "" for 0.
fn dateText(app: *App, secs: i64) []const u8 {
    if (secs <= 0) return "";
    const es = std.time.epoch.EpochSeconds{ .secs = @intCast(secs) };
    const yd = es.getEpochDay().calculateYearDay();
    const mday = yd.calculateMonthDay();
    const ds = es.getDaySeconds();
    return app.fmt("{d}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}", .{ yd.year, @intFromEnum(mday.month), mday.day_index + 1, ds.getHoursIntoDay(), ds.getMinutesIntoHour() });
}

// Zig tip: the list is a table drawn row by row: the icon, then the name, the description, the date and the size in KB, at
// columns that depend on the width of the panel (the name gets what is left). The row that is selected is painted; each row
// is a hit, so a click selects it and a second click opens it. The selected file decides if Run and Preview are active.
/// The Main Panel shows the content of a folder: icon, name, description, date made, size in KB.
fn folderArea(app: *App, ed: Window, fv: *app_mod.FolderView) !void {
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
    _ = put(ed, 0, 1, "─" ** 400, theme.on(theme.line, theme.deep));
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
        const bg = if (sel) theme.selected else theme.deep;
        const y: u16 = @intCast(2 + r);
        fillWith(sub(ed, 0, y, ed.width, 1), bg);
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
    if (n > rows) _ = vBar(app, ed, ed.width - 1, ed.height, n, fv.top, rows, .{ .folder_scroll = .up }, .{ .folder_scroll = .down });
}

/// The icon for a file name (the same as the tree and the tabs).
fn tabIconOfName(name: []const u8) []const u8 {
    if (hasExt(name, &.{ ".db", ".duckdb", ".sqlite", ".sqlite3", ".dbf" })) return "💾";
    if (hasExt(name, &.{".eve"})) return "📜";
    return "📄";
}

// Zig tip: a field is as wide as its data needs (the length of the field, 10 for a date) or its name, whichever is longer;
// the result is a `u16`, the type of a width on the screen.
/// The width a field asks for in the grid of a table.
fn naturalWidth(f: *const dbf.Field) u16 {
    const data: usize = switch (f.kind) {
        'D' => 10,
        'M' => 6,
        else => f.length,
    };
    return @intCast(std.math.clamp(@max(f.nameSlice().len, data), 4, 254));
}

// Zig tip: the widths are worked out once per frame into an array of the frame arena, which the click code reads too
// (`app.tbl_widths`): when the fields do not fit, the ones wider than 12 cells give up width in proportion to what they
// have above 12 (rounded up, so the sum fits), and none goes under 12; if they still do not fit, the grid scrolls
// sideways from `left`.
/// The widths of the columns of a table for `room` cells; also says whether all of them fit.
fn columnWidths(app: *App, t: *const dbf.Table, room: usize) struct { widths: []u16, fit: bool } {
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

// Zig tip: the grid is drawn column by column from `left`, with a `│` after each column and a `┼` where the rule under the
// header crosses it. The rows take turns between two backgrounds (`idx % 2`), the selected row a third one. The cell text
// is copied into the frame arena before `put`, because `put` keeps a pointer until the frame is shown.
/// The Main Panel shows a table: `#`, the names of the fields, then the records, with scroll bars.
fn tableArea(app: *App, ed: Window, tv: *app_mod.TableView) void {
    const t = &tv.t;
    app.tbl_rect = .{};
    app.tbl_widths = &.{};
    const dim = theme.on(theme.dim, theme.deep);
    if (t.fields.len == 0) {
        _ = put(ed, 2, 1, "This table has no fields yet.", theme.on(theme.text, theme.deep));
        _ = put(ed, 2, 2, "SQL:> alter table <name>  opens the dialog where you make them.", dim);
        return;
    }
    const num_w = app_mod.dbf_rownum_w;
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
    _ = put(ed, num_w - 3, 0, "#", head);
    _ = put(ed, num_w - 1, 0, "│", head_line);
    _ = put(ed, 0, 1, "─" ** 400, line);
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
        const row_bg = if (cur) theme.bar2 else if (odd) theme.panel else theme.deep;
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
        _ = put(body, 0, r, app.fmt("{d:>6}{s}", .{ idx + 1, if (gone) "*" else " " }), theme.on(theme.faint, row_bg));
        var cx: u16 = num_w;
        var k = tv.left;
        while (k < tv.left + shown) : (k += 1) {
            const f = &t.fields[k];
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
            const right: u16 = if (f.kind == 'N' or f.kind == 'F') w -| @as(u16, @intCast(@min(copy.len, w))) else 0;
            _ = put(body, cx + right, r, copy, style);
            cx += w + 1;
        }
    }
    app.tbl_rows = body_h;
    app.tbl_cols = shown;
    if (t.records > body_h) app.tblv_rect = vBar(app, body, body.width - 1, body.height, t.records, tv.top, body_h, .{ .table_scroll = .up }, .{ .table_scroll = .down });
    if (need_h) app.tblh_rect = hBar(app, ed, ed.height - 1, ed.width -| 1, t.fields.len, tv.left, shown, .{ .table_scroll = .left }, .{ .table_scroll = .right });
    if (t.records == 0) _ = put(ed, num_w + 1, 2, if (tv.readonly) "No rows." else "No records. The structure is changed with  SQL:> alter table <name>", dim);
}

// Zig tip: A tab is one character in the text but several cells on the screen. For drawing, the line is
// copied with every tab replaced by the spaces up to the next tab stop, so that the rest of the code
// can count one cell for each character. The copy is made in the arena of the frame (no free), and
// a line without tabs is returned as it is.
/// The line with its tabs spread into spaces.
fn expandTabs(app: *App, line: []const u8) []const u8 {
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

// Zig tip: The hidden characters are drawn over the line after the text: a middle dot for a space, a
// thin arrow at the start of a tab, and the line end sign right after the last character. The walk
// counts the cells like `displayWidth` does; only the cells inside the window (`left` to
// `left + cols`) are drawn.
/// Show the spaces, tabs and the line end of one line.
fn drawHidden(cw: Window, line: []const u8, left: usize, cols: usize, eol: []const u8, style: Style) void {
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

// Zig tip: The last line the view can start from: the end of the text may go up the screen until only
// three empty rows are left under the last line, never more. Without wrapping that is a sum; with
// wrapping the rows of the lines are counted from the end of the text until they fill the window
// less those three rows.
/// The largest first line that the editor can show.
fn maxTop(b: *const text.Buffer, rows: usize, cols: usize, wrap: bool) usize {
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

// Zig tip: With wrapping, the cursor is kept in view by counting rows, not lines: the rows of the
// lines from the first one shown up to the cursor, plus the piece of the cursor line it is in. When
// the cursor is far below, the first line jumps near it at once so the count stays short.
fn followWrap(b: *text.Buffer, rows: usize, cols: usize) void {
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

// Zig tip: `b.follow(rows, cols)` scrolls the buffer so the cursor is inside the window.
// `code.showCursor(col, row)` tells the terminal where the cursor is; the view hides the cursor at
// the start of every frame. In the wrap mode a line is drawn in several rows, one piece of `cols`
// cells each, and `left` is the first cell of the piece; the line number and the breakpoint are
// drawn on the first piece only. The variable `r` counts the rows of the screen, `ln` the lines.
fn editor(app: *App, ed: Window, tab: *app_mod.Tab, b: *text.Buffer) !void {
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
    while (r < rows and ln < b.lineCount()) : (ln += 1) {
        const line = b.lineAt(ln);
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
            if (tab.sql) drawSql(cw, shown, start, row_bg) else drawCode(cw, shown, start, tab.eve, row_bg);
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

// Zig tip: The glyphs of the bars are constants in one place, one set for each bar, so the look of
// the vertical and of the horizontal bar can be changed apart. The track is a light shade, the thumb
// a full block, the buttons are triangles. Block Elements has half blocks (`▀ ▄ ▌ ▐`) at the edges
// of a cell but no centered thin bar; `▬` (horizontal) and `▮` (vertical) of Geometric Shapes are
// centered, but fonts draw them differently: put them in `glyph_h_thumb` and `glyph_v_thumb` to try.
const glyph_v_track = "░";
const glyph_v_thumb = "█";
const glyph_h_track = "░";
const glyph_h_thumb = "█";
const glyph_up = "▲";
const glyph_down = "▼";
const glyph_left = "◀";
const glyph_right = "▶";

// Zig tip: The bars are one cell wide or tall. A proportion in integers gives the thumb: as long as
// the share of the text that is on the screen (`visible * span / total`), and placed by the share
// that is above the screen. The multiplication comes before the division, otherwise the integer
// division would round to 0. The vertical bar always has its buttons ▲ and ▼ (half a page each),
// with a free row above the first one so that it does not touch the title bar of the panel. The
// horizontal bar has ◀ and ▶ (ten columns each) and runs under the line numbers too, so it covers
// the whole width of the editor; with wrapping it is not drawn. Every button is a hit with the
// action `scroll`.
/// The vertical bar at the right of the text and, unless the text wraps, the horizontal bar under it.
/// The rectangles of the tracks are saved in the app for the mouse.
fn scrollBars(app: *App, ed: Window, b: *text.Buffer, rows: u16, cols: u16, lines_shown: usize) void {
    app.vbar_rect = .{};
    app.hbar_rect = .{};
    if (rows < 6 or cols < 6) return;
    const v_track = theme.on(theme.faint, theme.deep);
    const h_track = theme.on(theme.faint, theme.deep);
    const thumb = theme.on(theme.dim, theme.deep);
    const btn = theme.onBold(theme.text, theme.bar2);

    // the vertical bar: a free row, ▲, the track, ▼
    const vx = ed.width - 1;
    const total = b.lineCount() + 3; // the text may scroll up until three empty rows are left
    const y0: u16 = 2;
    const span: u16 = rows - 3;
    _ = put(ed, vx, 1, glyph_up, btn);
    addHit(app, ed, vx, 1, 1, 1, .{ .scroll = .up }) catch {};
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

// Zig tip: The selected part of a line is drawn again over the code with the selection colors. The
// selection is made of byte offsets in the real line; the columns they fall on (tabs count several
// cells) are found with `displayWidth` of the text before them, and the text to draw is cut from the
// copy with the tabs spread (`shown`), where a column is a character. A line whose end is selected
// gets one more colored cell, so the user sees that the line break is selected.
/// Paint the selected part of one line.
fn drawSelection(cw: Window, line: []const u8, shown: []const u8, row: usize, sel: text.Range, left: usize) void {
    if (row < sel.start.row or row > sel.end.row) return;
    const from = if (row == sel.start.row) sel.start.col else 0;
    const to = if (row == sel.end.row) sel.end.col else line.len;
    const style = theme.on(theme.bright, theme.sel_bg);
    const fc = text.Buffer.displayWidth(line[0..from]);
    const tc = text.Buffer.displayWidth(line[0..to]);
    const sc = @max(fc, left);
    if (sc < tc) {
        const sb = text.Buffer.byteAtDisplay(shown, sc);
        const eb = text.Buffer.byteAtDisplay(shown, tc);
        _ = put(cw, @intCast(sc - left), 0, shown[sb..eb], style);
    }
    if (row < sel.end.row) {
        const end_col = text.Buffer.displayWidth(line);
        if (end_col >= left) _ = put(cw, @intCast(end_col - left), 0, " ", style);
    }
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
    if (line.len > 0 and line[0] == '#') {
        const title = if (line.len > 1 and line[1] == '#') theme.subtitle else theme.title;
        _ = put(w, 0, 0, s, theme.on(title, bg));
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
        } else if (std.mem.startsWith(u8, s[i..], "(**")) {
            j = if (std.mem.indexOf(u8, s[i + 3 ..], "**)")) |e| i + 3 + e + 3 else s.len;
            style = theme.on(theme.comment_expr, bg);
        } else if (std.mem.startsWith(u8, s[i..], "/*")) {
            j = if (std.mem.indexOf(u8, s[i + 2 ..], "*/")) |e| i + 2 + e + 2 else s.len;
            style = theme.on(theme.comment_block, bg);
        } else if (std.ascii.isDigit(c)) {
            while (j < s.len and (std.ascii.isDigit(s[j]) or s[j] == '.' or s[j] == '_')) j += 1;
            style = theme.on(theme.number, bg);
        } else if (std.ascii.isAlphabetic(c) or c == '_') {
            while (j < s.len and (std.ascii.isAlphanumeric(s[j]) or s[j] == '_')) j += 1;
            if (wordColor(s[i..j])) |color| style = theme.on(color, bg);
        } else {
            // a character that is not a word: one UTF-8 character at a time
            const n = std.unicode.utf8ByteSequenceLength(c) catch 1;
            j = @min(s.len, i + n);
        }
        col = put(w, col, 0, s[i..j], style);
        i = j;
    }
}

// Zig tip: the SQL words are written in lower case and compared with the lower-cased word, because SQL does not care
// about the case. `std.ascii.lowerString` fills a small buffer: a word longer than the buffer is not a keyword.
const sql_keywords = [_][]const u8{
    "select",   "insert",  "update",     "delete",    "create",  "drop",      "alter",   "table",       "view",      "index",     "trigger",
    "into",     "values",  "set",        "as",        "distinct", "union",    "all",     "pragma",      "begin",     "commit",    "rollback",
    "transaction", "with", "recursive",  "replace",   "explain", "vacuum",    "analyze", "attach",      "detach",    "primary",   "key",
    "foreign",  "references", "default", "unique",    "check",   "constraint", "add",    "column",      "rename",    "to",        "if",
    "exists",   "temp",    "temporary",  "virtual",   "returning", "autoincrement", "cascade", "restrict", "conflict", "ignore",   "fail",
    "abort",    "database", "schema",    "truncate",  "grant",   "revoke",    "call",    "show",        "describe",  "use",       "load",
};
const sql_control = [_][]const u8{
    "from", "where", "join", "inner", "left", "right", "full", "outer", "cross", "natural", "on", "using", "group", "by",
    "order", "having", "limit", "offset", "case", "when", "then", "else", "end", "over", "partition", "window", "filter",
};
const sql_operators = [_][]const u8{ "and", "or", "not", "in", "is", "like", "glob", "between", "escape", "collate", "asc", "desc", "match", "regexp", "exists" };
const sql_constants = [_][]const u8{ "null", "true", "false", "current_timestamp", "current_date", "current_time" };
const sql_types = [_][]const u8{
    "integer", "int", "bigint", "smallint", "tinyint", "real", "double", "float", "numeric", "decimal", "text", "varchar", "char",
    "blob", "boolean", "date", "datetime", "timestamp", "uuid", "json", "huge", "interval",
};

fn inLower(list: []const []const u8, word: []const u8) bool {
    for (list) |k| {
        if (std.mem.eql(u8, k, word)) return true;
    }
    return false;
}

/// The color of a word of SQL; null for a name (a table, a column) that keeps the plain color.
fn sqlWordColor(word: []const u8) ?theme.Color {
    var buf: [24]u8 = undefined;
    if (word.len > buf.len) return null;
    const low = std.ascii.lowerString(&buf, word);
    if (inLower(&sql_constants, low)) return theme.number;
    if (inLower(&sql_types, low)) return theme.type_name;
    if (inLower(&sql_operators, low)) return theme.oper;
    if (inLower(&sql_control, low)) return theme.control;
    if (inLower(&sql_keywords, low)) return theme.keyword;
    return null;
}

// Zig tip: the same hand-written scanner as `drawCode`, for SQL: comments `-- ...` and `/* ... */`, strings in single
// quotes ('' inside is a quote), names in double quotes, numbers, words. A word followed by `(` that is not a keyword is
// a function (COUNT, SUM, ...). A block comment is colored on its own line only: the scanner keeps no state between lines.
/// Draw one line of SQL from byte `start`, with the colors of the theme.
fn drawSql(w: Window, line: []const u8, start: usize, bg: theme.Color) void {
    const s = line[start..];
    const plain = theme.on(theme.text, bg);
    var col: u16 = 0;
    var i: usize = 0;
    while (i < s.len) {
        const c = s[i];
        var j = i + 1;
        var style = plain;
        if (c == '\'') {
            while (j < s.len) : (j += 1) {
                if (s[j] == '\'') {
                    if (j + 1 < s.len and s[j + 1] == '\'') {
                        j += 1;
                        continue;
                    }
                    j += 1;
                    break;
                }
            }
            style = theme.on(theme.string, bg);
        } else if (c == '"') {
            while (j < s.len and s[j] != '"') j += 1;
            if (j < s.len) j += 1;
            style = theme.on(theme.type_name, bg);
        } else if (c == '-' and i + 1 < s.len and s[i + 1] == '-') {
            j = s.len;
            style = theme.on(theme.comment, bg);
        } else if (std.mem.startsWith(u8, s[i..], "/*")) {
            j = if (std.mem.indexOf(u8, s[i + 2 ..], "*/")) |e| i + 2 + e + 2 else s.len;
            style = theme.on(theme.comment_block, bg);
        } else if (std.ascii.isDigit(c)) {
            while (j < s.len and (std.ascii.isDigit(s[j]) or s[j] == '.')) j += 1;
            style = theme.on(theme.number, bg);
        } else if (std.ascii.isAlphabetic(c) or c == '_') {
            while (j < s.len and (std.ascii.isAlphanumeric(s[j]) or s[j] == '_')) j += 1;
            if (sqlWordColor(s[i..j])) |color| {
                style = theme.on(color, bg);
            } else if (j < s.len and s[j] == '(') {
                style = theme.on(theme.blue, bg);
            }
        } else {
            const n = std.unicode.utf8ByteSequenceLength(c) catch 1;
            j = @min(s.len, i + n);
        }
        col = put(w, col, 0, s[i..j], style);
        i = j;
    }
}

// Zig tip: `[_][]const u8{ ... }` is an array of string slices whose length the compiler counts. These
// lists are hand-written (the interruptions and the types of SCL, see `eve1.js` of the tutorial); the
// generated `keywords.words` holds all the keywords, and what is not in a list here is a plain keyword.
// `return` is not here: it closes a block, like the keywords that open one (`procedure`), and has their color.
const interrupt_words = [_][]const u8{ "abort", "break", "exit", "panic", "raise", "resume", "retry", "skip", "stop", "yield" };
const control_words = [_][]const u8{ "do", "done", "else", "for", "if", "job", "loop", "match", "parallel", "repeat", "then", "when", "while" };
const operator_words = [_][]const u8{ "and", "as", "eq", "in", "is", "not", "or", "xor" };
const type_words = [_][]const u8{
    "Byte", "Short", "Integer", "Natural", "Huge", "Real", "Float", "Decimal", "Rational", "String", "Logic", "Table",
    "Rune", "Record", "Ordinal", "Variant", "Date", "Time", "Array", "List", "Object", "Class", "Lambda", "Function",
    "DataSet", "DataMap", "Folder", "File", "Null", "True", "False", "Type",
};

// Zig tip: a parameter of type `[]const []const u8` is a slice of strings; passing `&array` turns the
// address of a fixed array into such a slice. `for (list) |k|` visits each word.
fn inList(list: []const []const u8, word: []const u8) bool {
    for (list) |k| {
        if (std.mem.eql(u8, k, word)) return true;
    }
    return false;
}

// Zig tip: A function that returns `?Color` says "a color or nothing": `null` means the word is not
// special and keeps the plain text color. The caller unpacks it with `if (...) |color|`.
// A linear search over short lists is fast enough for the few lines on the screen.
/// The color of a word: type, interruption, control word, operator word or keyword (`null` for none).
fn wordColor(word: []const u8) ?theme.Color {
    if (inList(&type_words, word)) return theme.type_name;
    if (inList(&interrupt_words, word)) return theme.interrupt;
    if (inList(&control_words, word)) return theme.control;
    if (inList(&operator_words, word)) return theme.oper;
    if (inList(&keywords.words, word)) return theme.keyword;
    return null;
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
    _ = put(box, 10, 5, if (isServerPath(tab.path)) "server (a folder of the server side)" else "client", theme.on(theme.text, theme.deep));
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

// Zig tip: The bar belongs to the Tools Panel: it is drawn above it and is not on the screen when that panel is hidden.
// A button that cannot act now is drawn dimmed and its hit is `.nop`, so a click on it does nothing.
fn debugBar(app: *App, win: Window, x0: u16, y: u16, rw: u16) !void {
    const bar = sub(win, x0, y, rw, 1);
    fillWith(bar, theme.panel);
    const on = theme.onBold(theme.bright, theme.green_bg);
    const stop = theme.onBold(theme.bright, theme.red);
    const off = theme.on(theme.faint, theme.panel);
    const idle = theme.on(theme.text, theme.bar);
    var x: u16 = 0;
    // The commands of the debugger, all as wide as the widest label. Run is "Running" (red, blinking) while a program runs;
    // then Halt is active, and the others wait. A stopped program is run again with Run.
    const labels = [_][]const u8{ "▶ Run", "● Running", "■ Halt", "↷ Next", "↓ Step", "↑ Exit", "⇉ Trace" };
    var bw: u16 = 0;
    for (labels) |l| bw = @max(bw, bar.gwidth(l));
    const paused = app.debugPaused();
    // a program of evetx (`job`) or a request of the machine (`!dir`, an eval) is running: Halt is on
    const alive = app.job != null or app.linkBusy();
    const free_run = alive and !paused;
    const blink = @mod(@divFloor(app.nowMs(), 500), 2) == 0;
    // Run (and the debugger buttons that start a program) work on an Eve file only, for now; a program that is already
    // running or stopped can always be driven
    const eve_file = app.canRun();
    const can_start = eve_file or alive;
    const run_style = if (free_run) (if (blink) theme.onBold(theme.bright, theme.red) else theme.onBold(theme.red, theme.bar)) else if (can_start) on else off;
    x = try fixedButton(app, bar, x, if (free_run) labels[1] else labels[0], bw, run_style, if (free_run or !can_start) .nop else .{ .button = .run });
    x += 1;
    x = try fixedButton(app, bar, x, labels[2], bw, if (alive) stop else off, if (alive) .{ .button = .halt } else .nop);
    x += 1;
    const dbg_style = if (free_run or !can_start) off else idle;
    x = try fixedButton(app, bar, x, labels[3], bw, dbg_style, if (free_run or !can_start) .nop else .{ .button = .next });
    x += 1;
    x = try fixedButton(app, bar, x, labels[4], bw, dbg_style, if (free_run or !can_start) .nop else .{ .button = .step });
    x += 1;
    x = try fixedButton(app, bar, x, labels[5], bw, dbg_style, if (free_run or !can_start) .nop else .{ .button = .exit });
    x += 1;
    _ = try fixedButton(app, bar, x, labels[6], bw, dbg_style, if (free_run or !can_start) .nop else .{ .button = .trace });
    // At the right end: the lock of the layout (locked: the borders between the panels stay; open: they can be dragged).
    if (rw > 60) {
        const locked = !app.modify;
        _ = put(bar, rw - 4, 0, if (locked) " 🔒 " else " 🔓 ", theme.onBold(if (locked) theme.text else theme.amber, theme.panel));
        try addHit(app, bar, rw - 4, 0, 4, 1, .lock_toggle);
    }
}

// Zig tip: `for (tabs, names) |t, n|` walks two arrays of the same length together. The label is a
// different string for the Breaks tab when there are breakpoints.
fn toolsPanel(app: *App, win: Window, r: Rect) !void {
    if (r.w == 0) return;
    const box = try panelBox(app, win, r, .tools);
    fillWith(box, theme.deep);
    const strip = sub(box, 0, 0, box.width, 1);
    fillWith(strip, theme.bar2);
    const tabs = [_]app_mod.BottomTab{ .console, .watch, .stderr, .stdout, .breaks, .sql };
    const names = [_][]const u8{ "Console", "Watch", "Stderr", "Stdout", "Breaks", "SQL" };
    var x: u16 = 0;
    for (tabs, names) |t, n| {
        const label = if (t == .breaks and app.breakpoints.items.len > 0)
            app.fmt(" {s} ({d}) ", .{ n, app.breakpoints.items.len })
        else if (t == .watch and app.watch_log.lines.items.len > 0)
            app.fmt(" {s} ({d}) ", .{ n, app.watch_log.lines.items.len })
        else
            app.fmt(" {s} ", .{n});
        const on = app.bottom == t;
        _ = put(strip, x, 0, label, if (on) theme.onBold(theme.deep, theme.blue) else theme.on(theme.text, theme.bar2));
        const w = strip.gwidth(label);
        try addHit(app, strip, x, 0, w, 1, .{ .bottom = t });
        x += w + 1;
    }
    try titleButtons(app, box, .tools);
    const body = sub(box, 0, 2, box.width, box.height -| 2);
    fillWith(body, theme.deep);
    switch (app.bottom) {
        .console => try consolePanel(app, body),
        .stdout => logPanel(app, body, &app.stdout_log, "nothing yet: run a program (F5)"),
        .stderr => logPanel(app, body, &app.stderr_log, "nothing yet: run a program (F5)"),
        .watch => logPanel(app, body, &app.watch_log, "the variables of the program show here when the debugger stops it (Next, Step, Trace)"),
        .breaks => try breaksPanel(app, body),
        .sql => try sqlPanel(app, body),
    }
}

// Zig tip: A long line is cut into pieces of at most `cap` cells (a cell is a column of the screen; a wide character counts
// two), and each piece gets its own row: this is the wrapping of the logs. `segCount` says how many rows a line needs and
// `segText` gives the piece number `seg`. They walk the characters with `std.unicode.Utf8View`, never cutting one in two.
/// How many rows the text needs when a row holds `cap` cells.
fn segCount(w: Window, s: []const u8, cap: usize) usize {
    if (cap == 0) return 1;
    var cells: usize = 0;
    var rows: usize = 1;
    var it = (std.unicode.Utf8View.init(s) catch return 1).iterator();
    while (it.nextCodepointSlice()) |ch| {
        const cw: usize = @max(1, w.gwidth(ch));
        if (cells + cw > cap) {
            rows += 1;
            cells = 0;
        }
        cells += cw;
    }
    return rows;
}

/// The piece `seg` (from 0) of the text, when a row holds `cap` cells.
fn segText(w: Window, s: []const u8, cap: usize, seg: usize) []const u8 {
    if (cap == 0) return s;
    var cells: usize = 0;
    var row: usize = 0;
    var start: usize = 0;
    var pos: usize = 0;
    var it = (std.unicode.Utf8View.init(s) catch return s).iterator();
    while (it.nextCodepointSlice()) |ch| {
        const cw: usize = @max(1, w.gwidth(ch));
        if (cells + cw > cap) {
            if (row == seg) return s[start..pos];
            row += 1;
            start = pos;
            cells = 0;
        }
        cells += cw;
        pos += ch.len;
    }
    return if (row == seg) s[start..] else "";
}

/// The prompt that a kind of line starts with, and its width.
fn logPrefix(kind: app_mod.LineKind) []const u8 {
    return switch (kind) {
        .input => "eve:> ",
        .shell => "$ ",
        .sql => "SQL:> ",
        else => "",
    };
}

// Zig tip: A `switch` on the kind of line gives each kind its color. The prompt is drawn on the first row of a line only;
// the other rows of a wrapped line start under the text, so the columns line up.
fn logLine(w: Window, row: u16, l: app_mod.LogLine, seg: usize, cap: usize) void {
    const piece = segText(w, l.text, cap, seg);
    const prefix = logPrefix(l.kind);
    const pw: u16 = @intCast(prefix.len);
    const x: u16 = 1 + pw;
    switch (l.kind) {
        .input => {
            if (seg == 0) _ = put(w, 1, row, prefix, theme.onBold(theme.green, theme.deep));
            _ = put(w, x, row, piece, theme.on(theme.bright, theme.deep));
        },
        .shell => {
            if (seg == 0) _ = put(w, 1, row, prefix, theme.onBold(theme.green, theme.deep));
            _ = put(w, x, row, piece, theme.on(theme.bright, theme.deep));
        },
        .out => _ = put(w, 1, row, piece, theme.on(theme.text, theme.deep)),
        .err => _ = put(w, 1, row, piece, theme.on(theme.red, theme.deep)),
        .info => _ = put(w, 1, row, piece, theme.on(theme.dim, theme.deep)),
        .sql => {
            if (seg == 0) _ = put(w, 1, row, prefix, theme.onBold(theme.blue, theme.deep));
            drawSql(sub(w, x, row, w.width -| x, 1), piece, 0, theme.deep);
        },
    }
}

// Zig tip: The rows are counted from the end: lines are taken from the last one (less `scroll`) backwards until the window
// is full. The first line taken may be only partly visible, so its first pieces are skipped (`skip`). Then the lines are
// drawn from the top. The scroll bar counts lines, not rows: it shows where the view is in the list of lines.
/// Draw the last lines of a log into `w` (the line `scroll` lines above the end is the last one shown); long lines wrap.
fn drawLog(app: *App, w: Window, log: *app_mod.Log) void {
    app.console_rect = absRect(w, 0, 0, w.width, w.height);
    const rows: usize = w.height;
    const total = log.lines.items.len;
    log.scroll = @min(log.scroll, total -| 1);
    const end = total - log.scroll;
    // is a bar needed? Then the rows are one cell narrower
    var bar = false;
    var cap: usize = (@as(usize, w.width) -| 2);
    var pass: u8 = 0;
    var first = end;
    var skip: usize = 0;
    while (pass < 2) : (pass += 1) {
        first = end;
        var used: usize = 0;
        while (first > 0 and used < rows) {
            const l = log.lines.items[first - 1];
            const pw = logPrefix(l.kind).len;
            used += segCount(w, l.text, cap -| pw);
            first -= 1;
        }
        skip = used -| rows;
        bar = total > end - first or first > 0;
        if (bar and pass == 0 and w.width > 3) {
            cap = (@as(usize, w.width) -| 3);
            continue;
        }
        break;
    }
    var r: u16 = 0;
    var i = first;
    while (i < end and r < rows) : (i += 1) {
        const l = log.lines.items[i];
        const pw = logPrefix(l.kind).len;
        const n = segCount(w, l.text, cap -| pw);
        var s: usize = if (i == first) skip else 0;
        while (s < n and r < rows) : (s += 1) {
            logLine(w, r, l, s, cap -| pw);
            r += 1;
        }
    }
    // the scroll bar: arrows at the ends and a thumb at the place of the view in the log
    if (bar and w.width > 3) {
        _ = vBar(app, w, w.width - 1, w.height, total, first, @max(1, end - first), .{ .log_scroll = .up }, .{ .log_scroll = .down });
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
    _ = put(body, 1, 0, "On Del File : line", theme.on(theme.dim, theme.deep));
    if (app.breakpoints.items.len == 0) {
        _ = put(body, 2, 2, "No breakpoints. Press F9 on a line of the editor.", theme.on(theme.faint, theme.deep));
        return;
    }
    const cap: usize = body.height -| 2;
    const n = app.breakpoints.items.len;
    // the first row shown: moved only as far as the selected breakpoint needs, and never past the end
    if (app.break_sel < app.break_top) app.break_top = app.break_sel;
    if (cap > 0 and app.break_sel >= app.break_top + cap) app.break_top = app.break_sel + 1 - cap;
    app.break_top = @min(app.break_top, n -| cap);
    app.breaks_rect = absRect(body, 0, 1, body.width, body.height -| 2);
    const text_w: u16 = if (n > cap) body.width -| 1 else body.width;
    var r: usize = 0;
    while (r < cap and app.break_top + r < n) : (r += 1) {
        const i = app.break_top + r;
        const bp = app.breakpoints.items[i];
        const sel = i == app.break_sel;
        const row = sub(body, 0, @intCast(r + 1), text_w, 1);
        fillWith(row, if (sel) theme.selected else theme.deep);
        const bg = if (sel) theme.selected else theme.deep;
        _ = put(row, 1, 0, if (bp.enabled) "[x]" else "[ ]", theme.on(if (bp.enabled) theme.red else theme.faint, bg));
        _ = put(row, 5, 0, "🗑", theme.on(theme.dim, bg));
        _ = put(row, 8, 0, app.fmt("{s} : {d}", .{ bp.path, bp.line }), theme.on(if (sel and bp.enabled) theme.bright else if (bp.enabled) theme.text else theme.faint, bg));
        try addHit(app, row, 0, 0, text_w, 1, .{ .break_row = i });
        try addHit(app, row, 1, 0, 3, 1, .{ .break_toggle = i });
        try addHit(app, row, 5, 0, 2, 1, .{ .break_trash = i });
    }
    if (n > cap and cap > 0) {
        const col = sub(body, 0, 1, body.width, @intCast(cap));
        _ = vBar(app, col, col.width - 1, col.height, n, app.break_top, cap, .{ .break_scroll = .up }, .{ .break_scroll = .down });
    }
    _ = put(body, 1, body.height -| 1, "Enter or a second click jumps · Space switches · Del removes", theme.on(theme.dim, theme.deep));
}

// Zig tip: the SQL panel has the same shape as the console: the output scrolls above, then a rule and the prompt. The
// line being typed is drawn by `drawSql`, so it has the colors of SQL, and the cursor of the terminal is put by hand
// (`showCursor`) at the width of the text before the cursor, since `TextInput.drawWithStyle` knows one style only.
/// The SQL panel: type a statement, Enter runs it on the database (`use <file.db>`, `clear`), the result is a table.
fn sqlPanel(app: *App, body: Window) !void {
    const h = body.height;
    if (h < 3) return;
    const out = sub(body, 0, 0, body.width, h - 2);
    if (app.sql_log.lines.items.len == 0) {
        _ = put(out, 2, 0, "SQL goes to the table or the database that is selected · use <file.db> chooses a file, use auto goes back · clear empties this panel", theme.on(theme.faint, theme.deep));
        app.console_rect = absRect(out, 0, 0, out.width, out.height);
    } else drawLog(app, out, &app.sql_log);
    _ = put(body, 0, h - 2, "─" ** 400, theme.on(theme.line, theme.deep));
    // the target of the SQL, on the rule, at the right
    const target = clipText(app.fmt(" {s} ", .{app.sqlTargetText()}), body.width -| 4);
    _ = put(body, body.width -| (body.gwidth(target) + 2), h - 2, target, theme.onBold(theme.blue, theme.deep));
    _ = put(body, 1, h - 1, "SQL:> ", theme.onBold(theme.blue, theme.deep));
    const line = sub(body, 7, h - 1, body.width -| 8, 1);
    fillWith(line, theme.deep);
    const first = app.sql_in.buf.firstHalf();
    const second = app.sql_in.buf.secondHalf();
    const joined = app.fmt("{s}{s}", .{ first, second });
    drawSql(line, joined, 0, theme.deep);
    if (app.focus == .sql and app.overlay == .none) line.showCursor(@intCast(@min(line.gwidth(first), line.width -| 1)), 0);
}

/// What the status bar says about the current window after its name: kind, size, line ends. The
/// project name is not repeated here: it is in the title bar of the Tree Panel.
fn fileFacts(app: *App) []const u8 {
    const t = app.activeTab() orelse return "";
    if (t.folder) |fv| return app.fmt(" · folder · {d} items", .{fv.items.items.len});
    if (t.table) |tv| return app.fmt(" · DBF table · {d} records · {d} fields", .{ tv.t.records, tv.t.fields.len });
    if (t.buf) |*b| {
        if (t.virtual) return app.fmt(" · read only · {d} lines", .{b.lineCount()});
        const kind: []const u8 = if (t.eve) "Eve source" else if (t.sql) "SQL" else "text";
        return app.fmt(" · {s} · {d} lines · {s}{s}", .{ kind, b.lineCount(), if (b.crlf) "CRLF" else "LF", if (b.dirty) " · modified" else "" });
    }
    return app.fmt(" · {s} · {s}", .{ t.card.kind, sizeText(app, t.card.size) });
}

// Zig tip: The bar has two parts. At the left the name of the current file with its path from the
// project folder (or a message or the running state, which take its place for a moment); at the
// right a fixed panel of 16 cells with the line and the column. `{d:>4}` prints a number right
// aligned in 4 cells, so the panel is wide enough for 9999 lines and 999 columns and does not move.
fn statusBar(app: *App, win: Window) !void {
    const W = win.width;
    const H = win.height;
    const box = boxed(win, 0, H - 3, W, 3, theme.line);
    fillWith(box, theme.deep);
    const w = box.width;
    const pos_w: u16 = 16;
    const pos_x: u16 = w -| (pos_w + 1);
    const left_w = pos_x -| 3;
    _ = put(box, pos_x -| 2, 0, "│", theme.on(theme.line, theme.deep));

    if (app.modify) {
        const hint = if (app.freeze_at != null)
            "Layout modify · it freezes in a moment · drag again to go on"
        else if (app.mouse_modify)
            "Layout modify · drag the border · Ctrl+F freezes at once"
        else
            "Layout modify · drag the borders or use the arrow keys · Ctrl+F or Esc freezes";
        _ = put(box, 1, 0, clipText(hint, left_w), theme.onBold(theme.amber, theme.deep));
    } else if (app.pendingLeft()) |ms| {
        const secs: i64 = @divFloor(ms + 999, 1000);
        const cmd_text = app.pending_text orelse "";
        _ = put(box, 1, 0, clipText(app.fmt("▶ {s} starts in {d}s · Enter runs now · Esc cancels · typing keeps it", .{ cmd_text, secs }), left_w), theme.onBold(theme.amber, theme.deep));
    } else if (app.message) |m| {
        _ = put(box, 1, 0, clipText(m, left_w), theme.onBold(theme.amber, theme.deep));
    } else if (app.running) {
        _ = put(box, 1, 0, "Running…", theme.onBold(theme.amber, theme.deep));
    } else if (app.activeTab()) |t| {
        const name = if (t.path.len == 0) "untitled" else t.path;
        const shown = clipText(name, left_w);
        const c = put(box, 1, 0, shown, theme.onBold(theme.bright, theme.deep));
        if (c + 2 < left_w + 1) _ = put(box, c, 0, clipText(fileFacts(app), left_w + 1 -| c), theme.on(theme.dim, theme.deep));
    } else {
        _ = put(box, 1, 0, "Ready", theme.on(theme.green, theme.deep));
    }

    if (app.activeBuffer()) |b| {
        putRight(box, w -| 2, 0, app.fmt("Ln {d:>4}, Col {d:>3}", .{ b.row + 1, b.displayCol() + 1 }), theme.on(theme.text, theme.deep));
    } else if (if (app.activeTab()) |t| t.table else null) |tv| {
        putRight(box, w -| 2, 0, app.fmt("Rec {d:>6}/{d}", .{ tv.row + 1, tv.t.records }), theme.on(theme.text, theme.deep));
    } else {
        putRight(box, w -| 2, 0, "Ln    -, Col   -", theme.on(theme.faint, theme.deep));
    }
}

// ------------------------------------------------------------------ overlays

// Zig tip: `addHit(...) catch {}` ignores an error on purpose: the empty block after `catch` is the
// whole handler. It is right here because the only error is "out of memory", and the worst result
// is that a click inside the dialog closes it.
/// Make the rectangle of a dialog a click that does nothing, so a click on its text does not close it.
fn solid(app: *App, win: Window, x: u16, y: u16, w: u16, h: u16) void {
    addHit(app, win, x, y, w, h, .nop) catch {};
}

// Zig tip: The close button of every dialog is the same: ` × ` drawn at a place, and a hit with the
// action `close_overlay`. Making it a function keeps all dialogs alike.
/// The × button that closes a dialog.
fn closeButton(app: *App, win: Window, x: u16, y: u16, style: Style) void {
    _ = put(win, x, y, " × ", style);
    addHit(app, win, x, y, 3, 1, .close_overlay) catch {};
}

// Zig tip: `@as(u32, ww) * 10 <= @as(u32, main.w) * 9` is the test "ww <= 90% of main.w" in whole numbers: both sides
// are multiplied by 10, so no floating point is needed, and widening to `u32` first keeps the product from overflowing.
// Zig tip: the shadow is made of the cells that touch the box on its right and under it, one cell wide and one row high,
// shifted by one: each keeps its character and its text color and gets a darker background, so what is behind the dialog is
// still readable, like under a real shadow. `win.readCell` gives the cell that is already drawn; `writeCell` puts it back.
// It is only for light themes: on a dark one a shadow would not show.
/// Draw the shadow of a box at (x, y) of `win`, `w` cells wide and `h` rows high (light themes only).
fn shadow(win: Window, x: u16, y: u16, w: u16, h: u16) void {
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

fn darken(win: Window, col: u16, row: u16) void {
    var cell = win.readCell(col, row) orelse vaxis.Cell{ .char = .{ .grapheme = " ", .width = 1 } };
    cell.style.bg = theme.line;
    cell.style.fg = theme.text;
    win.writeCell(col, row, cell);
}

// Returns the window inside the dialog so that the caller draws its lines at fixed rows.
// `@min(w, win.width -| 2)` keeps it inside a small window.
/// A dialog in the middle of the screen: returns the inside, the first row holds the title and the × button.
fn dialog(app: *App, win: Window, w: u16, h: u16, title: []const u8) Window {
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

// Zig tip: The search dialogs sit at the top right, under the menu bar, so the code stays visible
// while the user searches. The title and the × button are written over the top border of the box,
// in the parent window.
/// A small dialog at the top right of the screen: returns the inside.
fn topDialog(app: *App, win: Window, w: u16, h: u16, title: []const u8) Window {
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

// Zig tip: A struct for a button lets a dialog list its buttons as data: `buttonRow` lays them out
// from the right edge, the usual place of OK and Cancel. `primary` marks the one that Enter does.
const Btn = struct { label: []const u8, action: Action, primary: bool = false, enabled: bool = true };

/// A row of buttons at the right end of row `y` of a dialog.
fn buttonRow(app: *App, box: Window, y: u16, specs: []const Btn) !void {
    var total: u16 = 0;
    for (specs) |b| total += box.gwidth(b.label) + 3;
    var x: u16 = box.width -| (total + 1);
    for (specs) |b| {
        const style = if (!b.enabled) theme.on(theme.faint, theme.panel) else if (b.primary) theme.onBold(theme.bright, theme.green_bg) else theme.on(theme.text, theme.bar);
        x = try button(app, box, x, y, b.label, style, if (b.enabled) b.action else .nop) + 1;
    }
}

const ok_btn: Action = .{ .dlg = .ok };

// Zig tip: The popup menu of a tab opens at the place of the click. `@min(x, win.width -| w)` keeps it
// inside the screen when the click is near the right edge. The rows are hits like the rows of the
// main menu, and the mouse hover moves the selection.
/// The popup menu of a tab (right click on its title).
fn tabMenuBox(app: *App, win: Window) !void {
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
            _ = put(box, 0, r, "─" ** 60, theme.on(theme.line, theme.panel));
            continue;
        }
        _ = put(line, 1, 0, row.label, theme.on(if (sel) theme.bright else theme.text, bg));
        try addHit(app, box, 0, r, box.width, 1, .{ .tabmenu_item = i });
    }
}

// Zig tip: the facts are a fixed array of label and value pairs; `n` counts the ones that apply (an optional fact with no
// value is left out), and the height of the dialog follows. The name is the first row: Rename turns it into a field in
// the same place; the folder is a fact of its own, changed with Move (the folder selector).
/// The Info dialog (Info… of a tab, File > Rename…): `File: name` (or `Table:`, `View:`, `Folder:`), a rule, the facts.
fn propertiesBox(app: *App, win: Window) !void {
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
    _ = put(box, 0, 1, "─" ** 200, theme.on(theme.line, theme.panel));
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

// Zig tip: the dialog says where the table will go before the name is typed: the selected database (a SQLite table) or the
// folder (a DBF table), so the choice is never a surprise.
/// EDIT > Create table…: the name of the new table.
fn newTableBox(app: *App, win: Window) !void {
    const box = dialog(app, win, 70, 11, "Create table");
    const dim = theme.on(theme.dim, theme.panel);
    const db = app.selectedDb();
    _ = put(box, 2, 1, if (db != null) app.fmt("A SQLite table in the database {s}", .{db.?}) else app.fmt("A DBF table in the folder {s}", .{app.createTableTarget()}), theme.on(theme.text, theme.panel));
    _ = put(box, 2, 3, "Name of the table:", dim);
    const f = sub(box, 2, 4, box.width -| 4, 1);
    fillWith(f, theme.bar);
    app.saveas_in.drawWithStyle(f, theme.on(theme.bright, theme.bar));
    _ = put(box, 2, 6, "Select a database in the tree for a SQLite table, a folder for a DBF table.", dim);
    try buttonRow(app, box, box.height -| 2, &.{
        .{ .label = "Next", .action = ok_btn, .primary = true },
        .{ .label = "Cancel", .action = .close_overlay },
    });
}

// Zig tip: the width of the dialog follows the message (`gwidth` counts cells, not bytes), with a minimum, so a short or a
// long question fits. The two buttons are the usual `buttonRow`; Yes is the primary one (Enter), and the keys Y and N work.
/// The confirmation dialog: a message and Yes / No. Reused by every question (`App.askConfirm`).
fn confirmBox(app: *App, win: Window) !void {
    const msg = app.confirm_msg orelse "Are you sure?";
    const w: u16 = @max(40, win.gwidth(msg) + 6);
    const box = dialog(app, win, w, 7, "Confirm");
    _ = put(box, 2, 2, msg, theme.on(theme.text, theme.panel));
    try buttonRow(app, box, box.height -| 2, &.{
        .{ .label = "Yes", .action = .{ .confirm = true }, .primary = true },
        .{ .label = "No", .action = .{ .confirm = false } },
    });
}

// Zig tip: the grid is drawn with box characters from a repeated string: `"─" ** 40` is made when the program is compiled,
// and `hl[0 .. 3 * w]` takes `w` of them (each is 3 bytes in UTF-8). Every cell is a hit with its row and column; the
// type list is drawn last, over the grid, so it is on top and its hits are found first.
/// The structure dialog of a DBF table (design/design-structure.svg): a grid of the fields, one row each; Name, Type,
/// Length and Decimals are the columns, the type is chosen from a list.
fn structureBox(app: *App, win: Window) !void {
    const name = app.st_path orelse "";
    const box = dialog(app, win, 76, 28, app.fmt("Structure of {s}  (FoxPro 2.6 table)", .{name}));
    const dim = theme.on(theme.dim, theme.panel);
    const line = theme.on(theme.line, theme.panel);
    const fields = app.st_fields.items;
    const n = fields.len;
    const per: usize = 10;
    const page = app.st_row / per;
    const pages = (n + per - 1) / per;
    const first = page * per;
    const last = @min(first + per, n);
    _ = put(box, 2, 1, app.fmt("Fields {d}–{d} of {d} · page {d} of {d} · {d} records in the file", .{ first + 1, last, n, page + 1, pages, app.st_records }), theme.on(theme.text, theme.panel));
    _ = put(box, 2, 2, "arrows move · Enter edits · Ins adds · Del removes · Ctrl+Up/Down moves · Ctrl+S applies", dim);
    const widths = [_]u16{ 4, 12, 26, 8, 10 };
    const heads = [_][]const u8{ "#", "Name", "Type", "Length", "Decimals" };
    const hl = "─" ** 40;
    // borders: top, header separator, bottom
    var rule_buf: [3][256]u8 = undefined;
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
    var col_x: [5]u16 = undefined;
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
        const s = fields[r];
        const selrow = r == app.st_row;
        _ = put(box, gx, y, "│", line);
        var texts: [5][]const u8 = undefined;
        texts[0] = app.fmt("{d}", .{r + 1});
        texts[1] = app.fmt("{s}", .{s.f.nameSlice()}); // a copy: `s` is a local, and the screen keeps the pointer
        texts[2] = app.fmt("{c} {s}", .{ s.f.kind, dbf.kindName(s.f.kind) });
        texts[3] = if (s.f.kind == 'C' or s.f.kind == 'N' or s.f.kind == 'F') app.fmt("{d}", .{s.f.length}) else app.fmt("{d}", .{s.f.length});
        texts[4] = if (s.f.kind == 'N' or s.f.kind == 'F') app.fmt("{d}", .{s.f.decimals}) else "";
        for (widths, 0..) |w, k| {
            const kk: u8 = @intCast(k);
            const sel_cell = selrow and k > 0 and app.st_col == k - 1;
            const bg = if (sel_cell) theme.bar else if (selrow) theme.selected else theme.panel;
            const cell = sub(box, col_x[k], y, w, 1);
            fillWith(cell, bg);
            const editable = k == 1 or k == 2 or (k == 3 and (s.f.kind == 'C' or s.f.kind == 'N' or s.f.kind == 'F')) or (k == 4 and (s.f.kind == 'N' or s.f.kind == 'F'));
            const fg = if (sel_cell) theme.bright else if (editable or k == 0) theme.text else theme.faint;
            if (app.st_editing and sel_cell) {
                app.st_edit.drawWithStyle(cell, theme.on(theme.bright, theme.bar));
            } else {
                _ = put(cell, 1, 0, clipText(texts[k], w -| 2), theme.on(fg, bg));
            }
            if (k == 2) {
                _ = put(cell, w -| 2, 0, "▾", theme.onBold(theme.amber, bg));
                try addHit(app, box, col_x[k] + w -| 2, y, 2, 1, .st_drop_open);
            }
            if (k > 0) try addHit(app, box, col_x[k], y, if (k == 2) w -| 2 else w, 1, .{ .st_cell = .{ .row = @intCast(r), .col = @intCast(k - 1) } });
            _ = put(box, col_x[k] + w, y, "│", line);
            _ = kk;
        }
    }
    _ = put(box, gx, @intCast(7 + last - first), rules[2], line);
    // what is pending, and what is wrong
    const changes = app.stChanges();
    _ = put(box, 2, 20, if (changes == 0) "no changes yet" else app.fmt("{d} change(s) pending", .{changes}), theme.on(theme.amber, theme.panel));
    if (app.st_error) |e| _ = put(box, 2, 21, clipText(e, box.width -| 4), theme.on(theme.red, theme.panel));
    try buttonRow(app, box, box.height -| 4, &.{
        .{ .label = "◄ Previous page", .action = .{ .st_btn = .prev } },
        .{ .label = "Next page ►", .action = .{ .st_btn = .next } },
        .{ .label = "+ Add field", .action = .{ .st_btn = .add } },
        .{ .label = "− Remove field", .action = .{ .st_btn = .remove } },
    });
    try buttonRow(app, box, box.height -| 2, &.{
        .{ .label = "Apply", .action = .{ .st_btn = .apply }, .primary = true, .enabled = changes > 0 },
        .{ .label = "Cancel", .action = .close_overlay },
    });
    // the list of types, over the grid
    if (app.st_drop) {
        const dw: u16 = 32;
        const dh: u16 = @intCast(dbf.kinds.len + 2);
        const dx = col_x[2];
        const dy: u16 = @intCast(7 + app.st_row - first + 1);
        solid(app, box, dx, dy, dw, dh);
        const dbox = boxed(box, dx, dy, dw, dh, theme.blue);
        fillWith(dbox, theme.panel);
        for (dbf.kinds, 0..) |k, i| {
            const sel = i == app.st_drop_sel;
            const bg = if (sel) theme.selected else theme.panel;
            const row = sub(dbox, 0, @intCast(i), dbox.width, 1);
            fillWith(row, bg);
            _ = put(row, 1, 0, app.fmt("{c} {s}", .{ k, dbf.kindName(k) }), theme.on(if (sel) theme.bright else theme.text, bg));
            try addHit(app, dbox, 0, @intCast(i), dbox.width, 1, .{ .st_pick = k });
        }
    }
}

// Zig tip: the New dialog shows the folder where the file will go (the selected folder of the tree), a field for the name
// and the types the machine knows; the type is read from the extension when Enter is pressed.
/// File > New…: the name of the new file.
fn newBox(app: *App, win: Window) !void {
    const box = dialog(app, win, 70, 11, "New file");
    const dim = theme.on(theme.dim, theme.panel);
    const dir = app.targetDir();
    _ = put(box, 2, 1, app.fmt("Folder: {s}/", .{if (dir.len == 0) "(the project folder)" else dir}), theme.on(theme.text, theme.panel));
    _ = put(box, 2, 3, "Name, with its extension:", dim);
    const f = sub(box, 2, 4, box.width -| 4, 1);
    fillWith(f, theme.bar);
    app.saveas_in.drawWithStyle(f, theme.on(theme.bright, theme.bar));
    _ = put(box, 2, 6, ".eve  .sql  .dbf  .db  start a wizard · .md .json .txt ... start empty", dim);
    try buttonRow(app, box, box.height -| 2, &.{
        .{ .label = "Next", .action = ok_btn, .primary = true },
        .{ .label = "Cancel", .action = .close_overlay },
    });
}

/// The wizard of an Eve file or an SQL file: a name and what to start from.
fn wizardBox(app: *App, win: Window) !void {
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
fn appendNBox(app: *App, win: Window) !void {
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

// Zig tip: the same design as the structure of a DBF table (a bordered grid, one row for each field), with the columns of a
// SQLite table: Name, Type (from a list), Not null and Key (check boxes, Space or a click switches them) and Default. The
// rule lines are cut from one long string, as in `structureBox`.
/// The structure dialog of a SQLite table.
fn sqStructureBox(app: *App, win: Window) !void {
    const box = dialog(app, win, 92, 28, app.fmt("{s} {s}  ({s}, SQLite)", .{ if (app.sq_new) "New table" else "Structure of", app.sq_table orelse "", app.sq_db orelse "" }));
    const dim = theme.on(theme.dim, theme.panel);
    const line = theme.on(theme.line, theme.panel);
    const cols = app.sq_cols.items;
    const n = cols.len;
    const per: usize = 10;
    const page = app.sq_row / per;
    const pages = (n + per - 1) / per;
    const first = page * per;
    const last = @min(first + per, n);
    _ = put(box, 2, 1, app.fmt("Columns {d}–{d} of {d} · page {d} of {d}", .{ first + 1, last, n, page + 1, pages }), theme.on(theme.text, theme.panel));
    _ = put(box, 2, 2, "arrows move · Enter edits · Space switches a box · Ins adds · Del removes · Ctrl+Up/Down moves · Ctrl+S applies", dim);
    const widths = [_]u16{ 4, 22, 18, 10, 6, 22 };
    const heads = [_][]const u8{ "#", "Name", "Type", "Not null", "Key", "Default" };
    const hl = "─" ** 40;
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

// Zig tip: A `switch` on the optional command: `row.cmd orelse` is not needed because the labels
// that change with the state have a command, and a separator is handled before this function is
// called. The marks `[x]`, `[ ]` and `●` are drawn from the state of the app on every frame, so
// the menu is never out of date.
/// The text of a menu row: its label, with a check box (panels) or a dot (the current window)
/// in front when the row has one.
fn rowLabel(app: *App, row: app_mod.MenuRow) []const u8 {
    const cmd = row.cmd orelse return row.label;
    return switch (cmd) {
        .toggle_tree => app.fmt("[{s}] {s}", .{ if (app.show_tree) "x" else " ", row.label }),
        .toggle_main => app.fmt("[{s}] {s}", .{ if (app.show_main) "x" else " ", row.label }),
        .toggle_tools => app.fmt("[{s}] {s}", .{ if (app.show_tools) "x" else " ", row.label }),
        .toggle_hidden => app.fmt("[{s}] {s}", .{ if (app.show_hidden) "x" else " ", row.label }),
        .toggle_wrap => app.fmt("[{s}] {s}", .{ if (app.wrap) "x" else " ", row.label }),
        .window_pick => app.fmt("{s} {s}", .{ if (row.arg == app.active) "●" else " ", row.label }),
        else => row.label,
    };
}

/// The shortcut shown at the right of a row. A window has Ctrl and its number.
fn rowKey(app: *App, row: app_mod.MenuRow) []const u8 {
    if (row.cmd == .window_pick) return app.fmt("Ctrl+{d}", .{row.arg + 1});
    return row.key;
}

// Zig tip: `@max(a, b)` takes the larger of two numbers; a `for`
// over the rows finds the widest label and shortcut, so the box fits its content.
/// The drop-down of the open menu, under its name in the bar.
fn menuDrop(app: *App, win: Window) !void {
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
    const box = boxed(win, x, 1, w, h, theme.blue);
    fillWith(box, theme.panel);
    k = 0;
    while (k < n and k < box.height) : (k += 1) {
        const row = app.rowAt(m, k);
        const r: u16 = @intCast(k);
        if (row.cmd == null) {
            _ = put(box, 0, r, "─" ** 100, theme.on(theme.line, theme.panel));
            continue;
        }
        const sel = app.menu_sel == k;
        const bg = if (sel) theme.selected else theme.panel;
        const line = sub(box, 0, r, box.width, 1);
        fillWith(line, bg);
        _ = put(line, 1, 0, rowLabel(app, row), theme.on(if (sel) theme.bright else theme.text, bg));
        putRight(line, line.width -| 1, 0, rowKey(app, row), theme.on(if (sel) theme.bright else theme.dim, bg));
        try addHit(app, box, 0, r, box.width, 1, .{ .menu_item = k });
    }
}

// Zig tip: A color from hue, saturation and value (each 0 to 1), for the palette of the Colors tab.
// `@floor` and `@mod` split the hue circle in six parts; `@intFromFloat` makes the final byte. The
// function is pure: the same numbers always give the same color.
/// The color `0xRRGGBB` of a hue (0 to 1), a saturation and a value.
fn hsvHex(h: f32, s: f32, v: f32) u24 {
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

// Zig tip: The dialog has three tabs drawn by three functions; the tab number lives in the app
// (`opt_tab`), so a click and the Tab key change the same thing. The tabs of the dialog are drawn
// like the tabs of the editor: the open one in inverted colors.
/// The Options dialog: Theme, Colors, Timers. The options belong to the user and to the tool; the
/// settings of Eve are in the configuration files of the project.
fn settings(app: *App, win: Window) !void {
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
    _ = put(box, 0, 3, "─" ** 200, theme.on(theme.line, theme.panel));
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

// Zig tip: the list has two groups, the built-in themes and then the custom ones, with a rule between them. The rows that
// are shown start at `first`, moved only as far as the selected theme needs, like the file tree. `opt.count()` is the
// number of themes; the id of a theme is its place in the list, so a click sends that number.
/// The list of themes, the buttons under it (and the field of Rename, Export, Import), and a sample of the theme in use.
fn themeTab(app: *App, body: Window) !void {
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
fn colorsTab(app: *App, body: Window) !void {
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
fn timersTab(app: *App, body: Window) !void {
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

// Zig tip: `@embedFile("eve_zon")` is the text of the root `build.zig.zon` of the repository, copied
// into the program when it is built. The block below runs at compile time (`comptime`): it looks
// for `.version = "` and cuts the text up to the next quote, so the version is written once, in
// that file (D-167), and the About dialog shows it. `@setEvalBranchQuota` allows the compiler to
// run the search over a text of a few thousand bytes.
const eve_version = blk: {
    @setEvalBranchQuota(200_000);
    const zon = @embedFile("eve_zon");
    const key = ".version = \"";
    const at = std.mem.indexOf(u8, zon, key) orelse break :blk "?";
    const rest = zon[at + key.len ..];
    const len = std.mem.indexOfScalar(u8, rest, '"') orelse break :blk "?";
    break :blk rest[0..len];
};

fn about(app: *App, win: Window) !void {
    const box = dialog(app, win, 56, 11, "About");
    _ = put(box, 2, 2, "evetx: the Eve terminal IDE", theme.onBold(theme.bright, theme.panel));
    _ = put(box, 2, 3, app.fmt("Version {s}", .{eve_version}), theme.onBold(theme.green, theme.panel));
    _ = put(box, 2, 5, "A text user interface for Eve projects (level 6).", theme.on(theme.text, theme.panel));
    _ = put(box, 2, 6, "Built on libvaxis. (c) Sage-Code Laboratory", theme.on(theme.dim, theme.panel));
    try buttonRow(app, box, box.height -| 2, &.{.{ .label = "Close", .action = .close_overlay, .primary = true }});
}

// Zig tip: The text field is the one of the `App` (`goto_in`), drawn with `drawWithStyle`; the
// dialog never needs the keyboard focus, because an overlay takes the keys first.
fn gotoBox(app: *App, win: Window) !void {
    const box = topDialog(app, win, 40, 5, "GoTo");
    try field(app, box, 1, 0, box.width -| 2, &app.goto_in, 0, true);
    _ = put(box, 1, 1, "Line, or line:column (42 or 42:7)", theme.on(theme.dim, theme.panel));
    try buttonRow(app, box, 2, &.{
        .{ .label = "Go", .action = ok_btn, .primary = true },
        .{ .label = "Close", .action = .close_overlay },
    });
}

fn findTextBox(app: *App, win: Window) !void {
    const box = topDialog(app, win, 46, 5, "Find Text");
    try field(app, box, 1, 0, box.width -| 2, &app.find_in, 0, true);
    _ = put(box, 1, 1, "Enter finds the next match", theme.on(theme.dim, theme.panel));
    try buttonRow(app, box, 2, &.{
        .{ .label = "Next", .action = ok_btn, .primary = true },
        .{ .label = "Close", .action = .close_overlay },
    });
}

// Zig tip: `app.tree.entries.items[app.selected]` is the entry that the search moved to; the dialog
// shows its path so that the user sees the answer before pressing Enter.
fn findFileBox(app: *App, win: Window) !void {
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

fn replaceBox(app: *App, win: Window) !void {
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

// Zig tip: A dialog with one field. The key handling is in `App.overlayKey`: Enter saves under the
// typed path, Esc closes.
fn saveAsBox(app: *App, win: Window) !void {
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

// Zig tip: A list with a selected row that must stay on the screen: `top` is the first row shown and
// is moved only as far as needed, the same rule as the file tree. The rows are child windows of one
// line; each is a hit with the number of the project.
/// File > Open project: the projects of the cache, one row each.
fn projectBox(app: *App, win: Window) !void {
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
// Zig tip: one dialog for four uses (`app.fb_mode`): a `switch` picks the title and the main button; Export and Import
// also list the theme files (`.json`) after the folders and have a name field under the list, so the list is two rows
// shorter for them.
/// The folder selector: Open Folder, Move (a file of the Info dialog), Export and Import of a theme.
fn folderBox(app: *App, win: Window) !void {
    const with_name = app.fbHasName();
    const title: []const u8, const ok_label: []const u8 = switch (app.fb_mode) {
        .project => .{ "Open Folder", "Open as project" },
        .move_to => .{ app.fmt("Move {s} to a folder", .{app.infoName()}), "Move here" },
        .theme_export => .{ "Export theme", "Export" },
        .theme_import => .{ "Import theme", "Import" },
    };
    const box = dialog(app, win, 78, 22, title);
    const dim = theme.on(theme.dim, theme.panel);
    _ = put(box, 0, 1, "─" ** 200, theme.on(theme.line, theme.panel));
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
    if (need_bar) _ = vBar(app, frame, frame.width - 1, list_h, n, app.fb_top, list_h, .{ .fb_scroll = .up }, .{ .fb_scroll = .down });
    if (with_name) {
        _ = put(box, 2, box.height -| 6, "File name", dim);
        try field(app, box, 13, box.height -| 6, box.width -| 15, &app.fb_name, 2, app.dlg_field == 2);
    }
    const count = app.fb_entries.items.len;
    const info = switch (app.fb_mode) {
        .project => app.fmt("{d} folders · Enter in · Backspace up · Tab field/list · F2 open as project", .{count}),
        .move_to => app.fmt("{d} folders · Enter in · Backspace up · F2 moves here", .{count}),
        else => app.fmt("{d} folders · {d} theme files · Tab next field · F2 {s}", .{ count, app.fb_files.items.len, ok_label }),
    };
    _ = put(box, 2, box.height -| 4, clipText(info, box.width -| 4), dim);
    try buttonRow(app, box, box.height -| 2, &.{
        .{ .label = ok_label, .action = .{ .dlg = .open_here }, .primary = true },
        .{ .label = "Cancel", .action = .close_overlay },
    });
}
