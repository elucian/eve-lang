//! @eve-module parser
//! @spec spec/syntax/grammar.md, spec/syntax/declarations.md, spec/syntax/statements.md, spec/syntax/expressions.md
//! @feature F-VM-01, F-SPEC-02
//! @decision D-179
//! @tests test/level1, test/level2, test/level3
//! Parser: turns the tokens of a script into a syntax tree (see ast.zig) following the Eve grammar
//! (spec/syntax). On a syntax error it stops at the first one and says where.
//!
//! Grammar implemented so far (derived from test/level1; it grows test by test):
//!
//!     script     = aspect | module | macro                      (no free script, no `#!`: D-179)
//!     aspect     = [ "exclusive" | "concurrent" | "primary" ] "aspect" name "is" { declaration } "end" name ";"
//!                  (a process main, perhaps private processes)
//!     apply      = "apply" name { "/" name } "(" [ arguments ] ")" ";"
//!     declaration= let | set | class | function | method | process
//!     process    = "process" name "is" block [ "recover" block ] [ "finalize" block ] "return" ";"
//!     function   = "function" name [ params ] [ "=>" params ] "is" block "return" ";"   (method alike)
//!     class      = "class" name "=" "{" items "}" [ "<:" name ] ( ";" | "is" members "end" name ";" )
//!     statement  = let | set | if | while | loop | for | match | job | simple
//!     loop       = "loop" { declaration } ( "while" expr "do" tail | "do" block "repeat" [ "while" expr ] ";" )
//!     simple     = ( print | write | expect | raise | break | next | over | panic | retry | resume
//!                  | abort | expression [ assign-op expression ] ) [ "if" expression ] ";"
//!     expression : see `Parser.orExpr`, from the loosest operator (`or`) to a primary
//!
//! A parenthesized group with one item and no comma, `(a + b)`, is the item itself (grouping), not a
//! list of one element; `(a,)` is a list of one (D-058 said `(x)` is a list: the tests use it as grouping).
const std = @import("std");
const lexer = @import("lexer.zig");
const ast = @import("evecm").ast;
const checker = @import("check.zig");

const Token = lexer.Token;
const Node = ast.Node;
const Tag = ast.Tag;
pub const Diag = lexer.Diag;
pub const Error = lexer.Error;

const reserved = std.StaticStringMap(void).initComptime(.{
    .{"primary"},     .{"is"},        .{"process"},   .{"return"},    .{"end"},       .{"new"},     .{"set"},
    .{"let"},         .{"if"},        .{"else"},      .{"do"},        .{"done"},      .{"while"},   .{"loop"},
    .{"for"},         .{"in"},        .{"match"},     .{"when"},      .{"then"},      .{"break"},   .{"skip"},
    .{"raise"},       .{"recover"},   .{"finalize"},  .{"job"},       .{"retry"},     .{"resume"},  .{"abort"},
    .{"over"},        .{"exit"},      .{"stop"},      .{"pass"},      .{"panic"},     .{"print"},   .{"write"},
    .{"expect"},      .{"assert"},    .{"defer"},     .{"class"},     .{"function"},  .{"procedure"},
    .{"constructor"}, .{"public"},    .{"protected"}, .{"private"},   .{"and"},       .{"or"},      .{"xor"},
    .{"not"},         .{"repeat"},    .{"eq"},        .{"apply"},     .{"aspect"},    .{"exclusive"}, .{"concurrent"},
    .{"parallel"},    .{"start"},     .{"spawn"},     .{"await"},     .{"wait"},      .{"trait"},
});

// @eve-impl a plain number literal is converted once, by the parser (R1 of design/design-bytecode.md)
// @invariant the same value as `number` in code/evevm/src/interp/expr.zig gives for a text of digits (no comma, no suffix, no leading zero)
fn plainNumber(n: *Node, text: []const u8) void {
    if (text.len == 0 or text.len > 18 or (text.len > 1 and text[0] == '0' and text[1] != '.')) return;
    var dots: usize = 0;
    for (text) |c| {
        if (c == '.') {
            dots += 1;
        } else if (c < '0' or c > '9') return;
    }
    if (dots == 0) {
        n.lit_kind = .int;
        n.lit_bits = @bitCast(std.fmt.parseInt(i64, text, 10) catch return);
    } else if (dots == 1 and text[0] != '.' and text[text.len - 1] != '.') {
        n.lit_kind = .real;
        n.lit_bits = @bitCast(std.fmt.parseFloat(f64, text) catch return);
    }
}

/// Words that end a block: a statement list stops in front of them.
const block_end = std.StaticStringMap(void).initComptime(.{
    .{"return"}, .{"recover"}, .{"finalize"}, .{"done"}, .{"else"}, .{"then"}, .{"when"}, .{"end"}, .{"repeat"},
});

const Parser = struct {
    toks: []const Token,
    i: usize = 0,
    diag: *Diag,
    a: std.mem.Allocator,
    /// How many `parallel` do regions enclose the cursor: `start` is allowed only inside one (D-140).
    group_depth: usize = 0,
    /// How many `job` do regions enclose the cursor: `spawn` is allowed only inside one (D-143).
    job_depth: usize = 0,
    /// True in the body of a process: a `parallel` group is allowed only there (D-140).
    in_process: bool = false,
    /// The file being parsed when it is a module or an aspect of a project: routine nodes carry it (G-1).
    file: []const u8 = "",
    /// `file` once in the arena, shared by the routine nodes (a pointer costs less in a node than a slice).
    file_ref: ?*const []const u8 = null,
    /// True in the body of a generator: `yield` is allowed only there (D-067).
    in_generator: bool = false,
    /// Reading the name of an `external` routine: a reserved word such as `write` is a valid native name (D-189).
    external_name: bool = false,

    fn peek(p: *const Parser) Token {
        return p.toks[p.i];
    }

    fn peekAt(p: *const Parser, n: usize) Token {
        return p.toks[@min(p.i + n, p.toks.len - 1)];
    }

    fn advance(p: *Parser) Token {
        const t = p.toks[p.i];
        if (t.kind != .eof) p.i += 1;
        return t;
    }

    fn tokIs(t: Token, kind: Kind, text: []const u8) bool {
        return t.kind == kind and std.mem.eql(u8, t.text, text);
    }

    const Kind = lexer.Kind;

    /// Is the next token the identifier `text` (the keywords are identifiers to the lexer)?
    fn isWord(p: *const Parser, text: []const u8) bool {
        return tokIs(p.peek(), .ident, text);
    }

    fn isWordAt(p: *const Parser, n: usize, text: []const u8) bool {
        return tokIs(p.peekAt(n), .ident, text);
    }

    fn isSym(p: *const Parser, text: []const u8) bool {
        return tokIs(p.peek(), .symbol, text);
    }

    fn isSymAt(p: *const Parser, n: usize, text: []const u8) bool {
        return tokIs(p.peekAt(n), .symbol, text);
    }

    /// Consume the word if it is next; tell whether it was.
    fn acceptWord(p: *Parser, text: []const u8) bool {
        if (!p.isWord(text)) return false;
        _ = p.advance();
        return true;
    }

    fn acceptSym(p: *Parser, text: []const u8) bool {
        if (!p.isSym(text)) return false;
        _ = p.advance();
        return true;
    }

    fn fail(p: *Parser, comptime fmt: []const u8, args: anytype) Error {
        const t = p.peek();
        p.diag.set(t.line, t.col, fmt, args);
        return error.Syntax;
    }

    /// Like `fail`, but the error is reported at the token `t`.
    fn failAt(p: *Parser, t: Token, comptime fmt: []const u8, args: anytype) Error {
        p.diag.set(t.line, t.col, fmt, args);
        return error.Syntax;
    }

    fn describe(t: Token) []const u8 {
        return if (t.kind == .eof) "end of file" else t.text;
    }

    fn expectWord(p: *Parser, text: []const u8) Error!void {
        if (!p.acceptWord(text)) return p.fail("expected '{s}' but found '{s}'", .{ text, describe(p.peek()) });
    }

    fn expectSym(p: *Parser, text: []const u8) Error!void {
        if (!p.acceptSym(text)) return p.fail("expected '{s}' but found '{s}'", .{ text, describe(p.peek()) });
    }

    fn expectName(p: *Parser, what: []const u8) Error!Token {
        const t = p.peek();
        if (t.kind != .ident or reserved.has(t.text)) {
            return p.fail("expected {s} but found '{s}'", .{ what, describe(t) });
        }
        return p.advance();
    }

    // @eve-impl a name that may be a reserved word (the native members `write`, `expect`, `assert` of the system library)
    fn expectAnyName(p: *Parser) Error!Token {
        const t = p.peek();
        if (t.kind != .ident) return p.fail("expected a name but found '{s}'", .{describe(t)});
        return p.advance();
    }

    // ---- node construction ------------------------------------------------------------------

    fn mk(p: *Parser, tag: Tag, at: Token, text: []const u8, kids: []const *const Node) Error!*Node {
        const n = try p.a.create(Node);
        n.* = .{ .tag = tag, .line = at.line, .col = at.col, .text = text, .kids = try p.a.dupe(*const Node, kids) };
        switch (tag) {
            .bin => n.op = ast.opOf(text),
            .assign => if (std.mem.eql(u8, text, ":=")) {
                n.op = .set;
            } else if (std.mem.eql(u8, text, "::")) {
                n.op = .copy;
            } else if (std.mem.eql(u8, text, "<+")) {
                n.op = .push_back;
            } else if (std.mem.eql(u8, text, "+>")) {
                n.op = .push_front;
            } else if (text.len == 2 and text[1] == '=') {
                n.op = ast.opOf(text[0..1]);
            },
            .num => plainNumber(n, text),
            .type => n.tk = ast.typeKindOf(text),
            .function, .procedure, .method, .constructor, .destructor, .process, .generator => n.file = p.file_ref,
            else => {},
        }
        return n;
    }

    fn noneNode(p: *const Parser) *const Node {
        _ = p;
        return &ast.none;
    }

    // ---- literals ---------------------------------------------------------------------------

    fn appendCodePoint(p: *Parser, out: *std.ArrayList(u8), cp: u21) Error!void {
        var buf: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(cp, &buf) catch return p.fail("invalid Unicode code point", .{});
        try out.appendSlice(p.a, buf[0..n]);
    }

    /// The character an escape letter stands for, or null when the letter is not a simple escape.
    fn simpleEscape(c: u8) ?u8 {
        return switch (c) {
            'n' => '\n',
            't' => '\t',
            'r' => '\r',
            '0' => 0,
            '\\' => '\\',
            '"' => '"',
            '\'' => '\'',
            '{' => '{',
            '}' => '}',
            else => null,
        };
    }

    /// `'a'`, `'\n'` or `U+0061`: the node holds the UTF-8 bytes of the symbol.
    fn charNode(p: *Parser, t: Token) Error!*Node {
        var out: std.ArrayList(u8) = .empty;
        if (t.text[0] == 'U') {
            const cp = std.fmt.parseInt(u21, t.text[2..], 16) catch return p.fail("bad symbol literal", .{});
            try p.appendCodePoint(&out, cp);
        } else {
            const raw = t.text[1 .. t.text.len - 1];
            if (raw.len >= 2 and raw[0] == '\\') {
                const c = simpleEscape(raw[1]) orelse return p.failAt(t, "bad escape sequence \\{c}", .{raw[1]});
                try out.append(p.a, c);
            } else try out.appendSlice(p.a, raw);
        }
        const one = std.unicode.utf8CountCodepoints(out.items) catch 0;
        if (out.items.len == 0 and t.text.len == 2) return p.mk(.chr, t, "", &.{}); // '' is nil, the empty rune
        if (one != 1) return p.failAt(t, "a symbol literal holds exactly one character (use \"...\" for text)", .{});
        return p.mk(.chr, t, try out.toOwnedSlice(p.a), &.{});
    }

    /// Parse the text of an interpolation `\s{...}` as an expression.
    fn subExpr(p: *Parser, text: []const u8, at: Token) Error!*const Node {
        var d: Diag = .{};
        const toks = lexer.tokenize(p.a, text, &d) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.Syntax => {
                p.diag.set(at.line, at.col, "in interpolation: {s}", .{d.message()});
                return error.Syntax;
            },
        };
        var sub: Parser = .{ .toks = toks, .diag = p.diag, .a = p.a };
        const e = sub.expr() catch |err| {
            if (err == error.Syntax) {
                const why = try p.a.dupe(u8, p.diag.message()); // a copy: `set` writes in the same buffer
                p.diag.set(at.line, at.col, "in interpolation: {s}", .{why});
            }
            return err;
        };
        if (sub.peek().kind != .eof) {
            p.diag.set(at.line, at.col, "in interpolation: unexpected '{s}'", .{sub.peek().text});
            return error.Syntax;
        }
        return e;
    }

    // @decision D-097
    // @decision D-102
    /// A string literal: escapes decoded, placeholders parsed. `str` when plain, `interp` otherwise.
    fn stringNode(p: *Parser, t: Token) Error!*const Node {
        if (std.mem.startsWith(u8, t.text, "\"\"\"")) return p.textLiteral(t);
        const raw = t.text[1 .. t.text.len - 1];
        var cur: std.ArrayList(u8) = .empty;
        if (raw.len > 0 and raw[0] == '/') {
            var k: usize = 0;
            while (k < raw.len) : (k += 1) {
                if (raw[k] == '\\' and k + 1 < raw.len and raw[k + 1] == '"') k += 1;
                try cur.append(p.a, raw[k]);
            }
            return p.mk(.str, t, try cur.toOwnedSlice(p.a), &.{});
        }
        var parts: std.ArrayList(*const Node) = .empty;
        var i: usize = 0;
        while (i < raw.len) {
            const c = raw[i];
            if (c == '}') return p.failAt(t, "a lone '}}' in a string: write \\}}", .{});
            if (c == '{') {
                const close = matchBrace(raw, i) orelse return p.failAt(t, "unclosed placeholder: write \\{{ for a brace", .{});
                const inner = raw[i + 1 .. close];
                const pct = formatPercent(inner);
                const expr_text = std.mem.trim(u8, if (pct) |k| inner[0..k] else inner, " ");
                const spec = std.mem.trim(u8, if (pct) |k| inner[k + 1 ..] else "", " ");
                if (expr_text.len == 0) return p.failAt(t, "empty placeholder: write \\{{\\}} for braces", .{});
                if (cur.items.len > 0) try parts.append(p.a, try p.mk(.str, t, try cur.toOwnedSlice(p.a), &.{}));
                cur = .empty;
                var clean: std.ArrayList(u8) = .empty;
                var k: usize = 0;
                while (k < expr_text.len) : (k += 1) {
                    if (expr_text[k] == '\\' and k + 1 < expr_text.len and expr_text[k + 1] == '"') k += 1;
                    try clean.append(p.a, expr_text[k]);
                }
                const x = try p.subExpr(clean.items, t);
                try parts.append(p.a, try p.mk(.fmt, t, try std.fmt.allocPrint(p.a, "s{s}", .{spec}), &.{x}));
                i = close + 1;
                continue;
            }
            if (c == '&') {
                if (std.mem.indexOfScalarPos(u8, raw, i, ';')) |semi| {
                    if (try p.reference(&cur, raw[i + 1 .. semi])) {
                        i = semi + 1;
                        continue;
                    }
                }
            }
            if (c != '\\' or i + 1 >= raw.len) {
                try cur.append(p.a, c);
                i += 1;
                continue;
            }
            const e = raw[i + 1];
            if (e == '&') {
                try cur.append(p.a, '&');
                i += 2;
            } else if (simpleEscape(e)) |ch| {
                try cur.append(p.a, ch);
                i += 2;
            } else {
                return p.failAt(t, "bad escape sequence \\{c}", .{e});
            }
        }
        if (parts.items.len == 0) return p.mk(.str, t, try cur.toOwnedSlice(p.a), &.{});
        if (cur.items.len > 0) try parts.append(p.a, try p.mk(.str, t, try cur.toOwnedSlice(p.a), &.{}));
        return p.mk(.interp, t, "", parts.items);
    }

    /// A character reference `&...;` (the text between `&` and `;`): append it and say so, or say no.
    fn reference(p: *Parser, out: *std.ArrayList(u8), name: []const u8) Error!bool {
        const names = [_]struct { []const u8, u8 }{ .{ "amp", '&' }, .{ "lt", '<' }, .{ "gt", '>' }, .{ "quot", '"' }, .{ "apos", '\'' } };
        for (names) |n| {
            if (std.mem.eql(u8, n[0], name)) {
                try out.append(p.a, n[1]);
                return true;
            }
        }
        // the lower case Greek letters: alpha is U+03B1, omega U+03C9 (the final sigma U+03C2 has no name)
        const greek = [_][]const u8{ "alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota", "kappa", "lambda", "mu", "nu", "xi", "omicron", "pi", "rho", "", "sigma", "tau", "upsilon", "phi", "chi", "psi", "omega" };
        for (greek, 0..) |g, k| {
            if (g.len > 0 and std.mem.eql(u8, g, name)) {
                try p.appendCodePoint(out, @intCast(0x3B1 + k));
                return true;
            }
        }
        return false;
    }

    fn printArg(p: *Parser) Error!*const Node {
        const k = try p.expr();
        if (p.isSym(":")) {
            const t = p.advance();
            return p.mk(.pair, t, "", &.{ k, try p.expr() });
        }
        return k;
    }

    /// Index of the `}` that closes the `{` at `raw[open]`.
    fn matchBrace(raw: []const u8, open: usize) ?usize {
        var depth: usize = 0;
        var quote: u8 = 0; // the quote of the string literal being skipped, or 0
        var j = open;
        while (j < raw.len) : (j += 1) {
            const c = raw[j];
            if (quote != 0) {
                if (c == '\\') j += 1 else if (c == quote) quote = 0;
                continue;
            }
            if (c == '\\') {
                j += 1; // an escaped character, such as the old `\"` of a quoted key
                continue;
            }
            if (c == '"' or c == '\'') quote = c;
            if (c == '{') depth += 1;
            if (c == '}') {
                depth -= 1;
                if (depth == 0) return j;
            }
        }
        return null;
    }

    /// Index of the `%` that starts the format of a placeholder: the first one outside brackets.
    fn formatPercent(inner: []const u8) ?usize {
        var depth: usize = 0;
        var quote: u8 = 0;
        var skip = false; // the character after a backslash
        for (inner, 0..) |c, j| {
            if (skip) {
                skip = false;
                continue;
            }
            if (quote != 0) {
                if (c == quote) quote = 0;
                continue;
            }
            switch (c) {
                '\\' => skip = true,
                '"', '\'' => quote = c,
                '(', '[', '{' => depth += 1,
                ')', ']', '}' => depth -|= 1,
                '%' => if (depth == 0) return j,
                else => {},
            }
        }
        return null;
    }

    /// `"""` text literal: raw, several lines; the indentation of the closing quotes is removed.
    fn textLiteral(p: *Parser, t: Token) Error!*const Node {
        var s = t.text[3 .. t.text.len - 3];
        if (std.mem.indexOfScalar(u8, s, '\n')) |nl| {
            if (std.mem.trim(u8, s[0..nl], " \t\r").len == 0) s = s[nl + 1 ..];
        }
        var indent: []const u8 = "";
        var body = s;
        if (std.mem.lastIndexOfScalar(u8, s, '\n')) |nl| {
            const tail = s[nl + 1 ..];
            if (std.mem.trim(u8, tail, " \t\r").len == 0) {
                indent = tail;
                body = s[0..nl];
            }
        }
        var out: std.ArrayList(u8) = .empty;
        var lines = std.mem.splitScalar(u8, body, '\n');
        var first = true;
        while (lines.next()) |line| {
            if (!first) try out.append(p.a, '\n');
            first = false;
            const l = std.mem.trimEnd(u8, line, "\r");
            try out.appendSlice(p.a, if (std.mem.startsWith(u8, l, indent)) l[indent.len..] else l);
        }
        return p.mk(.text_lit, t, try out.toOwnedSlice(p.a), &.{});
    }

    // ---- types, parameters ------------------------------------------------------------------

    /// `Integer`, `[5]Integer`, `[]Integer`, `()Integer`, `Integer?`.
    fn typeName(p: *Parser) Error!*const Node {
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
    fn params(p: *Parser) Error!*const Node {
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
    fn routine(p: *Parser, tag: Tag) Error!*const Node {
        return p.routineOf(tag, false);
    }

    // @decision D-145
    /// A function, procedure, method or constructor; with `partial`, a signature that may end with `;`.
    fn routineOf(p: *Parser, tag: Tag, partial: bool) Error!*const Node {
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

    fn expr(p: *Parser) Error!*const Node {
        var l = try p.orExpr();
        while (p.isSym("<+") or p.isSym("+>") or p.isSym("<-") or p.isSym("->")) {
            const t = p.advance();
            const r = try p.orExpr();
            l = try p.mk(.bin, t, t.text, &.{ l, r });
        }
        return l;
    }

    fn orExpr(p: *Parser) Error!*const Node {
        var l = try p.xorExpr();
        while (p.isWord("or")) {
            const t = p.advance();
            l = try p.mk(.bin, t, "or", &.{ l, try p.xorExpr() });
        }
        return l;
    }

    fn xorExpr(p: *Parser) Error!*const Node {
        var l = try p.andExpr();
        while (p.isWord("xor")) {
            const t = p.advance();
            l = try p.mk(.bin, t, "xor", &.{ l, try p.andExpr() });
        }
        return l;
    }

    fn andExpr(p: *Parser) Error!*const Node {
        var l = try p.notExpr();
        while (p.isWord("and")) {
            const t = p.advance();
            l = try p.mk(.bin, t, "and", &.{ l, try p.notExpr() });
        }
        return l;
    }

    fn notExpr(p: *Parser) Error!*const Node {
        if (p.isWord("not") and !p.isWordAt(1, "in")) {
            const t = p.advance();
            return p.mk(.un, t, "not", &.{try p.notExpr()});
        }
        return p.compare();
    }

    /// `== <> < > <= >= =~ !~ in, not in, is, is not` (a chain is accepted, left to right).
    fn compare(p: *Parser) Error!*const Node {
        var l = try p.range();
        while (p.compareOp()) |op| {
            l = try p.mk(.bin, op.tok, op.text, &.{ l, try p.range() });
        }
        return l;
    }

    fn compareOp(p: *Parser) ?struct { tok: Token, text: []const u8 } {
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
    fn range(p: *Parser) Error!*const Node {
        const l = try p.additive();
        const ops = [_][]const u8{ "..", "..<", ">..", ">..<", "+-" };
        const t = p.peek();
        for (ops) |op| {
            if (p.acceptSym(op)) return p.mk(.range, t, op, &.{ l, try p.additive() });
        }
        return l;
    }

    fn additive(p: *Parser) Error!*const Node {
        var l = try p.multiplicative();
        while (p.isSym("+") or p.isSym("-") or p.isSym("||")) {
            const t = p.advance();
            l = try p.mk(.bin, t, t.text, &.{ l, try p.multiplicative() });
        }
        return l;
    }

    fn multiplicative(p: *Parser) Error!*const Node {
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
    fn unary(p: *Parser) Error!*const Node {
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
    fn power(p: *Parser) Error!*const Node {
        const l = try p.unary();
        if (p.isSym("^")) {
            const t = p.advance();
            return p.mk(.bin, t, "^", &.{ l, try p.power() });
        }
        return l;
    }

    fn postfix(p: *Parser) Error!*const Node {
        const first = p.peek();
        var n = try p.primary();
        var callable = first.kind == .ident or (first.kind == .symbol and first.text[0] == '(');
        while (true) {
            if (p.isSym(".")) {
                const dot = p.advance();
                // an attribute may be named like a keyword: `$error.job`
                if (p.peek().kind != .ident) return p.fail("expected an attribute name but found '{s}'", .{describe(p.peek())});
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
    fn indexList(p: *Parser, obj: *const Node) Error![]const *const Node {
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
    fn item(p: *Parser) Error!*const Node {
        const k = try p.conditional();
        if (p.isSym(":")) {
            const t = p.advance();
            return p.mk(.pair, t, "", &.{ k, try p.conditional() });
        }
        return k;
    }

    fn conditional(p: *Parser) Error!*const Node {
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
    fn items(p: *Parser, close: []const u8, out: *std.ArrayList(*const Node)) Error!void {
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
    fn group(p: *Parser, close: []const u8) Error!*const Node {
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
    fn isLambda(p: *const Parser) bool {
        var depth: usize = 0;
        var j = p.i;
        while (j < p.toks.len) : (j += 1) {
            const t = p.toks[j];
            if (t.kind == .eof) return false;
            if (t.kind != .symbol) continue;
            if (std.mem.eql(u8, t.text, "(")) depth += 1;
            if (std.mem.eql(u8, t.text, ")")) {
                depth -= 1;
                if (depth == 0) return tokIs(p.toks[@min(j + 1, p.toks.len - 1)], .symbol, "=>");
            }
        }
        return false;
    }

    fn primary(p: *Parser) Error!*const Node {
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

    /// Statements up to a word that ends the block (`return`, `done`, `else`, ...).
    fn block(p: *Parser) Error!*const Node {
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
    fn endSimple(p: *Parser, stmt: *const Node) Error!*const Node {
        if (p.isWord("if")) {
            const t = p.advance();
            const c = try p.expr();
            try p.expectSym(";");
            return p.mk(.cond_stmt, t, "", &.{ c, stmt });
        }
        try p.expectSym(";");
        return stmt;
    }

    fn assignOp(p: *const Parser) ?[]const u8 {
        const ops = [_][]const u8{ ":=", "::", "+=", "-=", "*=", "/=", "%=", "^=" };
        for (ops) |op| {
            if (p.isSym(op)) return op;
        }
        return null;
    }

    /// `new a, b := value :Type;`, `new x = y = 1 :Integer;`, `new a :Type;`, `new p, *rest :: n;`,
    /// `new e <- list;` and the constants `set A = 1;` (D-076).
    fn declaration(p: *Parser) Error!*const Node {
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
            const op = if (p.acceptSym("=")) "=" else if (p.acceptSym(":=")) ":=" else return p.fail("expected '=' or ':=' but found '{s}'", .{describe(p.peek())});
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
    fn letStatement(p: *Parser) Error!*const Node {
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
        return p.fail("expected an assignment operator after 'let' but found '{s}'", .{describe(p.peek())});
    }

    // @decision D-034
    /// The common end of `while`, `for`: `block [else block] done [label] ;`. Appends the body, else and
    /// then blocks to `kids`; the then block is always empty, the slot stays so the tree keeps its shape.
    fn loopTail(p: *Parser, kids: *std.ArrayList(*const Node), label: []const u8) Error!void {
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
    fn refuseThen(p: *Parser) Error!void {
        if (p.isWord("then")) return p.fail("'then' no longer exists: write the statements after 'done;'", .{});
    }

    fn closeLabel(p: *Parser, label: []const u8) Error!void {
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
    fn whileLoop(p: *Parser, label: []const u8, header: []const *const Node) Error!*const Node {
        const t = p.advance();
        var kids: std.ArrayList(*const Node) = .empty;
        try kids.append(p.a, try p.mk(.block, t, "", header));
        try kids.append(p.a, try p.expr());
        try p.expectWord("do");
        try p.loopTail(&kids, label);
        return p.mk(.while_, t, label, kids.items);
    }

    /// `for pattern in expression do ... done [label];`
    fn forLoop(p: *Parser, label: []const u8, header: []const *const Node) Error!*const Node {
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
    fn loopBlock(p: *Parser, label: []const u8) Error!*const Node {
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
        if (!p.isWord("repeat")) return p.fail("a 'loop … do' block ends with 'repeat', found '{s}'", .{describe(p.peek())});
        _ = p.advance();
        if (label.len > 0 and p.peek().kind == .ident and !p.isWord("while")) {
            const name = try p.expectName("the label");
            if (!std.mem.eql(u8, name.text, label)) return p.failAt(name, "'repeat {s}' does not match the label '{s}'", .{ name.text, label });
        }
        if (p.acceptWord("while")) try kids.append(p.a, try p.expr());
        try p.expectSym(";");
        return p.mk(.repeat_, t, label, kids.items);
    }

    fn ifStatement(p: *Parser) Error!*const Node {
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

    fn matchStatement(p: *Parser, label: []const u8) Error!*const Node {
        const kw = p.peek();
        try p.expectWord("match");
        const subject = try p.expr();
        // `one` (the default) stops at the first match, `all` tries every `when`
        const mode: []const u8 = if (p.acceptWord("one")) "one" else if (p.acceptWord("all")) "all" else "one";
        if (!p.isWord("when")) return p.fail("expected 'when' but found '{s}'", .{describe(p.peek())});
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
    fn isYieldStatement(p: *const Parser) bool {
        const next = p.peekAt(1);
        if (next.kind != .symbol) return true;
        const names_it = [_][]const u8{ ":=", "::", "=", "(", ".", "[", "+=", "-=", "*=", "/=", "%=", "^=", "<+", "+>" };
        for (names_it) |s| if (std.mem.eql(u8, next.text, s)) return false;
        return true;
    }

    /// `sql function …` as a declaration (`sql` is a keyword only before `function`, D-116, D-166).
    fn isSqlFunction(p: *const Parser) bool {
        return p.isWord("sql") and p.isWordAt(1, "function");
    }

    /// `sql function name(params) => (@r: T) is … return;`: a function that SQL can call (database.md, SQL functions).
    fn sqlFunction(p: *Parser) Error!*const Node {
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
    fn sqlType(p: *Parser, kw: Token, q: *const Node, what: []const u8) Error!void {
        const ty = q.ty orelse return p.failAt(kw, "the {s} '{s}' of a sql function needs a type (D-166)", .{ what, q.text });
        const base = std.mem.trimEnd(u8, ty.text, "?");
        const sql_types = [_][]const u8{ "Integer", "Natural", "Real", "Float", "Decimal", "String", "Logic", "Instant" };
        for (sql_types) |t| if (std.mem.eql(u8, base, t)) return;
        return p.failAt(kw, "the {s} '{s}' of a sql function has the type {s}, which SQL does not have (D-166)", .{ what, q.text, ty.text });
    }

    /// `table name: Class …` as a declaration (`table` is a word only at the start of a declaration, D-116).
    fn isTableDecl(p: *const Parser) bool {
        return p.isWord("table") and p.peekAt(1).kind == .ident and p.isSymAt(2, ":");
    }

    /// `table name: Class in "connection" [as "name"] ;` or with `is clauses end name;` (database.md, the table declaration).
    fn tableDecl(p: *Parser) Error!*const Node {
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
            if (w.kind != .ident) return p.fail("unexpected '{s}' in the table declaration", .{describe(w)});
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
    fn isGeneratorDecl(p: *const Parser) bool {
        return p.isWord("generator") and p.peekAt(1).kind == .ident;
    }

    fn statement(p: *Parser) Error!*const Node {
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

    fn process(p: *Parser) Error!*const Node {
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

    /// `class Name = (params) [: Type] <: Function;` (callbacks.html).
    fn functionType(p: *Parser, kw: Token, name: []const u8) Error!*const Node {
        _ = try p.params();
        if (p.acceptSym(":")) _ = try p.typeName();
        try p.expectSym("<:");
        const parent = try p.expectName("a parent class name");
        try p.expectSym(";");
        return p.mk(.class, kw, name, &.{ try p.mk(.block, kw, "", &.{}), try p.mk(.name, parent, parent.text, &.{}) });
    }

    fn class(p: *Parser) Error!*const Node {
        const kw = p.peek();
        try p.expectWord("class");
        const name = try p.expectName("a class name");
        try p.typeParams();
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
            } else if (p.isWord("destructor")) {
                // @eve-impl the destructor of a class, run when the object is freed (CLS-14, D-202)
                // @spec spec/syntax/declarations.md#classes-and-objects
                // @test c41_destructor
                try kids.append(p.a, try p.routine(.destructor));
            } else if (p.isWord("method")) {
                try kids.append(p.a, try p.routineOf(.method, true));
            } else if (p.isGeneratorDecl()) {
                try kids.append(p.a, try p.routine(.generator));
            } else return p.fail("unexpected '{s}' in the class, expected a constructor or a method", .{describe(p.peek())});
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
        return node;
    }

    // @decision D-145
    /// `(:T)` or `(:T <: Comparable, :U)` after the name of a generic class or trait.
    fn typeParams(p: *Parser) Error!void {
        _ = try p.typeList();
    }

    // @decision D-148
    /// The list of types of a generic subprogram or class; an empty `params` node when there is none.
    fn typeList(p: *Parser) Error!*const Node {
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
    fn trait(p: *Parser) Error!*const Node {
        const kw = p.advance();
        const name = try p.expectName("a trait name");
        try p.typeParams();
        try p.expectWord("is");
        var kids: std.ArrayList(*const Node) = .empty;
        try kids.append(p.a, try p.mk(.block, kw, "", &.{}));
        try kids.append(p.a, p.noneNode());
        while (!p.isWord("end")) {
            if (!p.isWord("method")) return p.fail("a trait holds only methods, found '{s}'", .{describe(p.peek())});
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

    fn declarationInDriver(p: *Parser) Error!*const Node {
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
        return p.fail("unexpected '{s}': an aspect or a module holds declarations; a statement goes in a process, a function, a procedure or a method (D-126)", .{describe(p.peek())});
    }

    /// `from path use (m, m as x, m(*), *);`: the path is folder names or strings joined by `/` (modules.md).
    fn importDecl(p: *Parser) Error!*const Node {
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
    fn exportDecl(p: *Parser) Error!*const Node {
        const kw = p.advance();
        try p.expectSym("(");
        var names: std.ArrayList(*const Node) = .empty;
        while (true) {
            // a reserved word may be the name of a native member (`write`, `expect`): the export list is not a statement
            const t = p.peek();
            if (t.kind != .ident) return p.fail("expected a member name but found '{s}'", .{describe(t)});
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
    fn module(p: *Parser) Error!*const Node {
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
        if (!p.isWord("end")) return p.fail("unexpected '{s}' in the module: the regions are initialize, recover and finalize, in this order", .{describe(p.peek())});
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
    fn applyStatement(p: *Parser) Error!*const Node {
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
    fn startStatement(p: *Parser) Error!*const Node {
        if (p.group_depth == 0) return p.fail("start is allowed only in the do region of a parallel group (D-140)", .{});
        const n = try p.applyStatement();
        @constCast(n).tag = .start_stmt;
        return n;
    }

    /// `[label:] parallel [on error cancel] [within d] declarations do statements done [label];` (D-140).
    fn parallelBlock(p: *Parser, at: Token, label: []const u8) Error!*const Node {
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
    fn isAspectStart(p: *Parser) bool {
        return p.isWord("exclusive") or p.isWord("concurrent") or p.isWord("primary") or p.isWord("aspect");
    }

    /// `[exclusive|concurrent|primary] aspect name is … end name;`: a process `main`, the entry point, and perhaps
    /// private processes (D-179). Without a kind word the aspect is exclusive (D-130).
    fn aspect(p: *Parser) Error!*const Node {
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
    fn looksLikeMacro(p: *Parser) bool {
        for (p.toks[p.i..]) |t| {
            if (t.kind != .ident or t.col != 1) continue;
            if (std.mem.eql(u8, t.text, "aspect") or std.mem.eql(u8, t.text, "exclusive") or
                std.mem.eql(u8, t.text, "concurrent") or std.mem.eql(u8, t.text, "primary")) return true;
        }
        return false;
    }

    /// An Eve macro (D-152): shared declarations and aspects in one file, exactly one of them primary (D-180).
    fn macro(p: *Parser, first: ?*const Node) Error!*const Node {
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
            } else if (p.isWord("new") or p.isWord("set") or p.isWord("class") or p.isWord("trait") or p.isWord("async") or
                p.isWord("function") or p.isWord("procedure") or p.isWord("method") or p.isWord("from") or p.isGeneratorDecl() or p.isTableDecl() or
                p.isSqlFunction())
            {
                try shared.append(p.a, try p.declarationInDriver());
            } else {
                return p.fail("a statement outside a declaration in a macro: '{s}' goes in a process (D-152)", .{describe(p.peek())});
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
    fn script(p: *Parser) Error!*const Node {
        var result: *const Node = undefined;
        if (p.isAspectStart()) {
            result = try p.aspect();
            if (p.peek().kind != .eof) result = try p.macro(result);
        } else if (p.isWord("module") or ((p.isWord("managed") or p.isWord("direct")) and p.isWordAt(1, "module"))) {
            result = try p.module();
        } else if (p.looksLikeMacro()) {
            result = try p.macro(null);
        } else {
            return p.fail("a file holds an aspect or a module: '{s}' cannot start it; a statement goes in a process (D-179)", .{describe(p.peek())});
        }
        if (p.peek().kind != .eof) return p.fail("unexpected '{s}' after the end of the aspect", .{describe(p.peek())});
        return result;
    }
};

/// Parse `src` into a tree. On a syntax error returns `error.Syntax` and fills `diag`.
pub fn parse(arena: std.mem.Allocator, src: []const u8, diag: *Diag) Error!*const Node {
    return parseFile(arena, src, diag, "");
}

// @eve-impl parse a module or an aspect of a project: its routines remember the file for the errors
// @see backlog/library-gaps.md:G-1
/// `parse`, and every routine of the tree carries `file` (the path of the module), so an error raised in it names that file.
pub fn parseFile(arena: std.mem.Allocator, src: []const u8, diag: *Diag, file: []const u8) Error!*const Node {
    const toks = try lexer.tokenize(arena, src, diag);
    var p: Parser = .{ .toks = toks, .diag = diag, .a = arena, .file = file };
    if (file.len > 0) {
        const ref = try arena.create([]const u8);
        ref.* = file;
        p.file_ref = ref;
    }
    const tree = try p.script();
    try checker.check(arena, tree, diag);
    return tree;
}

/// The syntax only: the tree of a text that is Eve, before the static checks (names, scopes, overloads). The tools use it to
/// show an outline even when a rule of the checker is broken (`analyze.zig`); `parse` is this plus `checker.check`.
// @eve-impl parse without the static checks
// @see code/evecp/src/analyze.zig:analyze
pub fn parseSyntax(arena: std.mem.Allocator, src: []const u8, diag: *Diag) Error!*const Node {
    const toks = try lexer.tokenize(arena, src, diag);
    var p: Parser = .{ .toks = toks, .diag = diag, .a = arena };
    return try p.script();
}

/// Check the script `src`. On a syntax error returns `error.Syntax` and fills `diag`.
pub fn check(gpa: std.mem.Allocator, src: []const u8, diag: *Diag) Error!void {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    _ = try parse(arena.allocator(), src, diag);
}

test "a minimal primary aspect parses" {
    var d: Diag = .{};
    try check(std.testing.allocator,
        \\# test
        \\primary aspect a01_driver is
        \\  process main is
        \\    over;
        \\  return;
        \\end a01_driver;
        \\** trailing comment
    , &d);
}

test "errors are reported with a position" {
    var d: Diag = .{};
    try std.testing.expectError(error.Syntax, check(std.testing.allocator,
        \\primary aspect a is
        \\  process main is
        \\    over
        \\  return;
        \\end a;
    , &d));
    try std.testing.expectEqual(@as(u32, 4), d.line);
    try std.testing.expectEqualStrings("expected ';' but found 'return'", d.message());

    try std.testing.expectError(error.Syntax, check(std.testing.allocator, "primary aspect a is process m is return; end b;", &d));
    try std.testing.expectEqualStrings("'end b' does not match 'aspect a'", d.message());
}

// @decision D-179
test "a primary aspect with expressions parses, and a free statement does not" {
    var d: Diag = .{};
    try check(std.testing.allocator,
        \\primary aspect t is
        \\  process main is
        \\    print "Hello";
        \\    new a := 2 ^ 3 ^ 2;
        \\    let a += (1, 2, 3)[$ - 1];
        \\    expect (x | x in (1..5)) == (1, 2, 3, 4, 5);
        \\  return;
        \\end t;
    , &d);
    try std.testing.expectError(error.Syntax, check(std.testing.allocator, "print \"Hello\";", &d));
}

test "wrong scripts are rejected" {
    const bad = [_][]const u8{
        "let := 1;",
        "let a := ;",
        "print 1 +;",
        "if x do print 1;",
        "while True do print 1; done",
        "primary aspect a is process m is let x := (1, 2; return; end a;",
        "primary aspect a is end b;",
        "for i (1..2) do done;",
        "x := 1 2;",
        "loop do print 1; done;",
        "loop do print 1; repeat while;",
    };
    var d: Diag = .{};
    for (bad) |src| try std.testing.expectError(error.Syntax, check(std.testing.allocator, src, &d));
}

// @decision D-090
// @decision D-130
// @decision D-179
// @decision D-181
test "an aspect and an apply parse, and the aspect rules hold" {
    var d: Diag = .{};
    try check(std.testing.allocator, "exclusive aspect a is process main(x: Integer, @y: Integer) is let y := x; return; end a;", &d);
    try check(std.testing.allocator, "concurrent aspect a is process main is return; end a;", &d);
    try check(std.testing.allocator, "aspect a is process main is return; end a;", &d);
    try check(std.testing.allocator, "primary aspect a is process main is apply prepare(); return; process prepare is return; end a;", &d);
    try check(std.testing.allocator, "primary aspect t is process main is new r :Integer; apply tools/a(1, v: 2, @r, *(3, 4)); return; end t;", &d);
    const bad = [_][]const u8{
        "exclusive aspect a is process other is return; end a;",
        "exclusive aspect a is function f() => (@r: Integer) is return; end a;",
        "exclusive aspect a is process main is return; process main is return; end a;",
        "exclusive aspect a is process main is apply b.p(); return; end a;",
        "primary aspect t is process main is apply b; return; end t;",
    };
    for (bad) |src| try std.testing.expectError(error.Syntax, check(std.testing.allocator, src, &d));
}

// @decision D-126
test "a module parses: imports, exports and regions; a free statement is refused" {
    var d: Diag = .{};
    try check(std.testing.allocator, "managed module m is from lib use (a, b as c, d(*)); export (f, g!); " ++
        "function f() => (@r: Integer) is let r := 1; return; " ++
        "initialize print \"up\"; recover print \"oops\"; finalize print \"down\"; end m;", &d);
    const bad = [_][]const u8{
        "module m is print \"x\"; end m;",
        "module m is process main is return; end m;",
        "module m is finalize print \"a\"; initialize print \"b\"; end m;",
    };
    for (bad) |src| try std.testing.expectError(error.Syntax, check(std.testing.allocator, src, &d));
}

test "Atomic(:T) is a type hint and a class may have no shape" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var d: Diag = .{};
    const tree = try parse(arena.allocator(), "primary aspect t is class S <: Atomic(:Integer); new n = 0 :Atomic(:Integer); new m = 0 :Integer; process main is return; end t;", &d);
    const cls = tree.kids[0];
    try std.testing.expectEqualStrings("Atomic", cls.kids[1].text);
    try std.testing.expectEqualStrings("Integer", cls.kids[1].ty.?.text);
    try std.testing.expect(tree.kids[1].ty.?.public);
    try std.testing.expectEqualStrings("Integer", tree.kids[1].ty.?.text);
    try std.testing.expect(!tree.kids[2].ty.?.public);
    // a type argument needs its colon
    try std.testing.expectError(error.Syntax, check(std.testing.allocator, "new n = 0 :Atomic(Integer);", &d));
}
