//! @eve-module interp.datatypes
//! @spec spec/library/data-language.md
//! @feature F-LNG-13, F-LIB-06, F-LIB-08
//! @tests test/level5
//! Decimal, Instant and Secret values (spec/library/data-language.md).
//! Part of the interpreter (interp.zig): every function takes the interpreter as `it: *Interp`, and
//! `Interp` names each of them again, so a call reads `it.name(...)` wherever it is made.
const std = @import("std");
const cmdargs = @import("cmdargs.zig");
const interp = @import("../interp.zig");
const db = @import("../db.zig");
const Interp = interp.Interp;
const data = interp.data;
const decimal = interp.decimal;
const dlib = interp.dlib;
const instant = interp.instant;
const Node = interp.Node;
const value = interp.value;
const Signal = interp.Signal;
const Value = interp.Value;
const Class = interp.Class;
const Arg = interp.Arg;
const err_key = interp.err_key;
const err_divide = interp.err_divide;
const rational = interp.rational;
const err_argument = interp.err_argument;
const err_convert = interp.err_convert;

// ---- Decimal, Instant, Secret (spec/library/data-language.md) ---------------------------------------

/// An arithmetic operator when one side is a Decimal and the other a Decimal or a whole number.
pub fn decimalOp(it: *Interp, op: []const u8, l: Value, r: Value) Signal!Value {
    const eql = std.mem.eql;
    const x = Interp.decOf(l) orelse return it.fail("operator {s} does not apply to {s} and {s}: a Decimal and a Real are never mixed, convert one explicitly", .{ op, Interp.typeName(l), Interp.typeName(r) });
    const y = Interp.decOf(r) orelse return it.fail("operator {s} does not apply to {s} and {s}: a Decimal and a Real are never mixed, convert one explicitly", .{ op, Interp.typeName(l), Interp.typeName(r) });
    if (eql(u8, op, "+")) return .{ .dec = decimal.add(x, y) orelse return it.overflow() };
    if (eql(u8, op, "-")) return .{ .dec = decimal.sub(x, y) orelse return it.overflow() };
    if (eql(u8, op, "*")) return .{ .dec = decimal.mul(x, y) orelse return it.overflow() };
    if (eql(u8, op, "/") or eql(u8, op, "%")) {
        if (y.m == 0) return it.failWith(err_divide, "Division by zero", .{});
        if (eql(u8, op, "%")) return .{ .dec = decimal.rem(x, y) };
        return .{ .dec = decimal.div(x, y) orelse return it.overflow() };
    }
    return it.fail("operator {s} does not apply to {s} and {s}", .{ op, Interp.typeName(l), Interp.typeName(r) });
}

/// A Decimal from a Real read in a column: the shortest text that gives the same number.
// @eve-impl arithmetic with a Rational: exact with a Rational or an Integer, a Real with a Real or a Float; a Decimal is refused
// @spec spec/semantics/types.md#rational
// @feature F-LNG-30
// @perf hot
pub fn ratOp(it: *Interp, op: []const u8, l: Value, r: Value) Signal!Value {
    const eql = std.mem.eql;
    if (l == .dec or r == .dec) return it.failWith(err_argument, "a Rational and a Decimal do not mix: convert one of them", .{});
    if (l == .real or l == .float or r == .real or r == .float) {
        const x = Interp.realOf(l) orelse return it.fail("operator {s} does not apply to {s} and {s}", .{ op, Interp.typeName(l), Interp.typeName(r) });
        const y = Interp.realOf(r) orelse return it.fail("operator {s} does not apply to {s} and {s}", .{ op, Interp.typeName(l), Interp.typeName(r) });
        if (eql(u8, op, "+")) return .{ .real = x + y };
        if (eql(u8, op, "-")) return .{ .real = x - y };
        if (eql(u8, op, "*")) return .{ .real = x * y };
        if (eql(u8, op, "/")) {
            if (y == 0) return it.failWith(err_divide, "Division by zero", .{});
            return .{ .real = x / y };
        }
        if (eql(u8, op, "^")) return .{ .real = std.math.pow(f64, x, y) };
        return it.fail("operator {s} does not apply to {s} and {s}", .{ op, Interp.typeName(l), Interp.typeName(r) });
    }
    const x = Interp.ratOf(l) orelse return it.fail("operator {s} does not apply to {s} and {s}", .{ op, Interp.typeName(l), Interp.typeName(r) });
    const y = Interp.ratOf(r) orelse return it.fail("operator {s} does not apply to {s} and {s}", .{ op, Interp.typeName(l), Interp.typeName(r) });
    if (op.len == 1) switch (op[0]) {
        '+' => return .{ .rat = rational.add(x, y) orelse return it.overflow() },
        '-' => return .{ .rat = rational.sub(x, y) orelse return it.overflow() },
        '*' => return .{ .rat = rational.mul(x, y) orelse return it.overflow() },
        '/' => {
            if (y.n == 0) return it.failWith(err_divide, "Division by zero", .{});
            return .{ .rat = rational.div(x, y) orelse return it.overflow() };
        },
        '^' => {
            if (y.d != 1) return it.failWith(err_argument, "a Rational is raised to a whole power", .{});
            if (x.n == 0 and y.n < 0) return it.failWith(err_divide, "Division by zero", .{});
            return .{ .rat = rational.pow(x, y.n) orelse return it.overflow() };
        },
        else => {},
    };
    return it.fail("operator {s} does not apply to {s} and {s}", .{ op, Interp.typeName(l), Interp.typeName(r) });
}

// @eve-impl arithmetic with a Complex: the other operand is an Integer, a Real, a Float, a Rational or a Complex; a Decimal is refused; no ordering
// @spec spec/semantics/types.md#complex
// @feature F-LNG-31
// @perf hot
pub fn cpxOp(it: *Interp, op: []const u8, l: Value, r: Value) Signal!Value {
    const c = interp.complex;
    if (l == .dec or r == .dec) return it.failWith(err_argument, "a Complex and a Decimal do not mix: convert one of them", .{});
    const x = Interp.cpxOf(l) orelse return it.fail("operator {s} does not apply to {s} and {s}", .{ op, Interp.typeName(l), Interp.typeName(r) });
    const y = Interp.cpxOf(r) orelse return it.fail("operator {s} does not apply to {s} and {s}", .{ op, Interp.typeName(l), Interp.typeName(r) });
    var z: c.Cpx = undefined;
    if (op.len == 1 and op[0] == '+') {
        z = c.add(x, y);
    } else if (op.len == 1 and op[0] == '-') {
        z = c.sub(x, y);
    } else if (op.len == 1 and op[0] == '*') {
        z = c.mul(x, y);
    } else if (op.len == 1 and op[0] == '/') {
        if (y.re == 0 and y.im == 0) return it.failWith(err_divide, "Division by zero", .{});
        z = c.div(x, y);
    } else if (op.len == 1 and op[0] == '^') {
        if (y.im == 0 and y.re == @floor(y.re) and @abs(y.re) <= 1.0e9) {
            if (x.re == 0 and x.im == 0 and y.re < 0) return it.failWith(err_divide, "Division by zero", .{});
            z = c.powInt(x, @intFromFloat(y.re));
        } else {
            if (x.re == 0 and x.im == 0 and !(y.re > 0 and y.im == 0)) return it.failWith(err_argument, "zero to a power that is not a positive real number", .{});
            z = c.pow(x, y);
        }
    } else return it.fail("operator {s} does not apply to {s} and {s}", .{ op, Interp.typeName(l), Interp.typeName(r) });
    if (!c.finite(z)) return it.overflow();
    return .{ .cpx = z };
}

/// A Date plus a number of days, or null when the result is outside year 1 to 9999.
fn dateAdd(it: *Interp, days: i32, n: i64) ?i32 {
    _ = it;
    const r = @as(i64, days) + n;
    if (r < interp.calendar.min_days or r > interp.calendar.max_days) return null;
    return @intCast(r);
}

// @eve-impl arithmetic of Duration and Instant: Duration with Duration, Duration with an Integer, Instant with a Duration, Instant minus Instant
// @spec spec/library/time.md#operators
// @feature F-LNG-13
pub fn timeOp(it: *Interp, op: []const u8, l: Value, r: Value) Signal!Value {
    const bad = "operator {s} does not apply to {s} and {s}";
    if (op.len != 1) return it.fail(bad, .{ op, Interp.typeName(l), Interp.typeName(r) });
    const c = op[0];
    if (l == .dur and r == .dur) {
        switch (c) {
            '+' => return .{ .dur = std.math.add(i64, l.dur, r.dur) catch return it.overflow() },
            '-' => return .{ .dur = std.math.sub(i64, l.dur, r.dur) catch return it.overflow() },
            '/' => {
                if (r.dur == 0) return it.failWith(err_divide, "Division by zero", .{});
                return .{ .real = @as(f64, @floatFromInt(l.dur)) / @as(f64, @floatFromInt(r.dur)) };
            },
            else => {},
        }
    } else if (l == .date and Interp.isInt(r) and (c == '+' or c == '-')) {
        const n = if (c == '+') Interp.intOf(r) else (std.math.negate(Interp.intOf(r)) catch return it.overflow());
        return .{ .date = dateAdd(it, l.date, n) orelse return it.overflow() };
    } else if (Interp.isInt(l) and r == .date and c == '+') {
        return .{ .date = dateAdd(it, r.date, Interp.intOf(l)) orelse return it.overflow() };
    } else if (l == .date and r == .date and c == '-') {
        return .{ .int = @as(i64, l.date) - r.date };
    } else if (l == .time and r == .dur and (c == '+' or c == '-')) {
        // the clock wraps round: 23:30 + 1h is 00:30
        const day = interp.calendar.us_per_day;
        const delta = @mod(r.dur, day);
        const sum = if (c == '+') l.time + delta else l.time - delta;
        return .{ .time = @mod(sum, day) };
    } else if (l == .dur and r == .time and c == '+') {
        return .{ .time = @mod(r.time + @mod(l.dur, interp.calendar.us_per_day), interp.calendar.us_per_day) };
    } else if (l == .time and r == .time and c == '-') {
        return .{ .dur = l.time - r.time };
    } else if (l == .dur and Interp.isInt(r)) {
        const k = Interp.intOf(r);
        switch (c) {
            '*' => return .{ .dur = std.math.mul(i64, l.dur, k) catch return it.overflow() },
            '/' => {
                if (k == 0) return it.failWith(err_divide, "Division by zero", .{});
                return .{ .dur = @divTrunc(l.dur, k) };
            },
            else => {},
        }
    } else if (Interp.isInt(l) and r == .dur and c == '*') {
        return .{ .dur = std.math.mul(i64, r.dur, Interp.intOf(l)) catch return it.overflow() };
    } else if (l == .dtm and r == .dur and (c == '+' or c == '-')) {
        const us = if (c == '+') std.math.add(i64, l.dtm.us, r.dur) else std.math.sub(i64, l.dtm.us, r.dur);
        return .{ .dtm = .{ .us = us catch return it.overflow(), .zone = l.dtm.zone } };
    } else if (l == .dur and r == .dtm and c == '+') {
        return .{ .dtm = .{ .us = std.math.add(i64, r.dtm.us, l.dur) catch return it.overflow(), .zone = r.dtm.zone } };
    } else if ((l == .dtm or l == .instant) and (r == .dtm or r == .instant) and c == '-') {
        const a: i64 = if (l == .dtm) l.dtm.us else l.instant;
        const b: i64 = if (r == .dtm) r.dtm.us else r.instant;
        return .{ .dur = std.math.sub(i64, a, b) catch return it.overflow() };
    } else if (l == .instant and r == .dur) {
        switch (c) {
            '+' => return .{ .instant = std.math.add(i64, l.instant, r.dur) catch return it.overflow() },
            '-' => return .{ .instant = std.math.sub(i64, l.instant, r.dur) catch return it.overflow() },
            else => {},
        }
    } else if (l == .dur and r == .instant and c == '+') {
        return .{ .instant = std.math.add(i64, r.instant, l.dur) catch return it.overflow() };
    } else if (l == .instant and r == .instant and c == '-') {
        return .{ .dur = std.math.sub(i64, l.instant, r.instant) catch return it.overflow() };
    }
    return it.fail(bad, .{ op, Interp.typeName(l), Interp.typeName(r) });
}

pub fn decFromReal(it: *Interp, x: f64) Signal!decimal.Dec {
    return decimal.fromF64(x) orelse it.overflow();
}

/// A text column read into the member `m`: a Decimal or an Instant is parsed, anything else is a String.
pub fn fromSqlText(it: *Interp, raw: []const u8, m: *const Node) Signal!Value {
    const ty = dlib.baseType(m.ty);
    if (std.mem.eql(u8, ty, "Decimal")) {
        return .{ .dec = decimal.parse(raw) orelse return it.failWith(err_convert, "DatabaseError: '{s}' is not a Decimal for '{s}'", .{ raw, m.text }) };
    }
    if (std.mem.eql(u8, ty, "Instant")) {
        return .{ .instant = instant.parse(raw) orelse return it.failWith(err_convert, "DatabaseError: '{s}' is not an Instant for '{s}'", .{ raw, m.text }) };
    }
    if (std.mem.eql(u8, ty, "Date")) {
        return .{ .date = interp.calendar.parseDate(raw) orelse return it.failWith(err_convert, "DatabaseError: '{s}' is not a Date for '{s}'", .{ raw, m.text }) };
    }
    if (std.mem.eql(u8, ty, "DateTime")) {
        return @import("../timelib.zig").parseDateTimeIso(it, raw) catch return it.failWith(err_convert, "DatabaseError: '{s}' is not a DateTime for '{s}'", .{ raw, m.text });
    }
    if (std.mem.eql(u8, ty, "Time")) {
        return .{ .time = interp.calendar.parseTime(raw) orelse return it.failWith(err_convert, "DatabaseError: '{s}' is not a Time for '{s}'", .{ raw, m.text }) };
    }
    if (std.mem.eql(u8, ty, "Duration")) {
        return .{ .dur = interp.duration.parse(raw) orelse return it.failWith(err_convert, "DatabaseError: '{s}' is not a Duration for '{s}'", .{ raw, m.text }) };
    }
    return it.newStr(raw);
}

/// `Secret(text)`: a value that prints as `***`.
pub fn makeSecret(it: *Interp, args: []const *const Node) Signal!Value {
    if (args.len != 1) return it.fail("Secret takes one text", .{});
    const v = try it.eval(args[0]);
    if (v != .str) return it.fail("Secret takes a String, not a {s}", .{Interp.typeName(v)});
    return it.secretObject(v);
}

/// Is the value a generator object?
pub fn isGenerator(it: *Interp, v: Value) bool {
    return v == .object and v.object.class != null and v.object.class == it.base().gen_class;
}

/// Is the value a Secret?
pub fn isSecret(it: *Interp, v: Value) bool {
    return v == .object and v.object.class != null and v.object.class == it.base().secret_class;
}

pub fn secretObject(it: *Interp, secret_text: Value) Signal!Value {
    const b = it.base();
    if (b.secret_class == null) {
        const cls = try it.a.create(Class);
        cls.* = .{ .name = "Secret" };
        b.secret_class = cls;
    }
    const obj = try it.newObject();
    obj.class = b.secret_class;
    try it.setField(obj, "text", secret_text);
    return .{ .object = obj };
}

// @decision D-155
/// `secret.get(name)`: the secret of the machine, or the error `$err_key` when there is none.
pub fn secretGet(it: *Interp, args: []const *const Node) Signal!Value {
    if (args.len != 1) return it.fail("secret.get takes the name of a secret", .{});
    const name = try it.text(try it.eval(args[0]));
    var upper: std.ArrayList(u8) = .empty;
    try upper.appendSlice(it.t, "EVE_SECRET_");
    for (name) |ch| try upper.append(it.t, std.ascii.toUpper(ch));
    const z = try it.t.dupeSentinel(u8, upper.items, 0);
    const found = std.c.getenv(z) orelse return it.failWith(err_key, "secret.get: no secret '{s}' (set {s})", .{ name, upper.items });
    return it.secretObject(try it.newStr(std.mem.span(found)));
}

pub fn runRoot(it: *Interp, root: *const Node) Signal!void {
    defer it.finalizeModules();
    defer db.closeDatabases(it.host());
    defer dlib.closeStreams(it);
    defer db.orm.closeCore(it.host());
    defer it.closeGenerators();
    for (root.kids) |d| if (d.tag == .import_decl) try it.execImport(d);
    for (root.kids) |d| {
        if (d.tag == .adopt or d.tag == .class or d.tag == .trait or d.tag == .function or d.tag == .procedure or d.tag == .method or d.tag == .generator) try it.declareRoutine(d);
    }
    for (root.kids) |d| if (d.tag == .table_decl) {
        try db.declareTables(it.host(), root.kids);
        break;
    };
    for (root.kids) |d| {
        if (d.tag == .var_decl or d.tag == .set) try it.exec(d);
    }
    const main = Interp.findProcess(root, "main") orelse return it.fail("the aspect has no process main", .{});
    // @eve-impl the bytecode machine runs `process main` after the same preparation as the tree walker (D-201)
    if (interp.engine == .bytecode and it.script_args.len == 0 and it.script_params.len == 0) {
        if (try @import("../bcvm.zig").runMain(it, root, main)) return;
    }
    // the arguments of the command line go to the parameters of the process
    // each text is converted to the type of its parameter; `-p name=value` goes to the parameter of that name (cmdargs.zig)
    try it.runProcess(main, try cmdargs.build(it, main), "aspect", root.text);
}
