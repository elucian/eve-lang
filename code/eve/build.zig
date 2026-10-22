//! @eve-module eve
//! @decision D-163
//! @decision D-167
//! The command `eve` (bin/eve.exe, its copy bin/evevm.exe and lib/) from the packages evecm, evecp and evevm.
//! The root build.zig forwards its steps here, so `zig build -p .` from the root and `zig build -p ../..` from code/eve/ do the same.
//!
//!     eve ──► evevm ──► evecp ──► evecm
//!      ├────► evedb ─────────────────►
//!      └──────────────────────────────►
const std = @import("std");

// @eve-impl read `.version` of the root build.zig.zon when the build is configured (the file is outside this package)
// @see code/evecp/build.zig:rootVersion
fn rootVersion(b: *std.Build) []const u8 {
    const path = b.root.joinString(b.graph.arena, "../../build.zig.zon") catch @panic("OOM");
    const text = std.Io.Dir.cwd().readFileAlloc(b.graph.io, path, b.graph.arena, .limited(1 << 16)) catch
        @panic("eve: cannot read ../../build.zig.zon");
    const key = ".version = \"";
    const at = std.mem.indexOf(u8, text, key) orelse @panic("eve: no .version in ../../build.zig.zon");
    const from = at + key.len;
    const to = std.mem.indexOfScalarPos(u8, text, from, '"') orelse @panic("eve: bad .version in ../../build.zig.zon");
    return text[from..to];
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The arrows between the packages are their build.zig.zon files; the version of Eve goes to them as an option.
    const version = b.option([]const u8, "version", "the version of Eve (default: the root build.zig.zon)") orelse rootVersion(b);
    const args = .{ .target = target, .optimize = optimize, .version = version };
    const evecm_dep = b.dependency("evecm", args);
    const evecp_dep = b.dependency("evecp", args);
    const evevm_dep = b.dependency("evevm", args);

    const exe = b.addExecutable(.{
        .name = "eve",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/eve.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "evecm", .module = evecm_dep.module("evecm") },
                .{ .name = "evecp", .module = evecp_dep.module("evecp") },
                .{ .name = "evevm", .module = evevm_dep.module("evevm") },
            },
        }),
    });

    // A running program locks its .exe on Windows: stop the eve programs of bin/ before the copy (script/stop_eve.ps1, `eve --kill`).
    // Only the install waits; other systems skip the step.
    const stop = b.addSystemCommand(&.{ "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File" });
    stop.addFileArg(b.path("../../script/stop_eve.ps1"));
    stop.addArg("-Bin");
    stop.addFileArg(.{ .relative = .{ .base = .install_prefix, .sub_path = "bin" } });
    stop.has_side_effects = true;
    const install_exe = b.addInstallArtifact(exe, .{});
    if (@import("builtin").os.tag == .windows) install_exe.step.dependOn(&stop.step);
    b.getInstallStep().dependOn(&install_exe.step);

    // bin/evevm is the same file as bin/eve: at start it reads its own name (src/eve.zig) and as `evevm` starts the machine.
    const evevm_name = b.fmt("evevm{s}", .{target.result.exeFileExt()});
    const install_evevm = b.addInstallBinFile(exe.getEmittedBin(), evevm_name);
    install_evevm.step.dependOn(&install_exe.step);
    b.getInstallStep().dependOn(&install_evevm.step);

    // The standard library in Eve is found beside the program: `<prefix>/lib/*.eve` for `<prefix>/bin/eve.exe` (src/eve.zig,
    // `standardLibrary`). With the repository as prefix the copy lands on the same files (the prefix is not known while configuring).
    const install_lib = b.addInstallDirectory(.{
        .source_dir = b.path("../../lib"),
        .install_dir = .prefix,
        .install_subdir = "lib",
        .exclude_extensions = &.{"md"},
    });
    b.getInstallStep().dependOn(&install_lib.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    b.step("run", "Run eve").dependOn(&run_cmd.step);

    // `zig build doc` writes lib/doc from lib/ (the standard modules in Eve) and lib/sys/ (the signatures of the native modules)
    // with `eve --doc` (D-082, D-189).
    const doc_step = b.step("doc", "Generate lib/doc from the Eve sources in lib/ and lib/sys/");
    for ([_][]const u8{ "lib", "lib/sys" }) |folder| {
        const doc_cmd = b.addRunArtifact(exe);
        doc_cmd.addArgs(&.{ "--doc", folder, "lib/doc" });
        doc_cmd.setCwd(b.path("../.."));
        doc_step.dependOn(&doc_cmd.step);
    }

    // The parts of the install by name (run.sh builds the parts one by one); `zig build` with no step installs all.
    const eve_step = b.step("eve", "Install bin/eve.exe and lib/");
    eve_step.dependOn(&install_exe.step);
    eve_step.dependOn(&install_lib.step);
    b.step("evevm", "Install bin/evevm.exe (a copy of eve, the machine)").dependOn(&install_evevm.step);

    // The tests of the command itself and the test step of each package it imports.
    const test_step = b.step("test", "Run the unit tests of eve, evecm, evecp and evevm");
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = exe.root_module })).step);
    for ([_]*std.Build.Dependency{ evecm_dep, evecp_dep, evevm_dep }) |dep| {
        test_step.dependOn(&dep.builder.top_level_steps.get("test").?.step);
    }
}
