const std = @import("std");
const rl = @import("raylib");
const _ResourceManager = @import("../../managers/ResourceManager.zig");
const ResourceManager = _ResourceManager.ResourceManagerSingleton;
const Font = _ResourceManager.FONT;

pub const Window = struct {
    width: i32,
    height: i32,
};

pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    color: rl.Color,

    pub fn draw(self: @This()) void {
        rl.drawRectangleRounded(.{ .x = self.x, .y = self.y, .width = self.width, .height = self.height }, 0.2, 6, self.color);
    }
};

pub const Text = struct {
    x: f32,
    y: f32,
    padding: rl.Rectangle = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    value: [:0]const u8,
    fontSize: f32,
    color: rl.Color,

    pub fn getWidth(self: Text) f32 {
        // TODO: Fix casts by using measureTextEx
        return @floatFromInt(rl.measureText(self.value, @as(i32, @intFromFloat(self.fontSize))));
    }

    pub fn draw(self: Text) void {
        rl.drawTextEx(
            ResourceManager.getFont(Font.ROBOTO_REGULAR),
            self.value,
            .{ .x = self.x, .y = self.y },
            self.fontSize,
            0,
            self.color,
        );
    }
};

const BUTTON_PADDING: f32 = 16;

pub const ButtonState = enum {
    NORMAL,
    HOVER,
    ACTIVE,
};

pub const ButtonColorVariant = struct {
    rect: rl.Color,
    text: rl.Color,
};

pub const ButtonColorVariants = struct {
    normal: ButtonColorVariant,
    hover: ButtonColorVariant,
    active: ButtonColorVariant,
};

pub fn Button() type {
    return struct {
        const Self = @This();

        rect: Rect,
        text: Text,
        state: ButtonState = ButtonState.NORMAL,
        variants: ButtonColorVariants,

        pub fn init(text: [:0]const u8, x: f32, y: f32, fontSize: f32, variants: ButtonColorVariants) Self {
            // TODO: Fix casts by using measureTextEx
            const width: i32 = rl.measureText(text, @as(i32, @intFromFloat(fontSize)));

            return .{
                .rect = .{
                    .x = x,
                    .y = y,
                    .width = @as(f32, @floatFromInt(width)) + BUTTON_PADDING * 2,
                    .height = fontSize + BUTTON_PADDING,
                    .color = .white,
                },

                .text = .{
                    .value = text,
                    .x = x + BUTTON_PADDING,
                    .y = y + BUTTON_PADDING / 2,
                    .fontSize = fontSize,
                    .color = .black,
                },

                .variants = variants,
            };
        }

        pub fn draw(self: Self) void {
            self.rect.draw();
            self.text.draw();
        }

        pub fn events(self: *Self) void {
            const mousePos: rl.Vector2 = rl.getMousePosition();
            const isButtonClicked: bool = rl.isMouseButtonPressed(.left);
            const isButtonHovered: bool = rl.checkCollisionPointRec(mousePos, .{
                .x = self.rect.x,
                .y = self.rect.y,
                .width = self.rect.width,
                .height = self.rect.height,
            });

            if (isButtonHovered and isButtonClicked) {
                self.state = ButtonState.ACTIVE;
            } else if (isButtonHovered) {
                self.state = ButtonState.HOVER;
            } else {
                self.state = ButtonState.NORMAL;
            }

            switch (self.state) {
                .HOVER => {
                    self.rect.color = self.variants.hover.rect;
                    self.text.color = self.variants.hover.text;
                },
                .ACTIVE => {
                    self.rect.color = self.variants.active.rect;
                    self.text.color = self.variants.active.text;
                },
                .NORMAL => {
                    self.rect.color = self.variants.normal.rect;
                    self.text.color = self.variants.normal.text;
                },
            }
        }

        pub fn setPosition(self: *Self, x: f32, y: f32) void {
            self.rect.x = x;
            self.rect.y = y;

            self.text.x = x + BUTTON_PADDING;
            self.text.y = y + BUTTON_PADDING / 2;
        }
    };
}
