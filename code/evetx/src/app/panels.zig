//! @eve-module evetx.app.panels
//! @feature F-TLS-24
//! @decision D-173
//! @see code/evetx/src/app.zig:App
//! Panels, windows, layout, split bars and scroll bars.
const std = @import("std");
const vaxis = @import("vaxis");
const Key = vaxis.Key;
const ide = @import("ide");
const project = ide.project;
const text = ide.text;
const App = @import("../app.zig").App;
const types = @import("types.zig");
const Panel = types.Panel;
const Tab = types.Tab;
const Layout = types.Layout;
const Drag = types.Drag;

// ------------------------------------------------------------ panels and windows

/// The width of the Tree Panel: the chosen one (Window > Modify) or a quarter of the screen.
pub fn treeWidth(self: *const App) u16 {
    const w: u16 = if (self.tree_w == 0) std.math.clamp(self.cols / 4, 26, 40) else self.tree_w;
    return std.math.clamp(w, 14, self.cols -| 24);
}

/// The height of the Tools Panel: the chosen one or a third of the work area.
pub fn toolsHeight(self: *const App) u16 {
    const mh = self.rows -| 4;
    const h: u16 = if (self.tools_h == 0) @max(7, mh / 3) else self.tools_h;
    return std.math.clamp(h, 5, mh -| 6);
}

/// Is panel `p` on the screen? A maximized panel hides the others.
pub fn isShown(self: *const App, p: Panel) bool {
    return switch (p) {
        .tree => self.show_tree and self.maximized != .main,
        .main => self.show_main and self.maximized != .tools,
        .tools => self.show_tools and self.maximized != .main,
    };
}

/// Work out where each panel is for a screen of `W` x `H` cells, and keep the answer.
pub fn computeLayout(self: *App, W: u16, H: u16) Layout {
    const tools_on = self.isShown(.tools);
    self.cols = W;
    self.rows = H;
    const mh = H - 4;
    var l: Layout = .{};
    var rx: u16 = 0;
    if (self.isShown(.tree)) {
        const tw = self.treeWidth();
        l.tree = .{ .x = 0, .y = 1, .w = tw, .h = mh };
        rx = tw;
    }
    const rw = W - rx;
    if (self.isShown(.main) and tools_on) {
        const bb = self.toolsHeight();
        const eh = mh - 1 - bb;
        l.main = .{ .x = rx, .y = 1, .w = rw, .h = eh };
        l.debug = .{ .x = rx, .y = 1 + eh, .w = rw, .h = 1 };
        l.tools = .{ .x = rx, .y = 2 + eh, .w = rw, .h = bb };
    } else if (self.isShown(.main)) {
        l.main = .{ .x = rx, .y = 1, .w = rw, .h = mh };
    } else if (tools_on) {
        // the Main Panel is off: the toolbar has a border of its own (a row above and below), until the panel is back
        l.debug = .{ .x = rx, .y = 1, .w = rw, .h = 3 };
        l.tools = .{ .x = rx, .y = 4, .w = rw, .h = mh - 3 };
    }
    self.layout = l;
    return l;
}

/// The panel that has the keyboard.
pub fn activePanel(self: *const App) Panel {
    return switch (self.focus) {
        .tree => .tree,
        .editor => .main,
        .console, .breaks, .sql => .tools,
    };
}

/// Give the keyboard to panel `p`.
pub fn focusPanel(self: *App, p: Panel) void {
    self.focus = switch (p) {
        .tree => .tree,
        .main => .editor,
        .tools => if (self.bottom == .breaks) .breaks else if (self.bottom == .sql) .sql else .console,
    };
}

/// Hide panel `p`, or show it again (Window > Tree Panel, Main Panel, Tools Panel; the x buttons).
pub fn togglePanel(self: *App, p: Panel) void {
    const flag = switch (p) {
        .tree => &self.show_tree,
        .main => &self.show_main,
        .tools => &self.show_tools,
    };
    flag.* = !flag.*;
    if (flag.*) {
        self.maximized = null;
        self.focusPanel(p);
    } else {
        if (self.maximized == p) self.maximized = null;
        if (self.activePanel() == p) self.rotatePanel(1);
    }
}

/// Alt+T, Alt+M, Alt+O: the panel is on and has the keyboard.
pub fn activatePanel(self: *App, p: Panel) void {
    const flag = switch (p) {
        .tree => self.show_tree,
        .main => self.show_main,
        .tools => self.show_tools,
    };
    if (!flag) return self.togglePanel(p);
    if (self.maximized != null and self.maximized != p) self.maximized = null;
    self.focusPanel(p);
}

/// The + button: a panel fills the screen, or goes back to its place.
pub fn toggleMaximize(self: *App, p: Panel) void {
    self.maximized = if (self.maximized == p) null else p;
    self.focusPanel(p);
}

/// Shift+Tab and Alt+Right: the keyboard goes to the next panel that is on the screen (Tree, Main, Tools); Alt+Left goes back.
pub fn rotatePanel(self: *App, delta: isize) void {
    const here: isize = @backingInt(self.activePanel());
    for (1..4) |k| {
        const p: Panel = @fromBackingInt(@intCast(@mod(here + delta * @as(isize, @intCast(k)), 3)));
        if (self.isShown(p)) {
            self.focusPanel(p);
            return;
        }
    }
}

/// Alt+Tab: the next window of the Main Panel, or the next tab of the Tools Panel when that panel has the keyboard.
pub fn nextTab(self: *App, delta: isize) void {
    if (self.activePanel() == .tools) {
        const n: isize = 5;
        const cur: isize = @backingInt(self.bottom);
        self.bottom = @fromBackingInt(@intCast(@mod(cur + delta, n)));
        self.focusPanel(.tools);
        return;
    }
    const n: isize = @intCast(self.tabs.items.len);
    if (n == 0) return;
    const to: usize = @intCast(@mod(@as(isize, @intCast(self.active)) + delta, n));
    self.pickWindow(to);
}

/// Make window `t` (a tab of the Main Panel) the current one.
pub fn pickWindow(self: *App, t: usize) void {
    if (t >= self.tabs.items.len) return;
    self.active = t;
    if (!self.show_main) self.togglePanel(.main);
    self.focus = .editor;
}

/// Open a window that is not a file: the text is read only, the title is its name.
pub fn openVirtual(self: *App, title: []const u8, content: []const u8) !void {
    for (self.tabs.items, 0..) |t, i| {
        if (t.virtual and std.mem.eql(u8, t.path, title)) {
            self.pickWindow(i);
            return;
        }
    }
    var b = try text.Buffer.init(self.gpa);
    errdefer b.deinit();
    try b.load(content);
    b.dirty = false;
    const path = try self.gpa.dupe(u8, title);
    errdefer self.gpa.free(path);
    try self.tabs.insert(self.gpa, 0, .{ .path = path, .buf = b, .virtual = true });
    if (!self.show_main) self.togglePanel(.main);
    self.maximized = if (self.maximized == .tools) null else self.maximized;
    self.active = 0;
    self.tab_first = 0;
    self.focus = .editor;
}

/// Open a project folder: the tree shows its files and the windows of the old project close.
pub fn openProject(self: *App, path: []const u8) !void {
    if (path.len == 0) return;
    for (self.tabs.items) |t| {
        if (t.buf != null and t.buf.?.dirty) {
            self.setMessage("save or close the changed files first", .{});
            return;
        }
    }
    const name = App.projectName(self.gpa, self.io, path) catch |err| {
        self.setMessage("cannot open the folder '{s}': {s}", .{ path, @errorName(err) });
        return;
    };
    errdefer self.gpa.free(name);
    const root = try self.gpa.dupe(u8, path);
    errdefer self.gpa.free(root);

    // from here on nothing can fail with `try`: the new name and root belong to the app
    while (self.tabs.items.len > 0) self.closeTab(0);
    for (self.breakpoints.items) |b| self.gpa.free(b.path);
    self.breakpoints.clearRetainingCapacity();
    if (self.saved_open) |snap| self.gpa.free(snap);
    self.saved_open = null;
    self.tree.deinit();
    self.tree = project.Tree.init(self.gpa);
    self.gpa.free(self.project_name);
    self.gpa.free(self.root);
    if (self.work_dir) |c| self.gpa.free(c);
    self.work_dir = null;
    self.project_name = name;
    self.root = root;
    self.selected = 0;
    self.tree_top = 0;
    self.tree.scan(self.io, root, name) catch |err| {
        self.setMessage("cannot read the folder '{s}': {s}", .{ path, @errorName(err) });
        return;
    };
    self.show_tree = true;
    self.maximized = null;
    self.focus = .tree;
    self.setMessage("project: {s}", .{name});
    self.saveSession() catch {};
}

/// A press on a border between panels: start dragging it. (Layout modify starts by itself, see `onMouse`.)
pub fn grabSplit(self: *App, m: vaxis.Mouse) bool {
    const which = self.splitAt(m) orelse return false;
    // a locked layout has no border to grab: unlock it first (the lock of the toolbar, or Ctrl+L)
    if (!self.modify) return false;
    self.drag = which;
    return true;
}

/// Which border between panels is under the pointer?
pub fn splitAt(self: *const App, m: vaxis.Mouse) ?Drag {
    const l = self.layout;
    const touching = l.main.w > 0 or l.tools.w > 0;
    if (l.tree.w > 0 and touching and (m.col == l.tree.w - 1 or m.col == l.tree.w) and m.row >= 1 and m.row < self.rows -| 3) return .tree_split;
    if (l.tools.w > 0 and l.main.w > 0 and m.col >= l.tools.x and m.row == l.tools.y) return .tools_split;
    // the toolbar between the two panels: its free space and its handle are part of the same border
    if (l.debug.w > 0 and l.tools.w > 0 and l.main.w > 0 and m.row == l.debug.y and m.col >= l.debug.x and m.col < l.debug.x + l.debug.w) {
        for (self.hits.items) |h| {
            if (h.rect.contains(m.col, m.row)) return null;
        }
        return .tools_split;
    }
    return null;
}

/// The first item shown when the pointer is `rel` cells from the start of a track of `span` cells.
pub fn thumbToTop(rel: usize, span: usize, total: usize, visible: usize) usize {
    if (total <= visible or span == 0) return 0;
    const th = @max(1, span * visible / total);
    if (span <= th) return 0;
    const at = @min(rel -| th / 2, span - th);
    return at * (total - visible) / (span - th);
}

/// A press on a scroll bar of the editor: start dragging its thumb.
pub fn grabBar(self: *App, m: vaxis.Mouse) bool {
    if (self.vbar_rect.contains(m.col, m.row)) {
        self.drag = .vbar;
    } else if (self.hbar_rect.contains(m.col, m.row)) {
        self.drag = .hbar;
    } else if (self.tblv_rect.contains(m.col, m.row)) {
        self.drag = .tbl_v;
    } else if (self.tblh_rect.contains(m.col, m.row)) {
        self.drag = .tbl_h;
    } else if (self.pbar_rect.contains(m.col, m.row)) {
        self.drag = .panel_v;
    } else if (self.tvbar_rect.contains(m.col, m.row)) {
        self.drag = .tree_v;
    } else if (self.thbar_rect.contains(m.col, m.row)) {
        self.drag = .tree_h;
    } else return false;
    self.follow = false;
    self.scrollTo(m);
    return true;
}

/// Scroll the editor to the place of the pointer on the bar that is being dragged.
pub fn scrollTo(self: *App, m: vaxis.Mouse) void {
    if (self.drag == .tbl_v or self.drag == .tbl_h) {
        const t = self.activeTab() orelse return;
        const tv = t.table orelse return;
        if (self.drag == .tbl_v) {
            const r = self.tblv_rect;
            if (r.h < 2) return;
            const rel: usize = @intCast(@min(@max(@as(i32, m.row) - r.y, 0), r.h - 1));
            tv.top = App.thumbToTop(rel, r.h, tv.t.records, self.tbl_rows);
        } else {
            const r = self.tblh_rect;
            if (r.w < 2) return;
            const rel: usize = @intCast(@min(@max(@as(i32, m.col) - r.x, 0), r.w - 1));
            tv.left = App.thumbToTop(rel, r.w, tv.t.fields.len, self.tbl_cols);
        }
        return;
    }
    if (self.drag == .panel_v) {
        const r = self.pbar_rect;
        if (r.h < 2 or self.pbar_total <= self.pbar_visible) return;
        const rel: usize = @intCast(@min(@max(@as(i32, m.row) - r.y, 0), r.h - 1));
        const at = App.thumbToTop(rel, r.h, self.pbar_total, self.pbar_visible);
        switch (self.pbar_kind) {
            // a log counts its scroll in lines from the end
            .log => self.shownLog().scroll = self.pbar_total - self.pbar_visible -| at,
            .folder => {
                const t = self.activeTab() orelse return;
                const fv = t.folder orelse return;
                fv.top = at;
            },
            .breaks => self.break_top = at,
            .fbox => {
                self.fb_top = at;
                self.fb_sel = @min(@max(self.fb_sel, at), at + self.pbar_visible -| 1);
            },
            .none => {},
        }
        return;
    }
    if (self.drag == .tree_v) {
        self.tree_follow = false;
        const r = self.tvbar_rect;
        const total = self.visible.items.len;
        if (r.h < 2 or total <= self.tree_rect.h) return;
        const rel: usize = @intCast(@min(@max(@as(i32, m.row) - r.y, 0), r.h - 1));
        self.tree_top = App.thumbToTop(rel, r.h, total, self.tree_rect.h);
        return;
    }
    if (self.drag == .tree_h) {
        self.tree_follow = false;
        const r = self.thbar_rect;
        if (r.w < 2 or self.tree_content <= self.tree_rect.w) return;
        const rel: usize = @intCast(@min(@max(@as(i32, m.col) - r.x, 0), r.w - 1));
        self.tree_left = App.thumbToTop(rel, r.w, self.tree_content, self.tree_rect.w);
        return;
    }
    const b = self.activeBuffer() orelse return;
    if (self.drag == .vbar) {
        const r = self.vbar_rect;
        const total = b.lineCount() + 3;
        if (r.h < 2 or total <= r.h) return;
        const rel: usize = @intCast(@min(@max(@as(i32, m.row) - r.y, 0), r.h - 1));
        b.top = App.thumbToTop(rel, r.h, total, r.h + 3);
    } else if (self.drag == .hbar) {
        const r = self.hbar_rect;
        if (r.w < 2 or self.hbar_content <= r.w) return;
        const rel: usize = @intCast(@min(@max(@as(i32, m.col) - r.x, 0), r.w - 1));
        b.left = App.thumbToTop(rel, r.w, self.hbar_content, r.w + 2);
    }
}

/// The line and the piece of it that are drawn at row `rel` of the editor (null below the last line).
pub fn rowToLine(self: *const App, b: *const text.Buffer, rel: usize) ?struct { line: usize, seg: usize } {
    if (!self.wrap) return if (b.top + rel < b.lineCount()) .{ .line = b.top + rel, .seg = 0 } else null;
    var r = rel;
    var ln = b.top;
    while (ln < b.lineCount()) : (ln += 1) {
        const n = text.Buffer.segRows(b.lineAt(ln), self.editor_rect.w);
        if (r < n) return .{ .line = ln, .seg = r };
        r -= n;
    }
    return null;
}

/// The line drawn at row `rel` of the editor, if any.
pub fn lineAtRow(self: *const App, b: *const text.Buffer, rel: usize) ?usize {
    const at = self.rowToLine(b, rel) orelse return null;
    return at.line;
}

/// The place in the text under the mouse pointer.
pub fn editorPos(self: *App, b: *text.Buffer, m: vaxis.Mouse) text.Pos {
    const r = self.editor_rect;
    const rel: i32 = @as(i32, m.row) - r.y;
    const last = b.lineCount() - 1;
    const dcol: usize = @intCast(@max(@as(i32, m.col) - r.x, 0));
    if (rel < 0) {
        b.top -|= 1;
        return .{ .row = b.top, .col = text.Buffer.byteAtDisplay(b.lineAt(b.top), dcol + b.left) };
    }
    if (rel >= r.h) {
        if (b.top < last) b.top += 1;
        const row = @min(b.top + r.h -| 1, last);
        return .{ .row = row, .col = text.Buffer.byteAtDisplay(b.lineAt(row), dcol + b.left) };
    }
    const at = self.rowToLine(b, @intCast(rel)) orelse return .{ .row = last, .col = b.lineAt(last).len };
    const base: usize = if (self.wrap) at.seg * r.w else b.left;
    return .{ .row = at.line, .col = text.Buffer.byteAtDisplay(b.lineAt(at.line), base + dcol) };
}

/// The pointer moves with the button down in the text: the cursor follows, the anchor is where the click was.
pub fn selectTo(self: *App, m: vaxis.Mouse) void {
    const b = self.activeBuffer() orelse return;
    self.follow = false;
    const pos = self.editorPos(b, m);
    if (b.anchor == null) b.anchor = self.sel_from;
    b.row = pos.row;
    b.col = pos.col;
}

/// The mouse moves with a button down.
pub fn dragTo(self: *App, m: vaxis.Mouse) void {
    switch (self.drag) {
        .none => {},
        .tree_split => self.tree_w = @intCast(@max(@as(i32, m.col) + 1, 0)),
        .tools_split => self.tools_h = @intCast(@max(@as(i32, self.rows) - 3 - m.row, 0)),
        .vbar, .hbar, .tree_v, .tree_h, .tbl_v, .tbl_h, .panel_v => self.scrollTo(m),
        .select => self.selectTo(m),
    }
}

/// Layout modify: the borders between the panels can be dragged, and the arrow keys change the sizes.
pub fn startModify(self: *App, by_mouse: bool) void {
    self.modify = true;
    self.mouse_modify = by_mouse;
    self.freeze_at = null;
}

/// Layout freeze: the sizes stay as they are.
pub fn freezeLayout(self: *App) void {
    self.modify = false;
    self.mouse_modify = false;
    self.freeze_at = null;
    self.drag = .none;
    self.setMessage("layout frozen", .{});
}

/// Does the main loop have to wake up by itself? (A command waits, or the layout is about to freeze.)
pub fn needsTick(self: *const App) bool {
    return self.pending_at != null or self.freeze_at != null or self.job != null or self.linkBusy() or (self.options.autosave_s > 0 and self.anyDirtyFile());
}

/// While Window > Modify is on: the arrows change the sizes, Esc and Enter freeze them. True when the key was used.
pub fn modifyKey(self: *App, key: Key) !bool {
    // the keyboard takes over: a countdown that the mouse started is cancelled
    self.freeze_at = null;
    if (key.matches(Key.escape, .{}) or key.matches(Key.enter, .{}) or key.matches('z', .{ .ctrl = true })) {
        self.freezeLayout();
    } else if (key.matches(Key.left, .{})) {
        self.tree_w = self.treeWidth() -| 2;
    } else if (key.matches(Key.right, .{})) {
        self.tree_w = self.treeWidth() + 2;
    } else if (key.matches(Key.up, .{})) {
        self.tools_h = self.toolsHeight() + 1;
    } else if (key.matches(Key.down, .{})) {
        self.tools_h = self.toolsHeight() -| 1;
    } else return false;
    return true;
}
