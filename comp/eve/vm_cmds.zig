//! The commands of the runtime part (`eve vm`): `execute`, `status`, `stop`, the doors `listen` and `serve`.
//! Part of the `eve` command (cli.zig holds the table of the commands and the REPL loop).
const std = @import("std");
const Io = std.Io;
const version = @import("evecm").version;
const ast = @import("evecm").ast;
const vm = @import("evevm").vm;
const client = @import("evevm").client;
const daemon = @import("evevm").daemon;
const channel = @import("evevm").channel;
const screen = @import("evevm").screen;
const tui = @import("evevm").tui;
const context = @import("context.zig");
const cli = @import("cli.zig");
// Zig tip: the shared names come from context.zig under short local names (`const Context = context.Context;`):
// the same type, not a copy. Files of one module may import each other, also in a circle.
const Context = context.Context;
const Handler = context.Handler;
const exit_usage = context.exit_usage;
const prompt = context.prompt;
const stub = context.stub;

// Zig tip: `catch return error.WriteFailed` turns the errors of the stop (out of memory, a failed write) into the one
// error that a handler of this table may return. The text is written before the call is made, and flushed, so that the
// screen shows it even if the stop takes a moment.
/// `stop`: close the doors this process opened (ipc and http together), tell the running scripts to stop, and stay at
/// the prompt. With no door open here, it stops the machine of another process (the one `evevm` started).
// Zig tip: the words of the line were split at the spaces; `std.mem.join` puts them back with one space, which is right
// for the table of commands (the prompt itself calls `shellLine` with the line as it was typed).
/// `shell <command>`: run a command of the system; the prompt stays in eve.
pub fn cmdShell(ctx: *Context, args: []const []const u8) Io.Writer.Error!void {
    const line = std.mem.join(ctx.gpa, " ", args) catch return error.WriteFailed;
    return shellLine(ctx, line);
}

// Zig tip: `channel.runShell` writes the output of the command to `ctx.out` while it comes (the upper part of the
// full-screen prompt, or the plain screen) and answers its exit code, which becomes the status of the prompt.
/// Run `text` in the system shell, in the current folder; `exit` is not needed: eve stays.
pub fn shellLine(ctx: *Context, text: []const u8) Io.Writer.Error!void {
    const command = std.mem.trim(u8, text, " \t\r");
    if (command.len == 0) {
        try ctx.out.writeAll("shell: give the command, for example: shell dir   (or !dir)\n");
        ctx.status = exit_usage;
        return;
    }
    ctx.status = channel.runShell(ctx.io, ctx.gpa, command, "", ctx.out);
    if (ctx.status != 0) try ctx.out.print("shell: exit {d}\n", .{ctx.status});
}

// Zig tip: at the prompt of `eve` the folder is the folder of the process, so `cd` changes it for real (`setCurrentPath`) and
// the commands that follow, of Eve or of the shell, start there. `currentPathAlloc` gives the new folder back as the system
// spells it. An error of the system (no such folder) is printed, as a shell prints it.
/// `cd [folder]` at the prompt: show or change the folder.
pub fn cdLine(ctx: *Context, text: []const u8) Io.Writer.Error!void {
    var arg = std.mem.trim(u8, text, " \t\r");
    // `cd /d <folder>` of the Windows shell
    if (arg.len > 3 and std.ascii.eqlIgnoreCase(arg[0..3], "/d ")) arg = std.mem.trim(u8, arg[3..], " \t");
    arg = std.mem.trim(u8, arg, "\"");
    if (arg.len > 0) {
        std.process.setCurrentPath(ctx.io, arg) catch |err| {
            try ctx.out.print("cd: {s}: {s}\n", .{ arg, @errorName(err) });
            ctx.status = 1;
            return;
        };
    }
    const here = std.process.currentPathAlloc(ctx.io, ctx.gpa) catch return;
    defer ctx.gpa.free(here);
    try ctx.out.print("{s}\n", .{here});
    ctx.status = 0;
}

pub fn cmdStop(ctx: *Context, _: []const []const u8) Io.Writer.Error!void {
    try ctx.out.flush();
    ctx.status = daemon.stopMachines(ctx.io, ctx.gpa, ctx.out, ctx.config orelse "eve.cfg") catch return error.WriteFailed;
}

// the next command finds the script the previous one loaded. `gpa.create(T)` allocates one `T` and
// returns a pointer; `s.* = .{ ... }` fills it. A `?*T` field is null until then, and `orelse`
// would also do: `if (ctx.machine) |s| return s;` is the early-return form.
/// The session of this run of `eve`.
pub fn session(ctx: *Context) Io.Writer.Error!*vm.Session {
    if (ctx.machine) |s| return s;
    const s = ctx.gpa.create(vm.Session) catch return error.WriteFailed;
    s.* = .{ .io = ctx.io, .gpa = ctx.gpa, .out = ctx.out, .debug = ctx.debug };
    ctx.machine = s;
    return s;
}

// Zig tip: `viaSession("load")` is a comptime function like `stub`: it returns a handler for one
// session command. `std.mem.join(gpa, " ", args)` glues the words back into one string (the
// `log` command takes the rest of the line). `ctx.status = s.status` copies the exit status of the
// command, and a `stop` from the session ends the REPL too.
/// A REPL command that is implemented by the session (vm.zig): `load`, `parse`, `ast`, ...
pub fn viaSession(comptime name: []const u8) Handler {
    return struct {
        fn run(ctx: *Context, args: []const []const u8) Io.Writer.Error!void {
            const s = try session(ctx);
            const rest = std.mem.join(ctx.gpa, " ", args) catch return error.WriteFailed;
            _ = try s.exec(name, args, rest);
            ctx.status = s.status;
            if (s.stopping) ctx.quit = true;
        }
    }.run;
}

// Zig tip: `comptime listen: bool` makes two handlers from one function, `door(true)` for `listen` and `door(false)`
// for `serve`, as `viaSession` does for the session commands. The words are read in any order: `start`, `stop`,
// `restart` or `status` is the action, and the other door's name adds that door (`listen serve` opens both).
/// `listen [word]` and `serve [word]` in the REPL: the same as `--listen` and `--serve`, but the doors open in this
/// process and the prompt stays.
pub fn door(comptime listen: bool) Handler {
    return struct {
        fn run(ctx: *Context, args: []const []const u8) Io.Writer.Error!void {
            var cmd: client.Cmd = .{ .listen = listen, .serve = !listen, .config = ctx.config };
            for (args) |w| {
                if (std.mem.eql(u8, w, "listen")) {
                    cmd.listen = true;
                } else if (std.mem.eql(u8, w, "serve")) {
                    cmd.serve = true;
                } else if (cmd.word.len == 0) {
                    cmd.word = w;
                } else {
                    try ctx.out.print("{s}: unexpected word: {s}\n", .{ if (listen) "listen" else "serve", w });
                    ctx.status = exit_usage;
                    return;
                }
            }
            const known = [_][]const u8{ "", "start", "stop", "restart", "status" };
            for (known) |k| if (std.mem.eql(u8, k, cmd.word)) break else {} else {
                try ctx.out.print("{s}: expected start, stop, restart or status, not {s}\n", .{ if (listen) "listen" else "serve", cmd.word });
                ctx.status = exit_usage;
                return;
            }
            try ctx.out.flush();
            const code = client.handle(ctx.io, ctx.gpa, ctx.out, cmd, true) catch return error.WriteFailed;
            ctx.status = code orelse 0;
        }
    }.run;
}

// Zig tip: a handler ignores the arguments it does not need with `_ = args;`: Zig reports an unused parameter as an
// error, so this line says "not used, on purpose". The report is only text written to `ctx.out`; it opens no door.
/// `status`: the machine in one page. The process (version, script, folder of the reports), then the configuration,
/// the doors and what a machine on them is doing. The line of the script in `summary.log` is still added.
pub fn cmdStatus(ctx: *Context, args: []const []const u8) Io.Writer.Error!void {
    _ = args;
    const s = try session(ctx);
    _ = try s.logStatus();
    try ctx.out.print("{s}\nthis process: command line, it opens no door itself\n", .{version.title});
    try s.writeState(ctx.out);
    try ctx.out.flush();
    client.machineStatus(ctx.io, ctx.gpa, ctx.out, ctx.config orelse "eve.cfg") catch return error.WriteFailed;
}

// Zig tip: a stack buffer for the reader of the standard input lives as long as the function; the debugger keeps a
// pointer to the reader (`&reader.interface`), which is fine because `s.run()` ends before the function does. The
// debugger itself is allocated with `gpa.create` because the session keeps a pointer to it in `s.dbg`.
/// `debug <file>`: run the script under the debugger. It stops before the first statement and reads commands (run,
/// halt, next, step, exit, trace, break, clear) from the standard input; see comp/evevm/src/debugger.zig.
pub fn cmdDebug(ctx: *Context, args: []const []const u8) Io.Writer.Error!void {
    if (args.len == 0) {
        try ctx.out.writeAll("debug: file name missing\n");
        ctx.status = exit_usage;
        return;
    }
    const s = try session(ctx);
    s.quiet = true;
    s.capture = false;
    s.script_args = args[1..];
    try s.load(args[0]);
    if (s.arena == null) {
        ctx.status = s.status;
        return;
    }
    var buf: [4096]u8 = undefined;
    var reader: Io.File.Reader = .init(.stdin(), ctx.io, &buf);
    const d = ctx.gpa.create(@import("evevm").debugger.Debugger) catch return error.WriteFailed;
    defer ctx.gpa.destroy(d);
    d.* = .{ .out = ctx.out, .in = &reader.interface, .io = ctx.io, .gpa = ctx.gpa };
    s.dbg = d;
    defer s.dbg = null;
    try s.run();
    ctx.status = s.status;
    if (s.outcome) |o| {
        if (o.code != 0 and s.machine != null) {
            try ctx.out.flush();
            for (s.machine.?.reports.items) |r| {
                if (!r.handled) std.debug.print("{s}:{d}: error {d}: {s}\n{s}{s}", .{ args[0], r.line, r.code, r.message, r.trace, r.details });
            }
        }
    }
}

// Zig tip: parse first, run second: the session's `run` parses the file when it was not parsed,
// and returns early on a syntax error, so a script with errors never starts. Unhandled errors go
// to stderr, so the standard output stays what the script printed.
/// `execute`: parse the script (as `check` does) and, only if it is correct, run its main process.
pub fn cmdExecute(ctx: *Context, args: []const []const u8) Io.Writer.Error!void {
    const s = try session(ctx);
    if (args.len == 0) {
        try ctx.out.writeAll("execute: file name missing\n");
        ctx.status = exit_usage;
        return;
    }
    s.quiet = true;
    s.capture = false;
    s.script_args = args[1..];
    try s.load(args[0]);
    if (s.arena == null) {
        ctx.status = s.status;
        return;
    }
    try s.run();
    ctx.status = s.status;
    if (s.outcome) |o| {
        if (o.stopped) try ctx.out.print("{s}: stopped\n", .{args[0]});
        if (o.code != 0 and s.machine != null) {
            try ctx.out.flush();
            for (s.machine.?.reports.items) |r| {
                if (!r.handled) {
                    const fmt = "{s}:{d}: error {d}: {s}\n{s}{s}";
                    const parts = .{ args[0], r.line, r.code, r.message, r.trace, r.details };
                    // on the full-screen REPL the error goes to the upper part, not under the bars (stderr)
                    if (ctx.tui != null) try ctx.out.print(fmt, parts) else std.debug.print(fmt, parts);
                }
            }
        }
    }
}
