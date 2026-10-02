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

const WindowsTerminal = struct {
    // Zig tip: `extern` declares a function written in another language, here Windows' own
    // `kernel32.dll`, which Zig can call directly with no wrapper and no C header. The signature
    // is typed by hand: `callconv(.winapi)` is the calling convention Windows uses, `*u32` is a
    // pointer through which the function writes its result, and the `i32` result is a C `BOOL`
    // (0 means failure).
    extern "kernel32" fn GetConsoleMode(handle: std.os.windows.HANDLE, mode: *u32) callconv(.winapi) i32;
    extern "kernel32" fn SetConsoleMode(handle: std.os.windows.HANDLE, mode: u32) callconv(.winapi) i32;

    const enable_processed_input = 0x0001; // Ctrl-C ends the program
    const enable_line_input = 0x0002; // the system collects a whole line
    const enable_echo_input = 0x0004; // the system shows the typed characters

    saved_mode: u32,

    // Zig tip: `~` inverts all bits and `&` keeps the bits set in both, so `mode & ~(a | b)`
    // clears the flags a and b. The constants above are untyped `comptime_int`, so the compiler
    // gives them the type `u32` needed here. `.{ .saved_mode = mode }` builds the struct that the
    // return type `EnterError!Terminal` names. `orelse` is not used here: `== 0` tests the BOOL.
    pub fn enter() EnterError!WindowsTerminal {
        const handle = Io.File.stdin().handle;
        var mode: u32 = 0;
        if (GetConsoleMode(handle, &mode) == 0) return error.NotATerminal;
        const raw = mode & ~@as(u32, enable_processed_input | enable_line_input | enable_echo_input);
        if (SetConsoleMode(handle, raw) == 0) return error.NotATerminal;
        return .{ .saved_mode = mode };
    }

    pub fn leave(self: WindowsTerminal) void {
        _ = SetConsoleMode(Io.File.stdin().handle, self.saved_mode);
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

    pub fn leave(self: PosixTerminal) void {
        std.posix.tcsetattr(Io.File.stdin().handle, .FLUSH, self.saved) catch {};
    }
};
