//! @eve-module interp.indexval
//! @spec spec/syntax/expressions.md#index-slice-member
//! @feature F-LNG-07
//! @decision D-064
//! @tests test/bytecode/bc28_indexes
//! Indexing and slicing with the indexes already evaluated: the bytecode machine computes the arguments of `a[i, j]`, `a[2..$]`,
//! `a[*]` in registers and calls these functions; `collections.zig` does the same for the tree walker, from nodes.
//! Part of the interpreter (interp.zig): every function takes the interpreter as `it: *Interp`.
const std = @import("std");
const bytesfn = @import("bytesfn.zig");
const interp = @import("../interp.zig");
const Interp = interp.Interp;
const Signal = interp.Signal;
const Value = interp.Value;
const List = interp.List;
const Idx = interp.Interp.Idx;
const err_index = interp.err_index;
const err_key = interp.err_key;

/// One index of a bracket group, evaluated: a number or a range value, or `*` (all).
pub const Arg = union(enum) { val: Value, all };

fn isRange(a: Arg) bool {
    return a == .val and a.val == .range;
}

fn idxOf(it: *Interp, a: Arg, len: i64) Signal!Idx {
    switch (a) {
        .all => return .all,
        .val => |v| {
            if (v == .range) {
                const lo = if (v.range.lo < 0) len + 1 + v.range.lo else v.range.lo;
                const hi = if (v.range.hi < 0) len + 1 + v.range.hi else v.range.hi;
                return .{ .rng = .{ .lo = lo, .hi = hi } };
            }
            if (!Interp.isInt(v)) return it.fail("an index must be an integer, found {s}", .{Interp.typeName(v)});
            const k = Interp.intOf(v);
            return .{ .one = if (k < 0) len + 1 + k else k };
        },
    }
}

fn walkArgs(it: *Interp, l: *List, args: []const Arg, depth: usize, out: *std.ArrayList(*Value)) Signal!void {
    const ix = try idxOf(it, args[depth], Interp.dimLen(l, 0));
    var cells: std.ArrayList(*Value) = .empty;
    for (l.elems()) |*e| try cells.append(it.t, e);
    var picked: std.ArrayList(*Value) = .empty;
    try it.pick(cells.items, ix, &picked);
    for (picked.items) |c| {
        if (depth + 1 == args.len) {
            try out.append(it.t, c);
        } else if (c.* == .list) {
            try walkArgs(it, c.list, args, depth + 1, out);
        } else return it.fail("too many indexes", .{});
    }
}

// @eve-impl the storage cells an evaluated index selects (one for `a[2]`, several for a slice or `[*]`)
// @see code/evevm/src/interp/collections.zig:slots
pub fn slotsArgs(it: *Interp, root: *List, args: []const Arg, out: *std.ArrayList(*Value)) Signal!void {
    if (args.len == 1 and Interp.isMatrix(root)) {
        var flat: std.ArrayList(*Value) = .empty;
        try it.leaves(root, &flat);
        const ix = try idxOf(it, args[0], @intCast(flat.items.len));
        try it.pick(flat.items, ix, out);
        return;
    }
    try walkArgs(it, root, args, 0, out);
}

// @eve-impl one group of brackets applied to a value, with the indexes evaluated
// @see code/evevm/src/interp/collections.zig:indexOf
pub fn indexOfArgs(it: *Interp, obj: Value, args: []const Arg) Signal!Value {
    switch (obj) {
        .map => |m| {
            if (args[0] == .all) return it.fail("a map is indexed by a key", .{});
            const i = Interp.mapFind(m, args[0].val) orelse return it.failWith(err_key, "Key not found", .{});
            return m.entries.items[i].val;
        },
        .list, .set => |l| {
            if (args.len == 1 and isRange(args[0]) and !Interp.isMatrix(l)) {
                const ix = try idxOf(it, args[0], @intCast(l.elems().len));
                const lo = ix.rng.lo;
                const hi = ix.rng.hi;
                if (lo < 1 or hi > l.elems().len or lo > hi + 1) return it.failWith(err_index, "Range {d}..{d} is out of range 1..{d}", .{ lo, hi, l.elems().len });
                const v = try it.h.make(List, .{ .array = l.array, .base = l, .off = @intCast(lo - 1), .len = @intCast(hi - lo + 1) });
                l.hdr.rc += 1;
                return .{ .list = v };
            }
            if (args.len == 1 and args[0] != .all and !Interp.isMatrix(l)) {
                const ix = try idxOf(it, args[0], @intCast(l.elems().len));
                const k = ix.one;
                if (k < 1 or k > l.elems().len) return it.failWith(err_index, "Index {d} is out of range 1..{d}", .{ k, l.elems().len });
                return l.elems()[@intCast(k - 1)];
            }
            var cells: std.ArrayList(*Value) = .empty;
            try slotsArgs(it, l, args, &cells);
            if (cells.items.len == 1 and args[0] != .all and args[args.len - 1] != .all) return cells.items[0].*;
            const out = try it.h.make(List, .{ .array = true });
            for (cells.items) |c| try it.listAppend(out, c.*);
            return .{ .list = out };
        },
        .bytes => |b| {
            const ix = try idxOf(it, args[0], @intCast(b.len));
            switch (ix) {
                .all => return bytesfn.newBytes(it, b),
                .rng => |r| {
                    if (r.lo < 1 or r.hi > b.len or r.lo > r.hi + 1) return it.failWith(err_index, "Range {d}..{d} is out of range 1..{d}", .{ r.lo, r.hi, b.len });
                    return bytesfn.newBytes(it, b[@intCast(r.lo - 1)..@intCast(r.hi)]);
                },
                .one => |k| {
                    if (k < 1 or k > b.len) return it.failWith(err_index, "Index {d} is out of range 1..{d}", .{ k, b.len });
                    return .{ .nat = b[@intCast(k - 1)] };
                },
            }
        },
        .str => |s| {
            const items = try it.iterate(obj);
            const ix = try idxOf(it, args[0], @intCast(items.len));
            if (ix == .rng) {
                const lo = ix.rng.lo;
                const hi = ix.rng.hi;
                if (lo < 1 or hi > items.len or lo > hi + 1) return it.failWith(err_index, "Range {d}..{d} is out of range 1..{d}", .{ lo, hi, items.len });
                var rune: usize = 1;
                var pos: usize = 0;
                while (pos < s.len and rune < lo) : (rune += 1) pos += std.unicode.utf8ByteSequenceLength(s[pos]) catch 1;
                const start = pos;
                while (pos < s.len and rune <= hi) : (rune += 1) pos += std.unicode.utf8ByteSequenceLength(s[pos]) catch 1;
                return try it.newStr(s[start..@min(pos, s.len)]);
            }
            if (ix != .one or ix.one < 1 or ix.one > items.len) return it.failWith(err_index, "Index is out of range 1..{d}", .{items.len});
            return items[@intCast(ix.one - 1)];
        },
        else => return it.fail("{s} cannot be indexed", .{Interp.typeName(obj)}),
    }
}

/// The value indexed last and its indexes, when the brackets are written as a chain `a[i][j]` (`sizes` is the count of indexes of
/// each group, `args` all of them in order). On a matrix the remaining groups merge into one: `m[x][y]` is `m[x, y]` (D-064).
pub fn chainTarget(it: *Interp, root: Value, sizes: []const u8, args: []const Arg) Signal!struct { obj: Value, args: []const Arg } {
    var obj = root;
    var off: usize = 0;
    var i: usize = 0;
    while (i + 1 < sizes.len) : (i += 1) {
        if (obj == .list and Interp.isMatrix(obj.list)) return .{ .obj = obj, .args = args[off..] };
        obj = try indexOfArgs(it, obj, args[off .. off + sizes[i]]);
        off += sizes[i];
    }
    return .{ .obj = obj, .args = args[off..] };
}

// @eve-impl `a[i, j] := v` with the indexes evaluated: a map entry, one element, or every cell a slice or `*` selects
// @see code/evevm/src/interp/stmt.zig:assignTo
pub fn assignIndexArgs(it: *Interp, obj: Value, args: []const Arg, v: Value) Signal!void {
    if (obj == .map) {
        if (args[0] == .all) return it.fail("a map is indexed by a key", .{});
        return it.mapPut(obj.map, args[0].val, v);
    }
    if (obj != .list) return it.fail("{s} cannot be assigned by index", .{Interp.typeName(obj)});
    if (args.len == 1 and args[0] != .all and !isRange(args[0]) and !Interp.isMatrix(obj.list)) {
        const l = obj.list;
        const ix = try idxOf(it, args[0], @intCast(l.elems().len));
        const k = ix.one;
        if (k < 1 or k > l.elems().len) return it.failWith(err_index, "Index {d} is out of range 1..{d}", .{ k, l.elems().len });
        it.setCell(&l.elems()[@intCast(k - 1)], v);
        return;
    }
    var cells: std.ArrayList(*Value) = .empty;
    try slotsArgs(it, obj.list, args, &cells);
    for (cells.items) |c| it.setCell(c, v);
}

// @eve-impl `$` inside the only index of `a[...]`: the length of what is indexed (the elements of a matrix counted flat)
pub fn dollarOf(it: *Interp, obj: Value) Signal!i64 {
    return switch (obj) {
        .list, .set => |l| if (Interp.isMatrix(l)) blk: {
            var flat: std.ArrayList(*Value) = .empty;
            try it.leaves(l, &flat);
            break :blk @intCast(flat.items.len);
        } else @intCast(l.elems().len),
        .str => @intCast((try it.iterate(obj)).len),
        .bytes => |b| @intCast(b.len),
        else => 0,
    };
}
