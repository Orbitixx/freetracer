const std = @import("std");
const rl = @import("raylib");

const UIFramework = @import("../ui/import/index.zig");
const Transform = @import("./Transform.zig");
const TextPrimitive = UIFramework.Text;
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

const TextConfig = struct {
    fontResource: FontResource = .ROBOTO_REGULAR,
    fontSize: f32 = 14,
    textColor: rl.Color = Color.white,
    textValue: []const u8,
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

state: ButtonState = .NORMAL,
transform: Transform,
texture: Texture,
textureTint: rl.Color = Color.white,
textBuffer: [TILED_BUTTON_MAX_TEXT_LENGTH]u8,
textConfig: TextConfig,
clickHandler: ButtonHandler,
cursorActive: bool = false,

pub fn init(textConfig: TextConfig, texture: TextureResource, transform: Transform, clickHandler: ButtonHandler) SpriteButton {
    var buff = std.mem.zeroes([TILED_BUTTON_MAX_TEXT_LENGTH]u8);

    @memcpy(
        buff[0..if (textConfig.textValue.len > TILED_BUTTON_MAX_TEXT_LENGTH) TILED_BUTTON_MAX_TEXT_LENGTH],
        if (textConfig.textValue.value.len > TILED_BUTTON_MAX_TEXT_LENGTH) textConfig.textValue[0..TILED_BUTTON_MAX_TEXT_LENGTH] else textConfig.textValue,
    );

    return .{
        .textBuffer = buff,
        .textConfig = textConfig,
        .texture = ResourceManager.getTexture(texture),
        .transform = transform,
        .clickHandler = clickHandler,
    };
}

pub fn start(self: *SpriteButton) !void {
    self.transform.resolve();

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
    self.transform.resolve();

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

pub fn draw(self: *SpriteButton) !void {
    self.texture.drawEx(
        self.transform.positionAsVector2(),
        0,
        self.transform.scale,
        self.textureTint,
    );

    rl.drawTextEx(
        self.font,
        @ptrCast(std.mem.sliceTo(&self.textBuffer, 0x00)),
        self.transform.positionAsVector2(),
        self.style.fontSize,
        self.style.spacing,
        self.style.textColor,
    );
}

pub fn deinit(self: *SpriteButton) void {
    _ = self;
}
