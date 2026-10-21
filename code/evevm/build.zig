//! @eve-module evevm.build
//! evevm: the runtime of Eve, a package of its own (design/components/README.md).
//! It exposes the module `evevm` (the interpreter, the machine and the database layer, with SQLite compiled in) and
//! runs its own unit tests: `zig build test` in code/evevm/. The program `eve` that uses it is built by the root build.zig.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const version = b.option([]const u8, "version", "the version of Eve (the root build.zig.zon)") orelse "0.0.0";

    const evecm = b.dependency("evecm", .{ .target = target, .optimize = optimize, .version = version }).module("evecm");
    const evecp = b.dependency("evecp", .{ .target = target, .optimize = optimize, .version = version }).module("evecp");

    // the wire protocol shared with the DuckDB server
    // @see drivers/duckdb/build.zig (the server makes the same module from the same files)
    const ewp_protocol = b.addModule("ewp_protocol", .{
        .root_source_file = b.path("../../drivers/duckdb/protocol/protocol.zig"),
        .target = target,
        .optimize = optimize,
    });

    const evevm = b.addModule("evevm", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        // the secrets of a script are read from the environment with the C library
        .link_libc = true,
        .imports = &.{
            .{ .name = "evecm", .module = evecm },
            .{ .name = "evecp", .module = evecp },
            .{ .name = "ewp_protocol", .module = ewp_protocol },
        },
    });

    // SQLite, the core database (design/design-database-core.md), compiled from the amalgamation into a static library
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
    const sqlite_c = b.addTranslateC(.{
        .root_source_file = sqlite_dep.path("sqlite3.h"),
        .target = target,
        .optimize = optimize,
    });
    evevm.addImport("sqlite_c", sqlite_c.createModule());
    evevm.linkLibrary(sqlite_lib);

    // one test program for the runtime and one for the protocol; they run from the root of the repository
    const test_step = b.step("test", "Run the unit tests of evevm");
    for ([_]*std.Build.Module{ evevm, ewp_protocol }) |m| {
        const run_tests = b.addRunArtifact(b.addTest(.{ .root_module = m }));
        run_tests.setCwd(b.path("../.."));
        test_step.dependOn(&run_tests.step);
    }
}
