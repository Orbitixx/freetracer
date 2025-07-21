const std = @import("std");
const osd = @import("osdialog");
const Debug = @import("freetracer-lib").Debug;

const System = @import("../../lib/sys/system.zig");
const USBStorageDevice = System.USBStorageDevice;

const ISOParser = @import("../../modules/IsoParser.zig");
const ISO_STATUS = ISOParser.ISO_PARSER_RESULT;

const EventManager = @import("../../managers/EventManager.zig").EventManagerSingleton;

const ComponentFramework = @import("../framework/import/index.zig");
// const WorkerContext = @import("./WorkerContext.zig", .{});

const DataFlasherUI = @import("./DataFlasherUI.zig");

const DataFlasherState = struct {
    isActive: bool = false,
    isoPath: ?[:0]const u8 = null,
    device: ?USBStorageDevice = null,
};

const DataFlasher = @This();
const DeviceList = @import("../DeviceList/DeviceList.zig");
const ISOFilePicker = @import("../FilePicker/FilePicker.zig");
const PrivilegedHelper = @import("../macos/PrivilegedHelper.zig");

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
        "data_flasher.on_active_state_changed",
        struct {
            isActive: bool,
        },
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
    self.component = try Component.init(self, &ComponentImplementation.vtable, parent);
}

pub fn start(self: *DataFlasher) !void {
    if (self.component) |*component| {
        if (component.children != null) return error.ComponentAlreadyCalledStartBefore;

        if (!EventManager.subscribe("data_flasher", component)) return error.UnableToSubscribeToEventManager;

        Debug.log(.DEBUG, "DataFlasher: attempting to initialize children...", .{});

        component.children = std.ArrayList(Component).init(self.allocator);

        self.ui = try DataFlasherUI.init(self.allocator, self);

        if (component.children) |*children| {
            if (self.ui) |*ui| {
                try ui.start();
                try children.append(ui.asComponent());
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
    //
    var eventResult = EventResult.init();

    eventLoop: switch (event.hash) {
        //
        DeviceList.Events.onDeviceListActiveStateChanged.Hash => {
            //
            const data = DeviceList.Events.onDeviceListActiveStateChanged.getData(event) orelse break :eventLoop;

            // If DeviceList Component is active -- break out early.
            if (data.isActive == true) break :eventLoop;

            try self.queryAndSaveISOPath();
            try self.queryAndSaveSelectedDevice();

            Debug.log(.DEBUG, "DataFlasher.handleEvent.onDeviceListActiveStateChanged: successfully obtained path and devices responses.", .{});

            // Update state in a block with shorter lifecycle
            {
                self.state.lock();
                defer self.state.unlock();
                self.state.data.isActive = true;

                std.debug.assert(self.state.data.isoPath != null and self.state.data.isoPath.?.len > 2);
                std.debug.assert(self.state.data.device != null and @TypeOf(self.state.data.device.?) == USBStorageDevice);

                Debug.log(.DEBUG, "DataFlasher received:\n\tisoPath: {s}\n\tdevice: {s}\n", .{
                    self.state.data.isoPath.?,
                    self.state.data.device.?.getBsdNameSlice(),
                });
            }

            eventResult.validate(.SUCCESS);

            // Broadcast component's state change to active
            EventManager.broadcast(Events.onActiveStateChanged.create(self.asComponentPtr(), &.{ .isActive = true }));
        },

        else => {},
    }

    return eventResult;
}
pub fn dispatchComponentAction(self: *DataFlasher) void {
    Debug.log(.DEBUG, "DataFlasher: dispatching component action!", .{});

    // NOTE: Need to be careful with the memory access operations here since targetDisk (and obtained slice below)
    // live/s only within the scope of this function.
    var device: USBStorageDevice = undefined;
    var isoPath: [:0]const u8 = undefined;

    {
        self.state.lock();
        defer self.state.unlock();
        device = self.state.data.device.?;
        isoPath = self.state.data.isoPath.?;
    }

    self.state.lock();
    errdefer self.state.unlock();

    if (isoPath.len > 3) {
        Debug.log(.DEBUG, "DataFlasher.dispatchComponentAction(): ISO path is confirmed as: {s}", .{isoPath});
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

    const isoParserResult = ISOParser.parseIso(self.allocator, isoPath, device.size);

    if (isoParserResult != ISOParser.ISO_PARSER_RESULT.ISO_VALID) {
        var message: [*:0]const u8 = "";

        switch (isoParserResult) {
            ISO_STATUS.INSUFFICIENT_DEVICE_CAPACITY => message = "The selected ISO file is larger than the capacity of the selected device.",
            ISO_STATUS.ISO_BOOT_OR_PVD_SECTOR_TOO_SHORT => message = "ISO appears corrupted: the Boot Record or the Primary Volume Descriptor are too short.",
            // TODO: this may be OK and desirable if the ISO is not an OS. Consider allowing to proceed.
            ISO_STATUS.ISO_INVALID_BOOT_INDICATOR => message = "ISO is not bootable, its boot indicator is set to non-bootable.",
            ISO_STATUS.ISO_INVALID_BOOT_SIGNATURE => message = "ISO appears corrupted: the boot signature is not correct.",
            ISO_STATUS.ISO_INVALID_REQUIRED_VOLUME_DESCRIPTORS => message = "ISO appears corrupted: unable to locate either the Primary Volume Descriptor or the Boot Record.",
            ISO_STATUS.ISO_SYSTEM_BLOCK_TOO_SHORT => message = "ISO appears corrputed: its system block is too short.",
            ISO_STATUS.UNABLE_TO_OPEN_ISO_FILE => message = "Freetracer is unable to open/read the selected ISO file. Please check permissions.",
            // TODO: implement remaining status codes
            else => message = "Unknown/unhandled ISO parser exception.",
        }

        _ = osd.message(message, .{ .level = .err, .buttons = .ok });

        return;
    }

    // Send a request to unmount the target disk to the PrivilegedHelper Component, which will communicate with the Helper Tool
    const unmountResult = EventManager.signal(
        "privileged_helper",
        PrivilegedHelper.Events.onWriteISOToDeviceRequest.create(self.asComponentPtr(), &.{
            .targetDisk = device.getBsdNameSlice(),
            .isoPath = isoPath,
        }),
    ) catch |err| errBlk: {
        Debug.log(.ERROR, "DataFlasher: Received an error dispatching a disk unmount request. Aborting... Error: {any}", .{err});
        break :errBlk EventResult{ .success = false, .validation = .FAILURE };
    };

    if (!unmountResult.success) return;

    // const isoFilePath: []const u8 = self.state.data.isoPath.?;
    // const device: USBStorageDevice = self.state.data.device.?;
    //
    // self.state.unlock();
    //
    // ISOParser.parseIso(self.allocator, isoFilePath) catch |err| {
    //     Debug.log(.DEBUG, "DataFlasher.dispatchComponentAction(): ISOParser.parseIso returned an error: {any}", .{err});
    //     return;
    // };

    // const devicePathPrefix: [:0]const u8 = "/dev/";
    // const deviceBsdName = device.getBsdNameSlice();
    //
    // const finalDevicePath = self.allocator.alloc(u8, devicePathPrefix.len + deviceBsdName.len) catch |err| {
    //     Debug.log(.DEBUG, "DataFlasher.dispatchComponentAction(): failed to allocate memory for device path. Error: {any}", .{err});
    //     return;
    // };
    // defer self.allocator.free(finalDevicePath);
    //
    // @memcpy(finalDevicePath[0..devicePathPrefix.len], devicePathPrefix);
    // @memcpy(finalDevicePath[devicePathPrefix.len..], deviceBsdName);
    //
    // std.debug.assert(finalDevicePath.len == devicePathPrefix.len + deviceBsdName.len);
    //
    // Debug.log(.DEBUG, "DataFlasher: final device path is: {s}", .{finalDevicePath});

}
pub fn deinit(self: *DataFlasher) void {
    _ = self;
}

pub const ComponentImplementation = ComponentFramework.ImplementComponent(DataFlasher);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;

fn queryAndSaveISOPath(self: *DataFlasher) !void {
    //
    self.state.lock();
    defer self.state.unlock();

    const isoResult = try EventManager.signal("iso_file_picker", ISOFilePicker.Events.onISOFilePathQueried.create(self.asComponentPtr(), null));

    if (isoResult.data) |isoData| {
        //
        const isoDataPtr: *ISOFilePicker.Events.onISOFilePathQueried.Response = @ptrCast(@alignCast(isoData));

        // Destroy a heap-allocated isoResult.data pointer.
        // Defer is required in order to clean up irrespective of function's outcome (i.e. success or error)
        // WARNING: cleaning up a pointer created on the heap by ISOFilePicker.handleEvent.onISOFilePathQueried.
        defer self.allocator.destroy(isoDataPtr);

        const isoResponse: ISOFilePicker.Events.onISOFilePathQueried.Response = isoDataPtr.*;

        if (!isoResult.success) return error.DataFlasherFailedToQueryISOPath;

        if (isoResponse.isoPath.len < 2) {
            Debug.log(.ERROR, "DataFlasher received invalid ISO path: {s}", .{isoResponse.isoPath});
            return error.DataFlasherReceivedInvalidISOPath;
        }

        self.state.data.isoPath = isoResponse.isoPath;
    } else return error.DataFlasherReceivedNullISOPath;
}

fn queryAndSaveSelectedDevice(self: *DataFlasher) !void {
    //
    self.state.lock();
    defer self.state.unlock();

    const deviceResult = try EventManager.signal("device_list", DeviceList.Events.onSelectedDeviceQueried.create(self.asComponentPtr(), null));

    if (deviceResult.data) |deviceData| {
        //
        const deviceDataPtr: *DeviceList.Events.onSelectedDeviceQueried.Response = @ptrCast(@alignCast(deviceData));

        // Destroy a heap-allocated deviceResult.data pointer.
        // Defer is required in order to clean up irrespective of function's outcome (i.e. success or error)
        // WARNING: cleaning up a pointer created on the heap by DeviceList.handleEvent.onSelectedDeviceQueried.
        defer self.allocator.destroy(deviceDataPtr);

        if (!deviceResult.success) return error.DataFlasherFailedToQuerySelectedDevice;

        const deviceResponse: DeviceList.Events.onSelectedDeviceQueried.Response = deviceDataPtr.*;

        // deviceResponse.device is not an optional, it cannot be a null device
        self.state.data.device = deviceResponse.device;
    } else return error.DataFlasherReceivedNullDevice;
}

pub const flashISOtoDeviceWrapper = struct {
    pub fn call(ctx: *anyopaque) void {
        var self = DataFlasher.asInstance(ctx);
        self.dispatchComponentAction();
    }
};
