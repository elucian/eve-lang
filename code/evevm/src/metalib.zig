//! @eve-module metalib: the meta database (reference data embedded in eve.exe) and the natives of the library `zone`
//! @spec spec/library/meta.md
//! @feature F-LIB-06
//! @decision D-222
//! @tests test/level5/e129_meta_zone, test/level5/e130_meta_zone_table
//! lib/meta/meta.db is a SQLite file (tools/meta/build_meta.py) embedded as it is and opened read only without a copy on first use; `EVE_META_DB`, a path, replaces it with a newer file. Zones are read once into memory (evecm zone.zig); a lookup is a binary search.
const std = @import("std");
const Io = std.Io;
const ast = @import("evecm").ast;
const zonelib = @import("evecm").zone;
const interp = @import("interp.zig");
const sqlite = @import("db/sqlite.zig");

const Node = ast.Node;
const Interp = interp.Interp;
const Value = interp.Value;
const Signal = interp.Signal;
const err_argument = interp.err_argument;

// The database stays on disk (D-225): `EVE_META_DB`, else `lib/meta/meta.db` in the `lib` folder beside the program.
// At optimization level 5 and above a background thread reads it when the run starts (D-226); a first use before the end waits for it.
const file_name = "meta/meta.db";

/// The file read by the background thread: its bytes, or the message of the failure.
var loader: ?std.Thread = null;
var loaded: ?[]const u8 = null;
var load_failure: ?[]const u8 = null;

const alloc = std.heap.page_allocator;

// @invariant `state` is read and written only with `lock` held; after the first open `db` is a read only connection that is never closed
var lock: std.atomic.Value(bool) = .init(false);
var db: ?sqlite.Db = null;
var zones: std.StringHashMapUnmanaged(*Entry) = .empty;

const Entry = struct { zone: zonelib.Zone, name: []const u8, canonical: []const u8, id: u32 = 0 };

// The zones that were asked for have a number, the id of the value `Zone`: 0 is `Z` (UTC), 1 and up are the entries of `slots`
// (id - 1), and a number with the top bit set is a fixed offset (`+03:00`), not stored anywhere.
// @invariant a slot is written once, with the lock held, before its id is given to anybody; reads of a slot need no lock
var slots: [2048]?*Entry = @splat(null);
var slot_count: u32 = 0;

fn register(e: *Entry) u32 {
    slots[slot_count] = e;
    slot_count += 1;
    return slot_count;
}

pub const fixed_bit: u32 = 0x8000_0000;

/// The id of the fixed offset `off` seconds from UTC (-18 to +18 hours); 0 for no offset.
pub fn fixedId(off: i32) u32 {
    return if (off == 0) 0 else fixed_bit | @as(u32, @intCast(off + 65536));
}

pub fn isFixed(id: u32) bool {
    return id == 0 or id & fixed_bit != 0;
}

pub fn fixedOffset(id: u32) i32 {
    return if (id == 0) 0 else @as(i32, @intCast(id & 0x7fff_ffff)) - 65536;
}

/// The local time of a zone value at the UTC instant `t` (seconds). A fixed offset has no abbreviation: it is "".
// @perf hot
pub fn localAt(id: u32, t: i64) zonelib.Local {
    if (isFixed(id)) return .{ .utoff = fixedOffset(id), .isdst = false, .abbr = "" };
    return zonelib.lookup(&slots[id - 1].?.zone, t);
}

/// The instants of a local time (seconds since 1970-01-01T00:00:00 local) in a zone value.
pub fn resolveLocal(id: u32, local: i64) zonelib.Resolve {
    if (isFixed(id)) return .{ .one = local - fixedOffset(id) };
    return zonelib.resolveLocal(&slots[id - 1].?.zone, local);
}

/// The text of a zone value: the name of a region, `Z`, or `+03:00`; fixed offsets are written into `buf`.
pub fn zoneName(id: u32, buf: *[8]u8) []const u8 {
    if (id == 0) return "Z";
    if (!isFixed(id)) return slots[id - 1].?.name;
    const off = fixedOffset(id);
    const a: u32 = @abs(off);
    return std.fmt.bufPrint(buf, "{c}{d:0>2}:{d:0>2}", .{ @as(u8, if (off < 0) '-' else '+'), a / 3600, a % 3600 / 60 }) catch "+??:??";
}

/// The offset in a text `Z`, `+03`, `+0330`, `+03:30`, `-05:00`, in seconds; null when it is not one or is outside 18 hours.
pub fn parseOffset(text: []const u8) ?i32 {
    if (std.mem.eql(u8, text, "Z")) return 0;
    if (text.len < 3 or (text[0] != '+' and text[0] != '-')) return null;
    const sign: i32 = if (text[0] == '-') -1 else 1;
    var h: i32 = 0;
    var m: i32 = 0;
    for (text[1..3]) |c| {
        if (!std.ascii.isDigit(c)) return null;
        h = h * 10 + (c - '0');
    }
    var rest = text[3..];
    if (rest.len > 0 and rest[0] == ':') rest = rest[1..];
    if (rest.len != 0) {
        if (rest.len != 2) return null;
        for (rest) |c| {
            if (!std.ascii.isDigit(c)) return null;
            m = m * 10 + (c - '0');
        }
    }
    if (h > 18 or m > 59 or (h == 18 and m > 0)) return null;
    return sign * (h * 3600 + m * 60);
}

/// The id of the zone a text names: `Z`, an offset, or a name of the database (a link is a zone of its own with the data of its target); null when there is none.
pub fn zoneIdOf(it: *Interp, text: []const u8) Signal!?u32 {
    if (parseOffset(text)) |off| return fixedId(off);
    acquire();
    defer release();
    const e = (try load(it, text)) orelse return null;
    return e.id;
}

fn acquire() void {
    while (lock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) std.atomic.spinLoopHint();
}

fn release() void {
    lock.store(false, .release);
}

var image_cache: ?[]const u8 = null;

// @eve-impl the meta database is read from disk: `EVE_META_DB`, else `<prefix>/lib/meta/meta.db` beside the program, else `lib/meta/meta.db` of the working folder (D-225)
// @spec spec/library/meta.md#the-file
// @feature F-LIB-06
// @test test/level5/e156_optimization_zone
/// The path of the meta database file, as the first candidate that exists; null when none does.
fn findFile(io: Io) ?[]const u8 {
    if (std.c.getenv("EVE_META_DB")) |p| return std.mem.span(p);
    const exe_dir = std.process.executableDirPathAlloc(io, alloc) catch return null;
    const beside = std.fs.path.join(alloc, &.{ exe_dir, "..", "lib", file_name }) catch return null;
    if (Io.Dir.cwd().access(io, beside, .{})) |_| return beside else |_| {}
    return "lib/" ++ file_name;
}

/// Reads the file; the result is its bytes, or the message of the failure (a Git LFS pointer or a missing file).
fn readImage(io: Io) struct { bytes: ?[]const u8, failure: ?[]const u8 } {
    const path = findFile(io) orelse return .{ .bytes = null, .failure = "meta database not found: lib/meta/meta.db is missing (see spec/library/meta.md)" };
    const bytes = Io.Dir.cwd().readFileAlloc(io, path, alloc, .limited(1 << 30)) catch |e|
        return .{ .bytes = null, .failure = std.fmt.allocPrint(alloc, "meta database: cannot read {s}: {s}", .{ path, @errorName(e) }) catch "meta database: cannot read the file" };
    if (std.mem.startsWith(u8, bytes, "version https://git-lfs")) {
        return .{ .bytes = null, .failure = "lib/meta/meta.db is a Git LFS pointer, not the database: run `git lfs pull` (D-222)" };
    }
    return .{ .bytes = bytes, .failure = null };
}

fn loadWorker(io: Io) void {
    const got = readImage(io);
    loaded = got.bytes;
    load_failure = got.failure;
}

/// Starts the background read of the meta database when the optimization level is 5 or more (D-226); below 5 the file is read at the first use.
pub fn prepare(io: Io, level: u8) void {
    if (level < 5 or loader != null or image_cache != null) return;
    loader = std.Thread.spawn(.{}, loadWorker, .{io}) catch null;
}

/// The bytes of the meta database: the background read when it was started (waited for here), else the file read now. Kept for the life of the process; a connection to it must not outlive these bytes, which never move.
pub fn image(it: *Interp) Signal![]const u8 {
    if (image_cache) |b| return b;
    if (loader) |t| {
        t.join();
        loader = null;
    } else {
        const io = it.io orelse return it.fail("meta: no input/output handle", .{});
        const got = readImage(io);
        loaded = got.bytes;
        load_failure = got.failure;
    }
    if (loaded) |b| {
        image_cache = b;
        return b;
    }
    return it.failWith(interp.err_file, "{s}", .{load_failure orelse "meta database: unknown failure"});
}

/// The connection of the library (zones, `meta.info`), opened on first use; the caller holds the lock.
fn open(it: *Interp) Signal!*sqlite.Db {
    if (db) |*d| return d;
    db = sqlite.Db.openImage(try image(it)) catch return it.failWith(interp.err_io, "meta: the meta database can not be opened", .{});
    return &db.?;
}

fn dup(s: []const u8) std.mem.Allocator.Error![]const u8 {
    return alloc.dupe(u8, s);
}

/// Read one zone (and the zone a link points to) into memory; the caller holds the lock.
fn load(it: *Interp, name: []const u8) Signal!?*Entry {
    if (zones.get(name)) |e| return e;
    const d = try open(it);
    var q = d.prepare("select id, link_of, rule, (select name from zone c where c.id = coalesce(z.link_of, z.id)) from zone z where name = ?") catch return it.failWith(interp.err_io, "meta: bad query", .{});
    defer q.finalize();
    q.bindText(1, name) catch return error.OutOfMemory;
    if (!(q.step() catch return it.failWith(interp.err_io, "meta: query failed", .{}))) return null;
    const own_id = q.columnInt(0);
    const canon_name = try dup(q.columnText(3));
    const key = try dup(name);
    var zid = own_id;
    if (q.columnKind(1) != .null) zid = q.columnInt(1);
    // a link shares the data of its zone
    if (!std.mem.eql(u8, canon_name, name)) if (zones.get(canon_name)) |target| {
        const e = try alloc.create(Entry);
        e.* = .{ .zone = target.zone, .name = key, .canonical = target.canonical };
        e.id = register(e);
        try zones.put(alloc, key, e);
        return e;
    };
    const rule_text = try dup(q.columnText(2));
    var types: std.ArrayList(zonelib.Type) = .empty;
    var tq = d.prepare("select utoff, isdst, abbr from zone_type where zone = ? order by idx") catch return it.failWith(interp.err_io, "meta: bad query", .{});
    defer tq.finalize();
    tq.bindInt(1, zid) catch return error.OutOfMemory;
    while (tq.step() catch return it.failWith(interp.err_io, "meta: query failed", .{})) {
        try types.append(alloc, .{ .utoff = @intCast(tq.columnInt(0)), .isdst = tq.columnInt(1) != 0, .abbr = try dup(tq.columnText(2)) });
    }
    var at: std.ArrayList(i64) = .empty;
    var idx: std.ArrayList(u8) = .empty;
    var rq = d.prepare("select at, idx from zone_transition where zone = ? order by at") catch return it.failWith(interp.err_io, "meta: bad query", .{});
    defer rq.finalize();
    rq.bindInt(1, zid) catch return error.OutOfMemory;
    while (rq.step() catch return it.failWith(interp.err_io, "meta: query failed", .{})) {
        try at.append(alloc, rq.columnInt(0));
        try idx.append(alloc, @intCast(rq.columnInt(1)));
    }
    if (types.items.len == 0) return it.failWith(interp.err_io, "meta: the zone {s} has no types", .{name});
    // the rule of a link is the rule of its zone: read it when the link came first
    var rule = zonelib.parseRule(rule_text);
    if (rule == null and !std.mem.eql(u8, canon_name, name)) {
        var cq = d.prepare("select rule from zone where id = ?") catch return it.failWith(interp.err_io, "meta: bad query", .{});
        defer cq.finalize();
        cq.bindInt(1, zid) catch return error.OutOfMemory;
        if (cq.step() catch false) rule = zonelib.parseRule(try dup(cq.columnText(0)));
    }
    const e = try alloc.create(Entry);
    e.* = .{ .zone = .{ .types = try types.toOwnedSlice(alloc), .at = try at.toOwnedSlice(alloc), .idx = try idx.toOwnedSlice(alloc), .rule = rule }, .name = key, .canonical = canon_name };
    e.id = register(e);
    try zones.put(alloc, key, e);
    return e;
}

const Fn = enum { exists, canonical, offset, abbreviation, is_dst, names };

fn zoneArg(it: *Interp, args: []const Value, what: []const u8) Signal![]const u8 {
    if (args.len < 1 or args[0] != .str) return it.failWith(err_argument, "zone.{s}: argument 1 is the name of a zone, a String", .{what});
    return args[0].str;
}

fn instantArg(it: *Interp, args: []const Value, what: []const u8) Signal!i64 {
    if (args.len >= 2 and args[1] == .dtm) return @divFloor(args[1].dtm.us, 1_000_000);
    if (args.len < 2 or args[1] != .instant) return it.failWith(err_argument, "zone.{s}: argument 2 is an Instant or a DateTime", .{what});
    return @divFloor(args[1].instant, 1_000_000);
}

fn compute(it: *Interp, f: Fn, args: []const Value) Signal!?Value {
    const n = @tagName(f);
    switch (f) {
        .names => {
            acquire();
            defer release();
            const d = try open(it);
            var q = d.prepare("select name from zone order by name") catch return it.failWith(interp.err_io, "meta: bad query", .{});
            defer q.finalize();
            var out: std.ArrayList(Value) = .empty;
            defer out.deinit(it.a);
            while (q.step() catch return it.failWith(interp.err_io, "meta: query failed", .{})) try out.append(it.a, try it.newStr(q.columnText(0)));
            return .{ .list = try it.newList(out.items, false) };
        },
        else => {},
    }
    if (args.len >= 1 and args[0] == .zone) {
        // a Zone value: no name to look up (the data of a region is already in memory)
        const id = args[0].zone;
        var nb: [8]u8 = undefined;
        switch (f) {
            .exists => return .{ .bool = true },
            .canonical => return try it.newStr(if (isFixed(id)) zoneName(id, &nb) else slots[id - 1].?.canonical),
            .offset, .abbreviation, .is_dst => {
                const l = localAt(id, try instantArg(it, args, n));
                return switch (f) {
                    .offset => .{ .dur = @as(i64, l.utoff) * 1_000_000 },
                    .abbreviation => try it.newStr(if (l.abbr.len > 0) l.abbr else zoneName(id, &nb)),
                    else => .{ .bool = l.isdst },
                };
            },
            .names => unreachable,
        }
    }
    const name = try zoneArg(it, args, n);
    acquire();
    defer release();
    const entry = (try load(it, name)) orelse {
        if (f == .exists) return .{ .bool = false };
        return it.failWith(err_argument, "zone.{s}: '{s}' is not a time zone of the IANA database", .{ n, name });
    };
    switch (f) {
        .exists => return .{ .bool = true },
        .canonical => return try it.newStr(entry.canonical),
        .offset, .abbreviation, .is_dst => {
            // the lock is held for the lookup only; the zone data never changes
            const l = zonelib.lookup(&entry.zone, try instantArg(it, args, n));
            return switch (f) {
                .offset => .{ .dur = @as(i64, l.utoff) * 1_000_000 },
                .abbreviation => try it.newStr(l.abbr),
                else => .{ .bool = l.isdst },
            };
        },
        .names => unreachable,
    }
}

pub fn fastId(name: []const u8) ?u16 {
    const f = std.meta.stringToEnum(Fn, name) orelse return null;
    return @intFromEnum(f);
}

// @perf hot
pub fn fastCall(it: *Interp, id: u16, args: []const Value) Signal!Value {
    return (try compute(it, @enumFromInt(id), args)) orelse .nil;
}

/// The entry of `dlib.natives`: evaluates the argument nodes, then computes.
pub fn zoneModule(it: *Interp, name: []const u8, _: []const *const Node, arg_nodes: []const *const Node) Signal!?Value {
    const f = std.meta.stringToEnum(Fn, name) orelse return null;
    var buf: [4]Value = undefined;
    if (arg_nodes.len > buf.len) return it.failWith(err_argument, "zone.{s}: too many arguments", .{name});
    for (arg_nodes, 0..) |nd, i| buf[i] = try it.eval(nd);
    return compute(it, f, buf[0..arg_nodes.len]);
}

// @eve-fn meta.info
// @spec spec/library/meta.md#metainfo
/// The entry of the module `meta`: `meta.info(name)` is a row of the table `meta_info` (the schema, the releases of the sources).
pub fn metaModule(it: *Interp, name: []const u8, _: []const *const Node, arg_nodes: []const *const Node) Signal!?Value {
    if (!std.mem.eql(u8, name, "info")) return null;
    if (arg_nodes.len != 1) return it.failWith(err_argument, "meta.info takes the name of an entry", .{});
    const key = try it.eval(arg_nodes[0]);
    if (key != .str) return it.failWith(err_argument, "meta.info: argument 1 is a String", .{});
    acquire();
    defer release();
    const d = try open(it);
    var q = d.prepare("select value from meta_info where name = ?") catch return it.failWith(interp.err_io, "meta: bad query", .{});
    defer q.finalize();
    q.bindText(1, key.str) catch return error.OutOfMemory;
    if (!(q.step() catch return it.failWith(interp.err_io, "meta: query failed", .{}))) return it.failWith(interp.err_key, "meta.info: there is no entry '{s}'", .{key.str});
    return try it.newStr(q.columnText(0));
}

test "spec: meta.md#the-file the database file opens and holds the zones" {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "lib/meta/meta.db", std.testing.allocator, .limited(1 << 30));
    defer std.testing.allocator.free(bytes);
    var d = try sqlite.Db.openImage(bytes);
    defer d.close();
    var q = try d.prepare("select count(*), (select value from meta_info where name = 'tzdata') from zone");
    defer q.finalize();
    try std.testing.expect(try q.step());
    try std.testing.expectEqual(@as(i64, 598), q.columnInt(0));
    try std.testing.expect(q.columnText(1).len >= 5);
}

test "spec: meta.md#zone a link shares the data of its zone" {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "lib/meta/meta.db", std.testing.allocator, .limited(1 << 30));
    defer std.testing.allocator.free(bytes);
    var d = try sqlite.Db.openImage(bytes);
    defer d.close();
    var q = try d.prepare("select count(*) from zone l join zone z on z.id = l.link_of where l.name = 'Asia/Calcutta' and z.name = 'Asia/Kolkata'");
    defer q.finalize();
    try std.testing.expect(try q.step());
    try std.testing.expectEqual(@as(i64, 1), q.columnInt(0));
}
