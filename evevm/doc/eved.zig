//! `eved`: the Eve documentation tool.
//!
//! Reads Eve source files and writes Markdown: for every declaration it keeps the comment
//! written right above it, and the signature line. Documentation comments are:
//!
//!   - `#` and `##` lines at column 0 (the `#!` first line is not documentation);
//!   - `**` to the end of the line;
//!   - `/* ... */` blocks.
//!
//! Expression comments `(** ... **)` are ignored.
//!
//!   eved <source-dir> <output-dir>
//!
//! One `<name>.md` is written for each `<name>.eve` found directly in the source folder.
const std = @import("std");
const Io = std.Io;

/// Words that start a declaration worth documenting.
const declarations = [_][]const u8{
    "driver", "aspect",  "module", "class", "trait", "function",
    "method", "process", "routine", "set",  "def",
};

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

/// Strips the delimiters and the frame characters people draw inside a block comment.
fn blockText(line: []const u8) []const u8 {
    var t = std.mem.trim(u8, line, " \t\r");
    if (std.mem.startsWith(u8, t, "/*")) t = t[2..];
    if (std.mem.endsWith(u8, t, "*/")) t = t[0 .. t.len - 2];
    return std.mem.trim(u8, t, " \t\r|-*=");
}

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

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 3) {
        std.debug.print("usage: eved <source-dir> <output-dir>\n", .{});
        std.process.exit(2);
    }

    const cwd = Io.Dir.cwd();
    var src_dir = try cwd.openDir(io, args[1], .{ .iterate = true });
    defer src_dir.close(io);
    try cwd.createDirPath(io, args[2]);
    var out_dir = try cwd.openDir(io, args[2], .{});
    defer out_dir.close(io);

    var it = src_dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".eve")) continue;
        const stem = entry.name[0 .. entry.name.len - 4];
        const source = try src_dir.readFileAlloc(io, entry.name, arena, .limited(16 * 1024 * 1024));
        var buf: Io.Writer.Allocating = .init(arena);
        try render(source, stem, &buf.writer);
        const out_name = try std.fmt.allocPrint(arena, "{s}.md", .{stem});
        try out_dir.writeFile(io, .{ .sub_path = out_name, .data = buf.written() });
        std.debug.print("eved: {s} -> {s}\n", .{ entry.name, out_name });
    }
}

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
