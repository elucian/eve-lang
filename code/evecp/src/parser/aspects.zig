//! @eve-module parser.aspects
//! @spec spec/syntax/grammar.md
//! @feature F-VM-01
//! @decision D-179
//! @see code/evecp/src/parser.zig:Parser
//! Parallel blocks, aspects, macros and the script entry.
const std = @import("std");
const lexer = @import("../lexer.zig");
const ast = @import("evecm").ast;
const Token = lexer.Token;
const Node = ast.Node;
const Error = lexer.Error;
const Parser = @import("../parser.zig").Parser;

/// `[label:] parallel [on error cancel] [within d] declarations do statements done [label];` (D-140).
pub fn parallelBlock(p: *Parser, at: Token, label: []const u8) Error!*const Node {
    if (!p.in_process) return p.fail("parallel is allowed only in a process (D-140)", .{});
    if (p.group_depth > 0) return p.fail("parallel groups are not nested in one process (D-140)", .{});
    try p.expectWord("parallel");
    var cancel = false;
    if (p.acceptWord("on")) {
        try p.expectWord("error");
        try p.expectWord("cancel");
        cancel = true;
    }
    const deadline = if (p.acceptWord("within")) try p.expr() else p.noneNode();
    var decls: std.ArrayList(*const Node) = .empty;
    while (!p.isWord("do")) {
        if (p.peek().kind == .eof) return p.fail("expected 'do' in the parallel group", .{});
        try decls.append(p.a, try p.declaration());
    }
    const dk = p.advance();
    p.group_depth += 1;
    const body = p.block() catch |e| {
        p.group_depth -= 1;
        return e;
    };
    p.group_depth -= 1;
    try p.expectWord("done");
    if (label.len > 0) {
        const end = try p.expectName("the label of the group");
        if (!std.mem.eql(u8, end.text, label)) {
            p.i -= 1;
            return p.fail("'done {s}' does not match the group '{s}'", .{ end.text, label });
        }
    }
    try p.expectSym(";");
    const node = try p.mk(.parallel, at, label, &.{ try p.mk(.block, at, "", decls.items), try p.mk(.block, dk, "", body.kids), deadline });
    node.public = cancel;
    return node;
}

// @decision D-181
// @decision D-130
/// Is the cursor on the start of an aspect: a kind word or `aspect`?
pub fn isAspectStart(p: *Parser) bool {
    return p.isWord("exclusive") or p.isWord("concurrent") or p.isWord("primary") or p.isWord("aspect");
}

/// `[exclusive|concurrent|primary] aspect name is … end name;`: a process `main`, the entry point, and perhaps
/// private processes (D-179). Without a kind word the aspect is exclusive (D-130).
pub fn aspect(p: *Parser) Error!*const Node {
    const kw = p.peek();
    const kind: []const u8 = if (p.isWord("exclusive") or p.isWord("concurrent") or p.isWord("primary")) p.advance().text else "exclusive";
    if (!p.isWord("aspect")) return p.fail("expected 'aspect' after '{s}'", .{kind});
    _ = p.advance();
    const name = try p.expectName("an aspect name");
    try p.expectWord("is");
    var decls: std.ArrayList(*const Node) = .empty;
    while (!p.isWord("end")) try decls.append(p.a, try p.declarationInDriver());
    try p.expectWord("end");
    const end_name = try p.expectName("the aspect name");
    if (!std.mem.eql(u8, name.text, end_name.text)) {
        p.i -= 1;
        return p.fail("'end {s}' does not match 'aspect {s}'", .{ end_name.text, name.text });
    }
    var has_main = false;
    for (decls.items, 0..) |d, i| if (d.tag == .process) {
        if (std.mem.eql(u8, d.text, "main")) has_main = true;
        for (decls.items[i + 1 ..]) |e| if (e.tag == .process and std.mem.eql(u8, e.text, d.text)) {
            p.diag.set(e.line, e.col, "the process '{s}' is declared twice", .{e.text});
            return error.Syntax;
        };
    };
    if (!has_main) {
        p.diag.set(name.line, name.col, "{s} has no process main: the entry point of an aspect (D-179)", .{name.text});
        return error.Syntax;
    }
    try p.expectSym(";");
    const node = try p.mk(.aspect, kw, name.text, decls.items);
    @constCast(node).public = std.mem.eql(u8, kind, "concurrent"); // the kind word, for the thread safety check (D-129)
    @constCast(node).primary = std.mem.eql(u8, kind, "primary");
    return node;
}

// @decision D-152
/// Does the file hold a top-level aspect after other declarations?
pub fn looksLikeMacro(p: *Parser) bool {
    for (p.toks[p.i..]) |t| {
        if (t.kind != .ident or t.col != 1) continue;
        if (std.mem.eql(u8, t.text, "aspect") or std.mem.eql(u8, t.text, "exclusive") or
            std.mem.eql(u8, t.text, "concurrent") or std.mem.eql(u8, t.text, "primary")) return true;
    }
    return false;
}

/// An Eve macro (D-152): shared declarations and aspects in one file, exactly one of them primary (D-180).
pub fn macro(p: *Parser, first: ?*const Node) Error!*const Node {
    var shared: std.ArrayList(*const Node) = .empty;
    var aspects: std.ArrayList(*const Node) = .empty;
    var prim: ?*const Node = null;
    if (first) |f| {
        if (f.primary) prim = f else try aspects.append(p.a, f);
    }
    while (p.peek().kind != .eof) {
        if (p.isAspectStart()) {
            const a = try p.aspect();
            if (a.primary) {
                if (prim != null) return p.fail("a macro has only one primary aspect (D-180)", .{});
                prim = a;
            } else try aspects.append(p.a, a);
        } else if (p.isWord("export")) {
            return p.fail("a macro exports nothing: export is not allowed in a macro (D-126, D-152)", .{});
        } else if (p.isWord("module") or p.isWord("managed") or p.isWord("direct")) {
            return p.fail("a module is its own file: it is not declared inside a macro (D-152)", .{});
        } else if (p.isWord("new") or p.isWord("set") or p.isWord("class") or p.isWord("trait") or (p.isWord("adopt") and p.isWordAt(2, "for")) or p.isWord("async") or
            p.isWord("function") or p.isWord("procedure") or p.isWord("method") or p.isWord("from") or p.isGeneratorDecl() or p.isTableDecl() or
            p.isSqlFunction())
        {
            try shared.append(p.a, try p.declarationInDriver());
        } else {
            return p.fail("a statement outside a declaration in a macro: '{s}' goes in a process (D-152)", .{Parser.describe(p.peek())});
        }
    }
    const d = prim orelse return p.fail("a macro needs a primary aspect: write 'primary aspect name is … end name;' (D-180)", .{});
    var kids: std.ArrayList(*const Node) = .empty;
    try kids.appendSlice(p.a, shared.items);
    try kids.appendSlice(p.a, d.kids);
    for (aspects.items) |a| {
        @constCast(a).macro = true;
        try kids.append(p.a, a);
    }
    const node = try p.a.create(Node);
    node.* = .{ .tag = .aspect, .line = d.line, .col = d.col, .text = d.text, .kids = kids.items, .macro = true, .primary = true };
    return node;
}

// @decision D-179
pub fn script(p: *Parser) Error!*const Node {
    var result: *const Node = undefined;
    if (p.isAspectStart()) {
        result = try p.aspect();
        if (p.peek().kind != .eof) result = try p.macro(result);
    } else if (p.isWord("module") or ((p.isWord("managed") or p.isWord("direct")) and p.isWordAt(1, "module"))) {
        result = try p.module();
    } else if (p.looksLikeMacro()) {
        result = try p.macro(null);
    } else {
        return p.fail("a file holds an aspect or a module: '{s}' cannot start it; a statement goes in a process (D-179)", .{Parser.describe(p.peek())});
    }
    if (p.peek().kind != .eof) return p.fail("unexpected '{s}' after the end of the aspect", .{Parser.describe(p.peek())});
    return result;
}
