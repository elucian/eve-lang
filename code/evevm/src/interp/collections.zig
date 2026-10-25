//! @eve-module interp.collections
//! @spec spec/syntax/expressions.md#index-slice-member, spec/syntax/expressions.md#literals-and-builders
//! @feature F-LNG-07
//! @tests test/level1
//! Collections: iteration, builders, indexing and slicing.
//! Part of the interpreter (interp.zig): every function takes the interpreter as `it: *Interp`, and
//! `Interp` names each of them again, so a call reads `it.name(...)` wherever it is made.
const std = @import("std");
const bytesfn = @import("bytesfn.zig");
const interp = @import("../interp.zig");
const Interp = interp.Interp;
const dlib = interp.dlib;
const Node = interp.Node;
const value = interp.value;
const Signal = interp.Signal;
const Value = interp.Value;
const List = interp.List;
const Range = interp.Range;
const err_index = interp.err_index;
const err_key = interp.err_key;

// ---- collections: iteration, builders, indexing ---------------------------------------

/// The elements of a collection, a range or a string, as a slice.
pub fn iterate(it: *Interp, v: Value) Signal![]const Value {
    switch (v) {
        .list, .set => |l| return l.elems(),
        .range => |r| {
            var out: std.ArrayList(Value) = .empty;
            var k = r.lo;
            while (k <= r.hi) : (k += r.step) {
                if (r.sym) try out.append(it.t, .{ .sym = @intCast(k) }) else try out.append(it.t, .{ .int = k });
            }
            return out.items;
        },
        .str => |s| {
            var out: std.ArrayList(Value) = .empty;
            var view = std.unicode.Utf8View.init(s) catch return it.fail("the string is not valid UTF-8", .{});
            var iter = view.iterator();
            while (iter.nextCodepoint()) |cp| try out.append(it.t, .{ .sym = cp });
            return out.items;
        },
        .map => |m| {
            var out: std.ArrayList(Value) = .empty;
            for (m.entries.items) |e| try out.append(it.t, .{ .list = try it.newList(&.{ e.key, e.val }, false) });
            return out.items;
        },
        .object => |o| {
            if (dlib.isStream(it, v)) return dlib.drain(it, o);
            if (o.class == null or o.class != it.base().gen_class) return it.fail("{s} is not iterable", .{Interp.typeName(v)});
            // a comprehension or a conversion collects every value of a generator
            const gs = it.base().gens.items[@intCast(Interp.intOf(Interp.fieldOf(o, "handle").?))];
            var out: std.ArrayList(Value) = .empty;
            while (try it.genNext(gs)) try out.append(it.t, gs.value);
            return out.items;
        },
        else => return it.fail("{s} is not iterable", .{Interp.typeName(v)}),
    }
}

/// Give the names of a loop or builder pattern their values: `x`, or `(a, b)` for a pair.
pub fn bindPattern(it: *Interp, pat: *const Node, v: Value) Signal!void {
    switch (pat.tag) {
        .name => try it.define(pat.text, v, false),
        .list => {
            // `for (k: v) in map`: the parentheses hold one pair
            if (pat.kids.len == 1 and pat.kids[0].tag == .pair) return it.bindPattern(pat.kids[0], v);
            const items = try it.iterate(v);
            for (pat.kids, 0..) |k, i| {
                if (i < items.len) try it.bindPattern(k, items[i]);
            }
        },
        .pair => {
            const items = try it.iterate(v);
            if (items.len != 2) return it.fail("a pair (key: value) is expected", .{});
            try it.bindPattern(pat.kids[0], items[0]);
            try it.bindPattern(pat.kids[1], items[1]);
        },
        else => return it.fail("bad loop variable", .{}),
    }
}

/// `(item | x in source and cond)`, `[...]` and `{...}`.
pub fn builder(it: *Interp, n: *const Node) Signal!Value {
    const saved = try it.pushScope();
    defer it.leaveScope(saved);
    var conds: std.ArrayList(*const Node) = .empty;
    var g = n.kids[1];
    while (g.tag == .bin and std.mem.eql(u8, g.text, "and")) {
        try conds.append(it.t, g.kids[1]);
        g = g.kids[0];
    }
    if (g.tag != .bin or !std.mem.eql(u8, g.text, "in")) return it.fail("a builder needs 'x in collection'", .{});
    const pat = g.kids[0];
    const src = g.kids[1];
    const open = n.text[0];
    const out = try it.h.make(List, .{ .array = open == '[' });

    if (src.tag == .bin and std.mem.eql(u8, src.text, "><")) {
        const xs = try it.iterate(try it.eval(src.kids[0]));
        const ys = try it.iterate(try it.eval(src.kids[1]));
        for (xs) |x| {
            const row = try it.h.make(List, .{ .array = true });
            for (ys) |y| {
                try it.bindPattern(pat, .{ .list = try it.newList(&.{ x, y }, false) });
                if (!try it.allTrue(conds.items)) continue;
                const v = try it.eval(n.kids[0]);
                if (open == '[') try it.listAppend(row, v) else try it.collect(out, open, v);
            }
            if (open == '[') try it.listAppend(out, .{ .list = row });
        }
    } else {
        for (try it.iterate(try it.eval(src))) |x| {
            try it.bindPattern(pat, x);
            if (!try it.allTrue(conds.items)) continue;
            try it.collect(out, open, try it.eval(n.kids[0]));
        }
    }
    return if (open == '{') .{ .set = out } else .{ .list = out };
}

pub fn allTrue(it: *Interp, conds: []const *const Node) Signal!bool {
    for (conds) |c| if (!try it.truth(try it.eval(c))) return false;
    return true;
}

pub fn collect(it: *Interp, out: *List, open: u8, v: Value) Signal!void {
    if (open == '{') try it.setAdd(out, v) else try it.listAppend(out, v);
}

// One index of `a[i, j]`: a number, `$` (already a number), `*` (all) or a range.
pub const Idx = union(enum) { one: i64, all, rng: struct { lo: i64, hi: i64 } };

/// A matrix or a tensor is an array whose elements are arrays.
// @decision D-064
/// Is `l` a matrix or a tensor: an array whose elements are arrays?
pub fn isMatrix(l: *List) bool {
    return l.array and l.elems().len > 0 and l.elems()[0] == .list and l.elems()[0].list.array;
}

pub fn dimLen(root: *List, depth: usize) i64 {
    var l = root;
    var d: usize = 0;
    while (d < depth) : (d += 1) {
        const e = l.elems();
        if (e.len == 0 or e[0] != .list) return 0;
        l = e[0].list;
    }
    return @intCast(l.elems().len);
}

pub fn evalIdx(it: *Interp, n: *const Node, len: i64) Signal!Idx {
    if (n.tag == .all) return .all;
    const saved = it.dollar;
    it.dollar = len;
    defer it.dollar = saved;
    if (n.tag == .range) {
        const r = try it.makeRange(n);
        const lo = if (r.range.lo < 0) len + 1 + r.range.lo else r.range.lo;
        const hi = if (r.range.hi < 0) len + 1 + r.range.hi else r.range.hi;
        return .{ .rng = .{ .lo = lo, .hi = hi } };
    }
    const v = try it.eval(n);
    if (!Interp.isInt(v)) return it.fail("an index must be an integer, found {s}", .{Interp.typeName(v)});
    const k = Interp.intOf(v);
    return .{ .one = if (k < 0) len + 1 + k else k };
}

pub fn leaves(it: *Interp, l: *List, out: *std.ArrayList(*Value)) Signal!void {
    for (l.elems()) |*e| {
        if (e.* == .list) try it.leaves(e.list, out) else try out.append(it.t, e);
    }
}

/// The storage cells an index expression selects (one for `a[2]`, several for a slice or `[*]`).
pub fn slots(it: *Interp, root: *List, args: []const *const Node, out: *std.ArrayList(*Value)) Signal!void {
    if (args.len == 1 and Interp.isMatrix(root)) {
        // one absolute row-major index, or all the elements, or a range of them
        var flat: std.ArrayList(*Value) = .empty;
        try it.leaves(root, &flat);
        const ix = try it.evalIdx(args[0], @intCast(flat.items.len));
        try it.pick(flat.items, ix, out);
        return;
    }
    try it.walk(root, args, 0, out);
}

pub fn pick(it: *Interp, cells: []*Value, ix: Idx, out: *std.ArrayList(*Value)) Signal!void {
    switch (ix) {
        .all => for (cells) |c| try out.append(it.t, c),
        .one => |k| {
            if (k < 1 or k > cells.len) return it.failWith(err_index, "Index {d} is out of range 1..{d}", .{ k, cells.len });
            try out.append(it.t, cells[@intCast(k - 1)]);
        },
        .rng => |r| {
            if (r.lo > r.hi) return;
            if (r.lo < 1 or r.hi > cells.len) return it.failWith(err_index, "Range {d}..{d} is out of range 1..{d}", .{ r.lo, r.hi, cells.len });
            for (cells[@intCast(r.lo - 1)..@intCast(r.hi)]) |c| try out.append(it.t, c);
        },
    }
}

pub fn walk(it: *Interp, l: *List, args: []const *const Node, depth: usize, out: *std.ArrayList(*Value)) Signal!void {
    const ix = try it.evalIdx(args[depth], Interp.dimLen(l, 0));
    var cells: std.ArrayList(*Value) = .empty;
    for (l.elems()) |*e| try cells.append(it.t, e);
    var picked: std.ArrayList(*Value) = .empty;
    try it.pick(cells.items, ix, &picked);
    for (picked.items) |c| {
        if (depth + 1 == args.len) {
            try out.append(it.t, c);
        } else if (c.* == .list) {
            try it.walk(c.list, args, depth + 1, out);
        } else return it.fail("too many indexes", .{});
    }
}

/// Resolves a chain of brackets `a[i][j]...` to the value indexed last and its indexes. On a
/// matrix or a tensor the remaining groups merge into one: `m[x][y]` is `m[x, y]` (D-064). One
/// group alone keeps its meaning: `m[k]` is the absolute row-major index.
pub fn indexChain(it: *Interp, n: *const Node) Signal!struct { obj: Value, args: []const *const Node } {
    // the parser nests `a[i][j]` as Interp.index(Interp.index(a, i), j): collect the groups outside-in, then reverse
    var groups: std.ArrayList([]const *const Node) = .empty;
    var root = n;
    while (root.tag == .index) : (root = root.kids[0]) {
        try groups.append(it.t, root.kids[1..]);
    }
    std.mem.reverse([]const *const Node, groups.items);
    var obj = try it.eval(root);
    var i: usize = 0;
    while (i + 1 < groups.items.len) : (i += 1) {
        if (obj == .list and Interp.isMatrix(obj.list)) {
            var merged: std.ArrayList(*const Node) = .empty;
            for (groups.items[i..]) |g| try merged.appendSlice(it.t, g);
            return .{ .obj = obj, .args = merged.items };
        }
        obj = try it.indexOf(obj, groups.items[i]);
    }
    return .{ .obj = obj, .args = groups.items[i] };
}

pub fn index(it: *Interp, n: *const Node) Signal!Value {
    const r = try it.indexChain(n);
    return it.indexOf(r.obj, r.args);
}

/// One group of brackets applied to a value: `obj[args]`.
pub fn indexOf(it: *Interp, obj: Value, args: []const *const Node) Signal!Value {
    switch (obj) {
        .map => |m| {
            const key = try it.eval(args[0]);
            const i = Interp.mapFind(m, key) orelse return it.failWith(err_key, "Key not found", .{});
            return m.entries.items[i].val;
        },
        .list, .set => |l| {
            // a range on a one-dimensional list is a view: it shares the storage
            if (args.len == 1 and args[0].tag == .range and !Interp.isMatrix(l)) {
                const ix = try it.evalIdx(args[0], @intCast(l.elems().len));
                const lo = ix.rng.lo;
                const hi = ix.rng.hi;
                if (lo < 1 or hi > l.elems().len or lo > hi + 1) return it.failWith(err_index, "Range {d}..{d} is out of range 1..{d}", .{ lo, hi, l.elems().len });
                // a view counts the list it shows
                const v = try it.h.make(List, .{ .array = l.array, .base = l, .off = @intCast(lo - 1), .len = @intCast(hi - lo + 1) });
                l.hdr.rc += 1;
                return .{ .list = v };
            }
            if (args.len == 1 and args[0].tag != .all and !Interp.isMatrix(l)) {
                // one index on a list: read the element directly
                const ix = try it.evalIdx(args[0], @intCast(l.elems().len));
                const k = ix.one;
                if (k < 1 or k > l.elems().len) return it.failWith(err_index, "Index {d} is out of range 1..{d}", .{ k, l.elems().len });
                return l.elems()[@intCast(k - 1)];
            }
            var cells: std.ArrayList(*Value) = .empty;
            try it.slots(l, args, &cells);
            if (cells.items.len == 1 and args[0].tag != .all and args[args.len - 1].tag != .all) return cells.items[0].*;
            const out = try it.h.make(List, .{ .array = true });
            for (cells.items) |c| try it.listAppend(out, c.*);
            return .{ .list = out };
        },
        .bytes => |b| return try bytesfn.index(it, b, args),
        .str => |s| {
            const items = try it.iterate(obj);
            const ix = try it.evalIdx(args[0], @intCast(items.len));
            // @eve-impl a range on a string: the substring of runes lo..hi, a copy (a string is immutable)
            // @spec spec/library/strings.md#slice
            // @feature F-LIB-03
            // @test test/level1/a86_string_slice
            if (ix == .rng) {
                const lo = ix.rng.lo;
                const hi = ix.rng.hi;
                if (lo < 1 or hi > items.len or lo > hi + 1) return it.failWith(err_index, "Range {d}..{d} is out of range 1..{d}", .{ lo, hi, items.len });
                var start: usize = 0;
                var rune: usize = 1;
                var pos: usize = 0;
                while (pos < s.len and rune < lo) : (rune += 1) pos += std.unicode.utf8ByteSequenceLength(s[pos]) catch 1;
                start = pos;
                while (pos < s.len and rune <= hi) : (rune += 1) pos += std.unicode.utf8ByteSequenceLength(s[pos]) catch 1;
                return try it.newStr(s[start..@min(pos, s.len)]);
            }
            if (ix != .one or ix.one < 1 or ix.one > items.len) return it.failWith(err_index, "Index is out of range 1..{d}", .{items.len});
            return items[@intCast(ix.one - 1)];
        },
        else => return it.fail("{s} cannot be indexed", .{Interp.typeName(obj)}),
    }
}

pub fn field(it: *Interp, n: *const Node) Signal!Value {
    const obj = try it.eval(n.kids[0]);
    switch (obj) {
        .object => |o| {
            if (o.class != null and o.class == it.base().gen_class and std.mem.eql(u8, n.text, "value") and Interp.fieldOf(o, "value") == null) {
                return it.fail("g.value is read before the first next(): ask for a value first (declarations.md#generators-level-5)", .{});
            }
            return Interp.fieldOf(o, n.text) orelse it.fail("no attribute '{s}'", .{n.text});
        },
        .module => |m| return it.moduleMember(m, n.text),
        .typ => |t| {
            if (std.mem.eql(u8, t, "Instant") and std.mem.eql(u8, n.text, "epoch")) return .{ .instant = 0 };
            return it.fail("{s} has no member '{s}'", .{ t, n.text });
        },
        .class => |c| {
            for (c.ord.items) |f| if (std.mem.eql(u8, f.name, n.text)) return f.val;
            return it.fail("{s} has no member '{s}'", .{ c.name, n.text });
        },
        else => return it.fail("{s} has no attribute '{s}'", .{ Interp.typeName(obj), n.text }),
    }
}

// @eve-impl methods of a DataMap: has, get, keys, values, delete
// @spec spec/semantics/types.md#datamap-methods
// @feature F-VM-06
// @see backlog/library-gaps.md:G-5
/// `m.has(k)`, `m.get(k)`, `m.get(k, default)`, `m.keys()`, `m.values()`, `m.delete(k)`; null when the name is not a map method.
pub fn mapMethod(it: *Interp, m: *value.Map, name: []const u8, args: []const *const Node) Signal!?Value {
    const eql = std.mem.eql;
    if (eql(u8, name, "keys") or eql(u8, name, "values")) {
        if (args.len != 0) return it.fail("{s}() takes no argument", .{name});
        const out = try it.h.make(List, .{});
        const keys = eql(u8, name, "keys");
        for (m.entries.items) |e| try it.listAppend(out, if (keys) e.key else e.val);
        return .{ .list = out };
    }
    if (eql(u8, name, "has") or eql(u8, name, "delete") or eql(u8, name, "get")) {
        const want: usize = if (eql(u8, name, "get")) 2 else 1;
        if (args.len < 1 or args.len > want) return it.fail("{s} takes {d} argument(s)", .{ name, want });
        const key = try it.eval(args[0]);
        const at = Interp.mapFind(m, key);
        if (eql(u8, name, "has")) return .{ .bool = at != null };
        if (eql(u8, name, "get")) {
            if (at) |i| return m.entries.items[i].val;
            return if (args.len == 2) try it.eval(args[1]) else .nil;
        }
        if (at) |i| {
            const gone = m.entries.orderedRemove(i);
            it.h.release(gone.key);
            it.h.release(gone.val);
        }
        return .nil;
    }
    return null;
}
