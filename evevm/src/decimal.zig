//! `Decimal`: exact base 10 numbers that keep their scale (spec/library/data-language.md#decimal-and-optional-types).
//! A value is an integer `m` and a scale `s`: it means `m / 10^s`, so `12.50d` is `m = 1250, s = 2` and prints
//! as `12.50`. The value fits in 64 bits (a 56-bit signed integer and an 8-bit scale), so it travels in a
//! `Value` like a `Real` does. The operations return null when the result does not fit: the interpreter
//! turns that into an Overflow error.
const std = @import("std");
const Io = std.Io;

/// The largest scale (digits after the point) that a Decimal keeps.
pub const max_scale: u8 = 18;

// Zig tip: `packed struct(u64)` lays the fields out bit by bit in a 64-bit integer: no padding, the size is
// exactly what the fields add up to. `i56` is a signed integer of 56 bits, a type Zig allows for any width.
// The whole struct is 8 bytes, the same as an `f64`, so a union that holds it does not get bigger.
/// A decimal number: `m / 10^scale`.
pub const Dec = packed struct(u64) {
    scale: u8,
    m: i56,
};

const min_m: i128 = std.math.minInt(i56);
const max_m: i128 = std.math.maxInt(i56);

// Zig tip: `std.math.pow(i128, 10, n)` is an integer power. `comptime` is not needed: the loop is short and
// the table is built when the file is compiled (`const pow10 = blk: { ... }` is a labeled block that runs at
// compile time, because the initializer of a file-level `const` must be known then).
const pow10: [39]i128 = blk: {
    var t: [39]i128 = undefined;
    var v: i128 = 1;
    for (&t) |*e| {
        e.* = v;
        v = @mulWithOverflow(v, 10)[0];
    }
    break :blk t;
};

fn make(m: i128, scale: u8) ?Dec {
    if (m < min_m or m > max_m) return null;
    return .{ .scale = scale, .m = @intCast(m) };
}

/// A whole number as a Decimal of scale 0.
pub fn fromInt(n: i64) ?Dec {
    return make(n, 0);
}

// Zig tip: the text is read once from left to right with a state held in a few variables. `std.ascii.isDigit`
// tests one byte. A `?Dec` result says "not a decimal number" without an error type: the caller decides what
// to do (the interpreter raises the error `parse`).
/// Read `12.50`, `-3`, `+0.1` or `7` (digits, an optional point, an optional sign). Null if it is not a number
/// or does not fit.
pub fn parse(text: []const u8) ?Dec {
    var i: usize = 0;
    var negative = false;
    if (i < text.len and (text[i] == '-' or text[i] == '+')) {
        negative = text[i] == '-';
        i += 1;
    }
    var m: i128 = 0;
    var digits: usize = 0;
    var scale: u8 = 0;
    var seen_point = false;
    while (i < text.len) : (i += 1) {
        const ch = text[i];
        if (ch == '.' and !seen_point) {
            seen_point = true;
            continue;
        }
        if (!std.ascii.isDigit(ch)) return null;
        digits += 1;
        m = m * 10 + (ch - '0');
        if (m > max_m * 10) return null;
        if (seen_point) {
            if (scale == max_scale) return null;
            scale += 1;
        }
    }
    if (digits == 0) return null;
    return make(if (negative) -m else m, scale);
}

/// The value as a `Real` (it can lose digits).
pub fn toF64(d: Dec) f64 {
    return @as(f64, @floatFromInt(d.m)) / std.math.pow(f64, 10, @floatFromInt(d.scale));
}

// Zig tip: to add two numbers of different scales, the one with the smaller scale is multiplied by a power of
// ten until the scales are equal; the arithmetic is done in `i128`, which cannot overflow for 56-bit values.
fn aligned(a: Dec, b: Dec) struct { x: i128, y: i128, scale: u8 } {
    const s = @max(a.scale, b.scale);
    return .{ .x = @as(i128, a.m) * pow10[s - a.scale], .y = @as(i128, b.m) * pow10[s - b.scale], .scale = s };
}

/// `a + b`: the larger scale of the two (`0.10d + 0.20d` is `0.30d`).
pub fn add(a: Dec, b: Dec) ?Dec {
    const v = aligned(a, b);
    return make(v.x + v.y, v.scale);
}

/// `a - b`: the larger scale of the two.
pub fn sub(a: Dec, b: Dec) ?Dec {
    const v = aligned(a, b);
    return make(v.x - v.y, v.scale);
}

// Zig tip: `@divTrunc` divides and rounds toward zero; adding half the divisor before dividing (with the sign
// of the number) rounds half away from zero, which is what a person doing the sum by hand expects.
fn roundDiv(n: i256, d: i256) i256 {
    const half = @divTrunc(if (d < 0) -d else d, 2);
    return @divTrunc(if ((n < 0) != (d < 0)) n - half else n + half, d);
}

/// `a * b`: the scales add (`1.5d * 2.00d` is `3.000d`); beyond 18 digits the result is rounded to 18.
pub fn mul(a: Dec, b: Dec) ?Dec {
    var v: i256 = @as(i256, a.m) * @as(i256, b.m);
    var scale: u16 = @as(u16, a.scale) + b.scale;
    while (scale > max_scale) {
        v = roundDiv(v, 10);
        scale -= 1;
    }
    if (v < min_m or v > max_m) return null;
    return make(@intCast(v), @intCast(scale));
}

/// `a / b` (b is not zero): the larger scale of the two plus 6 digits, at most 18, rounded half away from zero.
pub fn div(a: Dec, b: Dec) ?Dec {
    const rs: u8 = @min(max_scale, @max(a.scale, b.scale) + 6);
    const shift: usize = @as(usize, rs) + b.scale - a.scale;
    const num: i256 = @as(i256, a.m) * @as(i256, pow10[shift]);
    const q = roundDiv(num, b.m);
    if (q < min_m or q > max_m) return null;
    return make(@intCast(q), rs);
}

/// `a % b` (b is not zero): the remainder with the sign of the divisor, at the larger scale.
pub fn rem(a: Dec, b: Dec) Dec {
    const v = aligned(a, b);
    return .{ .scale = v.scale, .m = @intCast(@mod(v.x, v.y)) };
}

/// The value with the sign changed.
pub fn neg(a: Dec) ?Dec {
    return make(-@as(i128, a.m), a.scale);
}

/// Compare by value: `1.50d` and `1.5d` are equal.
pub fn order(a: Dec, b: Dec) std.math.Order {
    const v = aligned(a, b);
    return std.math.order(v.x, v.y);
}

// Zig tip: `{d}` prints an integer; the point is placed by hand. `std.fmt.bufPrint` writes into a stack buffer
// and returns the used part. A value like `5` with scale 3 must print `0.005`: the integer part is `m` divided
// by `10^scale`, the fraction is the remainder padded with zeros on the left (`{d:0>3}`).
/// Write the decimal with all its digits: `12.50`, `0.30`, `-0.05`, `7`.
pub fn write(w: *Io.Writer, d: Dec) Io.Writer.Error!void {
    var m: i128 = d.m;
    if (m < 0) {
        try w.writeByte('-');
        m = -m;
    }
    if (d.scale == 0) return w.print("{d}", .{m});
    const p = pow10[d.scale];
    try w.print("{d}.", .{@divTrunc(m, p)});
    const frac: u128 = @intCast(@mod(m, p));
    var digits: [18]u8 = undefined;
    var k: usize = d.scale;
    var f = frac;
    while (k > 0) {
        k -= 1;
        digits[k] = '0' + @as(u8, @intCast(f % 10));
        f /= 10;
    }
    try w.writeAll(digits[0..d.scale]);
}

test "a decimal keeps its scale and prints all its digits" {
    var buf: [64]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try write(&w, parse("12.50").?);
    try w.writeByte(' ');
    try write(&w, parse("-0.05").?);
    try w.writeByte(' ');
    try write(&w, parse("7").?);
    try w.writeByte(' ');
    try write(&w, parse("0.005").?);
    try std.testing.expectEqualStrings("12.50 -0.05 7 0.005", w.buffered());
    try std.testing.expect(parse("1.2.3") == null);
    try std.testing.expect(parse("abc") == null);
    try std.testing.expect(parse("") == null);
}

test "add, subtract and multiply are exact; the comparison is by value" {
    var buf: [64]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try write(&w, add(parse("0.10").?, parse("0.20").?).?);
    try w.writeByte(' ');
    try write(&w, mul(parse("1.5").?, parse("2.00").?).?);
    try w.writeByte(' ');
    try write(&w, sub(parse("1").?, parse("0.01").?).?);
    try std.testing.expectEqualStrings("0.30 3.000 0.99", w.buffered());
    try std.testing.expectEqual(std.math.Order.eq, order(parse("1.50").?, parse("1.5").?));
    try std.testing.expectEqual(std.math.Order.lt, order(parse("-1").?, parse("0.001").?));
}

test "division rounds at the scale of the operands plus six digits" {
    var buf: [64]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try write(&w, div(parse("1").?, parse("3").?).?);
    try w.writeByte(' ');
    try write(&w, div(parse("10.00").?, parse("4").?).?);
    try std.testing.expectEqualStrings("0.333333 2.50000000", w.buffered());
}
