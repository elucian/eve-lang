//! The commands of the compiler part (`eve cp`): `check`, `doc`, `project`.
//! Part of the `eve` command (cli.zig holds the table of the commands and the REPL loop).
const std = @import("std");
const Io = std.Io;
const parser = @import("evecp").parser;
const doc = @import("evecp").doc;
const scaffold = @import("evecp").scaffold;
const context = @import("context.zig");
const cli = @import("cli.zig");
// Zig tip: the shared names come from context.zig under short local names (`const Context = context.Context;`):
// the same type, not a copy. Files of one module may import each other, also in a circle.
const Context = context.Context;
const exit_usage = context.exit_usage;
const exit_syntax = context.exit_syntax;
const exit_no_input = context.exit_no_input;
const exit_cant_create = context.exit_cant_create;

// Zig tip: `Dir.cwd().readFileAlloc(io, path, gpa, limit)` reads a whole file into memory that
// `gpa` provides, and fails with an error if it is missing or longer than the limit
// (`.limited(n)` is a size limit in bytes). The caller frees it with `defer gpa.free(src)`.
// `catch |err| { ... continue; }` handles an error in place and goes on with the next file.
// `@errorName(err)` is the name of an error value as text. `worst` keeps the highest status.
// The message format `file:line:col: error: text` is the one editors and CI tools understand.
/// `check`: parse each file without executing it. Status 65 if any has a syntax error.
pub fn cmdCheck(ctx: *Context, args: []const []const u8) Io.Writer.Error!void {
    if (args.len == 0) {
        try ctx.out.writeAll("check: file name missing\n");
        ctx.status = exit_usage;
        return;
    }
    var worst: u8 = 0;
    for (args) |path| {
        const src = Io.Dir.cwd().readFileAlloc(ctx.io, path, ctx.gpa, .limited(16 << 20)) catch |err| {
            try ctx.out.print("{s}: cannot read: {s}\n", .{ path, @errorName(err) });
            worst = @max(worst, exit_no_input);
            continue;
        };
        defer ctx.gpa.free(src);
        var diag: parser.Diag = .{};
        if (parser.check(ctx.gpa, src, &diag)) {
            try ctx.out.print("{s}: ok\n", .{path});
        } else |err| switch (err) {
            error.Syntax => {
                try ctx.out.print("{s}:{d}:{d}: error: {s}\n", .{ path, diag.line, diag.col, diag.message() });
                worst = @max(worst, exit_syntax);
            },
            error.OutOfMemory => {
                try ctx.out.print("{s}: out of memory\n", .{path});
                worst = @max(worst, exit_no_input);
            },
        }
    }
    ctx.status = worst;
}

// Zig tip: `doc.generate(...) catch |err| switch (err) { ... }` handles the error union in place.
// `error.WriteFailed => |e| return e` passes on the one error this handler may return (its
// type is `Io.Writer.Error!void`); `else =>` covers every other error of the inferred set of
// `generate` (missing folder, unreadable file, out of memory) with one branch.
/// `doc`: write the Markdown documentation of a `.eve` file, or of the `.eve` files of a folder.
pub fn cmdDoc(ctx: *Context, args: []const []const u8) Io.Writer.Error!void {
    if (args.len == 0 or args.len > 2) {
        try ctx.out.writeAll("doc: usage: doc <folder | file.eve> [output folder, default doc]\n");
        ctx.status = exit_usage;
        return;
    }
    const out_path = if (args.len == 2) args[1] else "doc";
    const pages = doc.generate(ctx.io, ctx.gpa, args[0], out_path, ctx.out) catch |err| switch (err) {
        error.WriteFailed => |e| return e,
        else => {
            try ctx.out.print("doc: {s}: {s}\n", .{ args[0], @errorName(err) });
            ctx.status = exit_no_input;
            return;
        },
    };
    if (pages == 0) try ctx.out.print("doc: no .eve file in {s}\n", .{args[0]});
    ctx.status = 0;
}

// Zig tip: a subcommand is read from the first word of `args`. `std.mem.eql` compares the text
// (see `find`). `scaffold.init` returns an error union; `catch |err| switch (err)` passes on the
// one error of this handler's type (`WriteFailed`) and reports every other one as a message.
// `init` and `new` differ in one test only, so `is_new` is a plain bool and not two functions.
/// `project init <folder>` and `project new <folder>`: make a project with the standard layout
/// (plan/design-project-layout.md). `init` also works on an existing project and keeps its files;
/// `new` fails when the folder exists and is not empty.
pub fn cmdProject(ctx: *Context, args: []const []const u8) Io.Writer.Error!void {
    const is_new = args.len == 2 and std.mem.eql(u8, args[0], "new");
    if (args.len != 2 or !(is_new or std.mem.eql(u8, args[0], "init"))) {
        try ctx.out.writeAll("project: usage: project init <folder> | project new <folder>\n");
        ctx.status = exit_usage;
        return;
    }
    if (is_new) {
        const free = scaffold.isEmptyOrAbsent(ctx.io, Io.Dir.cwd(), args[1]) catch false;
        if (!free) {
            try ctx.out.print("project: {s} exists and is not empty (project init keeps its files)\n", .{args[1]});
            ctx.status = exit_cant_create;
            return;
        }
    }
    const result = scaffold.init(ctx.io, ctx.gpa, Io.Dir.cwd(), args[1], true, ctx.out) catch |err| switch (err) {
        error.WriteFailed => |e| return e,
        else => {
            try ctx.out.print("project: {s}: {s}\n", .{ args[1], @errorName(err) });
            ctx.status = exit_cant_create;
            return;
        },
    };
    try ctx.out.print("project {s}: {s}: {d} created, {d} kept\n", .{ args[0], args[1], result.created, result.kept });
    ctx.status = 0;
}
