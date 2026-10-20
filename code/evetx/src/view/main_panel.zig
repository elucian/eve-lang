//! @eve-module evetx.view.main_panel
//! @feature F-TLS-24
//! @decision D-173
//! @see code/evetx/src/view.zig:draw
//! The main panel: tab strip, logo, editor area and folder list.
const std = @import("std");
const vaxis = @import("vaxis");
const Window = vaxis.Window;
const app_mod = @import("../app.zig");
const App = app_mod.App;
const theme = @import("../theme.zig");
const ide = @import("ide");
const text = ide.text;
const Style = theme.Style;
const editor_m = @import("editor.zig");
const find_dialogs_m = @import("find_dialogs.zig");
const sidebar_m = @import("sidebar.zig");
const table_area_m = @import("table_area.zig");
const tools_m = @import("tools.zig");
const view_m = @import("../view.zig");
const widgets_m = @import("widgets.zig");
const sub = widgets_m.sub;
const fillWith = widgets_m.fillWith;
const put = widgets_m.put;
const absRect = widgets_m.absRect;
const addHit = widgets_m.addHit;
const button = widgets_m.button;
const panelBox = view_m.panelBox;
const titleButtons = view_m.titleButtons;
const hasExt = sidebar_m.hasExt;
const folderArea = table_area_m.folderArea;
const tableArea = table_area_m.tableArea;
const editor = editor_m.editor;
const card = tools_m.card;
const repeat = find_dialogs_m.repeat;

/// The Main Panel: the windows as tabs and the editor.
pub fn mainPanel(app: *App, win: Window, l: app_mod.Layout) !void {
    const r = l.main;
    if (r.w == 0) return;
    const box = try panelBox(app, win, r, .main);
    fillWith(box, theme.deep);
    try tabStrip(app, box);
    try titleButtons(app, box, .main);
    _ = put(box, 0, 1, repeat("─", 400), theme.on(theme.line, theme.deep));
    try editorArea(app, sub(box, 0, 2, box.width, box.height -| 2));
}

/// The icon of a tab, the same as the one of the file in the tree.
pub fn tabIcon(t: app_mod.Tab) []const u8 {
    if (std.mem.startsWith(u8, t.path, "filter:")) return "▽";
    if (t.folder != null) return "📂";
    if (std.mem.indexOfScalar(u8, t.path, '#') != null) return "▦";
    if (hasExt(t.path, &.{ ".db", ".duckdb", ".sqlite", ".sqlite3", ".dbf" })) return "💾";
    if (hasExt(t.path, &.{".eve"})) return "📜";
    return "📄";
}

/// The text of a tab: its icon, a dot when it has unsaved changes, and its title (in the frame arena).
pub fn tabLabel(app: *App, t: app_mod.Tab) []const u8 {
    return app.fmt(" {s} {s} ", .{ if (tabChanged(t)) "●" else tabIcon(t), t.title() });
}

/// Does the window hold changes that are not saved?
pub fn tabChanged(t: app_mod.Tab) bool {
    return t.buf != null and t.buf.?.dirty;
}

pub const changed_red = theme.fromHex(0xff1f1f);

/// Do the tabs `first` to `last` fit in `room` cells?
pub fn tabsFit(app: *App, strip: Window, first: usize, last: usize, room: u16) bool {
    var used: usize = 0;
    for (app.tabs.items[first .. last + 1]) |t| used += strip.gwidth(tabLabel(app, t)) + 3;
    return used <= room;
}

/// The tab row of the Main Panel: `<` at the left, the tabs, and (in `titleButtons`) `>` at the right.
pub fn tabStrip(app: *App, box: Window) !void {
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
        if (tabChanged(t)) _ = put(strip, x + 1, 0, "●", theme.onBold(changed_red, if (i == app.active) theme.blue else theme.bar2));
        try addHit(app, strip, x, 0, w, 1, .{ .tab = i });
        _ = put(strip, x + w, 0, "× ", style);
        try addHit(app, strip, x + w, 0, 2, 1, .{ .tab_close = i });
        x += w + 3;
    }
    app.tab_more_right = i < n;
    // the wheel or a button moved the row: the active tab follows it, so it stays in view
    if (app.tab_seen == active and i > app.tab_first) {
        const shown_last = i - 1;
        if (active < app.tab_first) app.active = app.tab_first else if (active > shown_last) app.active = shown_last;
        app.tab_seen = app.active;
    }
    const can_left = app.tab_first > 0;
    _ = put(strip, 0, 0, " < ", if (can_left) theme.onBold(theme.bright, theme.bar2) else theme.on(theme.faint, theme.bar2));
    if (can_left) try addHit(app, strip, 0, 0, 3, 1, .{ .tab_shift = -1 });
}

pub const logo_rows = [_][]const u8{
    "██████ ██  ██ ██████        ██████ ██  ██",
    "██     ██  ██ ██              ██    ████ ",
    "█████  ██  ██ █████  █████    ██     ██  ",
    "██      ████  ██              ██    ████ ",
    "██████   ██   ██████          ██   ██  ██",
};

/// Print `s` in the middle of `row`.
pub fn center(win: Window, row: u16, s: []const u8, style: Style) void {
    _ = put(win, (win.width -| win.gwidth(s)) / 2, row, s, style);
}

/// The picture of the Main Panel when no window is open: the logo, and two lines under it. In a
/// small panel the logo is replaced by plain text.
pub fn logo(ed: Window) void {
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

pub fn editorArea(app: *App, ed: Window) !void {
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

/// `YYYY-MM-DD HH:MM` for a moment given in seconds since 1970 (UTC), or "" for 0.
pub fn dateText(app: *App, secs: i64) []const u8 {
    if (secs <= 0) return "";
    const es = std.time.epoch.EpochSeconds{ .secs = @intCast(secs) };
    const yd = es.getEpochDay().calculateYearDay();
    const mday = yd.calculateMonthDay();
    const ds = es.getDaySeconds();
    return app.fmt("{d}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}", .{ yd.year, @backingInt(mday.month), mday.day_index + 1, ds.getHoursIntoDay(), ds.getMinutesIntoHour() });
}
