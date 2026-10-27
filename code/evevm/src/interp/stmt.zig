//! @eve-module interp.stmt
//! @spec spec/syntax/statements.md, spec/semantics/control.md
//! @feature F-LNG-02, F-LNG-04
//! @tests test/level1
//! Statements: `exec`, declarations, assignment, and the control statements.
//! Part of the interpreter (interp.zig): every function takes the interpreter as `it: *Interp`, and
//! `Interp` names each of them again, so a call reads `it.name(...)` wherever it is made.
const std = @import("std");
const interp = @import("../interp.zig");
const db = @import("../db.zig");
const host_mod = @import("../host.zig");
const Interp = interp.Interp;
const data = interp.data;
const overload = interp.overload;
const decimal = interp.decimal;
const dlib = interp.dlib;
const heap = interp.heap;
const Node = interp.Node;
const value = interp.value;
const Signal = interp.Signal;
const Value = interp.Value;
const Channel = interp.Channel;
const Class = interp.Class;
const err_raise = interp.err_raise;
const err_expect = interp.err_expect;
const err_assert = interp.err_assert;
const err_index = interp.err_index;
const Started = interp.Started;
const Heap = interp.Heap;
const Var = interp.Var;

// ---- statements -----------------------------------------------------------------------

/// `commit;` in a job.
pub fn commitStmt(it: *Interp) Signal!void {
    host_mod.enterDb(it.io);
    defer host_mod.leaveDb(it.io);
    try db.orm.commitJob(it.host());
}

pub fn execBlock(it: *Interp, b: *const Node) Signal!void {
    it.regionIn();
    defer it.regionOut();
    try it.execBody(b);
}

/// The statements of a loop body, each followed by a safe point.
pub fn execBody(it: *Interp, b: *const Node) Signal!void {
    for (b.kids) |s| {
        try it.exec(s);
        it.safe();
    }
}

pub fn tick(it: *Interp, n: *const Node) Signal!void {
    if (it.dbg) |d| {
        if (it.root == null) try d.before(d.ctx, it, n);
    }
    if (it.hook) |h| {
        if (h.poll(h.ctx, it.steps, it.line)) return error.Stop;
    }
    if (it.root != null) try it.checkCancel();
    it.steps += 1;
    if (n.line > 0) it.line = n.line;
}

pub fn exec(it: *Interp, n: *const Node) Signal!void {
    // what the statement puts in the scratch memory is freed when it ends, however it ends
    const m = it.scratch.mark();
    defer it.scratch.release(m);
    try it.tick(n);
    switch (n.tag) {
        .var_decl, .set => try it.declare(n),
        .block => try it.execBlock(n),
        .capture => try it.capture(n),
        .assign => try it.assign(n),
        .expr_stmt => try it.exprStmt(n.kids[0]),
        .print_stmt, .write_stmt => try it.print(n),
        .expect_stmt => {
            if (!try it.truth(try it.eval(n.kids[0]))) {
                if (n.kids.len > 1) return it.failWith(err_expect, "{s}", .{try it.text(try it.eval(n.kids[1]))});
                return it.failWith(err_expect, "expect failed", .{});
            }
        },
        .raise_stmt => return it.raise(n),
        .break_stmt => {
            it.jump_label = n.text;
            return error.Break;
        },
        .skip_stmt => {
            it.jump_label = n.text;
            return error.Skip;
        },
        .over_stmt => {
            try it.exitCodeOfStmt(n);
            return error.Over;
        },
        .exit_stmt => {
            try it.exitCodeOfStmt(n);
            return error.Exit;
        },
        .stop_stmt => return error.StopJob,
        .yield_stmt => try it.yieldStmt(n),
        .commit_stmt => try it.commitStmt(),
        .rollback_stmt => return error.JobRollback,
        .update_stmt => try it.updateStmt(n),
        .pass_stmt => {},
        .assert_stmt => {
            if (!try it.truth(try it.eval(n.kids[0]))) {
                if (n.kids.len > 1) return it.failWith(err_assert, "{s}", .{try it.text(try it.eval(n.kids[1]))});
                return it.failWith(err_assert, "assertion failed", .{});
            }
        },
        .defer_stmt => try it.defers.append(it.a, n.kids[0]),
        .panic_stmt => return error.Panic,
        .retry_stmt => return error.Retry,
        .resume_stmt => return error.Resume,
        .abort_stmt => return error.Abort,
        .cond_stmt => if (try it.truth(try it.eval(n.kids[0]))) try it.exec(n.kids[1]),
        .if_ => try it.ifStmt(n),
        .while_ => try it.whileStmt(n),
        .for_ => try it.forStmt(n),
        .repeat_ => try it.repeatStmt(n),
        .match_ => try it.matchStmt(n),
        .job => {
            const st = try it.jobBegin(n.text);
            return it.jobFinish(st, it.execBlock(n.kids[0]), null);
        },
        .class, .trait, .adopt, .function, .procedure, .method, .generator => try it.declareRoutine(n),
        .apply_stmt => try it.applyAspect(n),
        .parallel => try it.parallelGroup(n),
        .start_stmt => try it.startAspect(n),
        .spawn_stmt => try it.spawnTask(n),
        .wait_stmt => {
            const v = try it.eval(n.kids[0]);
            const ms = Interp.msOf(v) orelse return it.fail("wait takes a duration: wait 10ms;", .{});
            try it.waitFor(ms);
        },
        .process => {},
        else => return it.fail("cannot execute a {s}", .{@tagName(n.tag)}),
    }
}

/// Record the state of the job `label` in `jobs["label"].status`.
pub fn setJob(it: *Interp, label: []const u8, status: []const u8) void {
    const cell = it.scope.find("jobs") orelse return;
    if (cell.value != .map) return;
    const i = Interp.mapFind(cell.value.map, .{ .str = label }) orelse return;
    const rec = cell.value.map.entries.items[i].val;
    if (rec == .object) it.setField(rec.object, "status", it.staticStr(status) catch return) catch {};
}

pub fn exprStmt(it: *Interp, e: *const Node) Signal!void {
    if (e.tag == .bin and (std.mem.eql(u8, e.text, "<+") or std.mem.eql(u8, e.text, "<-") or std.mem.eql(u8, e.text, "->"))) {
        return it.listOp(e);
    }
    it.stmt_call = e.tag == .call;
    const v = try it.eval(e);
    it.stmt_call = false;
    // a bare name that is a function or method is a call without arguments: `hello;`
    if (e.tag == .name and v == .func) _ = try it.callValue(v, null, &.{});
}

/// `a <+ x;` appends in place, `x <- a;` removes the first `x`, `a -> x;` removes the last.
pub fn listOp(it: *Interp, e: *const Node) Signal!void {
    const op = e.text;
    const list_node = if (std.mem.eql(u8, op, "<-")) e.kids[1] else e.kids[0];
    const item_node = if (std.mem.eql(u8, op, "<-")) e.kids[0] else e.kids[1];
    const lv = try it.eval(list_node);
    const l = switch (lv) {
        .list, .set => |x| x,
        else => return it.fail("{s} needs a list, found {s}", .{ op, Interp.typeName(lv) }),
    };
    const item = try it.eval(item_node);
    if (std.mem.eql(u8, op, "<+")) {
        if (lv == .set) return it.setAdd(l, item);
        if (item == .list) try it.listAppendSlice(l, item.list.elems()) else try it.listAppend(l, item);
        return;
    }
    const items = l.items.items;
    var found: ?usize = null;
    if (std.mem.eql(u8, op, "<-")) {
        for (items, 0..) |x, i| if (Interp.eq(x, item)) {
            found = i;
            break;
        };
    } else {
        var i = items.len;
        while (i > 0) {
            i -= 1;
            if (Interp.eq(items[i], item)) {
                found = i;
                break;
            }
        }
    }
    if (found) |i| _ = it.listRemove(l, i);
}

pub fn print(it: *Interp, n: *const Node) Signal!void {
    const is_print = n.tag == .print_stmt;
    var buf: std.ArrayList(u8) = .empty;
    var sep: []const u8 = if (is_print) "," else "";
    if (n.kids.len > 0) {
        const e = n.kids[0];
        if (e.tag == .list) {
            var first = true;
            for (e.kids) |k| {
                if (k.tag == .pair and k.kids[0].tag == .name and std.mem.eql(u8, k.kids[0].text, "sep")) {
                    sep = try it.text(try it.eval(k.kids[1]));
                }
            }
            for (e.kids) |k| {
                if (k.tag == .pair) continue;
                if (!first) try buf.appendSlice(it.t, sep);
                first = false;
                try it.show(&buf, try it.eval(k), false);
            }
        } else try it.show(&buf, try it.eval(e), false);
    }
    if (is_print) try buf.append(it.t, '\n');
    try it.out.writeAll(buf.items);
}

pub fn raise(it: *Interp, n: *const Node) Signal {
    if (n.kids.len == 0) return it.fail("raise", .{});
    const v = it.eval(n.kids[0]) catch |e| return e;
    return it.raiseValue(v);
}

// @eve-impl `raise v`: the error of a value (a text, a list of a code and a text, an object with code and message)
// @spec spec/semantics/errors.md#errors
pub fn raiseValue(it: *Interp, v: Value) Signal {
    switch (v) {
        .str => |s| return it.fail("{s}", .{s}),
        .list => |l| {
            const items = l.elems();
            if (items.len == 2 and Interp.isInt(items[0])) {
                return it.failWith(@intCast(@max(1, @min(65535, Interp.intOf(items[0])))), "{s}", .{it.text(items[1]) catch ""});
            }
        },
        .object => |o| {
            const code: u16 = if (Interp.fieldOf(o, "code")) |c| @intCast(@max(1, @min(65535, Interp.intOf(c)))) else err_raise;
            const msg = if (Interp.fieldOf(o, "message")) |m| (it.text(m) catch "") else "";
            it.pending_fields = o;
            return it.failWith(code, "{s}", .{msg});
        },
        else => {},
    }
    return it.fail("{s}", .{it.text(v) catch ""});
}

// ---- declarations and assignment ------------------------------------------------------

// @eve-impl `adopt Trait for Type`: the methods of the block become extension methods of the type, the provided methods
// of the trait that the block does not write too, and `x is Trait` is true for the type (CLS-15, D-202)
// @spec spec/syntax/declarations.md#traits-and-generic-classes
// @test d42_adopt_trait
fn adoptTrait(it: *Interp, n: *const Node) Signal!void {
    const tv = it.scope.find(n.text) orelse return it.fail("undefined trait '{s}': write the trait before the adopt block", .{n.text});
    if (tv.value != .class or !tv.value.class.trait) return it.fail("'{s}' is not a trait", .{n.text});
    const tr = tv.value.class;
    const ty = n.kids[0];
    for (n.kids[1..]) |m| try it.exts.append(it.a, m);
    if (tr.node) |tn| for (tn.kids[2..]) |pm| {
        if (pm.tag != .method or pm.kids[3].tag == .none) continue;
        var written = false;
        for (n.kids[1..]) |m| if (std.mem.eql(u8, m.text, pm.text)) {
            written = true;
        };
        if (written) continue;
        const params = try it.a.create(Node);
        params.* = pm.kids[0].*;
        const first = try it.a.dupe(*const Node, pm.kids[0].kids);
        if (first.len > 0) {
            const p0 = try it.a.create(Node);
            p0.* = first[0].*;
            p0.ty = ty;
            first[0] = p0;
        }
        params.kids = first;
        const copy = try it.a.create(Node);
        copy.* = pm.*;
        const mk = try it.a.dupe(*const Node, pm.kids);
        mk[0] = params;
        copy.kids = mk;
        try it.exts.append(it.a, copy);
    };
    try it.adopted.append(it.a, .{ .ty = ty.text, .trait = tr });
}

pub fn declareRoutine(it: *Interp, n: *const Node) Signal!void {
    if (n.tag == .adopt) return adoptTrait(it, n);
    if (n.tag == .trait) {
        const c = try it.a.create(Class);
        c.* = .{ .name = n.text, .node = n, .trait = true };
        try it.define(n.text, .{ .class = c }, true);
        return;
    }
    if (n.tag == .class) {
        const c = try it.a.create(Class);
        c.* = .{ .name = n.text, .node = n };
        for (n.extra) |tr| {
            const tv = it.scope.find(tr.text) orelse return it.fail("undefined trait '{s}'", .{tr.text});
            if (tv.value != .class or !tv.value.class.trait) return it.fail("'{s}' is not a trait", .{tr.text});
            try c.traits.append(it.a, tv.value.class);
        }
        const parent = n.kids[1];
        if (parent.tag == .name) {
            if (it.scope.find(parent.text)) |pv| if (pv.value == .class) {
                c.parent = pv.value.class;
            };
        }
        c.has_destructor = c.destructor() != null or (if (c.parent) |pc| pc.has_destructor else false);
        if (parent.tag == .name and std.mem.eql(u8, parent.text, "Ordinal")) {
            c.ordinal = true;
            var next: i64 = 1;
            for (n.kids[0].kids) |m| {
                if (m.kids[0].tag != .none) next = Interp.intOf(try it.eval(m.kids[0]));
                try c.ord.append(it.a, .{ .name = m.text, .val = .{ .int = next } });
                // names that start with a capital letter need no qualifier
                if (std.ascii.isUpper(m.text[0])) try it.define(m.text, .{ .int = next }, true);
                next += 1;
            }
        }
        // the `set` constants of the body are evaluated once, here, and read as `Class.NAME` (D-202)
        if (n.kids.len > 2) for (n.kids[2..]) |m| if (m.tag == .set) {
            const val = if (m.kids[1].tag != .none) try it.eval(m.kids[1]) else Value.nil;
            for (m.kids[0].kids) |t| if (t.tag == .name) try c.ord.append(it.a, .{ .name = t.text, .val = val });
        };
        try it.define(n.text, .{ .class = c }, true);
        return;
    }
    if (n.tag == .method) {
        try it.exts.append(it.a, n);
        return;
    }
    // a function or procedure with the name of one declared before in this scope is an overload (D-149)
    if (n.tag == .function or n.tag == .procedure) {
        for (it.scope.binds.items) |b| {
            if (!std.mem.eql(u8, b.name, n.text) or b.v.value != .func) continue;
            const first = b.v.value.func.node;
            if (first.is_sql or n.is_sql) return it.fail("the sql function {s} can not be overloaded: SQL finds a function by its name (D-166)", .{n.text});
            Interp.lockShared();
            defer Interp.unlockShared();
            const set = try it.base().overloads.getOrPut(it.a, first);
            if (!set.found_existing) {
                set.value_ptr.* = .empty;
                try set.value_ptr.append(it.a, first);
            }
            try set.value_ptr.append(it.a, n);
            return;
        }
    }
    // a function declared inside another one closes over that call's scope (a closure, D-101)
    const f = try it.newFunc(n, if (it.scope == it.unit) it.unit else it.scope);
    try it.define(n.text, .{ .func = f }, true);
    if (n.is_sql) {
        host_mod.enterDb(it.io);
        defer host_mod.leaveDb(it.io);
        try db.conn.registerSqlFunction(it.host(), f);
    }
}

pub fn coerce(v: Value, ty: ?*const Node) Value {
    const t = ty orelse return v;
    // @perf hot
    if (t.tk != .none) {
        if (t.kids.len != 0) return v;
        switch (t.tk) {
            .real => {
                if (Interp.isInt(v)) return .{ .real = @floatFromInt(Interp.intOf(v)) };
                return Interp.coerceLike(.{ .real = 0 }, v);
            },
            .decimal => {
                if (Interp.isInt(v)) if (decimal.fromInt(Interp.intOf(v))) |d| return .{ .dec = d };
                return Interp.coerceLike(.{ .dec = .{ .m = 0, .scale = 0 } }, v);
            },
            .complex => {
                if (Interp.cpxOf(v)) |z| return .{ .cpx = z };
                return v;
            },
            .rational => {
                if (Interp.isInt(v)) return .{ .rat = interp.rational.fromInt(Interp.intOf(v)) };
                return v;
            },
            .integer => {
                if (v == .real or v == .float) return .{ .int = @intFromFloat(Interp.realOf(v).?) };
                return v;
            },
            else => return v,
        }
    }
    if (t.kids.len == 0 and std.mem.eql(u8, t.text, "Real") and Interp.isInt(v)) return .{ .real = @floatFromInt(Interp.intOf(v)) };
    if (t.kids.len == 0 and std.mem.eql(u8, t.text, "Rational") and Interp.isInt(v)) return .{ .rat = interp.rational.fromInt(Interp.intOf(v)) };
    if (t.kids.len == 0 and std.mem.eql(u8, t.text, "Decimal") and Interp.isInt(v)) {
        if (decimal.fromInt(Interp.intOf(v))) |d| return .{ .dec = d };
    }
    // a Real given to an Integer loses its decimals (D-080)
    if (t.kids.len == 0 and std.mem.eql(u8, t.text, "Integer") and (v == .real or v == .float)) return .{ .int = @intFromFloat(Interp.realOf(v).?) };
    // a Decimal given to a Real, a Real given to a Decimal: `:=` converts (data-language.md, D-168)
    if (t.kids.len == 0 and std.mem.eql(u8, t.text, "Real")) return Interp.coerceLike(.{ .real = 0 }, v);
    if (t.kids.len == 0 and std.mem.eql(u8, t.text, "Decimal")) return Interp.coerceLike(.{ .dec = .{ .m = 0, .scale = 0 } }, v);
    return v;
}

/// Run the `defer` statements registered since `mark`, newest first, and forget them.
pub fn runDefers(it: *Interp, mark: usize) void {
    while (it.defers.items.len > mark) {
        const stmt = it.defers.pop().?;
        it.exec(stmt) catch {};
    }
}

// @decision D-104
/// `let lst -> e;` takes the last element, `let e <- lst;` and `new e <- lst;` the first (D-104).
// @eve-impl `l -> x` and `x <- l`: take the last (`last`) or the first element out of a list
// @spec spec/syntax/statements.md#statements-that-bind-a-value
pub fn capturePick(it: *Interp, lv: Value, last: bool) Signal!Value {
    const l = switch (lv) {
        .list => |x| x,
        else => return it.fail("{s} needs a list, found {s}", .{ if (last) "->" else "<-", Interp.typeName(lv) }),
    };
    if (l.items.items.len == 0) return it.failWith(err_index, "Index 1 is out of range: the list is empty", .{});
    return if (last) it.listPop(l) else it.listRemove(l, 0);
}

pub fn capture(it: *Interp, n: *const Node) Signal!void {
    const item = try it.capturePick(try it.eval(n.kids[0]), n.text[0] == '-');
    const target = n.kids[1];
    if (target.tag == .name and std.mem.eql(u8, target.text, "_")) return;
    if (target.tag == .name) {
        const exists = it.scope.find(target.text) != null;
        if (n.kids[2].tag == .none or !exists) return it.define(target.text, item, false);
    }
    try it.assignTo(target, item);
}

// @eve-impl a loop has one scope for all its cycles: the same `new` run a second time in that scope is a run-time error
// @spec spec/semantics/scopes.md#redeclaration
// @test a104_scope_loop_redeclare
pub fn declare(it: *Interp, n: *const Node) Signal!void {
    const targets = n.kids[0].kids;
    for (targets) |t| {
        if ((t.tag != .name and t.tag != .star) or t.text.len == 0 or std.mem.eql(u8, t.text, "_")) continue;
        for (it.scope.binds.items) |b| {
            if (value.nameEql(b.name, t.text) and b.v.decl == @as(?*const anyopaque, n))
                return it.fail("'{s}' is already declared in this scope: a loop has one scope for all its cycles, declare the name before the loop", .{t.text});
        }
    }
    try declareStatement(it, n);
    for (targets) |t| {
        if ((t.tag != .name and t.tag != .star) or t.text.len == 0 or std.mem.eql(u8, t.text, "_")) continue;
        for (it.scope.binds.items) |b| if (value.nameEql(b.name, t.text)) {
            b.v.decl = n;
            // @eve-impl a variable typed `Atomic(:T)` holds a scalar and is shared by the tasks (Q1 of design-task-heap.md)
            if (n.ty) |ty| if (ty.public and n.tag != .set) {
                if (Heap.hdrOf(b.v.value) != null) return it.fail("an Atomic variable holds a Logic, a number, a symbol or an ordinal, not a {s}", .{Interp.typeName(b.v.value)});
                b.v.atomic = true;
            };
        };
    }
}

fn declareStatement(it: *Interp, n: *const Node) Signal!void {
    const targets = n.kids[0].kids;
    const constant = n.tag == .set;
    const vnode = n.kids[1];
    if (vnode.tag == .none) {
        for (targets) |t| {
            if (t.tag == .name) try it.define(t.text, try it.zero(n.ty), constant);
        }
        return;
    }
    var v = try it.eval(vnode);
    if (std.mem.eql(u8, n.text, "::")) v = try it.clone(v);
    v = Interp.coerce(v, n.ty);
    it.typeLiteral(v, n.ty);
    const multi_names = std.mem.eql(u8, n.text, "=");
    if (targets.len == 1 and targets[0].tag != .star) return it.declareOne(targets[0], v, constant);
    if (multi_names) {
        const elementwise = v == .list and v.list.elems().len == targets.len;
        for (targets, 0..) |t, i| try it.declareOne(t, if (elementwise) v.list.elems()[i] else v, constant);
        return;
    }
    // deconstruct: `_` skips one element, `*` skips many, `*rest` collects them
    const items = try it.iterate(v);
    var star: ?usize = null;
    for (targets, 0..) |t, i| if (t.tag == .star) {
        star = i;
    };
    const after = if (star) |s| targets.len - s - 1 else 0;
    if (items.len < targets.len - @intFromBool(star != null)) return it.fail("not enough elements to deconstruct", .{});
    for (targets, 0..) |t, i| {
        if (t.tag == .star) {
            if (t.text.len > 0) {
                const rest = try it.newList(items[i .. items.len - after], false);
                try it.define(t.text, .{ .list = rest }, constant);
            }
        } else if (star != null and i > star.?) {
            try it.declareOne(t, items[items.len - (targets.len - i)], constant);
        } else try it.declareOne(t, items[i], constant);
    }
}

/// Make an object literal an object of the class that the type hint of a declaration names.
pub fn typeLiteral(it: *Interp, v: Value, ty: ?*const Node) void {
    const t = ty orelse return;
    if (v != .object or v.object.class != null or t.kids.len > 0) return;
    const name = std.mem.trimEnd(u8, t.text, "?");
    const cell = it.scope.find(name) orelse return;
    if (cell.value == .class and cell.value.class.node != null) v.object.class = cell.value.class;
}

pub fn declareOne(it: *Interp, t: *const Node, v: Value, constant: bool) Signal!void {
    switch (t.tag) {
        .name => {
            if (std.mem.eql(u8, t.text, "_")) return;
            if (v == .chan and v.chan.name.len == 0) v.chan.name = t.text; // `new jobs := Channel(...)`
            try it.define(t.text, v, constant);
        },
        .field => try it.assignTo(t, v),
        else => return it.fail("cannot declare a {s}", .{@tagName(t.tag)}),
    }
}


// @eve-impl `cur op= v` on values: a list or a set changes in place (null), anything else gives the new value
// @spec spec/semantics/types.md#composite-types
// @see code/evevm/src/bcvm.zig:execute
/// The part of `assign` that works on two values; the bytecode machine calls it for the compound assignments that are not plain numbers.
pub fn augmentValue(it: *Interp, o: interp.ast.Op, op: []const u8, cur: Value, v: Value) Signal!?Value {
        // a list and a scalar: every element is updated in place (D-118)
        if (cur == .list and Interp.isScalar(v)) {
            const src = cur.list.elems();
            const out = try it.t.alloc(Value, src.len);
            for (src, 0..) |e, i| out[i] = try it.bulkOne(op, e, v);
            for (src, out) |*cell, x| it.setCell(cell, x);
            return null;
        }
        // += and -= on a collection change it in place
        if ((cur == .list or cur == .set) and (op[0] == '+' or op[0] == '-')) {
            const l = if (cur == .list) cur.list else cur.set;
            if (op[0] == '+') {
                if (cur == .set) {
                    for ((try it.setOf(v)).items.items) |e| try it.setAdd(l, e);
                } else if (v == .list) {
                    try it.listAppendSlice(l, v.list.elems());
                } else try it.listAppend(l, v);
            } else {
                const gone: []const Value = if (v == .set or (cur == .set and v == .list)) (try it.setOf(v)).items.items else &.{v};
                var k: usize = 0;
                while (k < l.items.items.len) {
                    var drop = false;
                    for (gone) |g| if (Interp.eq(l.items.items[k], g)) {
                        drop = true;
                    };
                    if (drop) _ = it.listRemove(l, k) else k += 1;
                }
            }
            return null;
        }
    return try it.applyOp(o, op, cur, v);
}

pub fn assign(it: *Interp, n: *const Node) Signal!void {
    const target = n.kids[0];
    const op = n.text;
    if (n.op == .push_back or n.op == .push_front) return it.listModifier(n);
    if (target.tag == .name and n.op != .set and n.op != .copy) {
        if (it.scope.find(target.text)) |cell| if (cell.atomic) return it.assignAtomic(n, cell);
    }
    var v = try it.eval(n.kids[1]);
    if (n.op == .copy) {
        v = try it.clone(v);
    } else if (n.op != .set) {
        const cur = try it.eval(target);
        v = (try it.augmentValue(n.op, op[0..1], cur, v)) orelse return;
    }
    // `let r := d;` converts a Decimal for a variable that holds a Real, and the other way (D-168)
    if (n.op == .set and target.tag == .name) {
        if (it.scope.find(target.text)) |cell| v = Interp.coerceLike(cell.value, v);
    }
    try it.assignTo(target, v);
}

// @eve-impl `let a += x;` on an `Atomic(:T)` variable reads, computes and stores in one step: the tasks on other cores see all the additions
// @spec spec/semantics/multitasking.md#data-rules
// @test d50_atomic_heavy
/// A compound assignment to the atomic variable `cell`.
pub fn assignAtomic(it: *Interp, n: *const Node, cell: *Var) Signal!void {
    const v = try it.eval(n.kids[1]);
    if (cell.constant) return it.fail("'{s}' is a constant", .{n.kids[0].text});
    value.atomic_lock.lock();
    defer value.atomic_lock.unlock();
    const nv = (try it.augmentValue(n.op, n.text[0..1], cell.value, v)) orelse return;
    cell.value = nv;
}

// @decision D-107
/// `let lst <+ x;` appends, `let x +> lst;` puts in front. A list given as `x` adds its elements.
pub fn listModifier(it: *Interp, n: *const Node) Signal!void {
    const front = n.text[0] == '+';
    const list_node = if (front) n.kids[1] else n.kids[0];
    const item = try it.eval(if (front) n.kids[0] else n.kids[1]);
    const lv = try it.eval(list_node);
    if (db.orm.isTable(it.host(), lv)) {
        host_mod.enterDb(it.io);
        defer host_mod.leaveDb(it.io);
        return db.orm.tableAdd(it.host(), lv.object, item);
    }
    if (lv == .str) {
        const add = try it.text(item);
        const joined = if (front) try it.persist2(add, lv.str) else try it.persist2(lv.str, add);
        return it.assignTo(list_node, .{ .str = joined });
    }
    const l = switch (lv) {
        .list, .set => |x| x,
        else => return it.fail("{s} needs a list, found {s}", .{ n.text, Interp.typeName(lv) }),
    };
    if (lv == .set) return it.setAdd(l, item);
    if (front) {
        if (item == .list) try it.listInsertSlice(l, 0, item.list.elems()) else try it.listInsert(l, 0, item);
    } else if (item == .list) {
        try it.listAppendSlice(l, item.list.elems());
    } else try it.listAppend(l, item);
}

/// `v` converted to the number kind that `cur` holds, Decimal or Real; any other value is kept (D-168). A Real
/// becomes the Decimal of its shortest text (`0.1` is `0.1d`); a Real too large for a Decimal is kept, and the
/// operator that uses it will say so.
pub fn coerceLike(cur: Value, v: Value) Value {
    if (cur == .real and v == .dec) return .{ .real = decimal.toF64(v.dec) };
    if (cur == .real and v == .rat) return .{ .real = interp.rational.toF64(v.rat) };
    if (cur == .cpx and v != .cpx) if (Interp.cpxOf(v)) |z| return .{ .cpx = z };
    if (cur == .rat and Interp.isInt(v)) return .{ .rat = interp.rational.fromInt(Interp.intOf(v)) };
    if (cur == .dec and (v == .real or v == .float)) {
        if (decimal.fromF64(Interp.realOf(v).?)) |d| return .{ .dec = d };
    }
    return v;
}

// @eve-impl `obj.name := v` on an evaluated object; a record watched by the database layer is told before and after
// @spec spec/syntax/statements.md#statements-that-bind-a-value
pub fn assignField(it: *Interp, obj: Value, name: []const u8, v: Value) Signal!void {
    if (obj != .object) return it.fail("{s} has no attributes", .{Interp.typeName(obj)});
    const watched = db.orm.active(it.host());
    if (watched) try db.orm.beforeChange(it.host(), obj.object, name, v);
    try it.setField(obj.object, name, v);
    if (watched) try db.orm.afterChange(it.host(), obj.object);
}

pub fn assignTo(it: *Interp, target: *const Node, v: Value) Signal!void {
    switch (target.tag) {
        .name => {
            if (std.mem.eql(u8, target.text, "_")) return; // `_` drops the value
            const cell = it.scope.find(target.text) orelse return it.fail("undefined name '{s}'", .{target.text});
            if (cell.constant) return it.fail("'{s}' is a constant", .{target.text});
            if (it.update_obj) |rec| if (it.update_scope) |us| if (Interp.hasLocal(us, target.text)) {
                // a field name inside `update record do … done;` is the field of that record
                try db.orm.beforeChange(it.host(), rec, target.text, v);
                try it.setField(rec, target.text, v);
                try db.orm.afterChange(it.host(), rec);
            };
            if (cell.atomic) {
                value.atomic_lock.lock();
                defer value.atomic_lock.unlock();
                cell.value = v;
                return;
            }
            it.setVar(cell, v);
        },
        .field => {
            const obj = try it.eval(target.kids[0]);
            try it.assignField(obj, target.text, v);
        },
        .index => {
            const r = try it.indexChain(target);
            const obj = r.obj;
            const args = r.args;
            if (obj == .map) return it.mapPut(obj.map, try it.eval(args[0]), v);
            if (obj != .list) return it.fail("{s} cannot be assigned by index", .{Interp.typeName(obj)});
            if (args.len == 1 and args[0].tag != .all and args[0].tag != .range and !Interp.isMatrix(obj.list)) {
                // one index on a list: write the element directly
                const l = obj.list;
                const ix = try it.evalIdx(args[0], @intCast(l.elems().len));
                const k = ix.one;
                if (k < 1 or k > l.elems().len) return it.failWith(err_index, "Index {d} is out of range 1..{d}", .{ k, l.elems().len });
                it.setCell(&l.elems()[@intCast(k - 1)], v);
                return;
            }
            var cells: std.ArrayList(*Value) = .empty;
            try it.slots(obj.list, args, &cells);
            for (cells.items) |c| it.setCell(c, v);
        },
        else => return it.fail("cannot assign to a {s}", .{@tagName(target.tag)}),
    }
}

// ---- control statements ---------------------------------------------------------------

pub fn ifStmt(it: *Interp, n: *const Node) Signal!void {
    var i: usize = 0;
    while (i + 1 < n.kids.len) : (i += 2) {
        if (try it.truth(try it.eval(n.kids[i]))) return it.execBlock(n.kids[i + 1]);
    }
    if (n.kids.len % 2 == 1) try it.execBlock(n.kids[n.kids.len - 1]);
}

// @decision D-034
pub fn caught(it: *Interp, label: []const u8) bool {
    if (it.jump_label.len == 0) return true;
    if (std.mem.eql(u8, it.jump_label, label)) {
        it.jump_label = "";
        return true;
    }
    return false;
}

pub fn whileStmt(it: *Interp, n: *const Node) Signal!void {
    const saved = try it.pushScope();
    defer it.leaveScope(saved);
    try it.execBlock(n.kids[0]);
    var ran = false;
    it.regionIn();
    defer it.regionOut();
    while (true) {
        defer it.safe();
        // the condition and the body of one pass free their scratch memory before the next pass
        const im = it.scratch.mark();
        defer it.scratch.release(im);
        if (!try it.truth(try it.eval(n.kids[1]))) break;
        ran = true;
        it.execBody(n.kids[2]) catch |e| switch (e) {
            error.Break => if (it.caught(n.text)) break else return e,
            error.Skip => if (it.caught(n.text)) continue else return e,
            else => return e,
        };
    }
    if (!ran) try it.execBlock(n.kids[3]);
    try it.execBlock(n.kids[4]);
}

pub fn forStmt(it: *Interp, n: *const Node) Signal!void {
    const saved = try it.pushScope();
    defer it.leaveScope(saved);
    const source = try it.eval(n.kids[1]);
    if (source == .object and source.object.class != null and source.object.class == it.base().gen_class) {
        return it.forGenerator(n, source.object);
    }
    if (dlib.isStream(it, source)) return dlib.forStream(it, n, source.object);
    // the elements are listed before the loop's region starts: the pairs of a map are made here and
    // must live through every pass
    const counted = source == .range and n.kids[0].tag == .name;
    const items: []const Value = if (source == .chan or counted) &.{} else try it.iterate(source);
    // the loop is a region: at the end of each pass, what the pass dropped is freed
    it.regionIn();
    defer it.regionOut();
    if (source == .chan) {
        // receive until the channel is closed and empty (D-141)
        while (try it.receive(source.chan)) |x| {
            const im = it.scratch.mark();
            defer it.scratch.release(im);
            defer it.safe();
            try it.bindPattern(n.kids[0], x);
            it.execBody(n.kids[2]) catch |e| switch (e) {
                error.Break => if (it.caught(n.text)) break else return e,
                error.Skip => if (it.caught(n.text)) continue else return e,
                else => return e,
            };
        }
        try it.execBlock(n.kids[4]);
        return;
    }
    var ran = false;
    if (counted) {
        // a range is counted, not turned into a list first: `for i in (1..1000000)` needs no memory
        const r = source.range;
        var k = r.lo;
        while (k <= r.hi) : (k += r.step) {
            ran = true;
            const im = it.scratch.mark();
            defer it.scratch.release(im);
            defer it.safe();
            try it.define(n.kids[0].text, if (r.sym) .{ .sym = @intCast(k) } else .{ .int = k }, false);
            it.execBody(n.kids[2]) catch |e| switch (e) {
                error.Break => if (it.caught(n.text)) break else return e,
                error.Skip => if (it.caught(n.text)) continue else return e,
                else => return e,
            };
        }
    } else {
        for (items) |x| {
            ran = true;
            const im = it.scratch.mark();
            defer it.scratch.release(im);
            defer it.safe();
            try it.bindPattern(n.kids[0], x);
            it.execBody(n.kids[2]) catch |e| switch (e) {
                error.Break => if (it.caught(n.text)) break else return e,
                error.Skip => if (it.caught(n.text)) continue else return e,
                else => return e,
            };
        }
    }
    if (!ran) try it.execBlock(n.kids[3]);
    try it.execBlock(n.kids[4]);
}

/// `loop [header] do body repeat [while c];` (D-074): the body runs at least once.
pub fn repeatStmt(it: *Interp, n: *const Node) Signal!void {
    const saved = try it.pushScope();
    defer it.leaveScope(saved);
    try it.execBlock(n.kids[0]);
    it.regionIn();
    defer it.regionOut();
    while (true) {
        const im = it.scratch.mark();
        defer it.scratch.release(im);
        defer it.safe();
        it.execBody(n.kids[1]) catch |e| switch (e) {
            error.Break => if (it.caught(n.text)) break else return e,
            error.Skip => if (!it.caught(n.text)) return e,
            else => return e,
        };
        if (n.kids.len > 2 and !try it.truth(try it.eval(n.kids[2]))) break;
    }
}

pub fn matchStmt(it: *Interp, n: *const Node) Signal!void {
    const subject = try it.eval(n.kids[0]);
    const all = std.mem.startsWith(u8, n.text, "all");
    for (n.kids[2..]) |w| {
        var hit = false;
        for (w.kids[0].kids) |pat| {
            if (pat.tag == .name and std.mem.eql(u8, pat.text, "other") and it.scope.find("other") == null) {
                hit = true;
                continue;
            }
            if (pat.tag == .list) { // `when ("two", "three")`: any of the values
                for (pat.kids) |k| if (Interp.eq(try it.eval(k), subject)) {
                    hit = true;
                };
                continue;
            }
            const pv = try it.eval(pat);
            if (switch (pv) {
                .range, .domain => try it.contains(pv, subject),
                // a class as pattern tests the class of an object, as `is` does (`match $error when FormatError do`)
                .class => if (subject == .object) it.isOp(subject, pv) else Interp.eq(pv, subject),
                else => Interp.eq(pv, subject),
            }) hit = true;
        }
        if (hit) {
            try it.execBlock(w.kids[1]);
            if (!all) break;
        }
    }
    try it.execBlock(n.kids[1]);
}

// @eve-impl the optional code of `over <code>;` and `exit <code>;`
// @spec spec/semantics/errors.md#ending-the-process
// @see backlog/library-gaps.md:G-2
/// Store the exit code of the program: 0, or 6 to 125 (1 to 5 belong to the machine).
pub fn exitCodeOfStmt(it: *Interp, n: *const Node) Signal!void {
    if (n.kids.len == 0) return;
    return it.setExitCode(try it.eval(n.kids[0]));
}

// @eve-impl the exit code of `exit n` and `over n`: 0 or 6 to 125
pub fn setExitCode(it: *Interp, v: Value) Signal!void {
    if (v != .int or v.int < 0 or v.int > 125 or (v.int >= 1 and v.int <= 5)) {
        return it.failWith(interp.err_argument, "an exit code is 0 or a number from 6 to 125: 1 to 5 belong to the machine", .{});
    }
    it.base().exit_code = @intCast(v.int);
}
