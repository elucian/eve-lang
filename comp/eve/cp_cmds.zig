//! @eve-module eve.cp_cmds
//! @decision D-198
//! The commands of the compiler part (`eve cp`): `check`, `doc`, `project`. The work is done by `evecp.cli`, the same code
//! as the program `evecp`, run here in the process of `eve`; these functions only give it the files, the memory and the output
//! of the `Context` and keep its exit status. Part of the `eve` command (cli.zig holds the table of the commands).
const std = @import("std");
const Io = std.Io;
const evecp = @import("evecp");
const context = @import("context.zig");
const Context = context.Context;

fn env(ctx: *Context) evecp.cli.Env {
    return .{ .io = ctx.io, .gpa = ctx.gpa, .out = ctx.out };
}

/// `check`: parse each file without executing it. Status 65 if any has a syntax error.
// @eve-fn cp.check
// @see comp/evecp/src/cli.zig:check
pub fn cmdCheck(ctx: *Context, args: []const []const u8) Io.Writer.Error!void {
    ctx.status = try evecp.cli.check(env(ctx), args);
}

/// `doc`: write the Markdown documentation of a `.eve` file, or of the `.eve` files of a folder.
// @eve-fn cp.doc
// @see comp/evecp/src/cli.zig:docs
pub fn cmdDoc(ctx: *Context, args: []const []const u8) Io.Writer.Error!void {
    ctx.status = try evecp.cli.docs(env(ctx), args);
}

/// `outline`: the nested outline of each file, or its syntax error.
// @eve-fn cp.outline
// @see comp/evecp/src/cli.zig:outline
pub fn cmdOutline(ctx: *Context, args: []const []const u8) Io.Writer.Error!void {
    ctx.status = try evecp.cli.outline(env(ctx), args, false);
}

/// `symbols`: the symbols of each file as one flat list.
// @eve-fn cp.symbols
// @see comp/evecp/src/cli.zig:outline
pub fn cmdSymbols(ctx: *Context, args: []const []const u8) Io.Writer.Error!void {
    ctx.status = try evecp.cli.outline(env(ctx), args, true);
}

/// `project init <folder>` and `project new <folder>`: make a project with the standard layout.
// @eve-fn cp.project
// @see comp/evecp/src/cli.zig:project
pub fn cmdProject(ctx: *Context, args: []const []const u8) Io.Writer.Error!void {
    ctx.status = try evecp.cli.project(env(ctx), args);
}
