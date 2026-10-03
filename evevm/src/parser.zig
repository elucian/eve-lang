//! Parser: turns the tokens of a script into a syntax tree (see ast.zig) following the Eve grammar
//! (spec/syntax). On a syntax error it stops at the first one and says where.
//!
//! Grammar implemented so far (derived from test/level1; it grows test by test):
//!
//!     script     = driver | { statement }                      (a script without a driver is "free")
//!     driver     = "driver" name "is" { declaration } "end" name ";"
//!     declaration= let | set | class | function | method | process
//!     process    = "process" name "is" block [ "recover" block ] [ "finalize" block ] "return" ";"
//!     function   = "function" name [ params ] [ "=>" params ] "is" block "return" ";"   (method alike)
//!     class      = "class" name "=" "{" items "}" [ "<:" name ] ( ";" | "is" members "end" name ";" )
//!     statement  = let | set | if | while | loop | for | match | job | simple
//!     simple     = ( print | write | expect | raise | break | next | over | panic | retry | resume
//!                  | abort | expression [ assign-op expression ] ) [ "if" expression ] ";"
//!     expression : see `Parser.orExpr`, from the loosest operator (`or`) to a primary
//!
//! A parenthesized group with one item and no comma, `(a + b)`, is the item itself (grouping), not a
//! list of one element; `(a,)` is a list of one (D-058 said `(x)` is a list: the tests use it as grouping).
const std = @import("std");
const lexer = @import("lexer.zig");
const ast = @import("ast.zig");

const Token = lexer.Token;
const Node = ast.Node;
const Tag = ast.Tag;
pub const Diag = lexer.Diag;
pub const Error = lexer.Error;

// Zig tip: a `const` array of strings at file level is built by the compiler. `std.StaticStringMap`
// is a lookup table of strings fixed at compile time: `.initComptime(.{ ... })` takes a tuple of
// `.{ key }` entries (with `void` as value, it acts as a set), and `has(text)` is the test. No
// allocation and no hashing at run time.
const reserved = std.StaticStringMap(void).initComptime(.{
    .{"driver"},      .{"is"},       .{"process"}, .{"return"}, .{"end"},    .{"let"},      .{"set"},
    .{"if"},          .{"else"},     .{"do"},      .{"done"},   .{"while"},  .{"loop"},     .{"for"},
    .{"in"},          .{"match"},    .{"when"},    .{"then"},   .{"break"},  .{"next"},     .{"raise"},
    .{"recover"},     .{"finalize"}, .{"job"},     .{"retry"},  .{"resume"}, .{"abort"},    .{"over"},
    .{"panic"},       .{"print"},    .{"write"},   .{"expect"}, .{"class"},  .{"function"}, .{"method"},
    .{"constructor"}, .{"and"},      .{"or"},      .{"xor"},    .{"not"},    .{"new"},
});

/// Words that end a block: a statement list stops in front of them.
const block_end = std.StaticStringMap(void).initComptime(.{
    .{"return"}, .{"recover"}, .{"finalize"}, .{"done"}, .{"else"}, .{"then"}, .{"when"}, .{"end"},
});

// Zig tip: this is a "recursive descent" parser: one function per grammar rule, each one consuming
// tokens and calling the functions of the rules inside it. `p.i` is the index of the next token.
// Operator precedence is encoded by the call chain: `orExpr` calls `xorExpr`, which calls
// `andExpr`, ... down to `primary`; the tighter an operator binds, the deeper its function is.
// Every function returns `Error!*const Node` (or `Error!void`) and the callers use `try`, so the
// first syntax error unwinds the whole parse and `diag` keeps its message. Nodes are allocated
// from `a`, an arena: nothing is freed one by one, the whole tree goes away with the arena.
const Parser = struct {
    toks: []const Token,
    i: usize = 0,
    diag: *Diag,
    a: std.mem.Allocator,

    // Zig tip: a function whose first parameter is the struct (`p: *Parser`) is called with dot
    // syntax: `p.name(...)`.
    fn peek(p: *const Parser) Token {
        return p.toks[p.i];
    }

    // Zig tip: `@min(a, b)` keeps an index inside the array: past the last token (always the eof
    // token) the parser sees eof again instead of reading out of bounds.
    fn peekAt(p: *const Parser, n: usize) Token {
        return p.toks[@min(p.i + n, p.toks.len - 1)];
    }

    // Zig tip: `advance` relies on the same Zig feature as `peek` above: see the tip there.
    fn advance(p: *Parser) Token {
        const t = p.toks[p.i];
        if (t.kind != .eof) p.i += 1;
        return t;
    }

    // Zig tip: `std.mem.eql(u8, a, b)` compares two slices by content; `==` on slices would compare
    // their addresses.
    fn tokIs(t: Token, kind: Kind, text: []const u8) bool {
        return t.kind == kind and std.mem.eql(u8, t.text, text);
    }

    const Kind = lexer.Kind;

    // Zig tip: `isWord` relies on the same Zig feature as `peek` above: see the tip there.
    /// Is the next token the identifier `text` (the keywords are identifiers to the lexer)?
    fn isWord(p: *const Parser, text: []const u8) bool {
        return tokIs(p.peek(), .ident, text);
    }

    // Zig tip: `isWordAt` relies on the same Zig feature as `peek` above: see the tip there.
    fn isWordAt(p: *const Parser, n: usize, text: []const u8) bool {
        return tokIs(p.peekAt(n), .ident, text);
    }

    // Zig tip: `isSym` relies on the same Zig feature as `peek` above: see the tip there.
    fn isSym(p: *const Parser, text: []const u8) bool {
        return tokIs(p.peek(), .symbol, text);
    }

    // Zig tip: `isSymAt` relies on the same Zig feature as `peek` above: see the tip there.
    fn isSymAt(p: *const Parser, n: usize, text: []const u8) bool {
        return tokIs(p.peekAt(n), .symbol, text);
    }

    // Zig tip: `acceptWord` relies on the same Zig feature as `peek` above: see the tip there.
    /// Consume the word if it is next; tell whether it was.
    fn acceptWord(p: *Parser, text: []const u8) bool {
        if (!p.isWord(text)) return false;
        _ = p.advance();
        return true;
    }

    // Zig tip: `acceptSym` relies on the same Zig feature as `peek` above: see the tip there.
    fn acceptSym(p: *Parser, text: []const u8) bool {
        if (!p.isSym(text)) return false;
        _ = p.advance();
        return true;
    }

    // Zig tip: `anytype` and `comptime fmt` let one `fail` take any message. `{s}` prints a
    // string. The function returns `Error` (not `Error!void`): it always fails, so callers
    // write `return p.fail(...)`, and the compiler accepts it wherever an error union is
    // expected, since an error value coerces to any error union that contains it.
    fn fail(p: *Parser, comptime fmt: []const u8, args: anytype) Error {
        const t = p.peek();
        p.diag.set(t.line, t.col, fmt, args);
        return error.Syntax;
    }

    // Zig tip: `failAt` relies on the same Zig feature as `peek` above: see the tip there.
    /// Like `fail`, but the error is reported at the token `t`.
    fn failAt(p: *Parser, t: Token, comptime fmt: []const u8, args: anytype) Error {
        p.diag.set(t.line, t.col, fmt, args);
        return error.Syntax;
    }

    // Zig tip: `describe` relies on the same Zig feature as `peek` above: see the tip there.
    fn describe(t: Token) []const u8 {
        return if (t.kind == .eof) "end of file" else t.text;
    }

    // Zig tip: `expectWord` relies on the same Zig feature as `peek` above: see the tip there.
    fn expectWord(p: *Parser, text: []const u8) Error!void {
        if (!p.acceptWord(text)) return p.fail("expected '{s}' but found '{s}'", .{ text, describe(p.peek()) });
    }

    // Zig tip: `expectSym` relies on the same Zig feature as `peek` above: see the tip there.
    fn expectSym(p: *Parser, text: []const u8) Error!void {
        if (!p.acceptSym(text)) return p.fail("expected '{s}' but found '{s}'", .{ text, describe(p.peek()) });
    }

    // Zig tip: `expectName` relies on the same Zig feature as `peek` above: see the tip there.
    fn expectName(p: *Parser, what: []const u8) Error!Token {
        const t = p.peek();
        if (t.kind != .ident or reserved.has(t.text)) {
            return p.fail("expected {s} but found '{s}'", .{ what, describe(t) });
        }
        return p.advance();
    }

    // ---- node construction ------------------------------------------------------------------

    // Zig tip: `a.create(Node)` allocates one `Node` and returns a pointer to it; `a.dupe(T, xs)`
    // allocates a copy of a slice. `ptr.* = .{ ... }` fills the new node by writing through the
    // pointer. `[]const *const Node` is "a slice of pointers to read-only nodes": the parts of a
    // node are shared, never copied. `&.{ l, r }` is an inline array that coerces to that slice.
    fn mk(p: *Parser, tag: Tag, at: Token, text: []const u8, kids: []const *const Node) Error!*Node {
        const n = try p.a.create(Node);
        n.* = .{ .tag = tag, .line = at.line, .col = at.col, .text = text, .kids = try p.a.dupe(*const Node, kids) };
        return n;
    }

    // Zig tip: `noneNode` relies on the same Zig feature as `peek` above: see the tip there.
    fn noneNode(p: *const Parser) *const Node {
        _ = p;
        return &ast.none;
    }

    // ---- literals ---------------------------------------------------------------------------

    // Zig tip: `std.fmt.parseInt(u21, hex, 16)` converts text to a number in a base; it returns an
    // error union, so `catch` gives a fallback. `u21` is the type of a Unicode code point.
    // `std.unicode.utf8Encode(cp, &buf)` writes the UTF-8 bytes of a code point and returns how
    // many. `buf[0..n]` is then a slice of exactly those bytes.
    fn appendCodePoint(p: *Parser, out: *std.ArrayList(u8), cp: u21) Error!void {
        var buf: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(cp, &buf) catch return p.fail("invalid Unicode code point", .{});
        try out.appendSlice(p.a, buf[0..n]);
    }

    // Zig tip: `a orelse b` unwraps an optional: it gives `b` when `a` is null, and `b` may leave
    // the function with `return`.
    /// `\xHH` or `\u{H...}` at `raw[i]` (the backslash). Returns the code point and the index after it.
    fn hexEscape(p: *Parser, raw: []const u8, i: usize) Error!struct { cp: u21, next: usize } {
        if (raw[i + 1] == 'x' and i + 4 <= raw.len) {
            const cp = std.fmt.parseInt(u21, raw[i + 2 .. i + 4], 16) catch return p.fail("bad \\x escape", .{});
            return .{ .cp = cp, .next = i + 4 };
        }
        if (raw[i + 1] == 'u' and i + 2 < raw.len and raw[i + 2] == '{') {
            const close = std.mem.indexOfScalarPos(u8, raw, i + 3, '}') orelse return p.fail("bad \\u escape", .{});
            const cp = std.fmt.parseInt(u21, raw[i + 3 .. close], 16) catch return p.fail("bad \\u escape", .{});
            return .{ .cp = cp, .next = close + 1 };
        }
        return p.fail("bad escape sequence", .{});
    }

    // Zig tip: a `switch` is an expression: it must cover every case, or end with `else`, and the
    // compiler checks it.
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

    // Zig tip: `x catch |e| ...` handles the error of a call on the spot, where `try` would pass it
    // up to the caller.
    /// `'a'`, `'\x41'`, `'\u{3B1}'` or `U+0061`: the node holds the UTF-8 bytes of the symbol.
    fn charNode(p: *Parser, t: Token) Error!*Node {
        var out: std.ArrayList(u8) = .empty;
        if (t.text[0] == 'U') {
            const cp = std.fmt.parseInt(u21, t.text[2..], 16) catch return p.fail("bad symbol literal", .{});
            try p.appendCodePoint(&out, cp);
        } else {
            const raw = t.text[1 .. t.text.len - 1];
            if (raw.len >= 2 and raw[0] == '\\') {
                if (simpleEscape(raw[1])) |c| {
                    try out.append(p.a, c);
                } else {
                    const h = try p.hexEscape(raw, 0);
                    try p.appendCodePoint(&out, h.cp);
                }
            } else try out.appendSlice(p.a, raw);
        }
        const one = std.unicode.utf8CountCodepoints(out.items) catch 0;
        if (one != 1) return p.failAt(t, "a symbol literal holds exactly one character (use \"...\" for text)", .{});
        return p.mk(.chr, t, try out.toOwnedSlice(p.a), &.{});
    }

    // Zig tip: `subExpr` relies on the same Zig feature as `charNode` above: see the tip there.
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
            if (err == error.Syntax) p.diag.set(at.line, at.col, "in interpolation: {s}", .{p.diag.message()});
            return err;
        };
        if (sub.peek().kind != .eof) {
            p.diag.set(at.line, at.col, "in interpolation: unexpected '{s}'", .{sub.peek().text});
            return error.Syntax;
        }
        return e;
    }

    // Zig tip: a string is decoded once, here, not every time the script runs: the tree holds the
    // final text. `std.ArrayList(u8)` is the growable byte buffer that builds it. The `while`
    // loop walks the raw bytes by index because an escape takes several of them. A labeled
    // result `.{ .cp = ..., .next = ... }` of an anonymous struct type lets `hexEscape` return two
    // values at once. `parts` collects the pieces of a string with interpolation.
    /// A string literal: escapes decoded, interpolations parsed. `str` when plain, `interp` otherwise.
    fn stringNode(p: *Parser, t: Token) Error!*const Node {
        if (std.mem.startsWith(u8, t.text, "\"\"\"")) return p.textLiteral(t);
        const raw = t.text[1 .. t.text.len - 1];
        var cur: std.ArrayList(u8) = .empty;
        var parts: std.ArrayList(*const Node) = .empty;
        var i: usize = 0;
        while (i < raw.len) {
            if (raw[i] != '\\' or i + 1 >= raw.len) {
                try cur.append(p.a, raw[i]);
                i += 1;
                continue;
            }
            const e = raw[i + 1];
            if ((e == 's' or e == '#' or e == 'b') and i + 2 < raw.len and raw[i + 2] == '{') {
                const close = matchBrace(raw, i + 2) orelse return p.fail("unclosed interpolation", .{});
                const inner = raw[i + 3 .. close];
                const colon = formatColon(inner);
                const expr_text = if (colon) |c| inner[0..c] else inner;
                const spec = if (colon) |c| inner[c + 1 ..] else "";
                if (cur.items.len > 0) try parts.append(p.a, try p.mk(.str, t, try cur.toOwnedSlice(p.a), &.{}));
                cur = .empty;
                const x = try p.subExpr(expr_text, t);
                const text = try std.fmt.allocPrint(p.a, "{c}{s}", .{ e, spec });
                try parts.append(p.a, try p.mk(.fmt, t, text, &.{x}));
                i = close + 1;
            } else if (e == 'u' or e == 'x') {
                const h = try p.hexEscape(raw, i);
                try p.appendCodePoint(&cur, h.cp);
                i = h.next;
            } else if (simpleEscape(e)) |c| {
                try cur.append(p.a, c);
                i += 2;
            } else {
                return p.fail("bad escape sequence \\{c}", .{e});
            }
        }
        if (parts.items.len == 0) return p.mk(.str, t, try cur.toOwnedSlice(p.a), &.{});
        if (cur.items.len > 0) try parts.append(p.a, try p.mk(.str, t, try cur.toOwnedSlice(p.a), &.{}));
        return p.mk(.interp, t, "", parts.items);
    }

    // Zig tip: `?usize` is "an index or nothing". A function that searches returns it, and the
    // caller unwraps with `orelse`. `depth` counts the nested braces so `\#{ {a: 1}.a }` works.
    /// Index of the `}` that closes the `{` at `raw[open]`.
    fn matchBrace(raw: []const u8, open: usize) ?usize {
        var depth: usize = 0;
        var j = open;
        while (j < raw.len) : (j += 1) {
            if (raw[j] == '{') depth += 1;
            if (raw[j] == '}') {
                depth -= 1;
                if (depth == 0) return j;
            }
        }
        return null;
    }

    // Zig tip: `for (xs) |x| ...` walks a slice; `for (xs, 0..) |x, i|` also gives the index.
    /// Index of the `:` that starts the format of an interpolation: the first one outside brackets.
    fn formatColon(inner: []const u8) ?usize {
        var depth: usize = 0;
        for (inner, 0..) |c, j| {
            switch (c) {
                '(', '[', '{' => depth += 1,
                ')', ']', '}' => depth -|= 1,
                ':' => if (depth == 0) return j,
                else => {},
            }
        }
        return null;
    }

    // Zig tip: `while (cond) { ... }` repeats; `while (opt) |v|` repeats as long as an optional has
    // a value.
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
        return p.mk(.str, t, try out.toOwnedSlice(p.a), &.{});
    }

    // ---- types, parameters ------------------------------------------------------------------

    // Zig tip: a `while (true)` loop with `break` is the usual way to write "repeat until a
    // condition found inside". `if (!p.acceptSym(",")) break;` reads: no comma, the list is over.
    // `std.ArrayList(T).empty` starts an empty list; `append(allocator, x)` adds; `.items` is the
    // slice of what it holds.
    /// `Integer`, `[5]Integer`, `[2, 2]Integer`.
    fn typeName(p: *Parser) Error!*const Node {
        var dims: std.ArrayList(*const Node) = .empty;
        const first = p.peek();
        if (p.acceptSym("[")) {
            while (true) {
                try dims.append(p.a, try p.expr());
                if (!p.acceptSym(",")) break;
            }
            try p.expectSym("]");
        }
        const name = try p.expectName("a type name");
        _ = first;
        return p.mk(.type, name, name.text, dims.items);
    }

    // Zig tip: `std.ArrayList(T)` is a growable array: it starts `.empty`, `append(allocator, x)`
    // adds, `.items` is the slice of what it holds.
    /// `( [@]name [= default] [: Type], ... )` of a function, a method, a constructor or a lambda.
    fn params(p: *Parser) Error!*const Node {
        const open = p.peek();
        try p.expectSym("(");
        var list: std.ArrayList(*const Node) = .empty;
        if (!p.isSym(")")) {
            while (true) {
                const by_ref = p.acceptSym("@");
                const name = try p.expectName("a parameter name");
                var default: *const Node = p.noneNode();
                if (p.acceptSym("=")) default = try p.expr();
                const prm = try p.mk(if (by_ref) .ref_param else .param, name, name.text, &.{default});
                if (p.acceptSym(":")) prm.ty = try p.typeName();
                try list.append(p.a, prm);
                if (!p.acceptSym(",")) break;
            }
        }
        try p.expectSym(")");
        return p.mk(.params, open, "", list.items);
    }

    // Zig tip: `try f()` calls `f` and, when it returns an error, returns that error from this
    // function too.
    /// `[ (params) ] [ (params) ] [ => (results) ] is block return ;` shared by function, method, constructor.
    fn routine(p: *Parser, tag: Tag) Error!*const Node {
        const kw = p.advance();
        const name = if (tag == .constructor) kw else try p.expectName("a name");
        const empty = try p.mk(.params, kw, "", &.{});
        const first = if (p.isSym("(")) try p.params() else empty;
        const second = if (p.isSym("(")) try p.params() else empty; // a constructor: (@self)(fields)
        const results = if (p.acceptSym("=>")) try p.params() else empty;
        try p.expectWord("is");
        const body = try p.block();
        try p.expectWord("return");
        try p.expectSym(";");
        return p.mk(tag, kw, if (tag == .constructor) "" else name.text, &.{ first, second, results, body });
    }

    // ---- expressions ------------------------------------------------------------------------

    // Zig tip: `const t = p.peek();` before building a node keeps the token of the operator for the
    // line number. `p.mk(.bin, t, t.text, &.{ l, r })` is a binary node. The loop `while (cond) { l = ... }`
    // rebinds `l` (a `var`) so `a - b - c` becomes `(a - b) - c`: left to right.
    fn expr(p: *Parser) Error!*const Node {
        var l = try p.orExpr();
        while (p.isSym("<+") or p.isSym("<-") or p.isSym("->")) {
            const t = p.advance();
            const r = try p.orExpr();
            l = try p.mk(.bin, t, t.text, &.{ l, r });
        }
        return l;
    }

    // Zig tip: `orExpr` relies on the same Zig feature as `routine` above: see the tip there.
    fn orExpr(p: *Parser) Error!*const Node {
        var l = try p.xorExpr();
        while (p.isWord("or")) {
            const t = p.advance();
            l = try p.mk(.bin, t, "or", &.{ l, try p.xorExpr() });
        }
        return l;
    }

    // Zig tip: `xorExpr` relies on the same Zig feature as `routine` above: see the tip there.
    fn xorExpr(p: *Parser) Error!*const Node {
        var l = try p.andExpr();
        while (p.isWord("xor")) {
            const t = p.advance();
            l = try p.mk(.bin, t, "xor", &.{ l, try p.andExpr() });
        }
        return l;
    }

    // Zig tip: `andExpr` relies on the same Zig feature as `routine` above: see the tip there.
    fn andExpr(p: *Parser) Error!*const Node {
        var l = try p.notExpr();
        while (p.isWord("and")) {
            const t = p.advance();
            l = try p.mk(.bin, t, "and", &.{ l, try p.notExpr() });
        }
        return l;
    }

    // Zig tip: a function may call itself: `not not x` is read by `notExpr` calling `notExpr`.
    // Recursion is how a grammar rule that contains itself (nested parentheses, `not not`) is
    // written; `return p.notExpr();` hands the result of the inner call straight back.
    fn notExpr(p: *Parser) Error!*const Node {
        if (p.isWord("not") and !p.isWordAt(1, "in")) {
            const t = p.advance();
            return p.mk(.un, t, "not", &.{try p.notExpr()});
        }
        return p.compare();
    }

    // Zig tip: an optional result `?[]const u8` lets one function both test and return: `compareOp`
    // answers "which comparison operator comes next, if any" and consumes it. `while (p.compareOp())
    // |op|` repeats while it returns a value. `==` on integers is a plain comparison; text needs `eql`.
    /// `== <> < > <= >= =~ !~ in, not in, is, is not` (a chain is accepted, left to right).
    fn compare(p: *Parser) Error!*const Node {
        var l = try p.range();
        while (p.compareOp()) |op| {
            l = try p.mk(.bin, op.tok, op.text, &.{ l, try p.range() });
        }
        return l;
    }

    // Zig tip: `compareOp` relies on the same Zig feature as `formatColon` above: see the tip there.
    fn compareOp(p: *Parser) ?struct { tok: Token, text: []const u8 } {
        const ops = [_][]const u8{ "==", "<>", "<=", ">=", "<", ">", "=~", "!~" };
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

    // Zig tip: `range` relies on the same Zig feature as `routine` above: see the tip there.
    /// `a..b  a..<b  a>..b  a>..<b`
    fn range(p: *Parser) Error!*const Node {
        const l = try p.additive();
        const ops = [_][]const u8{ "..", "..<", ">..", ">..<" };
        const t = p.peek();
        for (ops) |op| {
            if (p.acceptSym(op)) return p.mk(.range, t, op, &.{ l, try p.additive() });
        }
        return l;
    }

    // Zig tip: `additive` relies on the same Zig feature as `routine` above: see the tip there.
    fn additive(p: *Parser) Error!*const Node {
        var l = try p.multiplicative();
        while (p.isSym("+") or p.isSym("-") or p.isSym("||")) {
            const t = p.advance();
            l = try p.mk(.bin, t, t.text, &.{ l, try p.multiplicative() });
        }
        return l;
    }

    // Zig tip: `multiplicative` relies on the same Zig feature as `routine` above: see the tip
    // there.
    fn multiplicative(p: *Parser) Error!*const Node {
        var l = try p.unary();
        while (p.isSym("*") or p.isSym("/") or p.isSym("%") or p.isSym("&&") or p.isSym("><") or
            p.isSym("<<") or p.isSym(">>"))
        {
            const t = p.advance();
            l = try p.mk(.bin, t, t.text, &.{ l, try p.unary() });
        }
        return l;
    }

    // Zig tip: `unary` relies on the same Zig feature as `routine` above: see the tip there.
    fn unary(p: *Parser) Error!*const Node {
        if (p.isSym("-") or p.isSym("+")) {
            const t = p.advance();
            return p.mk(.un, t, t.text, &.{try p.unary()});
        }
        if (p.isWord("new")) {
            const t = p.advance();
            return p.mk(.new, t, "", &.{try p.postfix()});
        }
        return p.power();
    }

    // Zig tip: `power` relies on the same Zig feature as `routine` above: see the tip there.
    /// `^` binds tighter than `*` and goes right to left: `2 ^ 3 ^ 2` is `2 ^ (3 ^ 2)`.
    fn power(p: *Parser) Error!*const Node {
        const l = try p.postfix();
        if (p.isSym("^")) {
            const t = p.advance();
            return p.mk(.bin, t, "^", &.{ l, try p.unary() });
        }
        return l;
    }

    // Zig tip: `a.b`, `a[i]` and `a(x)` are "postfix" operations that can follow each other, so
    // they are a loop that wraps the node built so far. A call `(` may follow a name, a `)` or a
    // `]` but not a literal: `"x"(...)` is not a call, and the check also stops `print "a" (...)`
    // from being read as a call.
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
            } else if (callable and p.isSym("(")) {
                const open = p.peek();
                var kids: std.ArrayList(*const Node) = .empty;
                try kids.append(p.a, n);
                try p.items(")", &kids);
                n = try p.mk(.call, open, "", kids.items);
            } else break;
        }
        return n;
    }

    // Zig tip: `indexList` relies on the same Zig feature as `routine` above: see the tip there.
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

    // Zig tip: `item` relies on the same Zig feature as `routine` above: see the tip there.
    /// One element of a list, call or object: `expr`, `name: expr`, `x if c else y`, `@name`.
    fn item(p: *Parser) Error!*const Node {
        const k = try p.conditional();
        if (p.isSym(":")) {
            const t = p.advance();
            return p.mk(.pair, t, "", &.{ k, try p.conditional() });
        }
        return k;
    }

    // Zig tip: `conditional` relies on the same Zig feature as `routine` above: see the tip there.
    fn conditional(p: *Parser) Error!*const Node {
        if (p.isSym("@")) { // `@name` passes a variable by reference
            _ = p.advance();
            const name = try p.expectName("a variable name");
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

    // Zig tip: `items` relies on the same Zig feature as `routine` above: see the tip there.
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

    // Zig tip: `group` decides, after reading the items, what the brackets mean. `(`: one item and
    // no comma is plain grouping, otherwise a list. `[`: an array. `{`: a set, a map (the first
    // item is `key: value` with a literal key) or an object (an unquoted name as key). `|` after the
    // items makes a builder. `kids.items` is the slice of what was collected so far.
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

    // Zig tip: builtin functions start with `@`: they are the compiler's own, such as conversions
    // (`@intCast`, `@as`) and `@min`/`@max`.
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

    // Zig tip: `primary` relies on the same Zig feature as `routine` above: see the tip there.
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
                } else return p.fail("unexpected '{s}' in an expression", .{t.text});
            },
            .eof => return p.fail("unexpected end of file in an expression", .{}),
        }
    }

    // ---- statements -------------------------------------------------------------------------

    // Zig tip: `block_end.has(t.text)` asks a compile-time string set (see `reserved`) whether the
    // word ends the statement list. The loop leaves with `return` (success: the caller then
    // checks which word it is) or fails at the end of the file with a message.
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

    // Zig tip: `endSimple` relies on the same Zig feature as `routine` above: see the tip there.
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

    // Zig tip: `assignOp` relies on the same Zig feature as `formatColon` above: see the tip there.
    fn assignOp(p: *const Parser) ?[]const u8 {
        const ops = [_][]const u8{ ":=", "::", "+=", "-=", "*=", "/=", "%=", "^=" };
        for (ops) |op| {
            if (p.isSym(op)) return op;
        }
        return null;
    }

    /// `let a, b := value :Type;`, `let x = y = 1 :Integer;`, `let a :Type;`, `let p, *rest :: n;`
    // Zig tip: `p.acceptSym(":=") or p.acceptSym("::")` relies on short-circuit evaluation: the
    // second call runs only if the first returned false, and each call moves the cursor only
    // when it matches, so the `or` reads "one of these two symbols".
    fn declaration(p: *Parser) Error!*const Node {
        const kw = p.advance(); // let or set
        var targets: std.ArrayList(*const Node) = .empty;
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
                try targets.append(p.a, t);
            }
            if (!p.acceptSym(",")) break;
        }
        var op: []const u8 = "";
        var value: *const Node = p.noneNode();
        if (p.isSym(":=") or p.isSym("::")) {
            op = p.advance().text;
            value = try p.expr();
        } else if (p.isSym("=")) {
            _ = p.advance();
            op = "=";
            value = try p.expr();
            // `let x = y = 1`: every expression but the last is one more name
            while (p.acceptSym("=")) {
                if (value.tag != .name) return p.fail("expected a variable name before '='", .{});
                try targets.append(p.a, value);
                value = try p.expr();
            }
        }
        const tnode = try p.mk(.targets, kw, "", targets.items);
        const decl = try p.mk(if (std.mem.eql(u8, kw.text, "let")) .let else .set, kw, op, &.{ tnode, value });
        if (p.acceptSym(":")) decl.ty = try p.typeName();
        return p.endSimple(decl);
    }

    // Zig tip: `loopTail` relies on the same Zig feature as `routine` above: see the tip there.
    /// The common end of `while`, `for`: `block [else block] [then block] done ;`. Appends the
    /// body, else and then blocks (empty ones when absent) to `kids`.
    fn loopTail(p: *Parser, kids: *std.ArrayList(*const Node)) Error!void {
        const at = p.peek();
        try kids.append(p.a, try p.block());
        const empty = try p.mk(.block, at, "", &.{});
        try kids.append(p.a, if (p.acceptWord("else")) try p.block() else empty);
        try kids.append(p.a, if (p.acceptWord("then")) try p.block() else empty);
        try p.expectWord("done");
        try p.expectSym(";");
    }

    // Zig tip: `ifStatement` relies on the same Zig feature as `routine` above: see the tip there.
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

    // Zig tip: `matchStatement` relies on the same Zig feature as `routine` above: see the tip
    // there.
    fn matchStatement(p: *Parser) Error!*const Node {
        const kw = p.peek();
        try p.expectWord("match");
        const subject = try p.expr();
        if (!p.isWord("when")) return p.fail("expected 'when' but found '{s}'", .{describe(p.peek())});
        var whens: std.ArrayList(*const Node) = .empty;
        while (p.isWord("when")) {
            const w = p.advance();
            const pat = try p.expr();
            try p.expectWord("do");
            try whens.append(p.a, try p.mk(.when, w, "", &.{ pat, try p.block() }));
        }
        const then = if (p.acceptWord("then")) try p.block() else try p.mk(.block, kw, "", &.{});
        try p.expectWord("done");
        try p.expectSym(";");
        var kids: std.ArrayList(*const Node) = .empty;
        try kids.append(p.a, subject);
        try kids.append(p.a, then);
        try kids.appendSlice(p.a, whens.items);
        return p.mk(.match_, kw, "", kids.items);
    }

    // Zig tip: `std.mem.eql(u8, w, "let")` is how Zig compares text. A chain of `if` with early
    // `return` is a plain dispatch on the first word of the statement. `inline for` over a tuple
    // of `.{ word, tag }` pairs is unrolled by the compiler, so `tag` is a comptime-known enum
    // value, which `p.mk` needs for its `Tag` parameter.
    fn statement(p: *Parser) Error!*const Node {
        const t = p.peek();
        if (t.kind == .ident) {
            const w = t.text;
            if (std.mem.eql(u8, w, "let") or std.mem.eql(u8, w, "set")) return p.declaration();
            if (std.mem.eql(u8, w, "if")) return p.ifStatement();
            if (std.mem.eql(u8, w, "match")) return p.matchStatement();
            if (std.mem.eql(u8, w, "while")) {
                _ = p.advance();
                var kids: std.ArrayList(*const Node) = .empty;
                try kids.append(p.a, try p.mk(.block, t, "", &.{}));
                try kids.append(p.a, try p.expr());
                try p.expectWord("do");
                try p.loopTail(&kids);
                return p.mk(.while_, t, "", kids.items);
            }
            if (std.mem.eql(u8, w, "loop")) {
                _ = p.advance();
                var header: std.ArrayList(*const Node) = .empty;
                while (!p.isWord("while")) {
                    if (p.peek().kind == .eof) return p.fail("expected 'while' in the loop header", .{});
                    try header.append(p.a, try p.statement());
                }
                _ = p.advance();
                var kids: std.ArrayList(*const Node) = .empty;
                try kids.append(p.a, try p.mk(.block, t, "", header.items));
                try kids.append(p.a, try p.expr());
                try p.expectWord("do");
                try p.loopTail(&kids);
                return p.mk(.while_, t, "", kids.items);
            }
            if (std.mem.eql(u8, w, "for")) {
                _ = p.advance();
                var kids: std.ArrayList(*const Node) = .empty;
                try kids.append(p.a, try p.postfix());
                try p.expectWord("in");
                try kids.append(p.a, try p.expr());
                try p.expectWord("do");
                try p.loopTail(&kids);
                return p.mk(.for_, t, "", kids.items);
            }
            if (!reserved.has(w) and p.isSymAt(1, ":") and p.isWordAt(2, "job")) {
                _ = p.advance();
                _ = p.advance();
                _ = p.advance();
                try p.expectWord("do");
                const body = try p.block();
                try p.expectWord("done");
                const label = try p.expectName("the job label");
                if (!std.mem.eql(u8, label.text, w)) {
                    p.i -= 1;
                    return p.fail("'done {s}' does not match the job '{s}'", .{ label.text, w });
                }
                try p.expectSym(";");
                return p.mk(.job, t, w, &.{body});
            }
            inline for (.{
                .{ "break", Tag.break_stmt },
                .{ "next", Tag.next_stmt },
                .{ "over", Tag.over_stmt },
                .{ "panic", Tag.panic_stmt },
                .{ "retry", Tag.retry_stmt },
                .{ "resume", Tag.resume_stmt },
                .{ "abort", Tag.abort_stmt },
            }) |pair| {
                if (std.mem.eql(u8, w, pair[0])) {
                    _ = p.advance();
                    return p.endSimple(try p.mk(pair[1], t, "", &.{}));
                }
            }
            inline for (.{
                .{ "print", Tag.print_stmt },
                .{ "write", Tag.write_stmt },
                .{ "expect", Tag.expect_stmt },
                .{ "raise", Tag.raise_stmt },
            }) |pair| {
                if (std.mem.eql(u8, w, pair[0])) {
                    _ = p.advance();
                    if (!p.isSym(";") and !p.isWord("if")) {
                        return p.endSimple(try p.mk(pair[1], t, "", &.{try p.expr()}));
                    }
                    return p.endSimple(try p.mk(pair[1], t, "", &.{}));
                }
            }
            if (reserved.has(w)) {
                return p.fail("unexpected '{s}', expected a statement", .{w});
            }
        }
        const e = try p.expr();
        if (p.assignOp()) |op| {
            const at = p.advance();
            return p.endSimple(try p.mk(.assign, at, op, &.{ e, try p.expr() }));
        }
        return p.endSimple(try p.mk(.expr_stmt, t, "", &.{e}));
    }

    // ---- declarations -----------------------------------------------------------------------

    // Zig tip: `process` relies on the same Zig feature as `routine` above: see the tip there.
    fn process(p: *Parser) Error!*const Node {
        const kw = p.peek();
        try p.expectWord("process");
        const name = try p.expectName("a process name");
        try p.expectWord("is");
        const body = try p.block();
        const recover = if (p.acceptWord("recover")) try p.block() else p.noneNode();
        const finalize = if (p.acceptWord("finalize")) try p.block() else p.noneNode();
        try p.expectWord("return");
        try p.expectSym(";");
        return p.mk(.process, kw, name.text, &.{ body, recover, finalize });
    }

    // Zig tip: `class` relies on the same Zig feature as `routine` above: see the tip there.
    fn class(p: *Parser) Error!*const Node {
        const kw = p.peek();
        try p.expectWord("class");
        const name = try p.expectName("a class name");
        try p.expectSym("=");
        try p.expectSym("{");
        var members: std.ArrayList(*const Node) = .empty;
        if (!p.isSym("}")) {
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
        try p.expectSym("}");
        var kids: std.ArrayList(*const Node) = .empty;
        try kids.append(p.a, try p.mk(.block, kw, "", members.items));
        if (p.acceptSym("<:")) {
            const parent = try p.expectName("a parent class name");
            try kids.append(p.a, try p.mk(.name, parent, parent.text, &.{}));
        } else try kids.append(p.a, p.noneNode());
        if (p.acceptSym(";")) return p.mk(.class, kw, name.text, kids.items);
        try p.expectWord("is");
        while (!p.isWord("end")) {
            if (p.isWord("constructor")) {
                try kids.append(p.a, try p.routine(.constructor));
            } else if (p.isWord("method")) {
                try kids.append(p.a, try p.routine(.method));
            } else if (p.isWord("function")) {
                try kids.append(p.a, try p.routine(.function));
            } else return p.fail("unexpected '{s}' in the class, expected a constructor or a method", .{describe(p.peek())});
        }
        try p.expectWord("end");
        const end_name = try p.expectName("the class name");
        if (!std.mem.eql(u8, name.text, end_name.text)) {
            p.i -= 1;
            return p.fail("'end {s}' does not match 'class {s}'", .{ end_name.text, name.text });
        }
        try p.expectSym(";");
        return p.mk(.class, kw, name.text, kids.items);
    }

    // Zig tip: `declarationInDriver` relies on the same Zig feature as `peek` above: see the tip
    // there.
    fn declarationInDriver(p: *Parser) Error!*const Node {
        if (p.isWord("let") or p.isWord("set")) return p.declaration();
        if (p.isWord("class")) return p.class();
        if (p.isWord("function")) return p.routine(.function);
        if (p.isWord("method")) return p.routine(.method);
        if (p.isWord("process")) return p.process();
        return p.fail("unexpected '{s}' in the driver, expected a declaration or 'end'", .{describe(p.peek())});
    }

    // Zig tip: `driver` relies on the same Zig feature as `routine` above: see the tip there.
    fn driver(p: *Parser) Error!*const Node {
        const kw = p.peek();
        try p.expectWord("driver");
        const name = try p.expectName("a driver name");
        try p.expectWord("is");
        var decls: std.ArrayList(*const Node) = .empty;
        while (!p.isWord("end")) try decls.append(p.a, try p.declarationInDriver());
        try p.expectWord("end");
        const end_name = try p.expectName("the driver name");
        if (!std.mem.eql(u8, name.text, end_name.text)) {
            p.i -= 1; // report at the name after `end`
            return p.fail("'end {s}' does not match 'driver {s}'", .{ end_name.text, name.text });
        }
        try p.expectSym(";");
        return p.mk(.driver, kw, name.text, decls.items);
    }

    // Zig tip: `script` relies on the same Zig feature as `routine` above: see the tip there.
    fn script(p: *Parser) Error!*const Node {
        const at = p.peek();
        var result: *const Node = undefined;
        if (p.isWord("driver")) {
            result = try p.driver();
        } else {
            var list: std.ArrayList(*const Node) = .empty;
            while (p.peek().kind != .eof) try list.append(p.a, try p.statement());
            result = try p.mk(.script, at, "", list.items);
        }
        if (p.peek().kind != .eof) return p.fail("unexpected '{s}' after the end of the driver", .{describe(p.peek())});
        return result;
    }
};

// Zig tip: `pub fn` makes a function visible to other files. The caller passes an arena (see
// `std.heap.ArenaAllocator`): the tokens and every node are allocated from it and freed together
// when the caller drops the arena, which is why the nodes can point at each other freely and
// at the source text (tokens are views into `src`, so `src` must outlive the tree).
/// Parse `src` into a tree. On a syntax error returns `error.Syntax` and fills `diag`.
pub fn parse(arena: std.mem.Allocator, src: []const u8, diag: *Diag) Error!*const Node {
    const toks = try lexer.tokenize(arena, src, diag);
    var p: Parser = .{ .toks = toks, .diag = diag, .a = arena };
    return p.script();
}

// Zig tip: `std.heap.ArenaAllocator.init(gpa)` makes an arena on top of another allocator;
// `defer arena.deinit()` frees every allocation at once. `check` parses only to learn whether
// the script is correct, then drops the tree.
/// Check the script `src`. On a syntax error returns `error.Syntax` and fills `diag`.
pub fn check(gpa: std.mem.Allocator, src: []const u8, diag: *Diag) Error!void {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    _ = try parse(arena.allocator(), src, diag);
}

// Zig tip: `expectError` checks that a call fails with that exact error; after it the test reads
// the `Diag` to check the message and the position.
test "a minimal driver parses" {
    var d: Diag = .{};
    try check(std.testing.allocator,
        \\# test
        \\driver a01_driver is
        \\  process main is
        \\    over;
        \\  return;
        \\end a01_driver;
        \\** trailing comment
    , &d);
}

// Zig tip: a `test` block runs under `zig build test`; `try std.testing.expect...` fails it when the
// value is not the expected one.
test "errors are reported with a position" {
    var d: Diag = .{};
    try std.testing.expectError(error.Syntax, check(std.testing.allocator,
        \\driver a is
        \\  process main is
        \\    over
        \\  return;
        \\end a;
    , &d));
    try std.testing.expectEqual(@as(u32, 4), d.line);
    try std.testing.expectEqualStrings("expected ';' but found 'return'", d.message());

    try std.testing.expectError(error.Syntax, check(std.testing.allocator, "driver a is process m is return; end b;", &d));
    try std.testing.expectEqualStrings("'end b' does not match 'driver a'", d.message());
}

// Zig tip: `a free script and expressions parse` relies on the same Zig feature as `errors are
// reported with a position` above: see the tip there.
test "a free script and expressions parse" {
    var d: Diag = .{};
    try check(std.testing.allocator,
        \\#!/usr/bin/env eve
        \\print "Hello";
        \\let a := 2 ^ 3 ^ 2;
        \\a += (1, 2, 3)[$ - 1];
        \\expect (x | x in (1..5)) == (1, 2, 3, 4, 5);
    , &d);
}

// Zig tip: a table of scripts that must be rejected, checked in a loop: `for (bad) |src| { ... }`.
// `expectError` fails the test if the call succeeds, so each entry proves the parser says no.
test "wrong scripts are rejected" {
    const bad = [_][]const u8{
        "let := 1;",
        "let a := ;",
        "print 1 +;",
        "if x do print 1;",
        "while True do print 1; done",
        "driver a is process m is let x := (1, 2; return; end a;",
        "driver a is end b;",
        "for i (1..2) do done;",
        "x := 1 2;",
    };
    var d: Diag = .{};
    for (bad) |src| try std.testing.expectError(error.Syntax, check(std.testing.allocator, src, &d));
}
