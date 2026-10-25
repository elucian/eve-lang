//! @eve-module evecp.lint: unused names in a source file (`eve lint`)
//! @spec spec/semantics/tools.md#eve-lint
//! @feature F-TLS-08
//! @tests test/level4/d47_lint_command, code/evecp/src/lint.zig
//! A name is judged by its text inside the routine that declares it (a shadowing name hides an unused one: the tool errs on the side of silence). A name that starts with `_` is meant to be unused.
const std = @import("std");
const ast = @import("evecm").ast;
const Node = ast.Node;

pub const Finding = struct { line: u32, col: u32, name: []const u8, what: []const u8 };

const Decl = struct { name: []const u8, line: u32, col: u32, what: []const u8 };

const Names = std.StringHashMapUnmanaged(void);

const Linter = struct {
    gpa: std.mem.Allocator,
    decls: std.ArrayList(Decl) = .empty,
    uses: Names = .empty,

    fn use(l: *Linter, name: []const u8) std.mem.Allocator.Error!void {
        try l.uses.put(l.gpa, name, {});
    }

    fn declare(l: *Linter, n: *const Node, what: []const u8) std.mem.Allocator.Error!void {
        if (n.text.len == 0 or n.text[0] == '_') return;
        try l.decls.append(l.gpa, .{ .name = n.text, .line = n.line, .col = n.col, .what = what });
    }

    fn pattern(l: *Linter, n: *const Node) std.mem.Allocator.Error!void {
        switch (n.tag) {
            .name => try l.declare(n, "loop variable"),
            .star => try l.declare(n, "loop variable"),
            else => for (n.kids) |k| try l.pattern(k),
        }
    }

    fn walk(l: *Linter, n: *const Node) std.mem.Allocator.Error!void {
        switch (n.tag) {
            .name, .ref => try l.use(n.text),
            .targets => for (n.kids) |t| switch (t.tag) {
                .name, .star => try l.declare(t, "variable"),
                else => try l.walk(t),
            },
            .assign => {
                // `let x := v;` writes x; `x += 1`, `x[1] := v` and `x.f := v` also read it
                const target = n.kids[0];
                const writes_only = target.tag == .name and (std.mem.eql(u8, n.text, ":=") or std.mem.eql(u8, n.text, "::"));
                if (!writes_only) try l.walk(target);
                try l.walk(n.kids[1]);
            },
            .for_ => {
                try l.pattern(n.kids[0]);
                for (n.kids[1..]) |k| try l.walk(k);
            },
            .lambda => try l.walk(n.kids[1]),
            .field => for (n.kids) |k| try l.walk(k),
            else => for (n.kids) |k| try l.walk(k),
        }
    }
};

fn isRoutine(tag: ast.Tag) bool {
    return switch (tag) {
        .function, .procedure, .method, .constructor, .destructor, .generator, .process => true,
        else => false,
    };
}

fn lessFinding(_: void, a: Finding, b: Finding) bool {
    return if (a.line != b.line) a.line < b.line else a.col < b.col;
}

/// Judge one routine: its parameters (functions and procedures only: a method may have to take what it does not use, a process takes the command line), its variables and loop variables.
fn routine(gpa: std.mem.Allocator, n: *const Node, out: *std.ArrayList(Finding)) std.mem.Allocator.Error!void {
    if (n.is_external) return; // a signature has no body to judge
    var l: Linter = .{ .gpa = gpa };
    defer l.decls.deinit(gpa);
    defer l.uses.deinit(gpa);
    if (n.tag == .function or n.tag == .procedure or n.tag == .generator) {
        for (n.kids[0].kids) |p| {
            if (!std.mem.eql(u8, p.text, "self")) try l.declare(p, "parameter");
            for (p.kids) |k| try l.walk(k); // the default value
        }
    }
    const body_from: usize = if (n.tag == .process) 0 else 3;
    for (n.kids[@min(body_from, n.kids.len)..]) |k| {
        if (n.tag == .process and k.tag == .params) continue;
        try l.walk(k);
    }
    // the results of a function are named by the signature: they are never judged
    for (l.decls.items) |d| {
        if (l.uses.contains(d.name)) continue;
        try out.append(gpa, .{ .line = d.line, .col = d.col, .name = d.name, .what = d.what });
    }
}

fn visit(gpa: std.mem.Allocator, n: *const Node, out: *std.ArrayList(Finding)) std.mem.Allocator.Error!void {
    if (isRoutine(n.tag)) try routine(gpa, n, out);
    for (n.kids) |k| try visit(gpa, k, out);
}

fn allUses(gpa: std.mem.Allocator, n: *const Node, set: *Names) std.mem.Allocator.Error!void {
    if (n.tag == .name or n.tag == .ref) try set.put(gpa, n.text, {});
    for (n.kids) |k| try allUses(gpa, k, set);
}

fn imports(gpa: std.mem.Allocator, root: *const Node, out: *std.ArrayList(Finding)) std.mem.Allocator.Error!void {
    var seen: Names = .empty;
    defer seen.deinit(gpa);
    try allUses(gpa, root, &seen);
    var stack: std.ArrayList(*const Node) = .empty;
    defer stack.deinit(gpa);
    try stack.append(gpa, root);
    while (stack.pop()) |n| {
        if (n.tag == .import_decl) {
            for (n.kids) |item| {
                if (item.public or std.mem.eql(u8, item.text, "*")) continue;
                const alias = if (item.kids.len > 0 and item.kids[0].tag == .name) item.kids[0].text else "";
                if (seen.contains(item.text) or (alias.len > 0 and seen.contains(alias))) continue;
                try out.append(gpa, .{ .line = item.line, .col = item.col, .name = item.text, .what = "import" });
            }
            continue;
        }
        for (n.kids) |k| try stack.append(gpa, k);
    }
}

// @eve-fn cp.lint
// @spec spec/semantics/tools.md#eve-lint
/// The unused names of a tree, in the order of the source. The names point into the tree; free the list with `gpa`.
pub fn lint(gpa: std.mem.Allocator, root: *const Node) std.mem.Allocator.Error![]Finding {
    var out: std.ArrayList(Finding) = .empty;
    errdefer out.deinit(gpa);
    try visit(gpa, root, &out);
    try imports(gpa, root, &out);
    std.mem.sort(Finding, out.items, {}, lessFinding);
    return out.toOwnedSlice(gpa);
}
