const std = @import("std");
const osd = @import("osdialog");
const debug = @import("../../lib/util/debug.zig");

const ComponentFramework = @import("../framework/import/index.zig");

const AppObserver = @import("../../observers/AppObserver.zig").AppObserver;
const ObserverEvent = @import("../../observers/ObserverEvents.zig").ObserverEvent;
const ObserverPayload = @import("../../observers/ObserverPayload.zig");

pub const FilePickerState = struct {
    selected_path: ?[:0]u8 = null,
    is_selecting: bool = false,
};

const ComponentState = ComponentFramework.ComponentState(FilePickerState);
const ComponentWorker = ComponentFramework.Worker(FilePickerState);
const Component = ComponentFramework.Component;

const ComponentEvent = ComponentFramework.Event;
const EventResult = ComponentFramework.EventResult;
const WorkerStatus = ComponentFramework.WorkerStatus;

const ISOFilePickerUI = @import("./FilePickerUI.zig");

pub const ISOFilePickerComponent = @This();
component: ?Component = null,
allocator: std.mem.Allocator,
appObserver: *const AppObserver,
state: ComponentState,
worker: ?ComponentWorker = null,

pub const Events = struct {
    pub const UIWidthChangedEvent = ComponentFramework.defineEvent("iso_file_picker.ui_width_changed", struct { newWidth: f32 });
};

pub fn init(allocator: std.mem.Allocator, appObserver: *const AppObserver) ISOFilePickerComponent {
    std.debug.print("\nISOFilePickerComponent: component initialized!", .{});

    return .{
        .allocator = allocator,
        .appObserver = appObserver,
        .state = ComponentState.init(FilePickerState{}),
    };
}

pub fn initComponent(self: *ISOFilePickerComponent) void {
    self.component = Component.init(self, &ComponentImplementation.vtable);
}

fn initWorker(self: *ISOFilePickerComponent) void {
    self.worker = ComponentWorker.init(
        self.allocator,
        &self.state,
        .{
            .run_fn = ISOFilePickerComponent.workerRun,
            .run_context = self,
            .callback_fn = ISOFilePickerComponent.workerCallback,
            .callback_context = self,
        },
        .{
            .onSameThreadAsCaller = true,
        },
    );
}

pub fn start(self: *ISOFilePickerComponent) !void {
    std.debug.print("\nISOFilePickerComponent: start() function called!", .{});
    if (self.component == null) self.initComponent();
    if (self.worker == null) self.initWorker();

    if (self.component) |*component| {
        component.children = std.ArrayList(Component).init(self.allocator);
        var uiComponent = ISOFilePickerUI.init(self);
        try uiComponent.start();
        try component.children.?.append(uiComponent.asComponent());
    }
}

pub fn update(self: *ISOFilePickerComponent) !void {
    // Check for file selection changes
    const state = self.state.getDataLocked();
    defer self.state.unlock();

    self.checkAndJoinWorker();

    _ = state;

    // Update logic
}

pub fn draw(self: *ISOFilePickerComponent) !void {
    // Draw file picker UI
    // const state = self.state.getDataLocked();
    // defer self.state.unlock();

    // std.debug.print("\nDrawing file picker UI, selected: {s}", .{if (state.selected_path) |path| path else "none"});

    // Draw UI elements

    _ = self;
}

pub fn handleEvent(self: *ISOFilePickerComponent, event: ComponentEvent) !EventResult {
    _ = self;

    debug.printf("\nISOFilePickerComponent: handleEvent() received an event: \"{s}\"", .{event.name});

    var eventResult = EventResult{};

    switch (event.hash) {
        Events.UIWidthChangedEvent.Hash => {
            // TODO: handle null data gracefully
            const data = Events.UIWidthChangedEvent.getData(&event).?;

            if (@TypeOf(data.*) == Events.UIWidthChangedEvent.Data) {
                eventResult.success = true;
                eventResult.validation = @intFromFloat(data.newWidth);
            }

            debug.printf("\nISOFilePickerComponent: handleEvent() received: \"{s}\" event, data: newWidth = {d}", .{ event.name, data.newWidth });
        },
        else => {},
    }

    return eventResult;
}

pub fn deinit(self: *ISOFilePickerComponent) void {
    // Clean up resources
    const state = self.state.getDataLocked();
    defer self.state.unlock();

    if (state.selected_path) |path| {
        self.allocator.free(path);
    }

    if (self.component) |*component| {
        if (component.children) |children| {
            if (children.items.len > 0) {
                for (children.items) |*child| {
                    child.deinit();
                }
            }

            children.deinit();
        }

        component.children = null;
    }

    self.component = null;
}

pub fn notify(self: *ISOFilePickerComponent, event: ObserverEvent, payload: ObserverPayload) void {
    self.appObserver.onNotify(event, payload);
}

pub fn selectFile(self: *ISOFilePickerComponent) !void {
    if (self.worker) |*worker| {
        try worker.start();
    }
}

pub fn checkAndJoinWorker(self: *ISOFilePickerComponent) void {
    if (self.worker) |*worker| {
        if (worker.status == WorkerStatus.NEEDS_JOINING) {
            worker.join();
        }
    }
}

pub fn workerRun(worker: *ComponentWorker, context: *anyopaque) void {
    std.debug.print("\nISOFilePickerComponent: runWorker() started!", .{});

    _ = context;

    worker.state.withLock(struct {
        fn lambda(state: *FilePickerState) void {
            state.is_selecting = true;
        }
    }.lambda);

    worker.state.lock();
    defer worker.state.unlock();

    worker.state.data.selected_path = osd.path(worker.allocator, .open, .{});
    worker.state.data.is_selecting = false;

    std.debug.print("\nISOFilePickerComponent: runWorker() finished executing!", .{});
}

pub fn workerCallback(worker: *ComponentWorker, context: *anyopaque) void {
    std.debug.print("\nISOFilePickerComponent: workerCallback() called!", .{});

    _ = worker;
    _ = context;

    std.debug.print("\nISOFilePickerComponent: workerCallback() joined!", .{});
}

pub const ComponentImplementation = ComponentFramework.ImplementComponent(ISOFilePickerComponent);
pub const asComponent = ComponentImplementation.asComponent;
pub const asInstance = ComponentImplementation.asInstance;
