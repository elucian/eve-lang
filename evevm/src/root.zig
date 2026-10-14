//! evevm: the runtime of Eve (design-packages.md §3): the interpreter, the heap of the values, the
//! tasks, the natives of the standard library, the machine with its doors, the REPL and the core
//! database (SQLite, for now; it moves to `evedb`). It imports `evecp` and `evecm`.

/// The interpreter: values, scopes and the walk over the syntax tree.
pub const interp = @import("interp.zig");

/// The cooperative tasks of a job (D-144).
pub const task = @import("task.zig");

/// Scratch memory for the work of one statement.
pub const scratch = @import("scratch.zig");

/// Execution loop and the slot for external commands.
pub const vm = @import("vm.zig");

/// The natives of the standard library: streams, files, connections.
pub const dlib = @import("dlib.zig");

/// Records and tables: the object-relational layer.
pub const orm = @import("orm.zig");

/// SQLite, the core database of Eve (level 5).
pub const sqlite = @import("sqlite.zig");

/// The machine as a server and its client (F-NET-02, spec/library/machine.md).
pub const server = @import("server.zig");

/// The look of the REPL: banner and help table.
pub const screen = @import("screen.zig");

/// The full-screen REPL: scrollback, command line and status bar.
pub const tui = @import("tui.zig");

/// The texts of the help pages.
pub const helptext = @import("helptext.zig");

test {
    _ = interp;
    _ = task;
    _ = scratch;
    _ = vm;
    _ = dlib;
    _ = orm;
    _ = sqlite;
    _ = server;
    _ = screen;
    _ = tui;
}
