// const std = @import("std");
// const MacOS = @import("../../modules/macos/MacOSTypes.zig");
//
// const FlasherState = @This();
//
// mutex: std.Thread.Mutex = .{},
// allocator: std.mem.Allocator,
//
// taskRunning: bool = false,
// taskDone: bool = false,
// taskError: ?anyerror = null,
//
// device: ?MacOS.USBStorageDevice = null,
//
// pub fn deinit(self: FlasherState) void {
//     self.device.deinit();
// }
