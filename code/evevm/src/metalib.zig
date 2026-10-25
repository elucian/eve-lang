//! @eve-module metalib: the meta database connection (reference data read from disk, D-225); the library `zone` and `meta` are Eve code (D-229)
//! @spec spec/library/meta.md
//! @feature F-LIB-06
//! @decision D-222
//! @tests test/level5/e129_meta_zone, test/level5/e130_meta_zone_table, test/level5/e162_zone_spans
//! lib/meta/meta.db is a SQLite file (tools/meta/build_meta.py) read from disk: the tables a run needs are copied into a memory connection (D-226); `EVE_META_DB`, a path, replaces it with a newer file. Zones are read once into memory (evecm zone.zig); a lookup is a binary search.
const std = @import("std");
const Io = std.Io;
const ast = @import("evecm").ast;
const interp = @import("interp.zig");
const sqlite = @import("db/sqlite.zig");
const meta_need = @import("evecm").meta_need;
const zonespans = @import("zonespans.zig");

const Node = ast.Node;
const Interp = interp.Interp;
const Value = interp.Value;
const Signal = interp.Signal;
const err_argument = interp.err_argument;

// The database stays on disk (D-225): `EVE_META_DB`, else `lib/meta/meta.db` in the `lib` folder beside the program.
// A run copies only the tables it needs (D-226, meta_need.zig) from the file into a connection in memory: at optimization
// level 5 and above a background thread makes that copy when the run starts, and a use that comes before its end waits for it;
// below 5, and for a table that was not copied, the copy is made at the first use.
const file_name = "meta/meta.db";

/// The tables of the zone core and of `meta.info`: what every zone lookup reads.
const zone_core: meta_need.Need = .{ .mask = meta_need.Need.all.mask & ~(@as(u16, 1) << 3) & ~(@as(u16, 1) << 4) & ~(@as(u16, 1) << 6) & ~(@as(u16, 1) << 7) & ~(@as(u16, 1) << 8) };

/// The copy made by the background thread: its connection, the tables in it, or the message of its failure.
var prepared: ?sqlite.Db = null;
var prepared_mask: u16 = 0;
var prepared_failure: ?[]const u8 = null;
var loader: ?std.Thread = null;
/// The file the copies come from, found once.
var file_path: ?[]const u8 = null;

const alloc = std.heap.page_allocator;

// @invariant `db`, `loaded_mask` and `file_path` are read and written only with `lock` held; the connection is never closed, and the thread's copy is taken over under the lock after its join
var lock: std.atomic.Value(bool) = .init(false);
var db: ?sqlite.Db = null;
var loaded_mask: u16 = 0;
var zones: std.StringHashMapUnmanaged(*Entry) = .empty;

/// `db_id` is the id of the name in the spans (zonespans.zig): 0 until asked, `no_db_id` when the spans have no such name.
const Entry = struct { name: []const u8, id: u32 = 0, db_id: u32 = 0 };
const no_db_id: u32 = std.math.maxInt(u32);

/// The local time of a zone at an instant, and the instants of a local time: the answers of the zone module (D-229).
pub const Local = struct { utoff: i32, isdst: bool, abbr: []const u8 };
pub const Resolve = union(enum) {
    one: i64,
    two: struct { first: i64, second: i64 },
    gap: struct { before: i32, after: i32 },
};

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

/// The functions of the zone module found for the run `owner`: a module lives to the end of its run, so the lookup by name is made once per thread and run.
// @invariant `owner` is the root interpreter of the run; a function value stays valid while the run lives (the module scope is pinned)
const ZoneFns = struct { owner: ?*const Interp = null, local_at: ?*interp.Func = null, resolve_local: ?*interp.Func = null, exists: ?*interp.Func = null };
threadlocal var zone_fns: ZoneFns = .{};

fn zoneFn(it: *Interp, name: []const u8) Signal!*interp.Func {
    const owner = it.base();
    if (zone_fns.owner != owner) zone_fns = .{ .owner = owner };
    const slot: *?*interp.Func = if (std.mem.eql(u8, name, "local_at")) &zone_fns.local_at else if (std.mem.eql(u8, name, "resolve_local")) &zone_fns.resolve_local else &zone_fns.exists;
    if (slot.*) |f| return f;
    const known = it.modules orelse return it.fail("the time zones: no module table", .{});
    const node = known.get("lib/meta|zone") orelse return it.fail("the time zones need the module lib/meta/zone (a hidden import, D-230)", .{});
    const m = try it.instantiate(node);
    const f = try it.moduleMember(m, name);
    if (f != .func) return it.fail("zone.{s} is not a function", .{name});
    slot.* = f.func;
    return f.func;
}

/// Calls a function of the zone module (`lib/meta/zone.eve`, a hidden import when the script uses zones, D-230) with the arguments.
fn zoneCall(it: *Interp, name: []const u8, args: []const Value) Signal!Value {
    const f = try zoneFn(it, name);
    var call_args: [4]interp.Arg = undefined;
    for (args, 0..) |a, k| call_args[k] = .{ .value = a };
    return it.invokeWith(f, null, call_args[0..args.len]);
}

// The spans of the zones, read once from the meta database (zonespans.zig, design/design-zone-speed.md): a lookup that they answer does not call Eve.
// @invariant `span_tables` is written once, with the lock held, after the tables are complete; `span_state` is 0 (not tried), 1 (loaded) or 2 (no spans: every lookup goes to the Eve code)
var span_tables: ?*const zonespans.Tables = null;
var span_state: std.atomic.Value(u8) = .init(0);

/// The spans, loaded at the first lookup; null when they can not be used (`EVE_ZONE_SLOW` set, or the tables are missing): then the Eve code answers.
// @feature F-LIB-06
// @decision D-229
// @see code/evevm/src/zonespans.zig:Tables
fn spans(it: *Interp) ?*const zonespans.Tables {
    switch (span_state.load(.acquire)) {
        1 => return span_tables,
        2 => return null,
        else => {},
    }
    acquire();
    defer release();
    if (span_state.load(.acquire) != 0) return span_tables;
    var loaded: ?*const zonespans.Tables = null;
    if (std.c.getenv("EVE_ZONE_SLOW") == null) {
        loaded = loadSpans(it);
    }
    span_tables = loaded;
    span_state.store(if (loaded == null) 2 else 1, .release);
    return loaded;
}

/// Reads the spans straight from the file with a connection of their own: the copy of the tables into memory (for the SQL door and the Eve path) is not needed for them. The caller holds the lock.
fn loadSpans(it: *Interp) ?*const zonespans.Tables {
    const io = it.io orelse return null;
    if (file_path == null) {
        const path = findFile(io) orelse return null;
        if (checkFile(io, path) != null) return null;
        file_path = path;
    }
    const path = std.fmt.allocPrintSentinel(alloc, "{s}", .{file_path.?}, 0) catch return null;
    defer alloc.free(path);
    var conn = sqlite.Db.open(path) catch return null;
    defer conn.close();
    return zonespans.load(alloc, &conn) catch null;
}

/// The IANA zone that CLDR gives to a Windows zone name (`FLE Standard Time`, the key of the registry), for the default territory 001; null when there is none.
// @spec spec/library/time.md#zones
// @feature F-LIB-06
// @decision D-229
pub fn windowsRegion(it: *Interp, key: []const u8) ?[]const u8 {
    acquire();
    defer release();
    const io = it.io orelse return null;
    if (file_path == null) {
        const path = findFile(io) orelse return null;
        if (checkFile(io, path) != null) return null;
        file_path = path;
    }
    const path = std.fmt.allocPrintSentinel(alloc, "{s}", .{file_path.?}, 0) catch return null;
    defer alloc.free(path);
    var conn = sqlite.Db.open(path) catch return null;
    defer conn.close();
    var q = conn.prepare("SELECT zone FROM windows_zone WHERE name = ?1 AND territory = '001'") catch return null;
    defer q.finalize();
    q.bindText(1, key) catch return null;
    if (!(q.step() catch return null)) return null;
    return it.t.dupe(u8, q.columnText(0)) catch null;
}

/// The id of the entry in the spans; null when there are none for it.
fn spanId(t: *const zonespans.Tables, e: *Entry) ?u32 {
    if (e.db_id == 0) e.db_id = t.idOf(e.name) orelse no_db_id;
    return if (e.db_id == no_db_id) null else e.db_id;
}

/// The local time of a zone value at the UTC instant `t` (seconds). A fixed offset has no abbreviation: it is "".
// @perf hot
// @spec spec/library/meta.md#zone
// @feature F-LIB-06
// @decision D-229
pub fn localAt(it: *Interp, id: u32, t: i64) Signal!Local {
    if (isFixed(id)) return .{ .utoff = fixedOffset(id), .isdst = false, .abbr = "" };
    const e = slots[id - 1].?;
    if (spans(it)) |tables| if (spanId(tables, e)) |zid| if (tables.local(zid, t)) |l| return .{ .utoff = l.utoff, .isdst = l.isdst, .abbr = l.abbr };
    const got = try zoneCall(it, "local_at", &.{ try it.newStr(e.name), .{ .int = t } });
    const items = got.list.elems();
    return .{ .utoff = @intCast(Interp.intOf(items[0])), .isdst = items[1].bool, .abbr = try it.text(items[2]) };
}

/// The instants of a local time (seconds since 1970-01-01T00:00:00 local) in a zone value.
pub fn resolveLocal(it: *Interp, id: u32, local: i64) Signal!Resolve {
    if (isFixed(id)) return .{ .one = local - fixedOffset(id) };
    const e = slots[id - 1].?;
    if (spans(it)) |tables| if (spanId(tables, e)) |zid| if (tables.resolve(zid, local)) |r| return switch (r) {
        .one => |v| .{ .one = v },
        .two => |v| .{ .two = .{ .first = v.first, .second = v.second } },
        .gap => |v| .{ .gap = .{ .before = v.before, .after = v.after } },
    };
    const got = try zoneCall(it, "resolve_local", &.{ try it.newStr(e.name), .{ .int = local } });
    const items = got.list.elems();
    return switch (Interp.intOf(items[0])) {
        1 => .{ .one = Interp.intOf(items[1]) },
        2 => .{ .two = .{ .first = Interp.intOf(items[1]), .second = Interp.intOf(items[2]) } },
        else => .{ .gap = .{ .before = @intCast(Interp.intOf(items[1])), .after = @intCast(Interp.intOf(items[2])) } },
    };
}

/// The externals of `lib/meta/zone.eve` that read the spans: the answer is null when the spans have none (a fixed offset written as a name, a name that is not in the database, an instant beyond the horizon), and the Eve code goes on.
const SpanFn = enum { span_offset, span_dst, span_abbr };

pub fn fastId(name: []const u8) ?u16 {
    const f = std.meta.stringToEnum(SpanFn, name) orelse return null;
    return @intFromEnum(f);
}

// @perf hot
// @eve-impl zone.span_offset, zone.span_dst, zone.span_abbr (arguments: a zone name or a Zone value, an Instant or a DateTime)
pub fn fastCall(it: *Interp, id: u16, args: []const Value) Signal!Value {
    const tables = spans(it) orelse return .nil;
    const zid = switch (args[0]) {
        .str => |name| tables.idOf(name) orelse return .nil,
        .zone => |z| if (isFixed(z)) return .nil else spanId(tables, slots[z - 1].?) orelse return .nil,
        else => return .nil,
    };
    const us: i64 = switch (args[1]) {
        .instant => |v| v,
        .dtm => |v| v.us,
        else => return .nil,
    };
    const l = tables.local(zid, @divFloor(us, 1_000_000)) orelse return .nil;
    return switch (@as(SpanFn, @enumFromInt(id))) {
        .span_offset => .{ .dur = @as(i64, l.utoff) * 1_000_000 },
        .span_dst => .{ .bool = l.isdst },
        .span_abbr => try it.newStr(l.abbr),
    };
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

/// The id of the zone a text names: `Z`, an offset, or a name of the database (a link keeps its own name); null when there is none.
/// The names are asked of the zone module (`zone.exists`), so the lock is not held while it runs.
pub fn zoneIdOf(it: *Interp, text: []const u8) Signal!?u32 {
    if (parseOffset(text)) |off| return fixedId(off);
    acquire();
    const known = zones.get(text);
    release();
    if (known) |e| return e.id;
    const exists = if (spans(it)) |tables| tables.idOf(text) != null else (try zoneCall(it, "exists", &.{try it.newStr(text)})).bool;
    if (!exists) return null;
    const e = try alloc.create(Entry);
    e.* = .{ .name = try dup(text) };
    acquire();
    defer release();
    e.id = register(e);
    try zones.put(alloc, e.name, e);
    return e.id;
}

fn acquire() void {
    while (lock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) std.atomic.spinLoopHint();
}

fn release() void {
    lock.store(false, .release);
}

/// The path of the meta database file: `EVE_META_DB`, else `lib/meta/meta.db` beside the program (`<prefix>/lib`), else in the working folder.
fn findFile(io: Io) ?[]const u8 {
    if (std.c.getenv("EVE_META_DB")) |p| return std.mem.span(p);
    const exe_dir = std.process.executableDirPathAlloc(io, alloc) catch return null;
    const beside = std.fs.path.join(alloc, &.{ exe_dir, "..", "lib", file_name }) catch return null;
    if (Io.Dir.cwd().access(io, beside, .{})) |_| return beside else |_| {}
    return "lib/" ++ file_name;
}

/// Refuses a Git LFS pointer (a few lines of text where the database should be) and a file that is not there.
fn checkFile(io: Io, path: []const u8) ?[]const u8 {
    const st = Io.Dir.cwd().statFile(io, path, .{}) catch return "meta database not found: lib/meta/meta.db is missing (see spec/library/meta.md)";
    if (st.size < 1024) {
        const head = Io.Dir.cwd().readFileAlloc(io, path, alloc, .limited(1024)) catch return "meta database: cannot read the file";
        if (std.mem.startsWith(u8, head, "version https://git-lfs")) return "lib/meta/meta.db is a Git LFS pointer, not the database: run `git lfs pull` (D-222)";
    }
    return null;
}

/// Creates in `d` the table `name` and its indexes, with the statements of the file (keys, checks, unique columns); the rows come after.
fn copySchema(d: *sqlite.Db, name: []const u8) !void {
    const query = try std.fmt.allocPrintSentinel(alloc, "SELECT type, sql FROM src.sqlite_master WHERE tbl_name = ?1 AND sql IS NOT NULL ORDER BY type DESC", .{}, 0);
    var q = try d.prepare(query);
    defer q.finalize();
    try q.bindText(1, name);
    while (try q.step()) {
        const is_table = std.mem.eql(u8, q.columnText(0), "table");
        const sql = try alloc.dupe(u8, q.columnText(1));
        // the same statement, in the memory connection: `main.` in front of the name
        const made = if (is_table) blk: {
            if (!std.mem.startsWith(u8, sql, "CREATE TABLE ")) return error.Exec;
            break :blk try std.fmt.allocPrint(alloc, "CREATE TABLE main.{s}", .{sql["CREATE TABLE ".len..]});
        } else blk: {
            const at = (std.mem.indexOf(u8, sql, "INDEX ") orelse return error.Exec) + "INDEX ".len;
            break :blk try std.fmt.allocPrint(alloc, "{s}main.{s}", .{ sql[0..at], sql[at..] });
        };
        try d.exec(try std.fmt.allocPrintSentinel(alloc, "{s}", .{made}, 0));
    }
}

/// Copies one table of the file into `d`: its schema, then its rows.
fn copyTable(d: *sqlite.Db, name: []const u8) !void {
    try copySchema(d, name);
    try d.exec(try std.fmt.allocPrintSentinel(alloc, "INSERT INTO main.{s} SELECT * FROM src.{s}", .{ name, name }, 0));
}

/// Copies the tables of `mask` from the file at `path` into `d`, which must be a memory database; the file is attached only for the copy.
/// The parents of a table come first (a foreign key is checked on the insert), and a table that needs a parent takes it too.
fn copyTables(d: *sqlite.Db, path: []const u8, mask: u16) !u16 {
    // the connection is read only for the SQL door (D-222): writes are allowed only while the tables are copied
    try d.exec("PRAGMA query_only = OFF");
    defer d.exec("PRAGMA query_only = ON") catch {};
    const attach = try std.fmt.allocPrintSentinel(alloc, "ATTACH '{s}' AS src", .{path}, 0);
    try d.exec(attach);
    defer d.exec("DETACH src") catch {};
    const order = [_][]const u8{ "continent", "country", "zone", "zone_type", "zone_transition", "zone_kind", "zone_span", "windows_zone", "meta_info" };
    var want = mask;
    if (want & bitOf("zone") != 0) want |= bitOf("country") | bitOf("continent");
    if (want & bitOf("country") != 0) want |= bitOf("continent");
    for (order) |name| {
        if (want & bitOf(name) == 0) continue;
        try copyTable(d, name);
    }
    // the tables that are in `d` now: the parents come with their children
    return want;
}

fn bitOf(name: []const u8) u16 {
    return @as(u16, 1) << @intCast(meta_need.indexOf(name).?);
}

/// Reads the file in a background thread at optimization level 5 and above (D-226); the copy waits for the join in `connect`.
fn prepareWorker(io: Io, want: meta_need.Need) void {
    const path = findFile(io) orelse {
        prepared_failure = "meta database not found: lib/meta/meta.db is missing (see spec/library/meta.md)";
        return;
    };
    if (checkFile(io, path)) |why| {
        prepared_failure = why;
        return;
    }
    var d = sqlite.Db.open(":memory:") catch {
        prepared_failure = "meta database: cannot open a memory connection";
        return;
    };
    const copied = copyTables(&d, path, want.mask) catch {
        d.close();
        prepared_failure = "meta database: cannot copy the tables of the file";
        return;
    };
    file_path = path;
    prepared = d;
    prepared_mask = copied;
}

/// Starts the background copy of the tables a run needs when the optimization level is 5 or more (D-226). Below 5 nothing starts: the copy is made at the first use.
pub fn prepare(io: Io, level: u8, want: meta_need.Need) void {
    if (level < 5 or want.isEmpty() or loader != null or db != null) return;
    loader = std.Thread.spawn(.{}, prepareWorker, .{ io, want }) catch null;
}

/// The connection of the library with the tables `want` copied in: the background copy taken over (after its join), or the file opened now.
/// Copies a table that is not in the connection yet. The caller holds the lock.
fn connect(it: *Interp, want: meta_need.Need) Signal!*sqlite.Db {
    if (loader) |t| {
        t.join();
        loader = null;
        if (prepared) |p| {
            db = p;
            loaded_mask = prepared_mask;
            prepared = null;
        }
    }
    if (db == null) {
        const io = it.io orelse return it.fail("meta: no input/output handle", .{});
        const path = findFile(io) orelse return it.failWith(interp.err_file, "meta database not found: lib/meta/meta.db is missing (see spec/library/meta.md)", .{});
        if (checkFile(io, path)) |why| return it.failWith(interp.err_file, "{s}", .{why});
        db = sqlite.Db.open(":memory:") catch return it.failWith(interp.err_io, "meta: the memory connection can not be opened", .{});
        file_path = path;
    }
    const missing = want.mask & ~loaded_mask;
    if (missing != 0) {
        const copied = copyTables(&db.?, file_path.?, missing) catch |e| return it.failWith(interp.err_io, "meta: the tables can not be copied from the file: {s}: {s}", .{ @errorName(e), db.?.errorMessage() });
        loaded_mask |= copied;
    }
    return &db.?;
}

/// The connection that `database.connect("meta")` gives: every table, since a SQL statement may name any of them.
pub fn connection(it: *Interp) Signal!*sqlite.Db {
    acquire();
    defer release();
    return connect(it, meta_need.Need.all);
}

/// The connection of the zone lookups and of `meta.info`; the caller holds the lock.
fn open(it: *Interp) Signal!*sqlite.Db {
    return connect(it, zone_core);
}

fn dup(s: []const u8) std.mem.Allocator.Error![]const u8 {
    return alloc.dupe(u8, s);
}


test "spec: meta.md#the-file the database file opens and holds the zones" {
    var d = try sqlite.Db.open("lib/meta/meta.db");
    defer d.close();
    var q = try d.prepare("select count(*), (select value from meta_info where name = 'tzdata') from zone");
    defer q.finalize();
    try std.testing.expect(try q.step());
    try std.testing.expectEqual(@as(i64, 598), q.columnInt(0));
    try std.testing.expect(q.columnText(1).len >= 5);
}

test "spec: meta.md#zone a link shares the data of its zone" {
    var d = try sqlite.Db.open("lib/meta/meta.db");
    defer d.close();
    var q = try d.prepare("select count(*) from zone l join zone z on z.id = l.link_of where l.name = 'Asia/Calcutta' and z.name = 'Asia/Kolkata'");
    defer q.finalize();
    try std.testing.expect(try q.step());
    try std.testing.expectEqual(@as(i64, 1), q.columnInt(0));
}

test "spec: time.md#zones a Windows zone name maps to its IANA zone" {
    var d = try sqlite.Db.open("lib/meta/meta.db");
    defer d.close();
    var q = try d.prepare("SELECT zone FROM windows_zone WHERE name = 'FLE Standard Time' AND territory = '001'");
    defer q.finalize();
    try std.testing.expect(try q.step());
    try std.testing.expect(std.mem.indexOfScalar(u8, q.columnText(0), '/') != null);
}
