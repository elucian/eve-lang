//! @eve-module parser.literals
//! @spec spec/syntax/grammar.md
//! @feature F-VM-01
//! @decision D-179
//! @see code/evecp/src/parser.zig:Parser
//! Strings, interpolation, characters and text literals.
const std = @import("std");
const lexer = @import("../lexer.zig");
const ast = @import("evecm").ast;
const Token = lexer.Token;
const Node = ast.Node;
const Diag = lexer.Diag;
const Error = lexer.Error;
const Parser = @import("../parser.zig").Parser;

pub fn appendCodePoint(p: *Parser, out: *std.ArrayList(u8), cp: u21) Error!void {
    var buf: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(cp, &buf) catch return p.fail("invalid Unicode code point", .{});
    try out.appendSlice(p.a, buf[0..n]);
}

/// The character an escape letter stands for, or null when the letter is not a simple escape.
pub fn simpleEscape(c: u8) ?u8 {
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
pub fn charNode(p: *Parser, t: Token) Error!*Node {
    var out: std.ArrayList(u8) = .empty;
    if (t.text[0] == 'U') {
        const cp = std.fmt.parseInt(u21, t.text[2..], 16) catch return p.fail("bad symbol literal", .{});
        try p.appendCodePoint(&out, cp);
    } else {
        const raw = t.text[1 .. t.text.len - 1];
        if (raw.len >= 2 and raw[0] == '\\') {
            const c = Parser.simpleEscape(raw[1]) orelse return p.failAt(t, "bad escape sequence \\{c}", .{raw[1]});
            try out.append(p.a, c);
        } else try out.appendSlice(p.a, raw);
    }
    const one = std.unicode.utf8CountCodepoints(out.items) catch 0;
    if (out.items.len == 0 and t.text.len == 2) return p.mk(.chr, t, "", &.{}); // '' is nil, the empty rune
    if (one != 1) return p.failAt(t, "a symbol literal holds exactly one character (use \"...\" for text)", .{});
    return p.mk(.chr, t, try out.toOwnedSlice(p.a), &.{});
}

/// Parse the text of an interpolation `\s{...}` as an expression.
pub fn subExpr(p: *Parser, text: []const u8, at: Token) Error!*const Node {
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
pub fn stringNode(p: *Parser, t: Token) Error!*const Node {
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
            const close = Parser.matchBrace(raw, i) orelse return p.failAt(t, "unclosed placeholder: write \\{{ for a brace", .{});
            const inner = raw[i + 1 .. close];
            const pct = Parser.formatPercent(inner);
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
        } else if (Parser.simpleEscape(e)) |ch| {
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
pub fn reference(p: *Parser, out: *std.ArrayList(u8), name: []const u8) Error!bool {
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

pub fn printArg(p: *Parser) Error!*const Node {
    const k = try p.expr();
    if (p.isSym(":")) {
        const t = p.advance();
        return p.mk(.pair, t, "", &.{ k, try p.expr() });
    }
    return k;
}

/// Index of the `}` that closes the `{` at `raw[open]`.
pub fn matchBrace(raw: []const u8, open: usize) ?usize {
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
pub fn formatPercent(inner: []const u8) ?usize {
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
pub fn textLiteral(p: *Parser, t: Token) Error!*const Node {
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
