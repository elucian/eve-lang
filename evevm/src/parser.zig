//! Parser: checks that the tokens of a script follow the Eve grammar (spec/syntax). It builds no
//! tree yet: it only answers "is this script correct?" and, if not, where the first error is.
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
const std = @import("std");
const lexer = @import("lexer.zig");

const Token = lexer.Token;
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
// Every function returns `Error!void` and the callers use `try`, so the first syntax error
// unwinds the whole parse and `diag` keeps its message.
const Parser = struct {
    toks: []const Token,
    i: usize = 0,
    diag: *Diag,

    fn peek(p: *const Parser) Token {
        return p.toks[p.i];
    }

    // Zig tip: `@min(a, b)` keeps an index inside the array: past the last token (always the eof
    // token) the parser sees eof again instead of reading out of bounds.
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

    // ---- types, parameters ------------------------------------------------------------------

    // Zig tip: a `while (true)` loop with `break` is the usual way to write "repeat until a
    // condition found inside". `if (!p.acceptSym(",")) break;` reads: no comma, the list is over.
    /// `Integer`, `[5]Integer`, `[2, 2]Integer`.
    fn typeName(p: *Parser) Error!void {
        if (p.acceptSym("[")) {
            while (true) {
                try p.expr();
                if (!p.acceptSym(",")) break;
            }
            try p.expectSym("]");
        }
        _ = try p.expectName("a type name");
    }

    /// `( [@]name [= default] [: Type], ... )` of a function, a method, a constructor or a lambda.
    fn params(p: *Parser) Error!void {
        try p.expectSym("(");
        if (!p.isSym(")")) {
            while (true) {
                _ = p.acceptSym("@");
                _ = try p.expectName("a parameter name");
                if (p.acceptSym("=")) try p.expr();
                if (p.acceptSym(":")) try p.typeName();
                if (!p.acceptSym(",")) break;
            }
        }
        try p.expectSym(")");
    }

    /// `[ (params) ] [ => (results) ] is block return ;` shared by function, method, constructor.
    fn routine(p: *Parser, what: []const u8) Error!void {
        _ = p.advance();
        if (!std.mem.eql(u8, what, "constructor")) _ = try p.expectName("a name");
        if (p.isSym("(")) try p.params();
        if (p.isSym("(")) try p.params(); // a constructor has two groups: (@self)(fields)
        if (p.acceptSym("=>")) try p.params();
        try p.expectWord("is");
        try p.block();
        try p.expectWord("return");
        try p.expectSym(";");
    }

    // ---- expressions ------------------------------------------------------------------------

    fn expr(p: *Parser) Error!void {
        try p.orExpr();
        while (p.isSym("<+") or p.isSym("<-") or p.isSym("->")) {
            _ = p.advance();
            try p.orExpr();
        }
    }

    fn orExpr(p: *Parser) Error!void {
        try p.xorExpr();
        while (p.acceptWord("or")) try p.xorExpr();
    }

    fn xorExpr(p: *Parser) Error!void {
        try p.andExpr();
        while (p.acceptWord("xor")) try p.andExpr();
    }

    fn andExpr(p: *Parser) Error!void {
        try p.notExpr();
        while (p.acceptWord("and")) try p.notExpr();
    }

    // Zig tip: a function may call itself: `not not x` is read by `notExpr` calling `notExpr`.
    // Recursion is how a grammar rule that contains itself (nested parentheses, `not not`) is
    // written; `return p.notExpr();` hands the result of the inner call straight back.
    fn notExpr(p: *Parser) Error!void {
        if (p.acceptWord("not")) return p.notExpr();
        return p.compare();
    }

    // Zig tip: `inline for` over a tuple of strings is unrolled by the compiler, so `isSym` gets a
    // compile-time known text each time. A plain `for` over an array of strings works as well;
    // `for (list) |op| { if (...) { found = true; break; } }` is the run-time form used here.
    /// `== <> < > <= >= =~ !~ in, not in, is, is not` (a chain is accepted).
    fn compare(p: *Parser) Error!void {
        try p.range();
        while (true) {
            if (p.compareOp()) {
                try p.range();
            } else break;
        }
    }

    fn compareOp(p: *Parser) bool {
        const ops = [_][]const u8{ "==", "<>", "<", ">", "<=", ">=", "=~", "!~" };
        for (ops) |op| {
            if (p.acceptSym(op)) return true;
        }
        if (p.acceptWord("in")) return true;
        if (p.isWord("not") and p.isWordAt(1, "in")) {
            _ = p.advance();
            _ = p.advance();
            return true;
        }
        if (p.acceptWord("is")) {
            _ = p.acceptWord("not");
            return true;
        }
        return false;
    }

    /// `a..b  a..<b  a>..b  a>..<b`
    fn range(p: *Parser) Error!void {
        try p.additive();
        const ops = [_][]const u8{ "..", "..<", ">..", ">..<" };
        for (ops) |op| {
            if (p.acceptSym(op)) {
                try p.additive();
                return;
            }
        }
    }

    fn additive(p: *Parser) Error!void {
        try p.multiplicative();
        while (p.isSym("+") or p.isSym("-") or p.isSym("||")) {
            _ = p.advance();
            try p.multiplicative();
        }
    }

    fn multiplicative(p: *Parser) Error!void {
        try p.unary();
        while (p.isSym("*") or p.isSym("/") or p.isSym("%") or p.isSym("&&") or p.isSym("><") or
            p.isSym("<<") or p.isSym(">>"))
        {
            _ = p.advance();
            try p.unary();
        }
    }

    fn unary(p: *Parser) Error!void {
        if (p.acceptSym("-") or p.acceptSym("+")) return p.unary();
        if (p.acceptWord("new")) return p.postfix();
        return p.power();
    }

    /// `^` binds tighter than `*` and goes right to left: `2 ^ 3 ^ 2` is `2 ^ (3 ^ 2)`.
    fn power(p: *Parser) Error!void {
        try p.postfix();
        if (p.acceptSym("^")) try p.unary();
    }

    // Zig tip: a `switch` on a token kind covers a closed set of cases; `else` takes the rest.
    // `a.b`, `a[i]` and `a(x)` are "postfix" operations that can follow each other, so they are
    // a loop. A call `(` may follow a name, a `)` or a `]` but not a literal: `"x"(...)` is not
    // a call, and the check also stops `print "a" (...)` from being read as a call.
    fn postfix(p: *Parser) Error!void {
        const first = p.peek();
        try p.primary();
        var callable = first.kind == .ident or (first.kind == .symbol and first.text[0] == '(');
        while (true) {
            if (p.acceptSym(".")) {
                // an attribute may be named like a keyword: `$error.job`
                if (p.peek().kind != .ident) return p.fail("expected an attribute name but found '{s}'", .{describe(p.peek())});
                _ = p.advance();
                callable = true;
            } else if (p.acceptSym("[")) {
                try p.indexList();
                callable = true;
            } else if (callable and p.isSym("(")) {
                try p.group(")");
            } else break;
        }
    }

    /// The inside of `[ ... ]`: expressions, `$` for the last index, `*` for a whole dimension.
    fn indexList(p: *Parser) Error!void {
        while (true) {
            if (!(p.isSym("*") and (p.isSymAt(1, "]") or p.isSymAt(1, ","))))
                try p.expr()
            else
                _ = p.advance();
            if (!p.acceptSym(",")) break;
        }
        try p.expectSym("]");
    }

    /// One element of a list, call or object: `expr`, `name: expr`, `x if c else y`.
    fn item(p: *Parser) Error!void {
        try p.conditional();
        if (p.acceptSym(":")) try p.conditional();
    }

    // Zig tip: `_ = p.acceptSym("@");` calls a function only for its effect and drops its `bool`
    // result on purpose: Zig makes you write the `_ =` so a forgotten result is never silent.
    fn conditional(p: *Parser) Error!void {
        _ = p.acceptSym("@"); // `@name` passes a variable by reference
        try p.expr();
        if (p.acceptWord("if")) {
            try p.expr();
            try p.expectWord("else");
            try p.conditional();
        }
    }

    /// The items after an opening `(`, `[` or `{` and the closing symbol; a builder `| x in ...`
    /// may end the list.
    fn group(p: *Parser, close: []const u8) Error!void {
        _ = p.advance(); // the opening symbol
        if (!p.isSym(close)) {
            while (true) {
                try p.item();
                if (!p.acceptSym(",")) break;
            }
            if (p.acceptSym("|")) try p.expr();
        }
        try p.expectSym(close);
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

    fn primary(p: *Parser) Error!void {
        const t = p.peek();
        switch (t.kind) {
            .number, .string, .char => _ = p.advance(),
            .ident => {
                if (reserved.has(t.text)) {
                    return p.fail("unexpected '{s}' in an expression", .{t.text});
                }
                _ = p.advance();
            },
            .symbol => {
                if (p.isSym("(")) {
                    if (p.isLambda()) {
                        try p.params();
                        try p.expectSym("=>");
                        try p.group(")");
                    } else try p.group(")");
                } else if (p.isSym("[")) {
                    try p.group("]");
                } else if (p.isSym("{")) {
                    try p.group("}");
                } else if (p.isSym("$")) {
                    _ = p.advance();
                } else if (p.isSym("@")) {
                    _ = p.advance();
                    _ = try p.expectName("a variable name");
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
    fn block(p: *Parser) Error!void {
        while (true) {
            const t = p.peek();
            if (t.kind == .eof) return p.fail("unexpected end of file, the block is not closed", .{});
            if (t.kind == .ident and block_end.has(t.text)) return;
            try p.statement();
        }
    }

    /// `[ if condition ] ;` ends every simple statement.
    fn endSimple(p: *Parser) Error!void {
        if (p.acceptWord("if")) try p.expr();
        try p.expectSym(";");
    }

    fn isAssignOp(p: *const Parser) bool {
        const ops = [_][]const u8{ ":=", "::", "+=", "-=", "*=", "/=", "%=", "^=" };
        for (ops) |op| {
            if (p.isSym(op)) return true;
        }
        return false;
    }

    /// `let a, b := value :Type;`, `let x = y = 1 :Integer;`, `let a :Type;`, `let p, *rest :: n;`
    // Zig tip: `p.acceptSym(":=") or p.acceptSym("::")` relies on short-circuit evaluation: the
    // second call runs only if the first returned false, and each call moves the cursor only
    // when it matches, so the `or` reads "one of these two symbols".
    fn declaration(p: *Parser) Error!void {
        _ = p.advance(); // let or set
        while (true) {
            if (p.acceptSym("*")) {
                if (p.peek().kind == .ident and !reserved.has(p.peek().text)) _ = p.advance();
            } else {
                _ = try p.expectName("a variable name");
                while (p.acceptSym(".")) _ = try p.expectName("an attribute name");
            }
            if (!p.acceptSym(",")) break;
        }
        if (p.acceptSym(":=") or p.acceptSym("::")) {
            try p.expr();
        } else if (p.acceptSym("=")) {
            try p.expr();
            while (p.acceptSym("=")) try p.expr();
        }
        if (p.acceptSym(":")) try p.typeName();
        try p.endSimple();
    }

    /// The common end of `if`, `while`, `for`: `block [else block] [then block] done ;`.
    fn loopTail(p: *Parser) Error!void {
        try p.block();
        if (p.acceptWord("else")) try p.block();
        if (p.acceptWord("then")) try p.block();
        try p.expectWord("done");
        try p.expectSym(";");
    }

    fn ifStatement(p: *Parser) Error!void {
        try p.expectWord("if");
        try p.expr();
        try p.expectWord("do");
        try p.block();
        while (p.acceptWord("else")) {
            if (p.acceptWord("if")) {
                try p.expr();
                try p.expectWord("do");
                try p.block();
            } else {
                try p.block();
                break;
            }
        }
        try p.expectWord("done");
        try p.expectSym(";");
    }

    fn matchStatement(p: *Parser) Error!void {
        try p.expectWord("match");
        try p.expr();
        if (!p.isWord("when")) return p.fail("expected 'when' but found '{s}'", .{describe(p.peek())});
        while (p.acceptWord("when")) {
            try p.expr();
            try p.expectWord("do");
            try p.block();
        }
        if (p.acceptWord("then")) try p.block();
        try p.expectWord("done");
        try p.expectSym(";");
    }

    fn statement(p: *Parser) Error!void {
        const t = p.peek();
        if (t.kind == .ident) {
            const w = t.text;
            if (std.mem.eql(u8, w, "let") or std.mem.eql(u8, w, "set")) return p.declaration();
            if (std.mem.eql(u8, w, "if")) return p.ifStatement();
            if (std.mem.eql(u8, w, "match")) return p.matchStatement();
            if (std.mem.eql(u8, w, "while")) {
                _ = p.advance();
                try p.expr();
                try p.expectWord("do");
                return p.loopTail();
            }
            if (std.mem.eql(u8, w, "loop")) {
                _ = p.advance();
                while (!p.isWord("while")) {
                    if (p.peek().kind == .eof) return p.fail("expected 'while' in the loop header", .{});
                    try p.statement();
                }
                _ = p.advance();
                try p.expr();
                try p.expectWord("do");
                return p.loopTail();
            }
            if (std.mem.eql(u8, w, "for")) {
                _ = p.advance();
                try p.postfix();
                try p.expectWord("in");
                try p.expr();
                try p.expectWord("do");
                return p.loopTail();
            }
            if (!reserved.has(w) and p.isSymAt(1, ":") and p.isWordAt(2, "job")) {
                _ = p.advance();
                _ = p.advance();
                _ = p.advance();
                try p.expectWord("do");
                try p.block();
                try p.expectWord("done");
                const label = try p.expectName("the job label");
                if (!std.mem.eql(u8, label.text, w)) {
                    p.i -= 1;
                    return p.fail("'done {s}' does not match the job '{s}'", .{ label.text, w });
                }
                return p.expectSym(";");
            }
            const simple = [_][]const u8{ "break", "next", "over", "panic", "retry", "resume", "abort" };
            for (simple) |s| {
                if (std.mem.eql(u8, w, s)) {
                    _ = p.advance();
                    return p.endSimple();
                }
            }
            const with_value = [_][]const u8{ "print", "write", "expect", "raise" };
            for (with_value) |s| {
                if (std.mem.eql(u8, w, s)) {
                    _ = p.advance();
                    if (!p.isSym(";") and !p.isWord("if")) try p.expr();
                    return p.endSimple();
                }
            }
            if (reserved.has(w)) {
                return p.fail("unexpected '{s}', expected a statement", .{w});
            }
        }
        try p.expr();
        if (p.isAssignOp()) {
            _ = p.advance();
            try p.expr();
        }
        try p.endSimple();
    }

    // ---- declarations -----------------------------------------------------------------------

    fn process(p: *Parser) Error!void {
        try p.expectWord("process");
        _ = try p.expectName("a process name");
        try p.expectWord("is");
        try p.block();
        if (p.acceptWord("recover")) try p.block();
        if (p.acceptWord("finalize")) try p.block();
        try p.expectWord("return");
        try p.expectSym(";");
    }

    fn class(p: *Parser) Error!void {
        try p.expectWord("class");
        const name = try p.expectName("a class name");
        try p.expectSym("=");
        try p.expectSym("{");
        if (!p.isSym("}")) {
            while (true) {
                _ = try p.expectName("a member name");
                if (p.acceptSym(":")) {
                    if (p.peek().kind == .number) _ = p.advance() else try p.typeName();
                }
                if (!p.acceptSym(",")) break;
            }
        }
        try p.expectSym("}");
        if (p.acceptSym("<:")) _ = try p.expectName("a parent class name");
        if (p.acceptSym(";")) return;
        try p.expectWord("is");
        while (!p.isWord("end")) {
            if (p.isWord("constructor")) {
                try p.routine("constructor");
            } else if (p.isWord("method")) {
                try p.routine("method");
            } else if (p.isWord("function")) {
                try p.routine("function");
            } else return p.fail("unexpected '{s}' in the class, expected a constructor or a method", .{describe(p.peek())});
        }
        try p.expectWord("end");
        const end_name = try p.expectName("the class name");
        if (!std.mem.eql(u8, name.text, end_name.text)) {
            p.i -= 1;
            return p.fail("'end {s}' does not match 'class {s}'", .{ end_name.text, name.text });
        }
        try p.expectSym(";");
    }

    fn declarationInDriver(p: *Parser) Error!void {
        if (p.isWord("let") or p.isWord("set")) return p.declaration();
        if (p.isWord("class")) return p.class();
        if (p.isWord("function")) return p.routine("function");
        if (p.isWord("method")) return p.routine("method");
        if (p.isWord("process")) return p.process();
        return p.fail("unexpected '{s}' in the driver, expected a declaration or 'end'", .{describe(p.peek())});
    }

    fn driver(p: *Parser) Error!void {
        try p.expectWord("driver");
        const name = try p.expectName("a driver name");
        try p.expectWord("is");
        while (!p.isWord("end")) try p.declarationInDriver();
        try p.expectWord("end");
        const end_name = try p.expectName("the driver name");
        if (!std.mem.eql(u8, name.text, end_name.text)) {
            p.i -= 1; // report at the name after `end`
            return p.fail("'end {s}' does not match 'driver {s}'", .{ end_name.text, name.text });
        }
        try p.expectSym(";");
    }

    fn script(p: *Parser) Error!void {
        if (p.isWord("driver")) {
            try p.driver();
        } else {
            while (p.peek().kind != .eof) try p.statement();
        }
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
