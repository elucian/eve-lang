//! Static check: the pass between the parser and the interpreter. Eve is a compiler first: it
//! analyzes the whole script before it runs anything (D-110). This pass finds, without running the
//! script: an undefined name, a name declared twice in one scope, a `let` of a name that was never
//! declared, a procedure used as a value, a mandatory parameter given by position after optional
//! ones (D-106), a private method called from outside its class, an attribute added from outside
//! (Q-019h), and a string added to a number (D-080). The first problem stops the check, like the
//! parser, and the script does not start (exit 65).
const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");

const Node = ast.Node;
pub const Diag = lexer.Diag;
pub const Error = lexer.Error;

// Zig tip: an `enum` with a few names is the clearest way to say "what kind of thing is this".
// `?[]const u8` is a text or nothing: the type name that the check could work out, or null when it
// does not know (then it says nothing: the check never guesses).
const Kind = enum { variable, constant, function, procedure, class, param, builtin };

const Info = struct { kind: Kind, ty: ?[]const u8 = null, node: ?*const Node = null };

// Zig tip: `std.StringHashMapUnmanaged(V)` is a hash map whose keys are strings; "unmanaged" means
// it does not remember its allocator, so every call that may allocate gets it (`put(a, k, v)`).
// `.empty` is its empty value, like the lists in the other files.
const Frame = struct {
    names: std.StringHashMapUnmanaged(Info) = .empty,
};

// The names every script knows: the types, the constants and the functions of the library.
const builtins = std.StaticStringMap(void).initComptime(.{
    .{"True"},    .{"False"},  .{"Null"},    .{"null"},    .{"nil"},     .{"_"},       .{"type"},
    .{"floor"},   .{"ceiling"}, .{"round"},  .{"abs"},     .{"min"},     .{"max"},     .{"sqrt"},
    .{"Integer"}, .{"Natural"}, .{"Real"},   .{"Symbol"},  .{"Rune"},    .{"String"},  .{"Text"},
    .{"Logic"},   .{"List"},    .{"Array"},  .{"DataSet"}, .{"DataMap"}, .{"HashMap"}, .{"Object"},
    .{"Byte"},    .{"Short"},   .{"Huge"},   .{"Float"},   .{"Decimal"}, .{"Ordinal"}, .{"Function"},
    .{"Range"},   .{"jobs"},    .{"other"},
});

const Checker = struct {
    a: std.mem.Allocator,
    diag: *Diag,
    frames: std.ArrayList(Frame) = .empty,
    /// The class whose method or constructor is being checked (private members are visible there).
    in_class: ?[]const u8 = null,
    /// Every class of the script by name, for the methods of `obj.method()`.
    classes: std.StringHashMapUnmanaged(*const Node) = .empty,

    // Zig tip: `fail` fills the `Diag` and returns the error, as in the parser, so a caller writes
    // `return c.fail(n, "...", .{})`. `comptime fmt` is checked against `args` by the compiler.
    fn fail(c: *Checker, n: *const Node, comptime fmt: []const u8, args: anytype) Error {
        c.diag.set(n.line, n.col, fmt, args);
        return error.Syntax;
    }

    fn push(c: *Checker) Error!void {
        try c.frames.append(c.a, .{});
    }

    fn pop(c: *Checker) void {
        _ = c.frames.pop();
    }

    // Zig tip: a loop that walks the list from the end uses an index that counts down; `while (i > 0)
    // { i -= 1; ... }` reads the last frame first, the innermost scope.
    fn lookup(c: *Checker, name: []const u8) ?Info {
        var i = c.frames.items.len;
        while (i > 0) {
            i -= 1;
            if (c.frames.items[i].names.get(name)) |info| return info;
        }
        return null;
    }

    fn declare(c: *Checker, at: *const Node, name: []const u8, info: Info) Error!void {
        if (std.mem.eql(u8, name, "_")) return;
        const frame = &c.frames.items[c.frames.items.len - 1];
        if (frame.names.contains(name)) return c.fail(at, "'{s}' is already declared in this scope", .{name});
        try frame.names.put(c.a, name, info);
    }

    // Zig tip: `name[0] == '$'` looks at the first byte. A system variable such as `$epsilon` or
    // `$error` always exists and a driver may create its own (D-109), so it is never undefined.
    fn resolve(c: *Checker, at: *const Node, name: []const u8) Error!Info {
        if (name.len > 0 and name[0] == '$') return .{ .kind = .variable };
        if (c.lookup(name)) |info| return info;
        if (builtins.has(name)) return .{ .kind = .builtin };
        return c.fail(at, "undefined name '{s}'", .{name});
    }

    fn isNumeric(ty: ?[]const u8) bool {
        const t = ty orelse return false;
        return std.mem.eql(u8, t, "Integer") or std.mem.eql(u8, t, "Real");
    }

    fn isString(ty: ?[]const u8) bool {
        const t = ty orelse return false;
        return std.mem.eql(u8, t, "String");
    }

    // ---- expressions ------------------------------------------------------------------------

    // Zig tip: a recursive function that returns `Error!?[]const u8` returns an error union of an
    // optional: `try` unwraps the error, the caller still has the optional type name.
    /// Check an expression and return its type when the check knows it.
    fn expr(c: *Checker, n: *const Node) Error!?[]const u8 {
        switch (n.tag) {
            .num => {
                for (n.text) |ch| if (ch == '.') return "Real";
                for (n.text) |ch| if (std.ascii.isAlphabetic(ch)) return null;
                return "Integer";
            },
            .str, .text_lit, .interp => {
                for (n.kids) |k| if (k.tag == .fmt) {
                    _ = try c.expr(k.kids[0]);
                };
                return "String";
            },
            .chr => return "Rune",
            .name, .ref => return (try c.resolve(n, n.text)).ty,
            .bin => return c.binary(n),
            .un => return c.expr(n.kids[0]),
            .range => {
                for (n.kids) |k| if (k.tag != .open_end) {
                    _ = try c.expr(k);
                };
                return null;
            },
            .cond => {
                for (n.kids) |k| _ = try c.expr(k);
                return null;
            },
            .pair => {
                // `name: value`: a name before the colon is a parameter or a key, not a variable
                if (n.kids[0].tag != .name) _ = try c.expr(n.kids[0]);
                _ = try c.expr(n.kids[1]);
                return null;
            },
            .list, .array, .brace, .index, .spread, .field => {
                for (n.kids) |k| _ = try c.expr(k);
                return null;
            },
            .builder => return c.builder(n),
            .call => return c.call(n, false),
            .lambda => {
                try c.push();
                defer c.pop();
                try c.params(n.kids[0]);
                _ = try c.expr(n.kids[1]);
                return null;
            },
            .dollar, .all, .open_end, .none => return null,
            else => return null,
        }
    }

    fn binary(c: *Checker, n: *const Node) Error!?[]const u8 {
        const op = n.text;
        // `x =~ b +- t`: the right side is a tolerance, checked as a range
        const lt = try c.expr(n.kids[0]);
        const rt = try c.expr(n.kids[1]);
        if (std.mem.eql(u8, op, "+") and ((isString(lt) and isNumeric(rt)) or (isNumeric(lt) and isString(rt)))) {
            return c.fail(n, "'+' does not add a string and a number: use '<+' to append a number as text", .{});
        }
        if (std.mem.eql(u8, op, "+") and isString(lt) and isString(rt)) return "String";
        const cmp = [_][]const u8{ "==", "<>", "<", ">", "<=", ">=", "=~", "and", "or", "xor", "in", "not in", "is", "is not" };
        for (cmp) |o| if (std.mem.eql(u8, op, o)) return "Logic";
        if (isNumeric(lt) and isNumeric(rt)) {
            if (std.mem.eql(u8, op, "/")) return "Real";
            return if (std.mem.eql(u8, lt.?, "Real") or std.mem.eql(u8, rt.?, "Real")) "Real" else "Integer";
        }
        return null;
    }

    // Zig tip: `(x | x in (1..10) and x % 2 == 0)` names `x` in its generator, after the bar. The
    // names of the generators are declared first, in a scope of their own, then the item is checked.
    fn builder(c: *Checker, n: *const Node) Error!?[]const u8 {
        try c.push();
        defer c.pop();
        try c.generators(n.kids[1]);
        _ = try c.expr(n.kids[0]);
        return null;
    }

    fn generators(c: *Checker, g: *const Node) Error!void {
        if (g.tag == .bin and std.mem.eql(u8, g.text, "and")) {
            try c.generators(g.kids[0]);
            try c.generators(g.kids[1]);
        } else if (g.tag == .bin and std.mem.eql(u8, g.text, "in")) {
            _ = try c.expr(g.kids[1]);
            try c.pattern(g.kids[0]);
        } else _ = try c.expr(g);
    }

    /// Declare the names of a loop or builder pattern: `x`, `(a, b)`, `*rest`.
    fn pattern(c: *Checker, p: *const Node) Error!void {
        switch (p.tag) {
            .name => try c.declare(p, p.text, .{ .kind = .variable }),
            .list, .pair => for (p.kids) |k| try c.pattern(k), // `(a, b)` and `(key: value)`
            .star => if (p.text.len > 0) try c.declare(p, p.text, .{ .kind = .variable }),
            else => {},
        }
    }

    // ---- calls ------------------------------------------------------------------------------

    /// A call. `as_statement` is true for `foo(1);`, the only place where a procedure may be called.
    fn call(c: *Checker, n: *const Node, as_statement: bool) Error!?[]const u8 {
        const callee = n.kids[0];
        const args = n.kids[1..];
        var result: ?[]const u8 = null;
        if (callee.tag == .name) {
            const info = try c.resolve(callee, callee.text);
            switch (info.kind) {
                .procedure => if (!as_statement) {
                    return c.fail(n, "the procedure '{s}' returns nothing: it can't be used in an expression", .{callee.text});
                },
                .class => result = callee.text,
                else => {},
            }
            if (info.node) |target| try c.order(n, target, args);
        } else if (callee.tag == .field) {
            const obj_ty = try c.expr(callee.kids[0]);
            if (obj_ty) |t| try c.method(n, t, callee.text);
        } else _ = try c.expr(callee);
        for (args) |a| _ = try c.expr(a);
        return result;
    }

    // Zig tip: `std.mem.eql(u8, a, b)` compares two texts. A private method (the default, D-085) may
    // be called only inside its class or a subclass; `in_class` says where the check is now.
    /// `obj.name()` where the type of `obj` is a known class: the method must be public here.
    fn method(c: *Checker, n: *const Node, class_name: []const u8, name: []const u8) Error!void {
        var cur: ?[]const u8 = class_name;
        while (cur) |cn| {
            const cls = c.classes.get(cn) orelse return;
            for (cls.kids[2..]) |m| {
                if (m.tag != .method and m.tag != .function) continue;
                if (!std.mem.eql(u8, m.text, name)) continue;
                if (m.public) return;
                if (c.in_class) |here| if (std.mem.eql(u8, here, cn)) return;
                return c.fail(n, "'{s}' is private to the class {s}", .{ name, cn });
            }
            cur = if (cls.kids[1].tag == .name) cls.kids[1].text else null;
        }
    }

    // Zig tip: a position counter that skips the named arguments (`pair` nodes) finds which
    // parameter each positional argument reaches. A mandatory parameter that comes after an
    // optional one must be named (D-106): giving it by position is an error.
    /// The arguments of a call to `routine`: positional first, a late mandatory parameter by name.
    fn order(c: *Checker, n: *const Node, target: *const Node, args: []const *const Node) Error!void {
        const plist = target.kids[0].kids;
        var seen_optional = false;
        for (plist, 0..) |prm, i| {
            if (prm.tag == .vararg_param) return;
            const optional = prm.kids[0].tag != .none;
            if (optional) seen_optional = true;
            var given_by_position = false;
            var count: usize = 0;
            for (args) |a| {
                if (a.tag == .pair) continue;
                if (count == i) given_by_position = true;
                count += 1;
            }
            if (given_by_position and !optional and seen_optional) {
                return c.fail(n, "the parameter '{s}' follows optional parameters: give it by name, {s}: ...", .{ prm.text, prm.text });
            }
        }
    }

    // ---- declarations -----------------------------------------------------------------------

    /// Declare the parameters of a subprogram, a lambda or a process in the current scope.
    fn params(c: *Checker, list: *const Node) Error!void {
        for (list.kids) |prm| {
            const ty: ?[]const u8 = if (prm.ty) |t| t.text else null;
            try c.declare(prm, prm.text, .{ .kind = .param, .ty = ty });
        }
    }

    /// The body of a function, a procedure, a method or a constructor, in its own scope.
    fn routine(c: *Checker, r: *const Node, class_name: ?[]const u8) Error!void {
        try c.push();
        defer c.pop();
        const saved = c.in_class;
        defer c.in_class = saved;
        if (class_name) |cn| c.in_class = cn;
        try c.params(r.kids[0]);
        for (r.kids[2].kids) |res| {
            if (c.frames.items[c.frames.items.len - 1].names.contains(res.text)) continue; // `(@self)` repeats the parameter
            const ty: ?[]const u8 = if (res.ty) |t| t.text else null;
            // `self` of a method or a constructor has the type of its class
            try c.declare(res, res.text, .{ .kind = .variable, .ty = if (std.mem.eql(u8, res.text, "self")) class_name else ty });
        }
        if (r.tag == .method and r.kids[0].kids.len > 0 and r.kids[0].kids[0].ty == null) {
            // a method inside a class: `@self` without a type is an object of that class
            if (class_name) |cn| try c.retypeSelf(r, cn);
        }
        try c.block(r.kids[3]);
    }

    fn retypeSelf(c: *Checker, r: *const Node, class_name: []const u8) Error!void {
        const frame = &c.frames.items[c.frames.items.len - 1];
        if (frame.names.getPtr("self")) |info| info.ty = class_name;
        _ = r;
    }

    // ---- statements -------------------------------------------------------------------------

    fn block(c: *Checker, b: *const Node) Error!void {
        if (b.tag == .none) return;
        for (b.kids) |s| try c.statement(s);
    }

    /// The name at the root of an assignment target: `a`, `a[i]`, `a.x`, `a.x[i]`.
    fn root(t: *const Node) *const Node {
        var cur = t;
        while ((cur.tag == .field or cur.tag == .index) and cur.kids.len > 0) cur = cur.kids[0];
        return cur;
    }

    fn statement(c: *Checker, s: *const Node) Error!void {
        switch (s.tag) {
            .var_decl, .set => try c.declaration(s),
            .assign => {
                const value = s.kids[1];
                _ = try c.expr(value);
                const target = s.kids[0];
                if (std.mem.eql(u8, s.text, "+>")) {
                    _ = try c.expr(target); // `let x +> lst;`: the left side is the element
                    return;
                }
                const r = root(target);
                if (r.tag == .name) {
                    const info = try c.resolve(r, r.text);
                    if (info.kind == .constant and target.tag == .name) return c.fail(s, "'{s}' is a constant", .{r.text});
                }
                if (target.tag != .name) _ = try c.expr(target);
            },
            .capture => {
                _ = try c.expr(s.kids[0]);
                const target = s.kids[1];
                if (target.tag == .name and !std.mem.eql(u8, target.text, "_")) {
                    const frame = &c.frames.items[c.frames.items.len - 1];
                    if (s.kids[2].tag == .none) {
                        try c.declare(target, target.text, .{ .kind = .variable });
                    } else if (c.lookup(target.text) == null and !frame.names.contains(target.text)) {
                        try c.declare(target, target.text, .{ .kind = .variable });
                    }
                } else if (target.tag != .name) _ = try c.expr(target);
            },
            .print_stmt, .write_stmt, .expect_stmt, .assert_stmt, .raise_stmt => {
                for (s.kids) |k| _ = try c.expr(k);
            },
            .cond_stmt => {
                _ = try c.expr(s.kids[0]);
                try c.statement(s.kids[1]);
            },
            .defer_stmt => try c.statement(s.kids[0]),
            .expr_stmt => {
                const e = s.kids[0];
                if (e.tag == .call) {
                    _ = try c.call(e, true);
                } else _ = try c.expr(e);
            },
            .block => try c.block(s),
            .if_ => {
                var i: usize = 0;
                while (i + 1 < s.kids.len) : (i += 2) {
                    _ = try c.expr(s.kids[i]);
                    try c.block(s.kids[i + 1]);
                }
                if (s.kids.len % 2 == 1) try c.block(s.kids[s.kids.len - 1]);
            },
            .while_ => {
                try c.push();
                defer c.pop();
                try c.block(s.kids[0]);
                _ = try c.expr(s.kids[1]);
                for (s.kids[2..]) |b| try c.block(b);
            },
            .for_ => {
                _ = try c.expr(s.kids[1]);
                try c.push();
                defer c.pop();
                try c.pattern(s.kids[0]);
                for (s.kids[2..]) |b| try c.block(b);
            },
            .repeat_ => {
                try c.push();
                defer c.pop();
                try c.block(s.kids[0]);
                try c.block(s.kids[1]);
                if (s.kids.len > 2) _ = try c.expr(s.kids[2]);
            },
            .match_ => {
                _ = try c.expr(s.kids[0]);
                try c.push();
                defer c.pop();
                for (s.kids[2..]) |w| {
                    for (w.kids[0].kids) |p| _ = try c.expr(p);
                    try c.block(w.kids[1]);
                }
                try c.block(s.kids[1]);
            },
            .job => {
                try c.push();
                defer c.pop();
                try c.block(s.kids[0]);
            },
            else => {},
        }
    }

    // Zig tip: the value is checked before the names are declared, so `new x := x + 1;` does not see
    // the new `x`. A declaration with a field target (`new p.z := 7;`) adds an attribute: only a
    // method or a constructor may do it, and only to `self` (Q-019h, D-096).
    fn declaration(c: *Checker, s: *const Node) Error!void {
        var vt: ?[]const u8 = null;
        if (s.kids[1].tag != .none) vt = try c.expr(s.kids[1]);
        const targets = s.kids[0].kids;
        const hint: ?[]const u8 = if (s.ty) |t| t.text else null;
        for (targets) |t| {
            switch (t.tag) {
                .name => {
                    const ty = hint orelse (if (targets.len == 1 and !std.mem.eql(u8, s.text, "::")) vt else if (targets.len == 1) vt else null);
                    try c.declare(t, t.text, .{ .kind = if (s.tag == .set) .constant else .variable, .ty = ty });
                },
                .star => if (t.text.len > 0) try c.declare(t, t.text, .{ .kind = .variable }),
                .field => {
                    const r = root(t);
                    if (c.in_class == null or r.tag != .name or !std.mem.eql(u8, r.text, "self")) {
                        return c.fail(t, "code outside a class can't add the attribute '{s}' to an object", .{t.text});
                    }
                },
                else => {},
            }
        }
    }

    // ---- the script -------------------------------------------------------------------------

    /// Declare, before anything is checked, what a driver declares: they may come in any order (D-041).
    fn declareMembers(c: *Checker, members: []const *const Node) Error!void {
        for (members) |m| {
            switch (m.tag) {
                .class => {
                    try c.declare(m, m.text, .{ .kind = .class, .node = m });
                    try c.classes.put(c.a, m.text, m);
                    if (m.kids[1].tag == .name and std.mem.eql(u8, m.kids[1].text, "Ordinal")) {
                        // the values of an ordinal that start with a capital letter need no qualifier
                        for (m.kids[0].kids) |v| {
                            if (v.text.len > 0 and std.ascii.isUpper(v.text[0])) try c.declare(v, v.text, .{ .kind = .constant });
                        }
                    }
                },
                .function => try c.declare(m, m.text, .{ .kind = .function, .node = m }),
                .procedure => try c.declare(m, m.text, .{ .kind = .procedure, .node = m }),
                .var_decl, .set => {
                    const hint: ?[]const u8 = if (m.ty) |t| t.text else null;
                    for (m.kids[0].kids) |t| if (t.tag == .name) {
                        try c.declare(t, t.text, .{ .kind = if (m.tag == .set) .constant else .variable, .ty = hint });
                    };
                },
                else => {},
            }
        }
    }

    fn driver(c: *Checker, root_node: *const Node) Error!void {
        try c.push();
        try c.declareMembers(root_node.kids);
        for (root_node.kids) |m| {
            switch (m.tag) {
                .class => {
                    for (m.kids[2..]) |r| try c.routine(r, m.text);
                },
                .function, .procedure, .method => try c.routine(m, null),
                .var_decl, .set => if (m.kids[1].tag != .none) {
                    _ = try c.expr(m.kids[1]);
                },
                .process => {
                    try c.push();
                    defer c.pop();
                    try c.params(m.kids[3]);
                    try c.block(m.kids[0]);
                    try c.block(m.kids[1]);
                    try c.block(m.kids[2]);
                },
                else => {},
            }
        }
    }
};

// Zig tip: `check` is the one public function: it makes the checker, runs it on the tree and
// returns `error.Syntax` with the `Diag` filled when something is wrong. The checker allocates
// from the arena of the parse (frames, maps), freed together with the tree.
/// Check a parsed script. A driver is checked as a whole; a free script statement by statement.
pub fn check(arena: std.mem.Allocator, tree: *const Node, diag: *Diag) Error!void {
    var c: Checker = .{ .a = arena, .diag = diag };
    if (tree.tag == .driver) return c.driver(tree);
    try c.push();
    for (tree.kids) |s| try c.statement(s);
}

// Zig tip: a test of a pass that is part of `parse` goes through `parse`: the script is parsed and
// then checked, and `expectError` proves the whole chain refuses it. `d.message()` is the text
// that the compiler would print. Two files may import each other in Zig: `check.zig` is used by
// `parser.zig`, and this test uses `parser.zig` back.
test "an undefined name and a redeclared name are refused" {
    const parser = @import("parser.zig");
    var d: Diag = .{};
    try std.testing.expectError(error.Syntax, parser.check(std.testing.allocator, "driver a is process main is print y; return; end a;", &d));
    try std.testing.expectEqualStrings("undefined name 'y'", d.message());
    try std.testing.expectError(error.Syntax, parser.check(std.testing.allocator, "driver a is process main is new x := 1; new x := 2; return; end a;", &d));
    try std.testing.expectEqualStrings("'x' is already declared in this scope", d.message());
}

// Zig tip: the same helper `parser.check` returns nothing when the script is accepted, so `try`
// alone is the assertion.
test "a correct script passes, a let of a missing name does not" {
    const parser = @import("parser.zig");
    var d: Diag = .{};
    try parser.check(std.testing.allocator, "driver a is process main is new x := 1; let x += 2; new l := (1, 2); let l -> e; print e; return; end a;", &d);
    try std.testing.expectError(error.Syntax, parser.check(std.testing.allocator, "driver a is process main is let y := 5; return; end a;", &d));
}

// Zig tip: a procedure has no value, so using it in an expression is refused before the run.
test "a procedure is a statement, and a late mandatory parameter is named" {
    const parser = @import("parser.zig");
    var d: Diag = .{};
    try std.testing.expectError(error.Syntax, parser.check(std.testing.allocator, "driver a is procedure hi is return; process main is new v := hi(); return; end a;", &d));
    try std.testing.expectError(error.Syntax, parser.check(std.testing.allocator, "driver a is procedure add(p = 0: Integer, @o: Integer) is return; process main is new r: Integer; add(1, @r); return; end a;", &d));
    try parser.check(std.testing.allocator, "driver a is procedure add(p = 0: Integer, @o: Integer) is return; process main is new r: Integer; add(1, o: @r); return; end a;", &d);
}
