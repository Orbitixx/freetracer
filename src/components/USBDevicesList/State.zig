const std = @import("std");
const MacOS = @import("../../modules/macos/MacOSTypes.zig");

const USBDevicesListState = @This();

mutex: std.Thread.Mutex = .{},
allocator: std.mem.Allocator,

taskRunning: bool = false,
taskDone: bool = false,
taskError: ?anyerror = null,

devices: std.ArrayList(MacOS.USBStorageDevice),

pub fn deinit(self: USBDevicesListState) void {
    if (self.devices.items.len > 0) {
        for (self.devices.items) |device| {
            device.deinit();
        }
    }

    self.devices.deinit();
}
