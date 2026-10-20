//! The state of evetx and what the keys and the mouse do to it. Nothing here draws: `view.zig`
//! reads this state and draws it, and records where the clickable things are (`hits`).
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const vaxis = @import("vaxis");
const TextInput = vaxis.widgets.TextInput;
const Key = vaxis.Key;

// the files that evetx shares with eveux live in code/evecm/src/ide/ (module `ide`, made by code/evetx/build.zig)
const ide = @import("ide");
const project = ide.project;
const text = ide.text;
const grid = ide.grid;
const regex = ide.regex;
const sqlstruct = ide.sqlstruct;
const cache_mod = ide.cache;
const options_mod = @import("options.zig");
const link_mod = ide.link;
const theme = @import("theme.zig");
const types = @import("app/types.zig");
const files_m = @import("app/files.zig");
const sqlite_m = @import("app/sqlite.zig");
const newfile_m = @import("app/newfile.zig");
const data_m = @import("app/data.zig");
const structure_m = @import("app/structure.zig");
const props_m = @import("app/props.zig");
const filter_m = @import("app/filter.zig");
const tables_m = @import("app/tables.zig");
const run_m = @import("app/run.zig");
const session_m = @import("app/session.zig");
const search_m = @import("app/search.zig");
const menu_m = @import("app/menu.zig");
const panels_m = @import("app/panels.zig");
const settings_m = @import("app/settings.zig");
const dialogs_m = @import("app/dialogs.zig");
const keys_m = @import("app/keys.zig");
const mouse_m = @import("app/mouse.zig");
const tree_m = @import("app/tree.zig");

pub const Focus = types.Focus;
pub const BottomTab = types.BottomTab;
pub const Panel = types.Panel;
pub const Overlay = types.Overlay;
pub const Button = types.Button;
pub const DlgAction = types.DlgAction;
pub const PropBtn = types.PropBtn;
pub const FbMode = types.FbMode;
pub const Action = types.Action;
pub const Rect = types.Rect;
pub const Hit = types.Hit;
pub const LineKind = types.LineKind;
pub const LogLine = types.LogLine;
pub const Log = types.Log;
pub const Card = types.Card;
pub const Props = types.Props;
pub const rownumDigits = types.rownumDigits;
pub const rownumW = types.rownumW;
pub const TableView = types.TableView;
pub const FolderItem = types.FolderItem;
pub const FolderView = types.FolderView;
pub const describeName = types.describeName;
pub const Tab = types.Tab;
pub const FilterRow = types.FilterRow;
pub const NewKind = types.NewKind;
pub const Confirm = types.Confirm;
pub const Breakpoint = types.Breakpoint;
pub const WizKind = types.WizKind;
pub const StBtn = types.StBtn;
pub const IndexDef = types.IndexDef;
pub const ThemeBtn = types.ThemeBtn;
pub const OptEdit = types.OptEdit;
pub const OptAction = types.OptAction;
pub const TabCmd = types.TabCmd;
pub const TabMenuRow = types.TabMenuRow;
pub const tab_menu_rows = types.tab_menu_rows;
pub const MenuCmd = types.MenuCmd;
pub const MenuRow = types.MenuRow;
pub const sep = types.sep;
pub const Menu = types.Menu;
pub const menu_window = types.menu_window;
pub const menus = types.menus;
pub const help_shortcuts = types.help_shortcuts;
pub const help_manual = types.help_manual;
pub const help_tutorial = types.help_tutorial;
pub const Layout = types.Layout;
pub const ScrollBtn = types.ScrollBtn;
pub const RunJob = types.RunJob;
pub const Drag = types.Drag;
pub const PbarKind = types.PbarKind;
pub const CardExt = types.CardExt;
pub const card_exts = types.card_exts;
pub const extensionOf = types.extensionOf;
pub const cardLabel = types.cardLabel;
// ------------------------------------------------------------------ the application

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
    /// The field under the list of themes (Rename, Export, Import) and what it is for.
    opt_edit: OptEdit = .none,
    opt_in: TextInput,
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
    /// The border under the pointer while the layout is unlocked: it is painted and can be dragged.
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
    /// The shell that started evetx: it runs `!<command>` only when the machine cannot start (the machine runs it otherwise).
    shell_exe: []u8 = &.{},
    /// The machine of the console (`eve --stdio`, link.zig), started the first time a command needs it, and the ids of
    /// its requests that are not answered yet (the toolbar shows them as running; Halt sends `vm.cancel`).
    link: ?*link_mod.Link = null,
    link_pending: std.ArrayList(u32) = .empty,
    /// The variables of the stopped program (Watch tab), the SQL panel (its input, its output, its database file),
    /// and the first breakpoint shown in the Breaks tab.
    watch_log: Log = .{},
    sql_in: TextInput,
    sql_log: Log = .{},
    sql_db: ?[]u8 = null,
    break_top: usize = 0,
    /// The structure dialog (SQL:> alter table <name>): the file, the fields being edited and as they were, the records
    /// in the file, the selected cell, the cell being edited, the type list, and the last complaint.
    /// The command waiting in the prompt belongs to the SQL panel (not the Console).
    pending_sql: bool = false,
    /// Where the grid of a table is drawn, for the mouse.
    tbl_rect: Rect = .{},
    /// The widths of the columns of the table shown, as the last drawing made them (in the frame arena; the clicks read them).
    tbl_widths: []const u16 = &.{},
    /// The tracks of the scroll bars of a table (for the mouse).
    tblv_rect: Rect = .{},
    tblh_rect: Rect = .{},
    tbl_rows: usize = 0,
    tbl_cols: usize = 0,
    /// The cell of a table that is being edited, and its text.
    tbl_editing: bool = false,
    /// The last click on a cell of a table (a second click on the same cell within 400 ms starts the editing).
    tbl_click_ms: i64 = 0,
    tbl_click_row: usize = 0,
    tbl_click_col: usize = 0,
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
    /// The dialog of a new table has three pages: 0 name and description, 1 the fields, 2 the indexes.
    sq_page: u8 = 0,
    sq_name_in: TextInput,
    sq_desc_in: TextInput,
    sq_idx: std.ArrayList(IndexDef) = .empty,
    /// The index page: the field under the cursor, the fields ticked (a bit for each, the first 64), unique, the index selected
    /// in the list, and which of the two lists has the keys (0 the fields of the new index, 1 the indexes made).
    sq_ix_cur: usize = 0,
    sq_ix_mask: u64 = 0,
    sq_ix_uniq: bool = false,
    sq_ix_sel: usize = 0,
    sq_ix_focus: u8 = 0,
    /// The table that the confirmation dialog will drop: a table of a SQLite file (file and name).
    drop_a: ?[]u8 = null,
    drop_b: ?[]u8 = null,
    /// The Properties dialog: the file it shows (a path in the project, or `db#table` for a table of a SQLite file; owned)
    /// and its facts.
    rename_from: ?[]u8 = null,
    props: Props = .{},
    /// The name of the Info dialog is a field (Rename was pressed).
    prop_editing: bool = false,
    /// The pop-up of an operation that failed: its message (owned) and the dialog that its OK goes back to.
    alert_msg: ?[]u8 = null,
    alert_back: Overlay = .none,
    /// The tab row of the Main Panel: the first tab shown, the active tab at the last drawing (a change makes the row follow
    /// the active tab), and whether tabs are hidden at the right (the `>` button is on).
    tab_first: usize = 0,
    tab_seen: usize = std.math.maxInt(usize),
    tab_more_right: bool = false,
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
    /// The file that Save As is about to replace (a path in the project), while the question is open.
    save_rel: ?[]u8 = null,
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
    /// The scroll bar of the panel that shows a log, a folder or the breakpoints, with what it scrolls (for the mouse).
    pbar_rect: Rect = .{},
    pbar_kind: PbarKind = .none,
    pbar_total: usize = 0,
    pbar_visible: usize = 0,
    /// A press on a row of the tree: did it land on the icon, and the row and time of the click before it (double click).
    tdrag_icon: bool = false,
    /// A press on a row of a folder tab (it may become a drag to the tree), and whether the row was already selected.
    fdrag: ?usize = null,
    fdrag_was_sel: bool = false,
    last_click_row: ?u32 = null,
    last_click_ms: i64 = 0,
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
    new_kind: NewKind = .file,
    /// The filter dialog: the rows (a column and a pattern), the one selected, its pattern being typed, and the table.
    flt_rows: std.ArrayList(FilterRow) = .empty,
    flt_sel: usize = 0,
    flt_in: TextInput,
    flt_src: ?[]u8 = null,
    /// The filter window that the dialog is changing (Alter filter): the new rows replace its rows.
    flt_replace: ?[]u8 = null,
    /// Alter table on a view: the name of the view that the dialog remakes.
    flt_view: ?[]u8 = null,
    /// The list of the fields that are not in the filter is open (Add field), and the one chosen in it.
    flt_pick: bool = false,
    flt_pick_sel: usize = 0,
    flt_count: u32 = 0,
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
    /// Why the folder selector is open, the dialog it goes back to, the theme files of the folder shown (Export and Import
    /// list the `.json` files after the folders), and the field of the file name.
    fb_mode: FbMode = .project,
    fb_back: Overlay = .none,
    fb_files: std.ArrayList([]u8) = .empty,
    fb_name: TextInput,

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
    frame: std.heap.ArenaAllocator,
    tree_rect: Rect = .{},
    editor_rect: Rect = .{},
    console_rect: Rect = .{},
    breaks_rect: Rect = .{},

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
            .flt_in = TextInput.init(gpa),
            .project_in = TextInput.init(gpa),
            .sql_in = TextInput.init(gpa),
            .tbl_edit = TextInput.init(gpa),
            .sq_edit = TextInput.init(gpa),
            .sq_name_in = TextInput.init(gpa),
            .sq_desc_in = TextInput.init(gpa),
            .wiz_name = TextInput.init(gpa),
            .opt_in = TextInput.init(gpa),
            .fb_name = TextInput.init(gpa),
            .cache = cache,
            .frame = .init(gpa),
        };
        // the custom themes first: the options name the theme in use
        if (self.cache.readFile("evetx-themes.json")) |bytes| {
            defer gpa.free(bytes);
            self.options.loadThemes(gpa, bytes);
        }
        if (self.cache.readFile("evetx-options.txt")) |bytes| {
            defer gpa.free(bytes);
            self.options.parse(bytes);
        }
        self.applyOptions();
        // the shell that started evetx: $SHELL when there is one (Git Bash, a Linux shell), else the Windows command shell
        const sh = env.get("SHELL") orelse (if (builtin.os.tag == .windows) env.get("COMSPEC") orelse "cmd.exe" else "sh");
        self.shell_exe = try gpa.dupe(u8, std.fs.path.basename(sh));
        if (chosen.len > 0) {
            try self.tree.scan(io, chosen, name);
            self.restoreSession();
        }
        try self.console.add(gpa, "evetx: load, parse, errors, status and help go to the machine; !<command> runs a command of the system; run <file>, --check <file>, cd <folder>, clear, exit.", .info);
        return self;
    }

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
                tv.release();
                gpa.destroy(tv);
            }
            if (t.folder) |fv| self.freeFolder(fv);
            if (t.label.len > 0) gpa.free(t.label);
            gpa.free(t.path);
        }
        self.tabs.deinit(gpa);
        self.tree.deinit();
        self.visible.deinit(gpa);
        self.watch_log.deinit(gpa);
        if (self.wiz_path) |p| gpa.free(p);
        if (self.save_rel) |p| gpa.free(p);
        if (self.sq_db) |p| gpa.free(p);
        if (self.drop_a) |p| gpa.free(p);
        if (self.rename_from) |p| gpa.free(p);
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
        if (self.confirm_msg) |c| gpa.free(c);
        if (self.shell_exe.len > 0) gpa.free(self.shell_exe);
        if (self.link) |l| l.destroy();
        self.link_pending.deinit(gpa);
        self.sql_log.deinit(gpa);
        if (self.sql_db) |d| gpa.free(d);
        for ([_]*TextInput{ &self.sq_edit, &self.sq_name_in, &self.sq_desc_in, &self.tbl_edit, &self.wiz_name, &self.opt_in, &self.fb_name, &self.sql_in, &self.files_in, &self.find_in, &self.replace_in, &self.console_in, &self.goto_in, &self.saveas_in, &self.project_in, &self.flt_in }) |ti| ti.deinit();
        self.sq_idx.deinit(gpa);
        for (self.flt_rows.items) |r| gpa.free(r.pat);
        self.flt_rows.deinit(gpa);
        if (self.flt_src) |sp| gpa.free(sp);
        if (self.flt_replace) |sp| gpa.free(sp);
        if (self.flt_view) |sp| gpa.free(sp);
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
        if (self.sys_clip) |c| gpa.free(c);
        self.paste_buf.deinit(gpa);
        self.fbClear();
        self.fb_entries.deinit(gpa);
        self.fb_files.deinit(gpa);
        if (self.alert_msg) |m| gpa.free(m);
        if (self.fb_path) |fp| gpa.free(fp);
        gpa.destroy(self);
    }

    // The name of the project: the last part of the folder's real path.
    pub fn projectName(gpa: std.mem.Allocator, io: Io, root: []const u8) ![]u8 {
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        var dir = try Io.Dir.cwd().openDir(io, root, .{});
        defer dir.close(io);
        const n = dir.realPath(io, &buf) catch return gpa.dupe(u8, "project");
        const full = buf[0..n];
        const cut = std.mem.lastIndexOfAny(u8, full, "/\\");
        return gpa.dupe(u8, if (cut) |i| full[i + 1 ..] else full);
    }

    pub fn realPathOf(gpa: std.mem.Allocator, io: Io, path: []const u8) ![]u8 {
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        var dir = try Io.Dir.cwd().openDir(io, path, .{});
        defer dir.close(io);
        const n = try dir.realPath(io, &buf);
        return gpa.dupe(u8, buf[0..n]);
    }

    // ------------------------------------------------------------ messages and paths

    /// Start a frame: forget the strings of the last one.
    pub fn beginFrame(self: *App) void {
        _ = self.frame.reset(.retain_capacity);
    }

    /// Format a string that stays valid until the end of this frame (see `frame`).
    pub fn fmt(self: *App, comptime f: []const u8, args: anytype) []const u8 {
        return std.fmt.allocPrint(self.frame.allocator(), f, args) catch "?";
    }

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

    /// The path of a file of the project, as the operating system wants it. The caller frees it.
    pub fn fullPath(self: *App, rel: []const u8) ![]u8 {
        if (self.root.len == 0 or std.mem.eql(u8, self.root, ".")) return self.gpa.dupe(u8, rel);
        return std.fmt.allocPrint(self.gpa, "{s}/{s}", .{ self.root, rel });
    }

    pub fn activeTab(self: *App) ?*Tab {
        if (self.tabs.items.len == 0) return null;
        return &self.tabs.items[@min(self.active, self.tabs.items.len - 1)];
    }

    pub fn activeBuffer(self: *App) ?*text.Buffer {
        const t = self.activeTab() orelse return null;
        if (t.buf) |*b| return b;
        return null;
    }

    // ------------------------------------------------------------ app/files.zig
    pub const openFile = files_m.openFile;
    pub const closeTab = files_m.closeTab;
    pub const newFile = files_m.newFile;
    pub const save = files_m.save;
    pub const writeTab = files_m.writeTab;
    pub const saveAs = files_m.saveAs;
    pub const freeFolder = files_m.freeFolder;
    pub const loadFolder = files_m.loadFolder;
    pub const freeFolderItems = files_m.freeFolderItems;
    pub const showFolder = files_m.showFolder;
    pub const folderItemPath = files_m.folderItemPath;
    pub const openFolderItem = files_m.openFolderItem;
    pub const folderListKey = files_m.folderListKey;
    pub const folderSelectedFile = files_m.folderSelectedFile;
    pub const adoptFolderSelection = files_m.adoptFolderSelection;
    pub const canRun = files_m.canRun;
    // ------------------------------------------------------------ app/sqlite.zig
    pub const eveText = sqlite_m.eveText;
    pub const loadDbTables = sqlite_m.loadDbTables;
    pub const buildDbOverview = sqlite_m.buildDbOverview;
    pub const showDatabase = sqlite_m.showDatabase;
    pub const readSqliteTable = sqlite_m.readSqliteTable;
    pub const reloadSqlite = sqlite_m.reloadSqlite;
    pub const sqlView = sqlite_m.sqlView;
    pub const metaCreated = sqlite_m.metaCreated;
    pub const metaTouch = sqlite_m.metaTouch;
    pub const runDb = sqlite_m.runDb;
    pub const runSql = sqlite_m.runSql;
    pub const sqlQuoted = sqlite_m.sqlQuoted;
    pub const openSqliteTable = sqlite_m.openSqliteTable;
    // ------------------------------------------------------------ app/newfile.zig
    pub const targetDir = newfile_m.targetDir;
    pub const openNewDialog = newfile_m.openNewDialog;
    pub const openTableSaveAs = newfile_m.openTableSaveAs;
    pub const likeCondition = newfile_m.likeCondition;
    pub const selectSqlFor = newfile_m.selectSqlFor;
    pub const alterView = newfile_m.alterView;
    pub const tableSaveAs = newfile_m.tableSaveAs;
    pub const openImport = newfile_m.openImport;
    pub const isImportable = newfile_m.isImportable;
    pub const importFile = newfile_m.importFile;
    pub const openNewKind = newfile_m.openNewKind;
    pub const pathInTarget = newfile_m.pathInTarget;
    pub const newFromName = newfile_m.newFromName;
    pub const writeNew = newfile_m.writeNew;
    pub const createSqlite = newfile_m.createSqlite;
    pub const openWizard = newfile_m.openWizard;
    pub const wizardChoices = newfile_m.wizardChoices;
    pub const wizardKey = newfile_m.wizardKey;
    pub const wizardCreate = newfile_m.wizardCreate;
    pub const readonlyMessage = newfile_m.readonlyMessage;
    pub const dataStructure = newfile_m.dataStructure;
    // ------------------------------------------------------------ app/data.zig
    pub const activeTable = data_m.activeTable;
    pub const dataAppend = data_m.dataAppend;
    pub const openAppendN = data_m.openAppendN;
    pub const appendNEnter = data_m.appendNEnter;
    pub const dataDelete = data_m.dataDelete;
    pub const performDeleteRows = data_m.performDeleteRows;
    pub const dataEdit = data_m.dataEdit;
    pub const saveAll = data_m.saveAll;
    pub const dataEditOrOpen = data_m.dataEditOrOpen;
    pub const commitCell = data_m.commitCell;
    // ------------------------------------------------------------ app/structure.zig
    pub const openSqStructure = structure_m.openSqStructure;
    pub const openSqStructureNew = structure_m.openSqStructureNew;
    pub const sqTypedName = structure_m.sqTypedName;
    pub const sqNameOk = structure_m.sqNameOk;
    pub const sqGoPage = structure_m.sqGoPage;
    pub const sqInfoKey = structure_m.sqInfoKey;
    pub const sqIndexColsText = structure_m.sqIndexColsText;
    pub const sqIdxAdd = structure_m.sqIdxAdd;
    pub const sqIdxRemove = structure_m.sqIdxRemove;
    pub const sqIdxToggle = structure_m.sqIdxToggle;
    pub const sqIndexKey = structure_m.sqIndexKey;
    pub const sqChanges = structure_m.sqChanges;
    pub const sqAdd = structure_m.sqAdd;
    pub const sqRemove = structure_m.sqRemove;
    pub const sqMove = structure_m.sqMove;
    pub const sqStartEdit = structure_m.sqStartEdit;
    pub const sqCommit = structure_m.sqCommit;
    pub const sqKey = structure_m.sqKey;
    pub const sqApply = structure_m.sqApply;
    pub const sqApplyNow = structure_m.sqApplyNow;
    // ------------------------------------------------------------ app/props.zig
    pub const fileTarget = props_m.fileTarget;
    pub const propsTarget = props_m.propsTarget;
    pub const openRename = props_m.openRename;
    pub const openInfo = props_m.openInfo;
    pub const openPropertiesOf = props_m.openPropertiesOf;
    pub const infoName = props_m.infoName;
    pub const startRename = props_m.startRename;
    pub const fileFacts = props_m.fileFacts;
    pub const tableFacts = props_m.tableFacts;
    pub const secondLine = props_m.secondLine;
    pub const doRename = props_m.doRename;
    pub const moveFile = props_m.moveFile;
    pub const openMove = props_m.openMove;
    pub const projectRel = props_m.projectRel;
    pub const moveHere = props_m.moveHere;
    pub const renameTable = props_m.renameTable;
    pub const menuEnabled = props_m.menuEnabled;
    pub const shownPanels = props_m.shownPanels;
    pub const hasFileTarget = props_m.hasFileTarget;
    pub const tableTab = props_m.tableTab;
    pub const compact = props_m.compact;
    pub const compactDb = props_m.compactDb;
    // ------------------------------------------------------------ app/filter.zig
    pub const openFilter = filter_m.openFilter;
    pub const filterSetPat = filter_m.filterSetPat;
    pub const filterPush = filter_m.filterPush;
    pub const filtersLoad = filter_m.filtersLoad;
    pub const filtersStore = filter_m.filtersStore;
    pub const filterTable = filter_m.filterTable;
    pub const filterColName = filter_m.filterColName;
    pub const filterTableTitle = filter_m.filterTableTitle;
    pub const filterCommit = filter_m.filterCommit;
    pub const filterSelect = filter_m.filterSelect;
    pub const filterMissing = filter_m.filterMissing;
    pub const filterMissingCol = filter_m.filterMissingCol;
    pub const filterAdd = filter_m.filterAdd;
    pub const filterPickChoose = filter_m.filterPickChoose;
    pub const filterRemove = filter_m.filterRemove;
    pub const filterKey = filter_m.filterKey;
    pub const Matcher = filter_m.Matcher;
    pub const filterApply = filter_m.filterApply;
    // ------------------------------------------------------------ app/tables.zig
    pub const closeProject = tables_m.closeProject;
    pub const deleteTargets = tables_m.deleteTargets;
    pub const openDelete = tables_m.openDelete;
    pub const closeTabsUnder = tables_m.closeTabsUnder;
    pub const performDelete = tables_m.performDelete;
    pub const selectedDb = tables_m.selectedDb;
    pub const tableNameError = tables_m.tableNameError;
    pub const openCreateTable = tables_m.openCreateTable;
    pub const createTableNamed = tables_m.createTableNamed;
    pub const refreshDbTables = tables_m.refreshDbTables;
    pub const dropTable = tables_m.dropTable;
    pub const performDrop = tables_m.performDrop;
    pub const closeTabByPath = tables_m.closeTabByPath;
    pub const workDirRel = tables_m.workDirRel;
    pub const currentFolder = tables_m.currentFolder;
    pub const alterTable = tables_m.alterTable;
    pub const sqlTableNames = tables_m.sqlTableNames;
    pub const sqlTab = tables_m.sqlTab;
    pub const SqlTarget = tables_m.SqlTarget;
    pub const sqlTarget = tables_m.sqlTarget;
    pub const sqlTargetText = tables_m.sqlTargetText;
    pub const refreshTree = tables_m.refreshTree;
    // ------------------------------------------------------------ app/run.zig
    pub const toggleBreakpoint = run_m.toggleBreakpoint;
    pub const toggleBreakpointAt = run_m.toggleBreakpointAt;
    pub const hasBreakpoint = run_m.hasBreakpoint;
    pub const breakpointState = run_m.breakpointState;
    pub const toggleBreakpointEnabled = run_m.toggleBreakpointEnabled;
    pub const deleteBreakpoint = run_m.deleteBreakpoint;
    pub const askConfirm = run_m.askConfirm;
    pub const confirmYes = run_m.confirmYes;
    pub const clearPanel = run_m.clearPanel;
    pub const jumpToBreakpoint = run_m.jumpToBreakpoint;
    pub const eve_exe = run_m.eve_exe;
    pub const runEve = run_m.runEve;
    pub const runEveMode = run_m.runEveMode;
    pub const runShellLine = run_m.runShellLine;
    pub const startJob = run_m.startJob;
    pub const takeOutput = run_m.takeOutput;
    pub const pollDebug = run_m.pollDebug;
    pub const showVars = run_m.showVars;
    pub const syncBreakpoint = run_m.syncBreakpoint;
    pub const debugLine = run_m.debugLine;
    pub const debugPaused = run_m.debugPaused;
    pub const hasBreakpointsHere = run_m.hasBreakpointsHere;
    pub const debugCommand = run_m.debugCommand;
    pub const runButton = run_m.runButton;
    pub const haltRun = run_m.haltRun;
    pub const startDebug = run_m.startDebug;
    pub const sqlEnter = run_m.sqlEnter;
    pub const sqlKey = run_m.sqlKey;
    pub const shownLog = run_m.shownLog;
    pub const stopRun = run_m.stopRun;
    pub const finishRun = run_m.finishRun;
    pub const changeDir = run_m.changeDir;
    pub const enterScriptFolder = run_m.enterScriptFolder;
    pub const enterFolder = run_m.enterFolder;
    pub const runActive = run_m.runActive;
    pub const checkActive = run_m.checkActive;
    pub const nowMs = run_m.nowMs;
    pub const issueCommand = run_m.issueCommand;
    pub const issueSql = run_m.issueSql;
    // ------------------------------------------------------------ app/session.zig
    pub const sline = session_m.sline;
    pub const saveSession = session_m.saveSession;
    pub const restoreSession = session_m.restoreSession;
    pub const remember = session_m.remember;
    pub const cancelPending = session_m.cancelPending;
    pub const pendingLeft = session_m.pendingLeft;
    pub const tick = session_m.tick;
    pub const consoleEnter = session_m.consoleEnter;
    pub const session_words = session_m.session_words;
    pub const machineLink = session_m.machineLink;
    pub const consoleDir = session_m.consoleDir;
    pub const linkBusy = session_m.linkBusy;
    pub const machineShell = session_m.machineShell;
    pub const machineEval = session_m.machineEval;
    pub const forgetPending = session_m.forgetPending;
    pub const pollLink = session_m.pollLink;
    pub const historyStep = session_m.historyStep;
    // ------------------------------------------------------------ app/search.zig
    pub const filesChanged = search_m.filesChanged;
    pub const nextMatch = search_m.nextMatch;
    pub const selectEntry = search_m.selectEntry;
    pub const filesStep = search_m.filesStep;
    pub const filesRestore = search_m.filesRestore;
    pub const filesCancel = search_m.filesCancel;
    pub const findNext = search_m.findNext;
    pub const replaceOne = search_m.replaceOne;
    pub const replaceEvery = search_m.replaceEvery;
    pub const gotoEnter = search_m.gotoEnter;
    // ------------------------------------------------------------ app/menu.zig
    pub const openOverlay = menu_m.openOverlay;
    pub const rowCount = menu_m.rowCount;
    pub const rowAt = menu_m.rowAt;
    pub const firstItem = menu_m.firstItem;
    pub const openMenu = menu_m.openMenu;
    pub const menuByLetter = menu_m.menuByLetter;
    pub const notYet = menu_m.notYet;
    pub const runMenu = menu_m.runMenu;
    pub const menuMove = menu_m.menuMove;
    pub const menuSide = menu_m.menuSide;
    // ------------------------------------------------------------ app/panels.zig
    pub const treeWidth = panels_m.treeWidth;
    pub const toolsHeight = panels_m.toolsHeight;
    pub const isShown = panels_m.isShown;
    pub const computeLayout = panels_m.computeLayout;
    pub const activePanel = panels_m.activePanel;
    pub const focusPanel = panels_m.focusPanel;
    pub const togglePanel = panels_m.togglePanel;
    pub const activatePanel = panels_m.activatePanel;
    pub const toggleMaximize = panels_m.toggleMaximize;
    pub const rotatePanel = panels_m.rotatePanel;
    pub const nextTab = panels_m.nextTab;
    pub const pickWindow = panels_m.pickWindow;
    pub const openVirtual = panels_m.openVirtual;
    pub const openProject = panels_m.openProject;
    pub const grabSplit = panels_m.grabSplit;
    pub const splitAt = panels_m.splitAt;
    pub const thumbToTop = panels_m.thumbToTop;
    pub const grabBar = panels_m.grabBar;
    pub const scrollTo = panels_m.scrollTo;
    pub const rowToLine = panels_m.rowToLine;
    pub const lineAtRow = panels_m.lineAtRow;
    pub const editorPos = panels_m.editorPos;
    pub const selectTo = panels_m.selectTo;
    pub const dragTo = panels_m.dragTo;
    pub const startModify = panels_m.startModify;
    pub const freezeLayout = panels_m.freezeLayout;
    pub const needsTick = panels_m.needsTick;
    pub const modifyKey = panels_m.modifyKey;
    // ------------------------------------------------------------ app/settings.zig
    pub const applyOptions = settings_m.applyOptions;
    pub const saveOptions = settings_m.saveOptions;
    pub const openOptions = settings_m.openOptions;
    pub const optOk = settings_m.optOk;
    pub const editableTheme = settings_m.editableTheme;
    pub const setSlotColor = settings_m.setSlotColor;
    pub const setChannel = settings_m.setChannel;
    pub const adjustChannel = settings_m.adjustChannel;
    pub const adjustTimer = settings_m.adjustTimer;
    pub const themeStep = settings_m.themeStep;
    pub const themesDir = settings_m.themesDir;
    pub const themeSlug = settings_m.themeSlug;
    pub const themeButton = settings_m.themeButton;
    pub const themeFieldEnter = settings_m.themeFieldEnter;
    pub const optionsKey = settings_m.optionsKey;
    pub const optAction = settings_m.optAction;
    pub const chooserFile = settings_m.chooserFile;
    pub const exportTheme = settings_m.exportTheme;
    pub const importTheme = settings_m.importTheme;
    pub const fail = settings_m.fail;
    // ------------------------------------------------------------ app/dialogs.zig
    pub const anyDirtyFile = dialogs_m.anyDirtyFile;
    pub const autoSaveTick = dialogs_m.autoSaveTick;
    pub const undoRedo = dialogs_m.undoRedo;
    pub const closeClean = dialogs_m.closeClean;
    pub const closeAll = dialogs_m.closeAll;
    pub const openTabMenu = dialogs_m.openTabMenu;
    pub const runTabMenu = dialogs_m.runTabMenu;
    pub const closeOverlay = dialogs_m.closeOverlay;
    pub const openProjectDialog = dialogs_m.openProjectDialog;
    pub const openFolderDialog = dialogs_m.openFolderDialog;
    pub const openCached = dialogs_m.openCached;
    pub const forgetProject = dialogs_m.forgetProject;
    pub const openHere = dialogs_m.openHere;
    pub const openChooser = dialogs_m.openChooser;
    pub const chooserDone = dialogs_m.chooserDone;
    pub const fbHasName = dialogs_m.fbHasName;
    pub const fbOk = dialogs_m.fbOk;
    pub const baseName = dialogs_m.baseName;
    pub const fbLoad = dialogs_m.fbLoad;
    pub const fbClear = dialogs_m.fbClear;
    pub const fbHasParent = dialogs_m.fbHasParent;
    pub const fbRowCount = dialogs_m.fbRowCount;
    pub const fbRowName = dialogs_m.fbRowName;
    pub const fbRowIsFile = dialogs_m.fbRowIsFile;
    pub const fbPickName = dialogs_m.fbPickName;
    pub const fbUp = dialogs_m.fbUp;
    pub const fbEnterRow = dialogs_m.fbEnterRow;
    pub const projectKey = dialogs_m.projectKey;
    pub const folderKey = dialogs_m.folderKey;
    // ------------------------------------------------------------ app/keys.zig
    pub const onKey = keys_m.onKey;
    pub const pickDigit = keys_m.pickDigit;
    pub const tabSwitchesPanel = keys_m.tabSwitchesPanel;
    pub const ctrlEnterOpens = keys_m.ctrlEnterOpens;
    pub const isOverview = keys_m.isOverview;
    pub const ctrlDigit = keys_m.ctrlDigit;
    pub const searchShortcut = keys_m.searchShortcut;
    pub const fieldText = keys_m.fieldText;
    pub const overlayKey = keys_m.overlayKey;
    pub const menuKey = keys_m.menuKey;
    pub const tableKey = keys_m.tableKey;
    pub const editorKey = keys_m.editorKey;
    pub const copySelection = keys_m.copySelection;
    pub const needEditing = keys_m.needEditing;
    pub const pasteClip = keys_m.pasteClip;
    pub const windowTitle = keys_m.windowTitle;
    pub const takeSystemClip = keys_m.takeSystemClip;
    pub const pasteStart = keys_m.pasteStart;
    pub const pasteEnd = keys_m.pasteEnd;
    pub const treeKey = keys_m.treeKey;
    pub const selectionInfo = keys_m.selectionInfo;
    pub const openEntry = keys_m.openEntry;
    pub const filesKey = keys_m.filesKey;
    pub const replaceKey = keys_m.replaceKey;
    pub const consoleComplete = keys_m.consoleComplete;
    pub const consoleKey = keys_m.consoleKey;
    pub const breaksKey = keys_m.breaksKey;
    // ------------------------------------------------------------ app/mouse.zig
    pub const onMouse = mouse_m.onMouse;
    pub const clickTable = mouse_m.clickTable;
    // ------------------------------------------------------------ app/tree.zig
    pub const isMarked = tree_m.isMarked;
    pub const clearMarks = tree_m.clearMarks;
    pub const treePress = tree_m.treePress;
    pub const treeClick = tree_m.treeClick;
    pub const treeRowAt = tree_m.treeRowAt;
    pub const treeDragTo = tree_m.treeDragTo;
    pub const treeRelease = tree_m.treeRelease;
    pub const askMove = tree_m.askMove;
    pub const currentRowPath = tree_m.currentRowPath;
    pub const setMark = tree_m.setMark;
    pub const stepDown = tree_m.stepDown;
    pub const clearSelection = tree_m.clearSelection;
    pub const markCurrent = tree_m.markCurrent;
    pub const markAll = tree_m.markAll;
    pub const markKey = tree_m.markKey;
    pub const openSaveChooser = tree_m.openSaveChooser;
    pub const saveHere = tree_m.saveHere;
    pub const startMove = tree_m.startMove;
    pub const moveManyHere = tree_m.moveManyHere;
    pub const folderPress = tree_m.folderPress;
    pub const folderRelease = tree_m.folderRelease;
    pub const reloadFolders = tree_m.reloadFolders;
    pub const addMoveSource = tree_m.addMoveSource;
    pub const performMove = tree_m.performMove;
    pub const retarget = tree_m.retarget;
    pub const movedPath = tree_m.movedPath;
    pub const refreshHover = tree_m.refreshHover;
    pub const toggleLock = tree_m.toggleLock;
    pub const hover = tree_m.hover;
    pub const activate = tree_m.activate;
};
