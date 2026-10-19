//! `eve` command line: help, REPL and one-shot commands (the commands are not implemented yet).
// Zig tip: `@import("evevm")` is not a file but a module named in build.zig (`.imports`). That
// is how the thin `eve` program uses the parts of Eve; the parts never import the program, and the
// build refuses an import that the arrows of design-packages.md §3 do not allow. Only the module
// root file is named, and it re-exports what others may use.
const std = @import("std");
const Io = std.Io;
const builtin = @import("builtin");

const evecm = @import("evecm");
const evecp = @import("evecp");
const evevm = @import("evevm");
const cli = @import("cli.zig");
const Terminal = evecm.terminal.Terminal;

// Zig tip: a root file can declare `pub const std_options: std.Options`, and the standard library reads it at compile
// time to tune itself. `unexpected_error_tracing` prints a stack trace in Debug builds each time the system returns a
// code the library does not map. On Windows, Zig 0.16 does not map CONNECTION_REFUSED, so asking for a machine that
// is not running (`eve --serve status`) printed two traces before the right answer, `eve: not running`. The VM
// handles that error itself (comp/evevm/src/client.zig), so the trace is turned off.
pub const std_options: std.Options = .{ .unexpected_error_tracing = false };

// Zig tip: `std.ascii.lowerString(buf, text)` copies the text in lower case letters into `buf` and answers the part it
// used; a name that does not fit in the buffer cannot be `evevm`, so it is answered as it is. `lastIndexOfAny` finds
// the last `/` or `\`, which is where the file name starts on either system.
/// The name of the program without its folder and extension, in lower case: `C:\bin\EVEVM.exe` is `evevm`.
fn programName(buf: []u8, path: []const u8) []const u8 {
    const cut = std.mem.lastIndexOfAny(u8, path, "/\\");
    const file = if (cut) |i| path[i + 1 ..] else path;
    const name = file[0 .. std.mem.lastIndexOfScalar(u8, file, '.') orelse file.len];
    if (name.len > buf.len) return name;
    return std.ascii.lowerString(buf, name);
}

// @eve-impl folder of the standard modules written in Eve; null when there is none (a bare `eve.exe` copied alone)
// @spec spec/library/registry.md#search-order
// @invariant the folder holds `*.eve` modules directly (no `sys/`: those are signature files, never imported)
fn standardLibrary(init: std.process.Init, arena: std.mem.Allocator) ?[]const u8 {
    const folder = if (init.environ_map.get("EVE_STDLIB")) |f| f else blk: {
        const exe_dir = std.process.executableDirPathAlloc(init.io, arena) catch return null;
        break :blk std.fs.path.join(arena, &.{ exe_dir, "..", "lib" }) catch return null;
    };
    var dir = Io.Dir.cwd().openDir(init.io, folder, .{}) catch return null;
    dir.close(init.io);
    return folder;
}

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
        evecp.project.env_lib_path = folders.items;
    }

    // @eve-impl the standard library in Eve: `<prefix>/lib` for `<prefix>/bin/eve.exe`, or `$EVE_STDLIB`; searched before `$EVE_LIB_PATH`
    // @spec spec/library/registry.md#search-order
    // @feature F-LIB-01
    // @decision D-189
    if (standardLibrary(init, arena)) |std_folder| {
        var folders: std.ArrayList([]const u8) = .empty;
        try folders.append(arena, std_folder);
        try folders.appendSlice(arena, evecp.project.env_lib_path);
        evecp.project.env_lib_path = folders.items;
    }

    // Zig tip: `environ_map.get` answers an optional text; `orelse ""` turns a missing variable into an
    // empty one, so one comparison covers both cases. The heap reads these two switches (heap.zig).
    evecm.heap.show_stats = std.mem.eql(u8, init.environ_map.get("EVE_MEMSTATS") orelse "", "1");
    evecm.heap.verify = std.mem.eql(u8, init.environ_map.get("EVE_GC_VERIFY") orelse "", "1");
    // @eve-impl the engine of the run: `--engine bc` or `EVE_ENGINE=bc` selects the bytecode machine (D-201)
    if (std.mem.eql(u8, init.environ_map.get("EVE_ENGINE") orelse "", "bc")) evevm.interp.engine = .bytecode;
    if (std.mem.eql(u8, init.environ_map.get("EVE_PROFILE") orelse "", "1")) evevm.profile.start(arena);

    // Zig tip: `File.Writer.init` writes at its own position from 0 when the file can seek, which is right for a
    // file the program opened, but wrong for the standard output: `eve -x a.eve >> log.txt` overwrote the start of
    // the log. `initStreaming` writes where the system says (the end, with `>>`), like a pipe or a terminal.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .initStreaming(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    // Zig tip: `args[@min(1, args.len)..]` is a slice from index 1 (skip the program name);
    // `@min` keeps it valid even when args is empty. `for (xs) |a| stmt;` loops over a slice.
    var argv: std.ArrayList([]const u8) = .empty;
    for (args[@min(1, args.len)..]) |a| try argv.append(arena, a);

    // Zig tip: the same program file is installed twice, as `eve` and as `evevm`, and it looks at its own name to know
    // which one it is. `evevm` starts the machine in a new process and gives the prompt of the system back, so it
    // needs the runtime folder for the sockets before anything else, and it never reads the options of `eve`.
    // The machine that `evevm` starts is this same file started with `--listen --serve`: with one of these options
    // `evevm` behaves as `eve` and runs the machine in the foreground of its own (hidden) process.
    var name_buffer: [64]u8 = undefined;
    var foreground = false;
    for (argv.items) |a| {
        if (std.mem.eql(u8, a, "--listen") or std.mem.eql(u8, a, "--serve")) foreground = true;
    }
    if (!foreground and args.len > 0 and std.mem.eql(u8, programName(&name_buffer, args[0]), "evevm")) {
        evecm.config.runtime_dir = init.environ_map.get("XDG_RUNTIME_DIR") orelse init.environ_map.get("TMPDIR") orelse init.environ_map.get("TEMP") orelse "/tmp";
        const code = try evevm.daemon.daemonMain(init.io, arena, stdout, argv.items);
        try stdout.flush();
        std.process.exit(code);
    }

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
            error.BadWord => std.debug.print("eve: {s}: expected start, stop, restart or status after --listen or --serve\n", .{bad}),
            error.ServiceAlone => std.debug.print("eve: -s starts the service and takes only a configuration file; to load a configuration for a script or a command use -e file.cfg\n", .{}),
            error.OutOfMemory => return err,
        }
        std.debug.print("Try 'eve --help'.\n", .{});
        std.process.exit(cli.exit_usage);
    };

    if (opts.engine) |name| {
        if (std.mem.eql(u8, name, "bc") or std.mem.eql(u8, name, "bytecode")) {
            evevm.interp.engine = .bytecode;
        } else if (std.mem.eql(u8, name, "tree")) {
            evevm.interp.engine = .tree;
        } else {
            std.debug.print("eve: --engine takes tree or bc, not {s}\n", .{name});
            std.process.exit(cli.exit_usage);
        }
    }

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
        try stdout.print("{s}\n", .{evecm.version.title});
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
    };

    // Zig tip: the runtime directory for the IPC sockets comes from the environment, once, before any thread starts.
    // `orelse` chains try the variables in order; `get` answers an optional text.
    evecm.config.runtime_dir = init.environ_map.get("XDG_RUNTIME_DIR") orelse init.environ_map.get("TMPDIR") orelse init.environ_map.get("TEMP") orelse "/tmp";
    // the shell of `shell <command>`, `!<command>` and `vm.shell`: the one that started eve (`SHELL`: Git Bash, a Linux
    // shell; a Unix path such as /usr/bin/bash is not a Windows path, so on Windows its name is looked up in PATH), else
    // the command shell of Windows (`COMSPEC`)
    if (init.environ_map.get("SHELL")) |sh| {
        evevm.channel.shell_path = if (builtin.os.tag == .windows) std.fs.path.basenamePosix(sh) else sh;
    } else if (builtin.os.tag == .windows) {
        if (init.environ_map.get("COMSPEC")) |cs| evevm.channel.shell_path = cs;
    }
    // `--stdio`: the machine of one client on the standard input and output; nothing else of `main` runs
    if (opts.stdio) std.process.exit(try evevm.channel.serveStdio(init.io, arena, opts.config orelse "eve.cfg", init.environ_map.get("EVE_LOG") != null));
    // The machine options (`--listen`, `--serve`, `-loc`, `-rem`): a result means they handled the command. Without them
    // nothing here runs: `eve -x file.eve` reads no `eve.cfg` and asks no door, it executes the script at once.
    // Zig tip: at a terminal `eve --serve` opens the doors in threads and the prompt comes back (`embed`), so the same
    // window can send commands to its own machine; with a pipe, a file or a service manager nobody types, and the
    // start waits for the doors as before. `machine.embedded` tells that the doors are open in this process.
    // `-s`: the service (D-185). Nothing is printed on success; a failure goes to the error output. With EVE_SERVICE=foreground
    // this process is the machine itself (a container, systemd `Type=simple`); otherwise it starts one in a process of its own.
    if (opts.service) {
        var errbuf: [512]u8 = undefined;
        var errw: Io.File.Writer = .initStreaming(.stderr(), init.io, &errbuf);
        const stay = std.mem.eql(u8, init.environ_map.get("EVE_SERVICE") orelse "", "foreground");
        // `eve -s -db --serve evedb.cfg`: the service is evedb, the database server (D-186)
        const db_serve = opts.command != null and std.mem.eql(u8, opts.command.?.name, "db") and opts.args.len >= 1 and std.mem.eql(u8, opts.args[0], "serve");
        const code = if (db_serve) blk: {
            const cfg_path = if (opts.args.len >= 2) opts.args[1] else "evedb.cfg";
            break :blk try evevm.service.runEvedb(init.io, arena, cfg_path, stay, &errw.interface);
        } else try evevm.service.run(init.io, arena, opts.config, stay, &errw.interface);
        try errw.interface.flush();
        std.process.exit(code);
    }
    if (opts.tx) std.process.exit(try startPart(init.io, arena, stdout, "evetx", opts.tx_args));
    if (opts.ux) std.process.exit(try startPart(init.io, arena, stdout, "eveux", opts.ux_args));
    if (opts.kill) std.process.exit(try killOthers(init.io, arena, stdout));
    const interactive = (try Io.File.stdin().isTty(init.io)) and (try Io.File.stdout().isTty(init.io));
    // Zig tip: `Io.Writer.Allocating` is a writer that keeps what it is given in memory. At a terminal the machine
    // options write into it first, because the full-screen REPL (which may follow) starts only afterwards and has to
    // show these lines in its own upper part; a command that ends the program prints them on the plain screen.
    var held: Io.Writer.Allocating = .init(arena);
    const early_out: *Io.Writer = if (interactive) &held.writer else stdout;
    if (opts.machine.listen or opts.machine.serve or opts.machine.local or opts.machine.remote) {
        if (try evevm.client.handle(init.io, arena, early_out, opts.machine, interactive and opts.command == null and opts.machine.script == null)) |code| {
            if (!evevm.machine.embedded) {
                try stdout.writeAll(held.written());
                try stdout.flush();
                std.process.exit(code);
            }
        }
    }
    const early = held.written();

    if (opts.command) |command| {
        try stdout.writeAll(early);
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
    const term: ?Terminal = if (interactive) Terminal.enter() catch null else null;
    defer if (term) |t| t.leave();
    // Zig tip: the width of the help table and texts: the variable EVE_WIDTH wins, then `eve_width` of the configuration
    // file, then 100. `parseInt(...) catch width` keeps the earlier value when the text is not a number, and
    // `std.math.clamp` keeps the result between the least width worth drawing and a generous maximum.
    var width: usize = evevm.screen.default_width;
    if (evecm.config.readConfig(init.io, arena, opts.config orelse "eve.cfg")) |c| width = c.eve_width;
    if (init.environ_map.get("EVE_WIDTH")) |text| width = std.fmt.parseInt(usize, std.mem.trim(u8, text, " "), 10) catch width;
    ctx.width = std.math.clamp(width, evevm.screen.min_width, 400);

    // Zig tip: the full-screen REPL (tui.zig) needs the size of the window; without it the prompt keeps the plainer
    // look of a banner and a line editor. `defer t.leave()` is declared after the terminal's, so it runs first: the
    // screen is given back, then the keyboard mode.
    var screen_ui: ?*evevm.tui.Tui = null;
    if (term != null and Terminal.size() != null) {
        const raw_buffer = try arena.alloc(u8, 16384);
        const raw = try arena.create(Io.File.Writer);
        raw.* = .initStreaming(.stdout(), init.io, raw_buffer);
        screen_ui = try evevm.tui.Tui.create(init.io, arena, &raw.interface);
    }
    defer if (screen_ui) |t| t.leave();
    if (screen_ui) |t| {
        t.enter();
        ctx.out = &t.out;
        ctx.tui = t;
        ctx.fancy = true;
        evevm.machine.embed_log = &t.out;
        try evevm.screen.writeBanner(ctx.out, .{ .fancy = true });
        try ctx.out.writeAll(early);
        try ctx.out.flush();
    } else if (term != null) {
        // the banner and the colored table are for a person at a terminal; a pipe gets the plain text
        ctx.fancy = true;
        try evevm.screen.writeBanner(stdout, .{ .fancy = true });
        try stdout.writeAll(early);
        try stdout.flush();
    } else {
        try stdout.writeAll(early);
    }
    const edit: ?cli.Edit = if (term != null) .{ .io = init.io, .gpa = arena } else null;
    try cli.repl(&ctx, &stdin_file_reader.interface, edit);
}

// Zig tip: a program cannot replace its own file, or the file of a program that runs, on Windows: the build fails with
// AccessDenied. `eve --kill` asks the system to end the other programs of its own `bin/` folder. On Windows the work is
// the PowerShell script `script/stop_eve.ps1` (the same one `run.sh` and the build use); `-SkipParent` keeps this eve
// alive, since it is the parent of the PowerShell it started. Elsewhere `pkill -f` matches the full path of the program.
/// `eve --kill`: stop every other eve program that runs from the folder of this one.
fn killOthers(io: Io, arena: std.mem.Allocator, out: *Io.Writer) !u8 {
    const dir = try std.process.executableDirPathAlloc(io, arena);
    var argv: std.ArrayList([]const u8) = .empty;
    if (@import("builtin").os.tag == .windows) {
        const script = try std.fmt.allocPrint(arena, "{s}/../script/stop_eve.ps1", .{dir});
        try argv.appendSlice(arena, &.{ "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script, "-Bin", dir, "-SkipParent" });
    } else {
        const pattern = try std.fmt.allocPrint(arena, "{s}/evetx|{s}/evedb|{s}/evevm", .{ dir, dir, dir });
        try argv.appendSlice(arena, &.{ "pkill", "-f", pattern });
    }
    var child = std.process.spawn(io, .{ .argv = argv.items, .stdin = .inherit, .stdout = .inherit, .stderr = .inherit }) catch |err| {
        try out.print("eve: cannot run {s}: {s}\n", .{ argv.items[0], @errorName(err) });
        try out.flush();
        return 69;
    };
    _ = try child.wait(io);
    return 0;
}

// @eve-impl `eve -tx` and `eve -ux`: start a separate program that sits beside eve in bin/ and wait for it
// @spec manual/usage.md#the-user-interfaces--ux-and--tx-d-172
// @decision D-172
// @decision D-193
/// Start `name` (`evetx` the terminal IDE, `eveux` the native workbench) from the folder of `eve` with `args`, sharing this terminal, and
/// wait for it. Both are separate programs until they join the root build; a missing file is exit 69 with the build command.
fn startPart(io: Io, arena: std.mem.Allocator, out: *Io.Writer, name: []const u8, args: []const []const u8) !u8 {
    const dir = try std.process.executableDirPathAlloc(io, arena);
    const exe = try std.fmt.allocPrint(arena, "{s}{c}{s}{s}", .{ dir, std.fs.path.sep, name, @import("builtin").target.exeFileExt() });
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.append(arena, exe);
    try argv.appendSlice(arena, args);
    var child = std.process.spawn(io, .{ .argv = argv.items, .stdin = .inherit, .stdout = .inherit, .stderr = .inherit }) catch |err| {
        try out.print("eve: cannot start {s}: {s} (build it: ./run.sh build {s})\n", .{ exe, @errorName(err), name });
        try out.flush();
        return 69;
    };
    const term = try child.wait(io);
    return switch (term) {
        .exited => |code| code,
        else => 1,
    };
}
