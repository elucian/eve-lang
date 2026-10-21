//! @eve-module markdown: a Markdown subset parsed to blocks and spans, for the preview tab
//! @spec design/components/eveux/README.md#5-previews
//! @feature F-TLS-19
//! @decision D-193
//! @tests zig test src/preview/markdown.zig (from code/eveux/)
//! No screen code: the preview widget walks `Doc` and draws it. All text slices point into the source; only the lists of
//! blocks and spans are allocated, in the arena that the caller gives and frees at once.
//! Subset: headings `#`, paragraphs, bullet and numbered lists, code fences, block quotes, rules, pipe tables;
//! inline `code`, **strong**, *emphasis*, [links](url) and ![images](url). No raw HTML, no nested lists (first version).
const std = @import("std");

pub const SpanKind = enum { text, code, strong, emph, link, image };

/// A piece of a line: `text` is what is shown (the alt text of an image), `url` is the target of a link or an image.
pub const Span = struct { kind: SpanKind, text: []const u8, url: []const u8 = "" };

pub const Block = union(enum) {
    heading: struct { level: u8, spans: []const Span },
    paragraph: []const Span,
    bullets: []const []const Span,
    numbered: []const []const Span,
    code: struct { lang: []const u8, text: []const u8 },
    quote: []const Span,
    rule,
    table: struct { head: []const []const Span, rows: []const []const []const Span },
};

pub const Doc = struct { blocks: []const Block };

// @eve-fn parse
/// Parse `src` into blocks. `a` should be an arena: nothing is freed one by one.
pub fn parse(a: std.mem.Allocator, src: []const u8) std.mem.Allocator.Error!Doc {
    var blocks: std.ArrayList(Block) = .empty;
    var lines: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, src, '\n');
    while (it.next()) |raw| try lines.append(a, std.mem.trimEnd(u8, raw, "\r"));
    const ls = lines.items;
    var i: usize = 0;
    while (i < ls.len) {
        const line = ls[i];
        const t = std.mem.trim(u8, line, " \t");
        if (t.len == 0) {
            i += 1;
        } else if (std.mem.startsWith(u8, t, "```")) {
            const lang = std.mem.trim(u8, t[3..], " \t");
            const start = i + 1;
            var j = start;
            while (j < ls.len and !std.mem.startsWith(u8, std.mem.trim(u8, ls[j], " \t"), "```")) j += 1;
            try blocks.append(a, .{ .code = .{ .lang = lang, .text = joinLines(src, ls, start, j) } });
            i = if (j < ls.len) j + 1 else j;
        } else if (t[0] == '#') {
            var level: u8 = 0;
            while (level < t.len and t[level] == '#' and level < 6) level += 1;
            if (level < t.len and t[level] == ' ') {
                try blocks.append(a, .{ .heading = .{ .level = level, .spans = try inlines(a, std.mem.trim(u8, t[level..], " \t")) } });
                i += 1;
            } else {
                i = try paragraph(a, &blocks, ls, i);
            }
        } else if (isRule(t)) {
            try blocks.append(a, .rule);
            i += 1;
        } else if (t[0] == '>') {
            try blocks.append(a, .{ .quote = try inlines(a, std.mem.trim(u8, t[1..], " \t")) });
            i += 1;
        } else if (isBullet(t)) {
            var items: std.ArrayList([]const Span) = .empty;
            while (i < ls.len and isBullet(std.mem.trim(u8, ls[i], " \t"))) : (i += 1) {
                try items.append(a, try inlines(a, std.mem.trim(u8, ls[i], " \t")[2..]));
            }
            try blocks.append(a, .{ .bullets = items.items });
        } else if (numberLen(t) > 0) {
            var items: std.ArrayList([]const Span) = .empty;
            while (i < ls.len) : (i += 1) {
                const u = std.mem.trim(u8, ls[i], " \t");
                const n = numberLen(u);
                if (n == 0) break;
                try items.append(a, try inlines(a, std.mem.trim(u8, u[n..], " \t")));
            }
            try blocks.append(a, .{ .numbered = items.items });
        } else if (t[0] == '|' and i + 1 < ls.len and isTableRule(std.mem.trim(u8, ls[i + 1], " \t"))) {
            const head = try cells(a, t);
            var rows: std.ArrayList([]const []const Span) = .empty;
            i += 2;
            while (i < ls.len and std.mem.trim(u8, ls[i], " \t").len > 0 and std.mem.trim(u8, ls[i], " \t")[0] == '|') : (i += 1) {
                try rows.append(a, try cells(a, std.mem.trim(u8, ls[i], " \t")));
            }
            try blocks.append(a, .{ .table = .{ .head = head, .rows = rows.items } });
        } else {
            i = try paragraph(a, &blocks, ls, i);
        }
    }
    return .{ .blocks = blocks.items };
}

/// The text of lines `from` up to `to` (not included), as one slice of the source.
fn joinLines(src: []const u8, ls: []const []const u8, from: usize, to: usize) []const u8 {
    if (from >= to) return "";
    const a0 = @intFromPtr(ls[from].ptr) - @intFromPtr(src.ptr);
    const last = ls[to - 1];
    const b0 = @intFromPtr(last.ptr) - @intFromPtr(src.ptr) + last.len;
    return src[a0..b0];
}

fn paragraph(a: std.mem.Allocator, blocks: *std.ArrayList(Block), ls: []const []const u8, start: usize) std.mem.Allocator.Error!usize {
    var j = start;
    var buf: std.ArrayList(u8) = .empty;
    while (j < ls.len) : (j += 1) {
        const t = std.mem.trim(u8, ls[j], " \t");
        if (t.len == 0 or (j > start and (t[0] == '#' or isBullet(t) or std.mem.startsWith(u8, t, "```") or t[0] == '>'))) break;
        if (buf.items.len > 0) try buf.append(a, ' ');
        try buf.appendSlice(a, t);
    }
    try blocks.append(a, .{ .paragraph = try inlines(a, buf.items) });
    return j;
}

fn isBullet(t: []const u8) bool {
    return t.len >= 2 and (t[0] == '-' or t[0] == '*' or t[0] == '+') and t[1] == ' ';
}

fn isRule(t: []const u8) bool {
    if (t.len < 3) return false;
    for (t) |c| if (c != '-' and c != '*' and c != '_') return false;
    return true;
}

/// The length of `12. ` at the start of a line, or 0.
fn numberLen(t: []const u8) usize {
    var n: usize = 0;
    while (n < t.len and std.ascii.isDigit(t[n])) n += 1;
    if (n == 0 or n + 1 >= t.len or t[n] != '.' or t[n + 1] != ' ') return 0;
    return n + 2;
}

fn isTableRule(t: []const u8) bool {
    if (t.len == 0 or t[0] != '|') return false;
    for (t) |c| if (c != '|' and c != '-' and c != ':' and c != ' ') return false;
    return true;
}

fn cells(a: std.mem.Allocator, row: []const u8) std.mem.Allocator.Error![]const []const Span {
    var out: std.ArrayList([]const Span) = .empty;
    const inner = std.mem.trim(u8, std.mem.trim(u8, row, "|"), " ");
    var it = std.mem.splitScalar(u8, inner, '|');
    while (it.next()) |c| try out.append(a, try inlines(a, std.mem.trim(u8, c, " \t")));
    return out.items;
}

// @eve-fn inlines
/// The spans of one line of text: code, strong, emphasis, links and images; the rest is plain text.
pub fn inlines(a: std.mem.Allocator, s: []const u8) std.mem.Allocator.Error![]const Span {
    var out: std.ArrayList(Span) = .empty;
    var i: usize = 0;
    var plain: usize = 0;
    while (i < s.len) {
        const c = s[i];
        var consumed: usize = 0;
        var span: ?Span = null;
        if (c == '`') {
            if (std.mem.indexOfScalarPos(u8, s, i + 1, '`')) |e| {
                span = .{ .kind = .code, .text = s[i + 1 .. e] };
                consumed = e + 1 - i;
            }
        } else if (c == '*' and i + 1 < s.len and s[i + 1] == '*') {
            if (std.mem.indexOfPos(u8, s, i + 2, "**")) |e| {
                span = .{ .kind = .strong, .text = s[i + 2 .. e] };
                consumed = e + 2 - i;
            }
        } else if (c == '*' or c == '_') {
            if (std.mem.indexOfScalarPos(u8, s, i + 1, c)) |e| {
                if (e > i + 1) {
                    span = .{ .kind = .emph, .text = s[i + 1 .. e] };
                    consumed = e + 1 - i;
                }
            }
        } else if (c == '[' or (c == '!' and i + 1 < s.len and s[i + 1] == '[')) {
            const open = if (c == '!') i + 1 else i;
            if (std.mem.indexOfScalarPos(u8, s, open + 1, ']')) |close| {
                if (close + 1 < s.len and s[close + 1] == '(') {
                    if (std.mem.indexOfScalarPos(u8, s, close + 2, ')')) |end| {
                        span = .{ .kind = if (c == '!') .image else .link, .text = s[open + 1 .. close], .url = s[close + 2 .. end] };
                        consumed = end + 1 - i;
                    }
                }
            }
        }
        if (span) |sp| {
            if (i > plain) try out.append(a, .{ .kind = .text, .text = s[plain..i] });
            try out.append(a, sp);
            i += consumed;
            plain = i;
        } else {
            i += 1;
        }
    }
    if (plain < s.len) try out.append(a, .{ .kind = .text, .text = s[plain..] });
    return out.items;
}

test "headings, paragraphs and rules" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const doc = try parse(arena.allocator(), "# Sales ETL\n\nLoads the orders\nof the day.\n\n---\n");
    try std.testing.expectEqual(@as(usize, 3), doc.blocks.len);
    try std.testing.expectEqual(@as(u8, 1), doc.blocks[0].heading.level);
    try std.testing.expectEqualStrings("Sales ETL", doc.blocks[0].heading.spans[0].text);
    try std.testing.expectEqualStrings("Loads the orders of the day.", doc.blocks[1].paragraph[0].text);
    try std.testing.expect(doc.blocks[2] == .rule);
}

test "inline spans" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const sp = try inlines(arena.allocator(), "read `a.csv`, **now** and [docs](doc/x.md) ![logo](logo.png)");
    try std.testing.expectEqual(SpanKind.code, sp[1].kind);
    try std.testing.expectEqual(SpanKind.strong, sp[3].kind);
    try std.testing.expectEqualStrings("doc/x.md", sp[5].url);
    try std.testing.expectEqual(SpanKind.image, sp[7].kind);
}

test "lists, code fences and tables" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const src = "- one\n- two\n\n1. first\n2. second\n\n```eve\nnew x := 1;\n```\n\n| a | b |\n|---|---|\n| 1 | 2 |\n";
    const doc = try parse(arena.allocator(), src);
    try std.testing.expectEqual(@as(usize, 4), doc.blocks.len);
    try std.testing.expectEqual(@as(usize, 2), doc.blocks[0].bullets.len);
    try std.testing.expectEqual(@as(usize, 2), doc.blocks[1].numbered.len);
    try std.testing.expectEqualStrings("eve", doc.blocks[2].code.lang);
    try std.testing.expectEqualStrings("new x := 1;", doc.blocks[2].code.text);
    try std.testing.expectEqual(@as(usize, 2), doc.blocks[3].table.head.len);
    try std.testing.expectEqual(@as(usize, 1), doc.blocks[3].table.rows.len);
}

test "an unclosed mark stays plain text" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const sp = try inlines(arena.allocator(), "5 * 3 and `open");
    try std.testing.expectEqual(@as(usize, 1), sp.len);
    try std.testing.expectEqual(SpanKind.text, sp[0].kind);
}
