const std = @import("std");
const debug = @import("../../lib/util/debug.zig");

const MacOS = @import("../../modules/macos/MacOSTypes.zig");

const EventManager = @import("../../managers/EventManager.zig").EventManagerSingleton;

const ComponentFramework = @import("../framework/import/index.zig");
// const WorkerContext = @import("./WorkerContext.zig");

const DataFlasherUI = @import("./DataFlasherUI.zig");

const DataFlasherState = struct {
    isActive: bool = false,
    device: ?MacOS.USBStorageDevice = null,
};

const DataFlasher = @This();
const DeviceList = @import("../DeviceList/DeviceList.zig");

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

pub const Events = struct {};

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

        if (!EventManager.subscribe(component)) return error.UnableToSubscribeToEventManager;

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
    var eventResult = EventResult{
        .success = false,
        .validation = 0,
    };

    eventLoop: switch (event.hash) {
        //
        DeviceList.Events.onDeviceListActiveStateChanged.Hash => {
            const data = DeviceList.Events.onDeviceListActiveStateChanged.getData(event) orelse break :eventLoop;

            if (data.isActive == true) break :eventLoop;

            eventResult.validate(1);

            // Update state in a block with shorter lifycycle
            {
                self.state.lock();
                defer self.state.unlock();
                self.state.data.isActive = true;
            }

            const setUIActiveEvent = DataFlasherUI.Events.onActiveStateChanged.create(&self.component.?, &.{
                .isActive = data.isActive == false,
            });

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
