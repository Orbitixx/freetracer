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
parent: *ISOFilePicker,
state: ComponentState,

pub fn init(parent: *ISOFilePicker) ISOFilePickerUI {
    return .{
        .state = ComponentState.init(ISOFilePickerUIState{}),
        .parent = parent,
    };
}

pub fn initComponent(self: *ISOFilePickerUI) void {
    self.component = Component.init(self, &ComponentImplementation.vtable);
}

pub fn start(self: *ISOFilePickerUI) !void {
    if (self.component == null) self.initComponent();

    debug.print("\nHello from ISOFilePicker UI component start() method!");
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
pub const asInstance = ComponentImplementation.asInstance;
