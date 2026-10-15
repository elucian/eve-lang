//! The text of a file in the editor: lines, a cursor, and the find and replace operations.
const std = @import("std");
const Allocator = std.mem.Allocator;

// Zig tip: A struct of plain numbers needs no methods. `usize` is the unsigned integer as wide as
// a pointer: the right type for indices and lengths.
/// A place in the text that Find found and the editor shows highlighted.
pub const Match = struct { row: usize, col: usize, len: usize };

// Zig tip: Two small structs name a place in the text and a span between two places. The selection
// of the editor is a span from the anchor to the cursor, whichever comes first in the text.
/// A place in the text: a line and a byte offset in it.
pub const Pos = struct { row: usize, col: usize };
/// A selected span: `start` is before `end`; `end` is not included.
pub const Range = struct { start: Pos, end: Pos };

// Zig tip: a struct groups data and the functions that work on it. A function whose first
// parameter is `self: *Buffer` is called like a method: `buffer.insert(...)`. `*Buffer` means
// "a pointer to a Buffer": the function can change it. `self: Buffer` or `*const Buffer` can only read.
pub const Buffer = struct {
    gpa: Allocator,
    // Zig tip: `std.ArrayList(T)` is a growable array. Since Zig 0.15 it does not remember its
    // allocator: every call that may grow it takes one (`append(gpa, x)`), and `.empty` is its
    // empty value. A list of lists is how the lines are kept: one `ArrayList(u8)` per line.
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

    // Zig tip: `!Buffer` is an error union: the result is a `Buffer` or an error. `try x` unwraps the
    // value, or returns the error to the caller at once. Here the only error is running out of memory.
    pub fn init(gpa: Allocator) !Buffer {
        var b: Buffer = .{ .gpa = gpa };
        try b.lines.append(gpa, .empty);
        return b;
    }

    // Zig tip: `for (self.lines.items) |*l|` captures a pointer to each element (`*l`) instead of a
    // copy, so `l.deinit` can change and free the line in place.
    pub fn deinit(self: *Buffer) void {
        for (self.lines.items) |*l| l.deinit(self.gpa);
        self.lines.deinit(self.gpa);
    }

    // Zig tip: `errdefer` runs only if the function returns an error after that line: it frees `line`
    // when the append below fails, and is skipped when the line was handed to the list.
    // `std.mem.indexOf` returns an optional, null when nothing matched.
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

    // Zig tip: `toOwnedSlice` hands the memory of the list to the caller as one exact slice; the list
    // is empty afterwards. The caller must free the result with the same allocator.
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

    // Zig tip: A slice (`[]const u8`) is a pointer and a length. Returning the line as a slice copies
    // nothing: it points into the buffer and is valid until the buffer changes.
    pub fn lineAt(self: *const Buffer, row: usize) []const u8 {
        return self.lines.items[row].items;
    }

    // Zig tip: `self: *const Buffer` marks a method that only reads. Such a method can be called on a
    // `*Buffer` as well: Zig converts the pointer.
    pub fn lineCount(self: *const Buffer) usize {
        return self.lines.items.len;
    }

    // Zig tip: `std.unicode.utf8ByteSequenceLength` gives the length of a UTF-8 character from its
    // first byte. A byte that looks like `10xxxxxx` is a continuation byte, never the start of one,
    // so stepping back over those bytes lands on the start of the previous character.
    fn prevStart(line: []const u8, col: usize) usize {
        var c = col;
        if (c == 0) return 0;
        c -= 1;
        while (c > 0 and (line[c] & 0xC0) == 0x80) c -= 1;
        return c;
    }

    // Zig tip: `catch 1` gives a fallback value when the call on its left returns an error: here, a
    // byte that is not a valid UTF-8 start is treated as one character of one byte.
    fn nextEnd(line: []const u8, col: usize) usize {
        if (col >= line.len) return line.len;
        const n = std.unicode.utf8ByteSequenceLength(line[col]) catch 1;
        return @min(line.len, col + n);
    }

    // Zig tip: `s[0..n]` cuts a slice. In a safe build Zig checks that the range is inside the slice
    // and stops the program with a message if it is not.
    /// The display column of the cursor: one cell for every character before it.
    pub fn displayCol(self: *const Buffer) usize {
        return displayWidth(self.lineAt(self.row)[0..self.col]);
    }

    /// The width of a tab stop, in cells.
    pub const tab_width: usize = 4;

    // Zig tip: `tab_width - n % tab_width` is how far the next tab stop is from column `n`: `%` is the
    // remainder, so a tab at column 5 moves 3 cells to column 8. Every other character is one cell,
    // and the continuation bytes of a UTF-8 character (`10xxxxxx`) are not counted. The text must
    // start at the beginning of a line, because the tab stops are counted from there.
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

    // Zig tip: A `while` loop with an early `return` is the plain way to search. `nextEnd` is called
    // as a function of the file, without a `self`, because it is declared inside the struct but takes
    // no instance.
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

    // Zig tip: `insertSlice(gpa, index, items)` puts several elements into the list at an index. It
    // may have to grow the list, so it takes the allocator and can fail: that is why `insert` returns
    // `!void`.
    /// Insert text that has no line end at the cursor.
    pub fn insert(self: *Buffer, s: []const u8) !void {
        if (s.len == 0) return;
        try self.lines.items[self.row].insertSlice(self.gpa, self.col, s);
        self.col += s.len;
        self.dirty = true;
        self.match = null;
    }

    // Zig tip: The anchor could be left behind by an edit made somewhere else (a replace, for
    // example), so the function checks that it still points into the text before it is used:
    // `orelse return null` and the two `if`s turn a stale anchor into "no selection".
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

    // Zig tip: `?[]u8` is an optional slice: null means "nothing selected". The text is built in a
    // growable list of bytes and handed to the caller with `toOwnedSlice`, who frees it.
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

    // Zig tip: When the span covers several lines, the end of the last line is added to the first
    // line (a slice into the line that is about to be removed, so it is appended before the removal),
    // then the lines in between and the last one are taken out of the list one by one.
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

    // Zig tip: A text with line ends is inserted piece by piece: `std.mem.splitScalar` walks the
    // lines, a line end splits the current line at the cursor (no automatic indent, unlike Enter),
    // and tabs become two spaces as when a file is read. The selected text, if any, is replaced.
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

    // Zig tip: `&self.lines.items[self.row]` takes the address of an element. The pointer stays valid
    // only while the list does not grow, so the code finishes with `cur` before it calls `insert` on
    // the list.
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

    // Zig tip: `replaceRangeAssumeCapacity(start, len, &.{})` replaces a range by nothing, which
    // deletes it. "AssumeCapacity" means the call never allocates, which is true here because the list
    // only shrinks.
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

    // Zig tip: `orelse` and `else return` keep the main path flat: the function either does one of the
    // two cases or returns, and the code after the `if` is the shared ending.
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

    // Zig tip: `(w + cols - 1) / cols` is the integer division that rounds up: the number of rows
    // that a line of `w` cells needs when it is cut every `cols` cells. An empty line still takes
    // one row. The function has no `self`: it is a plain helper that lives in the struct.
    /// How many rows the line takes when the text is wrapped at `cols` cells.
    pub fn segRows(line: []const u8, cols: usize) usize {
        const w = displayWidth(line);
        if (w == 0 or cols == 0) return 1;
        return (w + cols - 1) / cols;
    }

    // Zig tip: An `enum` with three values names the kind of a character; a `switch` or an `==`
    // compares kinds. Letters, digits, `_` and every non ASCII byte are "word"; a run of the same
    // kind is skipped as one step, like in every code editor.
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

    // Zig tip: A function that returns `void` and cannot fail has no `!`, so the caller does not use
    // `try`. Plain cursor moves cannot run out of memory.
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

    // Zig tip: `@as(isize, @intCast(x))` converts an unsigned number to a signed one in two steps:
    // `@intCast` changes the width, `@as` names the type. `std.math.clamp(v, lo, hi)` keeps `v`
    // between the limits.
    /// Move `n` lines up or down, keeping the display column as well as the line allows.
    pub fn moveRows(self: *Buffer, delta: isize) void {
        const dc = self.displayCol();
        const last: isize = @intCast(self.lines.items.len - 1);
        const target: isize = std.math.clamp(@as(isize, @intCast(self.row)) + delta, 0, last);
        self.row = @intCast(target);
        self.col = byteAtDisplay(self.lineAt(self.row), dc);
    }

    // Zig tip: `if (a) x else y` is an expression, so it can be on the right of an assignment. Here
    // the Home key goes to the first letter, and to column 0 when the cursor is already there.
    pub fn home(self: *Buffer) void {
        // Home goes to the first non-blank character, and to column 0 when it is already there.
        const line = self.lineAt(self.row);
        var first: usize = 0;
        while (first < line.len and line[first] == ' ') first += 1;
        self.col = if (self.col == first) 0 else first;
    }

    // Zig tip: Zig does not allow a local name to hide a declaration of the same name in the file or
    // struct. This method is called `toEnd` because an `end` local in `delete` would otherwise be an
    // error.
    pub fn toEnd(self: *Buffer) void {
        self.col = self.lineAt(self.row).len;
    }

    // Zig tip: `@min(a, b)` is the smaller of two numbers. A line number of 0 or one beyond the end is
    // made valid here, so the callers do not have to check it.
    /// Put the cursor on a line (1 based) and a column (1 based, 0 = unchanged); out of range goes to the last line.
    pub fn gotoLine(self: *Buffer, line1: usize, col1: usize) void {
        const r = if (line1 == 0) 0 else line1 - 1;
        self.row = @min(r, self.lines.items.len - 1);
        self.col = if (col1 == 0) 0 else byteAtDisplay(self.lineAt(self.row), col1 - 1);
    }

    // Zig tip: An early `return` for an input that cannot be used (a window of size 0) keeps the rest
    // of the function free of that case.
    /// Scroll so that the cursor is inside a window of `rows` lines and `cols` columns.
    pub fn follow(self: *Buffer, rows: usize, cols: usize) void {
        if (rows == 0 or cols == 0) return;
        if (self.row < self.top) self.top = self.row;
        if (self.row >= self.top + rows) self.top = self.row + 1 - rows;
        const dc = self.displayCol();
        if (dc < self.left) self.left = dc;
        if (dc >= self.left + cols) self.left = dc + 1 - cols;
    }

    // Zig tip: `%` is the remainder: `(self.row + k) % n` walks the lines from the cursor and wraps to
    // the first line. `if (std.mem.indexOfPos(...)) |c|` runs when the optional holds a column.
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

    // Zig tip: `self.match orelse return self.findNext(needle)` unwraps the optional, or returns from
    // the function with another value when it is null.
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

    // Zig tip: `while (std.mem.indexOfPos(...)) |c|` repeats while the search finds something, with
    // `c` the column of each find. `count += 1` counts the replacements; the result is the count.
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
