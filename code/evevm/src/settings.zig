//! @eve-module evevm.settings
//! @spec spec/semantics/variables.md#system-variables
//! @feature F-STR-06
//! @tests test/level2/b60_cfg_setup
//! The configuration file of a script run (`-e file.cfg`, `--setup`, the command `setup`): lines `$name = literal`, `#` comments.
const std = @import("std");
const Io = std.Io;
const interp = @import("interp.zig");
const Interp = interp.Interp;
const Signal = interp.Signal;
const Value = interp.Value;

/// One setting: the name with its `$`, and the literal (a String is a slice of the source or of `text`).
pub const Entry = struct { name: []const u8, value: Value, line: usize };

/// A syntax error of the file.
pub const Problem = struct { line: usize, message: []const u8 };

// @eve-fn setup.parse
// @spec spec/semantics/variables.md#system-variables
// @test b60_cfg_setup
/// Parse the text of a `.cfg` file. A line is blank, a comment (`#` first), or `$name = literal` with an optional `# comment`
/// after the literal. A literal is an Integer, a Real (`2.5`), a Logic (`True`, `False`) or a String in double quotes (escapes: a backslash before a quote, a backslash, n or t).
pub fn parse(arena: std.mem.Allocator, text: []const u8, problem: *Problem) error{BadLine, OutOfMemory}![]Entry {
    var out: std.ArrayList(Entry) = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    var n: usize = 0;
    while (lines.next()) |raw| {
        n += 1;
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        if (line[0] != '$') return bad(problem, n, "a setting starts with $: $name = value");
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse return bad(problem, n, "a setting is $name = value");
        const name = std.mem.trim(u8, line[0..eq], " \t");
        if (name.len < 2 or !validName(name[1..])) return bad(problem, n, "bad name");
        var rest = std.mem.trim(u8, line[eq + 1 ..], " \t");
        var value: Value = undefined;
        if (rest.len > 0 and rest[0] == '"') {
            var buf: std.ArrayList(u8) = .empty;
            var i: usize = 1;
            var closed = false;
            while (i < rest.len) : (i += 1) {
                const c = rest[i];
                if (c == '"') {
                    closed = true;
                    i += 1;
                    break;
                }
                if (c == '\\' and i + 1 < rest.len) {
                    i += 1;
                    try buf.append(arena, switch (rest[i]) {
                        'n' => '\n',
                        't' => '\t',
                        else => rest[i],
                    });
                } else try buf.append(arena, c);
            }
            if (!closed) return bad(problem, n, "the text has no closing quote");
            rest = std.mem.trim(u8, rest[i..], " \t");
            value = .{ .str = buf.items };
        } else {
            const end = std.mem.indexOfScalar(u8, rest, '#') orelse rest.len;
            const word = std.mem.trim(u8, rest[0..end], " \t");
            rest = rest[end..];
            if (std.mem.eql(u8, word, "True")) {
                value = .{ .bool = true };
            } else if (std.mem.eql(u8, word, "False")) {
                value = .{ .bool = false };
            } else if (std.fmt.parseInt(i64, word, 10)) |v| {
                value = .{ .int = v };
            } else |_| if (std.fmt.parseFloat(f64, word)) |v| {
                if (std.mem.indexOfScalar(u8, word, '.') == null) return bad(problem, n, "not a literal");
                value = .{ .real = v };
            } else |_| return bad(problem, n, "not a literal: write a number, True, False or a text in double quotes");
        }
        if (rest.len > 0 and rest[0] != '#') return bad(problem, n, "unexpected text after the value");
        try out.append(arena, .{ .name = name, .value = value, .line = n });
    }
    return out.items;
}

fn bad(problem: *Problem, line: usize, message: []const u8) error{BadLine} {
    problem.* = .{ .line = line, .message = message };
    return error.BadLine;
}

fn validName(s: []const u8) bool {
    for (s) |c| if (!(std.ascii.isAlphanumeric(c) or c == '_')) return false;
    return s.len > 0 and !std.ascii.isDigit(s[0]);
}

/// Read and parse the file `path`; a message `path:line: reason` and the exit code when it fails (66 missing, 65 bad line).
pub fn load(io: Io, arena: std.mem.Allocator, path: []const u8, why: *[]const u8) error{Failed, OutOfMemory}![]Entry {
    const text = Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(1 << 20)) catch {
        why.* = try std.fmt.allocPrint(arena, "cannot read {s}", .{path});
        return error.Failed;
    };
    var problem: Problem = undefined;
    return parse(arena, text, &problem) catch |e| switch (e) {
        error.BadLine => {
            why.* = try std.fmt.allocPrint(arena, "{s}:{d}: {s}", .{ path, problem.line, problem.message });
            return error.Failed;
        },
        error.OutOfMemory => return error.OutOfMemory,
    };
}

// @eve-impl the settings of the file become read-only system variables of the run
/// Define every setting of the file as a constant `$name` in the scope of the run.
pub fn define(it: *Interp, entries: []const Entry) Signal!void {
    for (entries) |e| {
        const v: Value = switch (e.value) {
            .str => |s| try it.newStr(s),
            else => e.value,
        };
        try it.define(e.name, v, true);
    }
}
