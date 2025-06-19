const std = @import("std");
const debug = @import("../../lib/util/debug.zig");

const MacOS = @import("../../modules/macos/MacOSTypes.zig");

const EventManager = @import("../../managers/EventManager.zig").EventManagerSingleton;

const ComponentFramework = @import("../framework/import/index.zig");
const WorkerContext = @import("./WorkerContext.zig");

const DeviceListUI = @import("./DeviceListUI.zig");

const DeviceListState = struct {
    devices: std.ArrayList(MacOS.USBStorageDevice),
    selectedDevice: ?MacOS.USBStorageDevice = null,
};

const DeviceListComponent = @This();
const ISOFilePickerUI = @import("../FilePicker/FilePickerUI.zig");

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
uiComponent: ?DeviceListUI = null,

pub const Events = struct {
    pub const onDiscoverDevicesEnd = ComponentFramework.defineEvent("device_list.on_discover_devices_end", struct {
        devices: std.ArrayList(MacOS.USBStorageDevice),
    });

    pub const onSelectedDeviceConfirmed = ComponentFramework.defineEvent("device_list.on_selected_device_confirmed", struct {});
};

pub fn init(allocator: std.mem.Allocator) !DeviceListComponent {
    return .{
        .state = ComponentState.init(DeviceListState{
            .devices = std.ArrayList(MacOS.USBStorageDevice).init(allocator),
        }),
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
    try self.initWorker();

    if (self.component) |*component| {
        if (component.children != null) return error.ComponentAlreadyCalledStartBefore;

        if (!EventManager.subscribe(component)) return error.UnableToSubscribeToEventManager;

        std.debug.print("\nDeviceList: attempting to initialize children...", .{});

        component.children = std.ArrayList(Component).init(self.allocator);

        self.uiComponent = try DeviceListUI.init(self.allocator, self);

        if (component.children) |*children| {
            if (self.uiComponent) |*uiComponent| {
                try uiComponent.start();
                try children.append(uiComponent.asComponent());
            }
        }

        std.debug.print("\nDeviceList: finished initializing children.", .{});
    }
}

pub fn update(self: *DeviceListComponent) !void {
    self.checkAndJoinWorker();
}

pub fn draw(self: *DeviceListComponent) !void {
    _ = self;
}

pub fn handleEvent(self: *DeviceListComponent, event: ComponentEvent) !EventResult {
    debug.printf("\nDeviceList: handleEvent() received an event: \"{s}\"", .{event.name});

    var eventResult = EventResult.init();

    eventLoop: switch (event.hash) {
        //
        ISOFilePickerUI.Events.ISOFilePickerActiveStateChanged.Hash => {
            const data = ISOFilePickerUI.Events.ISOFilePickerActiveStateChanged.getData(event) orelse break :eventLoop;
            eventResult.validate(1);

            if (!data.isActive) self.dispatchComponentAction();
        },

        Events.onDiscoverDevicesEnd.Hash => {
            const data = Events.onDiscoverDevicesEnd.getData(event) orelse break :eventLoop;
            eventResult.validate(1);

            var state = self.state.getData();
            state.devices = data.devices;

            const responseEvent = DeviceListUI.Events.onDevicesReadyToRender.create(&self.component.?, null);

            EventManager.broadcast(responseEvent);

            debug.print("\nDeviceList: Component processed USBStorageDevices from Worker");
        },

        else => {},
    }

    return eventResult;
}

pub fn deinit(self: *DeviceListComponent) void {
    self.state.lock();
    defer self.state.unlock();

    for (self.state.data.devices.items) |*device| {
        device.deinit();
    }

    self.state.data.devices.deinit();
}

fn discoverDevices(self: *DeviceListComponent) !void {
    debug.print("\nDeviceList: discovering connected devices...");

    if (self.worker) |*worker| {
        debug.print("\nDeviceList: starting Worker...");
        try worker.start();
    }
}

pub const dispatchComponentFinishedAction = struct {
    pub fn call(ctx: *anyopaque) void {
        const self = DeviceListComponent.asInstance(ctx);

        const event = DeviceListUI.Events.onDeviceListActiveStateChanged.create(&self.component.?, &.{ .isActive = false });
        EventManager.broadcast(event);

        debug.print("\nDeviceList: component action wrapper dispatch.");
    }
};

pub const SelectDeviceCallbackContext = struct {
    component: *DeviceListComponent,
    selectedDevice: MacOS.USBStorageDevice,
};

pub const selectDeviceActionWrapper = struct {
    pub fn call(ctx: *anyopaque) void {
        const context: *SelectDeviceCallbackContext = @ptrCast(@alignCast(ctx));

        context.component.state.lock();
        defer context.component.state.unlock();

        // TODO: ugly block, refactor
        if (context.component.state.data.selectedDevice) |currentlySelectedDevice| {
            // If the same device is already selected -- then unselect it
            context.component.state.data.selectedDevice = if (currentlySelectedDevice.serviceId == context.selectedDevice.serviceId) null else context.selectedDevice;
        } else {
            // Otherwise, assign a device
            context.component.state.data.selectedDevice = context.selectedDevice;
        }

        debug.printf(
            "\nDeviceList: selected device set to: {s}",
            .{
                if (context.component.state.data.selectedDevice != null) std.mem.sliceTo(context.selectedDevice.bsdName, 0x00) else "NULL",
            },
        );

        const event = DeviceListUI.Events.onSelectedDeviceNameChanged.create(&context.component.component.?, &.{ .selectedDevice = context.component.state.data.selectedDevice });
        EventManager.broadcast(event);
    }
};

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
