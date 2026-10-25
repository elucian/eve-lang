//! @eve-module evecp.tools: the commands `fmt` and `lint`
//! @spec spec/semantics/tools.md
//! @feature F-TLS-08
//! @tests test/level4/d46_fmt_command, test/level4/d47_lint_command
//! Files and folders in, a line per finding out; the exit status is 0 when nothing was found, 1 when something was (a file not formatted with `--check`, an unused name), 65 for a syntax error.
const std = @import("std");
const Io = std.Io;
const cli = @import("cli.zig");
const parser = @import("parser.zig");
const fmt = @import("fmt.zig");
const lint = @import("lint.zig");

const Env = cli.Env;

/// The status of a run that found something to report (an unformatted file, an unused name).
pub const exit_findings = 1;

/// The `.eve` files named by `path`: a file as it is, a folder with its `.eve` files and those of its sub-folders (not the folders that start with a dot), in order.
fn collect(env: Env, arena: std.mem.Allocator, path: []const u8, list: *std.ArrayList([]const u8)) !void {
    if (std.mem.endsWith(u8, path, ".eve")) return list.append(arena, path);
    var dir = try Io.Dir.cwd().openDir(env.io, path, .{ .iterate = true });
    defer dir.close(env.io);
    const Item = struct { name: []const u8, kind: Io.File.Kind };
    var names: std.ArrayList(Item) = .empty;
    var it = dir.iterate();
    while (try it.next(env.io)) |e| {
        if (e.name[0] == '.') continue;
        try names.append(arena, .{ .name = try arena.dupe(u8, e.name), .kind = e.kind });
    }
    std.mem.sort(Item, names.items, {}, struct {
        fn less(_: void, a: Item, b: Item) bool {
            return std.mem.lessThan(u8, a.name, b.name);
        }
    }.less);
    for (names.items) |e| {
        const child = try std.fs.path.join(arena, &.{ path, e.name });
        switch (e.kind) {
            .directory => try collect(env, arena, child, list),
            .file => if (std.mem.endsWith(u8, e.name, ".eve")) try list.append(arena, child),
            else => {},
        }
    }
}

const Mode = enum { fmt, lint };

// @eve-fn cp.fmt
// @spec spec/semantics/tools.md#eve-fmt
/// `fmt [--check] <file.eve | folder>...`: write the layout of each file (see `fmt.zig`); with `--check` only report the files that would change.
pub fn fmtCommand(env: Env, args: []const []const u8) Io.Writer.Error!u8 {
    return run(env, args, .fmt);
}

// @eve-fn cp.lint
// @spec spec/semantics/tools.md#eve-lint
/// `lint <file.eve | folder>...`: the names that are declared and never used.
pub fn lintCommand(env: Env, args: []const []const u8) Io.Writer.Error!u8 {
    return run(env, args, .lint);
}

fn run(env: Env, args: []const []const u8, mode: Mode) Io.Writer.Error!u8 {
    const word = @tagName(mode);
    var check_only = false;
    var paths: std.ArrayList([]const u8) = .empty;
    var arena_state: std.heap.ArenaAllocator = .init(env.gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    for (args) |a| {
        if (mode == .fmt and std.mem.eql(u8, a, "--check")) {
            check_only = true;
            continue;
        }
        collect(env, arena, a, &paths) catch |err| {
            try env.out.print("{s}: {s}: cannot read: {s}\n", .{ word, a, @errorName(err) });
            return cli.exit_no_input;
        };
    }
    if (paths.items.len == 0) {
        try env.out.print("{s}: usage: {s} {s}<file.eve | folder>...\n", .{ word, word, if (mode == .fmt) "[--check] " else "" });
        return cli.exit_usage;
    }
    var status: u8 = 0;
    var changed: usize = 0;
    for (paths.items) |path| {
        const src = Io.Dir.cwd().readFileAlloc(env.io, path, arena, .limited(16 << 20)) catch |err| {
            try env.out.print("{s}: cannot read: {s}\n", .{ path, @errorName(err) });
            status = @max(status, cli.exit_no_input);
            continue;
        };
        var diag: parser.Diag = .{};
        const tree = parser.parseSyntax(arena, src, &diag) catch |err| switch (err) {
            error.Syntax => {
                try env.out.print("{s}:{d}:{d}: error: {s}\n", .{ path, diag.line, diag.col, diag.message() });
                status = @max(status, cli.exit_syntax);
                continue;
            },
            error.OutOfMemory => {
                try env.out.print("{s}: out of memory\n", .{path});
                status = @max(status, cli.exit_no_input);
                continue;
            },
        };
        switch (mode) {
            .fmt => {
                const text = fmt.format(arena, src) catch {
                    try env.out.print("{s}: out of memory\n", .{path});
                    return cli.exit_no_input;
                };
                if (std.mem.eql(u8, text, src)) continue;
                changed += 1;
                if (check_only) {
                    try env.out.print("{s}: not formatted\n", .{path});
                    status = @max(status, exit_findings);
                    continue;
                }
                Io.Dir.cwd().writeFile(env.io, .{ .sub_path = path, .data = text }) catch |err| {
                    try env.out.print("{s}: cannot write: {s}\n", .{ path, @errorName(err) });
                    status = @max(status, cli.exit_cant_create);
                    continue;
                };
                try env.out.print("{s}: formatted\n", .{path});
            },
            .lint => {
                const found = lint.lint(arena, tree) catch {
                    try env.out.print("{s}: out of memory\n", .{path});
                    return cli.exit_no_input;
                };
                for (found) |f| {
                    try env.out.print("{s}:{d}:{d}: warning: {s} '{s}' is never used\n", .{ path, f.line, f.col, f.what, f.name });
                    changed += 1;
                }
                if (found.len > 0) status = @max(status, exit_findings);
            },
        }
    }
    switch (mode) {
        .fmt => try env.out.print("fmt: {d} file(s), {d} {s}\n", .{ paths.items.len, changed, if (check_only) "not formatted" else "changed" }),
        .lint => try env.out.print("lint: {d} file(s), {d} warning(s)\n", .{ paths.items.len, changed }),
    }
    return status;
}

test "fmt --check reports a file that would change and fmt writes it" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "a.eve", .data = "primary aspect a is  \n  process main is\n    over;\n  return;\nend a;\n\n\n" });
    var buf: [2048]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    const env: Env = .{ .io = std.testing.io, .gpa = std.testing.allocator, .out = &w };
    const dir = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(dir);
    const path = try std.fs.path.join(std.testing.allocator, &.{ dir, "a.eve" });
    defer std.testing.allocator.free(path);
    try std.testing.expectEqual(@as(u8, exit_findings), try fmtCommand(env, &.{ "--check", path }));
    w = .fixed(&buf);
    try std.testing.expectEqual(@as(u8, 0), try fmtCommand(env, &.{path}));
    w = .fixed(&buf);
    try std.testing.expectEqual(@as(u8, 0), try fmtCommand(env, &.{ "--check", path }));
}
