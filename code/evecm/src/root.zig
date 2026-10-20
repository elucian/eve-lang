//! evecm: the common part of Eve, the leaf of the module graph (design-packages.md §3). It holds
//! what every other part uses and imports nothing but `std` and the build options: the syntax
//! tree, the number and time types, the Unicode tables, the data codecs, the version, and the
//! terminal and line editor, and the files that evetx and eveux share (`ide`). It holds Zig code only, never data.
const std = @import("std");

/// The syntax tree that the parser makes and the interpreter walks.
pub const ast = @import("ast.zig");
/// The instructions of the register machine (bytecode).
pub const op = @import("op.zig");
/// The compiled form of a program.
pub const chunk = @import("chunk.zig");

/// The `Decimal` type (exact numbers).
pub const decimal = @import("decimal.zig");

/// The `Instant` type and the calendar.
pub const instant = @import("instant.zig");

/// Unicode normalization form C.
pub const nfc = @import("nfc.zig");

/// The values of a script and the objects they point to.
pub const value = @import("value.zig");

/// The heap of the values: reference counting, regions and the tracing collector.
pub const heap = @import("heap.zig");

/// The configuration of a machine: `eve.cfg`, the socket folder, the exit codes.
pub const config = @import("config.zig");

/// JSON-RPC, the HTTP answers of the web door, and the client calls to a machine.
pub const wire = @import("wire.zig");

/// CSV and JSON text, and connection URLs.
pub const data = @import("data.zig");

/// The line editor of the prompt.
pub const line = @import("line.zig");

/// Raw keyboard mode of the REPL prompt.
pub const terminal = @import("terminal.zig");

/// What the two editors share, evetx and eveux: text buffer, Eve scanner, keywords, project tree, machine link, regex, grid, sqlstruct, cache.
pub const ide = @import("ide.zig");

/// The version, written once in the root build.zig.zon: `version.version`, `version.title`.
pub const version = @import("version.zig");

test {
    _ = ast;
    _ = op;
    _ = chunk;
    _ = decimal;
    _ = instant;
    _ = nfc;
    _ = value;
    _ = heap;
    _ = config;
    _ = wire;
    _ = data;
    _ = line;
    _ = terminal;
    _ = ide;
}

test "version strings are set" {
    try std.testing.expect(version.version.len > 0);
    try std.testing.expect(version.spec_version.len > 0);
}
