const std = @import("std");
const rl = @import("raylib");

const UIFramework = @import("../ui/import/index.zig");
const Transform = UIFramework.Transform;
const Text = UIFramework.Text;
const Color = @import("./Styles.zig").Color;

const ResourceImport = @import("../../managers/ResourceManager.zig");
const ResourceManager = ResourceImport.ResourceManagerSingleton;

const Texture = ResourceImport.Texture;
const Font = rl.Font;
const FontResource = ResourceImport.FONT;
const TextureResource = ResourceImport.TextureResource;

const SpriteButton = @This();
const TILED_BUTTON_MAX_TEXT_LENGTH = 36;

pub const ButtonState = enum {
    NORMAL,
    HOVER,
    ACTIVE,
    DISABLED,
};

const StateStyle = struct {
    textureColor: rl.Color,
    textColor: rl.Color,
};

const SpriteButtonInteractiveStyle = struct {
    pub const Active: StateStyle = .{ .textColor = Color.themeTertiary, .textureColor = Color.themeTertiary };
    pub const Hover: StateStyle = .{ .textColor = Color.themeSecondary, .textureColor = Color.themeSecondary };
    pub const Normal: StateStyle = .{ .textColor = Color.themePrimary, .textureColor = Color.themePrimary };
    pub const Disabled: StateStyle = .{ .textColor = Color.offWhite, .textureColor = Color.transparentDark };
};

pub const ButtonHandler = struct {
    function: *const fn (ctx: *anyopaque) void,
    context: *anyopaque,

    fn handle(self: ButtonHandler) void {
        return self.function(self.context);
    }
};

textBuffer: [TILED_BUTTON_MAX_TEXT_LENGTH]u8,
texture: Texture,
text: Text,
transform: Transform,
state: ButtonState = .NORMAL,
clickHandler: ButtonHandler,
cursorActive: bool = false,
textureTint: rl.Color = Color.white,

pub fn init(
    value: []const u8,
    font: FontResource,
    fontSize: f32,
    color: rl.Color,
    texture: TextureResource,
    transform: Transform,
    clickHandler: ButtonHandler,
) !SpriteButton {
    if (value.len > TILED_BUTTON_MAX_TEXT_LENGTH) return error.SpriteButtonValueExceedsMax;

    var buff = std.mem.zeroes([TILED_BUTTON_MAX_TEXT_LENGTH]u8);
    @memcpy(buff[0..value.len], value);

    const text = Text.init(
        "",
        .{ .x = 0, .y = 0 },
        .{
            .font = font,
            .fontSize = fontSize,
            .textColor = color,
        },
    );

    return .{
        .textBuffer = buff,
        .text = text,
        .texture = ResourceManager.getTexture(texture),
        .transform = transform,
        .clickHandler = clickHandler,
    };
}

pub fn start(self: *SpriteButton) void {
    self.text.value = @ptrCast(std.mem.sliceTo(&self.textBuffer, 0x00));

    self.transform.w = @floatFromInt(self.texture.width);
    self.transform.h = @floatFromInt(self.texture.height);

    const textDims = self.text.getDimensions();
    self.text.transform.x = self.transform.x + @as(f32, @floatFromInt(@divFloor(self.texture.width, 2))) - @divFloor(textDims.width, 2);
    self.text.transform.y = self.transform.y + @as(f32, @floatFromInt(@divFloor(self.texture.height, 2))) - @divFloor(textDims.height, 2);
    self.text.transform.w = textDims.width;
    self.text.transform.h = textDims.height;
}

pub fn update(self: *SpriteButton) !void {
    const mousePos: rl.Vector2 = rl.getMousePosition();
    const isButtonHovered: bool = self.transform.isPointWithinBounds(mousePos);
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
        // if (self.params.disableOnClick) self.setEnabled(false);
        self.clickHandler.handle();
    } else if (isButtonHovered) {
        self.state = ButtonState.HOVER;
    } else {
        self.state = ButtonState.NORMAL;
    }

    switch (self.state) {
        .HOVER => {
            self.text.style.textColor = SpriteButtonInteractiveStyle.Hover.textColor;
            self.textureTint = SpriteButtonInteractiveStyle.Hover.textureColor;
        },
        .ACTIVE => {
            self.text.style.textColor = SpriteButtonInteractiveStyle.Active.textColor;
            self.textureTint = SpriteButtonInteractiveStyle.Active.textureColor;
        },
        .NORMAL => {
            self.text.style.textColor = SpriteButtonInteractiveStyle.Normal.textColor;
            self.textureTint = SpriteButtonInteractiveStyle.Normal.textureColor;
        },
        .DISABLED => {
            self.text.style.textColor = SpriteButtonInteractiveStyle.Disabled.textColor;
            self.textureTint = SpriteButtonInteractiveStyle.Disabled.textureColor;
        },
    }
}

pub fn draw(self: *SpriteButton) void {
    self.texture.drawEx(
        .{ .x = self.transform.x, .y = self.transform.y },
        0,
        self.transform.scale,
        self.textureTint,
    );

    self.text.draw();
}
