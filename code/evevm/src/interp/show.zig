//! @eve-module interp.show
//! @spec spec/syntax/expressions.md, spec/semantics/data-types.md#canonical-form-and-round-trip
//! @feature F-LNG-08
//! @tests test/level1
//! The text of a value: `show`, `text`, and the formats of the interpolation (`{x:...}`).
//! Part of the interpreter (interp.zig): every function takes the interpreter as `it: *Interp`, and
//! `Interp` names each of them again, so a call reads `it.name(...)` wherever it is made.
const std = @import("std");
const Io = std.Io;
const interp = @import("../interp.zig");
const timelib = @import("../timelib.zig");
const metalib = @import("../metalib.zig");
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

pub fn utf8(it: *Interp, buf: *std.ArrayList(u8), cp: u21) Signal!void {
    var tmp: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(cp, &tmp) catch 1;
    try buf.appendSlice(it.t, tmp[0..n]);
}

/// Append formatted text to `buf`, which grows in `mem`.
pub fn appendFmt(buf: *std.ArrayList(u8), mem: std.mem.Allocator, comptime fmt: []const u8, args: anytype) Signal!void {
    try buf.print(mem, fmt, args);
}

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
        .zone => |id| {
            var nb: [8]u8 = undefined;
            try buf.appendSlice(it.t, metalib.zoneName(id, &nb));
        },
        .dtm => |d| {
            var aw: Io.Writer.Allocating = .init(it.t);
            timelib.writeDateTime(&aw.writer, try timelib.dtmParts(it, d)) catch return error.OutOfMemory;
            try buf.appendSlice(it.t, aw.written());
        },
        .date => |days| {
            var aw: Io.Writer.Allocating = .init(it.t);
            interp.calendar.writeDate(&aw.writer, days) catch return error.OutOfMemory;
            try buf.appendSlice(it.t, aw.written());
        },
        .time => |us| {
            var aw: Io.Writer.Allocating = .init(it.t);
            interp.calendar.writeTime(&aw.writer, us) catch return error.OutOfMemory;
            try buf.appendSlice(it.t, aw.written());
        },
        .dur => |us| {
            var aw: Io.Writer.Allocating = .init(it.t);
            interp.duration.write(&aw.writer, us) catch return error.OutOfMemory;
            try buf.appendSlice(it.t, aw.written());
        },
        .cpx => |z| {
            var aw: Io.Writer.Allocating = .init(it.t);
            interp.complex.write(&aw.writer, z) catch return error.OutOfMemory;
            try buf.appendSlice(it.t, aw.written());
        },
        .rat => |q| {
            var aw: Io.Writer.Allocating = .init(it.t);
            interp.rational.write(&aw.writer, q) catch return error.OutOfMemory;
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
        .uuid => |u| {
            var aw: Io.Writer.Allocating = .init(it.t);
            interp.uuid_text.write(&aw.writer, u) catch return error.OutOfMemory;
            try buf.appendSlice(it.t, aw.written());
        },
        .bytes => |b| {
            var aw: Io.Writer.Allocating = .init(it.t);
            interp.bytes_text.writePrint(&aw.writer, b) catch return error.OutOfMemory;
            try buf.appendSlice(it.t, aw.written());
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

pub fn text(it: *Interp, v: Value) Signal![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    try it.show(&buf, v, false);
    return buf.items;
}

/// Keep `bytes` beyond the current statement: the string of a value.
pub fn persist(it: *Interp, bytes: []const u8) Signal![]const u8 {
    return it.h.str(bytes);
}

/// The persistent string `x ++ y`, built without an intermediate copy.
pub fn persist2(it: *Interp, x: []const u8, y: []const u8) Signal![]const u8 {
    return it.h.str2(x, y);
}

// ---- formats of the interpolation -----------------------------------------------------

pub fn isAlign(c: u8) bool {
    return c == '<' or c == '>' or c == '^';
}

/// Apply the format `spec` (the text after the `:`) of `\s{}`, `\#{}` or `\b{}` to `v`.
pub fn format(it: *Interp, letter: u8, spec: []const u8, v: Value) Signal![]const u8 {
    // a Date, a Time or an Instant: the text after `%` is a pattern, `{d % yyyy-MM-dd}` (spec/library/time.md#patterns)
    if ((v == .date or v == .time or v == .instant or v == .dtm) and spec.len > 0) return timelib.formatText(it, v, spec);
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

/// A Real with `prec` decimals.
pub fn fixed(it: *Interp, x: f64, prec: usize) Signal![]const u8 {
    inline for (0..10) |p| {
        if (prec == p) return std.fmt.allocPrint(it.t, "{d:." ++ std.fmt.comptimePrint("{d}", .{p}) ++ "}", .{x});
    }
    return std.fmt.allocPrint(it.t, "{d:.9}", .{x});
}

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
