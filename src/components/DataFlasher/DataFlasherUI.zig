const std = @import("std");
const debug = @import("../../lib/util/debug.zig");

const MacOS = @import("../../modules/macos/MacOSTypes.zig");

const EventManager = @import("../../managers/EventManager.zig").EventManagerSingleton;

const ComponentFramework = @import("../framework/import/index.zig");
// const WorkerContext = @import("./WorkerContext.zig");

const DataFlasher = @import("./DataFlasher.zig");

const DataFlasherUIState = struct {
    device: ?MacOS.USBStorageDevice = null,
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
    pub const onSomething = ComponentFramework.defineEvent("data_flasher.on_", struct {});
};

pub fn init(allocator: std.mem.Allocator, parent: *DataFlasher) DataFlasherUI {
    return DataFlasherUI{
        .state = DataFlasherUIState{},
        .allocator = allocator,
        .parent = parent,
    };
}

pub fn initComponent(self: *DataFlasherUI, parent: *DataFlasher) !void {
    if (self.component != null) return error.BaseComponentAlreadyInitialized;
    self.component = try Component.init(self, &ComponentImplementation.vtable, parent);
}

pub fn start(self: *DataFlasherUI) !void {
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
    // const event = ISOFilePickerUI.Events.ISOFilePickerUIGetUIDimensions.create(&self.component.?, null);
    // EventManager.broadcast(event);
}

pub fn update(self: *DataFlasherUI) !void {
    _ = self;
}

pub fn draw(self: *DataFlasherUI) !void {
    _ = self;
}

pub fn handleEvent(self: *DataFlasherUI, event: ComponentEvent) !EventResult {
    _ = self;

    var eventResult = EventResult{
        .success = false,
        .validation = 0,
    };

    eventLoop: switch (event.hash) {
        //
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
pub fn dispatchComponentAction(self: *DataFlasherUI) !void {
    _ = self;
}
pub fn deinit(self: *DataFlasherUI) void {
    _ = self;
}

pub const ComponentImplementation = ComponentFramework.ImplementComponent(DataFlasher);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;
