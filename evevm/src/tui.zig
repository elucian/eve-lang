//! The full-screen look of the REPL at a terminal: an upper part with the output and its own scrollback, and a bar
//! that never leaves the bottom of the window:
//!
//!     (output of the commands and of the scripts, scrolls with Page Up/Down and the arrows)
//!     ────────────────────────────────────────  rule
//!     eve:> the command line
//!     ────────────────────────────────────────  rule
//!      ● Ready  ·  last run: execute 1.20 s      status bar (Running… blinks while a command runs)
//!
//! Everything the program writes goes through `Tui.out`, a `Writer` whose sink is the scrollback, so the machine's
//! log lines (other threads) and the output of a script land in the upper part and never on the command line. The
//! screen is the alternate screen of the terminal: when `eve` ends, the terminal shows what it showed before.
const std = @import("std");
const Io = std.Io;
const screen = @import("screen.zig");
const terminal = @import("evecm").terminal;
const line_editor = @import("evecm").line;
const version = @import("evecm").version;

/// Longest line of the upper part: a longer line is split here. A shorter one is never wrapped; if the window is
/// narrower than the line, the end of the line is cut off on the screen (the scrollback keeps all of it).
pub const wrap_at = 120;

/// The scrollback keeps at most this many lines and bytes; the oldest are dropped first.
const max_lines = 50_000;
const max_bytes = 32 << 20;

const reset = "\x1b[0m";
const accent = "\x1b[1;36m";
const dim = "\x1b[2m";
const bar_style = "\x1b[48;5;236m\x1b[97m";

/// A key that is not a plain character.
const Key = enum { up, down, page_up, page_down, home, end, right, other };

/// What a re-drawable block of the upper part shows; `arg` is the number of the command for `help_command`.
pub const BlockKind = enum { help_table, help_command };

// Zig tip: a block remembers what it shows (`kind`, `arg`) and where its lines are (`first`, `count`), not how it
// looks. When the window changes width the screen asks the renderer to make the text again for the new width and puts
// the new lines where the old ones were. The text of a program's output is not a block: it is kept as it was written.
/// A part of the scrollback that is drawn again when the width changes.
const Block = struct { kind: BlockKind, arg: usize, first: usize, count: usize };

// Zig tip: a function pointer type is a type like any other: `*const fn (...) void`. cli.zig gives the screen a
// function with this shape; the screen calls it and never needs to know the texts, so tui.zig does not import cli.zig
// (two files that import each other are hard to follow).
/// Writes a block for `width` characters. Given by cli.zig, which knows the texts.
pub const Renderer = *const fn (kind: BlockKind, arg: usize, width: usize, w: *Io.Writer) void;

// Zig tip: a struct that must not move in memory (its `out` field is found again from the pointer to the writer
// inside it, `@fieldParentPtr`) is made once with `gpa.create` and used through a pointer, never copied.
/// The state of the screen: the scrollback, the command line, the status bar.
pub const Tui = struct {
    io: Io,
    gpa: std.mem.Allocator,
    /// The terminal itself; written only with `lock` held.
    raw: *Io.Writer,
    lock: Io.Mutex = .init,
    /// What the rest of the program writes to (`ctx.out`).
    out: Io.Writer,
    out_buf: [4096]u8 = undefined,
    rows: usize = 24,
    cols: usize = 80,

    // the scrollback: finished lines (`text` holds them with a newline after each, `starts` their offsets) and the
    // line being written
    text: std.ArrayList(u8) = .empty,
    starts: std.ArrayList(usize) = .empty,
    partial: std.ArrayList(u8) = .empty,
    /// Characters of `partial` on the screen (escape sequences do not count), to split at `wrap_at`.
    shown: usize = 0,
    has_escape: bool = false,
    /// 0: plain text, 1: just after ESC, 2: inside `ESC [ ...`.
    escape: u8 = 0,
    /// A `\r` was seen: a following `\n` ends the line, any other character starts the line again.
    cr: bool = false,
    /// How many lines the view is scrolled back; 0 follows the end.
    offset: usize = 0,
    /// The width of the table and of the help texts (EVE_WIDTH, `eve_width` in eve.cfg); a narrower window wins.
    eve_width: usize = screen.default_width,
    blocks: std.ArrayList(Block) = .empty,
    renderer: ?Renderer = null,
    /// The width the blocks were drawn for; when `blockWidth` differs, they are drawn again.
    laid_width: usize = 0,
    /// `feed` splits lines at this length; a block lifts the limit because it was made for the width.
    wrap_limit: usize = wrap_at,
    /// How many lines were ever finished: lets a block count its own lines even if old ones are dropped meanwhile.
    committed: usize = 0,
    /// True while the blocks are made again: the scrollback is not trimmed in the middle of that.
    no_trim: bool = false,
    closing: std.atomic.Value(bool) = .init(false),
    /// The size of the window at the last drawing.
    drawn_rows: usize = 0,
    drawn_cols: usize = 0,

    // the bars
    running: bool = false,
    name: [24]u8 = undefined,
    name_len: usize = 0,
    last_ms: i64 = -1,
    prompt: []const u8 = "eve:> ",
    input: []const u8 = "",
    dirty: bool = false,
    last_paint: i64 = 0,

    // Zig tip: `.{ .vtable = &vtable, .buffer = ... }` builds a `Writer` by hand: a table of functions (`drain`, called
    // when the buffer is full, and `flush`) and a buffer. Whatever the program writes ends in `drain`, which here
    // feeds the scrollback. A writer is the Zig way to say "a place that takes bytes" without naming the place.
    const vtable: Io.Writer.VTable = .{ .drain = drain, .flush = flush };

    /// Make the screen state; call `enter` to take the terminal.
    pub fn create(io: Io, gpa: std.mem.Allocator, raw: *Io.Writer) !*Tui {
        const t = try gpa.create(Tui);
        t.* = .{ .io = io, .gpa = gpa, .raw = raw, .out = undefined };
        t.out = .{ .vtable = &vtable, .buffer = &t.out_buf };
        t.refreshSize();
        return t;
    }

    fn refreshSize(t: *Tui) void {
        if (terminal.Terminal.size()) |s| {
            t.rows = @max(s.rows, 7);
            t.cols = @max(s.cols, 20);
        }
    }

    fn now(t: *const Tui) i64 {
        return Io.Timestamp.now(t.io, .awake).toMilliseconds();
    }

    /// Rows of the upper part: the window without the two rules, the command line and the status bar.
    fn height(t: *const Tui) usize {
        return t.rows - 4;
    }

    /// Take the screen: the alternate screen, with the wheel of the mouse sent as arrows (mode 1007).
    pub fn enter(t: *Tui) void {
        t.lock.lockUncancelable(t.io);
        defer t.lock.unlock(t.io);
        t.raw.writeAll("\x1b[?1049h\x1b[?1007h\x1b[2J") catch {};
        t.paintAll();
        // a thread that looks at the size of the window and draws again when it changes, even while nobody types
        if (std.Thread.spawn(.{}, watch, .{t})) |th| th.detach() else |_| {}
    }

    // Zig tip: a detached thread that polls is the simplest way to learn that a window was resized: the program sleeps
    // on the keyboard and gets no event for it. `Io.sleep` waits without using the processor. The thread takes the
    // lock for every look, as every painter does, and ends when `leave` sets `closing`.
    fn watch(t: *Tui) void {
        while (!t.closing.load(.acquire)) {
            Io.sleep(t.io, .fromMilliseconds(150), .awake) catch {};
            t.lock.lockUncancelable(t.io);
            if (!t.closing.load(.acquire)) {
                if (terminal.Terminal.size()) |s| {
                    if (@max(s.rows, 7) != t.drawn_rows or @max(s.cols, 20) != t.drawn_cols) t.paintAll();
                }
            }
            t.lock.unlock(t.io);
        }
    }

    // Zig tip: the escape codes are plain text in a string: the first byte (code 27) is Esc, and `[2J` clears the screen, `[3J` its
    // scrollback, `[H` puts the cursor at the top left. A terminal does the work; the program only writes the bytes.
    /// Give the screen back to the terminal, cleared.
    pub fn leave(t: *Tui) void {
        t.closing.store(true, .release);
        t.lock.lockUncancelable(t.io);
        defer t.lock.unlock(t.io);
        // the shell screen is cleared and the cursor goes to the top, so the prompt does not creep down at every exit
        t.raw.writeAll("\x1b[0m\x1b[?1007l\x1b[?1049l\x1b[?25h\x1b[2J\x1b[3J\x1b[H") catch {};
        t.raw.flush() catch {};
    }

    // ---- the scrollback ---------------------------------------------------------------------------------------

    // Zig tip: `@fieldParentPtr("out", w)` goes from a pointer to a field (the `Writer`) back to the struct that
    // contains it. `@alignCast` tells the compiler the pointer is aligned like a `Tui`, which it is. The lock is the
    // `Io.Mutex` of the server: the REPL and the threads of the machine all write here, one at a time.
    fn drain(w: *Io.Writer, data: []const []const u8, splat: usize) Io.Writer.Error!usize {
        const t: *Tui = @alignCast(@fieldParentPtr("out", w));
        t.lock.lockUncancelable(t.io);
        defer t.lock.unlock(t.io);
        t.feed(w.buffer[0..w.end]);
        w.end = 0;
        var n: usize = 0;
        for (data[0 .. data.len - 1]) |d| {
            t.feed(d);
            n += d.len;
        }
        const last = data[data.len - 1];
        for (0..splat) |_| t.feed(last);
        n += last.len * splat;
        t.paintLive(false);
        return n;
    }

    fn flush(w: *Io.Writer) Io.Writer.Error!void {
        const t: *Tui = @alignCast(@fieldParentPtr("out", w));
        t.lock.lockUncancelable(t.io);
        defer t.lock.unlock(t.io);
        t.feed(w.buffer[0..w.end]);
        w.end = 0;
        t.paintLive(true);
    }

    // Zig tip: a small state machine reads the bytes one at a time. The states are plain fields (`escape`, `cr`), so
    // text that arrives cut in two pieces (a drain can end in the middle of a color code) is still read right. A UTF-8
    // character is counted once, by its first byte (`b & 0xC0 != 0x80`), because that is one place on the screen.
    /// Add bytes to the scrollback: split into lines, tabs expanded, long lines cut at `wrap_at`.
    fn feed(t: *Tui, bytes: []const u8) void {
        for (bytes) |b| {
            if (t.cr) {
                t.cr = false;
                if (b != '\n') t.resetLine();
            }
            if (t.escape == 1) {
                t.escape = if (b == '[') 2 else 0;
                t.partial.append(t.gpa, b) catch {};
                continue;
            }
            if (t.escape == 2) {
                if (b >= 0x40 and b <= 0x7e) t.escape = 0;
                t.partial.append(t.gpa, b) catch {};
                continue;
            }
            switch (b) {
                '\r' => t.cr = true,
                '\n' => t.commit(),
                '\t' => {
                    const to = @min((t.shown / 8 + 1) * 8, t.wrap_limit);
                    while (t.shown < to) t.putChar(' ');
                },
                0x1b => {
                    t.escape = 1;
                    t.has_escape = true;
                    t.partial.append(t.gpa, b) catch {};
                },
                0...8, 11, 12, 14...26, 28...31, 127 => {},
                else => if (b & 0xC0 == 0x80) {
                    t.partial.append(t.gpa, b) catch {};
                } else {
                    t.putChar(b);
                },
            }
        }
    }

    /// The first byte of a character: split the line first if it is full.
    fn putChar(t: *Tui, b: u8) void {
        if (t.shown >= t.wrap_limit) t.commit();
        t.partial.append(t.gpa, b) catch {};
        t.shown += 1;
    }

    fn resetLine(t: *Tui) void {
        t.partial.clearRetainingCapacity();
        t.shown = 0;
        t.has_escape = false;
        t.escape = 0;
    }

    /// End the line being written: it joins the finished lines.
    fn commit(t: *Tui) void {
        if (t.has_escape) t.partial.appendSlice(t.gpa, reset) catch {};
        t.starts.append(t.gpa, t.text.items.len) catch {};
        t.text.appendSlice(t.gpa, t.partial.items) catch {};
        t.text.append(t.gpa, '\n') catch {};
        t.resetLine();
        t.committed += 1;
        if (t.offset > 0) t.offset += 1; // a view scrolled back stays on the same text
        if (!t.no_trim and (t.starts.items.len > max_lines or t.text.items.len > max_bytes)) t.drop(t.starts.items.len / 4);
    }

    // Zig tip: `replaceRange(gpa, start, len, new)` removes `len` bytes at `start` and puts `new` in their place; with
    // an empty `new` it deletes, and moves the rest down in one copy. The offsets of the lines that stay all move
    // by the same amount.
    /// Forget the oldest `n` lines.
    fn drop(t: *Tui, n: usize) void {
        if (n == 0 or n > t.starts.items.len) return;
        const cut = if (n < t.starts.items.len) t.starts.items[n] else t.text.items.len;
        t.text.replaceRange(t.gpa, 0, cut, &.{}) catch return;
        t.starts.replaceRange(t.gpa, 0, n, &.{}) catch return;
        for (t.starts.items) |*s| s.* -= cut;
        t.offset = t.offset -| n;
        // a block that lost a line cannot be made again: it stays as text; the others move up with the lines
        var keep: usize = 0;
        for (t.blocks.items) |b| {
            if (b.first < n) continue;
            t.blocks.items[keep] = .{ .kind = b.kind, .arg = b.arg, .first = b.first - n, .count = b.count };
            keep += 1;
        }
        t.blocks.shrinkRetainingCapacity(keep);
    }

    // ---- the blocks: help tables and texts that are drawn again for a new width -------------------------------

    /// The width for tables and texts: `eve_width`, but never more than the window, and not less than `min_width`.
    fn blockWidth(t: *const Tui) usize {
        return @max(screen.min_width, @min(t.eve_width, t.cols));
    }

    // Zig tip: `Io.Writer.Allocating` collects what the renderer writes into memory; `defer aw.deinit()` frees it on
    // every way out. The text is then fed to the scrollback like any other output, with the limit of 120 lifted.
    /// Draw one block at the current width and add its lines to the end of the scrollback.
    fn renderInto(t: *Tui, kind: BlockKind, arg: usize) void {
        const render = t.renderer orelse return;
        var aw: Io.Writer.Allocating = .init(t.gpa);
        defer aw.deinit();
        render(kind, arg, t.blockWidth(), &aw.writer);
        t.wrap_limit = std.math.maxInt(usize);
        t.feed(aw.written());
        t.wrap_limit = wrap_at;
        if (t.partial.items.len > 0) t.commit(); // a block is made of whole lines
    }

    /// Show a block (the table of `help`, or the page of `help <command>`) in the upper part.
    pub fn addBlock(t: *Tui, kind: BlockKind, arg: usize) void {
        t.lock.lockUncancelable(t.io);
        defer t.lock.unlock(t.io);
        t.refreshSize();
        if (t.blockWidth() != t.laid_width) t.reflowBlocks();
        if (t.partial.items.len > 0) t.commit();
        const before = t.committed;
        t.renderInto(kind, arg);
        const count = t.committed - before;
        if (count <= t.starts.items.len) {
            t.blocks.append(t.gpa, .{ .kind = kind, .arg = arg, .first = t.starts.items.len - count, .count = count }) catch {};
        }
        t.paintLive(true);
    }

    // Zig tip: the old lines are copied aside (`gpa.dupe`) and the scrollback is built again from the start: lines that
    // are not blocks are copied byte for byte, and each block is drawn at the new width. The line being typed or
    // written (`partial`) is set aside and put back, because `feed` uses it as its workspace.
    /// Draw the blocks again for the current width, keeping everything else as it is.
    fn reflowBlocks(t: *Tui) void {
        t.laid_width = t.blockWidth();
        if (t.blocks.items.len == 0 or t.renderer == null) return;
        const old_text = t.gpa.dupe(u8, t.text.items) catch return;
        defer t.gpa.free(old_text);
        const old_starts = t.gpa.dupe(usize, t.starts.items) catch return;
        defer t.gpa.free(old_starts);
        const saved = t.partial;
        const saved_shown = t.shown;
        const saved_escape = t.has_escape;
        t.partial = .empty;
        t.resetLine();
        t.text.clearRetainingCapacity();
        t.starts.clearRetainingCapacity();
        t.no_trim = true;
        var next: usize = 0;
        for (t.blocks.items) |*b| {
            const old_first = b.first;
            const old_count = b.count;
            t.copyLines(old_text, old_starts, next, old_first);
            const before = t.committed;
            t.renderInto(b.kind, b.arg);
            b.count = t.committed - before;
            b.first = t.starts.items.len - b.count;
            next = old_first + old_count;
        }
        t.copyLines(old_text, old_starts, next, old_starts.len);
        t.no_trim = false;
        t.partial.deinit(t.gpa);
        t.partial = saved;
        t.shown = saved_shown;
        t.has_escape = saved_escape;
        t.offset = @min(t.offset, t.lineCount());
    }

    /// Copy the old lines `from` .. `to` (a line ends with its newline) to the end of the scrollback.
    fn copyLines(t: *Tui, old_text: []const u8, old_starts: []const usize, from: usize, to: usize) void {
        for (from..to) |i| {
            const end = if (i + 1 < old_starts.len) old_starts[i + 1] else old_text.len;
            t.starts.append(t.gpa, t.text.items.len) catch return;
            t.text.appendSlice(t.gpa, old_text[old_starts[i]..end]) catch return;
        }
    }

    fn lineCount(t: *const Tui) usize {
        return t.starts.items.len + @intFromBool(t.partial.items.len > 0);
    }

    fn lineAt(t: *const Tui, i: usize) []const u8 {
        if (i >= t.starts.items.len) return t.partial.items;
        const s = t.starts.items[i];
        const e = if (i + 1 < t.starts.items.len) t.starts.items[i + 1] - 1 else t.text.items.len - 1;
        return t.text.items[s..e];
    }

    /// Clear the upper part (the `clear` command).
    pub fn clear(t: *Tui) void {
        t.lock.lockUncancelable(t.io);
        defer t.lock.unlock(t.io);
        t.text.clearRetainingCapacity();
        t.starts.clearRetainingCapacity();
        t.blocks.clearRetainingCapacity();
        t.resetLine();
        t.cr = false;
        t.offset = 0;
        t.paintAll();
    }

    // ---- painting -----------------------------------------------------------------------------------------------

    // Zig tip: painting never fails the program: a terminal that cannot be written to is not a reason to stop the
    // REPL, so every write ends with `catch {}`. The cursor is hidden while the screen is drawn and shown at the end
    // on the command line, so it does not jump around.
    /// Draw everything.
    fn paintAll(t: *Tui) void {
        t.refreshSize();
        // a window of another size: the blocks are made again for the new width and the old picture is wiped
        if (t.blockWidth() != t.laid_width) t.reflowBlocks();
        if (t.drawn_rows != 0 and (t.drawn_rows != t.rows or t.drawn_cols != t.cols)) t.raw.writeAll("\x1b[2J") catch {};
        t.drawn_rows = t.rows;
        t.drawn_cols = t.cols;
        t.raw.writeAll("\x1b[?25l") catch {};
        t.paintOutput();
        t.paintBox();
        t.paintStatus();
        t.paintCursor();
        t.raw.flush() catch {};
        t.dirty = false;
        t.last_paint = t.now();
    }

    /// New output arrived (or a flush): follow the end of the text, at most every 30 ms unless `force`.
    fn paintLive(t: *Tui, force: bool) void {
        if (t.offset > 0) return;
        const ms = t.now();
        if (!force and ms - t.last_paint < 30) {
            t.dirty = true;
            return;
        }
        t.raw.writeAll("\x1b[?25l") catch {};
        t.paintOutput();
        t.paintCursor();
        t.raw.flush() catch {};
        t.dirty = false;
        t.last_paint = ms;
    }

    fn paintOutput(t: *Tui) void {
        const h = t.height();
        const n = t.lineCount();
        const end = n - @min(t.offset, n);
        const begin = end -| h;
        for (0..h) |r| {
            t.raw.print("\x1b[{d};1H", .{r + 1}) catch {};
            if (begin + r < end) t.clipped(t.lineAt(begin + r), t.cols);
            t.raw.writeAll(reset ++ "\x1b[K") catch {};
        }
    }

    // Zig tip: a line may hold color codes, which take no room on the screen, so the cut is made on the characters
    // that show: escape sequences are copied whole and only the other characters are counted.
    /// Write at most `width` characters of `s`, and the color codes that go with them.
    fn clipped(t: *Tui, s: []const u8, width: usize) void {
        var shown: usize = 0;
        var esc: u8 = 0;
        for (s) |b| {
            if (esc == 1) {
                esc = if (b == '[') 2 else 0;
            } else if (esc == 2) {
                if (b >= 0x40 and b <= 0x7e) esc = 0;
            } else if (b == 0x1b) {
                esc = 1;
            } else if (b & 0xC0 != 0x80) {
                if (shown >= width) return;
                shown += 1;
            }
            t.raw.writeByte(b) catch {};
        }
    }

    fn paintBox(t: *Tui) void {
        t.rule(t.rows - 3);
        t.rule(t.rows - 1);
        const avail = t.cols -| (screen.cells(t.prompt) + 1);
        const from = if (screen.cells(t.input) > avail) tailStart(t.input, avail) else 0;
        t.raw.print("\x1b[{d};1H" ++ accent ++ "{s}" ++ reset ++ "{s}\x1b[K", .{ t.rows - 2, t.prompt, t.input[from..] }) catch {};
    }

    fn rule(t: *Tui, row: usize) void {
        t.raw.print("\x1b[{d};1H" ++ dim, .{row}) catch {};
        for (0..t.cols) |_| t.raw.writeAll("─") catch {};
        t.raw.writeAll(reset) catch {};
    }

    /// Where the last `n` characters of `s` start.
    fn tailStart(s: []const u8, n: usize) usize {
        var i = s.len;
        var seen: usize = 0;
        while (i > 0) {
            i -= 1;
            if (s[i] & 0xC0 != 0x80) {
                seen += 1;
                if (seen == n) return i;
            }
        }
        return 0;
    }

    fn paintCursor(t: *Tui) void {
        const avail = t.cols -| (screen.cells(t.prompt) + 1);
        const typed = @min(screen.cells(t.input), avail);
        t.raw.print("\x1b[{d};{d}H\x1b[?25h", .{ t.rows - 2, screen.cells(t.prompt) + typed + 1 }) catch {};
    }

    // Zig tip: `std.fmt.bufPrint(&buf, ...)` formats into a buffer on the stack and returns the part it used, so no
    // memory is allocated for a short text. The `catch ""` keeps the status bar alive if a text did not fit.
    /// The status bar: Ready, or Running… (blinking, by the terminal), then the time of the last run; on the right the
    /// scroll position or the version.
    fn paintStatus(t: *Tui) void {
        const w = t.raw;
        w.print("\x1b[{d};1H" ++ bar_style, .{t.rows}) catch {};
        var used: usize = 1;
        w.writeByte(' ') catch {};
        var buf: [96]u8 = undefined;
        if (t.running) {
            w.writeAll("\x1b[33m▶\x1b[97m \x1b[5mRunning…\x1b[25m") catch {};
            used += 10;
            const name = std.fmt.bufPrint(&buf, " {s}", .{t.name[0..t.name_len]}) catch "";
            w.writeAll(name) catch {};
            used += screen.cells(name);
        } else {
            w.writeAll("\x1b[32m●\x1b[97m Ready") catch {};
            used += 7;
            if (t.last_ms >= 0) {
                var time: [32]u8 = undefined;
                const text = std.fmt.bufPrint(&buf, "  ·  last run: {s} {s}", .{ t.name[0..t.name_len], fmtMs(&time, t.last_ms) }) catch "";
                w.writeAll(text) catch {};
                used += screen.cells(text);
            } else {
                const text = "  ·  type help or ? for commands";
                w.writeAll(text) catch {};
                used += screen.cells(text);
            }
        }
        const right = if (t.offset > 0)
            std.fmt.bufPrint(&buf, "↑ {d} lines up, End returns ", .{t.offset}) catch ""
        else
            std.fmt.bufPrint(&buf, "eve {s} ", .{version.version}) catch "";
        const room = t.cols -| used;
        if (screen.cells(right) < room) {
            for (0..room - screen.cells(right)) |_| w.writeByte(' ') catch {};
            w.writeAll(right) catch {};
        } else {
            for (0..room) |_| w.writeByte(' ') catch {};
        }
        w.writeAll(reset) catch {};
    }

    /// `850 ms`, `1.20 s`, `2 min 05 s`.
    fn fmtMs(buf: []u8, ms: i64) []const u8 {
        const m = @max(ms, 0);
        const text = if (m < 1000)
            std.fmt.bufPrint(buf, "{d} ms", .{m})
        else if (m < 60_000)
            std.fmt.bufPrint(buf, "{d}.{d:0>2} s", .{ @divTrunc(m, 1000), @divTrunc(@mod(m, 1000), 10) })
        else
            std.fmt.bufPrint(buf, "{d} min {d:0>2} s", .{ @divTrunc(m, 60_000), @mod(@divTrunc(m, 1000), 60) });
        return text catch "";
    }

    // ---- the status of the command ----------------------------------------------------------------------------

    /// A command starts: the status bar says Running… and blinks.
    pub fn setRunning(t: *Tui, name: []const u8) void {
        t.lock.lockUncancelable(t.io);
        defer t.lock.unlock(t.io);
        t.name_len = @min(name.len, t.name.len);
        @memcpy(t.name[0..t.name_len], name[0..t.name_len]);
        t.running = true;
        t.raw.writeAll("\x1b[?25l") catch {};
        t.paintStatus();
        t.paintCursor();
        t.raw.flush() catch {};
    }

    /// The command ended after `ms` milliseconds: Ready, and the time of the run.
    pub fn setReady(t: *Tui, ms: i64) void {
        t.lock.lockUncancelable(t.io);
        defer t.lock.unlock(t.io);
        t.running = false;
        t.last_ms = ms;
        t.paintAll();
    }

    // ---- scrolling -----------------------------------------------------------------------------------------------

    fn scrollBy(t: *Tui, up: bool, lines: usize) void {
        t.lock.lockUncancelable(t.io);
        defer t.lock.unlock(t.io);
        const limit = t.lineCount() -| t.height();
        t.offset = if (up) @min(t.offset + lines, limit) else t.offset -| lines;
        t.raw.writeAll("\x1b[?25l") catch {};
        t.paintOutput();
        t.paintStatus();
        t.paintCursor();
        t.raw.flush() catch {};
    }

    fn scrollTo(t: *Tui, top: bool) void {
        t.scrollBy(top, if (top) std.math.maxInt(u32) else t.offset);
    }

    fn press(t: *Tui, key: Key) void {
        switch (key) {
            .up => t.scrollBy(true, 1),
            .down => t.scrollBy(false, 1),
            .page_up => t.scrollBy(true, t.height() -| 1),
            .page_down => t.scrollBy(false, t.height() -| 1),
            .home => t.scrollTo(true),
            .end => t.scrollTo(false),
            .right, .other => {},
        }
    }

    // ---- the command line ----------------------------------------------------------------------------------------

    /// Show `text` on the command line (a slice of the buffer being edited) and put the cursor after it.
    fn showInput(t: *Tui, text: []const u8) void {
        t.lock.lockUncancelable(t.io);
        defer t.lock.unlock(t.io);
        // a window that was resized is drawn again from scratch; otherwise only the command line changes
        const size = terminal.Terminal.size() orelse terminal.Size{ .rows = t.rows, .cols = t.cols };
        const resized = size.rows != t.rows or size.cols != t.cols;
        t.input = text;
        if (resized) {
            t.paintAll();
            return;
        }
        t.raw.writeAll("\x1b[?25l") catch {};
        t.paintBox();
        t.paintCursor();
        t.raw.flush() catch {};
    }

    /// The line was entered: it is copied into the upper part, the command line is empty again, the view follows the end.
    fn submit(t: *Tui, text: []const u8) void {
        t.lock.lockUncancelable(t.io);
        defer t.lock.unlock(t.io);
        t.feed(accent);
        t.feed(t.prompt);
        t.feed(reset);
        t.feed(text);
        t.feed("\n");
        t.input = "";
        t.offset = 0;
        t.paintAll();
    }

    // Zig tip: a keyboard sends one byte for a letter and a sequence for the other keys: `ESC [ A` for the up arrow,
    // `ESC [ 5 ~` for Page Up. The function reads the digits of the first parameter and the last byte (a letter or `~`)
    // and names the key. An unknown sequence is read to its end and ignored, so it cannot leak into the line.
    fn readKey(in: *Io.Reader) Key {
        const first = in.takeByte() catch return .other;
        if (first != '[' and first != 'O') return .other;
        var param: usize = 0;
        while (in.takeByte()) |c| {
            if (c >= '0' and c <= '9') {
                param = param * 10 + (c - '0');
                continue;
            }
            if (c == ';') continue;
            if (c < 0x40 or c > 0x7e) return .other;
            return switch (c) {
                'A' => .up,
                'B' => .down,
                'H' => .home,
                'F' => .end,
                'C' => .right,
                '~' => switch (param) {
                    5 => .page_up,
                    6 => .page_down,
                    1, 7 => .home,
                    4, 8 => .end,
                    else => .other,
                },
                else => .other,
            };
        } else |_| return .other;
    }

    /// Read one command line: editing, Right for file names, Page Up/Down and the arrows
    /// to scroll the upper part. Null at the end of the input (Ctrl-D on an empty line).
    pub fn readLine(
        t: *Tui,
        in: *Io.Reader,
        comp: *line_editor.Completer,
        buf: *[line_editor.max_line]u8,
        extOf: *const fn (line: []const u8) ?[]const u8,
    ) !?[]const u8 {
        var len: usize = 0;
        comp.stop();
        t.showInput("");
        while (true) {
            const b = in.takeByte() catch |e| switch (e) {
                error.EndOfStream => return if (len == 0) null else buf[0..len],
                else => return e,
            };
            // Tab is not the completion key; Right at the end of the line completes (the line is edited at its end only)
            if (b == '\t') continue;
            var complete = false;
            var key: Key = .other;
            if (b == 27) {
                key = readKey(in);
                complete = key == .right;
                if (!complete) {
                    comp.stop();
                    t.press(key);
                    continue;
                }
            }
            if (complete) {
                const ext = extOf(buf[0..len]) orelse "";
                const found = if (ext.len > 0) try comp.tab(t.io, buf[0..len], ext) else null;
                if (found) |word| {
                    const new_len = comp.word_start + word.len;
                    if (new_len <= buf.len) {
                        @memcpy(buf[comp.word_start..new_len], word);
                        len = new_len;
                        t.showInput(buf[0..len]);
                    }
                }
                continue;
            }
            comp.stop();
            switch (b) {
                '\r', '\n' => {
                    t.submit(buf[0..len]);
                    return buf[0..len];
                },
                3 => {
                    t.showInput("");
                    return buf[0..0];
                },
                4, 26 => if (len == 0) return null,
                8, 127 => if (len > 0) {
                    len -= 1;
                    while (len > 0 and buf[len] & 0xC0 == 0x80) len -= 1; // drop a whole UTF-8 character
                    t.showInput(buf[0..len]);
                },
                32...126, 128...255 => if (len < buf.len) {
                    buf[len] = b;
                    len += 1;
                    if (t.offset > 0) t.scrollTo(false); // typing brings the view back to the end
                    t.showInput(buf[0..len]);
                },
                else => {},
            }
        }
    }
};

// Zig tip: the tests drive the scrollback without a terminal: `Tui.create` takes any `Writer` as the screen, here a
// fixed buffer, and `feed` is called directly. `std.testing.allocator` also checks that nothing leaks.
test "long lines are split at 120 characters and short ones are not wrapped" {
    var sink: [65536]u8 = undefined;
    var raw: Io.Writer = .fixed(&sink);
    const t = try Tui.create(std.testing.io, std.testing.allocator, &raw);
    defer {
        t.text.deinit(t.gpa);
        t.starts.deinit(t.gpa);
        t.partial.deinit(t.gpa);
        t.gpa.destroy(t);
    }
    t.feed("short line\n");
    t.feed(&(@as([130]u8, @splat('x')) ++ [_]u8{10}));
    t.feed("a\tb\r\nnext\rover\n");
    try std.testing.expectEqual(@as(usize, 5), t.starts.items.len);
    try std.testing.expectEqualStrings("short line", t.lineAt(0));
    try std.testing.expectEqual(@as(usize, 120), t.lineAt(1).len);
    try std.testing.expectEqual(@as(usize, 10), t.lineAt(2).len);
    try std.testing.expectEqualStrings("a       b", t.lineAt(3));
    try std.testing.expectEqualStrings("over", t.lineAt(4));
}

test "colors take no room and a view scrolled back stays on its text" {
    var sink: [65536]u8 = undefined;
    var raw: Io.Writer = .fixed(&sink);
    const t = try Tui.create(std.testing.io, std.testing.allocator, &raw);
    defer {
        t.text.deinit(t.gpa);
        t.starts.deinit(t.gpa);
        t.partial.deinit(t.gpa);
        t.gpa.destroy(t);
    }
    t.feed("\x1b[1;36m" ++ @as([120]u8, @splat('y')) ++ "\x1b[0m\n");
    try std.testing.expectEqual(@as(usize, 1), t.starts.items.len);
    t.offset = 1;
    t.feed("more\n");
    try std.testing.expectEqual(@as(usize, 2), t.offset);
    t.drop(1);
    try std.testing.expectEqual(@as(usize, 1), t.starts.items.len);
    try std.testing.expectEqualStrings("more", t.lineAt(0));
}

test "time of the last run is written short" {
    var b: [32]u8 = undefined;
    try std.testing.expectEqualStrings("850 ms", Tui.fmtMs(&b, 850));
    try std.testing.expectEqualStrings("1.20 s", Tui.fmtMs(&b, 1204));
    try std.testing.expectEqualStrings("2 min 05 s", Tui.fmtMs(&b, 125_000));
}
