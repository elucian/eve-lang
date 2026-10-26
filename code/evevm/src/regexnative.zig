//! @eve-module regexnative: the module `regex` (is_match, matches, find, find_all, replace, split) over regexlib.zig
//! @spec spec/library/text.md#module-regex
//! @feature F-LIB-03
//! @decision D-236
//! @tests test/level3/c83_text_regex
//! The positions are counted in runes from 1, as `find` of a String counts; the end of a match is the last rune of it (one before the start for an empty match).
const std = @import("std");
const interp = @import("interp.zig");
const regexlib = @import("regexlib.zig");

const Interp = interp.Interp;
const Value = interp.Value;
const Signal = interp.Signal;
const Node = interp.Node;
const err_argument = interp.err_argument;

fn compileArg(it: *Interp, pattern: []const u8) Signal!regexlib.Prog {
    return regexlib.compileSpec(it.t, pattern) catch |e| switch (e) {
        error.OutOfMemory => error.OutOfMemory,
        error.BadPattern => it.failWith(err_argument, "regex: {s}, at byte {d} of the pattern", .{ regexlib.Prog.err_why, regexlib.Prog.err_at + 1 }),
        error.TooCostly => it.failWith(err_argument, "regex: the pattern is too costly", .{}),
    };
}

fn search(it: *Interp, prog: *const regexlib.Prog, text: []const u8, from: usize) Signal!?[]isize {
    return regexlib.search(it.t, prog, text, from) catch |e| switch (e) {
        error.OutOfMemory => error.OutOfMemory,
        error.BadPattern => it.failWith(err_argument, "regex: bad pattern", .{}),
        error.TooCostly => it.failWith(err_argument, "regex: the text and the pattern together are too large", .{}),
    };
}

/// The number of runes before the byte offset `at`.
fn runes(text: []const u8, at: usize) usize {
    return std.unicode.utf8CountCodepoints(text[0..at]) catch at;
}

fn slice(text: []const u8, slots: []const isize, g: usize) ?[]const u8 {
    const s = slots[g * 2];
    const e = slots[g * 2 + 1];
    if (s < 0 or e < 0) return null;
    return text[@intCast(s)..@intCast(e)];
}

fn matchValue(it: *Interp, text: []const u8, slots: []const isize) Signal!Value {
    const m = try it.newMap();
    const start = runes(text, @intCast(slots[0])) + 1;
    const whole = slice(text, slots, 0).?;
    const len = std.unicode.utf8CountCodepoints(whole) catch whole.len;
    try it.mapPut(m, try it.newStr("start"), .{ .int = @intCast(start) });
    try it.mapPut(m, try it.newStr("end"), .{ .int = @intCast(start + len - 1) });
    try it.mapPut(m, try it.newStr("text"), try it.newStr(whole));
    const groups = try it.newList(&.{}, false);
    var g: usize = 1;
    while (g * 2 < slots.len) : (g += 1) {
        try it.listAppend(groups, if (slice(text, slots, g)) |s| try it.newStr(s) else .nil);
    }
    try it.mapPut(m, try it.newStr("groups"), .{ .list = groups });
    return .{ .map = m };
}

/// The next start after a match: an empty match moves on by one rune so the search ends.
fn after(text: []const u8, slots: []const isize) usize {
    const e: usize = @intCast(slots[1]);
    if (slots[1] > slots[0]) return e;
    if (e >= text.len) return text.len + 1;
    return e + (std.unicode.utf8ByteSequenceLength(text[e]) catch 1);
}

// @eve-fn regex.is_match, regex.matches, regex.find, regex.find_all, regex.replace, regex.split
// @spec spec/library/text.md#module-regex
pub fn regexModule(it: *Interp, name: []const u8, _: []const *const Node, args: []const *const Node) Signal!?Value {
    const eql = std.mem.eql;
    const known = [_][]const u8{ "is_match", "matches", "find", "find_all", "replace", "split" };
    var found = false;
    for (known) |k| if (eql(u8, k, name)) {
        found = true;
    };
    if (!found) return null;
    const want: usize = if (eql(u8, name, "replace")) 3 else 2;
    if (args.len != want) return it.failWith(err_argument, "regex.{s} takes {d} arguments", .{ name, want });
    const text_v = try it.eval(args[0]);
    const pattern_v = try it.eval(args[1]);
    if (text_v != .str or pattern_v != .str) return it.failWith(err_argument, "regex.{s}: the text and the pattern are Strings", .{name});
    const text = text_v.str;
    const prog = try compileArg(it, pattern_v.str);
    if (eql(u8, name, "is_match")) return .{ .bool = (try search(it, &prog, text, 0)) != null };
    if (eql(u8, name, "matches")) {
        const whole = regexlib.compileSpecWhole(it.t, pattern_v.str, true) catch return it.failWith(err_argument, "regex: {s}", .{regexlib.Prog.err_why});
        return .{ .bool = (try search(it, &whole, text, 0)) != null };
    }
    if (eql(u8, name, "find")) {
        const slots = (try search(it, &prog, text, 0)) orelse return .nil;
        return @as(?Value, try matchValue(it, text, slots));
    }
    if (eql(u8, name, "find_all")) {
        const out = try it.newList(&.{}, false);
        var from: usize = 0;
        while (from <= text.len) {
            const slots = (try search(it, &prog, text, from)) orelse break;
            try it.listAppend(out, try matchValue(it, text, slots));
            from = after(text, slots);
        }
        return .{ .list = out };
    }
    if (eql(u8, name, "split")) {
        const out = try it.newList(&.{}, false);
        var last: usize = 0;
        var from: usize = 0;
        while (from <= text.len) {
            const slots = (try search(it, &prog, text, from)) orelse break;
            const s: usize = @intCast(slots[0]);
            const e: usize = @intCast(slots[1]);
            // an empty match splits nothing
            if (e > s) {
                try it.listAppend(out, try it.newStr(text[last..s]));
                last = e;
            }
            from = after(text, slots);
        }
        try it.listAppend(out, try it.newStr(text[last..]));
        return .{ .list = out };
    }
    // replace: $0 to $9 are the groups of the match, $$ is a dollar
    const repl_v = try it.eval(args[2]);
    if (repl_v != .str) return it.failWith(err_argument, "regex.replace: the replacement is a String", .{});
    const repl = repl_v.str;
    var out: std.ArrayList(u8) = .empty;
    var last: usize = 0;
    var from: usize = 0;
    while (from <= text.len) {
        const slots = (try search(it, &prog, text, from)) orelse break;
        const s: usize = @intCast(slots[0]);
        try out.appendSlice(it.t, text[last..s]);
        var i: usize = 0;
        while (i < repl.len) : (i += 1) {
            if (repl[i] == '$' and i + 1 < repl.len) {
                const k = repl[i + 1];
                if (k == '$') {
                    try out.append(it.t, '$');
                    i += 1;
                    continue;
                }
                if (k >= '0' and k <= '9') {
                    const g: usize = k - '0';
                    if (g * 2 >= slots.len) return it.failWith(err_argument, "regex.replace: the pattern has no group {d}", .{g});
                    if (slice(text, slots, g)) |part| try out.appendSlice(it.t, part);
                    i += 1;
                    continue;
                }
            }
            try out.append(it.t, repl[i]);
        }
        last = @intCast(slots[1]);
        from = after(text, slots);
    }
    try out.appendSlice(it.t, text[@min(last, text.len)..]);
    return @as(?Value, try it.newStr(out.items));
}
