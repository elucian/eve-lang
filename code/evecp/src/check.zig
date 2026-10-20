//! Static check: the pass between the parser and the interpreter. Eve is a compiler first: it
//! analyzes the whole script before it runs anything (D-110). This pass finds, without running the
//! script: an undefined name, a name declared twice in one scope, a `let` of a name that was never
//! declared, a procedure used as a value, a mandatory parameter given by position after optional
//! ones (D-106), a private method called from outside its class, an attribute added from outside
//! (Q-019h), and a string added to a number (D-080). The first problem stops the check, like the
//! parser, and the script does not start (exit 65).
const std = @import("std");
const ast = @import("evecm").ast;
const lexer = @import("lexer.zig");

const Node = ast.Node;
pub const Diag = lexer.Diag;
pub const Error = lexer.Error;

const overload = @import("overload.zig");

const Kind = enum { variable, constant, function, procedure, class, param, builtin };

const Info = struct { kind: Kind, ty: ?[]const u8 = null, node: ?*const Node = null };

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
    .{"Range"},   .{"jobs"},    .{"other"},    .{"log_err"}, .{"log_wrn"}, .{"Atomic"},
    .{"Channel"}, .{"Duration"}, .{"database"}, .{"csv"}, .{"json"}, .{"Instant"}, .{"Secret"}, .{"Table"}, .{"time"}, .{"txt"}, .{"fs"}, .{"Comparable"}, .{"Printable"}, .{"Iterable"}, .{"Stream"},
});

const Checker = struct {
    a: std.mem.Allocator,
    diag: *Diag,
    frames: std.ArrayList(Frame) = .empty,
    /// The class whose method or constructor is being checked (private members are visible there).
    in_class: ?[]const u8 = null,
    /// Every class of the script by name, for the methods of `obj.method()`.
    classes: std.StringHashMapUnmanaged(*const Node) = .empty,
    /// The script being checked is an aspect: it can't `apply` another aspect (D-066).
    /// An import brings names without a prefix (`m(*)` or `*`): they are known only when the modules
    /// are read (project.zig), so an unknown name is not an error here (modules.md).
    open_names: bool = false,
    /// The call being checked is the one of `spawn` or `await`: an async subprogram may be called (D-143).
    task_call: bool = false,
    /// The value of `let self := Parent(...)` in a constructor: an abstract class may be called (D-145).
    allow_abstract: bool = false,
    /// The routine being checked is a constructor.
    in_ctor: bool = false,
    /// The functions and procedures of the root aspect by name, in order, when several share one name (D-149).
    ov: std.StringHashMapUnmanaged(std.ArrayList(*const Node)) = .empty,
    /// The `table` declarations by name (level 5).
    tables: std.StringHashMapUnmanaged(*const Node) = .empty,
    /// The type the context asks for the expression about to be checked: a type hint, the type of the target
    /// of `let`, the type of a parameter. Only a call reads it, to choose among overloads by the result (D-149).
    expected: ?[]const u8 = null,

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

    // @decision D-109
    fn resolve(c: *Checker, at: *const Node, name: []const u8) Error!Info {
        if (name.len > 0 and name[0] == '$') return .{ .kind = .variable };
        if (c.lookup(name)) |info| return info;
        if (builtins.has(name)) return .{ .kind = .builtin };
        if (c.open_names) return .{ .kind = .variable };
        return c.fail(at, "undefined name '{s}'", .{name});
    }

    /// Is `n` the name `secret` used as the library module and not declared as anything else?
    fn isSecretModule(c: *Checker, n: *const Node) bool {
        if (n.tag != .name) return false;
        // @eve-impl names of native modules that are also common variable names: a module only when no variable of that name is in scope
        // @see code/evevm/src/dlib.zig (`natives`), spec/library/registry.md
        const library = std.mem.eql(u8, n.text, "secret") or std.mem.eql(u8, n.text, "checkpoint") or
            std.mem.eql(u8, n.text, "crypto") or std.mem.eql(u8, n.text, "os") or std.mem.eql(u8, n.text, "net");
        return library and c.lookup(n.text) == null;
    }

    fn isNumeric(ty: ?[]const u8) bool {
        const t = ty orelse return false;
        return std.mem.eql(u8, t, "Integer") or std.mem.eql(u8, t, "Real");
    }

    fn isType(ty: ?[]const u8, name: []const u8) bool {
        const t = ty orelse return false;
        return std.mem.eql(u8, t, name);
    }

    fn isDecimalLiteral(text: []const u8) bool {
        if (text.len < 2 or text[text.len - 1] != 'd' or !std.ascii.isDigit(text[0])) return false;
        if (text.len > 2 and text[0] == '0' and (text[1] == 'x' or text[1] == 'b')) return false;
        for (text[0 .. text.len - 1]) |ch| if (!std.ascii.isDigit(ch) and ch != '.' and ch != '_') return false;
        return true;
    }

    fn isString(ty: ?[]const u8) bool {
        const t = ty orelse return false;
        return std.mem.eql(u8, t, "String");
    }

    // ---- expressions ------------------------------------------------------------------------

    /// Check an expression and return its type when the check knows it.
    fn expr(c: *Checker, n: *const Node) Error!?[]const u8 {
        const exp = c.expected;
        c.expected = null; // only the expression that the context names uses it, not what is inside
        switch (n.tag) {
            .num => {
                if (isDecimalLiteral(n.text)) return "Decimal";
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
            .name => return (try c.resolve(n, n.text)).ty,
            .ref => {
                const info = try c.resolve(n, n.text);
                if (n.kids.len > 0) _ = try c.expr(n.kids[0]);
                return info.ty;
            },
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
                for (n.kids) |k| {
                    if (n.tag == .field and c.isSecretModule(k)) continue;
                    _ = try c.expr(k);
                }
                return null;
            },
            .builder => return c.builder(n),
            .call => {
                const ty = try c.callExpecting(n, false, exp);
                // `Secret(text)` makes a Secret: the checker knows its type (data-language.md#secrets)
                if (n.kids[0].tag == .name and std.mem.eql(u8, n.kids[0].text, "Secret")) return "Secret";
                return ty;
            },
            .await_ => {
                c.task_call = true;
                defer c.task_call = false;
                return c.call(n.kids[0], false);
            },
            .generic => {
                _ = try c.resolve(n, n.text);
                return n.text;
            },
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
        if (std.mem.eql(u8, op, "+") and (isType(lt, "Secret") or isType(rt, "Secret"))) {
            return c.fail(n, "a Secret is not a String: '+' can not join it to a text; give it to a sink that accepts a Secret (data-language.md#secrets)", .{});
        }
        if (std.mem.eql(u8, op, "+") and isString(lt) and isString(rt)) return "String";
        // a Decimal and a Real are never mixed without a conversion (data-language.md, D-080): a compile error (D-110)
        if ((isType(lt, "Decimal") and isType(rt, "Real")) or (isType(lt, "Real") and isType(rt, "Decimal"))) {
            return c.fail(n, "operator {s} does not apply to {s} and {s}: a Decimal and a Real are never mixed, convert one explicitly (D-080)", .{ op, lt.?, rt.? });
        }
        const cmp = [_][]const u8{ "==", "<>", "<", ">", "<=", ">=", "=~", "and", "or", "xor", "in", "not in", "is", "is not" };
        for (cmp) |o| if (std.mem.eql(u8, op, o)) return "Logic";
        // a Decimal with a Decimal or an Integer stays a Decimal
        if ((isType(lt, "Decimal") and (isType(rt, "Decimal") or isType(rt, "Integer"))) or (isType(lt, "Integer") and isType(rt, "Decimal"))) return "Decimal";
        if (isNumeric(lt) and isNumeric(rt)) {
            if (std.mem.eql(u8, op, "/")) return "Real";
            return if (std.mem.eql(u8, lt.?, "Real") or std.mem.eql(u8, rt.?, "Real")) "Real" else "Integer";
        }
        return null;
    }

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
        return c.callExpecting(n, as_statement, null);
    }

    fn callExpecting(c: *Checker, n: *const Node, as_statement: bool, exp: ?[]const u8) Error!?[]const u8 {
        const callee = n.kids[0];
        const args = n.kids[1..];
        var result: ?[]const u8 = null;
        var overloaded: ?[]const *const Node = null;
        var single: ?*const Node = null;
        if (callee.tag == .name or callee.tag == .generic) {
            const info = try c.resolve(callee, callee.text);
            if (info.node) |target| {
                if (target.tag == .generator and as_statement) {
                    return c.fail(n, "generator {s} is called as a statement: its values would be lost; use it in a for loop or call next() on it", .{callee.text});
                }
                if (target.is_async and !c.task_call) return c.fail(n, "{s} is async: use spawn or await (D-104)", .{callee.text});
                if (target.tag == .class and !c.allow_abstract) {
                    if (c.missing(target, false)) |_| return c.fail(n, "{s} is abstract: only the constructor of a subclass builds it (D-145)", .{callee.text});
                }
            }
            c.task_call = false;
            c.allow_abstract = false;
            if (info.kind == .class) try c.nullFields(callee.text, n);
            switch (info.kind) {
                .procedure => if (!as_statement) {
                    return c.fail(n, "the procedure '{s}' returns nothing: it can't be used in an expression", .{callee.text});
                },
                .class => result = callee.text,
                else => {},
            }
            if (c.ov.get(callee.text)) |list| {
                if (list.items.len > 1) overloaded = list.items;
            }
            if (callee.tag == .generic) {
                if (overloaded == null) if (info.node) |target| try c.constraints(callee, target);
            }
            if (overloaded == null) if (info.node) |target| {
                try c.order(n, target, args);
                if (target.tag == .function or target.tag == .procedure) single = target;
                // a type parameter that no value parameter mentions can only come from the call (D-148)
                if (callee.tag == .name) try c.inferable(n, target);
            };
        } else if (callee.tag == .field) {
            // `customers.find!(…)` gives a record of the class of the table
            if (callee.kids[0].tag == .name and std.mem.eql(u8, callee.text, "find!")) {
                if (c.tables.get(callee.kids[0].text)) |t| result = t.kids[0].text;
            }
            const obj_ty = if (c.isSecretModule(callee.kids[0])) null else try c.expr(callee.kids[0]);
            if (obj_ty) |t| try c.method(n, t, callee.text);
        } else _ = try c.expr(callee);
        var infos: std.ArrayList(overload.ArgInfo) = .empty;
        var all_known = true;
        for (args, 0..) |a, i| {
            if (a.tag == .pair and a.kids[0].tag == .name) {
                try infos.append(c.a, .{ .name = a.kids[0].text, .ty = try c.expr(a.kids[1]) });
            } else {
                if (single) |t| {
                    const plist = t.kids[0].kids;
                    if (i < plist.len and plist[i].tag != .vararg_param) c.expected = if (plist[i].ty) |pt| pt.text else null;
                }
                try infos.append(c.a, .{ .ty = try c.expr(a) });
            }
            if (infos.items[infos.items.len - 1].ty == null) all_known = false;
        }
        if (overloaded) |decls| {
            // a written type list, `describe(:Integer)(5)`, asks for the generic declarations (D-148)
            var generic_only: std.ArrayList(*const Node) = .empty;
            if (callee.tag == .generic) {
                for (decls) |d| if (d.kids[1].kids.len > 0) try generic_only.append(c.a, d);
            }
            switch (overload.select(if (generic_only.items.len > 0) generic_only.items else decls, infos.items, exp, null)) {
                .one => |d| @constCast(n).sel = d,
                .none => return c.fail(n, "no signature of {s} matches the arguments", .{callee.text}),
                // with a type that is not known here the choice is made at run time, from the values
                .ambiguous => if (all_known) return c.fail(n, "ambiguous call of {s}: more than one signature fits", .{callee.text}),
            }
        }
        return result;
    }

    // @decision D-085
    /// `obj.name()` where the type of `obj` is a known class: the method must be public here.
    fn method(c: *Checker, n: *const Node, class_name: []const u8, name: []const u8) Error!void {
        var cur: ?[]const u8 = class_name;
        while (cur) |cn| {
            const cls = c.classes.get(cn) orelse return;
            for (cls.kids[2..]) |m| {
                if (m.tag != .method and m.tag != .function and m.tag != .generator) continue;
                if (!std.mem.eql(u8, m.text, name)) continue;
                if (m.public) return;
                if (c.in_class) |here| if (std.mem.eql(u8, here, cn)) return;
                return c.fail(n, "'{s}' is private to the class {s}", .{ name, cn });
            }
            for (cls.extra) |tr| {
                const tn = c.classes.get(tr.text) orelse continue;
                for (tn.kids[2..]) |m| if (std.mem.eql(u8, m.text, name)) return;
            }
            cur = if (cls.kids[1].tag == .name) cls.kids[1].text else null;
        }
    }

    /// Two traits that provide a method with the same name force the class to write it (D-145).
    fn traitConflicts(c: *Checker, cls: *const Node) Error!void {
        for (cls.extra, 0..) |t1, i| {
            const n1 = c.classes.get(t1.text) orelse continue;
            for (cls.extra[i + 1 ..]) |t2| {
                const n2 = c.classes.get(t2.text) orelse continue;
                for (n1.kids[2..]) |m1| {
                    if (m1.kids[3].tag == .none) continue;
                    for (n2.kids[2..]) |m2| {
                        if (m2.kids[3].tag == .none or !std.mem.eql(u8, m1.text, m2.text)) continue;
                        var written = false;
                        for (cls.kids[2..]) |own| if (own.tag == .method and own.kids[3].tag != .none and std.mem.eql(u8, own.text, m1.text)) {
                            written = true;
                        };
                        if (!written) return c.fail(cls, "{s} must write {s}: it comes from {s} and {s} (D-145)", .{ cls.text, m1.text, t1.text, t2.text });
                    }
                }
            }
        }
    }

    // @decision D-145
    /// The first method that a class requires (from itself, its ancestors or its traits) and nobody writes.
    fn missing(c: *Checker, cls: *const Node, only_traits: bool) ?[]const u8 {
        var required: std.ArrayList([]const u8) = .empty;
        var written: std.ArrayList([]const u8) = .empty;
        var cur: ?*const Node = cls;
        while (cur) |k| {
            for (k.kids[2..]) |m| {
                if (m.tag != .method) continue;
                if (m.kids[3].tag == .none) {
                    if (!only_traits) required.append(c.a, m.text) catch return null;
                } else written.append(c.a, m.text) catch return null;
            }
            for (k.extra) |tr| {
                const tn = c.classes.get(tr.text) orelse continue;
                for (tn.kids[2..]) |m| {
                    if (m.kids[3].tag == .none) required.append(c.a, m.text) catch return null else written.append(c.a, m.text) catch return null;
                }
            }
            cur = if (k.kids[1].tag == .name) c.classes.get(k.kids[1].text) else null;
        }
        for (required.items) |r| {
            var found = false;
            for (written.items) |w| if (std.mem.eql(u8, r, w)) {
                found = true;
            };
            if (!found) return r;
        }
        return null;
    }

    // @decision D-106
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

    /// Does the class `name` adopt the trait `trait`, directly, through a parent or through a trait?
    fn adopts(c: *Checker, name: []const u8, trait: []const u8) bool {
        var cur: ?[]const u8 = name;
        while (cur) |cn| {
            if (std.mem.eql(u8, cn, trait)) return true;
            const cls = c.classes.get(cn) orelse return overload.isPrimitive(cn); // a basic type adopts the library traits; `Object` does not
            for (cls.extra) |tr| if (c.adopts(tr.text, trait)) return true;
            cur = if (cls.kids[1].tag == .name) cls.kids[1].text else null;
        }
        return false;
    }

    /// The written types of `largest(:Point)(...)` must adopt the constraints of the declaration (D-145, D-148).
    fn constraints(c: *Checker, callee: *const Node, target: *const Node) Error!void {
        for (target.kids[1].kids, 0..) |tp, i| {
            const want = tp.ty orelse continue;
            if (i >= callee.kids.len) break;
            const given = callee.kids[i].text;
            if (!c.adopts(given, want.text)) return c.fail(callee, "{s} does not adopt {s}, the constraint of {s} in {s} (D-148)", .{ given, want.text, tp.text, target.text });
        }
    }

    /// A call without a type list of a generic subprogram whose type parameters the arguments do not give.
    fn inferable(c: *Checker, n: *const Node, target: *const Node) Error!void {
        if (target.tag != .function and target.tag != .procedure) return;
        for (target.kids[1].kids) |tp| {
            var found = false;
            for (target.kids[0].kids) |prm| {
                if (prm.ty) |t| if (overload.mentions(t.text, tp.text)) {
                    found = true;
                };
            }
            if (!found) return c.fail(n, "can not infer the type {s} of {s}: write it at the call, {s}(:Type)(...) (D-148)", .{ tp.text, target.text, target.text });
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
        const saved_ctor = c.in_ctor;
        defer c.in_ctor = saved_ctor;
        c.in_ctor = r.tag == .constructor;
        for (r.kids[1].kids) |tp| try c.declare(tp, tp.text, .{ .kind = .class });
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
                // `let self := Shape(name);` is how a subclass constructor builds its abstract parent
                c.allow_abstract = c.in_ctor and s.kids[0].tag == .name and std.mem.eql(u8, s.kids[0].text, "self");
                if (s.kids[0].tag == .name) if (c.lookup(s.kids[0].text)) |target_info| {
                    c.expected = target_info.ty;
                };
                _ = try c.expr(value);
                c.allow_abstract = false;
                const target = s.kids[0];
                if (std.mem.eql(u8, s.text, "+>")) {
                    _ = try c.expr(target); // `let x +> lst;`: the left side is the element
                    return;
                }
                if (std.mem.eql(u8, s.text, "<+") and target.tag == .name) {
                    if (c.tables.get(target.text)) |t| if (tableHas(t, "read only")) {
                        return c.fail(s, "table {s} is read only: it has no add, no remove and no change of a field (database.md, the table declaration)", .{t.text});
                    };
                }
                if (target.tag == .field and target.kids[0].tag == .name) {
                    // `let c.id := 5;` when the type of `c` is a record class of a table: a key or generated field never changes
                    const info = c.lookup(target.kids[0].text);
                    if (info) |i| if (i.ty) |ty| try c.fieldChange(s, ty, target.text);
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
            .print_stmt, .write_stmt, .expect_stmt, .assert_stmt, .raise_stmt, .yield_stmt, .over_stmt, .exit_stmt => {
                for (s.kids) |k| _ = try c.expr(k);
            },
            .cond_stmt => {
                _ = try c.expr(s.kids[0]);
                try c.statement(s.kids[1]);
            },
            .defer_stmt => try c.statement(s.kids[0]),
            .commit_stmt, .rollback_stmt => {},
            .update_stmt => try c.updateBlock(s),
            .expr_stmt => {
                const e = s.kids[0];
                if (e.tag == .call) {
                    _ = try c.call(e, true);
                } else if (e.tag == .await_) {
                    c.task_call = true; // `await load(p, @t);`: an async procedure as a statement
                    _ = try c.call(e.kids[0], true);
                } else _ = try c.expr(e);
            },
            .spawn_stmt => {
                const call_node = s.kids[0];
                const callee = call_node.kids[0];
                if (callee.tag == .name) {
                    const info = try c.resolve(callee, callee.text);
                    if (info.kind == .function) return c.fail(s, "{s} is a function: use await, a spawned result would be lost (D-143)", .{callee.text});
                    if (info.node) |target| if (!target.is_async) return c.fail(s, "{s} is not async: spawn starts an async procedure (D-143)", .{callee.text});
                }
                c.task_call = true;
                _ = try c.call(call_node, true);
            },
            .wait_stmt => _ = try c.expr(s.kids[0]),
            .parallel => {
                if (s.kids[2].tag != .none) _ = try c.expr(s.kids[2]);
                try c.push();
                defer c.pop();
                try c.block(s.kids[0]);
                try c.block(s.kids[1]);
            },
            .start_stmt => for (s.kids) |a| {
                _ = try c.expr(a);
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
                try c.jobWrites(s);
                try c.block(s.kids[0]);
            },
            .apply_stmt => {
                for (s.kids) |a| _ = try c.expr(a);
            },
            else => {},
        }
    }

    // @decision D-080
    /// `{name: null} :Customer` or `Customer(name: null)`: `null` for a member that is not optional (D-080).
    fn nullFields(c: *Checker, class_name: []const u8, value: *const Node) Error!void {
        const cls = c.classes.get(class_name) orelse return;
        const items: []const *const Node = switch (value.tag) {
            .brace => value.kids,
            .call => if (value.kids.len > 1) value.kids[1..] else &.{},
            else => return,
        };
        for (items) |pair| {
            if (pair.tag != .pair or pair.kids[0].tag != .name) continue;
            const v = pair.kids[1];
            if (v.tag != .name or !(std.mem.eql(u8, v.text, "null") or std.mem.eql(u8, v.text, "Null"))) continue;
            for (cls.kids[0].kids) |m| {
                if (!std.mem.eql(u8, m.text, pair.kids[0].text)) continue;
                const ty = m.ty orelse continue;
                if (!std.mem.endsWith(u8, ty.text, "?")) {
                    return c.fail(pair, "null in {s}: {s} is not optional; write {s}? to allow null (D-080)", .{ class_name, m.text, ty.text });
                }
            }
        }
    }

    // @decision D-096
    fn declaration(c: *Checker, s: *const Node) Error!void {
        if (s.ty) |hint_node| try c.nullFields(hint_node.text, s.kids[1]);
        var vt: ?[]const u8 = null;
        const hint: ?[]const u8 = if (s.ty) |t| t.text else null;
        c.expected = hint;
        if (s.kids[1].tag != .none) vt = try c.expr(s.kids[1]);
        c.expected = null;
        const targets = s.kids[0].kids;
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

    /// Declare, before anything is checked, what a root aspect declares: they may come in any order (D-041).
    fn declareMembers(c: *Checker, members: []const *const Node) Error!void {
        for (members) |m| {
            switch (m.tag) {
                .class, .trait => {
                    try c.declare(m, m.text, .{ .kind = .class, .node = m });
                    try c.classes.put(c.a, m.text, m);
                    if (m.kids[1].tag == .name and std.mem.eql(u8, m.kids[1].text, "Ordinal")) {
                        // the values of an ordinal that start with a capital letter need no qualifier
                        for (m.kids[0].kids) |v| {
                            if (v.text.len > 0 and std.ascii.isUpper(v.text[0])) try c.declare(v, v.text, .{ .kind = .constant });
                        }
                    }
                },
                .function, .procedure, .generator => try c.declareSubprogram(m),
                .table_decl => {
                    try c.declare(m, m.text, .{ .kind = .variable, .ty = "Table", .node = m });
                    try c.tables.put(c.a, m.text, m);
                },
                .import_decl => for (m.kids) |item| {
                    const alias = item.kids[0];
                    if (item.public or std.mem.eql(u8, item.text, "*")) {
                        c.open_names = true;
                    } else {
                        const bound = if (alias.tag == .name) alias.text else item.text;
                        try c.declare(item, bound, .{ .kind = .variable });
                    }
                },
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

    // @decision D-149
    /// Declare a function or a procedure; several may share a name if their signatures differ.
    fn declareSubprogram(c: *Checker, m: *const Node) Error!void {
        if (c.ov.getPtr(m.text)) |list| {
            if (list.items[0].tag != m.tag) return c.fail(m, "{s} is both a function and a procedure: they never share a name (D-149)", .{m.text});
            if (list.items[0].is_sql or m.is_sql) return c.fail(m, "the sql function {s} can not be overloaded: SQL finds a function by its name (D-166)", .{m.text});
            for (list.items) |d| {
                if (overload.sameSignature(d, m)) return c.fail(m, "{s} is declared twice with the same signature (D-149)", .{m.text});
            }
            try list.append(c.a, m);
            return;
        }
        try c.declare(m, m.text, .{ .kind = if (m.tag == .procedure) .procedure else .function, .node = m });
        var list: std.ArrayList(*const Node) = .empty;
        try list.append(c.a, m);
        try c.ov.put(c.a, m.text, list);
    }

    fn collectNames(c: *Checker, n: *const Node, set: *std.StringHashMapUnmanaged(void)) Error!void {
        switch (n.tag) {
            .param, .ref_param, .vararg_param => try set.put(c.a, n.text, {}),
            .var_decl, .set => for (n.kids[0].kids) |t| if (t.tag == .name) try set.put(c.a, t.text, {}),
            .for_ => try c.patternNames(n.kids[0], set),
            else => {},
        }
        for (n.kids) |k| try c.collectNames(k, set);
    }

    fn patternNames(c: *Checker, p: *const Node, set: *std.StringHashMapUnmanaged(void)) Error!void {
        if (p.tag == .name) try set.put(c.a, p.text, {});
        for (p.kids) |k| try c.patternNames(k, set);
    }

    /// Is the shared variable declaration `k` atomic: typed `Atomic(:T)` (the parser marks the type `public`)?
    fn isAtomic(k: *const Node) bool {
        const t = k.ty orelse return false;
        return t.public;
    }

    /// Is the shared function or procedure `name` thread safe? No shared plain variable, no unsafe call (D-152).
    fn subprogramSafe(c: *Checker, macro_root: *const Node, name: []const u8, visiting: *std.ArrayList([]const u8)) Error!bool {
        for (visiting.items) |v| if (std.mem.eql(u8, v, name)) return true;
        for (macro_root.kids) |k| {
            if ((k.tag != .function and k.tag != .procedure) or !std.mem.eql(u8, k.text, name)) continue;
            try visiting.append(c.a, name);
            defer _ = visiting.pop();
            var locals: std.StringHashMapUnmanaged(void) = .empty;
            try c.collectNames(k, &locals);
            return c.bodySafe(macro_root, k, &locals, visiting);
        }
        return true;
    }

    fn bodySafe(c: *Checker, macro_root: *const Node, n: *const Node, locals: *std.StringHashMapUnmanaged(void), visiting: *std.ArrayList([]const u8)) Error!bool {
        if (n.tag == .name and !locals.contains(n.text)) {
            for (macro_root.kids) |k| {
                if (k.tag != .var_decl or isAtomic(k)) continue;
                for (k.kids[0].kids) |t| if (t.tag == .name and std.mem.eql(u8, t.text, n.text)) return false;
            }
        }
        if (n.tag == .call and n.kids[0].tag == .name and !locals.contains(n.kids[0].text)) {
            if (!try c.subprogramSafe(macro_root, n.kids[0].text, visiting)) return false;
        }
        for (n.kids) |k| if (!try c.bodySafe(macro_root, k, locals, visiting)) return false;
        return true;
    }

    /// Reject, in a `concurrent` aspect of a macro, a shared variable that is not atomic and a call of a shared
    /// subprogram that is not thread safe (D-152). The message names the aspect and the name.
    fn aspectSafe(c: *Checker, macro_root: *const Node, aspect: *const Node, n: *const Node, locals: *std.StringHashMapUnmanaged(void)) Error!void {
        if (n.tag == .name and !locals.contains(n.text)) {
            for (macro_root.kids) |k| {
                if (k.tag != .var_decl or isAtomic(k)) continue;
                for (k.kids[0].kids) |t| {
                    if (t.tag == .name and std.mem.eql(u8, t.text, n.text)) {
                        return c.fail(n, "the concurrent aspect '{s}' uses '{s}', which is not thread safe: declare it :Atomic(:Type) (D-152)", .{ aspect.text, n.text });
                    }
                }
            }
        }
        if (n.tag == .call and n.kids[0].tag == .name and !locals.contains(n.kids[0].text)) {
            var visiting: std.ArrayList([]const u8) = .empty;
            if (!try c.subprogramSafe(macro_root, n.kids[0].text, &visiting)) {
                return c.fail(n, "the concurrent aspect '{s}' calls '{s}', which is not thread safe (D-152)", .{ aspect.text, n.kids[0].text });
            }
        }
        for (n.kids) |k| try c.aspectSafe(macro_root, aspect, k, locals);
    }

    fn concurrentSafety(c: *Checker, macro_root: *const Node) Error!void {
        for (macro_root.kids) |a| {
            if (a.tag != .aspect or !a.public) continue;
            var locals: std.StringHashMapUnmanaged(void) = .empty;
            try c.collectNames(a, &locals);
            for (a.kids) |k| try c.aspectSafe(macro_root, a, k, &locals);
        }
    }

    // ---- tables (spec/library/database.md#the-table-declaration) -----------------------------------

    /// Does the table declaration have the clause `word` (`read only`, `temporary`, `key`, …)?
    fn tableHas(t: *const Node, word: []const u8) bool {
        for (t.kids[3..]) |cl| if (std.mem.eql(u8, cl.text, word)) return true;
        return false;
    }

    fn clauseOf(t: *const Node, word: []const u8) ?*const Node {
        for (t.kids[3..]) |cl| if (std.mem.eql(u8, cl.text, word)) return cl;
        return null;
    }

    fn classHasField(cls: *const Node, name: []const u8) bool {
        for (cls.kids[0].kids) |m| if (std.mem.eql(u8, m.text, name)) return true;
        return false;
    }

    /// The clause `word` of the table lists the field `name` (key, generated, version).
    fn clauseHasField(t: *const Node, word: []const u8, name: []const u8) bool {
        const cl = clauseOf(t, word) orelse return false;
        for (cl.kids) |f| if (std.mem.eql(u8, f.text, name)) return true;
        return false;
    }

    /// The names of the key fields of a table.
    pub fn keyFields(a: std.mem.Allocator, t: *const Node, cls: *const Node) ![]const []const u8 {
        var out: std.ArrayList([]const u8) = .empty;
        if (clauseOf(t, "key")) |cl| {
            for (cl.kids) |f| try out.append(a, f.text);
        } else if (classHasField(cls, "id")) try out.append(a, "id");
        return out.items;
    }

    /// The compile errors of one `table` declaration.
    fn checkTable(c: *Checker, t: *const Node) Error!void {
        const class_name = t.kids[0].text;
        const cls = c.classes.get(class_name) orelse return c.fail(t, "table {s}: the record class {s} is not declared", .{ t.text, class_name });
        if (cls.kids[1].tag != .name or !std.mem.eql(u8, cls.kids[1].text, "Record")) {
            return c.fail(t, "table {s}: {s} is not a record class: derive it from Record (class {s} = {{…}} <: Record)", .{ t.text, class_name, class_name });
        }
        for (t.kids[3..]) |cl| {
            const w = cl.text;
            if (std.mem.eql(u8, w, "key") or std.mem.eql(u8, w, "generated") or std.mem.eql(u8, w, "version") or std.mem.eql(u8, w, "column") or std.mem.eql(u8, w, "reference")) {
                const f = cl.kids[0];
                if (!classHasField(cls, f.text)) return c.fail(f, "unknown field {s} in {s} of {s}", .{ f.text, w, t.text });
                if (std.mem.eql(u8, w, "key") or std.mem.eql(u8, w, "generated")) {
                    for (cl.kids[1..]) |g| if (!classHasField(cls, g.text)) return c.fail(g, "unknown field {s} in {s} of {s}", .{ g.text, w, t.text });
                }
            }
            if (std.mem.eql(u8, w, "temporary")) {
                if (!std.mem.eql(u8, t.kids[1].text, "stage")) {
                    return c.fail(cl, "temporary is allowed only in the staging database, the connection \"stage\": table {s} is in \"{s}\"", .{ t.text, t.kids[1].text });
                }
            }
        }
        const keys = c.keyFieldsOf(t, cls) catch return error.OutOfMemory;
        if (keys.len == 0) return c.fail(t, "table {s} needs a key: the class {s} has no field id, write key (field);", .{ t.text, class_name });
        for (keys) |k| {
            if (!classHasField(cls, k)) return c.fail(t, "unknown field {s} in key of {s}", .{ k, t.text });
        }
        if (clauseOf(t, "version")) |v| {
            for (keys) |k| if (std.mem.eql(u8, k, v.kids[0].text)) return c.fail(v, "the version field {s} can not be a key field of {s}", .{ k, t.text });
        }
        if (clauseOf(t, "reference")) |_| {} // the cycle is looked for when every table is known
        try c.referenceCycle(t);
    }

    fn keyFieldsOf(c: *Checker, t: *const Node, cls: *const Node) ![]const []const u8 {
        return keyFields(c.a, t, cls);
    }

    /// A cycle of `reference` clauses is a compile error (database.md): `aa -> bb -> aa`.
    fn referenceCycle(c: *Checker, start: *const Node) Error!void {
        var path: std.ArrayList(*const Node) = .empty;
        try path.append(c.a, start);
        try c.walkReferences(start, &path);
    }

    fn walkReferences(c: *Checker, t: *const Node, path: *std.ArrayList(*const Node)) Error!void {
        for (t.kids[3..]) |cl| {
            if (!std.mem.eql(u8, cl.text, "reference")) continue;
            const target = c.tables.get(cl.kids[1].text) orelse return c.fail(cl, "unknown table {s} in reference of {s}", .{ cl.kids[1].text, t.text });
            for (path.items, 0..) |p, i| {
                if (p == target) {
                    var text: std.ArrayList(u8) = .empty;
                    for (path.items[i..]) |q| {
                        try text.appendSlice(c.a, q.text);
                        try text.appendSlice(c.a, " -> ");
                    }
                    try text.appendSlice(c.a, target.text);
                    return c.fail(cl, "reference cycle: {s}", .{text.items});
                }
            }
            try path.append(c.a, target);
            try c.walkReferences(target, path);
            _ = path.pop();
        }
    }

    /// A key or generated field never changes (database.md, dirty fields); the compiler refuses a change it can see.
    fn fieldChange(c: *Checker, at: *const Node, class_name: []const u8, field: []const u8) Error!void {
        var it = c.tables.iterator();
        while (it.next()) |entry| {
            const t = entry.value_ptr.*;
            if (!std.mem.eql(u8, t.kids[0].text, class_name)) continue;
            const cls = c.classes.get(class_name) orelse continue;
            const keys = c.keyFieldsOf(t, cls) catch continue;
            for (keys) |k| if (std.mem.eql(u8, k, field)) return c.fail(at, "field {s} can not be changed: it is the key of {s}; a key change is a delete and an insert", .{ field, t.text });
            if (clauseHasField(t, "generated", field)) return c.fail(at, "field {s} can not be changed: the database generates it in {s}", .{ field, t.text });
            if (tableHas(t, "read only")) return c.fail(at, "field {s} can not be changed: table {s} is read only", .{ field, t.text });
            return;
        }
    }

    /// `update record do … done;` (database.md, the update block).
    fn updateBlock(c: *Checker, s: *const Node) Error!void {
        const ty = try c.expr(s.kids[0]);
        try c.push();
        defer c.pop();
        const saved_open = c.open_names;
        defer c.open_names = saved_open;
        if (ty) |class_name| {
            if (c.classes.get(class_name)) |cls| {
                for (cls.kids[0].kids) |m| try c.declare(m, m.text, .{ .kind = .variable, .ty = if (m.ty) |t| t.text else null });
                try c.updateTargets(s.kids[1], class_name);
            } else c.open_names = true;
        } else c.open_names = true;
        try c.block(s.kids[1]);
    }

    /// Inside an update block, a `let` of a key, generated or read only field is refused.
    fn updateTargets(c: *Checker, n: *const Node, class_name: []const u8) Error!void {
        if (n.tag == .assign and n.kids[0].tag == .name) try c.fieldChange(n, class_name, n.kids[0].text);
        for (n.kids) |k| try c.updateTargets(k, class_name);
    }

    // @decision D-158
    /// A job writes to one connection only (database.md, transactions).
    fn jobWrites(c: *Checker, job: *const Node) Error!void {
        var first: ?[]const u8 = null;
        try c.collectWrites(job, job.kids[0], &first);
    }

    fn collectWrites(c: *Checker, job: *const Node, n: *const Node, first: *?[]const u8) Error!void {
        var table: ?*const Node = null;
        if (n.tag == .assign and std.mem.eql(u8, n.text, "<+") and n.kids[0].tag == .name) table = c.tables.get(n.kids[0].text);
        if (n.tag == .call and n.kids[0].tag == .field and n.kids[0].kids[0].tag == .name) {
            const m = n.kids[0].text;
            if (std.mem.eql(u8, m, "add") or std.mem.eql(u8, m, "remove") or std.mem.eql(u8, m, "flush") or std.mem.eql(u8, m, "load!")) {
                table = c.tables.get(n.kids[0].kids[0].text);
            }
        }
        if (table) |t| {
            const conn = t.kids[1].text;
            if (first.*) |f| {
                if (!std.mem.eql(u8, f, conn)) return c.fail(n, "job {s} writes to {s} and {s}: one connection per job (D-158)", .{ job.text, f, conn });
            } else first.* = conn;
        }
        for (n.kids) |k| try c.collectWrites(job, k, first);
    }

    /// An extension method (outside the class) with the signature of a method of its class would replace it (D-150).
    fn extensionClash(c: *Checker, m: *const Node) Error!void {
        const first = m.kids[0].kids;
        if (first.len == 0) return;
        const ty = first[0].ty orelse return;
        const cls = c.classes.get(ty.text) orelse return;
        for (cls.kids[2..]) |own| {
            if (own.tag != .method or !std.mem.eql(u8, own.text, m.text)) continue;
            if (overload.sameSignature(own, m)) return c.fail(m, "{s} has the same signature as a method of {s}: it would replace it (D-150)", .{ m.text, ty.text });
        }
    }

    /// Two methods of a class with the same name and the same signature (D-149).
    fn duplicateMethods(c: *Checker, cls: *const Node) Error!void {
        const members = cls.kids[2..];
        for (members, 0..) |a, i| {
            if (a.tag != .method and a.tag != .function) continue;
            for (members[i + 1 ..]) |b| {
                if (b.tag != a.tag or !std.mem.eql(u8, a.text, b.text)) continue;
                if (overload.sameSignature(a, b)) return c.fail(b, "{s} is declared twice with the same signature (D-149)", .{b.text});
            }
        }
    }

    /// Does a `start` below `n` start the private process `name` (D-179)?
    fn startsProcess(n: *const Node, name: []const u8) bool {
        if (n.tag == .start_stmt and std.mem.eql(u8, n.text, name)) return true;
        for (n.kids) |k| if (startsProcess(k, name)) return true;
        return false;
    }

    // @decision D-179
    // @decision D-152
    /// A concurrent aspect: each private process it starts uses only atomic variables and thread-safe subprograms.
    fn startedSafety(c: *Checker, aspect: *const Node) Error!void {
        for (aspect.kids) |prc| {
            if (prc.tag != .process or std.mem.eql(u8, prc.text, "main")) continue;
            if (!startsProcess(aspect, prc.text)) continue;
            var locals: std.StringHashMapUnmanaged(void) = .empty;
            try c.collectNames(prc, &locals);
            for (prc.kids) |k| try c.aspectSafe(aspect, aspect, k, &locals);
        }
    }

    // @decision D-179
    // @decision D-041
    fn checkRoot(c: *Checker, root_node: *const Node) Error!void {
        try c.push();
        try c.declareMembers(root_node.kids);
        try c.declMembers(root_node.kids);
        if (root_node.macro) try c.concurrentSafety(root_node);
        if (root_node.public) try c.startedSafety(root_node);
    }

    // @decision D-152
    /// Check the declarations of a root aspect, an aspect, a module or a macro.
    fn declMembers(c: *Checker, kids: []const *const Node) Error!void {
        for (kids) |m| {
            switch (m.tag) {
                .class, .trait => {
                    if (m.tag == .class) if (c.missing(m, true)) |name| {
                        return c.fail(m, "{s} does not implement {s}, required by its trait (D-145)", .{ m.text, name });
                    };
                    if (m.tag == .class) try c.traitConflicts(m);
                    try c.duplicateMethods(m);
                    for (m.kids[2..]) |r| try c.routine(r, m.text);
                },
                .method => {
                    try c.extensionClash(m);
                    try c.routine(m, null);
                },
                .function, .procedure, .generator => try c.routine(m, null),
                .table_decl => try c.checkTable(m),
                .aspect => {
                    try c.push();
                    defer c.pop();
                    try c.declareMembers(m.kids);
                    try c.declMembers(m.kids);
                    if (m.public) try c.startedSafety(m);
                },
                .region => try c.block(m.kids[0]),
                .var_decl, .set => if (m.kids[1].tag != .none) {
                    _ = try c.expr(m.kids[1]);
                },
                .process => {
                    try c.push();
                    defer c.pop();
                    if (m.kids.len > 4) for (m.kids[4].kids) |tp| try c.declare(tp, tp.text, .{ .kind = .class });
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

/// Check a parsed script: an aspect (or the root of a macro) or a module, as a whole.
pub fn check(arena: std.mem.Allocator, tree: *const Node, diag: *Diag) Error!void {
    var c: Checker = .{ .a = arena, .diag = diag };
    return c.checkRoot(tree);
}

test "an undefined name and a redeclared name are refused" {
    const parser = @import("parser.zig");
    var d: Diag = .{};
    try std.testing.expectError(error.Syntax, parser.check(std.testing.allocator, "primary aspect a is process main is print y; return; end a;", &d));
    try std.testing.expectEqualStrings("undefined name 'y'", d.message());
    try std.testing.expectError(error.Syntax, parser.check(std.testing.allocator, "primary aspect a is process main is new x := 1; new x := 2; return; end a;", &d));
    try std.testing.expectEqualStrings("'x' is already declared in this scope", d.message());
}

test "a correct script passes, a let of a missing name does not" {
    const parser = @import("parser.zig");
    var d: Diag = .{};
    try parser.check(std.testing.allocator, "primary aspect a is process main is new x := 1; let x += 2; new l := (1, 2); let l -> e; print e; return; end a;", &d);
    try std.testing.expectError(error.Syntax, parser.check(std.testing.allocator, "primary aspect a is process main is let y := 5; return; end a;", &d));
}

test "a procedure is a statement, and a late mandatory parameter is named" {
    const parser = @import("parser.zig");
    var d: Diag = .{};
    try std.testing.expectError(error.Syntax, parser.check(std.testing.allocator, "primary aspect a is procedure hi is return; process main is new v := hi(); return; end a;", &d));
    try std.testing.expectError(error.Syntax, parser.check(std.testing.allocator, "primary aspect a is procedure add(p = 0: Integer, @o: Integer) is return; process main is new r: Integer; add(1, @r); return; end a;", &d));
    try parser.check(std.testing.allocator, "primary aspect a is procedure add(p = 0: Integer, @o: Integer) is return; process main is new r: Integer; add(1, o: @r); return; end a;", &d);
}
