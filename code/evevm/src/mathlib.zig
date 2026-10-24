//! @eve-module mathlib: native functions of the library `math` (modules basic, explog, trig, numtheory)
//! @spec spec/library/math.md
//! @feature F-LIB-03
//! @decision D-214
//! @tests test/level1/a110_math_basic, test/level1/a111_math_trig
//! Handler of type `dlib.Native`, registered in `dlib.natives` under the module names `math`, `basic`, `explog`, `trig` and `numtheory`. Signatures: lib/math.eve, lib/math/*.eve.
const std = @import("std");
const ast = @import("evecm").ast;
const decimal = @import("evecm").decimal;
const rational = @import("evecm").rational;
const interp = @import("interp.zig");

const Node = ast.Node;
const Interp = interp.Interp;
const Value = interp.Value;
const Signal = interp.Signal;
const err_argument = interp.err_argument;
const err_divide = interp.err_divide;
const err_overflow = interp.err_overflow;

const Fn = enum {
    abs, sign, min, max, clamp, pow, sqrt, cbrt, hypot, div, mod, divmod, gcd, lcm,
    exp, log, log2, log10,
    sin, cos, tan, asin, acos, atan, atan2, sinh, cosh, tanh, radians, degrees,
    is_prime, factors, mod_pow,
};

fn isNumber(v: Value) bool {
    return Interp.isInt(v) or v == .real or v == .float or v == .dec or v == .rat;
}

fn arg(it: *Interp, args: []const Value, i: usize, what: []const u8) Signal!Value {
    if (args.len <= i) return it.failWith(err_argument, "math.{s}: argument {d} is missing", .{ what, i + 1 });
    const v = args[i];
    if (!isNumber(v)) return it.failWith(err_argument, "math.{s}: argument {d} is a number, found {s}", .{ what, i + 1, Interp.typeName(v) });
    return v;
}

fn intArg(it: *Interp, args: []const Value, i: usize, what: []const u8) Signal!i64 {
    const v = try arg(it, args, i, what);
    if (!Interp.isInt(v)) return it.failWith(err_argument, "math.{s}: argument {d} is a whole number", .{ what, i + 1 });
    return Interp.intOf(v);
}

fn real(v: Value) f64 {
    return switch (v) {
        .real, .float => |x| x,
        .dec => |d| decimal.toF64(d),
        .rat => |q| rational.toF64(q),
        else => @floatFromInt(Interp.intOf(v)),
    };
}

fn realArg(it: *Interp, args: []const Value, i: usize, what: []const u8) Signal!f64 {
    return real(try arg(it, args, i, what));
}

// @eve-impl a Real result must be finite: infinity is `$err_overflow`, NaN `$err_argument` (no function gives them silently)
fn finite(it: *Interp, x: f64, what: []const u8) Signal!Value {
    if (std.math.isNan(x)) return it.failWith(err_argument, "math.{s}: the argument is outside the domain", .{what});
    if (std.math.isInf(x)) return it.failWith(err_overflow, "math.{s}: the result is out of range", .{what});
    return .{ .real = x };
}

fn order(a: Value, b: Value) std.math.Order {
    if (Interp.isInt(a) and Interp.isInt(b)) return std.math.order(Interp.intOf(a), Interp.intOf(b));
    if (a == .dec and b == .dec) return decimal.order(a.dec, b.dec);
    if (a == .rat or b == .rat) if (Interp.ratOf(a)) |x| if (Interp.ratOf(b)) |y| return rational.order(x, y);
    return std.math.order(real(a), real(b));
}

fn floorDiv(a: i64, b: i64) i64 {
    return @divFloor(a, b);
}

fn gcdOf(a: i64, b: i64) i64 {
    var x: u64 = @abs(a);
    var y: u64 = @abs(b);
    while (y != 0) {
        const t = x % y;
        x = y;
        y = t;
    }
    return @intCast(x);
}

fn mulMod(a: u64, b: u64, m: u64) u64 {
    return @intCast((@as(u128, a) * b) % m);
}

fn powMod(base: u64, exp: u64, m: u64) u64 {
    var result: u64 = 1 % m;
    var b = base % m;
    var e = exp;
    while (e > 0) : (e >>= 1) {
        if (e & 1 == 1) result = mulMod(result, b, m);
        b = mulMod(b, b, m);
    }
    return result;
}

// @eve-impl deterministic Miller-Rabin: these bases decide every 64-bit number
fn isPrime(n: u64) bool {
    if (n < 2) return false;
    const bases = [_]u64{ 2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37 };
    for (bases) |p| {
        if (n == p) return true;
        if (n % p == 0) return false;
    }
    var d = n - 1;
    var r: u32 = 0;
    while (d & 1 == 0) : (d >>= 1) r += 1;
    outer: for (bases) |a| {
        var x = powMod(a, d, n);
        if (x == 1 or x == n - 1) continue;
        var i: u32 = 1;
        while (i < r) : (i += 1) {
            x = mulMod(x, x, n);
            if (x == n - 1) continue :outer;
        }
        return false;
    }
    return true;
}

// @eve-fn basic.abs, basic.sign, basic.min, basic.max, basic.clamp, basic.pow, basic.sqrt, basic.cbrt, basic.hypot, basic.div, basic.mod, basic.divmod, basic.gcd, basic.lcm
// @eve-fn explog.exp, explog.log, explog.log2, explog.log10
// @eve-fn trig.sin, trig.cos, trig.tan, trig.asin, trig.acos, trig.atan, trig.atan2, trig.sinh, trig.cosh, trig.tanh, trig.radians, trig.degrees
// @eve-fn numtheory.is_prime, numtheory.factors, numtheory.mod_pow
// @spec spec/library/math.md
// @feature F-LIB-03
// @perf hot
/// The function `f` of the module on values already evaluated: the body of the call, shared by the node entry and the fast path of a call.
fn compute(it: *Interp, f: Fn, args: []const Value) Signal!?Value {
    const n = @tagName(f);
    switch (f) {
        .abs => {
            if (args.len != 1) return it.failWith(err_argument, "math.abs takes one number", .{});
            // evaluated once: a Complex gives its modulus (types.md#complex), any other value must be a number
            const v = args[0];
            if (v == .cpx) return try finite(it, @import("evecm").complex.abs(v.cpx), n);
            if (!isNumber(v)) return it.failWith(err_argument, "math.abs: argument 1 is a number, found {s}", .{Interp.typeName(v)});
            if (Interp.isInt(v)) {
                const x = Interp.intOf(v);
                if (x == std.math.minInt(i64)) return it.failWith(err_overflow, "math.abs: the result does not fit", .{});
                return .{ .int = if (x < 0) -x else x };
            }
            if (v == .dec) return .{ .dec = decimal.neg(v.dec) orelse v.dec };
            if (v == .rat) return .{ .rat = if (v.rat.n < 0) (rational.neg(v.rat) orelse return it.failWith(err_overflow, "math.abs: the result does not fit", .{})) else v.rat };
            return .{ .real = @abs(real(v)) };
        },
        .sign => {
            const v = try arg(it, args, 0, n);
            return .{ .int = switch (order(v, .{ .int = 0 })) {
                .lt => -1,
                .eq => 0,
                .gt => 1,
            } };
        },
        .min, .max => {
            const a = try arg(it, args, 0, n);
            const b = try arg(it, args, 1, n);
            const o = order(a, b);
            return if (f == .min) (if (o == .gt) b else a) else (if (o == .lt) b else a);
        },
        .clamp => {
            const x = try arg(it, args, 0, n);
            const lo = try arg(it, args, 1, n);
            const hi = try arg(it, args, 2, n);
            if (order(lo, hi) == .gt) return it.failWith(err_argument, "math.clamp: low is greater than high", .{});
            if (order(x, lo) == .lt) return lo;
            if (order(x, hi) == .gt) return hi;
            return x;
        },
        .pow => {
            const x = try arg(it, args, 0, n);
            const e = try arg(it, args, 1, n);
            if (x == .rat and Interp.isInt(e)) {
                if (x.rat.n == 0 and Interp.intOf(e) < 0) return it.failWith(err_divide, "math.pow: zero to a negative power", .{});
                return .{ .rat = rational.pow(x.rat, Interp.intOf(e)) orelse return it.failWith(err_overflow, "math.pow: the result does not fit", .{}) };
            }
            if (Interp.isInt(e) and Interp.intOf(e) >= 0 and (Interp.isInt(x) or x == .dec)) {
                var k = Interp.intOf(e);
                if (Interp.isInt(x)) {
                    var result: i64 = 1;
                    const b = Interp.intOf(x);
                    while (k > 0) : (k -= 1) result = std.math.mul(i64, result, b) catch return it.failWith(err_overflow, "math.pow: the result does not fit", .{});
                    return .{ .int = result };
                }
                var result = decimal.fromInt(1).?;
                while (k > 0) : (k -= 1) result = decimal.mul(result, x.dec) orelse return it.failWith(err_overflow, "math.pow: the result does not fit", .{});
                return .{ .dec = result };
            }
            const b = real(x);
            const p = real(e);
            if (b == 0 and p < 0) return it.failWith(err_divide, "math.pow: zero to a negative power", .{});
            if (b < 0 and p != @floor(p)) return it.failWith(err_argument, "math.pow: a negative base needs a whole exponent", .{});
            return try finite(it, std.math.pow(f64, b, p), n);
        },
        .sqrt => {
            const x = try realArg(it, args, 0, n);
            if (x < 0) return it.failWith(err_argument, "math.sqrt: the argument is negative", .{});
            return .{ .real = @sqrt(x) };
        },
        .cbrt => return .{ .real = std.math.cbrt(try realArg(it, args, 0, n)) },
        .hypot => return try finite(it, std.math.hypot(try realArg(it, args, 0, n), try realArg(it, args, 1, n)), n),
        .div, .mod, .divmod => {
            const a = try intArg(it, args, 0, n);
            const b = try intArg(it, args, 1, n);
            if (b == 0) return it.failWith(err_divide, "math.{s}: division by zero", .{n});
            if (a == std.math.minInt(i64) and b == -1) return it.failWith(err_overflow, "math.{s}: the result does not fit", .{n});
            const q = floorDiv(a, b);
            const r = a - q * b;
            if (f == .div) return .{ .int = q };
            if (f == .mod) return .{ .int = r };
            return .{ .list = try it.newList(&.{ .{ .int = q }, .{ .int = r } }, false) };
        },
        .gcd, .lcm => {
            const a = try intArg(it, args, 0, n);
            const b = try intArg(it, args, 1, n);
            const g = gcdOf(a, b);
            if (f == .gcd) return .{ .int = g };
            if (g == 0) return .{ .int = 0 };
            const l = std.math.mul(i64, @divExact(a, g), b) catch return it.failWith(err_overflow, "math.lcm: the result does not fit", .{});
            if (l == std.math.minInt(i64)) return it.failWith(err_overflow, "math.lcm: the result does not fit", .{});
            return .{ .int = if (l < 0) -l else l };
        },
        .exp => return try finite(it, @exp(try realArg(it, args, 0, n)), n),
        .log => {
            const x = try realArg(it, args, 0, n);
            if (x <= 0) return it.failWith(err_argument, "math.log: the argument is zero or negative", .{});
            if (args.len == 1) return .{ .real = @log(x) };
            const base = try realArg(it, args, 1, n);
            if (base <= 0 or base == 1) return it.failWith(err_argument, "math.log: the base is zero, negative or one", .{});
            return .{ .real = @log(x) / @log(base) };
        },
        .log2, .log10 => {
            const x = try realArg(it, args, 0, n);
            if (x <= 0) return it.failWith(err_argument, "math.{s}: the argument is zero or negative", .{n});
            return .{ .real = if (f == .log2) @log2(x) else @log10(x) };
        },
        .sin => return try finite(it, @sin(try realArg(it, args, 0, n)), n),
        .cos => return try finite(it, @cos(try realArg(it, args, 0, n)), n),
        .tan => return try finite(it, @tan(try realArg(it, args, 0, n)), n),
        .asin, .acos => {
            const x = try realArg(it, args, 0, n);
            if (x < -1 or x > 1) return it.failWith(err_argument, "math.{s}: the argument is outside -1 .. 1", .{n});
            return .{ .real = if (f == .asin) std.math.asin(x) else std.math.acos(x) };
        },
        .atan => return .{ .real = std.math.atan(try realArg(it, args, 0, n)) },
        .atan2 => return .{ .real = std.math.atan2(try realArg(it, args, 0, n), try realArg(it, args, 1, n)) },
        .sinh => return try finite(it, std.math.sinh(try realArg(it, args, 0, n)), n),
        .cosh => return try finite(it, std.math.cosh(try realArg(it, args, 0, n)), n),
        .tanh => return .{ .real = std.math.tanh(try realArg(it, args, 0, n)) },
        .radians => return .{ .real = try realArg(it, args, 0, n) * (std.math.pi / 180.0) },
        .degrees => return .{ .real = try realArg(it, args, 0, n) * (180.0 / std.math.pi) },
        .is_prime => {
            const x = try intArg(it, args, 0, n);
            return .{ .bool = x >= 2 and isPrime(@intCast(x)) };
        },
        .factors => {
            var x = try intArg(it, args, 0, n);
            if (x < 2) return it.failWith(err_argument, "math.factors: the argument is less than 2", .{});
            var out: std.ArrayList(Value) = .empty;
            defer out.deinit(it.a);
            var p: i64 = 2;
            while (p <= x and p <= 3037000499 and @as(i128, p) * p <= x) {
                while (@mod(x, p) == 0) : (x = @divExact(x, p)) try out.append(it.a, .{ .int = p });
                p += if (p == 2) 1 else 2;
            }
            if (x > 1) try out.append(it.a, .{ .int = x });
            return .{ .list = try it.newList(out.items, false) };
        },
        .mod_pow => {
            const b = try intArg(it, args, 0, n);
            const e = try intArg(it, args, 1, n);
            const m = try intArg(it, args, 2, n);
            if (e < 0 or m <= 0) return it.failWith(err_argument, "math.mod_pow: the exponent is negative or the modulus is not positive", .{});
            const base: u64 = @intCast(@mod(b, m));
            return .{ .int = @intCast(powMod(base, @intCast(e), @intCast(m))) };
        },
    }
}

/// The entry of `dlib.natives`: evaluates the argument nodes, then computes.
pub fn mathModule(it: *Interp, name: []const u8, _: []const *const Node, arg_nodes: []const *const Node) Signal!?Value {
    const f = std.meta.stringToEnum(Fn, name) orelse return null;
    var buf: [4]Value = undefined;
    if (arg_nodes.len > buf.len) return it.failWith(err_argument, "math.{s}: too many arguments", .{name});
    for (arg_nodes, 0..) |nd, i| buf[i] = try it.eval(nd);
    return compute(it, f, buf[0..arg_nodes.len]);
}

// @eve-impl the call of a library function from `invokeWith` without a scope: the id is the position of the name in `Fn`
// @see code/evevm/src/dlib.zig:fastResolve
pub fn fastId(name: []const u8) ?u16 {
    const f = std.meta.stringToEnum(Fn, name) orelse return null;
    return @intFromEnum(f);
}

// @perf hot
pub fn fastCall(it: *Interp, id: u16, args: []const Value) Signal!Value {
    return (try compute(it, @enumFromInt(id), args)).?;
}

test "spec: math.md#module-numtheory primality and modular power" {
    try std.testing.expect(isPrime(2147483647));
    try std.testing.expect(!isPrime(2147483649));
    try std.testing.expectEqual(@as(u64, 24), powMod(2, 10, 1000));
}
