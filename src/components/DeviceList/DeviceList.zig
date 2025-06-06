const std = @import("std");
const debug = @import("../../lib/util/debug.zig");

const ComponentFramework = @import("../framework/import/index.zig");
const WorkerContext = @import("./WorkerContext.zig");

const DeviceListState = struct {
    devices: ?u8 = null,
};
const DeviceListComponent = @This();

const Component = ComponentFramework.Component;
const ComponentState = ComponentFramework.ComponentState(DeviceListState);
pub const ComponentWorker = ComponentFramework.Worker(DeviceListState);
const ComponentEvent = ComponentFramework.Event;

const EventResult = ComponentFramework.EventResult;

// Component-agnostic props
state: ComponentState,
component: ?Component = null,
worker: ?ComponentWorker = null,

// Component-specific, unique props
allocator: std.mem.Allocator,

pub const Events = struct {
    pub const EventName = ComponentFramework.defineEvent("device_list.", struct {});
};

pub fn init(allocator: std.mem.Allocator) !DeviceListComponent {
    return .{
        .state = ComponentState.init(DeviceListState{}),
        .allocator = allocator,
    };
}

pub fn initComponent(self: *DeviceListComponent, parent: ?*Component) !void {
    if (self.component != null) return error.BaseComponentAlreadyInitialized;
    self.component = try Component.init(self, &ComponentImplementation.vtable, parent);
}

pub fn initWorker(self: *DeviceListComponent) !void {
    if (self.worker != null) return error.ComponentWorkerAlreadyInitialized;

    self.worker = ComponentWorker.init(
        self.allocator,
        &self.state,
        .{
            .run_fn = WorkerContext.workerRun,
            .run_context = self,
            .callback_fn = WorkerContext.workerCallback,
            .callback_context = self,
        },
        .{
            .onSameThreadAsCaller = false,
        },
    );
}

pub fn start(self: *DeviceListComponent) !void {
    // try self.initWorker();
    _ = self;
}

pub fn update(self: *DeviceListComponent) !void {
    self.checkAndJoinWorker();
}

pub fn draw(self: *DeviceListComponent) !void {
    _ = self;
}

pub fn handleEvent(self: *DeviceListComponent, event: ComponentEvent) !EventResult {
    _ = self;

    const eventResult = EventResult{
        .success = false,
        .validation = 0,
    };

    eventLoop: switch (event.hash) {
        //
        Events.EventName.Hash => {
            break :eventLoop;
        },

        else => {},
    }

    return eventResult;
}

pub fn deinit(self: *DeviceListComponent) void {
    _ = self;
}

fn discoverDevices(self: *DeviceListComponent) !void {
    debug.print("\nDeviceList: discovering connected devices...");

    if (self.worker) |*worker| {
        debug.print("\nDeviceList: starting Worker...");
        try worker.start();
    }
}

pub fn dispatchComponentAction(self: *DeviceListComponent) void {
    debug.print("\nDeviceList: dispatched component action...");

    self.discoverDevices() catch |err| {
        debug.printf("\nDeviceList Component caught error: {any}", .{err});
    };
}

pub fn checkAndJoinWorker(self: *DeviceListComponent) void {
    if (self.worker) |*worker| {
        if (worker.status == ComponentFramework.WorkerStatus.NEEDS_JOINING) {
            debug.print("\nDeviceList: Worker finished, needs joining...");
            worker.join();
            debug.print("\nDeviceList: Worker joined.");
        }
    }
}

const ComponentImplementation = ComponentFramework.ImplementComponent(DeviceListComponent);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;
