//! @eve-module check.nullable: the rules of optional types that the checker applies (T?, narrowing by a test against null)
//! @spec spec/semantics/types.md#narrowing-and-the-default
//! @feature F-LNG-14
//! @decision D-221
//! @tests test/level5/e146_optional_narrow, test/level5/e147_optional_arith_error, test/level5/e148_optional_method_error, test/level5/e149_optional_scope_error, test/level5/e150_null_to_plain_error
//! The pure part: the type text `T?` and the tests of a name against null. The checker (check.zig) keeps the names narrowed in the scope it checks.
const std = @import("std");
const ast = @import("evecm").ast;
const Node = ast.Node;

/// True for the type text of an optional type, `T?`.
pub fn isOptional(ty: ?[]const u8) bool {
    const t = ty orelse return false;
    return t.len > 1 and t[t.len - 1] == '?';
}

/// The plain type of an optional type text (`Integer?` gives `Integer`); any other text is returned as it is.
pub fn plainOf(ty: ?[]const u8) ?[]const u8 {
    const t = ty orelse return null;
    if (!isOptional(ty)) return t;
    return t[0 .. t.len - 1];
}

/// A test of a name against null: `x <> null` (`not_null`) or `x == null`.
pub const NullTest = struct { name: []const u8, not_null: bool };

fn isNullName(n: *const Node) bool {
    return n.tag == .name and std.mem.eql(u8, n.text, "null");
}

// @eve-impl the test of a name against null: `x <> null` and `null == x` are read the same way
// @spec spec/semantics/types.md#narrowing-and-the-default
// @feature F-LNG-14
// @test test/level5/e146_optional_narrow
/// The name compared with null in `cond`, or null when `cond` is not such a test.
pub fn nullTest(cond: *const Node) ?NullTest {
    if (cond.tag != .bin) return null;
    const not_null = if (std.mem.eql(u8, cond.text, "<>")) true else if (std.mem.eql(u8, cond.text, "==")) false else return null;
    const a = cond.kids[0];
    const b = cond.kids[1];
    if (isNullName(b) and a.tag == .name) return .{ .name = a.text, .not_null = not_null };
    if (isNullName(a) and b.tag == .name) return .{ .name = b.text, .not_null = not_null };
    return null;
}

/// True when the block ends by `exit;`, so the code after the `if` that holds it runs only when the test failed.
pub fn endsWithExit(b: *const Node) bool {
    return b.kids.len > 0 and b.kids[b.kids.len - 1].tag == .exit_stmt;
}

/// The operators that need a plain value on both sides: a `T?` operand is a compile error until a test narrows it.
pub fn needsPlain(op: []const u8) bool {
    const ops = [_][]const u8{ "+", "-", "*", "/", "%", "^", "<", ">", "<=", ">=" };
    for (ops) |o| if (std.mem.eql(u8, op, o)) return true;
    return false;
}

test "spec: types.md#narrowing-and-the-default optional type text and plain type" {
    try std.testing.expect(isOptional("Integer?"));
    try std.testing.expect(!isOptional("Integer"));
    try std.testing.expect(!isOptional(null));
    try std.testing.expectEqualStrings("Integer", plainOf("Integer?").?);
    try std.testing.expectEqualStrings("Integer", plainOf("Integer").?);
}

test "spec: types.md#narrowing-and-the-default operators that need a plain value" {
    try std.testing.expect(needsPlain("+"));
    try std.testing.expect(needsPlain("<="));
    try std.testing.expect(!needsPlain("=="));
    try std.testing.expect(!needsPlain("??"));
}
