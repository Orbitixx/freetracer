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
    pub const onActiveStateChanged = ComponentFramework.defineEvent(
        "iso_file_picker.on_active_state_changed",
        struct {
            isActive: bool,
        },
        struct {},
    );

    pub const onUIWidthChanged = ComponentFramework.defineEvent(
        "iso_file_picker.on_ui_width_changed",
        struct {
            newWidth: f32,
        },
        struct {},
    );

    pub const onISOFileSelected = ComponentFramework.defineEvent(
        "iso_file_picker.on_iso_file_selected",
        struct {
            newPath: ?[:0]u8 = null,
        },
        struct {},
    );

    pub const onISOFilePathQueried = ComponentFramework.defineEvent(
        "iso_file_picker.on_iso_file_path_queried",
        struct {},
        struct {
            isoPath: [:0]u8,
        },
    );
};

pub fn init(allocator: std.mem.Allocator) !ISOFilePickerComponent {
    std.debug.print("ISOFilePickerComponent: component initialized!", .{});

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
    std.debug.print("ISOFilePickerComponent: start() function called!", .{});

    try self.initWorker();

    if (self.component) |*component| {
        if (component.children != null) return error.ComponentAlreadyCalledStartBefore;

        if (!EventManager.subscribe("iso_file_picker", component)) return error.UnableToSubscribeToEventManager;

        std.debug.print("ISOFilePickerComponent: attempting to initialize children...", .{});

        component.children = std.ArrayList(Component).init(self.allocator);

        self.uiComponent = try ISOFilePickerUI.init(self.allocator, self);

        if (component.children) |*children| {
            if (self.uiComponent) |*uiComponent| {
                try uiComponent.start();
                try children.append(uiComponent.asComponent());
            }
        }

        std.debug.print("ISOFilePickerComponent: finished initializing children.", .{});
    }
}

pub fn update(self: *ISOFilePickerComponent) !void {
    // Check for file selection changes
    // const state = self.state.getDataLocked();
    // defer self.state.unlock();

    self.checkAndJoinWorker();

    // Update logic
}

pub fn draw(self: *ISOFilePickerComponent) !void {
    // Draw file picker UI
    // const state = self.state.getDataLocked();
    // defer self.state.unlock();

    // Draw UI elements

    _ = self;
}

pub fn handleEvent(self: *ISOFilePickerComponent, event: ComponentEvent) !EventResult {
    debug.printf("ISOFilePickerComponent: handleEvent() received an event: \"{s}\"", .{event.name});

    var eventResult = EventResult.init();

    eventLoop: switch (event.hash) {

        // NOTE: On UI Dimensions Changed
        ISOFilePickerUI.Events.onGetUIDimensions.Hash => {
            //
            const data = ISOFilePickerUI.Events.onGetUIDimensions.getData(event) orelse break :eventLoop;
            eventResult.validate(1);

            debug.printf(
                "ISOFilePickerComponent: handleEvent() received: \"{s}\" event, data: newWidth = {d}",
                .{ event.name, data.transform.w },
            );
        },

        Events.onISOFileSelected.Hash => {
            self.state.lock();
            errdefer self.state.unlock();
            const isSelecting = self.state.data.is_selecting;
            const selectedPath = self.state.data.selected_path;
            self.state.unlock();

            if (isSelecting or selectedPath == null) {
                debug.print(
                    \\"ISOFilePicker.handleEvent.onISOFileSelected: 
                    \\WARNING - State reflects file is still being selected or path is NULL. Aborting event processing."
                    ,
                );
                break :eventLoop;
            }

            eventResult.validate(1);

            debug.printf(
                "ISOFilePickerComponent: handleEvent() received: \"{s}\" event, data: newPath = {s}",
                .{ event.name, if (selectedPath) |newPath| newPath else "NULL" },
            );

            if (selectedPath) |newPath| {
                //
                // TODO: Review this block again, this seems a bit crazy on the second look to dispatch another event with similar payload.
                const pathBuffer: [:0]u8 = try self.allocator.dupeZ(u8, newPath);

                const newEvent = ISOFilePickerUI.Events.onISOFilePathChanged.create(self.asComponentPtr(), &.{
                    .newPath = pathBuffer,
                });

                if (self.uiComponent) |*ui| {
                    const result = try ui.handleEvent(newEvent);

                    if (!result.success) {
                        debug.print("ERROR: FilePickerUI was not able to handle ISOFileNameChanged event.");
                    }
                }
            }

            const inactivateComponentEvent = Events.onActiveStateChanged.create(
                self.asComponentPtr(),
                &.{ .isActive = false },
            );

            // NOTE: Cannot broadcast here because order of operations matters here.
            _ = try EventManager.signal("iso_file_picker_ui", inactivateComponentEvent);
            _ = try EventManager.signal("device_list", inactivateComponentEvent);
        },

        Events.onISOFilePathQueried.Hash => {
            //
            self.state.lock();
            errdefer self.state.unlock();
            const path = self.state.data.selected_path;
            const isSelecting = self.state.data.is_selecting;
            self.state.unlock();

            debug.print("ISOFilePicker.handleEvent.onISOFilePathQueried: processing event...");

            debug.printf("\tpath: {s}\n\tisSelecting: {any}", .{ path.?, isSelecting });

            // WARNING: Debug assertion
            std.debug.assert(path != null and isSelecting == false);

            if (path == null or isSelecting == true) {
                eventResult.success = false;
                eventResult.validation = 0;
                eventResult.data = null;

                debug.printf(
                    \\"WARNING: ISOFilePicker.handleEvent.onISOFilePathQueried: the ISO path is either NULL 
                    \\ or is still being selected. Path: {any}, isSelecting: {any}"
                ,
                    .{ path, isSelecting },
                );

                break :eventLoop;
            }

            // TODO: Need to allocate space on the heap. Doesn't feel clean. Rethink this.
            // WARNING: Heap allocation
            const responseDataPtr = try self.allocator.create(Events.onISOFilePathQueried.Response);

            responseDataPtr.* = Events.onISOFilePathQueried.Response{
                .isoPath = path.?,
            };

            eventResult.validate(1);
            eventResult.data = @ptrCast(@constCast(responseDataPtr));
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
            debug.printf("ISOFilePickerComponent: Failed to dispatch component action. Error: {any}", .{err});
        };
    }
};

pub fn dispatchComponentAction(self: *ISOFilePickerComponent) void {
    self.selectFile() catch |err| {
        debug.printf("ISOFilePickerComponent: Failed to dispatch component action. Error: {any}", .{err});
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
    std.debug.print("ISOFilePickerComponent: runWorker() started!", .{});

    _ = context;

    // Update state in a block with shorter lifecycle (handles unlock on error too)
    {
        worker.state.lock();
        defer worker.state.unlock();
        worker.state.data.is_selecting = true;
    }

    // NOTE: It is important that this memory address / contents are released in component's deinit().
    // Currently, the ownership change occurs inside of handleEvent(), which assigns state as owner.
    // NOTE: osd.path cannot be run on a child process and must be run on the main process (enforced by MacOS).
    const selectedPath = osd.path(worker.allocator, .open, .{});

    // Update state in a block with shorter lifecycle (handles unlock on error too)
    {
        worker.state.lock();
        defer worker.state.unlock();
        worker.state.data.is_selecting = false;
        worker.state.data.selected_path = selectedPath;
    }

    const event = ISOFilePickerComponent.Events.onISOFileSelected.create(
        &ISOFilePickerComponent.asInstance(worker.context.run_context).component.?,
        &.{},
    );

    _ = ISOFilePickerComponent.asInstance(worker.context.run_context).handleEvent(event) catch |err| {
        debug.printf("ISOFilePickerComponent Worker caught error: {any}", .{err});
    };

    std.debug.print("ISOFilePickerComponent: runWorker() finished executing!", .{});
}

pub fn workerCallback(worker: *ComponentWorker, context: *anyopaque) void {
    std.debug.print("ISOFilePickerComponent: workerCallback() called!", .{});

    _ = worker;
    _ = context;

    std.debug.print("ISOFilePickerComponent: workerCallback() joined!", .{});
}

pub const ComponentImplementation = ComponentFramework.ImplementComponent(ISOFilePickerComponent);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;
