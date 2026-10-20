//! @eve-module main: entry of eveux; one window, one frame function
//! @spec code/eveux/README.md
//! @feature F-TLS-19
//! @decision D-193
const std = @import("std");
const dvui = @import("dvui");
const App = @import("app.zig").App;
const shell = @import("view/shell.zig");

pub const dvui_app: dvui.App = .{
    .config = .{ .options = .{
        .size = .{ .w = 1280.0, .h = 800.0 },
        .min_size = .{ .w = 640.0, .h = 400.0 },
        .title = "eveux",
    } },
    .frameFn = frame,
};
pub const main = dvui.App.main;
pub const panic = dvui.App.panic;
pub const std_options: std.Options = .{ .logFn = dvui.App.logFn };

var app: App = undefined;

// @eve-impl one frame of the window: the shell draws from the state of `app`
fn frame() !dvui.App.Result {
    return shell.frame(&app);
}
