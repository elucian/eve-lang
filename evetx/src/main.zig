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
    /// Posted by `watchQuit`: another program (`eve --kill`, the build) asks evetx to close itself.
    quit_request,
};

// Zig tip: `std_options` is a declaration of the root file that the standard library reads: `.logFn` replaces the function
// behind `std.log`. The default one writes to the standard error, which here is the same terminal as the screen, so a
// warning of the keyboard library (an unknown key) was written over the interface. This one keeps the text in a small buffer
// that the main loop empties into the message bar and the Stderr tab. It runs in any thread, so a spin lock guards the buffer.
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
    // the Windows console gives Ctrl+Space as a key code the keyboard library does not know (0x40): it is the shortcut
    // Ctrl+Space, so it is posted as that key, and not reported as a warning
    if (std.mem.indexOf(u8, line, "unknown wVirtualKeyCode: 0x40") != null) {
        if (g_loop) |l| l.postEvent(.{ .key_press = .{ .codepoint = ' ', .mods = .{ .ctrl = true } } }) catch {};
        return;
    }
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

// Zig tip: a function that runs in a second thread cannot share plain variables safely, so the flag that tells it
// to end is a `std.atomic.Value(bool)`: `load` and `store` are indivisible, and the order argument says how the other
// thread's writes become visible (`.acquire`/`.release`). `loop.postEvent` is made to be called from another thread:
// it puts an event in the queue that `nextEvent` waits on, so the blocked main loop wakes up.
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
    g_loop = &loop;
    defer g_loop = null;

    // the quit file of a previous run is stale: remove it, then start the thread that looks for a new one
    const exe_dir = try std.process.executableDirPathAlloc(io, gpa);
    defer gpa.free(exe_dir);
    const quit_path = try std.fmt.allocPrint(gpa, "{s}{c}evetx.quit", .{ exe_dir, std.fs.path.sep });
    defer gpa.free(quit_path);
    std.Io.Dir.cwd().deleteFile(io, quit_path) catch {};
    var stop_watch = std.atomic.Value(bool).init(false);
    // Zig tip: `std.Thread.spawn` starts a function in a new thread with the arguments in a tuple; `join` waits for it.
    // If the thread cannot start, evetx works as before (`catch null`) and only the polite quit is missing.
    const watcher: ?std.Thread = std.Thread.spawn(.{}, watchQuit, .{ io, &loop, quit_path, &stop_watch }) catch null;
    defer {
        stop_watch.store(true, .release);
        if (watcher) |t| t.join();
    }

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
