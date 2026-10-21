//! @eve-module app: the state of the window: the project, the open tabs, the machine, the settings
//! @spec design/components/eveux/README.md#7-the-code
//! @feature F-TLS-19
//! @decision D-193
//! Plain data and small operations; nothing here draws. The frame function reads `App` and the views draw from it.
//! Threads: the UI thread owns `App`. A worker thread never touches it: it sends a message through a queue (see `queue.zig`,
//! to write) and the UI thread applies it at the start of the next frame.
const std = @import("std");
const ide = @import("ide");
const kind = @import("preview/kind.zig");

pub const Tab = struct {
    path: []const u8,
    file_kind: kind.Kind,
    viewer: kind.Viewer,
    /// For a text tab: the buffer with its undo history (the one of evetx).
    buffer: ?ide.text.Buffer = null,
    /// A Markdown or HTML tab: Source, Split or Preview.
    mode: enum { source, split, preview } = .split,
    dirty: bool = false,

    pub fn title(self: *const Tab) []const u8 {
        return std.fs.path.basename(self.path);
    }
};

pub const Machine = struct { name: []const u8, connected: bool = false };

pub const App = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8 = "",
    tree: ide.project.Tree,
    tabs: std.ArrayList(Tab) = .empty,
    active: usize = 0,
    machines: std.ArrayList(Machine) = .empty,
    machine: usize = 0,
    /// The child `eve --stdio`; null until the first command needs it.
    link: ?*ide.link.Link = null,

    pub fn init(gpa: std.mem.Allocator, io: std.Io) App {
        return .{ .gpa = gpa, .io = io, .tree = ide.project.Tree.init(gpa) };
    }

    pub fn deinit(self: *App) void {
        self.tree.deinit();
        for (self.tabs.items) |*t| if (t.buffer) |*b| b.deinit();
        self.tabs.deinit(self.gpa);
        self.machines.deinit(self.gpa);
        if (self.link) |l| l.destroy();
    }

    // @eve-fn App.open
    /// Open a file in a tab (or switch to the tab that has it); the viewer comes from the kind of the file.
    pub fn open(self: *App, path: []const u8) !void {
        for (self.tabs.items, 0..) |t, i| if (std.mem.eql(u8, t.path, path)) {
            self.active = i;
            return;
        };
        const k = kind.kindOf(path);
        try self.tabs.append(self.gpa, .{ .path = path, .file_kind = k, .viewer = kind.viewerOf(k) });
        self.active = self.tabs.items.len - 1;
    }
};

test "opening a file twice keeps one tab" {
    var app = App.init(std.testing.allocator, undefined);
    defer app.deinit();
    try app.open("doc/README.md");
    try app.open("web/index.html");
    try app.open("doc/README.md");
    try std.testing.expectEqual(@as(usize, 2), app.tabs.items.len);
    try std.testing.expectEqual(@as(usize, 0), app.active);
    try std.testing.expectEqual(kind.Viewer.markdown, app.tabs.items[0].viewer);
}
