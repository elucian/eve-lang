//! Command line and REPL of the `eve` command (manual/usage.md).
//!
//! Every REPL command is one entry of the jump table `commands`. The same table serves the command
//! line: `eve --check script.eve` runs the `check` entry once and exits, without the REPL.
// Zig tip: `@import` returns a whole file as a struct (a namespace). Nothing is global: a file
// sees only what it imports. `@import("std")` is the standard library; `@import("evecm").version`
// is a file next to this one. `const` binds a name once; `var` would allow reassignment.
// `std.Io` is the input/output part of the library (Zig 0.16): readers, writers, files.
const std = @import("std");
const Io = std.Io;
const version = @import("evecm").version;
// Zig tip: Zig forbids a name that hides another one in an outer scope (shadowing). The file-level
// import is called `editor`, not `line`, because several functions below have a parameter `line`.
const editor = @import("evecm").line;
const parser = @import("evecp").parser;
const ast = @import("evecm").ast;
const doc = @import("evecp").doc;
const screen = @import("evevm").screen;
const tui = @import("evevm").tui;
const helptext = @import("evevm").helptext;

// Zig tip: the parts of the command are files of their own; `cli.zig` imports them and names again what the
// program (eve.zig) uses, so `cli.parseArgs` keeps working. Files of one module may import each other.
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

// Zig tip: the jump table is a plain array. `[_]Command{ ... }` lets the compiler count the
// elements. `.{ .name = "x", ... }` is an anonymous struct literal: the type `Command` is taken
// from the array, so it need not be repeated. `.run = cmdHelp` stores the function itself (a
// function name without `()` is a value); `stub("check")` calls a comptime function that
// returns one. The whole table is a constant, built by the compiler and stored in the program.
/// The jump table. Order is the order of the menu.
pub const commands = [_]Command{
    .{ .name = "check", .summary = "check the syntax of a script, do not execute it", .file = ".eve", .run = cp_cmds.cmdCheck },
    .{ .name = "compile", .summary = "compile a script to bytecode", .file = ".eve", .run = stub("compile") },
    .{ .name = "doc", .summary = "write Markdown documentation of a .eve file or folder", .file = ".eve", .run = cp_cmds.cmdDoc },
    .{ .name = "debug", .summary = "execute the main process in debug mode", .file = ".eve", .run = vm_cmds.cmdDebug },
    .{ .name = "execute", .summary = "execute the main process in production mode", .file = ".eve", .run = vm_cmds.cmdExecute },
    .{ .name = "project", .summary = "project init|new <folder>: make a project with the standard layout", .run = cp_cmds.cmdProject },
    .{ .name = "db", .summary = "db proc list: the database part (eve db ...)", .run = db_cmds.cmdDb },
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
    .{ .name = "setup", .summary = "load the configuration file", .file = ".cfg", .run = stub("setup") },
    .{ .name = "help", .summary = "display this menu", .run = ui_cmds.cmdHelp },
    .{ .name = "shell", .summary = "shell <command> (or !<command>): run a command of the system here; the prompt stays in eve", .run = vm_cmds.cmdShell },
    .{ .name = "quit", .summary = "exit from the REPL", .run = ui_cmds.cmdQuit },
    .{ .name = "exit", .summary = "same as quit", .run = ui_cmds.cmdQuit },
};

// Zig tip: `?*const Command` is "a pointer to a Command, or null". There are no null pointers
// in other types: absence must be written in the type with `?`. `for (&commands) |*c|`
// walks the array by pointer (`&` takes the address, `|*c|` captures each element by
// pointer, so nothing is copied). `std.mem.eql(u8, a, b)` compares two slices of bytes; `==`
// on slices does not compare contents. `return` inside the loop leaves the function.
pub fn find(name: []const u8) ?*const Command {
    for (&commands) |*c| {
        if (std.mem.eql(u8, c.name, name)) return c;
    }
    return null;
}

// Zig tip: memory is never allocated behind your back. A function that needs memory receives
// an `std.mem.Allocator` (`gpa`) from the caller, who decides where it comes from (here an
// arena that frees everything at once at the end of the program). `std.ArrayList(T)` is a
// growable array; `.empty` starts it with nothing and `append(gpa, x)` needs the allocator.
// `bad.* = a` writes through the pointer (`.*` dereferences). `orelse` gives a fallback when an
// optional is null, here by leaving the function with `return error.UnknownOption`.
// `while (cond) : (i += 1)` has a continue-expression that runs after each pass.
// `a[1] == 's'` compares a byte of the string with a character literal.

// Zig tip: `var words: [16][]const u8 = undefined;` is an array of 16 slices whose content is
// not initialised on purpose (`undefined`): it lives on the stack, no allocator needed, and
// only the first `n` are used. `words[1..n]` is a slice of the array from index 1 up to n (n
// excluded), a view without copying. `while (it.next()) |w|` repeats while `next()` returns a
// value (an optional) and ends on null. `std.mem.tokenizeAny` splits on any of the characters
// of the delimiter string and skips empty pieces. `if (opt) |c| {...} else {...}` unwraps an
// optional. Arrays and slices are bounds-checked: a wrong index stops the program in Debug.
/// Run one line typed at the prompt. Blank lines are ignored.
pub fn dispatch(ctx: *Context, line: []const u8) Io.Writer.Error!void {
    var words: [16][]const u8 = undefined;
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
    } else {
        try ctx.out.print("unknown command: {s} (type help or ?)\n", .{words[0]});
    }
}

// Zig tip: the REPL takes any `*Io.Reader`, not the keyboard itself. Real code passes stdin;
// the tests pass a string (`Io.Reader.fixed("quit\n")`). Writing code against an interface
// like this is how Zig programs are made testable. `(try in.takeDelimiter('\n')) orelse break`
// reads up to the newline; the result is null at the end of the input, and `orelse break`
// leaves the loop then. The slice points into the reader's own buffer and is valid only
// until the next read, so `dispatch` uses it at once and does not keep it.
// Zig tip: a function can return an optional slice: `?[]const u8` is a string or null. The line
// editor does not know the commands (line.zig must not import cli.zig, two files that import each
// other are hard to follow), so the REPL hands it this function: "which file extension does Tab
// complete here?". `std.mem.trimEnd` cuts the listed characters from the end of a slice. `orelse`
// gives a default for the null of `indexOfAny`. `return if (cond) a else null` is an `if` expression.
/// The extension Tab completes for the last word of `line`: `.cfg` after `-s`, otherwise what the
/// command takes (`.eve` for check, debug, execute and compile; `.cfg` for setup), else null.
pub fn completionExt(line: []const u8) ?[]const u8 {
    const head = std.mem.trimEnd(u8, line[0..editor.lastWordStart(line)], " \t");
    const c = find(head[0 .. std.mem.indexOfAny(u8, head, " \t") orelse head.len]) orelse return null;
    if (std.mem.eql(u8, head[editor.lastWordStart(head)..], "-s")) return ".cfg";
    if (std.mem.eql(u8, head[editor.lastWordStart(head)..], "-i")) return ".vmc";
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
        // Zig tip: `if (ctx.tui) |t| { ... continue; }` runs the full-screen branch when there is a screen and goes
        // back to the top of the loop; the code after it is the older line-by-line prompt, still used for pipes and
        // for a terminal whose size is unknown. The clock is read before and after the command for the status bar.
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

// Zig tip: `test "name" { }` blocks are compiled only by `zig build test` (./run.sh unit) and
// live next to the code they check. `std.testing.expect(cond)` and `expectEqual(expected,
// actual)` fail the test with an error. `.?` unwraps an optional and stops with an error if it
// is null. `expectEqual(c, find(c.name).?)` compares two pointers: the same table element.
// Zig tip: a test can keep two tables in step: the jump table and the help texts must name the same commands in the
// same order, or `help` would miss one or show one that does not exist. `inline for` is not needed: the arrays are
// walked at run time and `try` fails the test with the position of the first difference.
test "the help texts cover the commands of the jump table, in the same order" {
    try std.testing.expectEqual(commands.len, helptext.entries.len);
    for (&commands, &helptext.entries) |c, e| try std.testing.expectEqualStrings(c.name, e.name);
}

// Zig tip: an arena allocator frees everything at once with `deinit`, which suits a test that parses a few lines and
// looks at the result. `&.{ "a", "b" }` is a slice of texts written in place. The three cases are the ones that were
// confused once: a word after a door belongs to the door, a command word is the command, and `-u` is an option.
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

    const ui = try cmdline.parseArgs(arena.allocator(), &.{ "-ux", "status" }, &bad);
    try std.testing.expect(ui.ui);
    try std.testing.expectEqualStrings("status", ui.command.?.name);

    const only_ui = try cmdline.parseArgs(arena.allocator(), &.{"-ux"}, &bad);
    try std.testing.expect(only_ui.ui and only_ui.command == null);

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

// Zig tip: `var buf: [128]u8 = undefined;` is a byte array on the stack; `Io.Writer.fixed(&buf)`
// makes a writer that writes into it and `w.buffered()` returns what was written, so the test
// reads the output without a terminal. `.fixed(...)` is shorthand for `Io.Writer.fixed(...)`:
// with a declared type on the left, `.name` looks the function up in that type.
// `@as(u8, x)` gives x an explicit type; a builtin like it always starts with `@`.
test "a stub echoes its name" {
    var buf: [128]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var ctx: Context = .{ .out = &w, .io = std.testing.io, .gpa = std.testing.allocator };
    try dispatch(&ctx, "  resume  a.eve ");
    try std.testing.expectEqualStrings("resume command, not yet implemented\n", w.buffered());
    try std.testing.expectEqual(@as(u8, exit_not_implemented), ctx.status);
}

// Zig tip: this test relies on the same features as the test above: see the tip there.
test "doc without a path is a usage error" {
    var buf: [128]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var ctx: Context = .{ .out = &w, .io = std.testing.io, .gpa = std.testing.allocator };
    try dispatch(&ctx, "doc");
    try std.testing.expectEqual(@as(u8, exit_usage), ctx.status);
}

// Zig tip: `defer arena.deinit();` runs at the end of the scope, however it ends: the usual way
// to pair a resource with its release on the next line. The testing allocator reports memory
// that is never freed as a test failure. An ArenaAllocator frees everything in one `deinit`,
// so the parser's `append`s need no individual `free`. `&.{ "-d", "a.eve" }` is an inline
// array of strings, passed as a slice. `expectError(error.X, call)` checks that a call fails.
// Zig tip: `expectEqualStrings` compares two texts and prints both when they differ. The last word of a command line
// is the edge case of a parser that looks ahead: `--serve stop` must not read past the end of `argv`.
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

// Zig tip: a `for` over an array literal checks several inputs with one body. The old two-letter names of the
// machine options (`-lo`, `-r`, `-ls`) and `-lsn` (replaced by `--listen`, D-169) are unknown now, and `bad` names the
// word that was refused.
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
    const o = try cmdline.parseArgs(arena.allocator(), &.{ "-d", "-s", "f.cfg", "--check", "a.eve" }, &bad);
    try std.testing.expect(o.debug);
    try std.testing.expectEqualStrings("f.cfg", o.config.?);
    try std.testing.expectEqualStrings("check", o.command.?.name);
    try std.testing.expectEqual(@as(usize, 1), o.args.len);

    const s = try cmdline.parseArgs(arena.allocator(), &.{"a.eve"}, &bad);
    try std.testing.expectEqualStrings("execute", s.command.?.name);

    const x = try cmdline.parseArgs(arena.allocator(), &.{ "-x", "-i", "cmds.txt", "a.eve" }, &bad);
    try std.testing.expect(x.execute);
    try std.testing.expectEqualStrings("execute", x.command.?.name);
    try std.testing.expectEqualStrings("cmds.txt", x.slot.?);

    try std.testing.expectError(error.UnknownOption, cmdline.parseArgs(arena.allocator(), &.{"--bogus"}, &bad));
    try std.testing.expectEqualStrings("--bogus", bad);
    try std.testing.expectError(error.MissingValue, cmdline.parseArgs(arena.allocator(), &.{"-s"}, &bad));
}

test "completion extension follows the command and -s" {
    try std.testing.expectEqualStrings(".eve", completionExt("check te").?);
    try std.testing.expectEqualStrings(".eve", completionExt("compile ").?);
    try std.testing.expectEqualStrings(".cfg", completionExt("setup c").?);
    try std.testing.expectEqualStrings(".cfg", completionExt("debug a.eve -s c").?);
    try std.testing.expect(completionExt("print x") == null);
    try std.testing.expect(completionExt("che") == null);
}

// Zig tip: `inline for` is unrolled by the compiler: the body is compiled once per element,
// so `word` is a compile-time known string and `"..." ++ word ++ "..."` (compile-time
// concatenation) is allowed. A plain `for` could not do that.
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
