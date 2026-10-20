//! @eve-module profile
//! @decision D-201
//! A sampling profiler for the optimization work (design/design-bytecode.md, §4): with `EVE_PROFILE=1` a thread
//! looks at the instruction pointer of the main thread every millisecond, and at the end of the run the samples are
//! counted by function name and printed to the error output. Windows only (the symbols come from the `.pdb` file
//! beside `eve.exe`, through dbghelp.dll); on other systems it does nothing.
const std = @import("std");
const builtin = @import("builtin");

/// True when the profiler runs; the interpreter prints the report when a run ends.
pub var active: bool = false;

const win = builtin.os.tag == .windows;
const Handle = ?*anyopaque;

const k32 = if (win) struct {
    extern "kernel32" fn GetCurrentProcess() callconv(.winapi) Handle;
    extern "kernel32" fn GetCurrentThread() callconv(.winapi) Handle;
    extern "kernel32" fn DuplicateHandle(src_proc: Handle, src: Handle, dst_proc: Handle, dst: *Handle, access: u32, inherit: i32, options: u32) callconv(.winapi) i32;
    extern "kernel32" fn SuspendThread(h: Handle) callconv(.winapi) u32;
    extern "kernel32" fn ResumeThread(h: Handle) callconv(.winapi) u32;
    extern "kernel32" fn GetThreadContext(h: Handle, ctx: *anyopaque) callconv(.winapi) i32;
    extern "kernel32" fn GetModuleFileNameA(m: Handle, buf: [*]u8, size: u32) callconv(.winapi) u32;
    extern "kernel32" fn Sleep(ms: u32) callconv(.winapi) void;
    extern "kernel32" fn LoadLibraryA(name: [*:0]const u8) callconv(.winapi) Handle;
    extern "kernel32" fn GetProcAddress(m: Handle, name: [*:0]const u8) callconv(.winapi) ?*const anyopaque;
} else struct {};

// The 64-bit CONTEXT of Windows: 1232 bytes, 16-byte aligned; ContextFlags is at 0x30 and Rip at 0xF8.
const Context = extern struct { bytes: [1232]u8 align(16) };
const context_control: u32 = 0x100001;

const SymbolInfo = extern struct {
    size_of_struct: u32,
    type_index: u32,
    reserved: [2]u64,
    index: u32,
    size: u32,
    mod_base: u64,
    flags: u32,
    value: u64,
    address: u64,
    register: u32,
    scope: u32,
    tag: u32,
    name_len: u32,
    max_name_len: u32,
    name: [1]u8,
};

const max_samples = 1 << 20;
var samples: []u64 = &.{};
var count: usize = 0;
var stop_flag: std.atomic.Value(bool) = .init(false);
var target: Handle = null;
var thread: ?std.Thread = null;

/// Start sampling the calling thread.
pub fn start(gpa: std.mem.Allocator) void {
    if (!win) return;
    samples = gpa.alloc(u64, max_samples) catch return;
    // one millisecond between samples needs the 1 ms timer of Windows (the default step is about 15 ms)
    if (k32.LoadLibraryA("winmm.dll")) |winmm| {
        if (k32.GetProcAddress(winmm, "timeBeginPeriod")) |f| {
            const begin: *const fn (u32) callconv(.winapi) u32 = @ptrCast(f);
            _ = begin(1);
        }
    }
    const proc = k32.GetCurrentProcess();
    if (k32.DuplicateHandle(proc, k32.GetCurrentThread(), proc, &target, 0, 0, 2) == 0) return;
    thread = std.Thread.spawn(.{}, sampler, .{}) catch return;
    active = true;
}

fn sampler() void {
    var ctx: Context = undefined;
    while (!stop_flag.load(.acquire) and count < samples.len) {
        k32.Sleep(1);
        if (k32.SuspendThread(target) == 0xFFFFFFFF) continue;
        @memset(&ctx.bytes, 0);
        std.mem.writeInt(u32, ctx.bytes[0x30..][0..4], context_control, .little);
        if (k32.GetThreadContext(target, &ctx) != 0) {
            samples[count] = std.mem.readInt(u64, ctx.bytes[0xF8..][0..8], .little);
            count += 1;
        }
        _ = k32.ResumeThread(target);
    }
}

const Count = struct { name: []const u8, n: usize };

fn byCount(_: void, a: Count, b: Count) bool {
    return a.n > b.n;
}

/// Stop sampling and print the functions with the most samples (the top 30) to the error output.
pub fn report(gpa: std.mem.Allocator) void {
    if (!win or !active) return;
    active = false;
    stop_flag.store(true, .release);
    if (thread) |t| t.join();
    const dbg = k32.LoadLibraryA("dbghelp.dll");
    if (dbg == null) return;
    const SymSetOptions: *const fn (u32) callconv(.winapi) u32 = @ptrCast(k32.GetProcAddress(dbg, "SymSetOptions") orelse return);
    const SymInitialize: *const fn (Handle, ?[*:0]const u8, i32) callconv(.winapi) i32 = @ptrCast(k32.GetProcAddress(dbg, "SymInitialize") orelse return);
    const SymFromAddr: *const fn (Handle, u64, *u64, *SymbolInfo) callconv(.winapi) i32 = @ptrCast(k32.GetProcAddress(dbg, "SymFromAddr") orelse return);
    _ = SymSetOptions(0x2 | 0x4);
    const proc = k32.GetCurrentProcess();
    var path: [512:0]u8 = undefined;
    const len = k32.GetModuleFileNameA(null, &path, 500);
    var dir_end: usize = len;
    while (dir_end > 0 and path[dir_end - 1] != 0x5C and path[dir_end - 1] != '/') dir_end -= 1;
    path[if (dir_end > 0) dir_end - 1 else 0] = 0;
    if (SymInitialize(proc, &path, 1) == 0) return;

    var names: std.StringHashMapUnmanaged(usize) = .empty;
    var buf: [88 + 512]u8 align(8) = undefined;
    var cache: std.AutoHashMapUnmanaged(u64, []const u8) = .empty;
    for (samples[0..count]) |addr| {
        const name = cache.get(addr) orelse blk: {
            const info: *SymbolInfo = @ptrCast(&buf);
            info.* = std.mem.zeroes(SymbolInfo);
            info.size_of_struct = @sizeOf(SymbolInfo);
            info.max_name_len = 500;
            var disp: u64 = 0;
            const found = if (SymFromAddr(proc, addr, &disp, info) != 0)
                gpa.dupe(u8, std.mem.sliceTo(@as([*]const u8, @ptrCast(&info.name))[0..info.name_len], 0)) catch "?"
            else
                "(unknown)";
            cache.put(gpa, addr, found) catch {};
            break :blk found;
        };
        const slot = names.getOrPut(gpa, name) catch continue;
        if (!slot.found_existing) slot.value_ptr.* = 0;
        slot.value_ptr.* += 1;
    }
    var list: std.ArrayList(Count) = .empty;
    var it = names.iterator();
    while (it.next()) |e| list.append(gpa, .{ .name = e.key_ptr.*, .n = e.value_ptr.* }) catch {};
    std.mem.sort(Count, list.items, {}, byCount);
    std.debug.print("\nEVE_PROFILE: {d} samples (1 ms apart)\n", .{count});
    for (list.items[0..@min(30, list.items.len)]) |c| {
        std.debug.print("{d:6.1}%  {d:6}  {s}\n", .{ @as(f64, @floatFromInt(c.n)) * 100.0 / @as(f64, @floatFromInt(@max(count, 1))), c.n, c.name });
    }
}
