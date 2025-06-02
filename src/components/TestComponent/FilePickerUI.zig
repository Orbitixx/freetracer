const std = @import("std");
const debug = @import("../../lib/util/debug.zig");
const rl = @import("raylib");

const WindowManager = @import("../../managers/WindowManager.zig").WindowManagerSingleton;
const winRelX = WindowManager.relW;
const winRelY = WindowManager.relH;

const ISOFilePicker = @import("./TestComponent.zig").ISOFilePickerComponent;

const ComponentFramework = @import("../framework/import/index.zig");
const Component = ComponentFramework.Component;
const ComponentEvent = ComponentFramework.Event;
const EventResult = ComponentFramework.EventResult;

const UIFramework = @import("../ui/import/index.zig");
const Button = UIFramework.Button;
const Styles = UIFramework.Styles;

pub const ISOFilePickerUIState = struct {
    active: bool = true,
};
pub const ComponentState = ComponentFramework.ComponentState(ISOFilePickerUIState);

const ISOFilePickerUI = @This();

component: ?Component = null,
state: ComponentState,
parent: *ISOFilePicker,
bgRect: ?UIFramework.Primitives.Rectangle = null,
button: ?Button = null,

pub fn init(parent: *ISOFilePicker) !ISOFilePickerUI {
    debug.print("\nISOFilePickerUI: start() called.");

    return ISOFilePickerUI{
        .state = ComponentState.init(ISOFilePickerUIState{}),
        .parent = parent,
    };
}

pub fn initComponent(self: *ISOFilePickerUI, parent: ?*Component) !void {
    if (self.component != null) return error.BaseComponentAlreadyInitialized;
    self.component = try Component.init(self, &ComponentImplementation.vtable, parent);
}

pub fn start(self: *ISOFilePickerUI) !void {
    debug.print("\nISOFilePickerUI: component start() called.");

    if (self.component == null) try self.initComponent(self.parent.asComponentPtr());

    self.bgRect = UIFramework.Primitives.Rectangle{
        .transform = .{ .x = winRelX(0.08), .y = winRelY(0.2), .w = winRelX(0.35), .h = winRelY(0.7) },
        .style = .{
            .color = Styles.Color.transparentDark,
            .borderStyle = .{
                .color = Styles.Color.white,
            },
        },
        .rounded = true,
    };

    if (self.bgRect) |bgRect| {
        self.button = Button.init(
            "SELECT ISO",
            bgRect.transform.getPosition(),
            .Primary,
            .{
                .context = self.parent,
                .function = ISOFilePicker.dispatchComponentActionWrapper.call,
            },
        );

        if (self.button) |*button| {
            try button.start();
            button.rect.transform.x = bgRect.transform.relX(0.5) - @divTrunc(button.rect.transform.w, 2);
            button.rect.transform.y = bgRect.transform.relX(0.9) - @divTrunc(button.rect.transform.h, 2);
            button.rect.rounded = true;
        }
    }

    debug.print("\nISOFilePickerUI: component start() finished.");
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
    if (self.button) |*button| {
        try button.update();
    }
}

pub fn draw(self: *ISOFilePickerUI) !void {
    if (self.bgRect) |bgRect| {
        bgRect.draw();
    }

    if (self.button) |*button| {
        try button.draw();
    }
}

pub fn deinit(self: *ISOFilePickerUI) void {
    _ = self;
}

pub fn dispatchComponentAction(self: *ISOFilePickerUI) void {
    _ = self;
}

pub const ComponentImplementation = ComponentFramework.ImplementComponent(ISOFilePickerUI);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;
