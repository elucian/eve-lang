//! The look of the REPL: the banner shown when `eve` starts at a terminal, the table of the `help` command and the page
//! of `help <command>`.
//!
//! Two styles: `fancy` (box-drawing characters in UTF-8 and ANSI colors, for a person at a terminal) and plain
//! (ASCII borders, no colors, for a pipe or a test). Every drawing function takes the `width` to fill, so the screen can
//! draw the same text again when the window changes size. The console must show a fixed-width font with the box and
//! block characters, such as DejaVu Sans Mono: the font belongs to the terminal, not to the program (manual/usage.md).
const std = @import("std");
const Io = std.Io;
const version = @import("version.zig");
const helptext = @import("helptext.zig");

// Zig tip: a struct with a default field is a small "settings" value: `.{}` is plain, `.{ .fancy = true }` is the
// terminal look. Passing it around keeps one `if` per drawing function instead of a flag in every call.
/// How to draw.
pub const Style = struct {
    fancy: bool = false,
};

/// One line of the help table: a command and what it does.
pub const Row = struct {
    name: []const u8,
    summary: []const u8,
};

/// The width of the table and the texts when nothing else is set (the variable EVE_WIDTH, `eve_width` in eve.cfg).
pub const default_width = 100;
/// The least width that is worth drawing; a narrower window is drawn at this width and the terminal cuts it.
pub const min_width = 30;

const reset = "\x1b[0m";
const bold = "\x1b[1m";
const accent = "\x1b[1;36m";
const dim = "\x1b[2m";

// Zig tip: a struct of strings is a table of constants. `unicode` and `ascii` have the same fields, so the drawing
// code picks one of them once (`const c = if (...) unicode else ascii;`) and never asks again.
const Chars = struct {
    h: []const u8,
    v: []const u8,
    tl: []const u8,
    tm: []const u8,
    tr: []const u8,
    ml: []const u8,
    mm: []const u8,
    mr: []const u8,
    bl: []const u8,
    bm: []const u8,
    br: []const u8,
};

const unicode: Chars = .{ .h = "─", .v = "│", .tl = "┌", .tm = "┬", .tr = "┐", .ml = "├", .mm = "┼", .mr = "┤", .bl = "└", .bm = "┴", .br = "┘" };
const ascii: Chars = .{ .h = "-", .v = "|", .tl = "+", .tm = "+", .tr = "+", .ml = "+", .mm = "+", .mr = "+", .bl = "+", .bm = "+", .br = "+" };

// Zig tip: a string is bytes, and one UTF-8 character can take up to four of them. The continuation bytes all look
// like `10xxxxxx`, so counting the bytes that do not (`b & 0xC0 != 0x80`) counts the characters, which is the width on
// a fixed-width screen. `.len` would make a box with `─` or `█` too narrow to pad.
/// The width of a text on the screen, in characters.
pub fn cells(s: []const u8) usize {
    var n: usize = 0;
    for (s) |b| {
        if (b & 0xC0 != 0x80) n += 1;
    }
    return n;
}

// Zig tip: `for (0..n) |_|` repeats n times; the range `0..n` has no values worth a name, so `_` drops them.
fn pad(w: *Io.Writer, n: usize) Io.Writer.Error!void {
    for (0..n) |_| try w.writeByte(' ');
}

fn repeat(w: *Io.Writer, s: []const u8, n: usize) Io.Writer.Error!void {
    for (0..n) |_| try w.writeAll(s);
}

// Zig tip: `fancy and color.len > 0` short-circuits: with a plain style the color text is never written. The helper
// writes `text` in a color and the padding outside it, so the colors do not change the width of the column.
/// One cell of a row: a blank, the text (in `color` when fancy), blanks up to `width`, a blank.
fn cell(w: *Io.Writer, style: Style, text: []const u8, width: usize, color: []const u8) Io.Writer.Error!void {
    try w.writeByte(' ');
    if (style.fancy and color.len > 0 and text.len > 0) {
        try w.writeAll(color);
        try w.writeAll(text);
        try w.writeAll(reset);
    } else {
        try w.writeAll(text);
    }
    try pad(w, width -| cells(text));
    try w.writeByte(' ');
}

/// A horizontal rule of the table: `left`, the segments of the columns joined by `mid`, `right`.
fn rule(w: *Io.Writer, c: Chars, left: []const u8, mid: []const u8, right: []const u8, widths: []const usize) Io.Writer.Error!void {
    try w.writeAll(left);
    for (widths, 0..) |wd, i| {
        if (i > 0) try w.writeAll(mid);
        try repeat(w, c.h, wd + 2);
    }
    try w.writeAll(right);
    try w.writeByte('\n');
}

// Zig tip: the loop walks the bytes once and remembers where the last blank was, so a line breaks between words; a
// word longer than the width is cut at the width. Only the first byte of a character counts, as in `cells`. The
// function answers a length, and the caller slices the text with it: nothing is copied.
/// The length in bytes of the first line of `text` when it is wrapped at `width` characters.
fn firstLine(text: []const u8, width: usize) usize {
    var n: usize = 0;
    var last_blank: ?usize = null;
    for (text, 0..) |b, i| {
        if (b & 0xC0 != 0x80) {
            if (n == width) {
                if (b == ' ') return i;
                return last_blank orelse i;
            }
            n += 1;
        }
        if (b == ' ') last_blank = i;
    }
    return text.len;
}

// Zig tip: `std.mem.splitScalar` walks the pieces of a text between a separator, here the paragraphs; it gives the
// empty pieces too, which the loop skips. The first paragraph starts at `first` blanks and the next lines at `rest`:
// a hanging indent is two different numbers. `@max(avail, 1)` keeps the width positive in a very narrow window.
/// Write `text` wrapped to `width` characters. A `\n` in the text starts a new paragraph, after a blank line.
pub fn writeWrapped(w: *Io.Writer, text: []const u8, width: usize, first: usize, rest: usize) Io.Writer.Error!void {
    var paragraphs = std.mem.splitScalar(u8, text, '\n');
    var is_first = true;
    while (paragraphs.next()) |paragraph| {
        if (paragraph.len == 0) continue;
        if (!is_first) try w.writeByte('\n');
        var indent = if (is_first) first else rest;
        is_first = false;
        var left = paragraph;
        while (left.len > 0) {
            const n = firstLine(left, @max(width -| indent, 1));
            try pad(w, indent);
            try w.writeAll(left[0..n]);
            try w.writeByte('\n');
            left = std.mem.trimStart(u8, left[n..], " ");
            indent = rest;
        }
    }
}

/// An item of a list: `label` padded to `label_width`, then the text wrapped with the lines under the text.
fn writeItem(w: *Io.Writer, style: Style, indent: usize, label: []const u8, label_width: usize, text: []const u8, width: usize) Io.Writer.Error!void {
    try pad(w, indent);
    if (style.fancy) try w.writeAll(bold);
    try w.writeAll(label);
    if (style.fancy) try w.writeAll(reset);
    try pad(w, label_width -| cells(label));
    const hang = indent + label_width;
    var left = text;
    var first = true;
    while (left.len > 0) {
        const n = firstLine(left, @max(width -| hang, 1));
        if (!first) try pad(w, hang);
        try w.writeAll(left[0..n]);
        try w.writeByte('\n');
        left = std.mem.trimStart(u8, left[n..], " ");
        first = false;
    }
    if (first) try w.writeByte('\n');
}

fn heading(w: *Io.Writer, style: Style, text: []const u8) Io.Writer.Error!void {
    if (style.fancy) try w.writeAll(accent);
    try w.writeAll(text);
    if (style.fancy) try w.writeAll(reset);
    try w.writeByte('\n');
}

/// One line of the table: `|`, two cells, `|`.
fn line(w: *Io.Writer, style: Style, c: Chars, widths: []const usize, name: []const u8, text: []const u8, color: []const u8) Io.Writer.Error!void {
    try w.writeAll(c.v);
    try cell(w, style, name, widths[0], color);
    try w.writeAll(c.v);
    try cell(w, style, text, widths[1], "");
    try w.writeAll(c.v);
    try w.writeByte('\n');
}

// Zig tip: `@max(a, b)` is a builtin that works on any number type, and `[2]usize{ ... }` is an array whose length is
// part of its type. `std.mem.trimStart` cuts the listed characters from the start of a slice without copying: the
// result is a view of the same bytes. The table is as wide as `width` says (never less than the room the first
// column and a few characters of text need); a summary longer than its column continues on the next line.
/// Draw the table of the commands: two columns, a header, and a line between the commands.
pub fn writeTable(w: *Io.Writer, style: Style, rows: []const Row, width: usize) Io.Writer.Error!void {
    const c = if (style.fancy) unicode else ascii;
    var first_col: usize = "Command".len;
    for (rows) |r| first_col = @max(first_col, cells(r.name));
    const second_col = @max(width, first_col + 7 + 10) - first_col - 7;
    const widths = [2]usize{ first_col, second_col };
    try rule(w, c, c.tl, c.tm, c.tr, &widths);
    try line(w, style, c, &widths, "Command", "What it does", accent);
    for (rows) |r| {
        try rule(w, c, c.ml, c.mm, c.mr, &widths);
        var rest = r.summary;
        var first = true;
        while (first or rest.len > 0) {
            const n = firstLine(rest, second_col);
            try line(w, style, c, &widths, if (first) r.name else "", rest[0..n], bold);
            rest = std.mem.trimStart(u8, rest[n..], " ");
            first = false;
        }
    }
    try rule(w, c, c.bl, c.bm, c.br, &widths);
}

/// The hint under the table.
fn writeHint(w: *Io.Writer, style: Style, width: usize) Io.Writer.Error!void {
    if (style.fancy) try w.writeAll(dim);
    try writeWrapped(w, "help <command> (or <command> ?) shows the syntax and the options of one command. ? or help shows this table. Tab completes file names. quit leaves.", width, 0, 0);
    if (style.fancy) try w.writeAll(reset);
}

// Zig tip: `rows` is built in a fixed array on the stack, as long as the table of the help texts, which is known while
// compiling (`helptext.entries.len`). `for (&helptext.entries, &rows) |e, *row|` walks both together and fills each
// row in place through the pointer `*row`.
/// `help`: the table of all the commands and the hint.
pub fn writeHelpTable(w: *Io.Writer, style: Style, width: usize) Io.Writer.Error!void {
    var rows: [helptext.entries.len]Row = undefined;
    for (&helptext.entries, &rows) |e, *row| row.* = .{ .name = e.name, .summary = e.short };
    try writeTable(w, style, &rows, width);
    try writeHint(w, style, width);
}

/// `help <command>`: the page of one command: the syntax, the text, the options and the examples, wrapped to `width`.
pub fn writeDetail(w: *Io.Writer, style: Style, e: helptext.Entry, width: usize) Io.Writer.Error!void {
    var title: [256]u8 = undefined;
    const dash = if (style.fancy) "—" else "-";
    const text = std.fmt.bufPrint(&title, "{s} {s} {s}", .{ e.name, dash, e.short }) catch e.name;
    if (style.fancy) try w.writeAll(accent);
    try writeWrapped(w, text, width, 0, e.name.len + 3);
    if (style.fancy) try w.writeAll(reset);
    try w.writeByte('\n');
    try heading(w, style, "Syntax");
    for (e.syntax) |s| {
        if (style.fancy) try w.writeAll(bold);
        try writeWrapped(w, s, width, 2, 4);
        if (style.fancy) try w.writeAll(reset);
    }
    try w.writeByte('\n');
    try writeWrapped(w, e.text, width, 0, 0);
    if (e.options.len > 0) {
        var label_width: usize = 0;
        for (e.options) |o| label_width = @max(label_width, cells(o.word));
        try w.writeByte('\n');
        try heading(w, style, "Options");
        for (e.options) |o| try writeItem(w, style, 2, o.word, label_width + 2, o.text, width);
    }
    if (e.examples.len > 0) {
        try w.writeByte('\n');
        try heading(w, style, "Examples");
        for (e.examples) |x| {
            try pad(w, 2);
            try w.writeAll(x);
            try w.writeByte('\n');
        }
    }
}

const logo = [3][]const u8{ "█▀▀ █ █ █▀▀", "█▀▀ ▀▄▀ █▀▀", "▀▀▀  ▀  ▀▀▀" };
const info = [3][]const u8{
    "EVE " ++ version.version ++ "  ·  spec " ++ version.spec_version,
    "scripting for data and test automation",
    "machine, doors and database in one program",
};

// Zig tip: `inline for` is unrolled by the compiler and needs a comptime-known array, which `info` is, so the width
// of the box is computed while compiling and costs nothing at run time. `comptime` forces a block to run then.
/// The banner: a box with the logo, the version and the ready message under it.
pub fn writeBanner(w: *Io.Writer, style: Style) Io.Writer.Error!void {
    if (!style.fancy) {
        try w.print("{s}\nReady. Type help (or ?) and Enter for commands.\n", .{version.title});
        return;
    }
    const inner = comptime blk: {
        var m: usize = 0;
        for (info) |t| m = @max(m, cells(t));
        break :blk 2 + cells(logo[0]) + 3 + m + 2;
    };
    const c = unicode;
    try w.writeAll("\n");
    try w.writeAll("╭");
    try repeat(w, c.h, inner);
    try w.writeAll("╮\n");
    for (logo, info) |art, text| {
        try w.writeAll("│  ");
        try w.print("{s}{s}{s}   {s}", .{ accent, art, reset, text });
        try pad(w, inner - 2 - cells(art) - 3 - cells(text));
        try w.writeAll("│\n");
    }
    try w.writeAll("╰");
    try repeat(w, c.h, inner);
    try w.writeAll("╯\n\n");
    try w.print(" Ready. Type {s}help{s} (or {s}?{s}) and Enter for commands.\n\n", .{ bold, reset, bold, reset });
}

test "the table has a line between the commands, borders of equal width, and wraps a long summary" {
    var buf: [4096]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    const rows = [_]Row{
        .{ .name = "check", .summary = "check the syntax of a script, do not execute it" },
        .{ .name = "status", .summary = "the state of the machine: script, configuration, doors, what it is doing, and more words to make it long" },
    };
    try writeTable(&w, .{}, &rows, 60);
    var lines = std.mem.splitScalar(u8, w.buffered(), '\n');
    const top = lines.next().?;
    try std.testing.expect(std.mem.startsWith(u8, top, "+--"));
    try std.testing.expectEqual(@as(usize, 60), top.len);
    var count: usize = 1;
    var rules: usize = 1;
    while (lines.next()) |l| {
        if (l.len == 0) continue;
        try std.testing.expectEqual(top.len, l.len);
        count += 1;
        if (l[0] == '+') rules += 1;
    }
    // top, header, rule, check on two lines, rule, status on three lines (the column is 46 characters), bottom
    try std.testing.expectEqual(@as(usize, 10), count);
    try std.testing.expectEqual(@as(usize, 4), rules);
}

test "free text wraps to the width and keeps its paragraphs" {
    var buf: [1024]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try writeWrapped(&w, "one two three four five six\nnext paragraph", 12, 0, 2);
    try std.testing.expectEqualStrings("one two\n  three four\n  five six\n\n  next\n  paragraph\n", w.buffered());
}

test "help of one command shows syntax, options and examples at the given width" {
    var buf: [4096]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try writeDetail(&w, .{}, helptext.find("listen").?.*, 50);
    const out = w.buffered();
    try std.testing.expect(std.mem.indexOf(u8, out, "Syntax\n  listen [start|stop|restart|status]") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Options\n  start") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Examples\n  listen\n") != null);
    var lines = std.mem.splitScalar(u8, out, '\n');
    while (lines.next()) |l| try std.testing.expect(l.len <= 50);
}

test "the banner shows the version and the ready message" {
    var buf: [2048]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try writeBanner(&w, .{ .fancy = true });
    try std.testing.expect(std.mem.indexOf(u8, w.buffered(), version.version) != null);
    try std.testing.expect(std.mem.indexOf(u8, w.buffered(), "for commands") != null);
    try std.testing.expectEqual(@as(usize, 11), cells(logo[0]));
}
