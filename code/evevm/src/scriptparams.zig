//! @eve-module evevm.scriptparams
//! @spec spec/semantics/aspects.md#parameters-on-the-command-line
//! @feature F-STR-05
//! @tests test/level1/a98_script_params, test/level1/a99_script_help, test/level1/a100_script_param_missing
//! The parameters of a script on the command line: `-p name=value`, the help of `eve script.eve -h` made from the
//! comments `** @param name:Type; description` and the parameters of `process main`, and the check for a missing parameter.
const std = @import("std");
const Io = std.Io;
const ast = @import("evecm").ast;
const interp = @import("interp.zig");

const Node = ast.Node;

/// The exit code of a usage error: a parameter is missing or `-p` is not `name=value`.
pub const exit_usage = 64;

// @eve-fn cli.param
// @spec spec/semantics/aspects.md#parameters-on-the-command-line
// @test a98_script_params
/// The pairs of `-p name=value`; null (and `bad` set) when one of them has no `=`.
pub fn pairs(arena: std.mem.Allocator, raw: []const []const u8, bad: *[]const u8) !?[]interp.ScriptParam {
    var out: std.ArrayList(interp.ScriptParam) = .empty;
    for (raw) |r| {
        const eq = std.mem.indexOfScalar(u8, r, '=') orelse {
            bad.* = r;
            return null;
        };
        if (eq == 0) {
            bad.* = r;
            return null;
        }
        try out.append(arena, .{ .name = r[0..eq], .value = r[eq + 1 ..] });
    }
    return out.items;
}

/// The names of the parameters of `main` that have no default, no `@`, and no argument on the command line.
pub fn missing(arena: std.mem.Allocator, main: *const Node, positional: usize, given: []const interp.ScriptParam) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var pos: usize = 0;
    for (main.kids[3].kids) |prm| {
        if (prm.tag == .vararg_param) break;
        var named = false;
        for (given) |g| if (std.mem.eql(u8, g.name, prm.text)) {
            named = true;
        };
        if (named) continue;
        if (pos < positional) {
            pos += 1;
            continue;
        }
        if (prm.tag == .param and prm.kids[0].tag == .none) try out.append(arena, prm.text);
    }
    return out.items;
}

/// One `** @param name:Type; description` line of the source.
const Doc = struct { name: []const u8, ty: []const u8, text: []const u8 };

fn docs(arena: std.mem.Allocator, src: []const u8) ![]Doc {
    var out: std.ArrayList(Doc) = .empty;
    var lines = std.mem.splitScalar(u8, src, 10);
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (!std.mem.startsWith(u8, line, "** @param ")) continue;
        const rest = std.mem.trim(u8, line["** @param ".len..], " ");
        const colon = std.mem.indexOfScalar(u8, rest, ':') orelse continue;
        const semi = std.mem.indexOfScalarPos(u8, rest, colon, ';') orelse rest.len;
        try out.append(arena, .{
            .name = std.mem.trim(u8, rest[0..colon], " "),
            .ty = std.mem.trim(u8, rest[colon + 1 .. semi], " "),
            .text = if (semi < rest.len) std.mem.trim(u8, rest[semi + 1 ..], " ") else "",
        });
    }
    return out.items;
}

// @eve-fn cli.help
// @spec spec/semantics/aspects.md#parameters-on-the-command-line
// @test a98_script_params
/// The help of a script: the first comment line, the usage and one line for each parameter of `process main`. The text of a
/// parameter comes from its `** @param` comment; a parameter without one is listed with its declared type.
pub fn writeHelp(arena: std.mem.Allocator, w: *Io.Writer, file: []const u8, src: []const u8, main: *const Node) !void {
    var title: []const u8 = "";
    var first = std.mem.splitScalar(u8, src, 10);
    if (first.next()) |l| {
        const t = std.mem.trim(u8, l, " \t\r");
        if (t.len > 0 and t[0] == '#') title = std.mem.trim(u8, std.mem.trimStart(u8, t, "#"), " ");
    }
    if (title.len > 0) try w.print("{s}\n\n", .{title});
    const base = file[if (std.mem.lastIndexOfAny(u8, file, "/\\")) |c| c + 1 else 0..];
    try w.print("Usage: eve {s} [-p name=value]... [value]...\n", .{base});
    const params = main.kids[3].kids;
    if (params.len == 0) {
        try w.writeAll("\nThe script takes no parameters.\n");
        return;
    }
    const list = try docs(arena, src);
    try w.writeAll("\nParameters:\n");
    for (params) |prm| {
        var text: []const u8 = "";
        var ty: []const u8 = if (prm.ty) |t| t.text else "";
        for (list) |d| if (std.mem.eql(u8, d.name, prm.text)) {
            text = d.text;
            if (d.ty.len > 0) ty = d.ty;
        };
        const star: []const u8 = if (prm.tag == .vararg_param) "*" else if (prm.tag == .ref_param) "@" else "";
        const need: []const u8 = if (prm.tag == .param and prm.kids[0].tag == .none) " (required)" else "";
        try w.print("  {s}{s}", .{ star, prm.text });
        if (ty.len > 0) try w.print(":{s}", .{ty});
        try w.print("{s}", .{need});
        if (text.len > 0) try w.print("  {s}", .{text});
        try w.writeAll("\n");
    }
}
