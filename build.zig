//! Build Eve: one executable, `eve`, made of modules (design/design-packages.md).
//!
//!   zig build            -> zig-out/bin/eve.exe
//!   zig build -p .       -> bin/eve.exe (the official location, D-007)
//!   zig build run -- <args>
//!   zig build test       -> the unit tests of every module
//!   zig build doc        -> lib/doc from the Eve sources of lib/
//!
//! The arrows between the modules are the `.imports` below; a module that is not listed cannot be
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

    // Zig tip: `b.addOptions()` makes a small module of constants that the build decides. The
    // module `build_options` is read by code/evecm/src/version.zig.
    const options = b.addOptions();
    options.addOption([]const u8, "version", zon.version);

    // Zig tip: `b.createModule` makes a module (a root file and the modules it may import) that is
    // not an executable by itself. `target` and `optimize` are given to every module, so they are
    // all compiled for the same system and in the same mode.
    const evecm = b.createModule(.{
        .root_source_file = b.path("code/evecm/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "build_options", .module = options.createModule() }},
    });
    const evecp = b.createModule(.{
        .root_source_file = b.path("code/evecp/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "evecm", .module = evecm }},
    });
    // @eve-impl the module `ewp_protocol`: the wire protocol shared with the DuckDB server (D-199 5)
    // @see drivers/duckdb/build.zig (the server makes the same module from the same files)
    const ewp_protocol = b.createModule(.{
        .root_source_file = b.path("drivers/duckdb/protocol/protocol.zig"),
        .target = target,
        .optimize = optimize,
    });
    // The runtime and, inside it, the database layer (SQLite is linked below; D-198).
    const evevm = b.createModule(.{
        .root_source_file = b.path("code/evevm/src/root.zig"),
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
    evevm.addImport("sqlite_c", sqlite_c.createModule());
    evevm.linkLibrary(sqlite_lib);

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

    // One test program per module: each runs the tests of its own files.
    const test_step = b.step("test", "Run unit tests");
    for ([_]*std.Build.Module{ evecm, evecp, evevm, ewp_protocol, exe.root_module }) |m| {
        const t = b.addTest(.{ .root_module = m });
        test_step.dependOn(&b.addRunArtifact(t).step);
    }
}
