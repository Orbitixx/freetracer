const std = @import("std");
const debug = @import("../../lib/util/debug.zig");
const rl = @import("raylib");

const WindowManager = @import("../../managers/WindowManager.zig").WindowManagerSingleton;
const winRelX = WindowManager.relW;
const winRelY = WindowManager.relH;

const EventManager = @import("../../managers/EventManager.zig").EventManagerSingleton;

const DeviceList = @import("./DeviceList.zig");
const ISOFilePicker = @import("../FilePicker/FilePicker.zig");
const ISOFilePickerUI = @import("../FilePicker/FilePickerUI.zig");

const ComponentFramework = @import("../framework/import/index.zig");
const Component = ComponentFramework.Component;
const ComponentEvent = ComponentFramework.Event;
const EventResult = ComponentFramework.EventResult;

const UIFramework = @import("../ui/import/index.zig");
const Button = UIFramework.Button;
const Rectangle = UIFramework.Primitives.Rectangle;
const Text = UIFramework.Primitives.Text;
const Texture = UIFramework.Primitives.Texture;

const Styles = UIFramework.Styles;
const Color = UIFramework.Styles.Color;

pub const DeviceListUIState = struct {
    active: bool = false,
    deviceName: ?[:0]u8 = null,
};
pub const ComponentState = ComponentFramework.ComponentState(DeviceListUIState);

const DeviceListUI = @This();

const COMPONENT_UI_GAP: f32 = 20;

// Component-agnostic props
state: ComponentState,
parent: *DeviceList,
component: ?Component = null,

// Component-specific, unique props
bgRect: ?Rectangle = null,
headerLabel: ?Text = null,
diskImg: ?Texture = null,
button: ?Button = null,
deviceNameLabel: ?Text = null,

const BgRectParams = struct {
    width: f32,
    color: rl.Color,
    borderColor: rl.Color,
};

pub const Events = struct {
    pub const DeviceListActiveStateChanged = ComponentFramework.defineEvent(
        "device_list_ui.active_state_changed",
        struct { isActive: bool },
    );

    pub const DeviceListDeviceNameChanged = ComponentFramework.defineEvent(
        "device_list_ui.device_name_changed",
        struct {
            newDeviceName: [:0]u8,
        },
    );
};

pub fn init(parent: *DeviceList) !DeviceListUI {
    debug.print("\nDeviceListUI: start() called.");

    return DeviceListUI{
        .state = ComponentState.init(DeviceListUIState{}),
        .parent = parent,
    };
}

pub fn initComponent(self: *DeviceListUI, parent: ?*Component) !void {
    if (self.component != null) return error.BaseComponentAlreadyInitialized;
    self.component = try Component.init(self, &ComponentImplementation.vtable, parent);
}

pub fn start(self: *DeviceListUI) !void {
    debug.print("\nDeviceListUI: component start() called.");

    if (self.component == null) try self.initComponent(self.parent.asComponentPtr());

    if (self.component) |*component| {
        if (!EventManager.subscribe(component)) return error.UnableToSubscribeToEventManager;
    } else return error.UnableToSubscribeToEventManager;

    self.bgRect = Rectangle{
        .transform = .{ .x = winRelX(0.5), .y = winRelY(0.2), .w = winRelX(0.16), .h = winRelY(0.7) },
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
    const event = ISOFilePickerUI.Events.ISOFilePickerUIGetUIDimensions.create(&self.component.?, null);
    EventManager.broadcast(event);

    if (self.bgRect) |bgRect| {
        self.button = Button.init(
            "Next",
            bgRect.transform.getPosition(),
            .Primary,
            .{
                .context = self.parent,
                .function = DeviceList.dispatchComponentActionWrapper.call,
            },
        );

        if (self.button) |*btn| {
            btn.state = .DISABLED;
        }

        self.headerLabel = Text.init("device", .{
            .x = bgRect.transform.x + 12,
            .y = bgRect.transform.relY(0.01),
        }, .{
            .font = .JERSEY10_REGULAR,
            .fontSize = 34,
            .textColor = Styles.Color.white,
        });

        self.diskImg = Texture.init(.DISK_IMAGE, .{ .x = 0, .y = 0 });

        if (self.diskImg) |*img| {
            img.transform.scale = 0.7;
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

        self.deviceNameLabel = Text.init("No device selected...", .{ .x = 0, .y = 0 }, .{ .fontSize = 14 });

        if (self.deviceNameLabel) |*label| {
            if (self.diskImg) |img| {
                label.transform.x = bgRect.transform.relX(0.5) - label.getDimensions().width / 2;
                label.transform.y = img.transform.y + img.transform.getHeight() + winRelY(0.02);
            }
        }
    }

    debug.print("\nDeviceListUI: component start() finished.");
}

pub fn handleEvent(self: *DeviceListUI, event: ComponentEvent) !EventResult {
    debug.printf("\nDeviceListUI: handleEvent() received an event: \"{s}\"", .{event.name});

    var eventResult = EventResult{
        .success = false,
        .validation = 0,
    };

    eventLoop: switch (event.hash) {
        Events.DeviceListDeviceNameChanged.Hash => {
            //
            const maybe_data = Events.DeviceListDeviceNameChanged.getData(&event);
            var data: *const Events.DeviceListDeviceNameChanged.Data = undefined;
            if (maybe_data != null) data = maybe_data.? else break :eventLoop;

            eventResult.success = true;
            eventResult.validation = 1;

            var state = self.state.getData();

            state.deviceName = data.newDeviceName;

            if (self.bgRect) |bgRect| {
                self.deviceNameLabel = Text.init(state.deviceName.?, .{
                    .x = bgRect.transform.relX(0.5),
                    .y = bgRect.transform.relY(0.5),
                }, .{
                    .fontSize = 14,
                });
            }
        },

        // NOTE: ISOFilePickerUI emits this event in response to receiving the same event
        ISOFilePickerUI.Events.ISOFilePickerUIGetUIDimensions.Hash => {
            //
            const maybe_data = ISOFilePickerUI.Events.ISOFilePickerUIGetUIDimensions.getData(&event);
            var data: *ISOFilePickerUI.Events.ISOFilePickerUIGetUIDimensions.Data = undefined;
            if (maybe_data != null) data = @constCast(maybe_data.?) else break :eventLoop;

            eventResult.success = true;
            eventResult.validation = 1;

            if (self.bgRect) |*bgRect| {
                bgRect.transform.x = data.transform.x + data.transform.w + 20;
            }
        },

        ISOFilePickerUI.Events.ISOFilePickerActiveStateChanged.Hash => {
            //
            const maybe_data = ISOFilePickerUI.Events.ISOFilePickerActiveStateChanged.getData(&event);
            var data: *ISOFilePickerUI.Events.ISOFilePickerActiveStateChanged.Data = undefined;
            if (maybe_data != null) data = @constCast(maybe_data.?) else break :eventLoop;

            return try self.handleEvent(Events.DeviceListActiveStateChanged.create(
                &self.component.?,
                // Return the __opposite__ of the ISOFilePicker active state.
                &.{ .isActive = !data.isActive },
            ));
        },

        Events.DeviceListActiveStateChanged.Hash => {
            //
            const maybe_data = Events.DeviceListActiveStateChanged.getData(&event);
            var data: *Events.DeviceListActiveStateChanged.Data = undefined;
            if (maybe_data != null) data = @constCast(maybe_data.?) else break :eventLoop;

            eventResult.success = true;
            eventResult.validation = 1;

            var state = self.state.getData();
            state.active = data.isActive;

            switch (state.active) {
                true => {
                    debug.print("\nDeviceListUI: setting UI to ACTIVE.");
                    self.recalculateUI(.{
                        .width = winRelX(0.35),
                        .color = Color.blueGray,
                        .borderColor = Color.white,
                    });
                },

                false => {
                    debug.print("\nDeviceListUI: setting UI to INACTIVE.");
                    self.recalculateUI(.{
                        .width = winRelX(0.16),
                        .color = Color.darkBlueGray,
                        .borderColor = Color.transparentDark,
                    });
                },
            }
        },
        else => {},
    }

    return eventResult;
}

fn recalculateUI(self: *DeviceListUI, bgRectParams: BgRectParams) void {
    debug.print("\nDeviceListUI: updating bgRect properties!");

    if (self.bgRect) |*bgRect| {
        bgRect.transform.w = bgRectParams.width;
        bgRect.style.color = bgRectParams.color;
        bgRect.style.borderStyle.color = bgRectParams.borderColor;

        if (self.headerLabel) |*headerLabel| {
            headerLabel.transform.x = bgRect.transform.x + 12;
            headerLabel.transform.y = bgRect.transform.relY(0.01);
        }

        if (self.deviceNameLabel) |*deviceNameLabel| {
            deviceNameLabel.transform.x = bgRect.transform.relX(0.5) - deviceNameLabel.getDimensions().width / 2;
            deviceNameLabel.transform.y = bgRect.transform.relY(0.5) - deviceNameLabel.getDimensions().height / 2;
        }

        if (self.button) |*btn| {
            btn.setPosition(.{
                .x = bgRect.transform.relX(0.5) - btn.rect.transform.getWidth() / 2,
                .y = btn.rect.transform.y,
            });
        }
    }
}

pub fn update(self: *DeviceListUI) !void {
    if (self.button) |*button| {
        try button.update();
    }
}

pub fn draw(self: *DeviceListUI) !void {
    const state = self.state.getDataLocked();
    defer self.state.unlock();

    if (self.bgRect) |bgRect| {
        bgRect.draw();
    }

    if (self.headerLabel) |label| {
        label.draw();
    }

    if (state.active) try self.drawActive() else try self.drawInactive();
}

fn drawActive(self: *DeviceListUI) !void {
    if (self.button) |*button| {
        try button.draw();
    }
}

fn drawInactive(self: *DeviceListUI) !void {
    if (self.deviceNameLabel) |label| {
        label.draw();
    }

    if (self.diskImg) |img| {
        img.draw();
    }
}

pub fn deinit(self: *DeviceListUI) void {
    if (self.state.data.deviceName) |deviceName| {
        self.parent.allocator.free(deviceName);
    }
}

pub fn dispatchComponentAction(self: *DeviceListUI) void {
    _ = self;
}

pub const ComponentImplementation = ComponentFramework.ImplementComponent(DeviceListUI);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;
