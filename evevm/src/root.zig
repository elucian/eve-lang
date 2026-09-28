//! Eve virtual machine library. The `eve` command in main.zig is a thin front end over it.
const std = @import("std");

/// Implementation version; keep in step with `build.zig.zon`.
pub const version = "0.0.0";

/// Specification version this implementation targets (spec/README.md).
pub const spec_version = "0.1-draft";

pub const usage =
    \\Usage: eve <script.eve> [args...]
    \\       eve --version
    \\       eve --help
    \\
;

test "version strings are set" {
    try std.testing.expect(version.len > 0);
    try std.testing.expect(spec_version.len > 0);
}
