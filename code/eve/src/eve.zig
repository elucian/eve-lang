//! `eve` command line: help, REPL and one-shot commands (the commands are not implemented yet).
const std = @import("std");
const Io = std.Io;
const builtin = @import("builtin");

const evecm = @import("evecm");
const evecp = @import("evecp");
const evevm = @import("evevm");
const cli = @import("cli.zig");
const Terminal = evecm.terminal.Terminal;

pub const std_options: std.Options = .{ .unexpected_error_tracing = false };

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

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    // @decision D-128
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

    evecm.heap.show_stats = std.mem.eql(u8, init.environ_map.get("EVE_MEMSTATS") orelse "", "1");
    evecm.heap.verify = std.mem.eql(u8, init.environ_map.get("EVE_GC_VERIFY") orelse "", "1");
    evevm.bcvm.trace = std.mem.eql(u8, init.environ_map.get("EVE_BC_TRACE") orelse "", "1");
    // @eve-impl the engine of the run: `--engine bc` or `EVE_ENGINE=bc` selects the bytecode machine (D-201)
    if (std.mem.eql(u8, init.environ_map.get("EVE_ENGINE") orelse "", "bc")) evevm.interp.engine = .bytecode;
    if (std.mem.eql(u8, init.environ_map.get("EVE_PROFILE") orelse "", "1")) evevm.profile.start(arena);

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .initStreaming(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    var argv: std.ArrayList([]const u8) = .empty;
    for (args[@min(1, args.len)..]) |a| try argv.append(arena, a);

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
    const opts = cli.parseArgs(arena, argv.items, &bad) catch |err| {
        switch (err) {
            error.MissingValue => std.debug.print("eve: option {s} needs a value\n", .{bad}),
            error.UnknownOption => std.debug.print("eve: unknown option {s}\n", .{bad}),
            error.BadWord => std.debug.print("eve: {s}: expected start, stop, restart or status after --listen or --serve\n", .{bad}),
            error.BadOptimization => std.debug.print("eve: -O takes a whole number from 0 to 10, not {s}\n", .{bad}),
            error.ServiceAlone => std.debug.print("eve: -s starts the service and takes only a configuration file; to load a configuration for a script or a command use -e file.cfg\n", .{}),
            error.OutOfMemory => return err,
        }
        std.debug.print("Try 'eve --help'.\n", .{});
        std.process.exit(cli.exit_usage);
    };

    // the optimization level: `-O` first, then eve.cfg, then the implicit level 1 (D-227); set before any run
    const optimization_cfg = evecm.config.readConfig(init.io, arena, opts.config orelse "eve.cfg");
    evecm.optimization.level = opts.optimization orelse (if (optimization_cfg) |c| c.optimization else null) orelse evecm.optimization.default_level;

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

    var ctx: cli.Context = .{
        .out = stdout,
        .io = init.io,
        .gpa = arena,
        .debug = opts.debug,
        .config = opts.config,
        .memory = opts.memory,
        .params = opts.params,
        .script_help = opts.script_help,
    };

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
    // nothing here runs: `eve -x file.eve` asks no door and executes the script at once (it reads `eve.cfg` only for the optimization level, D-227).
    // @decision D-185
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

    const term: ?Terminal = if (interactive) Terminal.enter() catch null else null;
    defer if (term) |t| t.leave();
    var width: usize = evevm.screen.default_width;
    if (evecm.config.readConfig(init.io, arena, opts.config orelse "eve.cfg")) |c| width = c.eve_width;
    if (init.environ_map.get("EVE_WIDTH")) |text| width = std.fmt.parseInt(usize, std.mem.trim(u8, text, " "), 10) catch width;
    ctx.width = std.math.clamp(width, evevm.screen.min_width, 400);

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
// @spec manual/usage.md#the-machine---listen---serve--loc--rem
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
