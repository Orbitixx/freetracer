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
const Rectangle = UIFramework.Primitives.Rectangle;
const Text = UIFramework.Primitives.Text;
const Texture = UIFramework.Primitives.Texture;

const Styles = UIFramework.Styles;
const Color = UIFramework.Styles.Color;

const WindowManager = @import("../../managers/WindowManager.zig").WindowManagerSingleton;
const winRelX = WindowManager.relW;
const winRelY = WindowManager.relH;

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
writeProgressRect: Rectangle = undefined,
writeProgress: i64 = 0,

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
        .{
            .context = self.parent,
            .function = DataFlasher.flashISOtoDeviceWrapper.call,
        },
    );

    self.button.setEnabled(false);

    self.isoText = Text.init("NULL", .{
        .x = self.bgRect.transform.relX(0.05),
        .y = self.bgRect.transform.relY(0.1),
    }, .{
        .fontSize = 14,
    });

    self.deviceText = Text.init("NULL", .{
        .x = self.bgRect.transform.relX(0.05),
        .y = self.bgRect.transform.relY(0.15),
    }, .{
        .fontSize = 14,
    });

    self.headerLabel = Text.init("flash", .{
        .x = self.bgRect.transform.x + 12,
        .y = self.bgRect.transform.relY(0.01),
    }, .{
        .font = .JERSEY10_REGULAR,
        .fontSize = 34,
        .textColor = Styles.Color.white,
    });

    self.writeProgressRect = Rectangle{
        .bordered = true,
        .rounded = false,
        .style = .{
            .color = Color.white,
            .borderStyle = .{ .color = Color.white, .thickness = 2.00 },
        },
        .transform = .{
            .x = self.bgRect.transform.relX(0.2),
            .y = self.bgRect.transform.relY(0.7),
            .h = 18.0,
            .w = 0.0,
        },
    };

    // self.writeProgress = Text.init("", bgRect.transform.relX(0.), style: TextStyle)
    self.moduleImg = Texture.init(.DISK_IMAGE, .{ .x = 0, .y = 0 });

    self.moduleImg.transform.scale = 0.5;
    self.moduleImg.transform.x = self.bgRect.transform.relX(0.5) - self.moduleImg.transform.getWidth() / 2;
    self.moduleImg.transform.y = self.bgRect.transform.relY(0.5) - self.moduleImg.transform.getHeight() / 2;
    self.moduleImg.tint = .{ .r = 255, .g = 255, .b = 255, .a = 150 };

    try self.button.start();

    self.button.setPosition(.{
        .x = self.bgRect.transform.relX(0.5) - @divTrunc(self.button.rect.transform.getWidth(), 2),
        .y = self.bgRect.transform.relY(0.9) - @divTrunc(self.button.rect.transform.getHeight(), 2),
    });

    self.button.rect.rounded = true;
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
    self.writeProgressRect.draw();
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

                    self.isoText.value = isoPath;
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

            self.writeProgress = data.newProgress;

            Debug.log(.INFO, "Progress is: {d}", .{data.newProgress});

            const width: f32 = self.bgRect.transform.getWidth();
            const progress: f32 = @floatFromInt(data.newProgress);
            self.writeProgressRect.transform.w = (progress / 100) * 0.9 * width;

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

    self.headerLabel.transform.x = self.bgRect.transform.x + 12;
    self.headerLabel.transform.y = self.bgRect.transform.relY(0.01);

    self.moduleImg.transform.x = self.bgRect.transform.relX(0.5) - self.moduleImg.transform.getWidth() / 2;
    self.moduleImg.transform.y = self.bgRect.transform.relY(0.5) - self.moduleImg.transform.getHeight() / 2;

    self.isoText.transform.x = self.bgRect.transform.relX(0.05);
    self.isoText.transform.y = self.bgRect.transform.relY(0.13);

    self.deviceText.transform.x = self.bgRect.transform.relX(0.05);
    self.deviceText.transform.y = self.isoText.transform.y + self.isoText.transform.getHeight() + 10;

    self.writeProgressRect.transform.x = self.bgRect.transform.relX(0.05);

    self.button.setPosition(.{
        .x = self.bgRect.transform.relX(0.5) - self.button.rect.transform.getWidth() / 2,
        .y = self.button.rect.transform.y,
    });
}

pub const ComponentImplementation = ComponentFramework.ImplementComponent(DataFlasherUI);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;
