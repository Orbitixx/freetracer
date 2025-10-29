// Coordinates the GUI-side ISO/image selection workflow and bridges UI events to
// worker thread that invokes the platform file dialog. Owns the selected image
// memory and propagates state to other components via the ComponentFramework
// event bus while ensuring allocator ownership and worker lifecycle safety.
// ------------------------------------------------------------------------------
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

const AppManager = @import("../../managers/AppManager.zig");

const EventManager = @import("../../managers/EventManager.zig").EventManagerSingleton;
const ComponentName = EventManager.ComponentName.FILE_PICKER;
const ComponentFramework = @import("../framework/import/index.zig");

const UIFramework = @import("../ui/import/index.zig");

// This state is mutable and can be accessed from the main UI thread (draw/update)
// and a worker/event thread (handleEvent). Access must be guarded by state.lock().
pub const FilePickerState = struct {
    selectedPath: ?[:0]u8 = null,
    isSelecting: bool = false,
    image: Image = .{},
    userForcedUnknownImage: bool = false,
};

pub const ImageQueryObject = struct {
    imagePath: [:0]u8 = undefined,
    image: Image = undefined,
    userForcedUnknownImage: bool = false,
};

const ComponentState = ComponentFramework.ComponentState(FilePickerState);
const ComponentWorker = ComponentFramework.Worker(FilePickerState);
const Component = ComponentFramework.Component;

const ComponentEvent = ComponentFramework.Event;
const EventResult = ComponentFramework.EventResult;
const WorkerStatus = ComponentFramework.WorkerStatus;

const FilePickerUI = @import("./FilePickerUI.zig");

pub const FilePicker = @This();

// Component-agnostic props
state: ComponentState,
worker: ?ComponentWorker = null,
component: ?Component = null,

// Component-specific, unique props
allocator: std.mem.Allocator,
uiComponent: ?FilePickerUI = null,

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

    pub const onImageFileSelected = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_image_file_selected"),
        struct { newPath: ?[:0]u8 = null },
        struct {},
    );

    pub const onImageDetailsQueried = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_image_details_queried"),
        struct {
            result: *ImageQueryObject,
        },
        struct {
            isoPath: [:0]u8,
            image: Image,
        },
    );
};

/// Creates an FilePicker with an empty state; caller must invoke
/// `initComponent` and `start` before dispatching events. Allocator is retained
/// for the lifetime of the component and used by the worker thread.
pub fn init(allocator: std.mem.Allocator) !FilePicker {
    Debug.log(.DEBUG, "FilePicker: component initialized!", .{});

    return FilePicker{
        .allocator = allocator,
        .state = ComponentState.init(FilePickerState{}),
    };

    // NOTE: Can't call initComponent in here, because parent (*Component) reference will reference
    // address in the scope of this function instead of the struct.
}

pub fn initComponent(self: *FilePicker, parent: ?*Component) !void {
    if (self.component != null) return error.BaseComponentAlreadyInitialized;
    self.component = try Component.init(self, &ComponentImplementation.vtable, parent, self.allocator);
}

pub fn initWorker(self: *FilePicker) !void {
    if (self.worker != null) return error.ComponentWorkerAlreadyInitialized;

    self.worker = ComponentWorker.init(
        self.allocator,
        &self.state,
        .{
            .run_fn = FilePicker.workerRun,
            .run_context = self,
            .callback_fn = FilePicker.workerCallback,
            .callback_context = self,
        },
        .{
            .onSameThreadAsCaller = true,
        },
    );
}

/// Starts the worker thread context and materializes UI children; must only be
/// called once after `initComponent`. Subscribes the component to the event bus.
pub fn start(self: *FilePicker) !void {
    Debug.log(.DEBUG, "FilePicker: start() function called!", .{});

    try self.initWorker();

    if (self.component) |*component| {
        if (component.children != null) return error.ComponentAlreadyCalledStartBefore;

        if (!EventManager.subscribe(ComponentName, component)) return error.UnableToSubscribeToEventManager;

        Debug.log(.DEBUG, "FilePicker: attempting to initialize children...", .{});

        component.children = std.ArrayList(Component).empty;
        self.uiComponent = try FilePickerUI.init(self.allocator, self);

        if (component.children) |*children| {
            if (self.uiComponent) |*uiComponent| {
                try uiComponent.start();
                try children.append(self.allocator, uiComponent.asComponent());
            }
        }

        Debug.log(.DEBUG, "FilePicker: finished initializing children.", .{});
    }
}

pub fn update(self: *FilePicker) !void {
    self.checkAndJoinWorker();
}

pub fn draw(self: *FilePicker) !void {
    _ = self;
}

/// UI callback entry-point that safely dispatches the asynchronous selection
/// workflow; errors are logged rather than propagated to avoid UI crashes.
pub fn dispatchComponentAction(self: *FilePicker) void {
    self.selectFile() catch |err| {
        Debug.log(.ERROR, "FilePicker: Failed to dispatch component action. Error: {any}", .{err});
    };
}

/// Primary event handler. Dispatcher to more specialized functions.
pub fn handleEvent(self: *FilePicker, event: ComponentEvent) !EventResult {
    Debug.log(.DEBUG, "FilePicker: handleEvent received: \"{s}\"", .{event.name});

    var eventResult = EventResult.init();

    return switch (event.hash) {
        Events.onImageFileSelected.Hash => try self.handleImageFileSelected(),
        Events.onImageDetailsQueried.Hash => try self.handleImageDetailsQueried(event),
        AppManager.Events.AppResetEvent.Hash => self.handleAppResetRequest(),
        else => eventResult.fail(),
    };
}

pub fn deinit(self: *FilePicker) void {
    self.state.lock();
    defer self.state.unlock();
    if (self.state.data.selectedPath) |path| self.allocator.free(path);
    self.state.data.selectedPath = null;
    self.state.data.image = .{};
}

/// Handles the `onImageDetailsQueried` event, providing the currently selected path to the requester.
/// Avoids heap allocation by having the requester provide memory for the response.
fn handleImageDetailsQueried(self: *FilePicker, event: ComponentEvent) !EventResult {
    self.state.lock();
    defer self.state.unlock();

    const path = self.state.data.selectedPath;
    var eventResult = EventResult.init();

    const data = Events.onImageDetailsQueried.getData(event) orelse return eventResult.fail();

    if (path == null or self.state.data.isSelecting) {
        Debug.log(.WARNING, "FilePicker: Query failed. Path is null or selection is in progress.", .{});
        return eventResult.fail();
    }

    // Write the response directly into the caller-provided memory.
    data.result.* = ImageQueryObject{
        .imagePath = path.?,
        .image = self.state.data.image,
        .userForcedUnknownImage = self.state.data.userForcedUnknownImage,
    };

    return eventResult.succeed();
}

/// Handles the `onImageFileSelected` event after the worker finishes.
/// This function is responsible for validating the file and updating state and other components.
/// Validates the worker-selected path, updates component state, and notifies dependents.
/// Requires the component state lock to be held when invoked.
fn handleImageFileSelected(self: *FilePicker) !EventResult {
    self.state.lock();
    defer self.state.unlock();

    const selectedPath = self.state.data.selectedPath;
    const isSelecting = self.state.data.isSelecting;

    var eventResult = EventResult.init();

    if (isSelecting or selectedPath == null) {
        Debug.log(.WARNING, "FilePicker: State reflects file is still being selected or path is NULL.", .{});
        return eventResult.fail();
    }

    const newPath = selectedPath.?;
    try self.processSelectedPathLocked(newPath);

    return eventResult.succeed();
}

pub fn confirmSelectedImageFile(self: *FilePicker) !void {
    try AppManager.reportAction(.ImageSelected);

    const deactivateEvent = Events.onActiveStateChanged.create(self.asComponentPtr(), &.{ .isActive = false });
    _ = try EventManager.signal(EventManager.ComponentName.FILE_PICKER_UI, deactivateEvent);
    _ = try EventManager.signal(EventManager.ComponentName.DEVICE_LIST, deactivateEvent);
}

fn processSelectedPathLocked(self: *FilePicker, newPath: [:0]u8) !void {
    Debug.log(.DEBUG, "processSelectedPathLocked: attempting to validate the selected image file: {s}", .{newPath});
    const imageType = fs.getImageType(fs.getExtensionFromPath(newPath));

    Debug.log(.DEBUG, "processSelectedPathLocked: detected image type", .{});
    self.state.data.image.path = newPath;
    self.state.data.image.type = imageType;

    Debug.log(.DEBUG, "processSelectedPathLocked: calling openFileValidated", .{});

    const file = fs.openFileValidated(newPath, .{
        .userHomePath = std.posix.getenv("HOME") orelse return error.UnableToGetUserPath,
    }) catch |err| {
        Debug.log(.DEBUG, "processSelectedPathLocked: openFileValidated returned error", .{});
        var buf: [256]u8 = std.mem.zeroes([256]u8);
        _ = try std.fmt.bufPrint(&buf, "Could not obtain a validated file handle for selected file. Error: {any}.", .{err});
        Debug.log(.ERROR, "processSelectedPathLocked: Could not obtain a validated file handle for selected path: {s}; error: {any}", .{ std.mem.sliceTo(&buf, 0x00), err });
        _ = osd.message(@ptrCast(std.mem.sliceTo(&buf, 0x00)), .{ .buttons = .ok, .level = .err });
        return err;
    };

    defer file.close();

    Debug.log(.DEBUG, "processSelectedPathLocked: openFileValidated succeeded, getting file stats", .{});
    const stat = try file.stat();

    Debug.log(.DEBUG, "processSelectedPathLocked: successfully opened file. Size: {d}", .{stat.size});
    Debug.log(.DEBUG, "processSelectedPathLocked: attempting to validate structure...", .{});

    if (!fs.validateImageFile(file).isValid) {
        Debug.log(.DEBUG, "processSelectedPathLocked: file structure validation failed, showing dialog", .{});
        const proceed = osd.message("The selected file does not appear to contain a bootable file system (ISO 9660, UDF, GPT or MBR), this is unusual and may have unintended consequences. Are you sure you want to proceed?", .{
            .level = .warning,
            .buttons = .yes_no,
        });

        if (!proceed) {
            Debug.log(.DEBUG, "processSelectedPathLocked: user declined to proceed, cleaning up", .{});
            self.allocator.free(newPath);
            self.state.data.selectedPath = null;
            return;
        } else {
            self.state.data.userForcedUnknownImage = true;
        }
    }

    Debug.log(.INFO, "FilePicker selected file: {s}, size: {d:.0}", .{ newPath, stat.size });

    if (self.uiComponent) |*ui| {
        Debug.log(.DEBUG, "processSelectedPathLocked: notifying UI component of path change", .{});
        const pathChangedEvent = FilePickerUI.Events.onImageFilePathChanged.create(self.asComponentPtr(), &.{
            .newPath = newPath,
            .size = stat.size,
        });

        _ = try ui.handleEvent(pathChangedEvent);
    }

    Debug.log(.DEBUG, "processSelectedPathLocked: completed successfully", .{});
}

pub fn acceptDroppedFile(self: *FilePicker, path: []const u8) !void {
    if (path.len == 0) return;

    const owned = try self.allocator.alloc(u8, path.len + 1);
    @memcpy(owned[0..path.len], path);
    owned[path.len] = 0;
    const ownedZ = owned[0..path.len :0];

    self.state.lock();
    defer self.state.unlock();

    if (self.state.data.selectedPath) |prev| {
        self.allocator.free(prev);
    }

    self.state.data.selectedPath = ownedZ;
    self.state.data.isSelecting = false;

    self.processSelectedPathLocked(ownedZ) catch |err| {
        self.allocator.free(owned);
        self.state.data.selectedPath = null;
        return err;
    };
}

pub const HandleFileDropWrapper = struct {
    pub fn call(ptr: *anyopaque, path: []const u8) void {
        FilePicker.asInstance(ptr).acceptDroppedFile(path) catch |err| {
            Debug.log(.ERROR, "FilePicker: Failed to accept dropped file. Error: {any}", .{err});
        };
    }
};

pub fn selectFile(self: *FilePicker) !void {
    if (self.worker) |*worker| {
        try worker.start();
    }
}

pub const dispatchComponentActionWrapper = struct {
    pub fn call(ptr: *anyopaque) void {
        FilePicker.asInstance(ptr).selectFile() catch |err| {
            Debug.log(.ERROR, "FilePicker: Failed to dispatch component action. Error: {any}", .{err});
        };
    }
};

pub fn checkAndJoinWorker(self: *FilePicker) void {
    if (self.worker) |*worker| {
        if (worker.status == WorkerStatus.NEEDS_JOINING) {
            worker.join();
        }
    }
}

pub fn handleAppResetRequest(self: *FilePicker) EventResult {
    var eventResult = EventResult.init();
    self.deinit();
    return eventResult.succeed();
}

/// Runs on the worker thread to `synchronously` and `blockingly` invoke the OS file dialog
/// on the same thread and then signal completion back to the component on the owning thread.
/// Blocking because MacOS requires that new windows (like file picker) are spawned by the main thread.
pub fn workerRun(worker: *ComponentWorker, context: *anyopaque) void {
    Debug.log(.DEBUG, "FilePicker: runWorker() started!", .{});

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

    const event = FilePicker.Events.onImageFileSelected.create(
        &FilePicker.asInstance(worker.context.run_context).component.?,
        &.{},
    );

    _ = FilePicker.asInstance(worker.context.run_context).handleEvent(event) catch |err| {
        Debug.log(.DEBUG, "FilePicker Worker caught error: {any}", .{err});
    };

    Debug.log(.DEBUG, "FilePicker: runWorker() finished executing!", .{});
}

pub fn workerCallback(worker: *ComponentWorker, context: *anyopaque) void {
    Debug.log(.DEBUG, "FilePicker: workerCallback() called!", .{});

    _ = worker;
    _ = context;

    Debug.log(.DEBUG, "FilePicker: workerCallback() joined!", .{});
}

pub const ComponentImplementation = ComponentFramework.ImplementComponent(FilePicker);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;
