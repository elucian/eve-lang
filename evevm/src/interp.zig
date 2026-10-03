//! The interpreter: walks the syntax tree (ast.zig) and executes it. It is a plain "tree walker":
//! `exec` runs a statement, `eval` computes an expression, both by looking at the `tag` of the node.
//!
//! Control flow (break, next, over, raise, retry...) is carried by Zig errors (`Signal`): a `raise`
//! unwinds the Zig call stack up to the `recover` of the process, exactly as an exception would.
//! Every value the script creates is allocated from one arena and freed together when the run
//! ends, so there is no `free` anywhere in this file.
const std = @import("std");
const Io = std.Io;
const ast = @import("ast.zig");
const Node = ast.Node;

// Zig tip: an error set is a list of names; `||` merges sets. Every function that can fail while
// running a script returns `Signal!T`. Recursive functions (`eval` calls itself through its
// helpers) must name their error set: Zig cannot infer it for a cycle. The first names are
// control flow, the last two are the failures of the allocator and of the output writer.
/// What interrupts the normal flow of a script.
pub const Signal = error{ Raise, Break, Next, Over, Panic, Retry, Resume, Abort, Stop, OutOfMemory, WriteFailed };

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
    real: f64,
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
    /// The value of `Integer`, `String`, ... and of `type(x)`.
    typ: []const u8,
};

// Zig tip: a `struct` groups named fields (and functions); `pub` makes a name visible to other
// files; a field with `= value` has a default, so `.{ ... }` need not give it.
/// A list, an array, a set, or a view of a part of another list (a slice `v[2..3]`).
pub const List = struct {
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
/// A sorted map: the entries are kept in key order.
pub const Map = struct { entries: std.ArrayList(Entry) = .empty };

pub const Field = struct { name: []const u8, val: Value };
/// An object: named attributes in the order they were created; `class` is set for `new C(...)`.
pub const Object = struct { class: ?*Class = null, fields: std.ArrayList(Field) = .empty };

// Zig tip: `Class` relies on the same Zig feature as `List` above: see the tip there.
/// A class. `node` is null for the built-in `Object`. An ordinal class keeps its named values in `ord`.
pub const Class = struct {
    name: []const u8,
    node: ?*const Node = null,
    ordinal: bool = false,
    ord: std.ArrayList(Field) = .empty,
};

/// A function, method or lambda together with the scope it was created in.
pub const Func = struct { node: *const Node, closure: *Scope };

/// An integer range with both ends included; `(1..<5)` is stored as 1 to 4.
pub const Range = struct { lo: i64, hi: i64, step: i64 = 1 };

/// A variable. It is a separate struct so that a by-reference parameter can share it.
pub const Var = struct { value: Value, constant: bool = false };
pub const Binding = struct { name: []const u8, v: *Var };
// Zig tip: `Scope` relies on the same Zig feature as `List` above: see the tip there.
pub const Scope = struct {
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
};

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

const Arg = struct { name: []const u8 = "", value: Value, ref: ?*Var = null };

// Zig tip: `Interp` relies on the same Zig feature as `List` above: see the tip there.
pub const Interp = struct {
    a: std.mem.Allocator,
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
    reports: std.ArrayList(Report) = .empty,
    /// The error being handled (`$error`).
    err_code: u8 = err_raise,
    /// The scope of the last process that ran: kept so the introspection can list its variables.
    proc_scope: ?*Scope = null,

    // Zig tip: `init` builds the struct and `boot` fills the global scope. They are two steps
    // because the scope must live at a stable address (`a.create` gives a pointer that stays valid)
    // and the struct is returned by value. `a.create(Scope)` allocates one; `.* = .{}` sets it.
    pub fn init(a: std.mem.Allocator, out: *Io.Writer) Signal!Interp {
        const g = try a.create(Scope);
        g.* = .{};
        var it: Interp = .{ .a = a, .out = out, .global = g, .scope = g };
        try it.boot();
        return it;
    }

    // Zig tip: `for (xs) |x| ...` walks a slice; `for (xs, 0..) |x, i|` also gives the index.
    /// Define the names every script knows: `True`, `False`, `Null`, the type names, `Object`, `_`.
    fn boot(it: *Interp) Signal!void {
        try it.define("True", .{ .bool = true }, true);
        try it.define("False", .{ .bool = false }, true);
        try it.define("Null", .nil, true);
        try it.define("_", .nil, false);
        const types = [_][]const u8{ "Integer", "Natural", "Real", "Symbol", "String", "Logic", "List", "Array", "DataSet", "HashMap" };
        for (types) |t| try it.define(t, .{ .typ = t }, true);
        const object = try it.a.create(Class);
        object.* = .{ .name = "Object" };
        try it.define("Object", .{ .class = object }, true);
    }

    // ---- errors ---------------------------------------------------------------------------

    // Zig tip: `fail` formats a message into the arena and returns `error.Raise`, so a caller writes
    // `return it.fail("...", .{})`. The message is kept in `reports`, where the `recover` block
    // (`$error.message`) and the `errors` command read it. `comptime fmt` is checked against `args`.
    /// Raise an error with a code and a message.
    fn failWith(it: *Interp, code: u8, comptime fmt: []const u8, args: anytype) Signal {
        const msg = std.fmt.allocPrint(it.a, fmt, args) catch return error.OutOfMemory;
        it.reports.append(it.a, .{ .line = it.line, .code = code, .message = msg, .job = it.current_job }) catch return error.OutOfMemory;
        it.err_code = code;
        return error.Raise;
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
        const cell = try it.a.create(Var);
        cell.* = .{ .value = v, .constant = constant };
        try it.bind(name, cell);
    }

    // Zig tip: `std.mem.eql(u8, a, b)` compares two slices by content; `==` on slices would compare
    // their addresses.
    fn bind(it: *Interp, name: []const u8, cell: *Var) Signal!void {
        for (it.scope.binds.items) |*b| {
            if (std.mem.eql(u8, b.name, name)) {
                b.v = cell;
                return;
            }
        }
        try it.scope.binds.append(it.a, .{ .name = name, .v = cell });
    }

    // Zig tip: `lookup` relies on the same Zig feature as `fail` above: see the tip there.
    fn lookup(it: *Interp, name: []const u8) Signal!Value {
        if (it.scope.find(name)) |v| return v.value;
        return it.fail("undefined name '{s}'", .{name});
    }

    // Zig tip: `pushScope` relies on the same Zig feature as `define` above: see the tip there.
    fn pushScope(it: *Interp) Signal!*Scope {
        const saved = it.scope;
        const s = try it.a.create(Scope);
        s.* = .{ .parent = saved };
        it.scope = s;
        return saved;
    }

    // ---- values: construction and inspection ----------------------------------------------

    // Zig tip: `std.ArrayList(T)` is a growable array: it starts `.empty`, `append(allocator, x)`
    // adds, `.items` is the slice of what it holds.
    fn newList(it: *Interp, items: []const Value, array: bool) Signal!*List {
        const l = try it.a.create(List);
        l.* = .{ .array = array };
        try l.items.appendSlice(it.a, items);
        return l;
    }

    // Zig tip: `newObject` relies on the same Zig feature as `define` above: see the tip there.
    fn newObject(it: *Interp) Signal!*Object {
        const o = try it.a.create(Object);
        o.* = .{};
        return o;
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
            .real => "Real",
            .sym => "Symbol",
            .str => "String",
            .list => |l| if (l.array) "Array" else "List",
            .set => "DataSet",
            .map => "HashMap",
            .object => |o| if (o.class) |c| c.name else "Object",
            .class => "Class",
            .func => "Function",
            .range => "Range",
            .typ => "Type",
        };
    }

    // Zig tip: `isInt` relies on the same Zig feature as `fail` above: see the tip there.
    fn isInt(v: Value) bool {
        return v == .int or v == .nat;
    }

    // Zig tip: `intOf` relies on the same Zig feature as `typeName` above: see the tip there.
    fn intOf(v: Value) i64 {
        return switch (v) {
            .int, .nat => |n| n,
            else => 0,
        };
    }

    // Zig tip: builtin functions start with `@`: they are the compiler's own, such as conversions
    // (`@intCast`, `@as`) and `@min`/`@max`.
    fn realOf(v: Value) ?f64 {
        return switch (v) {
            .int, .nat => |n| @floatFromInt(n),
            .real => |r| r,
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
                f.val = v;
                return;
            }
        }
        try o.fields.append(it.a, .{ .name = name, .val = v });
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
        try s.items.insert(it.a, i, v);
    }

    // Zig tip: `setOf` relies on the same Zig feature as `define` above: see the tip there.
    fn setOf(it: *Interp, v: Value) Signal!*List {
        const s = try it.a.create(List);
        s.* = .{};
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
                if (!isInt(v)) return false;
                const n = intOf(v);
                return n >= r.lo and n <= r.hi and @mod(n - r.lo, r.step) == 0;
            },
            .str => |s| return v == .str and std.mem.indexOf(u8, s, v.str) != null,
            else => return it.fail("'in' needs a collection, found {s}", .{typeName(coll)}),
        }
    }

    // Zig tip: `clone` relies on the same Zig feature as `define` above: see the tip there.
    /// `::`: a deep copy. Natives are copied anyway.
    fn clone(it: *Interp, v: Value) Signal!Value {
        switch (v) {
            .list, .set => |l| {
                const c = try it.a.create(List);
                c.* = .{ .array = l.array };
                for (l.elems()) |e| try c.items.append(it.a, try it.clone(e));
                return if (v == .set) .{ .set = c } else .{ .list = c };
            },
            .map => |m| {
                const c = try it.a.create(Map);
                c.* = .{};
                for (m.entries.items) |e| try c.entries.append(it.a, .{ .key = e.key, .val = try it.clone(e.val) });
                return .{ .map = c };
            },
            .object => |o| {
                const c = try it.newObject();
                c.class = o.class;
                for (o.fields.items) |f| try c.fields.append(it.a, .{ .name = f.name, .val = try it.clone(f.val) });
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
        try buf.appendSlice(it.a, tmp[0..n]);
    }

    // Zig tip: `appendFmt` relies on the same Zig feature as `define` above: see the tip there.
    fn appendFmt(it: *Interp, buf: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) Signal!void {
        try buf.appendSlice(it.a, try std.fmt.allocPrint(it.a, fmt, args));
    }

    // Zig tip: `show` writes the text of a value into a growable byte list. `quoted` is true inside
    // a collection, where strings and symbols are shown with their quotes. `inline else` is not
    // needed: every kind is listed. `for (items, 0..) |e, i|` loops with the index `i` too.
    /// Append the text `print` gives for `v`.
    fn show(it: *Interp, buf: *std.ArrayList(u8), v: Value, quoted: bool) Signal!void {
        switch (v) {
            .nil => try buf.appendSlice(it.a, "Null"),
            .bool => |b| try buf.appendSlice(it.a, if (b) "True" else "False"),
            .int, .nat => |n| try it.appendFmt(buf, "{d}", .{n}),
            .real => |r| try it.appendFmt(buf, "{d}", .{r}),
            .sym => |c| {
                if (quoted) try buf.append(it.a, '\'');
                try it.utf8(buf, c);
                if (quoted) try buf.append(it.a, '\'');
            },
            .str => |s| {
                if (quoted) try buf.append(it.a, '"');
                try buf.appendSlice(it.a, s);
                if (quoted) try buf.append(it.a, '"');
            },
            .list, .set => |l| {
                const open: u8 = if (v == .set) '{' else if (l.array) '[' else '(';
                const close: u8 = if (v == .set) '}' else if (l.array) ']' else ')';
                try buf.append(it.a, open);
                for (l.elems(), 0..) |e, i| {
                    if (i > 0) try buf.append(it.a, ',');
                    try it.show(buf, e, true);
                }
                try buf.append(it.a, close);
            },
            .map => |m| {
                try buf.append(it.a, '{');
                for (m.entries.items, 0..) |e, i| {
                    if (i > 0) try buf.append(it.a, ',');
                    try it.show(buf, e.key, true);
                    try buf.append(it.a, ':');
                    try it.show(buf, e.val, true);
                }
                try buf.append(it.a, '}');
            },
            .object => |o| {
                try buf.append(it.a, '{');
                for (o.fields.items, 0..) |f, i| {
                    if (i > 0) try buf.append(it.a, ',');
                    try it.appendFmt(buf, "{s}:", .{f.name});
                    try it.show(buf, f.val, true);
                }
                try buf.append(it.a, '}');
            },
            .class => |c| try it.appendFmt(buf, "class {s}", .{c.name}),
            .func => try buf.appendSlice(it.a, "<function>"),
            .range => |r| try it.appendFmt(buf, "({d}..{d})", .{ r.lo, r.hi }),
            .typ => |t| try buf.appendSlice(it.a, t),
        }
    }

    // Zig tip: `text` relies on the same Zig feature as `define` above: see the tip there.
    pub fn text(it: *Interp, v: Value) Signal![]const u8 {
        var buf: std.ArrayList(u8) = .empty;
        try it.show(&buf, v, false);
        return buf.items;
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
            const digits = try std.fmt.allocPrint(it.a, "{d}", .{intOf(v)});
            const neg = digits[0] == '-';
            const ds = if (neg) digits[1..] else digits;
            if (neg) try buf.append(it.a, '-');
            for (ds, 0..) |c, k| {
                if (k > 0 and (ds.len - k) % 3 == 0) try buf.append(it.a, ',');
                try buf.append(it.a, c);
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
        try out.appendNTimes(it.a, fill, left);
        try out.appendSlice(it.a, body);
        try out.appendNTimes(it.a, fill, pad - left);
        return out.items;
    }

    // Zig tip: a format string must be known while compiling, so a precision that is only known
    // when the script runs cannot be written `{d:.*}`. `inline for` repeats its body once per
    // value of the range, each time with a compile-time `p`, so `"{d:." ++ digit ++ "}"` is built
    // by the compiler for p = 0, 1, 2, ... and the run-time `prec` picks the right copy.
    /// A Real with `prec` decimals.
    fn fixed(it: *Interp, x: f64, prec: usize) Signal![]const u8 {
        inline for (0..10) |p| {
            if (prec == p) return std.fmt.allocPrint(it.a, "{d:." ++ std.fmt.comptimePrint("{d}", .{p}) ++ "}", .{x});
        }
        return std.fmt.allocPrint(it.a, "{d:.9}", .{x});
    }

    // Zig tip: `interpolate` relies on the same Zig feature as `define` above: see the tip there.
    fn interpolate(it: *Interp, n: *const Node) Signal!Value {
        var buf: std.ArrayList(u8) = .empty;
        for (n.kids) |part| {
            if (part.tag == .str) {
                try buf.appendSlice(it.a, part.text);
            } else {
                const v = try it.eval(part.kids[0]);
                try buf.appendSlice(it.a, try it.format(part.text[0], part.text[1..], v));
            }
        }
        return .{ .str = buf.items };
    }

    // ---- expressions ----------------------------------------------------------------------

    // Zig tip: `std.mem.replaceScalar`-style cleanup is avoided: the number text is copied without
    // its `_` separators into a stack buffer. `std.fmt.parseInt(i64, s, 0)` with base 0 reads the
    // prefix itself (`0x`, `0b`). A failure falls back to a Real, so a huge integer literal is
    // still a number. `std.fmt.parseFloat(f64, s)` reads `3.5`.
    fn number(it: *Interp, n: *const Node) Signal!Value {
        var buf: [64]u8 = undefined;
        var len: usize = 0;
        for (n.text) |c| {
            if (c == '_' or len == buf.len) continue;
            buf[len] = c;
            len += 1;
        }
        const t = buf[0..len];
        if (std.mem.indexOfScalar(u8, t, '.') != null) {
            return .{ .real = std.fmt.parseFloat(f64, t) catch return it.fail("bad number {s}", .{n.text}) };
        }
        const v = std.fmt.parseInt(i64, t, 0) catch {
            return .{ .real = std.fmt.parseFloat(f64, t) catch return it.fail("bad number {s}", .{n.text}) };
        };
        if (t.len > 1 and t[0] == '0' and (t[1] == 'x' or t[1] == 'b')) return .{ .nat = v };
        return .{ .int = v };
    }

    // Zig tip: `symbolOf` relies on the same Zig feature as `utf8` above: see the tip there.
    /// The code point of the UTF-8 text of a symbol node.
    fn symbolOf(t: []const u8) u21 {
        return std.unicode.utf8Decode(t) catch 0xFFFD;
    }

    // Zig tip: `eval` relies on the same Zig feature as `define` above: see the tip there.
    pub fn eval(it: *Interp, n: *const Node) Signal!Value {
        switch (n.tag) {
            .num => return it.number(n),
            .str => return .{ .str = n.text },
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
                const l = try it.a.create(List);
                l.* = .{ .array = n.tag == .array };
                for (n.kids) |k| try l.items.append(it.a, try it.eval(k));
                return .{ .list = l };
            },
            .brace => return it.brace(n),
            .builder => return it.builder(n),
            .field => return it.field(n),
            .index => return it.index(n),
            .call => return it.call(n),
            .new => return it.construct(n),
            .lambda => {
                const f = try it.a.create(Func);
                f.* = .{ .node = n, .closure = it.scope };
                return .{ .func = f };
            },
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
            .int => |x| .{ .int = -x },
            .nat => |x| .{ .int = -x },
            .real => |x| .{ .real = -x },
            else => it.fail("cannot negate {s}", .{typeName(v)}),
        };
    }

    // Zig tip: `makeRange` relies on the same Zig feature as `define` above: see the tip there.
    fn makeRange(it: *Interp, n: *const Node) Signal!Value {
        const lo = try it.eval(n.kids[0]);
        const hi = try it.eval(n.kids[1]);
        if (!isInt(lo) or !isInt(hi)) return it.fail("a range needs integers, found {s} and {s}", .{ typeName(lo), typeName(hi) });
        const r = try it.a.create(Range);
        r.* = .{
            .lo = intOf(lo) + @as(i64, if (n.text[0] == '>') 1 else 0),
            .hi = intOf(hi) - @as(i64, if (n.text[n.text.len - 1] == '<') 1 else 0),
        };
        return .{ .range = r };
    }

    // Zig tip: `brace` relies on the same Zig feature as `define` above: see the tip there.
    /// `{ ... }`: a DataSet, a HashMap or an Object, as the parser decided.
    fn brace(it: *Interp, n: *const Node) Signal!Value {
        if (std.mem.eql(u8, n.text, "set")) {
            const s = try it.a.create(List);
            s.* = .{};
            for (n.kids) |k| try it.setAdd(s, try it.eval(k));
            return .{ .set = s };
        }
        if (std.mem.eql(u8, n.text, "map")) {
            const m = try it.a.create(Map);
            m.* = .{};
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
            m.entries.items[i].val = val;
            return;
        }
        var i: usize = 0;
        while (i < m.entries.items.len and (try it.order(m.entries.items[i].key, key)) == .lt) i += 1;
        try m.entries.insert(it.a, i, .{ .key = key, .val = val });
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
        return it.fail("integer overflow", .{});
    }

    // Zig tip: `@addWithOverflow(a, b)` returns a tuple `.{ result, overflowed }`; Eve raises an
    // error instead of wrapping around silently. `@mulWithOverflow` and `@subWithOverflow` are alike.
    // `std.math.pow(f64, x, y)` is the power for reals; integers use a loop of multiplications.
    /// Apply a binary operator to two values.
    fn apply(it: *Interp, op: []const u8, l: Value, r: Value) Signal!Value {
        const eql = std.mem.eql;
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
            if (l != .str or r != .str) return it.fail("a regular expression match needs two strings", .{});
            return .{ .bool = regexMatch(r.str, l.str) == eql(u8, op, "=~") };
        }
        if (eql(u8, op, "||") or eql(u8, op, "&&")) return it.setOp(op[0], l, r);
        if (eql(u8, op, "<+")) return it.concat(l, r);
        if (eql(u8, op, "+")) {
            if (textual(l) or textual(r)) return .{ .str = try std.mem.concat(it.a, u8, &.{ try it.text(l), try it.text(r) }) };
        }
        if (eql(u8, op, "-") and (l == .set or l == .list) and (r == .set or r == .list)) return it.setOp('-', l, r);
        if (eql(u8, op, "*") and l == .str and isInt(r)) {
            var buf: std.ArrayList(u8) = .empty;
            var k: i64 = 0;
            while (k < intOf(r)) : (k += 1) try buf.appendSlice(it.a, l.str);
            return .{ .str = buf.items };
        }
        if (eql(u8, op, "><")) return it.product(l, r);
        // numbers
        if (realOf(l) == null or realOf(r) == null) {
            return it.fail("operator {s} does not apply to {s} and {s}", .{ op, typeName(l), typeName(r) });
        }
        if (eql(u8, op, "/")) {
            const d = realOf(r).?;
            if (d == 0) return it.fail("division by zero", .{});
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
                if (y == 0) return it.fail("division by zero", .{});
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

    // Zig tip: `isOp` relies on the same Zig feature as `bind` above: see the tip there.
    fn isOp(it: *Interp, l: Value, r: Value) bool {
        _ = it;
        if (l == .typ and r == .typ) return std.mem.eql(u8, l.typ, r.typ);
        if (r == .typ) return std.mem.eql(u8, typeName(l), r.typ);
        return same(l, r);
    }

    // Zig tip: `setOp` relies on the same Zig feature as `define` above: see the tip there.
    /// `||` union, `&&` intersection, `-` difference: the result is a DataSet.
    fn setOp(it: *Interp, op: u8, l: Value, r: Value) Signal!Value {
        const a = try it.setOf(l);
        const b = try it.setOf(r);
        const out = try it.a.create(List);
        out.* = .{};
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
        const out = try it.a.create(List);
        out.* = .{ .array = src.array };
        try out.items.appendSlice(it.a, src.elems());
        if (r == .list) try out.items.appendSlice(it.a, r.list.elems()) else try out.items.append(it.a, r);
        return .{ .list = out };
    }

    // Zig tip: `product` relies on the same Zig feature as `define` above: see the tip there.
    /// `A >< B`: the pairs (a, b) of two collections, as a list of lists.
    fn product(it: *Interp, l: Value, r: Value) Signal!Value {
        const xs = try it.iterate(l);
        const ys = try it.iterate(r);
        const out = try it.a.create(List);
        out.* = .{};
        for (xs) |x| for (ys) |y| try out.items.append(it.a, .{ .list = try it.newList(&.{ x, y }, false) });
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
                while (k <= r.hi) : (k += r.step) try out.append(it.a, .{ .int = k });
                return out.items;
            },
            .str => |s| {
                var out: std.ArrayList(Value) = .empty;
                var view = std.unicode.Utf8View.init(s) catch return it.fail("the string is not valid UTF-8", .{});
                var iter = view.iterator();
                while (iter.nextCodepoint()) |cp| try out.append(it.a, .{ .sym = cp });
                return out.items;
            },
            .map => |m| {
                var out: std.ArrayList(Value) = .empty;
                for (m.entries.items) |e| try out.append(it.a, .{ .list = try it.newList(&.{ e.key, e.val }, false) });
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
        defer it.scope = saved;
        var conds: std.ArrayList(*const Node) = .empty;
        var g = n.kids[1];
        while (g.tag == .bin and std.mem.eql(u8, g.text, "and")) {
            try conds.append(it.a, g.kids[1]);
            g = g.kids[0];
        }
        if (g.tag != .bin or !std.mem.eql(u8, g.text, "in")) return it.fail("a builder needs 'x in collection'", .{});
        const pat = g.kids[0];
        const src = g.kids[1];
        const open = n.text[0];
        const out = try it.a.create(List);
        out.* = .{ .array = open == '[' };

        if (src.tag == .bin and std.mem.eql(u8, src.text, "><")) {
            const xs = try it.iterate(try it.eval(src.kids[0]));
            const ys = try it.iterate(try it.eval(src.kids[1]));
            for (xs) |x| {
                const row = try it.a.create(List);
                row.* = .{ .array = true };
                for (ys) |y| {
                    try it.bindPattern(pat, .{ .list = try it.newList(&.{ x, y }, false) });
                    if (!try it.allTrue(conds.items)) continue;
                    const v = try it.eval(n.kids[0]);
                    if (open == '[') try row.items.append(it.a, v) else try it.collect(out, open, v);
                }
                if (open == '[') try out.items.append(it.a, .{ .list = row });
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
        if (open == '{') try it.setAdd(out, v) else try out.items.append(it.a, v);
    }

    // One index of `a[i, j]`: a number, `$` (already a number), `*` (all) or a range.
    const Idx = union(enum) { one: i64, all, rng: struct { lo: i64, hi: i64 } };

    // Zig tip: `isMatrix` relies on the same Zig feature as `realOf` above: see the tip there.
    /// A matrix or a tensor is an array whose elements are arrays.
    fn isMatrix(l: *List) bool {
        return l.elems().len > 0 and l.elems()[0] == .list;
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
            return .{ .rng = .{ .lo = r.range.lo, .hi = r.range.hi } };
        }
        const v = try it.eval(n);
        if (!isInt(v)) return it.fail("an index must be an integer, found {s}", .{typeName(v)});
        return .{ .one = intOf(v) };
    }

    // Zig tip: `leaves` relies on the same Zig feature as `define` above: see the tip there.
    fn leaves(it: *Interp, l: *List, out: *std.ArrayList(*Value)) Signal!void {
        for (l.elems()) |*e| {
            if (e.* == .list) try it.leaves(e.list, out) else try out.append(it.a, e);
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
            .all => for (cells) |c| try out.append(it.a, c),
            .one => |k| {
                if (k < 1 or k > cells.len) return it.fail("index {d} out of range 1..{d}", .{ k, cells.len });
                try out.append(it.a, cells[@intCast(k - 1)]);
            },
            .rng => |r| {
                if (r.lo > r.hi) return;
                if (r.lo < 1 or r.hi > cells.len) return it.fail("range {d}..{d} out of range 1..{d}", .{ r.lo, r.hi, cells.len });
                for (cells[@intCast(r.lo - 1)..@intCast(r.hi)]) |c| try out.append(it.a, c);
            },
        }
    }

    // Zig tip: `walk` relies on the same Zig feature as `define` above: see the tip there.
    fn walk(it: *Interp, l: *List, args: []const *const Node, depth: usize, out: *std.ArrayList(*Value)) Signal!void {
        const ix = try it.evalIdx(args[depth], dimLen(l, 0));
        var cells: std.ArrayList(*Value) = .empty;
        for (l.elems()) |*e| try cells.append(it.a, e);
        var picked: std.ArrayList(*Value) = .empty;
        try it.pick(cells.items, ix, &picked);
        for (picked.items) |c| {
            if (depth + 1 == args.len) {
                try out.append(it.a, c);
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
            try groups.append(it.a, root.kids[1..]);
        }
        std.mem.reverse([]const *const Node, groups.items);
        var obj = try it.eval(root);
        var i: usize = 0;
        while (i + 1 < groups.items.len) : (i += 1) {
            if (obj == .list and isMatrix(obj.list)) {
                var merged: std.ArrayList(*const Node) = .empty;
                for (groups.items[i..]) |g| try merged.appendSlice(it.a, g);
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
                const i = mapFind(m, key) orelse return it.fail("key not found", .{});
                return m.entries.items[i].val;
            },
            .list, .set => |l| {
                // a range on a one-dimensional list is a view: it shares the storage
                if (args.len == 1 and args[0].tag == .range and !isMatrix(l)) {
                    const ix = try it.evalIdx(args[0], @intCast(l.elems().len));
                    const lo = ix.rng.lo;
                    const hi = ix.rng.hi;
                    if (lo < 1 or hi > l.elems().len or lo > hi + 1) return it.fail("range {d}..{d} out of range 1..{d}", .{ lo, hi, l.elems().len });
                    const v = try it.a.create(List);
                    v.* = .{ .array = l.array, .base = l, .off = @intCast(lo - 1), .len = @intCast(hi - lo + 1) };
                    return .{ .list = v };
                }
                var cells: std.ArrayList(*Value) = .empty;
                try it.slots(l, args, &cells);
                if (cells.items.len == 1 and args[0].tag != .all and args[args.len - 1].tag != .all) return cells.items[0].*;
                const out = try it.a.create(List);
                out.* = .{ .array = true };
                for (cells.items) |c| try out.items.append(it.a, c.*);
                return .{ .list = out };
            },
            .str => |s| {
                const items = try it.iterate(obj);
                const ix = try it.evalIdx(args[0], @intCast(items.len));
                _ = s;
                if (ix != .one or ix.one < 1 or ix.one > items.len) return it.fail("index out of range", .{});
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
        if (callee.tag == .field) return it.callMethod(try it.eval(callee.kids[0]), callee.text, args);
        if (callee.tag == .name and std.mem.eql(u8, callee.text, "type") and it.scope.find("type") == null) {
            if (args.len != 1) return it.fail("type() takes one argument", .{});
            return .{ .typ = typeName(try it.eval(args[0])) };
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
                if (!isInt(step) or intOf(step) < 1) return it.fail("the step of a range is a positive integer", .{});
                const c = try it.a.create(Range);
                c.* = .{ .lo = r.lo, .hi = r.hi, .step = intOf(step) };
                return .{ .range = c };
            },
            else => return it.fail("{s} is not callable", .{typeName(v)}),
        }
    }

    // Zig tip: `classRoutine` relies on the same Zig feature as `bind` above: see the tip there.
    fn classRoutine(c: *Class, name: []const u8) ?*const Node {
        const node = c.node orelse return null;
        for (node.kids[2..]) |r| {
            if (r.tag != .constructor and std.mem.eql(u8, r.text, name)) return r;
        }
        return null;
    }

    // Zig tip: `if (opt) |v| ... else ...` runs the first branch only when the optional has a value,
    // and names it `v`.
    fn callMethod(it: *Interp, recv: Value, name: []const u8, args: []const *const Node) Signal!Value {
        if (recv == .object) {
            if (recv.object.class) |c| {
                if (classRoutine(c, name)) |r| {
                    const f = try it.a.create(Func);
                    f.* = .{ .node = r, .closure = it.global };
                    return it.invoke(f, recv, args);
                }
            }
        }
        const eql = std.mem.eql;
        if (eql(u8, name, "length")) {
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
            const out = try it.a.create(List);
            out.* = .{};
            var parts = std.mem.splitSequence(u8, recv.str, sep);
            while (parts.next()) |p| try out.items.append(it.a, .{ .str = p });
            return .{ .list = out };
        }
        if (eql(u8, name, "join") and (recv == .list or recv == .set) and args.len == 1) {
            const sep = try it.text(try it.eval(args[0]));
            var buf: std.ArrayList(u8) = .empty;
            for (recv.list.elems(), 0..) |e, i| {
                if (i > 0) try buf.appendSlice(it.a, sep);
                try it.show(&buf, e, false);
            }
            return .{ .str = buf.items };
        }
        return it.fail("{s} has no method '{s}'", .{ typeName(recv), name });
    }

    // Zig tip: `evalArgs` relies on the same Zig feature as `define` above: see the tip there.
    /// Evaluate the arguments of a call in the caller's scope.
    fn evalArgs(it: *Interp, nodes: []const *const Node) Signal![]Arg {
        var out: std.ArrayList(Arg) = .empty;
        for (nodes) |a| {
            if (a.tag == .pair and a.kids[0].tag == .name) {
                try out.append(it.a, .{ .name = a.kids[0].text, .value = try it.eval(a.kids[1]) });
            } else if (a.tag == .ref) {
                const cell = it.scope.find(a.text) orelse return it.fail("undefined name '{s}'", .{a.text});
                try out.append(it.a, .{ .value = cell.value, .ref = cell });
            } else try out.append(it.a, .{ .value = try it.eval(a) });
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
        const node = f.node;
        const saved = it.scope;
        const s = try it.a.create(Scope);
        s.* = .{ .parent = f.closure };
        it.scope = s;
        defer it.scope = saved;
        if (node.tag == .lambda) {
            try it.bindParams(node.kids[0].kids, args, null);
            return it.eval(node.kids[1]);
        }
        var self_var: ?*Var = null;
        if (recv) |r| {
            self_var = try it.a.create(Var);
            self_var.?.* = .{ .value = r };
        }
        try it.bindParams(node.kids[0].kids, args, self_var);
        for (node.kids[2].kids) |res| try it.define(res.text, try it.zero(res.ty), false);
        try it.execBlock(node.kids[3]);
        if (node.kids[2].kids.len > 0) return s.find(node.kids[2].kids[0].text).?.value;
        return .nil;
    }

    // Zig tip: `construct` relies on the same Zig feature as `define` above: see the tip there.
    /// `new Class(args)`.
    fn construct(it: *Interp, n: *const Node) Signal!Value {
        const c = n.kids[0];
        const callee = if (c.tag == .call) c.kids[0] else c;
        const arg_nodes: []const *const Node = if (c.tag == .call) c.kids[1..] else &.{};
        const cv = try it.eval(callee);
        if (cv != .class) return it.fail("'new' needs a class, found {s}", .{typeName(cv)});
        const cls = cv.class;
        const obj = try it.newObject();
        if (cls.node == null) return .{ .object = obj };
        const args = try it.evalArgs(arg_nodes);
        var ctor: ?*const Node = null;
        for (cls.node.?.kids[2..]) |r| if (r.tag == .constructor) {
            ctor = r;
        };
        if (ctor) |k| {
            const saved = it.scope;
            const s = try it.a.create(Scope);
            s.* = .{ .parent = it.global };
            it.scope = s;
            defer it.scope = saved;
            const self_var = try it.a.create(Var);
            self_var.* = .{ .value = .nil };
            try it.bindParams(k.kids[0].kids, &.{}, self_var);
            try it.bindParams(k.kids[1].kids, args, null);
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
            const l = try it.a.create(List);
            l.* = .{ .array = true };
            var k: i64 = 0;
            while (k < intOf(dim)) : (k += 1) try l.items.append(it.a, try it.zero(&inner));
            return .{ .list = l };
        }
        const eql = std.mem.eql;
        if (eql(u8, t.text, "Integer")) return .{ .int = 0 };
        if (eql(u8, t.text, "Natural")) return .{ .nat = 0 };
        if (eql(u8, t.text, "Real")) return .{ .real = 0 };
        if (eql(u8, t.text, "Logic")) return .{ .bool = false };
        return .nil;
    }

    // ---- regular expressions --------------------------------------------------------------

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
    fn execBlock(it: *Interp, b: *const Node) Signal!void {
        for (b.kids) |s| try it.exec(s);
    }

    // Zig tip: `tick` is the "step" of the execution loop: it counts the statement, remembers its
    // line, and lets the VM look into the slot for external commands. A hook is a function pointer
    // plus an opaque context pointer (`*anyopaque`): the interpreter calls "something" without
    // knowing the VM, so this file does not import vm.zig.
    fn tick(it: *Interp, n: *const Node) Signal!void {
        if (it.hook) |h| {
            if (h.poll(h.ctx, it.steps, it.line)) return error.Stop;
        }
        it.steps += 1;
        if (n.line > 0) it.line = n.line;
    }

    // Zig tip: `exec` relies on the same Zig feature as `define` above: see the tip there.
    pub fn exec(it: *Interp, n: *const Node) Signal!void {
        try it.tick(n);
        switch (n.tag) {
            .let, .set => try it.declare(n),
            .assign => try it.assign(n),
            .expr_stmt => try it.exprStmt(n.kids[0]),
            .print_stmt, .write_stmt => try it.print(n),
            .expect_stmt => {
                if (!try it.truth(try it.eval(n.kids[0]))) return it.failWith(err_expect, "expect failed", .{});
            },
            .raise_stmt => return it.raise(n),
            .break_stmt => return error.Break,
            .next_stmt => return error.Next,
            .over_stmt => return error.Over,
            .panic_stmt => return error.Panic,
            .retry_stmt => return error.Retry,
            .resume_stmt => return error.Resume,
            .abort_stmt => return error.Abort,
            .cond_stmt => if (try it.truth(try it.eval(n.kids[0]))) try it.exec(n.kids[1]),
            .if_ => try it.ifStmt(n),
            .while_ => try it.whileStmt(n),
            .for_ => try it.forStmt(n),
            .match_ => try it.matchStmt(n),
            .job => {
                const saved = it.current_job;
                it.current_job = n.text;
                defer it.current_job = saved;
                try it.execBlock(n.kids[0]);
            },
            .class, .function, .method => try it.declareRoutine(n),
            .process => {},
            else => return it.fail("cannot execute a {s}", .{@tagName(n.tag)}),
        }
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
            if (item == .list) try l.items.appendSlice(it.a, item.list.elems()) else try l.items.append(it.a, item);
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
        if (found) |i| _ = l.items.orderedRemove(i);
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
                    if (k.tag == .pair and k.kids[0].tag == .name and std.mem.eql(u8, k.kids[0].text, "separator")) {
                        sep = try it.text(try it.eval(k.kids[1]));
                    }
                }
                for (e.kids) |k| {
                    if (k.tag == .pair) continue;
                    if (!first) try buf.appendSlice(it.a, sep);
                    first = false;
                    try it.show(&buf, try it.eval(k), false);
                }
            } else try it.show(&buf, try it.eval(e), false);
        }
        if (is_print) try buf.append(it.a, '\n');
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
        if (n.tag == .class) {
            const c = try it.a.create(Class);
            c.* = .{ .name = n.text, .node = n };
            const parent = n.kids[1];
            if (parent.tag == .name and std.mem.eql(u8, parent.text, "Ordinal")) {
                c.ordinal = true;
                var next: i64 = 0;
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
        const f = try it.a.create(Func);
        f.* = .{ .node = n, .closure = it.global };
        try it.define(n.text, .{ .func = f }, true);
    }

    // Zig tip: `coerce` relies on the same Zig feature as `bind` above: see the tip there.
    fn coerce(v: Value, ty: ?*const Node) Value {
        const t = ty orelse return v;
        if (t.kids.len == 0 and std.mem.eql(u8, t.text, "Real") and isInt(v)) return .{ .real = @floatFromInt(intOf(v)) };
        return v;
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
            for (targets) |t| try it.declareOne(t, v, constant);
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
        var v = try it.eval(n.kids[1]);
        if (std.mem.eql(u8, op, "::")) {
            v = try it.clone(v);
        } else if (!std.mem.eql(u8, op, ":=")) {
            const cur = try it.eval(target);
            // += and -= on a collection change it in place
            if ((cur == .list or cur == .set) and (op[0] == '+' or op[0] == '-')) {
                const l = if (cur == .list) cur.list else cur.set;
                if (op[0] == '+') {
                    if (cur == .set) {
                        for ((try it.setOf(v)).items.items) |e| try it.setAdd(l, e);
                    } else if (v == .list) {
                        try l.items.appendSlice(it.a, v.list.elems());
                    } else try l.items.append(it.a, v);
                } else {
                    const gone: []const Value = if (v == .set or (cur == .set and v == .list)) (try it.setOf(v)).items.items else &.{v};
                    var k: usize = 0;
                    while (k < l.items.items.len) {
                        var drop = false;
                        for (gone) |g| if (eq(l.items.items[k], g)) {
                            drop = true;
                        };
                        if (drop) _ = l.items.orderedRemove(k) else k += 1;
                    }
                }
                return;
            }
            v = try it.apply(op[0..1], cur, v);
        }
        try it.assignTo(target, v);
    }

    // Zig tip: `assignTo` relies on the same Zig feature as `define` above: see the tip there.
    fn assignTo(it: *Interp, target: *const Node, v: Value) Signal!void {
        switch (target.tag) {
            .name => {
                const cell = it.scope.find(target.text) orelse return it.fail("undefined name '{s}'", .{target.text});
                if (cell.constant) return it.fail("'{s}' is a constant", .{target.text});
                cell.value = v;
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
                var cells: std.ArrayList(*Value) = .empty;
                try it.slots(obj.list, args, &cells);
                for (cells.items) |c| c.* = v;
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

    // Zig tip: `whileStmt` relies on the same Zig feature as `define` above: see the tip there.
    fn whileStmt(it: *Interp, n: *const Node) Signal!void {
        const saved = try it.pushScope();
        defer it.scope = saved;
        try it.execBlock(n.kids[0]);
        var ran = false;
        while (try it.truth(try it.eval(n.kids[1]))) {
            ran = true;
            it.execBlock(n.kids[2]) catch |e| switch (e) {
                error.Break => break,
                error.Next => continue,
                else => return e,
            };
        }
        if (!ran) try it.execBlock(n.kids[3]);
        try it.execBlock(n.kids[4]);
    }

    // Zig tip: `forStmt` relies on the same Zig feature as `define` above: see the tip there.
    fn forStmt(it: *Interp, n: *const Node) Signal!void {
        const saved = try it.pushScope();
        defer it.scope = saved;
        const items = try it.iterate(try it.eval(n.kids[1]));
        var ran = false;
        for (items) |x| {
            ran = true;
            try it.bindPattern(n.kids[0], x);
            it.execBlock(n.kids[2]) catch |e| switch (e) {
                error.Break => break,
                error.Next => continue,
                else => return e,
            };
        }
        if (!ran) try it.execBlock(n.kids[3]);
        try it.execBlock(n.kids[4]);
    }

    // Zig tip: `matchStmt` relies on the same Zig feature as `define` above: see the tip there.
    fn matchStmt(it: *Interp, n: *const Node) Signal!void {
        const subject = try it.eval(n.kids[0]);
        for (n.kids[2..]) |w| {
            const pat = w.kids[0];
            var hit = false;
            if (pat.tag == .name and std.mem.eql(u8, pat.text, "other") and it.scope.find("other") == null) {
                hit = true;
            } else {
                const pv = try it.eval(pat);
                hit = switch (pv) {
                    .range => try it.contains(pv, subject),
                    .list => if (pat.tag == .list) try it.contains(pv, subject) else eq(pv, subject),
                    else => eq(pv, subject),
                };
            }
            if (hit) {
                try it.execBlock(w.kids[1]);
                break;
            }
        }
        try it.execBlock(n.kids[1]);
    }

    // ---- running a script -----------------------------------------------------------------

    // Zig tip: `errorObject` relies on the same Zig feature as `define` above: see the tip there.
    fn errorObject(it: *Interp) Signal!Value {
        const o = try it.newObject();
        const r = it.reports.items[it.reports.items.len - 1];
        try it.setField(o, "message", .{ .str = r.message });
        try it.setField(o, "code", .{ .int = r.code });
        try it.setField(o, "job" , .{ .str = r.job });
        return .{ .object = o };
    }

    // Zig tip: `catch |e| switch (e) { ... }` handles each error name differently: `Raise` goes to
    // `recover`, `Over` ends the process quietly, anything else is passed up with `return e`.
    // `continue` inside the `catch` block restarts the loop without advancing `i`: that is how `retry`
    // runs the same statement again, and `resume` (which adds one to `i`) skips it.
    /// Run a process: its statements, then `recover` after an error, then `finalize`.
    fn runProcess(it: *Interp, p: *const Node) Signal!void {
        const saved = try it.pushScope();
        defer it.scope = saved;
        it.proc_scope = it.scope;
        const body = p.kids[0].kids;
        const recover = p.kids[1];
        const finalize = p.kids[2];
        var i: usize = 0;
        var failed: ?Signal = null;
        while (i < body.len) {
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
                        else => return re,
                    };
                    it.reports.items[idx].handled = true;
                    break;
                },
                error.Over => return,
                else => return e,
            };
            i += 1;
        }
        if (finalize.tag != .none) try it.execBlock(finalize);
        if (failed) |f| return f;
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
        const result = it.runRoot(root);
        if (result) |_| return .{} else |e| switch (e) {
            error.Stop => return .{ .stopped = true },
            error.Panic => {
                it.note(1, "panic");
                return .{ .code = 1 };
            },
            error.Raise => return .{ .code = it.err_code },
            error.Abort => return .{ .code = it.err_code },
            error.Over => return .{},
            error.OutOfMemory => return .{ .code = 70 },
            error.WriteFailed => return .{ .code = 74 },
            else => {
                it.note(4, "break, next, retry or resume used outside its statement");
                return .{ .code = 4 };
            },
        }
    }

    // Zig tip: `note` relies on the same Zig feature as `newList` above: see the tip there.
    fn note(it: *Interp, code: u8, msg: []const u8) void {
        it.reports.append(it.a, .{ .line = it.line, .code = code, .message = msg, .job = "" }) catch {};
    }

    // Zig tip: `runRoot` relies on the same Zig feature as `define` above: see the tip there.
    fn runRoot(it: *Interp, root: *const Node) Signal!void {
        if (root.tag == .script) {
            for (root.kids) |s| try it.exec(s);
            return;
        }
        for (root.kids) |d| {
            if (d.tag == .class or d.tag == .function or d.tag == .method) try it.declareRoutine(d);
        }
        for (root.kids) |d| {
            if (d.tag == .let or d.tag == .set) try it.exec(d);
        }
        const main = findProcess(root, "main") orelse return it.fail("the driver has no process main", .{});
        try it.runProcess(main);
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
    const o = it.run(root);
    return .{ .out = w.buffered(), .code = o.code };
}

// Zig tip: a `test` block runs under `zig build test`; `try std.testing.expect...` fails it when the
// value is not the expected one.
test "a free script prints, computes and interpolates" {
    var buf: [256]u8 = undefined;
    const r = try runSource("let a := 2;\na += 3;\nexpect a == 5;\nprint \"a = \\#{a}\";\n", &buf);
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
