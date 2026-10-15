//! `evetx`: the Eve text user interface, a project IDE in the terminal (README.md, design/).
//!
//!   evetx [project-folder]     (without a folder no project is open)
const std = @import("std");
const vaxis = @import("vaxis");

const app_mod = @import("app.zig");
const view = @import("view.zig");

// Zig tip: a `union(enum)` is a tagged union: a value that is exactly one of its fields, with the
// name of the field stored beside it. libvaxis looks at the field names of this type and sends
// the events that have a field here (`key_press`, `mouse`, `winsize`, ...) and no others.
const Event = union(enum) {
    key_press: vaxis.Key,
    mouse: vaxis.Mouse,
    winsize: vaxis.Winsize,
    paste_start,
    paste_end,
    focus_in,
    focus_out,
};

// Zig tip: a file-level `pub const panic` replaces the handler that runs when the program panics
// (an index out of range, an overflow in a safe build). libvaxis gives one that first puts the
// terminal back in its normal mode, so a crash does not leave the shell in raw mode.
pub const panic = vaxis.panic_handler;

// Zig tip: in Zig 0.16 `main` may take a `std.process.Init`, filled by the runtime: `init.io` is
// the handle for input and output, `init.gpa` a general purpose allocator, and `init.minimal.args`
// the command line. `!void` means `main` may return an error, which ends the program with its name.
pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    // no folder on the command line: no project is open and the tree is empty (File > Open project)
    const root: []const u8 = if (args.len > 1) args[1] else "";

    const app = app_mod.App.create(gpa, io, init.environ_map, root) catch |err| {
        std.debug.print("evetx: cannot open the project folder '{s}': {s}\n", .{ root, @errorName(err) });
        return err;
    };
    defer app.destroy();

    var tty_buffer: [4096]u8 = undefined;
    var tty = try vaxis.Tty.init(io, &tty_buffer);
    defer tty.deinit();
    const writer = tty.writer();

    var vx = try vaxis.init(io, gpa, init.environ_map, .{});
    defer vx.deinit(gpa, tty.writer());

    var loop: vaxis.Loop(Event) = .init(io, &tty, &vx);
    try loop.start();
    defer loop.stop();

    // Zig tip: `defer` runs when the scope ends, in the opposite order of the `defer` lines. So the
    // terminal is given back (loop.stop, tty.deinit) even when the program ends with an error.
    try vx.enterAltScreen(writer);
    try vx.setMouseMode(writer, true);
    // a paste made by the terminal arrives between two markers, so it can be inserted as one piece
    try vx.setBracketedPaste(writer, true);
    try writer.flush();
    try vx.queryTerminal(tty.writer(), .fromSeconds(1));

    // where the user is (project, files, cursors) goes to the cache when the program ends
    defer app.saveSession() catch {};

    // the title of the terminal window follows the project; it is sent again only when it changes
    var title_buf: [256]u8 = undefined;
    var last_buf: [256]u8 = undefined;
    var last_title: []const u8 = "";

    while (!app.quit) {
        // Zig tip: while a command waits in the prompt the loop must wake up by itself, so it asks for an
        // event without blocking (`tryEvent`), sleeps a tenth of a second when there is none, and
        // lets `app.tick` start the command when its time is over. Without a waiting command the
        // loop blocks in `nextEvent` and uses no time.
        const maybe: ?Event = if (app.needsTick()) blk: {
            const ev = try loop.tryEvent();
            if (ev == null) try io.sleep(.fromMilliseconds(100), .awake);
            break :blk ev;
        } else try loop.nextEvent();
        if (maybe) |event| switch (event) {
            .key_press => |key| app.onKey(key) catch |err| app.setMessage("error: {s}", .{@errorName(err)}),
            .mouse => |m| app.onMouse(vx.translateMouse(m)) catch |err| app.setMessage("error: {s}", .{@errorName(err)}),
            .winsize => |ws| try vx.resize(gpa, tty.writer(), ws),
            .paste_start => app.pasteStart(),
            .paste_end => app.pasteEnd() catch |err| app.setMessage("error: {s}", .{@errorName(err)}),
            else => {},
        };
        app.tick() catch |err| app.setMessage("error: {s}", .{@errorName(err)});
        // Zig tip: `takeSystemClip` hands over the text of the last copy; the terminal puts it in the
        // clipboard of the system (OSC 52), and the copy is freed here.
        if (app.takeSystemClip()) |clip| {
            defer gpa.free(clip);
            vx.copyToSystemClipboard(writer, clip, gpa) catch {};
        }
        const title = app.windowTitle(&title_buf);
        if (!std.mem.eql(u8, title, last_title)) {
            vx.setTitle(writer, title) catch {};
            @memcpy(last_buf[0..title.len], title);
            last_title = last_buf[0..title.len];
        }
        vx.setMouseShape(app.pointer);
        const win = vx.window();
        win.clear();
        try view.draw(app, win);
        try vx.render(writer);
        try writer.flush();
    }
}
