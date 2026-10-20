//! @eve-module interp.script
//! @spec spec/semantics/aspects.md, spec/semantics/modules.md#import
//! @feature F-LNG-01, F-STR-01, F-STR-02
//! @tests test/level2, test/level3
//! Running a script and its modules: `run`, the root aspect and its aspects, imports.
//! Part of the interpreter (interp.zig): every function takes the interpreter as `it: *Interp`, and
//! `Interp` names each of them again, so a call reads `it.name(...)` wherever it is made.
const std = @import("std");
const interp = @import("../interp.zig");
const db = @import("../db.zig");
const Interp = interp.Interp;
const ast = interp.ast;
const Heap = interp.Heap;
const Node = interp.Node;
const Signal = interp.Signal;
const Value = interp.Value;
const Module = interp.Module;
const Var = interp.Var;
const Arg = interp.Arg;

// ---- running a script -----------------------------------------------------------------

pub fn errorObject(it: *Interp) Signal!Value {
    const o = try it.newObject();
    const r = it.reports.items[it.reports.items.len - 1];
    try it.setField(o, "message", try it.newStr(r.message));
    try it.setField(o, "code", .{ .int = r.code });
    try it.setField(o, "job", try it.newStr(r.job));
    try it.setField(o, "line", .{ .int = r.line });
    if (r.errors) |list| {
        try it.setField(o, "errors", .{ .list = list });
        try it.setField(o, "cancelled", .{ .int = r.cancelled });
    }
    return .{ .object = o };
}

/// Run a process: its statements, then `recover` after an error, then `finalize`.
pub fn runProcess(it: *Interp, p: *const Node, args: []const Arg, kind: []const u8, unit_name: []const u8) Signal!void {
    const saved = try it.pushScope();
    defer it.leaveScope(saved);
    it.setProc(it.scope);
    try it.frames.append(it.a, .{ .kind = kind, .name = unit_name, .call_line = it.line });
    defer _ = it.frames.pop();
    const body = p.kids[0].kids;
    const recover = p.kids[1];
    const finalize = p.kids[2];
    // the arguments of the call, or of the command line, go to the parameters of the process
    try it.bindParams(p.kids[3].kids, args, null);
    // the state of the jobs: jobs["j1"].status is "none", "pass" or "fail"
    const jobs = try it.newMap();
    for (body) |st| if (st.tag == .job) {
        const rec = try it.newObject();
        try it.setField(rec, "status", try it.staticStr("none"));
        try it.mapPut(jobs, try it.staticStr(st.text), .{ .object = rec });
    };
    // a parameter named `jobs` (a channel, say) wins over the map of the job states
    if (!Interp.hasLocal(it.scope, "jobs")) try it.define("jobs", .{ .map = jobs }, false);
    var i: usize = 0;
    var failed: ?Signal = null;
    // the body of the process is a region: a safe point follows each statement
    it.regionIn();
    defer it.regionOut();
    while (i < body.len) : (it.safe()) {
        it.exec(body[i]) catch |e| switch (e) {
            error.Raise => {
                if (recover.tag == .none) {
                    failed = e;
                    break;
                }
                try it.define("$error", try it.errorObject(), false);
                const idx = it.reports.items.len - 1;
                it.execBlock(recover) catch |re| switch (re) {
                    error.Retry => continue,
                    error.Resume => {
                        it.reports.items[idx].handled = true;
                        i += 1;
                        continue;
                    },
                    error.Abort => {
                        failed = error.Raise; // the error goes on to the caller; finalize runs first
                        break;
                    },
                    error.Over, error.Exit => break,
                    error.Raise => {
                        failed = re; // an error raised in recover aborts with that error
                        break;
                    },
                    else => return re,
                };
                it.reports.items[idx].handled = true;
                break;
            },
            error.Over, error.Exit => break, // a clean way out: finalize still runs (D-081, D-111)
            else => return e,
        };
        i += 1;
    }
    it.collectAtDone(); // the end of a process is a `done` too: cycles made by its body are freed
    if (finalize.tag != .none) try it.execBlock(finalize);
    if (failed) |f| return f;
}

// ---- modules (spec/semantics/modules.md) ------------------------------------------------------

/// The exported member `name` of a module.
pub fn moduleMember(it: *Interp, m: *Module, name: []const u8) Signal!Value {
    var listed = false;
    for (m.node.kids) |k| {
        if (k.tag != .export_decl) continue;
        for (k.kids) |nm| if (std.mem.eql(u8, nm.text, name)) {
            listed = true;
        };
    }
    if (!listed) return it.fail("'{s}' is not exported by the module '{s}'", .{ name, m.name });
    const cell = m.scope.find(name) orelse return it.fail("the module '{s}' has no member '{s}'", .{ m.name, name });
    return cell.value;
}

/// Load a module once: its imports first, then its routines and variables, then `initialize`.
pub fn instantiate(it: *Interp, node: *const Node) Signal!*Module {
    const owner = it.base();
    if (owner.loaded.get(node)) |known| return known;
    const m = try it.a.create(Module);
    const s = try it.newScope(try it.preludeScope());
    s.hdr.pinned = true; // a module is loaded once and lives to the end of the run
    m.* = .{ .name = node.text, .node = node, .scope = s };
    try owner.loaded.put(it.a, node, m);
    const saved_unit = it.unit;
    const saved_proc = it.proc_scope;
    if (saved_proc) |p| Heap.retainScope(p);
    try it.scope_stack.append(it.g, saved_unit);
    const saved_scope = try it.enterScope(s);
    it.unit = s;
    defer {
        it.leaveScope(saved_scope);
        _ = it.scope_stack.pop();
        it.unit = saved_unit;
        it.setProc(saved_proc);
        if (saved_proc) |p| it.h.releaseScope(p);
    }
    try it.boot();
    for (node.kids) |d| if (d.tag == .import_decl) try it.execImport(d);
    for (node.kids) |d| {
        if (d.tag == .adopt or d.tag == .class or d.tag == .trait or d.tag == .function or d.tag == .procedure or d.tag == .method) try it.declareRoutine(d);
    }
    for (node.kids) |d| {
        if (d.tag == .var_decl or d.tag == .set) try it.exec(d);
    }
    var init_block: *const Node = it.noneNode();
    var recover_block: *const Node = it.noneNode();
    for (node.kids) |d| if (d.tag == .region) {
        if (std.mem.eql(u8, d.text, "initialize")) init_block = d.kids[0];
        if (std.mem.eql(u8, d.text, "recover")) recover_block = d.kids[0];
    };
    if (init_block.tag != .none) {
        // the region runs like a process without parameters: `recover` handles its errors
        const params = try it.a.create(Node);
        params.* = .{ .tag = .params };
        const proc = try it.a.create(Node);
        const kids = try it.a.dupe(*const Node, &.{ init_block, recover_block, it.noneNode(), params });
        proc.* = .{ .tag = .process, .line = node.line, .text = "initialize", .kids = kids };
        try it.runProcess(proc, &.{}, "module", node.text);
    }
    try owner.load_order.append(it.a, m);
    return m;
}

/// The shared node that stands for an absent part.
pub fn noneNode(it: *Interp) *const Node {
    _ = it;
    return &ast.none;
}

/// Bring the exported names of a module into the current scope, without a prefix (`m(*)` and `*`).
pub fn bindBare(it: *Interp, m: *Module) Signal!void {
    for (m.node.kids) |k| {
        if (k.tag != .export_decl) continue;
        for (k.kids) |nm| if (m.scope.find(nm.text)) |cell| try it.bind(nm.text, cell);
    }
}

// @decision D-131
/// Run an import declaration: load the modules and bind their names in the current scope.
pub fn execImport(it: *Interp, decl: *const Node) Signal!void {
    const known = it.modules orelse return it.fail("no module is loaded: '{s}'", .{decl.text});
    for (decl.kids) |item| {
        if (std.mem.eql(u8, item.text, "*")) {
            const key = try std.fmt.allocPrint(it.a, "{s}|*", .{decl.text});
            const set = known.get(key) orelse return it.failWith(30, "Module * not found in {s}", .{decl.text});
            for (set.kids) |mn| try it.bindBare(try it.instantiate(mn));
            continue;
        }
        const key = try std.fmt.allocPrint(it.a, "{s}|{s}", .{ decl.text, item.text });
        const node = known.get(key) orelse return it.failWith(30, "Module {s} not found in {s}", .{ item.text, decl.text });
        const m = try it.instantiate(node);
        if (item.public) {
            try it.bindBare(m);
        } else {
            const bound = if (item.kids[0].tag == .name) item.kids[0].text else item.text;
            try it.define(bound, .{ .module = m }, true);
        }
    }
}

// @decision D-068
/// Run the `finalize` region of every loaded module, last loaded first.
pub fn finalizeModules(it: *Interp) void {
    var i = it.load_order.items.len;
    while (i > 0) {
        i -= 1;
        const m = it.load_order.items[i];
        for (m.node.kids) |d| {
            if (d.tag != .region or !std.mem.eql(u8, d.text, "finalize")) continue;
            const saved = it.enterScope(m.scope) catch return;
            defer it.leaveScope(saved);
            it.execBlock(d.kids[0]) catch {};
        }
    }
}

// @decision D-066
/// `apply name(args);`: run the `main` of an aspect, read and checked before the run.
pub fn applyAspect(it: *Interp, n: *const Node) Signal!void {
    if (n.sel) |prc| return it.applyPrivate(n, prc);
    const known = it.aspects orelse return it.fail("no aspect is loaded: '{s}'", .{n.text});
    const aspect = known.get(n.text) orelse return it.fail("aspect '{s}' is not loaded", .{n.text});
    const args = try it.evalArgs(n.kids);
    defer it.dropArgs(args);
    defer it.writeBack(args);
    try it.runAspect(aspect, args);
}

// @decision D-179
/// `apply name(args);` where `name` is a private process of the aspect that contains the call.
pub fn applyPrivate(it: *Interp, n: *const Node, prc: *const Node) Signal!void {
    const args = try it.evalArgs(n.kids);
    defer it.dropArgs(args);
    defer it.writeBack(args);
    try it.runPrivate(prc, args, it.unit);
}

// @decision D-048
/// Run the private process `prc` in the state `unit` of its aspect.
pub fn runPrivate(it: *Interp, prc: *const Node, args: []const Arg, unit: *interp.Scope) Signal!void {
    const saved_unit = it.unit;
    it.unit = unit;
    defer it.unit = saved_unit;
    const saved = try it.enterScope(unit);
    defer it.leaveScope(saved);
    try it.runProcess(prc, args, "aspect", prc.text);
}

/// Run the `main` of an aspect with evaluated arguments, in a fresh scope (D-066).
pub fn runAspect(it: *Interp, aspect: *const Node, args: []const Arg) Signal!void {
    const saved_unit = it.unit;
    const saved_proc = it.proc_scope;
    if (saved_proc) |p| Heap.retainScope(p);
    try it.scope_stack.append(it.g, saved_unit);
    // an aspect of a macro sees the shared declarations, which are those of the root aspect (D-152)
    const parent = if (aspect.macro) it.base().global else try it.preludeScope();
    const saved_scope = try it.enterScope(try it.newScope(parent));
    it.unit = it.scope;
    defer {
        it.leaveScope(saved_scope);
        _ = it.scope_stack.pop();
        it.unit = saved_unit;
        it.setProc(saved_proc);
        if (saved_proc) |p| it.h.releaseScope(p);
    }
    try it.boot();
    for (aspect.kids) |d| if (d.tag == .import_decl) try it.execImport(d);
    for (aspect.kids) |d| {
        if (d.tag == .adopt or d.tag == .class or d.tag == .trait or d.tag == .function or d.tag == .procedure or d.tag == .method or d.tag == .generator) try it.declareRoutine(d);
    }
    for (aspect.kids) |d| if (d.tag == .table_decl) {
        try db.declareTables(it.host(), aspect.kids);
        break;
    };
    for (aspect.kids) |d| {
        if (d.tag == .var_decl or d.tag == .set) try it.exec(d);
    }
    const main = Interp.findProcess(aspect, "main") orelse return it.fail("the aspect '{s}' has no process main", .{aspect.text});
    try it.runProcess(main, args, "aspect", aspect.text);
}
