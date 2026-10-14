//! Running a script and its modules: `run`, the root aspect and its aspects, imports.
//! Part of the interpreter (interp.zig): every function takes the interpreter as `it: *Interp`, and
//! `Interp` names each of them again, so a call reads `it.name(...)` wherever it is made.
const std = @import("std");
// Zig tip: interp.zig imports this file and this file imports interp.zig back. Zig allows such a cycle
// between files of one module: declarations are resolved lazily, when they are used, not in the order
// of the imports. `../` names the parent folder; a module may import any file below its root folder.
const interp = @import("../interp.zig");
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

// Zig tip: `errorObject` relies on the same Zig feature as `define` above: see the tip there.
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

// Zig tip: `catch |e| switch (e) { ... }` handles each error name differently: `Raise` goes to
// `recover`, `Over` ends the process quietly, anything else is passed up with `return e`.
// `continue` inside the `catch` block restarts the loop without advancing `i`: that is how `retry`
// runs the same statement again, and `resume` (which adds one to `i`) skips it.
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

// Zig tip: a member of a module is read through the module's own scope: `find` walks the scope and
// answers a pointer to the variable, or null. Only the names in an `export` list are public; the link
// step already refused a private name written in the source, this check guards the rest.
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

// Zig tip: `std.AutoHashMapUnmanaged(*const Node, *Module)` is a map whose key is a pointer: two
// imports of the same module give the same tree, so the second finds the first. The module is put in
// the map before its code runs, so a module that imports itself, directly or through others, finds
// the module that is being loaded and does not load it again. `defer` restores the scope and the
// other fields on every way out, as `applyAspect` does.
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
        if (d.tag == .class or d.tag == .trait or d.tag == .function or d.tag == .procedure or d.tag == .method) try it.declareRoutine(d);
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

// Zig tip: `_ = it;` says that a parameter is deliberately unused, so the compiler does not complain. The
// method keeps the same call style as the others: `it.noneNode()`.
/// The shared node that stands for an absent part.
pub fn noneNode(it: *Interp) *const Node {
    _ = it;
    return &ast.none;
}

// Zig tip: bare names are shared, not copied: `bind` puts the same `Var` cell of the module under the
// name in the importing scope, so a constant or a function is one thing seen from two places.
/// Bring the exported names of a module into the current scope, without a prefix (`m(*)` and `*`).
pub fn bindBare(it: *Interp, m: *Module) Signal!void {
    for (m.node.kids) |k| {
        if (k.tag != .export_decl) continue;
        for (k.kids) |nm| if (m.scope.find(nm.text)) |cell| try it.bind(nm.text, cell);
    }
}

// Zig tip: the link step stored every module under `path|name`; the same key finds it here. A module
// that was not found is the run-time error `$err_module`, code 30 (D-131): `failWith` raises it with
// the message `Module {name} not found in {library}`; nobody can recover it before the process
// starts, so the program ends with exit code 4.
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

// Zig tip: `finalize` of the modules runs when the root aspect has ended, after its process, in the reverse
// order of the initialization (D-068): the loop counts down. An error in one `finalize` does not stop
// the others: `catch {}` drops it.
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

// Zig tip: `defer` runs when the function ends however it ends, so the three fields that this
// call changes (`scope`, `unit`, `proc_scope`) are restored on success, on `over`, and on an
// error that unwinds through (the same idea as in `invoke`). The aspect gets a scope of its own
// with no parent but the names every script knows (`boot`): it cannot see the root aspect's variables,
// and the state it builds is dropped with that scope when the call ends (D-066).
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

// Zig tip: a private process is not an aspect: it runs on the state of the aspect that declares it (D-179). That state
// is the scope `it.unit`, the one `runAspect` made for the call (or the global scope of the aspect that is run), so
// `enterScope(it.unit)` makes it the parent of the new process scope, and the process sees the aspect-level
// variables and not the locals of the process that called it. The link step stored the process in `n.sel`.
/// `apply name(args);` where `name` is a private process of the aspect that contains the call.
pub fn applyPrivate(it: *Interp, n: *const Node, prc: *const Node) Signal!void {
    const args = try it.evalArgs(n.kids);
    defer it.dropArgs(args);
    defer it.writeBack(args);
    try it.runPrivate(prc, args, it.unit);
}

// Zig tip: `runPrivate` is also the body of a started private process: the task's interpreter calls it with the scope of
// the aspect state it was started from, and with its own arguments (copied at `start`, D-048).
/// Run the private process `prc` in the state `unit` of its aspect.
pub fn runPrivate(it: *Interp, prc: *const Node, args: []const Arg, unit: *interp.Scope) Signal!void {
    const saved_unit = it.unit;
    it.unit = unit;
    defer it.unit = saved_unit;
    const saved = try it.enterScope(unit);
    defer it.leaveScope(saved);
    try it.runProcess(prc, args, "aspect", prc.text);
}

// Zig tip: `runAspect` relies on the same Zig feature as `applyAspect` above: see the tip there.
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
        if (d.tag == .class or d.tag == .trait or d.tag == .function or d.tag == .procedure or d.tag == .method or d.tag == .generator) try it.declareRoutine(d);
    }
    for (aspect.kids) |d| if (d.tag == .table_decl) {
        try it.dataApi().declare_tables(it.host(), aspect.kids);
        break;
    };
    for (aspect.kids) |d| {
        if (d.tag == .var_decl or d.tag == .set) try it.exec(d);
    }
    const main = Interp.findProcess(aspect, "main") orelse return it.fail("the aspect '{s}' has no process main", .{aspect.text});
    try it.runProcess(main, args, "aspect", aspect.text);
}
