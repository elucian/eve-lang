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
const dbf = @import("dbf.zig");
const sqlstruct = @import("sqlstruct.zig");
const cache_mod = @import("cache.zig");
const options_mod = @import("options.zig");
const theme = @import("theme.zig");

// ------------------------------------------------------------------ small types

// Zig tip: An `enum` names a fixed set of choices. A `switch` on an enum must handle every value
// or have an `else`, so adding a choice later makes the compiler point at every place that needs a
// new case.
/// Where the keyboard goes.
pub const Focus = enum { tree, editor, console, breaks, sql };

// Zig tip: An enum like `Focus`: one name for every tab. `@tagName(tab)` would give its name as
// text.
/// The five tabs of the Tools Panel.
pub const BottomTab = enum { console, watch, stderr, stdout, breaks, sql };

// Zig tip: The three panels of the screen are an enum too. The keyboard focus (`Focus`) is finer
// than this: the Main Panel is the `editor` focus, the Tools Panel is `console` or `breaks`.
/// The three panels: the files tree, the windows with their editor, the console and the other tools.
pub const Panel = enum { tree, main, tools };

// Zig tip: The state "what is open over the screen" is one enum, so two dialogs can never be open
// together.
/// What is open over the screen, if anything.
pub const Overlay = enum { none, new_table, sq_structure, new_file, wizard, append_n, structure, confirm, tab_menu, machine_menu, register, menu, settings, about, goto, save_as, find_text, find_file, replace, open_project, open_folder };

// Zig tip: Naming every button lets `activate` use one `switch` for all clicks. `cont` is written
// instead of `continue` because `continue` is a keyword of Zig.
/// The buttons of the tool bars.
pub const Button = enum { run, halt, next, step, exit, trace, replace, replace_all };

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
    /// The machine name on the toolbar: open the list of the registered machines under it (absolute cell).
    machine_open: struct { x: u16, y: u16 },
    /// The gear on the toolbar: open the registration form.
    register_open,
    machinemenu_item: usize,
    /// The arrows of the scroll bar of a log (Console, Stdout, Stderr, Watch, SQL): half a page up or down.
    log_scroll: ScrollBtn,
    /// The arrows of the scroll bar of the list of breakpoints.
    break_scroll: ScrollBtn,
    /// The check box of a row of the Breaks tab: enable or disable the breakpoint.
    break_toggle: usize,
    /// The trash icon of a row: ask, then remove the breakpoint.
    break_trash: usize,
    /// The tool Clear of the Tools Panel.
    clear_panel,
    /// The arrows of the scroll bars of a DBF table.
    table_scroll: ScrollBtn,
    /// A cell of the structure grid, the buttons under it, a type of the drop-down list, and the arrow of the Type cell.
    st_cell: struct { row: u16, col: u8 },
    st_btn: StBtn,
    st_pick: u8,
    st_drop_open,
    /// A row of the list of a folder, and the arrows of its scroll bar.
    folder_row: usize,
    folder_scroll: ScrollBtn,
    /// The same for the structure dialog of a SQLite table.
    sq_cell: struct { row: u16, col: u8 },
    sq_btn: StBtn,
    sq_pick: u8,
    sq_drop_open,
    /// The View button of the Main Panel, and the arrows of the scroll bar of a rendered page.
    view_toggle,
    md_scroll: ScrollBtn,
    /// A choice in the list of a wizard.
    wiz_choice: usize,
    /// The buttons of the confirmation dialog.
    confirm: bool,
    reg_row: usize,
    reg_btn: RegBtn,
    menu_top: usize,
    menu_item: usize,
    dlg_field: u8,
    break_row: usize,
    close_overlay,
    nop,
    lock_toggle,
    panel_focus: Panel,
    panel_hide: Panel,
    panel_max: Panel,
    opt: OptAction,
    tabmenu_item: usize,
    scroll: ScrollBtn,
    tree_scroll: ScrollBtn,
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
pub const LineKind = enum { input, out, err, info, sql, shell };
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

/// A DBF table opened in a tab: the table, the cell that is selected, and the first row and column shown.
/// The width of the column of record numbers of a DBF grid.
pub const dbf_rownum_w: u16 = 8;

pub const TableView = struct {
    t: dbf.Table,
    row: usize = 0,
    col: usize = 0,
    top: usize = 0,
    left: usize = 0,
    /// A table read from a SQLite database (a result of SQL): it is shown, not edited.
    readonly: bool = false,
};

/// One line of the list of a folder.
pub const FolderItem = struct { name: []u8, is_dir: bool, size: u64, created: i64 };

/// The content of a folder, for the Main Panel: the folder (a path in the project), its items, the selected one and the first shown.
pub const FolderView = struct {
    dir: []u8,
    items: std.ArrayList(FolderItem) = .empty,
    sel: usize = 0,
    top: usize = 0,
};

// Zig tip: a table of a few rows, written in the function, says what to call each kind of file; the first row whose extension
// matches wins (the case is ignored). The labels of images, audio and so on come from `card_exts`.
/// A few words about a file or folder, for the list of a folder.
pub fn describeName(name: []const u8, is_dir: bool) []const u8 {
    if (is_dir) return if (std.mem.eql(u8, name, "..")) "Parent folder" else "Folder";
    const rows = [_]struct { e: []const u8, d: []const u8 }{
        .{ .e = "eve", .d = "Eve program" },
        .{ .e = "md", .d = "Markdown document" },
        .{ .e = "sql", .d = "SQL script" },
        .{ .e = "dbf", .d = "DBF table" },
        .{ .e = "db", .d = "SQLite database" },
        .{ .e = "sqlite", .d = "SQLite database" },
        .{ .e = "json", .d = "JSON data" },
        .{ .e = "cfg", .d = "Configuration" },
        .{ .e = "env", .d = "Environment" },
        .{ .e = "txt", .d = "Text" },
        .{ .e = "csv", .d = "CSV data" },
        .{ .e = "html", .d = "Web page" },
        .{ .e = "css", .d = "Style sheet" },
        .{ .e = "js", .d = "JavaScript" },
        .{ .e = "zig", .d = "Zig source" },
        .{ .e = "py", .d = "Python script" },
        .{ .e = "gitignore", .d = "Git ignore list" },
        .{ .e = "log", .d = "Log" },
    };
    const ext = extensionOf(name);
    for (rows) |r| {
        if (std.ascii.eqlIgnoreCase(r.e, ext)) return r.d;
    }
    return cardLabel(name) orelse "File";
}

/// A field in the structure dialog, and the place of the field it comes from in the file (null for a new one).
pub const StField = struct { f: dbf.Field, src: ?usize = null };

pub const Tab = struct {
    /// Relative to the project folder; empty for a new file that was never saved.
    path: []u8,
    /// Text files have a buffer; any other file has a card.
    buf: ?text.Buffer = null,
    card: Card = .{},
    eve: bool = false,
    /// An SQL file (`.sql`): the editor colors it as SQL.
    sql: bool = false,
    /// A DBF table (`.dbf`): the Main Panel shows its records in a grid.
    table: ?*TableView = null,
    /// A Markdown file that is shown rendered (View button), and the first rendered line shown.
    render: bool = false,
    render_top: usize = 0,
    /// A folder shown as a list (a click on a folder of the tree): there is only one such tab, and it follows the clicks.
    folder: ?*FolderView = null,
    /// The name shown on the tab when it is not the name of the file (a table of a database: `shop.orders`).
    label: []u8 = &.{},
    /// A window that is not a file (Shortcuts, Manual, Tutorial): read only, never saved.
    virtual: bool = false,

    // Zig tip: `self: Tab` takes a copy of the struct. The result is a slice into `self.path`, not a
    // new string, so it costs nothing. `if (cut) |i| a else b` unwraps the optional from
    // `lastIndexOfScalar`.
    pub fn title(self: Tab) []const u8 {
        if (self.label.len > 0) return self.label;
        if (self.path.len == 0) return "untitled";
        const cut = std.mem.lastIndexOfScalar(u8, self.path, '/');
        return if (cut) |i| self.path[i + 1 ..] else self.path;
    }
};

// Zig tip: `path` is owned (`[]u8`): every breakpoint has its own copy, freed when the breakpoint
// goes.
/// What a Yes of the confirmation dialog does.
pub const Confirm = enum { none, delete_breakpoint, clear_breakpoints, apply_structure, move_files, apply_sqlite, drop_table };

/// A breakpoint of the editor. A breakpoint that is not enabled stays in the list but the debugger does not stop at it.
pub const Breakpoint = struct { path: []u8, line: usize, enabled: bool = true };

// Zig tip: An enum with many values can be written over several lines. Each value is a command
// that the menu, a key or a click can ask for. A command that needs a number (which window, which
// machine) gets it in the `arg` of its row.
// Zig tip: A union of the things a click in the Options dialog can do. `slider` holds a small
// struct written in place (`struct { ch: u8, v: u8 }`): the channel (0 red, 1 green, 2 blue) and
// the value 0 to 255 that the clicked cell stands for. `i16` is signed so a button can add or take.
/// The buttons of the structure dialog.
/// The wizards of the new files that have choices to make.
pub const WizKind = enum { eve, sql };

pub const StBtn = enum { prev, next, add, remove, up, down, apply };

/// The buttons of the registration form.
pub const RegBtn = enum { save, select };

/// What a click in the Options dialog does.
pub const OptAction = union(enum) {
    tab: u8,
    theme: u8,
    slot: u8,
    channel: u8,
    slider: struct { ch: u8, v: u8 },
    swatch: u24,
    auto: i16,
    delay: i16,
    hover: i16,
    trace: i16,
    ok,
    defaults,
};

/// The commands of the popup menu of a tab (a right click on its title).
pub const TabCmd = enum { save, save_as, upload, close_this, close_right, close_left, close_clean };

/// A row of the popup menu of a tab.
pub const TabMenuRow = struct { label: []const u8, cmd: TabCmd };

pub const tab_menu_rows = [_]TabMenuRow{
    .{ .label = "Save", .cmd = .save },
    .{ .label = "Save As…", .cmd = .save_as },
    .{ .label = "Upload…", .cmd = .upload },
    .{ .label = "Close this", .cmd = .close_this },
    .{ .label = "Close right", .cmd = .close_right },
    .{ .label = "Close left", .cmd = .close_left },
    .{ .label = "Close clean", .cmd = .close_clean },
};

/// Every command of the main menu.
pub const MenuCmd = enum {
    open_project, open_folder, new_file, new_dbf, create_table, drop_table, preview, data_structure, data_append, data_append_n, data_delete, data_edit, save, save_as, close_tab, quit,
    undo, redo, replace, toggle_wrap, toggle_hidden, close_all, close_clean,
    find_text, find_file, goto_line, query,
    run, check_file, clear_panel, dbg_next, dbg_step, dbg_exit, dbg_trace, stop, breakpoint,
    machine_pick, register, upload,
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
pub const menu_window: usize = 6;
/// The place of the MACHINE menu: its first rows are the machines that are connected (see `App.rowAt`).
pub const menu_machine: usize = 4;

// Zig tip: a struct with slices that it owns (`[]u8`, not `[]const u8`) must be freed by whoever owns the struct: see
// `Machine.free`. Three texts, because `label` is computed once from the other two and drawn on every frame.
/// A registered machine: where it is (address and port) and the text that names it. The first one, Local, is always there.
pub const Machine = struct {
    label: []u8,
    address: []u8,
    port: u16,

    fn free(self: Machine, gpa: std.mem.Allocator) void {
        gpa.free(self.label);
        gpa.free(self.address);
    }
};

const machine_keys = [_][]const u8{ "Alt+1", "Alt+2", "Alt+3" };

// Zig tip: A `const` array of struct literals is built at compile time and stored in the program.
// `[_]Menu{...}` lets the compiler count the menus; `menus.len` is then a compile-time number.
/// The menus of the bar, left to right. The last one (HELP) is drawn at the right side.
pub const menus = [_]Menu{
    .{ .label = "FILE", .items = &.{
        .{ .label = "Open project…", .key = "Ctrl+O", .cmd = .open_project },
        .{ .label = "Open Folder…", .key = "Ctrl+Shift+O", .cmd = .open_folder },
        .{ .label = "New…", .key = "Ctrl+N", .cmd = .new_file },
        .{ .label = "Save", .key = "Ctrl+S", .cmd = .save },
        .{ .label = "Save As…", .key = "Ctrl+Shift+S", .cmd = .save_as },
        .{ .label = "Upload…", .cmd = .upload },
        .{ .label = "Close window", .key = "Ctrl+W", .cmd = .close_tab },
        sep,
        .{ .label = "Quit", .key = "Ctrl+Q", .cmd = .quit },
    } },
    .{ .label = "EDIT", .items = &.{
        .{ .label = "Undo", .key = "Ctrl+U", .cmd = .undo },
        .{ .label = "Redo", .key = "Ctrl+Y", .cmd = .redo },
        sep,
        .{ .label = "Replace…", .key = "Ctrl+H", .cmd = .replace },
        sep,
        .{ .label = "Wrap", .cmd = .toggle_wrap },
        .{ .label = "Show hidden characters", .cmd = .toggle_hidden },
        sep,
        .{ .label = "Edit structure…", .cmd = .data_structure },
        .{ .label = "Create table…", .cmd = .create_table },
        .{ .label = "Drop table…", .cmd = .drop_table },
        sep,
        .{ .label = "Append row", .key = "Ins", .cmd = .data_append },
        .{ .label = "Append rows…", .cmd = .data_append_n },
        .{ .label = "Edit cell", .key = "Enter", .cmd = .data_edit },
        .{ .label = "Delete / recall row", .key = "Del", .cmd = .data_delete },
    } },
    .{ .label = "SEARCH", .items = &.{
        .{ .label = "Find Text…", .key = "Ctrl+F", .cmd = .find_text },
        .{ .label = "Find File…", .key = "Ctrl+P", .cmd = .find_file },
        .{ .label = "GoTo…", .key = "Ctrl+G", .cmd = .goto_line },
        .{ .label = "Query…", .key = "F7", .cmd = .query },
    } },
    .{ .label = "RUN", .items = &.{
        .{ .label = "Run", .key = "F5", .cmd = .run },
        .{ .label = "Check syntax", .key = "F6", .cmd = .check_file },
        .{ .label = "Next", .key = "F8", .cmd = .dbg_next },
        .{ .label = "Step", .key = "F11", .cmd = .dbg_step },
        .{ .label = "Exit", .key = "Shift+F11", .cmd = .dbg_exit },
        .{ .label = "Trace", .key = "Shift+F8", .cmd = .dbg_trace },
        .{ .label = "Halt", .key = "Shift+F5", .cmd = .stop },
        .{ .label = "Clear panel", .cmd = .clear_panel },
        sep,
        .{ .label = "Breakpoint", .key = "F9", .cmd = .breakpoint },
    } },
    .{ .label = "MACHINE", .items = &.{
        sep,
        .{ .label = "Register…", .key = "Ctrl+K", .cmd = .register },
    } },
    .{ .label = "WINDOW", .items = &.{
        .{ .label = "Select", .key = "Ctrl+Tab", .cmd = .select_window },
        .{ .label = "Close", .key = "Ctrl+W", .cmd = .close_tab },
        .{ .label = "Close All", .cmd = .close_all },
        .{ .label = "Close Clean", .cmd = .close_clean },
        sep,
        .{ .label = "Layout modify", .key = "Ctrl+L", .cmd = .modify },
        .{ .label = "Layout freeze", .key = "Ctrl+Z", .cmd = .freeze },
        sep,
        .{ .label = "Preview", .cmd = .preview },
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

/// The small buttons at the ends of the scroll bars: ten columns left or right, half a page up or down.
pub const ScrollBtn = enum { left, right, up, down };

// Zig tip: `std.atomic.Value(bool)` is a flag that two threads can use without a lock: `store` and `load` are
// indivisible. The worker thread owns the plain fields until it sets `done`; after that the main thread (which sees
// `done` through an `.acquire` load) owns them. That rule replaces a mutex here. A debug session also shares a few
// things while it runs (the output lines, the commands, the place where the program is stopped): the numbers are atomic,
// and the two lists are guarded by `busy`, a tiny spin lock made from one atomic flag.
/// One run of `eve`: a worker thread starts the process and collects its output, so the screen keeps working and the
/// Stop button can end the process. A debug run (`eve debug`) also takes commands for the debugger on the standard input
/// and shows its output while it runs.
pub const RunJob = struct {
    io: Io,
    gpa: std.mem.Allocator,
    argv: [][]u8,
    cwd: ?[]u8,
    /// `eve debug <file>`: stdin is a pipe, `@debug` lines of the output are events, the rest is shown at once.
    debug: bool = false,
    stop: std.atomic.Value(bool) = .init(false),
    done: std.atomic.Value(bool) = .init(false),
    /// The program is stopped before a statement and waits for a command; `line` is that statement (from 1) and
    /// `serial` grows with each stop, so the main thread sees a new one.
    paused: std.atomic.Value(bool) = .init(false),
    line: std.atomic.Value(u32) = .init(0),
    serial: std.atomic.Value(u32) = .init(0),
    busy: std.atomic.Value(bool) = .init(false),
    /// Lines of output not yet taken by the main thread, and commands not yet written to the debugger (under `busy`).
    live: std.ArrayList(u8) = .empty,
    cmds: std.ArrayList(u8) = .empty,
    /// The variables of the last stop, `name = value` lines (under `busy`).
    vars: std.ArrayList(u8) = .empty,
    scanned: usize = 0,
    thread: ?std.Thread = null,
    stopped: bool = false,
    err_name: ?[]const u8 = null,
    term: ?std.process.Child.Term = null,
    stdout: []u8 = &.{},
    stderr: []u8 = &.{},

    fn destroy(self: *RunJob) void {
        for (self.argv) |a| self.gpa.free(a);
        self.gpa.free(self.argv);
        if (self.cwd) |c| self.gpa.free(c);
        self.gpa.free(self.stdout);
        self.gpa.free(self.stderr);
        self.live.deinit(self.gpa);
        self.cmds.deinit(self.gpa);
        self.vars.deinit(self.gpa);
        self.gpa.destroy(self);
    }

    // Zig tip: `cmpxchgWeak(false, true, ...)` sets the flag to true only if it is false and returns null when it won;
    // a non-null answer means somebody else holds it, so the loop tries again. `spinLoopHint` tells the processor we
    // are waiting. The lock is held for a few instructions only (copying a short line), so spinning is fine.
    fn lock(self: *RunJob) void {
        while (self.busy.cmpxchgWeak(false, true, .acquire, .monotonic) != null) std.atomic.spinLoopHint();
    }

    fn unlock(self: *RunJob) void {
        self.busy.store(false, .release);
    }

    /// Queue a command for the debugger (one line). The commands that let the program go on clear `paused` at once, so
    /// a second click on the same button does nothing while the program runs.
    pub fn sendCommand(self: *RunJob, line_text: []const u8) void {
        self.lock();
        defer self.unlock();
        self.cmds.appendSlice(self.gpa, line_text) catch return;
        self.cmds.append(self.gpa, '\n') catch return;
        const verb = if (std.mem.indexOfScalar(u8, line_text, ' ')) |k| line_text[0..k] else line_text;
        for ([_][]const u8{ "run", "next", "step", "exit", "trace", "halt" }) |v| {
            if (std.mem.eql(u8, v, verb)) self.paused.store(false, .release);
        }
    }

    /// Take the variables of the last stop; the caller frees the slice.
    pub fn takeVars(self: *RunJob) ?[]u8 {
        self.lock();
        defer self.unlock();
        return self.gpa.dupe(u8, self.vars.items) catch null;
    }

    /// Take the output lines that arrived since the last call; the caller frees the slice.
    pub fn takeLive(self: *RunJob) ?[]u8 {
        self.lock();
        defer self.unlock();
        if (self.live.items.len == 0) return null;
        return self.live.toOwnedSlice(self.gpa) catch null;
    }

    fn work(self: *RunJob) void {
        self.runChild() catch |err| {
            self.err_name = @errorName(err);
        };
        self.done.store(true, .release);
    }

    // Zig tip: `std.fmt.parseInt(u32, word, 10) catch 0` gives a default instead of an error; `tokenizeScalar` splits
    // the event line at spaces. An event is `@debug paused <line> <depth> <text>`, `@debug trace <line> <depth>` or
    // `@debug end <status>`; the lines `@debug break` and `@debug clear` only confirm a command.
    fn event(self: *RunJob, ev_text: []const u8) void {
        var words = std.mem.tokenizeScalar(u8, ev_text, ' ');
        _ = words.next();
        const kind = words.next() orelse return;
        if (std.mem.eql(u8, kind, "vars")) {
            self.lock();
            defer self.unlock();
            self.vars.clearRetainingCapacity();
        } else if (std.mem.eql(u8, kind, "var")) {
            // `@debug var name=value`: shown as `name = value`
            const rest = ev_text["@debug var ".len..];
            const eq = std.mem.indexOfScalar(u8, rest, '=') orelse return;
            self.lock();
            defer self.unlock();
            self.vars.appendSlice(self.gpa, rest[0..eq]) catch return;
            self.vars.appendSlice(self.gpa, " = ") catch return;
            self.vars.appendSlice(self.gpa, rest[eq + 1 ..]) catch return;
            self.vars.append(self.gpa, '\n') catch return;
        } else if (std.mem.eql(u8, kind, "paused") or std.mem.eql(u8, kind, "trace")) {
            const ln = std.fmt.parseInt(u32, words.next() orelse "0", 10) catch 0;
            self.line.store(ln, .release);
            if (kind[0] == 'p') {
                _ = self.serial.fetchAdd(1, .acq_rel);
                self.paused.store(true, .release);
            }
        } else if (std.mem.eql(u8, kind, "end")) {
            self.paused.store(false, .release);
        }
    }

    // Zig tip: the output of the child stays in the buffer of the reader, which we do not consume: `scanned` marks how
    // far we have looked. Only complete lines are handled (up to the last newline); at the end `final` also takes the
    // rest. A line is either an event of the debugger or a line of the program, which goes to `live`.
    fn scan(self: *RunJob, data: []const u8, final: bool) void {
        while (self.scanned < data.len) {
            const rest = data[self.scanned..];
            const nl = std.mem.indexOfScalar(u8, rest, '\n');
            if (nl == null and !final) return;
            const raw = if (nl) |k| rest[0..k] else rest;
            self.scanned += if (nl) |k| k + 1 else rest.len;
            const line = std.mem.trimEnd(u8, raw, "\r");
            if (std.mem.startsWith(u8, line, "@debug ")) {
                self.event(line);
            } else {
                self.lock();
                defer self.unlock();
                self.live.appendSlice(self.gpa, line) catch {};
                self.live.append(self.gpa, '\n') catch {};
            }
        }
    }

    // Zig tip: `fill` waits for output with a timeout, so the loop wakes ten times a second to look at the stop flag and
    // to write the queued commands. `error.Timeout` just means "nothing yet"; `error.EndOfStream` means both pipes are
    // closed. `defer child.kill` ends the process on every way out of the function (it does nothing after `wait`).
    fn runChild(self: *RunJob) !void {
        const io = self.io;
        var child = try std.process.spawn(io, .{
            .argv = self.argv,
            .cwd = if (self.cwd) |c| .{ .path = c } else .inherit,
            .stdin = if (self.debug) .pipe else .ignore,
            .stdout = .pipe,
            .stderr = .pipe,
        });
        defer child.kill(io);
        var buf: Io.File.MultiReader.Buffer(2) = undefined;
        var mr: Io.File.MultiReader = undefined;
        mr.init(self.gpa, io, buf.toStreams(), &.{ child.stdout.?, child.stderr.? });
        defer mr.deinit();
        while (true) {
            if (self.stop.load(.acquire)) {
                self.stopped = true;
                break;
            }
            if (self.debug) {
                var out: [256]u8 = undefined;
                var n: usize = 0;
                {
                    self.lock();
                    defer self.unlock();
                    n = @min(out.len, self.cmds.items.len);
                    @memcpy(out[0..n], self.cmds.items[0..n]);
                    self.cmds.replaceRange(self.gpa, 0, n, &.{}) catch {};
                }
                if (n > 0) child.stdin.?.writeStreamingAll(io, out[0..n]) catch {};
            }
            mr.fill(1, .{ .duration = .{ .raw = .fromMilliseconds(100), .clock = .awake } }) catch |err| switch (err) {
                error.EndOfStream => break,
                error.Timeout => {},
                else => return err,
            };
            if (self.debug) self.scan(mr.reader(0).buffered(), false);
        }
        if (!self.stopped) self.term = try child.wait(io);
        if (self.debug) self.scan(mr.reader(0).buffered(), true);
        self.paused.store(false, .release);
        const out_slice = try mr.toOwnedSlice(0);
        if (self.debug) self.gpa.free(out_slice) else self.stdout = out_slice;
        self.stderr = try mr.toOwnedSlice(1);
    }
};

/// What the mouse is dragging: a border between panels, or a scroll bar thumb.
pub const Drag = enum { none, tree_split, tools_split, vbar, hbar, select, tree_v, tree_h, md_v, tbl_v, tbl_h };

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
    /// The machines in order of registration (the first is Local, always), and the one in use (a place in the list).
    machines: std.ArrayList(Machine) = .empty,
    machine: usize = 0,
    /// The registration form: the selected row (the last row is the new machine), and its two fields.
    reg_sel: usize = 0,
    reg_addr: TextInput,
    reg_port: TextInput,
    /// The dropdown under the machine name of the toolbar: its place and the selected row.
    mm_x: u16 = 0,
    mm_y: u16 = 0,
    mm_sel: usize = 0,
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
    /// The layout was put in modify mode with the mouse: it freezes by itself three seconds after the
    /// mouse button is released (`freeze_at`, a time of the `awake` clock in milliseconds).
    mouse_modify: bool = false,
    /// The options of the tool (theme, timers), saved for the user; `opt_backup` is what they were when
    /// the Options dialog opened, to put back on Cancel. The rest is the state of that dialog.
    options: options_mod.Options = .{},
    opt_backup: options_mod.Options = .{},
    opt_tab: u8 = 0,
    opt_slot: u8 = 0,
    opt_channel: u8 = 0,
    opt_row: u8 = 0,
    /// When the changed files are saved by themselves (a time of the `awake` clock in milliseconds).
    autosave_at: ?i64 = null,
    /// The popup menu of a tab: where it is, which tab it is for, and the selected row.
    tab_menu_x: u16 = 0,
    tab_menu_y: u16 = 0,
    tab_menu_tab: usize = 0,
    tab_menu_sel: usize = 0,
    freeze_at: ?i64 = null,
    /// The shape of the mouse pointer: a double arrow over a border between panels.
    pointer: vaxis.Mouse.Shape = .default,
    /// The border under the pointer, whether or not it is active yet, and when the pointer came to it (clock `awake`, ms).
    hover_cand: ?Drag = null,
    hover_since: i64 = 0,
    /// The border that the pointer rests on long enough (the hover delay of the options) or that is free because the
    /// layout is unlocked: it is painted and can be dragged.
    hover_split: ?Drag = null,
    /// The eve process that Run started (see `RunJob`); the interface stays alive while it runs.
    job: ?*RunJob = null,
    /// The debug session: the script (path in the project) and the last stop that was shown (`RunJob.serial`).
    dbg_path: ?[]u8 = null,
    dbg_serial: u32 = 0,
    dbg_sent: bool = false,
    /// The command to send at the first stop: Run with breakpoints sends `run`, Trace sends `trace`; null waits.
    dbg_auto: ?[]const u8 = null,
    /// The line shown last while the program traces, so that the editor follows it.
    dbg_line_seen: u32 = 0,
    /// The confirmation dialog (`askConfirm`): its message, what a Yes does, and for which item.
    confirm_msg: ?[]u8 = null,
    confirm_what: Confirm = .none,
    confirm_arg: usize = 0,
    /// The console is a shell prompt (`$`) after `exit`: lines go to the shell that started evetx; `eve` comes back.
    shell_mode: bool = false,
    shell_exe: []u8 = &.{},
    /// The variables of the stopped program (Watch tab), the SQL panel (its input, its output, its database file),
    /// and the first breakpoint shown in the Breaks tab.
    watch_log: Log = .{},
    sql_in: TextInput,
    sql_log: Log = .{},
    sql_db: ?[]u8 = null,
    break_top: usize = 0,
    /// The structure dialog (SQL:> alter table <name>): the file, the fields being edited and as they were, the records
    /// in the file, the selected cell, the cell being edited, the type list, and the last complaint.
    st_path: ?[]u8 = null,
    st_fields: std.ArrayList(StField) = .empty,
    st_orig: std.ArrayList(StField) = .empty,
    st_records: u32 = 0,
    st_row: usize = 0,
    st_col: u8 = 0,
    st_edit: TextInput,
    st_editing: bool = false,
    st_drop: bool = false,
    st_drop_sel: usize = 0,
    st_error: ?[]const u8 = null,
    /// The command waiting in the prompt belongs to the SQL panel (not the Console).
    pending_sql: bool = false,
    /// Where the grid of a DBF table is drawn, for the mouse.
    tbl_rect: Rect = .{},
    /// The tracks of the scroll bars of the rendered page and of a table, and how much they show (for the mouse).
    mdbar_rect: Rect = .{},
    md_total: usize = 0,
    md_visible: usize = 0,
    tblv_rect: Rect = .{},
    tblh_rect: Rect = .{},
    tbl_rows: usize = 0,
    tbl_cols: usize = 0,
    /// The cell of a DBF table that is being edited, and its text.
    tbl_editing: bool = false,
    /// The structure dialog of a SQLite table: the file and the table, the columns being edited and as they were, the
    /// selected cell, the cell being edited, the type list, and the last complaint.
    sq_db: ?[]u8 = null,
    sq_table: ?[]u8 = null,
    sq_cols: std.ArrayList(sqlstruct.Col) = .empty,
    sq_orig: std.ArrayList(sqlstruct.Col) = .empty,
    sq_row: usize = 0,
    sq_col: u8 = 0,
    sq_edit: TextInput,
    sq_editing: bool = false,
    sq_drop: bool = false,
    sq_drop_sel: usize = 0,
    sq_error: ?[]const u8 = null,
    /// The structure dialog makes a new table (not the rebuild of an old one).
    sq_new: bool = false,
    /// The table that the confirmation dialog will drop: a DBF file (its path) or a table of a SQLite file (file and name).
    drop_a: ?[]u8 = null,
    drop_b: ?[]u8 = null,
    drop_is_dbf: bool = false,
    /// The Tab of the SQL panel: a cycle in progress, the letters typed when it began, the place in the matches, and how many
    /// letters of the word on the line it has put.
    sql_tab_active: bool = false,
    sql_tab_prefix: ?[]u8 = null,
    sql_tab_idx: usize = 0,
    sql_tab_len: usize = 0,
    /// The files marked in the tree with Ctrl+click (paths in the project, owned).
    marks: std.ArrayList([]u8) = .empty,
    /// A press on a row of the tree: the row, whether the pointer moved since (a drag), and the row under the pointer.
    tdrag_src: ?u32 = null,
    tdrag_active: bool = false,
    tdrag_over: ?u32 = null,
    /// What the confirmation dialog of a move will do: the files and the folder they go to (owned).
    move_srcs: std.ArrayList([]u8) = .empty,
    move_dest: ?[]u8 = null,
    tbl_edit: TextInput,
    /// The wizard of a new file: which one, the path of the file, the choice made in its list and the name field.
    wiz_kind: WizKind = .eve,
    wiz_path: ?[]u8 = null,
    wiz_choice: usize = 0,
    wiz_name: TextInput,
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
    /// The working folder of the console (`cd`), as the system wants it; null means the project folder. Run and Check
    /// set it to the folder of the script, so that `eve` finds the `eve.cfg` of that sub-project.
    work_dir: ?[]u8 = null,
    /// Edit > Wrap: long lines are cut at the right edge of the editor and the horizontal bar goes away.
    wrap: bool = false,
    /// Edit > Show hidden characters: spaces, tabs and line ends are drawn.
    show_hidden: bool = false,
    /// The tree: first column shown, longest row, and the places of its bars.
    tree_left: usize = 0,
    tree_content: usize = 0,
    tvbar_rect: Rect = .{},
    /// The tree must show the selected row (after a key, a search or a click); a scroll bar or the wheel turns it off, so
    /// the view can go where the person pulls it.
    tree_follow: bool = true,
    thbar_rect: Rect = .{},
    /// True while the session is being read: nothing is written then.
    restoring: bool = false,
    /// The line numbers of the editor: a click there sets or removes a breakpoint.
    gutter_rect: Rect = .{},
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
        var cache = try cache_mod.Cache.init(gpa, io, env);
        errdefer cache.deinit();
        cache.load();
        // no folder on the command line: reopen the project where the last session ended
        const last: ?[]u8 = if (root.len == 0) cache.lastProject() else null;
        defer if (last) |l| gpa.free(l);
        const chosen: []const u8 = last orelse root;
        const name = if (chosen.len == 0) try gpa.dupe(u8, "") else try projectName(gpa, io, chosen);
        errdefer gpa.free(name);
        const own_root = try gpa.dupe(u8, chosen);
        errdefer gpa.free(own_root);
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
            .reg_addr = TextInput.init(gpa),
            .sql_in = TextInput.init(gpa),
            .st_edit = TextInput.init(gpa),
            .tbl_edit = TextInput.init(gpa),
            .sq_edit = TextInput.init(gpa),
            .wiz_name = TextInput.init(gpa),
            .reg_port = TextInput.init(gpa),
            .cache = cache,
            .frame = .init(gpa),
        };
        if (self.cache.readFile("evetx-options.txt")) |bytes| {
            defer gpa.free(bytes);
            self.options = options_mod.Options.parse(bytes);
        }
        self.applyOptions();
        // the shell that started evetx: $SHELL when there is one (Git Bash, a Linux shell), else the Windows command shell
        const sh = env.get("SHELL") orelse (if (builtin.os.tag == .windows) env.get("COMSPEC") orelse "cmd.exe" else "sh");
        self.shell_exe = try gpa.dupe(u8, std.fs.path.basename(sh));
        try self.machineAdd("localhost", 0, "Local");
        self.loadMachines();
        if (chosen.len > 0) {
            try self.tree.scan(io, chosen, name);
            self.restoreSession();
        }
        try self.console.add(gpa, "evetx: the console runs `eve` with what you type (run <file>, --check <file>, cd <folder>, clear, quit).", .info);
        return self;
    }

    // Zig tip: `for ([_]*TextInput{ &a, &b }) |ti|` loops over an array of pointers written in place.
    // `destroy` frees in the opposite order of `create`, and the last step frees the `App` itself.
    pub fn destroy(self: *App) void {
        const gpa = self.gpa;
        if (self.job) |j| {
            j.stop.store(true, .release);
            if (j.thread) |t| t.join();
            j.destroy();
        }
        for (self.tabs.items) |*t| {
            if (t.buf) |*b| b.deinit();
            if (t.table) |tv| {
                tv.t.deinit();
                gpa.destroy(tv);
            }
            if (t.folder) |fv| self.freeFolder(fv);
            if (t.label.len > 0) gpa.free(t.label);
            gpa.free(t.path);
        }
        self.tabs.deinit(gpa);
        self.tree.deinit();
        self.visible.deinit(gpa);
        for (self.machines.items) |m| m.free(gpa);
        self.machines.deinit(gpa);
        self.watch_log.deinit(gpa);
        if (self.st_path) |p| gpa.free(p);
        if (self.wiz_path) |p| gpa.free(p);
        if (self.sq_db) |p| gpa.free(p);
        if (self.drop_a) |p| gpa.free(p);
        if (self.drop_b) |p| gpa.free(p);
        if (self.sql_tab_prefix) |p| gpa.free(p);
        if (self.sq_table) |p| gpa.free(p);
        self.sq_cols.deinit(gpa);
        self.sq_orig.deinit(gpa);
        for (self.marks.items) |p| gpa.free(p);
        self.marks.deinit(gpa);
        for (self.move_srcs.items) |p| gpa.free(p);
        self.move_srcs.deinit(gpa);
        if (self.move_dest) |p| gpa.free(p);
        self.st_fields.deinit(gpa);
        self.st_orig.deinit(gpa);
        if (self.confirm_msg) |c| gpa.free(c);
        if (self.shell_exe.len > 0) gpa.free(self.shell_exe);
        self.sql_log.deinit(gpa);
        if (self.sql_db) |d| gpa.free(d);
        for ([_]*TextInput{ &self.sq_edit, &self.tbl_edit, &self.wiz_name, &self.st_edit, &self.sql_in, &self.reg_addr, &self.reg_port, &self.files_in, &self.find_in, &self.replace_in, &self.console_in, &self.goto_in, &self.saveas_in, &self.project_in }) |ti| ti.deinit();
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
        if (self.work_dir) |c| gpa.free(c);
        if (self.dbg_path) |c| gpa.free(c);
        if (self.dbg_path) |c| gpa.free(c);
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

    // Zig tip: The real path of a folder (no `..`, the true letters of every name) is the key of the
    // session: two ways of writing the same folder give the same text.
    fn realPathOf(gpa: std.mem.Allocator, io: Io, path: []const u8) ![]u8 {
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        var dir = try Io.Dir.cwd().openDir(io, path, .{});
        defer dir.close(io);
        const n = try dir.realPath(io, &buf);
        return gpa.dupe(u8, buf[0..n]);
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
    // Zig tip: a message for the person (the bar at the bottom) and a record for later (the Stderr tab) are made together,
    // so an error is never only on the screen for a moment. The text may hold several lines: each is one line of the log.
    /// Report an error: the last line in the message bar and every line in the Stderr tab.
    pub fn logError(self: *App, text_in: []const u8) void {
        var last: []const u8 = "";
        var it = std.mem.splitScalar(u8, text_in, '\n');
        while (it.next()) |l| {
            if (l.len == 0) continue;
            self.stderr_log.add(self.gpa, l, .err) catch {};
            last = l;
        }
        if (last.len > 0) self.setMessage("{s}", .{last});
    }

    /// A key that is a shortcut (Ctrl or Alt) and that nothing uses: say so, and record it.
    pub fn unknownShortcut(self: *App, key: Key) void {
        if (key.codepoint == Key.left_control or key.codepoint == Key.right_control or key.codepoint == Key.left_shift or key.codepoint == Key.right_shift) return;
        var name_buf: [32]u8 = undefined;
        const base: []const u8 = switch (key.codepoint) {
            ' ' => "Space",
            Key.enter => "Enter",
            Key.tab => "Tab",
            Key.escape => "Esc",
            Key.backspace => "Backspace",
            else => if (key.codepoint < 128 and key.codepoint > 32) std.fmt.bufPrint(&name_buf, "{c}", .{std.ascii.toUpper(@intCast(key.codepoint))}) catch "?" else "?",
        };
        var msg_buf: [96]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "unknown shortcut: {s}{s}{s}{s}", .{
            if (key.mods.ctrl) "Ctrl+" else "",
            if (key.mods.alt) "Alt+" else "",
            if (key.mods.shift) "Shift+" else "",
            base,
        }) catch return;
        self.logError(msg);
    }

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
        if (std.mem.indexOfScalar(u8, rel, '#')) |h| return self.openSqliteTable(rel[0..h], rel[h + 1 ..]);
        for (self.tabs.items, 0..) |t, i| {
            if (std.mem.eql(u8, t.path, rel)) {
                self.active = i;
                self.focus = if (t.buf != null or t.table != null) .editor else .tree;
                return;
            }
        }
        var tab: Tab = .{ .path = try self.gpa.dupe(u8, rel) };
        errdefer self.gpa.free(tab.path);
        tab.eve = std.ascii.eqlIgnoreCase(extensionOf(rel), "eve");
        tab.sql = std.ascii.eqlIgnoreCase(extensionOf(rel), "sql");
        const full = try self.fullPath(rel);
        defer self.gpa.free(full);

        const size: u64 = if (Io.Dir.cwd().statFile(self.io, full, .{})) |st| st.size else |_| 0;
        if (std.ascii.eqlIgnoreCase(extensionOf(rel), "dbf")) {
            // a DBF table is read whole and shown as a grid
            if (Io.Dir.cwd().readFileAlloc(self.io, full, self.gpa, .limited(256 << 20))) |bytes| {
                if (dbf.Table.load(self.gpa, bytes)) |table| {
                    const tv = try self.gpa.create(TableView);
                    tv.* = .{ .t = table };
                    tab.table = tv;
                } else |err| {
                    self.gpa.free(bytes);
                    tab.card = .{ .kind = "DBF file", .size = size, .note = @errorName(err) };
                }
            } else |err| {
                tab.card = .{ .kind = "DBF file", .size = size, .note = @errorName(err) };
            }
        } else if (cardLabel(rel)) |label| {
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
        self.focus = if (tab.buf != null or tab.table != null) .editor else .tree;
        self.saveSession() catch {};
    }

    // Zig tip: `orderedRemove(i)` takes element `i` out of the list, keeps the order of the others and
    // returns the element, which we own and free. A `var` is needed because we call methods that
    // change it.
    pub fn closeTab(self: *App, index: usize) void {
        if (index >= self.tabs.items.len) return;
        var t = self.tabs.orderedRemove(index);
        if (t.buf) |*b| b.deinit();
        if (t.table) |tv| {
            tv.t.deinit();
            self.gpa.destroy(tv);
        }
        if (t.folder) |fv| self.freeFolder(fv);
        if (t.label.len > 0) self.gpa.free(t.label);
        self.gpa.free(t.path);
        if (self.active >= self.tabs.items.len and self.tabs.items.len > 0) self.active = self.tabs.items.len - 1;
        if (self.tabs.items.len == 0) self.active = 0;
        self.saveSession() catch {};
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
        if (rel.len > 0 and std.ascii.eqlIgnoreCase(extensionOf(rel), "dbf")) return self.createDbf(rel);
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
            t.sql = std.ascii.eqlIgnoreCase(extensionOf(rel), "sql");
        }
        self.setMessage("saved {s}", .{rel});
    }

    // ------------------------------------------------------------ the list of a folder

    fn freeFolder(self: *App, fv: *FolderView) void {
        for (fv.items.items) |it| self.gpa.free(it.name);
        fv.items.deinit(self.gpa);
        self.gpa.free(fv.dir);
        self.gpa.destroy(fv);
    }

    // Zig tip: each name is copied (`dupe`) because the iterator reuses its buffer; the size and the creation time come from
    // `statFile` on the entry. The list is sorted with the folders first, then by name, and a `..` row is put first when the
    // folder is not the project folder, so the list can go up as well as down.
    /// Read the content of folder `dir_rel` (a path in the project, "" for the project folder) into a new list.
    fn loadFolder(self: *App, dir_rel: []const u8) !*FolderView {
        const gpa = self.gpa;
        const fv = try gpa.create(FolderView);
        errdefer gpa.destroy(fv);
        fv.* = .{ .dir = try gpa.dupe(u8, dir_rel) };
        errdefer self.freeFolderItems(fv);
        const full = if (dir_rel.len == 0) try gpa.dupe(u8, if (self.root.len == 0) "." else self.root) else try self.fullPath(dir_rel);
        defer gpa.free(full);
        var dir = try Io.Dir.cwd().openDir(self.io, full, .{ .iterate = true });
        defer dir.close(self.io);
        var it = dir.iterate();
        while (try it.next(self.io)) |e| {
            const is_dir = e.kind == .directory;
            if (!is_dir and e.kind != .file) continue;
            const st = dir.statFile(self.io, e.name, .{}) catch null;
            const name = try gpa.dupe(u8, e.name);
            errdefer gpa.free(name);
            try fv.items.append(gpa, .{ .name = name, .is_dir = is_dir, .size = if (st) |s| s.size else 0, .created = if (st) |s| s.ctime.toSeconds() else 0 });
        }
        std.mem.sort(FolderItem, fv.items.items, {}, struct {
            fn less(_: void, x: FolderItem, y: FolderItem) bool {
                if (x.is_dir != y.is_dir) return x.is_dir;
                return std.ascii.lessThanIgnoreCase(x.name, y.name);
            }
        }.less);
        if (dir_rel.len > 0) try fv.items.insert(gpa, 0, .{ .name = try gpa.dupe(u8, ".."), .is_dir = true, .size = 0, .created = 0 });
        return fv;
    }

    fn freeFolderItems(self: *App, fv: *FolderView) void {
        for (fv.items.items) |it| self.gpa.free(it.name);
        fv.items.deinit(self.gpa);
        self.gpa.free(fv.dir);
    }

    /// A folder was clicked in the tree: the Main Panel shows its content (in the one tab that holds a folder).
    pub fn showFolder(self: *App, dir_rel: []const u8) !void {
        const gpa = self.gpa;
        const fv = try self.loadFolder(dir_rel);
        errdefer self.freeFolder(fv);
        const shown: []const u8 = if (dir_rel.len == 0) (if (self.project_name.len > 0) self.project_name else "project") else std.fs.path.basename(dir_rel);
        const label = try gpa.dupe(u8, shown);
        errdefer gpa.free(label);
        for (self.tabs.items, 0..) |*t, i| {
            if (t.folder) |old| {
                self.freeFolder(old);
                t.folder = fv;
                if (t.label.len > 0) gpa.free(t.label);
                t.label = label;
                gpa.free(t.path);
                t.path = try gpa.dupe(u8, dir_rel);
                self.active = i;
                return;
            }
        }
        try self.tabs.append(gpa, .{ .path = try gpa.dupe(u8, dir_rel), .folder = fv, .label = label });
        self.active = self.tabs.items.len - 1;
    }

    /// The path in the project of an item of a folder list.
    fn folderItemPath(self: *App, fv: *const FolderView, i: usize) ![]u8 {
        const name = fv.items.items[i].name;
        if (fv.dir.len == 0) return self.gpa.dupe(u8, name);
        return std.fmt.allocPrint(self.gpa, "{s}/{s}", .{ fv.dir, name });
    }

    /// Enter or a second click on a row: a folder is shown, a file is opened.
    fn openFolderItem(self: *App, fv: *FolderView, i: usize) !void {
        if (i >= fv.items.items.len) return;
        const it = fv.items.items[i];
        if (it.is_dir and std.mem.eql(u8, it.name, "..")) {
            const dir_copy = try self.gpa.dupe(u8, std.fs.path.dirname(fv.dir) orelse "");
            defer self.gpa.free(dir_copy);
            return self.showFolder(dir_copy);
        }
        const rel = try self.folderItemPath(fv, i);
        defer self.gpa.free(rel);
        if (it.is_dir) return self.showFolder(rel);
        try self.openFile(rel);
    }

    fn folderListKey(self: *App, fv: *FolderView, key: Key) !void {
        const n = fv.items.items.len;
        if (n == 0) return;
        if (key.matches(Key.up, .{})) fv.sel = fv.sel -| 1 else if (key.matches(Key.down, .{})) fv.sel = @min(fv.sel + 1, n - 1) else if (key.matches(Key.page_up, .{})) fv.sel = fv.sel -| 10 else if (key.matches(Key.page_down, .{})) fv.sel = @min(fv.sel + 10, n - 1) else if (key.matches(Key.home, .{})) fv.sel = 0 else if (key.matches(Key.end, .{})) fv.sel = n - 1 else if (key.matches(Key.enter, .{})) try self.openFolderItem(fv, fv.sel) else if (key.matches(Key.backspace, .{}) and fv.dir.len > 0) {
            const up = try self.gpa.dupe(u8, std.fs.path.dirname(fv.dir) orelse "");
            defer self.gpa.free(up);
            try self.showFolder(up);
        }
    }

    // Zig tip: the file that is selected in the list of a folder has the same buttons as an open file: Run when it is an Eve
    // file, Preview when it is Markdown. When the button is used, the file is opened first (`adoptFolderSelection`), so the
    // rest of the code finds an ordinary open tab.
    /// The file selected in the folder list of the active tab (its path in the project, copied), or null.
    fn folderSelectedFile(self: *App) ?[]u8 {
        const t = self.activeTab() orelse return null;
        const fv = t.folder orelse return null;
        if (fv.sel >= fv.items.items.len or fv.items.items[fv.sel].is_dir) return null;
        return self.folderItemPath(fv, fv.sel) catch null;
    }

    /// Open the file that is selected in a folder list, if the active tab is a folder list and a file is selected.
    fn adoptFolderSelection(self: *App) !void {
        const rel = self.folderSelectedFile() orelse return;
        defer self.gpa.free(rel);
        try self.openFile(rel);
    }

    /// Can Run work now? (An Eve file is open, or selected in a folder list.)
    pub fn canRun(self: *App) bool {
        if (self.folderSelectedFile()) |rel| {
            defer self.gpa.free(rel);
            return std.ascii.eqlIgnoreCase(extensionOf(rel), "eve");
        }
        const t = self.activeTab() orelse return false;
        return t.eve and t.buf != null;
    }

    // ------------------------------------------------------------ SQLite databases in the tree

    // Zig tip: `std.process.run` runs `eve db sql ...` and returns what it printed; the caller frees the text. A failure to
    // start the program is an error; an error of SQL is a text that begins with `error:`, which the callers look for.
    /// Run `eve <args>` and give back its output (the caller frees it).
    fn eveText(self: *App, args: []const []const u8) ![]u8 {
        const gpa = self.gpa;
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(gpa);
        try argv.append(gpa, eve_exe);
        try argv.appendSlice(gpa, args);
        const cwd: std.process.Child.Cwd = if (self.root.len == 0 or std.mem.eql(u8, self.root, ".")) .inherit else .{ .path = self.root };
        const result = try std.process.run(gpa, self.io, .{ .argv = argv.items, .cwd = cwd });
        defer gpa.free(result.stderr);
        return result.stdout;
    }

    /// The tables and views of a database entry of the tree are listed (with `eve db sql`) and put under it.
    fn loadDbTables(self: *App, index: u32) !void {
        const gpa = self.gpa;
        const db_rel = try gpa.dupe(u8, self.tree.entries.items[index].path);
        defer gpa.free(db_rel);
        const out = self.eveText(&.{ "db", "sql", "-t", db_rel, "select name from sqlite_master where type in ('table','view') and name not like 'sqlite_%' order by name;" }) catch |err| {
            self.setMessage("cannot read {s}: {s}", .{ db_rel, @errorName(err) });
            return;
        };
        defer gpa.free(out);
        if (std.mem.startsWith(u8, out, "error:")) {
            self.setMessage("{s}: {s}", .{ db_rel, std.mem.trim(u8, out, " \r\n") });
            return;
        }
        var names: std.ArrayList([]const u8) = .empty;
        defer names.deinit(gpa);
        var lines = std.mem.splitScalar(u8, out, '\n');
        _ = lines.next(); // the header
        while (lines.next()) |raw| {
            const n = std.mem.trim(u8, raw, " \r");
            if (n.len > 0) try names.append(gpa, n);
        }
        const delta = try self.tree.setTables(index, names.items);
        if (self.selected > index and delta != 0) self.selected = @intCast(@as(isize, @intCast(self.selected)) + delta);
        if (names.items.len == 0) self.setMessage("{s} has no tables", .{db_rel});
    }

    // Zig tip: a table of a database is a tab like a file, whose path is `db#table`. Its rows come from one `select`, as text
    // with tabs, and become a `dbf.Table` in memory (every column a Character field), so the grid of the Main Panel
    // draws them. `readonly` keeps the DATA commands from changing it. At most 5000 rows are read.
    /// Open the table `table` of the SQLite file `db_rel` in the Main Panel.
    fn openSqliteTable(self: *App, db_rel: []const u8, table: []const u8) !void {
        const gpa = self.gpa;
        const key = try std.fmt.allocPrint(gpa, "{s}#{s}", .{ db_rel, table });
        errdefer gpa.free(key);
        for (self.tabs.items, 0..) |t, i| {
            if (std.mem.eql(u8, t.path, key)) {
                self.active = i;
                self.focus = .editor;
                gpa.free(key);
                return;
            }
        }
        const sql = try std.fmt.allocPrint(gpa, "select * from \"{s}\" limit 5000;", .{table});
        defer gpa.free(sql);
        const out = try self.eveText(&.{ "db", "sql", "-t", db_rel, sql });
        defer gpa.free(out);
        if (std.mem.startsWith(u8, out, "error:")) {
            self.setMessage("{s}: {s}", .{ key, std.mem.trim(u8, out, " \r\n") });
            gpa.free(key);
            return;
        }
        var t = try dbf.fromTsv(gpa, out, self.dbfDate());
        errdefer t.deinit();
        const tv = try gpa.create(TableView);
        errdefer gpa.destroy(tv);
        tv.* = .{ .t = t, .readonly = true };
        const label = try std.fmt.allocPrint(gpa, "{s}.{s}", .{ std.fs.path.stem(db_rel), table });
        errdefer gpa.free(label);
        try self.tabs.append(gpa, .{ .path = key, .table = tv, .label = label });
        self.active = self.tabs.items.len - 1;
        self.focus = .editor;
    }

    // ------------------------------------------------------------ new files and wizards

    // Zig tip: the entry that is selected in the tree decides where a new file goes: a folder is the place itself, a file
    // means the folder that holds it. The answer is a slice of the path inside the tree (valid until the tree is scanned
    // again), "" for the project folder. `std.fs.path.dirname` returns null for a name with no folder.
    /// The folder of the project where a new file goes: the selected folder, or the folder of the selected file.
    pub fn targetDir(self: *const App) []const u8 {
        if (self.selected >= self.tree.entries.items.len) return "";
        const e = self.tree.entries.items[self.selected];
        if (e.is_dir) return e.path;
        return std.fs.path.dirname(e.path) orelse "";
    }

    /// File > New…: ask for the name of the file; the type is read from its extension.
    pub fn openNewDialog(self: *App) void {
        self.saveas_in.clearRetainingCapacity();
        self.openOverlay(.new_file);
    }

    /// The path in the project of a file `name` made in the target folder.
    fn pathInTarget(self: *App, name: []const u8) ![]u8 {
        const dir = self.targetDir();
        if (dir.len == 0) return self.gpa.dupe(u8, name);
        return std.fmt.allocPrint(self.gpa, "{s}/{s}", .{ dir, name });
    }

    // Zig tip: the machine reads the type from the extension and starts the wizard of that type: a DBF table asks for its
    // fields (the structure dialog), an Eve file and an SQL file ask what to start from, a SQLite file is just made, and any
    // other file starts empty (a few types start with one line). `switch` on the lower-cased extension picks the way.
    /// The name was typed in the New dialog: make the file in the target folder, with the wizard of its type.
    fn newFromName(self: *App) !void {
        const raw = try self.saveas_in.toOwnedContents(self.gpa);
        defer self.gpa.free(raw);
        const name = std.mem.trim(u8, raw, " /\\");
        if (name.len == 0) return;
        self.overlay = .none;
        const rel = try self.pathInTarget(name);
        defer self.gpa.free(rel);
        const full = try self.fullPath(rel);
        defer self.gpa.free(full);
        if (Io.Dir.cwd().statFile(self.io, full, .{})) |_| {
            self.setMessage("{s} exists already", .{rel});
            return;
        } else |_| {}
        var ext_buf: [16]u8 = undefined;
        const ext = std.ascii.lowerString(&ext_buf, extensionOf(rel)[0..@min(extensionOf(rel).len, ext_buf.len)]);
        if (std.mem.eql(u8, ext, "dbf")) return self.createDbf(rel);
        if (std.mem.eql(u8, ext, "eve")) return self.openWizard(.eve, rel);
        if (std.mem.eql(u8, ext, "sql")) return self.openWizard(.sql, rel);
        if (std.mem.eql(u8, ext, "db") or std.mem.eql(u8, ext, "sqlite") or std.mem.eql(u8, ext, "sqlite3")) return self.createSqlite(rel, full);
        const stem = std.fs.path.stem(rel);
        const body = if (std.mem.eql(u8, ext, "md")) try std.fmt.allocPrint(self.gpa, "# {s}\n", .{stem}) else if (std.mem.eql(u8, ext, "json")) try self.gpa.dupe(u8, "{}\n") else try self.gpa.dupe(u8, "");
        defer self.gpa.free(body);
        try self.writeNew(rel, full, body);
    }

    /// Write a new text file, show it in the tree and open it.
    fn writeNew(self: *App, rel: []const u8, full: []const u8, body: []const u8) !void {
        Io.Dir.cwd().writeFile(self.io, .{ .sub_path = full, .data = body }) catch |err| {
            self.setMessage("cannot make {s}: {s}", .{ rel, @errorName(err) });
            return;
        };
        self.refreshTree();
        try self.openFile(rel);
        self.setMessage("made {s}", .{rel});
    }

    /// A new SQLite database: `eve db sql` opens the file and writes its header.
    fn createSqlite(self: *App, rel: []const u8, full: []const u8) !void {
        const argv = [_][]const u8{ eve_exe, "db", "sql", full, "pragma user_version = 1;" };
        const result = std.process.run(self.gpa, self.io, .{ .argv = &argv }) catch |err| {
            self.setMessage("cannot make {s}: {s}", .{ rel, @errorName(err) });
            return;
        };
        defer self.gpa.free(result.stdout);
        defer self.gpa.free(result.stderr);
        self.refreshTree();
        try self.openFile(rel);
        self.setMessage("made the SQLite database {s}", .{rel});
    }

    fn openWizard(self: *App, kind: WizKind, rel: []const u8) !void {
        if (self.wiz_path) |old| self.gpa.free(old);
        self.wiz_path = try self.gpa.dupe(u8, rel);
        self.wiz_kind = kind;
        self.wiz_choice = 0;
        self.wiz_name.clearRetainingCapacity();
        try self.wiz_name.insertSliceAtCursor(std.fs.path.stem(rel));
        self.openOverlay(.wizard);
    }

    /// The choices of the wizard of a kind of file, as the list shows them.
    pub fn wizardChoices(kind: WizKind) []const []const u8 {
        return switch (kind) {
            .eve => &.{ "Primary aspect: a program with a main process", "Aspect: called with `apply`, takes arguments", "Module: functions and procedures to import" },
            .sql => &.{ "Empty script", "Create table", "Select", "Insert" },
        };
    }

    fn wizardKey(self: *App, key: Key) !void {
        const n = wizardChoices(self.wiz_kind).len;
        if (key.matches(Key.up, .{})) {
            self.wiz_choice = (self.wiz_choice + n - 1) % n;
        } else if (key.matches(Key.down, .{})) {
            self.wiz_choice = (self.wiz_choice + 1) % n;
        } else if (key.matches(Key.enter, .{})) {
            try self.wizardCreate();
        } else try self.wiz_name.update(.{ .key_press = key });
    }

    // Zig tip: the templates are format strings; `{{` and `}}` write a brace, because Eve's own `"{name}"` uses braces.
    // Each template is a complete, valid file of its kind, so the new file runs (or imports) at once.
    /// Create the file of the wizard with the text of the choice made.
    fn wizardCreate(self: *App) !void {
        const rel = self.wiz_path orelse return;
        const raw = try self.wiz_name.toOwnedContents(self.gpa);
        defer self.gpa.free(raw);
        var name = std.mem.trim(u8, raw, " ");
        if (name.len == 0) name = std.fs.path.stem(rel);
        const gpa = self.gpa;
        const body = switch (self.wiz_kind) {
            .eve => switch (self.wiz_choice) {
                0 => try std.fmt.allocPrint(gpa, "# {s}: a program\nprimary aspect {s} is\n  process main is\n    print \"Hello from {s}\";\n  return;\nend {s};\n", .{ name, name, name, name }),
                1 => try std.fmt.allocPrint(gpa, "# {s}: an aspect, called with: apply {s}(\"Eve\");\nexclusive aspect {s} is\n  process main(who: String) is\n    print \"Hello, {{who}}!\";\n  return;\nend {s};\n", .{ name, name, name, name }),
                else => try std.fmt.allocPrint(gpa, "# {s}: a module, imported with: from lib use ({s});\nmodule {s} is\n  export (hello);\n\n  procedure hello() is\n    print \"Hello from {s}\";\n  return;\nend {s};\n", .{ name, name, name, name, name }),
            },
            .sql => switch (self.wiz_choice) {
                0 => try std.fmt.allocPrint(gpa, "-- {s}\n", .{name}),
                1 => try std.fmt.allocPrint(gpa, "-- {s}\ncreate table {s} (\n  id integer primary key,\n  name text not null\n);\n", .{ name, name }),
                2 => try std.fmt.allocPrint(gpa, "-- {s}\nselect *\nfrom {s}\nwhere 1 = 1\norder by 1;\n", .{ name, name }),
                else => try std.fmt.allocPrint(gpa, "-- {s}\ninsert into {s} (id, name)\nvalues (1, 'first');\n", .{ name, name }),
            },
        };
        defer gpa.free(body);
        const full = try self.fullPath(rel);
        defer gpa.free(full);
        self.overlay = .none;
        const path = try gpa.dupe(u8, rel);
        defer gpa.free(path);
        try self.writeNew(path, full, body);
    }

    // ------------------------------------------------------------ the rendered Markdown page

    fn isMarkdown(path: []const u8) bool {
        const ext = extensionOf(path);
        return std.ascii.eqlIgnoreCase(ext, "md") or std.ascii.eqlIgnoreCase(ext, "markdown");
    }

    /// Can the active tab be shown rendered? (A Markdown file with a text buffer.)
    pub fn canRender(self: *App) bool {
        if (self.folderSelectedFile()) |rel| {
            defer self.gpa.free(rel);
            return isMarkdown(rel);
        }
        const t = self.activeTab() orelse return false;
        return t.buf != null and isMarkdown(t.path);
    }

    /// Is the active tab shown rendered, so the page goes full screen?
    pub fn mdFull(self: *App) bool {
        const t = self.activeTab() orelse return false;
        return t.render and t.buf != null;
    }

    // Zig tip: the View button switches the tab between the editor and the page; the page is drawn from the same text
    // buffer on every frame, so a change made in the editor shows at once. The layout follows (`computeLayout`): while the
    // page is shown the Tools Panel is out of the way and the Main Panel reaches the bottom bar.
    /// The View button: show the Markdown file rendered, or go back to the editor.
    pub fn toggleView(self: *App) void {
        if (self.canRender()) self.adoptFolderSelection() catch {};
        const t = self.activeTab() orelse return;
        if (!self.canRender()) {
            self.setMessage("View works on a Markdown file (.md)", .{});
            return;
        }
        t.render = !t.render;
        t.render_top = 0;
        self.focus = .editor;
    }

    /// The keys of a rendered page: arrows and pages scroll, Esc or V go back to the editor.
    fn mdKey(self: *App, t: *Tab, key: Key) void {
        const page: usize = @max(1, self.editor_rect.h -| 1);
        if (key.matches(Key.escape, .{}) or key.matches('v', .{})) {
            t.render = false;
        } else if (key.matches(Key.up, .{})) {
            t.render_top -|= 1;
        } else if (key.matches(Key.down, .{})) {
            t.render_top += 1;
        } else if (key.matches(Key.page_up, .{})) {
            t.render_top -|= page;
        } else if (key.matches(Key.page_down, .{}) or key.matches(Key.space, .{})) {
            t.render_top += page;
        } else if (key.matches(Key.home, .{})) {
            t.render_top = 0;
        } else if (key.matches(Key.end, .{})) {
            t.render_top = std.math.maxInt(u32);
        }
    }

    fn readonlyMessage(self: *App) void {
        self.setMessage("this table is read only here: change it with SQL or its structure", .{});
    }

    /// DATA > Structure…: the dialog of the fields of the table that is open.
    pub fn dataStructure(self: *App) !void {
        const t = self.activeTab() orelse return;
        if (t.table == null) {
            self.setMessage("Structure works on a DBF table: open one", .{});
            return;
        }
        if (std.mem.indexOfScalar(u8, t.path, '#')) |h| return self.openSqStructure(t.path[0..h], t.path[h + 1 ..]);
        try self.openStructure(t.path);
    }

    // ------------------------------------------------------------ the DATA menu

    /// The table of the active tab, when it is a DBF table.
    fn activeTable(self: *App) ?*TableView {
        const t = self.activeTab() orelse return null;
        return t.table;
    }

    /// Write the table of the active tab to its file (every change of the data is saved at once).
    fn saveTable(self: *App) void {
        const t = self.activeTab() orelse return;
        const tv = t.table orelse return;
        const full = self.fullPath(t.path) catch return;
        defer self.gpa.free(full);
        Io.Dir.cwd().writeFile(self.io, .{ .sub_path = full, .data = tv.t.fileBytes() }) catch |err| {
            self.setMessage("cannot save {s}: {s}", .{ t.path, @errorName(err) });
        };
    }

    // Zig tip: Ctrl+Space is one shortcut with two meanings, chosen by what is open: a table gets a blank record at its end,
    // a text file gets a new empty line at its end and the cursor there. A file that is not text says why nothing happened.
    /// Ctrl+Space: append a new row at the end of the table, or a new empty line at the end of the file.
    pub fn appendAtEnd(self: *App) !void {
        const t = self.activeTab() orelse {
            self.setMessage("Ctrl+Space appends a row: open a table or a file first", .{});
            return;
        };
        if (t.table) |tv| {
            if (tv.readonly) return self.readonlyMessage();
            return self.dataAppend(1);
        }
        if (t.buf) |*b| {
            if (t.virtual or t.render) {
                self.setMessage("this window is read only", .{});
                return;
            }
            try b.checkpoint(.other);
            b.gotoLine(b.lineCount(), 0);
            b.toEnd();
            if (b.lineAt(b.row).len > 0) try b.insertText("\n");
            self.focus = .editor;
            self.follow = true;
            return;
        }
        self.setMessage("nothing to append to in this window", .{});
    }

    /// DATA > Append row(s): blank records at the end of the table; the last one is selected.
    pub fn dataAppend(self: *App, n: u32) !void {
        const tv = self.activeTable() orelse {
            self.setMessage("DATA works on a DBF table: open one", .{});
            return;
        };
        if (tv.readonly) return self.readonlyMessage();
        if (tv.t.fields.len == 0) {
            self.setMessage("the table has no fields yet: SQL:> alter table <name>", .{});
            return;
        }
        try tv.t.appendRecords(n);
        tv.row = tv.t.records - 1;
        self.saveTable();
        self.setMessage("{d} row(s) appended: {d} records", .{ n, tv.t.records });
    }

    /// DATA > Append rows…: ask how many.
    pub fn openAppendN(self: *App) void {
        if (self.activeTable() == null) {
            self.setMessage("DATA works on a DBF table: open one", .{});
            return;
        }
        self.goto_in.clearRetainingCapacity();
        self.openOverlay(.append_n);
    }

    fn appendNEnter(self: *App) !void {
        const raw = try self.goto_in.toOwnedContents(self.gpa);
        defer self.gpa.free(raw);
        const n = std.fmt.parseInt(u32, std.mem.trim(u8, raw, " "), 10) catch 0;
        if (n == 0 or n > 100000) {
            self.setMessage("a number of rows from 1 to 100000", .{});
            return;
        }
        self.overlay = .none;
        try self.dataAppend(n);
    }

    /// DATA > Delete / recall row: mark the selected record deleted, or take the mark away.
    pub fn dataDelete(self: *App) !void {
        const tv = self.activeTable() orelse {
            self.setMessage("DATA works on a DBF table: open one", .{});
            return;
        };
        if (tv.readonly) return self.readonlyMessage();
        if (tv.row >= tv.t.records) return;
        tv.t.toggleDeleted(tv.row);
        self.saveTable();
        self.setMessage("record {d} {s}", .{ tv.row + 1, if (tv.t.deleted(tv.row)) "marked deleted" else "recalled" });
    }

    /// DATA > Edit cell: the selected cell becomes a text field with its value.
    pub fn dataEdit(self: *App) void {
        const tv = self.activeTable() orelse {
            self.setMessage("DATA works on a DBF table: open one", .{});
            return;
        };
        if (tv.readonly) return self.readonlyMessage();
        if (tv.row >= tv.t.records or tv.col >= tv.t.fields.len) return;
        var buf: [16]u8 = undefined;
        self.tbl_edit.clearRetainingCapacity();
        self.tbl_edit.insertSliceAtCursor(tv.t.display(tv.row, tv.col, &buf)) catch return;
        self.tbl_editing = true;
        self.focus = .editor;
    }

    fn commitCell(self: *App, tv: *TableView) !void {
        const raw = try self.tbl_edit.toOwnedContents(self.gpa);
        defer self.gpa.free(raw);
        tv.t.setCell(tv.row, tv.col, std.mem.trim(u8, raw, " "));
        self.tbl_editing = false;
        self.saveTable();
    }

    // ------------------------------------------------------------ the structure of a SQLite table

    // Zig tip: the columns come from `pragma table_info` (read with `eve db sql -t`) and are parsed by `sqlstruct`. They are
    // copied into two lists: one the person edits and one to compare with, so the dialog can count the changes.
    /// SQL:> alter table <name>, or DATA > Structure on a table of a database: open the dialog of its columns.
    fn openSqStructure(self: *App, db_rel: []const u8, table: []const u8) !void {
        const gpa = self.gpa;
        const sql = try std.fmt.allocPrint(gpa, "pragma table_info(\"{s}\");", .{table});
        defer gpa.free(sql);
        const out = try self.eveText(&.{ "db", "sql", "-t", db_rel, sql });
        defer gpa.free(out);
        self.sq_cols.clearRetainingCapacity();
        self.sq_orig.clearRetainingCapacity();
        sqlstruct.parseTableInfo(gpa, out, &self.sq_cols) catch {};
        if (self.sq_cols.items.len == 0) {
            const msg = try std.fmt.allocPrint(gpa, "alter table: there is no table {s} in {s}", .{ table, db_rel });
            defer gpa.free(msg);
            try self.sql_log.add(gpa, msg, .err);
            return;
        }
        try self.sq_orig.appendSlice(gpa, self.sq_cols.items);
        if (self.sq_db) |old| gpa.free(old);
        if (self.sq_table) |old| gpa.free(old);
        self.sq_db = try gpa.dupe(u8, db_rel);
        self.sq_table = try gpa.dupe(u8, table);
        self.sq_row = 0;
        self.sq_col = 0;
        self.sq_editing = false;
        self.sq_drop = false;
        self.sq_error = null;
        self.sq_new = false;
        self.openOverlay(.sq_structure);
    }

    // Zig tip: a new table starts with one column, `id INTEGER` as the key, so the dialog is not empty; the rest of the
    // dialog is the same as for an old table. With nothing to compare with (`sq_orig` empty), every column counts as a change.
    /// The dialog of a new SQLite table `name` in the file `db_rel`.
    fn openSqStructureNew(self: *App, db_rel: []const u8, name: []const u8) !void {
        const gpa = self.gpa;
        self.sq_cols.clearRetainingCapacity();
        self.sq_orig.clearRetainingCapacity();
        var c: sqlstruct.Col = .{ .pk = true, .notnull = true };
        c.setName("id");
        c.setType("INTEGER");
        try self.sq_cols.append(gpa, c);
        if (self.sq_db) |old| gpa.free(old);
        if (self.sq_table) |old| gpa.free(old);
        self.sq_db = try gpa.dupe(u8, db_rel);
        self.sq_table = try gpa.dupe(u8, name);
        self.sq_row = 0;
        self.sq_col = 0;
        self.sq_editing = false;
        self.sq_drop = false;
        self.sq_error = null;
        self.sq_new = true;
        self.openOverlay(.sq_structure);
    }

    pub fn sqChanges(self: *const App) usize {
        var n: usize = 0;
        for (self.sq_cols.items, 0..) |c, i| {
            const same = i < self.sq_orig.items.len and c.src == self.sq_orig.items[i].src and std.meta.eql(c, self.sq_orig.items[i]);
            if (!same) n += 1;
        }
        if (self.sq_orig.items.len > self.sq_cols.items.len) n += self.sq_orig.items.len - self.sq_cols.items.len;
        return n;
    }

    fn sqAdd(self: *App) !void {
        var c: sqlstruct.Col = .{};
        var n: usize = self.sq_cols.items.len + 1;
        var nb: [24]u8 = undefined;
        while (true) : (n += 1) {
            const name = std.fmt.bufPrint(&nb, "column{d}", .{n}) catch "column";
            var used = false;
            for (self.sq_cols.items) |o| {
                if (std.ascii.eqlIgnoreCase(o.nameS(), name)) used = true;
            }
            if (!used) {
                c.setName(name);
                break;
            }
        }
        c.setType("TEXT");
        const at = self.sq_row + 1;
        try self.sq_cols.insert(self.gpa, at, c);
        self.sq_row = at;
        self.sq_col = 0;
    }

    fn sqRemove(self: *App) void {
        if (self.sq_cols.items.len <= 1) {
            self.sq_error = "a table needs at least one column";
            return;
        }
        _ = self.sq_cols.orderedRemove(self.sq_row);
        self.sq_row = @min(self.sq_row, self.sq_cols.items.len - 1);
    }

    fn sqMove(self: *App, delta: isize) void {
        const to_i: isize = @as(isize, @intCast(self.sq_row)) + delta;
        if (to_i < 0 or to_i >= self.sq_cols.items.len) return;
        const to: usize = @intCast(to_i);
        std.mem.swap(sqlstruct.Col, &self.sq_cols.items[self.sq_row], &self.sq_cols.items[to]);
        self.sq_row = to;
    }

    fn sqStartEdit(self: *App) !void {
        const c = &self.sq_cols.items[self.sq_row];
        self.sq_error = null;
        switch (self.sq_col) {
            1 => {
                self.sq_drop = true;
                self.sq_drop_sel = 0;
                for (sqlstruct.types, 0..) |t, i| {
                    if (std.ascii.eqlIgnoreCase(t, c.typeS())) self.sq_drop_sel = i;
                }
            },
            2 => c.notnull = !c.notnull,
            3 => c.pk = !c.pk,
            else => {
                self.sq_edit.clearRetainingCapacity();
                try self.sq_edit.insertSliceAtCursor(if (self.sq_col == 0) c.nameS() else c.defaultS());
                self.sq_editing = true;
            },
        }
    }

    fn sqCommit(self: *App) !void {
        const raw = try self.sq_edit.toOwnedContents(self.gpa);
        defer self.gpa.free(raw);
        const t = std.mem.trim(u8, raw, " ");
        const c = &self.sq_cols.items[self.sq_row];
        self.sq_editing = false;
        if (self.sq_col == 0) c.setName(t) else c.setDefault(t);
        self.sq_error = sqlstruct.check(c);
    }

    /// The keys of the structure dialog of a SQLite table.
    fn sqKey(self: *App, key: Key) !void {
        if (self.sq_editing) {
            if (key.matches(Key.enter, .{})) return self.sqCommit();
            try self.sq_edit.update(.{ .key_press = key });
            return;
        }
        const kn = sqlstruct.types.len;
        if (self.sq_drop) {
            if (key.matches(Key.up, .{})) self.sq_drop_sel = (self.sq_drop_sel + kn - 1) % kn else if (key.matches(Key.down, .{})) self.sq_drop_sel = (self.sq_drop_sel + 1) % kn else if (key.matches(Key.enter, .{})) {
                self.sq_cols.items[self.sq_row].setType(sqlstruct.types[self.sq_drop_sel]);
                self.sq_drop = false;
            }
            return;
        }
        const n = self.sq_cols.items.len;
        if (key.matches(Key.up, .{ .ctrl = true })) return self.sqMove(-1);
        if (key.matches(Key.down, .{ .ctrl = true })) return self.sqMove(1);
        if (key.matches(Key.up, .{})) self.sq_row = self.sq_row -| 1 else if (key.matches(Key.down, .{})) self.sq_row = @min(self.sq_row + 1, n - 1) else if (key.matches(Key.left, .{})) self.sq_col = self.sq_col -| 1 else if (key.matches(Key.right, .{}) or key.matches(Key.tab, .{})) self.sq_col = @min(self.sq_col + 1, 4) else if (key.matches(Key.page_up, .{})) self.sq_row = self.sq_row -| 10 else if (key.matches(Key.page_down, .{})) self.sq_row = @min(self.sq_row + 10, n - 1) else if (key.matches(Key.enter, .{}) or key.matches(Key.space, .{})) try self.sqStartEdit() else if (key.matches(Key.insert, .{})) try self.sqAdd() else if (key.matches(Key.delete, .{})) self.sqRemove() else if (key.matches('s', .{ .ctrl = true })) try self.sqApply();
    }

    // Zig tip: SQLite cannot change a column in place, so Apply rebuilds the table: a new table, the rows copied, the old
    // table dropped, the new one renamed. That loses the indexes and the triggers of the table, so the question is asked first
    // (the same Yes/No dialog) whenever something changes.
    /// The Apply button of the SQLite structure dialog: check the columns and ask before the table is rebuilt.
    fn sqApply(self: *App) !void {
        self.sq_error = null;
        const items = self.sq_cols.items;
        for (items, 0..) |c, i| {
            if (sqlstruct.check(&c)) |msg| {
                self.sq_error = msg;
                self.sq_row = i;
                return;
            }
            for (items[0..i]) |o| {
                if (std.ascii.eqlIgnoreCase(o.nameS(), c.nameS())) {
                    self.sq_error = "two columns have the same name";
                    self.sq_row = i;
                    return;
                }
            }
        }
        if (self.sqChanges() == 0) {
            self.sq_error = "nothing to apply";
            return;
        }
        if (self.sq_new) return self.sqApplyNow();
        self.askConfirm(.apply_sqlite, 0, "Rebuild table {s}? Its indexes and triggers are not kept.", .{self.sq_table orelse ""});
    }

    fn sqApplyNow(self: *App) !void {
        const gpa = self.gpa;
        const db = self.sq_db orelse return;
        const table = self.sq_table orelse return;
        const script = if (self.sq_new) try sqlstruct.buildCreate(gpa, table, self.sq_cols.items) else try sqlstruct.buildScript(gpa, table, self.sq_cols.items, self.sq_orig.items);
        defer gpa.free(script);
        const out = try self.eveText(&.{ "db", "sql", db, script });
        defer gpa.free(out);
        if (std.mem.indexOf(u8, out, "error:") != null) {
            self.sq_error = "SQLite refused the change (see the SQL panel)";
            try self.sql_log.addBlock(gpa, out, .err);
            self.openOverlay(.sq_structure);
            return;
        }
        self.overlay = .none;
        // the table is shown again with its new columns
        const key = try std.fmt.allocPrint(gpa, "{s}#{s}", .{ db, table });
        defer gpa.free(key);
        for (self.tabs.items, 0..) |t, i| {
            if (std.mem.eql(u8, t.path, key)) {
                self.closeTab(i);
                break;
            }
        }
        if (self.sq_new) try self.refreshDbTables(db);
        try self.openSqliteTable(db, table);
        const msg = try std.fmt.allocPrint(gpa, "{s}: {s}, {d} columns", .{ key, if (self.sq_new) "table created" else "structure changed", self.sq_cols.items.len });
        defer gpa.free(msg);
        try self.sql_log.add(gpa, msg, .info);
        self.setMessage("{s}", .{msg});
    }

    // ------------------------------------------------------------ create table and drop table

    // Zig tip: the tree is the place to read "what is selected": a database (or one of its tables) means SQLite, a folder (or a
    // file in a folder) means DBF. `?[]const u8` is the path of the database, or null when the selection is not a database.
    /// The SQLite file that is selected in the tree (the file itself, or the file of a table), or null.
    pub fn selectedDb(self: *const App) ?[]const u8 {
        if (self.selected >= self.tree.entries.items.len) return null;
        const e = self.tree.entries.items[self.selected];
        return switch (e.kind) {
            .db => e.path,
            .table => e.path[0 .. std.mem.indexOfScalar(u8, e.path, '#') orelse e.path.len],
            .normal => null,
        };
    }

    /// What a new table would be now, as a text for the dialog: the database or the folder it goes to.
    pub fn createTableTarget(self: *const App) []const u8 {
        if (self.selectedDb()) |db| return db;
        const dir = self.targetDir();
        return if (dir.len == 0) "the project folder" else dir;
    }

    /// EDIT > Create table…, or `create table` in the SQL panel: ask for the name.
    pub fn openCreateTable(self: *App) void {
        self.saveas_in.clearRetainingCapacity();
        self.openOverlay(.new_table);
    }

    /// Make the table `name`: a SQLite table when a database is selected, a DBF table when a folder is.
    fn createTableNamed(self: *App, name: []const u8) !void {
        const gpa = self.gpa;
        if (name.len == 0 or !(std.ascii.isAlphabetic(name[0]) or name[0] == '_')) {
            self.setMessage("a table name begins with a letter", .{});
            return;
        }
        for (name) |c| {
            if (!(std.ascii.isAlphanumeric(c) or c == '_')) {
                self.setMessage("a table name has letters, digits and _ only", .{});
                return;
            }
        }
        if (self.selectedDb()) |db| {
            const copy = try gpa.dupe(u8, db);
            defer gpa.free(copy);
            try self.openSqStructureNew(copy, name);
            return;
        }
        const dir = self.targetDir();
        const rel = if (dir.len == 0) try std.fmt.allocPrint(gpa, "{s}.dbf", .{name}) else try std.fmt.allocPrint(gpa, "{s}/{s}.dbf", .{ dir, name });
        defer gpa.free(rel);
        try self.createDbf(rel);
    }

    /// The tables of a database of the tree are read again (and the database is opened), after one was made or dropped.
    fn refreshDbTables(self: *App, db_rel: []const u8) !void {
        for (self.tree.entries.items, 0..) |*e, i| {
            if (e.kind == .db and std.mem.eql(u8, e.path, db_rel)) {
                e.expanded = true;
                try self.loadDbTables(@intCast(i));
                return;
            }
        }
    }

    // Zig tip: `drop table [name]` is understood here and not sent to the database: the table is found first (the one open or
    // selected, or the one named in the database that is selected, or a DBF file of the current folder), and then the same
    // Yes/No dialog as everywhere asks; only the Yes drops. What to drop is kept in `drop_a`, `drop_b` and `drop_is_dbf`.
    /// Ask whether to drop a table: the current one, or the one called `name`.
    pub fn dropTable(self: *App, name: []const u8) !void {
        const gpa = self.gpa;
        var db: ?[]const u8 = null;
        var table: []const u8 = name;
        var dbf_rel: ?[]u8 = null;
        defer if (dbf_rel) |p| gpa.free(p);
        if (name.len == 0) {
            if (self.activeTab()) |t| {
                if (t.table != null) {
                    if (std.mem.indexOfScalar(u8, t.path, '#')) |h| {
                        db = t.path[0..h];
                        table = t.path[h + 1 ..];
                    } else dbf_rel = try gpa.dupe(u8, t.path);
                }
            }
            if (db == null and dbf_rel == null and self.selected < self.tree.entries.items.len) {
                const e = self.tree.entries.items[self.selected];
                if (e.kind == .table) {
                    const h = std.mem.indexOfScalar(u8, e.path, '#') orelse 0;
                    db = e.path[0..h];
                    table = e.path[h + 1 ..];
                } else if (!e.is_dir and std.ascii.eqlIgnoreCase(extensionOf(e.path), "dbf")) dbf_rel = try gpa.dupe(u8, e.path);
            }
            if (db == null and dbf_rel == null) {
                self.setMessage("drop table: no table is open or selected", .{});
                try self.sql_log.add(gpa, "drop table: no table is open or selected; open one, or write its name", .err);
                return;
            }
        } else switch (self.sqlTarget()) {
            .sqlite => |d| db = d,
            else => {
                dbf_rel = (try self.findDbf(name)) orelse {
                    try self.sql_log.add(gpa, "drop table: there is no DBF table of that name in the current folder", .err);
                    return;
                };
            },
        }
        if (self.drop_a) |old| gpa.free(old);
        if (self.drop_b) |old| gpa.free(old);
        self.drop_b = null;
        if (dbf_rel) |rel| {
            self.drop_a = try gpa.dupe(u8, rel);
            self.drop_is_dbf = true;
            self.askConfirm(.drop_table, 0, "Drop the table {s}? The file is deleted.", .{rel});
        } else {
            self.drop_a = try gpa.dupe(u8, db.?);
            self.drop_b = try gpa.dupe(u8, table);
            self.drop_is_dbf = false;
            self.askConfirm(.drop_table, 0, "Drop the table {s} of {s}? Its rows are lost.", .{ table, db.? });
        }
    }

    /// The Yes of the drop dialog: delete the DBF file, or drop the table of the database; close its tab; fix the tree.
    fn performDrop(self: *App) void {
        const gpa = self.gpa;
        const a_path = self.drop_a orelse return;
        if (self.drop_is_dbf) {
            const full = self.fullPath(a_path) catch return;
            defer gpa.free(full);
            Io.Dir.cwd().deleteFile(self.io, full) catch |err| {
                self.setMessage("cannot drop {s}: {s}", .{ a_path, @errorName(err) });
                return;
            };
            self.closeTabByPath(a_path);
            self.refreshTree();
            self.setMessage("dropped {s}", .{a_path});
            return;
        }
        const table = self.drop_b orelse return;
        const sql = std.fmt.allocPrint(gpa, "drop table \"{s}\";", .{table}) catch return;
        defer gpa.free(sql);
        var out = self.eveText(&.{ "db", "sql", a_path, sql }) catch return;
        if (std.mem.indexOf(u8, out, "view") != null) {
            gpa.free(out);
            const sql2 = std.fmt.allocPrint(gpa, "drop view \"{s}\";", .{table}) catch return;
            defer gpa.free(sql2);
            out = self.eveText(&.{ "db", "sql", a_path, sql2 }) catch return;
        }
        defer gpa.free(out);
        if (std.mem.startsWith(u8, out, "error:")) {
            self.setMessage("{s}", .{std.mem.trim(u8, out, " \r\n")});
            self.sql_log.addBlock(gpa, out, .err) catch {};
            return;
        }
        const key = std.fmt.allocPrint(gpa, "{s}#{s}", .{ a_path, table }) catch return;
        defer gpa.free(key);
        self.closeTabByPath(key);
        self.refreshDbTables(a_path) catch {};
        self.setMessage("dropped {s} of {s}", .{ table, a_path });
    }

    fn closeTabByPath(self: *App, path: []const u8) void {
        for (self.tabs.items, 0..) |t, i| {
            if (std.mem.eql(u8, t.path, path)) {
                self.closeTab(i);
                return;
            }
        }
    }

    // ------------------------------------------------------------ alter table and the Tab of the SQL panel

    /// The working folder of the console as a path in the project ("" for the project folder).
    fn workDirRel(self: *const App) []const u8 {
        const w = self.work_dir orelse return "";
        if (std.mem.eql(u8, w, self.root)) return "";
        if (w.len > self.root.len + 1 and std.mem.startsWith(u8, w, self.root) and w[self.root.len] == '/') return w[self.root.len + 1 ..];
        return "";
    }

    // Zig tip: the folders to look in are tried in order: the one the console is in, the one that holds the table that is
    // open or selected (or the selected folder), and the project folder. The answer is the path in the project of the first
    // file that exists, copied (the caller frees it), or null.
    /// The path in the project of the DBF table `name` (with or without `.dbf`), looked for in the current folders.
    fn findDbf(self: *App, name: []const u8) !?[]u8 {
        const gpa = self.gpa;
        const file = if (std.ascii.endsWithIgnoreCase(name, ".dbf")) try gpa.dupe(u8, name) else try std.fmt.allocPrint(gpa, "{s}.dbf", .{name});
        defer gpa.free(file);
        const folders = [_][]const u8{ self.workDirRel(), self.currentFolder(), "" };
        for (folders) |dir| {
            const rel = if (dir.len == 0) try gpa.dupe(u8, file) else try std.fmt.allocPrint(gpa, "{s}/{s}", .{ dir, file });
            const full = try self.fullPath(rel);
            defer gpa.free(full);
            if (Io.Dir.cwd().statFile(self.io, full, .{})) |_| {
                return rel;
            } else |_| gpa.free(rel);
        }
        return null;
    }

    /// The folder of the table that is open or selected, else the target folder of the tree.
    fn currentFolder(self: *const App) []const u8 {
        if (self.tabs.items.len > 0) {
            const t = self.tabs.items[@min(self.active, self.tabs.items.len - 1)];
            if (t.table != null and std.mem.indexOfScalar(u8, t.path, '#') == null) return std.fs.path.dirname(t.path) orelse "";
        }
        return self.targetDir();
    }

    // Zig tip: `alter table` alone means "the table I am on": the one open in the Main Panel, else the one selected in the
    // tree. With a name, the target of the SQL decides: a database that is selected owns the name; otherwise the name is a
    // DBF file in the current folder. A message in the SQL panel says when nothing is found.
    /// `alter table [name]`: open the structure dialog of that table.
    fn alterTable(self: *App, name: []const u8) !void {
        const gpa = self.gpa;
        if (name.len == 0) {
            if (self.activeTab()) |t| {
                if (t.table != null) {
                    if (std.mem.indexOfScalar(u8, t.path, '#')) |h| return self.openSqStructure(t.path[0..h], t.path[h + 1 ..]);
                    return self.openStructure(t.path);
                }
            }
            if (self.selected < self.tree.entries.items.len) {
                const e = self.tree.entries.items[self.selected];
                if (e.kind == .table) {
                    const h = std.mem.indexOfScalar(u8, e.path, '#') orelse return;
                    return self.openSqStructure(e.path[0..h], e.path[h + 1 ..]);
                }
                if (!e.is_dir and std.ascii.eqlIgnoreCase(extensionOf(e.path), "dbf")) return self.openStructure(e.path);
            }
            try self.sql_log.add(gpa, "alter table: no table is open or selected; open one, or write its name", .err);
            return;
        }
        switch (self.sqlTarget()) {
            .sqlite => |db| {
                const copy = try gpa.dupe(u8, db);
                defer gpa.free(copy);
                try self.openSqStructure(copy, name);
            },
            else => {
                const rel = (try self.findDbf(name)) orelse {
                    try self.sql_log.add(gpa, "alter table: there is no DBF table of that name in the current folder", .err);
                    return;
                };
                defer gpa.free(rel);
                try self.openStructure(rel);
            },
        }
    }

    /// The names of the tables that SQL can reach now: the tables of the database that is the target, or the DBF tables of
    /// the current folder. Sorted; the caller frees the names and the list.
    fn sqlTableNames(self: *App) !std.ArrayList([]u8) {
        const gpa = self.gpa;
        var out: std.ArrayList([]u8) = .empty;
        errdefer {
            for (out.items) |n| gpa.free(n);
            out.deinit(gpa);
        }
        switch (self.sqlTarget()) {
            .sqlite => |db| {
                const text_out = try self.eveText(&.{ "db", "sql", "-t", db, "select name from sqlite_master where type in ('table','view') and name not like 'sqlite_%' order by name;" });
                defer gpa.free(text_out);
                if (std.mem.startsWith(u8, text_out, "error:")) return out;
                var lines = std.mem.splitScalar(u8, text_out, '\n');
                _ = lines.next();
                while (lines.next()) |raw| {
                    const n = std.mem.trim(u8, raw, " \r");
                    if (n.len > 0) try out.append(gpa, try gpa.dupe(u8, n));
                }
            },
            else => {
                const dir_rel = switch (self.sqlTarget()) {
                    .dbf => |p| std.fs.path.dirname(p) orelse "",
                    else => if (self.workDirRel().len > 0) self.workDirRel() else self.targetDir(),
                };
                const full = if (dir_rel.len == 0) try gpa.dupe(u8, if (self.root.len == 0) "." else self.root) else try self.fullPath(dir_rel);
                defer gpa.free(full);
                var dir = Io.Dir.cwd().openDir(self.io, full, .{ .iterate = true }) catch return out;
                defer dir.close(self.io);
                var it = dir.iterate();
                while (it.next(self.io) catch null) |e| {
                    if (e.kind != .file or !std.ascii.eqlIgnoreCase(extensionOf(e.name), "dbf")) continue;
                    try out.append(gpa, try gpa.dupe(u8, std.fs.path.stem(e.name)));
                }
                std.mem.sort([]u8, out.items, {}, struct {
                    fn less(_: void, x: []u8, y: []u8) bool {
                        return std.ascii.lessThanIgnoreCase(x, y);
                    }
                }.less);
            },
        }
        return out;
    }

    // Zig tip: Tab cycles. The first Tab remembers what was typed (the word before the cursor) and puts the first table whose
    // name starts with it (the first table of all when nothing is typed); each next Tab puts the next one, and after the last
    // the first again. The word on the line is replaced each time: its letters are erased one by one with `deleteBeforeCursor`.
    // Any other key ends the cycle (`sql_tab_active` is set to false in `sqlKey`).
    /// Tab in the SQL panel: complete the word with the next table whose name starts with the letters typed.
    fn sqlTab(self: *App) !void {
        const gpa = self.gpa;
        if (!self.sql_tab_active) {
            const first = self.sql_in.buf.firstHalf();
            var start: usize = first.len;
            while (start > 0 and first[start - 1] != ' ' and first[start - 1] != '(' and first[start - 1] != ',') start -= 1;
            const word = first[start..];
            if (self.sql_tab_prefix) |old| gpa.free(old);
            self.sql_tab_prefix = try gpa.dupe(u8, word);
            self.sql_tab_len = std.unicode.utf8CountCodepoints(word) catch word.len;
            self.sql_tab_idx = 0;
            self.sql_tab_active = true;
        } else self.sql_tab_idx += 1;
        const prefix = self.sql_tab_prefix orelse "";
        var names = self.sqlTableNames() catch return;
        defer {
            for (names.items) |n| gpa.free(n);
            names.deinit(gpa);
        }
        var matches: std.ArrayList([]u8) = .empty;
        defer matches.deinit(gpa);
        for (names.items) |n| {
            if (n.len >= prefix.len and std.ascii.eqlIgnoreCase(n[0..prefix.len], prefix)) try matches.append(gpa, n);
        }
        if (matches.items.len == 0) {
            self.setMessage("no table starts with '{s}'", .{prefix});
            self.sql_tab_active = false;
            return;
        }
        const pick = matches.items[self.sql_tab_idx % matches.items.len];
        for (0..self.sql_tab_len) |_| self.sql_in.deleteBeforeCursor();
        try self.sql_in.insertSliceAtCursor(pick);
        self.sql_tab_len = std.unicode.utf8CountCodepoints(pick) catch pick.len;
    }

    // ------------------------------------------------------------ the target of SQL

    // Zig tip: a union with payloads names where the SQL goes: nowhere special (a memory database), a SQLite file, or a DBF
    // table (which SQLite gets as a copy). The target follows what is selected: the table that is open in the Main Panel
    // first, then the row selected in the tree. `use <file>` overrides it, `use auto` gives it back.
    const SqlTarget = union(enum) { memory, sqlite: []const u8, dbf: []const u8 };

    pub fn sqlTarget(self: *const App) SqlTarget {
        if (self.sql_db) |d| return if (std.mem.eql(u8, d, ":memory:")) .memory else .{ .sqlite = d };
        if (self.tabs.items.len > 0) {
            const t = self.tabs.items[@min(self.active, self.tabs.items.len - 1)];
            if (t.table != null) {
                if (std.mem.indexOfScalar(u8, t.path, '#')) |h| return .{ .sqlite = t.path[0..h] };
                return .{ .dbf = t.path };
            }
        }
        if (self.selected < self.tree.entries.items.len) {
            const e = self.tree.entries.items[self.selected];
            switch (e.kind) {
                .db => return .{ .sqlite = e.path },
                .table => return .{ .sqlite = e.path[0 .. std.mem.indexOfScalar(u8, e.path, '#') orelse e.path.len] },
                .normal => if (!e.is_dir and std.ascii.eqlIgnoreCase(extensionOf(e.path), "dbf")) return .{ .dbf = e.path },
            }
        }
        return .memory;
    }

    /// What the SQL panel says about its target.
    pub fn sqlTargetText(self: *const App) []const u8 {
        return switch (self.sqlTarget()) {
            .memory => "memory (forgotten after each command)",
            .sqlite => |p| p,
            .dbf => |p| p,
        };
    }

    // ------------------------------------------------------------ DBF tables

    /// The tree after a file was made: scanned again, the open folders kept.
    fn refreshTree(self: *App) void {
        var open: std.ArrayList([]u8) = .empty;
        defer {
            for (open.items) |p| self.gpa.free(p);
            open.deinit(self.gpa);
        }
        for (self.tree.entries.items) |e| {
            if (e.is_dir and e.expanded) {
                const copy = self.gpa.dupe(u8, e.path) catch continue;
                open.append(self.gpa, copy) catch self.gpa.free(copy);
            }
        }
        self.tree.scan(self.io, self.root, self.project_name) catch return;
        for (self.tree.entries.items) |*e| {
            for (open.items) |p| {
                if (e.is_dir and std.mem.eql(u8, e.path, p)) e.expanded = true;
            }
        }
    }

    /// Today as the three bytes of the header of a DBF file.
    fn dbfDate(self: *const App) [3]u8 {
        return dbf.headerDate(Io.Timestamp.now(self.io, .real).toSeconds());
    }

    // Zig tip: a new table is a file with a header and no fields. Right after, the table opens in the Main Panel and the
    // command `alter table <name>` is typed in the SQL panel, where it waits for the run delay like every command, so the
    // person sees it and can press Enter or Esc. `std.fs.path.stem` is the name without folder and extension.
    /// A new DBF table (File > New DBF, or Save As with a name that ends in .dbf): make the file and ask for its fields.
    fn createDbf(self: *App, rel: []const u8) !void {
        const full = try self.fullPath(rel);
        defer self.gpa.free(full);
        if (Io.Dir.cwd().statFile(self.io, full, .{})) |_| {
            self.setMessage("{s} exists already", .{rel});
            return;
        } else |_| {}
        const bytes = try dbf.rebuild(self.gpa, null, &.{}, self.dbfDate());
        defer self.gpa.free(bytes);
        Io.Dir.cwd().writeFile(self.io, .{ .sub_path = full, .data = bytes }) catch |err| {
            self.setMessage("cannot make {s}: {s}", .{ rel, @errorName(err) });
            return;
        };
        self.refreshTree();
        try self.openFile(rel);
        const cmd = try std.fmt.allocPrint(self.gpa, "alter table {s}", .{std.fs.path.stem(rel)});
        defer self.gpa.free(cmd);
        try self.issueSql(cmd);
    }

    /// File > New DBF: the Save As box with a name to change.
    pub fn newDbfDialog(self: *App) void {
        self.saveas_in.clearRetainingCapacity();
        self.saveas_in.insertSliceAtCursor("table.dbf") catch {};
        self.openOverlay(.save_as);
    }

    // Zig tip: the name typed after `alter table` may or may not have the extension; `endsWithIgnoreCase` decides. The
    // file is read whole and parsed by `dbf.Table.load`; the fields are copied into the list of the dialog twice: one list
    // to edit and one to compare with, so the dialog can tell what changed.
    /// `alter table <name>`: open the structure dialog of the DBF table.
    fn openStructure(self: *App, name: []const u8) !void {
        const gpa = self.gpa;
        const rel = if (std.ascii.endsWithIgnoreCase(name, ".dbf")) try gpa.dupe(u8, name) else try std.fmt.allocPrint(gpa, "{s}.dbf", .{name});
        errdefer gpa.free(rel);
        const full = try self.fullPath(rel);
        defer gpa.free(full);
        const bytes = Io.Dir.cwd().readFileAlloc(self.io, full, gpa, .limited(256 << 20)) catch {
            try self.sql_log.add(gpa, "alter table: there is no DBF table of that name in the project folder", .err);
            gpa.free(rel);
            return;
        };
        var table = dbf.Table.load(gpa, bytes) catch |err| {
            gpa.free(bytes);
            const msg = try std.fmt.allocPrint(gpa, "alter table: {s} is not a DBF table ({s})", .{ rel, @errorName(err) });
            defer gpa.free(msg);
            try self.sql_log.add(gpa, msg, .err);
            gpa.free(rel);
            return;
        };
        defer table.deinit();
        self.st_fields.clearRetainingCapacity();
        self.st_orig.clearRetainingCapacity();
        for (table.fields, 0..) |f, i| {
            try self.st_fields.append(gpa, .{ .f = f, .src = i });
            try self.st_orig.append(gpa, .{ .f = f, .src = i });
        }
        self.st_records = table.records;
        if (self.st_path) |old| gpa.free(old);
        self.st_path = rel;
        if (self.st_fields.items.len == 0) try self.stAdd();
        self.st_row = 0;
        self.st_col = 0;
        self.st_editing = false;
        self.st_drop = false;
        self.st_error = null;
        self.openOverlay(.structure);
    }

    /// Add a field after the selected one (a name that is not used yet, Character 10).
    fn stAdd(self: *App) !void {
        var f: dbf.Field = .{};
        var n: usize = self.st_fields.items.len + 1;
        var name_buf: [16]u8 = undefined;
        while (true) : (n += 1) {
            const name = std.fmt.bufPrint(&name_buf, "FIELD{d}", .{n}) catch "FIELD";
            var used = false;
            for (self.st_fields.items) |s| {
                if (std.ascii.eqlIgnoreCase(s.f.nameSlice(), name)) used = true;
            }
            if (!used) {
                f.setName(name);
                break;
            }
        }
        const at = if (self.st_fields.items.len == 0) 0 else self.st_row + 1;
        try self.st_fields.insert(self.gpa, at, .{ .f = f });
        self.st_row = at;
        self.st_col = 0;
    }

    fn stRemove(self: *App) void {
        if (self.st_fields.items.len <= 1) {
            self.st_error = "a table needs at least one field";
            return;
        }
        _ = self.st_fields.orderedRemove(self.st_row);
        self.st_row = @min(self.st_row, self.st_fields.items.len - 1);
    }

    fn stMove(self: *App, delta: isize) void {
        const n = self.st_fields.items.len;
        const to_i: isize = @as(isize, @intCast(self.st_row)) + delta;
        if (to_i < 0 or to_i >= n) return;
        const to: usize = @intCast(to_i);
        std.mem.swap(StField, &self.st_fields.items[self.st_row], &self.st_fields.items[to]);
        self.st_row = to;
    }

    /// How many differences there are between the dialog and the file: fields added, removed, changed or moved.
    pub fn stChanges(self: *const App) usize {
        var n: usize = 0;
        for (self.st_fields.items, 0..) |s, i| {
            const same = i < self.st_orig.items.len and s.src == self.st_orig.items[i].src and std.meta.eql(s.f, self.st_orig.items[i].f);
            if (!same) n += 1;
        }
        if (self.st_orig.items.len > self.st_fields.items.len) n += self.st_orig.items.len - self.st_fields.items.len;
        return n;
    }

    // Zig tip: the text of a cell is parsed when Enter is pressed; a bad number or name leaves the old value and says why in
    // `st_error`. `std.fmt.parseInt(u8, text, 10) catch` gives a number or runs the block after `catch`.
    /// Put the text being edited into the selected cell.
    fn stCommit(self: *App) !void {
        const text_in = try self.st_edit.toOwnedContents(self.gpa);
        defer self.gpa.free(text_in);
        const t = std.mem.trim(u8, text_in, " ");
        const f = &self.st_fields.items[self.st_row].f;
        self.st_editing = false;
        self.st_error = null;
        if (t.len == 0 and self.st_col != 0) return;
        switch (self.st_col) {
            0 => f.setName(t),
            2 => f.length = std.fmt.parseInt(u8, t, 10) catch {
                self.st_error = "the length is a number from 1 to 254";
                return;
            },
            3 => f.decimals = std.fmt.parseInt(u8, t, 10) catch {
                self.st_error = "the decimals are a number";
                return;
            },
            else => {},
        }
        self.st_error = dbf.checkField(f);
    }

    fn stStartEdit(self: *App) !void {
        const f = &self.st_fields.items[self.st_row].f;
        self.st_error = null;
        if (self.st_col == 1) {
            self.st_drop = true;
            self.st_drop_sel = std.mem.indexOfScalar(u8, dbf.kinds, f.kind) orelse 0;
            return;
        }
        if (self.st_col == 2 and (f.kind == 'D' or f.kind == 'L' or f.kind == 'M')) return;
        if (self.st_col == 3 and f.kind != 'N' and f.kind != 'F') return;
        self.st_edit.clearRetainingCapacity();
        var nb: [8]u8 = undefined;
        const cur: []const u8 = switch (self.st_col) {
            0 => f.nameSlice(),
            2 => std.fmt.bufPrint(&nb, "{d}", .{f.length}) catch "",
            else => std.fmt.bufPrint(&nb, "{d}", .{f.decimals}) catch "",
        };
        // a number is typed anew (the old value would have to be erased first); a name is edited
        if (self.st_col == 0) try self.st_edit.insertSliceAtCursor(cur);
        self.st_editing = true;
    }

    fn stPickType(self: *App, k: u8) void {
        const f = &self.st_fields.items[self.st_row].f;
        if (k == 'M' and f.kind != 'M') {
            self.st_error = "a memo field cannot be created (it needs a .FPT file); it is kept when the table has one";
            self.st_drop = false;
            return;
        }
        if (f.kind != k) dbf.defaultsFor(k, f);
        self.st_drop = false;
        self.st_error = null;
    }

    /// The keys of the structure dialog.
    fn structureKey(self: *App, key: Key) !void {
        if (self.st_editing) {
            if (key.matches(Key.enter, .{})) return self.stCommit();
            try self.st_edit.update(.{ .key_press = key });
            return;
        }
        const kn = dbf.kinds.len;
        if (self.st_drop) {
            if (key.matches(Key.up, .{})) self.st_drop_sel = (self.st_drop_sel + kn - 1) % kn else if (key.matches(Key.down, .{})) self.st_drop_sel = (self.st_drop_sel + 1) % kn else if (key.matches(Key.enter, .{})) self.stPickType(dbf.kinds[self.st_drop_sel]);
            return;
        }
        const n = self.st_fields.items.len;
        if (key.matches(Key.up, .{ .ctrl = true })) return self.stMove(-1);
        if (key.matches(Key.down, .{ .ctrl = true })) return self.stMove(1);
        if (key.matches(Key.up, .{})) self.st_row = self.st_row -| 1 else if (key.matches(Key.down, .{})) self.st_row = @min(self.st_row + 1, n - 1) else if (key.matches(Key.left, .{})) self.st_col = self.st_col -| 1 else if (key.matches(Key.right, .{}) or key.matches(Key.tab, .{})) self.st_col = @min(self.st_col + 1, 3) else if (key.matches(Key.page_up, .{})) self.st_row = self.st_row -| 10 else if (key.matches(Key.page_down, .{})) self.st_row = @min(self.st_row + 10, n - 1) else if (key.matches(Key.enter, .{})) try self.stStartEdit() else if (key.matches(Key.insert, .{})) try self.stAdd() else if (key.matches(Key.delete, .{})) self.stRemove() else if (key.matches('s', .{ .ctrl = true })) try self.stApply();
    }

    // Zig tip: the checks come first and name the first problem; only then is the cost of losing data weighed. A field of
    // the file that no field of the dialog comes from is dropped, and a field that changes type or gets shorter may lose
    // text. When there are records and something may be lost, the same Yes/No dialog as for a breakpoint asks first.
    /// The Apply button: check the fields, ask if data may be lost, then change the file.
    fn stApply(self: *App) !void {
        self.st_error = null;
        const items = self.st_fields.items;
        for (items, 0..) |s, i| {
            if (dbf.checkField(&s.f)) |msg| {
                self.st_error = msg;
                self.st_row = i;
                return;
            }
            for (items[0..i]) |other| {
                if (std.ascii.eqlIgnoreCase(other.f.nameSlice(), s.f.nameSlice())) {
                    self.st_error = "two fields have the same name";
                    self.st_row = i;
                    return;
                }
            }
        }
        if (self.stChanges() == 0) {
            self.st_error = "nothing to apply";
            return;
        }
        var risk: usize = 0;
        for (self.st_orig.items, 0..) |o, c| {
            var kept: ?StField = null;
            for (items) |s| {
                if (s.src == c) kept = s;
            }
            if (kept) |s| {
                if (s.f.kind != o.f.kind and s.f.kind != 'C') risk += 1 else if (s.f.length < o.f.length) risk += 1;
            } else risk += 1;
        }
        if (self.st_records > 0 and risk > 0) {
            self.askConfirm(.apply_structure, 0, "{d} field(s) lose or convert their data in {d} records. Apply?", .{ risk, self.st_records });
            return;
        }
        try self.stApplyNow();
    }

    /// Write the new structure: the file is read again, rebuilt with the data of the fields that stay, and written.
    fn stApplyNow(self: *App) !void {
        const gpa = self.gpa;
        const rel = self.st_path orelse return;
        const full = try self.fullPath(rel);
        defer gpa.free(full);
        const bytes = Io.Dir.cwd().readFileAlloc(self.io, full, gpa, .limited(256 << 20)) catch |err| {
            self.st_error = @errorName(err);
            self.openOverlay(.structure);
            return;
        };
        var table = dbf.Table.load(gpa, bytes) catch |err| {
            gpa.free(bytes);
            self.st_error = @errorName(err);
            self.openOverlay(.structure);
            return;
        };
        defer table.deinit();
        const specs = try gpa.alloc(dbf.Spec, self.st_fields.items.len);
        defer gpa.free(specs);
        for (self.st_fields.items, 0..) |s, i| specs[i] = .{ .field = s.f, .src = s.src };
        const out = try dbf.rebuild(gpa, &table, specs, self.dbfDate());
        defer gpa.free(out);
        Io.Dir.cwd().writeFile(self.io, .{ .sub_path = full, .data = out }) catch |err| {
            self.st_error = @errorName(err);
            self.openOverlay(.structure);
            return;
        };
        self.overlay = .none;
        self.reloadTable(rel);
        const msg = try std.fmt.allocPrint(gpa, "{s}: structure changed, {d} fields, {d} records", .{ rel, specs.len, table.records });
        defer gpa.free(msg);
        try self.sql_log.add(gpa, msg, .info);
        self.setMessage("{s}", .{msg});
    }

    /// Read the table of an open tab again (its structure or its data changed on disk).
    fn reloadTable(self: *App, rel: []const u8) void {
        for (self.tabs.items) |*t| {
            const tv = t.table orelse continue;
            if (!std.mem.eql(u8, t.path, rel)) continue;
            const full = self.fullPath(rel) catch return;
            defer self.gpa.free(full);
            const bytes = Io.Dir.cwd().readFileAlloc(self.io, full, self.gpa, .limited(256 << 20)) catch return;
            const table = dbf.Table.load(self.gpa, bytes) catch {
                self.gpa.free(bytes);
                return;
            };
            tv.t.deinit();
            tv.* = .{ .t = table };
        }
    }

    // ------------------------------------------------------------ breakpoints

    // Zig tip: `const b = t.buf orelse return;` unwraps an optional or leaves the function. Removing
    // from the list while looping is safe here because the loop returns right after `orderedRemove`.
    pub fn toggleBreakpoint(self: *App) !void {
        const b = self.activeBuffer() orelse return;
        try self.toggleBreakpointAt(b.row + 1);
    }

    /// Set a breakpoint on line `line` (1 based) of the current file, or remove it when there is one.
    pub fn toggleBreakpointAt(self: *App, line: usize) !void {
        const t = self.activeTab() orelse return;
        if (t.buf == null) return;
        if (t.virtual) return;
        if (t.path.len == 0) {
            self.setMessage("save the file first: a breakpoint needs a file", .{});
            return;
        }
        for (self.breakpoints.items, 0..) |bp, i| {
            if (bp.line == line and std.mem.eql(u8, bp.path, t.path)) {
                if (bp.enabled) self.syncBreakpoint(t.path, line, false);
                self.gpa.free(bp.path);
                _ = self.breakpoints.orderedRemove(i);
                return;
            }
        }
        try self.breakpoints.append(self.gpa, .{ .path = try self.gpa.dupe(u8, t.path), .line = line });
        self.syncBreakpoint(t.path, line, true);
    }

    // Zig tip: `self: *const App` is enough for a function that only looks. The view calls it for
    // every line it draws, so it does no allocation.
    pub fn hasBreakpoint(self: *const App, path: []const u8, line: usize) bool {
        return self.breakpointState(path, line) != null;
    }

    /// The state of the breakpoint on a line: null when there is none, else whether it is enabled.
    pub fn breakpointState(self: *const App, path: []const u8, line: usize) ?bool {
        for (self.breakpoints.items) |bp| {
            if (bp.line == line and std.mem.eql(u8, bp.path, path)) return bp.enabled;
        }
        return null;
    }

    // Zig tip: a breakpoint is switched, not removed: the line stays in the list (gray in the gutter) and the debugger
    // of a running session is told `clear` or `break`, as for a removal or a new breakpoint.
    /// The check box of the Breaks tab: enable or disable breakpoint `i`.
    fn toggleBreakpointEnabled(self: *App, i: usize) void {
        if (i >= self.breakpoints.items.len) return;
        const bp = &self.breakpoints.items[i];
        bp.enabled = !bp.enabled;
        self.syncBreakpoint(bp.path, bp.line, bp.enabled);
    }

    fn deleteBreakpoint(self: *App, i: usize) void {
        if (i >= self.breakpoints.items.len) return;
        const bp = self.breakpoints.items[i];
        if (bp.enabled) self.syncBreakpoint(bp.path, bp.line, false);
        self.gpa.free(bp.path);
        _ = self.breakpoints.orderedRemove(i);
        self.break_sel = @min(self.break_sel, self.breakpoints.items.len -| 1);
    }

    // Zig tip: one dialog serves every "are you sure": the message is a parameter (formatted by the caller), `what` says
    // what a Yes does and `arg` for which item. A new question is a new value of `Confirm` and one more branch in
    // `confirmYes`; the dialog and its keys stay as they are.
    /// Ask a yes/no question in a dialog. Yes does `what` for `arg`; No and Esc do nothing.
    pub fn askConfirm(self: *App, what: Confirm, arg: usize, comptime f: []const u8, args: anytype) void {
        const msg = std.fmt.allocPrint(self.gpa, f, args) catch return;
        if (self.confirm_msg) |old| self.gpa.free(old);
        self.confirm_msg = msg;
        self.confirm_what = what;
        self.confirm_arg = arg;
        self.openOverlay(.confirm);
    }

    /// The Yes of the confirmation dialog.
    fn confirmYes(self: *App) void {
        self.overlay = .none;
        switch (self.confirm_what) {
            .none => {},
            .delete_breakpoint => self.deleteBreakpoint(self.confirm_arg),
            .apply_structure => self.stApplyNow() catch {},
            .move_files => self.performMove(),
            .apply_sqlite => self.sqApplyNow() catch {},
            .drop_table => self.performDrop(),
            .clear_breakpoints => {
                while (self.breakpoints.items.len > 0) self.deleteBreakpoint(self.breakpoints.items.len - 1);
            },
        }
        self.confirm_what = .none;
    }

    // Zig tip: a `switch` on the tab of the bottom panel names what each one clears. The breakpoints are not a log: they
    // are removed only after the question, with the same dialog as the trash icon.
    /// The tool Clear: empty the panel of the Tools Panel that is shown (the Console, the SQL panel, Stdout, Stderr, Watch).
    pub fn clearPanel(self: *App) !void {
        switch (self.bottom) {
            .console => self.console.clear(self.gpa),
            .sql => self.sql_log.clear(self.gpa),
            .stdout => self.stdout_log.clear(self.gpa),
            .stderr => self.stderr_log.clear(self.gpa),
            .watch => self.watch_log.clear(self.gpa),
            .breaks => {
                if (self.breakpoints.items.len == 0) return;
                self.askConfirm(.clear_breakpoints, 0, "Remove all {d} breakpoints?", .{self.breakpoints.items.len});
            },
        }
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

    // Zig tip: `Thread.spawn(.{}, RunJob.work, .{job})` starts the worker; the job lives on the heap (`gpa.create`)
    // because both threads use it. `errdefer` undoes each step if a later one fails.
    /// Run `eve` with these arguments in the working folder of the console. The process runs in a thread; the output
    /// goes to the Stdout and Stderr tabs and a summary to the console when it ends (`finishRun`, called by `tick`).
    pub fn runEve(self: *App, args: []const []const u8) !void {
        return self.runEveMode(args, false);
    }

    /// `runEve`, with the debugger on or off (`eve debug <file>` takes commands and shows its output while it runs).
    fn runEveMode(self: *App, args: []const []const u8, debug: bool) !void {
        return self.startJob(eve_exe, args, debug);
    }

    // Zig tip: the shell takes the whole line as one argument after `-c` (`/c` for cmd.exe), so pipes, quotes and `&&` are
    // the shell's own business. The program runs like any job (output in the console, Halt stops it), in the working
    // folder; when it ends the console is where it was: at the eve prompt for `shell <command>`.
    /// Run one line in the shell that started evetx.
    fn runShellLine(self: *App, line: []const u8) !void {
        const flag: []const u8 = if (builtin.os.tag == .windows and std.ascii.eqlIgnoreCase(self.shell_exe, "cmd.exe")) "/c" else "-c";
        const sh_args = [_][]const u8{ flag, line };
        try self.startJob(self.shell_exe, &sh_args, false);
    }

    /// Start a program (`eve`, or the shell) with these arguments in the working folder of the console.
    fn startJob(self: *App, program: []const u8, args: []const []const u8, debug: bool) !void {
        const gpa = self.gpa;
        if (self.job != null) {
            self.setMessage("a program is running: Stop it first (Shift+F5 or the Stop button)", .{});
            return;
        }
        const argv = try gpa.alloc([]u8, args.len + 1);
        var made: usize = 0;
        errdefer {
            for (argv[0..made]) |a| gpa.free(a);
            gpa.free(argv);
        }
        argv[0] = try gpa.dupe(u8, program);
        made = 1;
        for (args) |a| {
            argv[made] = try gpa.dupe(u8, a);
            made += 1;
        }
        const base = self.work_dir orelse self.root;
        const cwd: ?[]u8 = if (base.len == 0 or std.mem.eql(u8, base, ".")) null else try gpa.dupe(u8, base);
        errdefer if (cwd) |c| gpa.free(c);
        const job = try gpa.create(RunJob);
        errdefer gpa.destroy(job);
        job.* = .{ .io = self.io, .gpa = gpa, .argv = argv, .cwd = cwd, .debug = debug };
        self.stdout_log.clear(gpa);
        self.stderr_log.clear(gpa);
        job.thread = try std.Thread.spawn(.{}, RunJob.work, .{job});
        self.job = job;
        self.running = true;
    }

    // Zig tip: `takeLive` hands over a slice that this function frees with `defer`. The same text goes to the Console and
    // to the Stdout tab, as the output of a finished run does.
    /// Show the output lines that a debug run produced since the last call.
    fn takeOutput(self: *App, job: *RunJob) !void {
        const live = job.takeLive() orelse return;
        defer self.gpa.free(live);
        try self.stdout_log.addBlock(self.gpa, live, .out);
        try self.console.addBlock(self.gpa, live, .out);
        self.console.scroll = 0;
        self.stdout_log.scroll = 0;
    }

    // Zig tip: `tick` calls this ten times a second while a job exists. A new stop is seen through `serial`: the first
    // time, the breakpoints of the editor are sent to the debugger and then the command that was waiting for the stop
    // (Run with breakpoints, Trace); every time, the variables go to the Watch tab, the file is opened and the cursor goes to
    // the line where the program stopped. While the program traces, the line changes without a stop, and the editor
    // follows it.
    /// Debug session: show the output and the variables, and follow the debugger to the line of the program.
    fn pollDebug(self: *App) !void {
        const job = self.job orelse return;
        if (!job.debug) return;
        try self.takeOutput(job);
        const serial = job.serial.load(.acquire);
        const line = job.line.load(.acquire);
        const stopped = serial != self.dbg_serial;
        if (!stopped and (line == self.dbg_line_seen or line == 0)) return;
        self.dbg_line_seen = line;
        if (stopped) {
            self.dbg_serial = serial;
            self.showVars(job);
        }
        if (stopped and !self.dbg_sent) {
            self.dbg_sent = true;
            if (self.dbg_path) |p| {
                const delay = try std.fmt.allocPrint(self.gpa, "delay {d}", .{self.options.trace_ms});
                defer self.gpa.free(delay);
                job.sendCommand(delay);
                for (self.breakpoints.items) |bp| {
                    if (!bp.enabled or !std.mem.eql(u8, bp.path, p)) continue;
                    const cmd = try std.fmt.allocPrint(self.gpa, "break {d}", .{bp.line});
                    defer self.gpa.free(cmd);
                    job.sendCommand(cmd);
                }
            }
            if (self.dbg_auto) |cmd| {
                self.dbg_auto = null;
                // a breakpoint on the very first statement stops the program there: `run` would pass it
                var here = false;
                if (self.dbg_path) |p| {
                    for (self.breakpoints.items) |bp| {
                        if (bp.enabled and bp.line == line and std.mem.eql(u8, bp.path, p)) here = true;
                    }
                }
                if (!(here and std.mem.eql(u8, cmd, "run"))) {
                    job.sendCommand(cmd);
                    return;
                }
            }
        }
        if (stopped) self.setMessage("stopped before line {d} · Run, Next, Step, Exit, Trace, Halt", .{line});
        if (self.dbg_path) |p| {
            const path = try self.gpa.dupe(u8, p);
            defer self.gpa.free(path);
            try self.openFile(path);
            if (self.activeBuffer()) |b| b.gotoLine(line, 0);
            self.follow = true;
        }
    }

    /// Fill the Watch tab with the variables of the stop.
    fn showVars(self: *App, job: *RunJob) void {
        const vars = job.takeVars() orelse return;
        defer self.gpa.free(vars);
        self.watch_log.clear(self.gpa);
        self.watch_log.addBlock(self.gpa, vars, .out) catch {};
        self.watch_log.scroll = 0;
    }

    // Zig tip: the line of a breakpoint set or removed while a session runs is sent at once, so the debugger and the
    // editor agree; before the first stop nothing is sent, because the whole list goes then (`pollDebug`).
    /// A breakpoint was set (`added`) or removed in the file `path`: tell the debugger of a running session.
    fn syncBreakpoint(self: *App, path: []const u8, line: usize, added: bool) void {
        const job = self.job orelse return;
        if (!job.debug or !self.dbg_sent) return;
        const p = self.dbg_path orelse return;
        if (!std.mem.eql(u8, p, path)) return;
        const cmd = std.fmt.allocPrint(self.gpa, "{s} {d}", .{ if (added) "break" else "clear", line }) catch return;
        defer self.gpa.free(cmd);
        job.sendCommand(cmd);
    }

    /// The line (from 1) where the program of the debug session is, when `path` is its file; else 0. While the program
    /// is stopped or traces it is the line of the arrow in the gutter.
    pub fn debugLine(self: *const App, path: []const u8) u32 {
        const job = self.job orelse return 0;
        const p = self.dbg_path orelse return 0;
        if (!job.debug or !std.mem.eql(u8, p, path)) return 0;
        return job.line.load(.acquire);
    }

    /// Is a debug session open, and is the program stopped, waiting for a command?
    pub fn debugPaused(self: *const App) bool {
        const job = self.job orelse return false;
        return job.debug and job.paused.load(.acquire);
    }

    /// Are there breakpoints in the file of the active tab? Then Run starts the debugger.
    fn hasBreakpointsHere(self: *App) bool {
        const t = self.activeTab() orelse return false;
        for (self.breakpoints.items) |bp| {
            if (bp.enabled and std.mem.eql(u8, bp.path, t.path)) return true;
        }
        return false;
    }

    // Zig tip: the command goes to the debugger only when the program is stopped; while it runs, a click says so. With
    // no session, `next`, `step` and `exit` start one (the script stops before its first statement), and `trace` starts
    // one and traces at once; `run` is the ordinary Run (see `runActive`).
    /// A debugger button or key: next, step, exit, trace, or run.
    pub fn debugCommand(self: *App, verb: []const u8) !void {
        if (self.job) |job| {
            if (!job.debug) {
                self.setMessage("a program is running without the debugger: Halt it first", .{});
                return;
            }
            if (!job.paused.load(.acquire)) {
                self.setMessage("the program is running: Halt stops it", .{});
                return;
            }
            job.sendCommand(verb);
            return;
        }
        if (std.mem.eql(u8, verb, "run")) return self.runActive();
        try self.startDebug(if (std.mem.eql(u8, verb, "trace")) "trace" else null);
    }

    /// The Run button: `run` for a program that is stopped, nothing for one that runs (Halt is its button), and the
    /// ordinary Run for no program, which starts the debugger when there are breakpoints.
    fn runButton(self: *App) !void {
        if (self.job) |job| {
            if (job.debug and job.paused.load(.acquire)) return self.debugCommand("run");
            self.setMessage("the program is running: Halt stops it", .{});
            return;
        }
        try self.runActive();
    }

    /// The Halt button: `halt` for a stopped program (it ends as stopped), the process is ended for one that runs.
    pub fn haltRun(self: *App) !void {
        if (self.job) |job| {
            if (job.debug and job.paused.load(.acquire)) {
                job.sendCommand("halt");
                return;
            }
        }
        self.stopRun();
    }

    /// Start `eve debug <file>` on the file of the active tab: it stops before the first statement, and then does
    /// `auto` (`run`, `trace`) when there is one.
    fn startDebug(self: *App, auto: ?[]const u8) !void {
        try self.leaveShell();
        if (self.canRun()) try self.adoptFolderSelection();
        const t = self.activeTab() orelse {
            self.setMessage("nothing to debug: open an .eve file", .{});
            return;
        };
        if (t.buf == null or !t.eve) {
            self.setMessage("Debug needs an .eve file", .{});
            return;
        }
        if (t.path.len == 0 or t.buf.?.dirty) try self.save();
        if (t.path.len == 0) return;
        if (!self.show_tools) self.togglePanel(.tools);
        self.bottom = .console;
        try self.enterScriptFolder(t.path);
        if (self.dbg_path) |p| self.gpa.free(p);
        self.dbg_path = try self.gpa.dupe(u8, t.path);
        self.dbg_sent = false;
        self.dbg_serial = 0;
        self.dbg_line_seen = 0;
        self.dbg_auto = auto;
        self.watch_log.clear(self.gpa);
        const args = [_][]const u8{ "debug", std.fs.path.basename(t.path) };
        try self.runEveMode(&args, true);
    }

    // Zig tip: `std.process.run` runs a program and waits for it. The SQL is short work, so the wait is not noticed; the
    // statement is one argument, so no quoting of the shell is involved. The database is a file of the project, or
    // `:memory:` (forgotten after each command: `use <file.db>` chooses a file).
    /// Enter in the SQL panel: run the line with `eve db sql` and show the result table.
    fn sqlEnter(self: *App) !void {
        const gpa = self.gpa;
        const line = try self.sql_in.toOwnedContents(gpa);
        defer gpa.free(line);
        self.sql_in.clearRetainingCapacity();
        const cmd = std.mem.trim(u8, line, " \t");
        if (cmd.len == 0) return;
        try self.sql_log.add(gpa, cmd, .sql);
        if (std.mem.eql(u8, cmd, "clear")) {
            self.sql_log.clear(gpa);
            return;
        }
        // `create table <name>` (no column list) and `drop table <name>` are understood here: the first asks for the columns in a
        // dialog (a SQLite table when a database is selected, a DBF table when a folder is), the second asks before it drops
        if (cmd.len >= 12 and std.ascii.eqlIgnoreCase(cmd[0..12], "create table") and (cmd.len == 12 or cmd[12] == ' ') and std.mem.indexOfScalar(u8, cmd, '(') == null) {
            const name = std.mem.trim(u8, cmd[12..], " ;");
            if (name.len == 0) self.openCreateTable() else try self.createTableNamed(name);
            return;
        }
        if (cmd.len >= 10 and std.ascii.eqlIgnoreCase(cmd[0..10], "drop table") and (cmd.len == 10 or cmd[10] == ' ') and std.ascii.indexOfIgnoreCase(cmd, " if ") == null) {
            try self.dropTable(std.mem.trim(u8, cmd[10..], " ;"));
            return;
        }
        // `alter table [<name>]` is not sent to a database: it opens the structure dialog. Without a name it is the table that is
        // open or selected; with one, a table of the selected database, or a DBF table of the current folder
        if (cmd.len >= 11 and std.ascii.eqlIgnoreCase(cmd[0..11], "alter table") and (cmd.len == 11 or cmd[11] == ' ')) {
            try self.alterTable(std.mem.trim(u8, cmd[11..], " ;"));
            return;
        }
        if (std.mem.eql(u8, cmd, "use auto")) {
            if (self.sql_db) |old| gpa.free(old);
            self.sql_db = null;
            try self.sql_log.add(gpa, "database: follows the selection", .info);
            return;
        }
        if (std.mem.startsWith(u8, cmd, "use ")) {
            const file = std.mem.trim(u8, cmd[4..], " ");
            if (self.sql_db) |old| gpa.free(old);
            self.sql_db = try gpa.dupe(u8, file);
            const msg = try std.fmt.allocPrint(gpa, "database: {s}", .{file});
            defer gpa.free(msg);
            try self.sql_log.add(gpa, msg, .info);
            return;
        }
        const cwd: std.process.Child.Cwd = if (self.root.len == 0 or std.mem.eql(u8, self.root, ".")) .inherit else .{ .path = self.root };
        // a DBF table is given to SQLite as a copy: a script that makes the table, then the statement typed
        var script_path: ?[]u8 = null;
        defer if (script_path) |p| gpa.free(p);
        var db: []const u8 = ":memory:";
        switch (self.sqlTarget()) {
            .memory => {},
            .sqlite => |p| db = p,
            .dbf => |rel| {
                const full = try self.fullPath(rel);
                defer gpa.free(full);
                const bytes = Io.Dir.cwd().readFileAlloc(self.io, full, gpa, .limited(256 << 20)) catch |err| {
                    const msg = try std.fmt.allocPrint(gpa, "cannot read {s}: {s}", .{ rel, @errorName(err) });
                    defer gpa.free(msg);
                    try self.sql_log.add(gpa, msg, .err);
                    return;
                };
                var table = dbf.Table.load(gpa, bytes) catch {
                    gpa.free(bytes);
                    try self.sql_log.add(gpa, "not a DBF table", .err);
                    return;
                };
                defer table.deinit();
                const sql_text = try dbf.toSql(gpa, &table, std.fs.path.stem(rel));
                defer gpa.free(sql_text);
                self.cache.writeFile("dbf-sql.tmp.sql", sql_text) catch {};
                script_path = try std.fmt.allocPrint(gpa, "{s}/dbf-sql.tmp.sql", .{if (self.cache.dir.len == 0) "." else self.cache.dir});
            },
        }
        var argv_list: std.ArrayList([]const u8) = .empty;
        defer argv_list.deinit(gpa);
        try argv_list.appendSlice(gpa, &.{ eve_exe, "db", "sql" });
        if (script_path) |sp| try argv_list.appendSlice(gpa, &.{ "--last", "-f", sp });
        try argv_list.appendSlice(gpa, &.{ db, cmd });
        const result = std.process.run(gpa, self.io, .{ .argv = argv_list.items, .cwd = cwd }) catch |err| {
            const msg = try std.fmt.allocPrint(gpa, "cannot run {s}: {s}", .{ eve_exe, @errorName(err) });
            defer gpa.free(msg);
            try self.sql_log.add(gpa, msg, .err);
            return;
        };
        defer gpa.free(result.stdout);
        defer gpa.free(result.stderr);
        try self.sql_log.addBlock(gpa, result.stdout, if (std.mem.startsWith(u8, result.stdout, "error:")) .err else .out);
        try self.sql_log.addBlock(gpa, result.stderr, .err);
    }

    /// The keys of the SQL panel: Enter runs the line, Esc goes back to the editor, Page Up and Down scroll.
    fn sqlKey(self: *App, key: Key) !void {
        if (key.matches(Key.escape, .{})) {
            if (self.pending_at != null) {
                self.cancelPending();
                self.sql_in.clearRetainingCapacity();
                self.setMessage("command cancelled", .{});
                return;
            }
            self.focus = .editor;
            return;
        }
        if (key.matches(Key.enter, .{})) {
            self.cancelPending();
            return self.sqlEnter();
        }
        if (self.pending_at != null) self.cancelPending();
        if (key.matches(Key.tab, .{})) return self.sqlTab();
        self.sql_tab_active = false;
        if (key.matches(Key.page_up, .{})) {
            self.sql_log.scroll +|= @max(1, self.console_rect.h / 2);
            return;
        }
        if (key.matches(Key.page_down, .{})) {
            self.sql_log.scroll -|= @max(1, self.console_rect.h / 2);
            return;
        }
        try self.sql_in.update(.{ .key_press = key });
    }

    /// The log that the Tools Panel shows now (for the wheel and the arrows of its scroll bar).
    fn shownLog(self: *App) *Log {
        return switch (self.bottom) {
            .stdout => &self.stdout_log,
            .stderr => &self.stderr_log,
            .watch => &self.watch_log,
            .sql => &self.sql_log,
            else => &self.console,
        };
    }

    /// The Stop button: end the process that runs (the worker sees the flag within a tenth of a second).
    pub fn stopRun(self: *App) void {
        if (self.job) |j| {
            j.stop.store(true, .release);
            self.setMessage("stopping the program…", .{});
        } else self.setMessage("nothing is running", .{});
    }

    // Zig tip: `.acquire` on the `done` flag pairs with the `.release` store of the worker: everything the worker wrote
    // before setting it is visible here. After `join` the thread is gone and the job is ours to read and free.
    /// When the worker is done: show its output and a summary, and free the job.
    fn finishRun(self: *App) !void {
        const job = self.job orelse return;
        if (!job.done.load(.acquire)) return;
        if (job.thread) |t| t.join();
        const was_debug = job.debug;
        try self.takeOutput(job);
        self.job = null;
        self.running = false;
        defer job.destroy();
        const gpa = self.gpa;
        if (was_debug) {
            if (self.dbg_path) |p| gpa.free(p);
            self.dbg_path = null;
            self.dbg_sent = false;
        }
        if (job.err_name) |name| {
            const msg = try std.fmt.allocPrint(gpa, "cannot run {s}: {s} (is it in the PATH?)", .{ job.argv[0], name });
            defer gpa.free(msg);
            try self.console.add(gpa, msg, .err);
            return;
        }
        try self.stdout_log.addBlock(gpa, job.stdout, .out);
        try self.stderr_log.addBlock(gpa, job.stderr, .err);
        try self.console.addBlock(gpa, job.stdout, .out);
        try self.console.addBlock(gpa, job.stderr, .err);
        const summary = if (job.stopped)
            try std.fmt.allocPrint(gpa, "stopped", .{})
        else if (job.term) |term| switch (term) {
            .exited => |code| try std.fmt.allocPrint(gpa, "finished, exit {d}", .{code}),
            else => try std.fmt.allocPrint(gpa, "ended by a signal", .{}),
        } else try std.fmt.allocPrint(gpa, "finished", .{});
        defer gpa.free(summary);
        try self.console.add(gpa, summary, .info);
        self.console.scroll = 0;
        self.stdout_log.scroll = 0;
        self.stderr_log.scroll = 0;
    }

    // Zig tip: `Io.Dir.cwd().openDir(io, path, .{})` fails with an error (a name of the error set, e.g.
    // `error.FileNotFound`) when the folder does not exist, so opening it is also the test. `defer dir.close(io)`
    // gives the handle back whatever happens. `try`-free code here: every failure is reported to the console.
    /// `cd`: the commands of the console run in this folder from now on. Says so in the console.
    fn changeDir(self: *App, target: []const u8) !void {
        var dir = Io.Dir.cwd().openDir(self.io, if (target.len == 0) "." else target, .{}) catch |err| {
            const msg = try std.fmt.allocPrint(self.gpa, "cd: cannot open the folder {s}: {s}", .{ target, @errorName(err) });
            defer self.gpa.free(msg);
            try self.console.add(self.gpa, msg, .err);
            return;
        };
        dir.close(self.io);
        const own = try self.gpa.dupe(u8, target);
        if (self.work_dir) |old| self.gpa.free(old);
        self.work_dir = own;
        const msg = try std.fmt.allocPrint(self.gpa, "folder: {s}", .{own});
        defer self.gpa.free(msg);
        try self.console.add(self.gpa, msg, .info);
    }

    // Zig tip: `std.fs.path.dirname` and `basename` cut a path into the folder part and the file name without
    // copying: both are slices of the same text. `dirname` returns an optional (null for a bare name), and
    // `orelse ""` turns "no folder" into the empty folder, the project root.
    /// Run and Check: go to the folder of the script first (a `cd` line in the console), and give back the file name.
    /// The folder of a script matters: `eve` loads the `eve.cfg` of its working folder, and a project may hold
    /// several sub-projects, each with its own.
    fn enterScriptFolder(self: *App, rel: []const u8) !void {
        try self.enterFolder(std.fs.path.dirname(rel) orelse "");
    }

    // Zig tip: the folder is a path from the project folder ("" is the project folder itself). The `cd` line is written in
    // the console in the style of the mode: `$ cd ...` at the shell prompt, `eve:> cd ...` otherwise, so the console tells
    // what happened. A folder that is already the working folder says nothing.
    /// Make a folder of the project the working folder of the console, and say so in the console.
    pub fn enterFolder(self: *App, dir_rel: []const u8) !void {
        const full = if (dir_rel.len == 0) try self.gpa.dupe(u8, if (self.root.len == 0) "." else self.root) else try self.fullPath(dir_rel);
        defer self.gpa.free(full);
        if (self.work_dir) |cur| {
            if (std.mem.eql(u8, cur, full)) return;
        }
        const shown = try std.fmt.allocPrint(self.gpa, "cd {s}", .{full});
        defer self.gpa.free(shown);
        try self.console.add(self.gpa, shown, if (self.shell_mode) .shell else .input);
        try self.changeDir(full);
    }

    /// Run, Check and Debug are eve's: at the shell prompt they bring eve back first.
    fn leaveShell(self: *App) !void {
        if (!self.shell_mode) return;
        self.shell_mode = false;
        try self.console.add(self.gpa, "eve is back", .info);
    }

    // Zig tip: `orelse { ...; return; }` can hold a block: unwrap the optional, or run the block and
    // leave. After that line `t` is a plain pointer, not an optional.
    /// F5, the Run button: save the file and run it.
    pub fn runActive(self: *App) !void {
        try self.leaveShell();
        if (self.canRun()) try self.adoptFolderSelection();
        if (self.debugPaused()) {
            self.job.?.sendCommand("run");
            return;
        }
        if (self.job == null and self.hasBreakpointsHere()) return self.startDebug("run");
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
        try self.enterScriptFolder(t.path);
        const line = try std.fmt.allocPrint(self.gpa, "run {s}", .{std.fs.path.basename(t.path)});
        defer self.gpa.free(line);
        try self.issueCommand(line);
    }

    /// F6: the syntax check of the current `.eve` file (`eve --check <file>`), through the prompt like Run.
    pub fn checkActive(self: *App) !void {
        try self.leaveShell();
        if (self.canRun()) try self.adoptFolderSelection();
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
        try self.enterScriptFolder(t.path);
        const line = try std.fmt.allocPrint(self.gpa, "--check {s}", .{std.fs.path.basename(t.path)});
        defer self.gpa.free(line);
        try self.issueCommand(line);
    }

    // Zig tip: `Io.Timestamp.now(io, .awake).toMilliseconds()` reads a clock that only goes forward
    // (it does not jump when the user changes the time of the computer), the right one to measure a
    // delay. The delay is a constant at file level so that it is written once.
    pub fn nowMs(self: *const App) i64 {
        return Io.Timestamp.now(self.io, .awake).toMilliseconds();
    }

    /// A run command (Run, Check) does not start at once: it is typed in the prompt of the console, where
    /// the user can read it, and it starts after the run delay of the options (three seconds at first). Enter starts it now, Esc cancels it, and
    /// typing in the prompt keeps the text but cancels the countdown. The line goes into the history of
    /// the console at once, so Ctrl+Up finds it again even if it was cancelled.
    pub fn issueCommand(self: *App, line: []const u8) !void {
        self.pending_sql = false;
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
        self.pending_at = self.nowMs() + @as(i64, self.options.run_delay_s) * 1000;
    }

    // Zig tip: the same countdown as `issueCommand`, with the text typed in the prompt of the SQL panel; `tick` runs it
    // when the delay (Options > Timers, Run delay) is over, Enter runs it at once, Esc cancels.
    /// Type an SQL command in the SQL panel and run it after the run delay.
    pub fn issueSql(self: *App, line: []const u8) !void {
        if (!self.show_tools) self.togglePanel(.tools);
        if (self.maximized == .main) self.maximized = null;
        self.bottom = .sql;
        self.focus = .sql;
        self.sql_in.clearRetainingCapacity();
        try self.sql_in.insertSliceAtCursor(line);
        if (self.pending_text) |old| self.gpa.free(old);
        self.pending_text = try self.gpa.dupe(u8, line);
        self.pending_sql = true;
        self.pending_at = self.nowMs() + @as(i64, self.options.run_delay_s) * 1000;
    }

    // ------------------------------------------------------------ the session

    // Zig tip: `comptime f: []const u8` and `f ++ "\n"` build the format string at compile time, so
    // every call writes one line of the session file. `anytype` takes the tuple of arguments.
    fn sline(self: *App, out: *std.ArrayList(u8), comptime f: []const u8, args: anytype) !void {
        const s = try std.fmt.allocPrint(self.gpa, f ++ "\n", args);
        defer self.gpa.free(s);
        try out.appendSlice(self.gpa, s);
    }

    // Zig tip: `@intFromBool(b)` is 1 or 0; `@tagName(e)` is the name of an enum value as text, which
    // `std.meta.stringToEnum` turns back into the value when the session is read.
    /// Write where the user is: the project, the panel sizes and visibility, the open files with their
    /// cursors, the open folders of the tree and the breakpoints. It goes to `evetx-session.txt` in the
    /// cache folder; evetx reads it at the next start. Called when the program ends and when the files change.
    pub fn saveSession(self: *App) !void {
        if (self.root.len == 0 or self.restoring) return;
        const abs = try realPathOf(self.gpa, self.io, self.root);
        defer self.gpa.free(abs);
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(self.gpa);
        try self.sline(&out, "project={s}", .{abs});
        try self.sline(&out, "tree_w={d}", .{self.tree_w});
        try self.sline(&out, "tools_h={d}", .{self.tools_h});
        try self.sline(&out, "show_tree={d}", .{@intFromBool(self.show_tree)});
        try self.sline(&out, "show_main={d}", .{@intFromBool(self.show_main)});
        try self.sline(&out, "show_tools={d}", .{@intFromBool(self.show_tools)});
        try self.sline(&out, "wrap={d}", .{@intFromBool(self.wrap)});
        try self.sline(&out, "hidden={d}", .{@intFromBool(self.show_hidden)});
        try self.sline(&out, "bottom={s}", .{@tagName(self.bottom)});
        try self.sline(&out, "focus={s}", .{@tagName(self.focus)});
        var saved: usize = 0;
        var active: usize = 0;
        for (self.tabs.items, 0..) |t, i| {
            if (t.virtual or t.path.len == 0 or t.folder != null) continue;
            if (i == self.active) active = saved;
            saved += 1;
            if (t.buf) |b| {
                try self.sline(&out, "tab={s}\t{d}\t{d}\t{d}", .{ t.path, b.row, b.col, b.top });
            } else try self.sline(&out, "tab={s}\t0\t0\t0", .{t.path});
        }
        try self.sline(&out, "active={d}", .{active});
        for (self.tree.entries.items) |e| {
            if (e.is_dir and e.expanded and e.parent != null) try self.sline(&out, "expand={s}", .{e.path});
        }
        if (self.selected < self.tree.entries.items.len) try self.sline(&out, "selected={s}", .{self.tree.entries.items[self.selected].path});
        for (self.breakpoints.items) |bp| try self.sline(&out, "break={s}\t{d}\t{d}", .{ bp.path, bp.line, @intFromBool(bp.enabled) });
        try self.cache.writeFile("evetx-session.txt", out.items);
    }

    // Zig tip: A `switch` cannot take strings, so the keys are tried with a chain of `std.mem.eql`.
    // `std.fmt.parseInt(...) catch 0` reads a number and uses 0 when the text is not one. Errors are
    // never passed up from here: a damaged session file must not stop the program from starting.
    /// Read `evetx-session.txt` and put the screen back as it was, when it is the session of this project.
    fn restoreSession(self: *App) void {
        const bytes = self.cache.readFile("evetx-session.txt") orelse return;
        defer self.gpa.free(bytes);
        const abs = realPathOf(self.gpa, self.io, self.root) catch return;
        defer self.gpa.free(abs);
        var same = false;
        var first = std.mem.splitScalar(u8, bytes, '\n');
        while (first.next()) |raw| {
            const l = std.mem.trimEnd(u8, raw, "\r");
            if (std.mem.startsWith(u8, l, "project=")) {
                same = std.ascii.eqlIgnoreCase(l["project=".len..], abs);
                break;
            }
        }
        if (!same) return;

        self.restoring = true;
        defer self.restoring = false;
        var active: usize = 0;
        var it = std.mem.splitScalar(u8, bytes, '\n');
        while (it.next()) |raw| {
            const l = std.mem.trimEnd(u8, raw, "\r");
            const eq = std.mem.indexOfScalar(u8, l, '=') orelse continue;
            const key = l[0..eq];
            const val = l[eq + 1 ..];
            const num = std.fmt.parseInt(usize, val, 10) catch 0;
            if (std.mem.eql(u8, key, "tree_w")) {
                self.tree_w = @intCast(@min(num, 500));
            } else if (std.mem.eql(u8, key, "tools_h")) {
                self.tools_h = @intCast(@min(num, 500));
            } else if (std.mem.eql(u8, key, "show_tree")) {
                self.show_tree = num != 0;
            } else if (std.mem.eql(u8, key, "show_main")) {
                self.show_main = num != 0;
            } else if (std.mem.eql(u8, key, "show_tools")) {
                self.show_tools = num != 0;
            } else if (std.mem.eql(u8, key, "wrap")) {
                self.wrap = num != 0;
            } else if (std.mem.eql(u8, key, "hidden")) {
                self.show_hidden = num != 0;
            } else if (std.mem.eql(u8, key, "bottom")) {
                self.bottom = std.meta.stringToEnum(BottomTab, val) orelse .console;
            } else if (std.mem.eql(u8, key, "focus")) {
                self.focus = std.meta.stringToEnum(Focus, val) orelse .tree;
            } else if (std.mem.eql(u8, key, "active")) {
                active = num;
            } else if (std.mem.eql(u8, key, "expand")) {
                for (self.tree.entries.items) |*e| {
                    if (e.is_dir and std.mem.eql(u8, e.path, val)) e.expanded = true;
                }
            } else if (std.mem.eql(u8, key, "selected")) {
                for (self.tree.entries.items, 0..) |e, i| {
                    if (std.mem.eql(u8, e.path, val)) self.selected = @intCast(i);
                }
            } else if (std.mem.eql(u8, key, "break")) {
                const tab = std.mem.indexOfScalar(u8, val, '\t') orelse continue;
                const path = self.gpa.dupe(u8, val[0..tab]) catch continue;
                var rest = std.mem.splitScalar(u8, val[tab + 1 ..], '\t');
                const line = std.fmt.parseInt(usize, rest.next() orelse "0", 10) catch 0;
                const flag_text: []const u8 = rest.next() orelse "1";
                const enabled = flag_text.len == 0 or flag_text[0] != '0';
                self.breakpoints.append(self.gpa, .{ .path = path, .line = line, .enabled = enabled }) catch self.gpa.free(path);
            } else if (std.mem.eql(u8, key, "tab")) {
                var f = std.mem.splitScalar(u8, val, '\t');
                const path = f.next() orelse continue;
                const row = std.fmt.parseInt(usize, f.next() orelse "0", 10) catch 0;
                const col = std.fmt.parseInt(usize, f.next() orelse "0", 10) catch 0;
                const top = std.fmt.parseInt(usize, f.next() orelse "0", 10) catch 0;
                self.openFile(path) catch continue;
                if (self.activeBuffer()) |b| {
                    b.row = @min(row, b.lineCount() - 1);
                    const line = b.lineAt(b.row);
                    var c = @min(col, line.len);
                    while (c > 0 and c < line.len and (line[c] & 0xC0) == 0x80) c -= 1;
                    b.col = c;
                    b.top = @min(top, b.lineCount() - 1);
                }
            }
        }
        if (active < self.tabs.items.len) self.active = active;
        self.follow = false;
        if (self.message) |m| {
            self.gpa.free(m);
            self.message = null;
        }
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
        self.autoSaveTick();
        try self.pollDebug();
        try self.finishRun();
        self.refreshHover();
        if (self.freeze_at) |at| {
            if (self.nowMs() >= at) self.freezeLayout();
        }
        const left = self.pendingLeft() orelse return;
        if (left > 0) return;
        self.pending_at = null;
        if (self.pending_sql) {
            self.pending_sql = false;
            try self.sqlEnter();
            return;
        }
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
        try self.console.add(self.gpa, cmd, if (self.shell_mode) .shell else .input);

        if (std.mem.eql(u8, cmd, "clear")) {
            self.console.clear(self.gpa);
            return;
        }
        // `quit` closes evetx, as Ctrl+Q does. `exit` stops eve and shows the prompt `$` of the shell that started evetx
        // (the mode `shell_mode`): its commands run there, and `eve` brings the prompt of eve back. (`eve quit` as a
        // one-shot process would end only that process.)
        if (std.mem.eql(u8, cmd, "quit")) {
            self.quit = true;
            return;
        }
        if (std.mem.eql(u8, cmd, "exit")) {
            if (self.shell_mode) {
                try self.console.add(self.gpa, "evetx stays open: type quit to close it, eve to go back to eve", .info);
                return;
            }
            if (self.job != null) self.stopRun();
            self.shell_mode = true;
            try self.console.add(self.gpa, "eve stopped. The commands go to the shell now; eve starts it again, quit closes evetx.", .info);
            return;
        }
        var words: std.ArrayList([]const u8) = .empty;
        defer words.deinit(self.gpa);
        var it = std.mem.tokenizeScalar(u8, cmd, ' ');
        while (it.next()) |w| try words.append(self.gpa, w);
        // `cd <folder>` changes the working folder of the console; a relative folder starts from the current one.
        if (std.mem.eql(u8, words.items[0], "cd")) {
            const arg = std.mem.trim(u8, cmd[2..], " ");
            if (arg.len == 0) {
                const msg = try std.fmt.allocPrint(self.gpa, "folder: {s}", .{self.work_dir orelse self.root});
                defer self.gpa.free(msg);
                try self.console.add(self.gpa, msg, .info);
                return;
            }
            const base = self.work_dir orelse self.root;
            const target = if (std.fs.path.isAbsolute(arg) or base.len == 0) try self.gpa.dupe(u8, arg) else try std.fmt.allocPrint(self.gpa, "{s}/{s}", .{ base, arg });
            defer self.gpa.free(target);
            try self.changeDir(target);
            return;
        }
        // the shell prompt: `eve` alone goes back to eve, `eve <arguments>` runs eve once, any other line is the shell's
        if (self.shell_mode) {
            if (std.mem.eql(u8, words.items[0], "eve")) {
                if (words.items.len == 1) {
                    self.shell_mode = false;
                    try self.console.add(self.gpa, "eve is back", .info);
                    return;
                }
                try self.runEve(words.items[1..]);
                return;
            }
            try self.runShellLine(cmd);
            return;
        }
        // `shell <command>` at the eve prompt: leave eve for one command of the shell, then be in eve again
        if (std.mem.eql(u8, words.items[0], "shell")) {
            if (words.items.len == 1) {
                if (self.job != null) self.stopRun();
                self.shell_mode = true;
                try self.console.add(self.gpa, "eve stopped. The commands go to the shell now; eve starts it again, quit closes evetx.", .info);
                return;
            }
            try self.runShellLine(std.mem.trim(u8, cmd["shell".len..], " "));
            return;
        }
        // `run x.eve` is `eve x.eve`; any other line is given to eve as its arguments.
        const args = if (std.mem.eql(u8, words.items[0], "run")) words.items[1..] else words.items;
        try self.runEve(args);
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
        self.tree_follow = true;
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
        try b.checkpoint(.other);
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
        try b.checkpoint(.other);
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
        if (which == .save_as) {
            const untitled = if (self.activeTab()) |t| t.path.len == 0 else false;
            const dir = self.targetDir();
            if (untitled and dir.len > 0 and self.saveas_in.buf.firstHalf().len + self.saveas_in.buf.secondHalf().len == 0) {
                self.saveas_in.insertSliceAtCursor(dir) catch {};
                self.saveas_in.insertSliceAtCursor("/") catch {};
            }
        }
        self.overlay = which;
        self.dlg_field = 0;
    }

    // Zig tip: `self: *const App` promises that the function only reads the app, so the drawing
    // code can call it too. A row that is not in the fixed list of the menu is made on the spot: the
    // WINDOW menu ends with a separator and one row for each open window (at most nine, the ones
    // that Ctrl+1 to Ctrl+9 reach).
    // Zig tip: `std.ArrayList(Machine)` is a growing array that owns its memory: `append(gpa, x)` may allocate, so it
    // can fail, and `deinit(gpa)` gives the memory back. The registration order is the order of the items.
    /// Add a machine to the list. `name` null makes the label `address:port`.
    fn machineAdd(self: *App, address: []const u8, port: u16, name: ?[]const u8) !void {
        const addr = try self.gpa.dupe(u8, address);
        errdefer self.gpa.free(addr);
        const label = if (name) |n| try self.gpa.dupe(u8, n) else try std.fmt.allocPrint(self.gpa, "{s}:{d}", .{ address, port });
        errdefer self.gpa.free(label);
        try self.machines.append(self.gpa, .{ .label = label, .address = addr, .port = port });
    }

    /// Is machine `i` connected? Only the local machine for now; the others join with step T5.
    pub fn isConnected(self: *const App, i: usize) bool {
        _ = self;
        return i == 0;
    }

    /// The machines of the user, one `address<TAB>port` line each, in the file `evetx-machines.txt` of the user cache.
    fn loadMachines(self: *App) void {
        const bytes = self.cache.readFile("evetx-machines.txt") orelse return;
        defer self.gpa.free(bytes);
        var it = std.mem.splitScalar(u8, bytes, '\n');
        while (it.next()) |raw| {
            const l = std.mem.trim(u8, raw, " \r");
            const tab = std.mem.indexOfScalar(u8, l, '\t') orelse continue;
            const port = std.fmt.parseInt(u16, l[tab + 1 ..], 10) catch continue;
            if (tab == 0) continue;
            self.machineAdd(l[0..tab], port, null) catch return;
        }
    }

    fn saveMachines(self: *App) void {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(self.gpa);
        for (self.machines.items[1..]) |m| {
            const line = std.fmt.allocPrint(self.gpa, "{s}\t{d}\n", .{ m.address, m.port }) catch return;
            defer self.gpa.free(line);
            out.appendSlice(self.gpa, line) catch return;
        }
        self.cache.writeFile("evetx-machines.txt", out.items) catch |err| self.setMessage("machines not saved: {s}", .{@errorName(err)});
    }

    /// How many rows menu `m` has now.
    pub fn rowCount(self: *const App, m: usize) usize {
        const base = menus[m].items.len;
        if (m == menu_window and self.tabs.items.len > 0) return base + 1 + @min(self.tabs.items.len, 9);
        if (m == menu_machine) return base + self.machines.items.len;
        return base;
    }

    /// Row `k` of menu `m`. The title of a window is a slice of the tab, valid while the tab is open.
    pub fn rowAt(self: *const App, m: usize, k: usize) MenuRow {
        const items = menus[m].items;
        if (m == menu_machine) {
            // the registered machines come first, in order of registration, then the fixed rows
            const n = self.machines.items.len;
            if (k < n) return .{ .label = self.machines.items[k].label, .key = if (k < machine_keys.len) machine_keys[k] else "", .cmd = .machine_pick, .arg = k };
            return items[k - n];
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
            .new_dbf, .new_file => self.openNewDialog(),
            .preview => self.toggleView(),
            .create_table => self.openCreateTable(),
            .drop_table => try self.dropTable(""),
            .data_structure => try self.dataStructure(),
            .data_append => try self.dataAppend(1),
            .data_append_n => self.openAppendN(),
            .data_delete => try self.dataDelete(),
            .data_edit => self.dataEdit(),
            .save => try self.save(),
            .save_as => self.openOverlay(.save_as),
            .close_tab => self.closeTab(self.active),
            .quit => self.quit = true,
            .undo => try self.undoRedo(true),
            .redo => try self.undoRedo(false),
            .close_all => self.closeAll(),
            .close_clean => self.closeClean(0, self.tabs.items.len),
            .find_text => self.openOverlay(.find_text),
            .find_file => self.openOverlay(.find_file),
            .replace => self.openOverlay(.replace),
            .toggle_hidden => self.show_hidden = !self.show_hidden,
            .toggle_wrap => {
                self.wrap = !self.wrap;
                self.follow = true;
            },
            .goto_line => self.openOverlay(.goto),
            .query => self.notYet("Query", "T7"),
            .run => try self.runActive(),
            .check_file => try self.checkActive(),
            .dbg_next => try self.debugCommand("next"),
            .dbg_step => try self.debugCommand("step"),
            .dbg_exit => try self.debugCommand("exit"),
            .dbg_trace => try self.debugCommand("trace"),
            .stop => try self.haltRun(),
            .clear_panel => try self.clearPanel(),
            .breakpoint => try self.toggleBreakpoint(),
            .machine_pick => self.pickMachine(arg),
            .register => self.openRegister(),
            .upload => self.notYet("Remote machines", "T5"),
            .select_window => self.nextTab(1),
            .modify => self.startModify(false),
            .freeze => self.freezeLayout(),
            .toggle_tree => self.togglePanel(.tree),
            .toggle_main => self.togglePanel(.main),
            .toggle_tools => self.togglePanel(.tools),
            .window_pick => self.pickWindow(arg),
            .shortcuts => try self.openVirtual("Shortcuts", help_shortcuts),
            .manual => try self.openVirtual("Manual", help_manual),
            .tutorial => try self.openVirtual("Tutorial", help_tutorial),
            .about => self.openOverlay(.about),
            .options => self.openOptions(),
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
        // a rendered Markdown page runs full screen: the Tools Panel steps aside and the Main Panel goes down to the bottom bar
        const tools_on = self.isShown(.tools) and !self.mdFull();
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
        if (self.isShown(.main) and tools_on) {
            const bb = self.toolsHeight();
            const eh = mh - 1 - bb;
            l.main = .{ .x = rx, .y = 1, .w = rw, .h = eh };
            l.debug = .{ .x = rx, .y = 1 + eh, .w = rw, .h = 1 };
            l.tools = .{ .x = rx, .y = 2 + eh, .w = rw, .h = bb };
        } else if (self.isShown(.main)) {
            l.main = .{ .x = rx, .y = 1, .w = rw, .h = mh };
        } else if (tools_on) {
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
            .console, .breaks, .sql => .tools,
        };
    }

    /// Give the keyboard to panel `p`.
    pub fn focusPanel(self: *App, p: Panel) void {
        self.focus = switch (p) {
            .tree => .tree,
            .main => .editor,
            .tools => if (self.bottom == .breaks) .breaks else if (self.bottom == .sql) .sql else .console,
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
        if (self.work_dir) |c| self.gpa.free(c);
        self.work_dir = null;
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
        self.saveSession() catch {};
    }

    // Zig tip: A `switch` on the enum `Drag` decides what the moving mouse changes. The raw column
    // of the pointer is stored; `treeWidth` and `toolsHeight` clamp it, so a wild drag cannot break
    // the screen.
    /// A press on a border between panels: start dragging it. (Layout modify starts by itself, see `onMouse`.)
    fn grabSplit(self: *App, m: vaxis.Mouse) bool {
        const which = self.splitAt(m) orelse return false;
        // a locked layout lets a border be grabbed only after the hover delay (the border is then painted)
        if (!self.modify and self.hover_split != which) return false;
        self.drag = which;
        return true;
    }

    // Zig tip: `?Drag` is an optional enum: the answer is a kind of border, or null when the pointer is
    // not over one. The borders are the two columns where the Tree Panel and the Main Panel touch, and
    // the top border row of the Tools Panel (the row of the Run buttons above it is not part of it).
    /// Which border between panels is under the pointer?
    fn splitAt(self: *const App, m: vaxis.Mouse) ?Drag {
        const l = self.layout;
        const touching = l.main.w > 0 or l.tools.w > 0;
        if (l.tree.w > 0 and touching and (m.col == l.tree.w - 1 or m.col == l.tree.w) and m.row >= 1 and m.row < self.rows -| 3) return .tree_split;
        if (l.tools.w > 0 and l.main.w > 0 and m.col >= l.tools.x and m.row == l.tools.y) return .tools_split;
        // the toolbar between the two panels: its free space and its handle are part of the same border
        if (l.debug.w > 0 and l.tools.w > 0 and l.main.w > 0 and m.row == l.debug.y and m.col >= l.debug.x and m.col < l.debug.x + l.debug.w) {
            for (self.hits.items) |h| {
                if (h.rect.contains(m.col, m.row)) return null;
            }
            return .tools_split;
        }
        return null;
    }

    // Zig tip: the thumb has a size (`th`) and can only be at places from 0 to `span - th`; so the pointer places the *middle*
    // of the thumb, and the first item shown is the proportion of that place in the range of the thumb. Then the thumb goes
    // all the way to both ends of the track with the pointer, and the first and last item are reached. All the numbers are
    // `usize`; `-|` is a subtraction that stops at 0.
    /// The first item shown when the pointer is `rel` cells from the start of a track of `span` cells.
    fn thumbToTop(rel: usize, span: usize, total: usize, visible: usize) usize {
        if (total <= visible or span == 0) return 0;
        const th = @max(1, span * visible / total);
        if (span <= th) return 0;
        const at = @min(rel -| th / 2, span - th);
        return at * (total - visible) / (span - th);
    }

    /// A press on a scroll bar of the editor: start dragging its thumb.
    fn grabBar(self: *App, m: vaxis.Mouse) bool {
        if (self.vbar_rect.contains(m.col, m.row)) {
            self.drag = .vbar;
        } else if (self.hbar_rect.contains(m.col, m.row)) {
            self.drag = .hbar;
        } else if (self.mdbar_rect.contains(m.col, m.row)) {
            self.drag = .md_v;
        } else if (self.tblv_rect.contains(m.col, m.row)) {
            self.drag = .tbl_v;
        } else if (self.tblh_rect.contains(m.col, m.row)) {
            self.drag = .tbl_h;
        } else if (self.tvbar_rect.contains(m.col, m.row)) {
            self.drag = .tree_v;
        } else if (self.thbar_rect.contains(m.col, m.row)) {
            self.drag = .tree_h;
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
        if (self.drag == .md_v) {
            const r = self.mdbar_rect;
            const t = self.activeTab() orelse return;
            if (r.h < 2) return;
            const rel: usize = @intCast(@min(@max(@as(i32, m.row) - r.y, 0), r.h - 1));
            t.render_top = thumbToTop(rel, r.h, self.md_total, self.md_visible);
            return;
        }
        if (self.drag == .tbl_v or self.drag == .tbl_h) {
            const t = self.activeTab() orelse return;
            const tv = t.table orelse return;
            if (self.drag == .tbl_v) {
                const r = self.tblv_rect;
                if (r.h < 2) return;
                const rel: usize = @intCast(@min(@max(@as(i32, m.row) - r.y, 0), r.h - 1));
                tv.top = thumbToTop(rel, r.h, tv.t.records, self.tbl_rows);
            } else {
                const r = self.tblh_rect;
                if (r.w < 2) return;
                const rel: usize = @intCast(@min(@max(@as(i32, m.col) - r.x, 0), r.w - 1));
                tv.left = thumbToTop(rel, r.w, tv.t.fields.len, self.tbl_cols);
            }
            return;
        }
        if (self.drag == .tree_v) {
            self.tree_follow = false;
            const r = self.tvbar_rect;
            const total = self.visible.items.len;
            if (r.h < 2 or total <= self.tree_rect.h) return;
            const rel: usize = @intCast(@min(@max(@as(i32, m.row) - r.y, 0), r.h - 1));
            self.tree_top = thumbToTop(rel, r.h, total, self.tree_rect.h);
            return;
        }
        if (self.drag == .tree_h) {
            self.tree_follow = false;
            const r = self.thbar_rect;
            if (r.w < 2 or self.tree_content <= self.tree_rect.w) return;
            const rel: usize = @intCast(@min(@max(@as(i32, m.col) - r.x, 0), r.w - 1));
            self.tree_left = thumbToTop(rel, r.w, self.tree_content, self.tree_rect.w);
            return;
        }
        const b = self.activeBuffer() orelse return;
        if (self.drag == .vbar) {
            const r = self.vbar_rect;
            const total = b.lineCount() + 3;
            if (r.h < 2 or total <= r.h) return;
            const rel: usize = @intCast(@min(@max(@as(i32, m.row) - r.y, 0), r.h - 1));
            b.top = thumbToTop(rel, r.h, total, r.h + 3);
        } else if (self.drag == .hbar) {
            const r = self.hbar_rect;
            if (r.w < 2 or self.hbar_content <= r.w) return;
            const rel: usize = @intCast(@min(@max(@as(i32, m.col) - r.x, 0), r.w - 1));
            b.left = thumbToTop(rel, r.w, self.hbar_content, r.w + 2);
        }
    }

    // Zig tip: With wrapping, one line takes several rows, so a row of the screen is found by
    // walking the lines from the first one shown and taking away the rows each one uses
    // (`Buffer.segRows`). The function returns the line and which piece of it (0 for the first row).
    /// The line and the piece of it that are drawn at row `rel` of the editor (null below the last line).
    fn rowToLine(self: *const App, b: *const text.Buffer, rel: usize) ?struct { line: usize, seg: usize } {
        if (!self.wrap) return if (b.top + rel < b.lineCount()) .{ .line = b.top + rel, .seg = 0 } else null;
        var r = rel;
        var ln = b.top;
        while (ln < b.lineCount()) : (ln += 1) {
            const n = text.Buffer.segRows(b.lineAt(ln), self.editor_rect.w);
            if (r < n) return .{ .line = ln, .seg = r };
            r -= n;
        }
        return null;
    }

    /// The line drawn at row `rel` of the editor, if any.
    fn lineAtRow(self: *const App, b: *const text.Buffer, rel: usize) ?usize {
        const at = self.rowToLine(b, rel) orelse return null;
        return at.line;
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
        const dcol: usize = @intCast(@max(@as(i32, m.col) - r.x, 0));
        if (rel < 0) {
            b.top -|= 1;
            return .{ .row = b.top, .col = text.Buffer.byteAtDisplay(b.lineAt(b.top), dcol + b.left) };
        }
        if (rel >= r.h) {
            if (b.top < last) b.top += 1;
            const row = @min(b.top + r.h -| 1, last);
            return .{ .row = row, .col = text.Buffer.byteAtDisplay(b.lineAt(row), dcol + b.left) };
        }
        const at = self.rowToLine(b, @intCast(rel)) orelse return .{ .row = last, .col = b.lineAt(last).len };
        const base: usize = if (self.wrap) at.seg * r.w else b.left;
        return .{ .row = at.line, .col = text.Buffer.byteAtDisplay(b.lineAt(at.line), base + dcol) };
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
            .vbar, .hbar, .tree_v, .tree_h, .md_v, .tbl_v, .tbl_h => self.scrollTo(m),
            .select => self.selectTo(m),
        }
    }

    // Zig tip: `fn startModify(self: *App, by_mouse: bool)` takes a plain `bool`; the two ways in (the
    // menu or Ctrl+L, and a click on a border) differ only in this flag: with the mouse the layout
    // freezes by itself after the release, with the keyboard it stays until Ctrl+F or Esc.
    /// Layout modify: the borders between the panels can be dragged, and the arrow keys change the sizes.
    pub fn startModify(self: *App, by_mouse: bool) void {
        self.modify = true;
        self.mouse_modify = by_mouse;
        self.freeze_at = null;
    }

    /// Layout freeze: the sizes stay as they are.
    pub fn freezeLayout(self: *App) void {
        self.modify = false;
        self.mouse_modify = false;
        self.freeze_at = null;
        self.drag = .none;
        self.setMessage("layout frozen", .{});
    }

    /// Does the main loop have to wake up by itself? (A command waits, or the layout is about to freeze.)
    pub fn needsTick(self: *const App) bool {
        return self.pending_at != null or self.freeze_at != null or self.job != null or (self.hover_cand != null and self.hover_split == null) or (self.options.autosave_s > 0 and self.anyDirtyFile());
    }

    // Zig tip: The function returns `!bool`: an error union around a plain `bool`. The caller writes
    // `try self.modifyKey(key)` to get the `bool` or pass the error up. Here nothing can fail, but
    // the shape is the same as the other key functions.
    /// While Window > Modify is on: the arrows change the sizes, Esc and Enter freeze them. True when the key was used.
    fn modifyKey(self: *App, key: Key) !bool {
        // the keyboard takes over: a countdown that the mouse started is cancelled
        self.freeze_at = null;
        if (key.matches(Key.escape, .{}) or key.matches(Key.enter, .{}) or key.matches('z', .{ .ctrl = true })) {
            self.freezeLayout();
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

    // ------------------------------------------------------------ options

    /// Put the colors of the options in use (the drawing reads them in the next frame).
    pub fn applyOptions(self: *App) void {
        theme.apply(self.options.palette());
    }

    /// Write the options to the user cache.
    pub fn saveOptions(self: *App) void {
        const text_out = self.options.format(self.gpa) catch return;
        defer self.gpa.free(text_out);
        self.cache.writeFile("evetx-options.txt", text_out) catch |err| self.setMessage("options not saved: {s}", .{@errorName(err)});
    }

    /// File: Options (Ctrl+,): the dialog opens on the Theme tab.
    pub fn openOptions(self: *App) void {
        self.opt_backup = self.options;
        self.opt_tab = 0;
        self.openOverlay(.settings);
    }

    /// The OK button of the Options dialog: keep the changes and write them.
    fn optOk(self: *App) void {
        self.saveOptions();
        self.overlay = .none;
        self.setMessage("options saved", .{});
    }

    // Zig tip: A color is edited by changing one of its three bytes. `hex >> shift & 0xff` reads the
    // byte, and `(hex & ~mask) | (v << shift)` writes it: `~` flips all the bits, so the mask keeps the
    // other two bytes. The first change of a ready-made theme copies it to the Custom theme and
    // switches to it, so the ready-made themes are never changed.
    /// Set a color of the Custom theme (the theme in use becomes Custom).
    fn setSlotColor(self: *App, slot: usize, hex: u24) void {
        if (self.options.theme_id != theme.custom_id) {
            self.options.custom = self.options.palette();
            self.options.theme_id = theme.custom_id;
        }
        self.options.custom[slot] = hex;
        self.applyOptions();
    }

    fn setChannel(self: *App, ch: u8, v: u8) void {
        const slot: usize = self.opt_slot;
        const hex: u24 = self.options.palette()[slot];
        const shift: u5 = @intCast(8 * (2 - @as(u5, @intCast(ch))));
        const cleared: u24 = hex & ~(@as(u24, 0xff) << shift);
        self.setSlotColor(slot, cleared | (@as(u24, v) << shift));
    }

    /// Add `delta` to the channel that is selected in the Colors tab.
    fn adjustChannel(self: *App, delta: i32) void {
        const hex: u24 = self.options.palette()[self.opt_slot];
        const shift: u5 = @intCast(8 * (2 - @as(u5, @intCast(self.opt_channel))));
        const now: i32 = @intCast((hex >> shift) & 0xff);
        self.setChannel(self.opt_channel, @intCast(std.math.clamp(now + delta, 0, 255)));
    }

    fn adjustTimer(self: *App, row: u8, delta: i32) void {
        if (row == 0) {
            self.options.autosave_s = @intCast(std.math.clamp(@as(i32, self.options.autosave_s) + delta, 0, 3600));
        } else if (row == 3) {
            self.options.trace_ms = @intCast(std.math.clamp(@as(i32, self.options.trace_ms) + delta, 0, 5000));
        } else if (row == 2) {
            self.options.hover_delay_s = @intCast(std.math.clamp(@as(i32, self.options.hover_delay_s) + delta, 0, 60));
        } else {
            self.options.run_delay_s = @intCast(std.math.clamp(@as(i32, self.options.run_delay_s) + delta, 0, 60));
        }
    }

    fn themeStep(self: *App, delta: i32) void {
        const id: i32 = @intCast(self.options.theme_id);
        self.options.theme_id = @intCast(std.math.clamp(id + delta, 0, @as(i32, theme.custom_id)));
        self.applyOptions();
    }

    // Zig tip: `var k = key; k.mods.shift = false;` copies the key without Shift so the same
    // `matches` calls work with and without it; Shift then means "a small step". One `switch` on the
    // tab number sends the arrows to the tab that is open.
    /// The keys of the Options dialog: Tab changes the tab, the arrows change the values, Enter saves.
    fn optionsKey(self: *App, key: Key) !void {
        if (key.matches(Key.tab, .{})) {
            self.opt_tab = (self.opt_tab + 1) % 3;
            return;
        }
        if (key.matches(Key.tab, .{ .shift = true })) {
            self.opt_tab = (self.opt_tab + 2) % 3;
            return;
        }
        if (key.matches(Key.enter, .{})) return self.optOk();
        var k = key;
        k.mods.shift = false;
        const small = key.mods.shift;
        const up = k.matches(Key.up, .{});
        const down = k.matches(Key.down, .{});
        const left = k.matches(Key.left, .{});
        const right = k.matches(Key.right, .{});
        switch (self.opt_tab) {
            0 => {
                if (up) self.themeStep(-1) else if (down) self.themeStep(1);
            },
            1 => {
                if (up) self.opt_slot = self.opt_slot -| 1 else if (down) self.opt_slot = @intCast(@min(self.opt_slot + 1, theme.slot_count - 1)) else if (left) self.adjustChannel(if (small) -1 else -8) else if (right) self.adjustChannel(if (small) 1 else 8) else if (k.matches('r', .{})) self.opt_channel = 0 else if (k.matches('g', .{})) self.opt_channel = 1 else if (k.matches('b', .{})) self.opt_channel = 2;
            },
            else => {
                const step: i32 = if (self.opt_row == 3) 50 else if (small or self.opt_row != 0) 1 else 10;
                if (up) self.opt_row = (self.opt_row + 3) % 4 else if (down) self.opt_row = (self.opt_row + 1) % 4 else if (left) self.adjustTimer(self.opt_row, -step) else if (right) self.adjustTimer(self.opt_row, step);
            },
        }
    }

    /// A click in the Options dialog.
    fn optAction(self: *App, o: OptAction) void {
        switch (o) {
            .tab => |t| self.opt_tab = t,
            .theme => |t| {
                self.options.theme_id = t;
                self.applyOptions();
            },
            .slot => |i| self.opt_slot = i,
            .channel => |c| self.opt_channel = c,
            .slider => |s| {
                self.opt_channel = s.ch;
                self.setChannel(s.ch, s.v);
            },
            .swatch => |hex| self.setSlotColor(self.opt_slot, hex),
            .auto => |d| {
                self.opt_row = 0;
                self.adjustTimer(0, d);
            },
            .delay => |d| {
                self.opt_row = 1;
                self.adjustTimer(1, d);
            },
            .trace => |d| {
                self.opt_row = 3;
                self.adjustTimer(3, d);
            },
            .hover => |d| {
                self.opt_row = 2;
                self.adjustTimer(2, d);
            },
            .ok => self.optOk(),
            .defaults => {
                self.options = .{};
                self.applyOptions();
            },
        }
    }

    // ------------------------------------------------------------ auto save

    fn anyDirtyFile(self: *const App) bool {
        for (self.tabs.items) |t| {
            if (!t.virtual and t.path.len > 0 and t.buf != null and t.buf.?.dirty) return true;
        }
        return false;
    }

    // Zig tip: The countdown starts when the first change is seen and runs even if the user goes on
    // typing: the file is saved at most `autosave_s` seconds after the oldest unsaved change. Setting
    // the time to null when nothing is changed makes the next change start a new countdown.
    /// Called all the time by `tick`: saves the files that have changes when the auto save time is over.
    fn autoSaveTick(self: *App) void {
        if (self.options.autosave_s == 0 or !self.anyDirtyFile()) {
            self.autosave_at = null;
            return;
        }
        const now = self.nowMs();
        const at = self.autosave_at orelse {
            self.autosave_at = now + @as(i64, self.options.autosave_s) * 1000;
            return;
        };
        if (now < at) return;
        self.autosave_at = null;
        var n: usize = 0;
        for (self.tabs.items) |*t| {
            if (t.virtual or t.path.len == 0 or t.buf == null or !t.buf.?.dirty) continue;
            self.writeTab(t, t.path) catch continue;
            n += 1;
        }
        if (n > 0) self.setMessage("auto saved {d} file(s)", .{n});
    }

    // ------------------------------------------------------------ undo and closing many windows

    // Zig tip: One function for both directions, with a `bool`: `undo` or `redo` of the buffer return
    // false when there is nothing to do, and the message tells the user.
    /// Ctrl+U (undo) and Ctrl+Y (redo) on the current window.
    pub fn undoRedo(self: *App, undo: bool) !void {
        const b = self.activeBuffer() orelse return;
        if (self.activeTab().?.virtual) return;
        const done = if (undo) try b.undo() else try b.redo();
        if (!done) self.setMessage("nothing to {s}", .{if (undo) "undo" else "redo"});
        self.follow = true;
    }

    // Zig tip: The loop counts down (`while (i > lo) { i -= 1; ... }`) because closing a tab moves the
    // ones after it one place to the left: going from the end keeps the numbers that are still to be
    // visited correct. A window with changes is kept, and the message says how many.
    /// Close the windows `lo` to `hi - 1` that have no unsaved changes.
    pub fn closeClean(self: *App, lo: usize, hi: usize) void {
        var kept: usize = 0;
        var i = @min(hi, self.tabs.items.len);
        while (i > lo) {
            i -= 1;
            const t = self.tabs.items[i];
            if (t.buf != null and t.buf.?.dirty) kept += 1 else self.closeTab(i);
        }
        if (kept > 0) self.setMessage("{d} window(s) with unsaved changes were kept", .{kept});
    }

    /// Window > Close All: closes every window, unless one has unsaved changes.
    pub fn closeAll(self: *App) void {
        var dirty: usize = 0;
        for (self.tabs.items) |t| {
            if (t.buf != null and t.buf.?.dirty) dirty += 1;
        }
        if (dirty > 0) {
            self.setMessage("{d} window(s) have unsaved changes: save them, or use Close Clean", .{dirty});
            return;
        }
        while (self.tabs.items.len > 0) self.closeTab(0);
    }

    /// A right click on a tab: open its popup menu there.
    fn openTabMenu(self: *App, tab: usize, m: vaxis.Mouse) void {
        self.tab_menu_tab = tab;
        self.tab_menu_sel = 0;
        self.tab_menu_x = @intCast(@max(m.col, 0));
        self.tab_menu_y = @intCast(@max(m.row + 1, 0));
        self.overlay = .tab_menu;
    }

    /// Run row `i` of the popup menu of a tab.
    fn runTabMenu(self: *App, i: usize) !void {
        const tab = self.tab_menu_tab;
        self.overlay = .none;
        if (tab >= self.tabs.items.len or i >= tab_menu_rows.len) return;
        switch (tab_menu_rows[i].cmd) {
            .save => {
                self.active = tab;
                try self.save();
            },
            .save_as => {
                self.active = tab;
                self.openOverlay(.save_as);
            },
            .upload => self.notYet("Remote machines", "T5"),
            .close_this => self.closeTab(tab),
            .close_right => self.closeClean(tab + 1, self.tabs.items.len),
            .close_left => self.closeClean(0, tab),
            .close_clean => self.closeClean(0, self.tabs.items.len),
        }
    }

    // ------------------------------------------------------------ dialogs: projects and folders

    // Zig tip: One function is the single way to close a dialog (Esc, the x button, a click outside),
    // so the work that some dialogs need when they close is written once.
    /// Close the dialog that is open. The Find File dialog puts the tree back as it was.
    pub fn closeOverlay(self: *App) void {
        // Esc in the structure dialog first leaves the cell or the type list that is open
        if (self.overlay == .structure and (self.st_editing or self.st_drop)) {
            self.st_editing = false;
            self.st_drop = false;
            return;
        }
        if (self.overlay == .sq_structure and (self.sq_editing or self.sq_drop)) {
            self.sq_editing = false;
            self.sq_drop = false;
            return;
        }
        if (self.overlay == .find_file) self.filesCancel();
        if (self.overlay == .settings) {
            // Cancel: the options go back to what they were when the dialog opened
            self.options = self.opt_backup;
            self.applyOptions();
        }
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
            if (key.codepoint >= '1' and key.codepoint <= '3') return self.pickMachine(@intCast(key.codepoint - '1'));
            if (menuByLetter(key.codepoint)) |m| return self.openMenu(m);
        }
        if (key.matches(Key.tab, .{ .shift = true })) return self.rotatePanel(1);
        if (key.matches(Key.space, .{ .ctrl = true }) or key.codepoint == 0) return self.appendAtEnd();
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
        if (key.matches(',', .{ .ctrl = true })) return self.openOptions();
        if (key.matches('u', .{ .ctrl = true })) return self.undoRedo(true);
        if (key.matches('y', .{ .ctrl = true })) return self.undoRedo(false);
        if (key.matches('o', .{ .ctrl = true, .shift = true })) return self.openFolderDialog();
        if (key.matches('o', .{ .ctrl = true })) return self.openProjectDialog();
        if (key.matches('q', .{ .ctrl = true })) {
            self.quit = true;
            return;
        }
        if (key.matches('s', .{ .ctrl = true, .shift = true })) return self.openOverlay(.save_as);
        if (key.matches('s', .{ .ctrl = true })) return self.save();
        if (key.matches('w', .{ .ctrl = true })) return self.closeTab(self.active);
        if (key.matches('n', .{ .ctrl = true })) return self.openNewDialog();
        if (self.searchShortcut(key)) return;
        if (key.matches(Key.f5, .{})) return self.runActive();
        if (key.matches(Key.f6, .{})) return self.checkActive();
        if (key.matches(Key.f7, .{})) return self.notYet("Query", "T7");
        if (key.matches(Key.f9, .{})) return self.toggleBreakpoint();
        if (key.matches(Key.f8, .{})) return self.debugCommand("next");
        if (key.matches(Key.f8, .{ .shift = true })) return self.debugCommand("trace");
        if (key.matches(Key.f11, .{})) return self.debugCommand("step");
        if (key.matches(Key.f11, .{ .shift = true })) return self.debugCommand("exit");
        if (key.matches(Key.f5, .{ .shift = true })) return self.haltRun();

        switch (self.focus) {
            .editor => try self.editorKey(key),
            .tree => try self.treeKey(key),
            .console => try self.consoleKey(key),
            .breaks => try self.breaksKey(key),
            .sql => try self.sqlKey(key),
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
        if (key.matches('f', .{ .ctrl = true })) self.openOverlay(.find_text) else if (key.matches('p', .{ .ctrl = true })) self.openOverlay(.find_file) else if (key.matches('h', .{ .ctrl = true })) self.openOverlay(.replace) else if (key.matches('g', .{ .ctrl = true })) self.openOverlay(.goto) else if (key.matches('l', .{ .ctrl = true })) self.startModify(false) else return false;
        return true;
    }

    // Zig tip: an index from outside (a key, a click) is checked against the length of the list before it is used:
    // `i >= self.machines.items.len` is false for every valid place, so a wrong value does nothing.
    /// Use machine `i` of the list. A machine that is not connected is chosen all the same; the toolbar shows it in red.
    fn pickMachine(self: *App, i: usize) void {
        if (i >= self.machines.items.len) return;
        self.machine = i;
        if (self.isConnected(i)) self.setMessage("connection: {s}", .{self.machines.items[i].label}) else self.setMessage("{s} is chosen but not connected (remote machines come with step T5)", .{self.machines.items[i].label});
    }

    /// The dropdown of the registered machines under the name on the toolbar.
    fn openMachineMenu(self: *App, x: u16, y: u16) void {
        self.mm_x = x;
        self.mm_y = y;
        self.mm_sel = self.machine;
        self.overlay = .machine_menu;
    }

    // ------------------------------------------------------------ the registration form

    // Zig tip: a `TextInput` keeps its text in a gap buffer; `toOwnedContents(gpa)` copies it to a new slice that the
    // caller frees. `clearRetainingCapacity` empties it but keeps the memory for the next use.
    /// Fill the two fields from the selected row (empty for the new machine at the end of the table).
    fn regLoad(self: *App) void {
        self.reg_addr.clearRetainingCapacity();
        self.reg_port.clearRetainingCapacity();
        if (self.reg_sel >= self.machines.items.len) return;
        const m = self.machines.items[self.reg_sel];
        self.reg_addr.insertSliceAtCursor(m.address) catch {};
        if (self.reg_sel > 0) {
            const p = std.fmt.allocPrint(self.gpa, "{d}", .{m.port}) catch return;
            defer self.gpa.free(p);
            self.reg_port.insertSliceAtCursor(p) catch {};
        }
    }

    /// File > Register: the form opens on the machine in use.
    pub fn openRegister(self: *App) void {
        self.reg_sel = self.machine;
        self.regLoad();
        self.openOverlay(.register);
    }

    /// The text of a field, valid until the end of the frame.
    fn fieldText(self: *App, ti: *TextInput) []const u8 {
        const s = ti.toOwnedContents(self.frame.allocator()) catch return "";
        return std.mem.trim(u8, s, " ");
    }

    // Zig tip: `and`/`or` stop at the first answer (short circuit): `sel > 0 and ...` does not look at the row of the
    // local machine, which cannot be modified. The save button is on when the new row has anything in it, or when a
    // registered row differs from what the fields say.
    /// Can the registration form save? (A new machine is present, or the selected one is modified.)
    pub fn regDirty(self: *App) bool {
        const addr = self.fieldText(&self.reg_addr);
        const port = self.fieldText(&self.reg_port);
        const n = self.machines.items.len;
        if (self.reg_sel >= n) return addr.len > 0 or port.len > 0;
        if (self.reg_sel == 0) return false;
        const m = self.machines.items[self.reg_sel];
        const same_port = std.fmt.parseInt(u16, port, 10) catch null;
        return !std.mem.eql(u8, addr, m.address) or same_port == null or same_port.? != m.port;
    }

    /// The Select button is on when the row selected is a registered machine other than the one in use.
    pub fn regCanSelect(self: *const App) bool {
        return self.reg_sel < self.machines.items.len and self.reg_sel != self.machine;
    }

    /// Save button: add the new machine at the end of the list, or change the selected one.
    fn regSave(self: *App) void {
        if (!self.regDirty()) return;
        const addr = self.fieldText(&self.reg_addr);
        const port_text = self.fieldText(&self.reg_port);
        if (addr.len == 0 or std.mem.indexOfAny(u8, addr, " \t") != null) {
            self.setMessage("address: a name or an IP number, without spaces", .{});
            return;
        }
        const port = std.fmt.parseInt(u16, port_text, 10) catch 0;
        if (port == 0) {
            self.setMessage("port: a number from 1 to 65535", .{});
            return;
        }
        for (self.machines.items[1..], 1..) |m, i| {
            if (i != self.reg_sel and m.port == port and std.mem.eql(u8, m.address, addr)) {
                self.setMessage("{s}:{d} is already registered", .{ addr, port });
                return;
            }
        }
        if (self.reg_sel >= self.machines.items.len) {
            self.machineAdd(addr, port, null) catch {
                self.setMessage("out of memory", .{});
                return;
            };
            self.reg_sel = self.machines.items.len - 1;
        } else {
            const old = self.machines.items[self.reg_sel];
            const new_addr = self.gpa.dupe(u8, addr) catch return;
            const new_label = std.fmt.allocPrint(self.gpa, "{s}:{d}", .{ addr, port }) catch {
                self.gpa.free(new_addr);
                return;
            };
            old.free(self.gpa);
            self.machines.items[self.reg_sel] = .{ .label = new_label, .address = new_addr, .port = port };
        }
        self.saveMachines();
        self.regLoad();
        self.setMessage("registered {s}", .{self.machines.items[self.reg_sel].label});
    }

    /// Select button: use the machine of the selected row, and close the form (nothing is saved).
    fn regSelect(self: *App) void {
        if (!self.regCanSelect()) return;
        self.pickMachine(self.reg_sel);
        self.overlay = .none;
    }

    /// Move the selected row of the table by `delta` (the last row is the new machine).
    fn regMove(self: *App, delta: isize) void {
        const rows: isize = @intCast(self.machines.items.len + 1);
        const now: isize = @intCast(self.reg_sel);
        self.reg_sel = @intCast(std.math.clamp(now + delta, 0, rows - 1));
        self.regLoad();
    }

    /// The keys of the registration form: Up and Down choose the row, Tab the field, Enter saves, text goes to the field.
    fn regKey(self: *App, key: Key) !void {
        if (key.matches(Key.up, .{})) return self.regMove(-1);
        if (key.matches(Key.down, .{})) return self.regMove(1);
        if (key.matches(Key.tab, .{})) {
            self.dlg_field = 1 - self.dlg_field;
            return;
        }
        if (key.matches(Key.enter, .{})) return if (self.regDirty()) self.regSave() else self.regSelect();
        if (self.reg_sel == 0) return;
        const ti = if (self.dlg_field == 0) &self.reg_addr else &self.reg_port;
        try ti.update(.{ .key_press = key });
    }

    // Zig tip: `switch (self.overlay)` on an enum, with `.none => {}` for the value that needs
    // nothing. An `if` chain with `else if` works as well, but the `switch` lists every case.
    fn overlayKey(self: *App, key: Key) !void {
        if (key.matches(Key.escape, .{})) return self.closeOverlay();
        if (self.overlay != .menu and self.overlay != .tab_menu and self.overlay != .machine_menu and self.overlay != .register and self.overlay != .confirm and self.overlay != .structure and self.overlay != .sq_structure and self.overlay != .new_table and self.overlay != .new_file and self.overlay != .wizard and self.overlay != .append_n and self.searchShortcut(key)) return;
        switch (self.overlay) {
            .menu => try self.menuKey(key),
            .tab_menu => {
                const n = tab_menu_rows.len;
                if (key.matches(Key.up, .{})) {
                    self.tab_menu_sel = (self.tab_menu_sel + n - 1) % n;
                } else if (key.matches(Key.down, .{})) {
                    self.tab_menu_sel = (self.tab_menu_sel + 1) % n;
                } else if (key.matches(Key.enter, .{})) try self.runTabMenu(self.tab_menu_sel);
            },
            .machine_menu => {
                const n = self.machines.items.len + 1; // the machines, then Register…
                if (key.matches(Key.up, .{})) {
                    self.mm_sel = (self.mm_sel + n - 1) % n;
                } else if (key.matches(Key.down, .{})) {
                    self.mm_sel = (self.mm_sel + 1) % n;
                } else if (key.matches(Key.enter, .{})) {
                    self.overlay = .none;
                    if (self.mm_sel >= self.machines.items.len) self.openRegister() else self.pickMachine(self.mm_sel);
                }
            },
            .register => try self.regKey(key),
            .new_file => {
                if (key.matches(Key.enter, .{})) try self.newFromName() else try self.saveas_in.update(.{ .key_press = key });
            },
            .wizard => try self.wizardKey(key),
            .append_n => {
                if (key.matches(Key.enter, .{})) try self.appendNEnter() else try self.goto_in.update(.{ .key_press = key });
            },
            .structure => try self.structureKey(key),
            .sq_structure => try self.sqKey(key),
            .new_table => {
                if (key.matches(Key.enter, .{})) {
                    const raw = try self.saveas_in.toOwnedContents(self.gpa);
                    defer self.gpa.free(raw);
                    self.overlay = .none;
                    try self.createTableNamed(std.mem.trim(u8, raw, " "));
                } else try self.saveas_in.update(.{ .key_press = key });
            },
            .confirm => {
                if (key.matches('y', .{}) or key.matches('Y', .{ .shift = true }) or key.matches(Key.enter, .{})) {
                    self.confirmYes();
                } else if (key.matches('n', .{}) or key.matches('N', .{ .shift = true })) self.overlay = .none;
            },
            .settings => try self.optionsKey(key),
            .about => {
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
    // Zig tip: the cell that is selected is `row` and `col`; the view moves `top` and `left` so it stays on the screen.
    // `-|` and `+|` are saturating: they stop at 0 or at the largest number instead of failing.
    /// The keys of a DBF table: arrows move the cell, Page Up and Down a page, Home and End the first and last record.
    fn tableKey(self: *App, tv: *TableView, key: Key) !void {
        if (self.tbl_editing) {
            if (key.matches(Key.enter, .{})) return self.commitCell(tv);
            if (key.matches(Key.escape, .{})) {
                self.tbl_editing = false;
                return;
            }
            try self.tbl_edit.update(.{ .key_press = key });
            return;
        }
        const rows = tv.t.records;
        const cols = tv.t.fields.len;
        const page: usize = 15;
        if (key.matches(Key.enter, .{})) return self.dataEdit();
        if (key.matches(Key.insert, .{})) return self.dataAppend(1);
        if (key.matches(Key.delete, .{})) return self.dataDelete();
        if (key.matches(Key.up, .{})) tv.row -|= 1 else if (key.matches(Key.down, .{})) tv.row = @min(tv.row + 1, rows -| 1) else if (key.matches(Key.left, .{})) tv.col -|= 1 else if (key.matches(Key.right, .{})) tv.col = @min(tv.col + 1, cols -| 1) else if (key.matches(Key.page_up, .{})) tv.row -|= page else if (key.matches(Key.page_down, .{})) tv.row = @min(tv.row + page, rows -| 1) else if (key.matches(Key.home, .{})) tv.row = 0 else if (key.matches(Key.end, .{})) tv.row = rows -| 1 else if (key.matches(Key.home, .{ .ctrl = true })) tv.col = 0 else if (key.matches(Key.end, .{ .ctrl = true })) tv.col = cols -| 1;
    }

    /// The keys of the editor: moving (Shift extends the selection), typing, copy and paste.
    fn editorKey(self: *App, key: Key) !void {
        if (self.activeTab()) |t| {
            if (t.table) |tv| return self.tableKey(tv, key);
            if (t.folder) |fv| return self.folderListKey(fv, key);
            if (t.render) return self.mdKey(t, key);
        }
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
            b.last_edit = .none;
            return;
        }
        if (key.matches(Key.escape, .{})) {
            b.anchor = null;
            return;
        }
        if (ro) return;
        const selected = b.selection() != null;
        if (key.matches(Key.enter, .{})) {
            try b.checkpoint(.other);
            _ = try b.deleteSelection();
            try b.newline();
        } else if (key.matches(Key.backspace, .{})) {
            try b.checkpoint(if (selected) .other else .erasing);
            if (!try b.deleteSelection()) try b.backspace();
        } else if (key.matches(Key.delete, .{})) {
            try b.checkpoint(if (selected) .other else .erasing);
            if (!try b.deleteSelection()) try b.delete();
        } else if (key.matches(Key.tab, .{})) {
            try b.checkpoint(if (selected) .other else .typing);
            _ = try b.deleteSelection();
            try b.insert("  ");
        } else if (key.mods.ctrl or key.mods.alt) {
            // a shortcut that is not ours: do not type its letter; say so
            self.unknownShortcut(key);
        } else if (key.text) |t| {
            try b.checkpoint(if (selected) .other else .typing);
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
        if (cut and !self.activeTab().?.virtual) {
            try b.checkpoint(.other);
            _ = try b.deleteSelection();
        }
    }

    /// Ctrl+V: insert the copied text. (A paste made by the terminal comes as keys: see `pasteEnd`.)
    fn pasteClip(self: *App) !void {
        const b = self.activeBuffer() orelse return;
        if (self.activeTab().?.virtual) return;
        const c = self.clip orelse {
            self.setMessage("nothing copied yet", .{});
            return;
        };
        try b.checkpoint(.other);
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
        if (self.overlay != .none or self.focus == .console or self.focus == .sql) {
            const ti: ?*TextInput = switch (self.overlay) {
                .none => if (self.focus == .sql) &self.sql_in else &self.console_in,
                .goto => &self.goto_in,
                .save_as, .new_file, .new_table => &self.saveas_in,
                .wizard => &self.wiz_name,
                .append_n => &self.goto_in,
                .find_text => &self.find_in,
                .find_file => &self.files_in,
                .replace => if (self.dlg_field == 0) &self.find_in else &self.replace_in,
                .register => if (self.reg_sel == 0) null else if (self.dlg_field == 0) &self.reg_addr else &self.reg_port,
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
            try b.checkpoint(.other);
            try b.insertText(t);
        }
    }

    // Zig tip: `self.selected = rows[pos -| 10]` uses `-|`, the subtraction that stops at zero instead
    // of failing on an unsigned number that would go below zero. `+|` does the same for the top.
    fn treeKey(self: *App, key: Key) !void {
        self.tree_follow = true;
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
            if (e.kind == .db and !e.expanded) {
                e.expanded = true;
                try self.loadDbTables(self.selected);
            }
        } else if (key.matches(Key.left, .{})) {
            if ((e.is_dir or e.kind == .db) and e.expanded and e.parent != null) e.expanded = false else if (e.parent) |p| self.selected = p;
        } else if (key.matches(Key.enter, .{}) or key.matches(Key.space, .{})) {
            try self.openEntry(self.selected);
        } else if (key.matches(Key.page_up, .{})) {
            self.selected = rows[pos -| 10];
        } else if (key.matches(Key.page_down, .{})) {
            self.selected = rows[@min(pos + 10, rows.len - 1)];
        } else if (key.mods.ctrl or key.mods.alt) {
            self.unknownShortcut(key);
        }
    }

    // Zig tip: `const e = &self.tree.entries.items[index];` is a pointer to the entry, so `e.expanded
    // = !e.expanded` changes the tree itself and not a copy.
    pub fn openEntry(self: *App, index: u32) !void {
        const e = &self.tree.entries.items[index];
        self.selected = index;
        self.tree_follow = true;
        if (e.kind == .table) return self.openFile(e.path);
        if (e.kind == .db) {
            e.expanded = !e.expanded;
            if (e.expanded) try self.loadDbTables(index);
            return;
        }
        if (e.is_dir) {
            if (e.parent != null) e.expanded = !e.expanded;
            // the folder that is clicked becomes the working folder of the console, and its content fills the Main Panel
            try self.enterFolder(e.path);
            const folder_path = try self.gpa.dupe(u8, e.path);
            defer self.gpa.free(folder_path);
            try self.showFolder(folder_path);
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

    // Zig tip: the word before the cursor is cut at the last space; if it holds a `/` or `\`, what comes before the last one
    // is the folder to look in and what comes after is the beginning of the name. `first` is a slice of the text field,
    // and the completion inserts only the letters that are still missing, so the user's own letters (and their case) stay.
    // The names found are copied (`dupe`) before the directory is closed, and freed by the `defer` loop.
    /// Tab in the console: complete the file or folder name that starts with the letters before the cursor. One match is
    /// completed (a folder gets a `/`), several are completed as far as they agree and listed in the console.
    fn consoleComplete(self: *App) !void {
        const gpa = self.gpa;
        const first = self.console_in.buf.firstHalf();
        var start: usize = first.len;
        while (start > 0 and first[start - 1] != ' ') start -= 1;
        const word = first[start..];
        const sep_at = std.mem.lastIndexOfAny(u8, word, "/\\");
        const dir_part = if (sep_at) |i| word[0 .. i + 1] else "";
        const prefix = if (sep_at) |i| word[i + 1 ..] else word;
        const base = self.work_dir orelse (if (self.root.len == 0) "." else self.root);
        const dir_path = if (dir_part.len > 0 and std.fs.path.isAbsolute(dir_part))
            try gpa.dupe(u8, dir_part)
        else if (dir_part.len > 0)
            try std.fmt.allocPrint(gpa, "{s}/{s}", .{ base, dir_part })
        else
            try gpa.dupe(u8, base);
        defer gpa.free(dir_path);
        var dir = Io.Dir.cwd().openDir(self.io, dir_path, .{ .iterate = true }) catch return;
        defer dir.close(self.io);
        const Match = struct { name: []u8, is_dir: bool };
        var found: std.ArrayList(Match) = .empty;
        defer {
            for (found.items) |m| gpa.free(m.name);
            found.deinit(gpa);
        }
        var it = dir.iterate();
        while (it.next(self.io) catch null) |e| {
            if (e.name.len < prefix.len or !std.ascii.eqlIgnoreCase(e.name[0..prefix.len], prefix)) continue;
            const copy = gpa.dupe(u8, e.name) catch break;
            found.append(gpa, .{ .name = copy, .is_dir = e.kind == .directory }) catch {
                gpa.free(copy);
                break;
            };
        }
        if (found.items.len == 0) {
            self.setMessage("no file or folder starts with '{s}'", .{prefix});
            return;
        }
        std.mem.sort(Match, found.items, {}, struct {
            fn less(_: void, a: Match, b: Match) bool {
                return std.ascii.lessThanIgnoreCase(a.name, b.name);
            }
        }.less);
        // the longest start that all the names share
        var common: usize = found.items[0].name.len;
        for (found.items[1..]) |m| {
            var k: usize = 0;
            while (k < common and k < m.name.len and std.ascii.toLower(m.name[k]) == std.ascii.toLower(found.items[0].name[k])) k += 1;
            common = k;
        }
        if (common > prefix.len) {
            try self.console_in.insertSliceAtCursor(found.items[0].name[prefix.len..common]);
        }
        if (found.items.len == 1) {
            if (found.items[0].is_dir) try self.console_in.insertSliceAtCursor("/");
            return;
        }
        if (common > prefix.len) return;
        // nothing more to add: show what there is
        var line: std.ArrayList(u8) = .empty;
        defer line.deinit(gpa);
        for (found.items) |m| {
            try line.appendSlice(gpa, m.name);
            if (m.is_dir) try line.append(gpa, '/');
            try line.appendSlice(gpa, "  ");
        }
        try self.console.add(gpa, std.mem.trimEnd(u8, line.items, " "), .info);
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
        if (key.matches(Key.tab, .{})) return self.consoleComplete();
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
            self.askConfirm(.delete_breakpoint, self.break_sel, "Remove the breakpoint {s}:{d}?", .{ self.breakpoints.items[self.break_sel].path, self.breakpoints.items[self.break_sel].line });
        } else if (key.matches(' ', .{})) self.toggleBreakpointEnabled(self.break_sel);
    }

    // ------------------------------------------------------------ the mouse

    // Zig tip: `m.type != .press` compares an enum value. The `while (i > 0) { i -= 1; ... }` loop
    // walks the hits from the last to the first, so what was drawn last (an open menu) is hit first.
    pub fn onMouse(self: *App, m: vaxis.Mouse) !void {
        if (m.type == .motion) return self.hover(m);
        if (m.type == .release) {
            if (self.tdrag_src != null) try self.treeRelease();
            self.drag = .none;
            // three seconds after the release the layout freezes by itself
            if (self.modify and self.mouse_modify) self.freeze_at = self.nowMs() + 3000;
            return;
        }
        if (m.type == .drag) {
            if (self.tdrag_src != null) {
                self.treeDragTo(m);
                return;
            }
            self.freeze_at = null;
            return self.dragTo(m);
        }
        self.alt_hint = false;
        self.freeze_at = null;
        if (m.button == .wheel_up or m.button == .wheel_down) {
            const up = m.button == .wheel_up;
            self.follow = false;
            if (self.tree_rect.contains(m.col, m.row)) {
                self.tree_follow = false;
                self.tree_top = if (up) self.tree_top -| 3 else self.tree_top + 3;
            } else if (self.tbl_rect.contains(m.col, m.row)) {
                if (self.activeTab()) |t| {
                    if (t.table) |tv| tv.top = if (up) tv.top -| 3 else @min(tv.top + 3, tv.t.records -| 1);
                }
            } else if (self.editor_rect.contains(m.col, m.row)) {
                if (self.activeTab()) |t| {
                    if (t.folder) |fv| {
                        fv.top = if (up) fv.top -| 3 else @min(fv.top + 3, fv.items.items.len -| 1);
                        return;
                    }
                    if (t.render) {
                        t.render_top = if (up) t.render_top -| 3 else t.render_top + 3;
                        return;
                    }
                }
                if (self.activeBuffer()) |b| b.top = if (up) b.top -| 3 else @min(b.top + 3, b.lineCount() - 1);
            } else if (self.console_rect.contains(m.col, m.row)) {
                const log = self.shownLog();
                log.scroll = if (up) log.scroll +| 3 else log.scroll -| 3;
            }
            return;
        }
        if (m.button == .right and self.overlay == .none) {
            // a right click on a tab opens its popup menu
            var k = self.hits.items.len;
            while (k > 0) {
                k -= 1;
                const h = self.hits.items[k];
                if (h.rect.contains(m.col, m.row)) {
                    switch (h.action) {
                        .tab, .tab_close => |t| self.openTabMenu(t, m),
                        else => {},
                    }
                    return;
                }
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
            if (self.grabSplit(m)) {
                // a press on a border starts Layout modify; a layout already in modify keeps how it was started
                if (!self.modify) self.startModify(true);
                return;
            }
            if (self.grabBar(m)) return;
            if (self.gutter_rect.contains(m.col, m.row)) {
                if (self.activeBuffer()) |b| {
                    const rel: usize = @intCast(@as(i32, m.row) - self.gutter_rect.y);
                    if (self.lineAtRow(b, rel)) |ln| try self.toggleBreakpointAt(ln + 1);
                    return;
                }
            }
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
                    b.last_edit = .none;
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
            if (h.rect.contains(m.col, m.row)) {
                if (h.action == .tree_row) return self.treePress(h.action.tree_row, m);
                return self.activate(h.action);
            }
        }
        if (self.overlay != .none) return self.closeOverlay();
        if (self.tbl_rect.contains(m.col, m.row)) {
            if (self.activeTab()) |t| {
                if (t.table) |tv| {
                    self.focus = .editor;
                    self.clickTable(tv, m);
                    return;
                }
            }
        }
        if (self.console_rect.contains(m.col, m.row) and self.bottom == .console) {
            self.focus = .console;
        } else if (self.console_rect.contains(m.col, m.row) and self.bottom == .sql) {
            self.focus = .sql;
        }
    }

    // Zig tip: the column under the mouse is found by adding up the widths of the columns from the first one shown, the
    // way the view draws them: a row number column, then each field with one cell between.
    /// A click on the grid of a DBF table: select the record and the field under the pointer.
    fn clickTable(self: *App, tv: *TableView, m: vaxis.Mouse) void {
        const r = self.tbl_rect;
        const row = tv.top + @as(usize, @intCast(@as(i32, m.row) - r.y));
        if (row < tv.t.records) tv.row = row;
        var x: i32 = @as(i32, r.x) + dbf_rownum_w;
        var c = tv.left;
        while (c < tv.t.fields.len) : (c += 1) {
            const w: i32 = dbf.displayWidth(&tv.t.fields[c]) + 1;
            if (m.col >= x and m.col < x + w) {
                tv.col = c;
                return;
            }
            x += w;
        }
    }

    // ------------------------------------------------------------ marks and moving files in the tree

    pub fn isMarked(self: *const App, path: []const u8) bool {
        for (self.marks.items) |p| {
            if (std.mem.eql(u8, p, path)) return true;
        }
        return false;
    }

    fn clearMarks(self: *App) void {
        for (self.marks.items) |p| self.gpa.free(p);
        self.marks.clearRetainingCapacity();
    }

    // Zig tip: a press on a row does not open it yet: the row may be the start of a drag. `tdrag_src` remembers it; the
    // release without any drag opens it (`treeRelease`), the release after a drag drops it on the row under the pointer.
    // Ctrl+click is different: it marks or unmarks the file, so several can be moved together.
    /// A press on a row of the tree.
    fn treePress(self: *App, idx: u32, m: vaxis.Mouse) !void {
        self.focus = .tree;
        const e = self.tree.entries.items[idx];
        if (m.mods.ctrl) {
            self.selected = idx;
            if (e.parent == null) return;
            for (self.marks.items, 0..) |p, i| {
                if (std.mem.eql(u8, p, e.path)) {
                    self.gpa.free(p);
                    _ = self.marks.orderedRemove(i);
                    return;
                }
            }
            try self.marks.append(self.gpa, try self.gpa.dupe(u8, e.path));
            return;
        }
        if (e.kind == .table) {
            // a table of a database is opened, never dragged
            self.clearMarks();
            self.selected = idx;
            try self.openEntry(idx);
            return;
        }
        if (!self.isMarked(e.path)) self.clearMarks();
        self.selected = idx;
        self.tdrag_src = idx;
        self.tdrag_active = false;
        self.tdrag_over = null;
    }

    /// The row of the tree under the pointer, or null.
    fn treeRowAt(self: *const App, m: vaxis.Mouse) ?u32 {
        if (!self.tree_rect.contains(m.col, m.row)) return null;
        const k = self.tree_top + @as(usize, @intCast(@as(i32, m.row) - self.tree_rect.y));
        if (k >= self.visible.items.len) return null;
        return self.visible.items[k];
    }

    fn treeDragTo(self: *App, m: vaxis.Mouse) void {
        self.tdrag_active = true;
        self.tdrag_over = self.treeRowAt(m);
    }

    // Zig tip: the folder that receives the files is the row under the pointer if it is a folder, else the folder of that
    // file. The files to move are the marked ones if the dragged row is marked, else just the dragged row. A file whose
    // folder is already the target, and a folder dropped into itself, are left out; if nothing is left, nothing happens.
    /// The button was released: open the row (no drag), or ask whether to move the files to the folder under the pointer.
    fn treeRelease(self: *App) !void {
        const src = self.tdrag_src orelse return;
        const active = self.tdrag_active;
        const over = self.tdrag_over;
        self.tdrag_src = null;
        self.tdrag_active = false;
        self.tdrag_over = null;
        if (!active) {
            self.clearMarks();
            return self.openEntry(src);
        }
        const target = over orelse return;
        const te = self.tree.entries.items[target];
        const dest = if (te.is_dir) te.path else (std.fs.path.dirname(te.path) orelse "");
        const dragged = self.tree.entries.items[src].path;
        for (self.move_srcs.items) |p| self.gpa.free(p);
        self.move_srcs.clearRetainingCapacity();
        const use_marks = self.isMarked(dragged);
        if (use_marks) {
            for (self.marks.items) |p| try self.addMoveSource(p, dest);
        } else if (self.tree.entries.items[src].parent != null) {
            try self.addMoveSource(dragged, dest);
        }
        if (self.move_srcs.items.len == 0) return;
        if (self.move_dest) |old| self.gpa.free(old);
        self.move_dest = try self.gpa.dupe(u8, dest);
        const shown: []const u8 = if (dest.len == 0) "the project folder" else dest;
        if (self.move_srcs.items.len == 1) {
            self.askConfirm(.move_files, 0, "Move {s} to {s}?", .{ self.move_srcs.items[0], shown });
        } else {
            self.askConfirm(.move_files, 0, "Move {d} files to {s}?", .{ self.move_srcs.items.len, shown });
        }
    }

    fn addMoveSource(self: *App, path: []const u8, dest: []const u8) !void {
        const parent = std.fs.path.dirname(path) orelse "";
        if (std.mem.eql(u8, parent, dest)) return;
        if (std.mem.eql(u8, path, dest)) return;
        if (dest.len > path.len and std.mem.startsWith(u8, dest, path) and dest[path.len] == '/') return;
        try self.move_srcs.append(self.gpa, try self.gpa.dupe(u8, path));
    }

    // Zig tip: `Io.Dir.rename(dir, old, dir, new, io)` moves a file or a folder inside one file system. A name that exists
    // in the target is never overwritten: that file is skipped and counted. The paths of the open tabs and of the
    // breakpoints that were inside the moved path follow it, so nothing points to a file that is gone.
    /// Yes of the move dialog: move the files, then fix the tabs, the breakpoints and the tree.
    fn performMove(self: *App) void {
        const dest = self.move_dest orelse return;
        var moved: usize = 0;
        var skipped: usize = 0;
        for (self.move_srcs.items) |src| {
            const base = std.fs.path.basename(src);
            const new_rel = if (dest.len == 0) self.gpa.dupe(u8, base) catch continue else std.fmt.allocPrint(self.gpa, "{s}/{s}", .{ dest, base }) catch continue;
            defer self.gpa.free(new_rel);
            const old_full = self.fullPath(src) catch continue;
            defer self.gpa.free(old_full);
            const new_full = self.fullPath(new_rel) catch continue;
            defer self.gpa.free(new_full);
            if (Io.Dir.cwd().statFile(self.io, new_full, .{})) |_| {
                skipped += 1;
                continue;
            } else |_| {}
            Io.Dir.rename(Io.Dir.cwd(), old_full, Io.Dir.cwd(), new_full, self.io) catch {
                skipped += 1;
                continue;
            };
            moved += 1;
            self.retarget(src, new_rel);
        }
        self.clearMarks();
        self.refreshTree();
        self.saveSession() catch {};
        if (skipped > 0) self.setMessage("moved {d}, {d} skipped (the name exists in the folder)", .{ moved, skipped }) else self.setMessage("moved {d} file(s)", .{moved});
    }

    /// A file or folder was moved from `old` to `new`: open tabs and breakpoints inside it get the new path.
    fn retarget(self: *App, old: []const u8, new: []const u8) void {
        for (self.tabs.items) |*t| {
            const np = self.movedPath(t.path, old, new) orelse continue;
            self.gpa.free(t.path);
            t.path = np;
        }
        for (self.breakpoints.items) |*b| {
            const np = self.movedPath(b.path, old, new) orelse continue;
            self.gpa.free(b.path);
            b.path = np;
        }
    }

    fn movedPath(self: *App, path: []const u8, old: []const u8, new: []const u8) ?[]u8 {
        if (std.mem.eql(u8, path, old)) return self.gpa.dupe(u8, new) catch null;
        if (path.len > old.len and std.mem.startsWith(u8, path, old) and path[old.len] == '/') {
            return std.fmt.allocPrint(self.gpa, "{s}{s}", .{ new, path[old.len..] }) catch null;
        }
        return null;
    }

    // Zig tip: `a != b` works on optionals too: two `?Drag` are equal when both are null or both hold the same value.
    // The border under the pointer is a candidate; it becomes active (`hover_split`) when the layout is unlocked, or when
    // the pointer has rested on it for `hover_delay_s` seconds. `tick` calls this again, so no mouse move is needed.
    /// Decide whether the border under the pointer is active, and set the shape of the pointer.
    fn refreshHover(self: *App) void {
        const cand = self.hover_cand orelse {
            self.hover_split = null;
            self.pointer = .default;
            return;
        };
        const waited = self.nowMs() - self.hover_since;
        const ready = self.modify or waited >= @as(i64, self.options.hover_delay_s) * 1000;
        self.hover_split = if (ready) cand else null;
        self.pointer = if (!ready) .default else if (cand == .tree_split) .@"ew-resize" else .@"ns-resize";
    }

    /// The lock of the toolbar: locked means the layout is frozen; unlocked it can be modified (Window > Layout modify).
    pub fn toggleLock(self: *App) void {
        if (self.modify) self.freezeLayout() else self.startModify(false);
    }

    // Zig tip: A `motion` event arrives when the mouse moves. Only an open menu cares: the row or
    // the menu title under the pointer becomes the selected one, as in a classic menu.
    fn hover(self: *App, m: vaxis.Mouse) void {
        if (self.overlay == .none) {
            // over a border between panels the pointer is a double arrow, once it has rested there for the hover delay
            const cand = self.splitAt(m);
            if (cand != self.hover_cand) {
                self.hover_cand = cand;
                self.hover_since = self.nowMs();
            }
            self.refreshHover();
            return;
        }
        self.hover_cand = null;
        self.hover_split = null;
        self.pointer = .default;
        if (self.overlay != .menu and self.overlay != .tab_menu and self.overlay != .machine_menu) return;
        var i = self.hits.items.len;
        while (i > 0) {
            i -= 1;
            const h = self.hits.items[i];
            if (!h.rect.contains(m.col, m.row)) continue;
            switch (h.action) {
                .menu_top => |t| if (t != self.menu_top) self.openMenu(t),
                .menu_item => |r| self.menu_sel = r,
                .tabmenu_item => |r| self.tab_menu_sel = r,
                .machinemenu_item => |r| self.mm_sel = r,
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
                self.focus = if (self.tabs.items[i].buf != null or self.tabs.items[i].table != null) .editor else .tree;
            },
            .tab_close => |i| self.closeTab(i),
            .bottom => |t| {
                self.bottom = t;
                self.focus = switch (t) {
                    .console => .console,
                    .breaks => .breaks,
                    .sql => .sql,
                    else => self.focus,
                };
            },
            .machine_open => |p| self.openMachineMenu(p.x, p.y),
            .register_open => self.openRegister(),
            .view_toggle => self.toggleView(),
            .folder_row => |i| {
                self.focus = .editor;
                const t = self.activeTab() orelse return;
                const fv = t.folder orelse return;
                if (fv.sel == i) try self.openFolderItem(fv, i) else fv.sel = i;
            },
            .folder_scroll => |d| {
                const t = self.activeTab() orelse return;
                const fv = t.folder orelse return;
                switch (d) {
                    .up => fv.top -|= 8,
                    .down => fv.top = @min(fv.top + 8, fv.items.items.len -| 1),
                    else => {},
                }
            },
            .md_scroll => |d| {
                if (self.activeTab()) |t| switch (d) {
                    .up => t.render_top -|= 8,
                    .down => t.render_top += 8,
                    else => {},
                };
            },
            .log_scroll => |d| {
                const log = self.shownLog();
                const half = @max(1, self.console_rect.h / 2);
                switch (d) {
                    .up => log.scroll +|= half,
                    .down => log.scroll -|= half,
                    else => {},
                }
            },
            .break_scroll => |d| switch (d) {
                .up => self.break_top -|= 3,
                .down => self.break_top += 3,
                else => {},
            },
            .machinemenu_item => |i| {
                self.overlay = .none;
                if (i >= self.machines.items.len) self.openRegister() else self.pickMachine(i);
            },
            .reg_row => |i| {
                self.reg_sel = i;
                self.regLoad();
            },
            .reg_btn => |b| switch (b) {
                .save => self.regSave(),
                .select => self.regSelect(),
            },
            .menu_top => |t| {
                if (self.overlay == .menu and self.menu_top == t) self.overlay = .none else self.openMenu(t);
            },
            .menu_item => |i| {
                const row = self.rowAt(self.menu_top, i);
                if (row.cmd) |c| try self.runMenu(c, row.arg);
            },
            .dlg_field => |f| self.dlg_field = f,
            .nop => {},
            .lock_toggle => self.toggleLock(),
            .opt => |o| self.optAction(o),
            .tabmenu_item => |i| try self.runTabMenu(i),
            .tree_scroll => |d| {
                const half = @max(1, self.tree_rect.h / 2);
                switch (d) {
                    .left => self.tree_left -|= 10,
                    .right => self.tree_left += 10,
                    .up => self.tree_top -|= half,
                    .down => self.tree_top += half,
                }
            },
            .table_scroll => |d| {
                if (self.activeTab()) |t| {
                    if (t.table) |tv| switch (d) {
                        .up => tv.top -|= 8,
                        .down => tv.top = @min(tv.top + 8, tv.t.records -| 1),
                        .left => tv.left -|= 1,
                        .right => tv.left = @min(tv.left + 1, tv.t.fields.len -| 1),
                    };
                }
            },
            .scroll => |d| {
                const b = self.activeBuffer() orelse return;
                self.follow = false;
                const half = @max(1, self.editor_rect.h / 2);
                switch (d) {
                    .left => b.left -|= 10,
                    .right => b.left = @min(b.left + 10, self.hbar_content -| self.editor_rect.w),
                    .up => b.top -|= half,
                    .down => b.top = @min(b.top + half, b.lineCount() - 1),
                }
            },
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
            .wiz_choice => |i| self.wiz_choice = i,
            .sq_cell => |c| {
                self.sq_row = c.row;
                self.sq_col = c.col;
                self.sq_drop = false;
                if (self.sq_editing) self.sq_editing = false;
                if (c.col == 2 or c.col == 3) self.sqStartEdit() catch {};
            },
            .sq_drop_open => {
                self.sq_col = 1;
                self.sqStartEdit() catch {};
            },
            .sq_pick => |i| {
                if (i < sqlstruct.types.len) self.sq_cols.items[self.sq_row].setType(sqlstruct.types[i]);
                self.sq_drop = false;
            },
            .sq_btn => |b| switch (b) {
                .prev => self.sq_row = self.sq_row -| 10,
                .next => self.sq_row = @min(self.sq_row + 10, self.sq_cols.items.len - 1),
                .add => self.sqAdd() catch {},
                .remove => self.sqRemove(),
                .up => self.sqMove(-1),
                .down => self.sqMove(1),
                .apply => try self.sqApply(),
            },
            .st_cell => |c| {
                self.st_row = c.row;
                self.st_col = c.col;
                self.st_drop = false;
                if (self.st_editing) self.st_editing = false;
            },
            .st_drop_open => {
                self.st_col = 1;
                self.stStartEdit() catch {};
            },
            .st_pick => |k| self.stPickType(k),
            .st_btn => |b| switch (b) {
                .prev => self.st_row = self.st_row -| 10,
                .next => self.st_row = @min(self.st_row + 10, self.st_fields.items.len - 1),
                .add => self.stAdd() catch {},
                .remove => self.stRemove(),
                .up => self.stMove(-1),
                .down => self.stMove(1),
                .apply => try self.stApply(),
            },
            .break_toggle => |i| self.toggleBreakpointEnabled(i),
            .break_trash => |i| {
                if (i < self.breakpoints.items.len) self.askConfirm(.delete_breakpoint, i, "Remove the breakpoint {s}:{d}?", .{ self.breakpoints.items[i].path, self.breakpoints.items[i].line });
            },
            .clear_panel => try self.clearPanel(),
            .confirm => |yes| {
                if (yes) self.confirmYes() else self.overlay = .none;
            },
            .break_row => |i| {
                if (self.break_sel == i) try self.jumpToBreakpoint(i) else self.break_sel = i;
                self.focus = .breaks;
            },
            .close_overlay => self.closeOverlay(),
            .button => |b| switch (b) {
                .run => try self.runButton(),
                .halt => try self.haltRun(),
                .next => try self.debugCommand("next"),
                .step => try self.debugCommand("step"),
                .exit => try self.debugCommand("exit"),
                .trace => try self.debugCommand("trace"),
                .replace => try self.replaceOne(),
                .replace_all => try self.replaceEvery(),
            },
        }
    }
};
