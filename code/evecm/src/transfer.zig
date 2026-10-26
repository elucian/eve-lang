//! @eve-module transfer
//! @spec spec/semantics/multitasking.md#data-rules
//! @feature F-VM-05, F-MTK-02
//! @decision D-144
//! @tests test/level4
//! The copy of a value from the heap of one task into the heap of another: the only way a value crosses a border.
//! Inputs, outputs and channel messages are copied; no object of one heap is ever reached from another (design/design-task-heap.md).
const std = @import("std");
const I = @import("value.zig");
const heap_mod = @import("heap.zig");
const Value = I.Value;
const Heap = heap_mod.Heap;
const Obj = heap_mod.Obj;

pub const Error = error{OutOfMemory};

// @eve-impl a deep copy into `dst`: strings, lists, sets, maps and objects are new objects of `dst`; a constant of the root heap and a channel are shared
// @eve-impl a function is copied with its closure: the scopes up to a shared one are copied once each (a snapshot of the captured variables, as the inputs of a task are values)
// @invariant the result and everything it reaches is owned by `dst`, or pinned in the root heap
// @see code/evevm/src/interp/parallel.zig:childArgs
/// A copy of `v` in the heap `dst`, count zero (the caller stores it).
pub fn copyInto(dst: *Heap, v: Value) Error!Value {
    if (Heap.hdrOf(v) == null) return v;
    var c: Copier = .{ .dst = dst };
    defer c.memo.deinit(dst.gpa);
    return c.value(v);
}

/// One copy in progress: `memo` maps the scopes, variables and functions already copied (closures can be cyclic).
const Copier = struct {
    dst: *Heap,
    memo: std.AutoHashMapUnmanaged(*Obj, *Obj) = .empty,

    fn shared(c: *Copier, o: *Obj) bool {
        return o.owner == c.dst.id or (o.pinned and o.owner == 0);
    }

    fn value(c: *Copier, v: Value) Error!Value {
        const dst = c.dst;
        const o = Heap.hdrOf(v) orelse return v;
        switch (v) {
            .str => |s| {
                if (o.owner == dst.id) return v;
                const n = try dst.str(s);
                Heap.strHdr(n).text = Heap.strHdr(s).text;
                return .{ .str = n };
            },
            .bytes => |s| return if (o.owner == dst.id) v else .{ .bytes = try dst.str(s) },
            else => {},
        }
        if (c.shared(o)) return v;
        switch (v) {
            .list, .set => |l| {
                const n = try dst.make(I.List, .{ .array = l.array });
                const src = l.elems();
                try n.items.ensureTotalCapacity(dst.gpa, src.len);
                for (src) |e| {
                    const x = try c.value(e);
                    n.items.appendAssumeCapacity(x);
                    Heap.retain(x);
                }
                return if (v == .set) .{ .set = n } else .{ .list = n };
            },
            .map => |m| {
                const n = try dst.make(I.Map, .{});
                try n.entries.ensureTotalCapacity(dst.gpa, m.entries.items.len);
                for (m.entries.items) |e| {
                    const k = try c.value(e.key);
                    const x = try c.value(e.val);
                    n.entries.appendAssumeCapacity(.{ .key = k, .val = x });
                    Heap.retain(k);
                    Heap.retain(x);
                }
                return .{ .map = n };
            },
            .object => |ob| {
                const n = try dst.make(I.Object, .{ .class = ob.class });
                try n.fields.ensureTotalCapacity(dst.gpa, ob.fields.items.len);
                for (ob.fields.items) |f| {
                    const x = try c.value(f.val);
                    n.fields.appendAssumeCapacity(.{ .name = f.name, .val = x });
                    Heap.retain(x);
                }
                return .{ .object = n };
            },
            .func => |f| return .{ .func = try c.func(f) },
            .range => |r| return .{ .range = try dst.make(I.Range, .{ .lo = r.lo, .hi = r.hi, .step = r.step, .sym = r.sym }) },
            .domain => |d| return .{ .domain = try dst.make(I.Domain, .{ .lo = d.lo, .hi = d.hi, .lo_excl = d.lo_excl, .hi_excl = d.hi_excl, .step = d.step }) },
            else => return v,
        }
    }

    fn func(c: *Copier, f: *I.Func) Error!*I.Func {
        if (c.memo.get(&f.hdr)) |known| return @fieldParentPtr("hdr", known);
        const n = try c.dst.make(I.Func, .{ .node = f.node, .closure = f.closure, .fast = f.fast });
        try c.memo.put(c.dst.gpa, &f.hdr, &n.hdr);
        n.closure = try c.scope(f.closure);
        Heap.retainScope(n.closure);
        return n;
    }

    fn scope(c: *Copier, s: *I.Scope) Error!*I.Scope {
        if (c.shared(&s.hdr)) return s;
        if (c.memo.get(&s.hdr)) |known| return @fieldParentPtr("hdr", known);
        const n = try c.dst.make(I.Scope, .{});
        try c.memo.put(c.dst.gpa, &s.hdr, &n.hdr);
        try n.binds.ensureTotalCapacity(c.dst.gpa, s.binds.items.len);
        for (s.binds.items) |b| {
            const nv = try c.variable(b.v);
            n.binds.appendAssumeCapacity(.{ .name = b.name, .v = nv });
            Heap.retainVar(nv);
        }
        if (s.parent) |p| {
            n.parent = try c.scope(p);
            Heap.retainScope(n.parent.?);
        }
        return n;
    }

    fn variable(c: *Copier, v: *I.Var) Error!*I.Var {
        if (c.shared(&v.hdr)) return v;
        if (c.memo.get(&v.hdr)) |known| return @fieldParentPtr("hdr", known);
        const n = try c.dst.make(I.Var, .{ .value = .nil, .constant = v.constant, .decl = v.decl });
        try c.memo.put(c.dst.gpa, &v.hdr, &n.hdr);
        n.value = try c.value(v.value);
        Heap.retain(n.value);
        return n;
    }
};

test "a copy is owned by the target heap and independent of the source" {
    var a = Heap.init(std.testing.allocator);
    defer a.deinit();
    var b = Heap.initTask(std.testing.allocator);
    defer b.deinit();
    a.pushRegion();
    b.pushRegion();
    const l = try a.make(I.List, .{});
    const s = try a.str("hello");
    try l.items.append(a.gpa, .{ .str = s });
    Heap.retain(.{ .str = s });
    const c = try copyInto(&b, .{ .list = l });
    try std.testing.expect(c.list != l);
    try std.testing.expectEqual(b.id, c.list.hdr.owner);
    try std.testing.expectEqual(b.id, Heap.hdrOf(c.list.items.items[0]).?.owner);
    try std.testing.expect(c.list.items.items[0].str.ptr != s.ptr);
    try std.testing.expectEqualStrings("hello", c.list.items.items[0].str);
}

test "a pinned constant of the root heap is shared, not copied" {
    var a = Heap.init(std.testing.allocator);
    defer a.deinit();
    var b = Heap.initTask(std.testing.allocator);
    defer b.deinit();
    a.pushRegion();
    b.pushRegion();
    const l = try a.make(I.List, .{});
    Heap.pinDeep(.{ .list = l });
    const c = try copyInto(&b, .{ .list = l });
    try std.testing.expect(c.list == l);
}

test "a function is copied with its closure, which may hold the function itself" {
    const ast = @import("ast.zig");
    var a = Heap.init(std.testing.allocator);
    defer a.deinit();
    var b = Heap.initTask(std.testing.allocator);
    defer b.deinit();
    a.pushRegion();
    b.pushRegion();
    const sc = try a.make(I.Scope, .{});
    const f = try a.make(I.Func, .{ .node = &ast.none, .closure = sc });
    Heap.retainScope(sc);
    const v = try a.make(I.Var, .{ .value = .{ .func = f } });
    Heap.retain(.{ .func = f });
    try sc.binds.append(a.gpa, .{ .name = "f", .v = v });
    Heap.retainVar(v);
    const c = try copyInto(&b, .{ .func = f });
    try std.testing.expect(c.func != f);
    try std.testing.expect(c.func.closure != sc);
    try std.testing.expectEqual(b.id, c.func.closure.hdr.owner);
    try std.testing.expect(c.func.closure.binds.items[0].v.value.func == c.func); // the cycle is kept, inside the copy
}
