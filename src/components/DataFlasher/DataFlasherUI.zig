const std = @import("std");
const rl = @import("raylib");
const freetracer_lib = @import("freetracer-lib");
const Debug = freetracer_lib.Debug;

const AppConfig = @import("../../config.zig");

const StorageDevice = freetracer_lib.StorageDevice;

const EventManager = @import("../../managers/EventManager.zig").EventManagerSingleton;
const ComponentName = EventManager.ComponentName.DATA_FLASHER_UI;

const ComponentFramework = @import("../framework/import/index.zig");
// const WorkerContext = @import("./WorkerContext.zig");

const DataFlasher = @import("./DataFlasher.zig");
const DeviceList = @import("../DeviceList/DeviceList.zig");
const DeviceListUI = @import("../DeviceList/DeviceListUI.zig");

const SECTION_PADDING: f32 = 0.1;
const PADDING_LEFT: f32 = SECTION_PADDING / 2;
const PADDING_RIGHT: f32 = PADDING_LEFT;

const TEXTURE_TILE_SIZE = 16;

const ICON_SIZE = 22;
const ICON_TEXT_GAP_X = ICON_SIZE * 1.5;
const ISO_ICON_POS_REL_X = PADDING_LEFT;
const ISO_ICON_POS_REL_Y = SECTION_PADDING;
const DEV_ICON_POS_REL_X = ISO_ICON_POS_REL_X;
const DEV_ICON_POS_REL_Y = ISO_ICON_POS_REL_Y + ISO_ICON_POS_REL_Y / 2;

const ITEM_GAP_Y = 8;
const STATUS_INDICATOR_SIZE: f32 = 20;

const DataFlasherUIState = struct {
    isActive: bool = false,
    isoPath: ?[:0]const u8 = null,
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
const Statusbox = UIFramework.Statuxbox;

const PrivilegedHelper = @import("../macos/PrivilegedHelper.zig");

const Styles = UIFramework.Styles;
const Color = UIFramework.Styles.Color;

const WindowManager = @import("../../managers/WindowManager.zig").WindowManagerSingleton;
const winRelX = WindowManager.relW;
const winRelY = WindowManager.relH;

const BgRectParams = struct {
    width: f32,
    color: rl.Color,
    borderColor: rl.Color,
};

const ProgressBox = struct {
    value: u64 = 0,
    text: Text = undefined,
    percentTextBuf: [5]u8 = undefined,
    percentText: Text = undefined,
    rect: Rectangle = undefined,

    pub fn draw(self: *ProgressBox) void {
        self.text.draw();
        self.percentText.draw();
        self.rect.draw();
    }

    pub fn setProgressTo(self: *ProgressBox, referenceRect: Rectangle, newValue: u64) void {
        self.value = newValue;

        const width: f32 = referenceRect.transform.getWidth();
        const progress: f32 = @floatFromInt(newValue);
        self.percentTextBuf = std.mem.zeroes([5]u8);
        self.percentText.value = "";
        self.percentText.value = @ptrCast(std.fmt.bufPrint(&self.percentTextBuf, "{d}%", .{progress}) catch "Err");
        self.rect.transform.w = (progress / 100) * (1 - SECTION_PADDING) * width;
    }
};

const StatusIndicator = struct {
    text: Text = undefined,
    box: Statusbox = undefined,

    pub fn init(text: [:0]const u8, size: f32) StatusIndicator {
        var statusBox = Statusbox.init(.{ .x = 0, .y = 0 }, size, .Primary);
        statusBox.switchState(.NONE);

        return StatusIndicator{
            .text = Text.init(text, .{ .x = 0, .y = 0 }, .{ .fontSize = 14 }),
            .box = statusBox,
        };
    }

    pub fn switchState(self: *StatusIndicator, newState: Statusbox.StatusboxState) void {
        self.box.switchState(newState);
    }

    pub fn calculateUI(self: *StatusIndicator, transform: Transform) void {
        self.text.transform.x = transform.x;
        self.text.transform.y = transform.y + transform.h / 2 - self.text.getDimensions().height / 2;
        self.box.setPosition(.{ .x = transform.x + transform.w - transform.h, .y = transform.y });
    }

    pub fn draw(self: *StatusIndicator) !void {
        self.text.draw();
        try self.box.draw();
    }
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
progressBox: ProgressBox = undefined,
displayISOTextBuffer: [std.fs.max_path_bytes]u8 = undefined,
displayDeviceTextBuffer: [std.fs.max_path_bytes]u8 = undefined,

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

pub fn start(self: *DataFlasherUI) !void {
    if (self.component == null) try self.initComponent(self.parent.asComponentPtr());

    if (self.component) |*component| {
        if (!EventManager.subscribe(ComponentName, component)) return error.UnableToSubscribeToEventManager;
    } else return error.UnableToSubscribeToEventManager;

    self.bgRect = Rectangle{
        .transform = .{
            .x = winRelX(0.5),
            .y = winRelY(AppConfig.APP_UI_MODULE_PANEL_Y),
            .w = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_INACTIVE),
            .h = winRelY(AppConfig.APP_UI_MODULE_PANEL_HEIGHT),
        },
        .style = .{
            .color = Styles.Color.darkGreen,
            .borderStyle = .{
                .color = Styles.Color.darkGreen,
            },
        },
        .rounded = true,
        .bordered = true,
    };

    // Get initial width of the preceding UI element
    try self.queryDeviceListUIDimensions();

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

    self.isoText = Text.init("NULL", .{ .x = 0, .y = 0 }, .{ .fontSize = 14 });
    self.deviceText = Text.init("NULL", .{ .x = 0, .y = 0 }, .{ .fontSize = 14 });

    self.headerLabel = Text.init("flash", .{ .x = self.bgRect.transform.x + 12, .y = self.bgRect.transform.relY(0.01) }, .{
        .font = .JERSEY10_REGULAR,
        .fontSize = 34,
        .textColor = Styles.Color.white,
    });

    self.uiSheetTexture = Texture.init(.BUTTON_UI, .{ .x = winRelX(1.5), .y = winRelY(1.5) });

    self.moduleImg = Texture.init(.DISK_IMAGE, .{ .x = 0, .y = 0 });
    self.moduleImg.transform.scale = 0.5;
    self.moduleImg.transform.x = self.bgRect.transform.relX(0.5) - self.moduleImg.transform.getWidth() / 2;
    self.moduleImg.transform.y = self.bgRect.transform.relY(0.5) - self.moduleImg.transform.getHeight() / 2;
    self.moduleImg.tint = .{ .r = 255, .g = 255, .b = 255, .a = 150 };

    self.statusSectionHeader = Text.init(
        "status",
        .{ .x = self.bgRect.transform.relX(PADDING_LEFT), .y = self.bgRect.transform.relY(0.26) },
        .{ .fontSize = 24, .font = .JERSEY10_REGULAR },
    );

    self.isoStatus = StatusIndicator.init("ISO validated & stream open", STATUS_INDICATOR_SIZE);
    self.deviceStatus = StatusIndicator.init("Device validated & stream open", STATUS_INDICATOR_SIZE);
    self.permissionsStatus = StatusIndicator.init("Freetracer has necessary permissions", STATUS_INDICATOR_SIZE);
    self.writeStatus = StatusIndicator.init("Write successfully completed", STATUS_INDICATOR_SIZE);
    self.verificationStatus = StatusIndicator.init("Written bytes successfuly verified", STATUS_INDICATOR_SIZE);

    self.progressBox = ProgressBox{
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

    self.displayISOTextBuffer = std.mem.zeroes([std.fs.max_path_bytes]u8);
    self.displayDeviceTextBuffer = std.mem.zeroes([std.fs.max_path_bytes]u8);
}

pub fn update(self: *DataFlasherUI) !void {
    try self.button.update();
}

pub fn draw(self: *DataFlasherUI) !void {
    self.state.lock();
    errdefer self.state.unlock();
    const isActive = self.state.data.isActive;
    self.state.unlock();

    self.bgRect.draw();
    self.headerLabel.draw();

    if (isActive) try self.drawActive() else try self.drawInactive();
}

fn drawActive(self: *DataFlasherUI) !void {
    self.isoText.draw();
    self.deviceText.draw();

    rl.drawTexturePro(
        self.uiSheetTexture.texture,
        .{ .x = TEXTURE_TILE_SIZE * 9, .y = TEXTURE_TILE_SIZE * 10, .width = TEXTURE_TILE_SIZE, .height = TEXTURE_TILE_SIZE },
        .{ .x = self.bgRect.transform.relX(ISO_ICON_POS_REL_X), .y = self.bgRect.transform.relY(ISO_ICON_POS_REL_Y), .width = ICON_SIZE, .height = ICON_SIZE },
        .{ .x = 0, .y = 0 },
        0,
        .white,
    );

    rl.drawTexturePro(
        self.uiSheetTexture.texture,
        .{ .x = TEXTURE_TILE_SIZE * 10, .y = TEXTURE_TILE_SIZE * 11, .width = TEXTURE_TILE_SIZE, .height = TEXTURE_TILE_SIZE },
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
    self.moduleImg.draw();
}

pub fn handleEvent(self: *DataFlasherUI, event: ComponentEvent) !EventResult {
    var eventResult = EventResult{
        .success = false,
        .validation = .FAILURE,
    };

    eventLoop: switch (event.hash) {
        //
        // Event: parent's authoritative state signal
        DataFlasher.Events.onActiveStateChanged.Hash => {
            //
            const data = DataFlasher.Events.onActiveStateChanged.getData(event) orelse break :eventLoop;

            eventResult.validate(.SUCCESS);

            {
                self.state.lock();
                defer self.state.unlock();
                self.state.data.isActive = data.isActive;
            }

            try self.queryDeviceListUIDimensions();

            switch (data.isActive) {
                true => {
                    Debug.log(.DEBUG, "DataFlasherUI: setting UI to ACTIVE.", .{});

                    var isoPath: [:0]const u8 = "NULL";
                    var device: ?*StorageDevice = null;
                    var areStateParamsAvailable: bool = false;

                    {
                        self.parent.state.lock();
                        defer self.parent.state.unlock();
                        isoPath = self.parent.state.data.isoPath orelse "NULL";
                        device = &self.parent.state.data.device.?;
                        areStateParamsAvailable = (self.parent.state.data.isoPath != null and self.parent.state.data.device != null);

                        if (areStateParamsAvailable) {
                            std.debug.assert(device != null);
                            std.debug.assert(isoPath.len > 2);
                            std.debug.assert(device.?.getBsdNameSlice().len > 2);
                        }
                    }

                    if (areStateParamsAvailable) self.button.setEnabled(true);

                    self.headerLabel.style.textColor = Color.white;

                    self.recalculateUI(.{
                        .width = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_ACTIVE),
                        .color = Color.activeGreen,
                        .borderColor = Color.white,
                    });

                    const tempText = Text.init(isoPath, .{ .x = winRelX(1.5), .y = winRelY(1.5) }, self.isoText.style);
                    const isoDims = tempText.getDimensions();
                    const availableWidth = (1 - SECTION_PADDING) * self.bgRect.transform.getWidth() - (ICON_SIZE + ICON_TEXT_GAP_X);
                    const widthDiff = availableWidth - isoDims.width;

                    Debug.log(.INFO, "isoPath width: {d}, widthDiff: {d}, activeWidth: {d}", .{ isoDims.width, widthDiff, (1 - SECTION_PADDING) * self.bgRect.transform.getWidth() });

                    if (widthDiff < 0) {
                        const d_widthDiff_d_isoWidth = @abs(widthDiff / isoDims.width);
                        const numCharsToObscure = @round(@as(f32, @floatFromInt(isoPath.len)) * d_widthDiff_d_isoWidth);
                        Debug.log(.DEBUG, "d_widthDiff_d_isoWidth = {d}, numCharsToObscure = {d}", .{ d_widthDiff_d_isoWidth, numCharsToObscure });

                        if (numCharsToObscure > @as(f32, @floatFromInt(isoPath.len - 16))) {
                            self.isoText.value = isoPath[isoPath.len - 16 ..];
                        } else {
                            const filler = "...";
                            const textMidPoint = isoPath.len / 2;
                            const startCharIdx = textMidPoint - @as(usize, @intFromFloat((numCharsToObscure) / 2));
                            const endCharIdx = startCharIdx + @as(usize, @intFromFloat(numCharsToObscure));
                            const remainingLen = isoPath.len - endCharIdx;

                            @memcpy(self.displayISOTextBuffer[0..startCharIdx], isoPath[0..startCharIdx]);
                            @memcpy(self.displayISOTextBuffer[startCharIdx .. startCharIdx + filler.len], filler);
                            @memcpy(self.displayISOTextBuffer[startCharIdx + filler.len .. startCharIdx + filler.len + remainingLen], isoPath[endCharIdx..]);

                            self.isoText.value = @ptrCast(std.mem.sliceTo(&self.displayISOTextBuffer, 0x00));
                        }

                        Debug.log(.DEBUG, "New display path is: {s}", .{self.isoText.value});
                    } else {
                        self.isoText.value = isoPath;
                    }

                    if (device) |dev| {
                        const devName = dev.getNameSlice();
                        const p1 = " (";
                        const bsdName = dev.getBsdNameSlice();
                        const p2 = ")";

                        @memcpy(self.displayDeviceTextBuffer[0..devName.len], devName);
                        @memcpy(self.displayDeviceTextBuffer[devName.len .. devName.len + p1.len], p1);
                        @memcpy(self.displayDeviceTextBuffer[devName.len + p1.len .. devName.len + p1.len + bsdName.len], bsdName);
                        @memcpy(self.displayDeviceTextBuffer[devName.len + p1.len + bsdName.len .. devName.len + p1.len + bsdName.len + p2.len], p2);

                        self.deviceText.value = @ptrCast(std.mem.sliceTo(&self.displayDeviceTextBuffer, 0x00));
                    }
                },

                false => {
                    Debug.log(.DEBUG, "DataFlasherUI: setting UI to INACTIVE.", .{});

                    self.headerLabel.style.textColor = Color.lightGray;
                    self.button.setEnabled(false);

                    self.recalculateUI(.{
                        .width = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_INACTIVE),
                        .color = Color.darkBlueGray,
                        .borderColor = Color.transparentDark,
                    });
                },
            }
        },

        PrivilegedHelper.Events.onHelperISOFileOpenSuccess.Hash => {
            self.isoStatus.switchState(.SUCCESS);
        },

        PrivilegedHelper.Events.onHelperISOFileOpenFailed.Hash => {
            self.isoStatus.switchState(.FAILURE);
        },

        PrivilegedHelper.Events.onHelperDeviceOpenSuccess.Hash => {
            self.deviceStatus.switchState(.SUCCESS);
            self.permissionsStatus.switchState(.SUCCESS);
        },

        PrivilegedHelper.Events.onHelperDeviceOpenFailed.Hash => {
            self.deviceStatus.switchState(.FAILURE);
            self.permissionsStatus.switchState(.FAILURE);
        },

        PrivilegedHelper.Events.onHelperWriteSuccess.Hash => {
            self.writeStatus.switchState(.SUCCESS);
        },

        PrivilegedHelper.Events.onHelperWriteFailed.Hash => {
            self.writeStatus.switchState(.FAILURE);
        },

        PrivilegedHelper.Events.onHelperVerificationSuccess.Hash => {
            self.verificationStatus.switchState(.SUCCESS);
            self.progressBox.text.value = "Finished writing ISO. You may now eject the device.";
        },

        PrivilegedHelper.Events.onHelperVerificationFailed.Hash => {
            self.verificationStatus.switchState(.FAILURE);
        },

        PrivilegedHelper.Events.onISOWriteProgressChanged.Hash => {
            const data = PrivilegedHelper.Events.onISOWriteProgressChanged.getData(event) orelse break :eventLoop;

            Debug.log(.INFO, "Write progress is: {d}", .{data.newProgress});

            self.progressBox.text.value = "Writing ISO... Do not eject the device.";
            self.progressBox.setProgressTo(self.bgRect, data.newProgress);
            self.progressBox.percentText.transform.x = self.bgRect.transform.relX(PADDING_LEFT) +
                (1 - SECTION_PADDING) * self.bgRect.transform.getWidth() - self.progressBox.percentText.getDimensions().width;

            eventResult.validate(.SUCCESS);
        },

        PrivilegedHelper.Events.onWriteVerificationProgressChanged.Hash => {
            const data = PrivilegedHelper.Events.onWriteVerificationProgressChanged.getData(event) orelse break :eventLoop;

            Debug.log(.INFO, "Verification progress is: {d}", .{data.newProgress});

            self.progressBox.text.value = "Verifying device blocks...";
            self.progressBox.setProgressTo(self.bgRect, data.newProgress);

            eventResult.validate(.SUCCESS);
        },

        else => {},
    }

    return eventResult;
}
pub fn dispatchComponentAction(self: *DataFlasherUI) void {
    _ = self;
}

pub fn deinit(self: *DataFlasherUI) void {
    _ = self;
}

fn queryDeviceListUIDimensions(self: *DataFlasherUI) !void {
    const queryDimensionsEvent = DeviceListUI.Events.onUITransformQueried.create(self.asComponentPtr(), null);
    const eventResult = try EventManager.signal("device_list_ui", queryDimensionsEvent);

    if (!eventResult.success or eventResult.data == null) return error.DataFlasherUICouldNotObtainInitialUIDimensions;

    if (eventResult.data) |dimensionsData| {
        const deviceListUIData: *DeviceListUI.Events.onUITransformQueried.Response = @ptrCast(@alignCast(dimensionsData));
        self.bgRect.transform.x = deviceListUIData.transform.x + deviceListUIData.transform.getWidth() + 20;
        self.allocator.destroy(deviceListUIData);
    }
}

fn recalculateUI(self: *DataFlasherUI, bgRectParams: BgRectParams) void {
    Debug.log(.DEBUG, "DataFlasherUI: updating bgRect properties!", .{});

    self.bgRect.transform.w = bgRectParams.width;
    self.bgRect.style.color = bgRectParams.color;
    self.bgRect.style.borderStyle.color = bgRectParams.borderColor;

    const leftPadding = self.bgRect.transform.relX(PADDING_LEFT);
    const centerX = self.bgRect.transform.relX(0.5);

    self.headerLabel.transform.x = self.bgRect.transform.x + 12;
    self.headerLabel.transform.y = self.bgRect.transform.relY(0.01);

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
