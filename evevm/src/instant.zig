//! `Instant`: a point in time in UTC, kept as microseconds since 1970-01-01T00:00:00Z
//! (spec/library/data-language.md#time-types). The canonical text is ISO 8601 with a `Z`, with no fraction
//! when the fraction is zero (spec/semantics/data-types.md#canonical-form-and-round-trip).
const std = @import("std");
const Io = std.Io;

const us_per_second: i64 = 1_000_000;
const seconds_per_day: i64 = 86_400;

// Zig tip: these are the "civil from days" and "days from civil" algorithms of Howard Hinnant: they turn a day
// count since 1970-01-01 into a year, month and day (and back) with integer arithmetic only, with no table and
// no loop, for any date of the proleptic Gregorian calendar. `@divFloor` divides and rounds toward minus
// infinity, so dates before 1970 work too.
fn daysFromCivil(y_in: i64, m: i64, d: i64) i64 {
    const y = if (m <= 2) y_in - 1 else y_in;
    const era = @divFloor(y, 400);
    const yoe = y - era * 400;
    const mp = @mod(m + 9, 12);
    const doy = @divFloor(153 * mp + 2, 5) + d - 1;
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + doe - 719468;
}

fn civilFromDays(z_in: i64) struct { y: i64, m: i64, d: i64 } {
    const z = z_in + 719468;
    const era = @divFloor(z, 146097);
    const doe = z - era * 146097;
    const yoe = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const doy = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp = @divFloor(5 * doy + 2, 153);
    const d = doy - @divFloor(153 * mp + 2, 5) + 1;
    const m = if (mp < 10) mp + 3 else mp - 9;
    const y = yoe + era * 400 + (if (m <= 2) @as(i64, 1) else 0);
    return .{ .y = y, .m = m, .d = d };
}

fn digits(text: []const u8, from: usize, n: usize) ?i64 {
    if (from + n > text.len) return null;
    var v: i64 = 0;
    for (text[from .. from + n]) |ch| {
        if (!std.ascii.isDigit(ch)) return null;
        v = v * 10 + (ch - '0');
    }
    return v;
}

fn leap(y: i64) bool {
    return (@mod(y, 4) == 0 and @mod(y, 100) != 0) or @mod(y, 400) == 0;
}

fn daysIn(y: i64, m: i64) i64 {
    return switch (m) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        else => if (leap(y)) 29 else 28,
    };
}

// Zig tip: a parser that reads fixed-width fields (`YYYY-MM-DDTHH:MM:SS`) by position is a few `digits` calls
// and character tests; each `orelse return null` leaves with "not an instant". The fraction is optional,
// 1 to 6 digits; a longer one is refused so no digit is lost silently.
/// Read `2026-10-10T08:00:00Z` (with an optional fraction `.5`, `.123456`). Null if the text is not an instant.
pub fn parse(text: []const u8) ?i64 {
    if (text.len < 20 or text[text.len - 1] != 'Z') return null;
    const y = digits(text, 0, 4) orelse return null;
    const mo = digits(text, 5, 2) orelse return null;
    const d = digits(text, 8, 2) orelse return null;
    const h = digits(text, 11, 2) orelse return null;
    const mi = digits(text, 14, 2) orelse return null;
    const s = digits(text, 17, 2) orelse return null;
    if (text[4] != '-' or text[7] != '-' or text[10] != 'T' or text[13] != ':' or text[16] != ':') return null;
    if (mo < 1 or mo > 12 or d < 1 or d > daysIn(y, mo) or h > 23 or mi > 59 or s > 59) return null;
    var frac: i64 = 0;
    if (text.len > 20) {
        if (text[19] != '.') return null;
        const f = text[20 .. text.len - 1];
        if (f.len == 0 or f.len > 6) return null;
        var scale: i64 = us_per_second;
        for (f) |ch| {
            if (!std.ascii.isDigit(ch)) return null;
            scale = @divExact(scale, 10);
            frac += (ch - '0') * scale;
        }
    }
    const days = daysFromCivil(y, mo, d);
    return ((days * seconds_per_day) + h * 3600 + mi * 60 + s) * us_per_second + frac;
}

/// Write the canonical text: `2026-10-10T08:00:00Z`, with a fraction (trailing zeros cut) only when it is not zero.
pub fn write(w: *Io.Writer, us: i64) Io.Writer.Error!void {
    const secs = @divFloor(us, us_per_second);
    const frac = @mod(us, us_per_second);
    const days = @divFloor(secs, seconds_per_day);
    const sod = @mod(secs, seconds_per_day);
    const c = civilFromDays(days);
    // Zig tip: with a width, `{d}` on a signed integer prints a `+`; the fields are never negative here, so each
    // one is turned into an unsigned integer first (`@intCast` checks that it fits).
    const f: [6]u32 = .{ @intCast(c.y), @intCast(c.m), @intCast(c.d), @intCast(@divFloor(sod, 3600)), @intCast(@divFloor(@mod(sod, 3600), 60)), @intCast(@mod(sod, 60)) };
    try w.print("{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}", .{ f[0], f[1], f[2], f[3], f[4], f[5] });
    if (frac != 0) {
        var buf: [6]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "{d:0>6}", .{@as(u32, @intCast(frac))}) catch unreachable; // unsigned: a signed {d} may print a sign
        try w.writeByte('.');
        try w.writeAll(std.mem.trimEnd(u8, &buf, "0"));
    }
    try w.writeByte('Z');
}

test "an instant parses and prints in the canonical form" {
    var buf: [200]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try write(&w, 0);
    try w.writeByte(' ');
    try write(&w, parse("2026-10-10T08:00:00Z").?);
    try w.writeByte(' ');
    try write(&w, parse("2026-10-10T08:00:00.500Z").?);
    try w.writeByte(' ');
    try write(&w, parse("1969-12-31T23:59:59Z").?);
    try w.writeByte(' ');
    try write(&w, parse("2024-02-29T00:00:00.000001Z").?);
    try std.testing.expectEqualStrings("1970-01-01T00:00:00Z 2026-10-10T08:00:00Z 2026-10-10T08:00:00.5Z 1969-12-31T23:59:59Z 2024-02-29T00:00:00.000001Z", w.buffered());
    try std.testing.expectEqual(@as(i64, 0), parse("1970-01-01T00:00:00Z").?);
}

test "a text that is not an instant is refused" {
    try std.testing.expect(parse("yesterday") == null);
    try std.testing.expect(parse("2026-13-10T08:00:00Z") == null);
    try std.testing.expect(parse("2023-02-29T00:00:00Z") == null);
    try std.testing.expect(parse("2026-10-10T08:00:00") == null);
    try std.testing.expect(parse("2026-10-10T08:00:00.1234567Z") == null);
}
