//! The Eve machine, client side: `-loc`, `-rem`, `--listen status|stop`, `--serve status|stop`. It sends one
//! JSON-RPC message to a machine and prints the answer, or opens the doors in this process (zig).
const std = @import("std");
const Io = std.Io;
const vm = @import("vm.zig");
// Zig tip: `const ok = wire.ok;` gives a function of another file a short local name. It copies nothing: the
// name points to the same function, and calls read as they did before the code was split into files.
const config = @import("evecm").config;
const wire = @import("evecm").wire;

const Config = config.Config;
const loadConfig = config.loadConfig;
const readConfig = config.readConfig;
const exit_unavailable = config.exit_unavailable;
const exit_usage = config.exit_usage;
const socketPath = config.socketPath;
const fail = wire.fail;
const message = wire.message;
const ipcCall = wire.ipcCall;
const httpCall = wire.httpCall;
const machine = @import("machine.zig");

// ---- the client side -----------------------------------------------------------------------------------------

// Zig tip: `?[]const u8 = null` is an optional text that is absent by default: `-loc` with no port leaves
// `local_port` null, and the configuration keeps its own port.
/// What the command line asked for (built by `main.zig` from the options).
pub const Cmd = struct {
    listen: bool = false,
    serve: bool = false,
    /// `start`, `stop`, `restart` or `status` after `--listen` or `--serve`; empty is `start` (D-169).
    word: []const u8 = "",
    local: bool = false,
    local_port: ?[]const u8 = null,
    remote: bool = false,
    remote_addr: ?[]const u8 = null,
    config: ?[]const u8 = null,
    /// The script of `-x file.eve` and its arguments.
    script: ?[]const u8 = null,
    script_args: []const []const u8 = &.{},
};

// Zig tip: a struct with one field gives a name to a value: `?Answer` reads better than `?std.json.Value`, where null
// (nobody answered) and the JSON `null` would look alike.
/// The answer to a call: the JSON `result` of the message.
pub const Answer = struct { result: std.json.Value };

// Zig tip: the outcome is an optional, not an error: `Answer` when the machine answered, `null` when nobody did, and
// the caller prints the message that fits its option. `remote_name: *[]const u8` is an out-parameter: the function
// writes the address it tried through the pointer (`remote_name.* = addr`). `std.json.parseFromSliceLeaky` allocates
// the parsed tree in `gpa` and never frees it, which is fine for a program that sends one command and exits.
/// Send `request` to the machine the options point to: `-rem` the HTTP door of that address, `-loc` the IPC door, and
/// without option the IPC door and then the HTTP door of `localhost`.
pub fn send(io: Io, gpa: std.mem.Allocator, cfg: Config, cmd: Cmd, request: []const u8, remote_name: *[]const u8) ?Answer {
    var reply: ?[]const u8 = null;
    if (cmd.remote) {
        const addr = cmd.remote_addr orelse cfg.remote orelse "";
        remote_name.* = addr;
        const colon = std.mem.lastIndexOfScalar(u8, addr, ':') orelse addr.len;
        const port = if (colon < addr.len) std.fmt.parseInt(u16, addr[colon + 1 ..], 10) catch 0 else cfg.http_port;
        if (addr.len > 0 and port != 0) reply = httpCall(io, gpa, addr[0..colon], port, request);
    } else {
        const socket = socketPath(gpa, cfg) catch return null;
        reply = ipcCall(io, gpa, socket, request);
        if (reply == null and !cmd.local) reply = httpCall(io, gpa, cfg.http_host, cfg.http_port, request);
    }
    const body = reply orelse return null;
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, gpa, body, .{}) catch return null;
    if (parsed != .object) return null;
    return .{ .result = parsed.object.get("result") orelse .null };
}

// Zig tip: `std.json.Value` is a tagged union: `v == .object` tests the tag, and `v.object` is then safe to use.
// These four small readers give a neutral value (null, "", 0, "off") when the answer has another shape.
pub fn field(v: std.json.Value, name: []const u8) std.json.Value {
    return if (v == .object) (v.object.get(name) orelse .null) else .null;
}

pub fn text(v: std.json.Value) []const u8 {
    return if (v == .string) v.string else "";
}

pub fn number(v: std.json.Value) i64 {
    return if (v == .integer) v.integer else 0;
}

pub fn listening(v: std.json.Value) []const u8 {
    return if (v == .bool and v.bool) "listening" else "off";
}

// Zig tip: `{d:0>2}` pads a number with zeros to two digits. `@divTrunc` and `@mod` are the integer division and
// remainder; Zig asks for them by name on signed numbers because `/` and `%` are not defined for negative values.
/// Write a duration in milliseconds as `850 ms`, `12 s`, `3 min 05 s` or `2 h 05 min`.
pub fn writeDuration(out: *Io.Writer, ms: i64) !void {
    const s = @divTrunc(@max(ms, 0), 1000);
    if (s < 1) return out.print("{d} ms", .{@max(ms, 0)});
    if (s < 60) return out.print("{d} s", .{s});
    if (s < 3600) return out.print("{d} min {d:0>2} s", .{ @divTrunc(s, 60), @mod(s, 60) });
    return out.print("{d} h {d:0>2} min", .{ @divTrunc(s, 3600), @mod(@divTrunc(s, 60), 60) });
}

// Zig tip: the first four lines are the answer of the first version of `--serve status` and keep their form; the lines
// after them need the fields that only `vm.stat` sends (`uptime_ms`), so an older machine prints just the four.
// `field(r, "x") == .integer` tests the tag of a JSON value before it is read.
/// Print the answer of `vm.stat`: the doors, then what the machine has done and what it is doing.
pub fn printMachine(out: *Io.Writer, r: std.json.Value) !void {
    try out.print("machine: {s} ipc={d} http={d}\nipc: {s}\nhttp: {s}\nruns: {d}\n", .{
        text(field(r, "domain")),
        number(field(r, "ipc_port")),
        number(field(r, "http_port")),
        listening(field(r, "ipc")),
        listening(field(r, "http")),
        number(field(r, "runs")),
    });
    if (field(r, "uptime_ms") != .integer) return;
    try out.print("requests: {d}\nuptime: ", .{number(field(r, "requests"))});
    try writeDuration(out, number(field(r, "uptime_ms")));
    const running = text(field(r, "running"));
    if (running.len > 0) {
        try out.print("\ndoing: running {s} for ", .{running});
        try writeDuration(out, number(field(r, "running_ms")));
    } else {
        try out.writeAll("\ndoing: idle, waiting for requests");
    }
    if (field(r, "http") == .bool and field(r, "http").bool) {
        try out.print("\nweb: folder {s} at http://{s}:{d}", .{ text(field(r, "web")), text(field(r, "http_host")), number(field(r, "http_port")) });
    }
    const parts = field(r, "parts");
    if (parts == .array) {
        try out.writeAll("\nparts:");
        for (parts.array.items) |p| try out.print(" {s}", .{text(p)});
    }
    try out.writeByte('\n');
}

// Zig tip: a struct literal for a type with all defaults, `Cmd{}`, is "no option given": `send` then tries the IPC
// door and the HTTP door of the configuration. The whole function only reads: it opens no door and starts nothing.
/// The part of `status` about the machine: the configuration file, the doors, and whether a machine answers on them.
pub fn machineStatus(io: Io, gpa: std.mem.Allocator, out: *Io.Writer, config_path: []const u8) !void {
    const found = readConfig(io, gpa, config_path);
    const cfg = found orelse Config{};
    if (found != null) {
        try out.print("configuration: {s} (loaded)\n", .{config_path});
    } else {
        try out.print("configuration: {s} not found, the defaults are in use\n", .{config_path});
    }
    try out.print("  domain={s} ipc_port={d} http_port={d} http_host={s} web={s} remote={s}\n", .{
        cfg.domain, cfg.ipc_port, cfg.http_port, cfg.http_host, cfg.web, cfg.remote orelse "-",
    });
    var name: []const u8 = "";
    const answer = send(io, gpa, cfg, .{}, message(gpa, "vm.stat", null), &name) orelse {
        try out.print("machine: not running (nothing answers on ipc {s} or on http {s}:{d})\n", .{ try socketPath(gpa, cfg), cfg.http_host, cfg.http_port });
        try out.writeAll("  start it with: eve --listen (ipc), eve --serve (http) or eve --listen --serve (both)\n");
        return;
    };
    try out.writeAll("machine: running\n");
    try printMachine(out, answer.result);
}

// Zig tip: `!u8` returns an exit code or a write error; `try out.print` passes the error up. One function chooses
// the message of each option, so the three ways to miss a machine are worded in one place.
pub fn gone(out: *Io.Writer, cmd: Cmd, name: []const u8) !u8 {
    if (cmd.remote) {
        try out.print("eve: no remote machine at {s}\n", .{name});
    } else if (cmd.local) {
        try out.writeAll("eve: no local machine\n");
    } else {
        try out.writeAll("eve: not running\n");
    }
    return exit_unavailable;
}

// Zig tip: `if (cond) |x| …` unwraps an optional in the condition; `?u8` is "an exit code, or nothing". Returning
// null here means "the machine options did not handle this command: run it the normal way". `try out.print` passes a
// write error up to the caller; the VM never expects one on a terminal.
/// Handle the options of the machine. Returns the exit code, or null when the command is an ordinary local one.
/// With `embed` a start opens the doors in threads and returns 0 at once (the caller shows the prompt); without it the
/// start waits for the doors, as a service does.
pub fn handle(io: Io, gpa: std.mem.Allocator, out: *Io.Writer, cmd: Cmd, embed: bool) !?u8 {
    var cfg = loadConfig(io, gpa, cmd.config orelse "eve.cfg");
    if (cmd.local_port) |p| cfg.ipc_port = std.fmt.parseInt(u16, p, 10) catch cfg.ipc_port;
    var name: []const u8 = "";
    const word = cmd.word;
    if (cmd.remote and (cmd.remote_addr orelse cfg.remote) == null) {
        try out.writeAll("eve: -rem needs an address (host:port) or the key remote in eve.cfg\n");
        return exit_usage;
    }
    // `--listen <word>` speaks to the machine through the IPC door only, as `-loc` does; `--serve <word>` tries the
    // IPC door, then the HTTP door (D-169)
    var via = cmd;
    if (cmd.listen) via.local = true;
    const door = cmd.listen or cmd.serve;
    const starting = door and (word.len == 0 or std.mem.eql(u8, word, "start") or std.mem.eql(u8, word, "restart"));
    if (starting) {
        // `--serve` alone is HTTP only; `--listen` is IPC only; both together open both doors
        var ipc = cmd.listen;
        var http = cmd.serve;
        if (std.mem.eql(u8, word, "restart")) {
            // a restart keeps the doors of the running machine: ask them before the stop; `--listen` may add IPC
            var probe = via;
            if (send(io, gpa, cfg, via, message(gpa, "vm.stat", null), &name)) |a| {
                const had_ipc = field(a.result, "ipc") == .bool and field(a.result, "ipc").bool;
                ipc = ipc or had_ipc;
                http = (field(a.result, "http") == .bool and field(a.result, "http").bool) or !ipc;
                _ = send(io, gpa, cfg, via, message(gpa, "vm.stop", null), &name);
                try out.print("eve: stopped, starting again\n", .{});
                // wait through IPC when the old machine had it: a refused TCP connection takes about 2 s on Windows
                probe.local = had_ipc;
            }
            var tries: usize = 0;
            while (tries < 50 and send(io, gpa, cfg, probe, message(gpa, "vm.ping", null), &name) != null) : (tries += 1) {
                Io.sleep(io, .fromMilliseconds(100), .awake) catch {};
            }
        }
        return try machine.serve(io, gpa, out, cfg, ipc, http, embed);
    }
    if (door and std.mem.eql(u8, word, "stop")) {
        _ = send(io, gpa, cfg, via, message(gpa, "vm.stop", null), &name) orelse return try gone(out, via, name);
        try out.writeAll("eve: stopped\n");
        return 0;
    }
    if (door and std.mem.eql(u8, word, "status")) {
        const a = send(io, gpa, cfg, via, message(gpa, "vm.stat", null), &name) orelse return try gone(out, via, name);
        try printMachine(out, a.result);
        return 0;
    }
    if (door) {
        try out.print("eve: {s} {s}: expected start, stop, restart or status\n", .{ if (cmd.listen) "--listen" else "--serve", word });
        return exit_usage;
    }
    if (cmd.script != null and (cmd.remote or cmd.local)) return try runVia(io, gpa, out, cfg, cmd);
    if (cmd.remote) {
        try out.writeAll("eve: -rem needs a command: -x file.eve or --serve status\n");
        return exit_usage;
    }
    return null;
}

// Zig tip: `path[if (...) |i| i + 1 else 0..]` slices from an index computed in place: `if` is an expression, so
// the base name of the file is cut without a temporary. `@intCast` narrows the exit code to `u8` after `@min`/`@max`
// kept it in 0..255, so the cast can never fail.
/// `-loc -x file` and `-rem addr -x file`: send the text of the script to the machine and print what comes back.
pub fn runVia(io: Io, gpa: std.mem.Allocator, out: *Io.Writer, cfg: Config, cmd: Cmd) !?u8 {
    const path = cmd.script.?;
    var name: []const u8 = "";
    const source = Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(16 << 20)) catch {
        try out.print("eve: cannot read {s}\n", .{path});
        return 66;
    };
    const base = path[if (std.mem.lastIndexOfAny(u8, path, "/\\")) |i| i + 1 else 0..];
    const request = message(gpa, "vm.run", .{ .name = base, .source = source, .args = cmd.script_args });
    const a = send(io, gpa, cfg, cmd, request, &name) orelse {
        // `-loc` without a machine runs the script by itself; `-rem` without a machine is a failure
        if (cmd.remote) return try gone(out, cmd, name);
        return null;
    };
    const r = a.result;
    try out.writeAll(text(field(r, "output")));
    try out.flush();
    const errors = text(field(r, "errors"));
    if (errors.len > 0) std.debug.print("{s}", .{errors});
    return @intCast(@max(0, @min(255, number(field(r, "status")))));
}
