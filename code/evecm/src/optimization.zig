//! @eve-module optimization: the optimization level of a run, `-O n` on the command line or `optimization = n` in eve.cfg (D-227)
//! @spec spec/semantics/variables.md#optimization-level
//! @feature F-LIB-06
//! @decision D-227
//! @tests test/level5/e155_optimization_level
//! A whole number from 0 to 10; the implicit level is 1, the lowest. The level is set once at the start of a run and read by the scripts as `$optimization`; a script can not set it.
const std = @import("std");

pub const default_level: u8 = 1;
pub const max_level: u8 = 10;

/// The level of this process: set by `eve` before the script runs.
pub var level: u8 = default_level;

// @eve-fn parseLevel
// @spec spec/semantics/variables.md#optimization-level
// @feature F-LIB-06
// @test test/level5/e155_optimization_level
// @invariant only a whole number from 0 to 10 is a level; anything else is null
/// The level written in `text`, or null when it is not a whole number from 0 to 10.
pub fn parseLevel(text: []const u8) ?u8 {
    const n = std.fmt.parseInt(u8, std.mem.trim(u8, text, " "), 10) catch return null;
    if (n > max_level) return null;
    return n;
}

test "spec: variables.md#optimization-level the level is a whole number from 0 to 10" {
    try std.testing.expectEqual(@as(?u8, 10), parseLevel("10"));
    try std.testing.expectEqual(@as(?u8, 0), parseLevel(" 0 "));
    try std.testing.expectEqual(@as(?u8, null), parseLevel("11"));
    try std.testing.expectEqual(@as(?u8, null), parseLevel("-1"));
    try std.testing.expectEqual(@as(?u8, null), parseLevel("high"));
}
