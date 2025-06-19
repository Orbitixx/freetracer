const std = @import("std");
const osd = @import("osdialog");
const debug = @import("../../lib/util/debug.zig");

const EventManager = @import("../../managers/EventManager.zig").EventManagerSingleton;
const ComponentFramework = @import("../framework/import/index.zig");

const UIFramework = @import("../ui/import/index.zig");

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

// Component-agnostic props
state: ComponentState,
worker: ?ComponentWorker = null,
component: ?Component = null,

// Component-specific, unique props
allocator: std.mem.Allocator,
uiComponent: ?ISOFilePickerUI = null,

pub const Events = struct {
    //
    pub const UIWidthChangedEvent = ComponentFramework.defineEvent(
        "iso_file_picker.ui_width_changed",
        struct { newWidth: f32 },
    );

    pub const ISOFileSelected = ComponentFramework.defineEvent(
        "iso_file_picker.iso_file_selected",
        struct { newPath: ?[:0]u8 = null },
    );
};

pub fn init(allocator: std.mem.Allocator) !ISOFilePickerComponent {
    std.debug.print("\nISOFilePickerComponent: component initialized!", .{});

    return ISOFilePickerComponent{
        .allocator = allocator,
        .state = ComponentState.init(FilePickerState{}),
    };

    // WARNING: Can't call initComponent in here, because parent (*Component) reference will refence
    // address in the scope of this function instead of the struct.
}

pub fn initComponent(self: *ISOFilePickerComponent, parent: ?*Component) !void {
    if (self.component != null) return error.BaseComponentAlreadyInitialized;
    self.component = try Component.init(self, &ComponentImplementation.vtable, parent);
}

pub fn initWorker(self: *ISOFilePickerComponent) !void {
    if (self.worker != null) return error.ComponentWorkerAlreadyInitialized;

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

    try self.initWorker();

    if (self.component) |*component| {
        if (component.children != null) return error.ComponentAlreadyCalledStartBefore;

        if (!EventManager.subscribe(component)) return error.UnableToSubscribeToEventManager;

        std.debug.print("\nISOFilePickerComponent: attempting to initialize children...", .{});

        component.children = std.ArrayList(Component).init(self.allocator);

        self.uiComponent = try ISOFilePickerUI.init(self);

        if (component.children) |*children| {
            if (self.uiComponent) |*uiComponent| {
                try uiComponent.start();
                try children.append(uiComponent.asComponent());
            }
        }

        std.debug.print("\nISOFilePickerComponent: finished initializing children.", .{});
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
    debug.printf("\nISOFilePickerComponent: handleEvent() received an event: \"{s}\"", .{event.name});

    var eventResult = EventResult.init();

    eventLoop: switch (event.hash) {

        // NOTE: On UI Dimensions Changed
        ISOFilePickerUI.Events.ISOFilePickerUIGetUIDimensions.Hash => {
            //
            const data = ISOFilePickerUI.Events.ISOFilePickerUIGetUIDimensions.getData(event) orelse break :eventLoop;
            eventResult.validate(1);

            debug.printf(
                "\nISOFilePickerComponent: handleEvent() received: \"{s}\" event, data: newWidth = {d}",
                .{ event.name, data.transform.w },
            );
        },

        Events.ISOFileSelected.Hash => {
            //
            const data = Events.ISOFileSelected.getData(event) orelse break :eventLoop;
            eventResult.validate(1);

            debug.printf(
                "\nISOFilePickerComponent: handleEvent() received: \"{s}\" event, data: newPath = {s}",
                .{ event.name, data.newPath.? },
            );

            var state = self.state.getData();
            state.selected_path = data.newPath;
            state.is_selecting = false;

            if (data.newPath) |newPath| {
                const pathBuffer: [:0]u8 = try self.allocator.dupeZ(u8, newPath);

                const eventData = ISOFilePickerUI.Events.ISOFilePathChanged.Data{ .newPath = pathBuffer };
                const newEvent = ISOFilePickerUI.Events.ISOFilePathChanged.create(&self.component.?, &eventData);

                if (self.uiComponent) |*ui| {
                    const result = try ui.handleEvent(newEvent);

                    if (!result.success) {
                        debug.print("\nERROR: FilePickerUI was not able to handle ISOFileNameChanged event.");
                    }
                }
            }

            const makeUIInactiveData = ISOFilePickerUI.Events.ISOFilePickerActiveStateChanged.Data{ .isActive = false };
            const makeUIInactiveEvent = ISOFilePickerUI.Events.ISOFilePickerActiveStateChanged.create(&self.component.?, &makeUIInactiveData);

            EventManager.broadcast(makeUIInactiveEvent);
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
}

pub fn selectFile(self: *ISOFilePickerComponent) !void {
    if (self.worker) |*worker| {
        try worker.start();
    }
}

pub const dispatchComponentActionWrapper = struct {
    pub fn call(ptr: *anyopaque) void {
        ISOFilePickerComponent.asInstance(ptr).selectFile() catch |err| {
            debug.printf("\nISOFilePickerComponent: Failed to dispatch component action. Error: {any}", .{err});
        };
    }
};

pub fn dispatchComponentAction(self: *ISOFilePickerComponent) void {
    self.selectFile() catch |err| {
        debug.printf("\nISOFilePickerComponent: Failed to dispatch component action. Error: {any}", .{err});
    };
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

    // NOTE: It is important that this memory address / contents are released in component's deinit().
    // Currently, the ownership change occurs inside of handleEvent(), which assigns state as owner.
    const selectedPath = osd.path(worker.allocator, .open, .{});

    const data = ISOFilePickerComponent.Events.ISOFileSelected.Data{ .newPath = selectedPath };

    const event = ISOFilePickerComponent.Events.ISOFileSelected.create(
        &ISOFilePickerComponent.asInstance(worker.context.run_context).component.?,
        &data,
    );

    _ = ISOFilePickerComponent.asInstance(worker.context.run_context).handleEvent(event) catch |err| {
        debug.printf("ISOFilePickerComponent Worker caught error: {any}", .{err});
    };

    // NOTE: It is also possible to modify the Component State directly like below. Similar ownership disclaimer applies.
    // worker.state.data.selected_path = osd.path(worker.allocator, .open, .{});
    // worker.state.data.is_selecting = false;

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
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;
