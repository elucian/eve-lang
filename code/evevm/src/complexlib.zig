//! @eve-module complexlib: native functions of the library module `complex`
//! @spec spec/library/math.md#module-complex
//! @feature F-LNG-31
//! @decision D-214
//! @tests test/level3/c52_complex_library
//! Handler of type `dlib.Native`, registered in `dlib.natives` as `complex`. Signatures: lib/math/complex.eve. The type itself: code/evecm/src/complex.zig.
const std = @import("std");
const ast = @import("evecm").ast;
const cx = @import("evecm").complex;
const interp = @import("interp.zig");

const Node = ast.Node;
const Interp = interp.Interp;
const Value = interp.Value;
const Signal = interp.Signal;
const err_argument = interp.err_argument;
const err_divide = interp.err_divide;
const err_overflow = interp.err_overflow;

const Fn = enum { of, real_part, imag_part, modulus, argument, conjugate, from_polar, exp, log, sqrt, pow, is_real };

fn cpxArg(it: *Interp, args: []const Value, i: usize, what: []const u8) Signal!cx.Cpx {
    if (args.len <= i) return it.failWith(err_argument, "complex.{s}: argument {d} is missing", .{ what, i + 1 });
    const v = args[i];
    return Interp.cpxOf(v) orelse it.failWith(err_argument, "complex.{s}: argument {d} is a Complex or a real number, found {s}", .{ what, i + 1, Interp.typeName(v) });
}

fn realArg(it: *Interp, args: []const Value, i: usize, what: []const u8) Signal!f64 {
    if (args.len <= i) return it.failWith(err_argument, "complex.{s}: argument {d} is missing", .{ what, i + 1 });
    const v = args[i];
    if (v == .dec or v == .cpx) return it.failWith(err_argument, "complex.{s}: argument {d} is a real number, found {s}", .{ what, i + 1, Interp.typeName(v) });
    return Interp.realOf(v) orelse it.failWith(err_argument, "complex.{s}: argument {d} is a real number, found {s}", .{ what, i + 1, Interp.typeName(v) });
}

fn result(it: *Interp, z: cx.Cpx, what: []const u8) Signal!Value {
    if (!cx.finite(z)) return it.failWith(err_overflow, "complex.{s}: the result is out of range", .{what});
    return .{ .cpx = z };
}

// @eve-fn complex.of, complex.real_part, complex.imag_part, complex.modulus, complex.argument, complex.conjugate, complex.from_polar
// @eve-fn complex.exp, complex.log, complex.sqrt, complex.pow, complex.is_real
// @spec spec/library/math.md#module-complex
// @feature F-LNG-31
// @perf hot
/// The function `f` of the module on values already evaluated: the body of the call, shared by the node entry and the fast path of a call.
fn compute(it: *Interp, f: Fn, args: []const Value) Signal!?Value {
    const n = @tagName(f);
    switch (f) {
        .of => return try result(it, .{ .re = try realArg(it, args, 0, n), .im = try realArg(it, args, 1, n) }, n),
        .real_part => return .{ .real = (try cpxArg(it, args, 0, n)).re },
        .imag_part => return .{ .real = (try cpxArg(it, args, 0, n)).im },
        .modulus => return try finiteReal(it, cx.abs(try cpxArg(it, args, 0, n)), n),
        .argument => return .{ .real = cx.arg(try cpxArg(it, args, 0, n)) },
        .conjugate => return .{ .cpx = cx.conj(try cpxArg(it, args, 0, n)) },
        .from_polar => {
            const r = try realArg(it, args, 0, n);
            const theta = try realArg(it, args, 1, n);
            if (r < 0) return it.failWith(err_argument, "complex.from_polar: the modulus is negative", .{});
            return try result(it, cx.polar(r, theta), n);
        },
        .exp => return try result(it, cx.exp(try cpxArg(it, args, 0, n)), n),
        .log => {
            const z = try cpxArg(it, args, 0, n);
            if (z.re == 0 and z.im == 0) return it.failWith(err_argument, "complex.log: the logarithm of zero", .{});
            return try result(it, cx.log(z), n);
        },
        .sqrt => return try result(it, cx.sqrt(try cpxArg(it, args, 0, n)), n),
        .pow => {
            const a = try cpxArg(it, args, 0, n);
            const b = try cpxArg(it, args, 1, n);
            if (a.re == 0 and a.im == 0 and !(b.re > 0 and b.im == 0)) {
                if (b.re == 0 and b.im == 0) return .{ .cpx = cx.fromReal(1) };
                return it.failWith(err_divide, "complex.pow: zero to a power that is not a positive real number", .{});
            }
            return try result(it, cx.pow(a, b), n);
        },
        .is_real => return .{ .bool = (try cpxArg(it, args, 0, n)).im == 0 },
    }
}

fn finiteReal(it: *Interp, x: f64, what: []const u8) Signal!Value {
    if (!std.math.isFinite(x)) return it.failWith(err_overflow, "complex.{s}: the result is out of range", .{what});
    return .{ .real = x };
}

/// The entry of `dlib.natives`: evaluates the argument nodes, then computes.
pub fn complexModule(it: *Interp, name: []const u8, _: []const *const Node, arg_nodes: []const *const Node) Signal!?Value {
    const f = std.meta.stringToEnum(Fn, name) orelse return null;
    var buf: [4]Value = undefined;
    if (arg_nodes.len > buf.len) return it.failWith(err_argument, "complex.{s}: too many arguments", .{name});
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

