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
const I = @import("interp.zig");
const Value = I.Value;

// Zig tip: an `enum(u8)` is a set of names stored in one byte. `switch` on it must cover every name,
// so adding a kind makes the compiler point at every place that must handle it.
/// The kind of a heap object.
pub const Kind = enum(u8) { str, list, map, object, func, range, domain, chan, scope, variable };

// Zig tip: every heap object starts with this header, as its first field `hdr`. A pointer to the header
// leads back to the whole object with `@fieldParentPtr("hdr", h)`: the compiler knows where the field
// is inside the struct and subtracts its offset. That is how one list of headers holds objects of
// many types.
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
};

// Zig tip: a string of the heap is a header followed by its bytes, in one allocation. The `Value`
// keeps only the slice of bytes; the header is found by stepping back `@sizeOf(Str)` bytes. `magic`
// guards that rule: a slice that does not come from the heap has no magic before it, and the check
// stops the program instead of reading garbage.
/// The header of a heap string; the bytes follow it.
pub const Str = struct {
    hdr: Obj = .{ .kind = .str },
    magic: u32 = str_magic,
    len: u32 = 0,
    /// The bytes allocated for the header and the text (a big string gets a rounded size, see `allocStr`).
    cap: u32 = 0,
};
const str_magic: u32 = 0x5354_524e;

// Zig tip: `Region` relies on the same Zig feature as `Str` above: see the tip there.
/// Objects made since `start`, and the ones among them whose count fell to zero.
const Region = struct { start: u64, zct: std.ArrayList(*Obj) = .empty };

// Zig tip: a struct whose fields all have defaults is built with `.{}`; the heap keeps one and adds to
// its counters as objects are made and freed.
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

// Zig tip: a global `var` set once by main.zig, like `project.env_lib_path`: the library reads the
// environment through the program, which owns it.
/// `EVE_MEMSTATS=1`: print the statistics of the heap when the run ends.
pub var show_stats: bool = false;
/// `EVE_GC_VERIFY=1`: check every free of the reference count against a trace (slow, for the tests).
pub var verify: bool = false;

// Zig tip: `Heap` is created once per run and shared by the driver and its tasks. `gpa` is the
// general-purpose allocator that gives memory back one object at a time (`smp_allocator`, fast and
// safe between threads); `objs` lists every live object for the tracing collector.
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

    const kind_count = @typeInfo(Kind).@"enum".fields.len;
    /// How many freed objects of one kind are kept, and the largest inner buffer kept with them.
    const pool_max = 4096;
    const buffer_max = 64;

    // Zig tip: `init` returns the struct by value; the first region, which starts at 1, is the whole run:
    // it is never left, so objects that outlive every block end up there.
    /// A new heap over the allocator `gpa`.
    pub fn init(gpa: std.mem.Allocator) Heap {
        return .{ .gpa = gpa };
    }

    // Zig tip: `deinit` frees every object still alive without looking at the counts: the run is over.
    // `@fieldParentPtr` goes from the header to the object (see `Obj`).
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

    // Zig tip: `comptime T: type` makes `make` generic: the compiler writes one copy per type it is
    // called with (`List`, `Map`, ...). `@hasField` checks at compile time that `T` has a header.
    // The caller's initial value is copied first, then the header is filled, so a literal such as
    // `.{ .array = true }` cannot reset the bookkeeping.
    /// A new object of type `T` with the fields of `first`, registered in the heap, count zero.
    // Zig tip: a freed object of the same kind is reused when one waits in the pool: no call to the
    // allocator. Its inner buffer (the elements of a list, the variables of a scope) is kept too:
    // `@field(p, name)` reads a field whose name is known at compile time, so the buffer is saved
    // before the new value is copied in and put back after.
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

    // Zig tip: a function that returns `?[]const u8` at compile time can be used in `if (comptime ...)`:
    // the branch that does not apply is not even compiled for that type.
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

    // Zig tip: `kindOf` runs at compile time: a `switch` on a type compares it with each listed type.
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

    // Zig tip: a new object starts with count zero and goes to the zero count table of the region:
    // if nobody stores it before the next safe point, it was a temporary and is freed there.
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

    // Zig tip: `alignedAlloc(u8, .of(Str), n)` asks for bytes aligned like a `Str`, so the header can be
    // written at the start with `@ptrCast`. The bytes of the text follow the header.
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

    // Zig tip: `std.math.log2_int_ceil` gives the exponent of the next power of two. A big block comes
    // from the cache of its size when one waits there; otherwise from the allocator, which for more
    // than 32 KB asks the operating system each time, the cost the cache avoids.
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

    // Zig tip: `freeStr` relies on the same Zig feature as `allocStr` above: see the tip there.
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

    // Zig tip: `str2` relies on the same Zig feature as `str` above: see the tip there. Joining two texts
    // copies each one once, straight into the new string.
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

    // Zig tip: `getOrPut` looks a key up and makes room for it when it is missing, in one search; the
    // address of the original text is the key, so the same literal always gives the same copy.
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

    // Zig tip: `@ptrFromInt(@intFromPtr(p) - n)` steps back `n` bytes from a pointer; the result is a
    // pointer to the header. `std.debug.assert` stops a Debug or ReleaseSafe build when it is false.
    /// The header of a heap string.
    pub fn strHdr(s: []const u8) *Str {
        const p: *Str = @ptrFromInt(@intFromPtr(s.ptr) - @sizeOf(Str));
        std.debug.assert(p.magic == str_magic);
        return p;
    }

    // Zig tip: a `switch` with `|x|` captures the payload of each union case; kinds that are plain values
    // (numbers, booleans) have no header and answer null.
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

    // Zig tip: `if (hdrOf(v)) |o|` runs only for heap values; numbers cost one test of the tag.
    /// One more holder of `v`.
    pub fn retain(v: Value) void {
        if (hdrOf(v)) |o| o.rc += 1;
    }

    // Zig tip: `release` relies on the same Zig feature as `retain` above: see the tip there.
    /// One holder less: at zero the value waits for the next safe point of its region.
    pub fn release(h: *Heap, v: Value) void {
        const o = hdrOf(v) orelse return;
        h.drop(o);
    }

    // Zig tip: `drop` relies on the same Zig feature as `retain` above: see the tip there.
    fn drop(h: *Heap, o: *Obj) void {
        std.debug.assert(o.rc > 0 or o.pinned);
        if (o.rc > 0) o.rc -= 1;
        if (o.rc == 0 and !o.pinned and !o.in_zct) h.zctPush(o) catch {};
    }

    // Zig tip: variables and scopes are freed at once when their count reaches zero: only the
    // interpreter's own frames hold them, and a frame counts itself (see `Interp.enterScope`).
    /// One more holder of a variable.
    pub fn retainVar(v: *I.Var) void {
        v.hdr.rc += 1;
    }

    // Zig tip: `releaseVar` relies on the same Zig feature as `retainVar` above: see the tip there.
    /// One holder less; the last one frees the variable and lets its value go.
    pub fn releaseVar(h: *Heap, v: *I.Var) void {
        std.debug.assert(v.hdr.rc > 0 or v.hdr.pinned);
        if (v.hdr.rc > 0) v.hdr.rc -= 1;
        if (v.hdr.rc == 0 and !v.hdr.pinned) h.free(&v.hdr, .rc);
    }

    // Zig tip: `retainScope` relies on the same Zig feature as `retainVar` above: see the tip there.
    /// One more holder of a scope (a frame, a child scope, a closure).
    pub fn retainScope(s: *I.Scope) void {
        s.hdr.rc += 1;
    }

    // Zig tip: `releaseScope` relies on the same Zig feature as `retainVar` above: see the tip there.
    /// One holder less; the last one frees the scope, its variables and its hold on its parent.
    pub fn releaseScope(h: *Heap, s: *I.Scope) void {
        std.debug.assert(s.hdr.rc > 0 or s.hdr.pinned);
        if (s.hdr.rc > 0) s.hdr.rc -= 1;
        if (s.hdr.rc == 0 and !s.hdr.pinned) h.free(&s.hdr, .rc);
    }

    // Zig tip: pinning an object keeps it to the end of the run, whatever its count says.
    /// Keep `v` until the end of the run.
    pub fn pin(v: Value) void {
        if (hdrOf(v)) |o| o.pinned = true;
    }

    // ---- regions and safe points --------------------------------------------------------------

    // Zig tip: the regions are a stack that is never shrunk: a popped slot keeps its table's memory for
    // the next push (`clearRetainingCapacity`), so a loop that enters a block a million times allocates
    // once.
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

    // Zig tip: what a region did not free goes to the region around it, whose objects now include it.
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

    // Zig tip: the regions are searched from the innermost: the first one whose start is not after the
    // object is the one it belongs to. While tasks run, the table waits in `deferred`.
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

    // Zig tip: the loop reads `zct.items` again at each pass because freeing an object may add its
    // children to the same table (and the list may move in memory when it grows).
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

    // Zig tip: `pause` and `resume_` count the tasks; the trailing underscore avoids the keyword `resume`.
    /// A task starts: stop freeing.
    pub fn pause(h: *Heap) void {
        h.paused += 1;
    }

    // Zig tip: the deferred zero counts go back into the regions of the driver, by their number.
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

    // Zig tip: an enum without a tag type is the smallest way to name a few cases: here, which of the two
    // collectors freed an object, for the statistics.
    const Why = enum { rc, gc };

    // Zig tip: freeing an object first lets go of what it holds (its elements, its variables, its
    // closure), then gives its memory back. A child whose count falls to zero is not freed here but
    // waits in a table: no deep recursion, even for a list of a million lists.
    /// Free one object.
    fn free(h: *Heap, o: *Obj, why: Why) void {
        h.releaseChildren(o);
        h.unregister(o, why);
        h.destroy(o);
    }

    // Zig tip: `@fieldParentPtr("hdr", o)` returns the object that contains the header `o`; the type
    // of the result comes from the variable it is assigned to (`const l: *I.List = ...`).
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

    // Zig tip: `swapRemove`-style removal: the last object takes the place of the removed one and its
    // `idx` is updated, so removing costs the same for any position.
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

    // Zig tip: `sizeOf` relies on the same Zig feature as `releaseChildren` above: see the tip there.
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

    // Zig tip: `destroy` keeps the object in the pool of its kind when there is room, with its inner
    // buffer emptied (`clearRetainingCapacity` keeps the memory, sets the length to zero); a big buffer
    // is given back, so a pooled list never pins a lot of memory. Strings and channels are not pooled.
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

    // Zig tip: `anytype` lets one function take a pointer to any `ArrayList`: the compiler makes one copy
    // per list type it is called with.
    /// Empty an inner list for reuse, or free it when it grew big.
    fn trimBuffer(h: *Heap, list: anytype) void {
        if (list.capacity > buffer_max) {
            list.deinit(h.gpa); // `deinit` leaves the list undefined: it is set again to empty
            list.* = .empty;
        } else list.clearRetainingCapacity();
    }

    // Zig tip: `releaseMemory` gives back the memory of one object and of the list it owns (`deinit`). A
    // string is freed with the same size and alignment it was allocated with.
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

    // Zig tip: marking uses an explicit stack (`marks`) instead of recursion, so a very long chain of
    // lists cannot overflow the Zig call stack.
    /// Mark `o` and everything it reaches.
    pub fn markFrom(h: *Heap, o: *Obj) void {
        if (o.mark) return;
        o.mark = true;
        h.marks.append(h.gpa, o) catch return;
        while (h.marks.pop()) |x| h.markChildren(x);
    }

    // Zig tip: `markValue` relies on the same Zig feature as `markFrom` above: see the tip there.
    /// Mark the heap object of a value, if it has one.
    pub fn markValue(h: *Heap, v: Value) void {
        if (hdrOf(v)) |o| h.push(o);
    }

    // Zig tip: `push` relies on the same Zig feature as `markFrom` above: see the tip there.
    fn push(h: *Heap, o: *Obj) void {
        if (o.mark) return;
        o.mark = true;
        h.marks.append(h.gpa, o) catch {};
    }

    // Zig tip: `markChildren` relies on the same Zig feature as `releaseChildren` above: see the tip there.
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

    // Zig tip: the roots of a trace are what the interpreter can still reach without the heap: its
    // scopes (given by `root_fn`), the pinned objects, and every object waiting in a zero count table
    // (it may be a temporary of a statement that has not ended). Objects older than the innermost
    // region are roots too: a statement of an outer region may still hold them.
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

    // Zig tip: a trace has two passes over the garbage: first every garbage object lets go of the
    // objects that survive (their counts must stay right), then the garbage is freed without looking
    // at its children again, since they may be garbage already freed. A variable or a scope that only
    // garbage held is freed last, once the garbage is gone.
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

    // Zig tip: after the marking, a child that is marked survives the trace; an unmarked one is garbage
    // too and is left alone. `late` collects the variables and scopes that nobody holds any more.
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

    // Zig tip: `dropIfAlive` relies on the same Zig feature as `dropSurvivors` above: see the tip there.
    fn dropIfAlive(h: *Heap, c: *Obj, late: *std.ArrayList(*Obj)) void {
        if (!c.mark) return;
        if (c.rc > 0) c.rc -= 1;
        if (c.rc != 0 or c.pinned or c.in_zct) return;
        if (c.kind == .scope or c.kind == .variable) late.append(h.gpa, c) catch {} else h.zctPush(c) catch {};
    }

    // Zig tip: `clearMarks` relies on the same Zig feature as `markFrom` above: see the tip there.
    fn clearMarks(h: *Heap) void {
        for (h.objs.items) |o| o.mark = false;
    }

    // ---- verification ----------------------------------------------------------------------------

    // Zig tip: `std.debug.panic` stops the program with a message and a stack trace: a wrong count is a
    // bug of the interpreter, never of the script.
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

    // Zig tip: `std.debug.print` writes to the standard error, which the tests do not compare.
    /// Print the statistics (`EVE_MEMSTATS=1`).
    pub fn report(h: *Heap) void {
        const s = h.stats;
        std.debug.print("heap: {d} objects made, {d} freed by count, {d} freed by trace ({d} traces), {d} live; peak {d} objects, {d} KB\n", .{ s.made, s.freed_rc, s.freed_gc, s.traces, s.live, s.peak_live, s.peak_bytes / 1024 });
    }
};

// Zig tip: the testing allocator fails a test that does not give back every byte: `deinit` of the heap must
// free the live objects, the pooled ones and the tables. `defer` runs it however the test ends.
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

// Zig tip: `&ast.none` is the address of a constant node that the interpreter shares for "nothing"; a
// function object only needs some node to point to.
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
