//! @eve-module evetx.app.session
//! @feature F-TLS-24
//! @decision D-173
//! @see code/evetx/src/app.zig:App
//! The session file and the console commands of the machine.
const std = @import("std");
const vaxis = @import("vaxis");
const ide = @import("ide");
const project = ide.project;
const text = ide.text;
const link_mod = ide.link;
const App = @import("../app.zig").App;
const types = @import("types.zig");
const Focus = types.Focus;
const BottomTab = types.BottomTab;
const Tab = types.Tab;

// ------------------------------------------------------------ the session

pub fn sline(self: *App, out: *std.ArrayList(u8), comptime f: []const u8, args: anytype) !void {
    const s = try std.fmt.allocPrint(self.gpa, f ++ "\n", args);
    defer self.gpa.free(s);
    try out.appendSlice(self.gpa, s);
}

/// Write where the user is: the project, the panel sizes and visibility, the open files with their
/// cursors, the open folders of the tree and the breakpoints. It goes to `evetx-session.txt` in the
/// cache folder; evetx reads it at the next start. Called when the program ends and when the files change.
pub fn saveSession(self: *App) !void {
    if (self.root.len == 0 or self.restoring) return;
    const abs = try App.realPathOf(self.gpa, self.io, self.root);
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
        // windows that are made on the fly are not saved: a filter, the list of the tables of a database
        if (std.mem.startsWith(u8, t.path, "filter:") or t.path[t.path.len - 1] == '#') continue;
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

/// Read `evetx-session.txt` and put the screen back as it was, when it is the session of this project.
pub fn restoreSession(self: *App) void {
    const bytes = self.cache.readFile("evetx-session.txt") orelse return;
    defer self.gpa.free(bytes);
    const abs = App.realPathOf(self.gpa, self.io, self.root) catch return;
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
    // every tab was put first, so the list is backwards now
    std.mem.reverse(Tab, self.tabs.items);
    if (active < self.tabs.items.len) self.active = active;
    self.follow = false;
    if (self.message) |m| {
        self.gpa.free(m);
        self.message = null;
    }
}

/// Add a command to the history of the console, unless it is the same as the last one.
pub fn remember(self: *App, cmd: []const u8) !void {
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
    try self.pollLink();
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

pub fn consoleEnter(self: *App) !void {
    const line = try self.console_in.toOwnedContents(self.gpa);
    defer self.gpa.free(line);
    self.console_in.clearRetainingCapacity();
    self.history_pos = null;
    const cmd = std.mem.trim(u8, line, " ");
    if (cmd.len == 0) return;
    try self.remember(cmd);
    const system = cmd[0] == '!' or std.mem.startsWith(u8, cmd, "shell ") or std.mem.eql(u8, cmd, "shell");
    try self.console.add(self.gpa, cmd, if (system) .shell else .input);

    if (std.mem.eql(u8, cmd, "clear")) {
        self.console.clear(self.gpa);
        return;
    }
    // `exit` and `quit` close evetx: back to the command shell that started it (Ctrl+Q does the same)
    if (std.mem.eql(u8, cmd, "quit") or std.mem.eql(u8, cmd, "exit")) {
        self.quit = true;
        return;
    }
    // `!<command>` and `shell <command>`: a command of the system, run by the machine in the working folder; eve stays
    if (system) {
        const command = std.mem.trim(u8, if (cmd[0] == '!') cmd[1..] else cmd["shell".len..], " ");
        if (command.len == 0) {
            try self.console.add(self.gpa, "shell: give the command, for example: !dir or shell git status", .info);
            return;
        }
        return self.machineShell(command);
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
    // the commands of a session go to the machine, which keeps the loaded script between them
    for (App.session_words) |w| {
        if (std.mem.eql(u8, w, words.items[0])) return self.machineEval(cmd);
    }
    // `run x.eve` is `eve x.eve`; any other line is given to eve as its arguments.
    const args = if (std.mem.eql(u8, words.items[0], "run")) words.items[1..] else words.items;
    try self.runEve(args);
}

/// The words of the console that are commands of a session of the machine (`vm.eval`).
pub const session_words = [_][]const u8{ "load", "parse", "ast", "inspect", "errors", "status", "report", "help", "outdir", "capture", "log" };

// ------------------------------------------------------------ the machine of the console

/// The machine of the console, started if needed; null when it cannot start.
pub fn machineLink(self: *App) ?*link_mod.Link {
    if (self.link) |l| {
        if (l.alive()) return l;
        l.destroy();
        self.link = null;
        self.link_pending.clearRetainingCapacity();
    }
    self.link = link_mod.Link.start(self.gpa, self.io, App.eve_exe) catch |err| {
        self.console.add(self.gpa, "the machine cannot start (eve --stdio); is eve in the PATH?", .err) catch {};
        self.setMessage("machine: {s}", .{@errorName(err)});
        return null;
    };
    return self.link;
}

/// The working folder of the console, as evetx and its machine see it (both start in the same folder).
pub fn consoleDir(self: *const App) []const u8 {
    if (self.work_dir) |w| return w;
    return if (self.root.len == 0) "." else self.root;
}

/// Is a request of the machine not answered yet? (The toolbar shows it as running.)
pub fn linkBusy(self: *const App) bool {
    return self.link_pending.items.len > 0;
}

/// `!<command>`: a command of the system, run by the machine in the working folder of the console.
pub fn machineShell(self: *App, command: []const u8) !void {
    const l = self.machineLink() orelse return self.runShellLine(command);
    const id = l.call("vm.shell", .{ .command = command, .cwd = self.consoleDir(), .stream = true });
    if (id != 0) try self.link_pending.append(self.gpa, id);
}

/// A command of the session of the machine (`load`, `parse`, `errors`, `status`, …), in the working folder.
pub fn machineEval(self: *App, line_text: []const u8) !void {
    const l = self.machineLink() orelse return;
    const id = l.call("vm.eval", .{ .line = line_text, .cwd = self.consoleDir(), .stream = true });
    if (id != 0) try self.link_pending.append(self.gpa, id);
}

pub fn forgetPending(self: *App, id: u32) void {
    if (std.mem.indexOfScalar(u32, self.link_pending.items, id)) |i| _ = self.link_pending.swapRemove(i);
}

/// Called by `tick`: show what the machine sent since the last frame.
pub fn pollLink(self: *App) !void {
    const l = self.link orelse return;
    const gpa = self.gpa;
    if (l.take()) |events| {
        defer {
            for (events) |e| e.free(gpa);
            gpa.free(events);
        }
        for (events) |e| switch (e.kind) {
            .output => {
                try self.console.addBlock(gpa, e.text, .out);
                try self.stdout_log.addBlock(gpa, e.text, .out);
            },
            .log => try self.stderr_log.add(gpa, e.text, .err),
            .failed => {
                self.forgetPending(e.id);
                const msg = try std.fmt.allocPrint(gpa, "machine: {s}", .{e.text});
                defer gpa.free(msg);
                try self.console.add(gpa, msg, .err);
            },
            .done => {
                self.forgetPending(e.id);
                if (e.text.len > 0) try self.console.addBlock(gpa, e.text, if (e.status == 0) .out else .err);
                if (e.status != 0) {
                    const msg = try std.fmt.allocPrint(gpa, "exit {d}", .{e.status});
                    defer gpa.free(msg);
                    try self.console.add(gpa, msg, .info);
                }
            },
        };
    }
    if (!l.alive() and self.link_pending.items.len > 0) {
        self.link_pending.clearRetainingCapacity();
        const msg = try std.fmt.allocPrint(gpa, "the machine ended ({s}); the next command starts a new one", .{l.err_name orelse "done"});
        defer gpa.free(msg);
        try self.console.add(gpa, msg, .err);
    }
}

pub fn historyStep(self: *App, delta: isize) !void {
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
