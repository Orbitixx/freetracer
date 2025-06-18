const std = @import("std");
const debug = @import("../../lib/util/debug.zig");
const rl = @import("raylib");

const MacOS = @import("../../modules/macos/MacOSTypes.zig");

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
const Checkbox = UIFramework.Checkbox;
const Rectangle = UIFramework.Primitives.Rectangle;
const Text = UIFramework.Primitives.Text;
const Texture = UIFramework.Primitives.Texture;

const Styles = UIFramework.Styles;
const Color = UIFramework.Styles.Color;

pub const DeviceListUIState = struct {
    active: bool = false,
    devices: *std.ArrayList(MacOS.USBStorageDevice),
    selectedDeviceName: ?[:0]u8 = null,
};

pub const ComponentState = ComponentFramework.ComponentState(DeviceListUIState);

const DeviceListUI = @This();

const COMPONENT_UI_GAP: f32 = 20;

// Component-agnostic props
state: ComponentState,
parent: *DeviceList,
component: ?Component = null,

// Component-specific, unique props
allocator: std.mem.Allocator,
bgRect: ?Rectangle = null,
headerLabel: ?Text = null,
diskImg: ?Texture = null,
button: ?Button = null,
deviceNameLabel: ?Text = null,
deviceCheckboxes: std.ArrayList(Checkbox),

const BgRectParams = struct {
    width: f32,
    color: rl.Color,
    borderColor: rl.Color,
};

pub const Events = struct {
    //
    pub const DeviceListActiveStateChanged = ComponentFramework.defineEvent(
        "device_list_ui.active_state_changed",
        struct {
            isActive: bool,
        },
    );

    pub const DeviceListDeviceNameChanged = ComponentFramework.defineEvent(
        "device_list_ui.device_name_changed",
        struct {
            newDeviceName: [:0]u8,
        },
    );

    pub const onDevicesReadyToRender = ComponentFramework.defineEvent(
        "device_list_ui.on_devices_ready_to_render",
        struct {},
    );
};

pub fn init(allocator: std.mem.Allocator, parent: *DeviceList) !DeviceListUI {
    debug.print("\nDeviceListUI: start() called.");

    parent.state.lock();
    defer parent.state.unlock();

    return DeviceListUI{
        .allocator = allocator,
        .state = ComponentState.init(DeviceListUIState{
            .devices = &parent.state.data.devices,
        }),
        .parent = parent,
        .deviceCheckboxes = std.ArrayList(Checkbox).init(allocator),
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

    var eventResult = EventResult.init();

    eventLoop: switch (event.hash) {

        // ISOFilePickerUI emits this event in response to receiving the same event
        ISOFilePickerUI.Events.ISOFilePickerUIGetUIDimensions.Hash => {
            //
            const data = ISOFilePickerUI.Events.ISOFilePickerUIGetUIDimensions.getData(event) orelse break :eventLoop;
            eventResult.validate(1);

            if (self.bgRect) |*bgRect| {
                bgRect.transform.x = data.transform.x + data.transform.w + 20;
            }
        },

        ISOFilePickerUI.Events.ISOFilePickerActiveStateChanged.Hash => {
            //
            const data = ISOFilePickerUI.Events.ISOFilePickerActiveStateChanged.getData(event) orelse break :eventLoop;

            return try self.handleEvent(Events.DeviceListActiveStateChanged.create(
                &self.component.?,
                // Set the __opposite__ of the ISOFilePicker active state.
                &.{ .isActive = !data.isActive },
            ));
        },

        Events.onDevicesReadyToRender.Hash => {
            //
            //
            debug.print("\nDeviceListUI: onDevicesReadyToRender() start.");

            // self.state.lock();
            // defer self.state.unlock();

            if (self.state.data.devices.items.len < 1) {
                debug.print("\nDeviceListUI: onDevicesReadyToRender(): no devices discovered, breaking the event loop.");
                break :eventLoop;
            }

            debug.printf("\nDeviceListUI: onDevicesReadyToRender(): processing checkboxes for {d} devices.", .{self.state.data.devices.items.len});

            for (self.state.data.devices.items, 0..) |device, i| {
                //
                const selectDeviceContext = try self.allocator.create(DeviceList.SelectDeviceCallbackContext);

                selectDeviceContext.* = DeviceList.SelectDeviceCallbackContext{
                    .component = self.parent,
                    .selectedDevice = device,
                };

                try self.deviceCheckboxes.append(Checkbox.init(
                    @ptrCast(@alignCast(device.deviceName)),
                    .{
                        .x = self.bgRect.?.transform.relX(0.05),
                        .y = self.bgRect.?.transform.relY(0.12) + @as(f32, @floatFromInt(i)) * 25,
                    },
                    20,
                    .Primary,
                    .{
                        .context = selectDeviceContext,
                        .function = DeviceList.selectDeviceActionWrapper.call,
                    },
                ));

                for (self.deviceCheckboxes.items) |*checkbox| {
                    checkbox.outerRect.bordered = true;
                    checkbox.outerRect.rounded = true;
                    checkbox.innerRect.rounded = true;
                    try checkbox.start();
                }
            }

            debug.print("\nDeviceListUI: onDevicesReadyToRender() end.");
        },

        Events.DeviceListDeviceNameChanged.Hash => {
            //
            const data = Events.DeviceListDeviceNameChanged.getData(event) orelse break :eventLoop;
            eventResult.validate(1);

            var state = self.state.getData();
            state.selectedDeviceName = data.newDeviceName;

            if (self.bgRect) |bgRect| {
                self.deviceNameLabel = Text.init(state.selectedDeviceName.?, .{
                    .x = bgRect.transform.relX(0.5),
                    .y = bgRect.transform.relY(0.5),
                }, .{
                    .fontSize = 14,
                });
            }
        },

        Events.DeviceListActiveStateChanged.Hash => {
            //
            const data = Events.DeviceListActiveStateChanged.getData(event) orelse break :eventLoop;
            eventResult.validate(1);

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
    for (self.deviceCheckboxes.items) |*checkbox| {
        try checkbox.update();
    }

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
    // self.parent.state.lock();
    // defer self.parent.state.unlock();

    for (self.deviceCheckboxes.items) |*checkbox| {
        try checkbox.draw();
    }

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
    if (self.state.data.selectedDeviceName) |deviceName| {
        self.parent.allocator.free(deviceName);
    }

    for (self.deviceCheckboxes.items) |checkbox| {
        const ctx: *DeviceList.SelectDeviceCallbackContext = @ptrCast(@alignCast(checkbox.clickHandler.context));
        self.allocator.destroy(ctx);
    }

    self.deviceCheckboxes.deinit();
}

pub fn dispatchComponentAction(self: *DeviceListUI) void {
    _ = self;
}

pub const ComponentImplementation = ComponentFramework.ImplementComponent(DeviceListUI);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;
