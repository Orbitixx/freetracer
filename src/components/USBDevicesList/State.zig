const std = @import("std");

pub const USBDevicesListState = struct {
    mutex: std.Thread.Mutex = .{},
    allocator: std.mem.Allocator,

    taskRunning: bool = false,
    taskDone: bool = false,
    taskError: ?anyerror = null,

    filePath: ?[]const u8 = null,

    pub fn deinit(self: USBDevicesListState) void {
        if (self.filePath != null)
            self.allocator.free(self.filePath.?);
    }
};
