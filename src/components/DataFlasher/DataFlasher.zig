const std = @import("std");
const osd = @import("osdialog");
const freetracer_lib = @import("freetracer-lib");
const Debug = freetracer_lib.Debug;
const types = freetracer_lib.types;

const StorageDevice = types.StorageDevice;
const DeviceType = types.DeviceType;
const ImageType = types.ImageType;
const Image = types.Image;

const AppManager = @import("../../managers/AppManager.zig");
const EventManager = @import("../../managers/EventManager.zig").EventManagerSingleton;
const ComponentName = EventManager.ComponentName.DATA_FLASHER;

const ComponentFramework = @import("../framework/import/index.zig");
// const WorkerContext = @import("./WorkerContext.zig", .{});
const DeviceList = @import("../DeviceList/DeviceList.zig");
const FilePicker = @import("../FilePicker/FilePicker.zig");
const PrivilegedHelper = @import("../macos/PrivilegedHelper.zig");

const DataFlasherUI = @import("./DataFlasherUI.zig");

// This state is mutable and can be accessed from the main UI thread (draw/update)
// and a worker/event thread (handleEvent). Access must be guarded by state.lock().
const DataFlasherState = struct {
    isActive: bool = false,
    // owned by FilePicker
    imagePath: ?[:0]const u8 = null,
    // owned by DeviceList (via state ArrayList)
    device: ?StorageDevice = null,
    image: Image = .{},
    config: PrivilegedHelper.WriteConfig = .{},
};

const DataFlasher = @This();

const Component = ComponentFramework.Component;
const ComponentState = ComponentFramework.ComponentState(DataFlasherState);
pub const ComponentWorker = ComponentFramework.Worker(DataFlasherState);
const ComponentEvent = ComponentFramework.Event;

const EventResult = ComponentFramework.EventResult;

// Component-agnostic props
state: ComponentState,
component: ?Component = null,
worker: ?ComponentWorker = null,

// Component-specific, unique props
allocator: std.mem.Allocator,
ui: ?DataFlasherUI = null,

pub const Events = struct {
    //
    // Event: component's active state changed
    pub const onActiveStateChanged = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_active_state_changed"),
        struct { isActive: bool },
        struct {},
    );
};

pub const DEVICE_SIZE_CHECK = enum(u1) {
    SIZE_NOT_OK = 0,
    SIZE_OK = 1,
};

pub fn init(allocator: std.mem.Allocator) !DataFlasher {
    return DataFlasher{
        .state = ComponentState.init(DataFlasherState{}),
        .allocator = allocator,
    };
}

pub fn initComponent(self: *DataFlasher, parent: ?*Component) !void {
    if (self.component != null) return error.BaseComponentAlreadyInitialized;
    self.component = try Component.init(self, &ComponentImplementation.vtable, parent, self.allocator);
}

pub fn start(self: *DataFlasher) !void {
    if (self.component) |*component| {
        if (component.children != null) return error.ComponentAlreadyCalledStartBefore;

        if (!EventManager.subscribe(ComponentName, component)) return error.UnableToSubscribeToEventManager;

        Debug.log(.DEBUG, "DataFlasher: attempting to initialize children...", .{});

        component.children = std.ArrayList(Component).empty;

        self.ui = try DataFlasherUI.init(self.allocator, self);

        if (component.children) |*children| {
            if (self.ui) |*ui| {
                try ui.start();
                try children.append(self.allocator, ui.asComponent());
            }
        }

        Debug.log(.DEBUG, "DataFlasher: finished initializing children.", .{});
    }
}
pub fn update(self: *DataFlasher) !void {
    _ = self;
}
pub fn draw(self: *DataFlasher) !void {
    _ = self;
}
pub fn handleEvent(self: *DataFlasher, event: ComponentEvent) !EventResult {
    var eventResult = EventResult.init();

    return switch (event.hash) {
        DeviceList.Events.onDeviceListActiveStateChanged.Hash => try self.handleDeviceListActiveStateChanged(event),
        AppManager.Events.AppResetEvent.Hash => self.handleAppResetRequest(),
        else => return eventResult.fail(),
    };
}

pub fn dispatchComponentAction(self: *DataFlasher) void {
    Debug.log(.DEBUG, "DataFlasher: dispatching component action!", .{});

    AppManager.reportAction(.SelectionConfirmed) catch |err| {
        Debug.log(.ERROR, "DataFlasher: Unable to report 'SelectionConfirmed' action to AppManager, error: {any}", .{err});
        return;
    };

    // NOTE: Need to be careful with the memory access operations here since targetDisk (and obtained slice below)
    // live/s only within the scope of this function.
    var device: StorageDevice = undefined;
    var imagePath: [:0]const u8 = undefined;
    var imageType: ImageType = undefined;
    var writeConfig: PrivilegedHelper.WriteConfig = .{};

    {
        self.state.lock();
        defer self.state.unlock();
        device = self.state.data.device.?;
        imagePath = self.state.data.imagePath.?;
        imageType = self.state.data.image.type;
        writeConfig = self.state.data.config;
    }

    self.state.lock();
    errdefer self.state.unlock();

    if (imagePath.len > 3) {
        Debug.log(.DEBUG, "DataFlasher.dispatchComponentAction(): ISO path is confirmed as: {s}", .{imagePath});
    } else {
        Debug.log(.WARNING, "DataFlasher.dispatchComponentAction(): ISO path is NULL! Aborting...", .{});
        return;
    }

    if (device.getBsdNameSlice().len < 2) {
        Debug.log(.ERROR, "DataFlasher.dispatchComponentAction: unable to obtain the BSD Name of the target device.", .{});
        return;
    }

    Debug.log(.DEBUG, "DataFlasher.dispatchComponentAction(): target device is confirmed as: {s}", .{device.getBsdNameSlice()});

    self.state.unlock();

    // NOTE: Since the application's function is to perform a raw, block-for-block write of the image to the device,
    // it has no need to understand the internal filesystem structure of the ISO file. Therefore, the most secure approach
    // is to avoid parsing the ISO 9660 filesystem structure entirely.

    // const isoParserResult = ISOParser.parseIso(self.allocator, imagePath, device.size);
    //
    // if (isoParserResult != ISOParser.ISO_PARSER_RESULT.ISO_VALID) {
    //     var message: [*:0]const u8 = "";
    //
    //     switch (isoParserResult) {
    //         ISO_STATUS.INSUFFICIENT_DEVICE_CAPACITY => message = "The selected ISO file is larger than the capacity of the selected device.",
    //         ISO_STATUS.ISO_BOOT_OR_PVD_SECTOR_TOO_SHORT => message = "ISO appears corrupted: the Boot Record or the Primary Volume Descriptor are too short.",
    //         // NOTE: this may be OK and desirable if the ISO is not an OS. Consider allowing to proceed.
    //
    //         ISO_STATUS.ISO_INVALID_BOOT_INDICATOR => message = "ISO is not bootable, its boot indicator is set to non-bootable.",
    //         ISO_STATUS.ISO_INVALID_BOOT_SIGNATURE => message = "ISO appears corrupted: the boot signature is not correct.",
    //         ISO_STATUS.ISO_INVALID_REQUIRED_VOLUME_DESCRIPTORS => message = "ISO appears corrupted: unable to locate either the Primary Volume Descriptor or the Boot Record.",
    //         ISO_STATUS.ISO_SYSTEM_BLOCK_TOO_SHORT => message = "ISO appears corrputed: its system block is too short.",
    //         ISO_STATUS.UNABLE_TO_OPEN_ISO_FILE => message = "Freetracer is unable to open/read the selected ISO file. Please check permissions.",
    //         // TODO: implement remaining status codes
    //         else => message = "Unknown/unhandled ISO parser exception.",
    //     }
    //
    //     _ = osd.message(message, .{ .level = .err, .buttons = .ok });
    //
    //     return;
    // }

    // Send a request to write to target disk to the PrivilegedHelper Component, which will communicate with the Helper Tool
    const writeRequest = PrivilegedHelper.WriteRequest{
        .targetDisk = device.getBsdNameSlice(),
        .imagePath = imagePath,
        .device = device,
        .imageType = imageType,
        .config = writeConfig,
    };

    const flashResult = EventManager.signal(
        "privileged_helper",
        PrivilegedHelper.Events.onWriteImageToDeviceRequest.create(self.asComponentPtr(), &writeRequest),
    ) catch |err| errBlk: {
        Debug.log(.ERROR, "DataFlasher: Received an error dispatching a disk write request. Aborting... Error: {any}", .{err});
        break :errBlk EventResult{ .success = false, .validation = .FAILURE };
    };

    if (!flashResult.success) return;
}
pub fn deinit(self: *DataFlasher) void {
    _ = self;
}

pub const ComponentImplementation = ComponentFramework.ImplementComponent(DataFlasher);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;

fn queryAndSaveImageDetails(self: *DataFlasher) !void {
    //
    self.state.lock();
    defer self.state.unlock();

    var imageInfo: FilePicker.ImageQueryObject = .{};
    const data = FilePicker.Events.onImageDetailsQueried.Data{ .result = &imageInfo };

    const eventResult = try EventManager.signal("iso_file_picker", FilePicker.Events.onImageDetailsQueried.create(self.asComponentPtr(), &data));

    if (!eventResult.success) return error.DataFlasherFailedToQueryImagePath;

    if (imageInfo.imagePath.len < 2) {
        Debug.log(.ERROR, "DataFlasher received invalid ISO path: {s}", .{imageInfo.imagePath});
        return error.DataFlasherReceivedInvalidImagePath;
    }

    self.state.data.imagePath = imageInfo.imagePath;
    self.state.data.image = imageInfo.image;
    self.state.data.config.userForcedFlag = imageInfo.userForcedUnknownImage;
}

fn queryAndSaveSelectedDevice(self: *DataFlasher) !void {
    //
    self.state.lock();
    defer self.state.unlock();

    var query: DeviceList.DeviceQueryObject = .{};

    const deviceResult = try EventManager.signal("device_list", DeviceList.Events.onSelectedDeviceQueried.create(self.asComponentPtr(), &.{ .result = &query }));

    if (!deviceResult.success or query.selectedDevice == null) {
        return error.DataFlasherFailedToQuerySelectedDevice;
    }

    if (query.selectedDevice) |dev| self.state.data.device = dev;
}

fn handleDeviceListActiveStateChanged(self: *DataFlasher, event: ComponentEvent) !EventResult {
    var eventResult = EventResult.init();
    //

    Debug.log(.DEBUG, "DataFlasher: auth check: {any}", .{AppManager.authorizeAction(.ActivateDataFlasher)});
    if (!AppManager.authorizeAction(.ActivateDataFlasher)) return eventResult.fail();

    const data = DeviceList.Events.onDeviceListActiveStateChanged.getData(event) orelse return eventResult.fail();
    if (data.isActive == true) return eventResult.succeed();

    try self.queryAndSaveImageDetails();
    try self.queryAndSaveSelectedDevice();

    Debug.log(.DEBUG, "DataFlasher.handleEvent.onDeviceListActiveStateChanged: successfully obtained path and devices responses.", .{});

    // Update state in a block with shorter lifecycle
    {
        self.state.lock();
        defer self.state.unlock();
        self.state.data.isActive = true;

        std.debug.assert(self.state.data.imagePath != null and self.state.data.imagePath.?.len > 2);
        std.debug.assert(self.state.data.device != null and @TypeOf(self.state.data.device.?) == StorageDevice);

        Debug.log(.DEBUG, "DataFlasher received:\n\timagePath: {s}\n\tdevice: {s} ({any})\n", .{
            self.state.data.imagePath.?,
            self.state.data.device.?.getBsdNameSlice(),
            self.state.data.device.?.type,
        });
    }

    // Broadcast component's state change to active
    EventManager.broadcast(Events.onActiveStateChanged.create(self.asComponentPtr(), &.{ .isActive = true }));

    return eventResult.succeed();
}

pub const flashISOtoDeviceWrapper = struct {
    pub fn call(ctx: *anyopaque) void {
        var self = DataFlasher.asInstance(ctx);
        if (self.ui) |*ui| ui.flashRequested = true;
        self.dispatchComponentAction();
    }
};

pub fn toggleConfigFlagVerifyBytes(ctx: *anyopaque) void {
    var self: *DataFlasher = @ptrCast(@alignCast(ctx));
    self.state.lock();
    defer self.state.unlock();
    self.state.data.config.verifyBytesFlag = !self.state.data.config.verifyBytesFlag;
}

pub fn toggleConfigFlagEjectDevice(ctx: *anyopaque) void {
    var self: *DataFlasher = @ptrCast(@alignCast(ctx));
    self.state.lock();
    defer self.state.unlock();
    self.state.data.config.ejectDeviceFlag = !self.state.data.config.ejectDeviceFlag;
}

pub fn handleAppResetRequest(self: *DataFlasher) EventResult {
    var eventResult = EventResult.init();

    self.state.lock();
    defer self.state.unlock();

    self.state.data.isActive = false;
    self.state.data.device = null;
    self.state.data.imagePath = null;

    return eventResult.succeed();
}
