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
    isActive: bool = false,
    devices: *std.ArrayList(MacOS.USBStorageDevice),
    selectedDeviceName: ?[:0]u8 = null,
    selectedDevice: ?MacOS.USBStorageDevice = null,
};

pub const ComponentState = ComponentFramework.ComponentState(DeviceListUIState);

const DeviceListUI = @This();

const COMPONENT_UI_GAP: f32 = 20;

// Component-agnostic props
state: ComponentState,
component: ?Component = null,

// Component-specific, unique props
allocator: std.mem.Allocator,
parent: *DeviceList,
bgRect: ?Rectangle = null,
headerLabel: ?Text = null,
moduleImg: ?Texture = null,
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
    pub const onDeviceListUIActiveStateChanged = ComponentFramework.defineEvent(
        "device_list_ui.on_active_state_changed",
        struct {
            isActive: bool,
        },
        struct {},
    );

    pub const onDevicesReadyToRender = ComponentFramework.defineEvent(
        "device_list_ui.on_devices_ready_to_render",
        struct {},
        struct {},
    );

    pub const onSelectedDeviceNameChanged = ComponentFramework.defineEvent(
        "device_list_ui.on_device_name_changed",
        struct {
            // Not authoritative data; copy only -- use parent.
            selectedDevice: ?MacOS.USBStorageDevice,
        },
        struct {},
    );

    pub const onUITransformQueried = ComponentFramework.defineEvent(
        "device_list_ui.on_ui_transform_queried",
        struct {},
        struct {
            transform: UIFramework.Primitives.Transform,
        },
    );
};

// Creates and returns an instance of DeviceListUI component
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

// Parent param is technically not required here, since the component already stores it as a property,
// however, the param is preserved for convention's sake.
pub fn initComponent(self: *DeviceListUI, parent: ?*Component) !void {
    if (self.component != null) return error.BaseComponentAlreadyInitialized;
    self.component = try Component.init(self, &ComponentImplementation.vtable, parent);
}

// Called once upon component initialization.
pub fn start(self: *DeviceListUI) !void {
    debug.print("\nDeviceListUI: component start() called.");

    if (self.component == null) try self.initComponent(self.parent.asComponentPtr());

    if (self.component) |*component| {
        if (!EventManager.subscribe("device_list_ui", component)) return error.UnableToSubscribeToEventManager;
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
    const initialPositionEvent = ISOFilePickerUI.Events.onGetUIDimensions.create(self.asComponentPtr(), null);
    EventManager.broadcast(initialPositionEvent);

    // const response = try EventManager.signal("iso_file_picker", event);
    // const data: *ISOFilePickerUI.Events.onGetUIDimensions.Response = response.data

    if (self.bgRect) |bgRect| {
        self.button = Button.init(
            "Next",
            bgRect.transform.getPosition(),
            .Primary,
            .{
                .context = self.parent,
                .function = DeviceList.dispatchComponentFinishedAction.call,
            },
        );

        if (self.button) |*button| {
            button.setEnabled(false);
        }

        self.headerLabel = Text.init("device", .{
            .x = bgRect.transform.x + 12,
            .y = bgRect.transform.relY(0.01),
        }, .{
            .font = .JERSEY10_REGULAR,
            .fontSize = 34,
            .textColor = Styles.Color.white,
        });

        self.moduleImg = Texture.init(.USB_IMAGE, .{ .x = 0, .y = 0 });

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

        self.deviceNameLabel = Text.init("No device selected...", .{ .x = 0, .y = 0 }, .{ .fontSize = 14 });

        if (self.deviceNameLabel) |*label| {
            if (self.moduleImg) |img| {
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
        ISOFilePickerUI.Events.onGetUIDimensions.Hash => {
            //
            const data = ISOFilePickerUI.Events.onGetUIDimensions.getData(event) orelse break :eventLoop;
            eventResult.validate(1);

            if (self.bgRect) |*bgRect| {
                bgRect.transform.x = data.transform.x + data.transform.w + 20;
            }
        },

        ISOFilePicker.Events.onActiveStateChanged.Hash => {
            //
            const data = ISOFilePicker.Events.onActiveStateChanged.getData(event) orelse break :eventLoop;

            // Dispatch a parent event that the current component already listens to (for simplicity)
            return try self.handleEvent(DeviceList.Events.onDeviceListActiveStateChanged.create(
                &self.component.?,
                // Set the __opposite__ of the ISOFilePicker active state.
                &.{ .isActive = !data.isActive },
            ));
        },

        DeviceList.Events.onDeviceListActiveStateChanged.Hash => {
            //
            const data = DeviceList.Events.onDeviceListActiveStateChanged.getData(event) orelse break :eventLoop;
            eventResult.validate(1);

            // debug.print("")

            // Update state in a block with a shorter lifecycle
            {
                self.state.lock();
                defer self.state.unlock();
                self.state.data.isActive = data.isActive;
            }

            switch (data.isActive) {
                true => {
                    debug.print("\nDeviceListUI: setting UI to ACTIVE.");

                    if (self.headerLabel) |*header| {
                        header.style.textColor = Color.white;
                    }

                    self.recalculateUI(.{
                        .width = winRelX(0.35),
                        .color = Color.blueGray,
                        .borderColor = Color.white,
                    });
                },

                false => {
                    debug.print("\nDeviceListUI: setting UI to INACTIVE.");

                    if (self.headerLabel) |*header| {
                        header.style.textColor = Color.lightGray;
                    }

                    self.recalculateUI(.{
                        .width = winRelX(0.16),
                        .color = Color.darkBlueGray,
                        .borderColor = Color.transparentDark,
                    });
                },
            }
        },

        Events.onUITransformQueried.Hash => {
            eventResult.validate(1);

            const responseDataPtr: *Events.onUITransformQueried.Response = try self.allocator.create(Events.onUITransformQueried.Response);

            responseDataPtr.* = .{
                .transform = if (self.bgRect) |bgRect| bgRect.transform else UIFramework.Primitives.Transform{
                    .x = 0,
                    .w = 0,
                    .h = 0,
                    .y = 0,
                },
            };

            eventResult.data = @ptrCast(@alignCast(responseDataPtr));
        },

        Events.onDevicesReadyToRender.Hash => {
            //
            debug.print("\nDeviceListUI: onDevicesReadyToRender() start.");

            // WARNING: General defer is OK here because no other call is coupled here where mutex lock would propagate.
            self.state.lock();
            defer self.state.unlock();

            if (self.state.data.devices.items.len < 1) {
                debug.print("\nDeviceListUI: onDevicesReadyToRender(): no devices discovered, breaking the event loop.");
                break :eventLoop;
            }

            debug.printf("\nDeviceListUI: onDevicesReadyToRender(): processing checkboxes for {d} devices.", .{self.state.data.devices.items.len});

            for (self.state.data.devices.items, 0..) |device, i| {
                //
                const selectDeviceContext = try self.allocator.create(DeviceList.SelectDeviceCallbackContext);

                // Define context for the checkbox's on-click behavior/callback
                selectDeviceContext.* = DeviceList.SelectDeviceCallbackContext{
                    .component = self.parent,
                    .selectedDevice = device,
                };

                // Buffered display string in a predefined format
                const deviceStringBuffer = self.allocator.allocSentinel(u8, 254, 0x00) catch |err| {
                    std.debug.panic("\n{any}", .{err});
                };

                _ = std.fmt.bufPrintZ(
                    deviceStringBuffer,
                    "{s} - {s} ({d:.0}GB)",
                    .{
                        device.deviceName,
                        std.mem.sliceTo(device.bsdName, 0x00),
                        @divTrunc(device.size, 1_000_000_000),
                    },
                ) catch |err| {
                    std.debug.panic("\n{any}", .{err});
                };

                debug.printf("\nComponentUI: formatted string is: {s}", .{deviceStringBuffer});

                try self.deviceCheckboxes.append(Checkbox.init(
                    @ptrCast(@alignCast(deviceStringBuffer)),
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

        // Fired when a device is selected, e.g. selectedDevice != null
        Events.onSelectedDeviceNameChanged.Hash => {
            //
            const data = Events.onSelectedDeviceNameChanged.getData(event) orelse break :eventLoop;
            eventResult.validate(1);

            {
                self.state.lock();
                defer self.state.unlock();
                self.state.data.selectedDevice = data.selectedDevice;
            }

            // BUG: Text display contains memory address? e.g.: "Sandisk 3.1Gen1@????"
            // Console print is clean, however. Bug appeared after commit 4c694ad, redefining USBStorageDevice comptime type.
            const labelDisplayName: [:0]const u8 = if (data.selectedDevice) |device| @ptrCast(@alignCast(std.mem.sliceTo(device.deviceName, 0x00))) else "NULL";
            debug.printf("\n\n\nDeviceListUI: labelDisplayName = {s}, len = {d}, original len = {d}\n\n\n", .{ labelDisplayName, labelDisplayName.len, data.selectedDevice.?.deviceName.len });

            if (self.bgRect) |bgRect| {
                self.deviceNameLabel = Text.init(labelDisplayName, .{
                    .x = bgRect.transform.relX(0.5),
                    .y = bgRect.transform.relY(0.5),
                }, .{
                    .fontSize = 14,
                });
            }

            // Toggle the "Next" button based on whether or not a device is selected
            if (self.button) |*button| {
                button.setEnabled(data.selectedDevice != null);
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

        if (self.moduleImg) |*image| {
            image.transform.x = bgRect.transform.relX(0.5) - image.transform.getWidth() / 2;
            image.transform.y = bgRect.transform.relY(0.5) - image.transform.getHeight() / 2;

            if (self.deviceNameLabel) |*deviceNameLabel| {
                deviceNameLabel.transform.x = bgRect.transform.relX(0.5) - deviceNameLabel.getDimensions().width / 2;
                deviceNameLabel.transform.y = image.transform.y + image.transform.getHeight() + winRelY(0.02);
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

pub fn update(self: *DeviceListUI) !void {
    self.state.lock();
    const isActive = self.state.data.isActive;
    self.state.unlock();

    if (!isActive) return;

    for (self.deviceCheckboxes.items) |*checkbox| {
        try checkbox.update();
    }

    if (self.button) |*button| {
        try button.update();
    }
}

pub fn draw(self: *DeviceListUI) !void {
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

fn drawActive(self: *DeviceListUI) !void {
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

    if (self.moduleImg) |img| {
        img.draw();
    }
}

pub fn deinit(self: *DeviceListUI) void {
    // if (self.state.data.selectedDeviceName) |deviceName| {
    //     self.parent.allocator.free(deviceName);
    // }

    for (self.deviceCheckboxes.items) |checkbox| {
        // Free the buffered display name (allocated via std.mem.buffPrintZ)
        self.allocator.free(checkbox.text.value);

        // Destroy the heap-based pointer to the checkbox's on-click context
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
