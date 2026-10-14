//! The commands of the REPL itself: `quit`, `clear`, `help`.
//! Part of the `eve` command (cli.zig holds the table of the commands and the REPL loop).
const std = @import("std");
const Io = std.Io;
const screen = @import("evevm").screen;
const tui = @import("evevm").tui;
const helptext = @import("evevm").helptext;
const context = @import("context.zig");
const cli = @import("cli.zig");
// Zig tip: the shared names come from context.zig under short local names (`const Context = context.Context;`):
// the same type, not a copy. Files of one module may import each other, also in a circle.
const Context = context.Context;
const exit_usage = context.exit_usage;
const prompt = context.prompt;

// Zig tip: `ctx` is a pointer, so `ctx.quit = true` changes the caller's Context. Zig has no
// hidden copies: a struct passed by value is copied, a pointer lets the callee modify it.
// Fields are reached with `.` for both a struct and a pointer to it.
pub fn cmdQuit(ctx: *Context, _: []const []const u8) Io.Writer.Error!void {
    ctx.quit = true;
}

// Zig tip: the same command does the right thing in each of the three kinds of screen: the scrollback of the
// full-screen REPL is emptied, a plain terminal gets the escape codes that erase the window and move the cursor home,
// and a pipe gets nothing (an escape code in a file is noise).
/// `clear`: clear the upper part of the screen.
pub fn cmdClear(ctx: *Context, _: []const []const u8) Io.Writer.Error!void {
    if (ctx.tui) |t| {
        t.clear();
    } else if (ctx.fancy) {
        try ctx.out.writeAll("\x1b[2J\x1b[H");
    }
}

// Zig tip: the same function serves the full-screen REPL and the plain prompt. With a screen, the text is added as a
// *block* (`addBlock`), which the screen draws again when the window changes size; without one the text is written at
// once, at the width of `eve_width`. `orelse { ... return; }` leaves the function with a message when the optional
// is null: here, a command that has no help.
/// `help` and `?`: the table of the commands; `help <command>`: the page of one command.
pub fn cmdHelp(ctx: *Context, args: []const []const u8) Io.Writer.Error!void {
    const style: screen.Style = .{ .fancy = ctx.fancy };
    if (args.len == 0) {
        if (ctx.tui) |t| t.addBlock(.help_table, 0) else try screen.writeHelpTable(ctx.out, style, ctx.width);
        return;
    }
    const index = helptext.indexOf(args[0]) orelse {
        try ctx.out.print("help: no help for {s} (type help for the list)\n", .{args[0]});
        ctx.status = exit_usage;
        return;
    };
    if (ctx.tui) |t| t.addBlock(.help_command, index) else try screen.writeDetail(ctx.out, style, helptext.entries[index], ctx.width);
}

// Zig tip: a `switch` on an enum must cover every tag; `catch {}` drops the write error because the writer here is a
// block in memory that cannot fail in a way the screen could use.
/// The function that the full-screen REPL calls to draw a block again for a new width.
pub fn renderBlock(kind: tui.BlockKind, arg: usize, width: usize, w: *Io.Writer) void {
    const style: screen.Style = .{ .fancy = true };
    switch (kind) {
        .help_table => screen.writeHelpTable(w, style, width) catch {},
        .help_command => screen.writeDetail(w, style, helptext.entries[arg], width) catch {},
    }
}
