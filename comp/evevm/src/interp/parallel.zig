//! Level 4: parallel groups, channels and tasks (spec/semantics/multitasking.md).
//! Part of the interpreter (interp.zig): every function takes the interpreter as `it: *Interp`, and
//! `Interp` names each of them again, so a call reads `it.name(...)` wherever it is made.
const std = @import("std");
const Io = std.Io;
// Zig tip: interp.zig imports this file and this file imports interp.zig back. Zig allows such a cycle
// between files of one module: declarations are resolved lazily, when they are used, not in the order
// of the imports. `../` names the parent folder; a module may import any file below its root folder.
const interp = @import("../interp.zig");
const Interp = interp.Interp;
const task = interp.task;
const heap = interp.heap;
const profile = @import("../profile.zig");
const Heap = interp.Heap;
const Node = interp.Node;
const value = interp.value;
const host_mod = @import("../host.zig");
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

// ---- level 4: parallel groups, channels, tasks (spec/semantics/multitasking.md) -----------------

// Zig tip: `orelse` gives the value of an optional or, when it is null, the expression after it:
// the root aspect's interpreter has no `root`, so it is its own base.
/// The interpreter that owns the modules of the run: the root aspect's.
/// The interface that lets the database layer use this interpreter (host.zig).
pub fn host(it: *Interp) host_mod.Host {
    return host_mod.of(it);
}

pub fn base(it: *Interp) *Interp {
    return it.root orelse it;
}

// Zig tip: the scheduler is made only when the first task starts, so a program without parallel
// work never pays for it. `catch return error.OutOfMemory` maps the one error `init` may return
// onto the `Signal` set of the interpreter.
/// The scheduler of the run, made on first use; the root aspect's thread becomes the root task.
pub fn ensureSched(it: *Interp) Signal!*task.Sched {
    if (it.sched) |s| return s;
    const io = it.io orelse return it.fail("parallel work needs the machine: no input/output handle", .{});
    const s = task.Sched.init(it.a, io) catch return error.OutOfMemory;
    it.sched = s;
    it.me = s.root();
    return s;
}

// Zig tip: `@rem` is the remainder of a division (`%` is not allowed on signed integers in Zig
// unless the compiler can prove they are positive). The largest unit that divides the value
// exactly is chosen, so `100` prints `100ms` and `30000` prints `30s`.
/// The text of a duration in milliseconds: `100ms`, `2s`, `5m`, `1h`.
pub fn durText(it: *Interp, ms: i64) Signal![]const u8 {
    if (ms > 0 and @rem(ms, 3_600_000) == 0) return std.fmt.allocPrint(it.t, "{d}h", .{@divTrunc(ms, 3_600_000)});
    if (ms > 0 and @rem(ms, 60_000) == 0) return std.fmt.allocPrint(it.t, "{d}m", .{@divTrunc(ms, 60_000)});
    if (ms > 0 and @rem(ms, 1000) == 0) return std.fmt.allocPrint(it.t, "{d}s", .{@divTrunc(ms, 1000)});
    return std.fmt.allocPrint(it.t, "{d}ms", .{ms});
}

// Zig tip: a `switch` on an enum value with one prong per case; `.none => {}` does nothing. The
// time-out is an ordinary error (code 41) that the aspect may see in its `recover`; the flag is
// cleared first, so it is raised once. `on error cancel` uses the internal `error.Cancel`, which no
// `recover` catches: the task simply stops (D-140).
/// Stop this task when its group asked it to: a cancel or a time-out.
pub fn checkCancel(it: *Interp) Signal!void {
    const me = it.me orelse return;
    if (it.root == null) return;
    switch (me.cancel) {
        .none => {},
        .cancel => return error.Cancel,
        .timeout => {
            me.cancel = .none;
            return it.failWith(41, "Time-out after {s}", .{try it.durText(me.limit_ms)});
        },
    }
}

// Zig tip: `Io.sleep` takes the handle, a duration and the clock. With tasks, a sleeping task gives
// the baton away instead (`yield`), so the others run while it waits: the loop ends when the time
// has come or when the group stops the task.
/// `wait ms;`: pause this task, letting the others run.
pub fn waitFor(it: *Interp, ms: i64) Signal!void {
    if (ms <= 0) return;
    if (it.sched) |s| {
        const me = it.me.?;
        const until = s.now() + ms;
        while (s.now() < until and me.cancel == .none) {
            me.wait = .sleep;
            me.wake_at = until;
            s.yield(me);
            me.wait = .none;
        }
        return it.checkCancel();
    }
    if (it.io) |io| Io.sleep(io, .fromMilliseconds(ms), .awake) catch {};
}

// Zig tip: `blockOn` is the one place where a task waits for a channel. It records what it waits for
// and the `progress` counter, gives the baton away, and comes back when something changed; the
// caller then looks at the channel again (a `while` loop around the call).
/// Wait until the channel `ch` may have changed; raise a deadlock or a cancel when asked to.
pub fn blockOn(it: *Interp, wait: task.Wait, ch: *Channel, since: *?i64) Signal!void {
    const s = it.sched orelse return it.deadlock(wait, ch); // no other task: it would wait forever
    const me = it.me.?;
    const limit = it.timeoutMs();
    if (since.* == null) since.* = s.now();
    me.wait = wait;
    me.blocked_at = s.progress;
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

// Zig tip: `$timeout` is an ordinary variable: an aspect shadows the root aspect value with its own
// `set $timeout = 5s;` (D-081 rule 8), so the scope chain gives the right one. The default is 60 seconds.
/// The longest wait on a channel, in milliseconds.
pub fn timeoutMs(it: *Interp) i64 {
    if (it.scope.find("$timeout")) |v| if (Interp.isInt(v.value) and Interp.intOf(v.value) > 0) return Interp.intOf(v.value);
    return 60_000;
}

// Zig tip: the return type `Signal` without `!` is an error value itself: the caller writes
// `return it.deadlock(...)` and the error travels up like any `raise`.
/// Raise DeadlockError for this task, naming the operation and the channel (D-141).
pub fn deadlock(it: *Interp, wait: task.Wait, ch: *Channel) Signal {
    const op = if (wait == .send) "send to" else "receive from";
    return it.failWith(42, "Deadlock: {s} waits to {s} {s}", .{ it.task_name, op, ch.name });
}

// Zig tip: named arguments arrive as `Arg` records with a `name`; a positional one has an empty name.
// `capacity` is the first parameter and is required, `senders` the second (D-141).
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
    return .{ .chan = ch };
}

// Zig tip: `if (opt) |s|` runs only when the optional holds a value: without tasks there is no
// scheduler and nobody to wake.
/// Note a change that a waiting task may be interested in.
pub fn moved(it: *Interp) void {
    if (it.sched) |s| s.progress += 1;
}

// Zig tip: `for (list.items) |x| if (x == ch) return;` searches a list of pointers: two pointers are
// equal when they point to the same channel. The value is copied on send (`clone`), so a receiver
// never shares a collection with the sender (D-141).
/// `ch.send(v)`: wait while the channel is full; a closed channel is an error.
pub fn send(it: *Interp, ch: *Channel, v: Value) Signal!void {
    var since: ?i64 = null;
    while (true) {
        if (ch.closed) return it.failWith(46, "Channel {s} is closed", .{ch.name});
        if (ch.buf.items.len < ch.capacity) {
            const c = try it.clone(v);
            try ch.buf.append(it.g, c);
            Heap.retain(c);
            for (it.sent.items) |x| if (x == ch) break else {} else try it.sent.append(it.a, ch);
            it.moved();
            return;
        }
        try it.blockOn(.send, ch, &since);
    }
}

// Zig tip: the result `?Value` is null when the channel is closed and empty: the `for` loop ends
// there, and `ch.receive(@x)` turns it into an error.
/// Take the first value; wait while the channel is empty and open.
pub fn receive(it: *Interp, ch: *Channel) Signal!?Value {
    var since: ?i64 = null;
    while (true) {
        if (ch.buf.items.len > 0) {
            const v = ch.buf.orderedRemove(0);
            it.h.release(v);
            it.moved();
            return v;
        }
        if (ch.closed) return null;
        try it.blockOn(.receive, ch, &since);
    }
}

// Zig tip: `closeChannel` relies on the same Zig feature as `send` above: see the tip there.
/// `ch.close()`: this sender has finished; the channel closes after `senders` closes.
pub fn closeChannel(it: *Interp, ch: *Channel) Signal!void {
    for (it.closed.items) |x| if (x == ch) return; // a second close by the same task does nothing
    if (ch.closed) return it.failWith(46, "Channel {s} is closed", .{ch.name});
    try it.closed.append(it.a, ch);
    ch.closes += 1;
    if (ch.closes >= ch.senders) ch.closed = true;
    it.moved();
}

// Zig tip: `catch {}` drops the error of a close on purpose: the task is over, and a channel that
// is already closed needs nothing more.
/// At the end of a task: close every channel it has sent into and not closed (D-141).
pub fn closeSent(it: *Interp) void {
    for (it.sent.items) |ch| it.closeChannel(ch) catch {};
}

// Zig tip: `orelse return ...` turns the null of a closed, empty channel into the error of `receive`;
// `cell.value = v` writes through the pointer of the `@x` variable.
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
    if (eql(u8, name, "count") and args.len == 0) return .{ .int = @intCast(ch.buf.items.len) };
    return it.fail("Channel has no method '{s}'", .{name});
}

// Zig tip: the parts are views would share the storage; here they are new lists, so a task that
// receives one by value owns it. `split(k)` gives the first `len % k` parts one element more.
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

// Zig tip: `indexChain` and `slots` are the code of the brackets `a[i]`; here they find the one cell
// `s[i]` names. The element is copied into a fresh `Var`, which the parameter binds to; `writeBack`
// puts the final value into the cell.
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

// Zig tip: `if (a.cell) |c|` unwraps the optional pointer; the element counts its new value.
/// Put the values of the `@s[i]` arguments back into their elements.
pub fn writeBack(it: *Interp, args: []const Arg) void {
    for (args) |a| if (a.cell) |c| {
        it.setCell(c, a.ref.?.value);
    };
}

// Zig tip: a struct literal with `.field = value` builds the child interpreter; the fields not
// written take their defaults (empty lists, null pointers). The child shares the allocator, the
// global names, the aspects, the modules and the scheduler with its parent; everything else is its own.
/// A new interpreter for a task, writing to `out`.
pub fn newChild(it: *Interp, out: *Io.Writer, name: []const u8) Signal!*Interp {
    const c = try it.a.create(Interp);
    const sc = try Interp.newScratch(it.a);
    c.* = .{
        .a = it.a,
        .t = sc.allocator(),
        .scratch = sc,
        .h = it.h,
        .g = it.g,
        .out = out,
        .global = it.global,
        .scope = it.global,
        .unit = it.unit,
        .io = it.io,
        .sched = it.sched,
        .root = it.base(),
        .aspects = it.aspects,
        .modules = it.modules,
        .task_name = name,
    };
    try c.exts.appendSlice(it.a, it.exts.items);
    return c;
}

// Zig tip: `std.Thread.spawn(config, function, args)` starts an operating-system thread that runs
// `function` with the tuple `args`. The thread first waits for the baton, so starting it does not
// run it: the parent goes on until it waits at `done` (task.zig).
/// Make the task record and its thread.
pub fn launch(it: *Interp, st: *Started) Signal!void {
    st.t.thread = std.Thread.spawn(.{}, taskMain, .{st}) catch return it.fail("cannot start a thread for {s}", .{st.label});
}

// Zig tip: inputs are passed by value (D-048): `clone` copies a collection, so the parent may change
// its variables while the task runs. A channel is not cloned: it is the one object tasks share.
/// Copy the input arguments of a task.
pub fn ownInputs(it: *Interp, args: []Arg) Signal!void {
    for (args) |*a| if (a.ref == null and a.value != .chan) {
        a.value = try it.clone(a.value);
    };
}

// Zig tip: `@intFromPtr` turns a pointer into a number, so variables and list elements, two different
// types, can be kept in one list of addresses and compared. A channel is shared on purpose and is
// skipped. The arguments and their nodes are matched one to one unless a spread changed the count.
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

// Zig tip: `Io.Writer.Allocating` is a writer that keeps what is written in memory taken from the
// allocator; `&buf.writer` is the `*Io.Writer` the child prints to, so its lines wait for `done`.
/// `start name(args);`: start a concurrent aspect in the group whose do region runs (D-140).
pub fn startAspect(it: *Interp, n: *const Node) Signal!void {
    const g = it.group orelse return it.fail("start is allowed only in the do region of a parallel group", .{});
    const s = try it.ensureSched();
    if (n.sel) |prc| return it.startPrivate(n, prc, g, s);
    const known = it.aspects orelse return it.fail("no aspect is loaded: '{s}'", .{n.text});
    const aspect = known.get(n.text) orelse return it.fail("aspect '{s}' is not loaded", .{n.text});
    const args = try it.a.dupe(Arg, try it.evalArgs(n.kids));
    try it.ownOutputs(g, n.kids, args);
    try it.ownInputs(args);
    const buf = try it.a.create(Io.Writer.Allocating);
    buf.* = .init(it.a);
    const st = try it.a.create(Started);
    st.* = .{
        .t = try s.add(),
        .label = aspect.text,
        .aspect = aspect,
        .args = args,
        .child = try it.newChild(&buf.writer, aspect.text),
        .out = buf,
        .siblings = g.list,
        .cancel_policy = g.cancel,
    };
    st.child.me = st.t;
    try g.list.append(it.a, st);
    it.h.pause(); // nothing is freed while the task may run (heap.zig)
    try it.launch(st);
}

// Zig tip: a started private process (D-179) is a task like a started aspect, but it runs in the state of the aspect
// that started it: the record keeps `unit`, the scope of that state, and the task calls `runPrivate` in it. The
// link step proved that it uses only thread-safe names, so tasks may share that scope; only one task runs at a time
// (the baton, task.zig). The type of `s` is the scheduler returned by `ensureSched`.
/// `start name(args);` where `name` is a private process of the concurrent aspect that contains the call.
pub fn startPrivate(it: *Interp, n: *const Node, prc: *const Node, g: Group, s: anytype) Signal!void {
    const args = try it.a.dupe(Arg, try it.evalArgs(n.kids));
    try it.ownOutputs(g, n.kids, args);
    try it.ownInputs(args);
    const buf = try it.a.create(Io.Writer.Allocating);
    buf.* = .init(it.a);
    const st = try it.a.create(Started);
    st.* = .{
        .t = try s.add(),
        .label = prc.text,
        .proc = prc,
        .unit = it.unit,
        .args = args,
        .child = try it.newChild(&buf.writer, prc.text),
        .out = buf,
        .siblings = g.list,
        .cancel_policy = g.cancel,
    };
    st.child.me = st.t;
    try g.list.append(it.a, st);
    it.h.pause(); // nothing is freed while the task may run (heap.zig)
    try it.launch(st);
}

// Zig tip: `spawnTask` relies on the same Zig feature as `startAspect` above: see the tip there. A
// spawned task prints to the same writer as its job: the tasks of a job share one core (D-104).
/// `spawn f(args);`: start an async procedure as a task of the job (D-143).
pub fn spawnTask(it: *Interp, n: *const Node) Signal!void {
    const list = it.job_tasks orelse return it.fail("spawn is allowed only in the do region of a job", .{});
    const s = try it.ensureSched();
    const call_node = n.kids[0];
    const fv = try it.eval(call_node.kids[0]);
    if (fv != .func) return it.fail("spawn starts an async procedure", .{});
    const args = try it.a.dupe(Arg, try it.evalArgs(call_node.kids[1..]));
    try it.ownInputs(args);
    const st = try it.a.create(Started);
    st.* = .{
        .t = try s.add(),
        .label = fv.func.node.text,
        .func = fv.func,
        .args = args,
        .child = try it.newChild(it.out, fv.func.node.text),
        .siblings = list,
    };
    st.child.me = st.t;
    st.child.current_job = it.current_job;
    try list.append(it.a, st);
    it.h.pause();
    try it.launch(st);
}

// Zig tip: this is the body of every task thread. It never returns an error (a thread function
// returns `void`): each way out of the script is turned into a field of `Started`, which the parent
// reads after `done`. `finish` gives the baton away; after it this thread touches nothing shared.
/// The thread of a task: wait for the baton, run, record the outcome, hand the baton on.
pub fn taskMain(st: *Started) void {
    const c = st.child;
    const s = c.sched.?;
    s.waitTurn(st.t);
    if (st.t.cancel != .none) {
        st.cancelled = true; // cancelled before it began: it never runs
    } else {
        const outcome = if (st.proc) |prc| c.runPrivate(prc, st.args, st.unit.?) else if (st.aspect) |asp| c.runAspect(asp, st.args) else blk: {
            _ = c.invokeWith(st.func.?, null, st.args) catch |e| break :blk e;
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
        for (st.siblings.items) |o| if (o != st and !o.t.done and o.t.cancel == .none) {
            o.t.cancel = .cancel;
        };
    }
    s.finish(st.t);
}

// Zig tip: the `do` region may fail after some tasks were started: the error is kept in `outcome`
// and raised only after every task has ended, so no thread is left running. `defer` restores the
// fields of the group on every way out.
/// `[label:] parallel ... do ... done [label];` (D-140).
pub fn parallelGroup(it: *Interp, n: *const Node) Signal!void {
    const s = try it.ensureSched();
    const saved = try it.pushScope();
    defer it.leaveScope(saved);
    const saved_job = it.current_job;
    it.current_job = n.text;
    defer it.current_job = saved_job;
    var deadline: ?i64 = null;
    var limit: i64 = 0;
    if (n.kids[2].tag != .none) {
        const d = try it.eval(n.kids[2]);
        if (!Interp.isInt(d)) return it.fail("within takes a duration: within 30s", .{});
        limit = Interp.intOf(d);
        deadline = s.now() + limit;
    }
    const members = try it.a.create(std.ArrayList(*Started));
    members.* = .empty;
    const owned = try it.a.create(std.ArrayList(usize));
    owned.* = .empty;
    const saved_group = it.group;
    it.group = .{ .list = members, .cancel = n.public, .owned = owned };
    defer it.group = saved_group;
    var outcome: Signal!void = {};
    it.execBlock(n.kids[0]) catch |e| {
        outcome = e;
    };
    if (outcome) |_| {
        it.execBlock(n.kids[1]) catch |e| {
            outcome = e;
        };
    } else |_| {}
    it.group = saved_group;
    try it.joinTasks(members, deadline, limit);
    try it.endTasks(members);
    it.h.resume_(@intCast(members.items.len));
    it.collectAtDone();
    try outcome;
    try it.raiseFailed(members, n.text);
}

// Zig tip: `me.timer` asks the scheduler to wake this task at the deadline even when nothing else
// changes; then the time-out is given to every task still running, and the wait goes on until they
// have reacted. `th.join()` waits for the operating-system thread, which has already ended its work.
/// Wait at `done` for every task of `members`; give a time-out at the deadline.
pub fn joinTasks(it: *Interp, members: *std.ArrayList(*Started), deadline: ?i64, limit: i64) Signal!void {
    const s = it.sched.?;
    const me = it.me.?;
    var timed_out = false;
    while (true) {
        var all = true;
        for (members.items) |m| if (!m.t.done) {
            all = false;
        };
        if (all) break;
        if (deadline) |d| if (!timed_out and s.now() >= d) {
            timed_out = true;
            for (members.items) |m| if (!m.t.done) {
                m.t.cancel = .timeout;
                m.t.limit_ms = limit;
            };
        };
        me.wait = .join;
        me.blocked_at = s.progress;
        me.timer = deadline != null and !timed_out;
        if (me.timer) me.wake_at = deadline.?;
        s.yield(me);
        me.wait = .none;
        me.timer = false;
    }
    for (members.items) |m| if (m.t.thread) |th| {
        th.join();
        m.t.thread = null;
    };
}

// Zig tip: `written()` is what an `Io.Writer.Allocating` has collected. The outputs are written in the
// order of `start`, so the output of a group is the same at every run (D-140).
/// After `done`: write the output of each task in the order of start, its log messages, its outputs.
pub fn endTasks(it: *Interp, members: *std.ArrayList(*Started)) Signal!void {
    for (members.items) |m| {
        if (m.out) |b| try it.out.writeAll(b.written());
        try it.logs.appendSlice(it.a, m.child.logs.items);
        it.writeBack(m.args);
        it.dropArgs(m.args);
        m.child.scratch.deinit();
    }
}

// Zig tip: `since_trace` counts the objects made since the last trace; a job or a group that made
// many of them is a good moment for the backup collector, because the statement that ends holds
// nothing any more (garbage is usually collected at `done`).
/// Run the tracing collector at `done` when enough was made since the last trace.
pub fn collectAtDone(it: *Interp) void {
    if (it.root == null and it.h.since_trace > 1_000) it.h.trace();
}

// Zig tip: the error list is built as Eve objects, so `recover` reads it like any value:
// `$error.errors[1].message`. `failWith` records the report and returns `error.Raise`; the extra
// fields are added to that report before the error is returned (D-140).
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

// Zig tip: `Scope.find` walks the parents too; this looks at one scope only, the one of the process.
/// Is `name` declared in `sc` itself?
pub fn hasLocal(sc: *Scope, name: []const u8) bool {
    for (sc.binds.items) |b| if (interp.value.nameEql(b.name, name)) return true;
    return false;
}

// Zig tip: `findProcess` relies on the same Zig feature as `bind` above: see the tip there.
pub fn findProcess(root: *const Node, name: []const u8) ?*const Node {
    for (root.kids) |k| {
        if (k.tag == .process and std.mem.eql(u8, k.text, name)) return k;
    }
    return null;
}

// Zig tip: `run` relies on the same Zig feature as `callMethod` above: see the tip there.
/// Run a script: a root aspect (declarations, then `process main`) or a free script (the statements).
pub fn run(it: *Interp, root: *const Node) Outcome {
    it.h.root_fn = Interp.roots;
    it.h.root_ctx = it;
    defer if (heap.show_stats) it.h.report();
    defer if (profile.active) profile.report(it.a);
    const result = it.runRoot(root);
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

// Zig tip: an error code is not an exit code (D-081): a failed `expect` ends with 2, a failed
// `assert` with 3, any other unhandled error with 4. `switch` on an integer needs an `else`.
pub fn exitCodeOf(code: u8) u8 {
    return switch (code) {
        2 => 2,
        3 => 3,
        else => 4,
    };
}

// Zig tip: `note` relies on the same Zig feature as `newList` above: see the tip there.
pub fn note(it: *Interp, code: u8, msg: []const u8) void {
    it.reports.append(it.a, .{ .line = it.line, .code = code, .message = msg, .job = "" }) catch {};
}
