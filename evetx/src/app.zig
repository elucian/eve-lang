//! The state of evetx and what the keys and the mouse do to it. Nothing here draws: `view.zig`
//! reads this state and draws it, and records where the clickable things are (`hits`).
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const vaxis = @import("vaxis");
const TextInput = vaxis.widgets.TextInput;
const Key = vaxis.Key;

const project = @import("project.zig");
const text = @import("text.zig");

// ------------------------------------------------------------------ small types

// Zig tip: An `enum` names a fixed set of choices. A `switch` on an enum must handle every value
// or have an `else`, so adding a choice later makes the compiler point at every place that needs a
// new case.
/// Where the keyboard goes.
pub const Focus = enum { tree, editor, files, find, replace, console, breaks };

// Zig tip: An enum like `Focus`: one name for every tab. `@tagName(tab)` would give its name as
// text.
/// The five tabs of the bottom panel.
pub const BottomTab = enum { console, watch, stderr, stdout, breaks };

// Zig tip: The state "what is open over the screen" is one enum, so two dialogs can never be open
// together.
/// What is open over the screen, if anything.
pub const Overlay = enum { none, menu, help, settings, goto, save_as };

// Zig tip: Naming every button lets `activate` use one `switch` for all clicks. `cont` is written
// instead of `continue` because `continue` is a keyword of Zig.
/// The buttons of the tool bars.
pub const Button = enum { run, step_into, step_out, cont, stop, replace, replace_all, goto, help, settings };

// Zig tip: A tagged union with payloads, like `Event` in main.zig. `.tree_row = 5` builds a value;
// `switch (a) { .tree_row => |i| ... }` reads its payload. A field without a payload
// (`menu_title`) has type `void`.
/// What a click on a clickable place does (see `Hit`).
pub const Action = union(enum) {
    tree_row: u32,
    tab: usize,
    tab_close: usize,
    bottom: BottomTab,
    button: Button,
    machine: u8,
    menu_title,
    menu_item: usize,
    field: Focus,
    break_row: usize,
    close_overlay,
};

// Zig tip: a struct with methods is how Zig does what other languages call a class. `contains` is
// called as `rect.contains(col, row)`: the value before the dot is passed as `self`.
pub const Rect = struct {
    x: u16 = 0,
    y: u16 = 0,
    w: u16 = 0,
    h: u16 = 0,

    pub fn contains(self: Rect, col: i16, row: i16) bool {
        return col >= self.x and col < self.x + self.w and row >= self.y and row < self.y + self.h;
    }
};

// Zig tip: A struct made of other types: a place on the screen and what a click on it does. The
// list of hits is rebuilt in every frame.
/// A clickable rectangle that the last drawing recorded.
pub const Hit = struct { rect: Rect, action: Action };

// Zig tip: Four kinds of line, and one color for each in view.zig.
pub const LineKind = enum { input, out, err, info };
// Zig tip: `[]u8` (without `const`) is a slice that this struct owns and may change or free,
// unlike the `[]const u8` slices that only look at memory of somebody else.
pub const LogLine = struct { text: []u8, kind: LineKind };

/// A list of lines with a scroll position, the shape of the console and of the Stdout and Stderr tabs.
pub const Log = struct {
    lines: std.ArrayList(LogLine) = .empty,
    /// How many lines the view is above the end (0 shows the end).
    scroll: usize = 0,

    // Zig tip: `gpa.dupe(u8, s)` makes a copy of a slice in new memory. `errdefer gpa.free(copy)`
    // frees the copy if the `append` after it fails, so a failure leaks nothing.
    pub fn add(self: *Log, gpa: std.mem.Allocator, s: []const u8, kind: LineKind) !void {
        const copy = try gpa.dupe(u8, s);
        errdefer gpa.free(copy);
        try self.lines.append(gpa, .{ .text = copy, .kind = kind });
        self.scroll = 0;
    }

    // Zig tip: `std.mem.splitScalar` returns an iterator over the pieces between line ends.
    // `it.peek()` looks at the next piece without taking it, which lets the loop skip the empty piece
    // after a final line end.
    /// Add a block of text, one line for every line end.
    pub fn addBlock(self: *Log, gpa: std.mem.Allocator, bytes: []const u8, kind: LineKind) !void {
        var it = std.mem.splitScalar(u8, bytes, '\n');
        while (it.next()) |l| {
            const t = std.mem.trimEnd(u8, l, "\r");
            if (it.peek() == null and t.len == 0) break;
            try self.add(gpa, t, kind);
        }
    }

    // Zig tip: `clearRetainingCapacity` empties the list but keeps its memory for the next lines. The
    // text of every line is owned by the log, so each one is freed first.
    pub fn clear(self: *Log, gpa: std.mem.Allocator) void {
        for (self.lines.items) |l| gpa.free(l.text);
        self.lines.clearRetainingCapacity();
        self.scroll = 0;
    }

    // Zig tip: Cleanup runs in the opposite order of creation: the lines are freed first (`clear`),
    // then the list that held them.
    pub fn deinit(self: *Log, gpa: std.mem.Allocator) void {
        self.clear(gpa);
        self.lines.deinit(gpa);
    }
};

// Zig tip: Fields with a default value (`= ""`, `= 0`) can be left out when a value is written:
// `.{ .kind = "PNG image" }` fills the others.
/// What the card of a file that is not text shows.
pub const Card = struct { kind: []const u8 = "", size: u64 = 0, note: []const u8 = "" };

pub const Tab = struct {
    /// Relative to the project folder; empty for a new file that was never saved.
    path: []u8,
    /// Text files have a buffer; any other file has a card.
    buf: ?text.Buffer = null,
    card: Card = .{},
    eve: bool = false,

    // Zig tip: `self: Tab` takes a copy of the struct. The result is a slice into `self.path`, not a
    // new string, so it costs nothing. `if (cut) |i| a else b` unwraps the optional from
    // `lastIndexOfScalar`.
    pub fn title(self: Tab) []const u8 {
        if (self.path.len == 0) return "untitled";
        const cut = std.mem.lastIndexOfScalar(u8, self.path, '/');
        return if (cut) |i| self.path[i + 1 ..] else self.path;
    }
};

// Zig tip: `path` is owned (`[]u8`): every breakpoint has its own copy, freed when the breakpoint
// goes.
pub const Breakpoint = struct { path: []u8, line: usize };

// Zig tip: An enum with many values can be written over several lines. Each value is a command
// that the menu, a key or a click can ask for.
/// Every command of the main menu.
pub const MenuCmd = enum {
    open_project, new_file, save, save_as, close_tab, quit,
    undo, redo, find, replace,
    run, step_into, step_out, cont, stop, breakpoint,
    connect, upload, next_machine,
    help, settings,
};

// Zig tip: `cmd: ?MenuCmd = null` is an optional enum with a default: a row without a command is a
// section title. One struct serves both kinds of row.
/// A row of the menu: a section title (`cmd` null) or a command with its shortcut.
pub const MenuRow = struct { label: []const u8, key: []const u8 = "", cmd: ?MenuCmd = null };

// Zig tip: A `const` array of struct literals is built at compile time and stored in the program.
// `[_]MenuRow{...}` lets the compiler count the rows; `menu_rows.len` is then a compile-time
// number.
pub const menu_rows = [_]MenuRow{
    .{ .label = "File" },
    .{ .label = "Open project…", .key = "Ctrl+O", .cmd = .open_project },
    .{ .label = "New file", .key = "Ctrl+N", .cmd = .new_file },
    .{ .label = "Save", .key = "Ctrl+S", .cmd = .save },
    .{ .label = "Save As…", .key = "Ctrl+Shift+S", .cmd = .save_as },
    .{ .label = "Close tab", .key = "Ctrl+W", .cmd = .close_tab },
    .{ .label = "Quit", .key = "Ctrl+Q", .cmd = .quit },
    .{ .label = "Edit" },
    .{ .label = "Undo", .key = "Ctrl+Z", .cmd = .undo },
    .{ .label = "Redo", .key = "Ctrl+Y", .cmd = .redo },
    .{ .label = "Find", .key = "Ctrl+F", .cmd = .find },
    .{ .label = "Replace", .key = "Ctrl+H", .cmd = .replace },
    .{ .label = "Run" },
    .{ .label = "Run", .key = "F5", .cmd = .run },
    .{ .label = "Step into", .key = "F11", .cmd = .step_into },
    .{ .label = "Step out", .key = "Shift+F11", .cmd = .step_out },
    .{ .label = "Continue", .key = "F8", .cmd = .cont },
    .{ .label = "Stop", .key = "Shift+F5", .cmd = .stop },
    .{ .label = "Breakpoint", .key = "F9", .cmd = .breakpoint },
    .{ .label = "Machine" },
    .{ .label = "Connect…", .key = "Ctrl+K", .cmd = .connect },
    .{ .label = "Upload…", .key = "Ctrl+U", .cmd = .upload },
    .{ .label = "Next machine", .key = "Ctrl+→", .cmd = .next_machine },
    .{ .label = "Help" },
    .{ .label = "Help", .key = "Ctrl+/", .cmd = .help },
    .{ .label = "Settings…", .key = "Ctrl+,", .cmd = .settings },
};

// File kinds that open a card and never an editor (D-178): images, SVG, audio, video, archives,
// documents, programs and database files.
// Zig tip: A small private struct (no `pub`): only this file needs the pair of a file extension
// and its description.
const CardExt = struct { ext: []const u8, label: []const u8 };
const card_exts = [_]CardExt{
    .{ .ext = "png", .label = "PNG image" },       .{ .ext = "jpg", .label = "JPEG image" },
    .{ .ext = "jpeg", .label = "JPEG image" },     .{ .ext = "gif", .label = "GIF image" },
    .{ .ext = "bmp", .label = "BMP image" },       .{ .ext = "webp", .label = "WebP image" },
    .{ .ext = "ico", .label = "icon" },            .{ .ext = "svg", .label = "SVG image" },
    .{ .ext = "mp3", .label = "MP3 audio" },       .{ .ext = "wav", .label = "WAV audio" },
    .{ .ext = "flac", .label = "FLAC audio" },     .{ .ext = "ogg", .label = "Ogg audio" },
    .{ .ext = "m4a", .label = "M4A audio" },       .{ .ext = "mp4", .label = "MP4 video" },
    .{ .ext = "mkv", .label = "MKV video" },       .{ .ext = "avi", .label = "AVI video" },
    .{ .ext = "mov", .label = "MOV video" },       .{ .ext = "webm", .label = "WebM video" },
    .{ .ext = "zip", .label = "ZIP archive" },     .{ .ext = "gz", .label = "gzip archive" },
    .{ .ext = "tar", .label = "tar archive" },     .{ .ext = "7z", .label = "7-Zip archive" },
    .{ .ext = "pdf", .label = "PDF document" },    .{ .ext = "exe", .label = "program" },
    .{ .ext = "dll", .label = "library" },         .{ .ext = "db", .label = "database file" },
    .{ .ext = "duckdb", .label = "DuckDB database" }, .{ .ext = "sqlite", .label = "SQLite database" },
};

// Zig tip: The result is a slice of the argument, not a copy, so it is valid only as long as
// `path` is. `orelse return ""` leaves the function early when there is no dot.
fn extensionOf(path: []const u8) []const u8 {
    const base = if (std.mem.lastIndexOfScalar(u8, path, '/')) |i| path[i + 1 ..] else path;
    const dot = std.mem.lastIndexOfScalar(u8, base, '.') orelse return "";
    return base[dot + 1 ..];
}

// Zig tip: A function that may find nothing returns an optional (`?[]const u8`).
// `std.ascii.eqlIgnoreCase` compares two strings without regard to upper or lower case.
fn cardLabel(path: []const u8) ?[]const u8 {
    const ext = extensionOf(path);
    for (card_exts) |c| {
        if (std.ascii.eqlIgnoreCase(c.ext, ext)) return c.label;
    }
    return null;
}

// ------------------------------------------------------------------ the application

// Zig tip: The whole state of the program is one struct, so every function receives it as `self:
// *App`. Fields with a default (`= 0`, `= .empty`) can be left out when it is created.
pub const App = struct {
    gpa: std.mem.Allocator,
    io: Io,
    /// The project folder as given on the command line (a path from the current folder).
    root: []const u8,
    project_name: []const u8,
    tree: project.Tree,
    /// Rows of the tree that the last drawing showed (indices into `tree.entries`).
    visible: std.ArrayList(u32) = .empty,
    selected: u32 = 0,
    tree_top: usize = 0,

    tabs: std.ArrayList(Tab) = .empty,
    active: usize = 0,

    focus: Focus = .tree,
    overlay: Overlay = .none,
    bottom: BottomTab = .console,
    menu_sel: usize = 1,
    machine: u8 = 1,
    running: bool = false,
    quit: bool = false,

    files_in: TextInput,
    find_in: TextInput,
    replace_in: TextInput,
    console_in: TextInput,
    goto_in: TextInput,
    saveas_in: TextInput,

    console: Log = .{},
    stdout_log: Log = .{},
    stderr_log: Log = .{},
    history: std.ArrayList([]u8) = .empty,
    history_pos: ?usize = null,

    breakpoints: std.ArrayList(Breakpoint) = .empty,
    break_sel: usize = 0,

    /// The folders that were open before the file search started, to put them back on Esc.
    saved_open: ?[]bool = null,
    /// A message for the status bar (owned); it stays until the next key.
    message: ?[]u8 = null,

    hits: std.ArrayList(Hit) = .empty,
    // Zig tip: libvaxis keeps a pointer to every string that is drawn until the frame is rendered,
    // it does not copy the text. A string formatted into a local buffer would be gone by then.
    // So every string of a frame lives in this arena, which is emptied at the start of the next one.
    frame: std.heap.ArenaAllocator,
    tree_rect: Rect = .{},
    editor_rect: Rect = .{},
    console_rect: Rect = .{},
    breaks_rect: Rect = .{},

    // Zig tip: `create` allocates the App on the heap and returns a pointer to it. The arena inside
    // `tree` must stay where it is (project.zig), and a heap object never moves, unlike a local
    // variable that is copied when it is returned. `errdefer` runs only if the function fails later.
    pub fn create(gpa: std.mem.Allocator, io: Io, root: []const u8) !*App {
        const self = try gpa.create(App);
        errdefer gpa.destroy(self);
        const name = try projectName(gpa, io, root);
        errdefer gpa.free(name);
        self.* = .{
            .gpa = gpa,
            .io = io,
            .root = root,
            .project_name = name,
            .tree = project.Tree.init(gpa),
            .files_in = TextInput.init(gpa),
            .find_in = TextInput.init(gpa),
            .replace_in = TextInput.init(gpa),
            .console_in = TextInput.init(gpa),
            .goto_in = TextInput.init(gpa),
            .saveas_in = TextInput.init(gpa),
            .frame = .init(gpa),
        };
        try self.tree.scan(io, root, name);
        try self.console.add(gpa, "evetx: the console runs `eve` with what you type (run <file>, --check <file>, clear).", .info);
        return self;
    }

    // Zig tip: `for ([_]*TextInput{ &a, &b }) |ti|` loops over an array of pointers written in place.
    // `destroy` frees in the opposite order of `create`, and the last step frees the `App` itself.
    pub fn destroy(self: *App) void {
        const gpa = self.gpa;
        for (self.tabs.items) |*t| {
            if (t.buf) |*b| b.deinit();
            gpa.free(t.path);
        }
        self.tabs.deinit(gpa);
        self.tree.deinit();
        self.visible.deinit(gpa);
        for ([_]*TextInput{ &self.files_in, &self.find_in, &self.replace_in, &self.console_in, &self.goto_in, &self.saveas_in }) |ti| ti.deinit();
        self.console.deinit(gpa);
        self.stdout_log.deinit(gpa);
        self.stderr_log.deinit(gpa);
        for (self.history.items) |h| gpa.free(h);
        self.history.deinit(gpa);
        for (self.breakpoints.items) |b| gpa.free(b.path);
        self.breakpoints.deinit(gpa);
        if (self.saved_open) |s| gpa.free(s);
        if (self.message) |m| gpa.free(m);
        self.hits.deinit(gpa);
        self.frame.deinit();
        gpa.free(self.project_name);
        gpa.destroy(self);
    }

    // The name of the project: the last part of the folder's real path.
    // Zig tip: `var buf: [N]u8 = undefined` is a buffer on the stack that is not set to zero: it is
    // filled by the call that follows. `dir.realPath(io, &buf)` returns how many bytes it wrote, and
    // `buf[0..n]` is the part that counts.
    fn projectName(gpa: std.mem.Allocator, io: Io, root: []const u8) ![]u8 {
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        var dir = try Io.Dir.cwd().openDir(io, root, .{});
        defer dir.close(io);
        const n = dir.realPath(io, &buf) catch return gpa.dupe(u8, "project");
        const full = buf[0..n];
        const cut = std.mem.lastIndexOfAny(u8, full, "/\\");
        return gpa.dupe(u8, if (cut) |i| full[i + 1 ..] else full);
    }

    // ------------------------------------------------------------ messages and paths

    // Zig tip: `_ = x;` throws a value away on purpose: Zig does not let a result be ignored by
    // accident. `reset(.retain_capacity)` empties an arena and keeps its memory for the next frame.
    /// Start a frame: forget the strings of the last one.
    pub fn beginFrame(self: *App) void {
        _ = self.frame.reset(.retain_capacity);
    }

    // Zig tip: `comptime f: []const u8` is a format string that the compiler checks against `args`
    // (`anytype` takes any tuple). A wrong `{d}` for a string is a compile error. `catch "?"` shows a
    // mark instead of failing the drawing.
    /// Format a string that stays valid until the end of this frame (see `frame`).
    pub fn fmt(self: *App, comptime f: []const u8, args: anytype) []const u8 {
        return std.fmt.allocPrint(self.frame.allocator(), f, args) catch "?";
    }

    // Zig tip: The format string is `comptime`, as in `fmt`, and the old message is freed before the
    // new one is stored: the app owns exactly one message at a time.
    pub fn setMessage(self: *App, comptime f: []const u8, args: anytype) void {
        if (self.message) |m| self.gpa.free(m);
        self.message = std.fmt.allocPrint(self.gpa, f, args) catch null;
    }

    // Zig tip: A function that returns a new string says in its doc comment who frees it: here the
    // caller, with `self.gpa`. `std.fmt.allocPrint` builds the text in memory it allocates.
    /// The path of a file of the project, as the operating system wants it. The caller frees it.
    pub fn fullPath(self: *App, rel: []const u8) ![]u8 {
        if (std.mem.eql(u8, self.root, ".")) return self.gpa.dupe(u8, rel);
        return std.fmt.allocPrint(self.gpa, "{s}/{s}", .{ self.root, rel });
    }

    // Zig tip: `?*Tab` is an optional pointer: null when no tab is open. The caller can change the tab
    // through the pointer, and must unwrap it before use.
    pub fn activeTab(self: *App) ?*Tab {
        if (self.tabs.items.len == 0) return null;
        return &self.tabs.items[@min(self.active, self.tabs.items.len - 1)];
    }

    // Zig tip: `if (t.buf) |*b| return b;` unwraps an optional field by pointer (`|*b|`): `b` points
    // at the buffer inside the tab and is not a copy of it.
    pub fn activeBuffer(self: *App) ?*text.Buffer {
        const t = self.activeTab() orelse return null;
        if (t.buf) |*b| return b;
        return null;
    }

    // ------------------------------------------------------------ files and tabs

    // Zig tip: `for (xs, 0..) |t, i|` walks a slice and a counter together. `if (call) |v| {...} else
    // |err| {...}` takes the value of an error union or its error: here the file is read, or its error
    // name goes in the card.
    /// Open a file of the project in a tab (or go to its tab when it is open).
    pub fn openFile(self: *App, rel: []const u8) !void {
        for (self.tabs.items, 0..) |t, i| {
            if (std.mem.eql(u8, t.path, rel)) {
                self.active = i;
                self.focus = if (t.buf != null) .editor else .tree;
                return;
            }
        }
        var tab: Tab = .{ .path = try self.gpa.dupe(u8, rel) };
        errdefer self.gpa.free(tab.path);
        tab.eve = std.ascii.eqlIgnoreCase(extensionOf(rel), "eve");
        const full = try self.fullPath(rel);
        defer self.gpa.free(full);

        const size: u64 = if (Io.Dir.cwd().statFile(self.io, full, .{})) |st| st.size else |_| 0;
        if (cardLabel(rel)) |label| {
            tab.card = .{ .kind = label, .size = size, .note = if (std.ascii.eqlIgnoreCase(extensionOf(rel), "db") or std.ascii.eqlIgnoreCase(extensionOf(rel), "duckdb") or std.ascii.eqlIgnoreCase(extensionOf(rel), "sqlite")) "The list of tables comes with step T7 (README.md §8)." else "No preview in evetx. The rendered file is shown by eveux (eve -ux)." };
        } else if (Io.Dir.cwd().readFileAlloc(self.io, full, self.gpa, .limited(8 << 20))) |bytes| {
            defer self.gpa.free(bytes);
            if (std.mem.indexOfScalar(u8, bytes[0..@min(bytes.len, 4096)], 0) != null) {
                tab.card = .{ .kind = "binary file", .size = size, .note = "Not text: evetx does not open it in the editor." };
            } else {
                var b = try text.Buffer.init(self.gpa);
                errdefer b.deinit();
                try b.load(bytes);
                if (b.tabs_replaced) self.setMessage("{s}: tabs were replaced by spaces", .{rel});
                tab.buf = b;
            }
        } else |err| {
            tab.card = .{ .kind = "file", .size = size, .note = @errorName(err) };
        }
        try self.tabs.append(self.gpa, tab);
        self.active = self.tabs.items.len - 1;
        self.focus = if (tab.buf != null) .editor else .tree;
    }

    // Zig tip: `orderedRemove(i)` takes element `i` out of the list, keeps the order of the others and
    // returns the element, which we own and free. A `var` is needed because we call methods that
    // change it.
    pub fn closeTab(self: *App, index: usize) void {
        if (index >= self.tabs.items.len) return;
        var t = self.tabs.orderedRemove(index);
        if (t.buf) |*b| b.deinit();
        self.gpa.free(t.path);
        if (self.active >= self.tabs.items.len and self.tabs.items.len > 0) self.active = self.tabs.items.len - 1;
        if (self.tabs.items.len == 0) self.active = 0;
    }

    // Zig tip: `.{ .path = ..., .buf = b, .eve = true }` is a struct literal; the fields that are not
    // written take their defaults. The anonymous literal takes its type from `append`.
    pub fn newFile(self: *App) !void {
        var b = try text.Buffer.init(self.gpa);
        errdefer b.deinit();
        try self.tabs.append(self.gpa, .{ .path = try self.gpa.dupe(u8, ""), .buf = b, .eve = true });
        self.active = self.tabs.items.len - 1;
        self.focus = .editor;
    }

    // Zig tip: `return self.openOverlay(...)` returns the result of a call that returns `void`: legal,
    // and it ends the function. Errors from `writeTab` go up through `try`.
    pub fn save(self: *App) !void {
        const t = self.activeTab() orelse return;
        if (t.buf == null) return;
        if (t.path.len == 0) {
            self.openOverlay(.save_as);
            return;
        }
        try self.writeTab(t, t.path);
        self.setMessage("saved {s}", .{t.path});
    }

    // Zig tip: `defer self.gpa.free(bytes)` frees the buffer when the function ends, on every path
    // including a failed write. Two `defer` lines run in the opposite order.
    fn writeTab(self: *App, t: *Tab, rel: []const u8) !void {
        const b = &t.buf.?;
        const bytes = try b.toBytes(self.gpa);
        defer self.gpa.free(bytes);
        const full = try self.fullPath(rel);
        defer self.gpa.free(full);
        try Io.Dir.cwd().writeFile(self.io, .{ .sub_path = full, .data = bytes });
        b.dirty = false;
    }

    // Zig tip: After `free` the old slice must not be used. The code stores the new one in `t.path` at
    // once, so the tab is never left pointing at freed memory.
    pub fn saveAs(self: *App, rel: []const u8) !void {
        const t = self.activeTab() orelse return;
        if (t.buf == null or rel.len == 0) return;
        try self.writeTab(t, rel);
        if (!std.mem.eql(u8, t.path, rel)) {
            self.gpa.free(t.path);
            t.path = try self.gpa.dupe(u8, rel);
            t.eve = std.ascii.eqlIgnoreCase(extensionOf(rel), "eve");
        }
        self.setMessage("saved {s}", .{rel});
    }

    // ------------------------------------------------------------ breakpoints

    // Zig tip: `const b = t.buf orelse return;` unwraps an optional or leaves the function. Removing
    // from the list while looping is safe here because the loop returns right after `orderedRemove`.
    pub fn toggleBreakpoint(self: *App) !void {
        const t = self.activeTab() orelse return;
        const b = t.buf orelse return;
        if (t.path.len == 0) {
            self.setMessage("save the file first: a breakpoint needs a file", .{});
            return;
        }
        const line = b.row + 1;
        for (self.breakpoints.items, 0..) |bp, i| {
            if (bp.line == line and std.mem.eql(u8, bp.path, t.path)) {
                self.gpa.free(bp.path);
                _ = self.breakpoints.orderedRemove(i);
                return;
            }
        }
        try self.breakpoints.append(self.gpa, .{ .path = try self.gpa.dupe(u8, t.path), .line = line });
    }

    // Zig tip: `self: *const App` is enough for a function that only looks. The view calls it for
    // every line it draws, so it does no allocation.
    pub fn hasBreakpoint(self: *const App, path: []const u8, line: usize) bool {
        for (self.breakpoints.items) |bp| {
            if (bp.line == line and std.mem.eql(u8, bp.path, path)) return true;
        }
        return false;
    }

    // Zig tip: A private function (no `pub`) of the struct: only the code of `App` can call it. It
    // uses `try` for the calls that can fail and passes the error on.
    fn jumpToBreakpoint(self: *App, index: usize) !void {
        if (index >= self.breakpoints.items.len) return;
        const bp = self.breakpoints.items[index];
        try self.openFile(bp.path);
        if (self.activeBuffer()) |b| b.gotoLine(bp.line, 0);
        self.focus = .editor;
    }

    // ------------------------------------------------------------ run and the console

    // Zig tip: A `const` inside a struct is shared by all instances. The `if` on `builtin.os.tag` is
    // decided by the compiler: the Windows build contains "eve.exe" and no other name.
    const eve_exe = if (builtin.os.tag == .windows) "eve.exe" else "eve";

    // Zig tip: `std.process.run` starts a program, waits for it and returns what it wrote on both
    // streams as slices that the caller must free (the two `defer`s). `catch |err| {...}` handles the
    // error inline and `return`s from the function.
    /// Run `eve` with these arguments in the project folder; its output goes to the Stdout and
    /// Stderr tabs and a summary to the console. It waits until the program ends.
    pub fn runEve(self: *App, args: []const []const u8) !void {
        const gpa = self.gpa;
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(gpa);
        try argv.append(gpa, eve_exe);
        try argv.appendSlice(gpa, args);

        self.stdout_log.clear(gpa);
        self.stderr_log.clear(gpa);
        const cwd: std.process.Child.Cwd = if (std.mem.eql(u8, self.root, ".")) .inherit else .{ .path = self.root };
        const result = std.process.run(gpa, self.io, .{ .argv = argv.items, .cwd = cwd }) catch |err| {
            const msg = try std.fmt.allocPrint(gpa, "cannot start {s}: {s} (is bin/ in the PATH?)", .{ eve_exe, @errorName(err) });
            defer gpa.free(msg);
            try self.console.add(gpa, msg, .err);
            return;
        };
        defer gpa.free(result.stdout);
        defer gpa.free(result.stderr);
        try self.stdout_log.addBlock(gpa, result.stdout, .out);
        try self.stderr_log.addBlock(gpa, result.stderr, .err);
        try self.console.addBlock(gpa, result.stdout, .out);
        try self.console.addBlock(gpa, result.stderr, .err);
        const summary = switch (result.term) {
            .exited => |code| try std.fmt.allocPrint(gpa, "finished, exit {d}", .{code}),
            else => try std.fmt.allocPrint(gpa, "ended by a signal", .{}),
        };
        defer gpa.free(summary);
        try self.console.add(gpa, summary, .info);
    }

    // Zig tip: `orelse { ...; return; }` can hold a block: unwrap the optional, or run the block and
    // leave. After that line `t` is a plain pointer, not an optional.
    /// F5, the Run button: save the file and run it.
    pub fn runActive(self: *App) !void {
        const t = self.activeTab() orelse {
            self.setMessage("nothing to run: open an .eve file", .{});
            return;
        };
        if (t.buf == null or !t.eve) {
            self.setMessage("Run needs an .eve file", .{});
            return;
        }
        if (t.path.len == 0 or t.buf.?.dirty) try self.save();
        if (t.path.len == 0) return;
        const line = try std.fmt.allocPrint(self.gpa, "run {s}", .{t.path});
        defer self.gpa.free(line);
        try self.console.add(self.gpa, line, .input);
        try self.runEve(&.{t.path});
    }

    // Zig tip: `std.mem.tokenizeScalar` skips empty pieces, so two spaces count as one.
    // `words.items[1..]` is the slice from the second word on. Slices make "the rest of the list"
    // free.
    fn consoleEnter(self: *App) !void {
        const line = try self.console_in.toOwnedContents(self.gpa);
        defer self.gpa.free(line);
        self.console_in.clearRetainingCapacity();
        self.history_pos = null;
        const cmd = std.mem.trim(u8, line, " ");
        if (cmd.len == 0) return;
        try self.history.append(self.gpa, try self.gpa.dupe(u8, cmd));
        try self.console.add(self.gpa, cmd, .input);

        if (std.mem.eql(u8, cmd, "clear")) {
            self.console.clear(self.gpa);
            return;
        }
        var words: std.ArrayList([]const u8) = .empty;
        defer words.deinit(self.gpa);
        var it = std.mem.tokenizeScalar(u8, cmd, ' ');
        while (it.next()) |w| try words.append(self.gpa, w);
        // `run x.eve` is `eve x.eve`; any other line is given to eve as its arguments.
        const args = if (std.mem.eql(u8, words.items[0], "run")) words.items[1..] else words.items;
        self.running = true;
        try self.runEve(args);
        self.running = false;
    }

    // Zig tip: `isize` is the signed integer of pointer width, used because the position can go below
    // zero before `clamp` brings it back. `@intCast` converts between integer types and checks the
    // value in safe builds.
    fn historyStep(self: *App, delta: isize) !void {
        if (self.history.items.len == 0) return;
        const n: isize = @intCast(self.history.items.len);
        var pos: isize = if (self.history_pos) |p| @intCast(p) else n;
        pos = std.math.clamp(pos + delta, 0, n);
        self.console_in.clearRetainingCapacity();
        if (pos < n) {
            self.history_pos = @intCast(pos);
            try self.console_in.insertSliceAtCursor(self.history.items[@intCast(pos)]);
        } else self.history_pos = null;
    }

    // ------------------------------------------------------------ the two searches

    // Zig tip: A function can return early from `if (q.len == 0) {...; return;}`. The snapshot `snap`
    // is a slice of `bool`, one per entry, allocated with `gpa.alloc(bool, n)` and freed in
    // `filesRestore`.
    /// The Files search: the tree goes to the first name that starts with the typed letters and opens the way to it.
    fn filesChanged(self: *App) !void {
        const q = try self.files_in.toOwnedContents(self.gpa);
        defer self.gpa.free(q);
        if (q.len == 0) {
            self.filesRestore();
            return;
        }
        if (self.saved_open == null) {
            const snap = try self.gpa.alloc(bool, self.tree.entries.items.len);
            for (self.tree.entries.items, 0..) |e, i| snap[i] = e.expanded;
            self.saved_open = snap;
        }
        if (self.nextMatch(q, 0, 1)) |i| self.selectEntry(i);
    }

    // Zig tip: `@mod(i, n)` is the modulo that stays positive for a negative `i`, which `%` does not
    // allow on signed numbers. It lets the loop wrap in both directions. The result is `?u32`: null
    // when nothing matches.
    /// The first entry at or after `from` (going `step` entries at a time, wrapping) whose name starts with `q`.
    fn nextMatch(self: *App, q: []const u8, from: usize, step: isize) ?u32 {
        const n: isize = @intCast(self.tree.entries.items.len);
        var i: isize = @intCast(from);
        var k: isize = 0;
        while (k < n) : (k += 1) {
            const idx: usize = @intCast(@mod(i, n));
            const e = self.tree.entries.items[idx];
            if (e.parent != null and e.name.len >= q.len and std.ascii.eqlIgnoreCase(e.name[0..q.len], q)) return @intCast(idx);
            i += step;
        }
        return null;
    }

    // Zig tip: A tiny function with a name is clearer than the two lines it holds, and the two places
    // that select an entry now agree.
    fn selectEntry(self: *App, i: u32) void {
        self.tree.expandTo(i);
        self.selected = i;
    }

    // Zig tip: `@as(isize, @intCast(x))` again: first the width, then the type.
    // `std.ascii.eqlIgnoreCase` and `startsWith` are not used here because `nextMatch` does the
    // matching.
    fn filesStep(self: *App, step: isize) !void {
        const q = try self.files_in.toOwnedContents(self.gpa);
        defer self.gpa.free(q);
        if (q.len == 0) return;
        const from: isize = @as(isize, @intCast(self.selected)) + step;
        if (self.nextMatch(q, @intCast(@mod(from, @as(isize, @intCast(self.tree.entries.items.len)))), step)) |i| self.selectEntry(i);
    }

    // Zig tip: `snap` is freed after its values are copied back. Setting `self.saved_open = null`
    // makes sure that a second call finds nothing to restore and cannot free it twice.
    fn filesRestore(self: *App) void {
        if (self.saved_open) |snap| {
            for (self.tree.entries.items, 0..) |*e, i| {
                if (i < snap.len) e.expanded = snap[i];
            }
            self.gpa.free(snap);
            self.saved_open = null;
        }
    }

    // Zig tip: Several small functions are composed here: restore, clear, change focus. Each one can
    // be read, and tested by hand, alone.
    fn filesCancel(self: *App) void {
        self.filesRestore();
        self.files_in.clearRetainingCapacity();
        self.focus = .tree;
    }

    // Zig tip: A method of `App` may have the same name as a method of `Buffer`: each belongs to its
    // own struct, and the call `b.findNext(q)` says which one is meant.
    fn findNext(self: *App) !void {
        const b = self.activeBuffer() orelse return;
        const q = try self.find_in.toOwnedContents(self.gpa);
        defer self.gpa.free(q);
        if (!b.findNext(q)) self.setMessage("not found: {s}", .{q});
    }

    // Zig tip: `if (!try b.replaceMatch(q, w))`: `try` is applied first, then `!` negates the `bool`.
    // The function says to the user what happened through `setMessage`.
    fn replaceOne(self: *App) !void {
        const b = self.activeBuffer() orelse return;
        const q = try self.find_in.toOwnedContents(self.gpa);
        defer self.gpa.free(q);
        const w = try self.replace_in.toOwnedContents(self.gpa);
        defer self.gpa.free(w);
        if (!try b.replaceMatch(q, w)) self.setMessage("no more matches", .{});
    }

    // Zig tip: `{d}` in the format prints an integer in decimal. The count comes from `replaceAll`,
    // which returns a `usize`.
    fn replaceEvery(self: *App) !void {
        const b = self.activeBuffer() orelse return;
        const q = try self.find_in.toOwnedContents(self.gpa);
        defer self.gpa.free(q);
        const w = try self.replace_in.toOwnedContents(self.gpa);
        defer self.gpa.free(w);
        const n = try b.replaceAll(q, w);
        self.setMessage("{d} replaced", .{n});
    }

    // Zig tip: `std.fmt.parseInt(usize, text, 10)` turns text into a number or returns an error;
    // `catch { ...; return; }` handles the error with a block and `catch 0` supplies a default.
    /// The `#` prompt: `42` or `42:7` goes to a line (and a column).
    fn gotoEnter(self: *App) !void {
        const s = try self.goto_in.toOwnedContents(self.gpa);
        defer self.gpa.free(s);
        self.goto_in.clearRetainingCapacity();
        self.overlay = .none;
        const b = self.activeBuffer() orelse {
            self.setMessage("# works in an editor (records of a table come with step T7)", .{});
            return;
        };
        const t = std.mem.trim(u8, s, " ");
        const colon = std.mem.indexOfScalar(u8, t, ':');
        const line = std.fmt.parseInt(usize, if (colon) |c| t[0..c] else t, 10) catch {
            self.setMessage("not a line number: {s}", .{t});
            return;
        };
        const col = if (colon) |c| std.fmt.parseInt(usize, t[c + 1 ..], 10) catch 0 else 0;
        b.gotoLine(line, col);
        self.focus = .editor;
    }

    // ------------------------------------------------------------ overlays and the menu

    // Zig tip: `which: Overlay` is an enum parameter: callers write `.menu`. Zig finds the enum from
    // the parameter type, so no `Overlay.` prefix is needed.
    pub fn openOverlay(self: *App, which: Overlay) void {
        self.overlay = which;
        if (which == .menu and self.menu_sel >= menu_rows.len) self.menu_sel = 1;
    }

    // Zig tip: A helper for the features that are planned but not built, so the message is the same
    // everywhere and easy to find with a search for `notYet`.
    fn notYet(self: *App, what: []const u8, step: []const u8) void {
        self.setMessage("{s}: not yet ({s}, README.md §8)", .{ what, step });
    }

    // Zig tip: A `switch` over an enum with one branch for each value. The compiler checks that every
    // command has a branch. A branch may be a block, a call, or `try` on a call.
    pub fn runMenu(self: *App, cmd: MenuCmd) !void {
        self.overlay = .none;
        switch (cmd) {
            .open_project => self.notYet("Open project", "T5"),
            .new_file => try self.newFile(),
            .save => try self.save(),
            .save_as => self.openOverlay(.save_as),
            .close_tab => self.closeTab(self.active),
            .quit => self.quit = true,
            .undo, .redo => self.notYet("Undo and redo", "T3"),
            .find => self.focus = .find,
            .replace => self.focus = .replace,
            .run => try self.runActive(),
            .step_into, .step_out, .cont, .stop => self.notYet("The debugger", "T6"),
            .breakpoint => try self.toggleBreakpoint(),
            .connect, .upload, .next_machine => self.notYet("Remote machines", "T5"),
            .help => self.openOverlay(.help),
            .settings => self.openOverlay(.settings),
        }
    }

    // Zig tip: `while (true) {... break;}` loops until a `break`. `@mod` wraps the index; the loop
    // skips the rows that have no command (section titles).
    fn menuMove(self: *App, delta: isize) void {
        var i: isize = @intCast(self.menu_sel);
        const n: isize = menu_rows.len;
        while (true) {
            i = @mod(i + delta, n);
            if (menu_rows[@intCast(i)].cmd != null) break;
        }
        self.menu_sel = @intCast(i);
    }

    // ------------------------------------------------------------ keys

    // Zig tip: `key.matches(codepoint, mods)` compares a key with a letter and the modifier keys,
    // written as a struct with defaults: `.{ .ctrl = true }`. The order of the `if`s matters: the
    // first that matches wins.
    pub fn onKey(self: *App, key: Key) !void {
        if (self.message) |m| {
            self.gpa.free(m);
            self.message = null;
        }
        if (self.overlay != .none) return self.overlayKey(key);

        if (key.matches(Key.enter, .{ .ctrl = true }) or key.matches(Key.f10, .{})) return self.openOverlay(.menu);
        if (key.matches('/', .{ .ctrl = true }) or key.matches(Key.f12, .{})) return self.openOverlay(.help);
        if (key.matches(',', .{ .ctrl = true })) return self.openOverlay(.settings);
        if (key.matches('q', .{ .ctrl = true })) {
            self.quit = true;
            return;
        }
        if (key.matches('s', .{ .ctrl = true, .shift = true })) return self.openOverlay(.save_as);
        if (key.matches('s', .{ .ctrl = true })) return self.save();
        if (key.matches('w', .{ .ctrl = true })) return self.closeTab(self.active);
        if (key.matches('n', .{ .ctrl = true })) return self.newFile();
        if (key.matches('p', .{ .ctrl = true })) {
            self.focus = .files;
            return;
        }
        if (key.matches('f', .{ .ctrl = true })) {
            self.focus = .find;
            return;
        }
        if (key.matches('h', .{ .ctrl = true })) {
            self.focus = .replace;
            return;
        }
        if (key.matches('g', .{ .ctrl = true })) return self.openOverlay(.goto);
        if (key.matches(Key.f5, .{})) return self.runActive();
        if (key.matches(Key.f9, .{})) return self.toggleBreakpoint();
        if (key.matches(Key.f1, .{})) return self.pickMachine(1);
        if (key.matches(Key.f2, .{})) return self.pickMachine(2);
        if (key.matches(Key.f3, .{})) return self.pickMachine(3);
        if (key.matches(Key.f11, .{}) or key.matches(Key.f8, .{}) or key.matches(Key.f5, .{ .shift = true })) {
            self.notYet("The debugger", "T6");
            return;
        }

        switch (self.focus) {
            .editor => try self.editorKey(key),
            .tree => try self.treeKey(key),
            .files => try self.filesKey(key),
            .find => try self.findKey(key),
            .replace => try self.replaceKey(key),
            .console => try self.consoleKey(key),
            .breaks => try self.breaksKey(key),
        }
    }

    // Zig tip: `n == 1` and `else`: the value `u8` is a small integer type of one byte; here 1, 2 and
    // 3 are the F-keys. Real machines come with step T5.
    fn pickMachine(self: *App, n: u8) void {
        if (n == 1) {
            self.machine = 1;
            self.setMessage("connection: local", .{});
        } else self.notYet("A remote machine", "T5");
    }

    // Zig tip: `switch (self.overlay)` on an enum, with `.none => {}` for the value that needs
    // nothing. An `if` chain with `else if` works as well, but the `switch` lists every case.
    fn overlayKey(self: *App, key: Key) !void {
        if (key.matches(Key.escape, .{})) {
            self.overlay = .none;
            return;
        }
        switch (self.overlay) {
            .menu => {
                if (key.matches(Key.up, .{})) self.menuMove(-1) else if (key.matches(Key.down, .{})) self.menuMove(1) else if (key.matches(Key.enter, .{})) {
                    if (menu_rows[self.menu_sel].cmd) |c| try self.runMenu(c);
                }
            },
            .help, .settings => {
                if (key.matches('/', .{ .ctrl = true }) or key.matches(Key.f12, .{}) or key.matches(Key.enter, .{})) self.overlay = .none;
            },
            .goto => {
                if (key.matches(Key.enter, .{})) try self.gotoEnter() else try self.goto_in.update(.{ .key_press = key });
            },
            .save_as => {
                if (key.matches(Key.enter, .{})) {
                    const s = try self.saveas_in.toOwnedContents(self.gpa);
                    defer self.gpa.free(s);
                    self.saveas_in.clearRetainingCapacity();
                    self.overlay = .none;
                    try self.saveAs(std.mem.trim(u8, s, " "));
                } else try self.saveas_in.update(.{ .key_press = key });
            },
            .none => {},
        }
    }

    // Zig tip: A long chain of `else if` ends in `else if (key.text) |t| ...`: the text of a printable
    // key is an optional slice, and it is typed only when no control key was held.
    fn editorKey(self: *App, key: Key) !void {
        const b = self.activeBuffer() orelse return;
        if (key.matches(Key.left, .{})) b.moveLeft() else if (key.matches(Key.right, .{})) b.moveRight() else if (key.matches(Key.up, .{})) b.moveRows(-1) else if (key.matches(Key.down, .{})) b.moveRows(1) else if (key.matches(Key.page_up, .{})) b.moveRows(-@as(isize, self.editor_rect.h)) else if (key.matches(Key.page_down, .{})) b.moveRows(@as(isize, self.editor_rect.h)) else if (key.matches(Key.home, .{})) b.home() else if (key.matches(Key.end, .{})) b.toEnd() else if (key.matches(Key.enter, .{})) try b.newline() else if (key.matches(Key.backspace, .{})) try b.backspace() else if (key.matches(Key.delete, .{})) try b.delete() else if (key.matches(Key.tab, .{})) try b.insert("  ") else if (key.mods.ctrl or key.mods.alt) {
            // a shortcut that is not ours: do not type its letter
        } else if (key.text) |t| try b.insert(t);
    }

    // Zig tip: `self.selected = rows[pos -| 10]` uses `-|`, the subtraction that stops at zero instead
    // of failing on an unsigned number that would go below zero. `+|` does the same for the top.
    fn treeKey(self: *App, key: Key) !void {
        const rows = self.visible.items;
        if (rows.len == 0) return;
        var pos: usize = 0;
        for (rows, 0..) |r, i| {
            if (r == self.selected) pos = i;
        }
        const e = &self.tree.entries.items[self.selected];
        if (key.matches(Key.up, .{})) {
            self.selected = rows[if (pos > 0) pos - 1 else 0];
        } else if (key.matches(Key.down, .{})) {
            self.selected = rows[@min(pos + 1, rows.len - 1)];
        } else if (key.matches(Key.right, .{})) {
            if (e.is_dir) e.expanded = true;
        } else if (key.matches(Key.left, .{})) {
            if (e.is_dir and e.expanded and e.parent != null) e.expanded = false else if (e.parent) |p| self.selected = p;
        } else if (key.matches(Key.enter, .{}) or key.matches(Key.space, .{})) {
            try self.openEntry(self.selected);
        } else if (key.matches(Key.page_up, .{})) {
            self.selected = rows[pos -| 10];
        } else if (key.matches(Key.page_down, .{})) {
            self.selected = rows[@min(pos + 10, rows.len - 1)];
        }
    }

    // Zig tip: `const e = &self.tree.entries.items[index];` is a pointer to the entry, so `e.expanded
    // = !e.expanded` changes the tree itself and not a copy.
    pub fn openEntry(self: *App, index: u32) !void {
        const e = &self.tree.entries.items[index];
        self.selected = index;
        if (e.is_dir) {
            if (e.parent != null) e.expanded = !e.expanded;
        } else try self.openFile(e.path);
    }

    // Zig tip: The keys are tried in order: Esc, Enter, Up and Down belong to the search; any other
    // key goes to the text field widget with `update`. The `had` flag shows `if` used as a plain
    // statement.
    fn filesKey(self: *App, key: Key) !void {
        if (key.matches(Key.escape, .{})) return self.filesCancel();
        if (key.matches(Key.enter, .{})) {
            const had = self.saved_open != null;
            if (had) {
                self.gpa.free(self.saved_open.?);
                self.saved_open = null;
            }
            self.files_in.clearRetainingCapacity();
            self.focus = .tree;
            return self.openEntry(self.selected);
        }
        if (key.matches(Key.down, .{})) return self.filesStep(1);
        if (key.matches(Key.up, .{})) return self.filesStep(-1);
        try self.files_in.update(.{ .key_press = key });
        try self.filesChanged();
    }

    // Zig tip: `try self.find_in.update(.{ .key_press = key })` hands the key to the text field of
    // libvaxis. The `.{ .key_press = key }` literal takes its type from the parameter.
    fn findKey(self: *App, key: Key) !void {
        if (key.matches(Key.escape, .{})) {
            self.focus = .editor;
            return;
        }
        if (key.matches(Key.enter, .{})) return self.findNext();
        try self.find_in.update(.{ .key_press = key });
    }

    // Zig tip: The same shape as `findKey`: Esc leaves, Enter does the action, other keys edit the
    // text.
    fn replaceKey(self: *App, key: Key) !void {
        if (key.matches(Key.escape, .{})) {
            self.focus = .editor;
            return;
        }
        if (key.matches(Key.enter, .{})) return self.replaceOne();
        try self.replace_in.update(.{ .key_press = key });
    }

    // Zig tip: `self.console.scroll +|= n` is saturating addition with assignment: it stops at the
    // largest number instead of failing on overflow. `-|=` stops at zero.
    fn consoleKey(self: *App, key: Key) !void {
        if (key.matches(Key.escape, .{})) {
            self.focus = .editor;
            return;
        }
        if (key.matches(Key.enter, .{})) return self.consoleEnter();
        if (key.matches(Key.up, .{ .ctrl = true })) return self.historyStep(-1);
        if (key.matches(Key.down, .{ .ctrl = true })) return self.historyStep(1);
        if (key.matches(Key.page_up, .{})) {
            self.console.scroll +|= @max(1, self.console_rect.h / 2);
            return;
        }
        if (key.matches(Key.page_down, .{})) {
            self.console.scroll -|= @max(1, self.console_rect.h / 2);
            return;
        }
        try self.console_in.update(.{ .key_press = key });
    }

    // Zig tip: `orderedRemove` returns the removed element and we ignore it with `_ =`: the path was
    // freed one line before. The index is clamped after the removal so it never points past the end.
    fn breaksKey(self: *App, key: Key) !void {
        const n = self.breakpoints.items.len;
        if (n == 0) return;
        if (key.matches(Key.up, .{})) self.break_sel = self.break_sel -| 1 else if (key.matches(Key.down, .{})) self.break_sel = @min(self.break_sel + 1, n - 1) else if (key.matches(Key.enter, .{})) try self.jumpToBreakpoint(self.break_sel) else if (key.matches(Key.delete, .{})) {
            self.gpa.free(self.breakpoints.items[self.break_sel].path);
            _ = self.breakpoints.orderedRemove(self.break_sel);
            self.break_sel = @min(self.break_sel, self.breakpoints.items.len -| 1);
        }
    }

    // ------------------------------------------------------------ the mouse

    // Zig tip: `m.type != .press` compares an enum value. The `while (i > 0) { i -= 1; ... }` loop
    // walks the hits from the last to the first, so what was drawn last (an open menu) is hit first.
    pub fn onMouse(self: *App, m: vaxis.Mouse) !void {
        if (m.type != .press) return;
        if (m.button == .wheel_up or m.button == .wheel_down) {
            const up = m.button == .wheel_up;
            if (self.tree_rect.contains(m.col, m.row)) {
                self.tree_top = if (up) self.tree_top -| 3 else self.tree_top + 3;
            } else if (self.editor_rect.contains(m.col, m.row)) {
                if (self.activeBuffer()) |b| b.top = if (up) b.top -| 3 else @min(b.top + 3, b.lineCount() - 1);
            } else if (self.console_rect.contains(m.col, m.row)) {
                const log = switch (self.bottom) {
                    .stdout => &self.stdout_log,
                    .stderr => &self.stderr_log,
                    else => &self.console,
                };
                log.scroll = if (up) log.scroll +| 3 else log.scroll -| 3;
            }
            return;
        }
        if (m.button != .left) return;

        var i = self.hits.items.len;
        while (i > 0) {
            i -= 1;
            const h = self.hits.items[i];
            if (h.rect.contains(m.col, m.row)) return self.activate(h.action);
        }
        if (self.overlay != .none) {
            self.overlay = .none;
            return;
        }
        if (self.editor_rect.contains(m.col, m.row)) {
            if (self.activeBuffer()) |b| {
                const row = b.top + @as(usize, @intCast(@as(i32, m.row) - self.editor_rect.y));
                b.row = @min(row, b.lineCount() - 1);
                const dc = b.left + @as(usize, @intCast(@as(i32, m.col) - self.editor_rect.x));
                b.col = text.Buffer.byteAtDisplay(b.lineAt(b.row), dc);
                self.focus = .editor;
            }
        } else if (self.console_rect.contains(m.col, m.row) and self.bottom == .console) {
            self.focus = .console;
        }
    }

    // Zig tip: `switch` on the `Action` union with a payload capture in each branch: `.tree_row => |i|
    // ...` gives the index that the click carried. The inner `switch (b)` handles the buttons.
    fn activate(self: *App, action: Action) !void {
        switch (action) {
            .tree_row => |i| {
                self.focus = .tree;
                try self.openEntry(i);
            },
            .tab => |i| {
                self.active = i;
                self.focus = if (self.tabs.items[i].buf != null) .editor else .tree;
            },
            .tab_close => |i| self.closeTab(i),
            .bottom => |t| {
                self.bottom = t;
                self.focus = switch (t) {
                    .console => .console,
                    .breaks => .breaks,
                    else => self.focus,
                };
            },
            .machine => |n| self.pickMachine(n),
            .menu_title => self.openOverlay(.menu),
            .menu_item => |i| {
                if (menu_rows[i].cmd) |c| try self.runMenu(c);
            },
            .field => |f| self.focus = f,
            .break_row => |i| {
                if (self.break_sel == i) try self.jumpToBreakpoint(i) else self.break_sel = i;
                self.focus = .breaks;
            },
            .close_overlay => self.overlay = .none,
            .button => |b| switch (b) {
                .run => try self.runActive(),
                .step_into, .step_out, .cont, .stop => self.notYet("The debugger", "T6"),
                .replace => try self.replaceOne(),
                .replace_all => try self.replaceEvery(),
                .goto => self.openOverlay(.goto),
                .help => self.openOverlay(.help),
                .settings => self.openOverlay(.settings),
            },
        }
    }
};
