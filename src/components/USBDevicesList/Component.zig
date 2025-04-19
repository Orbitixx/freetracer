const std = @import("std");

const debug = @import("../../lib/util/debug.zig");
const UI = @import("../../lib/ui/ui.zig");

const MacOS = @import("../../modules/macos/MacOSTypes.zig");
const IOKit = @import("../../modules/macos/IOKit.zig");

const Thread = std.Thread;
const Checkbox = @import("../../lib/ui/Checkbox.zig").Checkbox();

const AppObserverF = @import("../../observers/AppObserver.zig");
const AppObserver = AppObserverF.AppObserver;
const Event = AppObserverF.Event;

const Component = @import("../Component.zig");
const USBDevicesListComponent = @This();
const USBDevicesListState = @import("State.zig");
const USBDevicesListWorker = @import("Worker.zig");

allocator: std.mem.Allocator,
state: *USBDevicesListState,
appObserver: *const AppObserver,
worker: ?std.Thread = null,
componentActive: bool = false,
devicesFound: bool = false,

pub fn init(allocator: std.mem.Allocator, appObserver: *const AppObserver) USBDevicesListComponent {
    const state = allocator.create(USBDevicesListState) catch |err| {
        debug.printf("\nERROR: Unable to allocate memory for USBDevicesListState. {any}", .{err});
        std.debug.panic("\n{any}", .{err});
    };

    state.* = .{
        .allocator = allocator,
        .devices = std.ArrayList(MacOS.USBStorageDevice).init(allocator),
    };

    return .{
        .allocator = allocator,
        .appObserver = appObserver,
        .state = state,
    };
}

pub fn enable(self: *USBDevicesListComponent) void {
    self.componentActive = true;
}

pub fn update(self: *USBDevicesListComponent) void {
    if (self.componentActive) {
        debug.print("\nUSBDevicesListComponent: Dispatching component action...");
        if (!self.devicesFound) dispatchComponentAction(self);
        self.componentActive = false;
    }

    var workerFinished = false;

    self.state.mutex.lock();

    if (self.state.taskDone) {
        debug.print("\nUSBDevicesListComponent: task done signal receieved.");
        workerFinished = true;

        if (self.state.devices.items.len > 0) self.devicesFound = true;
        self.notify(.USB_DEVICES_DISCOVERED);
        self.componentActive = false;
    }

    self.state.mutex.unlock();

    if (workerFinished) {
        if (self.worker) |thread| {
            debug.print("\nUSBDevicesListComponent: joining worker thread...");
            thread.join();
            self.worker = null;
            debug.print("\nUSBDevicesListComponent: worker joined.");
        }

        self.state.mutex.lock();

        self.state.taskDone = false;
        self.state.taskRunning = false;

        self.state.mutex.unlock();

        debug.print("\nUSBDevicesListComponent: Finished finding USB devices.");
    }
}

pub fn draw(self: *USBDevicesListComponent) void {
    if (!self.devicesFound) return;

    self.state.mutex.lock();
    for (self.state.devices.items) |device| {
        const string = std.fmt.allocPrintZ(
            self.allocator,
            "{s} {d}GB",
            .{ device.deviceName, @divTrunc(device.size, 1_000_000_000) },
        ) catch blk: {
            debug.print("\nUSBDevicesListComponent: Error when constructing device string buffer.");
            break :blk "NULL";
        };
        var checkbox = Checkbox.init(string, 120, 150, 20);
        checkbox.update();
        checkbox.draw();
        self.allocator.free(string);
    }
    self.state.mutex.unlock();
}

pub fn deinit(self: *USBDevicesListComponent) void {
    if (self.worker) |thread| {
        debug.print("USBDevicesListComponent.deinit(): Joining worker thread...\n");
        thread.join();
        self.worker = null;
    }

    self.state.deinit();

    self.allocator.destroy(self.state);
}

pub fn notify(self: *USBDevicesListComponent, event: Event) void {
    self.appObserver.*.onNotify(event);
}

pub fn asComponent(self: *const USBDevicesListComponent) Component {
    return Component{
        .ptr = @constCast(self),
        .vtable = &VTable,
    };
}

fn dispatchComponentAction(self: *USBDevicesListComponent) void {
    self.state.mutex.lock();

    if (self.state.taskRunning) {
        debug.print("\nWARNING! USBDevicesListComponent: worker task already running!");
        self.state.mutex.unlock();
        return;
    }

    debug.print("\nUSBDevicesListComponent: Starting worker...");

    self.state.taskRunning = true;
    self.state.taskDone = false;
    self.state.taskError = null;

    // Clear out old devices
    if (self.state.devices.items.len > 0) {
        for (self.state.devices.items) |device| {
            device.deinit();
        }
        self.state.devices.clearAndFree();
    }

    self.state.mutex.unlock();

    self.worker = Thread.spawn(.{}, USBDevicesListWorker.run, .{ self.allocator, self.state }) catch blk: {
        debug.print("\nERROR! USBDevicesListComponent: Failed to spawn worker.\n");

        self.state.mutex.lock();
        // Reset state
        self.state.taskDone = false;
        self.state.taskRunning = false;
        self.state.taskError = error.FailedToSpawnUSBDevicesListWorker;

        self.state.mutex.unlock();
        break :blk null;
    };

    debug.print("\nUSBDevicesListComponent: Finished worker dispatch.");
}

// --- Component Interface Implementation -------------------------//
// Below methods are intended to be called internally within the struct only.
// Use public implementations above: enable, update, draw, notify, deinit...

const VTable = Component.VTable{
    .enable = rawEnable,
    .update = rawUpdate,
    .draw = rawDraw,
    .notify = rawNotify,
    .deinit = rawDeinit,
};

fn rawEnable(selfOpaque: *anyopaque) void {
    const self: *USBDevicesListComponent = @ptrCast(@alignCast(selfOpaque));
    return USBDevicesListComponent.enable(self);
}

fn rawUpdate(selfOpaque: *anyopaque) void {
    const self: *USBDevicesListComponent = @ptrCast(@alignCast(selfOpaque));
    return USBDevicesListComponent.update(self);
}

fn rawDraw(selfOpaque: *anyopaque) void {
    const self: *USBDevicesListComponent = @ptrCast(@alignCast(selfOpaque));
    return USBDevicesListComponent.draw(self);
}

fn rawNotify(selfOpaque: *anyopaque, event: Event) void {
    const self: *USBDevicesListComponent = @ptrCast(@alignCast(selfOpaque));
    return USBDevicesListComponent.notify(self, event);
}

fn rawDeinit(selfOpaque: *anyopaque) void {
    const self: *USBDevicesListComponent = @ptrCast(@alignCast(selfOpaque));
    return USBDevicesListComponent.deinit(self);
}

