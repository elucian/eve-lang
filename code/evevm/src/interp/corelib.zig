//! @eve-module interp.corelib
//! @spec spec/library/lists.md, spec/library/maps.md, spec/library/strings.md
//! @feature F-LIB-03
//! @tests test/level1/a106_list_functions, test/level1/a107_list_errors, test/level1/a108_map_functions, test/level1/a109_string_more
//! The functions of the core library on lists, maps and strings (library step L1). A function never changes its receiver.
//! Part of the interpreter (interp.zig): called from `callMethod` (calls.zig) after the extension methods of the program.
const std = @import("std");
const interp = @import("../interp.zig");
const Interp = interp.Interp;
const Node = interp.Node;
const Signal = interp.Signal;
const Value = interp.Value;
const List = interp.List;
const Arg = interp.Arg;
const err_argument = interp.err_argument;

const ListFn = enum { sort, reverse, sum, min, max, contains, index_of, unique, take, drop, zip, map, filter, reduce, any, all };

// @eve-fn List.sort, List.reverse, List.sum, List.min, List.max, List.contains, List.index_of, List.unique, List.take, List.drop
// @eve-fn List.zip, List.map, List.filter, List.reduce, List.any, List.all
// @spec spec/library/lists.md#functions
// @test a106_list_functions
// @invariant the receiver is never changed; the result of a List or an Array function is a new List or Array, of a DataSet a List
/// A function of the library on a List, an Array or a DataSet, or null when `name` is not one.
pub fn listMethod(it: *Interp, recv: Value, name: []const u8, arg_nodes: []const *const Node) Signal!?Value {
    const l: *List = switch (recv) {
        .list, .set => |x| x,
        else => return null,
    };
    const id = std.meta.stringToEnum(ListFn, name) orelse return null;
    const args = try it.evalArgs(arg_nodes);
    defer it.dropArgs(args);
    const items = l.elems();
    const array = recv == .list and l.array;
    switch (id) {
        .sort => return try sortList(it, items, args, array),
        .reverse => {
            try expectArgs(it, name, args, 0);
            const out = try it.t.alloc(Value, items.len);
            for (items, 0..) |x, i| out[items.len - 1 - i] = x;
            return .{ .list = try it.newList(out, array) };
        },
        .sum => {
            try expectArgs(it, name, args, 0);
            var acc: Value = if (items.len > 0 and items[0] == .dur) .{ .dur = 0 } else .{ .int = 0 };
            for (items) |x| {
                if (!Interp.isInt(x) and x != .real and x != .float and x != .dec and x != .rat and x != .dur) return it.failWith(err_argument, "sum needs numbers, found {s}", .{Interp.typeName(x)});
                acc = try it.applyOp(.add, "+", acc, x);
            }
            return acc;
        },
        .min, .max => {
            try expectArgs(it, name, args, 0);
            if (items.len == 0) return it.failWith(err_argument, "{s} of an empty list", .{name});
            var best = items[0];
            for (items[1..]) |x| {
                const o = try compare(it, x, best);
                if ((id == .min and o == .lt) or (id == .max and o == .gt)) best = x;
            }
            return best;
        },
        .contains => {
            try expectArgs(it, name, args, 1);
            for (items) |x| if (Interp.eq(x, args[0].value)) return .{ .bool = true };
            return .{ .bool = false };
        },
        .index_of => {
            try expectArgs(it, name, args, 1);
            for (items, 0..) |x, i| if (Interp.eq(x, args[0].value)) return .{ .int = @intCast(i + 1) };
            return .{ .int = 0 };
        },
        .unique => {
            try expectArgs(it, name, args, 0);
            var out: std.ArrayList(Value) = .empty;
            for (items) |x| {
                var seen = false;
                for (out.items) |y| if (Interp.eq(x, y)) {
                    seen = true;
                    break;
                };
                if (!seen) try out.append(it.t, x);
            }
            return .{ .list = try it.newList(out.items, array) };
        },
        .take, .drop => {
            try expectArgs(it, name, args, 1);
            const n = args[0].value;
            if (!Interp.isInt(n) or Interp.intOf(n) < 0) return it.failWith(err_argument, "{s} takes a whole number, zero or more", .{name});
            const k: usize = @min(@as(usize, @intCast(Interp.intOf(n))), items.len);
            return .{ .list = try it.newList(if (id == .take) items[0..k] else items[k..], array) };
        },
        .zip => {
            try expectArgs(it, name, args, 1);
            const other = switch (args[0].value) {
                .list, .set => |o| o.elems(),
                else => return it.failWith(err_argument, "zip takes a list", .{}),
            };
            var out: std.ArrayList(Value) = .empty;
            for (0..@min(items.len, other.len)) |i| {
                const pair = try it.newList(&.{ items[i], other[i] }, false);
                try out.append(it.t, .{ .list = pair });
            }
            return .{ .list = try it.newList(out.items, false) };
        },
        .map, .filter, .any, .all => {
            try expectArgs(it, name, args, 1);
            var out: std.ArrayList(Value) = .empty;
            for (items) |x| {
                const r = try call(it, name, args[0].value, &.{x});
                switch (id) {
                    .map => try out.append(it.t, r),
                    .filter => if (try it.truth(r)) try out.append(it.t, x),
                    .any => if (try it.truth(r)) return .{ .bool = true },
                    .all => if (!try it.truth(r)) return .{ .bool = false },
                    else => unreachable,
                }
            }
            return switch (id) {
                .any => .{ .bool = false },
                .all => .{ .bool = true },
                else => .{ .list = try it.newList(out.items, array) },
            };
        },
        .reduce => {
            try expectArgs(it, name, args, 2);
            var acc = args[0].value;
            for (items) |x| acc = try call(it, name, args[1].value, &.{ acc, x });
            return acc;
        },
    }
}

fn isNumber(v: Value) bool {
    return Interp.isInt(v) or v == .real or v == .float or v == .dec or v == .rat;
}

/// Order two elements; elements of different families (a number and a text) are `$err_argument`, not a comparison.
fn compare(it: *Interp, a: Value, b: Value) Signal!std.math.Order {
    const same_family = (isNumber(a) and isNumber(b)) or (a == .dur and b == .dur) or (a == .date and b == .date) or ((a == .dtm or a == .instant) and (b == .dtm or b == .instant)) or (a == .time and b == .time) or (a == .str and b == .str) or (a == .sym and b == .sym) or (a == .instant and b == .instant);
    if (!same_family) return it.failWith(err_argument, "cannot compare {s} with {s}", .{ Interp.typeName(a), Interp.typeName(b) });
    return it.order(a, b);
}

/// The exact number of arguments, all positional.
fn expectArgs(it: *Interp, name: []const u8, args: []const Arg, n: usize) Signal!void {
    if (args.len != n) return it.failWith(err_argument, "{s} takes {d} argument(s)", .{ name, n });
    for (args) |a| if (a.name.len > 0) return it.failWith(err_argument, "{s}: unknown argument '{s}'", .{ name, a.name });
}

/// Call the function `f` (a function, a lambda or a method value) with evaluated arguments.
fn call(it: *Interp, name: []const u8, f: Value, values: []const Value) Signal!Value {
    if (f != .func) return it.failWith(err_argument, "{s} takes a function", .{name});
    const args = try it.t.alloc(Arg, values.len);
    for (values, 0..) |v, i| args[i] = .{ .value = v };
    return it.invokeWith(f.func, null, args);
}

const Pair = struct { key: Value, val: Value };

const SortCtx = struct {
    it: *Interp,
    descending: bool,
    err: ?Signal = null,

    fn less(ctx: *SortCtx, a: Pair, b: Pair) bool {
        if (ctx.err != null) return false;
        const o = compare(ctx.it, a.key, b.key) catch |e| {
            ctx.err = e;
            return false;
        };
        return if (ctx.descending) o == .gt else o == .lt;
    }
};

/// `sort()`, `sort(by: f)`, `sort(descending: True)`: a stable sort into a new list. The keys must be comparable with each other.
fn sortList(it: *Interp, items: []const Value, args: []const Arg, array: bool) Signal!Value {
    var by: ?Value = null;
    var descending = false;
    for (args) |a| {
        if (std.mem.eql(u8, a.name, "by") or a.name.len == 0) {
            by = a.value;
        } else if (std.mem.eql(u8, a.name, "descending")) {
            descending = try it.truth(a.value);
        } else return it.failWith(err_argument, "sort: unknown argument '{s}'", .{a.name});
    }
    const pairs = try it.t.alloc(Pair, items.len);
    for (items, 0..) |x, i| pairs[i] = .{ .key = if (by) |f| try call(it, "sort", f, &.{x}) else x, .val = x };
    var ctx: SortCtx = .{ .it = it, .descending = descending };
    std.sort.block(Pair, pairs, &ctx, SortCtx.less);
    if (ctx.err) |e| return e;
    const out = try it.t.alloc(Value, items.len);
    for (pairs, 0..) |p, i| out[i] = p.val;
    return .{ .list = try it.newList(out, array) };
}

// @eve-fn DataMap.merge, DataMap.invert
// @spec spec/library/maps.md#functions
// @test a108_map_functions
/// A function of the library on a DataMap, or null when `name` is not one.
pub fn mapMore(it: *Interp, m: *interp.Map, name: []const u8, arg_nodes: []const *const Node) Signal!?Value {
    const merge = std.mem.eql(u8, name, "merge");
    if (!merge and !std.mem.eql(u8, name, "invert")) return null;
    const args = try it.evalArgs(arg_nodes);
    defer it.dropArgs(args);
    const out = try it.newMap();
    if (merge) {
        try expectArgs(it, name, args, 1);
        if (args[0].value != .map) return it.failWith(err_argument, "merge takes a map", .{});
        for (m.entries.items) |e| try it.mapPut(out, e.key, e.val);
        for (args[0].value.map.entries.items) |e| try it.mapPut(out, e.key, e.val);
        return .{ .map = out };
    }
    try expectArgs(it, name, args, 0);
    for (m.entries.items) |e| {
        if (e.val != .str and !Interp.isInt(e.val)) return it.failWith(err_argument, "invert needs values that are texts or whole numbers", .{});
        if (Interp.mapFind(out, e.val) != null) return it.failWith(err_argument, "invert: two keys have the value {s}", .{try it.text(e.val)});
        try it.mapPut(out, e.val, e.key);
    }
    return .{ .map = out };
}

const StringFn = enum { reverse, repeat, pad_start, pad_end, lines };

// @eve-fn String.reverse, String.repeat, String.pad_start, String.pad_end, String.lines
// @spec spec/library/strings.md#functions
// @test a109_string_more
/// A function of the library on a String, or null when `name` is not one.
pub fn stringMore(it: *Interp, s: []const u8, name: []const u8, arg_nodes: []const *const Node) Signal!?Value {
    const id = std.meta.stringToEnum(StringFn, name) orelse return null;
    const args = try it.evalArgs(arg_nodes);
    defer it.dropArgs(args);
    switch (id) {
        .reverse, .lines => {
            try expectArgs(it, name, args, 0);
            if (id == .lines) {
                var out: std.ArrayList(Value) = .empty;
                var parts = std.mem.splitScalar(u8, s, 10);
                while (parts.next()) |p| {
                    if (parts.peek() == null and p.len == 0) break;
                    try out.append(it.t, try it.newStr(std.mem.trimEnd(u8, p, "\r")));
                }
                return .{ .list = try it.newList(out.items, false) };
            }
            var cps: std.ArrayList([]const u8) = .empty;
            var at: usize = 0;
            while (at < s.len) {
                const n = std.unicode.utf8ByteSequenceLength(s[at]) catch 1;
                const end = @min(at + n, s.len);
                try cps.append(it.t, s[at..end]);
                at = end;
            }
            const out = try it.t.alloc(u8, s.len);
            var w: usize = 0;
            var i = cps.items.len;
            while (i > 0) {
                i -= 1;
                @memcpy(out[w .. w + cps.items[i].len], cps.items[i]);
                w += cps.items[i].len;
            }
            return try it.newStr(out);
        },
        .repeat => {
            try expectArgs(it, name, args, 1);
            const n = args[0].value;
            if (!Interp.isInt(n) or Interp.intOf(n) < 0) return it.failWith(err_argument, "repeat takes a whole number, zero or more", .{});
            const times: usize = @intCast(Interp.intOf(n));
            if (s.len != 0 and times > (64 << 20) / s.len) return it.failWith(err_argument, "repeat: the text would be longer than 64 MB", .{});
            const out = try it.t.alloc(u8, s.len * times);
            for (0..times) |i| @memcpy(out[i * s.len .. (i + 1) * s.len], s);
            return try it.newStr(out);
        },
        .pad_start, .pad_end => {
            if (args.len < 1 or args.len > 2) return it.failWith(err_argument, "{s} takes a length and an optional filler", .{name});
            const n = args[0].value;
            if (!Interp.isInt(n) or Interp.intOf(n) < 0) return it.failWith(err_argument, "{s} takes a whole number, zero or more", .{name});
            var fill: []const u8 = " ";
            if (args.len == 2) {
                if (args[1].value != .str or (std.unicode.utf8CountCodepoints(args[1].value.str) catch 0) != 1)
                    return it.failWith(err_argument, "{s}: the filler is one character", .{name});
                fill = args[1].value.str;
            }
            const have = std.unicode.utf8CountCodepoints(s) catch s.len;
            const want: usize = @intCast(Interp.intOf(n));
            if (want <= have) return try it.newStr(s);
            const missing = want - have;
            if (missing * fill.len > (64 << 20)) return it.failWith(err_argument, "{s}: the text would be longer than 64 MB", .{name});
            const out = try it.t.alloc(u8, s.len + missing * fill.len);
            const pad_at: usize = if (id == .pad_start) 0 else s.len;
            const text_at: usize = if (id == .pad_start) missing * fill.len else 0;
            for (0..missing) |i| @memcpy(out[pad_at + i * fill.len .. pad_at + (i + 1) * fill.len], fill);
            @memcpy(out[text_at .. text_at + s.len], s);
            return try it.newStr(out);
        },
    }
}

// @eve-fn String.upper, String.lower
// @spec spec/library/strings.md#functions
// @test a109_string_more
// @invariant ASCII, Latin-1, Latin Extended-A, Greek and Cyrillic letters change case; every other rune is kept as it is
/// The text in upper or lower case, letter by letter (no rune changes its length except the few that are listed in the page).
pub fn caseMapped(it: *Interp, s: []const u8, upper: bool) Signal!Value {
    var out: std.ArrayList(u8) = .empty;
    var at: usize = 0;
    while (at < s.len) {
        const n = std.unicode.utf8ByteSequenceLength(s[at]) catch 1;
        const end = @min(at + n, s.len);
        const cp = std.unicode.utf8Decode(s[at..end]) catch {
            try out.append(it.t, s[at]);
            at += 1;
            continue;
        };
        const mapped = if (upper) upperOf(cp) else lowerOf(cp);
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(mapped, &buf) catch {
            try out.appendSlice(it.t, s[at..end]);
            at = end;
            continue;
        };
        try out.appendSlice(it.t, buf[0..len]);
        at = end;
    }
    return try it.newStr(out.items);
}

fn upperOf(c: u21) u21 {
    return switch (c) {
        'a'...'z' => c - 32,
        0xE0...0xF6, 0xF8...0xFE => c - 32,
        0xFF => 0x178,
        0x131 => 'I',
        0x17F => 'S',
        0x100...0x12F, 0x132...0x137, 0x14A...0x177 => if (c % 2 == 1) c - 1 else c,
        0x139...0x148, 0x179...0x17E => if (c % 2 == 0) c - 1 else c,
        0x3B1...0x3C1, 0x3C3...0x3CB => c - 32,
        0x3C2 => 0x3A3,
        0x3AC => 0x386,
        0x3AD...0x3AF => c - 37,
        0x3CC => 0x38C,
        0x3CD, 0x3CE => c - 63,
        0x430...0x44F => c - 32,
        0x450...0x45F => c - 80,
        0x460...0x481, 0x48A...0x4BF, 0x4D0...0x52F => if (c % 2 == 1) c - 1 else c,
        else => c,
    };
}

fn lowerOf(c: u21) u21 {
    return switch (c) {
        'A'...'Z' => c + 32,
        0xC0...0xD6, 0xD8...0xDE => c + 32,
        0x178 => 0xFF,
        0x130 => 'i',
        0x100...0x12F, 0x132...0x137, 0x14A...0x177 => if (c % 2 == 0) c + 1 else c,
        0x139...0x148, 0x179...0x17E => if (c % 2 == 1) c + 1 else c,
        0x391...0x3A1, 0x3A3...0x3AB => c + 32,
        0x386 => 0x3AC,
        0x388...0x38A => c + 37,
        0x38C => 0x3CC,
        0x38E, 0x38F => c + 63,
        0x410...0x42F => c + 32,
        0x400...0x40F => c + 80,
        0x460...0x481, 0x48A...0x4BF, 0x4D0...0x52F => if (c % 2 == 0) c + 1 else c,
        else => c,
    };
}
