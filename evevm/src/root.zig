//! Eve virtual machine library. The `eve` command in main.zig is a thin front end over it.
const std = @import("std");

// Zig tip: `pub const x = y;` re-exports a declaration under another name. This file is the
// public face of the library: the program sees `evevm.version` and `evevm.cli`, not the file
// layout behind them. Declarations are lazy: nothing is compiled until it is used.
const v = @import("version.zig");

pub const version = v.version;
pub const spec_version = v.spec_version;
pub const title = v.title;

/// Command line, jump table and REPL.
pub const cli = @import("cli.zig");

/// Execution loop and the slot for external commands.
pub const vm = @import("vm.zig");

/// Raw keyboard mode of the REPL prompt.
pub const terminal = @import("terminal.zig");
pub const project = @import("project.zig");

/// The heap of the values: reference counting, regions and the tracing collector.
pub const heap = @import("heap.zig");

// Zig tip: tests are found only in files that the compiler reaches. `_ = cli;` inside an
// unnamed `test { }` references the file so its tests also run with `zig build test`.
test {
    _ = cli;
    _ = @import("line.zig");
    _ = terminal;
    _ = vm;
    _ = @import("lexer.zig");
    _ = @import("parser.zig");
    _ = @import("check.zig");
    _ = @import("project.zig");
    _ = @import("ast.zig");
    _ = @import("interp.zig");
    _ = @import("scratch.zig");
    _ = heap;
    _ = @import("doc.zig");
}

test "version strings are set" {
    try std.testing.expect(version.len > 0);
    try std.testing.expect(spec_version.len > 0);
}
