// This file implements the UI component for the DataFlasher module. It is responsible
// for rendering the flasher's state, including the selected ISO file and target device,
// progress bar, and status indicators. It operates entirely in the unprivileged GUI
// process, receiving state changes and progress updates via an internal event system
// from its parent `DataFlasher` component, which in turn communicates with the
// privileged helper. This component allocates UI widgets using an allocator provided
// by its parent and is responsible for their deinitialization.
const std = @import("std");
const rl = @import("raylib");
const freetracer_lib = @import("freetracer-lib");
const Debug = freetracer_lib.Debug;

const AppConfig = @import("../../config.zig");

const StorageDevice = freetracer_lib.StorageDevice;

const AppManager = @import("../../managers/AppManager.zig");
const EventManager = @import("../../managers/EventManager.zig").EventManagerSingleton;
const ComponentName = EventManager.ComponentName.DATA_FLASHER_UI;

const ComponentFramework = @import("../framework/import/index.zig");
// const WorkerContext = @import("./WorkerContext.zig");

const DataFlasher = @import("./DataFlasher.zig");
const DeviceList = @import("../DeviceList/DeviceList.zig");
const DeviceListUI = @import("../DeviceList/DeviceListUI.zig");

const SECTION_PADDING: f32 = AppConfig.APP_UI_MODULE_SECTION_PADDING;
const PADDING_LEFT: f32 = AppConfig.APP_UI_MODULE_PADDING_LEFT;
const PADDING_RIGHT: f32 = AppConfig.APP_UI_MODULE_PADDING_RIGHT;

const HEADER_LABEL_OFFSET_X: f32 = AppConfig.HEADER_LABEL_OFFSET_X;
const HEADER_LABEL_REL_Y: f32 = AppConfig.HEADER_LABEL_REL_Y;
const FLASH_BUTTON_REL_Y: f32 = AppConfig.FLASH_BUTTON_REL_Y;

const TEXTURE_TILE_SIZE = AppConfig.TEXTURE_TILE_SIZE;

const ICON_SIZE = AppConfig.ICON_SIZE;
const ICON_TEXT_GAP_X = AppConfig.ICON_TEXT_GAP_X;
const ISO_ICON_POS_REL_X = PADDING_LEFT;
const ISO_ICON_POS_REL_Y = SECTION_PADDING;
const DEV_ICON_POS_REL_X = ISO_ICON_POS_REL_X;
const DEV_ICON_POS_REL_Y = ISO_ICON_POS_REL_Y + ISO_ICON_POS_REL_Y / 2;

const ITEM_GAP_Y = AppConfig.ITEM_GAP_Y;
const STATUS_INDICATOR_SIZE: f32 = AppConfig.STATUS_INDICATOR_SIZE;

// --- SpriteSheet Coordinates ---
const ICON_SRC_ISO = rl.Rectangle{
    .x = TEXTURE_TILE_SIZE * 9,
    .y = TEXTURE_TILE_SIZE * 10,
    .width = TEXTURE_TILE_SIZE,
    .height = TEXTURE_TILE_SIZE,
};
const ICON_SRC_DEVICE = rl.Rectangle{
    .x = TEXTURE_TILE_SIZE * 10,
    .y = TEXTURE_TILE_SIZE * 11,
    .width = TEXTURE_TILE_SIZE,
    .height = TEXTURE_TILE_SIZE,
};

// This state is mutable and can be accessed from the main UI thread (draw/update)
// and a worker/event thread (handleEvent). Access must be guarded by state.lock().
const DataFlasherUIState = struct {
    isActive: bool = false,
    // owned by FilePicker
    isoPath: ?[:0]const u8 = null,
    // owned by DeviceList (via state ArrayList)
    device: ?StorageDevice = null,
};

const DataFlasherUI = @This();

const Component = ComponentFramework.Component;
const ComponentState = ComponentFramework.ComponentState(DataFlasherUIState);
pub const ComponentWorker = ComponentFramework.Worker(DataFlasherUIState);
const ComponentEvent = ComponentFramework.Event;

const EventResult = ComponentFramework.EventResult;

const DeprecatedUI = @import("../ui/import/index.zig");
const Panel = DeprecatedUI.Panel;
const Button = DeprecatedUI.Button;
const Checkbox = DeprecatedUI.Checkbox;
const Transform = DeprecatedUI.Primitives.Transform;
const Rectangle = DeprecatedUI.Primitives.Rectangle;
const Text = DeprecatedUI.Primitives.Text;
const Texture = DeprecatedUI.Primitives.Texture;
const Statusbox = DeprecatedUI.Statusbox;
const Progressbox = DeprecatedUI.Progressbox;
const StatusIndicator = DeprecatedUI.StatusIndicator;
const Layout = DeprecatedUI.Layout;

const UIFramework = @import("../ui/framework/import.zig");
const View = UIFramework.View;
const UIChain = UIFramework.UIChain;

const PrivilegedHelper = @import("../macos/PrivilegedHelper.zig");

const Styles = DeprecatedUI.Styles;
const Color = DeprecatedUI.Styles.Color;

const WindowManager = @import("../../managers/WindowManager.zig").WindowManagerSingleton;
const winRelX = WindowManager.relW;
const winRelY = WindowManager.relH;

const NULL_TEXT: [:0]const u8 = "NULL";

const MAX_PATH_DISPLAY_LENGTH = 40;
const DEFAULT_SECTION_HEADER = "Confirm & Flash";

// Component-agnostic props
state: ComponentState,
component: ?Component = null,
worker: ?ComponentWorker = null,

// Component-specific, unique props
allocator: std.mem.Allocator,
parent: *DataFlasher,
// bgRect: Rectangle = undefined,
// headerLabel: Text = undefined,
// moduleImg: Texture = undefined,
// uiSheetTexture: Texture = undefined,
// button: Button = undefined,
// isoText: Text = undefined,
// deviceText: Text = undefined,
// progressBox: Progressbox = undefined,
displayISOTextBuffer: [std.fs.max_path_bytes]u8 = undefined,
displayDeviceTextBuffer: [std.fs.max_path_bytes]u8 = undefined,
// frame: Layout.Bounds = undefined,

layout: View = undefined,

flashRequested: bool = false,

// statusSectionHeader: Text = undefined,
// isoStatus: StatusIndicator = undefined,
// deviceStatus: StatusIndicator = undefined,
// permissionsStatus: StatusIndicator = undefined,
// writeStatus: StatusIndicator = undefined,
// verificationStatus: StatusIndicator = undefined,

pub const Events = struct {
    pub const onActiveStateChanged = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_active_state_changed"),
        struct { isActive: bool },
        struct {},
    );
};

// Shares the caller's allocator and captures a parent pointer.
// The caller retains ownership of the allocator and is responsible for calling deinit.
pub fn init(allocator: std.mem.Allocator, parent: *DataFlasher) !DataFlasherUI {
    return DataFlasherUI{
        .state = ComponentState.init(DataFlasherUIState{}),
        .allocator = allocator,
        .parent = parent,
    };
}

pub fn initComponent(self: *DataFlasherUI, parent: ?*Component) !void {
    if (self.component != null) return error.BaseComponentAlreadyInitialized;
    self.component = try Component.init(self, &ComponentImplementation.vtable, parent, self.allocator);
}

/// Subscribes to events and prepares visual primitives; call exactly once during setup.
pub fn start(self: *DataFlasherUI) !void {
    if (self.component == null) try self.initComponent(self.parent.asComponentPtr());

    try self.subscribeToEvents();
    try self.initLayout();
    // try self.initFlashButton();
    //
    // self.initModuleLabels();
    // self.initTextures();
    // self.initStatusIndicators();
    // self.initProgressbox();
    //
}

pub fn update(self: *DataFlasherUI) !void {
    try self.layout.update();
    // try self.button.update();
}

/// Draws the module frame and then the appropriate active/inactive presentation.
pub fn draw(self: *DataFlasherUI) !void {
    // const isActive = self.readIsActive();

    try self.layout.draw();

    // self.updateLayout();
    //
    // self.bgRect.draw();
    // self.headerLabel.draw();

    // if (isActive) try self.drawActive() else try self.drawInactive();
}

/// Render routine when the module is active; expects state lock not held by caller.
// fn drawActive(self: *DataFlasherUI) !void {
//     self.isoText.draw();
//     self.deviceText.draw();
//     // TODO: Create separate label Component with optional icon
//     rl.drawTexturePro(
//         self.uiSheetTexture.texture,
//         ICON_SRC_ISO,
//         .{ .x = self.bgRect.transform.relX(ISO_ICON_POS_REL_X), .y = self.bgRect.transform.relY(ISO_ICON_POS_REL_Y), .width = ICON_SIZE, .height = ICON_SIZE },
//         .{ .x = 0, .y = 0 },
//         0,
//         .white,
//     );
//
//     rl.drawTexturePro(
//         self.uiSheetTexture.texture,
//         ICON_SRC_DEVICE,
//         .{ .x = self.bgRect.transform.relX(DEV_ICON_POS_REL_X), .y = self.bgRect.transform.relY(DEV_ICON_POS_REL_Y), .width = ICON_SIZE, .height = ICON_SIZE },
//         .{ .x = 0, .y = 0 },
//         0,
//         .white,
//     );
//
//     if (self.flashRequested) {
//         self.statusSectionHeader.draw();
//         try self.isoStatus.draw();
//         try self.deviceStatus.draw();
//         try self.permissionsStatus.draw();
//         try self.writeStatus.draw();
//         try self.verificationStatus.draw();
//     }
//
//     self.progressBox.draw();
//
//     try self.button.draw();
// }
//
// fn drawInactive(self: *DataFlasherUI) !void {
//     self.moduleImg.draw();
// }

/// Consumes DataFlasher/PrivilegedHelper events; returns failure for unknown events.
pub fn handleEvent(self: *DataFlasherUI, event: ComponentEvent) !EventResult {
    var eventResult = EventResult.init();

    return switch (event.hash) {
        //
        // Event: parent's authoritative state signal
        DataFlasher.Events.onActiveStateChanged.Hash => try self.handleOnActiveStateChanged(event),

        PrivilegedHelper.Events.onHelperISOFileOpenSuccess.Hash => {
            // self.isoStatus.switchState(.SUCCESS);
            return eventResult.succeed();
        },

        PrivilegedHelper.Events.onHelperISOFileOpenFailed.Hash => {
            // self.isoStatus.switchState(.FAILURE);
            return eventResult.succeed();
        },

        PrivilegedHelper.Events.onHelperDeviceOpenSuccess.Hash => {
            // self.deviceStatus.switchState(.SUCCESS);
            // self.permissionsStatus.switchState(.SUCCESS);
            return eventResult.succeed();
        },

        PrivilegedHelper.Events.onHelperDeviceOpenFailed.Hash => {
            // self.deviceStatus.switchState(.FAILURE);
            // self.permissionsStatus.switchState(.FAILURE);
            return eventResult.succeed();
        },

        PrivilegedHelper.Events.onHelperWriteSuccess.Hash => {
            // self.writeStatus.switchState(.SUCCESS);
            return eventResult.succeed();
        },

        PrivilegedHelper.Events.onHelperWriteFailed.Hash => {
            // self.writeStatus.switchState(.FAILURE);
            return eventResult.succeed();
        },

        PrivilegedHelper.Events.onHelperVerificationSuccess.Hash => {
            // self.verificationStatus.switchState(.SUCCESS);
            // self.progressBox.text.value = "Finished writing ISO. You may now eject the device.";
            try AppManager.reportAction(.DataFlashed);
            return eventResult.succeed();
        },

        PrivilegedHelper.Events.onHelperVerificationFailed.Hash => {
            // self.verificationStatus.switchState(.FAILURE);
            return eventResult.succeed();
        },

        PrivilegedHelper.Events.onISOWriteProgressChanged.Hash => try self.handleOnISOWriteProgressChanged(event),
        PrivilegedHelper.Events.onWriteVerificationProgressChanged.Hash => try self.handleOnWriteVerificationProgressChanged(event),
        AppManager.Events.AppResetEvent.Hash => self.handleAppResetRequest(),

        else => return eventResult.fail(),
    };
}

pub fn dispatchComponentAction(self: *DataFlasherUI) void {
    _ = self;
}

/// Deinitializes all UI widgets owned by this component, releasing their memory back to the allocator provided in init.
pub fn deinit(self: *DataFlasherUI) void {
    self.layout.deinit();
    // self.button.deinit();
}

fn subscribeToEvents(self: *DataFlasherUI) !void {
    if (self.component) |*component| {
        if (!EventManager.subscribe(ComponentName, component)) return error.UnableToSubscribeToEventManager;
    } else return error.UnableToSubscribeToEventManager;
}

fn initLayout(self: *DataFlasherUI) !void {
    var ui = UIChain.init(self.allocator);

    self.layout = try ui.view(.{
        .id = null,
        .position = .percent(1, AppConfig.APP_UI_MODULE_PANEL_Y_INACTIVE),
        .offset_x = AppConfig.APP_UI_MODULE_GAP_X,
        .size = .percent(AppConfig.APP_UI_MODULE_PANEL_WIDTH_INACTIVE, AppConfig.APP_UI_MODULE_PANEL_HEIGHT_INACTIVE),
        .size_transform_height = try AppManager.getGlobalTransform(),
        .size_transform_width = try AppManager.getGlobalTransform(),
        .position_transform_x = try UIFramework.queryViewTransform(DeviceListUI),
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

        ui.texture(.FLASH_PLACEHOLDER, .{})
            .elId(.DataFlasherPlaceholderTexture)
            .position(.percent(0.5, 0.6))
            .positionRef(.Parent)
            .scale(3)
            .offsetToOrigin(),
    });

    self.layout.callbacks.onStateChange = .{ .function = UIConfig.Callbacks.MainView.StateHandler.handler, .context = &self.layout };

    try self.layout.start();
}

// fn initFlashButton(self: *DataFlasherUI) !void {
//     self.button = Button.init(
//         "Flash",
//         null,
//         self.bgRect.transform.getPosition(),
//         .Primary,
//         .{ .context = self.parent, .function = DataFlasher.flashISOtoDeviceWrapper.call },
//         self.allocator,
//     );
//     self.button.params.disableOnClick = true;
//     self.button.setEnabled(false);
//     try self.button.start();
//     self.button.setPosition(.{
//         .x = self.bgRect.transform.relX(0.5) - @divTrunc(self.button.rect.transform.getWidth(), 2),
//         .y = self.bgRect.transform.relY(0.9) - @divTrunc(self.button.rect.transform.getHeight(), 2),
//     });
//     self.button.rect.rounded = true;
// }
//
// fn initModuleLabels(self: *DataFlasherUI) void {
//     self.displayISOTextBuffer = std.mem.zeroes([std.fs.max_path_bytes]u8);
//     self.displayDeviceTextBuffer = std.mem.zeroes([std.fs.max_path_bytes]u8);
//     self.isoText = Text.init("NULL", .{ .x = 0, .y = 0 }, .{ .fontSize = 14 });
//     self.deviceText = Text.init("NULL", .{ .x = 0, .y = 0 }, .{ .fontSize = 14 });
//
//     self.headerLabel = Text.init("flash", .{ .x = self.bgRect.transform.x + 12, .y = self.bgRect.transform.relY(0.01) }, .{
//         .font = .JERSEY10_REGULAR,
//         .fontSize = 34,
//         .textColor = Styles.Color.white,
//     });
//
//     self.statusSectionHeader = Text.init(
//         "status",
//         .{ .x = self.bgRect.transform.relX(PADDING_LEFT), .y = self.bgRect.transform.relY(0.26) },
//         .{ .fontSize = 24, .font = .JERSEY10_REGULAR },
//     );
// }
//
// fn initStatusIndicators(self: *DataFlasherUI) void {
//     self.isoStatus = StatusIndicator.init("ISO validated & stream open", STATUS_INDICATOR_SIZE);
//     self.deviceStatus = StatusIndicator.init("Device validated & stream open", STATUS_INDICATOR_SIZE);
//     self.permissionsStatus = StatusIndicator.init("Freetracer has necessary permissions", STATUS_INDICATOR_SIZE);
//     self.writeStatus = StatusIndicator.init("Write successfully completed", STATUS_INDICATOR_SIZE);
//     self.verificationStatus = StatusIndicator.init("Written bytes successfuly verified", STATUS_INDICATOR_SIZE);
// }
//
//
// fn initProgressbox(self: *DataFlasherUI) void {
//     self.progressBox = Progressbox{
//         .text = Text.init("", .{
//             .x = self.bgRect.transform.relX(PADDING_LEFT),
//             .y = self.bgRect.transform.relY(0.75),
//         }, .{
//             .font = .ROBOTO_REGULAR,
//             .fontSize = 14,
//             .textColor = .white,
//         }),
//         .percentText = Text.init(
//             "",
//             .{ .x = self.bgRect.transform.relX(PADDING_LEFT), .y = self.bgRect.transform.relY(0.75) },
//             .{ .fontSize = 14 },
//         ),
//         .value = 0,
//         .percentTextBuf = std.mem.zeroes([5]u8),
//         .rect = .{
//             .bordered = true,
//             .rounded = true,
//             .style = .{ .color = Color.white, .borderStyle = .{ .color = Color.white, .thickness = 2.00 } },
//             .transform = .{
//                 .x = self.bgRect.transform.relX(0.2),
//                 .y = self.bgRect.transform.relY(0.7),
//                 .h = 18.0,
//                 .w = 0.0,
//             },
//         },
//     };
// }
//

fn storeIsActive(self: *DataFlasherUI, isActive: bool) void {
    self.state.lock();
    defer self.state.unlock();
    self.state.data.isActive = isActive;
}

fn readIsActive(self: *DataFlasherUI) bool {
    self.state.lock();
    defer self.state.unlock();
    return self.state.data.isActive;
}

const ParentSelection = struct {
    isoPath: ?[:0]const u8 = null,
    device: ?StorageDevice = null,
};

fn readParentSelection(self: *DataFlasherUI) ParentSelection {
    var selection = ParentSelection{};

    self.parent.state.lock();
    defer self.parent.state.unlock();

    selection.isoPath = self.parent.state.data.isoPath;
    selection.device = self.parent.state.data.device;

    return selection;
}

fn updateIsoDisplay(self: *DataFlasherUI, isoPath: [:0]const u8) void {
    @memset(&self.displayISOTextBuffer, 0);

    const availableWidth = (1 - SECTION_PADDING) * self.bgRect.transform.getWidth() - (ICON_SIZE + ICON_TEXT_GAP_X);

    self.isoText.value = isoPath;
    const dims = self.isoText.getDimensions();

    var finalValue: [:0]const u8 = NULL_TEXT;
    if (dims.width > availableWidth) {
        Debug.log(.DEBUG, "DataFlasherUI: truncated ISO path for display", .{});
        finalValue = ellipsizePath(self.displayISOTextBuffer[0..], isoPath, MAX_PATH_DISPLAY_LENGTH);
    } else {
        const buffer = self.displayISOTextBuffer[0..];
        const copied = std.fmt.bufPrintZ(buffer, "{s}", .{isoPath}) catch |err| blk: {
            Debug.log(.ERROR, "DataFlasherUI: failed to cache ISO path for display: {any}", .{err});
            break :blk NULL_TEXT;
        };
        finalValue = copied;
    }
}

fn updateDeviceDisplay(self: *DataFlasherUI, device: ?StorageDevice) void {
    @memset(&self.displayDeviceTextBuffer, 0);

    if (device) |dev| {
        const label = formatDeviceLabel(self.displayDeviceTextBuffer[0..], dev.getNameSlice(), dev.getBsdNameSlice());
        _ = label;
        // setTextValue(&self.deviceText, label);
    } else {
        // setTextValue(&self.deviceText, NULL_TEXT);
    }
}

pub const ComponentImplementation = ComponentFramework.ImplementComponent(DataFlasherUI);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;

/// Truncates a file path with a "..." in the middle to fit within max_chars.
/// Always writes the result to the provided buffer.
fn ellipsizePath(buffer: []u8, path: [:0]const u8, maxChars: usize) [:0]const u8 {
    // If the path already fits, just copy it and return.
    if (path.len <= maxChars) {
        return std.fmt.bufPrintZ(buffer, "{s}", .{path}) catch path;
    }

    // If max_chars is too small for ellipsis, just truncate from the left.
    if (maxChars < 5) { // e.g., "a...b" requires 5 chars
        const startChar = path.len - @min(path.len, maxChars);
        return std.fmt.bufPrintZ(buffer, "{s}", .{path[startChar..]}) catch path;
    }

    const ellipsis = "...";
    const tailLen = (maxChars - ellipsis.len) / 2;
    const headLen = maxChars - ellipsis.len - tailLen;

    const head = path[0..headLen];
    const tail = path[path.len - tailLen ..];

    return std.fmt.bufPrintZ(buffer, "{s}{s}{s}", .{ head, ellipsis, tail }) catch {
        // Fallback in case of an unexpected formatting error, though unlikely.
        // Just copy the original path if it fits, otherwise it's an error.
        return if (buffer.len > path.len) blk: {
            @memcpy(buffer, path);
            buffer[path.len] = 0;
            break :blk buffer[0..path.len :0];
        } else path;
    };
}

fn formatDeviceLabel(buffer: []u8, dev_name: [:0]const u8, bsd_name: [:0]const u8) [:0]const u8 {
    return std.fmt.bufPrintZ(buffer, "{s} ({s})", .{ dev_name, bsd_name }) catch dev_name;
}

pub fn handleOnActiveStateChanged(self: *DataFlasherUI, event: ComponentEvent) !EventResult {
    var eventResult = EventResult.init();
    const data = DataFlasher.Events.onActiveStateChanged.getData(event) orelse return eventResult.fail();

    self.storeIsActive(data.isActive);

    if (data.isActive) {
        Debug.log(.DEBUG, "DataFlasherUI: setting UI to ACTIVE.", .{});
        // self.onActivated();
    } else {
        Debug.log(.DEBUG, "DataFlasherUI: setting UI to INACTIVE.", .{});
        // self.onDeactivated();
    }

    self.layout.emitEvent(.{ .StateChanged = .{ .isActive = data.isActive } }, .{});

    self.layout.emitEvent(.{ .StateChanged = .{ .target = .DataFlasherPlaceholderTexture, .isActive = !data.isActive } }, .{ .excludeSelf = true });

    // if (data.isActive) {
    //     self.bgRect.transform.w = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_ACTIVE);
    //     self.bgRect.transform.h = winRelY(AppConfig.APP_UI_MODULE_PANEL_HEIGHT_ACTIVE);
    // } else {
    //     self.bgRect.transform.w = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_INACTIVE);
    //     self.bgRect.transform.h = winRelY(AppConfig.APP_UI_MODULE_PANEL_HEIGHT_INACTIVE);
    // }

    return eventResult.succeed();
}

// fn onActivated(self: *DataFlasherUI) void {
//     const selection = self.readParentSelection();
//     const isoPath = selection.isoPath orelse NULL_TEXT;
//     _ = isoPath;
//
//     // self.applyPanelMode(panelAppearanceActive());
//
//     // self.updateIsoDisplay(isoPath);
//     // self.updateDeviceDisplay(selection.device);
//
//     // const ready = selection.isoPath != null and selection.device != null;
//     // self.button.setEnabled(ready);
//
//     // self.applyLayoutFromBounds();
// }

// fn onDeactivated(self: *DataFlasherUI) void {
//     // self.button.setEnabled(false);
//     // self.applyPanelMode(panelAppearanceInactive());
// }

pub fn handleOnISOWriteProgressChanged(self: *DataFlasherUI, event: ComponentEvent) !EventResult {
    var eventResult = EventResult.init();
    const data = PrivilegedHelper.Events.onISOWriteProgressChanged.getData(event) orelse return eventResult.fail();

    Debug.log(.INFO, "Write progress is: {d}", .{data.newProgress});
    _ = self;

    // self.progressBox.text.value = "Writing ISO... Do not eject the device.";
    // self.progressBox.setProgressTo(self.bgRect, data.newProgress);
    // self.progressBox.percentText.transform.x = self.bgRect.transform.relX(PADDING_LEFT) +
    //     (1 - SECTION_PADDING) * self.bgRect.transform.getWidth() - self.progressBox.percentText.getDimensions().width;

    return eventResult.succeed();
}

pub fn handleOnWriteVerificationProgressChanged(self: *DataFlasherUI, event: ComponentEvent) !EventResult {
    var eventResult = EventResult.init();
    const data = PrivilegedHelper.Events.onWriteVerificationProgressChanged.getData(event) orelse return eventResult.fail();

    Debug.log(.INFO, "Verification progress is: {d}", .{data.newProgress});
    _ = self;

    // self.progressBox.text.value = "Verifying device blocks...";
    // self.progressBox.setProgressTo(self.bgRect, data.newProgress);

    return eventResult.succeed();
}

pub fn handleAppResetRequest(self: *DataFlasherUI) EventResult {
    var eventResult = EventResult.init();

    {
        self.state.lock();
        defer self.state.unlock();

        self.state.data.isActive = false;
        self.state.data.device = null;
        self.state.data.isoPath = null;

        self.displayISOTextBuffer = std.mem.zeroes([std.fs.max_path_bytes]u8);
        self.displayDeviceTextBuffer = std.mem.zeroes([std.fs.max_path_bytes]u8);

        // setTextValue(&self.isoText, NULL_TEXT);
        // setTextValue(&self.deviceText, NULL_TEXT);

        // self.progressBox.text.value = "";
        // self.progressBox.value = 0;
        // self.progressBox.percentTextBuf = std.mem.zeroes([5]u8);
        // self.progressBox.percentText.value = "";
        // self.progressBox.rect.transform.w = 0;
        self.flashRequested = false;
    }

    // self.button.setEnabled(false);

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
                            Debug.log(.DEBUG, "Main DataFlasherUI View received a SetActive(true) command.", .{});
                            self.transform.size = .pixels(
                                WindowManager.relW(AppConfig.APP_UI_MODULE_PANEL_WIDTH_ACTIVE),
                                WindowManager.relH(AppConfig.APP_UI_MODULE_PANEL_HEIGHT_ACTIVE),
                            );

                            self.transform.position.y = .pixels(winRelY(AppConfig.APP_UI_MODULE_PANEL_Y));
                        },
                        false => {
                            Debug.log(.DEBUG, "Main DataFlasherUI View received a SetActive(false) command.", .{});
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

    pub const Styles = struct {
        //
        const HeaderTextbox: UIFramework.Textbox.TextboxStyle = .{
            .background = .{ .color = Color.transparent, .borderStyle = .{ .color = Color.transparent, .thickness = 0 }, .roundness = 0 },
            .text = .{ .font = .JERSEY10_REGULAR, .fontSize = 34, .textColor = Color.white },
            .lineSpacing = -5,
        };
    };
};
