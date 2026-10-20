//! @eve-module ide.text
//! @decision D-193
//! The text of a file in the editor: lines, a cursor, and the find and replace operations.
const std = @import("std");
const Allocator = std.mem.Allocator;

/// A place in the text that Find found and the editor shows highlighted.
pub const Match = struct { row: usize, col: usize, len: usize };

/// What kind of change is about to be made (see `Buffer.checkpoint`).
pub const EditKind = enum { none, typing, erasing, other };

/// The text and the cursor at one moment, for undo and redo.
pub const Snapshot = struct { bytes: []u8, row: usize, col: usize };

/// The most snapshots that undo keeps.
const max_undo = 100;

/// A place in the text: a line and a byte offset in it.
pub const Pos = struct { row: usize, col: usize };
/// A selected span: `start` is before `end`; `end` is not included.
pub const Range = struct { start: Pos, end: Pos };

pub const Buffer = struct {
    gpa: Allocator,
    lines: std.ArrayList(std.ArrayList(u8)) = .empty,
    /// The cursor: a line and a byte offset in it (always at the start of a character).
    row: usize = 0,
    col: usize = 0,
    /// The first line shown, and the first column shown.
    top: usize = 0,
    left: usize = 0,
    dirty: bool = false,
    /// The file had Windows line ends; they are written again on save.
    crlf: bool = false,
    /// The file had tabs; they were replaced by spaces when it was read.
    tabs_replaced: bool = false,
    match: ?Match = null,
    /// Where the selection started; the cursor is its other end. Null when nothing is selected.
    anchor: ?Pos = null,
    undo_stack: std.ArrayList(Snapshot) = .empty,
    redo_stack: std.ArrayList(Snapshot) = .empty,
    last_edit: EditKind = .none,

    pub fn init(gpa: Allocator) !Buffer {
        var b: Buffer = .{ .gpa = gpa };
        try b.lines.append(gpa, .empty);
        return b;
    }

    pub fn deinit(self: *Buffer) void {
        for (self.lines.items) |*l| l.deinit(self.gpa);
        self.lines.deinit(self.gpa);
        self.clearStack(&self.undo_stack);
        self.undo_stack.deinit(self.gpa);
        self.clearStack(&self.redo_stack);
        self.redo_stack.deinit(self.gpa);
    }

    fn clearStack(self: *Buffer, stack: *std.ArrayList(Snapshot)) void {
        for (stack.items) |s| self.gpa.free(s.bytes);
        stack.clearRetainingCapacity();
    }

    fn snapshot(self: *const Buffer) !Snapshot {
        return .{ .bytes = try self.toBytes(self.gpa), .row = self.row, .col = self.col };
    }

    /// Call before a change of the text: takes a snapshot, unless this change continues a run of the
    /// same kind (typing, erasing).
    pub fn checkpoint(self: *Buffer, kind: EditKind) !void {
        if ((kind == .typing or kind == .erasing) and self.last_edit == kind) return;
        self.last_edit = kind;
        self.clearStack(&self.redo_stack);
        const snap = try self.snapshot();
        errdefer self.gpa.free(snap.bytes);
        try self.undo_stack.append(self.gpa, snap);
        if (self.undo_stack.items.len > max_undo) self.gpa.free(self.undo_stack.orderedRemove(0).bytes);
    }

    fn travel(self: *Buffer, from: *std.ArrayList(Snapshot), to: *std.ArrayList(Snapshot)) !bool {
        if (from.items.len == 0) return false;
        const now = try self.snapshot();
        errdefer self.gpa.free(now.bytes);
        try to.append(self.gpa, now);
        const snap = from.pop().?;
        defer self.gpa.free(snap.bytes);
        const crlf = self.crlf;
        const top = self.top;
        const left = self.left;
        try self.load(snap.bytes);
        self.crlf = crlf;
        self.top = top;
        self.left = left;
        self.row = @min(snap.row, self.lines.items.len - 1);
        self.col = @min(snap.col, self.lines.items[self.row].items.len);
        self.dirty = true;
        self.anchor = null;
        self.last_edit = .none;
        return true;
    }

    /// Undo the last change. False when there is nothing to undo.
    pub fn undo(self: *Buffer) !bool {
        return self.travel(&self.undo_stack, &self.redo_stack);
    }

    /// Redo what was undone. False when there is nothing to redo.
    pub fn redo(self: *Buffer) !bool {
        return self.travel(&self.redo_stack, &self.undo_stack);
    }

    /// Replace the content by `bytes` (a whole file).
    pub fn load(self: *Buffer, bytes: []const u8) !void {
        for (self.lines.items) |*l| l.deinit(self.gpa);
        self.lines.clearRetainingCapacity();
        self.crlf = std.mem.indexOf(u8, bytes, "\r\n") != null;
        var rest = bytes;
        while (true) {
            const nl = std.mem.indexOfScalar(u8, rest, '\n');
            var chunk = if (nl) |i| rest[0..i] else rest;
            if (chunk.len > 0 and chunk[chunk.len - 1] == '\r') chunk = chunk[0 .. chunk.len - 1];
            var line: std.ArrayList(u8) = .empty;
            errdefer line.deinit(self.gpa);
            // tabs stay tabs: they are drawn up to the next tab stop and written back as they are
            try line.appendSlice(self.gpa, chunk);
            try self.lines.append(self.gpa, line);
            if (nl) |i| rest = rest[i + 1 ..] else break;
        }
        // A file that ends with a line end has an empty last line: keep it, so the end is kept on save.
        self.row = 0;
        self.col = 0;
        self.top = 0;
        self.left = 0;
        self.dirty = false;
        self.match = null;
    }

    /// The whole text as bytes, with the line ends of the file. The caller owns the result.
    pub fn toBytes(self: *const Buffer, gpa: Allocator) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(gpa);
        for (self.lines.items, 0..) |l, i| {
            if (i > 0) try out.appendSlice(gpa, if (self.crlf) "\r\n" else "\n");
            try out.appendSlice(gpa, l.items);
        }
        return out.toOwnedSlice(gpa);
    }

    pub fn lineAt(self: *const Buffer, row: usize) []const u8 {
        return self.lines.items[row].items;
    }

    pub fn lineCount(self: *const Buffer) usize {
        return self.lines.items.len;
    }

    fn prevStart(line: []const u8, col: usize) usize {
        var c = col;
        if (c == 0) return 0;
        c -= 1;
        while (c > 0 and (line[c] & 0xC0) == 0x80) c -= 1;
        return c;
    }

    fn nextEnd(line: []const u8, col: usize) usize {
        if (col >= line.len) return line.len;
        const n = std.unicode.utf8ByteSequenceLength(line[col]) catch 1;
        return @min(line.len, col + n);
    }

    /// The display column of the cursor: one cell for every character before it.
    pub fn displayCol(self: *const Buffer) usize {
        return displayWidth(self.lineAt(self.row)[0..self.col]);
    }

    /// The width of a tab stop, in cells.
    pub const tab_width: usize = 4;

    /// The number of cells that the start of a line `s` takes (a tab goes to the next tab stop).
    pub fn displayWidth(s: []const u8) usize {
        var n: usize = 0;
        for (s) |c| {
            if (c == '\t') {
                n += tab_width - n % tab_width;
            } else if ((c & 0xC0) != 0x80) n += 1;
        }
        return n;
    }

    /// The byte offset of display column `dc` in `line` (the end of the line when it is shorter). A
    /// column inside a tab gives the place of the tab.
    pub fn byteAtDisplay(line: []const u8, dc: usize) usize {
        var n: usize = 0;
        var i: usize = 0;
        while (i < line.len) {
            const w: usize = if (line[i] == '\t') tab_width - n % tab_width else 1;
            if (dc < n + w) return i;
            i = nextEnd(line, i);
            n += w;
        }
        return line.len;
    }

    /// Insert text that has no line end at the cursor.
    pub fn insert(self: *Buffer, s: []const u8) !void {
        if (s.len == 0) return;
        try self.lines.items[self.row].insertSlice(self.gpa, self.col, s);
        self.col += s.len;
        self.dirty = true;
        self.match = null;
    }

    /// The selected span, or null when nothing is selected.
    pub fn selection(self: *const Buffer) ?Range {
        const a = self.anchor orelse return null;
        if (a.row >= self.lines.items.len or a.col > self.lines.items[a.row].items.len) return null;
        if (a.row == self.row and a.col == self.col) return null;
        const a_first = a.row < self.row or (a.row == self.row and a.col < self.col);
        const c: Pos = .{ .row = self.row, .col = self.col };
        return if (a_first) Range{ .start = a, .end = c } else Range{ .start = c, .end = a };
    }

    /// Select the whole text: the cursor goes to the end.
    pub fn selectAll(self: *Buffer) void {
        self.anchor = .{ .row = 0, .col = 0 };
        self.row = self.lines.items.len - 1;
        self.col = self.lineAt(self.row).len;
    }

    /// A copy of the selected text, lines joined with `\n`; the caller frees it. Null when nothing is selected.
    pub fn selectedText(self: *const Buffer, gpa: Allocator) !?[]u8 {
        const sel = self.selection() orelse return null;
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(gpa);
        var r = sel.start.row;
        while (r <= sel.end.row) : (r += 1) {
            const line = self.lineAt(r);
            const from = if (r == sel.start.row) sel.start.col else 0;
            const to = if (r == sel.end.row) sel.end.col else line.len;
            try out.appendSlice(gpa, line[from..to]);
            if (r < sel.end.row) try out.append(gpa, '\n');
        }
        return try out.toOwnedSlice(gpa);
    }

    /// Delete the selected text and put the cursor where it was. False when nothing was selected.
    pub fn deleteSelection(self: *Buffer) !bool {
        const sel = self.selection() orelse {
            self.anchor = null;
            return false;
        };
        if (sel.start.row == sel.end.row) {
            self.lines.items[sel.start.row].replaceRangeAssumeCapacity(sel.start.col, sel.end.col - sel.start.col, &.{});
        } else {
            const first = &self.lines.items[sel.start.row];
            const tail = self.lines.items[sel.end.row].items[sel.end.col..];
            first.shrinkRetainingCapacity(sel.start.col);
            try first.appendSlice(self.gpa, tail);
            var n = sel.end.row - sel.start.row;
            while (n > 0) : (n -= 1) {
                var gone = self.lines.orderedRemove(sel.start.row + 1);
                gone.deinit(self.gpa);
            }
        }
        self.row = sel.start.row;
        self.col = sel.start.col;
        self.anchor = null;
        self.dirty = true;
        self.match = null;
        return true;
    }

    /// Insert a text that may have line ends (a paste) at the cursor, replacing the selection.
    pub fn insertText(self: *Buffer, s: []const u8) !void {
        _ = try self.deleteSelection();
        var lines = std.mem.splitScalar(u8, s, '\n');
        var first = true;
        while (lines.next()) |raw| {
            const piece = std.mem.trimEnd(u8, raw, "\r");
            if (!first) try self.splitLine();
            first = false;
            var parts = std.mem.splitScalar(u8, piece, '\t');
            var first_part = true;
            while (parts.next()) |part| {
                if (!first_part) try self.insert("  ");
                first_part = false;
                try self.insert(part);
            }
        }
    }

    /// Break the line at the cursor, without an indent.
    fn splitLine(self: *Buffer) !void {
        const cur = &self.lines.items[self.row];
        var tail: std.ArrayList(u8) = .empty;
        errdefer tail.deinit(self.gpa);
        try tail.appendSlice(self.gpa, cur.items[self.col..]);
        cur.shrinkRetainingCapacity(self.col);
        try self.lines.insert(self.gpa, self.row + 1, tail);
        self.row += 1;
        self.col = 0;
        self.dirty = true;
        self.match = null;
    }

    pub fn newline(self: *Buffer) !void {
        const cur = &self.lines.items[self.row];
        var tail: std.ArrayList(u8) = .empty;
        errdefer tail.deinit(self.gpa);
        // The new line starts with the indent of this one: the habit of every editor for code.
        var indent: usize = 0;
        while (indent < cur.items.len and cur.items[indent] == ' ') indent += 1;
        indent = @min(indent, self.col);
        try tail.appendNTimes(self.gpa, ' ', indent);
        try tail.appendSlice(self.gpa, cur.items[self.col..]);
        cur.shrinkRetainingCapacity(self.col);
        try self.lines.insert(self.gpa, self.row + 1, tail);
        self.row += 1;
        self.col = indent;
        self.dirty = true;
        self.match = null;
    }

    pub fn backspace(self: *Buffer) !void {
        if (self.col > 0) {
            const line = &self.lines.items[self.row];
            const start = prevStart(line.items, self.col);
            line.replaceRangeAssumeCapacity(start, self.col - start, &.{});
            self.col = start;
        } else if (self.row > 0) {
            var cur = self.lines.orderedRemove(self.row);
            defer cur.deinit(self.gpa);
            self.row -= 1;
            self.col = self.lines.items[self.row].items.len;
            try self.lines.items[self.row].appendSlice(self.gpa, cur.items);
        } else return;
        self.dirty = true;
        self.match = null;
    }

    pub fn delete(self: *Buffer) !void {
        const line = &self.lines.items[self.row];
        if (self.col < line.items.len) {
            const end = nextEnd(line.items, self.col);
            line.replaceRangeAssumeCapacity(self.col, end - self.col, &.{});
        } else if (self.row + 1 < self.lines.items.len) {
            var nxt = self.lines.orderedRemove(self.row + 1);
            defer nxt.deinit(self.gpa);
            try line.appendSlice(self.gpa, nxt.items);
        } else return;
        self.dirty = true;
        self.match = null;
    }

    /// How many rows the line takes when the text is wrapped at `cols` cells.
    pub fn segRows(line: []const u8, cols: usize) usize {
        const w = displayWidth(line);
        if (w == 0 or cols == 0) return 1;
        return (w + cols - 1) / cols;
    }

    const CharClass = enum { space, word, other };

    fn classAt(line: []const u8, i: usize) CharClass {
        const c = line[i];
        if (c == ' ' or c == '\t') return .space;
        if (std.ascii.isAlphanumeric(c) or c == '_' or c >= 0x80) return .word;
        return .other;
    }

    /// Ctrl+Left: to the start of the word on the left (the end of the previous line at column 0).
    pub fn wordLeft(self: *Buffer) void {
        if (self.col == 0) {
            if (self.row > 0) {
                self.row -= 1;
                self.col = self.lineAt(self.row).len;
            }
            return;
        }
        const line = self.lineAt(self.row);
        var c = self.col;
        while (c > 0 and classAt(line, prevStart(line, c)) == .space) c = prevStart(line, c);
        if (c > 0) {
            const cls = classAt(line, prevStart(line, c));
            while (c > 0 and classAt(line, prevStart(line, c)) == cls) c = prevStart(line, c);
        }
        self.col = c;
    }

    /// Ctrl+Right: to the start of the next word (the start of the next line at the end of a line).
    pub fn wordRight(self: *Buffer) void {
        const line = self.lineAt(self.row);
        if (self.col >= line.len) {
            if (self.row + 1 < self.lines.items.len) {
                self.row += 1;
                self.col = 0;
            }
            return;
        }
        var c = self.col;
        const cls = classAt(line, c);
        if (cls != .space) {
            while (c < line.len and classAt(line, c) == cls) c = nextEnd(line, c);
        }
        while (c < line.len and classAt(line, c) == .space) c = nextEnd(line, c);
        self.col = c;
    }

    pub fn moveLeft(self: *Buffer) void {
        if (self.col > 0) {
            self.col = prevStart(self.lineAt(self.row), self.col);
        } else if (self.row > 0) {
            self.row -= 1;
            self.col = self.lineAt(self.row).len;
        }
    }

    pub fn moveRight(self: *Buffer) void {
        const line = self.lineAt(self.row);
        if (self.col < line.len) {
            self.col = nextEnd(line, self.col);
        } else if (self.row + 1 < self.lines.items.len) {
            self.row += 1;
            self.col = 0;
        }
    }

    /// Move `n` lines up or down, keeping the display column as well as the line allows.
    pub fn moveRows(self: *Buffer, delta: isize) void {
        const dc = self.displayCol();
        const last: isize = @intCast(self.lines.items.len - 1);
        const target: isize = std.math.clamp(@as(isize, @intCast(self.row)) + delta, 0, last);
        self.row = @intCast(target);
        self.col = byteAtDisplay(self.lineAt(self.row), dc);
    }

    pub fn home(self: *Buffer) void {
        // Home goes to the first non-blank character, and to column 0 when it is already there.
        const line = self.lineAt(self.row);
        var first: usize = 0;
        while (first < line.len and line[first] == ' ') first += 1;
        self.col = if (self.col == first) 0 else first;
    }

    pub fn toEnd(self: *Buffer) void {
        self.col = self.lineAt(self.row).len;
    }

    /// Put the cursor on a line (1 based) and a column (1 based, 0 = unchanged); out of range goes to the last line.
    pub fn gotoLine(self: *Buffer, line1: usize, col1: usize) void {
        const r = if (line1 == 0) 0 else line1 - 1;
        self.row = @min(r, self.lines.items.len - 1);
        self.col = if (col1 == 0) 0 else byteAtDisplay(self.lineAt(self.row), col1 - 1);
    }

    /// Scroll so that the cursor is inside a window of `rows` lines and `cols` columns.
    pub fn follow(self: *Buffer, rows: usize, cols: usize) void {
        if (rows == 0 or cols == 0) return;
        if (self.row < self.top) self.top = self.row;
        if (self.row >= self.top + rows) self.top = self.row + 1 - rows;
        const dc = self.displayCol();
        if (dc < self.left) self.left = dc;
        if (dc >= self.left + cols) self.left = dc + 1 - cols;
    }

    /// Find `needle` from the cursor (after the current match), wrapping once; select it as the match.
    pub fn findNext(self: *Buffer, needle: []const u8) bool {
        if (needle.len == 0) return false;
        const n = self.lines.items.len;
        var start_col = if (self.match) |m| m.col + 1 else self.col;
        var k: usize = 0;
        while (k <= n) : (k += 1) {
            const r = (self.row + k) % n;
            const line = self.lineAt(r);
            const from = if (k == 0) @min(start_col, line.len) else 0;
            // On the last step we are back in the first line: only look before the start.
            if (std.mem.indexOfPos(u8, line, from, needle)) |c| {
                self.row = r;
                self.col = c;
                self.match = .{ .row = r, .col = c, .len = needle.len };
                return true;
            }
            start_col = 0;
        }
        return false;
    }

    /// Replace the current match by `with`, then go to the next one.
    pub fn replaceMatch(self: *Buffer, needle: []const u8, with: []const u8) !bool {
        const m = self.match orelse return self.findNext(needle);
        const line = &self.lines.items[m.row];
        line.replaceRangeAssumeCapacity(m.col, m.len, &.{});
        try line.insertSlice(self.gpa, m.col, with);
        self.row = m.row;
        self.col = m.col + with.len;
        self.match = null;
        self.dirty = true;
        return self.findNext(needle);
    }

    /// Replace every occurrence of `needle` in the text by `with`; returns how many.
    pub fn replaceAll(self: *Buffer, needle: []const u8, with: []const u8) !usize {
        if (needle.len == 0) return 0;
        var count: usize = 0;
        for (self.lines.items) |*line| {
            var from: usize = 0;
            while (std.mem.indexOfPos(u8, line.items, from, needle)) |c| {
                line.replaceRangeAssumeCapacity(c, needle.len, &.{});
                try line.insertSlice(self.gpa, c, with);
                from = c + with.len;
                count += 1;
            }
        }
        if (count > 0) {
            self.dirty = true;
            self.match = null;
        }
        return count;
    }
};
