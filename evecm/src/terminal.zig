//! Raw keyboard mode for the REPL prompt, so that the Tab key reaches the program.
//!
//! In the normal ("cooked") mode the operating system collects a whole line, echoes it and gives it
//! to the program only after Enter, so a Tab can never be seen. In raw mode the program receives
//! every key at once and must echo and edit the line itself (see line.zig).
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

// Zig tip: `switch` is an expression and `builtin.os.tag` is known at compile time, so this picks a
// type while compiling. The branch that is not chosen is never analysed, so the Windows code
// below does not even have to compile on Linux, and the other way round. This is how one
// source tree serves several operating systems without `#ifdef`.
/// Handle to restore the keyboard mode: `enter` it, `leave` it when done.
pub const Terminal = switch (builtin.os.tag) {
    .windows => WindowsTerminal,
    else => PosixTerminal,
};

pub const EnterError = error{NotATerminal};

/// The size of the window in characters.
pub const Size = struct { rows: usize, cols: usize };

const WindowsTerminal = struct {
    // Zig tip: `extern` declares a function written in another language, here Windows' own
    // `kernel32.dll`, which Zig can call directly with no wrapper and no C header. The signature
    // is typed by hand: `callconv(.winapi)` is the calling convention Windows uses, `*u32` is a
    // pointer through which the function writes its result, and the `i32` result is a C `BOOL`
    // (0 means failure).
    extern "kernel32" fn GetConsoleMode(handle: std.os.windows.HANDLE, mode: *u32) callconv(.winapi) i32;
    extern "kernel32" fn SetConsoleMode(handle: std.os.windows.HANDLE, mode: u32) callconv(.winapi) i32;
    extern "kernel32" fn GetConsoleScreenBufferInfo(handle: std.os.windows.HANDLE, info: *BufferInfo) callconv(.winapi) i32;
    extern "kernel32" fn GetConsoleOutputCP() callconv(.winapi) u32;
    extern "kernel32" fn SetConsoleOutputCP(code_page: u32) callconv(.winapi) i32;

    const enable_processed_input = 0x0001; // Ctrl-C ends the program
    const enable_line_input = 0x0002; // the system collects a whole line
    const enable_echo_input = 0x0004; // the system shows the typed characters

    // Zig tip: `extern struct` has the memory layout of a C struct, field after field, which is what the Windows call
    // writes into. `i16` is a signed 16-bit number, the type of a console coordinate.
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

    // Zig tip: `~` inverts all bits and `&` keeps the bits set in both, so `mode & ~(a | b)`
    // clears the flags a and b. The constants above are untyped `comptime_int`, so the compiler
    // gives them the type `u32` needed here. `.{ .saved_mode = mode }` builds the struct that the
    // return type `EnterError!Terminal` names. `orelse` is not used here: `== 0` tests the BOOL.
    pub fn enter() EnterError!WindowsTerminal {
        const handle = Io.File.stdin().handle;
        var mode: u32 = 0;
        if (GetConsoleMode(handle, &mode) == 0) return error.NotATerminal;
        const raw = (mode & ~@as(u32, enable_processed_input | enable_line_input | enable_echo_input)) | enable_virtual_terminal_input;
        if (SetConsoleMode(handle, raw) == 0) return error.NotATerminal;
        var self: WindowsTerminal = .{ .saved_mode = mode };
        // Zig tip: the same two calls prepare the output: UTF-8 so that the box and block characters of the banner
        // are drawn, and the ANSI colors. A failure is not an error: the banner is plainer on a console that refuses.
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

    // Zig tip: `termios` is the terminal settings record of Linux and macOS. `var raw = saved;`
    // copies the struct (assignment copies, it never aliases), so the original stays intact for
    // `leave`. `lflag` is a packed struct of booleans, one per flag: `raw.lflag.ECHO = false`
    // switches one flag off. `catch return error.NotATerminal` converts any error of the call
    // into ours. This branch is compiled only on non-Windows targets.
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

    // Zig tip: `ioctl` asks the terminal driver a question; `TIOCGWINSZ` is "get the window size" and fills a
    // `winsize` record. This branch is not compiled on Windows, and it has not been run there.
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
