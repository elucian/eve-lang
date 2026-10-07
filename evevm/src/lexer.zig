//! Lexer: turns the text of an Eve script into tokens (spec/lexical/lexical.md).
//!
//! Comments are skipped here, the parser never sees them: `#` or `##` at column 0 and `**` run to
//! the end of the line, `(** ... **)` and `/* ... */` run to their closing marker (no nesting).
const std = @import("std");

// Zig tip: an `enum` is a closed list of names. `switch` on an enum must cover every name (or have
// an `else`), so adding a name later makes the compiler show every `switch` to update.
pub const Kind = enum { ident, number, string, char, symbol, eof };

// Zig tip: `text` is a view into the script's own bytes, not a copy, so a token costs no
// allocation. `u32` is a 32-bit unsigned integer, plenty for a line number.
pub const Token = struct {
    kind: Kind,
    text: []const u8,
    /// Line and column of the first character, both counted from 1.
    line: u32,
    col: u32,
};

// Zig tip: an error in Zig is only a name; it cannot carry a message or a position. The usual
// answer is an out parameter: the failing function fills a `Diag` that the caller passes in, and
// returns `error.Syntax` to say "look at the Diag". `std.fmt.bufPrint` formats into a fixed
// buffer, so reporting an error never allocates (and cannot fail for lack of memory).
/// Where and why a script is wrong. The lexer and the parser both fill it.
pub const Diag = struct {
    line: u32 = 0,
    col: u32 = 0,
    buf: [160]u8 = undefined,
    len: usize = 0,

    // Zig tip: `comptime fmt: []const u8, args: anytype` is how a function takes a format string
    // and a tuple of values, like `print`: the compiler checks them against each other.
    // `catch @as([]u8, &d.buf)` keeps the text cut when it is too long (error.NoSpaceLeft).
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

// Zig tip: a struct with fields and functions is Zig's "class". A function whose first parameter
// is the struct (`lx: *Lexer`) is called as a method: `lx.next()`. `*const Lexer` promises not
// to change it. `src[i]` is bounds-checked: reading past the end stops the program in Debug,
// which is why `at` returns 0 instead of reading outside the text.
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

    // Zig tip: `@intCast` converts between integer types (here `usize` to `u32`) and, in Debug,
    // stops the program if the value does not fit.
    fn col(lx: *const Lexer) u32 {
        return @intCast(lx.pos - lx.line_start + 1);
    }

    fn skipToEndOfLine(lx: *Lexer) void {
        while (lx.pos < lx.src.len and lx.src[lx.pos] != '\n') lx.pos += 1;
    }

    // Zig tip: a function that returns `Error!void` can fail with `return error.Syntax`; the
    // caller passes the failure on with `try`. The `while` loop here ends with `else return`:
    // a chain of `if ... else if` where the last `else` leaves the function.
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

    // Zig tip: `std.mem.indexOf(u8, haystack, needle)` returns `?usize`: the position or null.
    // `orelse { ... }` runs a block when it is null; the block must leave the function.
    // The lines inside the comment are counted so later positions stay right.
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

    // Zig tip: a `bool` function can be used directly as a loop or `if` condition. The digit
    // separator `_` is not accepted in a number (Q-013, D-095), so `1_000` lexes as the number
    // `1` followed by the name `_000`, which the parser then refuses.
    fn digits(lx: *Lexer) void {
        while (std.ascii.isDigit(lx.at(0))) lx.pos += 1;
    }

    // Zig tip: a number is lexed by looking at the next bytes without consuming them (`at(1)`).
    // `1..5` must lex as `1`, `..`, `5`, so a `.` belongs to the number only when a digit follows.
    // `std.ascii.isAlphanumeric` accepts the hex digits of `0xFF` and the `0b101` marker alike.
    fn number(lx: *Lexer) void {
        if (lx.at(0) == '0' and (lx.at(1) == 'x' or lx.at(1) == 'b')) {
            lx.pos += 2;
            while (std.ascii.isAlphanumeric(lx.at(0))) lx.pos += 1;
            return;
        }
        lx.digits();
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

    // Zig tip: `"""` opens a text literal: raw, several lines, closed by the next `"""`. The
    // ordinary string ends at its closing quote, skips the byte after a backslash (so `\"`
    // does not end it) and may not contain a line break. `interpolation` escapes such as `\#{x}`
    // need no special care here: the backslash skips the `#`, the rest is plain text.
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
        while (true) {
            const s = lx.at(0);
            if (s == 0 or s == '\n') {
                lx.diag.set(line, column, "unterminated string", .{});
                return error.Syntax;
            }
            lx.pos += 1;
            if (s == '"') return;
            if (s == '\\' and lx.at(0) != 0 and lx.at(0) != '\n') lx.pos += 1;
        }
    }

    /// A symbol literal: `'a'`, `'β'`, `'\x41'`, `'\u{3B1}'`; one line, closed by the next `'`.
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

    // Zig tip: a table of constant strings, longest first, is the simplest "longest match" lexer:
    // `for` tries each entry with `startsWith` and the first hit wins, so `>..<` is tried before
    // `>..` and `..`. `inline`-free: the table is an ordinary array evaluated at run time.
    const operators = [_][]const u8{
        ">..<", "..<", ">..", ":=", "::", "+=", "-=", "*=", "/=", "%=", "^=", "==", "<>", "<=", ">=",
        "=>",   "<:",  "<+",  "+>", "+-", "<-", "->", "=~", "..", "||", "&&", "<<", ">>", "><",
    };

    // Zig tip: `std.ascii.isDigit` and friends test one byte. `'a'` in single quotes is a byte
    // value (`u8`), so it can be compared and used in ranges, unlike a string. An identifier
    // may start with `$` (`$error`); a lone `$` is the last-index symbol. `U+0061` is a symbol
    // literal written with its code point. `return lx.token(...)` ends the function with the
    // token; `continue`-free style: each `if` returns.
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

// Zig tip: the caller owns what an allocating function returns: `toOwnedSlice` hands the list's
// memory over as a plain slice, and the caller frees it with `gpa.free(tokens)`. `errdefer` is
// like `defer` but runs only when the function returns an error, so a failure half way does not
// leak the list.
/// All the tokens of `src`, ending with one `.eof`. On a syntax error `diag` tells where.
pub fn tokenize(gpa: std.mem.Allocator, src: []const u8, diag: *Diag) Error![]Token {
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

// Zig tip: a multi-line string literal (`\\` lines) holds a whole script inside a test.
// `defer gpa.free(toks)` pairs the release with the line that took the memory; the testing
// allocator fails the test if it is forgotten.
test "comments are skipped and positions are kept" {
    const gpa = std.testing.allocator;
    var d: Diag = .{};
    const toks = try tokenize(gpa,
        \\# title
        \\driver x is ** trailing
        \\/* a
        \\   b */ over;
    , &d);
    defer gpa.free(toks);
    // driver, x, is, over, ;, eof
    try std.testing.expectEqual(@as(usize, 6), toks.len);
    try std.testing.expectEqualStrings("driver", toks[0].text);
    try std.testing.expectEqual(@as(u32, 2), toks[0].line);
    try std.testing.expectEqualStrings("over", toks[3].text);
    try std.testing.expectEqual(@as(u32, 4), toks[3].line);
    try std.testing.expectEqual(@as(u32, 9), toks[3].col);
    try std.testing.expectEqual(Kind.eof, toks[5].kind);
}

test "unterminated block comment and string are reported" {
    var d: Diag = .{};
    try std.testing.expectError(error.Syntax, tokenize(std.testing.allocator, "x\n/* open", &d));
    try std.testing.expectEqual(@as(u32, 2), d.line);
    try std.testing.expectError(error.Syntax, tokenize(std.testing.allocator, "\"abc\n", &d));
    try std.testing.expectEqualStrings("unterminated string", d.message());
}
