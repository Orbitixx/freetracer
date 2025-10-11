const std = @import("std");
const rl = @import("raylib");

const ResourceManager = @import("../../managers/ResourceManager.zig").ResourceManagerSingleton;
const Texture = @import("../../managers/ResourceManager.zig").Texture;
const TextureResource = @import("../../managers/ResourceManager.zig").TextureResource;

const ComponentFramework = @import("../framework/import/index.zig");
const Component = ComponentFramework.Component;

const Event = ComponentFramework.Event;
const EventResult = ComponentFramework.EventResult;
const defineEvent = ComponentFramework.defineEvent;

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
    DISABLED,
};

pub const ButtonParams = struct {
    disableOnClick: bool = false,
};

pub const ButtonHandler = struct {
    function: *const fn (ctx: *anyopaque) void,
    context: *anyopaque,

    fn handle(self: ButtonHandler) void {
        return self.function(self.context);
    }
};

const ButtonComponent = @This();

// Component-agnostic props
component: ?Component = null,
allocator: std.mem.Allocator,

// Component-specific, unique props
rect: Rectangle,
texture: ?Texture = null,
text: Text,
styles: ButtonStyles,
state: ButtonState = ButtonState.NORMAL,
clickHandler: ButtonHandler,
params: ButtonParams = .{},
cursorActive: bool = false,

pub const Events = struct {
    pub const onButtonToggleEnabled = defineEvent(
        "button.on_toggle_enabled",
        struct {
            isEnabled: bool,
        },
        struct {},
    );
};

pub fn init(
    text: [:0]const u8,
    texture: ?TextureResource,
    position: rl.Vector2,
    variant: ButtonVariant,
    clickHandler: ButtonHandler,
    allocator: std.mem.Allocator,
) ButtonComponent {
    const btnText = Text.init(text, position, variant.normal.textStyle);

    const textDimensions = btnText.getDimensions();

    const rect: Rectangle = .{
        .transform = .{
            .x = position.x,
            .y = position.y,
            .w = if (text.len > 0) textDimensions.width + BUTTON_PADDING * 2 else BUTTON_PADDING * 2,
            .h = if (text.len > 0) textDimensions.height + BUTTON_PADDING else BUTTON_PADDING * 2,
        },
        .style = variant.normal.bgStyle,
    };

    return .{
        .allocator = allocator,
        .rect = rect,
        .text = Text.init(
            text,
            .{
                .x = position.x + (rect.transform.w / 2) - (textDimensions.width / 2),
                .y = position.y + (rect.transform.h / 2) - (textDimensions.height / 2),
            },
            variant.normal.textStyle,
        ),
        .texture = if (texture) |resource| ResourceManager.getTexture(resource) else null,
        .styles = variant.asButtonStyles(),
        .clickHandler = clickHandler,
    };
}

pub fn initComponent(self: *ButtonComponent, parent: ?*Component) !void {
    if (self.component != null) return error.ButtonBaseComponentAlreadyInitialized;
    self.component = try Component.init(self, &ComponentImplementation.vtable, parent, self.allocator);
}

/// Called once when Component is fully initialized
pub fn start(self: *ButtonComponent) !void {
    if (self.component == null) try self.initComponent(null);

    if (self.texture) |*texture| {
        texture.width = @intFromFloat(self.rect.transform.getWidth() * 0.75);
        texture.height = @intFromFloat(self.rect.transform.getHeight() * 0.75);
    }
}

pub fn setPosition(self: *ButtonComponent, position: rl.Vector2) void {
    self.rect.transform.x = position.x;
    self.rect.transform.y = position.y;
    self.text.transform.x = position.x + (self.rect.transform.w / 2) - (self.text.getDimensions().width / 2);
    self.text.transform.y = position.y + (self.rect.transform.h / 2) - (self.text.getDimensions().height / 2);
}

pub fn update(self: *ButtonComponent) !void {
    const mousePos: rl.Vector2 = rl.getMousePosition();
    const isButtonHovered: bool = self.rect.transform.isPointWithinBounds(mousePos);
    const wantsCursor = isButtonHovered and self.state != ButtonState.DISABLED;

    if (wantsCursor and !self.cursorActive) {
        rl.setMouseCursor(.pointing_hand);
        self.cursorActive = true;
    } else if (!wantsCursor and self.cursorActive) {
        rl.setMouseCursor(.default);
        self.cursorActive = false;
    }

    if (self.state == ButtonState.DISABLED) return;

    const isButtonClicked: bool = rl.isMouseButtonPressed(.left);

    // Don't bother updating if state change triggers are not present
    if (self.state == ButtonState.NORMAL and (!isButtonHovered and !isButtonClicked)) return;
    if (self.state == ButtonState.HOVER and (isButtonHovered and !isButtonClicked)) return;

    if (isButtonHovered and isButtonClicked) {
        self.state = ButtonState.ACTIVE;
        if (self.params.disableOnClick) self.setEnabled(false);
        self.clickHandler.handle();
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
        .DISABLED => {
            self.rect.style = self.styles.disabled.bgStyle;
            self.text.style = self.styles.disabled.textStyle;
        },
    }
}

pub fn draw(self: *ButtonComponent) !void {
    self.rect.draw();
    self.text.draw();

    if (self.texture) |*texture| {
        texture.drawEx(.{
            .x = self.rect.transform.x + (self.rect.transform.getWidth() / 2) - (@as(f32, @floatFromInt(texture.width)) / 2),
            .y = self.rect.transform.y + (self.rect.transform.getHeight() / 2) - (@as(f32, @floatFromInt(texture.height)) / 2),
        }, 0, 1, Color.white);
    }
}

pub fn handleEvent(self: *ButtonComponent, event: Event) !EventResult {
    //
    var eventResult = ComponentFramework.EventResult.init();

    eventLoop: switch (event.hash) {
        Events.onButtonToggleEnabled.Hash => {
            //
            const data = Events.onButtonToggleEnabled.getData(event) orelse break :eventLoop;
            self.setEnabled(data.isEnabled);
            eventResult.validate(.SUCCESS);
        },
        else => {},
    }

    return eventResult;
}

pub fn setEnabled(self: *ButtonComponent, flag: bool) void {
    switch (flag) {
        true => {
            self.state = .NORMAL;
            self.rect.style = self.styles.normal.bgStyle;
            self.text.style = self.styles.normal.textStyle;
        },
        false => {
            if (self.cursorActive) {
                rl.setMouseCursor(.default);
                self.cursorActive = false;
            }
            self.state = .DISABLED;
            self.rect.style = self.styles.disabled.bgStyle;
            self.text.style = self.styles.disabled.textStyle;
        },
    }
}

pub fn deinit(self: *ButtonComponent) void {
    _ = self;
}

pub fn dispatchComponentAction(self: *ButtonComponent) void {
    _ = self;
}

pub const ComponentImplementation = ComponentFramework.ImplementComponent(ButtonComponent);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;

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

    disabled: ButtonStyle = .{
        .bgStyle = .{},
        .textStyle = .{},
    },

    pub const Primary: ButtonVariant = .{
        .normal = .{
            .bgStyle = .{
                .borderStyle = .{},
                .color = .{ .r = 115, .g = 102, .b = 162, .a = 255 },
                .roundness = 0.2,
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
                .roundness = 0.2,
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
                .roundness = 0.2,
            },
            .textStyle = .{
                .font = .ROBOTO_REGULAR,
                .fontSize = 14,
                .spacing = 0,
                .textColor = .white,
            },
        },
        .disabled = .{
            .bgStyle = .{
                .borderStyle = .{},
                .color = Color.transparentDark,
                .roundness = 0.2,
            },
            .textStyle = .{
                .font = .ROBOTO_REGULAR,
                .fontSize = 14,
                .spacing = 0,
                .textColor = Color.lightGray,
            },
        },
    };

    fn asButtonStyles(self: ButtonVariant) ButtonStyles {
        return ButtonStyles{
            .normal = self.normal,
            .hover = self.hover,
            .active = self.active,
            .disabled = self.disabled,
        };
    }
};
