const std = @import("std");

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

const CHECKBOX_TEXT_MARGIN: f32 = 12;

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
allocator: std.mem.Allocator,
deviceId: u32,
transform: Transform,
outerRect: Rectangle,
innerRect: Rectangle,
text: Text,
state: CheckboxState = .NORMAL,
styles: CheckboxVariant,
clickHandler: CheckboxHandler,

pub fn init(allocator: std.mem.Allocator, deviceId: u32, text: [:0]const u8, position: rl.Vector2, size: f32, variant: CheckboxVariant, clickHandler: CheckboxHandler) Checkbox {
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
            .x = position.x + 3,
            .y = position.y + 3,
            .w = size - 6,
            .h = size - 6,
        },
    };

    var _text = Text.init(text, position, variant.normal.textStyle);

    const textDimensions = _text.getDimensions();

    _text.transform.x = position.x + outerRect.transform.w + CHECKBOX_TEXT_MARGIN;
    _text.transform.y = position.y + outerRect.transform.h / 2 - textDimensions.height / 2;

    return .{
        .allocator = allocator,
        .deviceId = deviceId,
        .transform = .{
            .x = position.x,
            .y = position.y,
            .w = outerRect.transform.w + CHECKBOX_TEXT_MARGIN + textDimensions.width,
            .h = if (size > textDimensions.height) size else textDimensions.height,
        },
        .state = .NORMAL,
        .outerRect = outerRect,
        .innerRect = innerRect,
        .text = _text,
        .styles = variant,
        .clickHandler = clickHandler,
    };
}

pub fn start(self: *Checkbox) !void {
    self.outerRect.style = self.styles.normal.outerRectStyle;
    self.innerRect.style = self.styles.normal.innerRectStyle;
    self.text.style = self.styles.normal.textStyle;
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
        if (self.state == .CHECKED) {
            // Handle state transition from CHECKED to NORMAL
            self.state = CheckboxState.NORMAL;
            self.clickHandler.handle();
        } else {
            // Handle State transition from NORMAL to CHECKED
            self.state = CheckboxState.CHECKED;
            self.clickHandler.handle();
        }
    } else if (isCheckboxHovered and !isCheckboxClicked) {
        if (self.state != .CHECKED) self.state = CheckboxState.HOVER;
    } else {
        if (self.state != .CHECKED) self.state = CheckboxState.NORMAL;
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
    self.allocator.free(self.text);
    self.allocator.destroy(self.clickHandler.context);
}

pub fn dispatchComponentAction(self: *Checkbox) void {
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
                .color = Color.transparent,
                .borderStyle = .{
                    .color = .white,
                    .thickness = 2,
                },
            },
            .innerRectStyle = .{
                .color = Color.transparent,
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
                .color = Color.transparent,
                .borderStyle = .{
                    .color = .white,
                    .thickness = 1.5,
                },
            },
            .innerRectStyle = .{
                .color = Color.secondary,
                .borderStyle = .{},
            },
            .textStyle = .{
                .font = .ROBOTO_REGULAR,
                .fontSize = 14,
                .spacing = 0,
                .textColor = Color.secondary,
            },
        },

        .checked = .{
            .outerRectStyle = .{
                .color = Color.transparent,
                .borderStyle = .{
                    .color = .white,
                    .thickness = 1.5,
                },
            },
            .innerRectStyle = .{
                .color = .white,
                .borderStyle = .{
                    .color = Color.transparent,
                },
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
