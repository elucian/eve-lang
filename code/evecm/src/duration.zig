//! @eve-module duration: the length of time behind the type Duration (`30s`, `PT1H30M`)
//! @spec spec/library/time.md#the-types
//! @feature F-LNG-13
//! @decision D-221
//! @tests test/level5/e120_duration_literal, test/level5/e121_duration_arithmetic
//! A Duration is a signed count of microseconds in an i64 (about 292,000 years each way). Every operation is checked: null means overflow.
const std = @import("std");
const Io = std.Io;

pub const us_per_ms: i64 = 1000;
pub const us_per_s: i64 = 1_000_000;
pub const us_per_min: i64 = 60 * us_per_s;
pub const us_per_h: i64 = 60 * us_per_min;

/// The value of a duration literal: digits and a unit (`us`, `ms`, `s`, `m`, `h`), as the lexer reads them. Null when `lit` is not one or does not fit.
pub fn parseLiteral(lit: []const u8) ?i64 {
    if (lit.len < 2 or !std.ascii.isDigit(lit[0])) return null;
    const units = [_]struct { []const u8, i64 }{ .{ "us", 1 }, .{ "ms", us_per_ms }, .{ "s", us_per_s }, .{ "m", us_per_min }, .{ "h", us_per_h } };
    for (units) |u| {
        if (!std.mem.endsWith(u8, lit, u[0])) continue;
        const digits = lit[0 .. lit.len - u[0].len];
        for (digits) |c| if (!std.ascii.isDigit(c)) return null;
        const v = std.fmt.parseInt(i64, digits, 10) catch return null;
        return std.math.mul(i64, v, u[1]) catch null;
    }
    return null;
}

/// Read the text of a duration: the ISO 8601 form (`PT1H30M`, `PT0.25S`, `-PT5S`, `P1DT2H`) or the short form of the literals with several units (`1h30m`, `90m`, `250ms`, `1m30s`, `-5s`).
pub fn parse(text_in: []const u8) ?i64 {
    var text = std.mem.trim(u8, text_in, " ");
    var negative = false;
    if (text.len > 0 and (text[0] == '-' or text[0] == '+')) {
        negative = text[0] == '-';
        text = text[1..];
    }
    if (text.len == 0) return null;
    var total: i64 = 0;
    if (text[0] == 'P' or text[0] == 'p') {
        // ISO: P[nD]T[nH][nM][n[.f]S]; years and months have no fixed length and are refused
        var i: usize = 1;
        var in_time = false;
        var any = false;
        while (i < text.len) {
            if (text[i] == 'T' or text[i] == 't') {
                in_time = true;
                i += 1;
                continue;
            }
            var j = i;
            while (j < text.len and (std.ascii.isDigit(text[j]) or text[j] == '.')) j += 1;
            if (j == i or j >= text.len) return null;
            const unit = std.ascii.toUpper(text[j]);
            const part = text[i..j];
            const us: i64 = switch (unit) {
                'D' => if (in_time) return null else (std.math.mul(i64, std.fmt.parseInt(i64, part, 10) catch return null, 24 * us_per_h) catch return null),
                'H' => if (!in_time) return null else (std.math.mul(i64, std.fmt.parseInt(i64, part, 10) catch return null, us_per_h) catch return null),
                'M' => if (!in_time) return null else (std.math.mul(i64, std.fmt.parseInt(i64, part, 10) catch return null, us_per_min) catch return null),
                'S' => if (!in_time) return null else (secondsToUs(part) orelse return null),
                else => return null,
            };
            total = std.math.add(i64, total, us) catch return null;
            any = true;
            i = j + 1;
        }
        if (!any) return null;
    } else {
        // short: a run of number and unit, `1h30m`
        var i: usize = 0;
        while (i < text.len) {
            var j = i;
            while (j < text.len and std.ascii.isDigit(text[j])) j += 1;
            if (j == i) return null;
            var k = j;
            while (k < text.len and std.ascii.isAlphabetic(text[k])) k += 1;
            const us = parseLiteral(text[i..k]) orelse return null;
            total = std.math.add(i64, total, us) catch return null;
            i = k;
        }
    }
    return if (negative) std.math.negate(total) catch null else total;
}

/// `1.5` seconds to microseconds, exactly (up to six decimals; more digits are refused).
fn secondsToUs(part: []const u8) ?i64 {
    const dot = std.mem.indexOfScalar(u8, part, '.');
    const whole = std.fmt.parseInt(i64, if (dot) |d| part[0..d] else part, 10) catch return null;
    var frac: i64 = 0;
    if (dot) |d| {
        const f = part[d + 1 ..];
        if (f.len == 0 or f.len > 6) return null;
        frac = std.fmt.parseInt(i64, f, 10) catch return null;
        var k = f.len;
        while (k < 6) : (k += 1) frac *= 10;
    }
    return std.math.add(i64, std.math.mul(i64, whole, us_per_s) catch return null, frac) catch null;
}

/// The canonical text, ISO 8601: `PT1H30M`, `PT0.25S`, `PT0S`, `-PT5S`. Days are not used (a day is not always 24 hours): `PT100H`.
pub fn write(w: *Io.Writer, us_in: i64) Io.Writer.Error!void {
    if (us_in == 0) return w.writeAll("PT0S");
    const negative = us_in < 0;
    var us: u64 = if (negative) @as(u64, @intCast(-@as(i128, us_in))) else @intCast(us_in);
    if (negative) try w.writeByte('-');
    try w.writeAll("PT");
    const h = us / @as(u64, @intCast(us_per_h));
    us %= @as(u64, @intCast(us_per_h));
    const m = us / @as(u64, @intCast(us_per_min));
    us %= @as(u64, @intCast(us_per_min));
    if (h > 0) try w.print("{d}H", .{h});
    if (m > 0) try w.print("{d}M", .{m});
    if (us > 0) {
        const s = us / @as(u64, @intCast(us_per_s));
        const f = us % @as(u64, @intCast(us_per_s));
        if (f == 0) {
            try w.print("{d}S", .{s});
        } else {
            var buf: [6]u8 = undefined;
            _ = std.fmt.bufPrint(&buf, "{d:0>6}", .{f}) catch unreachable;
            var n: usize = 6;
            while (n > 0 and buf[n - 1] == '0') n -= 1;
            try w.print("{d}.{s}S", .{ s, buf[0..n] });
        }
    }
}

test "spec: time.md#the-types literals and units" {
    const t = std.testing;
    try t.expectEqual(@as(?i64, 30_000_000), parseLiteral("30s"));
    try t.expectEqual(@as(?i64, 250_000), parseLiteral("250ms"));
    try t.expectEqual(@as(?i64, 5), parseLiteral("5us"));
    try t.expectEqual(@as(?i64, 7_200_000_000), parseLiteral("2h"));
    try t.expectEqual(@as(?i64, 120_000_000), parseLiteral("2m"));
    try t.expectEqual(@as(?i64, null), parseLiteral("42"));
    try t.expectEqual(@as(?i64, null), parseLiteral("5d"));
    try t.expectEqual(@as(?i64, null), parseLiteral("9223372036854775807h"));
}

test "spec: time.md#the-module-time parse of the ISO and short forms" {
    const t = std.testing;
    try t.expectEqual(@as(?i64, 5_400_000_000), parse("PT1H30M"));
    try t.expectEqual(@as(?i64, 5_400_000_000), parse("1h30m"));
    try t.expectEqual(@as(?i64, 5_400_000_000), parse("90m"));
    try t.expectEqual(@as(?i64, 250_000), parse("PT0.25S"));
    try t.expectEqual(@as(?i64, -5_000_000), parse("-PT5S"));
    try t.expectEqual(@as(?i64, -5_000_000), parse("-5s"));
    try t.expectEqual(@as(?i64, 93_600_000_000), parse("P1DT2H"));
    try t.expectEqual(@as(?i64, null), parse("P1Y"));
    try t.expectEqual(@as(?i64, null), parse("PT"));
    try t.expectEqual(@as(?i64, null), parse("1x"));
    try t.expectEqual(@as(?i64, null), parse(""));
    try t.expectEqual(@as(?i64, null), parse("PT1.1234567S"));
}

test "spec: time.md#the-types canonical text" {
    var aw: Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    const cases = [_]i64{ 0, 5_400_000_000, 250_000, 1_500_000, -5_000_000, 360_000_000_000, 61_000_001, 1 };
    for (cases) |c| {
        try write(&aw.writer, c);
        try aw.writer.writeAll("|");
    }
    try std.testing.expectEqualStrings("PT0S|PT1H30M|PT0.25S|PT1.5S|-PT5S|PT100H|PT1M1.000001S|PT0.000001S|", aw.written());
    // text and parse agree
    for (cases) |c| {
        aw.clearRetainingCapacity();
        try write(&aw.writer, c);
        try std.testing.expectEqual(@as(?i64, c), parse(aw.written()));
    }
}
