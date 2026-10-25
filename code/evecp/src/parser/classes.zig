//! @eve-module parser.classes
//! @spec spec/syntax/grammar.md
//! @feature F-VM-01
//! @decision D-179
//! @see code/evecp/src/parser.zig:Parser
//! Classes, traits and adopt.
const std = @import("std");
const lexer = @import("../lexer.zig");
const ast = @import("evecm").ast;
const Token = lexer.Token;
const Node = ast.Node;
const Error = lexer.Error;
const Parser = @import("../parser.zig").Parser;

/// `class Name = (params) [: Type] <: Function;` (callbacks.html).
pub fn functionType(p: *Parser, kw: Token, name: []const u8) Error!*const Node {
    _ = try p.params();
    if (p.acceptSym(":")) _ = try p.typeName();
    try p.expectSym("<:");
    const parent = try p.expectName("a parent class name");
    try p.expectSym(";");
    return p.mk(.class, kw, name, &.{ try p.mk(.block, kw, "", &.{}), try p.mk(.name, parent, parent.text, &.{}) });
}

pub fn class(p: *Parser) Error!*const Node {
    const kw = p.peek();
    try p.expectWord("class");
    const name = try p.expectName("a class name");
    const type_params = try p.typeList();
    // `class Name = {members} <: Parent` or, with no attribute of its own, `class Name <: Parent` (D-132)
    const shaped = p.acceptSym("=");
    if (!shaped and !p.isSym("<:")) return p.fail("expected '=' or '<:' after the class name", .{});
    if (shaped and p.isSym("(")) return p.functionType(kw, name.text);
    if (shaped) try p.expectSym("{");
    var members: std.ArrayList(*const Node) = .empty;
    if (shaped and !p.isSym("}")) {
        while (true) {
            const m = try p.expectName("a member name");
            var value: *const Node = p.noneNode();
            var ty: ?*const Node = null;
            if (p.acceptSym(":")) {
                if (p.peek().kind == .number) value = try p.primary() else ty = try p.typeName();
            }
            const mem = try p.mk(.member, m, m.text, &.{value});
            mem.ty = ty;
            try members.append(p.a, mem);
            if (!p.acceptSym(",")) break;
        }
    }
    if (shaped) try p.expectSym("}");
    var kids: std.ArrayList(*const Node) = .empty;
    try kids.append(p.a, try p.mk(.block, kw, "", members.items));
    var traits: std.ArrayList(*const Node) = .empty;
    if (p.acceptSym("<:")) {
        // `<: Parent` or `<: (Parent, Trait1, Trait2)`: one class first, then the traits (D-145)
        const listed = p.acceptSym("(");
        const parent = try p.expectName("a parent class name");
        const pn = try p.mk(.name, parent, parent.text, &.{});
        if (p.isSym("(") and p.isSymAt(1, ":")) { // a class with a type argument: `Atomic(:Integer)`
            _ = p.advance();
            try p.expectSym(":");
            @constCast(pn).ty = try p.typeName();
            try p.expectSym(")");
        }
        try kids.append(p.a, pn);
        if (listed) {
            while (p.acceptSym(",")) {
                const tr = try p.expectName("a trait name");
                try traits.append(p.a, try p.mk(.name, tr, tr.text, &.{}));
            }
            try p.expectSym(")");
        }
    } else try kids.append(p.a, p.noneNode());
    if (p.acceptSym(";")) {
        const bare = try p.mk(.class, kw, name.text, kids.items);
        bare.extra = traits.items;
        if (type_params.kids.len > 0) @constCast(bare).ty = type_params;
        return bare;
    }
    try p.expectWord("is");
    while (!p.isWord("end")) {
        const public = p.acceptWord("public");
        if (!public and (p.isWord("private") or p.isWord("protected"))) _ = p.advance();
        const first_member = kids.items.len;
        if (p.isWord("procedure") or p.isWord("function")) {
            return p.fail("a class hosts only methods: declare the {s} outside the class (D-123)", .{p.peek().text});
        } else if (p.isWord("constructor")) {
            try kids.append(p.a, try p.routine(.constructor));
        } else if (p.isWord("set")) {
            // @eve-impl a constant of the class, `set NAME = value :Type;`, read as `Class.NAME` (CLS-17b, D-202)
            // @spec spec/syntax/declarations.md#classes-and-objects
            // @test c42_class_constant
            try kids.append(p.a, try p.declaration());
        } else if (p.isWord("destructor")) {
            // @eve-impl the destructor of a class, run when the object is freed (CLS-14, D-202)
            // @spec spec/syntax/declarations.md#classes-and-objects
            // @test c41_destructor
            try kids.append(p.a, try p.routine(.destructor));
        } else if (p.isWord("method")) {
            try kids.append(p.a, try p.routineOf(.method, true));
        } else if (p.isGeneratorDecl()) {
            try kids.append(p.a, try p.routine(.generator));
        } else return p.fail("unexpected '{s}' in the class, expected a constructor or a method", .{Parser.describe(p.peek())});
        if (public) @constCast(kids.items[first_member]).public = true;
    }
    try p.expectWord("end");
    const end_name = try p.expectName("the class name");
    if (!std.mem.eql(u8, name.text, end_name.text)) {
        p.i -= 1;
        return p.fail("'end {s}' does not match 'class {s}'", .{ end_name.text, name.text });
    }
    try p.expectSym(";");
    const node = try p.mk(.class, kw, name.text, kids.items);
    node.extra = traits.items;
    // the type parameters of a generic class, with their constraints (`class Sorted(:T <: Comparable)`), for the checker (D-148)
    if (type_params.kids.len > 0) @constCast(node).ty = type_params;
    return node;
}

// @decision D-145
/// `(:T)` or `(:T <: Comparable, :U)` after the name of a generic class or trait.
pub fn typeParams(p: *Parser) Error!void {
    _ = try p.typeList();
}

// @decision D-148
/// The list of types of a generic subprogram or class; an empty `params` node when there is none.
pub fn typeList(p: *Parser) Error!*const Node {
    const open = p.peek();
    var list: std.ArrayList(*const Node) = .empty;
    if (!(p.isSym("(") and p.isSymAt(1, ":"))) return p.mk(.params, open, "", &.{});
    _ = p.advance();
    while (true) {
        try p.expectSym(":");
        const name = try p.expectName("a type parameter");
        const prm = try p.mk(.param, name, name.text, &.{p.noneNode()});
        if (p.acceptSym("<:")) @constCast(prm).ty = try p.typeName();
        try list.append(p.a, prm);
        if (!p.acceptSym(",")) break;
    }
    try p.expectSym(")");
    return p.mk(.params, open, "", list.items);
}

/// `trait Name is method ...; method ... is ... return; end Name;` (D-145).
pub fn trait(p: *Parser) Error!*const Node {
    const kw = p.advance();
    const name = try p.expectName("a trait name");
    try p.typeParams();
    try p.expectWord("is");
    var kids: std.ArrayList(*const Node) = .empty;
    try kids.append(p.a, try p.mk(.block, kw, "", &.{}));
    try kids.append(p.a, p.noneNode());
    while (!p.isWord("end")) {
        if (!p.isWord("method")) return p.fail("a trait holds only methods, found '{s}'", .{Parser.describe(p.peek())});
        const m = try p.routineOf(.method, true);
        @constCast(m).public = true;
        try kids.append(p.a, m);
    }
    try p.expectWord("end");
    const end_name = try p.expectName("the trait name");
    if (!std.mem.eql(u8, name.text, end_name.text)) {
        p.i -= 1;
        return p.fail("'end {s}' does not match 'trait {s}'", .{ end_name.text, name.text });
    }
    try p.expectSym(";");
    return p.mk(.trait, kw, name.text, kids.items);
}

// @eve-impl `adopt Trait for Type is method ... end adopt;`: a type adopts a trait outside its declaration (CLS-15, D-202)
// @spec spec/syntax/declarations.md#traits-and-generic-classes
// @test d42_adopt_trait
pub fn adopt(p: *Parser) Error!*const Node {
    const kw = p.advance();
    const trait_name = try p.expectName("a trait name");
    try p.expectWord("for");
    const ty = try p.typeName();
    try p.expectWord("is");
    var kids: std.ArrayList(*const Node) = .empty;
    try kids.append(p.a, ty);
    while (!p.isWord("end")) {
        if (!p.isWord("method")) return p.fail("an adopt block holds only methods, found '{s}'", .{Parser.describe(p.peek())});
        const m = try p.routineOf(.method, false);
        // the methods are extension methods: `@self` has the type that adopts the trait
        const first = m.kids[0].kids;
        if (first.len > 0 and first[0].ty == null) @constCast(first[0]).ty = ty;
        @constCast(m).public = true;
        try kids.append(p.a, m);
    }
    try p.expectWord("end");
    const end_name = try p.expectName("adopt");
    if (!std.mem.eql(u8, end_name.text, "adopt")) {
        p.i -= 1;
        return p.fail("'end {s}' does not match 'adopt'", .{end_name.text});
    }
    try p.expectSym(";");
    return p.mk(.adopt, kw, trait_name.text, kids.items);
}
