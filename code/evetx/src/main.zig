//! `evetx`: the Eve text user interface, a project IDE in the terminal (README.md, design/).
//!
//!   evetx [project-folder]     (without a folder no project is open)
const std = @import("std");
const vaxis = @import("vaxis");

const app_mod = @import("app.zig");
const view = @import("view.zig");

const Event = union(enum) {
    key_press: vaxis.Key,
    mouse: vaxis.Mouse,
    winsize: vaxis.Winsize,
    paste_start,
    paste_end,
    focus_in,
    focus_out,
    /// Posted by `watchQuit`: another program (`eve --kill`, the build) asks evetx to close itself.
    quit_request,
};

pub const std_options: std.Options = .{ .logFn = logToApp };

var log_lock = std.atomic.Value(bool).init(false);
var log_buf: [2048]u8 = undefined;
var log_len: usize = 0;
/// The loop of events, for the function that turns a warning into a key (set once the loop exists).
var g_loop: ?*vaxis.Loop(Event) = null;

fn logToApp(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    // only warnings and errors matter to the person; the debug and info lines of the libraries are dropped
    if (level == .debug or level == .info) return;
    var tmp: [512]u8 = undefined;
    const line = std.fmt.bufPrint(&tmp, "{s}({s}): " ++ format, .{ level.asText(), @tagName(scope) } ++ args) catch return;
    // the Windows console gives Ctrl+Space as a key code the keyboard library does not know (0x40): it has no shortcut, so it
    // is dropped and not reported as a warning
    if (std.mem.indexOf(u8, line, "unknown wVirtualKeyCode: 0x40") != null) return;
    while (log_lock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) std.atomic.spinLoopHint();
    defer log_lock.store(false, .release);
    if (log_len + line.len + 1 > log_buf.len) return;
    @memcpy(log_buf[log_len..][0..line.len], line);
    log_len += line.len;
    log_buf[log_len] = '\n';
    log_len += 1;
}

/// The text logged since the last call (copied; the caller frees it), or null.
fn takeLog(gpa: std.mem.Allocator) ?[]u8 {
    while (log_lock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) std.atomic.spinLoopHint();
    defer log_lock.store(false, .release);
    if (log_len == 0) return null;
    const copy = gpa.dupe(u8, log_buf[0..log_len]) catch return null;
    log_len = 0;
    return copy;
}

/// The thread that looks, five times a second, for the file `evetx.quit` beside the program. When it appears
/// the file is removed and the loop gets `quit_request`: evetx ends the normal way, and the terminal is given back
/// (a program killed from outside leaves the mouse mode and the alternate screen on, and the shell shows numbers).
fn watchQuit(io: std.Io, loop: *vaxis.Loop(Event), path: []const u8, stop: *std.atomic.Value(bool)) void {
    while (!stop.load(.acquire)) {
        io.sleep(.fromMilliseconds(200), .awake) catch return;
        if (std.Io.Dir.cwd().statFile(io, path, .{})) |_| {
            std.Io.Dir.cwd().deleteFile(io, path) catch {};
            loop.postEvent(.quit_request) catch {};
            return;
        } else |_| {}
    }
}

pub const panic = vaxis.panic_handler;

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
    defer {
        writer.writeAll("\x1b[2J\x1b[3J\x1b[H") catch {};
        writer.flush() catch {};
    }

    var vx = try vaxis.init(io, gpa, init.environ_map, .{});
    defer vx.deinit(gpa, tty.writer());

    var loop: vaxis.Loop(Event) = .init(io, &tty, &vx);
    try loop.start();
    defer loop.stop();
    g_loop = &loop;
    defer g_loop = null;

    // the quit file of a previous run is stale: remove it, then start the thread that looks for a new one
    const exe_dir = try std.process.executableDirPathAlloc(io, gpa);
    defer gpa.free(exe_dir);
    const quit_path = try std.fmt.allocPrint(gpa, "{s}{c}evetx.quit", .{ exe_dir, std.fs.path.sep });
    defer gpa.free(quit_path);
    std.Io.Dir.cwd().deleteFile(io, quit_path) catch {};
    var stop_watch = std.atomic.Value(bool).init(false);
    const watcher: ?std.Thread = std.Thread.spawn(.{}, watchQuit, .{ io, &loop, quit_path, &stop_watch }) catch null;
    defer {
        stop_watch.store(true, .release);
        if (watcher) |t| t.join();
    }

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
        const maybe: ?Event = if (app.needsTick()) blk: {
            const ev = try loop.tryEvent();
            if (ev == null) try io.sleep(.fromMilliseconds(100), .awake);
            break :blk ev;
        } else try loop.nextEvent();
        if (maybe) |event| switch (event) {
            .key_press => |key| app.onKey(key) catch |err| app.setMessage("error: {s}", .{@errorName(err)}),
            .mouse => |m| app.onMouse(vx.translateMouse(m)) catch |err| app.setMessage("error: {s}", .{@errorName(err)}),
            .winsize => |ws| try vx.resize(gpa, tty.writer(), ws),
            .quit_request => app.quit = true,
            .paste_start => app.pasteStart(),
            .paste_end => app.pasteEnd() catch |err| app.setMessage("error: {s}", .{@errorName(err)}),
            else => {},
        };
        app.tick() catch |err| app.setMessage("error: {s}", .{@errorName(err)});
        // what the libraries logged goes to the message bar and the Stderr tab, never to the screen
        if (takeLog(gpa)) |logged| {
            defer gpa.free(logged);
            app.logError(logged);
        }
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
