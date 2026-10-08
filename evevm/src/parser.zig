//! Parser: turns the tokens of a script into a syntax tree (see ast.zig) following the Eve grammar
//! (spec/syntax). On a syntax error it stops at the first one and says where.
//!
//! Grammar implemented so far (derived from test/level1; it grows test by test):
//!
//!     script     = driver | aspect | { statement }             (a script without a driver is "free")
//!     aspect     = ("exclusive" | "concurrent") "aspect" name "is" { declaration } "end" name ";"   (one process, main)
//!     apply      = "apply" name { "/" name } "(" [ arguments ] ")" ";"
//!     driver     = "driver" name "is" { declaration } "end" name ";"
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
const ast = @import("ast.zig");
const checker = @import("check.zig");

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
    .{"driver"},      .{"is"},        .{"process"},   .{"return"},    .{"end"},       .{"new"},     .{"set"},
    .{"let"},         .{"if"},        .{"else"},      .{"do"},        .{"done"},      .{"while"},   .{"loop"},
    .{"for"},         .{"in"},        .{"match"},     .{"when"},      .{"then"},      .{"break"},   .{"skip"},
    .{"raise"},       .{"recover"},   .{"finalize"},  .{"job"},       .{"retry"},     .{"resume"},  .{"abort"},
    .{"over"},        .{"exit"},      .{"stop"},      .{"pass"},      .{"panic"},     .{"print"},   .{"write"},
    .{"expect"},      .{"assert"},    .{"defer"},     .{"class"},     .{"function"},  .{"procedure"}, .{"method"},
    .{"constructor"}, .{"public"},    .{"protected"}, .{"private"},   .{"and"},       .{"or"},      .{"xor"},
    .{"not"},         .{"repeat"},    .{"eq"},        .{"apply"},     .{"aspect"},    .{"exclusive"}, .{"concurrent"},
});

/// Words that end a block: a statement list stops in front of them.
const block_end = std.StaticStringMap(void).initComptime(.{
    .{"return"}, .{"recover"}, .{"finalize"}, .{"done"}, .{"else"}, .{"then"}, .{"when"}, .{"end"}, .{"repeat"},
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
    // the function with `return`. A function that returns `?T` says "maybe nothing" in its type.
    /// The code point of a placeholder `{U+H...}` (the text between the braces), or null when the
    /// text is not of that form.
    fn codePointPlaceholder(inner: []const u8) ?u21 {
        if (inner.len < 3 or inner[0] != 'U' or inner[1] != '+') return null;
        return std.fmt.parseInt(u21, inner[2..], 16) catch null;
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
    // loop walks the raw bytes by index because an escape takes several of them. `parts` collects
    // the pieces of a string with placeholders. A string that starts with `/` is a regular
    // expression: raw, no escapes and no placeholders, only `\"` (D-097). In any other string a
    // `{` opens a placeholder `{name}` or `{name % format}` (D-102); `\{` and `\}` are literal
    // braces, and a brace that opens no valid placeholder is an error.
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
                if (codePointPlaceholder(inner)) |cp| {
                    try p.appendCodePoint(&cur, cp);
                    i = close + 1;
                    continue;
                }
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

    // Zig tip: a function can answer "did it apply?" with a `bool` and still change what it was
    // given through a pointer: `out` receives the character. `&#955;` and `&#x3BB;` name a code
    // point; `&amp;`, `&lt;`, `&gt;`, `&quot;` and `&apos;` name the five marked characters.
    /// A character reference `&...;` (the text between `&` and `;`): append it and say so, or say no.
    fn reference(p: *Parser, out: *std.ArrayList(u8), name: []const u8) Error!bool {
        if (name.len > 1 and name[0] == '#') {
            const hex = name[1] == 'x' or name[1] == 'X';
            const digits = if (hex) name[2..] else name[1..];
            const cp = std.fmt.parseInt(u21, digits, if (hex) 16 else 10) catch return false;
            try p.appendCodePoint(out, cp);
            return true;
        }
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

    // Zig tip: an argument of `print` is an expression, or `name: expression` (`sep: " "`). A plain
    // `expr` is used, not `conditional`, so a trailing `if` stays the condition of the statement.
    fn printArg(p: *Parser) Error!*const Node {
        const k = try p.expr();
        if (p.isSym(":")) {
            const t = p.advance();
            return p.mk(.pair, t, "", &.{ k, try p.expr() });
        }
        return k;
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
    /// Index of the `%` that starts the format of a placeholder: the first one outside brackets.
    fn formatPercent(inner: []const u8) ?usize {
        var depth: usize = 0;
        for (inner, 0..) |c, j| {
            switch (c) {
                '(', '[', '{' => depth += 1,
                ')', ']', '}' => depth -|= 1,
                '%' => if (depth == 0) return j,
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
        return p.mk(.text_lit, t, try out.toOwnedSlice(p.a), &.{});
    }

    // ---- types, parameters ------------------------------------------------------------------

    // Zig tip: a `while (true)` loop with `break` is the usual way to write "repeat until a
    // condition found inside". `if (!p.acceptSym(",")) break;` reads: no comma, the list is over.
    // `std.ArrayList(T).empty` starts an empty list; `append(allocator, x)` adds; `.items` is the
    // slice of what it holds. `std.fmt.allocPrint(a, "...", args)` builds a new string in the arena.
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
        const suffix: []const u8 = if (p.acceptSym("?")) "?" else "";
        const text = if (prefix.len == 0 and suffix.len == 0) name.text else try std.fmt.allocPrint(p.a, "{s}{s}{s}", .{ prefix, name.text, suffix });
        return p.mk(.type, name, text, dims.items);
    }

    // Zig tip: `@constCast` removes `const` from a pointer. The nodes are shared as `*const Node`
    // once the tree is built, but while a parameter list is being read the parser may still give
    // a type to the parameters that came before it: `a, b: Integer` gives `Integer` to `a` and `b`.
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

    // Zig tip: `if (a) b else c` is an expression too. A subprogram has one parameter list (D-029) and
    // an optional result list after `=>`. A `function` must have results and a `procedure` must not
    // (D-100); a procedure is never deterministic, so its name does not end with `!` (D-101).
    /// `function|procedure|method|constructor name [(params)] [=> (results)] is block return ;`.
    fn routine(p: *Parser, tag: Tag) Error!*const Node {
        const kw = p.advance();
        const name = if (tag == .constructor) kw else try p.expectName("a name");
        const empty = try p.mk(.params, kw, "", &.{});
        const first = if (p.isSym("(")) try p.params() else empty;
        const has_results = p.isSym("=>");
        const results = if (p.acceptSym("=>")) try p.params() else empty;
        if (tag == .procedure and has_results) return p.failAt(kw, "a procedure has no result list (use function)", .{});
        if (tag == .function and !has_results) return p.failAt(kw, "a function must have a result list '=> (@r: Type)' (use procedure)", .{});
        if (tag == .procedure and name.text[name.text.len - 1] == '!') return p.failAt(name, "a procedure can't end with '!' (D-101)", .{});
        try p.expectWord("is");
        const body = try p.block();
        try p.expectWord("return");
        try p.expectSym(";");
        return p.mk(tag, kw, if (tag == .constructor) "" else name.text, &.{ first, empty, results, body });
    }

    // ---- expressions ------------------------------------------------------------------------

    // Zig tip: `const t = p.peek();` before building a node keeps the token of the operator for the
    // line number. `p.mk(.bin, t, t.text, &.{ l, r })` is a binary node. The loop `while (cond) { l = ... }`
    // rebinds `l` (a `var`) so `a - b - c` becomes `(a - b) - c`: left to right.
    fn expr(p: *Parser) Error!*const Node {
        var l = try p.orExpr();
        while (p.isSym("<+") or p.isSym("+>") or p.isSym("<-") or p.isSym("->")) {
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

    // Zig tip: `range` relies on the same Zig feature as `routine` above: see the tip there.
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
        var l = try p.power();
        while (p.isSym("*") or p.isSym("/") or p.isSym("%") or p.isSym("&&") or p.isSym("><") or
            p.isSym("<<") or p.isSym(">>"))
        {
            const t = p.advance();
            l = try p.mk(.bin, t, t.text, &.{ l, try p.power() });
        }
        return l;
    }

    // Zig tip: the unary minus is read before the power: `-2 ^ 2` is `(-2) ^ 2`, 4 (Q-030, the
    // grammar of spec/syntax/grammar.md). `unary` calls itself for `- - x` and falls to `postfix`.
    fn unary(p: *Parser) Error!*const Node {
        if (p.isSym("-") or p.isSym("+")) {
            const t = p.advance();
            return p.mk(.un, t, t.text, &.{try p.unary()});
        }
        return p.postfix();
    }

    // Zig tip: `power` relies on the same Zig feature as `unary` above: see the tip there.
    /// `^` goes right to left: `2 ^ 3 ^ 2` is `2 ^ (3 ^ 2)`.
    fn power(p: *Parser) Error!*const Node {
        const l = try p.unary();
        if (p.isSym("^")) {
            const t = p.advance();
            return p.mk(.bin, t, "^", &.{ l, try p.power() });
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
        if (p.isSym("*") and !p.isSymAt(1, ")") and !p.isSymAt(1, ",")) { // `*list` spreads a list into the arguments
            const star = p.advance();
            return p.mk(.spread, star, "", &.{try p.expr()});
        }
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
                } else if (p.isSym("?")) {
                    _ = p.advance();
                    return p.mk(.open_end, t, "", &.{});
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

    /// `new a, b := value :Type;`, `new x = y = 1 :Integer;`, `new a :Type;`, `new p, *rest :: n;`,
    /// `new e <- list;` and the constants `set A = 1;` (D-076).
    // Zig tip: `p.acceptSym(":=") or p.acceptSym("::")` relies on short-circuit evaluation: the
    // second call runs only if the first returned false, and each call moves the cursor only
    // when it matches, so the `or` reads "one of these two symbols".
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

    // Zig tip: a function can return early with `return` as soon as it knows the answer; here each
    // `if` handles one shape of the `let` statement and leaves. In `let lst -> e;` the list is on
    // the left and the target on the right; in `let e <- lst;` the target is on the left. For
    // `let x +> lst;` the target is the list on the right: the node keeps source order, the
    // interpreter knows which side is which (D-107).
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

    // Zig tip: a loop with a label closes with `done label;` and a loop without one with `done;`
    // (D-034). The label is kept in the text of the node so `break label` and `skip label` can find it.
    /// The common end of `while`, `for`: `block [else block] [then block] done [label] ;`. Appends the
    /// body, else and then blocks (empty ones when absent) to `kids`.
    fn loopTail(p: *Parser, kids: *std.ArrayList(*const Node), label: []const u8) Error!void {
        const at = p.peek();
        try kids.append(p.a, try p.block());
        const empty = try p.mk(.block, at, "", &.{});
        try kids.append(p.a, if (p.acceptWord("else")) try p.block() else empty);
        try kids.append(p.a, if (p.acceptWord("then")) try p.block() else empty);
        try p.expectWord("done");
        try p.closeLabel(label);
    }

    // Zig tip: `closeLabel` checks the name after `done`: it must repeat the label of the block.
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

    // Zig tip: `whileLoop`, `forLoop` and `loopBlock` are the three loops of D-074. Each one
    // takes the label that was written before it (empty when there is none).
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
        const then = if (p.acceptWord("then")) try p.block() else try p.mk(.block, kw, "", &.{});
        try p.expectWord("done");
        try p.closeLabel(label);
        var kids: std.ArrayList(*const Node) = .empty;
        try kids.append(p.a, subject);
        try kids.append(p.a, then);
        try kids.appendSlice(p.a, whens.items);
        return p.mk(.match_, kw, try std.fmt.allocPrint(p.a, "{s}:{s}", .{ mode, label }), kids.items);
    }

    // Zig tip: `std.mem.eql(u8, w, "let")` is how Zig compares text. A chain of `if` with early
    // `return` is a plain dispatch on the first word of the statement. `inline for` over a tuple
    // of `.{ word, tag }` pairs is unrolled by the compiler, so `tag` is a comptime-known enum
    // value, which `p.mk` needs for its `Tag` parameter.
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
            // a function declared inside a function or a procedure is a closure (D-101)
            if (std.mem.eql(u8, w, "function")) return p.routine(.function);
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

    // Zig tip: `process` relies on the same Zig feature as `routine` above: see the tip there.
    fn process(p: *Parser) Error!*const Node {
        const kw = p.peek();
        try p.expectWord("process");
        const name = try p.expectName("a process name");
        const prm = if (p.isSym("(")) try p.params() else try p.mk(.params, kw, "", &.{});
        try p.expectWord("is");
        const body = try p.block();
        const recover = if (p.acceptWord("recover")) try p.block() else p.noneNode();
        const finalize = if (p.acceptWord("finalize")) try p.block() else p.noneNode();
        try p.expectWord("return");
        try p.expectSym(";");
        return p.mk(.process, kw, name.text, &.{ body, recover, finalize, prm });
    }

    // Zig tip: the signature of a callback is a class with no members: `class BinEx = (p1, p2 :Integer):
    // Integer <: Function;`. `params()` reads the parenthesized list, an optional `: Type` is the
    // result, and the node is a `class` whose member block is empty and whose parent is `Function`.
    /// `class Name = (params) [: Type] <: Function;` (callbacks.html).
    fn functionType(p: *Parser, kw: Token, name: []const u8) Error!*const Node {
        _ = try p.params();
        if (p.acceptSym(":")) _ = try p.typeName();
        try p.expectSym("<:");
        const parent = try p.expectName("a parent class name");
        try p.expectSym(";");
        return p.mk(.class, kw, name, &.{ try p.mk(.block, kw, "", &.{}), try p.mk(.name, parent, parent.text, &.{}) });
    }

    // Zig tip: `class` relies on the same Zig feature as `routine` above: see the tip there.
    fn class(p: *Parser) Error!*const Node {
        const kw = p.peek();
        try p.expectWord("class");
        const name = try p.expectName("a class name");
        try p.expectSym("=");
        if (p.isSym("(")) return p.functionType(kw, name.text);
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
            const public = p.acceptWord("public");
            if (!public and (p.isWord("private") or p.isWord("protected"))) _ = p.advance();
            const first_member = kids.items.len;
            if (p.isWord("procedure")) {
                return p.fail("a class hosts functions and methods, not procedures (D-103)", .{});
            } else if (p.isWord("constructor")) {
                try kids.append(p.a, try p.routine(.constructor));
            } else if (p.isWord("method")) {
                try kids.append(p.a, try p.routine(.method));
            } else if (p.isWord("function")) {
                try kids.append(p.a, try p.routine(.function));
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
        return p.mk(.class, kw, name.text, kids.items);
    }

    // Zig tip: `declarationInDriver` relies on the same Zig feature as `peek` above: see the tip
    // there.
    fn declarationInDriver(p: *Parser) Error!*const Node {
        if (p.isWord("new") or p.isWord("set")) return p.declaration();
        if (p.isWord("class")) return p.class();
        if (p.isWord("function")) return p.routine(.function);
        if (p.isWord("procedure")) return p.routine(.procedure);
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

    // Zig tip: `std.ArrayList(u8)` is a growable text buffer: `appendSlice` adds a piece and `.items`
    // is the finished slice. The path of an aspect is built here, name by name, from the tokens
    // `folder`, `/`, `name`, so `apply tools/hello()` keeps its folder in `text`.
    /// `apply path(args);`: run an aspect. The parentheses are always written (processing.html).
    fn applyStatement(p: *Parser) Error!*const Node {
        const kw = p.advance();
        var path: std.ArrayList(u8) = .empty;
        try path.appendSlice(p.a, (try p.expectName("an aspect name")).text);
        while (p.acceptSym("/")) {
            try path.append(p.a, '/');
            try path.appendSlice(p.a, (try p.expectName("a name after '/'")).text);
        }
        if (!p.isSym("(")) return p.fail("expected '(' after 'apply {s}': the parentheses are always written", .{path.items});
        var args: std.ArrayList(*const Node) = .empty;
        try p.items(")", &args);
        return p.endSimple(try p.mk(.apply_stmt, kw, path.items, args.items));
    }

    // Zig tip: a rule can be checked after it is parsed: the aspect is read like a driver, then the
    // list of declarations is searched for its process. `return p.fail(...)` reports at the token
    // under the cursor, so `p.i -= 1` first moves it back onto the name after `end`.
    /// `exclusive aspect name is … end name;`: a driver-shaped script with exactly one process, `main`.
    fn aspect(p: *Parser) Error!*const Node {
        const kw = p.peek();
        const kind: []const u8 = if (p.isWord("exclusive") or p.isWord("concurrent")) p.advance().text else "";
        if (!p.isWord("aspect")) return p.fail("expected 'aspect' after '{s}'", .{kind});
        if (kind.len == 0) return p.fail("an aspect is declared 'exclusive aspect' or 'concurrent aspect' (D-090)", .{});
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
        var processes: usize = 0;
        for (decls.items) |d| if (d.tag == .process) {
            processes += 1;
            if (!std.mem.eql(u8, d.text, "main")) {
                p.diag.set(d.line, d.col, "the process of an aspect is named main, not '{s}' (D-066)", .{d.text});
                return error.Syntax;
            }
        };
        if (processes != 1) {
            p.diag.set(name.line, name.col, "an aspect has exactly one process, named main (D-066)", .{});
            return error.Syntax;
        }
        try p.expectSym(";");
        return p.mk(.aspect, kw, name.text, decls.items);
    }

    // Zig tip: `script` relies on the same Zig feature as `routine` above: see the tip there.
    fn script(p: *Parser) Error!*const Node {
        const at = p.peek();
        var result: *const Node = undefined;
        if (p.isWord("driver")) {
            result = try p.driver();
        } else if (p.isWord("exclusive") or p.isWord("concurrent") or p.isWord("aspect")) {
            result = try p.aspect();
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
    const tree = try p.script();
    try checker.check(arena, tree, diag);
    return tree;
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
        \\new a := 2 ^ 3 ^ 2;
        \\let a += (1, 2, 3)[$ - 1];
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
        "loop do print 1; done;",
        "loop do print 1; repeat while;",
    };
    var d: Diag = .{};
    for (bad) |src| try std.testing.expectError(error.Syntax, check(std.testing.allocator, src, &d));
}

// Zig tip: one test can hold the good and the bad cases of a rule. The first `try check(...)` must
// succeed (an error would fail the test through `try`); the list of bad scripts must all fail with
// `error.Syntax`. Here: an aspect needs its kind word and exactly one process named main, and an
// aspect can't `apply` (D-066, D-090).
test "an aspect and an apply parse, and the aspect rules hold" {
    var d: Diag = .{};
    try check(std.testing.allocator, "exclusive aspect a is process main(x: Integer, @y: Integer) is let y := x; return; end a;", &d);
    try check(std.testing.allocator, "concurrent aspect a is process main is return; end a;", &d);
    try check(std.testing.allocator, "driver t is process main is new r :Integer; apply tools/a(1, v: 2, @r, *(3, 4)); return; end t;", &d);
    const bad = [_][]const u8{
        "aspect a is process main is return; end a;",
        "exclusive aspect a is process other is return; end a;",
        "exclusive aspect a is function f() => (@r: Integer) is return; end a;",
        "exclusive aspect a is process main is return; process main is return; end a;",
        "exclusive aspect a is process main is apply b(); return; end a;",
        "driver t is process main is apply b; return; end t;",
    };
    for (bad) |src| try std.testing.expectError(error.Syntax, check(std.testing.allocator, src, &d));
}
