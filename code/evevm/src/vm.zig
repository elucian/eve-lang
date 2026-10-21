//! @eve-module vm
//! @spec spec/library/machine.md
//! @feature F-VM-02, F-TLS-02
//! @decision D-188
//! @tests test/level1, test/smoke
//! The virtual machine session: it holds one script at a time (loaded, parsed, executed).
//!
//! Its commands (`load a.eve`, `parse`, `run`, `errors`, `ast`, `inspect`, `status`, ...) come from the
//! prompt of the REPL or, one line per message, from `vm.eval` on a lasting door of the machine (IPC or
//! `eve --stdio`). A workflow drives one machine with many such lines (`script/workflow.py`) and reads
//! the reports the session leaves in its folder. The command files (`.vmc`, `eve -i`) are gone (D-188).
const std = @import("std");

/// The comment rule of a command line (it moved to evecm with the configuration reader).
pub const clean = @import("evecm").config.clean;
const Io = std.Io;
const ast = @import("evecm").ast;
const parser = @import("evecp").parser;
const project = @import("evecp").project;
const interp = @import("interp.zig");
const sysvars = @import("interp/sysvars.zig");
const debugger = @import("debugger.zig");
const settings = @import("settings.zig");
const scriptparams = @import("scriptparams.zig");

/// How many times `cancelAll` was called.
pub var cancel_generation: std.atomic.Value(usize) = .init(0);

/// Tell every script that runs now (in any thread) to stop at its next statement.
pub fn cancelAll() void {
    _ = cancel_generation.fetchAdd(1, .release);
}

/// Exit status when a file cannot be read (EX_NOINPUT) and when it has syntax errors (EX_DATAERR).
pub const exit_no_input = 66;
pub const exit_syntax = 65;

/// Words of a command line, at most this many.
const max_words = 16;

/// One VM session. Commands are the `exec` methods below; the REPL and `vm.eval` both call them.
pub const Session = struct {
    io: Io,
    gpa: std.mem.Allocator,
    out: *Io.Writer,
    /// Folder of the report files (`outdir`).
    outdir: []const u8 = "temp/output",
    /// Print only errors (the command line `eve script.eve`): the output is the script's own.
    quiet: bool = false,
    /// Keep the program output in a file (`<outdir>/<name>.out`) instead of writing it to `out`.
    capture: bool = false,
    /// The `halt` flag of the command line (not used yet).
    debug: bool = false,
    /// The debugger that drives the run (`eve debug`), or null.
    dbg: ?*debugger.Debugger = null,
    /// Exit status of the last command.
    status: u8 = 0,
    /// Set by `stop`: the loop that reads commands ends.
    stopping: bool = false,
    running: bool = false,
    /// The value of `cancel_generation` when the script started: a different value later means "stop now".
    cancel_seen: usize = 0,
    /// Statements executed and the line of the last one, as the hook of the interpreter reports.
    steps: usize = 0,
    line: u32 = 0,

    // the current script
    arena: ?std.heap.ArenaAllocator = null,
    path: []const u8 = "",
    name: []const u8 = "",
    src: []const u8 = "",
    tree: ?*const ast.Node = null,
    diag: parser.Diag = .{},
    /// The aspect file that holds the error in `diag`, or "" when it is in the script itself.
    bad_path: []const u8 = "",
    /// The aspects the script applies, read and checked by `parse` (project.zig).
    aspects: ast.Aspects = .empty,
    /// The modules that the imports of the script reach, read and checked by `parse` (project.zig).
    modules: ast.Modules = .empty,
    parse_failed: bool = false,
    machine: ?*interp.Interp = null,
    /// The command-line arguments after the script name (the arguments of `process main`).
    script_args: []const []const u8 = &.{},
    /// `-e file.cfg`: the settings that become `$` variables of the run (settings.zig); checked by the caller before `run`.
    config_file: ?[]const u8 = null,
    /// `-p name=value` (scriptparams.zig) and `-h` after the script name.
    script_params: []const interp.ScriptParam = &.{},
    script_help: bool = false,
    outcome: ?interp.Outcome = null,

    /// The text of `summary.log`, one line per `status` or `log`.
    summary: std.ArrayList(u8) = .empty,

    /// Free the memory of the last run's interpreter.
    fn dropMachine(self: *Session) void {
        if (self.machine) |m| m.deinit();
        self.machine = null;
    }

    /// The memory of the current script (created when the session has none yet).
    fn mem(self: *Session) std.mem.Allocator {
        if (self.arena == null) self.arena = .init(std.heap.page_allocator);
        return self.arena.?.allocator();
    }

    fn forget(self: *Session) void {
        self.dropMachine();
        if (self.arena) |*a| a.deinit();
        self.arena = null;
        self.path = "";
        self.name = "";
        self.src = "";
        self.tree = null;
        self.parse_failed = false;
        self.machine = null;
        self.outcome = null;
        self.diag = .{};
        self.bad_path = "";
        self.aspects = .empty;
        self.modules = .empty;
    }

    // ---- loading, parsing, running --------------------------------------------------------

    /// Load the script `path` (the previous one is forgotten).
    pub fn load(self: *Session, path: []const u8) Io.Writer.Error!void {
        self.forget();
        self.arena = .init(std.heap.page_allocator);
        const src = Io.Dir.cwd().readFileAlloc(self.io, path, self.mem(), .limited(16 << 20)) catch |err| {
            self.forget();
            try self.out.print("{s}: cannot read: {s}\n", .{ path, @errorName(err) });
            self.status = exit_no_input;
            return;
        };
        try self.loadSource(path, src);
    }

    /// Use `src` (kept by the caller for as long as the session needs it) as the current script.
    pub fn loadSource(self: *Session, path: []const u8, src: []const u8) Io.Writer.Error!void {
        if (self.arena == null) self.arena = .init(std.heap.page_allocator);
        self.path = self.mem().dupe(u8, path) catch return error.WriteFailed;
        const cut = std.mem.lastIndexOfAny(u8, path, "/\\");
        self.setName(if (cut) |i| path[i + 1 ..] else path, src);
    }

    fn setName(self: *Session, base: []const u8, src: []const u8) void {
        const stem = base[0 .. std.mem.lastIndexOfScalar(u8, base, '.') orelse base.len];
        self.name = self.mem().dupe(u8, stem) catch stem;
        self.src = src;
        self.tree = null;
        self.parse_failed = false;
        self.machine = null;
        self.outcome = null;
        self.diag = .{};
        self.bad_path = "";
        self.aspects = .empty;
        self.modules = .empty;
        self.status = 0;
    }

    /// Parse the script and, for a root aspect, read the aspects it applies and match every `apply`.
    fn build(self: *Session) parser.Error!*const ast.Node {
        const tree = try parser.parse(self.mem(), self.src, &self.diag);
        const cut = std.mem.lastIndexOfAny(u8, self.path, "/\\");
        const dir = if (cut) |i| self.path[0..i] else ".";
        try project.link(self.mem(), self.io, dir, tree, &self.diag, &self.bad_path, &self.aspects, &self.modules, project.env_lib_path);
        return tree;
    }

    /// `parse`: build the syntax tree. A syntax error is printed as `file:line:col: error: text`.
    pub fn parse(self: *Session) Io.Writer.Error!void {
        if (self.arena == null) {
            try self.out.writeAll("parse: no script loaded (use load)\n");
            self.status = exit_no_input;
            return;
        }
        self.tree = null;
        self.diag = .{};
        self.bad_path = "";
        self.aspects = .empty;
        if (self.build()) |tree| {
            self.tree = tree;
            self.parse_failed = false;
            var stats: ast.Stats = .{};
            stats.add(tree, 0);
            if (!self.quiet) try self.out.print("{s}: parse ok, {d} nodes\n", .{ self.name, stats.nodes });
            self.status = 0;
        } else |err| {
            self.parse_failed = true;
            self.status = exit_syntax;
            switch (err) {
                error.Syntax => try self.out.print("{s}:{d}:{d}: error: {s}\n", .{ if (self.bad_path.len > 0) self.bad_path else self.path, self.diag.line, self.diag.col, self.diag.message() }),
                error.OutOfMemory => try self.out.print("{s}: out of memory\n", .{self.path}),
            }
        }
    }

    fn pollHook(ctx: *anyopaque, steps: usize, line: u32) bool {
        const self: *Session = @ptrCast(@alignCast(ctx));
        self.steps = steps;
        self.line = line;
        return self.stopping or cancel_generation.load(.monotonic) != self.cancel_seen;
    }

    /// `run`: execute the loaded script. A script that was not parsed yet is parsed first.
    pub fn run(self: *Session) Io.Writer.Error!void {
        if (self.arena == null) {
            try self.out.writeAll("run: no script loaded (use load)\n");
            self.status = exit_no_input;
            return;
        }
        if (self.tree == null and !self.parse_failed) try self.parse();
        const tree = self.tree orelse return; // the syntax error was reported by parse
        const a = self.mem();
        var cap: ?*Io.Writer = null;
        if (self.capture) {
            const buf = a.alloc(u8, 1 << 20) catch return error.WriteFailed;
            cap = a.create(Io.Writer) catch return error.WriteFailed;
            cap.?.* = .fixed(buf);
        }
        self.dropMachine();
        const machine = a.create(interp.Interp) catch return error.WriteFailed;
        machine.* = interp.Interp.init(a, cap orelse self.out) catch return error.WriteFailed;
        machine.hook = .{ .ctx = self, .poll = pollHook };
        if (self.dbg) |d| {
            d.src = self.src;
            machine.dbg = d.hook();
        }
        machine.script_args = self.script_args;
        machine.script_params = self.script_params;
        machine.aspects = &self.aspects;
        machine.modules = &self.modules;
        machine.io = self.io; // threads, locks and clocks of the tasks (level 4)
        machine.defineOsPwd() catch {};
        const cut = std.mem.lastIndexOfAny(u8, self.path, "/\\");
        sysvars.define(machine, if (cut) |i| self.path[0..i] else ".") catch {};
        if (self.config_file) |cf| {
            var why: []const u8 = "";
            if (settings.load(self.io, self.mem(), cf, &why)) |entries| settings.define(machine, entries) catch {} else |_| {}
        }
        self.machine = machine;
        self.steps = 0;
        self.line = 0;
        self.cancel_seen = cancel_generation.load(.acquire);
        self.running = true;
        const o = machine.run(tree);
        self.running = false;
        if (self.dbg) |d| {
            self.out.print("@debug end {d}{s}\n", .{ o.code, if (o.stopped) " stopped" else "" }) catch {};
            self.out.flush() catch {};
            d.breaks.deinit(d.gpa);
        }
        self.steps = machine.steps;
        self.outcome = o;
        self.status = o.code;
        self.writeRunLog(machine);
        if (cap) |w| {
            self.ensureDir();
            self.writeReport("out", w.buffered());
            try self.out.print("{s}: run, exit {d}{s}\n", .{ self.name, o.code, if (o.stopped) ", stopped" else "" });
        }
    }

    // @eve-impl `eve script.eve -h` prints the help of the script; a required parameter without a value is a usage error (64)
    // @spec spec/semantics/aspects.md#parameters-on-the-command-line
    // @test a98_script_params
    /// False when the run must not start: the help was asked for, or a parameter of `process main` has no value.
    pub fn paramsReady(self: *Session) Io.Writer.Error!bool {
        if (self.arena == null) return true;
        if (self.tree == null and !self.parse_failed) try self.parse();
        const tree = self.tree orelse return true;
        const main = interp.Interp.findProcess(tree, "main") orelse return true;
        const a = self.mem();
        if (self.script_help) {
            scriptparams.writeHelp(a, self.out, self.path, self.src, main) catch return error.WriteFailed;
            self.status = 0;
            return false;
        }
        const miss = scriptparams.missing(a, main, self.script_args.len, self.script_params) catch return error.WriteFailed;
        if (miss.len == 0) return true;
        try self.out.print("{s}: missing parameter{s}:", .{ self.path, if (miss.len > 1) "s" else "" });
        for (miss) |m| try self.out.print(" {s}", .{m});
        try self.out.writeAll("\n\n");
        scriptparams.writeHelp(a, self.out, self.path, self.src, main) catch return error.WriteFailed;
        self.status = scriptparams.exit_usage;
        return false;
    }

    /// Append the run to `out/run-log-<date>.json` of the project: a JSON array, one object per run (D-114).
    fn writeRunLog(self: *Session, m: *const interp.Interp) void {
        if (m.logs.items.len == 0) return;
        const a = self.mem();
        const now = Io.Timestamp.now(self.io, .real).toSeconds();
        const secs: std.time.epoch.EpochSeconds = .{ .secs = @intCast(@max(0, now)) };
        const year_day = secs.getEpochDay().calculateYearDay();
        const month_day = year_day.calculateMonthDay();
        const day = secs.getDaySeconds();
        const cut = std.mem.lastIndexOfAny(u8, self.path, "/\\");
        const root = if (cut) |i| self.path[0..i] else ".";
        const folder = std.fmt.allocPrint(a, "{s}/out", .{root}) catch return;
        Io.Dir.cwd().createDirPath(self.io, folder) catch return;
        const path = std.fmt.allocPrint(a, "{s}/run-log-{d:0>4}-{d:0>2}-{d:0>2}.json", .{ folder, year_day.year, @intFromEnum(month_day.month), month_day.day_index + 1 }) catch return;
        const old = Io.Dir.cwd().readFileAlloc(self.io, path, a, .limited(64 << 20)) catch "";
        var runs: usize = 1;
        var from: usize = 0;
        while (std.mem.indexOfPos(u8, old, from, "\"run\":")) |i| : (from = i + 1) runs += 1;
        var buf: std.ArrayList(u8) = .empty;
        const body = std.mem.trimEnd(u8, old, " \t\r\n");
        if (body.len > 1 and body[body.len - 1] == ']') {
            buf.appendSlice(a, body[0 .. body.len - 1]) catch return;
            buf.appendSlice(a, ",\n") catch return;
        } else buf.appendSlice(a, "[\n") catch return;
        const head = std.fmt.allocPrint(a, "  {{\"run\": {d}, \"time\": \"{d:0>2}:{d:0>2}:{d:0>2}\", \"script\": \"{s}\",\n   \"messages\": [", .{ runs, day.getHoursIntoDay(), day.getMinutesIntoHour(), day.getSecondsIntoMinute(), if (self.tree) |t| t.text else self.name }) catch return;
        buf.appendSlice(a, head) catch return;
        for (m.logs.items, 0..) |msg, i| {
            const row = std.fmt.allocPrint(a, "{s}\n     {{\"type\": \"{s}\", \"line\": {d}, \"unit\": \"{s}\", \"level\": {d}, \"message\": \"", .{ if (i > 0) "," else "", if (msg.is_error) "error" else "warning", msg.line, msg.unit, msg.level }) catch return;
            buf.appendSlice(a, row) catch return;
            for (msg.text) |ch| switch (ch) {
                '"' => buf.appendSlice(a, "\\\"") catch return,
                '\\' => buf.appendSlice(a, "\\\\") catch return,
                '\n' => buf.appendSlice(a, "\\n") catch return,
                '\r' => buf.appendSlice(a, "\\r") catch return,
                '\t' => buf.appendSlice(a, "\\t") catch return,
                else => buf.append(a, ch) catch return,
            };
            buf.appendSlice(a, "\"}") catch return;
        }
        buf.appendSlice(a, "\n   ]}\n]\n") catch return;
        Io.Dir.cwd().writeFile(self.io, .{ .sub_path = path, .data = buf.items }) catch {};
    }

    // ---- reports --------------------------------------------------------------------------

    fn ensureDir(self: *Session) void {
        Io.Dir.cwd().createDirPath(self.io, self.outdir) catch {};
    }

    fn writeReport(self: *Session, ext: []const u8, data: []const u8) void {
        const p = std.fmt.allocPrint(self.mem(), "{s}/{s}.{s}", .{ self.outdir, self.name, ext }) catch return;
        Io.Dir.cwd().writeFile(self.io, .{ .sub_path = p, .data = data }) catch {};
    }

    fn writeSummary(self: *Session) void {
        self.ensureDir();
        const p = std.fmt.allocPrint(self.mem(), "{s}/summary.log", .{self.outdir}) catch return;
        Io.Dir.cwd().writeFile(self.io, .{ .sub_path = p, .data = self.summary.items }) catch {};
    }

    /// A buffer of `n` bytes in the script's arena, wrapped as a writer: reports are rendered into it.
    fn scratch(self: *Session, n: usize) ?Io.Writer {
        const buf = self.mem().alloc(u8, n) catch return null;
        return .fixed(buf);
    }

    /// `ast [depth]`: the syntax tree as indented text, in `<outdir>/<name>.ast`.
    fn cmdAst(self: *Session, args: []const []const u8) Io.Writer.Error!void {
        const tree = self.tree orelse {
            try self.out.print("ast: {s}\n", .{if (self.arena == null) "no script loaded (use load)" else "the script is not parsed (use parse)"});
            self.status = exit_no_input;
            return;
        };
        const depth = if (args.len > 0) std.fmt.parseInt(usize, args[0], 10) catch 64 else 64;
        var w = self.scratch(8 << 20) orelse return error.WriteFailed;
        ast.dump(&w, tree, 0, depth) catch {
            try w.writeAll("\n... cut: the dump is bigger than its buffer\n");
        };
        self.ensureDir();
        self.writeReport("ast", w.buffered());
        try self.out.print("{s}: ast written ({d} bytes)\n", .{ self.name, w.buffered().len });
    }

    /// `inspect`: what the script is made of (node counts, depth), its declarations, and the
    /// result of the last run: the introspection report `<outdir>/<name>.inspect`.
    fn cmdInspect(self: *Session) Io.Writer.Error!void {
        const tree = self.tree orelse {
            try self.out.print("inspect: {s}\n", .{if (self.arena == null) "no script loaded (use load)" else "the script is not parsed (use parse)"});
            self.status = exit_no_input;
            return;
        };
        var w = self.scratch(1 << 20) orelse return error.WriteFailed;
        var stats: ast.Stats = .{};
        stats.add(tree, 0);
        w.print("script {s}\n", .{self.path}) catch {};
        stats.write(&w) catch {};
        w.writeAll("\ndeclarations\n") catch {};
        ast.outline(&w, tree, 1) catch {};
        if (self.outcome) |o| {
            w.print("\nrun: exit {d}, {d} statements, last line {d}{s}\n", .{ o.code, self.steps, self.line, if (o.stopped) ", stopped" else "" }) catch {};
        }
        if (self.machine) |m| {
            self.listVariables(&w, m, "globals", m.global);
            if (m.proc_scope) |ps| self.listVariables(&w, m, "variables of the last process", ps);
        }
        self.ensureDir();
        self.writeReport("inspect", w.buffered());
        try self.out.print("{s}: inspect written ({d} nodes, depth {d})\n", .{ self.name, stats.nodes, stats.depth });
    }

    /// Write `title` and the variables of `scope` with their type and value.
    fn listVariables(self: *Session, w: *Io.Writer, m: *interp.Interp, title: []const u8, scope: *interp.Scope) void {
        _ = self;
        w.print("\n{s}\n", .{title}) catch {};
        for (scope.binds.items) |b| {
            switch (b.v.value) {
                .func, .class, .typ => continue,
                else => {},
            }
            const builtin = [_][]const u8{ "True", "False", "Null", "_" };
            var skip = false;
            for (builtin) |n| skip = skip or std.mem.eql(u8, n, b.name);
            if (skip) continue;
            const shown = m.text(b.v.value) catch "";
            const cut = if (shown.len > 60) shown[0..60] else shown;
            w.print("  {s}{s} : {s} = {s}{s}\n", .{ b.name, if (b.v.constant) " (set)" else "", interp.Interp.typeName(b.v.value), cut, if (shown.len > 60) "..." else "" }) catch {};
        }
    }

    fn errorCount(self: *const Session) usize {
        var n: usize = if (self.parse_failed) 1 else 0;
        if (self.machine) |m| n += m.reports.items.len;
        return n;
    }

    /// `errors`: every error of the script (syntax, raised, failed expect) in `<outdir>/<name>.err`.
    fn cmdErrors(self: *Session) Io.Writer.Error!void {
        var w = self.scratch(1 << 20) orelse return error.WriteFailed;
        if (self.parse_failed) {
            w.print("{s}:{d}:{d}: syntax error: {s}\n", .{ self.path, self.diag.line, self.diag.col, self.diag.message() }) catch {};
        }
        if (self.machine) |m| {
            for (m.reports.items) |r| {
                w.print("{s}:{d}: error {d}{s}{s}: {s}{s}\n", .{
                    if (r.file.len > 0) r.file else self.path,  r.line,
                    r.code,                                     if (r.job.len > 0) " in job " else "",
                    r.job,                                      r.message,
                    if (r.handled) " (handled by recover)" else "",
                }) catch {};
            }
        }
        const n = self.errorCount();
        self.ensureDir();
        self.writeReport("err", w.buffered());
        try self.out.print("{s}: {d} error(s)\n", .{ self.name, n });
        if (n > 0) try self.out.writeAll(w.buffered());
    }

    /// `status`: one line in `<outdir>/summary.log` for the current script.
    fn cmdStatus(self: *Session) Io.Writer.Error!void {
        if (try self.logStatus()) {
            try self.out.print("{s}: status logged\n", .{self.name});
        } else {
            try self.out.writeAll("status: no script loaded, nothing to log\n");
        }
    }

    /// Add the line of the script to `summary.log` (the work of the `status` command). False when no script is loaded.
    pub fn logStatus(self: *Session) Io.Writer.Error!bool {
        if (self.name.len == 0) return false;
        const parse_word = if (self.tree != null) "ok" else if (self.parse_failed) "FAIL" else "-";
        const a = self.mem();
        const line = if (self.outcome) |o|
            std.fmt.allocPrint(a, "{s}\tparse={s}\trun={d}\tsteps={d}\terrors={d}\n", .{ self.name, parse_word, o.code, self.steps, self.errorCount() })
        else
            std.fmt.allocPrint(a, "{s}\tparse={s}\trun=-\tsteps=0\terrors={d}\n", .{ self.name, parse_word, self.errorCount() });
        self.summary.appendSlice(self.gpa, line catch return error.WriteFailed) catch return error.WriteFailed;
        self.writeSummary();
        return true;
    }

    /// The lines of `status` about this session: the script, its state, and the report folder.
    pub fn writeState(self: *const Session, w: *Io.Writer) Io.Writer.Error!void {
        if (self.name.len == 0) {
            try w.writeAll("script: none loaded (use: load <file.eve>)\n");
        } else {
            const parsed = if (self.tree != null) "parse ok" else if (self.parse_failed) "parse FAILED" else "not parsed";
            try w.print("script: {s}, {s}, ", .{ self.path, parsed });
            if (self.running) {
                try w.print("running (line {d}, {d} steps)", .{ self.line, self.steps });
            } else if (self.outcome) |o| {
                try w.print("finished with exit {d} ({d} steps)", .{ o.code, self.steps });
            } else {
                try w.writeAll("not run");
            }
            try w.print(", {d} error(s)\n", .{self.errorCount()});
        }
        try w.print("reports: folder {s}, capture {s}\n", .{ self.outdir, if (self.capture) "on" else "off" });
    }

    fn cmdReport(self: *Session) Io.Writer.Error!void {
        try self.out.print("report: pc {d}, {d} steps, {s}\n", .{ self.line, self.steps, if (self.running) "running" else "idle" });
    }

    // ---- commands -------------------------------------------------------------------------

    pub const command_names = [_][]const u8{ "load", "parse", "run", "ast", "inspect", "errors", "status", "outdir", "capture", "log", "clear", "report", "stop", "quit", "exit", "help" };

    /// Run one command. Returns false when `cmd` is not a session command.
    pub fn exec(self: *Session, cmd: []const u8, args: []const []const u8, rest: []const u8) Io.Writer.Error!bool {
        const eql = std.mem.eql;
        self.status = 0;
        if (eql(u8, cmd, "load")) {
            if (args.len == 0) {
                try self.out.writeAll("load: file name missing\n");
                self.status = 64;
            } else {
                try self.load(args[0]);
                if (self.arena != null) try self.out.print("{s}: loaded\n", .{self.name});
            }
        } else if (eql(u8, cmd, "parse")) {
            if (args.len > 0) try self.load(args[0]);
            if (self.arena != null) try self.parse() else if (args.len == 0) try self.parse();
        } else if (eql(u8, cmd, "run")) {
            if (args.len > 0) try self.load(args[0]);
            if (self.arena != null or args.len == 0) try self.run();
        } else if (eql(u8, cmd, "ast")) {
            try self.cmdAst(args);
        } else if (eql(u8, cmd, "inspect")) {
            try self.cmdInspect();
        } else if (eql(u8, cmd, "errors")) {
            try self.cmdErrors();
        } else if (eql(u8, cmd, "status")) {
            try self.cmdStatus();
        } else if (eql(u8, cmd, "outdir")) {
            if (args.len == 0) {
                try self.out.print("outdir: {s}\n", .{self.outdir});
            } else {
                self.outdir = self.gpa.dupe(u8, args[0]) catch return error.WriteFailed;
                self.ensureDirNow();
            }
        } else if (eql(u8, cmd, "capture")) {
            self.capture = args.len == 0 or !eql(u8, args[0], "off");
        } else if (eql(u8, cmd, "log")) {
            self.summary.appendSlice(self.gpa, rest) catch return error.WriteFailed;
            self.summary.append(self.gpa, '\n') catch return error.WriteFailed;
            self.writeSummaryNow();
        } else if (eql(u8, cmd, "clear")) {
            self.forget();
        } else if (eql(u8, cmd, "report")) {
            try self.cmdReport();
        } else if (eql(u8, cmd, "stop") or eql(u8, cmd, "quit") or eql(u8, cmd, "exit")) {
            self.stopping = true;
        } else if (eql(u8, cmd, "help")) {
            for (command_names) |c| try self.out.print("  {s}\n", .{c});
        } else return false;
        return true;
    }

    fn ensureDirNow(self: *Session) void {
        Io.Dir.cwd().createDirPath(self.io, self.outdir) catch {};
    }

    fn writeSummaryNow(self: *Session) void {
        self.ensureDirNow();
        const p = std.fmt.allocPrint(self.gpa, "{s}/summary.log", .{self.outdir}) catch return;
        Io.Dir.cwd().writeFile(self.io, .{ .sub_path = p, .data = self.summary.items }) catch {};
    }

    /// Run one command line (of the REPL or of `vm.eval`). While a script runs, only `report` and `stop` work.
    pub fn handleLine(self: *Session, line: []const u8) Io.Writer.Error!void {
        const t = clean(line);
        if (t.len == 0) return;
        var words: [max_words][]const u8 = undefined;
        var n: usize = 0;
        var it = std.mem.tokenizeAny(u8, t, " \t");
        while (it.next()) |w| {
            if (n == words.len) break;
            words[n] = w;
            n += 1;
        }
        const cmd = words[0];
        const rest = std.mem.trim(u8, t[cmd.len..], " \t");
        var known = false;
        for (command_names) |c| known = known or std.mem.eql(u8, c, cmd);
        if (!known) {
            try self.out.print("unknown command: {s}\n", .{t});
            return;
        }
        if (self.running and !(std.mem.eql(u8, cmd, "report") or std.mem.eql(u8, cmd, "stop") or
            std.mem.eql(u8, cmd, "quit") or std.mem.eql(u8, cmd, "exit")))
        {
            try self.out.print("busy, '{s}' ignored while a script runs\n", .{cmd});
            return;
        }
        if (!try self.exec(cmd, words[1..n], rest)) try self.out.print("unknown command: {s}\n", .{t});
    }

    pub fn deinit(self: *Session) void {
        self.forget();
    }
};

test "comments are removed from command lines" {
    try std.testing.expectEqualStrings("report", clean(" report\r"));
    try std.testing.expectEqualStrings("report", clean("report ** show the state"));
    try std.testing.expectEqualStrings("", clean("** stop"));
    try std.testing.expectEqualStrings("", clean("  # stop"));
    try std.testing.expectEqualStrings("", clean("   "));
    try std.testing.expectEqualStrings("frob", clean(" frob  ** why\r"));
}

test "a session parses and runs a script from text" {
    var buf: [512]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var s: Session = .{ .io = std.testing.io, .gpa = std.testing.allocator, .out = &w };
    defer s.deinit();
    defer s.summary.deinit(std.testing.allocator);
    try s.loadSource("t/a.eve", "primary aspect a is process main is print \"hi\"; return; end a;\n");
    try s.handleLine("run  ** parses first");
    try std.testing.expectEqualStrings("a: parse ok, 9 nodes\nhi\n", w.buffered());
    try std.testing.expectEqual(@as(u8, 0), s.status);
}

test "a syntax error is reported with its position and the run does not start" {
    var buf: [512]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var s: Session = .{ .io = std.testing.io, .gpa = std.testing.allocator, .out = &w };
    defer s.deinit();
    try s.loadSource("bad.eve", "print 1 +;\n");
    try s.handleLine("run");
    try std.testing.expect(std.mem.startsWith(u8, w.buffered(), "bad.eve:1:"));
    try std.testing.expectEqual(@as(u8, exit_syntax), s.status);
}

test "report and stop commands, unknown words" {
    var buf: [512]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var s: Session = .{ .io = std.testing.io, .gpa = std.testing.allocator, .out = &w };
    defer s.deinit();
    try s.handleLine("report");
    try s.handleLine("frob ** not a command");
    try std.testing.expectEqualStrings("report: pc 0, 0 steps, idle\nunknown command: frob\n", w.buffered());
    try std.testing.expect(!s.stopping);
    try s.handleLine("stop");
    try std.testing.expect(s.stopping);
}
