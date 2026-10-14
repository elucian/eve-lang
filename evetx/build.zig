//! Build evetx, the Eve text user interface (README.md).
//!
//!   zig build            -> zig-out/bin/evetx.exe
//!   zig build -p ..      -> ../bin/evetx.exe, next to eve.exe
//!   zig build run
//!
//! evetx is a separate program until the split of design-packages.md exists; then this folder
//! becomes the module `evetx` of the root build.zig (README.md §11).
const std = @import("std");

// Zig tip: `build` is an ordinary Zig function that the `zig build` command calls. It does not
// compile anything itself: it describes steps (compile, install, run) and how they depend on
// each other, and the build runner executes only the steps that are needed.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Zig tip: `b.dependency("vaxis", ...)` loads the package named `vaxis` in build.zig.zon
    // (fetched once into the global cache, checked by its hash). The options after the name are
    // passed to that package's own build.zig, so it is compiled for the same target and mode.
    const vaxis_dep = b.dependency("vaxis", .{ .target = target, .optimize = optimize });

    const exe = b.addExecutable(.{
        .name = "evetx",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            // Zig tip: `.imports` gives the code a named module to `@import`. Only this program
            // can write `@import("vaxis")`: the other parts of Eve do not see the library.
            .imports = &.{
                .{ .name = "vaxis", .module = vaxis_dep.module("vaxis") },
            },
        }),
    });
    // Zig tip: `addAnonymousImport` gives a file a name that `@embedFile("name")` understands, even
    // when the file is outside the source folder of the program. The text of the help windows is
    // therefore a plain file in `manual/evetx/`, and it is copied into the program at build time.
    for ([_][]const u8{ "shortcuts", "manual", "tutorial" }) |name| {
        exe.root_module.addAnonymousImport(b.fmt("help_{s}", .{name}), .{
            .root_source_file = b.path(b.fmt("../manual/evetx/{s}.txt", .{name})),
        });
    }
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    // Zig tip: `b.args` holds what the user typed after `--` on the command line, so
    // `zig build run -- ..\test` passes `..\test` to evetx.
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run evetx").dependOn(&run_cmd.step);
}
