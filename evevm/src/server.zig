//! The Eve machine as a server (F-NET-02, D-162, `spec/library/machine.md`): a singleton that listens on two doors, the
//! IPC door (`--listen`, a Unix domain socket) and the HTTP door (`--serve`, the web folder and `POST /rpc`), and the client
//! side of the same protocol (`-loc`, `-rem`, `--serve stop|status`). Both doors speak JSON-RPC 2.0.
const std = @import("std");
const builtin = @import("builtin");
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
    /// Width of the help table and texts in characters (`eve_width`; 100 when it is not set).
    eve_width: usize = 100,
};

// Zig tip: `catch return .{}` on a read means "no file, no keys": the answer is the default configuration. The values
// are slices of `bytes`, which stays alive (it is allocated with `gpa` and never freed: the configuration lives as
// long as the program).
/// Read the configuration file; a missing file gives the defaults.
pub fn loadConfig(io: Io, gpa: std.mem.Allocator, path: []const u8) Config {
    return readConfig(io, gpa, path) orelse .{};
}

// Zig tip: the optional `?Config` tells "no file" (null) from "a file with no keys" (a default `Config`), which
// `loadConfig` above cannot: the status report needs the difference to say if the configuration was loaded.
/// Read the configuration file; null when it is missing.
pub fn readConfig(io: Io, gpa: std.mem.Allocator, path: []const u8) ?Config {
    const bytes = Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1 << 20)) catch return null;
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
        if (std.mem.eql(u8, key, "eve_width")) cfg.eve_width = std.fmt.parseInt(usize, value, 10) catch cfg.eve_width;
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
fn note(m: *Machine, comptime fmt: []const u8, args: anytype) void {
    m.log_lock.lockUncancelable(m.io);
    defer m.log_lock.unlock(m.io);
    const out = if (m.embedded) embed_log orelse m.out else m.out;
    out.print("eve: " ++ fmt ++ "\n", args) catch return;
    out.flush() catch {};
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
    const name = methodName(method) orelse {
        note(m, "{s} {s}: method not found", .{ door, method });
        return fail(a, id, -32601, "method not found");
    };
    _ = m.requests.fetchAdd(1, .monotonic);
    if (name != .run) note(m, "{s} {s}", .{ door, method });
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
            });
        },
        .stop => {
            stop.* = true;
            return ok(a, id, "stopping");
        },
        .run => return runScript(m, a, door, id, params),
    }
}

// Zig tip: an `enum` names a closed set of choices, and `switch` on it must cover every one: adding a method to
// the enum makes the compiler point at the `switch` of `rpc` until the new method is handled.
/// The methods a machine answers today (D-165): the names of the machine API and their first names (D-162).
const Method = enum { ping, stat, run, stop };

// Zig tip: a table of pairs `.{ name, value }` walked by `for` is the simplest map for a handful of names; the
// result is an optional (`?Method`), null for a name that is not in the table.
/// `vm.ping` and `ping`, `vm.stat` and `status`, `vm.run` and `run`, `vm.stop` and `stop`; null for another name.
fn methodName(method: []const u8) ?Method {
    const names = [_]struct { []const u8, Method }{
        .{ "vm.ping", .ping }, .{ "ping", .ping },
        .{ "vm.stat", .stat }, .{ "status", .stat },
        .{ "vm.run", .run },   .{ "run", .run },
        .{ "vm.stop", .stop }, .{ "stop", .stop },
    };
    for (names) |n| if (std.mem.eql(u8, method, n[0])) return n[1];
    return null;
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
    setCurrent(m, name, started);
    defer setCurrent(m, null, 0);
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

// Zig tip: `defer setCurrent(m, null, 0)` in `runScript` runs before the `unlock` deferred above it (defers run in
// reverse order), so the machine is never seen "running" a script whose lock is already free. The name points into the
// memory of the request, which lives until the answer is sent, longer than the run.
/// Say which script runs now (null: none); `vm.stat` reports it.
fn setCurrent(m: *Machine, name: ?[]const u8, since: i64) void {
    m.log_lock.lockUncancelable(m.io);
    defer m.log_lock.unlock(m.io);
    m.current = name;
    m.current_since = since;
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
    var chunked = false;
    while (true) {
        const h = std.mem.trim(u8, r.takeDelimiterInclusive('\n') catch return false, "\r\n");
        if (h.len == 0) break;
        const colon = std.mem.indexOfScalar(u8, h, ':') orelse continue;
        if (std.ascii.eqlIgnoreCase(h[0..colon], "content-length")) length = std.fmt.parseInt(usize, std.mem.trim(u8, h[colon + 1 ..], " "), 10) catch 0;
        if (std.ascii.eqlIgnoreCase(h[0..colon], "transfer-encoding") and std.ascii.indexOfIgnoreCase(h[colon + 1 ..], "chunked") != null) chunked = true;
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

// Zig tip: an error set can be declared by hand (`error{TooLarge}`) and merged with another one with `||`: the
// function may fail with the errors of the reader or with its own. `std.fmt.parseInt(usize, text, 16)` reads the
// hexadecimal size of a chunk; what follows a `;` on that line is an extension that a server may ignore.
/// The body of a request sent with `Transfer-Encoding: chunked`: chunks `<size in hex>\r\n<bytes>\r\n`, ended by a
/// chunk of size 0 and the empty line after the trailer headers (RFC 9112, section 7.1). At most `limit` bytes.
fn readChunked(r: *Io.Reader, a: std.mem.Allocator, limit: usize) (error{ TooLarge, BadChunk } || Io.Reader.Error || Io.Reader.DelimiterError || std.mem.Allocator.Error)![]u8 {
    var body: std.ArrayList(u8) = .empty;
    while (true) {
        const line = std.mem.trim(u8, try r.takeDelimiterInclusive('\n'), " \r\n");
        const hex = line[0 .. std.mem.indexOfScalar(u8, line, ';') orelse line.len];
        const size = std.fmt.parseInt(usize, hex, 16) catch return error.BadChunk;
        if (size == 0) break;
        if (body.items.len + size > limit) return error.TooLarge;
        try body.appendSlice(a, try r.take(size));
        _ = try r.takeDelimiterInclusive('\n'); // the CRLF after the bytes of the chunk
    }
    // the trailer: header lines up to an empty line
    while (std.mem.trim(u8, try r.takeDelimiterInclusive('\n'), "\r\n").len > 0) {}
    return body.items;
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
fn connection(m: *Machine, stream: net.Stream, ipc: bool) void {
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
fn shutdown(m: *Machine) void {
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
/// `--listen`, `--serve`: open the doors and stay active. Returns the exit code if the machine could not start.
fn serve(io: Io, gpa: std.mem.Allocator, out: *Io.Writer, cfg: Config, ipc: bool, http: bool, embed: bool) !u8 {
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

// Zig tip: `{d:0>2}` pads a number with zeros to two digits. `@divTrunc` and `@mod` are the integer division and
// remainder; Zig asks for them by name on signed numbers because `/` and `%` are not defined for negative values.
/// Write a duration in milliseconds as `850 ms`, `12 s`, `3 min 05 s` or `2 h 05 min`.
fn writeDuration(out: *Io.Writer, ms: i64) !void {
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
fn printMachine(out: *Io.Writer, r: std.json.Value) !void {
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
        return try serve(io, gpa, out, cfg, ipc, http, embed);
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
fn runVia(io: Io, gpa: std.mem.Allocator, out: *Io.Writer, cfg: Config, cmd: Cmd) !?u8 {
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

// ---- stop, the machine as its own process (evevm) and the user interface (-u) ---------------------------------------

// Zig tip: `@splat(null)` fills an array with one value; here four empty places for the machines that this process
// opened (a machine is opened in the process by `serve` with `embed`). The array is read by `stop` on the thread of the
// prompt, and written by `serve` on the same thread, so it needs no lock.
var machines: [4]?*Machine = @splat(null);

/// Remember a machine that lives in this process, so that `stop` finds it. A place of a machine that stopped is reused.
fn register(m: *Machine) void {
    for (&machines) |*slot| {
        if (slot.* == null or slot.*.?.stopping.load(.acquire)) {
            slot.* = m;
            return;
        }
    }
}

// Zig tip: `for (&machines) |*slot|` walks the array by pointer; `slot.* orelse continue` reads the optional behind the
// pointer and skips a place that is empty. The function does three things in order of preference, and returns after the
// first that finds something to stop: the doors of this process, then a machine in another process.
/// `stop`: close the doors that this process opened and tell the scripts to stop, without leaving the prompt. When this
/// process has no door open, stop the machine of another process that answers (the one that `evevm` started).
pub fn stopMachines(io: Io, gpa: std.mem.Allocator, out: *Io.Writer, config_path: []const u8) !u8 {
    var closed: usize = 0;
    for (&machines) |*slot| {
        const m = slot.* orelse continue;
        if (m.stopping.load(.acquire)) continue;
        shutdown(m);
        closed += 1;
    }
    if (closed > 0) {
        try out.writeAll("stop: closed the doors of this process and told the scripts to stop\n");
        return 0;
    }
    const cfg = loadConfig(io, gpa, config_path);
    var name: []const u8 = "";
    if (send(io, gpa, cfg, .{}, message(gpa, "vm.stop", null), &name) != null) {
        try out.print("stop: stopped the machine of ipc {s}:{d} (http {s}:{d}) and its scripts\n", .{ cfg.domain, cfg.ipc_port, cfg.http_host, cfg.http_port });
        return 0;
    }
    try out.writeAll("stop: nothing to stop, no door is open here and no machine answers\n");
    return exit_unavailable;
}

/// Where the machine started by `evevm` writes its log: `<runtime>/eve-<domain>-<ipc_port>.log`.
fn logPath(gpa: std.mem.Allocator, cfg: Config) ![]u8 {
    return std.fmt.allocPrint(gpa, "{s}/eve-{s}-{d}.log", .{ runtime_dir, cfg.domain, cfg.ipc_port });
}

// Zig tip: `std.process.spawn` starts another program. `.stdin = .ignore` connects it to the null device, and a
// `.file` gives it an open file as its output: the machine has no terminal, so its log goes to a file. With
// `create_no_window` Windows gives the child no console window of its own, and it goes on running after this program
// has ended. The result is a `Child`; this function does not wait for it, because the machine is meant to stay.
/// Start `eve --listen --serve` as a new process, wait until its IPC door answers, and report. The machine runs on
/// its own: the prompt of the system comes back.
fn startDetached(io: Io, gpa: std.mem.Allocator, out: *Io.Writer, cfg: Config, config_path: ?[]const u8) !u8 {
    var name: []const u8 = "";
    const ipc_only: Cmd = .{ .local = true };
    const ping = message(gpa, "vm.ping", null);
    if (send(io, gpa, cfg, ipc_only, ping, &name) != null) {
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
        if (send(io, gpa, cfg, ipc_only, ping, &name) != null) {
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

const daemon_usage =
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
        _ = try handle(io, gpa, out, .{ .serve = true, .word = "stop", .config = config_path }, false);
        var name: []const u8 = "";
        var tries: usize = 0;
        while (tries < 50 and send(io, gpa, cfg, .{ .local = true }, message(gpa, "vm.ping", null), &name) != null) : (tries += 1) {
            Io.sleep(io, .fromMilliseconds(100), .awake) catch {};
        }
        return try startDetached(io, gpa, out, cfg, config_path);
    }
    return (try handle(io, gpa, out, .{ .serve = true, .word = word, .config = config_path }, false)) orelse 0;
}

// Zig tip: a failed call to `spawn` or `wait` is not worth stopping for here, so the result is a plain `bool`:
// "the helper program ran and ended". `&.{ ... }` with a value that is known only at run time (`url`) is an array
// built on the stack, which `spawn` reads and does not keep.
/// Run a helper program with no window and no input or output, and wait for it to end.
fn runQuiet(io: Io, argv: []const []const u8) bool {
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
