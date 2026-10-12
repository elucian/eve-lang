//! The Eve machine as a server (F-NET-02, D-162, `spec/library/machine.md`): a singleton that listens on two doors, the
//! IPC door (`-lsn`, a Unix domain socket) and the HTTP door (`--serve`, the web folder and `POST /rpc`), and the client
//! side of the same protocol (`-loc`, `-rem`, `--serve stop|status`). Both doors speak JSON-RPC 2.0.
const std = @import("std");
const Io = std.Io;
const net = Io.net;
const vm = @import("vm.zig");

/// Exit codes of the machine (spec/library/machine.md): nobody answers / a machine already runs.
pub const exit_unavailable = 69;
pub const exit_running = 75;
const exit_usage = 64;

// Zig tip: a `var` at file level is a global. The program sets it once at start (main.zig) from the environment, before
// any thread exists, so no lock is needed. `[]const u8` is a read-only text: the global does not own the memory.
/// The folder of the IPC sockets: `$XDG_RUNTIME_DIR`, else `$TMPDIR`, else `%TEMP%`, else `/tmp`.
pub var runtime_dir: []const u8 = "/tmp";

// Zig tip: a struct with default values for all its fields: `.{}` is a complete configuration, and
// `.{ .ipc_port = 4195 }` changes one field. The defaults are the ones of the specification.
/// The keys of `eve.cfg` that the machine reads.
pub const Config = struct {
    domain: []const u8 = "localhost",
    ipc_port: u16 = 4042,
    http_port: u16 = 8042,
    http_host: []const u8 = "localhost",
    web: []const u8 = "web",
    remote: ?[]const u8 = null,
};

// Zig tip: `catch return .{}` on a read means "no file, no keys": the answer is the default configuration. The values
// are slices of `bytes`, which stays alive (it is allocated with `gpa` and never freed: the configuration lives as
// long as the program).
/// Read the configuration file; a missing file gives the defaults.
pub fn loadConfig(io: Io, gpa: std.mem.Allocator, path: []const u8) Config {
    const bytes = Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1 << 20)) catch return .{};
    return parseConfig(bytes);
}

// Zig tip: a text is cut into lines with `tokenizeScalar`; `indexOfScalar` returns an optional, and `orelse continue`
// skips a line that has no `=`. `vm.clean` is the comment rule of the slot files, reused: a line that starts with `#`
// and the text from `**` to the end of a line are comments, as in Eve and in the `eve.cfg` that `project init` writes.
/// Read `key = value` lines; unknown keys (such as `database "x" = …` or `core_db`) are ignored.
pub fn parseConfig(bytes: []const u8) Config {
    var cfg: Config = .{};
    var lines = std.mem.tokenizeScalar(u8, bytes, '\n');
    while (lines.next()) |raw| {
        const line = vm.clean(raw);
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq], " \t");
        const value = std.mem.trim(u8, std.mem.trim(u8, line[eq + 1 ..], " \t"), "\"");
        if (std.mem.eql(u8, key, "domain")) cfg.domain = value;
        if (std.mem.eql(u8, key, "ipc_port")) cfg.ipc_port = std.fmt.parseInt(u16, value, 10) catch cfg.ipc_port;
        if (std.mem.eql(u8, key, "http_port")) cfg.http_port = std.fmt.parseInt(u16, value, 10) catch cfg.http_port;
        if (std.mem.eql(u8, key, "http_host")) cfg.http_host = value;
        if (std.mem.eql(u8, key, "web")) cfg.web = value;
        if (std.mem.eql(u8, key, "remote")) cfg.remote = value;
    }
    return cfg;
}

// Zig tip: `![]u8` is an error union with an inferred error set: the function returns a new text or the error of
// `allocPrint` (out of memory), and the caller writes `try`. `{d}` prints a number, `{s}` a text.
/// The path of the socket that identifies the machine: `<runtime>/eve-<domain>-<ipc_port>.sock`.
fn socketPath(gpa: std.mem.Allocator, cfg: Config) ![]u8 {
    return std.fmt.allocPrint(gpa, "{s}/eve-{s}-{d}.sock", .{ runtime_dir, cfg.domain, cfg.ipc_port });
}

// ---- the machine (server side) -------------------------------------------------------------------------------

// Zig tip: a struct that threads share holds what they share. `std.atomic.Value(usize)` is a counter that several
// threads can add to without a lock; `Io.Mutex` is a lock (each call takes the `Io` handle in Zig 0.16). The two doors
// run in two threads, and the mutex makes the scripts run one at a time.
/// What both doors share: the configuration, the counters, the lock of the scripts and the log of the machine.
const Machine = struct {
    io: Io,
    cfg: Config,
    ipc: bool,
    http: bool,
    socket: []const u8,
    /// The terminal of the machine: one line per request (`note`).
    out: *Io.Writer,
    runs: std.atomic.Value(usize) = .init(0),
    run_lock: Io.Mutex = .init,
    log_lock: Io.Mutex = .init,
    ipc_server: net.Server = undefined,
    http_server: net.Server = undefined,
};

// Zig tip: `comptime fmt: []const u8` makes the format a compile-time value, so `"eve: " ++ fmt ++ "\n"` joins the
// texts while compiling (`++` works only on comptime values). A `Writer` is not safe for two threads at once: the two
// doors log through the same terminal, so the lock makes each line whole.
/// Write one line of the log of the machine on its terminal.
fn note(m: *Machine, comptime fmt: []const u8, args: anytype) void {
    m.log_lock.lockUncancelable(m.io);
    defer m.log_lock.unlock(m.io);
    m.out.print("eve: " ++ fmt ++ "\n", args) catch return;
    m.out.flush() catch {};
}

// Zig tip: `Io.Timestamp.now(io, .awake)` reads a clock that only goes forward (it does not jump when the time of
// day is changed), the right one to measure a duration. `toMilliseconds` turns it into a number.
fn millis(io: Io) i64 {
    return Io.Timestamp.now(io, .awake).toMilliseconds();
}

// Zig tip: the per-request memory is an arena over `page_allocator`: everything the request allocates (the parsed
// JSON, the answer, the session of the script) is freed with one `deinit`, so a machine that runs for days does not
// grow. The process arena of `main` is never freed, so it must not be used for a server.
/// One JSON-RPC message in, one message out (allocated in `a`). Sets `stop` when the method is `stop`. `door` is
/// `ipc` or `http`, for the log.
fn rpc(m: *Machine, a: std.mem.Allocator, door: []const u8, body: []const u8, stop: *bool) []const u8 {
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, a, body, .{}) catch return fail(a, .null, -32700, "parse error");
    if (parsed != .object) return fail(a, .null, -32600, "invalid request");
    const id = parsed.object.get("id") orelse .null;
    const method = switch (parsed.object.get("method") orelse .null) {
        .string => |s| s,
        else => return fail(a, id, -32600, "invalid request"),
    };
    const params = parsed.object.get("params") orelse .null;
    if (!std.mem.eql(u8, method, "run")) note(m, "{s} {s}", .{ door, method });
    if (std.mem.eql(u8, method, "ping")) return ok(a, id, "pong");
    if (std.mem.eql(u8, method, "status")) return ok(a, id, .{
        .ipc = m.ipc,
        .http = m.http,
        .runs = m.runs.load(.monotonic),
        .domain = m.cfg.domain,
        .ipc_port = m.cfg.ipc_port,
        .http_port = m.cfg.http_port,
    });
    if (std.mem.eql(u8, method, "stop")) {
        stop.* = true;
        return ok(a, id, "stopping");
    }
    if (std.mem.eql(u8, method, "run")) return runScript(m, a, door, id, params);
    return fail(a, id, -32601, "method not found");
}

// Zig tip: `anytype` takes a value of any type, here a string or an anonymous struct, and `std.json.Stringify`
// turns it into JSON by looking at the fields (at compile time). A field called `error` is a keyword, so it is
// written `@"error"`.
fn ok(a: std.mem.Allocator, id: std.json.Value, result: anytype) []const u8 {
    return std.json.Stringify.valueAlloc(a, .{ .jsonrpc = "2.0", .id = id, .result = result }, .{}) catch "";
}

// Zig tip: `fail` relies on the same features as `ok` above: see the tip there.
fn fail(a: std.mem.Allocator, id: std.json.Value, code: i32, reason: []const u8) []const u8 {
    return std.json.Stringify.valueAlloc(a, .{ .jsonrpc = "2.0", .id = id, .@"error" = .{ .code = code, .message = reason } }, .{}) catch "";
}

// Zig tip: the session (`vm.Session`) is the same object the REPL uses; here its output is an `Io.Writer.Allocating`,
// a writer that grows in memory, so the text of the script comes back in the answer instead of the terminal. `defer`
// runs at the end of the function on every path, which releases the lock even when something fails.
/// `run`: execute the script of the params in a session of its own, one at a time.
fn runScript(m: *Machine, a: std.mem.Allocator, door: []const u8, id: std.json.Value, params: std.json.Value) []const u8 {
    if (params != .object) return fail(a, id, -32602, "run needs the params name and source");
    const source = switch (params.object.get("source") orelse .null) {
        .string => |s| s,
        else => return fail(a, id, -32602, "run needs the param source"),
    };
    const name = switch (params.object.get("name") orelse .null) {
        .string => |s| s,
        else => "script.eve",
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
    var out: Io.Writer.Allocating = .init(a);
    var s: vm.Session = .{ .io = m.io, .gpa = a, .out = &out.writer };
    s.quiet = true;
    s.script_args = args.items;
    s.loadSource(name, source) catch return fail(a, id, -32000, "out of memory");
    s.run() catch return fail(a, id, -32000, "the script could not run");
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

// Zig tip: `[_][2][]const u8{ ... }` is an array of pairs of texts whose length the compiler counts (`_`). A table in
// the code is a constant, built at compile time; the loop returns at the first extension that matches.
/// The type of a file for the `Content-Type` header, from its extension.
fn contentType(path: []const u8) []const u8 {
    const table = [_][2][]const u8{
        .{ ".html", "text/html; charset=utf-8" },  .{ ".css", "text/css; charset=utf-8" },
        .{ ".js", "text/javascript; charset=utf-8" }, .{ ".json", "application/json" },
        .{ ".svg", "image/svg+xml" },              .{ ".png", "image/png" },
        .{ ".jpg", "image/jpeg" },                 .{ ".ico", "image/x-icon" },
        .{ ".txt", "text/plain; charset=utf-8" },  .{ ".wasm", "application/wasm" },
    };
    for (table) |e| if (std.mem.endsWith(u8, path, e[0])) return e[1];
    return "application/octet-stream";
}

// Zig tip: a path from the network is never trusted. The path is refused when it has `..`, a backslash or a colon
// (a drive on Windows), so it can only name a file below the web folder. `std.mem.splitScalar` walks the pieces
// between `/`.
/// True when the request path may be joined to the web folder.
fn safePath(path: []const u8) bool {
    if (path.len == 0 or path[0] != '/') return false;
    if (std.mem.indexOfAny(u8, path, "\\:\x00") != null) return false;
    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |p| if (std.mem.eql(u8, p, "..")) return false;
    return true;
}

// Zig tip: `catch return` in a function that returns `void` gives up quietly: a browser that closed the connection
// is not an error of the machine. CR LF is the line end that HTTP requires.
/// Write one HTTP/1.1 answer and let the caller close the connection.
fn respond(w: *Io.Writer, status: []const u8, kind: []const u8, body: []const u8) void {
    w.print("HTTP/1.1 {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{ status, kind, body.len }) catch return;
    w.writeAll(body) catch return;
    w.flush() catch {};
}

// Zig tip: `takeDelimiterInclusive('\n')` reads one line with its newline from a `Reader`; the bytes live in the
// reader's buffer, so a line longer than the buffer is an error (`StreamTooLong`) and the connection is dropped.
// `std.ascii.eqlIgnoreCase` compares header names, which are case-insensitive in HTTP.
/// Serve one HTTP connection: `GET` a file of the web folder, `POST /rpc` a JSON-RPC message. Returns true on `stop`.
fn serveHttp(m: *Machine, stream: net.Stream) bool {
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
    while (true) {
        const h = std.mem.trim(u8, r.takeDelimiterInclusive('\n') catch return false, "\r\n");
        if (h.len == 0) break;
        const colon = std.mem.indexOfScalar(u8, h, ':') orelse continue;
        if (std.ascii.eqlIgnoreCase(h[0..colon], "content-length")) length = std.fmt.parseInt(usize, std.mem.trim(u8, h[colon + 1 ..], " "), 10) catch 0;
    }
    const target = target_all[0 .. std.mem.indexOfScalar(u8, target_all, '?') orelse target_all.len];
    if (std.mem.eql(u8, method, "POST")) {
        if (!std.mem.eql(u8, target, "/rpc")) return respondText(w, "404 Not Found", "not found\n");
        if (length > 16 << 20) return respondText(w, "413 Payload Too Large", "too large\n");
        const body = r.readAlloc(a, length) catch return false;
        var stop = false;
        respond(w, "200 OK", "application/json", rpc(m, a, "http", body, &stop));
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

// Zig tip: `respondText` returns `false` so a caller can write `return respondText(...)` in a function that answers
// "was it a stop?": one line answers the request and gives the result.
fn respondText(w: *Io.Writer, status: []const u8, body: []const u8) bool {
    respond(w, status, "text/plain; charset=utf-8", body);
    return false;
}

// Zig tip: `takeDelimiter` (with the newline byte) answers an optional slice: a line, or null at the end of the stream; `orelse return
// false` leaves when the client sent nothing. The buffer of the reader (16 MiB here) is the longest message accepted.
/// Serve one IPC connection: one JSON-RPC message on a line, one answer on a line. Returns true on `stop`.
fn serveIpc(m: *Machine, stream: net.Stream) bool {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const rbuf = a.alloc(u8, 16 << 20) catch return false;
    var reader = stream.reader(m.io, rbuf);
    var wbuf: [4096]u8 = undefined;
    var writer = stream.writer(m.io, &wbuf);
    const line = (reader.interface.takeDelimiter('\n') catch return false) orelse return false;
    var stop = false;
    const answer = rpc(m, a, "ipc", line, &stop);
    writer.interface.writeAll(answer) catch return false;
    writer.interface.writeAll("\n") catch return false;
    writer.interface.flush() catch {};
    return stop;
}

// Zig tip: a thread function takes its arguments as a tuple: `std.Thread.spawn(.{}, loop, .{ m, kind })`. It cannot
// return an error, so every failure is handled inside. After `stop` the machine ends with `std.process.exit(0)`: the
// reply was flushed first, and the socket file is removed so the next start does not find a dead one.
/// The accept loop of one door; it never returns, except by ending the process on `stop`.
fn accepting(m: *Machine, ipc: bool) void {
    while (true) {
        const server = if (ipc) &m.ipc_server else &m.http_server;
        const stream = server.accept(m.io) catch |e| switch (e) {
            error.SocketNotListening => return,
            else => continue,
        };
        const stop = if (ipc) serveIpc(m, stream) else serveHttp(m, stream);
        stream.close(m.io);
        if (stop) {
            if (m.ipc) Io.Dir.deleteFileAbsolute(m.io, m.socket) catch {};
            std.process.exit(0);
        }
    }
}

// Zig tip: a connection that is opened only to test the door is closed at once; `catch return false` turns every
// error of `connect` (no file, nobody listening) into the answer "no".
/// True when something answers on the IPC socket of this configuration.
fn ipcAlive(io: Io, socket: []const u8) bool {
    const ua = net.UnixAddress.init(socket) catch return false;
    const s = ua.connect(io) catch return false;
    s.close(io);
    return true;
}

// Zig tip: the start is a list of steps that can each fail; a failure prints one line and returns the exit code,
// so `main` only has to exit with it. `catch |e| switch (e) { error.AddressInUse => …, else => … }` picks the message
// by the kind of error.
/// `-lsn`, `--serve`: open the doors and stay active. Returns the exit code if the machine could not start.
fn serve(io: Io, gpa: std.mem.Allocator, out: *Io.Writer, cfg: Config, ipc: bool, http: bool) !u8 {
    const m = try gpa.create(Machine);
    m.* = .{ .io = io, .cfg = cfg, .ipc = ipc, .http = http, .socket = try socketPath(gpa, cfg), .out = out };
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
        if (httpCall(io, gpa, cfg.http_host, cfg.http_port, message(gpa, "ping", null)) != null) {
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
    var threads: [2]?std.Thread = .{ null, null };
    if (ipc) threads[0] = try std.Thread.spawn(.{}, accepting, .{ m, true });
    if (http) threads[1] = try std.Thread.spawn(.{}, accepting, .{ m, false });
    for (threads) |t| if (t) |th| th.join();
    return 0;
}

// ---- the client side -----------------------------------------------------------------------------------------

// Zig tip: a client connects, sends one message and reads until the server closes the connection: `allocRemaining`
// reads to the end of the stream into memory, with a limit. The answer is `null` when nobody listens: the caller
// decides what that means (`-loc` falls back to a local run, `-rem` fails).
/// Send one JSON-RPC message on the IPC socket; the answer, or null when no machine listens.
fn ipcCall(io: Io, gpa: std.mem.Allocator, socket: []const u8, request: []const u8) ?[]const u8 {
    const ua = net.UnixAddress.init(socket) catch return null;
    const stream = ua.connect(io) catch return null;
    defer stream.close(io);
    var wbuf: [4096]u8 = undefined;
    var writer = stream.writer(io, &wbuf);
    writer.interface.writeAll(request) catch return null;
    writer.interface.writeAll("\n") catch return null;
    writer.interface.flush() catch return null;
    var rbuf: [4096]u8 = undefined;
    var reader = stream.reader(io, &rbuf);
    const all = reader.interface.allocRemaining(gpa, .limited(64 << 20)) catch return null;
    return std.mem.trim(u8, all, "\r\n");
}

// Zig tip: `httpCall` relies on the same features as `ipcCall` above: see the tip there. HTTP adds a head: the request
// line, the headers and an empty line; the answer is cut at the first empty line to keep only its body.
/// Send one JSON-RPC message to the HTTP door `host:port` (`POST /rpc`); the body of the answer, or null.
fn httpCall(io: Io, gpa: std.mem.Allocator, host: []const u8, port: u16, request: []const u8) ?[]const u8 {
    const ip = if (std.mem.eql(u8, host, "localhost")) "127.0.0.1" else host;
    const addr = net.IpAddress.parse(ip, port) catch return null;
    const stream = addr.connect(io, .{ .mode = .stream }) catch return null;
    defer stream.close(io);
    var wbuf: [4096]u8 = undefined;
    var writer = stream.writer(io, &wbuf);
    writer.interface.print("POST /rpc HTTP/1.1\r\nHost: {s}:{d}\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{ host, port, request.len }) catch return null;
    writer.interface.writeAll(request) catch return null;
    writer.interface.flush() catch return null;
    var rbuf: [4096]u8 = undefined;
    var reader = stream.reader(io, &rbuf);
    const all = reader.interface.allocRemaining(gpa, .limited(64 << 20)) catch return null;
    const cut = std.mem.indexOf(u8, all, "\r\n\r\n") orelse return null;
    if (!std.mem.startsWith(u8, all, "HTTP/1.1 200")) return null;
    return all[cut + 4 ..];
}

// Zig tip: `?[]const u8 = null` is an optional text that is absent by default: `-lsn` with no port leaves
// `listen_port` null, and the configuration keeps its own port.
/// What the command line asked for (built by `main.zig` from the options).
pub const Cmd = struct {
    listen: bool = false,
    listen_port: ?[]const u8 = null,
    serve: bool = false,
    /// `start`, `stop`, `restart` or `status` after `--serve`; empty is `start`.
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
const Answer = struct { result: std.json.Value };

// Zig tip: the outcome is an optional, not an error: `Answer` when the machine answered, `null` when nobody did, and
// the caller prints the message that fits its option. `remote_name: *[]const u8` is an out-parameter: the function
// writes the address it tried through the pointer (`remote_name.* = addr`). `std.json.parseFromSliceLeaky` allocates
// the parsed tree in `gpa` and never frees it, which is fine for a program that sends one command and exits.
/// Send `request` to the machine the options point to: `-rem` the HTTP door of that address, `-loc` the IPC door, and
/// without option the IPC door and then the HTTP door of `localhost`.
fn send(io: Io, gpa: std.mem.Allocator, cfg: Config, cmd: Cmd, request: []const u8, remote_name: *[]const u8) ?Answer {
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
fn field(v: std.json.Value, name: []const u8) std.json.Value {
    return if (v == .object) (v.object.get(name) orelse .null) else .null;
}

fn text(v: std.json.Value) []const u8 {
    return if (v == .string) v.string else "";
}

fn number(v: std.json.Value) i64 {
    return if (v == .integer) v.integer else 0;
}

fn listening(v: std.json.Value) []const u8 {
    return if (v == .bool and v.bool) "listening" else "off";
}

// Zig tip: `message` relies on the same features as `ok` above (`anytype` and `std.json.Stringify`): see the tip there.
/// A message `{"jsonrpc":"2.0","id":1,"method":…,"params":…}` (allocated in `gpa`).
fn message(gpa: std.mem.Allocator, method: []const u8, params: anytype) []const u8 {
    return std.json.Stringify.valueAlloc(gpa, .{ .jsonrpc = "2.0", .id = 1, .method = method, .params = params }, .{}) catch "";
}

// Zig tip: `!u8` returns an exit code or a write error; `try out.print` passes the error up. One function chooses
// the message of each option, so the three ways to miss a machine are worded in one place.
fn gone(out: *Io.Writer, cmd: Cmd, name: []const u8) !u8 {
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
pub fn handle(io: Io, gpa: std.mem.Allocator, out: *Io.Writer, cmd: Cmd) !?u8 {
    var cfg = loadConfig(io, gpa, cmd.config orelse "eve.cfg");
    if (cmd.listen_port) |p| cfg.ipc_port = std.fmt.parseInt(u16, p, 10) catch cfg.ipc_port;
    if (cmd.local_port) |p| cfg.ipc_port = std.fmt.parseInt(u16, p, 10) catch cfg.ipc_port;
    var name: []const u8 = "";
    const word = cmd.word;
    if (cmd.remote and (cmd.remote_addr orelse cfg.remote) == null) {
        try out.writeAll("eve: -rem needs an address (host:port) or the key remote in eve.cfg\n");
        return exit_usage;
    }
    const starting = cmd.listen or (cmd.serve and (word.len == 0 or std.mem.eql(u8, word, "start") or std.mem.eql(u8, word, "restart")));
    if (starting) {
        // `--serve` alone is HTTP only; `-lsn` is IPC only; both together open both doors
        var ipc = cmd.listen;
        var http = cmd.serve;
        if (std.mem.eql(u8, word, "restart")) {
            // a restart keeps the doors of the running machine: ask them before the stop; `-lsn` may add IPC
            var probe = cmd;
            if (send(io, gpa, cfg, cmd, message(gpa, "status", null), &name)) |a| {
                const had_ipc = field(a.result, "ipc") == .bool and field(a.result, "ipc").bool;
                ipc = ipc or had_ipc;
                http = (field(a.result, "http") == .bool and field(a.result, "http").bool) or !ipc;
                _ = send(io, gpa, cfg, cmd, message(gpa, "stop", null), &name);
                try out.print("eve: stopped, starting again\n", .{});
                // wait through IPC when the old machine had it: a refused TCP connection takes about 2 s on Windows
                probe.local = had_ipc;
            }
            var tries: usize = 0;
            while (tries < 50 and send(io, gpa, cfg, probe, message(gpa, "ping", null), &name) != null) : (tries += 1) {
                Io.sleep(io, .fromMilliseconds(100), .awake) catch {};
            }
        }
        return try serve(io, gpa, out, cfg, ipc, http);
    }
    if (cmd.serve and std.mem.eql(u8, word, "stop")) {
        _ = send(io, gpa, cfg, cmd, message(gpa, "stop", null), &name) orelse return try gone(out, cmd, name);
        try out.writeAll("eve: stopped\n");
        return 0;
    }
    if (cmd.serve and std.mem.eql(u8, word, "status")) {
        const a = send(io, gpa, cfg, cmd, message(gpa, "status", null), &name) orelse return try gone(out, cmd, name);
        const r = a.result;
        try out.print("machine: {s} ipc={d} http={d}\nipc: {s}\nhttp: {s}\nruns: {d}\n", .{
            text(field(r, "domain")),
            number(field(r, "ipc_port")),
            number(field(r, "http_port")),
            listening(field(r, "ipc")),
            listening(field(r, "http")),
            number(field(r, "runs")),
        });
        return 0;
    }
    if (cmd.serve) {
        try out.print("eve: --serve {s}: expected start, stop, restart or status\n", .{word});
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
fn runVia(io: Io, gpa: std.mem.Allocator, out: *Io.Writer, cfg: Config, cmd: Cmd) !?u8 {
    const path = cmd.script.?;
    var name: []const u8 = "";
    const source = Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(16 << 20)) catch {
        try out.print("eve: cannot read {s}\n", .{path});
        return 66;
    };
    const base = path[if (std.mem.lastIndexOfAny(u8, path, "/\\")) |i| i + 1 else 0..];
    const request = message(gpa, "run", .{ .name = base, .source = source, .args = cmd.script_args });
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
