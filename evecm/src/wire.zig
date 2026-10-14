//! The wire of the machine: what both doors speak. JSON-RPC 2.0 messages, the HTTP answers of the
//! web door, and the calls that a client makes to the IPC door and to the HTTP door of a machine
//! (spec/library/machine.md). Part of evecm: the machine, the command line and the user interface
//! share it, and none of them needs the interpreter to use it.
const std = @import("std");
const Io = std.Io;
const net = Io.net;

// Zig tip: `anytype` takes a value of any type, here a string or an anonymous struct, and `std.json.Stringify`
// turns it into JSON by looking at the fields (at compile time). A field called `error` is a keyword, so it is
// written `@"error"`.
pub fn ok(a: std.mem.Allocator, id: std.json.Value, result: anytype) []const u8 {
    return std.json.Stringify.valueAlloc(a, .{ .jsonrpc = "2.0", .id = id, .result = result }, .{}) catch "";
}

// Zig tip: `fail` relies on the same features as `ok` above: see the tip there.
pub fn fail(a: std.mem.Allocator, id: std.json.Value, code: i32, reason: []const u8) []const u8 {
    return std.json.Stringify.valueAlloc(a, .{ .jsonrpc = "2.0", .id = id, .@"error" = .{ .code = code, .message = reason } }, .{}) catch "";
}

// Zig tip: `message` relies on the same features as `ok` above (`anytype` and `std.json.Stringify`): see the tip there.
/// A message `{"jsonrpc":"2.0","id":1,"method":…,"params":…}` (allocated in `gpa`).
pub fn message(gpa: std.mem.Allocator, method: []const u8, params: anytype) []const u8 {
    return std.json.Stringify.valueAlloc(gpa, .{ .jsonrpc = "2.0", .id = 1, .method = method, .params = params }, .{}) catch "";
}

// Zig tip: `[_][2][]const u8{ ... }` is an array of pairs of texts whose length the compiler counts (`_`). A table in
// the code is a constant, built at compile time; the loop returns at the first extension that matches.
/// The type of a file for the `Content-Type` header, from its extension.
pub fn contentType(path: []const u8) []const u8 {
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
pub fn safePath(path: []const u8) bool {
    if (path.len == 0 or path[0] != '/') return false;
    if (std.mem.indexOfAny(u8, path, "\\:\x00") != null) return false;
    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |p| if (std.mem.eql(u8, p, "..")) return false;
    return true;
}

// Zig tip: `catch return` in a function that returns `void` gives up quietly: a browser that closed the connection
// is not an error of the machine. CR LF is the line end that HTTP requires.
/// Write one HTTP/1.1 answer and let the caller close the connection.
pub fn respond(w: *Io.Writer, status: []const u8, kind: []const u8, body: []const u8) void {
    w.print("HTTP/1.1 {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{ status, kind, body.len }) catch return;
    w.writeAll(body) catch return;
    w.flush() catch {};
}

// Zig tip: an error set can be declared by hand (`error{TooLarge}`) and merged with another one with `||`: the
// function may fail with the errors of the reader or with its own. `std.fmt.parseInt(usize, text, 16)` reads the
// hexadecimal size of a chunk; what follows a `;` on that line is an extension that a server may ignore.
/// The body of a request sent with `Transfer-Encoding: chunked`: chunks `<size in hex>\r\n<bytes>\r\n`, ended by a
/// chunk of size 0 and the empty line after the trailer headers (RFC 9112, section 7.1). At most `limit` bytes.
pub fn readChunked(r: *Io.Reader, a: std.mem.Allocator, limit: usize) (error{ TooLarge, BadChunk } || Io.Reader.Error || Io.Reader.DelimiterError || std.mem.Allocator.Error)![]u8 {
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
pub fn respondText(w: *Io.Writer, status: []const u8, body: []const u8) bool {
    respond(w, status, "text/plain; charset=utf-8", body);
    return false;
}

// Zig tip: a connection that is opened only to test the door is closed at once; `catch return false` turns every
// error of `connect` (no file, nobody listening) into the answer "no".
/// True when something answers on the IPC socket of this configuration.
pub fn ipcAlive(io: Io, socket: []const u8) bool {
    const ua = net.UnixAddress.init(socket) catch return false;
    const s = ua.connect(io) catch return false;
    s.close(io);
    return true;
}

// Zig tip: a client connects, sends one message and reads until the server closes the connection: `allocRemaining`
// reads to the end of the stream into memory, with a limit. The answer is `null` when nobody listens: the caller
// decides what that means (`-loc` falls back to a local run, `-rem` fails).
/// Send one JSON-RPC message on the IPC socket; the answer, or null when no machine listens.
pub fn ipcCall(io: Io, gpa: std.mem.Allocator, socket: []const u8, request: []const u8) ?[]const u8 {
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
pub fn httpCall(io: Io, gpa: std.mem.Allocator, host: []const u8, port: u16, request: []const u8) ?[]const u8 {
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
