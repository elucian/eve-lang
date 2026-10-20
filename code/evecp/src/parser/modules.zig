//! @eve-module parser.modules
//! @spec spec/syntax/grammar.md
//! @feature F-VM-01
//! @decision D-179
//! @see code/evecp/src/parser.zig:Parser
//! Declarations in a driver, import, export, module, apply, start.
const std = @import("std");
const lexer = @import("../lexer.zig");
const ast = @import("evecm").ast;
const Node = ast.Node;
const Error = lexer.Error;
const Parser = @import("../parser.zig").Parser;
const consts = @import("consts.zig");
const reserved = consts.reserved;

pub fn declarationInDriver(p: *Parser) Error!*const Node {
    if (p.isWord("adopt") and p.isWordAt(2, "for")) return p.adopt();
    if (p.isWord("new") or p.isWord("set")) return p.declaration();
    if (p.isWord("class")) return p.class();
    if (p.isWord("trait")) return p.trait();
    if (p.isWord("async") and (p.isWordAt(1, "function") or p.isWordAt(1, "procedure"))) {
        // `async procedure name is`: a subprogram that runs as a task of a job (D-104, D-143)
        _ = p.advance();
        const r = try p.routine(if (p.isWord("function")) .function else .procedure);
        @constCast(r).is_async = true;
        return r;
    }
    if (p.isWord("external") and (p.isWordAt(1, "function") or p.isWordAt(1, "procedure"))) {
        // @eve-impl `external function|procedure name(...) [=> (...)];` of a module: a signature, the machine has the body
        // @spec spec/semantics/modules.md#members
        // @feature F-LIB-01
        // @decision D-056, D-189
        _ = p.advance();
        p.external_name = true;
        defer p.external_name = false;
        const r = try p.routineOf(if (p.isWord("function")) .function else .procedure, true);
        if (r.kids[3].tag != .none) return p.failAt(p.peek(), "an external {s} has no body: end the signature with ';'", .{@tagName(r.tag)});
        @constCast(r).is_external = true;
        return r;
    }
    if (p.isWord("function")) return p.routine(.function);
    if (p.isSqlFunction()) return p.sqlFunction();
    if (p.isWord("procedure")) return p.routine(.procedure);
    if (p.isWord("method")) return p.routine(.method);
    if (p.isGeneratorDecl()) return p.routine(.generator);
    if (p.isTableDecl()) return p.tableDecl();
    if (p.isWord("process")) return p.process();
    if (p.isWord("from")) return p.importDecl();
    if (p.isWord("export")) return p.exportDecl();
    return p.fail("unexpected '{s}': an aspect or a module holds declarations; a statement goes in a process, a function, a procedure or a method (D-126)", .{Parser.describe(p.peek())});
}

/// `from path use (m, m as x, m(*), *);`: the path is folder names or strings joined by `/` (modules.md).
pub fn importDecl(p: *Parser) Error!*const Node {
    const kw = p.advance();
    var path: std.ArrayList(u8) = .empty;
    while (true) {
        const t = p.peek();
        if (t.kind == .string) {
            _ = p.advance();
            try path.appendSlice(p.a, t.text[1 .. t.text.len - 1]);
        } else try path.appendSlice(p.a, (try p.expectName("a folder name")).text);
        if (!p.acceptSym("/")) break;
        try path.append(p.a, '/');
    }
    try p.expectWord("use");
    try p.expectSym("(");
    var picks: std.ArrayList(*const Node) = .empty;
    while (true) {
        const t = p.peek();
        if (p.acceptSym("*")) {
            try picks.append(p.a, try p.mk(.import_item, t, "*", &.{p.noneNode()}));
        } else {
            const name = try p.expectName("a module name");
            var alias = p.noneNode();
            var members = false;
            if (p.acceptWord("as")) {
                const a = try p.expectName("an alias");
                alias = try p.mk(.name, a, a.text, &.{});
            } else if (p.acceptSym("(")) {
                try p.expectSym("*");
                try p.expectSym(")");
                members = true;
            }
            const entry = try p.mk(.import_item, name, name.text, &.{alias});
            @constCast(entry).public = members;
            try picks.append(p.a, entry);
        }
        if (!p.acceptSym(",")) break;
    }
    try p.expectSym(")");
    try p.expectSym(";");
    return p.mk(.import_decl, kw, path.items, picks.items);
}

/// `export (a, b!);`: the public members of a module (D-085).
pub fn exportDecl(p: *Parser) Error!*const Node {
    const kw = p.advance();
    try p.expectSym("(");
    var names: std.ArrayList(*const Node) = .empty;
    while (true) {
        // a reserved word may be the name of a native member (`write`, `expect`): the export list is not a statement
        const t = p.peek();
        if (t.kind != .ident) return p.fail("expected a member name but found '{s}'", .{Parser.describe(t)});
        const n = p.advance();
        try names.append(p.a, try p.mk(.name, n, n.text, &.{}));
        if (!p.acceptSym(",")) break;
    }
    try p.expectSym(")");
    try p.expectSym(";");
    return p.mk(.export_decl, kw, "", names.items);
}

// @decision D-126
/// `[managed|direct] module name is ... end name;` (modules.md).
pub fn module(p: *Parser) Error!*const Node {
    const kw = p.peek();
    const managed = p.isWord("managed");
    if (managed or p.isWord("direct")) _ = p.advance();
    try p.expectWord("module");
    const name = try p.expectName("a module name");
    try p.expectWord("is");
    var decls: std.ArrayList(*const Node) = .empty;
    while (!p.isWord("end") and !p.isWord("initialize") and !p.isWord("recover") and !p.isWord("finalize")) {
        if (p.isWord("process")) return p.fail("a module has no process: it holds declarations and regions (D-126)", .{});
        try decls.append(p.a, try p.declarationInDriver());
    }
    const words = [_][]const u8{ "initialize", "recover", "finalize" };
    for (words) |w| {
        if (p.isWord(w)) {
            const rk = p.advance();
            try decls.append(p.a, try p.mk(.region, rk, w, &.{try p.block()}));
        }
    }
    if (!p.isWord("end")) return p.fail("unexpected '{s}' in the module: the regions are initialize, recover and finalize, in this order", .{Parser.describe(p.peek())});
    try p.expectWord("end");
    const end_name = try p.expectName("the module name");
    if (!std.mem.eql(u8, name.text, end_name.text)) {
        p.i -= 1;
        return p.fail("'end {s}' does not match 'module {s}'", .{ end_name.text, name.text });
    }
    try p.expectSym(";");
    const node = try p.mk(.module, kw, name.text, decls.items);
    @constCast(node).public = managed;
    return node;
}

/// `apply path(args);`: run an aspect. The parentheses are always written (processing.html).
pub fn applyStatement(p: *Parser) Error!*const Node {
    const kw = p.advance();
    var path: std.ArrayList(u8) = .empty;
    try path.appendSlice(p.a, (try p.expectName("an aspect name")).text);
    if (p.isSym(".")) return p.fail("the dot is never applied to an aspect: write 'apply {s}(...)', main is its only entry point (D-179)", .{path.items});
    while (p.acceptSym("/")) {
        try path.append(p.a, '/');
        try path.appendSlice(p.a, (try p.expectName("a name after '/'")).text);
    }
    // `apply largest(:String)(rows)`: the types of a generic process, written before the arguments (D-148)
    var types: std.ArrayList(*const Node) = .empty;
    if (p.isSym("(") and p.isSymAt(1, ":")) {
        _ = p.advance();
        while (true) {
            try p.expectSym(":");
            try types.append(p.a, try p.typeName());
            if (!p.acceptSym(",")) break;
        }
        try p.expectSym(")");
    }
    if (!p.isSym("(")) return p.fail("expected '(' after 'apply {s}': the parentheses are always written", .{path.items});
    var args: std.ArrayList(*const Node) = .empty;
    try p.items(")", &args);
    const node = try p.mk(.apply_stmt, kw, path.items, args.items);
    @constCast(node).extra = types.items;
    return p.endSimple(node);
}

// @decision D-140
/// `start path(args);`: start a concurrent aspect in a parallel group.
pub fn startStatement(p: *Parser) Error!*const Node {
    if (p.group_depth == 0) return p.fail("start is allowed only in the do region of a parallel group (D-140)", .{});
    const n = try p.applyStatement();
    @constCast(n).tag = .start_stmt;
    return n;
}
