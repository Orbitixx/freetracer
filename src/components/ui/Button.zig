const std = @import("std");
const debug = @import("../../lib/util/debug.zig");

const rl = @import("raylib");

const ISOFilePickerUIState = struct {};

const ComponentFramework = @import("../framework/import/index.zig");
const Component = ComponentFramework.Component;
const ComponentState = ComponentFramework.ComponentState(ISOFilePickerUIState);
const ComponentWorker = ComponentFramework.Worker(ISOFilePickerUIState);

const AppObserver = @import("../../observers/AppObserver.zig").AppObserver;
const ObserverEvent = @import("../../observers/ObserverEvents.zig").ObserverEvent;
const ObserverPayload = @import("../../observers/ObserverPayload.zig");

const Primitives = @import("Primitives.zig");
const Text = Primitives.Text;
const Rectangle = Primitives.Rectangle;

const Styles = @import("./Styles.zig");
const ButtonStyle = Styles.ButtonStyle;
const ButtonStyles = Styles.ButtonStyles;

const Color = Styles.Color;

const Font = @import("../../managers/ResourceManager.zig").FONT;

const BUTTON_PADDING: f32 = 16;

pub const ButtonState = enum {
    NORMAL,
    HOVER,
    ACTIVE,
};

const ButtonComponent = @This();

ptr: *anyopaque,
vtable: *const VTable,

rect: Rectangle,
text: Text,
styles: ButtonStyles,
state: ButtonState = ButtonState.NORMAL,

pub const VTable = struct {
    init_fn: *const fn (ptr: *anyopaque) anyerror!void,
    deinit_fn: *const fn (ptr: *anyopaque) void,
    update_fn: *const fn (ptr: *anyopaque) anyerror!void,
    draw_fn: *const fn (ptr: *anyopaque) anyerror!void,
    notify_fn: *const fn (ptr: *anyopaque, event: ObserverEvent, payload: ObserverPayload) void,
};

pub fn init(text: [:0]const u8, position: rl.Vector2, styles: ButtonStyles) ButtonComponent {
    const btnText = Text.init(text, position, styles.normal);

    const textDimensions = btnText.getDimensions();

    const rect: Rectangle = .{
        .transform = .{
            .x = position.x,
            .y = position.y,
            .w = textDimensions.width + BUTTON_PADDING * 2,
            .h = textDimensions.height + BUTTON_PADDING,
        },
        .color = Color.white,
    };

    return .{
        .rect = rect,
        .text = Text.init(
            text,
            .{
                .x = position.x + (rect.transform.w / 2) - (textDimensions.width / 2),
                .y = position.y + (rect.transform.h / 2) - (textDimensions.height / 2),
            },
            styles.normal.textStyle,
        ),
        .styles = styles,
    };
}

/// Called once when Component is fully initialized
pub fn start(self: *ButtonComponent) void {
    _ = self;
}

pub fn update(self: *ButtonComponent) void {
    const mousePos: rl.Vector2 = rl.getMousePosition();
    const isButtonClicked: bool = rl.isMouseButtonPressed(.left);
    const isButtonHovered: bool = self.rect.transform.isPointWithinBounds(mousePos);

    // Don't bother updating if state change triggers are not present
    if (self.state == ButtonState.NORMAL and (!isButtonHovered or !isButtonClicked)) return;
    if (self.state == ButtonState.HOVER and (isButtonHovered and !isButtonClicked)) return;

    if (isButtonHovered and isButtonClicked) {
        self.state = ButtonState.ACTIVE;
    } else if (isButtonHovered) {
        self.state = ButtonState.HOVER;
    } else {
        self.state = ButtonState.NORMAL;
    }

    switch (self.state) {
        .HOVER => {
            self.rect.style = self.styles.hover.bgStyle;
            self.text.style = self.styles.hover.textStyle;
        },
        .ACTIVE => {
            self.rect.style = self.styles.active.bgStyle;
            self.text.style = self.styles.active.textStyle;
        },
        .NORMAL => {
            self.rect.style = self.styles.normal.bgStyle;
            self.text.style = self.styles.normal.textStyle;
        },
    }
}

pub fn draw(self: *ButtonComponent) void {
    self.rect.draw();
    self.text.draw();
}

pub fn deinit(self: *ButtonComponent) void {
    _ = self;
}

pub fn notify(self: *ButtonComponent, event: ObserverEvent, payload: ObserverPayload) void {
    _ = self;
    _ = event;
    _ = payload;
}

// pub fn asComponent(self: *ButtonComponent) Component {
//     //
//     const vtable = &Component.VTable{
//         //
//         .init_fn = ButtonComponent.start,
//         .deinit_fn = ButtonComponent.deinitWrapper,
//         .update_fn = ButtonComponent.updateWrapper,
//         .draw_fn = ButtonComponent.drawWrapper,
//         .notify_fn = ButtonComponent.notifyWrapper,
//     };
//
//     return ComponentFramework.Component.init(self, vtable);
// }
//
// pub fn asInstance(ptr: *anyopaque) *ButtonComponent {
//     return @ptrCast(@alignCast(ptr));
// }
