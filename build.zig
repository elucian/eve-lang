//! @decision D-163
//! @decision D-167
//! Build Eve from the root: every step is the step of the package `eve` (code/eve/build.zig), which builds the command from
//! the packages evecm, evecp and evevm (design/components/README.md). This file only passes the version written once in build.zig.zon.
//!
//!   zig build            -> zig-out/bin/eve.exe
//!   zig build -p .       -> bin/eve.exe (the official location, D-007)
//!   zig build run -- <args>
//!   zig build test       -> the unit tests of every module
//!   zig build doc        -> lib/doc from the Eve sources of lib/
const std = @import("std");
const zon = @import("build.zig.zon");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const eve = b.dependency("eve", .{ .target = target, .optimize = optimize, .version = zon.version });

    // The install prefix is shared with the dependency, so its install lands in the prefix of this build.
    b.getInstallStep().dependOn(eve.builder.getInstallStep());
    const forwarded = [_][2][]const u8{
        .{ "run", "Run eve" },
        .{ "doc", "Generate lib/doc from the Eve sources in lib/ and lib/sys/" },
        .{ "eve", "Install bin/eve.exe and lib/" },
        .{ "evevm", "Install bin/evevm.exe (a copy of eve, the machine)" },
        .{ "test", "Run unit tests" },
    };
    for (forwarded) |step| {
        b.step(step[0], step[1]).dependOn(&eve.builder.top_level_steps.get(step[0]).?.step);
    }
}
