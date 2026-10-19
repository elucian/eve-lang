//! @eve-module netlib: native module `net`, TCP sockets for Eve code (classes Listener and Socket)
//! @spec spec/library/net.md, spec/library/registry.md
//! @feature F-NET-02, F-NET-03
//! @decision D-189
//! @tests test/level6/f09_net
//! A waiting call (accept, read) runs on a helper thread when the run has tasks, and gives the baton to the other tasks
//! between two looks (`Interp.waitFor`), so a server and its clients can be tasks of one script. Signatures: lib/sys/net.eve.
const std = @import("std");
const Io = std.Io;
const net = Io.net;
const ast = @import("evecm").ast;
const interp = @import("interp.zig");

const Node = ast.Node;
const Interp = interp.Interp;
const Value = interp.Value;
const Class = interp.Class;
const Object = interp.Object;
const Signal = interp.Signal;
const err_argument = interp.err_argument;
const err_io = interp.err_io;

/// The longest line or block that `read_line!` and `read_exact!` can hold.
const buffer_size = 64 * 1024;

// @eve-impl state of one open TCP connection (an Eve `Socket`); the Eve object keeps its index in `Interp.net_conns`
pub const Conn = struct {
    stream: net.Stream,
    reader: net.Stream.Reader,
    rbuf: []u8,
    open: bool = true,
    peer: []const u8 = "",
    /// `set_timeout(ms)`: a read that waits longer fails with `$err_timeout`; 0 waits for ever (TD-27).
    timeout_ms: i64 = 0,
    /// A read timed out: its helper thread still holds the reader, so the socket can be written and dropped, never read or freed.
    abandoned: bool = false,
};

// @eve-impl state of one listening socket (an Eve `Listener`)
pub const Listen = struct {
    server: net.Server,
    open: bool = true,
    port: u16 = 0,
    /// An `accept!` waits on a helper thread; `close()` must not free the socket under it (Zig panics) but wake it.
    pending: bool = false,
    closing: bool = false,
};

// @eve-impl run a blocking call without stopping the other tasks: in a run with tasks, on a helper thread that is polled
// with `Interp.waitFor` (the baton goes to the other tasks between two looks); alone in the run, directly.
// The helper thread is needed because the sockets of Zig's `std.Io` on Windows are not Winsock handles (no `WSAPoll`).
// @invariant `ctx` and the result live in `it.a` memory until the thread ends; a cancelled task leaves the thread to finish
// @see spec/library/net.md#waiting
fn offload(it: *Interp, comptime R: type, comptime func: anytype, ctx: anytype, timeout_ms: i64) Signal!?R {
    const io = it.io orelse return it.fail("net: no input/output handle", .{});
    if (it.sched == null and timeout_ms <= 0) return func(ctx);
    const Job = struct {
        done: std.atomic.Value(bool) = .init(false),
        result: R = undefined,
        ctx: @TypeOf(ctx),
        sched: ?*@import("task.zig").Sched,
        task: ?*@import("task.zig").Task,
    };
    const job = try it.a.create(Job);
    job.* = .{ .ctx = ctx, .sched = it.sched, .task = it.me };
    const Run = struct {
        fn main(j: *Job) void {
            j.result = func(j.ctx);
            j.done.store(true, .release);
            if (j.sched) |sc| sc.ioDone(j.task.?);
        }
    };
    const deadline: i64 = if (timeout_ms > 0) Io.Timestamp.now(io, .awake).toMilliseconds() + timeout_ms else 0;
    const me = it.me;
    var old_timer = false;
    var old_wake: i64 = 0;
    if (me) |m| {
        old_timer = m.timer;
        old_wake = m.wake_at;
        m.io_ready.store(false, .release);
        m.wait = .io;
        if (timeout_ms > 0 and !(m.timer and m.wake_at < deadline)) {
            m.timer = true;
            m.wake_at = deadline;
        }
    }
    const th = std.Thread.spawn(.{}, Run.main, .{job}) catch {
        if (me) |m| m.wait = .none;
        return it.fail("net: cannot start a helper thread", .{});
    };
    th.detach();
    var timed_out = false;
    while (true) {
        if (me) |m| m.io_ready.store(false, .release);
        if (job.done.load(.acquire)) break;
        if (me) |m| if (m.cancel != .none) break;
        if (timeout_ms > 0 and Io.Timestamp.now(io, .awake).toMilliseconds() >= deadline) {
            timed_out = true;
            break;
        }
        if (it.sched) |sc| sc.yield(me.?) else Io.sleep(io, .fromMilliseconds(1), .awake) catch {};
    }
    if (me) |m| {
        m.wait = .none;
        m.timer = old_timer;
        m.wake_at = old_wake;
    }
    try it.checkCancel();
    if (timed_out) return null;
    const result = job.result;
    it.a.destroy(job);
    return result;
}

const AcceptCtx = struct { server: *net.Server, io: Io };

fn acceptNow(c: AcceptCtx) net.Server.AcceptError!net.Stream {
    return c.server.accept(c.io);
}

fn fillNow(r: *Io.Reader) Io.Reader.Error!void {
    return r.fillMore();
}

fn listenerClass(it: *Interp) Signal!*Class {
    const b = it.base();
    if (b.net_listener_class == null) {
        const cls = try it.a.create(Class);
        cls.* = .{ .name = "Listener" };
        b.net_listener_class = cls;
    }
    return b.net_listener_class.?;
}

fn socketClass(it: *Interp) Signal!*Class {
    const b = it.base();
    if (b.net_socket_class == null) {
        const cls = try it.a.create(Class);
        cls.* = .{ .name = "Socket" };
        b.net_socket_class = cls;
    }
    return b.net_socket_class.?;
}

// @eve-impl is the value a Listener or a Socket of the `net` module
pub fn isNet(it: *Interp, v: Value) bool {
    if (v != .object or v.object.class == null) return false;
    const b = it.base();
    return v.object.class == b.net_listener_class or v.object.class == b.net_socket_class;
}

fn newSocket(it: *Interp, stream: net.Stream, peer: []const u8) Signal!Value {
    const b = it.base();
    const c = try it.a.create(Conn);
    const rbuf = try it.a.alloc(u8, buffer_size);
    c.* = .{ .stream = stream, .reader = undefined, .rbuf = rbuf, .peer = try it.a.dupe(u8, peer) };
    c.reader = stream.reader(it.io.?, rbuf);
    try b.net_conns.append(it.a, c);
    const obj = try it.newObject();
    obj.class = try socketClass(it);
    try it.setField(obj, "handle", .{ .int = @intCast(b.net_conns.items.len - 1) });
    return .{ .object = obj };
}

fn connOf(it: *Interp, o: *Object) *Conn {
    return it.base().net_conns.items[@intCast(Interp.intOf(Interp.fieldOf(o, "handle").?))];
}

fn listenOf(it: *Interp, o: *Object) *Listen {
    return it.base().net_listeners.items[@intCast(Interp.intOf(Interp.fieldOf(o, "handle").?))];
}

fn textArg(it: *Interp, args: []const *const Node, index: usize, what: []const u8) Signal![]const u8 {
    if (args.len <= index) return it.failWith(err_argument, "{s}: argument {d} is missing", .{ what, index + 1 });
    const v = try it.eval(args[index]);
    if (v != .str) return it.failWith(err_argument, "{s}: argument {d} is a String", .{ what, index + 1 });
    return v.str;
}

fn intArg(it: *Interp, args: []const *const Node, index: usize, what: []const u8) Signal!i64 {
    if (args.len <= index) return it.failWith(err_argument, "{s}: argument {d} is missing", .{ what, index + 1 });
    const v = try it.eval(args[index]);
    if (!Interp.isInt(v)) return it.failWith(err_argument, "{s}: argument {d} is a whole number", .{ what, index + 1 });
    return Interp.intOf(v);
}

// @eve-fn net.listen!, net.connect!
// @spec spec/library/net.md#functions
// @feature F-NET-02
pub fn netModule(it: *Interp, name: []const u8, _: []const *const Node, args: []const *const Node) Signal!?Value {
    const eql = std.mem.eql;
    const io = it.io orelse return it.fail("net: no input/output handle", .{});
    if (eql(u8, name, "listen!")) {
        const host = try textArg(it, args, 0, "net.listen!");
        const port = try intArg(it, args, 1, "net.listen!");
        if (port < 0 or port > 65535) return it.failWith(err_argument, "net.listen!: a port from 0 to 65535", .{});
        const addr = net.IpAddress.parse(host, @intCast(port)) catch return it.failWith(err_argument, "net.listen!: '{s}' is not an IP address", .{host});
        const server = addr.listen(io, .{ .reuse_address = true }) catch |e| return it.failWith(err_io, "net.listen! {s}:{d}: {s}", .{ host, port, @errorName(e) });
        const b = it.base();
        const l = try it.a.create(Listen);
        l.* = .{ .server = server, .port = server.socket.address.getPort() };
        try b.net_listeners.append(it.a, l);
        const obj = try it.newObject();
        obj.class = try listenerClass(it);
        try it.setField(obj, "handle", .{ .int = @intCast(b.net_listeners.items.len - 1) });
        return .{ .object = obj };
    }
    if (eql(u8, name, "connect!")) {
        const host = try textArg(it, args, 0, "net.connect!");
        const port = try intArg(it, args, 1, "net.connect!");
        if (port < 1 or port > 65535) return it.failWith(err_argument, "net.connect!: a port from 1 to 65535", .{});
        const addr = net.IpAddress.parse(host, @intCast(port)) catch return it.failWith(err_argument, "net.connect!: '{s}' is not an IP address", .{host});
        const stream = addr.connect(io, .{ .mode = .stream }) catch |e| return it.failWith(err_io, "net.connect! {s}:{d}: {s}", .{ host, port, @errorName(e) });
        return try newSocket(it, stream, try std.fmt.allocPrint(it.t, "{s}:{d}", .{ host, port }));
    }
    return null;
}

// @eve-impl a read that timed out: the helper thread still waits in the reader, so the socket is abandoned
// @spec spec/library/net.md#time-outs
fn timedOut(it: *Interp, c: *Conn, name: []const u8) Signal {
    c.abandoned = true;
    return it.failWith(41, "{s}: Time-out after {d} ms", .{ name, c.timeout_ms });
}

// @eve-fn Listener.accept!, Listener.port, Listener.close, Socket.read_line!, Socket.read!, Socket.read_exact!, Socket.write
// @eve-fn Socket.close, Socket.is_open, Socket.peer
// @spec spec/library/net.md#functions
// @feature F-NET-02
pub fn call(it: *Interp, o: *Object, name: []const u8, args: []const *const Node) Signal!Value {
    const eql = std.mem.eql;
    const io = it.io orelse return it.fail("net: no input/output handle", .{});
    if (o.class == it.base().net_listener_class) {
        const l = listenOf(it, o);
        if (eql(u8, name, "port")) return .{ .int = l.port };
        if (eql(u8, name, "close")) {
            if (!l.open or l.closing) return .nil;
            if (!l.pending) {
                l.server.deinit(io);
                l.open = false;
                return .nil;
            }
            // @eve-impl a listener with an accept in flight: ask it to end, and wake it with a connection to ourselves; the
            // accept! call frees the socket when it returns (closing the socket under the helper thread panics in Zig 0.16)
            l.closing = true;
            if (net.IpAddress.parse("127.0.0.1", l.port)) |addr| {
                if (addr.connect(io, .{ .mode = .stream })) |wake| wake.close(io) else |_| {}
            } else |_| {}
            return .nil;
        }
        if (eql(u8, name, "accept!")) {
            if (!l.open or l.closing) return it.failWith(err_io, "accept!: the listener is closed", .{});
            l.pending = true;
            const got = (try offload(it, net.Server.AcceptError!net.Stream, acceptNow, AcceptCtx{ .server = &l.server, .io = io }, 0)).?;
            l.pending = false;
            if (l.closing) {
                if (got) |extra| extra.close(io) else |_| {}
                l.server.deinit(io);
                l.open = false;
                return it.failWith(err_io, "accept!: the listener is closed", .{});
            }
            const stream = got catch |e| return it.failWith(err_io, "accept!: {s}", .{@errorName(e)});
            return try newSocket(it, stream, "client");
        }
        return it.fail("a Listener has no method '{s}'", .{name});
    }
    const c = connOf(it, o);
    if (eql(u8, name, "is_open")) return .{ .bool = c.open };
    if (eql(u8, name, "peer")) return try it.newStr(c.peer);
    if (eql(u8, name, "close")) {
        // an abandoned socket has a helper thread in its reader: closing under it panics, so it is only forgotten
        if (c.open and !c.abandoned) c.stream.close(io);
        c.open = false;
        return .nil;
    }
    if (eql(u8, name, "set_timeout")) {
        const ms = try intArg(it, args, 0, name);
        if (ms < 0) return it.failWith(err_argument, "set_timeout: a time-out of 0 or more milliseconds", .{});
        c.timeout_ms = ms;
        return .nil;
    }
    if (!c.open) return it.failWith(err_io, "{s}: the socket is closed", .{name});
    if (eql(u8, name, "write")) {
        const text = try textArg(it, args, 0, "write");
        var wbuf: [4096]u8 = undefined;
        var w = c.stream.writer(io, &wbuf);
        w.interface.writeAll(text) catch return it.failWith(err_io, "write: the connection is lost", .{});
        w.interface.flush() catch return it.failWith(err_io, "write: the connection is lost", .{});
        return .nil;
    }
    if (c.abandoned and !eql(u8, name, "write")) return it.failWith(41, "{s}: an earlier read timed out; the socket can only be written and closed", .{name});
    const r = &c.reader.interface;
    if (eql(u8, name, "read_line!")) {
        while (true) {
            const have = r.buffered();
            if (std.mem.indexOfScalar(u8, have, '\n')) |at| {
                const line = std.mem.trimEnd(u8, have[0..at], "\r");
                const v = try it.newStr(line);
                r.toss(at + 1);
                return v;
            }
            if (have.len >= buffer_size) return it.failWith(err_io, "read_line!: the line is longer than {d} bytes", .{buffer_size});
            const filled = (try offload(it, Io.Reader.Error!void, fillNow, r, c.timeout_ms)) orelse return timedOut(it, c, name);
            filled catch |e| switch (e) {
                error.EndOfStream => {
                    if (have.len == 0) return .nil;
                    const v = try it.newStr(std.mem.trimEnd(u8, have, "\r"));
                    r.tossBuffered();
                    return v;
                },
                error.ReadFailed => return it.failWith(err_io, "read_line!: the connection is lost", .{}),
            };
        }
    }
    if (eql(u8, name, "read!") or eql(u8, name, "read_exact!")) {
        const want = try intArg(it, args, 0, name);
        if (want < 0 or want > buffer_size) return it.failWith(err_argument, "{s}: a number of bytes from 0 to {d}", .{ name, buffer_size });
        const n: usize = @intCast(want);
        const exact = name[5] == 'e';
        while (true) {
            const have = r.buffered();
            if (have.len >= n or (!exact and have.len > 0)) {
                const take = @min(n, have.len);
                const v = try it.newStr(have[0..take]);
                r.toss(take);
                return v;
            }
            const filled = (try offload(it, Io.Reader.Error!void, fillNow, r, c.timeout_ms)) orelse return timedOut(it, c, name);
            filled catch |e| switch (e) {
                error.EndOfStream => {
                    if (exact) return it.failWith(err_io, "read_exact!: the stream ends before {d} bytes", .{n});
                    return try it.newStr("");
                },
                error.ReadFailed => return it.failWith(err_io, "{s}: the connection is lost", .{name}),
            };
        }
    }
    return it.fail("a Socket has no method '{s}'", .{name});
}
