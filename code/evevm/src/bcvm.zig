//! @eve-module bcvm
//! @spec design/design-bytecode.md#3-the-target
//! @feature F-VM-04
//! @decision D-201
//! @tests test/bytecode (`python script/bctest.py`), every level with `python script/runtest.py all --both`
//! The bytecode machine (stages B5.2 to B5.3b): runs the chunks made by `evecp.emit` on the services of the interpreter (heap,
//! output, `show`, `applyOp`, errors), so values, messages and exit codes are those of the tree walker. `process main` and every
//! routine that the emitter translates run here, whoever calls them (design-bytecode.md §16.2); a call between translated routines
//! does not recurse in Zig: it pushes a frame and the loop goes on.
const std = @import("std");
const evecm = @import("evecm");
const evecp = @import("evecp");
const interp = @import("interp.zig");
const cmdargs = @import("interp/cmdargs.zig");
const dlib = @import("dlib.zig");
const chunk = evecm.chunk;
const Inst = evecm.op.Inst;
const ast = evecm.ast;
const Interp = interp.Interp;
const Value = interp.Value;
const Signal = interp.Signal;
const Node = interp.Node;
const Scope = interp.value.Scope;

const Frame = struct {
    c: *const chunk.Chunk,
    func: u16,
    /// The next instruction, relative to the start of the function.
    pc: u32,
    /// The first register of the frame in the stack (an index: the stack moves when it grows).
    base: u32,
    /// The slot of the stack that receives the result.
    ret: u32,
    /// A call that is a statement: the result is let go.
    discard: bool = false,
    /// The scope that was current before the frame entered the scope of its routine (a routine compiled alone), or null.
    saved: ?*Scope = null,
};

/// True for the values that live outside the heap: a register that holds one can be overwritten without a count.
// @see code/evecm/src/heap.zig:hdrOf
// @invariant every tag listed has no heap header (`hdrOf` is null); the list of the plain tags compiles to a faster test than its complement
// @perf hot
inline fn heapless(v: Value) bool {
    return switch (v) {
        .nil, .bool, .int, .nat, .byte, .short, .huge, .real, .float, .dec, .rat, .cpx, .dur, .date, .time, .zone, .dtm, .instant, .sym, .uuid, .typ => true,
        else => false,
    };
}

// @eve-impl write a register: the new value is counted, the old one let go (the rule of `setVar` for a register)
// @invariant every register above the top of the stack holds a value without a heap object
// @perf hot
inline fn put(it: *Interp, slot: *Value, v: Value) void {
    if (heapless(slot.*) and heapless(v)) {
        slot.* = v;
    } else it.setCell(slot, v);
}

/// The registers of a frame.
// @invariant only the run that owns the current stack grows it (a nested run has a stack of its own), so the registers of a run
// move only at its own calls, where the loop takes them again
inline fn at(it: *Interp, base: u32) [*]Value {
    return it.bc_stack.ptr + base;
}

// @eve-impl a nested run of the machine (the tree walker calls a routine of the machine while a run waits) gets a stack of its own,
// taken from the spare ones: the stack of the waiting run never moves, so its loop keeps its register pointer without a check
// @spec design/design-bytecode.md#35-frames-and-the-stack
fn enterSegment(it: *Interp) Signal!void {
    try it.bc_waiting.append(it.g, .{ .stack = it.bc_stack, .top = it.bc_top });
    it.bc_stack = it.bc_spare.pop() orelse &.{};
    it.bc_top = 0;
}

/// Back to the stack of the waiting run; the stack of the nested run (all its registers null again) is kept for the next one.
fn leaveSegment(it: *Interp) void {
    const seg = it.bc_waiting.pop().?;
    if (it.bc_stack.len > 0) it.bc_spare.append(it.g, it.bc_stack) catch it.g.free(it.bc_stack);
    it.bc_stack = seg.stack;
    it.bc_top = seg.top;
}

/// Make room for `need` registers; the new ones are null. The stack moves: the registers are taken again after it.
fn grow(it: *Interp, need: usize) Signal!void {
    if (need <= it.bc_stack.len) return;
    var n = @max(it.bc_stack.len * 2, 1024);
    while (n < need) n *= 2;
    if (n > (1 << 22)) return it.fail("StackOverflow: the calls are nested too deeply", .{});
    const old = it.bc_stack;
    const fresh = try it.g.alloc(Value, n);
    @memcpy(fresh[0..old.len], old);
    @memset(fresh[old.len..], .nil);
    it.bc_stack = fresh;
    if (old.len > 0) it.g.free(old);
}

fn opText(o: evecm.op.Op) []const u8 {
    return switch (o) {
        .add => "+",
        .sub => "-",
        .mul => "*",
        .div => "/",
        .mod => "%",
        .eq => "==",
        .ne => "<>",
        .lt => "<",
        .le => "<=",
        .gt => ">",
        .ge => ">=",
        .pow => "^",
        else => "?",
    };
}

fn astOp(o: evecm.op.Op) ast.Op {
    return switch (o) {
        .add => .add,
        .sub => .sub,
        .mul => .mul,
        .div => .div,
        .mod => .mod,
        .eq => .eq,
        .ne => .ne,
        .lt => .lt,
        .le => .le,
        .gt => .gt,
        .ge => .ge,
        else => .other,
    };
}

/// Print why a program runs on the tree walker (`EVE_BC_TRACE=1`).
pub var trace: bool = false;

/// The names of the function values in `s` and the scopes above it, short of the prelude: the emitter makes a call of one a
/// `call` of kind `value` (its callee looked up by name), not a built-in.
fn knownFuncs(it: *Interp, s: ?*Scope) Signal![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var cur = s;
    while (cur) |sc| : (cur = sc.parent) {
        if (it.prelude) |p| if (sc == p) break;
        for (sc.binds.items) |b| if (b.v.value == .func) try out.append(it.a, b.name);
    }
    return out.items;
}

// @eve-impl run `process main` on the bytecode machine; false when the emitter can not translate it (the tree walker then runs it)
// @spec design/design-bytecode.md#9-stages
// @see code/evevm/src/interp/datatypes.zig:runRoot
/// The bytecode counterpart of `runProcess` for `main`: true when it ran, false when the program stays with the tree walker.
pub fn runMain(it: *Interp, root: *const Node, main: *const Node) Signal!bool {
    var diag: evecp.emit.Diag = .{};
    const cp = try it.a.create(chunk.Chunk);
    cp.* = evecp.emit.compile(it.a, root, try knownFuncs(it, it.scope), &diag) catch |e| switch (e) {
        error.Unsupported => {
            if (trace) std.debug.print("bytecode: the tree walker runs this program: {s} (line {d})\n", .{ diag.message, diag.line });
            return false;
        },
        error.OutOfMemory => return error.OutOfMemory,
    };
    const c: *const chunk.Chunk = cp;
    try registerAspect(it, root, c);
    const saved = try it.pushScope();
    defer it.leaveScope(saved);
    it.setProc(it.scope);
    try it.frames.append(it.a, .{ .kind = "aspect", .name = root.text, .call_line = it.line });
    defer _ = it.frames.pop();
    // the state of the jobs: jobs["j1"].status is "none", "pass" or "fail" (the jobs written in the body of `main`)
    const jobs = try it.newMap();
    for (root.kids) |k| if (k.tag == .process and std.mem.eql(u8, k.text, "main")) {
        for (k.kids[0].kids) |st| if (st.tag == .job) {
            const rec = try it.newObject();
            try it.setField(rec, "status", try it.staticStr("none"));
            try it.mapPut(jobs, try it.staticStr(st.text), .{ .object = rec });
        };
    };
    try it.define("jobs", .{ .map = jobs }, false);
    it.regionIn();
    defer it.regionOut();
    // @eve-impl the process `main` with `recover` and `finalize` (the loop of `runProcess` on the bytecode): an error leaves `run`,
    // `recover` runs on the tree walker with the variables copied in and out, `retry` and `resume` start again at a statement
    // @spec spec/semantics/errors.md#recover
    // @test test/bytecode/bc14_recover
    const frames_len = it.frames.items.len;
    const m = c.funcs[c.main];
    try grow(it, m.nregs);
    it.bc_top = m.nregs;
    // the arguments of the command line go to the parameters of `main`, as `runProcess` binds them
    if (main.kids[3].kids.len > 0) try bindArgs(it, main.kids[3].kids, try cmdargs.build(it, main), 0);
    var entry: u32 = 0;
    var failed: ?Signal = null;
    while (true) {
        _ = run(it, c, c.main, entry, 0) catch |e| {
            // the frames of the calls that the error left, and their registers, are gone
            it.frames.shrinkRetainingCapacity(frames_len);
            for (it.bc_stack[m.nregs..@max(it.bc_top, m.nregs)]) |*slot| put(it, slot, .nil);
            it.bc_top = m.nregs;
            switch (e) {
                error.Raise => {
                    if (c.recover == chunk.no_x) {
                        failed = e;
                        break;
                    }
                    var k: usize = 0;
                    const pc = it.bc_main_pc -| 1;
                    while (k + 2 < c.main_stmts.len and c.main_stmts[k + 1] <= pc) k += 1;
                    const idx = it.reports.items.len - 1;
                    runBlock(it, c, c.recover, true) catch |re| switch (re) {
                        error.Retry => {
                            entry = c.main_stmts[k];
                            continue;
                        },
                        error.Resume => {
                            it.reports.items[idx].handled = true;
                            entry = c.main_stmts[k + 1];
                            continue;
                        },
                        error.Abort => {
                            failed = error.Raise;
                            break;
                        },
                        error.Over, error.Exit => break,
                        error.Raise => {
                            failed = re;
                            break;
                        },
                        else => return re,
                    };
                    it.reports.items[idx].handled = true;
                    break;
                },
                error.Over, error.Exit => break,
                else => return e,
            }
        };
        break;
    }
    it.collectAtDone(); // the end of a process is a `done` too
    if (c.finalize != chunk.no_x) try runBlock(it, c, c.finalize, false);
    for (it.bc_stack[0..it.bc_top]) |*slot| put(it, slot, .nil);
    it.bc_top = 0;
    if (failed) |f| return f;
    return true;
}

/// The routines of the aspect that the chunk of `main` holds: a call of one from anywhere (the tree walker included) runs that code.
fn registerAspect(it: *Interp, root: *const Node, c: *const chunk.Chunk) Signal!void {
    const b = it.base();
    Interp.lockShared();
    defer Interp.unlockShared();
    for (root.kids) |k| {
        if (k.tag != .function and k.tag != .procedure) continue;
        for (c.funcs, 0..) |f, fi| if (fi != c.main and f.line == k.line and std.mem.eql(u8, f.name, k.text)) {
            try b.bc_routines.put(it.a, k, .{ .chunk = c, .func = @intCast(fi) });
        };
    }
}

// @eve-impl a `recover` or `finalize` block on the tree walker: the variables of the process are copied in, and copied back also when the block ends with `retry`, `resume` or an error
fn runBlock(it: *Interp, c: *const chunk.Chunk, xi: u16, with_error: bool) Signal!void {
    const x = c.xnodes[xi];
    const mark = it.scratch.mark();
    defer it.scratch.release(mark);
    const outer = try it.pushScope();
    defer it.leaveScope(outer);
    const scope = it.scope;
    for (x.names) |nm| try it.define(nm.name, it.bc_stack[nm.reg], false);
    if (with_error) try it.define("$error", try it.errorObject(), false);
    var result: Signal!void = {};
    it.execBlock(x.node) catch |e| {
        result = e;
    };
    for (x.names) |nm| if (scope.find(nm.name)) |cell| put(it, &it.bc_stack[nm.reg], cell.value);
    return result;
}

// @eve-impl the rare case of a fast instruction: the expression `xnode` runs on the tree walker and its value goes to register `dst`
fn evalSlow(it: *Interp, c: *const chunk.Chunk, base: u32, xi: u16, dst: u8) Signal!void {
    const x = c.xnodes[xi];
    const mark = it.scratch.mark();
    defer it.scratch.release(mark);
    const outer = try it.pushScope();
    defer it.leaveScope(outer);
    for (x.names) |nm| try it.define(nm.name, at(it, base)[nm.reg], false);
    const v = try it.eval(x.node);
    put(it, &at(it, base)[dst], v);
}

// @eve-impl the rare case of a fast instruction: the statement `xnode` runs on the tree walker, the variables it names are copied back
fn execSlow(it: *Interp, c: *const chunk.Chunk, base: u32, xi: u16) Signal!void {
    const x = c.xnodes[xi];
    const mark = it.scratch.mark();
    defer it.scratch.release(mark);
    const outer = try it.pushScope();
    defer it.leaveScope(outer);
    const scope = it.scope;
    for (x.names) |nm| try it.define(nm.name, at(it, base)[nm.reg], false);
    try it.exec(x.node);
    for (x.names) |nm| if (scope.find(nm.name)) |cell| put(it, &at(it, base)[nm.reg], cell.value);
}

/// A hidden name of a call site (`$1`, `$2`, ...): the value is in the register of the argument; any other argument node is a
/// literal or a name outside the registers, which the site keeps as it is (`selfEvident` of the emitter).
inline fn isHidden(n: *const Node) bool {
    return n.tag == .name and n.text.len > 1 and n.text[0] == '$' and n.text[1] >= '0' and n.text[1] <= '9';
}

/// A function value that the tree walker would call without a choice among overloads.
fn plainFunc(it: *Interp, v: Value) ?*interp.Func {
    if (v != .func) return null;
    const b = it.base();
    if (b.overloads.count() != 0) {
        Interp.lockShared();
        defer Interp.unlockShared();
        if (b.overloads.get(v.func.node) != null) return null;
    }
    return v.func;
}

/// Can the routine of `f` run on the machine at all: a function or a procedure with a body, called without a receiver; an `async`
/// routine runs as a task and a `sql function` is called by the database from its own threads, so both stay with the tree walker.
fn eligible(f: *interp.Func) bool {
    const n = f.node;
    return (n.tag == .function or n.tag == .procedure or n.tag == .method) and n.kids[3].tag != .none and !n.is_external and !n.is_async and !n.is_sql and n.kids.len <= 4;
}

/// A routine whose first parameter is `@self`: it runs only with a receiver, which is the variable `self` of its scope.
fn hasSelf(n: *const Node) bool {
    const ps = n.kids[0].kids;
    return ps.len > 0 and ps[0].tag == .ref_param and std.mem.eql(u8, ps[0].text, "self");
}

// @eve-impl the compiled code of a routine: found in the table of the root interpreter, or compiled at its first call; null when the
// emitter refuses it (the tree walker runs it, and the refusal is kept so it is not tried again)
// @spec design/design-bytecode.md#162-the-pivot-the-unit-of-the-bridge-is-the-routine-not-the-expression
// @test test/bytecode/bc24_routines
fn routineFor(it: *Interp, f: *interp.Func) Signal!?interp.BcRoutine {
    if (!eligible(f)) return null;
    const b = it.base();
    Interp.lockShared();
    defer Interp.unlockShared();
    if (b.bc_routines.get(f.node)) |r| return if (r.chunk != null) r else null;
    var diag: evecp.emit.Diag = .{};
    var entry: interp.BcRoutine = .{ .chunk = null };
    if (evecp.emit.compileRoutine(b.a, f.node, try knownFuncs(b, f.closure), &diag)) |c| {
        const cp = try b.a.create(chunk.Chunk);
        cp.* = c;
        entry = .{ .chunk = cp, .func = 0 };
        if (trace) std.debug.print("bytecode: compiled {s} {s}\n", .{ @tagName(f.node.tag), f.node.text });
    } else |e| switch (e) {
        error.Unsupported => if (trace) std.debug.print("bytecode: the tree walker runs {s} {s}: {s} (line {d})\n", .{ @tagName(f.node.tag), f.node.text, diag.message, diag.line }),
        error.OutOfMemory => return error.OutOfMemory,
    }
    try b.bc_routines.put(b.a, f.node, entry);
    return if (entry.chunk != null) entry else null;
}

// @eve-impl the parameters of a routine on the machine from the arguments of a call, by the rule of `bindParams`: a named argument
// first, then the next positional one, else the zero value of the type; an argument left over is an error
// @see code/evevm/src/interp/calls.zig:bindParams
fn bindArgs(it: *Interp, params: []const *const Node, args: []const interp.Arg, win: u32) Signal!void {
    var taken: [32]bool = @splat(false);
    if (args.len > taken.len) return it.fail("too many arguments", .{});
    var pos: usize = 0;
    for (params, 0..) |prm, k| {
        if (prm.tag == .vararg_param) {
            // the positional arguments that are left, as a list
            const rest = try it.newList(&.{}, false);
            while (pos < args.len) : (pos += 1) {
                if (taken[pos] or args[pos].name.len > 0) continue;
                taken[pos] = true;
                try it.listAppend(rest, args[pos].value);
            }
            put(it, &at(it, win)[k], .{ .list = rest });
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
        const v = if (found) |i| blk: {
            taken[i] = true;
            break :blk args[i].value;
        } else if (prm.kids[0].tag != .none) try it.eval(prm.kids[0]) else try it.zero(prm.ty);
        put(it, &at(it, win)[k], v);
    }
    for (args, 0..) |a, i| {
        if (!taken[i]) return it.fail("unexpected argument{s}{s}", .{ if (a.name.len > 0) " " else "", a.name });
    }
}

// @eve-impl a call of the tree walker (`invokeWith`) of a routine that the machine runs: the routine runs in a new window above the top
// of the stack, in a new scope below its closure, as `runRoutine` would; null when the routine stays with the tree walker
// @spec design/design-bytecode.md#162-the-pivot-the-unit-of-the-bridge-is-the-routine-not-the-expression
// @see code/evevm/src/interp/calls.zig:invokeWith
pub fn runRoutine(it: *Interp, f: *interp.Func, recv: ?Value, args: []const interp.Arg) Signal!?Value {
    if (hasSelf(f.node) != (recv != null)) return null;
    const entry = (try routineFor(it, f)) orelse return null;
    const c = entry.chunk.?;
    const callee = c.funcs[entry.func];
    const s = try it.newScope(f.closure);
    const saved = try it.enterScope(s);
    defer it.leaveScope(saved);
    // the receiver is also the variable `self` of the scope (lambdas, the tree walker), as `runRoutine` of the tree walker binds it
    if (recv) |r| {
        const self_var = try it.h.make(interp.Var, .{ .value = r });
        interp.Heap.retain(r);
        try it.bind("self", self_var);
    }
    try it.frames.append(it.a, .{ .kind = callee.kind, .name = callee.name, .call_line = it.line, .file = callee.file });
    defer _ = it.frames.pop();
    try enterSegment(it);
    defer leaveSegment(it);
    const base: u32 = @intCast(it.bc_top);
    try grow(it, base + callee.nregs);
    it.bc_top = base + callee.nregs;
    errdefer {
        for (it.bc_stack[base..@max(it.bc_top, base)]) |*slot| put(it, slot, .nil);
        it.bc_top = base;
    }
    const params = f.node.kids[0].kids;
    if (recv) |r| put(it, &at(it, base)[0], r);
    try bindArgs(it, if (recv != null) params[1..] else params, args, if (recv != null) base + 1 else base);
    // the body of the routine is a region, as `execBlock` makes it in the tree walker: the safe points of its loops free only what it
    // made, never the temporaries of the expression of the tree walker that called it
    it.regionIn();
    defer it.regionOut();
    return try run(it, c, entry.func, 0, base);
}

// @eve-impl the elements of a map, a set, a string or a table listed once: the pairs of a map are made here and live through every pass
fn snapshot(it: *Interp, slot: *Value) Signal!void {
    const items = try it.iterate(slot.*);
    const snap = try it.h.make(interp.List, .{});
    for (items) |e| try it.listAppend(snap, e);
    put(it, slot, .{ .list = snap });
}

// @eve-impl `new a, b := v;` `new (a, b) = v;` `new p, *, r := v;`: the parts of the value go to the registers, by the rule of `declareStatement`
// @see code/evevm/src/interp/stmt.zig:declareStatement
fn unpack(it: *Interp, regs: [*]Value, i: Inst, form: u16) Signal!void {
    const v = regs[i.a];
    const count: usize = i.c;
    const out = regs + i.b;
    if (form & 1 == 1) {
        const elementwise = v == .list and v.list.elems().len == count;
        for (0..count) |k| put(it, &out[k], if (elementwise) v.list.elems()[k] else v);
        return;
    }
    const items = try it.iterate(v);
    const star: ?usize = if (form >> 1 > 0) (form >> 1) - 1 else null;
    const after = if (star) |s| count - s - 1 else 0;
    if (items.len < count - @intFromBool(star != null)) return it.fail("not enough elements to deconstruct", .{});
    for (0..count) |k| {
        if (star != null and k == star.?) {
            put(it, &out[k], .{ .list = try it.newList(items[k .. items.len - after], false) });
        } else if (star != null and k > star.?) {
            put(it, &out[k], items[items.len - (count - k)]);
        } else put(it, &out[k], items[k]);
    }
}

// @eve-impl the next element of a loop over a range value, a channel, a generator or a stream, into the variable A+2; false at the end
// @see code/evevm/src/interp/stmt.zig:forStmt
fn iterPull(it: *Interp, regs: [*]Value, a: u8) Signal!bool {
    switch (regs[a]) {
        .range => |r| {
            const k = regs[a + 1].int;
            if (k > r.hi) return false;
            put(it, &regs[a + 2], if (r.sym) .{ .sym = @intCast(k) } else .{ .int = k });
            regs[a + 1] = .{ .int = k + r.step };
            return true;
        },
        .chan => |ch| {
            const x = (try it.receive(ch)) orelse return false;
            put(it, &regs[a + 2], x);
            return true;
        },
        .object => |o| {
            if (o.class != null and o.class == it.base().gen_class) {
                const gs = it.genOf(o);
                if (!try it.genNext(gs)) return false;
                put(it, &regs[a + 2], gs.value);
                return true;
            }
            const unit = (try dlib.streamNext(it, dlib.streamOf(it, o))) orelse return false;
            put(it, &regs[a + 2], unit);
            return true;
        },
        else => unreachable,
    }
}

/// What a `call` site calls, found once: the receiver (or the callee) and the value to call (a member of a module receiver).
const Target = struct { recv: Value, target: Value };

fn resolveTarget(it: *Interp, site: chunk.XNode, regs: [*]Value, a: u8, kind: evecm.op.CallKind, named: bool) Signal!Target {
    if (kind == .builtin or kind == .apply) return .{ .recv = .nil, .target = .nil };
    const callee = site.node.kids[0];
    const recv: Value = if (!named) regs[a] else if (kind == .method) try it.lookup(callee.kids[0].text) else try it.lookup(callee.text);
    var target = recv;
    if (kind == .method and target == .module) target = try it.moduleMember(target.module, callee.text);
    return .{ .recv = recv, .target = target };
}

/// The routine of a target that the machine runs (a plain function value, eligible), or null.
fn directFunc(it: *Interp, kind: evecm.op.CallKind, t: Target) ?*interp.Func {
    if (kind == .builtin or kind == .apply or (kind == .method and t.recv != .module)) return null;
    const f = plainFunc(it, t.target) orelse return null;
    return if (eligible(f) and !hasSelf(f.node)) f else null;
}

/// The arguments of a call site as values: a hidden name is its register, a literal or an outside name is evaluated now.
fn siteArgs(it: *Interp, site: chunk.XNode, base: u32, a: u8) Signal![]interp.Arg {
    const kids = site.node.kids[1..];
    const args = try it.t.alloc(interp.Arg, kids.len);
    for (args, kids, 1..) |*arg, an, k| {
        const vn = if (an.tag == .pair) an.kids[1] else an;
        const v = if (isHidden(vn)) at(it, base)[a + k] else try it.eval(vn);
        arg.* = .{ .name = if (an.tag == .pair) an.kids[0].text else "", .value = v };
    }
    return args;
}

/// The cell of an output of a task already started in the block for the variable at stack slot `slot`.
fn outCell(it: *Interp, slot: usize) ?*interp.Var {
    const outs = it.bc_outs orelse return null;
    for (outs.items) |o| if (o.slot == slot) return o.cell;
    return null;
}

/// After a `start` or a `spawn`: the cells of its `@x` arguments are kept until `done`, which writes the outputs of the tasks into them.
fn noteOuts(it: *Interp, site: chunk.XNode, base: u32) Signal!void {
    const outs = it.bc_outs orelse return;
    for (site.names) |nm| if (nm.back != chunk.no_back) {
        if (outCell(it, base + nm.back) != null) continue;
        const cell = it.scope.find(nm.name) orelse continue;
        interp.Heap.retainVar(cell);
        try outs.append(it.g, .{ .cell = cell, .slot = base + nm.back });
    };
}

// @eve-impl the `call` instruction: a plain function value (a parameter, a module member) is called with the values of the
// registers; every other callee goes to the tree walker as the call node of the site, its values bound to hidden names
// @spec design/design-bytecode.md#163-calls-the-call-instruction
// @test test/bytecode/bc23_calls
// @perf hot
noinline fn callSite(it: *Interp, site: chunk.XNode, base: u32, a: u8, kind: evecm.op.CallKind, stmt: bool, has_ref: bool, tbits: u8, t: Target) Signal!void {
    const node = site.node;
    const callee = if (kind == .apply) node else node.kids[0];
    const recv = t.recv;
    const target = t.target;
    if (kind != .builtin and kind != .apply and !has_ref) if (plainFunc(it, target)) |f| {
        const mark = it.scratch.mark();
        defer it.scratch.release(mark);
        const args = try siteArgs(it, site, base, a);
        it.written_types = false;
        const v = try it.invokeWith(f, null, args);
        put(it, &at(it, base)[a], v);
        return;
    };
    // the adapter: the values are bound to the hidden names of the site, the native reads the argument nodes
    const mark = it.scratch.mark();
    defer it.scratch.release(mark);
    const outer = try it.pushScope();
    defer it.leaveScope(outer);
    for (site.names) |nm| {
        const cur = at(it, base)[nm.reg];
        // an output of a task: the cell of the variable stays the same for every task of the block (one owner each, D-140)
        if (tbits != 0 and nm.back != chunk.no_back) if (outCell(it, base + nm.back)) |cell| {
            it.setVar(cell, cur);
            try it.bind(nm.name, cell);
            continue;
        };
        try it.define(nm.name, cur, false);
    }
    // an `@x` argument: the cell of the hidden name is what the callee changes; its final value goes back to the variable, also when
    // the call fails (as `writeBack` does in the tree walker)
    defer if (has_ref and tbits == 0) for (site.names) |nm| if (nm.back != chunk.no_back) {
        if (it.scope.find(nm.name)) |cell| put(it, &at(it, base)[nm.back], cell.value);
    };
    const arg_nodes = if (kind == .apply) node.kids else node.kids[1..];
    const v = switch (kind) {
        .apply => {
            it.stmt_call = false;
            if (tbits & evecm.op.call_start != 0) {
                try it.startAspect(node);
            } else if (tbits & evecm.op.call_spawn != 0) {
                try it.spawnTask(node);
            } else return try it.applyAspect(node);
            try noteOuts(it, site, base);
            return;
        },
        .builtin => blk: {
            it.stmt_call = stmt;
            defer it.stmt_call = false;
            break :blk try it.eval(node);
        },
        .value => blk: {
            it.written_types = false;
            break :blk try it.callValue(target, null, arg_nodes);
        },
        .method => blk: {
            it.written_types = false;
            if (recv == .module) break :blk try it.callValue(target, null, arg_nodes);
            it.type_args = callee.kids[1..];
            it.call_is_stmt = stmt;
            break :blk try it.callMethod(target, callee.text, arg_nodes);
        },
    };
    put(it, &at(it, base)[a], v);
}

// @eve-impl `storeg`: the assignment of a name outside the registers, the steps of `assign` of the tree walker with the value given
// @see code/evevm/src/interp/stmt.zig:assign
noinline fn storeGlobal(it: *Interp, n: *const Node, value: Value) Signal!void {
    const target = n.kids[0];
    if (n.op != .set and n.op != .copy) {
        if (it.scope.find(target.text)) |cell| if (cell.atomic) {
            if (cell.constant) return it.fail("'{s}' is a constant", .{target.text});
            interp.value.atomic_lock.lock();
            defer interp.value.atomic_lock.unlock();
            const nv = (try it.augmentValue(n.op, n.text[0..1], cell.value, value)) orelse return;
            cell.value = nv;
            return;
        };
    }
    var v = value;
    if (n.op == .copy) {
        v = try it.clone(v);
    } else if (n.op != .set) {
        const cur = try it.lookup(target.text);
        v = (try it.augmentValue(n.op, n.text[0..1], cur, v)) orelse return;
    }
    if (n.op == .set) {
        if (it.scope.find(target.text)) |cell| v = Interp.coerceLike(cell.value, v);
    }
    try it.assignTo(target, v);
}

/// A frame pushed by a `call` of a routine that the machine runs.
const Pushed = struct { c: *const chunk.Chunk, func: u16 };

// @eve-impl a call of a routine that the machine runs pushes a frame: the arguments go to a new window above the top, the routine gets
// a scope below its closure and a region, its result goes to register A of the caller; null when the target is not such a routine
// @spec design/design-bytecode.md#162-the-pivot-the-unit-of-the-bridge-is-the-routine-not-the-expression
// @test test/bytecode/bc24_routines
noinline fn pushCall(it: *Interp, frames: *std.ArrayList(Frame), site: chunk.XNode, base: u32, i: Inst, kind: evecm.op.CallKind, stmt: bool, tgt: Target) Signal!?Pushed {
    const f = directFunc(it, kind, tgt) orelse return null;
    const target = (try routineFor(it, f)) orelse return null;
    const rc = target.chunk.?;
    const callee = rc.funcs[target.func];
    const mark = it.scratch.mark();
    defer it.scratch.release(mark);
    const args = try siteArgs(it, site, base, i.a);
    const nb: u32 = @intCast(it.bc_top);
    try grow(it, nb + callee.nregs);
    it.bc_top = nb + callee.nregs;
    bindArgs(it, f.node.kids[0].kids, args, nb) catch |e| {
        for (it.bc_stack[nb .. nb + callee.nregs]) |*slot| put(it, slot, .nil);
        it.bc_top = nb;
        return e;
    };
    var k: usize = 1;
    while (k <= i.b) : (k += 1) put(it, &at(it, base)[i.a + k], .nil);
    const s = try it.newScope(f.closure);
    const saved = try it.enterScope(s);
    try it.frames.append(it.a, .{ .kind = callee.kind, .name = callee.name, .call_line = it.line, .file = callee.file });
    try frames.append(it.g, .{ .c = rc, .func = target.func, .pc = 0, .base = nb, .ret = base + i.a, .discard = stmt, .saved = saved });
    it.regionIn();
    return .{ .c = rc, .func = target.func };
}

/// After `done`: the values the tasks wrote go to the registers of the variables; the cells are let go.
fn copyOuts(it: *Interp) void {
    const outs = it.bc_outs orelse return;
    for (outs.items) |o| {
        put(it, &it.bc_stack[o.slot], o.cell.value);
        it.h.releaseVar(o.cell);
    }
    outs.clearRetainingCapacity();
}

/// What a `job` or `parallel` block keeps while it runs.
const Block = union(enum) { job: interp.Interp.JobState, par: interp.Interp.ParState };

/// An open `job` or `parallel` block of a run: the frame it belongs to, where its end is, the error that ended it early.
const Handler = struct {
    depth: usize,
    /// The pc of the `jobclose` or `parclose`, relative to the start of the function of the frame.
    pc: u32,
    err: ?Signal = null,
    block: Block,
    /// The outputs of the tasks started in the block, and the list that was current before.
    outs: std.ArrayList(interp.Interp.Out) = .empty,
    saved_outs: ?*std.ArrayList(interp.Interp.Out) = null,
};

const RunState = struct {
    frames: std.ArrayList(Frame) = .empty,
    handlers: std.ArrayList(*Handler) = .empty,
    trace_len: usize = 0,
};

// @eve-impl an error in a `job` or `parallel` block: the frames above the block go, the block's own frame goes on at its end
// instruction (`jobclose`, `parclose`) with the error kept; false when no block of this run is open
fn catchBlock(it: *Interp, st: *RunState, e: Signal) Signal!bool {
    if (st.handlers.items.len == 0) return false;
    const h = st.handlers.items[st.handlers.items.len - 1];
    if (h.err != null) return false;
    // the frames above the one of the block: their regions, scopes, registers and trace entries
    var k = st.frames.items.len;
    while (k > h.depth) : (k -= 1) {
        const f = st.frames.items[k - 1];
        it.regionOut();
        if (f.saved) |s| it.leaveScope(s);
        _ = it.frames.pop();
    }
    st.frames.shrinkRetainingCapacity(h.depth);
    const top = &st.frames.items[h.depth - 1];
    const top_end = top.base + top.c.funcs[top.func].nregs;
    for (it.bc_stack[top_end..@max(it.bc_top, top_end)]) |*slot| put(it, slot, .nil);
    it.bc_top = top_end;
    h.err = e;
    top.pc = h.pc;
    return true;
}

/// Let go of the frames above the bottom one when an error leaves the loop: their scopes, their registers, their trace entries.
fn unwind(it: *Interp, frames: []const Frame, trace_len: usize) void {
    var k = frames.len;
    while (k > 1) : (k -= 1) {
        const f = frames[k - 1];
        it.regionOut();
        if (f.saved) |s| it.leaveScope(s);
    }
    const bottom = frames[0];
    const top_of_bottom = bottom.base + bottom.c.funcs[bottom.func].nregs;
    for (it.bc_stack[top_of_bottom..@max(it.bc_top, top_of_bottom)]) |*slot| put(it, slot, .nil);
    it.bc_top = top_of_bottom;
    it.frames.shrinkRetainingCapacity(trace_len);
}

// @eve-impl the loop of the machine: fetch, decode, do; a call of a translated routine pushes a frame, `ret` pops it; the bottom frame
// is function `fi` of `c0` with its window at `base0` (its parameters already there); its result is the value of the run
// @perf hot
fn run(it: *Interp, c0: *const chunk.Chunk, fi: u16, entry: u32, base0: u32) Signal!Value {
    var st: RunState = .{};
    defer st.frames.deinit(it.g);
    defer st.handlers.deinit(it.g);
    try st.frames.append(it.g, .{ .c = c0, .func = fi, .pc = entry, .base = base0, .ret = base0 });
    st.trace_len = it.frames.items.len;
    while (true) {
        return execute(it, &st) catch |e| {
            if (try catchBlock(it, &st, e)) continue;
            // the pc of the main frame when an error leaves: the statement that failed (`recover`, `retry`, `resume`)
            it.bc_main_pc = st.frames.items[0].pc;
            unwind(it, st.frames.items, st.trace_len);
            return e;
        };
    }
}

// @eve-impl the instructions from the top frame of `st` until the run ends or an error leaves; `run` calls it again after an error
// that a `job` or `parallel` block of the run handles
// @perf hot
fn execute(it: *Interp, st: *RunState) Signal!Value {
    const frames = &st.frames;
    var fr: *Frame = &frames.items[frames.items.len - 1];
    var c = fr.c;
    var func = c.funcs[fr.func];
    var regs: [*]Value = at(it, fr.base);
    while (true) {
        const pc = func.start + fr.pc;
        const i = Inst.fromWord(c.code[pc]);
        fr.pc += 1;
        switch (i.op) {
            .move => put(it, &regs[i.a], regs[i.b]),
            .loadk => {
                const v = switch (c.consts[i.bx()]) {
                    .int => |x| Value{ .int = x },
                    .real => |x| Value{ .real = x },
                    .rat => |x| Value{ .rat = .{ .n = x[0], .d = x[1] } },
                    .cpx => |x| Value{ .cpx = .{ .re = x[0], .im = x[1] } },
                    .dur => |x| Value{ .dur = x },
                    .str => |s| blk: {
                        it.line = c.lines[pc];
                        break :blk try it.staticStr(s);
                    },
                };
                put(it, &regs[i.a], v);
            },
            .loadi => put(it, &regs[i.a], .{ .int = i.sbx() }),
            .storeg => {
                it.line = c.lines[pc];
                try storeGlobal(it, c.xnodes[i.bx()].node, regs[i.a]);
            },
            .loadg => {
                it.line = c.lines[pc];
                const v = try it.lookup(c.consts[i.bx()].str);
                put(it, &regs[i.a], v);
            },
            .loadnil => put(it, &regs[i.a], .nil),
            .loadtrue => put(it, &regs[i.a], .{ .bool = true }),
            .loadfalse => put(it, &regs[i.a], .{ .bool = false }),
            .add, .sub, .mul, .div, .mod, .eq, .ne, .lt, .le, .gt, .ge => {
                const l = regs[i.b];
                const r = regs[i.c];
                it.line = c.lines[pc];
                const v = try it.applyOp(astOp(i.op), opText(i.op), l, r);
                put(it, &regs[i.a], v);
            },
            .neg => {
                const v = regs[i.b];
                it.line = c.lines[pc];
                const nv = switch (v) {
                    .int, .nat, .byte, .short => |x| Value{ .int = -x },
                    .real, .float => |x| Value{ .real = -x },
                    else => try it.negate(v),
                };
                put(it, &regs[i.a], nv);
            },
            .not => {
                it.line = c.lines[pc];
                const t = try it.truth(regs[i.b]);
                put(it, &regs[i.a], .{ .bool = !t });
            },
            .jmp => {
                const off = i.sbx();
                fr.pc = @intCast(@as(i64, fr.pc) + off);
                if (off < 0) it.safe();
            },
            .jnn => if (regs[i.a] != .nil) {
                fr.pc = @intCast(@as(i64, fr.pc) + i.sbx());
            },
            .unpack => {
                const x = Inst.fromWord(c.code[pc + 1]);
                fr.pc += 1;
                it.line = c.lines[pc];
                try unpack(it, regs, i, x.bx());
            },
            .wait => {
                it.line = c.lines[pc];
                const ms = Interp.msOf(regs[i.a]) orelse return it.fail("wait takes a duration: wait 10ms;", .{});
                try it.waitFor(ms);
            },
            .jf, .jt => {
                const v = regs[i.a];
                const t = if (v == .bool) v.bool else blk: {
                    it.line = c.lines[pc];
                    break :blk try it.truth(v);
                };
                if (t == (i.op == .jt)) fr.pc = @intCast(@as(i64, fr.pc) + i.sbx());
            },
            .forprep => {
                const lo = regs[i.a];
                const hi = regs[i.a + 1];
                const is_sym = lo == .sym and hi == .sym;
                if (!is_sym and (lo != .int or hi != .int)) {
                    it.line = c.lines[pc];
                    return it.fail("bytecode: a for loop over something other than integers or runes is not supported yet", .{});
                }
                const l: i64 = if (is_sym) lo.sym else lo.int;
                const h: i64 = if (is_sym) hi.sym else hi.int;
                if (l > h) {
                    fr.pc = @intCast(@as(i64, fr.pc) + i.sbx());
                } else regs[i.a + 2] = lo;
            },
            .forloop => {
                const is_sym = regs[i.a] == .sym;
                const next = (if (is_sym) @as(i64, regs[i.a].sym) else regs[i.a].int) + 1;
                if (next <= (if (is_sym) @as(i64, regs[i.a + 1].sym) else regs[i.a + 1].int)) {
                    regs[i.a] = if (is_sym) .{ .sym = @intCast(next) } else .{ .int = next };
                    regs[i.a + 2] = regs[i.a];
                    fr.pc = @intCast(@as(i64, fr.pc) + i.sbx());
                    it.safe();
                }
            },
            .callf => {
                const callee = c.funcs[i.c];
                it.line = c.lines[pc];
                const base: u32 = fr.base + i.a + 1;
                try grow(it, base + callee.nregs);
                try it.frames.append(it.a, .{ .kind = callee.kind, .name = callee.name, .call_line = it.line, .file = callee.file });
                try frames.append(it.g, .{ .c = c, .func = i.c, .pc = 0, .base = base, .ret = base - 1 });
                it.bc_top = base + callee.nregs;
                // the body of a routine is a region, as in the tree walker: its safe points free only what it made
                it.regionIn();
                fr = &frames.items[frames.items.len - 1];
                func = callee;
                regs = at(it, fr.base);
            },
            .ret => {
                const done = frames.items[frames.items.len - 1];
                const callee_regs = at(it, done.base);
                const result: Value = if (i.b == 1) callee_regs[i.a] else .nil;
                if (frames.items.len == 1) {
                    // the bottom frame: the result is the value of the run; a value let go waits for the next safe point, as the result of
                    // `runRoutine` does when its scope ends
                    var k: usize = 0;
                    while (k < func.nregs) : (k += 1) put(it, &callee_regs[k], .nil);
                    it.bc_top = done.base;
                    return result;
                }
                _ = frames.pop();
                _ = it.frames.pop();
                // the result goes to the slot of the caller that the call named
                if (!done.discard) put(it, &it.bc_stack[done.ret], result) else put(it, &it.bc_stack[done.ret], .nil);
                var k: usize = 0;
                while (k < func.nregs) : (k += 1) put(it, &callee_regs[k], .nil);
                it.regionOut();
                if (done.saved) |s| it.leaveScope(s);
                fr = &frames.items[frames.items.len - 1];
                c = fr.c;
                func = c.funcs[fr.func];
                it.bc_top = fr.base + func.nregs;
                regs = at(it, fr.base);
            },
            .print => {
                const mark = it.scratch.mark();
                defer it.scratch.release(mark);
                it.line = c.lines[pc];
                var buf: std.ArrayList(u8) = .empty;
                var k: usize = 0;
                while (k < i.b) : (k += 1) {
                    if (k > 0 and i.c == 1) try buf.append(it.t, ',');
                    try it.show(&buf, regs[i.a + k], false);
                }
                if (i.c == 1) try buf.append(it.t, '\n');
                try it.out.writeAll(buf.items);
            },
            .expect => {
                it.line = c.lines[pc];
                if (!try it.truth(regs[i.a])) return it.failWith(interp.err_expect, "expect failed", .{});
            },
            .setlike => {
                const v = regs[i.b];
                put(it, &regs[i.a], if (heapless(regs[i.a]) and heapless(v) and (regs[i.a] == .int or regs[i.a] == .bool or regs[i.a] == .nil)) v else Interp.coerceLike(regs[i.a], v));
            },
            .augment => {
                it.line = c.lines[pc];
                const o: evecm.op.Op = @enumFromInt(i.c);
                const cur = regs[i.a];
                const v = regs[i.b];
                if (cur == .list or cur == .set or v == .list or v == .set) {
                    const nv = try it.augmentValue(astOp(o), opText(o), cur, v);
                    it.aug_inplace = nv == null;
                    if (nv) |x| put(it, &regs[i.a], x);
                } else {
                    it.aug_inplace = false;
                    const nv = try it.applyOp(astOp(o), opText(o), cur, v);
                    put(it, &regs[i.a], nv);
                }
            },
            .coerce => {
                const tk: ast.TypeKind = @enumFromInt(i.b);
                const v = regs[i.a];
                switch (tk) {
                    .real => if (Interp.isInt(v)) put(it, &regs[i.a], .{ .real = @floatFromInt(Interp.intOf(v)) }) else put(it, &regs[i.a], Interp.coerceLike(.{ .real = 0 }, v)),
                    .integer => if (v == .real or v == .float) put(it, &regs[i.a], .{ .int = @intFromFloat(Interp.realOf(v).?) }),
                    else => {},
                }
            },
            .binx => {
                const next = Inst.fromWord(c.code[pc + 1]);
                fr.pc += 1;
                it.line = c.lines[pc];
                const v = try it.apply(c.consts[next.bx()].str, regs[i.b], regs[i.c]);
                put(it, &regs[i.a], v);
            },
            .extra, .pow => unreachable,
            .evalx => {
                it.line = c.lines[pc];
                try evalSlow(it, c, fr.base, i.bx(), i.a);
            },
            .execx => {
                it.line = c.lines[pc];
                try execSlow(it, c, fr.base, i.bx());
            },
            .new_list => {
                const l = try it.h.make(interp.List, .{ .array = i.b == 1 });
                put(it, &regs[i.a], .{ .list = l });
            },
            .new_map => {
                const m = try it.newMap();
                put(it, &regs[i.a], .{ .map = m });
            },
            .new_set => {
                const l = try it.h.make(interp.List, .{});
                put(it, &regs[i.a], .{ .set = l });
            },
            .list_push => try it.listAppend(regs[i.a].list, regs[i.b]),
            .set_add => {
                it.line = c.lines[pc];
                try it.setAdd(regs[i.a].set, regs[i.b]);
            },
            .map_set => {
                it.line = c.lines[pc];
                try it.mapPut(regs[i.a].map, regs[i.b], regs[i.c]);
            },
            .index => {
                const x = Inst.fromWord(c.code[pc + 1]);
                fr.pc += 1;
                it.line = c.lines[pc];
                const key = regs[i.c];
                switch (regs[i.b]) {
                    .list => |l| if (key == .int and !Interp.isMatrix(l)) {
                        const items = l.elems();
                        const k = if (key.int < 0) @as(i64, @intCast(items.len)) + 1 + key.int else key.int;
                        if (k >= 1 and k <= items.len) {
                            put(it, &regs[i.a], items[@intCast(k - 1)]);
                            continue;
                        }
                    },
                    .map => |m| if (Interp.mapFind(m, key)) |at_key| {
                        put(it, &regs[i.a], m.entries.items[at_key].val);
                        continue;
                    },
                    else => {},
                }
                try evalSlow(it, c, fr.base, x.bx(), i.a);
            },
            .index_set => {
                const x = Inst.fromWord(c.code[pc + 1]);
                fr.pc += 1;
                it.line = c.lines[pc];
                const key = regs[i.b];
                switch (regs[i.a]) {
                    .list => |l| if (key == .int and !Interp.isMatrix(l)) {
                        const items = l.elems();
                        const k = if (key.int < 0) @as(i64, @intCast(items.len)) + 1 + key.int else key.int;
                        if (k >= 1 and k <= items.len) {
                            it.setCell(&items[@intCast(k - 1)], regs[i.c]);
                            continue;
                        }
                    },
                    .map => |m| {
                        try it.mapPut(m, key, regs[i.c]);
                        continue;
                    },
                    else => {},
                }
                try execSlow(it, c, fr.base, x.bx());
            },
            .push_front => {
                const x = Inst.fromWord(c.code[pc + 1]);
                fr.pc += 1;
                it.line = c.lines[pc];
                switch (regs[i.a]) {
                    .list => |l| if (regs[i.b] != .list and l.base == null) {
                        try it.listInsert(l, 0, regs[i.b]);
                        continue;
                    },
                    .set => |l| {
                        try it.setAdd(l, regs[i.b]);
                        continue;
                    },
                    else => {},
                }
                try execSlow(it, c, fr.base, x.bx());
            },
            .push => {
                const x = Inst.fromWord(c.code[pc + 1]);
                fr.pc += 1;
                it.line = c.lines[pc];
                switch (regs[i.a]) {
                    .list => |l| if (regs[i.b] != .list and l.base == null) {
                        try it.listAppend(l, regs[i.b]);
                        continue;
                    },
                    .set => |l| {
                        try it.setAdd(l, regs[i.b]);
                        continue;
                    },
                    else => {},
                }
                try execSlow(it, c, fr.base, x.bx());
            },
            .length => {
                const x = Inst.fromWord(c.code[pc + 1]);
                fr.pc += 1;
                it.line = c.lines[pc];
                const v = regs[i.b];
                const len: ?i64 = switch (v) {
                    .str => @intCast(std.unicode.utf8CountCodepoints(v.str) catch v.str.len),
                    .list, .set => |l| @intCast(l.elems().len),
                    .map => |m| @intCast(m.entries.items.len),
                    else => null,
                };
                if (len) |n| {
                    put(it, &regs[i.a], .{ .int = n });
                } else try evalSlow(it, c, fr.base, x.bx(), i.a);
            },
            .loadrune => put(it, &regs[i.a], .{ .sym = Interp.symbolOf(c.consts[i.bx()].str) }),
            .loadnum => {
                it.line = c.lines[pc];
                const lit: Node = .{ .tag = .num, .text = c.consts[i.bx()].str };
                put(it, &regs[i.a], try it.number(&lit));
            },
            .field => {
                const x = Inst.fromWord(c.code[pc + 1]);
                fr.pc += 1;
                it.line = c.lines[pc];
                const name = c.xnodes[x.bx()].node.text;
                switch (regs[i.b]) {
                    .object => |o| if (o.class == null or o.class != it.base().gen_class) {
                        if (Interp.fieldOf(o, name)) |v| {
                            put(it, &regs[i.a], v);
                            continue;
                        }
                    },
                    .module => |m| {
                        put(it, &regs[i.a], try it.moduleMember(m, name));
                        continue;
                    },
                    else => {},
                }
                try evalSlow(it, c, fr.base, x.bx(), i.a);
            },
            .matcheq => put(it, &regs[i.a], .{ .bool = Interp.eq(regs[i.b], regs[i.c]) }),
            .matchpat => {
                it.line = c.lines[pc];
                const subj = regs[i.b];
                const pv = regs[i.c];
                const hit = switch (pv) {
                    .range, .domain => try it.contains(pv, subj),
                    .class => if (subj == .object) it.isOp(subj, pv) else Interp.eq(pv, subj),
                    else => Interp.eq(pv, subj),
                };
                put(it, &regs[i.a], .{ .bool = hit });
            },
            .clone => {
                it.line = c.lines[pc];
                put(it, &regs[i.a], try it.clone(regs[i.b]));
            },
            .declty => {
                const d = c.xnodes[i.bx()].node;
                var v = Interp.coerce(regs[i.a], d.ty);
                it.typeLiteral(v, d.ty);
                if (v == .chan and v.chan.name.len == 0) v.chan.name = d.kids[0].kids[0].text;
                put(it, &regs[i.a], v);
            },
            .new_obj => put(it, &regs[i.a], .{ .object = try it.newObject() }),
            .obj_set => {
                const x = Inst.fromWord(c.code[pc + 1]);
                fr.pc += 1;
                try it.setField(regs[i.a].object, c.consts[x.bx()].str, regs[i.b]);
            },
            .range => {
                const x = Inst.fromWord(c.code[pc + 1]);
                fr.pc += 1;
                it.line = c.lines[pc];
                const v = try it.rangeOf(c.consts[x.bx()].str, regs[i.b], regs[i.c], x.a & 1 != 0, x.a & 2 != 0);
                put(it, &regs[i.a], v);
            },
            .setfield => {
                const x = Inst.fromWord(c.code[pc + 1]);
                fr.pc += 1;
                it.line = c.lines[pc];
                // C = 1: a compound assignment whose list or set was changed in place stores nothing
                if (i.c == 1 and it.aug_inplace) continue;
                try it.assignField(regs[i.a], c.consts[x.bx()].str, regs[i.b]);
            },
            .capture => {
                it.line = c.lines[pc];
                const item = try it.capturePick(regs[i.b], i.c == 0);
                put(it, &regs[i.a], item);
            },
            .dim => put(it, &regs[i.a], .{ .int = try it.dollarOf(regs[i.b]) }),
            .indexv, .index_setv => {
                const x = Inst.fromWord(c.code[pc + 1]);
                fr.pc += 1;
                it.line = c.lines[pc];
                // an `extra` word with A = 1: a compound assignment whose collection was changed in place stores nothing
                if (i.op == .index_setv and x.a == 1 and it.aug_inplace) continue;
                const spec = c.consts[x.bx()].str;
                const ng: usize = spec[0];
                const sizes = spec[1 .. 1 + ng];
                const kinds = spec[1 + ng ..];
                var buf: [16]interp.Interp.IndexArg = undefined;
                const first: usize = i.b;
                var next: usize = first + 1;
                for (kinds, 0..) |kd, k| {
                    if (kd == 1) {
                        buf[k] = .all;
                    } else {
                        buf[k] = .{ .val = regs[next] };
                        next += 1;
                    }
                }
                const target = try it.chainTarget(regs[first], sizes, buf[0..kinds.len]);
                if (i.op == .indexv) {
                    put(it, &regs[i.a], try it.indexOfArgs(target.obj, target.args));
                } else try it.assignIndexArgs(target.obj, target.args, regs[i.a]);
            },
            .step => switch (regs[i.a]) {
                .int => |n| regs[i.a] = .{ .int = n + i.sbx() },
                .sym => |n| regs[i.a] = .{ .sym = @intCast(@as(i64, n) + i.sbx()) },
                else => {},
            },
            .near => {
                it.line = c.lines[pc];
                const x = Interp.realOf(regs[i.b]) orelse return it.fail("=~ with +- needs numbers", .{});
                const mid = Interp.realOf(regs[i.b + 1]) orelse return it.fail("=~ with +- needs numbers", .{});
                const t = Interp.realOf(regs[i.b + 2]) orelse return it.fail("=~ with +- needs numbers", .{});
                put(it, &regs[i.a], .{ .bool = @abs(x - mid) <= t });
            },
            .iterlist => {
                it.line = c.lines[pc];
                const items = try it.iterate(regs[i.b]);
                put(it, &regs[i.a], .{ .list = try it.newList(items, false) });
            },
            .defvar => {
                it.line = c.lines[pc];
                try it.define(c.consts[i.bx() & 0x7fff].str, regs[i.a], i.bx() & 0x8000 != 0);
            },
            .closure => {
                const f = try it.newFunc(c.xnodes[i.bx()].node, it.scope);
                put(it, &regs[i.a], .{ .func = f });
            },
            .jobbegin, .parbegin => {
                const x = Inst.fromWord(c.code[pc + 1]);
                fr.pc += 1;
                it.line = c.lines[pc];
                const label = c.consts[x.bx()].str;
                const block: Block = if (i.op == .jobbegin) .{ .job = try it.jobBegin(label) } else .{ .par = try it.parBegin(label, x.a != 0, if (i.a != 255) regs[i.a] else null) };
                const h = try it.g.create(Handler);
                h.* = .{ .depth = frames.items.len, .pc = @intCast(@as(i64, fr.pc) - 1 + i.sbx()), .block = block, .saved_outs = it.bc_outs };
                it.regionIn();
                it.bc_outs = &h.outs;
                try st.handlers.append(it.g, h);
            },
            .jobclose, .parclose => {
                // the line stays that of the last statement of the block, as in the tree walker (an error of the group names it)
                const h = st.handlers.pop().?;
                defer it.g.destroy(h);
                defer h.outs.deinit(it.g);
                it.regionOut();
                const outcome: Signal!void = if (h.err) |e| e else {};
                defer {
                    it.bc_outs = h.saved_outs;
                    for (h.outs.items) |o| it.h.releaseVar(o.cell);
                }
                switch (h.block) {
                    .job => |js| try it.jobFinish(js, outcome, copyOuts),
                    .par => |ps| try it.parFinish(ps, outcome, copyOuts),
                }
            },
            .signal => return switch (blk: {
                it.line = c.lines[pc];
                break :blk i.a;
            }) {
                0 => error.StopJob,
                1 => error.JobRollback,
                else => error.Panic,
            },
            .commit => {
                it.line = c.lines[pc];
                try it.commitStmt();
            },
            .exitcode => {
                it.line = c.lines[pc];
                try it.setExitCode(regs[i.a]);
            },
            .raise => {
                it.line = c.lines[pc];
                return it.raiseValue(regs[i.a]);
            },
            .failmsg => {
                it.line = c.lines[pc];
                const code: u16 = if (i.b == 1) interp.err_assert else interp.err_expect;
                if (i.c == 1) return it.failWith(code, "{s}", .{try it.text(regs[i.a])});
                return it.failWith(code, "{s}", .{if (i.b == 1) "assertion failed" else "expect failed"});
            },
            .declmark => {
                it.line = c.lines[pc];
                if (regs[i.a] == .bool and regs[i.a].bool) return it.fail("'{s}' is already declared in this scope: a loop has one scope for all its cycles, declare the name before the loop", .{c.consts[i.bx()].str});
                regs[i.a] = .{ .bool = true };
            },
            .xref, .site => unreachable,
            .call => {
                const x = Inst.fromWord(c.code[pc + 1]);
                fr.pc += 1;
                it.line = c.lines[pc];
                const site = c.xnodes[x.bx()];
                const kind: evecm.op.CallKind = @enumFromInt(i.c & 3);
                const stmt = i.c & evecm.op.call_stmt != 0;
                const named = i.c & evecm.op.call_named != 0;
                const tgt = try resolveTarget(it, site, regs, i.a, kind, named);
                const has_ref = i.c & evecm.op.call_ref != 0;
                const pushed = if (has_ref) null else try pushCall(it, frames, site, fr.base, i, kind, stmt, tgt);
                if (pushed) |p| {
                    fr = &frames.items[frames.items.len - 1];
                    c = p.c;
                    func = c.funcs[p.func];
                    regs = at(it, fr.base);
                    continue;
                }
                try callSite(it, site, fr.base, i.a, kind, stmt, has_ref, i.c & (evecm.op.call_start | evecm.op.call_spawn), tgt);
                // the arguments are let go at once, as the tree walker lets go of the values it evaluated; the result of a statement too
                var k: usize = 1;
                while (k <= i.b) : (k += 1) put(it, &regs[i.a + k], .nil);
                if (stmt) put(it, &regs[i.a], .nil);
            },
            .interp => {
                const x = Inst.fromWord(c.code[pc + 1]);
                fr.pc += 1;
                it.line = c.lines[pc];
                const mark = it.scratch.mark();
                defer it.scratch.release(mark);
                var buf: std.ArrayList(u8) = .empty;
                for (c.xnodes[x.bx()].node.kids, 0..) |part, k| {
                    if (part.tag == .str) {
                        try buf.appendSlice(it.t, part.text);
                    } else try buf.appendSlice(it.t, try it.format(part.text[0], part.text[1..], regs[i.b + k]));
                }
                const s = try it.persist(buf.items);
                put(it, &regs[i.a], .{ .str = s });
            },
            .iterprep => {
                fr.pc += 1; // the word after it names the statement, for the listing
                it.line = c.lines[pc];
                const src = regs[i.a];
                var pulled = false;
                switch (src) {
                    .list => {},
                    .range => |r| {
                        regs[i.a + 1] = .{ .int = r.lo };
                        pulled = true;
                    },
                    .chan => pulled = true,
                    .object => |o| if ((o.class != null and o.class == it.base().gen_class) or dlib.isStream(it, src)) {
                        pulled = true;
                    } else try snapshot(it, &regs[i.a]),
                    else => try snapshot(it, &regs[i.a]),
                }
                if (pulled) {
                    if (!try iterPull(it, regs, i.a)) fr.pc = @intCast(@as(i64, fr.pc) + i.sbx() - 1);
                    continue;
                }
                const items = regs[i.a].list.elems();
                if (items.len == 0) {
                    fr.pc = @intCast(@as(i64, fr.pc) + i.sbx() - 1); // counted from the word after iterprep, before the xref word
                } else {
                    regs[i.a + 1] = .{ .int = 1 };
                    put(it, &regs[i.a + 2], items[0]);
                }
            },
            .iterloop => {
                if (regs[i.a] != .list) {
                    if (try iterPull(it, regs, i.a)) {
                        fr.pc = @intCast(@as(i64, fr.pc) + i.sbx());
                        it.safe();
                    }
                    continue;
                }
                const items = regs[i.a].list.elems();
                const next = regs[i.a + 1].int + 1;
                if (next <= items.len) {
                    regs[i.a + 1] = .{ .int = next };
                    put(it, &regs[i.a + 2], items[@intCast(next - 1)]);
                    fr.pc = @intCast(@as(i64, fr.pc) + i.sbx());
                    it.safe();
                }
            },
            .iterend => switch (regs[i.a]) {
                .object => |o| if (o.class != null and o.class == it.base().gen_class) {
                    const gs = it.genOf(o);
                    if (!gs.finished) it.genClose(gs) catch {};
                } else if (dlib.isStream(it, regs[i.a])) dlib.finishStream(it, dlib.streamOf(it, o)) catch {},
                else => {},
            },
            .zero => {
                it.line = c.lines[pc];
                const v = try it.zero(c.xnodes[i.bx()].node);
                put(it, &regs[i.a], v);
            },
            .safe => it.safe(),
            // `over` ends the process from any routine, as the signal of the tree walker; `halt` is the end of `main`
            .over => return error.Over,
            .halt => return .nil,
        }
    }
}
