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

const UIFramework = @import("../ui/import/index.zig");
const Button = UIFramework.Button;
const Checkbox = UIFramework.Checkbox;
const Transform = UIFramework.Primitives.Transform;
const Rectangle = UIFramework.Primitives.Rectangle;
const Text = UIFramework.Primitives.Text;
const Texture = UIFramework.Primitives.Texture;
const Statusbox = UIFramework.Statusbox;
const Progressbox = UIFramework.Progressbox;
const StatusIndicator = UIFramework.StatusIndicator;
const Layout = UIFramework.Layout;

const PrivilegedHelper = @import("../macos/PrivilegedHelper.zig");

const Styles = UIFramework.Styles;
const Color = UIFramework.Styles.Color;

const WindowManager = @import("../../managers/WindowManager.zig").WindowManagerSingleton;
const winRelX = WindowManager.relW;
const winRelY = WindowManager.relH;

const NULL_TEXT: [:0]const u8 = "NULL";

const BgRectParams = struct {
    width: f32,
    color: rl.Color,
    borderColor: rl.Color,
};

const MAX_PATH_DISPLAY_LENGTH = 40;

// Component-agnostic props
state: ComponentState,
component: ?Component = null,
worker: ?ComponentWorker = null,

// Component-specific, unique props
allocator: std.mem.Allocator,
parent: *DataFlasher,
bgRect: Rectangle = undefined,
headerLabel: Text = undefined,
moduleImg: Texture = undefined,
uiSheetTexture: Texture = undefined,
button: Button = undefined,
isoText: Text = undefined,
deviceText: Text = undefined,
progressBox: Progressbox = undefined,
displayISOTextBuffer: [std.fs.max_path_bytes]u8 = undefined,
displayDeviceTextBuffer: [std.fs.max_path_bytes]u8 = undefined,
frame: Layout.Bounds = undefined,

flashRequested: bool = false,

statusSectionHeader: Text = undefined,
isoStatus: StatusIndicator = undefined,
deviceStatus: StatusIndicator = undefined,
permissionsStatus: StatusIndicator = undefined,
writeStatus: StatusIndicator = undefined,
verificationStatus: StatusIndicator = undefined,

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

    try self.initBgRect();
    try self.initFlashButton();
    self.initModuleLabels();
    self.initTextures();
    self.initStatusIndicators();
    self.initProgressbox();

    self.recalculateUI(.{
        .width = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_INACTIVE),
        .color = Styles.Color.themeSectionBg,
        .borderColor = Styles.Color.themeSectionBorder,
    });
}

pub fn update(self: *DataFlasherUI) !void {
    try self.button.update();
}

/// Draws the module frame and then the appropriate active/inactive presentation.
pub fn draw(self: *DataFlasherUI) !void {
    self.state.lock();
    defer self.state.unlock();
    const isActive = self.state.data.isActive;

    self.bgRect.transform = self.frame.resolve();

    self.bgRect.draw();
    self.headerLabel.draw();

    if (isActive) try self.drawActive() else try self.drawInactive();
}

/// Render routine when the module is active; expects state lock not held by caller.
fn drawActive(self: *DataFlasherUI) !void {
    self.applyLayoutFromBounds();

    self.isoText.draw();
    self.deviceText.draw();
    // TODO: Create separate label Component with optional icon
    rl.drawTexturePro(
        self.uiSheetTexture.texture,
        ICON_SRC_ISO,
        .{ .x = self.bgRect.transform.relX(ISO_ICON_POS_REL_X), .y = self.bgRect.transform.relY(ISO_ICON_POS_REL_Y), .width = ICON_SIZE, .height = ICON_SIZE },
        .{ .x = 0, .y = 0 },
        0,
        .white,
    );

    rl.drawTexturePro(
        self.uiSheetTexture.texture,
        ICON_SRC_DEVICE,
        .{ .x = self.bgRect.transform.relX(DEV_ICON_POS_REL_X), .y = self.bgRect.transform.relY(DEV_ICON_POS_REL_Y), .width = ICON_SIZE, .height = ICON_SIZE },
        .{ .x = 0, .y = 0 },
        0,
        .white,
    );

    if (self.flashRequested) {
        self.statusSectionHeader.draw();
        try self.isoStatus.draw();
        try self.deviceStatus.draw();
        try self.permissionsStatus.draw();
        try self.writeStatus.draw();
        try self.verificationStatus.draw();
    }

    self.progressBox.draw();

    try self.button.draw();
}

fn drawInactive(self: *DataFlasherUI) !void {
    self.applyLayoutFromBounds();
    self.moduleImg.draw();
}

/// Consumes DataFlasher/PrivilegedHelper events; returns failure for unknown events.
pub fn handleEvent(self: *DataFlasherUI, event: ComponentEvent) !EventResult {
    var eventResult = EventResult.init();

    return switch (event.hash) {
        //
        // Event: parent's authoritative state signal
        DataFlasher.Events.onActiveStateChanged.Hash => try self.handleOnActiveStateChanged(event),

        PrivilegedHelper.Events.onHelperISOFileOpenSuccess.Hash => {
            self.isoStatus.switchState(.SUCCESS);
            return eventResult.succeed();
        },

        PrivilegedHelper.Events.onHelperISOFileOpenFailed.Hash => {
            self.isoStatus.switchState(.FAILURE);
            return eventResult.succeed();
        },

        PrivilegedHelper.Events.onHelperDeviceOpenSuccess.Hash => {
            self.deviceStatus.switchState(.SUCCESS);
            self.permissionsStatus.switchState(.SUCCESS);
            return eventResult.succeed();
        },

        PrivilegedHelper.Events.onHelperDeviceOpenFailed.Hash => {
            self.deviceStatus.switchState(.FAILURE);
            self.permissionsStatus.switchState(.FAILURE);
            return eventResult.succeed();
        },

        PrivilegedHelper.Events.onHelperWriteSuccess.Hash => {
            self.writeStatus.switchState(.SUCCESS);
            return eventResult.succeed();
        },

        PrivilegedHelper.Events.onHelperWriteFailed.Hash => {
            self.writeStatus.switchState(.FAILURE);
            return eventResult.succeed();
        },

        PrivilegedHelper.Events.onHelperVerificationSuccess.Hash => {
            self.verificationStatus.switchState(.SUCCESS);
            self.progressBox.text.value = "Finished writing ISO. You may now eject the device.";
            return eventResult.succeed();
        },

        PrivilegedHelper.Events.onHelperVerificationFailed.Hash => {
            self.verificationStatus.switchState(.FAILURE);
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
    self.button.deinit();
}

fn subscribeToEvents(self: *DataFlasherUI) !void {
    if (self.component) |*component| {
        if (!EventManager.subscribe(ComponentName, component)) return error.UnableToSubscribeToEventManager;
    } else return error.UnableToSubscribeToEventManager;
}

fn initFlashButton(self: *DataFlasherUI) !void {
    self.button = Button.init(
        "Flash",
        null,
        self.bgRect.transform.getPosition(),
        .Primary,
        .{ .context = self.parent, .function = DataFlasher.flashISOtoDeviceWrapper.call },
        self.allocator,
    );
    self.button.params.disableOnClick = true;
    self.button.setEnabled(false);
    try self.button.start();
    self.button.setPosition(.{
        .x = self.bgRect.transform.relX(0.5) - @divTrunc(self.button.rect.transform.getWidth(), 2),
        .y = self.bgRect.transform.relY(0.9) - @divTrunc(self.button.rect.transform.getHeight(), 2),
    });
    self.button.rect.rounded = true;
}

fn initBgRect(self: *DataFlasherUI) !void {
    const deviceListTransform: *Transform = try UIFramework.utils.queryComponentTransform(DeviceListUI);

    self.frame = Layout.Bounds.relative(
        deviceListTransform,
        .{
            .x = Layout.UnitValue.mix(1.0, AppConfig.APP_UI_MODULE_GAP_X),
            .y = Layout.UnitValue.pixels(0),
        },
        .{
            .width = Layout.UnitValue.pixels(winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_INACTIVE)),
            .height = Layout.UnitValue.pixels(winRelY(AppConfig.APP_UI_MODULE_PANEL_HEIGHT)),
        },
    );

    self.bgRect = Rectangle{
        .transform = self.frame.resolve(),
        .style = .{
            .color = Styles.Color.themeSectionBg,
            .borderStyle = .{
                .color = Styles.Color.themeSectionBorder,
            },
        },
        .rounded = true,
        .bordered = true,
    };
}

fn initModuleLabels(self: *DataFlasherUI) void {
    self.displayISOTextBuffer = std.mem.zeroes([std.fs.max_path_bytes]u8);
    self.displayDeviceTextBuffer = std.mem.zeroes([std.fs.max_path_bytes]u8);
    self.isoText = Text.init("NULL", .{ .x = 0, .y = 0 }, .{ .fontSize = 14 });
    self.deviceText = Text.init("NULL", .{ .x = 0, .y = 0 }, .{ .fontSize = 14 });

    self.headerLabel = Text.init("flash", .{ .x = self.bgRect.transform.x + 12, .y = self.bgRect.transform.relY(0.01) }, .{
        .font = .JERSEY10_REGULAR,
        .fontSize = 34,
        .textColor = Styles.Color.white,
    });

    self.statusSectionHeader = Text.init(
        "status",
        .{ .x = self.bgRect.transform.relX(PADDING_LEFT), .y = self.bgRect.transform.relY(0.26) },
        .{ .fontSize = 24, .font = .JERSEY10_REGULAR },
    );
}

fn initStatusIndicators(self: *DataFlasherUI) void {
    self.isoStatus = StatusIndicator.init("ISO validated & stream open", STATUS_INDICATOR_SIZE);
    self.deviceStatus = StatusIndicator.init("Device validated & stream open", STATUS_INDICATOR_SIZE);
    self.permissionsStatus = StatusIndicator.init("Freetracer has necessary permissions", STATUS_INDICATOR_SIZE);
    self.writeStatus = StatusIndicator.init("Write successfully completed", STATUS_INDICATOR_SIZE);
    self.verificationStatus = StatusIndicator.init("Written bytes successfuly verified", STATUS_INDICATOR_SIZE);
}

fn initTextures(self: *DataFlasherUI) void {
    self.uiSheetTexture = Texture.init(.BUTTON_UI, .{ .x = winRelX(1.5), .y = winRelY(1.5) });

    self.moduleImg = Texture.init(.DISK_IMAGE, .{ .x = 0, .y = 0 });
    self.moduleImg.transform.scale = 0.5;
    self.moduleImg.transform.x = self.bgRect.transform.relX(0.5) - self.moduleImg.transform.getWidth() / 2;
    self.moduleImg.transform.y = self.bgRect.transform.relY(0.5) - self.moduleImg.transform.getHeight() / 2;
    self.moduleImg.tint = .{ .r = 255, .g = 255, .b = 255, .a = 150 };
}

fn initProgressbox(self: *DataFlasherUI) void {
    self.progressBox = Progressbox{
        .text = Text.init("", .{
            .x = self.bgRect.transform.relX(PADDING_LEFT),
            .y = self.bgRect.transform.relY(0.75),
        }, .{
            .font = .ROBOTO_REGULAR,
            .fontSize = 14,
            .textColor = .white,
        }),
        .percentText = Text.init(
            "",
            .{ .x = self.bgRect.transform.relX(PADDING_LEFT), .y = self.bgRect.transform.relY(0.75) },
            .{ .fontSize = 14 },
        ),
        .value = 0,
        .percentTextBuf = std.mem.zeroes([5]u8),
        .rect = .{
            .bordered = true,
            .rounded = true,
            .style = .{ .color = Color.white, .borderStyle = .{ .color = Color.white, .thickness = 2.00 } },
            .transform = .{
                .x = self.bgRect.transform.relX(0.2),
                .y = self.bgRect.transform.relY(0.7),
                .h = 18.0,
                .w = 0.0,
            },
        },
    };
}

/// Repositions child elements after background sizing/color changes.
fn recalculateUI(self: *DataFlasherUI, bgRectParams: BgRectParams) void {
    Debug.log(.DEBUG, "DataFlasherUI: updating bgRect properties!", .{});

    self.frame.size.width = Layout.UnitValue.pixels(bgRectParams.width);
    self.bgRect.transform = self.frame.resolve();

    self.bgRect.style.color = bgRectParams.color;
    self.bgRect.style.borderStyle.color = bgRectParams.borderColor;

    self.applyLayoutFromBounds();
}

fn applyLayoutFromBounds(self: *DataFlasherUI) void {
    const leftPadding = self.bgRect.transform.relX(PADDING_LEFT);
    const centerX = self.bgRect.transform.relX(0.5);

    self.headerLabel.transform.x = self.bgRect.transform.x + HEADER_LABEL_OFFSET_X;
    self.headerLabel.transform.y = self.bgRect.transform.relY(HEADER_LABEL_REL_Y);

    self.moduleImg.transform.x = centerX - self.moduleImg.transform.getWidth() / 2;
    self.moduleImg.transform.y = self.bgRect.transform.relY(0.5) - self.moduleImg.transform.getHeight() / 2;

    self.isoText.transform.x = self.bgRect.transform.relX(ISO_ICON_POS_REL_X) + ICON_TEXT_GAP_X;
    self.isoText.transform.y = self.bgRect.transform.relY(ISO_ICON_POS_REL_Y) + self.isoText.getDimensions().height / 8;

    self.deviceText.transform.x = self.bgRect.transform.relX(DEV_ICON_POS_REL_X) + ICON_TEXT_GAP_X;
    self.deviceText.transform.y = self.bgRect.transform.relY(DEV_ICON_POS_REL_Y) + self.deviceText.getDimensions().height / 8;

    self.statusSectionHeader.transform.x = self.bgRect.transform.relX(PADDING_LEFT);

    self.isoStatus.calculateUI(.{
        .x = self.bgRect.transform.relX(PADDING_LEFT),
        .y = self.statusSectionHeader.transform.y + self.statusSectionHeader.getDimensions().height + ITEM_GAP_Y,
        .w = (1 - SECTION_PADDING) * self.bgRect.transform.getWidth(),
        .h = STATUS_INDICATOR_SIZE,
    });

    self.deviceStatus.calculateUI(.{
        .x = self.bgRect.transform.relX(PADDING_LEFT),
        .y = self.isoStatus.box.transform.y + STATUS_INDICATOR_SIZE + ITEM_GAP_Y,
        .w = (1 - SECTION_PADDING) * self.bgRect.transform.getWidth(),
        .h = STATUS_INDICATOR_SIZE,
    });

    self.permissionsStatus.calculateUI(.{
        .x = self.bgRect.transform.relX(PADDING_LEFT),
        .y = self.deviceStatus.box.transform.y + STATUS_INDICATOR_SIZE + ITEM_GAP_Y,
        .w = (1 - SECTION_PADDING) * self.bgRect.transform.getWidth(),
        .h = STATUS_INDICATOR_SIZE,
    });

    self.writeStatus.calculateUI(.{
        .x = self.bgRect.transform.relX(PADDING_LEFT),
        .y = self.permissionsStatus.box.transform.y + STATUS_INDICATOR_SIZE + ITEM_GAP_Y,
        .w = (1 - SECTION_PADDING) * self.bgRect.transform.getWidth(),
        .h = STATUS_INDICATOR_SIZE,
    });

    self.verificationStatus.calculateUI(.{
        .x = self.bgRect.transform.relX(PADDING_LEFT),
        .y = self.writeStatus.box.transform.y + STATUS_INDICATOR_SIZE + ITEM_GAP_Y,
        .w = (1 - SECTION_PADDING) * self.bgRect.transform.getWidth(),
        .h = STATUS_INDICATOR_SIZE,
    });

    self.progressBox.text.transform.x = leftPadding;
    self.progressBox.text.transform.y = self.verificationStatus.box.transform.y + self.verificationStatus.box.transform.h + 2 * ITEM_GAP_Y;
    self.progressBox.percentText.transform.x = leftPadding + (1 - SECTION_PADDING) * self.bgRect.transform.getWidth() - self.progressBox.percentText.getDimensions().width;
    self.progressBox.percentText.transform.y = self.progressBox.text.transform.y;
    self.progressBox.rect.transform.x = leftPadding;
    self.progressBox.rect.transform.y = self.progressBox.text.transform.y + self.progressBox.text.getDimensions().height + 2.5 * ITEM_GAP_Y;

    self.button.setPosition(.{
        .x = centerX - self.button.rect.transform.getWidth() / 2,
        .y = self.button.rect.transform.y,
    });
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

    {
        self.state.lock();
        defer self.state.unlock();
        self.state.data.isActive = data.isActive;
    }

    // self.bgRect.transform.x = transform.x + transform.w + AppConfig.APP_UI_MODULE_GAP_X;

    switch (data.isActive) {
        true => {
            Debug.log(.DEBUG, "DataFlasherUI: setting UI to ACTIVE.", .{});

            var isoPath: [:0]const u8 = NULL_TEXT;
            var device: ?StorageDevice = null;
            var hasImagePath = false;
            var hasDevice = false;

            {
                self.parent.state.lock();
                defer self.parent.state.unlock();
                if (self.parent.state.data.isoPath) |path| {
                    isoPath = path;
                    hasImagePath = true;
                }
                if (self.parent.state.data.device) |dev| {
                    device = dev;
                    hasDevice = true;
                }
            }

            const areStateParamsAvailable = hasImagePath and hasDevice;
            self.button.setEnabled(areStateParamsAvailable);

            self.headerLabel.style.textColor = Color.white;

            self.recalculateUI(.{
                .width = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_ACTIVE),
                .color = Color.themeSectionBg,
                .borderColor = Color.themeSectionBorder,
            });

            const tempText = Text.init(isoPath, .{ .x = winRelX(1.5), .y = winRelY(1.5) }, self.isoText.style);
            const isoDims = tempText.getDimensions();
            const availableWidth = (1 - SECTION_PADDING) * self.bgRect.transform.getWidth() - (ICON_SIZE + ICON_TEXT_GAP_X);

            if (isoDims.width > availableWidth) {
                self.isoText.value = ellipsizePath(self.displayISOTextBuffer[0..], isoPath, MAX_PATH_DISPLAY_LENGTH);
                Debug.log(.DEBUG, "DataFlasherUI: truncated ISO path for display", .{});
            } else {
                const isoBuffer = self.displayISOTextBuffer[0..];
                self.isoText.value = std.fmt.bufPrintZ(isoBuffer, "{s}", .{isoPath}) catch blk: {
                    Debug.log(.ERROR, "DataFlasherUI: failed to cache ISO path for display.", .{});
                    break :blk NULL_TEXT;
                };
            }

            if (device) |dev| {
                self.deviceText.value = formatDeviceLabel(self.displayDeviceTextBuffer[0..], dev.getNameSlice(), dev.getBsdNameSlice());
            } else {
                self.deviceText.value = NULL_TEXT;
            }

            return eventResult.succeed();
        },

        false => {
            Debug.log(.DEBUG, "DataFlasherUI: setting UI to INACTIVE.", .{});

            self.headerLabel.style.textColor = Color.lightGray;
            self.button.setEnabled(false);

            self.recalculateUI(.{
                .width = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_INACTIVE),
                .color = Color.themeSectionBg,
                .borderColor = Color.themeSectionBorder,
            });

            return eventResult.succeed();
        },
    }
}

pub fn handleOnISOWriteProgressChanged(self: *DataFlasherUI, event: ComponentEvent) !EventResult {
    var eventResult = EventResult.init();
    const data = PrivilegedHelper.Events.onISOWriteProgressChanged.getData(event) orelse return eventResult.fail();

    Debug.log(.INFO, "Write progress is: {d}", .{data.newProgress});

    self.progressBox.text.value = "Writing ISO... Do not eject the device.";
    self.progressBox.setProgressTo(self.bgRect, data.newProgress);
    self.progressBox.percentText.transform.x = self.bgRect.transform.relX(PADDING_LEFT) +
        (1 - SECTION_PADDING) * self.bgRect.transform.getWidth() - self.progressBox.percentText.getDimensions().width;

    return eventResult.succeed();
}

pub fn handleOnWriteVerificationProgressChanged(self: *DataFlasherUI, event: ComponentEvent) !EventResult {
    var eventResult = EventResult.init();
    const data = PrivilegedHelper.Events.onWriteVerificationProgressChanged.getData(event) orelse return eventResult.fail();

    Debug.log(.INFO, "Verification progress is: {d}", .{data.newProgress});

    self.progressBox.text.value = "Verifying device blocks...";
    self.progressBox.setProgressTo(self.bgRect, data.newProgress);

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

        self.isoText.value = NULL_TEXT;
        self.deviceText.value = NULL_TEXT;

        self.progressBox.text.value = "";
        self.progressBox.value = 0;
        self.progressBox.percentTextBuf = std.mem.zeroes([5]u8);
        self.progressBox.percentText.value = "";
        self.progressBox.rect.transform.w = 0;
        self.flashRequested = false;
    }

    self.headerLabel.style.textColor = Color.lightGray;
    self.button.setEnabled(false);

    self.recalculateUI(.{
        .width = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_INACTIVE),
        .color = Color.themeSectionBg,
        .borderColor = Color.themeSectionBorder,
    });

    return eventResult.succeed();
}
