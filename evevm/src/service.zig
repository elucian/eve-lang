//! Service mode: `eve -s` (D-185, design-service.md section 17). The machine runs with no user interface: no prompt, nothing
//! on the standard output, its log in a file. On Windows it is a service of the Service Control Manager; on Linux it is a
//! daemon that a shell, systemd or another init system starts.
//!
//! Three ways to arrive here, one machine at the end:
//!  1. from a console or a shell (`eve -s`): the machine is started in a process of its own, detached from the terminal, and
//!     `eve -s` ends as soon as the IPC door answers (`daemon.startDetached`);
//!  2. from the Service Control Manager (`sc create eve binPath= "…\eve.exe -s eve.cfg"`): this process is the service: it
//!     reports its state to Windows and stops when Windows says stop;
//!  3. in the foreground, when the variable `EVE_SERVICE` is `foreground` (a container, systemd `Type=simple`): this process
//!     is the machine and ends on SIGTERM or `vm.stop`.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const config = @import("evecm").config;
const wire = @import("evecm").wire;
const machine = @import("machine.zig");
const client = @import("client.zig");
const daemon = @import("daemon.zig");

const Config = config.Config;
const message = wire.message;

/// Set by a stop request (the Service Control Manager, SIGTERM, SIGINT): the foreground loop sees it and shuts the machine.
var stop_flag = std.atomic.Value(bool).init(false);

// Zig tip: the result type `!T` (or `Error!T`) is an error union: a value or an error. `try f()` passes the error to the
// caller; `f() catch …` handles it in place.
/// Where the pid of the machine is written: `<runtime>/eve-<domain>-<ipc_port>.pid`.
pub fn pidPath(gpa: std.mem.Allocator, cfg: Config) ![]u8 {
    return std.fmt.allocPrint(gpa, "{s}/eve-{s}-{d}.pid", .{ config.runtime_dir, cfg.domain, cfg.ipc_port });
}

// Zig tip: a pid file holds the number of the process and a line break. It is written by the process that knows the number
// (the machine in the foreground, or the starter that just spawned it) and removed when the machine stops, so an init system
// can find the machine to stop it. A failure to write it is not an error: the machine works without.
fn writePid(io: Io, gpa: std.mem.Allocator, cfg: Config, pid: u64) void {
    const path = pidPath(gpa, cfg) catch return;
    defer gpa.free(path);
    const text = std.fmt.allocPrint(gpa, "{d}\n", .{pid}) catch return;
    defer gpa.free(text);
    Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = text }) catch {};
}

// Zig tip: `removePid` relies on the same Zig feature as `writePid` above: see the tip there.
fn removePid(io: Io, gpa: std.mem.Allocator, cfg: Config) void {
    const path = pidPath(gpa, cfg) catch return;
    defer gpa.free(path);
    Io.Dir.cwd().deleteFile(io, path) catch {};
}

// Zig tip: a plain function: the types of the parameters and of the result are written out, and Zig has no default
// arguments, so a call always passes every parameter.
fn onSignal(_: std.posix.SIG) callconv(.c) void {
    stop_flag.store(true, .release);
}

// Zig tip: a signal handler may only do very little, so it sets an atomic flag and nothing else; the loop that waits for the
// machine reads the flag and does the real work. `SIGHUP` is ignored: the machine must not stop when the terminal that
// started it closes.
fn installSignals() void {
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) return;
    const term: std.posix.Sigaction = .{ .handler = .{ .handler = onSignal }, .mask = std.posix.sigemptyset(), .flags = 0 };
    std.posix.sigaction(std.posix.SIG.TERM, &term, null);
    std.posix.sigaction(std.posix.SIG.INT, &term, null);
    const ign: std.posix.Sigaction = .{ .handler = .{ .handler = std.posix.SIG.IGN }, .mask = std.posix.sigemptyset(), .flags = 0 };
    std.posix.sigaction(std.posix.SIG.HUP, &ign, null);
}

// Zig tip: `a orelse b` unwraps an optional: the value when there is one, else `b` (which may be `return` or `continue`,
// leaving the function or the loop).
fn anyMachineRuns() bool {
    for (&machine.machines) |*slot| {
        const m = slot.* orelse continue;
        if (!m.stopping.load(.acquire)) return true;
    }
    return false;
}

// Zig tip: the machine is started "embedded" (its threads run on their own and `serve` returns), so this function can wait:
// it sleeps in short steps until a stop is asked or the machine ended by itself (`vm.stop`), then shuts the doors. The log of
// an embedded machine goes where `embed_log` points, here the log file. `catch return` gives up quietly: a service has no
// terminal to tell.
/// Run the machine in this process until it is stopped; the log goes to `<runtime>/eve-<domain>-<ipc_port>.log`.
pub fn runForeground(io: Io, gpa: std.mem.Allocator, config_path: ?[]const u8, report: ?*const fn (state: u32) void) u8 {
    const cfg = config.loadConfig(io, gpa, config_path orelse "eve.cfg");
    const log = daemon.logPath(gpa, cfg) catch return 1;
    const log_file = Io.Dir.cwd().createFile(io, log, .{}) catch null;
    const wbuf = gpa.alloc(u8, 4096) catch return 1;
    const fw = gpa.create(Io.File.Writer) catch return 1;
    if (log_file) |f| {
        fw.* = .initStreaming(f, io, wbuf);
        machine.embed_log = &fw.interface;
    }
    installSignals();
    var sink = Io.Writer.Allocating.init(gpa);
    defer sink.deinit();
    const out: *Io.Writer = if (log_file != null) &fw.interface else &sink.writer;
    const code = machine.serve(io, gpa, out, cfg, true, true, true) catch return 1;
    if (code != 0) {
        out.flush() catch {};
        return code;
    }
    writePid(io, gpa, cfg, currentPid());
    if (report) |r| r(4);
    while (!stop_flag.load(.acquire) and anyMachineRuns()) Io.sleep(io, .fromMilliseconds(200), .awake) catch {};
    if (report) |r| r(3);
    for (&machine.machines) |*slot| {
        const m = slot.* orelse continue;
        machine.shutdown(m);
    }
    Io.sleep(io, .fromMilliseconds(300), .awake) catch {};
    removePid(io, gpa, cfg);
    out.flush() catch {};
    return 0;
}

// Zig tip: `switch` must cover every value of what it tests (or have `else`); the compiler checks it, so a new case can not
// be forgotten. A prong can be an expression that gives the result.
fn currentPid() u64 {
    return switch (builtin.os.tag) {
        .windows => std.os.windows.GetCurrentProcessId(),
        .wasi => 0,
        else => @intCast(std.c.getpid()),
    };
}

// ---- Windows: the Service Control Manager ---------------------------------------------------------------------------------

const win = if (builtin.os.tag == .windows) struct {
    // Zig tip: a `struct` groups named fields, and may hold functions (its methods) and constants; a field with a default
    // value may be left out when a value is made with `.{ ... }`.
    const SERVICE_STATUS = extern struct {
        dwServiceType: u32,
        dwCurrentState: u32,
        dwControlsAccepted: u32,
        dwWin32ExitCode: u32,
        dwServiceSpecificExitCode: u32,
        dwCheckPoint: u32,
        dwWaitHint: u32,
    };
    const ServiceMainFn = *const fn (argc: u32, argv: ?[*]?[*:0]u16) callconv(.winapi) void;
    const HandlerFn = *const fn (control: u32, event_type: u32, data: ?*anyopaque, ctx: ?*anyopaque) callconv(.winapi) u32;
    // Zig tip: `TableEntry` relies on the same Zig feature as `SERVICE_STATUS` above: see the tip there.
    const TableEntry = extern struct { name: ?[*:0]const u16, proc: ?ServiceMainFn };
    extern "advapi32" fn StartServiceCtrlDispatcherW(table: [*]const TableEntry) callconv(.winapi) i32;
    extern "advapi32" fn RegisterServiceCtrlHandlerExW(name: [*:0]const u16, handler: HandlerFn, ctx: ?*anyopaque) callconv(.winapi) ?*anyopaque;
    extern "advapi32" fn SetServiceStatus(handle: ?*anyopaque, status: *const SERVICE_STATUS) callconv(.winapi) i32;
    extern "kernel32" fn GetLastError() callconv(.winapi) u32;

    const service_name = std.unicode.utf8ToUtf16LeStringLiteral("eve");
    const SERVICE_WIN32_OWN_PROCESS: u32 = 0x10;
    const SERVICE_STOPPED: u32 = 1;
    const SERVICE_START_PENDING: u32 = 2;
    const SERVICE_STOP_PENDING: u32 = 3;
    const SERVICE_RUNNING: u32 = 4;
    const SERVICE_ACCEPT_STOP_SHUTDOWN: u32 = 0x1 | 0x4;
    const ERROR_FAILED_SERVICE_CONTROLLER_CONNECT: u32 = 1063;

    var handle: ?*anyopaque = null;
    var g_io: Io = undefined;
    var g_gpa: std.mem.Allocator = undefined;
    var g_config: ?[]const u8 = null;
    var g_exit: u8 = 0;
    /// When set, the service supervises this program (evedb) instead of running the machine.
    var g_child: ?[]const []const u8 = null;
    var g_child_log: []const u8 = "";

    // Zig tip: `setState` relies on the same Zig feature as `onSignal` above: see the tip there.
    fn setState(state: u32, exit_code: u32) void {
        const accepted: u32 = if (state == SERVICE_RUNNING) SERVICE_ACCEPT_STOP_SHUTDOWN else 0;
        const st: SERVICE_STATUS = .{
            .dwServiceType = SERVICE_WIN32_OWN_PROCESS,
            .dwCurrentState = state,
            .dwControlsAccepted = accepted,
            .dwWin32ExitCode = exit_code,
            .dwServiceSpecificExitCode = 0,
            .dwCheckPoint = 0,
            .dwWaitHint = if (state == SERVICE_START_PENDING or state == SERVICE_STOP_PENDING) 5000 else 0,
        };
        _ = SetServiceStatus(handle, &st);
    }

    // Zig tip: `report` relies on the same Zig feature as `onSignal` above: see the tip there.
    fn report(state: u32) void {
        setState(state, 0);
    }

    // Zig tip: the Service Control Manager calls this function on one of its threads with a stop (1), an interrogate (4) or a
    // shutdown (5). It only sets the flag the machine loop watches, and answers NO_ERROR (0); anything else is "not
    // implemented" (120).
    fn control(code: u32, _: u32, _: ?*anyopaque, _: ?*anyopaque) callconv(.winapi) u32 {
        switch (code) {
            1, 5 => {
                stop_flag.store(true, .release);
                return 0;
            },
            4 => return 0,
            else => return 120,
        }
    }

    // Zig tip: `serviceMain` relies on the same Zig feature as `onSignal` above: see the tip there.
    fn serviceMain(_: u32, _: ?[*]?[*:0]u16) callconv(.winapi) void {
        handle = RegisterServiceCtrlHandlerExW(service_name, control, null);
        if (handle == null) return;
        setState(SERVICE_START_PENDING, 0);
        g_exit = if (g_child) |argv| supervise(g_io, g_gpa, argv, g_child_log, report) else runForeground(g_io, g_gpa, g_config, report);
        setState(SERVICE_STOPPED, g_exit);
    }

    // Zig tip: `dispatch` relies on the same Zig feature as `onSignal` above: see the tip there.
    /// Hand this process to the Service Control Manager. True when it was started by it (and the service has ended);
    /// false when it was started from a console.
    fn dispatch(io: Io, gpa: std.mem.Allocator, config_path: ?[]const u8) bool {
        g_io = io;
        g_gpa = gpa;
        g_config = config_path;
        const table = [_]TableEntry{
            .{ .name = service_name, .proc = serviceMain },
            .{ .name = null, .proc = null },
        };
        if (StartServiceCtrlDispatcherW(&table) != 0) return true;
        return GetLastError() != ERROR_FAILED_SERVICE_CONTROLLER_CONNECT;
    }
} else struct {};

// ---- evedb as a service: `eve -s -db --serve evedb.cfg` (evedb README section 11) ----------------------------------------------

// Zig tip: `std.process.executableDirPathAlloc` gives the folder of this program, so `eve` finds `evedb` beside it in `bin/`.
// `exeFileExt` is `.exe` on Windows and empty elsewhere, known when the program is compiled.
/// The path of `evedb` beside this program.
pub fn evedbPath(io: Io, gpa: std.mem.Allocator) ![]u8 {
    const dir = try std.process.executableDirPathAlloc(io, gpa);
    return std.fmt.allocPrint(gpa, "{s}{c}evedb{s}", .{ dir, std.fs.path.sep, builtin.target.exeFileExt() });
}

// Zig tip: `evedbLog` relies on the same Zig feature as `pidPath` above: see the tip there.
/// Where the log of evedb started as a service goes: `<runtime>/evedb-<name of the configuration>.log`.
pub fn evedbLog(gpa: std.mem.Allocator, config_path: []const u8) ![]u8 {
    return std.fmt.allocPrint(gpa, "{s}/evedb-{s}.log", .{ config.runtime_dir, std.fs.path.stem(config_path) });
}

var child_done = std.atomic.Value(bool).init(false);

// Zig tip: `f() catch x` uses `x` when `f` fails; `catch {}` drops the error on purpose. Zig refuses to compile an error
// that nobody handles.
fn waitChild(io: Io, child: *std.process.Child) void {
    _ = child.wait(io) catch {};
    child_done.store(true, .release);
}

// Zig tip: a service that runs another program watches two things at once: the stop request (a flag set by the Service
// Control Manager or a signal) and the end of the child (a thread blocks in `wait` and sets another flag). The main loop
// sleeps in short steps until one of the flags is set; on a stop it kills the child.
/// Run `argv` as the work of the service, its output in the log, until a stop is asked or it ends by itself.
pub fn supervise(io: Io, _: std.mem.Allocator, argv: []const []const u8, log: []const u8, report: ?*const fn (state: u32) void) u8 {
    const log_file = Io.Dir.cwd().createFile(io, log, .{}) catch null;
    const sink: std.process.SpawnOptions.StdIo = if (log_file) |f| .{ .file = f } else .ignore;
    var child = std.process.spawn(io, .{ .argv = argv, .stdin = .ignore, .stdout = sink, .stderr = sink, .create_no_window = true }) catch return 69;
    if (log_file) |f| f.close(io);
    installSignals();
    const waiter = std.Thread.spawn(.{}, waitChild, .{ io, &child }) catch return 69;
    if (report) |r| r(4);
    while (!stop_flag.load(.acquire) and !child_done.load(.acquire)) Io.sleep(io, .fromMilliseconds(200), .awake) catch {};
    if (report) |r| r(3);
    if (!child_done.load(.acquire)) child.kill(io);
    waiter.join();
    return 0;
}

// Zig tip: from a console, evedb is started detached (no window, its own process group, our standard handles not inherited),
// and `eve` waits until the log says on which ports it listens. The ready line is written by evedb itself, so this works for
// any port of the configuration, including 0.
/// Start evedb in a process of its own and end when it is ready; silent when all went well.
pub fn startEvedbDetached(io: Io, gpa: std.mem.Allocator, argv: []const []const u8, log: []const u8, err: *Io.Writer) !u8 {
    const log_file = Io.Dir.cwd().createFile(io, log, .{}) catch {
        try err.print("eve: cannot write the log {s}\n", .{log});
        return 73;
    };
    daemon.releaseStdHandles();
    _ = std.process.spawn(io, .{
        .argv = argv,
        .stdin = .ignore,
        .stdout = .{ .file = log_file },
        .stderr = .{ .file = log_file },
        .create_no_window = true,
        .pgid = if (builtin.os.tag == .windows) null else 0,
    }) catch |e| {
        log_file.close(io);
        try err.print("eve: cannot start {s}: {s} (build it: cd evedb && zig build -p ..)\n", .{ argv[0], @errorName(e) });
        return 69;
    };
    log_file.close(io);
    var tries: usize = 0;
    while (tries < 100) : (tries += 1) {
        Io.sleep(io, .fromMilliseconds(100), .awake) catch {};
        const text = Io.Dir.cwd().readFileAlloc(io, log, gpa, .limited(1 << 16)) catch continue;
        if (std.mem.indexOf(u8, text, "on port") != null) return 0;
        if (std.mem.indexOf(u8, text, "runs already") != null) {
            try err.print("{s}", .{text});
            return 75;
        }
        if (std.mem.indexOf(u8, text, "evedb: ") != null and std.mem.indexOf(u8, text, "cannot") != null) {
            try err.print("{s}", .{text});
            return 69;
        }
    }
    const text = Io.Dir.cwd().readFileAlloc(io, log, gpa, .limited(4096)) catch "";
    try err.print("eve: evedb did not say it was ready within 10 seconds; its log {s} says:\n{s}\n", .{ log, text });
    return 69;
}

// Zig tip: `runEvedb` relies on the same Zig feature as `pidPath` above: see the tip there.
/// `eve -s -db --serve evedb.cfg` (also `eve -s db serve evedb.cfg`): evedb as a service, silent.
pub fn runEvedb(io: Io, gpa: std.mem.Allocator, config_path: []const u8, environ_foreground: bool, err: *Io.Writer) !u8 {
    const exe = try evedbPath(io, gpa);
    const argv = try gpa.dupe([]const u8, &.{ exe, "serve", "--config", config_path });
    const log = try evedbLog(gpa, config_path);
    if (builtin.os.tag == .windows and !environ_foreground) {
        win.g_child = argv;
        win.g_child_log = log;
        if (win.dispatch(io, gpa, null)) return win.g_exit;
    }
    if (environ_foreground) return supervise(io, gpa, argv, log, null);
    return startEvedbDetached(io, gpa, argv, log, err);
}

// Zig tip: `run` relies on the same Zig feature as `writePid` above: see the tip there.
/// `eve -s [file.cfg]`: start the machine as a service; returns the exit code of the command.
pub fn run(io: Io, gpa: std.mem.Allocator, config_path: ?[]const u8, environ_foreground: bool, err: *Io.Writer) !u8 {
    if (builtin.os.tag == .windows and !environ_foreground) {
        // started by the Service Control Manager, this call returns when the service has stopped
        if (win.dispatch(io, gpa, config_path)) return win.g_exit;
    }
    if (environ_foreground) return runForeground(io, gpa, config_path, null);
    // from a console or a shell: the machine runs in a process of its own and this command ends, silent when all went well
    const cfg = config.loadConfig(io, gpa, config_path orelse "eve.cfg");
    var sink = Io.Writer.Allocating.init(gpa);
    defer sink.deinit();
    const code = try daemon.startDetached(io, gpa, &sink.writer, cfg, config_path);
    if (code != 0) try err.writeAll(sink.written());
    return code;
}

// Zig tip: a `test` block is compiled only by `zig build test`; `try std.testing.expect…` fails the test, with the values,
// when a check is false.
test "the pid file and the log are named after the machine" {
    const cfg: Config = .{};
    const gpa = std.testing.allocator;
    config.runtime_dir = "/run";
    const pid = try pidPath(gpa, cfg);
    defer gpa.free(pid);
    try std.testing.expectEqualStrings("/run/eve-localhost-4042.pid", pid);
}
