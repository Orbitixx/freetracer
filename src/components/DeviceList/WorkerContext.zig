const std = @import("std");
const debug = @import("../../lib/util/debug.zig");

const MacOS = @import("../../modules/macos/MacOSTypes.zig");
const IOKit = @import("../../modules/macos/IOKit.zig");

const EventManager = @import("../../managers/EventManager.zig").EventManagerSingleton;

const DeviceListComponent = @import("./DeviceList.zig");
const DeviceListComponentWorker = @import("./DeviceList.zig").ComponentWorker;

pub fn workerRun(worker: *DeviceListComponentWorker, context: *anyopaque) void {
    debug.print("\nDevicesList Worker: starting devices discovery...");

    const deviceList = DeviceListComponent.asInstance(context);

    // worker.state.lock();
    //  worker.state.unlock();

    const devices = IOKit.getUSBStorageDevices(deviceList.allocator) catch blk: {
        debug.print("\nWARNING: Unable to capture USB devices. Please make sure a USB flash drive is plugged in.");
        break :blk std.ArrayList(MacOS.USBStorageDevice).init(deviceList.allocator);
    };

    debug.printf("\nDeviceList Worker: finished finding USB Storage devices, found: {d}", .{devices.items.len});

    var event = DeviceListComponent.Events.onDiscoverDevicesEnd.create(@ptrCast(@alignCast(worker.context.run_context)), &.{
        .devices = devices,
    });

    // Important to toggle flag for self-notify override
    event.flags.overrideNotifySelfOnSelfOrigin = true;

    EventManager.broadcast(event);
}

pub fn workerCallback(worker: *DeviceListComponentWorker, context: *anyopaque) void {
    _ = worker;
    _ = context;
}
