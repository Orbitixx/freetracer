const std = @import("std");
const freetracer_lib = @import("freetracer-lib");
const Debug = freetracer_lib.Debug;

const EventManager = @import("../../managers/EventManager.zig").EventManagerSingleton;

const StorageDevice = freetracer_lib.types.StorageDevice;
const DeviceListComponent = @import("./DeviceList.zig");
const DeviceListComponentWorker = @import("./DeviceList.zig").ComponentWorker;

pub fn workerRun(worker: *DeviceListComponentWorker, context: *anyopaque) void {
    Debug.log(.DEBUG, "DevicesList Worker: starting devices discovery...", .{});

    const deviceList = DeviceListComponent.asInstance(context);

    // worker.state.lock();
    // worker.state.unlock();

    const devices = freetracer_lib.IOKit.getStorageDevices(deviceList.allocator) catch blk: {
        Debug.log(.WARNING, "Unable to capture USB devices. Please make sure a USB flash drive is plugged in.", .{});
        break :blk std.ArrayList(StorageDevice).empty;
    };

    Debug.log(.INFO, "DeviceList Worker: finished finding USB Storage devices, found: {d}", .{devices.items.len});

    var event = DeviceListComponent.Events.onDiscoverDevicesEnd.create(@ptrCast(@alignCast(worker.context.run_context)), &.{
        .devices = devices,
    });

    for (devices.items) |device| {
        Debug.log(
            .DEBUG,
            "\n\tbsdName:\t{s}\n\tdeviceName:\t{s}\n\tserviceId:\t{d}\n\tsize:\t{d}",
            .{ device.getBsdNameSlice(), device.getNameSlice(), device.serviceId, device.size },
        );
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
