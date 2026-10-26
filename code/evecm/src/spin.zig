//! @eve-module spin
//! @feature F-MTK-02, F-LNG-18
//! @decision D-144
//! A spin lock for very short critical sections shared by the tasks of a run: the buffer of a channel, an `Atomic` variable.
const std = @import("std");

pub const SpinLock = struct {
    held: std.atomic.Value(bool) = .init(false),

    pub fn lock(l: *SpinLock) void {
        var spins: u32 = 0;
        while (l.held.cmpxchgWeak(false, true, .acquire, .monotonic) != null) {
            spins += 1;
            if (spins < 64) std.atomic.spinLoopHint() else std.Thread.yield() catch {};
        }
    }

    pub fn unlock(l: *SpinLock) void {
        l.held.store(false, .release);
    }
};

test "a spin lock excludes" {
    var l: SpinLock = .{};
    l.lock();
    try std.testing.expect(l.held.load(.monotonic));
    l.unlock();
    try std.testing.expect(!l.held.load(.monotonic));
}
