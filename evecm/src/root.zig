//! evecm: the common part of Eve, the leaf of the module graph (design-packages.md §3). It holds
//! what every other part uses and imports nothing but `std` and the build options: the syntax
//! tree, the number and time types, the Unicode tables, the data codecs, the version, and the
//! terminal and line editor. It holds Zig code only, never data.
const std = @import("std");

// Zig tip: `pub const x = @import("file.zig");` re-exports a file under a name. This file is the
// public face of the module: the other modules write `@import("evecm").ast`, and the layout of
// the files behind it can change without touching them. Declarations are lazy: nothing is
// compiled until it is used.

/// The syntax tree that the parser makes and the interpreter walks.
pub const ast = @import("ast.zig");

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

/// The interfaces between the runtime and the database layer: `Host` and `Data`.
pub const iface = @import("iface.zig");

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

/// The version, written once in the root build.zig.zon: `version.version`, `version.title`.
pub const version = @import("version.zig");

// Zig tip: tests are found only in files that the compiler reaches. `_ = x;` inside an unnamed
// `test { }` references the file, so its tests also run with `zig build test`.
test {
    _ = ast;
    _ = decimal;
    _ = instant;
    _ = nfc;
    _ = value;
    _ = heap;
    _ = iface;
    _ = config;
    _ = wire;
    _ = data;
    _ = line;
    _ = terminal;
}

test "version strings are set" {
    try std.testing.expect(version.version.len > 0);
    try std.testing.expect(version.spec_version.len > 0);
}
