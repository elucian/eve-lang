//! `project init <folder>`: the setup of a new Eve project (plan/design-project-layout.md). It makes
//! the folders of the standard layout, the configuration file, the project description and a first
//! driver, and starts a Git repository when the folder is not in one. It never overwrites: a file
//! that exists is kept, so the command can run again on a project to add what is missing.
const std = @import("std");
const Io = std.Io;
const parser = @import("parser.zig");
const version = @import("evecm").version;

/// The layout version written in `meta/project.json`.
pub const layout_version = 1;

// Zig tip: a `const` at file level is evaluated at compile time, so these tables and texts cost
// nothing at run time. `[_][]const u8{ ... }` is an array of strings whose length the compiler counts.
/// A folder of the layout and the reason it exists. An empty folder gets a `.gitkeep` file, because
/// git does not keep an empty folder.
const folders = [_][]const u8{
    "db", // the core database (SQLite): logs and metadata, never data (D-156, D-159)
    "log", // the minimal fallback log: fatal errors only
    "meta", // the description of the project, mappings and schema versions
    "data/in", // files that the jobs read
    "data/out", // files that the jobs write
    "test", // the files of the test databases (evedb), not versioned
    "asp", // aspects (D-160)
    "lib", // modules (D-160)
    "src", // other sources of the project (D-160)
    "doc", // documentation, written by `eve --doc` (D-160)
    "web", // templates and static files of the web part (D-160)
};

const gitignore =
    \\# Eve project: the files that a run makes
    \\db/*.db
    \\db/*.db-*
    \\log/*.log
    \\log/*.log.*
    \\log/*.db
    \\data/in/*
    \\data/out/*
    \\test/*
    \\!.gitkeep
    \\
;

// Zig tip: a format string is checked at compile time; `{{` writes a literal brace, so JSON can be
// a format string. The format of `allocPrint` must be known at compile time (`comptime fmt`).
const project_json_fmt =
    \\{{
    \\  "name": "{s}",
    \\  "layout": {d},
    \\  "eve": "{s}"
    \\}}
    \\
;

const config_fmt =
    \\# Configuration of the project {s} (spec/library/database.md#configuration-evecfg)
    \\** The core database: logs and metadata, read as $EVE_CORE_DB.
    \\core_db = "db/local.db"
    \\
    \\** The minimal fallback log: fatal crashes, unhandled panics and startup failures only.
    \\** Plain text, append-only; at the size limit the file is renamed to <file>.1 and a new one starts.
    \\fallback_log = "log/eve.log"
    \\fallback_log_max = "5MB"
    \\
    \\** The test database (DuckDB), served by `eve db serve --test` (database.md, layers).
    \\** database "check" = "evedb://localhost/check"
    \\
;

// a driver starts with its title, `# …`: a `#!` line would make it a free script or a macro (lexical.md, file header)
const driver_fmt =
    \\# The main script of the project {s}.
    \\driver {s} is
    \\  process main is
    \\    print "{s}: ready";
    \\  return;
    \\end {s};
    \\
;

// Zig tip: the counters are `usize`, the type of lengths and indexes. Fields with a default
// (`= 0`) let `.{}` build a struct that starts at zero.
/// What `init` did.
pub const Result = struct {
    created: usize = 0,
    kept: usize = 0,
    git: Git = .skipped,
};

// Zig tip: an `enum` is a closed set of names; `switch` over it must list every case. Here it says
// what the Git step did.
/// What `init` did about Git.
pub const Git = enum {
    /// not asked (the unit tests)
    skipped,
    /// the folder is already inside a repository: nothing to do
    existing,
    /// `git init` made a repository
    initialized,
    /// the `git` program was not found or failed
    missing,
};

// Zig tip: the name of a driver must be an identifier, but a folder can be called anything. This
// function builds a new text in memory the caller owns (`gpa.alloc`), so it returns an error union
// with `Allocator.Error` (only out of memory can fail). `for (name, 0..) |c, i|` walks the bytes
// together with their index; `std.ascii.isAlphanumeric` tests one byte.
/// The driver name for a folder: its last component with every character that an identifier cannot
/// have turned into `_`, and `p_` in front of a name that starts with a digit. `project` when empty.
pub fn driverName(gpa: std.mem.Allocator, folder: []const u8) std.mem.Allocator.Error![]u8 {
    const trimmed = std.mem.trimEnd(u8, folder, "/\\");
    const last = if (std.mem.lastIndexOfAny(u8, trimmed, "/\\")) |i| trimmed[i + 1 ..] else trimmed;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    if (last.len > 0 and std.ascii.isDigit(last[0])) try out.appendSlice(gpa, "p_");
    for (last) |c| try out.append(gpa, if (std.ascii.isAlphanumeric(c) or c == '_') c else '_');
    // A name made only of `_` (for example ".") says nothing: use the default.
    if (std.mem.indexOfNone(u8, out.items, "_") == null) {
        out.clearRetainingCapacity();
        try out.appendSlice(gpa, "project");
    }
    return out.toOwnedSlice(gpa);
}

// Zig tip: `access` answers with an error when the path is missing, and `catch` turns that into a
// boolean: `access(...) catch return false` returns false from the function on any error, and falls
// through to `true` when the call succeeded. A probe whose only question is "is it there?" can drop the reason of the error.
fn exists(io: Io, base: Io.Dir, path: []const u8) bool {
    base.access(io, path, .{}) catch return false;
    return true;
}

// Zig tip: `anytype` for `args` lets one function format any tuple, like `allocPrint` does; here the
// values are only passed through. The arena (see the tip in doc.zig) frees every path and text at
// once, so this function never frees what it builds.
fn putFile(
    io: Io,
    arena: std.mem.Allocator,
    base: Io.Dir,
    root: []const u8,
    rel: []const u8,
    data: []const u8,
    out: *Io.Writer,
    result: *Result,
) !void {
    const path = try std.fmt.allocPrint(arena, "{s}/{s}", .{ root, rel });
    if (exists(io, base, path)) {
        result.kept += 1;
        try out.print("  keep    {s}\n", .{path});
        return;
    }
    try base.writeFile(io, .{ .sub_path = path, .data = data });
    result.created += 1;
    try out.print("  create  {s}\n", .{path});
}

// Zig tip: `std.process.run` starts a program and waits for it. It returns the exit state in a
// tagged union (`Term`): `.exited` carries the code. A program that cannot start (not installed) is
// an error value, so `catch return null` says "no answer". The output buffers belong to the caller,
// hence the two `defer gpa.free`. `.cwd = .{ .dir = d }` starts the child inside the directory `d`.
/// Run `git <args>` in `dir`; the exit code, or null when Git can not be started.
fn git(io: Io, gpa: std.mem.Allocator, dir: Io.Dir, args: []const []const u8) ?u8 {
    var argv: [4][]const u8 = undefined;
    argv[0] = "git";
    for (args, 0..) |a, i| argv[i + 1] = a;
    const r = std.process.run(gpa, io, .{ .argv = argv[0 .. args.len + 1], .cwd = .{ .dir = dir } }) catch return null;
    defer gpa.free(r.stdout);
    defer gpa.free(r.stderr);
    return switch (r.term) {
        .exited => |code| code,
        else => null,
    };
}

// Zig tip: `openDir(..., .{ .iterate = true })` opens a folder so that `iterate()` can list it; the
// first `next()` that returns an entry proves the folder is not empty. A folder that does not exist
// is an error (`FileNotFound`), which here means "empty enough".
/// True when `folder` does not exist or has nothing in it. `project new` needs this.
pub fn isEmptyOrAbsent(io: Io, base: Io.Dir, folder: []const u8) !bool {
    var dir = base.openDir(io, folder, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return true,
        else => return err,
    };
    defer dir.close(io);
    var it = dir.iterate();
    return (try it.next(io)) == null;
}

// Zig tip: a function that can fail in many ways (disk, memory, the output) can leave its error set
// to the compiler with `!Result`: the set is inferred from every `try` in the body. `base` is a
// directory handle, not a path: the folder is made inside it, which is what lets the tests use a
// temporary directory instead of the real working directory.
/// Make the project `folder` (inside `base`). Every action is logged on `out`.
pub fn init(io: Io, gpa: std.mem.Allocator, base: Io.Dir, folder: []const u8, use_git: bool, out: *Io.Writer) !Result {
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const root = std.mem.trimEnd(u8, folder, "/\\");
    const name = try driverName(arena, root);
    var result: Result = .{};

    try base.createDirPath(io, root);
    for (folders) |f| {
        const dir = try std.fmt.allocPrint(arena, "{s}/{s}", .{ root, f });
        try base.createDirPath(io, dir);
    }

    // The folders that hold no file of their own get the `.gitkeep`.
    for (folders) |f| {
        if (std.mem.eql(u8, f, "meta")) continue;
        const keep = try std.fmt.allocPrint(arena, "{s}/.gitkeep", .{f});
        try putFile(io, arena, base, root, keep, "", out, &result);
    }

    const driver_file = try std.fmt.allocPrint(arena, "{s}.eve", .{name});
    try putFile(io, arena, base, root, driver_file, try std.fmt.allocPrint(arena, driver_fmt, .{ name, name, name, name }), out, &result);
    try putFile(io, arena, base, root, "eve.cfg", try std.fmt.allocPrint(arena, config_fmt, .{name}), out, &result);
    try putFile(io, arena, base, root, "meta/project.json", try std.fmt.allocPrint(arena, project_json_fmt, .{ name, layout_version, version.version }), out, &result);
    try putFile(io, arena, base, root, ".gitignore", gitignore, out, &result);

    // Git: a folder inside a repository is left to it; otherwise start one (the .gitignore is there).
    if (use_git) {
        var dir = try base.openDir(io, root, .{});
        defer dir.close(io);
        if (git(io, gpa, dir, &.{ "rev-parse", "--git-dir" })) |code| {
            if (code == 0) {
                result.git = .existing;
                try out.writeAll("  git     inside a repository, kept\n");
            } else {
                const ok = (git(io, gpa, dir, &.{"init"}) orelse 1) == 0;
                result.git = if (ok) .initialized else .missing;
                try out.writeAll(if (ok) "  git     init\n" else "  git     init failed\n");
            }
        } else {
            result.git = .missing;
            try out.writeAll("  git     not found: install Git, then run git init\n");
        }
    }
    return result;
}

// Zig tip: a test is a block `test "name" { ... }` that `zig build test` runs; any error that
// escapes (`try`) fails it. `std.testing.tmpDir(.{})` makes a fresh directory and `defer
// tmp.cleanup()` removes it, so tests leave nothing behind. `std.testing.allocator` reports a leak
// as a failure, and `std.testing.io` is the `Io` that tests pass to code that touches files.
test "the driver name is an identifier made from the folder" {
    const a = std.testing.allocator;
    const cases = [_][2][]const u8{
        .{ "shop", "shop" },
        .{ "work/my-shop/", "my_shop" },
        .{ "C:\\eve\\2025 plan", "p_2025_plan" },
        .{ ".", "project" },
        .{ "", "project" },
    };
    for (cases) |c| {
        const got = try driverName(a, c[0]);
        defer a.free(got);
        try std.testing.expectEqualStrings(c[1], got);
    }
}

// Zig tip: `Io.Writer.Allocating` collects the log in memory (see doc.zig). `expect(cond)` fails
// the test when `cond` is false; `try` is needed because it returns an error then.
test "init makes the layout, the files parse, and a second run keeps everything" {
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var log: Io.Writer.Allocating = .init(a);
    defer log.deinit();

    const first = try init(std.testing.io, a, tmp.dir, "shop", false, &log.writer);
    try std.testing.expectEqual(@as(usize, 0), first.kept);
    try std.testing.expectEqual(@as(usize, 14), first.created);
    for ([_][]const u8{ "shop/shop.eve", "shop/eve.cfg", "shop/meta/project.json", "shop/.gitignore", "shop/data/in/.gitkeep", "shop/log/.gitkeep", "shop/test/.gitkeep", "shop/web/.gitkeep" }) |p| {
        try tmp.dir.access(std.testing.io, p, .{});
    }

    // The first driver must be a correct Eve script.
    const src = try tmp.dir.readFileAlloc(std.testing.io, "shop/shop.eve", a, .limited(1 << 16));
    defer a.free(src);
    var diag: parser.Diag = .{};
    try parser.check(a, src, &diag);

    // A file the author changed is not overwritten.
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "shop/eve.cfg", .data = "mine\n" });
    const second = try init(std.testing.io, a, tmp.dir, "shop/", false, &log.writer);
    try std.testing.expectEqual(@as(usize, 0), second.created);
    try std.testing.expectEqual(@as(usize, 14), second.kept);
    const cfg = try tmp.dir.readFileAlloc(std.testing.io, "shop/eve.cfg", a, .limited(1 << 16));
    defer a.free(cfg);
    try std.testing.expectEqualStrings("mine\n", cfg);
}

// Zig tip: `!` in front of a call negates its bool result; `try` goes first: `!try f()` would be
// written `!(try f())`, so the test writes the parentheses to be clear.
test "a folder is empty or absent until something is in it" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.testing.io;
    try std.testing.expect(try isEmptyOrAbsent(io, tmp.dir, "nothing"));
    try tmp.dir.createDirPath(io, "here");
    try std.testing.expect(try isEmptyOrAbsent(io, tmp.dir, "here"));
    try tmp.dir.writeFile(io, .{ .sub_path = "here/a.txt", .data = "x" });
    try std.testing.expect(!(try isEmptyOrAbsent(io, tmp.dir, "here")));
}
