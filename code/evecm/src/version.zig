//! The version of Eve, written once in the root `build.zig.zon` and given to the code by the build
//! (a build option). Shown by `eve -v` and in the title of `eve -h`.

const options = @import("build_options");

/// Implementation version, the one of `build.zig.zon`.
pub const version: []const u8 = options.version;

/// Specification version this implementation targets (spec/README.md).
pub const spec_version = "0.1-draft";

/// The title line of the version and help output.
pub const title = "EVE - Version: " ++ version;
