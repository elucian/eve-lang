//! The syntax tree of an Eve script, and the introspection of it: `dump` writes the tree as text,
//! `Stats` counts what a script is made of. The parser builds the tree, the interpreter walks it.
//!
//! One node type serves every construct. A node has a `tag` (what it is), a `text` (a name, an
//! operator, a literal) and `kids` (its parts, in the order documented at each tag below). This is
//! less strict than one struct per construct, but a dump or a statistic is then a few lines.
const std = @import("std");
const Io = std.Io;

// Zig tip: an `enum` with many names is Zig's list of cases. A name that is a Zig keyword (`if`,
// `while`, `for`, `break`...) cannot be written plainly: it needs `@"if"`. To avoid that every
// tag below that clashes ends with `_` (`if_`, `while_`...). `@tagName(x)` gives the name of an
// enum value as text, which is how the dump prints it without a table.
/// What a node is. The comment on each tag lists its `kids`.
pub const Tag = enum {
    /// A missing optional part (a shared empty node, never null).
    none,
    // ---- expressions ----
    /// `text` = the literal as written: `42`, `0xFF`, `3.5`.
    num,
    /// `text` = the decoded string.
    str,
    /// A string with interpolation: kids are `str` and `fmt` nodes, joined.
    interp,
    /// `\s{x:f}`, `\#{x}`, `\b{x}`: text = kind letter (`s`, `#`, `b`) then the format; kids = [expr].
    fmt,
    /// A symbol: `text` = its UTF-8 bytes.
    chr,
    /// A name: `text`.
    name,
    /// `$`, the last index inside `[ ]`.
    dollar,
    /// `*` inside `[ ]`: a whole dimension.
    all,
    /// `@name` in an argument: pass the variable by reference. `text` = the name.
    ref,
    /// `text` = operator (`+`, `and`, `in`, `not in`, `is`, `is not`, `<+`...); kids = [left, right].
    bin,
    /// `text` = `-`, `+` or `not`; kids = [operand].
    un,
    /// `text` = `..`, `..<`, `>..`, `>..<`; kids = [low, high].
    range,
    /// `x if c else y`: kids = [x, c, y].
    cond,
    /// `key: value` in a list, a call or an object: kids = [key, value].
    pair,
    /// `( a, b )`: kids = the items.
    list,
    /// `[ a, b ]`: kids = the items.
    array,
    /// `{ ... }`: text = `set`, `map` or `object`; kids = the items.
    brace,
    /// `(x | x in s and c)`: text = the opening symbol; kids = [item, generator].
    builder,
    /// `obj.name`: text = name; kids = [obj].
    field,
    /// `obj[i, j]`: kids = [obj, index...] (an index may be `dollar` or `all`).
    index,
    /// `f(a, b: 1, @c)`: kids = [callee, arg...].
    call,
    /// `(params) => (body)`: kids = [params, body].
    lambda,
    // ---- statements ----
    /// Statements: kids = the statements.
    block,
    /// `let` (a variable) or `set` (a constant): text = `:=`, `::`, `=` or empty; kids = [targets, value or none];
    /// `ty` = the declared type.
    var_decl,
    set,
    /// `let lst -> e;`, `new x <- lst;`: kids = [list, target], text = `->` or `<-`.
    capture,
    /// A `"""` text literal: a String that `type()` reports as Text.
    text_lit,
    /// `*list` in a call: the elements become arguments.
    spread,
    /// `?` as an end of a range: `(0..?)`.
    open_end,
    /// The names declared by a `let`: kids = `name`, `field` and `star` nodes (`star`: text = name, may be empty).
    targets,
    star,
    /// `target op value;`: text = `:=`, `::`, `+=`...; kids = [target, value].
    assign,
    /// An expression used as a statement: kids = [expr].
    expr_stmt,
    /// `print x;` and `write x;`: kids = [] or [expr].
    print_stmt,
    write_stmt,
    /// `expect cond;`: kids = [cond].
    expect_stmt,
    /// `raise x;`: kids = [] or [expr].
    raise_stmt,
    break_stmt,
    /// `skip;`: go to the continuation point of the loop (next element, condition, or the test of `repeat`).
    skip_stmt,
    over_stmt,
    exit_stmt,
    stop_stmt,
    pass_stmt,
    assert_stmt,
    defer_stmt,
    panic_stmt,
    retry_stmt,
    resume_stmt,
    abort_stmt,
    /// `stmt if cond;`: kids = [cond, stmt].
    cond_stmt,
    /// `if c do b else if c2 do b2 else b3 done;`: kids = [c, b, c2, b2, ..., else block (when odd)].
    if_,
    /// `while`: kids = [header block, cond, body, else block, then block]. `loop` has a header.
    while_,
    /// `for p in it do`: kids = [pattern, iterable, body, else block, then block].
    for_,
    /// `loop … do … repeat [while c];`: kids = [header block, body] or [header block, body, cond].
    repeat_,
    /// `match x when ...`: kids = [subject, then block, when...].
    match_,
    /// `when p do b`: kids = [pattern, block].
    when,
    /// `label: job do ... done label;`: text = label; kids = [body].
    job,
    // ---- declarations ----
    /// `process name is ... recover ... finalize ... return;`: kids = [body, recover or none, finalize or none].
    process,
    /// `function`, `method` and `constructor`: text = name; kids = [params, second params, results, body].
    function,
    procedure,
    method,
    constructor,
    /// `( [@]name [= default] [: Type] )`: kids = `param` and `ref_param` nodes (kids = [default or none]; `ty`).
    params,
    param,
    ref_param,
    vararg_param,
    /// `Integer`, `[5]Integer`: text = name; kids = the dimensions.
    type,
    /// `class Name = {members} <: Parent is ... end Name;`: kids = [members, parent name or none, routine...].
    class,
    /// A class member: text = name; kids = [explicit value or none]; `ty`.
    member,
    /// `driver name is ... end name;`: kids = the declarations.
    driver,
    /// `[exclusive|concurrent] aspect name is ... end name;`: kids = the declarations, with one `process main` (D-066, D-090);
    /// `public` is true for `concurrent`.
    aspect,
    /// `apply folder/name(args);`: text = the aspect path as written; kids = the arguments, as in a `call`.
    apply_stmt,
    /// A script without a driver: kids = the statements.
    script,
    /// `[managed|direct] module name is ... end name;` (D-129): kids = the declarations, the imports, the exports and
    /// up to three `region` nodes; `public` is true for `safe`.
    module,
    /// `from path use (items);`: text = the path as written (`lib/db`); kids = `import_item` nodes.
    import_decl,
    /// One item of an import: text = the module name, or `*` for every module of the folder; kids = [alias name or none];
    /// `public` is true for `m(*)`, the members without a prefix.
    import_item,
    /// `export (a, b!);`: kids = `name` nodes, text = the member name (with its `!`).
    export_decl,
    /// `initialize`, `recover` or `finalize` of a module: text = the word; kids = [block].
    region,
    // ---- level 4: parallel processing, tasks, traits (spec/semantics/multitasking.md) ----
    /// `[label:] parallel [on error cancel] [within d] decls do body done [label];`: text = label;
    /// kids = [declarations block, body block, deadline expression or none]; `public` is true for `on error cancel`.
    parallel,
    /// `start folder/name(args);`: like `apply_stmt`, only in the do region of a parallel group.
    start_stmt,
    /// `spawn f(args);`: kids = [call]; only in the do region of a job.
    spawn_stmt,
    /// `await f(args)`, an expression: kids = [call].
    await_,
    /// `wait duration;`: kids = [expression].
    wait_stmt,
    /// `Name(:T, :U)`, a generic class with its type arguments: text = the name; kids = the types.
    generic,
    /// `trait Name is ... end Name;`: the shape of a `class` (kids = [empty members, none, methods...]).
    trait,
};

// Zig tip: `std.StringHashMapUnmanaged(V)` is a hash map with text keys that does not remember its
// allocator (see the tip in check.zig). The aspects an `apply` can reach are found before the run
// (project.zig) and kept in one of these maps: the key is the path as written in the `apply`.
/// The parsed aspects of a project, by the path written in `apply`.
pub const Aspects = std.StringHashMapUnmanaged(*const Node);

// Zig tip: a second map, with the same shape, for the modules: the key is the path as written in
// the import, a `|` and the module name (`lib|counter`), so the interpreter finds the tree that the
// link step read without searching the disk again. The key `lib|*` holds a `block` node whose kids
// are the modules of the whole folder.
/// The parsed modules of a project, by `path|name`.
pub const Modules = std.StringHashMapUnmanaged(*const Node);

// Zig tip: a `struct` groups named fields (and functions); `pub` makes a name visible to other
// files; a field with `= value` has a default, so `.{ ... }` need not give it.
/// One node of the tree.
pub const Node = struct {
    tag: Tag,
    line: u32 = 0,
    col: u32 = 0,
    text: []const u8 = "",
    kids: []const *const Node = &.{},
    /// The declared type of a `new`, `set`, parameter or member.
    ty: ?*const Node = null,
    /// A member of a class written with `public` (the default is private, D-085).
    public: bool = false,
    /// A function or procedure declared `async`: it runs as a task, started by `spawn` or `await` (D-143).
    is_async: bool = false,
    /// The traits a class adopts, after its superclass in `<: (Object, Printable)` (D-145).
    extra: []const *const Node = &.{},
};

// Zig tip: a `const` of a struct type at file level is a value built while compiling. Parts that
// are missing in the source all point to this single node, so a `kids` slot is never null and the
// interpreter needs no `orelse`. `&none` is a pointer to it; it must be `const` to coerce to
// `*const Node`.
/// The node that stands for an absent optional part.
pub const none: Node = .{ .tag = .none };

// Zig tip: a function with `anytype` takes a value of any type, checked when it is used. A
// recursive function (`dump` calls itself for each kid) needs an explicit error type: the
// compiler cannot infer the errors of a function that calls itself, so `Io.Writer.Error!void` is
// written out. `for (n.kids) |k|` walks a slice; `\n` is a newline; `{d}` prints a number.
// `w.splatByteAll(' ', n)` writes the same byte n times (the indentation).
/// Write the tree as indented text, one node per line: `tag text @line`. `max_depth` cuts the output.
pub fn dump(w: *Io.Writer, n: *const Node, depth: usize, max_depth: usize) Io.Writer.Error!void {
    try w.splatByteAll(' ', depth * 2);
    try w.writeAll(@tagName(n.tag));
    if (n.text.len > 0) try w.print(" {s}", .{n.text});
    if (n.line > 0) try w.print("  @{d}", .{n.line});
    try w.writeByte('\n');
    if (depth + 1 >= max_depth) {
        if (n.kids.len > 0) {
            try w.splatByteAll(' ', (depth + 1) * 2);
            try w.print("... {d} more\n", .{n.kids.len});
        }
        return;
    }
    if (n.ty) |t| try dump(w, t, depth + 1, max_depth);
    for (n.kids) |k| try dump(w, k, depth + 1, max_depth);
}

// Zig tip: `std.EnumArray(Tag, usize)` is an array indexed by an enum: `counts.get(.num)`. It is
// as big as the enum and needs no hash map. `.initFill(0)` starts every cell at 0.
// `std.enums.values(Tag)` is the list of all the values of the enum, known at compile time.
/// What a script is made of: node count per tag, the deepest nesting, and the declared names.
pub const Stats = struct {
    counts: std.EnumArray(Tag, usize) = .initFill(0),
    nodes: usize = 0,
    depth: usize = 0,

    // Zig tip: `if (opt) |v| ... else ...` runs the first branch only when the optional has a value,
    // and names it `v`.
    /// Count `n` and everything under it.
    pub fn add(s: *Stats, n: *const Node, depth: usize) void {
        s.counts.set(n.tag, s.counts.get(n.tag) + 1);
        s.nodes += 1;
        s.depth = @max(s.depth, depth);
        if (n.ty) |t| s.add(t, depth + 1);
        for (n.kids) |k| s.add(k, depth + 1);
    }

    // Zig tip: `for (xs) |x| ...` walks a slice; `for (xs, 0..) |x, i|` also gives the index.
    /// One line per tag that occurs, most frequent first is left to the reader: tags are in declaration order.
    pub fn write(s: *const Stats, w: *Io.Writer) Io.Writer.Error!void {
        try w.print("nodes {d}, depth {d}\n", .{ s.nodes, s.depth });
        for (std.enums.values(Tag)) |t| {
            const c = s.counts.get(t);
            if (c > 0 and t != .none) try w.print("  {s: <12}{d}\n", .{ @tagName(t), c });
        }
    }
};

// Zig tip: a walk that collects names is another recursive function. `inline` is not needed: it
// is an ordinary run-time recursion. The `switch` on the tag has an `else => {}` branch for every
// tag it does not care about.
/// Write the declarations of the script: drivers, processes, functions, classes, variables.
pub fn outline(w: *Io.Writer, n: *const Node, depth: usize) Io.Writer.Error!void {
    switch (n.tag) {
        .driver, .aspect, .script => {
            try w.print("{s}{s} {s}\n", .{ indent(depth), @tagName(n.tag), n.text });
            for (n.kids) |k| try outline(w, k, depth + 1);
        },
        .process, .function, .procedure, .method, .constructor, .class, .job => {
            try w.print("{s}{s} {s}  @{d}\n", .{ indent(depth), @tagName(n.tag), n.text, n.line });
            for (n.kids) |k| try outline(w, k, depth + 1);
        },
        .var_decl, .set => {
            try w.print("{s}{s}", .{ indent(depth), @tagName(n.tag) });
            for (n.kids[0].kids) |t| try w.print(" {s}", .{t.text});
            try w.print("  @{d}\n", .{n.line});
        },
        .block, .if_, .while_, .for_, .repeat_, .match_, .when, .cond_stmt => for (n.kids) |k| try outline(w, k, depth),
        else => {},
    }
}

// Zig tip: builtin functions start with `@`: they are the compiler's own, such as conversions
// (`@intCast`, `@as`) and `@min`/`@max`.
fn indent(depth: usize) []const u8 {
    const spaces = "                                ";
    return spaces[0..@min(depth * 2, spaces.len)];
}

// Zig tip: a `test` block runs under `zig build test`; `try std.testing.expect...` fails it when the
// value is not the expected one.
test "dump writes one line per node" {
    var buf: [256]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    const a: Node = .{ .tag = .num, .line = 1, .text = "1" };
    const kids = [_]*const Node{&a};
    const n: Node = .{ .tag = .un, .line = 1, .text = "-", .kids = &kids };
    try dump(&w, &n, 0, 8);
    try std.testing.expectEqualStrings("un -  @1\n  num 1  @1\n", w.buffered());
    var s: Stats = .{};
    s.add(&n, 0);
    try std.testing.expectEqual(@as(usize, 2), s.nodes);
    try std.testing.expectEqual(@as(usize, 1), s.depth);
}
