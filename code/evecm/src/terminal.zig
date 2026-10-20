//! Raw keyboard mode for the REPL prompt, so that the Tab key reaches the program.
//!
//! In the normal ("cooked") mode the operating system collects a whole line, echoes it and gives it
//! to the program only after Enter, so a Tab can never be seen. In raw mode the program receives
//! every key at once and must echo and edit the line itself (see line.zig).
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

/// Handle to restore the keyboard mode: `enter` it, `leave` it when done.
pub const Terminal = switch (builtin.os.tag) {
    .windows => WindowsTerminal,
    else => PosixTerminal,
};

pub const EnterError = error{NotATerminal};

/// The size of the window in characters.
pub const Size = struct { rows: usize, cols: usize };

const WindowsTerminal = struct {
    extern "kernel32" fn GetConsoleMode(handle: std.os.windows.HANDLE, mode: *u32) callconv(.winapi) i32;
    extern "kernel32" fn SetConsoleMode(handle: std.os.windows.HANDLE, mode: u32) callconv(.winapi) i32;
    extern "kernel32" fn GetConsoleScreenBufferInfo(handle: std.os.windows.HANDLE, info: *BufferInfo) callconv(.winapi) i32;
    extern "kernel32" fn GetConsoleOutputCP() callconv(.winapi) u32;
    extern "kernel32" fn SetConsoleOutputCP(code_page: u32) callconv(.winapi) i32;

    const enable_processed_input = 0x0001; // Ctrl-C ends the program
    const enable_line_input = 0x0002; // the system collects a whole line
    const enable_echo_input = 0x0004; // the system shows the typed characters

    const Coord = extern struct { x: i16, y: i16 };
    const SmallRect = extern struct { left: i16, top: i16, right: i16, bottom: i16 };
    const BufferInfo = extern struct { size: Coord, cursor: Coord, attributes: u16, window: SmallRect, max_size: Coord };

    const enable_virtual_terminal_input = 0x0200; // arrows and Page Up/Down arrive as ESC [ ... sequences
    const enable_virtual_terminal_processing = 0x0004; // the output understands colors (ANSI escape codes)
    const utf8_code_page = 65001;

    saved_mode: u32,
    /// The output mode and code page to restore; the mode is null when the output is not a console.
    saved_out_mode: ?u32 = null,
    saved_code_page: u32 = 0,

    pub fn enter() EnterError!WindowsTerminal {
        const handle = Io.File.stdin().handle;
        var mode: u32 = 0;
        if (GetConsoleMode(handle, &mode) == 0) return error.NotATerminal;
        const raw = (mode & ~@as(u32, enable_processed_input | enable_line_input | enable_echo_input)) | enable_virtual_terminal_input;
        if (SetConsoleMode(handle, raw) == 0) return error.NotATerminal;
        var self: WindowsTerminal = .{ .saved_mode = mode };
        const out = Io.File.stdout().handle;
        var out_mode: u32 = 0;
        if (GetConsoleMode(out, &out_mode) != 0) {
            self.saved_code_page = GetConsoleOutputCP();
            _ = SetConsoleOutputCP(utf8_code_page);
            if (SetConsoleMode(out, out_mode | enable_virtual_terminal_processing) != 0) self.saved_out_mode = out_mode;
        }
        return self;
    }

    /// The visible window (not the buffer behind it): rows and columns, or null when the output is not a console.
    pub fn size() ?Size {
        var info: BufferInfo = undefined;
        if (GetConsoleScreenBufferInfo(Io.File.stdout().handle, &info) == 0) return null;
        const rows = info.window.bottom - info.window.top + 1;
        const cols = info.window.right - info.window.left + 1;
        if (rows <= 0 or cols <= 0) return null;
        return .{ .rows = @intCast(rows), .cols = @intCast(cols) };
    }

    pub fn leave(self: WindowsTerminal) void {
        _ = SetConsoleMode(Io.File.stdin().handle, self.saved_mode);
        if (self.saved_out_mode) |m| {
            _ = SetConsoleMode(Io.File.stdout().handle, m);
            _ = SetConsoleOutputCP(self.saved_code_page);
        }
    }
};

const PosixTerminal = struct {
    saved: std.posix.termios,

    pub fn enter() EnterError!PosixTerminal {
        const fd = Io.File.stdin().handle;
        const saved = std.posix.tcgetattr(fd) catch return error.NotATerminal;
        var raw = saved;
        raw.lflag.ICANON = false; // no line collecting
        raw.lflag.ECHO = false; // the program echoes
        raw.lflag.ISIG = false; // Ctrl-C arrives as the byte 3
        raw.cc[@intFromEnum(std.posix.V.MIN)] = 1; // a read returns after one byte
        raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;
        std.posix.tcsetattr(fd, .FLUSH, raw) catch return error.NotATerminal;
        return .{ .saved = saved };
    }

    pub fn size() ?Size {
        var ws: std.posix.winsize = undefined;
        const rc = std.posix.system.ioctl(Io.File.stdout().handle, std.posix.T.IOCGWINSZ, @intFromPtr(&ws));
        if (std.posix.errno(rc) != .SUCCESS or ws.row == 0 or ws.col == 0) return null;
        return .{ .rows = ws.row, .cols = ws.col };
    }

    pub fn leave(self: PosixTerminal) void {
        std.posix.tcsetattr(Io.File.stdin().handle, .FLUSH, self.saved) catch {};
    }
};
