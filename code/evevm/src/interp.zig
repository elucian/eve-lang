//! @eve-module interp
//! @spec spec/semantics/control.md, spec/semantics/variables.md, spec/semantics/errors.md
//! @feature F-VM-02, F-LNG-04, F-LNG-05
//! @decision D-151
//! @tests test/level1, test/level2, test/level3
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
pub const rational = @import("evecm").rational;
pub const complex = @import("evecm").complex;
pub const duration = @import("evecm").duration;
pub const calendar = @import("evecm").calendar;
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

/// One `-p name=value` of the command line.
pub const ScriptParam = struct { name: []const u8, value: []const u8 };
pub const err_file = value.err_file;
pub const err_io = value.err_io;
pub const err_access = value.err_access;
pub const err_overflow = value.err_overflow;
pub const err_sql = value.err_sql;

// @eve-impl which engine runs the program: the tree walker (the reference) or the bytecode machine (design/design-bytecode.md)
// @decision D-201
/// The engine of the run, chosen by `--engine` or `EVE_ENGINE`.
pub const Engine = enum { tree, bytecode };

/// The engine in use; the tree walker until the bytecode machine passes every level.
pub var engine: Engine = .tree;

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

/// The parallel group whose do region is running.
pub const Group = struct {
    list: *std.ArrayList(*Started),
    cancel: bool,
    /// The addresses of the variables and elements given as outputs so far: one owner each (D-140).
    owned: *std.ArrayList(usize),
};

/// One call in progress: what runs and from which line it was called.
pub const Frame = struct { kind: []const u8, name: []const u8, call_line: u32, file: []const u8 = "" };

// @decision D-114
/// One message of `log_err` or `log_wrn`.
pub const LogMsg = struct { is_error: bool, line: u32, unit: []const u8, level: usize, text: []const u8 };

/// How the VM asks to look into the slot between two statements.
pub const Hook = struct {
    ctx: *anyopaque,
    /// Returns true when the run must stop.
    poll: *const fn (ctx: *anyopaque, steps: usize, line: u32) bool,
};

/// How the debugger (debugger.zig) is called before each statement of the main task.
pub const DebugHook = struct {
    ctx: *anyopaque,
    before: *const fn (ctx: *anyopaque, it: *Interp, n: *const Node) Signal!void,
};

/// The end of a run.
pub const Outcome = struct {
    /// Exit status: 0, 1 panic, 2 failed expect, 4 raise (D-055).
    code: u8 = 0,
    stopped: bool = false,
};





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
    /// The registers of the bytecode machine and how many are in use (the roots of a trace); empty with the tree walker.
    bc_stack: []Value = &.{},
    bc_top: usize = 0,
    /// The pc (relative to `main`) of the main frame when the last error left the machine: the failing statement for `recover`.
    bc_main_pc: u32 = 0,
    /// The exit code that `over <code>;` or `exit <code>;` gave; the program ends with it when nothing worse happens.
    exit_code: u8 = 0,
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
    /// `-p name=value`: the arguments of `process main` given by name (cmdargs.zig).
    script_params: []const ScriptParam = &.{},
    /// The extension methods declared outside a class (D-040).
    exts: std.ArrayList(*const Node) = .empty,
    /// The `adopt Trait for Type` declarations: `x is Trait` is true for a value of the type (CLS-15).
    adopted: std.ArrayList(struct { ty: []const u8, trait: *Class }) = .empty,
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

    /// A new scratch memory for an interpreter.
    pub fn newScratch(a: std.mem.Allocator) Signal!*Scratch {
        const sc = try a.create(Scratch);
        sc.* = .{ .parent = std.heap.page_allocator };
        return sc;
    }

    /// Give back the memory the interpreter took outside its arena.
    pub fn deinit(it: *Interp) void {
        it.scratch.deinit();
        it.h.deinit();
        it.scope_stack.deinit(it.g);
    }

    /// Mark what the interpreter reaches without the heap: its scopes (the roots of a trace).
    pub fn roots(ctx: *anyopaque, h: *Heap) void {
        const it: *Interp = @ptrCast(@alignCast(ctx));
        h.markFrom(&it.global.hdr);
        h.markFrom(&it.unit.hdr);
        h.markFrom(&it.scope.hdr);
        if (it.proc_scope) |p| h.markFrom(&p.hdr);
        for (it.scope_stack.items) |sc| h.markFrom(&sc.hdr);
        const b = it.base();
        for (b.bc_stack[0..b.bc_top]) |v| h.markValue(v);
        var mods = it.loaded.valueIterator();
        while (mods.next()) |m| h.markFrom(&m.*.scope.hdr);
    }

    /// Define the names every unit owns: `$epsilon` and `_` (the constants are in the prelude).
    pub fn boot(it: *Interp) Signal!void {
        try it.define("$epsilon", .{ .real = 1e-9 }, false);
        try it.define("_", .nil, false);
    }

    // @eve-impl `$OS_PWD`: the working folder of the machine when the run starts; read-only (CMD-05, D-202)
    // @spec spec/semantics/variables.md
    // @test a93_os_pwd
    /// Called once `io` is known (the interpreter is made before it).
    pub fn defineOsPwd(it: *Interp) Signal!void {
        const io = it.io orelse return;
        const here = std.process.currentPathAlloc(io, it.t) catch return;
        try it.define("$OS_PWD", try it.newStr(here), true);
    }

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
        const types = [_][]const u8{ "Integer", "Natural", "Real", "Symbol", "Rune", "String", "Text", "Logic", "List", "Array", "DataSet", "HashMap", "DataMap", "Byte", "Short", "Huge", "Float", "Decimal", "Rational", "Complex", "Duration", "Date", "Time", "Zone", "DateTime", "Instant", "Secret", "Table", "database", "csv", "json", "txt", "fs", "time", "secret", "checkpoint", "crypto", "os", "net", "Listener", "Socket" };
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
            .{ "$wrn_deprecated", 5 }, .{ "$wrn_truncate", 6 }, .{ "$wrn_unused", 7 }, .{ "$wrn_hidden", 8 },
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

    /// Raise an error with a code and a message.
    pub fn failWith(it: *Interp, code: u8, comptime fmt: []const u8, args: anytype) Signal {
        const msg = std.fmt.allocPrint(it.a, fmt, args) catch return error.OutOfMemory;
        return it.failMsg(code, msg);
    }

    /// Raise an error whose message is already made (the database layer formats its own).
    pub fn failMsg(it: *Interp, code: u8, msg: []const u8) Signal {
        const trace = try it.traceText();
        it.reports.append(it.a, .{ .line = it.line, .code = code, .message = msg, .job = it.current_job, .trace = trace, .file = if (it.frames.items.len > 0) it.frames.items[it.frames.items.len - 1].file else "" }) catch return error.OutOfMemory;
        it.err_code = code;
        return error.Raise;
    }

    /// The stack of calls as text, innermost first (D-113).
    pub fn traceText(it: *Interp) Signal![]const u8 {
        var buf: std.ArrayList(u8) = .empty;
        var line = it.line;
        var i = it.frames.items.len;
        while (i > 0) : (i -= 1) {
            const f = it.frames.items[i - 1];
            try appendFmt(&buf, it.a, "  line {d} in {s} {s}{s}{s}\n", .{ line, f.kind, f.name, if (f.file.len > 0) " of " else "", f.file });
            line = f.call_line;
        }
        if (it.current_job.len > 0) try appendFmt(&buf, it.a, "  in job {s}\n", .{it.current_job});
        return buf.items;
    }

    pub fn fail(it: *Interp, comptime fmt: []const u8, args: anytype) Signal {
        return it.failWith(err_raise, fmt, args);
    }

    // ---- scopes ---------------------------------------------------------------------------

    /// Declare `name` in the current scope (a second declaration replaces the first).
    pub fn define(it: *Interp, name: []const u8, v: Value, constant: bool) Signal!void {
        // a name declared again in the same scope (a loop variable, a `new` in a loop body) keeps its
        // variable when nobody else holds it: the value is replaced, nothing is allocated
        for (it.scope.binds.items) |b| {
            if (b.v.hdr.rc == 1 and value.nameEql(b.name, name)) {
                it.setVar(b.v, v);
                b.v.constant = constant;
                return;
            }
        }
        const cell = try it.h.make(Var, .{ .value = v, .constant = constant });
        Heap.retain(v);
        try it.bind(name, cell);
    }

    pub fn bind(it: *Interp, name: []const u8, cell: *Var) Signal!void {
        Heap.retainVar(cell);
        for (it.scope.binds.items) |*b| {
            if (value.nameEql(b.name, name)) {
                const old = b.v;
                b.v = cell;
                it.h.releaseVar(old);
                return;
            }
        }
        try it.scope.binds.append(it.g, .{ .name = name, .v = cell });
    }

    /// Store `v` in the variable `cell`.
    pub fn setVar(it: *Interp, cell: *Var, v: Value) void {
        Heap.retain(v);
        it.h.release(cell.value);
        cell.value = v;
    }

    /// Store `v` in an element of a list (or any counted cell).
    pub fn setCell(it: *Interp, c: *Value, v: Value) void {
        Heap.retain(v);
        it.h.release(c.*);
        c.* = v;
    }

    // @eve-impl `$NAME`: any operating system environment variable, read when the name is used (a String)
    // @spec spec/semantics/variables.md
    // @test a94_env_variable
    pub fn lookup(it: *Interp, name: []const u8) Signal!Value {
        if (it.scope.find(name)) |v| return v.value;
        if (name.len > 1 and name[0] == '$') {
            const z = try it.t.dupeSentinel(u8, name[1..], 0);
            if (std.c.getenv(z.ptr)) |got| return try it.newStr(std.mem.span(got));
        }
        return it.fail("undefined name '{s}'", .{name});
    }

    pub fn pushScope(it: *Interp) Signal!*Scope {
        return it.enterScope(try it.newScope(it.scope));
    }

    /// A new scope below `parent` (none for the scope of an aspect or a module).
    pub fn newScope(it: *Interp, parent: ?*Scope) Signal!*Scope {
        const s = try it.h.make(Scope, .{ .parent = parent });
        if (parent) |p| Heap.retainScope(p);
        return s;
    }

    /// Make `s` the current scope; returns the scope to come back to.
    pub fn enterScope(it: *Interp, s: *Scope) Signal!*Scope {
        Heap.retainScope(s);
        try it.scope_stack.append(it.g, it.scope);
        const saved = it.scope;
        it.scope = s;
        return saved;
    }

    /// Come back to `saved` and let the scope that ends go.
    pub fn leaveScope(it: *Interp, saved: *Scope) void {
        const s = it.scope;
        it.scope = saved;
        _ = it.scope_stack.pop();
        it.h.releaseScope(s);
    }

    /// Remember the scope of the last process that ran (for the introspection commands).
    pub fn setProc(it: *Interp, s: ?*Scope) void {
        if (s) |x| Heap.retainScope(x);
        if (it.proc_scope) |old| it.h.releaseScope(old);
        it.proc_scope = s;
    }

    // ---- regions and safe points (heap.zig) -------------------------------------------------------

    /// Start a region (a block, a loop, a process).
    pub fn regionIn(it: *Interp) void {
        if (it.root == null) it.h.pushRegion();
    }

    /// Leave the region.
    pub fn regionOut(it: *Interp) void {
        if (it.root == null) it.h.popRegion();
    }

    /// A safe point: a statement or a pass of a loop has ended, its temporaries are gone.
    pub fn safe(it: *Interp) void {
        if (it.root == null) it.h.safePoint();
    }

    // ---- counted containers ---------------------------------------------------------------------

    pub fn listAppend(it: *Interp, l: *List, v: Value) Signal!void {
        try l.items.append(it.g, v);
        Heap.retain(v);
    }

    pub fn listAppendSlice(it: *Interp, l: *List, vs: []const Value) Signal!void {
        try l.items.appendSlice(it.g, vs);
        for (vs) |v| Heap.retain(v);
    }

    pub fn listInsert(it: *Interp, l: *List, i: usize, v: Value) Signal!void {
        try l.items.insert(it.g, i, v);
        Heap.retain(v);
    }

    pub fn listInsertSlice(it: *Interp, l: *List, i: usize, vs: []const Value) Signal!void {
        try l.items.insertSlice(it.g, i, vs);
        for (vs) |v| Heap.retain(v);
    }

    pub fn listRemove(it: *Interp, l: *List, i: usize) Value {
        const v = l.items.orderedRemove(i);
        it.h.release(v);
        return v;
    }

    pub fn listPop(it: *Interp, l: *List) Value {
        const v = l.items.pop().?;
        it.h.release(v);
        return v;
    }

    pub fn newRange(it: *Interp, r: Range) Signal!*Range {
        return it.h.make(Range, r);
    }

    pub fn newDomain(it: *Interp, d: Domain) Signal!*Domain {
        return it.h.make(Domain, d);
    }

    pub fn newFunc(it: *Interp, node: *const Node, closure: *Scope) Signal!*Func {
        const f = try it.h.make(Func, .{ .node = node, .closure = closure });
        Heap.retainScope(closure);
        return f;
    }

    pub fn newMap(it: *Interp) Signal!*Map {
        return it.h.make(Map, .{});
    }

    /// A new heap string with a copy of `bytes`.
    pub fn newStr(it: *Interp, bytes: []const u8) Signal!Value {
        return .{ .str = try it.h.str(bytes) };
    }

    /// The pinned heap copy of a text that never changes (a literal, a constant word).
    pub fn staticStr(it: *Interp, bytes: []const u8) Signal!Value {
        return .{ .str = try it.h.static(bytes) };
    }

    /// Let go of the variables the arguments own.
    pub fn dropArgs(it: *Interp, args: []const Arg) void {
        for (args) |a| if (a.cell != null) {
            if (a.ref) |r| it.h.releaseVar(r);
        };
    }

    // ---- values: construction and inspection ----------------------------------------------

    pub fn newList(it: *Interp, items: []const Value, array: bool) Signal!*List {
        const l = try it.h.make(List, .{ .array = array });
        try it.listAppendSlice(l, items);
        return l;
    }

    pub fn newObject(it: *Interp) Signal!*Object {
        return it.h.make(Object, .{});
    }

    pub const typeName = value.typeName;

    pub const isInt = value.isInt;

    pub const intOf = value.intOf;

    pub const realOf = value.realOf;

    pub const decOf = value.decOf;
    pub const ratOf = value.ratOf;
    pub const cpxOf = value.cpxOf;
    pub const msOf = value.msOf;

    pub fn truth(it: *Interp, v: Value) Signal!bool {
        return switch (v) {
            .bool => |b| b,
            else => it.fail("a Logic value is expected, found {s}", .{typeName(v)}),
        };
    }

    /// Order two values of the same family (numbers, strings, symbols).
    pub fn order(it: *Interp, a: Value, b: Value) Signal!std.math.Order {
        if (isInt(a) and isInt(b)) return std.math.order(intOf(a), intOf(b));
        if (a == .dec or b == .dec) if (decOf(a)) |x| if (decOf(b)) |y| return decimal.order(x, y);
        if (a == .dur and b == .dur) return std.math.order(a.dur, b.dur);
        if (a == .date and b == .date) return std.math.order(a.date, b.date);
        if (a == .time and b == .time) return std.math.order(a.time, b.time);
        if (a == .rat or b == .rat) if (ratOf(a)) |x| if (ratOf(b)) |y| return rational.order(x, y);
        if (a == .instant and b == .instant) return std.math.order(a.instant, b.instant);
        if ((a == .dtm or a == .instant) and (b == .dtm or b == .instant)) {
            const x: i64 = if (a == .dtm) a.dtm.us else a.instant;
            const y: i64 = if (b == .dtm) b.dtm.us else b.instant;
            return std.math.order(x, y);
        }
        if (realOf(a)) |x| if (realOf(b)) |y| return std.math.order(x, y);
        if (a == .str and b == .str) return std.mem.order(u8, a.str, b.str);
        if (a == .sym and b == .sym) return std.math.order(a.sym, b.sym);
        return it.fail("cannot compare {s} with {s}", .{ typeName(a), typeName(b) });
    }

    pub const eq = value.eq;

    pub const same = value.same;

    pub const fieldOf = value.fieldOf;

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

    pub fn setOf(it: *Interp, v: Value) Signal!*List {
        const s = try it.h.make(List, .{});
        switch (v) {
            .list, .set => |l| for (l.elems()) |e| try it.setAdd(s, e),
            else => return it.fail("a collection is expected, found {s}", .{typeName(v)}),
        }
        return s;
    }

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
    pub const negate = part_expr.negate;
    pub const augmentValue = part_stmt.augmentValue;
    pub const applyOp = part_expr.applyOp;
    pub const exitCodeOfStmt = part_stmt.exitCodeOfStmt;
    pub const mapMethod = part_collections.mapMethod;
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
    pub const runDestructor = part_calls.runDestructor;

    /// The `Finalizer` of the heap (CLS-14).
    pub fn finalizeObject(ctx: *anyopaque, obj: *Object, cls: *Class) void {
        const it: *Interp = @ptrCast(@alignCast(ctx));
        it.runDestructor(obj, cls);
    }
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
    pub const ratOp = part_datatypes.ratOp;
    pub const fastCodeOf = part_calls.fastCodeOf;
    pub const cpxOp = part_datatypes.cpxOp;
    pub const timeOp = part_datatypes.timeOp;
    pub const decFromReal = part_datatypes.decFromReal;
    pub const fromSqlText = part_datatypes.fromSqlText;
    pub const makeSecret = part_datatypes.makeSecret;
    pub const isGenerator = part_datatypes.isGenerator;
    pub const isSecret = part_datatypes.isSecret;
    pub const secretObject = part_datatypes.secretObject;
    pub const secretGet = part_datatypes.secretGet;
    pub const runRoot = part_datatypes.runRoot;
};

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

test "a free script prints, computes and interpolates" {
    var buf: [256]u8 = undefined;
    const r = try runSource("primary aspect t is\n  process main is\n    new a := 2;\n    let a += 3;\n    expect a == 5;\n    print \"a = {a}\";\n  return;\nend t;\n", &buf);
    try std.testing.expectEqualStrings("a = 5\n", r.out);
    try std.testing.expectEqual(@as(u8, 0), r.code);
}

test "a failed expect exits with 2 and recover catches a raise" {
    var buf: [256]u8 = undefined;
    const r = try runSource("primary aspect d is process main is print \"x\"; expect 1 == 2; return; end d;", &buf);
    try std.testing.expectEqualStrings("x\n", r.out);
    try std.testing.expectEqual(@as(u8, 2), r.code);
    const s = try runSource("primary aspect d is process main is raise \"boom\"; recover print $error.message; return; end d;", &buf);
    try std.testing.expectEqualStrings("boom\n", s.out);
    try std.testing.expectEqual(@as(u8, 0), s.code);
}

test "regular expressions" {
    try std.testing.expect(Interp.regexMatch("/^this/", "this is"));
    try std.testing.expect(Interp.regexMatch("/l.ke$/", "like"));
    try std.testing.expect(Interp.regexMatch("/abc/i", "xABCx"));
    try std.testing.expect(!Interp.regexMatch("/^not/", "this is not"));
    try std.testing.expect(Interp.regexMatch("/c[0-9]+/", "abc123"));
}

// @decision D-142
// @decision D-144
test "durations are milliseconds, split and batch cut a list" {
    try std.testing.expectEqual(@as(?i64, 30_000_000), duration.parseLiteral("30s"));
    try std.testing.expectEqual(@as(?i64, 10_000), duration.parseLiteral("10ms"));
    try std.testing.expectEqual(@as(?i64, null), duration.parseLiteral("42"));
    var buf: [256]u8 = undefined;
    const r = try runSource("primary aspect t is\n  process main is\n    new l := (1, 2, 3, 4, 5);\n    print l.split(2);\n    print l.batch(2);\n  return;\nend t;\n", &buf);
    try std.testing.expectEqualStrings("((1,2,3),(4,5))\n((1,2),(3,4),(5))\n", r.out);
}

test "a loop frees what each pass makes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var diag: @import("evecp").lexer.Diag = .{};
    const src = "primary aspect t is\n  process main is\n    new total := 0;\n    new s := \"\";\n    new parts := ();\n    for i in (1..10000) do\n      let s := \"item {i}\";\n      let parts := (i, i + 1);\n      let total += parts.length();\n    done;\n    print total;\n  return;\nend t;\n";
    const root = try @import("evecp").parser.parse(arena.allocator(), src, &diag);
    var buf: [64]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var it = try Interp.init(arena.allocator(), &w);
    defer it.deinit();
    _ = it.run(root);
    try std.testing.expectEqualStrings("20000\n", w.buffered());
    try std.testing.expect(it.h.stats.made > 20_000);
    // what stays alive is the pinned names of the prelude (a Var each: types, modules, error codes) and the scopes, not the 20,000 values of the loop
    try std.testing.expect(it.h.stats.live < 150);
}
