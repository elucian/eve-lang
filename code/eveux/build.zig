//! @eve-module eveux build: the native workbench, a Zig program on dvui (see README.md, design/)
//! @spec code/eveux/README.md#7-the-code
//! @decision D-193
//! Build from code/eveux/: `zig build -p ../..` installs `bin/eveux.exe`; `-Dbackend=dx11|sdl3` chooses the window backend.
const std = @import("std");

const Backend = enum { sdl3, dx11 };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const backend = b.option(Backend, "backend", "window backend of dvui (default sdl3; dx11 is Windows only)") orelse .sdl3;

    // the option of dvui has to be a literal, so each backend has its own call
    const dvui_dep = switch (backend) {
        .sdl3 => b.dependency("dvui", .{ .target = target, .optimize = optimize, .backend = .sdl3 }),
        .dx11 => b.dependency("dvui", .{ .target = target, .optimize = optimize, .backend = .dx11 }),
    };
    const dvui_mod = dvui_dep.module(switch (backend) {
        .sdl3 => "dvui_sdl3",
        .dx11 => "dvui_dx11",
    });

    // The files that evetx and eveux share, as one module (code/evecm/src/ide.zig): text buffer, Eve scanner, keywords,
    // project tree, machine link, regex, grid, sqlstruct, cache. See README.md section 6.
    const ide_mod = b.createModule(.{ .root_source_file = b.path("../evecm/src/ide.zig"), .target = target, .optimize = optimize });

    const exe = b.addExecutable(.{
        .name = "eveux",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{ .{ .name = "dvui", .module = dvui_mod }, .{ .name = "ide", .module = ide_mod } },
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    b.step("run", "Run eveux").dependOn(&run_cmd.step);

    // @eve-impl `zig build test` in code/eveux/: the files with no window code, each as its own test root (they import `ide` only)
    const test_step = b.step("test", "Run the unit tests of eveux (the logic that has no window)");
    for ([_][]const u8{ "src/app.zig", "src/editor/lang.zig", "src/preview/kind.zig", "src/preview/markdown.zig", "src/vcs/git_status.zig", "src/deploy/manifest.zig" }) |file| {
        const t = b.addTest(.{ .root_module = b.createModule(.{
            .root_source_file = b.path(file),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "ide", .module = ide_mod }},
        }) });
        test_step.dependOn(&b.addRunArtifact(t).step);
    }
}
