//! The interpreter: walks the syntax tree (ast.zig) and executes it. It is a plain "tree walker":
//! `exec` runs a statement, `eval` computes an expression, both by looking at the `tag` of the node.
//!
//! Control flow (break, next, over, raise, retry...) is carried by Zig errors (`Signal`): a `raise`
//! unwinds the Zig call stack up to the `recover` of the process, exactly as an exception would.
//! The values of the script live in the heap (heap.zig) and are reference counted: every place that
//! stores a value (a variable, an element, an entry, a field) counts it with `retain` and lets the old
//! one go with `release`. The syntax tree, the classes and the messages stay in the arena of the run.
pub const std = @import("std");
pub const Io = std.Io;
pub const ast = @import("evecm").ast;
pub const task = @import("task.zig");
pub const data = @import("evecm").data;
pub const overload = @import("evecp").overload;
pub const decimal = @import("evecm").decimal;
pub const dlib = @import("dlib.zig");
pub const netlib = @import("netlib.zig");
pub const instant = @import("evecm").instant;
pub const Scratch = @import("scratch.zig").Scratch;
pub const heap = @import("evecm").heap;
pub const Heap = heap.Heap;
pub const Obj = heap.Obj;
pub const Node = ast.Node;

// The values live in evecm (value.zig); they are named here too, so that the code of the interpreter and of the
// libraries keeps writing `interp.Value`.
pub const value = @import("evecm").value;
pub const Signal = value.Signal;
pub const Value = value.Value;
pub const Channel = value.Channel;
pub const Module = value.Module;
pub const List = value.List;
pub const Entry = value.Entry;
pub const Map = value.Map;
pub const Field = value.Field;
pub const Object = value.Object;
pub const Class = value.Class;
pub const Func = value.Func;
pub const Range = value.Range;
pub const Domain = value.Domain;
pub const Var = value.Var;
pub const Binding = value.Binding;
pub const Scope = value.Scope;
pub const Report = value.Report;
pub const Arg = value.Arg;
pub const err_raise = value.err_raise;
pub const err_expect = value.err_expect;
pub const err_assert = value.err_assert;
pub const err_index = value.err_index;
pub const err_key = value.err_key;
pub const err_divide = value.err_divide;
pub const err_convert = value.err_convert;
pub const err_parse = value.err_parse;
pub const err_null = value.err_null;
pub const err_argument = value.err_argument;
pub const err_file = value.err_file;
pub const err_io = value.err_io;
pub const err_access = value.err_access;
pub const err_overflow = value.err_overflow;
pub const err_sql = value.err_sql;

// Zig tip: a task needs its own interpreter (`child`): its scope, its call stack, its output buffer.
// `Started` keeps everything the parent needs after the task ended: the outcome, the arguments to
// write back, the output to flush at `done`. `report` is copied from the child, because the child's
// list of reports is gone with it from the parent's point of view.
/// A started aspect or a spawned subprogram, seen from the parent.
pub const Started = struct {
    t: *task.Task,
    /// The aspect name, or the subprogram name of a spawned task.
    label: []const u8,
    aspect: ?*const Node = null,
    /// A started private process of an aspect (D-179), and the scope of that aspect's state, in which it runs.
    proc: ?*const Node = null,
    unit: ?*Scope = null,
    func: ?*Func = null,
    args: []Arg,
    child: *Interp,
    /// The output of a started aspect, written at `done`; null for a spawned task, which prints directly.
    out: ?*Io.Writer.Allocating = null,
    /// The other tasks of the group, for `on error cancel`.
    siblings: *std.ArrayList(*Started),
    cancel_policy: bool = false,
    failed: bool = false,
    cancelled: bool = false,
    report: Report = .{ .line = 0, .code = 0, .message = "", .job = "" },
};

// Zig tip: a generator is a coroutine: its body runs on a thread of its own (the child interpreter), but only when
// its caller asks for a value, because the two hand the baton to each other (task.zig, `resumeGen`). This record is
// what they share. `value` holds what the generator yielded last; `closing` asks the body to stop at its next
// `yield`; the flags tell the caller what happened while the body ran.
/// The state of one generator object (declarations.md#generators-level-5).
pub const GenState = struct {
    t: *task.Task,
    child: *Interp,
    func: *Func,
    recv: ?Value,
    args: []Arg,
    obj: *Object,
    caller: *task.Task,
    started: bool = false,
    finished: bool = false,
    closing: bool = false,
    failed: bool = false,
    paused: bool = false,
    value: Value = .nil,
    report: Report = .{ .line = 0, .code = 0, .message = "", .job = "" },
};

// Zig tip: a group is a list of the tasks started in it plus its policy; the interpreter keeps a
// pointer to the group whose `do` region is running, so `start` knows where to add the task.
/// The parallel group whose do region is running.
pub const Group = struct {
    list: *std.ArrayList(*Started),
    cancel: bool,
    /// The addresses of the variables and elements given as outputs so far: one owner each (D-140).
    owned: *std.ArrayList(usize),
};

// Zig tip: a small struct for the stack of calls. `kind` is a word that is printed (`function`,
// `procedure`, `method`, `aspect`) and `call_line` is the line, in the caller, where
// this call was made: with it the trace can tell on which line each unit was running.
/// One call in progress: what runs and from which line it was called.
pub const Frame = struct { kind: []const u8, name: []const u8, call_line: u32 };

// Zig tip: a `bool` field is the cheapest way to say "one of two kinds"; `is_error` false means a
// warning. The interpreter only collects these messages: it has no file system, so the session
// (vm.zig) writes them to the run log when the run is over (D-114).
/// One message of `log_err` or `log_wrn`.
pub const LogMsg = struct { is_error: bool, line: u32, unit: []const u8, level: usize, text: []const u8 };

// Zig tip: `Hook` relies on the same Zig feature as `List` above: see the tip there.
/// How the VM asks to look into the slot between two statements.
pub const Hook = struct {
    ctx: *anyopaque,
    /// Returns true when the run must stop.
    poll: *const fn (ctx: *anyopaque, steps: usize, line: u32) bool,
};

// Zig tip: `Hook` above sees only numbers; the debugger must see the node about to run and the interpreter (for the
// depth of the calls), so its hook gets both. `*const fn (...) Signal!void` can fail: an error from the hook (the
// `halt` command is `error.Stop`) unwinds the run exactly as an error of the script would.
/// How the debugger (debugger.zig) is called before each statement of the main task.
pub const DebugHook = struct {
    ctx: *anyopaque,
    before: *const fn (ctx: *anyopaque, it: *Interp, n: *const Node) Signal!void,
};

// Zig tip: `Outcome` relies on the same Zig feature as `List` above: see the tip there.
/// The end of a run.
pub const Outcome = struct {
    /// Exit status: 0, 1 panic, 2 failed expect, 4 raise (D-055).
    code: u8 = 0,
    stopped: bool = false,
};





// Zig tip: the methods of `Interp` are written in several files (interp/*.zig), grouped by concern. Each file holds plain
// functions whose first parameter is `it: *Interp`; the struct names each of them again (`pub const eval = part_expr.eval;`),
// and Zig lets a declaration that is a function be called with the dot syntax: `it.eval(n)` calls `part_expr.eval(it, n)`.
const part_show = @import("interp/show.zig");
const part_expr = @import("interp/expr.zig");
const part_collections = @import("interp/collections.zig");
const part_calls = @import("interp/calls.zig");
const part_stmt = @import("interp/stmt.zig");
const part_script = @import("interp/script.zig");
const part_parallel = @import("interp/parallel.zig");
const part_generators = @import("interp/generators.zig");
const part_datatypes = @import("interp/datatypes.zig");

pub const Interp = struct {
    /// The arena of the run: the syntax tree, the classes, the messages; freed when the script is unloaded.
    a: std.mem.Allocator,
    /// Scratch memory for the buffers that live during one statement (scratch.zig): released at its end.
    t: std.mem.Allocator,
    scratch: *Scratch,
    /// The heap of the values (heap.zig), shared with the tasks; `g` is its allocator, used for the
    /// lists inside heap objects (the elements of a List, the variables of a Scope).
    h: *Heap,
    g: std.mem.Allocator,
    /// The scopes of the calls in progress, outermost first: the roots of the tracing collector.
    scope_stack: std.ArrayList(*Scope) = .empty,
    /// The class `Object`, made once per run.
    object_class: ?*Class = null,
    /// Where the database layer (evedb) keeps its state: one `State` for the run, in the root aspect's interpreter.
    data_slot: ?*anyopaque = null,
    /// The functions and procedures that share a name (D-149): the key is the first declaration, the list holds
    /// all of them in order. A name that is not overloaded has no entry. Only the root aspect's interpreter keeps it.
    overloads: std.AutoHashMapUnmanaged(*const Node, std.ArrayList(*const Node)) = .empty,
    /// The call being made stands alone as a statement (so a method without a result is meant), D-149.
    call_is_stmt: bool = false,
    /// Set by an expression statement for the call it holds, read by `call` (so a nested call is not a statement).
    stmt_call: bool = false,
    /// The call being made writes a type list, `describe(:Integer)(5)`: only generic declarations are meant (D-148).
    written_types: bool = false,
    /// The generators made so far (their objects keep the index in the field `handle`), the class of those objects,
    /// and, for the child interpreter that runs a generator body, the state of that generator.
    gens: std.ArrayList(*GenState) = .empty,
    gen_class: ?*Class = null,
    gen: ?*GenState = null,
    /// The open sources of `csv.read!`, `json.read!`, `txt.read!` and `fs.lines!` (their objects keep the index in the
    /// field `handle`) and the class of those objects (dlib.zig).
    streams: std.ArrayList(*dlib.Stream) = .empty,
    stream_class: ?*Class = null,
    /// The open sockets and listeners of the `net` module (their objects keep the index in the field `handle`) and the
    /// classes of those objects (netlib.zig).
    net_conns: std.ArrayList(*netlib.Conn) = .empty,
    net_listeners: std.ArrayList(*netlib.Listen) = .empty,
    net_socket_class: ?*Class = null,
    net_listener_class: ?*Class = null,
    /// The object of the `update` block that runs, and the scope that holds its field names.
    update_obj: ?*Object = null,
    update_scope: ?*Scope = null,
    /// The class of the objects that `Secret(text)` makes: they print as `***`.
    secret_class: ?*Class = null,
    /// The type arguments of the library call being made: `(:Row)` in `csv.read!(:Row)(path)`.
    type_args: []const *const Node = &.{},
    /// The scope of the built-in names (`True`, the type names, the error codes): made once per run by
    /// the root aspect's interpreter and the parent of every unit (the root aspect, each aspect call, each module).
    prelude: ?*Scope = null,
    out: *Io.Writer,
    global: *Scope,
    scope: *Scope,
    hook: ?Hook = null,
    /// The debugger, when `eve debug` runs the script (only the interpreter of the main task has it).
    dbg: ?DebugHook = null,
    /// Statements executed and the line of the last one: what `report` shows.
    steps: usize = 0,
    line: u32 = 0,
    /// `$` inside an index: the last index of the dimension being indexed.
    dollar: i64 = 0,
    current_job: []const u8 = "",
    /// The label named by the `break` or `skip` that is unwinding; empty for the innermost loop.
    jump_label: []const u8 = "",
    reports: std.ArrayList(Report) = .empty,
    /// The error being handled (`$error`).
    err_code: u8 = err_raise,
    /// The scope of the last process that ran: kept so the introspection can list its variables.
    proc_scope: ?*Scope = null,
    /// The start addresses of the strings made by text literals: `type(x)` says Text for them. Only the
    /// root interpreter keeps the set (`base()`), so the tasks share it.
    text_ptrs: std.AutoHashMapUnmanaged(usize, void) = .empty,
    /// The command-line arguments after the script name: the arguments of `process main`.
    script_args: []const []const u8 = &.{},
    /// The extension methods declared outside a class (D-040).
    exts: std.ArrayList(*const Node) = .empty,
    /// The `defer` statements registered and not yet run, oldest first (D-081).
    defers: std.ArrayList(*const Node) = .empty,
    /// The scope of the script being run: the root aspect's globals, or the scope of one aspect call.
    /// The functions and classes of that script close over it.
    unit: *Scope,
    /// The aspects the root aspect applies, read and checked before the run (project.zig).
    aspects: ?*const ast.Aspects = null,
    /// The modules that the imports reach, read and checked before the run (project.zig).
    modules: ?*const ast.Modules = null,
    /// The modules loaded so far, by tree: a module is loaded once. `load_order` keeps the order of the
    /// initialization, so `finalize` can run in the reverse order (D-068).
    loaded: std.AutoHashMapUnmanaged(*const Node, *Module) = .empty,
    load_order: std.ArrayList(*Module) = .empty,
    /// The calls in progress, outermost first (the trace of an error is read from it).
    frames: std.ArrayList(Frame) = .empty,
    /// The messages of `log_err` and `log_wrn`, in the order written (the run log, D-114).
    logs: std.ArrayList(LogMsg) = .empty,
    /// The input/output handle of the machine: threads, locks and clocks need it (level 4).
    io: ?Io = null,
    /// The scheduler of the tasks, made at the first `parallel` or `spawn` (task.zig).
    sched: ?*task.Sched = null,
    /// The task this interpreter runs: the root for the root aspect.
    me: ?*task.Task = null,
    /// For the interpreter of a task: the root aspect's interpreter, which owns the modules.
    root: ?*Interp = null,
    /// The name of the task, for the messages of a deadlock: the aspect or the subprogram.
    task_name: []const u8 = "aspect",
    /// The group whose do region runs, and the tasks spawned by the job that runs.
    group: ?Group = null,
    job_tasks: ?*std.ArrayList(*Started) = null,
    /// The channels this task has sent into and the ones it has closed: the others are closed when it ends.
    sent: std.ArrayList(*Channel) = .empty,
    closed: std.ArrayList(*Channel) = .empty,

    // Zig tip: `init` builds the struct and `boot` fills the global scope. They are two steps
    // because the scope must live at a stable address (`a.create` gives a pointer that stays valid)
    // and the struct is returned by value. `a.create(Scope)` allocates one; `.* = .{}` sets it.
    pub fn init(a: std.mem.Allocator, out: *Io.Writer) Signal!Interp {
        const hp = try a.create(Heap);
        hp.* = Heap.init(std.heap.smp_allocator);
        hp.pushRegion(); // the region of the whole run
        const g = try hp.make(Scope, .{});
        g.hdr.pinned = true;
        const sc = try newScratch(a);
        var it: Interp = .{ .a = a, .t = sc.allocator(), .scratch = sc, .h = hp, .g = hp.gpa, .out = out, .global = g, .scope = g, .unit = g };
        g.parent = try it.preludeScope();
        try it.boot();
        return it;
    }

    // Zig tip: the scratch struct must stay at one address (its allocator interface points to it), so it
    // is created in the arena and the interpreter keeps a pointer. Its chunks come from `page_allocator`,
    // memory asked directly from the operating system, and go back to it in `deinit`.
    /// A new scratch memory for an interpreter.
    pub fn newScratch(a: std.mem.Allocator) Signal!*Scratch {
        const sc = try a.create(Scratch);
        sc.* = .{ .parent = std.heap.page_allocator };
        return sc;
    }

    // Zig tip: `deinit` relies on the same Zig feature as `newScratch` above: see the tip there.
    /// Give back the memory the interpreter took outside its arena.
    pub fn deinit(it: *Interp) void {
        it.scratch.deinit();
        it.h.deinit();
        it.scope_stack.deinit(it.g);
    }

    // Zig tip: a function pointer with a context pointer (`*anyopaque`) lets the heap call back into the
    // interpreter without importing it as a type it must know: the same idea as `Hook` below.
    /// Mark what the interpreter reaches without the heap: its scopes (the roots of a trace).
    pub fn roots(ctx: *anyopaque, h: *Heap) void {
        const it: *Interp = @ptrCast(@alignCast(ctx));
        h.markFrom(&it.global.hdr);
        h.markFrom(&it.unit.hdr);
        h.markFrom(&it.scope.hdr);
        if (it.proc_scope) |p| h.markFrom(&p.hdr);
        for (it.scope_stack.items) |sc| h.markFrom(&sc.hdr);
        var mods = it.loaded.valueIterator();
        while (mods.next()) |m| h.markFrom(&m.*.scope.hdr);
    }

    // Zig tip: only the two names a script may change are defined in each unit; the constants are found
    // in the prelude, the parent scope of the unit, so an `apply` does not define sixty names again.
    /// Define the names every unit owns: `$epsilon` and `_` (the constants are in the prelude).
    pub fn boot(it: *Interp) Signal!void {
        try it.define("$epsilon", .{ .real = 1e-9 }, false);
        try it.define("_", .nil, false);
    }

    // Zig tip: `for (xs) |x| ...` walks a slice; `for (xs, 0..) |x, i|` also gives the index. The prelude is
    // pinned: it lives to the end of the run, and the units count it as their parent without freeing it.
    /// The scope of the built-in names, made on first use: `True`, `False`, `Null`, the types, `Object`.
    pub fn preludeScope(it: *Interp) Signal!*Scope {
        const b = it.base();
        if (b.prelude) |p| return p;
        const p = try it.newScope(null);
        p.hdr.pinned = true;
        b.prelude = p;
        const saved = it.scope;
        it.scope = p;
        defer it.scope = saved;
        try it.define("True", .{ .bool = true }, true);
        try it.define("False", .{ .bool = false }, true);
        try it.define("Null", .nil, true);
        try it.define("null", .nil, true);
        try it.define("nil", .{ .sym = 0 }, true);
        const types = [_][]const u8{ "Integer", "Natural", "Real", "Symbol", "Rune", "String", "Text", "Logic", "List", "Array", "DataSet", "HashMap", "DataMap", "Byte", "Short", "Huge", "Float", "Decimal", "Instant", "Secret", "Table", "database", "csv", "json", "txt", "fs", "time", "secret", "checkpoint", "crypto", "os", "net", "Listener", "Socket" };
        for (types) |t| try it.define(t, .{ .typ = t }, true);
        try it.define("Channel", .{ .typ = "Channel" }, true);
        // the library traits of version 0.3 (D-145): one shared value each, so `x is Printable` means the
        // same in the root aspect, its aspects and its modules
        for (&value.library_traits) |*tr| try it.define(tr.name, .{ .class = tr }, true);
        const codes = [_]struct { []const u8, i64 }{
            .{ "$err_panic", 1 },     .{ "$err_expect", 2 },    .{ "$err_assert", 3 },   .{ "$err_raise", 4 },
            .{ "$err_index", 10 },    .{ "$err_key", 11 },      .{ "$err_divide", 12 }, .{ "$err_overflow", 13 },
            .{ "$err_convert", 14 },  .{ "$err_parse", 15 },    .{ "$err_null", 16 },   .{ "$err_argument", 17 },
            .{ "$err_file", 20 },     .{ "$err_access", 21 },   .{ "$err_io", 22 },     .{ "$err_module", 30 },
            .{ "$err_process", 31 },  .{ "$err_memory", 40 },   .{ "$err_timeout", 41 }, .{ "$err_deadlock", 42 },
            .{ "$err_output", 43 },   .{ "$err_recursion", 44 }, .{ "$err_parallel", 45 }, .{ "$err_channel", 46 },
            .{ "$err_database", 50 }, .{ "$err_connection", 51 }, .{ "$err_constraint", 52 }, .{ "$err_conflict", 53 },
            .{ "$err_mapping", 54 },  .{ "$err_commit", 55 },   .{ "$err_format", 56 },  .{ "$err_http", 57 },
            .{ "$err_batch", 58 },    .{ "$err_sql", 59 },
            .{ "$wrn_deprecated", 5 }, .{ "$wrn_truncate", 6 }, .{ "$wrn_unused", 7 },
        };
        for (codes) |c| try it.define(c[0], .{ .int = c[1] }, true);
        if (b.object_class == null) {
            const object = try it.a.create(Class);
            object.* = .{ .name = "Object" };
            b.object_class = object;
        }
        try it.define("Object", .{ .class = b.object_class.? }, true);
        return p;
    }

    // ---- errors ---------------------------------------------------------------------------

    // Zig tip: `fail` formats a message into the arena and returns `error.Raise`, so a caller writes
    // `return it.fail("...", .{})`. The message is kept in `reports`, where the `recover` block
    // (`$error.message`) and the `errors` command read it. `comptime fmt` is checked against `args`.
    /// Raise an error with a code and a message.
    pub fn failWith(it: *Interp, code: u8, comptime fmt: []const u8, args: anytype) Signal {
        const msg = std.fmt.allocPrint(it.a, fmt, args) catch return error.OutOfMemory;
        return it.failMsg(code, msg);
    }

    /// Raise an error whose message is already made (the database layer formats its own).
    pub fn failMsg(it: *Interp, code: u8, msg: []const u8) Signal {
        const trace = try it.traceText();
        it.reports.append(it.a, .{ .line = it.line, .code = code, .message = msg, .job = it.current_job, .trace = trace }) catch return error.OutOfMemory;
        it.err_code = code;
        return error.Raise;
    }

    // Zig tip: the trace is built from the stack of frames, walking it from the top (`while (i > 0) :
    // (i -= 1)` counts down, see check.zig). The innermost unit was running on `it.line`; the unit
    // below it was running on the line where it made the call, which the frame above remembers.
    /// The stack of calls as text, innermost first (D-113).
    pub fn traceText(it: *Interp) Signal![]const u8 {
        var buf: std.ArrayList(u8) = .empty;
        var line = it.line;
        var i = it.frames.items.len;
        while (i > 0) : (i -= 1) {
            const f = it.frames.items[i - 1];
            try appendFmt(&buf, it.a, "  line {d} in {s} {s}\n", .{ line, f.kind, f.name });
            line = f.call_line;
        }
        if (it.current_job.len > 0) try appendFmt(&buf, it.a, "  in job {s}\n", .{it.current_job});
        return buf.items;
    }

    // Zig tip: a function whose first parameter is the struct (`p: *Parser`) is called with dot
    // syntax: `p.name(...)`.
    pub fn fail(it: *Interp, comptime fmt: []const u8, args: anytype) Signal {
        return it.failWith(err_raise, fmt, args);
    }

    // ---- scopes ---------------------------------------------------------------------------

    // Zig tip: `try f()` calls `f` and, when it returns an error, returns that error from this
    // function too.
    /// Declare `name` in the current scope (a second declaration replaces the first).
    pub fn define(it: *Interp, name: []const u8, v: Value, constant: bool) Signal!void {
        // a name declared again in the same scope (a loop variable, a `new` in a loop body) keeps its
        // variable when nobody else holds it: the value is replaced, nothing is allocated
        for (it.scope.binds.items) |b| {
            if (b.v.hdr.rc == 1 and std.mem.eql(u8, b.name, name)) {
                it.setVar(b.v, v);
                b.v.constant = constant;
                return;
            }
        }
        const cell = try it.h.make(Var, .{ .value = v, .constant = constant });
        Heap.retain(v);
        try it.bind(name, cell);
    }

    // Zig tip: `std.mem.eql(u8, a, b)` compares two slices by content; `==` on slices would compare
    // their addresses.
    // A binding counts its variable: replacing one lets the old variable go.
    pub fn bind(it: *Interp, name: []const u8, cell: *Var) Signal!void {
        Heap.retainVar(cell);
        for (it.scope.binds.items) |*b| {
            if (std.mem.eql(u8, b.name, name)) {
                const old = b.v;
                b.v = cell;
                it.h.releaseVar(old);
                return;
            }
        }
        try it.scope.binds.append(it.g, .{ .name = name, .v = cell });
    }

    // Zig tip: the new value is counted before the old one is let go: if both are the same object, its
    // count never touches zero on the way.
    /// Store `v` in the variable `cell`.
    pub fn setVar(it: *Interp, cell: *Var, v: Value) void {
        Heap.retain(v);
        it.h.release(cell.value);
        cell.value = v;
    }

    // Zig tip: `setCell` relies on the same Zig feature as `setVar` above: see the tip there.
    /// Store `v` in an element of a list (or any counted cell).
    pub fn setCell(it: *Interp, c: *Value, v: Value) void {
        Heap.retain(v);
        it.h.release(c.*);
        c.* = v;
    }

    // Zig tip: `lookup` relies on the same Zig feature as `fail` above: see the tip there.
    pub fn lookup(it: *Interp, name: []const u8) Signal!Value {
        if (it.scope.find(name)) |v| return v.value;
        return it.fail("undefined name '{s}'", .{name});
    }

    // Zig tip: `pushScope` relies on the same Zig feature as `define` above: see the tip there.
    pub fn pushScope(it: *Interp) Signal!*Scope {
        return it.enterScope(try it.newScope(it.scope));
    }

    // Zig tip: a child scope counts its parent: the parent lives as long as any scope below it.
    /// A new scope below `parent` (none for the scope of an aspect or a module).
    pub fn newScope(it: *Interp, parent: ?*Scope) Signal!*Scope {
        const s = try it.h.make(Scope, .{ .parent = parent });
        if (parent) |p| Heap.retainScope(p);
        return s;
    }

    // Zig tip: the frame that enters a scope counts it, and `leaveScope` lets it go: a scope that no
    // closure captured is freed right there, with its variables. The scope that was current goes on
    // `scope_stack`, where the tracing collector finds it.
    /// Make `s` the current scope; returns the scope to come back to.
    pub fn enterScope(it: *Interp, s: *Scope) Signal!*Scope {
        Heap.retainScope(s);
        try it.scope_stack.append(it.g, it.scope);
        const saved = it.scope;
        it.scope = s;
        return saved;
    }

    // Zig tip: `leaveScope` relies on the same Zig feature as `enterScope` above: see the tip there.
    /// Come back to `saved` and let the scope that ends go.
    pub fn leaveScope(it: *Interp, saved: *Scope) void {
        const s = it.scope;
        it.scope = saved;
        _ = it.scope_stack.pop();
        it.h.releaseScope(s);
    }

    // Zig tip: `setProc` relies on the same Zig feature as `setVar` above: see the tip there.
    /// Remember the scope of the last process that ran (for the introspection commands).
    pub fn setProc(it: *Interp, s: ?*Scope) void {
        if (s) |x| Heap.retainScope(x);
        if (it.proc_scope) |old| it.h.releaseScope(old);
        it.proc_scope = s;
    }

    // ---- regions and safe points (heap.zig) -------------------------------------------------------

    // Zig tip: only the root aspect's interpreter keeps regions: tasks share the heap, and while they run
    // nothing is freed (see `Heap.pause`), so their blocks need no bookkeeping.
    /// Start a region (a block, a loop, a process).
    pub fn regionIn(it: *Interp) void {
        if (it.root == null) it.h.pushRegion();
    }

    // Zig tip: `regionOut` relies on the same Zig feature as `regionIn` above: see the tip there.
    /// Leave the region.
    pub fn regionOut(it: *Interp) void {
        if (it.root == null) it.h.popRegion();
    }

    // Zig tip: `safe` relies on the same Zig feature as `regionIn` above: see the tip there.
    /// A safe point: a statement or a pass of a loop has ended, its temporaries are gone.
    pub fn safe(it: *Interp) void {
        if (it.root == null) it.h.safePoint();
    }

    // ---- counted containers ---------------------------------------------------------------------

    // Zig tip: every change of a list goes through these helpers, which count what comes in and let
    // go of what goes out. A removed value is still usable until the next safe point.
    pub fn listAppend(it: *Interp, l: *List, v: Value) Signal!void {
        try l.items.append(it.g, v);
        Heap.retain(v);
    }

    // Zig tip: `listAppendSlice` relies on the same Zig feature as `listAppend` above: see the tip there.
    pub fn listAppendSlice(it: *Interp, l: *List, vs: []const Value) Signal!void {
        try l.items.appendSlice(it.g, vs);
        for (vs) |v| Heap.retain(v);
    }

    // Zig tip: `listInsert` relies on the same Zig feature as `listAppend` above: see the tip there.
    pub fn listInsert(it: *Interp, l: *List, i: usize, v: Value) Signal!void {
        try l.items.insert(it.g, i, v);
        Heap.retain(v);
    }

    // Zig tip: `listInsertSlice` relies on the same Zig feature as `listAppend` above: see the tip there.
    pub fn listInsertSlice(it: *Interp, l: *List, i: usize, vs: []const Value) Signal!void {
        try l.items.insertSlice(it.g, i, vs);
        for (vs) |v| Heap.retain(v);
    }

    // Zig tip: `listRemove` relies on the same Zig feature as `listAppend` above: see the tip there.
    pub fn listRemove(it: *Interp, l: *List, i: usize) Value {
        const v = l.items.orderedRemove(i);
        it.h.release(v);
        return v;
    }

    // Zig tip: `listPop` relies on the same Zig feature as `listAppend` above: see the tip there.
    pub fn listPop(it: *Interp, l: *List) Value {
        const v = l.items.pop().?;
        it.h.release(v);
        return v;
    }

    // Zig tip: `newRange` relies on the same Zig feature as `newObject` below: see the tip there.
    pub fn newRange(it: *Interp, r: Range) Signal!*Range {
        return it.h.make(Range, r);
    }

    // Zig tip: `newDomain` relies on the same Zig feature as `newObject` below: see the tip there.
    pub fn newDomain(it: *Interp, d: Domain) Signal!*Domain {
        return it.h.make(Domain, d);
    }

    // Zig tip: a function counts the scope it closes over: the scope lives as long as the function.
    pub fn newFunc(it: *Interp, node: *const Node, closure: *Scope) Signal!*Func {
        const f = try it.h.make(Func, .{ .node = node, .closure = closure });
        Heap.retainScope(closure);
        return f;
    }

    // Zig tip: `newMap` relies on the same Zig feature as `newObject` below: see the tip there.
    pub fn newMap(it: *Interp) Signal!*Map {
        return it.h.make(Map, .{});
    }

    // Zig tip: a string value always lives in the heap (heap.zig, `Str`): this copies scratch or arena
    // text into it.
    /// A new heap string with a copy of `bytes`.
    pub fn newStr(it: *Interp, bytes: []const u8) Signal!Value {
        return .{ .str = try it.h.str(bytes) };
    }

    // Zig tip: `staticStr` relies on the same Zig feature as `newStr` above: see the tip there.
    /// The pinned heap copy of a text that never changes (a literal, a constant word).
    pub fn staticStr(it: *Interp, bytes: []const u8) Signal!Value {
        return .{ .str = try it.h.static(bytes) };
    }

    // Zig tip: an argument `@s[i]` owns the variable made for it (see `elementRef`): once its value is
    // written back, the variable is let go.
    /// Let go of the variables the arguments own.
    pub fn dropArgs(it: *Interp, args: []const Arg) void {
        for (args) |a| if (a.cell != null) {
            if (a.ref) |r| it.h.releaseVar(r);
        };
    }

    // ---- values: construction and inspection ----------------------------------------------

    // Zig tip: `std.ArrayList(T)` is a growable array: it starts `.empty`, `append(allocator, x)`
    // adds, `.items` is the slice of what it holds.
    pub fn newList(it: *Interp, items: []const Value, array: bool) Signal!*List {
        const l = try it.h.make(List, .{ .array = array });
        try it.listAppendSlice(l, items);
        return l;
    }

    // Zig tip: `newObject` relies on the same Zig feature as `define` above: see the tip there.
    pub fn newObject(it: *Interp) Signal!*Object {
        return it.h.make(Object, .{});
    }

    pub const typeName = value.typeName;

    pub const isInt = value.isInt;

    pub const intOf = value.intOf;

    pub const realOf = value.realOf;

    pub const decOf = value.decOf;

    // Zig tip: `truth` relies on the same Zig feature as `typeName` above: see the tip there.
    pub fn truth(it: *Interp, v: Value) Signal!bool {
        return switch (v) {
            .bool => |b| b,
            else => it.fail("a Logic value is expected, found {s}", .{typeName(v)}),
        };
    }

    // Zig tip: `std.math.order(a, b)` returns `.lt`, `.eq` or `.gt` for numbers. A function returns
    // an error union when it can fail: comparing a String with a List is a script error here.
    /// Order two values of the same family (numbers, strings, symbols).
    pub fn order(it: *Interp, a: Value, b: Value) Signal!std.math.Order {
        if (isInt(a) and isInt(b)) return std.math.order(intOf(a), intOf(b));
        if (a == .dec or b == .dec) if (decOf(a)) |x| if (decOf(b)) |y| return decimal.order(x, y);
        if (a == .instant and b == .instant) return std.math.order(a.instant, b.instant);
        if (realOf(a)) |x| if (realOf(b)) |y| return std.math.order(x, y);
        if (a == .str and b == .str) return std.mem.order(u8, a.str, b.str);
        if (a == .sym and b == .sym) return std.math.order(a.sym, b.sym);
        return it.fail("cannot compare {s} with {s}", .{ typeName(a), typeName(b) });
    }

    pub const eq = value.eq;

    pub const same = value.same;

    pub const fieldOf = value.fieldOf;

    // Zig tip: `setField` relies on the same Zig feature as `define` above: see the tip there.
    pub fn setField(it: *Interp, o: *Object, name: []const u8, v: Value) Signal!void {
        for (o.fields.items) |*f| {
            if (std.mem.eql(u8, f.name, name)) {
                it.setCell(&f.val, v);
                return;
            }
        }
        try o.fields.append(it.g, .{ .name = name, .val = v });
        Heap.retain(v);
    }

    // Zig tip: `std.mem.order(u8, a, b)` compares two byte slices. Keeping the set sorted at every
    // insertion (`insert` at the found position) costs a little per element and makes `==`, `print`
    // and `in` simple. A `while` loop with an index finds the first element not smaller than `v`.
    /// Add `v` to the sorted list `s` unless an equal element is there.
    pub fn setAdd(it: *Interp, s: *List, v: Value) Signal!void {
        var i: usize = 0;
        while (i < s.items.items.len) : (i += 1) {
            switch (try it.order(s.items.items[i], v)) {
                .lt => continue,
                .eq => return,
                .gt => break,
            }
        }
        try it.listInsert(s, i, v);
    }

    // Zig tip: `setOf` relies on the same Zig feature as `define` above: see the tip there.
    pub fn setOf(it: *Interp, v: Value) Signal!*List {
        const s = try it.h.make(List, .{});
        switch (v) {
            .list, .set => |l| for (l.elems()) |e| try it.setAdd(s, e),
            else => return it.fail("a collection is expected, found {s}", .{typeName(v)}),
        }
        return s;
    }

    // Zig tip: `contains` relies on the same Zig feature as `newList` above: see the tip there.
    pub fn contains(it: *Interp, coll: Value, v: Value) Signal!bool {
        switch (coll) {
            .list, .set => |l| {
                for (l.elems()) |e| if (eq(e, v)) return true;
                return false;
            },
            .map => |m| {
                for (m.entries.items) |e| if (eq(e.key, v)) return true;
                return false;
            },
            .range => |r| {
                if (r.sym) return v == .sym and v.sym >= r.lo and v.sym <= r.hi;
                if (!isInt(v)) return false;
                const n = intOf(v);
                return n >= r.lo and n <= r.hi and @mod(n, r.step) == 0;
            },
            .domain => |d| return if (realOf(v)) |x| inDomain(d, x) else false,
            .str => |s| return v == .str and std.mem.indexOf(u8, s, v.str) != null,
            else => return it.fail("'in' needs a collection, found {s}", .{typeName(coll)}),
        }
    }

    // Zig tip: `clone` relies on the same Zig feature as `define` above: see the tip there.
    /// `::`: a deep copy. Natives are copied anyway.
    pub fn clone(it: *Interp, v: Value) Signal!Value {
        switch (v) {
            .list, .set => |l| {
                const c = try it.h.make(List, .{ .array = l.array });
                try c.items.ensureTotalCapacity(it.g, l.elems().len); // one allocation for the copy
                for (l.elems()) |e| try it.listAppend(c, try it.clone(e));
                return if (v == .set) .{ .set = c } else .{ .list = c };
            },
            .map => |m| {
                const c = try it.newMap();
                for (m.entries.items) |e| {
                    const val = try it.clone(e.val);
                    try c.entries.append(it.g, .{ .key = e.key, .val = val });
                    Heap.retain(e.key);
                    Heap.retain(val);
                }
                return .{ .map = c };
            },
            .object => |o| {
                const c = try it.newObject();
                c.class = o.class;
                for (o.fields.items) |f| {
                    const val = try it.clone(f.val);
                    try c.fields.append(it.g, .{ .name = f.name, .val = val });
                    Heap.retain(val);
                }
                return .{ .object = c };
            },
            else => return v,
        }
    }

    // ---- text of a value ------------------------------------------------------------------
    // (in interp/show.zig)
    pub const utf8 = part_show.utf8;
    pub const appendFmt = part_show.appendFmt;
    pub const show = part_show.show;
    pub const text = part_show.text;
    pub const persist = part_show.persist;
    pub const persist2 = part_show.persist2;
    // ---- formats of the interpolation -----------------------------------------------------
    // (in interp/show.zig)
    pub const isAlign = part_show.isAlign;
    pub const format = part_show.format;
    pub const fixed = part_show.fixed;
    pub const interpolate = part_show.interpolate;
    // ---- expressions ----------------------------------------------------------------------
    // (in interp/expr.zig)
    pub const number = part_expr.number;
    pub const symbolOf = part_expr.symbolOf;
    pub const durationMs = part_expr.durationMs;
    pub const eval = part_expr.eval;
    pub const unary = part_expr.unary;
    pub const makeRange = part_expr.makeRange;
    pub const inDomain = part_expr.inDomain;
    pub const brace = part_expr.brace;
    pub const mapFind = part_expr.mapFind;
    pub const mapPut = part_expr.mapPut;
    // ---- operators ------------------------------------------------------------------------
    // (in interp/expr.zig)
    pub const binary = part_expr.binary;
    pub const textual = part_expr.textual;
    pub const overflow = part_expr.overflow;
    pub const apply = part_expr.apply;
    pub const isScalar = part_expr.isScalar;
    pub const isBulkOp = part_expr.isBulkOp;
    pub const bulkOne = part_expr.bulkOne;
    pub const broadcast = part_expr.broadcast;
    pub const isOp = part_expr.isOp;
    pub const setOp = part_expr.setOp;
    pub const concat = part_expr.concat;
    pub const product = part_expr.product;
    // ---- collections: iteration, builders, indexing ---------------------------------------
    // (in interp/collections.zig)
    pub const iterate = part_collections.iterate;
    pub const bindPattern = part_collections.bindPattern;
    pub const builder = part_collections.builder;
    pub const allTrue = part_collections.allTrue;
    pub const collect = part_collections.collect;
    pub const Idx = part_collections.Idx;
    pub const isMatrix = part_collections.isMatrix;
    pub const dimLen = part_collections.dimLen;
    pub const evalIdx = part_collections.evalIdx;
    pub const leaves = part_collections.leaves;
    pub const slots = part_collections.slots;
    pub const pick = part_collections.pick;
    pub const walk = part_collections.walk;
    pub const indexChain = part_collections.indexChain;
    pub const index = part_collections.index;
    pub const indexOf = part_collections.indexOf;
    pub const field = part_collections.field;
    // ---- calls ----------------------------------------------------------------------------
    // (in interp/calls.zig)
    pub const call = part_calls.call;
    pub const invokeOverloaded = part_calls.invokeOverloaded;
    pub const callValue = part_calls.callValue;
    pub const classRoutine = part_calls.classRoutine;
    pub const routinesNamed = part_calls.routinesNamed;
    pub const addUnique = part_calls.addUnique;
    pub const extensionFor = part_calls.extensionFor;
    pub const callMethod = part_calls.callMethod;
    pub const evalArgs = part_calls.evalArgs;
    pub const bindParams = part_calls.bindParams;
    pub const invoke = part_calls.invoke;
    pub const invokeWith = part_calls.invokeWith;
    pub const runRoutine = part_calls.runRoutine;
    pub const constructClass = part_calls.constructClass;
    pub const zero = part_calls.zero;
    pub const atomLen = part_calls.atomLen;
    pub const atomMatch = part_calls.atomMatch;
    pub const matchHere = part_calls.matchHere;
    pub const regexMatch = part_calls.regexMatch;
    // ---- statements -----------------------------------------------------------------------
    // (in interp/stmt.zig)
    pub const execBlock = part_stmt.execBlock;
    pub const execBody = part_stmt.execBody;
    pub const tick = part_stmt.tick;
    pub const exec = part_stmt.exec;
    pub const setJob = part_stmt.setJob;
    pub const exprStmt = part_stmt.exprStmt;
    pub const listOp = part_stmt.listOp;
    pub const print = part_stmt.print;
    pub const raise = part_stmt.raise;
    // ---- declarations and assignment ------------------------------------------------------
    // (in interp/stmt.zig)
    pub const declareRoutine = part_stmt.declareRoutine;
    pub const coerce = part_stmt.coerce;
    pub const runDefers = part_stmt.runDefers;
    pub const capture = part_stmt.capture;
    pub const declare = part_stmt.declare;
    pub const typeLiteral = part_stmt.typeLiteral;
    pub const declareOne = part_stmt.declareOne;
    pub const assign = part_stmt.assign;
    pub const listModifier = part_stmt.listModifier;
    pub const coerceLike = part_stmt.coerceLike;
    pub const assignTo = part_stmt.assignTo;
    // ---- control statements ---------------------------------------------------------------
    // (in interp/stmt.zig)
    pub const ifStmt = part_stmt.ifStmt;
    pub const caught = part_stmt.caught;
    pub const whileStmt = part_stmt.whileStmt;
    pub const forStmt = part_stmt.forStmt;
    pub const repeatStmt = part_stmt.repeatStmt;
    pub const matchStmt = part_stmt.matchStmt;
    // ---- running a script -----------------------------------------------------------------
    // (in interp/script.zig)
    pub const errorObject = part_script.errorObject;
    pub const runProcess = part_script.runProcess;
    // ---- modules (spec/semantics/modules.md) ------------------------------------------------------
    // (in interp/script.zig)
    pub const moduleMember = part_script.moduleMember;
    pub const instantiate = part_script.instantiate;
    pub const noneNode = part_script.noneNode;
    pub const bindBare = part_script.bindBare;
    pub const execImport = part_script.execImport;
    pub const finalizeModules = part_script.finalizeModules;
    pub const applyAspect = part_script.applyAspect;
    pub const runAspect = part_script.runAspect;
    pub const applyPrivate = part_script.applyPrivate;
    pub const runPrivate = part_script.runPrivate;
    // ---- level 4: parallel groups, channels, tasks (spec/semantics/multitasking.md) -----------------
    // (in interp/parallel.zig)
    pub const host = part_parallel.host;
    pub const base = part_parallel.base;
    pub const ensureSched = part_parallel.ensureSched;
    pub const durText = part_parallel.durText;
    pub const checkCancel = part_parallel.checkCancel;
    pub const waitFor = part_parallel.waitFor;
    pub const blockOn = part_parallel.blockOn;
    pub const timeoutMs = part_parallel.timeoutMs;
    pub const deadlock = part_parallel.deadlock;
    pub const newChannel = part_parallel.newChannel;
    pub const moved = part_parallel.moved;
    pub const send = part_parallel.send;
    pub const receive = part_parallel.receive;
    pub const closeChannel = part_parallel.closeChannel;
    pub const closeSent = part_parallel.closeSent;
    pub const channelMethod = part_parallel.channelMethod;
    pub const cut = part_parallel.cut;
    pub const elementRef = part_parallel.elementRef;
    pub const writeBack = part_parallel.writeBack;
    pub const newChild = part_parallel.newChild;
    pub const launch = part_parallel.launch;
    pub const ownInputs = part_parallel.ownInputs;
    pub const ownOutputs = part_parallel.ownOutputs;
    pub const startAspect = part_parallel.startAspect;
    pub const startPrivate = part_parallel.startPrivate;
    pub const spawnTask = part_parallel.spawnTask;
    pub const taskMain = part_parallel.taskMain;
    pub const parallelGroup = part_parallel.parallelGroup;
    pub const joinTasks = part_parallel.joinTasks;
    pub const endTasks = part_parallel.endTasks;
    pub const collectAtDone = part_parallel.collectAtDone;
    pub const raiseFailed = part_parallel.raiseFailed;
    pub const hasLocal = part_parallel.hasLocal;
    pub const findProcess = part_parallel.findProcess;
    pub const run = part_parallel.run;
    pub const exitCodeOf = part_parallel.exitCodeOf;
    pub const note = part_parallel.note;
    // ---- the update block (database.md) ---------------------------------------------------------------
    // (in interp/generators.zig)
    pub const updateStmt = part_generators.updateStmt;
    // ---- generators (spec/syntax/declarations.md#generators-level-5) ---------------------------------
    // (in interp/generators.zig)
    pub const makeGenerator = part_generators.makeGenerator;
    pub const genMain = part_generators.genMain;
    pub const yieldStmt = part_generators.yieldStmt;
    pub const genNext = part_generators.genNext;
    pub const genEnded = part_generators.genEnded;
    pub const genClose = part_generators.genClose;
    pub const generatorCall = part_generators.generatorCall;
    pub const forGenerator = part_generators.forGenerator;
    pub const closeGenerators = part_generators.closeGenerators;
    // ---- Decimal, Instant, Secret (spec/library/data-language.md) ---------------------------------------
    // (in interp/datatypes.zig)
    pub const decimalOp = part_datatypes.decimalOp;
    pub const decFromReal = part_datatypes.decFromReal;
    pub const fromSqlText = part_datatypes.fromSqlText;
    pub const makeSecret = part_datatypes.makeSecret;
    pub const isGenerator = part_datatypes.isGenerator;
    pub const isSecret = part_datatypes.isSecret;
    pub const secretObject = part_datatypes.secretObject;
    pub const secretGet = part_datatypes.secretGet;
    pub const runRoot = part_datatypes.runRoot;
};

// Zig tip: the interpreter is tested end to end: parse a script, run it, compare what it printed.
// `std.heap.ArenaAllocator` over the testing allocator frees every node and value at `deinit`,
// and the testing allocator then checks that nothing leaked. `Io.Writer.fixed` collects the output.
fn runSource(src: []const u8, buf: []u8) !struct { out: []const u8, code: u8 } {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var diag: @import("evecp").lexer.Diag = .{};
    const root = try @import("evecp").parser.parse(arena.allocator(), src, &diag);
    var w: Io.Writer = .fixed(buf);
    var it = try Interp.init(arena.allocator(), &w);
    defer it.deinit();
    const o = it.run(root);
    return .{ .out = w.buffered(), .code = o.code };
}

// Zig tip: a `test` block runs under `zig build test`; `try std.testing.expect...` fails it when the
// value is not the expected one.
test "a free script prints, computes and interpolates" {
    var buf: [256]u8 = undefined;
    const r = try runSource("primary aspect t is\n  process main is\n    new a := 2;\n    let a += 3;\n    expect a == 5;\n    print \"a = {a}\";\n  return;\nend t;\n", &buf);
    try std.testing.expectEqualStrings("a = 5\n", r.out);
    try std.testing.expectEqual(@as(u8, 0), r.code);
}

// Zig tip: `a failed expect exits with 2 and recover catches a raise` relies on the same Zig feature
// as `a free script prints, computes and interpolates` above: see the tip there.
test "a failed expect exits with 2 and recover catches a raise" {
    var buf: [256]u8 = undefined;
    const r = try runSource("primary aspect d is process main is print \"x\"; expect 1 == 2; return; end d;", &buf);
    try std.testing.expectEqualStrings("x\n", r.out);
    try std.testing.expectEqual(@as(u8, 2), r.code);
    const s = try runSource("primary aspect d is process main is raise \"boom\"; recover print $error.message; return; end d;", &buf);
    try std.testing.expectEqualStrings("boom\n", s.out);
    try std.testing.expectEqual(@as(u8, 0), s.code);
}

// Zig tip: `regular expressions` relies on the same Zig feature as `a free script prints, computes
// and interpolates` above: see the tip there.
test "regular expressions" {
    try std.testing.expect(Interp.regexMatch("/^this/", "this is"));
    try std.testing.expect(Interp.regexMatch("/l.ke$/", "like"));
    try std.testing.expect(Interp.regexMatch("/abc/i", "xABCx"));
    try std.testing.expect(!Interp.regexMatch("/^not/", "this is not"));
    try std.testing.expect(Interp.regexMatch("/c[0-9]+/", "abc123"));
}

// Zig tip: `std.testing.expectEqual(expected, actual)` compares two values of the same type; `@as(?i64, 30_000)`
// gives the literal the optional type of the result, so the two sides match. The second half runs a
// small script: `split` and `batch` need no task, so no input/output handle is needed (D-142, D-144).
test "durations are milliseconds, split and batch cut a list" {
    try std.testing.expectEqual(@as(?i64, 30_000), Interp.durationMs("30s"));
    try std.testing.expectEqual(@as(?i64, 10), Interp.durationMs("10ms"));
    try std.testing.expectEqual(@as(?i64, null), Interp.durationMs("42"));
    var buf: [256]u8 = undefined;
    const r = try runSource("primary aspect t is\n  process main is\n    new l := (1, 2, 3, 4, 5);\n    print l.split(2);\n    print l.batch(2);\n  return;\nend t;\n", &buf);
    try std.testing.expectEqualStrings("((1,2,3),(4,5))\n((1,2),(3,4),(5))\n", r.out);
}

// Zig tip: a test can look inside the interpreter after a run: `it.h.stats` counts what the heap made
// and freed. A loop that builds a string and a list at each pass must not keep them: reference
// counting frees them at the end of each pass, so only a few objects are alive at the end.
test "a loop frees what each pass makes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var diag: @import("evecp").lexer.Diag = .{};
    const src = "primary aspect t is\n  process main is\n    new total := 0;\n    for i in (1..10000) do\n      new s := \"item {i}\";\n      new parts := (i, i + 1);\n      let total += parts.length();\n    done;\n    print total;\n  return;\nend t;\n";
    const root = try @import("evecp").parser.parse(arena.allocator(), src, &diag);
    var buf: [64]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var it = try Interp.init(arena.allocator(), &w);
    defer it.deinit();
    _ = it.run(root);
    try std.testing.expectEqualStrings("20000\n", w.buffered());
    try std.testing.expect(it.h.stats.made > 20_000);
    try std.testing.expect(it.h.stats.live < 100);
}
