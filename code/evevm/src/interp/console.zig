//! @eve-module interp.console
//! @spec spec/syntax/statements.md#calls
//! @feature F-LIB-01
//! @tests test/level1/a96_read_line
//! The standard input of a script: `read(prompt)` reads one line and gives it as a String, `null` at the end of the input (Q-069).
//! Part of the interpreter (interp.zig): a call from calls.zig.
const std = @import("std");
const interp = @import("../interp.zig");
const Interp = interp.Interp;
const Node = interp.Node;
const Signal = interp.Signal;
const Value = interp.Value;

const err_io = 22;

var stdin_buf: [64 * 1024]u8 = undefined;
var stdin_reader: ?std.Io.File.Reader = null;

// @eve-fn io.read
// @spec spec/syntax/statements.md#calls
// @test a96_read_line
/// `read(prompt)`: write the prompt (optional), read a line from standard input and give it without its line end; `null` at the end of the input.
pub fn read(it: *Interp, args: []const *const Node) Signal!Value {
    if (args.len > 1) return it.fail("read(prompt) takes at most one argument", .{});
    if (args.len == 1) try it.out.writeAll(try it.text(try it.eval(args[0])));
    it.out.flush() catch {};
    const io = it.io orelse return it.fail("read(): no standard input", .{});
    if (stdin_reader == null) stdin_reader = .init(.stdin(), io, &stdin_buf);
    const line = stdin_reader.?.interface.takeDelimiter(10) catch return it.failWith(err_io, "read: cannot read the standard input", .{});
    const got = line orelse return .nil;
    return try it.newStr(std.mem.trimEnd(u8, got, "\r"));
}
