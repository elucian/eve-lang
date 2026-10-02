//! Parser: checks that the tokens of a script follow the Eve grammar (spec/syntax). It builds no
//! tree yet: it only answers "is this script correct?" and, if not, where the first error is.
//!
//! Grammar implemented so far (grows test by test):
//!
//!     script    = "driver" name "is" process { process } "end" name ";"
//!     process   = "process" name "is" { statement } "return" ";"
//!     statement = ( "over" | "panic" ) ";"
const std = @import("std");
const lexer = @import("lexer.zig");

const Token = lexer.Token;
pub const Diag = lexer.Diag;
pub const Error = lexer.Error;

// Zig tip: this is a "recursive descent" parser: one function per grammar rule, each one consuming
// tokens and calling the functions of the rules inside it. `self.i` is the index of the next
// token; the helpers `peek`, `word`, `expectWord`... move it. The parser holds a slice of tokens
// and a pointer to the `Diag` it fills on the first error; it stops at the first error because
// every function returns `Error!void` and the callers use `try`.
const Parser = struct {
    toks: []const Token,
    i: usize = 0,
    diag: *Diag,

    fn peek(p: *const Parser) Token {
        return p.toks[p.i];
    }

    fn advance(p: *Parser) Token {
        const t = p.toks[p.i];
        if (t.kind != .eof) p.i += 1;
        return t;
    }

    /// Is the next token the identifier `text` (the keywords are identifiers to the lexer)?
    fn isWord(p: *const Parser, text: []const u8) bool {
        const t = p.peek();
        return t.kind == .ident and std.mem.eql(u8, t.text, text);
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

    fn describe(t: Token) []const u8 {
        return if (t.kind == .eof) "end of file" else t.text;
    }

    fn expectWord(p: *Parser, text: []const u8) Error!void {
        if (!p.isWord(text)) return p.fail("expected '{s}' but found '{s}'", .{ text, describe(p.peek()) });
        _ = p.advance();
    }

    fn expectSymbol(p: *Parser, c: u8) Error!void {
        const t = p.peek();
        if (t.kind != .symbol or t.text[0] != c) {
            return p.fail("expected '{c}' but found '{s}'", .{ c, describe(t) });
        }
        _ = p.advance();
    }

    fn expectName(p: *Parser, what: []const u8) Error!Token {
        const t = p.peek();
        if (t.kind != .ident) return p.fail("expected {s} but found '{s}'", .{ what, describe(t) });
        return p.advance();
    }

    fn statement(p: *Parser) Error!void {
        if (p.isWord("over") or p.isWord("panic")) {
            _ = p.advance();
            return p.expectSymbol(';');
        }
        return p.fail("unexpected '{s}', expected a statement or 'return'", .{describe(p.peek())});
    }

    fn process(p: *Parser) Error!void {
        try p.expectWord("process");
        _ = try p.expectName("a process name");
        try p.expectWord("is");
        while (!p.isWord("return")) try p.statement();
        try p.expectWord("return");
        try p.expectSymbol(';');
    }

    fn script(p: *Parser) Error!void {
        try p.expectWord("driver");
        const name = try p.expectName("a driver name");
        try p.expectWord("is");
        try p.process();
        while (p.isWord("process")) try p.process();
        try p.expectWord("end");
        const end_name = try p.expectName("the driver name");
        if (!std.mem.eql(u8, name.text, end_name.text)) {
            p.i -= 1; // report at the name after `end`
            return p.fail("'end {s}' does not match 'driver {s}'", .{ end_name.text, name.text });
        }
        try p.expectSymbol(';');
        if (p.peek().kind != .eof) return p.fail("unexpected '{s}' after the end of the driver", .{describe(p.peek())});
    }
};

// Zig tip: `pub fn` makes a function visible to other files. This is the whole public face of the
// parser: text in, nothing or a `Diag` out. `defer gpa.free(toks)` releases the tokens on every
// way out, success or error.
/// Check the script `src`. On a syntax error returns `error.Syntax` and fills `diag`.
pub fn check(gpa: std.mem.Allocator, src: []const u8, diag: *Diag) Error!void {
    const toks = try lexer.tokenize(gpa, src, diag);
    defer gpa.free(toks);
    var p: Parser = .{ .toks = toks, .diag = diag };
    try p.script();
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
