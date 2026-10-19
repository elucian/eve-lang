//! The types that every command shares: the context of a run, a handler, a command of the table, the exit codes.
//! Part of the `eve` command (cli.zig holds the table of the commands and the REPL loop).
const std = @import("std");
const Io = std.Io;
const vm = @import("evevm").vm;
const screen = @import("evevm").screen;
const tui = @import("evevm").tui;
const cli = @import("cli.zig");
const evecp = @import("evecp");

// Zig tip: `pub` makes a declaration visible to other files (main.zig uses `cli.exit_usage`).
// Without it the name is private to this file. A `const` number without a type is a
// `comptime_int`: it has no size until it is used (here as the `u8` exit status).
// `///` documents the next declaration, `//!` documents the file; tools show both.
/// Exit status: bad command line (EX_USAGE).
pub const exit_usage = 64;

/// Exit status: the script has syntax errors (EX_DATAERR), reported by `check`.
pub const exit_syntax = evecp.cli.exit_syntax;

/// Exit status: not implemented, outside the Eve range (EX_SOFTWARE).
pub const exit_not_implemented = 70;

/// The input file cannot be read (EX_NOINPUT of sysexits.h).
pub const exit_no_input = evecp.cli.exit_no_input;

/// A file or folder cannot be created (EX_CANTCREAT of sysexits.h).
pub const exit_cant_create = evecp.cli.exit_cant_create;

// Zig tip: a string literal is a pointer to a constant array of bytes; there is no string type.
// Text is `[]const u8`: a slice (pointer + length) of read-only bytes, in UTF-8.
pub const prompt = "eve:> ";

// Zig tip: a `struct` is a record. Fields can have default values (`= false`), so
// `.{ .out = w }` builds a Context and fills the rest. Types are written after the name:
//   `*Io.Writer`    pointer to one Writer (the struct does not own it, it only borrows it)
//   `?[]const u8`   optional: either a string or `null` (no -s option given)
//   `u8`            unsigned 8-bit integer, 0 to 255, exactly what a process exit code is
/// State shared by the command handlers.
pub const Context = struct {
    out: *Io.Writer,
    /// For reading files, and the allocator the commands use for the file and its tokens.
    io: Io,
    gpa: std.mem.Allocator,
    /// `-d`: `halt` statements stop the script; otherwise they are ignored.
    debug: bool = false,
    /// `-e file.cfg` or `--setup file.cfg` (the same file `setup` loads), or the file after `-s`
    config: ?[]const u8 = null,
    /// `-m size`
    memory: ?[]const u8 = null,
    /// The VM session, created by the first command that needs it.
    machine: ?*vm.Session = null,
    /// Set by `quit` and `exit`: the REPL ends.
    quit: bool = false,
    /// Exit status of the last command.
    status: u8 = 0,
    /// A person is at the terminal: boxes in UTF-8 and colors (set by `main`), else plain ASCII.
    fancy: bool = false,
    /// The full-screen REPL, when there is one: `out` writes into its upper part.
    tui: ?*tui.Tui = null,
    /// The width of the help table and texts: EVE_WIDTH, or `eve_width` of eve.cfg, or 100.
    width: usize = screen.default_width,
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
    /// Extension of the file the command takes (Tab completes such files); "" when it takes none.
    file: []const u8 = "",
};

// Zig tip: `comptime` parameters are known while compiling. `stub("check")` is evaluated by the
// compiler, which generates a separate small function for each name. A function cannot capture
// local variables, so the trick is to return a function declared inside an anonymous struct,
// whose `name` is a constant the compiler fills in. `_` as a parameter name means "unused":
// Zig reports unused parameters and variables as errors. `try x` means: if `x` is an error,
// return it from this function at once; otherwise use the value. `.{name}` is a tuple of the
// values for the `{s}` placeholder (`s` = string) of `print`.
/// A branch that is not written yet: it echoes its name.
pub fn stub(comptime name: []const u8) Handler {
    return struct {
        fn run(ctx: *Context, _: []const []const u8) Io.Writer.Error!void {
            try ctx.out.print("{s} command, not yet implemented\n", .{name});
            ctx.status = exit_not_implemented;
        }
    }.run;
}
