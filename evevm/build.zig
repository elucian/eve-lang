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

    // Zig tip: `b.dependency("sqlite", .{})` finds the package named in build.zig.zon (fetched
    // once by `zig build`, checked against its hash, kept in the global cache); `dep.path(...)`
    // names a file inside it. Nothing of SQLite is copied into this repository.
    // SQLite, the core database (design-database-core.md §2), compiled from the amalgamation
    // into a static library and linked into the VM.
    const sqlite_dep = b.dependency("sqlite", .{});
    const sqlite_lib = b.addLibrary(.{
        .name = "sqlite3",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    sqlite_lib.root_module.addCSourceFile(.{
        .file = sqlite_dep.path("sqlite3.c"),
        .flags = &.{
            "-DSQLITE_THREADSAFE=1", // serialized: safe whatever thread uses a connection
            "-DSQLITE_DEFAULT_FOREIGN_KEYS=1", // foreign keys checked unless turned off
            "-DSQLITE_DQS=0", // "x" is always a name, never a string (Eve quotes names)
            "-DSQLITE_OMIT_LOAD_EXTENSION", // no native code loaded from a database
            "-DSQLITE_OMIT_DEPRECATED",
            "-DSQLITE_DEFAULT_MEMSTATUS=0", // no global memory counters: faster malloc
            "-DSQLITE_ENABLE_MATH_FUNCTIONS",
        },
    });
    // Zig tip: `addTranslateC` turns a C header into a Zig module at build time, replacing
    // `@cImport` in the source: the module is imported by name (`@import("sqlite_c")`).
    const sqlite_c = b.addTranslateC(.{
        .root_source_file = sqlite_dep.path("sqlite3.h"),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("sqlite_c", sqlite_c.createModule());
    mod.linkLibrary(sqlite_lib);

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

    // `zig build doc` writes doc/ from lib/ with the `doc` command of eve (`eve --doc`, D-082).
    const doc_cmd = b.addRunArtifact(exe);
    doc_cmd.addArgs(&.{ "--doc", "lib", "doc" });
    doc_cmd.setCwd(b.path("."));
    const doc_step = b.step("doc", "Generate doc/ from the Eve sources in lib/");
    doc_step.dependOn(&doc_cmd.step);

    const mod_tests = b.addTest(.{ .root_module = mod });
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(mod_tests).step);
    test_step.dependOn(&b.addRunArtifact(exe_tests).step);
}
