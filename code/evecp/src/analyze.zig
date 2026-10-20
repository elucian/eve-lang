//! @eve-module evecp.analyze
//! @spec spec/syntax/grammar.md
//! @feature F-TLS-19, F-TLS-24
//! @decision D-198
//! @tests code/evecp/src/analyze.zig
//! The entry point of the tools (TD-34): one call, a text in, what an editor shows out. The diagnostics (an error with its
//! line, column and message) and the outline (the aspects, modules, classes, subprograms and tables of the text, with their
//! positions and nesting). `evetx` and `eveux` call it while the person types; `evecp outline` and `evecp symbols` print it.
//!
//! Limits of this version: the parser stops at its first error, so a text with a syntax error has one diagnostic and no
//! outline. A text that is Eve but breaks a rule of the checker has that one diagnostic and its full outline. The checks look
//! at one text alone (as `eve check` does), so a name that only another file defines is reported.
const std = @import("std");
const evecm = @import("evecm");
const parser = @import("parser.zig");
const check = @import("check.zig");

const Node = evecm.ast.Node;
const Tag = evecm.ast.Tag;

/// What kind of problem a diagnostic is.
pub const Kind = enum {
    /// The text is not Eve (the parser stopped).
    syntax,
    /// The text is Eve but breaks a rule of the language (names, scopes, types, overloads).
    semantic,
};

/// One problem, at a place of the text (both numbers start at 1).
pub const Diagnostic = struct {
    kind: Kind,
    line: u32,
    col: u32,
    message: []const u8,
};

/// What a symbol of the outline is.
pub const SymbolKind = enum { aspect, module, class, trait, process, function, procedure, method, constructor, destructor, generator, table, import, member };

/// One entry of the outline.
pub const Symbol = struct {
    name: []const u8,
    kind: SymbolKind,
    line: u32,
    col: u32,
    /// The place in `Analysis.symbols` of the symbol that contains this one; null at the top level.
    parent: ?u32,
};

/// The result of `analyze`. Everything in it lives in `arena`: `deinit` frees it all.
pub const Analysis = struct {
    arena: std.heap.ArenaAllocator,
    diagnostics: []const Diagnostic,
    symbols: []const Symbol,

    pub fn deinit(a: *Analysis) void {
        a.arena.deinit();
    }
};

fn symbolKind(tag: Tag) ?SymbolKind {
    return switch (tag) {
        .aspect => .aspect,
        .module => .module,
        .class => .class,
        .trait => .trait,
        .process => .process,
        .function => .function,
        .procedure => .procedure,
        .method => .method,
        .constructor => .constructor,
        .destructor => .destructor,
        .generator => .generator,
        .table_decl => .table,
        .import_decl => .import,
        .member => .member,
        else => null,
    };
}

/// Only these nodes hold declarations: the walk does not enter statements and expressions.
fn isContainer(tag: Tag) bool {
    return switch (tag) {
        .aspect, .module, .class, .trait, .region => true,
        else => false,
    };
}

fn walk(arena: std.mem.Allocator, list: *std.ArrayList(Symbol), node: *const Node, parent: ?u32) std.mem.Allocator.Error!void {
    for (node.kids) |kid| {
        var next = parent;
        if (symbolKind(kid.tag)) |kind| {
            const name = if ((kind == .constructor or kind == .destructor) and kid.text.len == 0 and parent != null) list.items[parent.?].name else kid.text;
            try list.append(arena, .{ .name = name, .kind = kind, .line = kid.line, .col = kid.col, .parent = parent });
            next = @intCast(list.items.len - 1);
        }
        if (isContainer(kid.tag)) try walk(arena, list, kid, next);
    }
}

/// Analyze a text. Errors in the text are in the result, not in the error set: only running out of memory fails.
// @eve-fn cp.analyze
// @feature F-TLS-19
// @test analyze gives the outline of a script and the error of a broken one
pub fn analyze(gpa: std.mem.Allocator, source: []const u8) std.mem.Allocator.Error!Analysis {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    errdefer arena.deinit();
    const a = arena.allocator();
    var diagnostics: std.ArrayList(Diagnostic) = .empty;
    var symbols: std.ArrayList(Symbol) = .empty;

    var diag: parser.Diag = .{};
    if (parser.parseSyntax(a, source, &diag)) |tree| {
        // the root of a file is the aspect or the module itself
        var top: ?u32 = null;
        if (symbolKind(tree.tag)) |kind| {
            try symbols.append(a, .{ .name = tree.text, .kind = kind, .line = tree.line, .col = tree.col, .parent = null });
            top = 0;
        }
        try walk(a, &symbols, tree, top);
        var cdiag: check.Diag = .{};
        check.check(a, tree, &cdiag) catch |err| switch (err) {
            error.Syntax => try diagnostics.append(a, .{ .kind = .semantic, .line = cdiag.line, .col = cdiag.col, .message = try a.dupe(u8, cdiag.message()) }),
            error.OutOfMemory => return error.OutOfMemory,
        };
    } else |err| switch (err) {
        error.Syntax => try diagnostics.append(a, .{ .kind = .syntax, .line = diag.line, .col = diag.col, .message = try a.dupe(u8, diag.message()) }),
        error.OutOfMemory => return error.OutOfMemory,
    }
    return .{ .arena = arena, .diagnostics = diagnostics.items, .symbols = symbols.items };
}

// @test analyze gives the outline of a script and the error of a broken one
test "analyze gives the outline of a script and the error of a broken one" {
    const good =
        \\primary aspect shop is
        \\  class Item = {id: Integer, name: String};
        \\  function double(x: Integer) => (@r: Integer) is
        \\    let r := x * 2;
        \\  return;
        \\  process main is
        \\    over;
        \\  return;
        \\end shop;
        \\
    ;
    var ok = try analyze(std.testing.allocator, good);
    defer ok.deinit();
    try std.testing.expectEqual(@as(usize, 0), ok.diagnostics.len);
    try std.testing.expect(ok.symbols.len >= 4);
    try std.testing.expectEqualStrings("shop", ok.symbols[0].name);
    try std.testing.expectEqual(SymbolKind.aspect, ok.symbols[0].kind);
    try std.testing.expectEqual(@as(?u32, null), ok.symbols[0].parent);
    var found_process = false;
    for (ok.symbols) |s| {
        if (s.kind == .process) {
            found_process = true;
            try std.testing.expectEqualStrings("main", s.name);
            try std.testing.expectEqual(@as(?u32, 0), s.parent);
        }
    }
    try std.testing.expect(found_process);

    var bad = try analyze(std.testing.allocator, "primary aspect shop is\n  process main is\n    print \"x\n");
    defer bad.deinit();
    try std.testing.expectEqual(@as(usize, 1), bad.diagnostics.len);
    try std.testing.expectEqual(Kind.syntax, bad.diagnostics[0].kind);
    try std.testing.expect(bad.diagnostics[0].line >= 1);
    try std.testing.expectEqual(@as(usize, 0), bad.symbols.len);
}

// @test a text that breaks a rule of the checker keeps its outline
test "a rule of the checker is a diagnostic and the outline stays" {
    var r = try analyze(std.testing.allocator, "primary aspect shop is\n  process main is\n    print missing_name;\n  return;\nend shop;\n");
    defer r.deinit();
    try std.testing.expectEqual(@as(usize, 1), r.diagnostics.len);
    try std.testing.expectEqual(Kind.semantic, r.diagnostics[0].kind);
    try std.testing.expectEqual(@as(u32, 3), r.diagnostics[0].line);
    try std.testing.expect(std.mem.indexOf(u8, r.diagnostics[0].message, "missing_name") != null);
    try std.testing.expectEqual(@as(usize, 2), r.symbols.len);
    try std.testing.expectEqualStrings("main", r.symbols[1].name);
}
