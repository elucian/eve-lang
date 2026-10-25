//! @eve-module evecp.fmt: the layout of a source file (`eve fmt`)
//! @spec spec/lexical/lexical.md#layout
//! @feature F-TLS-08
//! @tests test/level4/d46_fmt_command, code/evecp/src/fmt.zig
//! Text rules only; the indentation and the spaces inside a line are the author's (the parser already refuses a wrong indentation). A raw text literal (`"""` ... `"""`) is never touched.
const std = @import("std");

// @eve-fn cp.fmt
// @spec spec/lexical/lexical.md#layout
// @invariant format(format(x)) == format(x)
/// The source with LF line endings, no white space at the end of a line, no blank line at the start of the file, at most one blank line in a row and one line ending at the end. Free with `gpa`.
pub fn format(gpa: std.mem.Allocator, src: []const u8) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var in_raw = false;
    var blanks: usize = 0;
    var started = false;
    var rest = src;
    while (rest.len > 0) {
        const nl = std.mem.indexOfAny(u8, rest, "\r\n");
        const line = if (nl) |i| rest[0..i] else rest;
        const skip: usize = if (nl) |i| (if (rest[i] == '\r' and i + 1 < rest.len and rest[i + 1] == '\n') i + 2 else i + 1) else rest.len;
        rest = rest[skip..];
        if (in_raw) {
            // the inside of a raw text literal is data: every byte stays
            const closes = opensOrCloses(line);
            // the line that closes the literal ends in code: its end is trimmed like any other
            try out.appendSlice(gpa, if (closes) std.mem.trimEnd(u8, line, " \t") else line);
            try out.append(gpa, '\n');
            if (closes) in_raw = false;
            continue;
        }
        const text = std.mem.trimEnd(u8, line, " \t");
        if (text.len == 0) {
            if (started) blanks += 1;
            continue;
        }
        if (blanks > 0) try out.append(gpa, '\n');
        blanks = 0;
        started = true;
        try out.appendSlice(gpa, text);
        try out.append(gpa, '\n');
        if (opensOrCloses(text)) in_raw = true;
    }
    return out.toOwnedSlice(gpa);
}

/// Does the line change the state of a raw text literal: an odd number of `"""` outside a comment.
fn opensOrCloses(line: []const u8) bool {
    const t = std.mem.trimStart(u8, line, " \t");
    if (std.mem.startsWith(u8, t, "**") or (line.len > 0 and line[0] == '#')) return false;
    var n: usize = 0;
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, line, i, "\"\"\"")) |at| {
        n += 1;
        i = at + 3;
    }
    return n % 2 == 1;
}

test "spec: lexical.md#layout the layout of a file is trimmed, blank lines are collapsed and the end is one line ending" {
    const a = std.testing.allocator;
    const got = try format(a, "\n\n# title  \r\nprimary aspect a is\t\n\n\n\n  process main is\r\n    print 1;   \n  return;\nend a;\n\n\n");
    defer a.free(got);
    try std.testing.expectEqualStrings("# title\nprimary aspect a is\n\n  process main is\n    print 1;\n  return;\nend a;\n", got);
}

test "spec: lexical.md#layout a raw text literal is not touched" {
    const a = std.testing.allocator;
    const src = "x := \"\"\"\n  keep  \n\n\n  this   \n\"\"\";  \nend\n";
    const got = try format(a, src);
    defer a.free(got);
    try std.testing.expectEqualStrings("x := \"\"\"\n  keep  \n\n\n  this   \n\"\"\";\nend\n", got);
}

test "format is idempotent" {
    const a = std.testing.allocator;
    const once = try format(a, "a  \n\n\n\nb\t\n");
    defer a.free(once);
    const twice = try format(a, once);
    defer a.free(twice);
    try std.testing.expectEqualStrings(once, twice);
}
