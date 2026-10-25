//! @eve-module parser.expr
//! @spec spec/syntax/grammar.md
//! @feature F-VM-01
//! @decision D-179
//! @see code/evecp/src/parser.zig:Parser
//! Expressions, from `or` to a primary.
const std = @import("std");
const lexer = @import("../lexer.zig");
const ast = @import("evecm").ast;
const Token = lexer.Token;
const Node = ast.Node;
const Error = lexer.Error;
const Parser = @import("../parser.zig").Parser;
const consts = @import("consts.zig");
const reserved = consts.reserved;

pub fn expr(p: *Parser) Error!*const Node {
    var l = try p.nullishExpr();
    while (p.isSym("<+") or p.isSym("+>") or p.isSym("<-") or p.isSym("->")) {
        const t = p.advance();
        const r = try p.orExpr();
        l = try p.mk(.bin, t, t.text, &.{ l, r });
    }
    return l;
}

// @eve-impl `x ?? d`: the default of an optional value; it groups to the right and binds looser than `or` (types.md#narrowing-and-the-default)
// @spec spec/semantics/types.md#narrowing-and-the-default
// @feature F-LNG-14
// @test test/level5/e145_optional_default
pub fn nullishExpr(p: *Parser) Error!*const Node {
    const l = try p.orExpr();
    if (!p.isSym("??")) return l;
    const t = p.advance();
    return p.mk(.bin, t, "??", &.{ l, try p.nullishExpr() });
}

pub fn orExpr(p: *Parser) Error!*const Node {
    var l = try p.xorExpr();
    while (p.isWord("or")) {
        const t = p.advance();
        l = try p.mk(.bin, t, "or", &.{ l, try p.xorExpr() });
    }
    return l;
}

pub fn xorExpr(p: *Parser) Error!*const Node {
    var l = try p.andExpr();
    while (p.isWord("xor")) {
        const t = p.advance();
        l = try p.mk(.bin, t, "xor", &.{ l, try p.andExpr() });
    }
    return l;
}

pub fn andExpr(p: *Parser) Error!*const Node {
    var l = try p.notExpr();
    while (p.isWord("and")) {
        const t = p.advance();
        l = try p.mk(.bin, t, "and", &.{ l, try p.notExpr() });
    }
    return l;
}

pub fn notExpr(p: *Parser) Error!*const Node {
    if (p.isWord("not") and !p.isWordAt(1, "in")) {
        const t = p.advance();
        return p.mk(.un, t, "not", &.{try p.notExpr()});
    }
    return p.compare();
}

/// `== <> < > <= >= =~ !~ in, not in, is, is not` (a chain is accepted, left to right).
pub fn compare(p: *Parser) Error!*const Node {
    var l = try p.range();
    while (p.compareOp()) |op| {
        l = try p.mk(.bin, op.tok, op.text, &.{ l, try p.range() });
    }
    return l;
}

pub fn compareOp(p: *Parser) ?struct { tok: Token, text: []const u8 } {
    const ops = [_][]const u8{ "==", "<>", "<=", ">=", "<", ">", "=~" };
    const t = p.peek();
    for (ops) |op| {
        if (p.acceptSym(op)) return .{ .tok = t, .text = op };
    }
    if (p.acceptWord("in")) return .{ .tok = t, .text = "in" };
    if (p.isWord("not") and p.isWordAt(1, "in")) {
        _ = p.advance();
        _ = p.advance();
        return .{ .tok = t, .text = "not in" };
    }
    if (p.acceptWord("is")) {
        if (p.acceptWord("not")) return .{ .tok = t, .text = "is not" };
        return .{ .tok = t, .text = "is" };
    }
    return null;
}

/// `a..b  a..<b  a>..b  a>..<b`
pub fn range(p: *Parser) Error!*const Node {
    const l = try p.additive();
    const ops = [_][]const u8{ "..", "..<", ">..", ">..<", "+-" };
    const t = p.peek();
    for (ops) |op| {
        if (p.acceptSym(op)) return p.mk(.range, t, op, &.{ l, try p.additive() });
    }
    return l;
}

pub fn additive(p: *Parser) Error!*const Node {
    var l = try p.multiplicative();
    while (p.isSym("+") or p.isSym("-") or p.isSym("||")) {
        const t = p.advance();
        l = try p.mk(.bin, t, t.text, &.{ l, try p.multiplicative() });
    }
    return l;
}

pub fn multiplicative(p: *Parser) Error!*const Node {
    var l = try p.power();
    while (p.isSym("*") or p.isSym("/") or p.isSym("%") or p.isSym("&&") or p.isSym("><") or
        p.isSym("<<") or p.isSym(">>"))
    {
        const t = p.advance();
        l = try p.mk(.bin, t, t.text, &.{ l, try p.power() });
    }
    return l;
}

// @spec spec/syntax/grammar.md
pub fn unary(p: *Parser) Error!*const Node {
    if (p.isWord("await")) {
        // `await f(x)` starts an async subprogram and waits for it at once (D-143)
        const t = p.advance();
        const c = try p.postfix();
        if (c.tag != .call) return p.failAt(t, "await is followed by a call: await name(arguments)", .{});
        return p.mk(.await_, t, "", &.{c});
    }
    if (p.isSym("-") or p.isSym("+")) {
        const t = p.advance();
        return p.mk(.un, t, t.text, &.{try p.unary()});
    }
    return p.postfix();
}

/// `^` goes right to left: `2 ^ 3 ^ 2` is `2 ^ (3 ^ 2)`.
pub fn power(p: *Parser) Error!*const Node {
    const l = try p.unary();
    if (p.isSym("^")) {
        const t = p.advance();
        return p.mk(.bin, t, "^", &.{ l, try p.power() });
    }
    return l;
}

pub fn postfix(p: *Parser) Error!*const Node {
    const first = p.peek();
    var n = try p.primary();
    var callable = first.kind == .ident or (first.kind == .symbol and first.text[0] == '(');
    while (true) {
        if (p.isSym(".")) {
            const dot = p.advance();
            // an attribute may be named like a keyword: `$error.job`
            if (p.peek().kind != .ident) return p.fail("expected an attribute name but found '{s}'", .{Parser.describe(p.peek())});
            const name = p.advance();
            n = try p.mk(.field, dot, name.text, &.{n});
            callable = true;
        } else if (p.isSym("[")) {
            const open = p.advance();
            n = try p.mk(.index, open, "", try p.indexList(n));
            callable = true;
        } else if (callable and p.isSym("(") and p.isSymAt(1, ":")) {
            // `Channel(:Integer)`, `Box(:String)`: the type arguments of a generic class (D-145)
            const open = p.advance();
            var types: std.ArrayList(*const Node) = .empty;
            while (true) {
                try p.expectSym(":");
                try types.append(p.a, try p.typeName());
                if (!p.acceptSym(",")) break;
            }
            try p.expectSym(")");
            if (n.tag == .field) {
                // `csv.read!(:Row)(path)`: the type arguments of a library function or of a method (D-148)
                // go after the receiver in the kids of the field node; the call that follows is a plain call.
                var kids: std.ArrayList(*const Node) = .empty;
                try kids.append(p.a, n.kids[0]);
                try kids.appendSlice(p.a, types.items);
                n = try p.mk(.field, open, n.text, kids.items);
                continue;
            }
            if (n.tag != .name) return p.failAt(open, "type arguments follow the name of a class", .{});
            n = try p.mk(.generic, open, n.text, types.items);
        } else if (callable and p.isSym("(")) {
            const open = p.peek();
            // `((x) => (x * 2))(5)` is not Eve: a lambda gets a name first, then it is called;
            // a second `(...)` after a name is kept for the type list of a generic (D-147)
            if (n.tag == .lambda) return p.failAt(open, "a lambda can not be called where it is written; assign it to a name, then call the name", .{});
            var kids: std.ArrayList(*const Node) = .empty;
            try kids.append(p.a, n);
            try p.items(")", &kids);
            n = try p.mk(.call, open, "", kids.items);
        } else break;
    }
    return n;
}

/// The inside of `[ ... ]`: expressions, `$` for the last index, `*` for a whole dimension.
/// Returns the kids of the index node: the indexed object first.
pub fn indexList(p: *Parser, obj: *const Node) Error![]const *const Node {
    var kids: std.ArrayList(*const Node) = .empty;
    try kids.append(p.a, obj);
    while (true) {
        if (p.isSym("*") and (p.isSymAt(1, "]") or p.isSymAt(1, ","))) {
            try kids.append(p.a, try p.mk(.all, p.advance(), "", &.{}));
        } else try kids.append(p.a, try p.expr());
        if (!p.acceptSym(",")) break;
    }
    try p.expectSym("]");
    return kids.items;
}

/// One element of a list, call or object: `expr`, `name: expr`, `x if c else y`, `@name`.
pub fn item(p: *Parser) Error!*const Node {
    const k = try p.conditional();
    if (p.isSym(":")) {
        const t = p.advance();
        return p.mk(.pair, t, "", &.{ k, try p.conditional() });
    }
    return k;
}

pub fn conditional(p: *Parser) Error!*const Node {
    if (p.isSym("*") and !p.isSymAt(1, ")") and !p.isSymAt(1, ",")) { // `*list` spreads a list into the arguments
        const star = p.advance();
        return p.mk(.spread, star, "", &.{try p.expr()});
    }
    if (p.isSym("@")) { // `@name` passes a variable by reference, `@s[i]` one element of it
        _ = p.advance();
        const name = try p.expectName("a variable name");
        if (p.isSym("[")) {
            var target: *const Node = try p.mk(.name, name, name.text, &.{});
            while (p.isSym("[")) {
                const open = p.advance();
                target = try p.mk(.index, open, "", try p.indexList(target));
            }
            return p.mk(.ref, name, name.text, &.{target});
        }
        return p.mk(.ref, name, name.text, &.{});
    }
    const x = try p.expr();
    if (p.isWord("if")) {
        const t = p.advance();
        const c = try p.expr();
        try p.expectWord("else");
        return p.mk(.cond, t, "", &.{ x, c, try p.conditional() });
    }
    return x;
}

/// The items after an opening symbol up to `close` (the opening one is consumed here too).
pub fn items(p: *Parser, close: []const u8, out: *std.ArrayList(*const Node)) Error!void {
    _ = p.advance();
    if (!p.isSym(close)) {
        while (true) {
            try out.append(p.a, try p.item());
            if (!p.acceptSym(",")) break;
        }
    }
    try p.expectSym(close);
}

/// A bracketed group: list, array, set, map, object or builder.
pub fn group(p: *Parser, close: []const u8) Error!*const Node {
    const open = p.advance();
    var kids: std.ArrayList(*const Node) = .empty;
    var comma = false;
    if (std.mem.eql(u8, close, "}") and p.isSym(":") and p.isSymAt(1, "}")) {
        _ = p.advance();
        _ = p.advance();
        return p.mk(.brace, open, "map", &.{});
    }
    if (!p.isSym(close)) {
        while (true) {
            try kids.append(p.a, try p.item());
            if (!p.acceptSym(",")) break;
            comma = true;
            if (p.isSym(close)) break;
        }
        if (p.acceptSym("|")) {
            const gen = try p.expr();
            try p.expectSym(close);
            return p.mk(.builder, open, open.text, &.{ kids.items[0], gen });
        }
    }
    try p.expectSym(close);
    if (close[0] == ')') {
        if (kids.items.len == 1 and !comma and kids.items[0].tag != .pair) return kids.items[0];
        return p.mk(.list, open, "", kids.items);
    }
    if (close[0] == ']') return p.mk(.array, open, "", kids.items);
    var kind: []const u8 = "set";
    if (kids.items.len > 0 and kids.items[0].tag == .pair) {
        kind = if (kids.items[0].kids[0].tag == .name) "object" else "map";
    }
    return p.mk(.brace, open, kind, kids.items);
}

/// Is the `(` at the cursor the start of a lambda `(params) => (expression)`?
pub fn isLambda(p: *const Parser) bool {
    var depth: usize = 0;
    var j = p.i;
    while (j < p.toks.len) : (j += 1) {
        const t = p.toks[j];
        if (t.kind == .eof) return false;
        if (t.kind != .symbol) continue;
        if (std.mem.eql(u8, t.text, "(")) depth += 1;
        if (std.mem.eql(u8, t.text, ")")) {
            depth -= 1;
            if (depth == 0) return Parser.tokIs(p.toks[@min(j + 1, p.toks.len - 1)], .symbol, "=>");
        }
    }
    return false;
}

pub fn primary(p: *Parser) Error!*const Node {
    const t = p.peek();
    switch (t.kind) {
        .number => {
            _ = p.advance();
            return p.mk(.num, t, t.text, &.{});
        },
        .string => {
            _ = p.advance();
            return p.stringNode(t);
        },
        .char => {
            _ = p.advance();
            return p.charNode(t);
        },
        .ident => {
            if (reserved.has(t.text)) {
                return p.fail("unexpected '{s}' in an expression", .{t.text});
            }
            _ = p.advance();
            return p.mk(.name, t, t.text, &.{});
        },
        .symbol => {
            if (p.isSym("(") and p.isSymAt(1, ":")) return p.fail("a lambda has no type list: write overloaded functions instead (D-148)", .{});
            if (p.isSym("(")) {
                if (p.isLambda()) {
                    const prm = try p.params();
                    const arrow = p.peek();
                    try p.expectSym("=>");
                    const body = try p.group(")");
                    const lam = try p.mk(.lambda, arrow, "", &.{ prm, body });
                    return lam;
                }
                return p.group(")");
            } else if (p.isSym("[")) {
                return p.group("]");
            } else if (p.isSym("{")) {
                return p.group("}");
            } else if (p.isSym("$")) {
                _ = p.advance();
                return p.mk(.dollar, t, "", &.{});
            } else if (p.isSym("?")) {
                _ = p.advance();
                return p.mk(.open_end, t, "", &.{});
            } else return p.fail("unexpected '{s}' in an expression", .{t.text});
        },
        .eof => return p.fail("unexpected end of file in an expression", .{}),
    }
}

// ---- statements -------------------------------------------------------------------------
