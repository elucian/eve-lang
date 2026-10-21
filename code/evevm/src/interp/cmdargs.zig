//! @eve-module interp.cmdargs
//! @spec spec/semantics/aspects.md#parameters-on-the-command-line
//! @feature F-STR-05
//! @tests test/level1/a98_script_params
//! The arguments of the command line become the arguments of `process main`: a text is converted to the type of the parameter.
//! Part of the interpreter (interp.zig): called from runRoot (datatypes.zig).
const std = @import("std");
const interp = @import("../interp.zig");
const decimal = interp.decimal;
const Interp = interp.Interp;
const Node = interp.Node;
const Signal = interp.Signal;
const Value = interp.Value;
const Arg = interp.Arg;
const err_argument = interp.err_argument;

// @eve-impl the arguments after the script name, and `-p name=value`, with the types of the parameters of `main`
// @spec spec/semantics/aspects.md#parameters-on-the-command-line
// @test a98_script_params
/// A positional text goes to the next parameter, `-p name=value` to the parameter of that name.
pub fn build(it: *Interp, main: *const Node) Signal![]Arg {
    const params = main.kids[3].kids;
    var out: std.ArrayList(Arg) = .empty;
    var k: usize = 0;
    for (it.script_args) |text| {
        // the vararg takes the rest as texts
        while (k < params.len and params[k].tag != .vararg_param and isNamed(it, params[k].text)) k += 1;
        if (k >= params.len or params[k].tag == .vararg_param) {
            try out.append(it.a, .{ .value = try it.staticStr(text) });
            continue;
        }
        try out.append(it.a, .{ .value = try convert(it, params[k].text, text, params[k].ty) });
        k += 1;
    }
    for (it.script_params) |p| {
        var ty: ?*const Node = null;
        for (params) |prm| if (std.mem.eql(u8, prm.text, p.name)) {
            ty = prm.ty;
        };
        try out.append(it.a, .{ .name = p.name, .value = try convert(it, p.name, p.value, ty) });
    }
    return out.items;
}

fn isNamed(it: *Interp, name: []const u8) bool {
    for (it.script_params) |p| if (std.mem.eql(u8, p.name, name)) return true;
    return false;
}

/// One text to a value of the declared type: Integer, Real, Logic (`True`, `False`), Decimal, String (quotes optional),
/// a list `(a, b, c)` of those, an optional type (`null`).
fn convert(it: *Interp, name: []const u8, text_in: []const u8, ty: ?*const Node) Signal!Value {
    const t = ty orelse return it.staticStr(text_in);
    return convertAs(it, name, std.mem.trim(u8, text_in, " "), t.text);
}

fn convertAs(it: *Interp, name: []const u8, text: []const u8, type_text: []const u8) Signal!Value {
    const eql = std.mem.eql;
    if (type_text.len > 0 and type_text[type_text.len - 1] == '?') {
        if (eql(u8, text, "null") or eql(u8, text, "Null")) return .nil;
        return convertAs(it, name, text, type_text[0 .. type_text.len - 1]);
    }
    if (std.mem.startsWith(u8, type_text, "()") or std.mem.startsWith(u8, type_text, "[]")) {
        const array = type_text[0] == '[';
        var inner = text;
        if (inner.len >= 2 and (inner[0] == '(' or inner[0] == '[') and (inner[inner.len - 1] == ')' or inner[inner.len - 1] == ']')) inner = inner[1 .. inner.len - 1];
        var items: std.ArrayList(Value) = .empty;
        var start: usize = 0;
        var quoted = false;
        for (inner, 0..) |c, i| {
            if (c == '"') quoted = !quoted;
            if (c == ',' and !quoted) {
                try items.append(it.t, try convertAs(it, name, std.mem.trim(u8, inner[start..i], " "), type_text[2..]));
                start = i + 1;
            }
        }
        const last = std.mem.trim(u8, inner[start..], " ");
        if (last.len > 0 or items.items.len > 0) try items.append(it.t, try convertAs(it, name, last, type_text[2..]));
        return .{ .list = try it.newList(items.items, array) };
    }
    if (eql(u8, type_text, "Integer") or eql(u8, type_text, "Short") or eql(u8, type_text, "Byte")) {
        const v = std.fmt.parseInt(i64, text, 10) catch return notA(it, name, text, "an Integer");
        return .{ .int = v };
    }
    if (eql(u8, type_text, "Natural")) {
        const v = std.fmt.parseInt(i64, text, 0) catch return notA(it, name, text, "a Natural");
        return .{ .nat = v };
    }
    if (eql(u8, type_text, "Real") or eql(u8, type_text, "Float")) {
        const v = std.fmt.parseFloat(f64, text) catch return notA(it, name, text, "a number");
        return .{ .real = v };
    }
    if (eql(u8, type_text, "Logic")) {
        if (eql(u8, text, "True")) return .{ .bool = true };
        if (eql(u8, text, "False")) return .{ .bool = false };
        return notA(it, name, text, "True or False");
    }
    if (eql(u8, type_text, "Decimal")) {
        const v = decimal.parse(text) orelse return notA(it, name, text, "a Decimal");
        return .{ .dec = v };
    }
    // String, and every other type: the text itself, without the quotes of a literal
    if (text.len >= 2 and text[0] == '"' and text[text.len - 1] == '"') return it.staticStr(text[1 .. text.len - 1]);
    return it.staticStr(text);
}

fn notA(it: *Interp, name: []const u8, text: []const u8, what: []const u8) Signal {
    return it.failWith(err_argument, "parameter {s}: '{s}' is not {s}", .{ name, text, what });
}
