//! @eve-module interp.sysvars
//! @spec spec/semantics/variables.md#system-variables
//! @feature F-STR-07, F-STR-04
//! @tests test/level1/a97_eve_variables, test/level1/a116_eve_dir_asp
//! The variables `$EVE_DIR`, `$EVE_ASP` and the project variables `$EVE_HOME`, `$EVE_LIB`, `$EVE_LIB_PATH`, `$EVE_CORE_DB`, `$EVE_OUT`: read-only strings made when a run starts.
//! Part of the interpreter (interp.zig): called from vm.zig once `io` is known.
const std = @import("std");
const interp = @import("../interp.zig");
const Interp = interp.Interp;
const Signal = interp.Signal;
const evecm = @import("evecm");

// @eve-impl `$EVE_*`: the operating system variable of the same name wins, then the default of the table
// @spec spec/semantics/variables.md#system-variables
// @test a97_eve_variables
// @see code/evevm/src/db/orm.zig:coreDb (reads core_db from eve.cfg itself)
/// `script_dir` is the folder of the script that runs; it is the home of the project.
pub fn define(it: *Interp, script_dir: []const u8) Signal!void {
    const io = it.io orelse return;
    const cwd = std.process.currentPathAlloc(io, it.t) catch return;
    const home = std.fs.path.resolve(it.t, &.{ cwd, script_dir }) catch return;
    try set(it, "EVE_HOME", home);
    const exe_dir = std.process.executableDirPathAlloc(io, it.t) catch "";
    try set(it, "EVE_DIR", exe_dir);
    try set(it, "EVE_ASP", "asp");
    try set(it, "EVE_LIB", "lib");
    try set(it, "EVE_LIB_PATH", "");
    try set(it, "EVE_OUT", "out");
    try set(it, "EVE_CORE_DB", coreDbName(it, home));
    // `$cores`: the hardware cores, at most 16, read only; `$max_parallel`: the tasks of a parallel group that run at a time, a program may change it (multitasking.md#where-a-group-is-allowed)
    const cores = std.Thread.getCpuCount() catch 1;
    try it.define("$cores", .{ .int = @intCast(@min(@max(cores, 1), 16)) }, true);
    try it.define("$max_parallel", .{ .int = 8 }, false);
    // `$optimization`: the level of the run, read only (D-227)
    try it.define("$optimization", .{ .int = evecm.optimization.level }, true);
}

fn set(it: *Interp, name: []const u8, default: []const u8) Signal!void {
    const z = try it.t.dupeSentinel(u8, name, 0);
    const text = if (std.c.getenv(z.ptr)) |got| std.mem.span(got) else default;
    const key = try std.fmt.allocPrint(it.t, "${s}", .{name});
    try it.define(key, try it.newStr(text), true);
}

/// The `core_db` line of `eve.cfg` in the home folder, `db/local.db` when there is none.
fn coreDbName(it: *Interp, home: []const u8) []const u8 {
    const io = it.io orelse return "db/local.db";
    const path = std.fs.path.join(it.t, &.{ home, "eve.cfg" }) catch return "db/local.db";
    const cfg = std.Io.Dir.cwd().readFileAlloc(io, path, it.t, .limited(1 << 20)) catch return "db/local.db";
    var lines = std.mem.splitScalar(u8, cfg, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (!std.mem.startsWith(u8, line, "core_db")) continue;
        const eq_at = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const rest = std.mem.trim(u8, line[eq_at + 1 ..], " \t");
        if (rest.len >= 2 and rest[0] == '"') {
            if (std.mem.indexOfScalarPos(u8, rest, 1, '"')) |end| return rest[1..end];
        }
    }
    return "db/local.db";
}
