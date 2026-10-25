//! @eve-module dlib: native modules `database`, `csv`, `json`, `txt`, `fs`, `checkpoint`, `time`, `secret`, `crypto`, `os` (registry `natives`; crypto and os are in syslib.zig)
//! @spec spec/library/registry.md, spec/library/data-language.md, spec/library/database.md
//! @feature F-LIB-04, F-LIB-05, F-LIB-06, F-LIB-08, F-DAT-01
//! @decision D-189
//! @tests test/level5, test/level7/g01_pg_driver, test/level7/g02_evedb_columnar
//! The library of the data language (spec/library/data-language.md, spec/library/database.md): the modules
//! `csv`, `json` and `database`, the `Connection` of a database and the readers and writers of the formats.
//! They are free functions that take the interpreter, so `interp.zig` stays the core of the language: it calls
//! `libraryCall` for a method of a module and `connectionCall` for a method of a connection.
const std = @import("std");
const Io = std.Io;
const ast = @import("evecm").ast;
const interp = @import("interp.zig");
const db = @import("db.zig");
const data = @import("evecm").data;
const decimal = @import("evecm").decimal;
const instant = @import("evecm").instant;
const nfc = @import("evecm").nfc;
const Heap = @import("evecm").heap.Heap;
const syslib = @import("syslib.zig");
const netlib = @import("netlib.zig");
const mathlib = @import("mathlib.zig");
const timelib = @import("timelib.zig");
const metalib = @import("metalib.zig");
const evecm = @import("evecm");
const linearlib = @import("linearlib.zig");
const rationallib = @import("rationallib.zig");
const complexlib = @import("complexlib.zig");
const randomlib = @import("randomlib.zig");

const Node = ast.Node;
const Interp = interp.Interp;
const bytesfn = @import("interp/bytesfn.zig");
const uuidlib = @import("uuidlib.zig");
const globlib = @import("globlib.zig");
const gziplib = @import("gziplib.zig");
const Value = interp.Value;
const Class = interp.Class;
const Object = interp.Object;
const List = interp.List;
const Signal = interp.Signal;
const err_argument = interp.err_argument;
const err_convert = interp.err_convert;
const err_file = interp.err_file;
const err_io = interp.err_io;
const err_key = interp.err_key;
const err_null = interp.err_null;

// ---- the library of the data language: files, formats and the database connection --------------
// (spec/library/data-language.md, spec/semantics/data-types.md, spec/library/database.md#direct-sql). A call
// `csv.read!(:Row)(path)` reaches `libraryCall` through `callMethod`: `csv`, `json`, `txt`, `fs`, `time`,
// `secret` and `database` are values of the prelude (`.typ`), like `Channel`. The type argument `(:Row)` names
// the record class that the units of a file become.

/// The error code of a `FormatError`: a unit of a data file is not well formed (errors.md, `$err_format`).
pub const err_format = 56;

/// One option of a library call: `name: value`.
pub const Opt = struct {
    name: []const u8,
    value: Value,
    used: bool = false,
};

/// Evaluate the arguments after the first ones: each must be written `name: value`.
fn options(it: *Interp, nodes: []const *const Node, what: []const u8) Signal![]Opt {
    var out: std.ArrayList(Opt) = .empty;
    for (nodes) |n| {
        if (n.tag != .pair or n.kids[0].tag != .name) return it.failWith(err_argument, "{s}: an option is written name: value", .{what});
        try out.append(it.t, .{ .name = n.kids[0].text, .value = try it.eval(n.kids[1]) });
    }
    return out.items;
}

fn opt(opts: []Opt, name: []const u8) ?Value {
    for (opts) |*o| if (std.mem.eql(u8, o.name, name)) {
        o.used = true;
        return o.value;
    };
    return null;
}

fn optText(it: *Interp, opts: []Opt, name: []const u8) Signal!?[]const u8 {
    const v = opt(opts, name) orelse return null;
    if (v != .str) return it.failWith(err_argument, "the option {s} is a String", .{name});
    return v.str;
}

fn optFlag(it: *Interp, opts: []Opt, name: []const u8, default: bool) Signal!bool {
    const v = opt(opts, name) orelse return default;
    if (v != .bool) return it.failWith(err_argument, "the option {s} is True or False", .{name});
    return v.bool;
}

fn noMoreOptions(it: *Interp, opts: []Opt, what: []const u8) Signal!void {
    for (opts) |o| if (!o.used) return it.failWith(err_argument, "{s}: unknown option '{s}'", .{ what, o.name });
}

// @eve-impl library registry: module name -> native handler (one hash lookup instead of a chain of string compares)
// @spec spec/library/registry.md#registry-rules
// @feature F-LIB-01
// @decision D-189
// @invariant a module name is in `natives` iff it is a value of the prelude with native members (the `types` list in code/evevm/src/interp.zig:354)
// @see lib/README.md (signature files of the same modules)
/// A native handler: the functions of one module. Returns null when `name` is not a function of the module.
pub const Native = *const fn (it: *Interp, name: []const u8, targs: []const *const Node, args: []const *const Node) Signal!?Value;

// @eve-impl the table of native modules; add a module here and give it a signature file lib/<module>.eve
// @spec spec/library/registry.md#modules-of-the-system-library-at-level-6
// @feature F-LIB-01
pub const natives = std.StaticStringMap(Native).initComptime(.{
    .{ "database", databaseModule },
    .{ "csv", csvModule },
    .{ "json", jsonModule },
    .{ "txt", txtModule },
    .{ "fs", fsModule },
    .{ "checkpoint", checkpointModule },
    .{ "time", timelib.timeModule },
    .{ "secret", secretModule },
    .{ "crypto", syslib.cryptoModule },
    .{ "uuid", uuidlib.uuidModule },
    .{ "gzip", gzipModule },
    .{ "os", syslib.osModule },
    .{ "net", netlib.netModule },
    .{ "basic", mathlib.mathModule },
    .{ "explog", mathlib.mathModule },
    .{ "trig", mathlib.mathModule },
    .{ "numtheory", mathlib.mathModule },
    .{ "linear", linearlib.linearModule },
    .{ "rational", rationallib.rationalModule },
    .{ "complex", complexlib.complexModule },
    .{ "random", randomlib.randomModule },
});

// @eve-impl the fast path of a call of a pure numeric library function: no scope, no names, the values go straight to the function
// @spec spec/library/registry.md#modules-of-the-system-library-at-level-6
// @feature F-LIB-03
// @perf hot
// @invariant the code is 65536 * family + id of the function (family 1 mathlib, 2 rationallib, 3 complexlib, 4 timelib, 5 metalib); a code below 2 is never returned
pub fn fastResolve(module: []const u8, name: []const u8) ?u32 {
    const eql = std.mem.eql;
    if (eql(u8, module, "basic") or eql(u8, module, "explog") or eql(u8, module, "trig") or eql(u8, module, "numtheory")) {
        return if (mathlib.fastId(name)) |id| @as(u32, 65536) + id else null;
    }
    if (eql(u8, module, "rational")) return if (rationallib.fastId(name)) |id| 2 * @as(u32, 65536) + id else null;
    if (eql(u8, module, "complex")) return if (complexlib.fastId(name)) |id| 3 * @as(u32, 65536) + id else null;
    if (eql(u8, module, "time")) return if (timelib.fastId(name)) |id| 4 * @as(u32, 65536) + id else null;
    return null;
}

// @perf hot
pub fn fastCall(it: *Interp, code: u32, args: []const Value) Signal!Value {
    const id: u16 = @intCast(code & 0xffff);
    return switch (code >> 16) {
        1 => mathlib.fastCall(it, id, args),
        2 => rationallib.fastCall(it, id, args),
        4 => timelib.fastCall(it, id, args),
        else => complexlib.fastCall(it, id, args),
    };
}

// @eve-impl entry point of every `module.name(...)` call on a prelude type
// @feature F-LIB-01
// @perf hot
// @see code/evevm/src/interp/calls.zig (callMethod, `recv == .typ`)
/// A function of a library module, or null when `module.name` is not one.
pub fn libraryCall(it: *Interp, module: []const u8, name: []const u8, args: []const *const Node) Signal!?Value {
    const handler = natives.get(module) orelse return null;
    // the type arguments are copied now: evaluating the arguments runs other calls, which overwrite the field
    return try handler(it, name, it.type_args, args);
}

// @eve-fn database.connect
// @spec spec/library/database.md#direct-sql
fn databaseModule(it: *Interp, name: []const u8, _: []const *const Node, args: []const *const Node) Signal!?Value {
    if (std.mem.eql(u8, name, "connect")) return try db.driver.connect(it.host(), args);
    return null;
}

// @eve-fn gzip.open!
// @spec spec/library/data-language.md#compression
// @feature F-LIB-09
// @test test/level5/e154_gzip_stream
/// `gzip.open!(path)`: the content of a gzip file as a Stream(:Bytes), in chunks of 64 KiB; the content is inflated when the file is opened.
fn gzipModule(it: *Interp, name: []const u8, _: []const *const Node, args: []const *const Node) Signal!?Value {
    if (!std.mem.eql(u8, name, "open!")) return null;
    const path = try pathArg(it, args, 0, "gzip.open!");
    const raw = try readFile(it, path);
    const inflated = (try gziplib.gunzip(it.a, raw)) orelse return it.failWith(err_format, "gzip.open!: {s} is not gzip", .{path});
    return try newStream(it, .{ .kind = .bytes, .path = path, .text = inflated });
}

// @eve-fn csv.read!, csv.write
// @spec spec/library/data-language.md
fn csvModule(it: *Interp, name: []const u8, targs: []const *const Node, args: []const *const Node) Signal!?Value {
    return try recordModule(it, .csv, name, targs, args);
}

// @eve-fn json.read!, json.write
// @spec spec/library/data-language.md
fn jsonModule(it: *Interp, name: []const u8, targs: []const *const Node, args: []const *const Node) Signal!?Value {
    if (std.mem.eql(u8, name, "parse")) return try jsonParse(it, args);
    if (std.mem.eql(u8, name, "text")) return try jsonText(it, args);
    if (std.mem.eql(u8, name, "valid")) return try jsonValid(it, args);
    return try recordModule(it, .json, name, targs, args);
}

// @eve-fn json.parse
// @spec spec/library/data-language.md#json-text-in-memory-jsonparse-and-jsontext
// @feature F-LIB-05
// @test test/level6/f06_json_text
fn jsonParse(it: *Interp, args: []const *const Node) Signal!Value {
    if (args.len != 1) return it.failWith(err_argument, "json.parse takes a text", .{});
    const v = try it.eval(args[0]);
    if (v != .str) return it.failWith(err_argument, "json.parse: the argument is a String", .{});
    var diag: data.JsonDiag = .{};
    const j = data.parseJson(it.t, v.str, &diag) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.BadJson => return it.failWith(err_format, "json.parse: {s} (line {d}, column {d})", .{ diag.reason, diag.line, diag.column }),
    };
    return try jsonToValue(it, j);
}

// @eve-fn json.valid
// @spec spec/library/data-language.md#json-text-in-memory-jsonparse-and-jsontext
// @feature F-LIB-05
// @test test/level6/f06_json_text
// @invariant a function of Eve code can not catch an error (G-4), so a library asks `json.valid` before `json.parse`
fn jsonValid(it: *Interp, args: []const *const Node) Signal!Value {
    if (args.len != 1) return it.failWith(err_argument, "json.valid takes a text", .{});
    const v = try it.eval(args[0]);
    if (v != .str) return .{ .bool = false };
    var diag: data.JsonDiag = .{};
    _ = data.parseJson(it.t, v.str, &diag) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.BadJson => return .{ .bool = false },
    };
    return .{ .bool = true };
}

// @eve-impl a parsed JSON value as an Eve value: null, Logic, Integer or Real, String, List, DataMap
fn jsonToValue(it: *Interp, j: data.Json) Signal!Value {
    switch (j) {
        .null => return .nil,
        .boolean => |b| return .{ .bool = b },
        .number => |n| {
            if (std.fmt.parseInt(i64, n, 10)) |i| return .{ .int = i } else |_| {}
            return .{ .real = std.fmt.parseFloat(f64, n) catch return it.failWith(err_format, "json.parse: bad number {s}", .{n}) };
        },
        .string => |s| return try it.newStr(s),
        .array => |items| {
            const list = try it.newList(&.{}, false);
            for (items) |e| try it.listAppend(list, try jsonToValue(it, e));
            return .{ .list = list };
        },
        .object => |members| {
            const m = try it.newMap();
            for (members) |mem| try it.mapPut(m, try it.newStr(mem.key), try jsonToValue(it, mem.value));
            return .{ .map = m };
        },
    }
}

// @eve-fn json.text
// @spec spec/library/data-language.md#json-text-in-memory-jsonparse-and-jsontext
// @feature F-LIB-05
// @test test/level6/f06_json_text
fn jsonText(it: *Interp, args: []const *const Node) Signal!Value {
    if (args.len != 1) return it.failWith(err_argument, "json.text takes a value", .{});
    const v = try it.eval(args[0]);
    var w: Io.Writer.Allocating = .init(it.t);
    try jsonValue(it, &w.writer, v);
    return try it.newStr(w.written());
}

// @eve-fn txt.read!, txt.write
// @spec spec/library/data-language.md
fn txtModule(it: *Interp, name: []const u8, targs: []const *const Node, args: []const *const Node) Signal!?Value {
    return try recordModule(it, .txt, name, targs, args);
}

// @eve-impl shared body of csv, json and txt: `read!` opens a stream of records, `write` writes them
fn recordModule(it: *Interp, kind: Kind, name: []const u8, targs: []const *const Node, args: []const *const Node) Signal!?Value {
    if (std.mem.eql(u8, name, "read!")) return try openRecords(it, kind, targs, args);
    if (std.mem.eql(u8, name, "write")) {
        try writeRecords(it, kind, args);
        return .nil;
    }
    return null;
}

// @eve-fn fs.*
// @spec spec/library/data-language.md
// @see fsCall (the list of functions)
fn fsModule(it: *Interp, name: []const u8, _: []const *const Node, args: []const *const Node) Signal!?Value {
    return try fsCall(it, name, args);
}

// @eve-fn checkpoint.*
// @spec spec/library/database.md
fn checkpointModule(it: *Interp, name: []const u8, targs: []const *const Node, args: []const *const Node) Signal!?Value {
    return try db.orm.checkpointCall(it.host(), name, targs, args);
}

// @eve-fn secret.get
// @spec spec/library/registry.md#registry-rules (rule 5: a Secret is never printed)
fn secretModule(it: *Interp, name: []const u8, _: []const *const Node, args: []const *const Node) Signal!?Value {
    if (std.mem.eql(u8, name, "get")) return try it.secretGet(args);
    return null;
}

// @test registry: every module of `natives` has a handler and `libraryCall` of an unknown module is null
test "natives registry names" {
    try std.testing.expect(natives.get("fs") != null);
    try std.testing.expect(natives.get("database") != null);
    try std.testing.expect(natives.get("no_such_module") == null);
}

/// The class named by the type argument of a library call (`(:Row)`): it must be a record class.
pub fn recordClass(it: *Interp, targs: []const *const Node, what: []const u8) Signal!*Class {
    if (targs.len != 1) return it.failWith(err_argument, "{s} needs the record class as a type argument: {s}(:Row)(...)", .{ what, what });
    const v = try it.lookup(targs[0].text);
    if (v != .class or v.class.node == null) return it.failWith(err_argument, "{s}: '{s}' is not a record class", .{ what, targs[0].text });
    return v.class;
}

/// Does the type end with `?`; see ast.zig.
pub const isOptional = ast.isOptional;
/// The name of a type without its `?`; see ast.zig.
pub const baseType = ast.baseType;

// ---- errors of the readers --------------------------------------------------------------------

/// Raise a `FormatError` (code 56): `Bad CSV at line 3, column 1: reason`.
fn formatError(it: *Interp, format: []const u8, line: usize, column: usize, comptime fmt: []const u8, args: anytype) Signal {
    var buf: [256]u8 = undefined;
    const reason = std.fmt.bufPrint(&buf, fmt, args) catch "a unit is not well formed";
    return it.failWith(err_format, "Bad {s} at line {d}, column {d}: {s}", .{ format, line, column, reason });
}

// ---- reading text: encodings -------------------------------------------------------------------

const win1252 = [32]u21{
    0x20AC, 0x81,   0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D,   0x017D, 0x8F,
    0x90,   0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D,   0x017E, 0x0178,
};

/// Decode the bytes of a file to UTF-8 text.
fn decodeBytes(it: *Interp, bytes_in: []const u8, encoding_opt: ?[]const u8, invalid: []const u8, what: []const u8, path: []const u8) Signal![]const u8 {
    var bytes = bytes_in;
    var enc: []const u8 = "utf-8";
    if (encoding_opt) |e| enc = e;
    if (std.mem.startsWith(u8, bytes, "\xEF\xBB\xBF")) {
        bytes = bytes[3..];
        enc = "utf-8";
    } else if (std.mem.startsWith(u8, bytes, "\xFF\xFE")) {
        bytes = bytes[2..];
        enc = "utf-16le";
    } else if (std.mem.startsWith(u8, bytes, "\xFE\xFF")) {
        bytes = bytes[2..];
        enc = "utf-16be";
    }
    var lower: [32]u8 = undefined;
    const name = std.ascii.lowerString(&lower, enc[0..@min(enc.len, lower.len)]);
    const eql = std.mem.eql;
    if (eql(u8, name, "utf-16le") or eql(u8, name, "utf-16be")) {
        if (bytes.len % 2 != 0) return formatError(it, what, 1, 1, "{s}: a UTF-16 file has an even number of bytes", .{path});
        const units = try it.a.alloc(u16, bytes.len / 2);
        for (units, 0..) |*u, i| {
            u.* = if (eql(u8, name, "utf-16le")) std.mem.readInt(u16, bytes[i * 2 ..][0..2], .little) else std.mem.readInt(u16, bytes[i * 2 ..][0..2], .big);
        }
        return std.unicode.utf16LeToUtf8Alloc(it.a, units) catch formatError(it, what, 1, 1, "{s}: not valid UTF-16", .{path});
    }
    if (eql(u8, name, "iso-8859-1") or eql(u8, name, "latin1") or eql(u8, name, "windows-1252") or eql(u8, name, "cp1252")) {
        const cp1252 = eql(u8, name, "windows-1252") or eql(u8, name, "cp1252");
        var out: std.ArrayList(u8) = .empty;
        for (bytes) |b| {
            const cp: u21 = if (cp1252 and b >= 0x80 and b < 0xA0) win1252[b - 0x80] else b;
            var buf: [4]u8 = undefined;
            const n = std.unicode.utf8Encode(cp, &buf) catch continue;
            try out.appendSlice(it.a, buf[0..n]);
        }
        return out.items;
    }
    if (!eql(u8, name, "utf-8") and !eql(u8, name, "utf8")) {
        return it.failWith(err_argument, "encoding '{s}' is not supported: utf-8, utf-16le, utf-16be, iso-8859-1, windows-1252", .{enc});
    }
    if (std.unicode.utf8ValidateSlice(bytes)) return bytes;
    // find the first invalid byte, for the message, or replace every invalid byte
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    var line: usize = 1;
    var col: usize = 1;
    while (i < bytes.len) {
        const len = std.unicode.utf8ByteSequenceLength(bytes[i]) catch 0;
        const ok = len > 0 and i + len <= bytes.len and std.unicode.utf8ValidateSlice(bytes[i .. i + len]);
        if (!ok) {
            if (!std.mem.eql(u8, invalid, "replace")) return formatError(it, what, line, col, "{s}: invalid UTF-8 at byte {d}", .{ path, i });
            try out.appendSlice(it.a, "\u{FFFD}");
            i += 1;
            col += 1;
            continue;
        }
        try out.appendSlice(it.a, bytes[i .. i + len]);
        if (bytes[i] == '\n') {
            line += 1;
            col = 1;
        } else col += 1;
        i += len;
    }
    return out.items;
}

/// Read a whole file into memory of the run; a missing file is the error `$err_file`.
// @eve-impl the readers of csv, json, txt and fs.lines! inflate a `.gz` path (data-language.md#compression)
// @spec spec/library/data-language.md#compression
// @feature F-LIB-09
// @test test/level5/e152_gzip_readers
/// The content of a data file: the bytes, or the inflated bytes when the path ends in .gz.
fn readData(it: *Interp, path: []const u8) Signal![]const u8 {
    const raw = try readFile(it, path);
    if (!gziplib.isGzPath(path)) return raw;
    return (try gziplib.gunzip(it.a, raw)) orelse it.failWith(err_format, "cannot read {s}: the file is not gzip", .{path});
}

pub fn readFile(it: *Interp, path: []const u8) Signal![]const u8 {
    const io = it.io orelse return it.fail("no input/output handle", .{});
    return Io.Dir.cwd().readFileAlloc(io, path, it.a, .limited(1 << 30)) catch |e| switch (e) {
        error.FileNotFound => it.failWith(err_file, "cannot read {s}: the file does not exist", .{path}),
        error.AccessDenied, error.PermissionDenied => it.failWith(interp.err_access, "cannot read {s}: access refused", .{path}),
        else => it.failWith(err_io, "cannot read {s}: {s}", .{ path, @errorName(e) }),
    };
}

fn writeFile(it: *Interp, path: []const u8, bytes: []const u8) Signal!void {
    const io = it.io orelse return it.fail("no input/output handle", .{});
    if (std.fs.path.dirname(path)) |dir| Io.Dir.cwd().createDirPath(io, dir) catch |e|
        return it.failWith(err_io, "cannot make the folder of {s}: {s}", .{ path, @errorName(e) });
    Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = bytes }) catch |e|
        return it.failWith(err_io, "cannot write {s}: {s}", .{ path, @errorName(e) });
}

// ---- streams: the units of a file, one at a time ---------------------------------------------

pub const Kind = enum { lines, csv, json, txt, bytes };

/// The size of a chunk of a stream of Bytes (`gzip.open!`): the unit a stream gives at a time.
const bytes_chunk: usize = 64 * 1024;

/// A unit that was refused and went to the rejects file (data-types.md, transform and rejects).
const Reject = struct {
    line: usize,
    column: usize,
    text: []const u8,
    reason: []const u8,
};

/// The open source of a `for` loop over `csv.read!`, `json.read!`, `txt.read!` or `fs.lines!`.
pub const Stream = struct {
    kind: Kind,
    path: []const u8,
    cls: ?*Class = null,
    members: []const *const Node = &.{},
    /// `lines`: the text and the place of the next line.
    text: []const u8 = "",
    pos: usize = 0,
    /// `csv`: the rows, the column of each member, the number of fields of the header, the next row.
    rows: []const data.Row = &.{},
    cols: []const usize = &.{},
    header_len: usize = 0,
    next_row: usize = 1,
    /// `json`: the documents and the next one.
    docs: []const data.Json = &.{},
    next_doc: usize = 0,
    /// `txt`: the widths, in code points, and the lines.
    widths: []const usize = &.{},
    line_no: usize = 0,
    normalize: bool = false,
    rejects_path: ?[]const u8 = null,
    max_rejects: usize = std.math.maxInt(usize),
    rejects: std.ArrayList(Reject) = .empty,
    reject_count: usize = 0,
    finished: bool = false,
};

fn streamOf(it: *Interp, o: *Object) *Stream {
    return it.base().streams.items[@intCast(Interp.intOf(Interp.fieldOf(o, "handle").?))];
}

/// Is the value a `Stream` object?
pub fn isStream(it: *Interp, v: Value) bool {
    return v == .object and v.object.class != null and v.object.class == it.base().stream_class;
}

fn newStream(it: *Interp, st: Stream) Signal!Value {
    const b = it.base();
    if (b.stream_class == null) {
        const cls = try it.a.create(Class);
        cls.* = .{ .name = "Stream" };
        b.stream_class = cls;
    }
    const slot = try it.a.create(Stream);
    slot.* = st;
    try b.streams.append(it.a, slot);
    const obj = try it.newObject();
    obj.class = b.stream_class;
    try it.setField(obj, "handle", .{ .int = @intCast(b.streams.items.len - 1) });
    return .{ .object = obj };
}

/// `fs.lines!(path)`: a stream of the lines of a text file, without their line endings.
fn openLines(it: *Interp, args: []const *const Node) Signal!Value {
    if (args.len < 1) return it.fail("fs.lines! takes a path", .{});
    const path = try it.text(try it.eval(args[0]));
    const opts = try options(it, args[1..], "fs.lines!");
    const bytes = try readData(it, path);
    const text = try decodeBytes(it, bytes, try optText(it, opts, "encoding"), try optText(it, opts, "invalid") orelse "error", "text", path);
    try noMoreOptions(it, opts, "fs.lines!");
    return newStream(it, .{ .kind = .lines, .path = path, .text = text });
}

/// The widths of `txt`: a list of whole numbers.
fn widthList(it: *Interp, v: ?Value, what: []const u8) Signal![]const usize {
    const w = v orelse return it.failWith(err_argument, "{s} needs the option widths: (4, 8, ...)", .{what});
    if (w != .list) return it.failWith(err_argument, "{s}: widths is a list of whole numbers", .{what});
    const out = try it.a.alloc(usize, w.list.elems().len);
    for (w.list.elems(), out) |e, *slot| {
        if (!Interp.isInt(e) or Interp.intOf(e) <= 0) return it.failWith(err_argument, "{s}: a width is a positive whole number", .{what});
        slot.* = @intCast(Interp.intOf(e));
    }
    return out;
}

fn openRecords(it: *Interp, kind: Kind, targs: []const *const Node, args: []const *const Node) Signal!Value {
    const what: []const u8 = switch (kind) {
        .csv => "csv.read!",
        .json => "json.read!",
        else => "txt.read!",
    };
    const cls = try recordClass(it, targs, what);
    if (args.len < 1) return it.failWith(err_argument, "{s} takes a path", .{what});
    const path = try it.text(try it.eval(args[0]));
    const opts = try options(it, args[1..], what);
    const format: []const u8 = switch (kind) {
        .csv => "CSV",
        .json => "JSON",
        else => "TXT",
    };
    var st: Stream = .{ .kind = kind, .path = path, .cls = cls, .members = cls.node.?.kids[0].kids };
    const encoding = try optText(it, opts, "encoding");
    const invalid = try optText(it, opts, "invalid") orelse "error";
    if (try optText(it, opts, "normalize")) |n| {
        if (!std.mem.eql(u8, n, "nfc")) return it.failWith(err_argument, "{s}: normalize is \"nfc\"", .{what});
        st.normalize = true;
    }
    st.rejects_path = try optText(it, opts, "rejects");
    if (opt(opts, "max_rejects")) |m| {
        if (!Interp.isInt(m) or Interp.intOf(m) < 0) return it.failWith(err_argument, "{s}: max_rejects is a whole number", .{what});
        st.max_rejects = @intCast(Interp.intOf(m));
    }
    const text = try decodeBytes(it, try readData(it, path), encoding, invalid, format, path);
    switch (kind) {
        .csv => {
            const sep_text = try optText(it, opts, "sep") orelse ",";
            if (sep_text.len != 1) return it.failWith(err_argument, "csv.read!: sep is one character", .{});
            const renames = opt(opts, "columns");
            st.rows = data.parseCsv(it.a, text, sep_text[0]) catch |e| switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
                error.UnterminatedQuote => return formatError(it, format, 1, 1, "{s}: a quote is not closed", .{path}),
            };
            if (st.rows.len == 0) return formatError(it, format, 1, 1, "{s}: no header line", .{path});
            st.header_len = st.rows[0].fields.len;
            const cols = try it.a.alloc(usize, st.members.len);
            for (st.members, cols) |m, *slot| {
                var wanted: []const u8 = m.text;
                // `columns: {"Order No": "id"}` maps the name in the file to the member
                if (renames) |r| if (r == .map) for (r.map.entries.items) |entry| {
                    if (entry.val == .str and std.mem.eql(u8, entry.val.str, m.text) and entry.key == .str) wanted = entry.key.str;
                };
                slot.* = for (st.rows[0].fields, 0..) |h, j| {
                    if (std.mem.eql(u8, h.text, wanted)) break j;
                } else return formatError(it, format, 1, 1, "{s}: no column '{s}' for {s}", .{ path, wanted, cls.name });
            }
            st.cols = cols;
        },
        .json => {
            var diag: data.JsonDiag = .{};
            st.docs = data.parseJsonDocuments(it.a, text, &diag) catch |e| switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
                error.BadJson => return formatError(it, format, diag.line, diag.column, "{s}", .{diag.reason}),
            };
        },
        .txt => {
            st.widths = try widthList(it, opt(opts, "widths"), what);
            st.text = text;
        },
        .lines, .bytes => unreachable,
    }
    try noMoreOptions(it, opts, what);
    return newStream(it, st);
}

/// Convert one field (text and whether it was quoted) to the value of the member `m`; null if it can not be.
fn fromField(it: *Interp, f: data.Field, m: *const Node, reason: *[]const u8) Signal!?Value {
    const eql = std.mem.eql;
    const ty = baseType(m.ty);
    if (f.text.len == 0 and !f.quoted) {
        if (isOptional(m.ty)) return .nil;
        reason.* = try std.fmt.allocPrint(it.t, "'{s}' is empty but is not optional", .{m.text});
        return null;
    }
    if (eql(u8, ty, "String") or eql(u8, ty, "Text")) return try it.newStr(f.text);
    if (eql(u8, ty, "Integer") or eql(u8, ty, "Short") or eql(u8, ty, "Byte")) {
        const n = std.fmt.parseInt(i64, f.text, 10) catch {
            reason.* = try std.fmt.allocPrint(it.t, "'{s}' is not an Integer: {s}", .{ m.text, f.text });
            return null;
        };
        return .{ .int = n };
    }
    if (eql(u8, ty, "Real") or eql(u8, ty, "Float")) {
        const x = std.fmt.parseFloat(f64, f.text) catch {
            reason.* = try std.fmt.allocPrint(it.t, "'{s}' is not a Real: {s}", .{ m.text, f.text });
            return null;
        };
        return .{ .real = x };
    }
    if (eql(u8, ty, "Decimal")) {
        const d = decimal.parse(f.text) orelse {
            reason.* = try std.fmt.allocPrint(it.t, "'{s}' is not a Decimal: {s}", .{ m.text, f.text });
            return null;
        };
        return .{ .dec = d };
    }
    if (eql(u8, ty, "Date")) {
        const days = evecm.calendar.parseDate(f.text) orelse {
            reason.* = try std.fmt.allocPrint(it.t, "'{s}' is not a Date: {s}", .{ m.text, f.text });
            return null;
        };
        return .{ .date = days };
    }
    if (eql(u8, ty, "Time")) {
        const us = evecm.calendar.parseTime(f.text) orelse {
            reason.* = try std.fmt.allocPrint(it.t, "'{s}' is not a Time: {s}", .{ m.text, f.text });
            return null;
        };
        return .{ .time = us };
    }
    if (eql(u8, ty, "Duration")) {
        const us = evecm.duration.parse(f.text) orelse {
            reason.* = try std.fmt.allocPrint(it.t, "'{s}' is not a Duration: {s}", .{ m.text, f.text });
            return null;
        };
        return .{ .dur = us };
    }
    if (eql(u8, ty, "DateTime")) {
        const v = timelib.parseDateTimeIso(it, f.text) catch {
            reason.* = try std.fmt.allocPrint(it.t, "'{s}' is not a DateTime: {s}", .{ m.text, f.text });
            return null;
        };
        return v;
    }
    if (eql(u8, ty, "Zone")) {
        const zid = (metalib.zoneIdOf(it, f.text) catch null) orelse {
            reason.* = try std.fmt.allocPrint(it.t, "'{s}' is not a Zone: {s}", .{ m.text, f.text });
            return null;
        };
        return .{ .zone = zid };
    }
    if (eql(u8, ty, "Instant")) {
        const us = instant.parse(f.text) orelse {
            reason.* = try std.fmt.allocPrint(it.t, "'{s}' is not an Instant: {s}", .{ m.text, f.text });
            return null;
        };
        return .{ .instant = us };
    }
    if (eql(u8, ty, "Logic")) {
        if (eql(u8, f.text, "True") or eql(u8, f.text, "true")) return .{ .bool = true };
        if (eql(u8, f.text, "False") or eql(u8, f.text, "false")) return .{ .bool = false };
        reason.* = try std.fmt.allocPrint(it.t, "'{s}' is not a Logic: {s}", .{ m.text, f.text });
        return null;
    }
    reason.* = try std.fmt.allocPrint(it.t, "the type {s} of '{s}' can not be read from a file yet", .{ ty, m.text });
    return null;
}

/// A JSON value as a field: a string is quoted text, a number keeps its text, null is an empty field.
fn jsonField(j: data.Json, reason: *[]const u8) ?data.Field {
    return switch (j) {
        .null => .{ .text = "", .quoted = false },
        .boolean => |b| .{ .text = if (b) "True" else "False", .quoted = false },
        .number => |n| .{ .text = n, .quoted = false },
        .string => |s| .{ .text = s, .quoted = true },
        else => blk: {
            reason.* = "a nested value can not be read into a field";
            break :blk null;
        },
    };
}

/// Cut the line `text` into fields of the given widths, in code points; a short line gives empty fields.
fn txtFields(it: *Interp, line: []const u8, widths: []const usize) Signal![]data.Field {
    const out = try it.t.alloc(data.Field, widths.len);
    var pos: usize = 0;
    for (widths, out) |w, *slot| {
        const start = pos;
        var n: usize = 0;
        while (n < w and pos < line.len) : (n += 1) {
            pos += std.unicode.utf8ByteSequenceLength(line[pos]) catch 1;
            if (pos > line.len) pos = line.len;
        }
        slot.* = .{ .text = std.mem.trim(u8, line[start..pos], " "), .quoted = false };
    }
    return out;
}

fn addReject(it: *Interp, st: *Stream, line: usize, column: usize, text: []const u8, reason: []const u8) Signal!void {
    st.reject_count += 1;
    if (st.reject_count > st.max_rejects) {
        return formatError(it, formatName(st.kind), line, column, "more than {d} rejects; the last: {s}", .{ st.max_rejects, reason });
    }
    try st.rejects.append(it.a, .{ .line = line, .column = column, .text = try it.a.dupe(u8, text), .reason = try it.a.dupe(u8, reason) });
}

fn formatName(kind: Kind) []const u8 {
    return switch (kind) {
        .csv => "CSV",
        .json => "JSON",
        .txt => "TXT",
        .lines => "text",
        .bytes => "Bytes",
    };
}

/// A field, with its text composed to NFC when the read asks for it.
fn normalized(it: *Interp, st: *Stream, f: data.Field) Signal!data.Field {
    if (!st.normalize or f.text.len == 0) return f;
    return .{ .text = nfc.normalize(it.a, f.text) catch return error.OutOfMemory, .quoted = f.quoted };
}

/// The next value of a stream, or null at the end. Errors of a unit are raised here, when the loop reaches it.
pub fn streamNext(it: *Interp, st: *Stream) Signal!?Value {
    if (st.finished) return null;
    switch (st.kind) {
        .bytes => {
            if (st.pos >= st.text.len) {
                try finishStream(it, st);
                return null;
            }
            const end = @min(st.pos + bytes_chunk, st.text.len);
            const chunk = st.text[st.pos..end];
            st.pos = end;
            return try bytesfn.newBytes(it, chunk);
        },
        .lines => {
            if (st.pos >= st.text.len) {
                try finishStream(it, st);
                return null;
            }
            const end = std.mem.indexOfScalarPos(u8, st.text, st.pos, '\n') orelse st.text.len;
            var line = st.text[st.pos..end];
            if (line.len > 0 and line[line.len - 1] == '\r') line = line[0 .. line.len - 1];
            st.pos = @min(end + 1, st.text.len + 1);
            return try it.newStr(line);
        },
        else => {},
    }
    const format = formatName(st.kind);
    while (true) {
        var fields: []const data.Field = &.{};
        var line: usize = 0;
        var raw: []const u8 = "";
        switch (st.kind) {
            .csv => {
                if (st.next_row >= st.rows.len) break;
                const row = st.rows[st.next_row];
                st.next_row += 1;
                line = row.line;
                fields = row.fields;
                raw = if (fields.len > 0) fields[0].text else "";
                if (fields.len != st.header_len) {
                    const reason = try std.fmt.allocPrint(it.t, "expected {d} fields, found {d}", .{ st.header_len, fields.len });
                    if (st.rejects_path != null) {
                        try addReject(it, st, line, 1, try joinFields(it, fields), reason);
                        continue;
                    }
                    return formatError(it, format, line, 1, "{s}", .{reason});
                }
            },
            .json => {
                if (st.next_doc >= st.docs.len) break;
                const doc = st.docs[st.next_doc];
                st.next_doc += 1;
                line = st.next_doc;
                if (doc != .object) {
                    if (st.rejects_path != null) {
                        try addReject(it, st, line, 1, "", "a unit is a JSON object");
                        continue;
                    }
                    return formatError(it, format, line, 1, "a unit is a JSON object", .{});
                }
                const fs_ = try it.t.alloc(data.Field, st.members.len);
                var jreason: []const u8 = "";
                var bad = false;
                for (st.members, fs_) |m, *slot| {
                    var found: ?data.Json = null;
                    for (doc.object) |mem| if (std.mem.eql(u8, mem.key, m.text)) {
                        found = mem.value;
                    };
                    const f = if (found) |j| jsonField(j, &jreason) else data.Field{ .text = "", .quoted = false };
                    slot.* = f orelse {
                        bad = true;
                        break;
                    };
                }
                if (bad) {
                    if (st.rejects_path != null) {
                        try addReject(it, st, line, 1, "", jreason);
                        continue;
                    }
                    return formatError(it, format, line, 1, "{s}", .{jreason});
                }
                fields = fs_;
            },
            .txt => {
                if (st.pos >= st.text.len) break;
                const end = std.mem.indexOfScalarPos(u8, st.text, st.pos, '\n') orelse st.text.len;
                var l = st.text[st.pos..end];
                if (l.len > 0 and l[l.len - 1] == '\r') l = l[0 .. l.len - 1];
                st.pos = @min(end + 1, st.text.len + 1);
                st.line_no += 1;
                line = st.line_no;
                raw = l;
                fields = try txtFields(it, l, st.widths);
            },
            .lines, .bytes => unreachable,
        }
        // the unit is made field by field, in the order of the class
        const obj = try it.newObject();
        var reason: []const u8 = "";
        var bad_col: usize = 0;
        var bad = false;
        for (st.members, 0..) |m, k| {
            const index = if (st.kind == .csv) st.cols[k] else k;
            const f = try normalized(it, st, fields[index]);
            const v = (try fromField(it, f, m, &reason)) orelse {
                bad = true;
                bad_col = index + 1;
                break;
            };
            try it.setField(obj, m.text, v);
        }
        if (bad) {
            if (st.rejects_path != null) {
                try addReject(it, st, line, bad_col, if (st.kind == .txt) raw else try joinFields(it, fields), reason);
                continue;
            }
            return formatError(it, format, line, bad_col, "{s}", .{reason});
        }
        obj.class = st.cls;
        return .{ .object = obj };
    }
    try finishStream(it, st);
    return null;
}

/// The fields of a refused row, joined with commas, for the rejects file.
fn joinFields(it: *Interp, fields: []const data.Field) Signal![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (fields, 0..) |f, i| {
        if (i > 0) try out.append(it.t, ',');
        try out.appendSlice(it.t, f.text);
    }
    return out.items;
}

/// The stream is done: write the rejects file (once) and close the source.
pub fn finishStream(it: *Interp, st: *Stream) Signal!void {
    if (st.finished) return;
    st.finished = true;
    const path = st.rejects_path orelse return;
    if (st.reject_count == 0) return; // nothing was refused: no file
    var buf: std.ArrayList(u8) = .empty;
    try buf.appendSlice(it.t, "source,line,column,text,reason\n");
    for (st.rejects.items) |r| {
        try csvCell(it, &buf, st.path, ',');
        try buf.append(it.t, ',');
        try buf.appendSlice(it.t, try std.fmt.allocPrint(it.t, "{d},{d},", .{ r.line, r.column }));
        try csvCell(it, &buf, r.text, ',');
        try buf.append(it.t, ',');
        try csvCell(it, &buf, r.reason, ',');
        try buf.append(it.t, '\n');
    }
    try writeFile(it, path, buf.items);
}

/// Append a CSV cell: in quotes only when it holds the separator, a quote or a line break; `""` is the empty string.
fn csvCell(it: *Interp, buf: *std.ArrayList(u8), text: []const u8, sep: u8) Signal!void {
    const needs = text.len == 0 or std.mem.indexOfAny(u8, text, "\"\r\n") != null or std.mem.indexOfScalar(u8, text, sep) != null;
    if (!needs) return buf.appendSlice(it.t, text);
    try buf.append(it.t, '"');
    for (text) |ch| {
        if (ch == '"') try buf.append(it.t, '"');
        try buf.append(it.t, ch);
    }
    try buf.append(it.t, '"');
}

/// `for x in stream do … done`: take the units one by one; leaving the loop finishes the stream.
pub fn forStream(it: *Interp, n: *const Node, o: *Object) Signal!void {
    const st = streamOf(it, o);
    const saved = try it.pushScope();
    defer it.leaveScope(saved);
    it.regionIn();
    defer it.regionOut();
    defer finishStream(it, st) catch {};
    var ran = false;
    while (try streamNext(it, st)) |unit| {
        ran = true;
        const im = it.scratch.mark();
        defer it.scratch.release(im);
        defer it.safe();
        try it.bindPattern(n.kids[0], unit);
        it.execBody(n.kids[2]) catch |e| switch (e) {
            error.Break => if (it.caught(n.text)) break else return e,
            error.Skip => if (it.caught(n.text)) continue else return e,
            else => return e,
        };
    }
    if (!ran) try it.execBlock(n.kids[3]);
    try it.execBlock(n.kids[4]);
}

/// Every unit of a stream, as a list in the scratch memory (a comprehension, `all()`).
pub fn drain(it: *Interp, o: *Object) Signal![]const Value {
    const st = streamOf(it, o);
    var out: std.ArrayList(Value) = .empty;
    while (try streamNext(it, st)) |unit| try out.append(it.t, unit);
    return out.items;
}

/// The methods of a stream object: `all()`, `count()`, `next()` and `close()`.
pub fn streamCall(it: *Interp, o: *Object, name: []const u8, args: []const *const Node) Signal!Value {
    const st = streamOf(it, o);
    if (args.len != 0) return it.fail("{s}() takes no argument", .{name});
    // a Stream adopts the protocol of a generator (data-language.md, generators): `next()` gives True and a new
    // `s.value`, or False at the end, when `s.done` becomes True (declarations.md#generators-level-5)
    if (std.mem.eql(u8, name, "next")) {
        if (try streamNext(it, st)) |rec| {
            try it.setField(o, "value", rec);
            return .{ .bool = true };
        }
        try it.setField(o, "done", .{ .bool = true });
        return .{ .bool = false };
    }
    if (std.mem.eql(u8, name, "close")) {
        try finishStream(it, st);
        try it.setField(o, "done", .{ .bool = true });
        return .nil;
    }
    if (std.mem.eql(u8, name, "all") or std.mem.eql(u8, name, "count")) {
        const items = try drain(it, o);
        if (std.mem.eql(u8, name, "count")) return .{ .int = @intCast(items.len) };
        return .{ .list = try it.newList(items, false) };
    }
    return it.fail("a Stream has no method '{s}'", .{name});
}

/// At the end of the run: write the rejects of the streams that were not finished.
pub fn closeStreams(it: *Interp) void {
    for (it.streams.items) |st| finishStream(it, st) catch {};
}

// ---- writers ----------------------------------------------------------------------------------

/// The text of a value in a CSV or TXT cell. `null` is empty; a Decimal keeps its scale.
fn cellText(it: *Interp, v: Value) Signal![]const u8 {
    return switch (v) {
        .nil => "",
        .list, .set, .map, .object, .func, .class, .module, .chan, .range, .domain, .typ => it.failWith(err_convert, "a {s} can not be written in a cell of a file", .{Interp.typeName(v)}),
        else => it.text(v),
    };
}

/// The names of the columns of a unit: the members of its class in order, else its fields.
fn columnNames(it: *Interp, first: Value) Signal![]const []const u8 {
    if (first != .object) return it.failWith(err_argument, "a file is written from records, not from a {s}", .{Interp.typeName(first)});
    var names: std.ArrayList([]const u8) = .empty;
    const o = first.object;
    if (o.class) |c| if (c.node) |node| if (node.tag == .class and node.kids.len > 0 and node.kids[0].kids.len > 0) {
        for (node.kids[0].kids) |m| try names.append(it.t, m.text);
        return names.items;
    };
    for (o.fields.items) |f| try names.append(it.t, f.name);
    return names.items;
}

fn rowValue(it: *Interp, row: Value, name: []const u8) Signal!Value {
    if (row != .object) return it.failWith(err_argument, "a file is written from records, not from a {s}", .{Interp.typeName(row)});
    return Interp.fieldOf(row.object, name) orelse .nil;
}

/// The code points of a text: widths of the TXT format count them, not the bytes.
fn codepoints(text: []const u8) usize {
    return std.unicode.utf8CountCodepoints(text) catch text.len;
}

/// `csv.write(path, rows, …)`, `json.write(path, rows)` and `txt.write(path, rows, widths: …)`.
fn writeRecords(it: *Interp, kind: Kind, args: []const *const Node) Signal!void {
    const what: []const u8 = switch (kind) {
        .csv => "csv.write",
        .json => "json.write",
        else => "txt.write",
    };
    if (args.len < 2) return it.failWith(err_argument, "{s} takes a path and the rows to write", .{what});
    const path = try it.text(try it.eval(args[0]));
    const source = try it.eval(args[1]);
    const opts = try options(it, args[2..], what);
    const items: []const Value = switch (source) {
        .list, .set => |l| l.elems(),
        .object => if (isStream(it, source)) try drain(it, source.object) else if (it.isGenerator(source)) try it.iterate(source) else &.{source},
        else => &.{source},
    };
    var buf: std.ArrayList(u8) = .empty;
    switch (kind) {
        .json => {
            const lines = std.mem.endsWith(u8, path, ".jsonl") or std.mem.endsWith(u8, path, ".ndjson") or try optFlag(it, opts, "lines", false);
            var w: Io.Writer.Allocating = .init(it.t);
            if (!lines) w.writer.writeAll("[\n") catch return error.OutOfMemory;
            for (items, 0..) |e, i| {
                try jsonValue(it, &w.writer, e);
                if (!lines and i + 1 < items.len) w.writer.writeByte(',') catch return error.OutOfMemory;
                w.writer.writeByte('\n') catch return error.OutOfMemory;
            }
            if (!lines) w.writer.writeAll("]\n") catch return error.OutOfMemory;
            try noMoreOptions(it, opts, what);
            try writeFile(it, path, w.written());
            return;
        },
        .csv => {
            const sep_text = try optText(it, opts, "sep") orelse ",";
            if (sep_text.len != 1) return it.failWith(err_argument, "csv.write: sep is one character", .{});
            const header = try optFlag(it, opts, "header", true);
            const bom = try optFlag(it, opts, "bom", false);
            const eol: []const u8 = if (std.mem.eql(u8, try optText(it, opts, "eol") orelse "lf", "crlf")) "\r\n" else "\n";
            try noMoreOptions(it, opts, what);
            if (bom) try buf.appendSlice(it.t, "\xEF\xBB\xBF");
            if (items.len == 0) return writeFile(it, path, buf.items);
            const names = try columnNames(it, items[0]);
            if (header) {
                for (names, 0..) |nm, i| {
                    if (i > 0) try buf.append(it.t, sep_text[0]);
                    try csvCell(it, &buf, nm, sep_text[0]);
                }
                try buf.appendSlice(it.t, eol);
            }
            for (items) |row| {
                for (names, 0..) |nm, i| {
                    if (i > 0) try buf.append(it.t, sep_text[0]);
                    const v = try rowValue(it, row, nm);
                    // null is an empty field; the empty string is two quotes
                    if (v == .nil) continue;
                    try csvCell(it, &buf, try cellText(it, v), sep_text[0]);
                }
                try buf.appendSlice(it.t, eol);
            }
        },
        .txt => {
            const widths = try widthList(it, opt(opts, "widths"), what);
            const cut = std.mem.eql(u8, try optText(it, opts, "overflow") orelse "error", "cut");
            try noMoreOptions(it, opts, what);
            if (items.len == 0) return writeFile(it, path, "");
            const names = try columnNames(it, items[0]);
            if (names.len != widths.len) return it.failWith(err_argument, "txt.write: {d} widths for {d} fields", .{ widths.len, names.len });
            for (items, 1..) |row, line| {
                for (names, widths, 0..) |nm, w, col| {
                    const v = try rowValue(it, row, nm);
                    var cell: []const u8 = if (v == .nil) "" else try cellText(it, v);
                    var n = codepoints(cell);
                    if (n > w) {
                        if (!cut) return formatError(it, "TXT", line, col + 1, "the value of '{s}' is {d} characters, the width is {d}", .{ nm, n, w });
                        // cut to the width, in code points
                        var end: usize = 0;
                        var k: usize = 0;
                        while (k < w) : (k += 1) end += std.unicode.utf8ByteSequenceLength(cell[end]) catch 1;
                        cell = cell[0..end];
                        n = w;
                    }
                    const right = switch (v) {
                        .int, .nat, .byte, .short, .huge, .real, .float, .dec => true,
                        else => false,
                    };
                    const pad = w - n;
                    if (right) try buf.appendNTimes(it.t, ' ', pad);
                    try buf.appendSlice(it.t, cell);
                    if (!right) try buf.appendNTimes(it.t, ' ', pad);
                }
                try buf.append(it.t, '\n');
            }
        },
        .lines, .bytes => unreachable,
    }
    try writeFile(it, path, buf.items);
}

/// Write a value as JSON text: `null`, numbers, strings, lists as arrays, objects and maps as objects. The keys
/// of a record come in the order of the members of its class (data-types.md, JSON).
pub fn jsonValue(it: *Interp, w: *Io.Writer, v: Value) Signal!void {
    switch (v) {
        .nil => w.writeAll("null") catch return error.OutOfMemory,
        .bool => |b| w.writeAll(if (b) "true" else "false") catch return error.OutOfMemory,
        .int, .nat, .byte, .short, .huge => |n| w.print("{d}", .{n}) catch return error.OutOfMemory,
        .real, .float => |x| w.print("{d}", .{x}) catch return error.OutOfMemory,
        .dec => |d| decimal.write(w, d) catch return error.OutOfMemory,
        .zone, .dtm => {
            w.writeByte('"') catch return error.OutOfMemory;
            var nb: [8]u8 = undefined;
            switch (v) {
                .zone => |id| w.writeAll(metalib.zoneName(id, &nb)) catch return error.OutOfMemory,
                .dtm => |d| timelib.writeDateTime(w, d) catch return error.OutOfMemory,
                else => unreachable,
            }
            w.writeByte('"') catch return error.OutOfMemory;
        },
        .date, .time, .dur => {
            w.writeByte('"') catch return error.OutOfMemory;
            switch (v) {
                .date => |days| evecm.calendar.writeDate(w, days) catch return error.OutOfMemory,
                .time => |us| evecm.calendar.writeTime(w, us) catch return error.OutOfMemory,
                .dur => |us| evecm.duration.write(w, us) catch return error.OutOfMemory,
                else => unreachable,
            }
            w.writeByte('"') catch return error.OutOfMemory;
        },
        .instant => |us| {
            w.writeByte('"') catch return error.OutOfMemory;
            instant.write(w, us) catch return error.OutOfMemory;
            w.writeByte('"') catch return error.OutOfMemory;
        },
        .str => |s| data.writeJsonString(w, s) catch return error.OutOfMemory,
        .list, .set => |l| {
            w.writeByte('[') catch return error.OutOfMemory;
            for (l.elems(), 0..) |e, i| {
                if (i > 0) w.writeByte(',') catch return error.OutOfMemory;
                try jsonValue(it, w, e);
            }
            w.writeByte(']') catch return error.OutOfMemory;
        },
        .object => |o| {
            if (it.isSecret(v)) return it.fail("json: a Secret is never written to a file", .{});
            w.writeByte('{') catch return error.OutOfMemory;
            var first = true;
            const names = try columnNames(it, v);
            for (names) |nm| {
                const fv = Interp.fieldOf(o, nm) orelse continue;
                if (!first) w.writeByte(',') catch return error.OutOfMemory;
                first = false;
                data.writeJsonString(w, nm) catch return error.OutOfMemory;
                w.writeByte(':') catch return error.OutOfMemory;
                try jsonValue(it, w, fv);
            }
            w.writeByte('}') catch return error.OutOfMemory;
        },
        .map => |m| {
            w.writeByte('{') catch return error.OutOfMemory;
            for (m.entries.items, 0..) |e, i| {
                if (i > 0) w.writeByte(',') catch return error.OutOfMemory;
                data.writeJsonString(w, try it.text(e.key)) catch return error.OutOfMemory;
                w.writeByte(':') catch return error.OutOfMemory;
                try jsonValue(it, w, e.val);
            }
            w.writeByte('}') catch return error.OutOfMemory;
        },
        else => return it.fail("json: a {s} can not be written as JSON", .{Interp.typeName(v)}),
    }
}

// ---- fs: files, folders and paths (data-language.md#files-and-paths) ---------------------------

fn pathArg(it: *Interp, args: []const *const Node, index: usize, what: []const u8) Signal![]const u8 {
    if (args.len <= index) return it.failWith(err_argument, "{s} needs a path", .{what});
    const v = try it.eval(args[index]);
    if (v != .str) return it.failWith(err_argument, "{s}: a path is a String", .{what});
    return v.str;
}

fn fsCall(it: *Interp, name: []const u8, args: []const *const Node) Signal!?Value {
    const eql = std.mem.eql;
    const io = it.io orelse return it.fail("fs: no input/output handle", .{});
    const cwd = Io.Dir.cwd();
    if (eql(u8, name, "write") or eql(u8, name, "append")) {
        if (args.len != 2) return it.failWith(err_argument, "fs.{s} takes a path and a text", .{name});
        const path = try pathArg(it, args, 0, "fs.write");
        const body = try it.text(try it.eval(args[1]));
        if (eql(u8, name, "write")) {
            try writeFile(it, path, body);
        } else {
            const old: []const u8 = cwd.readFileAlloc(io, path, it.t, .limited(1 << 30)) catch "";
            const joined = try std.mem.concat(it.t, u8, &.{ old, body });
            try writeFile(it, path, joined);
        }
        return .nil;
    }
    if (eql(u8, name, "write_bytes")) {
        // `Bytes` is a sequence of whole numbers from 0 to 255 (data-language.md#bytes)
        if (args.len != 2) return it.failWith(err_argument, "fs.write_bytes takes a path and the bytes", .{});
        const path = try pathArg(it, args, 0, "fs.write_bytes");
        const items = try it.eval(args[1]);
        if (items == .bytes) {
            try writeFile(it, path, items.bytes);
            return .nil;
        }
        if (items != .list) return it.failWith(err_argument, "fs.write_bytes: the bytes are a Bytes or a list of whole numbers from 0 to 255", .{});
        var raw: std.ArrayList(u8) = .empty;
        for (items.list.elems()) |e| {
            if (!Interp.isInt(e) or Interp.intOf(e) < 0 or Interp.intOf(e) > 255) return it.failWith(err_argument, "fs.write_bytes: a byte is a whole number from 0 to 255", .{});
            try raw.append(it.t, @intCast(Interp.intOf(e)));
        }
        try writeFile(it, path, raw.items);
        return .nil;
    }
    if (eql(u8, name, "read_bytes!")) {
        const path = try pathArg(it, args, 0, "fs.read_bytes!");
        const bytes = try readFile(it, path);
        return try bytesfn.newBytes(it, bytes);
    }
    if (eql(u8, name, "read!")) {
        const path = try pathArg(it, args, 0, "fs.read!");
        const text = try decodeBytes(it, try readFile(it, path), null, "error", "text", path);
        return try it.newStr(text);
    }
    if (eql(u8, name, "lines!")) return try openLines(it, args);
    if (eql(u8, name, "exists!")) {
        const path = try pathArg(it, args, 0, "fs.exists!");
        return .{ .bool = if (cwd.access(io, path, .{})) |_| true else |_| false };
    }
    if (eql(u8, name, "size!")) {
        const path = try pathArg(it, args, 0, "fs.size!");
        const stat = cwd.statFile(io, path, .{}) catch return it.failWith(err_file, "cannot read the size of {s}: the file does not exist", .{path});
        return .{ .int = @intCast(stat.size) };
    }
    if (eql(u8, name, "remove")) {
        const path = try pathArg(it, args, 0, "fs.remove");
        cwd.deleteFile(io, path) catch |e| switch (e) {
            error.FileNotFound => return it.failWith(err_file, "cannot remove {s}: the file does not exist", .{path}),
            else => return it.failWith(err_io, "cannot remove {s}: {s}", .{ path, @errorName(e) }),
        };
        return .nil;
    }
    if (eql(u8, name, "make_dir")) {
        const path = try pathArg(it, args, 0, "fs.make_dir");
        cwd.createDirPath(io, path) catch |e| return it.failWith(err_io, "cannot make the folder {s}: {s}", .{ path, @errorName(e) });
        return .nil;
    }
    if (eql(u8, name, "move")) {
        const from = try pathArg(it, args, 0, "fs.move");
        const to = try pathArg(it, args, 1, "fs.move");
        if (std.fs.path.dirname(to)) |dir| cwd.createDirPath(io, dir) catch {};
        Io.Dir.rename(cwd, from, cwd, to, io) catch |e| switch (e) {
            error.FileNotFound => return it.failWith(err_file, "cannot move {s}: the file does not exist", .{from}),
            else => return it.failWith(err_io, "cannot move {s}: {s}", .{ from, @errorName(e) }),
        };
        return .nil;
    }
    if (eql(u8, name, "glob!")) {
        const pattern = try pathArg(it, args, 0, "fs.glob!");
        const out = try it.newList(&.{}, false);
        for (try globlib.glob(it, pattern)) |n| try it.listAppend(out, try it.newStr(n));
        return .{ .list = out };
    }
    if (eql(u8, name, "list!")) {
        const path = try pathArg(it, args, 0, "fs.list!");
        var dir = cwd.openDir(io, path, .{ .iterate = true }) catch |e| switch (e) {
            error.FileNotFound => return it.failWith(err_file, "cannot list {s}: the folder does not exist", .{path}),
            else => return it.failWith(err_io, "cannot list {s}: {s}", .{ path, @errorName(e) }),
        };
        defer dir.close(io);
        var names: std.ArrayList([]const u8) = .empty;
        var iter = dir.iterate();
        while (iter.next(io) catch null) |entry| try names.append(it.t, try it.t.dupe(u8, entry.name));
        std.mem.sort([]const u8, names.items, {}, struct {
            fn less(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.order(u8, a, b) == .lt;
            }
        }.less);
        const out = try it.newList(&.{}, false);
        for (names.items) |n| try it.listAppend(out, try it.newStr(n));
        return .{ .list = out };
    }
    if (eql(u8, name, "join")) {
        const a = try pathArg(it, args, 0, "fs.join");
        const b = try pathArg(it, args, 1, "fs.join");
        return try it.newStr(try joinPath(it, a, b));
    }
    if (eql(u8, name, "name") or eql(u8, name, "parent") or eql(u8, name, "extension")) {
        const p = try pathArg(it, args, 0, "fs.name");
        const cut = std.mem.lastIndexOfAny(u8, p, "/\\");
        const base = if (cut) |i| p[i + 1 ..] else p;
        if (eql(u8, name, "name")) return try it.newStr(base);
        if (eql(u8, name, "parent")) return try it.newStr(if (cut) |i| p[0..i] else "");
        const dot = std.mem.lastIndexOfScalar(u8, base, '.');
        return try it.newStr(if (dot) |i| base[i..] else "");
    }
    return null;
}

/// `a / b` of two paths: the two joined with one `/`.
pub fn joinPath(it: *Interp, a: []const u8, b: []const u8) Signal![]const u8 {
    if (a.len == 0) return b;
    if (b.len > 0 and (b[0] == '/' or (b.len > 1 and b[1] == ':'))) return b; // an absolute path replaces
    const sep = if (a[a.len - 1] == '/' or a[a.len - 1] == '\\') "" else "/";
    return std.fmt.allocPrint(it.t, "{s}{s}{s}", .{ a, sep, b });
}
