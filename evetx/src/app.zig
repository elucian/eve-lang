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
const cache_mod = @import("cache.zig");

// ------------------------------------------------------------------ small types

// Zig tip: An `enum` names a fixed set of choices. A `switch` on an enum must handle every value
// or have an `else`, so adding a choice later makes the compiler point at every place that needs a
// new case.
/// Where the keyboard goes.
pub const Focus = enum { tree, editor, console, breaks };

// Zig tip: An enum like `Focus`: one name for every tab. `@tagName(tab)` would give its name as
// text.
/// The five tabs of the Tools Panel.
pub const BottomTab = enum { console, watch, stderr, stdout, breaks };

// Zig tip: The three panels of the screen are an enum too. The keyboard focus (`Focus`) is finer
// than this: the Main Panel is the `editor` focus, the Tools Panel is `console` or `breaks`.
/// The three panels: the files tree, the windows with their editor, the console and the other tools.
pub const Panel = enum { tree, main, tools };

// Zig tip: The state "what is open over the screen" is one enum, so two dialogs can never be open
// together.
/// What is open over the screen, if anything.
pub const Overlay = enum { none, menu, settings, about, goto, save_as, find_text, find_file, replace, open_project, open_folder };

// Zig tip: Naming every button lets `activate` use one `switch` for all clicks. `cont` is written
// instead of `continue` because `continue` is a keyword of Zig.
/// The buttons of the tool bars.
pub const Button = enum { run, step_into, step_out, cont, stop, replace, replace_all };

// Zig tip: A tagged union with payloads, like `Event` in main.zig. `.tree_row = 5` builds a value;
// `switch (a) { .tree_row => |i| ... }` reads its payload. A field without a payload
// (`menu_title`) has type `void`.
/// The buttons of the dialogs that are not a plain "close": `ok` does what Enter does in that dialog.
pub const DlgAction = enum { ok, forget, browse, open_here };

/// What a click on a clickable place does (see `Hit`).
pub const Action = union(enum) {
    tree_row: u32,
    tab: usize,
    tab_close: usize,
    bottom: BottomTab,
    button: Button,
    machine: u8,
    menu_top: usize,
    menu_item: usize,
    dlg_field: u8,
    break_row: usize,
    close_overlay,
    nop,
    panel_focus: Panel,
    panel_hide: Panel,
    panel_max: Panel,
    dlg: DlgAction,
    proj_row: usize,
    fb_row: usize,
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
    /// A window that is not a file (Shortcuts, Manual, Tutorial): read only, never saved.
    virtual: bool = false,

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
// that the menu, a key or a click can ask for. A command that needs a number (which window, which
// machine) gets it in the `arg` of its row.
/// Every command of the main menu.
pub const MenuCmd = enum {
    open_project, open_folder, new_file, save, save_as, close_tab, quit,
    undo, redo, replace,
    find_text, find_file, goto_line, query,
    run, check_file, step_into, step_out, cont, stop, breakpoint,
    machine_pick, connect, upload,
    select_window, modify, freeze, toggle_tree, toggle_main, toggle_tools, window_pick,
    shortcuts, manual, tutorial, about, options,
};

// Zig tip: `cmd: ?MenuCmd = null` is an optional enum with a default: a row without a command is a
// separator line. One struct serves both kinds of row.
/// A row of a menu: a command with its shortcut, or a separator (`cmd` null).
pub const MenuRow = struct { label: []const u8, key: []const u8 = "", cmd: ?MenuCmd = null, arg: usize = 0 };

/// A separator row.
const sep: MenuRow = .{ .label = "-" };

// Zig tip: `items: []const MenuRow` is a slice, so every menu can have its own number of rows. The
// literal `&.{ ... }` below makes a constant array and takes its address, which coerces to the
// slice; all of it is built by the compiler.
/// One menu of the bar: its name (upper case; the first letter is the Alt key) and its fixed rows.
/// The WINDOW menu has more rows after these: one for each open window (see `App.rowAt`).
pub const Menu = struct { label: []const u8, items: []const MenuRow };

/// The place of the WINDOW menu in `menus`.
pub const menu_window: usize = 5;
/// The place of the MACHINE menu: its first rows are the machines that are connected (see `App.rowAt`).
pub const menu_machine: usize = 4;

const machine_names = [_][]const u8{ "Local", "Machine 2", "Machine 3" };
const machine_keys = [_][]const u8{ "Alt+1", "Alt+2", "Alt+3" };

// Zig tip: A `const` array of struct literals is built at compile time and stored in the program.
// `[_]Menu{...}` lets the compiler count the menus; `menus.len` is then a compile-time number.
/// The menus of the bar, left to right. The last one (HELP) is drawn at the right side.
pub const menus = [_]Menu{
    .{ .label = "FILE", .items = &.{
        .{ .label = "Open project…", .key = "Ctrl+O", .cmd = .open_project },
        .{ .label = "Open Folder…", .key = "Ctrl+Shift+O", .cmd = .open_folder },
        .{ .label = "New file", .key = "Ctrl+N", .cmd = .new_file },
        .{ .label = "Save", .key = "Ctrl+S", .cmd = .save },
        .{ .label = "Save As…", .key = "Ctrl+Shift+S", .cmd = .save_as },
        .{ .label = "Close window", .key = "Ctrl+W", .cmd = .close_tab },
        sep,
        .{ .label = "Quit", .key = "Ctrl+Q", .cmd = .quit },
    } },
    .{ .label = "EDIT", .items = &.{
        .{ .label = "Undo", .key = "Ctrl+Z", .cmd = .undo },
        .{ .label = "Redo", .key = "Ctrl+Y", .cmd = .redo },
        sep,
        .{ .label = "Replace…", .key = "Ctrl+H", .cmd = .replace },
    } },
    .{ .label = "SEARCH", .items = &.{
        .{ .label = "Find Text…", .key = "Ctrl+F", .cmd = .find_text },
        .{ .label = "Find File…", .key = "Ctrl+P", .cmd = .find_file },
        .{ .label = "GoTo…", .key = "Ctrl+G", .cmd = .goto_line },
        .{ .label = "Query…", .key = "Ctrl+L", .cmd = .query },
    } },
    .{ .label = "RUN", .items = &.{
        .{ .label = "Run", .key = "F5", .cmd = .run },
        .{ .label = "Check syntax", .key = "F6", .cmd = .check_file },
        .{ .label = "Step into", .key = "F11", .cmd = .step_into },
        .{ .label = "Step out", .key = "Shift+F11", .cmd = .step_out },
        .{ .label = "Continue", .key = "F8", .cmd = .cont },
        .{ .label = "Stop", .key = "Shift+F5", .cmd = .stop },
        sep,
        .{ .label = "Breakpoint", .key = "F9", .cmd = .breakpoint },
    } },
    .{ .label = "MACHINE", .items = &.{
        sep,
        .{ .label = "Connect…", .key = "Ctrl+K", .cmd = .connect },
        .{ .label = "Upload…", .key = "Ctrl+U", .cmd = .upload },
    } },
    .{ .label = "WINDOW", .items = &.{
        .{ .label = "Select", .key = "Ctrl+Tab", .cmd = .select_window },
        .{ .label = "Close", .key = "Ctrl+W", .cmd = .close_tab },
        .{ .label = "Modify", .cmd = .modify },
        .{ .label = "Freeze", .key = "Esc", .cmd = .freeze },
        sep,
        .{ .label = "Tree Panel", .cmd = .toggle_tree },
        .{ .label = "Main Panel", .cmd = .toggle_main },
        .{ .label = "Tools Panel", .cmd = .toggle_tools },
    } },
    .{ .label = "HELP", .items = &.{
        .{ .label = "Shortcuts", .key = "Ctrl+/", .cmd = .shortcuts },
        .{ .label = "Manual", .cmd = .manual },
        .{ .label = "Tutorial", .cmd = .tutorial },
        .{ .label = "About", .cmd = .about },
        sep,
        .{ .label = "Options…", .key = "Ctrl+,", .cmd = .options },
    } },
};

// Zig tip: `@embedFile("help_shortcuts")` copies a file into the program at build time and gives
// it as a string: no file is read when evetx runs. The name is the one `build.zig` gave to the file.
const help_shortcuts = @embedFile("help_shortcuts");
const help_manual = @embedFile("help_manual");
const help_tutorial = @embedFile("help_tutorial");

// Zig tip: A struct without fields is a namespace for a constant; with fields it is a record. This
// one is the answer of `computeLayout`: where each panel is, as rectangles of the screen. A panel
// that is hidden has a rectangle of width 0.
/// The places of the panels on the screen (absolute cells).
pub const Layout = struct { tree: Rect = .{}, main: Rect = .{}, debug: Rect = .{}, tools: Rect = .{} };

/// What the mouse is dragging: a border between panels, or a scroll bar thumb.
pub const Drag = enum { none, tree_split, tools_split, vbar, hbar, select };

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
    /// The project folder (a path from the current folder); empty when no project is open. Owned.
    root: []u8,
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
    /// The menu of the bar that is open (while `overlay` is `.menu`) and its selected row.
    menu_top: usize = 0,
    menu_sel: usize = 0,
    /// In the Replace dialog: 0 is the Find field, 1 the Replace field.
    dlg_field: u8 = 0,
    /// The Alt key was pressed alone: the bar shows its letters underlined until the next key or click.
    alt_hint: bool = false,
    machine: u8 = 1,
    /// Which machines are connected. The local machine always is; the others join with step T5.
    connected: [3]bool = .{ true, false, false },
    running: bool = false,
    quit: bool = false,

    show_tree: bool = true,
    show_main: bool = true,
    show_tools: bool = true,
    /// The panel that fills the screen (the "+" button), if one does.
    maximized: ?Panel = null,
    /// Window > Modify: the borders between the panels follow the mouse and the arrow keys.
    modify: bool = false,
    drag: Drag = .none,
    /// Width of the Tree Panel and height of the Tools Panel in cells; 0 means "automatic".
    tree_w: u16 = 0,
    tools_h: u16 = 0,
    /// The size of the screen at the last drawing, and the places of the panels.
    cols: u16 = 80,
    rows: u16 = 24,
    layout: Layout = .{},
    /// True when the editor must scroll to show the cursor (after a key); false after the wheel or a scroll bar.
    follow: bool = true,
    /// The text copied with Ctrl+C or Ctrl+X (owned), and a copy waiting to be sent to the system clipboard.
    /// A command waiting in the prompt of the console: it starts by itself at `pending_at` (a time in
    /// milliseconds of the `awake` clock) unless the user presses a key. Owned text of the command.
    pending_at: ?i64 = null,
    pending_text: ?[]u8 = null,
    clip: ?[]u8 = null,
    sys_clip: ?[]u8 = null,
    /// True between the start and the end of a paste made by the terminal: the keys are collected.
    pasting: bool = false,
    paste_buf: std.ArrayList(u8) = .empty,
    /// Where a drag with the mouse started in the text.
    sel_from: text.Pos = .{ .row = 0, .col = 0 },
    vbar_rect: Rect = .{},
    hbar_rect: Rect = .{},
    /// The longest line that the horizontal scroll bar knows, in cells.
    hbar_content: usize = 0,

    files_in: TextInput,
    find_in: TextInput,
    replace_in: TextInput,
    console_in: TextInput,
    goto_in: TextInput,
    saveas_in: TextInput,
    project_in: TextInput,

    /// The projects the user knows (File > Open project), kept in a file of the user data folder.
    cache: cache_mod.Cache,
    proj_sel: usize = 0,
    proj_top: usize = 0,
    /// The folder browser (File > Open Folder): the folder shown (owned), its sub folders, the selected row.
    fb_path: ?[]u8 = null,
    fb_entries: std.ArrayList([]u8) = .empty,
    fb_sel: usize = 0,
    fb_top: usize = 0,

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
    pub fn create(gpa: std.mem.Allocator, io: Io, env: *const std.process.Environ.Map, root: []const u8) !*App {
        const self = try gpa.create(App);
        errdefer gpa.destroy(self);
        const name = if (root.len == 0) try gpa.dupe(u8, "") else try projectName(gpa, io, root);
        errdefer gpa.free(name);
        const own_root = try gpa.dupe(u8, root);
        errdefer gpa.free(own_root);
        var cache = try cache_mod.Cache.init(gpa, io, env);
        errdefer cache.deinit();
        cache.load();
        self.* = .{
            .gpa = gpa,
            .io = io,
            .root = own_root,
            .project_name = name,
            .tree = project.Tree.init(gpa),
            .files_in = TextInput.init(gpa),
            .find_in = TextInput.init(gpa),
            .replace_in = TextInput.init(gpa),
            .console_in = TextInput.init(gpa),
            .goto_in = TextInput.init(gpa),
            .saveas_in = TextInput.init(gpa),
            .project_in = TextInput.init(gpa),
            .cache = cache,
            .frame = .init(gpa),
        };
        if (root.len > 0) try self.tree.scan(io, root, name);
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
        for ([_]*TextInput{ &self.files_in, &self.find_in, &self.replace_in, &self.console_in, &self.goto_in, &self.saveas_in, &self.project_in }) |ti| ti.deinit();
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
        gpa.free(self.root);
        self.cache.deinit();
        if (self.clip) |c| gpa.free(c);
        if (self.pending_text) |c| gpa.free(c);
        if (self.sys_clip) |c| gpa.free(c);
        self.paste_buf.deinit(gpa);
        self.fbClear();
        self.fb_entries.deinit(gpa);
        if (self.fb_path) |fp| gpa.free(fp);
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
        if (self.root.len == 0 or std.mem.eql(u8, self.root, ".")) return self.gpa.dupe(u8, rel);
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
        if (t.virtual) {
            self.setMessage("{s} is a read-only window", .{t.path});
            return;
        }
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
        if (t.virtual) {
            self.setMessage("{s} is a read-only window", .{t.path});
            return;
        }
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
        if (t.virtual) return;
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
        const cwd: std.process.Child.Cwd = if (self.root.len == 0 or std.mem.eql(u8, self.root, ".")) .inherit else .{ .path = self.root };
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
        try self.issueCommand(line);
    }

    /// F6: the syntax check of the current `.eve` file (`eve --check <file>`), through the prompt like Run.
    pub fn checkActive(self: *App) !void {
        const t = self.activeTab() orelse {
            self.setMessage("nothing to check: open an .eve file", .{});
            return;
        };
        if (t.buf == null or !t.eve) {
            self.setMessage("Check needs an .eve file", .{});
            return;
        }
        if (t.path.len == 0 or t.buf.?.dirty) try self.save();
        if (t.path.len == 0) return;
        const line = try std.fmt.allocPrint(self.gpa, "--check {s}", .{t.path});
        defer self.gpa.free(line);
        try self.issueCommand(line);
    }

    // Zig tip: `Io.Timestamp.now(io, .awake).toMilliseconds()` reads a clock that only goes forward
    // (it does not jump when the user changes the time of the computer), the right one to measure a
    // delay. The delay is a constant at file level so that it is written once.
    const command_delay_ms: i64 = 3000;

    fn nowMs(self: *const App) i64 {
        return Io.Timestamp.now(self.io, .awake).toMilliseconds();
    }

    /// A run command (Run, Check) does not start at once: it is typed in the prompt of the console, where
    /// the user can read it, and it starts after three seconds. Enter starts it now, Esc cancels it, and
    /// typing in the prompt keeps the text but cancels the countdown. The line goes into the history of
    /// the console at once, so Ctrl+Up finds it again even if it was cancelled.
    pub fn issueCommand(self: *App, line: []const u8) !void {
        if (!self.show_tools) self.togglePanel(.tools);
        if (self.maximized == .main) self.maximized = null;
        self.bottom = .console;
        self.focus = .console;
        self.console_in.clearRetainingCapacity();
        try self.console_in.insertSliceAtCursor(line);
        self.history_pos = null;
        try self.remember(line);
        if (self.pending_text) |old| self.gpa.free(old);
        self.pending_text = try self.gpa.dupe(u8, line);
        self.pending_at = self.nowMs() + command_delay_ms;
    }

    /// Add a command to the history of the console, unless it is the same as the last one.
    fn remember(self: *App, cmd: []const u8) !void {
        if (self.history.items.len > 0 and std.mem.eql(u8, self.history.items[self.history.items.len - 1], cmd)) return;
        try self.history.append(self.gpa, try self.gpa.dupe(u8, cmd));
    }

    /// Stop the countdown of a waiting command (the text stays in the prompt).
    pub fn cancelPending(self: *App) void {
        self.pending_at = null;
    }

    /// Milliseconds before the waiting command starts, or null when none waits.
    pub fn pendingLeft(self: *const App) ?i64 {
        const at = self.pending_at orelse return null;
        return @max(0, at - self.nowMs());
    }

    /// Called by the main loop all the time while a command waits: starts it when its time is over.
    pub fn tick(self: *App) !void {
        const left = self.pendingLeft() orelse return;
        if (left > 0) return;
        self.pending_at = null;
        try self.consoleEnter();
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
        try self.remember(cmd);
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
        if (q.len == 0 or self.tree.entries.items.len == 0) return;
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
        if (self.activeTab().?.virtual) return self.setMessage("a read-only window cannot be changed", .{});
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
        if (self.activeTab().?.virtual) return self.setMessage("a read-only window cannot be changed", .{});
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
        self.dlg_field = 0;
    }

    // Zig tip: `self: *const App` promises that the function only reads the app, so the drawing
    // code can call it too. A row that is not in the fixed list of the menu is made on the spot: the
    // WINDOW menu ends with a separator and one row for each open window (at most nine, the ones
    // that Ctrl+1 to Ctrl+9 reach).
    /// How many machines are connected.
    pub fn connectedCount(self: *const App) usize {
        var n: usize = 0;
        for (self.connected) |on| n += @intFromBool(on);
        return n;
    }

    /// How many rows menu `m` has now.
    pub fn rowCount(self: *const App, m: usize) usize {
        const base = menus[m].items.len;
        if (m == menu_window and self.tabs.items.len > 0) return base + 1 + @min(self.tabs.items.len, 9);
        if (m == menu_machine) return base + self.connectedCount();
        return base;
    }

    /// Row `k` of menu `m`. The title of a window is a slice of the tab, valid while the tab is open.
    pub fn rowAt(self: *const App, m: usize, k: usize) MenuRow {
        const items = menus[m].items;
        if (m == menu_machine) {
            // the machines that are connected come first, then the fixed rows
            var seen: usize = 0;
            for (self.connected, 0..) |on, n| {
                if (!on) continue;
                if (seen == k) return .{ .label = machine_names[n], .key = machine_keys[n], .cmd = .machine_pick, .arg = n + 1 };
                seen += 1;
            }
            return items[k - seen];
        }
        if (k < items.len) return items[k];
        if (k == items.len) return sep;
        const t = k - items.len - 1;
        return .{ .label = self.tabs.items[t].title(), .cmd = .window_pick, .arg = t };
    }

    /// The first row of menu `m` that is a command (not a separator).
    fn firstItem(self: *const App, m: usize) usize {
        var k: usize = 0;
        while (k < self.rowCount(m)) : (k += 1) {
            if (self.rowAt(m, k).cmd != null) return k;
        }
        return 0;
    }

    // Zig tip: `menus[i]` is checked against the array length in a safe build, so a wrong `i` stops
    // the program with a message instead of reading other memory.
    /// Open menu `i` of the bar (a click, F10 or Alt and its letter) with its first command selected.
    pub fn openMenu(self: *App, i: usize) void {
        self.overlay = .menu;
        self.menu_top = i;
        self.menu_sel = self.firstItem(i);
    }

    // Zig tip: `menus[i].label[0]` is the first byte of a string literal, a `u8`. `std.ascii.toLower`
    // turns it into the lower case letter that the comparison needs.
    /// The menu whose letter is `c` (upper or lower case), if there is one.
    fn menuByLetter(c: u21) ?usize {
        if (c > 127) return null;
        const lower = std.ascii.toLower(@intCast(c));
        for (menus, 0..) |m, i| {
            if (std.ascii.toLower(m.label[0]) == lower) return i;
        }
        return null;
    }

    // Zig tip: A helper for the features that are planned but not built, so the message is the same
    // everywhere and easy to find with a search for `notYet`.
    fn notYet(self: *App, what: []const u8, step: []const u8) void {
        self.setMessage("{s}: not yet ({s}, README.md §8)", .{ what, step });
    }

    // Zig tip: A `switch` over an enum with one branch for each value. The compiler checks that every
    // command has a branch. A branch may be a block, a call, or `try` on a call.
    pub fn runMenu(self: *App, cmd: MenuCmd, arg: usize) !void {
        self.overlay = .none;
        switch (cmd) {
            .open_project => self.openProjectDialog(),
            .open_folder => self.openFolderDialog(),
            .new_file => try self.newFile(),
            .save => try self.save(),
            .save_as => self.openOverlay(.save_as),
            .close_tab => self.closeTab(self.active),
            .quit => self.quit = true,
            .undo, .redo => self.notYet("Undo and redo", "T3"),
            .find_text => self.openOverlay(.find_text),
            .find_file => self.openOverlay(.find_file),
            .replace => self.openOverlay(.replace),
            .goto_line => self.openOverlay(.goto),
            .query => self.notYet("Query", "T7"),
            .run => try self.runActive(),
            .check_file => try self.checkActive(),
            .step_into, .step_out, .cont, .stop => self.notYet("The debugger", "T6"),
            .breakpoint => try self.toggleBreakpoint(),
            .machine_pick => self.pickMachine(@intCast(arg)),
            .connect, .upload => self.notYet("Remote machines", "T5"),
            .select_window => self.nextTab(1),
            .modify => {
                self.modify = true;
                self.setMessage("Modify: drag the borders or use the arrow keys; Esc freezes the sizes", .{});
            },
            .freeze => self.modify = false,
            .toggle_tree => self.togglePanel(.tree),
            .toggle_main => self.togglePanel(.main),
            .toggle_tools => self.togglePanel(.tools),
            .window_pick => self.pickWindow(arg),
            .shortcuts => try self.openVirtual("Shortcuts", help_shortcuts),
            .manual => try self.openVirtual("Manual", help_manual),
            .tutorial => try self.openVirtual("Tutorial", help_tutorial),
            .about => self.openOverlay(.about),
            .options => self.openOverlay(.settings),
        }
    }

    // Zig tip: `while (true) {... break;}` loops until a `break`. `@mod` wraps the index; the loop
    // skips the rows that have no command (separators).
    fn menuMove(self: *App, delta: isize) void {
        var i: isize = @intCast(self.menu_sel);
        const n: isize = @intCast(self.rowCount(self.menu_top));
        while (true) {
            i = @mod(i + delta, n);
            if (self.rowAt(self.menu_top, @intCast(i)).cmd != null) break;
        }
        self.menu_sel = @intCast(i);
    }

    // Zig tip: `@intCast(self.menu_top)` widens to `isize` so that `-1` can be added without the
    // unsigned wrap-around; `@mod` brings the result back in `0..n`.
    fn menuSide(self: *App, delta: isize) void {
        const n: isize = menus.len;
        const to: usize = @intCast(@mod(@as(isize, @intCast(self.menu_top)) + delta, n));
        self.openMenu(to);
    }

    // ------------------------------------------------------------ panels and windows

    // Zig tip: `std.math.clamp(v, lo, hi)` needs `lo <= hi`; the window is at least 70 x 18 cells
    // (view.zig), so the ranges below are never empty. `@as(u16, ...)` makes the type of the
    // literal explicit.
    /// The width of the Tree Panel: the chosen one (Window > Modify) or a quarter of the screen.
    pub fn treeWidth(self: *const App) u16 {
        const w: u16 = if (self.tree_w == 0) std.math.clamp(self.cols / 4, 26, 40) else self.tree_w;
        return std.math.clamp(w, 14, self.cols -| 24);
    }

    /// The height of the Tools Panel: the chosen one or a third of the work area.
    pub fn toolsHeight(self: *const App) u16 {
        const mh = self.rows -| 4;
        const h: u16 = if (self.tools_h == 0) @max(7, mh / 3) else self.tools_h;
        return std.math.clamp(h, 5, mh -| 6);
    }

    // Zig tip: A `switch` that returns a value is an expression; each branch is one `bool`.
    /// Is panel `p` on the screen? A maximized panel hides the others.
    pub fn isShown(self: *const App, p: Panel) bool {
        return switch (p) {
            .tree => self.show_tree and self.maximized != .main,
            .main => self.show_main and self.maximized != .tools,
            .tools => self.show_tools and self.maximized != .main,
        };
    }

    // Zig tip: The drawing asks for the places of the panels once per frame, and the mouse code
    // reads the saved answer (`self.layout`). Rows: 0 is the menu bar, the last three are the
    // status bar. The row with the Run buttons belongs to the Tools Panel: it is above it, and goes with it.
    /// Work out where each panel is for a screen of `W` x `H` cells, and keep the answer.
    pub fn computeLayout(self: *App, W: u16, H: u16) Layout {
        self.cols = W;
        self.rows = H;
        const mh = H - 4;
        var l: Layout = .{};
        var rx: u16 = 0;
        if (self.isShown(.tree)) {
            const tw = self.treeWidth();
            l.tree = .{ .x = 0, .y = 1, .w = tw, .h = mh };
            rx = tw;
        }
        const rw = W - rx;
        if (self.isShown(.main) and self.isShown(.tools)) {
            const bb = self.toolsHeight();
            const eh = mh - 1 - bb;
            l.main = .{ .x = rx, .y = 1, .w = rw, .h = eh };
            l.debug = .{ .x = rx, .y = 1 + eh, .w = rw, .h = 1 };
            l.tools = .{ .x = rx, .y = 2 + eh, .w = rw, .h = bb };
        } else if (self.isShown(.main)) {
            l.main = .{ .x = rx, .y = 1, .w = rw, .h = mh };
        } else if (self.isShown(.tools)) {
            l.debug = .{ .x = rx, .y = 1, .w = rw, .h = 1 };
            l.tools = .{ .x = rx, .y = 2, .w = rw, .h = mh - 1 };
        }
        self.layout = l;
        return l;
    }

    /// The panel that has the keyboard.
    pub fn activePanel(self: *const App) Panel {
        return switch (self.focus) {
            .tree => .tree,
            .editor => .main,
            .console, .breaks => .tools,
        };
    }

    /// Give the keyboard to panel `p`.
    pub fn focusPanel(self: *App, p: Panel) void {
        self.focus = switch (p) {
            .tree => .tree,
            .main => .editor,
            .tools => if (self.bottom == .breaks) .breaks else .console,
        };
    }

    // Zig tip: `inline else` is not needed here: the `switch` lists the three panels. Taking the
    // address of a field of a struct chosen by a switch (`&self.show_tree`) gives a pointer to the
    // one `bool`, so the three panels share the same code after the `switch`.
    /// Hide panel `p`, or show it again (Window > Tree Panel, Main Panel, Tools Panel; the x buttons).
    pub fn togglePanel(self: *App, p: Panel) void {
        const flag = switch (p) {
            .tree => &self.show_tree,
            .main => &self.show_main,
            .tools => &self.show_tools,
        };
        flag.* = !flag.*;
        if (flag.*) {
            self.maximized = null;
            self.focusPanel(p);
        } else {
            if (self.maximized == p) self.maximized = null;
            if (self.activePanel() == p) self.rotatePanel(1);
        }
    }

    /// The + button: a panel fills the screen, or goes back to its place.
    pub fn toggleMaximize(self: *App, p: Panel) void {
        self.maximized = if (self.maximized == p) null else p;
        self.focusPanel(p);
    }

    // Zig tip: `for (0..3) |k|` counts from 0 to 2 without a variable. `@enumFromInt` turns a number
    // back into the enum value, and `@intFromEnum` turns a value into its number: the panels are
    // numbered 0, 1, 2 in the order of the declaration.
    /// Shift+Tab and Alt+Right: the keyboard goes to the next panel that is on the screen (Tree, Main, Tools); Alt+Left goes back.
    pub fn rotatePanel(self: *App, delta: isize) void {
        const here: isize = @intFromEnum(self.activePanel());
        for (1..4) |k| {
            const p: Panel = @enumFromInt(@mod(here + delta * @as(isize, @intCast(k)), 3));
            if (self.isShown(p)) {
                self.focusPanel(p);
                return;
            }
        }
    }

    // Zig tip: `(a + n + delta) % n` wraps around the end of a list in both directions when `delta`
    // is 1 or `n - 1`; here the signed `@mod` is simpler. The tabs of the Tools Panel are the enum
    // `BottomTab`, so the same arithmetic walks them with `@intFromEnum`.
    /// Alt+Tab: the next window of the Main Panel, or the next tab of the Tools Panel when that panel has the keyboard.
    pub fn nextTab(self: *App, delta: isize) void {
        if (self.activePanel() == .tools) {
            const n: isize = 5;
            const cur: isize = @intFromEnum(self.bottom);
            self.bottom = @enumFromInt(@mod(cur + delta, n));
            self.focusPanel(.tools);
            return;
        }
        const n: isize = @intCast(self.tabs.items.len);
        if (n == 0) return;
        const to: usize = @intCast(@mod(@as(isize, @intCast(self.active)) + delta, n));
        self.pickWindow(to);
    }

    /// Make window `t` (a tab of the Main Panel) the current one.
    pub fn pickWindow(self: *App, t: usize) void {
        if (t >= self.tabs.items.len) return;
        self.active = t;
        if (!self.show_main) self.togglePanel(.main);
        self.focus = if (self.tabs.items[t].buf != null) .editor else self.focus;
    }

    // Zig tip: `errdefer` frees the copy only if a later `try` fails. After `append` succeeds the tab
    // owns `path`, and `closeTab` frees it.
    /// Open a window that is not a file: the text is read only, the title is its name.
    pub fn openVirtual(self: *App, title: []const u8, content: []const u8) !void {
        for (self.tabs.items, 0..) |t, i| {
            if (t.virtual and std.mem.eql(u8, t.path, title)) {
                self.pickWindow(i);
                return;
            }
        }
        var b = try text.Buffer.init(self.gpa);
        errdefer b.deinit();
        try b.load(content);
        b.dirty = false;
        const path = try self.gpa.dupe(u8, title);
        errdefer self.gpa.free(path);
        try self.tabs.append(self.gpa, .{ .path = path, .buf = b, .virtual = true });
        if (!self.show_main) self.togglePanel(.main);
        self.maximized = if (self.maximized == .tools) null else self.maximized;
        self.active = self.tabs.items.len - 1;
        self.focus = .editor;
    }

    // Zig tip: The folder is checked first (`projectName` opens it), and only then the old project is
    // let go, so a wrong path leaves the screen as it was. `self.tree.deinit()` followed by
    // `self.tree = Tree.init(...)` reuses the same place of the struct: the tree is never copied
    // after it gave out memory.
    /// Open a project folder: the tree shows its files and the windows of the old project close.
    pub fn openProject(self: *App, path: []const u8) !void {
        if (path.len == 0) return;
        for (self.tabs.items) |t| {
            if (t.buf != null and t.buf.?.dirty) {
                self.setMessage("save or close the changed files first", .{});
                return;
            }
        }
        const name = projectName(self.gpa, self.io, path) catch |err| {
            self.setMessage("cannot open the folder '{s}': {s}", .{ path, @errorName(err) });
            return;
        };
        errdefer self.gpa.free(name);
        const root = try self.gpa.dupe(u8, path);
        errdefer self.gpa.free(root);

        // from here on nothing can fail with `try`: the new name and root belong to the app
        while (self.tabs.items.len > 0) self.closeTab(0);
        for (self.breakpoints.items) |b| self.gpa.free(b.path);
        self.breakpoints.clearRetainingCapacity();
        if (self.saved_open) |snap| self.gpa.free(snap);
        self.saved_open = null;
        self.tree.deinit();
        self.tree = project.Tree.init(self.gpa);
        self.gpa.free(self.project_name);
        self.gpa.free(self.root);
        self.project_name = name;
        self.root = root;
        self.selected = 0;
        self.tree_top = 0;
        self.tree.scan(self.io, root, name) catch |err| {
            self.setMessage("cannot read the folder '{s}': {s}", .{ path, @errorName(err) });
            return;
        };
        self.show_tree = true;
        self.maximized = null;
        self.focus = .tree;
        self.setMessage("project: {s}", .{name});
    }

    // Zig tip: A `switch` on the enum `Drag` decides what the moving mouse changes. The raw column
    // of the pointer is stored; `treeWidth` and `toolsHeight` clamp it, so a wild drag cannot break
    // the screen.
    /// A press on a border between panels while Window > Modify is on: start dragging it.
    fn grabSplit(self: *App, m: vaxis.Mouse) bool {
        const l = self.layout;
        if (l.tree.w > 0 and (m.col == l.tree.w - 1 or m.col == l.tree.w) and m.row >= 1) {
            self.drag = .tree_split;
            return true;
        }
        if (l.tools.w > 0 and l.main.w > 0 and m.col >= l.tools.x and (m.row == l.tools.y or m.row == l.tools.y - 1)) {
            self.drag = .tools_split;
            return true;
        }
        return false;
    }

    /// A press on a scroll bar of the editor: start dragging its thumb.
    fn grabBar(self: *App, m: vaxis.Mouse) bool {
        if (self.vbar_rect.contains(m.col, m.row)) {
            self.drag = .vbar;
        } else if (self.hbar_rect.contains(m.col, m.row)) {
            self.drag = .hbar;
        } else return false;
        self.follow = false;
        self.scrollTo(m);
        return true;
    }

    // Zig tip: The position of the pointer on the bar, from 0 to `len - 1`, is turned into a line (or
    // column) by a proportion: `rel * (total - shown) / (len - 1)`. `@max(..., 0)` first, because the
    // pointer may be outside the bar during a drag and `m.row` is signed.
    /// Scroll the editor to the place of the pointer on the bar that is being dragged.
    fn scrollTo(self: *App, m: vaxis.Mouse) void {
        const b = self.activeBuffer() orelse return;
        if (self.drag == .vbar) {
            const r = self.vbar_rect;
            const total = b.lineCount();
            if (r.h < 2 or total <= r.h) return;
            const rel: usize = @intCast(@min(@max(@as(i32, m.row) - r.y, 0), r.h - 1));
            b.top = rel * (total - r.h) / (r.h - 1);
        } else if (self.drag == .hbar) {
            const r = self.hbar_rect;
            if (r.w < 2 or self.hbar_content <= r.w) return;
            const rel: usize = @intCast(@min(@max(@as(i32, m.col) - r.x, 0), r.w - 1));
            b.left = rel * (self.hbar_content - r.w) / (r.w - 1);
        }
    }

    // Zig tip: The place under the pointer is found from the rectangle of the text: the row is the
    // first row shown plus the distance from the top of the rectangle, the column goes through
    // `byteAtDisplay` so that it lands at the start of a character. A pointer above or below the
    // text scrolls it one line, so a drag can select more than the screen shows.
    /// The place in the text under the mouse pointer.
    fn editorPos(self: *App, b: *text.Buffer, m: vaxis.Mouse) text.Pos {
        const r = self.editor_rect;
        const rel: i32 = @as(i32, m.row) - r.y;
        const last = b.lineCount() - 1;
        var row: usize = undefined;
        if (rel < 0) {
            b.top -|= 1;
            row = b.top;
        } else if (rel >= r.h) {
            if (b.top + r.h <= last) b.top += 1;
            row = @min(b.top + r.h -| 1, last);
        } else row = @min(b.top + @as(usize, @intCast(rel)), last);
        const dc: usize = b.left + @as(usize, @intCast(@max(@as(i32, m.col) - r.x, 0)));
        return .{ .row = row, .col = text.Buffer.byteAtDisplay(b.lineAt(row), dc) };
    }

    /// The pointer moves with the button down in the text: the cursor follows, the anchor is where the click was.
    fn selectTo(self: *App, m: vaxis.Mouse) void {
        const b = self.activeBuffer() orelse return;
        self.follow = false;
        const pos = self.editorPos(b, m);
        if (b.anchor == null) b.anchor = self.sel_from;
        b.row = pos.row;
        b.col = pos.col;
    }

    /// The mouse moves with a button down.
    fn dragTo(self: *App, m: vaxis.Mouse) void {
        switch (self.drag) {
            .none => {},
            .tree_split => self.tree_w = @intCast(@max(@as(i32, m.col) + 1, 0)),
            .tools_split => self.tools_h = @intCast(@max(@as(i32, self.rows) - 3 - m.row, 0)),
            .vbar, .hbar => self.scrollTo(m),
            .select => self.selectTo(m),
        }
    }

    // Zig tip: The function returns `!bool`: an error union around a plain `bool`. The caller writes
    // `try self.modifyKey(key)` to get the `bool` or pass the error up. Here nothing can fail, but
    // the shape is the same as the other key functions.
    /// While Window > Modify is on: the arrows change the sizes, Esc and Enter freeze them. True when the key was used.
    fn modifyKey(self: *App, key: Key) !bool {
        if (key.matches(Key.escape, .{}) or key.matches(Key.enter, .{})) {
            self.modify = false;
            self.setMessage("sizes frozen", .{});
        } else if (key.matches(Key.left, .{})) {
            self.tree_w = self.treeWidth() -| 2;
        } else if (key.matches(Key.right, .{})) {
            self.tree_w = self.treeWidth() + 2;
        } else if (key.matches(Key.up, .{})) {
            self.tools_h = self.toolsHeight() + 1;
        } else if (key.matches(Key.down, .{})) {
            self.tools_h = self.toolsHeight() -| 1;
        } else return false;
        return true;
    }

    // ------------------------------------------------------------ dialogs: projects and folders

    // Zig tip: One function is the single way to close a dialog (Esc, the x button, a click outside),
    // so the work that some dialogs need when they close is written once.
    /// Close the dialog that is open. The Find File dialog puts the tree back as it was.
    pub fn closeOverlay(self: *App) void {
        if (self.overlay == .find_file) self.filesCancel();
        self.overlay = .none;
    }

    /// File > Open project: the list of the known projects.
    pub fn openProjectDialog(self: *App) void {
        self.proj_sel = 0;
        self.proj_top = 0;
        self.openOverlay(.open_project);
    }

    /// File > Open Folder: the folder browser, which starts in the project folder, or in the current folder.
    pub fn openFolderDialog(self: *App) void {
        if (self.fb_path == null) self.fbLoad(if (self.root.len > 0) self.root else ".");
        self.openOverlay(.open_folder);
        self.dlg_field = 1;
    }

    // Zig tip: `orelse return` leaves the function when the optional is null. The path is copied
    // first because `openProject` and the cache change the lists that the original lives in.
    /// Open project `i` of the list and move it to the top of the list.
    fn openCached(self: *App, i: usize) !void {
        if (i >= self.cache.projects.items.len) return;
        const path = try self.gpa.dupe(u8, self.cache.projects.items[i]);
        defer self.gpa.free(path);
        self.overlay = .none;
        self.cache.add(path) catch {};
        try self.openProject(path);
    }

    /// Take the selected project out of the list (its folder and files stay).
    fn forgetProject(self: *App) !void {
        const n = self.cache.projects.items.len;
        if (self.proj_sel >= n) return;
        const name = try self.gpa.dupe(u8, baseName(self.cache.projects.items[self.proj_sel]));
        defer self.gpa.free(name);
        try self.cache.forget(self.proj_sel);
        self.proj_sel = @min(self.proj_sel, self.cache.projects.items.len -| 1);
        self.setMessage("forgotten: {s} (the folder stays on the disk)", .{name});
    }

    /// The button Open as project of the folder browser: the folder joins the list and opens.
    fn openHere(self: *App) !void {
        const shown = self.fb_path orelse return;
        const path = try self.gpa.dupe(u8, shown);
        defer self.gpa.free(path);
        self.overlay = .none;
        self.cache.add(path) catch |err| self.setMessage("project cache: {s}", .{@errorName(err)});
        try self.openProject(path);
    }

    /// The last part of a path.
    pub fn baseName(path: []const u8) []const u8 {
        const cut = std.mem.lastIndexOfAny(u8, path, "/\\");
        return if (cut) |i| path[i + 1 ..] else path;
    }

    // Zig tip: `std.mem.sort` with an anonymous struct that holds the comparison, as in project.zig.
    // `catch null` inside the `while` condition turns an error of `next` into the end of the loop.
    /// Show folder `path` in the browser: read its sub folders, and put its real path in the field.
    /// A folder that cannot be read leaves the browser as it was.
    pub fn fbLoad(self: *App, path: []const u8) void {
        var dir = Io.Dir.cwd().openDir(self.io, path, .{ .iterate = true }) catch |err| {
            self.setMessage("cannot open '{s}': {s}", .{ path, @errorName(err) });
            return;
        };
        defer dir.close(self.io);
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const n = dir.realPath(self.io, &buf) catch |err| {
            self.setMessage("cannot read '{s}': {s}", .{ path, @errorName(err) });
            return;
        };
        const abs = self.gpa.dupe(u8, buf[0..n]) catch return;
        self.fbClear();
        var it = dir.iterate();
        while (it.next(self.io) catch null) |e| {
            if (e.kind != .directory or self.fb_entries.items.len >= 2000) continue;
            const name = self.gpa.dupe(u8, e.name) catch break;
            self.fb_entries.append(self.gpa, name) catch {
                self.gpa.free(name);
                break;
            };
        }
        std.mem.sort([]u8, self.fb_entries.items, {}, struct {
            fn less(_: void, a: []u8, b: []u8) bool {
                return std.ascii.lessThanIgnoreCase(a, b);
            }
        }.less);
        if (self.fb_path) |old| self.gpa.free(old);
        self.fb_path = abs;
        self.fb_sel = 0;
        self.fb_top = 0;
        self.project_in.clearRetainingCapacity();
        self.project_in.insertSliceAtCursor(abs) catch {};
    }

    fn fbClear(self: *App) void {
        for (self.fb_entries.items) |e| self.gpa.free(e);
        self.fb_entries.clearRetainingCapacity();
    }

    /// Is there a folder above the one shown? (Not at the root of a drive.)
    pub fn fbHasParent(self: *const App) bool {
        const p = self.fb_path orelse return false;
        return std.fs.path.dirname(p) != null;
    }

    /// The rows of the browser: `..` first when there is a parent, then the sub folders.
    pub fn fbRowCount(self: *const App) usize {
        return self.fb_entries.items.len + @intFromBool(self.fbHasParent());
    }

    /// The name shown in row `i`.
    pub fn fbRowName(self: *const App, i: usize) []const u8 {
        if (self.fbHasParent()) {
            if (i == 0) return "..";
            return self.fb_entries.items[i - 1];
        }
        return self.fb_entries.items[i];
    }

    // Zig tip: `std.fs.path.dirname` returns a slice of the path itself, and `fbLoad` frees the old
    // path, so the parent is copied before the call and freed after it.
    fn fbUp(self: *App) void {
        const p = self.fb_path orelse return;
        const parent = std.fs.path.dirname(p) orelse return;
        const copy = self.gpa.dupe(u8, parent) catch return;
        defer self.gpa.free(copy);
        self.fbLoad(copy);
    }

    /// Go into the folder of row `i` (or up, for `..`).
    fn fbEnterRow(self: *App, i: usize) void {
        if (i >= self.fbRowCount()) return;
        const name = self.fbRowName(i);
        if (std.mem.eql(u8, name, "..")) return self.fbUp();
        const p = self.fb_path orelse return;
        const joined = std.fs.path.join(self.gpa, &.{ p, name }) catch return;
        defer self.gpa.free(joined);
        self.fbLoad(joined);
    }

    // Zig tip: Keys are tried in order and each `return` ends the function, so the order is the
    // priority. `Key.f2` opens the shown folder as a project without going into a sub folder.
    /// The keys of the project list.
    fn projectKey(self: *App, key: Key) !void {
        const n = self.cache.projects.items.len;
        if (key.matches(Key.enter, .{})) return self.openCached(self.proj_sel);
        if (key.matches(Key.delete, .{}) or key.matches('f', .{})) return self.forgetProject();
        if (key.matches('i', .{}) or key.matches(Key.insert, .{})) return self.openFolderDialog();
        if (n == 0) return;
        if (key.matches(Key.up, .{})) self.proj_sel = self.proj_sel -| 1 else if (key.matches(Key.down, .{})) self.proj_sel = @min(self.proj_sel + 1, n - 1) else if (key.matches(Key.page_up, .{})) self.proj_sel = self.proj_sel -| 8 else if (key.matches(Key.page_down, .{})) self.proj_sel = @min(self.proj_sel + 8, n - 1) else if (key.matches(Key.home, .{})) self.proj_sel = 0 else if (key.matches(Key.end, .{})) self.proj_sel = n - 1;
    }

    /// The keys of the folder browser: Tab switches between the path field and the list.
    fn folderKey(self: *App, key: Key) !void {
        if (key.matches(Key.tab, .{})) {
            self.dlg_field = 1 - self.dlg_field;
            return;
        }
        if (key.matches(Key.f2, .{})) return self.openHere();
        if (self.dlg_field == 0) {
            if (key.matches(Key.enter, .{})) {
                const typed = try self.project_in.toOwnedContents(self.gpa);
                defer self.gpa.free(typed);
                self.fbLoad(std.mem.trim(u8, typed, " \""));
                self.dlg_field = 1;
            } else if (key.matches(Key.down, .{})) {
                self.dlg_field = 1;
            } else try self.project_in.update(.{ .key_press = key });
            return;
        }
        const n = self.fbRowCount();
        if (key.matches(Key.enter, .{}) or key.matches(Key.right, .{})) return self.fbEnterRow(self.fb_sel);
        if (key.matches(Key.left, .{}) or key.matches(Key.backspace, .{})) return self.fbUp();
        if (n == 0) return;
        if (key.matches(Key.up, .{})) self.fb_sel = self.fb_sel -| 1 else if (key.matches(Key.down, .{})) self.fb_sel = @min(self.fb_sel + 1, n - 1) else if (key.matches(Key.page_up, .{})) self.fb_sel = self.fb_sel -| 8 else if (key.matches(Key.page_down, .{})) self.fb_sel = @min(self.fb_sel + 8, n - 1) else if (key.matches(Key.home, .{})) self.fb_sel = 0 else if (key.matches(Key.end, .{})) self.fb_sel = n - 1;
    }

    // ------------------------------------------------------------ keys

    // Zig tip: `key.matches(codepoint, mods)` compares a key with a letter and the modifier keys,
    // written as a struct with defaults: `.{ .ctrl = true }`. The order of the `if`s matters: the
    // first that matches wins.
    pub fn onKey(self: *App, key: Key) !void {
        // Zig tip: the Windows console reports the Alt key on its own as a key press whose code is
        // `Key.left_alt` or `Key.right_alt`; there is no event when it is released, so the hint
        // stays until the next key or click.
        if (key.codepoint == Key.left_alt or key.codepoint == Key.right_alt) {
            self.alt_hint = true;
            return;
        }
        self.alt_hint = false;
        self.follow = true;
        if (self.pasting) {
            // a paste made by the terminal arrives as keys: collect them until the paste ends
            if (key.text) |t| try self.paste_buf.appendSlice(self.gpa, t) else if (key.matches(Key.enter, .{})) try self.paste_buf.append(self.gpa, '\n') else if (key.matches(Key.tab, .{})) try self.paste_buf.append(self.gpa, '\t');
            return;
        }
        if (self.message) |m| {
            self.gpa.free(m);
            self.message = null;
        }
        if (self.overlay != .none) return self.overlayKey(key);

        if (self.modify and try self.modifyKey(key)) return;
        if (key.matches(Key.enter, .{ .ctrl = true }) or key.matches(Key.f10, .{})) return self.openMenu(0);
        if (key.mods.alt and !key.mods.ctrl) {
            if (key.codepoint == Key.left) return self.rotatePanel(-1);
            if (key.codepoint == Key.right) return self.rotatePanel(1);
            if (key.codepoint == Key.tab) return self.nextTab(if (key.mods.shift) -1 else 1);
            if (key.codepoint >= '1' and key.codepoint <= '3') return self.pickMachine(@intCast(key.codepoint - '0'));
            if (menuByLetter(key.codepoint)) |m| return self.openMenu(m);
        }
        if (key.matches(Key.tab, .{ .shift = true })) return self.rotatePanel(1);
        if (key.matches(Key.page_up, .{ .ctrl = true })) return self.nextTab(-1);
        if (key.matches(Key.page_down, .{ .ctrl = true })) return self.nextTab(1);
        if (key.matches(Key.tab, .{ .ctrl = true })) return self.nextTab(1);
        if (ctrlDigit(key)) |d| {
            if (d >= self.tabs.items.len) {
                self.setMessage("no window {d}", .{d + 1});
                return;
            }
            return self.pickWindow(d);
        }
        if (key.matches('/', .{ .ctrl = true }) or key.matches(Key.f12, .{})) return self.runMenu(.shortcuts, 0);
        if (key.matches(',', .{ .ctrl = true })) return self.openOverlay(.settings);
        if (key.matches('o', .{ .ctrl = true, .shift = true })) return self.openFolderDialog();
        if (key.matches('o', .{ .ctrl = true })) return self.openProjectDialog();
        if (key.matches('q', .{ .ctrl = true })) {
            self.quit = true;
            return;
        }
        if (key.matches('s', .{ .ctrl = true, .shift = true })) return self.openOverlay(.save_as);
        if (key.matches('s', .{ .ctrl = true })) return self.save();
        if (key.matches('w', .{ .ctrl = true })) return self.closeTab(self.active);
        if (key.matches('n', .{ .ctrl = true })) return self.newFile();
        if (self.searchShortcut(key)) return;
        if (key.matches(Key.f5, .{})) return self.runActive();
        if (key.matches(Key.f6, .{})) return self.checkActive();
        if (key.matches(Key.f9, .{})) return self.toggleBreakpoint();
        if (key.matches(Key.f11, .{}) or key.matches(Key.f8, .{}) or key.matches(Key.f5, .{ .shift = true })) {
            self.notYet("The debugger", "T6");
            return;
        }

        switch (self.focus) {
            .editor => try self.editorKey(key),
            .tree => try self.treeKey(key),
            .console => try self.consoleKey(key),
            .breaks => try self.breaksKey(key),
        }
    }

    // Zig tip: `?u8` is an optional byte: a number from 0 to 8, or null when the key is not Ctrl and a
    // digit. The digit is looked for in the code of the key and in the code of the key on the
    // standard layout (`base_layout_codepoint`), which terminals fill in differently.
    /// Ctrl+1 to Ctrl+9 give 0 to 8.
    fn ctrlDigit(key: Key) ?usize {
        if (!key.mods.ctrl or key.mods.alt) return null;
        if (key.codepoint >= '1' and key.codepoint <= '9') return key.codepoint - '1';
        if (key.base_layout_codepoint) |c| {
            if (c >= '1' and c <= '9') return c - '1';
        }
        return null;
    }

    // Zig tip: A function that returns `bool` can say "I used this key" to its caller, which then
    // stops looking. The same shortcuts work on the screen and inside a dialog, so the dialogs
    // can replace each other.
    /// Ctrl+F, Ctrl+P, Ctrl+H, Ctrl+G, Ctrl+L: open a search dialog. True when the key was one of them.
    fn searchShortcut(self: *App, key: Key) bool {
        if (key.matches('f', .{ .ctrl = true })) self.openOverlay(.find_text) else if (key.matches('p', .{ .ctrl = true })) self.openOverlay(.find_file) else if (key.matches('h', .{ .ctrl = true })) self.openOverlay(.replace) else if (key.matches('g', .{ .ctrl = true })) self.openOverlay(.goto) else if (key.matches('l', .{ .ctrl = true })) self.notYet("Query", "T7") else return false;
        return true;
    }

    // Zig tip: `n == 1` and `else`: the value `u8` is a small integer type of one byte; here 1, 2 and
    // 3 are the F-keys. Real machines come with step T5.
    fn pickMachine(self: *App, n: u8) void {
        if (n < 1 or n > 3) return;
        if (!self.connected[n - 1]) {
            self.setMessage("machine {d} is not connected (MACHINE > Connect)", .{n});
            return;
        }
        self.machine = n;
        self.setMessage("connection: {s}", .{if (n == 1) "local" else machine_names[n - 1]});
    }

    // Zig tip: `switch (self.overlay)` on an enum, with `.none => {}` for the value that needs
    // nothing. An `if` chain with `else if` works as well, but the `switch` lists every case.
    fn overlayKey(self: *App, key: Key) !void {
        if (key.matches(Key.escape, .{})) return self.closeOverlay();
        if (self.overlay != .menu and self.searchShortcut(key)) return;
        switch (self.overlay) {
            .menu => try self.menuKey(key),
            .settings, .about => {
                if (key.matches(Key.enter, .{})) self.overlay = .none;
            },
            .open_project => try self.projectKey(key),
            .open_folder => try self.folderKey(key),
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
            .find_text => {
                if (key.matches(Key.enter, .{})) try self.findNext() else try self.find_in.update(.{ .key_press = key });
            },
            .find_file => try self.filesKey(key),
            .replace => try self.replaceKey(key),
            .none => {},
        }
    }

    // Zig tip: A plain `if` chain with early `return`s reads like a table of keys. A letter without
    // Ctrl goes to the menu bar and opens the menu of that letter.
    /// The keys while a menu is open: arrows move, Enter runs, a letter opens another menu.
    fn menuKey(self: *App, key: Key) !void {
        if (key.matches(Key.up, .{})) return self.menuMove(-1);
        if (key.matches(Key.down, .{})) return self.menuMove(1);
        if (key.matches(Key.left, .{})) return self.menuSide(-1);
        if (key.matches(Key.right, .{})) return self.menuSide(1);
        if (key.matches(Key.home, .{})) {
            self.menu_sel = self.firstItem(self.menu_top);
            return;
        }
        if (key.matches(Key.enter, .{})) {
            const row = self.rowAt(self.menu_top, self.menu_sel);
            if (row.cmd) |c| try self.runMenu(c, row.arg);
            return;
        }
        if (!key.mods.ctrl) {
            if (menuByLetter(key.codepoint)) |m| self.openMenu(m);
        }
    }

    // Zig tip: `var k = key; k.mods.shift = false;` copies the key and clears one flag of the copy, so
    // the same `matches` calls recognize an arrow whether Shift is held or not. Shift then only
    // says "extend the selection". The `blk:` label gives the block a name so `break :blk value`
    // can leave it with a result.
    /// The keys of the editor: moving (Shift extends the selection), typing, copy and paste.
    fn editorKey(self: *App, key: Key) !void {
        const b = self.activeBuffer() orelse return;
        const ro = self.activeTab().?.virtual;
        if (key.matches('c', .{ .ctrl = true })) return self.copySelection(false);
        if (key.matches('x', .{ .ctrl = true })) return self.copySelection(true);
        if (key.matches('v', .{ .ctrl = true })) return self.pasteClip();
        if (key.matches('a', .{ .ctrl = true })) {
            b.selectAll();
            return;
        }
        var k = key;
        k.mods.shift = false;
        const here: text.Pos = .{ .row = b.row, .col = b.col };
        const page: isize = @max(1, @as(isize, self.editor_rect.h));
        const moved = blk: {
            if (k.matches(Key.left, .{ .ctrl = true })) b.wordLeft() else if (k.matches(Key.right, .{ .ctrl = true })) b.wordRight() else if (k.matches(Key.left, .{})) b.moveLeft() else if (k.matches(Key.right, .{})) b.moveRight() else if (k.matches(Key.up, .{})) b.moveRows(-1) else if (k.matches(Key.down, .{})) b.moveRows(1) else if (k.matches(Key.page_up, .{})) b.moveRows(-page) else if (k.matches(Key.page_down, .{})) b.moveRows(page) else if (k.matches(Key.home, .{})) b.home() else if (k.matches(Key.end, .{})) b.toEnd() else break :blk false;
            break :blk true;
        };
        if (moved) {
            if (!key.mods.shift) b.anchor = null else if (b.anchor == null) b.anchor = here;
            return;
        }
        if (key.matches(Key.escape, .{})) {
            b.anchor = null;
            return;
        }
        if (ro) return;
        if (key.matches(Key.enter, .{})) {
            _ = try b.deleteSelection();
            try b.newline();
        } else if (key.matches(Key.backspace, .{})) {
            if (!try b.deleteSelection()) try b.backspace();
        } else if (key.matches(Key.delete, .{})) {
            if (!try b.deleteSelection()) try b.delete();
        } else if (key.matches(Key.tab, .{})) {
            _ = try b.deleteSelection();
            try b.insert("  ");
        } else if (key.mods.ctrl or key.mods.alt) {
            // a shortcut that is not ours: do not type its letter
        } else if (key.text) |t| {
            _ = try b.deleteSelection();
            try b.insert(t);
        }
    }

    // Zig tip: The copy is kept twice: `clip` for Ctrl+V inside evetx, and `sys_clip`, which the main
    // loop sends to the clipboard of the system with the terminal (OSC 52) after the event. Each
    // is replaced by freeing the old one first, so the app owns at most one of each.
    /// Ctrl+C, and Ctrl+X when `cut` is true.
    fn copySelection(self: *App, cut: bool) !void {
        const b = self.activeBuffer() orelse return;
        const t = (try b.selectedText(self.gpa)) orelse {
            self.setMessage("nothing is selected", .{});
            return;
        };
        errdefer self.gpa.free(t);
        const sys = try self.gpa.dupe(u8, t);
        if (self.clip) |c| self.gpa.free(c);
        self.clip = t;
        if (self.sys_clip) |c| self.gpa.free(c);
        self.sys_clip = sys;
        if (cut and !self.activeTab().?.virtual) _ = try b.deleteSelection();
    }

    /// Ctrl+V: insert the copied text. (A paste made by the terminal comes as keys: see `pasteEnd`.)
    fn pasteClip(self: *App) !void {
        const b = self.activeBuffer() orelse return;
        if (self.activeTab().?.virtual) return;
        const c = self.clip orelse {
            self.setMessage("nothing copied yet", .{});
            return;
        };
        try b.insertText(c);
    }

    // Zig tip: `std.fmt.bufPrint` formats into a buffer the caller owns and returns the part it
    // wrote; it fails when the buffer is too small, and `catch` then falls back to the plain name.
    /// The title of the terminal window: the program and the project.
    pub fn windowTitle(self: *const App, buf: []u8) []const u8 {
        if (self.project_name.len == 0) return "EVE-TX";
        return std.fmt.bufPrint(buf, "EVE-TX · {s}", .{self.project_name}) catch "EVE-TX";
    }

    /// The main loop takes the text for the system clipboard (the caller frees it).
    pub fn takeSystemClip(self: *App) ?[]u8 {
        const c = self.sys_clip;
        self.sys_clip = null;
        return c;
    }

    pub fn pasteStart(self: *App) void {
        self.pasting = true;
        self.paste_buf.clearRetainingCapacity();
    }

    // Zig tip: A switch on the overlay picks which text field gets the pasted text; `?*TextInput` is
    // an optional pointer, null when the dialog has no field. Only the first line of a paste goes to
    // a one-line field.
    /// The terminal ended a paste: the collected text goes to the dialog field, the console or the editor.
    pub fn pasteEnd(self: *App) !void {
        self.pasting = false;
        const t = self.paste_buf.items;
        if (t.len == 0) return;
        if (self.overlay != .none or self.focus == .console) {
            const ti: ?*TextInput = switch (self.overlay) {
                .none => &self.console_in,
                .goto => &self.goto_in,
                .save_as => &self.saveas_in,
                .find_text => &self.find_in,
                .find_file => &self.files_in,
                .replace => if (self.dlg_field == 0) &self.find_in else &self.replace_in,
                .open_folder => if (self.dlg_field == 0) &self.project_in else null,
                else => null,
            };
            const field = ti orelse return;
            const line = t[0 .. std.mem.indexOfScalar(u8, t, '\n') orelse t.len];
            try field.insertSliceAtCursor(line);
            if (self.overlay == .find_file) try self.filesChanged();
            return;
        }
        if (self.focus == .editor) {
            const b = self.activeBuffer() orelse return;
            if (self.activeTab().?.virtual) return;
            try b.insertText(t);
        }
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
        if (key.matches(Key.enter, .{})) {
            const had = self.saved_open != null;
            if (had) {
                self.gpa.free(self.saved_open.?);
                self.saved_open = null;
            }
            self.files_in.clearRetainingCapacity();
            self.focus = .tree;
            self.overlay = .none;
            return self.openEntry(self.selected);
        }
        if (key.matches(Key.down, .{})) return self.filesStep(1);
        if (key.matches(Key.up, .{})) return self.filesStep(-1);
        try self.files_in.update(.{ .key_press = key });
        try self.filesChanged();
    }

    // Zig tip: `const ti = if (a) &x else &y;` picks which field gets the key, and the one call
    // `ti.update` serves both. Tab moves between the two fields.
    fn replaceKey(self: *App, key: Key) !void {
        if (key.matches(Key.tab, .{}) or key.matches(Key.down, .{}) or key.matches(Key.up, .{})) {
            self.dlg_field = 1 - self.dlg_field;
            return;
        }
        if (key.matches(Key.enter, .{})) return if (self.dlg_field == 0) self.findNext() else self.replaceOne();
        const ti = if (self.dlg_field == 0) &self.find_in else &self.replace_in;
        try ti.update(.{ .key_press = key });
    }

    // Zig tip: `self.console.scroll +|= n` is saturating addition with assignment: it stops at the
    // largest number instead of failing on overflow. `-|=` stops at zero.
    fn consoleKey(self: *App, key: Key) !void {
        if (key.matches(Key.escape, .{})) {
            // Esc cancels a waiting command, and clears the prompt
            if (self.pending_at != null) {
                self.cancelPending();
                self.console_in.clearRetainingCapacity();
                self.setMessage("command cancelled", .{});
            }
            self.focus = .editor;
            return;
        }
        if (key.matches(Key.enter, .{})) {
            self.cancelPending();
            return self.consoleEnter();
        }
        if (self.pending_at != null) self.cancelPending();
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
        if (m.type == .motion) return self.hover(m);
        if (m.type == .release) {
            self.drag = .none;
            return;
        }
        if (m.type == .drag) return self.dragTo(m);
        self.alt_hint = false;
        if (m.button == .wheel_up or m.button == .wheel_down) {
            const up = m.button == .wheel_up;
            self.follow = false;
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
        if (m.button == .middle) {
            // a middle click on a tab closes it
            var k = self.hits.items.len;
            while (k > 0) {
                k -= 1;
                const h = self.hits.items[k];
                if (h.rect.contains(m.col, m.row)) {
                    switch (h.action) {
                        .tab, .tab_close => |t| self.closeTab(t),
                        else => {},
                    }
                    return;
                }
            }
            return;
        }
        if (m.button != .left) return;
        self.follow = true;
        if (self.overlay == .none) {
            if (self.modify and self.grabSplit(m)) return;
            if (self.grabBar(m)) return;
            if (self.editor_rect.contains(m.col, m.row)) {
                if (self.activeBuffer()) |b| {
                    const before: text.Pos = .{ .row = b.row, .col = b.col };
                    const pos = self.editorPos(b, m);
                    b.row = pos.row;
                    b.col = pos.col;
                    // a click starts a selection; with Shift it extends the one that exists
                    if (m.mods.shift) {
                        if (b.anchor == null) b.anchor = before;
                    } else {
                        b.anchor = null;
                        self.sel_from = pos;
                    }
                    self.drag = .select;
                    self.focus = .editor;
                    return;
                }
            }
        }

        var i = self.hits.items.len;
        while (i > 0) {
            i -= 1;
            const h = self.hits.items[i];
            if (h.rect.contains(m.col, m.row)) return self.activate(h.action);
        }
        if (self.overlay != .none) return self.closeOverlay();
        if (self.console_rect.contains(m.col, m.row) and self.bottom == .console) {
            self.focus = .console;
        }
    }

    // Zig tip: A `motion` event arrives when the mouse moves. Only an open menu cares: the row or
    // the menu title under the pointer becomes the selected one, as in a classic menu.
    fn hover(self: *App, m: vaxis.Mouse) void {
        if (self.overlay != .menu) return;
        var i = self.hits.items.len;
        while (i > 0) {
            i -= 1;
            const h = self.hits.items[i];
            if (!h.rect.contains(m.col, m.row)) continue;
            switch (h.action) {
                .menu_top => |t| if (t != self.menu_top) self.openMenu(t),
                .menu_item => |r| self.menu_sel = r,
                else => {},
            }
            return;
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
            .menu_top => |t| {
                if (self.overlay == .menu and self.menu_top == t) self.overlay = .none else self.openMenu(t);
            },
            .menu_item => |i| {
                const row = self.rowAt(self.menu_top, i);
                if (row.cmd) |c| try self.runMenu(c, row.arg);
            },
            .dlg_field => |f| self.dlg_field = f,
            .nop => {},
            .dlg => |d| switch (d) {
                .ok => try self.overlayKey(.{ .codepoint = Key.enter }),
                .forget => try self.forgetProject(),
                .browse => self.openFolderDialog(),
                .open_here => try self.openHere(),
            },
            .proj_row => |i| {
                if (self.proj_sel == i) try self.openCached(i) else self.proj_sel = i;
            },
            .fb_row => |i| {
                self.dlg_field = 1;
                if (self.fb_sel == i) self.fbEnterRow(i) else self.fb_sel = i;
            },
            .panel_focus => |p| self.focusPanel(p),
            .panel_hide => |p| self.togglePanel(p),
            .panel_max => |p| self.toggleMaximize(p),
            .break_row => |i| {
                if (self.break_sel == i) try self.jumpToBreakpoint(i) else self.break_sel = i;
                self.focus = .breaks;
            },
            .close_overlay => self.closeOverlay(),
            .button => |b| switch (b) {
                .run => try self.runActive(),
                .step_into, .step_out, .cont, .stop => self.notYet("The debugger", "T6"),
                .replace => try self.replaceOne(),
                .replace_all => try self.replaceEvery(),
            },
        }
    }
};
