//! @eve-module uuidlib: the type Uuid and the library module `uuid` (identifiers of versions 3, 4, 5 and 7)
//! @spec spec/library/bytes.md#uuid
//! @feature F-LNG-13
//! @tests test/level5/e142_uuid_basics, test/level5/e143_uuid_errors, test/level5/e144_uuid_v7_time
//! Handler of type `dlib.Native`, registered in `dlib.natives` as `uuid`. Signatures: lib/sys/uuid.eve. The values and the text: code/evecm/src/uuid.zig.
//! The static calls `Uuid.parse` and `Uuid.from_bytes` and the methods of a Uuid value are reached from calls.zig.
const std = @import("std");
const Io = std.Io;
const evecm = @import("evecm");
const interp = @import("interp.zig");
const bytesfn = @import("interp/bytesfn.zig");
const uuid = evecm.uuid;
const Node = interp.Node;
const Interp = interp.Interp;
const Value = interp.Value;
const Signal = interp.Signal;
const err_argument = interp.err_argument;
const err_parse = interp.err_parse;
const eql = std.mem.eql;

// @eve-fn Uuid.parse, Uuid.from_bytes
// @spec spec/library/bytes.md#uuid
// @feature F-LNG-13
// @test test/level5/e142_uuid_basics
// @test test/level5/e143_uuid_errors
/// The static calls of the type: `Uuid.parse(text)` and `Uuid.from_bytes(b)`; null for another name.
pub fn staticCall(it: *Interp, name: []const u8, args: []const *const Node) Signal!?Value {
    if (eql(u8, name, "parse") and args.len == 1) {
        const txt = try it.text(try it.eval(args[0]));
        const u = uuid.parse(txt) orelse return it.failWith(err_parse, "Cannot parse '{s}' as a Uuid: expected 550e8400-e29b-41d4-a716-446655440000", .{txt});
        return .{ .uuid = u };
    }
    if (eql(u8, name, "from_bytes") and args.len == 1) {
        const v = try it.eval(args[0]);
        if (v != .bytes) return it.failWith(err_argument, "Uuid.from_bytes: the argument is Bytes, found {s}", .{Interp.typeName(v)});
        if (v.bytes.len != 16) return it.failWith(err_argument, "Uuid.from_bytes: a Uuid is 16 bytes, found {d}", .{v.bytes.len});
        return .{ .uuid = v.bytes[0..16].* };
    }
    return null;
}

// @eve-impl the methods of a Uuid value: version, bytes and the time of a version 7 (bytes.md#uuid)
// @spec spec/library/bytes.md#uuid
// @feature F-LNG-13
// @test test/level5/e142_uuid_basics
// @test test/level5/e143_uuid_errors
/// The methods of a Uuid value, such as `u.version()`; null when `name` is not one of them.
pub fn method(it: *Interp, u: uuid.Bytes16, name: []const u8, args: []const *const Node) Signal!?Value {
    if (args.len != 0) return null;
    if (eql(u8, name, "version")) return .{ .int = uuid.version(u) };
    if (eql(u8, name, "bytes")) return try bytesfn.newBytes(it, &u);
    if (eql(u8, name, "instant")) {
        if (uuid.version(u) != 7) return it.failWith(err_argument, "Uuid.instant: only a version 7 Uuid carries a time, this one is version {d}", .{uuid.version(u)});
        return .{ .instant = uuid.timeOf7(u) };
    }
    return null;
}

// @eve-impl the constants of the type and of the module: `Uuid.nil`, `uuid.namespace_dns`, `uuid.namespace_url`, `uuid.namespace_oid`, `uuid.namespace_x500` (RFC 9562, Appendix B)
// @spec spec/library/bytes.md#uuid
// @feature F-LNG-13
// @test test/level5/e142_uuid_basics
/// A constant member of `owner` (the type `Uuid` or the module `uuid`), or null when `name` is not one.
pub fn member(owner: []const u8, name: []const u8) ?Value {
    if (eql(u8, owner, "Uuid") and eql(u8, name, "nil")) return .{ .uuid = @splat(0) };
    if (!eql(u8, owner, "uuid")) return null;
    const text = if (eql(u8, name, "namespace_dns")) "6ba7b810-9dad-11d1-80b4-00c04fd430c8" else if (eql(u8, name, "namespace_url")) "6ba7b811-9dad-11d1-80b4-00c04fd430c8" else if (eql(u8, name, "namespace_oid")) "6ba7b812-9dad-11d1-80b4-00c04fd430c8" else if (eql(u8, name, "namespace_x500")) "6ba7b814-9dad-11d1-80b4-00c04fd430c8" else return null;
    return .{ .uuid = uuid.parse(text) orelse return null };
}

/// Sixteen bytes of the system generator; an error without an input/output handle.
fn randomBytes(it: *Interp) Signal!uuid.Bytes16 {
    const io = it.io orelse return it.fail("uuid: no input/output handle for the random bytes", .{});
    var out: uuid.Bytes16 = undefined;
    io.random(&out);
    return out;
}

/// The Uuid argument `v` of the function `what`, or `$err_argument`.
fn uuidArg(it: *Interp, v: Value, what: []const u8) Signal!uuid.Bytes16 {
    if (v != .uuid) return it.failWith(err_argument, "{s}: the namespace is a Uuid, found {s}", .{ what, Interp.typeName(v) });
    return v.uuid;
}

// @eve-fn uuid.v4!, uuid.v7!, uuid.v3, uuid.v5
// @spec spec/library/bytes.md#uuid
// @feature F-LNG-13
// @test test/level5/e142_uuid_basics
// @test test/level5/e143_uuid_errors
// @test test/level5/e144_uuid_v7_time
// @perf hot
/// The functions of the module `uuid`; the names are those of the signature file lib/sys/uuid.eve.
pub fn uuidModule(it: *Interp, name: []const u8, _: []const *const Node, args: []const *const Node) Signal!?Value {
    if (eql(u8, name, "v4!")) return .{ .uuid = uuid.v4(try randomBytes(it)) };
    if (eql(u8, name, "v7!")) {
        const io = it.io orelse return it.fail("uuid.v7!: no input/output handle for the clock", .{});
        const ms: u64 = @intCast(@divFloor(Io.Timestamp.now(io, .real).toNanoseconds(), 1_000_000));
        return .{ .uuid = uuid.v7(ms, try randomBytes(it)) };
    }
    if (eql(u8, name, "v3") or eql(u8, name, "v5")) {
        if (args.len != 2) return it.failWith(err_argument, "uuid.{s} takes a namespace and a name", .{name});
        const ns = try uuidArg(it, try it.eval(args[0]), name);
        const txt = try it.text(try it.eval(args[1]));
        return .{ .uuid = if (eql(u8, name, "v3")) uuid.v3(ns, txt) else uuid.v5(ns, txt) };
    }
    return null;
}
