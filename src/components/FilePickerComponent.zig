const std = @import("std");
const debug = @import("../lib/util/debug.zig");
const UI = @import("../lib/ui/ui.zig");

const AppObserverF = @import("../observers/AppObserver.zig");
const AppObserver = AppObserverF.AppObserver;
const Event = AppObserverF.Event;

const Component = @import("ComponentNew.zig");

const FilePickerComponent = @This();
const FilePickerState = @import("FilePicker/State.zig").FilePickerState;

const runFilePickerWorker = @import("FilePicker/Worker.zig").runFilePickerWorker;

allocator: std.mem.Allocator,
appObserver: *const AppObserver,
state: *FilePickerState,
button: UI.Button(),
worker: ?std.Thread = null,
currentPath: ?[:0]const u8 = null,

const VTable = Component.VTable{
    .draw = rawDraw,
    .update = rawUpdate,
    .notify = rawNotify,
    .deinit = rawDeinit,
};

pub fn init(allocator: std.mem.Allocator, appObserver: *const AppObserver) FilePickerComponent {
    var state: FilePickerState = .{ .allocator = allocator };

    return .{
        .allocator = allocator,
        .appObserver = appObserver,
        .state = &state,
        .button = UI.Button().init("Select ISO...", 150, 150, 14, .white, .red),
    };
}

pub fn draw(self: *FilePickerComponent) void {
    self.button.draw();
}

pub fn update(self: *FilePickerComponent) void {
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

pub fn notify(self: FilePickerComponent, event: Event) void {
    self.appObserver.*.onNotify(event);
}

pub fn deinit(self: *FilePickerComponent) void {
    if (self.currentPath) |path| self.allocator.free(path);

    if (self.worker) |thread| {
        debug.print("FilePickerComponent.deinit(): Joining worker thread...\n");
        thread.join();
        self.worker = null;
    }

    self.state.deinit();
}

fn dispatchFilePickerAction(self: *FilePickerComponent) void {
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

fn processFilePickerResult(self: *FilePickerComponent) void {
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

fn rawDraw(selfOpaque: *anyopaque) void {
    const self: *FilePickerComponent = @ptrCast(@alignCast(selfOpaque));
    FilePickerComponent.draw(self);
}

fn rawUpdate(selfOpaque: *anyopaque) void {
    const self: *FilePickerComponent = @ptrCast(@alignCast(selfOpaque));
    FilePickerComponent.update(self);
}

fn rawDeinit(selfOpaque: *anyopaque) void {
    const self: *FilePickerComponent = @ptrCast(@alignCast(selfOpaque));
    FilePickerComponent.deinit(self);
}

fn rawNotify(selfOpaque: *anyopaque, event: Event) void {
    const self: *FilePickerComponent = @ptrCast(@alignCast(selfOpaque));
    FilePickerComponent.notify(self, event);
}

pub fn asComponent(self: *FilePickerComponent) Component {
    return Component{
        // Pass the pointer to the FilePickerComponent instance, type-erased.
        .self = self,
        // Pass the pointer to FilePickerComponent's specific vtable.
        .vtable = &VTable,
    };
}
