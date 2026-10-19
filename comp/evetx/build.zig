//! Build evetx, the Eve text user interface (README.md).
//!
//!   zig build            -> zig-out/bin/evetx.exe
//!   zig build -p ../..   -> ../../bin/evetx.exe, next to eve.exe
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

    // The files that evetx shares with eveux (text buffer, scanner, project tree, machine link, grid, ...) live in
    // comp/evecm/src/ide.zig and import `std` only, so this module needs no build options. Their tests run in the root `zig build test`.
    const ide_mod = b.createModule(.{ .root_source_file = b.path("../evecm/src/ide.zig"), .target = target, .optimize = optimize });

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
                .{ .name = "ide", .module = ide_mod },
            },
        }),
    });
    // @eve-impl the texts of the help windows (Shortcuts, Manual, Tutorial), embedded as `help_<name>`
    // @see comp/evetx/doc/shortcuts.txt
    // the texts live in comp/evetx/doc/ (the doc of the component); script/genmanual.py copies that folder into manual/evetx/
    for ([_][]const u8{ "shortcuts", "manual", "tutorial" }) |name| {
        exe.root_module.addAnonymousImport(b.fmt("help_{s}", .{name}), .{
            .root_source_file = b.path(b.fmt("doc/{s}.txt", .{name})),
        });
    }
    // the version of Eve is written once, in the root build.zig.zon; the About dialog shows it
    exe.root_module.addAnonymousImport("eve_zon", .{ .root_source_file = b.path("../../build.zig.zon") });
    // Zig tip: a running program locks its .exe on Windows, so the copy into `bin/` fails with AccessDenied. The
    // step below runs a command (`addSystemCommand`) that stops the eve programs of that folder, and `dependOn` makes
    // the copy wait for it. Compiling goes on in parallel; only the install waits. The same script is `eve --kill`.
    // `builtin.os.tag` is the system the build runs on (not the target), so other systems skip the step.
    const stop = b.addSystemCommand(&.{ "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File" });
    stop.addFileArg(b.path("../../script/stop_eve.ps1"));
    stop.addArg("-Bin");
    stop.addFileArg(.{ .relative = .{ .base = .install_prefix, .sub_path = "bin" } });
    stop.has_side_effects = true;
    const install_exe = b.addInstallArtifact(exe, .{});
    if (@import("builtin").os.tag == .windows) install_exe.step.dependOn(&stop.step);
    b.getInstallStep().dependOn(&install_exe.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    // Zig tip: `b.args` holds what the user typed after `--` on the command line, so
    // `zig build run -- ..\test` passes `..\test` to evetx.
    run_cmd.addPassthruArgs();
    b.step("run", "Run evetx").dependOn(&run_cmd.step);

    // @eve-impl `zig build test` in comp/evetx/: the unit tests of the pure parts (the comment carry of view.zig, options; the shared files test in the root build)
    // @see comp/evetx/src/view.zig (`carryAfter`, `Scan`)
    const unit = b.addTest(.{ .root_module = exe.root_module });
    b.step("test", "Run the unit tests of evetx").dependOn(&b.addRunArtifact(unit).step);
}
