//! @eve-module interp.expr
//! @spec spec/syntax/expressions.md
//! @feature F-LNG-03
//! @tests test/level1
//! Expressions and operators: `eval` and the arithmetic, comparison and logic of values.
//! Part of the interpreter (interp.zig): every function takes the interpreter as `it: *Interp`, and
//! `Interp` names each of them again, so a call reads `it.name(...)` wherever it is made.
const std = @import("std");
const bytesfn = @import("bytesfn.zig");
const interp = @import("../interp.zig");
const Interp = interp.Interp;
const ast = interp.ast;
const data = interp.data;
const decimal = interp.decimal;
const dlib = interp.dlib;
const Heap = interp.Heap;
const Node = interp.Node;
const value = interp.value;
const Signal = interp.Signal;
const Value = interp.Value;
const List = interp.List;
const Map = interp.Map;
const Object = interp.Object;
const Class = interp.Class;
const Domain = interp.Domain;
const err_divide = interp.err_divide;
const err_overflow = interp.err_overflow;

// ---- expressions ----------------------------------------------------------------------

pub fn number(it: *Interp, n: *const Node) Signal!Value {
    switch (n.lit_kind) {
        .int => return .{ .int = @bitCast(n.lit_bits) },
        .real => return .{ .real = @bitCast(n.lit_bits) },
        .rat => return .{ .rat = .{ .n = @intCast(n.lit_bits & 0xffffffff), .d = @intCast(n.lit_bits >> 32) } },
        .imag => return .{ .cpx = .{ .re = 0, .im = @bitCast(n.lit_bits) } },
        .dur => return .{ .dur = @bitCast(n.lit_bits) },
        .none => {},
    }
    if (interp.duration.parseLiteral(n.text)) |us| return .{ .dur = us };
    // an imaginary literal `i99`, `i2.5` (types.md#complex)
    if (n.text.len > 1 and n.text[0] == 'i') {
        const im = std.fmt.parseFloat(f64, n.text[1..]) catch return it.fail("bad number {s}", .{n.text});
        return .{ .cpx = .{ .re = 0, .im = im } };
    }
    // a Rational literal `3\4` (types.md#rational)
    if (std.mem.indexOfScalar(u8, n.text, '\\') != null) {
        const q = interp.rational.parse(n.text) orelse {
            if (std.mem.endsWith(u8, n.text, "\\0")) return it.failWith(err_divide, "Division by zero in the Rational literal {s}", .{n.text});
            return it.overflow();
        };
        return .{ .rat = q };
    }
    var buf: [64]u8 = undefined;
    var len: usize = 0;
    var digits_text = n.text;
    var suffix: u8 = 0;
    if (digits_text.len > 1 and digits_text[0] == '"') {
        // a number written as a string with a type suffix: `"1,000,000"z`, `"12,500.75"d`
        suffix = digits_text[digits_text.len - 1];
        digits_text = digits_text[1 .. digits_text.len - 2];
    } else if (digits_text.len > 1 and std.ascii.isAlphabetic(digits_text[digits_text.len - 1]) and !(digits_text.len > 2 and digits_text[0] == '0' and digits_text[1] == 'x')) {
        const last = digits_text[digits_text.len - 1];
        if (std.mem.indexOfScalar(u8, "drfbwnz", last) != null) {
            suffix = last;
            digits_text = digits_text[0 .. digits_text.len - 1];
        }
    }
    for (digits_text) |c| {
        if (c == ',' or len == buf.len) continue;
        buf[len] = c;
        len += 1;
    }
    const t = buf[0..len];
    const is_float = std.mem.indexOfScalar(u8, t, '.') != null or ((std.mem.indexOfAny(u8, t, "eE") != null) and !(t.len > 1 and t[0] == '0' and t[1] == 'x'));
    if (is_float) {
        const x = std.fmt.parseFloat(f64, t) catch return it.fail("bad number {s}", .{n.text});
        if (suffix == 'd') return .{ .dec = decimal.parse(t) orelse return it.fail("bad decimal {s}", .{n.text}) };
        return switch (suffix) {
            'f' => .{ .float = x },
            else => .{ .real = x },
        };
    }
    const v = std.fmt.parseInt(i64, t, 0) catch {
        return .{ .real = std.fmt.parseFloat(f64, t) catch return it.fail("bad number {s}", .{n.text}) };
    };
    switch (suffix) {
        'd' => return .{ .dec = decimal.fromInt(v) orelse return it.overflow() },
        'r' => return .{ .real = @floatFromInt(v) },
        'f' => return .{ .float = @floatFromInt(v) },
        'b' => return .{ .byte = v },
        'w' => return .{ .short = v },
        'n' => return .{ .nat = v },
        'z' => return .{ .huge = v },
        else => {},
    }
    if (t.len > 1 and t[0] == '0' and (t[1] == 'x' or t[1] == 'b')) return .{ .nat = v };
    return .{ .int = v };
}

/// The code point of the UTF-8 text of a symbol node.
pub fn symbolOf(t: []const u8) u21 {
    if (t.len == 0) return 0; // the empty rune, nil
    return std.unicode.utf8Decode(t) catch 0xFFFD;
}

// @decision D-144
/// The milliseconds of a duration literal (`10ms`, `30s`, `2m`, `1h`), or null for another number.
pub fn durationMs(lit: []const u8) ?i64 {
    if (lit.len < 2 or !std.ascii.isDigit(lit[0])) return null;
    const units = [_]struct { []const u8, i64 }{ .{ "ms", 1 }, .{ "s", 1000 }, .{ "m", 60_000 }, .{ "h", 3_600_000 } };
    for (units) |u| {
        if (!std.mem.endsWith(u8, lit, u[0])) continue;
        const digits = lit[0 .. lit.len - u[0].len];
        for (digits) |c| if (!std.ascii.isDigit(c)) return null;
        const v = std.fmt.parseInt(i64, digits, 10) catch return null;
        return v * u[1];
    }
    return null;
}

pub fn eval(it: *Interp, n: *const Node) Signal!Value {
    switch (n.tag) {
        .num => return it.number(n),
        .str => return it.staticStr(n.text),
        .text_lit => {
            const v = try it.staticStr(n.text);
            try it.base().text_ptrs.put(it.a, @intFromPtr(v.str.ptr), {});
            return v;
        },
        .interp => return it.interpolate(n),
        .chr => return .{ .sym = Interp.symbolOf(n.text) },
        .name => return it.lookup(n.text),
        .ref => return it.lookup(n.text),
        .dollar => return .{ .int = it.dollar },
        .bin => return it.binary(n),
        .un => return it.unary(n),
        .range => return it.makeRange(n),
        .cond => {
            const c = try it.truth(try it.eval(n.kids[1]));
            return it.eval(if (c) n.kids[0] else n.kids[2]);
        },
        .list, .array => {
            const l = try it.h.make(List, .{ .array = n.tag == .array });
            for (n.kids) |k| try it.listAppend(l, try it.eval(k));
            return .{ .list = l };
        },
        .brace => return it.brace(n),
        .builder => return it.builder(n),
        .field => return it.field(n),
        .index => return it.index(n),
        .call => return it.call(n),
        .lambda => return .{ .func = try it.newFunc(n, it.scope) },
        // `await f(x)`: the call runs here and now; while it waits, the other tasks run (D-143)
        .await_ => return it.call(n.kids[0]),
        // `Box(:Integer)`: version 0.3 erases the type arguments, the class itself is the value (D-145)
        .generic => return it.lookup(n.text),
        else => return it.fail("cannot evaluate a {s}", .{@tagName(n.tag)}),
    }
}

pub fn unary(it: *Interp, n: *const Node) Signal!Value {
    const v = try it.eval(n.kids[0]);
    const op = n.text;
    if (std.mem.eql(u8, op, "not")) return .{ .bool = !(try it.truth(v)) };
    if (std.mem.eql(u8, op, "+")) return v;
    return it.negate(v);
}

// @eve-impl the arithmetic negation of a value, shared with the bytecode machine
/// `-v`.
pub fn negate(it: *Interp, v: Value) Signal!Value {
    return switch (v) {
        .int, .nat, .byte, .short => |x| .{ .int = -x },
        .huge => |x| .{ .huge = -x },
        .real, .float => |x| .{ .real = -x },
        .dec => |d| .{ .dec = decimal.neg(d) orelse return it.overflow() },
        .rat => |q| .{ .rat = interp.rational.neg(q) orelse return it.overflow() },
        .cpx => |z| .{ .cpx = interp.complex.neg(z) },
        .dur => |us| .{ .dur = std.math.negate(us) catch return it.overflow() },
        else => it.fail("cannot negate {s}", .{Interp.typeName(v)}),
    };
}

pub fn makeRange(it: *Interp, n: *const Node) Signal!Value {
    const open_lo = n.kids[0].tag == .open_end;
    const open_hi = n.kids[1].tag == .open_end;
    const lo = if (open_lo) Value.nil else try it.eval(n.kids[0]);
    const hi = if (open_hi) Value.nil else try it.eval(n.kids[1]);
    if (std.mem.eql(u8, n.text, "+-")) {
        const c = Interp.realOf(lo) orelse return it.fail("+- needs numbers", .{});
        const t = Interp.realOf(hi) orelse return it.fail("+- needs numbers", .{});
        return .{ .domain = try it.newDomain(.{ .lo = c - t, .hi = c + t }) };
    }
    const excl_lo = n.text[0] == '>';
    const excl_hi = n.text[n.text.len - 1] == '<';
    if (!open_lo and !open_hi and Interp.isInt(lo) and Interp.isInt(hi)) {
        return .{ .range = try it.newRange(.{ .lo = Interp.intOf(lo) + @as(i64, if (excl_lo) 1 else 0), .hi = Interp.intOf(hi) - @as(i64, if (excl_hi) 1 else 0) }) };
    }
    if (lo == .sym and hi == .sym) {
        return .{ .range = try it.newRange(.{ .lo = lo.sym + @as(i64, if (excl_lo) 1 else 0), .hi = hi.sym - @as(i64, if (excl_hi) 1 else 0), .sym = true }) };
    }
    if ((!open_lo and Interp.realOf(lo) == null) or (!open_hi and Interp.realOf(hi) == null)) {
        return it.fail("a range needs numbers or symbols, found {s} and {s}", .{ Interp.typeName(lo), Interp.typeName(hi) });
    }
    return .{ .domain = try it.newDomain(.{ .lo = Interp.realOf(lo), .hi = Interp.realOf(hi), .lo_excl = excl_lo, .hi_excl = excl_hi }) };
}

/// Is the real `x` inside the domain `d`? (limits, excluded limits, step)
pub fn inDomain(d: *const Domain, x: f64) bool {
    if (d.lo) |lo| if (x < lo or (d.lo_excl and x == lo)) return false;
    if (d.hi) |hi| if (x > hi or (d.hi_excl and x == hi)) return false;
    if (d.step) |st| {
        const q = x / st;
        if (@abs(q - @round(q)) > 1e-9) return false;
    }
    return true;
}

/// `{ ... }`: a DataSet, a HashMap or an Object, as the parser decided.
pub fn brace(it: *Interp, n: *const Node) Signal!Value {
    if (std.mem.eql(u8, n.text, "set")) {
        const s = try it.h.make(List, .{});
        for (n.kids) |k| try it.setAdd(s, try it.eval(k));
        return .{ .set = s };
    }
    if (std.mem.eql(u8, n.text, "map")) {
        const m = try it.newMap();
        for (n.kids) |k| try it.mapPut(m, try it.eval(k.kids[0]), try it.eval(k.kids[1]));
        return .{ .map = m };
    }
    const o = try it.newObject();
    for (n.kids) |k| try it.setField(o, k.kids[0].text, try it.eval(k.kids[1]));
    return .{ .object = o };
}

pub fn mapFind(m: *Map, key: Value) ?usize {
    for (m.entries.items, 0..) |e, i| {
        if (Interp.eq(e.key, key)) return i;
    }
    return null;
}

/// Set `key` in the sorted map, creating the entry in its place when it is missing.
pub fn mapPut(it: *Interp, m: *Map, key: Value, val: Value) Signal!void {
    if (Interp.mapFind(m, key)) |i| {
        it.setCell(&m.entries.items[i].val, val);
        return;
    }
    var i: usize = 0;
    while (i < m.entries.items.len and (try it.order(m.entries.items[i].key, key)) == .lt) i += 1;
    try m.entries.insert(it.g, i, .{ .key = key, .val = val });
    Heap.retain(key);
    Heap.retain(val);
}

// ---- operators ------------------------------------------------------------------------

pub fn binary(it: *Interp, n: *const Node) Signal!Value {
    const op = n.text;
    // `x ?? d`: d is evaluated only when x is null (types.md#narrowing-and-the-default)
    if (std.mem.eql(u8, op, "??")) {
        const x = try it.eval(n.kids[0]);
        if (x != .nil) return x;
        return it.eval(n.kids[1]);
    }
    if (std.mem.eql(u8, op, "and")) {
        if (!try it.truth(try it.eval(n.kids[0]))) return .{ .bool = false };
        return .{ .bool = try it.truth(try it.eval(n.kids[1])) };
    }
    if (std.mem.eql(u8, op, "or")) {
        if (try it.truth(try it.eval(n.kids[0]))) return .{ .bool = true };
        return .{ .bool = try it.truth(try it.eval(n.kids[1])) };
    }
    if (std.mem.eql(u8, op, "=~") and n.kids[1].tag == .range and std.mem.eql(u8, n.kids[1].text, "+-")) {
        const x = Interp.realOf(try it.eval(n.kids[0])) orelse return it.fail("=~ with +- needs numbers", .{});
        const c = Interp.realOf(try it.eval(n.kids[1].kids[0])) orelse return it.fail("=~ with +- needs numbers", .{});
        const t = Interp.realOf(try it.eval(n.kids[1].kids[1])) orelse return it.fail("=~ with +- needs numbers", .{});
        return .{ .bool = @abs(x - c) <= t };
    }
    const l = try it.eval(n.kids[0]);
    const r = try it.eval(n.kids[1]);
    return it.applyOp(n.op, op, l, r);
}

pub const textual = value.textual;

pub fn overflow(it: *Interp) Signal {
    return it.failWith(err_overflow, "Overflow in integer arithmetic", .{});
}

// @eve-impl the arithmetic and comparison of two integers or two reals without comparing the operator text; the rest is `apply`
// @invariant gives what `apply` gives for these cases (overflow, division by zero, a real result of `/`)
// @perf hot
/// Apply a binary operator whose `Op` the parser set.
pub fn applyOp(it: *Interp, o: ast.Op, op: []const u8, l: Value, r: Value) Signal!Value {
    if (l == .int and r == .int) {
        const x = l.int;
        const y = r.int;
        switch (o) {
            .add => {
                const s = @addWithOverflow(x, y);
                return if (s[1] != 0) it.overflow() else .{ .int = s[0] };
            },
            .sub => {
                const s = @subWithOverflow(x, y);
                return if (s[1] != 0) it.overflow() else .{ .int = s[0] };
            },
            .mul => {
                const s = @mulWithOverflow(x, y);
                return if (s[1] != 0) it.overflow() else .{ .int = s[0] };
            },
            .mod => if (y != 0) return .{ .int = @mod(x, y) },
            .eq => return .{ .bool = x == y },
            .ne => return .{ .bool = x != y },
            .lt => return .{ .bool = x < y },
            .gt => return .{ .bool = x > y },
            .le => return .{ .bool = x <= y },
            .ge => return .{ .bool = x >= y },
            else => {},
        }
    } else if (l == .real and r == .real) {
        switch (o) {
            .add => return .{ .real = l.real + r.real },
            .sub => return .{ .real = l.real - r.real },
            .mul => return .{ .real = l.real * r.real },
            else => {},
        }
    } else if (l == .instant or l == .dur or l == .date or l == .time) {
        // @perf hot
        // Instant, Duration, Date and Time without the operator text: the same results as `timeOp` and `order` (time.md#operators)
        if (timeFast(o, l, r)) |v| return v;
    } else if (l == .cpx and r == .cpx) {
        // @perf hot
        const c = interp.complex;
        switch (o) {
            .add => return .{ .cpx = c.add(l.cpx, r.cpx) },
            .sub => return .{ .cpx = c.sub(l.cpx, r.cpx) },
            .mul => {
                const z = c.mul(l.cpx, r.cpx);
                if (c.finite(z)) return .{ .cpx = z };
            },
            .eq => return .{ .bool = c.eql(l.cpx, r.cpx) },
            .ne => return .{ .bool = !c.eql(l.cpx, r.cpx) },
            else => {},
        }
    } else if (l == .rat or r == .rat) {
        // @perf hot
        // exact fractions without the operator text: the same results as `ratOp` (types.md#rational)
        if (Interp.ratOf(l)) |x| if (Interp.ratOf(r)) |y| {
            const q = interp.rational;
            switch (o) {
                .add => return .{ .rat = q.add(x, y) orelse return it.overflow() },
                .sub => return .{ .rat = q.sub(x, y) orelse return it.overflow() },
                .mul => return .{ .rat = q.mul(x, y) orelse return it.overflow() },
                .div => if (y.n != 0) return .{ .rat = q.div(x, y) orelse return it.overflow() },
                .eq => return .{ .bool = x.n == y.n and x.d == y.d },
                .ne => return .{ .bool = x.n != y.n or x.d != y.d },
                .lt => return .{ .bool = q.order(x, y) == .lt },
                .gt => return .{ .bool = q.order(x, y) == .gt },
                .le => return .{ .bool = q.order(x, y) != .gt },
                .ge => return .{ .bool = q.order(x, y) != .lt },
                else => {},
            }
        };
    }
    return it.apply(op, l, r);
}

// @eve-impl the common cases of the operators on times; null when the general path must decide (a mix, an overflow, a zero divisor)
// @spec spec/library/time.md#operators
fn timeFast(o: ast.Op, l: Value, r: Value) ?Value {
    switch (l) {
        .instant => |a| switch (r) {
            .dur => |b| switch (o) {
                .add => return .{ .instant = std.math.add(i64, a, b) catch return null },
                .sub => return .{ .instant = std.math.sub(i64, a, b) catch return null },
                else => {},
            },
            .instant => |b| switch (o) {
                .sub => return .{ .dur = std.math.sub(i64, a, b) catch return null },
                .eq => return .{ .bool = a == b },
                .ne => return .{ .bool = a != b },
                .lt => return .{ .bool = a < b },
                .gt => return .{ .bool = a > b },
                .le => return .{ .bool = a <= b },
                .ge => return .{ .bool = a >= b },
                else => {},
            },
            else => {},
        },
        .dur => |a| switch (r) {
            .dur => |b| switch (o) {
                .add => return .{ .dur = std.math.add(i64, a, b) catch return null },
                .sub => return .{ .dur = std.math.sub(i64, a, b) catch return null },
                .eq => return .{ .bool = a == b },
                .ne => return .{ .bool = a != b },
                .lt => return .{ .bool = a < b },
                .gt => return .{ .bool = a > b },
                .le => return .{ .bool = a <= b },
                .ge => return .{ .bool = a >= b },
                else => {},
            },
            .int => |k| switch (o) {
                .mul => return .{ .dur = std.math.mul(i64, a, k) catch return null },
                else => {},
            },
            .instant => |b| if (o == .add) return .{ .instant = std.math.add(i64, b, a) catch return null },
            else => {},
        },
        .date => |a| switch (r) {
            .int => |k| switch (o) {
                .add => return dateIn(@as(i64, a) + k),
                .sub => return dateIn(@as(i64, a) - k),
                else => {},
            },
            .date => |b| switch (o) {
                .sub => return .{ .int = @as(i64, a) - b },
                .eq => return .{ .bool = a == b },
                .ne => return .{ .bool = a != b },
                .lt => return .{ .bool = a < b },
                .gt => return .{ .bool = a > b },
                .le => return .{ .bool = a <= b },
                .ge => return .{ .bool = a >= b },
                else => {},
            },
            else => {},
        },
        .time => |a| switch (r) {
            .time => |b| switch (o) {
                .sub => return .{ .dur = a - b },
                .eq => return .{ .bool = a == b },
                .ne => return .{ .bool = a != b },
                .lt => return .{ .bool = a < b },
                .gt => return .{ .bool = a > b },
                .le => return .{ .bool = a <= b },
                .ge => return .{ .bool = a >= b },
                else => {},
            },
            else => {},
        },
        else => {},
    }
    if (l == .int and r == .dur and o == .mul) return .{ .dur = std.math.mul(i64, r.dur, l.int) catch return null };
    return null;
}

fn dateIn(days: i64) ?Value {
    if (days < interp.calendar.min_days or days > interp.calendar.max_days) return null;
    return .{ .date = @intCast(days) };
}

/// Apply a binary operator to two values.
pub fn apply(it: *Interp, op: []const u8, l: Value, r: Value) Signal!Value {
    const eql = std.mem.eql;
    if ((eql(u8, op, "+") or eql(u8, op, "<+") or eql(u8, op, "+>")) and (it.isSecret(l) or it.isSecret(r))) {
        return it.fail("a Secret is not converted to a String: it can not be joined to a text (data-language.md#secrets)", .{});
    }
    if (l == .list and Interp.isScalar(r) and Interp.isBulkOp(op)) return it.broadcast(op, l.list, r);
    if (eql(u8, op, "==")) return .{ .bool = Interp.eq(l, r) };
    if (eql(u8, op, "<>")) return .{ .bool = !Interp.eq(l, r) };
    if (eql(u8, op, "<")) return .{ .bool = (try it.order(l, r)) == .lt };
    if (eql(u8, op, ">")) return .{ .bool = (try it.order(l, r)) == .gt };
    if (eql(u8, op, "<=")) return .{ .bool = (try it.order(l, r)) != .gt };
    if (eql(u8, op, ">=")) return .{ .bool = (try it.order(l, r)) != .lt };
    if (eql(u8, op, "xor")) return .{ .bool = (try it.truth(l)) != (try it.truth(r)) };
    if (eql(u8, op, "in")) return .{ .bool = try it.contains(r, l) };
    if (eql(u8, op, "not in")) return .{ .bool = !(try it.contains(r, l)) };
    if (eql(u8, op, "is")) return .{ .bool = it.isOp(l, r) };
    if (eql(u8, op, "is not")) return .{ .bool = !it.isOp(l, r) };
    if (eql(u8, op, "=~") or eql(u8, op, "!~")) {
        if (Interp.realOf(l)) |x| if (Interp.realOf(r)) |y| {
            const eps = Interp.realOf((it.scope.find("$epsilon") orelse return it.fail("$epsilon is missing", .{})).value) orelse 1e-9;
            return .{ .bool = (@abs(x - y) <= eps) == eql(u8, op, "=~") };
        };
        if (l != .str or r != .str) return it.fail("a regular expression match needs two strings", .{});
        return .{ .bool = Interp.regexMatch(r.str, l.str) == eql(u8, op, "=~") };
    }
    if (eql(u8, op, "||") or eql(u8, op, "&&")) return it.setOp(op[0], l, r);
    if (eql(u8, op, "<+")) {
        if (l == .str) return .{ .str = try it.persist2(l.str, try it.text(r)) };
        return it.concat(l, r);
    }
    if (eql(u8, op, "+>")) {
        if (r == .str) return .{ .str = try it.persist2(try it.text(l), r.str) };
        if (r == .list) {
            const out = try it.h.make(List, .{});
            try it.listAppend(out, l);
            try it.listAppendSlice(out, r.list.elems());
            return .{ .list = out };
        }
        return it.fail("+> needs a list or a string on the right, found {s}", .{Interp.typeName(r)});
    }
    if (l == .bytes or r == .bytes) if (try bytesfn.binary(it, op, l, r)) |v| return v;
    if (eql(u8, op, "+")) {
        if (Interp.textual(l) or Interp.textual(r)) return .{ .str = try it.persist2(try it.text(l), try it.text(r)) };
    }
    if (eql(u8, op, "-") and (l == .set or l == .list) and (r == .set or r == .list)) return it.setOp('-', l, r);
    if (eql(u8, op, "*") and l == .str and Interp.isInt(r)) {
        var buf: std.ArrayList(u8) = .empty;
        var k: i64 = 0;
        while (k < Interp.intOf(r)) : (k += 1) try buf.appendSlice(it.t, l.str);
        return .{ .str = try it.persist(buf.items) };
    }
    if (eql(u8, op, "><")) return it.product(l, r);
    if (eql(u8, op, "/") and l == .str and r == .str) return .{ .str = try it.persist(try dlib.joinPath(it, l.str, r.str)) }; // the operator / joins paths
    if (l == .dur or r == .dur or l == .date or r == .date or l == .time or r == .time or l == .dtm or r == .dtm or ((l == .instant or r == .instant) and op.len == 1 and (op[0] == '+' or op[0] == '-'))) return it.timeOp(op, l, r);
    if (l == .cpx or r == .cpx) return it.cpxOp(op, l, r);
    if (l == .rat or r == .rat) return it.ratOp(op, l, r);
    if (l == .dec or r == .dec) return it.decimalOp(op, l, r);
    // numbers
    if (Interp.realOf(l) == null or Interp.realOf(r) == null) {
        return it.fail("operator {s} does not apply to {s} and {s}", .{ op, Interp.typeName(l), Interp.typeName(r) });
    }
    if (eql(u8, op, "/")) {
        const d = Interp.realOf(r).?;
        if (d == 0) return it.failWith(err_divide, "Division by zero", .{});
        return .{ .real = Interp.realOf(l).? / d };
    }
    if (Interp.isInt(l) and Interp.isInt(r)) {
        const x = Interp.intOf(l);
        const y = Interp.intOf(r);
        if (eql(u8, op, "+")) {
            const s = @addWithOverflow(x, y);
            return if (s[1] != 0) it.overflow() else .{ .int = s[0] };
        }
        if (eql(u8, op, "-")) {
            const s = @subWithOverflow(x, y);
            return if (s[1] != 0) it.overflow() else .{ .int = s[0] };
        }
        if (eql(u8, op, "*")) {
            const s = @mulWithOverflow(x, y);
            return if (s[1] != 0) it.overflow() else .{ .int = s[0] };
        }
        if (eql(u8, op, "%")) {
            if (y == 0) return it.failWith(err_divide, "Division by zero", .{});
            return .{ .int = @mod(x, y) };
        }
        if (eql(u8, op, "^")) {
            if (y < 0) return .{ .real = std.math.pow(f64, @floatFromInt(x), @floatFromInt(y)) };
            var acc: i64 = 1;
            var k: i64 = 0;
            while (k < y) : (k += 1) {
                const s = @mulWithOverflow(acc, x);
                if (s[1] != 0) return it.overflow();
                acc = s[0];
            }
            return .{ .int = acc };
        }
        if (eql(u8, op, "<<") and y >= 0 and y < 63) return .{ .int = x << @intCast(y) };
        if (eql(u8, op, ">>") and y >= 0 and y < 63) return .{ .int = x >> @intCast(y) };
    } else {
        const x = Interp.realOf(l).?;
        const y = Interp.realOf(r).?;
        if (eql(u8, op, "+")) return .{ .real = x + y };
        if (eql(u8, op, "-")) return .{ .real = x - y };
        if (eql(u8, op, "*")) return .{ .real = x * y };
        if (eql(u8, op, "%")) return .{ .real = @mod(x, y) };
        if (eql(u8, op, "^")) return .{ .real = std.math.pow(f64, x, y) };
    }
    return it.fail("unknown operator {s}", .{op});
}

pub const isScalar = value.isScalar;

/// The operators that apply to every element of a list when the other operand is a scalar (D-118).
pub fn isBulkOp(op: []const u8) bool {
    inline for (.{ "+", "-", "*", "/", "%", "^", "<", ">", "<=", ">=", "=~" }) |o| {
        if (std.mem.eql(u8, op, o)) return true;
    }
    return false;
}

/// One element with a scalar. Arithmetic never builds a string: that needs a loop (D-118).
pub fn bulkOne(it: *Interp, op: []const u8, e: Value, s: Value) Signal!Value {
    const arithmetic = std.mem.indexOfScalar(u8, "+-*/%^", op[0]) != null and op.len == 1;
    if (arithmetic and (Interp.textual(e) or Interp.textual(s))) {
        return it.fail("operator {s} on a collection and a string is not possible: build a new collection with a loop", .{op});
    }
    return it.apply(op, e, s);
}

/// `list op scalar`: a new list with `op` applied to each element (D-118).
pub fn broadcast(it: *Interp, op: []const u8, src: *List, s: Value) Signal!Value {
    const out = try it.h.make(List, .{ .array = src.array });
    for (src.elems()) |e| try it.listAppend(out, try it.bulkOne(op, e, s));
    return .{ .list = out };
}

pub fn isOp(it: *Interp, l: Value, r: Value) bool {
    if (r == .class and r.class.trait) {
        for (it.adopted.items) |a| if (a.trait == r.class and std.mem.eql(u8, a.ty, Interp.typeName(l))) return true;
    }
    if (l == .typ and r == .typ) return std.mem.eql(u8, l.typ, r.typ);
    if (r == .typ) return std.mem.eql(u8, Interp.typeName(l), r.typ);
    if (r == .class and l == .object) {
        var cur: ?*Class = l.object.class;
        while (cur) |k| : (cur = k.parent) {
            if (k == r.class) return true;
            for (k.traits.items) |tr| if (tr == r.class) return true;
        }
        return false;
    }
    return Interp.same(l, r);
}

/// `||` union, `&&` intersection, `-` difference: the result is a DataSet.
pub fn setOp(it: *Interp, op: u8, l: Value, r: Value) Signal!Value {
    const a = try it.setOf(l);
    const b = try it.setOf(r);
    const out = try it.h.make(List, .{});
    for (a.items.items) |e| {
        const in_b = try it.contains(.{ .set = b }, e);
        if (op == '|' or (op == '&' and in_b) or (op == '-' and !in_b)) try it.setAdd(out, e);
    }
    if (op == '|') for (b.items.items) |e| try it.setAdd(out, e);
    return .{ .set = out };
}

/// `a <+ b` as an expression: a new list with the element or the list `b` added at the end.
pub fn concat(it: *Interp, l: Value, r: Value) Signal!Value {
    const src = switch (l) {
        .list, .set => |x| x,
        else => return it.fail("<+ needs a list on the left, found {s}", .{Interp.typeName(l)}),
    };
    const out = try it.h.make(List, .{ .array = src.array });
    try it.listAppendSlice(out, src.elems());
    if (r == .list) try it.listAppendSlice(out, r.list.elems()) else try it.listAppend(out, r);
    return .{ .list = out };
}

/// `A >< B`: the pairs (a, b) of two collections, as a list of lists.
pub fn product(it: *Interp, l: Value, r: Value) Signal!Value {
    const xs = try it.iterate(l);
    const ys = try it.iterate(r);
    const out = try it.h.make(List, .{});
    for (xs) |x| for (ys) |y| try it.listAppend(out, .{ .list = try it.newList(&.{ x, y }, false) });
    return .{ .list = out };
}
