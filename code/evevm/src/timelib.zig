//! @eve-module timelib: native functions of the library module `time` (the clock, durations, dates and times of the day)
//! @spec spec/library/time.md#the-module-time
//! @feature F-LIB-06
//! @decision D-221
//! @tests test/level5/e122_time_module, test/level5/e123_date_basics, test/level5/e124_date_arithmetic, test/level5/e125_date_table
//! Handler of type `dlib.Native`, registered in `dlib.natives` as `time`. Signatures: lib/sys/time.eve. Zones, `DateTime` and patterns come in the next steps (design/design-data-types.md D2 and D3).
const std = @import("std");
const Io = std.Io;
const ast = @import("evecm").ast;
const cal = @import("evecm").calendar;
const tf = @import("evecm").timefmt;
const metalib = @import("metalib.zig");
const Dtm = @import("evecm").value.Dtm;
const builtin = @import("builtin");
const interp = @import("interp.zig");

const Node = ast.Node;
const Interp = interp.Interp;
const Value = interp.Value;
const Signal = interp.Signal;
const err_argument = interp.err_argument;
const err_overflow = interp.err_overflow;

const Fn = enum {
    @"now!", now, seconds, millis, micros, sleep,
    @"today!", date, clock, year, month, day, hour, minute, second, micro,
    weekday, day_of_year, iso_week, iso_year, add_months, add_years, start_of,
    end_of_month, days_in_month, is_leap, months_between, years_between,
    format, parse,
    zone, at_zone, make, date_of, time_of, instant_of, zone_of, offset_of, @"local_zone!",
};

fn zoneIdArg(it: *Interp, args: []const Value, i: usize, what: []const u8) Signal!u32 {
    if (args.len <= i) return it.failWith(err_argument, "time.{s}: argument {d} is missing", .{ what, i + 1 });
    switch (args[i]) {
        .zone => |z| return z,
        .str => |s| return (try metalib.zoneIdOf(it, s)) orelse it.failWith(err_argument, "time.{s}: '{s}' is not a time zone (a name such as Europe/Bucharest, Z, or an offset such as +03:00)", .{ what, s }),
        else => return it.failWith(err_argument, "time.{s}: argument {d} is a Zone or its name, found {s}", .{ what, i + 1, Interp.typeName(args[i]) }),
    }
}

fn instantUs(it: *Interp, args: []const Value, i: usize, what: []const u8) Signal!i64 {
    if (args.len <= i) return it.failWith(err_argument, "time.{s}: argument {d} is missing", .{ what, i + 1 });
    return switch (args[i]) {
        .instant => |us| us,
        .dtm => |d| d.us,
        else => it.failWith(err_argument, "time.{s}: argument {d} is an Instant or a DateTime, found {s}", .{ what, i + 1, Interp.typeName(args[i]) }),
    };
}

fn durationArg(it: *Interp, args: []const Value, i: usize, what: []const u8) Signal!i64 {
    if (args.len <= i) return it.failWith(err_argument, "time.{s}: argument {d} is missing", .{ what, i + 1 });
    if (args[i] != .dur) return it.failWith(err_argument, "time.{s}: argument {d} is a Duration, found {s}", .{ what, i + 1, Interp.typeName(args[i]) });
    return args[i].dur;
}

fn intArg(it: *Interp, args: []const Value, i: usize, what: []const u8) Signal!i64 {
    if (args.len <= i) return it.failWith(err_argument, "time.{s}: argument {d} is missing", .{ what, i + 1 });
    if (!Interp.isInt(args[i])) return it.failWith(err_argument, "time.{s}: argument {d} is a whole number, found {s}", .{ what, i + 1, Interp.typeName(args[i]) });
    return Interp.intOf(args[i]);
}

// ---- the zone of the machine ----------------------------------------------------------------

const CTm = if (builtin.os.tag == .windows)
    extern struct { sec: c_int, min: c_int, hour: c_int, mday: c_int, mon: c_int, year: c_int, wday: c_int, yday: c_int, isdst: c_int }
else
    extern struct { sec: c_int, min: c_int, hour: c_int, mday: c_int, mon: c_int, year: c_int, wday: c_int, yday: c_int, isdst: c_int, gmtoff: c_long, zone: ?[*:0]const u8 };

extern "c" fn localtime_r(t: *const i64, out: *CTm) ?*CTm;
extern "c" fn _localtime64_s(out: *CTm, t: *const i64) c_int;
extern "c" fn readlink(path: [*:0]const u8, buf: [*]u8, len: usize) isize;

/// The offset from UTC that the machine uses at the UTC second `t`, from the C library (summer time included); null when it cannot be asked.
fn machineOffsetAt(t_in: i64) ?i32 {
    var t = t_in;
    var tm: CTm = undefined;
    if (builtin.os.tag == .windows) {
        if (_localtime64_s(&tm, &t) != 0) return null;
    } else {
        if (localtime_r(&t, &tm) == null) return null;
    }
    const days = cal.make(@as(i64, tm.year) + 1900, @as(i64, tm.mon) + 1, tm.mday) orelse return null;
    const local = @as(i64, days) * 86400 + @as(i64, tm.hour) * 3600 + @as(i64, tm.min) * 60 + tm.sec;
    return std.math.cast(i32, local - t_in);
}

/// The name of a zone in the text of a link `/usr/share/zoneinfo/Europe/Bucharest` or `../usr/share/zoneinfo/Europe/Bucharest`, or in a TZ variable `:Europe/Bucharest`.
pub fn regionName(path: []const u8) ?[]const u8 {
    var p = path;
    if (p.len > 0 and p[0] == ':') p = p[1..];
    if (std.mem.indexOf(u8, p, "zoneinfo/")) |i| p = p[i + "zoneinfo/".len ..];
    if (p.len == 0 or p[0] == '/') return null;
    return p;
}

// @eve-impl the zone of the machine: the region named by TZ or by /etc/localtime when the database knows it, else the offset in force now as a fixed zone
// @spec spec/library/time.md#zones
fn localZone(it: *Interp) Signal!u32 {
    if (std.c.getenv("TZ")) |tz| {
        if (regionName(std.mem.span(tz))) |name| if (try metalib.zoneIdOf(it, name)) |id| return id;
    }
    if (builtin.os.tag != .windows) {
        var buf: [512]u8 = undefined;
        const n = readlink("/etc/localtime", &buf, buf.len);
        if (n > 0) {
            if (regionName(buf[0..@intCast(n)])) |name| if (try metalib.zoneIdOf(it, name)) |id| return id;
        }
    }
    const io = it.io orelse return 0;
    const now_s: i64 = @intCast(@divFloor(Io.Timestamp.now(io, .real).toNanoseconds(), 1_000_000_000));
    return metalib.fixedId(machineOffsetAt(now_s) orelse 0);
}

/// The wall-clock fields of a DateTime: its date, its time of the day and the offset in force.
pub const Parts = struct { days: i32, us_of_day: i64, utoff: i32 };

pub fn dtmParts(d: Dtm) Parts {
    const l = metalib.localAt(d.zone, @divFloor(d.us, 1_000_000));
    const loc = d.us + @as(i64, l.utoff) * 1_000_000;
    return .{ .days = @intCast(@divFloor(loc, cal.us_per_day)), .us_of_day = @mod(loc, cal.us_per_day), .utoff = l.utoff };
}

// @eve-impl a wall-clock time in a zone to an instant, for a result that must exist: a time the clock skips moves forward by the jump, a time it shows twice is the first
// @spec spec/library/time.md#zones
pub fn instantOfLocal(zone_id: u32, days: i32, us_of_day: i64) ?i64 {
    const sec = @as(i64, days) * 86400 + @divFloor(us_of_day, 1_000_000);
    const sub_us = @mod(us_of_day, 1_000_000);
    const t: i64 = switch (metalib.resolveLocal(zone_id, sec)) {
        .one => |x| x,
        .two => |p| p.first,
        .gap => |g| sec - g.before,
    };
    return std.math.add(i64, std.math.mul(i64, t, 1_000_000) catch return null, sub_us) catch null;
}

/// `2026-10-24T11:30:00+03:00`: the local date and time and the offset (`Z` for none; seconds are added for the old local mean times).
pub fn writeDateTime(w: *Io.Writer, d: Dtm) Io.Writer.Error!void {
    const p = dtmParts(d);
    try cal.writeDate(w, p.days);
    try w.writeByte('T');
    try cal.writeTime(w, p.us_of_day);
    try writeOffset(w, p.utoff, true);
}

/// An offset as `Z` or `+03:00` (`+03:00:30` when it has seconds and `seconds` is true).
pub fn writeOffset(w: *Io.Writer, utoff: i32, seconds: bool) Io.Writer.Error!void {
    if (utoff == 0) return w.writeByte('Z');
    const a: u32 = @abs(utoff);
    try w.print("{c}{d:0>2}:{d:0>2}", .{ @as(u8, if (utoff < 0) '-' else '+'), a / 3600, a % 3600 / 60 });
    if (seconds and a % 60 != 0) try w.print(":{d:0>2}", .{a % 60});
}

fn dateArg(it: *Interp, args: []const Value, i: usize, what: []const u8) Signal!i32 {
    if (args.len > i and args[i] == .dtm) return dtmParts(args[i].dtm).days;
    if (args.len <= i) return it.failWith(err_argument, "time.{s}: argument {d} is missing", .{ what, i + 1 });
    if (args[i] != .date) return it.failWith(err_argument, "time.{s}: argument {d} is a Date, found {s}", .{ what, i + 1, Interp.typeName(args[i]) });
    return args[i].date;
}

fn timeArg(it: *Interp, args: []const Value, i: usize, what: []const u8) Signal!i64 {
    if (args.len > i and args[i] == .dtm) return dtmParts(args[i].dtm).us_of_day;
    if (args.len <= i) return it.failWith(err_argument, "time.{s}: argument {d} is missing", .{ what, i + 1 });
    if (args[i] != .time) return it.failWith(err_argument, "time.{s}: argument {d} is a Time, found {s}", .{ what, i + 1, Interp.typeName(args[i]) });
    return args[i].time;
}

fn dateOrFail(it: *Interp, days: ?i32, what: []const u8) Signal!?Value {
    return .{ .date = days orelse return it.failWith(err_overflow, "time.{s}: the result is outside the years 1 to 9999", .{what}) };
}

fn patternFail(it: *Interp, what: []const u8, pattern: []const u8, e: tf.PatternError) Signal {
    return it.failWith(err_argument, "time.{s}: pattern '{s}': {s} (column {d})", .{ what, pattern, e.msg, e.pos + 1 });
}

// @eve-impl the text of a Date, a Time or an Instant (in UTC) by a pattern; also the format of a placeholder `{d % yyyy-MM-dd}`
// @spec spec/library/time.md#patterns
pub fn formatText(it: *Interp, v: Value, pattern: []const u8) Signal![]const u8 {
    var toks: [tf.max_tokens]tf.Token = undefined;
    var pe: tf.PatternError = undefined;
    const n = tf.compile(pattern, &toks, &pe) catch return patternFail(it, "format", pattern, pe);
    const fields: tf.Fields = switch (v) {
        .date => |d| .{ .days = d, .has_date = true },
        .time => |us| .{ .us_of_day = us, .has_time = true },
        .instant => |us| .{ .days = @intCast(@divFloor(us, cal.us_per_day)), .us_of_day = @mod(us, cal.us_per_day), .has_date = true, .has_time = true, .has_zone = true },
        .dtm => |d| blk: {
            const p = dtmParts(d);
            var nb: [8]u8 = undefined;
            const l = metalib.localAt(d.zone, @divFloor(d.us, 1_000_000));
            const zn = try it.t.dupe(u8, metalib.zoneName(d.zone, &nb));
            break :blk .{ .days = p.days, .us_of_day = p.us_of_day, .has_date = true, .has_time = true, .has_zone = true, .utoff = p.utoff, .zone_name = zn, .abbr = if (l.abbr.len > 0) l.abbr else zn };
        },
        else => return it.failWith(err_argument, "time.format: argument 1 is a Date, a Time, an Instant or a DateTime, found {s}", .{Interp.typeName(v)}),
    };
    var aw: Io.Writer.Allocating = .init(it.t);
    tf.format(&aw.writer, toks[0..n], fields) catch |e| return switch (e) {
        error.NeedsDate => it.failWith(err_argument, "time.format: the pattern '{s}' has date letters and a {s} has no date", .{ pattern, Interp.typeName(v) }),
        error.NeedsTime => it.failWith(err_argument, "time.format: the pattern '{s}' has time letters and a {s} has no time of the day", .{ pattern, Interp.typeName(v) }),
        error.NeedsZone => it.failWith(err_argument, "time.format: the letters X, VV and z need a value with a zone (an Instant for X, a DateTime for all), found {s}", .{Interp.typeName(v)}),
        error.WriteFailed => error.OutOfMemory,
    };
    return aw.written();
}

// @eve-impl `DateTime.parse(text)`: `2026-10-24T11:30:00+03:00`, `...Z`, with a space instead of the T, and an optional `[Europe/Bucharest]`; the offset becomes a fixed zone unless the name is given
// @spec spec/library/time.md#the-types
pub fn parseDateTimeIso(it: *Interp, text_in: []const u8) Signal!Value {
    const text = std.mem.trim(u8, text_in, " ");
    const bad = "Cannot parse '{s}' as a DateTime: expected 2026-10-24T11:30:00+03:00";
    var body = text;
    var zone_name: ?[]const u8 = null;
    if (std.mem.indexOfScalar(u8, text, '[')) |lb| {
        if (text[text.len - 1] != ']') return it.failWith(15, bad, .{text});
        zone_name = text[lb + 1 .. text.len - 1];
        body = text[0..lb];
    }
    if (body.len < 20) return it.failWith(15, bad, .{text});
    const days = cal.parseDate(body[0..10]) orelse return it.failWith(15, bad, .{text});
    if (body[10] != 'T' and body[10] != ' ') return it.failWith(15, bad, .{text});
    // the offset starts at Z, + or - after the time
    var k: usize = 11;
    while (k < body.len and body[k] != 'Z' and body[k] != '+' and body[k] != '-') k += 1;
    if (k >= body.len) return it.failWith(15, bad, .{text});
    const us_of_day = cal.parseTime(body[11..k]) orelse return it.failWith(15, bad, .{text});
    const off = metalib.parseOffset(body[k..]) orelse return it.failWith(15, bad, .{text});
    const t = @as(i64, days) * 86400 + @divFloor(us_of_day, 1_000_000) - off;
    const us = t * 1_000_000 + @mod(us_of_day, 1_000_000);
    var zid = metalib.fixedId(off);
    if (zone_name) |zn| {
        zid = (try metalib.zoneIdOf(it, zn)) orelse return it.failWith(15, "Cannot parse '{s}': '{s}' is not a time zone", .{ text, zn });
        if (metalib.localAt(zid, t).utoff != off) return it.failWith(15, "Cannot parse '{s}': the offset does not fit the zone at that moment", .{text});
    }
    return .{ .dtm = .{ .us = us, .zone = zid } };
}

// @eve-impl read a text by a pattern: a Date, a Time or an Instant (date, time and an offset, normalized to UTC); `want` is the type asked by `Date.parse(text, pattern)`
// @spec spec/library/time.md#patterns
pub fn parseText(it: *Interp, text: []const u8, pattern: []const u8, want: ?[]const u8, zone_arg: ?u32) Signal!Value {
    var toks: [tf.max_tokens]tf.Token = undefined;
    var pe: tf.PatternError = undefined;
    const n = tf.compile(pattern, &toks, &pe) catch return patternFail(it, "parse", pattern, pe);
    var p: tf.Parsed = .{};
    var perr: tf.ParseError = undefined;
    tf.parse(text, toks[0..n], &p, &perr) catch return it.failWith(15, "Cannot parse '{s}' by the pattern '{s}': {s} (column {d})", .{ text, pattern, perr.msg, perr.pos + 1 });
    if (p.has_isoweek or p.has_quarter) return it.failWith(err_argument, "time.parse: the letters w and Q can be written but not read", .{});
    const has_date = p.year != null or p.month != null or p.day != null or p.doy != null;
    const has_time = p.hour24 != null or p.hour12 != null or p.minute != null or p.second != null or p.micro != null;
    var days: i32 = 0;
    if (has_date) {
        const y = p.year orelse return it.failWith(err_argument, "time.parse: the pattern '{s}' has no year", .{pattern});
        if (p.doy) |doy| {
            const jan1 = cal.make(y, 1, 1) orelse return it.failWith(15, "Cannot parse '{s}': the year {d} is outside 1 to 9999", .{ text, y });
            const last: u16 = if (cal.isLeap(y)) 366 else 365;
            if (doy < 1 or doy > last) return it.failWith(15, "Cannot parse '{s}': day {d} of the year does not exist", .{ text, doy });
            days = jan1 + doy - 1;
        } else {
            const m = p.month orelse return it.failWith(err_argument, "time.parse: the pattern '{s}' has no month", .{pattern});
            const d = p.day orelse return it.failWith(err_argument, "time.parse: the pattern '{s}' has no day", .{pattern});
            days = cal.make(y, m, d) orelse return it.failWith(15, "Cannot parse '{s}': {d}-{d}-{d} is not a date", .{ text, y, m, d });
        }
        if (p.weekday) |wd| if (cal.weekday(days) != wd) return it.failWith(15, "Cannot parse '{s}': the day of the week does not fit the date", .{text});
    }
    var us_of_day: i64 = 0;
    if (has_time) {
        var hour: i64 = 0;
        if (p.hour24) |h| {
            hour = h;
        } else if (p.hour12) |h| {
            if (h < 1 or h > 12) return it.failWith(15, "Cannot parse '{s}': the hour {d} is not 1 to 12", .{ text, h });
            const pm = p.pm orelse return it.failWith(err_argument, "time.parse: the pattern '{s}' has h but no a (AM or PM)", .{pattern});
            hour = @as(i64, h % 12) + (if (pm) @as(i64, 12) else 0);
        } else return it.failWith(err_argument, "time.parse: the pattern '{s}' has no hour", .{pattern});
        us_of_day = cal.makeTime(hour, p.minute orelse 0, p.second orelse 0, p.micro orelse 0) orelse return it.failWith(15, "Cannot parse '{s}': not a time of the day", .{text});
    }
    const have_offset = p.offset_min != null;
    if (p.has_abbr) return it.failWith(err_argument, "time.parse: the letter z can be written but not read; use VV or X", .{});
    // the zone: written in the text (VV), else the argument, else the offset of the text as a fixed zone
    var zone_id: ?u32 = zone_arg;
    if (p.zone_name) |zn| zone_id = (try metalib.zoneIdOf(it, zn)) orelse return it.failWith(15, "Cannot parse '{s}': '{s}' is not a time zone", .{ text, zn });
    var result: Value = undefined;
    var type_name: []const u8 = undefined;
    if (has_date and has_time and (zone_id != null or have_offset)) {
        const local_sec = @as(i64, days) * 86400 + @divFloor(us_of_day, 1_000_000);
        const sub_us = @mod(us_of_day, 1_000_000);
        if (zone_id) |zid| {
            var t: i64 = undefined;
            if (have_offset) {
                t = local_sec - @as(i64, p.offset_min.?) * 60;
                if (metalib.localAt(zid, t).utoff != p.offset_min.? * 60) return it.failWith(15, "Cannot parse '{s}': the offset does not fit the zone at that moment", .{text});
            } else switch (metalib.resolveLocal(zid, local_sec)) {
                .one => |x| t = x,
                .two => |pair| t = pair.first,
                .gap => return it.failWith(15, "Cannot parse '{s}': that local time does not exist in the zone (the clock jumps)", .{text}),
            }
            result = .{ .dtm = .{ .us = t * 1_000_000 + sub_us, .zone = zid } };
            type_name = "DateTime";
        } else {
            const t = local_sec - @as(i64, p.offset_min.?) * 60;
            if (want != null and std.mem.eql(u8, want.?, "DateTime")) {
                result = .{ .dtm = .{ .us = t * 1_000_000 + sub_us, .zone = metalib.fixedId(p.offset_min.? * 60) } };
                type_name = "DateTime";
            } else {
                result = .{ .instant = t * 1_000_000 + sub_us };
                type_name = "Instant";
            }
        }
    } else if (has_date and !has_time and !have_offset and zone_id == null) {
        result = .{ .date = days };
        type_name = "Date";
    } else if (has_time and !has_date and !have_offset and zone_id == null) {
        result = .{ .time = us_of_day };
        type_name = "Time";
    } else if (has_date and has_time) {
        return it.failWith(err_argument, "time.parse: the pattern '{s}' has a date and a time but no offset (X) or zone (VV), and no zone is given: it does not name a moment", .{pattern});
    } else return it.failWith(err_argument, "time.parse: the pattern '{s}' must have date letters, time letters, or both with an offset or a zone", .{pattern});
    if (want) |w| if (!std.mem.eql(u8, w, type_name)) return it.failWith(err_argument, "{s}.parse: the pattern '{s}' gives a {s}", .{ w, pattern, type_name });
    return result;
}

/// A DateTime `months` months later in the same zone: the local date moves, the local time stays, the instant is found again.
fn dtmShift(it: *Interp, d: Dtm, months: i64, what: []const u8) Signal!?Value {
    const p = dtmParts(d);
    const days = cal.addMonths(p.days, months) orelse return it.failWith(err_overflow, "time.{s}: the result is outside the years 1 to 9999", .{what});
    const us = instantOfLocal(d.zone, days, p.us_of_day) orelse return it.failWith(err_overflow, "time.{s}: the result is outside the years 1 to 9999", .{what});
    return .{ .dtm = .{ .us = us, .zone = d.zone } };
}

// @perf hot
/// The function `f` on values already evaluated: shared by the node entry, the fast call of `invokeWith` (D-220) and the methods of a Date and a Time.
fn compute(it: *Interp, f: Fn, args: []const Value) Signal!?Value {
    const n = @tagName(f);
    switch (f) {
        .now => return it.fail("time.now is not deterministic: write time.now!() (D-087)", .{}),
        .@"now!" => {
            const io = it.io orelse return it.fail("time.now!: no input/output handle", .{});
            return .{ .instant = @intCast(@divFloor(Io.Timestamp.now(io, .real).toNanoseconds(), 1000)) };
        },
        .@"today!" => {
            const io = it.io orelse return it.fail("time.today!: no input/output handle", .{});
            const us: i64 = @intCast(@divFloor(Io.Timestamp.now(io, .real).toNanoseconds(), 1000));
            // without an argument: the date in the zone of the machine; with a Zone or its name: the date there
            const zid: u32 = if (args.len > 0) try zoneIdArg(it, args, 0, n) else try localZone(it);
            const off = metalib.localAt(zid, @divFloor(us, 1_000_000)).utoff;
            return .{ .date = @intCast(@divFloor(us + @as(i64, off) * 1_000_000, cal.us_per_day)) };
        },
        .@"local_zone!" => return .{ .zone = try localZone(it) },
        .seconds => return .{ .real = @as(f64, @floatFromInt(try durationArg(it, args, 0, n))) / 1.0e6 },
        .millis => return .{ .int = @divTrunc(try durationArg(it, args, 0, n), 1000) },
        .micros => return .{ .int = try durationArg(it, args, 0, n) },
        .sleep => {
            const us = try durationArg(it, args, 0, n);
            try it.waitFor(Interp.msOf(.{ .dur = us }).?);
            return .nil;
        },
        .date => {
            const y = try intArg(it, args, 0, n);
            const m = try intArg(it, args, 1, n);
            const d = try intArg(it, args, 2, n);
            return .{ .date = cal.make(y, m, d) orelse return it.failWith(err_argument, "time.date: {d}-{d}-{d} is not a date (years 1 to 9999)", .{ y, m, d }) };
        },
        .clock => {
            const h = try intArg(it, args, 0, n);
            const m = try intArg(it, args, 1, n);
            const s = try intArg(it, args, 2, n);
            const micro = if (args.len > 3) try intArg(it, args, 3, n) else 0;
            return .{ .time = cal.makeTime(h, m, s, micro) orelse return it.failWith(err_argument, "time.clock: {d}:{d}:{d}.{d} is not a time of the day", .{ h, m, s, micro }) };
        },
        .year, .month, .day, .weekday, .day_of_year, .iso_week, .iso_year => {
            const days = try dateArg(it, args, 0, n);
            const c = cal.civilFromDays(days);
            return .{ .int = switch (f) {
                .year => c.year,
                .month => c.month,
                .day => c.day,
                .weekday => cal.weekday(days),
                .day_of_year => cal.dayOfYear(days),
                .iso_week => cal.isoWeek(days).week,
                else => cal.isoWeek(days).year,
            } };
        },
        .hour, .minute, .second, .micro => {
            const us = try timeArg(it, args, 0, n);
            return .{ .int = switch (f) {
                .hour => @divFloor(us, 3_600_000_000),
                .minute => @mod(@divFloor(us, 60_000_000), 60),
                .second => @mod(@divFloor(us, 1_000_000), 60),
                else => @mod(us, 1_000_000),
            } };
        },
        .add_months => {
            if (args.len > 0 and args[0] == .dtm) return try dtmShift(it, args[0].dtm, try intArg(it, args, 1, n), n);
            return dateOrFail(it, cal.addMonths(try dateArg(it, args, 0, n), try intArg(it, args, 1, n)), n);
        },
        .add_years => {
            const years = try intArg(it, args, 1, n);
            if (@abs(years) > 10000) return it.failWith(err_overflow, "time.add_years: the result is outside the years 1 to 9999", .{});
            if (args.len > 0 and args[0] == .dtm) return try dtmShift(it, args[0].dtm, years * 12, n);
            return dateOrFail(it, cal.addMonths(try dateArg(it, args, 0, n), years * 12), n);
        },
        .start_of => {
            if (args.len < 2) return it.failWith(err_argument, "time.start_of takes a value and a unit", .{});
            if (args[1] != .str) return it.failWith(err_argument, "time.start_of: the unit is a text: \"month\"", .{});
            const unit = cal.unitOf(args[1].str) orelse return it.failWith(err_argument, "time.start_of: '{s}' is not a unit (year, quarter, month, week, day, hour, minute, second)", .{args[1].str});
            if (args[0] == .dtm) {
                const p = dtmParts(args[0].dtm);
                const us_of_day: i64 = if (cal.startOfTime(p.us_of_day, unit)) |v| v else 0;
                const days: i32 = switch (unit) {
                    .hour, .minute, .second => p.days,
                    else => cal.startOfDate(p.days, unit).?,
                };
                const keep_time = unit == .hour or unit == .minute or unit == .second;
                const us = instantOfLocal(args[0].dtm.zone, days, if (keep_time) us_of_day else 0) orelse return it.failWith(err_overflow, "time.start_of: the result is outside the years 1 to 9999", .{});
                return .{ .dtm = .{ .us = us, .zone = args[0].dtm.zone } };
            }
            if (args[0] == .date) return .{ .date = cal.startOfDate(args[0].date, unit) orelse return it.failWith(err_argument, "time.start_of: a Date has no {s}", .{args[1].str}) };
            if (args[0] == .time) return .{ .time = cal.startOfTime(args[0].time, unit) orelse return it.failWith(err_argument, "time.start_of: a Time has no {s}", .{args[1].str}) };
            return it.failWith(err_argument, "time.start_of: argument 1 is a Date or a Time, found {s}", .{Interp.typeName(args[0])});
        },
        .end_of_month => {
            const c = cal.civilFromDays(try dateArg(it, args, 0, n));
            return .{ .date = cal.daysFromCivil(c.year, c.month, cal.daysInMonth(c.year, c.month)) };
        },
        .days_in_month => {
            const y = try intArg(it, args, 0, n);
            const m = try intArg(it, args, 1, n);
            if (y < cal.min_year or y > cal.max_year or m < 1 or m > 12) return it.failWith(err_argument, "time.days_in_month: year 1 to 9999 and month 1 to 12", .{});
            return .{ .int = cal.daysInMonth(@intCast(y), @intCast(m)) };
        },
        .is_leap => {
            const y = try intArg(it, args, 0, n);
            return .{ .bool = cal.isLeap(@intCast(std.math.clamp(y, -1_000_000, 1_000_000))) };
        },
        .months_between => return .{ .int = cal.monthsBetween(try dateArg(it, args, 0, n), try dateArg(it, args, 1, n)) },
        .zone => return .{ .zone = try zoneIdArg(it, args, 0, n) },
        .at_zone => return .{ .dtm = .{ .us = try instantUs(it, args, 0, n), .zone = try zoneIdArg(it, args, 1, n) } },
        .make => {
            const days = try dateArg(it, args, 0, n);
            const us_of_day = try timeArg(it, args, 1, n);
            const zid = try zoneIdArg(it, args, 2, n);
            const sec = @as(i64, days) * 86400 + @divFloor(us_of_day, 1_000_000);
            const t: i64 = switch (metalib.resolveLocal(zid, sec)) {
                .one => |x| x,
                .two => |p| p.first,
                .gap => |g| return it.failWith(err_argument, "time.make: the local time does not exist in that zone: the clock jumps from {d} to {d} seconds of offset", .{ g.before, g.after }),
            };
            return .{ .dtm = .{ .us = t * 1_000_000 + @mod(us_of_day, 1_000_000), .zone = zid } };
        },
        .date_of, .time_of, .instant_of, .zone_of, .offset_of => {
            if (args.len < 1 or args[0] != .dtm) return it.failWith(err_argument, "time.{s}: argument 1 is a DateTime, found {s}", .{ n, if (args.len > 0) Interp.typeName(args[0]) else "nothing" });
            const d = args[0].dtm;
            const p = dtmParts(d);
            return switch (f) {
                .date_of => .{ .date = p.days },
                .time_of => .{ .time = p.us_of_day },
                .instant_of => .{ .instant = d.us },
                .zone_of => .{ .zone = d.zone },
                else => .{ .dur = @as(i64, p.utoff) * 1_000_000 },
            };
        },
        .format => {
            if (args.len != 2 or args[1] != .str) return it.failWith(err_argument, "time.format takes a Date, a Time or an Instant and a pattern", .{});
            return try it.newStr(try formatText(it, args[0], args[1].str));
        },
        .parse => {
            if (args.len < 2 or args.len > 3 or args[0] != .str or args[1] != .str) return it.failWith(err_argument, "time.parse takes a text, a pattern and, to read a local time, a zone", .{});
            const zid: ?u32 = if (args.len > 2) try zoneIdArg(it, args, 2, n) else null;
            return try parseText(it, args[0].str, args[1].str, null, zid);
        },
        .years_between => return .{ .int = @divTrunc(cal.monthsBetween(try dateArg(it, args, 0, n), try dateArg(it, args, 1, n)), 12) },
    }
}

/// The entry of `dlib.natives`: evaluates the argument nodes, then computes.
pub fn timeModule(it: *Interp, name: []const u8, _: []const *const Node, arg_nodes: []const *const Node) Signal!?Value {
    const f = std.meta.stringToEnum(Fn, name) orelse return null;
    var buf: [4]Value = undefined;
    if (arg_nodes.len > buf.len) return it.failWith(err_argument, "time.{s}: too many arguments", .{name});
    for (arg_nodes, 0..) |nd, i| buf[i] = try it.eval(nd);
    return compute(it, f, buf[0..arg_nodes.len]);
}

// @eve-impl the functions of the module as methods of a Date or a Time: `d.year()`, `d.add_months(1)`, `t.start_of("hour")`; the receiver is the first argument
// @spec spec/library/time.md#the-module-time
pub fn method(it: *Interp, recv: Value, name: []const u8, arg_nodes: []const *const Node) Signal!?Value {
    const f = std.meta.stringToEnum(Fn, name) orelse return null;
    var buf: [4]Value = undefined;
    if (arg_nodes.len + 1 > buf.len) return it.failWith(err_argument, "{s}: too many arguments", .{name});
    buf[0] = recv;
    for (arg_nodes, 0..) |nd, i| buf[i + 1] = try it.eval(nd);
    return compute(it, f, buf[0 .. arg_nodes.len + 1]);
}

pub fn fastId(name: []const u8) ?u16 {
    const f = std.meta.stringToEnum(Fn, name) orelse return null;
    return @intFromEnum(f);
}

pub fn fastCall(it: *Interp, id: u16, args: []const Value) Signal!Value {
    return (try compute(it, @enumFromInt(id), args)) orelse .nil;
}

test "spec: time.md#zones the name of a zone in a link or in TZ" {
    const t = std.testing;
    try t.expectEqualStrings("Europe/Bucharest", regionName("/usr/share/zoneinfo/Europe/Bucharest").?);
    try t.expectEqualStrings("Europe/Bucharest", regionName("../usr/share/zoneinfo/Europe/Bucharest").?);
    try t.expectEqualStrings("Europe/Bucharest", regionName(":Europe/Bucharest").?);
    try t.expectEqualStrings("UTC", regionName("UTC").?);
    try t.expect(regionName("/etc/localtime") == null);
    try t.expect(regionName("") == null);
}
