//! A small Markdown renderer for the terminal: it turns the lines of a Markdown text into lines of styled pieces that fit a
//! given width. It knows headings, paragraphs (wrapped), bullet and numbered lists, block quotes, fenced code, rules and
//! tables, and inside a paragraph **bold**, *italic*, `code`, [links](url) and ![images](src). It draws nothing: the view
//! gives each kind of piece its color.
const std = @import("std");

// Zig tip: an enum names the kinds of piece; the view has one `switch` over it, so a new kind cannot be forgotten there.
/// What a piece of a rendered line is.
pub const Kind = enum { text, bold, italic, code, link, h1, h2, h3, quote, bullet, rule, code_block, table, table_head, table_line };

/// A piece of text of one kind. `text` is a slice of the source or of memory of the arena.
pub const Span = struct { text: []const u8, kind: Kind };

/// A line of the rendered page.
pub const Line = struct { spans: []const Span };

const Inline = struct { text: []const u8, kind: Kind };

// Zig tip: the scanner walks the paragraph once and cuts it at the marks `**`, `*`, `_`, `` ` `` and `[`. What lies between
// two marks is a piece of that kind. `std.mem.indexOfPos` finds the closing mark after the opening one; without a closing
// mark the opening mark is plain text. Every piece is a slice of the line: nothing is copied.
/// Cut a line of text into pieces by its inline marks.
fn inlines(a: std.mem.Allocator, s: []const u8) ![]Inline {
    var out: std.ArrayList(Inline) = .empty;
    var plain_start: usize = 0;
    var i: usize = 0;
    while (i < s.len) {
        var handled = false;
        const rest = s[i..];
        var kind: Kind = .text;
        var open: usize = 0;
        var close_mark: []const u8 = "";
        if (std.mem.startsWith(u8, rest, "**")) {
            kind = .bold;
            open = 2;
            close_mark = "**";
        } else if (rest[0] == '`') {
            kind = .code;
            open = 1;
            close_mark = "`";
        } else if (rest[0] == '*' or rest[0] == '_') {
            // `_` inside a word (snake_case) is not a mark
            const inside = rest[0] == '_' and i > 0 and std.ascii.isAlphanumeric(s[i - 1]);
            if (!inside) {
                kind = .italic;
                open = 1;
                close_mark = rest[0..1];
            }
        }
        if (open > 0) {
            if (std.mem.indexOfPos(u8, s, i + open, close_mark)) |end| {
                if (end > i + open) {
                    if (i > plain_start) try out.append(a, .{ .text = s[plain_start..i], .kind = .text });
                    try out.append(a, .{ .text = s[i + open .. end], .kind = kind });
                    i = end + close_mark.len;
                    plain_start = i;
                    handled = true;
                }
            }
        } else if (rest[0] == '[' or (rest[0] == '!' and rest.len > 1 and rest[1] == '[')) {
            const image = rest[0] == '!';
            const lb = i + @as(usize, if (image) 1 else 0);
            if (std.mem.indexOfScalarPos(u8, s, lb, ']')) |rb| {
                if (rb + 1 < s.len and s[rb + 1] == '(') {
                    if (std.mem.indexOfScalarPos(u8, s, rb + 2, ')')) |rp| {
                        if (i > plain_start) try out.append(a, .{ .text = s[plain_start..i], .kind = .text });
                        const label = s[lb + 1 .. rb];
                        if (image) {
                            try out.append(a, .{ .text = try std.fmt.allocPrint(a, "[image: {s}]", .{label}), .kind = .italic });
                        } else try out.append(a, .{ .text = std.mem.trim(u8, label, "`"), .kind = .link });
                        i = rp + 1;
                        plain_start = i;
                        handled = true;
                    }
                }
            }
        }
        if (!handled) i += 1;
    }
    if (plain_start < s.len) try out.append(a, .{ .text = s[plain_start..], .kind = .text });
    return out.toOwnedSlice(a);
}

// Zig tip: a paragraph is poured into lines word by word: a word that does not fit on the line starts the next one. The
// words keep the kind of the piece they come from, so a bold word stays bold. `prefix` is written at the start of the first
// line and `hang` (blanks of the same width) at the start of the others, which is how a list item keeps its indent.
fn wrap(a: std.mem.Allocator, lines: *std.ArrayList(Line), pieces: []const Inline, width: usize, prefix: []const Span, prefix_w: usize, hang: []const u8) !void {
    var cur: std.ArrayList(Span) = .empty;
    try cur.appendSlice(a, prefix);
    var used: usize = prefix_w;
    const avail = if (width > prefix_w + 8) width else prefix_w + 8;
    var first_in_line = true;
    // a blank between two pieces is written once, and only inside a line; `pending` remembers that one is due
    var pending = false;
    for (pieces) |p| {
        var words = std.mem.tokenizeScalar(u8, p.text, ' ');
        if (p.text.len > 0 and p.text[0] == ' ') pending = true;
        var k: usize = 0;
        while (words.next()) |w| : (k += 1) {
            const wl = std.unicode.utf8CountCodepoints(w) catch w.len;
            const space = !first_in_line and (pending or k > 0);
            const need = wl + @as(usize, if (space) 1 else 0);
            if (used + need > avail and !first_in_line) {
                try lines.append(a, .{ .spans = try cur.toOwnedSlice(a) });
                cur = .empty;
                try cur.append(a, .{ .text = hang, .kind = .text });
                used = hang.len;
                first_in_line = true;
            } else if (space) {
                try cur.append(a, .{ .text = " ", .kind = .text });
                used += 1;
            }
            try cur.append(a, .{ .text = w, .kind = p.kind });
            used += wl;
            first_in_line = false;
            pending = false;
        }
        if (p.text.len > 0 and p.text[p.text.len - 1] == ' ') pending = true;
    }
    if (cur.items.len > 0 and !(cur.items.len == prefix.len and prefix.len == 0)) try lines.append(a, .{ .spans = try cur.toOwnedSlice(a) });
}

fn isRule(t: []const u8) bool {
    if (t.len < 3) return false;
    const c = t[0];
    if (c != '-' and c != '*' and c != '_') return false;
    for (t) |x| {
        if (x != c and x != ' ') return false;
    }
    return true;
}

fn isTableSeparator(t: []const u8) bool {
    var has_dash = false;
    for (t) |c| {
        switch (c) {
            '-' => has_dash = true,
            '|', ':', ' ' => {},
            else => return false,
        }
    }
    return has_dash;
}

fn listMarkerLen(t: []const u8) usize {
    if (t.len >= 2 and (t[0] == '-' or t[0] == '*' or t[0] == '+') and t[1] == ' ') return 2;
    var d: usize = 0;
    while (d < t.len and std.ascii.isDigit(t[d])) d += 1;
    if (d > 0 and d + 1 < t.len and t[d] == '.' and t[d + 1] == ' ') return d + 2;
    return 0;
}

fn startsBlock(t: []const u8) bool {
    return t.len == 0 or t[0] == '#' or t[0] == '>' or t[0] == '|' or std.mem.startsWith(u8, t, "```") or isRule(t) or listMarkerLen(t) > 0;
}

// Zig tip: all the memory comes from the arena `a` that the caller gives (the arena of the frame), so nothing is freed
// here: the arena is dropped when the frame ends. The source is a list of lines, each a slice of the text buffer.
/// Render the Markdown `src` (one slice per line) into lines that are at most `width` cells wide.
pub fn render(a: std.mem.Allocator, src: []const []const u8, width: usize) ![]Line {
    var lines: std.ArrayList(Line) = .empty;
    var i: usize = 0;
    var in_code = false;
    while (i < src.len) : (i += 1) {
        const raw = std.mem.trimEnd(u8, src[i], "\r");
        const t = std.mem.trim(u8, raw, " \t");
        if (std.mem.startsWith(u8, t, "```")) {
            in_code = !in_code;
            continue;
        }
        if (in_code) {
            try lines.append(a, .{ .spans = try a.dupe(Span, &.{.{ .text = if (raw.len == 0) " " else raw, .kind = .code_block }}) });
            continue;
        }
        if (t.len == 0) {
            if (lines.items.len > 0 and lines.items[lines.items.len - 1].spans.len > 0) try lines.append(a, .{ .spans = &.{} });
            continue;
        }
        if (t[0] == '#') {
            var n: usize = 0;
            while (n < t.len and t[n] == '#') n += 1;
            const title = std.mem.trim(u8, t[n..], " #");
            const kind: Kind = switch (n) {
                1 => .h1,
                2 => .h2,
                else => .h3,
            };
            try lines.append(a, .{ .spans = try a.dupe(Span, &.{.{ .text = title, .kind = kind }}) });
            if (n <= 2) {
                try lines.append(a, .{ .spans = try a.dupe(Span, &.{.{ .text = if (n == 1) "═" else "─", .kind = .rule }}) });
            }
            continue;
        }
        if (isRule(t)) {
            try lines.append(a, .{ .spans = try a.dupe(Span, &.{.{ .text = "─", .kind = .rule }}) });
            continue;
        }
        if (t[0] == '>') {
            const body = std.mem.trim(u8, t[1..], " ");
            const prefix = try a.dupe(Span, &.{.{ .text = "▎ ", .kind = .quote }});
            try wrap(a, &lines, try inlines(a, body), width, prefix, 2, "▎ ");
            continue;
        }
        if (t[0] == '|') {
            // a table: the following lines that begin with `|`
            var rows: std.ArrayList([]const []const u8) = .empty;
            var head_rows: usize = 0;
            var j = i;
            while (j < src.len) : (j += 1) {
                const tj = std.mem.trim(u8, std.mem.trimEnd(u8, src[j], "\r"), " \t");
                if (tj.len == 0 or tj[0] != '|') break;
                if (isTableSeparator(tj)) {
                    if (rows.items.len > 0 and head_rows == 0) head_rows = rows.items.len;
                    continue;
                }
                var cells: std.ArrayList([]const u8) = .empty;
                var parts = std.mem.splitScalar(u8, std.mem.trim(u8, tj, "|"), '|');
                while (parts.next()) |c| try cells.append(a, std.mem.trim(u8, c, " "));
                try rows.append(a, try cells.toOwnedSlice(a));
            }
            i = j - 1;
            try renderTable(a, &lines, rows.items, head_rows);
            continue;
        }
        const marker = listMarkerLen(t);
        if (marker > 0) {
            const indent = raw.len - std.mem.trimStart(u8, raw, " \t").len;
            const bullet_text = if (t[0] == '-' or t[0] == '*' or t[0] == '+') "• " else t[0..marker];
            const lead = try a.alloc(u8, indent + 1);
            @memset(lead, ' ');
            const prefix = try a.dupe(Span, &.{ .{ .text = lead, .kind = .text }, .{ .text = bullet_text, .kind = .bullet } });
            const hang = try a.alloc(u8, lead.len + (std.unicode.utf8CountCodepoints(bullet_text) catch bullet_text.len));
            @memset(hang, ' ');
            try wrap(a, &lines, try inlines(a, t[marker..]), width, prefix, hang.len, hang);
            continue;
        }
        // a paragraph: this line and the following lines up to a blank line or the start of another block
        var para: std.ArrayList(u8) = .empty;
        try para.appendSlice(a, t);
        while (i + 1 < src.len) {
            const nt = std.mem.trim(u8, std.mem.trimEnd(u8, src[i + 1], "\r"), " \t");
            if (startsBlock(nt)) break;
            try para.append(a, ' ');
            try para.appendSlice(a, nt);
            i += 1;
        }
        try wrap(a, &lines, try inlines(a, para.items), width, &.{}, 0, "");
    }
    return lines.toOwnedSlice(a);
}

// Zig tip: the width of each column is the widest cell of that column; a row is then written cell by cell between
// vertical bars, padded with spaces. The lines of the frame are `table_line` pieces, the head row is `table_head`.
fn renderTable(a: std.mem.Allocator, lines: *std.ArrayList(Line), rows: []const []const []const u8, head_rows: usize) !void {
    var ncols: usize = 0;
    for (rows) |r| ncols = @max(ncols, r.len);
    if (ncols == 0) return;
    const widths = try a.alloc(usize, ncols);
    @memset(widths, 1);
    for (rows) |r| {
        for (r, 0..) |c, k| widths[k] = @max(widths[k], std.unicode.utf8CountCodepoints(c) catch c.len);
    }
    try lines.append(a, .{ .spans = try a.dupe(Span, &.{.{ .text = try rule(a, widths, "┌", "┬", "┐"), .kind = .table_line }}) });
    for (rows, 0..) |r, ri| {
        var spans: std.ArrayList(Span) = .empty;
        try spans.append(a, .{ .text = "│", .kind = .table_line });
        for (0..ncols) |k| {
            const c: []const u8 = if (k < r.len) r[k] else "";
            const cw = std.unicode.utf8CountCodepoints(c) catch c.len;
            const cell = try std.fmt.allocPrint(a, " {s}{s} ", .{ c, spaces(a, widths[k] - cw) });
            try spans.append(a, .{ .text = cell, .kind = if (ri < head_rows) .table_head else .table });
            try spans.append(a, .{ .text = "│", .kind = .table_line });
        }
        try lines.append(a, .{ .spans = try spans.toOwnedSlice(a) });
        if (head_rows > 0 and ri + 1 == head_rows and ri + 1 < rows.len) {
            try lines.append(a, .{ .spans = try a.dupe(Span, &.{.{ .text = try rule(a, widths, "├", "┼", "┤"), .kind = .table_line }}) });
        }
    }
    try lines.append(a, .{ .spans = try a.dupe(Span, &.{.{ .text = try rule(a, widths, "└", "┴", "┘"), .kind = .table_line }}) });
}

fn spaces(a: std.mem.Allocator, n: usize) []const u8 {
    const s = a.alloc(u8, n) catch return "";
    @memset(s, ' ');
    return s;
}

fn rule(a: std.mem.Allocator, widths: []const usize, l: []const u8, m: []const u8, r: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, l);
    for (widths, 0..) |w, k| {
        for (0..w + 2) |_| try out.appendSlice(a, "─");
        try out.appendSlice(a, if (k + 1 == widths.len) r else m);
    }
    return out.toOwnedSlice(a);
}

// Zig tip: the tests use an arena, so they need no `free`: `defer arena.deinit()` drops everything at the end.
test "headings, wrapped paragraph, list and table" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = [_][]const u8{ "# Title", "", "Some **bold** words and `code` that must wrap onto the next line.", "", "- one", "- two", "", "| a | b |", "|---|---|", "| 1 | 22 |" };
    const lines = try render(a, &src, 30);
    try std.testing.expect(lines.len >= 10);
    try std.testing.expectEqual(Kind.h1, lines[0].spans[0].kind);
    var saw_bold = false;
    var saw_table = false;
    for (lines) |l| {
        for (l.spans) |s| {
            if (s.kind == .bold and std.mem.eql(u8, s.text, "bold")) saw_bold = true;
            if (s.kind == .table_head) saw_table = true;
        }
    }
    try std.testing.expect(saw_bold and saw_table);
}
