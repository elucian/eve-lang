//! The configuration of a machine: the keys of `eve.cfg`, the folder of the IPC sockets, the exit
//! codes of the machine, and the comment rule that `eve.cfg` and the command files share
//! (spec/library/machine.md). Part of evecm: the runtime, the database layer and the user
//! interface all read the same file in the same way.
const std = @import("std");
const Io = std.Io;

/// Exit codes of the machine (spec/library/machine.md): nobody answers / a machine already runs.
pub const exit_unavailable = 69;

pub const exit_running = 75;

pub const exit_usage = 64;

/// The folder of the IPC sockets: `$XDG_RUNTIME_DIR`, else `$TMPDIR`, else `%TEMP%`, else `/tmp`.
pub var runtime_dir: []const u8 = "/tmp";

/// The keys of `eve.cfg` that the machine reads.
pub const Config = struct {
    domain: []const u8 = "localhost",
    ipc_port: u16 = 4042,
    http_port: u16 = 8042,
    http_host: []const u8 = "localhost",
    web: []const u8 = "web",
    remote: ?[]const u8 = null,
    /// Width of the help table and texts in characters (`eve_width`; 100 when it is not set).
    eve_width: usize = 100,
};

/// Read the configuration file; a missing file gives the defaults.
pub fn loadConfig(io: Io, gpa: std.mem.Allocator, path: []const u8) Config {
    return readConfig(io, gpa, path) orelse .{};
}

/// Read the configuration file; null when it is missing.
pub fn readConfig(io: Io, gpa: std.mem.Allocator, path: []const u8) ?Config {
    const bytes = Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1 << 20)) catch return null;
    return parseConfig(bytes);
}

/// Read `key = value` lines; unknown keys (such as `database "x" = …` or `core_db`) are ignored.
pub fn parseConfig(bytes: []const u8) Config {
    var cfg: Config = .{};
    var lines = std.mem.tokenizeScalar(u8, bytes, '\n');
    while (lines.next()) |raw| {
        const line = clean(raw);
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq], " \t");
        const value = std.mem.trim(u8, std.mem.trim(u8, line[eq + 1 ..], " \t"), "\"");
        if (std.mem.eql(u8, key, "domain")) cfg.domain = value;
        if (std.mem.eql(u8, key, "ipc_port")) cfg.ipc_port = std.fmt.parseInt(u16, value, 10) catch cfg.ipc_port;
        if (std.mem.eql(u8, key, "http_port")) cfg.http_port = std.fmt.parseInt(u16, value, 10) catch cfg.http_port;
        if (std.mem.eql(u8, key, "http_host")) cfg.http_host = value;
        if (std.mem.eql(u8, key, "web")) cfg.web = value;
        if (std.mem.eql(u8, key, "remote")) cfg.remote = value;
        if (std.mem.eql(u8, key, "eve_width")) cfg.eve_width = std.fmt.parseInt(usize, value, 10) catch cfg.eve_width;
    }
    return cfg;
}

/// The path of the socket that identifies the machine: `<runtime>/eve-<domain>-<ipc_port>.sock`.
pub fn socketPath(gpa: std.mem.Allocator, cfg: Config) ![]u8 {
    return std.fmt.allocPrint(gpa, "{s}/eve-{s}-{d}.sock", .{ runtime_dir, cfg.domain, cfg.ipc_port });
}

/// The command of one slot line: comments and blanks removed. A line whose first character is
/// `#`, and everything from `**` to the end of a line, is a comment (the same marks as Eve).
pub fn clean(line: []const u8) []const u8 {
    const code = line[0 .. std.mem.indexOf(u8, line, "**") orelse line.len];
    const t = std.mem.trim(u8, code, " \t\r");
    return if (t.len > 0 and t[0] == '#') "" else t;
}
