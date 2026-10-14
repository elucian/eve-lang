//! The machine as a process: `stop`, the machine that `evevm` starts in its own process, and the user interface (`-u`).
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const vm = @import("vm.zig");
// Zig tip: `const ok = wire.ok;` gives a function of another file a short local name. It copies nothing: the
// name points to the same function, and calls read as they did before the code was split into files.
const config = @import("evecm").config;
const wire = @import("evecm").wire;

const Config = config.Config;
const loadConfig = config.loadConfig;
const parseConfig = config.parseConfig;
const exit_unavailable = config.exit_unavailable;
const exit_running = config.exit_running;
const exit_usage = config.exit_usage;
const message = wire.message;
const contentType = wire.contentType;
const safePath = wire.safePath;
const httpCall = wire.httpCall;
const machine = @import("machine.zig");
const client = @import("client.zig");

// ---- stop, the machine as its own process (evevm) and the user interface (-u) ---------------------------------------


// Zig tip: `for (&machines) |*slot|` walks the array by pointer; `slot.* orelse continue` reads the optional behind the
// pointer and skips a place that is empty. The function does three things in order of preference, and returns after the
// first that finds something to stop: the doors of this process, then a machine in another process.
/// `stop`: close the doors that this process opened and tell the scripts to stop, without leaving the prompt. When this
/// process has no door open, stop the machine of another process that answers (the one that `evevm` started).
pub fn stopMachines(io: Io, gpa: std.mem.Allocator, out: *Io.Writer, config_path: []const u8) !u8 {
    var closed: usize = 0;
    for (&machine.machines) |*slot| {
        const m = slot.* orelse continue;
        if (m.stopping.load(.acquire)) continue;
        machine.shutdown(m);
        closed += 1;
    }
    if (closed > 0) {
        try out.writeAll("stop: closed the doors of this process and told the scripts to stop\n");
        return 0;
    }
    const cfg = loadConfig(io, gpa, config_path);
    var name: []const u8 = "";
    if (client.send(io, gpa, cfg, .{}, message(gpa, "vm.stop", null), &name) != null) {
        try out.print("stop: stopped the machine of ipc {s}:{d} (http {s}:{d}) and its scripts\n", .{ cfg.domain, cfg.ipc_port, cfg.http_host, cfg.http_port });
        return 0;
    }
    try out.writeAll("stop: nothing to stop, no door is open here and no machine answers\n");
    return exit_unavailable;
}

/// Where the machine started by `evevm` writes its log: `<runtime>/eve-<domain>-<ipc_port>.log`.
pub fn logPath(gpa: std.mem.Allocator, cfg: Config) ![]u8 {
    return std.fmt.allocPrint(gpa, "{s}/eve-{s}-{d}.log", .{ config.runtime_dir, cfg.domain, cfg.ipc_port });
}

// Zig tip: `std.process.spawn` starts another program. `.stdin = .ignore` connects it to the null device, and a
// `.file` gives it an open file as its output: the machine has no terminal, so its log goes to a file. With
// `create_no_window` Windows gives the child no console window of its own, and it goes on running after this program
// has ended. The result is a `Child`; this function does not wait for it, because the machine is meant to stay.
/// Start `eve --listen --serve` as a new process, wait until its IPC door answers, and report. The machine runs on
/// its own: the prompt of the system comes back.
pub fn startDetached(io: Io, gpa: std.mem.Allocator, out: *Io.Writer, cfg: Config, config_path: ?[]const u8) !u8 {
    var name: []const u8 = "";
    const ipc_only: client.Cmd = .{ .local = true };
    const ping = message(gpa, "vm.ping", null);
    if (client.send(io, gpa, cfg, ipc_only, ping, &name) != null) {
        try out.print("evevm: already running (ipc {s}:{d})\n", .{ cfg.domain, cfg.ipc_port });
        return exit_running;
    }
    var exe_buf: [std.fs.max_path_bytes]u8 = undefined;
    const exe_len = std.process.executablePath(io, &exe_buf) catch {
        try out.writeAll("evevm: cannot find the path of this program\n");
        return exit_unavailable;
    };
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(gpa, &.{ try gpa.dupe(u8, exe_buf[0..exe_len]), "--listen", "--serve" });
    if (config_path) |p| try argv.appendSlice(gpa, &.{ "-s", p });
    const log = try logPath(gpa, cfg);
    const log_file: ?Io.File = Io.Dir.cwd().createFile(io, log, .{}) catch null;
    const sink: std.process.SpawnOptions.StdIo = if (log_file) |f| .{ .file = f } else .ignore;
    _ = std.process.spawn(io, .{
        .argv = argv.items,
        .stdin = .ignore,
        .stdout = sink,
        .stderr = sink,
        .create_no_window = true,
    }) catch |e| {
        try out.print("evevm: cannot start the machine: {s}\n", .{@errorName(e)});
        return exit_unavailable;
    };
    if (log_file) |f| f.close(io); // the machine has its own handle of the file
    var tries: usize = 0;
    while (tries < 100) : (tries += 1) {
        if (client.send(io, gpa, cfg, ipc_only, ping, &name) != null) {
            try out.print("evevm: the machine runs in its own process (ipc {s}:{d}, http http://{s}:{d})\n", .{ cfg.domain, cfg.ipc_port, cfg.http_host, cfg.http_port });
            try out.print("evevm: its log is {s}; stop it with: eve stop (or evevm stop)\n", .{log});
            return 0;
        }
        Io.sleep(io, .fromMilliseconds(100), .awake) catch {};
    }
    try out.writeAll("evevm: the machine did not answer within 10 seconds\n");
    const tail = Io.Dir.cwd().readFileAlloc(io, log, gpa, .limited(2048)) catch "";
    if (tail.len > 0) try out.print("evevm: its log says:\n{s}\n", .{tail});
    return exit_unavailable;
}

pub const daemon_usage =
    \\evevm: start the Eve machine (both doors, as eve --listen --serve) in a new process; the system prompt comes back
    \\usage: evevm [start|stop|restart|status] [-s file.cfg]
    \\
;

// Zig tip: the program decides what to do from its own name (`evevm` or `eve`) and from a word; `eql` is a comparison
// of two texts. `orelse 0` turns "the machine options did not handle it" into a plain success. A `restart` is a `stop`
// followed by a wait until nobody answers, then a `start`.
/// The command `evevm [start|stop|restart|status] [-s file.cfg]`; returns the exit code.
pub fn daemonMain(io: Io, gpa: std.mem.Allocator, out: *Io.Writer, argv: []const []const u8) !u8 {
    var word: []const u8 = "start";
    var config_path: ?[]const u8 = null;
    var i: usize = 0;
    while (i < argv.len) : (i += 1) {
        const a = argv[i];
        if (std.mem.eql(u8, a, "-s") and i + 1 < argv.len) {
            i += 1;
            config_path = argv[i];
        } else if (std.mem.eql(u8, a, "-h") or std.mem.eql(u8, a, "--help")) {
            try out.writeAll(daemon_usage);
            return 0;
        } else if (std.mem.eql(u8, a, "start") or std.mem.eql(u8, a, "stop") or std.mem.eql(u8, a, "restart") or std.mem.eql(u8, a, "status")) {
            word = a;
        } else {
            try out.print("evevm: unexpected {s}\n{s}", .{ a, daemon_usage });
            return exit_usage;
        }
    }
    const cfg = loadConfig(io, gpa, config_path orelse "eve.cfg");
    if (std.mem.eql(u8, word, "start")) return try startDetached(io, gpa, out, cfg, config_path);
    if (std.mem.eql(u8, word, "restart")) {
        _ = try client.handle(io, gpa, out, .{ .serve = true, .word = "stop", .config = config_path }, false);
        var name: []const u8 = "";
        var tries: usize = 0;
        while (tries < 50 and client.send(io, gpa, cfg, .{ .local = true }, message(gpa, "vm.ping", null), &name) != null) : (tries += 1) {
            Io.sleep(io, .fromMilliseconds(100), .awake) catch {};
        }
        return try startDetached(io, gpa, out, cfg, config_path);
    }
    return (try client.handle(io, gpa, out, .{ .serve = true, .word = word, .config = config_path }, false)) orelse 0;
}

// Zig tip: a failed call to `spawn` or `wait` is not worth stopping for here, so the result is a plain `bool`:
// "the helper program ran and ended". `&.{ ... }` with a value that is known only at run time (`url`) is an array
// built on the stack, which `spawn` reads and does not keep.
/// Run a helper program with no window and no input or output, and wait for it to end.
pub fn runQuiet(io: Io, argv: []const []const u8) bool {
    var child = std.process.spawn(io, .{
        .argv = argv,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
        .create_no_window = true,
    }) catch return false;
    _ = child.wait(io) catch return false;
    return true;
}

/// `-u`: open the user interface, the web page of the HTTP door. If the HTTP door already answers, the interface is
/// open and nothing more happens; otherwise the machine is started in its own process and the browser is opened.
pub fn openUi(io: Io, gpa: std.mem.Allocator, out: *Io.Writer, config_path: ?[]const u8) !u8 {
    const cfg = loadConfig(io, gpa, config_path orelse "eve.cfg");
    const url = try std.fmt.allocPrint(gpa, "http://{s}:{d}/", .{ cfg.http_host, cfg.http_port });
    const ping = message(gpa, "vm.ping", null);
    if (httpCall(io, gpa, cfg.http_host, cfg.http_port, ping) != null) {
        try out.print("eve: the user interface is already open: {s}\n", .{url});
        return 0;
    }
    const code = try startDetached(io, gpa, out, cfg, config_path);
    if (code == exit_running) {
        try out.writeAll("eve: a machine runs without the HTTP door; restart it with: evevm restart\n");
        return code;
    }
    if (code != 0) return code;
    var tries: usize = 0;
    while (tries < 50 and httpCall(io, gpa, cfg.http_host, cfg.http_port, ping) == null) : (tries += 1) {
        Io.sleep(io, .fromMilliseconds(100), .awake) catch {};
    }
    const index = try std.fmt.allocPrint(gpa, "{s}/index.html", .{cfg.web});
    if (Io.Dir.cwd().readFileAlloc(io, index, gpa, .limited(1))) |_| {} else |e| {
        if (e == error.FileNotFound) try out.print("eve: note: {s} does not exist, the page will be 404\n", .{index});
    }
    const opened = switch (builtin.os.tag) {
        .windows => runQuiet(io, &.{ "cmd.exe", "/c", "start", "", url }),
        .macos => runQuiet(io, &.{ "open", url }),
        else => runQuiet(io, &.{ "xdg-open", url }),
    };
    if (opened) {
        try out.print("eve: the user interface is open: {s}\n", .{url});
    } else {
        try out.print("eve: the machine runs; open {s} in a browser\n", .{url});
    }
    return 0;
}

// Zig tip: a test of the pure parts needs no network: the path check and the configuration reader are plain functions
// of text. `std.testing.expect` fails the test when the value is false.
test "web paths stay below the web folder" {
    try std.testing.expect(safePath("/index.html"));
    try std.testing.expect(safePath("/css/style.css"));
    try std.testing.expect(!safePath("/../eve.cfg"));
    try std.testing.expect(!safePath("/a/..\\b"));
    try std.testing.expect(!safePath("index.html"));
    try std.testing.expectEqualStrings("text/css; charset=utf-8", contentType("/css/style.css"));
}

// Zig tip: a multi-line string literal (lines that start with `\\`) holds a whole file in the test, with no escapes.
// `expectEqual` compares numbers; the ports show that a `**` comment at the end of a line is not part of the value.
test "eve.cfg: keys of the machine, comments and unknown keys" {
    const cfg = parseConfig(
        \\# configuration of a test
        \\core_db = "db/local.db"
        \\** database "check" = "evedb://test/check.duckdb"
        \\domain = "localhost"
        \\ipc_port = 4300 ** the IPC door
        \\http_port = 8300
        \\web = "web"
    );
    try std.testing.expectEqual(@as(u16, 4300), cfg.ipc_port);
    try std.testing.expectEqual(@as(u16, 8300), cfg.http_port);
    try std.testing.expectEqualStrings("web", cfg.web);
    try std.testing.expect(cfg.remote == null);
}
