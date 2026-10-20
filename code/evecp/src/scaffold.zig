//! `project init <folder>`: the setup of a new Eve project (design/design-project-layout.md). It makes
//! the folders of the standard layout, the configuration file, the project description and a first
//! primary aspect, and starts a Git repository when the folder is not in one. It never overwrites: a file
//! that exists is kept, so the command can run again on a project to add what is missing.
const std = @import("std");
const Io = std.Io;
const parser = @import("parser.zig");
const version = @import("evecm").version;

/// The layout version written in `meta/project.json`.
pub const layout_version = 1;

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

// the first aspect starts with its title, `# …`: a `#!` line is refused (lexical.md, file header)
const aspect_fmt =
    \\# The main script of the project {s}.
    \\primary aspect {s} is
    \\  process main is
    \\    print "{s}: ready";
    \\  return;
    \\end {s};
    \\
;

/// What `init` did.
pub const Result = struct {
    created: usize = 0,
    kept: usize = 0,
    git: Git = .skipped,
};

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

/// The root aspect name for a folder: its last component with every character that an identifier cannot
/// have turned into `_`, and `p_` in front of a name that starts with a digit. `project` when empty.
pub fn aspectName(gpa: std.mem.Allocator, folder: []const u8) std.mem.Allocator.Error![]u8 {
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

fn exists(io: Io, base: Io.Dir, path: []const u8) bool {
    base.access(io, path, .{}) catch return false;
    return true;
}

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

/// Make the project `folder` (inside `base`). Every action is logged on `out`.
pub fn init(io: Io, gpa: std.mem.Allocator, base: Io.Dir, folder: []const u8, use_git: bool, out: *Io.Writer) !Result {
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const root = std.mem.trimEnd(u8, folder, "/\\");
    const name = try aspectName(arena, root);
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

    const aspect_file = try std.fmt.allocPrint(arena, "{s}.eve", .{name});
    try putFile(io, arena, base, root, aspect_file, try std.fmt.allocPrint(arena, aspect_fmt, .{ name, name, name, name }), out, &result);
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

test "the aspect name is an identifier made from the folder" {
    const a = std.testing.allocator;
    const cases = [_][2][]const u8{
        .{ "shop", "shop" },
        .{ "work/my-shop/", "my_shop" },
        .{ "C:\\eve\\2025 plan", "p_2025_plan" },
        .{ ".", "project" },
        .{ "", "project" },
    };
    for (cases) |c| {
        const got = try aspectName(a, c[0]);
        defer a.free(got);
        try std.testing.expectEqualStrings(c[1], got);
    }
}

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

    // The first aspect must be a correct Eve script.
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
