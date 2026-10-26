//! @eve-module interp.calls
//! @spec spec/syntax/declarations.md#functions-and-procedures, spec/syntax/declarations.md#generic-subprograms-and-overloading
//! @feature F-LNG-09, F-LNG-10, F-LNG-21
//! @decision D-106, D-149
//! @tests test/level2, test/level3
//! Calls: functions, methods, constructors, overloads and the arguments of a call.
//! Part of the interpreter (interp.zig): every function takes the interpreter as `it: *Interp`, and
//! `Interp` names each of them again, so a call reads `it.name(...)` wherever it is made.
const std = @import("std");
const interp = @import("../interp.zig");
const regexlib = @import("../regexlib.zig");
const timelib = @import("../timelib.zig");
const bytesfn = @import("bytesfn.zig");
const uuidlib = @import("../uuidlib.zig");
const metalib = @import("../metalib.zig");
const db = @import("../db.zig");
const Interp = interp.Interp;
const task = interp.task;
const data = interp.data;
const overload = interp.overload;
const decimal = interp.decimal;
const dlib = interp.dlib;
const corelib = @import("corelib.zig");
const console = @import("console.zig");
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
    if (callee.tag == .name and args.len == 1 and
        (std.mem.eql(u8, callee.text, "floor") or std.mem.eql(u8, callee.text, "ceiling") or std.mem.eql(u8, callee.text, "round")) and
        it.scope.find(callee.text) == null)
    {
        const eql = std.mem.eql;
        const arg = try it.eval(args[0]);
        if (arg == .rat) {
            const q = arg.rat;
            if (eql(u8, callee.text, "floor")) return .{ .int = interp.rational.floor(q) };
            if (eql(u8, callee.text, "ceiling")) return .{ .int = interp.rational.ceiling(q) };
            return .{ .int = interp.rational.round(q) };
        }
        const x = Interp.realOf(arg) orelse return it.fail("{s}() needs a number", .{callee.text});
        if (eql(u8, callee.text, "floor")) return .{ .int = @intFromFloat(@floor(x)) };
        if (eql(u8, callee.text, "ceiling")) return .{ .int = @intFromFloat(@ceil(x)) };
        if (eql(u8, callee.text, "round")) return .{ .int = @intFromFloat(@round(x)) };
    }
    // @eve-fn error, warning
    // @spec spec/semantics/aspects.md#messages-on-the-standard-error
    // @decision D-057
    // @test a95_error_warning
    if (callee.tag == .name and args.len == 1 and it.scope.find(callee.text) == null and
        (std.mem.eql(u8, callee.text, "error") or std.mem.eql(u8, callee.text, "warning")))
    {
        const msg = try it.text(try it.eval(args[0]));
        const io = it.io orelse return it.fail("{s}(): no standard error", .{callee.text});
        var buf: [256]u8 = undefined;
        var w: std.Io.File.Writer = .initStreaming(.stderr(), io, &buf);
        w.interface.print("{s}\n", .{msg}) catch {};
        w.interface.flush() catch {};
        return .nil;
    }
    // @eve-fn warn
    // @spec spec/semantics/errors.md#error-classes
    // @test c62_error_construct
    if (callee.tag == .name and args.len == 2 and it.scope.find(callee.text) == null and std.mem.eql(u8, callee.text, "warn")) {
        const code = try it.eval(args[0]);
        if (!Interp.isInt(code)) return it.failWith(err_argument, "warn: the code is a whole number", .{});
        const msg = try it.text(try it.eval(args[1]));
        const io = it.io orelse return it.fail("warn(): no standard error", .{});
        var buf: [256]u8 = undefined;
        var w: std.Io.File.Writer = .initStreaming(.stderr(), io, &buf);
        const top = it.frames.items[it.frames.items.len - 1];
        w.interface.print("{s}:{d}: warning {d}: {s}\n", .{ top.name, it.line, Interp.intOf(code), msg }) catch {};
        w.interface.flush() catch {};
        return .nil;
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
    if (callee.tag == .name and std.mem.eql(u8, callee.text, "read") and it.scope.find("read") == null)
        return console.read(it, args);
    // @eve-fn error_type
    // @spec spec/semantics/errors.md#error-classes
    // @test c61_error_classes
    if (callee.tag == .name and std.mem.eql(u8, callee.text, "error_type") and it.scope.find("error_type") == null) {
        if (args.len != 1) return it.fail("error_type() takes the code of an error", .{});
        const code = try it.eval(args[0]);
        if (!Interp.isInt(code)) return it.failWith(interp.err_argument, "error_type: the code is a whole number, found {s}", .{Interp.typeName(code)});
        return if (interp.errclasses.byCode(Interp.intOf(code))) |c| .{ .class = c } else .nil;
    }
    if (callee.tag == .name and std.mem.eql(u8, callee.text, "type") and it.scope.find("type") == null) {
        if (args.len != 1) return it.fail("type() takes one argument", .{});
        const arg = try it.eval(args[0]);
        if (arg == .str and it.base().text_ptrs.contains(@intFromPtr(arg.str.ptr))) return .{ .typ = "Text" };
        return .{ .typ = Interp.typeName(arg) };
    }
    return it.callValue(try it.eval(callee), null, args);
}

// @decision D-149
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

/// Every method called `name` that the class, its ancestors, its traits and the extension methods give.
pub fn routinesNamed(it: *Interp, c: *Class, name: []const u8, out: *std.ArrayList(*const Node)) Signal!void {
    var cur: ?*Class = c;
    while (cur) |k| : (cur = k.parent) {
        if (k.node) |node| {
            for (node.kids[2..]) |r| {
                if (r.tag == .set or r.tag == .constructor or r.kids[3].tag == .none or !std.mem.eql(u8, r.text, name)) continue;
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

// @decision D-040
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
    if (recv == .typ and eql(u8, name, "parse") and args.len >= 2 and args.len <= 3 and (eql(u8, recv.typ, "Date") or eql(u8, recv.typ, "Time") or eql(u8, recv.typ, "Instant") or eql(u8, recv.typ, "DateTime"))) {
        const txt = try it.text(try it.eval(args[0]));
        const pat = try it.text(try it.eval(args[1]));
        var zid: ?u32 = null;
        if (args.len == 3) {
            const zv = try it.eval(args[2]);
            zid = switch (zv) {
                .zone => |z| z,
                .str => |zs| (try metalib.zoneIdOf(it, zs)) orelse return it.failWith(err_argument, "{s}.parse: '{s}' is not a time zone", .{ recv.typ, zs }),
                else => return it.failWith(err_argument, "{s}.parse: argument 3 is a Zone or its name", .{recv.typ}),
            };
        }
        return timelib.parseText(it, txt, pat, recv.typ, zid);
    }
    if (recv == .typ and eql(u8, recv.typ, "DateTime") and eql(u8, name, "parse") and args.len == 1) return timelib.parseDateTimeIso(it, try it.text(try it.eval(args[0])));
    if (recv == .typ and eql(u8, recv.typ, "Zone") and eql(u8, name, "parse") and args.len == 1) {
        const zs = try it.text(try it.eval(args[0]));
        return .{ .zone = (try metalib.zoneIdOf(it, std.mem.trim(u8, zs, " "))) orelse return it.failWith(err_parse, "Cannot parse '{s}' as a Zone: a name of the IANA database, Z, or an offset such as +03:00", .{zs}) };
    }
    if ((recv == .instant or recv == .dtm) and eql(u8, name, "format")) if (try timelib.method(it, recv, name, args)) |v| return v;
    if (recv == .typ and eql(u8, recv.typ, "Date") and eql(u8, name, "parse") and args.len == 1) {
        const txt = try it.text(try it.eval(args[0]));
        const days = interp.calendar.parseDate(std.mem.trim(u8, txt, " ")) orelse return it.failWith(err_parse, "Cannot parse '{s}' as a Date: expected 2026-10-24", .{txt});
        return .{ .date = days };
    }
    if (recv == .typ and eql(u8, recv.typ, "Time") and eql(u8, name, "parse") and args.len == 1) {
        const txt = try it.text(try it.eval(args[0]));
        const us = interp.calendar.parseTime(std.mem.trim(u8, txt, " ")) orelse return it.failWith(err_parse, "Cannot parse '{s}' as a Time: expected 08:30:00", .{txt});
        return .{ .time = us };
    }
    // the functions of the module `time` as methods of a Date or a Time: `d.year()`, `d.add_months(1)`
    if (recv == .date or recv == .time or recv == .dtm) if (try timelib.method(it, recv, name, args)) |v| return v;
    if (recv == .bytes) if (try bytesfn.method(it, recv.bytes, name, args)) |v| return v;
    if (recv == .uuid) if (try uuidlib.method(it, recv.uuid, name, args)) |v| return v;
    if (recv == .typ and eql(u8, recv.typ, "Uuid")) if (try uuidlib.staticCall(it, name, args)) |v| return v;
    if (recv == .typ and eql(u8, recv.typ, "Bytes")) if (try bytesfn.staticCall(it, name, args)) |v| return v;
    if (recv == .typ and eql(u8, recv.typ, "Duration") and eql(u8, name, "parse") and args.len == 1) {
        const txt = try it.text(try it.eval(args[0]));
        const us = interp.duration.parse(txt) orelse return it.failWith(err_parse, "Cannot parse '{s}' as a Duration: expected PT1H30M or 1h30m", .{txt});
        return .{ .dur = us };
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
    // @eve-impl an extension method of a basic type (`method describe(@self: Integer)`, `adopt ... for Integer`): CLS-15, D-202
    // @spec spec/syntax/declarations.md#traits-and-generic-classes
    // @test d42_adopt_trait
    if (recv != .object) for (it.exts.items) |m| {
        if (!eql(u8, m.text, name) or m.kids[0].kids.len == 0) continue;
        const ty = m.kids[0].kids[0].ty orelse continue;
        if (eql(u8, ty.text, Interp.typeName(recv))) return it.invoke(try it.newFunc(m, it.unit), recv, args);
    };
    // the core library: more functions of a String, a List and a DataMap (spec/library/lists.md, maps.md, strings.md)
    if (recv == .str) if (try corelib.stringMore(it, recv.str, name, args)) |v| return v;
    if (recv == .list or recv == .set) if (try corelib.listMethod(it, recv, name, args)) |v| return v;
    if (recv == .map) if (try corelib.mapMore(it, recv.map, name, args)) |v| return v;
    return it.fail("{s} has no method '{s}'", .{ Interp.typeName(recv), name });
}

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

/// Call a function, method or lambda. `recv` is the object of `obj.method(...)`.
pub fn invoke(it: *Interp, f: *Func, recv: ?Value, arg_nodes: []const *const Node) Signal!Value {
    const args = try it.evalArgs(arg_nodes);
    defer it.dropArgs(args);
    defer it.writeBack(args);
    return it.invokeWith(f, recv, args);
}

/// The fast code of an `external` routine of a library module, or 1 when it has none.
pub fn fastCodeOf(it: *Interp, f: *Func) u32 {
    var mods = it.base().loaded.valueIterator();
    while (mods.next()) |m| if (m.*.scope == f.closure) return dlib.fastResolve(m.*.name, f.node.text) orelse 1;
    return 1;
}

/// Call a function, method or lambda with arguments already evaluated.
pub fn invokeWith(it: *Interp, f: *Func, recv: ?Value, args: []const Arg) Signal!Value {
    // @perf hot
    // @eve-impl a pure numeric library function (math, rational, complex) is called with the values, without a scope (TD-71)
    if (f.node.is_external and f.fast != 1) {
        if (f.fast == 0) {
            f.fast = it.fastCodeOf(f);
        }
        if (f.fast > 1 and recv == null and args.len <= 4 and args.len == f.node.kids[0].kids.len) {
            var vals: [4]Value = undefined;
            var plain = true;
            for (args, 0..) |a, i| {
                if (a.name.len != 0 or a.ref != null) plain = false;
                vals[i] = a.value;
            }
            if (plain) return dlib.fastCall(it, f.fast, vals[0..args.len]);
        }
    }
    // a call of a generator does not run its body: it makes the generator object (D-067)
    if (f.node.tag == .generator) return it.makeGenerator(f, recv, args);
    return it.runRoutine(f, recv, args);
}

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
    // @perf hot
    // one allocation for the bindings of the call (parameters, results, `self`) instead of a growth by steps
    if (node.tag != .lambda) try s.binds.ensureTotalCapacity(it.g, node.kids[0].kids.len + node.kids[2].kids.len + 1) else try s.binds.ensureTotalCapacity(it.g, node.kids[0].kids.len);
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
        if (eql(u8, name, "upper") or eql(u8, name, "lower")) return try corelib.caseMapped(it, s, name[0] == 'u');
        if (eql(u8, name, "bytes")) return try bytesfn.newBytes(it, s);
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

/// `new Class(args)`.
pub fn constructClass(it: *Interp, cls: *Class, arg_nodes: []const *const Node) Signal!Value {
    // a class derived from `Memory` is a columnar table (D-184)
    if (cls.node != null) if (try db.memory.memoryNew(it.host(), cls)) |v| return v;
    const obj = try it.newObject();
    if (cls.node == null) {
        // @eve-impl `Error(code, message)` and `DivideError(message: "text")`: an error object to raise (errors.md#error-classes)
        // @spec spec/semantics/errors.md#error-classes
        // @test c62_error_construct
        if (interp.errclasses.codeOf(cls)) |class_code| {
            const given = try it.evalArgs(arg_nodes);
            defer it.dropArgs(given);
            var code: i64 = class_code;
            var message: []const u8 = cls.name;
            var positional: usize = 0;
            for (given) |a| {
                if (a.name.len == 0) {
                    // `Error(9, "text")`: the code first (a class with a code of its own takes only the message)
                    if (interp.errclasses.isBase(cls) and positional == 0 and Interp.isInt(a.value)) {
                        code = Interp.intOf(a.value);
                    } else if (a.value == .str) {
                        message = a.value.str;
                    } else return it.failWith(err_argument, "{s}: the arguments are the code (Error only) and the message", .{cls.name});
                    positional += 1;
                } else if (std.mem.eql(u8, a.name, "code") and Interp.isInt(a.value)) {
                    code = Interp.intOf(a.value);
                } else if (std.mem.eql(u8, a.name, "message") and a.value == .str) {
                    message = a.value.str;
                } else try it.setField(obj, a.name, a.value);
            }
            try it.setField(obj, "code", .{ .int = code });
            try it.setField(obj, "message", try it.newStr(message));
            obj.class = cls;
        }
        return .{ .object = obj };
    }
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
        // a member written with a value, `{code: 1001, ...}`, starts with it
        if (m.kids.len > 0 and m.kids[0].tag != .none) v = try it.eval(m.kids[0]);
        for (args) |a| if (std.mem.eql(u8, a.name, m.text)) {
            v = a.value;
        };
        if (pos < args.len and args[pos].name.len == 0 and v == .nil) v = args[pos].value;
        if (args.len > pos and args[pos].name.len == 0) pos += 1;
        try it.setField(obj, m.text, v);
    }
    obj.class = cls;
    if (isErrorClass(cls)) try errorFields(it, obj, cls, args);
    return .{ .object = obj };
}

/// Does the class derive from `Error`?
fn isErrorClass(cls: *Class) bool {
    var cur: ?*Class = cls.parent;
    while (cur) |k| : (cur = k.parent) if (interp.errclasses.isBase(k)) return true;
    return false;
}

// @eve-impl an object of a class below `Error` has the fields code and message of an error: the code of the class (its own member or the one of a parent of the program), the message from the argument `message:`
// @spec spec/semantics/errors.md#errors-of-a-program
// @test c71_error_class_code
fn errorFields(it: *Interp, obj: *interp.Object, cls: *Class, args: []const Arg) Signal!void {
    if (Interp.fieldOf(obj, "code") == null) {
        var code: i64 = 4;
        var cur: ?*Class = cls;
        find: while (cur) |k| : (cur = k.parent) {
            if (k.node) |nd| for (nd.kids[0].kids) |m| if (std.mem.eql(u8, m.text, "code") and m.kids.len > 0 and m.kids[0].tag != .none) {
                code = Interp.intOf(try it.eval(m.kids[0]));
                break :find;
            };
        }
        try it.setField(obj, "code", .{ .int = code });
    }
    if (Interp.fieldOf(obj, "message") == null) {
        var message: []const u8 = "";
        for (args) |a| if (std.mem.eql(u8, a.name, "message") and a.value == .str) {
            message = a.value.str;
        };
        try it.setField(obj, "message", try it.newStr(message));
    }
}

// @eve-impl run the destructor of `cls` on `obj` (CLS-14, D-202); an error in it is dropped and the free goes on
// @spec spec/syntax/declarations.md#classes-and-objects
// @test c41_destructor
pub fn runDestructor(it: *Interp, obj: *interp.Object, cls: *Class) void {
    const d = cls.destructor() orelse return;
    const saved = it.enterScope(it.newScope(it.unit) catch return) catch return;
    defer it.leaveScope(saved);
    const self_var = it.h.make(Var, .{ .value = .nil }) catch return;
    it.bind("self", self_var) catch return;
    it.setVar(self_var, .{ .object = obj });
    it.execBlock(d.kids[3]) catch {};
}

/// The value a variable of a type has before it is assigned.
pub fn zero(it: *Interp, ty: ?*const Node) Signal!Value {
    const t = ty orelse return .nil;
    if (t.kids.len > 0) {
        // an array: the first dimension is built here, the others inside
        const dim = try it.eval(t.kids[0]);
        if (!Interp.isInt(dim)) return it.fail("an array size is an integer", .{});
        const inner: Node = .{ .tag = .type, .text = t.text, .kids = t.kids[1..], .tk = t.tk };
        const l = try it.h.make(List, .{ .array = true });
        var k: i64 = 0;
        while (k < Interp.intOf(dim)) : (k += 1) try it.listAppend(l, try it.zero(&inner));
        return .{ .list = l };
    }
    const eql = std.mem.eql;
    if (t.text.len > 0 and t.text[t.text.len - 1] == '?') return .nil; // an optional type starts as null
    if (std.mem.startsWith(u8, t.text, "()")) return .{ .list = try it.newList(&.{}, false) };
    if (std.mem.startsWith(u8, t.text, "[]")) return .{ .list = try it.newList(&.{}, true) };
    switch (t.tk) {
        .integer, .short, .byte => return .{ .int = 0 },
        .natural => return .{ .nat = 0 },
        .real, .float => return .{ .real = 0 },
        .logic => return .{ .bool = false },
        .decimal => return .{ .dec = .{ .scale = 0, .m = 0 } },
        .rational => return .{ .rat = interp.rational.fromInt(0) },
        .complex => return .{ .cpx = .{ .re = 0, .im = 0 } },
        .duration => return .{ .dur = 0 },
        .bytes => return bytesfn.newBytes(it, ""),
        .uuid => return .{ .uuid = @splat(0) },
        .date => return .{ .date = 0 },
        .zone => return .{ .zone = 0 },
        .datetime => return .{ .dtm = .{ .us = 0, .zone = 0 } },
        .time => return .{ .time = 0 },
        .instant => return .{ .instant = 0 },
        .string => return it.staticStr(""),
        .symbol, .rune => return .{ .sym = 0 },
        .dataset => return .{ .set = try it.newList(&.{}, false) },
        .datamap => return .{ .map = try it.newMap() },
        .other => return .nil,
        .none => {},
    }
    if (eql(u8, t.text, "Integer") or eql(u8, t.text, "Short") or eql(u8, t.text, "Byte")) return .{ .int = 0 };
    if (eql(u8, t.text, "Natural")) return .{ .nat = 0 };
    if (eql(u8, t.text, "Real") or eql(u8, t.text, "Float")) return .{ .real = 0 };
    if (eql(u8, t.text, "Logic")) return .{ .bool = false };
    if (eql(u8, t.text, "Decimal")) return .{ .dec = .{ .scale = 0, .m = 0 } };
    if (eql(u8, t.text, "Rational")) return .{ .rat = interp.rational.fromInt(0) };
    if (eql(u8, t.text, "Instant")) return .{ .instant = 0 };
    if (eql(u8, t.text, "String")) return it.staticStr("");
    if (eql(u8, t.text, "Symbol") or eql(u8, t.text, "Rune")) return .{ .sym = 0 };
    if (eql(u8, t.text, "DataSet")) return .{ .set = try it.newList(&.{}, false) };
    if (eql(u8, t.text, "DataMap")) return .{ .map = try it.newMap() };
    return .nil;
}

pub fn atomLen(pat: []const u8) usize {
    if (pat[0] == '\\' and pat.len > 1) return 2;
    if (pat[0] == '[') return (std.mem.indexOfScalar(u8, pat, ']') orelse pat.len - 1) + 1;
    return 1;
}

/// Does `text` match the pattern `/body/flags`? The engine is regexlib.zig; a text that is not a good pattern matches nothing.
// @spec spec/lexical/lexical.md#string
// @test a28_regex
pub fn regexMatch(spec: []const u8, txt: []const u8) bool {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const prog = regexlib.compileSpec(a, spec) catch return false;
    const found = regexlib.search(a, &prog, txt, 0) catch return false;
    return found != null;
}
