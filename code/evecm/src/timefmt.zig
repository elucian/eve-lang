//! @eve-module timefmt: the patterns of time.format and time.parse (`yyyy-MM-dd HH:mm:ss`)
//! @spec spec/library/time.md#patterns
//! @feature F-LIB-06
//! @decision D-221
//! @tests test/level5/e127_time_patterns, test/level5/e128_time_pattern_table
//! The letters of Unicode CLDR and Java, the ones a database or a spreadsheet user knows. A pattern is compiled to at most `max_tokens` tokens; formatting and parsing walk the tokens. No allocation.
const std = @import("std");
const Io = std.Io;
const cal = @import("calendar.zig");

pub const max_tokens = 48;

pub const Kind = enum { literal, year, month, day, doy, weekday, hour24, hour12, minute, second, fraction, ampm, isoweek, quarter, offset, zone_id, zone_abbr };

pub const Token = struct { kind: Kind, n: u8 = 1, text: []const u8 = "" };

pub const PatternError = struct { pos: usize, msg: []const u8 };

pub const months_long = [_][]const u8{ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };
pub const days_long = [_][]const u8{ "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" };

fn kindOf(c: u8) ?Kind {
    return switch (c) {
        'y' => .year,
        'M' => .month,
        'd' => .day,
        'D' => .doy,
        'E' => .weekday,
        'H' => .hour24,
        'h' => .hour12,
        'm' => .minute,
        's' => .second,
        'S' => .fraction,
        'a' => .ampm,
        'w' => .isoweek,
        'Q' => .quarter,
        'X' => .offset,
        'V' => .zone_id,
        'z' => .zone_abbr,
        else => null,
    };
}

/// Compile a pattern. Letters are fields, `'text'` is text (`''` is a quote), any other character stands for itself. Returns the number of tokens.
pub fn compile(pattern: []const u8, out: *[max_tokens]Token, err: *PatternError) error{BadPattern}!usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < pattern.len) {
        if (n >= max_tokens) {
            err.* = .{ .pos = i, .msg = "the pattern is too long" };
            return error.BadPattern;
        }
        const c = pattern[i];
        if (c == '\'') {
            if (i + 1 < pattern.len and pattern[i + 1] == '\'') {
                out[n] = .{ .kind = .literal, .text = "'" };
                n += 1;
                i += 2;
                continue;
            }
            // quoted text; a doubled quote inside it is a quote character: 'it''s' is it's
            var from = i + 1;
            while (true) {
                const close = std.mem.indexOfScalarPos(u8, pattern, from, '\'') orelse {
                    err.* = .{ .pos = i, .msg = "a quote is not closed" };
                    return error.BadPattern;
                };
                if (n + 2 >= max_tokens) {
                    err.* = .{ .pos = i, .msg = "the pattern is too long" };
                    return error.BadPattern;
                }
                if (close > from) {
                    out[n] = .{ .kind = .literal, .text = pattern[from..close] };
                    n += 1;
                }
                if (close + 1 < pattern.len and pattern[close + 1] == '\'') {
                    out[n] = .{ .kind = .literal, .text = "'" };
                    n += 1;
                    from = close + 2;
                    continue;
                }
                i = close + 1;
                break;
            }
            continue;
        }
        if (std.ascii.isAlphabetic(c)) {
            const k = kindOf(c) orelse {
                err.* = .{ .pos = i, .msg = "unknown letter (the letters are y M d D E H h m s S a w Q X V z; text goes in quotes)" };
                return error.BadPattern;
            };
            var j = i;
            while (j < pattern.len and pattern[j] == c) j += 1;
            const count = j - i;
            const max: usize = switch (k) {
                .year => 9,
                .month => 4,
                .weekday => 4,
                .fraction => 9,
                .doy => 3,
                .offset => 3,
                .zone_id => 2,
                .zone_abbr => 3,
                .ampm => 1,
                .quarter => 2,
                else => 2,
            };
            if (count > max) {
                err.* = .{ .pos = i, .msg = "too many repeated letters" };
                return error.BadPattern;
            }
            out[n] = .{ .kind = k, .n = @intCast(count) };
            n += 1;
            i = j;
            continue;
        }
        // a run of other characters is one text token
        var j = i;
        while (j < pattern.len and !std.ascii.isAlphabetic(pattern[j]) and pattern[j] != '\'') j += 1;
        out[n] = .{ .kind = .literal, .text = pattern[i..j] };
        n += 1;
        i = j;
    }
    return n;
}

/// What a value holds for formatting: a Date has `has_date`, a Time `has_time`, an Instant both and a zone (UTC).
pub const Fields = struct {
    days: i32 = 0,
    us_of_day: i64 = 0,
    has_date: bool = false,
    has_time: bool = false,
    has_zone: bool = false,
    /// the offset from UTC in seconds when there is a zone (an Instant is UTC: 0)
    utoff: i32 = 0,
    /// the name of the zone (`Europe/Bucharest`, `+03:00`) and its abbreviation; empty for an Instant
    zone_name: []const u8 = "",
    abbr: []const u8 = "",
};

pub const FormatError = error{ NeedsDate, NeedsTime, NeedsZone };

fn pad(w: *Io.Writer, v: u64, width: usize) Io.Writer.Error!void {
    var buf: [20]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d}", .{v}) catch unreachable;
    var k = s.len;
    while (k < width) : (k += 1) try w.writeByte('0');
    try w.writeAll(s);
}

pub fn format(w: *Io.Writer, tokens: []const Token, f: Fields) (FormatError || Io.Writer.Error)!void {
    const c = cal.civilFromDays(f.days);
    const us = f.us_of_day;
    const hour: u64 = @intCast(@divFloor(us, 3_600_000_000));
    const minute: u64 = @intCast(@mod(@divFloor(us, 60_000_000), 60));
    const second: u64 = @intCast(@mod(@divFloor(us, 1_000_000), 60));
    const micro: u64 = @intCast(@mod(us, 1_000_000));
    for (tokens) |t| {
        switch (t.kind) {
            .literal => try w.writeAll(t.text),
            .year, .month, .day, .doy, .weekday, .isoweek, .quarter => {
                if (!f.has_date) return error.NeedsDate;
                switch (t.kind) {
                    .year => {
                        const y: u64 = @intCast(c.year);
                        if (t.n == 2) try pad(w, y % 100, 2) else try pad(w, y, t.n);
                    },
                    .month => if (t.n >= 4) try w.writeAll(months_long[c.month - 1]) else if (t.n == 3) try w.writeAll(months_long[c.month - 1][0..3]) else try pad(w, c.month, t.n),
                    .day => try pad(w, c.day, t.n),
                    .doy => try pad(w, cal.dayOfYear(f.days), t.n),
                    .weekday => {
                        const name = days_long[cal.weekday(f.days) - 1];
                        try w.writeAll(if (t.n >= 4) name else name[0..3]);
                    },
                    .isoweek => try pad(w, cal.isoWeek(f.days).week, t.n),
                    else => try pad(w, (c.month - 1) / 3 + 1, t.n),
                }
            },
            .hour24, .hour12, .minute, .second, .fraction, .ampm => {
                if (!f.has_time) return error.NeedsTime;
                switch (t.kind) {
                    .hour24 => try pad(w, hour, t.n),
                    .hour12 => try pad(w, if (hour % 12 == 0) 12 else hour % 12, t.n),
                    .minute => try pad(w, minute, t.n),
                    .second => try pad(w, second, t.n),
                    .ampm => try w.writeAll(if (hour < 12) "AM" else "PM"),
                    else => {
                        // the first n digits of the fraction, zeros after the sixth
                        var digits: [9]u8 = @splat('0');
                        _ = std.fmt.bufPrint(digits[0..6], "{d:0>6}", .{@as(u32, @intCast(micro))}) catch unreachable;
                        try w.writeAll(digits[0..t.n]);
                    },
                }
            },
            .offset => {
                if (!f.has_zone) return error.NeedsZone;
                if (f.utoff == 0) {
                    try w.writeAll("Z");
                } else {
                    const a: u32 = @abs(f.utoff);
                    try w.writeByte(if (f.utoff < 0) '-' else '+');
                    try pad(w, a / 3600, 2);
                    if (t.n >= 2 or a % 3600 != 0) {
                        if (t.n >= 3) try w.writeByte(':');
                        try pad(w, a % 3600 / 60, 2);
                    }
                }
            },
            .zone_id => {
                if (f.zone_name.len == 0) return error.NeedsZone;
                try w.writeAll(f.zone_name);
            },
            .zone_abbr => {
                if (f.abbr.len == 0) return error.NeedsZone;
                try w.writeAll(f.abbr);
            },
        }
    }
}

pub const Parsed = struct {
    year: ?i32 = null,
    month: ?u8 = null,
    day: ?u8 = null,
    doy: ?u16 = null,
    weekday: ?u8 = null,
    hour24: ?u8 = null,
    hour12: ?u8 = null,
    pm: ?bool = null,
    minute: ?u8 = null,
    second: ?u8 = null,
    micro: ?u32 = null,
    offset_min: ?i32 = null,
    zone_name: ?[]const u8 = null,
    has_abbr: bool = false,
    has_isoweek: bool = false,
    has_quarter: bool = false,
};

pub const ParseError = struct { pos: usize, msg: []const u8 };

fn readNumber(text: []const u8, pos: *usize, n: u8, err: *ParseError) error{BadText}!u64 {
    // two or more letters: exactly that many digits; one letter: one or two digits (a year: up to four)
    const exact = n >= 2;
    const max: usize = if (exact) n else 2;
    var j = pos.*;
    var v: u64 = 0;
    while (j < text.len and j - pos.* < max and std.ascii.isDigit(text[j])) : (j += 1) v = v * 10 + (text[j] - '0');
    const got = j - pos.*;
    if (got == 0 or (exact and got != n)) {
        err.* = .{ .pos = pos.*, .msg = "a number is expected here" };
        return error.BadText;
    }
    pos.* = j;
    return v;
}

fn readName(text: []const u8, pos: *usize, names: []const []const u8, long: bool, err: *ParseError) error{BadText}!usize {
    for (names, 0..) |name, idx| {
        const want = if (long) name else name[0..3];
        if (pos.* + want.len <= text.len and std.ascii.eqlIgnoreCase(text[pos.* .. pos.* + want.len], want)) {
            pos.* += want.len;
            return idx;
        }
    }
    err.* = .{ .pos = pos.*, .msg = "a name of a month or of a weekday (in English) is expected here" };
    return error.BadText;
}

/// Read `text` by the tokens. The text must be used completely.
pub fn parse(text: []const u8, tokens: []const Token, out: *Parsed, err: *ParseError) error{BadText}!void {
    var pos: usize = 0;
    for (tokens) |t| {
        switch (t.kind) {
            .literal => {
                if (pos + t.text.len > text.len or !std.mem.eql(u8, text[pos .. pos + t.text.len], t.text)) {
                    err.* = .{ .pos = pos, .msg = "the text does not match the text of the pattern" };
                    return error.BadText;
                }
                pos += t.text.len;
            },
            .year => {
                if (t.n == 2) {
                    const v = try readNumber(text, &pos, 2, err);
                    out.year = @intCast(if (v >= 70) 1900 + v else 2000 + v);
                } else if (t.n >= 3) {
                    const v = try readNumber(text, &pos, t.n, err);
                    out.year = @intCast(v);
                } else {
                    var j = pos;
                    var v: u64 = 0;
                    while (j < text.len and j - pos < 4 and std.ascii.isDigit(text[j])) : (j += 1) v = v * 10 + (text[j] - '0');
                    if (j == pos) {
                        err.* = .{ .pos = pos, .msg = "a year is expected here" };
                        return error.BadText;
                    }
                    pos = j;
                    out.year = @intCast(v);
                }
            },
            .month => {
                if (t.n >= 3) {
                    out.month = @intCast(try readName(text, &pos, &months_long, t.n >= 4, err) + 1);
                } else out.month = @intCast(try readNumber(text, &pos, t.n, err));
            },
            .day => out.day = @intCast(try readNumber(text, &pos, t.n, err)),
            .doy => {
                var j = pos;
                var v: u64 = 0;
                while (j < text.len and j - pos < 3 and std.ascii.isDigit(text[j])) : (j += 1) v = v * 10 + (text[j] - '0');
                if (j == pos or (t.n == 3 and j - pos != 3)) {
                    err.* = .{ .pos = pos, .msg = "a day of the year is expected here" };
                    return error.BadText;
                }
                pos = j;
                out.doy = @intCast(v);
            },
            .weekday => out.weekday = @intCast(try readName(text, &pos, &days_long, t.n >= 4, err) + 1),
            .hour24 => out.hour24 = @intCast(try readNumber(text, &pos, t.n, err)),
            .hour12 => out.hour12 = @intCast(try readNumber(text, &pos, t.n, err)),
            .minute => out.minute = @intCast(try readNumber(text, &pos, t.n, err)),
            .second => out.second = @intCast(try readNumber(text, &pos, t.n, err)),
            .ampm => {
                if (pos + 2 <= text.len and std.ascii.eqlIgnoreCase(text[pos .. pos + 2], "AM")) {
                    out.pm = false;
                } else if (pos + 2 <= text.len and std.ascii.eqlIgnoreCase(text[pos .. pos + 2], "PM")) {
                    out.pm = true;
                } else {
                    err.* = .{ .pos = pos, .msg = "AM or PM is expected here" };
                    return error.BadText;
                }
                pos += 2;
            },
            .fraction => {
                if (t.n > 6) {
                    err.* = .{ .pos = pos, .msg = "a fraction has at most 6 digits when it is read" };
                    return error.BadText;
                }
                if (pos + t.n > text.len) {
                    err.* = .{ .pos = pos, .msg = "digits of a fraction are expected here" };
                    return error.BadText;
                }
                var v: u32 = 0;
                for (text[pos .. pos + t.n]) |ch| {
                    if (!std.ascii.isDigit(ch)) {
                        err.* = .{ .pos = pos, .msg = "digits of a fraction are expected here" };
                        return error.BadText;
                    }
                    v = v * 10 + (ch - '0');
                }
                var k: usize = t.n;
                while (k < 6) : (k += 1) v *= 10;
                out.micro = v;
                pos += t.n;
            },
            .isoweek => {
                _ = try readNumber(text, &pos, t.n, err);
                out.has_isoweek = true;
            },
            .quarter => {
                _ = try readNumber(text, &pos, t.n, err);
                out.has_quarter = true;
            },
            .zone_id => {
                var j = pos;
                while (j < text.len and (std.ascii.isAlphanumeric(text[j]) or text[j] == '_' or text[j] == '/' or text[j] == '+' or text[j] == '-')) j += 1;
                if (j == pos) {
                    err.* = .{ .pos = pos, .msg = "the name of a zone is expected here" };
                    return error.BadText;
                }
                out.zone_name = text[pos..j];
                pos = j;
            },
            .zone_abbr => {
                out.has_abbr = true;
                var j = pos;
                while (j < text.len and (std.ascii.isAlphabetic(text[j]) or text[j] == '+' or text[j] == '-' or std.ascii.isDigit(text[j]))) j += 1;
                pos = j;
            },
            .offset => {
                if (pos < text.len and (text[pos] == 'Z' or text[pos] == 'z')) {
                    out.offset_min = 0;
                    pos += 1;
                } else if (pos < text.len and (text[pos] == '+' or text[pos] == '-')) {
                    const sign: i32 = if (text[pos] == '-') -1 else 1;
                    pos += 1;
                    const h = try readNumber(text, &pos, 2, err);
                    if (pos < text.len and text[pos] == ':') pos += 1;
                    var m: u64 = 0;
                    if (pos < text.len and std.ascii.isDigit(text[pos])) m = try readNumber(text, &pos, 2, err);
                    if (h > 18 or m > 59) {
                        err.* = .{ .pos = pos, .msg = "the offset is outside -18:00 to +18:00" };
                        return error.BadText;
                    }
                    out.offset_min = sign * @as(i32, @intCast(h * 60 + m));
                } else {
                    err.* = .{ .pos = pos, .msg = "Z or an offset such as +03:00 is expected here" };
                    return error.BadText;
                }
            },
        }
    }
    if (pos != text.len) {
        err.* = .{ .pos = pos, .msg = "the text is longer than the pattern" };
        return error.BadText;
    }
}

fn toks(pattern: []const u8, buf: *[max_tokens]Token) ![]const Token {
    var e: PatternError = undefined;
    const n = try compile(pattern, buf, &e);
    return buf[0..n];
}

test "spec: time.md#patterns format of a date, a time and an instant" {
    const t = std.testing;
    var buf: [max_tokens]Token = undefined;
    var aw: Io.Writer.Allocating = .init(t.allocator);
    defer aw.deinit();
    const d = cal.make(2026, 10, 24).?;
    const both: Fields = .{ .days = d, .us_of_day = 8 * 3_600_000_000 + 5 * 60_000_000 + 7 * 1_000_000 + 123_456, .has_date = true, .has_time = true, .has_zone = true };
    try format(&aw.writer, try toks("yyyy-MM-dd HH:mm:ss", &buf), both);
    try aw.writer.writeAll("|");
    try format(&aw.writer, try toks("EEE, d MMM yy", &buf), both);
    try aw.writer.writeAll("|");
    try format(&aw.writer, try toks("EEEE d MMMM yyyy 'at' h:mm a", &buf), both);
    try aw.writer.writeAll("|");
    try format(&aw.writer, try toks("HH:mm:ss.SSS XXX", &buf), both);
    try aw.writer.writeAll("|");
    try format(&aw.writer, try toks("D ww Q 'it''s'", &buf), both);
    try t.expectEqualStrings("2026-10-24 08:05:07|Sat, 24 Oct 26|Saturday 24 October 2026 at 8:05 AM|08:05:07.123 Z|297 43 4 it's", aw.written());
    var only_date: Fields = .{ .days = d, .has_date = true };
    aw.clearRetainingCapacity();
    try t.expectError(error.NeedsTime, format(&aw.writer, try toks("HH", &buf), only_date));
    only_date.has_zone = false;
    try t.expectError(error.NeedsZone, format(&aw.writer, try toks("XXX", &buf), .{ .days = d, .us_of_day = 0, .has_date = true, .has_time = true }));
    const only_time: Fields = .{ .us_of_day = 0, .has_time = true };
    try t.expectError(error.NeedsDate, format(&aw.writer, try toks("yyyy", &buf), only_time));
}

test "spec: time.md#patterns parse" {
    const t = std.testing;
    var buf: [max_tokens]Token = undefined;
    var p: Parsed = .{};
    var e: ParseError = undefined;
    try parse("2026-10-24 08:05:07.5", try toks("yyyy-MM-dd HH:mm:ss.S", &buf), &p, &e);
    try t.expectEqual(@as(?i32, 2026), p.year);
    try t.expectEqual(@as(?u8, 10), p.month);
    try t.expectEqual(@as(?u8, 24), p.day);
    try t.expectEqual(@as(?u8, 8), p.hour24);
    try t.expectEqual(@as(?u32, 500_000), p.micro);
    p = .{};
    try parse("20261024", try toks("yyyyMMdd", &buf), &p, &e);
    try t.expectEqual(@as(?u8, 24), p.day);
    p = .{};
    try parse("Sat, 24 oct 26", try toks("EEE, d MMM yy", &buf), &p, &e);
    try t.expectEqual(@as(?i32, 2026), p.year);
    try t.expectEqual(@as(?u8, 6), p.weekday);
    p = .{};
    try parse("2026-10-24T08:00:00+03:30", try toks("yyyy-MM-dd'T'HH:mm:ssXXX", &buf), &p, &e);
    try t.expectEqual(@as(?i32, 210), p.offset_min);
    p = .{};
    try parse("1 Jan 99", try toks("d MMM yy", &buf), &p, &e);
    try t.expectEqual(@as(?i32, 1999), p.year);
    p = .{};
    try t.expectError(error.BadText, parse("2026-1-24", try toks("yyyy-MM-dd", &buf), &p, &e));
    try t.expectEqual(@as(usize, 5), e.pos);
    p = .{};
    try t.expectError(error.BadText, parse("2026-10-24 extra", try toks("yyyy-MM-dd", &buf), &p, &e));
    try t.expectEqualStrings("the text is longer than the pattern", e.msg);
}

test "spec: time.md#patterns bad patterns" {
    const t = std.testing;
    var buf: [max_tokens]Token = undefined;
    var e: PatternError = undefined;
    try t.expectError(error.BadPattern, compile("yyyy-MM-dd Z", &buf, &e));
    try t.expectEqual(@as(usize, 11), e.pos);
    try t.expectError(error.BadPattern, compile("'open", &buf, &e));
    try t.expectError(error.BadPattern, compile("MMMMM", &buf, &e));
}

test "spec: time.md#patterns the offset and the zone letters of a DateTime" {
    const t = std.testing;
    var buf: [max_tokens]Token = undefined;
    var aw: Io.Writer.Allocating = .init(t.allocator);
    defer aw.deinit();
    const f: Fields = .{ .days = cal.make(2026, 7, 1).?, .us_of_day = 15 * 3_600_000_000, .has_date = true, .has_time = true, .has_zone = true, .utoff = 10800, .zone_name = "Europe/Bucharest", .abbr = "EEST" };
    try format(&aw.writer, try toks("HH:mm X|XX|XXX VV z", &buf), f);
    try t.expectEqualStrings("15:00 +03|+0300|+03:00 Europe/Bucharest EEST", aw.written());
    aw.clearRetainingCapacity();
    const g: Fields = .{ .days = 0, .us_of_day = 0, .has_date = true, .has_time = true, .has_zone = true, .utoff = -12600, .zone_name = "America/St_Johns", .abbr = "NST" };
    try format(&aw.writer, try toks("X XX XXX", &buf), g);
    try t.expectEqualStrings("-0330 -0330 -03:30", aw.written());
    var p: Parsed = .{};
    var e: ParseError = undefined;
    try parse("2026-07-01 15:00 Europe/Bucharest", try toks("yyyy-MM-dd HH:mm VV", &buf), &p, &e);
    try t.expectEqualStrings("Europe/Bucharest", p.zone_name.?);
}
