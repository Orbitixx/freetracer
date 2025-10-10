// DeviceList orchestrates discovery and selection of removable storage devices, mediating between the
// background worker that talks to the helper via IOKit and the UI subcomponent that renders choices.
// It subscribes to component events (activation, refresh, selection queries) and broadcasts updates to
// downstream consumers while owning the allocator-backed device list shared with the UI layer.
// ----------------------------------------------------------------------------------------------------
const std = @import("std");
const freetracer_lib = @import("freetracer-lib");
const types = freetracer_lib.types;
const Debug = freetracer_lib.Debug;

const StorageDevice = types.StorageDevice;

const AppManager = @import("../../managers/AppManager.zig");
const EventManager = @import("../../managers/EventManager.zig").EventManagerSingleton;
const ComponentName = EventManager.ComponentName.DEVICE_LIST;

const ComponentFramework = @import("../framework/import/index.zig");
const WorkerContext = @import("./WorkerContext.zig");

const DeviceListUI = @import("./DeviceListUI.zig");

pub const DeviceQueryObject = struct {
    selectedDevice: ?StorageDevice = null,
};

// This state is mutable and can be accessed from the main UI thread (draw/update)
// and a worker/event thread (handleEvent). Access must be guarded by state.lock().
const DeviceListState = struct {
    isActive: bool = false,
    devices: std.ArrayList(StorageDevice),
    selectedDevice: ?StorageDevice = null,
};

const DeviceListComponent = @This();
const ISOFilePicker = @import("../FilePicker/FilePicker.zig");

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

// Events belonging to this component
pub const Events = struct {
    // Event: state.data.isActive property changed
    pub const onDeviceListActiveStateChanged = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_active_state_changed"),
        struct { isActive: bool },
        struct {},
    );

    // Event: Worker finished discovering storage devices
    pub const onDiscoverDevicesEnd = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_discover_devices_end"),
        struct { devices: std.ArrayList(StorageDevice) },
        struct {},
    );

    pub const onDevicesCleanup = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_devices_cleanup"),
        struct {},
        struct {},
    );

    // Event: User selected a target storage device to be written
    pub const onSelectedDeviceConfirmed = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_selected_device_confirmed"),
        struct {},
        struct {},
    );

    // Event: User completed interacting with this component (e.g. clicked "Next")
    pub const onFinishedComponentInteraction = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_finished_component_interaction"),
        struct {},
        struct {},
    );

    // Event: Another component requested info about selected device
    pub const onSelectedDeviceQueried = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_selected_device_queried"),
        struct { result: *DeviceQueryObject },
        struct { device: StorageDevice },
    );
};

/// Initializes the DeviceList component with an empty device collection backed by `allocator`.
pub fn init(allocator: std.mem.Allocator) !DeviceListComponent {
    return .{
        .state = ComponentState.init(DeviceListState{
            .devices = std.ArrayList(StorageDevice).empty,
        }),
        .allocator = allocator,
    };
}

/// Binds this component instance into the `Component` interface.
pub fn initComponent(self: *DeviceListComponent, parent: ?*Component) !void {
    if (self.component != null) return error.BaseComponentAlreadyInitialized;
    self.component = try Component.init(self, &ComponentImplementation.vtable, parent, self.allocator);
}

/// Prepares the background worker responsible for enumerating storage devices.
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

/// Starts the component, creating UI children and registering for DeviceList events.
pub fn start(self: *DeviceListComponent) !void {
    try self.initWorker();

    if (self.component) |*component| {
        if (component.children != null) return error.ComponentAlreadyCalledStartBefore;

        if (!EventManager.subscribe(ComponentName, component)) return error.UnableToSubscribeToEventManager;

        Debug.log(.DEBUG, "DeviceList: attempting to initialize children...", .{});

        component.children = std.ArrayList(Component).empty;

        self.uiComponent = try DeviceListUI.init(self.allocator, self);

        if (component.children) |*children| {
            if (self.uiComponent) |*uiComponent| {
                try uiComponent.start();
                try children.append(self.allocator, uiComponent.asComponent());
            }
        }

        Debug.log(.DEBUG, "DeviceList: finished initializing children.", .{});
    }
}

pub fn update(self: *DeviceListComponent) !void {
    self.checkAndJoinWorker();
}

pub fn draw(self: *DeviceListComponent) !void {
    _ = self;
}

pub fn handleEvent(self: *DeviceListComponent, event: ComponentEvent) !EventResult {
    Debug.log(.INFO, "DeviceList: handleEvent() received an event: \"{s}\"", .{event.name});

    var eventResult = EventResult.init();

    return switch (event.hash) {
        ISOFilePicker.Events.onActiveStateChanged.Hash => try self.handlePrecedingComponentStateChange(event),
        Events.onDiscoverDevicesEnd.Hash => try self.handleDevicesDiscovered(event),
        Events.onFinishedComponentInteraction.Hash => try self.handleFinishedInteraction(),
        Events.onSelectedDeviceQueried.Hash => try self.handleSelectedDeviceQuery(event),
        else => eventResult.fail(),
    };
}

pub fn deinit(self: *DeviceListComponent) void {
    self.state.lock();
    defer self.state.unlock();

    self.state.data.devices.deinit(self.allocator);
}

pub fn dispatchComponentAction(self: *DeviceListComponent) void {
    Debug.log(.DEBUG, "DeviceList: dispatched component action...", .{});

    self.discoverDevices() catch |err| {
        Debug.log(.ERROR, "DeviceList Component caught error: {any}", .{err});
    };
}

const ComponentImplementation = ComponentFramework.ImplementComponent(DeviceListComponent);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;

pub fn checkAndJoinWorker(self: *DeviceListComponent) void {
    if (self.worker) |*worker| {
        if (worker.status == ComponentFramework.WorkerStatus.NEEDS_JOINING) {
            Debug.log(.DEBUG, "DeviceList: Worker finished, needs joining...", .{});
            worker.join();
            Debug.log(.DEBUG, "DeviceList: Worker joined.", .{});
        }
    }
}

/// Resets cached device state, requests UI cleanup, and schedules the background worker to rescan.
fn discoverDevices(self: *DeviceListComponent) !void {
    Debug.log(.DEBUG, "DeviceList: discovering connected devices...", .{});

    self.state.lock();
    const hadDevices = self.state.data.devices.items.len > 0;
    self.state.data.devices.clearAndFree(self.allocator);
    self.state.data.selectedDevice = null;
    self.state.unlock();

    // Important memory cleanup for the refresh devices functionality
    if (hadDevices) {
        const eventResult = try EventManager.signal("device_list_ui", Events.onDevicesCleanup.create(self.asComponentPtr(), null));

        if (!eventResult.success) return error.DeviceListCouldNotCleanUpDevicesBeforeDiscoveringNewOnes;
    }

    Debug.log(.DEBUG, "DeviceList: starting Worker...", .{});

    // Start the worker once the cleanup is complete
    if (self.worker) |*worker| try worker.start() else {
        Debug.log(.ERROR, "DeviceList: attempted to discover devices without initializing worker.", .{});
        return error.ComponentWorkerNotInitialized;
    }
}

pub const dispatchRefreshDevicesAction = struct {
    pub fn call(ctx: *anyopaque) void {
        const self = DeviceListComponent.asInstance(ctx);
        self.refreshDevices();
    }
};

pub const dispatchComponentFinishedAction = struct {
    pub fn call(ctx: *anyopaque) void {
        const self = DeviceListComponent.asInstance(ctx);

        Debug.log(.DEBUG, "DeviceList: component action wrapper dispatch.", .{});

        _ = self.handleEvent(Events.onFinishedComponentInteraction.create(self.asComponentPtr(), null)) catch |err| {
            Debug.log(.ERROR, "DeviceList.dispatchComponentAction: ERROR - {any}", .{err});
            std.debug.panic("DeviceList.dispatchComponentAction failed. May result in unpredictable behavior, please report. Error: {any}", .{err});
        };
    }
};

pub const SelectDeviceCallbackContext = struct {
    component: *DeviceListComponent,
    selectedDevice: StorageDevice,
};

pub const selectDeviceActionWrapper = struct {
    pub fn call(ctx: *anyopaque) void {
        const context: *SelectDeviceCallbackContext = @ptrCast(@alignCast(ctx));

        const new_selection = context.component.toggleSelectedDevice(context.selectedDevice);
        context.component.publishSelectionChanged(new_selection);

        //     var isSameUnselected: bool = false;
        //
        //     context.component.state.lock();
        //
        //     // TODO: ugly block, refactor
        //     if (context.component.state.data.selectedDevice) |currentlySelectedDevice| {
        //         // If the same device is already selected -- then unselect it
        //         if (currentlySelectedDevice.serviceId == context.selectedDevice.serviceId) {
        //             context.component.state.data.selectedDevice = null;
        //             isSameUnselected = true;
        //         } else context.component.state.data.selectedDevice = context.selectedDevice;
        //     } else {
        //         // Otherwise, assign a device
        //         context.component.state.data.selectedDevice = context.selectedDevice;
        //     }
        //
        //     Debug.log(
        //         .INFO,
        //         "DeviceList: selected device set to: {s}",
        //         .{
        //             if (context.component.state.data.selectedDevice != null) context.selectedDevice.getBsdNameSlice() else "NULL",
        //         },
        //     );
        //
        //     context.component.state.unlock();
        //
        //     // TODO: CHECK: changed context.state.data.selectedDevice to context.selectedDevice -- probably not right but fixing another issue
        //     const event = DeviceListUI.Events.onSelectedDeviceNameChanged.create(
        //         &context.component.component.?,
        //         &.{ .selectedDevice = if (isSameUnselected) null else context.selectedDevice },
        //     );
        //     _ = EventManager.broadcast(event);
    }
};

fn handlePrecedingComponentStateChange(self: *DeviceListComponent, event: ComponentEvent) !EventResult {
    var eventResult = EventResult.init();
    const data = ISOFilePicker.Events.onActiveStateChanged.getData(event) orelse return eventResult.fail();

    if (data.isActive) return eventResult.succeed();

    Debug.log(.DEBUG, "Requesting Device List activation, auth: {any}", .{AppManager.authorizeAction(.ActivateDeviceList)});
    if (!AppManager.authorizeAction(.ActivateDeviceList)) return eventResult.fail();

    self.state.lock();
    self.state.data.isActive = true;
    self.state.unlock();

    EventManager.broadcast(Events.onDeviceListActiveStateChanged.create(self.asComponentPtr(), &.{ .isActive = true }));
    self.dispatchComponentAction();

    return eventResult.succeed();
}

fn handleDevicesDiscovered(self: *DeviceListComponent, event: ComponentEvent) !EventResult {
    var eventResult = EventResult.init();
    const data = Events.onDiscoverDevicesEnd.getData(event) orelse return eventResult.fail();

    self.state.lock();
    self.state.data.devices = data.devices;
    self.state.data.selectedDevice = null;
    self.state.unlock();

    EventManager.broadcast(DeviceListUI.Events.onDevicesReadyToRender.create(self.asComponentPtr(), null));
    Debug.log(.DEBUG, "DeviceList: Component processed StorageDevices from Worker", .{});

    return eventResult.succeed();
}

fn handleFinishedInteraction(self: *DeviceListComponent) !EventResult {
    var eventResult = EventResult.init();

    self.state.lock();

    if (self.state.data.selectedDevice == null) {
        self.state.unlock();
        Debug.log(
            .WARNING,
            "DeviceList.handleEvent.onFinishedComponentInteraction: WARNING - selectedDevice is NULL.",
            .{},
        );
        return eventResult.fail();
    }

    self.state.data.isActive = false;
    self.state.unlock();

    try AppManager.reportAction(.DeviceSelected);

    var responseEvent = Events.onDeviceListActiveStateChanged.create(
        self.asComponentPtr(),
        &.{ .isActive = false },
    );

    responseEvent.flags.overrideNotifySelfOnSelfOrigin = true;

    Debug.log(.DEBUG, "DeviceList: broadcasting state changed to INACTIVE.", .{});
    EventManager.broadcast(responseEvent);

    return eventResult.succeed();
}

fn handleSelectedDeviceQuery(self: *DeviceListComponent, event: ComponentEvent) !EventResult {
    var eventResult = EventResult.init();
    const data = Events.onSelectedDeviceQueried.getData(event) orelse return eventResult.fail();

    self.state.lock();
    const selected = self.state.data.selectedDevice;
    self.state.unlock();

    data.result.* = .{ .selectedDevice = selected };

    if (selected == null) {
        Debug.log(.WARNING, "DeviceList: Selected device query failed; no device chosen.", .{});
        return eventResult.fail();
    }

    return eventResult.succeed();
}

/// Toggles the selection state for `device`, returning the new selection (or null when deselected).
fn toggleSelectedDevice(self: *DeviceListComponent, device: StorageDevice) ?StorageDevice {
    self.state.lock();

    if (self.state.data.selectedDevice) |current| {
        if (current.serviceId == device.serviceId) {
            self.state.data.selectedDevice = null;
        } else {
            self.state.data.selectedDevice = device;
        }
    } else {
        self.state.data.selectedDevice = device;
    }

    const selection = self.state.data.selectedDevice;
    self.state.unlock();

    Debug.log(
        .INFO,
        "DeviceList: selected device set to: {s}",
        .{if (selection) |selected_device| selected_device.getBsdNameSlice() else "NULL"},
    );

    return selection;
}

/// Notifies UI listeners that the selected device has changed.
fn publishSelectionChanged(self: *DeviceListComponent, selection: ?StorageDevice) void {
    _ = EventManager.broadcast(DeviceListUI.Events.onSelectedDeviceNameChanged.create(self.asComponentPtr(), &.{ .selectedDevice = selection }));
}

/// Requests a fresh device scan, clearing any existing devices.
fn refreshDevices(self: *DeviceListComponent) void {
    if (self.uiComponent) |*ui| {
        ui.clearDeviceCheckboxes();
    }

    self.dispatchComponentAction();
}
