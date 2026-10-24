//! @eve-module randomlib: native functions of the library module `random` (seeded and unseeded generator)
//! @spec spec/library/math.md#module-random
//! @feature F-LIB-03
//! @decision D-214
//! @tests test/level1/a114_math_random
//! Handler of type `dlib.Native`, registered in `dlib.natives` as `random`. Signatures: lib/math/random.eve.
//! One generator for the whole process: xoshiro256** seeded through SplitMix64, so a seed gives the same numbers on every machine.
const std = @import("std");
const ast = @import("evecm").ast;
const decimal = @import("evecm").decimal;
const interp = @import("interp.zig");

const Node = ast.Node;
const Interp = interp.Interp;
const Value = interp.Value;
const Signal = interp.Signal;
const err_argument = interp.err_argument;

const Fn = enum { @"seed", @"next!", @"integer!", @"real!", @"normal!", @"choice!", @"shuffle!", @"sample!" };

// @invariant `state` is read and written only with `lock` held; `ready` is false until the first seed (explicit or from the system)
var state: [4]u64 = undefined;
var ready = false;
var lock: std.atomic.Value(bool) = .init(false);

fn acquire() void {
    while (lock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) std.atomic.spinLoopHint();
}

fn release() void {
    lock.store(false, .release);
}

fn splitMix(x: *u64) u64 {
    x.* +%= 0x9e3779b97f4a7c15;
    var z = x.*;
    z = (z ^ (z >> 30)) *% 0xbf58476d1ce4e5b9;
    z = (z ^ (z >> 27)) *% 0x94d049bb133111eb;
    return z ^ (z >> 31);
}

fn seedWith(seed: u64) void {
    var x = seed;
    for (&state) |*s| s.* = splitMix(&x);
    ready = true;
}

fn rotl(x: u64, k: u6) u64 {
    return (x << k) | (x >> @intCast(64 - @as(u7, k)));
}

// @eve-impl xoshiro256** (Blackman, Vigna); the caller holds the lock and has seeded
fn nextU64() u64 {
    const result = rotl(state[1] *% 5, 7) *% 9;
    const t = state[1] << 17;
    state[2] ^= state[0];
    state[3] ^= state[1];
    state[1] ^= state[2];
    state[0] ^= state[3];
    state[2] ^= t;
    state[3] = rotl(state[3], 45);
    return result;
}

fn unit() f64 {
    return @as(f64, @floatFromInt(nextU64() >> 11)) * (1.0 / 9007199254740992.0);
}

// @eve-impl a number in 0 .. bound - 1 without modulo bias (rejection)
fn below(bound: u64) u64 {
    const limit = std.math.maxInt(u64) - (std.math.maxInt(u64) % bound);
    while (true) {
        const x = nextU64();
        if (x < limit) return x % bound;
    }
}

fn ensureSeeded(it: *Interp) Signal!void {
    if (ready) return;
    var raw: [8]u8 = undefined;
    const io = it.io orelse return it.fail("random: no input/output handle", .{});
    io.random(&raw);
    seedWith(std.mem.readInt(u64, &raw, .little));
}

fn realOf(it: *Interp, v: Value, what: []const u8) Signal!f64 {
    return switch (v) {
        .real, .float => |x| x,
        .dec => |d| decimal.toF64(d),
        else => if (Interp.isInt(v)) @floatFromInt(Interp.intOf(v)) else it.failWith(err_argument, "random.{s}: a number is expected, found {s}", .{ what, Interp.typeName(v) }),
    };
}

fn intArg(it: *Interp, args: []const *const Node, i: usize, what: []const u8) Signal!i64 {
    if (args.len <= i) return it.failWith(err_argument, "random.{s}: argument {d} is missing", .{ what, i + 1 });
    const v = try it.eval(args[i]);
    if (!Interp.isInt(v)) return it.failWith(err_argument, "random.{s}: argument {d} is a whole number", .{ what, i + 1 });
    return Interp.intOf(v);
}

fn listArg(it: *Interp, args: []const *const Node, what: []const u8) Signal![]Value {
    if (args.len < 1) return it.failWith(err_argument, "random.{s}: a list is missing", .{what});
    const v = try it.eval(args[0]);
    return switch (v) {
        .list, .set => |l| l.elems(),
        else => it.failWith(err_argument, "random.{s}: argument 1 is a list", .{what}),
    };
}

// @eve-fn random.seed, random.next!, random.integer!, random.real!, random.normal!, random.choice!, random.shuffle!, random.sample!
// @spec spec/library/math.md#module-random
// @feature F-LIB-03
pub fn randomModule(it: *Interp, name: []const u8, _: []const *const Node, args: []const *const Node) Signal!?Value {
    const f = std.meta.stringToEnum(Fn, name) orelse return null;
    const n = name;
    switch (f) {
        .@"seed" => {
            const s = try intArg(it, args, 0, n);
            acquire();
            defer release();
            seedWith(@bitCast(s));
            return .nil;
        },
        .@"next!" => {
            try ensureSeeded(it);
            acquire();
            defer release();
            return .{ .real = unit() };
        },
        .@"integer!" => {
            const lo = try intArg(it, args, 0, n);
            const hi = try intArg(it, args, 1, n);
            if (lo > hi) return it.failWith(err_argument, "random.integer!: low is greater than high", .{});
            try ensureSeeded(it);
            acquire();
            defer release();
            const span: u64 = @as(u64, @bitCast(hi -% lo)) +% 1;
            const off: u64 = if (span == 0) nextU64() else below(span);
            return .{ .int = lo +% @as(i64, @bitCast(off)) };
        },
        .@"real!" => {
            if (args.len != 2) return it.failWith(err_argument, "random.real! takes low and high", .{});
            const lo = try realOf(it, try it.eval(args[0]), n);
            const hi = try realOf(it, try it.eval(args[1]), n);
            if (lo > hi) return it.failWith(err_argument, "random.real!: low is greater than high", .{});
            try ensureSeeded(it);
            acquire();
            defer release();
            return .{ .real = lo + (hi - lo) * unit() };
        },
        .@"normal!" => {
            if (args.len != 2) return it.failWith(err_argument, "random.normal! takes the mean and the standard deviation", .{});
            const mean = try realOf(it, try it.eval(args[0]), n);
            const sd = try realOf(it, try it.eval(args[1]), n);
            if (sd < 0) return it.failWith(err_argument, "random.normal!: the standard deviation is negative", .{});
            try ensureSeeded(it);
            acquire();
            defer release();
            const ua = 1.0 - unit(); // in (0, 1]: the logarithm is finite
            const ub = unit();
            return .{ .real = mean + sd * @sqrt(-2.0 * @log(ua)) * @cos(2.0 * std.math.pi * ub) };
        },
        .@"choice!" => {
            const items = try listArg(it, args, n);
            if (items.len == 0) return it.failWith(err_argument, "random.choice!: the list is empty", .{});
            try ensureSeeded(it);
            acquire();
            defer release();
            return items[@intCast(below(items.len))];
        },
        .@"shuffle!" => {
            const items = try listArg(it, args, n);
            const copy = try it.t.dupe(Value, items);
            try ensureSeeded(it);
            {
                acquire();
                defer release();
                var i = copy.len;
                while (i > 1) {
                    i -= 1;
                    const j: usize = @intCast(below(i + 1));
                    std.mem.swap(Value, &copy[i], &copy[j]);
                }
            }
            return .{ .list = try it.newList(copy, false) };
        },
        .@"sample!" => {
            const items = try listArg(it, args, n);
            const k = try intArg(it, args, 1, n);
            if (k < 0 or k > items.len) return it.failWith(err_argument, "random.sample!: the size is from 0 to the length of the list", .{});
            const copy = try it.t.dupe(Value, items);
            const count: usize = @intCast(k);
            try ensureSeeded(it);
            {
                acquire();
                defer release();
                for (0..count) |i| {
                    const j = i + @as(usize, @intCast(below(copy.len - i)));
                    std.mem.swap(Value, &copy[i], &copy[j]);
                }
            }
            return .{ .list = try it.newList(copy[0..count], false) };
        },
    }
}

test "spec: math.md#module-random the same seed gives the same numbers" {
    acquire();
    defer release();
    seedWith(7);
    const a = nextU64();
    seedWith(7);
    try std.testing.expectEqual(a, nextU64());
    const x = unit();
    try std.testing.expect(x >= 0 and x < 1);
    for (0..1000) |_| try std.testing.expect(below(6) < 6);
}
