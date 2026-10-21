//! @eve-module interp.console
//! @spec spec/syntax/statements.md#calls
//! @feature F-LIB-01
//! @tests test/level1/a96_read_line
//! The standard input of a script: `read(@v, prompt)` reads one line into the variable `v`.
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
/// `read(@v, "prompt")`: write the prompt, read a line from standard input (without its line end) into `v`.
/// At the end of input the error `$err_io` is raised (open question Q-069).
pub fn read(it: *Interp, args: []const *const Node) Signal!Value {
    if (args.len < 1 or args.len > 2 or args[0].tag != .ref or args[0].kids.len > 0)
        return it.fail("read(@v, prompt) needs a variable written with @", .{});
    const cell = it.scope.find(args[0].text) orelse return it.fail("undefined name '{s}'", .{args[0].text});
    if (cell.constant) return it.fail("'{s}' is a constant", .{args[0].text});
    if (args.len == 2) try it.out.writeAll(try it.text(try it.eval(args[1])));
    it.out.flush() catch {};
    const io = it.io orelse return it.fail("read(): no standard input", .{});
    if (stdin_reader == null) stdin_reader = .init(.stdin(), io, &stdin_buf);
    const line = stdin_reader.?.interface.takeDelimiter('\n') catch return it.failWith(err_io, "read: cannot read the standard input", .{});
    const got = line orelse return it.failWith(err_io, "read: end of input", .{});
    const v = try it.newStr(std.mem.trimEnd(u8, got, "\r"));
    it.setVar(cell, v);
    return .nil;
}
