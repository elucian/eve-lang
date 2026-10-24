//! @eve-module rationallib: native functions of the library module `rational` (fractions of whole numbers)
//! @spec spec/library/math.md#module-rational
//! @feature F-LNG-30
//! @decision D-214
//! @tests test/level3/c48_rational_library
//! Handler of type `dlib.Native`, registered in `dlib.natives` as `rational`. Signatures: lib/math/rational.eve. The type itself: code/evecm/src/rational.zig.
const std = @import("std");
const ast = @import("evecm").ast;
const rational = @import("evecm").rational;
const interp = @import("interp.zig");

const Node = ast.Node;
const Interp = interp.Interp;
const Value = interp.Value;
const Signal = interp.Signal;
const err_argument = interp.err_argument;
const err_divide = interp.err_divide;
const err_overflow = interp.err_overflow;

const Fn = enum { of, numerator, denominator, reciprocal, truncate, is_whole, to_real, from_real, parse, mediant, continued };

fn ratArg(it: *Interp, args: []const Value, i: usize, what: []const u8) Signal!rational.Rat {
    if (args.len <= i) return it.failWith(err_argument, "rational.{s}: argument {d} is missing", .{ what, i + 1 });
    const v = args[i];
    return Interp.ratOf(v) orelse it.failWith(err_argument, "rational.{s}: argument {d} is a Rational or an Integer, found {s}", .{ what, i + 1, Interp.typeName(v) });
}

fn intArg(it: *Interp, args: []const Value, i: usize, what: []const u8) Signal!i64 {
    if (args.len <= i) return it.failWith(err_argument, "rational.{s}: argument {d} is missing", .{ what, i + 1 });
    const v = args[i];
    if (!Interp.isInt(v)) return it.failWith(err_argument, "rational.{s}: argument {d} is a whole number", .{ what, i + 1 });
    return Interp.intOf(v);
}

// @eve-fn rational.of, rational.numerator, rational.denominator, rational.reciprocal, rational.truncate, rational.is_whole
// @eve-fn rational.to_real, rational.from_real, rational.parse, rational.mediant, rational.continued
// @spec spec/library/math.md#module-rational
// @feature F-LNG-30
// @perf hot
/// The function `f` of the module on values already evaluated: the body of the call, shared by the node entry and the fast path of a call.
fn compute(it: *Interp, f: Fn, args: []const Value) Signal!?Value {
    const n = @tagName(f);
    switch (f) {
        .of => {
            const num = try intArg(it, args, 0, n);
            const den = try intArg(it, args, 1, n);
            if (den == 0) return it.failWith(err_divide, "rational.of: the denominator is zero", .{});
            return .{ .rat = rational.make(num, den) orelse return it.failWith(err_overflow, "rational.of: the fraction does not fit", .{}) };
        },
        .numerator => return .{ .int = (try ratArg(it, args, 0, n)).n },
        .denominator => return .{ .int = (try ratArg(it, args, 0, n)).d },
        .reciprocal => {
            const q = try ratArg(it, args, 0, n);
            if (q.n == 0) return it.failWith(err_divide, "rational.reciprocal: zero has no reciprocal", .{});
            return .{ .rat = rational.reciprocal(q) orelse return it.failWith(err_overflow, "rational.reciprocal: the fraction does not fit", .{}) };
        },
        .truncate => {
            const q = try ratArg(it, args, 0, n);
            return .{ .int = @divTrunc(q.n, q.d) };
        },
        .is_whole => return .{ .bool = (try ratArg(it, args, 0, n)).d == 1 },
        .to_real => return .{ .real = rational.toF64(try ratArg(it, args, 0, n)) },
        .from_real => {
            if (args.len < 1) return it.failWith(err_argument, "rational.from_real takes a Real and a largest denominator", .{});
            const x = Interp.realOf(args[0]) orelse return it.failWith(err_argument, "rational.from_real: argument 1 is a number", .{});
            const max_den = if (args.len > 1) try intArg(it, args, 1, n) else 1_000_000;
            if (max_den < 1) return it.failWith(err_argument, "rational.from_real: the largest denominator is 1 or more", .{});
            return .{ .rat = rational.fromF64(x, max_den) orelse return it.failWith(err_argument, "rational.from_real: the number is not finite or is too large", .{}) };
        },
        .parse => {
            if (args.len != 1) return it.failWith(err_argument, "rational.parse takes a text", .{});
            const v = args[0];
            if (v != .str) return it.failWith(err_argument, "rational.parse: argument 1 is a String", .{});
            const text = std.mem.trim(u8, v.str, " ");
            return .{ .rat = rational.parse(text) orelse return it.failWith(interp.err_parse, "rational.parse: '{s}' is not a Rational (write 3\\4)", .{text}) };
        },
        .mediant => {
            const a = try ratArg(it, args, 0, n);
            const b = try ratArg(it, args, 1, n);
            return .{ .rat = rational.make(@as(i128, a.n) + b.n, @as(i128, a.d) + b.d) orelse return it.failWith(err_overflow, "rational.mediant: the fraction does not fit", .{}) };
        },
        .continued => {
            var q = try ratArg(it, args, 0, n);
            var terms: std.ArrayList(Value) = .empty;
            defer terms.deinit(it.a);
            while (true) {
                const fl = rational.floor(q);
                try terms.append(it.a, .{ .int = fl });
                const rest = rational.sub(q, rational.fromInt(fl)) orelse break;
                if (rest.n == 0) break;
                q = rational.reciprocal(rest) orelse break;
            }
            return .{ .list = try it.newList(terms.items, false) };
        },
    }
}

/// The entry of `dlib.natives`: evaluates the argument nodes, then computes.
pub fn rationalModule(it: *Interp, name: []const u8, _: []const *const Node, arg_nodes: []const *const Node) Signal!?Value {
    const f = std.meta.stringToEnum(Fn, name) orelse return null;
    var buf: [4]Value = undefined;
    if (arg_nodes.len > buf.len) return it.failWith(err_argument, "rational.{s}: too many arguments", .{name});
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

