//! @eve-module parser.statements
//! @spec spec/syntax/grammar.md
//! @feature F-VM-01
//! @decision D-179
//! @see code/evecp/src/parser.zig:Parser
//! Blocks, declarations, loops, if, match, SQL declarations and every statement.
const std = @import("std");
const lexer = @import("../lexer.zig");
const ast = @import("evecm").ast;
const Token = lexer.Token;
const Node = ast.Node;
const Tag = ast.Tag;
const Error = lexer.Error;
const Parser = @import("../parser.zig").Parser;
const consts = @import("consts.zig");
const reserved = consts.reserved;
const block_end = consts.block_end;

/// Statements up to a word that ends the block (`return`, `done`, `else`, ...).
pub fn block(p: *Parser) Error!*const Node {
    const open = p.peek();
    var list: std.ArrayList(*const Node) = .empty;
    while (true) {
        const t = p.peek();
        if (t.kind == .eof) return p.fail("unexpected end of file, the block is not closed", .{});
        if (t.kind == .ident and block_end.has(t.text)) break;
        try list.append(p.a, try p.statement());
    }
    return p.mk(.block, open, "", list.items);
}

/// `[ if condition ] ;` ends every simple statement; the condition wraps the statement.
pub fn endSimple(p: *Parser, stmt: *const Node) Error!*const Node {
    if (p.isWord("if")) {
        const t = p.advance();
        const c = try p.expr();
        try p.expectSym(";");
        return p.mk(.cond_stmt, t, "", &.{ c, stmt });
    }
    try p.expectSym(";");
    return stmt;
}

pub fn assignOp(p: *const Parser) ?[]const u8 {
    const ops = [_][]const u8{ ":=", "::", "+=", "-=", "*=", "/=", "%=", "^=" };
    for (ops) |op| {
        if (p.isSym(op)) return op;
    }
    return null;
}

/// `new a, b := value :Type;`, `new x = y = 1 :Integer;`, `new a :Type;`, `new p, *rest :: n;`,
/// `new e <- list;` and the constants `set A = 1;` (D-076).
pub fn declaration(p: *Parser) Error!*const Node {
    const kw = p.advance(); // new or set
    const tag: Tag = if (std.mem.eql(u8, kw.text, "new")) .var_decl else .set;
    var targets: std.ArrayList(*const Node) = .empty;
    // `new (u, v, w) = 7;`: one value for several names
    if (p.isSym("(")) {
        _ = p.advance();
        while (true) {
            const name = try p.expectName("a variable name");
            try targets.append(p.a, try p.mk(.name, name, name.text, &.{}));
            if (!p.acceptSym(",")) break;
        }
        try p.expectSym(")");
        const op = if (p.acceptSym("=")) "=" else if (p.acceptSym(":=")) ":=" else return p.fail("expected '=' or ':=' but found '{s}'", .{Parser.describe(p.peek())});
        const value = try p.expr();
        const decl = try p.mk(tag, kw, "=", &.{ try p.mk(.targets, kw, "", targets.items), value });
        _ = op;
        if (p.acceptSym(":")) decl.ty = try p.typeName();
        return p.endSimple(decl);
    }
    // a list of items: names to bind (`x = 1, y = 2`) or patterns to deconstruct (`x, y, *rest :: a`)
    var bindings: std.ArrayList(*const Node) = .empty;
    while (true) {
        if (p.isSym("*")) {
            const s = p.advance();
            var nm: []const u8 = "";
            if (p.peek().kind == .ident and !reserved.has(p.peek().text)) nm = p.advance().text;
            try targets.append(p.a, try p.mk(.star, s, nm, &.{}));
        } else {
            const name = try p.expectName("a variable name");
            var t: *const Node = try p.mk(.name, name, name.text, &.{});
            while (p.isSym(".")) {
                const dot = p.advance();
                const attr = try p.expectName("an attribute name");
                t = try p.mk(.field, dot, attr.text, &.{t});
            }
            if (p.isSym("=") or p.isSym(":=")) {
                const op = p.advance();
                const value = try p.expr();
                try bindings.append(p.a, try p.mk(tag, kw, op.text, &.{ try p.mk(.targets, kw, "", &.{t}), value }));
            } else try targets.append(p.a, t);
        }
        if (!p.acceptSym(",")) break;
    }
    if (bindings.items.len == 1 and targets.items.len > 0) {
        // `new q, r := f();` the last name carries the operator: a pattern to deconstruct
        const b = bindings.items[0];
        try targets.append(p.a, b.kids[0].kids[0]);
        const decl = try p.mk(tag, kw, b.text, &.{ try p.mk(.targets, kw, "", targets.items), b.kids[1] });
        if (p.acceptSym(":")) decl.ty = try p.typeName();
        return p.endSimple(decl);
    }
    if (bindings.items.len > 0) {
        if (targets.items.len > 0) return p.fail("a name without a value in a list of bindings: expected '=' or ':='", .{});
        const hint: ?*const Node = if (p.acceptSym(":")) try p.typeName() else null;
        for (bindings.items) |b| @constCast(b).ty = hint;
        try p.expectSym(";");
        if (bindings.items.len == 1) return bindings.items[0];
        return p.mk(.block, kw, "", bindings.items);
    }
    var op: []const u8 = "";
    var value: *const Node = p.noneNode();
    if (p.isSym(":=") or p.isSym("::")) {
        op = p.advance().text;
        value = try p.expr();
    } else if (p.isSym("<-") and targets.items.len == 1) {
        // capture: the new variable takes the first element, the list loses it
        _ = p.advance();
        const list = try p.expr();
        return p.endSimple(try p.mk(.capture, kw, "<-", &.{ list, targets.items[0], p.noneNode() }));
    }
    const decl = try p.mk(tag, kw, op, &.{ try p.mk(.targets, kw, "", targets.items), value });
    if (p.acceptSym(":")) decl.ty = try p.typeName();
    return p.endSimple(decl);
}

// @decision D-107
/// `let target modifier expression;` changes a variable (D-076); `let lst -> e;` and `let e <- lst;`
/// capture an element and create `e` when it does not exist (D-104); `let lst -> new f;` says it.
pub fn letStatement(p: *Parser) Error!*const Node {
    const kw = p.advance();
    const first = try p.postfix();
    if (p.isSym("->")) {
        _ = p.advance();
        const explicit_new = p.isWord("new");
        if (explicit_new) _ = p.advance();
        const target = try p.postfix();
        return p.endSimple(try p.mk(.capture, kw, "->", &.{ first, target, if (explicit_new) p.noneNode() else first }));
    }
    if (p.isSym("<-")) {
        _ = p.advance();
        const list = try p.expr();
        return p.endSimple(try p.mk(.capture, kw, "<-", &.{ list, first, first }));
    }
    const ops = [_][]const u8{ ":=", "::", "+=", "-=", "*=", "/=", "%=", "^=", "<+", "+>", "<<", ">>" };
    for (ops) |op| {
        if (p.isSym(op)) {
            const at = p.advance();
            return p.endSimple(try p.mk(.assign, at, op, &.{ first, try p.expr() }));
        }
    }
    return p.fail("expected an assignment operator after 'let' but found '{s}'", .{Parser.describe(p.peek())});
}

// @decision D-034
/// The common end of `while`, `for`: `block [else block] done [label] ;`. Appends the body, else and
/// then blocks to `kids`; the then block is always empty, the slot stays so the tree keeps its shape.
pub fn loopTail(p: *Parser, kids: *std.ArrayList(*const Node), label: []const u8) Error!void {
    const at = p.peek();
    try kids.append(p.a, try p.block());
    const empty = try p.mk(.block, at, "", &.{});
    try kids.append(p.a, if (p.acceptWord("else")) try p.block() else empty);
    try p.refuseThen();
    try kids.append(p.a, empty);
    try p.expectWord("done");
    try p.closeLabel(label);
}

/// `then` was removed from `match` and the loops: the code goes after `done;`, in the scope of the process or job.
pub fn refuseThen(p: *Parser) Error!void {
    if (p.isWord("then")) return p.fail("'then' no longer exists: write the statements after 'done;'", .{});
}

pub fn closeLabel(p: *Parser, label: []const u8) Error!void {
    if (label.len > 0) {
        const name = try p.expectName("the label");
        if (!std.mem.eql(u8, name.text, label)) {
            p.i -= 1;
            return p.fail("'done {s}' does not match the label '{s}'", .{ name.text, label });
        }
    }
    try p.expectSym(";");
}

// @decision D-074
/// `while condition do ... done [label];`
pub fn whileLoop(p: *Parser, label: []const u8, header: []const *const Node) Error!*const Node {
    const t = p.advance();
    var kids: std.ArrayList(*const Node) = .empty;
    try kids.append(p.a, try p.mk(.block, t, "", header));
    try kids.append(p.a, try p.expr());
    try p.expectWord("do");
    try p.loopTail(&kids, label);
    return p.mk(.while_, t, label, kids.items);
}

/// `for pattern in expression do ... done [label];`
pub fn forLoop(p: *Parser, label: []const u8, header: []const *const Node) Error!*const Node {
    const t = p.advance();
    var kids: std.ArrayList(*const Node) = .empty;
    try kids.append(p.a, try p.postfix());
    try p.expectWord("in");
    try kids.append(p.a, try p.expr());
    try p.expectWord("do");
    try p.loopTail(&kids, label);
    const loop = try p.mk(.for_, t, label, kids.items);
    if (header.len == 0) return loop;
    // the declarations of `loop ... for` run first, then the loop
    var all: std.ArrayList(*const Node) = .empty;
    try all.appendSlice(p.a, header);
    try all.append(p.a, loop);
    return p.mk(.block, t, "", all.items);
}

/// `[label:] loop declarations (while c do ... done | for p in e do ... done | do ... repeat [while c];)`.
pub fn loopBlock(p: *Parser, label: []const u8) Error!*const Node {
    const t = p.advance(); // loop
    var header: std.ArrayList(*const Node) = .empty;
    while (!p.isWord("while") and !p.isWord("do") and !p.isWord("for")) {
        if (p.peek().kind == .eof) return p.fail("expected 'while', 'for' or 'do' after the loop header", .{});
        try header.append(p.a, try p.statement());
    }
    if (p.isWord("while")) return p.whileLoop(label, header.items);
    if (p.isWord("for")) return p.forLoop(label, header.items);
    _ = p.advance(); // do
    var kids: std.ArrayList(*const Node) = .empty;
    try kids.append(p.a, try p.mk(.block, t, "", header.items));
    try kids.append(p.a, try p.block());
    if (!p.isWord("repeat")) return p.fail("a 'loop … do' block ends with 'repeat', found '{s}'", .{Parser.describe(p.peek())});
    _ = p.advance();
    if (label.len > 0 and p.peek().kind == .ident and !p.isWord("while")) {
        const name = try p.expectName("the label");
        if (!std.mem.eql(u8, name.text, label)) return p.failAt(name, "'repeat {s}' does not match the label '{s}'", .{ name.text, label });
    }
    if (p.acceptWord("while")) try kids.append(p.a, try p.expr());
    try p.expectSym(";");
    return p.mk(.repeat_, t, label, kids.items);
}

pub fn ifStatement(p: *Parser) Error!*const Node {
    const kw = p.peek();
    try p.expectWord("if");
    var kids: std.ArrayList(*const Node) = .empty;
    try kids.append(p.a, try p.expr());
    try p.expectWord("do");
    try kids.append(p.a, try p.block());
    while (p.acceptWord("else")) {
        if (p.acceptWord("if")) {
            try kids.append(p.a, try p.expr());
            try p.expectWord("do");
            try kids.append(p.a, try p.block());
        } else {
            try kids.append(p.a, try p.block());
            break;
        }
    }
    try p.expectWord("done");
    try p.expectSym(";");
    return p.mk(.if_, kw, "", kids.items);
}

pub fn matchStatement(p: *Parser, label: []const u8) Error!*const Node {
    const kw = p.peek();
    try p.expectWord("match");
    const subject = try p.expr();
    // `one` (the default) stops at the first match, `all` tries every `when`
    const mode: []const u8 = if (p.acceptWord("one")) "one" else if (p.acceptWord("all")) "all" else "one";
    if (!p.isWord("when")) return p.fail("expected 'when' but found '{s}'", .{Parser.describe(p.peek())});
    var whens: std.ArrayList(*const Node) = .empty;
    while (p.isWord("when")) {
        const w = p.advance();
        var pats: std.ArrayList(*const Node) = .empty;
        while (true) {
            try pats.append(p.a, try p.expr());
            if (!p.acceptSym(",")) break;
        }
        try p.expectWord("do");
        try whens.append(p.a, try p.mk(.when, w, "", &.{ try p.mk(.list, w, "", pats.items), try p.block() }));
    }
    try p.refuseThen();
    const then = try p.mk(.block, kw, "", &.{});
    try p.expectWord("done");
    try p.closeLabel(label);
    var kids: std.ArrayList(*const Node) = .empty;
    try kids.append(p.a, subject);
    try kids.append(p.a, then);
    try kids.appendSlice(p.a, whens.items);
    return p.mk(.match_, kw, try std.fmt.allocPrint(p.a, "{s}:{s}", .{ mode, label }), kids.items);
}

// @decision D-116
/// Is the word under the cursor a `yield` statement (and not a variable called yield)?
pub fn isYieldStatement(p: *const Parser) bool {
    const next = p.peekAt(1);
    if (next.kind != .symbol) return true;
    const names_it = [_][]const u8{ ":=", "::", "=", "(", ".", "[", "+=", "-=", "*=", "/=", "%=", "^=", "<+", "+>" };
    for (names_it) |s| if (std.mem.eql(u8, next.text, s)) return false;
    return true;
}

/// `sql function …` as a declaration (`sql` is a keyword only before `function`, D-116, D-166).
pub fn isSqlFunction(p: *const Parser) bool {
    return p.isWord("sql") and p.isWordAt(1, "function");
}

/// `sql function name(params) => (@r: T) is … return;`: a function that SQL can call (database.md, SQL functions).
pub fn sqlFunction(p: *Parser) Error!*const Node {
    const kw = p.advance();
    const r = try p.routine(.function);
    if (r.text[r.text.len - 1] == '!') return p.failAt(kw, "a sql function is deterministic: '{s}' can not end with '!' (D-166)", .{r.text});
    if (r.kids[1].kids.len > 0) return p.failAt(kw, "a sql function is not generic: SQL gives it no type list (D-166)", .{});
    if (r.kids[2].kids.len != 1) return p.failAt(kw, "a sql function has exactly one result (D-166)", .{});
    for (r.kids[0].kids) |q| {
        if (q.tag != .param) return p.failAt(kw, "a sql function takes its arguments by value: '{s}' (D-166)", .{q.text});
        try p.sqlType(kw, q, "parameter");
    }
    try p.sqlType(kw, r.kids[2].kids[0], "result");
    @constCast(r).is_sql = true;
    return r;
}

/// A parameter or the result of a `sql function` has a type that maps to a SQL value (database.md, mapping).
pub fn sqlType(p: *Parser, kw: Token, q: *const Node, what: []const u8) Error!void {
    const ty = q.ty orelse return p.failAt(kw, "the {s} '{s}' of a sql function needs a type (D-166)", .{ what, q.text });
    const base = std.mem.trimEnd(u8, ty.text, "?");
    const sql_types = [_][]const u8{ "Integer", "Natural", "Real", "Float", "Decimal", "String", "Logic", "Instant" };
    for (sql_types) |t| if (std.mem.eql(u8, base, t)) return;
    return p.failAt(kw, "the {s} '{s}' of a sql function has the type {s}, which SQL does not have (D-166)", .{ what, q.text, ty.text });
}

/// `table name: Class …` as a declaration (`table` is a word only at the start of a declaration, D-116).
pub fn isTableDecl(p: *const Parser) bool {
    return p.isWord("table") and p.peekAt(1).kind == .ident and p.isSymAt(2, ":");
}

/// `table name: Class in "connection" [as "name"] ;` or with `is clauses end name;` (database.md, the table declaration).
pub fn tableDecl(p: *Parser) Error!*const Node {
    const kw = p.advance();
    const name = try p.expectName("a table name");
    try p.expectSym(":");
    const class_tok = try p.expectName("a record class");
    try p.expectWord("in");
    const conn = try p.primary();
    if (conn.tag != .str) return p.fail("the connection of a table is a text: in \"sales\"", .{});
    var kids: std.ArrayList(*const Node) = .empty;
    try kids.append(p.a, try p.mk(.name, class_tok, class_tok.text, &.{}));
    try kids.append(p.a, conn);
    if (p.acceptWord("as")) {
        const alias = try p.primary();
        if (alias.tag != .str) return p.fail("the database name of a table is a text: as \"schema.table\"", .{});
        try kids.append(p.a, alias);
    } else try kids.append(p.a, p.noneNode());
    if (p.acceptSym(";")) return p.mk(.table_decl, kw, name.text, kids.items);
    try p.expectWord("is");
    while (!p.isWord("end")) {
        const w = p.peek();
        if (w.kind != .ident) return p.fail("unexpected '{s}' in the table declaration", .{Parser.describe(w)});
        _ = p.advance();
        var args: std.ArrayList(*const Node) = .empty;
        var word = w.text;
        if (std.mem.eql(u8, w.text, "key") or std.mem.eql(u8, w.text, "generated")) {
            try p.expectSym("(");
            while (true) {
                const f = try p.expectName("a field name");
                try args.append(p.a, try p.mk(.name, f, f.text, &.{}));
                if (!p.acceptSym(",")) break;
            }
            try p.expectSym(")");
        } else if (std.mem.eql(u8, w.text, "version")) {
            const f = try p.expectName("a field name");
            try args.append(p.a, try p.mk(.name, f, f.text, &.{}));
        } else if (std.mem.eql(u8, w.text, "column")) {
            const f = try p.expectName("a field name");
            try args.append(p.a, try p.mk(.name, f, f.text, &.{}));
            try p.expectWord("as");
            const col = try p.primary();
            if (col.tag != .str) return p.fail("the name of a column is a text: column city as \"town\"", .{});
            try args.append(p.a, col);
        } else if (std.mem.eql(u8, w.text, "reference")) {
            const f = try p.expectName("a field name");
            try args.append(p.a, try p.mk(.name, f, f.text, &.{}));
            try p.expectWord("to");
            const t = try p.expectName("a table name");
            try args.append(p.a, try p.mk(.name, t, t.text, &.{}));
        } else if (std.mem.eql(u8, w.text, "read")) {
            try p.expectWord("only");
            word = "read only";
        } else if (std.mem.eql(u8, w.text, "temporary")) {
            // no arguments
        } else if (std.mem.eql(u8, w.text, "cached")) {
            try args.append(p.a, try p.expr());
        } else return p.failAt(w, "unknown clause '{s}' in the table declaration: key, generated, version, column, reference, read only, temporary, cached", .{w.text});
        try p.expectSym(";");
        try kids.append(p.a, try p.mk(.clause, w, word, args.items));
    }
    try p.expectWord("end");
    const end_name = try p.expectName("the table name");
    if (!std.mem.eql(u8, name.text, end_name.text)) {
        p.i -= 1;
        return p.fail("'end {s}' does not match 'table {s}'", .{ end_name.text, name.text });
    }
    try p.expectSym(";");
    return p.mk(.table_decl, kw, name.text, kids.items);
}

/// `generator name …` as a declaration (`generator` is a word only before a name, D-116).
pub fn isGeneratorDecl(p: *const Parser) bool {
    return p.isWord("generator") and p.peekAt(1).kind == .ident;
}

pub fn statement(p: *Parser) Error!*const Node {
    const t = p.peek();
    if (t.kind == .ident) {
        const w = t.text;
        if (std.mem.eql(u8, w, "new") or std.mem.eql(u8, w, "set")) return p.declaration();
        if (std.mem.eql(u8, w, "let")) return p.letStatement();
        if (std.mem.eql(u8, w, "defer")) {
            _ = p.advance();
            return p.mk(.defer_stmt, t, "", &.{try p.statement()});
        }
        if (std.mem.eql(u8, w, "apply")) return p.applyStatement();
        if (std.mem.eql(u8, w, "start")) return p.startStatement();
        if (std.mem.eql(u8, w, "parallel")) return p.parallelBlock(t, "");
        if (std.mem.eql(u8, w, "spawn")) {
            _ = p.advance();
            if (p.job_depth == 0) return p.failAt(t, "spawn is allowed only in the do region of a job (D-143)", .{});
            const c = try p.postfix();
            if (c.tag != .call) return p.failAt(t, "spawn is followed by a call: spawn name(arguments)", .{});
            return p.endSimple(try p.mk(.spawn_stmt, t, "", &.{c}));
        }
        if (std.mem.eql(u8, w, "await")) {
            // `await load(p, @t);`: an awaited procedure is a statement (D-143)
            return p.endSimple(try p.mk(.expr_stmt, t, "", &.{try p.expr()}));
        }
        if (std.mem.eql(u8, w, "wait")) {
            _ = p.advance();
            return p.endSimple(try p.mk(.wait_stmt, t, "", &.{try p.expr()}));
        }
        // a function declared inside a function or a procedure is a closure (D-101)
        if (std.mem.eql(u8, w, "function")) return p.routine(.function);
        if ((std.mem.eql(u8, w, "commit") or std.mem.eql(u8, w, "rollback")) and (p.isSymAt(1, ";") or p.isWordAt(1, "if"))) {
            _ = p.advance();
            if (p.job_depth == 0) return p.failAt(t, "{s} is allowed only in a job: write it in the do region of a job (D-158)", .{w});
            return p.endSimple(try p.mk(if (std.mem.eql(u8, w, "commit")) .commit_stmt else .rollback_stmt, t, "", &.{}));
        }
        if (std.mem.eql(u8, w, "update") and p.peekAt(1).kind == .ident and !reserved.has(p.peekAt(1).text) and p.isWordAt(2, "do")) {
            _ = p.advance();
            const target = try p.postfix();
            try p.expectWord("do");
            const body = try p.block();
            try p.expectWord("done");
            try p.expectSym(";");
            return p.mk(.update_stmt, t, "", &.{ target, body });
        }
        if (std.mem.eql(u8, w, "yield") and p.isYieldStatement()) {
            _ = p.advance();
            if (!p.in_generator) return p.failAt(t, "yield outside a generator: only the body of a generator can yield (D-067)", .{});
            const value: []const *const Node = if (p.isSym(";") or p.isWord("if")) &.{} else &.{try p.expr()};
            return p.endSimple(try p.mk(.yield_stmt, t, "", value));
        }
        if (std.mem.eql(u8, w, "if")) return p.ifStatement();
        if (std.mem.eql(u8, w, "match")) return p.matchStatement("");
        if (std.mem.eql(u8, w, "while")) return p.whileLoop("", &.{});
        if (std.mem.eql(u8, w, "loop")) return p.loopBlock("");
        if (std.mem.eql(u8, w, "for")) return p.forLoop("", &.{});
        if (!reserved.has(w) and p.isSymAt(1, ":") and (p.isWordAt(2, "loop") or p.isWordAt(2, "match") or p.isWordAt(2, "while") or p.isWordAt(2, "for"))) {
            _ = p.advance();
            _ = p.advance();
            if (p.isWord("loop")) return p.loopBlock(w);
            if (p.isWord("match")) return p.matchStatement(w);
            if (p.isWord("while")) return p.whileLoop(w, &.{});
            return p.forLoop(w, &.{});
        }
        if (!reserved.has(w) and p.isSymAt(1, ":") and p.isWordAt(2, "parallel")) {
            _ = p.advance();
            _ = p.advance();
            return p.parallelBlock(t, w);
        }
        if (!reserved.has(w) and p.isSymAt(1, ":") and p.isWordAt(2, "job")) {
            _ = p.advance();
            _ = p.advance();
            _ = p.advance();
            // the declarations of a job come before `do` and run again at every retry: they are the first
            // statements of the body (database.md#transactions, long loads)
            var decls: std.ArrayList(*const Node) = .empty;
            while (!p.isWord("do")) {
                if (p.peek().kind == .eof) return p.fail("expected 'do' in the job", .{});
                try decls.append(p.a, try p.declaration());
            }
            try p.expectWord("do");
            p.job_depth += 1;
            const parsed = p.block() catch |e| {
                p.job_depth -= 1;
                return e;
            };
            p.job_depth -= 1;
            const body = if (decls.items.len == 0) parsed else blk: {
                try decls.appendSlice(p.a, parsed.kids);
                break :blk try p.mk(.block, t, "", decls.items);
            };
            try p.expectWord("done");
            const label = try p.expectName("the job label");
            if (!std.mem.eql(u8, label.text, w)) {
                p.i -= 1;
                return p.fail("'done {s}' does not match the job '{s}'", .{ label.text, w });
            }
            try p.expectSym(";");
            return p.mk(.job, t, w, &.{body});
        }
        if (std.mem.eql(u8, w, "break") or std.mem.eql(u8, w, "skip")) {
            _ = p.advance();
            var label: []const u8 = "";
            if (p.peek().kind == .ident and !reserved.has(p.peek().text)) label = p.advance().text;
            return p.endSimple(try p.mk(if (std.mem.eql(u8, w, "break")) .break_stmt else .skip_stmt, t, label, &.{}));
        }
        inline for (.{
            .{ "over", Tag.over_stmt },
            .{ "exit", Tag.exit_stmt },
            .{ "stop", Tag.stop_stmt },
            .{ "pass", Tag.pass_stmt },
            .{ "panic", Tag.panic_stmt },
            .{ "retry", Tag.retry_stmt },
            .{ "resume", Tag.resume_stmt },
            .{ "abort", Tag.abort_stmt },
        }) |pair| {
            if (std.mem.eql(u8, w, pair[0])) {
                _ = p.advance();
                // `over 7;` and `exit 7;` give the exit code of the program (statements.md#interruptions)
                if ((pair[1] == Tag.over_stmt or pair[1] == Tag.exit_stmt) and !p.isSym(";") and !p.isWord("if") and !(p.peek().kind == .ident and reserved.has(p.peek().text))) {
                    return p.endSimple(try p.mk(pair[1], t, "", &.{try p.expr()}));
                }
                return p.endSimple(try p.mk(pair[1], t, "", &.{}));
            }
        }
        inline for (.{
            .{ "print", Tag.print_stmt },
            .{ "write", Tag.write_stmt },
            .{ "expect", Tag.expect_stmt },
            .{ "assert", Tag.assert_stmt },
            .{ "raise", Tag.raise_stmt },
        }) |pair| {
            if (std.mem.eql(u8, w, pair[0])) {
                _ = p.advance();
                if (!p.isSym(";") and !p.isWord("if")) {
                    // `print a, b;`: the arguments, separated by commas, become one list
                    const first = try p.printArg();
                    // @eve-impl `expect cond else "message";` and `expect cond, "message";` (the same for assert): kids = [cond, message]
                    // @spec spec/semantics/errors.md#expect-and-assert
                    // @test c70_expect_message
                    if ((pair[1] == Tag.expect_stmt or pair[1] == Tag.assert_stmt) and (p.isWord("else") or p.isSym(","))) {
                        _ = p.advance();
                        const message = try p.expr();
                        return p.endSimple(try p.mk(pair[1], t, "", &.{ first, message }));
                    }
                    if (!p.isSym(",")) return p.endSimple(try p.mk(pair[1], t, "", &.{first}));
                    var args: std.ArrayList(*const Node) = .empty;
                    try args.append(p.a, first);
                    while (p.acceptSym(",")) try args.append(p.a, try p.printArg());
                    return p.endSimple(try p.mk(pair[1], t, "", &.{try p.mk(.list, t, "", args.items)}));
                }
                return p.endSimple(try p.mk(pair[1], t, "", &.{}));
            }
        }
        if (reserved.has(w)) {
            return p.fail("unexpected '{s}', expected a statement", .{w});
        }
    }
    const e = try p.expr();
    if (p.assignOp() != null or p.isSym("=")) {
        return p.fail("a change of a variable is written with 'let': let x {s} ...", .{p.peek().text});
    }
    if (e.tag == .bin and (std.mem.eql(u8, e.text, "<+") or std.mem.eql(u8, e.text, "+>") or std.mem.eql(u8, e.text, "<-") or std.mem.eql(u8, e.text, "->"))) {
        return p.failAt(t, "a list modifier is a statement with 'let': let a {s} b;", .{e.text});
    }
    return p.endSimple(try p.mk(.expr_stmt, t, "", &.{e}));
}

// ---- declarations -----------------------------------------------------------------------

pub fn process(p: *Parser) Error!*const Node {
    const kw = p.peek();
    try p.expectWord("process");
    const name = try p.expectName("a process name");
    const types = try p.typeList();
    const prm = if (p.isSym("(")) try p.params() else try p.mk(.params, kw, "", &.{});
    try p.expectWord("is");
    p.in_process = true;
    defer p.in_process = false;
    const body = try p.block();
    const recover = if (p.acceptWord("recover")) try p.block() else p.noneNode();
    const finalize = if (p.acceptWord("finalize")) try p.block() else p.noneNode();
    try p.expectWord("return");
    try p.expectSym(";");
    return p.mk(.process, kw, name.text, &.{ body, recover, finalize, prm, types });
}
