//! Build evedb, the Eve test database (README.md).
//!
//!   zig build            -> zig-out/bin/evedb.exe (+ duckdb.dll on Windows)
//!   zig build -p ..      -> ../bin/evedb.exe, next to eve.exe
//!   zig build run
//!   zig build test
const std = @import("std");

// Zig tip: `build` is an ordinary Zig function that the `zig build` command calls. It does not
// compile anything itself: it describes steps (compile, install, run, test) and how they depend
// on each other, and the build runner executes only the steps that are needed.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Zig tip: `switch` on an enum must cover every value or have `else`. Here the operating
    // system of the target chooses the name of the DuckDB package of build.zig.zon.
    const os = target.result.os.tag;
    const dep_name = switch (os) {
        .windows => "duckdb_windows_amd64",
        .linux => "duckdb_linux_amd64",
        .macos => "duckdb_osx_universal",
        else => @panic("evedb: no prebuilt DuckDB library for this system"),
    };
    // Zig tip: a lazy dependency (`.lazy = true` in build.zig.zon) is downloaded only when a
    // build asks for it. `lazyDependency` returns null the first time; the runner then fetches
    // the package and runs `build` again, so returning early is the expected path, not an error.
    const duckdb_dep = b.lazyDependency(dep_name, .{}) orelse return;

    // The C header of DuckDB, translated into the Zig module `duckdb_c`.
    const duckdb_c = b.addTranslateC(.{
        .root_source_file = duckdb_dep.path("duckdb.h"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "evedb",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "duckdb_c", .module = duckdb_c.createModule() },
            },
        }),
    });
    // The prebuilt library: the import library duckdb.lib on Windows, libduckdb.so / .dylib elsewhere.
    exe.root_module.addLibraryPath(duckdb_dep.path(""));
    exe.root_module.linkSystemLibrary("duckdb", .{});
    b.installArtifact(exe);

    // Zig tip: `addInstallFileWithDir` makes a step that copies a file (here a `LazyPath` inside
    // a dependency) into a folder of the install prefix; `dependOn` adds it to `zig build`.
    // On Windows a program finds its DLLs in its own folder, so duckdb.dll goes next to evedb.exe.
    if (os == .windows) {
        const dll = b.addInstallFileWithDir(duckdb_dep.path("duckdb.dll"), .bin, "duckdb.dll");
        b.getInstallStep().dependOn(&dll.step);
    }

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    b.step("run", "Run evedb").dependOn(&run_cmd.step);

    const tests = b.addTest(.{ .root_module = exe.root_module });
    const run_tests = b.addRunArtifact(tests);
    // The test program needs duckdb.dll too: run it from the install folder, where the DLL is.
    run_tests.step.dependOn(b.getInstallStep());
    if (os == .windows) run_tests.setCwd(.{ .cwd_relative = b.getInstallPath(.bin, "") });
    b.step("test", "Run unit tests").dependOn(&run_tests.step);
}
