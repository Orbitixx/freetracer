const std = @import("std");
const Debug = @import("freetracer-lib").Debug;

const System = @import("../../lib/sys/system.zig");
const USBStorageDevice = System.USBStorageDevice;

const MacOS = @import("../../modules/macos/MacOSTypes.zig");
const IOKit = @import("../../modules/macos/IOKit.zig");

const EventManager = @import("../../managers/EventManager.zig").EventManagerSingleton;

const DeviceListComponent = @import("./DeviceList.zig");
const DeviceListComponentWorker = @import("./DeviceList.zig").ComponentWorker;

pub fn workerRun(worker: *DeviceListComponentWorker, context: *anyopaque) void {
    Debug.log(.DEBUG, "DevicesList Worker: starting devices discovery...", .{});

    const deviceList = DeviceListComponent.asInstance(context);

    // worker.state.lock();
    // worker.state.unlock();

    const devices = IOKit.getUSBStorageDevices(deviceList.allocator) catch blk: {
        Debug.log(.WARNING, "Unable to capture USB devices. Please make sure a USB flash drive is plugged in.", .{});
        break :blk std.ArrayList(USBStorageDevice).init(deviceList.allocator);
    };

    Debug.log(.INFO, "DeviceList Worker: finished finding USB Storage devices, found: {d}", .{devices.items.len});

    var event = DeviceListComponent.Events.onDiscoverDevicesEnd.create(@ptrCast(@alignCast(worker.context.run_context)), &.{
        .devices = devices,
    });

    for (devices.items) |device| {
        Debug.log(.INFO, "{any}", .{device});
    }

    // Important to toggle flag for self-notify override since we're targeting self (DeviceList)
    event.flags.overrideNotifySelfOnSelfOrigin = true;

    _ = EventManager.broadcast(event);
}

pub fn workerCallback(worker: *DeviceListComponentWorker, context: *anyopaque) void {
    _ = worker;
    _ = context;
    Debug.log(.DEBUG, "DeviceList: Worker - onWorkerFinished callback executed.", .{});
}
