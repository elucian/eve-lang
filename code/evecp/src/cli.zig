//! @eve-module evecp.cli
//! @spec manual/usage.md
//! @feature F-TLS-23
//! @decision D-198
//! @tests code/evecp/src/cli.zig
//! The commands of the compiler: `check`, `doc` and `project init|new`. They are written once, here, and run in two places:
//! the program `evecp` (`main.zig`) and the `eve` command (`eve cp ...`, `eve check ...`, `code/eve/src/cp_cmds.zig`), which calls
//! these functions in its own process. Both give the same text and the same exit status.
const std = @import("std");
const Io = std.Io;
const evecm = @import("evecm");
const parser = @import("parser.zig");
const doc = @import("doc.zig");
const scaffold = @import("scaffold.zig");
const analyzer = @import("analyze.zig");
const emitter = @import("emit.zig");
const tools = @import("tools.zig");

/// Exit statuses (the codes of `sysexits.h`, as the manual lists them).
pub const exit_usage = evecm.config.exit_usage;
/// A syntax error in a script.
pub const exit_syntax = 65;
/// A file that cannot be read.
pub const exit_no_input = 66;
/// A file or folder that cannot be made.
pub const exit_cant_create = 73;

/// What a command needs from the program that runs it: files, memory and a place to write.
pub const Env = struct {
    io: Io,
    gpa: std.mem.Allocator,
    out: *Io.Writer,
};

/// The commands of `evecp`, one per line, as `evecp` prints them.
pub const usage =
    \\usage: evecp <command> [arguments]
    \\  check <file.eve>...                 check the syntax of scripts, run nothing (exit 65 on a syntax error)
    \\  disasm <file.eve>...                 the bytecode of scripts as a listing (stage B5.2: the core of level 1)
    \\  doc <folder | file.eve> [folder]    write Markdown documentation of a .eve file or of the .eve files of a folder
    \\  outline <file.eve>...                the aspects, classes and subprograms of scripts, nested, with their lines
    \\  symbols <file.eve>...               the same as a flat list: line:col, kind, name, container
    \\  fmt [--check] <file.eve | folder>... write the layout of scripts (exit 1 with --check when a file would change)
    \\  lint <file.eve | folder>...         the names that are declared and never used (exit 1 when there are any)
    \\  project init <folder>               make a project with the standard layout, keep the files that exist
    \\  project new <folder>                the same, but the folder must not exist or must be empty
    \\  -v, --version                       the version
    \\  -h, --help                          this text
    \\
;

/// Run the command named by the first word of `args` and give its exit status.
// @eve-impl evecp <command>
// @see code/evecp/src/main.zig:main
pub fn run(env: Env, args: []const []const u8) Io.Writer.Error!u8 {
    if (args.len == 0) {
        try env.out.writeAll(usage);
        return exit_usage;
    }
    const word = args[0];
    const rest = args[1..];
    if (std.mem.eql(u8, word, "check")) return check(env, rest);
    if (std.mem.eql(u8, word, "disasm")) return disasm(env, rest);
    if (std.mem.eql(u8, word, "doc")) return docs(env, rest);
    if (std.mem.eql(u8, word, "fmt")) return tools.fmtCommand(env, rest);
    if (std.mem.eql(u8, word, "lint")) return tools.lintCommand(env, rest);
    if (std.mem.eql(u8, word, "project")) return project(env, rest);
    if (std.mem.eql(u8, word, "outline")) return outline(env, rest, false);
    if (std.mem.eql(u8, word, "symbols")) return outline(env, rest, true);
    try env.out.print("evecp: unknown command '{s}'\n", .{word});
    try env.out.writeAll(usage);
    return exit_usage;
}

// The message format `file:line:col: error: text` is the one editors and CI tools understand.
// `worst` keeps the highest status, so a run over many files ends with the most serious problem.
/// `check`: parse each file without executing it. Status 65 if any has a syntax error.
// @eve-fn cp.check
// @spec spec/syntax/grammar.md
// @test check gives the status of the worst file
pub fn check(env: Env, args: []const []const u8) Io.Writer.Error!u8 {
    if (args.len == 0) {
        try env.out.writeAll("check: file name missing\n");
        return exit_usage;
    }
    var worst: u8 = 0;
    for (args) |path| {
        const src = Io.Dir.cwd().readFileAlloc(env.io, path, env.gpa, .limited(16 << 20)) catch |err| {
            try env.out.print("{s}: cannot read: {s}\n", .{ path, @errorName(err) });
            worst = @max(worst, exit_no_input);
            continue;
        };
        defer env.gpa.free(src);
        var diag: parser.Diag = .{};
        if (parser.check(env.gpa, src, &diag)) {
            try env.out.print("{s}: ok\n", .{path});
        } else |err| switch (err) {
            error.Syntax => {
                try env.out.print("{s}:{d}:{d}: error: {s}\n", .{ path, diag.line, diag.col, diag.message() });
                worst = @max(worst, exit_syntax);
            },
            error.OutOfMemory => {
                try env.out.print("{s}: out of memory\n", .{path});
                worst = @max(worst, exit_no_input);
            },
        }
    }
    return worst;
}

/// `disasm`: compile each file to bytecode and write the listing; status 65 on a syntax error, 70 when the emitter does not know a construct yet.
// @eve-fn cp.disasm
// @feature F-VM-04
// @see code/evecp/src/emit.zig:compile
pub fn disasm(env: Env, args: []const []const u8) Io.Writer.Error!u8 {
    if (args.len == 0) {
        try env.out.writeAll("disasm: file name missing\n");
        return exit_usage;
    }
    var worst: u8 = 0;
    for (args) |path| {
        const src = Io.Dir.cwd().readFileAlloc(env.io, path, env.gpa, .limited(16 << 20)) catch |err| {
            try env.out.print("{s}: cannot read: {s}\n", .{ path, @errorName(err) });
            worst = @max(worst, exit_no_input);
            continue;
        };
        defer env.gpa.free(src);
        var arena: std.heap.ArenaAllocator = .init(env.gpa);
        defer arena.deinit();
        var diag: parser.Diag = .{};
        const tree = parser.parse(arena.allocator(), src, &diag) catch |err| switch (err) {
            error.Syntax => {
                try env.out.print("{s}:{d}:{d}: error: {s}\n", .{ path, diag.line, diag.col, diag.message() });
                worst = @max(worst, exit_syntax);
                continue;
            },
            error.OutOfMemory => {
                try env.out.print("{s}: out of memory\n", .{path});
                worst = @max(worst, exit_no_input);
                continue;
            },
        };
        var why: emitter.Diag = .{};
        const c = emitter.compile(arena.allocator(), tree, &why) catch |err| switch (err) {
            error.Unsupported => {
                try env.out.print("{s}:{d}: bytecode: {s} is not supported yet\n", .{ path, why.line, why.message });
                worst = @max(worst, 70);
                continue;
            },
            error.OutOfMemory => {
                try env.out.print("{s}: out of memory\n", .{path});
                worst = @max(worst, exit_no_input);
                continue;
            },
        };
        try evecm.chunk.disassemble(&c, env.out);
    }
    return worst;
}

/// `outline` and `symbols`: what an editor shows of each file (`analyze.zig`): the error if the text is not Eve, else the
/// symbols, nested (`outline`) or as one flat list (`symbols`).
// @eve-fn cp.outline
// @feature F-TLS-19
pub fn outline(env: Env, args: []const []const u8, flat: bool) Io.Writer.Error!u8 {
    if (args.len == 0) {
        try env.out.print("{s}: file name missing\n", .{if (flat) "symbols" else "outline"});
        return exit_usage;
    }
    var worst: u8 = 0;
    for (args) |path| {
        const src = Io.Dir.cwd().readFileAlloc(env.io, path, env.gpa, .limited(16 << 20)) catch |err| {
            try env.out.print("{s}: cannot read: {s}\n", .{ path, @errorName(err) });
            worst = @max(worst, exit_no_input);
            continue;
        };
        defer env.gpa.free(src);
        var result = analyzer.analyze(env.gpa, src) catch {
            try env.out.print("{s}: out of memory\n", .{path});
            worst = @max(worst, exit_no_input);
            continue;
        };
        defer result.deinit();
        for (result.diagnostics) |d| {
            try env.out.print("{s}:{d}:{d}: error: {s}\n", .{ path, d.line, d.col, d.message });
            worst = @max(worst, exit_syntax);
        }
        if (args.len > 1 and result.diagnostics.len == 0) try env.out.print("{s}:\n", .{path});
        for (result.symbols, 0..) |s, i| {
            _ = i;
            if (flat) {
                const container = if (s.parent) |p| result.symbols[p].name else "-";
                try env.out.print("{d}:{d}\t{s}\t{s}\t{s}\n", .{ s.line, s.col, @tagName(s.kind), s.name, container });
            } else {
                var depth: usize = 0;
                var p = s.parent;
                while (p) |at| : (p = result.symbols[at].parent) depth += 1;
                try env.out.splatByteAll(' ', depth * 2);
                try env.out.print("{s} {s}  ({d}:{d})\n", .{ @tagName(s.kind), s.name, s.line, s.col });
            }
        }
    }
    return worst;
}

/// `doc`: write the Markdown documentation of a `.eve` file, or of the `.eve` files of a folder.
// @eve-fn cp.doc
// @spec manual/usage.md
pub fn docs(env: Env, args: []const []const u8) Io.Writer.Error!u8 {
    if (args.len == 0 or args.len > 2) {
        try env.out.writeAll("doc: usage: doc <folder | file.eve> [output folder, default doc]\n");
        return exit_usage;
    }
    const out_path = if (args.len == 2) args[1] else "doc";
    const pages = doc.generate(env.io, env.gpa, args[0], out_path, env.out) catch |err| switch (err) {
        error.WriteFailed => |e| return e,
        else => {
            try env.out.print("doc: {s}: {s}\n", .{ args[0], @errorName(err) });
            return exit_no_input;
        },
    };
    if (pages == 0) try env.out.print("doc: no .eve file in {s}\n", .{args[0]});
    return 0;
}

/// `project init <folder>` and `project new <folder>`: make a project with the standard layout
/// (design/design-project-layout.md). `init` also works on an existing project and keeps its files;
/// `new` fails when the folder exists and is not empty.
// @eve-fn cp.project
// @feature F-TLS-23
pub fn project(env: Env, args: []const []const u8) Io.Writer.Error!u8 {
    const is_new = args.len == 2 and std.mem.eql(u8, args[0], "new");
    if (args.len != 2 or !(is_new or std.mem.eql(u8, args[0], "init"))) {
        try env.out.writeAll("project: usage: project init <folder> | project new <folder>\n");
        return exit_usage;
    }
    if (is_new) {
        const free = scaffold.isEmptyOrAbsent(env.io, Io.Dir.cwd(), args[1]) catch false;
        if (!free) {
            try env.out.print("project: {s} exists and is not empty (project init keeps its files)\n", .{args[1]});
            return exit_cant_create;
        }
    }
    const result = scaffold.init(env.io, env.gpa, Io.Dir.cwd(), args[1], true, env.out) catch |err| switch (err) {
        error.WriteFailed => |e| return e,
        else => {
            try env.out.print("project: {s}: {s}\n", .{ args[1], @errorName(err) });
            return exit_cant_create;
        },
    };
    try env.out.print("project {s}: {s}: {d} created, {d} kept\n", .{ args[0], args[1], result.created, result.kept });
    return 0;
}

// @test the commands answer a missing argument, an unknown word and a missing file with the right status and text
test "usage errors and a file that does not exist" {
    var buf: [2048]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    const env: Env = .{ .io = std.testing.io, .gpa = std.testing.allocator, .out = &w };
    try std.testing.expectEqual(@as(u8, exit_usage), try run(env, &.{}));
    try std.testing.expect(std.mem.startsWith(u8, w.buffered(), "usage: evecp"));
    w = .fixed(&buf);
    try std.testing.expectEqual(@as(u8, exit_usage), try run(env, &.{"frobnicate"}));
    try std.testing.expect(std.mem.indexOf(u8, w.buffered(), "unknown command 'frobnicate'") != null);
    w = .fixed(&buf);
    try std.testing.expectEqual(@as(u8, exit_usage), try run(env, &.{"check"}));
    w = .fixed(&buf);
    try std.testing.expectEqual(@as(u8, exit_no_input), try run(env, &.{ "check", "no/such/file.eve" }));
    try std.testing.expect(std.mem.indexOf(u8, w.buffered(), "no/such/file.eve: cannot read") != null);
}

// @test check gives the status of the worst file
test "check: ok, syntax error, and the worst status wins" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "good.eve", .data = "primary aspect good is\n  process main is\n    over;\n  return;\nend good;\n" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "bad.eve", .data = "primary aspect bad is\n  process main is\n    print \"x\n" });
    var buf: [2048]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    const env: Env = .{ .io = std.testing.io, .gpa = std.testing.allocator, .out = &w };
    const dir = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(dir);
    const good = try std.fs.path.join(std.testing.allocator, &.{ dir, "good.eve" });
    defer std.testing.allocator.free(good);
    const bad = try std.fs.path.join(std.testing.allocator, &.{ dir, "bad.eve" });
    defer std.testing.allocator.free(bad);
    try std.testing.expectEqual(@as(u8, 0), try check(env, &.{good}));
    try std.testing.expect(std.mem.endsWith(u8, std.mem.trimEnd(u8, w.buffered(), "\n"), "good.eve: ok"));
    w = .fixed(&buf);
    try std.testing.expectEqual(@as(u8, exit_syntax), try check(env, &.{ good, bad }));
    try std.testing.expect(std.mem.indexOf(u8, w.buffered(), "error:") != null);
}
