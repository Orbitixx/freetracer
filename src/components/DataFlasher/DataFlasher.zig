const std = @import("std");
const debug = @import("../../lib/util/debug.zig");

const System = @import("../../lib/sys/system.zig");
const USBStorageDevice = System.USBStorageDevice;

const MacOS = @import("../../modules/macos/MacOSTypes.zig");

const EventManager = @import("../../managers/EventManager.zig").EventManagerSingleton;

const ComponentFramework = @import("../framework/import/index.zig");
// const WorkerContext = @import("./WorkerContext.zig");

const DataFlasherUI = @import("./DataFlasherUI.zig");

const DataFlasherState = struct {
    isActive: bool = false,
    isoPath: ?[:0]const u8 = null,
    device: ?USBStorageDevice = null,
};

const DataFlasher = @This();
const DeviceList = @import("../DeviceList/DeviceList.zig");
const ISOFilePicker = @import("../FilePicker/FilePicker.zig");

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

        std.debug.print("\nDataFlasher: attempting to initialize children...", .{});

        component.children = std.ArrayList(Component).init(self.allocator);

        self.ui = try DataFlasherUI.init(self.allocator, self);

        if (component.children) |*children| {
            if (self.ui) |*ui| {
                try ui.start();
                try children.append(ui.asComponent());
            }
        }

        std.debug.print("\nDataFlasher: finished initializing children.", .{});
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

            debug.print("\nDataFlasher.handleEvent.onDeviceListActiveStateChanged: successfully obtained path and devices responses.");

            // Update state in a block with shorter lifecycle
            {
                self.state.lock();
                defer self.state.unlock();
                self.state.data.isActive = true;

                std.debug.assert(self.state.data.isoPath != null and self.state.data.isoPath.?.len > 2);
                std.debug.assert(self.state.data.device != null and @TypeOf(self.state.data.device.?) == USBStorageDevice);

                debug.printf("\nDataFlasher received:\n\tisoPath: {s}\n\tdevice: {s}\n", .{
                    self.state.data.isoPath.?,
                    self.state.data.device.?.getBsdNameSlice(),
                });
            }

            eventResult.validate(1);

            // Broadcast component's state change to active
            EventManager.broadcast(Events.onActiveStateChanged.create(self.asComponentPtr(), &.{ .isActive = true }));
        },

        else => {},
    }

    return eventResult;
}
pub fn dispatchComponentAction(self: *DataFlasher) void {
    _ = self;
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
            debug.printf("\nERROR: DataFlasher received invalid ISO path: {s}", .{isoResponse.isoPath});
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
