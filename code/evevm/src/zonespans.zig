//! @eve-module zonespans: the spans of the time zones in memory, read once from the meta database (tables zone_span, zone_kind, zone)
//! @spec spec/library/meta.md#zone
//! @feature F-LIB-06
//! @decision D-229
//! @tests test/level5/e129_meta_zone, test/level5/e131_meta_zone_bulk
//! A lookup is a binary search over the spans of a zone; no zone data is written here, the tables come from tools/meta/zone_spans.py. An instant beyond the horizon (kind 0) has no answer here: the Eve code of lib/meta/zone.eve gives it.
//! @see code/evevm/src/metalib.zig:spans
const std = @import("std");
const sqlite = @import("db/sqlite.zig");

/// The local time of a zone at an instant.
pub const Local = struct { utoff: i32, isdst: bool, abbr: []const u8 };

pub const Resolve = union(enum) {
    one: i64,
    two: struct { first: i64, second: i64 },
    gap: struct { before: i32, after: i32 },
};

const Kind = struct { utoff: i32, isdst: bool, abbr: []const u8 };

// @invariant read only after `load`: the threads read it without a lock; `at` of a zone is sorted, its first span starts at the start of time
pub const Tables = struct {
    at: []const i64,
    kind: []const u16,
    /// the spans of the zone with the database id `z` are `start[z]..start[z + 1]` (empty for a link: see `target`)
    start: []const u32,
    /// the database id of the zone whose data a name uses: itself, or the zone a link points to
    target: []const u32,
    kinds: []const Kind,
    ids: std.StringHashMapUnmanaged(u32),

    /// The database id of a zone name (a link has its own id), null when the name is not in the database.
    pub fn idOf(t: *const Tables, name: []const u8) ?u32 {
        return t.ids.get(name);
    }

    /// The local time of the zone `id` at the UTC second `instant`; null beyond the horizon of the spans.
    // @perf hot
    pub fn local(t: *const Tables, id: u32, instant: i64) ?Local {
        const z = t.target[id];
        const lo = t.start[z];
        const hi = t.start[z + 1];
        const spans = t.at[lo..hi];
        // the last span that starts at or before the instant (the first one starts at the start of time)
        const after = std.sort.upperBound(i64, spans, instant, order);
        const k = t.kind[lo + after - 1];
        if (k == 0) return null;
        const kind = t.kinds[k - 1];
        return .{ .utoff = kind.utoff, .isdst = kind.isdst, .abbr = kind.abbr };
    }

    fn offset(t: *const Tables, id: u32, instant: i64) ?i32 {
        return (t.local(id, instant) orelse return null).utoff;
    }

    /// The instants of a local time (seconds since 1970-01-01T00:00:00 local), as `zone.resolve_local` of lib/meta/zone.eve; null when a lookup is beyond the horizon.
    // @see lib/meta/zone.eve:resolve_local
    pub fn resolve(t: *const Tables, id: u32, wall: i64) ?Resolve {
        const before = t.offset(id, wall - 86400) orelse return null;
        const after = t.offset(id, wall + 86400) orelse return null;
        const t1 = wall - before;
        const ok1 = (t.offset(id, t1) orelse return null) == before;
        if (before == after) {
            if (ok1) return .{ .one = t1 };
            const mid = t.offset(id, t1) orelse return null;
            const t3 = wall - mid;
            if ((t.offset(id, t3) orelse return null) == mid) return .{ .one = t3 };
            return .{ .gap = .{ .before = before, .after = mid } };
        }
        const t2 = wall - after;
        const ok2 = (t.offset(id, t2) orelse return null) == after;
        if (ok1 and ok2) return .{ .two = .{ .first = @min(t1, t2), .second = @max(t1, t2) } };
        if (ok1) return .{ .one = t1 };
        if (ok2) return .{ .one = t2 };
        return .{ .gap = .{ .before = before, .after = after } };
    }
};

fn order(key: i64, item: i64) std.math.Order {
    return std.math.order(key, item);
}

/// Reads the three tables from `db` (a connection that has them) into memory.
pub fn load(a: std.mem.Allocator, db: *sqlite.Db) !*const Tables {
    var max_id: u32 = 0;
    {
        var q = try db.prepare("SELECT max(id), count(*) FROM zone");
        defer q.finalize();
        if (!try q.step()) return error.Step;
        max_id = @intCast(q.columnInt(0));
    }
    const n = max_id + 1;
    const target = try a.alloc(u32, n);
    @memset(target, 0);
    var ids: std.StringHashMapUnmanaged(u32) = .empty;
    {
        var q = try db.prepare("SELECT id, name, coalesce(link_of, id) FROM zone");
        defer q.finalize();
        while (try q.step()) {
            const id: u32 = @intCast(q.columnInt(0));
            target[id] = @intCast(q.columnInt(2));
            try ids.put(a, try a.dupe(u8, q.columnText(1)), id);
        }
    }
    var kinds: std.ArrayList(Kind) = .empty;
    {
        var q = try db.prepare("SELECT utoff, isdst, abbr FROM zone_kind ORDER BY id");
        defer q.finalize();
        while (try q.step()) try kinds.append(a, .{ .utoff = @intCast(q.columnInt(0)), .isdst = q.columnInt(1) != 0, .abbr = try a.dupe(u8, q.columnText(2)) });
    }
    var count: usize = 0;
    {
        var q = try db.prepare("SELECT count(*) FROM zone_span");
        defer q.finalize();
        if (!try q.step()) return error.Step;
        count = @intCast(q.columnInt(0));
    }
    const at = try a.alloc(i64, count);
    const kind = try a.alloc(u16, count);
    const start = try a.alloc(u32, n + 1);
    @memset(start, 0);
    {
        var q = try db.prepare("SELECT zone, at, kind FROM zone_span ORDER BY zone, at");
        defer q.finalize();
        var i: usize = 0;
        var prev: u32 = 0;
        while (try q.step()) : (i += 1) {
            const z: u32 = @intCast(q.columnInt(0));
            // the spans of a zone are together: fill the starts of the zones in between
            while (prev < z) : (prev += 1) start[prev + 1] = @intCast(i);
            at[i] = q.columnInt(1);
            kind[i] = @intCast(q.columnInt(2));
        }
        while (prev < n) : (prev += 1) start[prev + 1] = @intCast(i);
    }
    const t = try a.create(Tables);
    t.* = .{ .at = at, .kind = kind, .start = start, .target = target, .kinds = try kinds.toOwnedSlice(a), .ids = ids };
    return t;
}
