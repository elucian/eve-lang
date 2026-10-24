//! @eve-module complex: the number behind the type Complex (`(10 + i99)`)
//! @spec spec/semantics/types.md#complex
//! @feature F-LNG-31
//! @decision D-214
//! @tests test/level3/c50_complex_literal, test/level3/c51_complex_arithmetic
//! A Cpx is a real part and an imaginary part, two f64. No operation gives NaN or an infinity: the caller reports `$err_overflow` or `$err_argument`.
const std = @import("std");
const Io = std.Io;

pub const Cpx = struct {
    re: f64,
    im: f64 = 0,
};

pub fn fromReal(x: f64) Cpx {
    return .{ .re = x, .im = 0 };
}

pub fn finite(z: Cpx) bool {
    return std.math.isFinite(z.re) and std.math.isFinite(z.im);
}

pub fn eql(a: Cpx, b: Cpx) bool {
    return a.re == b.re and a.im == b.im;
}

// @perf hot
pub fn add(a: Cpx, b: Cpx) Cpx {
    return .{ .re = a.re + b.re, .im = a.im + b.im };
}

// @perf hot
pub fn sub(a: Cpx, b: Cpx) Cpx {
    return .{ .re = a.re - b.re, .im = a.im - b.im };
}

// @perf hot
pub fn mul(a: Cpx, b: Cpx) Cpx {
    return .{ .re = a.re * b.re - a.im * b.im, .im = a.re * b.im + a.im * b.re };
}

/// `a / b` by Smith's method (no overflow in the middle for large parts); the caller has checked that `b` is not zero.
pub fn div(a: Cpx, b: Cpx) Cpx {
    if (@abs(b.re) >= @abs(b.im)) {
        const r = b.im / b.re;
        const d = b.re + b.im * r;
        return .{ .re = (a.re + a.im * r) / d, .im = (a.im - a.re * r) / d };
    }
    const r = b.re / b.im;
    const d = b.re * r + b.im;
    return .{ .re = (a.re * r + a.im) / d, .im = (a.im * r - a.re) / d };
}

pub fn neg(a: Cpx) Cpx {
    return .{ .re = -a.re, .im = -a.im };
}

pub fn conj(a: Cpx) Cpx {
    return .{ .re = a.re, .im = -a.im };
}

/// The modulus.
pub fn abs(a: Cpx) f64 {
    return std.math.hypot(a.re, a.im);
}

/// The argument in (-pi, pi]; 0 for zero.
pub fn arg(a: Cpx) f64 {
    return std.math.atan2(a.im, a.re);
}

pub fn polar(r: f64, theta: f64) Cpx {
    return .{ .re = r * @cos(theta), .im = r * @sin(theta) };
}

pub fn exp(a: Cpx) Cpx {
    const e = @exp(a.re);
    return .{ .re = e * @cos(a.im), .im = e * @sin(a.im) };
}

/// The principal logarithm; the caller has checked that `a` is not zero.
pub fn log(a: Cpx) Cpx {
    return .{ .re = @log(abs(a)), .im = arg(a) };
}

/// The principal square root (real part not negative).
pub fn sqrt(a: Cpx) Cpx {
    if (a.re == 0 and a.im == 0) return .{ .re = 0, .im = 0 };
    const m = abs(a);
    const re = @sqrt((m + a.re) / 2);
    const im = @sqrt((m - a.re) / 2);
    return .{ .re = re, .im = if (a.im < 0) -im else im };
}

/// `a` to a whole power by repeated squaring (exact for small Gaussian integers); the caller has checked `a` is not zero for a negative power.
pub fn powInt(a: Cpx, e: i64) Cpx {
    var k: u64 = @abs(e);
    var base = a;
    var result = fromReal(1);
    while (k > 0) : (k >>= 1) {
        if (k & 1 == 1) result = mul(result, base);
        if (k > 1) base = mul(base, base);
    }
    return if (e < 0) div(fromReal(1), result) else result;
}

/// `a` to the power `b` by exp(b log a); `0` to a positive power is `0`, the caller rejects the rest of the zero cases.
pub fn pow(a: Cpx, b: Cpx) Cpx {
    if (a.re == 0 and a.im == 0) return fromReal(0);
    return exp(mul(b, log(a)));
}

/// `(10 + i99)`: the form of the literal; the real part first, the sign of the imaginary part between the two.
pub fn write(w: *Io.Writer, a: Cpx) Io.Writer.Error!void {
    const negative = a.im < 0 or (a.im == 0 and std.math.signbit(a.im));
    // `+ 0.0` turns a negative zero into 0: `-i2` prints `(0 - i2)`
    try w.print("({d} {s} i{d})", .{ a.re + 0.0, if (negative) "-" else "+", @abs(a.im) });
}

test "spec: types.md#complex field arithmetic" {
    const t = std.testing;
    const a: Cpx = .{ .re = 1, .im = 2 };
    const b: Cpx = .{ .re = 3, .im = -1 };
    try t.expect(eql(add(a, b), .{ .re = 4, .im = 1 }));
    try t.expect(eql(sub(a, b), .{ .re = -2, .im = 3 }));
    try t.expect(eql(mul(a, b), .{ .re = 5, .im = 5 }));
    const q = div(mul(a, b), b);
    try t.expectApproxEqAbs(@as(f64, 1), q.re, 1e-12);
    try t.expectApproxEqAbs(@as(f64, 2), q.im, 1e-12);
    try t.expect(eql(powInt(.{ .re = 0, .im = 1 }, 2), .{ .re = -1, .im = 0 }));
    try t.expect(eql(powInt(.{ .re = 1, .im = 1 }, 4), .{ .re = -4, .im = 0 }));
}

test "spec: types.md#complex functions" {
    const t = std.testing;
    const e = exp(.{ .re = 0, .im = std.math.pi });
    try t.expectApproxEqAbs(@as(f64, -1), e.re, 1e-12);
    try t.expectApproxEqAbs(@as(f64, 0), e.im, 1e-12);
    const s = sqrt(.{ .re = -4, .im = 0 });
    try t.expectApproxEqAbs(@as(f64, 0), s.re, 1e-12);
    try t.expectApproxEqAbs(@as(f64, 2), s.im, 1e-12);
    try t.expectApproxEqAbs(@as(f64, 5), abs(.{ .re = 3, .im = 4 }), 1e-12);
    const l = log(.{ .re = -1, .im = 0 });
    try t.expectApproxEqAbs(std.math.pi, l.im, 1e-12);
}

test "spec: types.md#complex printing" {
    var aw: Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try write(&aw.writer, .{ .re = 10, .im = 99 });
    try aw.writer.writeAll("|");
    try write(&aw.writer, .{ .re = -1.5, .im = -2 });
    try std.testing.expectEqualStrings("(10 + i99)|(-1.5 - i2)", aw.written());
}
