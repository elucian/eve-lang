//! The version of Eve, written once in the root `build.zig.zon` and given to the code by the build
//! (a build option). Shown by `eve -v` and in the title of `eve -h`.

// Zig tip: `@import("build_options")` is a module that `build.zig` fills with `b.addOptions()`:
// values that the build decides (here the version of build.zig.zon) become ordinary constants of
// the program, known when it is compiled, with no file read at run time.
const options = @import("build_options");

/// Implementation version, the one of `build.zig.zon`.
pub const version: []const u8 = options.version;

/// Specification version this implementation targets (spec/README.md).
pub const spec_version = "0.1-draft";

// Zig tip: `++` joins arrays and strings at compile time, so `title` is one constant string
// in the program, with no memory allocated while running. `**` repeats ("ab" ** 3).
/// The title line of the version and help output.
pub const title = "EVE - Version: " ++ version;
