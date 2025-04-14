const std = @import("std");
const osd = @import("osdialog");

const debug = @import("../../lib/util/debug.zig");
const UI = @import("../../lib/ui/ui.zig");

const MacOS = @import("../../modules/macos/MacOSTypes.zig");
const IOKit = @import("../../modules/macos/IOKit.zig");

const Thread = std.Thread;

const AppController = @import("../../AppController.zig");

const USBDevicesListState = @import("State.zig").USBDevicesListState;

const runUSBDevicesListWorker = @import("Worker.zig").runUSBDevicesListWorker;

pub fn USBDevicesListComponent() type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        state: *USBDevicesListState,
        appController: ?*AppController = null,
        worker: ?std.Thread = null,
        componentActive: bool = false,

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
                dispatchComponentAction(self);
                self.componentActive = false;
            }

            var workerFinished = false;

            self.state.mutex.lock();

            if (self.state.taskDone) {
                debug.print("\nUSBDevicesListComponent: task done signal receieved.");
                workerFinished = true;
            }

            self.state.mutex.unlock();

            if (workerFinished) {
                debug.print("\nGot to worker check");
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
            _ = self;
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

fn processFilePickerResult(self: *USBDevicesListComponent()) void {
    if (self.state.taskError) |err| {
        debug.printf("Component: Worker finished with error: {any}\n", .{err});

        if (self.currentPath) |oldPath| self.allocator.free(oldPath);

        self.currentPath = null;
    } else {
        if (self.state.filePath) |newPath| {
            debug.printf("\nFilePickerComponent: worker successfully returned with path: {s}", .{newPath});

            if (self.currentPath) |oldPath| self.allocator.free(oldPath);

            self.currentPath = self.allocator.dupe(u8, newPath) catch blk: {
                debug.print("\nERROR! FilePickerComponent: Unable to allocate heap memory to duplicate current path.");
                break :blk null;
            };

            // self.allocator.free(newPath);
        } else {
            debug.print("\nFilePickerComponent: worker successfully return without a path (null/cancelled).");

            if (self.currentPath) |oldPath| self.allocator.free(oldPath);

            self.currentPath = null;
        }

        self.state.filePath = null;
    }

    self.state.taskDone = false;
    self.state.taskRunning = false;
}
