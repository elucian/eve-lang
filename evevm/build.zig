//! Build the Eve virtual machine.
//!
//!   zig build            -> zig-out/bin/eve.exe
//!   zig build -p ..      -> ../bin/eve.exe (the official location, D-007)
//!   zig build run -- <args>
//!   zig build test
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The VM as a library module: lexer, parser, interpreter.
    const mod = b.addModule("evevm", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    // The `eve` command line.
    const exe = b.addExecutable(.{
        .name = "eve",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "evevm", .module = mod },
            },
        }),
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run eve");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // `eved`, the Eve documentation tool: `zig build doc` writes doc/ from lib/.
    const eved = b.addExecutable(.{
        .name = "eved",
        .root_module = b.createModule(.{
            .root_source_file = b.path("doc/eved.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(eved);
    const doc_cmd = b.addRunArtifact(eved);
    doc_cmd.addArgs(&.{ "lib", "doc" });
    doc_cmd.setCwd(b.path("."));
    const doc_step = b.step("doc", "Generate doc/ from the Eve sources in lib/");
    doc_step.dependOn(&doc_cmd.step);

    const mod_tests = b.addTest(.{ .root_module = mod });
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(mod_tests).step);
    test_step.dependOn(&b.addRunArtifact(exe_tests).step);
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = eved.root_module })).step);
}
