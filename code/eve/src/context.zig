//! The types that every command shares: the context of a run, a handler, a command of the table, the exit codes.
//! Part of the `eve` command (cli.zig holds the table of the commands and the REPL loop).
const std = @import("std");
const Io = std.Io;
const vm = @import("evevm").vm;
const screen = @import("evevm").screen;
const tui = @import("evevm").tui;
const cli = @import("cli.zig");
const evecp = @import("evecp");

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

pub const prompt = "eve:> ";

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
    /// `-p name=value`: the parameters of the script by name; `-h` after the script name asks for its help.
    params: []const []const u8 = &.{},
    script_help: bool = false,
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

pub const Handler = *const fn (ctx: *Context, args: []const []const u8) Io.Writer.Error!void;

pub const Command = struct {
    name: []const u8,
    summary: []const u8,
    run: Handler,
    /// Extension of the file the command takes (Tab completes such files); "" when it takes none.
    file: []const u8 = "",
};

/// A branch that is not written yet: it echoes its name.
pub fn stub(comptime name: []const u8) Handler {
    return struct {
        fn run(ctx: *Context, _: []const []const u8) Io.Writer.Error!void {
            try ctx.out.print("{s} command, not yet implemented\n", .{name});
            ctx.status = exit_not_implemented;
        }
    }.run;
}
