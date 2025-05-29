const std = @import("std");
const debug = @import("../../lib/util/debug.zig");

const ISOFilePicker = @import("./TestComponent.zig").ISOFilePickerComponent;

const ComponentFramework = @import("../framework/import/index.zig");
const Component = ComponentFramework.Component;
const ComponentEvent = ComponentFramework.Event;
const EventResult = ComponentFramework.EventResult;

pub const ISOFilePickerUIState = struct {
    active: bool = true,
};
pub const ComponentState = ComponentFramework.ComponentState(ISOFilePickerUIState);

const ISOFilePickerUI = @This();

component: ?Component = null,
state: ComponentState,

pub fn init(parent: ?*Component) !ISOFilePickerUI {
    debug.print("\nISOFilePickerUI: start() called.");
    _ = parent;

    return ISOFilePickerUI{
        .state = ComponentState.init(ISOFilePickerUIState{}),
    };
}

pub fn initComponent(self: *ISOFilePickerUI, parent: ?*Component) !void {
    if (self.component != null) return error.BaseComponentAlreadyInitialized;
    self.component = try Component.init(self, &ComponentImplementation.vtable, parent);
}

pub fn start(self: *ISOFilePickerUI) !void {
    try self.initComponent(null);

    debug.print("\nISOFilePickerUI: component start() called.");
}

pub fn handleEvent(self: *ISOFilePickerUI, event: ComponentEvent) !EventResult {
    _ = self;
    _ = event;

    const eventResult = EventResult{
        .success = false,
        .validation = 0,
    };

    return eventResult;
}

pub fn update(self: *ISOFilePickerUI) !void {
    _ = self;
}

pub fn draw(self: *ISOFilePickerUI) !void {
    _ = self;
}

pub fn deinit(self: *ISOFilePickerUI) void {
    _ = self;
}

pub const ComponentImplementation = ComponentFramework.ImplementComponent(ISOFilePickerUI);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;
