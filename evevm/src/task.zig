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

// Zig tip: an `enum` lists the states a task can be in. `wait` says what a task waits for when it has
// given the baton away, so the scheduler can tell whether it may go on: a channel waiter is tried again
// only when something changed since it blocked (the `progress` counter), a sleeper only when its time
// has come.
/// What a task waits for.
pub const Wait = enum { none, send, receive, join, sleep };

// Zig tip: a second enum for the reason a task must stop: `cancel` comes from `on error cancel`,
// `timeout` from the `within` deadline of its group (D-140).
/// Why a task is asked to stop.
pub const Cancel = enum { none, cancel, timeout };

// Zig tip: fields with a default (`= .none`) need not be given when the struct is made: `.{ .index = 3 }`
// fills the rest. `?std.Thread` is "a thread, or nothing": the root task is the thread that runs the
// driver, it was not spawned and is never joined.
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
    thread: ?std.Thread = null,
};

// Zig tip: `Io.Mutex` and `Io.Condition` are the locks of Zig 0.16: each call takes the `Io` handle,
// which knows how to put a thread to sleep. A thread waits on the condition, inside the mutex, until
// `current` is itself; the thread that gives the baton sets `current` and wakes everybody with
// `broadcast`. The running thread holds no lock while it executes the script.
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

    // Zig tip: `a.create(T)` allocates one value and returns a pointer that stays valid; the scheduler
    // and its tasks live in the arena of the run and are freed with it. The thread that calls `init` is
    // the root task, index 0, and holds the baton from the start.
    /// A scheduler whose root task is the calling thread.
    pub fn init(a: std.mem.Allocator, io: Io) error{OutOfMemory}!*Sched {
        const first = try a.create(Task);
        first.* = .{ .index = 0 };
        const s = try a.create(Sched);
        s.* = .{ .io = io, .a = a, .current = first };
        try s.tasks.append(a, first);
        return s;
    }

    /// The root task: the thread of the driver.
    pub fn root(s: *Sched) *Task {
        return s.tasks.items[0];
    }

    // Zig tip: a new task is only a record; its thread is spawned by the interpreter, and the thread
    // first waits for the baton (`waitTurn`). Only the baton holder calls `add`, so the list needs no lock.
    /// Register a new task, last in the order of creation.
    pub fn add(s: *Sched) error{OutOfMemory}!*Task {
        const t = try s.a.create(Task);
        t.* = .{ .index = s.tasks.items.len };
        try s.tasks.append(s.a, t);
        return t;
    }

    // Zig tip: `Io.Clock.awake` is a monotonic clock: it never goes back, so it is the right one to
    // measure a deadline. `toMilliseconds` turns the timestamp into an `i64`.
    /// The time now, in milliseconds of the monotonic clock.
    pub fn now(s: *Sched) i64 {
        return Io.Timestamp.now(s.io, .awake).toMilliseconds();
    }

    // Zig tip: `switch` on an enum must name every value or have `else`; each prong here answers
    // whether the task may run now.
    /// May `t` take the baton now?
    fn runnable(s: *Sched, t: *Task, now_ms: i64) bool {
        if (t.done) return false;
        if (t.cancel != .none or t.deadlock) return true;
        if (t.timer and now_ms >= t.wake_at) return true;
        return switch (t.wait) {
            .none => true,
            .send, .receive, .join => t.blocked_at != s.progress,
            .sleep => now_ms >= t.wake_at,
        };
    }

    // Zig tip: `(i + k) % n` walks a list in a circle: the search starts after `me` and comes back to
    // `me` last, so the tasks take turns in the order of creation.
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

    // Zig tip: a `bool` parameter selects a variant of the search: with `channels` false the time-outs
    // of the channel waits (`$timeout`) are left out, so the scheduler can see that only they remain.
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

    // Zig tip: `lockUncancelable` and `waitUncancelable` are the forms that never fail: the scheduler
    // has no way to report a cancelation of the thread itself, so it does not ask for one. The loop
    // `while (s.current != me)` protects against a spurious wake-up: a thread may wake without being chosen.
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

    // Zig tip: when no task may run, either one is asleep (the thread sleeps until the earliest timer,
    // with `Io.sleep`, and looks again) or every unfinished task waits on a channel or on a `done`: a
    // deadlock. Then each channel waiter gets the flag `deadlock`, which makes it runnable, and raises
    // DeadlockError when it gets the baton (D-141).
    /// The running task `me` has set its `wait`: give the baton to the next runnable task and return
    /// when `me` may go on (or must react to a cancel or a deadlock).
    pub fn yield(s: *Sched, me: *Task) void {
        while (true) {
            if (s.pick(me)) |next| {
                if (next != me) s.handoff(me, next);
                return;
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

    // Zig tip: the thread of a finished task gives the baton away and does not wait for it: it ends
    // right after, and the parent joins it at `done`. `progress += 1` wakes the parent waiting on `done`.
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
