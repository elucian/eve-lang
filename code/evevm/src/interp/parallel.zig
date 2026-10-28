//! @eve-module interp.parallel
//! @spec spec/semantics/multitasking.md
//! @feature F-MTK-01, F-MTK-03, F-MTK-04
//! @decision D-144
//! @tests test/level4
//! Level 4: parallel groups, channels and tasks (spec/semantics/multitasking.md).
//! Part of the interpreter (interp.zig): every function takes the interpreter as `it: *Interp`, and
//! `Interp` names each of them again, so a call reads `it.name(...)` wherever it is made.
const std = @import("std");
const Io = std.Io;
const interp = @import("../interp.zig");
const Interp = interp.Interp;
const task = interp.task;
const heap = interp.heap;
const profile = @import("../profile.zig");
const Heap = interp.Heap;
const Node = interp.Node;
const value = interp.value;
const host_mod = @import("../host.zig");
const db = @import("../db.zig");
const Signal = interp.Signal;
const Value = interp.Value;
const Channel = interp.Channel;
const List = interp.List;
const Var = interp.Var;
const Scope = interp.Scope;
const Arg = interp.Arg;
const Started = interp.Started;
const Group = interp.Group;
const Outcome = interp.Outcome;
const transfer = @import("evecm").transfer;

// ---- level 4: parallel groups, channels, tasks (spec/semantics/multitasking.md) -----------------

/// The interpreter that owns the modules of the run: the root aspect's.
/// The interface that lets the database layer use this interpreter (host.zig).
pub fn host(it: *Interp) host_mod.Host {
    return host_mod.of(it);
}

pub fn base(it: *Interp) *Interp {
    return it.root orelse it;
}

// @eve-impl how many lanes run at a time: `$cores`, or `EVE_CORES`; one when the debugger or a step hook watches the run
// @spec spec/semantics/multitasking.md#implementation-notes
/// The number of cores the tasks of this run may use.
pub fn coresToUse(it: *Interp) u32 {
    if (it.dbg != null) return 1;
    if (std.c.getenv("EVE_CORES")) |z| {
        const n = std.fmt.parseInt(u32, std.mem.span(z), 10) catch 0;
        if (n >= 1) return @min(n, 64);
    }
    if (it.scope.find("$cores")) |v| if (Interp.isInt(v.value) and Interp.intOf(v.value) >= 1) return @intCast(Interp.intOf(v.value));
    return 1;
}

/// The scheduler of the run, made on first use; the root aspect's thread becomes the root task.
pub fn ensureSched(it: *Interp) Signal!*task.Sched {
    if (it.sched) |s| return s;
    const io = it.io orelse return it.fail("parallel work needs the machine: no input/output handle", .{});
    const s = task.Sched.init(it.a, io, it.coresToUse()) catch return error.OutOfMemory;
    it.sched = s;
    it.me = s.root();
    return s;
}

/// The text of a duration in milliseconds: `100ms`, `2s`, `5m`, `1h`.
pub fn durText(it: *Interp, ms: i64) Signal![]const u8 {
    if (ms > 0 and @rem(ms, 3_600_000) == 0) return std.fmt.allocPrint(it.t, "{d}h", .{@divTrunc(ms, 3_600_000)});
    if (ms > 0 and @rem(ms, 60_000) == 0) return std.fmt.allocPrint(it.t, "{d}m", .{@divTrunc(ms, 60_000)});
    if (ms > 0 and @rem(ms, 1000) == 0) return std.fmt.allocPrint(it.t, "{d}s", .{@divTrunc(ms, 1000)});
    return std.fmt.allocPrint(it.t, "{d}ms", .{ms});
}

// @decision D-140
/// Stop this task when its group asked it to: a cancel or a time-out.
pub fn checkCancel(it: *Interp) Signal!void {
    const me = it.me orelse return;
    if (it.root == null) return;
    switch (me.cancelOf()) {
        .none => {},
        .cancel => return error.Cancel,
        .timeout => {
            @atomicStore(task.Cancel, &me.cancel, .none, .release);
            return it.failWith(41, "Time-out after {s}", .{try it.durText(me.limit_ms)});
        },
    }
}

/// `wait ms;`: pause this task, letting the others run.
pub fn waitFor(it: *Interp, ms: i64) Signal!void {
    if (ms <= 0) return;
    if (it.sched) |s| {
        const me = it.me.?;
        const until = s.now() + ms;
        while (s.now() < until and me.cancelOf() == .none) {
            me.wait = .sleep;
            me.wake_at = until;
            s.yield(me);
            me.wait = .none;
        }
        return it.checkCancel();
    }
    if (it.io) |io| Io.sleep(io, .fromMilliseconds(ms), .awake) catch {};
}

/// Wait until the channel `ch` may have changed; raise a deadlock or a cancel when asked to.
pub fn blockOn(it: *Interp, wait: task.Wait, ch: *Channel, since: *?i64, seen: u64) Signal!void {
    const s = it.sched orelse return it.deadlock(wait, ch); // no other task: it would wait forever
    const me = it.me.?;
    if (s.spinFor(seen)) return; // the channel changed while we looked: the caller looks again
    const limit = it.timeoutMs();
    if (since.* == null) since.* = s.now();
    me.wait = wait;
    me.blocked_at = seen; // the progress read before the channel was looked at: a change since then wakes the task
    me.timer = true;
    me.wake_at = since.*.? + limit;
    s.yield(me);
    me.wait = .none;
    me.timer = false;
    if (me.deadlock) {
        me.deadlock = false;
        return it.deadlock(wait, ch);
    }
    try it.checkCancel();
    if (s.now() >= since.*.? + limit) return it.failWith(41, "Time-out after {s}", .{try it.durText(limit)});
}

// @decision D-081
/// The longest wait on a channel, in milliseconds.
pub fn timeoutMs(it: *Interp) i64 {
    if (it.scope.find("$timeout")) |v| if (Interp.msOf(v.value)) |ms| if (ms > 0) return ms;
    return 60_000;
}

/// Raise DeadlockError for this task, naming the operation and the channel (D-141).
pub fn deadlock(it: *Interp, wait: task.Wait, ch: *Channel) Signal {
    const op = if (wait == .send) "send to" else "receive from";
    return it.failWith(42, "Deadlock: {s} waits to {s} {s}", .{ it.task_name, op, ch.name });
}

// @decision D-141
/// `Channel(:T)(capacity: n, senders: m)`.
pub fn newChannel(it: *Interp, arg_nodes: []const *const Node) Signal!Value {
    const args = try it.evalArgs(arg_nodes);
    var capacity: ?i64 = null;
    var senders: i64 = 1;
    for (args, 0..) |a, i| {
        if (!Interp.isInt(a.value)) return it.fail("the arguments of a Channel are integers", .{});
        const named_cap = std.mem.eql(u8, a.name, "capacity") or (a.name.len == 0 and i == 0);
        const named_snd = std.mem.eql(u8, a.name, "senders") or (a.name.len == 0 and i == 1);
        if (named_cap) capacity = Interp.intOf(a.value) else if (named_snd) senders = Interp.intOf(a.value) else return it.fail("a Channel has no parameter '{s}'", .{a.name});
    }
    const cap = capacity orelse return it.fail("a Channel needs its capacity: Channel(:T)(capacity: n)", .{});
    if (cap < 1 or senders < 1) return it.fail("the capacity and the senders of a Channel are at least 1", .{});
    const ch = try it.h.make(Channel, .{ .capacity = @intCast(cap), .senders = @intCast(senders) });
    // @eve-impl a channel is shared by the tasks: nobody counts it, and its messages live in a heap of its own
    ch.hdr.pinned = true;
    const mem = try it.h.gpa.create(Heap);
    mem.* = Heap.initTask(it.h.gpa);
    mem.pushRegion();
    ch.mem = mem;
    return .{ .chan = ch };
}

/// Note a change that a waiting task may be interested in.
pub fn moved(it: *Interp) void {
    if (it.sched) |s| s.bump(it.me);
}

/// The progress counter now: read it before looking at the state a task is going to wait for.
pub fn progressNow(it: *Interp) u64 {
    return if (it.sched) |s| s.progressNow() else 0;
}

// @decision D-141
/// `ch.send(v)`: wait while the channel is full; a closed channel is an error.
pub fn send(it: *Interp, ch: *Channel, v: Value) Signal!void {
    var since: ?i64 = null;
    while (true) {
        const seen = it.progressNow();
        ch.mutex.lock();
        if (ch.closed) {
            ch.mutex.unlock();
            return it.failWith(46, "Channel {s} is closed", .{ch.name});
        }
        if (ch.buf.items.len < ch.capacity) {
            defer ch.mutex.unlock();
            const mem = ch.mem.?;
            const c = transfer.copyInto(mem, v) catch |e| return it.borderFailed(e);
            try ch.buf.append(mem.gpa, c);
            Heap.retain(c);
            mem.safePoint();
            for (it.sent.items) |x| if (x == ch) break else {} else try it.sent.append(it.a, ch);
            it.moved();
            return;
        }
        ch.mutex.unlock();
        try it.blockOn(.send, ch, &since, seen);
    }
}

/// Take the first value; wait while the channel is empty and open.
pub fn receive(it: *Interp, ch: *Channel) Signal!?Value {
    var since: ?i64 = null;
    while (true) {
        const seen = it.progressNow();
        ch.mutex.lock();
        if (ch.buf.items.len > 0) {
            defer ch.mutex.unlock();
            const mem = ch.mem.?;
            const m = ch.buf.orderedRemove(0);
            const v = transfer.copyInto(it.h, m) catch |e| return it.borderFailed(e);
            mem.release(m);
            mem.safePoint();
            it.moved();
            return v;
        }
        const closed = ch.closed;
        ch.mutex.unlock();
        if (closed) return null;
        try it.blockOn(.receive, ch, &since, seen);
    }
}

/// `ch.close()`: this sender has finished; the channel closes after `senders` closes.
pub fn closeChannel(it: *Interp, ch: *Channel) Signal!void {
    for (it.closed.items) |x| if (x == ch) return; // a second close by the same task does nothing
    ch.mutex.lock();
    if (ch.closed) {
        ch.mutex.unlock();
        return it.failWith(46, "Channel {s} is closed", .{ch.name});
    }
    it.closed.append(it.a, ch) catch {
        ch.mutex.unlock();
        return error.OutOfMemory;
    };
    ch.closes += 1;
    if (ch.closes >= ch.senders) ch.closed = true;
    ch.mutex.unlock();
    it.moved();
}

/// At the end of a task: close every channel it has sent into and not closed (D-141).
pub fn closeSent(it: *Interp) void {
    for (it.sent.items) |ch| it.closeChannel(ch) catch {};
}

/// The methods of a channel: `send`, `receive`, `close`, `count`.
pub fn channelMethod(it: *Interp, ch: *Channel, name: []const u8, args: []const *const Node) Signal!Value {
    const eql = std.mem.eql;
    if (eql(u8, name, "send") and args.len == 1) {
        try it.send(ch, try it.eval(args[0]));
        return .nil;
    }
    if (eql(u8, name, "receive") and args.len == 1 and args[0].tag == .ref) {
        const v = (try it.receive(ch)) orelse return it.failWith(46, "Channel {s} is closed", .{ch.name});
        const cell = it.scope.find(args[0].text) orelse return it.fail("undefined name '{s}'", .{args[0].text});
        it.setVar(cell, v);
        return .nil;
    }
    if (eql(u8, name, "close") and args.len == 0) {
        try it.closeChannel(ch);
        return .nil;
    }
    if (eql(u8, name, "count") and args.len == 0) {
        ch.mutex.lock();
        defer ch.mutex.unlock();
        return .{ .int = @intCast(ch.buf.items.len) };
    }
    return it.fail("Channel has no method '{s}'", .{name});
}

/// `lst.batch(n)`: parts of `n` elements, the last one shorter; `lst.split(k)`: `k` nearly equal parts (D-142).
pub fn cut(it: *Interp, l: *List, by_count: bool, size: Value) Signal!Value {
    if (!Interp.isInt(size) or Interp.intOf(size) < 1) return it.fail("{s} takes a positive integer", .{if (by_count) "split" else "batch"});
    const items = l.elems();
    const n: usize = @intCast(Interp.intOf(size));
    const out = try it.newList(&.{}, false);
    var from: usize = 0;
    var k: usize = 0;
    while (from < items.len or (by_count and k < n)) : (k += 1) {
        if (by_count and k == n) break;
        const len = if (by_count) items.len / n + @intFromBool(k < items.len % n) else @min(n, items.len - from);
        try it.listAppend(out, .{ .list = try it.newList(items[from .. from + len], false) });
        from += len;
    }
    return .{ .list = out };
}

/// The argument `@s[i]`: a reference to one element of a list.
pub fn elementRef(it: *Interp, r: *const Node) Signal!Arg {
    const chain = try it.indexChain(r.kids[0]);
    if (chain.obj != .list) return it.fail("@{s}[...] needs a list or an array", .{r.text});
    var cells: std.ArrayList(*Value) = .empty;
    try it.slots(chain.obj.list, chain.args, &cells);
    if (cells.items.len != 1) return it.fail("@{s}[...] must name one element", .{r.text});
    // the argument owns the variable (count 1) until `dropArgs`
    const v = try it.h.make(Var, .{ .value = cells.items[0].* });
    Heap.retain(v.value);
    Heap.retainVar(v);
    return .{ .value = v.value, .ref = v, .cell = cells.items[0] };
}

/// Put the values of the `@s[i]` arguments back into their elements.
pub fn writeBack(it: *Interp, args: []const Arg) void {
    for (args) |a| if (a.cell) |c| {
        it.setCell(c, a.ref.?.value);
    };
}

// @eve-impl a task has a heap of its own (`own_heap`); a generator body is a coroutine of its caller and uses the caller's heap
// @spec spec/semantics/multitasking.md#data-rules
// @see design/design-task-heap.md
/// A new interpreter for a task, writing to `out`.
pub fn newChild(it: *Interp, out: *Io.Writer, name: []const u8, own_heap: bool) Signal!*Interp {
    const c = try it.a.create(Interp);
    const sc = try Interp.newScratch(it.a);
    var hp = it.h;
    if (own_heap) {
        hp = try it.a.create(Heap);
        hp.* = Heap.initTask(std.heap.smp_allocator);
        hp.pushRegion(); // the region of the whole task
    }
    c.* = .{
        .a = it.a,
        .t = sc.allocator(),
        .scratch = sc,
        .h = hp,
        .g = hp.gpa,
        .out = out,
        .global = it.global,
        .scope = it.global,
        .unit = it.unit,
        .io = it.io,
        .sched = it.sched,
        .root = it.base(),
        .own_heap = own_heap,
        .aspects = it.aspects,
        .modules = it.modules,
        .task_name = name,
    };
    try c.exts.appendSlice(it.a, it.exts.items);
    if (own_heap) {
        hp.root_fn = Interp.roots;
        hp.root_ctx = c;
        hp.finalizer = .{ .ctx = c, .run = Interp.finalizeObject };
    }
    return c;
}

/// The error of a copy across a border, as an Eve error.
pub fn borderFailed(it: *Interp, e: transfer.Error) Signal {
    _ = it;
    return switch (e) {
        error.OutOfMemory => error.OutOfMemory,
    };
}

// @eve-impl the tasks read the names of the aspect that created them: its scope and its constants are pinned, so no heap counts them
// @invariant the unit scope of an aspect that created a task is pinned
/// Let the tasks created from `it` read the names of its aspect.
fn shareUnit(it: *Interp) void {
    const u = it.unit;
    if (u.hdr.pinned) return;
    u.hdr.pinned = true;
    for (u.binds.items) |b| {
        if (b.v.constant or b.v.value == .chan or b.v.value == .func) {
            b.v.hdr.pinned = true;
            Heap.pinDeep(b.v.value);
        }
    }
}

/// Make the task record and its thread.
pub fn launch(it: *Interp, st: *Started) Signal!void {
    const s = it.sched.?;
    st.job = .{ .run = taskMainJob, .arg = st };
    task.submit(s.io, &st.job) catch {
        s.abandon(st.t);
        return it.fail("cannot start a thread for {s}", .{st.label});
    };
    st.t.job = &st.job;
    s.kick(it.me orelse s.root());
}

// @decision D-048
// @eve-impl the arguments of a task are copies in its own heap; an output (`@x`) is a variable of the task, copied back at `done` (`endTasks`)
// @spec spec/semantics/multitasking.md#data-rules
/// The arguments of the task `child` as it sees them.
pub fn childArgs(it: *Interp, child: *Interp, args: []const Arg) Signal![]Arg {
    const out = try it.a.alloc(Arg, args.len);
    for (args, out) |a, *o| {
        const v = transfer.copyInto(child.h, a.value) catch |e| return it.borderFailed(e);
        Heap.retain(v); // held until the heap of the task ends
        o.* = .{ .name = a.name, .value = v };
        if (a.ref != null) {
            const cell = try child.h.make(Var, .{ .value = v });
            Heap.retain(v);
            Heap.retainVar(cell);
            o.ref = cell;
        }
    }
    return out;
}

/// Refuse an output that another task of the group already owns: `$err_output` 43 (D-140).
pub fn ownOutputs(it: *Interp, g: Group, nodes: []const *const Node, args: []const Arg) Signal!void {
    for (args, 0..) |a, i| {
        const r = a.ref orelse continue;
        if (r.value == .chan) continue;
        const addr = if (a.cell) |c| @intFromPtr(c) else @intFromPtr(r);
        const name = if (i < nodes.len) (if (nodes[i].tag == .pair) nodes[i].kids[1].text else nodes[i].text) else "?";
        for (g.owned.items) |o| if (o == addr) return it.failWith(43, "Output {s} is given to two tasks of the group", .{name});
        try g.owned.append(it.a, addr);
    }
}

// @eve-impl a start beyond `$max_parallel` waits until a task of the group has ended
// @spec spec/semantics/multitasking.md#where-a-group-is-allowed
// @test d49_max_parallel
/// Wait while the group already runs `$max_parallel` tasks.
fn throttle(it: *Interp, g: Group, s: *task.Sched) Signal!void {
    var limit: usize = 8;
    if (it.scope.find("$max_parallel")) |v| if (Interp.isInt(v.value) and Interp.intOf(v.value) >= 1) {
        limit = @intCast(Interp.intOf(v.value));
    };
    const me = it.me.?;
    while (true) {
        const seen = s.finishedNow();
        var running: usize = 0;
        for (g.list.items) |m| if (!m.t.isDone()) {
            running += 1;
        };
        if (running < limit) return;
        me.wait = .join;
        me.blocked_at = seen;
        s.yield(me);
        me.wait = .none;
        try it.checkCancel();
    }
}

/// `start name(args);`: start a concurrent aspect in the group whose do region runs (D-140).
pub fn startAspect(it: *Interp, n: *const Node) Signal!void {
    const g = it.group orelse return it.fail("start is allowed only in the do region of a parallel group", .{});
    const s = try it.ensureSched();
    try throttle(it, g, s);
    if (n.sel) |prc| return it.startPrivate(n, prc, g, s);
    const known = it.aspects orelse return it.fail("no aspect is loaded: '{s}'", .{n.text});
    const aspect = known.get(n.text) orelse return it.fail("aspect '{s}' is not loaded", .{n.text});
    const args = try it.a.dupe(Arg, try it.evalArgs(n.kids));
    try it.ownOutputs(g, n.kids, args);
    // @eve-impl the modules of the aspect are loaded here, in the heap of the root task, which outlives every task
    // @invariant a module is made by the root task only
    for (aspect.kids) |d| if (d.tag == .import_decl) {
        const saved = try it.pushScope();
        defer it.leaveScope(saved);
        try it.execImport(d);
    };
    const buf = try it.a.create(Io.Writer.Allocating);
    buf.* = .init(it.a);
    const child = try it.newChild(&buf.writer, aspect.text, true);
    const st = try it.a.create(Started);
    st.* = .{
        .t = try s.add(null),
        .label = aspect.text,
        .aspect = aspect,
        .args = args,
        .cargs = try it.childArgs(child, args),
        .child = child,
        .out = buf,
        .siblings = g.list,
        .cancel_policy = g.cancel,
    };
    st.child.me = st.t;
    try g.list.append(it.a, st);
    try it.launch(st);
}

// @decision D-179
/// `start name(args);` where `name` is a private process of the concurrent aspect that contains the call.
pub fn startPrivate(it: *Interp, n: *const Node, prc: *const Node, g: Group, s: anytype) Signal!void {
    const args = try it.a.dupe(Arg, try it.evalArgs(n.kids));
    try it.ownOutputs(g, n.kids, args);
    shareUnit(it);
    const buf = try it.a.create(Io.Writer.Allocating);
    buf.* = .init(it.a);
    const child = try it.newChild(&buf.writer, prc.text, true);
    const st = try it.a.create(Started);
    st.* = .{
        .t = try s.add(null),
        .label = prc.text,
        .proc = prc,
        .unit = it.unit,
        .args = args,
        .cargs = try it.childArgs(child, args),
        .child = child,
        .out = buf,
        .siblings = g.list,
        .cancel_policy = g.cancel,
    };
    st.child.me = st.t;
    try g.list.append(it.a, st);
    try it.launch(st);
}

// @decision D-104
/// `spawn f(args);`: start an async procedure as a task of the job (D-143).
pub fn spawnTask(it: *Interp, n: *const Node) Signal!void {
    const list = it.job_tasks orelse return it.fail("spawn is allowed only in the do region of a job", .{});
    const s = try it.ensureSched();
    const call_node = n.kids[0];
    const fv = try it.eval(call_node.kids[0]);
    if (fv != .func) return it.fail("spawn starts an async procedure", .{});
    const args = try it.a.dupe(Arg, try it.evalArgs(call_node.kids[1..]));
    // @eve-impl a task of a job shares the core, the heap and the output of its caller and runs only while the caller waits (multitasking.md#tasks-in-a-job): its inputs are copies in that heap
    for (args) |*a| if (a.ref == null and a.value != .chan) {
        a.value = try it.clone(a.value);
    };
    const child = try it.newChild(it.out, fv.func.node.text, false);
    const st = try it.a.create(Started);
    st.* = .{
        .t = try s.add((it.me orelse s.root()).lane),
        .label = fv.func.node.text,
        .func = fv.func,
        .args = args,
        .cargs = args,
        .child = child,
        .siblings = list,
    };
    st.child.me = st.t;
    st.child.current_job = it.current_job;
    try list.append(it.a, st);
    it.h.pause(); // nothing is freed while a task of the job may run: they share this heap (heap.zig)
    try it.launch(st);
}

/// The thread of a task: wait for the baton, run, record the outcome, hand the baton on.
fn taskMainJob(arg: *anyopaque) void {
    taskMain(@ptrCast(@alignCast(arg)));
}

pub fn taskMain(st: *Started) void {
    const c = st.child;
    const s = c.sched.?;
    s.waitTurn(st.t);
    if (st.t.cancelOf() != .none) {
        st.cancelled = true; // cancelled before it began: it never runs
    } else {
        const outcome = if (st.proc) |prc| c.runPrivate(prc, st.cargs, st.unit.?) else if (st.aspect) |asp| c.runAspect(asp, st.cargs) else blk: {
            _ = c.invokeWith(st.func.?, null, st.cargs) catch |e| break :blk e;
            break :blk {};
        };
        outcome catch |e| switch (e) {
            error.Cancel => st.cancelled = true,
            error.Raise, error.Abort => {
                st.failed = true;
                if (c.reports.items.len > 0) st.report = c.reports.items[c.reports.items.len - 1];
            },
            else => {
                st.failed = true;
                st.report = .{ .line = c.line, .code = if (e == error.Panic) 1 else 4, .message = @errorName(e), .job = "" };
            },
        };
    }
    c.closeSent();
    c.setProc(null);
    if (st.failed and st.cancel_policy) {
        for (st.siblings.items) |o| if (o != st and !o.t.isDone() and o.t.cancelOf() == .none) {
            s.cancelTask(o.t, .cancel, 0);
        };
    }
    s.finish(st.t);
}

/// The state of a running `job` between its start and its `done`.
pub const JobState = struct {
    name: []const u8,
    saved_job: []const u8,
    saved_tasks: ?*std.ArrayList(*Started),
    spawned: *std.ArrayList(*Started),
    scope: *Scope,
};

// @eve-impl the start of a `job`: the label, the list of the tasks spawned in it (D-143), and a scope for each attempt (control.md#job)
// @spec spec/semantics/control.md#job
// @see code/evecm/src/op.zig:jobbegin
pub fn jobBegin(it: *Interp, name: []const u8) Signal!JobState {
    const spawned = try it.a.create(std.ArrayList(*Started));
    spawned.* = .empty;
    const scope = try it.pushScope();
    const st: JobState = .{ .name = name, .saved_job = it.current_job, .saved_tasks = it.job_tasks, .spawned = spawned, .scope = scope };
    it.current_job = name;
    it.job_tasks = spawned;
    return st;
}

// @eve-impl the end of a `job`: wait for its tasks, flush and commit when it went well, roll back otherwise, set the state of the job
// @spec spec/semantics/control.md#job
pub fn jobFinish(it: *Interp, st: JobState, outcome: Signal!void, after_end: ?*const fn (*Interp) void) Signal!void {
    defer {
        it.current_job = st.saved_job;
        it.job_tasks = st.saved_tasks;
    }
    it.leaveScope(st.scope);
    const spawned = st.spawned;
    if (spawned.items.len > 0) {
        try it.joinTasks(spawned, null, 0);
        try it.endTasks(spawned);
        it.h.resume_(@intCast(spawned.items.len));
    }
    if (after_end) |cb| cb(it);
    it.collectAtDone();
    // the end of the job: flush and commit when it went well, roll back otherwise (database.md, transactions)
    const rolled_back = if (outcome) |_| false else |e| e == error.JobRollback;
    const went_well = if (outcome) |_| true else |e| e == error.StopJob;
    host_mod.enterDb(it.io);
    const closed: Signal!void = db.orm.endJob(it.host(), went_well);
    host_mod.leaveDb(it.io);
    if (rolled_back) {
        it.setJob(st.name, "rolled back");
        return;
    }
    closed catch |e| {
        it.setJob(st.name, "fail");
        return e;
    };
    outcome catch |e| switch (e) {
        error.StopJob => {},
        else => {
            it.setJob(st.name, "fail");
            return e;
        },
    };
    it.raiseFailed(spawned, st.name) catch |e| {
        it.setJob(st.name, "fail");
        return e;
    };
    it.setJob(st.name, "pass");
}

/// The state of a running `parallel` group between its start and its `done`.
pub const ParState = struct {
    scope: *Scope,
    saved_job: []const u8,
    saved_group: ?Group,
    members: *std.ArrayList(*Started),
    deadline: ?i64,
    limit: i64,
    label: []const u8,
};

// @eve-impl the start of a `parallel` group: a scope, the label as the job, a group for the `start` statements; `within` is evaluated
// @spec spec/semantics/multitasking.md#where-a-group-is-allowed
// @see code/evecm/src/op.zig:parbegin
pub fn parBegin(it: *Interp, label: []const u8, cancel: bool, within: ?Value) Signal!ParState {
    const s = try it.ensureSched();
    var deadline: ?i64 = null;
    var limit: i64 = 0;
    if (within) |d| {
        limit = Interp.msOf(d) orelse return it.fail("within takes a duration: within 30s", .{});
        deadline = s.now() + limit;
    }
    const saved = try it.pushScope();
    const saved_job = it.current_job;
    it.current_job = label;
    const members = try it.a.create(std.ArrayList(*Started));
    members.* = .empty;
    const owned = try it.a.create(std.ArrayList(usize));
    owned.* = .empty;
    const saved_group = it.group;
    it.group = .{ .list = members, .cancel = cancel, .owned = owned };
    return .{ .scope = saved, .saved_job = saved_job, .saved_group = saved_group, .members = members, .deadline = deadline, .limit = limit, .label = label };
}

// @eve-impl the end of a `parallel` group: wait for the tasks, write their outputs, report the failures of the group
pub fn parFinish(it: *Interp, st: ParState, outcome: Signal!void, after_end: ?*const fn (*Interp) void) Signal!void {
    defer {
        it.leaveScope(st.scope);
        it.current_job = st.saved_job;
        it.group = st.saved_group;
    }
    it.group = st.saved_group;
    try it.joinTasks(st.members, st.deadline, st.limit);
    try it.endTasks(st.members);
    if (after_end) |cb| cb(it);
    it.collectAtDone();
    try outcome;
    try it.raiseFailed(st.members, st.label);
}

/// `[label:] parallel ... do ... done [label];` (D-140).
pub fn parallelGroup(it: *Interp, n: *const Node) Signal!void {
    const within: ?Value = if (n.kids[2].tag != .none) try it.eval(n.kids[2]) else null;
    const st = try it.parBegin(n.text, n.public, within);
    var outcome: Signal!void = {};
    it.execBlock(n.kids[0]) catch |e| {
        outcome = e;
    };
    if (outcome) |_| {
        it.execBlock(n.kids[1]) catch |e| {
            outcome = e;
        };
    } else |_| {}
    return it.parFinish(st, outcome, null);
}

/// An output (`@x`) of a task that the bytecode machine started: the cell the task writes at `done`, and the stack slot of the variable.
pub const Out = struct { cell: *Var, slot: usize };

/// Wait at `done` for every task of `members`; give a time-out at the deadline.
pub fn joinTasks(it: *Interp, members: *std.ArrayList(*Started), deadline: ?i64, limit: i64) Signal!void {
    const s = it.sched.?;
    const me = it.me.?;
    var timed_out = false;
    while (true) {
        const seen = s.finishedNow();
        var all = true;
        for (members.items) |m| if (!m.t.isDone()) {
            all = false;
        };
        if (all) break;
        if (deadline) |d| if (!timed_out and s.now() >= d) {
            timed_out = true;
            for (members.items) |m| if (!m.t.isDone()) s.cancelTask(m.t, .timeout, limit);
        };
        me.wait = .join;
        me.blocked_at = seen;
        me.timer = deadline != null and !timed_out;
        if (me.timer) me.wake_at = deadline.?;
        s.yield(me);
        me.wait = .none;
        me.timer = false;
    }
    for (members.items) |m| if (m.t.job) |j| {
        j.wait();
        m.t.job = null;
    };
}

// @decision D-140
/// After `done`: write the output of each task in the order of start, its log messages, its outputs.
pub fn endTasks(it: *Interp, members: *std.ArrayList(*Started)) Signal!void {
    for (members.items) |m| {
        if (!m.child.own_heap) {
            // a task of a job: it used the heap and the output of its caller, and wrote its outputs itself
            try it.logs.appendSlice(it.a, m.child.logs.items);
            it.writeBack(m.args);
            it.dropArgs(m.args);
            m.child.scratch.deinit();
            continue;
        }
        m.child.h.finalizeAll(); // the destructors of what the task left alive
        if (m.out) |b| try it.out.writeAll(b.written());
        try it.logs.appendSlice(it.a, m.child.logs.items);
        for (m.args, m.cargs) |a, ca| {
            const cv = (ca.ref orelse continue).value;
            if (cv == .chan) continue;
            const nv = transfer.copyInto(it.h, cv) catch |e| return it.borderFailed(e);
            if (a.cell) |c| it.setCell(c, nv) else if (a.ref) |r| it.setVar(r, nv);
        }
        it.dropArgs(m.args);
        m.child.scratch.deinit();
        m.child.h.deinit(); // the whole heap of the task goes at once
    }
}

/// Run the tracing collector at `done` when enough was made since the last trace.
pub fn collectAtDone(it: *Interp) void {
    if (it.own_heap and it.h.since_trace > 1_000) it.h.trace();
}

// @decision D-140
/// Raise one ParallelError (code 45) when a task of `members` failed.
pub fn raiseFailed(it: *Interp, members: *std.ArrayList(*Started), label: []const u8) Signal!void {
    var failed: usize = 0;
    var cancelled: i64 = 0;
    const list = try it.newList(&.{}, false);
    var details: std.ArrayList(u8) = .empty;
    for (members.items, 1..) |m, i| {
        if (m.cancelled) cancelled += 1;
        if (!m.failed) continue;
        failed += 1;
        try Interp.appendFmt(&details, it.a, "  task {d} {s}: error {d}: {s}\n", .{ i, m.label, m.report.code, m.report.message });
        const o = try it.newObject();
        try it.setField(o, "index", .{ .int = @intCast(i) });
        try it.setField(o, "aspect", try it.newStr(if (m.aspect != null) m.label else ""));
        try it.setField(o, "code", .{ .int = m.report.code });
        try it.setField(o, "message", try it.newStr(m.report.message));
        try it.setField(o, "job", try it.newStr(label));
        try it.setField(o, "line", .{ .int = m.report.line });
        try it.listAppend(list, .{ .object = o });
    }
    if (failed == 0) return;
    const e = it.failWith(45, "{d} of {d} tasks failed", .{ failed, members.items.len });
    const r = &it.reports.items[it.reports.items.len - 1];
    Heap.pin(.{ .list = list }); // the report outlives every scope
    r.errors = list;
    r.cancelled = cancelled;
    r.details = details.items;
    return e;
}

/// Is `name` declared in `sc` itself?
pub fn hasLocal(sc: *Scope, name: []const u8) bool {
    for (sc.binds.items) |b| if (interp.value.nameEql(b.name, name)) return true;
    return false;
}

pub fn findProcess(root: *const Node, name: []const u8) ?*const Node {
    for (root.kids) |k| {
        if (k.tag == .process and std.mem.eql(u8, k.text, name)) return k;
    }
    return null;
}

/// Run a script: a root aspect (declarations, then `process main`) or a free script (the statements).
pub fn run(it: *Interp, root: *const Node) Outcome {
    it.h.root_fn = Interp.roots;
    it.h.root_ctx = it;
    defer if (heap.show_stats) it.h.report();
    defer if (profile.active) profile.report(it.a);
    it.h.finalizer = .{ .ctx = it, .run = Interp.finalizeObject };
    const result = it.runRoot(root);
    // the destructors of the objects that live to the end of the run, unless the run was cut off (CLS-14)
    if (result) |_| it.h.finalizeAll() else |e| switch (e) {
        error.Stop, error.Panic => {},
        else => it.h.finalizeAll(),
    }
    if (result) |_| return .{ .code = it.base().exit_code } else |e| switch (e) {
        error.Stop => return .{ .stopped = true },
        error.Panic => {
            it.note(1, "panic");
            return .{ .code = 1 };
        },
        error.Raise, error.Abort => return .{ .code = Interp.exitCodeOf(it.err_code) },
        error.Over => return .{ .code = it.base().exit_code },
        error.OutOfMemory => return .{ .code = 70 },
        error.WriteFailed => return .{ .code = 74 },
        else => {
            it.note(4, "break, next, retry or resume used outside its statement");
            return .{ .code = 4 };
        },
    }
}

// @decision D-081
pub fn exitCodeOf(code: u16) u8 {
    return switch (code) {
        2 => 2,
        3 => 3,
        else => 4,
    };
}

pub fn note(it: *Interp, code: u16, msg: []const u8) void {
    it.reports.append(it.a, .{ .line = it.line, .code = code, .message = msg, .job = "" }) catch {};
}
