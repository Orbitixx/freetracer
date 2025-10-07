// DeviceListUI renders the interactive list of removable storage devices and coordinates
// selection state between the GUI component tree and the backing DeviceList model.
// It subscribes to DeviceList and UI framework events, updates raylib primitives for
// display, and emits callbacks that ultimately trigger helper-side disk operations.
// Memory ownership stays within this component except for checkbox callback contexts,
// which are allocated/freed via the component allocator.
// --------------------------------------------------------------------------------------

const std = @import("std");
const rl = @import("raylib");
const freetracer_lib = @import("freetracer-lib");
const Debug = freetracer_lib.Debug;
const types = freetracer_lib.types;

const Character = freetracer_lib.constants.Character;
const StorageDevice = types.StorageDevice;

const AppConfig = @import("../../config.zig");

const WindowManager = @import("../../managers/WindowManager.zig").WindowManagerSingleton;
const winRelX = WindowManager.relW;
const winRelY = WindowManager.relH;

const EventManager = @import("../../managers/EventManager.zig").EventManagerSingleton;
pub const ComponentName = EventManager.ComponentName.DEVICE_LIST_UI;

const DeviceList = @import("./DeviceList.zig");
const ISOFilePicker = @import("../FilePicker/FilePicker.zig");
const ISOFilePickerUI = @import("../FilePicker/FilePickerUI.zig");

const ComponentFramework = @import("../framework/import/index.zig");
const Component = ComponentFramework.Component;
const ComponentEvent = ComponentFramework.Event;
const EventResult = ComponentFramework.EventResult;

const UIFramework = @import("../ui/import/index.zig");
const Button = UIFramework.Button;
const Checkbox = UIFramework.Checkbox;
const Rectangle = UIFramework.Primitives.Rectangle;
const Text = UIFramework.Primitives.Text;
const Transform = UIFramework.Primitives.Transform;
const Texture = UIFramework.Primitives.Texture;
const UI = UIFramework.utils;

const Styles = UIFramework.Styles;
const Color = UIFramework.Styles.Color;

pub const DeviceListUIState = struct {
    isActive: bool = false,
    devices: *std.ArrayList(StorageDevice),
    selectedDevice: ?StorageDevice = null,
};

pub const ComponentState = ComponentFramework.ComponentState(DeviceListUIState);

const DeviceListUI = @This();

const COMPONENT_UI_GAP: f32 = 20;
const MAX_DISPLAY_STRING_LENGTH: usize = 254;
const MAX_SELECTED_DEVICE_NAME_LEN: usize = 12;

const kStringDeviceListNoDeviceSelected = "No device selected...";

// Component-agnostic props
state: ComponentState,
component: ?Component = null,

// Component-specific, unique props
allocator: std.mem.Allocator,
parent: *DeviceList,
deviceCheckboxes: std.ArrayList(Checkbox),
bgRect: Rectangle = undefined,
headerLabel: Text = undefined,
moduleImg: Texture = undefined,
nextButton: Button = undefined,
deviceNameLabel: Text = undefined,
noDevicesLabel: Text = undefined,
refreshDevicesButton: Button = undefined,
selectedDeviceNameBuf: [MAX_DISPLAY_STRING_LENGTH:0]u8 = undefined,

const BgRectParams = struct {
    width: f32,
    color: rl.Color,
    borderColor: rl.Color,
};

pub const Events = struct {
    //
    pub const onDeviceListUIActiveStateChanged = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_active_state_changed"),
        struct { isActive: bool },
        struct {},
    );

    pub const onDevicesReadyToRender = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_devices_ready_to_render"),
        struct {},
        struct {},
    );

    pub const onSelectedDeviceNameChanged = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_device_name_changed"),
        struct {
            // Not authoritative data; copy only -- use parent for authoritative.
            selectedDevice: ?StorageDevice,
        },
        struct {},
    );

    pub const onUITransformQueried = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_ui_transform_queried"),
        struct { result: *UIFramework.Primitives.Transform },
        struct {},
    );
};

// Creates and returns an instance of DeviceListUI component
pub fn init(allocator: std.mem.Allocator, parent: *DeviceList) !DeviceListUI {
    Debug.log(.DEBUG, "DeviceListUI: start() called.", .{});

    parent.state.lock();
    defer parent.state.unlock();

    return DeviceListUI{
        .allocator = allocator,
        .state = ComponentState.init(DeviceListUIState{
            .devices = &parent.state.data.devices,
        }),
        .parent = parent,
        .deviceCheckboxes = std.ArrayList(Checkbox).empty,
        .selectedDeviceNameBuf = std.mem.zeroes([MAX_DISPLAY_STRING_LENGTH:0]u8),
    };
}

// Parent param is technically not required here, since the component already stores it as a property,
// however, the param is preserved for convention's sake.
pub fn initComponent(self: *DeviceListUI, parent: ?*Component) !void {
    if (self.component != null) return error.BaseComponentAlreadyInitialized;
    self.component = try Component.init(self, &ComponentImplementation.vtable, parent, self.allocator);
}

/// Called once per component lifetime to wire event subscriptions and initial draw state.
pub fn start(self: *DeviceListUI) !void {
    Debug.log(.DEBUG, "DeviceListUI: component start() called.", .{});

    try self.initComponent(&self.parent.component.?);
    try self.subscribeToEvents();

    self.initBgRect();
    try self.initNextBtn();
    self.initRefreshDevicesBtn();
    self.initHeaderLabel();
    self.initModuleCoverTexture();
    // Must come after initModuleCoverTexture() as deviceNameLabel references its position
    self.initDeviceNameLabel();

    self.noDevicesLabel = Text.init("No external devices found...", .{ .x = 0, .y = 0 }, .{ .fontSize = 14 });

    Debug.log(.DEBUG, "DeviceListUI: component start() finished.", .{});
}

pub fn handleEvent(self: *DeviceListUI, event: ComponentEvent) !EventResult {
    Debug.log(.INFO, "DeviceListUI: handleEvent() received an event: \"{s}\"", .{event.name});

    var eventResult = EventResult.init();

    return switch (event.hash) {
        DeviceList.Events.onDeviceListActiveStateChanged.Hash => try self.handleOnDeviceListActiveStateChanged(event),
        DeviceList.Events.onDevicesCleanup.Hash => try self.handleOnDevicesCleanup(),
        Events.onUITransformQueried.Hash => try self.handleOnUITransformQueried(event),
        Events.onDevicesReadyToRender.Hash => try self.handleOnDevicesReadyToRender(),
        Events.onSelectedDeviceNameChanged.Hash => try self.handleOnSelectedDeviceNameChanged(event),
        else => return eventResult.fail(),
    };
}

pub fn update(self: *DeviceListUI) !void {
    self.state.lock();
    const isActive = self.state.data.isActive;
    self.state.unlock();

    if (!isActive) return;

    for (self.deviceCheckboxes.items) |*checkbox| {
        try checkbox.update();
    }

    try self.refreshDevicesButton.update();
    try self.nextButton.update();
}

pub fn draw(self: *DeviceListUI) !void {
    self.state.lock();
    const isActive = self.state.data.isActive;
    self.state.unlock();

    self.bgRect.draw();
    self.headerLabel.draw();

    if (isActive) try self.drawActive() else try self.drawInactive();
}

pub fn deinit(self: *DeviceListUI) void {
    self.destroyDeviceCheckboxContexts();
    self.deviceCheckboxes.deinit(self.allocator);
}

pub fn dispatchComponentAction(self: *DeviceListUI) void {
    _ = self;
}

pub const ComponentImplementation = ComponentFramework.ImplementComponent(DeviceListUI);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;

fn subscribeToEvents(self: *DeviceListUI) !void {
    if (self.component) |*component| {
        if (!EventManager.subscribe(ComponentName, component)) return error.UnableToSubscribeToEventManager;
    } else return error.UnableToSubscribeToEventManager;
}

fn initBgRect(self: *DeviceListUI) void {
    // Obtain previous UI section's Transform
    const filePickerBgRectTransform = UI.queryComponentTransform(ISOFilePickerUI);

    self.bgRect = Rectangle{
        .transform = .{
            .x = filePickerBgRectTransform.x + filePickerBgRectTransform.w + AppConfig.APP_UI_MODULE_GAP_X,
            .y = winRelY(AppConfig.APP_UI_MODULE_PANEL_Y),
            .w = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_INACTIVE),
            .h = winRelY(AppConfig.APP_UI_MODULE_PANEL_HEIGHT),
        },
        .style = .{
            .color = Styles.Color.darkBlueGray,
            .borderStyle = .{ .color = Styles.Color.darkBlueGray },
        },
        .rounded = true,
        .bordered = true,
    };
}

fn initNextBtn(self: *DeviceListUI) !void {
    self.nextButton = Button.init("Next", null, self.bgRect.transform.getPosition(), .Primary, .{
        .context = self.parent,
        .function = DeviceList.dispatchComponentFinishedAction.call,
    }, self.allocator);

    self.nextButton.setEnabled(false);

    try self.nextButton.start();

    self.nextButton.setPosition(.{
        .x = self.bgRect.transform.relX(0.5) - @divTrunc(self.nextButton.rect.transform.getWidth(), 2),
        .y = self.bgRect.transform.relY(0.9) - @divTrunc(self.nextButton.rect.transform.getHeight(), 2),
    });

    self.nextButton.rect.rounded = true;
}

fn initRefreshDevicesBtn(self: *DeviceListUI) void {
    self.refreshDevicesButton = Button.init("", .RELOAD_ICON, self.bgRect.transform.getPosition(), .Primary, .{
        .context = self.parent,
        .function = refreshDevices.call,
    }, self.allocator);

    self.refreshDevicesButton.rect.rounded = true;
}

fn initHeaderLabel(self: *DeviceListUI) void {
    self.headerLabel = Text.init("device", .{
        .x = self.bgRect.transform.x + 12,
        .y = self.bgRect.transform.relY(0.01),
    }, .{
        .font = .JERSEY10_REGULAR,
        .fontSize = 34,
        .textColor = Styles.Color.white,
    });
}

fn initModuleCoverTexture(self: *DeviceListUI) void {
    self.moduleImg = Texture.init(.USB_IMAGE, .{ .x = 0, .y = 0 });
    self.moduleImg.transform.scale = 0.5;
    self.moduleImg.transform.x = self.bgRect.transform.relX(0.5) - self.moduleImg.transform.getWidth() / 2;
    self.moduleImg.transform.y = self.bgRect.transform.relY(0.5) - self.moduleImg.transform.getHeight() / 2;
    self.moduleImg.tint = .{ .r = 255, .g = 255, .b = 255, .a = 150 };
}

fn initDeviceNameLabel(self: *DeviceListUI) void {
    self.deviceNameLabel = Text.init("", .{ .x = 0, .y = 0 }, .{ .fontSize = 14 });
    self.deviceNameLabel.transform.x = self.bgRect.transform.relX(0.5) - self.deviceNameLabel.getDimensions().width / 2;
    self.deviceNameLabel.transform.y = self.moduleImg.transform.y + self.moduleImg.transform.getHeight() + winRelY(0.02);
    self.updateDeviceNameLabel(kStringDeviceListNoDeviceSelected, null);
}

fn drawActive(self: *DeviceListUI) !void {
    self.state.lock();
    const foundDevices = self.state.data.devices.items.len > 0;
    self.state.unlock();

    if (!foundDevices) {
        self.noDevicesLabel.draw();
    }

    for (self.deviceCheckboxes.items) |*checkbox| {
        try checkbox.draw();
    }

    try self.refreshDevicesButton.draw();
    try self.nextButton.draw();
}

fn drawInactive(self: *DeviceListUI) !void {
    self.state.lock();
    const foundDevices = self.state.data.devices.items.len > 0;
    self.state.unlock();

    if (foundDevices) self.deviceNameLabel.draw();
    self.moduleImg.draw();
}

fn recalculateUI(self: *DeviceListUI, bgRectParams: BgRectParams) void {
    Debug.log(.DEBUG, "DeviceListUI: updating self.bgRect properties!", .{});

    self.bgRect.transform.w = bgRectParams.width;
    self.bgRect.style.color = bgRectParams.color;
    self.bgRect.style.borderStyle.color = bgRectParams.borderColor;

    self.headerLabel.transform.x = self.bgRect.transform.x + 12;
    self.headerLabel.transform.y = self.bgRect.transform.relY(0.01);

    const dims = self.noDevicesLabel.getDimensions();
    self.noDevicesLabel.transform.x = self.bgRect.transform.relX(0.5) - dims.width / 2;
    self.noDevicesLabel.transform.y = self.bgRect.transform.relY(0.5) - dims.height / 2;

    self.state.lock();
    const devicesFound = self.state.data.devices.items.len > 0;
    self.state.unlock();

    if (devicesFound) {
        self.refreshDevicesButton.setPosition(.{
            .x = self.bgRect.transform.relX(0.9) - self.refreshDevicesButton.rect.transform.getWidth() / 2,
            .y = self.bgRect.transform.relY(0.1) - self.refreshDevicesButton.rect.transform.getHeight() / 2,
        });

        self.deviceNameLabel.transform.x = self.bgRect.transform.relX(0.5) - self.deviceNameLabel.getDimensions().width / 2;
        self.deviceNameLabel.transform.y = self.moduleImg.transform.y + self.moduleImg.transform.getHeight() + winRelY(0.02);
    } else {
        self.refreshDevicesButton.setPosition(.{
            .x = self.bgRect.transform.relX(0.5) - self.refreshDevicesButton.rect.transform.getWidth() / 2,
            .y = self.noDevicesLabel.transform.y + self.noDevicesLabel.transform.h + winRelY(0.02),
        });
    }

    self.moduleImg.transform.x = self.bgRect.transform.relX(0.5) - self.moduleImg.transform.getWidth() / 2;
    self.moduleImg.transform.y = self.bgRect.transform.relY(0.5) - self.moduleImg.transform.getHeight() / 2;

    self.refreshDevicesButton.setPosition(.{
        .x = self.bgRect.transform.relX(0.95) - self.refreshDevicesButton.rect.transform.getWidth(),
        .y = self.bgRect.transform.relY(0.05),
    });

    self.nextButton.setPosition(.{
        .x = self.bgRect.transform.relX(0.5) - self.nextButton.rect.transform.getWidth() / 2,
        .y = self.nextButton.rect.transform.y,
    });
}

const refreshDevices = struct {
    fn call(ctx: *anyopaque) void {
        const component = DeviceList.asInstance(ctx);

        if (component.uiComponent) |*ui| {
            if (ui.deviceCheckboxes.items.len > 0) {
                ui.destroyDeviceCheckboxContexts();
                ui.deviceCheckboxes.clearAndFree(ui.allocator);
            }
        }

        component.dispatchComponentAction();
    }
};

fn handleOnDeviceListActiveStateChanged(self: *DeviceListUI, event: ComponentEvent) !EventResult {
    var eventResult = EventResult.init();

    const data = DeviceList.Events.onDeviceListActiveStateChanged.getData(event) orelse return eventResult.fail();

    // Update state in a block with a shorter lifecycle
    {
        self.state.lock();
        defer self.state.unlock();
        self.state.data.isActive = data.isActive;
    }

    const filePickerBgRectTransform = UI.queryComponentTransform(ISOFilePickerUI);
    self.bgRect.transform.x = filePickerBgRectTransform.x + filePickerBgRectTransform.w + AppConfig.APP_UI_MODULE_GAP_X;

    switch (data.isActive) {
        true => {
            Debug.log(.DEBUG, "DeviceListUI: setting UI to ACTIVE.", .{});

            self.headerLabel.style.textColor = Color.white;

            self.recalculateUI(.{
                .width = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_ACTIVE),
                .color = Color.blueGray,
                .borderColor = Color.white,
            });
        },

        false => {
            Debug.log(.DEBUG, "DeviceListUI: setting UI to INACTIVE.", .{});

            self.headerLabel.style.textColor = Color.lightGray;

            self.recalculateUI(.{
                .width = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_INACTIVE),
                .color = Color.darkBlueGray,
                .borderColor = Color.transparentDark,
            });
        },
    }

    return eventResult.succeed();
}

/// Releases checkbox callback contexts without mutating the backing ArrayList buffer.
fn destroyDeviceCheckboxContexts(self: *DeviceListUI) void {
    for (self.deviceCheckboxes.items) |checkbox| {
        const ctx: *DeviceList.SelectDeviceCallbackContext = @ptrCast(@alignCast(checkbox.clickHandler.context));
        self.allocator.destroy(ctx);
    }
}

/// Copies `value` into an owned buffer, optionally truncating for UI display, and updates label layout.
fn updateDeviceNameLabel(self: *DeviceListUI, value: [:0]const u8, truncate_len: ?usize) void {
    self.selectedDeviceNameBuf = std.mem.zeroes([MAX_DISPLAY_STRING_LENGTH:0]u8);

    const max_allowed = if (truncate_len) |limit| @min(limit, MAX_DISPLAY_STRING_LENGTH - 1) else MAX_DISPLAY_STRING_LENGTH - 1;
    const truncated_len = @min(value.len, max_allowed);

    if (truncated_len > 0) {
        @memcpy(self.selectedDeviceNameBuf[0..truncated_len], value[0..truncated_len]);
    }

    self.selectedDeviceNameBuf[truncated_len] = 0;
    self.deviceNameLabel.value = std.mem.sliceTo(self.selectedDeviceNameBuf[0..], 0);

    const dims = self.deviceNameLabel.getDimensions();
    self.deviceNameLabel.transform.x = self.bgRect.transform.relX(0.5) - dims.width / 2;
    self.deviceNameLabel.transform.y = self.moduleImg.transform.y + self.moduleImg.transform.getHeight() + winRelY(0.02);
    self.deviceNameLabel.transform.w = dims.width;
    self.deviceNameLabel.transform.h = dims.height;
}

fn handleOnUITransformQueried(self: *DeviceListUI, event: ComponentEvent) !EventResult {
    var eventResult = EventResult.init();
    const data = Events.onUITransformQueried.getData(event) orelse return eventResult.fail();
    data.result.* = self.bgRect.transform;
    return eventResult.succeed();
}

fn handleOnDevicesCleanup(self: *DeviceListUI) !EventResult {
    var eventResult = EventResult.init();
    self.state.lock();
    self.state.data.selectedDevice = null;
    self.state.unlock();
    self.updateDeviceNameLabel(kStringDeviceListNoDeviceSelected, null);
    return eventResult.succeed();
}

/// Rebuilds checkbox controls from the latest removable device snapshot while holding state lock.
fn handleOnDevicesReadyToRender(self: *DeviceListUI) !EventResult {
    var eventResult = EventResult.init();
    //
    Debug.log(.DEBUG, "DeviceListUI: onDevicesReadyToRender() start.", .{});

    self.destroyDeviceCheckboxContexts();
    self.deviceCheckboxes.clearAndFree(self.allocator);

    self.state.lock();
    defer self.state.unlock();

    if (self.state.data.devices.items.len < 1) {
        Debug.log(.WARNING, "DeviceListUI: onDevicesReadyToRender(): no devices discovered, breaking the event loop.", .{});
        return eventResult.fail();
    }

    Debug.log(.DEBUG, "DeviceListUI: onDevicesReadyToRender(): processing checkboxes for {d} devices.", .{self.state.data.devices.items.len});

    for (self.state.data.devices.items, 0..) |*device, i| {
        //
        const selectDeviceContext = try self.allocator.create(DeviceList.SelectDeviceCallbackContext);
        errdefer self.allocator.destroy(selectDeviceContext);

        // Define context for the checkbox's on-click behavior/callback
        selectDeviceContext.* = DeviceList.SelectDeviceCallbackContext{
            .component = self.parent,
            .selectedDevice = device.*,
        };

        var textBuf: [AppConfig.CHECKBOX_TEXT_BUFFER_SIZE]u8 = std.mem.zeroes([AppConfig.CHECKBOX_TEXT_BUFFER_SIZE]u8);

        const deviceName = std.mem.sliceTo(device.deviceName[0..], Character.NULL);
        const bsdName = device.getBsdNameSlice();

        _ = std.fmt.bufPrintZ(
            textBuf[0..],
            "{s} - {s} ({d:.0}GB) [{s}]",
            .{
                if (deviceName.len > 20) deviceName[0..20] else deviceName,
                if (bsdName.len > 10) bsdName[0..10] else bsdName,
                @divTrunc(device.size, 1_000_000_000),
                if (device.type == .USB) "USB" else if (device.type == .SD) "SD" else "Other",
            },
        ) catch |err| {
            Debug.log(.ERROR, "DeviceListUI: failed to format checkbox label: {any}", .{err});
            return eventResult.fail();
        };

        Debug.log(.DEBUG, "ComponentUI: formatted string is: {s}", .{std.mem.sliceTo(textBuf[0..], Character.NULL)});

        try self.deviceCheckboxes.append(self.allocator, Checkbox.init(
            self.allocator,
            device.serviceId,
            textBuf,
            .{
                .x = self.bgRect.transform.relX(0.05),
                .y = self.bgRect.transform.relY(0.12) + @as(f32, @floatFromInt(i)) * AppConfig.DEVICE_CHECKBOXES_GAP_FACTOR_Y,
            },
            20,
            .Primary,
            .{
                .context = selectDeviceContext,
                .function = DeviceList.selectDeviceActionWrapper.call,
            },
        ));

        const checkboxPtr = &self.deviceCheckboxes.items[self.deviceCheckboxes.items.len - 1];

        checkboxPtr.outerRect.bordered = true;
        checkboxPtr.outerRect.rounded = true;
        checkboxPtr.innerRect.rounded = true;

        try checkboxPtr.*.start();
    }

    Debug.log(.DEBUG, "DeviceListUI: onDevicesReadyToRender() end.", .{});

    return eventResult.succeed();
}

/// Synchronizes checkbox toggles and summary label when the selected device changes.
fn handleOnSelectedDeviceNameChanged(self: *DeviceListUI, event: ComponentEvent) !EventResult {
    var eventResult = EventResult.init();

    const data = Events.onSelectedDeviceNameChanged.getData(event) orelse return eventResult.fail();

    var displayName: [:0]const u8 = kStringDeviceListNoDeviceSelected;
    var truncateDisplay: bool = false;

    self.state.lock();
    defer self.state.unlock();
    self.state.data.selectedDevice = data.selectedDevice;

    for (self.deviceCheckboxes.items) |*checkbox| {
        if (data.selectedDevice) |device| {
            if (device.serviceId == checkbox.deviceId) {
                checkbox.setState(.CHECKED);
            } else {
                checkbox.setState(.NORMAL);
            }
        } else {
            checkbox.setState(.NORMAL);
        }
    }

    Debug.log(
        .DEBUG,
        "DeviceListUI.handleEvent.onSelectedDeviceNameChanged received selectedDevice: \n{s}\n",
        .{if (data.selectedDevice) |device| device.getNameSlice() else kStringDeviceListNoDeviceSelected},
    );

    if (self.state.data.selectedDevice) |*device| {
        displayName = device.getNameSlice();
        truncateDisplay = true;
    }

    // Toggle the "Next" button based on whether or not a device is selected
    self.nextButton.setEnabled(data.selectedDevice != null);
    self.updateDeviceNameLabel(displayName, if (truncateDisplay) MAX_SELECTED_DEVICE_NAME_LEN else null);

    return eventResult.succeed();
}
