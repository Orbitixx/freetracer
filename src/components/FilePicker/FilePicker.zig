const std = @import("std");
const osd = @import("osdialog");

const freetracer_lib = @import("freetracer-lib");
const Debug = freetracer_lib.Debug;
const Character = freetracer_lib.constants.Character;
const ImageType = freetracer_lib.types.ImageType;
const Image = freetracer_lib.types.Image;

const fs = freetracer_lib.fs;

const AppConfig = @import("../../config.zig");
const MAX_EXT_LEN = AppConfig.MAX_EXT_LEN;

const EventManager = @import("../../managers/EventManager.zig").EventManagerSingleton;
const ComponentName = EventManager.ComponentName.ISO_FILE_PICKER;
const ComponentFramework = @import("../framework/import/index.zig");

const UIFramework = @import("../ui/import/index.zig");

pub const FilePickerState = struct {
    selectedPath: ?[:0]u8 = null,
    isSelecting: bool = false,
    image: Image = .{},
};

pub const ImageQueryObject = struct {
    imagePath: [:0]u8 = undefined,
    image: Image = undefined,
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
        EventManager.createEventName(ComponentName, "on_active_state_changed"),
        struct { isActive: bool },
        struct {},
    );

    pub const onUIWidthChanged = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_ui_width_changed"),
        struct { newWidth: f32 },
        struct {},
    );

    pub const onISOFileSelected = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_iso_file_selected"),
        struct { newPath: ?[:0]u8 = null },
        struct {},
    );

    pub const onISOFilePathQueried = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_iso_file_path_queried"),
        struct {
            result: *ImageQueryObject,
        },
        struct {
            isoPath: [:0]u8,
            image: Image,
        },
    );
};

pub fn init(allocator: std.mem.Allocator) !ISOFilePickerComponent {
    Debug.log(.DEBUG, "ISOFilePickerComponent: component initialized!", .{});

    return ISOFilePickerComponent{
        .allocator = allocator,
        .state = ComponentState.init(FilePickerState{}),
    };

    // NOTE: Can't call initComponent in here, because parent (*Component) reference will reference
    // address in the scope of this function instead of the struct.
}

pub fn initComponent(self: *ISOFilePickerComponent, parent: ?*Component) !void {
    if (self.component != null) return error.BaseComponentAlreadyInitialized;
    self.component = try Component.init(self, &ComponentImplementation.vtable, parent, self.allocator);
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
    Debug.log(.DEBUG, "ISOFilePickerComponent: start() function called!", .{});

    try self.initWorker();

    if (self.component) |*component| {
        if (component.children != null) return error.ComponentAlreadyCalledStartBefore;

        if (!EventManager.subscribe(ComponentName, component)) return error.UnableToSubscribeToEventManager;

        Debug.log(.DEBUG, "ISOFilePickerComponent: attempting to initialize children...", .{});

        component.children = std.ArrayList(Component).empty;
        self.uiComponent = try ISOFilePickerUI.init(self.allocator, self);

        if (component.children) |*children| {
            if (self.uiComponent) |*uiComponent| {
                try uiComponent.start();
                try children.append(self.allocator, uiComponent.asComponent());
            }
        }

        Debug.log(.DEBUG, "ISOFilePickerComponent: finished initializing children.", .{});
    }
}

pub fn update(self: *ISOFilePickerComponent) !void {
    self.checkAndJoinWorker();
}

pub fn draw(self: *ISOFilePickerComponent) !void {
    _ = self;
}

pub fn dispatchComponentAction(self: *ISOFilePickerComponent) void {
    self.selectFile() catch |err| {
        Debug.log(.ERROR, "ISOFilePickerComponent: Failed to dispatch component action. Error: {any}", .{err});
    };
}

/// Primary event handler. Dispatcher to more specialized functions.
pub fn handleEvent(self: *ISOFilePickerComponent, event: ComponentEvent) !EventResult {
    Debug.log(.DEBUG, "ISOFilePickerComponent: handleEvent received: \"{s}\"", .{event.name});

    var eventResult = EventResult.init();

    return switch (event.hash) {
        Events.onISOFileSelected.Hash => try self.handleISOFileSelected(),
        Events.onISOFilePathQueried.Hash => try self.handleISOFilePathQueried(event),
        else => eventResult.fail(),
    };
}

pub fn deinit(self: *ISOFilePickerComponent) void {
    self.state.lock();
    defer self.state.unlock();
    if (self.state.data.selectedPath) |path| self.allocator.free(path);
}

/// Handles the `onISOFilePathQueried` event, providing the currently selected path to the requester.
/// Avoids heap allocation by having the requester provide memory for the response.
fn handleISOFilePathQueried(self: *ISOFilePickerComponent, event: ComponentEvent) !EventResult {
    self.state.lock();
    defer self.state.unlock();

    const path = self.state.data.selectedPath;
    var eventResult = EventResult.init();

    const data = Events.onISOFilePathQueried.getData(event) orelse return eventResult.fail();

    if (path == null or self.state.data.isSelecting) {
        Debug.log(.WARNING, "ISOFilePicker: Query failed. Path is null or selection is in progress.", .{});
        return eventResult.fail();
    }

    // Write the response directly into the caller-provided memory.
    data.result.* = ImageQueryObject{
        .imagePath = path.?,
        .image = self.state.data.image,
    };

    return eventResult.succeed();
}

/// Handles the `onISOFileSelected` event after the worker finishes.
/// This function is responsible for validating the file and updating state and other components.
fn handleISOFileSelected(self: *ISOFilePickerComponent) !EventResult {
    self.state.lock();
    defer self.state.unlock();

    const selectedPath = self.state.data.selectedPath;
    const isSelecting = self.state.data.isSelecting;

    var eventResult = EventResult.init();

    if (isSelecting or selectedPath == null) {
        Debug.log(.WARNING, "ISOFilePicker: State reflects file is still being selected or path is NULL.", .{});
        return eventResult.fail();
    }

    const newPath = selectedPath.?;

    // --- Validate extension
    if (!fs.isExtensionAllowed(AppConfig.ALLOWED_ISO_EXTENSIONS.len, AppConfig.ALLOWED_ISO_EXTENSIONS, newPath)) {
        const proceed = osd.message("The selected file extension is not a recognized image type (.iso, .img). Proceed anyway?", .{
            .level = .warning,
            .buttons = .yes_no,
        });

        if (!proceed) {
            // If user cancelled, clean up the path.
            self.allocator.free(newPath);
            self.state.data.selectedPath = null;
            return eventResult.succeed();
        }
    }

    // --- Update state & notify UI
    self.state.data.image.path = newPath;
    self.state.data.image.type = fs.getImageType(fs.getExtensionFromPath(newPath));

    if (self.uiComponent) |*ui| {
        const pathChangedEvent = ISOFilePickerUI.Events.onISOFilePathChanged.create(self.asComponentPtr(), &.{
            .newPath = newPath,
        });

        _ = try ui.handleEvent(pathChangedEvent);
    }

    // --- Notify other components
    const deactivateEvent = Events.onActiveStateChanged.create(self.asComponentPtr(), &.{ .isActive = false });

    // signal() instead of broadcast() because order of operation matters here.
    _ = try EventManager.signal("iso_file_picker_ui", deactivateEvent);
    _ = try EventManager.signal("device_list", deactivateEvent);

    return eventResult.succeed();
}

pub fn selectFile(self: *ISOFilePickerComponent) !void {
    if (self.worker) |*worker| {
        try worker.start();
    }
}

pub const dispatchComponentActionWrapper = struct {
    pub fn call(ptr: *anyopaque) void {
        ISOFilePickerComponent.asInstance(ptr).selectFile() catch |err| {
            Debug.log(.ERROR, "ISOFilePickerComponent: Failed to dispatch component action. Error: {any}", .{err});
        };
    }
};

pub fn checkAndJoinWorker(self: *ISOFilePickerComponent) void {
    if (self.worker) |*worker| {
        if (worker.status == WorkerStatus.NEEDS_JOINING) {
            worker.join();
        }
    }
}

pub fn workerRun(worker: *ComponentWorker, context: *anyopaque) void {
    Debug.log(.DEBUG, "ISOFilePickerComponent: runWorker() started!", .{});

    _ = context;

    worker.state.lock();
    errdefer worker.state.unlock();
    worker.state.data.isSelecting = true;

    // NOTE: It is important that this memory address / contents are released in component's deinit().
    // Currently, the ownership change occurs inside of handleEvent(), which assigns state as owner.
    // NOTE: osd.path cannot be run on a child process and must be run on the main process (enforced by MacOS).
    const selectedPath = osd.path(worker.allocator, .open, .{});

    if (worker.state.data.selectedPath) |previous| {
        if (selectedPath == null or previous.ptr != selectedPath.?.ptr) {
            worker.allocator.free(previous);
        }
    }

    worker.state.data.isSelecting = false;
    worker.state.data.selectedPath = selectedPath;
    worker.state.unlock();

    const event = ISOFilePickerComponent.Events.onISOFileSelected.create(
        &ISOFilePickerComponent.asInstance(worker.context.run_context).component.?,
        &.{},
    );

    _ = ISOFilePickerComponent.asInstance(worker.context.run_context).handleEvent(event) catch |err| {
        Debug.log(.DEBUG, "ISOFilePickerComponent Worker caught error: {any}", .{err});
    };

    Debug.log(.DEBUG, "ISOFilePickerComponent: runWorker() finished executing!", .{});
}

pub fn workerCallback(worker: *ComponentWorker, context: *anyopaque) void {
    Debug.log(.DEBUG, "ISOFilePickerComponent: workerCallback() called!", .{});

    _ = worker;
    _ = context;

    Debug.log(.DEBUG, "ISOFilePickerComponent: workerCallback() joined!", .{});
}

pub const ComponentImplementation = ComponentFramework.ImplementComponent(ISOFilePickerComponent);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;

pub const FilePickerComponent = @import("../framework/Component.zig").implementInterface(Component, ISOFilePickerComponent);
// FilePickerComponent.
