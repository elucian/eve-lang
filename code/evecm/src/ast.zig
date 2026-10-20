//! @eve-module ast
//! @spec spec/syntax/grammar.md
//! @feature F-VM-01
//! @tests test/level1
//! The syntax tree of an Eve script, and the introspection of it: `dump` writes the tree as text,
//! `Stats` counts what a script is made of. The parser builds the tree, the interpreter walks it.
//!
//! One node type serves every construct. A node has a `tag` (what it is), a `text` (a name, an
//! operator, a literal) and `kids` (its parts, in the order documented at each tag below). This is
//! less strict than one struct per construct, but a dump or a statistic is then a few lines.
const std = @import("std");
const Io = std.Io;

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
    /// `while`: kids = [header block, cond, body, else block, empty block (was `then`)]. `loop` has a header.
    while_,
    /// `for p in it do`: kids = [pattern, iterable, body, else block, empty block (was `then`)].
    for_,
    /// `loop … do … repeat [while c];`: kids = [header block, body] or [header block, body, cond].
    repeat_,
    /// `match x when ...`: kids = [subject, empty block (was `then`), when...].
    match_,
    /// `when p do b`: kids = [pattern, block].
    when,
    /// `label: job do ... done label;`: text = label; kids = [body].
    job,
    // ---- declarations ----
    /// `process name is ... recover ... finalize ... return;`: kids = [body, recover or none, finalize or none, params, type list].
    process,
    /// `generator`: like a function with exactly one result; its body may `yield` (level 5, D-067).
    generator,
    /// `yield;` or `yield expr;`: kids = [] or [expr]. Only in the body of a generator.
    yield_stmt,
    /// `table name: Class in "connection" [as "schema.table"] [is clauses end name];` (level 5):
    /// text = the table name; kids = [class name (`name`), connection (`str`), database name (`str` or none), clause...].
    table_decl,
    /// One clause of a table: text = `key`, `generated`, `version`, `column`, `reference`, `read only`, `temporary` or `cached`;
    /// kids = the field names (`name` nodes), then for `column` the column name (`str`), for `reference` the table (`name`),
    /// for `cached` the duration.
    clause,
    /// `commit;` and `rollback;` in the do region of a job (database.md#transactions).
    commit_stmt,
    rollback_stmt,
    /// `update record do … done;`: kids = [record expression, block].
    update_stmt,
    /// `function`, `method` and `constructor`: text = name; kids = [params, type list, results, body]. The type list is
    /// a `params` node with a `param` for each type parameter (`ty` = its constraint), empty when not generic (D-148).
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
    /// `[exclusive|concurrent|primary] aspect name is ... end name;`: kids = the declarations and the processes, with
    /// a `process main` and perhaps private processes (D-179, D-181); `public` is true for `concurrent`, `primary` for
    /// `primary`. The root of an Eve macro is the node of its primary aspect, with the shared declarations and the other
    /// aspects among its kids (D-152, D-180).
    aspect,
    /// `apply folder/name(args);`: text = the aspect path as written; kids = the arguments, as in a `call`;
    /// `extra` = the written type list `(:T)` of a generic process (D-148).
    apply_stmt,
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

/// The parsed aspects of a project, by the path written in `apply`.
// @eve-impl the operators of the hot path as data, set by the parser (R1 of design/design-bytecode.md)
// @decision D-201
/// A binary operator that the interpreter (and later the bytecode) handles without comparing text; `other` is every other one.
pub const Op = enum(u8) { none, add, sub, mul, div, mod, eq, ne, lt, gt, le, ge, other, set, copy, push_back, push_front };

/// The `Op` of the text of an operator.
pub fn opOf(text: []const u8) Op {
    const map = std.StaticStringMap(Op).initComptime(.{
        .{ "+", .add }, .{ "-", .sub },  .{ "*", .mul }, .{ "/", .div }, .{ "%", .mod }, .{ "==", .eq },
        .{ "<>", .ne }, .{ "<", .lt },   .{ ">", .gt },  .{ "<=", .le }, .{ ">=", .ge },
    });
    return map.get(text) orelse .other;
}

/// The built-in type a `type` node names, set by the parser so that the interpreter does not compare type names; `other` is any other name.
pub const TypeKind = enum(u8) { none, integer, short, byte, natural, real, float, logic, decimal, instant, string, symbol, rune, dataset, datamap, other };

/// The `TypeKind` of the exact text of a type.
pub fn typeKindOf(text: []const u8) TypeKind {
    const map = std.StaticStringMap(TypeKind).initComptime(.{
        .{ "Integer", .integer }, .{ "Short", .short },     .{ "Byte", .byte },       .{ "Natural", .natural },
        .{ "Real", .real },       .{ "Float", .float },     .{ "Logic", .logic },     .{ "Decimal", .decimal },
        .{ "Instant", .instant }, .{ "String", .string },   .{ "Symbol", .symbol },   .{ "Rune", .rune },
        .{ "DataSet", .dataset }, .{ "DataMap", .datamap },
    });
    return map.get(text) orelse .other;
}

/// What the parser could convert of a number literal: a plain integer or a plain real; the rest is read at run time.
pub const LitKind = enum(u8) { none, int, real };

pub const Aspects = std.StringHashMapUnmanaged(*const Node);

/// The parsed modules of a project, by `path|name`.
pub const Modules = std.StringHashMapUnmanaged(*const Node);

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
    /// A function or procedure declared `external`: a signature with no body, the machine provides it (D-056, D-189).
    is_external: bool = false,
    /// A function declared `sql function`: SQLite (and later DuckDB) can call it from SQL (D-166).
    is_sql: bool = false,
    /// The traits a class adopts, after its superclass in `<: (Object, Printable)` (D-145).
    extra: []const *const Node = &.{},
    /// A call: the declaration the checker selected among overloaded ones, when it can decide at compile time
    /// (D-149). Null when the name is not overloaded or the choice waits for the values at run time.
    sel: ?*const Node = null,
    /// The root made from an Eve macro, and each aspect of it: the aspects see the shared declarations of the
    /// macro, which are the declarations of the root node (D-152).
    macro: bool = false,
    /// `bin`: the operator; `assign`: `set` for `:=`, `copy` for `::`, `push_back`/`push_front` for `<+`/`+>`, else the operator of `+=`, `-=`...
    op: Op = .none,
    /// `num`: a plain literal already converted; `lit_bits` holds the `i64` or the bits of the `f64`.
    lit_kind: LitKind = .none,
    /// `type`: the built-in type named by the text; `none` for a node made by the interpreter.
    tk: TypeKind = .none,
    lit_bits: u64 = 0,
    /// The file of a routine that does not belong to the main script (a module or an aspect found by the link); empty otherwise.
    file: ?*const []const u8 = null,

    /// An aspect declared `primary`: it is run by a command and no aspect applies or starts it (D-181).
    primary: bool = false,
};

/// The node that stands for an absent optional part.
/// The file of a routine, or empty.
pub fn fileOf(n: *const Node) []const u8 {
    return if (n.file) |f| f.* else "";
}

pub const none: Node = .{ .tag = .none };

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

/// What a script is made of: node count per tag, the deepest nesting, and the declared names.
pub const Stats = struct {
    counts: std.EnumArray(Tag, usize) = .initFill(0),
    nodes: usize = 0,
    depth: usize = 0,

    /// Count `n` and everything under it.
    pub fn add(s: *Stats, n: *const Node, depth: usize) void {
        s.counts.set(n.tag, s.counts.get(n.tag) + 1);
        s.nodes += 1;
        s.depth = @max(s.depth, depth);
        if (n.ty) |t| s.add(t, depth + 1);
        for (n.kids) |k| s.add(k, depth + 1);
    }

    /// One line per tag that occurs, most frequent first is left to the reader: tags are in declaration order.
    pub fn write(s: *const Stats, w: *Io.Writer) Io.Writer.Error!void {
        try w.print("nodes {d}, depth {d}\n", .{ s.nodes, s.depth });
        for (std.enums.values(Tag)) |t| {
            const c = s.counts.get(t);
            if (c > 0 and t != .none) try w.print("  {s: <12}{d}\n", .{ @tagName(t), c });
        }
    }
};

/// Write the declarations of the script: aspects, processes, functions, classes, variables.
pub fn outline(w: *Io.Writer, n: *const Node, depth: usize) Io.Writer.Error!void {
    switch (n.tag) {
        .aspect => {
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

fn indent(depth: usize) []const u8 {
    const spaces = "                                ";
    return spaces[0..@min(depth * 2, spaces.len)];
}

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

/// Does the type end with `?`: may the value be `null`?
pub fn isOptional(ty: ?*const Node) bool {
    const t = ty orelse return false;
    return t.text.len > 0 and t.text[t.text.len - 1] == '?';
}

/// The name of a type without its `?`; `String` for a member that has no type.
pub fn baseType(ty: ?*const Node) []const u8 {
    const t = ty orelse return "String";
    return std.mem.trimEnd(u8, t.text, "?");
}
