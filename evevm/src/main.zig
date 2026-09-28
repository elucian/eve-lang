//! `eve` command line: runs an Eve script on the virtual machine.
const std = @import("std");
const Io = std.Io;

const evevm = @import("evevm");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    const arg: []const u8 = if (args.len > 1) args[1] else "--help";
    if (std.mem.eql(u8, arg, "--version")) {
        try stdout.print("eve {s} (Eve {s})\n", .{ evevm.version, evevm.spec_version });
    } else if (std.mem.eql(u8, arg, "--help")) {
        try stdout.writeAll(evevm.usage);
    } else {
        // 70 (EX_SOFTWARE): an internal VM failure, so no test that expects a script's
        // own exit code can pass by accident.
        std.debug.print("eve: cannot run {s}: the interpreter is not implemented yet\n", .{arg});
        std.process.exit(70);
    }
    try stdout.flush();
}
