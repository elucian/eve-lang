//! @eve-module evecp.main
//! @spec manual/usage.md
//! @decision D-198
//! The program `evecp` (`bin/evecp.exe`): the compiler front end as a command. It checks scripts, writes documentation and
//! makes projects (`cli.zig`); later it compiles to bytecode. The same commands run inside `eve` as `eve cp ...`.
const std = @import("std");
const Io = std.Io;
const evecm = @import("evecm");
const cli = @import("cli.zig");

// @eve-impl the entry point of evecp: -v, -h, or a command of cli.zig; the output is written at the end, the status is the exit code
pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    // `initStreaming` writes where the system says (the end of a file with `>>`), like a pipe or a terminal.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .initStreaming(.stdout(), init.io, &stdout_buffer);
    const out = &stdout_file_writer.interface;

    const rest = args[@min(1, args.len)..];
    var code: u8 = 0;
    if (rest.len == 1 and (std.mem.eql(u8, rest[0], "-v") or std.mem.eql(u8, rest[0], "--version"))) {
        try out.print("evecp {s}\n", .{evecm.version.version});
    } else if (rest.len == 1 and (std.mem.eql(u8, rest[0], "-h") or std.mem.eql(u8, rest[0], "--help"))) {
        try out.writeAll(cli.usage);
    } else {
        code = try cli.run(.{ .io = init.io, .gpa = init.gpa, .out = out }, rest);
    }
    try out.flush();
    std.process.exit(code);
}
