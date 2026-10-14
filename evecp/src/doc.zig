//! Documentation of Eve source files: the `doc` command of `eve` (`eve --doc`, D-082).
//!
//! Reads Eve source files and writes Markdown: for every declaration it keeps the comment
//! written right above it, and the signature line. Documentation comments are:
//!
//!   - `#` and `##` lines at column 0 (the `#!` first line is not documentation);
//!   - `**` to the end of the line;
//!   - `/* ... */` blocks.
//!
//! Expression comments `(** ... **)` are ignored. One `<name>.md` is written for each
//! `<name>.eve`: the files found directly in a folder, or one file given by its path.
const std = @import("std");
const Io = std.Io;

// Zig tip: `[_][]const u8{ ... }` is an array of strings whose length the compiler counts
// (`_`). A `const` at file level is built once, at compile time, and stored in the program.
/// Words that start a declaration worth documenting.
const declarations = [_][]const u8{
    "driver", "aspect",  "module", "class", "trait", "function",
    "method", "process", "routine", "set",  "def",  "service",
    "generator",
};

// Zig tip: `var rest = ...` makes a variable we can change; `rest = rest[1..]` re-slices it
// to drop the first byte, without copying the text. A slice is only a pointer and a length,
// so slicing is free. `rest[word.len]` reads one byte; Zig checks the index at run time in
// Debug builds, which is why the length test comes first (`and` stops early).
fn startsDeclaration(line: []const u8) bool {
    var rest = std.mem.trimStart(u8, line, " \t");
    // `external` in front of a signature: implemented in Zig by the virtual machine.
    if (std.mem.startsWith(u8, rest, "external ")) return true;
    if (std.mem.startsWith(u8, rest, ".")) rest = rest[1..]; // public member prefix
    for (declarations) |word| {
        if (std.mem.startsWith(u8, rest, word) and rest.len > word.len and
            (rest[word.len] == ' ' or rest[word.len] == '\t')) return true;
    }
    return false;
}

// Zig tip: the return type `?[]const u8` is an optional: the text of the comment, or `null`
// when the line is not a comment. The caller unwraps it with `if (text) |t| { ... }`.
/// Text of a line comment: `#` or `##` at column 0, or `**` after the indentation.
fn lineComment(line: []const u8) ?[]const u8 {
    if (line.len > 0 and line[0] == '#') {
        if (line.len > 1 and line[1] == '!') return null;
        return std.mem.trim(u8, std.mem.trimStart(u8, line, "#"), " \t\r");
    }
    const t = std.mem.trimStart(u8, line, " \t");
    if (!std.mem.startsWith(u8, t, "**")) return null;
    return std.mem.trim(u8, t[2..], " \t\r");
}

// Zig tip: `t[0 .. t.len - 2]` is a slice with an end index: everything but the last two bytes.
// `std.mem.trim` takes the set of characters to cut as a string: here blanks and the frame
// characters `| - * =`.
/// Strips the delimiters and the frame characters people draw inside a block comment.
fn blockText(line: []const u8) []const u8 {
    var t = std.mem.trim(u8, line, " \t\r");
    if (std.mem.startsWith(u8, t, "/*")) t = t[2..];
    if (std.mem.endsWith(u8, t, "*/")) t = t[0 .. t.len - 2];
    return std.mem.trim(u8, t, " \t\r|-*=");
}

// Zig tip: `var comment: [64][]const u8 = undefined;` is a fixed array of 64 slices on the stack:
// no allocation. `undefined` means "not set yet"; only the first `count` entries are ever read.
// `std.mem.splitScalar` returns an iterator; `while (lines.next()) |raw|` runs until `next()`
// returns null. The function writes into any `*Io.Writer`: a file, a buffer in memory, stdout.
/// Writes the Markdown page of one Eve source. A comment is documentation when it comes right
/// above a declaration: any other line of code between them cancels it.
pub fn render(source: []const u8, name: []const u8, out: *Io.Writer) Io.Writer.Error!void {
    try out.print("# {s}\n\n", .{name});
    var comment: [64][]const u8 = undefined;
    var count: usize = 0;
    var first = true;
    var in_block = false;
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        const trimmed = std.mem.trim(u8, line, " \t");
        if (!in_block and std.mem.startsWith(u8, trimmed, "(**") and std.mem.endsWith(u8, trimmed, "**)")) continue;
        var text: ?[]const u8 = null;
        if (in_block) {
            text = blockText(line);
            if (std.mem.indexOf(u8, line, "*/") != null) in_block = false;
        } else if (std.mem.startsWith(u8, trimmed, "/*")) {
            text = blockText(line);
            in_block = std.mem.indexOf(u8, trimmed[2..], "*/") == null;
        } else {
            text = lineComment(line);
        }
        if (text) |t| {
            if (t.len > 0 and count < comment.len) {
                comment[count] = t;
                count += 1;
            }
        } else if (startsDeclaration(line)) {
            // The first declaration is the script header: its comment is the page summary.
            if (first) {
                first = false;
            } else {
                try out.print("## `{s}`\n\n", .{trimmed});
            }
            for (comment[0..count]) |c| try out.print("{s}\n", .{c});
            if (count > 0) try out.writeAll("\n");
            count = 0;
        } else if (trimmed.len != 0 and !std.mem.startsWith(u8, line, "#!")) {
            count = 0;
        }
    }
}

// Zig tip: `std.mem.lastIndexOfAny` returns the position of the last `/` or `\`, or null;
// `orelse` turns the null into a default. Windows accepts both separators, so both are cut.
/// The name of a page: the file name of `path` without its folder and without `.eve`.
fn stem(path: []const u8) []const u8 {
    const start = if (std.mem.lastIndexOfAny(u8, path, "/\\")) |i| i + 1 else 0;
    const base = path[start..];
    return if (std.mem.endsWith(u8, base, ".eve")) base[0 .. base.len - 4] else base;
}

// Zig tip: an `ArenaAllocator` hands out memory from big blocks and frees everything in one
// `deinit`, so the file contents and the pages need no `free` each; `defer` pairs the arena
// with its release. `Io.Writer.Allocating` is a writer that grows a buffer in memory;
// `written()` is what it holds. The return type `!usize` has an inferred error set: the compiler
// collects every error that a `try` in the body can pass up (missing folder, read or write
// failure, out of memory) and the caller can `switch` on them.
/// Writes `<out_path>/<name>.md` for the `.eve` file `source`, or for every `.eve` file directly
/// in the folder `source`. Logs one line per page on `log` and returns the number of pages.
pub fn generate(io: Io, gpa: std.mem.Allocator, source: []const u8, out_path: []const u8, log: *Io.Writer) !usize {
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const cwd = Io.Dir.cwd();
    try cwd.createDirPath(io, out_path);
    var out_dir = try cwd.openDir(io, out_path, .{});
    defer out_dir.close(io);

    if (std.mem.endsWith(u8, source, ".eve")) {
        const text = try cwd.readFileAlloc(io, source, arena, .limited(16 << 20));
        try writePage(io, arena, out_dir, text, stem(source), out_path, log);
        return 1;
    }

    var src_dir = try cwd.openDir(io, source, .{ .iterate = true });
    defer src_dir.close(io);
    var pages: usize = 0;
    var it = src_dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".eve")) continue;
        const text = try src_dir.readFileAlloc(io, entry.name, arena, .limited(16 << 20));
        try writePage(io, arena, out_dir, text, stem(entry.name), out_path, log);
        pages += 1;
    }
    return pages;
}

// Zig tip: `Io.Dir` is passed by value: it is a small handle (the open folder), cheap to copy.
// `std.fmt.allocPrint` formats into new memory from the allocator, here the arena of `generate`.
/// Renders one source and writes `<name>.md` into `out_dir`.
fn writePage(io: Io, arena: std.mem.Allocator, out_dir: Io.Dir, text: []const u8, name: []const u8, out_path: []const u8, log: *Io.Writer) !void {
    var buf: Io.Writer.Allocating = .init(arena);
    try render(text, name, &buf.writer);
    const out_name = try std.fmt.allocPrint(arena, "{s}.md", .{name});
    try out_dir.writeFile(io, .{ .sub_path = out_name, .data = buf.written() });
    try log.print("doc: {s}.eve -> {s}/{s}\n", .{ name, out_path, out_name });
}

// Zig tip: `++` joins string literals at compile time, so a long test input can be split over
// lines. `std.testing.allocator` fails the test if memory is not freed, hence `defer buf.deinit()`.
test "documents a declaration with its comment" {
    const src = "** Strings.\nmodule strings is\n\n  ** Remove blanks at both ends.\n" ++
        "  function .trim(s: String) => (String) is\n  return;\nend strings;\n";
    var buf: Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    try render(src, "strings", &buf.writer);
    try std.testing.expectEqualStrings(
        "# strings\n\nStrings.\n\n## `function .trim(s: String) => (String) is`\n\nRemove blanks at both ends.\n\n",
        buf.written(),
    );
}

// Zig tip: this test relies on the same features as the test above: see the tip there.
test "reads #, ## and block comments, ignores expression comments" {
    const src = "#! free script\n# Title\n## Subtitle\n/* block\n | framed */\nmodule m is\n" ++
        "  (** inline **)\n  ** about f\n  function .f() => (Integer) is\nend m;\n";
    var buf: Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    try render(src, "m", &buf.writer);
    try std.testing.expectEqualStrings(
        "# m\n\nTitle\nSubtitle\nblock\nframed\n\n## `function .f() => (Integer) is`\n\nabout f\n\n",
        buf.written(),
    );
}

// Zig tip: `expectEqualStrings(expected, actual)` compares the contents of two slices and
// prints both when they differ.
test "the page name is the file name without folder and extension" {
    try std.testing.expectEqualStrings("io", stem("lib/io.eve"));
    try std.testing.expectEqualStrings("io", stem("C:\\eve\\lib\\io.eve"));
    try std.testing.expectEqualStrings("io", stem("io.eve"));
}
