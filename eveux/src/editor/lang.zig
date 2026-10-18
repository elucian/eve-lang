//! @eve-module lang: the language of a tab and the colored spans of a line
//! @spec eveux/README.md#7-the-code
//! @feature F-TLS-19
//! @decision D-193
//! @tests zig test --dep shared -Mroot=src/editor/lang.zig -Mshared=../evetx/src/shared.zig (from eveux/)
//! A colorizer turns one line (and the state left by the lines above) into spans of a class; the editor widget maps a class to a
//! theme color. Eve uses the scanner and the keyword list of evetx (module `shared`, generated from spec/lexical/keywords.json).
//! The other languages are plain in this draft: each gets its own file next to this one (html.zig, css.zig, js.zig, json.zig,
//! xml.zig, sql.zig, md.zig), as small hand-written scanners like the one of evetx for SQL.
const std = @import("std");
const shared = @import("shared");

pub const Lang = enum { eve, sql, json, xml, html, css, javascript, markdown, plain };

pub const Class = enum { plain, comment, string, number, keyword, title, type_name, function, tag, attribute };

pub const Span = struct { start: usize, end: usize, class: Class };

/// The state at the start of a line: inside a block comment or an expression comment of an earlier line.
pub const Carry = shared.scan.Carry;

// @eve-fn isKeyword
/// Is `word` a keyword of Eve (the generated list of evetx).
pub fn isKeyword(word: []const u8) bool {
    for (shared.keywords.words) |k| if (std.mem.eql(u8, k, word)) return true;
    return false;
}

// @eve-fn highlight
/// Append the spans of one line and leave the state for the next line in `carry`. The spans cover the whole line, in order.
pub fn highlight(a: std.mem.Allocator, lang: Lang, line: []const u8, carry: *Carry, out: *std.ArrayList(Span)) std.mem.Allocator.Error!void {
    switch (lang) {
        .eve => try highlightEve(a, line, carry, out),
        else => if (line.len > 0) try out.append(a, .{ .start = 0, .end = line.len, .class = .plain }),
    }
}

fn highlightEve(a: std.mem.Allocator, line: []const u8, carry: *Carry, out: *std.ArrayList(Span)) std.mem.Allocator.Error!void {
    const start_carry = carry.*;
    var sc: shared.scan.Scan = .{ .line = line, .carry = carry.* };
    while (sc.next()) |t| {
        const class: Class = switch (t.kind) {
            .comment => if (start_carry == .none and line[0] == '#') .title else .comment,
            .comment_expr, .comment_block => .comment,
            .string => .string,
            .number => .number,
            .word => if (isKeyword(line[t.start..t.end])) .keyword else .plain,
            .plain => .plain,
        };
        try out.append(a, .{ .start = t.start, .end = t.end, .class = class });
    }
    carry.* = sc.carry;
}

test "an Eve line: keyword, string, comment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var spans: std.ArrayList(Span) = .empty;
    var carry: Carry = .none;
    try highlight(arena.allocator(), .eve, "primary aspect a is ** note", &carry, &spans);
    try std.testing.expectEqual(Class.keyword, spans.items[0].class);
    try std.testing.expectEqual(Class.comment, spans.items[spans.items.len - 1].class);
    try std.testing.expectEqual(Carry.none, carry);
}

test "a block comment keeps its state on the next line" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var spans: std.ArrayList(Span) = .empty;
    var carry: Carry = .none;
    try highlight(arena.allocator(), .eve, "new x := 1; /* start", &carry, &spans);
    try std.testing.expectEqual(Carry.block, carry);
    spans.clearRetainingCapacity();
    try highlight(arena.allocator(), .eve, "# still comment */ print x;", &carry, &spans);
    try std.testing.expectEqual(Class.comment, spans.items[0].class);
    try std.testing.expectEqual(Carry.none, carry);
}

test "the title line" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var spans: std.ArrayList(Span) = .empty;
    var carry: Carry = .none;
    try highlight(arena.allocator(), .eve, "# sales load", &carry, &spans);
    try std.testing.expectEqual(Class.title, spans.items[0].class);
}
