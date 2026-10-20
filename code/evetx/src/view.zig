//! Drawing: reads the state of `App` and draws the screen of design/design.svg. It also records
//! the clickable places (`app.hits`) and the areas that scroll, for the mouse.
pub const std = @import("std");
pub const vaxis = @import("vaxis");
pub const Window = vaxis.Window;
pub const TextInput = vaxis.widgets.TextInput;

pub const app_mod = @import("app.zig");
pub const options_mod = @import("options.zig");
pub const App = app_mod.App;
pub const Action = app_mod.Action;
pub const Rect = app_mod.Rect;
pub const theme = @import("theme.zig");
pub const ide = @import("ide");
pub const grid = ide.grid;
pub const sqlstruct = ide.sqlstruct;
pub const text = ide.text;
pub const scan = ide.scan;
pub const keywords = ide.keywords;

pub const Style = theme.Style;
const dialogs_m = @import("view/dialogs.zig");
const find_dialogs_m = @import("view/find_dialogs.zig");
const main_panel_m = @import("view/main_panel.zig");
const menu_m = @import("view/menu.zig");
const settings_m = @import("view/settings.zig");
const sidebar_m = @import("view/sidebar.zig");
const tools_m = @import("view/tools.zig");
const widgets_m = @import("view/widgets.zig");
const sub = widgets_m.sub;
const boxed = widgets_m.boxed;
const fillWith = widgets_m.fillWith;
const put = widgets_m.put;
const addHit = widgets_m.addHit;
const button = widgets_m.button;
const sidebar = sidebar_m.sidebar;
const mainPanel = main_panel_m.mainPanel;
const tabStrip = main_panel_m.tabStrip;
const debugBar = tools_m.debugBar;
const toolsPanel = tools_m.toolsPanel;
const statusBar = tools_m.statusBar;
const dialog = dialogs_m.dialog;
const buttonRow = dialogs_m.buttonRow;
const ok_btn = dialogs_m.ok_btn;
const filterBox = dialogs_m.filterBox;
const tabMenuBox = dialogs_m.tabMenuBox;
const propertiesBox = dialogs_m.propertiesBox;
const confirmBox = dialogs_m.confirmBox;
const newBox = dialogs_m.newBox;
const wizardBox = dialogs_m.wizardBox;
const appendNBox = dialogs_m.appendNBox;
const sqStructureBox = dialogs_m.sqStructureBox;
const menuDrop = menu_m.menuDrop;
const settings = settings_m.settings;
const about = find_dialogs_m.about;
const gotoBox = find_dialogs_m.gotoBox;
const findTextBox = find_dialogs_m.findTextBox;
const findFileBox = find_dialogs_m.findFileBox;
const replaceBox = find_dialogs_m.replaceBox;
const saveAsBox = find_dialogs_m.saveAsBox;
const projectBox = find_dialogs_m.projectBox;
const folderBox = find_dialogs_m.folderBox;

// ------------------------------------------------------------------ the whole screen

pub fn draw(app: *App, win: Window) !void {
    app.beginFrame();
    app.hits.clearRetainingCapacity();
    app.pbar_rect = .{};
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
    if (l.debug.w > 0) {
        if (l.debug.h >= 3) {
            const live = app.overlay == .none and app.activePanel() == .tools;
            const frame = boxed(win, l.debug.x, l.debug.y, l.debug.w, l.debug.h, if (app.modify) theme.amber else if (live) theme.accent() else theme.line);
            try debugBar(app, frame, 0, 0, frame.width);
        } else try debugBar(app, win, l.debug.x, l.debug.y, l.debug.w);
    }
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

/// Draw the dialog `which`.
pub fn overlayBox(app: *App, win: Window, which: app_mod.Overlay) !void {
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
        .sq_structure => try sqStructureBox(app, win),
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
        .filter => try filterBox(app, win),
    }
}

/// The pop-up of a failed operation: its title, the message, and OK, which closes it (and goes back to the dialog under it).
pub fn alertBox(app: *App, win: Window) !void {
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

/// Paint the border between panels that is under the pointer.
pub fn drawSplitHint(app: *App, win: Window, l: app_mod.Layout) void {
    const which = (if (app.drag == .tree_split or app.drag == .tools_split) app.drag else null) orelse app.hover_split orelse return;
    if (app.overlay != .none) return;
    // the colour of the border it covers: the panel colour, so the line keeps the look of the border in every theme
    const style = theme.on(theme.amber, theme.panel);
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

/// The column of menu `i` in the bar: the menus follow each other from the left, the last one
/// (HELP) is at the right side.
pub fn menuX(W: u16, i: usize) u16 {
    const menus = app_mod.menus;
    if (i == menus.len - 1) return W -| @as(u16, @intCast(menus[i].label.len + 3));
    var x: u16 = 1;
    for (menus[0..i]) |m| x += @intCast(m.label.len + 2);
    return x;
}

/// The classic menu bar: upper case names, the first letter is the Alt key. The letter has its own
/// color; when the user presses Alt, or while a menu is open, it is underlined too.
pub fn menuBar(app: *App, win: Window) !void {
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

/// `s` cut to at most `max` bytes, at the start of a character.
pub fn clipText(s: []const u8, max: usize) []const u8 {
    if (s.len <= max) return s;
    var n = max;
    while (n > 0 and (s[n] & 0xC0) == 0x80) n -= 1;
    return s[0..n];
}

/// Draw the border of a panel and return its inside.
pub fn panelBox(app: *App, win: Window, r: Rect, p: app_mod.Panel) !Window {
    const live = app.overlay == .none and app.activePanel() == p;
    const color = if (app.modify) theme.amber else if (live) theme.accent() else theme.line;
    try addHit(app, win, r.x, r.y, r.w, r.h, .{ .panel_focus = p });
    return boxed(win, r.x, r.y, r.w, r.h, color);
}

/// The + (maximize) and × (hide) buttons at the right of the title bar of a panel.
pub fn titleButtons(app: *App, box: Window, p: app_mod.Panel) !void {
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
