//! The values of an Eve script and the objects they point to: `Value`, the lists, maps, objects,
//! classes, functions, scopes and variables, and the error codes. They are data with a few small
//! methods; the interpreter (evevm) works on them, and the database layer reads and builds them.
//! Part of evecm, so that no part has to import the interpreter to name a value.
const std = @import("std");
const ast = @import("ast.zig");
const decimal = @import("decimal.zig");
const heap = @import("heap.zig");
const Obj = heap.Obj;
const Node = ast.Node;

// Zig tip: an error set is a list of names; `||` merges sets. Every function that can fail while
// running a script returns `Signal!T`. Recursive functions (`eval` calls itself through its
// helpers) must name their error set: Zig cannot infer it for a cycle. The first names are
// control flow, the last two are the failures of the allocator and of the output writer.
/// What interrupts the normal flow of a script.
pub const Signal = error{ JobRollback, Raise, Break, Skip, Over, Exit, StopJob, Panic, Retry, Resume, Abort, Stop, Cancel, OutOfMemory, WriteFailed };

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
    /// A Decimal: an integer and a scale, exact (decimal.zig).
    dec: decimal.Dec,
    /// An Instant: microseconds since 1970-01-01T00:00:00Z (instant.zig).
    instant: i64,
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
pub var library_traits = [_]Class{
    .{ .name = "Printable", .trait = true },
    .{ .name = "Comparable", .trait = true },
    .{ .name = "Iterable", .trait = true },
    .{ .name = "Stream", .trait = true },
};

// Zig tip: `?*Class` may be null (an object made without a class); `orelse return false` answers for it.
/// Does the class, or one of its ancestors, adopt the trait called `name`?
pub fn adopts(cls: ?*Class, name: []const u8) bool {
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
pub const Arg = struct { name: []const u8 = "", value: Value, ref: ?*Var = null, cell: ?*Value = null };

pub const err_raise = 4;
pub const err_expect = 2;
pub const err_assert = 3;
pub const err_index = 10;
pub const err_key = 11;
pub const err_divide = 12;
pub const err_convert = 14;
pub const err_parse = 15;
pub const err_null = 16;
pub const err_argument = 17;
pub const err_file = 20;
pub const err_io = 22;
pub const err_access = 21;
pub const err_overflow = 13;
/// An error in a `sql function`, or a NULL for one of its non-nullable parameters: the query stops (D-166).
pub const err_sql = 59;

// ------------------------------------------------------------------ helpers on values
// Plain functions of the values, moved here from the interpreter: nothing in them needs it.

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
        .instant => "Instant",
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
pub fn isInt(v: Value) bool {
    return v == .int or v == .nat or v == .byte or v == .short or v == .huge;
}

// Zig tip: `intOf` relies on the same Zig feature as `typeName` above: see the tip there.
pub fn intOf(v: Value) i64 {
    return switch (v) {
        .int, .nat, .byte, .short, .huge => |n| n,
        else => 0,
    };
}

// Zig tip: builtin functions start with `@`: they are the compiler's own, such as conversions
// (`@intCast`, `@as`) and `@min`/`@max`.
pub fn realOf(v: Value) ?f64 {
    return switch (v) {
        .int, .nat, .byte, .short, .huge => |n| @floatFromInt(n),
        .real, .float => |r| r,
        .dec => |d| decimal.toF64(d),
        else => null,
    };
}

// Zig tip: an optional result lets one function say "this value is not a Decimal-compatible number". A whole
// number is a Decimal of scale 0, so `5 + 0.50d` is exact; a Real is not converted (spec: never mixed).
/// The value as a Decimal: a Decimal itself, or an integer.
pub fn decOf(v: Value) ?decimal.Dec {
    return switch (v) {
        .dec => |d| d,
        .int, .nat, .byte, .short, .huge => |n| decimal.fromInt(n),
        else => null,
    };
}

// Zig tip: `a orelse b` unwraps an optional: it gives `b` when `a` is null, and `b` may leave
// the function with `return`.
/// `==`: same value. Collections and objects compare their contents.
pub fn eq(a: Value, b: Value) bool {
    if (isInt(a) and isInt(b)) return intOf(a) == intOf(b);
    if (a == .dec or b == .dec) if (decOf(a)) |x| if (decOf(b)) |y| return decimal.order(x, y) == .eq;
    if (a == .instant) return b == .instant and a.instant == b.instant;
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
pub fn same(a: Value, b: Value) bool {
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
pub fn fieldOf(o: *Object, name: []const u8) ?Value {
    for (o.fields.items) |f| {
        if (std.mem.eql(u8, f.name, name)) return f.val;
    }
    return null;
}

// Zig tip: `textual` relies on the same Zig feature as `fail` above: see the tip there.
pub fn textual(v: Value) bool {
    return v == .str or v == .sym;
}

// Zig tip: a `switch` on a `Value` (a tagged union) with `=> true` arms and an `else` arm is the
// short way to ask "is it one of these cases?". A `bool` function like this one can be inlined.
/// A scalar is a single value: a number, a boolean, a symbol or a string (never a collection).
pub fn isScalar(v: Value) bool {
    return switch (v) {
        .bool, .int, .nat, .byte, .short, .huge, .real, .float, .dec, .sym, .str => true,
        else => false,
    };
}

// Zig tip: `classRoutine` relies on the same Zig feature as `bind` above: see the tip there.
pub fn classRoutine(c: *Class, name: []const u8) ?*const Node {
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
