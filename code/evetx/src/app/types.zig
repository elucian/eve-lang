//! @eve-module evetx.app.types
//! @feature F-TLS-24
//! @decision D-173
//! @see code/evetx/src/app.zig:App
//! The types of the state of evetx (focus, overlays, actions, tabs, log, run job) and the menus; `app.zig` re-exports them.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const vaxis = @import("vaxis");
const TextInput = vaxis.widgets.TextInput;
const Key = vaxis.Key;
const ide = @import("ide");
const project = ide.project;
const text = ide.text;
const grid = ide.grid;
const regex = ide.regex;
const sqlstruct = ide.sqlstruct;
const cache_mod = ide.cache;
const options_mod = @import("../options.zig");
const link_mod = ide.link;
const theme = @import("../theme.zig");

// ------------------------------------------------------------------ small types

/// Where the keyboard goes.
pub const Focus = enum { tree, editor, console, breaks, sql };

/// The five tabs of the Tools Panel.
pub const BottomTab = enum { console, watch, stderr, stdout, breaks, sql };

/// The three panels: the files tree, the windows with their editor, the console and the other tools.
pub const Panel = enum { tree, main, tools };

/// What is open over the screen, if anything.
pub const Overlay = enum { none, properties, alert, sq_structure, new_file, wizard, append_n, confirm, tab_menu, menu, settings, about, goto, save_as, find_text, find_file, replace, open_project, open_folder, filter };

/// The buttons of the tool bars.
pub const Button = enum { run, halt, next, step, exit, trace, replace, replace_all };

/// The buttons of the dialogs that are not a plain "close": `ok` does what Enter does in that dialog.
pub const DlgAction = enum { ok, forget, browse, open_here, filter_add, filter_remove };

/// The buttons of the Info dialog that are not Close.
pub const PropBtn = enum { rename, move };

/// Why the folder selector is open: Open Folder (a project), Move (a file of the Info dialog), Export or Import a theme.
pub const FbMode = enum { project, move_to, move_many, save_as, theme_export, theme_import };

/// What a click on a clickable place does (see `Hit`).
pub const Action = union(enum) {
    tree_row: u32,
    tab: usize,
    tab_close: usize,
    bottom: BottomTab,
    button: Button,
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
    /// The arrows of the scroll bars of a table.
    table_scroll: ScrollBtn,
    /// A cell of the structure grid, the buttons under it, a type of the drop-down list, and the arrow of the Type cell.
    /// A row of the list of a folder, and the arrows of its scroll bar.
    folder_row: usize,
    folder_scroll: ScrollBtn,
    /// The arrows of the scroll bar of the folder selector.
    fb_scroll: ScrollBtn,
    /// The same for the structure dialog of a SQLite table.
    sq_cell: struct { row: u16, col: u8 },
    sq_btn: StBtn,
    sq_pick: u8,
    /// The page of the dialog of a new table (0 name, 1 fields, 2 indexes) and the parts of the index page.
    sq_ix_field: u16,
    sq_ix_row: u16,
    sq_ix_unique,
    sq_ix_add,
    sq_ix_remove,
    sq_drop_open,
    /// The `<` and `>` buttons of the tab row of the Main Panel: show the tabs one place further left (-1) or right (+1).
    tab_shift: i8,
    /// The Rename and Move buttons of the Info dialog.
    prop_btn: PropBtn,
    /// A choice in the list of a wizard.
    wiz_choice: usize,
    /// The buttons of the confirmation dialog.
    confirm: bool,
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
    /// A row of the filter dialog, and the column name of a row (a click changes the column).
    filter_row: usize,
    filter_col: usize,
    /// A field of the list of Add field.
    filter_pick: usize,
};

pub const Rect = struct {
    x: u16 = 0,
    y: u16 = 0,
    w: u16 = 0,
    h: u16 = 0,

    pub fn contains(self: Rect, col: i16, row: i16) bool {
        return col >= self.x and col < self.x + self.w and row >= self.y and row < self.y + self.h;
    }
};

/// A clickable rectangle that the last drawing recorded.
pub const Hit = struct { rect: Rect, action: Action };

pub const LineKind = enum { input, out, err, info, sql, shell };
pub const LogLine = struct { text: []u8, kind: LineKind };

/// A list of lines with a scroll position, the shape of the console and of the Stdout and Stderr tabs.
pub const Log = struct {
    lines: std.ArrayList(LogLine) = .empty,
    /// How many lines the view is above the end (0 shows the end).
    scroll: usize = 0,

    pub fn add(self: *Log, gpa: std.mem.Allocator, s: []const u8, kind: LineKind) !void {
        const copy = try gpa.dupe(u8, s);
        errdefer gpa.free(copy);
        try self.lines.append(gpa, .{ .text = copy, .kind = kind });
        self.scroll = 0;
    }

    /// Add a block of text, one line for every line end.
    pub fn addBlock(self: *Log, gpa: std.mem.Allocator, bytes: []const u8, kind: LineKind) !void {
        var it = std.mem.splitScalar(u8, bytes, '\n');
        while (it.next()) |l| {
            const t = std.mem.trimEnd(u8, l, "\r");
            if (it.peek() == null and t.len == 0) break;
            try self.add(gpa, t, kind);
        }
    }

    pub fn clear(self: *Log, gpa: std.mem.Allocator) void {
        for (self.lines.items) |l| gpa.free(l.text);
        self.lines.clearRetainingCapacity();
        self.scroll = 0;
    }

    pub fn deinit(self: *Log, gpa: std.mem.Allocator) void {
        self.clear(gpa);
        self.lines.deinit(gpa);
    }
};

/// What the card of a file that is not text shows.
pub const Card = struct { kind: []const u8 = "", size: u64 = 0, note: []const u8 = "" };

/// What the Properties dialog shows about a file or a table of a SQLite file (see `App.openPropertiesOf`).
pub const Props = struct {
    kind: []const u8 = "",
    /// The folder of the file in the project, or the database file of a table (a slice of `App.rename_from`).
    place: []const u8 = "",
    size: ?u64 = null,
    /// Seconds since 1970 (UTC); 0 when unknown.
    modified: i64 = 0,
    lines: ?usize = null,
    line_ends: []const u8 = "",
    unsaved: bool = false,
    records: ?u64 = null,
    fields: ?usize = null,
    /// A view of a SQLite file cannot be renamed with `alter table`.
    is_view: bool = false,
};

/// A table opened in a tab: the table, the cell that is selected, and the first row and column shown.
/// The number of digits of the record numbers of a grid of `records` rows.
pub fn rownumDigits(records: usize) u16 {
    var n: u16 = 4;
    var v = records / 10000;
    while (v > 0) : (v /= 10) n += 1;
    return n;
}

/// The width of the left part of a grid: the selection column, the record numbers and the separator.
pub fn rownumW(records: usize) u16 {
    return 1 + rownumDigits(records) + 1;
}

pub const TableView = struct {
    t: grid.Table,
    row: usize = 0,
    col: usize = 0,
    top: usize = 0,
    left: usize = 0,
    /// A table that cannot be changed here: a view of a SQLite database, or a table the rows of which cannot be told apart.
    readonly: bool = false,
    /// The rows selected with `+`, `*` and Ctrl+click.
    sel: std.AutoArrayHashMapUnmanaged(usize, void) = .empty,
    /// A SQLite table: the real names of the columns and the `rowid` of each record.
    colnames: [][]u8 = &.{},
    rowids: []i64 = &.{},
    /// A filter window: the table it was made from, the filters (a column and a pattern each), and the records that matched
    /// (their numbers in that table, and their rowids when it is a SQLite table).
    filter_src: []u8 = &.{},
    filter_rows: []FilterRow = &.{},
    kept: []usize = &.{},
    kept_ids: []i64 = &.{},

    /// Free what the view holds besides the table itself.
    pub fn freeExtras(self: *TableView) void {
        const g = self.t.gpa;
        self.sel.deinit(g);
        for (self.colnames) |n| g.free(n);
        if (self.colnames.len > 0) g.free(self.colnames);
        if (self.rowids.len > 0) g.free(self.rowids);
        if (self.filter_src.len > 0) g.free(self.filter_src);
        for (self.filter_rows) |r| g.free(r.pat);
        if (self.filter_rows.len > 0) g.free(self.filter_rows);
        if (self.kept.len > 0) g.free(self.kept);
        if (self.kept_ids.len > 0) g.free(self.kept_ids);
    }

    pub fn release(self: *TableView) void {
        self.freeExtras();
        self.t.deinit();
    }
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
pub const Tab = struct {
    /// Relative to the project folder; empty for a new file that was never saved.
    path: []u8,
    /// Text files have a buffer; any other file has a card.
    buf: ?text.Buffer = null,
    card: Card = .{},
    eve: bool = false,
    /// An SQL file (`.sql`): the editor colors it as SQL.
    sql: bool = false,
    /// A table of a database: the Main Panel shows its records in a grid.
    table: ?*TableView = null,
    /// A folder shown as a list (a click on a folder of the tree): there is only one such tab, and it follows the clicks.
    folder: ?*FolderView = null,
    /// The name shown on the tab when it is not the name of the file (a table of a database: `shop.orders`).
    label: []u8 = &.{},
    /// A window that is not a file (Shortcuts, Manual, Tutorial): read only, never saved.
    virtual: bool = false,
    /// The window is in editing mode: Enter starts it, Esc and Save stop it. A text file cannot be typed in, and a table cannot
    /// have its cells changed, until then.
    editing: bool = false,

    pub fn title(self: Tab) []const u8 {
        if (self.label.len > 0) return self.label;
        if (self.path.len == 0) return "untitled";
        const cut = std.mem.lastIndexOfScalar(u8, self.path, '/');
        return if (cut) |i| self.path[i + 1 ..] else self.path;
    }
};

/// What a Yes of the confirmation dialog does.
/// One row of the filter dialog: a column of the table and the value or pattern its cells must match.
pub const FilterRow = struct { col: usize, pat: []u8 };

/// What the New dialog makes.
pub const NewKind = enum { file, folder, database, table_copy, import_data };

pub const Confirm = enum { none, delete_breakpoint, clear_breakpoints, move_files, apply_sqlite, drop_table, delete_file, replace_file, delete_rows };

/// A breakpoint of the editor. A breakpoint that is not enabled stays in the list but the debugger does not stop at it.
pub const Breakpoint = struct { path: []u8, line: usize, enabled: bool = true };

/// The buttons of the structure dialog.
/// The wizards of the new files that have choices to make.
pub const WizKind = enum { eve, sql };

pub const StBtn = enum { prev, next, add, remove, up, down, apply };

/// An index that the dialog of a new table will create: its name, its fields (a list separated by commas) and unique or not.
pub const IndexDef = struct {
    name: [112]u8 = undefined,
    name_len: u8 = 0,
    cols: [160]u8 = undefined,
    cols_len: u8 = 0,
    unique: bool = false,

    pub fn nameS(self: *const IndexDef) []const u8 {
        return self.name[0..self.name_len];
    }
    pub fn colsS(self: *const IndexDef) []const u8 {
        return self.cols[0..self.cols_len];
    }
};

/// The buttons under the list of themes, and the button that applies the field of Rename, Export or Import.
pub const ThemeBtn = enum { rename, remove, export_file, import_file, apply };

/// What the field under the list of themes is for (none: there is no field). Export and Import use the folder selector.
pub const OptEdit = enum { none, rename };

/// What a click in the Options dialog does.
pub const OptAction = union(enum) {
    tab: u8,
    theme: u8,
    theme_btn: ThemeBtn,
    slot: u8,
    channel: u8,
    slider: struct { ch: u8, v: u8 },
    swatch: u24,
    auto: i16,
    delay: i16,
    trace: i16,
    ok,
    defaults,
};

/// The commands of the popup menu of a tab (a right click on its title).
pub const TabCmd = enum { save, save_as, info, rename, sep, close_this, close_right, close_left, close_clean };

/// A row of the popup menu of a tab.
pub const TabMenuRow = struct { label: []const u8, cmd: TabCmd };

pub const tab_menu_rows = [_]TabMenuRow{
    .{ .label = "Save", .cmd = .save },
    .{ .label = "Save As…", .cmd = .save_as },
    .{ .label = "Info…", .cmd = .info },
    .{ .label = "Rename…", .cmd = .rename },
    .{ .label = "-", .cmd = .sep },
    .{ .label = "Close this", .cmd = .close_this },
    .{ .label = "Close right", .cmd = .close_right },
    .{ .label = "Close left", .cmd = .close_left },
    .{ .label = "Close clean", .cmd = .close_clean },
};

/// Every command of the main menu.
pub const MenuCmd = enum {
    close_window,
    close_project,
    filter_table,
    new_folder,
    new_database,
    find_files,
    replace_files,
    compact,
    open_project,
    open_folder,
    new_file,
    import_data,
    rename_file,
    delete_file,
    move_marked,
    select_all,
    select_row,
    unselect_row,
    unselect_all,
    create_table,
    drop_table,
    data_structure,
    data_append,
    data_append_n,
    data_delete,
    data_edit,
    save,
    save_all,
    next_panel,
    save_as,
    close_tab,
    quit,
    undo,
    redo,
    replace,
    toggle_wrap,
    toggle_hidden,
    close_all,
    close_clean,
    find_text,
    find_file,
    goto_line,
    query,
    run,
    check_file,
    clear_panel,
    dbg_next,
    dbg_step,
    dbg_exit,
    dbg_trace,
    stop,
    breakpoint,
    select_window,
    modify,
    freeze,
    toggle_tree,
    toggle_main,
    toggle_tools,
    window_pick,
    shortcuts,
    manual,
    tutorial,
    about,
    options,
};

/// A row of a menu: a command with its shortcut, or a separator (`cmd` null).
pub const MenuRow = struct { label: []const u8, key: []const u8 = "", cmd: ?MenuCmd = null, arg: usize = 0 };

/// A separator row.
pub const sep: MenuRow = .{ .label = "-" };

/// One menu of the bar: its name (upper case; the first letter is the Alt key) and its fixed rows.
/// The WINDOW menu has more rows after these: one for each open window (see `App.rowAt`).
pub const Menu = struct { label: []const u8, items: []const MenuRow };

/// The place of the WINDOW menu in `menus`.
pub const menu_window: usize = 4;

/// The menus of the bar, left to right. The last one (HELP) is drawn at the right side.
pub const menus = [_]Menu{
    .{ .label = "FILE", .items = &.{
        .{ .label = "New file…", .key = "Ctrl+N", .cmd = .new_file },
        .{ .label = "New folder…", .cmd = .new_folder },
        .{ .label = "New database…", .cmd = .new_database },
        sep,
        .{ .label = "Open project…", .key = "Ctrl+O", .cmd = .open_project },
        .{ .label = "Open Folder…", .key = "Ctrl+Shift+O", .cmd = .open_folder },
        .{ .label = "Locate file…", .key = "Ctrl+P", .cmd = .find_file },
        sep,
        .{ .label = "Save", .key = "Ctrl+S", .cmd = .save },
        .{ .label = "Save As…", .key = "Ctrl+Shift+S", .cmd = .save_as },
        .{ .label = "Save All", .key = "Ctrl+A", .cmd = .save_all },
        sep,
        .{ .label = "Select all", .key = "*", .cmd = .select_all },
        .{ .label = "Select", .key = "+", .cmd = .select_row },
        .{ .label = "Unselect", .key = "-", .cmd = .unselect_row },
        .{ .label = "Unselect all", .key = "/", .cmd = .unselect_all },
        sep,
        .{ .label = "Rename…", .cmd = .rename_file },
        .{ .label = "Delete…", .cmd = .delete_file },
        .{ .label = "Move…", .cmd = .move_marked },
        sep,
        .{ .label = "Close", .cmd = .close_tab },
        .{ .label = "Close project", .cmd = .close_project },
        sep,
        .{ .label = "Quit", .key = "Ctrl+Q", .cmd = .quit },
    } },
    .{ .label = "EDIT", .items = &.{
        .{ .label = "Undo", .key = "Ctrl+U", .cmd = .undo },
        .{ .label = "Redo", .key = "Ctrl+Y", .cmd = .redo },
        sep,
        .{ .label = "Wrap text", .cmd = .toggle_wrap },
        .{ .label = "Show hidden", .cmd = .toggle_hidden },
        sep,
        .{ .label = "Alter table…", .cmd = .data_structure },
        .{ .label = "Create table…", .cmd = .create_table },
        .{ .label = "Drop table…", .cmd = .drop_table },
        .{ .label = "Compact", .cmd = .compact },
        .{ .label = "Import…", .cmd = .import_data },
        sep,
        .{ .label = "Append row", .key = "Ins", .cmd = .data_append },
        .{ .label = "Append rows…", .key = "Ctrl+Ins", .cmd = .data_append_n },
        .{ .label = "Start Editing", .key = "Enter", .cmd = .data_edit },
        .{ .label = "Delete", .key = "Del", .cmd = .data_delete },
    } },
    .{ .label = "SEARCH", .items = &.{
        .{ .label = "Find…", .key = "Ctrl+F", .cmd = .find_text },
        .{ .label = "Replace…", .key = "Ctrl+H", .cmd = .replace },
        sep,
        .{ .label = "Find in files…", .cmd = .find_files },
        .{ .label = "Replace in files…", .cmd = .replace_files },
        sep,
        .{ .label = "Go to #…", .key = "Ctrl+G", .cmd = .goto_line },
        .{ .label = "Filter…", .cmd = .filter_table },
        .{ .label = "Query SQL…", .key = "F7", .cmd = .query },
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
    .{ .label = "WINDOW", .items = &.{
        .{ .label = "Next Window", .key = "Shift+Tab", .cmd = .select_window },
        .{ .label = "Next Panel", .key = "Tab", .cmd = .next_panel },
        sep,
        .{ .label = "Close Window", .key = "Ctrl+W", .cmd = .close_window },
        .{ .label = "Close All", .cmd = .close_all },
        .{ .label = "Close Clean", .cmd = .close_clean },
        sep,
        .{ .label = "Layout modify", .key = "Ctrl+L", .cmd = .modify },
        .{ .label = "Layout freeze", .key = "Ctrl+Z", .cmd = .freeze },
        sep,
        .{ .label = "Tree Panel", .key = "Alt+T", .cmd = .toggle_tree },
        .{ .label = "Main Panel", .key = "Alt+M", .cmd = .toggle_main },
        .{ .label = "Tools Panel", .key = "Alt+O", .cmd = .toggle_tools },
    } },
    .{ .label = "HELP", .items = &.{
        .{ .label = "Shortcuts", .key = "F12", .cmd = .shortcuts },
        .{ .label = "Manual", .cmd = .manual },
        .{ .label = "Tutorial", .cmd = .tutorial },
        .{ .label = "About", .cmd = .about },
        sep,
        .{ .label = "Options…", .key = "F2", .cmd = .options },
    } },
};

pub const help_shortcuts = @embedFile("help_shortcuts");
pub const help_manual = @embedFile("help_manual");
pub const help_tutorial = @embedFile("help_tutorial");

/// The places of the panels on the screen (absolute cells).
pub const Layout = struct { tree: Rect = .{}, main: Rect = .{}, debug: Rect = .{}, tools: Rect = .{} };

/// The small buttons at the ends of the scroll bars: ten columns left or right, half a page up or down.
pub const ScrollBtn = enum { left, right, up, down };

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

    pub fn destroy(self: *RunJob) void {
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

    pub fn lock(self: *RunJob) void {
        while (self.busy.cmpxchgWeak(false, true, .acquire, .monotonic) != null) std.atomic.spinLoopHint();
    }

    pub fn unlock(self: *RunJob) void {
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

    pub fn work(self: *RunJob) void {
        self.runChild() catch |err| {
            self.err_name = @errorName(err);
        };
        self.done.store(true, .release);
    }

    pub fn event(self: *RunJob, ev_text: []const u8) void {
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

    pub fn scan(self: *RunJob, data: []const u8, final: bool) void {
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

    pub fn runChild(self: *RunJob) !void {
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
pub const Drag = enum { none, tree_split, tools_split, vbar, hbar, select, tree_v, tree_h, tbl_v, tbl_h, panel_v };

/// Which panel owns the scroll bar saved in `App.pbar_rect`.
pub const PbarKind = enum { none, log, folder, breaks, fbox };

// File kinds that open a card and never an editor (D-178): images, SVG, audio, video, archives,
// documents, programs and database files.
pub const CardExt = struct { ext: []const u8, label: []const u8 };
pub const card_exts = [_]CardExt{
    .{ .ext = "png", .label = "PNG image" },          .{ .ext = "jpg", .label = "JPEG image" },
    .{ .ext = "jpeg", .label = "JPEG image" },        .{ .ext = "gif", .label = "GIF image" },
    .{ .ext = "bmp", .label = "BMP image" },          .{ .ext = "webp", .label = "WebP image" },
    .{ .ext = "ico", .label = "icon" },               .{ .ext = "svg", .label = "SVG image" },
    .{ .ext = "mp3", .label = "MP3 audio" },          .{ .ext = "wav", .label = "WAV audio" },
    .{ .ext = "flac", .label = "FLAC audio" },        .{ .ext = "ogg", .label = "Ogg audio" },
    .{ .ext = "m4a", .label = "M4A audio" },          .{ .ext = "mp4", .label = "MP4 video" },
    .{ .ext = "mkv", .label = "MKV video" },          .{ .ext = "avi", .label = "AVI video" },
    .{ .ext = "mov", .label = "MOV video" },          .{ .ext = "webm", .label = "WebM video" },
    .{ .ext = "zip", .label = "ZIP archive" },        .{ .ext = "gz", .label = "gzip archive" },
    .{ .ext = "tar", .label = "tar archive" },        .{ .ext = "7z", .label = "7-Zip archive" },
    .{ .ext = "pdf", .label = "PDF document" },       .{ .ext = "exe", .label = "program" },
    .{ .ext = "dll", .label = "library" },            .{ .ext = "db", .label = "database file" },
    .{ .ext = "duckdb", .label = "DuckDB database" }, .{ .ext = "sqlite", .label = "SQLite database" },
};

pub fn extensionOf(path: []const u8) []const u8 {
    const base = if (std.mem.lastIndexOfScalar(u8, path, '/')) |i| path[i + 1 ..] else path;
    const dot = std.mem.lastIndexOfScalar(u8, base, '.') orelse return "";
    return base[dot + 1 ..];
}

pub fn cardLabel(path: []const u8) ?[]const u8 {
    const ext = extensionOf(path);
    for (card_exts) |c| {
        if (std.ascii.eqlIgnoreCase(c.ext, ext)) return c.label;
    }
    return null;
}
