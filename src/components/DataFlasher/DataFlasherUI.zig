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

const Styles = UIFramework.Styles;
const Color = UIFramework.Styles.Color;

const WindowManager = @import("../../managers/WindowManager.zig").WindowManagerSingleton;
const winRelX = WindowManager.relW;
const winRelY = WindowManager.relH;

const ProgressBox = struct {
    value: i64 = 0,
    text: Text = undefined,
    rect: Rectangle = undefined,

    pub fn draw(self: *ProgressBox) void {
        self.text.draw();
        self.rect.draw();
    }

    pub fn setProgressTo(self: *ProgressBox, referenceRect: Rectangle, newValue: i64) void {
        self.value = newValue;

        const width: f32 = referenceRect.transform.getWidth();
        const progress: f32 = @floatFromInt(newValue);
        self.rect.transform.w = (progress / 100) * (1 - SECTION_PADDING) * width;
    }
};

const SpecDimensions = struct { x: f32, y: f32, w: f32, h: f32, gap: f32 };

const StatusIndicator = struct {
    text: Text = undefined,
    box: Statusbox = undefined,
    dims: SpecDimensions = undefined,

    pub fn init(text: [:0]const u8, dims: SpecDimensions) StatusIndicator {
        var statusBox = Statusbox.init(.{ .x = 0, .y = 0 }, dims.h, .Primary);
        statusBox.switchState(.NONE);

        return StatusIndicator{
            .text = Text.init(text, .{ .x = 0, .y = 0 }, .{ .fontSize = 14 }),
            .box = statusBox,
            .dims = dims,
        };
    }

    pub fn calculateUI(self: *StatusIndicator, referenceRect: Rectangle) void {
        const startX = referenceRect.transform.relX(self.dims.x);
        const startY = referenceRect.transform.relY(self.dims.y) + if (self.dims.gap > 0) self.dims.h + self.dims.gap else 0;

        self.text.transform.x = startX;
        self.text.transform.y = startY + self.dims.h / 2 - self.text.getDimensions().height / 2;
        self.box.setPosition(.{ .x = startX + referenceRect.transform.getWidth() * self.dims.w - self.dims.h, .y = startY });
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

pub const Events = struct {
    pub const onActiveStateChanged = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_active_state_changed"),
        struct { isActive: bool },
        struct {},
    );

    pub const onISOWriteProgressChanged = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_iso_write_progress_changed"),
        struct { newProgress: i64 },
        struct {},
    );

    pub const onWriteVerificationProgressChanged = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_write_verification_progress_changed"),
        struct { newProgress: i64 },
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

    self.progressBox = ProgressBox{
        .text = Text.init("", .{
            .x = self.bgRect.transform.relX(0.05),
            .y = self.bgRect.transform.relY(0.62),
        }, .{
            .font = .ROBOTO_REGULAR,
            .fontSize = 14,
            .textColor = .white,
        }),
        .value = 0,
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

    self.moduleImg = Texture.init(.DISK_IMAGE, .{ .x = 0, .y = 0 });
    self.moduleImg.transform.scale = 0.5;
    self.moduleImg.transform.x = self.bgRect.transform.relX(0.5) - self.moduleImg.transform.getWidth() / 2;
    self.moduleImg.transform.y = self.bgRect.transform.relY(0.5) - self.moduleImg.transform.getHeight() / 2;
    self.moduleImg.tint = .{ .r = 255, .g = 255, .b = 255, .a = 150 };

    const size: f32 = 20;
    const leftPadding: f32 = 0.05;
    const gap: f32 = 8;

    self.isoStatus = StatusIndicator.init("ISO validated & stream open...", .{
        .x = leftPadding,
        .y = 0.24,
        .w = 1 - SECTION_PADDING,
        .h = size,
        .gap = 0,
    });
    self.isoStatus.calculateUI(self.bgRect);

    self.deviceStatus = StatusIndicator.init("Device validated & stream open...", .{
        .x = leftPadding,
        .y = 0.30,
        .w = 1 - SECTION_PADDING,
        .h = size,
        .gap = gap,
    });
    self.deviceStatus.calculateUI(self.bgRect);

    self.permissionsStatus = StatusIndicator.init("Freetracer has necessary permissions...", .{
        .x = leftPadding,
        .y = 0.36,
        .w = 1 - SECTION_PADDING,
        .h = size,
        .gap = gap,
    });
    self.permissionsStatus.calculateUI(self.bgRect);

    self.writeStatus = StatusIndicator.init("Write successfully completed...", .{
        .x = leftPadding,
        .y = 0.42,
        .w = 1 - SECTION_PADDING,
        .h = size,
        .gap = gap,
    });
    self.writeStatus.calculateUI(self.bgRect);

    self.verificationStatus = StatusIndicator.init("Written bytes successfuly verified...", .{
        .x = leftPadding,
        .y = 0.48,
        .w = 1 - SECTION_PADDING,
        .h = size,
        .gap = gap,
    });
    self.verificationStatus.calculateUI(self.bgRect);
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

        Events.onISOWriteProgressChanged.Hash => {
            const data = Events.onISOWriteProgressChanged.getData(event) orelse break :eventLoop;

            Debug.log(.INFO, "Write progress is: {d}", .{data.newProgress});

            self.progressBox.text.value = "Writing ISO...";
            self.progressBox.setProgressTo(self.bgRect, data.newProgress);

            eventResult.validate(.SUCCESS);
        },

        Events.onWriteVerificationProgressChanged.Hash => {
            const data = Events.onWriteVerificationProgressChanged.getData(event) orelse break :eventLoop;

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

    self.isoStatus.calculateUI(self.bgRect);
    self.deviceStatus.calculateUI(self.bgRect);
    self.permissionsStatus.calculateUI(self.bgRect);
    self.writeStatus.calculateUI(self.bgRect);
    self.verificationStatus.calculateUI(self.bgRect);

    self.progressBox.rect.transform.x = leftPadding;
    self.progressBox.text.transform.x = leftPadding;

    self.button.setPosition(.{
        .x = centerX - self.button.rect.transform.getWidth() / 2,
        .y = self.button.rect.transform.y,
    });
}

pub const ComponentImplementation = ComponentFramework.ImplementComponent(DataFlasherUI);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;
