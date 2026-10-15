//! The help pages of `eve -h` and of the `help` command.
//! Part of the `eve` command (cli.zig holds the table of the commands and the REPL loop).
const std = @import("std");
const Io = std.Io;
const version = @import("evecm").version;
const screen = @import("evevm").screen;
const context = @import("context.zig");
const cli = @import("cli.zig");
// Zig tip: the shared names come from context.zig under short local names (`const Context = context.Context;`):
// the same type, not a copy. Files of one module may import each other, also in a circle.
const prompt = context.prompt;

// Zig tip: lines that start with `\\` form a multi-line string literal. There are no escapes
// inside; each line ends with a newline and the text starts right after the `\\`. The last
// line `\\` followed by nothing adds an empty line.
pub const quick_help =
    \\Usage: eve [options]                      start the REPL
    \\       eve [options] <script.eve> [args]  execute a script (same as -x)
    \\       eve [options] <command> [args]     run one command and exit, no REPL (same as --<command>)
    \\       evevm [start|stop|restart|status]  the machine in a new process (listen and serve), the prompt returns
    \\
    \\Quick help:
    \\  -x                execute the script now, in this process (parsed first): no IPC or
    \\                    HTTP lookup, the fast way to run a script; same as --execute
    \\  -ux               open the web user interface (the page of the machine) if it is not open; with a
    \\                    command, open it and then run the command
    \\  -tx [folder]      start the terminal IDE, evetx, on a project folder (also: eve tx)
    \\  --kill            stop all the other eve programs of this bin/ folder (eve, evetx, evedb); the build runs it (also: eve kill)
    \\  -d                debug mode: halt statements stop the script (ignored otherwise)
    \\  -s <file.cfg>     setup: load the configuration file
    \\  -m <size>         memory for the process
    \\  -i <file>         slot: cli.commands (report, stop) that other programs append to the file
    \\  -t <seconds>      slot without a script: stop after this long without a command
    \\  -v, --version     display the version and exit
    \\  -h, --help        display this help and exit
    \\
    \\The machine (an eve that stays active and answers requests):
    \\  --listen [word]   the IPC door (this computer): start (the default), stop, restart or status
    \\  --serve [word]    the HTTP door: start (the default), stop, restart or status
    \\                    --listen --serve opens both doors; the ports are ipc_port and http_port of eve.cfg
    \\  -loc [port]       --local: run the command in the machine through IPC, or in
    \\                    this process when none listens; never the network
    \\  -rem [host:port]  --remote: run the command in a remote machine through HTTP;
    \\                    fails when nobody answers (no address: remote of eve.cfg)
    \\
;

pub const more_prompt = "-- press enter for more --";

pub const commands_head =
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
    for (&cli.commands) |c| try w.print("  --{s: <9}{s}\n", .{ c.name, c.summary });
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
