const std = @import("std");
const osd = @import("osdialog");

const debug = @import("../../lib/util/debug.zig");
const UI = @import("../../lib/ui/ui.zig");
const Checkbox = @import("../../lib/ui/Checkbox.zig").Checkbox();

const MacOS = @import("../../modules/macos/MacOSTypes.zig");
const IOKit = @import("../../modules/macos/IOKit.zig");

const Thread = std.Thread;

const AppObserver = @import("../../observers/AppObserver.zig").AppObserver;

const USBDevicesListState = @import("State.zig").USBDevicesListState;

const runUSBDevicesListWorker = @import("Worker.zig").runUSBDevicesListWorker;

pub fn USBDevicesListComponent() type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        state: *USBDevicesListState,
        appObserver: *const AppObserver,
        worker: ?std.Thread = null,
        componentActive: bool = false,
        devicesFound: bool = false,

        pub fn enable(self: *Self) void {
            self.componentActive = true;
        }

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .state = USBDevicesListState{
                    .allocator = allocator,
                    .devices = std.ArrayList(MacOS.USBStorageDevice).init(allocator),
                },
            };
        }

        pub fn update(self: *Self) void {
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

        pub fn draw(self: *Self) void {
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

        pub fn deinit(self: *Self) void {
            if (self.worker) |thread| {
                debug.print("USBDevicesListComponent.deinit(): Joining worker thread...\n");
                // TODO: Signal the worker to cancel here, if possible
                thread.join();
                self.worker = null;
            }

            self.state.deinit();
        }
    };
}

fn dispatchComponentAction(self: *USBDevicesListComponent()) void {
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

    self.worker = Thread.spawn(.{}, runUSBDevicesListWorker, .{ self.allocator, self.state }) catch blk: {
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
