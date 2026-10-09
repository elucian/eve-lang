//! Scratch memory: a bump allocator for the short-lived buffers of the interpreter (the cells of an
//! index, the text of a value being printed, the arguments of a call). The interpreter takes a
//! `mark` when a statement starts and goes back to it when the statement ends: everything the
//! statement allocated is freed at once, in the order of a stack. Values of the script never live
//! here; they live in the heap (heap.zig).
const std = @import("std");
const Alignment = std.mem.Alignment;

// Zig tip: a struct that hands out memory keeps it in "chunks" taken from a parent allocator. A
// chunk is a slice of bytes; `used` says how much of the last chunk is taken. Asking for more than
// a chunk holds starts a new, bigger chunk. Nothing is given back to the parent until `deinit`, so
// a loop that runs a million statements reuses the same few chunks.
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

    // Zig tip: a mark is a small value struct: going back to it is two assignments. Marks must be
    // released in the reverse order they were taken, like the statements that take them.
    /// A position in the scratch memory.
    pub const Mark = struct { cur: usize, used: usize };

    // Zig tip: `mark` relies on the same Zig feature as `Mark` above: see the tip there.
    /// The current position: give it to `release` to free what comes after.
    pub fn mark(s: *const Scratch) Mark {
        return .{ .cur = s.cur, .used = s.used };
    }

    // Zig tip: releasing does not free chunks: the next allocations reuse them. Only the position moves.
    /// Free everything allocated since `m`.
    pub fn release(s: *Scratch, m: Mark) void {
        s.cur = m.cur;
        s.used = m.used;
    }

    // Zig tip: `deinit` gives every chunk back to the parent allocator; `defer s.deinit()` pairs it
    // with the creation of the scratch.
    /// Give all the memory back.
    pub fn deinit(s: *Scratch) void {
        for (s.chunks.items) |c| s.parent.free(c);
        s.chunks.deinit(s.parent);
        s.* = .{ .parent = s.parent };
    }

    // Zig tip: `std.mem.Allocator` is an interface: a pointer to the object (`ptr`, of type `*anyopaque`,
    // "a pointer to anything") and a table of functions (`vtable`). Code that takes an `Allocator` does
    // not know it talks to a Scratch: it only calls `alloc`, `resize`, `remap` and `free` through the table.
    /// This scratch as a `std.mem.Allocator`.
    pub fn allocator(s: *Scratch) std.mem.Allocator {
        return .{ .ptr = s, .vtable = &vtable };
    }

    const vtable: std.mem.Allocator.VTable = .{ .alloc = alloc, .resize = resize, .remap = remap, .free = free };

    // Zig tip: `alignment.forward(address)` rounds an address up to the next multiple of the alignment;
    // `@intFromPtr` gives the address of a pointer as a number, `@ptrFromInt` the reverse. The function
    // returns `?[*]u8`: a many-item pointer, or null when the parent allocator has no memory left.
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

    // Zig tip: `notePeak` relies on the same Zig feature as `mark` above: see the tip there.
    /// Remember the largest amount of scratch memory in use.
    fn notePeak(s: *Scratch) void {
        var total: usize = s.used;
        for (s.chunks.items[0..s.cur]) |c| total += c.len;
        if (total > s.peak) s.peak = total;
    }

    // Zig tip: a buffer can grow in place only when it is the last thing allocated in the current chunk
    // (its end is the end of the used part) and the chunk has room. Otherwise `resize` answers false and
    // the caller (an `ArrayList`) allocates a new buffer and copies.
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

    // Zig tip: `remap` may move the memory; answering null tells the caller to allocate and copy itself.
    fn remap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        return if (resize(ctx, memory, alignment, new_len, ret_addr)) memory.ptr else null;
    }

    // Zig tip: freeing the last allocation gives its bytes back at once; any other free does nothing
    // until the statement releases its mark.
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

// Zig tip: the test allocator checks that every byte taken from it is given back: `deinit` must free
// the chunks, or the test fails with a leak report.
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
