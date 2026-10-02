//! Command line and REPL of the `eve` command (manual/usage.md).
//!
//! Every REPL command is one entry of the jump table `commands`. The same table serves the command
//! line: `eve --check script.eve` runs the `check` entry once and exits, without the REPL.
// Zig tip: `@import` returns a whole file as a struct (a namespace). Nothing is global: a file
// sees only what it imports. `@import("std")` is the standard library; `@import("version.zig")`
// is a file next to this one. `const` binds a name once; `var` would allow reassignment.
// `std.Io` is the input/output part of the library (Zig 0.16): readers, writers, files.
const std = @import("std");
const Io = std.Io;
const version = @import("version.zig");
// Zig tip: Zig forbids a name that hides another one in an outer scope (shadowing). The file-level
// import is called `editor`, not `line`, because several functions below have a parameter `line`.
const editor = @import("line.zig");

// Zig tip: `pub` makes a declaration visible to other files (main.zig uses `cli.exit_usage`).
// Without it the name is private to this file. A `const` number without a type is a
// `comptime_int`: it has no size until it is used (here as the `u8` exit status).
// `///` documents the next declaration, `//!` documents the file; tools show both.
/// Exit status: bad command line (EX_USAGE).
pub const exit_usage = 64;
/// Exit status: the script has syntax errors (EX_DATAERR), reported by `check`.
pub const exit_syntax = 65;
/// Exit status: not implemented, outside the Eve range (EX_SOFTWARE).
pub const exit_not_implemented = 70;

// Zig tip: a string literal is a pointer to a constant array of bytes; there is no string type.
// Text is `[]const u8`: a slice (pointer + length) of read-only bytes, in UTF-8.
pub const prompt = "eve:> ";

// Zig tip: a `struct` is a record. Fields can have default values (`= false`), so
// `.{ .out = w }` builds a Context and fills the rest. Types are written after the name:
//   `*Io.Writer`    pointer to one Writer (the struct does not own it, it only borrows it)
//   `?[]const u8`   optional: either a string or `null` (no -c option given)
//   `u8`            unsigned 8-bit integer, 0 to 255, exactly what a process exit code is
/// State shared by the command handlers.
pub const Context = struct {
    out: *Io.Writer,
    /// `-d`: `halt` statements stop the script; otherwise they are ignored.
    debug: bool = false,
    /// `-c file.cfg`
    config: ?[]const u8 = null,
    /// `-m size`
    memory: ?[]const u8 = null,
    /// Set by `quit` and `exit`: the REPL ends.
    quit: bool = false,
    /// Exit status of the last command.
    status: u8 = 0,
};

// Zig tip: types are ordinary values, so `const Handler = ...` names a type. This one is a
// pointer to a function (`*const fn`): the jump table stores handlers in it and calls them.
// `Io.Writer.Error!void` is an error union: the function returns either `void` (nothing) or
// one of the errors of Io.Writer. The caller must handle it: `try` (pass it up) or `catch`.
// `[]const []const u8` is a slice of strings: the words after the command name.
pub const Handler = *const fn (ctx: *Context, args: []const []const u8) Io.Writer.Error!void;

pub const Command = struct {
    name: []const u8,
    summary: []const u8,
    run: Handler,
};

// Zig tip: `comptime` parameters are known while compiling. `stub("check")` is evaluated by the
// compiler, which generates a separate small function for each name. A function cannot capture
// local variables, so the trick is to return a function declared inside an anonymous struct,
// whose `name` is a constant the compiler fills in. `_` as a parameter name means "unused":
// Zig reports unused parameters and variables as errors. `try x` means: if `x` is an error,
// return it from this function at once; otherwise use the value. `.{name}` is a tuple of the
// values for the `{s}` placeholder (`s` = string) of `print`.
/// A branch that is not written yet: it echoes its name.
fn stub(comptime name: []const u8) Handler {
    return struct {
        fn run(ctx: *Context, _: []const []const u8) Io.Writer.Error!void {
            try ctx.out.print("{s} echo, not yet implemented\n", .{name});
            ctx.status = exit_not_implemented;
        }
    }.run;
}

// Zig tip: `ctx` is a pointer, so `ctx.quit = true` changes the caller's Context. Zig has no
// hidden copies: a struct passed by value is copied, a pointer lets the callee modify it.
// Fields are reached with `.` for both a struct and a pointer to it.
fn cmdQuit(ctx: *Context, _: []const []const u8) Io.Writer.Error!void {
    ctx.quit = true;
}

fn cmdHelp(ctx: *Context, _: []const []const u8) Io.Writer.Error!void {
    try writeMenu(ctx.out);
}

// Zig tip: the jump table is a plain array. `[_]Command{ ... }` lets the compiler count the
// elements. `.{ .name = "x", ... }` is an anonymous struct literal: the type `Command` is taken
// from the array, so it need not be repeated. `.run = cmdHelp` stores the function itself (a
// function name without `()` is a value); `stub("check")` calls a comptime function that
// returns one. The whole table is a constant, built by the compiler and stored in the program.
/// The jump table. Order is the order of the menu.
pub const commands = [_]Command{
    .{ .name = "check", .summary = "check the syntax of a script, do not execute it", .run = stub("check") },
    .{ .name = "debug", .summary = "execute the main process in debug mode", .run = stub("debug") },
    .{ .name = "execute", .summary = "execute the main process in production mode", .run = stub("execute") },
    .{ .name = "begin", .summary = "start the step by step execution", .run = stub("begin") },
    .{ .name = "enter", .summary = "execute the next step", .run = stub("enter") },
    .{ .name = "print", .summary = "display the value of a global variable", .run = stub("print") },
    .{ .name = "resume", .summary = "run until the next halt statement", .run = stub("resume") },
    .{ .name = "report", .summary = "report the system state", .run = stub("report") },
    .{ .name = "stop", .summary = "stop the driver, keep the memory", .run = stub("stop") },
    .{ .name = "clear", .summary = "stop the driver and clean the memory", .run = stub("clear") },
    .{ .name = "setup", .summary = "load the configuration file", .run = stub("setup") },
    .{ .name = "help", .summary = "display this menu", .run = cmdHelp },
    .{ .name = "quit", .summary = "exit from the REPL", .run = cmdQuit },
    .{ .name = "exit", .summary = "same as quit", .run = cmdQuit },
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

// Zig tip: lines that start with `\\` form a multi-line string literal. There are no escapes
// inside; each line ends with a newline and the text starts right after the `\\`. The last
// line `\\` followed by nothing adds an empty line.
pub const quick_help =
    \\Usage: eve [options]                      start the REPL
    \\       eve [options] <script.eve> [args]  execute a script (same as --execute)
    \\       eve [options] --<command> [args]   run one command and exit, no REPL
    \\
    \\Quick help:
    \\  -c <file.cfg>   configuration file
    \\  -m <size>       memory for the process
    \\  -d              debug mode: halt statements stop the script (ignored otherwise)
    \\  -v, --version   display the version and exit
    \\  -h, --help      display this help and exit
    \\
;

pub const more_prompt = "-- press enter for more --";

const commands_head =
    \\Commands (REPL, or --<command> on the command line):
    \\
    \\
;

// Zig tip: `w.print("{s}\n\n", .{version.title})` formats like printf, checked by the compiler:
// the number and types of the values must match the placeholders. `{s}` is a string, `{d}` a
// number. `{s: <9}` (see below) pads a string with spaces on the right to 9 characters.
// `version.title` is built with `++` at compile time (see version.zig).
/// Page 1 of the help: the title and the short options.
pub fn writeQuickHelp(w: *Io.Writer) Io.Writer.Error!void {
    try w.print("{s}\n\n", .{version.title});
    try w.writeAll(quick_help);
}

// Zig tip: `for (&commands) |c|` here captures each element by value (a copy); the one-line
// body after `)` needs no braces. `'\n'` in single quotes is one byte (a `u8`), not a string.
/// Page 2 of the help: the same title and the `--<command>` list.
pub fn writeCommandsHelp(w: *Io.Writer) Io.Writer.Error!void {
    try w.print("{s}\n\n", .{version.title});
    try w.writeAll(commands_head);
    for (&commands) |c| try w.print("  --{s: <9}{s}\n", .{ c.name, c.summary });
}

/// Both pages in a row (the REPL `help` command).
pub fn writeMenu(w: *Io.Writer) Io.Writer.Error!void {
    try writeQuickHelp(w);
    try w.writeByte('\n');
    try writeCommandsHelp(w);
}

// Zig tip: `!void` without an error set means "any error": the compiler works out which ones
// from the body. `in: ?*Io.Reader` is an optional pointer; `if (in) |r| { ... }` runs the block
// only when it is not null, and `r` is the unwrapped pointer. `_ = expr;` explicitly throws a
// result away (Zig refuses to ignore values silently). `w.flush()` matters: a Writer keeps
// text in a buffer and sends it to the screen only on flush, so flush before waiting for input.
/// The paged help of `eve -h`: the quick page, then, after Enter, the commands page. Without `in`
/// (output is not a terminal) both pages are written without waiting.
pub fn writeHelp(w: *Io.Writer, in: ?*Io.Reader) !void {
    try writeQuickHelp(w);
    try w.writeByte('\n');
    if (in) |r| {
        try w.writeAll(more_prompt);
        try w.flush();
        _ = try r.takeDelimiter('\n');
        try w.writeByte('\n');
    }
    try writeCommandsHelp(w);
}

// Zig tip: a struct can group the result of parsing. Every field has a default, so
// `var o: Options = .{};` is the all-defaults value. `&.{}` is an empty slice literal, the
// default of `args`.
pub const Options = struct {
    help: bool = false,
    version: bool = false,
    debug: bool = false,
    config: ?[]const u8 = null,
    memory: ?[]const u8 = null,
    /// Command chosen with `--<command>` or implied by a script path.
    command: ?*const Command = null,
    /// Positional arguments after the command.
    args: []const []const u8 = &.{},
};

// Zig tip: `error{ A, B }` is a set of error names. Errors are values, not exceptions: a
// function that can fail says so in its return type (`ParseError!Options`) and the caller must
// deal with it. Errors cannot carry data, so the bad argument is returned through the pointer
// parameter `bad` of parseArgs.
pub const ParseError = error{ MissingValue, UnknownOption, OutOfMemory };

// Zig tip: memory is never allocated behind your back. A function that needs memory receives
// an `std.mem.Allocator` (`gpa`) from the caller, who decides where it comes from (here an
// arena that frees everything at once at the end of the program). `std.ArrayList(T)` is a
// growable array; `.empty` starts it with nothing and `append(gpa, x)` needs the allocator.
// `bad.* = a` writes through the pointer (`.*` dereferences). `orelse` gives a fallback when an
// optional is null, here by leaving the function with `return error.UnknownOption`.
// `while (cond) : (i += 1)` has a continue-expression that runs after each pass.
// `a[1] == 'c'` compares a byte of the string with a character literal.

/// Parse the command line (without the program name). On error `bad` names the argument.
pub fn parseArgs(
    gpa: std.mem.Allocator,
    argv: []const []const u8,
    bad: *[]const u8,
) ParseError!Options {
    var o: Options = .{};
    var rest: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (i < argv.len) : (i += 1) {
        const a = argv[i];
        if (std.mem.eql(u8, a, "-h") or std.mem.eql(u8, a, "--help")) {
            o.help = true;
        } else if (std.mem.eql(u8, a, "-v") or std.mem.eql(u8, a, "--version")) {
            o.version = true;
        } else if (std.mem.eql(u8, a, "-d")) {
            o.debug = true;
        } else if (std.mem.eql(u8, a, "-c") or std.mem.eql(u8, a, "-m")) {
            i += 1;
            if (i >= argv.len) {
                bad.* = a;
                return error.MissingValue;
            }
            if (a[1] == 'c') o.config = argv[i] else o.memory = argv[i];
        } else if (std.mem.startsWith(u8, a, "--") and a.len > 2) {
            const c = find(a[2..]) orelse {
                bad.* = a;
                return error.UnknownOption;
            };
            if (o.command == null) o.command = c else try rest.append(gpa, a);
        } else if (a.len > 1 and a[0] == '-') {
            bad.* = a;
            return error.UnknownOption;
        } else {
            if (o.command == null) o.command = find("execute");
            try rest.append(gpa, a);
        }
    }
    o.args = try rest.toOwnedSlice(gpa);
    return o;
}

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
    if (find(words[0])) |c| {
        try c.run(ctx, words[1..n]);
    } else {
        try ctx.out.print("unknown command: {s} (type help)\n", .{words[0]});
    }
}

// Zig tip: the REPL takes any `*Io.Reader`, not the keyboard itself. Real code passes stdin;
// the tests pass a string (`Io.Reader.fixed("quit\n")`). Writing code against an interface
// like this is how Zig programs are made testable. `(try in.takeDelimiter('\n')) orelse break`
// reads up to the newline; the result is null at the end of the input, and `orelse break`
// leaves the loop then. The slice points into the reader's own buffer and is valid only
// until the next read, so `dispatch` uses it at once and does not keep it.
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
    while (!ctx.quit) {
        try ctx.out.writeAll(prompt);
        try ctx.out.flush();
        const text = if (edit) |e|
            (try editor.readLine(e.io, in, ctx.out, prompt, &comp.?, &buf)) orelse break
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
    var ctx: Context = .{ .out = &w };
    try dispatch(&ctx, "  check  a.eve ");
    try std.testing.expectEqualStrings("check command, not yet implemented\n", w.buffered());
    try std.testing.expectEqual(@as(u8, exit_not_implemented), ctx.status);
}

// Zig tip: `defer arena.deinit();` runs at the end of the scope, however it ends: the usual way
// to pair a resource with its release on the next line. The testing allocator reports memory
// that is never freed as a test failure. An ArenaAllocator frees everything in one `deinit`,
// so the parser's `append`s need no individual `free`. `&.{ "-d", "a.eve" }` is an inline
// array of strings, passed as a slice. `expectError(error.X, call)` checks that a call fails.
test "options: flags, command and script" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var bad: []const u8 = "";
    const o = try parseArgs(arena.allocator(), &.{ "-d", "-c", "f.cfg", "--check", "a.eve" }, &bad);
    try std.testing.expect(o.debug);
    try std.testing.expectEqualStrings("f.cfg", o.config.?);
    try std.testing.expectEqualStrings("check", o.command.?.name);
    try std.testing.expectEqual(@as(usize, 1), o.args.len);

    const s = try parseArgs(arena.allocator(), &.{"a.eve"}, &bad);
    try std.testing.expectEqualStrings("execute", s.command.?.name);

    try std.testing.expectError(error.UnknownOption, parseArgs(arena.allocator(), &.{"--bogus"}, &bad));
    try std.testing.expectEqualStrings("--bogus", bad);
    try std.testing.expectError(error.MissingValue, parseArgs(arena.allocator(), &.{"-c"}, &bad));
}

// Zig tip: `inline for` is unrolled by the compiler: the body is compiled once per element,
// so `word` is a compile-time known string and `"..." ++ word ++ "..."` (compile-time
// concatenation) is allowed. A plain `for` could not do that.
test "repl ends on quit and on exit" {
    inline for (.{ "quit", "exit" }) |word| {
        var buf: [256]u8 = undefined;
        var w: Io.Writer = .fixed(&buf);
        var ctx: Context = .{ .out = &w };
        var in: Io.Reader = .fixed("\nresume\n" ++ word ++ "\nprint x\n");
        try repl(&ctx, &in, null);
        try std.testing.expect(ctx.quit);
        try std.testing.expectEqualStrings(
            prompt ++ prompt ++ "resume echo, not yet implemented\n" ++ prompt,
            w.buffered(),
        );
    }
}

test "repl ends at end of input and reports unknown commands" {
    var buf: [256]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var ctx: Context = .{ .out = &w };
    var in: Io.Reader = .fixed("frob\n");
    try repl(&ctx, &in, null);
    try std.testing.expect(!ctx.quit);
    try std.testing.expect(std.mem.indexOf(u8, w.buffered(), "unknown command: frob") != null);
}
