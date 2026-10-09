//! The interpreter: walks the syntax tree (ast.zig) and executes it. It is a plain "tree walker":
//! `exec` runs a statement, `eval` computes an expression, both by looking at the `tag` of the node.
//!
//! Control flow (break, next, over, raise, retry...) is carried by Zig errors (`Signal`): a `raise`
//! unwinds the Zig call stack up to the `recover` of the process, exactly as an exception would.
//! The values of the script live in the heap (heap.zig) and are reference counted: every place that
//! stores a value (a variable, an element, an entry, a field) counts it with `retain` and lets the old
//! one go with `release`. The syntax tree, the classes and the messages stay in the arena of the run.
const std = @import("std");
const Io = std.Io;
const ast = @import("ast.zig");
const task = @import("task.zig");
const Scratch = @import("scratch.zig").Scratch;
const heap = @import("heap.zig");
const Heap = heap.Heap;
const Obj = heap.Obj;
const Node = ast.Node;

// Zig tip: an error set is a list of names; `||` merges sets. Every function that can fail while
// running a script returns `Signal!T`. Recursive functions (`eval` calls itself through its
// helpers) must name their error set: Zig cannot infer it for a cycle. The first names are
// control flow, the last two are the failures of the allocator and of the output writer.
/// What interrupts the normal flow of a script.
pub const Signal = error{ Raise, Break, Skip, Over, Exit, StopJob, Panic, Retry, Resume, Abort, Stop, Cancel, OutOfMemory, WriteFailed };

// Zig tip: a `union(enum)` is a "tagged union": a value that is exactly one of several kinds, and
// remembers which. `switch (v)` must handle every kind. `.int => |n|` captures the payload. Kinds
// that point to a struct (`*List`) are shared: copying the `Value` copies the pointer, so two
// variables see the same list. Kinds such as `int` and `real` are copied. This is Eve's rule:
// "`:=` shares a collection, native values are always copied" (D-049). A field cannot be called
// `null` in Zig (a keyword), hence `nil`.
/// Any value of an Eve script.
pub const Value = union(enum) {
    nil,
    bool: bool,
    int: i64,
    /// Natural: written in hexadecimal or binary.
    nat: i64,
    byte: i64,
    short: i64,
    huge: i64,
    real: f64,
    float: f64,
    dec: f64,
    /// A Symbol: one Unicode code point.
    sym: u21,
    str: []const u8,
    /// A List `( )` or an Array `[ ]` (see `List.array`).
    list: *List,
    /// A DataSet `{ }`: a List kept sorted, without duplicates.
    set: *List,
    map: *Map,
    object: *Object,
    class: *Class,
    func: *Func,
    range: *Range,
    domain: *Domain,
    /// The value of `Integer`, `String`, ... and of `type(x)`.
    typ: []const u8,
    /// A module that an import brought in: `counter.tick()` reaches its exported members (modules.md).
    module: *Module,
    /// A channel that connects the tasks of a parallel group (D-141).
    chan: *Channel,
};

// Zig tip: a channel is a queue with a fixed capacity, shared by pointer: every task that receives it
// with `@` sees the same one. It needs no lock, because only the task holding the baton runs (task.zig);
// a full or empty channel makes the task give the baton away and try again later.
/// `Channel(:T)(capacity: n, senders: m)`: values in order, closed after `senders` closes (D-141).
pub const Channel = struct {
    hdr: Obj = .{ .kind = .chan },
    /// The name of the variable that created it: the error messages name it.
    name: []const u8 = "",
    buf: std.ArrayList(Value) = .empty,
    capacity: usize,
    senders: usize = 1,
    closes: usize = 0,
    closed: bool = false,
};

// Zig tip: a module is loaded once (D-068), so one `Module` exists per module file for the whole run. It
// owns a `Scope` of its own: the private variables of the module live there and the functions of the
// module close over it, so only they can change them. `node` is the parsed tree, kept for its
// `export` list and its regions.
/// A loaded module: its scope, its tree and its name.
pub const Module = struct { name: []const u8, node: *const Node, scope: *Scope };

// Zig tip: a `struct` groups named fields (and functions); `pub` makes a name visible to other
// files; a field with `= value` has a default, so `.{ ... }` need not give it.
/// A list, an array, a set, or a view of a part of another list (a slice `v[2..3]`).
pub const List = struct {
    hdr: Obj = .{ .kind = .list },
    items: std.ArrayList(Value) = .empty,
    array: bool = false,
    /// A view shares the storage of `base`: `off` and `len` say which part.
    base: ?*List = null,
    off: usize = 0,
    len: usize = 0,

    // Zig tip: a method that returns a slice into another struct's memory is a "view": no copy.
    // `b.elems()[a..b]` slices the slice. Writing through it changes the base list.
    /// The elements, whether the list owns them or is a view.
    pub fn elems(l: *List) []Value {
        if (l.base) |b| return b.elems()[l.off .. l.off + l.len];
        return l.items.items;
    }
};

pub const Entry = struct { key: Value, val: Value };
// Zig tip: `hdr: Obj = .{ .kind = .map }` is the header every heap object starts with (heap.zig, `Obj`):
// a field with a default value, so the heap can build the map with `.{}` and then fill the header in.
/// A sorted map: the entries are kept in key order.
pub const Map = struct { hdr: Obj = .{ .kind = .map }, entries: std.ArrayList(Entry) = .empty };

pub const Field = struct { name: []const u8, val: Value };
// Zig tip: `Object` relies on the same Zig feature as `Map` above: see the tip there.
/// An object: named attributes in the order they were created; `class` is set for `new C(...)`.
pub const Object = struct { hdr: Obj = .{ .kind = .object }, class: ?*Class = null, fields: std.ArrayList(Field) = .empty };

// Zig tip: `Class` relies on the same Zig feature as `List` above: see the tip there.
/// A class. `node` is null for the built-in `Object`. An ordinal class keeps its named values in `ord`.
pub const Class = struct {
    name: []const u8,
    node: ?*const Node = null,
    ordinal: bool = false,
    parent: ?*Class = null,
    ord: std.ArrayList(Field) = .empty,
    /// The traits the class adopts (D-145); a trait itself is a `Class` with `trait` set.
    traits: std.ArrayList(*Class) = .empty,
    trait: bool = false,
};

// Zig tip: a `var` at file level is a global with a fixed address for the whole program; `&library_traits[0]`
// is a pointer that stays valid, so every scope can point to the same trait. They hold no allocated memory
// (no node, empty lists), so sharing them between runs is safe.
/// The traits of the library: `Printable`, `Comparable`, `Iterable`, `Stream` (D-145).
var library_traits = [_]Class{
    .{ .name = "Printable", .trait = true },
    .{ .name = "Comparable", .trait = true },
    .{ .name = "Iterable", .trait = true },
    .{ .name = "Stream", .trait = true },
};

// Zig tip: `?*Class` may be null (an object made without a class); `orelse return false` answers for it.
/// Does the class, or one of its ancestors, adopt the trait called `name`?
fn adopts(cls: ?*Class, name: []const u8) bool {
    var cur: ?*Class = cls orelse return false;
    while (cur) |k| : (cur = k.parent) {
        for (k.traits.items) |tr| if (std.mem.eql(u8, tr.name, name)) return true;
    }
    return false;
}

// Zig tip: `Func` relies on the same Zig feature as `Map` above: see the tip there.
/// A function, method or lambda together with the scope it was created in.
pub const Func = struct { hdr: Obj = .{ .kind = .func }, node: *const Node, closure: *Scope };

// Zig tip: `Range` relies on the same Zig feature as `Map` above: see the tip there.
/// An integer range with both ends included; `(1..<5)` is stored as 1 to 4.
pub const Range = struct { hdr: Obj = .{ .kind = .range }, lo: i64, hi: i64, step: i64 = 1, sym: bool = false };

// Zig tip: a range that is not a plain run of integers is a "domain": real limits, an open end
// (`null` is no limit), a limit that is excluded, a step that sets the precision (`(0..1)(0.01)`).
// An optional `?f64` is a float or nothing.
/// A domain of values (D-022, D-079): `x in domain` asks whether the value is inside.
pub const Domain = struct { hdr: Obj = .{ .kind = .domain }, lo: ?f64 = null, hi: ?f64 = null, lo_excl: bool = false, hi_excl: bool = false, step: ?f64 = null };

// Zig tip: `Var` relies on the same Zig feature as `Map` above: see the tip there.
/// A variable. It is a separate struct so that a by-reference parameter can share it.
pub const Var = struct { hdr: Obj = .{ .kind = .variable }, value: Value, constant: bool = false };
pub const Binding = struct { name: []const u8, v: *Var };
// Zig tip: `Scope` relies on the same Zig feature as `List` above: see the tip there.
pub const Scope = struct {
    hdr: Obj = .{ .kind = .scope },
    binds: std.ArrayList(Binding) = .empty,
    parent: ?*Scope = null,

    // Zig tip: `?*Var` is a pointer that may be null. A `while (cur) |s|` loop walks the chain of
    // parent scopes: `cur = s.parent` moves one level up and the loop ends at the null.
    /// The variable called `name` in this scope or the enclosing ones.
    pub fn find(sc: *Scope, name: []const u8) ?*Var {
        var cur: ?*Scope = sc;
        while (cur) |s| : (cur = s.parent) {
            for (s.binds.items) |b| {
                if (std.mem.eql(u8, b.name, name)) return b.v;
            }
        }
        return null;
    }
};

// Zig tip: `Report` relies on the same Zig feature as `List` above: see the tip there.
/// One error met while running: kept for the reports (`errors` command) even when `recover` handles it.
pub const Report = struct {
    line: u32,
    code: u8,
    message: []const u8,
    job: []const u8,
    handled: bool = false,
    /// The calls that led to the error, innermost first, one `line n in kind name` per line (D-113).
    trace: []const u8 = "",
    /// A ParallelError: the errors of the failed tasks, in the order of `start` (D-140).
    errors: ?*List = null,
    /// A ParallelError: how many tasks `on error cancel` stopped.
    cancelled: i64 = 0,
    /// A ParallelError: one line per failed task, printed under the error when nobody recovers it.
    details: []const u8 = "",
};

// Zig tip: an argument passed as `@s[i]` is one element of a list. A parameter binds to a `*Var`, so
// the element is copied into a fresh `Var`, and `cell` remembers where it came from: when the call or
// the task ends, the value is written back there (`writeBack`).
/// One argument of a call, `apply`, `start` or `spawn`.
const Arg = struct { name: []const u8 = "", value: Value, ref: ?*Var = null, cell: ?*Value = null };

// Zig tip: a task needs its own interpreter (`child`): its scope, its call stack, its output buffer.
// `Started` keeps everything the parent needs after the task ended: the outcome, the arguments to
// write back, the output to flush at `done`. `report` is copied from the child, because the child's
// list of reports is gone with it from the parent's point of view.
/// A started aspect or a spawned subprogram, seen from the parent.
const Started = struct {
    t: *task.Task,
    /// The aspect name, or the subprogram name of a spawned task.
    label: []const u8,
    aspect: ?*const Node = null,
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

// Zig tip: a group is a list of the tasks started in it plus its policy; the interpreter keeps a
// pointer to the group whose `do` region is running, so `start` knows where to add the task.
/// The parallel group whose do region is running.
const Group = struct {
    list: *std.ArrayList(*Started),
    cancel: bool,
    /// The addresses of the variables and elements given as outputs so far: one owner each (D-140).
    owned: *std.ArrayList(usize),
};

// Zig tip: a small struct for the stack of calls. `kind` is a word that is printed (`function`,
// `procedure`, `method`, `aspect`, `driver`) and `call_line` is the line, in the caller, where
// this call was made: with it the trace can tell on which line each unit was running.
/// One call in progress: what runs and from which line it was called.
const Frame = struct { kind: []const u8, name: []const u8, call_line: u32 };

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

// Zig tip: `Outcome` relies on the same Zig feature as `List` above: see the tip there.
/// The end of a run.
pub const Outcome = struct {
    /// Exit status: 0, 1 panic, 2 failed expect, 4 raise (D-055).
    code: u8 = 0,
    stopped: bool = false,
};

const err_raise = 4;
const err_expect = 2;
const err_assert = 3;
const err_index = 10;
const err_key = 11;
const err_divide = 12;
const err_overflow = 13;


// Zig tip: `Interp` relies on the same Zig feature as `List` above: see the tip there.
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
    /// The scope of the built-in names (`True`, the type names, the error codes): made once per run by
    /// the driver's interpreter and the parent of every unit (the driver, each aspect call, each module).
    prelude: ?*Scope = null,
    out: *Io.Writer,
    global: *Scope,
    scope: *Scope,
    hook: ?Hook = null,
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
    /// driver's interpreter keeps the set (`base()`), so the tasks share it.
    text_ptrs: std.AutoHashMapUnmanaged(usize, void) = .empty,
    /// The command-line arguments after the script name: the arguments of `process main`.
    script_args: []const []const u8 = &.{},
    /// The extension methods declared outside a class (D-040).
    exts: std.ArrayList(*const Node) = .empty,
    /// The `defer` statements registered and not yet run, oldest first (D-081).
    defers: std.ArrayList(*const Node) = .empty,
    /// The scope of the script being run: the driver's globals, or the scope of one aspect call.
    /// The functions and classes of that script close over it.
    unit: *Scope,
    /// The aspects the driver applies, read and checked before the run (project.zig).
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
    /// The task this interpreter runs: the root for the driver.
    me: ?*task.Task = null,
    /// For the interpreter of a task: the driver's interpreter, which owns the modules.
    root: ?*Interp = null,
    /// The name of the task, for the messages of a deadlock: the aspect or the subprogram.
    task_name: []const u8 = "driver",
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
    fn newScratch(a: std.mem.Allocator) Signal!*Scratch {
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
    fn roots(ctx: *anyopaque, h: *Heap) void {
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
    fn boot(it: *Interp) Signal!void {
        try it.define("$epsilon", .{ .real = 1e-9 }, false);
        try it.define("_", .nil, false);
    }

    // Zig tip: `for (xs) |x| ...` walks a slice; `for (xs, 0..) |x, i|` also gives the index. The prelude is
    // pinned: it lives to the end of the run, and the units count it as their parent without freeing it.
    /// The scope of the built-in names, made on first use: `True`, `False`, `Null`, the types, `Object`.
    fn preludeScope(it: *Interp) Signal!*Scope {
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
        const types = [_][]const u8{ "Integer", "Natural", "Real", "Symbol", "Rune", "String", "Text", "Logic", "List", "Array", "DataSet", "HashMap", "DataMap", "Byte", "Short", "Huge", "Float", "Decimal" };
        for (types) |t| try it.define(t, .{ .typ = t }, true);
        try it.define("Channel", .{ .typ = "Channel" }, true);
        // the library traits of version 0.3 (D-145): one shared value each, so `x is Printable` means the
        // same in the driver, its aspects and its modules
        for (&library_traits) |*tr| try it.define(tr.name, .{ .class = tr }, true);
        const codes = [_]struct { []const u8, i64 }{
            .{ "$err_panic", 1 },     .{ "$err_expect", 2 },    .{ "$err_assert", 3 },   .{ "$err_raise", 4 },
            .{ "$err_index", 10 },    .{ "$err_key", 11 },      .{ "$err_divide", 12 }, .{ "$err_overflow", 13 },
            .{ "$err_convert", 14 },  .{ "$err_parse", 15 },    .{ "$err_null", 16 },   .{ "$err_argument", 17 },
            .{ "$err_file", 20 },     .{ "$err_access", 21 },   .{ "$err_io", 22 },     .{ "$err_module", 30 },
            .{ "$err_process", 31 },  .{ "$err_memory", 40 },   .{ "$err_timeout", 41 }, .{ "$err_deadlock", 42 },
            .{ "$err_output", 43 },   .{ "$err_recursion", 44 }, .{ "$err_parallel", 45 }, .{ "$err_channel", 46 },
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
    fn failWith(it: *Interp, code: u8, comptime fmt: []const u8, args: anytype) Signal {
        const msg = std.fmt.allocPrint(it.a, fmt, args) catch return error.OutOfMemory;
        const trace = try it.traceText();
        it.reports.append(it.a, .{ .line = it.line, .code = code, .message = msg, .job = it.current_job, .trace = trace }) catch return error.OutOfMemory;
        it.err_code = code;
        return error.Raise;
    }

    // Zig tip: the trace is built from the stack of frames, walking it from the top (`while (i > 0) :
    // (i -= 1)` counts down, see check.zig). The innermost unit was running on `it.line`; the unit
    // below it was running on the line where it made the call, which the frame above remembers.
    /// The stack of calls as text, innermost first (D-113).
    fn traceText(it: *Interp) Signal![]const u8 {
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
    fn fail(it: *Interp, comptime fmt: []const u8, args: anytype) Signal {
        return it.failWith(err_raise, fmt, args);
    }

    // ---- scopes ---------------------------------------------------------------------------

    // Zig tip: `try f()` calls `f` and, when it returns an error, returns that error from this
    // function too.
    /// Declare `name` in the current scope (a second declaration replaces the first).
    fn define(it: *Interp, name: []const u8, v: Value, constant: bool) Signal!void {
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
    fn bind(it: *Interp, name: []const u8, cell: *Var) Signal!void {
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
    fn setVar(it: *Interp, cell: *Var, v: Value) void {
        Heap.retain(v);
        it.h.release(cell.value);
        cell.value = v;
    }

    // Zig tip: `setCell` relies on the same Zig feature as `setVar` above: see the tip there.
    /// Store `v` in an element of a list (or any counted cell).
    fn setCell(it: *Interp, c: *Value, v: Value) void {
        Heap.retain(v);
        it.h.release(c.*);
        c.* = v;
    }

    // Zig tip: `lookup` relies on the same Zig feature as `fail` above: see the tip there.
    fn lookup(it: *Interp, name: []const u8) Signal!Value {
        if (it.scope.find(name)) |v| return v.value;
        return it.fail("undefined name '{s}'", .{name});
    }

    // Zig tip: `pushScope` relies on the same Zig feature as `define` above: see the tip there.
    fn pushScope(it: *Interp) Signal!*Scope {
        return it.enterScope(try it.newScope(it.scope));
    }

    // Zig tip: a child scope counts its parent: the parent lives as long as any scope below it.
    /// A new scope below `parent` (none for the scope of an aspect or a module).
    fn newScope(it: *Interp, parent: ?*Scope) Signal!*Scope {
        const s = try it.h.make(Scope, .{ .parent = parent });
        if (parent) |p| Heap.retainScope(p);
        return s;
    }

    // Zig tip: the frame that enters a scope counts it, and `leaveScope` lets it go: a scope that no
    // closure captured is freed right there, with its variables. The scope that was current goes on
    // `scope_stack`, where the tracing collector finds it.
    /// Make `s` the current scope; returns the scope to come back to.
    fn enterScope(it: *Interp, s: *Scope) Signal!*Scope {
        Heap.retainScope(s);
        try it.scope_stack.append(it.g, it.scope);
        const saved = it.scope;
        it.scope = s;
        return saved;
    }

    // Zig tip: `leaveScope` relies on the same Zig feature as `enterScope` above: see the tip there.
    /// Come back to `saved` and let the scope that ends go.
    fn leaveScope(it: *Interp, saved: *Scope) void {
        const s = it.scope;
        it.scope = saved;
        _ = it.scope_stack.pop();
        it.h.releaseScope(s);
    }

    // Zig tip: `setProc` relies on the same Zig feature as `setVar` above: see the tip there.
    /// Remember the scope of the last process that ran (for the introspection commands).
    fn setProc(it: *Interp, s: ?*Scope) void {
        if (s) |x| Heap.retainScope(x);
        if (it.proc_scope) |old| it.h.releaseScope(old);
        it.proc_scope = s;
    }

    // ---- regions and safe points (heap.zig) -------------------------------------------------------

    // Zig tip: only the driver's interpreter keeps regions: tasks share the heap, and while they run
    // nothing is freed (see `Heap.pause`), so their blocks need no bookkeeping.
    /// Start a region (a block, a loop, a process).
    fn regionIn(it: *Interp) void {
        if (it.root == null) it.h.pushRegion();
    }

    // Zig tip: `regionOut` relies on the same Zig feature as `regionIn` above: see the tip there.
    /// Leave the region.
    fn regionOut(it: *Interp) void {
        if (it.root == null) it.h.popRegion();
    }

    // Zig tip: `safe` relies on the same Zig feature as `regionIn` above: see the tip there.
    /// A safe point: a statement or a pass of a loop has ended, its temporaries are gone.
    fn safe(it: *Interp) void {
        if (it.root == null) it.h.safePoint();
    }

    // ---- counted containers ---------------------------------------------------------------------

    // Zig tip: every change of a list goes through these helpers, which count what comes in and let
    // go of what goes out. A removed value is still usable until the next safe point.
    fn listAppend(it: *Interp, l: *List, v: Value) Signal!void {
        try l.items.append(it.g, v);
        Heap.retain(v);
    }

    // Zig tip: `listAppendSlice` relies on the same Zig feature as `listAppend` above: see the tip there.
    fn listAppendSlice(it: *Interp, l: *List, vs: []const Value) Signal!void {
        try l.items.appendSlice(it.g, vs);
        for (vs) |v| Heap.retain(v);
    }

    // Zig tip: `listInsert` relies on the same Zig feature as `listAppend` above: see the tip there.
    fn listInsert(it: *Interp, l: *List, i: usize, v: Value) Signal!void {
        try l.items.insert(it.g, i, v);
        Heap.retain(v);
    }

    // Zig tip: `listInsertSlice` relies on the same Zig feature as `listAppend` above: see the tip there.
    fn listInsertSlice(it: *Interp, l: *List, i: usize, vs: []const Value) Signal!void {
        try l.items.insertSlice(it.g, i, vs);
        for (vs) |v| Heap.retain(v);
    }

    // Zig tip: `listRemove` relies on the same Zig feature as `listAppend` above: see the tip there.
    fn listRemove(it: *Interp, l: *List, i: usize) Value {
        const v = l.items.orderedRemove(i);
        it.h.release(v);
        return v;
    }

    // Zig tip: `listPop` relies on the same Zig feature as `listAppend` above: see the tip there.
    fn listPop(it: *Interp, l: *List) Value {
        const v = l.items.pop().?;
        it.h.release(v);
        return v;
    }

    // Zig tip: `newRange` relies on the same Zig feature as `newObject` below: see the tip there.
    fn newRange(it: *Interp, r: Range) Signal!*Range {
        return it.h.make(Range, r);
    }

    // Zig tip: `newDomain` relies on the same Zig feature as `newObject` below: see the tip there.
    fn newDomain(it: *Interp, d: Domain) Signal!*Domain {
        return it.h.make(Domain, d);
    }

    // Zig tip: a function counts the scope it closes over: the scope lives as long as the function.
    fn newFunc(it: *Interp, node: *const Node, closure: *Scope) Signal!*Func {
        const f = try it.h.make(Func, .{ .node = node, .closure = closure });
        Heap.retainScope(closure);
        return f;
    }

    // Zig tip: `newMap` relies on the same Zig feature as `newObject` below: see the tip there.
    fn newMap(it: *Interp) Signal!*Map {
        return it.h.make(Map, .{});
    }

    // Zig tip: a string value always lives in the heap (heap.zig, `Str`): this copies scratch or arena
    // text into it.
    /// A new heap string with a copy of `bytes`.
    fn newStr(it: *Interp, bytes: []const u8) Signal!Value {
        return .{ .str = try it.h.str(bytes) };
    }

    // Zig tip: `staticStr` relies on the same Zig feature as `newStr` above: see the tip there.
    /// The pinned heap copy of a text that never changes (a literal, a constant word).
    fn staticStr(it: *Interp, bytes: []const u8) Signal!Value {
        return .{ .str = try it.h.static(bytes) };
    }

    // Zig tip: an argument `@s[i]` owns the variable made for it (see `elementRef`): once its value is
    // written back, the variable is let go.
    /// Let go of the variables the arguments own.
    fn dropArgs(it: *Interp, args: []const Arg) void {
        for (args) |a| if (a.cell != null) {
            if (a.ref) |r| it.h.releaseVar(r);
        };
    }

    // ---- values: construction and inspection ----------------------------------------------

    // Zig tip: `std.ArrayList(T)` is a growable array: it starts `.empty`, `append(allocator, x)`
    // adds, `.items` is the slice of what it holds.
    fn newList(it: *Interp, items: []const Value, array: bool) Signal!*List {
        const l = try it.h.make(List, .{ .array = array });
        try it.listAppendSlice(l, items);
        return l;
    }

    // Zig tip: `newObject` relies on the same Zig feature as `define` above: see the tip there.
    fn newObject(it: *Interp) Signal!*Object {
        return it.h.make(Object, .{});
    }

    // Zig tip: a `switch` is an expression: it must cover every case, or end with `else`, and the
    // compiler checks it.
    /// The name of the type of a value (what `type(x)` gives and `x is Integer` tests).
    pub fn typeName(v: Value) []const u8 {
        return switch (v) {
            .nil => "Null",
            .bool => "Logic",
            .int => "Integer",
            .nat => "Natural",
            .byte => "Byte",
            .short => "Short",
            .huge => "Huge",
            .real => "Real",
            .float => "Float",
            .dec => "Decimal",
            .sym => "Rune",
            .str => "String",
            .list => |l| if (l.array) "Array" else "List",
            .set => "DataSet",
            .map => "HashMap",
            .object => |o| if (o.class) |c| c.name else "Object",
            .class => "Class",
            .func => "Function",
            .range, .domain => "Range",
            .typ => "Type",
            .module => "Module",
            .chan => "Channel",
        };
    }

    // Zig tip: `isInt` relies on the same Zig feature as `fail` above: see the tip there.
    fn isInt(v: Value) bool {
        return v == .int or v == .nat or v == .byte or v == .short or v == .huge;
    }

    // Zig tip: `intOf` relies on the same Zig feature as `typeName` above: see the tip there.
    fn intOf(v: Value) i64 {
        return switch (v) {
            .int, .nat, .byte, .short, .huge => |n| n,
            else => 0,
        };
    }

    // Zig tip: builtin functions start with `@`: they are the compiler's own, such as conversions
    // (`@intCast`, `@as`) and `@min`/`@max`.
    fn realOf(v: Value) ?f64 {
        return switch (v) {
            .int, .nat, .byte, .short, .huge => |n| @floatFromInt(n),
            .real, .float, .dec => |r| r,
            else => null,
        };
    }

    // Zig tip: `truth` relies on the same Zig feature as `typeName` above: see the tip there.
    fn truth(it: *Interp, v: Value) Signal!bool {
        return switch (v) {
            .bool => |b| b,
            else => it.fail("a Logic value is expected, found {s}", .{typeName(v)}),
        };
    }

    // Zig tip: `std.math.order(a, b)` returns `.lt`, `.eq` or `.gt` for numbers. A function returns
    // an error union when it can fail: comparing a String with a List is a script error here.
    /// Order two values of the same family (numbers, strings, symbols).
    fn order(it: *Interp, a: Value, b: Value) Signal!std.math.Order {
        if (isInt(a) and isInt(b)) return std.math.order(intOf(a), intOf(b));
        if (realOf(a)) |x| if (realOf(b)) |y| return std.math.order(x, y);
        if (a == .str and b == .str) return std.mem.order(u8, a.str, b.str);
        if (a == .sym and b == .sym) return std.math.order(a.sym, b.sym);
        return it.fail("cannot compare {s} with {s}", .{ typeName(a), typeName(b) });
    }

    // Zig tip: `a orelse b` unwraps an optional: it gives `b` when `a` is null, and `b` may leave
    // the function with `return`.
    /// `==`: same value. Collections and objects compare their contents.
    fn eq(a: Value, b: Value) bool {
        if (isInt(a) and isInt(b)) return intOf(a) == intOf(b);
        if (realOf(a)) |x| if (realOf(b)) |y| return x == y;
        switch (a) {
            .nil => return b == .nil,
            .bool => |x| return b == .bool and b.bool == x,
            .sym => |x| return b == .sym and b.sym == x,
            .str => |x| return b == .str and std.mem.eql(u8, x, b.str),
            .list, .set => |x| {
                const y = switch (b) {
                    .list, .set => |l| l,
                    else => return false,
                };
                if ((a == .set) != (b == .set)) return false;
                const xs = x.elems();
                const ys = y.elems();
                if (xs.len != ys.len) return false;
                for (xs, ys) |p, q| if (!eq(p, q)) return false;
                return true;
            },
            .map => |x| {
                if (b != .map or x.entries.items.len != b.map.entries.items.len) return false;
                for (x.entries.items, b.map.entries.items) |p, q| if (!eq(p.key, q.key) or !eq(p.val, q.val)) return false;
                return true;
            },
            .object => |x| {
                if (b != .object or x.fields.items.len != b.object.fields.items.len) return false;
                for (x.fields.items) |f| {
                    const other = fieldOf(b.object, f.name) orelse return false;
                    if (!eq(f.val, other)) return false;
                }
                return true;
            },
            .class => |x| return b == .class and b.class == x,
            .func => |x| return b == .func and b.func == x,
            .range => |x| return b == .range and x.lo == b.range.lo and x.hi == b.range.hi and x.step == b.range.step,
            .domain => |x| {
                if (b != .domain) return false;
                const y = b.domain;
                return std.meta.eql(x.lo, y.lo) and std.meta.eql(x.hi, y.hi) and x.lo_excl == y.lo_excl and x.hi_excl == y.hi_excl and std.meta.eql(x.step, y.step);
            },
            .typ => |x| return b == .typ and std.mem.eql(u8, x, b.typ),
            else => return false,
        }
    }

    // Zig tip: `same` relies on the same Zig feature as `typeName` above: see the tip there.
    /// `is`: the same thing (identity for references, equality for values).
    fn same(a: Value, b: Value) bool {
        return switch (a) {
            .list, .set => |x| switch (b) {
                .list, .set => |y| x == y,
                else => false,
            },
            .map => |x| b == .map and b.map == x,
            .object => |x| b == .object and b.object == x,
            else => eq(a, b),
        };
    }

    // Zig tip: `fieldOf` relies on the same Zig feature as `newList` above: see the tip there.
    fn fieldOf(o: *Object, name: []const u8) ?Value {
        for (o.fields.items) |f| {
            if (std.mem.eql(u8, f.name, name)) return f.val;
        }
        return null;
    }

    // Zig tip: `setField` relies on the same Zig feature as `define` above: see the tip there.
    fn setField(it: *Interp, o: *Object, name: []const u8, v: Value) Signal!void {
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
    fn setAdd(it: *Interp, s: *List, v: Value) Signal!void {
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
    fn setOf(it: *Interp, v: Value) Signal!*List {
        const s = try it.h.make(List, .{});
        switch (v) {
            .list, .set => |l| for (l.elems()) |e| try it.setAdd(s, e),
            else => return it.fail("a collection is expected, found {s}", .{typeName(v)}),
        }
        return s;
    }

    // Zig tip: `contains` relies on the same Zig feature as `newList` above: see the tip there.
    fn contains(it: *Interp, coll: Value, v: Value) Signal!bool {
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
    fn clone(it: *Interp, v: Value) Signal!Value {
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

    // Zig tip: `x catch |e| ...` handles the error of a call on the spot, where `try` would pass it
    // up to the caller.
    fn utf8(it: *Interp, buf: *std.ArrayList(u8), cp: u21) Signal!void {
        var tmp: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(cp, &tmp) catch 1;
        try buf.appendSlice(it.t, tmp[0..n]);
    }

    // Zig tip: `buf.print(allocator, fmt, args)` formats straight into the growing list: no
    // temporary string is made. The allocator is a parameter because the list may live in the
    // scratch memory (text being built) or in the arena (a report that is kept).
    /// Append formatted text to `buf`, which grows in `mem`.
    fn appendFmt(buf: *std.ArrayList(u8), mem: std.mem.Allocator, comptime fmt: []const u8, args: anytype) Signal!void {
        try buf.print(mem, fmt, args);
    }

    // Zig tip: `show` writes the text of a value into a growable byte list. `quoted` is true inside
    // a collection, where strings and symbols are shown with their quotes. `inline else` is not
    // needed: every kind is listed. `for (items, 0..) |e, i|` loops with the index `i` too.
    /// Append the text `print` gives for `v`.
    fn show(it: *Interp, buf: *std.ArrayList(u8), v: Value, quoted: bool) Signal!void {
        switch (v) {
            .nil => try buf.appendSlice(it.t, "Null"),
            .bool => |b| try buf.appendSlice(it.t, if (b) "True" else "False"),
            .int, .nat, .byte, .short, .huge => |n| try appendFmt(buf, it.t, "{d}", .{n}),
            .real, .float, .dec => |r| try appendFmt(buf, it.t, "{d}", .{r}),
            .sym => |c| {
                if (quoted) try buf.append(it.t, '\'');
                try it.utf8(buf, c);
                if (quoted) try buf.append(it.t, '\'');
            },
            .str => |s| {
                if (quoted) try buf.append(it.t, '"');
                try buf.appendSlice(it.t, s);
                if (quoted) try buf.append(it.t, '"');
            },
            .list, .set => |l| {
                const open: u8 = if (v == .set) '{' else if (l.array) '[' else '(';
                const close: u8 = if (v == .set) '}' else if (l.array) ']' else ')';
                try buf.append(it.t, open);
                for (l.elems(), 0..) |e, i| {
                    if (i > 0) try buf.append(it.t, ',');
                    try it.show(buf, e, true);
                }
                try buf.append(it.t, close);
            },
            .map => |m| {
                try buf.append(it.t, '{');
                for (m.entries.items, 0..) |e, i| {
                    if (i > 0) try buf.append(it.t, ',');
                    try it.show(buf, e.key, true);
                    try buf.append(it.t, ':');
                    try it.show(buf, e.val, true);
                }
                try buf.append(it.t, '}');
            },
            .object => |o| {
                if (adopts(o.class, "Printable")) {
                    // a Printable object prints the text of its own `describe` method (D-145)
                    try it.show(buf, try it.callMethod(v, "describe", &.{}), false);
                    return;
                }
                try buf.append(it.t, '{');
                for (o.fields.items, 0..) |f, i| {
                    if (i > 0) try buf.append(it.t, ',');
                    try appendFmt(buf, it.t, "{s}:", .{f.name});
                    try it.show(buf, f.val, true);
                }
                try buf.append(it.t, '}');
            },
            .class => |c| try appendFmt(buf, it.t, "class {s}", .{c.name}),
            .func => try buf.appendSlice(it.t, "<function>"),
            .module => |m| try appendFmt(buf, it.t, "module {s}", .{m.name}),
            .chan => |c| try appendFmt(buf, it.t, "Channel {s}", .{c.name}),
            .range => |r| try appendFmt(buf, it.t, "({d}..{d})", .{ r.lo, r.hi }),
            .domain => try buf.appendSlice(it.t, "(domain)"),
            .typ => |t| try buf.appendSlice(it.t, t),
        }
    }

    // Zig tip: `text` relies on the same Zig feature as `define` above: see the tip there.
    // The text is in the scratch memory: it lives until the statement ends. A caller that keeps it
    // copies it with `persist`.
    pub fn text(it: *Interp, v: Value) Signal![]const u8 {
        var buf: std.ArrayList(u8) = .empty;
        try it.show(&buf, v, false);
        return buf.items;
    }

    // Zig tip: `a.dupe(u8, bytes)` copies a slice into memory of the allocator `a`: the copy stays
    // valid after the scratch memory of the statement is released.
    /// Keep `bytes` beyond the current statement: the string of a value.
    fn persist(it: *Interp, bytes: []const u8) Signal![]const u8 {
        return it.h.str(bytes);
    }

    // Zig tip: `persist2` relies on the same Zig feature as `persist` above: see the tip there.
    /// The persistent string `x ++ y`, built without an intermediate copy.
    fn persist2(it: *Interp, x: []const u8, y: []const u8) Signal![]const u8 {
        return it.h.str2(x, y);
    }

    // ---- formats of the interpolation -----------------------------------------------------

    // Zig tip: a plain `fn` at file level; without `pub` it is private to this file, and its
    // parameters are read-only.
    fn isAlign(c: u8) bool {
        return c == '<' or c == '>' or c == '^';
    }

    // Zig tip: a format such as `0>i5` is a tiny language: [fill][align][,][i|f]width[.precision].
    // `spec` is cut with indexes; `std.fmt.parseInt(usize, digits, 10)` reads a number (`catch 0` when
    // there are no digits). `@as(usize, ...)` pins the type of a literal. `std.unicode.utf8CountCodepoints`
    // counts symbols, not bytes, so the width of "αβγ" is 3. Padding is built with `appendNTimes`.
    /// Apply the format `spec` (the text after the `:`) of `\s{}`, `\#{}` or `\b{}` to `v`.
    fn format(it: *Interp, letter: u8, spec: []const u8, v: Value) Signal![]const u8 {
        var buf: std.ArrayList(u8) = .empty;
        if (v == .bool or letter == 'b') {
            const b = v == .bool and v.bool;
            const word = if (std.mem.eql(u8, spec, "yn")) (if (b) "Yes" else "No") else if (std.mem.eql(u8, spec, "01"))
                (if (b) "1" else "0")
            else if (std.mem.eql(u8, spec, "tf")) (if (b) "T" else "F") else (if (b) "True" else "False");
            return word;
        }
        var fill: u8 = ' ';
        var al: u8 = 0;
        var i: usize = 0;
        if (spec.len >= 2 and isAlign(spec[1])) {
            fill = spec[0];
            al = spec[1];
            i = 2;
        } else if (spec.len >= 1 and isAlign(spec[0])) {
            al = spec[0];
            i = 1;
        }
        var comma = false;
        if (i < spec.len and spec[i] == ',') {
            comma = true;
            i += 1;
        }
        var kind: u8 = 0;
        if (i < spec.len and (spec[i] == 'i' or spec[i] == 'f' or spec[i] == 's')) {
            kind = spec[i];
            i += 1;
        }
        var j = i;
        while (j < spec.len and std.ascii.isDigit(spec[j])) j += 1;
        const width = std.fmt.parseInt(usize, spec[i..j], 10) catch 0;
        var prec: ?usize = null;
        if (j < spec.len and spec[j] == '.') prec = std.fmt.parseInt(usize, spec[j + 1 ..], 10) catch 0;

        const numeric = realOf(v) != null;
        var body: []const u8 = undefined;
        if (numeric and kind == 'f') {
            body = try it.fixed(realOf(v).?, prec orelse 6);
        } else if (numeric and isInt(v) and comma) {
            const digits = try std.fmt.allocPrint(it.t, "{d}", .{intOf(v)});
            const neg = digits[0] == '-';
            const ds = if (neg) digits[1..] else digits;
            if (neg) try buf.append(it.t, '-');
            for (ds, 0..) |c, k| {
                if (k > 0 and (ds.len - k) % 3 == 0) try buf.append(it.t, ',');
                try buf.append(it.t, c);
            }
            body = buf.items;
        } else {
            body = try it.text(v);
            if (prec) |p| if (!numeric) {
                var k: usize = 0;
                var cps: usize = 0;
                while (k < body.len and cps < p) : (cps += 1) k += std.unicode.utf8ByteSequenceLength(body[k]) catch 1;
                body = body[0..@min(k, body.len)];
            };
        }
        const shown = std.unicode.utf8CountCodepoints(body) catch body.len;
        if (shown >= width) return body;
        const pad = width - shown;
        const side: u8 = if (al != 0) al else if (numeric) '>' else '<';
        var out: std.ArrayList(u8) = .empty;
        const left: usize = switch (side) {
            '>' => pad,
            '^' => pad / 2,
            else => 0,
        };
        try out.appendNTimes(it.t, fill, left);
        try out.appendSlice(it.t, body);
        try out.appendNTimes(it.t, fill, pad - left);
        return out.items;
    }

    // Zig tip: a format string must be known while compiling, so a precision that is only known
    // when the script runs cannot be written `{d:.*}`. `inline for` repeats its body once per
    // value of the range, each time with a compile-time `p`, so `"{d:." ++ digit ++ "}"` is built
    // by the compiler for p = 0, 1, 2, ... and the run-time `prec` picks the right copy.
    /// A Real with `prec` decimals.
    fn fixed(it: *Interp, x: f64, prec: usize) Signal![]const u8 {
        inline for (0..10) |p| {
            if (prec == p) return std.fmt.allocPrint(it.t, "{d:." ++ std.fmt.comptimePrint("{d}", .{p}) ++ "}", .{x});
        }
        return std.fmt.allocPrint(it.t, "{d:.9}", .{x});
    }

    // Zig tip: `interpolate` relies on the same Zig feature as `define` above: see the tip there.
    fn interpolate(it: *Interp, n: *const Node) Signal!Value {
        var buf: std.ArrayList(u8) = .empty;
        for (n.kids) |part| {
            if (part.tag == .str) {
                try buf.appendSlice(it.t, part.text);
            } else {
                const v = try it.eval(part.kids[0]);
                try buf.appendSlice(it.t, try it.format(part.text[0], part.text[1..], v));
            }
        }
        return .{ .str = try it.persist(buf.items) };
    }

    // ---- expressions ----------------------------------------------------------------------

    // Zig tip: `std.mem.replaceScalar`-style cleanup is avoided: the number text is copied without
    // its `_` separators into a stack buffer. `std.fmt.parseInt(i64, s, 0)` with base 0 reads the
    // prefix itself (`0x`, `0b`). A failure falls back to a Real, so a huge integer literal is
    // still a number. `std.fmt.parseFloat(f64, s)` reads `3.5`.
    fn number(it: *Interp, n: *const Node) Signal!Value {
        if (durationMs(n.text)) |ms| return .{ .int = ms };
        var buf: [64]u8 = undefined;
        var len: usize = 0;
        var digits_text = n.text;
        var suffix: u8 = 0;
        if (digits_text.len > 1 and digits_text[0] == '"') {
            // a number written as a string with a type suffix: `"1,000,000"z`, `"12,500.75"d`
            suffix = digits_text[digits_text.len - 1];
            digits_text = digits_text[1 .. digits_text.len - 2];
        } else if (digits_text.len > 1 and std.ascii.isAlphabetic(digits_text[digits_text.len - 1]) and !(digits_text.len > 2 and digits_text[0] == '0' and digits_text[1] == 'x')) {
            const last = digits_text[digits_text.len - 1];
            if (std.mem.indexOfScalar(u8, "drfbwnz", last) != null) {
                suffix = last;
                digits_text = digits_text[0 .. digits_text.len - 1];
            }
        }
        for (digits_text) |c| {
            if (c == ',' or len == buf.len) continue;
            buf[len] = c;
            len += 1;
        }
        const t = buf[0..len];
        const is_float = std.mem.indexOfScalar(u8, t, '.') != null or ((std.mem.indexOfAny(u8, t, "eE") != null) and !(t.len > 1 and t[0] == '0' and t[1] == 'x'));
        if (is_float) {
            const x = std.fmt.parseFloat(f64, t) catch return it.fail("bad number {s}", .{n.text});
            return switch (suffix) {
                'd' => .{ .dec = x },
                'f' => .{ .float = x },
                else => .{ .real = x },
            };
        }
        const v = std.fmt.parseInt(i64, t, 0) catch {
            return .{ .real = std.fmt.parseFloat(f64, t) catch return it.fail("bad number {s}", .{n.text}) };
        };
        switch (suffix) {
            'd' => return .{ .dec = @floatFromInt(v) },
            'r' => return .{ .real = @floatFromInt(v) },
            'f' => return .{ .float = @floatFromInt(v) },
            'b' => return .{ .byte = v },
            'w' => return .{ .short = v },
            'n' => return .{ .nat = v },
            'z' => return .{ .huge = v },
            else => {},
        }
        if (t.len > 1 and t[0] == '0' and (t[1] == 'x' or t[1] == 'b')) return .{ .nat = v };
        return .{ .int = v };
    }

    // Zig tip: `symbolOf` relies on the same Zig feature as `utf8` above: see the tip there.
    /// The code point of the UTF-8 text of a symbol node.
    fn symbolOf(t: []const u8) u21 {
        if (t.len == 0) return 0; // the empty rune, nil
        return std.unicode.utf8Decode(t) catch 0xFFFD;
    }

    // Zig tip: `eval` relies on the same Zig feature as `define` above: see the tip there.
    // Zig tip: `std.mem.endsWith` tests the end of a text. A duration literal is kept as an Integer of
    // milliseconds in version 0.3: `wait`, `within` and `$timeout` read it; its own type comes with
    // the time types of level 5 (D-144). `orelse return null` gives up when the digits do not parse.
    /// The milliseconds of a duration literal (`10ms`, `30s`, `2m`, `1h`), or null for another number.
    fn durationMs(lit: []const u8) ?i64 {
        if (lit.len < 2 or !std.ascii.isDigit(lit[0])) return null;
        const units = [_]struct { []const u8, i64 }{ .{ "ms", 1 }, .{ "s", 1000 }, .{ "m", 60_000 }, .{ "h", 3_600_000 } };
        for (units) |u| {
            if (!std.mem.endsWith(u8, lit, u[0])) continue;
            const digits = lit[0 .. lit.len - u[0].len];
            for (digits) |c| if (!std.ascii.isDigit(c)) return null;
            const v = std.fmt.parseInt(i64, digits, 10) catch return null;
            return v * u[1];
        }
        return null;
    }

    pub fn eval(it: *Interp, n: *const Node) Signal!Value {
        switch (n.tag) {
            .num => return it.number(n),
            .str => return it.staticStr(n.text),
            .text_lit => {
                const v = try it.staticStr(n.text);
                try it.base().text_ptrs.put(it.a, @intFromPtr(v.str.ptr), {});
                return v;
            },
            .interp => return it.interpolate(n),
            .chr => return .{ .sym = symbolOf(n.text) },
            .name => return it.lookup(n.text),
            .ref => return it.lookup(n.text),
            .dollar => return .{ .int = it.dollar },
            .bin => return it.binary(n),
            .un => return it.unary(n),
            .range => return it.makeRange(n),
            .cond => {
                const c = try it.truth(try it.eval(n.kids[1]));
                return it.eval(if (c) n.kids[0] else n.kids[2]);
            },
            .list, .array => {
                const l = try it.h.make(List, .{ .array = n.tag == .array });
                for (n.kids) |k| try it.listAppend(l, try it.eval(k));
                return .{ .list = l };
            },
            .brace => return it.brace(n),
            .builder => return it.builder(n),
            .field => return it.field(n),
            .index => return it.index(n),
            .call => return it.call(n),
            .lambda => return .{ .func = try it.newFunc(n, it.scope) },
            // `await f(x)`: the call runs here and now; while it waits, the other tasks run (D-143)
            .await_ => return it.call(n.kids[0]),
            // `Box(:Integer)`: version 0.3 erases the type arguments, the class itself is the value (D-145)
            .generic => return it.lookup(n.text),
            else => return it.fail("cannot evaluate a {s}", .{@tagName(n.tag)}),
        }
    }

    // Zig tip: `unary` relies on the same Zig feature as `define` above: see the tip there.
    fn unary(it: *Interp, n: *const Node) Signal!Value {
        const v = try it.eval(n.kids[0]);
        const op = n.text;
        if (std.mem.eql(u8, op, "not")) return .{ .bool = !(try it.truth(v)) };
        if (std.mem.eql(u8, op, "+")) return v;
        return switch (v) {
            .int, .nat, .byte, .short => |x| .{ .int = -x },
            .huge => |x| .{ .huge = -x },
            .real, .float, .dec => |x| .{ .real = -x },
            else => it.fail("cannot negate {s}", .{typeName(v)}),
        };
    }

    // Zig tip: `makeRange` relies on the same Zig feature as `define` above: see the tip there.
    fn makeRange(it: *Interp, n: *const Node) Signal!Value {
        const open_lo = n.kids[0].tag == .open_end;
        const open_hi = n.kids[1].tag == .open_end;
        const lo = if (open_lo) Value.nil else try it.eval(n.kids[0]);
        const hi = if (open_hi) Value.nil else try it.eval(n.kids[1]);
        if (std.mem.eql(u8, n.text, "+-")) {
            const c = realOf(lo) orelse return it.fail("+- needs numbers", .{});
            const t = realOf(hi) orelse return it.fail("+- needs numbers", .{});
            return .{ .domain = try it.newDomain(.{ .lo = c - t, .hi = c + t }) };
        }
        const excl_lo = n.text[0] == '>';
        const excl_hi = n.text[n.text.len - 1] == '<';
        if (!open_lo and !open_hi and isInt(lo) and isInt(hi)) {
            return .{ .range = try it.newRange(.{ .lo = intOf(lo) + @as(i64, if (excl_lo) 1 else 0), .hi = intOf(hi) - @as(i64, if (excl_hi) 1 else 0) }) };
        }
        if (lo == .sym and hi == .sym) {
            return .{ .range = try it.newRange(.{ .lo = lo.sym + @as(i64, if (excl_lo) 1 else 0), .hi = hi.sym - @as(i64, if (excl_hi) 1 else 0), .sym = true }) };
        }
        if ((!open_lo and realOf(lo) == null) or (!open_hi and realOf(hi) == null)) {
            return it.fail("a range needs numbers or symbols, found {s} and {s}", .{ typeName(lo), typeName(hi) });
        }
        return .{ .domain = try it.newDomain(.{ .lo = realOf(lo), .hi = realOf(hi), .lo_excl = excl_lo, .hi_excl = excl_hi }) };
    }

    // Zig tip: `x - @round(x)` is the distance to the nearest whole number; a value is on the grid
    // of a step when `x / step` is whole, with a small tolerance for the rounding of a `f64`.
    /// Is the real `x` inside the domain `d`? (limits, excluded limits, step)
    fn inDomain(d: *const Domain, x: f64) bool {
        if (d.lo) |lo| if (x < lo or (d.lo_excl and x == lo)) return false;
        if (d.hi) |hi| if (x > hi or (d.hi_excl and x == hi)) return false;
        if (d.step) |st| {
            const q = x / st;
            if (@abs(q - @round(q)) > 1e-9) return false;
        }
        return true;
    }

    // Zig tip: `brace` relies on the same Zig feature as `define` above: see the tip there.
    /// `{ ... }`: a DataSet, a HashMap or an Object, as the parser decided.
    fn brace(it: *Interp, n: *const Node) Signal!Value {
        if (std.mem.eql(u8, n.text, "set")) {
            const s = try it.h.make(List, .{});
            for (n.kids) |k| try it.setAdd(s, try it.eval(k));
            return .{ .set = s };
        }
        if (std.mem.eql(u8, n.text, "map")) {
            const m = try it.newMap();
            for (n.kids) |k| try it.mapPut(m, try it.eval(k.kids[0]), try it.eval(k.kids[1]));
            return .{ .map = m };
        }
        const o = try it.newObject();
        for (n.kids) |k| try it.setField(o, k.kids[0].text, try it.eval(k.kids[1]));
        return .{ .object = o };
    }

    // Zig tip: `mapFind` relies on the same Zig feature as `newList` above: see the tip there.
    fn mapFind(m: *Map, key: Value) ?usize {
        for (m.entries.items, 0..) |e, i| {
            if (eq(e.key, key)) return i;
        }
        return null;
    }

    // Zig tip: `while (cond) { ... }` repeats; `while (opt) |v|` repeats as long as an optional has
    // a value.
    /// Set `key` in the sorted map, creating the entry in its place when it is missing.
    fn mapPut(it: *Interp, m: *Map, key: Value, val: Value) Signal!void {
        if (mapFind(m, key)) |i| {
            it.setCell(&m.entries.items[i].val, val);
            return;
        }
        var i: usize = 0;
        while (i < m.entries.items.len and (try it.order(m.entries.items[i].key, key)) == .lt) i += 1;
        try m.entries.insert(it.g, i, .{ .key = key, .val = val });
        Heap.retain(key);
        Heap.retain(val);
    }

    // ---- operators ------------------------------------------------------------------------

    // Zig tip: `binary` relies on the same Zig feature as `define` above: see the tip there.
    fn binary(it: *Interp, n: *const Node) Signal!Value {
        const op = n.text;
        if (std.mem.eql(u8, op, "and")) {
            if (!try it.truth(try it.eval(n.kids[0]))) return .{ .bool = false };
            return .{ .bool = try it.truth(try it.eval(n.kids[1])) };
        }
        if (std.mem.eql(u8, op, "or")) {
            if (try it.truth(try it.eval(n.kids[0]))) return .{ .bool = true };
            return .{ .bool = try it.truth(try it.eval(n.kids[1])) };
        }
        if (std.mem.eql(u8, op, "=~") and n.kids[1].tag == .range and std.mem.eql(u8, n.kids[1].text, "+-")) {
            const x = realOf(try it.eval(n.kids[0])) orelse return it.fail("=~ with +- needs numbers", .{});
            const c = realOf(try it.eval(n.kids[1].kids[0])) orelse return it.fail("=~ with +- needs numbers", .{});
            const t = realOf(try it.eval(n.kids[1].kids[1])) orelse return it.fail("=~ with +- needs numbers", .{});
            return .{ .bool = @abs(x - c) <= t };
        }
        const l = try it.eval(n.kids[0]);
        const r = try it.eval(n.kids[1]);
        return it.apply(op, l, r);
    }

    // Zig tip: `textual` relies on the same Zig feature as `fail` above: see the tip there.
    fn textual(v: Value) bool {
        return v == .str or v == .sym;
    }

    // Zig tip: `overflow` relies on the same Zig feature as `fail` above: see the tip there.
    fn overflow(it: *Interp) Signal {
        return it.failWith(err_overflow, "Overflow in integer arithmetic", .{});
    }

    // Zig tip: `@addWithOverflow(a, b)` returns a tuple `.{ result, overflowed }`; Eve raises an
    // error instead of wrapping around silently. `@mulWithOverflow` and `@subWithOverflow` are alike.
    // `std.math.pow(f64, x, y)` is the power for reals; integers use a loop of multiplications.
    /// Apply a binary operator to two values.
    fn apply(it: *Interp, op: []const u8, l: Value, r: Value) Signal!Value {
        const eql = std.mem.eql;
        if (l == .list and isScalar(r) and isBulkOp(op)) return it.broadcast(op, l.list, r);
        if (eql(u8, op, "==")) return .{ .bool = eq(l, r) };
        if (eql(u8, op, "<>")) return .{ .bool = !eq(l, r) };
        if (eql(u8, op, "<")) return .{ .bool = (try it.order(l, r)) == .lt };
        if (eql(u8, op, ">")) return .{ .bool = (try it.order(l, r)) == .gt };
        if (eql(u8, op, "<=")) return .{ .bool = (try it.order(l, r)) != .gt };
        if (eql(u8, op, ">=")) return .{ .bool = (try it.order(l, r)) != .lt };
        if (eql(u8, op, "xor")) return .{ .bool = (try it.truth(l)) != (try it.truth(r)) };
        if (eql(u8, op, "in")) return .{ .bool = try it.contains(r, l) };
        if (eql(u8, op, "not in")) return .{ .bool = !(try it.contains(r, l)) };
        if (eql(u8, op, "is")) return .{ .bool = it.isOp(l, r) };
        if (eql(u8, op, "is not")) return .{ .bool = !it.isOp(l, r) };
        if (eql(u8, op, "=~") or eql(u8, op, "!~")) {
            if (realOf(l)) |x| if (realOf(r)) |y| {
                const eps = realOf((it.scope.find("$epsilon") orelse return it.fail("$epsilon is missing", .{})).value) orelse 1e-9;
                return .{ .bool = (@abs(x - y) <= eps) == eql(u8, op, "=~") };
            };
            if (l != .str or r != .str) return it.fail("a regular expression match needs two strings", .{});
            return .{ .bool = regexMatch(r.str, l.str) == eql(u8, op, "=~") };
        }
        if (eql(u8, op, "||") or eql(u8, op, "&&")) return it.setOp(op[0], l, r);
        if (eql(u8, op, "<+")) {
            if (l == .str) return .{ .str = try it.persist2(l.str, try it.text(r)) };
            return it.concat(l, r);
        }
        if (eql(u8, op, "+>")) {
            if (r == .str) return .{ .str = try it.persist2(try it.text(l), r.str) };
            if (r == .list) {
                const out = try it.h.make(List, .{});
                try it.listAppend(out, l);
                try it.listAppendSlice(out, r.list.elems());
                return .{ .list = out };
            }
            return it.fail("+> needs a list or a string on the right, found {s}", .{typeName(r)});
        }
        if (eql(u8, op, "+")) {
            if (textual(l) or textual(r)) return .{ .str = try it.persist2(try it.text(l), try it.text(r)) };
        }
        if (eql(u8, op, "-") and (l == .set or l == .list) and (r == .set or r == .list)) return it.setOp('-', l, r);
        if (eql(u8, op, "*") and l == .str and isInt(r)) {
            var buf: std.ArrayList(u8) = .empty;
            var k: i64 = 0;
            while (k < intOf(r)) : (k += 1) try buf.appendSlice(it.t, l.str);
            return .{ .str = try it.persist(buf.items) };
        }
        if (eql(u8, op, "><")) return it.product(l, r);
        // numbers
        if (realOf(l) == null or realOf(r) == null) {
            return it.fail("operator {s} does not apply to {s} and {s}", .{ op, typeName(l), typeName(r) });
        }
        if (eql(u8, op, "/")) {
            const d = realOf(r).?;
            if (d == 0) return it.failWith(err_divide, "Division by zero", .{});
            return .{ .real = realOf(l).? / d };
        }
        if (isInt(l) and isInt(r)) {
            const x = intOf(l);
            const y = intOf(r);
            if (eql(u8, op, "+")) {
                const s = @addWithOverflow(x, y);
                return if (s[1] != 0) it.overflow() else .{ .int = s[0] };
            }
            if (eql(u8, op, "-")) {
                const s = @subWithOverflow(x, y);
                return if (s[1] != 0) it.overflow() else .{ .int = s[0] };
            }
            if (eql(u8, op, "*")) {
                const s = @mulWithOverflow(x, y);
                return if (s[1] != 0) it.overflow() else .{ .int = s[0] };
            }
            if (eql(u8, op, "%")) {
                if (y == 0) return it.failWith(err_divide, "Division by zero", .{});
                return .{ .int = @mod(x, y) };
            }
            if (eql(u8, op, "^")) {
                if (y < 0) return .{ .real = std.math.pow(f64, @floatFromInt(x), @floatFromInt(y)) };
                var acc: i64 = 1;
                var k: i64 = 0;
                while (k < y) : (k += 1) {
                    const s = @mulWithOverflow(acc, x);
                    if (s[1] != 0) return it.overflow();
                    acc = s[0];
                }
                return .{ .int = acc };
            }
            if (eql(u8, op, "<<") and y >= 0 and y < 63) return .{ .int = x << @intCast(y) };
            if (eql(u8, op, ">>") and y >= 0 and y < 63) return .{ .int = x >> @intCast(y) };
        } else {
            const x = realOf(l).?;
            const y = realOf(r).?;
            if (eql(u8, op, "+")) return .{ .real = x + y };
            if (eql(u8, op, "-")) return .{ .real = x - y };
            if (eql(u8, op, "*")) return .{ .real = x * y };
            if (eql(u8, op, "%")) return .{ .real = @mod(x, y) };
            if (eql(u8, op, "^")) return .{ .real = std.math.pow(f64, x, y) };
        }
        return it.fail("unknown operator {s}", .{op});
    }

    // Zig tip: a `switch` on a `Value` (a tagged union) with `=> true` arms and an `else` arm is the
    // short way to ask "is it one of these cases?". A `bool` function like this one can be inlined.
    /// A scalar is a single value: a number, a boolean, a symbol or a string (never a collection).
    fn isScalar(v: Value) bool {
        return switch (v) {
            .bool, .int, .nat, .byte, .short, .huge, .real, .float, .dec, .sym, .str => true,
            else => false,
        };
    }

    // Zig tip: `inline for` unrolls a loop over a comptime-known array, so each `op` is a constant.
    // `std.mem.eql(u8, a, b)` compares two byte slices (strings) by content, not by address.
    /// The operators that apply to every element of a list when the other operand is a scalar (D-118).
    fn isBulkOp(op: []const u8) bool {
        inline for (.{ "+", "-", "*", "/", "%", "^", "<", ">", "<=", ">=", "=~" }) |o| {
            if (std.mem.eql(u8, op, o)) return true;
        }
        return false;
    }

    // Zig tip: `std.mem.indexOfScalar(u8, "+-*/%^", op[0])` finds one byte in a slice and returns an
    // optional index (`?usize`); `!= null` turns it into a yes/no answer.
    /// One element with a scalar. Arithmetic never builds a string: that needs a loop (D-118).
    fn bulkOne(it: *Interp, op: []const u8, e: Value, s: Value) Signal!Value {
        const arithmetic = std.mem.indexOfScalar(u8, "+-*/%^", op[0]) != null and op.len == 1;
        if (arithmetic and (textual(e) or textual(s))) {
            return it.fail("operator {s} on a collection and a string is not possible: build a new collection with a loop", .{op});
        }
        return it.apply(op, e, s);
    }

    // Zig tip: `try` inside a `for` leaves the function at the first error, so a half-built `out`
    // is simply dropped: its count is zero, and the next safe point frees it.
    /// `list op scalar`: a new list with `op` applied to each element (D-118).
    fn broadcast(it: *Interp, op: []const u8, src: *List, s: Value) Signal!Value {
        const out = try it.h.make(List, .{ .array = src.array });
        for (src.elems()) |e| try it.listAppend(out, try it.bulkOne(op, e, s));
        return .{ .list = out };
    }

    // Zig tip: `isOp` relies on the same Zig feature as `bind` above: see the tip there.
    fn isOp(it: *Interp, l: Value, r: Value) bool {
        _ = it;
        if (l == .typ and r == .typ) return std.mem.eql(u8, l.typ, r.typ);
        if (r == .typ) return std.mem.eql(u8, typeName(l), r.typ);
        if (r == .class and l == .object) {
            var cur: ?*Class = l.object.class;
            while (cur) |k| : (cur = k.parent) {
                if (k == r.class) return true;
                for (k.traits.items) |tr| if (tr == r.class) return true;
            }
            return false;
        }
        return same(l, r);
    }

    // Zig tip: `setOp` relies on the same Zig feature as `define` above: see the tip there.
    /// `||` union, `&&` intersection, `-` difference: the result is a DataSet.
    fn setOp(it: *Interp, op: u8, l: Value, r: Value) Signal!Value {
        const a = try it.setOf(l);
        const b = try it.setOf(r);
        const out = try it.h.make(List, .{});
        for (a.items.items) |e| {
            const in_b = try it.contains(.{ .set = b }, e);
            if (op == '|' or (op == '&' and in_b) or (op == '-' and !in_b)) try it.setAdd(out, e);
        }
        if (op == '|') for (b.items.items) |e| try it.setAdd(out, e);
        return .{ .set = out };
    }

    // Zig tip: `concat` relies on the same Zig feature as `define` above: see the tip there.
    /// `a <+ b` as an expression: a new list with the element or the list `b` added at the end.
    fn concat(it: *Interp, l: Value, r: Value) Signal!Value {
        const src = switch (l) {
            .list, .set => |x| x,
            else => return it.fail("<+ needs a list on the left, found {s}", .{typeName(l)}),
        };
        const out = try it.h.make(List, .{ .array = src.array });
        try it.listAppendSlice(out, src.elems());
        if (r == .list) try it.listAppendSlice(out, r.list.elems()) else try it.listAppend(out, r);
        return .{ .list = out };
    }

    // Zig tip: `product` relies on the same Zig feature as `define` above: see the tip there.
    /// `A >< B`: the pairs (a, b) of two collections, as a list of lists.
    fn product(it: *Interp, l: Value, r: Value) Signal!Value {
        const xs = try it.iterate(l);
        const ys = try it.iterate(r);
        const out = try it.h.make(List, .{});
        for (xs) |x| for (ys) |y| try it.listAppend(out, .{ .list = try it.newList(&.{ x, y }, false) });
        return .{ .list = out };
    }

    // ---- collections: iteration, builders, indexing ---------------------------------------

    // Zig tip: `iterate` relies on the same Zig feature as `define` above: see the tip there.
    /// The elements of a collection, a range or a string, as a slice.
    fn iterate(it: *Interp, v: Value) Signal![]const Value {
        switch (v) {
            .list, .set => |l| return l.elems(),
            .range => |r| {
                var out: std.ArrayList(Value) = .empty;
                var k = r.lo;
                while (k <= r.hi) : (k += r.step) {
                    if (r.sym) try out.append(it.t, .{ .sym = @intCast(k) }) else try out.append(it.t, .{ .int = k });
                }
                return out.items;
            },
            .str => |s| {
                var out: std.ArrayList(Value) = .empty;
                var view = std.unicode.Utf8View.init(s) catch return it.fail("the string is not valid UTF-8", .{});
                var iter = view.iterator();
                while (iter.nextCodepoint()) |cp| try out.append(it.t, .{ .sym = cp });
                return out.items;
            },
            .map => |m| {
                var out: std.ArrayList(Value) = .empty;
                for (m.entries.items) |e| try out.append(it.t, .{ .list = try it.newList(&.{ e.key, e.val }, false) });
                return out.items;
            },
            else => return it.fail("{s} is not iterable", .{typeName(v)}),
        }
    }

    // Zig tip: `bindPattern` relies on the same Zig feature as `define` above: see the tip there.
    /// Give the names of a loop or builder pattern their values: `x`, or `(a, b)` for a pair.
    fn bindPattern(it: *Interp, pat: *const Node, v: Value) Signal!void {
        switch (pat.tag) {
            .name => try it.define(pat.text, v, false),
            .list => {
                // `for (k: v) in map`: the parentheses hold one pair
                if (pat.kids.len == 1 and pat.kids[0].tag == .pair) return it.bindPattern(pat.kids[0], v);
                const items = try it.iterate(v);
                for (pat.kids, 0..) |k, i| {
                    if (i < items.len) try it.bindPattern(k, items[i]);
                }
            },
            .pair => {
                const items = try it.iterate(v);
                if (items.len != 2) return it.fail("a pair (key: value) is expected", .{});
                try it.bindPattern(pat.kids[0], items[0]);
                try it.bindPattern(pat.kids[1], items[1]);
            },
            else => return it.fail("bad loop variable", .{}),
        }
    }

    // Zig tip: `defer stmt;` runs `stmt` when the scope ends, however it ends: it pairs a release
    // with the line that took the resource.
    /// `(item | x in source and cond)`, `[...]` and `{...}`.
    fn builder(it: *Interp, n: *const Node) Signal!Value {
        const saved = try it.pushScope();
        defer it.leaveScope(saved);
        var conds: std.ArrayList(*const Node) = .empty;
        var g = n.kids[1];
        while (g.tag == .bin and std.mem.eql(u8, g.text, "and")) {
            try conds.append(it.t, g.kids[1]);
            g = g.kids[0];
        }
        if (g.tag != .bin or !std.mem.eql(u8, g.text, "in")) return it.fail("a builder needs 'x in collection'", .{});
        const pat = g.kids[0];
        const src = g.kids[1];
        const open = n.text[0];
        const out = try it.h.make(List, .{ .array = open == '[' });

        if (src.tag == .bin and std.mem.eql(u8, src.text, "><")) {
            const xs = try it.iterate(try it.eval(src.kids[0]));
            const ys = try it.iterate(try it.eval(src.kids[1]));
            for (xs) |x| {
                const row = try it.h.make(List, .{ .array = true });
                for (ys) |y| {
                    try it.bindPattern(pat, .{ .list = try it.newList(&.{ x, y }, false) });
                    if (!try it.allTrue(conds.items)) continue;
                    const v = try it.eval(n.kids[0]);
                    if (open == '[') try it.listAppend(row, v) else try it.collect(out, open, v);
                }
                if (open == '[') try it.listAppend(out, .{ .list = row });
            }
        } else {
            for (try it.iterate(try it.eval(src))) |x| {
                try it.bindPattern(pat, x);
                if (!try it.allTrue(conds.items)) continue;
                try it.collect(out, open, try it.eval(n.kids[0]));
            }
        }
        return if (open == '{') .{ .set = out } else .{ .list = out };
    }

    // Zig tip: `allTrue` relies on the same Zig feature as `define` above: see the tip there.
    fn allTrue(it: *Interp, conds: []const *const Node) Signal!bool {
        for (conds) |c| if (!try it.truth(try it.eval(c))) return false;
        return true;
    }

    // Zig tip: `collect` relies on the same Zig feature as `define` above: see the tip there.
    fn collect(it: *Interp, out: *List, open: u8, v: Value) Signal!void {
        if (open == '{') try it.setAdd(out, v) else try it.listAppend(out, v);
    }

    // One index of `a[i, j]`: a number, `$` (already a number), `*` (all) or a range.
    const Idx = union(enum) { one: i64, all, rng: struct { lo: i64, hi: i64 } };

    // Zig tip: `isMatrix` relies on the same Zig feature as `realOf` above: see the tip there.
    /// A matrix or a tensor is an array whose elements are arrays.
    // Zig tip: `and` stops at the first false operand, so `l.elems()[0]` is read only when the list
    // has an element. A matrix is an array of arrays, `[[1, 2], [3, 4]]` (types.md); a list of lists
    // `((1, 2), (3))` is not one, so each pair of brackets indexes the result of the previous (D-064).
    /// Is `l` a matrix or a tensor: an array whose elements are arrays?
    fn isMatrix(l: *List) bool {
        return l.array and l.elems().len > 0 and l.elems()[0] == .list and l.elems()[0].list.array;
    }

    // Zig tip: `dimLen` relies on the same Zig feature as `realOf` above: see the tip there.
    fn dimLen(root: *List, depth: usize) i64 {
        var l = root;
        var d: usize = 0;
        while (d < depth) : (d += 1) {
            const e = l.elems();
            if (e.len == 0 or e[0] != .list) return 0;
            l = e[0].list;
        }
        return @intCast(l.elems().len);
    }

    // Zig tip: `evalIdx` relies on the same Zig feature as `define` above: see the tip there.
    fn evalIdx(it: *Interp, n: *const Node, len: i64) Signal!Idx {
        if (n.tag == .all) return .all;
        const saved = it.dollar;
        it.dollar = len;
        defer it.dollar = saved;
        if (n.tag == .range) {
            const r = try it.makeRange(n);
            const lo = if (r.range.lo < 0) len + 1 + r.range.lo else r.range.lo;
            const hi = if (r.range.hi < 0) len + 1 + r.range.hi else r.range.hi;
            return .{ .rng = .{ .lo = lo, .hi = hi } };
        }
        const v = try it.eval(n);
        if (!isInt(v)) return it.fail("an index must be an integer, found {s}", .{typeName(v)});
        const k = intOf(v);
        return .{ .one = if (k < 0) len + 1 + k else k };
    }

    // Zig tip: `leaves` relies on the same Zig feature as `define` above: see the tip there.
    fn leaves(it: *Interp, l: *List, out: *std.ArrayList(*Value)) Signal!void {
        for (l.elems()) |*e| {
            if (e.* == .list) try it.leaves(e.list, out) else try out.append(it.t, e);
        }
    }

    // Zig tip: `slots` relies on the same Zig feature as `define` above: see the tip there.
    /// The storage cells an index expression selects (one for `a[2]`, several for a slice or `[*]`).
    fn slots(it: *Interp, root: *List, args: []const *const Node, out: *std.ArrayList(*Value)) Signal!void {
        if (args.len == 1 and isMatrix(root)) {
            // one absolute row-major index, or all the elements, or a range of them
            var flat: std.ArrayList(*Value) = .empty;
            try it.leaves(root, &flat);
            const ix = try it.evalIdx(args[0], @intCast(flat.items.len));
            try it.pick(flat.items, ix, out);
            return;
        }
        try it.walk(root, args, 0, out);
    }

    // Zig tip: `pick` relies on the same Zig feature as `define` above: see the tip there.
    fn pick(it: *Interp, cells: []*Value, ix: Idx, out: *std.ArrayList(*Value)) Signal!void {
        switch (ix) {
            .all => for (cells) |c| try out.append(it.t, c),
            .one => |k| {
                if (k < 1 or k > cells.len) return it.failWith(err_index, "Index {d} is out of range 1..{d}", .{ k, cells.len });
                try out.append(it.t, cells[@intCast(k - 1)]);
            },
            .rng => |r| {
                if (r.lo > r.hi) return;
                if (r.lo < 1 or r.hi > cells.len) return it.failWith(err_index, "Range {d}..{d} is out of range 1..{d}", .{ r.lo, r.hi, cells.len });
                for (cells[@intCast(r.lo - 1)..@intCast(r.hi)]) |c| try out.append(it.t, c);
            },
        }
    }

    // Zig tip: `walk` relies on the same Zig feature as `define` above: see the tip there.
    fn walk(it: *Interp, l: *List, args: []const *const Node, depth: usize, out: *std.ArrayList(*Value)) Signal!void {
        const ix = try it.evalIdx(args[depth], dimLen(l, 0));
        var cells: std.ArrayList(*Value) = .empty;
        for (l.elems()) |*e| try cells.append(it.t, e);
        var picked: std.ArrayList(*Value) = .empty;
        try it.pick(cells.items, ix, &picked);
        for (picked.items) |c| {
            if (depth + 1 == args.len) {
                try out.append(it.t, c);
            } else if (c.* == .list) {
                try it.walk(c.list, args, depth + 1, out);
            } else return it.fail("too many indexes", .{});
        }
    }

    // Zig tip: a function can return a struct type written on the spot, with no name (an anonymous
    // struct): `Signal!struct { obj: Value, args: ... }`. The caller reads `r.obj` and `r.args`, and
    // the two results travel together without declaring a type used only here.
    /// Resolves a chain of brackets `a[i][j]...` to the value indexed last and its indexes. On a
    /// matrix or a tensor the remaining groups merge into one: `m[x][y]` is `m[x, y]` (D-064). One
    /// group alone keeps its meaning: `m[k]` is the absolute row-major index.
    fn indexChain(it: *Interp, n: *const Node) Signal!struct { obj: Value, args: []const *const Node } {
        // the parser nests `a[i][j]` as index(index(a, i), j): collect the groups outside-in, then reverse
        var groups: std.ArrayList([]const *const Node) = .empty;
        var root = n;
        while (root.tag == .index) : (root = root.kids[0]) {
            try groups.append(it.t, root.kids[1..]);
        }
        std.mem.reverse([]const *const Node, groups.items);
        var obj = try it.eval(root);
        var i: usize = 0;
        while (i + 1 < groups.items.len) : (i += 1) {
            if (obj == .list and isMatrix(obj.list)) {
                var merged: std.ArrayList(*const Node) = .empty;
                for (groups.items[i..]) |g| try merged.appendSlice(it.t, g);
                return .{ .obj = obj, .args = merged.items };
            }
            obj = try it.indexOf(obj, groups.items[i]);
        }
        return .{ .obj = obj, .args = groups.items[i] };
    }

    // Zig tip: `index` relies on the same Zig feature as `define` above: see the tip there.
    fn index(it: *Interp, n: *const Node) Signal!Value {
        const r = try it.indexChain(n);
        return it.indexOf(r.obj, r.args);
    }

    // Zig tip: `indexOf` relies on the same Zig feature as `define` above: see the tip there.
    /// One group of brackets applied to a value: `obj[args]`.
    fn indexOf(it: *Interp, obj: Value, args: []const *const Node) Signal!Value {
        switch (obj) {
            .map => |m| {
                const key = try it.eval(args[0]);
                const i = mapFind(m, key) orelse return it.failWith(err_key, "Key not found", .{});
                return m.entries.items[i].val;
            },
            .list, .set => |l| {
                // a range on a one-dimensional list is a view: it shares the storage
                if (args.len == 1 and args[0].tag == .range and !isMatrix(l)) {
                    const ix = try it.evalIdx(args[0], @intCast(l.elems().len));
                    const lo = ix.rng.lo;
                    const hi = ix.rng.hi;
                    if (lo < 1 or hi > l.elems().len or lo > hi + 1) return it.failWith(err_index, "Range {d}..{d} is out of range 1..{d}", .{ lo, hi, l.elems().len });
                    // a view counts the list it shows
                    const v = try it.h.make(List, .{ .array = l.array, .base = l, .off = @intCast(lo - 1), .len = @intCast(hi - lo + 1) });
                    l.hdr.rc += 1;
                    return .{ .list = v };
                }
                if (args.len == 1 and args[0].tag != .all and !isMatrix(l)) {
                    // one index on a list: read the element directly
                    const ix = try it.evalIdx(args[0], @intCast(l.elems().len));
                    const k = ix.one;
                    if (k < 1 or k > l.elems().len) return it.failWith(err_index, "Index {d} is out of range 1..{d}", .{ k, l.elems().len });
                    return l.elems()[@intCast(k - 1)];
                }
                var cells: std.ArrayList(*Value) = .empty;
                try it.slots(l, args, &cells);
                if (cells.items.len == 1 and args[0].tag != .all and args[args.len - 1].tag != .all) return cells.items[0].*;
                const out = try it.h.make(List, .{ .array = true });
                for (cells.items) |c| try it.listAppend(out, c.*);
                return .{ .list = out };
            },
            .str => |s| {
                const items = try it.iterate(obj);
                const ix = try it.evalIdx(args[0], @intCast(items.len));
                _ = s;
                if (ix != .one or ix.one < 1 or ix.one > items.len) return it.failWith(err_index, "Index is out of range 1..{d}", .{items.len});
                return items[@intCast(ix.one - 1)];
            },
            else => return it.fail("{s} cannot be indexed", .{typeName(obj)}),
        }
    }

    // Zig tip: `field` relies on the same Zig feature as `define` above: see the tip there.
    fn field(it: *Interp, n: *const Node) Signal!Value {
        const obj = try it.eval(n.kids[0]);
        switch (obj) {
            .object => |o| return fieldOf(o, n.text) orelse it.fail("no attribute '{s}'", .{n.text}),
            .module => |m| return it.moduleMember(m, n.text),
            .class => |c| {
                for (c.ord.items) |f| if (std.mem.eql(u8, f.name, n.text)) return f.val;
                return it.fail("{s} has no member '{s}'", .{ c.name, n.text });
            },
            else => return it.fail("{s} has no attribute '{s}'", .{ typeName(obj), n.text }),
        }
    }

    // ---- calls ----------------------------------------------------------------------------

    // Zig tip: `call` relies on the same Zig feature as `define` above: see the tip there.
    fn call(it: *Interp, n: *const Node) Signal!Value {
        const callee = n.kids[0];
        const args = n.kids[1..];
        if (callee.tag == .field) {
            const recv = try it.eval(callee.kids[0]);
            if (recv == .module) return it.callValue(try it.moduleMember(recv.module, callee.text), null, args);
            return it.callMethod(recv, callee.text, args);
        }
        if (callee.tag == .name and args.len == 1 and it.scope.find(callee.text) == null and
            (std.mem.eql(u8, callee.text, "floor") or std.mem.eql(u8, callee.text, "ceiling") or std.mem.eql(u8, callee.text, "round")))
        {
            const eql = std.mem.eql;
            const x = realOf(try it.eval(args[0])) orelse return it.fail("{s}() needs a number", .{callee.text});
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
            return .{ .typ = typeName(arg) };
        }
        return it.callValue(try it.eval(callee), null, args);
    }

    // Zig tip: `callValue` relies on the same Zig feature as `define` above: see the tip there.
    fn callValue(it: *Interp, v: Value, recv: ?Value, args: []const *const Node) Signal!Value {
        switch (v) {
            .func => |f| return it.invoke(f, recv, args),
            .range => |r| {
                if (args.len != 1) return it.fail("a range takes one step", .{});
                const step = try it.eval(args[0]);
                if (isInt(step) and intOf(step) >= 1) {
                    return .{ .range = try it.newRange(.{ .lo = r.lo, .hi = r.hi, .step = intOf(step), .sym = r.sym }) };
                }
                const st = realOf(step) orelse return it.fail("the step of a range is a number", .{});
                return .{ .domain = try it.newDomain(.{ .lo = @floatFromInt(r.lo), .hi = @floatFromInt(r.hi), .step = st }) };
            },
            .domain => |d0| {
                if (args.len != 1) return it.fail("a range takes one step", .{});
                const st = realOf(try it.eval(args[0])) orelse return it.fail("the step of a range is a number", .{});
                return .{ .domain = try it.newDomain(.{ .lo = d0.lo, .hi = d0.hi, .lo_excl = d0.lo_excl, .hi_excl = d0.hi_excl, .step = st }) };
            },
            .class => |c| return it.constructClass(c, args),
            .typ => |name| {
                if (std.mem.eql(u8, name, "Channel")) return it.newChannel(args);
                return it.fail("{s} is not callable", .{name});
            },
            else => return it.fail("{s} is not callable", .{typeName(v)}),
        }
    }

    // Zig tip: `classRoutine` relies on the same Zig feature as `bind` above: see the tip there.
    fn classRoutine(c: *Class, name: []const u8) ?*const Node {
        var cur: ?*Class = c;
        while (cur) |k| : (cur = k.parent) {
            const node = k.node orelse continue;
            for (node.kids[2..]) |r| {
                if (r.tag != .constructor and r.kids[3].tag != .none and std.mem.eql(u8, r.text, name)) return r;
            }
        }
        // a method provided by a trait, when the class and its ancestors do not write it (D-145)
        cur = c;
        while (cur) |k| : (cur = k.parent) {
            for (k.traits.items) |tr| if (classRoutine(tr, name)) |r| return r;
        }
        return null;
    }

    // Zig tip: an extension method is declared outside the class; its first parameter is `@self`
    // with the type of the class (D-040). The call `p.shift(1, 2)` finds it by the name of the
    // class of `p` or of one of its ancestors.
    /// The extension method `name` for objects of class `c`.
    fn extensionFor(it: *Interp, c: *Class, name: []const u8) ?*const Node {
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
    fn callMethod(it: *Interp, recv: Value, name: []const u8, args: []const *const Node) Signal!Value {
        if (recv == .object) {
            if (recv.object.class) |c| {
                if (classRoutine(c, name) orelse it.extensionFor(c, name)) |r| {
                    return it.invoke(try it.newFunc(r, it.unit), recv, args);
                }
            }
        }
        const eql = std.mem.eql;
        if (recv == .chan) return it.channelMethod(recv.chan, name, args);
        if ((eql(u8, name, "batch") or eql(u8, name, "split")) and recv == .list and args.len == 1) {
            return it.cut(recv.list, eql(u8, name, "split"), try it.eval(args[0]));
        }
        if (eql(u8, name, "compare") and args.len == 1 and recv != .object) {
            return .{ .int = switch (try it.order(recv, try it.eval(args[0]))) {
                .lt => -1,
                .eq => 0,
                .gt => 1,
            } };
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
                if (eq(l.items.items[k], gone)) _ = it.listRemove(l, k) else k += 1;
            }
            return .nil;
        }
        if (eql(u8, name, "length") or eql(u8, name, "count")) {
            return .{ .int = switch (recv) {
                .str => |s| @intCast(std.unicode.utf8CountCodepoints(s) catch s.len),
                .list, .set => |l| @intCast(l.elems().len),
                .map => |m| @intCast(m.entries.items.len),
                .object => |o| @intCast(o.fields.items.len),
                else => return it.fail("{s} has no length", .{typeName(recv)}),
            } };
        }
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
        return it.fail("{s} has no method '{s}'", .{ typeName(recv), name });
    }

    // Zig tip: `evalArgs` relies on the same Zig feature as `define` above: see the tip there.
    /// Evaluate the arguments of a call in the caller's scope.
    fn evalArgs(it: *Interp, nodes: []const *const Node) Signal![]Arg {
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
    fn bindParams(it: *Interp, params: []const *const Node, args: []const Arg, self_var: ?*Var) Signal!void {
        var taken = [_]bool{false} ** 32;
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
    fn invoke(it: *Interp, f: *Func, recv: ?Value, arg_nodes: []const *const Node) Signal!Value {
        const args = try it.evalArgs(arg_nodes);
        defer it.dropArgs(args);
        defer it.writeBack(args);
        return it.invokeWith(f, recv, args);
    }

    // Zig tip: `invokeWith` relies on the same Zig feature as `invoke` above: see the tip there. A
    // spawned task evaluates its arguments in the parent, at `spawn`, and calls this in its own thread.
    /// Call a function, method or lambda with arguments already evaluated.
    fn invokeWith(it: *Interp, f: *Func, recv: ?Value, args: []const Arg) Signal!Value {
        const node = f.node;
        const s = try it.newScope(f.closure);
        const saved = try it.enterScope(s);
        defer it.leaveScope(saved);
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
        try it.frames.append(it.a, .{ .kind = @tagName(node.tag), .name = node.text, .call_line = it.line });
        defer _ = it.frames.pop();
        const mark = it.defers.items.len;
        const outcome = it.execBlock(node.kids[3]);
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

    // Zig tip: `construct` relies on the same Zig feature as `define` above: see the tip there.
    /// `new Class(args)`.
    fn constructClass(it: *Interp, cls: *Class, arg_nodes: []const *const Node) Signal!Value {
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
    fn zero(it: *Interp, ty: ?*const Node) Signal!Value {
        const t = ty orelse return .nil;
        if (t.kids.len > 0) {
            // an array: the first dimension is built here, the others inside
            const dim = try it.eval(t.kids[0]);
            if (!isInt(dim)) return it.fail("an array size is an integer", .{});
            const inner: Node = .{ .tag = .type, .text = t.text, .kids = t.kids[1..] };
            const l = try it.h.make(List, .{ .array = true });
            var k: i64 = 0;
            while (k < intOf(dim)) : (k += 1) try it.listAppend(l, try it.zero(&inner));
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
        if (eql(u8, t.text, "String")) return it.staticStr("");
        if (eql(u8, t.text, "Symbol") or eql(u8, t.text, "Rune")) return .{ .sym = 0 };
        if (eql(u8, t.text, "DataSet")) return .{ .set = try it.newList(&.{}, false) };
        if (eql(u8, t.text, "DataMap")) return .{ .map = try it.newMap() };
        return .nil;
    }

    // Zig tip: a tiny matcher, written as three small recursive functions. It supports literals,
    // `.`, `^`, `$`, classes `[a-z]`, `\d \w \s`, the quantifiers `* + ?` and `|` between whole
    // alternatives; groups are not supported. `pattern` is `/body/flags`; the flag `i` ignores case.
    fn atomLen(pat: []const u8) usize {
        if (pat[0] == '\\' and pat.len > 1) return 2;
        if (pat[0] == '[') return (std.mem.indexOfScalar(u8, pat, ']') orelse pat.len - 1) + 1;
        return 1;
    }

    // Zig tip: `atomMatch` relies on the same Zig feature as `mapPut` above: see the tip there.
    fn atomMatch(atom: []const u8, c: u8, ic: bool) bool {
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
    fn matchHere(pat: []const u8, txt: []const u8, ic: bool) bool {
        if (pat.len == 0) return true;
        if (pat.len == 1 and pat[0] == '$') return txt.len == 0;
        const n = atomLen(pat);
        const atom = pat[0..n];
        const rest = pat[n..];
        if (rest.len > 0 and (rest[0] == '*' or rest[0] == '+' or rest[0] == '?')) {
            var k: usize = 0;
            const limit: usize = if (rest[0] == '?') 1 else txt.len;
            while (k < limit and k < txt.len and atomMatch(atom, txt[k], ic)) k += 1;
            const min: usize = if (rest[0] == '+') 1 else 0;
            while (true) {
                if (k >= min and matchHere(rest[1..], txt[k..], ic)) return true;
                if (k == 0) return false;
                k -= 1;
            }
        }
        if (txt.len > 0 and atomMatch(atom, txt[0], ic)) return matchHere(rest, txt[1..], ic);
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
                if (matchHere(pat, txt[i..], ic)) return true;
                if (anchored) break;
            }
        }
        return false;
    }

    // ---- statements -----------------------------------------------------------------------

    // Zig tip: `execBlock` relies on the same Zig feature as `define` above: see the tip there.
    // Zig tip: a block is a region of the heap: after each statement, the values it made and dropped are
    // freed (a safe point); `defer` leaves the region however the block ends.
    fn execBlock(it: *Interp, b: *const Node) Signal!void {
        it.regionIn();
        defer it.regionOut();
        try it.execBody(b);
    }

    // Zig tip: the body of a loop needs no region of its own: the loop has one, and the statements of the
    // body end at safe points of that region. Entering a region at each pass would cost a little for
    // nothing.
    /// The statements of a loop body, each followed by a safe point.
    fn execBody(it: *Interp, b: *const Node) Signal!void {
        for (b.kids) |s| {
            try it.exec(s);
            it.safe();
        }
    }

    // Zig tip: `tick` is the "step" of the execution loop: it counts the statement, remembers its
    // line, and lets the VM look into the slot for external commands. A hook is a function pointer
    // plus an opaque context pointer (`*anyopaque`): the interpreter calls "something" without
    // knowing the VM, so this file does not import vm.zig.
    fn tick(it: *Interp, n: *const Node) Signal!void {
        if (it.hook) |h| {
            if (h.poll(h.ctx, it.steps, it.line)) return error.Stop;
        }
        if (it.root != null) try it.checkCancel();
        it.steps += 1;
        if (n.line > 0) it.line = n.line;
    }

    // Zig tip: `exec` relies on the same Zig feature as `define` above: see the tip there.
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
                if (!try it.truth(try it.eval(n.kids[0]))) return it.failWith(err_expect, "expect failed", .{});
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
            .over_stmt => return error.Over,
            .exit_stmt => return error.Exit,
            .stop_stmt => return error.StopJob,
            .pass_stmt => {},
            .assert_stmt => {
                if (!try it.truth(try it.eval(n.kids[0]))) return it.failWith(err_assert, "assertion failed", .{});
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
                const saved = it.current_job;
                it.current_job = n.text;
                defer it.current_job = saved;
                // the tasks spawned in this job (D-143); `done` waits for them however the job ends
                const spawned = try it.a.create(std.ArrayList(*Started));
                spawned.* = .empty;
                const saved_tasks = it.job_tasks;
                it.job_tasks = spawned;
                defer it.job_tasks = saved_tasks;
                const outcome = it.execBlock(n.kids[0]);
                if (spawned.items.len > 0) {
                    try it.joinTasks(spawned, null, 0);
                    try it.endTasks(spawned);
                    it.h.resume_(@intCast(spawned.items.len));
                }
                it.collectAtDone();
                outcome catch |e| switch (e) {
                    error.StopJob => {},
                    else => {
                        it.setJob(n.text, "fail");
                        return e;
                    },
                };
                it.raiseFailed(spawned, n.text) catch |e| {
                    it.setJob(n.text, "fail");
                    return e;
                };
                it.setJob(n.text, "pass");
            },
            .class, .trait, .function, .procedure, .method => try it.declareRoutine(n),
            .apply_stmt => try it.applyAspect(n),
            .parallel => try it.parallelGroup(n),
            .start_stmt => try it.startAspect(n),
            .spawn_stmt => try it.spawnTask(n),
            .wait_stmt => {
                const v = try it.eval(n.kids[0]);
                if (!isInt(v)) return it.fail("wait takes a duration: wait 10ms;", .{});
                try it.waitFor(intOf(v));
            },
            .process => {},
            else => return it.fail("cannot execute a {s}", .{@tagName(n.tag)}),
        }
    }

    // Zig tip: `catch {}` after a call drops its error on purpose; here a missing `jobs` map
    // (a free script) is not a failure. The state of a job is one field of an object in the map.
    /// Record the state of the job `label` in `jobs["label"].status`.
    fn setJob(it: *Interp, label: []const u8, status: []const u8) void {
        const cell = it.scope.find("jobs") orelse return;
        if (cell.value != .map) return;
        const i = mapFind(cell.value.map, .{ .str = label }) orelse return;
        const rec = cell.value.map.entries.items[i].val;
        if (rec == .object) it.setField(rec.object, "status", it.staticStr(status) catch return) catch {};
    }

    // Zig tip: `exprStmt` relies on the same Zig feature as `define` above: see the tip there.
    fn exprStmt(it: *Interp, e: *const Node) Signal!void {
        if (e.tag == .bin and (std.mem.eql(u8, e.text, "<+") or std.mem.eql(u8, e.text, "<-") or std.mem.eql(u8, e.text, "->"))) {
            return it.listOp(e);
        }
        const v = try it.eval(e);
        // a bare name that is a function or method is a call without arguments: `hello;`
        if (e.tag == .name and v == .func) _ = try it.callValue(v, null, &.{});
    }

    // Zig tip: `listOp` relies on the same Zig feature as `define` above: see the tip there.
    /// `a <+ x;` appends in place, `x <- a;` removes the first `x`, `a -> x;` removes the last.
    fn listOp(it: *Interp, e: *const Node) Signal!void {
        const op = e.text;
        const list_node = if (std.mem.eql(u8, op, "<-")) e.kids[1] else e.kids[0];
        const item_node = if (std.mem.eql(u8, op, "<-")) e.kids[0] else e.kids[1];
        const lv = try it.eval(list_node);
        const l = switch (lv) {
            .list, .set => |x| x,
            else => return it.fail("{s} needs a list, found {s}", .{ op, typeName(lv) }),
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
            for (items, 0..) |x, i| if (eq(x, item)) {
                found = i;
                break;
            };
        } else {
            var i = items.len;
            while (i > 0) {
                i -= 1;
                if (eq(items[i], item)) {
                    found = i;
                    break;
                }
            }
        }
        if (found) |i| _ = it.listRemove(l, i);
    }

    // Zig tip: `print` relies on the same Zig feature as `define` above: see the tip there.
    fn print(it: *Interp, n: *const Node) Signal!void {
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

    // Zig tip: `raise` relies on the same Zig feature as `realOf` above: see the tip there.
    fn raise(it: *Interp, n: *const Node) Signal {
        if (n.kids.len == 0) return it.fail("raise", .{});
        const v = it.eval(n.kids[0]) catch |e| return e;
        switch (v) {
            .str => |s| return it.fail("{s}", .{s}),
            .list => |l| {
                const items = l.elems();
                if (items.len == 2 and isInt(items[0])) {
                    return it.failWith(@intCast(@max(1, @min(255, intOf(items[0])))), "{s}", .{it.text(items[1]) catch ""});
                }
            },
            .object => |o| {
                const code: u8 = if (fieldOf(o, "code")) |c| @intCast(@max(1, @min(255, intOf(c)))) else err_raise;
                const msg = if (fieldOf(o, "message")) |m| (it.text(m) catch "") else "";
                return it.failWith(code, "{s}", .{msg});
            },
            else => {},
        }
        return it.fail("{s}", .{it.text(v) catch ""});
    }

    // ---- declarations and assignment ------------------------------------------------------

    // Zig tip: `declareRoutine` relies on the same Zig feature as `define` above: see the tip there.
    fn declareRoutine(it: *Interp, n: *const Node) Signal!void {
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
            if (parent.tag == .name and std.mem.eql(u8, parent.text, "Ordinal")) {
                c.ordinal = true;
                var next: i64 = 1;
                for (n.kids[0].kids) |m| {
                    if (m.kids[0].tag != .none) next = intOf(try it.eval(m.kids[0]));
                    try c.ord.append(it.a, .{ .name = m.text, .val = .{ .int = next } });
                    // names that start with a capital letter need no qualifier
                    if (std.ascii.isUpper(m.text[0])) try it.define(m.text, .{ .int = next }, true);
                    next += 1;
                }
            }
            try it.define(n.text, .{ .class = c }, true);
            return;
        }
        if (n.tag == .method) {
            try it.exts.append(it.a, n);
            return;
        }
        // a function declared inside another one closes over that call's scope (a closure, D-101)
        const f = try it.newFunc(n, if (it.scope == it.unit) it.unit else it.scope);
        try it.define(n.text, .{ .func = f }, true);
    }

    // Zig tip: `coerce` relies on the same Zig feature as `bind` above: see the tip there.
    fn coerce(v: Value, ty: ?*const Node) Value {
        const t = ty orelse return v;
        if (t.kids.len == 0 and std.mem.eql(u8, t.text, "Real") and isInt(v)) return .{ .real = @floatFromInt(intOf(v)) };
        // a Real given to an Integer loses its decimals (D-080)
        if (t.kids.len == 0 and std.mem.eql(u8, t.text, "Integer") and (v == .real or v == .float or v == .dec)) return .{ .int = @intFromFloat(realOf(v).?) };
        return v;
    }

    // Zig tip: `while (i > mark) { i -= 1; ... }` walks a list backwards: the last `defer`
    // registered runs first. `pop()` of an `ArrayList` returns an optional (null when empty).
    // `catch {}` drops an error on purpose: a failing `defer` does not hide the first error.
    /// Run the `defer` statements registered since `mark`, newest first, and forget them.
    fn runDefers(it: *Interp, mark: usize) void {
        while (it.defers.items.len > mark) {
            const stmt = it.defers.pop().?;
            it.exec(stmt) catch {};
        }
    }

    // Zig tip: `std.mem.eql(u8, a, b)` compares text. `orderedRemove(0)` takes the first element
    // and moves the others down; `pop()` takes the last one. The third kid of a capture node says
    // whether the name may already exist: `.none` is the explicit `new` (D-104).
    /// `let lst -> e;` takes the last element, `let e <- lst;` and `new e <- lst;` the first (D-104).
    fn capture(it: *Interp, n: *const Node) Signal!void {
        const lv = try it.eval(n.kids[0]);
        const l = switch (lv) {
            .list => |x| x,
            else => return it.fail("{s} needs a list, found {s}", .{ n.text, typeName(lv) }),
        };
        if (l.items.items.len == 0) return it.failWith(err_index, "Index 1 is out of range: the list is empty", .{});
        const item = if (std.mem.eql(u8, n.text, "->")) it.listPop(l) else it.listRemove(l, 0);
        const target = n.kids[1];
        if (target.tag == .name and std.mem.eql(u8, target.text, "_")) return;
        if (target.tag == .name) {
            const exists = it.scope.find(target.text) != null;
            if (n.kids[2].tag == .none or !exists) return it.define(target.text, item, false);
        }
        try it.assignTo(target, item);
    }

    // Zig tip: `declare` relies on the same Zig feature as `define` above: see the tip there.
    fn declare(it: *Interp, n: *const Node) Signal!void {
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
        v = coerce(v, n.ty);
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

    // Zig tip: `declareOne` relies on the same Zig feature as `define` above: see the tip there.
    fn declareOne(it: *Interp, t: *const Node, v: Value, constant: bool) Signal!void {
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

    // Zig tip: `assign` relies on the same Zig feature as `define` above: see the tip there.
    fn assign(it: *Interp, n: *const Node) Signal!void {
        const target = n.kids[0];
        const op = n.text;
        if (std.mem.eql(u8, op, "<+") or std.mem.eql(u8, op, "+>")) return it.listModifier(n);
        var v = try it.eval(n.kids[1]);
        if (std.mem.eql(u8, op, "::")) {
            v = try it.clone(v);
        } else if (!std.mem.eql(u8, op, ":=")) {
            const cur = try it.eval(target);
            // a list and a scalar: every element is updated in place (D-118)
            if (cur == .list and isScalar(v)) {
                const src = cur.list.elems();
                const out = try it.t.alloc(Value, src.len);
                for (src, 0..) |e, i| out[i] = try it.bulkOne(op[0..1], e, v);
                for (src, out) |*cell, x| it.setCell(cell, x);
                return;
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
                        for (gone) |g| if (eq(l.items.items[k], g)) {
                            drop = true;
                        };
                        if (drop) _ = it.listRemove(l, k) else k += 1;
                    }
                }
                return;
            }
            v = try it.apply(op[0..1], cur, v);
        }
        try it.assignTo(target, v);
    }

    // Zig tip: `let a <+ x;` has the list on the left, `let x +> a;` on the right: the arrow points
    // away from the list (D-107). `insert(allocator, 0, x)` puts an element at the front.
    /// `let lst <+ x;` appends, `let x +> lst;` puts in front. A list given as `x` adds its elements.
    fn listModifier(it: *Interp, n: *const Node) Signal!void {
        const front = n.text[0] == '+';
        const list_node = if (front) n.kids[1] else n.kids[0];
        const item = try it.eval(if (front) n.kids[0] else n.kids[1]);
        const lv = try it.eval(list_node);
        if (lv == .str) {
            const add = try it.text(item);
            const joined = if (front) try it.persist2(add, lv.str) else try it.persist2(lv.str, add);
            return it.assignTo(list_node, .{ .str = joined });
        }
        const l = switch (lv) {
            .list, .set => |x| x,
            else => return it.fail("{s} needs a list, found {s}", .{ n.text, typeName(lv) }),
        };
        if (lv == .set) return it.setAdd(l, item);
        if (front) {
            if (item == .list) try it.listInsertSlice(l, 0, item.list.elems()) else try it.listInsert(l, 0, item);
        } else if (item == .list) {
            try it.listAppendSlice(l, item.list.elems());
        } else try it.listAppend(l, item);
    }

    // Zig tip: `assignTo` relies on the same Zig feature as `define` above: see the tip there.
    fn assignTo(it: *Interp, target: *const Node, v: Value) Signal!void {
        switch (target.tag) {
            .name => {
                if (std.mem.eql(u8, target.text, "_")) return; // `_` drops the value
                const cell = it.scope.find(target.text) orelse return it.fail("undefined name '{s}'", .{target.text});
                if (cell.constant) return it.fail("'{s}' is a constant", .{target.text});
                it.setVar(cell, v);
            },
            .field => {
                const obj = try it.eval(target.kids[0]);
                if (obj != .object) return it.fail("{s} has no attributes", .{typeName(obj)});
                try it.setField(obj.object, target.text, v);
            },
            .index => {
                const r = try it.indexChain(target);
                const obj = r.obj;
                const args = r.args;
                if (obj == .map) return it.mapPut(obj.map, try it.eval(args[0]), v);
                if (obj != .list) return it.fail("{s} cannot be assigned by index", .{typeName(obj)});
                if (args.len == 1 and args[0].tag != .all and args[0].tag != .range and !isMatrix(obj.list)) {
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

    // Zig tip: `ifStmt` relies on the same Zig feature as `define` above: see the tip there.
    fn ifStmt(it: *Interp, n: *const Node) Signal!void {
        var i: usize = 0;
        while (i + 1 < n.kids.len) : (i += 2) {
            if (try it.truth(try it.eval(n.kids[i]))) return it.execBlock(n.kids[i + 1]);
        }
        if (n.kids.len % 2 == 1) try it.execBlock(n.kids[n.kids.len - 1]);
    }

    // Zig tip: a `break` or `skip` with a label unwinds through the inner loops as a Zig error; each
    // loop asks `caught` whether the signal is for it. A bare `break` (empty label) belongs to the
    // innermost loop, a labeled one to the loop with that label (D-034).
    fn caught(it: *Interp, label: []const u8) bool {
        if (it.jump_label.len == 0) return true;
        if (std.mem.eql(u8, it.jump_label, label)) {
            it.jump_label = "";
            return true;
        }
        return false;
    }

    // Zig tip: `whileStmt` relies on the same Zig feature as `define` above: see the tip there.
    fn whileStmt(it: *Interp, n: *const Node) Signal!void {
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

    // Zig tip: `forStmt` relies on the same Zig feature as `define` above: see the tip there.
    fn forStmt(it: *Interp, n: *const Node) Signal!void {
        const saved = try it.pushScope();
        defer it.leaveScope(saved);
        const source = try it.eval(n.kids[1]);
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

    // Zig tip: `while (true)` has no condition of its own: the loop ends only by `break`. The test
    // sits at the bottom, after the body. In `catch |e| switch (e)`, the branch `error.Skip => {}`
    // is an empty block: the error is swallowed and execution falls through to the bottom test,
    // which is exactly what `skip` means in a `repeat` loop. `n.kids.len > 2` checks whether the
    // optional `while` condition was written; a bare `repeat;` loops until `break`.
    /// `loop [header] do body repeat [while c];` (D-074): the body runs at least once.
    fn repeatStmt(it: *Interp, n: *const Node) Signal!void {
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

    // Zig tip: `matchStmt` relies on the same Zig feature as `define` above: see the tip there.
    fn matchStmt(it: *Interp, n: *const Node) Signal!void {
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
                    for (pat.kids) |k| if (eq(try it.eval(k), subject)) {
                        hit = true;
                    };
                    continue;
                }
                const pv = try it.eval(pat);
                if (switch (pv) {
                    .range, .domain => try it.contains(pv, subject),
                    else => eq(pv, subject),
                }) hit = true;
            }
            if (hit) {
                try it.execBlock(w.kids[1]);
                if (!all) break;
            }
        }
        try it.execBlock(n.kids[1]);
    }

    // ---- running a script -----------------------------------------------------------------

    // Zig tip: `errorObject` relies on the same Zig feature as `define` above: see the tip there.
    fn errorObject(it: *Interp) Signal!Value {
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
    fn runProcess(it: *Interp, p: *const Node, args: []const Arg, kind: []const u8, unit_name: []const u8) Signal!void {
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
        if (!hasLocal(it.scope, "jobs")) try it.define("jobs", .{ .map = jobs }, false);
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
    fn moduleMember(it: *Interp, m: *Module, name: []const u8) Signal!Value {
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
    fn instantiate(it: *Interp, node: *const Node) Signal!*Module {
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
    fn noneNode(it: *Interp) *const Node {
        _ = it;
        return &ast.none;
    }

    // Zig tip: bare names are shared, not copied: `bind` puts the same `Var` cell of the module under the
    // name in the importing scope, so a constant or a function is one thing seen from two places.
    /// Bring the exported names of a module into the current scope, without a prefix (`m(*)` and `*`).
    fn bindBare(it: *Interp, m: *Module) Signal!void {
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
    fn execImport(it: *Interp, decl: *const Node) Signal!void {
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

    // Zig tip: `finalize` of the modules runs when the driver has ended, after its process, in the reverse
    // order of the initialization (D-068): the loop counts down. An error in one `finalize` does not stop
    // the others: `catch {}` drops it.
    /// Run the `finalize` region of every loaded module, last loaded first.
    fn finalizeModules(it: *Interp) void {
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
    // with no parent but the names every script knows (`boot`): it cannot see the driver's variables,
    // and the state it builds is dropped with that scope when the call ends (D-066).
    /// `apply name(args);`: run the `main` of an aspect, read and checked before the run.
    fn applyAspect(it: *Interp, n: *const Node) Signal!void {
        const known = it.aspects orelse return it.fail("no aspect is loaded: '{s}'", .{n.text});
        const aspect = known.get(n.text) orelse return it.fail("aspect '{s}' is not loaded", .{n.text});
        const args = try it.evalArgs(n.kids);
        defer it.dropArgs(args);
        defer it.writeBack(args);
        try it.runAspect(aspect, args);
    }

    // Zig tip: `runAspect` relies on the same Zig feature as `applyAspect` above: see the tip there.
    /// Run the `main` of an aspect with evaluated arguments, in a fresh scope (D-066).
    fn runAspect(it: *Interp, aspect: *const Node, args: []const Arg) Signal!void {
        const saved_unit = it.unit;
        const saved_proc = it.proc_scope;
        if (saved_proc) |p| Heap.retainScope(p);
        try it.scope_stack.append(it.g, saved_unit);
        const saved_scope = try it.enterScope(try it.newScope(try it.preludeScope()));
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
            if (d.tag == .class or d.tag == .trait or d.tag == .function or d.tag == .procedure or d.tag == .method) try it.declareRoutine(d);
        }
        for (aspect.kids) |d| {
            if (d.tag == .var_decl or d.tag == .set) try it.exec(d);
        }
        const main = findProcess(aspect, "main") orelse return it.fail("the aspect '{s}' has no process main", .{aspect.text});
        try it.runProcess(main, args, "aspect", aspect.text);
    }


    // ---- level 4: parallel groups, channels, tasks (spec/semantics/multitasking.md) -----------------

    // Zig tip: `orelse` gives the value of an optional or, when it is null, the expression after it:
    // the driver's interpreter has no `root`, so it is its own base.
    /// The interpreter that owns the modules of the run: the driver's.
    fn base(it: *Interp) *Interp {
        return it.root orelse it;
    }

    // Zig tip: the scheduler is made only when the first task starts, so a program without parallel
    // work never pays for it. `catch return error.OutOfMemory` maps the one error `init` may return
    // onto the `Signal` set of the interpreter.
    /// The scheduler of the run, made on first use; the driver's thread becomes the root task.
    fn ensureSched(it: *Interp) Signal!*task.Sched {
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
    fn durText(it: *Interp, ms: i64) Signal![]const u8 {
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
    fn checkCancel(it: *Interp) Signal!void {
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
    fn waitFor(it: *Interp, ms: i64) Signal!void {
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
    fn blockOn(it: *Interp, wait: task.Wait, ch: *Channel, since: *?i64) Signal!void {
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

    // Zig tip: `$timeout` is an ordinary variable: an aspect shadows the driver value with its own
    // `set $timeout = 5s;` (D-081 rule 8), so the scope chain gives the right one. The default is 60 seconds.
    /// The longest wait on a channel, in milliseconds.
    fn timeoutMs(it: *Interp) i64 {
        if (it.scope.find("$timeout")) |v| if (isInt(v.value) and intOf(v.value) > 0) return intOf(v.value);
        return 60_000;
    }

    // Zig tip: the return type `Signal` without `!` is an error value itself: the caller writes
    // `return it.deadlock(...)` and the error travels up like any `raise`.
    /// Raise DeadlockError for this task, naming the operation and the channel (D-141).
    fn deadlock(it: *Interp, wait: task.Wait, ch: *Channel) Signal {
        const op = if (wait == .send) "send to" else "receive from";
        return it.failWith(42, "Deadlock: {s} waits to {s} {s}", .{ it.task_name, op, ch.name });
    }

    // Zig tip: named arguments arrive as `Arg` records with a `name`; a positional one has an empty name.
    // `capacity` is the first parameter and is required, `senders` the second (D-141).
    /// `Channel(:T)(capacity: n, senders: m)`.
    fn newChannel(it: *Interp, arg_nodes: []const *const Node) Signal!Value {
        const args = try it.evalArgs(arg_nodes);
        var capacity: ?i64 = null;
        var senders: i64 = 1;
        for (args, 0..) |a, i| {
            if (!isInt(a.value)) return it.fail("the arguments of a Channel are integers", .{});
            const named_cap = std.mem.eql(u8, a.name, "capacity") or (a.name.len == 0 and i == 0);
            const named_snd = std.mem.eql(u8, a.name, "senders") or (a.name.len == 0 and i == 1);
            if (named_cap) capacity = intOf(a.value) else if (named_snd) senders = intOf(a.value) else return it.fail("a Channel has no parameter '{s}'", .{a.name});
        }
        const cap = capacity orelse return it.fail("a Channel needs its capacity: Channel(:T)(capacity: n)", .{});
        if (cap < 1 or senders < 1) return it.fail("the capacity and the senders of a Channel are at least 1", .{});
        const ch = try it.h.make(Channel, .{ .capacity = @intCast(cap), .senders = @intCast(senders) });
        return .{ .chan = ch };
    }

    // Zig tip: `if (opt) |s|` runs only when the optional holds a value: without tasks there is no
    // scheduler and nobody to wake.
    /// Note a change that a waiting task may be interested in.
    fn moved(it: *Interp) void {
        if (it.sched) |s| s.progress += 1;
    }

    // Zig tip: `for (list.items) |x| if (x == ch) return;` searches a list of pointers: two pointers are
    // equal when they point to the same channel. The value is copied on send (`clone`), so a receiver
    // never shares a collection with the sender (D-141).
    /// `ch.send(v)`: wait while the channel is full; a closed channel is an error.
    fn send(it: *Interp, ch: *Channel, v: Value) Signal!void {
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
    fn receive(it: *Interp, ch: *Channel) Signal!?Value {
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
    fn closeChannel(it: *Interp, ch: *Channel) Signal!void {
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
    fn closeSent(it: *Interp) void {
        for (it.sent.items) |ch| it.closeChannel(ch) catch {};
    }

    // Zig tip: `orelse return ...` turns the null of a closed, empty channel into the error of `receive`;
    // `cell.value = v` writes through the pointer of the `@x` variable.
    /// The methods of a channel: `send`, `receive`, `close`, `count`.
    fn channelMethod(it: *Interp, ch: *Channel, name: []const u8, args: []const *const Node) Signal!Value {
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
    fn cut(it: *Interp, l: *List, by_count: bool, size: Value) Signal!Value {
        if (!isInt(size) or intOf(size) < 1) return it.fail("{s} takes a positive integer", .{if (by_count) "split" else "batch"});
        const items = l.elems();
        const n: usize = @intCast(intOf(size));
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
    fn elementRef(it: *Interp, r: *const Node) Signal!Arg {
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
    fn writeBack(it: *Interp, args: []const Arg) void {
        for (args) |a| if (a.cell) |c| {
            it.setCell(c, a.ref.?.value);
        };
    }

    // Zig tip: a struct literal with `.field = value` builds the child interpreter; the fields not
    // written take their defaults (empty lists, null pointers). The child shares the allocator, the
    // global names, the aspects, the modules and the scheduler with its parent; everything else is its own.
    /// A new interpreter for a task, writing to `out`.
    fn newChild(it: *Interp, out: *Io.Writer, name: []const u8) Signal!*Interp {
        const c = try it.a.create(Interp);
        const sc = try newScratch(it.a);
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
    fn launch(it: *Interp, st: *Started) Signal!void {
        st.t.thread = std.Thread.spawn(.{}, taskMain, .{st}) catch return it.fail("cannot start a thread for {s}", .{st.label});
    }

    // Zig tip: inputs are passed by value (D-048): `clone` copies a collection, so the parent may change
    // its variables while the task runs. A channel is not cloned: it is the one object tasks share.
    /// Copy the input arguments of a task.
    fn ownInputs(it: *Interp, args: []Arg) Signal!void {
        for (args) |*a| if (a.ref == null and a.value != .chan) {
            a.value = try it.clone(a.value);
        };
    }

    // Zig tip: `@intFromPtr` turns a pointer into a number, so variables and list elements, two different
    // types, can be kept in one list of addresses and compared. A channel is shared on purpose and is
    // skipped. The arguments and their nodes are matched one to one unless a spread changed the count.
    /// Refuse an output that another task of the group already owns: `$err_output` 43 (D-140).
    fn ownOutputs(it: *Interp, g: Group, nodes: []const *const Node, args: []const Arg) Signal!void {
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
    fn startAspect(it: *Interp, n: *const Node) Signal!void {
        const g = it.group orelse return it.fail("start is allowed only in the do region of a parallel group", .{});
        const s = try it.ensureSched();
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

    // Zig tip: `spawnTask` relies on the same Zig feature as `startAspect` above: see the tip there. A
    // spawned task prints to the same writer as its job: the tasks of a job share one core (D-104).
    /// `spawn f(args);`: start an async procedure as a task of the job (D-143).
    fn spawnTask(it: *Interp, n: *const Node) Signal!void {
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
    fn taskMain(st: *Started) void {
        const c = st.child;
        const s = c.sched.?;
        s.waitTurn(st.t);
        if (st.t.cancel != .none) {
            st.cancelled = true; // cancelled before it began: it never runs
        } else {
            const outcome = if (st.aspect) |asp| c.runAspect(asp, st.args) else blk: {
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
    fn parallelGroup(it: *Interp, n: *const Node) Signal!void {
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
            if (!isInt(d)) return it.fail("within takes a duration: within 30s", .{});
            limit = intOf(d);
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
    fn joinTasks(it: *Interp, members: *std.ArrayList(*Started), deadline: ?i64, limit: i64) Signal!void {
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
    fn endTasks(it: *Interp, members: *std.ArrayList(*Started)) Signal!void {
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
    fn collectAtDone(it: *Interp) void {
        if (it.root == null and it.h.since_trace > 1_000) it.h.trace();
    }

    // Zig tip: the error list is built as Eve objects, so `recover` reads it like any value:
    // `$error.errors[1].message`. `failWith` records the report and returns `error.Raise`; the extra
    // fields are added to that report before the error is returned (D-140).
    /// Raise one ParallelError (code 45) when a task of `members` failed.
    fn raiseFailed(it: *Interp, members: *std.ArrayList(*Started), label: []const u8) Signal!void {
        var failed: usize = 0;
        var cancelled: i64 = 0;
        const list = try it.newList(&.{}, false);
        var details: std.ArrayList(u8) = .empty;
        for (members.items, 1..) |m, i| {
            if (m.cancelled) cancelled += 1;
            if (!m.failed) continue;
            failed += 1;
            try appendFmt(&details, it.a, "  task {d} {s}: error {d}: {s}\n", .{ i, m.label, m.report.code, m.report.message });
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
    fn hasLocal(sc: *Scope, name: []const u8) bool {
        for (sc.binds.items) |b| if (std.mem.eql(u8, b.name, name)) return true;
        return false;
    }

    // Zig tip: `findProcess` relies on the same Zig feature as `bind` above: see the tip there.
    fn findProcess(root: *const Node, name: []const u8) ?*const Node {
        for (root.kids) |k| {
            if (k.tag == .process and std.mem.eql(u8, k.text, name)) return k;
        }
        return null;
    }

    // Zig tip: `run` relies on the same Zig feature as `callMethod` above: see the tip there.
    /// Run a script: a driver (declarations, then `process main`) or a free script (the statements).
    pub fn run(it: *Interp, root: *const Node) Outcome {
        it.h.root_fn = roots;
        it.h.root_ctx = it;
        defer if (heap.show_stats) it.h.report();
        const result = it.runRoot(root);
        if (result) |_| return .{} else |e| switch (e) {
            error.Stop => return .{ .stopped = true },
            error.Panic => {
                it.note(1, "panic");
                return .{ .code = 1 };
            },
            error.Raise, error.Abort => return .{ .code = exitCodeOf(it.err_code) },
            error.Over => return .{},
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
    fn exitCodeOf(code: u8) u8 {
        return switch (code) {
            2 => 2,
            3 => 3,
            else => 4,
        };
    }

    // Zig tip: `note` relies on the same Zig feature as `newList` above: see the tip there.
    fn note(it: *Interp, code: u8, msg: []const u8) void {
        it.reports.append(it.a, .{ .line = it.line, .code = code, .message = msg, .job = "" }) catch {};
    }

    // Zig tip: `runRoot` relies on the same Zig feature as `define` above: see the tip there.
    fn runRoot(it: *Interp, root: *const Node) Signal!void {
        if (root.tag == .script) {
            it.regionIn();
            defer it.regionOut();
            for (root.kids) |s| {
                try it.exec(s);
                it.safe();
            }
            return;
        }
        defer it.finalizeModules();
        for (root.kids) |d| if (d.tag == .import_decl) try it.execImport(d);
        for (root.kids) |d| {
            if (d.tag == .class or d.tag == .trait or d.tag == .function or d.tag == .procedure or d.tag == .method) try it.declareRoutine(d);
        }
        for (root.kids) |d| {
            if (d.tag == .var_decl or d.tag == .set) try it.exec(d);
        }
        const main = findProcess(root, "main") orelse return it.fail("the driver has no process main", .{});
        // the arguments of the command line go to the parameters of the process
        var args: std.ArrayList(Arg) = .empty;
        for (it.script_args) |a| try args.append(it.a, .{ .value = try it.staticStr(a) });
        try it.runProcess(main, args.items, "driver", root.text);
    }
};

// Zig tip: the interpreter is tested end to end: parse a script, run it, compare what it printed.
// `std.heap.ArenaAllocator` over the testing allocator frees every node and value at `deinit`,
// and the testing allocator then checks that nothing leaked. `Io.Writer.fixed` collects the output.
fn runSource(src: []const u8, buf: []u8) !struct { out: []const u8, code: u8 } {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var diag: @import("lexer.zig").Diag = .{};
    const root = try @import("parser.zig").parse(arena.allocator(), src, &diag);
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
    const r = try runSource("new a := 2;\nlet a += 3;\nexpect a == 5;\nprint \"a = {a}\";\n", &buf);
    try std.testing.expectEqualStrings("a = 5\n", r.out);
    try std.testing.expectEqual(@as(u8, 0), r.code);
}

// Zig tip: `a failed expect exits with 2 and recover catches a raise` relies on the same Zig feature
// as `a free script prints, computes and interpolates` above: see the tip there.
test "a failed expect exits with 2 and recover catches a raise" {
    var buf: [256]u8 = undefined;
    const r = try runSource("driver d is process main is print \"x\"; expect 1 == 2; return; end d;", &buf);
    try std.testing.expectEqualStrings("x\n", r.out);
    try std.testing.expectEqual(@as(u8, 2), r.code);
    const s = try runSource("driver d is process main is raise \"boom\"; recover print $error.message; return; end d;", &buf);
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
    const r = try runSource("new l := (1, 2, 3, 4, 5);\nprint l.split(2);\nprint l.batch(2);\n", &buf);
    try std.testing.expectEqualStrings("((1,2,3),(4,5))\n((1,2),(3,4),(5))\n", r.out);
}

// Zig tip: a test can look inside the interpreter after a run: `it.h.stats` counts what the heap made
// and freed. A loop that builds a string and a list at each pass must not keep them: reference
// counting frees them at the end of each pass, so only a few objects are alive at the end.
test "a loop frees what each pass makes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var diag: @import("lexer.zig").Diag = .{};
    const src = "new total := 0;\nfor i in (1..10000) do\n  new s := \"item {i}\";\n  new parts := (i, i + 1);\n  let total += parts.length();\ndone;\nprint total;\n";
    const root = try @import("parser.zig").parse(arena.allocator(), src, &diag);
    var buf: [64]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var it = try Interp.init(arena.allocator(), &w);
    defer it.deinit();
    _ = it.run(root);
    try std.testing.expectEqualStrings("20000\n", w.buffered());
    try std.testing.expect(it.h.stats.made > 20_000);
    try std.testing.expect(it.h.stats.live < 100);
}
