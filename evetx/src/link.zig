//! The link of evetx to its machine (`spec/library/machine.md#lasting-doors`): evetx starts one `eve --stdio` as its
//! child, the first time the console needs it, and speaks JSON-RPC with it on the pipes, one message per line. The
//! commands of the console (`load`, `parse`, `errors`, `status`, …) go to `vm.eval` in the default session of the
//! channel, the commands of the system (`!dir`, `shell git status`) go to `vm.shell`, and the output comes back as
//! `vm.output` notifications while it is made. The same messages work over SSH (`ssh host eve --stdio`) and, later,
//! from eveux over a WebSocket. A worker thread does all the waiting, so the screen never stops.
const std = @import("std");
const Io = std.Io;

// Zig tip: an enum of the kinds of event, and a struct for one event. `text` is owned by the event (`[]u8`): the
// main thread that takes the events frees it (`Event.free`).
/// What the machine sent: some output of a request, its end (with the exit status), a failure, or a line of its log.
pub const Kind = enum { output, done, failed, log };

pub const Event = struct {
    kind: Kind,
    /// The id of the request this event belongs to (0 for the log).
    id: u32,
    text: []u8,
    status: i64 = 0,

    pub fn free(self: Event, gpa: std.mem.Allocator) void {
        gpa.free(self.text);
    }
};

// Zig tip: the same sharing rule as `RunJob` in app.zig: the two lists are guarded by `busy`, a tiny spin lock made of one
// atomic flag, and the flags `stop` and `done` are atomics. The worker owns the child process; the main thread only
// queues bytes (`call`) and takes events (`take`).
/// One machine of evetx, and the thread that talks to it.
pub const Link = struct {
    io: Io,
    gpa: std.mem.Allocator,
    exe: []const u8,
    thread: ?std.Thread = null,
    stop: std.atomic.Value(bool) = .init(false),
    done: std.atomic.Value(bool) = .init(false),
    busy: std.atomic.Value(bool) = .init(false),
    /// The messages not yet written to the machine, and the events not yet taken by the main thread (under `busy`).
    outgoing: std.ArrayList(u8) = .empty,
    events: std.ArrayList(Event) = .empty,
    /// The next id of a request (main thread only).
    next_id: u32 = 1,
    /// Why the machine could not start or ended (an error name), for the console.
    err_name: ?[]const u8 = null,

    // Zig tip: `gpa.create` puts the link on the heap, so its address stays the same for the worker thread, which keeps a
    // pointer to it. `errdefer` frees it if the thread cannot start.
    /// Start the machine (`<exe> --stdio`, in the current folder of evetx) and the thread that talks to it.
    pub fn start(gpa: std.mem.Allocator, io: Io, exe: []const u8) !*Link {
        const self = try gpa.create(Link);
        errdefer gpa.destroy(self);
        self.* = .{ .io = io, .gpa = gpa, .exe = exe };
        self.thread = try std.Thread.spawn(.{}, work, .{self});
        return self;
    }

    // Zig tip: after `stop` the worker closes the input of the machine, which ends it (the end of its input), then waits
    // for it; `join` waits for the worker. Every event that nobody took is freed.
    /// Stop the machine and free the link.
    pub fn destroy(self: *Link) void {
        self.stop.store(true, .release);
        if (self.thread) |t| t.join();
        for (self.events.items) |e| e.free(self.gpa);
        self.events.deinit(self.gpa);
        self.outgoing.deinit(self.gpa);
        self.gpa.destroy(self);
    }

    // Zig tip: the spin lock of `RunJob.lock` in app.zig: see the tip there.
    fn lock(self: *Link) void {
        while (self.busy.cmpxchgWeak(false, true, .acquire, .monotonic) != null) std.atomic.spinLoopHint();
    }

    fn unlock(self: *Link) void {
        self.busy.store(false, .release);
    }

    // Zig tip: `self: *const Link` only reads; `.acquire` makes the work of the worker before `done` visible here.
    /// Is the machine still there? (False after it ended or could not start.)
    pub fn alive(self: *const Link) bool {
        return !self.done.load(.acquire);
    }

    // Zig tip: `std.json.Stringify.valueAlloc` writes the message from a struct literal; `params: anytype` lets the caller
    // pass any struct (`.{ .line = text, .stream = true }`). The id is the answer, so the caller can match the events.
    /// Send a request to the machine; answers its id (0 when it could not be queued).
    pub fn call(self: *Link, method: []const u8, params: anytype) u32 {
        const id = self.next_id;
        const text = std.json.Stringify.valueAlloc(self.gpa, .{ .jsonrpc = "2.0", .id = id, .method = method, .params = params }, .{}) catch return 0;
        defer self.gpa.free(text);
        self.lock();
        defer self.unlock();
        self.outgoing.appendSlice(self.gpa, text) catch return 0;
        self.outgoing.append(self.gpa, '\n') catch return 0;
        self.next_id += 1;
        return id;
    }

    // Zig tip: `toOwnedSlice` hands the items to the caller and leaves the list empty, all under the lock.
    /// Take the events that came since the last call; the caller frees the list and each event.
    pub fn take(self: *Link) ?[]Event {
        self.lock();
        defer self.unlock();
        if (self.events.items.len == 0) return null;
        return self.events.toOwnedSlice(self.gpa) catch null;
    }

    // Zig tip: the text is copied before the lock is taken (an allocation can be slow); `catch self.gpa.free(copy)` gives it
    // back when the list cannot grow.
    /// Add an event for the main thread.
    fn push(self: *Link, kind: Kind, id: u32, text: []const u8, status: i64) void {
        const copy = self.gpa.dupe(u8, text) catch return;
        self.lock();
        defer self.unlock();
        self.events.append(self.gpa, .{ .kind = kind, .id = id, .text = copy, .status = status }) catch self.gpa.free(copy);
    }

    // Zig tip: the body of the worker thread: it cannot return an error, so the name of the error is kept for the console.
    fn work(self: *Link) void {
        self.talk() catch |err| {
            self.err_name = @errorName(err);
        };
        self.done.store(true, .release);
    }

    // Zig tip: the loop is the one of `RunJob.runChild`: `fill` waits for output at most 50 ms, then the queued messages are
    // written to the machine. The lines of the standard output are messages; the lines of the error output are its log.
    // Only whole lines are handled; `toss` marks them as read, so the buffers do not grow.
    fn talk(self: *Link) !void {
        const io = self.io;
        const argv = [_][]const u8{ self.exe, "--stdio" };
        var child = try std.process.spawn(io, .{ .argv = &argv, .stdin = .pipe, .stdout = .pipe, .stderr = .pipe });
        defer child.kill(io);
        var buf: Io.File.MultiReader.Buffer(2) = undefined;
        var mr: Io.File.MultiReader = undefined;
        mr.init(self.gpa, io, buf.toStreams(), &.{ child.stdout.?, child.stderr.? });
        defer mr.deinit();
        while (!self.stop.load(.acquire)) {
            var chunk: [4096]u8 = undefined;
            var n: usize = 0;
            {
                self.lock();
                defer self.unlock();
                n = @min(chunk.len, self.outgoing.items.len);
                @memcpy(chunk[0..n], self.outgoing.items[0..n]);
                self.outgoing.replaceRange(self.gpa, 0, n, &.{}) catch {};
            }
            if (n > 0) try child.stdin.?.writeStreamingAll(io, chunk[0..n]);
            const ended = if (mr.fill(1, .{ .duration = .{ .raw = .fromMilliseconds(50), .clock = .awake } })) |_| false else |err| switch (err) {
                error.Timeout => false,
                error.EndOfStream => true,
                else => return err,
            };
            self.lines(mr.reader(0), false);
            self.lines(mr.reader(1), true);
            if (ended) return error.MachineEnded;
        }
        // the end of its input ends the machine; it gets a moment to close its sessions
        child.stdin.?.close(io);
        child.stdin = null;
        _ = child.wait(io) catch {};
    }

    // Zig tip: `while (opt) |nl|` repeats while a newline is found in what the reader holds; `toss` consumes the line.
    /// Handle the whole lines that a pipe holds now: messages (`log` false) or lines of the log.
    fn lines(self: *Link, r: *Io.Reader, log: bool) void {
        while (std.mem.indexOfScalar(u8, r.buffered(), '\n')) |nl| {
            const line = std.mem.trimEnd(u8, r.buffered()[0..nl], "\r");
            if (log) self.push(.log, 0, line, 0) else self.message(line);
            r.toss(nl + 1);
        }
    }

    // Zig tip: the message is read into a tree of JSON values (`std.json.Value`), whose memory is one arena freed at the end
    // (`parsed.deinit()`): the texts that the events keep are copied first (`push` duplicates them).
    /// One message of the machine: a `vm.output` notification, or the answer to a request.
    fn message(self: *Link, line: []const u8) void {
        const parsed = std.json.parseFromSlice(std.json.Value, self.gpa, line, .{}) catch return;
        defer parsed.deinit();
        const v = parsed.value;
        if (v != .object) return;
        if (v.object.get("method")) |method| {
            if (method != .string or !std.mem.eql(u8, method.string, "vm.output")) return;
            const params = v.object.get("params") orelse return;
            if (params != .object) return;
            const text = params.object.get("text") orelse return;
            if (text != .string) return;
            self.push(.output, idOf(params.object.get("id")), text.string, 0);
            return;
        }
        const id = idOf(v.object.get("id"));
        if (v.object.get("error")) |e| {
            const msg = if (e == .object) e.object.get("message") else null;
            self.push(.failed, id, if (msg != null and msg.? == .string) msg.?.string else "the machine refused the request", 1);
            return;
        }
        const result = v.object.get("result") orelse return;
        if (result == .string) return self.push(.done, id, result.string, 0);
        if (result != .object) return self.push(.done, id, "", 0);
        const status: i64 = if (result.object.get("status")) |s| (if (s == .integer) s.integer else 0) else 0;
        // the output that was not streamed, and the errors that nobody recovered, come with the answer
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(self.gpa);
        for ([_][]const u8{ "output", "errors" }) |key| {
            if (result.object.get(key)) |t| if (t == .string) text.appendSlice(self.gpa, t.string) catch {};
        }
        self.push(.done, id, text.items, status);
    }

    // Zig tip: a JSON number is an `i64` in `std.json.Value`; it is checked to fit a `u32` before `@intCast`.
    /// The id of a message as a number (0 when it has none).
    fn idOf(v: ?std.json.Value) u32 {
        const x = v orelse return 0;
        return if (x == .integer and x.integer > 0 and x.integer <= std.math.maxInt(u32)) @intCast(x.integer) else 0;
    }
};
