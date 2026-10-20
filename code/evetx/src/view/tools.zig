//! @eve-module evetx.view.tools
//! @feature F-TLS-24
//! @decision D-173
//! @see code/evetx/src/view.zig:draw
//! The file card, the debug bar, the tools panel (console, watch, breaks, SQL) and the status bar.
const std = @import("std");
const vaxis = @import("vaxis");
const Window = vaxis.Window;
const app_mod = @import("../app.zig");
const App = app_mod.App;
const Rect = app_mod.Rect;
const theme = @import("../theme.zig");
const ide = @import("ide");
const text = ide.text;
const editor_m = @import("editor.zig");
const find_dialogs_m = @import("find_dialogs.zig");
const sidebar_m = @import("sidebar.zig");
const syntax_m = @import("syntax.zig");
const view_m = @import("../view.zig");
const widgets_m = @import("widgets.zig");
const sub = widgets_m.sub;
const boxed = widgets_m.boxed;
const fillWith = widgets_m.fillWith;
const put = widgets_m.put;
const putRight = widgets_m.putRight;
const absRect = widgets_m.absRect;
const addHit = widgets_m.addHit;
const fixedButton = widgets_m.fixedButton;
const clipText = view_m.clipText;
const panelBox = view_m.panelBox;
const titleButtons = view_m.titleButtons;
const vBar = sidebar_m.vBar;
const setPbar = sidebar_m.setPbar;
const isServerSide = sidebar_m.isServerSide;
const editor = editor_m.editor;
const drawSql = syntax_m.drawSql;
const about = find_dialogs_m.about;
const repeat = find_dialogs_m.repeat;

// @decision D-178
/// The card of a file that is not text: its facts, and no preview (D-178).
pub fn card(app: *App, tab: *app_mod.Tab, ed: Window) void {
    const w: u16 = @min(ed.width -| 4, 64);
    const h: u16 = 9;
    if (ed.height < h + 2 or w < 30) return;
    const x = (ed.width - w) / 2;
    const y = (ed.height - h) / 2;
    const box = boxed(ed, x, y, w, h, theme.line);
    fillWith(box, theme.deep);
    _ = put(box, 2, 0, tab.title(), theme.onBold(theme.bright, theme.deep));
    _ = put(box, 2, 1, tab.card.kind, theme.on(theme.text, theme.deep));
    _ = put(box, 2, 3, "Path", theme.on(theme.dim, theme.deep));
    _ = put(box, 10, 3, tab.path, theme.on(theme.text, theme.deep));
    _ = put(box, 2, 4, "Size", theme.on(theme.dim, theme.deep));
    _ = put(box, 10, 4, sizeText(app, tab.card.size), theme.on(theme.text, theme.deep));
    _ = put(box, 2, 5, "Side", theme.on(theme.dim, theme.deep));
    _ = put(box, 10, 5, if (isServerPath(tab.path)) "server (a folder of the server side)" else "client", theme.on(theme.text, theme.deep));
    _ = put(box, 2, box.height -| 1, tab.card.note, theme.on(theme.dim, theme.deep));
}

pub fn isServerPath(path: []const u8) bool {
    const cut = std.mem.indexOfScalar(u8, path, '/') orelse return false;
    return isServerSide(path[0..cut]);
}

pub fn sizeText(app: *App, size: u64) []const u8 {
    if (size >= 1 << 20) return app.fmt("{d}.{d} MB ({d} bytes)", .{ size >> 20, (size & ((1 << 20) - 1)) * 10 >> 20, size });
    if (size >= 1 << 10) return app.fmt("{d}.{d} KB ({d} bytes)", .{ size >> 10, (size & 1023) * 10 >> 10, size });
    return app.fmt("{d} bytes", .{size});
}

pub fn debugBar(app: *App, win: Window, x0: u16, y: u16, rw: u16) !void {
    const bar = sub(win, x0, y, rw, 1);
    fillWith(bar, theme.panel);
    const on = theme.onBold(theme.bright, theme.green_bg);
    const stop = theme.onBold(theme.bright, theme.red);
    const off = theme.on(theme.faint, theme.panel);
    const idle = theme.on(theme.text, theme.bar);
    var x: u16 = 0;
    // The commands of the debugger, all as wide as the widest label. Run is "Running" (red, blinking) while a program runs;
    // then Halt is active, and the others wait. A stopped program is run again with Run.
    const labels = [_][]const u8{ "▶ Run", "● Running", "■ Halt", "↷ Next", "↓ Step", "↑ Exit", "⇉ Trace" };
    var bw: u16 = 0;
    for (labels) |l| bw = @max(bw, bar.gwidth(l));
    const paused = app.debugPaused();
    // a program of evetx (`job`) or a request of the machine (`!dir`, an eval) is running: Halt is on
    const alive = app.job != null or app.linkBusy();
    const free_run = alive and !paused;
    const blink = @mod(@divFloor(app.nowMs(), 500), 2) == 0;
    // Run (and the debugger buttons that start a program) work on an Eve file only, for now; a program that is already
    // running or stopped can always be driven
    const eve_file = app.canRun();
    const can_start = eve_file or alive;
    const run_style = if (free_run) (if (blink) theme.onBold(theme.bright, theme.red) else theme.onBold(theme.red, theme.bar)) else if (can_start) on else off;
    x = try fixedButton(app, bar, x, if (free_run) labels[1] else labels[0], bw, run_style, if (free_run or !can_start) .nop else .{ .button = .run });
    x += 1;
    x = try fixedButton(app, bar, x, labels[2], bw, if (alive) stop else off, if (alive) .{ .button = .halt } else .nop);
    x += 1;
    const dbg_style = if (free_run or !can_start) off else idle;
    x = try fixedButton(app, bar, x, labels[3], bw, dbg_style, if (free_run or !can_start) .nop else .{ .button = .next });
    x += 1;
    x = try fixedButton(app, bar, x, labels[4], bw, dbg_style, if (free_run or !can_start) .nop else .{ .button = .step });
    x += 1;
    x = try fixedButton(app, bar, x, labels[5], bw, dbg_style, if (free_run or !can_start) .nop else .{ .button = .exit });
    x += 1;
    _ = try fixedButton(app, bar, x, labels[6], bw, dbg_style, if (free_run or !can_start) .nop else .{ .button = .trace });
    // At the right end: the lock of the layout (locked: the borders between the panels stay; open: they can be dragged).
    if (rw > 60) {
        const locked = !app.modify;
        _ = put(bar, rw - 4, 0, if (locked) " 🔒 " else " 🔓 ", theme.onBold(if (locked) theme.text else theme.amber, theme.panel));
        try addHit(app, bar, rw - 4, 0, 4, 1, .lock_toggle);
    }
}

pub fn toolsPanel(app: *App, win: Window, r: Rect) !void {
    if (r.w == 0) return;
    const box = try panelBox(app, win, r, .tools);
    fillWith(box, theme.deep);
    const strip = sub(box, 0, 0, box.width, 1);
    fillWith(strip, theme.bar2);
    const tabs = [_]app_mod.BottomTab{ .console, .watch, .stderr, .stdout, .breaks, .sql };
    const names = [_][]const u8{ "Console", "Watch", "Stderr", "Stdout", "Breaks", "SQL" };
    var x: u16 = 0;
    for (tabs, names) |t, n| {
        const label = if (t == .breaks and app.breakpoints.items.len > 0)
            app.fmt(" {s} ({d}) ", .{ n, app.breakpoints.items.len })
        else if (t == .watch and app.watch_log.lines.items.len > 0)
            app.fmt(" {s} ({d}) ", .{ n, app.watch_log.lines.items.len })
        else
            app.fmt(" {s} ", .{n});
        const on = app.bottom == t;
        _ = put(strip, x, 0, label, if (on) theme.onBold(theme.deep, theme.blue) else theme.on(theme.text, theme.bar2));
        const w = strip.gwidth(label);
        try addHit(app, strip, x, 0, w, 1, .{ .bottom = t });
        x += w + 1;
    }
    try titleButtons(app, box, .tools);
    _ = put(box, 0, 1, repeat("─", 400), theme.on(theme.line, theme.deep));
    const body = sub(box, 0, 2, box.width, box.height -| 2);
    fillWith(body, theme.deep);
    switch (app.bottom) {
        .console => try consolePanel(app, body),
        .stdout => logPanel(app, body, &app.stdout_log, "nothing yet: run a program (F5)"),
        .stderr => logPanel(app, body, &app.stderr_log, "nothing yet: run a program (F5)"),
        .watch => logPanel(app, body, &app.watch_log, "the variables of the program show here when the debugger stops it (Next, Step, Trace)"),
        .breaks => try breaksPanel(app, body),
        .sql => try sqlPanel(app, body),
    }
}

/// How many rows the text needs when a row holds `cap` cells.
pub fn segCount(w: Window, s: []const u8, cap: usize) usize {
    if (cap == 0) return 1;
    var cells: usize = 0;
    var rows: usize = 1;
    var it = (std.unicode.Utf8View.init(s) catch return 1).iterator();
    while (it.nextCodepointSlice()) |ch| {
        const cw: usize = @max(1, w.gwidth(ch));
        if (cells + cw > cap) {
            rows += 1;
            cells = 0;
        }
        cells += cw;
    }
    return rows;
}

/// The piece `seg` (from 0) of the text, when a row holds `cap` cells.
pub fn segText(w: Window, s: []const u8, cap: usize, seg: usize) []const u8 {
    if (cap == 0) return s;
    var cells: usize = 0;
    var row: usize = 0;
    var start: usize = 0;
    var pos: usize = 0;
    var it = (std.unicode.Utf8View.init(s) catch return s).iterator();
    while (it.nextCodepointSlice()) |ch| {
        const cw: usize = @max(1, w.gwidth(ch));
        if (cells + cw > cap) {
            if (row == seg) return s[start..pos];
            row += 1;
            start = pos;
            cells = 0;
        }
        cells += cw;
        pos += ch.len;
    }
    return if (row == seg) s[start..] else "";
}

/// The prompt that a kind of line starts with, and its width.
pub fn logPrefix(kind: app_mod.LineKind) []const u8 {
    return switch (kind) {
        .input => "eve:> ",
        .shell => "$ ",
        .sql => "SQL:> ",
        else => "",
    };
}

pub fn logLine(w: Window, row: u16, l: app_mod.LogLine, seg: usize, cap: usize) void {
    const piece = segText(w, l.text, cap, seg);
    const prefix = logPrefix(l.kind);
    const pw: u16 = @intCast(prefix.len);
    const x: u16 = 1 + pw;
    switch (l.kind) {
        .input => {
            if (seg == 0) _ = put(w, 1, row, prefix, theme.onBold(theme.green, theme.deep));
            _ = put(w, x, row, piece, theme.on(theme.bright, theme.deep));
        },
        .shell => {
            if (seg == 0) _ = put(w, 1, row, prefix, theme.onBold(theme.green, theme.deep));
            _ = put(w, x, row, piece, theme.on(theme.bright, theme.deep));
        },
        .out => _ = put(w, 1, row, piece, theme.on(theme.text, theme.deep)),
        .err => _ = put(w, 1, row, piece, theme.on(theme.red, theme.deep)),
        .info => _ = put(w, 1, row, piece, theme.on(theme.dim, theme.deep)),
        .sql => {
            if (seg == 0) _ = put(w, 1, row, prefix, theme.onBold(theme.blue, theme.deep));
            drawSql(sub(w, x, row, w.width -| x, 1), piece, 0, theme.deep);
        },
    }
}

/// Draw the last lines of a log into `w` (the line `scroll` lines above the end is the last one shown); long lines wrap.
pub fn drawLog(app: *App, w: Window, log: *app_mod.Log) void {
    app.console_rect = absRect(w, 0, 0, w.width, w.height);
    const rows: usize = w.height;
    const total = log.lines.items.len;
    log.scroll = @min(log.scroll, total -| 1);
    const end = total - log.scroll;
    // is a bar needed? Then the rows are one cell narrower
    var bar = false;
    var cap: usize = (@as(usize, w.width) -| 2);
    var pass: u8 = 0;
    var first = end;
    var skip: usize = 0;
    while (pass < 2) : (pass += 1) {
        first = end;
        var used: usize = 0;
        while (first > 0 and used < rows) {
            const l = log.lines.items[first - 1];
            const pw = logPrefix(l.kind).len;
            used += segCount(w, l.text, cap -| pw);
            first -= 1;
        }
        skip = used -| rows;
        bar = total > end - first or first > 0;
        if (bar and pass == 0 and w.width > 3) {
            cap = (@as(usize, w.width) -| 3);
            continue;
        }
        break;
    }
    var r: u16 = 0;
    var i = first;
    while (i < end and r < rows) : (i += 1) {
        const l = log.lines.items[i];
        const pw = logPrefix(l.kind).len;
        const n = segCount(w, l.text, cap -| pw);
        var s: usize = if (i == first) skip else 0;
        while (s < n and r < rows) : (s += 1) {
            logLine(w, r, l, s, cap -| pw);
            r += 1;
        }
    }
    // the scroll bar: arrows at the ends and a thumb at the place of the view in the log
    if (bar and w.width > 3) {
        setPbar(app, .log, vBar(app, w, w.width - 1, w.height, total, first, @max(1, end - first), .{ .log_scroll = .up }, .{ .log_scroll = .down }, false), total, @max(1, end - first));
    }
}

pub fn logPanel(app: *App, body: Window, log: *app_mod.Log, empty: []const u8) void {
    if (log.lines.items.len == 0) {
        _ = put(body, 2, 1, empty, theme.on(theme.faint, theme.deep));
        app.console_rect = absRect(body, 0, 0, body.width, body.height);
        return;
    }
    drawLog(app, body, log);
}

/// The console of evevm: the output scrolls above, then a rule and the prompt `eve:> `.
pub fn consolePanel(app: *App, body: Window) !void {
    const h = body.height;
    if (h < 3) return;
    const out = sub(body, 0, 0, body.width, h - 2);
    drawLog(app, out, &app.console);
    _ = put(body, 0, h - 2, repeat("─", 400), theme.on(theme.line, theme.deep));
    const prompt = if (app.running) "Running… " else "eve:> ";
    _ = put(body, 1, h - 1, prompt, theme.onBold(if (app.running) theme.amber else theme.green, theme.deep));
    const pw: u16 = @intCast(body.gwidth(prompt));
    const line = sub(body, 1 + pw, h - 1, body.width -| (2 + pw), 1);
    fillWith(line, theme.deep);
    if (app.focus == .console and app.overlay == .none) {
        app.console_in.drawWithStyle(line, theme.on(theme.bright, theme.deep));
    } else {
        const first = app.console_in.buf.firstHalf();
        const c = put(line, 0, 0, first, theme.on(theme.text, theme.deep));
        _ = put(line, c, 0, app.console_in.buf.secondHalf(), theme.on(theme.text, theme.deep));
    }
}

pub fn breaksPanel(app: *App, body: Window) !void {
    app.console_rect = .{};
    _ = put(body, 1, 0, "On Del File : line", theme.on(theme.dim, theme.deep));
    if (app.breakpoints.items.len == 0) {
        _ = put(body, 2, 2, "No breakpoints. Press F9 on a line of the editor.", theme.on(theme.faint, theme.deep));
        return;
    }
    const cap: usize = body.height -| 2;
    const n = app.breakpoints.items.len;
    // the first row shown: moved only as far as the selected breakpoint needs, and never past the end
    if (app.break_sel < app.break_top) app.break_top = app.break_sel;
    if (cap > 0 and app.break_sel >= app.break_top + cap) app.break_top = app.break_sel + 1 - cap;
    app.break_top = @min(app.break_top, n -| cap);
    app.breaks_rect = absRect(body, 0, 1, body.width, body.height -| 2);
    const text_w: u16 = if (n > cap) body.width -| 1 else body.width;
    var r: usize = 0;
    while (r < cap and app.break_top + r < n) : (r += 1) {
        const i = app.break_top + r;
        const bp = app.breakpoints.items[i];
        const sel = i == app.break_sel;
        const row = sub(body, 0, @intCast(r + 1), text_w, 1);
        fillWith(row, if (sel) theme.selected else theme.deep);
        const bg = if (sel) theme.selected else theme.deep;
        _ = put(row, 1, 0, if (bp.enabled) "[x]" else "[ ]", theme.on(if (bp.enabled) theme.red else theme.faint, bg));
        _ = put(row, 5, 0, "🗑", theme.on(theme.dim, bg));
        _ = put(row, 8, 0, app.fmt("{s} : {d}", .{ bp.path, bp.line }), theme.on(if (sel and bp.enabled) theme.bright else if (bp.enabled) theme.text else theme.faint, bg));
        try addHit(app, row, 0, 0, text_w, 1, .{ .break_row = i });
        try addHit(app, row, 1, 0, 3, 1, .{ .break_toggle = i });
        try addHit(app, row, 5, 0, 2, 1, .{ .break_trash = i });
    }
    if (n > cap and cap > 0) {
        const col = sub(body, 0, 1, body.width, @intCast(cap));
        setPbar(app, .breaks, vBar(app, col, col.width - 1, col.height, n, app.break_top, cap, .{ .break_scroll = .up }, .{ .break_scroll = .down }, false), n, cap);
    }
    _ = put(body, 1, body.height -| 1, "Enter or a second click jumps · Space switches · Del removes", theme.on(theme.dim, theme.deep));
}

/// The SQL panel: type a statement, Enter runs it on the database (`use <file.db>`, `clear`), the result is a table.
pub fn sqlPanel(app: *App, body: Window) !void {
    const h = body.height;
    if (h < 3) return;
    const out = sub(body, 0, 0, body.width, h - 2);
    if (app.sql_log.lines.items.len == 0) {
        _ = put(out, 2, 0, "SQL goes to the table or the database that is selected · use <file.db> chooses a file, use auto goes back · clear empties this panel", theme.on(theme.faint, theme.deep));
        app.console_rect = absRect(out, 0, 0, out.width, out.height);
    } else drawLog(app, out, &app.sql_log);
    _ = put(body, 0, h - 2, repeat("─", 400), theme.on(theme.line, theme.deep));
    // the target of the SQL, on the rule, at the right
    const target = clipText(app.fmt(" {s} ", .{app.sqlTargetText()}), body.width -| 4);
    _ = put(body, body.width -| (body.gwidth(target) + 2), h - 2, target, theme.onBold(theme.blue, theme.deep));
    _ = put(body, 1, h - 1, "SQL:> ", theme.onBold(theme.blue, theme.deep));
    const line = sub(body, 7, h - 1, body.width -| 8, 1);
    fillWith(line, theme.deep);
    const first = app.sql_in.buf.firstHalf();
    const second = app.sql_in.buf.secondHalf();
    const joined = app.fmt("{s}{s}", .{ first, second });
    drawSql(line, joined, 0, theme.deep);
    if (app.focus == .sql and app.overlay == .none) line.showCursor(@intCast(@min(line.gwidth(first), line.width -| 1)), 0);
}

/// What the status bar says about the current window after its name: kind, size, line ends. The
/// project name is not repeated here: it is in the title bar of the Tree Panel.
pub fn fileFacts(app: *App) []const u8 {
    const t = app.activeTab() orelse return "";
    if (t.folder) |fv| return app.fmt(" · folder · {d} items", .{fv.items.items.len});
    if (t.table) |tv| return app.fmt(" · table · {d} records · {d} fields", .{ tv.t.records, tv.t.fields.len });
    if (t.buf) |*b| {
        if (t.virtual) return app.fmt(" · read only · {d} lines", .{b.lineCount()});
        const kind: []const u8 = if (t.eve) "Eve source" else if (t.sql) "SQL" else "text";
        return app.fmt(" · {s} · {d} lines · {s}{s}", .{ kind, b.lineCount(), if (b.crlf) "CRLF" else "LF", if (b.dirty) " · modified" else "" });
    }
    return app.fmt(" · {s} · {s}", .{ t.card.kind, sizeText(app, t.card.size) });
}

pub fn statusBar(app: *App, win: Window) !void {
    const W = win.width;
    const H = win.height;
    const box = boxed(win, 0, H - 3, W, 3, theme.line);
    fillWith(box, theme.deep);
    const w = box.width;
    const pos_w: u16 = 16;
    const pos_x: u16 = w -| (pos_w + 1);
    const left_w = pos_x -| 3;
    _ = put(box, pos_x -| 2, 0, "│", theme.on(theme.line, theme.deep));

    if (app.modify) {
        const hint = if (app.freeze_at != null)
            "Layout modify · it freezes in a moment · drag again to go on"
        else if (app.mouse_modify)
            "Layout modify · drag the border · Ctrl+F freezes at once"
        else
            "Layout modify · drag the borders or use the arrow keys · Ctrl+F or Esc freezes";
        _ = put(box, 1, 0, clipText(hint, left_w), theme.onBold(theme.amber, theme.deep));
    } else if (app.pendingLeft()) |ms| {
        const secs: i64 = @divFloor(ms + 999, 1000);
        const cmd_text = app.pending_text orelse "";
        _ = put(box, 1, 0, clipText(app.fmt("▶ {s} starts in {d}s · Enter runs now · Esc cancels · typing keeps it", .{ cmd_text, secs }), left_w), theme.onBold(theme.amber, theme.deep));
    } else if (app.message) |m| {
        _ = put(box, 1, 0, clipText(m, left_w), theme.onBold(theme.amber, theme.deep));
    } else if (app.running) {
        _ = put(box, 1, 0, "Running…", theme.onBold(theme.amber, theme.deep));
    } else if (app.activeTab()) |t| {
        const name = if (t.path.len == 0) "untitled" else t.path;
        const shown = clipText(name, left_w);
        const c = put(box, 1, 0, shown, theme.onBold(theme.bright, theme.deep));
        if (c + 2 < left_w + 1) _ = put(box, c, 0, clipText(fileFacts(app), left_w + 1 -| c), theme.on(theme.dim, theme.deep));
    } else {
        _ = put(box, 1, 0, "Ready", theme.on(theme.green, theme.deep));
    }

    if (app.activeBuffer()) |b| {
        const mode: []const u8 = if (app.activeTab()) |t| (if (t.editing) "EDIT  " else "") else "";
        putRight(box, w -| 2, 0, app.fmt("{s}Ln {d:>4}, Col {d:>3}", .{ mode, b.row + 1, b.displayCol() + 1 }), theme.on(theme.text, theme.deep));
    } else if (if (app.activeTab()) |t| t.table else null) |tv| {
        const mode: []const u8 = if (app.activeTab()) |t| (if (t.editing) "EDIT  " else "") else "";
        putRight(box, w -| 2, 0, app.fmt("{s}Rec {d:>6}/{d}", .{ mode, tv.row + 1, tv.t.records }), theme.on(theme.text, theme.deep));
    } else {
        putRight(box, w -| 2, 0, "Ln    -, Col   -", theme.on(theme.faint, theme.deep));
    }
}
