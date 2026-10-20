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
const consts = @import("parser/consts.zig");
const literals_m = @import("parser/literals.zig");
const routines_m = @import("parser/routines.zig");
const expr_m = @import("parser/expr.zig");
const statements_m = @import("parser/statements.zig");
const classes_m = @import("parser/classes.zig");
const modules_m = @import("parser/modules.zig");
const aspects_m = @import("parser/aspects.zig");

const Token = lexer.Token;
const Node = ast.Node;
const Tag = ast.Tag;
pub const Diag = lexer.Diag;
pub const Error = lexer.Error;

pub const reserved = consts.reserved;
pub const plainNumber = consts.plainNumber;
pub const block_end = consts.block_end;
pub const Parser = struct {
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

    pub fn peek(p: *const Parser) Token {
        return p.toks[p.i];
    }

    pub fn peekAt(p: *const Parser, n: usize) Token {
        return p.toks[@min(p.i + n, p.toks.len - 1)];
    }

    pub fn advance(p: *Parser) Token {
        const t = p.toks[p.i];
        if (t.kind != .eof) p.i += 1;
        return t;
    }

    pub fn tokIs(t: Token, kind: Kind, text: []const u8) bool {
        return t.kind == kind and std.mem.eql(u8, t.text, text);
    }

    const Kind = lexer.Kind;

    /// Is the next token the identifier `text` (the keywords are identifiers to the lexer)?
    pub fn isWord(p: *const Parser, text: []const u8) bool {
        return tokIs(p.peek(), .ident, text);
    }

    pub fn isWordAt(p: *const Parser, n: usize, text: []const u8) bool {
        return tokIs(p.peekAt(n), .ident, text);
    }

    pub fn isSym(p: *const Parser, text: []const u8) bool {
        return tokIs(p.peek(), .symbol, text);
    }

    pub fn isSymAt(p: *const Parser, n: usize, text: []const u8) bool {
        return tokIs(p.peekAt(n), .symbol, text);
    }

    /// Consume the word if it is next; tell whether it was.
    pub fn acceptWord(p: *Parser, text: []const u8) bool {
        if (!p.isWord(text)) return false;
        _ = p.advance();
        return true;
    }

    pub fn acceptSym(p: *Parser, text: []const u8) bool {
        if (!p.isSym(text)) return false;
        _ = p.advance();
        return true;
    }

    pub fn fail(p: *Parser, comptime fmt: []const u8, args: anytype) Error {
        const t = p.peek();
        p.diag.set(t.line, t.col, fmt, args);
        return error.Syntax;
    }

    /// Like `fail`, but the error is reported at the token `t`.
    pub fn failAt(p: *Parser, t: Token, comptime fmt: []const u8, args: anytype) Error {
        p.diag.set(t.line, t.col, fmt, args);
        return error.Syntax;
    }

    pub fn describe(t: Token) []const u8 {
        return if (t.kind == .eof) "end of file" else t.text;
    }

    pub fn expectWord(p: *Parser, text: []const u8) Error!void {
        if (!p.acceptWord(text)) return p.fail("expected '{s}' but found '{s}'", .{ text, describe(p.peek()) });
    }

    pub fn expectSym(p: *Parser, text: []const u8) Error!void {
        if (!p.acceptSym(text)) return p.fail("expected '{s}' but found '{s}'", .{ text, describe(p.peek()) });
    }

    pub fn expectName(p: *Parser, what: []const u8) Error!Token {
        const t = p.peek();
        if (t.kind != .ident or reserved.has(t.text)) {
            return p.fail("expected {s} but found '{s}'", .{ what, describe(t) });
        }
        return p.advance();
    }

    // @eve-impl a name that may be a reserved word (the native members `write`, `expect`, `assert` of the system library)
    pub fn expectAnyName(p: *Parser) Error!Token {
        const t = p.peek();
        if (t.kind != .ident) return p.fail("expected a name but found '{s}'", .{describe(t)});
        return p.advance();
    }

    // ---- node construction ------------------------------------------------------------------

    pub fn mk(p: *Parser, tag: Tag, at: Token, text: []const u8, kids: []const *const Node) Error!*Node {
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

    pub fn noneNode(p: *const Parser) *const Node {
        _ = p;
        return &ast.none;
    }

    // ---- literals ---------------------------------------------------------------------------

    // ------------------------------------------------------------ parser/literals.zig
    pub const appendCodePoint = literals_m.appendCodePoint;
    pub const simpleEscape = literals_m.simpleEscape;
    pub const charNode = literals_m.charNode;
    pub const subExpr = literals_m.subExpr;
    pub const stringNode = literals_m.stringNode;
    pub const reference = literals_m.reference;
    pub const printArg = literals_m.printArg;
    pub const matchBrace = literals_m.matchBrace;
    pub const formatPercent = literals_m.formatPercent;
    pub const textLiteral = literals_m.textLiteral;
    // ------------------------------------------------------------ parser/routines.zig
    pub const typeName = routines_m.typeName;
    pub const params = routines_m.params;
    pub const routine = routines_m.routine;
    pub const routineOf = routines_m.routineOf;
    // ------------------------------------------------------------ parser/expr.zig
    pub const expr = expr_m.expr;
    pub const orExpr = expr_m.orExpr;
    pub const xorExpr = expr_m.xorExpr;
    pub const andExpr = expr_m.andExpr;
    pub const notExpr = expr_m.notExpr;
    pub const compare = expr_m.compare;
    pub const compareOp = expr_m.compareOp;
    pub const range = expr_m.range;
    pub const additive = expr_m.additive;
    pub const multiplicative = expr_m.multiplicative;
    pub const unary = expr_m.unary;
    pub const power = expr_m.power;
    pub const postfix = expr_m.postfix;
    pub const indexList = expr_m.indexList;
    pub const item = expr_m.item;
    pub const conditional = expr_m.conditional;
    pub const items = expr_m.items;
    pub const group = expr_m.group;
    pub const isLambda = expr_m.isLambda;
    pub const primary = expr_m.primary;
    // ------------------------------------------------------------ parser/statements.zig
    pub const block = statements_m.block;
    pub const endSimple = statements_m.endSimple;
    pub const assignOp = statements_m.assignOp;
    pub const declaration = statements_m.declaration;
    pub const letStatement = statements_m.letStatement;
    pub const loopTail = statements_m.loopTail;
    pub const refuseThen = statements_m.refuseThen;
    pub const closeLabel = statements_m.closeLabel;
    pub const whileLoop = statements_m.whileLoop;
    pub const forLoop = statements_m.forLoop;
    pub const loopBlock = statements_m.loopBlock;
    pub const ifStatement = statements_m.ifStatement;
    pub const matchStatement = statements_m.matchStatement;
    pub const isYieldStatement = statements_m.isYieldStatement;
    pub const isSqlFunction = statements_m.isSqlFunction;
    pub const sqlFunction = statements_m.sqlFunction;
    pub const sqlType = statements_m.sqlType;
    pub const isTableDecl = statements_m.isTableDecl;
    pub const tableDecl = statements_m.tableDecl;
    pub const isGeneratorDecl = statements_m.isGeneratorDecl;
    pub const statement = statements_m.statement;
    pub const process = statements_m.process;
    // ------------------------------------------------------------ parser/classes.zig
    pub const functionType = classes_m.functionType;
    pub const class = classes_m.class;
    pub const typeParams = classes_m.typeParams;
    pub const typeList = classes_m.typeList;
    pub const trait = classes_m.trait;
    pub const adopt = classes_m.adopt;
    // ------------------------------------------------------------ parser/modules.zig
    pub const declarationInDriver = modules_m.declarationInDriver;
    pub const importDecl = modules_m.importDecl;
    pub const exportDecl = modules_m.exportDecl;
    pub const module = modules_m.module;
    pub const applyStatement = modules_m.applyStatement;
    pub const startStatement = modules_m.startStatement;
    // ------------------------------------------------------------ parser/aspects.zig
    pub const parallelBlock = aspects_m.parallelBlock;
    pub const isAspectStart = aspects_m.isAspectStart;
    pub const aspect = aspects_m.aspect;
    pub const looksLikeMacro = aspects_m.looksLikeMacro;
    pub const macro = aspects_m.macro;
    pub const script = aspects_m.script;
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
