//! Overloading (D-149, D-150): functions, procedures and methods that share a name when their signatures
//! differ. This file holds the rules, on syntax nodes and type names only, so the checker (at compile time,
//! with the types it knows) and the interpreter (at run time, with the types of the values) apply the same ones.
//! Spec: spec/syntax/declarations.md#overloading.
const std = @import("std");
const ast = @import("evecm").ast;

const Node = ast.Node;

/// One argument of a call: its name when it is written `name: value`, and its type when it is known.
pub const ArgInfo = struct {
    name: []const u8 = "",
    ty: ?[]const u8 = null,
};

/// How the choice ended.
pub const Choice = union(enum) {
    one: *const Node,
    /// no declaration accepts the call
    none,
    /// two or more accept it equally well
    ambiguous,
};

// Zig tip: `std.StaticStringMap(void).initComptime` is a set of strings built while compiling (see
// check.zig). `has` answers "is this text in the set?".
const primitives = std.StaticStringMap(void).initComptime(.{
    .{"Integer"}, .{"Natural"}, .{"Real"}, .{"Float"},  .{"Decimal"}, .{"Byte"},   .{"Short"},
    .{"Huge"},    .{"String"},  .{"Text"}, .{"Logic"},  .{"Symbol"},  .{"Rune"},
});

/// Is `name` one of the basic types? They adopt `Comparable` and `Printable` in the library.
pub fn isPrimitive(name: []const u8) bool {
    return primitives.has(name);
}

/// Types that every value adopts, so a parameter of one of them accepts anything.
const universal = std.StaticStringMap(void).initComptime(.{
    .{"Object"}, .{"Printable"}, .{"Comparable"}, .{"Iterable"}, .{"Stream"},
});

// Zig tip: the score is a small number, bigger when the match is closer: 3 the same type, 2 a widening
// (an `Integer` given to a `Real`), 1 when the match can not be judged (an unknown type, a type parameter, a
// class whose parents are not looked at here). Returning `null` means "this argument is not accepted". An
// optional result `?u32` is how one function answers both "no" and "how well".
/// How well an argument of type `arg` fits a parameter of type `param`; null when it does not fit.
fn fit(param: ?*const Node, arg: ?[]const u8, tparams: []const *const Node) ?u32 {
    const p = param orelse return 1;
    const a = arg orelse return 1;
    var t = p.text;
    const optional = t.len > 0 and t[t.len - 1] == '?';
    if (optional) t = t[0 .. t.len - 1];
    if (optional and std.mem.eql(u8, a, "Null")) return 3;
    for (tparams) |tp| if (std.mem.eql(u8, tp.text, t)) return 1;
    if (std.mem.eql(u8, t, a)) return 3;
    const t_prim = primitives.has(t);
    const a_prim = primitives.has(a);
    if (t_prim and a_prim) {
        const eql = std.mem.eql;
        if (eql(u8, a, "Integer") and (eql(u8, t, "Real") or eql(u8, t, "Float") or eql(u8, t, "Decimal") or eql(u8, t, "Huge"))) return 2;
        if (eql(u8, a, "Natural") and (eql(u8, t, "Integer") or eql(u8, t, "Real") or eql(u8, t, "Huge"))) return 2;
        if (eql(u8, a, "Rune") and eql(u8, t, "Symbol")) return 3;
        if (eql(u8, a, "Symbol") and eql(u8, t, "Rune")) return 3;
        if (eql(u8, a, "String") and eql(u8, t, "Text")) return 2;
        return null;
    }
    if (t_prim) return null; // a class, list or Null given to a number or a string
    if (universal.has(t)) return 1;
    if (std.mem.startsWith(u8, t, "()") or std.mem.startsWith(u8, t, "[]")) {
        return if (a_prim) null else 1;
    }
    if (a_prim) return null; // a number or a string given to a class
    return 1;
}

// Zig tip: `decl.kids[0].kids` is the list of value parameters of a routine, `decl.kids[1].kids` its list of
// types (ast.zig). A method starts with `@self`, which the caller does not write, so it is skipped.
fn valueParams(decl: *const Node) []const *const Node {
    const list = decl.kids[0].kids;
    if (decl.tag == .method and list.len > 0 and list[0].tag == .ref_param and std.mem.eql(u8, list[0].text, "self")) return list[1..];
    return list;
}

/// Does a declaration have a result list? A method without one and a method with one are different methods.
pub fn hasResult(decl: *const Node) bool {
    return decl.kids[2].kids.len > 0;
}

// Zig tip: the same loops as `bindParams` in interp.zig decide which argument reaches which parameter: named
// arguments first, then the positional ones in order, a vararg takes the rest. `var taken = [_]bool{false} ** 32`
// is a stack array of 32 booleans (see the tip there). Here nothing is bound, only counted.
/// The score of a call to `decl`, or null when `decl` does not accept the arguments (number, names, types).
pub fn score(decl: *const Node, args: []const ArgInfo) ?u32 {
    const params = valueParams(decl);
    const tparams = decl.kids[1].kids;
    var taken = [_]bool{false} ** 32;
    if (args.len > taken.len) return null;
    var total: u32 = 0;
    var pos: usize = 0;
    for (params) |prm| {
        if (prm.tag == .vararg_param) {
            while (pos < args.len) : (pos += 1) {
                if (taken[pos] or args[pos].name.len > 0) continue;
                taken[pos] = true;
            }
            continue;
        }
        var found: ?usize = null;
        for (args, 0..) |a, i| {
            if (!taken[i] and a.name.len > 0 and std.mem.eql(u8, a.name, prm.text)) found = i;
        }
        if (found == null) {
            while (pos < args.len and (taken[pos] or args[pos].name.len > 0)) pos += 1;
            if (pos < args.len) {
                found = pos;
                pos += 1;
            }
        }
        if (found) |i| {
            taken[i] = true;
            total += fit(prm.ty, args[i].ty, tparams) orelse return null;
        } else if (prm.kids[0].tag == .none) return null; // a parameter without a value and without a default
    }
    for (args, 0..) |_, i| if (!taken[i]) return null;
    return total;
}

fn resultType(decl: *const Node) ?[]const u8 {
    if (decl.kids[2].kids.len == 0) return null;
    const t = decl.kids[2].kids[0].ty orelse return null;
    return t.text;
}

// Zig tip: a function can keep a short list on the stack with a fixed-size array and a counter (`n`), when the
// number of candidates is small. `[16]*const Node` holds up to 16 pointers; more overloads of one name than
// that are refused by the checker long before.
/// Choose the declaration for a call (D-149). `expected` is the type the context asks for, `statement` says
/// whether the call stands alone (a method without a result) or is part of an expression (a method with one).
pub fn select(decls: []const *const Node, args: []const ArgInfo, expected: ?[]const u8, statement: ?bool) Choice {
    var cand: [16]*const Node = undefined;
    var scores: [16]u32 = undefined;
    var n: usize = 0;
    for (decls) |d| {
        const s = score(d, args) orelse continue;
        if (n == cand.len) return .ambiguous;
        cand[n] = d;
        scores[n] = s;
        n += 1;
    }
    if (n == 0) return .none;
    if (statement) |stmt| {
        // a call as a statement uses a routine without a result; in an expression, one with a result (D-149)
        var kept: usize = 0;
        for (0..n) |i| {
            if (hasResult(cand[i]) != stmt) {
                cand[kept] = cand[i];
                scores[kept] = scores[i];
                kept += 1;
            }
        }
        if (kept > 0) n = kept;
    }
    var best: u32 = 0;
    for (scores[0..n]) |s| best = @max(best, s);
    var kept: usize = 0;
    for (0..n) |i| {
        if (scores[i] == best) {
            cand[kept] = cand[i];
            kept += 1;
        }
    }
    n = kept;
    if (n == 1) return .{ .one = cand[0] };
    if (expected) |e| {
        var match: ?*const Node = null;
        var count: usize = 0;
        for (cand[0..n]) |d| {
            const r = resultType(d) orelse continue;
            if (std.mem.eql(u8, r, e)) {
                match = d;
                count += 1;
            }
        }
        if (count == 1) return .{ .one = match.? };
    }
    return .ambiguous;
}

// Zig tip: the signature of a declaration is the types of its value parameters and, for a function, the type of
// its result. Names, defaults and `@` marks are not part of it (D-150). A parameter without a type is written
// `?` so that `f(x)` and `f(x: Integer)` differ.
/// Two declarations with the same signature: the second is a compile error (D-149).
pub fn sameSignature(a: *const Node, b: *const Node) bool {
    const pa = valueParams(a);
    const pb = valueParams(b);
    if (pa.len != pb.len) return false;
    for (pa, pb) |x, y| {
        const tx = if (x.ty) |t| t.text else "?";
        const ty = if (y.ty) |t| t.text else "?";
        if (!std.mem.eql(u8, tx, ty)) return false;
    }
    if (hasResult(a) != hasResult(b)) return false;
    const ra = resultType(a) orelse "?";
    const rb = resultType(b) orelse "?";
    return std.mem.eql(u8, ra, rb);
}

/// Does the text of a type mention the type parameter `name` as a whole word (`T`, `()T`, `T?`)?
pub fn mentions(ty_text: []const u8, name: []const u8) bool {
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, ty_text, i, name)) |at| {
        const before = at == 0 or !std.ascii.isAlphanumeric(ty_text[at - 1]);
        const end = at + name.len;
        const after = end >= ty_text.len or !std.ascii.isAlphanumeric(ty_text[end]);
        if (before and after) return true;
        i = at + 1;
    }
    return false;
}

// Zig tip: a test builds small syntax nodes by hand with `.{ .tag = ..., .kids = ... }`. A `const` node can be
// pointed to by `&x` as `*const Node`. This is the same data the parser makes, without a source text.
fn testParam(name: []const u8, ty: *const Node) Node {
    return .{ .tag = .param, .text = name, .ty = ty, .kids = &.{&ast.none} };
}

test "the score prefers the exact type and refuses a wrong one" {
    const int_t: Node = .{ .tag = .type, .text = "Integer" };
    const real_t: Node = .{ .tag = .type, .text = "Real" };
    const pi = testParam("x", &int_t);
    const pr = testParam("x", &real_t);
    const li = [_]*const Node{&pi};
    const lr = [_]*const Node{&pr};
    const params_i: Node = .{ .tag = .params, .kids = &li };
    const params_r: Node = .{ .tag = .params, .kids = &lr };
    const empty: Node = .{ .tag = .params };
    const di: Node = .{ .tag = .function, .text = "half", .kids = &.{ &params_i, &empty, &empty, &ast.none } };
    const dr: Node = .{ .tag = .function, .text = "half", .kids = &.{ &params_r, &empty, &empty, &ast.none } };
    const decls = [_]*const Node{ &di, &dr };

    const c1 = select(&decls, &.{.{ .ty = "Integer" }}, null, null);
    try std.testing.expect(c1 == .one and c1.one == &di);
    const c2 = select(&decls, &.{.{ .ty = "Real" }}, null, null);
    try std.testing.expect(c2 == .one and c2.one == &dr);
    try std.testing.expect(select(&decls, &.{.{ .ty = "String" }}, null, null) == .none);
    try std.testing.expect(select(&decls, &.{}, null, null) == .none);
    // unknown type: both fit equally well
    try std.testing.expect(select(&decls, &.{.{}}, null, null) == .ambiguous);
    try std.testing.expect(!sameSignature(&di, &dr));
    try std.testing.expect(sameSignature(&di, &di));
}

test "a type parameter is found as a whole word" {
    try std.testing.expect(mentions("()T", "T"));
    try std.testing.expect(mentions("T?", "T"));
    try std.testing.expect(!mentions("Text", "T"));
    try std.testing.expect(!mentions("Integer", "T"));
}
