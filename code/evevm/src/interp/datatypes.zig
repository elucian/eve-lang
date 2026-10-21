//! @eve-module interp.datatypes
//! @spec spec/library/data-language.md
//! @feature F-LNG-13, F-LIB-06, F-LIB-08
//! @tests test/level5
//! Decimal, Instant and Secret values (spec/library/data-language.md).
//! Part of the interpreter (interp.zig): every function takes the interpreter as `it: *Interp`, and
//! `Interp` names each of them again, so a call reads `it.name(...)` wherever it is made.
const std = @import("std");
const cmdargs = @import("cmdargs.zig");
const interp = @import("../interp.zig");
const db = @import("../db.zig");
const Interp = interp.Interp;
const data = interp.data;
const decimal = interp.decimal;
const dlib = interp.dlib;
const instant = interp.instant;
const Node = interp.Node;
const value = interp.value;
const Signal = interp.Signal;
const Value = interp.Value;
const Class = interp.Class;
const Arg = interp.Arg;
const err_key = interp.err_key;
const err_divide = interp.err_divide;
const err_convert = interp.err_convert;

// ---- Decimal, Instant, Secret (spec/library/data-language.md) ---------------------------------------

/// An arithmetic operator when one side is a Decimal and the other a Decimal or a whole number.
pub fn decimalOp(it: *Interp, op: []const u8, l: Value, r: Value) Signal!Value {
    const eql = std.mem.eql;
    const x = Interp.decOf(l) orelse return it.fail("operator {s} does not apply to {s} and {s}: a Decimal and a Real are never mixed, convert one explicitly", .{ op, Interp.typeName(l), Interp.typeName(r) });
    const y = Interp.decOf(r) orelse return it.fail("operator {s} does not apply to {s} and {s}: a Decimal and a Real are never mixed, convert one explicitly", .{ op, Interp.typeName(l), Interp.typeName(r) });
    if (eql(u8, op, "+")) return .{ .dec = decimal.add(x, y) orelse return it.overflow() };
    if (eql(u8, op, "-")) return .{ .dec = decimal.sub(x, y) orelse return it.overflow() };
    if (eql(u8, op, "*")) return .{ .dec = decimal.mul(x, y) orelse return it.overflow() };
    if (eql(u8, op, "/") or eql(u8, op, "%")) {
        if (y.m == 0) return it.failWith(err_divide, "Division by zero", .{});
        if (eql(u8, op, "%")) return .{ .dec = decimal.rem(x, y) };
        return .{ .dec = decimal.div(x, y) orelse return it.overflow() };
    }
    return it.fail("operator {s} does not apply to {s} and {s}", .{ op, Interp.typeName(l), Interp.typeName(r) });
}

/// A Decimal from a Real read in a column: the shortest text that gives the same number.
pub fn decFromReal(it: *Interp, x: f64) Signal!decimal.Dec {
    return decimal.fromF64(x) orelse it.overflow();
}

/// A text column read into the member `m`: a Decimal or an Instant is parsed, anything else is a String.
pub fn fromSqlText(it: *Interp, raw: []const u8, m: *const Node) Signal!Value {
    const ty = dlib.baseType(m.ty);
    if (std.mem.eql(u8, ty, "Decimal")) {
        return .{ .dec = decimal.parse(raw) orelse return it.failWith(err_convert, "DatabaseError: '{s}' is not a Decimal for '{s}'", .{ raw, m.text }) };
    }
    if (std.mem.eql(u8, ty, "Instant")) {
        return .{ .instant = instant.parse(raw) orelse return it.failWith(err_convert, "DatabaseError: '{s}' is not an Instant for '{s}'", .{ raw, m.text }) };
    }
    return it.newStr(raw);
}

/// `Secret(text)`: a value that prints as `***`.
pub fn makeSecret(it: *Interp, args: []const *const Node) Signal!Value {
    if (args.len != 1) return it.fail("Secret takes one text", .{});
    const v = try it.eval(args[0]);
    if (v != .str) return it.fail("Secret takes a String, not a {s}", .{Interp.typeName(v)});
    return it.secretObject(v);
}

/// Is the value a generator object?
pub fn isGenerator(it: *Interp, v: Value) bool {
    return v == .object and v.object.class != null and v.object.class == it.base().gen_class;
}

/// Is the value a Secret?
pub fn isSecret(it: *Interp, v: Value) bool {
    return v == .object and v.object.class != null and v.object.class == it.base().secret_class;
}

pub fn secretObject(it: *Interp, secret_text: Value) Signal!Value {
    const b = it.base();
    if (b.secret_class == null) {
        const cls = try it.a.create(Class);
        cls.* = .{ .name = "Secret" };
        b.secret_class = cls;
    }
    const obj = try it.newObject();
    obj.class = b.secret_class;
    try it.setField(obj, "text", secret_text);
    return .{ .object = obj };
}

// @decision D-155
/// `secret.get(name)`: the secret of the machine, or the error `$err_key` when there is none.
pub fn secretGet(it: *Interp, args: []const *const Node) Signal!Value {
    if (args.len != 1) return it.fail("secret.get takes the name of a secret", .{});
    const name = try it.text(try it.eval(args[0]));
    var upper: std.ArrayList(u8) = .empty;
    try upper.appendSlice(it.t, "EVE_SECRET_");
    for (name) |ch| try upper.append(it.t, std.ascii.toUpper(ch));
    const z = try it.t.dupeSentinel(u8, upper.items, 0);
    const found = std.c.getenv(z) orelse return it.failWith(err_key, "secret.get: no secret '{s}' (set {s})", .{ name, upper.items });
    return it.secretObject(try it.newStr(std.mem.span(found)));
}

pub fn runRoot(it: *Interp, root: *const Node) Signal!void {
    defer it.finalizeModules();
    defer db.closeDatabases(it.host());
    defer dlib.closeStreams(it);
    defer db.orm.closeCore(it.host());
    defer it.closeGenerators();
    for (root.kids) |d| if (d.tag == .import_decl) try it.execImport(d);
    for (root.kids) |d| {
        if (d.tag == .adopt or d.tag == .class or d.tag == .trait or d.tag == .function or d.tag == .procedure or d.tag == .method or d.tag == .generator) try it.declareRoutine(d);
    }
    for (root.kids) |d| if (d.tag == .table_decl) {
        try db.declareTables(it.host(), root.kids);
        break;
    };
    for (root.kids) |d| {
        if (d.tag == .var_decl or d.tag == .set) try it.exec(d);
    }
    const main = Interp.findProcess(root, "main") orelse return it.fail("the aspect has no process main", .{});
    // @eve-impl the bytecode machine runs `process main` after the same preparation as the tree walker (D-201)
    if (interp.engine == .bytecode and it.script_args.len == 0 and it.script_params.len == 0) {
        if (try @import("../bcvm.zig").runMain(it, root, main)) return;
    }
    // the arguments of the command line go to the parameters of the process
    // each text is converted to the type of its parameter; `-p name=value` goes to the parameter of that name (cmdargs.zig)
    try it.runProcess(main, try cmdargs.build(it, main), "aspect", root.text);
}
