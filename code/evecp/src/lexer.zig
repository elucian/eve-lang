//! @eve-module lexer
//! @spec spec/lexical/lexical.md
//! @feature F-VM-01, F-SPEC-01
//! @decision D-011, D-014
//! @tests test/level1
//! Lexer: turns the text of an Eve script into tokens (spec/lexical/lexical.md).
//!
//! Comments are skipped here, the parser never sees them: `#` or `##` at column 0 and `**` run to
//! the end of the line, `(** ... **)` and `/* ... */` run to their closing marker (no nesting).
const std = @import("std");

pub const Kind = enum { ident, number, string, char, symbol, eof };

pub const Token = struct {
    kind: Kind,
    text: []const u8,
    /// Line and column of the first character, both counted from 1.
    line: u32,
    col: u32,
};

/// Where and why a script is wrong. The lexer and the parser both fill it.
pub const Diag = struct {
    line: u32 = 0,
    col: u32 = 0,
    buf: [160]u8 = undefined,
    len: usize = 0,

    pub fn set(d: *Diag, line: u32, col: u32, comptime fmt: []const u8, args: anytype) void {
        d.line = line;
        d.col = col;
        d.len = (std.fmt.bufPrint(&d.buf, fmt, args) catch @as([]u8, &d.buf)).len;
    }

    pub fn message(d: *const Diag) []const u8 {
        return d.buf[0..d.len];
    }
};

pub const Error = error{ Syntax, OutOfMemory };

fn isIdentStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

fn isIdentChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

const Lexer = struct {
    src: []const u8,
    pos: usize = 0,
    line: u32 = 1,
    /// Index in `src` of the first character of the current line.
    line_start: usize = 0,
    diag: *Diag,

    fn at(lx: *const Lexer, offset: usize) u8 {
        const i = lx.pos + offset;
        return if (i < lx.src.len) lx.src[i] else 0;
    }

    fn col(lx: *const Lexer) u32 {
        return @intCast(lx.pos - lx.line_start + 1);
    }

    fn skipToEndOfLine(lx: *Lexer) void {
        while (lx.pos < lx.src.len and lx.src[lx.pos] != '\n') lx.pos += 1;
    }

    /// Skip blanks and comments. An unterminated block comment is the only thing that can fail.
    fn skipBlanks(lx: *Lexer) Error!void {
        while (lx.pos < lx.src.len) {
            const c = lx.src[lx.pos];
            if (c == '\n') {
                lx.pos += 1;
                lx.line += 1;
                lx.line_start = lx.pos;
            } else if (c == ' ' or c == '\t' or c == '\r') {
                lx.pos += 1;
            } else if (c == '#' and lx.pos == lx.line_start) {
                lx.skipToEndOfLine();
            } else if (c == '*' and lx.at(1) == '*') {
                lx.skipToEndOfLine();
            } else if (c == '/' and lx.at(1) == '*') {
                try lx.skipBlock("*/", "block comment");
            } else if (c == '(' and lx.at(1) == '*' and lx.at(2) == '*') {
                try lx.skipBlock("**)", "expression comment");
            } else return;
        }
    }

    fn skipBlock(lx: *Lexer, close: []const u8, what: []const u8) Error!void {
        const start_line = lx.line;
        const start_col = lx.col();
        const end = std.mem.indexOf(u8, lx.src[lx.pos + 2 ..], close) orelse {
            lx.diag.set(start_line, start_col, "unterminated {s}, '{s}' not found", .{ what, close });
            return error.Syntax;
        };
        const stop = lx.pos + 2 + end + close.len;
        while (lx.pos < stop) : (lx.pos += 1) {
            if (lx.src[lx.pos] == '\n') {
                lx.line += 1;
                lx.line_start = lx.pos + 1;
            }
        }
    }

    fn token(lx: *const Lexer, kind: Kind, start: usize, line: u32, column: u32) Token {
        return .{ .kind = kind, .text = lx.src[start..lx.pos], .line = line, .col = column };
    }

    // @decision D-095
    fn digits(lx: *Lexer) void {
        while (std.ascii.isDigit(lx.at(0))) lx.pos += 1;
    }

    fn number(lx: *Lexer) void {
        if (lx.at(0) == '0' and (lx.at(1) == 'x' or lx.at(1) == 'b')) {
            lx.pos += 2;
            while (std.ascii.isAlphanumeric(lx.at(0))) lx.pos += 1;
            return;
        }
        lx.digits();
        // a Rational literal: digits, a backslash, digits: `3\4` (types.md#rational)
        if (lx.at(0) == '\\' and std.ascii.isDigit(lx.at(1))) {
            lx.pos += 1;
            lx.digits();
            return;
        }
        // a duration (D-144, D-221): an integer followed at once by `us`, `ms`, `s`, `m` or `h`: `10ms`, `30s`
        if (lx.at(0) == 'u' and lx.at(1) == 's' and !isIdentChar(lx.at(2))) {
            lx.pos += 2;
            return;
        }
        if (lx.at(0) == 'm' and lx.at(1) == 's' and !isIdentChar(lx.at(2))) {
            lx.pos += 2;
            return;
        }
        if ((lx.at(0) == 's' or lx.at(0) == 'm' or lx.at(0) == 'h') and !isIdentChar(lx.at(1))) {
            lx.pos += 1;
            return;
        }
        if (lx.at(0) == '.' and std.ascii.isDigit(lx.at(1))) {
            lx.pos += 1;
            lx.digits();
        }
        // a type suffix right after the digits (D-080): `12.50d`, `255b`, `42n`, `1.5f`, `5r`, `11w`, `7z`
        if (std.mem.indexOfScalar(u8, "drfbwnz", lx.at(0)) != null and !isIdentChar(lx.at(1))) {
            lx.pos += 1;
            return;
        }
        // exponent (D-095): `e` or `E`, an optional sign, digits: `1.5e3`, `2e-3`
        if (lx.at(0) == 'e' or lx.at(0) == 'E') {
            const sign: usize = if (lx.at(1) == '+' or lx.at(1) == '-') 1 else 0;
            if (std.ascii.isDigit(lx.at(1 + sign))) {
                lx.pos += 1 + sign;
                lx.digits();
            }
        }
    }

    fn string(lx: *Lexer, line: u32, column: u32) Error!void {
        if (lx.at(1) == '"' and lx.at(2) == '"') {
            const end = std.mem.indexOf(u8, lx.src[lx.pos + 3 ..], "\"\"\"") orelse {
                lx.diag.set(line, column, "unterminated text literal, '\"\"\"' not found", .{});
                return error.Syntax;
            };
            const stop = lx.pos + 3 + end + 3;
            while (lx.pos < stop) : (lx.pos += 1) {
                if (lx.src[lx.pos] == '\n') {
                    lx.line += 1;
                    lx.line_start = lx.pos + 1;
                }
            }
            return;
        }
        lx.pos += 1;
        const raw = lx.at(0) == '/'; // a regex literal has no placeholders: its braces are plain
        var depth: usize = 0; // braces open in the placeholder being read
        var inner: u8 = 0; // the quote of a string inside a placeholder, or 0
        while (true) {
            const s = lx.at(0);
            if (s == 0 or s == '\n') {
                lx.diag.set(line, column, "unterminated string", .{});
                return error.Syntax;
            }
            lx.pos += 1;
            if (s == '\\' and lx.at(0) != 0 and lx.at(0) != '\n') {
                lx.pos += 1;
            } else if (depth == 0) {
                if (s == '"') return;
                if (s == '{' and !raw) depth = 1;
            } else if (inner != 0) {
                if (s == inner) inner = 0;
            } else switch (s) {
                '"', '\'' => inner = s,
                '{' => depth += 1,
                '}' => depth -= 1,
                else => {},
            }
        }
    }

    /// A symbol literal: `'a'`, `'β'`, `'\n'`, `U+03B1`; one line, closed by the next `'`.
    fn char(lx: *Lexer, line: u32, column: u32) Error!void {
        lx.pos += 1;
        while (true) {
            const s = lx.at(0);
            if (s == 0 or s == '\n') {
                lx.diag.set(line, column, "unterminated symbol literal", .{});
                return error.Syntax;
            }
            lx.pos += 1;
            if (s == '\'') return;
            if (s == '\\' and lx.at(0) != 0 and lx.at(0) != '\n') lx.pos += 1;
        }
    }

    const operators = [_][]const u8{
        ">..<", "..<", ">..", ":=", "::", "??", "+=", "-=", "*=", "/=", "%=", "^=", "==", "<>", "<=", ">=",
        "=>",   "<:",  "<+",  "+>", "+-", "<-", "->", "=~", "..", "||", "&&", "<<", ">>", "><",
    };

    fn next(lx: *Lexer) Error!Token {
        try lx.skipBlanks();
        const start = lx.pos;
        const line = lx.line;
        const column = lx.col();
        if (start >= lx.src.len) return lx.token(.eof, start, line, column);
        const c = lx.src[start];
        if (c == 'U' and lx.at(1) == '+' and std.ascii.isHex(lx.at(2))) {
            lx.pos += 2;
            while (std.ascii.isHex(lx.at(0))) lx.pos += 1;
            return lx.token(.char, start, line, column);
        }
        // an imaginary literal: `i` and a number, `i99`, `i2.5`, `i1e3`, not followed by a name character and not a member name after a dot
        if (c == 'i' and std.ascii.isDigit(lx.at(1)) and !(start > 0 and lx.src[start - 1] == '.')) {
            var j: usize = 1;
            while (std.ascii.isDigit(lx.at(j))) j += 1;
            if (lx.at(j) == '.' and std.ascii.isDigit(lx.at(j + 1))) {
                j += 1;
                while (std.ascii.isDigit(lx.at(j))) j += 1;
            }
            if (lx.at(j) == 'e' or lx.at(j) == 'E') {
                const sign: usize = if (lx.at(j + 1) == '+' or lx.at(j + 1) == '-') 1 else 0;
                if (std.ascii.isDigit(lx.at(j + 1 + sign))) {
                    j += 1 + sign;
                    while (std.ascii.isDigit(lx.at(j))) j += 1;
                }
            }
            if (!isIdentChar(lx.at(j))) {
                lx.pos += j;
                return lx.token(.number, start, line, column);
            }
        }
        if (isIdentStart(c) or (c == '$' and isIdentStart(lx.at(1)))) {
            lx.pos += 1;
            while (isIdentChar(lx.at(0))) lx.pos += 1;
            // a name may end with `!`: a function or method that is not deterministic (D-087)
            if (lx.at(0) == '!' and lx.at(1) != '=' and lx.at(1) != '~') lx.pos += 1;
            return lx.token(.ident, start, line, column);
        }
        if (std.ascii.isDigit(c)) {
            lx.number();
            return lx.token(.number, start, line, column);
        }
        if (c == '"') {
            try lx.string(line, column);
            // a string followed at once by a type suffix is a number: `"1,000,000"z`, `"12,500.75"d`
            if ((lx.at(0) == 'z' or lx.at(0) == 'd') and !isIdentChar(lx.at(1))) {
                lx.pos += 1;
                return lx.token(.number, start, line, column);
            }
            return lx.token(.string, start, line, column);
        }
        if (c == '\'') {
            try lx.char(line, column);
            return lx.token(.char, start, line, column);
        }
        for (operators) |op| {
            if (std.mem.startsWith(u8, lx.src[start..], op)) {
                lx.pos += op.len;
                return lx.token(.symbol, start, line, column);
            }
        }
        if (c < 128 and std.ascii.isPrint(c) and c != '\\') {
            lx.pos += 1;
            return lx.token(.symbol, start, line, column);
        }
        lx.diag.set(line, column, "unexpected character (byte {d})", .{c});
        return error.Syntax;
    }
};

// @decision D-179
/// All the tokens of `src`, ending with one `.eof`. On a syntax error `diag` tells where.
pub fn tokenize(gpa: std.mem.Allocator, src: []const u8, diag: *Diag) Error![]Token {
    if (std.mem.startsWith(u8, src, "#!")) {
        diag.set(1, 1, "a file has no #! line: Eve has no free scripts, every program is an aspect (D-179)", .{});
        return error.Syntax;
    }
    var lx: Lexer = .{ .src = src, .diag = diag };
    var list: std.ArrayList(Token) = .empty;
    errdefer list.deinit(gpa);
    while (true) {
        const t = try lx.next();
        try list.append(gpa, t);
        if (t.kind == .eof) break;
    }
    return list.toOwnedSlice(gpa);
}

test "comments are skipped and positions are kept" {
    const gpa = std.testing.allocator;
    var d: Diag = .{};
    const toks = try tokenize(gpa,
        \\# title
        \\aspect x is ** trailing
        \\/* a
        \\   b */ over;
    , &d);
    defer gpa.free(toks);
    // aspect, x, is, over, ;, eof
    try std.testing.expectEqual(@as(usize, 6), toks.len);
    try std.testing.expectEqualStrings("aspect", toks[0].text);
    try std.testing.expectEqual(@as(u32, 2), toks[0].line);
    try std.testing.expectEqualStrings("over", toks[3].text);
    try std.testing.expectEqual(@as(u32, 4), toks[3].line);
    try std.testing.expectEqual(@as(u32, 9), toks[3].col);
    try std.testing.expectEqual(Kind.eof, toks[5].kind);
}

test "a #! line is refused" {
    var d: Diag = .{};
    try std.testing.expectError(error.Syntax, tokenize(std.testing.allocator, "#!/usr/bin/env eve\nprint 1;", &d));
    try std.testing.expect(std.mem.indexOf(u8, d.message(), "no free scripts") != null);
}

test "unterminated block comment and string are reported" {
    var d: Diag = .{};
    try std.testing.expectError(error.Syntax, tokenize(std.testing.allocator, "x\n/* open", &d));
    try std.testing.expectEqual(@as(u32, 2), d.line);
    try std.testing.expectError(error.Syntax, tokenize(std.testing.allocator, "\"abc\n", &d));
    try std.testing.expectEqualStrings("unterminated string", d.message());
}
