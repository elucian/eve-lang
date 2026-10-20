//! @eve-module parser.routines
//! @spec spec/syntax/grammar.md
//! @feature F-VM-01
//! @decision D-179
//! @see code/evecp/src/parser.zig:Parser
//! Type names, parameters and routines.
const std = @import("std");
const lexer = @import("../lexer.zig");
const ast = @import("evecm").ast;
const Node = ast.Node;
const Tag = ast.Tag;
const Error = lexer.Error;
const Parser = @import("../parser.zig").Parser;

/// `Integer`, `[5]Integer`, `[]Integer`, `()Integer`, `Integer?`.
pub fn typeName(p: *Parser) Error!*const Node {
    var dims: std.ArrayList(*const Node) = .empty;
    var prefix: []const u8 = "";
    if (p.isSym("{")) {
        // `{:}(String, Integer)` is a DataMap type, `{Integer | Real}` a variant type
        const open = p.advance();
        if (p.acceptSym(":")) {
            try p.expectSym("}");
            try p.expectSym("(");
            _ = try p.typeName();
            try p.expectSym(",");
            _ = try p.typeName();
            try p.expectSym(")");
            return p.mk(.type, open, "DataMap", &.{});
        }
        while (true) {
            _ = try p.typeName();
            if (!p.acceptSym("|")) break;
        }
        try p.expectSym("}");
        return p.mk(.type, open, "{variant}", &.{});
    }
    if (p.isSym("(") and p.isSymAt(1, ")")) {
        _ = p.advance();
        _ = p.advance();
        prefix = "()";
    } else if (p.acceptSym("[")) {
        if (!p.isSym("]")) {
            while (true) {
                try dims.append(p.a, try p.expr());
                if (!p.acceptSym(",")) break;
            }
        }
        try p.expectSym("]");
        if (dims.items.len == 0) prefix = "[]"; // `[5]Integer` keeps the element type and the size
    }
    const name = try p.expectName("a type name");
    if (std.mem.eql(u8, name.text, "Atomic") and p.isSym("(")) {
        // `Atomic(:Integer)` (D-132): a library class that wraps a Zig atomic. In this single-threaded
        // machine it is the type `Integer` with the flag `public` set, so every check and every
        // default value of `Integer` applies and the link step can ask "is this variable atomic?"
        _ = p.advance();
        try p.expectSym(":"); // a type argument starts with ':', the visual signal that a type follows
        const inner = try p.typeName();
        try p.expectSym(")");
        const wrapped = try p.mk(.type, name, inner.text, inner.kids);
        @constCast(wrapped).public = true;
        return wrapped;
    }
    var generic_arg: ?*const Node = null;
    if (p.isSym("(") and p.isSymAt(1, ":")) {
        // `Channel(:Integer)`, `Box(:T)`: the type arguments of a generic class (D-145). The first one
        // is kept in `ty`; version 0.3 erases the type arguments at run time.
        _ = p.advance();
        while (true) {
            try p.expectSym(":");
            const arg = try p.typeName();
            if (generic_arg == null) generic_arg = arg;
            if (!p.acceptSym(",")) break;
        }
        try p.expectSym(")");
    }
    const suffix: []const u8 = if (p.acceptSym("?")) "?" else "";
    const text = if (prefix.len == 0 and suffix.len == 0) name.text else try std.fmt.allocPrint(p.a, "{s}{s}{s}", .{ prefix, name.text, suffix });
    const node = try p.mk(.type, name, text, dims.items);
    node.ty = generic_arg;
    return node;
}

/// `( [@|*]name [= value | := value] [: Type], ... )` of a function, procedure, method, constructor,
/// process or lambda; also the result list `(@r: Type, ...)`. A type is shared by the names before it
/// that have none (D-028). `*name` is the vararg, `@name` the input/output parameter (D-048, D-106).
pub fn params(p: *Parser) Error!*const Node {
    const open = p.peek();
    try p.expectSym("(");
    var list: std.ArrayList(*const Node) = .empty;
    var pending: usize = 0; // index of the first parameter that still waits for a type
    if (!p.isSym(")")) {
        while (true) {
            const kind: Tag = if (p.acceptSym("@")) .ref_param else if (p.acceptSym("*")) .vararg_param else .param;
            const name = try p.expectName("a parameter name");
            var default: *const Node = p.noneNode();
            if (p.acceptSym("=") or p.acceptSym(":=")) default = try p.expr();
            const prm = try p.mk(kind, name, name.text, &.{default});
            try list.append(p.a, prm);
            if (p.acceptSym(":")) {
                const ty = try p.typeName();
                for (list.items[pending..]) |q| {
                    if (q.ty == null) @constCast(q).ty = ty;
                }
                pending = list.items.len;
            }
            if (!p.acceptSym(",")) break;
        }
    }
    try p.expectSym(")");
    return p.mk(.params, open, "", list.items);
}

// @decision D-029
// @decision D-100
// @decision D-101
/// `function|procedure|method|constructor name [(params)] [=> (results)] is block return ;`.
pub fn routine(p: *Parser, tag: Tag) Error!*const Node {
    return p.routineOf(tag, false);
}

// @decision D-145
/// A function, procedure, method or constructor; with `partial`, a signature that may end with `;`.
pub fn routineOf(p: *Parser, tag: Tag, partial: bool) Error!*const Node {
    const saved_group = p.group_depth;
    const saved_job = p.job_depth;
    const saved_process = p.in_process;
    const saved_generator = p.in_generator;
    p.group_depth = 0;
    p.job_depth = 0;
    p.in_process = false;
    p.in_generator = tag == .generator; // a function inside a generator can not yield (Eve has no coroutines)
    defer {
        p.group_depth = saved_group;
        p.job_depth = saved_job;
        p.in_process = saved_process;
        p.in_generator = saved_generator;
    }
    const kw = p.advance();
    const name = if (tag == .constructor or tag == .destructor) kw else if (p.external_name) try p.expectAnyName() else try p.expectName("a name");
    const empty = try p.mk(.params, kw, "", &.{});
    const types = try p.typeList();
    const first = if (p.isSym("(")) try p.params() else empty;
    // @decision D-123
    if (tag == .generator) {
        // a generator has inputs only, by value (declarations.md#generators-level-5)
        for (first.kids) |q| if (q.tag == .ref_param and !std.mem.eql(u8, q.text, "self")) return p.failAt(kw, "a generator has inputs only, by value: '@{s}' is not allowed", .{q.text});
    }
    if (tag == .function or tag == .procedure) {
        for (first.kids) |q| {
            if (q.tag == .ref_param and std.mem.eql(u8, q.text, "self")) {
                return p.failAt(kw, "only a method can have '@self': declare a method, not a {s} (D-123)", .{kw.text});
            }
        }
    }
    const has_results = p.isSym("=>");
    const results = if (p.acceptSym("=>")) try p.params() else empty;
    if (tag == .procedure and has_results) return p.failAt(kw, "a procedure has no result list (use function)", .{});
    if (tag == .function and !has_results) return p.failAt(kw, "a function must have a result list '=> (@r: Type)' (use procedure)", .{});
    if (tag == .generator and results.kids.len != 1) return p.failAt(kw, "a generator has exactly one result: '=> (@x: Type)', the value it produces", .{});
    if (tag == .procedure and name.text[name.text.len - 1] == '!') return p.failAt(name, "a procedure can't end with '!' (D-101)", .{});
    if (partial and p.acceptSym(";")) {
        // a required method: no body; the class that adopts it writes it (D-145)
        return p.mk(tag, kw, name.text, &.{ first, types, results, p.noneNode() });
    }
    try p.expectWord("is");
    const body = try p.block();
    // @eve-impl optional `recover` region of a function, procedure or method: kids[4]; a routine without it has four kids
    // @spec spec/semantics/errors.md#recover-in-a-function-procedure-or-method
    // @feature F-STR-11
    // @decision D-192
    // @test test/level2/b55_function_recover, test/level3/c35_method_recover
    if ((tag == .function or tag == .procedure or tag == .method) and p.acceptWord("recover")) {
        const handler = try p.block();
        try p.expectWord("return");
        try p.expectSym(";");
        return p.mk(tag, kw, name.text, &.{ first, types, results, body, handler });
    }
    try p.expectWord("return");
    try p.expectSym(";");
    return p.mk(tag, kw, if (tag == .constructor or tag == .destructor) "" else name.text, &.{ first, types, results, body });
}

// ---- expressions ------------------------------------------------------------------------
