//! @eve-module shared: the files of evetx that have no screen library, exposed as one module for eveux (and later `evecl`)
//! @spec eveux/README.md#6-reuse-from-evetx
//! @decision D-193
//! eveux/build.zig makes a module from this file (`b.path("../evetx/src/shared.zig")`), so the module root is this folder and
//! the files below are imported as they are, with no copy. Only files with no dependency on vaxis belong here: when a file
//! needs a screen type it stays out. When the set is stable the files move to a folder `evecl/` and both programs import it.
pub const text = @import("text.zig");
pub const scan = @import("scan.zig");
pub const keywords = @import("keywords.zig");
pub const project = @import("project.zig");
pub const link = @import("link.zig");
pub const regex = @import("regex.zig");
pub const grid = @import("grid.zig");
pub const sqlstruct = @import("sqlstruct.zig");
pub const cache = @import("cache.zig");

test {
    _ = text;
    _ = scan;
    _ = grid;
    _ = regex;
}
