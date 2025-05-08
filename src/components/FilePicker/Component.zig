const std = @import("std");
const debug = @import("../../lib/util/debug.zig");
const UI = @import("../../lib/ui/ui.zig");

const AppObserverF = @import("../../observers/AppObserver.zig");

const AppObserver = AppObserverF.AppObserver;
const Event = AppObserverF.Event;
const EventPayload = AppObserverF.Payload;

const Component = @import("../Component.zig");

const FilePickerComponent = @This();
const FilePickerState = @import("State.zig");
const FilePickerWorker = @import("Worker.zig");
const ComponentUI = @import("UI.zig");

allocator: std.mem.Allocator,
appObserver: *const AppObserver,
state: *FilePickerState,
worker: ?std.Thread = null,
componentActive: bool = true,
currentPath: ?[:0]const u8 = null,
ui: ComponentUI,

pub fn init(allocator: std.mem.Allocator, appObserver: *const AppObserver) FilePickerComponent {
    const state = allocator.create(FilePickerState) catch |err| {
        debug.printf("\nERROR: Unable to create a pointer to FilePickerState. {any}", .{err});
        std.debug.panic("{any}", .{err});
    };

    state.* = .{ .allocator = allocator };

    var component: FilePickerComponent = .{
        .allocator = allocator,
        .appObserver = appObserver,
        .state = state,
        .ui = .{
            .appObserver = appObserver,
        },
    };

    component.ui.init();

    return component;
}

pub fn enable(self: *FilePickerComponent) void {
    self.componentActive = true;
}

pub fn setActive(self: *FilePickerComponent, flag: bool) void {
    // self.componentActive = flag;
    self.ui.setActive(flag);
}

pub fn update(self: *FilePickerComponent) void {
    if (!self.componentActive) return;

    var workerFinished = false;

    self.ui.update();

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

        self.notify(Event.ISO_FILE_SELECTED, .{});
    }
}

pub fn draw(self: *FilePickerComponent) void {
    if (!self.componentActive) return;

    self.ui.draw();
    // self.button.draw();
}

pub fn notify(self: *FilePickerComponent, event: Event, payload: EventPayload) void {
    self.appObserver.*.onNotify(event, payload);
}

pub fn deinit(self: *FilePickerComponent) void {
    if (self.currentPath) |path| self.allocator.free(path);

    if (self.worker) |thread| {
        debug.print("FilePickerComponent.deinit(): Joining worker thread...\n");
        thread.join();
        self.worker = null;
    }

    self.state.deinit();
    self.allocator.destroy(self.state);
}

pub fn asComponent(self: *const FilePickerComponent) Component {
    return Component{
        .ptr = @constCast(self),
        .vtable = &VTable,
    };
}

pub fn dispatchComponentAction(self: *FilePickerComponent) void {
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

    FilePickerWorker.run(self.allocator, self.state);
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

        // if (self.currentPath) |oldPath| self.allocator.free(oldPath);

        self.currentPath = newPath;
        return;
    }

    // If file picker dialog cancelled without picking a file.
    debug.print("\nFilePickerComponent: worker successfully returned without a path (null/cancelled).");
    if (self.currentPath) |oldPath| self.allocator.free(oldPath);
    self.currentPath = null;
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
    const self: *FilePickerComponent = @ptrCast(@alignCast(selfOpaque));
    FilePickerComponent.enable(self);
}

fn rawDraw(selfOpaque: *anyopaque) void {
    const self: *FilePickerComponent = @ptrCast(@alignCast(selfOpaque));
    FilePickerComponent.draw(self);
}

fn rawUpdate(selfOpaque: *anyopaque) void {
    const self: *FilePickerComponent = @ptrCast(@alignCast(selfOpaque));
    FilePickerComponent.update(self);
}

fn rawNotify(selfOpaque: *anyopaque, event: Event, payload: EventPayload) void {
    const self: *FilePickerComponent = @ptrCast(@alignCast(selfOpaque));
    FilePickerComponent.notify(self, event, payload);
}

fn rawDeinit(selfOpaque: *anyopaque) void {
    const self: *FilePickerComponent = @ptrCast(@alignCast(selfOpaque));
    FilePickerComponent.deinit(self);
}
