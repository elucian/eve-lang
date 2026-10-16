//! evevm: the runtime of Eve (design-packages.md §3): the interpreter, the heap of the values, the
//! tasks, the natives of the standard library, the machine with its doors and the REPL. The databases are
//! `evedb`, reached through the `Data` interface. It imports `evecp` and `evecm`.

/// The interpreter: values, scopes and the walk over the syntax tree.
pub const interp = @import("interp.zig");

/// The debugger: `eve debug`, the commands run, halt, next, step, exit and trace (F-TLS-04).
pub const debugger = @import("debugger.zig");

/// The cooperative tasks of a job (D-144).
pub const task = @import("task.zig");

/// Scratch memory for the work of one statement.
pub const scratch = @import("scratch.zig");

/// Execution loop and the slot for external commands.
pub const vm = @import("vm.zig");

/// The natives of the standard library: streams, files, connections.
pub const dlib = @import("dlib.zig");

/// The machine, server side: the IPC and HTTP doors and the methods of the machine (F-NET-02, spec/library/machine.md).
pub const machine = @import("machine.zig");

pub const channel = @import("channel.zig");

/// The machine, client side: `-loc`, `-rem`, the words `status` and `stop` of the doors.
pub const client = @import("client.zig");

/// The machine as a process: `stop`, `evevm`, `-u`.
pub const daemon = @import("daemon.zig");

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
    _ = machine;
    _ = channel;
    _ = client;
    _ = daemon;
    _ = screen;
    _ = tui;
}
