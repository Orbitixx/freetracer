const std = @import("std");
const debug = @import("../../lib/util/debug.zig");

const MacOS = @import("../../modules/macos/MacOSTypes.zig");

const EventManager = @import("../../managers/EventManager.zig").EventManagerSingleton;

const ComponentFramework = @import("../framework/import/index.zig");
// const WorkerContext = @import("./WorkerContext.zig");

const DataFlasherUI = @import("./DataFlasherUI.zig");

const DataFlasherState = struct {
    device: ?MacOS.USBStorageDevice = null,
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
    pub const onSomething = ComponentFramework.defineEvent("data_flasher.on_", struct {});
};

pub fn init(allocator: std.mem.Allocator) DataFlasher {
    return DataFlasher{
        .state = DataFlasherState{},
        .allocator = allocator,
    };
}

pub fn initComponent(self: *DataFlasher) !void {
    if (self.component != null) return error.BaseComponentAlreadyInitialized;
    self.component = try Component.init(self, &ComponentImplementation.vtable, null);
}

pub fn start(self: *DataFlasher) !void {
    _ = self;
}
pub fn update(self: *DataFlasher) !void {
    _ = self;
}
pub fn draw(self: *DataFlasher) !void {
    _ = self;
}
pub fn handleEvent(self: *DataFlasher, event: ComponentEvent) !EventResult {
    _ = self;

    var eventResult = EventResult{
        .success = false,
        .validation = 0,
    };

    eventLoop: switch (event.hash) {
        //
        Events.onSomething.Hash => {
            //
            const data = Events.onSomething.getData(event) orelse break :eventLoop;
            _ = data;

            eventResult.validate(1);
        },

        else => {},
    }

    return eventResult;
}
pub fn dispatchComponentAction(self: *DataFlasher) !void {
    _ = self;
}
pub fn deinit(self: *DataFlasher) void {
    _ = self;
}

pub const ComponentImplementation = ComponentFramework.ImplementComponent(DataFlasher);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;
