//! The wire of the machine: what both doors speak. JSON-RPC 2.0 messages, the HTTP answers of the
//! web door, and the calls that a client makes to the IPC door and to the HTTP door of a machine
//! (spec/library/machine.md). Part of evecm: the machine, the command line and the user interface
//! share it, and none of them needs the interpreter to use it.
const std = @import("std");
const Io = std.Io;
const net = Io.net;

pub fn ok(a: std.mem.Allocator, id: std.json.Value, result: anytype) []const u8 {
    return std.json.Stringify.valueAlloc(a, .{ .jsonrpc = "2.0", .id = id, .result = result }, .{}) catch "";
}

pub fn fail(a: std.mem.Allocator, id: std.json.Value, code: i32, reason: []const u8) []const u8 {
    return std.json.Stringify.valueAlloc(a, .{ .jsonrpc = "2.0", .id = id, .@"error" = .{ .code = code, .message = reason } }, .{}) catch "";
}

/// A message `{"jsonrpc":"2.0","id":1,"method":…,"params":…}` (allocated in `gpa`).
pub fn message(gpa: std.mem.Allocator, method: []const u8, params: anytype) []const u8 {
    return std.json.Stringify.valueAlloc(gpa, .{ .jsonrpc = "2.0", .id = 1, .method = method, .params = params }, .{}) catch "";
}

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

/// True when the request path may be joined to the web folder.
pub fn safePath(path: []const u8) bool {
    if (path.len == 0 or path[0] != '/') return false;
    if (std.mem.indexOfAny(u8, path, "\\:\x00") != null) return false;
    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |p| if (std.mem.eql(u8, p, "..")) return false;
    return true;
}

/// Write one HTTP/1.1 answer and let the caller close the connection.
pub fn respond(w: *Io.Writer, status: []const u8, kind: []const u8, body: []const u8) void {
    w.print("HTTP/1.1 {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{ status, kind, body.len }) catch return;
    w.writeAll(body) catch return;
    w.flush() catch {};
}

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

pub fn respondText(w: *Io.Writer, status: []const u8, body: []const u8) bool {
    respond(w, status, "text/plain; charset=utf-8", body);
    return false;
}

/// True when something answers on the IPC socket of this configuration.
pub fn ipcAlive(io: Io, socket: []const u8) bool {
    const ua = net.UnixAddress.init(socket) catch return false;
    const s = ua.connect(io) catch return false;
    s.close(io);
    return true;
}

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
    const rbuf = gpa.alloc(u8, 16 << 20) catch return null;
    var reader = stream.reader(io, rbuf);
    while (true) {
        const line = (reader.interface.takeDelimiter('\n') catch return null) orelse return null;
        const text = std.mem.trim(u8, line, "\r\n ");
        if (text.len == 0 or std.mem.startsWith(u8, text, "{\"jsonrpc\":\"2.0\",\"method\"")) continue;
        return gpa.dupe(u8, text) catch null;
    }
}

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
