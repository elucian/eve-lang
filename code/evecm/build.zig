//! @eve-module evecm.build
//! evecm: the common part of Eve, a package of its own (design/components/README.md).
//! It exposes the module `evecm` and runs its own unit tests: `zig build test` in code/evecm/.
//! The version of Eve is written once, in the root `build.zig.zon`, and given by the root build as the option `version`.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const options = b.addOptions();
    options.addOption([]const u8, "version", b.option([]const u8, "version", "the version of Eve (the root build.zig.zon)") orelse "0.0.0");

    const evecm = b.addModule("evecm", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "build_options", .module = options.createModule() }},
    });

    const test_step = b.step("test", "Run the unit tests of evecm");
    const run_tests = b.addRunArtifact(b.addTest(.{ .root_module = evecm }));
    // some tests read the files of the repository (a folder of .eve files): they run from the root, as in the root build
    run_tests.setCwd(b.path("../.."));
    test_step.dependOn(&run_tests.step);
}
