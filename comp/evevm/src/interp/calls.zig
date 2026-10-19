//! Calls: functions, methods, constructors, overloads and the arguments of a call.
//! Part of the interpreter (interp.zig): every function takes the interpreter as `it: *Interp`, and
//! `Interp` names each of them again, so a call reads `it.name(...)` wherever it is made.
const std = @import("std");
// Zig tip: interp.zig imports this file and this file imports interp.zig back. Zig allows such a cycle
// between files of one module: declarations are resolved lazily, when they are used, not in the order
// of the imports. `../` names the parent folder; a module may import any file below its root folder.
const interp = @import("../interp.zig");
const db = @import("../db.zig");
const Interp = interp.Interp;
const task = interp.task;
const data = interp.data;
const overload = interp.overload;
const decimal = interp.decimal;
const dlib = interp.dlib;
const netlib = interp.netlib;
const instant = interp.instant;
const Heap = interp.Heap;
const Node = interp.Node;
const value = interp.value;
const Signal = interp.Signal;
const Value = interp.Value;
const Channel = interp.Channel;
const List = interp.List;
const Class = interp.Class;
const Func = interp.Func;
const Var = interp.Var;
const Arg = interp.Arg;
const err_parse = interp.err_parse;
const err_argument = interp.err_argument;

// ---- calls ----------------------------------------------------------------------------

// Zig tip: `call` relies on the same Zig feature as `define` above: see the tip there.
pub fn call(it: *Interp, n: *const Node) Signal!Value {
    const callee = n.kids[0];
    const args = n.kids[1..];
    const stmt = it.stmt_call;
    it.stmt_call = false;
    it.written_types = callee.tag == .generic;
    if (n.sel) |chosen| {
        // the checker chose among overloaded declarations at compile time (D-149)
        const fv = try it.eval(callee);
        if (fv == .func) return it.invoke(try it.newFunc(chosen, fv.func.closure), null, args);
    }
    if (callee.tag == .field) {
        const recv = try it.eval(callee.kids[0]);
        if (recv == .module) return it.callValue(try it.moduleMember(recv.module, callee.text), null, args);
        it.type_args = callee.kids[1..];
        it.call_is_stmt = stmt;
        return it.callMethod(recv, callee.text, args);
    }
    if (callee.tag == .name and args.len == 1 and it.scope.find(callee.text) == null and
        (std.mem.eql(u8, callee.text, "floor") or std.mem.eql(u8, callee.text, "ceiling") or std.mem.eql(u8, callee.text, "round")))
    {
        const eql = std.mem.eql;
        const x = Interp.realOf(try it.eval(args[0])) orelse return it.fail("{s}() needs a number", .{callee.text});
        if (eql(u8, callee.text, "floor")) return .{ .int = @intFromFloat(@floor(x)) };
        if (eql(u8, callee.text, "ceiling")) return .{ .int = @intFromFloat(@ceil(x)) };
        if (eql(u8, callee.text, "round")) return .{ .int = @intFromFloat(@round(x)) };
    }
    if (callee.tag == .name and args.len == 1 and it.scope.find(callee.text) == null and
        (std.mem.eql(u8, callee.text, "log_err") or std.mem.eql(u8, callee.text, "log_wrn")))
    {
        const msg = try it.a.dupe(u8, try it.text(try it.eval(args[0]))); // the run log outlives the values
        const top = it.frames.items[it.frames.items.len - 1];
        try it.logs.append(it.a, .{
            .is_error = callee.text[4] == 'e',
            .line = it.line,
            .unit = top.name,
            .level = it.frames.items.len - 1,
            .text = msg,
        });
        return .nil;
    }
    if (callee.tag == .name and std.mem.eql(u8, callee.text, "type") and it.scope.find("type") == null) {
        if (args.len != 1) return it.fail("type() takes one argument", .{});
        const arg = try it.eval(args[0]);
        if (arg == .str and it.base().text_ptrs.contains(@intFromPtr(arg.str.ptr))) return .{ .typ = "Text" };
        return .{ .typ = Interp.typeName(arg) };
    }
    return it.callValue(try it.eval(callee), null, args);
}

// Zig tip: the types of the arguments are read from the values (`typeName`), then the shared rules of
// overload.zig choose, as the checker did at compile time with the types it knew (D-149). `newFunc` makes
// a function value for the chosen declaration with the scope of the first one; `invokeWith` calls it
// directly, so the choice is not made twice.
/// Call the right declaration among several with the same name, from the values of the arguments.
pub fn invokeOverloaded(it: *Interp, f: *Func, decls: []const *const Node, recv: ?Value, arg_nodes: []const *const Node) Signal!Value {
    const args = try it.evalArgs(arg_nodes);
    defer it.dropArgs(args);
    defer it.writeBack(args);
    const infos = try it.t.alloc(overload.ArgInfo, args.len);
    for (args, infos) |a, *info| info.* = .{ .name = a.name, .ty = Interp.typeName(a.value) };
    const stmt: ?bool = if (decls[0].tag == .method) it.call_is_stmt else null;
    var generic_only: std.ArrayList(*const Node) = .empty;
    if (it.written_types) {
        for (decls) |d| if (d.kids[1].kids.len > 0) try generic_only.append(it.t, d);
    }
    it.written_types = false;
    switch (overload.select(if (generic_only.items.len > 0) generic_only.items else decls, infos, null, stmt)) {
        .one => |d| return it.invokeWith(try it.newFunc(d, f.closure), recv, args),
        .none => return it.fail("no signature of {s} matches the arguments", .{decls[0].text}),
        .ambiguous => return it.fail("ambiguous call of {s}: more than one signature fits", .{decls[0].text}),
    }
}

// Zig tip: `callValue` relies on the same Zig feature as `define` above: see the tip there.
pub fn callValue(it: *Interp, v: Value, recv: ?Value, args: []const *const Node) Signal!Value {
    switch (v) {
        .func => |f| {
            if (it.base().overloads.get(f.node)) |set| return it.invokeOverloaded(f, set.items, recv, args);
            return it.invoke(f, recv, args);
        },
        .range => |r| {
            if (args.len != 1) return it.fail("a range takes one step", .{});
            const step = try it.eval(args[0]);
            if (Interp.isInt(step) and Interp.intOf(step) >= 1) {
                return .{ .range = try it.newRange(.{ .lo = r.lo, .hi = r.hi, .step = Interp.intOf(step), .sym = r.sym }) };
            }
            const st = Interp.realOf(step) orelse return it.fail("the step of a range is a number", .{});
            return .{ .domain = try it.newDomain(.{ .lo = @floatFromInt(r.lo), .hi = @floatFromInt(r.hi), .step = st }) };
        },
        .domain => |d0| {
            if (args.len != 1) return it.fail("a range takes one step", .{});
            const st = Interp.realOf(try it.eval(args[0])) orelse return it.fail("the step of a range is a number", .{});
            return .{ .domain = try it.newDomain(.{ .lo = d0.lo, .hi = d0.hi, .lo_excl = d0.lo_excl, .hi_excl = d0.hi_excl, .step = st }) };
        },
        .class => |c| return it.constructClass(c, args),
        .typ => |name| {
            if (std.mem.eql(u8, name, "Channel")) return it.newChannel(args);
            if (std.mem.eql(u8, name, "Secret")) return it.makeSecret(args);
            if (std.mem.eql(u8, name, "Table")) return .{ .list = try it.newList(&.{}, false) };
            return it.fail("{s} is not callable", .{name});
        },
        else => return it.fail("{s} is not callable", .{Interp.typeName(v)}),
    }
}

pub const classRoutine = value.classRoutine;

// Zig tip: a method of a subclass hides the method of its parent that has the same signature, so a
// candidate is added only if no nearer one has the same signature (`overload.sameSignature`). The list
// lives in the scratch memory of the statement (`it.t`).
/// Every method called `name` that the class, its ancestors, its traits and the extension methods give.
pub fn routinesNamed(it: *Interp, c: *Class, name: []const u8, out: *std.ArrayList(*const Node)) Signal!void {
    var cur: ?*Class = c;
    while (cur) |k| : (cur = k.parent) {
        if (k.node) |node| {
            for (node.kids[2..]) |r| {
                if (r.tag == .constructor or r.kids[3].tag == .none or !std.mem.eql(u8, r.text, name)) continue;
                try it.addUnique(out, r);
            }
        }
        for (k.traits.items) |tr| try it.routinesNamed(tr, name, out);
    }
    for (it.exts.items) |m| {
        if (!std.mem.eql(u8, m.text, name)) continue;
        if (m.kids[0].kids.len == 0) continue;
        const ty = m.kids[0].kids[0].ty orelse continue;
        var anc: ?*Class = c;
        while (anc) |k| : (anc = k.parent) {
            if (std.mem.eql(u8, k.name, ty.text)) try it.addUnique(out, m);
        }
    }
}

pub fn addUnique(it: *Interp, out: *std.ArrayList(*const Node), r: *const Node) Signal!void {
    for (out.items) |o| if (overload.sameSignature(o, r)) return;
    try out.append(it.t, r);
}

// Zig tip: an extension method is declared outside the class; its first parameter is `@self`
// with the type of the class (D-040). The call `p.shift(1, 2)` finds it by the name of the
// class of `p` or of one of its ancestors.
/// The extension method `name` for objects of class `c`.
pub fn extensionFor(it: *Interp, c: *Class, name: []const u8) ?*const Node {
    for (it.exts.items) |m| {
        if (!std.mem.eql(u8, m.text, name)) continue;
        const first = m.kids[0].kids;
        if (first.len == 0) continue;
        const ty = first[0].ty orelse continue;
        var cur: ?*Class = c;
        while (cur) |k| : (cur = k.parent) if (std.mem.eql(u8, k.name, ty.text)) return m;
    }
    return null;
}

// Zig tip: `if (opt) |v| ... else ...` runs the first branch only when the optional has a value,
// and names it `v`.
pub fn callMethod(it: *Interp, recv: Value, name: []const u8, args: []const *const Node) Signal!Value {
    const stmt = it.call_is_stmt;
    it.call_is_stmt = false;
    if (recv == .object) {
        if (recv.object.class) |c| {
            var cands: std.ArrayList(*const Node) = .empty;
            try it.routinesNamed(c, name, &cands);
            if (cands.items.len > 1) {
                // several methods share the name (D-149): the arguments decide
                const values = try it.evalArgs(args);
                defer it.dropArgs(values);
                defer it.writeBack(values);
                const infos = try it.t.alloc(overload.ArgInfo, values.len);
                for (values, infos) |a, *info| info.* = .{ .name = a.name, .ty = Interp.typeName(a.value) };
                switch (overload.select(cands.items, infos, null, stmt)) {
                    .one => |d| return it.invokeWith(try it.newFunc(d, it.unit), recv, values),
                    .none => return it.fail("no signature of {s} matches the arguments", .{name}),
                    .ambiguous => return it.fail("ambiguous call of {s}: more than one signature fits", .{name}),
                }
            }
            if (Interp.classRoutine(c, name) orelse it.extensionFor(c, name)) |r| {
                return it.invoke(try it.newFunc(r, it.unit), recv, args);
            }
        }
    }
    const eql = std.mem.eql;
    if (recv == .typ) if (try dlib.libraryCall(it, recv.typ, name, args)) |v| return v;
    if (recv == .object and recv.object.class != null and recv.object.class == it.base().gen_class) {
        return it.generatorCall(recv.object, name, args);
    }
    if (dlib.isStream(it, recv)) return dlib.streamCall(it, recv.object, name, args);
    if (netlib.isNet(it, recv)) return netlib.call(it, recv.object, name, args);
    if (db.orm.isTable(it.host(), recv)) return db.orm.tableCall(it.host(), recv.object, name, args);
    if (db.driver.isConnection(it.host(), recv)) return db.driver.connectionCall(it.host(), recv.object, name, args);
    if (db.memory.isMemory(it.host(), recv)) return db.memory.memoryCall(it.host(), recv.object, name, args);
    if (db.memory.isColumn(it.host(), recv)) return db.memory.columnCall(it.host(), recv.object, name, args);
    if (recv == .chan) return it.channelMethod(recv.chan, name, args);
    if (recv == .map) if (try it.mapMethod(recv.map, name, args)) |v| return v;
    if ((eql(u8, name, "batch") or eql(u8, name, "split")) and recv == .list and args.len == 1) {
        return it.cut(recv.list, eql(u8, name, "split"), try it.eval(args[0]));
    }
    // the explicit conversions between Decimal and Real (data-language.md, D-168)
    if (eql(u8, name, "real") and args.len == 0 and recv == .dec) return .{ .real = decimal.toF64(recv.dec) };
    if (eql(u8, name, "decimal") and args.len == 0 and (recv == .real or recv == .float)) return .{ .dec = try it.decFromReal(Interp.realOf(recv).?) };
    if (eql(u8, name, "compare") and args.len == 1 and recv != .object) {
        return .{ .int = switch (try it.order(recv, try it.eval(args[0]))) {
            .lt => -1,
            .eq => 0,
            .gt => 1,
        } };
    }
    if (recv == .typ and eql(u8, recv.typ, "Instant") and eql(u8, name, "parse") and args.len == 1) {
        const txt = try it.text(try it.eval(args[0]));
        const us = instant.parse(txt) orelse return it.failWith(err_parse, "Cannot parse '{s}' as an Instant: expected 2026-10-10T08:00:00Z", .{txt});
        return .{ .instant = us };
    }
    if (recv == .typ and eql(u8, name, "parse") and args.len == 1) {
        const txt = try it.text(try it.eval(args[0]));
        const x = std.fmt.parseFloat(f64, std.mem.trim(u8, txt, " ")) catch return it.failWith(15, "Cannot parse {s} as {s}", .{ txt, recv.typ });
        if (eql(u8, recv.typ, "Integer")) return .{ .int = @intFromFloat(x) };
        return .{ .real = x };
    }
    if (eql(u8, name, "delete") and (recv == .list or recv == .set) and args.len == 1) {
        const gone = try it.eval(args[0]);
        const l = recv.list;
        var k: usize = 0;
        while (k < l.items.items.len) {
            if (Interp.eq(l.items.items[k], gone)) _ = it.listRemove(l, k) else k += 1;
        }
        return .nil;
    }
    if (eql(u8, name, "length") or eql(u8, name, "count")) {
        return .{ .int = switch (recv) {
            .str => |s| @intCast(std.unicode.utf8CountCodepoints(s) catch s.len),
            .list, .set => |l| @intCast(l.elems().len),
            .map => |m| @intCast(m.entries.items.len),
            .object => |o| @intCast(o.fields.items.len),
            else => return it.fail("{s} has no length", .{Interp.typeName(recv)}),
        } };
    }
    if (recv == .str) if (try stringFunction(it, recv.str, name, args)) |v| return v;
    if (eql(u8, name, "split") and recv == .str and args.len == 1) {
        const sep = try it.text(try it.eval(args[0]));
        const out = try it.h.make(List, .{});
        var parts = std.mem.splitSequence(u8, recv.str, sep);
        while (parts.next()) |p| try it.listAppend(out, try it.newStr(p));
        return .{ .list = out };
    }
    if (eql(u8, name, "join") and (recv == .list or recv == .set) and args.len == 1) {
        const sep = try it.text(try it.eval(args[0]));
        var buf: std.ArrayList(u8) = .empty;
        for (recv.list.elems(), 0..) |e, i| {
            if (i > 0) try buf.appendSlice(it.t, sep);
            try it.show(&buf, e, false);
        }
        return .{ .str = try it.persist(buf.items) };
    }
    return it.fail("{s} has no method '{s}'", .{ Interp.typeName(recv), name });
}

// Zig tip: `evalArgs` relies on the same Zig feature as `define` above: see the tip there.
/// Evaluate the arguments of a call in the caller's scope.
pub fn evalArgs(it: *Interp, nodes: []const *const Node) Signal![]Arg {
    var out: std.ArrayList(Arg) = .empty;
    for (nodes) |a| {
        if (a.tag == .pair and a.kids[0].tag == .name and a.kids[1].tag == .ref and a.kids[1].kids.len > 0) {
            var arg = try it.elementRef(a.kids[1]);
            arg.name = a.kids[0].text;
            try out.append(it.t, arg);
        } else if (a.tag == .pair and a.kids[0].tag == .name and a.kids[1].tag == .ref) {
            const cell = it.scope.find(a.kids[1].text) orelse return it.fail("undefined name '{s}'", .{a.kids[1].text});
            try out.append(it.t, .{ .name = a.kids[0].text, .value = cell.value, .ref = cell });
        } else if (a.tag == .pair and a.kids[0].tag == .name) {
            try out.append(it.t, .{ .name = a.kids[0].text, .value = try it.eval(a.kids[1]) });
        } else if (a.tag == .spread) {
            const spread = try it.eval(a.kids[0]);
            if (spread == .map) {
                // `*map`: every key is the name of a parameter, every value its argument
                for (spread.map.entries.items) |e| {
                    // Zig tip: a labeled block `blk: { ... break :blk v; }` is an expression whose value is
                    // the `break`; here it builds the text of a symbol, while a text key is used as it is.
                    const key = switch (e.key) {
                        .str => |s| s,
                        .sym => |c| blk: {
                            var buf: std.ArrayList(u8) = .empty;
                            try it.utf8(&buf, c);
                            break :blk buf.items;
                        },
                        else => return it.fail("a map spread into arguments needs text or symbol keys", .{}),
                    };
                    try out.append(it.t, .{ .name = key, .value = e.val });
                }
            } else for (try it.iterate(spread)) |x| try out.append(it.t, .{ .value = x });
        } else if (a.tag == .ref and a.kids.len > 0) {
            try out.append(it.t, try it.elementRef(a));
        } else if (a.tag == .ref) {
            const cell = it.scope.find(a.text) orelse return it.fail("undefined name '{s}'", .{a.text});
            try out.append(it.t, .{ .value = cell.value, .ref = cell });
        } else try out.append(it.t, .{ .value = try it.eval(a) });
    }
    return out.items;
}

// Zig tip: parameters are matched to arguments in three steps: by name, then by position,
// then by default value. `taken` marks the arguments already used, a stack array of booleans
// (`[_]bool{false} ** 32` repeats one value 32 times at compile time). A by-reference
// parameter does not copy the value: it binds the parameter name to the caller's `*Var`.
/// Bind the parameters of `params` in the current scope. `self_var` is the receiver of a method.
pub fn bindParams(it: *Interp, params: []const *const Node, args: []const Arg, self_var: ?*Var) Signal!void {
    var taken: [32]bool = @splat(false);
    if (args.len > taken.len) return it.fail("too many arguments", .{});
    var pos: usize = 0;
    for (params, 0..) |prm, k| {
        if (k == 0 and prm.tag == .ref_param and std.mem.eql(u8, prm.text, "self") and self_var != null) {
            try it.bind("self", self_var.?);
            continue;
        }
        if (prm.tag == .vararg_param) {
            const rest = try it.newList(&.{}, false);
            while (pos < args.len) : (pos += 1) {
                if (taken[pos] or args[pos].name.len > 0) continue;
                taken[pos] = true;
                try it.listAppend(rest, args[pos].value);
            }
            try it.define(prm.text, .{ .list = rest }, false);
            continue;
        }
        var found: ?usize = null;
        for (args, 0..) |a, i| {
            if (!taken[i] and a.name.len > 0 and std.mem.eql(u8, a.name, prm.text)) found = i;
        }
        if (found == null) {
            while (pos < args.len and (taken[pos] or args[pos].name.len > 0)) pos += 1;
            if (pos < args.len) {
                found = pos;
                pos += 1;
            }
        }
        if (found) |i| {
            taken[i] = true;
            if (prm.tag == .ref_param and args[i].ref != null) {
                try it.bind(prm.text, args[i].ref.?);
            } else try it.define(prm.text, args[i].value, false);
        } else if (prm.kids[0].tag != .none) {
            try it.define(prm.text, try it.eval(prm.kids[0]), false);
        } else try it.define(prm.text, try it.zero(prm.ty), false);
    }
    for (args, 0..) |a, i| {
        if (!taken[i]) return it.fail("unexpected argument{s}{s}", .{ if (a.name.len > 0) " " else "", a.name });
    }
}

// Zig tip: `defer it.scope = saved;` restores the caller's scope however the function ends, also
// when a `raise` unwinds through it: this is what makes error handling with Zig errors safe.
/// Call a function, method or lambda. `recv` is the object of `obj.method(...)`.
pub fn invoke(it: *Interp, f: *Func, recv: ?Value, arg_nodes: []const *const Node) Signal!Value {
    const args = try it.evalArgs(arg_nodes);
    defer it.dropArgs(args);
    defer it.writeBack(args);
    return it.invokeWith(f, recv, args);
}

// Zig tip: `invokeWith` relies on the same Zig feature as `invoke` above: see the tip there. A
// spawned task evaluates its arguments in the parent, at `spawn`, and calls this in its own thread.
/// Call a function, method or lambda with arguments already evaluated.
pub fn invokeWith(it: *Interp, f: *Func, recv: ?Value, args: []const Arg) Signal!Value {
    // a call of a generator does not run its body: it makes the generator object (D-067)
    if (f.node.tag == .generator) return it.makeGenerator(f, recv, args);
    return it.runRoutine(f, recv, args);
}

// Zig tip: `runRoutine` is the old body of `invokeWith`: it runs a function, method, lambda or the body of a
// generator (on the thread of the generator).
/// Run the body of a routine with the arguments already evaluated.
pub fn runRoutine(it: *Interp, f: *Func, recv: ?Value, args: []const Arg) Signal!Value {
    const node = f.node;
    // @eve-impl an `external` routine of a user module has no native yet: a clear error, not a crash on the empty body
    // @spec spec/semantics/modules.md#members
    // @decision D-189
    // @eve-impl an `external` routine of module M is the native `M.name` of the machine (G-3, TD-2): the arguments are bound as parameters, then the native reads them by name
    // @spec spec/semantics/modules.md#members
    // @decision D-189
    const s = try it.newScope(f.closure);
    const saved = try it.enterScope(s);
    defer it.leaveScope(saved);
    if (node.is_external) {
        var mod: ?*interp.Module = null;
        var mods = it.base().loaded.valueIterator();
        while (mods.next()) |m| if (m.*.scope == f.closure) {
            mod = m.*;
        };
        try it.bindParams(node.kids[0].kids, args, null);
        if (mod) |m| {
            const params = node.kids[0].kids;
            const names = try it.a.alloc(*const Node, params.len);
            for (params, names) |p, *slot| {
                const nm = try it.a.create(Node);
                nm.* = .{ .tag = .name, .line = it.line, .text = p.text };
                slot.* = nm;
            }
            if (try dlib.libraryCall(it, m.name, node.text, names)) |v| return v;
        }
        return it.fail("external {s} {s} has no native implementation in this machine", .{ @tagName(node.tag), node.text });
    }
    if (node.tag == .lambda) {
        try it.bindParams(node.kids[0].kids, args, null);
        return it.eval(node.kids[1]);
    }
    var self_var: ?*Var = null;
    if (recv) |r| {
        self_var = try it.h.make(Var, .{ .value = r });
        Heap.retain(r);
    }
    try it.bindParams(node.kids[0].kids, args, self_var);
    for (node.kids[2].kids) |res| try it.define(res.text, try it.zero(res.ty), false);
    try it.frames.append(it.a, .{ .kind = @tagName(node.tag), .name = node.text, .call_line = it.line, .file = interp.ast.fileOf(node) });
    defer _ = it.frames.pop();
    const mark = it.defers.items.len;
    var outcome = it.execBlock(node.kids[3]);
    // @eve-impl the `recover` region of a function, procedure or method (kids[4]): runs after a raised error, with `$error`;
    // reaching its end handles the error and the routine returns the result variables as they are; `abort` passes the error on
    // @spec spec/semantics/errors.md#recover-in-a-function-procedure-or-method
    // @feature F-STR-11
    // @decision D-192
    if (node.kids.len > 4) if (outcome) |_| {} else |e| if (e == error.Raise) {
        try it.define("$error", try it.errorObject(), false);
        const idx = it.reports.items.len - 1;
        outcome = it.execBlock(node.kids[4]);
        if (outcome) |_| {
            it.reports.items[idx].handled = true;
        } else |re| switch (re) {
            error.Abort => outcome = error.Raise,
            error.Retry, error.Resume => outcome = it.fail("retry and resume need a failed job: a {s} can only handle the error or abort (D-192)", .{@tagName(node.tag)}),
            else => {},
        }
    };
    if (outcome) |_| it.runDefers(mark) else |e| if (e != error.Panic) it.runDefers(mark);
    outcome catch |e| if (e != error.Exit) return e;
    const res = node.kids[2].kids;
    if (res.len > 1) {
        const l = try it.h.make(List, .{});
        for (res) |r| try it.listAppend(l, s.find(r.text).?.value);
        return .{ .list = l };
    }
    if (res.len == 1) return s.find(res[0].text).?.value;
    return .nil;
}

// @eve-fn String.trim, String.trim_start, String.trim_end, String.upper, String.lower, String.starts_with, String.ends_with
// @eve-fn String.contains, String.find, String.replace
// @spec spec/library/strings.md#functions
// @feature F-LIB-03
// @decision D-189
// @test test/level1/a87_string_functions
// @invariant plain text, not a pattern, even when the argument starts with `/` (Q-066); `find` counts runes from 1, 0 = none
/// A string function of the library, or null when `name` is not one.
fn stringFunction(it: *Interp, s: []const u8, name: []const u8, args: []const *const Node) Signal!?Value {
    const eql = std.mem.eql;
    const white = [_]u8{ ' ', 9, 10, 13 }; // space, tab, LF, CR
    if (args.len == 0) {
        if (eql(u8, name, "trim")) return try it.newStr(std.mem.trim(u8, s, &white));
        if (eql(u8, name, "trim_start")) return try it.newStr(std.mem.trimStart(u8, s, &white));
        if (eql(u8, name, "trim_end")) return try it.newStr(std.mem.trimEnd(u8, s, &white));
        if (eql(u8, name, "upper") or eql(u8, name, "lower")) {
            const out = try it.t.alloc(u8, s.len);
            for (s, 0..) |c, i| out[i] = if (name[0] == 'u') std.ascii.toUpper(c) else std.ascii.toLower(c);
            return try it.newStr(out);
        }
        return null;
    }
    const one = eql(u8, name, "starts_with") or eql(u8, name, "ends_with") or eql(u8, name, "contains") or eql(u8, name, "find");
    const two = eql(u8, name, "replace");
    if (!(one and args.len == 1) and !(two and args.len == 2)) return null;
    const t = try it.eval(args[0]);
    if (t != .str) return it.failWith(err_argument, "{s}: the argument is a String", .{name});
    if (one) {
        if (eql(u8, name, "starts_with")) return .{ .bool = std.mem.startsWith(u8, s, t.str) };
        if (eql(u8, name, "ends_with")) return .{ .bool = std.mem.endsWith(u8, s, t.str) };
        const at = std.mem.indexOf(u8, s, t.str);
        if (eql(u8, name, "contains")) return .{ .bool = at != null };
        const byte = at orelse return .{ .int = 0 };
        return .{ .int = @intCast((std.unicode.utf8CountCodepoints(s[0..byte]) catch byte) + 1) };
    }
    const repl = try it.eval(args[1]);
    if (repl != .str) return it.failWith(err_argument, "replace: the new text is a String", .{});
    if (t.str.len == 0) return it.failWith(err_argument, "replace: the text to replace is empty", .{});
    return try it.newStr(try std.mem.replaceOwned(u8, it.t, s, t.str, repl.str));
}

// Zig tip: `construct` relies on the same Zig feature as `define` above: see the tip there.
/// `new Class(args)`.
pub fn constructClass(it: *Interp, cls: *Class, arg_nodes: []const *const Node) Signal!Value {
    // a class derived from `Memory` is a columnar table (D-184)
    if (cls.node != null) if (try db.memory.memoryNew(it.host(), cls)) |v| return v;
    const obj = try it.newObject();
    if (cls.node == null) return .{ .object = obj };
    const args = try it.evalArgs(arg_nodes);
    defer it.dropArgs(args);
    var ctor: ?*const Node = null;
    for (cls.node.?.kids[2..]) |r| if (r.tag == .constructor) {
        ctor = r;
    };
    if (ctor) |k| {
        const saved = try it.enterScope(try it.newScope(it.unit));
        defer it.leaveScope(saved);
        const self_var = try it.h.make(Var, .{ .value = .nil });
        try it.bind("self", self_var);
        try it.bindParams(k.kids[0].kids, args, null);
        try it.execBlock(k.kids[3]);
        if (self_var.value != .object) return it.fail("the constructor of {s} must set self to an object", .{cls.name});
        self_var.value.object.class = cls;
        return self_var.value;
    }
    const members = cls.node.?.kids[0].kids;
    var pos: usize = 0;
    for (members) |m| {
        var v = try it.zero(m.ty);
        for (args) |a| if (std.mem.eql(u8, a.name, m.text)) {
            v = a.value;
        };
        if (pos < args.len and args[pos].name.len == 0 and v == .nil) v = args[pos].value;
        if (args.len > pos and args[pos].name.len == 0) pos += 1;
        try it.setField(obj, m.text, v);
    }
    obj.class = cls;
    return .{ .object = obj };
}

// Zig tip: `zero` relies on the same Zig feature as `define` above: see the tip there.
/// The value a variable of a type has before it is assigned.
pub fn zero(it: *Interp, ty: ?*const Node) Signal!Value {
    const t = ty orelse return .nil;
    if (t.kids.len > 0) {
        // an array: the first dimension is built here, the others inside
        const dim = try it.eval(t.kids[0]);
        if (!Interp.isInt(dim)) return it.fail("an array size is an integer", .{});
        const inner: Node = .{ .tag = .type, .text = t.text, .kids = t.kids[1..] };
        const l = try it.h.make(List, .{ .array = true });
        var k: i64 = 0;
        while (k < Interp.intOf(dim)) : (k += 1) try it.listAppend(l, try it.zero(&inner));
        return .{ .list = l };
    }
    const eql = std.mem.eql;
    if (t.text.len > 0 and t.text[t.text.len - 1] == '?') return .nil; // an optional type starts as null
    if (std.mem.startsWith(u8, t.text, "()")) return .{ .list = try it.newList(&.{}, false) };
    if (std.mem.startsWith(u8, t.text, "[]")) return .{ .list = try it.newList(&.{}, true) };
    if (eql(u8, t.text, "Integer") or eql(u8, t.text, "Short") or eql(u8, t.text, "Byte")) return .{ .int = 0 };
    if (eql(u8, t.text, "Natural")) return .{ .nat = 0 };
    if (eql(u8, t.text, "Real") or eql(u8, t.text, "Float")) return .{ .real = 0 };
    if (eql(u8, t.text, "Logic")) return .{ .bool = false };
    if (eql(u8, t.text, "Decimal")) return .{ .dec = .{ .scale = 0, .m = 0 } };
    if (eql(u8, t.text, "Instant")) return .{ .instant = 0 };
    if (eql(u8, t.text, "String")) return it.staticStr("");
    if (eql(u8, t.text, "Symbol") or eql(u8, t.text, "Rune")) return .{ .sym = 0 };
    if (eql(u8, t.text, "DataSet")) return .{ .set = try it.newList(&.{}, false) };
    if (eql(u8, t.text, "DataMap")) return .{ .map = try it.newMap() };
    return .nil;
}

// Zig tip: a tiny matcher, written as three small recursive functions. It supports literals,
// `.`, `^`, `$`, classes `[a-z]`, `\d \w \s`, the quantifiers `* + ?` and `|` between whole
// alternatives; groups are not supported. `pattern` is `/body/flags`; the flag `i` ignores case.
pub fn atomLen(pat: []const u8) usize {
    if (pat[0] == '\\' and pat.len > 1) return 2;
    if (pat[0] == '[') return (std.mem.indexOfScalar(u8, pat, ']') orelse pat.len - 1) + 1;
    return 1;
}

// Zig tip: `atomMatch` relies on the same Zig feature as `mapPut` above: see the tip there.
pub fn atomMatch(atom: []const u8, c: u8, ic: bool) bool {
    const ch = if (ic) std.ascii.toLower(c) else c;
    if (atom[0] == '.') return true;
    if (atom[0] == '\\' and atom.len > 1) {
        return switch (atom[1]) {
            'd' => std.ascii.isDigit(c),
            'w' => std.ascii.isAlphanumeric(c) or c == '_',
            's' => std.ascii.isWhitespace(c),
            else => c == atom[1],
        };
    }
    if (atom[0] == '[') {
        var body = atom[1 .. atom.len - 1];
        var negate = false;
        if (body.len > 0 and body[0] == '^') {
            negate = true;
            body = body[1..];
        }
        var hit = false;
        var k: usize = 0;
        while (k < body.len) : (k += 1) {
            if (k + 2 < body.len and body[k + 1] == '-') {
                if (ch >= std.ascii.toLower(body[k]) and ch <= std.ascii.toLower(body[k + 2]) or c >= body[k] and c <= body[k + 2]) hit = true;
                k += 2;
            } else if (ch == (if (ic) std.ascii.toLower(body[k]) else body[k])) hit = true;
        }
        return hit != negate;
    }
    return ch == (if (ic) std.ascii.toLower(atom[0]) else atom[0]);
}

// Zig tip: `matchHere` relies on the same Zig feature as `mapPut` above: see the tip there.
pub fn matchHere(pat: []const u8, txt: []const u8, ic: bool) bool {
    if (pat.len == 0) return true;
    if (pat.len == 1 and pat[0] == '$') return txt.len == 0;
    const n = Interp.atomLen(pat);
    const atom = pat[0..n];
    const rest = pat[n..];
    if (rest.len > 0 and (rest[0] == '*' or rest[0] == '+' or rest[0] == '?')) {
        var k: usize = 0;
        const limit: usize = if (rest[0] == '?') 1 else txt.len;
        while (k < limit and k < txt.len and Interp.atomMatch(atom, txt[k], ic)) k += 1;
        const min: usize = if (rest[0] == '+') 1 else 0;
        while (true) {
            if (k >= min and Interp.matchHere(rest[1..], txt[k..], ic)) return true;
            if (k == 0) return false;
            k -= 1;
        }
    }
    if (txt.len > 0 and Interp.atomMatch(atom, txt[0], ic)) return Interp.matchHere(rest, txt[1..], ic);
    return false;
}

// Zig tip: `regexMatch` relies on the same Zig feature as `mapPut` above: see the tip there.
/// Does `text` match the pattern `/body/flags`?
pub fn regexMatch(spec: []const u8, txt: []const u8) bool {
    const last = std.mem.lastIndexOfScalar(u8, spec, '/') orelse return std.mem.indexOf(u8, txt, spec) != null;
    if (spec.len < 2 or spec[0] != '/' or last == 0) return std.mem.indexOf(u8, txt, spec) != null;
    const body = spec[1..last];
    const ic = std.mem.indexOfScalar(u8, spec[last + 1 ..], 'i') != null;
    var alts = std.mem.splitScalar(u8, body, '|');
    while (alts.next()) |alt| {
        const anchored = alt.len > 0 and alt[0] == '^';
        const pat = if (anchored) alt[1..] else alt;
        var i: usize = 0;
        while (i <= txt.len) : (i += 1) {
            if (Interp.matchHere(pat, txt[i..], ic)) return true;
            if (anchored) break;
        }
    }
    return false;
}
