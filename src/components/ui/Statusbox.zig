const std = @import("std");
const rl = @import("raylib");

const ComponentFramework = @import("../framework/import/index.zig");
const Component = ComponentFramework.Component;

const Primitives = @import("Primitives.zig");
const Text = Primitives.Text;
const Rectangle = Primitives.Rectangle;
const Transform = Primitives.Transform;

const Styles = @import("./Styles.zig");
const StatusboxStyle = Styles.StatusboxStyle;
const StatusboxStyles = Styles.StatusboxStyles;

const Color = Styles.Color;

const ResourceManager = @import("../../managers/ResourceManager.zig");
const Font = ResourceManager.FONT;
const getTexture = ResourceManager.ResourceManagerSingleton.getTexture;

pub const StatusboxState = enum {
    NONE,
    SUCCESS,
    FAILURE,
};

pub const CheckboxHandler = struct {
    function: *const fn (ctx: *anyopaque) void,
    context: *anyopaque,

    fn handle(self: CheckboxHandler) void {
        return self.function(self.context);
    }
};

const Statusbox = @This();

// Component-agnostic props
component: ?Component = null,

// Component-specific, unique props
transform: Transform,
outerRect: Rectangle,
innerRect: Rectangle,
state: StatusboxState = .NONE,
styles: StatusboxVariant,
texture: ?ResourceManager.Texture = null,
textureOffsetX: f32 = 0,
textureOffsetY: f32 = 0,
textureSize: f32,
textureTileSize: f32 = 16,

pub fn init(position: rl.Vector2, size: f32, variant: StatusboxVariant) Statusbox {
    const outerRect = Rectangle{
        .transform = .{
            .x = position.x,
            .y = position.y,
            .w = size,
            .h = size,
        },
        .bordered = true,
        .rounded = true,
    };

    const innerRect = Rectangle{
        .transform = .{
            .x = position.x + size / 4,
            .y = position.y + size / 4,
            .w = size - size / 2,
            .h = size - size / 2,
        },
        .rounded = true,
    };

    return .{
        .transform = .{
            .x = position.x,
            .y = position.y,
            .w = outerRect.transform.w,
            .h = size,
        },
        .state = .NONE,
        .outerRect = outerRect,
        .innerRect = innerRect,
        .styles = variant,
        .texture = getTexture(.BUTTON_UI),
        .textureSize = size,
    };
}

pub fn setPosition(self: *Statusbox, position: rl.Vector2) void {
    self.transform.x = position.x;
    self.transform.y = position.y;
    self.outerRect.transform.x = position.x;
    self.outerRect.transform.y = position.y;
    self.innerRect.transform.x = position.x + self.transform.h / 4;
    self.innerRect.transform.y = position.y + self.transform.h / 4;
}

pub fn start(self: *Statusbox) !void {
    self.outerRect.style = self.styles.none.outerRectStyle;
    self.innerRect.style = self.styles.none.innerRectStyle;
}

pub fn initComponent(self: *Statusbox, parent: ?*Component) !void {
    if (self.component != null) return error.CheckboxBaseComponentAlreadyInitialized;
    self.component = try Component.init(self, &ComponentImplementation.vtable, parent);
}

pub fn switchState(self: *Statusbox, newState: StatusboxState) void {
    switch (newState) {
        .NONE => {
            self.outerRect.style = self.styles.none.outerRectStyle;
            self.innerRect.style = self.styles.none.innerRectStyle;

            if (self.texture) |_| {
                self.textureOffsetX = self.textureTileSize * 6;
                self.textureOffsetY = self.textureTileSize * 9;
            }
        },
        .SUCCESS => {
            self.outerRect.style = self.styles.success.outerRectStyle;
            self.innerRect.style = self.styles.success.innerRectStyle;

            if (self.texture) |_| {
                self.textureOffsetX = self.textureTileSize * 5;
                self.textureOffsetY = self.textureTileSize * 1;
            }
        },
        .FAILURE => {
            self.outerRect.style = self.styles.failure.outerRectStyle;
            self.innerRect.style = self.styles.failure.innerRectStyle;

            if (self.texture) |_| {
                self.textureOffsetX = self.textureTileSize * 4;
                self.textureOffsetY = self.textureTileSize * 4;
            }
        },
    }
}

pub fn update(self: *Statusbox) !void {
    _ = self;
}

pub fn draw(self: *Statusbox) !void {
    self.outerRect.draw();
    // self.innerRect.draw();

    if (self.texture) |texture| {
        rl.drawTexturePro(
            texture,
            .{ .x = 0 + self.textureOffsetX, .y = 0 + self.textureOffsetY, .width = self.textureTileSize, .height = self.textureTileSize },
            .{ .x = self.transform.x, .y = self.transform.y, .width = self.textureSize, .height = self.textureSize },
            .{ .x = 0, .y = 0 },
            0,
            .white,
        );
    }
}

pub fn handleEvent(self: *Statusbox, event: ComponentFramework.Event) !ComponentFramework.EventResult {
    _ = self;
    _ = event;

    return .{
        .success = true,
        .validation = 1,
    };
}

pub fn deinit(self: *Statusbox) void {
    _ = self;
}

pub fn dispatchComponentAction(self: *Statusbox) void {
    _ = self;
}

pub const ComponentImplementation = ComponentFramework.ImplementComponent(Statusbox);
pub const asComponent = ComponentImplementation.asComponent;
pub const asComponentPtr = ComponentImplementation.asComponentPtr;
pub const asInstance = ComponentImplementation.asInstance;

pub const StatusboxVariant = struct {
    none: StatusboxStyle = .{},
    success: StatusboxStyle = .{},
    failure: StatusboxStyle = .{},

    pub const Primary: StatusboxVariant = .{
        .none = .{
            .outerRectStyle = .{
                .color = Color.transparent,
                .borderStyle = .{
                    .color = Color.white,
                    .thickness = 1.5,
                },
            },
            .innerRectStyle = .{
                .color = Color.transparent,
                .borderStyle = .{},
            },
        },

        .success = .{
            .outerRectStyle = .{
                .color = Color.transparent,
                .borderStyle = .{
                    .color = Color.green,
                    .thickness = 1.5,
                },
            },
            .innerRectStyle = .{
                .color = Color.green,
                .borderStyle = .{},
            },
        },

        .failure = .{
            .outerRectStyle = .{
                .color = Color.transparent,
                .borderStyle = .{
                    .color = Color.red,
                    .thickness = 1.5,
                },
            },
            .innerRectStyle = .{
                .color = Color.red,
                .borderStyle = .{
                    .color = Color.red,
                },
            },
        },
    };
};
