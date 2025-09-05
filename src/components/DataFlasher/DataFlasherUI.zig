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

const ProgressBox = struct {
    value: i64 = 0,
    text: Text = undefined,
    percentTextBuf: [4]u8 = undefined,
    percentText: Text = undefined,
    rect: Rectangle = undefined,

    pub fn draw(self: *ProgressBox) void {
        self.text.draw();
        self.percentText.draw();
        self.rect.draw();
    }

    pub fn setProgressTo(self: *ProgressBox, referenceRect: Rectangle, newValue: i64) void {
        self.value = newValue;

        const width: f32 = referenceRect.transform.getWidth();
        const progress: f32 = @floatFromInt(newValue);
        self.percentTextBuf = std.mem.zeroes([4]u8);
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
button: Button = undefined,
isoText: Text = undefined,
deviceText: Text = undefined,
progressBox: ProgressBox = undefined,
buffer: [MAX_PATH_DISPLAY_LENGTH]u8 = undefined,
// operationInProgress: bool = false,

statusSectionHeader: Text = undefined,
isoStatus: StatusIndicator = undefined,
deviceStatus: StatusIndicator = undefined,
permissionsStatus: StatusIndicator = undefined,
writeStatus: StatusIndicator = undefined,
verificationStatus: StatusIndicator = undefined,

const BgRectParams = struct {
    width: f32,
    color: rl.Color,
    borderColor: rl.Color,
};

const statusIndicatorSize: f32 = 20;
const perc_relPaddingLeft: f32 = 0.05;
const statusIndicatorGapY: f32 = 8;

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
    self.component = try Component.init(self, &ComponentImplementation.vtable, parent);
}

pub fn start(self: *DataFlasherUI) !void {
    if (self.component == null) try self.initComponent(self.parent.asComponentPtr());

    if (self.component) |*component| {
        if (!EventManager.subscribe(ComponentName, component)) return error.UnableToSubscribeToEventManager;
    } else return error.UnableToSubscribeToEventManager;

    self.bgRect = Rectangle{
        .transform = .{
            .x = winRelX(0.5),
            .y = winRelY(0.2),
            .w = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_INACTIVE),
            .h = winRelY(AppConfig.APP_UI_MODULE_PANEL_HEIGHT),
        },
        .style = .{
            .color = Styles.Color.transparentDark,
            .borderStyle = .{
                .color = Styles.Color.transparentDark,
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
    );
    self.button.params.disableOnClick = true;
    self.button.setEnabled(false);
    try self.button.start();
    self.button.setPosition(.{
        .x = self.bgRect.transform.relX(0.5) - @divTrunc(self.button.rect.transform.getWidth(), 2),
        .y = self.bgRect.transform.relY(0.9) - @divTrunc(self.button.rect.transform.getHeight(), 2),
    });
    self.button.rect.rounded = true;

    self.isoText = Text.init("NULL", .{
        .x = self.bgRect.transform.relX(0.05),
        .y = self.bgRect.transform.relY(0.1),
    }, .{
        .fontSize = 14,
    });

    self.deviceText = Text.init("NULL", .{ .x = self.bgRect.transform.relX(0.05), .y = self.bgRect.transform.relY(0.15) }, .{ .fontSize = 14 });

    self.headerLabel = Text.init("flash", .{ .x = self.bgRect.transform.x + 12, .y = self.bgRect.transform.relY(0.01) }, .{
        .font = .JERSEY10_REGULAR,
        .fontSize = 34,
        .textColor = Styles.Color.white,
    });

    self.moduleImg = Texture.init(.DISK_IMAGE, .{ .x = 0, .y = 0 });
    self.moduleImg.transform.scale = 0.5;
    self.moduleImg.transform.x = self.bgRect.transform.relX(0.5) - self.moduleImg.transform.getWidth() / 2;
    self.moduleImg.transform.y = self.bgRect.transform.relY(0.5) - self.moduleImg.transform.getHeight() / 2;
    self.moduleImg.tint = .{ .r = 255, .g = 255, .b = 255, .a = 150 };

    self.statusSectionHeader = Text.init(
        "status",
        .{ .x = self.bgRect.transform.relX(perc_relPaddingLeft), .y = self.bgRect.transform.relY(0.26) },
        .{ .fontSize = 24, .font = .JERSEY10_REGULAR },
    );

    self.isoStatus = StatusIndicator.init("ISO validated & stream open", statusIndicatorSize);
    self.deviceStatus = StatusIndicator.init("Device validated & stream open", statusIndicatorSize);
    self.permissionsStatus = StatusIndicator.init("Freetracer has necessary permissions", statusIndicatorSize);
    self.writeStatus = StatusIndicator.init("Write successfully completed", statusIndicatorSize);
    self.verificationStatus = StatusIndicator.init("Written bytes successfuly verified", statusIndicatorSize);

    self.progressBox = ProgressBox{
        .text = Text.init("", .{
            .x = self.bgRect.transform.relX(0.05),
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
        .percentTextBuf = std.mem.zeroes([4]u8),
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
    self.progressBox.draw();

    self.statusSectionHeader.draw();
    try self.isoStatus.draw();
    try self.deviceStatus.draw();
    try self.permissionsStatus.draw();
    try self.writeStatus.draw();
    try self.verificationStatus.draw();

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

                    // const maxTextWidth = (1 - SECTION_PADDING) * self.bgRect.transform.getWidth();
                    self.isoText.value = isoPath;
                    // // const textWidth = self.isoText.getDimensions().width;
                    // // const characterCount = @divExact(@as(f32, @floatFromInt(self.isoText.font.baseSize)), textWidth);
                    // // _ = characterCount;
                    // // (maxTextWidth - textWidth) / self.isoText.font.recs.*.width;
                    //
                    // if (self.isoText.getDimensions().width > maxTextWidth) {
                    //     @memcpy(self.buffer[0..20], self.parent.state.data.isoPath.?[0..20]);
                    //     @memcpy(self.buffer[20..40], self.parent.state.data.isoPath.?[isoPath.len - 20 .. isoPath.len]);
                    //     self.isoText.value = @ptrCast(self.buffer[0..40]);
                    // }

                    self.deviceText.value = device.?.getBsdNameSlice();

                    if (areStateParamsAvailable) self.button.setEnabled(true);

                    self.headerLabel.style.textColor = Color.white;

                    self.recalculateUI(.{
                        .width = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_ACTIVE),
                        .color = Color.blueGray,
                        .borderColor = Color.white,
                    });
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

    self.isoText.transform.x = leftPadding;
    self.isoText.transform.y = self.bgRect.transform.relY(0.13);

    self.deviceText.transform.x = leftPadding;
    self.deviceText.transform.y = self.isoText.transform.y + self.isoText.transform.getHeight() + 10;

    self.statusSectionHeader.transform.x = self.bgRect.transform.relX(perc_relPaddingLeft);

    self.isoStatus.calculateUI(.{
        .x = self.bgRect.transform.relX(perc_relPaddingLeft),
        .y = self.statusSectionHeader.transform.y + self.statusSectionHeader.getDimensions().height + statusIndicatorGapY,
        .w = (1 - SECTION_PADDING) * self.bgRect.transform.getWidth(),
        .h = statusIndicatorSize,
    });

    self.deviceStatus.calculateUI(.{
        .x = self.bgRect.transform.relX(perc_relPaddingLeft),
        .y = self.isoStatus.box.transform.y + statusIndicatorSize + statusIndicatorGapY,
        .w = (1 - SECTION_PADDING) * self.bgRect.transform.getWidth(),
        .h = statusIndicatorSize,
    });

    self.permissionsStatus.calculateUI(.{
        .x = self.bgRect.transform.relX(perc_relPaddingLeft),
        .y = self.deviceStatus.box.transform.y + statusIndicatorSize + statusIndicatorGapY,
        .w = (1 - SECTION_PADDING) * self.bgRect.transform.getWidth(),
        .h = statusIndicatorSize,
    });

    self.writeStatus.calculateUI(.{
        .x = self.bgRect.transform.relX(perc_relPaddingLeft),
        .y = self.permissionsStatus.box.transform.y + statusIndicatorSize + statusIndicatorGapY,
        .w = (1 - SECTION_PADDING) * self.bgRect.transform.getWidth(),
        .h = statusIndicatorSize,
    });

    self.verificationStatus.calculateUI(.{
        .x = self.bgRect.transform.relX(perc_relPaddingLeft),
        .y = self.writeStatus.box.transform.y + statusIndicatorSize + statusIndicatorGapY,
        .w = (1 - SECTION_PADDING) * self.bgRect.transform.getWidth(),
        .h = statusIndicatorSize,
    });

    self.progressBox.text.transform.x = leftPadding;
    self.progressBox.text.transform.y = self.verificationStatus.box.transform.y + self.verificationStatus.box.transform.h + 2 * statusIndicatorGapY;
    self.progressBox.percentText.transform.x = leftPadding + (1 - SECTION_PADDING) * self.bgRect.transform.getWidth() - self.progressBox.percentText.getDimensions().width;
    self.progressBox.percentText.transform.y = self.progressBox.text.transform.y;
    self.progressBox.rect.transform.x = leftPadding;
    self.progressBox.rect.transform.y = self.progressBox.text.transform.y + self.progressBox.text.getDimensions().height + 2.5 * statusIndicatorGapY;

    self.button.setPosition(.{
        .x = centerX - self.button.rect.transform.getWidth() / 2,
        .y = self.button.rect.transform.y,
    });
}

pub const ComponentImplementation = ComponentFramework.ImplementComponent(DataFlasherUI);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;
