//! The commands of the REPL itself: `quit`, `clear`, `help`.
//! Part of the `eve` command (cli.zig holds the table of the commands and the REPL loop).
const std = @import("std");
const Io = std.Io;
const screen = @import("evevm").screen;
const tui = @import("evevm").tui;
const helptext = @import("evevm").helptext;
const context = @import("context.zig");
const cli = @import("cli.zig");
const Context = context.Context;
const exit_usage = context.exit_usage;
const prompt = context.prompt;

pub fn cmdQuit(ctx: *Context, _: []const []const u8) Io.Writer.Error!void {
    ctx.quit = true;
}

/// `clear`: clear the upper part of the screen.
pub fn cmdClear(ctx: *Context, _: []const []const u8) Io.Writer.Error!void {
    if (ctx.tui) |t| {
        t.clear();
    } else if (ctx.fancy) {
        try ctx.out.writeAll("\x1b[2J\x1b[H");
    }
}

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

/// The function that the full-screen REPL calls to draw a block again for a new width.
pub fn renderBlock(kind: tui.BlockKind, arg: usize, width: usize, w: *Io.Writer) void {
    const style: screen.Style = .{ .fancy = true };
    switch (kind) {
        .help_table => screen.writeHelpTable(w, style, width) catch {},
        .help_command => screen.writeDetail(w, style, helptext.entries[arg], width) catch {},
    }
}
