//! @eve-module errclasses: the classes of the errors of the language (`Error`, `DivideError`, `FormatError` ...) and the code each one stands for
//! @spec spec/semantics/errors.md#error-classes
//! @feature F-LNG-15
//! @tests test/level3/c61_error_classes
//! One class per `$err_` code (errors.md#error-codes), all below `Error`; `SqlError` is below `DatabaseError`. The values are shared by every run, so `x is DivideError` means the same in every aspect and module.
const std = @import("std");
const value = @import("value.zig");
const Class = value.Class;

const Entry = struct { name: []const u8, code: i64, parent: []const u8 = "Error" };

// @invariant the table is in the order of the codes; `Error` is first and has code 0 (it stands for no code in particular)
const table = [_]Entry{
    .{ .name = "Error", .code = 0, .parent = "" },
    .{ .name = "PanicError", .code = 1 },
    .{ .name = "ExpectError", .code = 2 },
    .{ .name = "AssertError", .code = 3 },
    .{ .name = "RaiseError", .code = 4 },
    .{ .name = "IndexError", .code = 10 },
    .{ .name = "KeyError", .code = 11 },
    .{ .name = "DivideError", .code = 12 },
    .{ .name = "OverflowError", .code = 13 },
    .{ .name = "ConvertError", .code = 14 },
    .{ .name = "ParseError", .code = 15 },
    .{ .name = "NullError", .code = 16 },
    .{ .name = "ArgumentError", .code = 17 },
    .{ .name = "FileError", .code = 20 },
    .{ .name = "AccessError", .code = 21 },
    .{ .name = "IoError", .code = 22 },
    .{ .name = "ModuleError", .code = 30 },
    .{ .name = "ProcessError", .code = 31 },
    .{ .name = "MemoryError", .code = 40 },
    .{ .name = "TimeoutError", .code = 41 },
    .{ .name = "DeadlockError", .code = 42 },
    .{ .name = "OutputError", .code = 43 },
    .{ .name = "RecursionError", .code = 44 },
    .{ .name = "ParallelError", .code = 45 },
    .{ .name = "ChannelError", .code = 46 },
    .{ .name = "DatabaseError", .code = 50 },
    .{ .name = "ConnectionError", .code = 51 },
    .{ .name = "ConstraintError", .code = 52 },
    .{ .name = "ConflictError", .code = 53 },
    .{ .name = "MappingError", .code = 54 },
    .{ .name = "CommitError", .code = 55 },
    .{ .name = "FormatError", .code = 56 },
    .{ .name = "HttpError", .code = 57 },
    .{ .name = "BatchError", .code = 58 },
    .{ .name = "SqlError", .code = 59, .parent = "DatabaseError" },
};

/// The classes, filled by `init`.
pub var classes: [table.len]Class = undefined;
var ready = false;

/// Makes the classes. Call it before the first thread starts (the prelude of a run does).
pub fn init() void {
    if (ready) return;
    for (table, 0..) |e, i| classes[i] = .{ .name = e.name };
    for (table, 0..) |e, i| {
        if (e.parent.len == 0) continue;
        classes[i].parent = byName(e.parent);
    }
    ready = true;
}

/// The names of the classes, for the checker (which does not make them).
pub fn names() []const Entry {
    return &table;
}

pub fn isName(name: []const u8) bool {
    for (table) |e| if (std.mem.eql(u8, e.name, name)) return true;
    return false;
}

/// The class called `name`, or null.
pub fn byName(name: []const u8) ?*Class {
    for (table, 0..) |e, i| if (std.mem.eql(u8, e.name, name)) return &classes[i];
    return null;
}

/// The code that a class stands for (0 for `Error`), or null when `c` is not a class of this file.
pub fn codeOf(c: *const Class) ?i64 {
    const base = @intFromPtr(&classes[0]);
    const at = @intFromPtr(c);
    if (at < base or at >= base + @sizeOf(@TypeOf(classes))) return null;
    return table[(at - base) / @sizeOf(Class)].code;
}

// @eve-fn error_type
// @spec spec/semantics/errors.md#error-classes
/// The class of an error code, null when the language has no class for it (a code of the program, 0, a negative number).
pub fn byCode(code: i64) ?*Class {
    for (table, 0..) |e, i| if (e.code == code and code != 0) return &classes[i];
    return null;
}

test "spec: errors.md#error-classes every code has its class and SqlError is a DatabaseError" {
    init();
    try std.testing.expectEqualStrings("DivideError", byCode(12).?.name);
    try std.testing.expectEqualStrings("FormatError", byCode(56).?.name);
    try std.testing.expect(byCode(9999) == null);
    try std.testing.expect(byName("SqlError").?.parent == byName("DatabaseError").?);
    try std.testing.expect(byName("DatabaseError").?.parent == byName("Error").?);
    try std.testing.expect(isName("Error") and !isName("Nothing"));
}
