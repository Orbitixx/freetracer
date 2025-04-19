const std = @import("std");
const osd = @import("osdialog");

const debug = @import("../../lib/util/debug.zig");

const MacOS = @import("../../modules/macos/MacOSTypes.zig");
const IOKit = @import("../../modules/macos/IOKit.zig");

const ComponentState = @import("State.zig");

pub fn runUSBDevicesListWorker(allocator: std.mem.Allocator, state: *ComponentState) void {
    debug.print("\nUSBDevicesList Worker: starting devices discovery...");

    // --- Perform the potentially blocking action ---
    // const usbStorageDevices = IOKit.getUSBStorageDevices(&allocator) catch blk: {
    //     debug.print("\nWARNING: Unable to capture USB devices. Please make sure a USB flash drive is plugged in.");
    //     break :blk std.ArrayList(MacOS.USBStorageDevice).init(allocator);
    // };
    //
    // defer {
    //     if (usbStorageDevices.items.len > 0) {
    //         for (usbStorageDevices.items) |device| {
    //             device.deinit();
    //         }
    //     }
    //
    //     usbStorageDevices.deinit();
    // }

    // --- Critical Section: Update Shared State ---
    state.mutex.lock();

    state.devices = IOKit.getUSBStorageDevices(allocator) catch blk: {
        debug.print("\nWARNING: Unable to capture USB devices. Please make sure a USB flash drive is plugged in.");
        break :blk std.ArrayList(MacOS.USBStorageDevice).init(allocator);
    };

    // Store results/errors
    state.taskError = null;

    // Update flags
    state.taskDone = true;
    state.taskRunning = false;

    state.mutex.unlock();

    debug.print("\nUSBDevcesList Worker: Updated shared state. Exiting.\n");
}
