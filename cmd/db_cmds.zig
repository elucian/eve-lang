//! The commands of the database part (`eve db`): `db proc list`.
//! Part of the `eve` command (cli.zig holds the table of the commands and the REPL loop).
const std = @import("std");
const Io = std.Io;
const parser = @import("evecp").parser;
const ast = @import("evecm").ast;
const context = @import("context.zig");
const cli = @import("cli.zig");
// Zig tip: the shared names come from context.zig under short local names (`const Context = context.Context;`):
// the same type, not a copy. Files of one module may import each other, also in a circle.
const Context = context.Context;
const exit_usage = context.exit_usage;
const exit_syntax = context.exit_syntax;
const exit_no_input = context.exit_no_input;

// Zig tip: the VM session is created the first time a command needs it and kept in the Context, so
// Zig tip: `cmdDb` relies on the same Zig feature as `cmdDoc`: the work is done by a function with an inferred error
// set, and the handler passes on `WriteFailed` and turns every other error into a message.
/// `db`: the commands of the database part (`eve db ...`, D-163). Today `db proc list`.
pub fn cmdDb(ctx: *Context, args: []const []const u8) Io.Writer.Error!void {
    if (!(args.len == 2 and std.mem.eql(u8, args[0], "proc") and std.mem.eql(u8, args[1], "list"))) {
        try ctx.out.writeAll("db: usage: db proc list\n");
        ctx.status = exit_usage;
        return;
    }
    procList(ctx) catch |err| switch (err) {
        error.WriteFailed => |e| return e,
        else => {
            try ctx.out.print("db proc list: {s}\n", .{@errorName(err)});
            ctx.status = exit_no_input;
        },
    };
}

// Zig tip: `std.mem.sort` sorts a slice in place with a comparison function; `{}` is the empty context the function
// receives. `std.crypto.hash.sha2.Sha256.hash` fills a 32-byte array with the hash of the source, and
// `std.fmt.bytesToHex` writes bytes as hexadecimal text: the first 4 bytes are the short hash printed.
/// `db proc list`: each module of the folder `proc/`, sorted, with the hash of its source, and its exported procedures
/// and functions with their signatures (database.md#stored-procedures, D-166).
pub fn procList(ctx: *Context) !void {
    const io = ctx.io;
    var dir = Io.Dir.cwd().openDir(io, "proc", .{ .iterate = true }) catch {
        try ctx.out.writeAll("db proc list: there is no folder proc/ here\n");
        ctx.status = exit_no_input;
        return;
    };
    defer dir.close(io);
    var names: std.ArrayList([]const u8) = .empty;
    var entries = dir.iterate();
    while (try entries.next(io)) |e| {
        if (e.kind == .file and std.mem.endsWith(u8, e.name, ".eve")) try names.append(ctx.gpa, try ctx.gpa.dupe(u8, e.name));
    }
    std.mem.sort([]const u8, names.items, {}, lessName);
    ctx.status = 0;
    for (names.items) |name| {
        const src = try dir.readFileAlloc(io, name, ctx.gpa, .limited(16 << 20));
        var hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(src, &hash, .{});
        var diag: parser.Diag = .{};
        const tree = parser.parse(ctx.gpa, src, &diag) catch {
            try ctx.out.print("proc/{s}:{d}:{d}: error: {s}\n", .{ name, diag.line, diag.col, diag.message() });
            ctx.status = exit_syntax;
            continue;
        };
        if (tree.tag != .module) {
            try ctx.out.print("proc/{s}: not a module: a stored procedure lives in a module\n", .{name});
            ctx.status = exit_syntax;
            continue;
        }
        try ctx.out.print("{s} {s}\n", .{ tree.text, &std.fmt.bytesToHex(hash[0..4], .lower) });
        for (tree.kids) |ex| if (ex.tag == .export_decl) for (ex.kids) |n| {
            for (tree.kids) |d| if ((d.tag == .procedure or d.tag == .function) and std.mem.eql(u8, d.text, n.text)) {
                try writeSignature(ctx.out, d);
            };
        };
    }
}

// Zig tip: the first parameter of a comparison for `std.mem.sort` is the context (`void` here: none); `_` names a
// parameter that is not used, which Zig would otherwise report as an error. `std.mem.lessThan` orders bytes.
pub fn lessName(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

// Zig tip: `for (list, 0..) |q, i|` counts while it walks, so the separator `, ` goes before every item but the first.
/// One line: `  procedure archive(before: String, @moved: Integer)` or `  sql function f(x: T) => (@r: T)`.
pub fn writeSignature(w: *Io.Writer, d: *const ast.Node) Io.Writer.Error!void {
    try w.print("  {s}{s} {s}(", .{ if (d.is_sql) "sql " else "", @tagName(d.tag), d.text });
    try writeParams(w, d.kids[0].kids);
    try w.writeAll(")");
    if (d.tag == .function) {
        try w.writeAll(" => (");
        try writeParams(w, d.kids[2].kids);
        try w.writeAll(")");
    }
    try w.writeAll("\n");
}

// Zig tip: `writeParams` relies on the same Zig feature as `writeSignature` above: see the tip there. `if (q.ty) |t|`
// unwraps the optional type of a parameter: a parameter without a type prints its name alone.
pub fn writeParams(w: *Io.Writer, params: []const *const ast.Node) Io.Writer.Error!void {
    for (params, 0..) |q, i| {
        if (i > 0) try w.writeAll(", ");
        try w.print("{s}{s}", .{ if (q.tag == .ref_param) "@" else "", q.text });
        if (q.ty) |t| try w.print(": {s}", .{t.text});
    }
}
