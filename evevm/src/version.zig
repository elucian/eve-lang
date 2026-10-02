//! Version of the machine, hard-coded at build time. Shown by `eve -v` and in the title of `eve -h`.

/// Implementation version; keep in step with `build.zig.zon`.
pub const version = "0.0.1";

/// Specification version this implementation targets (spec/README.md).
pub const spec_version = "0.1-draft";

// Zig tip: `++` joins arrays and strings at compile time, so `title` is one constant string
// in the program, with no memory allocated while running. `**` repeats ("ab" ** 3).
/// The title line of the version and help output.
pub const title = "EVE - Version: " ++ version;
