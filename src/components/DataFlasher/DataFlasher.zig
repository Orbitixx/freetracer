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
            const data = DeviceList.Events.onDeviceListActiveStateChanged.getData(event) orelse break :eventLoop;

            // If DeviceList Component is still active -- break out early.
            if (data.isActive == true) break :eventLoop;

            eventResult.validate(1);

            const isoResult = try EventManager.signal(
                "iso_file_picker",
                ISOFilePicker.Events.onISOFilePathQueried.create(self.asComponentPtr(), null),
            );

            if (!isoResult.success) return error.DataFlasherFailedToQueryISOPath;

            const deviceResult = try EventManager.signal(
                "device_list",
                DeviceList.Events.onSelectedDeviceQueried.create(self.asComponentPtr(), null),
            );

            if (!deviceResult.success) return error.DataFlasherFailedToQuerySelectedDevice;

            debug.print("\nDataFlasher.handleEvent.onDeviceListActiveStateChanged: successfully obtained path and devices responses.");

            // Update state in a block with shorter lifycycle
            {
                self.state.lock();
                defer self.state.unlock();
                self.state.data.isActive = data.isActive == false;

                if (isoResult.data) |isoData| {
                    const isoResponse: ISOFilePicker.Events.onISOFilePathQueried.Response = @as(
                        *ISOFilePicker.Events.onISOFilePathQueried.Response,
                        @ptrCast(@alignCast(isoData)),
                    ).*;

                    // const intermediatePath: [*:0]const u8 = @ptrCast(@alignCast(isoData));
                    // const len = std.mem.len(intermediatePath);
                    self.state.data.isoPath = isoResponse.isoPath;

                    // WARNING: cleaning up a pointer created on the heap by ISOFilePicker.handleEvent.onISOFilePathQueried.
                    self.allocator.destroy(@as(
                        *ISOFilePicker.Events.onISOFilePathQueried.Response,
                        @ptrCast(@alignCast(isoData)),
                    ));
                    //
                } else return error.DataFlasherReceivedNullISOPath;

                if (deviceResult.data) |deviceData| {
                    const deviceResponse: DeviceList.Events.onSelectedDeviceQueried.Response = @as(
                        *DeviceList.Events.onSelectedDeviceQueried.Response,
                        @ptrCast(@alignCast(deviceData)),
                    ).*;

                    self.state.data.device = deviceResponse.device;

                    // self.state.data.device = @as(*USBStorageDevice, @ptrCast(@alignCast(deviceData))).*;

                    // WARNING: cleaning up a pointer created on the heap by DeviceList.handleEvent.onSelectedDeviceQueried.
                    self.allocator.destroy(@as(
                        *DeviceList.Events.onSelectedDeviceQueried.Response,
                        @ptrCast(@alignCast(deviceData)),
                    ));
                    //
                } else return error.DataFlasherReceivedNullDevice;

                debug.printf("\n\n\nDataFlasher received:\n\tisoPath: {s}\n\tdevice: {s}\n\n\n", .{
                    self.state.data.isoPath.?,
                    self.state.data.device.?.bsdName,
                });
            }

            const setUIActiveEvent = Events.onActiveStateChanged.create(
                self.asComponentPtr(),
                &.{ .isActive = data.isActive == false },
            );

            EventManager.broadcast(setUIActiveEvent);
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
