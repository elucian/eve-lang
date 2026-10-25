//! @eve-module repl: the statements and the expressions typed at the prompt, run in one session scope that lasts between the lines (F-TLS-03)
//! @spec spec/semantics/repl.md#prompt-lines
//! @feature F-TLS-03
//! @tests test/level3/c60_repl_session
//! A line is parsed without the static checks (a name of an earlier line is not in the line), and its statements run in the scope of the session. An expression is printed.
const std = @import("std");
const Io = std.Io;
const ast = @import("evecm").ast;
const parser = @import("evecp").parser;
const interp = @import("interp.zig");
const sysvars = @import("interp/sysvars.zig");

/// A session of the prompt: its interpreter and the scope where its variables live.
pub const Session = struct {
    machine: *interp.Interp,
    scope: *interp.Scope,
};

/// Opens a session whose output goes to `out`; its modules and aspects are those of the prompt.
pub fn open(io: Io, a: std.mem.Allocator, out: *Io.Writer, modules: *const ast.Modules, aspects: *const ast.Aspects) !Session {
    const machine = try a.create(interp.Interp);
    machine.* = interp.Interp.init(a, out) catch return error.OutOfMemory;
    machine.io = io;
    machine.modules = modules;
    machine.aspects = aspects;
    machine.defineOsPwd() catch {};
    sysvars.define(machine, ".") catch {};
    // the scope of the session: made once, kept alive for the life of the prompt
    const outer = machine.pushScope() catch return error.OutOfMemory;
    const scope = machine.scope;
    scope.hdr.pinned = true;
    machine.leaveScope(outer);
    return .{ .machine = machine, .scope = scope };
}

/// The statements of a text, in the body of a process of a wrapper aspect; null when the text is not Eve code.
fn bodyOf(a: std.mem.Allocator, text: []const u8, diag: *parser.Diag) ?[]const *const ast.Node {
    const src = std.fmt.allocPrint(a, "primary aspect repl is\n  process main is\n{s}\n  return;\nend repl;\n", .{text}) catch return null;
    const root = parser.parseSyntax(a, src, diag) catch return null;
    for (root.kids) |k| if (k.tag == .process) return k.kids[0].kids;
    return null;
}

/// The statements that a prompt line stands for. A line that does not end in `;` is an expression first: it is printed.
fn parseLine(a: std.mem.Allocator, text: []const u8, diag: *parser.Diag) ?[]const *const ast.Node {
    const t = std.mem.trim(u8, text, " \t\r");
    if (t.len == 0) return &.{};
    if (t[t.len - 1] != ';' and t[t.len - 1] != '}') {
        // an expression: printed
        const as_print = std.fmt.allocPrint(a, "print ({s});", .{t}) catch return null;
        if (bodyOf(a, as_print, diag)) |body| return body;
        // a statement without its `;`
        const with_semi = std.fmt.allocPrint(a, "{s};", .{t}) catch return null;
        if (bodyOf(a, with_semi, diag)) |body| return body;
    }
    return bodyOf(a, t, diag);
}

/// Runs one line of the prompt in the session; the errors and the values go to the output of the session. Gives the status of the line.
pub fn evalLine(s: *Session, a: std.mem.Allocator, text: []const u8) u8 {
    var diag: parser.Diag = .{};
    const body = parseLine(a, text, &diag) orelse {
        const out = s.machine.out;
        out.print("error: {d}:{d}: {s}\n", .{ diag.line, diag.col, diag.message() }) catch {};
        return 65;
    };
    const machine = s.machine;
    const saved = machine.enterScope(s.scope) catch return 4;
    defer machine.leaveScope(saved);
    for (body) |st| {
        machine.exec(st) catch |e| {
            if (e == error.Raise and machine.reports.items.len > 0) {
                const r = machine.reports.items[machine.reports.items.len - 1];
                machine.out.print("error {d}: {s}\n", .{ r.code, r.message }) catch {};
                return r.code;
            }
            machine.out.print("error: the line stopped\n", .{}) catch {};
            return 4;
        };
    }
    return 0;
}

test "spec: repl.md#prompt-lines an expression is printed and a statement is kept in the session" {
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var diag: parser.Diag = .{};
    const body = parseLine(arena.allocator(), "1 + 2", &diag) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 1), body.len);
    const stmt = parseLine(arena.allocator(), "new x := 5;", &diag) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 1), stmt.len);
}
