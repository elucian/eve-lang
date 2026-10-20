//! @eve-module evetx.app.mouse
//! @feature F-TLS-24
//! @decision D-173
//! @see code/evetx/src/app.zig:App
//! The mouse: clicks, drags, scroll.
const vaxis = @import("vaxis");
const ide = @import("ide");
const text = ide.text;
const grid = ide.grid;
const App = @import("../app.zig").App;
const types = @import("types.zig");
const rownumW = types.rownumW;
const TableView = types.TableView;
const Layout = types.Layout;

// ------------------------------------------------------------ the mouse

pub fn onMouse(self: *App, m: vaxis.Mouse) !void {
    if (m.type == .motion) return self.hover(m);
    if (m.type == .release) {
        if (self.tdrag_src != null) try self.treeRelease();
        if (self.fdrag != null) try self.folderRelease();
        self.drag = .none;
        // three seconds after the release the layout freezes by itself
        if (self.modify and self.mouse_modify) self.freeze_at = self.nowMs() + 3000;
        return;
    }
    if (m.type == .drag) {
        if (self.tdrag_src != null or self.fdrag != null) {
            self.treeDragTo(m);
            return;
        }
        self.freeze_at = null;
        return self.dragTo(m);
    }
    self.alt_hint = false;
    self.freeze_at = null;
    if (m.button == .wheel_up or m.button == .wheel_down) {
        const up = m.button == .wheel_up;
        if (self.overlay == .open_folder) {
            // the list of the folder selector: the selection moves, the list follows
            const n = self.fbRowCount();
            if (n > 0) self.fb_sel = if (up) self.fb_sel -| 3 else @min(self.fb_sel + 3, n - 1);
            return;
        }
        self.follow = false;
        const lm = self.layout.main;
        if (lm.w > 0 and m.row == lm.y and m.col >= lm.x and m.col < lm.x + lm.w) {
            // the wheel over the tab row moves the row of tabs; the view keeps the active tab inside it
            if (up) self.tab_first -|= 1 else if (self.tab_more_right) self.tab_first += 1;
            return;
        }
        if (self.tree_rect.contains(m.col, m.row)) {
            self.tree_follow = false;
            self.tree_top = if (up) self.tree_top -| 3 else self.tree_top + 3;
        } else if (self.tbl_rect.contains(m.col, m.row)) {
            if (self.activeTab()) |t| {
                if (t.table) |tv| tv.top = if (up) tv.top -| 3 else @min(tv.top + 3, tv.t.records -| 1);
            }
        } else if (self.editor_rect.contains(m.col, m.row)) {
            if (self.activeTab()) |t| {
                if (t.folder) |fv| {
                    fv.top = if (up) fv.top -| 3 else @min(fv.top + 3, fv.items.items.len -| 1);
                    return;
                }
            }
            if (self.activeBuffer()) |b| b.top = if (up) b.top -| 3 else @min(b.top + 3, b.lineCount() - 1);
        } else if (self.console_rect.contains(m.col, m.row)) {
            const log = self.shownLog();
            log.scroll = if (up) log.scroll +| 3 else log.scroll -| 3;
        }
        return;
    }
    if (m.button == .right and self.overlay == .none) {
        // a right click on a tab opens its popup menu
        var k = self.hits.items.len;
        while (k > 0) {
            k -= 1;
            const h = self.hits.items[k];
            if (h.rect.contains(m.col, m.row)) {
                switch (h.action) {
                    .tab, .tab_close => |t| self.openTabMenu(t, m),
                    else => {},
                }
                return;
            }
        }
        return;
    }
    if (m.button == .middle) {
        // a middle click on a tab closes it
        var k = self.hits.items.len;
        while (k > 0) {
            k -= 1;
            const h = self.hits.items[k];
            if (h.rect.contains(m.col, m.row)) {
                switch (h.action) {
                    .tab, .tab_close => |t| self.closeTab(t),
                    else => {},
                }
                return;
            }
        }
        return;
    }
    if (m.button != .left) return;
    self.follow = true;
    if (self.overlay == .open_folder and self.pbar_kind == .fbox and self.pbar_rect.contains(m.col, m.row)) {
        self.drag = .panel_v;
        self.scrollTo(m);
        return;
    }
    if (self.overlay == .none) {
        if (self.grabSplit(m)) {
            // a press on a border starts Layout modify; a layout already in modify keeps how it was started
            if (!self.modify) self.startModify(true);
            return;
        }
        if (self.grabBar(m)) return;
        if (self.gutter_rect.contains(m.col, m.row)) {
            if (self.activeBuffer()) |b| {
                const rel: usize = @intCast(@as(i32, m.row) - self.gutter_rect.y);
                if (self.lineAtRow(b, rel)) |ln| try self.toggleBreakpointAt(ln + 1);
                return;
            }
        }
        if (self.editor_rect.contains(m.col, m.row)) {
            if (self.activeBuffer()) |b| {
                const before: text.Pos = .{ .row = b.row, .col = b.col };
                const pos = self.editorPos(b, m);
                b.row = pos.row;
                b.col = pos.col;
                // a click starts a selection; with Shift it extends the one that exists
                if (m.mods.shift) {
                    if (b.anchor == null) b.anchor = before;
                } else {
                    b.anchor = null;
                    self.sel_from = pos;
                }
                b.last_edit = .none;
                self.drag = .select;
                self.focus = .editor;
                return;
            }
        }
    }

    var i = self.hits.items.len;
    while (i > 0) {
        i -= 1;
        const h = self.hits.items[i];
        if (h.rect.contains(m.col, m.row)) {
            if (h.action == .tree_row) return self.treePress(h.action.tree_row, m);
            if (h.action == .folder_row) return self.folderPress(h.action.folder_row, m);
            // a click inside a panel gives it the keyboard and goes on to the part that was clicked (a cell, the console)
            if (h.action == .panel_focus) {
                try self.activate(h.action);
                break;
            }
            return self.activate(h.action);
        }
    }
    if (self.overlay != .none) return self.closeOverlay();
    if (self.tbl_rect.contains(m.col, m.row)) {
        if (self.activeTab()) |t| {
            if (t.table) |tv| {
                self.focus = .editor;
                self.clickTable(tv, m);
                return;
            }
        }
    }
    if (self.console_rect.contains(m.col, m.row) and self.bottom == .console) {
        self.focus = .console;
    } else if (self.console_rect.contains(m.col, m.row) and self.bottom == .sql) {
        self.focus = .sql;
    }
}

/// A click on the grid of a table: select the record and the field under the pointer; Ctrl+click selects the row; a double click edits.
pub fn clickTable(self: *App, tv: *TableView, m: vaxis.Mouse) void {
    const r = self.tbl_rect;
    const row = tv.top + @as(usize, @intCast(@max(@as(i32, m.row) - r.y, 0)));
    var x: i32 = @as(i32, r.x) + rownumW(tv.t.records);
    var c = tv.left;
    var found: ?usize = null;
    while (c < tv.t.fields.len) : (c += 1) {
        const w: i32 = @as(i32, if (c < self.tbl_widths.len) self.tbl_widths[c] else tv.t.fields[c].width) + 1;
        if (m.col >= x and m.col < x + w) {
            found = c;
            break;
        }
        x += w;
    }
    if (row >= tv.t.records) return;
    // a click on the cell being edited goes on editing; a click elsewhere ends the editing and keeps the value
    if (self.tbl_editing) {
        if (found != null and row == tv.row and found.? == tv.col) return;
        self.commitCell(tv) catch {};
    }
    tv.row = row;
    if (m.mods.ctrl) {
        if (tv.sel.contains(row)) _ = tv.sel.swapRemove(row) else tv.sel.put(self.gpa, row, {}) catch {};
        return;
    }
    const col = found orelse return;
    tv.col = col;
    // a second click on the same cell within 400 ms starts the editing
    const now = self.nowMs();
    const double = now - self.tbl_click_ms < 400 and self.tbl_click_row == row and self.tbl_click_col == col;
    self.tbl_click_ms = if (double) 0 else now;
    self.tbl_click_row = row;
    self.tbl_click_col = col;
    if (double) self.dataEdit();
}
