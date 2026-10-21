//! Build Eve: one executable, `eve`, made of the packages evecm, evecp and evevm (code/<component>/build.zig, design/components/README.md).
//!
//!   zig build            -> zig-out/bin/eve.exe
//!   zig build -p .       -> bin/eve.exe (the official location, D-007)
//!   zig build run -- <args>
//!   zig build test       -> the unit tests of every module
//!   zig build doc        -> lib/doc from the Eve sources of lib/
//!
//! The arrows between the packages are their build.zig.zon files; a package that is not listed cannot be
//! imported, so a wrong import is a compile error, not a habit that creeps in:
//!
//!     eve ──► evevm ──► evecp ──► evecm
//!      ├────► evedb ─────────────────►
//!      └──────────────────────────────►
const std = @import("std");
// Zig tip: a `.zon` file is data in Zig syntax, and `@import` reads it into a struct at compile
// time. The version is written once, in build.zig.zon, and the build hands it to the code.
const zon = @import("build.zig.zon");

// Zig tip: `build` is an ordinary Zig function that the `zig build` command calls. It does not
// compile anything itself: it describes steps (compile, install, run, test) and how they depend
// on each other, and the build runner executes only the steps that are needed.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Each component is a package of its own (code/<component>/build.zig, listed in build.zig.zon) that exposes its module and
    // its unit tests. The arrows between the packages are their build.zig.zon files; the version of Eve goes to them as an option.
    const args = .{ .target = target, .optimize = optimize, .version = zon.version };
    const evecm_dep = b.dependency("evecm", args);
    const evecp_dep = b.dependency("evecp", args);
    const evevm_dep = b.dependency("evevm", args);
    const evecm = evecm_dep.module("evecm");
    const evecp = evecp_dep.module("evecp");
    const evevm = evevm_dep.module("evevm");

    // The `eve` command line.
    const exe = b.addExecutable(.{
        .name = "eve",
        .root_module = b.createModule(.{
            .root_source_file = b.path("code/eve/src/eve.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "evecm", .module = evecm },
                .{ .name = "evecp", .module = evecp },
                .{ .name = "evevm", .module = evevm },
            },
        }),
    });
    // Zig tip: a running program locks its .exe on Windows, so the copy into `bin/` fails with AccessDenied. The
    // step below runs a command (`addSystemCommand`) that stops the eve programs of that folder, and `dependOn` makes
    // the copy wait for it. Compiling goes on in parallel; only the install waits. The same script is `eve --kill`.
    // `builtin.os.tag` is the system the build runs on (not the target), so other systems skip the step.
    const stop = b.addSystemCommand(&.{ "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File" });
    stop.addFileArg(b.path("script/stop_eve.ps1"));
    stop.addArg("-Bin");
    stop.addFileArg(.{ .relative = .{ .base = .install_prefix, .sub_path = "bin" } });
    stop.has_side_effects = true;
    const install_exe = b.addInstallArtifact(exe, .{});
    if (@import("builtin").os.tag == .windows) install_exe.step.dependOn(&stop.step);
    b.getInstallStep().dependOn(&install_exe.step);

    // Zig tip: `addInstallBinFile` copies a file into `bin/` under another name. The program `evevm` is the very same
    // file as `eve`: at start it reads its own name (code/eve/src/eve.zig), and as `evevm` it starts the machine in a new process.
    // `getEmittedBin()` is the file the compiler makes, so the copy waits for the build of `eve`. The extension of the
    // copy follows the target (`.exe` on Windows, none elsewhere).
    const evevm_name = b.fmt("evevm{s}", .{target.result.exeFileExt()});
    const install_evevm = b.addInstallBinFile(exe.getEmittedBin(), evevm_name);
    install_evevm.step.dependOn(&install_exe.step);
    b.getInstallStep().dependOn(&install_evevm.step);

    const run_step = b.step("run", "Run eve");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    // `zig build doc` writes lib/doc from lib/ (the standard modules in Eve) and lib/sys/ (the signatures of the
    // native modules) with the `doc` command of eve (`eve --doc`, D-082, D-189).
    const doc_step = b.step("doc", "Generate lib/doc from the Eve sources in lib/ and lib/sys/");
    for ([_][]const u8{ "lib", "lib/sys" }) |folder| {
        const doc_cmd = b.addRunArtifact(exe);
        doc_cmd.addArgs(&.{ "--doc", folder, "lib/doc" });
        doc_cmd.setCwd(b.path("."));
        doc_step.dependOn(&doc_cmd.step);
    }

    // The standard library in Eve is found beside the program: `<prefix>/lib/*.eve` for `<prefix>/bin/eve.exe`
    // (code/eve/src/eve.zig, `standardLibrary`). With `-p .` the prefix is the repository and the copy lands on the same files
    // (Zig 0.17 cannot tell the prefix while configuring, so the step is always there).
    const install_lib = b.addInstallDirectory(.{
        .source_dir = b.path("lib"),
        .install_dir = .prefix,
        .install_subdir = "lib",
        .exclude_extensions = &.{"md"},
    });
    b.getInstallStep().dependOn(&install_lib.step);

    // The parts of the install by name: `zig build eve` installs bin/eve.exe and lib/, `zig build evevm` installs
    // bin/evevm.exe. `zig build` with no step installs both, as before. run.sh builds the parts one by one.
    const eve_step = b.step("eve", "Install bin/eve.exe and lib/");
    eve_step.dependOn(&install_exe.step);
    eve_step.dependOn(&install_lib.step);
    const evevm_step = b.step("evevm", "Install bin/evevm.exe (a copy of eve, the machine)");
    evevm_step.dependOn(&install_evevm.step);

    // The tests: the program `eve` itself, and the test step of each package.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = exe.root_module })).step);
    for ([_]*std.Build.Dependency{ evecm_dep, evecp_dep, evevm_dep }) |dep| {
        test_step.dependOn(&dep.builder.top_level_steps.get("test").?.step);
    }
}
