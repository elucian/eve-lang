//! The scheduler of the tasks of a run: started aspects (`start`) and spawned subprograms (`spawn`).
//! This is stage A of D-144: every task runs on its own operating-system thread, so the recursive
//! interpreter keeps its own Zig call stack per task, but only the thread that holds the **baton**
//! runs. The baton passes only when the running task waits (a full or empty channel, `wait`, the
//! `done` of a group or a job, the end of the task), to the next ready task in the order of creation.
//! The result is deterministic: the same program prints the same lines and the same errors at every
//! run (spec/semantics/multitasking.md#determinism). It also means that the interpreter, which is not
//! thread safe, never runs on two threads at the same time.
const std = @import("std");
const Io = std.Io;

/// What a task waits for.
pub const Wait = enum { none, send, receive, join, sleep, gen, io };

// @decision D-140
/// Why a task is asked to stop.
pub const Cancel = enum { none, cancel, timeout };

/// One task: its place in the order of creation and what it is doing.
pub const Task = struct {
    index: usize,
    done: bool = false,
    wait: Wait = .none,
    /// The value of `Sched.progress` when the task blocked.
    blocked_at: u64 = 0,
    /// For `sleep`, and for `join` with a deadline: the time (milliseconds, monotonic clock) to wake up.
    wake_at: i64 = 0,
    timer: bool = false,
    cancel: Cancel = .none,
    /// The `within` time of the group, in milliseconds: the message of a time-out names it.
    limit_ms: i64 = 0,
    /// Set by the scheduler when every task waits and nothing can move: the task raises DeadlockError.
    deadlock: bool = false,
    /// For `io`: set by the helper thread of a blocking call (netlib.zig) when it has ended.
    io_ready: std.atomic.Value(bool) = .init(false),
    thread: ?std.Thread = null,
};

/// The baton and the list of every task of the run.
pub const Sched = struct {
    io: Io,
    a: std.mem.Allocator,
    mutex: Io.Mutex = .init,
    cond: Io.Condition = .init,
    tasks: std.ArrayList(*Task) = .empty,
    /// The task that holds the baton.
    current: *Task,
    /// Grows at every change another task may wait for: a value sent or received, a channel closed,
    /// a task ended.
    progress: u64 = 0,

    /// A scheduler whose root task is the calling thread.
    pub fn init(a: std.mem.Allocator, io: Io) error{OutOfMemory}!*Sched {
        const first = try a.create(Task);
        first.* = .{ .index = 0 };
        const s = try a.create(Sched);
        s.* = .{ .io = io, .a = a, .current = first };
        try s.tasks.append(a, first);
        return s;
    }

    /// The root task: the thread of the root aspect.
    pub fn root(s: *Sched) *Task {
        return s.tasks.items[0];
    }

    /// Register a new task, last in the order of creation.
    pub fn add(s: *Sched) error{OutOfMemory}!*Task {
        const t = try s.a.create(Task);
        t.* = .{ .index = s.tasks.items.len };
        try s.tasks.append(s.a, t);
        return t;
    }

    /// The time now, in milliseconds of the monotonic clock.
    pub fn now(s: *Sched) i64 {
        return Io.Timestamp.now(s.io, .awake).toMilliseconds();
    }

    /// May `t` take the baton now?
    fn runnable(s: *Sched, t: *Task, now_ms: i64) bool {
        if (t.done) return false;
        if (t.cancel != .none or t.deadlock) return true;
        if (t.timer and now_ms >= t.wake_at) return true;
        return switch (t.wait) {
            .none => true,
            .send, .receive, .join => t.blocked_at != s.progress,
            .sleep => now_ms >= t.wake_at,
            .io => t.io_ready.load(.acquire),
            // a generator and the task that resumed it hand the baton to each other by name, never by `pick`
            .gen => false,
        };
    }

    /// The next task that may run, starting after `me`; `me` itself last.
    fn pick(s: *Sched, me: *Task) ?*Task {
        const n = s.tasks.items.len;
        const now_ms = s.now();
        var k: usize = 1;
        while (k <= n) : (k += 1) {
            const t = s.tasks.items[(me.index + k) % n];
            if (s.runnable(t, now_ms)) return t;
        }
        return null;
    }

    /// Does any task wait for a helper thread?
    fn ioPending(s: *Sched) bool {
        for (s.tasks.items) |t| if (!t.done and t.wait == .io) return true;
        return false;
    }

    /// Has any task that waits for a helper thread been told that the helper has ended?
    fn anyIoReady(s: *Sched) bool {
        for (s.tasks.items) |t| if (!t.done and t.wait == .io and t.io_ready.load(.acquire)) return true;
        return false;
    }

    /// Called by the helper thread of a blocking call when it ends: wake the scheduler.
    pub fn ioDone(s: *Sched, t: *Task) void {
        s.mutex.lockUncancelable(s.io);
        t.io_ready.store(true, .release);
        s.cond.broadcast(s.io);
        s.mutex.unlock(s.io);
    }

    /// The earliest time a sleeping task or a deadline wakes up, or null when there is none.
    fn nextTimer(s: *Sched, channels: bool) ?i64 {
        var best: ?i64 = null;
        for (s.tasks.items) |t| {
            if (t.done) continue;
            if (!channels and (t.wait == .send or t.wait == .receive)) continue;
            if (t.wait == .sleep or t.timer) {
                if (best == null or t.wake_at < best.?) best = t.wake_at;
            }
        }
        return best;
    }

    /// Give the baton to `next` and sleep until it comes back to `me`.
    fn handoff(s: *Sched, me: *Task, next: *Task) void {
        s.mutex.lockUncancelable(s.io);
        s.current = next;
        s.cond.broadcast(s.io);
        while (s.current != me) s.cond.waitUncancelable(s.io, &s.mutex);
        s.mutex.unlock(s.io);
    }

    /// Called by a new thread before it runs: wait until the baton is given to `me`.
    pub fn waitTurn(s: *Sched, me: *Task) void {
        s.mutex.lockUncancelable(s.io);
        while (s.current != me) s.cond.waitUncancelable(s.io, &s.mutex);
        s.mutex.unlock(s.io);
    }

    // @decision D-141
    /// The running task `me` has set its `wait`: give the baton to the next runnable task and return
    /// when `me` may go on (or must react to a cancel or a deadlock).
    pub fn yield(s: *Sched, me: *Task) void {
        while (true) {
            if (s.pick(me)) |next| {
                if (next != me) s.handoff(me, next);
                return;
            }
            // @eve-impl a task waits for the helper thread of a blocking call (`io`): nothing else can run, so sleep on the
            // condition until a helper says it has ended, or wake for the earliest timer; no deadlock can be declared
            // while a call is pending, because its end is the progress that the other tasks wait for
            // @see code/evevm/src/netlib.zig (`offload`), `ioDone`
            if (s.ioPending()) {
                if (s.nextTimer(true)) |at| {
                    // @eve-impl wait on the condition up to the timer, not in 1 ms steps (a Windows step is about 15 ms: p6e went from 450 ms to 4.8 s)
                    const left = at - s.now();
                    if (left > 0) {
                        s.mutex.lockUncancelable(s.io);
                        if (!s.anyIoReady()) s.cond.waitTimeout(s.io, &s.mutex, .{ .duration = .{ .raw = .fromMilliseconds(left), .clock = .awake } }) catch {};
                        s.mutex.unlock(s.io);
                    }
                    continue;
                }
                s.mutex.lockUncancelable(s.io);
                while (!s.anyIoReady()) s.cond.waitUncancelable(s.io, &s.mutex);
                s.mutex.unlock(s.io);
                continue;
            }
            // a deadlock is reported at once, before the time-outs of the channel waits: when only they
            // remain, nothing but a time-out could move, and every waiter would wait for nothing
            if (s.nextTimer(false) == null) {
                var any = false;
                for (s.tasks.items) |t| {
                    if (!t.done and (t.wait == .send or t.wait == .receive)) {
                        t.deadlock = true;
                        any = true;
                    }
                }
                if (any) continue;
            }
            if (s.nextTimer(true)) |at| {
                const left = at - s.now();
                if (left > 0) Io.sleep(s.io, .fromMilliseconds(left), .awake) catch {};
                continue;
            }
            return; // nothing can be woken: let `me` look at its own state again
        }
    }

    /// The task `me` asks the generator task `gen` for the next value and waits for it.
    pub fn resumeGen(s: *Sched, me: *Task, gen: *Task) void {
        me.wait = .gen;
        gen.wait = .none;
        s.handoff(me, gen);
        me.wait = .none;
    }

    /// The generator task `me` has a value (or must stop at a close): give the baton back to its caller `back`
    /// and sleep until the next request.
    pub fn parkGen(s: *Sched, me: *Task, back: *Task) void {
        me.wait = .gen;
        s.handoff(me, back);
    }

    /// The generator task `me` has ended: mark it and give the baton to its caller. The thread ends right after.
    pub fn finishGen(s: *Sched, me: *Task, back: *Task) void {
        me.done = true;
        me.wait = .none;
        s.progress += 1;
        s.mutex.lockUncancelable(s.io);
        s.current = back;
        s.cond.broadcast(s.io);
        s.mutex.unlock(s.io);
    }

    /// The task `me` has ended: mark it and give the baton to the next runnable task.
    pub fn finish(s: *Sched, me: *Task) void {
        me.done = true;
        s.progress += 1;
        const next = s.pick(me) orelse s.root();
        s.mutex.lockUncancelable(s.io);
        s.current = next;
        s.cond.broadcast(s.io);
        s.mutex.unlock(s.io);
    }
};
