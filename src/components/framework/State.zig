const std = @import("std");

pub fn ComponentState(comptime T: type) type {
    return struct {
        const Self = @This();
        data: T,
        mutex: std.Thread.Mutex = .{},

        pub fn init(data: T) Self {
            return .{ .data = data };
        }

        pub fn lock(self: *Self) void {
            self.mutex.lock();
        }

        pub fn unlock(self: *Self) void {
            self.mutex.unlock();
        }

        pub fn getData(self: *Self) *T {
            return &self.data;
        }

        pub fn getDataLocked(self: *Self) *T {
            self.lock();
            return &self.data;
        }

        pub fn withLock(self: *Self, comptime func: fn (*T) void) void {
            self.lock();
            defer self.unlock();
            func(&self.data);
        }
    };
}
