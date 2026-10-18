//! A client of the PostgreSQL frontend/backend protocol, version 3.0 (README.md section 5B): the protocol part of the Eve driver
//! for PostgreSQL. It knows the startup, the authentication (trust, cleartext password, md5 and SCRAM-SHA-256), the simple query
//! protocol and the error messages. It knows nothing about Eve values: the driver (`pgdriver.zig`) turns Eve values into SQL text
//! and the text of the rows into Eve values. No TLS yet: a server that asks for TLS is refused with a clear error.
const std = @import("std");
const Io = std.Io;
const net = Io.net;
const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;
const Sha256 = std.crypto.hash.sha2.Sha256;

pub const Error = error{ Connect, Auth, Protocol, Server, Unsupported } || std.mem.Allocator.Error || Io.Reader.Error || Io.Writer.Error;

// Zig tip: a `struct` groups named fields, and may hold functions (its methods) and constants; a field with a default value
// may be left out when a value is made with `.{ ... }`.
/// A column of a result: its name and the type number of PostgreSQL.
pub const Col = struct { name: []const u8, oid: u32 };

// Zig tip: `Result` relies on the same Zig feature as `Col` above: see the tip there.
/// The answer to a query: the columns and the rows of the last statement, the command tag, and the rows it changed.
pub const Result = struct {
    cols: []Col = &.{},
    /// Row after row; a null is NULL. All in the arena the call was given.
    rows: []const []const ?[]const u8 = &.{},
    tag: []const u8 = "",
    affected: u64 = 0,
};

// Zig tip: `Url` relies on the same Zig feature as `Col` above: see the tip there.
/// The URL of a connection: `postgres://user:password@host:port/database`.
pub const Url = struct {
    user: []const u8,
    password: []const u8,
    host: []const u8,
    port: u16,
    database: []const u8,
};

// Zig tip: the result type `?T` is an optional: a value or `null`. The caller must unwrap it (`if (x) |v|`, `orelse`), so a
// missing value can never be used by accident.
fn hexValue(c: u8) ?u8 {
    return std.fmt.charToDigit(c, 16) catch null;
}

// Zig tip: a password in a URL may hold characters that mean something in a URL (`@`, `:`, `/`), so they are written as `%40`,
// `%3A`, `%2F`. This reads them back. The result is allocated; the input is not changed.
fn percentDecode(a: std.mem.Allocator, s: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == '%' and i + 2 < s.len + 0 and hexValue(s[i + 1]) != null and hexValue(s[i + 2]) != null) {
            try out.append(a, hexValue(s[i + 1]).? * 16 + hexValue(s[i + 2]).?);
            i += 2;
        } else try out.append(a, s[i]);
    }
    return out.items;
}

// Zig tip: `parseUrl` relies on the same Zig feature as `hexValue` above: see the tip there.
/// Parse `postgres://user:password@host:port/database` (also `postgresql://`); the user and the database may be missing.
pub fn parseUrl(a: std.mem.Allocator, url: []const u8) ?Url {
    var rest: []const u8 = undefined;
    if (std.mem.startsWith(u8, url, "postgres://")) {
        rest = url["postgres://".len..];
    } else if (std.mem.startsWith(u8, url, "postgresql://")) {
        rest = url["postgresql://".len..];
    } else return null;
    var user: []const u8 = "postgres";
    var password: []const u8 = "";
    if (std.mem.lastIndexOfScalar(u8, rest, '@')) |at| {
        const cred = rest[0..at];
        rest = rest[at + 1 ..];
        if (std.mem.indexOfScalar(u8, cred, ':')) |c| {
            user = percentDecode(a, cred[0..c]) catch return null;
            password = percentDecode(a, cred[c + 1 ..]) catch return null;
        } else user = percentDecode(a, cred) catch return null;
    }
    var database: []const u8 = "";
    if (std.mem.indexOfScalar(u8, rest, '/')) |sl| {
        database = percentDecode(a, rest[sl + 1 ..]) catch return null;
        rest = rest[0..sl];
    }
    var host = rest;
    var port: u16 = 5432;
    if (std.mem.lastIndexOfScalar(u8, rest, ':')) |c| {
        host = rest[0..c];
        port = std.fmt.parseInt(u16, rest[c + 1 ..], 10) catch return null;
    }
    if (host.len == 0) host = "127.0.0.1";
    return .{ .user = user, .password = password, .host = host, .port = port, .database = if (database.len == 0) user else database };
}

// Zig tip: `Client` relies on the same Zig feature as `Col` above: see the tip there.
pub const Client = struct {
    io: Io,
    gpa: std.mem.Allocator,
    stream: net.Stream,
    rbuf: []u8,
    wbuf: []u8,
    reader: net.Stream.Reader,
    writer: net.Stream.Writer,
    /// The state letter of the last ReadyForQuery: I idle, T in a transaction, E failed transaction.
    status: u8 = 'I',
    /// `standard_conforming_strings` of the server: when off, a backslash in a text must be doubled.
    scs: bool = true,
    /// The last error of the server: SQL state and message.
    err_code: [5]u8 = "XX000".*,
    err_msg: [512]u8 = undefined,
    err_len: usize = 0,
    closed: bool = false,
    /// A transaction was begun for a job (the driver commits or rolls it back at the end of the job).
    job_tx: bool = false,

    // Zig tip: a function declared inside a struct whose first parameter is the struct (`self: *T`) is a method: `x.f()`
    // calls `f(&x)`.
    pub fn errorMessage(self: *const Client) []const u8 {
        return self.err_msg[0..self.err_len];
    }

    // Zig tip: `errorCode` relies on the same Zig feature as `errorMessage` above: see the tip there.
    pub fn errorCode(self: *const Client) []const u8 {
        return &self.err_code;
    }

    // Zig tip: `a orelse b` unwraps an optional: the value when there is one, else `b` (which may be `return` or
    // `continue`, leaving the function or the loop).
    fn keepError(self: *Client, body: []const u8) void {
        // fields: a letter and a text ending in a zero, until a zero letter
        var i: usize = 0;
        self.err_len = 0;
        while (i < body.len and body[i] != 0) {
            const f = body[i];
            const end = std.mem.indexOfScalarPos(u8, body, i + 1, 0) orelse body.len;
            const val = body[i + 1 .. end];
            if (f == 'C' and val.len == 5) @memcpy(&self.err_code, val[0..5]);
            if (f == 'M') {
                const n = @min(val.len, self.err_msg.len);
                @memcpy(self.err_msg[0..n], val[0..n]);
                self.err_len = n;
            }
            i = end + 1;
        }
    }

    // Zig tip: `Msg` relies on the same Zig feature as `Col` above: see the tip there.
    const Msg = struct { kind: u8, body: []u8 };

    // Zig tip: `readMsg` relies on the same Zig feature as `percentDecode` above: see the tip there.
    fn readMsg(self: *Client, a: std.mem.Allocator) Error!Msg {
        var head: [5]u8 = undefined;
        try self.reader.interface.readSliceAll(&head);
        const len = std.mem.readInt(i32, head[1..5], .big);
        if (len < 4 or len > 1 << 30) return error.Protocol;
        const body = try a.alloc(u8, @intCast(len - 4));
        try self.reader.interface.readSliceAll(body);
        return .{ .kind = head[0], .body = body };
    }

    // Zig tip: `send` relies on the same Zig feature as `percentDecode` above: see the tip there.
    fn send(self: *Client, kind: u8, body: []const u8) Error!void {
        var head: [5]u8 = undefined;
        head[0] = kind;
        std.mem.writeInt(u32, head[1..5], @intCast(body.len + 4), .big);
        try self.writer.interface.writeAll(&head);
        try self.writer.interface.writeAll(body);
        try self.writer.interface.flush();
    }

    // Zig tip: `connect` relies on the same Zig feature as `Client` above: see the tip there.
    /// Connect, log in, and wait for the first ReadyForQuery.
    pub fn connect(io: Io, gpa: std.mem.Allocator, url: Url) Error!*Client {
        const host = if (std.mem.eql(u8, url.host, "localhost")) "127.0.0.1" else url.host;
        const addr = net.IpAddress.parse(host, url.port) catch return error.Connect;
        const stream = addr.connect(io, .{ .mode = .stream }) catch return error.Connect;
        const c = try gpa.create(Client);
        errdefer gpa.destroy(c);
        const rbuf = try gpa.alloc(u8, 64 * 1024);
        errdefer gpa.free(rbuf);
        const wbuf = try gpa.alloc(u8, 16 * 1024);
        errdefer gpa.free(wbuf);
        c.* = .{ .io = io, .gpa = gpa, .stream = stream, .rbuf = rbuf, .wbuf = wbuf, .reader = stream.reader(io, rbuf), .writer = stream.writer(io, wbuf) };
        errdefer stream.close(io);
        try c.startup(url);
        return c;
    }

    // Zig tip: `f() catch x` uses `x` when `f` fails; `catch {}` drops the error on purpose. Zig refuses to compile an
    // error that nobody handles.
    pub fn close(self: *Client) void {
        if (!self.closed) {
            self.closed = true;
            self.send('X', "") catch {};
        }
        self.stream.close(self.io);
    }

    // Zig tip: `defer` runs its statement when the scope ends, by any path (a `return`, an error, the end of the block), so
    // a free or a close is written once, next to what it undoes.
    fn startup(self: *Client, url: Url) Error!void {
        var arena: std.heap.ArenaAllocator = .init(self.gpa);
        defer arena.deinit();
        const a = arena.allocator();
        var body: std.ArrayList(u8) = .empty;
        try body.appendSlice(a, &std.mem.toBytes(std.mem.nativeToBig(i32, 196608)));
        for ([_][]const u8{ "user", url.user, "database", url.database, "client_encoding", "UTF8", "application_name", "eve" }) |w| {
            try body.appendSlice(a, w);
            try body.append(a, 0);
        }
        try body.append(a, 0);
        var head: [4]u8 = undefined;
        std.mem.writeInt(u32, &head, @intCast(body.items.len + 4), .big);
        try self.writer.interface.writeAll(&head);
        try self.writer.interface.writeAll(body.items);
        try self.writer.interface.flush();
        while (true) {
            const m = try self.readMsg(a);
            switch (m.kind) {
                'R' => {
                    const code = std.mem.readInt(i32, m.body[0..4], .big);
                    switch (code) {
                        0 => {},
                        3 => try self.send('p', try std.mem.concat(a, u8, &.{ url.password, "\x00" })),
                        5 => {
                            var inner: [32]u8 = undefined;
                            md5hex(&inner, &.{ url.password, url.user });
                            var outer: [32]u8 = undefined;
                            md5hex(&outer, &.{ &inner, m.body[4..8] });
                            try self.send('p', try std.mem.concat(a, u8, &.{ "md5", &outer, "\x00" }));
                        },
                        10 => try self.scram(a, url, m.body[4..]),
                        else => return error.Unsupported,
                    }
                },
                'S' => {
                    const name = std.mem.sliceTo(m.body, 0);
                    const val = std.mem.sliceTo(m.body[name.len + 1 ..], 0);
                    if (std.mem.eql(u8, name, "standard_conforming_strings")) self.scs = std.mem.eql(u8, val, "on");
                },
                'K', 'N' => {},
                'E' => {
                    self.keepError(m.body);
                    return error.Auth;
                },
                'Z' => {
                    self.status = m.body[0];
                    return;
                },
                else => {},
            }
        }
    }

    // Zig tip: SCRAM-SHA-256 (RFC 5802 and 7677) proves that the client knows the password without sending it. The client
    // sends a nonce; the server answers with its own nonce, a salt and an iteration count; the client derives a key from the
    // password with PBKDF2, signs the whole exchange, and sends the proof; the server answers with its signature, which the
    // client checks. `std.crypto` has HMAC, SHA-256 and PBKDF2, so no code of ours does the arithmetic.
    fn scram(self: *Client, a: std.mem.Allocator, url: Url, mechanisms: []const u8) Error!void {
        if (std.mem.indexOf(u8, mechanisms, "SCRAM-SHA-256") == null) return error.Unsupported;
        var nonce_src: [18]u8 = undefined;
        const ns = Io.Timestamp.now(self.io, .real).toNanoseconds();
        var h = Sha256.init(.{});
        h.update(std.mem.asBytes(&ns));
        h.update(url.user);
        h.update(std.mem.asBytes(&self));
        var d: [32]u8 = undefined;
        h.final(&d);
        @memcpy(&nonce_src, d[0..18]);
        var nonce_buf: [24]u8 = undefined;
        const nonce = std.base64.standard.Encoder.encode(&nonce_buf, &nonce_src);
        const first_bare = try std.fmt.allocPrint(a, "n={s},r={s}", .{ url.user, nonce });
        const first = try std.fmt.allocPrint(a, "n,,{s}", .{first_bare});
        var init_body: std.ArrayList(u8) = .empty;
        try init_body.appendSlice(a, "SCRAM-SHA-256\x00");
        try init_body.appendSlice(a, &std.mem.toBytes(std.mem.nativeToBig(i32, @intCast(first.len))));
        try init_body.appendSlice(a, first);
        try self.send('p', init_body.items);
        const m1 = try self.readMsg(a);
        if (m1.kind == 'E') {
            self.keepError(m1.body);
            return error.Auth;
        }
        if (m1.kind != 'R' or std.mem.readInt(i32, m1.body[0..4], .big) != 11) return error.Protocol;
        const server_first = m1.body[4..];
        const client_final_body = scramFinal(a, url.password, first_bare, server_first, nonce) catch return error.Auth;
        try self.send('p', client_final_body.message);
        const m2 = try self.readMsg(a);
        if (m2.kind == 'E') {
            self.keepError(m2.body);
            return error.Auth;
        }
        if (m2.kind != 'R' or std.mem.readInt(i32, m2.body[0..4], .big) != 12) return error.Protocol;
        const v = m2.body[4..];
        if (!std.mem.startsWith(u8, v, "v=")) return error.Auth;
        if (!std.mem.eql(u8, v[2..], client_final_body.server_signature)) return error.Auth;
    }

    // Zig tip: `query` relies on the same Zig feature as `percentDecode` above: see the tip there.
    /// Run SQL (one statement or several, with no parameters) and read all the answers. A failure of the server is
    /// `error.Server`, with the SQL state and the message in `errorCode` and `errorMessage`.
    pub fn query(self: *Client, a: std.mem.Allocator, sql: []const u8) Error!Result {
        var q: std.ArrayList(u8) = .empty;
        try q.appendSlice(a, sql);
        try q.append(a, 0);
        try self.send('Q', q.items);
        var res: Result = .{};
        var rows: std.ArrayList([]const ?[]const u8) = .empty;
        var failed = false;
        while (true) {
            const m = try self.readMsg(a);
            switch (m.kind) {
                'T' => {
                    // a new result set starts: forget the rows of the one before
                    rows = .empty;
                    const n: usize = std.mem.readInt(u16, m.body[0..2], .big);
                    const cols = try a.alloc(Col, n);
                    var pos: usize = 2;
                    for (cols) |*c| {
                        const name = std.mem.sliceTo(m.body[pos..], 0);
                        pos += name.len + 1;
                        // table oid (4), column number (2), type oid (4), size (2), modifier (4), format (2)
                        const oid = std.mem.readInt(u32, m.body[pos + 6 ..][0..4], .big);
                        pos += 18;
                        c.* = .{ .name = name, .oid = oid };
                    }
                    res.cols = cols;
                },
                'D' => {
                    const n: usize = std.mem.readInt(u16, m.body[0..2], .big);
                    const row = try a.alloc(?[]const u8, n);
                    var pos: usize = 2;
                    for (row) |*cell| {
                        const len = std.mem.readInt(i32, m.body[pos..][0..4], .big);
                        pos += 4;
                        if (len < 0) {
                            cell.* = null;
                        } else {
                            cell.* = m.body[pos .. pos + @as(usize, @intCast(len))];
                            pos += @intCast(len);
                        }
                    }
                    try rows.append(a, row);
                },
                'C' => {
                    const tag = std.mem.sliceTo(m.body, 0);
                    res.tag = tag;
                    // the number at the end of the tag: INSERT 0 3, UPDATE 2, SELECT 5
                    if (std.mem.lastIndexOfScalar(u8, tag, ' ')) |sp| res.affected = std.fmt.parseInt(u64, tag[sp + 1 ..], 10) catch 0;
                    if (res.cols.len == 0) rows = .empty;
                },
                'E' => {
                    self.keepError(m.body);
                    failed = true;
                },
                'Z' => {
                    self.status = m.body[0];
                    if (failed) return error.Server;
                    res.rows = rows.items;
                    return res;
                },
                'S' => {
                    const name = std.mem.sliceTo(m.body, 0);
                    const val = std.mem.sliceTo(m.body[name.len + 1 ..], 0);
                    if (std.mem.eql(u8, name, "standard_conforming_strings")) self.scs = std.mem.eql(u8, val, "on");
                },
                else => {},
            }
        }
    }
};

// Zig tip: a plain function: the types of the parameters and of the result are written out, and Zig has no default
// arguments, so a call always passes every parameter.
fn md5hex(out: *[32]u8, parts: []const []const u8) void {
    var h = std.crypto.hash.Md5.init(.{});
    for (parts) |p| h.update(p);
    var d: [16]u8 = undefined;
    h.final(&d);
    out.* = std.fmt.bytesToHex(d, .lower);
}

// Zig tip: `ScramFinal` relies on the same Zig feature as `Col` above: see the tip there.
const ScramFinal = struct { message: []const u8, server_signature: []const u8 };

// Zig tip: this function holds all the arithmetic of the exchange, with no network, so a test can feed it the example of
// RFC 7677 and compare the proof byte for byte. Everything is allocated in the arena of the caller.
/// The client-final message and the signature the server must answer with.
fn scramFinal(a: std.mem.Allocator, password: []const u8, first_bare: []const u8, server_first: []const u8, nonce: []const u8) !ScramFinal {
    var r: ?[]const u8 = null;
    var salt_b64: ?[]const u8 = null;
    var iter: ?u32 = null;
    var it = std.mem.splitScalar(u8, server_first, ',');
    while (it.next()) |part| {
        if (std.mem.startsWith(u8, part, "r=")) r = part[2..];
        if (std.mem.startsWith(u8, part, "s=")) salt_b64 = part[2..];
        if (std.mem.startsWith(u8, part, "i=")) iter = std.fmt.parseInt(u32, part[2..], 10) catch null;
    }
    const server_nonce = r orelse return error.Protocol;
    if (!std.mem.startsWith(u8, server_nonce, nonce)) return error.Protocol;
    const salt = try a.alloc(u8, try std.base64.standard.Decoder.calcSizeForSlice(salt_b64 orelse return error.Protocol));
    try std.base64.standard.Decoder.decode(salt, salt_b64.?);
    var salted: [32]u8 = undefined;
    try std.crypto.pwhash.pbkdf2(&salted, password, salt, iter orelse return error.Protocol, HmacSha256);
    var client_key: [32]u8 = undefined;
    HmacSha256.create(&client_key, "Client Key", &salted);
    var stored: [32]u8 = undefined;
    Sha256.hash(&client_key, &stored, .{});
    const without_proof = try std.fmt.allocPrint(a, "c=biws,r={s}", .{server_nonce});
    const auth_message = try std.fmt.allocPrint(a, "{s},{s},{s}", .{ first_bare, server_first, without_proof });
    var signature: [32]u8 = undefined;
    HmacSha256.create(&signature, auth_message, &stored);
    var proof: [32]u8 = undefined;
    for (&proof, client_key, signature) |*p, ck, sg| p.* = ck ^ sg;
    var proof_b64: [44]u8 = undefined;
    const proof_text = std.base64.standard.Encoder.encode(&proof_b64, &proof);
    var server_key: [32]u8 = undefined;
    HmacSha256.create(&server_key, "Server Key", &salted);
    var server_sig: [32]u8 = undefined;
    HmacSha256.create(&server_sig, auth_message, &server_key);
    var sig_b64: [44]u8 = undefined;
    const sig_text = std.base64.standard.Encoder.encode(&sig_b64, &server_sig);
    return .{
        .message = try std.fmt.allocPrint(a, "{s},p={s}", .{ without_proof, proof_text }),
        .server_signature = try a.dupe(u8, sig_text),
    };
}

// Zig tip: a `test` block is compiled only by `zig build test`; `try std.testing.expect…` fails the test, with the values,
// when a check is false.
test "SCRAM-SHA-256 gives the proof of RFC 7677" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const f = try scramFinal(arena.allocator(), "pencil", "n=user,r=rOprNGfwEbeRWgbNEkqO", "r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096", "rOprNGfwEbeRWgbNEkqO");
    try std.testing.expectEqualStrings("c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=", f.message);
    try std.testing.expectEqualStrings("6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=", f.server_signature);
}

// Zig tip: test "a connection URL" relies on the same Zig feature as test "SCRAM-SHA-256 gives the proof of RFC 7677"
// above: see the tip there.
test "a connection URL" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const u = parseUrl(arena.allocator(), "postgres://eve:p%40ss@db.example.com:5433/shop").?;
    try std.testing.expectEqualStrings("eve", u.user);
    try std.testing.expectEqualStrings("p@ss", u.password);
    try std.testing.expectEqualStrings("db.example.com", u.host);
    try std.testing.expectEqual(@as(u16, 5433), u.port);
    try std.testing.expectEqualStrings("shop", u.database);
    const v = parseUrl(arena.allocator(), "postgresql://localhost").?;
    try std.testing.expectEqual(@as(u16, 5432), v.port);
    try std.testing.expectEqualStrings("postgres", v.database);
    try std.testing.expect(parseUrl(arena.allocator(), "sqlite://x.db") == null);
}
