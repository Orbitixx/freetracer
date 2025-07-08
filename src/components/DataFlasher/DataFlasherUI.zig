const std = @import("std");
const debug = @import("../../lib/util/debug.zig");
const rl = @import("raylib");

const AppConfig = @import("../../config.zig");

const System = @import("../../lib/sys/system.zig");
const USBStorageDevice = System.USBStorageDevice;

const EventManager = @import("../../managers/EventManager.zig").EventManagerSingleton;

const ComponentFramework = @import("../framework/import/index.zig");
// const WorkerContext = @import("./WorkerContext.zig");

const DataFlasher = @import("./DataFlasher.zig");
const DeviceList = @import("../DeviceList/DeviceList.zig");
const DeviceListUI = @import("../DeviceList/DeviceListUI.zig");

const DataFlasherUIState = struct {
    isActive: bool = false,
    isoPath: ?[:0]const u8 = null,
    device: ?USBStorageDevice = null,
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
bgRect: ?Rectangle = null,
headerLabel: ?Text = null,
moduleImg: ?Texture = null,
button: ?Button = null,
isoText: ?Text = null,
deviceText: ?Text = null,

const BgRectParams = struct {
    width: f32,
    color: rl.Color,
    borderColor: rl.Color,
};

pub const Events = struct {
    pub const onActiveStateChanged = ComponentFramework.defineEvent(
        "data_flasher.on_active_state_changed",
        struct {
            isActive: bool,
        },
        struct {},
    );

    pub const onSomething = ComponentFramework.defineEvent(
        "data_flasher.on_",
        struct {},
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
        if (!EventManager.subscribe("data_flasher_ui", component)) return error.UnableToSubscribeToEventManager;
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

    if (self.bgRect) |bgRect| {
        self.button = Button.init(
            "Flash",
            bgRect.transform.getPosition(),
            .Primary,
            .{
                .context = self.parent,
                .function = DataFlasher.flashISOtoDeviceWrapper.call,
            },
        );

        if (self.button) |*button| {
            button.setEnabled(false);
        }

        self.isoText = Text.init("NULL", .{
            .x = bgRect.transform.relX(0.05),
            .y = bgRect.transform.relY(0.1),
        }, .{
            .fontSize = 14,
        });

        self.deviceText = Text.init("NULL", .{
            .x = bgRect.transform.relX(0.05),
            .y = bgRect.transform.relY(0.15),
        }, .{
            .fontSize = 14,
        });

        self.headerLabel = Text.init("flash", .{
            .x = bgRect.transform.x + 12,
            .y = bgRect.transform.relY(0.01),
        }, .{
            .font = .JERSEY10_REGULAR,
            .fontSize = 34,
            .textColor = Styles.Color.white,
        });

        self.moduleImg = Texture.init(.DISK_IMAGE, .{ .x = 0, .y = 0 });

        if (self.moduleImg) |*img| {
            img.transform.scale = 0.5;
            img.transform.x = bgRect.transform.relX(0.5) - img.transform.getWidth() / 2;
            img.transform.y = bgRect.transform.relY(0.5) - img.transform.getHeight() / 2;
            img.tint = .{ .r = 255, .g = 255, .b = 255, .a = 150 };
        }

        if (self.button) |*button| {
            try button.start();

            button.setPosition(.{
                .x = bgRect.transform.relX(0.5) - @divTrunc(button.rect.transform.getWidth(), 2),
                .y = bgRect.transform.relY(0.9) - @divTrunc(button.rect.transform.getHeight(), 2),
            });

            button.rect.rounded = true;
        }
    }
}

pub fn update(self: *DataFlasherUI) !void {
    if (self.button) |*button| {
        try button.update();
    }
}

pub fn draw(self: *DataFlasherUI) !void {
    self.state.lock();
    const isActive = self.state.data.isActive;
    self.state.unlock();

    if (self.bgRect) |bgRect| {
        bgRect.draw();
    }

    if (self.headerLabel) |label| {
        label.draw();
    }

    if (isActive) try self.drawActive() else try self.drawInactive();
}

fn drawActive(self: *DataFlasherUI) !void {
    if (self.isoText) |*text| {
        text.draw();
    }

    if (self.deviceText) |*text| {
        text.draw();
    }

    if (self.button) |*button| {
        try button.draw();
    }
}

fn drawInactive(self: *DataFlasherUI) !void {
    if (self.moduleImg) |img| {
        img.draw();
    }
}

pub fn handleEvent(self: *DataFlasherUI, event: ComponentEvent) !EventResult {
    var eventResult = EventResult{
        .success = false,
        .validation = 0,
    };

    eventLoop: switch (event.hash) {
        //
        // Event: parent's authoritative state signal
        DataFlasher.Events.onActiveStateChanged.Hash => {
            //
            const data = DataFlasher.Events.onActiveStateChanged.getData(event) orelse break :eventLoop;

            eventResult.validate(1);

            {
                self.state.lock();
                defer self.state.unlock();
                self.state.data.isActive = data.isActive;
            }

            try self.queryDeviceListUIDimensions();

            switch (data.isActive) {
                true => {
                    debug.print("DataFlasherUI: setting UI to ACTIVE.");

                    var isoPath: [:0]const u8 = "NULL";
                    var device: ?*System.USBStorageDevice = null;
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

                    if (self.isoText) |*text| {
                        text.value = isoPath;
                    }

                    if (self.deviceText) |*text| {
                        text.value = device.?.getBsdNameSlice();
                    }

                    if (areStateParamsAvailable) {
                        if (self.button) |*button| {
                            button.setEnabled(true);
                        }
                    }

                    if (self.headerLabel) |*header| {
                        header.style.textColor = Color.white;
                    }

                    self.recalculateUI(.{
                        .width = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_ACTIVE),
                        .color = Color.blueGray,
                        .borderColor = Color.white,
                    });
                },

                false => {
                    debug.print("DataFlasherUI: setting UI to INACTIVE.");

                    if (self.headerLabel) |*header| {
                        header.style.textColor = Color.lightGray;
                    }

                    if (self.button) |*button| {
                        button.setEnabled(false);
                    }

                    self.recalculateUI(.{
                        .width = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_INACTIVE),
                        .color = Color.darkBlueGray,
                        .borderColor = Color.transparentDark,
                    });
                },
            }
        },

        Events.onSomething.Hash => {
            //
            const data = Events.onSomething.getData(event) orelse break :eventLoop;
            _ = data;

            eventResult.validate(1);
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

        if (self.bgRect) |*bgRect| {
            bgRect.transform.x = deviceListUIData.transform.x + deviceListUIData.transform.getWidth() + 20;
        }

        self.allocator.destroy(deviceListUIData);
    }
}

fn recalculateUI(self: *DataFlasherUI, bgRectParams: BgRectParams) void {
    debug.print("DataFlasherUI: updating bgRect properties!");

    if (self.bgRect) |*bgRect| {
        bgRect.transform.w = bgRectParams.width;
        bgRect.style.color = bgRectParams.color;
        bgRect.style.borderStyle.color = bgRectParams.borderColor;

        if (self.headerLabel) |*headerLabel| {
            headerLabel.transform.x = bgRect.transform.x + 12;
            headerLabel.transform.y = bgRect.transform.relY(0.01);
        }

        if (self.moduleImg) |*image| {
            image.transform.x = bgRect.transform.relX(0.5) - image.transform.getWidth() / 2;
            image.transform.y = bgRect.transform.relY(0.5) - image.transform.getHeight() / 2;
        }

        if (self.isoText) |*isoText| {
            isoText.transform.x = bgRect.transform.relX(0.05);
            isoText.transform.y = bgRect.transform.relY(0.13);

            if (self.deviceText) |*deviceText| {
                deviceText.transform.x = bgRect.transform.relX(0.05);
                deviceText.transform.y = isoText.transform.y + isoText.transform.getHeight() + 10;
            }
        }

        if (self.button) |*btn| {
            btn.setPosition(.{
                .x = bgRect.transform.relX(0.5) - btn.rect.transform.getWidth() / 2,
                .y = btn.rect.transform.y,
            });
        }
    }
}

pub const ComponentImplementation = ComponentFramework.ImplementComponent(DataFlasherUI);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;
