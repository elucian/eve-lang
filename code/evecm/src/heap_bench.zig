//! @eve-module heap_bench
//! @spec design/reference_counting.md#3-how-it-was-measured
//! @decision D-151
//! Micro-benchmark of the heap: `zig run -OReleaseSafe code/evecm/src/heap_bench.zig` (one thread, the allocator `smp_allocator`).
const std = @import("std");
const I = @import("value.zig");
const Heap = @import("heap.zig").Heap;

fn now(io: std.Io) i96 {
    return std.Io.Timestamp.now(io, .awake).toNanoseconds();
}

fn per(t0: i96, t1: i96, n: usize) f64 {
    return @as(f64, @floatFromInt(t1 - t0)) / @as(f64, @floatFromInt(n));
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = std.heap.smp_allocator;
    var h = Heap.init(gpa);
    defer h.deinit();
    h.pushRegion();
    h.pushRegion();
    const n: usize = 1_000_000;

    // a routine call: one scope and one variable made, bound, let go, freed at the safe point
    var t0 = now(io);
    for (0..n) |_| {
        const s = try h.make(I.Scope, .{});
        Heap.retainScope(s);
        const v = try h.make(I.Var, .{ .value = .{ .int = 1 } });
        Heap.retainVar(v);
        h.releaseVar(v);
        h.releaseScope(s);
        h.safePoint();
    }
    var t1 = now(io);
    std.debug.print("scope + variable made and freed by count: {d:.1} ns per pair\n", .{per(t0, t1, n)});

    // a temporary list: made with count zero, freed at the safe point
    t0 = now(io);
    for (0..n) |_| {
        _ = try h.make(I.List, .{});
        h.safePoint();
    }
    t1 = now(io);
    std.debug.print("list made and freed at the safe point: {d:.1} ns\n", .{per(t0, t1, n)});

    // the counting alone
    const keep = try h.make(I.List, .{});
    Heap.retain(.{ .list = keep });
    t0 = now(io);
    for (0..n * 10) |_| {
        Heap.retain(.{ .list = keep });
        h.release(.{ .list = keep });
    }
    t1 = now(io);
    std.debug.print("retain + release of a live list: {d:.2} ns per pair\n", .{per(t0, t1, n * 10)});

    // a safe point with nothing to free
    t0 = now(io);
    for (0..n * 10) |_| h.safePoint();
    t1 = now(io);
    std.debug.print("empty safe point: {d:.2} ns\n", .{per(t0, t1, n * 10)});

    // a string of 20 bytes
    t0 = now(io);
    for (0..n) |_| {
        _ = try h.str("twenty bytes of text");
        h.safePoint();
    }
    t1 = now(io);
    std.debug.print("string of 20 bytes made and freed: {d:.1} ns\n", .{per(t0, t1, n)});

    // the tracing collector over 200,000 live objects
    var keepers: std.ArrayList(*I.List) = .empty;
    defer keepers.deinit(gpa);
    for (0..200_000) |_| {
        const l = try h.make(I.List, .{});
        Heap.retain(.{ .list = l });
        try keepers.append(gpa, l);
    }
    t0 = now(io);
    h.since_trace = 1_000_000;
    h.trace();
    t1 = now(io);
    std.debug.print("one trace over {d} live objects: {d:.2} ms ({d:.1} ns per object)\n", .{ h.objs.items.len, per(t0, t1, 1) / 1e6, per(t0, t1, h.objs.items.len) });
}
