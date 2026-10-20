//! @eve-module shell: the layout of the window: menu bar, explorer, tabs, editor area, side bar, bottom panel, status bar
//! @spec code/eveux/README.md#3-the-screen
//! @feature F-TLS-19
//! @decision D-193
//! DRAFT, not compiled yet (dvui cannot be fetched on the author's Windows without Developer Mode, README section 12). The
//! widgets to use are those of dvui v0.5.0 (src/widgets): PanedWidget for the resizable panes, DockingWidget for the side
//! bar and bottom panel, TabsWidget for the tabs, TreeWidget for the explorer, MenuWidget and FloatingMenuWidget for menus,
//! GridWidget for the data grids, TextEntryWidget as the base of the editor, FloatingWindowWidget for dialogs.
//! One function for each part keeps a frame readable; each takes `*App` and draws from it.
const dvui = @import("dvui");
const App = @import("../app.zig").App;

// @eve-impl one frame of the whole window; returns .close when the user quits
pub fn frame(app: *App) !dvui.App.Result {
    _ = app;
    var root = dvui.box(@src(), .{}, .{ .expand = .both });
    defer root.deinit();
    // TODO(P2): menuBar(app); toolBar(app); panes: explorer | tabs + editor area | side bar; bottom panel; statusBar(app)
    dvui.labelNoFmt(@src(), "eveux: the Eve native workbench", .{}, .{});
    return .ok;
}
