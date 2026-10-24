//! @eve-module calendar: the proleptic Gregorian calendar behind the types Date and Time
//! @spec spec/library/time.md#the-types
//! @feature F-LNG-13
//! @decision D-221
//! @tests test/level5/e123_date_basics, test/level5/e124_date_arithmetic, test/level5/e125_date_table
//! A Date is an i32 count of days since 1970-01-01 (year 1 to 9999); a Time is an i64 count of microseconds since midnight. Pure functions, no allocation.
const std = @import("std");
const Io = std.Io;

pub const min_year: i32 = 1;
pub const max_year: i32 = 9999;
/// 0001-01-01 and 9999-12-31 as day counts.
pub const min_days: i32 = -719162;
pub const max_days: i32 = 2932896;
pub const us_per_day: i64 = 86_400_000_000;

pub const Civil = struct { year: i32, month: u8, day: u8 };

pub fn isLeap(y: i32) bool {
    return (@mod(y, 4) == 0 and @mod(y, 100) != 0) or @mod(y, 400) == 0;
}

pub fn daysInMonth(y: i32, m: u8) u8 {
    return switch (m) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        else => if (isLeap(y)) 29 else 28,
    };
}

/// The day count of a civil date (Howard Hinnant's days_from_civil); the caller checked the fields.
pub fn daysFromCivil(y_in: i32, m: u8, d: u8) i32 {
    const y: i32 = if (m <= 2) y_in - 1 else y_in;
    const era = @divFloor(y, 400);
    const yoe: i32 = y - era * 400;
    const mp: i32 = @mod(@as(i32, m) + 9, 12);
    const doy: i32 = @divFloor(153 * mp + 2, 5) + @as(i32, d) - 1;
    const doe: i32 = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + doe - 719468;
}

/// The civil date of a day count (Hinnant's civil_from_days).
pub fn civilFromDays(z_in: i32) Civil {
    const z: i32 = z_in + 719468;
    const era = @divFloor(z, 146097);
    const doe: i32 = z - era * 146097;
    const yoe: i32 = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const y: i32 = yoe + era * 400;
    const doy: i32 = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp: i32 = @divFloor(5 * doy + 2, 153);
    const d: i32 = doy - @divFloor(153 * mp + 2, 5) + 1;
    const m: i32 = if (mp < 10) mp + 3 else mp - 9;
    return .{ .year = if (m <= 2) y + 1 else y, .month = @intCast(m), .day = @intCast(d) };
}

/// The day count of a valid date, or null when a field is outside its range or the day does not exist in the month.
pub fn make(y: i64, m: i64, d: i64) ?i32 {
    if (y < min_year or y > max_year or m < 1 or m > 12 or d < 1) return null;
    const yy: i32 = @intCast(y);
    const mm: u8 = @intCast(m);
    if (d > daysInMonth(yy, mm)) return null;
    return daysFromCivil(yy, mm, @intCast(d));
}

/// 1 for Monday to 7 for Sunday (ISO). 1970-01-01 was a Thursday.
pub fn weekday(days: i32) u8 {
    return @intCast(@mod(days + 3, 7) + 1);
}

pub fn dayOfYear(days: i32) u16 {
    const c = civilFromDays(days);
    return @intCast(days - daysFromCivil(c.year, 1, 1) + 1);
}

fn p(y: i32) i32 {
    return @mod(y + @divFloor(y, 4) - @divFloor(y, 100) + @divFloor(y, 400), 7);
}

/// The number of ISO weeks of a year, 52 or 53.
pub fn weeksInYear(y: i32) u8 {
    return if (p(y) == 4 or p(y - 1) == 3) 53 else 52;
}

pub const IsoWeek = struct { year: i32, week: u8 };

pub fn isoWeek(days: i32) IsoWeek {
    const c = civilFromDays(days);
    const w: i32 = @divFloor(@as(i32, dayOfYear(days)) - weekday(days) + 10, 7);
    if (w < 1) return .{ .year = c.year - 1, .week = weeksInYear(c.year - 1) };
    if (w > weeksInYear(c.year)) return .{ .year = c.year + 1, .week = 1 };
    return .{ .year = c.year, .week = @intCast(w) };
}

/// The date `n` months after `days` (before for a negative `n`); the day is kept or cut to the end of the month. Null outside year 1 to 9999.
pub fn addMonths(days: i32, n: i64) ?i32 {
    const c = civilFromDays(days);
    const total: i64 = @as(i64, c.year) * 12 + (c.month - 1) + n;
    const y = @divFloor(total, 12);
    if (y < min_year or y > max_year) return null;
    const m: u8 = @intCast(@mod(total, 12) + 1);
    const yy: i32 = @intCast(y);
    return daysFromCivil(yy, m, @min(c.day, daysInMonth(yy, m)));
}

/// Whole months from `a` to `b`: the number m with addMonths(a, m) <= b < addMonths(a, m + 1) for b >= a, and the negative of the count from b to a otherwise.
pub fn monthsBetween(a: i32, b: i32) i64 {
    if (b < a) return -monthsBetween(b, a);
    const ca = civilFromDays(a);
    const cb = civilFromDays(b);
    var m: i64 = (@as(i64, cb.year) - ca.year) * 12 + (@as(i64, cb.month) - ca.month);
    if (m > 0 and (addMonths(a, m) orelse std.math.maxInt(i32)) > b) m -= 1;
    return m;
}

pub const Unit = enum { year, quarter, month, week, day, hour, minute, second };

pub fn unitOf(name: []const u8) ?Unit {
    return std.meta.stringToEnum(Unit, name);
}

/// The first day of the unit that holds `days`: year, quarter, month, week (Monday) or the day itself.
pub fn startOfDate(days: i32, unit: Unit) ?i32 {
    const c = civilFromDays(days);
    return switch (unit) {
        .year => daysFromCivil(c.year, 1, 1),
        .quarter => daysFromCivil(c.year, @intCast(@divFloor(@as(i32, c.month) - 1, 3) * 3 + 1), 1),
        .month => daysFromCivil(c.year, c.month, 1),
        .week => days - (weekday(days) - 1),
        .day => days,
        .hour, .minute, .second => null,
    };
}

/// A Time cut to the start of an hour, minute or second (`day` is midnight).
pub fn startOfTime(us: i64, unit: Unit) ?i64 {
    return switch (unit) {
        .day => 0,
        .hour => @divFloor(us, 3_600_000_000) * 3_600_000_000,
        .minute => @divFloor(us, 60_000_000) * 60_000_000,
        .second => @divFloor(us, 1_000_000) * 1_000_000,
        else => null,
    };
}

/// A Time from its fields, or null when one is out of range.
pub fn makeTime(h: i64, m: i64, s: i64, micro: i64) ?i64 {
    if (h < 0 or h > 23 or m < 0 or m > 59 or s < 0 or s > 59 or micro < 0 or micro > 999_999) return null;
    return ((h * 60 + m) * 60 + s) * 1_000_000 + micro;
}

/// `2026-10-24`.
pub fn writeDate(w: *Io.Writer, days: i32) Io.Writer.Error!void {
    const c = civilFromDays(days);
    try w.print("{d:0>4}-{d:0>2}-{d:0>2}", .{ @as(u32, @intCast(c.year)), c.month, c.day });
}

/// `08:30:00`, `08:30:00.5`, `08:30:00.000123`: the fraction in microseconds with the trailing zeros cut.
pub fn writeTime(w: *Io.Writer, us: i64) Io.Writer.Error!void {
    const total_s = @divFloor(us, 1_000_000);
    const frac = @mod(us, 1_000_000);
    try w.print("{d:0>2}:{d:0>2}:{d:0>2}", .{ @as(u32, @intCast(@divFloor(total_s, 3600))), @as(u32, @intCast(@mod(@divFloor(total_s, 60), 60))), @as(u32, @intCast(@mod(total_s, 60))) });
    if (frac != 0) {
        var buf: [6]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "{d:0>6}", .{@as(u32, @intCast(frac))}) catch unreachable;
        var n: usize = 6;
        while (n > 0 and buf[n - 1] == '0') n -= 1;
        try w.print(".{s}", .{buf[0..n]});
    }
}

fn digits(text: []const u8, from: usize, count: usize) ?i64 {
    if (from + count > text.len) return null;
    var v: i64 = 0;
    for (text[from .. from + count]) |c| {
        if (c < '0' or c > '9') return null;
        v = v * 10 + (c - '0');
    }
    return v;
}

/// Read `YYYY-MM-DD` (four digits for the year); null for anything else or a date that does not exist.
pub fn parseDate(text: []const u8) ?i32 {
    if (text.len != 10 or text[4] != '-' or text[7] != '-') return null;
    return make(digits(text, 0, 4) orelse return null, digits(text, 5, 2) orelse return null, digits(text, 8, 2) orelse return null);
}

/// Read `HH:MM`, `HH:MM:SS` or `HH:MM:SS.f` with one to six digits of fraction; null for anything else.
pub fn parseTime(text: []const u8) ?i64 {
    if (text.len < 5 or text[2] != ':') return null;
    const h = digits(text, 0, 2) orelse return null;
    const mi = digits(text, 3, 2) orelse return null;
    if (text.len == 5) return makeTime(h, mi, 0, 0);
    if (text.len < 8 or text[5] != ':') return null;
    const s = digits(text, 6, 2) orelse return null;
    if (text.len == 8) return makeTime(h, mi, s, 0);
    if (text[8] != '.' or text.len < 10 or text.len > 15) return null;
    const f = digits(text, 9, text.len - 9) orelse return null;
    var micro = f;
    var k = text.len - 9;
    while (k < 6) : (k += 1) micro *= 10;
    return makeTime(h, mi, s, micro);
}

test "spec: time.md#the-types the day count and the civil date agree over the whole range" {
    var d: i32 = min_days;
    while (d <= max_days) : (d += 1) {
        const c = civilFromDays(d);
        try std.testing.expectEqual(d, daysFromCivil(c.year, c.month, c.day));
        try std.testing.expect(c.day >= 1 and c.day <= daysInMonth(c.year, c.month));
    }
    try std.testing.expectEqual(@as(i32, 1), civilFromDays(min_days).year);
    try std.testing.expectEqual(@as(i32, 9999), civilFromDays(max_days).year);
}

test "spec: time.md#the-types known dates" {
    const t = std.testing;
    try t.expectEqual(@as(?i32, 0), make(1970, 1, 1));
    try t.expectEqual(@as(?i32, min_days), make(1, 1, 1));
    try t.expectEqual(@as(?i32, max_days), make(9999, 12, 31));
    try t.expectEqual(@as(?i32, 11016), make(2000, 2, 29));
    try t.expectEqual(@as(?i32, null), make(1900, 2, 29));
    try t.expectEqual(@as(?i32, null), make(2026, 2, 30));
    try t.expectEqual(@as(?i32, null), make(2026, 13, 1));
    try t.expectEqual(@as(?i32, null), make(0, 1, 1));
    try t.expectEqual(@as(?i32, null), make(10000, 1, 1));
    try t.expect(isLeap(2000) and isLeap(2024) and !isLeap(1900) and !isLeap(2100));
}

test "spec: time.md#the-module-time weekdays, day of year, ISO weeks" {
    const t = std.testing;
    try t.expectEqual(@as(u8, 4), weekday(0)); // Thursday
    try t.expectEqual(@as(u8, 6), weekday(make(2026, 10, 24).?)); // Saturday
    try t.expectEqual(@as(u16, 366), dayOfYear(make(2024, 12, 31).?));
    try t.expectEqual(@as(u16, 1), dayOfYear(make(2026, 1, 1).?));
    const w1 = isoWeek(make(2021, 1, 3).?); // Sunday: week 53 of 2020
    try t.expectEqual(@as(i32, 2020), w1.year);
    try t.expectEqual(@as(u8, 53), w1.week);
    const w2 = isoWeek(make(2024, 12, 30).?); // Monday: week 1 of 2025
    try t.expectEqual(@as(i32, 2025), w2.year);
    try t.expectEqual(@as(u8, 1), w2.week);
    const w3 = isoWeek(make(2026, 10, 24).?);
    try t.expectEqual(@as(u8, 43), w3.week);
    try t.expectEqual(@as(u8, 53), weeksInYear(2020));
    try t.expectEqual(@as(u8, 52), weeksInYear(2021));
}

test "spec: time.md#the-module-time months" {
    const t = std.testing;
    try t.expectEqual(make(2026, 2, 28), addMonths(make(2026, 1, 31).?, 1));
    try t.expectEqual(make(2028, 2, 29), addMonths(make(2028, 1, 31).?, 1));
    try t.expectEqual(make(2025, 12, 31), addMonths(make(2026, 1, 31).?, -1));
    try t.expectEqual(make(2027, 1, 15), addMonths(make(2026, 1, 15).?, 12));
    try t.expectEqual(@as(?i32, null), addMonths(make(9999, 12, 1).?, 1));
    try t.expectEqual(@as(i64, 1), monthsBetween(make(2026, 1, 31).?, make(2026, 2, 28).?));
    try t.expectEqual(@as(i64, 0), monthsBetween(make(2026, 1, 15).?, make(2026, 2, 14).?));
    try t.expectEqual(@as(i64, 1), monthsBetween(make(2026, 1, 15).?, make(2026, 2, 15).?));
    try t.expectEqual(@as(i64, -1), monthsBetween(make(2026, 2, 28).?, make(2026, 1, 31).?));
    try t.expectEqual(@as(i64, 24), monthsBetween(make(2024, 3, 1).?, make(2026, 3, 1).?));
}

test "spec: time.md#the-module-time start_of" {
    const t = std.testing;
    const d = make(2026, 10, 24).?;
    try t.expectEqual(make(2026, 1, 1), startOfDate(d, .year));
    try t.expectEqual(make(2026, 10, 1), startOfDate(d, .quarter));
    try t.expectEqual(make(2026, 10, 1), startOfDate(d, .month));
    try t.expectEqual(make(2026, 10, 19), startOfDate(d, .week));
    try t.expectEqual(@as(?i32, d), startOfDate(d, .day));
    try t.expectEqual(@as(?i64, 8 * 3_600_000_000), startOfTime(8 * 3_600_000_000 + 1_234_567_890, .hour));
}

test "spec: time.md#the-types text of a Date and a Time" {
    const t = std.testing;
    var aw: Io.Writer.Allocating = .init(t.allocator);
    defer aw.deinit();
    try writeDate(&aw.writer, make(2026, 10, 24).?);
    try aw.writer.writeAll("|");
    try writeDate(&aw.writer, min_days);
    try aw.writer.writeAll("|");
    try writeTime(&aw.writer, makeTime(8, 30, 0, 0).?);
    try aw.writer.writeAll("|");
    try writeTime(&aw.writer, makeTime(8, 30, 0, 500_000).?);
    try aw.writer.writeAll("|");
    try writeTime(&aw.writer, makeTime(23, 59, 59, 123).?);
    try t.expectEqualStrings("2026-10-24|0001-01-01|08:30:00|08:30:00.5|23:59:59.000123", aw.written());
    try t.expectEqual(make(2026, 10, 24), parseDate("2026-10-24"));
    try t.expectEqual(@as(?i32, null), parseDate("2026-1-24"));
    try t.expectEqual(@as(?i32, null), parseDate("2026-02-30"));
    try t.expectEqual(@as(?i32, null), parseDate("20261024"));
    try t.expectEqual(makeTime(8, 30, 0, 0), parseTime("08:30"));
    try t.expectEqual(makeTime(8, 30, 5, 250_000), parseTime("08:30:05.25"));
    try t.expectEqual(makeTime(23, 59, 59, 999_999), parseTime("23:59:59.999999"));
    try t.expectEqual(@as(?i64, null), parseTime("24:00:00"));
    try t.expectEqual(@as(?i64, null), parseTime("08:30:00.1234567"));
    try t.expectEqual(@as(?i64, null), parseTime("8:30"));
}
