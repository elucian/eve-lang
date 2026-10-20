//! Scratch memory: a bump allocator for the short-lived buffers of the interpreter (the cells of an
//! index, the text of a value being printed, the arguments of a call). The interpreter takes a
//! `mark` when a statement starts and goes back to it when the statement ends: everything the
//! statement allocated is freed at once, in the order of a stack. Values of the script never live
//! here; they live in the heap (heap.zig).
const std = @import("std");
const Alignment = std.mem.Alignment;

/// A stack-like bump allocator with marks.
pub const Scratch = struct {
    parent: std.mem.Allocator,
    chunks: std.ArrayList([]u8) = .empty,
    /// The chunk being filled and how many of its bytes are taken.
    cur: usize = 0,
    used: usize = 0,
    /// The most bytes ever taken at once: what the memory statistics report.
    peak: usize = 0,

    const first_size = 64 * 1024;

    /// A position in the scratch memory.
    pub const Mark = struct { cur: usize, used: usize };

    /// The current position: give it to `release` to free what comes after.
    pub fn mark(s: *const Scratch) Mark {
        return .{ .cur = s.cur, .used = s.used };
    }

    /// Free everything allocated since `m`.
    pub fn release(s: *Scratch, m: Mark) void {
        s.cur = m.cur;
        s.used = m.used;
    }

    /// Give all the memory back.
    pub fn deinit(s: *Scratch) void {
        for (s.chunks.items) |c| s.parent.free(c);
        s.chunks.deinit(s.parent);
        s.* = .{ .parent = s.parent };
    }

    /// This scratch as a `std.mem.Allocator`.
    pub fn allocator(s: *Scratch) std.mem.Allocator {
        return .{ .ptr = s, .vtable = &vtable };
    }

    const vtable: std.mem.Allocator.VTable = .{ .alloc = alloc, .resize = resize, .remap = remap, .free = free };

    fn alloc(ctx: *anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const s: *Scratch = @ptrCast(@alignCast(ctx));
        while (true) {
            if (s.cur < s.chunks.items.len) {
                const c = s.chunks.items[s.cur];
                const base = @intFromPtr(c.ptr);
                const start = alignment.forward(base + s.used) - base;
                if (start + len <= c.len) {
                    s.used = start + len;
                    s.notePeak();
                    return c.ptr + start;
                }
                // the chunk is full: try the next one, which a previous statement may have made
                if (s.cur + 1 < s.chunks.items.len) {
                    s.cur += 1;
                    s.used = 0;
                    continue;
                }
            }
            const last = if (s.chunks.items.len > 0) s.chunks.items[s.chunks.items.len - 1].len else 0;
            const size = @max(first_size, last * 2, len + alignment.toByteUnits());
            const c = s.parent.alloc(u8, size) catch return null;
            s.chunks.append(s.parent, c) catch {
                s.parent.free(c);
                return null;
            };
            s.cur = s.chunks.items.len - 1;
            s.used = 0;
        }
    }

    /// Remember the largest amount of scratch memory in use.
    fn notePeak(s: *Scratch) void {
        var total: usize = s.used;
        for (s.chunks.items[0..s.cur]) |c| total += c.len;
        if (total > s.peak) s.peak = total;
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
        _ = alignment;
        _ = ret_addr;
        const s: *Scratch = @ptrCast(@alignCast(ctx));
        if (s.cur >= s.chunks.items.len) return new_len <= memory.len;
        const c = s.chunks.items[s.cur];
        const end = @intFromPtr(memory.ptr) + memory.len;
        const is_last = end == @intFromPtr(c.ptr) + s.used;
        if (!is_last) return new_len <= memory.len;
        const start = @intFromPtr(memory.ptr) - @intFromPtr(c.ptr);
        if (start + new_len > c.len) return false;
        s.used = start + new_len;
        s.notePeak();
        return true;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        return if (resize(ctx, memory, alignment, new_len, ret_addr)) memory.ptr else null;
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void {
        _ = alignment;
        _ = ret_addr;
        const s: *Scratch = @ptrCast(@alignCast(ctx));
        if (s.cur >= s.chunks.items.len) return;
        const c = s.chunks.items[s.cur];
        if (@intFromPtr(memory.ptr) + memory.len == @intFromPtr(c.ptr) + s.used) {
            s.used = @intFromPtr(memory.ptr) - @intFromPtr(c.ptr);
        }
    }
};

test "scratch memory is freed back to a mark" {
    var s: Scratch = .{ .parent = std.testing.allocator };
    defer s.deinit();
    const a = s.allocator();
    const m = s.mark();
    var list: std.ArrayList(u32) = .empty;
    for (0..10_000) |i| try list.append(a, @intCast(i));
    try std.testing.expectEqual(@as(u32, 9_999), list.items[9_999]);
    const big = s.used + s.cur;
    s.release(m);
    try std.testing.expect(s.used + s.cur < big);
    const again = try a.alloc(u8, 100);
    try std.testing.expectEqual(@as(usize, 100), again.len);
}
