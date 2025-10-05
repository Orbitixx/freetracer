const std = @import("std");
const osd = @import("osdialog");

const freetracer_lib = @import("freetracer-lib");
const Debug = freetracer_lib.Debug;
const Character = freetracer_lib.constants.Character;
const ImageType = freetracer_lib.types.ImageType;
const Image = freetracer_lib.types.Image;

const AppConfig = @import("../../config.zig");
const MAX_EXT_LEN = AppConfig.MAX_EXT_LEN;

const EventManager = @import("../../managers/EventManager.zig").EventManagerSingleton;
const ComponentName = EventManager.ComponentName.ISO_FILE_PICKER;
const ComponentFramework = @import("../framework/import/index.zig");

const UIFramework = @import("../ui/import/index.zig");

pub const FilePickerState = struct {
    selected_path: ?[:0]u8 = null,
    is_selecting: bool = false,
    image: Image = .{},
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
        struct {},
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

    // WARNING: Can't call initComponent in here, because parent (*Component) reference will refence
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

pub fn handleEvent(self: *ISOFilePickerComponent, event: ComponentEvent) !EventResult {
    Debug.log(.DEBUG, "ISOFilePickerComponent: handleEvent() received an event: \"{s}\"", .{event.name});

    var eventResult = EventResult.init();

    eventLoop: switch (event.hash) {

        // NOTE: On UI Dimensions Changed
        ISOFilePickerUI.Events.onGetUIDimensions.Hash => {
            //
            const data = ISOFilePickerUI.Events.onGetUIDimensions.getData(event) orelse break :eventLoop;

            Debug.log(
                .DEBUG,
                "ISOFilePickerComponent: handleEvent() received: \"{s}\" event, data: newWidth = {d}",
                .{ event.name, data.transform.w },
            );

            eventResult.validate(.SUCCESS);
        },

        Events.onISOFileSelected.Hash => {
            self.state.lock();
            errdefer self.state.unlock();
            const isSelecting = self.state.data.is_selecting;
            const selectedPath = self.state.data.selected_path;
            self.state.unlock();

            if (isSelecting or selectedPath == null) {
                Debug.log(.WARNING,
                    \\"ISOFilePicker.handleEvent.onISOFileSelected: 
                    \\State reflects file is still being selected or path is NULL. Aborting event processing."
                , .{});
                break :eventLoop;
            }

            Debug.log(
                .INFO,
                "ISOFilePickerComponent: handleEvent() received: \"{s}\" event, data: newPath = {s}",
                .{ event.name, if (selectedPath) |newPath| newPath else "NULL" },
            );

            if (selectedPath) |newPath| {
                const pathUpToDot: []const u8 = std.mem.sliceTo(newPath, Character.DOT); // slice to the dot
                const fileExtension: []const u8 = newPath[pathUpToDot.len..];

                var isOKToProceedPopupResponse = false;
                const isExtensionOK = isExtensionAllowed(fileExtension);

                if (!isExtensionOK) {
                    //
                    isOKToProceedPopupResponse = osd.message("The extension of the selected file does not appear to be '.iso' or '.img', are you sure you want to proceed?", .{
                        .level = .warning,
                        .buttons = .yes_no,
                    });

                    if (!isOKToProceedPopupResponse) break :eventLoop;
                }

                {
                    self.state.lock();
                    defer self.state.unlock();
                    self.state.data.image.path = newPath;
                    self.state.data.image.type = getImageType(fileExtension);
                }

                const newEvent = ISOFilePickerUI.Events.onISOFilePathChanged.create(self.asComponentPtr(), &.{
                    .newPath = newPath,
                });

                if (self.uiComponent) |*ui| {
                    const result = try ui.handleEvent(newEvent);

                    if (!result.success) {
                        Debug.log(.ERROR, "FilePickerUI was not able to handle ISOFileNameChanged event.", .{});
                    }
                }

                eventResult.validate(.SUCCESS);
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
            const image = self.state.data.image;
            self.state.unlock();

            Debug.log(.INFO, "ISOFilePicker.handleEvent.onISOFilePathQueried: processing event...", .{});
            Debug.log(.DEBUG, "\tpath: {s}\n\tisSelecting: {any}", .{ path.?, isSelecting });

            // WARNING: Debug assertion
            std.debug.assert(path != null and isSelecting == false);

            if (path == null or isSelecting == true) {
                eventResult.success = false;
                eventResult.validation = .FAILURE;
                eventResult.data = null;

                Debug.log(
                    .WARNING,
                    \\"ISOFilePicker.handleEvent.onISOFilePathQueried: the ISO path is either NULL 
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
                .image = image,
            };

            eventResult.validate(.SUCCESS);
            eventResult.data = @ptrCast(@constCast(responseDataPtr));
        },

        else => {},
    }

    return eventResult;
}

pub fn deinit(self: *ISOFilePickerComponent) void {
    _ = self;
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

pub fn dispatchComponentAction(self: *ISOFilePickerComponent) void {
    self.selectFile() catch |err| {
        Debug.log(.ERROR, "ISOFilePickerComponent: Failed to dispatch component action. Error: {any}", .{err});
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
    Debug.log(.DEBUG, "ISOFilePickerComponent: runWorker() started!", .{});

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

pub fn isExtensionAllowed(ext: []const u8) bool {
    if (ext.len > MAX_EXT_LEN or ext.len < 1) {
        Debug.log(.ERROR, "Selected file's extension length is more than allowed MAX length or it is 0: `{s}`", .{ext});
        return false;
    }

    var fileExtBuffer: [MAX_EXT_LEN]u8 = std.mem.zeroes([MAX_EXT_LEN]u8);
    var allowedExtBuffer: [MAX_EXT_LEN]u8 = std.mem.zeroes([MAX_EXT_LEN]u8);
    _ = std.ascii.upperString(fileExtBuffer[0..ext.len], ext);

    const ucExt: []const u8 = std.mem.sliceTo(&fileExtBuffer, 0);

    for (AppConfig.ALLOWED_ISO_EXTENSIONS) |allowedExt| {
        allowedExtBuffer = std.mem.zeroes([MAX_EXT_LEN]u8);
        _ = std.ascii.upperString(allowedExtBuffer[0..allowedExt.len], allowedExt);
        const ucAllowedExt: []const u8 = std.mem.sliceTo(&allowedExtBuffer, 0x00);
        Debug.log(.DEBUG, "Comparing extensions: {s} and {s}", .{ ucExt, ucAllowedExt });
        if (std.mem.eql(u8, ucExt, ucAllowedExt)) return true;
    }

    return false;
}

fn getImageType(ext: []const u8) ImageType {
    var fileExtBuffer: [MAX_EXT_LEN]u8 = std.mem.zeroes([MAX_EXT_LEN]u8);
    _ = std.ascii.upperString(fileExtBuffer[0..ext.len], ext);
    const ucExt: []const u8 = std.mem.sliceTo(&fileExtBuffer, 0);

    if (std.mem.eql(u8, ucExt, "ISO")) return .ISO;
    if (std.mem.eql(u8, ucExt, "IMG")) return .IMG;

    return .Other;
}

test ".iso and .img extensions are allowed" {
    const ext1: []const u8 = ".iso";
    const ext2: []const u8 = ".img";

    try std.testing.expect(isExtensionAllowed(ext1));
    try std.testing.expect(isExtensionAllowed(ext2));
}

test "random extensions are not allowed" {
    const ext1: []const u8 = ".md";
    const ext2: []const u8 = ".exe";

    try std.testing.expect(!isExtensionAllowed(ext1));
    try std.testing.expect(!isExtensionAllowed(ext2));
}
