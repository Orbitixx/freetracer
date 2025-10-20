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
const DeviceSelectBoxList = UIFramework.DeviceSelectBoxList;
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
const DeviceListUIError = error{DeviceSelectBoxListMissing};

const MAX_DISPLAY_STRING_LENGTH: usize = 254;
const MAX_SELECTED_DEVICE_NAME_LEN: usize = 12;

const kStringDeviceListNoDeviceSelected = "No device selected...";

// Component-agnostic props
state: ComponentState,
component: ?Component = null,

// Component-specific, unique props
allocator: std.mem.Allocator,
parent: *DeviceList,
deviceSelectList: ?*DeviceSelectBoxList = null,
selectedDeviceNameBuf: [MAX_DISPLAY_STRING_LENGTH:0]u8 = undefined,
layout: View = undefined,

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
    try self.initLayout();

    Debug.log(.DEBUG, "DeviceListUI: component start() finished.", .{});
}

pub fn handleEvent(self: *DeviceListUI, event: ComponentEvent) !EventResult {
    Debug.log(.INFO, "DeviceListUI: handleEvent() received an event: \"{s}\"", .{event.name});

    var eventResult = EventResult.init();

    return switch (event.hash) {
        DeviceList.Events.onDeviceListActiveStateChanged.Hash => try self.handleOnDeviceListActiveStateChanged(event),
        DeviceList.Events.onDevicesCleanup.Hash => try self.handleOnDevicesCleanup(),
        Events.onRootViewTransformQueried.Hash => try self.handleOnRootViewTransformQueried(event),
        Events.onDevicesReadyToRender.Hash => try self.handleOnDevicesReadyToRender(),
        Events.onSelectedDeviceNameChanged.Hash => try self.handleOnSelectedDeviceNameChanged(event),
        AppManager.Events.AppResetEvent.Hash => self.handleAppResetRequest(),
        else => return eventResult.fail(),
    };
}

pub fn update(self: *DeviceListUI) !void {
    if (!self.readIsActive()) return;

    try self.layout.update();
}

pub fn draw(self: *DeviceListUI) !void {
    // const isActive = self.readIsActive();
    // const devicesFound = self.hasDevices();

    try self.layout.draw();

    // if (isActive) try self.drawActive(devicesFound) else try self.drawInactive(devicesFound);
}

pub fn deinit(self: *DeviceListUI) void {
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

fn initLayout(self: *DeviceListUI) !void {
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

        ui.spriteButton(.{
            .identifier = .DeviceListRefreshDevicesButton,
            .text = "",
            .texture = .RELOAD_ICON,
        })
            .position(.percent(1.05, 0.15))
            .positionRef(.{ .NodeId = "header_textbox" })
            .size(.percent(0.07, 0.07))
            .sizeRef(.Parent)
            .offsetToOrigin()
            .active(false)
            .callbacks(.{
            .onClick = .{
                .function = refreshDevices.call,
                .context = self.parent,
            },
        }),

        ui.deviceSelectBoxList(.{
            .identifier = .DeviceListDeviceListBox,
            .allocator = self.allocator,
            .layout = UIConfig.Layout.DeviceSelectBox,
            .style = UIConfig.Styles.DeviceSelectBoxElement,
        })
            .id("device_select_list")
            .position(.percent(0, 1.7))
            .positionRef(.{ .NodeId = "header_icon" })
            .size(.percent(0.9, 0.7))
            .sizeRef(.Parent)
            .active(false),
        // .callbacks(.{ .onStateChange = .{} }),

        ui.texture(.WARNING_ICON, .{})
            .id("device_list_warning_icon")
            .position(.percent(0.05, 0.88))
            .positionRef(.Parent)
            .active(false),

        ui.textbox("All data on selected device will be erased.", Textbox.TextboxStyle{ .text = .{
            .fontSize = 14,
            .textColor = rl.Color.init(255, 194, 14, 255),
        } }, Textbox.Params{ .wordWrap = true })
            .id("device_list_warning_textbox")
            .position(.percent(1.7, 0))
            .positionRef(.{ .NodeId = "device_list_warning_icon" })
            .size(.percent(0.48, 0.15))
            .sizeRef(.Parent)
            .active(false),

        ui.spriteButton(.{
            .text = "Confirm",
            .texture = .BUTTON_FRAME,
            .callbacks = .{
                .onClick = .{
                    .function = DeviceList.dispatchComponentFinishedAction.call,
                    .context = self.parent,
                },
            },
            .enabled = false,
            .style = UIConfig.Styles.ConfirmButton,
        }).position(.percent(1.1, 0))
            .elId(.DeviceListConfirmButton)
            .offset(0, -10)
            .positionRef(.{ .NodeId = "device_list_warning_textbox" })
            .size(.percent(0.3, 0.1))
            .sizeRef(.Parent)
            .active(false),

        ui.text("No devices found", .{})
            .elId(.DeviceListNoDevicesText)
            .position(.percent(0.5, 0.5))
            .positionRef(.Parent)
            .offsetToOrigin()
            .active(false),

        ui.texture(.DEVICE_LIST_PLACEHOLDER, .{})
            .elId(.DeviceListPlaceholderTexture)
            .position(.percent(0.5, 0.6))
            .positionRef(.Parent)
            .scale(2.5)
            .offsetToOrigin(),
    });

    self.layout.callbacks.onStateChange = .{ .function = UIConfig.Callbacks.MainView.StateHandler.handler, .context = &self.layout };

    try self.layout.start();
    try self.bindDeviceSelectList();
}

fn bindDeviceSelectList(self: *DeviceListUI) DeviceListUIError!void {
    for (self.layout.children.items) |*child| {
        switch (child.*) {
            .DeviceSelectBoxList => |*list| {
                self.deviceSelectList = list;
                return;
            },
            else => {},
        }
    }
    return DeviceListUIError.DeviceSelectBoxListMissing;
}

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

fn destroySelectDeviceContext(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const typed: *DeviceList.SelectDeviceCallbackContext = @ptrCast(@alignCast(ctx));
    allocator.destroy(typed);
}

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

fn clearDeviceSelectBoxes(self: *DeviceListUI) void {
    if (self.deviceSelectList) |list| list.clear();
}

fn updateDeviceSelectBoxSelection(self: *DeviceListUI, selection: ?StorageDevice) void {
    const service_id = if (selection) |device| @as(usize, @intCast(device.serviceId)) else null;
    if (self.deviceSelectList) |list| list.setSelected(service_id);
}

fn appendDeviceSelectBox(self: *DeviceListUI, device: StorageDevice) !void {
    const context = try self.makeSelectDeviceContext(device);
    errdefer self.allocator.destroy(context);

    var pathBuf: [MAX_DEVICE_SELECTBOX_TEXT_LEN:0]u8 = std.mem.zeroes([MAX_DEVICE_SELECTBOX_TEXT_LEN:0]u8);
    _ = try std.fmt.bufPrintZ(pathBuf[0..], "/dev/{s}", .{device.getBsdNameSlice()});

    const is_selected = if (self.state.data.selectedDevice) |current| current.serviceId == device.serviceId else false;

    if (self.deviceSelectList) |list| try list.append(.{
        .deviceKind = deviceSelectBoxKind(device),
        .content = .{
            .name = device.getNameSlice(),
            .path = @ptrCast(std.mem.sliceTo(&pathBuf, 0x00)),
            .media = deviceTypeLabelZ(device),
        },
        .callbacks = .{
            .onClick = .{ .function = DeviceList.selectDeviceActionWrapper.call, .context = context },
        },
        .selected = is_selected,
        .serviceId = @as(usize, @intCast(device.serviceId)),
        .context = context,
        .context_dtor = destroySelectDeviceContext,
    }) else {
        destroySelectDeviceContext(context, self.allocator);
        return DeviceListUIError.DeviceSelectBoxListMissing;
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

    self.layout.emitEvent(
        .{ .StateChanged = .{ .isActive = data.isActive } },
        .{},
    );
    self.layout.emitEvent(
        .{ .StateChanged = .{ .target = .DeviceListPlaceholderTexture, .isActive = !data.isActive } },
        .{ .excludeSelf = true },
    );
    self.layout.emitEvent(
        .{ .StateChanged = .{ .target = .DeviceListDeviceListBox, .isActive = data.isActive } },
        .{ .excludeSelf = true },
    );
    self.layout.emitEvent(
        .{ .StateChanged = .{ .target = .DeviceListRefreshDevicesButton, .isActive = data.isActive } },
        .{ .excludeSelf = true },
    );

    return eventResult.succeed();
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
        self.layout.emitEvent(
            .{ .StateChanged = .{ .target = .DeviceListNoDevicesText, .isActive = true } },
            .{ .excludeSelf = true },
        );
        return eventResult.fail();
    }

    self.layout.emitEvent(
        .{ .StateChanged = .{ .target = .DeviceListNoDevicesText, .isActive = false } },
        .{ .excludeSelf = true },
    );

    Debug.log(.DEBUG, "DeviceListUI: onDevicesReadyToRender(): processing checkboxes for {d} devices.", .{self.state.data.devices.items.len});

    for (self.state.data.devices.items) |*device| {
        try self.appendDeviceSelectBox(device.*);
    }

    Debug.log(.DEBUG, "DeviceListUI: onDevicesReadyToRender() end.", .{});

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

    _ = displayName;

    self.layout.emitEvent(
        .{ .SpriteButtonEnabledChanged = .{ .target = .DeviceListConfirmButton, .enabled = hasSelection } },
        .{ .excludeSelf = true },
    );

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
        pub const DeviceSelectBox = DeviceSelectBoxList.Layout{
            .padding = 0,
            .spacing = 12,
            .row_height = 82,
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
            .iconFraction = 0.15,
            .contentSpacing = 20,
            .lineSpacing = 6,
            .textLineSpacing = 4,
            .primaryText = .{ .font = .ROBOTO_REGULAR, .fontSize = 20, .textColor = Color.white },
            .secondaryText = .{ .font = .JERSEY10_REGULAR, .fontSize = 20, .textColor = Color.offWhite },
            .detailText = .{ .font = .ROBOTO_REGULAR, .fontSize = 14, .textColor = Color.lightGray },
            .scale = 0.7,
        };

        const ConfirmButton: UIFramework.SpriteButton.Style = .{
            .font = .JERSEY10_REGULAR,
            .fontSize = 24,
            .textColor = Color.themePrimary,
            .tint = Color.themePrimary,
            .hoverTint = Color.themeTertiary,
            .hoverTextColor = Color.themeTertiary,
        };
    };
};
