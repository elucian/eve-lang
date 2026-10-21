//! evecp: the compiler front end as a program. Build from code/evecp/: `zig build -p ../..` installs `bin/evecp.exe`.
//! `./run.sh build evecp` does the same from the root. The version is the one of the root `build.zig.zon` (D-167).
//! The same code is also a module of the root build (`eve cp ...` runs it inside `eve`): the root build.zig.zon lists this package.
const std = @import("std");

// @eve-impl read `.version` of the root build.zig.zon when the build is configured (the file is outside this package)
fn rootVersion(b: *std.Build) []const u8 {
    const path = b.root.joinString(b.graph.arena, "../../build.zig.zon") catch @panic("OOM");
    const text = std.Io.Dir.cwd().readFileAlloc(b.graph.io, path, b.graph.arena, .limited(1 << 16)) catch
        @panic("evecp: cannot read ../../build.zig.zon");
    const key = ".version = \"";
    const at = std.mem.indexOf(u8, text, key) orelse @panic("evecp: no .version in ../../build.zig.zon");
    const from = at + key.len;
    const to = std.mem.indexOfScalarPos(u8, text, from, '"') orelse @panic("evecp: bad .version in ../../build.zig.zon");
    return text[from..to];
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // evecm is a package of its own; the version of Eve goes to it as an option
    const version = b.option([]const u8, "version", "the version of Eve (default: the root build.zig.zon)") orelse rootVersion(b);
    const evecm = b.dependency("evecm", .{ .target = target, .optimize = optimize, .version = version }).module("evecm");
    const evecp = b.addModule("evecp", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "evecm", .module = evecm }},
    });
    const exe = b.addExecutable(.{
        .name = "evecp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "evecm", .module = evecm },
                .{ .name = "evecp", .module = evecp },
            },
        }),
    });

    // A running program locks its .exe on Windows: stop the programs of bin/ before the copy (script/stop_eve.ps1).
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
    run_cmd.addPassthruArgs();
    b.step("run", "Run evecp").dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run the unit tests of evecp");
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = evecp })).step);
}
