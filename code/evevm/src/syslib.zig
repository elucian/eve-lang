//! @eve-module syslib: native modules `crypto` and `os` of the system library
//! @spec spec/library/crypto.md, spec/library/os.md, spec/library/registry.md
//! @feature F-LIB-10, F-LIB-07
//! @decision D-189
//! @tests test/level6/f04_crypto, test/level6/f05_os
//! Handlers of type `dlib.Native`, registered in the table `dlib.natives`. Signatures: lib/sys/crypto.eve, lib/sys/os.eve.
const std = @import("std");
const Io = std.Io;
const ast = @import("evecm").ast;
const interp = @import("interp.zig");
const dlib = @import("dlib.zig");

const Node = ast.Node;
const Interp = interp.Interp;
const Value = interp.Value;
const Signal = interp.Signal;
const err_argument = interp.err_argument;

const Sha256 = std.crypto.hash.sha2.Sha256;
const Sha512 = std.crypto.hash.sha2.Sha512;
const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;

// @eve-impl evaluate argument `index` and require a String; `what` names the call in the error
fn strArg(it: *Interp, args: []const *const Node, index: usize, what: []const u8) Signal![]const u8 {
    if (args.len <= index) return it.failWith(err_argument, "{s}: argument {d} is missing", .{ what, index + 1 });
    const v = try it.eval(args[index]);
    if (v != .str) return it.failWith(err_argument, "{s}: argument {d} is a String", .{ what, index + 1 });
    return v.str;
}

// @eve-impl lower-case hexadecimal text of bytes, in scratch memory
fn hexText(it: *Interp, bytes: []const u8) Signal!Value {
    const out = try it.t.alloc(u8, bytes.len * 2);
    const digits = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        out[i * 2] = digits[b >> 4];
        out[i * 2 + 1] = digits[b & 15];
    }
    return try it.newStr(out);
}

// @eve-fn crypto.sha256, crypto.sha512, crypto.sha256_file!, crypto.hmac_sha256, crypto.hex_encode, crypto.hex_decode
// @eve-fn crypto.base64_encode, crypto.base64_decode, crypto.random_hex!, crypto.same
// @spec spec/library/crypto.md
// @feature F-LIB-10
pub fn cryptoModule(it: *Interp, name: []const u8, _: []const *const Node, args: []const *const Node) Signal!?Value {
    const eql = std.mem.eql;
    // @eve-fn crypto.crc32, crypto.fnv1a
    // @spec spec/library/crypto.md
    // @test c103_ids_hash
    if (eql(u8, name, "crc32")) return .{ .int = std.hash.Crc32.hash(try strArg(it, args, 0, "crypto.crc32")) };
    if (eql(u8, name, "fnv1a")) return .{ .int = std.hash.Fnv1a_32.hash(try strArg(it, args, 0, "crypto.fnv1a")) };
    if (eql(u8, name, "sha256")) {
        var digest: [Sha256.digest_length]u8 = undefined;
        Sha256.hash(try strArg(it, args, 0, "crypto.sha256"), &digest, .{});
        return try hexText(it, &digest);
    }
    if (eql(u8, name, "sha512")) {
        var digest: [Sha512.digest_length]u8 = undefined;
        Sha512.hash(try strArg(it, args, 0, "crypto.sha512"), &digest, .{});
        return try hexText(it, &digest);
    }
    if (eql(u8, name, "sha256_file!")) {
        const path = try strArg(it, args, 0, "crypto.sha256_file!");
        const bytes = try dlib.readFile(it, path);
        var digest: [Sha256.digest_length]u8 = undefined;
        Sha256.hash(bytes, &digest, .{});
        return try hexText(it, &digest);
    }
    if (eql(u8, name, "hmac_sha256")) {
        if (args.len != 2) return it.failWith(err_argument, "crypto.hmac_sha256 takes a key and the data", .{});
        const key_value = try it.eval(args[0]);
        const key: []const u8 = if (key_value == .str) key_value.str else if (it.isSecret(key_value)) blk: {
            const t = Interp.fieldOf(key_value.object, "text") orelse return it.failWith(err_argument, "crypto.hmac_sha256: empty Secret", .{});
            break :blk try it.text(t);
        } else return it.failWith(err_argument, "crypto.hmac_sha256: the key is a String or a Secret", .{});
        var mac: [HmacSha256.mac_length]u8 = undefined;
        HmacSha256.create(&mac, try strArg(it, args, 1, "crypto.hmac_sha256"), key);
        return try hexText(it, &mac);
    }
    if (eql(u8, name, "hex_encode")) return try hexText(it, try strArg(it, args, 0, "crypto.hex_encode"));
    if (eql(u8, name, "hex_decode")) {
        const text = try strArg(it, args, 0, "crypto.hex_decode");
        if (text.len % 2 != 0) return it.failWith(err_argument, "crypto.hex_decode: an odd number of digits", .{});
        const out = try it.t.alloc(u8, text.len / 2);
        _ = std.fmt.hexToBytes(out, text) catch return it.failWith(err_argument, "crypto.hex_decode: not a hexadecimal digit", .{});
        return try it.newStr(out);
    }
    if (eql(u8, name, "base64_encode")) {
        const data = try strArg(it, args, 0, "crypto.base64_encode");
        const enc = std.base64.standard.Encoder;
        const out = try it.t.alloc(u8, enc.calcSize(data.len));
        _ = enc.encode(out, data);
        return try it.newStr(out);
    }
    if (eql(u8, name, "base64_decode")) {
        const text = try strArg(it, args, 0, "crypto.base64_decode");
        const dec = std.base64.standard.Decoder;
        const size = dec.calcSizeForSlice(text) catch return it.failWith(err_argument, "crypto.base64_decode: not Base64 text", .{});
        const out = try it.t.alloc(u8, size);
        dec.decode(out, text) catch return it.failWith(err_argument, "crypto.base64_decode: not Base64 text", .{});
        return try it.newStr(out);
    }
    if (eql(u8, name, "random_hex!")) {
        if (args.len != 1) return it.failWith(err_argument, "crypto.random_hex! takes a number of bytes", .{});
        const n = try it.eval(args[0]);
        if (!Interp.isInt(n) or Interp.intOf(n) < 0 or Interp.intOf(n) > 1 << 20) return it.failWith(err_argument, "crypto.random_hex!: a number of bytes from 0 to 1048576", .{});
        const io = it.io orelse return it.fail("crypto.random_hex!: no input/output handle", .{});
        const raw = try it.t.alloc(u8, @intCast(Interp.intOf(n)));
        io.random(raw);
        return try hexText(it, raw);
    }
    if (eql(u8, name, "same")) {
        const a = try strArg(it, args, 0, "crypto.same");
        const b = try strArg(it, args, 1, "crypto.same");
        // the whole length of the longer text is always visited, so the time does not tell where they differ
        var diff: usize = a.len ^ b.len;
        const n = @max(a.len, b.len);
        for (0..n) |i| {
            const x: u8 = if (i < a.len) a[i] else 0;
            const y: u8 = if (i < b.len) b[i] else 0;
            diff |= x ^ y;
        }
        return .{ .bool = diff == 0 };
    }
    return null;
}

// @eve-fn os.run!, os.env!, os.hostname!, os.pid!, os.platform
// @spec spec/library/os.md
// @feature F-LIB-07
pub fn osModule(it: *Interp, name: []const u8, _: []const *const Node, args: []const *const Node) Signal!?Value {
    const eql = std.mem.eql;
    const builtin = @import("builtin");
    if (eql(u8, name, "platform")) {
        return try it.newStr(switch (builtin.os.tag) {
            .windows => "windows",
            .macos => "macos",
            else => "linux",
        });
    }
    if (eql(u8, name, "pid!")) {
        return .{ .int = if (builtin.os.tag == .windows) @intCast(std.os.windows.GetCurrentProcessId()) else @intCast(std.c.getpid()) };
    }
    if (eql(u8, name, "env!")) {
        const var_name = try strArg(it, args, 0, "os.env!");
        const default = try strArg(it, args, 1, "os.env!");
        const z = try it.t.dupeSentinel(u8, var_name, 0);
        const got = std.c.getenv(z.ptr) orelse return try it.newStr(default);
        return try it.newStr(std.mem.span(got));
    }
    if (eql(u8, name, "hostname!")) {
        var buf: [if (builtin.os.tag == .windows) 256 else std.posix.HOST_NAME_MAX]u8 = undefined;
        if (builtin.os.tag == .windows) {
            const z = std.c.getenv("COMPUTERNAME") orelse return try it.newStr("localhost");
            return try it.newStr(std.mem.span(z));
        }
        const got = std.posix.gethostname(&buf) catch return try it.newStr("localhost");
        return try it.newStr(got);
    }
    if (eql(u8, name, "run!")) return try run(it, args);
    return null;
}

/// The environment of this process as a map, to add variables to it for a child.
fn currentEnvironMap(gpa: std.mem.Allocator) !std.process.Environ.Map {
    const E = std.process.Environ;
    const env: E = if (@import("builtin").os.tag == .windows) .{ .block = .global } else .{ .block = .{ .slice = std.mem.span(std.c.environ) } };
    return env.createMap(gpa);
}

// @eve-impl os.run!: start a program with an argument list (no shell), collect both outputs, give a ProcessResult
// @spec spec/library/os.md
// @invariant the child's stdin is closed; a program that can not start gives status 127 and the reason in `err`
fn run(it: *Interp, args: []const *const Node) Signal!Value {
    if (args.len < 3 or args.len > 5) return it.failWith(err_argument, "os.run! takes a command, a list of arguments, a folder, an optional time-out and an optional map of environment variables", .{});
    const command = try strArg(it, args, 0, "os.run!");
    const list = try it.eval(args[1]);
    if (list != .list) return it.failWith(err_argument, "os.run!: the arguments are a list of String", .{});
    const cwd = try strArg(it, args, 2, "os.run!");
    const limit_ms: i64 = if (args.len == 4) (try it.eval(args[3])).int else 0;
    // @eve-impl the optional 5th argument of os.run!: a map String -> String added to the environment of the child (CLS: CMD-04, G-10)
    var child_env: ?std.process.Environ.Map = null;
    defer if (child_env) |*m| m.deinit();
    if (args.len == 5) {
        const extra = try it.eval(args[4]);
        if (extra != .map) return it.failWith(err_argument, "os.run!: the environment is a map of String to String", .{});
        var m = currentEnvironMap(it.t) catch return it.fail("os.run!: cannot read the environment", .{});
        child_env = m;
        for (extra.map.entries.items) |e| {
            if (e.key != .str or e.val != .str) return it.failWith(err_argument, "os.run!: the environment is a map of String to String", .{});
            child_env.?.put(e.key.str, e.val.str) catch return it.fail("os.run!: out of memory", .{});
        }
        m = child_env.?;
    }
    const io = it.io orelse return it.fail("os.run!: no input/output handle", .{});

    var argv: std.ArrayList([]const u8) = .empty;
    try argv.append(it.t, command);
    for (list.list.elems()) |e| {
        if (e != .str) return it.failWith(err_argument, "os.run!: every argument is a String", .{});
        try argv.append(it.t, e.str);
    }

    const result = try it.newObject();
    var out: std.ArrayList(u8) = .empty;
    var err: std.ArrayList(u8) = .empty;
    var status: i64 = 0;
    spawn: {
        var child = std.process.spawn(io, .{
            .argv = argv.items,
            .cwd = if (cwd.len > 0) .{ .path = cwd } else .inherit,
            .environ_map = if (child_env) |*m| m else null,
            .stdin = .ignore,
            .stdout = .pipe,
            .stderr = .pipe,
        }) catch |e| {
            status = 127;
            try err.print(it.t, "cannot start {s}: {s}", .{ command, @errorName(e) });
            break :spawn;
        };
        defer child.kill(io);
        var buf: Io.File.MultiReader.Buffer(2) = undefined;
        var mr: Io.File.MultiReader = undefined;
        mr.init(it.t, io, buf.toStreams(), &.{ child.stdout.?, child.stderr.? });
        defer mr.deinit();
        // @eve-impl time-out of os.run! (TD-9, TD-27): the deadline covers the whole run; the child is killed and the status is 124
        const deadline: Io.Timeout = if (limit_ms > 0) .{ .deadline = .fromNow(io, .{ .raw = .fromMilliseconds(limit_ms), .clock = .awake }) } else .none;
        var timed_out = false;
        while (true) {
            mr.fill(1, deadline) catch |e| {
                timed_out = e == error.Timeout;
                break;
            };
        }
        if (timed_out) {
            child.kill(io);
            status = 124;
            try err.print(it.t, "{s}: Time-out after {d} ms", .{ command, limit_ms });
            break :spawn;
        }
        try out.appendSlice(it.t, mr.reader(0).buffered());
        try err.appendSlice(it.t, mr.reader(1).buffered());
        const term = child.wait(io) catch {
            status = 1;
            break :spawn;
        };
        status = switch (term) {
            .exited => |code| code,
            else => 1,
        };
    }
    try it.setField(result, "status", .{ .int = status });
    try it.setField(result, "out", try it.newStr(out.items));
    try it.setField(result, "err", try it.newStr(err.items));
    return .{ .object = result };
}
