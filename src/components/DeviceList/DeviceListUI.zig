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

const AppManager = @import("../../managers/AppManager.zig");
const WindowManager = @import("../../managers/WindowManager.zig").WindowManagerSingleton;
const winRelX = WindowManager.relW;
const winRelY = WindowManager.relH;

const EventManager = @import("../../managers/EventManager.zig").EventManagerSingleton;
pub const ComponentName = EventManager.ComponentName.DEVICE_LIST_UI;

const DeviceList = @import("./DeviceList.zig");
const FilePickerUI = @import("../FilePicker/FilePickerUI.zig");

const ComponentFramework = @import("../framework/import/index.zig");
const Component = ComponentFramework.Component;
const ComponentEvent = ComponentFramework.Event;
const EventResult = ComponentFramework.EventResult;

const DeprecatedUI = @import("../ui/import/index.zig");
const Panel = DeprecatedUI.Panel;
const Button = DeprecatedUI.Button;
const Rectangle = DeprecatedUI.Primitives.Rectangle;
const Text = DeprecatedUI.Primitives.Text;
const Transform = DeprecatedUI.Primitives.Transform;
const Texture = DeprecatedUI.Primitives.Texture;
const Layout = DeprecatedUI.Layout;
const UI = DeprecatedUI.utils;

const Styles = DeprecatedUI.Styles;
const Color = DeprecatedUI.Styles.Color;

const UIFramework = @import("../ui/framework/import.zig");
const UIChain = UIFramework.UIChain;
const View = UIFramework.View;
const Textbox = UIFramework.Textbox;
const DeviceSelectBox = UIFramework.DeviceSelectBox;
const UnitValue = UIFramework.UnitValue;
const PositionSpec = UIFramework.PositionSpec;
const SizeSpec = UIFramework.SizeSpec;

const DEFAULT_SECTION_HEADER = "Select Device";

// This state is mutable and can be accessed from the main UI thread (draw/update)
// and a worker/event thread (handleEvent). Access must be guarded by state.lock().
pub const DeviceListUIState = struct {
    isActive: bool = false,
    devices: *std.ArrayList(StorageDevice),
    selectedDevice: ?StorageDevice = null,
};

pub const ComponentState = ComponentFramework.ComponentState(DeviceListUIState);

const DeviceListUI = @This();

const MAX_DISPLAY_STRING_LENGTH: usize = 254;
const MAX_SELECTED_DEVICE_NAME_LEN: usize = 12;

const kStringDeviceListNoDeviceSelected = "No device selected...";

// Component-agnostic props
state: ComponentState,
component: ?Component = null,

// Component-specific, unique props
allocator: std.mem.Allocator,
parent: *DeviceList,
deviceSelectBoxes: std.ArrayList(DeviceSelectBox),
// TODO: Deprecated
// bgRect: Rectangle = undefined,
// headerLabel: Text = undefined,
// nextButton: Button = undefined,
// deviceNameLabel: Text = undefined,
// noDevicesLabel: Text = undefined,
// refreshDevicesButton: Button = undefined,
selectedDeviceNameBuf: [MAX_DISPLAY_STRING_LENGTH:0]u8 = undefined,
// TODO: Deprecated
// frame: DeprecatedUI.Layout.Bounds = undefined,
layout: View = undefined,

// fn panelAppearanceActive() Panel.Appearance {
//     return .{
//         .width = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_ACTIVE),
//         .backgroundColor = Styles.Color.white,
//         .borderColor = Styles.Color.white,
//         .headerColor = Color.white,
//     };
// }
//
// fn panelAppearanceInactive() Panel.Appearance {
//     return .{
//         .width = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_INACTIVE),
//         .backgroundColor = Styles.Color.white,
//         .borderColor = Styles.Color.white,
//         .headerColor = Color.lightGray,
//     };
// }
//
// fn panelAppearanceFor(isActive: bool) Panel.Appearance {
//     return if (isActive) panelAppearanceActive() else panelAppearanceInactive();
// }

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

    pub const onRootViewTransformQueried = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_root_view_transform_queried"),
        struct { result: **UIFramework.Transform },
        struct {},
    );

    // TODO: Deprecated
    pub const onUITransformQueried = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_ui_transform_queried"),
        struct { result: **DeprecatedUI.Primitives.Transform },
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
        .deviceSelectBoxes = std.ArrayList(DeviceSelectBox).empty,
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

    try self.initBgRect();
    // try self.initNextBtn();
    // self.initRefreshDevicesBtn();
    // self.initHeaderLabel();
    // Must come after initModuleCoverTexture() as deviceNameLabel references its position
    // self.initDeviceNameLabel();

    // self.noDevicesLabel = Text.init("No external devices found...", .{ .x = 0, .y = 0 }, .{ .fontSize = 14 });

    // self.applyPanelMode(panelAppearanceInactive());

    Debug.log(.DEBUG, "DeviceListUI: component start() finished.", .{});
}

pub fn handleEvent(self: *DeviceListUI, event: ComponentEvent) !EventResult {
    Debug.log(.INFO, "DeviceListUI: handleEvent() received an event: \"{s}\"", .{event.name});

    var eventResult = EventResult.init();

    return switch (event.hash) {
        DeviceList.Events.onDeviceListActiveStateChanged.Hash => try self.handleOnDeviceListActiveStateChanged(event),
        DeviceList.Events.onDevicesCleanup.Hash => try self.handleOnDevicesCleanup(),
        Events.onRootViewTransformQueried.Hash => try self.handleOnRootViewTransformQueried(event),
        // Events.onUITransformQueried.Hash => try self.handleOnUITransformQueried(event),
        Events.onDevicesReadyToRender.Hash => try self.handleOnDevicesReadyToRender(),
        Events.onSelectedDeviceNameChanged.Hash => try self.handleOnSelectedDeviceNameChanged(event),
        AppManager.Events.AppResetEvent.Hash => self.handleAppResetRequest(),
        else => return eventResult.fail(),
    };
}

pub fn update(self: *DeviceListUI) !void {
    if (!self.readIsActive()) return;

    try self.layout.update();

    for (self.deviceSelectBoxes.items) |*entry| {
        try entry.update();
    }

    // try self.refreshDevicesButton.update();
    // try self.nextButton.update();
}

pub fn draw(self: *DeviceListUI) !void {
    const isActive = self.readIsActive();
    const devicesFound = self.hasDevices();

    // self.refreshLayout(devicesFound);
    try self.layout.draw();

    // self.bgRect.draw();
    // self.headerLabel.draw();

    if (isActive) try self.drawActive(devicesFound) else try self.drawInactive(devicesFound);
}

pub fn deinit(self: *DeviceListUI) void {
    self.destroyDeviceSelectBoxContexts();
    self.deviceSelectBoxes.deinit(self.allocator);
    self.layout.deinit();
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

fn initBgRect(self: *DeviceListUI) !void {
    // const filePickerFrame = try UI.queryComponentTransform(FilePickerUI);
    //
    // self.frame = DeprecatedUI.Layout.Bounds.relative(
    //     filePickerFrame,
    //     .{
    //         .x = Layout.UnitValue.mix(1.0, AppConfig.APP_UI_MODULE_GAP_X),
    //         .y = Layout.UnitValue.pixels(0),
    //     },
    //     .{
    //         .width = DeprecatedUI.Layout.UnitValue.pixels(winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_INACTIVE)),
    //         .height = DeprecatedUI.Layout.UnitValue.pixels(winRelY(AppConfig.APP_UI_MODULE_PANEL_HEIGHT)),
    //     },
    // );

    // self.bgRect = Rectangle{
    //     .transform = self.frame.resolve(),
    //     .style = .{
    //         .color = Styles.Color.white,
    //         .borderStyle = .{ .color = Styles.Color.white },
    //     },
    //     .rounded = true,
    //     .bordered = true,
    // };

    var ui = UIChain.init(self.allocator);

    self.layout = try ui.view(.{
        .id = null,
        .position = .percent(1, AppConfig.APP_UI_MODULE_PANEL_Y_INACTIVE),
        .offset_x = AppConfig.APP_UI_MODULE_GAP_X,
        .size = .percent(AppConfig.APP_UI_MODULE_PANEL_WIDTH_INACTIVE, AppConfig.APP_UI_MODULE_PANEL_HEIGHT_INACTIVE),
        .size_transform_height = try AppManager.getGlobalTransform(),
        .size_transform_width = try AppManager.getGlobalTransform(),
        .position_transform_x = try UIFramework.queryViewTransform(FilePickerUI),
        .position_transform_y = try AppManager.getGlobalTransform(),
        .background = .{
            .transform = .{},
            .style = .{
                .color = Color.themeSectionBg,
                .borderStyle = .{ .color = Color.themeSectionBorder },
            },
            .rounded = true,
            .bordered = true,
        },
    }).children(.{
        //
        ui.texture(.STEP_1_INACTIVE, .{})
            .id("header_icon")
            .position(.percent(0.05, 0.03))
            .positionRef(.Parent)
            .scale(0.5)
            .callbacks(.{ .onStateChange = .{} }), // Consumes .StateChanged event without doing anything
        //
        ui.textbox(DEFAULT_SECTION_HEADER, UIConfig.Styles.HeaderTextbox, UIFramework.Textbox.Params{ .wordWrap = true })
            .id("header_textbox")
            .position(.percent(1, 0))
            .offset(10, -2)
            .positionRef(.{ .NodeId = "header_icon" })
            .size(.percent(0.7, 0.3))
            .sizeRef(.Parent)
            .callbacks(.{ .onStateChange = .{} }), // Consumes .StateChanged event without doing anything
    });

    self.layout.callbacks.onStateChange = .{ .function = UIConfig.Callbacks.MainView.StateHandler.handler, .context = &self.layout };

    try self.layout.start();
}

// fn initNextBtn(self: *DeviceListUI) !void {
//     self.nextButton = Button.init("Next", null, self.bgRect.transform.getPosition(), .Primary, .{
//         .context = self.parent,
//         .function = DeviceList.dispatchComponentFinishedAction.call,
//     }, self.allocator);
//
//     self.nextButton.setEnabled(false);
//
//     try self.nextButton.start();
//
//     self.nextButton.setPosition(.{
//         .x = self.bgRect.transform.relX(0.5) - @divTrunc(self.nextButton.rect.transform.getWidth(), 2),
//         .y = self.bgRect.transform.relY(0.9) - @divTrunc(self.nextButton.rect.transform.getHeight(), 2),
//     });
//
//     self.nextButton.rect.rounded = true;
// }

// fn initRefreshDevicesBtn(self: *DeviceListUI) void {
//     self.refreshDevicesButton = Button.init("", .RELOAD_ICON, self.bgRect.transform.getPosition(), .Primary, .{
//         .context = self.parent,
//         .function = refreshDevices.call,
//     }, self.allocator);
//
//     self.refreshDevicesButton.rect.rounded = true;
// }

// fn initDeviceNameLabel(self: *DeviceListUI) void {
//     self.deviceNameLabel = Text.init("", .{ .x = 0, .y = 0 }, .{ .fontSize = 14 });
//     self.deviceNameLabel.transform.x = self.bgRect.transform.relX(0.5) - self.deviceNameLabel.getDimensions().width / 2;
//     self.deviceNameLabel.transform.y = winRelY(0.02);
//     self.updateDeviceNameLabel(kStringDeviceListNoDeviceSelected, null);
// }

fn drawActive(self: *DeviceListUI, devicesFound: bool) !void {
    if (!devicesFound) {
        // self.noDevicesLabel.draw();
    }

    for (self.deviceSelectBoxes.items) |*entry| {
        try entry.draw();
    }

    // try self.refreshDevicesButton.draw();
    // try self.nextButton.draw();
}

fn drawInactive(self: *DeviceListUI, devicesFound: bool) !void {
    if (devicesFound) {}

    _ = self;
}

// fn panelElements(self: *DeviceListUI) Panel.Elements {
//     return .{
//         .frame = &self.frame,
//         .rect = &self.bgRect,
//         .header = &self.headerLabel,
//     };
// }
//
// fn applyPanelMode(self: *DeviceListUI, appearance: Panel.Appearance) void {
//     Debug.log(.DEBUG, "DeviceListUI: applying panel appearance.", .{});
//     // Panel.applyAppearance(self.panelElements(), appearance);
//     self.updateLayout();
// }

// fn refreshLayout(self: *DeviceListUI, devicesFound: bool) void {
//     self.bgRect.transform = self.frame.resolve();
//     // self.headerLabel.transform.x = self.bgRect.transform.x + 12;
//     // self.headerLabel.transform.y = self.bgRect.transform.relY(0.01);
//     self.applyLayoutFromBounds(devicesFound);
// }

// fn updateLayout(self: *DeviceListUI) void {
//     self.refreshLayout(self.hasDevices());
// }

fn storeIsActive(self: *DeviceListUI, isActive: bool) void {
    self.state.lock();
    defer self.state.unlock();
    self.state.data.isActive = isActive;
}

fn readIsActive(self: *DeviceListUI) bool {
    self.state.lock();
    defer self.state.unlock();
    return self.state.data.isActive;
}

fn hasDevices(self: *DeviceListUI) bool {
    self.state.lock();
    defer self.state.unlock();
    return self.state.data.devices.items.len > 0;
}

fn storeSelectedDevice(self: *DeviceListUI, selected: ?StorageDevice) void {
    self.state.lock();
    defer self.state.unlock();
    self.state.data.selectedDevice = selected;
}

// fn applyLayoutFromBounds(self: *DeviceListUI, devicesFound: bool) void {
//     const noDevicesDims = self.noDevicesLabel.getDimensions();
//     self.noDevicesLabel.transform.x = self.bgRect.transform.relX(0.5) - noDevicesDims.width / 2;
//     self.noDevicesLabel.transform.y = self.bgRect.transform.relY(0.5) - noDevicesDims.height / 2;
//
//     self.nextButton.setPosition(.{
//         .x = self.bgRect.transform.relX(0.5) - self.nextButton.rect.transform.getWidth() / 2,
//         .y = self.bgRect.transform.relY(0.9) - self.nextButton.rect.transform.getHeight() / 2,
//     });
//
//     if (devicesFound) {
//         self.refreshDevicesButton.setPosition(.{
//             .x = self.bgRect.transform.relX(0.9) - self.refreshDevicesButton.rect.transform.getWidth() / 2,
//             .y = self.bgRect.transform.relY(0.1) - self.refreshDevicesButton.rect.transform.getHeight() / 2,
//         });
//
//         self.deviceNameLabel.transform.x = self.bgRect.transform.relX(0.5) - self.deviceNameLabel.getDimensions().width / 2;
//         self.deviceNameLabel.transform.y = winRelY(0.02);
//     } else {
//         self.refreshDevicesButton.setPosition(.{
//             .x = self.bgRect.transform.relX(0.5) - self.refreshDevicesButton.rect.transform.getWidth() / 2,
//             .y = self.noDevicesLabel.transform.y + self.noDevicesLabel.transform.h + winRelY(0.02),
//         });
//     }
// }

fn clearDeviceSelectBoxes(self: *DeviceListUI) void {
    if (self.deviceSelectBoxes.items.len == 0) return;
    self.destroyDeviceSelectBoxContexts();
    self.deviceSelectBoxes.clearAndFree(self.allocator);
}

fn updateDeviceSelectBoxSelection(self: *DeviceListUI, selection: ?StorageDevice) void {
    const selected_id: ?usize = if (selection) |device| blk: {
        break :blk @as(usize, @intCast(device.serviceId));
    } else null;

    for (self.deviceSelectBoxes.items) |*entry| {
        if (selected_id) |id| {
            if (entry.serviceIdentifier()) |candidate| {
                entry.setSelected(candidate == id);
            } else entry.setSelected(false);
        } else {
            entry.setSelected(false);
        }
    }
}

fn makeSelectDeviceContext(self: *DeviceListUI, device: StorageDevice) !*DeviceList.SelectDeviceCallbackContext {
    const ctx = try self.allocator.create(DeviceList.SelectDeviceCallbackContext);
    errdefer self.allocator.destroy(ctx);

    ctx.* = .{ .component = self.parent, .selectedDevice = device };
    return ctx;
}

const MAX_DEVICE_SELECTBOX_TEXT_LEN: usize = 128;
const USB_LABEL = [_:0]u8{ 'U', 'S', 'B', 0 };
const SD_LABEL = [_:0]u8{ 'S', 'D', 0 };
const OTHER_LABEL = [_:0]u8{ 'O', 't', 'h', 'e', 'r', 0 };

fn deviceSelectBoxKind(device: StorageDevice) DeviceSelectBox.DeviceKind {
    return switch (device.type) {
        .USB => .usb,
        .SD => .sd,
        else => .other,
    };
}

fn deviceTypeLabelZ(device: StorageDevice) [:0]const u8 {
    return switch (device.type) {
        .USB => USB_LABEL[0.. :0],
        .SD => SD_LABEL[0.. :0],
        else => OTHER_LABEL[0.. :0],
    };
}

fn appendDeviceSelectBox(self: *DeviceListUI, device: StorageDevice, index: usize) !void {
    const context = try self.makeSelectDeviceContext(device);
    errdefer self.allocator.destroy(context);

    var pathBuf: [MAX_DEVICE_SELECTBOX_TEXT_LEN:0]u8 = std.mem.zeroes([MAX_DEVICE_SELECTBOX_TEXT_LEN:0]u8);
    _ = try std.fmt.bufPrintZ(pathBuf[0..], "/dev/{s}", .{device.getBsdNameSlice()});

    var selectBox = DeviceSelectBox.init(.{
        .deviceKind = deviceSelectBoxKind(device),
        .content = .{
            .name = device.getNameSlice(),
            .path = @ptrCast(std.mem.sliceTo(&pathBuf, 0x00)),
            .media = deviceTypeLabelZ(device),
        },
        .style = UIConfig.Styles.DeviceSelectBoxElement,
        .callbacks = .{
            .onClick = .{ .function = DeviceList.selectDeviceActionWrapper.call, .context = context },
        },
        .serviceId = @as(usize, @intCast(device.serviceId)),
    });

    const layout = UIConfig.Layout.DeviceSelectBox;
    const y_offset = layout.vertical_padding + @as(f32, @floatFromInt(index)) * (layout.row_height + layout.spacing);

    selectBox.transform.relativeTransform = &self.layout.transform;
    selectBox.transform.position = PositionSpec.mix(
        UnitValue.mix(0, layout.horizontal_padding),
        UnitValue.mix(0, y_offset),
    );
    selectBox.transform.size = SizeSpec.mix(
        UnitValue.mix(1, -2 * layout.horizontal_padding),
        UnitValue.pixels(layout.row_height),
    );

    try selectBox.start();
    try self.deviceSelectBoxes.append(self.allocator, selectBox);

    if (self.state.data.selectedDevice) |selected_device| {
        const appended = &self.deviceSelectBoxes.items[self.deviceSelectBoxes.items.len - 1];
        appended.setSelected(selected_device.serviceId == device.serviceId);
    }
}

const refreshDevices = struct {
    fn call(ctx: *anyopaque) void {
        const component = DeviceList.asInstance(ctx);

        if (component.uiComponent) |*ui| {
            ui.clearDeviceSelectBoxes();
        }

        component.dispatchComponentAction();
    }
};

fn handleOnDeviceListActiveStateChanged(self: *DeviceListUI, event: ComponentEvent) !EventResult {
    var eventResult = EventResult.init();

    const data = DeviceList.Events.onDeviceListActiveStateChanged.getData(event) orelse return eventResult.fail();

    self.storeIsActive(data.isActive);

    // TODO: Deprecated
    if (data.isActive) {
        // self.bgRect.transform.w = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_ACTIVE);
        // self.bgRect.transform.h = winRelY(AppConfig.APP_UI_MODULE_PANEL_HEIGHT_ACTIVE);
    } else {
        // self.bgRect.transform.w = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_INACTIVE);
        // self.bgRect.transform.h = winRelY(AppConfig.APP_UI_MODULE_PANEL_HEIGHT_INACTIVE);
    }

    self.layout.emitEvent(.{ .StateChanged = .{ .isActive = data.isActive } }, .{});

    // self.applyPanelMode(panelAppearanceFor(data.isActive));

    if (!data.isActive) {
        // self.nextButton.setEnabled(false);
    }

    return eventResult.succeed();
}

/// Releases checkbox callback contexts without mutating the backing ArrayList buffer.
fn destroyDeviceSelectBoxContexts(self: *DeviceListUI) void {
    for (self.deviceSelectBoxes.items) |*box| {
        if (box.callbacks.onClick) |*handler| {
            const ctx = handler.context;
            const typed: *DeviceList.SelectDeviceCallbackContext = @ptrCast(@alignCast(ctx));
            self.allocator.destroy(typed);
            box.callbacks.onClick = null;
        }
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
    // self.deviceNameLabel.value = std.mem.sliceTo(self.selectedDeviceNameBuf[0..], 0);

    // const dims = self.deviceNameLabel.getDimensions();
    // self.deviceNameLabel.transform.x = winRelX(0.5); //self.bgRect.transform.relX(0.5) - dims.width / 2;
    // self.deviceNameLabel.transform.y = winRelY(0.02);
    // self.deviceNameLabel.transform.w = dims.width;
    // self.deviceNameLabel.transform.h = dims.height;
}

fn handleOnRootViewTransformQueried(self: *DeviceListUI, event: ComponentEvent) !EventResult {
    var eventResult = EventResult.init();
    const data = Events.onRootViewTransformQueried.getData(event) orelse return eventResult.fail();
    data.result.* = &self.layout.transform;
    return eventResult.succeed();
}

// TODO: Deprecated
// fn handleOnUITransformQueried(self: *DeviceListUI, event: ComponentEvent) !EventResult {
//     var eventResult = EventResult.init();
//     const data = Events.onUITransformQueried.getData(event) orelse return eventResult.fail();
//     data.result.* = &self.layout.transform;
//     return eventResult.succeed();
// }

fn handleOnDevicesCleanup(self: *DeviceListUI) !EventResult {
    var eventResult = EventResult.init();
    self.storeSelectedDevice(null);
    self.clearDeviceSelectBoxes();
    // self.nextButton.setEnabled(false);
    // self.updateDeviceNameLabel(kStringDeviceListNoDeviceSelected, null);
    // self.refreshLayout(false);
    return eventResult.succeed();
}

/// Rebuilds checkbox controls from the latest removable device snapshot while holding state lock.
fn handleOnDevicesReadyToRender(self: *DeviceListUI) !EventResult {
    var eventResult = EventResult.init();
    //
    Debug.log(.DEBUG, "DeviceListUI: onDevicesReadyToRender() start.", .{});
    self.clearDeviceSelectBoxes();
    // self.nextButton.setEnabled(false);

    self.state.lock();
    defer self.state.unlock();

    if (self.state.data.devices.items.len < 1) {
        Debug.log(.WARNING, "DeviceListUI: onDevicesReadyToRender(): no devices discovered, breaking the event loop.", .{});
        // self.refreshLayout(false);
        return eventResult.fail();
    }

    Debug.log(.DEBUG, "DeviceListUI: onDevicesReadyToRender(): processing checkboxes for {d} devices.", .{self.state.data.devices.items.len});

    // self.bgRect.transform = self.frame.resolve();

    for (self.state.data.devices.items, 0..) |*device, i| {
        try self.appendDeviceSelectBox(device.*, i);
    }

    Debug.log(.DEBUG, "DeviceListUI: onDevicesReadyToRender() end.", .{});

    // self.refreshLayout(true);

    return eventResult.succeed();
}

/// Synchronizes checkbox toggles and summary label when the selected device changes.
fn handleOnSelectedDeviceNameChanged(self: *DeviceListUI, event: ComponentEvent) !EventResult {
    var eventResult = EventResult.init();

    const data = Events.onSelectedDeviceNameChanged.getData(event) orelse return eventResult.fail();

    self.storeSelectedDevice(data.selectedDevice);
    self.updateDeviceSelectBoxSelection(data.selectedDevice);

    Debug.log(
        .DEBUG,
        "DeviceListUI.handleEvent.onSelectedDeviceNameChanged received selectedDevice: \n{s}\n",
        .{if (data.selectedDevice) |device| device.getNameSlice() else kStringDeviceListNoDeviceSelected},
    );

    const hasSelection = data.selectedDevice != null;
    const displayName: [:0]const u8 = if (data.selectedDevice) |device| device.getNameSlice() else kStringDeviceListNoDeviceSelected;

    _ = hasSelection;
    _ = displayName;

    // self.nextButton.setEnabled(hasSelection);
    // self.updateDeviceNameLabel(displayName, if (hasSelection) MAX_SELECTED_DEVICE_NAME_LEN else null);

    return eventResult.succeed();
}

pub fn handleAppResetRequest(self: *DeviceListUI) EventResult {
    var eventResult = EventResult.init();

    {
        self.state.lock();
        defer self.state.unlock();
        self.state.data.selectedDevice = null;
        self.state.data.isActive = false;
    }

    self.clearDeviceSelectBoxes();
    // self.nextButton.setEnabled(false);

    // self.updateDeviceNameLabel(kStringDeviceListNoDeviceSelected, null);
    // self.applyPanelMode(panelAppearanceInactive());

    return eventResult.succeed();
}

pub const UIConfig = struct {
    //
    pub const Callbacks = struct {
        //
        pub const MainView = struct {
            //
            pub const StateHandler = struct {
                pub fn handler(ctx: *anyopaque, flag: bool) void {
                    const self: *View = @ptrCast(@alignCast(ctx));

                    switch (flag) {
                        true => {
                            Debug.log(.DEBUG, "Main DeviceListUI View received a SetActive(true) command.", .{});
                            self.transform.size = .pixels(
                                WindowManager.relW(AppConfig.APP_UI_MODULE_PANEL_WIDTH_ACTIVE),
                                WindowManager.relH(AppConfig.APP_UI_MODULE_PANEL_HEIGHT_ACTIVE),
                            );

                            self.transform.position.y = .pixels(winRelY(AppConfig.APP_UI_MODULE_PANEL_Y));
                        },
                        false => {
                            Debug.log(.DEBUG, "Main DeviceListUI View received a SetActive(false) command.", .{});
                            self.transform.size = .pixels(
                                WindowManager.relW(AppConfig.APP_UI_MODULE_PANEL_WIDTH_INACTIVE),
                                WindowManager.relH(AppConfig.APP_UI_MODULE_PANEL_HEIGHT_INACTIVE),
                            );

                            self.transform.position.y = .pixels(winRelY(AppConfig.APP_UI_MODULE_PANEL_Y_INACTIVE));
                        },
                    }

                    self.transform.resolve();
                }
            };
        };
    };

    pub const Layout = struct {
        pub const DeviceSelectBox = struct {
            pub const horizontal_padding: f32 = 24;
            pub const vertical_padding: f32 = 24;
            pub const spacing: f32 = 18;
            pub const row_height: f32 = 110;
        };
    };

    pub const Styles = struct {
        //
        const HeaderTextbox: Textbox.TextboxStyle = .{
            .background = .{ .color = Color.transparent, .borderStyle = .{ .color = Color.transparent, .thickness = 0 }, .roundness = 0 },
            .text = .{ .font = .JERSEY10_REGULAR, .fontSize = 34, .textColor = Color.white },
            .lineSpacing = -5,
        };

        pub const DeviceSelectBoxElement: DeviceSelectBox.Style = .{
            .backgroundColor = Color.themeDark,
            .hoverBackgroundColor = rl.Color.init(40, 43, 57, 255),
            .selectedBackgroundColor = Color.themeSectionBg,
            .disabledBackgroundColor = Color.transparentDark,
            .iconTint = Color.white,
            .borderColor = Color.themePrimary,
            .borderThickness = 2,
            .cornerRadius = 0.12,
            .cornerSegments = 10,
            .padding = 10,
            .iconFraction = 0.23,
            .contentSpacing = 20,
            .lineSpacing = 6,
            .primaryText = .{ .font = .ROBOTO_REGULAR, .fontSize = 22, .textColor = Color.white },
            .secondaryText = .{ .font = .JERSEY10_REGULAR, .fontSize = 20, .textColor = Color.offWhite },
            .detailText = .{ .font = .ROBOTO_REGULAR, .fontSize = 14, .textColor = Color.lightGray },
            .scale = 0.7,
        };
    };
};
