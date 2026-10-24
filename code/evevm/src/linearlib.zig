//! @eve-module linearlib: native functions of the library module `linear` (vectors and matrices)
//! @spec spec/library/math.md#module-linear
//! @feature F-LIB-03
//! @decision D-214
//! @tests test/level1/a113_math_linear
//! Handler of type `dlib.Native`, registered in `dlib.natives` as `linear`. Signatures: lib/math/linear.eve.
const std = @import("std");
const ast = @import("evecm").ast;
const decimal = @import("evecm").decimal;
const interp = @import("interp.zig");

const Node = ast.Node;
const Interp = interp.Interp;
const Value = interp.Value;
const Signal = interp.Signal;
const err_argument = interp.err_argument;

const Fn = enum { dot, cross, norm, scale, add, subtract, transpose, matmul, matvec, identity, trace, det, inverse, solve };

/// A matrix read from a list of lists: row-major, `rows` by `cols`.
const Matrix = struct {
    rows: usize,
    cols: usize,
    data: []f64,

    fn at(m: Matrix, r: usize, c: usize) f64 {
        return m.data[r * m.cols + c];
    }
    fn set(m: Matrix, r: usize, c: usize, x: f64) void {
        m.data[r * m.cols + c] = x;
    }
};

fn number(it: *Interp, v: Value, what: []const u8) Signal!f64 {
    return switch (v) {
        .real, .float => |x| x,
        .dec => |d| decimal.toF64(d),
        else => if (Interp.isInt(v)) @floatFromInt(Interp.intOf(v)) else it.failWith(err_argument, "linear.{s}: an element is a number, found {s}", .{ what, Interp.typeName(v) }),
    };
}

fn listArg(it: *Interp, args: []const *const Node, i: usize, what: []const u8) Signal![]Value {
    if (args.len <= i) return it.failWith(err_argument, "linear.{s}: argument {d} is missing", .{ what, i + 1 });
    const v = try it.eval(args[i]);
    return switch (v) {
        .list => |l| l.elems(),
        else => it.failWith(err_argument, "linear.{s}: argument {d} is a list", .{ what, i + 1 }),
    };
}

fn vector(it: *Interp, items: []const Value, what: []const u8) Signal![]f64 {
    const out = try it.t.alloc(f64, items.len);
    for (items, out) |v, *x| x.* = try number(it, v, what);
    return out;
}

fn matrix(it: *Interp, items: []const Value, what: []const u8) Signal!Matrix {
    if (items.len == 0) return it.failWith(err_argument, "linear.{s}: the matrix has no rows", .{what});
    const first = switch (items[0]) {
        .list => |l| l.elems(),
        else => return it.failWith(err_argument, "linear.{s}: a matrix is a list of lists", .{what}),
    };
    if (first.len == 0) return it.failWith(err_argument, "linear.{s}: the matrix has no columns", .{what});
    const m: Matrix = .{ .rows = items.len, .cols = first.len, .data = try it.t.alloc(f64, items.len * first.len) };
    for (items, 0..) |row, r| {
        const cells = switch (row) {
            .list => |l| l.elems(),
            else => return it.failWith(err_argument, "linear.{s}: a matrix is a list of lists", .{what}),
        };
        if (cells.len != m.cols) return it.failWith(err_argument, "linear.{s}: the rows have different lengths", .{what});
        for (cells, 0..) |v, c| m.set(r, c, try number(it, v, what));
    }
    return m;
}

fn realList(it: *Interp, xs: []const f64) Signal!Value {
    const vals = try it.t.alloc(Value, xs.len);
    for (xs, vals) |x, *v| v.* = .{ .real = x };
    return .{ .list = try it.newList(vals, false) };
}

fn matrixValue(it: *Interp, m: Matrix) Signal!Value {
    const rows = try it.t.alloc(Value, m.rows);
    for (rows, 0..) |*row, r| row.* = try realList(it, m.data[r * m.cols .. (r + 1) * m.cols]);
    return .{ .list = try it.newList(rows, false) };
}

fn newMatrix(it: *Interp, rows: usize, cols: usize) Signal!Matrix {
    const m: Matrix = .{ .rows = rows, .cols = cols, .data = try it.t.alloc(f64, rows * cols) };
    @memset(m.data, 0);
    return m;
}

fn finiteOrFail(it: *Interp, x: f64, what: []const u8) Signal!f64 {
    if (!std.math.isFinite(x)) return it.failWith(interp.err_overflow, "linear.{s}: the result is out of range", .{what});
    return x;
}

// @eve-impl Gauss-Jordan elimination with partial pivoting on [a | b]: returns the determinant (0 when singular) and leaves in `b` the solution for each column of b
fn eliminate(a: Matrix, b: Matrix) f64 {
    const n = a.rows;
    var det: f64 = 1;
    for (0..n) |col| {
        var pivot = col;
        for (col + 1..n) |r| {
            if (@abs(a.at(r, col)) > @abs(a.at(pivot, col))) pivot = r;
        }
        if (a.at(pivot, col) == 0) return 0;
        if (pivot != col) {
            det = -det;
            for (0..a.cols) |c| std.mem.swap(f64, &a.data[pivot * a.cols + c], &a.data[col * a.cols + c]);
            for (0..b.cols) |c| std.mem.swap(f64, &b.data[pivot * b.cols + c], &b.data[col * b.cols + c]);
        }
        const p = a.at(col, col);
        det *= p;
        for (0..a.cols) |c| a.set(col, c, a.at(col, c) / p);
        for (0..b.cols) |c| b.set(col, c, b.at(col, c) / p);
        for (0..n) |r| {
            if (r == col) continue;
            const f = a.at(r, col);
            if (f == 0) continue;
            for (0..a.cols) |c| a.set(r, c, a.at(r, c) - f * a.at(col, c));
            for (0..b.cols) |c| b.set(r, c, b.at(r, c) - f * b.at(col, c));
        }
    }
    return det;
}

fn squareArg(it: *Interp, args: []const *const Node, i: usize, what: []const u8) Signal!Matrix {
    const m = try matrix(it, try listArg(it, args, i, what), what);
    if (m.rows != m.cols) return it.failWith(err_argument, "linear.{s}: the matrix is not square ({d} by {d})", .{ what, m.rows, m.cols });
    return m;
}

// @eve-fn linear.dot, linear.cross, linear.norm, linear.scale, linear.add, linear.subtract, linear.transpose, linear.matmul, linear.matvec
// @eve-fn linear.identity, linear.trace, linear.det, linear.inverse, linear.solve
// @spec spec/library/math.md#module-linear
// @feature F-LIB-03
pub fn linearModule(it: *Interp, name: []const u8, _: []const *const Node, args: []const *const Node) Signal!?Value {
    const f = std.meta.stringToEnum(Fn, name) orelse return null;
    const n = @tagName(f);
    switch (f) {
        .dot => {
            const a = try vector(it, try listArg(it, args, 0, n), n);
            const b = try vector(it, try listArg(it, args, 1, n), n);
            if (a.len != b.len) return it.failWith(err_argument, "linear.dot: the vectors have different lengths", .{});
            var s: f64 = 0;
            for (a, b) |x, y| s += x * y;
            return .{ .real = try finiteOrFail(it, s, n) };
        },
        .cross => {
            const a = try vector(it, try listArg(it, args, 0, n), n);
            const b = try vector(it, try listArg(it, args, 1, n), n);
            if (a.len != 3 or b.len != 3) return it.failWith(err_argument, "linear.cross: both vectors have 3 elements", .{});
            return try realList(it, &.{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] });
        },
        .norm => {
            const a = try vector(it, try listArg(it, args, 0, n), n);
            var s: f64 = 0;
            for (a) |x| s += x * x;
            return .{ .real = try finiteOrFail(it, @sqrt(s), n) };
        },
        .scale => {
            const items = try listArg(it, args, 0, n);
            if (args.len < 2) return it.failWith(err_argument, "linear.scale takes a vector or a matrix and a number", .{});
            const k = try number(it, try it.eval(args[1]), n);
            if (items.len > 0 and items[0] == .list) {
                const m = try matrix(it, items, n);
                for (m.data) |*x| x.* *= k;
                return try matrixValue(it, m);
            }
            const a = try vector(it, items, n);
            for (a) |*x| x.* *= k;
            return try realList(it, a);
        },
        .add, .subtract => {
            const ia = try listArg(it, args, 0, n);
            const ib = try listArg(it, args, 1, n);
            const sign: f64 = if (f == .add) 1 else -1;
            if (ia.len > 0 and ia[0] == .list) {
                const a = try matrix(it, ia, n);
                const b = try matrix(it, ib, n);
                if (a.rows != b.rows or a.cols != b.cols) return it.failWith(err_argument, "linear.{s}: the matrices have different shapes", .{n});
                for (a.data, b.data) |*x, y| x.* += sign * y;
                return try matrixValue(it, a);
            }
            const a = try vector(it, ia, n);
            const b = try vector(it, ib, n);
            if (a.len != b.len) return it.failWith(err_argument, "linear.{s}: the vectors have different lengths", .{n});
            for (a, b) |*x, y| x.* += sign * y;
            return try realList(it, a);
        },
        .transpose => {
            const a = try matrix(it, try listArg(it, args, 0, n), n);
            const t = try newMatrix(it, a.cols, a.rows);
            for (0..a.rows) |r| for (0..a.cols) |c| t.set(c, r, a.at(r, c));
            return try matrixValue(it, t);
        },
        .matmul => {
            const a = try matrix(it, try listArg(it, args, 0, n), n);
            const b = try matrix(it, try listArg(it, args, 1, n), n);
            if (a.cols != b.rows) return it.failWith(err_argument, "linear.matmul: {d} columns against {d} rows", .{ a.cols, b.rows });
            const p = try newMatrix(it, a.rows, b.cols);
            for (0..a.rows) |r| for (0..b.cols) |c| {
                var s: f64 = 0;
                for (0..a.cols) |k| s += a.at(r, k) * b.at(k, c);
                p.set(r, c, try finiteOrFail(it, s, n));
            };
            return try matrixValue(it, p);
        },
        .matvec => {
            const a = try matrix(it, try listArg(it, args, 0, n), n);
            const v = try vector(it, try listArg(it, args, 1, n), n);
            if (a.cols != v.len) return it.failWith(err_argument, "linear.matvec: {d} columns against a vector of {d}", .{ a.cols, v.len });
            const out = try it.t.alloc(f64, a.rows);
            for (0..a.rows) |r| {
                var s: f64 = 0;
                for (0..a.cols) |k| s += a.at(r, k) * v[k];
                out[r] = try finiteOrFail(it, s, n);
            }
            return try realList(it, out);
        },
        .identity => {
            if (args.len != 1) return it.failWith(err_argument, "linear.identity takes the size", .{});
            const v = try it.eval(args[0]);
            if (!Interp.isInt(v) or Interp.intOf(v) < 1 or Interp.intOf(v) > 4096) return it.failWith(err_argument, "linear.identity: a size from 1 to 4096", .{});
            const size: usize = @intCast(Interp.intOf(v));
            const m = try newMatrix(it, size, size);
            for (0..size) |i| m.set(i, i, 1);
            return try matrixValue(it, m);
        },
        .trace => {
            const a = try squareArg(it, args, 0, n);
            var s: f64 = 0;
            for (0..a.rows) |i| s += a.at(i, i);
            return .{ .real = s };
        },
        .det => {
            const a = try squareArg(it, args, 0, n);
            const b = try newMatrix(it, a.rows, 0);
            return .{ .real = try finiteOrFail(it, eliminate(a, b), n) };
        },
        .inverse => {
            const a = try squareArg(it, args, 0, n);
            const inv = try newMatrix(it, a.rows, a.rows);
            for (0..a.rows) |i| inv.set(i, i, 1);
            if (eliminate(a, inv) == 0) return it.failWith(err_argument, "linear.inverse: the matrix is singular", .{});
            return try matrixValue(it, inv);
        },
        .solve => {
            const a = try squareArg(it, args, 0, n);
            const rhs = try vector(it, try listArg(it, args, 1, n), n);
            if (rhs.len != a.rows) return it.failWith(err_argument, "linear.solve: {d} equations and {d} constants", .{ a.rows, rhs.len });
            const b: Matrix = .{ .rows = a.rows, .cols = 1, .data = rhs };
            if (eliminate(a, b) == 0) return it.failWith(err_argument, "linear.solve: the matrix is singular", .{});
            return try realList(it, rhs);
        },
    }
}

test "spec: math.md#module-linear elimination solves 2x + y = 5, x - y = 1" {
    var ad = [_]f64{ 2, 1, 1, -1 };
    var bd = [_]f64{ 5, 1 };
    const a: Matrix = .{ .rows = 2, .cols = 2, .data = &ad };
    const b: Matrix = .{ .rows = 2, .cols = 1, .data = &bd };
    try std.testing.expectApproxEqAbs(@as(f64, -3), eliminate(a, b), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 2), bd[0], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1), bd[1], 1e-12);
}
