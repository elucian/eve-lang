//! Line editor for the REPL prompt with Tab completion of file names (manual/usage.md).
//!
//! `check test/level1<Tab>` replaces the last word by the first `.eve` file (or sub-folder) of that
//! folder (`.cfg` files for `setup` and after `-s`: the caller says which extension); every further Tab shows the next one, and after the last one the first again. Any other
//! key ends the cycle. The editor is used only when a person types at a terminal (raw mode, see
//! terminal.zig); a pipe or a test is read line by line without it.
const std = @import("std");
const Io = std.Io;

/// Longest line the editor accepts; more characters are ignored.
pub const max_line = 512;

/// Where the last word of the line starts: after the last blank, or 0 for the first word.
pub fn lastWordStart(line: []const u8) usize {
    var i = line.len;
    while (i > 0 and line[i - 1] != ' ' and line[i - 1] != '\t') i -= 1;
    return i;
}

// Zig tip: a struct can own an allocator-backed value. The completer keeps its candidate names in an
// `ArenaAllocator`: an allocator that never frees single items but drops everything at once with
// `reset` or `deinit`. That suits a list rebuilt from scratch at every new word: no per-name
// `free` and no leaks to track. `.init(gpa)` wraps a parent allocator ("general purpose") that
// supplies the real memory.
/// Tab completion state, kept between the keys of one prompt.
pub const Completer = struct {
    arena: std.heap.ArenaAllocator,
    /// The candidates for the word being completed, sorted.
    items: []const []const u8 = &.{},
    /// Index of the candidate the next Tab shows.
    next: usize = 0,
    /// True between the first Tab and the next other key.
    active: bool = false,
    /// Where the completed word starts in the line.
    word_start: usize = 0,

    pub fn init(gpa: std.mem.Allocator) Completer {
        return .{ .arena = .init(gpa) };
    }

    pub fn deinit(c: *Completer) void {
        c.arena.deinit();
    }

    /// Any key but Tab: the next Tab starts a new cycle.
    pub fn stop(c: *Completer) void {
        c.active = false;
    }

    // Zig tip: `!?[]const u8` reads as "an error, or null, or a string": three outcomes in one return
    // value. Here null means "nothing to show" (first word, or no file matches), which is not a
    // failure. `%` is the remainder, so `(next + 1) % len` wraps the index back to 0.
    // `c.arena.reset(.retain_capacity)` frees every name at once but keeps the memory for reuse.
    // `catch &.{}` turns a failed folder read into an empty list: no completion, no crash.
    /// The candidate for the last word of `line` that this Tab shows, or null when there is none.
    /// The first word (the command name) is not completed.
    pub fn tab(c: *Completer, io: Io, line: []const u8, ext: []const u8) !?[]const u8 {
        if (!c.active) {
            c.word_start = lastWordStart(line);
            if (c.word_start == 0) return null;
            _ = c.arena.reset(.retain_capacity);
            c.items = matches(c.arena.allocator(), io, line[c.word_start..], ext) catch &.{};
            c.next = 0;
            c.active = c.items.len > 0;
            if (!c.active) return null;
        }
        const item = c.items[c.next];
        c.next = (c.next + 1) % c.items.len;
        return item;
    }
};

fn isDirectory(io: Io, path: []const u8) bool {
    var d = Io.Dir.cwd().openDir(io, path, .{}) catch return false;
    d.close(io);
    return true;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

// Zig tip: `arena` is the allocator for the returned names, chosen by the caller (the arena above), so
// this function never frees anything itself. `std.fmt.allocPrint` is `printf` into fresh memory.
// `lastIndexOfAny` returns an optional index, unwrapped with `if (...) |i|`. `defer dir.close(io)`
// closes the folder on every way out of the function, including an error return. `it.next(io)`
// is the folder iterator: it returns an optional entry, so the `while (...) |entry|` loop ends
// when the folder is read to the end. A `switch` on an enum (`entry.kind`) needs a branch for
// each tag or an `else`. `std.mem.sort` sorts a slice in place, given a comparison function.
/// The files ending in `ext` and the sub-folders that complete `word`, with the folder part as typed. A word
/// that is a folder without a trailing slash (`test/level1`) lists the content of that folder.
fn matches(arena: std.mem.Allocator, io: Io, word: []const u8, ext: []const u8) ![]const []const u8 {
    var dir_part: []const u8 = "";
    var prefix: []const u8 = word;
    if (std.mem.lastIndexOfAny(u8, word, "/\\")) |i| {
        dir_part = word[0 .. i + 1];
        prefix = word[i + 1 ..];
    }
    var open_path: []const u8 = if (dir_part.len == 0) "." else dir_part;
    if (prefix.len > 0 and isDirectory(io, word)) {
        dir_part = try std.fmt.allocPrint(arena, "{s}/", .{word});
        open_path = word;
        prefix = "";
    }

    var dir = try Io.Dir.cwd().openDir(io, open_path, .{ .iterate = true });
    defer dir.close(io);
    var found: std.ArrayList([]const u8) = .empty;
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (!std.mem.startsWith(u8, entry.name, prefix)) continue;
        if (entry.name[0] == '.' and !std.mem.startsWith(u8, prefix, ".")) continue;
        const suffix: []const u8 = switch (entry.kind) {
            .directory => "/",
            .file => if (std.mem.endsWith(u8, entry.name, ext)) "" else continue,
            else => continue,
        };
        try found.append(arena, try std.fmt.allocPrint(arena, "{s}{s}{s}", .{ dir_part, entry.name, suffix }));
    }
    std.mem.sort([]const u8, found.items, {}, lessThan);
    return found.items;
}

// Zig tip: `-|` is saturating subtraction: `old -| new` is 0 instead of an overflow error when new is
// larger (plain unsigned `-` that goes below zero stops the program in Debug builds).
// `for (0..n) |_|` repeats n times; `0..n` is a range and `_` discards the index.
// `\r` returns the cursor to column 0 and byte 8 moves it one column left, so redrawing needs
// no terminal escape codes and works in the Windows console too.
/// Draw the prompt and the line again from column 0, wiping what is left of a longer old line.
fn redraw(out: *Io.Writer, prompt: []const u8, line: []const u8, old_len: usize) !void {
    try out.writeAll("\r");
    try out.writeAll(prompt);
    try out.writeAll(line);
    const extra = old_len -| line.len;
    for (0..extra) |_| try out.writeByte(' ');
    for (0..extra) |_| try out.writeByte(8);
    try out.flush();
}

// Zig tip: `switch (b)` on an integer lists values and ranges (`32...126`); `else` handles the rest.
// A `switch` branch can use `continue`, `break` and `return` of the loop around it. `buf: *[N]u8` is
// a pointer to an array of known size, and `buf[0..len]` makes a slice of its first `len` bytes.
// `@memcpy(dest, source)` copies bytes; both slices must have the same length.
// `in.takeByte()` fails with `error.EndOfStream` at the end of the input; `catch |e| switch (e)`
// maps that one error to "no more input" (null) and passes every other error on.
/// Read one line with editing: printable keys, Backspace, Tab, Enter. Ctrl-C drops the line (an
/// empty line is returned), Ctrl-D or Ctrl-Z on an empty line is the end of input (null).
/// The returned slice is part of `buf`.
pub fn readLine(
    io: Io,
    in: *Io.Reader,
    out: *Io.Writer,
    prompt: []const u8,
    comp: *Completer,
    buf: *[max_line]u8,
    extOf: *const fn (line: []const u8) ?[]const u8,
) !?[]const u8 {
    var len: usize = 0;
    comp.stop();
    while (true) {
        const b = in.takeByte() catch |e| switch (e) {
            error.EndOfStream => return if (len == 0) null else buf[0..len],
            else => return e,
        };
        if (b == '\t') {
            const old = len;
            const ext = extOf(buf[0..len]) orelse "";
            const found = if (ext.len > 0) try comp.tab(io, buf[0..len], ext) else null;
            if (found) |word| {
                const new_len = comp.word_start + word.len;
                if (new_len <= buf.len) {
                    @memcpy(buf[comp.word_start..new_len], word);
                    len = new_len;
                    try redraw(out, prompt, buf[0..len], old);
                }
            } else {
                try out.writeByte(7); // bell: nothing to complete
                try out.flush();
            }
            continue;
        }
        comp.stop();
        switch (b) {
            '\r', '\n' => {
                try out.writeAll("\r\n");
                try out.flush();
                return buf[0..len];
            },
            3 => {
                try out.writeAll("^C\r\n");
                try out.flush();
                return buf[0..0];
            },
            4, 26 => if (len == 0) {
                try out.writeAll("\r\n");
                try out.flush();
                return null;
            },
            8, 127 => if (len > 0) {
                const old = len;
                len -= 1;
                while (len > 0 and buf[len] & 0xC0 == 0x80) len -= 1; // drop a whole UTF-8 character
                try redraw(out, prompt, buf[0..len], old);
            },
            27 => skipEscape(in),
            32...126, 128...255 => if (len < buf.len) {
                buf[len] = b;
                len += 1;
                try out.writeByte(b);
                try out.flush();
            },
            else => {},
        }
    }
}

/// Arrow and function keys arrive as ESC [ ... letter; they are not edited, so drop them.
fn skipEscape(in: *Io.Reader) void {
    const first = in.takeByte() catch return;
    if (first != '[' and first != 'O') return;
    while (in.takeByte()) |c| {
        if (c >= 0x40 and c <= 0x7e) return;
    } else |_| {}
}

// Zig tip: a test that touches the real file system uses paths relative to the folder where
// `zig build test` runs (evevm/). `std.testing.allocator` is a leak-checking allocator for
// tests. `std.testing.io` is the `Io` value tests pass to code that reads files.
fn testExt(_: []const u8) ?[]const u8 {
    return ".eve";
}

test "last word start" {
    try std.testing.expectEqual(@as(usize, 0), lastWordStart("check"));
    try std.testing.expectEqual(@as(usize, 6), lastWordStart("check a/b"));
    try std.testing.expectEqual(@as(usize, 6), lastWordStart("check "));
}

test "tab cycles through the eve files of a folder" {
    var comp: Completer = .init(std.testing.allocator);
    defer comp.deinit();
    const io = std.testing.io;
    const first = (try comp.tab(io, "check lib", ".eve")).?; // "lib" is a folder: list its content
    try std.testing.expect(std.mem.startsWith(u8, first, "lib/"));
    var n: usize = 1;
    while (n < 20) : (n += 1) {
        const w = (try comp.tab(io, "check lib/x", ".eve")).?; // `active`: the line is not read again
        if (std.mem.eql(u8, w, first)) break;
        try std.testing.expect(std.mem.endsWith(u8, w, ".eve") or std.mem.endsWith(u8, w, "/"));
    }
    try std.testing.expect(n > 1 and n < 20); // it wrapped to the first candidate
}

test "no completion for the command name or an unknown folder" {
    var comp: Completer = .init(std.testing.allocator);
    defer comp.deinit();
    try std.testing.expect((try comp.tab(std.testing.io, "che", ".eve")) == null);
    try std.testing.expect((try comp.tab(std.testing.io, "check nofolder/x", ".eve")) == null);
}

test "the editor edits and completes a line" {
    var comp: Completer = .init(std.testing.allocator);
    defer comp.deinit();
    var obuf: [512]u8 = undefined;
    var out: Io.Writer = .fixed(&obuf);
    var in: Io.Reader = .fixed("chexx\x08\x08ck lib\t\x08\r");
    var buf: [max_line]u8 = undefined;
    const got = (try readLine(std.testing.io, &in, &out, "eve:> ", &comp, &buf, testExt)).?;
    // Tab filled "lib/...", then Backspace removed its last character.
    try std.testing.expect(std.mem.startsWith(u8, got, "check lib/"));
    try std.testing.expect(std.mem.endsWith(u8, out.buffered(), "\r\n"));
}

test "Ctrl-D ends the input only on an empty line" {
    var comp: Completer = .init(std.testing.allocator);
    defer comp.deinit();
    var obuf: [64]u8 = undefined;
    var out: Io.Writer = .fixed(&obuf);
    var in: Io.Reader = .fixed("\x04");
    var buf: [max_line]u8 = undefined;
    try std.testing.expect((try readLine(std.testing.io, &in, &out, "> ", &comp, &buf, testExt)) == null);
}
