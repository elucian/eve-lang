//! The text of a value: `show`, `text`, and the formats of the interpolation (`{x:...}`).
//! Part of the interpreter (interp.zig): every function takes the interpreter as `it: *Interp`, and
//! `Interp` names each of them again, so a call reads `it.name(...)` wherever it is made.
const std = @import("std");
const Io = std.Io;
// Zig tip: interp.zig imports this file and this file imports interp.zig back. Zig allows such a cycle
// between files of one module: declarations are resolved lazily, when they are used, not in the order
// of the imports. `../` names the parent folder; a module may import any file below its root folder.
const interp = @import("../interp.zig");
const Interp = interp.Interp;
const data = interp.data;
const decimal = interp.decimal;
const instant = interp.instant;
const Node = interp.Node;
const value = interp.value;
const Signal = interp.Signal;
const Value = interp.Value;
const Channel = interp.Channel;

// ---- text of a value ------------------------------------------------------------------

// Zig tip: `x catch |e| ...` handles the error of a call on the spot, where `try` would pass it
// up to the caller.
pub fn utf8(it: *Interp, buf: *std.ArrayList(u8), cp: u21) Signal!void {
    var tmp: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(cp, &tmp) catch 1;
    try buf.appendSlice(it.t, tmp[0..n]);
}

// Zig tip: `buf.print(allocator, fmt, args)` formats straight into the growing list: no
// temporary string is made. The allocator is a parameter because the list may live in the
// scratch memory (text being built) or in the arena (a report that is kept).
/// Append formatted text to `buf`, which grows in `mem`.
pub fn appendFmt(buf: *std.ArrayList(u8), mem: std.mem.Allocator, comptime fmt: []const u8, args: anytype) Signal!void {
    try buf.print(mem, fmt, args);
}

// Zig tip: `show` writes the text of a value into a growable byte list. `quoted` is true inside
// a collection, where strings and symbols are shown with their quotes. `inline else` is not
// needed: every kind is listed. `for (items, 0..) |e, i|` loops with the index `i` too.
/// Append the text `print` gives for `v`.
pub fn show(it: *Interp, buf: *std.ArrayList(u8), v: Value, quoted: bool) Signal!void {
    switch (v) {
        // `null` is the value, `Null` its type (D-080, D-168): print writes the value
        .nil => try buf.appendSlice(it.t, "null"),
        .bool => |b| try buf.appendSlice(it.t, if (b) "True" else "False"),
        .int, .nat, .byte, .short, .huge => |n| try Interp.appendFmt(buf, it.t, "{d}", .{n}),
        .real, .float => |r| try Interp.appendFmt(buf, it.t, "{d}", .{r}),
        .dec => |d| {
            var aw: Io.Writer.Allocating = .init(it.t);
            decimal.write(&aw.writer, d) catch return error.OutOfMemory;
            try buf.appendSlice(it.t, aw.written());
        },
        .instant => |us| {
            var aw: Io.Writer.Allocating = .init(it.t);
            instant.write(&aw.writer, us) catch return error.OutOfMemory;
            try buf.appendSlice(it.t, aw.written());
        },
        .sym => |c| {
            if (quoted) try buf.append(it.t, '\'');
            try it.utf8(buf, c);
            if (quoted) try buf.append(it.t, '\'');
        },
        .str => |s| {
            if (quoted) try buf.append(it.t, '"');
            try buf.appendSlice(it.t, s);
            if (quoted) try buf.append(it.t, '"');
        },
        .list, .set => |l| {
            const open: u8 = if (v == .set) '{' else if (l.array) '[' else '(';
            const close: u8 = if (v == .set) '}' else if (l.array) ']' else ')';
            try buf.append(it.t, open);
            for (l.elems(), 0..) |e, i| {
                if (i > 0) try buf.append(it.t, ',');
                try it.show(buf, e, true);
            }
            try buf.append(it.t, close);
        },
        .map => |m| {
            try buf.append(it.t, '{');
            for (m.entries.items, 0..) |e, i| {
                if (i > 0) try buf.append(it.t, ',');
                try it.show(buf, e.key, true);
                try buf.append(it.t, ':');
                try it.show(buf, e.val, true);
            }
            try buf.append(it.t, '}');
        },
        .object => |o| {
            // a Secret never shows its text: print and interpolation write *** (data-language.md#secrets)
            if (o.class != null and o.class == it.base().secret_class) {
                try buf.appendSlice(it.t, "***");
                return;
            }
            if (value.adopts(o.class, "Printable")) {
                // a Printable object prints the text of its own `describe` method (D-145)
                try it.show(buf, try it.callMethod(v, "describe", &.{}), false);
                return;
            }
            try buf.append(it.t, '{');
            for (o.fields.items, 0..) |f, i| {
                if (i > 0) try buf.append(it.t, ',');
                try Interp.appendFmt(buf, it.t, "{s}:", .{f.name});
                try it.show(buf, f.val, true);
            }
            try buf.append(it.t, '}');
        },
        .class => |c| try Interp.appendFmt(buf, it.t, "class {s}", .{c.name}),
        .func => try buf.appendSlice(it.t, "<function>"),
        .module => |m| try Interp.appendFmt(buf, it.t, "module {s}", .{m.name}),
        .chan => |c| try Interp.appendFmt(buf, it.t, "Channel {s}", .{c.name}),
        .range => |r| try Interp.appendFmt(buf, it.t, "({d}..{d})", .{ r.lo, r.hi }),
        .domain => try buf.appendSlice(it.t, "(domain)"),
        .typ => |t| try buf.appendSlice(it.t, t),
    }
}

// Zig tip: `text` relies on the same Zig feature as `define` above: see the tip there.
// The text is in the scratch memory: it lives until the statement ends. A caller that keeps it
// copies it with `persist`.
pub fn text(it: *Interp, v: Value) Signal![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    try it.show(&buf, v, false);
    return buf.items;
}

// Zig tip: `a.dupe(u8, bytes)` copies a slice into memory of the allocator `a`: the copy stays
// valid after the scratch memory of the statement is released.
/// Keep `bytes` beyond the current statement: the string of a value.
pub fn persist(it: *Interp, bytes: []const u8) Signal![]const u8 {
    return it.h.str(bytes);
}

// Zig tip: `persist2` relies on the same Zig feature as `persist` above: see the tip there.
/// The persistent string `x ++ y`, built without an intermediate copy.
pub fn persist2(it: *Interp, x: []const u8, y: []const u8) Signal![]const u8 {
    return it.h.str2(x, y);
}

// ---- formats of the interpolation -----------------------------------------------------

// Zig tip: a plain `fn` at file level; without `pub` it is private to this file, and its
// parameters are read-only.
pub fn isAlign(c: u8) bool {
    return c == '<' or c == '>' or c == '^';
}

// Zig tip: a format such as `0>i5` is a tiny language: [fill][align][,][i|f]width[.precision].
// `spec` is cut with indexes; `std.fmt.parseInt(usize, digits, 10)` reads a number (`catch 0` when
// there are no digits). `@as(usize, ...)` pins the type of a literal. `std.unicode.utf8CountCodepoints`
// counts symbols, not bytes, so the width of "αβγ" is 3. Padding is built with `appendNTimes`.
/// Apply the format `spec` (the text after the `:`) of `\s{}`, `\#{}` or `\b{}` to `v`.
pub fn format(it: *Interp, letter: u8, spec: []const u8, v: Value) Signal![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    if (v == .bool or letter == 'b') {
        const b = v == .bool and v.bool;
        const word = if (std.mem.eql(u8, spec, "yn")) (if (b) "Yes" else "No") else if (std.mem.eql(u8, spec, "01"))
            (if (b) "1" else "0")
        else if (std.mem.eql(u8, spec, "tf")) (if (b) "T" else "F") else (if (b) "True" else "False");
        return word;
    }
    var fill: u8 = ' ';
    var al: u8 = 0;
    var i: usize = 0;
    if (spec.len >= 2 and Interp.isAlign(spec[1])) {
        fill = spec[0];
        al = spec[1];
        i = 2;
    } else if (spec.len >= 1 and Interp.isAlign(spec[0])) {
        al = spec[0];
        i = 1;
    }
    var comma = false;
    if (i < spec.len and spec[i] == ',') {
        comma = true;
        i += 1;
    }
    var kind: u8 = 0;
    if (i < spec.len and (spec[i] == 'i' or spec[i] == 'f' or spec[i] == 's')) {
        kind = spec[i];
        i += 1;
    }
    var j = i;
    while (j < spec.len and std.ascii.isDigit(spec[j])) j += 1;
    const width = std.fmt.parseInt(usize, spec[i..j], 10) catch 0;
    var prec: ?usize = null;
    if (j < spec.len and spec[j] == '.') prec = std.fmt.parseInt(usize, spec[j + 1 ..], 10) catch 0;

    const numeric = Interp.realOf(v) != null;
    var body: []const u8 = undefined;
    if (numeric and kind == 'f') {
        body = try it.fixed(Interp.realOf(v).?, prec orelse 6);
    } else if (numeric and Interp.isInt(v) and comma) {
        const digits = try std.fmt.allocPrint(it.t, "{d}", .{Interp.intOf(v)});
        const neg = digits[0] == '-';
        const ds = if (neg) digits[1..] else digits;
        if (neg) try buf.append(it.t, '-');
        for (ds, 0..) |c, k| {
            if (k > 0 and (ds.len - k) % 3 == 0) try buf.append(it.t, ',');
            try buf.append(it.t, c);
        }
        body = buf.items;
    } else {
        body = try it.text(v);
        if (prec) |p| if (!numeric) {
            var k: usize = 0;
            var cps: usize = 0;
            while (k < body.len and cps < p) : (cps += 1) k += std.unicode.utf8ByteSequenceLength(body[k]) catch 1;
            body = body[0..@min(k, body.len)];
        };
    }
    const shown = std.unicode.utf8CountCodepoints(body) catch body.len;
    if (shown >= width) return body;
    const pad = width - shown;
    const side: u8 = if (al != 0) al else if (numeric) '>' else '<';
    var out: std.ArrayList(u8) = .empty;
    const left: usize = switch (side) {
        '>' => pad,
        '^' => pad / 2,
        else => 0,
    };
    try out.appendNTimes(it.t, fill, left);
    try out.appendSlice(it.t, body);
    try out.appendNTimes(it.t, fill, pad - left);
    return out.items;
}

// Zig tip: a format string must be known while compiling, so a precision that is only known
// when the script runs cannot be written `{d:.*}`. `inline for` repeats its body once per
// value of the range, each time with a compile-time `p`, so `"{d:." ++ digit ++ "}"` is built
// by the compiler for p = 0, 1, 2, ... and the run-time `prec` picks the right copy.
/// A Real with `prec` decimals.
pub fn fixed(it: *Interp, x: f64, prec: usize) Signal![]const u8 {
    inline for (0..10) |p| {
        if (prec == p) return std.fmt.allocPrint(it.t, "{d:." ++ std.fmt.comptimePrint("{d}", .{p}) ++ "}", .{x});
    }
    return std.fmt.allocPrint(it.t, "{d:.9}", .{x});
}

// Zig tip: `interpolate` relies on the same Zig feature as `define` above: see the tip there.
pub fn interpolate(it: *Interp, n: *const Node) Signal!Value {
    var buf: std.ArrayList(u8) = .empty;
    for (n.kids) |part| {
        if (part.tag == .str) {
            try buf.appendSlice(it.t, part.text);
        } else {
            const v = try it.eval(part.kids[0]);
            try buf.appendSlice(it.t, try it.format(part.text[0], part.text[1..], v));
        }
    }
    return .{ .str = try it.persist(buf.items) };
}
