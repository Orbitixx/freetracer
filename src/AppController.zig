const std = @import("std");
const debug = @import("lib/util/debug.zig");

const FilePicker = @import("components/FilePicker/Index.zig");
const USBDevicesList = @import("components/USBDevicesList/Index.zig");

const Self = @This();

isoFilePathObtained: bool = false,

isoFilePickerState: *FilePicker.State,
usbDevicesListState: *USBDevicesList.State,

pub fn notifyISOFilePathObtained(self: *Self, path: []u8) void {
    self.isoFilePathObtained = true;
    debug.printf("\nAppController: confirmation of obtained ISO path: {s}", .{path});
}
