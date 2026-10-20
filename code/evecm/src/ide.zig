//! @eve-module ide: what the two editors of Eve share (evetx on the terminal, eveux in a window), with no screen library
//! @spec code/eveux/README.md#6-reuse-from-evetx
//! @decision D-193
//! @tests code/evecm/src/ide.zig (zig build test)
//! The files below import `std` and each other only. A file that needs a screen type (vaxis, dvui) stays in its program.
//! Two ways to reach them: inside `evecm` as `@import("evecm").ide` (the root build), and as the module `ide` that
//! `code/evetx/build.zig` and `code/eveux/build.zig` make from this file (`b.path("../evecm/src/ide.zig")`), which needs no build
//! options. Both are the same files, never a copy.
pub const text = @import("ide/text.zig");
pub const scan = @import("ide/scan.zig");
pub const keywords = @import("ide/keywords.zig");
pub const project = @import("ide/project.zig");
pub const link = @import("ide/link.zig");
pub const regex = @import("ide/regex.zig");
pub const grid = @import("ide/grid.zig");
pub const sqlstruct = @import("ide/sqlstruct.zig");
pub const cache = @import("ide/cache.zig");

test {
    _ = text;
    _ = scan;
    _ = grid;
    _ = regex;
    _ = sqlstruct;
}
