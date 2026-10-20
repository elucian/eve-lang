//! @eve-module evetx.app.run
//! @feature F-TLS-27
//! @decision D-173
//! @see code/evetx/src/app.zig:App
//! Breakpoints, running a script, the debugger and the console.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const vaxis = @import("vaxis");
const Key = vaxis.Key;
const ide = @import("ide");
const project = ide.project;
const text = ide.text;
const App = @import("../app.zig").App;
const types = @import("types.zig");
const Panel = types.Panel;
const Log = types.Log;
const Confirm = types.Confirm;
const RunJob = types.RunJob;

// ------------------------------------------------------------ breakpoints

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

/// The check box of the Breaks tab: enable or disable breakpoint `i`.
pub fn toggleBreakpointEnabled(self: *App, i: usize) void {
    if (i >= self.breakpoints.items.len) return;
    const bp = &self.breakpoints.items[i];
    bp.enabled = !bp.enabled;
    self.syncBreakpoint(bp.path, bp.line, bp.enabled);
}

pub fn deleteBreakpoint(self: *App, i: usize) void {
    if (i >= self.breakpoints.items.len) return;
    const bp = self.breakpoints.items[i];
    if (bp.enabled) self.syncBreakpoint(bp.path, bp.line, false);
    self.gpa.free(bp.path);
    _ = self.breakpoints.orderedRemove(i);
    self.break_sel = @min(self.break_sel, self.breakpoints.items.len -| 1);
}

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
pub fn confirmYes(self: *App) void {
    self.overlay = .none;
    switch (self.confirm_what) {
        .none => {},
        .delete_breakpoint => self.deleteBreakpoint(self.confirm_arg),
        .move_files => self.performMove(),
        .apply_sqlite => self.sqApplyNow() catch {},
        .drop_table => self.performDrop(),
        .delete_file => self.performDelete(),
        .delete_rows => self.performDeleteRows(),
        .replace_file => if (self.save_rel) |r| self.saveAs(r) catch |err| self.setMessage("cannot save {s}: {s}", .{ r, @errorName(err) }),
        .clear_breakpoints => {
            while (self.breakpoints.items.len > 0) self.deleteBreakpoint(self.breakpoints.items.len - 1);
        },
    }
    self.confirm_what = .none;
}

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

pub fn jumpToBreakpoint(self: *App, index: usize) !void {
    if (index >= self.breakpoints.items.len) return;
    const bp = self.breakpoints.items[index];
    try self.openFile(bp.path);
    if (self.activeBuffer()) |b| b.gotoLine(bp.line, 0);
    self.focus = .editor;
}

// ------------------------------------------------------------ run and the console

pub const eve_exe = if (builtin.os.tag == .windows) "eve.exe" else "eve";

/// Run `eve` with these arguments in the working folder of the console. The process runs in a thread; the output
/// goes to the Stdout and Stderr tabs and a summary to the console when it ends (`finishRun`, called by `tick`).
pub fn runEve(self: *App, args: []const []const u8) !void {
    return self.runEveMode(args, false);
}

/// `runEve`, with the debugger on or off (`eve debug <file>` takes commands and shows its output while it runs).
pub fn runEveMode(self: *App, args: []const []const u8, debug: bool) !void {
    return self.startJob(App.eve_exe, args, debug);
}

/// Run one line in the shell that started evetx.
pub fn runShellLine(self: *App, line: []const u8) !void {
    const flag: []const u8 = if (builtin.os.tag == .windows and std.ascii.eqlIgnoreCase(self.shell_exe, "cmd.exe")) "/c" else "-c";
    const sh_args = [_][]const u8{ flag, line };
    try self.startJob(self.shell_exe, &sh_args, false);
}

/// Start a program (`eve`, or the shell) with these arguments in the working folder of the console.
pub fn startJob(self: *App, program: []const u8, args: []const []const u8, debug: bool) !void {
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

/// Show the output lines that a debug run produced since the last call.
pub fn takeOutput(self: *App, job: *RunJob) !void {
    const live = job.takeLive() orelse return;
    defer self.gpa.free(live);
    try self.stdout_log.addBlock(self.gpa, live, .out);
    try self.console.addBlock(self.gpa, live, .out);
    self.console.scroll = 0;
    self.stdout_log.scroll = 0;
}

/// Debug session: show the output and the variables, and follow the debugger to the line of the program.
pub fn pollDebug(self: *App) !void {
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
pub fn showVars(self: *App, job: *RunJob) void {
    const vars = job.takeVars() orelse return;
    defer self.gpa.free(vars);
    self.watch_log.clear(self.gpa);
    self.watch_log.addBlock(self.gpa, vars, .out) catch {};
    self.watch_log.scroll = 0;
}

/// A breakpoint was set (`added`) or removed in the file `path`: tell the debugger of a running session.
pub fn syncBreakpoint(self: *App, path: []const u8, line: usize, added: bool) void {
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
pub fn hasBreakpointsHere(self: *App) bool {
    const t = self.activeTab() orelse return false;
    for (self.breakpoints.items) |bp| {
        if (bp.enabled and std.mem.eql(u8, bp.path, t.path)) return true;
    }
    return false;
}

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
pub fn runButton(self: *App) !void {
    if (self.job) |job| {
        if (job.debug and job.paused.load(.acquire)) return self.debugCommand("run");
        self.setMessage("the program is running: Halt stops it", .{});
        return;
    }
    try self.runActive();
}

/// The Halt button: `halt` for a stopped program (it ends as stopped), the process is ended for one that runs.
pub fn haltRun(self: *App) !void {
    // a request of the machine (a command of the system, an eval) is cancelled by the machine
    if (self.job == null and self.linkBusy()) {
        if (self.link) |l| _ = l.call("vm.cancel", .{});
        self.setMessage("Halt: the machine cancels what it runs", .{});
        return;
    }
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
pub fn startDebug(self: *App, auto: ?[]const u8) !void {
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
    if (!self.running) self.bottom = .console;
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

/// Enter in the SQL panel: run the line with `eve db sql` and show the result table.
pub fn sqlEnter(self: *App) !void {
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
    if (cmd.len >= 10 and std.ascii.eqlIgnoreCase(cmd[0..10], "drop table") and (cmd.len == 10 or cmd[10] == ' ') and std.ascii.findIgnoreCase(cmd, " if ") == null) {
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
    var db: []const u8 = ":memory:";
    switch (self.sqlTarget()) {
        .memory => {},
        .sqlite => |p| db = p,
    }
    var argv_list: std.ArrayList([]const u8) = .empty;
    defer argv_list.deinit(gpa);
    try argv_list.appendSlice(gpa, &.{ App.eve_exe, "db", "sql" });
    try argv_list.appendSlice(gpa, &.{ db, cmd });
    const result = std.process.run(gpa, self.io, .{ .argv = argv_list.items, .cwd = cwd }) catch |err| {
        const msg = try std.fmt.allocPrint(gpa, "cannot run {s}: {s}", .{ App.eve_exe, @errorName(err) });
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
pub fn sqlKey(self: *App, key: Key) !void {
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
    if (key.matches(Key.right, .{}) and self.sql_in.buf.secondHalf().len == 0 and self.sql_in.buf.firstHalf().len > 0) return self.sqlTab();
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
pub fn shownLog(self: *App) *Log {
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

/// When the worker is done: show its output and a summary, and free the job.
pub fn finishRun(self: *App) !void {
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

/// `cd`: the commands of the console run in this folder from now on. Says so in the console.
pub fn changeDir(self: *App, target: []const u8) !void {
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

/// Run and Check: go to the folder of the script first (a `cd` line in the console), and give back the file name.
/// The folder of a script matters: `eve` loads the `eve.cfg` of its working folder, and a project may hold
/// several sub-projects, each with its own.
pub fn enterScriptFolder(self: *App, rel: []const u8) !void {
    try self.enterFolder(std.fs.path.dirname(rel) orelse "");
}

/// Make a folder of the project the working folder of the console, and say so in the console.
pub fn enterFolder(self: *App, dir_rel: []const u8) !void {
    const full = if (dir_rel.len == 0) try self.gpa.dupe(u8, if (self.root.len == 0) "." else self.root) else try self.fullPath(dir_rel);
    defer self.gpa.free(full);
    if (self.work_dir) |cur| {
        if (std.mem.eql(u8, cur, full)) return;
    }
    const shown = try std.fmt.allocPrint(self.gpa, "cd {s}", .{full});
    defer self.gpa.free(shown);
    try self.console.add(self.gpa, shown, .input);
    try self.changeDir(full);
}

/// F5, the Run button: save the file and run it.
pub fn runActive(self: *App) !void {
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
    // while a program runs the tab of the Tools Panel that the person chose stays (the output, the watch)
    if (!self.running) {
        self.bottom = .console;
        self.focus = .console;
    }
    self.console_in.clearRetainingCapacity();
    try self.console_in.insertSliceAtCursor(line);
    self.history_pos = null;
    try self.remember(line);
    if (self.pending_text) |old| self.gpa.free(old);
    self.pending_text = try self.gpa.dupe(u8, line);
    self.pending_at = self.nowMs() + @as(i64, self.options.run_delay_s) * 1000;
}

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
