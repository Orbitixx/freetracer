const std = @import("std");
const debug = @import("../../lib/util/debug.zig");

const System = @import("../../lib/sys/system.zig");
const USBStorageDevice = System.USBStorageDevice;

const MacOS = @import("../../modules/macos/MacOSTypes.zig");

const EventManager = @import("../../managers/EventManager.zig").EventManagerSingleton;

const ComponentFramework = @import("../framework/import/index.zig");
// const WorkerContext = @import("./WorkerContext.zig");

const DataFlasher = @import("./DataFlasher.zig");
const DeviceList = @import("../DeviceList/DeviceList.zig");
const DeviceListUI = @import("../DeviceList/DeviceListUI.zig");

const DataFlasherUIState = struct {
    isActive: bool = false,
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
    const initialDimensionsEvent = DeviceListUI.Events.onUITransformQueried.create(self.asComponentPtr(), null);
    const eventResult = try EventManager.signal("device_list_ui", initialDimensionsEvent);

    if (!eventResult.success or eventResult.data == null) return error.DataFlasherUICouldNotObtainInitialUIDimensions;

    if (eventResult.data) |dimensionsData| {
        const deviceListUIData: *DeviceListUI.Events.onUITransformQueried.Response = @ptrCast(@alignCast(dimensionsData));

        if (self.bgRect) |*bgRect| {
            bgRect.transform.x = deviceListUIData.transform.x + deviceListUIData.transform.getWidth() + 20;
        }

        self.allocator.destroy(deviceListUIData);
    }
}

pub fn update(self: *DataFlasherUI) !void {
    _ = self;
}

pub fn draw(self: *DataFlasherUI) !void {
    if (self.bgRect) |bgRect| {
        bgRect.draw();
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

            switch (data.isActive) {
                //
                true => {
                    debug.print("\nDataFlasherUI is now active");
                },

                false => {},
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

pub const ComponentImplementation = ComponentFramework.ImplementComponent(DataFlasherUI);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;
