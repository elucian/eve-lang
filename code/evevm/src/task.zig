//! @eve-module task
//! @spec spec/semantics/multitasking.md#tasks-in-a-job
//! @feature F-MTK-02, F-MTK-04, F-MTK-05
//! @decision D-144
//! @tests test/level4
//! The scheduler of the tasks of a run: started aspects (`start`), spawned subprograms (`spawn`) and generators.
//! Stage B of D-144: every task runs on its own operating-system thread (so the recursive interpreter keeps its
//! own Zig call stack per task), and at most `cores` **lanes** run at a time. A lane is a set of tasks that share
//! one heap: a started aspect with the job tasks and generators it creates. The tasks of a lane run one at a time
//! and switch only when the running one waits (a full or empty channel, `wait`, the `done` of a group or a job,
//! the end of the task), to the next ready task in the order of creation. With `cores = 1` this is the baton of
//! stage A: the same program prints the same lines and the same errors at every run
//! (spec/semantics/multitasking.md#determinism).
//!
//! A lane holds a **permit** while one of its tasks runs. A task that waits gives its permit back, and the
//! scheduler hands it to the next ready task whose lane is idle; a parked thread sleeps until it is granted.
//! All the state below is guarded by `mutex`; the fields other tasks read without it are atomic.
const std = @import("std");
const Io = std.Io;

/// What a task waits for.
pub const Wait = enum { none, send, receive, join, sleep, gen, io };

// @decision D-140
/// Why a task is asked to stop.
pub const Cancel = enum { none, cancel, timeout };

/// The tasks that share one heap (and one core): a started aspect and the tasks it spawns.
pub const Lane = struct {
    /// A task of the lane holds a permit.
    running: bool = false,
};

/// One task: its place in the order of creation and what it is doing.
pub const Task = struct {
    index: usize,
    lane: *Lane,
    /// Written under the lock, read by the others with `isDone`.
    done: bool = false,
    wait: Wait = .none,
    /// The value of `Sched.progress` when the task blocked.
    blocked_at: u64 = 0,
    /// For `sleep`, and for `join` with a deadline: the time (milliseconds, monotonic clock) to wake up.
    wake_at: i64 = 0,
    timer: bool = false,
    /// Read and written with `cancelOf` and `Sched.cancelTask`.
    cancel: Cancel = .none,
    /// The `within` time of the group, in milliseconds: the message of a time-out names it.
    limit_ms: i64 = 0,
    /// Set by the scheduler when every task waits and nothing can move: the task raises DeadlockError.
    deadlock: bool = false,
    /// For `io`: set by the helper thread of a blocking call (netlib.zig) when it has ended.
    io_ready: std.atomic.Value(bool) = .init(false),
    thread: ?std.Thread = null,
    /// The task holds a permit (it runs, or it is about to).
    granted: bool = false,
    /// The task waits for a permit (a new task is parked until the scheduler grants it one).
    parked: bool = true,
    /// The task is parked on a change of `progress` and counted in `Sched.waiting`.
    counted: bool = false,

    pub fn isDone(t: *Task) bool {
        return @atomicLoad(bool, &t.done, .acquire);
    }

    pub fn cancelOf(t: *Task) Cancel {
        return @atomicLoad(Cancel, &t.cancel, .acquire);
    }
};

/// The permits and the list of every task of the run.
pub const Sched = struct {
    io: Io,
    a: std.mem.Allocator,
    mutex: Io.Mutex = .init,
    cond: Io.Condition = .init,
    tasks: std.ArrayList(*Task) = .empty,
    /// How many lanes may run at a time (`$cores`).
    cores: u32,
    /// The permits in use. Changed under the lock; `bump` reads it without (sequentially consistent, see `bump`).
    running: std.atomic.Value(u32) = .init(0),
    /// The parked tasks that wait for a change of `progress` (a channel, a join): when there are none, `bump` only counts.
    waiting: std.atomic.Value(u32) = .init(0),
    /// Grows at every change another task may wait for: a value sent or received, a channel closed,
    /// a task ended.
    progress: std.atomic.Value(u64) = .init(0),
    /// Grows when a task ends: what a `join` and a `$max_parallel` wait look for.
    finishes: std.atomic.Value(u64) = .init(0),

    /// A scheduler whose root task is the calling thread.
    pub fn init(a: std.mem.Allocator, io: Io, cores: u32) error{OutOfMemory}!*Sched {
        const lane = try a.create(Lane);
        lane.* = .{ .running = true };
        const first = try a.create(Task);
        first.* = .{ .index = 0, .lane = lane, .granted = true, .parked = false };
        const s = try a.create(Sched);
        s.* = .{ .io = io, .a = a, .cores = @max(cores, 1), .running = .init(1) };
        try s.tasks.append(a, first);
        return s;
    }

    /// The root task: the thread of the root aspect.
    pub fn root(s: *Sched) *Task {
        return s.tasks.items[0];
    }

    fn lock(s: *Sched) void {
        s.mutex.lockUncancelable(s.io);
    }

    fn unlock(s: *Sched) void {
        s.mutex.unlock(s.io);
    }

    /// Register a new task, last in the order of creation, in `lane` (a new lane when null).
    pub fn add(s: *Sched, lane: ?*Lane) error{OutOfMemory}!*Task {
        const l = lane orelse blk: {
            const n = try s.a.create(Lane);
            n.* = .{};
            break :blk n;
        };
        s.lock();
        defer s.unlock();
        const t = try s.a.create(Task);
        t.* = .{ .index = s.tasks.items.len, .lane = l };
        try s.tasks.append(s.a, t);
        return t;
    }

    // @eve-impl a short spin before a task parks on a change that another core is about to make: a pipeline of fast stages would otherwise sleep and wake at every message
    /// Wait a few microseconds for `progress` to differ from `seen`; true when it did.
    pub fn spinFor(s: *Sched, seen: u64) bool {
        if (s.running.load(.monotonic) < 2) return false; // nobody else runs: nobody can make the change
        var i: u32 = 0;
        while (i < 600) : (i += 1) {
            if (s.progress.load(.acquire) != seen) return true;
            std.atomic.spinLoopHint();
        }
        return false;
    }

    /// The time now, in milliseconds of the monotonic clock.
    pub fn now(s: *Sched) i64 {
        return Io.Timestamp.now(s.io, .awake).toMilliseconds();
    }

    /// The current value of the progress counter.
    pub fn progressNow(s: *Sched) u64 {
        return s.progress.load(.acquire);
    }

    /// The number of tasks ended so far: read it before looking at which tasks are done.
    pub fn finishedNow(s: *Sched) u64 {
        return s.finishes.load(.acquire);
    }

    /// May the parked task `t` take a permit now? (`now_ms` is read from the clock only when a task has a time to wait for.)
    fn runnable(s: *Sched, t: *Task, now_ms: *?i64) bool {
        if (t.done) return false;
        if (t.cancel != .none or t.deadlock) return true;
        if (t.timer or t.wait == .sleep) {
            if (now_ms.* == null) now_ms.* = s.now();
        }
        if (t.timer and now_ms.*.? >= t.wake_at) return true;
        return switch (t.wait) {
            .none => true,
            .send, .receive => t.blocked_at != s.progress.load(.seq_cst),
            .join => t.blocked_at != s.finishes.load(.seq_cst),
            .sleep => now_ms.*.? >= t.wake_at,
            .io => t.io_ready.load(.acquire),
            // a generator and the task that resumed it hand the permit to each other by name, never by `pickFor`
            .gen => false,
        };
    }

    /// The next parked task that may run, starting after `from`, whose lane is idle.
    fn pickFor(s: *Sched, from: usize) ?*Task {
        const n = s.tasks.items.len;
        var now_ms: ?i64 = null;
        var k: usize = 1;
        while (k <= n) : (k += 1) {
            const t = s.tasks.items[(from + k) % n];
            if (t.parked and !t.lane.running and s.runnable(t, &now_ms)) return t;
        }
        return null;
    }

    fn grant(s: *Sched, t: *Task) void {
        if (t.counted) {
            t.counted = false;
            _ = s.waiting.fetchSub(1, .seq_cst);
        }
        t.granted = true;
        t.parked = false;
        t.lane.running = true;
        _ = s.running.fetchAdd(1, .seq_cst);
    }

    /// Hand the free permits to the ready tasks, in the order of creation after `from`. True when one was given.
    fn dispatch(s: *Sched, from: usize) bool {
        var any = false;
        while (s.running.load(.monotonic) < s.cores) {
            const t = s.pickFor(from) orelse break;
            s.grant(t);
            any = true;
        }
        if (any) s.cond.broadcast(s.io);
        return any;
    }

    fn releasePermit(s: *Sched, me: *Task) void {
        me.granted = false;
        me.lane.running = false;
        _ = s.running.fetchSub(1, .seq_cst);
    }

    /// Does any task wait for a helper thread?
    fn ioPending(s: *Sched) bool {
        for (s.tasks.items) |t| if (!t.done and t.parked and t.wait == .io) return true;
        return false;
    }

    /// The earliest time a sleeping task or a deadline wakes up, or null when there is none.
    fn nextTimer(s: *Sched, channels: bool) ?i64 {
        var best: ?i64 = null;
        for (s.tasks.items) |t| {
            if (t.done or !t.parked) continue;
            if (!channels and (t.wait == .send or t.wait == .receive)) continue;
            if (t.wait == .sleep or t.timer) {
                if (best == null or t.wake_at < best.?) best = t.wake_at;
            }
        }
        return best;
    }

    /// Nobody runs and nobody can be granted: when only channel waits remain (no sleeper, no deadline, no helper
    /// thread), they would wait for nothing, so they are told at once (a deadlock is reported before the time-outs
    /// of the channel waits, D-141). True when a task was told.
    fn stuck(s: *Sched) bool {
        if (s.ioPending()) return false;
        if (s.nextTimer(false) != null) return false;
        var any = false;
        for (s.tasks.items) |t| {
            if (!t.done and t.parked and (t.wait == .send or t.wait == .receive)) {
                t.deadlock = true;
                any = true;
            }
        }
        return any;
    }

    /// Called by a new thread before it runs: wait until a permit is granted to `me`.
    pub fn waitTurn(s: *Sched, me: *Task) void {
        s.lock();
        defer s.unlock();
        while (!me.granted) s.cond.waitUncancelable(s.io, &s.mutex);
    }

    /// A task was created: give it a permit at once when one is free.
    pub fn kick(s: *Sched, me: *Task) void {
        s.lock();
        defer s.unlock();
        _ = s.dispatch(me.index);
    }

    /// The thread of the task `t` could not be started: the task is over before it began.
    pub fn abandon(s: *Sched, t: *Task) void {
        s.lock();
        defer s.unlock();
        t.done = true;
        _ = s.progress.fetchAdd(1, .seq_cst);
        _ = s.finishes.fetchAdd(1, .seq_cst);
        _ = s.dispatch(t.index);
    }

    // @eve-impl when every permit is in use nobody can be woken, so a change only counts: a task that releases a permit looks at the counter then
    // @invariant `progress` is bumped before `running` is read here, and `running` is lowered before the counter is read by `dispatch` (sequentially consistent): one of the two sees the other
    /// Note a change that a waiting task may be interested in.
    pub fn bump(s: *Sched, me: ?*Task) void {
        _ = s.progress.fetchAdd(1, .seq_cst);
        if (s.running.load(.seq_cst) >= s.cores or s.waiting.load(.seq_cst) == 0) return;
        s.lock();
        defer s.unlock();
        _ = s.dispatch(if (me) |m| m.index else 0);
    }

    /// Ask the task `t` to stop (a cancel, or a time-out with the `within` time `limit_ms`).
    pub fn cancelTask(s: *Sched, t: *Task, kind: Cancel, limit_ms: i64) void {
        s.lock();
        defer s.unlock();
        t.limit_ms = limit_ms;
        @atomicStore(Cancel, &t.cancel, kind, .release);
        _ = s.dispatch(t.index);
        s.cond.broadcast(s.io);
    }

    /// Called by the helper thread of a blocking call when it ends: wake the scheduler.
    pub fn ioDone(s: *Sched, t: *Task) void {
        s.lock();
        defer s.unlock();
        t.io_ready.store(true, .release);
        _ = s.dispatch(t.index);
        s.cond.broadcast(s.io);
    }

    // @decision D-141
    /// The running task `me` has set its `wait`: give its permit away and return when it has one again
    /// (and must react to a cancel or a deadlock).
    pub fn yield(s: *Sched, me: *Task) void {
        s.lock();
        defer s.unlock();
        me.parked = true;
        s.releasePermit(me);
        if (me.wait == .send or me.wait == .receive) {
            me.counted = true;
            _ = s.waiting.fetchAdd(1, .seq_cst);
        }
        while (true) {
            _ = s.dispatch(me.index);
            if (me.granted) return;
            if (s.running.load(.monotonic) == 0) {
                if (s.stuck()) continue;
                // nothing can be woken: let `me` look at its own state again
                if (!s.ioPending() and s.nextTimer(true) == null) {
                    s.grant(me);
                    return;
                }
            }
            // sleep until a grant, or until the time of `me` itself
            if (me.wait == .sleep or me.timer) {
                const left = me.wake_at - s.now();
                if (left > 0) {
                    s.cond.waitTimeout(s.io, &s.mutex, .{ .duration = .{ .raw = .fromMilliseconds(left), .clock = .awake } }) catch {};
                    continue;
                }
            }
            s.cond.waitUncancelable(s.io, &s.mutex);
        }
    }

    /// Hand the permit of the running task `me` to the task `next` of its lane, and sleep until it comes back.
    fn handoff(s: *Sched, me: *Task, next: *Task) void {
        s.lock();
        defer s.unlock();
        me.granted = false;
        me.parked = true;
        next.granted = true;
        next.parked = false;
        s.cond.broadcast(s.io);
        while (!me.granted) s.cond.waitUncancelable(s.io, &s.mutex);
    }

    /// The task `me` asks the generator task `gen` for the next value and waits for it.
    pub fn resumeGen(s: *Sched, me: *Task, gen: *Task) void {
        me.wait = .gen;
        gen.wait = .none;
        s.handoff(me, gen);
        me.wait = .none;
    }

    /// The generator task `me` has a value (or must stop at a close): give the permit back to its caller `back`
    /// and sleep until the next request.
    pub fn parkGen(s: *Sched, me: *Task, back: *Task) void {
        me.wait = .gen;
        s.handoff(me, back);
    }

    /// The generator task `me` has ended: mark it and give the permit to its caller. The thread ends right after.
    pub fn finishGen(s: *Sched, me: *Task, back: *Task) void {
        s.lock();
        defer s.unlock();
        @atomicStore(bool, &me.done, true, .release);
        me.wait = .none;
        _ = s.progress.fetchAdd(1, .acq_rel);
        me.granted = false;
        back.granted = true;
        back.parked = false;
        s.cond.broadcast(s.io);
    }

    /// The task `me` has ended: mark it and give its permit to the next ready task.
    pub fn finish(s: *Sched, me: *Task) void {
        s.lock();
        defer s.unlock();
        @atomicStore(bool, &me.done, true, .release);
        _ = s.progress.fetchAdd(1, .seq_cst);
        _ = s.finishes.fetchAdd(1, .seq_cst);
        s.releasePermit(me);
        _ = s.dispatch(me.index);
        while (s.running.load(.monotonic) == 0 and s.stuck()) _ = s.dispatch(me.index);
        s.cond.broadcast(s.io);
    }
};
