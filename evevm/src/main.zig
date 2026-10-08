//! `eve` command line: help, REPL and one-shot commands (the commands are not implemented yet).
// Zig tip: `@import("evevm")` is not a file but a module named in build.zig (`.imports`). That
// is how the thin `eve` program uses the library in src/root.zig; the library never imports
// the program. Only the module root file is named, and it re-exports what others may use.
const std = @import("std");
const Io = std.Io;

const evevm = @import("evevm");
const cli = evevm.cli;
const Terminal = evevm.terminal.Terminal;

// Zig tip: in Zig 0.16 `main` may take a `std.process.Init` that the runtime fills: `init.io`
// (the handle for input/output), `init.arena` (an allocator freed when the program ends) and
// `init.minimal.args` (the command line). `!void` means main may return an error; the runtime
// then prints it and exits with a failure. There are no global streams: output goes through a
// `Writer` you build yourself, with a buffer you provide (`var stdout_buffer: [1024]u8`).
// `.init(.stdout(), ...)` uses the declared type on the left to find `init`; `&x.interface`
// is the generic Writer inside the file writer, which is what other code asks for.
pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    // Zig tip: `std.mem.tokenizeScalar(u8, text, ';')` walks the pieces of a text between separators and skips
    // empty ones. The folders of `EVE_LIB_PATH` are separated like the PATH of the system (D-128).
    if (init.environ_map.get("EVE_LIB_PATH")) |list| {
        var folders: std.ArrayList([]const u8) = .empty;
        var parts = std.mem.tokenizeScalar(u8, list, std.fs.path.delimiter);
        while (parts.next()) |folder| try folders.append(arena, folder);
        evevm.project.env_lib_path = folders.items;
    }

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    // Zig tip: `args[@min(1, args.len)..]` is a slice from index 1 (skip the program name);
    // `@min` keeps it valid even when args is empty. `for (xs) |a| stmt;` loops over a slice.
    var argv: std.ArrayList([]const u8) = .empty;
    for (args[@min(1, args.len)..]) |a| try argv.append(arena, a);

    var bad: []const u8 = "";
    // Zig tip: `call() catch |err| { ... }` handles an error in place. The block must end by
    // leaving (return, exit) or produce the success type. `switch (err)` over an error set must
    // list every error (Zig checks it); `error.OutOfMemory => return err` passes it on.
    // `std.process.exit(n)` stops the program with exit status n. `std.debug.print` writes to
    // stderr, unbuffered: for messages that should not mix with the normal output.
    const opts = cli.parseArgs(arena, argv.items, &bad) catch |err| {
        switch (err) {
            error.MissingValue => std.debug.print("eve: option {s} needs a value\n", .{bad}),
            error.UnknownOption => std.debug.print("eve: unknown option {s}\n", .{bad}),
            error.OutOfMemory => return err,
        }
        std.debug.print("Try 'eve --help'.\n", .{});
        std.process.exit(cli.exit_usage);
    };

    var stdin_buffer: [4096]u8 = undefined;
    var stdin_file_reader: Io.File.Reader = .init(.stdin(), init.io, &stdin_buffer);

    if (opts.help) {
        // Page by page only when a person is at both ends; a pipe or a file gets everything.
        // Zig tip: `if` is an expression, so `if (paged) &reader else null` picks a value; the
        // result type is `?*Io.Reader` (a pointer or null). `and`/`or` are the logical operators
        // (not `&&`/`||`); they stop early.
        const paged = (try Io.File.stdin().isTty(init.io)) and (try Io.File.stdout().isTty(init.io));
        try cli.writeHelp(stdout, if (paged) &stdin_file_reader.interface else null);
        try stdout.flush();
        return;
    }
    if (opts.version) {
        try stdout.print("{s}\n", .{evevm.title});
        try stdout.flush();
        return;
    }

    // Zig tip: the struct literal fills `Context` by field name; `out`, `debug`, ... are
    // given and `quit` and `status` take their defaults. Always `flush` before exiting: the
    // buffer is not written by itself, and `std.process.exit` does not run `defer`s.
    var ctx: cli.Context = .{
        .out = stdout,
        .io = init.io,
        .gpa = arena,
        .debug = opts.debug,
        .config = opts.config,
        .memory = opts.memory,
        .slot = opts.slot,
        .idle_ms = if (opts.idle) |t| (std.fmt.parseInt(u64, t, 10) catch 30) * 1000 else 30_000,
    };

    if (opts.command) |command| {
        // One command from the command line, no REPL.
        try command.run(&ctx, opts.args);
        try stdout.flush();
        std.process.exit(ctx.status);
    }

    // Zig tip: `Terminal.enter() catch null` means "try it, and if it fails carry on without": the
    // result is an optional that is null when the console cannot switch mode. `defer` runs when
    // `main` ends, which restores the keyboard mode on every normal way out (`quit`, end of
    // input, an error); `if (term) |t|` unwraps the optional. Raw mode is used only when a
    // person is at both ends, so pipes behave as before.
    const interactive = (try Io.File.stdin().isTty(init.io)) and (try Io.File.stdout().isTty(init.io));
    const term: ?Terminal = if (interactive) Terminal.enter() catch null else null;
    defer if (term) |t| t.leave();
    const edit: ?cli.Edit = if (term != null) .{ .io = init.io, .gpa = arena } else null;
    try cli.repl(&ctx, &stdin_file_reader.interface, edit);
}
