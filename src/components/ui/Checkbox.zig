const std = @import("std");
const debug = @import("../../lib/util/debug.zig");

const rl = @import("raylib");

const ComponentFramework = @import("../framework/import/index.zig");
const Component = ComponentFramework.Component;

const Primitives = @import("Primitives.zig");
const Text = Primitives.Text;
const Rectangle = Primitives.Rectangle;
const Transform = Primitives.Transform;

const Styles = @import("./Styles.zig");
const CheckboxStyle = Styles.CheckboxStyle;
const CheckboxStyles = Styles.CheckboxStyles;

const Color = Styles.Color;

const Font = @import("../../managers/ResourceManager.zig").FONT;

pub const CheckboxState = enum {
    NORMAL,
    HOVER,
    CHECKED,
};

const CHECKBOX_TEXT_MARGIN: f32 = 16;

pub const CheckboxHandler = struct {
    function: *const fn (ctx: *anyopaque) void,
    context: *anyopaque,

    fn handle(self: CheckboxHandler) void {
        return self.function(self.context);
    }
};

const Checkbox = @This();

// Component-agnostic props
component: ?Component = null,

// Component-specific, unique props
transform: Transform,
outerRect: Rectangle,
innerRect: Rectangle,
text: Text,
state: CheckboxState = .NORMAL,
styles: CheckboxVariant,
clickHandler: CheckboxHandler,

pub fn init(text: [:0]const u8, position: rl.Vector2, size: f32, variant: CheckboxVariant, clickHandler: CheckboxHandler) Checkbox {
    const _text = Text.init(text, position, variant.normal.textStyle);

    const textDimensions = _text.getDimensions();

    const outerRect = Rectangle{
        .transform = .{
            .x = position.x,
            .y = position.y,
            .w = size,
            .h = size,
        },
        .bordered = false,
        .rounded = true,
    };

    const innerRect = Rectangle{
        .transform = .{
            .x = position.x + 2,
            .y = position.y + 2,
            .w = size - 2,
            .h = size - 2,
        },
    };

    return .{
        .transform = .{
            .x = position.x,
            .y = position.y,
            .w = outerRect + CHECKBOX_TEXT_MARGIN + textDimensions.width,
            .h = if (size > textDimensions.height) size else textDimensions.height,
        },
        .outerRect = outerRect,
        .innerRect = innerRect,
        .text = _text,
        .styles = variant,
        .clickHandler = clickHandler,
    };
}

pub fn start(self: *Checkbox) !void {
    _ = self;
}

pub fn initComponent(self: *Checkbox, parent: ?*Component) !void {
    if (self.component != null) return error.CheckboxBaseComponentAlreadyInitialized;
    self.component = try Component.init(self, &ComponentImplementation.vtable, parent);
}

pub fn update(self: *Checkbox) !void {
    const mousePos: rl.Vector2 = rl.getMousePosition();
    const isCheckboxClicked: bool = rl.isMouseButtonPressed(.left);
    const isCheckboxHovered: bool = self.transform.isPointWithinBounds(mousePos);

    // Don't bother updating if state change triggers are not present
    if (self.state == CheckboxState.NORMAL and (!isCheckboxHovered and !isCheckboxClicked)) return;
    if (self.state == CheckboxState.HOVER and (isCheckboxHovered and !isCheckboxClicked)) return;

    if (isCheckboxHovered and isCheckboxClicked) {
        self.state = CheckboxState.CHECKED;
    } else if (isCheckboxHovered) {
        self.state = CheckboxState.HOVER;
    } else {
        self.state = CheckboxState.NORMAL;
    }

    switch (self.state) {
        .HOVER => {
            self.outerRect.style = self.styles.hover.outerRectStyle;
            self.innerRect.style = self.styles.hover.innerRectStyle;
            self.text.style = self.styles.hover.textStyle;
        },
        .CHECKED => {
            self.outerRect.style = self.styles.checked.outerRectStyle;
            self.innerRect.style = self.styles.checked.innerRectStyle;
            self.text.style = self.styles.checked.textStyle;
            self.clickHandler.handle();
        },
        .NORMAL => {
            self.outerRect.style = self.styles.normal.outerRectStyle;
            self.innerRect.style = self.styles.normal.innerRectStyle;
            self.text.style = self.styles.normal.textStyle;
        },
    }
}

pub fn draw(self: *Checkbox) !void {
    self.outerRect.draw();
    self.innerRect.draw();
    self.text.draw();
}

pub fn handleEvent(self: *Checkbox, event: ComponentFramework.Event) !ComponentFramework.EventResult {
    _ = self;
    _ = event;

    return .{
        .success = true,
        .validation = 1,
    };
}

pub fn deinit(self: *Checkbox) void {
    _ = self;
}

pub fn dispatchComponentAction(self: *Checkbox) !void {
    _ = self;
}

pub const ComponentImplementation = ComponentFramework.ImplementComponent(Checkbox);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;

pub const CheckboxVariant = struct {
    normal: CheckboxStyle = .{},
    hover: CheckboxStyle = .{},
    checked: CheckboxStyle = .{},

    pub const Primary: CheckboxVariant = .{
        .normal = .{
            .outerRectStyle = .{
                .color = .transparent,
                .borderStyle = .{
                    .color = .white,
                    .thickness = 1.5,
                },
            },
            .innerRectStyle = .{
                .color = .transparent,
                .borderStyle = .{},
            },
            .textStyle = .{
                .font = .ROBOTO_REGULAR,
                .fontSize = 14,
                .spacing = 0,
                .textColor = .white,
            },
        },

        .hover = .{
            .outerRectStyle = .{
                .color = .transparent,
                .borderStyle = .{
                    .color = .white,
                    .thickness = 1.5,
                },
            },
            .innerRectStyle = .{
                .color = .secondary,
                .borderStyle = .{},
            },
            .textStyle = .{
                .font = .ROBOTO_REGULAR,
                .fontSize = 14,
                .spacing = 0,
                .textColor = .secondary,
            },
        },

        .checked = .{
            .outerRectStyle = .{
                .color = .white,
                .borderStyle = .{
                    .color = .white,
                    .thickness = 1.5,
                },
            },
            .innerRectStyle = .{
                .color = .white,
                .borderStyle = .{},
            },
            .textStyle = .{
                .font = .ROBOTO_REGULAR,
                .fontSize = 14,
                .spacing = 0,
                .textColor = .white,
            },
        },
    };
};
