//! Fault injection (README.md section 8.1): a test says `pragma eve_fault('drop', 'after_commit')` and the server fails once,
//! at the next matching point of that session (or of every session). This file parses the statement and keeps the list.
const std = @import("std");

/// The kinds of fault of section 8.1.
pub const Kind = enum { drop, conflict, deadlock, commit_fail, status_unknown, delay, lease_expire };

/// The points where a `drop` can happen.
pub const Point = enum { begin, execute, before_commit, after_commit };

/// One fault waiting to fire.
pub const Fault = struct {
    kind: Kind,
    point: [48]u8 = undefined,
    point_len: u8 = 0,
    arg: i64 = 0,
    /// scope all: the fault belongs to the server, not to one session.
    all: bool = false,

    pub fn pointText(self: *const Fault) []const u8 {
        return self.point[0..self.point_len];
    }
};

pub const ParseError = error{ NotAFault, BadKind, BadPoint, BadArgument };

fn unquote(s: []const u8) []const u8 {
    const t = std.mem.trim(u8, s, " \t\r\n");
    if (t.len >= 2 and (t[0] == '\'' or t[0] == '"') and t[t.len - 1] == t[0]) return t[1 .. t.len - 1];
    return t;
}

/// True when the statement is `pragma eve_fault(...)`, in any case, with or without a final `;`.
pub fn isFaultStatement(sql: []const u8) bool {
    const t = std.mem.trim(u8, sql, " \t\r\n;");
    const head = "pragma eve_fault";
    return t.len > head.len and std.ascii.eqlIgnoreCase(t[0..head.len], head);
}

/// Parse `pragma eve_fault(kind [, point [, arg]])`.
pub fn parse(sql: []const u8) ParseError!Fault {
    if (!isFaultStatement(sql)) return error.NotAFault;
    const open = std.mem.indexOfScalar(u8, sql, '(') orelse return error.BadKind;
    const close = std.mem.lastIndexOfScalar(u8, sql, ')') orelse return error.BadKind;
    if (close < open) return error.BadKind;
    var it = std.mem.splitScalar(u8, sql[open + 1 .. close], ',');
    const kind_text = unquote(it.next() orelse return error.BadKind);
    const kind = std.meta.stringToEnum(Kind, kind_text) orelse return error.BadKind;
    var f: Fault = .{ .kind = kind };
    if (it.next()) |p| {
        const pt = unquote(p);
        if (pt.len > f.point.len) return error.BadPoint;
        @memcpy(f.point[0..pt.len], pt);
        f.point_len = @intCast(pt.len);
    }
    if (it.next()) |a| {
        const at = unquote(a);
        if (std.ascii.eqlIgnoreCase(at, "all")) {
            f.all = true;
        } else f.arg = std.fmt.parseInt(i64, at, 10) catch return error.BadArgument;
    }
    switch (kind) {
        .drop => if (std.meta.stringToEnum(Point, f.pointText()) == null) return error.BadPoint,
        .conflict => if (f.point_len == 0) return error.BadPoint,
        .delay => {
            // `delay` takes its milliseconds as the second argument: pragma eve_fault('delay', 200)
            if (f.point_len > 0 and f.arg == 0) f.arg = std.fmt.parseInt(i64, f.pointText(), 10) catch return error.BadArgument;
        },
        else => {},
    }
    return f;
}

/// The faults waiting in a session (or in the server, for scope all).
pub const List = struct {
    items: std.ArrayList(Fault) = .empty,

    pub fn deinit(self: *List, gpa: std.mem.Allocator) void {
        self.items.deinit(gpa);
    }

    pub fn add(self: *List, gpa: std.mem.Allocator, f: Fault) !void {
        try self.items.append(gpa, f);
    }

    /// Remove and answer the first fault of the kind `kind` whose point text is `point` (a `null` point matches any).
    pub fn take(self: *List, kind: Kind, point: ?[]const u8) ?Fault {
        for (self.items.items, 0..) |f, i| {
            if (f.kind != kind) continue;
            if (point) |p| if (!std.mem.eql(u8, f.pointText(), p)) continue;
            return self.items.orderedRemove(i);
        }
        return null;
    }

    /// The first fault of the kind, left in place (a `delay` fires for every frame).
    pub fn peek(self: *const List, kind: Kind) ?Fault {
        for (self.items.items) |f| if (f.kind == kind) return f;
        return null;
    }

    /// Does the SQL text name the table `name` (a whole word, any case)?
    pub fn namesTable(sql: []const u8, name: []const u8) bool {
        var i: usize = 0;
        while (i + name.len <= sql.len) : (i += 1) {
            if (!std.ascii.eqlIgnoreCase(sql[i .. i + name.len], name)) continue;
            const before = i == 0 or !(std.ascii.isAlphanumeric(sql[i - 1]) or sql[i - 1] == '_');
            const after = i + name.len == sql.len or !(std.ascii.isAlphanumeric(sql[i + name.len]) or sql[i + name.len] == '_');
            if (before and after) return true;
        }
        return false;
    }
};

test "a fault statement is parsed" {
    const f = try parse("pragma eve_fault('drop', 'after_commit', 0);");
    try std.testing.expectEqual(Kind.drop, f.kind);
    try std.testing.expectEqualStrings("after_commit", f.pointText());
    const g = try parse("PRAGMA eve_fault('conflict', 'orders', 'all')");
    try std.testing.expect(g.all);
    try std.testing.expectEqualStrings("orders", g.pointText());
    const d = try parse("pragma eve_fault('delay', 250)");
    try std.testing.expectEqual(@as(i64, 250), d.arg);
    try std.testing.expectError(error.BadKind, parse("pragma eve_fault('explode')"));
    try std.testing.expectError(error.BadPoint, parse("pragma eve_fault('drop', 'nowhere')"));
    try std.testing.expect(!isFaultStatement("select 1"));
}

test "a fault fires once and only at its point" {
    const gpa = std.testing.allocator;
    var l: List = .{};
    defer l.deinit(gpa);
    try l.add(gpa, try parse("pragma eve_fault('drop', 'before_commit')"));
    try l.add(gpa, try parse("pragma eve_fault('commit_fail')"));
    try std.testing.expect(l.take(.drop, "begin") == null);
    try std.testing.expect(l.take(.drop, "before_commit") != null);
    try std.testing.expect(l.take(.drop, "before_commit") == null);
    try std.testing.expect(l.take(.commit_fail, null) != null);
    try std.testing.expect(List.namesTable("update Orders set x = 1", "orders"));
    try std.testing.expect(!List.namesTable("update order_lines set x = 1", "order"));
}
