const std = @import("std");
const osd = @import("osdialog");

const Thread = std.Thread;

const debug = @import("../../lib/util/debug.zig");
const UI = @import("../../lib/ui/ui.zig");

const Component = @import("../Component.zig").Component;
const AppObserver = @import("../../observers/AppObserver.zig").AppObserver;
const Event = @import("../../observers/AppObserver.zig").Event;

pub const ComponentState = @import("./State.zig").FilePickerState;

const runFilePickerWorker = @import("Worker.zig").runFilePickerWorker;

pub fn FilePickerComponent() type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        button: UI.Button(),
        state: *ComponentState,
        appObserver: *const AppObserver,
        worker: ?std.Thread = null,
        currentPath: ?[:0]const u8 = null,

        pub fn getSelectedPath(self: Self) ?[]const u8 {
            return self.currentPath;
        }

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                // .state = &ComponentState{ .allocator = allocator },
            };
        }

        pub fn update(self: *Self) void {
            self.button.events();

            const isBtnClicked = self.button.mouseClick;

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

                self.notify(Event.ISO_FILE_SELECTED);
            }
        }

        pub fn draw(self: *Self) void {
            self.button.draw();
        }

        pub fn deinit(self: *Self) void {
            if (self.currentPath) |path| self.allocator.free(path);

            if (self.worker) |thread| {
                debug.print("FilePickerComponent.deinit(): Joining worker thread...\n");
                thread.join();
                self.worker = null;
            }

            self.state.deinit();
        }

        pub fn notify(self: Self, event: Event) void {
            self.appObserver.*.onNotify(event);
        }
    };
}

fn dispatchFilePickerAction(self: *FilePickerComponent()) void {
    self.state.mutex.lock();

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

    // self.worker = Thread.spawn(.{}, runFilePickerWorker, .{ self.allocator, self.state }) catch blk: {
    //     debug.print("\nERROR! FilePickerComponent: Failed to spawn worker.\n");
    //
    //     self.state.mutex.lock();
    //     // Reset state
    //     self.state.taskDone = false;
    //     self.state.taskRunning = false;
    //     self.state.taskError = error.FailedToSpawnFilePickerWorker;
    //
    //     self.state.mutex.unlock();
    //     break :blk null;
    // };

    runFilePickerWorker(self.allocator, self.state);
}

fn processFilePickerResult(self: *FilePickerComponent()) void {
    defer self.state.taskDone = false;
    defer self.state.taskRunning = false;

    // If error is not null
    if (self.state.taskError) |err| {
        debug.printf("Component: Worker finished with error: {any}\n", .{err});

        if (self.currentPath) |oldPath| self.allocator.free(oldPath);

        self.currentPath = null;
        return;
    }

    // If valid file path
    if (self.state.filePath) |newPath| {
        debug.printf("\nFilePickerComponent: worker successfully returned with path: {s}", .{newPath});

        if (self.currentPath) |oldPath| self.allocator.free(oldPath);

        self.currentPath = newPath;
        return;
    }

    // If file picker dialog cancelled without picking a file.
    debug.print("\nFilePickerComponent: worker successfully returned without a path (null/cancelled).");
    if (self.currentPath) |oldPath| self.allocator.free(oldPath);
    self.currentPath = null;
}
