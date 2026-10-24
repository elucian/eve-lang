//! @eve-module rational: the exact fraction behind the type Rational (`3\4`)
//! @spec spec/semantics/types.md#rational
//! @feature F-LNG-30
//! @decision D-214
//! @tests test/level3/c46_rational_literal, test/level3/c47_rational_arithmetic
//! A Rat is a numerator and a denominator of 64 bits, always in lowest terms with a positive denominator, so equal values have equal fields.
const std = @import("std");
const Io = std.Io;

pub const Rat = struct {
    n: i64,
    d: i64 = 1,
};

// @invariant every Rat made by this file has d > 0 and gcd(|n|, d) == 1; 0 is 0\1
// @perf hot
/// Binary GCD of two 64-bit numbers: shifts and subtractions, no division.
fn gcd64(a_in: u64, b_in: u64) u64 {
    var a = a_in;
    var b = b_in;
    if (a == 0) return b;
    if (b == 0) return a;
    const shift: u6 = @intCast(@ctz(a | b));
    a >>= @intCast(@ctz(a));
    while (b != 0) {
        b >>= @intCast(@ctz(b));
        if (a > b) std.mem.swap(u64, &a, &b);
        b -= a;
    }
    return a << shift;
}

fn gcd128(a_in: u128, b_in: u128) u128 {
    var a = a_in;
    var b = b_in;
    if (a == 0) return b;
    if (b == 0) return a;
    const shift: u7 = @intCast(@ctz(a | b));
    a >>= @intCast(@ctz(a));
    while (b != 0) {
        b >>= @intCast(@ctz(b));
        if (a > b) std.mem.swap(u128, &a, &b);
        b -= a;
    }
    return a << shift;
}

/// The GCD of the magnitude of a 128-bit number and a positive 64-bit number: one remainder, then the 64-bit loop.
fn gcdWide(a: u128, b: u64) u64 {
    if (a <= std.math.maxInt(u64)) return gcd64(@intCast(a), b);
    return gcd64(@intCast(a % b), b);
}

fn fits(nn: i128, dd: i128) ?Rat {
    if (nn > std.math.maxInt(i64) or nn < std.math.minInt(i64) or dd > std.math.maxInt(i64)) return null;
    return .{ .n = @intCast(nn), .d = @intCast(dd) };
}

// @perf hot
/// `n / d` in lowest terms; null when the denominator is zero or the result does not fit in 64 bits.
pub fn make(n: i128, d: i128) ?Rat {
    if (d == 0) return null;
    var nn = n;
    var dd = d;
    if (dd < 0) {
        nn = -nn;
        dd = -dd;
    }
    if (dd != 1) {
        const mag = @abs(nn);
        const g: u128 = if (dd <= std.math.maxInt(u64)) gcdWide(mag, @intCast(dd)) else gcd128(mag, @intCast(dd));
        if (g > 1) {
            nn = @divExact(nn, @as(i128, @intCast(g)));
            dd = @divExact(dd, @as(i128, @intCast(g)));
        }
    }
    return fits(nn, dd);
}

pub fn fromInt(n: i64) Rat {
    return .{ .n = n, .d = 1 };
}

// @eve-impl a/b + c/d with g = gcd(b, d) (Knuth 4.5.1): when g is 1 the result is already in lowest terms; otherwise gcd(t, g) is the only other one
// @perf hot
fn addSigned(a: Rat, b: Rat, sign: i128) ?Rat {
    if (a.d == b.d) {
        const t = @as(i128, a.n) + sign * b.n;
        if (a.d == 1) return fits(t, 1);
        const g = gcdWide(@abs(t), @intCast(a.d));
        if (g <= 1) return fits(t, a.d);
        return fits(@divExact(t, @as(i128, g)), @divExact(@as(i128, a.d), @as(i128, g)));
    }
    const g = gcd64(@intCast(a.d), @intCast(b.d));
    const ad: i128 = @divExact(a.d, @as(i64, @intCast(g)));
    const bd: i128 = @divExact(b.d, @as(i64, @intCast(g)));
    const t = @as(i128, a.n) * bd + sign * @as(i128, b.n) * ad;
    const den: i128 = ad * b.d;
    if (g == 1) return fits(t, den);
    const g2 = gcdWide(@abs(t), @intCast(g));
    if (g2 <= 1) return fits(t, den);
    return fits(@divExact(t, @as(i128, g2)), @divExact(den, @as(i128, g2)));
}

// @perf hot
pub fn add(a: Rat, b: Rat) ?Rat {
    return addSigned(a, b, 1);
}

// @perf hot
pub fn sub(a: Rat, b: Rat) ?Rat {
    return addSigned(a, b, -1);
}

// @eve-impl a/b * c/d with the cross reduction gcd(a, d) and gcd(c, b): the product is in lowest terms and stays small
// @perf hot
pub fn mul(a: Rat, b: Rat) ?Rat {
    if (a.d == 1 and b.d == 1) return fits(@as(i128, a.n) * b.n, 1);
    const g1: i64 = @intCast(gcd64(@abs(a.n), @intCast(b.d)));
    const g2: i64 = @intCast(gcd64(@abs(b.n), @intCast(a.d)));
    const n = @as(i128, @divExact(a.n, g1)) * @divExact(b.n, g2);
    const d = @as(i128, @divExact(a.d, g2)) * @divExact(b.d, g1);
    return fits(n, d);
}

/// `a / b`; null when `b` is zero or the result does not fit.
pub fn div(a: Rat, b: Rat) ?Rat {
    if (b.n == 0) return null;
    // a * (1 / b), with the sign moved to the numerator
    const inv: Rat = if (b.n < 0) .{ .n = std.math.negate(b.d) catch return null, .d = std.math.negate(b.n) catch return null } else .{ .n = b.d, .d = b.n };
    return mul(a, inv);
}

pub fn neg(a: Rat) ?Rat {
    return make(-@as(i128, a.n), a.d);
}

pub fn reciprocal(a: Rat) ?Rat {
    return make(a.d, a.n);
}

// @perf hot
pub fn order(a: Rat, b: Rat) std.math.Order {
    if (a.d == b.d) return std.math.order(a.n, b.n);
    return std.math.order(@as(i128, a.n) * b.d, @as(i128, b.n) * a.d);
}

pub fn toF64(a: Rat) f64 {
    return @as(f64, @floatFromInt(a.n)) / @as(f64, @floatFromInt(a.d));
}

/// The largest whole number not above `a`.
pub fn floor(a: Rat) i64 {
    return @divFloor(a.n, a.d);
}

/// The smallest whole number not below `a`.
pub fn ceiling(a: Rat) i64 {
    return -@divFloor(-a.n, a.d);
}

/// The nearest whole number; halves go away from zero.
pub fn round(a: Rat) i64 {
    const twice: i128 = @as(i128, a.n) * 2 + (if (a.n < 0) -@as(i128, a.d) else @as(i128, a.d));
    return @intCast(@divTrunc(twice, @as(i128, a.d) * 2));
}

/// `a` to a whole power (negative powers invert); null when it does not fit or `a` is zero with a negative power.
pub fn pow(a: Rat, e: i64) ?Rat {
    var base = a;
    var k: u64 = @abs(e);
    if (e < 0) base = reciprocal(a) orelse return null;
    var result = fromInt(1);
    while (k > 0) : (k >>= 1) {
        if (k & 1 == 1) result = mul(result, base) orelse return null;
        if (k > 1) base = mul(base, base) orelse return null;
    }
    return result;
}

// @eve-impl best rational approximation with a bounded denominator: the last convergent, or the semiconvergent that is closer to x (Stern-Brocot / continued fractions)
/// The fraction nearest to `x` whose denominator is at most `max_den`; null for NaN, infinity, a huge `x` or `max_den` below 1.
pub fn fromF64(x: f64, max_den: i64) ?Rat {
    if (!std.math.isFinite(x) or max_den < 1) return null;
    const negative = x < 0;
    const ax = @abs(x);
    if (ax > 9.0e18) return null;
    var v = ax;
    var h0: i128 = 0;
    var h1: i128 = 1;
    var k0: i128 = 1;
    var k1: i128 = 0;
    var i: usize = 0;
    while (i < 64) : (i += 1) {
        const a: i128 = @intFromFloat(@floor(v));
        const h2 = a * h1 + h0;
        const k2 = a * k1 + k0;
        if (k2 > max_den or h2 > std.math.maxInt(i64)) {
            // the semiconvergent with the largest multiplier m that keeps the denominator in range
            if (k1 > 0) {
                const m: i128 = @divFloor(max_den - k0, k1);
                if (m >= 1) {
                    const hs = m * h1 + h0;
                    const ks = m * k1 + k0;
                    const err_conv = @abs(ax - @as(f64, @floatFromInt(h1)) / @as(f64, @floatFromInt(k1)));
                    const err_semi = @abs(ax - @as(f64, @floatFromInt(hs)) / @as(f64, @floatFromInt(ks)));
                    if (err_semi <= err_conv and hs <= std.math.maxInt(i64)) {
                        h1 = hs;
                        k1 = ks;
                    }
                }
            } else {
                // the integer part itself is above the limit of the loop: the nearest whole number
                h1 = @intFromFloat(@round(ax));
                k1 = 1;
            }
            break;
        }
        h0 = h1;
        h1 = h2;
        k0 = k1;
        k1 = k2;
        const frac = v - @floor(v);
        if (frac < 1e-15) break;
        v = 1.0 / frac;
    }
    if (k1 == 0) return make(0, 1);
    return make(if (negative) -h1 else h1, k1);
}

/// Read `3\4`, `-3\4` or `7` (a whole number is a fraction over 1).
pub fn parse(text: []const u8) ?Rat {
    const cut = std.mem.indexOfAny(u8, text, "\\/");
    const n = std.fmt.parseInt(i64, if (cut) |c| text[0..c] else text, 10) catch return null;
    const d = if (cut) |c| (std.fmt.parseInt(i64, text[c + 1 ..], 10) catch return null) else 1;
    return make(n, d);
}

/// `3\4`; a whole number is written without the denominator.
pub fn write(w: *Io.Writer, a: Rat) Io.Writer.Error!void {
    if (a.d == 1) return w.print("{d}", .{a.n});
    try w.print("{d}\\{d}", .{ a.n, a.d });
}

test "spec: types.md#rational lowest terms and signs" {
    const t = std.testing;
    const h = make(6, -8).?;
    try t.expectEqual(@as(i64, -3), h.n);
    try t.expectEqual(@as(i64, 4), h.d);
    try t.expectEqual(@as(?Rat, null), make(1, 0));
    try t.expectEqual(fromInt(0), make(0, -5).?);
}

test "spec: types.md#rational arithmetic is exact" {
    const t = std.testing;
    const third = make(1, 3).?;
    const sum = add(add(third, third).?, third).?;
    try t.expectEqual(fromInt(1), sum);
    try t.expectEqual(make(5, 6).?, add(make(1, 2).?, third).?);
    try t.expectEqual(make(1, 6).?, sub(make(1, 2).?, third).?);
    try t.expectEqual(make(2, 9).?, mul(make(2, 3).?, third).?);
    try t.expectEqual(make(9, 2).?, div(make(3, 2).?, third).?);
    try t.expectEqual(@as(?Rat, null), div(third, fromInt(0)));
    try t.expectEqual(std.math.Order.lt, order(third, make(1, 2).?));
}

test "spec: types.md#rational rounding" {
    const t = std.testing;
    try t.expectEqual(@as(i64, -2), floor(make(-3, 2).?));
    try t.expectEqual(@as(i64, -1), ceiling(make(-3, 2).?));
    try t.expectEqual(@as(i64, 2), round(make(3, 2).?));
    try t.expectEqual(@as(i64, -2), round(make(-3, 2).?));
    try t.expectEqual(@as(i64, 1), round(make(4, 3).?));
}

test "spec: types.md#rational power and overflow" {
    const t = std.testing;
    try t.expectEqual(make(8, 27).?, pow(make(2, 3).?, 3).?);
    try t.expectEqual(make(27, 8).?, pow(make(2, 3).?, -3).?);
    try t.expectEqual(@as(?Rat, null), pow(fromInt(10), 30));
    try t.expectEqual(@as(?Rat, null), pow(fromInt(0), -1));
}

test "spec: types.md#rational from a real by continued fractions" {
    const t = std.testing;
    try t.expectEqual(make(1, 3).?, fromF64(0.3333333333333333, 1000).?);
    try t.expectEqual(make(355, 113).?, fromF64(3.14159265358979, 113).?);
    try t.expectEqual(make(-5, 2).?, fromF64(-2.5, 10).?);
}

// @test the fast paths (gcd first, cross reduction) give the same answers as the plain formula reduced by `make`
test "spec: types.md#rational random operands agree with the plain formula" {
    var prng = std.Random.DefaultPrng.init(0x5eed);
    const rnd = prng.random();
    var checked: usize = 0;
    for (0..200_000) |i| {
        const big = i % 5 == 0;
        const span: i64 = if (big) 3_000_000_000 else 400;
        const a = make(rnd.intRangeAtMost(i64, -span, span), rnd.intRangeAtMost(i64, 1, span)) orelse continue;
        const b = make(rnd.intRangeAtMost(i64, -span, span), rnd.intRangeAtMost(i64, 1, span)) orelse continue;
        const sum = make(@as(i128, a.n) * b.d + @as(i128, b.n) * a.d, @as(i128, a.d) * b.d);
        const dif = make(@as(i128, a.n) * b.d - @as(i128, b.n) * a.d, @as(i128, a.d) * b.d);
        const prod = make(@as(i128, a.n) * b.n, @as(i128, a.d) * b.d);
        try std.testing.expectEqual(sum, add(a, b));
        try std.testing.expectEqual(dif, sub(a, b));
        try std.testing.expectEqual(prod, mul(a, b));
        if (b.n != 0) {
            const q = if (b.n < 0) make(-@as(i128, a.n) * b.d, -@as(i128, a.d) * b.n) else make(@as(i128, a.n) * b.d, @as(i128, a.d) * b.n);
            try std.testing.expectEqual(q, div(a, b));
        }
        if (sum) |s| {
            try std.testing.expect(s.d > 0 and gcd64(@abs(s.n), @intCast(s.d)) == 1 or s.n == 0 and s.d == 1);
        }
        checked += 1;
    }
    try std.testing.expect(checked > 150_000);
}

test "spec: types.md#rational extremes do not trap" {
    const t = std.testing;
    const lo = fromInt(std.math.minInt(i64));
    const hi = fromInt(std.math.maxInt(i64));
    try t.expectEqual(@as(?Rat, null), add(hi, hi));
    try t.expectEqual(@as(?Rat, null), neg(lo));
    try t.expectEqual(@as(?Rat, null), mul(lo, fromInt(2)));
    try t.expectEqual(fromInt(-1), add(lo, hi));
    try t.expectEqual(@as(?Rat, null), div(lo, fromInt(-1)));
    try t.expectEqual(make(1, std.math.maxInt(i64)).?, div(fromInt(1), hi).?);
    try t.expectEqual(std.math.Order.lt, order(lo, hi));
}

test "spec: types.md#rational from a real: the nearest fraction with a bounded denominator" {
    const t = std.testing;
    try t.expectEqual(make(1, 2).?, fromF64(0.5, 2).?);
    try t.expectEqual(make(22, 7).?, fromF64(3.14159265358979, 7).?);
    try t.expectEqual(make(3, 1).?, fromF64(3.14159265358979, 1).?);
    try t.expectEqual(make(1, 3).?, fromF64(0.34, 3).?);
    try t.expectEqual(make(2, 5).?, fromF64(0.4, 5).?);
    try t.expectEqual(make(7, 10).?, fromF64(0.7, 10).?);
    try t.expectEqual(make(1, 1).?, fromF64(0.5, 1).?);
    try t.expectEqual(make(0, 1).?, fromF64(0.0, 5).?);
    try t.expectEqual(@as(?Rat, null), fromF64(std.math.inf(f64), 5));
}
