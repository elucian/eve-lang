//! @eve-module interp.generators
//! @spec spec/syntax/declarations.md#generators-level-5
//! @feature F-LNG-12
//! @tests test/level5
//! The `update` block of a record, and generators (`yield`).
//! Part of the interpreter (interp.zig): every function takes the interpreter as `it: *Interp`, and
//! `Interp` names each of them again, so a call reads `it.name(...)` wherever it is made.
const std = @import("std");
const interp = @import("../interp.zig");
const Interp = interp.Interp;
const task = interp.task;
const heap = interp.heap;
const Node = interp.Node;
const value = interp.value;
const Signal = interp.Signal;
const Value = interp.Value;
const Object = interp.Object;
const Class = interp.Class;
const Func = interp.Func;
const Arg = interp.Arg;
const GenState = interp.GenState;

// ---- the update block (database.md) ---------------------------------------------------------------

/// `update record do … done;`: change several fields of one record without repeating its name.
pub fn updateStmt(it: *Interp, n: *const Node) Signal!void {
    const rec = try it.eval(n.kids[0]);
    if (rec != .object or rec.object.class == null or rec.object.class.?.node == null) return it.fail("update needs a record, not a {s}", .{Interp.typeName(rec)});
    const saved_obj = it.update_obj;
    const saved_scope = it.update_scope;
    defer {
        it.update_obj = saved_obj;
        it.update_scope = saved_scope;
    }
    const saved = try it.pushScope();
    defer it.leaveScope(saved);
    for (rec.object.class.?.node.?.kids[0].kids) |m| {
        try it.define(m.text, Interp.fieldOf(rec.object, m.text) orelse .nil, false);
    }
    it.update_obj = rec.object;
    it.update_scope = it.scope;
    try it.execBlock(n.kids[1]);
    if (rec.object.class) |c| {
        if (value.classRoutine(c, "validate") != null) _ = try it.callMethod(.{ .object = rec.object }, "validate", &.{});
    }
}

// ---- generators (spec/syntax/declarations.md#generators-level-5) ---------------------------------

/// `count_to(5)`: the generator object. The body begins at the first request for a value.
pub fn makeGenerator(it: *Interp, f: *Func, recv: ?Value, args: []const Arg) Signal!Value {
    const s = try it.ensureSched();
    const b = it.base();
    if (b.gen_class == null) {
        const cls = try it.a.create(Class);
        cls.* = .{ .name = "Generator" };
        b.gen_class = cls;
    }
    const copy = try it.a.dupe(Arg, args);
    try it.ownInputs(copy);
    const obj = try it.newObject();
    obj.class = b.gen_class;
    const gs = try it.a.create(GenState);
    gs.* = .{
        .t = try s.add(),
        .child = try it.newChild(it.out, f.node.text),
        .func = f,
        .recv = recv,
        .args = copy,
        .obj = obj,
        .caller = it.me orelse s.root(),
    };
    gs.child.me = gs.t;
    gs.child.gen = gs;
    gs.child.current_job = it.current_job;
    // the generator task is parked from the start: only a request wakes it
    gs.t.wait = .gen;
    try b.gens.append(it.a, gs);
    try it.setField(obj, "done", .{ .bool = false });
    try it.setField(obj, "handle", .{ .int = @intCast(b.gens.items.len - 1) });
    return .{ .object = obj };
}

/// The thread of a generator.
pub fn genMain(gs: *GenState) void {
    const c = gs.child;
    const s = c.sched.?;
    s.waitTurn(gs.t);
    if (!gs.closing) {
        _ = c.runRoutine(gs.func, gs.recv, gs.args) catch |e| switch (e) {
            error.Cancel => {},
            error.Raise, error.Abort => {
                gs.failed = true;
                if (c.reports.items.len > 0) gs.report = c.reports.items[c.reports.items.len - 1];
            },
            else => {
                gs.failed = true;
                gs.report = .{ .line = c.line, .code = if (e == error.Panic) 1 else 4, .message = @errorName(e), .job = "" };
            },
        };
    }
    gs.finished = true;
    s.finishGen(gs.t, gs.caller);
}

/// `yield;` or `yield expr;` in the body of a generator: give the value to the caller and wait for the next request.
pub fn yieldStmt(it: *Interp, n: *const Node) Signal!void {
    const gs = it.gen orelse return it.fail("yield outside a generator", .{});
    const res = gs.func.node.kids[2].kids[0];
    const cell = it.scope.find(res.text) orelse return it.fail("the result '{s}' of the generator is not declared", .{res.text});
    if (n.kids.len > 0) it.setVar(cell, Interp.coerce(try it.eval(n.kids[0]), res.ty));
    gs.value = cell.value;
    it.sched.?.parkGen(gs.t, gs.caller);
    if (gs.closing) return error.Cancel;
}

/// Ask the generator for the next value: true with `gs.value` set, false when the body has returned.
pub fn genNext(it: *Interp, gs: *GenState) Signal!bool {
    if (gs.finished) return false;
    const s = it.sched.?;
    gs.caller = it.me orelse s.root();
    if (!gs.started) {
        gs.started = true;
        gs.paused = true;
        it.h.pause();
        gs.t.thread = std.Thread.spawn(.{}, genMain, .{gs}) catch return it.fail("cannot start a thread for {s}", .{gs.func.node.text});
    }
    s.resumeGen(gs.caller, gs.t);
    if (gs.finished) {
        try it.genEnded(gs);
        if (gs.failed) return it.failWith(gs.report.code, "{s}", .{gs.report.message});
        return false;
    }
    try it.setField(gs.obj, "value", gs.value);
    return true;
}

pub fn genEnded(it: *Interp, gs: *GenState) Signal!void {
    try it.setField(gs.obj, "done", .{ .bool = true });
    if (gs.paused) {
        gs.paused = false;
        it.h.resume_(1);
    }
}

/// `g.close()`: the body stops at its `yield` (its `defer` statements run) and `g.done` is true.
pub fn genClose(it: *Interp, gs: *GenState) Signal!void {
    if (!gs.finished) {
        gs.closing = true;
        if (gs.started) {
            const s = it.sched.?;
            gs.caller = it.me orelse s.root();
            s.resumeGen(gs.caller, gs.t);
        } else {
            gs.finished = true; // the body never ran: no thread to stop
            gs.t.done = true;
        }
    }
    try it.genEnded(gs);
}

/// The methods of a generator object: `next()` and `close()`; `done` and `value` are attributes.
pub fn generatorCall(it: *Interp, g: *Object, name: []const u8, args: []const *const Node) Signal!Value {
    const gs = it.base().gens.items[@intCast(Interp.intOf(Interp.fieldOf(g, "handle").?))];
    if (args.len != 0) return it.fail("{s}() takes no argument", .{name});
    if (std.mem.eql(u8, name, "next")) return .{ .bool = try it.genNext(gs) };
    if (std.mem.eql(u8, name, "close")) {
        try it.genClose(gs);
        return .nil;
    }
    return it.fail("a Generator has no method '{s}'", .{name});
}

/// `for x in generator do … done`: take the values one by one; leaving the loop closes the generator.
pub fn forGenerator(it: *Interp, n: *const Node, g: *Object) Signal!void {
    const gs = it.base().gens.items[@intCast(Interp.intOf(Interp.fieldOf(g, "handle").?))];
    const saved = try it.pushScope();
    defer it.leaveScope(saved);
    it.regionIn();
    defer it.regionOut();
    defer if (!gs.finished) it.genClose(gs) catch {};
    var ran = false;
    while (try it.genNext(gs)) {
        ran = true;
        const im = it.scratch.mark();
        defer it.scratch.release(im);
        defer it.safe();
        try it.bindPattern(n.kids[0], gs.value);
        it.execBody(n.kids[2]) catch |e| switch (e) {
            error.Break => if (it.caught(n.text)) break else return e,
            error.Skip => if (it.caught(n.text)) continue else return e,
            else => return e,
        };
    }
    if (!ran) try it.execBlock(n.kids[3]);
    try it.execBlock(n.kids[4]);
}

/// At the end of the run: stop the generators that nobody finished, so their threads end.
pub fn closeGenerators(it: *Interp) void {
    for (it.gens.items) |gs| if (gs.started and !gs.finished) it.genClose(gs) catch {};
}
