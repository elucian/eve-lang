//! @eve-module heap
//! @spec spec/semantics/variables.md#runtime-objects
//! @feature F-VM-05, F-VM-02
//! @decision D-151
//! @tests test/level1, test/level4
//! The heap of the values of a script: strings, lists, maps, objects, functions, ranges, channels,
//! and the scopes and variables that hold them.
//!
//! Memory is freed by **reference counting**: every object counts the variables, elements, entries
//! and fields that hold it. A value whose count falls to zero is not freed at once, because the
//! interpreter may still hold it for a moment while it computes an expression (a temporary, which
//! is not counted). It goes to the "zero count table" of its **region** and is freed at the next
//! **safe point**: the end of a statement, of a pass of a loop, of a `done`. A region is the part of
//! the run that started with a block, a loop or a process; its objects are those made after it
//! started. Variables and scopes are freed at once when the last holder lets them go.
//!
//! Reference counting cannot free a cycle (a scope that holds a function that closes over the same
//! scope). A **tracing collector** is the backup: it marks what the roots reach and frees the rest;
//! it runs at `done` and when the heap has grown a lot since its last run.
//!
//! While tasks run in parallel, nothing is freed: the zero counts wait in a list until the group or
//! the job reaches `done` (the tasks of stage A share one heap, D-144).
const std = @import("std");
const I = @import("value.zig");
const Value = I.Value;

/// The kind of a heap object.
pub const Kind = enum(u8) { str, list, map, object, func, range, domain, chan, scope, variable };

/// The header of a heap object.
pub const Obj = struct {
    /// How many holders count this object: variables, elements, entries, fields, closures.
    rc: u32 = 0,
    kind: Kind,
    /// Reached by the tracing collector in its current run.
    mark: bool = false,
    /// Waiting in a zero count table.
    in_zct: bool = false,
    /// Never freed before the end of the run: literals, module scopes, the global scope.
    pinned: bool = false,
    /// The place of the object in `Heap.objs`.
    idx: u32 = 0,
    /// The order of creation: a region holds the objects whose `seq` is at least its start.
    seq: u64 = 0,
    /// The destructor of the object has run (it runs once).
    finalized: bool = false,
};

/// The header of a heap string; the bytes follow it.
pub const Str = struct {
    hdr: Obj = .{ .kind = .str },
    magic: u32 = str_magic,
    len: u32 = 0,
    /// The bytes allocated for the header and the text (a big string gets a rounded size, see `allocStr`).
    cap: u32 = 0,
};
const str_magic: u32 = 0x5354_524e;

/// The interpreter's side of the destructors: `run` calls the destructor of `cls` with `obj` as `self`.
pub const Finalizer = struct {
    ctx: *anyopaque,
    run: *const fn (ctx: *anyopaque, obj: *I.Object, cls: *I.Class) void,
};

/// Objects made since `start`, and the ones among them whose count fell to zero.
const Region = struct { start: u64, zct: std.ArrayList(*Obj) = .empty };

/// Memory statistics, printed by `EVE_MEMSTATS=1` and read by the tests.
pub const Stats = struct {
    made: u64 = 0,
    freed_rc: u64 = 0,
    freed_gc: u64 = 0,
    traces: u64 = 0,
    live: u64 = 0,
    peak_live: u64 = 0,
    bytes: u64 = 0,
    peak_bytes: u64 = 0,
};

/// `EVE_MEMSTATS=1`: print the statistics of the heap when the run ends.
pub var show_stats: bool = false;
/// `EVE_GC_VERIFY=1`: check every free of the reference count against a trace (slow, for the tests).
pub var verify: bool = false;

/// The heap of one run.
pub const Heap = struct {
    gpa: std.mem.Allocator,
    objs: std.ArrayList(*Obj) = .empty,
    next_seq: u64 = 1,
    regions: std.ArrayList(Region) = .empty,
    depth: usize = 0,
    /// The zero counts of the time when tasks run: they are sorted into regions at `done`.
    deferred: std.ArrayList(*Obj) = .empty,
    /// How many tasks are alive; nothing is freed while there are any.
    paused: u32 = 0,
    /// Runs the destructor of an object (CLS-14, D-202); set by the interpreter.
    finalizer: ?Finalizer = null,
    /// Interned strings: one pinned copy per literal or constant text.
    statics: std.AutoHashMapUnmanaged(usize, []const u8) = .empty,
    /// The objects made since the last trace, and the limit that starts the next one.
    since_trace: u64 = 0,
    trace_limit: u64 = 200_000,
    stats: Stats = .{},
    /// The roots of a trace, given by the interpreter (`Interp.roots`).
    root_fn: ?*const fn (ctx: *anyopaque, h: *Heap) void = null,
    root_ctx: *anyopaque = undefined,
    marks: std.ArrayList(*Obj) = .empty,
    /// Freed objects kept for reuse, one stack per kind (see `make` and `destroy`).
    pools: [kind_count]std.ArrayList(*Obj) = @splat(.empty),
    /// Freed blocks of big strings, by power of two: a string that grows in a loop reuses them.
    big_count: [big_classes]u8 = @splat(0),
    big_blocks: [big_classes][big_keep][]align(@alignOf(Str)) u8 = undefined,

    /// A string of more than `big_min` bytes takes a block of a power of two; `big_keep` blocks of each size wait for reuse.
    const big_min = 16 * 1024;
    const big_classes = 33;
    const big_keep = 4;

    const kind_count = std.meta.fieldNames(Kind).len;
    /// How many freed objects of one kind are kept, and the largest inner buffer kept with them.
    const pool_max = 4096;
    const buffer_max = 64;

    /// A new heap over the allocator `gpa`.
    pub fn init(gpa: std.mem.Allocator) Heap {
        return .{ .gpa = gpa };
    }

    /// Free everything: the end of the run.
    pub fn deinit(h: *Heap) void {
        for (h.objs.items) |o| h.destroy(o);
        h.objs.deinit(h.gpa);
        for (h.regions.items) |*r| r.zct.deinit(h.gpa);
        h.regions.deinit(h.gpa);
        h.deferred.deinit(h.gpa);
        h.statics.deinit(h.gpa);
        h.marks.deinit(h.gpa);
        for (&h.pools) |*pool| {
            for (pool.items) |o| h.releaseMemory(o);
            pool.deinit(h.gpa);
        }
        for (0..big_classes) |c| {
            for (h.big_blocks[c][0..h.big_count[c]]) |b| h.gpa.free(b);
        }
    }

    // ---- making objects --------------------------------------------------------------------------

    /// A new object of type `T` with the fields of `first`, registered in the heap, count zero.
    pub fn make(h: *Heap, comptime T: type, first: T) error{OutOfMemory}!*T {
        comptime std.debug.assert(@hasField(T, "hdr"));
        const k = comptime kindOf(T);
        const p: *T = if (h.pools[@intFromEnum(k)].pop()) |o| blk: {
            const old: *T = @fieldParentPtr("hdr", o);
            if (comptime bufferOf(T)) |f| {
                const saved = @field(old, f);
                old.* = first;
                @field(old, f) = saved;
            } else old.* = first;
            break :blk old;
        } else blk: {
            const fresh = try h.gpa.create(T);
            fresh.* = first;
            break :blk fresh;
        };
        try h.register(&p.hdr, k, @sizeOf(T));
        return p;
    }

    /// The name of the inner list of a heap type, kept when the object is reused.
    fn bufferOf(comptime T: type) ?[]const u8 {
        return switch (T) {
            I.List => "items",
            I.Map => "entries",
            I.Object => "fields",
            I.Scope => "binds",
            else => null,
        };
    }

    /// The kind of the heap type `T`.
    fn kindOf(comptime T: type) Kind {
        return switch (T) {
            I.List => .list,
            I.Map => .map,
            I.Object => .object,
            I.Func => .func,
            I.Range => .range,
            I.Domain => .domain,
            I.Channel => .chan,
            I.Scope => .scope,
            I.Var => .variable,
            else => @compileError("not a heap type"),
        };
    }

    /// Give the object its place, its number and its region.
    fn register(h: *Heap, o: *Obj, kind: Kind, size: usize) error{OutOfMemory}!void {
        o.* = .{ .kind = kind, .seq = h.next_seq, .idx = @intCast(h.objs.items.len) };
        h.next_seq += 1;
        try h.objs.append(h.gpa, o);
        h.stats.made += 1;
        h.stats.live += 1;
        h.stats.bytes += size;
        if (h.stats.live > h.stats.peak_live) h.stats.peak_live = h.stats.live;
        if (h.stats.bytes > h.stats.peak_bytes) h.stats.peak_bytes = h.stats.bytes;
        h.since_trace += 1;
        if (kind != .scope and kind != .variable) try h.zctPush(o);
    }

    /// A new heap string with a copy of `bytes`.
    pub fn str(h: *Heap, bytes: []const u8) error{OutOfMemory}![]const u8 {
        const total = @sizeOf(Str) + bytes.len;
        const mem = try h.allocStr(total);
        const s: *Str = @ptrCast(mem.ptr);
        s.* = .{ .len = @intCast(bytes.len), .cap = @intCast(mem.len) };
        const out = mem[@sizeOf(Str)..][0..bytes.len];
        @memcpy(out, bytes);
        try h.register(&s.hdr, .str, total);
        return out;
    }

    /// The memory for a string of `total` bytes (header included).
    fn allocStr(h: *Heap, total: usize) error{OutOfMemory}![]align(@alignOf(Str)) u8 {
        if (total <= big_min) return h.gpa.alignedAlloc(u8, .of(Str), total);
        const c = std.math.log2_int_ceil(usize, total);
        if (h.big_count[c] > 0) {
            h.big_count[c] -= 1;
            return h.big_blocks[c][h.big_count[c]];
        }
        return h.gpa.alignedAlloc(u8, .of(Str), @as(usize, 1) << @intCast(c));
    }

    /// Give back the memory of a string, or keep a big block for the next big string.
    fn freeStr(h: *Heap, s: *Str) void {
        const base: [*]align(@alignOf(Str)) u8 = @ptrCast(s);
        const mem = base[0..s.cap];
        if (s.cap > big_min) {
            const c = std.math.log2_int_ceil(usize, s.cap);
            if (h.big_count[c] < big_keep) {
                h.big_blocks[c][h.big_count[c]] = mem;
                h.big_count[c] += 1;
                return;
            }
        }
        h.gpa.free(mem);
    }

    /// A new heap string with the bytes of `x` followed by those of `y`.
    pub fn str2(h: *Heap, x: []const u8, y: []const u8) error{OutOfMemory}![]const u8 {
        const total = @sizeOf(Str) + x.len + y.len;
        const mem = try h.allocStr(total);
        const s: *Str = @ptrCast(mem.ptr);
        s.* = .{ .len = @intCast(x.len + y.len), .cap = @intCast(mem.len) };
        const out = mem[@sizeOf(Str)..][0 .. x.len + y.len];
        @memcpy(out[0..x.len], x);
        @memcpy(out[x.len..], y);
        try h.register(&s.hdr, .str, total);
        return out;
    }

    /// The pinned heap copy of a text that never changes (a literal of the script, a constant word).
    pub fn static(h: *Heap, bytes: []const u8) error{OutOfMemory}![]const u8 {
        const key = @intFromPtr(bytes.ptr) ^ (bytes.len << 48);
        const gop = try h.statics.getOrPut(h.gpa, key);
        if (gop.found_existing) return gop.value_ptr.*;
        const s = try h.str(bytes);
        strHdr(s).hdr.pinned = true;
        gop.value_ptr.* = s;
        return s;
    }

    /// The header of a heap string.
    pub fn strHdr(s: []const u8) *Str {
        const p: *Str = @ptrFromInt(@intFromPtr(s.ptr) - @sizeOf(Str));
        std.debug.assert(p.magic == str_magic);
        return p;
    }

    /// The header of a value that lives in the heap, or null for a plain value.
    pub fn hdrOf(v: Value) ?*Obj {
        return switch (v) {
            .str => |s| &strHdr(s).hdr,
            .list, .set => |l| &l.hdr,
            .map => |m| &m.hdr,
            .object => |o| &o.hdr,
            .func => |f| &f.hdr,
            .range => |r| &r.hdr,
            .domain => |d| &d.hdr,
            .chan => |c| &c.hdr,
            else => null,
        };
    }

    // ---- counting -----------------------------------------------------------------------------

    /// One more holder of `v`.
    pub fn retain(v: Value) void {
        if (hdrOf(v)) |o| o.rc += 1;
    }

    /// One holder less: at zero the value waits for the next safe point of its region.
    pub fn release(h: *Heap, v: Value) void {
        const o = hdrOf(v) orelse return;
        h.drop(o);
    }

    fn drop(h: *Heap, o: *Obj) void {
        std.debug.assert(o.rc > 0 or o.pinned);
        if (o.rc > 0) o.rc -= 1;
        if (o.rc == 0 and !o.pinned and !o.in_zct) h.zctPush(o) catch {};
    }

    /// One more holder of a variable.
    pub fn retainVar(v: *I.Var) void {
        v.hdr.rc += 1;
    }

    /// One holder less; the last one frees the variable and lets its value go.
    pub fn releaseVar(h: *Heap, v: *I.Var) void {
        std.debug.assert(v.hdr.rc > 0 or v.hdr.pinned);
        if (v.hdr.rc > 0) v.hdr.rc -= 1;
        if (v.hdr.rc == 0 and !v.hdr.pinned) h.free(&v.hdr, .rc);
    }

    /// One more holder of a scope (a frame, a child scope, a closure).
    pub fn retainScope(s: *I.Scope) void {
        s.hdr.rc += 1;
    }

    /// One holder less; the last one frees the scope, its variables and its hold on its parent.
    pub fn releaseScope(h: *Heap, s: *I.Scope) void {
        std.debug.assert(s.hdr.rc > 0 or s.hdr.pinned);
        if (s.hdr.rc > 0) s.hdr.rc -= 1;
        if (s.hdr.rc == 0 and !s.hdr.pinned) h.free(&s.hdr, .rc);
    }

    /// Keep `v` until the end of the run.
    pub fn pin(v: Value) void {
        if (hdrOf(v)) |o| o.pinned = true;
    }

    // ---- regions and safe points --------------------------------------------------------------

    /// Start a region: the objects made from now on belong to it.
    pub fn pushRegion(h: *Heap) void {
        if (h.depth == h.regions.items.len) {
            h.regions.append(h.gpa, .{ .start = h.next_seq }) catch {
                return; // no memory for the bookkeeping: the objects stay in the outer region
            };
        } else {
            h.regions.items[h.depth].start = h.next_seq;
            h.regions.items[h.depth].zct.clearRetainingCapacity();
        }
        h.depth += 1;
    }

    /// Leave the innermost region.
    pub fn popRegion(h: *Heap) void {
        if (h.depth <= 1) return;
        const inner = &h.regions.items[h.depth - 1];
        const outer = &h.regions.items[h.depth - 2];
        outer.zct.appendSlice(h.gpa, inner.zct.items) catch {
            for (inner.zct.items) |o| o.in_zct = false; // they will be found by the tracing collector
        };
        inner.zct.clearRetainingCapacity();
        h.depth -= 1;
    }

    /// Put an object whose count is zero in the table of its region.
    fn zctPush(h: *Heap, o: *Obj) error{OutOfMemory}!void {
        o.in_zct = true;
        if (h.paused > 0 or h.depth == 0) {
            try h.deferred.append(h.gpa, o);
            return;
        }
        var i = h.depth;
        while (i > 0) {
            i -= 1;
            if (h.regions.items[i].start <= o.seq or i == 0) {
                try h.regions.items[i].zct.append(h.gpa, o);
                return;
            }
        }
    }

    /// A safe point of the innermost region: free its objects whose count is still zero.
    pub fn safePoint(h: *Heap) void {
        if (h.paused > 0 or h.depth == 0) return;
        const r = &h.regions.items[h.depth - 1];
        if (r.zct.items.len > 0) {
            if (verify) h.verifyFrees(h.depth - 1);
            var i: usize = 0;
            while (i < h.regions.items[h.depth - 1].zct.items.len) : (i += 1) {
                const o = h.regions.items[h.depth - 1].zct.items[i];
                o.in_zct = false;
                if (o.rc == 0 and !o.pinned) h.free(o, .rc);
            }
            h.regions.items[h.depth - 1].zct.clearRetainingCapacity();
        }
        // a trace looks only at the objects of this region: it is worth it when the region holds many
        // (a loop at the end of a pass, the body of a process), not at the end of a small inner block
        if (h.since_trace > h.trace_limit and h.next_seq - h.regions.items[h.depth - 1].start > h.trace_limit / 2) h.trace();
    }

    /// A task starts: stop freeing.
    pub fn pause(h: *Heap) void {
        h.paused += 1;
    }

    /// A task has ended and its parent is at `done`: free again when no task is left.
    pub fn resume_(h: *Heap, n: u32) void {
        h.paused -= @min(n, h.paused);
        if (h.paused > 0) return;
        var later = h.deferred;
        h.deferred = .empty;
        defer later.deinit(h.gpa);
        for (later.items) |o| {
            o.in_zct = false;
            if (o.rc == 0 and !o.pinned) h.zctPush(o) catch {};
        }
    }

    // ---- freeing ----------------------------------------------------------------------------

    const Why = enum { rc, gc };

    /// Free one object.
    fn free(h: *Heap, o: *Obj, why: Why) void {
        if (o.kind == .object and !h.finalize(o)) return;
        h.releaseChildren(o);
        h.unregister(o, why);
        h.destroy(o);
    }

    // @eve-impl destructors: run the `destructor` of the class and of its parents, child first, once per object
    // @spec spec/syntax/declarations.md#classes-and-objects
    // @decision D-202
    // @test c41_destructor
    // @invariant a destructor runs while the object is alive (its count is raised) and while freeing is paused, so it frees nothing
    /// False when the destructor kept a reference to the object (the free is cancelled).
    fn finalize(h: *Heap, o: *Obj) bool {
        const f = h.finalizer orelse return true;
        if (o.finalized) return true;
        const ob: *I.Object = @fieldParentPtr("hdr", o);
        if (!(ob.class orelse return true).has_destructor) return true;
        var cur = ob.class;
        var any = false;
        while (cur) |cls| : (cur = cls.parent) {
            if (cls.destructor() != null) any = true;
        }
        o.finalized = true;
        if (!any) return true;
        o.rc += 1;
        h.paused += 1;
        cur = ob.class;
        while (cur) |cls| : (cur = cls.parent) {
            if (cls.destructor() != null) f.run(f.ctx, ob, cls);
        }
        h.paused -= 1;
        o.rc -= 1;
        return o.rc == 0;
    }

    /// The end of a run: the destructors of the objects that are still alive, the newest first (CLS-14).
    pub fn finalizeAll(h: *Heap) void {
        if (h.finalizer == null) return;
        var live: std.ArrayList(*Obj) = .empty;
        defer live.deinit(h.gpa);
        for (h.objs.items) |o| {
            if (o.kind != .object or o.finalized) continue;
            const ob: *I.Object = @fieldParentPtr("hdr", o);
            var cur = ob.class;
            while (cur) |cls| : (cur = cls.parent) {
                if (cls.destructor() != null) {
                    live.append(h.gpa, o) catch return;
                    break;
                }
            }
        }
        std.mem.sort(*Obj, live.items, {}, newer);
        for (live.items) |o| _ = h.finalize(o);
    }

    fn newer(_: void, a: *Obj, b: *Obj) bool {
        return a.seq > b.seq;
    }

    /// Let go of everything the object holds.
    fn releaseChildren(h: *Heap, o: *Obj) void {
        switch (o.kind) {
            .str, .range, .domain => {},
            .list => {
                const l: *I.List = @fieldParentPtr("hdr", o);
                if (l.base) |b| h.drop(&b.hdr) else for (l.items.items) |e| h.release(e);
            },
            .map => {
                const m: *I.Map = @fieldParentPtr("hdr", o);
                for (m.entries.items) |e| {
                    h.release(e.key);
                    h.release(e.val);
                }
            },
            .object => {
                const ob: *I.Object = @fieldParentPtr("hdr", o);
                for (ob.fields.items) |f| h.release(f.val);
            },
            .func => {
                const f: *I.Func = @fieldParentPtr("hdr", o);
                h.releaseScope(f.closure);
            },
            .chan => {
                const c: *I.Channel = @fieldParentPtr("hdr", o);
                for (c.buf.items) |e| h.release(e);
            },
            .scope => {
                const s: *I.Scope = @fieldParentPtr("hdr", o);
                for (s.binds.items) |b| h.releaseVar(b.v);
                if (s.parent) |p| h.releaseScope(p);
            },
            .variable => {
                const v: *I.Var = @fieldParentPtr("hdr", o);
                h.release(v.value);
            },
        }
    }

    /// Take the object out of the list of live objects.
    fn unregister(h: *Heap, o: *Obj, why: Why) void {
        const last = h.objs.pop().?;
        if (last != o) {
            h.objs.items[o.idx] = last;
            last.idx = o.idx;
        }
        h.stats.live -= 1;
        h.stats.bytes -|= sizeOf(o);
        if (why == .rc) h.stats.freed_rc += 1 else h.stats.freed_gc += 1;
    }

    /// The bytes counted for an object (its struct, or a string's header and text).
    fn sizeOf(o: *Obj) u64 {
        return switch (o.kind) {
            .str => blk: {
                const s: *Str = @fieldParentPtr("hdr", o);
                break :blk @sizeOf(Str) + s.len;
            },
            .list => @sizeOf(I.List),
            .map => @sizeOf(I.Map),
            .object => @sizeOf(I.Object),
            .func => @sizeOf(I.Func),
            .range => @sizeOf(I.Range),
            .domain => @sizeOf(I.Domain),
            .chan => @sizeOf(I.Channel),
            .scope => @sizeOf(I.Scope),
            .variable => @sizeOf(I.Var),
        };
    }

    /// Free the memory of an object, or keep the object for reuse.
    fn destroy(h: *Heap, o: *Obj) void {
        const pool = &h.pools[@intFromEnum(o.kind)];
        const poolable = o.kind != .str and o.kind != .chan and pool.items.len < pool_max;
        if (poolable) {
            switch (o.kind) {
                .list => trimBuffer(h, &@as(*I.List, @fieldParentPtr("hdr", o)).items),
                .map => trimBuffer(h, &@as(*I.Map, @fieldParentPtr("hdr", o)).entries),
                .object => trimBuffer(h, &@as(*I.Object, @fieldParentPtr("hdr", o)).fields),
                .scope => trimBuffer(h, &@as(*I.Scope, @fieldParentPtr("hdr", o)).binds),
                else => {},
            }
            pool.append(h.gpa, o) catch return h.releaseMemory(o);
            return;
        }
        h.releaseMemory(o);
    }

    /// Empty an inner list for reuse, or free it when it grew big.
    fn trimBuffer(h: *Heap, list: anytype) void {
        if (list.capacity > buffer_max) {
            list.deinit(h.gpa); // `deinit` leaves the list undefined: it is set again to empty
            list.* = .empty;
        } else list.clearRetainingCapacity();
    }

    /// Give the memory of an object back to the allocator.
    fn releaseMemory(h: *Heap, o: *Obj) void {
        switch (o.kind) {
            .str => h.freeStr(@fieldParentPtr("hdr", o)),
            .list => {
                const l: *I.List = @fieldParentPtr("hdr", o);
                l.items.deinit(h.gpa);
                h.gpa.destroy(l);
            },
            .map => {
                const m: *I.Map = @fieldParentPtr("hdr", o);
                m.entries.deinit(h.gpa);
                h.gpa.destroy(m);
            },
            .object => {
                const ob: *I.Object = @fieldParentPtr("hdr", o);
                ob.fields.deinit(h.gpa);
                h.gpa.destroy(ob);
            },
            .func => h.gpa.destroy(@as(*I.Func, @fieldParentPtr("hdr", o))),
            .range => h.gpa.destroy(@as(*I.Range, @fieldParentPtr("hdr", o))),
            .domain => h.gpa.destroy(@as(*I.Domain, @fieldParentPtr("hdr", o))),
            .chan => {
                const c: *I.Channel = @fieldParentPtr("hdr", o);
                c.buf.deinit(h.gpa);
                h.gpa.destroy(c);
            },
            .scope => {
                const sc: *I.Scope = @fieldParentPtr("hdr", o);
                sc.binds.deinit(h.gpa);
                h.gpa.destroy(sc);
            },
            .variable => h.gpa.destroy(@as(*I.Var, @fieldParentPtr("hdr", o))),
        }
    }

    // ---- the tracing collector ------------------------------------------------------------------

    /// Mark `o` and everything it reaches.
    pub fn markFrom(h: *Heap, o: *Obj) void {
        if (o.mark) return;
        o.mark = true;
        h.marks.append(h.gpa, o) catch return;
        while (h.marks.pop()) |x| h.markChildren(x);
    }

    /// Mark the heap object of a value, if it has one.
    pub fn markValue(h: *Heap, v: Value) void {
        if (hdrOf(v)) |o| h.push(o);
    }

    fn push(h: *Heap, o: *Obj) void {
        if (o.mark) return;
        o.mark = true;
        h.marks.append(h.gpa, o) catch {};
    }

    fn markChildren(h: *Heap, o: *Obj) void {
        switch (o.kind) {
            .str, .range, .domain => {},
            .list => {
                const l: *I.List = @fieldParentPtr("hdr", o);
                if (l.base) |b| h.push(&b.hdr) else for (l.items.items) |e| h.markValue(e);
            },
            .map => {
                const m: *I.Map = @fieldParentPtr("hdr", o);
                for (m.entries.items) |e| {
                    h.markValue(e.key);
                    h.markValue(e.val);
                }
            },
            .object => {
                const ob: *I.Object = @fieldParentPtr("hdr", o);
                for (ob.fields.items) |f| h.markValue(f.val);
            },
            .func => h.push(&@as(*I.Func, @fieldParentPtr("hdr", o)).closure.hdr),
            .chan => {
                const c: *I.Channel = @fieldParentPtr("hdr", o);
                for (c.buf.items) |e| h.markValue(e);
            },
            .scope => {
                const s: *I.Scope = @fieldParentPtr("hdr", o);
                for (s.binds.items) |b| h.push(&b.v.hdr);
                if (s.parent) |p| h.push(&p.hdr);
            },
            .variable => h.markValue(@as(*I.Var, @fieldParentPtr("hdr", o)).value),
        }
    }

    /// Mark everything that may still be used, for a trace of the objects made since `start`.
    fn markRoots(h: *Heap, start: u64, skip_region: ?usize) void {
        if (h.root_fn) |f| f(h.root_ctx, h);
        for (h.regions.items[0..h.depth], 0..) |r, ri| {
            if (skip_region != null and ri == skip_region.?) continue;
            for (r.zct.items) |o| h.push(o);
        }
        for (h.deferred.items) |o| h.push(o);
        for (h.objs.items) |o| if (o.pinned or o.seq < start) h.push(o);
        while (h.marks.pop()) |x| h.markChildren(x);
    }

    /// The backup collector: free the unreachable objects of the innermost region (cycles included).
    pub fn trace(h: *Heap) void {
        if (h.paused > 0 or h.depth == 0) return;
        const start = h.regions.items[h.depth - 1].start;
        h.markRoots(start, null);
        var garbage: std.ArrayList(*Obj) = .empty;
        defer garbage.deinit(h.gpa);
        var late: std.ArrayList(*Obj) = .empty;
        defer late.deinit(h.gpa);
        for (h.objs.items) |o| {
            if (!o.mark and !o.in_zct and !o.pinned and o.seq >= start) garbage.append(h.gpa, o) catch {
                h.clearMarks();
                return;
            };
        }
        if (h.finalizer != null) {
            std.mem.sort(*Obj, garbage.items, {}, newer);
            for (garbage.items) |o| if (o.kind == .object) {
                _ = h.finalize(o);
            };
        }
        for (garbage.items) |o| h.dropSurvivors(o, &late);
        for (garbage.items) |o| {
            h.unregister(o, .gc);
            h.destroy(o);
        }
        h.clearMarks();
        for (late.items) |o| if (o.rc == 0 and !o.pinned) h.free(o, .gc);
        h.stats.traces += 1;
        h.since_trace = 0;
        h.trace_limit = @max(200_000, h.stats.live);
    }

    /// Lower the counts of the survivors held by the garbage object `o`.
    fn dropSurvivors(h: *Heap, o: *Obj, late: *std.ArrayList(*Obj)) void {
        switch (o.kind) {
            .str, .range, .domain => {},
            .list => {
                const l: *I.List = @fieldParentPtr("hdr", o);
                if (l.base) |b| h.dropIfAlive(&b.hdr, late) else for (l.items.items) |e| if (hdrOf(e)) |c| h.dropIfAlive(c, late);
            },
            .map => {
                const m: *I.Map = @fieldParentPtr("hdr", o);
                for (m.entries.items) |e| {
                    if (hdrOf(e.key)) |c| h.dropIfAlive(c, late);
                    if (hdrOf(e.val)) |c| h.dropIfAlive(c, late);
                }
            },
            .object => {
                const ob: *I.Object = @fieldParentPtr("hdr", o);
                for (ob.fields.items) |f| if (hdrOf(f.val)) |c| h.dropIfAlive(c, late);
            },
            .func => h.dropIfAlive(&@as(*I.Func, @fieldParentPtr("hdr", o)).closure.hdr, late),
            .chan => {
                const c: *I.Channel = @fieldParentPtr("hdr", o);
                for (c.buf.items) |e| if (hdrOf(e)) |x| h.dropIfAlive(x, late);
            },
            .scope => {
                const s: *I.Scope = @fieldParentPtr("hdr", o);
                for (s.binds.items) |b| h.dropIfAlive(&b.v.hdr, late);
                if (s.parent) |p| h.dropIfAlive(&p.hdr, late);
            },
            .variable => if (hdrOf(@as(*I.Var, @fieldParentPtr("hdr", o)).value)) |c| h.dropIfAlive(c, late),
        }
    }

    fn dropIfAlive(h: *Heap, c: *Obj, late: *std.ArrayList(*Obj)) void {
        if (!c.mark) return;
        if (c.rc > 0) c.rc -= 1;
        if (c.rc != 0 or c.pinned or c.in_zct) return;
        if (c.kind == .scope or c.kind == .variable) late.append(h.gpa, c) catch {} else h.zctPush(c) catch {};
    }

    fn clearMarks(h: *Heap) void {
        for (h.objs.items) |o| o.mark = false;
    }

    // ---- verification ----------------------------------------------------------------------------

    /// `EVE_GC_VERIFY=1`: before the zero counts of a region are freed, check that none of them can be
    /// reached from the roots. A reachable one means that a holder forgot to count it.
    fn verifyFrees(h: *Heap, region: usize) void {
        h.markRoots(0, region);
        for (h.regions.items[region].zct.items) |o| {
            if (o.rc == 0 and !o.pinned and o.mark) {
                h.clearMarks();
                std.debug.panic("heap: a {s} with count 0 is still reachable (a holder forgot to count it)", .{@tagName(o.kind)});
            }
        }
        h.clearMarks();
    }

    /// Print the statistics (`EVE_MEMSTATS=1`).
    pub fn report(h: *Heap) void {
        const s = h.stats;
        std.debug.print("heap: {d} objects made, {d} freed by count, {d} freed by trace ({d} traces), {d} live; peak {d} objects, {d} KB\n", .{ s.made, s.freed_rc, s.freed_gc, s.traces, s.live, s.peak_live, s.peak_bytes / 1024 });
    }
};

test "a temporary is freed at the safe point of its region, a stored value survives" {
    var h = Heap.init(std.testing.allocator);
    defer h.deinit();
    h.pushRegion();
    h.pushRegion();
    const kept = try h.make(I.List, .{});
    _ = try h.str("a temporary");
    const cell = try h.make(I.Var, .{ .value = .{ .list = kept } });
    Heap.retain(.{ .list = kept });
    Heap.retainVar(cell);
    h.safePoint();
    try std.testing.expectEqual(@as(u64, 1), h.stats.freed_rc); // the string nobody stored
    try std.testing.expectEqual(@as(u64, 2), h.stats.live);
    h.releaseVar(cell); // the variable goes at once, its list waits for the safe point
    try std.testing.expectEqual(@as(u64, 1), h.stats.live);
    h.safePoint();
    try std.testing.expectEqual(@as(u64, 0), h.stats.live);
}

test "the tracing collector frees a cycle that reference counting keeps" {
    const ast = @import("ast.zig");
    var h = Heap.init(std.testing.allocator);
    defer h.deinit();
    h.pushRegion();
    h.pushRegion();
    // a scope holds a variable that holds a function that closes over the scope
    const s = try h.make(I.Scope, .{});
    Heap.retainScope(s); // the frame that runs in it
    const f = try h.make(I.Func, .{ .node = &ast.none, .closure = s });
    Heap.retainScope(s);
    const v = try h.make(I.Var, .{ .value = .{ .func = f } });
    Heap.retain(.{ .func = f });
    try s.binds.append(h.gpa, .{ .name = "f", .v = v });
    Heap.retainVar(v);
    h.releaseScope(s); // the frame ends: the closure still counts the scope
    h.safePoint();
    try std.testing.expectEqual(@as(u64, 3), h.stats.live);
    h.trace();
    try std.testing.expectEqual(@as(u64, 0), h.stats.live);
    try std.testing.expectEqual(@as(u64, 3), h.stats.freed_gc);
}
