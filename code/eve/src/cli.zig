//! Command line and REPL of the `eve` command (manual/usage.md).
//!
//! Every REPL command is one entry of the jump table `commands`. The same table serves the command
//! line: `eve --check script.eve` runs the `check` entry once and exits, without the REPL.
const std = @import("std");
const Io = std.Io;
const version = @import("evecm").version;
const editor = @import("evecm").line;
const parser = @import("evecp").parser;
const ast = @import("evecm").ast;
const doc = @import("evecp").doc;
const screen = @import("evevm").screen;
const tui = @import("evevm").tui;
const helptext = @import("evevm").helptext;

const context = @import("context.zig");
const ui_cmds = @import("ui_cmds.zig");
const cp_cmds = @import("cp_cmds.zig");
const db_cmds = @import("db_cmds.zig");
const vm_cmds = @import("vm_cmds.zig");
const help_pages = @import("help.zig");
const cmdline = @import("options.zig");
pub const Context = context.Context;
pub const Handler = context.Handler;
pub const Command = context.Command;
pub const exit_usage = context.exit_usage;
pub const exit_syntax = context.exit_syntax;
pub const exit_not_implemented = context.exit_not_implemented;
pub const exit_no_input = context.exit_no_input;
pub const exit_cant_create = context.exit_cant_create;
pub const prompt = context.prompt;
pub const stub = context.stub;
pub const parseArgs = cmdline.parseArgs;
pub const Options = cmdline.Options;
pub const writeHelp = help_pages.writeHelp;

/// The jump table. Order is the order of the menu.
pub const commands = [_]Command{
    .{ .name = "check", .summary = "check the syntax of a script, do not execute it", .file = ".eve", .run = cp_cmds.cmdCheck },
    .{ .name = "compile", .summary = "compile a script to bytecode (the .evb file comes in stage B5.7)", .file = ".eve", .run = stub("compile") },
    .{ .name = "disasm", .summary = "the bytecode of a script as a listing", .file = ".eve", .run = cp_cmds.cmdDisasm },
    .{ .name = "doc", .summary = "write Markdown documentation of a .eve file or folder", .file = ".eve", .run = cp_cmds.cmdDoc },
    .{ .name = "debug", .summary = "execute the main process in debug mode", .file = ".eve", .run = vm_cmds.cmdDebug },
    .{ .name = "execute", .summary = "execute the main process in production mode", .file = ".eve", .run = vm_cmds.cmdExecute },
    .{ .name = "outline", .summary = "the aspects, classes and subprograms of a script, nested", .file = ".eve", .run = cp_cmds.cmdOutline },
    .{ .name = "symbols", .summary = "the symbols of a script as a flat list", .file = ".eve", .run = cp_cmds.cmdSymbols },
    .{ .name = "project", .summary = "project init|new <folder>: make a project with the standard layout", .run = cp_cmds.cmdProject },
    .{ .name = "db", .summary = "database: sql, views and tables, proc list", .run = db_cmds.cmdDb },
    .{ .name = "begin", .summary = "start the step by step execution", .run = stub("begin") },
    .{ .name = "enter", .summary = "execute the next step", .run = stub("enter") },
    .{ .name = "run", .summary = "execute the loaded script, or the file given (parsed first)", .file = ".eve", .run = vm_cmds.viaSession("run") },
    .{ .name = "load", .summary = "load a script, forget the previous one", .file = ".eve", .run = vm_cmds.viaSession("load") },
    .{ .name = "parse", .summary = "parse the loaded script, report syntax errors", .file = ".eve", .run = vm_cmds.viaSession("parse") },
    .{ .name = "ast", .summary = "write the syntax tree to <outdir>/<name>.ast", .run = vm_cmds.viaSession("ast") },
    .{ .name = "inspect", .summary = "write the introspection report <outdir>/<name>.inspect", .run = vm_cmds.viaSession("inspect") },
    .{ .name = "errors", .summary = "report the errors of the script (<outdir>/<name>.err)", .run = vm_cmds.viaSession("errors") },
    .{ .name = "status", .summary = "the state of the machine: script, configuration, doors, what it is doing", .run = vm_cmds.cmdStatus },
    .{ .name = "listen", .summary = "listen [start|stop|restart|status]: the IPC vm_cmds.door, the prompt stays", .run = vm_cmds.door(true) },
    .{ .name = "serve", .summary = "serve [start|stop|restart|status]: the HTTP vm_cmds.door, the prompt stays", .run = vm_cmds.door(false) },
    .{ .name = "outdir", .summary = "set the folder of the report files", .run = vm_cmds.viaSession("outdir") },
    .{ .name = "capture", .summary = "capture on|off: keep the script output in <outdir>/<name>.out", .run = vm_cmds.viaSession("capture") },
    .{ .name = "log", .summary = "add a line of text to summary.log", .run = vm_cmds.viaSession("log") },
    .{ .name = "print", .summary = "display the value of a global variable", .run = stub("print") },
    .{ .name = "resume", .summary = "run until the next halt statement", .run = stub("resume") },
    .{ .name = "report", .summary = "report the system state", .run = vm_cmds.viaSession("report") },
    .{ .name = "stop", .summary = "stop the doors (ipc and http) and the scripts; the prompt stays", .run = vm_cmds.cmdStop },
    .{ .name = "clear", .summary = "clear the upper part of the screen (the output); the command line stays", .run = ui_cmds.cmdClear },
    .{ .name = "setup", .summary = "load the configuration file", .file = ".cfg", .run = vm_cmds.cmdSetup },
    .{ .name = "help", .summary = "display this menu", .run = ui_cmds.cmdHelp },
    .{ .name = "shell", .summary = "shell <command> (or !<command>): run a command of the system here; the prompt stays in eve", .run = vm_cmds.cmdShell },
    .{ .name = "quit", .summary = "exit from the REPL", .run = ui_cmds.cmdQuit },
    .{ .name = "exit", .summary = "same as quit", .run = ui_cmds.cmdQuit },
};

pub fn find(name: []const u8) ?*const Command {
    for (&commands) |*c| {
        if (std.mem.eql(u8, c.name, name)) return c;
    }
    return null;
}

/// Run one line typed at the prompt. Blank lines are ignored.
pub fn dispatch(ctx: *Context, line: []const u8) Io.Writer.Error!void {
    var words: [256][]const u8 = undefined;
    var n: usize = 0;
    var it = std.mem.tokenizeAny(u8, line, " \t\r");
    while (it.next()) |w| {
        if (n == words.len) break;
        words[n] = w;
        n += 1;
    }
    if (n == 0) return;
    // `!<command>` and `shell <command>` give the rest of the line to the system shell as it was typed (quotes, pipes)
    const raw = std.mem.trimStart(u8, line, " \t");
    if (raw[0] == '!') return vm_cmds.shellLine(ctx, raw[1..]);
    if (std.mem.eql(u8, words[0], "shell")) return vm_cmds.shellLine(ctx, raw["shell".len..]);
    // `?` is `help`, `? <command>` is `help <command>`, and `<command> ?` is the page of that command
    if (std.mem.eql(u8, words[0], "?")) return ui_cmds.cmdHelp(ctx, words[1..n]);
    if (n >= 2 and std.mem.eql(u8, words[n - 1], "?") and find(words[0]) != null) return ui_cmds.cmdHelp(ctx, words[0..1]);
    if (find(words[0])) |c| {
        try c.run(ctx, words[1..n]);
    } else if (std.mem.eql(u8, words[0], "cd")) {
        // `cd` and the commands of the shell (md, dir, ls, rm ...) work at the prompt as they do in a shell
        try vm_cmds.cdLine(ctx, raw["cd".len..]);
    } else if (@import("evevm").channel.shellLine(ctx.gpa, raw)) |sh| {
        defer ctx.gpa.free(sh);
        try vm_cmds.shellLine(ctx, sh);
    } else {
        try ctx.out.print("unknown command: {s} (type help or ?)\n", .{words[0]});
    }
}

/// The extension Tab completes for the last word of `line`: `.cfg` after `-e` or `-s`, otherwise what the
/// command takes (`.eve` for check, debug, execute and compile; `.cfg` for setup), else null.
pub fn completionExt(line: []const u8) ?[]const u8 {
    const head = std.mem.trimEnd(u8, line[0..editor.lastWordStart(line)], " \t");
    const c = find(head[0 .. std.mem.indexOfAny(u8, head, " \t") orelse head.len]) orelse return null;
    const last = head[editor.lastWordStart(head)..];
    if (std.mem.eql(u8, last, "-e") or std.mem.eql(u8, last, "--setup") or std.mem.eql(u8, last, "-s")) return ".cfg";
    return if (c.file.len > 0) c.file else null;
}

/// What the line editor needs: the `Io` for reading folders and an allocator for the candidates.
pub const Edit = struct {
    io: Io,
    gpa: std.mem.Allocator,
};

/// The read, execute, print, loop. Ends on `quit`, `exit` or end of input. With `edit` the line
/// is read key by key (Tab completes file names, the terminal must be in raw mode); without it
/// the line is read as a whole, for pipes and tests.
pub fn repl(ctx: *Context, in: *Io.Reader, edit: ?Edit) !void {
    var comp: ?editor.Completer = if (edit) |e| editor.Completer.init(e.gpa) else null;
    defer if (comp) |*c| c.deinit();
    var buf: [editor.max_line]u8 = undefined;
    if (ctx.tui) |t| {
        t.eve_width = ctx.width;
        t.renderer = ui_cmds.renderBlock;
    }
    while (!ctx.quit) {
        if (ctx.tui) |t| {
            const text = (try t.readLine(in, &comp.?, &buf, completionExt)) orelse break;
            var words = std.mem.tokenizeAny(u8, text, " \t");
            const word = words.next() orelse continue;
            const started = Io.Timestamp.now(ctx.io, .awake).toMilliseconds();
            t.setRunning(if (std.mem.eql(u8, word, "?")) "help" else word);
            try dispatch(ctx, text);
            try ctx.out.flush();
            if (!ctx.quit) t.setReady(Io.Timestamp.now(ctx.io, .awake).toMilliseconds() - started);
            continue;
        }
        try ctx.out.writeAll(prompt);
        try ctx.out.flush();
        const text = if (edit) |e|
            (try editor.readLine(e.io, in, ctx.out, prompt, &comp.?, &buf, completionExt)) orelse break
        else
            (try in.takeDelimiter('\n')) orelse break;
        try dispatch(ctx, text);
    }
    try ctx.out.flush();
}

test "the help texts cover the commands of the jump table, in the same order" {
    try std.testing.expectEqual(commands.len, helptext.entries.len);
    for (&commands, &helptext.entries) |c, e| try std.testing.expectEqualStrings(c.name, e.name);
}

test "a command word is the command, a vm_cmds.door word stays with its vm_cmds.door, -u is an option" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var bad: []const u8 = "";

    const served = try cmdline.parseArgs(arena.allocator(), &.{ "--serve", "status" }, &bad);
    try std.testing.expect(served.command == null and served.machine.serve);
    try std.testing.expectEqualStrings("status", served.machine.word);

    const check = try cmdline.parseArgs(arena.allocator(), &.{ "check", "a.eve" }, &bad);
    try std.testing.expectEqualStrings("check", check.command.?.name);
    try std.testing.expectEqualStrings("a.eve", check.args[0]);

    const stop = try cmdline.parseArgs(arena.allocator(), &.{"stop"}, &bad);
    try std.testing.expectEqualStrings("stop", stop.command.?.name);

    // `-ux` and the word `ux` start the native workbench with the rest of the line (D-193); `ux start|stop|restart|status` is the web door
    const ux = try cmdline.parseArgs(arena.allocator(), &.{ "-ux", "test/project" }, &bad);
    try std.testing.expect(ux.ux and ux.command == null);
    try std.testing.expectEqualStrings("test/project", ux.ux_args[0]);
    const ux_word = try cmdline.parseArgs(arena.allocator(), &.{"ux"}, &bad);
    try std.testing.expect(ux_word.ux and ux_word.ux_args.len == 0);
    const ux_door = try cmdline.parseArgs(arena.allocator(), &.{ "ux", "start" }, &bad);
    try std.testing.expect(!ux_door.ux and ux_door.machine.serve);

    // `-tx` and the word `tx` start the terminal IDE with the rest of the line (D-172)
    const tx = try cmdline.parseArgs(arena.allocator(), &.{ "-tx", "test/project" }, &bad);
    try std.testing.expect(tx.tx and tx.command == null);
    try std.testing.expectEqualStrings("test/project", tx.tx_args[0]);
    const tx_word = try cmdline.parseArgs(arena.allocator(), &.{"tx"}, &bad);
    try std.testing.expect(tx_word.tx and tx_word.tx_args.len == 0);
    try std.testing.expectError(error.UnknownOption, cmdline.parseArgs(arena.allocator(), &.{"-u"}, &bad));

    const script = try cmdline.parseArgs(arena.allocator(), &.{"status.eve"}, &bad);
    try std.testing.expectEqualStrings("execute", script.command.?.name);

    const listen = try cmdline.parseArgs(arena.allocator(), &.{ "listen", "status" }, &bad);
    try std.testing.expect(listen.machine.listen and listen.command == null);
    try std.testing.expectEqualStrings("status", listen.machine.word);
}

test "every command is found by name" {
    for (&commands) |*c| try std.testing.expectEqual(c, find(c.name).?);
    try std.testing.expect(find("nope") == null);
}

test "a stub echoes its name" {
    var buf: [128]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var ctx: Context = .{ .out = &w, .io = std.testing.io, .gpa = std.testing.allocator };
    try dispatch(&ctx, "  resume  a.eve ");
    try std.testing.expectEqualStrings("resume command, not yet implemented\n", w.buffered());
    try std.testing.expectEqual(@as(u8, exit_not_implemented), ctx.status);
}

test "doc without a path is a usage error" {
    var buf: [128]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var ctx: Context = .{ .out = &w, .io = std.testing.io, .gpa = std.testing.allocator };
    try dispatch(&ctx, "doc");
    try std.testing.expectEqual(@as(u8, exit_usage), ctx.status);
}

test "options of the machine: --listen, --serve, -loc, -rem" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var bad: []const u8 = "";
    for ([_][]const u8{ "start", "stop", "restart", "status" }) |w| {
        const o = try cmdline.parseArgs(arena.allocator(), &.{ "--serve", w }, &bad);
        try std.testing.expect(o.machine.serve);
        try std.testing.expectEqualStrings(w, o.machine.word);
        const l = try cmdline.parseArgs(arena.allocator(), &.{ "--listen", w }, &bad);
        try std.testing.expect(l.machine.listen and !l.machine.serve);
        try std.testing.expectEqualStrings(w, l.machine.word);
    }
    try std.testing.expectError(error.BadWord, cmdline.parseArgs(arena.allocator(), &.{ "--listen", "nope" }, &bad));
    try std.testing.expectEqualStrings("nope", bad);
    const both = try cmdline.parseArgs(arena.allocator(), &.{ "--listen", "--serve" }, &bad);
    try std.testing.expect(both.machine.listen and both.machine.serve);
    try std.testing.expectEqualStrings("", both.machine.word);
    const remote = try cmdline.parseArgs(arena.allocator(), &.{ "-rem", "localhost:8095", "-x", "a.eve", "x" }, &bad);
    try std.testing.expectEqualStrings("localhost:8095", remote.machine.remote_addr.?);
    try std.testing.expectEqualStrings("a.eve", remote.machine.script.?);
    try std.testing.expectEqual(@as(usize, 1), remote.machine.script_args.len);
    const local = try cmdline.parseArgs(arena.allocator(), &.{ "-loc", "-x", "a.eve" }, &bad);
    try std.testing.expect(local.machine.local and local.machine.local_port == null);
    const long = try cmdline.parseArgs(arena.allocator(), &.{ "--local", "4043", "--remote", "--listen" }, &bad);
    try std.testing.expect(long.machine.local and long.machine.remote and long.machine.listen);
    try std.testing.expectEqualStrings("4043", long.machine.local_port.?);
}

// @decision D-169
test "-x alone touches no machine; the old names are refused" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var bad: []const u8 = "";
    const x = try cmdline.parseArgs(arena.allocator(), &.{ "-x", "a.eve" }, &bad);
    const m = x.machine;
    try std.testing.expect(!(m.listen or m.serve or m.local or m.remote));
    for ([_][]const u8{ "-lo", "-r", "-ls", "-lsn" }) |old| {
        try std.testing.expectError(error.UnknownOption, cmdline.parseArgs(arena.allocator(), &.{ old, "-x", "a.eve" }, &bad));
        try std.testing.expectEqualStrings(old, bad);
    }
}

test "options: flags, command and script" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var bad: []const u8 = "";
    const o = try cmdline.parseArgs(arena.allocator(), &.{ "-d", "-e", "f.cfg", "--check", "a.eve" }, &bad);
    try std.testing.expect(o.debug);
    try std.testing.expectEqualStrings("f.cfg", o.config.?);
    try std.testing.expectEqualStrings("check", o.command.?.name);
    try std.testing.expectEqual(@as(usize, 1), o.args.len);

    const s = try cmdline.parseArgs(arena.allocator(), &.{"a.eve"}, &bad);
    try std.testing.expectEqualStrings("execute", s.command.?.name);

    const x = try cmdline.parseArgs(arena.allocator(), &.{ "-x", "--setup", "m.cfg", "a.eve" }, &bad);
    try std.testing.expect(x.execute);
    try std.testing.expectEqualStrings("execute", x.command.?.name);
    try std.testing.expectEqualStrings("m.cfg", x.config.?);
    // the command files are gone (D-188): `-i` and `-t` are unknown options
    try std.testing.expectError(error.UnknownOption, cmdline.parseArgs(arena.allocator(), &.{ "-x", "-i", "cmds.vmc" }, &bad));
    try std.testing.expectError(error.UnknownOption, cmdline.parseArgs(arena.allocator(), &.{ "-t", "30" }, &bad));

    try std.testing.expectError(error.UnknownOption, cmdline.parseArgs(arena.allocator(), &.{"--bogus"}, &bad));
    try std.testing.expectEqualStrings("--bogus", bad);
    try std.testing.expectError(error.MissingValue, cmdline.parseArgs(arena.allocator(), &.{"-m"}, &bad));
}

// @decision D-188
test "options: -s is the service, -e the configuration file" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var bad: []const u8 = "";
    const bare = try cmdline.parseArgs(arena.allocator(), &.{"-s"}, &bad);
    try std.testing.expect(bare.service and bare.config == null);
    const with_file = try cmdline.parseArgs(arena.allocator(), &.{ "-s", "m.cfg" }, &bad);
    try std.testing.expect(with_file.service);
    try std.testing.expectEqualStrings("m.cfg", with_file.config.?);
    const script = try cmdline.parseArgs(arena.allocator(), &.{ "-e", "m.cfg", "a.eve" }, &bad);
    try std.testing.expect(!script.service);
    try std.testing.expectEqualStrings("m.cfg", script.config.?);
    const command = try cmdline.parseArgs(arena.allocator(), &.{ "--setup", "m.cfg", "--check", "a.eve" }, &bad);
    try std.testing.expect(!command.service);
    const door = try cmdline.parseArgs(arena.allocator(), &.{ "--listen", "-e", "m.cfg" }, &bad);
    try std.testing.expect(!door.service and door.machine.listen);
    const stop = try cmdline.parseArgs(arena.allocator(), &.{ "--serve", "stop", "-e", "m.cfg" }, &bad);
    try std.testing.expect(!stop.service);
    const db = try cmdline.parseArgs(arena.allocator(), &.{ "-s", "-db", "--serve", "evedb.cfg" }, &bad);
    try std.testing.expect(db.service);
    try std.testing.expectError(error.ServiceAlone, cmdline.parseArgs(arena.allocator(), &.{ "-s", "m.cfg", "a.eve" }, &bad));
    try std.testing.expectError(error.ServiceAlone, cmdline.parseArgs(arena.allocator(), &.{ "--listen", "-s" }, &bad));
    try std.testing.expectError(error.MissingValue, cmdline.parseArgs(arena.allocator(), &.{"-e"}, &bad));
}

test "completion extension follows the command and -e" {
    try std.testing.expectEqualStrings(".eve", completionExt("check te").?);
    try std.testing.expectEqualStrings(".eve", completionExt("compile ").?);
    try std.testing.expectEqualStrings(".cfg", completionExt("setup c").?);
    try std.testing.expectEqualStrings(".cfg", completionExt("debug a.eve -e c").?);
    try std.testing.expect(completionExt("print x") == null);
    try std.testing.expect(completionExt("che") == null);
}

test "repl ends on quit and on exit" {
    inline for (.{ "quit", "exit" }) |word| {
        var buf: [256]u8 = undefined;
        var w: Io.Writer = .fixed(&buf);
        var ctx: Context = .{ .out = &w, .io = std.testing.io, .gpa = std.testing.allocator };
        var in: Io.Reader = .fixed("\nresume\n" ++ word ++ "\nprint x\n");
        try repl(&ctx, &in, null);
        try std.testing.expect(ctx.quit);
        try std.testing.expectEqualStrings(
            prompt ++ prompt ++ "resume command, not yet implemented\n" ++ prompt,
            w.buffered(),
        );
    }
}

test "repl ends at end of input and reports unknown commands" {
    var buf: [256]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var ctx: Context = .{ .out = &w, .io = std.testing.io, .gpa = std.testing.allocator };
    var in: Io.Reader = .fixed("frob\n");
    try repl(&ctx, &in, null);
    try std.testing.expect(!ctx.quit);
    try std.testing.expect(std.mem.indexOf(u8, w.buffered(), "unknown command: frob") != null);
}
