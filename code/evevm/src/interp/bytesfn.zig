//! @eve-module interp.bytesfn
//! @spec spec/library/bytes.md#bytes
//! @feature F-LNG-13
//! @decision D-221
//! @tests test/level5/e139_bytes_basics, test/level5/e140_bytes_errors, test/level5/e141_bytes_file
//! The type Bytes in the interpreter: the constructors `Bytes.from_hex`, `Bytes.from_base64` and `Bytes.of`, the methods of a value, its index and slice, and `+`.
//! Part of the interpreter (interp.zig): every function takes the interpreter as `it: *Interp`, and
//! `Interp` names each of them again, so a call reads `it.name(...)` wherever it is made.
const std = @import("std");
const Io = std.Io;
const interp = @import("../interp.zig");
const collections = @import("collections.zig");
const bytes_text = interp.bytes_text;
const Interp = interp.Interp;
const Node = interp.Node;
const Signal = interp.Signal;
const Value = interp.Value;
const err_index = interp.value.err_index;
const err_argument = interp.err_argument;
const err_convert = interp.value.err_convert;
const eql = std.mem.eql;

// @eve-impl a Bytes is a copy of its bytes in a heap string block (heap.zig); no value shares a buffer with another
// @spec spec/library/bytes.md#bytes
// @feature F-LNG-13
// @test test/level5/e141_bytes_file
/// A new Bytes with a copy of `b`.
pub fn newBytes(it: *Interp, b: []const u8) Signal!Value {
    return .{ .bytes = try it.h.str(b) };
}

// @eve-fn Bytes.from_hex, Bytes.from_base64, Bytes.of
// @spec spec/library/bytes.md#bytes
// @feature F-LNG-13
// @test test/level5/e139_bytes_basics
// @test test/level5/e140_bytes_errors
/// The constructors of the type: `Bytes.from_hex(text)`, `Bytes.from_base64(text)`, `Bytes.of(n, ...)`; null for another name.
pub fn staticCall(it: *Interp, name: []const u8, args: []const *const Node) Signal!?Value {
    if (eql(u8, name, "from_hex") and args.len == 1) {
        const txt = try it.text(try it.eval(args[0]));
        const raw = (try bytes_text.fromHex(it.t, txt)) orelse return it.failWith(err_argument, "Bytes.from_hex: '{s}' is not hexadecimal text of an even length", .{txt});
        return try newBytes(it, raw);
    }
    if (eql(u8, name, "from_base64") and args.len == 1) {
        const txt = try it.text(try it.eval(args[0]));
        const raw = (try bytes_text.fromBase64(it.t, txt)) orelse return it.failWith(err_argument, "Bytes.from_base64: '{s}' is not Base64 text", .{txt});
        return try newBytes(it, raw);
    }
    if (eql(u8, name, "of")) {
        var raw: std.ArrayList(u8) = .empty;
        for (args) |a| {
            const v = try it.eval(a);
            if (!Interp.isInt(v) or Interp.intOf(v) < 0 or Interp.intOf(v) > 255) return it.failWith(err_argument, "Bytes.of: a byte is a whole number from 0 to 255", .{});
            try raw.append(it.t, @intCast(Interp.intOf(v)));
        }
        return try newBytes(it, raw.items);
    }
    return null;
}

/// The text of a Bytes as a String: its hexadecimal digits, or the Base64 text of its bytes.
fn encoded(it: *Interp, b: []const u8, name: []const u8) Signal!?Value {
    if (eql(u8, name, "hex")) {
        var aw: Io.Writer.Allocating = .init(it.t);
        bytes_text.writeHex(&aw.writer, b) catch return error.OutOfMemory;
        return try it.newStr(aw.written());
    }
    if (eql(u8, name, "base64")) return try it.newStr(try bytes_text.toBase64(it.t, b, false));
    if (eql(u8, name, "base64url")) return try it.newStr(try bytes_text.toBase64(it.t, b, true));
    return null;
}

// @eve-impl the methods of a Bytes value: length, the text forms, the search (bytes.md#bytes)
// @spec spec/library/bytes.md#bytes
// @feature F-LNG-13
// @test test/level5/e139_bytes_basics
/// The methods of a Bytes value, such as `b.length()` and `b.index_of(c)`; null when `name` is not one of them.
pub fn method(it: *Interp, b: []const u8, name: []const u8, args: []const *const Node) Signal!?Value {
    if (args.len == 0) {
        if (eql(u8, name, "length")) return .{ .int = @intCast(b.len) };
        if (eql(u8, name, "text")) {
            if (!std.unicode.utf8ValidateSlice(b)) return it.failWith(err_convert, "Bytes.text: the bytes are not valid UTF-8", .{});
            return try it.newStr(b);
        }
        return encoded(it, b, name);
    }
    if (args.len != 1) return null;
    const isSearch = eql(u8, name, "index_of") or eql(u8, name, "contains") or eql(u8, name, "starts_with") or eql(u8, name, "ends_with");
    if (!isSearch) return null;
    const v = try it.eval(args[0]);
    if (v != .bytes) return it.failWith(err_argument, "{s}: the argument is a Bytes, found {s}", .{ name, Interp.typeName(v) });
    const needle = v.bytes;
    if (eql(u8, name, "index_of")) return .{ .int = @intCast(bytes_text.indexOf(b, needle)) };
    if (eql(u8, name, "contains")) return .{ .bool = std.mem.indexOf(u8, b, needle) != null };
    if (eql(u8, name, "starts_with")) return .{ .bool = std.mem.startsWith(u8, b, needle) };
    return .{ .bool = std.mem.endsWith(u8, b, needle) };
}

// @eve-impl `b[i]` is one byte as a Natural, counted from 1; `b[a..z]` is a copy of the bytes a to z (strings.md#slice)
// @spec spec/library/bytes.md#bytes
// @feature F-LNG-13
// @test test/level5/e139_bytes_basics
// @test test/level5/e140_bytes_errors
/// The index or the slice of a Bytes: one byte as a `Natural`, or a new Bytes for a range; an index outside 1 to the length is `$err_index`.
pub fn index(it: *Interp, b: []const u8, args: []const *const Node) Signal!Value {
    const ix = try collections.evalIdx(it, args[0], @intCast(b.len));
    switch (ix) {
        .all => return newBytes(it, b),
        .rng => |r| {
            if (r.lo < 1 or r.hi > b.len or r.lo > r.hi + 1) return it.failWith(err_index, "Range {d}..{d} is out of range 1..{d}", .{ r.lo, r.hi, b.len });
            return newBytes(it, b[@intCast(r.lo - 1)..@intCast(r.hi)]);
        },
        .one => |k| {
            if (k < 1 or k > b.len) return it.failWith(err_index, "Index {d} is out of range 1..{d}", .{ k, b.len });
            return .{ .nat = b[@intCast(k - 1)] };
        },
    }
}

// @eve-impl `+` joins two Bytes into a new one; a Bytes with another kind is an error (bytes.md#bytes: `Bytes + String` is a compile error)
// @spec spec/library/bytes.md#bytes
// @feature F-LNG-13
// @test test/level5/e139_bytes_basics
/// The operator on a Bytes: `+` joins two Bytes; null for the other operators, which the general rules handle.
pub fn binary(it: *Interp, op: []const u8, l: Value, r: Value) Signal!?Value {
    if (!eql(u8, op, "+")) return null;
    if (l != .bytes or r != .bytes) return it.failWith(err_argument, "+: a Bytes joins only with another Bytes, found {s}", .{Interp.typeName(if (l == .bytes) r else l)});
    return .{ .bytes = try it.h.str2(l.bytes, r.bytes) };
}
