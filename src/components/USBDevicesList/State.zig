const std = @import("std");
const MacOS = @import("../../modules/macos/MacOSTypes.zig");

pub const USBDevicesListState = struct {
    mutex: std.Thread.Mutex = .{},
    allocator: std.mem.Allocator,

    taskRunning: bool = false,
    taskDone: bool = false,
    taskError: ?anyerror = null,

    devices: std.ArrayList(MacOS.USBStorageDevice),

    pub fn deinit(self: USBDevicesListState) void {
        for (self.devices.items) |device| {
            device.deinit();
        }

        self.devices.deinit();
    }
};
