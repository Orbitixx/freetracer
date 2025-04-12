const std = @import("std");
const osd = @import("osdialog");

const debug = @import("../../lib/util/debug.zig");
const UI = @import("../../lib/ui/ui.zig");

const Thread = std.Thread;

const USBDevicesListState = @import("State.zig").USBDevicesListState;

const runUSBDevicesListWorker = @import("Worker.zig").runUSBDevicesListWorker;

pub fn USBDevicesListComponent() type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        state: USBDevicesListState,
        worker: ?std.Thread = null,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .state = USBDevicesListState{ .allocator = allocator },
            };
        }

        pub fn update(self: *Self) void {
            if (self.button == null) return;

            self.button.?.events();

            const isBtnClicked = self.button.?.mouseClick;

            if (isBtnClicked) dispatchFilePickerAction(self);

            var workerFinished = false;

            self.state.mutex.lock();

            if (self.state.taskDone) {
                debug.print("\nFilePickerComponent: processing file picker result.");
                processFilePickerResult(self);
                debug.print("\nFilePickerComponent: finished processing file picker result.");

                workerFinished = true;
            }

            self.state.mutex.unlock();

            if (workerFinished) {
                if (self.worker) |thread| {
                    debug.print("\nFilePickerComponent: joining worker thread...");
                    thread.join();
                    self.worker = null;
                    debug.print("\nFilePickerComponent: worker joined.");
                }
            }
        }

        pub fn draw(self: *Self) void {
            if (self.button == null) return;
            self.button.?.draw();
        }

        pub fn deinit(self: *Self) void {
            if (self.currentPath) |path| self.allocator.free(path);

            if (self.worker) |thread| {
                debug.print("FilePickerComponent.deinit(): Joining worker thread...\n");
                // TODO: Signal the worker to cancel here, if possible
                thread.join();
                self.worker = null;
            }

            self.state.deinit();
        }
    };
}

fn dispatchFilePickerAction(self: *USBDevicesListComponent()) void {
    self.state.mutex.lock();
    // Schedule Mutex unclock whenever function exits
    // defer self.state.mutex.unlock();

    if (self.state.taskRunning) {
        debug.print("\nWARNING! FilePickerComponent: worker task already running!");
        self.state.mutex.unlock();
        return;
    }

    debug.print("\nFilePickerComponent: Button clicked, starting worker...");

    self.state.taskRunning = true;
    self.state.taskDone = false;
    self.state.taskError = null;

    if (self.state.filePath) |oldPath| {
        self.allocator.free(oldPath);
        self.state.filePath = null;
    }

    self.state.mutex.unlock();

    self.worker = Thread.spawn(.{}, runUSBDevicesListWorker(.{ self.allocator, &self.state })) catch blk: {
        debug.print("\nERROR! FilePickerComponent: Failed to spawn worker.\n");

        self.state.mutex.lock();
        // Reset state
        self.state.taskDone = false;
        self.state.taskRunning = false;
        self.state.taskError = error.FailedToSpawnFilePickerWorker;

        self.state.mutex.unlock();
        break :blk null;
    };
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
