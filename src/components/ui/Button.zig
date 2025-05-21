const std = @import("std");
const debug = @import("../../lib/util/debug.zig");

const rl = @import("raylib");

const ButtonComponentState = struct {};

const ComponentFramework = @import("../framework/import/index.zig");
const Component = ComponentFramework.Component;
const ComponentState = ComponentFramework.ComponentState(ButtonComponentState);
const ComponentWorker = ComponentFramework.Worker(ButtonComponentState);

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

pub const ButtonHandler = struct {
    function: *const fn (ctx: *anyopaque) void,
    context: *anyopaque,

    fn handle(self: ButtonHandler) void {
        return self.function(self.context);
    }
};

const ButtonComponent = @This();

// TODO: Recall, this is a Component implementation so ComponentState and ComponentWorkers are available, if needed.

rect: Rectangle,
text: Text,
styles: ButtonStyles,
state: ButtonState = ButtonState.NORMAL,
clickHandler: ButtonHandler,

pub fn init(text: [:0]const u8, position: rl.Vector2, variant: ButtonVariant, clickHandler: ButtonHandler) ButtonComponent {
    const btnText = Text.init(text, position, variant.normal.textStyle);

    const textDimensions = btnText.getDimensions();

    const rect: Rectangle = .{
        .transform = .{
            .x = position.x,
            .y = position.y,
            .w = textDimensions.width + BUTTON_PADDING * 2,
            .h = textDimensions.height + BUTTON_PADDING,
        },
        .style = variant.normal.bgStyle,
    };

    return .{
        .rect = rect,
        .text = Text.init(
            text,
            .{
                .x = position.x + (rect.transform.w / 2) - (textDimensions.width / 2),
                .y = position.y + (rect.transform.h / 2) - (textDimensions.height / 2),
            },
            variant.normal.textStyle,
        ),
        .styles = variant.asButtonStyles(),
        .clickHandler = clickHandler,
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
    if (self.state == ButtonState.NORMAL and (!isButtonHovered and !isButtonClicked)) return;
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
            self.clickHandler.handle();
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

pub fn asInstance(ptr: *anyopaque) *ButtonComponent {
    return @ptrCast(@alignCast(ptr));
}

pub fn asComponent(self: *ButtonComponent) Component {
    const vtable = &Component.VTable{
        .init_fn = struct {
            fn lambda(ptr: *anyopaque) anyerror!void {
                ButtonComponent.asInstance(ptr).start();
            }
        }.lambda,

        .update_fn = struct {
            fn lambda(ptr: *anyopaque) anyerror!void {
                ButtonComponent.asInstance(ptr).update();
            }
        }.lambda,

        .draw_fn = struct {
            fn lambda(ptr: *anyopaque) anyerror!void {
                ButtonComponent.asInstance(ptr).draw();
            }
        }.lambda,

        .deinit_fn = struct {
            fn lambda(ptr: *anyopaque) void {
                ButtonComponent.asInstance(ptr).deinit();
            }
        }.lambda,

        .notify_fn = struct {
            fn lambda(ptr: *anyopaque, event: ObserverEvent, payload: ObserverPayload) void {
                ButtonComponent.asInstance(ptr).notify(event, payload);
            }
        }.lambda,
    };

    return Component.init(self, vtable);
}

pub const ButtonVariant = struct {
    normal: ButtonStyle = .{
        .bgStyle = .{},
        .textStyle = .{},
    },

    hover: ButtonStyle = .{
        .bgStyle = .{},
        .textStyle = .{},
    },

    active: ButtonStyle = .{
        .bgStyle = .{},
        .textStyle = .{},
    },

    pub const Primary: ButtonVariant = .{
        .normal = .{
            .bgStyle = .{
                .borderStyle = .{},
                .color = .{ .r = 115, .g = 102, .b = 162, .a = 255 },
            },
            .textStyle = .{
                .font = .ROBOTO_REGULAR,
                .fontSize = 14,
                .spacing = 0,
                .textColor = .white,
            },
        },
        .hover = .{
            .bgStyle = .{
                .borderStyle = .{},
                .color = .{ .r = 115, .g = 102, .b = 162, .a = 127 },
            },
            .textStyle = .{
                .font = .ROBOTO_REGULAR,
                .fontSize = 14,
                .spacing = 0,
                .textColor = .white,
            },
        },
        .active = .{
            .bgStyle = .{
                .borderStyle = .{},
                .color = .{ .r = 96, .g = 83, .b = 145, .a = 255 },
            },
            .textStyle = .{
                .font = .ROBOTO_REGULAR,
                .fontSize = 14,
                .spacing = 0,
                .textColor = .white,
            },
        },
    };

    fn asButtonStyles(self: ButtonVariant) ButtonStyles {
        return ButtonStyles{
            .normal = self.normal,
            .hover = self.hover,
            .active = self.active,
        };
    }
};
