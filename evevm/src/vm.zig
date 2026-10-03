//! The virtual machine session: it holds one script at a time (loaded, parsed, executed) and the
//! slot that receives external commands while it works.
//!
//! The slot is a text file (`eve -i commands.vmc`). Anything can append lines to it while the VM
//! runs: a batch (`echo report >> commands.vmc`), a Python script, an editor. One command per line.
//! A file was chosen over a pipe or a socket because every language and every shell can write one.
//! The manual describes the commands and the comments (manual/usage.md, "Command files").
//!
//! A workflow is a command file such as `load a.eve`, `parse`, `run`, `errors`, `ast`, `inspect`,
//! `status`, repeated for each script and ended by `stop`. The VM is started once (`eve -x -i
//! level1.vmc`), works through the file, and leaves its reports in a folder for later reading.
const std = @import("std");
const Io = std.Io;
const ast = @import("ast.zig");
const parser = @import("parser.zig");
const interp = @import("interp.zig");

// Zig tip: a function with no side effect, like `clean`, is the easiest kind to test. `std.mem.trim(u8,
// s, " \t\r")` cuts the listed characters at both ends of a slice (a view, nothing is copied).
// `std.mem.indexOf(u8, hay, needle)` returns `?usize`; `orelse line.len` keeps the whole line
// when there is no comment. The function returns a slice of its input (or the literal `""`), so
// nothing is allocated and nothing needs freeing.
/// The command of one slot line: comments and blanks removed. A line whose first character is
/// `#`, and everything from `**` to the end of a line, is a comment (the same marks as Eve).
pub fn clean(line: []const u8) []const u8 {
    const code = line[0 .. std.mem.indexOf(u8, line, "**") orelse line.len];
    const t = std.mem.trim(u8, code, " \t\r");
    return if (t.len > 0 and t[0] == '#') "" else t;
}

// Zig tip: a struct can own memory. `data` is a slice that this struct allocated, so the struct
// must free it: that is what `deinit` is for, and the caller pairs `init` with
// `defer slot.deinit()`. Zig has no destructors that run by themselves.
/// Reads new lines appended to a file. The file may not exist yet; that means "no commands".
/// A line is delivered only once it is complete (ends with a newline), so a writer that is in
/// the middle of a line is never read half way.
pub const Slot = struct {
    io: Io,
    gpa: std.mem.Allocator,
    path: []const u8,
    /// The last copy of the file, owned by the slot.
    data: []u8 = &.{},
    /// Bytes already delivered; the next line starts here.
    cursor: usize = 0,
    /// End of the last complete line in `data`.
    end: usize = 0,

    // Zig tip: a function whose first parameter is the struct (`p: *Parser`) is called with dot
    // syntax: `p.name(...)`.
    pub fn deinit(self: *Slot) void {
        self.gpa.free(self.data);
    }

    // Zig tip: `catch return` in a function that returns nothing means "on any error, give up
    // quietly": a missing file or a failed read is not a failure here, it is just no news.
    // `std.mem.lastIndexOfScalar` finds the last byte equal to a value, or returns null; `if (x)
    // |i| ... else ...` unwraps that optional. Freeing the old copy before the new one is
    // assigned keeps exactly one copy alive.
    fn refill(self: *Slot) void {
        const bytes = Io.Dir.cwd().readFileAlloc(self.io, self.path, self.gpa, .limited(1 << 20)) catch return;
        self.gpa.free(self.data);
        self.data = bytes;
        self.end = if (std.mem.lastIndexOfScalar(u8, bytes, '\n')) |i| i + 1 else 0;
        if (self.cursor > self.end) self.cursor = self.end; // the file was truncated
    }

    // Zig tip: the result `?[]const u8` is a line or null (nothing new). The slice points into
    // `data`, so it is valid only until the next call that refills: use it at once.
    /// The next complete line, not consumed: `peek` again gives the same line until `next` is called.
    pub fn peek(self: *Slot) ?[]const u8 {
        if (self.cursor >= self.end) self.refill();
        if (self.cursor >= self.end) return null;
        const stop = std.mem.indexOfScalarPos(u8, self.data, self.cursor, '\n').?;
        return self.data[self.cursor..stop];
    }

    // Zig tip: `a orelse b` unwraps an optional: it gives `b` when `a` is null, and `b` may leave
    // the function with `return`.
    /// The next complete line, consumed, or null when there is nothing new.
    pub fn next(self: *Slot) ?[]const u8 {
        const line = self.peek() orelse return null;
        self.cursor += line.len + 1;
        return line;
    }
};

/// Exit status when a file cannot be read (EX_NOINPUT) and when it has syntax errors (EX_DATAERR).
pub const exit_no_input = 66;
pub const exit_syntax = 65;

/// Words of a command line, at most this many.
const max_words = 16;

// Zig tip: a struct holds the whole state of the machine, so a command is a method that changes
// it. Fields with a default (`= ""`, `= null`) need not be given when the struct is built. The
// per-script memory is an arena: `load` drops the previous one with `deinit`, so a session of
// hundreds of scripts does not grow. `std.heap.page_allocator` is the allocator that asks the
// operating system for memory directly; the arena is built on top of it.
/// One VM session. Commands are the `exec` methods below; the REPL and the slot both call them.
pub const Session = struct {
    io: Io,
    gpa: std.mem.Allocator,
    out: *Io.Writer,
    slot: ?*Slot = null,
    /// Folder of the report files (`outdir`).
    outdir: []const u8 = "temp/output",
    /// Print only errors (the command line `eve script.eve`): the output is the script's own.
    quiet: bool = false,
    /// Keep the program output in a file (`<outdir>/<name>.out`) instead of writing it to `out`.
    capture: bool = false,
    /// The `halt` flag of the command line (not used yet).
    debug: bool = false,
    /// Exit status of the last command.
    status: u8 = 0,
    /// Set by `stop`: the loop that reads commands ends.
    stopping: bool = false,
    running: bool = false,
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
    parse_failed: bool = false,
    machine: ?*interp.Interp = null,
    outcome: ?interp.Outcome = null,

    /// The text of `summary.log`, one line per `status` or `log`.
    summary: std.ArrayList(u8) = .empty,

    // Zig tip: `mem` relies on the same Zig feature as `deinit` above: see the tip there.
    /// The memory of the current script.
    fn mem(self: *Session) std.mem.Allocator {
        return self.arena.?.allocator();
    }

    // Zig tip: `if (opt) |v| ... else ...` runs the first branch only when the optional has a value,
    // and names it `v`.
    fn forget(self: *Session) void {
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
    }

    // ---- loading, parsing, running --------------------------------------------------------

    // Zig tip: `std.fs.path.stem` was moved in 0.16; the name of the script is cut by hand:
    // after the last `/` or `\`, before the last `.`. `std.mem.lastIndexOfAny` finds the last byte
    // that is in a set. `self.arena = .init(page_allocator)` assigns a fresh arena to the optional.
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

    // Zig tip: `x catch |e| ...` handles the error of a call on the spot, where `try` would pass it
    // up to the caller.
    /// Use `src` (kept by the caller for as long as the session needs it) as the current script.
    pub fn loadSource(self: *Session, path: []const u8, src: []const u8) Io.Writer.Error!void {
        if (self.arena == null) self.arena = .init(std.heap.page_allocator);
        self.path = self.mem().dupe(u8, path) catch return error.WriteFailed;
        const cut = std.mem.lastIndexOfAny(u8, path, "/\\");
        self.setName(if (cut) |i| path[i + 1 ..] else path, src);
    }

    // Zig tip: `setName` relies on the same Zig feature as `loadSource` above: see the tip there.
    fn setName(self: *Session, base: []const u8, src: []const u8) void {
        const stem = base[0 .. std.mem.lastIndexOfScalar(u8, base, '.') orelse base.len];
        self.name = self.mem().dupe(u8, stem) catch stem;
        self.src = src;
        self.tree = null;
        self.parse_failed = false;
        self.machine = null;
        self.outcome = null;
        self.diag = .{};
        self.status = 0;
    }

    // Zig tip: a `switch` is an expression: it must cover every case, or end with `else`, and the
    // compiler checks it.
    /// `parse`: build the syntax tree. A syntax error is printed as `file:line:col: error: text`.
    pub fn parse(self: *Session) Io.Writer.Error!void {
        if (self.arena == null) {
            try self.out.writeAll("parse: no script loaded (use load)\n");
            self.status = exit_no_input;
            return;
        }
        self.tree = null;
        self.diag = .{};
        if (parser.parse(self.mem(), self.src, &self.diag)) |tree| {
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
                error.Syntax => try self.out.print("{s}:{d}:{d}: error: {s}\n", .{ self.path, self.diag.line, self.diag.col, self.diag.message() }),
                error.OutOfMemory => try self.out.print("{s}: out of memory\n", .{self.path}),
            }
        }
    }

    // Zig tip: builtin functions start with `@`: they are the compiler's own, such as conversions
    // (`@intCast`, `@as`) and `@min`/`@max`.
    fn pollHook(ctx: *anyopaque, steps: usize, line: u32) bool {
        const self: *Session = @ptrCast(@alignCast(ctx));
        self.steps = steps;
        self.line = line;
        self.drainRunning();
        return self.stopping;
    }

    // Zig tip: `@ptrCast(@alignCast(ctx))` turns the `*anyopaque` the hook carries back into a
    // `*Session`: the interpreter stored it without knowing the type, and only this file knows what
    // it really is. The destination type comes from the declaration on the left. `.run` keeps
    // the previous parse when it is already there ("parse first, only once").
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
        const machine = a.create(interp.Interp) catch return error.WriteFailed;
        machine.* = interp.Interp.init(a, cap orelse self.out) catch return error.WriteFailed;
        machine.hook = .{ .ctx = self, .poll = pollHook };
        self.machine = machine;
        self.steps = 0;
        self.line = 0;
        self.running = true;
        const o = machine.run(tree);
        self.running = false;
        self.steps = machine.steps;
        self.outcome = o;
        self.status = o.code;
        if (cap) |w| {
            self.ensureDir();
            self.writeReport("out", w.buffered());
            try self.out.print("{s}: run, exit {d}{s}\n", .{ self.name, o.code, if (o.stopped) ", stopped" else "" });
        }
    }

    // ---- reports --------------------------------------------------------------------------

    // Zig tip: `ensureDir` relies on the same Zig feature as `loadSource` above: see the tip there.
    fn ensureDir(self: *Session) void {
        Io.Dir.cwd().createDirPath(self.io, self.outdir) catch {};
    }

    // Zig tip: `std.fs.path.join` is replaced here by `allocPrint`, which builds `dir/name.ext` in
    // the arena. `catch return` abandons a report that cannot be written: a missing report must not
    // stop the machine. `Io.Dir.cwd().writeFile(io, .{ .sub_path = ..., .data = ... })` creates or
    // replaces a whole file.
    fn writeReport(self: *Session, ext: []const u8, data: []const u8) void {
        const p = std.fmt.allocPrint(self.mem(), "{s}/{s}.{s}", .{ self.outdir, self.name, ext }) catch return;
        Io.Dir.cwd().writeFile(self.io, .{ .sub_path = p, .data = data }) catch {};
    }

    // Zig tip: `std.ArrayList(T)` is a growable array: it starts `.empty`, `append(allocator, x)`
    // adds, `.items` is the slice of what it holds.
    fn writeSummary(self: *Session) void {
        self.ensureDir();
        const p = std.fmt.allocPrint(self.mem(), "{s}/summary.log", .{self.outdir}) catch return;
        Io.Dir.cwd().writeFile(self.io, .{ .sub_path = p, .data = self.summary.items }) catch {};
    }

    // Zig tip: `scratch` relies on the same Zig feature as `loadSource` above: see the tip there.
    /// A buffer of `n` bytes in the script's arena, wrapped as a writer: reports are rendered into it.
    fn scratch(self: *Session, n: usize) ?Io.Writer {
        const buf = self.mem().alloc(u8, n) catch return null;
        return .fixed(buf);
    }

    // Zig tip: `try f()` calls `f` and, when it returns an error, returns that error from this
    // function too.
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

    // Zig tip: `cmdInspect` relies on the same Zig feature as `cmdAst` above: see the tip there.
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

    // Zig tip: `switch (b.v.value)` with `continue` skips the bindings that are not data (functions,
    // classes, type names). `catch ""` gives an empty text when the value cannot be shown. The
    // built-in names (`True`, `Null`, `_`, ...) are constants defined before the script: they are
    // left out by name so the list shows only what the script created.
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

    // Zig tip: `errorCount` relies on the same Zig feature as `writeSummary` above: see the tip
    // there.
    fn errorCount(self: *const Session) usize {
        var n: usize = if (self.parse_failed) 1 else 0;
        if (self.machine) |m| n += m.reports.items.len;
        return n;
    }

    // Zig tip: `for (xs) |x| ...` walks a slice; `for (xs, 0..) |x, i|` also gives the index.
    /// `errors`: every error of the script (syntax, raised, failed expect) in `<outdir>/<name>.err`.
    fn cmdErrors(self: *Session) Io.Writer.Error!void {
        var w = self.scratch(1 << 20) orelse return error.WriteFailed;
        if (self.parse_failed) {
            w.print("{s}:{d}:{d}: syntax error: {s}\n", .{ self.path, self.diag.line, self.diag.col, self.diag.message() }) catch {};
        }
        if (self.machine) |m| {
            for (m.reports.items) |r| {
                w.print("{s}:{d}: error {d}{s}{s}: {s}{s}\n", .{
                    self.path,                                  r.line,
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

    // Zig tip: `cmdStatus` relies on the same Zig feature as `cmdAst` above: see the tip there.
    /// `status`: one line in `<outdir>/summary.log` for the current script.
    fn cmdStatus(self: *Session) Io.Writer.Error!void {
        const parse_word = if (self.tree != null) "ok" else if (self.parse_failed) "FAIL" else "-";
        const a = self.mem();
        const line = if (self.outcome) |o|
            std.fmt.allocPrint(a, "{s}\tparse={s}\trun={d}\tsteps={d}\terrors={d}\n", .{ self.name, parse_word, o.code, self.steps, self.errorCount() })
        else
            std.fmt.allocPrint(a, "{s}\tparse={s}\trun=-\tsteps=0\terrors={d}\n", .{ self.name, parse_word, self.errorCount() });
        self.summary.appendSlice(self.gpa, line catch return error.WriteFailed) catch return error.WriteFailed;
        self.writeSummary();
        try self.out.print("{s}: status logged\n", .{self.name});
    }

    // Zig tip: `cmdReport` relies on the same Zig feature as `cmdAst` above: see the tip there.
    fn cmdReport(self: *Session) Io.Writer.Error!void {
        try self.out.print("report: pc {d}, {d} steps, {s}\n", .{ self.line, self.steps, if (self.running) "running" else "idle" });
    }

    // ---- commands -------------------------------------------------------------------------

    pub const command_names = [_][]const u8{ "load", "parse", "run", "ast", "inspect", "errors", "status", "outdir", "capture", "log", "clear", "report", "stop", "quit", "exit", "help" };

    // Zig tip: one `if` per command name is the plainest dispatch: `std.mem.eql(u8, cmd, "load")`
    // compares text. The function returns `false` for a name it does not know, so the caller can say
    // "unknown command". A word list (`args`) is a slice of slices of bytes: `args[0]` is the first
    // argument, and `std.mem.join` would glue them back when a command takes the rest of the line.
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

    // Zig tip: `ensureDirNow` relies on the same Zig feature as `loadSource` above: see the tip
    // there.
    fn ensureDirNow(self: *Session) void {
        Io.Dir.cwd().createDirPath(self.io, self.outdir) catch {};
    }

    // Zig tip: `writeSummaryNow` relies on the same Zig feature as `writeSummary` above: see the tip
    // there.
    fn writeSummaryNow(self: *Session) void {
        self.ensureDirNow();
        const p = std.fmt.allocPrint(self.gpa, "{s}/summary.log", .{self.outdir}) catch return;
        Io.Dir.cwd().writeFile(self.io, .{ .sub_path = p, .data = self.summary.items }) catch {};
    }

    // Zig tip: `tokenizeAny` splits a line on blanks without allocating. `it.rest()` is the text
    // not yet consumed, used here to give `log` the whole remainder of the line. While a script runs
    // only a few commands are allowed: Zig's single thread cannot load another script in the middle
    // of the first one.
    /// Run one line of the slot (or of the REPL). While a script runs, only `report` and `stop` work.
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
            try self.out.print("slot: unknown command: {s}\n", .{t});
            return;
        }
        if (self.running and !(std.mem.eql(u8, cmd, "report") or std.mem.eql(u8, cmd, "stop") or
            std.mem.eql(u8, cmd, "quit") or std.mem.eql(u8, cmd, "exit")))
        {
            try self.out.print("slot: busy, '{s}' ignored while a script runs\n", .{cmd});
            return;
        }
        if (!try self.exec(cmd, words[1..n], rest)) try self.out.print("slot: unknown command: {s}\n", .{t});
    }

    // Zig tip: a hook that runs in the middle of a script must not eat the commands meant for after
    // it. `peek` looks at the next line without consuming it; the loop stops in front of a command
    // that needs an idle machine (`load`, `parse`, `run`, ...), which stays in the slot, in order,
    // for the serve loop. Blank lines, comments, `report`, `stop` and unknown words are consumed.
    /// Run the new lines of the slot, while a script runs: only the ones allowed then.
    fn drainRunning(self: *Session) void {
        const s = self.slot orelse return;
        while (s.peek()) |line| {
            const t = clean(line);
            if (t.len > 0) {
                var it = std.mem.tokenizeAny(u8, t, " \t");
                const cmd = it.next().?;
                if (isCommand(cmd) and !isControl(cmd)) return;
            }
            _ = s.next();
            self.handleLine(line) catch {};
        }
    }

    // Zig tip: `std.mem.eql(u8, a, b)` compares two slices by content; `==` on slices would compare
    // their addresses.
    fn isCommand(cmd: []const u8) bool {
        for (command_names) |c| if (std.mem.eql(u8, c, cmd)) return true;
        return false;
    }

    // Zig tip: `isControl` relies on the same Zig feature as `isCommand` above: see the tip there.
    /// The commands that are allowed while a script runs.
    fn isControl(cmd: []const u8) bool {
        const eql = std.mem.eql;
        return eql(u8, cmd, "report") or eql(u8, cmd, "stop") or eql(u8, cmd, "quit") or eql(u8, cmd, "exit");
    }

    // Zig tip: `while (cond) { ... }` repeats; `while (opt) |v|` repeats as long as an optional has
    // a value.
    /// Run every new line of the slot (the machine is idle).
    pub fn drain(self: *Session) void {
        if (self.slot) |s| {
            while (s.next()) |line| self.handleLine(line) catch {};
        }
    }

    // Zig tip: `self.io.sleep(duration, clock)` pauses the program without using the processor; the
    // `Io` value is how Zig 0.16 reaches the operating system. `.fromMilliseconds(25)` builds the
    // duration; `.awake` is the clock that counts time while the machine runs. `catch {}` ignores
    // the "cancelled" error: nobody cancels this program. The loop ends on `stop` or after
    // `idle_ms` milliseconds without a command (so a forgotten `stop` does not hang a batch).
    /// Serve mode: with no script, wait for commands in the slot until `stop`.
    pub fn serve(self: *Session, idle_ms: u64) Io.Writer.Error!void {
        var idle: u64 = 0;
        while (!self.stopping) {
            const before = if (self.slot) |s| s.cursor else 0;
            self.drain();
            try self.out.flush();
            if (self.stopping) break;
            const after = if (self.slot) |s| s.cursor else 0;
            if (after != before) {
                idle = 0;
                continue;
            }
            if (idle >= idle_ms) {
                try self.out.writeAll("serve: idle timeout, stopping\n");
                self.status = 75;
                break;
            }
            self.io.sleep(.fromMilliseconds(25), .awake) catch {};
            idle += 25;
        }
        if (self.stopping) try self.out.writeAll("serve: stopped\n");
    }

    // Zig tip: `deinit` relies on the same Zig feature as `deinit` above: see the tip there.
    pub fn deinit(self: *Session) void {
        self.forget();
    }
};

// Zig tip: a `test` block runs under `zig build test`; `try std.testing.expect...` fails it when the
// value is not the expected one.
test "comments are removed from slot lines" {
    try std.testing.expectEqualStrings("report", clean(" report\r"));
    try std.testing.expectEqualStrings("report", clean("report ** show the state"));
    try std.testing.expectEqualStrings("", clean("** stop"));
    try std.testing.expectEqualStrings("", clean("  # stop"));
    try std.testing.expectEqualStrings("", clean("   "));
    try std.testing.expectEqualStrings("frob", clean(" frob  ** why\r"));
}

// Zig tip: `.fixed(&buf)` makes a Writer that fills a byte array, so the test can read the
// output with `w.buffered()`. The session is built with a struct literal; fields not named take
// their defaults. `defer s.deinit()` frees the arena of the loaded script at the end of the test.
test "a session parses and runs a script from text" {
    var buf: [512]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var s: Session = .{ .io = std.testing.io, .gpa = std.testing.allocator, .out = &w };
    defer s.deinit();
    defer s.summary.deinit(std.testing.allocator);
    try s.loadSource("t/a.eve", "print \"hi\";\n");
    try s.handleLine("run  ** parses first");
    try std.testing.expectEqualStrings("a: parse ok, 3 nodes\nhi\n", w.buffered());
    try std.testing.expectEqual(@as(u8, 0), s.status);
}

// Zig tip: `a syntax error is reported with its position and the run does not start` relies on the
// same Zig feature as `comments are removed from slot lines` above: see the tip there.
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

// Zig tip: `report and stop commands, unknown words` relies on the same Zig feature as `comments are
// removed from slot lines` above: see the tip there.
test "report and stop commands, unknown words" {
    var buf: [512]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var s: Session = .{ .io = std.testing.io, .gpa = std.testing.allocator, .out = &w };
    defer s.deinit();
    try s.handleLine("report");
    try s.handleLine("frob ** not a command");
    try std.testing.expectEqualStrings("report: pc 0, 0 steps, idle\nslot: unknown command: frob\n", w.buffered());
    try std.testing.expect(!s.stopping);
    try s.handleLine("stop");
    try std.testing.expect(s.stopping);
}
