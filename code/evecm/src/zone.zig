//! @eve-module zone: the offset of a time zone at an instant, from the transitions of the meta database and the POSIX rule of the future
//! @spec spec/library/meta.md#zone
//! @feature F-LIB-06
//! @decision D-222
//! @tests test/level5/e129_meta_zone, test/level5/e130_meta_zone_table
//! A Zone holds the types and the transitions of one zone (as TZif files do) and the rule that applies after the last transition (`EET-2EEST,M3.5.0/3,M10.5.0/4`). Pure functions on slices; the loader is in code/evevm/src/metalib.zig.
const std = @import("std");
const cal = @import("calendar.zig");

pub const Type = struct { utoff: i32, isdst: bool, abbr: []const u8 };

/// How a rule names the day of a change.
pub const RuleDay = union(enum) {
    /// `Mm.w.d`: month 1 to 12, week 1 to 5 (5 is the last), weekday 0 (Sunday) to 6
    month: struct { m: u8, w: u8, d: u8 },
    /// `Jn`: day 1 to 365, 29 February is never counted
    julian1: u16,
    /// `n`: day 0 to 365, 29 February is counted
    julian0: u16,
};

pub const Change = struct { day: RuleDay, secs: i32 = 7200 };

pub const Rule = struct {
    std_abbr: []const u8,
    std_off: i32,
    dst: ?struct { abbr: []const u8, off: i32, start: Change, end: Change } = null,
};

pub const Zone = struct {
    types: []const Type,
    at: []const i64,
    idx: []const u8,
    rule: ?Rule = null,
};

pub const Local = struct { utoff: i32, isdst: bool, abbr: []const u8 };

const Cursor = struct {
    s: []const u8,
    i: usize = 0,
    fn peek(c: *Cursor) ?u8 {
        return if (c.i < c.s.len) c.s[c.i] else null;
    }
};

fn parseName(c: *Cursor) ?[]const u8 {
    if (c.peek() == '<') {
        const close = std.mem.indexOfScalarPos(u8, c.s, c.i, '>') orelse return null;
        const name = c.s[c.i + 1 .. close];
        c.i = close + 1;
        return if (name.len >= 3) name else null;
    }
    const start = c.i;
    while (c.peek()) |ch| {
        if (!std.ascii.isAlphabetic(ch)) break;
        c.i += 1;
    }
    return if (c.i - start >= 3) c.s[start..c.i] else null;
}

fn parseNum(c: *Cursor) ?i32 {
    const start = c.i;
    var v: i32 = 0;
    while (c.peek()) |ch| {
        if (!std.ascii.isDigit(ch)) break;
        v = std.math.add(i32, std.math.mul(i32, v, 10) catch return null, ch - '0') catch return null;
        c.i += 1;
    }
    return if (c.i > start) v else null;
}

/// `[+-]hh[:mm[:ss]]` in seconds.
fn parseTime(c: *Cursor) ?i32 {
    var sign: i32 = 1;
    if (c.peek() == '-') {
        sign = -1;
        c.i += 1;
    } else if (c.peek() == '+') c.i += 1;
    var secs = (parseNum(c) orelse return null) * 3600;
    if (c.peek() == ':') {
        c.i += 1;
        secs += (parseNum(c) orelse return null) * 60;
        if (c.peek() == ':') {
            c.i += 1;
            secs += parseNum(c) orelse return null;
        }
    }
    return sign * secs;
}

fn parseChange(c: *Cursor) ?Change {
    var day: RuleDay = undefined;
    if (c.peek() == 'M') {
        c.i += 1;
        const m = parseNum(c) orelse return null;
        if (c.peek() != '.') return null;
        c.i += 1;
        const w = parseNum(c) orelse return null;
        if (c.peek() != '.') return null;
        c.i += 1;
        const d = parseNum(c) orelse return null;
        if (m < 1 or m > 12 or w < 1 or w > 5 or d > 6) return null;
        day = .{ .month = .{ .m = @intCast(m), .w = @intCast(w), .d = @intCast(d) } };
    } else if (c.peek() == 'J') {
        c.i += 1;
        const n = parseNum(c) orelse return null;
        if (n < 1 or n > 365) return null;
        day = .{ .julian1 = @intCast(n) };
    } else {
        const n = parseNum(c) orelse return null;
        if (n > 365) return null;
        day = .{ .julian0 = @intCast(n) };
    }
    var secs: i32 = 7200;
    if (c.peek() == '/') {
        c.i += 1;
        secs = parseTime(c) orelse return null;
    }
    return .{ .day = day, .secs = secs };
}

/// Read a POSIX TZ string (as in the footer of a TZif file); null when it is empty or malformed. The names point into `text`.
pub fn parseRule(text: []const u8) ?Rule {
    var c: Cursor = .{ .s = text };
    const std_abbr = parseName(&c) orelse return null;
    const std_off = -(parseTime(&c) orelse return null);
    if (c.peek() == null) return .{ .std_abbr = std_abbr, .std_off = std_off };
    const dst_abbr = parseName(&c) orelse return null;
    var dst_off = std_off + 3600;
    if (c.peek()) |ch| if (ch != ',') {
        dst_off = -(parseTime(&c) orelse return null);
    };
    if (c.peek() != ',') return null;
    c.i += 1;
    const start = parseChange(&c) orelse return null;
    if (c.peek() != ',') return null;
    c.i += 1;
    const end = parseChange(&c) orelse return null;
    if (c.peek() != null) return null;
    return .{ .std_abbr = std_abbr, .std_off = std_off, .dst = .{ .abbr = dst_abbr, .off = dst_off, .start = start, .end = end } };
}

/// The day number (days since 1970-01-01) a rule names in a year.
fn dayOf(rd: RuleDay, y: i32) i64 {
    const jan1: i64 = cal.daysFromCivil(y, 1, 1);
    switch (rd) {
        .julian1 => |n| return jan1 + n - 1 + (if (cal.isLeap(y) and n >= 60) @as(i64, 1) else 0),
        .julian0 => |n| return jan1 + n,
        .month => |mw| {
            const first: i64 = cal.daysFromCivil(y, mw.m, 1);
            // weekday of the first: 0 Sunday to 6 Saturday (cal.weekday: 1 Monday to 7 Sunday)
            const wd_first: i64 = @mod(@as(i64, cal.weekday(@intCast(first))), 7);
            var day = first + @mod(@as(i64, mw.d) - wd_first, 7) + 7 * (@as(i64, mw.w) - 1);
            const dim: i64 = cal.daysInMonth(y, mw.m);
            while (day >= first + dim) day -= 7;
            return day;
        },
    }
}

/// The local time at the UTC instant `t` (seconds since the epoch) by a rule.
pub fn ruleAt(r: Rule, t: i64) Local {
    const d = r.dst orelse return .{ .utoff = r.std_off, .isdst = false, .abbr = r.std_abbr };
    const local_days = @divFloor(t + r.std_off, 86400);
    const y: i32 = cal.civilFromDays(@intCast(std.math.clamp(local_days, cal.min_days, cal.max_days))).year;
    const s = dayOf(d.start.day, y) * 86400 + d.start.secs - r.std_off;
    const e = dayOf(d.end.day, y) * 86400 + d.end.secs - d.off;
    const in_dst = if (s < e) (t >= s and t < e) else (t >= s or t < e);
    return if (in_dst) .{ .utoff = d.off, .isdst = true, .abbr = d.abbr } else .{ .utoff = r.std_off, .isdst = false, .abbr = r.std_abbr };
}

/// The local time of a zone at the UTC instant `t`.
// @perf hot
pub fn lookup(z: *const Zone, t: i64) Local {
    const n = z.at.len;
    if (n == 0 or t < z.at[0]) {
        if (n == 0) if (z.rule) |r| return ruleAt(r, t);
        const ty = z.types[0];
        return .{ .utoff = ty.utoff, .isdst = ty.isdst, .abbr = ty.abbr };
    }
    if (t >= z.at[n - 1]) if (z.rule) |r| return ruleAt(r, t);
    // the last transition at or before t
    var lo: usize = 0;
    var hi: usize = n;
    while (hi - lo > 1) {
        const mid = lo + (hi - lo) / 2;
        if (z.at[mid] <= t) lo = mid else hi = mid;
    }
    const ty = z.types[z.idx[lo]];
    return .{ .utoff = ty.utoff, .isdst = ty.isdst, .abbr = ty.abbr };
}

/// The instants that a local wall-clock time (seconds since 1970-01-01T00:00:00 local) can have in a zone.
pub const Resolve = union(enum) {
    /// exactly one instant
    one: i64,
    /// the clock showed this time twice (summer time ends): the first and the second instant
    two: struct { first: i64, second: i64 },
    /// the clock never showed this time (summer time starts): the offsets before and after the jump
    gap: struct { before: i32, after: i32 },
};

// @eve-impl local time to instants: try the offsets in force a day before and a day after; an offset is right when the zone has that offset at the instant it gives
// @spec spec/library/time.md#zones
/// Resolve a local time in a zone.
pub fn resolveLocal(z: *const Zone, local: i64) Resolve {
    const before = lookup(z, local - 86400).utoff;
    const after = lookup(z, local + 86400).utoff;
    const t1 = local - before;
    const ok1 = lookup(z, t1).utoff == before;
    if (before == after) {
        if (ok1) return .{ .one = t1 };
        // a change inside the day that returns to the same offset: look at the offset in force at the guess
        const mid = lookup(z, t1).utoff;
        const t3 = local - mid;
        if (lookup(z, t3).utoff == mid) return .{ .one = t3 };
        return .{ .gap = .{ .before = before, .after = mid } };
    }
    const t2 = local - after;
    const ok2 = lookup(z, t2).utoff == after;
    if (ok1 and ok2) return if (t1 <= t2) .{ .two = .{ .first = t1, .second = t2 } } else .{ .two = .{ .first = t2, .second = t1 } };
    if (ok1) return .{ .one = t1 };
    if (ok2) return .{ .one = t2 };
    return .{ .gap = .{ .before = before, .after = after } };
}

test "spec: meta.md#zone POSIX rules" {
    const t = std.testing;
    const ny = parseRule("EST5EDT,M3.2.0,M11.1.0").?;
    try t.expectEqual(@as(i32, -18000), ny.std_off);
    try t.expectEqual(@as(i32, -14400), ny.dst.?.off);
    try t.expectEqual(@as(i32, 7200), ny.dst.?.start.secs);
    const ro = parseRule("EET-2EEST,M3.5.0/3,M10.5.0/4").?;
    try t.expectEqual(@as(i32, 7200), ro.std_off);
    try t.expectEqual(@as(i32, 10800), ro.dst.?.off);
    const ind = parseRule("IST-5:30").?;
    try t.expectEqual(@as(i32, 19800), ind.std_off);
    try t.expect(ind.dst == null);
    const ir = parseRule("<+0330>-3:30").?;
    try t.expectEqualStrings("+0330", ir.std_abbr);
    const gl = parseRule("<-02>2<-01>,M3.5.0/-1,M10.5.0/0").?;
    try t.expectEqual(@as(i32, -3600), gl.dst.?.start.secs);
    const dub = parseRule("IST-1GMT0,M10.5.0,M3.5.0/1").?;
    try t.expectEqual(@as(i32, 0), dub.dst.?.off);
    try t.expect(parseRule("") == null);
    try t.expect(parseRule("EST5EDT,M13.2.0,M11.1.0") == null);
    try t.expect(parseRule("EST") == null);
}

test "spec: meta.md#zone a rule at instants (New York, Bucharest, Sydney, Dublin)" {
    const t = std.testing;
    const ny = parseRule("EST5EDT,M3.2.0,M11.1.0").?;
    // 2026-03-08 06:59:59Z is still EST, 07:00:00Z is EDT; 2026-11-01 05:59:59Z is EDT, 06:00:00Z is EST
    const mar = @as(i64, cal.make(2026, 3, 8).?) * 86400;
    try t.expectEqual(@as(i32, -18000), ruleAt(ny, mar + 7 * 3600 - 1).utoff);
    try t.expectEqual(@as(i32, -14400), ruleAt(ny, mar + 7 * 3600).utoff);
    const nov = @as(i64, cal.make(2026, 11, 1).?) * 86400;
    try t.expectEqual(@as(i32, -14400), ruleAt(ny, nov + 6 * 3600 - 1).utoff);
    try t.expectEqual(@as(i32, -18000), ruleAt(ny, nov + 6 * 3600).utoff);
    const ro = parseRule("EET-2EEST,M3.5.0/3,M10.5.0/4").?;
    const ro_mar = @as(i64, cal.make(2026, 3, 29).?) * 86400; // last Sunday of March
    try t.expectEqual(@as(i32, 7200), ruleAt(ro, ro_mar + 1 * 3600 - 1).utoff);
    try t.expectEqual(@as(i32, 10800), ruleAt(ro, ro_mar + 1 * 3600).utoff);
    const sy = parseRule("AEST-10AEDT,M10.1.0,M4.1.0/3").?;
    try t.expectEqual(@as(i32, 39600), ruleAt(sy, @as(i64, cal.make(2026, 1, 15).?) * 86400).utoff); // January is summer
    try t.expectEqual(@as(i32, 36000), ruleAt(sy, @as(i64, cal.make(2026, 7, 15).?) * 86400).utoff);
    const dub = parseRule("IST-1GMT0,M10.5.0,M3.5.0/1").?;
    try t.expectEqual(@as(i32, 3600), ruleAt(dub, @as(i64, cal.make(2026, 7, 15).?) * 86400).utoff);
    try t.expectEqual(@as(i32, 0), ruleAt(dub, @as(i64, cal.make(2026, 12, 15).?) * 86400).utoff);
    try t.expect(ruleAt(dub, @as(i64, cal.make(2026, 12, 15).?) * 86400).isdst);
}

test "spec: meta.md#zone lookup in the transitions, then the rule" {
    const t = std.testing;
    const types = [_]Type{ .{ .utoff = 5000, .isdst = false, .abbr = "LMT" }, .{ .utoff = 7200, .isdst = false, .abbr = "EET" }, .{ .utoff = 10800, .isdst = true, .abbr = "EEST" } };
    const at = [_]i64{ 1000, 2000, 3000 };
    const idx = [_]u8{ 1, 2, 1 };
    const z: Zone = .{ .types = &types, .at = &at, .idx = &idx, .rule = parseRule("EET-2EEST,M3.5.0/3,M10.5.0/4") };
    try t.expectEqualStrings("LMT", lookup(&z, 999).abbr);
    try t.expectEqualStrings("EET", lookup(&z, 1000).abbr);
    try t.expectEqualStrings("EEST", lookup(&z, 2500).abbr);
    try t.expectEqualStrings("EEST", lookup(&z, 2999).abbr);
    try t.expectEqualStrings("EET", lookup(&z, 3000).abbr); // from the last transition on the rule decides: January 1970 is winter
    // after the last transition the rule decides: July is summer time
    try t.expectEqualStrings("EEST", lookup(&z, @as(i64, cal.make(2040, 7, 1).?) * 86400).abbr);
    const none: Zone = .{ .types = types[1..2], .at = &.{}, .idx = &.{} };
    try t.expectEqual(@as(i32, 7200), lookup(&none, 123456789).utoff);
}

test "spec: time.md#zones local time to instants: one, two or none" {
    const t = std.testing;
    const types = [_]Type{ .{ .utoff = 3600, .isdst = false, .abbr = "CET" }, .{ .utoff = 7200, .isdst = true, .abbr = "CEST" } };
    // summer time from 1000 s to 100000 s, then back
    const at = [_]i64{ 1000, 100000 };
    const idx = [_]u8{ 1, 0 };
    const z: Zone = .{ .types = &types, .at = &at, .idx = &idx };
    // well before: one instant; inside: one
    try t.expectEqual(Resolve{ .one = 100 - 3600 }, resolveLocal(&z, 100));
    try t.expectEqual(Resolve{ .one = 50000 - 7200 }, resolveLocal(&z, 50000));
    // the jump forward at 1000 s: the local times 1000+3600 to 1000+7200 do not exist
    switch (resolveLocal(&z, 1000 + 3600 + 100)) {
        .gap => |g| {
            try t.expectEqual(@as(i32, 3600), g.before);
            try t.expectEqual(@as(i32, 7200), g.after);
        },
        else => return error.TestUnexpectedResult,
    }
    // the jump back at 100000 s: the local times from 100000+3600 to 100000+7200 happen twice
    switch (resolveLocal(&z, 100000 + 3600 + 100)) {
        .two => |p| {
            try t.expectEqual(@as(i64, 100000 + 3600 + 100 - 7200), p.first);
            try t.expectEqual(@as(i64, 100000 + 3600 + 100 - 3600), p.second);
        },
        else => return error.TestUnexpectedResult,
    }
}
