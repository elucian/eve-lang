//! The Eve machine, server side (F-NET-02, D-162, `spec/library/machine.md`): a singleton that listens on two doors,
//! the IPC door (`--listen`, a Unix domain socket) and the HTTP door (`--serve`, the web folder and `POST /rpc`), or a
//! machine of one client on the stdio door (`--stdio`, channel.zig). The doors speak JSON-RPC 2.0 (evecm/wire.zig) and
//! run the methods of the machine API (`vm.ping`, `vm.stat`, `vm.run`, `vm.stop`, and on the lasting doors the
//! sessions, `vm.shell` and `vm.cancel`).
const std = @import("std");
const Io = std.Io;
const net = Io.net;
const vm = @import("vm.zig");
const channel = @import("channel.zig");
// Zig tip: `const ok = wire.ok;` gives a function of another file a short local name. It copies nothing: the
// name points to the same function, and calls read as they did before the code was split into files.
const config = @import("evecm").config;
const wire = @import("evecm").wire;

const Config = config.Config;
const exit_unavailable = config.exit_unavailable;
const exit_running = config.exit_running;
const exit_usage = config.exit_usage;
const socketPath = config.socketPath;
const ok = wire.ok;
const fail = wire.fail;
const message = wire.message;
const contentType = wire.contentType;
const safePath = wire.safePath;
const respond = wire.respond;
const readChunked = wire.readChunked;
const respondText = wire.respondText;
const ipcAlive = wire.ipcAlive;
const httpCall = wire.httpCall;

// ---- the machine (server side) -------------------------------------------------------------------------------

// Zig tip: a struct that threads share holds what they share. `std.atomic.Value(usize)` is a counter that several
// threads can add to without a lock; `Io.Mutex` is a lock (each call takes the `Io` handle in Zig 0.16). The two doors
// run in two threads, and the mutex makes the scripts run one at a time.
/// What both doors share: the configuration, the counters, the lock of the scripts and the log of the machine.
pub const Machine = struct {
    io: Io,
    cfg: Config,
    ipc: bool,
    http: bool,
    socket: []const u8,
    /// The terminal of the machine: one line per request (`note`).
    out: *Io.Writer,
    runs: std.atomic.Value(usize) = .init(0),
    /// Every request the doors answered (a `ping` or a `stat` counts too).
    requests: std.atomic.Value(usize) = .init(0),
    /// The clock (`millis`) when the machine started.
    started: i64 = 0,
    /// The script that runs now (null when idle) and when it began; both are guarded by `log_lock`.
    current: ?[]const u8 = null,
    current_since: i64 = 0,
    run_lock: Io.Mutex = .init,
    log_lock: Io.Mutex = .init,
    ipc_server: net.Server = undefined,
    http_server: net.Server = undefined,
    /// The doors live inside the REPL (`eve --serve` at a terminal, or the REPL commands `listen` and `serve`): a `stop`
    /// closes the doors and the REPL goes on, it does not end the process.
    embedded: bool = false,
    /// Set by `shutdown`, read by the accept loops: an error after the close is the end, not a failure to retry.
    stopping: std.atomic.Value(bool) = .init(false),
    /// No log lines (the stdio door: its standard output is the channel, and an IDE does not read a log).
    quiet: bool = false,
    /// The sessions that `vm.open` made (the lasting doors).
    sessions: channel.Sessions = .{},
};

// Zig tip: a `pub var` at file level is a global that other files may read. This one is written once, by `serve`, on
// the thread that starts the machine, before `main` reads it. The REPL of `main` looks at it to know that the doors
// are open in its own process and that the prompt must come back.
/// True after `serve` opened the doors inside this process and returned (the REPL is the foreground).
pub var embedded = false;

// Zig tip: the log of an embedded machine normally has a writer of its own, but the full-screen REPL needs the lines in
// its upper part, so `main` can point the log at the screen's writer (a global read at each line, set before any
// request can arrive). A null means "use the machine's own writer".
/// Where the log of an embedded machine goes instead of its own writer.
pub var embed_log: ?*Io.Writer = null;

// Zig tip: `comptime fmt: []const u8` makes the format a compile-time value, so `"eve: " ++ fmt ++ "\n"` joins the
// texts while compiling (`++` works only on comptime values). A `Writer` is not safe for two threads at once: the two
// doors log through the same terminal, so the lock makes each line whole.
/// Write one line of the log of the machine on its terminal.
pub fn note(m: *Machine, comptime fmt: []const u8, args: anytype) void {
    if (m.quiet) return;
    m.log_lock.lockUncancelable(m.io);
    defer m.log_lock.unlock(m.io);
    const out = if (m.embedded) embed_log orelse m.out else m.out;
    out.print("eve: " ++ fmt ++ "\n", args) catch return;
    out.flush() catch {};
}

// Zig tip: `Io.Timestamp.now(io, .awake)` reads a clock that only goes forward (it does not jump when the time of
// day is changed), the right one to measure a duration. `toMilliseconds` turns it into a number.
pub fn millis(io: Io) i64 {
    return Io.Timestamp.now(io, .awake).toMilliseconds();
}

// Zig tip: the per-request memory is an arena over `page_allocator`: everything the request allocates (the parsed
// JSON, the answer, the session of the script) is freed with one `deinit`, so a machine that runs for days does not
// grow. The process arena of `main` is never freed, so it must not be used for a server.
// Zig tip: `ch: ?*channel.Channel` is null on the HTTP door, where a reply is the whole answer; on a lasting door it is
// the connection, through which the machine also sends notifications. The methods that need it check it first.
/// One JSON-RPC message in, one message out (allocated in `a`). Sets `stop` when the method is `stop`. `door` is
/// `ipc`, `http` or `stdio`, for the log and `vm.stat`.
pub fn rpc(m: *Machine, a: std.mem.Allocator, door: []const u8, body: []const u8, stop: *bool, ch: ?*channel.Channel) []const u8 {
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, a, body, .{}) catch return fail(a, .null, -32700, "parse error");
    if (parsed != .object) return fail(a, .null, -32600, "invalid request");
    const id = parsed.object.get("id") orelse .null;
    const method = switch (parsed.object.get("method") orelse .null) {
        .string => |s| s,
        else => return fail(a, id, -32600, "invalid request"),
    };
    const params = parsed.object.get("params") orelse .null;
    const name = methodName(method) orelse {
        note(m, "{s} {s}: method not found", .{ door, method });
        return fail(a, id, -32601, "method not found");
    };
    _ = m.requests.fetchAdd(1, .monotonic);
    if (name != .run and name != .eval) note(m, "{s} {s}", .{ door, method });
    switch (name) {
        .ping => return ok(a, id, "pong"),
        .stat => {
            const status = .{
                .ipc = m.ipc,
                .http = m.http,
                .runs = m.runs.load(.monotonic),
                .domain = m.cfg.domain,
                .ipc_port = m.cfg.ipc_port,
                .http_port = m.cfg.http_port,
            };
            // `vm.stat` adds the active parts: the runtime and its IPC door, the UI and its web door (D-164)
            if (!std.mem.startsWith(u8, method, "vm.")) return ok(a, id, status);
            const parts: []const []const u8 = if (m.http) &.{ "vm", "ux" } else &.{"vm"};
            // what the machine is doing now is read under the lock that `setCurrent` takes to change it
            m.log_lock.lockUncancelable(m.io);
            defer m.log_lock.unlock(m.io);
            const now = millis(m.io);
            return ok(a, id, .{
                .ipc = status.ipc,
                .http = status.http,
                .runs = status.runs,
                .domain = status.domain,
                .ipc_port = status.ipc_port,
                .http_port = status.http_port,
                .parts = parts,
                .http_host = m.cfg.http_host,
                .web = m.cfg.web,
                .requests = m.requests.load(.monotonic),
                .uptime_ms = now - m.started,
                .running = m.current,
                .running_ms = if (m.current != null) now - m.current_since else 0,
                .door = door,
                .sessions = m.sessions.count(m.io),
            });
        },
        .stop => {
            stop.* = true;
            return ok(a, id, "stopping");
        },
        .run => return runScript(m, a, door, id, params, ch),
        .cancel => {
            vm.cancelAll();
            return ok(a, id, "cancelled");
        },
        .open => return if (ch == null) channel.localOnly(a, id) else channel.openRequest(m, a, id, params),
        .close => return if (ch == null) channel.localOnly(a, id) else channel.closeRequest(m, a, id, params),
        .eval => return if (ch) |c| channel.evalRequest(m, a, id, params, c) else channel.localOnly(a, id),
        .shell => return if (ch) |c| channel.shellRequest(m, a, id, params, c) else channel.localOnly(a, id),
    }
}

// Zig tip: an `enum` names a closed set of choices, and `switch` on it must cover every one: adding a method to
// the enum makes the compiler point at the `switch` of `rpc` until the new method is handled.
/// The methods a machine answers today (D-165): the names of the machine API and their first names (D-162).
pub const Method = enum { ping, stat, run, stop, cancel, open, eval, close, shell };

// Zig tip: a table of pairs `.{ name, value }` walked by `for` is the simplest map for a handful of names; the
// result is an optional (`?Method`), null for a name that is not in the table.
/// `vm.ping` and `ping`, `vm.stat` and `status`, `vm.run` and `run`, `vm.stop` and `stop`, and the methods of the
/// lasting doors (`vm.cancel`, `vm.open`, `vm.eval`, `vm.close`, `vm.shell`); null for another name.
pub fn methodName(method: []const u8) ?Method {
    const names = [_]struct { []const u8, Method }{
        .{ "vm.ping", .ping }, .{ "ping", .ping },
        .{ "vm.stat", .stat }, .{ "status", .stat },
        .{ "vm.run", .run },   .{ "run", .run },
        .{ "vm.stop", .stop }, .{ "stop", .stop },
        .{ "vm.cancel", .cancel }, .{ "vm.open", .open },
        .{ "vm.eval", .eval },     .{ "vm.close", .close },
        .{ "vm.shell", .shell },
    };
    for (names) |n| if (std.mem.eql(u8, method, n[0])) return n[1];
    return null;
}

// Zig tip: the session (`vm.Session`) is the same object the REPL uses; here its output is an `Io.Writer.Allocating`,
// a writer that grows in memory, so the text of the script comes back in the answer instead of the terminal. `defer`
// runs at the end of the function on every path, which releases the lock even when something fails.
// Zig tip: a script comes as text (`source`, what a remote client sends) or as a file of the machine (`path`, what an IDE
// on the same computer sends: nothing to copy). With `"stream": true` on a lasting door the output goes out as
// `vm.output` notifications while the script runs, and `output` in the answer is empty.
/// `run`: execute the script of the params in a session of its own, one at a time.
pub fn runScript(m: *Machine, a: std.mem.Allocator, door: []const u8, id: std.json.Value, params: std.json.Value, ch: ?*channel.Channel) []const u8 {
    if (params != .object) return fail(a, id, -32602, "run needs the params name and source, or path");
    const path: ?[]const u8 = switch (params.object.get("path") orelse .null) {
        .string => |s| s,
        else => null,
    };
    const source: ?[]const u8 = switch (params.object.get("source") orelse .null) {
        .string => |s| s,
        else => null,
    };
    if (source == null and path == null) return fail(a, id, -32602, "run needs the param source or path");
    // a path is a file of the machine: the HTTP door has no login yet, so it sends the text of the script
    if (source == null and ch == null) return channel.localOnly(a, id);
    const name = switch (params.object.get("name") orelse .null) {
        .string => |s| s,
        else => path orelse "script.eve",
    };
    var args: std.ArrayList([]const u8) = .empty;
    if (params.object.get("args")) |list| if (list == .array) for (list.array.items) |item| {
        if (item == .string) args.append(a, item.string) catch {};
    };
    // the log shows when a script had to wait for another one: the machine runs one script at a time
    const asked = millis(m.io);
    m.run_lock.lockUncancelable(m.io);
    defer m.run_lock.unlock(m.io);
    const started = millis(m.io);
    setCurrent(m, name, started);
    defer setCurrent(m, null, 0);
    var out: Io.Writer.Allocating = .init(a);
    const stream = ch != null and params.object.get("stream") != null and params.object.get("stream").? == .bool and params.object.get("stream").?.bool;
    var os: channel.OutStream = if (ch) |c| .init(c, a, id) else undefined;
    const w = if (stream) &os.interface else &out.writer;
    var s: vm.Session = .{ .io = m.io, .gpa = a, .out = w };
    s.quiet = true;
    s.script_args = args.items;
    if (source) |src| {
        s.loadSource(name, src) catch return fail(a, id, -32000, "out of memory");
    } else {
        s.load(path.?) catch return fail(a, id, -32000, "out of memory");
        if (s.arena == null) {
            if (stream) os.finish();
            return ok(a, id, .{ .status = s.status, .output = out.written(), .errors = "" });
        }
    }
    s.run() catch return fail(a, id, -32000, "the script could not run");
    w.flush() catch {};
    if (stream) os.finish();
    var errors: Io.Writer.Allocating = .init(a);
    if (s.outcome) |o| if (o.code != 0) if (s.machine) |machine| for (machine.reports.items) |r| {
        if (!r.handled) errors.writer.print("{s}:{d}: error {d}: {s}\n{s}{s}", .{ name, r.line, r.code, r.message, r.trace, r.details }) catch {};
    };
    _ = m.runs.fetchAdd(1, .monotonic);
    const waited = started - asked;
    if (waited >= 100) {
        note(m, "{s} run {s}: exit {d}, {d} ms (waited {d} ms for another script)", .{ door, name, s.status, millis(m.io) - started, waited });
    } else {
        note(m, "{s} run {s}: exit {d}, {d} ms", .{ door, name, s.status, millis(m.io) - started });
    }
    return ok(a, id, .{ .status = s.status, .output = out.written(), .errors = errors.written() });
}

// Zig tip: `defer setCurrent(m, null, 0)` in `runScript` runs before the `unlock` deferred above it (defers run in
// reverse order), so the machine is never seen "running" a script whose lock is already free. The name points into the
// memory of the request, which lives until the answer is sent, longer than the run.
/// Say which script runs now (null: none); `vm.stat` reports it.
pub fn setCurrent(m: *Machine, name: ?[]const u8, since: i64) void {
    m.log_lock.lockUncancelable(m.io);
    defer m.log_lock.unlock(m.io);
    m.current = name;
    m.current_since = since;
}

// Zig tip: `takeDelimiterInclusive('\n')` reads one line with its newline from a `Reader`; the bytes live in the
// reader's buffer, so a line longer than the buffer is an error (`StreamTooLong`) and the connection is dropped.
// `std.ascii.eqlIgnoreCase` compares header names, which are case-insensitive in HTTP.
/// Serve one HTTP connection: `GET` a file of the web folder, `POST /rpc` a JSON-RPC message. Returns true on `stop`.
pub fn serveHttp(m: *Machine, stream: net.Stream) bool {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const rbuf = a.alloc(u8, 64 * 1024) catch return false;
    var reader = stream.reader(m.io, rbuf);
    var wbuf: [4096]u8 = undefined;
    var writer = stream.writer(m.io, &wbuf);
    const r = &reader.interface;
    const w = &writer.interface;
    const first = r.takeDelimiterInclusive('\n') catch return false;
    var words = std.mem.tokenizeScalar(u8, std.mem.trim(u8, first, "\r\n"), ' ');
    const method = a.dupe(u8, words.next() orelse return false) catch return false;
    const target_all = a.dupe(u8, words.next() orelse return false) catch return false;
    var length: usize = 0;
    var chunked = false;
    while (true) {
        const h = std.mem.trim(u8, r.takeDelimiterInclusive('\n') catch return false, "\r\n");
        if (h.len == 0) break;
        const colon = std.mem.indexOfScalar(u8, h, ':') orelse continue;
        if (std.ascii.eqlIgnoreCase(h[0..colon], "content-length")) length = std.fmt.parseInt(usize, std.mem.trim(u8, h[colon + 1 ..], " "), 10) catch 0;
        if (std.ascii.eqlIgnoreCase(h[0..colon], "transfer-encoding") and std.ascii.findIgnoreCase(h[colon + 1 ..], "chunked") != null) chunked = true;
    }
    const target = target_all[0 .. std.mem.indexOfScalar(u8, target_all, '?') orelse target_all.len];
    if (std.mem.eql(u8, method, "POST")) {
        if (!std.mem.eql(u8, target, "/rpc")) return respondText(w, "404 Not Found", "not found\n");
        if (length > 16 << 20) return respondText(w, "413 Payload Too Large", "too large\n");
        const body = (if (chunked) readChunked(r, a, 16 << 20) else r.readAlloc(a, length)) catch |e| switch (e) {
            error.TooLarge => return respondText(w, "413 Payload Too Large", "too large\n"),
            else => return false,
        };
        var stop = false;
        respond(w, "200 OK", "application/json", rpc(m, a, "http", body, &stop, null));
        return stop;
    }
    if (!std.mem.eql(u8, method, "GET") and !std.mem.eql(u8, method, "HEAD")) {
        note(m, "http {s} {s}: 405", .{ method, target });
        return respondText(w, "405 Method Not Allowed", "method not allowed\n");
    }
    const path = if (std.mem.eql(u8, target, "/")) "/index.html" else target;
    const file = std.fmt.allocPrint(a, "{s}{s}", .{ m.cfg.web, path }) catch return false;
    const bytes = (if (safePath(path)) Io.Dir.cwd().readFileAlloc(m.io, file, a, .limited(64 << 20)) catch null else null) orelse {
        note(m, "http {s} {s}: 404", .{ method, target });
        return respondText(w, "404 Not Found", "not found\n");
    };
    note(m, "http {s} {s}: 200", .{ method, target });
    // `HEAD` asks for the headers only: the length is the one of the file, the body is not sent
    if (std.mem.eql(u8, method, "HEAD")) {
        w.print("HTTP/1.1 200 OK\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{ contentType(path), bytes.len }) catch return false;
        w.flush() catch {};
        return false;
    }
    respond(w, "200 OK", contentType(path), bytes);
    return false;
}

// Zig tip: the connection stays open while the client keeps it (channel.zig): one message per line, the answers and the
// notifications back on the same connection. A client that sends one line and closes (the CLI) still works: the next
// read finds the end of the stream. The buffer of the reader (16 MiB here) is the longest message accepted.
/// Serve one IPC connection: JSON-RPC messages on lines, until the client closes it. Returns true on `stop`.
pub fn serveIpc(m: *Machine, stream: net.Stream) bool {
    const rbuf = std.heap.page_allocator.alloc(u8, 16 << 20) catch return false;
    defer std.heap.page_allocator.free(rbuf);
    var reader = stream.reader(m.io, rbuf);
    var wbuf: [4096]u8 = undefined;
    var writer = stream.writer(m.io, &wbuf);
    var ch: channel.Channel = .{ .io = m.io, .w = &writer.interface };
    return channel.serveLines(m, &reader.interface, &ch, "ipc");
}

// Zig tip: a thread function takes its arguments as a tuple: `std.Thread.spawn(.{}, loop, .{ m, kind })`. It cannot
// return an error, so every failure is handled inside. After `stop` the machine ends with `std.process.exit(0)`: the
// reply was flushed first, and the socket file is removed so the next start does not find a dead one.
/// The accept loop of one door; it never returns, except by ending the process on `stop`.
pub fn accepting(m: *Machine, ipc: bool) void {
    while (true) {
        const server = if (ipc) &m.ipc_server else &m.http_server;
        const stream = server.accept(m.io) catch |e| switch (e) {
            error.SocketNotListening => return,
            else => continue,
        };
        // the connection that woke the loop after `shutdown`: the loop closes its own door and ends
        if (m.stopping.load(.acquire)) {
            stream.close(m.io);
            // the file goes first: a `restart` waits until nobody answers and then binds the same path, and a file
            // deleted after that would be the new one
            if (ipc) Io.Dir.deleteFileAbsolute(m.io, m.socket) catch {};
            server.socket.close(m.io);
            return;
        }
        // one thread per connection: a `status` is answered while a script runs (the scripts themselves still run one
        // at a time, `run_lock`). Without a thread to spare the connection is served here, as before.
        const t = std.Thread.spawn(.{}, connection, .{ m, stream, ipc }) catch {
            connection(m, stream, ipc);
            continue;
        };
        t.detach();
    }
}

// Zig tip: `Thread.detach` lets a thread end by itself, with nobody to `join` it: right for a thread that serves one
// connection and is done. `connection` is the body of that thread; it owns the stream and closes it.
/// Serve one connection of a door, close it, and end the process when the request was `stop`.
pub fn connection(m: *Machine, stream: net.Stream, ipc: bool) void {
    const stop = if (ipc) serveIpc(m, stream) else serveHttp(m, stream);
    stream.close(m.io);
    if (stop) {
        if (m.embedded) return shutdown(m);
        if (m.ipc) Io.Dir.deleteFileAbsolute(m.io, m.socket) catch {};
        std.process.exit(0);
    }
}

// Zig tip: a thread that waits in `accept` must not have its socket closed from outside: the standard library of
// Zig 0.16 treats the resulting `CANCELLED` code on Windows as impossible (`unreachable`) and the program panics. The
// safe way to stop a loop is to ask it: set the flag, then connect to the door once so that `accept` returns, and the
// loop (which sees the flag) closes its own socket and ends. `atomic.Value.swap` sets the flag and says if it was
// already set, so a second `stop` does nothing.
/// Stop the doors of a machine that lives inside the REPL, and leave the process running.
pub fn shutdown(m: *Machine) void {
    if (m.stopping.swap(true, .acq_rel)) return;
    vm.cancelAll();
    if (m.ipc) if (net.UnixAddress.init(m.socket)) |ua| {
        if (ua.connect(m.io)) |s| s.close(m.io) else |_| {}
    } else |_| {};
    if (m.http) {
        const host = if (std.mem.eql(u8, m.cfg.http_host, "localhost")) "127.0.0.1" else m.cfg.http_host;
        if (net.IpAddress.parse(host, m.cfg.http_port)) |addr| {
            if (addr.connect(m.io, .{ .mode = .stream })) |s| s.close(m.io) else |_| {}
        } else |_| {}
    }
    note(m, "stopped, the prompt keeps running", .{});
}

// Zig tip: the start is a list of steps that can each fail; a failure prints one line and returns the exit code,
// so `main` only has to exit with it. `catch |e| switch (e) { error.AddressInUse => …, else => … }` picks the message
// by the kind of error.
/// `--listen`, `--serve`: open the doors and stay active. Returns the exit code if the machine could not start.
pub fn serve(io: Io, gpa: std.mem.Allocator, out: *Io.Writer, cfg: Config, ipc: bool, http: bool, embed: bool) !u8 {
    const m = try gpa.create(Machine);
    m.* = .{ .io = io, .cfg = cfg, .ipc = ipc, .http = http, .socket = try socketPath(gpa, cfg), .out = out, .started = millis(io) };
    if (ipc) {
        if (ipcAlive(io, m.socket)) {
            try out.print("eve: already running (ipc {s}:{d})\n", .{ cfg.domain, cfg.ipc_port });
            return exit_running;
        }
        Io.Dir.deleteFileAbsolute(io, m.socket) catch {}; // a socket left by a crash
        const ua = net.UnixAddress.init(m.socket) catch {
            try out.print("eve: the path of the socket is too long: {s}\n", .{m.socket});
            return exit_usage;
        };
        m.ipc_server = ua.listen(io, .{}) catch |e| {
            try out.print("eve: cannot listen on ipc {s}: {s}\n", .{ m.socket, @errorName(e) });
            return if (e == error.AddressInUse) exit_running else exit_unavailable;
        };
    }
    if (http) {
        // Windows lets a second socket bind a port that is already listening, so the bind is not a lock: ask the port
        if (httpCall(io, gpa, cfg.http_host, cfg.http_port, message(gpa, "vm.ping", null)) != null) {
            try out.print("eve: already running (http {s}:{d})\n", .{ cfg.http_host, cfg.http_port });
            if (ipc) Io.Dir.deleteFileAbsolute(io, m.socket) catch {};
            return exit_running;
        }
        const host = if (std.mem.eql(u8, cfg.http_host, "localhost")) "127.0.0.1" else cfg.http_host;
        const addr = net.IpAddress.parse(host, cfg.http_port) catch {
            try out.print("eve: http_host is not an address: {s}\n", .{cfg.http_host});
            return exit_usage;
        };
        m.http_server = addr.listen(io, .{}) catch |e| {
            if (ipc) Io.Dir.deleteFileAbsolute(io, m.socket) catch {};
            try out.print("eve: cannot serve http on {s}:{d}: {s}\n", .{ cfg.http_host, cfg.http_port, @errorName(e) });
            return if (e == error.AddressInUse) exit_running else exit_unavailable;
        };
    }
    if (ipc) try out.print("eve: ipc {s}:{d}\n", .{ cfg.domain, cfg.ipc_port });
    if (http) try out.print("eve: http http://{s}:{d}\n", .{ cfg.http_host, cfg.http_port });
    try out.flush();
    if (embed) {
        // the log of the machine gets a writer of its own: the REPL writes to `out` from another thread, and a Writer
        // is not safe for two threads. Both end on the same terminal, one whole line at a time.
        const buf = try gpa.alloc(u8, 1024);
        const w = try gpa.create(Io.File.Writer);
        w.* = .initStreaming(.stdout(), io, buf);
        m.out = &w.interface;
        m.embedded = true;
        embedded = true;
        register(m);
    }
    var threads: [2]?std.Thread = .{ null, null };
    if (ipc) threads[0] = try std.Thread.spawn(.{}, accepting, .{ m, true });
    if (http) threads[1] = try std.Thread.spawn(.{}, accepting, .{ m, false });
    // inside the REPL the threads run on their own and the prompt comes back; as a service the caller waits for them
    for (threads) |t| if (t) |th| if (embed) th.detach() else th.join();
    return 0;
}


// Zig tip: `@splat(null)` fills an array with one value; here four empty places for the machines that this process
// opened (a machine is opened in the process by `serve` with `embed`). The array is read by `stop` on the thread of the
// prompt, and written by `serve` on the same thread, so it needs no lock.
pub var machines: [4]?*Machine = @splat(null);

/// Remember a machine that lives in this process, so that `stop` finds it. A place of a machine that stopped is reused.
pub fn register(m: *Machine) void {
    for (&machines) |*slot| {
        if (slot.* == null or slot.*.?.stopping.load(.acquire)) {
            slot.* = m;
            return;
        }
    }
}
