const std = @import("std");
const rl = @import("raylib");
const freetracer_lib = @import("freetracer-lib");
const Debug = freetracer_lib.Debug;
const Character = freetracer_lib.Character;

const AppConfig = @import("../../config.zig");

const StorageDevice = freetracer_lib.StorageDevice;

const WindowManager = @import("../../managers/WindowManager.zig").WindowManagerSingleton;
const winRelX = WindowManager.relW;
const winRelY = WindowManager.relH;

const EventManager = @import("../../managers/EventManager.zig").EventManagerSingleton;
const ComponentName = EventManager.ComponentName.DEVICE_LIST_UI;

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
    devices: *std.ArrayList(StorageDevice),
    selectedDevice: ?StorageDevice = null,
};

pub const ComponentState = ComponentFramework.ComponentState(DeviceListUIState);

const DeviceListUI = @This();

const COMPONENT_UI_GAP: f32 = 20;
const MAX_DISPLAY_STRING_LENGTH: usize = 254;

// Component-agnostic props
state: ComponentState,
component: ?Component = null,

// Component-specific, unique props
allocator: std.mem.Allocator,
parent: *DeviceList,
deviceCheckboxes: std.ArrayList(Checkbox),
bgRect: Rectangle = undefined,
headerLabel: Text = undefined,
moduleImg: Texture = undefined,
nextButton: Button = undefined,
deviceNameLabel: Text = undefined,
noDevicesLabel: Text = undefined,
refreshDevicesButton: Button = undefined,

const BgRectParams = struct {
    width: f32,
    color: rl.Color,
    borderColor: rl.Color,
};

pub const Events = struct {
    //
    pub const onDeviceListUIActiveStateChanged = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_active_state_changed"),
        struct { isActive: bool },
        struct {},
    );

    pub const onDevicesReadyToRender = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_devices_ready_to_render"),
        struct {},
        struct {},
    );

    pub const onSelectedDeviceNameChanged = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_device_name_changed"),
        struct {
            // Not authoritative data; copy only -- use parent for authoritative.
            selectedDevice: ?StorageDevice,
        },
        struct {},
    );

    pub const onUITransformQueried = ComponentFramework.defineEvent(
        EventManager.createEventName(ComponentName, "on_ui_transform_queried"),
        struct {},
        struct { transform: UIFramework.Primitives.Transform },
    );
};

// Creates and returns an instance of DeviceListUI component
pub fn init(allocator: std.mem.Allocator, parent: *DeviceList) !DeviceListUI {
    Debug.log(.DEBUG, "DeviceListUI: start() called.", .{});

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
    Debug.log(.DEBUG, "DeviceListUI: component start() called.", .{});

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

    self.nextButton = Button.init(
        "Next",
        null,
        self.bgRect.transform.getPosition(),
        .Primary,
        .{
            .context = self.parent,
            .function = DeviceList.dispatchComponentFinishedAction.call,
        },
    );

    self.nextButton.setEnabled(false);

    self.refreshDevicesButton = Button.init(
        "",
        .RELOAD_ICON,
        self.bgRect.transform.getPosition(),
        .Primary,
        .{
            .context = self.parent,
            .function = refreshDevices.call,
        },
    );

    self.refreshDevicesButton.rect.rounded = true;

    self.headerLabel = Text.init(
        "device",
        .{
            .x = self.bgRect.transform.x + 12,
            .y = self.bgRect.transform.relY(0.01),
        },
        .{
            .font = .JERSEY10_REGULAR,
            .fontSize = 34,
            .textColor = Styles.Color.white,
        },
    );

    self.moduleImg = Texture.init(.USB_IMAGE, .{ .x = 0, .y = 0 });
    self.moduleImg.transform.scale = 0.5;
    self.moduleImg.transform.x = self.bgRect.transform.relX(0.5) - self.moduleImg.transform.getWidth() / 2;
    self.moduleImg.transform.y = self.bgRect.transform.relY(0.5) - self.moduleImg.transform.getHeight() / 2;
    self.moduleImg.tint = .{ .r = 255, .g = 255, .b = 255, .a = 150 };

    try self.nextButton.start();

    self.nextButton.setPosition(.{
        .x = self.bgRect.transform.relX(0.5) - @divTrunc(self.nextButton.rect.transform.getWidth(), 2),
        .y = self.bgRect.transform.relY(0.9) - @divTrunc(self.nextButton.rect.transform.getHeight(), 2),
    });

    self.nextButton.rect.rounded = true;

    self.noDevicesLabel = Text.init("No external devices found...", .{ .x = 0, .y = 0 }, .{ .fontSize = 14 });
    self.deviceNameLabel = Text.init("No device selected...", .{ .x = 0, .y = 0 }, .{ .fontSize = 14 });
    self.deviceNameLabel.transform.x = self.bgRect.transform.relX(0.5) - self.deviceNameLabel.getDimensions().width / 2;
    self.deviceNameLabel.transform.y = self.moduleImg.transform.y + self.moduleImg.transform.getHeight() + winRelY(0.02);

    Debug.log(.DEBUG, "DeviceListUI: component start() finished.", .{});
}

pub fn handleEvent(self: *DeviceListUI, event: ComponentEvent) !EventResult {
    Debug.log(.INFO, "DeviceListUI: handleEvent() received an event: \"{s}\"", .{event.name});

    var eventResult = EventResult.init();

    eventLoop: switch (event.hash) {

        // ISOFilePickerUI emits this event in response to receiving the same event
        ISOFilePickerUI.Events.onGetUIDimensions.Hash => {
            //
            const data = ISOFilePickerUI.Events.onGetUIDimensions.getData(event) orelse break :eventLoop;
            eventResult.validate(.SUCCESS);

            self.bgRect.transform.x = data.transform.x + data.transform.w + 20;
        },

        ISOFilePicker.Events.onActiveStateChanged.Hash => {
            //
            const data = ISOFilePicker.Events.onActiveStateChanged.getData(event) orelse break :eventLoop;

            // Dispatch a parent event that the current component already listens to (for simplicity)
            return try self.handleEvent(DeviceList.Events.onDeviceListActiveStateChanged.create(
                self.asComponentPtr(),
                // Set the __opposite__ of the ISOFilePicker active state.
                &.{ .isActive = !data.isActive },
            ));
        },

        DeviceList.Events.onDeviceListActiveStateChanged.Hash => {
            //
            const data = DeviceList.Events.onDeviceListActiveStateChanged.getData(event) orelse break :eventLoop;
            eventResult.validate(.SUCCESS);

            // Update state in a block with a shorter lifecycle
            {
                self.state.lock();
                defer self.state.unlock();
                self.state.data.isActive = data.isActive;
            }

            switch (data.isActive) {
                true => {
                    Debug.log(.DEBUG, "DeviceListUI: setting UI to ACTIVE.", .{});

                    self.headerLabel.style.textColor = Color.white;

                    self.recalculateUI(.{
                        .width = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_ACTIVE),
                        .color = Color.blueGray,
                        .borderColor = Color.white,
                    });
                },

                false => {
                    Debug.log(.DEBUG, "DeviceListUI: setting UI to INACTIVE.", .{});

                    self.headerLabel.style.textColor = Color.lightGray;

                    self.recalculateUI(.{
                        .width = winRelX(AppConfig.APP_UI_MODULE_PANEL_WIDTH_INACTIVE),
                        .color = Color.darkBlueGray,
                        .borderColor = Color.transparentDark,
                    });
                },
            }
        },

        DeviceList.Events.onDevicesCleanup.Hash => {
            self.deviceNameLabel.value = "NULL";

            self.state.lock();
            defer self.state.unlock();

            self.state.data.selectedDevice = null;

            eventResult.validate(.SUCCESS);
        },

        Events.onUITransformQueried.Hash => {
            eventResult.validate(.SUCCESS);

            const responseDataPtr: *Events.onUITransformQueried.Response = try self.allocator.create(Events.onUITransformQueried.Response);

            responseDataPtr.* = .{
                .transform = self.bgRect.transform,
            };

            eventResult.data = @ptrCast(@alignCast(responseDataPtr));
        },

        Events.onDevicesReadyToRender.Hash => {
            //
            Debug.log(.DEBUG, "DeviceListUI: onDevicesReadyToRender() start.", .{});

            // WARNING: General defer is OK here because no other call is coupled here where mutex lock would propagate.
            self.state.lock();
            defer self.state.unlock();

            if (self.state.data.devices.items.len < 1) {
                Debug.log(.WARNING, "DeviceListUI: onDevicesReadyToRender(): no devices discovered, breaking the event loop.", .{});
                break :eventLoop;
            }

            Debug.log(.DEBUG, "DeviceListUI: onDevicesReadyToRender(): processing checkboxes for {d} devices.", .{self.state.data.devices.items.len});

            for (self.state.data.devices.items, 0..) |*device, i| {
                //
                const selectDeviceContext = try self.allocator.create(DeviceList.SelectDeviceCallbackContext);

                // Define context for the checkbox's on-click behavior/callback
                selectDeviceContext.* = DeviceList.SelectDeviceCallbackContext{
                    .component = self.parent,
                    .selectedDevice = device.*,
                };

                var textBuf: [AppConfig.CHECKBOX_TEXT_BUFFER_SIZE]u8 = std.mem.zeroes([AppConfig.CHECKBOX_TEXT_BUFFER_SIZE]u8);

                const deviceName = std.mem.sliceTo(device.deviceName[0..], Character.NULL);
                const bsdName = device.getBsdNameSlice();

                _ = std.fmt.bufPrintZ(
                    textBuf[0..],
                    "{s} - {s} ({d:.0}GB)",
                    .{
                        if (deviceName.len > 20) deviceName[0..20] else deviceName,
                        if (bsdName.len > 10) bsdName[0..10] else bsdName,
                        @divTrunc(device.size, 1_000_000_000),
                    },
                ) catch |err| {
                    std.debug.panic("{any}", .{err});
                };

                Debug.log(.DEBUG, "ComponentUI: formatted string is: {s}", .{std.mem.sliceTo(textBuf[0..], Character.NULL)});

                try self.deviceCheckboxes.append(Checkbox.init(
                    self.allocator,
                    device.serviceId,
                    textBuf,
                    .{
                        .x = self.bgRect.transform.relX(0.05),
                        .y = self.bgRect.transform.relY(0.12) + @as(f32, @floatFromInt(i)) * 25,
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
            Debug.log(.DEBUG, "DeviceListUI: onDevicesReadyToRender() end.", .{});
        },

        // Fired when a device is selected, e.g. selectedDevice != null
        Events.onSelectedDeviceNameChanged.Hash => {
            //
            const data = Events.onSelectedDeviceNameChanged.getData(event) orelse break :eventLoop;

            // WARNING: Mutex lock is used within broader scope of this event instead of dedicated scope. OK as of the moment of implementation.
            self.state.lock();
            defer self.state.unlock();
            self.state.data.selectedDevice = data.selectedDevice;

            // TODO: doesn't quite fix the visual selection bug with multiple devices
            {
                for (self.deviceCheckboxes.items) |*cb| {
                    cb.state = .NORMAL;
                }

                if (data.selectedDevice) |device| {
                    for (self.deviceCheckboxes.items) |*cb| {
                        if (device.serviceId == cb.deviceId) cb.state = .CHECKED;
                    }
                }
            }

            Debug.log(.DEBUG, "DeviceListUI.handleEvent.onSelectedDeviceNameChanged received selectedDevice: \n{s}\n\n", .{data.selectedDevice.?.getNameSlice()});

            self.deviceNameLabel = Text.init(if (self.state.data.selectedDevice) |*device| device.getNameSlice() else "NULL", .{
                .x = self.bgRect.transform.relX(0.5),
                .y = self.bgRect.transform.relY(0.5),
            }, .{
                .fontSize = 14,
            });

            // Toggle the "Next" button based on whether or not a device is selected
            self.nextButton.setEnabled(data.selectedDevice != null);

            eventResult.validate(.SUCCESS);
        },
        else => {},
    }

    return eventResult;
}

pub fn update(self: *DeviceListUI) !void {
    self.state.lock();
    const isActive = self.state.data.isActive;
    self.state.unlock();

    if (!isActive) return;

    for (self.deviceCheckboxes.items) |*checkbox| {
        try checkbox.update();
    }

    try self.refreshDevicesButton.update();
    try self.nextButton.update();
}

pub fn draw(self: *DeviceListUI) !void {
    self.state.lock();
    const isActive = self.state.data.isActive;
    self.state.unlock();

    self.bgRect.draw();
    self.headerLabel.draw();

    if (isActive) try self.drawActive() else try self.drawInactive();
}

fn drawActive(self: *DeviceListUI) !void {
    self.state.lock();
    const foundDevices = self.state.data.devices.items.len > 0;
    self.state.unlock();

    if (!foundDevices) {
        self.noDevicesLabel.draw();
    }

    for (self.deviceCheckboxes.items) |*checkbox| {
        try checkbox.draw();
    }

    try self.refreshDevicesButton.draw();
    try self.nextButton.draw();
}

fn drawInactive(self: *DeviceListUI) !void {
    self.deviceNameLabel.draw();
    self.moduleImg.draw();
}

pub fn deinit(self: *DeviceListUI) void {
    for (self.deviceCheckboxes.items) |checkbox| {
        // Destroy the heap-based pointer to the checkbox's on-click context
        const ctx: *DeviceList.SelectDeviceCallbackContext = @ptrCast(@alignCast(checkbox.clickHandler.context));
        self.allocator.destroy(ctx);
    }

    self.deviceCheckboxes.deinit();
}

pub fn dispatchComponentAction(self: *DeviceListUI) void {
    _ = self;
}

fn recalculateUI(self: *DeviceListUI, bgRectParams: BgRectParams) void {
    Debug.log(.DEBUG, "DeviceListUI: updating self.bgRect properties!", .{});

    self.bgRect.transform.w = bgRectParams.width;
    self.bgRect.style.color = bgRectParams.color;
    self.bgRect.style.borderStyle.color = bgRectParams.borderColor;

    self.headerLabel.transform.x = self.bgRect.transform.x + 12;
    self.headerLabel.transform.y = self.bgRect.transform.relY(0.01);

    const dims = self.noDevicesLabel.getDimensions();
    self.noDevicesLabel.transform.x = self.bgRect.transform.relX(0.5) - dims.width / 2;
    self.noDevicesLabel.transform.y = self.bgRect.transform.relY(0.5) - dims.height / 2;

    self.state.lock();
    errdefer self.state.unlock();
    // BUG: appears to be truthy when no devices are found
    const devicesFound = self.state.data.devices.items.len > 0;
    self.state.unlock();

    if (devicesFound) {
        self.refreshDevicesButton.setPosition(.{
            .x = self.bgRect.transform.relX(0.9) - self.refreshDevicesButton.rect.transform.getWidth() / 2,
            .y = self.bgRect.transform.relY(0.1) - self.refreshDevicesButton.rect.transform.getHeight() / 2,
        });
    } else {
        self.refreshDevicesButton.setPosition(.{
            .x = self.bgRect.transform.relX(0.5) - self.refreshDevicesButton.rect.transform.getWidth() / 2,
            .y = self.noDevicesLabel.transform.y + self.noDevicesLabel.transform.h + winRelY(0.02),
        });
    }

    self.moduleImg.transform.x = self.bgRect.transform.relX(0.5) - self.moduleImg.transform.getWidth() / 2;
    self.moduleImg.transform.y = self.bgRect.transform.relY(0.5) - self.moduleImg.transform.getHeight() / 2;

    self.deviceNameLabel.transform.x = self.bgRect.transform.relX(0.5) - self.deviceNameLabel.getDimensions().width / 2;
    self.deviceNameLabel.transform.y = self.moduleImg.transform.y + self.moduleImg.transform.getHeight() + winRelY(0.02);

    self.refreshDevicesButton.setPosition(.{
        .x = self.bgRect.transform.relX(0.95) - self.refreshDevicesButton.rect.transform.getWidth(),
        .y = self.bgRect.transform.relY(0.05),
    });

    self.nextButton.setPosition(.{
        .x = self.bgRect.transform.relX(0.5) - self.nextButton.rect.transform.getWidth() / 2,
        .y = self.nextButton.rect.transform.y,
    });
}

const refreshDevices = struct {
    fn call(ctx: *anyopaque) void {
        const component = DeviceList.asInstance(ctx);

        if (component.uiComponent) |*ui| {
            if (ui.deviceCheckboxes.items.len > 0) {
                for (ui.deviceCheckboxes.items) |*cb| {
                    const p: *DeviceList.SelectDeviceCallbackContext = @ptrCast(@alignCast(cb.clickHandler.context));
                    cb.allocator.destroy(p);
                }

                ui.deviceCheckboxes.clearAndFree();
            }
        }

        component.dispatchComponentAction();
    }
};

pub const ComponentImplementation = ComponentFramework.ImplementComponent(DeviceListUI);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;
