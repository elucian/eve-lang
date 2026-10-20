//! The lasting doors of the machine (level 6, `spec/library/machine.md#lasting-doors`): one connection carries many
//! JSON-RPC messages both ways. The IPC door keeps its connection open, and the stdio door (`eve --stdio`) is the
//! standard input and output of a machine that an IDE starts as its child: on this computer, or at the other end of an
//! SSH link (`ssh host eve --stdio`), where SSH does the login. On these doors the machine also sends notifications
//! (`vm.output`: the text of a run while it runs), keeps sessions (`vm.open`, `vm.eval`, `vm.close`) and runs commands
//! of the operating system (`vm.shell`). The HTTP door has none of these until the login of the machine (F-NET-06).
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const vm = @import("vm.zig");
const machine = @import("machine.zig");
const wire = @import("evecm").wire;
const config = @import("evecm").config;

const ok = wire.ok;
const fail = wire.fail;

/// The shell of `vm.shell` and of the REPL command `shell`; `main` sets it once from the environment (`SHELL`, else
/// `COMSPEC` on Windows).
pub var shell_path: []const u8 = if (builtin.os.tag == .windows) "cmd.exe" else "/bin/sh";

const long_gpa = std.heap.smp_allocator;

// ---- the channel ------------------------------------------------------------------------------------------------

/// One lasting connection: the answers and the notifications of the machine go out through it, one line each.
pub const Channel = struct {
    io: Io,
    w: *Io.Writer,
    lock: Io.Mutex = .init,
    active: std.atomic.Value(usize) = .init(0),
    /// The slow requests (a run, an eval, a shell command) take a ticket when they arrive and wait for their `turn`, so
    /// they run in the order the client sent them; `closing` makes the ones still waiting give up after a `stop`.
    turn: std.atomic.Value(usize) = .init(0),
    closing: std.atomic.Value(bool) = .init(false),
    /// The session of `vm.eval` without a `session` param: made by the first such eval, closed with the channel.
    session: ?u32 = null,

    /// Write one message on the channel.
    pub fn send(ch: *Channel, line: []const u8) void {
        ch.lock.lockUncancelable(ch.io);
        defer ch.lock.unlock(ch.io);
        ch.w.writeAll(line) catch return;
        ch.w.writeAll("\n") catch return;
        ch.w.flush() catch {};
    }

    /// A notification: a message with a method and no id (JSON-RPC 2.0).
    pub fn notify(ch: *Channel, method: []const u8, params: anytype) void {
        const text = std.json.Stringify.valueAlloc(long_gpa, .{ .jsonrpc = "2.0", .method = method, .params = params }, .{}) catch return;
        defer long_gpa.free(text);
        ch.send(text);
    }
};

/// A writer whose text goes to a channel as `vm.output` notifications of request `id`, a batch of whole lines at a time.
pub const OutStream = struct {
    ch: *Channel,
    a: std.mem.Allocator,
    id: std.json.Value,
    pending: std.ArrayList(u8) = .empty,
    interface: Io.Writer,

    pub fn init(ch: *Channel, a: std.mem.Allocator, id: std.json.Value) OutStream {
        return .{ .ch = ch, .a = a, .id = id, .interface = .{ .vtable = &.{ .drain = drain }, .buffer = &.{} } };
    }

    fn drain(w: *Io.Writer, data: []const []const u8, splat: usize) Io.Writer.Error!usize {
        const s: *OutStream = @alignCast(@fieldParentPtr("interface", w));
        var n: usize = 0;
        for (data[0 .. data.len - 1]) |d| {
            s.pending.appendSlice(s.a, d) catch return error.WriteFailed;
            n += d.len;
        }
        const last = data[data.len - 1];
        for (0..splat) |_| s.pending.appendSlice(s.a, last) catch return error.WriteFailed;
        n += last.len * splat;
        if (std.mem.lastIndexOfScalar(u8, s.pending.items, '\n')) |k| {
            s.ch.notify("vm.output", .{ .id = s.id, .text = s.pending.items[0 .. k + 1] });
            s.pending.replaceRange(s.a, 0, k + 1, &.{}) catch {};
        }
        return n;
    }

    /// Send the text that waits for its line end (the last line of a run without a newline).
    pub fn finish(s: *OutStream) void {
        if (s.pending.items.len == 0) return;
        s.ch.notify("vm.output", .{ .id = s.id, .text = s.pending.items });
        s.pending.clearRetainingCapacity();
    }
};

// ---- serving a lasting connection ----------------------------------------------------------------------------------

/// Serve a lasting connection: one message per line, answers and notifications on `ch`. Returns true on `stop`.
pub fn serveLines(m: *machine.Machine, r: *Io.Reader, ch: *Channel, door: []const u8) bool {
    var stop: std.atomic.Value(bool) = .init(false);
    var tickets: usize = 0;
    while (!stop.load(.acquire)) {
        const line = (r.takeDelimiter('\n') catch break) orelse break;
        const text = std.mem.trim(u8, line, " \r\t");
        if (text.len == 0) continue;
        const copy = long_gpa.dupe(u8, text) catch break;
        _ = ch.active.fetchAdd(1, .acq_rel);
        if (isQuick(copy)) {
            request(m, ch, door, copy, &stop);
            continue;
        }
        const ticket = tickets;
        tickets += 1;
        const t = std.Thread.spawn(.{}, slowRequest, .{ m, ch, door, copy, &stop, ticket }) catch {
            slowRequest(m, ch, door, copy, &stop, ticket);
            continue;
        };
        t.detach();
    }
    // a stop cancels what still runs; the requests in flight then end and the channel can close (3 s at most)
    if (stop.load(.acquire)) {
        ch.closing.store(true, .release);
        vm.cancelAll();
    }
    var waited: usize = 0;
    while (ch.active.load(.acquire) > 0 and waited < 3000) : (waited += 10) m.io.sleep(.fromMilliseconds(10), .awake) catch {};
    // the default session of the channel goes with it
    if (ch.session) |sid| {
        m.run_lock.lockUncancelable(m.io);
        defer m.run_lock.unlock(m.io);
        _ = m.sessions.close(m.io, sid);
    }
    return stop.load(.acquire);
}

/// One request of a lasting connection: run it in an arena of its own and send the answer.
fn request(m: *machine.Machine, ch: *Channel, door: []const u8, body: []u8, stop: *std.atomic.Value(bool)) void {
    defer {
        long_gpa.free(body);
        _ = ch.active.fetchSub(1, .acq_rel);
    }
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    var s = false;
    const answer = machine.rpc(m, arena.allocator(), door, body, &s, ch);
    if (answer.len > 0) ch.send(answer);
    if (s) stop.store(true, .release);
}

/// A slow request: wait for its turn, then run it like any other.
fn slowRequest(m: *machine.Machine, ch: *Channel, door: []const u8, body: []u8, stop: *std.atomic.Value(bool), ticket: usize) void {
    defer _ = ch.turn.fetchAdd(1, .acq_rel);
    while (ch.turn.load(.acquire) != ticket) {
        if (ch.closing.load(.acquire)) {
            long_gpa.free(body);
            _ = ch.active.fetchSub(1, .acq_rel);
            return;
        }
        m.io.sleep(.fromMilliseconds(2), .awake) catch {};
    }
    if (ch.closing.load(.acquire)) {
        long_gpa.free(body);
        _ = ch.active.fetchSub(1, .acq_rel);
        return;
    }
    request(m, ch, door, body, stop);
}

/// Is the message one of the quick methods, answered in order by the reading thread?
fn isQuick(body: []const u8) bool {
    var buf: [4096]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&buf);
    const v = std.json.parseFromSliceLeaky(std.json.Value, fba.allocator(), body, .{}) catch return true;
    if (v != .object) return true;
    const method = v.object.get("method") orelse return true;
    if (method != .string) return true;
    const name = machine.methodName(method.string) orelse return true;
    return switch (name) {
        .ping, .stat, .stop, .cancel, .open, .close => true,
        .run, .eval, .shell => false,
    };
}

/// `eve --stdio`: a machine whose door is the standard input and output; it ends at the end of the input or on `vm.stop`.
pub fn serveStdio(io: Io, gpa: std.mem.Allocator, cfg_path: []const u8, log: bool) !u8 {
    const cfg = config.loadConfig(io, gpa, cfg_path);
    const ebuf = try gpa.alloc(u8, 1024);
    const ew = try gpa.create(Io.File.Writer);
    ew.* = .initStreaming(.stderr(), io, ebuf);
    const m = try gpa.create(machine.Machine);
    m.* = .{ .io = io, .cfg = cfg, .ipc = false, .http = false, .socket = "", .out = &ew.interface, .started = machine.millis(io), .quiet = !log };
    const wbuf = try gpa.alloc(u8, 64 * 1024);
    const w = try gpa.create(Io.File.Writer);
    w.* = .initStreaming(.stdout(), io, wbuf);
    var ch: Channel = .{ .io = io, .w = &w.interface };
    const rbuf = try gpa.alloc(u8, 16 << 20);
    var r: Io.File.Reader = .init(.stdin(), io, rbuf);
    _ = serveLines(m, &r.interface, &ch, "stdio");
    return 0;
}

// ---- sessions ------------------------------------------------------------------------------------------------------

var discard_buf: [0]u8 = .{};
var discard: Io.Writer.Discarding = .init(&discard_buf);

/// A session of the machine: the state of the prompt (the loaded script, its reports) kept between requests, and the
/// folder where its file names and shell commands start.
pub const Sess = struct {
    id: u32,
    s: vm.Session,
    /// The folder of the session (owned); "" is the folder of the machine.
    cwd: []u8,
};

/// The sessions of a machine.
pub const Sessions = struct {
    list: [16]?*Sess = @splat(null),
    next: u32 = 1,
    lock: Io.Mutex = .init,

    /// Open a session that starts in `cwd`.
    pub fn open(self: *Sessions, io: Io, cwd: []const u8) !*Sess {
        self.lock.lockUncancelable(io);
        defer self.lock.unlock(io);
        for (&self.list) |*slot| {
            if (slot.* != null) continue;
            const sess = try long_gpa.create(Sess);
            sess.* = .{ .id = self.next, .s = .{ .io = io, .gpa = long_gpa, .out = &discard.writer }, .cwd = try long_gpa.dupe(u8, cwd) };
            self.next += 1;
            slot.* = sess;
            return sess;
        }
        return error.TooManySessions;
    }

    /// The session with this id, or null.
    pub fn find(self: *Sessions, io: Io, id: u32) ?*Sess {
        self.lock.lockUncancelable(io);
        defer self.lock.unlock(io);
        for (self.list) |slot| if (slot) |sess| if (sess.id == id) return sess;
        return null;
    }

    /// Close the session with this id; false when there is none.
    pub fn close(self: *Sessions, io: Io, id: u32) bool {
        self.lock.lockUncancelable(io);
        defer self.lock.unlock(io);
        for (&self.list) |*slot| if (slot.*) |sess| if (sess.id == id) {
            sess.s.deinit();
            sess.s.summary.deinit(long_gpa);
            long_gpa.free(sess.cwd);
            long_gpa.destroy(sess);
            slot.* = null;
            return true;
        };
        return false;
    }

    /// How many sessions are open.
    pub fn count(self: *Sessions, io: Io) usize {
        self.lock.lockUncancelable(io);
        defer self.lock.unlock(io);
        var n: usize = 0;
        for (self.list) |slot| n += @intFromBool(slot != null);
        return n;
    }
};

fn strParam(params: std.json.Value, key: []const u8) ?[]const u8 {
    if (params != .object) return null;
    const v = params.object.get(key) orelse return null;
    return if (v == .string) v.string else null;
}

fn intParam(params: std.json.Value, key: []const u8) ?u32 {
    if (params != .object) return null;
    const v = params.object.get(key) orelse return null;
    return if (v == .integer and v.integer >= 0 and v.integer <= std.math.maxInt(u32)) @intCast(v.integer) else null;
}

fn boolParam(params: std.json.Value, key: []const u8) bool {
    if (params != .object) return false;
    const v = params.object.get(key) orelse return false;
    return v == .bool and v.bool;
}

/// The answer to a method of the lasting doors called through the HTTP door.
pub fn localOnly(a: std.mem.Allocator, id: std.json.Value) []const u8 {
    return fail(a, id, -32001, "this method works on the IPC and stdio doors only (the HTTP door has no login yet)");
}

/// `vm.open`: a new session; `{"cwd": "folder"}` sets its folder.
pub fn openRequest(m: *machine.Machine, a: std.mem.Allocator, id: std.json.Value, params: std.json.Value) []const u8 {
    const sess = m.sessions.open(m.io, strParam(params, "cwd") orelse "") catch return fail(a, id, -32000, "no room for another session (16 at most)");
    return ok(a, id, .{ .session = sess.id, .cwd = sess.cwd });
}

/// `vm.close`: end a session.
pub fn closeRequest(m: *machine.Machine, a: std.mem.Allocator, id: std.json.Value, params: std.json.Value) []const u8 {
    const sid = intParam(params, "session") orelse return fail(a, id, -32602, "vm.close needs the param session");
    m.run_lock.lockUncancelable(m.io);
    defer m.run_lock.unlock(m.io);
    if (!m.sessions.close(m.io, sid)) return fail(a, id, -32602, "no such session");
    return ok(a, id, "closed");
}

/// `vm.eval`: one line in a session, as at the prompt; without `session`, the default session of the channel. Answers
/// `{status, output, closed, session}`.
pub fn evalRequest(m: *machine.Machine, a: std.mem.Allocator, id: std.json.Value, params: std.json.Value, ch: *Channel) []const u8 {
    const line = strParam(params, "line") orelse return fail(a, id, -32602, "vm.eval needs the param line");
    m.run_lock.lockUncancelable(m.io);
    defer m.run_lock.unlock(m.io);
    const given = intParam(params, "session");
    const sid: u32 = given orelse ch.session orelse blk: {
        const made = m.sessions.open(m.io, "") catch return fail(a, id, -32000, "no room for another session (16 at most)");
        ch.session = made.id;
        break :blk made.id;
    };
    const sess = m.sessions.find(m.io, sid) orelse return fail(a, id, -32602, "no such session");
    if (strParam(params, "cwd")) |cwd| {
        const copy = long_gpa.dupe(u8, cwd) catch return fail(a, id, -32000, "out of memory");
        long_gpa.free(sess.cwd);
        sess.cwd = copy;
    }
    machine.setCurrent(m, line, machine.millis(m.io));
    defer machine.setCurrent(m, null, 0);
    var collected: Io.Writer.Allocating = .init(a);
    var os: OutStream = .init(ch, a, id);
    const stream = boolParam(params, "stream");
    const w = if (stream) &os.interface else &collected.writer;
    const status = evalLine(m.io, sess, a, line, w);
    if (stream) os.finish();
    const closed = sess.s.stopping;
    if (closed) {
        _ = m.sessions.close(m.io, sid);
        if (ch.session == sid) ch.session = null;
    }
    return ok(a, id, .{ .status = status, .output = collected.written(), .closed = closed, .session = sid });
}

/// `vm.shell`: a command of the operating system in the folder `cwd` (or the folder of `session`). Answers
/// `{status, output}`; with `"stream": true` the output comes as `vm.output` notifications while the command runs.
pub fn shellRequest(m: *machine.Machine, a: std.mem.Allocator, id: std.json.Value, params: std.json.Value, ch: *Channel) []const u8 {
    const command = strParam(params, "command") orelse return fail(a, id, -32602, "vm.shell needs the param command");
    var cwd: []const u8 = strParam(params, "cwd") orelse "";
    if (cwd.len == 0) if (intParam(params, "session")) |sid| if (m.sessions.find(m.io, sid)) |sess| {
        cwd = a.dupe(u8, sess.cwd) catch "";
    };
    var collected: Io.Writer.Allocating = .init(a);
    var os: OutStream = .init(ch, a, id);
    const stream = boolParam(params, "stream");
    const w = if (stream) &os.interface else &collected.writer;
    const status = runShell(m.io, a, command, cwd, w);
    if (stream) os.finish();
    return ok(a, id, .{ .status = status, .output = collected.written() });
}

/// Run one line of the prompt in a session; the output goes to `w`. Answers the exit status.
pub fn evalLine(io: Io, sess: *Sess, a: std.mem.Allocator, line: []const u8, w: *Io.Writer) u8 {
    const eql = std.mem.eql;
    const t = vm.clean(line);
    if (t.len == 0) return 0;
    defer w.flush() catch {};
    if (t[0] == '!') return runShell(io, a, std.mem.trim(u8, t[1..], " \t"), sess.cwd, w);
    var it = std.mem.tokenizeAny(u8, t, " \t");
    const cmd = it.next().?;
    const rest = std.mem.trim(u8, t[cmd.len..], " \t");
    if (eql(u8, cmd, "shell")) {
        if (rest.len == 0) {
            w.writeAll("shell: give the command, for example: shell dir\n") catch {};
            return 64;
        }
        return runShell(io, a, rest, sess.cwd, w);
    }
    if (eql(u8, cmd, "cd")) return changeDir(io, sess, a, rest, w);
    var known = false;
    for (vm.Session.command_names) |c| known = known or eql(u8, c, cmd);
    // a word that is not a command of Eve but a command of the shell (md, dir, ls, rm ...) goes to the shell, as if typed there
    if (!known) {
        if (shellLine(a, t)) |sh| return runShell(io, a, sh, sess.cwd, w);
    }
    if (!known) {
        w.print("eve: unknown command: {s} (help lists the commands)\n", .{cmd}) catch {};
        return 64;
    }
    var text = t;
    if (sess.cwd.len > 0 and (eql(u8, cmd, "load") or eql(u8, cmd, "parse") or eql(u8, cmd, "run"))) {
        if (it.next()) |arg| if (!std.fs.path.isAbsolute(arg)) {
            text = std.fmt.allocPrint(a, "{s} {s}/{s}", .{ cmd, sess.cwd, arg }) catch t;
        };
    }
    sess.s.out = w;
    defer sess.s.out = &discard.writer;
    sess.s.handleLine(text) catch {};
    if (eql(u8, cmd, "help")) w.writeAll("  cd <folder>\n  shell <command>   (or !<command>)\n  md, dir, ls, cp, mv, rm ...  commands of the shell run as they are\n") catch {};
    return sess.s.status;
}

const ShellPair = struct { unix: []const u8, win: []const u8 };
const shell_pairs = [_]ShellPair{
    .{ .unix = "ls", .win = "dir" },
    .{ .unix = "cp", .win = "copy" },
    .{ .unix = "mv", .win = "move" },
    .{ .unix = "rm", .win = "del" },
    .{ .unix = "cat", .win = "type" },
    .{ .unix = "mkdir", .win = "md" },
    .{ .unix = "rmdir", .win = "rd" },
    .{ .unix = "pwd", .win = "cd" },
    .{ .unix = "mv", .win = "ren" },
    .{ .unix = "mv", .win = "rename" },
    .{ .unix = "echo", .win = "echo" },
};

/// The line to give to the shell when its first word is a command of the shell (in the spelling of this shell), else null.
pub fn shellLine(a: std.mem.Allocator, t: []const u8) ?[]const u8 {
    var it = std.mem.tokenizeAny(u8, t, " \t");
    const word = it.next() orelse return null;
    const rest = std.mem.trim(u8, t[word.len..], " \t");
    const windows_cmd = std.ascii.eqlIgnoreCase(std.fs.path.stem(shell_path), "cmd");
    for (shell_pairs) |p| {
        const is_unix = std.ascii.eqlIgnoreCase(word, p.unix);
        const is_win = std.ascii.eqlIgnoreCase(word, p.win);
        if (!is_unix and !is_win) continue;
        const name = if (windows_cmd) p.win else p.unix;
        return std.fmt.allocPrint(a, "{s} {s}", .{ name, rest }) catch null;
    }
    return null;
}

/// `cd [folder]`: show or change the folder of the session.
fn changeDir(io: Io, sess: *Sess, a: std.mem.Allocator, arg: []const u8, w: *Io.Writer) u8 {
    if (arg.len == 0) {
        w.print("folder: {s}\n", .{if (sess.cwd.len == 0) "(the folder of the machine)" else sess.cwd}) catch {};
        return 0;
    }
    // `cd /d <folder>` of the Windows shell: the switch is not part of the name
    const named = if (arg.len > 3 and std.ascii.eqlIgnoreCase(arg[0..3], "/d ")) std.mem.trim(u8, arg[3..], " \t\"") else std.mem.trim(u8, arg, "\"");
    const target = if (std.fs.path.isAbsolute(named) or sess.cwd.len == 0) named else std.fmt.allocPrint(a, "{s}/{s}", .{ sess.cwd, named }) catch return 1;
    var dir = Io.Dir.cwd().openDir(io, target, .{}) catch |err| {
        w.print("cd: {s}: {s}\n", .{ target, @errorName(err) }) catch {};
        return 1;
    };
    // the folder is written the way the system spells it (`..` and `.` are resolved), as `cd` of a shell does
    var real_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real_len = dir.realPath(io, &real_buf) catch 0;
    dir.close(io);
    const copy = long_gpa.dupe(u8, if (real_len > 0) real_buf[0..real_len] else target) catch return 1;
    long_gpa.free(sess.cwd);
    sess.cwd = copy;
    w.print("folder: {s}\n", .{copy}) catch {};
    return 0;
}

/// Run a command of the operating system in `cwd` ("" = here); its output (and error output) goes to `w` as it comes.
/// Answers the exit code (127 when the shell cannot start, 130 when cancelled).
pub fn runShell(io: Io, a: std.mem.Allocator, command: []const u8, cwd: []const u8, w: *Io.Writer) u8 {
    if (command.len == 0) return 0;
    const windows_cmd = std.ascii.eqlIgnoreCase(std.fs.path.stem(shell_path), "cmd");
    const argv = [_][]const u8{ shell_path, if (windows_cmd) "/c" else "-c", command };
    var child = std.process.spawn(io, .{
        .argv = &argv,
        .cwd = if (cwd.len > 0) .{ .path = cwd } else .inherit,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .pipe,
    }) catch |err| {
        w.print("shell: cannot start {s}: {s}\n", .{ shell_path, @errorName(err) }) catch {};
        return 127;
    };
    defer child.kill(io);
    var buf: Io.File.MultiReader.Buffer(2) = undefined;
    var mr: Io.File.MultiReader = undefined;
    mr.init(a, io, buf.toStreams(), &.{ child.stdout.?, child.stderr.? });
    defer mr.deinit();
    const seen = vm.cancel_generation.load(.acquire);
    while (true) {
        if (vm.cancel_generation.load(.acquire) != seen) {
            w.writeAll("shell: cancelled\n") catch {};
            return 130;
        }
        const end = if (mr.fill(1, .{ .duration = .{ .raw = .fromMilliseconds(100), .clock = .awake } })) |_| false else |err| switch (err) {
            error.Timeout => false,
            else => true,
        };
        passOn(&mr, w);
        if (end) break;
    }
    const term = child.wait(io) catch return 1;
    return switch (term) {
        .exited => |code| code,
        else => 1,
    };
}

/// Write what both pipes of the child have now to `w`.
fn passOn(mr: *Io.File.MultiReader, w: *Io.Writer) void {
    for (0..2) |i| {
        const r = mr.reader(i);
        const b = r.buffered();
        if (b.len == 0) continue;
        w.writeAll(b) catch {};
        r.toss(b.len);
    }
    w.flush() catch {};
}

test "a session answers its commands, cd and unknown words" {
    var sessions: Sessions = .{};
    const io = std.testing.io;
    const sess = try sessions.open(io, "");
    defer _ = sessions.close(io, sess.id);
    // the machine gives every request an arena; the test does the same
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var buf: [2048]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try std.testing.expectEqual(@as(u8, 64), evalLine(io, sess, a, "frob", &w));
    try std.testing.expect(std.mem.indexOf(u8, w.buffered(), "unknown command: frob") != null);
    w = .fixed(&buf);
    try std.testing.expectEqual(@as(u8, 0), evalLine(io, sess, a, "cd .", &w));
    // `cd` writes the folder as the system spells it, not as it was typed
    try std.testing.expect(sess.cwd.len > 1 and !std.mem.eql(u8, sess.cwd, "."));
    const here = try a.dupe(u8, sess.cwd);
    w = .fixed(&buf);
    try std.testing.expectEqual(@as(u8, 1), evalLine(io, sess, a, "cd no-such-folder-here", &w));
    try std.testing.expectEqualStrings(here, sess.cwd);
    w = .fixed(&buf);
    _ = evalLine(io, sess, a, "help", &w);
    try std.testing.expect(std.mem.indexOf(u8, w.buffered(), "shell <command>") != null);
    try std.testing.expectEqual(@as(usize, 1), sessions.count(io));
}

test "a shell command runs and its output comes back" {
    var buf: [1024]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqual(@as(u8, 0), runShell(std.testing.io, arena.allocator(), "echo eve-shell", "", &w));
    try std.testing.expect(std.mem.indexOf(u8, w.buffered(), "eve-shell") != null);
}
